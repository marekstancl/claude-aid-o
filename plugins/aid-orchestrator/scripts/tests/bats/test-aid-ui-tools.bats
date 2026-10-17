#!/usr/bin/env bats
# aid-tier: t2
# P103 Step 5 — aid-ui-tool.sh: the glyph check sees a system-font fallback for ř,
# the WebP tool keeps the size limit, and node_modules is installed until a marker
# matching the lockfile proves a finished npm ci.

setup() {
  PLUG="$BATS_TEST_DIRNAME/../../.."
  TOOL="$PLUG/scripts/aid-ui-tool.sh"
  PNG="$BATS_TEST_DIRNAME/../fixtures/aid-ui/icons/favicon-48.png"
  T="$BATS_TEST_TMPDIR"
  command -v node >/dev/null || skip "node missing"
  ls -d "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome >/dev/null 2>&1 \
    || [[ -n "${CHROME:-}" ]] || skip "no Chromium in ~/.cache/ms-playwright and no \$CHROME"
}

teardown() { [[ -n "${SRV:-}" ]] && kill "$SRV" 2>/dev/null || true; }

# serve <dir> — a local HTTP server on a free port; sets PORT and SRV
serve() {
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$1" >/dev/null 2>&1 &
  SRV=$!
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && return 0; sleep 0.1; done
  return 1
}

# page <font file> <name> — a page whose only web font is <font file>
page() {
  cp "$1" "$T/site/"
  printf '<!doctype html><meta charset=utf-8><style>@font-face{font-family:T;src:url(%s)}p{font-family:T,serif}</style><p>Příliš žluťoučký kůň řeže</p>' \
    "$(basename "$1")" > "$T/site/$2.html"
}

@test "glyph flags a font without ř and passes one with it; HTTP 404 is a blocker" {
  lacks=/usr/share/fonts/opentype/tlwg/Loma.otf          # Latin, no U+0159
  has=/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf
  [[ -f "$lacks" && -f "$has" ]] || skip "fonts-tlwg-loma or fonts-liberation missing"
  mkdir -p "$T/site"; page "$lacks" bad; page "$has" good
  serve "$T/site"
  run "$TOOL" glyph "http://127.0.0.1:$PORT/bad.html"
  [ "$status" -eq 1 ]; [[ "$output" == *BLOCKER*Příliš* ]]
  run "$TOOL" glyph "http://127.0.0.1:$PORT/good.html"
  [ "$status" -eq 0 ]; [[ "$output" == *'OK no fallback'* ]]
  run "$TOOL" glyph "http://127.0.0.1:$PORT/missing.html"
  [ "$status" -eq 1 ]; [[ "$output" == *'HTTP 404'* ]]
}

@test "webp writes a WebP under the requested size and refuses one over it" {
  run "$TOOL" webp --max-kb 20 "$PNG" "$T/o.webp" 400 0.8
  [ "$status" -eq 0 ]
  [ "$(head -c 12 "$T/o.webp" | tail -c 4)" = WEBP ]
  (( $(stat -c %s "$T/o.webp") <= 20 * 1024 ))
  run "$TOOL" webp --max-kb 0 "$PNG" "$T/o2.webp" 400
  [ "$status" -eq 1 ]; [[ "$output" == *'over 0 kB'* ]]
}

@test "a missing node_modules is installed on the first call" {
  mkdir -p "$T/p/scripts" "$T/p/lib/ui-fidelity"
  cp "$TOOL" "$T/p/scripts/"
  cp "$PLUG"/lib/ui-fidelity/{package.json,package-lock.json,aid-ui-webp.mjs} "$T/p/lib/ui-fidelity/"
  run "$T/p/scripts/aid-ui-tool.sh" webp "$PNG" "$T/o3.webp" 100
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -d "$T/p/lib/ui-fidelity/node_modules/@playwright/test" ]
  [[ "$output" == *'npm ci'* ]]
}

