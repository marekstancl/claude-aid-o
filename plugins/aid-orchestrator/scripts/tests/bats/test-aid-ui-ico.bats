#!/usr/bin/env bats
# aid-tier: t0
# P102 Step 5 — aid-ui-ico.py packs favicon.ico and checks the icon package of /aid-ui step 1i.

setup() {
  ICO="$BATS_TEST_DIRNAME/../../aid-ui-ico.py"
  FX="$BATS_TEST_DIRNAME/../fixtures/aid-ui/icons"
  T="$BATS_TEST_TMPDIR"
}

# hdr <side> <file> — a PNG signature + IHDR only; --verify reads nothing further.
hdr() {
  python3 -c 'import struct,sys; n=int(sys.argv[1]); sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n"+struct.pack(">I",13)+b"IHDR"+struct.pack(">II",n,n))' "$1" > "$2"
}

complete_set() {
  cp "$FX"/favicon-16.png "$FX"/favicon-32.png "$FX"/favicon-48.png "$T/"
  hdr 180 "$T/apple-touch-icon.png"; hdr 192 "$T/icon-192.png"
  hdr 512 "$T/icon-512.png"; hdr 512 "$T/icon-maskable-512.png"
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"/>' > "$T/favicon.svg"
  python3 "$ICO" "$T/favicon.ico" "$T"/favicon-16.png "$T"/favicon-32.png "$T"/favicon-48.png
}

@test "three PNG fixtures -> an ICO with 3 entries of 16/32/48" {
  run python3 "$ICO" "$T/f.ico" "$FX/favicon-16.png" "$FX/favicon-32.png" "$FX/favicon-48.png"
  [ "$status" -eq 0 ]
  run python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(); r,t,n=struct.unpack("<HHH",d[:6]); print(r,t,n,*[d[6+16*i] for i in range(n)])' "$T/f.ico"
  [ "$output" = "0 1 3 16 32 48" ]
}

@test "a non-PNG is refused with exit 1" {
  echo 'not a png' > "$T/x.png"
  run python3 "$ICO" "$T/f.ico" "$T/x.png"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a PNG"* ]]
  [ ! -e "$T/f.ico" ]
}

@test "a PNG above 256 px is refused with exit 1" {
  hdr 512 "$T/big.png"
  run python3 "$ICO" "$T/f.ico" "$T/big.png"
  [ "$status" -eq 1 ]
}

@test "--verify on a complete set -> exit 0" {
  complete_set
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" != *WRONG* ]]
}

@test "--verify with the wrong-sized file -> exit 1 naming it" {
  complete_set
  cp "$FX/wrong-size-100.png" "$T/apple-touch-icon.png"
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WRONG   apple-touch-icon.png expected 180x180, got 100x100"* ]]
}

@test "--verify names a missing file" {
  complete_set
  rm "$T/icon-maskable-512.png"
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"icon-maskable-512.png expected 512x512, got missing"* ]]
}

@test "--verify refuses an unsafe or non-square favicon.svg, one WRONG line each" {
  complete_set
  S='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 32 32">'
  for body in '<script>alert(1)</script>' '<foreignObject><p>x</p></foreignObject>' '<iframe src="x"/>' \
      '<rect width="1" height="1" onload="alert(1)"/>' '<a href="javascript:alert(1)"><rect/></a>' \
      '<use xlink:href="https://evil.example/s.svg#a"/>'; do
    printf '%s%s</svg>\n' "$S" "$body" > "$T/favicon.svg"
    run python3 "$ICO" --verify "$T"
    [ "$status" -eq 1 ] || { echo "passed: $body"; return 1; }
    [ "$(grep -c '^WRONG   favicon.svg ' <<<"$output")" -eq 1 ]
  done
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 24"><use href="#a"/></svg>' > "$T/favicon.svg"
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WRONG   favicon.svg viewBox 0 0 32 24 is not square"* ]]
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><use href="#a"/></svg>' > "$T/favicon.svg"
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 0 ]
}

