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

@test "--verify refuses what the tree never shows: PI, DOCTYPE/ATTLIST, image-set; and caps size and depth" {
  complete_set
  S='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'; R='<rect width="32" height="32"/>'
  for doc in \
    "<?xml version=\"1.0\"?><?xml-stylesheet type=\"text/xsl\" href=\"https://evil.example/x.xsl\"?>$S$R</svg>" \
    "<?xml version=\"1.0\" standalone=\"no\"?><!DOCTYPE svg [<!ENTITY % p SYSTEM \"p.dtd\">%p;<!ATTLIST svg onload CDATA \"alert(document.domain)\">]>$S$R</svg>" \
    "<?xml version=\"1.0\"?><?xml-stylesheet type=\"text/css\" href=\"https://evil.example/x.css\"?>$S$R</svg>" \
    "$S<rect width=\"32\" height=\"32\" mask=\"image-set('https://evil.example/t.png' 1x)\"/></svg>" \
    "$S<rect width=\"32\" height=\"32\" mask=\"-webkit-image-set('https://evil.example/t.png' 1x)\"/></svg>" \
    "$S<g transform=\"translate(1 1) image-set('https://evil.example/t.png')\">$R</g></svg>"; do
    printf '%s\n' "$doc" > "$T/favicon.svg"
    run python3 "$ICO" --verify "$T"
    [ "$status" -eq 1 ] || { echo "passed: $doc"; return 1; }
    [ "$(grep -c '^WRONG   favicon.svg ' <<<"$output")" -eq 1 ]
  done
  python3 -c 'import sys; print(sys.argv[1] + "<g>" * 64 + "</g>" * 64 + "</svg>")' "$S" > "$T/favicon.svg"
  run python3 "$ICO" --verify "$T"
  [[ "$output" == *"WRONG   favicon.svg nested deeper than 64 elements"* ]]
  python3 -c 'import sys; print(sys.argv[1] + "<path d=\"" + "M0 0" * 140000 + "\"/></svg>")' "$S" > "$T/favicon.svg"
  run python3 "$ICO" --verify "$T"
  [[ "$output" == *"WRONG   favicon.svg larger than 512 KB"* ]]
  printf '\xef\xbb\xbf<?xml version="1.0" encoding="UTF-8"?>\n%s<g transform="translate(2,2) scale(.5) rotate(45 16 16)">%s</g></svg>\n' "$S" "$R" > "$T/favicon.svg"
  run python3 "$ICO" --verify "$T"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "--check-svg refuses script, onload and the DOCTYPE/ATTLIST case, writes nothing; passes a clean SVG" {
  S='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'; R='<rect width="32" height="32"/>'
  for doc in "$S<script>alert(1)</script>$R</svg>" \
    "$S<rect width=\"32\" height=\"32\" onload=\"alert(1)\"/></svg>" \
    "<?xml version=\"1.0\" standalone=\"no\"?><!DOCTYPE svg [<!ENTITY % p SYSTEM \"p.dtd\">%p;<!ATTLIST svg onload CDATA \"alert(document.domain)\">]>$S$R</svg>"; do
    printf '%s\n' "$doc" > "$T/bad.svg"
    run python3 "$ICO" --check-svg "$T/bad.svg" "$T/bad.checked.svg"
    [ "$status" -eq 1 ] || { echo "passed: $doc"; return 1; }
    [[ "$output" == "WRONG   $T/bad.svg "* ]]
    [ -z "$(ls "$T" | grep -v '^bad.svg$')" ]   # no .checked.svg, no .tmp left
  done
  printf '%s%s</svg>\n' "$S" "$R" > "$T/ok.svg"
  run python3 "$ICO" --check-svg "$T/ok.svg" "$T/ok.checked.svg"
  [ "$status" -eq 0 ]
  cmp "$T/ok.svg" "$T/ok.checked.svg"
  run python3 "$ICO" --check-svg "$T/ok.svg" "$T/ok.svg.out"   # output name must end in .checked.svg
  [ "$status" -eq 2 ]; [ ! -e "$T/ok.svg.out" ]
}

# run_icons <symbol> <out> — runs references/brand-icons.js in a node vm whose only global
# is a stub page (no require, process or import, as in the Playwright MCP sandbox): goto
# file:// reads the file and prints "GOTO <url>", screenshot() writes a PNG header of the
# viewport size.
run_icons() {
  command -v node >/dev/null || skip "node not installed"
  sed -e "s|__ABSOLUTE_SYMBOL_SVG__|$1|" -e "s|__ABSOLUTE_ICONS_DIR__|$2|" \
    "$BATS_TEST_DIRNAME/../../../skills/ui-design/references/brand-icons.js" > "$T/brand-icons.js"
  run node -e '
    const fs = require("fs"), vm = require("vm");
    let doc = "", vp = null;
    const png = (n) => { const b = Buffer.alloc(24); Buffer.from("89504e470d0a1a0a0000000d49484452", "hex").copy(b); b.writeUInt32BE(n.width, 16); b.writeUInt32BE(n.height, 20); return b; };
    const page = {
      goto: async (u) => { console.log("GOTO " + u); doc = u.startsWith("file://") ? fs.readFileSync(u.slice(7), "utf8") : ""; },
      evaluate: async () => doc,
      setViewportSize: async (v) => { vp = v; },
      setContent: async () => {},
      screenshot: async (o) => fs.writeFileSync(o.path, png(vp)),
    };
    const fn = vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8"), { page });
    fn(page).then((w) => console.log(w), (e) => { console.log(e.message); process.exit(1); });
  ' "$T/brand-icons.js"
}

@test "brand-icons.js uses no Node API (the MCP sandbox has none)" {
  F="$BATS_TEST_DIRNAME/../../../skills/ui-design/references/brand-icons.js"
  ! grep -nE 'require\(|import\(|process\.' "$F"
}

@test "brand-icons.js reads the SVG as data: backticks and \${} in it never run" {
  mkdir -p "$T/icons"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><desc>`${page.screenshot({path:"%s/pwned"})}`</desc><rect/></svg>' "$T" > "$T/symbol.svg"
  python3 "$ICO" --check-svg "$T/symbol.svg" "$T/symbol.checked.svg"
  run_icons "$T/symbol.checked.svg" "$T/icons"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$T/pwned" ]
  [[ "$output" == *"icon-maskable-512.png"* ]]
  ! grep -q '<svg' "$T/brand-icons.js"
  cp "$T/symbol.checked.svg" "$T/icons/favicon.svg"
  python3 "$ICO" "$T/icons/favicon.ico" "$T"/icons/favicon-{16,32,48}.png
  run python3 "$ICO" --verify "$T/icons"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "brand-icons.js refuses an SVG that did not pass --check-svg before opening anything" {
  mkdir -p "$T/icons"
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" onload="alert(1)"/>' > "$T/symbol.svg"
  run_icons "$T/symbol.svg" "$T/icons"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused: not a .checked.svg"* ]]
  [[ "$output" != *GOTO* ]]
  run python3 "$ICO" --check-svg "$T/symbol.svg" "$T/symbol.checked.svg"
  [ "$status" -eq 1 ]; [ ! -e "$T/symbol.checked.svg" ]
}

@test "brand-icons.js refuses a path that is not plain absolute and a non-square viewBox" {
  mkdir -p "$T/icons"
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"/>' > "$T/symbol.checked.svg"
  run_icons "relative/symbol.checked.svg" "$T/icons"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refused: not a plain absolute path"* ]]
  run_icons "$T/symbol.checked.svg" "$T/icons/../icons"
  [ "$status" -eq 1 ]
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 24"/>' > "$T/symbol.checked.svg"
  run_icons "$T/symbol.checked.svg" "$T/icons"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not square"* ]]
}