# stub_lib — a copy of the tool whose npm is a stub on PATH; NPM_FAIL=1 makes npm ci fail
# after leaving a partial node_modules; every npm call is logged to $T/npm.log
stub_lib() {
  mkdir -p "$T/s/scripts" "$T/s/lib/ui-fidelity" "$T/bin"
  cp "$TOOL" "$T/s/scripts/"
  echo '{"lockfileVersion":3}' > "$T/s/lib/ui-fidelity/package-lock.json"
  echo 'process.exit(0)' > "$T/s/lib/ui-fidelity/aid-ui-glyph-check.mjs"
  cat > "$T/bin/npm" <<STUB
#!/usr/bin/env bash
echo "npm \$*" >> "$T/npm.log"
mkdir -p node_modules/partial
[[ "\${NPM_FAIL:-}" == 1 ]] && exit 1
exit 0
STUB
  chmod +x "$T/bin/npm"
}

@test "a failed npm ci leaves no marker and no node_modules; the next call reinstalls" {
  stub_lib
  NPM_FAIL=1 PATH="$T/bin:$PATH" run "$T/s/scripts/aid-ui-tool.sh" glyph x
  [ "$status" -eq 1 ]; [[ "$output" == *'npm ci failed'* ]]
  [ ! -e "$T/s/lib/ui-fidelity/node_modules" ]
  PATH="$T/bin:$PATH" run "$T/s/scripts/aid-ui-tool.sh" glyph x
  [ "$status" -eq 0 ]
  [ "$(cat "$T/s/lib/ui-fidelity/node_modules/.aid-installed")" = "$(sha256sum "$T/s/lib/ui-fidelity/package-lock.json" | cut -d' ' -f1)" ]
  [ "$(wc -l < "$T/npm.log")" -eq 2 ]
  PATH="$T/bin:$PATH" run "$T/s/scripts/aid-ui-tool.sh" glyph x      # marker matches: no install
  [ "$status" -eq 0 ]; [ "$(wc -l < "$T/npm.log")" -eq 2 ]
}

@test "a bare node_modules or a stale marker triggers a reinstall" {
  stub_lib
  mkdir -p "$T/s/lib/ui-fidelity/node_modules"                       # directory, no marker
  PATH="$T/bin:$PATH" run "$T/s/scripts/aid-ui-tool.sh" glyph x
  [ "$status" -eq 0 ]; [ "$(wc -l < "$T/npm.log")" -eq 1 ]
  echo '{"lockfileVersion":3,"changed":1}' > "$T/s/lib/ui-fidelity/package-lock.json"   # marker now stale
  PATH="$T/bin:$PATH" run "$T/s/scripts/aid-ui-tool.sh" glyph x
  [ "$status" -eq 0 ]; [ "$(wc -l < "$T/npm.log")" -eq 2 ]
  echo garbage > "$T/s/lib/ui-fidelity/node_modules/.aid-installed"
  PATH="$T/bin:$PATH" run "$T/s/scripts/aid-ui-tool.sh" glyph x
  [ "$status" -eq 0 ]; [ "$(wc -l < "$T/npm.log")" -eq 3 ]
}

@test "glyph --sample refuses a family outside the allowlist before any page is built" {
  for fam in "Roboto',monospace;background:url(http://x/)" 'A"B' 'url(x)' 'Rob;oto' "$(printf 'A%.0s' {1..65})" ''; do
    run "$TOOL" glyph --sample "$fam" "Příliš"
    [ "$status" -eq 2 ] || { echo "accepted: $fam"; return 1; }
    [[ "$output" == *'must match'* ]]
  done
}

@test "glyph --sample with a family that does not exist is a failure, not OK" {
  run "$TOOL" glyph --sample "Aid Nonexistent Family Zz" "Příliš žluťoučký"
  [ "$status" -eq 1 ]; [[ "$output" == *'FAIL Aid Nonexistent'* ]]
  [[ "$output" == *'no web font rendered'* ]]
}