@test "--verify allowlist: animation, <a>, <style>, style and remote url() refused; gradient + use accepted" {
  complete_set
  S='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 32 32">'
  for body in '<a><animate attributeName="href" values="javascript:alert(1)"/><rect width="32" height="32"/></a>' \
      '<a><set attributeName="href" to="javascript:alert(1)"/><rect width="32" height="32"/></a>' \
      '<a><animate attributeName="xlink:href" values="javascript:alert(1)"/><rect width="32" height="32"/></a>' \
      '<style>@import url(https://evil.example/x.css);</style><rect width="32" height="32"/>' \
      '<rect width="32" height="32" style="fill:url(https://evil.example/p.svg#g)"/>' \
      '<rect width="32" height="32" fill="url(https://evil.example/p.svg#g)"/>' \
      '<rect width="32" height="32" fill="u\72l(https://evil.example/p.svg#g)"/>' \
      '<text>A</text>' '<metadata><script>alert(1)</script></metadata>'; do
    printf '%s%s</svg>\n' "$S" "$body" > "$T/favicon.svg"
    run python3 "$ICO" --verify "$T"
    [ "$status" -eq 1 ] || { echo "passed: $body"; return 1; }
    [ "$(grep -c '^WRONG   favicon.svg ' <<<"$output")" -eq 1 ]
  done
  cat > "$T/favicon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" version="1.1">
  <title>Logo</title>
  <defs>
    <linearGradient id="grad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0a5"/><stop offset="1" stop-color="#05a" stop-opacity=".8"/>
    </linearGradient>
    <path id="x" d="M4 4h24v24H4z"/>
  </defs>
  <use href="#x" fill="url(#grad)"/>
  <circle cx="16" cy="16" r="6" fill="#fff" stroke="#000" stroke-width="1.5"/>
</svg>
SVG
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# run_icons <symbol> <out> — runs references/brand-icons.js under node with a stub page
# whose screenshot() writes an empty file, the paths filled in the way 1i step 6 says.
run_icons() {
  command -v node >/dev/null || skip "node not installed"
  sed -e "s|__ABSOLUTE_SYMBOL_SVG__|$1|" -e "s|__ABSOLUTE_ICONS_DIR__|$2|" \
    "$BATS_TEST_DIRNAME/../../../skills/ui-design/references/brand-icons.js" > "$T/brand-icons.js"
  run node -e '
    const fs = require("fs");
    const fn = eval(fs.readFileSync(process.argv[1], "utf8"));
    const page = { setViewportSize: async () => {}, goto: async () => {},
      locator: () => ({ screenshot: async (o) => fs.writeFileSync(o.path, "") }) };
    fn(page).then((w) => console.log(w.join(" ")), (e) => { console.log(e.message); process.exit(1); });
  ' "$T/brand-icons.js"
}

@test "brand-icons.js reads the SVG as data: backticks and \${} in it never run" {
  mkdir -p "$T/icons"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><desc>`${require("fs").writeFileSync("%s/pwned","x")}`</desc><rect/></svg>' "$T" > "$T/symbol.svg"
  run_icons "$T/symbol.svg" "$T/icons"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$T/pwned" ]
  [[ "$output" == *"icon-maskable-512.png favicon.svg"* ]]
  cmp "$T/symbol.svg" "$T/icons/favicon.svg"
  ! grep -q '<svg' "$T/brand-icons.js"
}

@test "brand-icons.js refuses a path that is not plain absolute and a non-square viewBox" {
  mkdir -p "$T/icons"
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"/>' > "$T/symbol.svg"
  run_icons "relative/symbol.svg" "$T/icons"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused: not a plain absolute path"* ]]
  run_icons "$T/symbol.svg" "$T/icons/../icons"
  [ "$status" -eq 1 ]
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 24"/>' > "$T/symbol.svg"
  run_icons "$T/symbol.svg" "$T/icons"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not square"* ]]
}
