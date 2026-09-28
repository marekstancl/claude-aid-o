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