@test "glyph on a page rendered by system fonts only, or with no text, is a failure" {
  mkdir -p "$T/site"
  printf '<!doctype html><meta charset=utf-8><p style="font-family:NoSuchWebFont,serif">Příliš</p>' > "$T/site/sys.html"
  printf '<!doctype html><meta charset=utf-8><div></div>' > "$T/site/empty.html"
  serve "$T/site"
  run "$TOOL" glyph "http://127.0.0.1:$PORT/sys.html"
  [ "$status" -eq 1 ]; [[ "$output" == *'no web font rendered'* ]]
  run "$TOOL" glyph "http://127.0.0.1:$PORT/empty.html"
  [ "$status" -eq 1 ]; [[ "$output" == *'no text element could be observed'* ]]
}

@test "unknown tool is a usage error" {
  run "$TOOL" nope
  [ "$status" -eq 2 ]
}

@test "wordmark: Czech name from split font files, accents and descenders inside the viewBox; outlines vs live text; png" {
  F="$BATS_TEST_DIRNAME/../fixtures/aid-ui/verify-site/site/fonts"
  B="$T/pkg"; mkdir -p "$B/symbol"
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0,0,32,32" fill="#c00"><rect width="32" height="32"/></svg>' >"$B/symbol/s-color.svg"
  cat >"$T/wm.json" <<J
{"package": "$B", "base": "x-logo", "name": "Žluťoučký gyp", "font": ["$F/geist-latin.woff2", "$F/geist-latin-ext.woff2"],
 "family": "Geist", "weight": 600, "licence": "SIL OFL 1.1 -- test", "variants": [{"id": "color", "symbol": "symbol/s-color.svg", "text": "#111"},
 {"id": "color-on-dark", "symbol": "symbol/s-color.svg", "text": "#eee"}]}
J
  run bash "$TOOL" wordmark --spec "$T/wm.json" --root /
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q '<text' "$B/source/x-logo-master.svg"
  grep -q 'licence SIL OFL 1.1 - test' "$B/source/x-logo-master.svg"   # "--" never inside an XML comment
  ! grep -q '<text' "$B/source/x-logo-master-outlines.svg"
  grep -q 'fill="#c00"' "$B/logo/x-logo-color.svg"    # the symbol keeps its root fill
  grep -q 'fill="#eee"' "$B/logo/x-logo-color-on-dark.svg"
  # the viewBox reaches above 0 (Ž) and below 64 (g, y, p)
  python3 - "$B/logo/x-logo-color.svg" <<'P'
import re, sys
x, y, w, h = map(float, re.search(r'viewBox="([^"]+)"', open(sys.argv[1]).read()).group(1).split())
assert y < 0 and y + h > 64, (y, h)
P
  run bash "$TOOL" png "$B/logo/x-logo-color.svg" "$T/x.png" 600
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); w,h=struct.unpack(">II",d[16:24]); assert w==600 and h>50, (w,h)' "$T/x.png"
}

@test "wordmark: a name no font file can set is exit 1; a bad spec (path in id, colour, broken JSON) is exit 2; a symbol with an ENTITY is refused" {
  F="$BATS_TEST_DIRNAME/../fixtures/aid-ui/verify-site/site/fonts"
  B="$T/pkg"; mkdir -p "$B/symbol"
  echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64"/></svg>' >"$B/symbol/s.svg"
  spec() { echo "{\"package\":\"$B\",\"base\":\"$1\",\"name\":\"$2\",\"font\":\"$F/geist-latin.woff2\",\"family\":\"Geist\",\"weight\":400,\"variants\":[{\"id\":\"color\",\"symbol\":\"symbol/s.svg\",\"text\":\"$3\"}]}" >"$T/wm.json"; }
  spec x '日本' '#000'; run bash "$TOOL" wordmark --spec "$T/wm.json" --root /
  [ "$status" -eq 1 ]; [[ "$output" == *"no font file has a glyph"* ]]
  spec ../x Ok '#000'; run bash "$TOOL" wordmark --spec "$T/wm.json" --root /
  [ "$status" -eq 2 ]
  spec x Ok 'red" onload="x'; run bash "$TOOL" wordmark --spec "$T/wm.json" --root /
  [ "$status" -eq 2 ]
  echo '{"name": 1}' >"$T/wm.json"; run bash "$TOOL" wordmark --spec "$T/wm.json"
  [ "$status" -eq 2 ]; [[ "$output" == *"bad spec"* ]]
  printf '<?xml version="1.0"?><!DOCTYPE s [<!ENTITY e "x">]><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">&e;</svg>' >"$B/symbol/s.svg"
  spec x Ok '#000'; run bash "$TOOL" wordmark --spec "$T/wm.json" --root /
  [ "$status" -eq 1 ]; [[ "$output" == *"DOCTYPE or ENTITY"* ]]
}

@test "png refuses an SVG without a viewBox" {
  echo '<svg xmlns="http://www.w3.org/2000/svg"><rect width="4" height="4"/></svg>' >"$T/n.svg"
  run bash "$TOOL" png "$T/n.svg" "$T/n.png" 100
  [ "$status" -eq 1 ]; [[ "$output" == *"no usable viewBox"* ]]
}

@test "measure: control roles grouped by colours with count and heights, fields, type and breakpoints; an off-screen skip link is no role" {
  D="$T/site"; mkdir -p "$D"
  cat >"$D/index.html" <<'H'
<!doctype html><html lang="cs"><head><style>
.btn{background:#1a1a1a;color:#fff;padding:12px 20px;border:0;border-radius:4px;display:inline-block;text-decoration:none;font:inherit}
.skip{position:absolute;top:-80px;background:#ff0;color:#000;padding:8px}
@media (max-width: 760px){h1{font-size:2rem}}
</style></head><body><a class="skip" href="#m">Přeskočit</a><main id="m"><h1>Pekárna</h1><p>Text.</p>
<a class="btn" href="/k">Objednat</a> <button class="btn">Poslat</button> <a href="/o">obyčejný odkaz</a>
<input type="email"></main></body></html>
H
  serve "$D"
  run bash "$TOOL" measure "http://127.0.0.1:$PORT/" "$T/m.json" index.html
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '(.controls | length) == 1 and .controls[0].count == 2 and .controls[0].background == "rgb(26, 26, 26)"
         and (.controls[0].height."390" > 0) and (.fields | length) == 1 and .type.h1 and (.breakpoints == ["max-width: 760px"])' "$T/m.json" >/dev/null \
    || { jq -c . "$T/m.json"; return 1; }
}

@test "p113: shot --name gives unique names and a header crop; strip and video record an animation; CHROME nowhere is refused" {
  mkdir -p "$T/site"
  printf '<html><head><style>@keyframes k{from{opacity:0}to{opacity:1}} h1{animation:k 1s linear}</style></head><body><h1>Logo</h1></body></html>' > "$T/site/a.html"
  serve "$T/site"
  run bash "$TOOL" shot "$T/n" --name konkurent --header "http://127.0.0.1:$PORT/a.html" "http://127.0.0.1:$PORT/a.html"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  for f in konkurent-1440 konkurent-header-1440 konkurent-390 konkurent-2-1440 konkurent-2-390; do [ -s "$T/n/$f.png" ] || { echo "no $f"; return 1; }; done
  run bash "$TOOL" strip "$T/s" "http://127.0.0.1:$PORT/a.html" --every 250 --until 1000; [ "$status" -eq 0 ]
  [ "$(ls "$T/s"/frame-*.png | wc -l)" -eq 5 ]
  ! cmp -s "$T/s/frame-00000.png" "$T/s/frame-01000.png"   # the animation moved between the first and the last frame
  run bash "$TOOL" video "$T/v" "http://127.0.0.1:$PORT/a.html" --until 600; [ "$status" -eq 0 ]; [ -s "$T/v/video.webm" ]
  CHROME=/nikde run bash "$TOOL" shot "$T/x" "http://127.0.0.1:$PORT/a.html"; [ "$status" -eq 2 ]; [[ "$output" == *"CHROME=/nikde is not an executable browser"* ]]
}
