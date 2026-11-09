#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/aid-companion.sh live (lib/brainstorm-server/kit-live-server.mjs, kit-live-panel.js, kit-proto.mjs liveEnv; scripts/lib/aid-ui-config.sh aid_ui_live_detect)
# test-companion-live.bats — the live preview (3.17.0, PM 2A after WAN P121): the PM opens the real application
# through a proxy with the AID panel instead of captures. Proves: the copy needs ui.live.env and never a production
# host; HTML gets window.AID_VARIANT from ?v= and the panel, other responses pass as they are; the panel's answers
# land in answers.jsonl only from the proxy's own page; down stops the proxy. No browser, no real app: a python
# HTTP server stands in for the copy's dev server. 3.18.1 (PM 1A: the live preview everywhere, wired): /aid-init
# proposes ui.live from the app's proxy target and never guesses an address; up tells the agent whether the PM can
# see the real app; live writes the brainstorm gate's basis.

bats_require_minimum_version 1.5.0

setup() {
  command -v node >/dev/null || skip "node not installed"
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  C="$AID_PLUGIN_PATH/scripts/aid-companion.sh"
  R="$BATS_TEST_TMPDIR/p"; mkdir -p "$R/.aid-o/config" "$R/web"
  git -C "$R" init -q -b main
  D="$R/.aid-o/work/companion/P970"; mkdir -p "$D/proto"
  printf '<html><head><title>app</title></head><body><main>Provize</main></body></html>' > "$R/web/index.html"
  printf 'body{}' > "$R/web/app.css"
  # the copy's dev server: its own process group (as proto starts it), on a loopback port
  PP="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  # serves web/, echoes the Cookie it got at /echo, a gzip page at /gz.html, an ETag on every file
  cat > "$BATS_TEST_TMPDIR/app.py" <<'PY'
import gzip, http.server, os, sys
root = sys.argv[2]
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=root, **k)
    def end_headers(s): s.send_header("ETag", '"e1"'); super().end_headers()
    def do_GET(s):
        if s.path.startswith("/echo"):
            b = (s.headers.get("Cookie") or "-").encode(); s.send_response(200); s.send_header("Content-Type", "text/plain"); s.send_header("Content-Length", str(len(b))); s.end_headers(); s.wfile.write(b); return
        if s.path.startswith("/gz.html"):
            b = gzip.compress(b"<html><head></head><body>gz</body></html>"); s.send_response(200); s.send_header("Content-Type", "text/html"); s.send_header("Content-Encoding", "gzip"); s.send_header("Content-Length", str(len(b))); s.end_headers(); s.wfile.write(b); return
        super().do_GET()
    def log_message(s, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
  setsid python3 "$BATS_TEST_TMPDIR/app.py" "$PP" "$R/web" >/dev/null 2>&1 &
  SP=$!
  for i in $(seq 50); do curl -sf "http://127.0.0.1:$PP/" >/dev/null && break; sleep 0.1; done
  jq -n --argjson pid "$SP" --arg st "$(sed -E 's/^.*\) //' /proc/$SP/stat | awk '{print $20}')" --argjson port "$PP" \
    '{pid: $pid, pgid: $pid, starttime: $st, port: $port, url: "http://127.0.0.1:\($port)", live_env: "0123456789abcdef"}' > "$D/proto.json"
  jq -n '{kolo: 1, body: [{bod: 1, otazka: "Jak ukázat provize", varianty: [{klic: "A", popis: "tabulka", cesta: "/index.html"}, {klic: "B", popis: "karty", cesta: "/index.html"}]}]}' > "$D/live.json"
  export AID_COMPANION_BIND=127.0.0.1 AID_COMPANION_URL_HOST=127.0.0.1 AID_COMPANION_LIVE_PORTS="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); p=s.getsockname()[1]; print(f"{p}-{p}")')"
}
teardown() {
  bash "$C" down --plan P970 --project-dir "$R" >/dev/null 2>&1 || true
  [[ -n "${SP:-}" ]] && kill "$SP" 2>/dev/null || true
}
_live() { run bash "$C" live --plan P970 --project-dir "$R"; }
# (the default range without AID_COMPANION_LIVE_PORTS is exercised by the PM's live run, 3.17.1: set -u had broken it)
_port() { jq -r .port "$D/live-server.json"; }
_tok() { jq -r .url "$D/live-server.json" | sed -E 's/.*aid_t=([0-9a-f]+).*/\1/'; }
_ck() { printf 'aid_t_%s=%s' "$(_port)" "$(_tok)"; }
_get() { curl -s -H "Cookie: $(_ck)" "$@"; }

@test "live: without the run's token everything is 403; the token in the address becomes a cookie and leaves the address" {
  _live; echo "$output"; [ "$status" -eq 0 ]
  local u="http://127.0.0.1:$(_port)"
  [[ "$(jq -r .url <<< "$output")" == "$u/index.html?v=A&aid_t="* ]]
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$u/index.html")" = 403 ]
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$u/__aid/live.json")" = 403 ]
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: aid_t_$(_port)=000000000000000000000000000000000000000000000000" "$u/index.html")" = 403 ]
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: aid_t_1=$(_tok)" "$u/index.html")" = 403 ]                 # another proxy's cookie
  # a token of the right length in other characters is refused, the proxy stays up
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$u/index.html?aid_t=$(printf '%%C5%%BE%.0s' $(seq 48))")" = 403 ]
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$u/index.html")" = 403 ]
  # a cookie left from an earlier run on this port does not hide the valid token in the address (3.17.1, PM's try)
  [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: aid_t_$(_port)=000000000000000000000000000000000000000000000000" "$u/index.html?aid_t=$(_tok)")" = 302 ]
  run curl -s -D - -o /dev/null "$u/index.html?v=B&aid_t=$(_tok)"
  [[ "$output" == *"302"* ]]; [[ "$output" == *"set-cookie: aid_t_$(_port)=$(_tok); Path=/; HttpOnly; SameSite=Strict"* ]]   # the port in the name: two proxies on one IP keep their own
  [[ "$output" == *"location: /index.html?v=B"* ]]
}

@test "live: HTML gets window.AID_VARIANT (only a key of live.json), the panel and a CSP; the cookie keeps the variant; other files pass as they are; /@fs outside the copy is 403" {
  _live; [ "$status" -eq 0 ]; local u="http://127.0.0.1:$(_port)"
  local h; h="$(_get -D "$BATS_TEST_TMPDIR/hdr" "$u/index.html?v=B")"
  [[ "$h" == *'<head><script>window.AID_VARIANT="B";</script><title>'* ]]
  [[ "$h" == *'<script src="/__aid/panel.js" defer></script></body>'* ]]
  grep -qi "^content-security-policy: connect-src 'self'" "$BATS_TEST_TMPDIR/hdr"
  grep -qi "^set-cookie: aid_v_$(_port)=B" "$BATS_TEST_TMPDIR/hdr"
  grep -qi '^cache-control: no-store' "$BATS_TEST_TMPDIR/hdr"; ! grep -qi '^etag:' "$BATS_TEST_TMPDIR/hdr"     # a cached page would carry another variant
  [[ "$(curl -s -H "Cookie: $(_ck); aid_v_$(_port)=B" "$u/index.html")" == *'window.AID_VARIANT="B"'* ]]
  [ "$(curl -s -H "Cookie: $(_ck); aid_v_$(_port)=B; app=1" "$u/echo")" = "app=1" ]                      # the proxy's own cookies never reach the app
  [[ "$(_get "$u/gz.html")" == *'window.AID_VARIANT=null'*'<body>gz<script src="/__aid/panel.js"'* ]]      # a gzip page is unpacked and gets the panel
  [ "$(_get -o /dev/null -w '%{http_code}' "$u//@fs/etc/passwd")" = 400 ]
  [[ "$(_get "$u/index.html?v=Z")" == *'window.AID_VARIANT=null'* ]]                          # not a key of live.json
  [[ "$(_get "$u/index.html?v=%3C%2Fscript%3E")" == *'window.AID_VARIANT=null'* ]]
  [ "$(_get "$u/app.css")" = 'body{}' ]
  [[ "$(_get "$u/__aid/panel.js")" == *"attachShadow"* ]]
  [ "$(_get "$u/__aid/live.json" | jq -r '.body[0].varianty[1].klic')" = B ]
  [ "$(_get -o /dev/null -w '%{http_code}' "$u/@fs/etc/passwd")" = 403 ]
  [ "$(_get -o /dev/null -w '%{http_code}' "$u/__open-in-editor?file=x")" = 403 ]
}

@test "live: an answer from the proxy's own page lands in answers.jsonl and answers reads it; a foreign origin is refused" {
  _live; [ "$status" -eq 0 ]; local u="http://127.0.0.1:$(_port)"
  run _get -o /dev/null -w '%{http_code}' -H "Origin: $u" -H 'content-type: application/json' -d '{"type":"choice","bod":1,"volba":"B"}' "$u/__aid/answer"
  [ "$output" = 200 ]
  run _get -o /dev/null -w '%{http_code}' -H "Origin: http://evil.example" -d '{"type":"choice","bod":1,"volba":"A"}' "$u/__aid/answer"
  [ "$output" = 403 ]
  run _get -o /dev/null -w '%{http_code}' -d '{"type":"choice","bod":1,"volba":"A"}' "$u/__aid/answer"
  [ "$output" = 403 ]
  run curl -s -o /dev/null -w '%{http_code}' -H "Origin: $u" -d '{"type":"choice","bod":1,"volba":"A"}' "$u/__aid/answer"
  [ "$output" = 403 ]                                                                         # no token
  run bash "$C" answers --plan P970 --project-dir "$R"; echo "$output"
  [ "$(jq -r '.volby["1"]' <<< "$output")" = B ]
  [ "$(jq -r 'select(.type == "choice") | "\(.page) \(.zdroj)"' "$D/answers.jsonl")" = "live live" ]
}

@test "live: refuses a copy running on mocks and a live.json of the wrong shape; down stops the proxy" {
  jq '.live_env = null' "$D/proto.json" > "$D/p.t" && mv "$D/p.t" "$D/proto.json"
  _live; [ "$status" -ne 0 ]; [[ "$output" == *"without ui.live.env"* ]]
  jq '.live_env = "0123456789abcdef"' "$D/proto.json" > "$D/p.t" && mv "$D/p.t" "$D/proto.json"
  local c; for c in "//evil.example/" "/x?v=Z" "/x#y"; do
    jq --arg c "$c" '.body[0].varianty[0].cesta = $c' "$D/live.json" > "$D/l.t" && mv "$D/l.t" "$D/live.json"
    _live; [ "$status" -ne 0 ]; [[ "$output" == *"must be"* ]]
  done
  jq '.body[0].varianty[0].cesta = "/index.html"' "$D/live.json" > "$D/l.t" && mv "$D/l.t" "$D/live.json"
  _live; [ "$status" -eq 0 ]; local port; port="$(_port)"
  run bash "$C" down --plan P970 --project-dir "$R"; [[ "$output" == *"live proxy"*"stopped"* ]]
  sleep 0.3; [ -z "$(ss -ltnH "sport = :$port")" ]
}

@test "proto --live: no ui.live.env or allowed_api, an address outside the allowlist, a secret-looking key are refused; the env is clean" {
  _env() { run node --input-type=module -e "import { liveEnv } from '$AID_PLUGIN_PATH/lib/brainstorm-server/kit-proto.mjs'; const die = m => { console.log('DIE ' + m); process.exit(1); };
    const r = await liveEnv($1, die); console.log(JSON.stringify(r))"; }
  _env '{}'; [ "$status" -eq 1 ]; [[ "$output" == *"no ui.live.env"* ]]
  _env "{ live: { env: { VITE_API_TARGET: 'http://127.0.0.1:8000' } } }"; [ "$status" -eq 1 ]; [[ "$output" == *"no ui.live.allowed_api"* ]]
  _env "{ live: { env: { VITE_API_TARGET: 'http://10.20.20.21:8000' }, allowed_api: ['10.20.20.22'] } }"; [ "$status" -eq 1 ]; [[ "$output" == *"not one of ui.live.allowed_api"* ]]
  _env "{ live: { env: { VITE_API_TARGET: 'http://LOCALHOST:8000/x' }, allowed_api: ['10.20.20.22'] } }"; [ "$status" -eq 1 ]   # a name resolves to an address outside
  _env "{ live: { env: { API_TOKEN: 'x' }, allowed_api: ['127.0.0.1'] } }"; [ "$status" -eq 1 ]; [[ "$output" == *"looks like a secret"* ]]
  _env "{ live: { env: { VITE_API_HOST: '10.20.20.21:8000' }, allowed_api: ['127.0.0.1'] } }"; [ "$status" -eq 1 ]; [[ "$output" == *"one whole URL"* ]]
  _env "{ live: { env: { VITE_API_TARGET: 'http://127.0.0.1:9999' }, allowed_api: ['127.0.0.1:8000'] } }"; [ "$status" -eq 1 ]   # another port of the host
  GH_TOKEN=leak _env "{ live: { env: { VITE_API_TARGET: 'http://127.0.0.1:8000' }, allowed_api: ['127.0.0.1'] } }"; echo "$output"
  [ "$status" -eq 0 ]; [ "$(jq -r .env.VITE_API_TARGET <<< "$output")" = "http://127.0.0.1:8000" ]
  [ "$(jq -r '.env.GH_TOKEN // "absent"' <<< "$output")" = absent ]                           # the agent's keys stay out
  [[ "$(jq -r .digest <<< "$output")" =~ ^[0-9a-f]{16}$ ]]
}


@test "marks: a mark is checked by the proxy (druh, numbers, text, an existing id to delete), gets the server's id, lists per screen and variant, answers folds deletions (3.18.0)" {
  _live; [ "$status" -eq 0 ]; local u="http://127.0.0.1:$(_port)"
  _m() { _get -s -o "$BATS_TEST_TMPDIR/mr" -w '%{http_code}' -H "Origin: $u" -H 'content-type: application/json' -d "$1" "$u/__aid/answer"; }
  local ok='{"type":"mark","druh":"bod","text":"tady","varianta":"A","cesta_path":"/index.html","kotva":{"selector":"main > p:nth-of-type(1)","x":10,"y":50},"rect":{"x":1,"y":2,"w":0,"h":0},"prvek":{"tag":"p"}}'
  [ "$(_m "$ok")" = 200 ]; local id; id="$(jq -r .id "$BATS_TEST_TMPDIR/mr")"; [[ "$id" =~ ^[0-9a-f-]{36}$ ]]
  [ "$(_m "$(jq -c '.druh = "sipka"' <<< "$ok")")" = 400 ]
  [ "$(_m "$(jq -c '.kotva.x = 101' <<< "$ok")")" = 400 ]
  [ "$(_m "${ok/\"w\":0/\"w\":1e400}")" = 400 ]                                                  # Infinity
  [ "$(_m "$(jq -c '.rect.y = -1' <<< "$ok")")" = 400 ]
  [ "$(_m "$(jq -c --arg t "$(head -c 4001 /dev/zero | tr '\0' x)" '.text = $t' <<< "$ok")")" = 400 ]
  [ "$(_m "$(jq -c --arg t "$(head -c 501 /dev/zero | tr '\0' x)" '.kotva.selector = $t' <<< "$ok")")" = 400 ]
  [ "$(_m "$(jq -c '.druh = "oblast"' <<< "$ok")")" = 400 ]                                      # an area needs w and h
  [ "$(_m '{"type":"mark","smazano":true,"id":"no-such-id"}')" = 400 ]
  [ "$(_get "$u/__aid/marks?p=/index.html&v=A" | jq -r '.[0].text')" = tady ]
  [ "$(_get "$u/__aid/marks?p=/index.html&v=B" | jq length)" = 0 ]
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$u/__aid/marks?p=/index.html&v=A")" = 403 ]                 # no token
  # a mark belongs to its round: in round 2 the panel shows none of round 1 and cannot delete them
  jq '.kolo = 2' "$D/live.json" > "$D/l.t" && mv "$D/l.t" "$D/live.json"
  [ "$(_get "$u/__aid/marks?p=/index.html&v=A" | jq length)" = 0 ]
  [ "$(_m "{\"type\":\"mark\",\"smazano\":true,\"id\":\"$id\"}")" = 400 ]
  jq '.kolo = 1' "$D/live.json" > "$D/l.t" && mv "$D/l.t" "$D/live.json"
  [ "$(_m "$(jq -c '.text = "druha"' <<< "$ok")")" = 200 ]
  [ "$(_m "{\"type\":\"mark\",\"smazano\":true,\"id\":\"$id\"}")" = 200 ]
  run bash "$C" answers --plan P970 --project-dir "$R"; echo "$output"
  [ "$(jq -c '[.znacky[].text]' <<< "$output")" = '["druha"]' ]
  [ "$(jq -r '.znacky[0].kotva.selector' <<< "$output")" = "main > p:nth-of-type(1)" ]
  # the companion page (index.js) writes no marks: the shared writer allows them only where the live proxy asks
  run node -e "const a = require('$AID_PLUGIN_PATH/lib/brainstorm-server/answers.js'); console.log(a.appendAnswer('$D', { type: 'mark', druh: 'bod' }, {}))"
  [ "$output" = null ]
}

@test "marks in a browser: outside the mode the app gets its clicks, inside it does not; a point is anchored to its element and follows a scrolled <main>; a note is shown as text only; Esc leaves the mode" {
  local lib="$AID_PLUGIN_PATH/lib/ui-fidelity" chrome
  [[ -f "$lib/node_modules/.aid-installed" ]] || (cd "$lib" && npm ci --no-audit --no-fund >/dev/null 2>&1 && sha256sum package-lock.json | cut -d' ' -f1 > node_modules/.aid-installed)
  chrome="$(ls -d "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | sort -V | tail -1)"
  [[ -n "$chrome" ]] || { echo "no chromium for the browser case (the kit's own tools)"; false; }
  printf '<html><head></head><body style="margin:0"><main id="m" style="height:300px;overflow:auto"><div style="height:2000px">
    <button id="b" onclick="window.cnt=(window.cnt||0)+1">app</button><p id="target" style="margin-top:400px;width:200px">cil</p></div></main></body></html>' > "$R/web/marks.html"
  jq '.body[0].varianty[0].cesta = "/marks.html"' "$D/live.json" > "$D/l.t" && mv "$D/l.t" "$D/live.json"
  _live; [ "$status" -eq 0 ]
  run env CHROME="$chrome" node --input-type=module -e "
    import { createRequire } from 'node:module';
    const { chromium } = createRequire('$lib/package.json')('@playwright/test');
    const b = await chromium.launch({ executablePath: process.env.CHROME }); const p = await b.newPage({ viewport: { width: 1200, height: 800 } });
    await p.goto('$(jq -r .url "$D/live-server.json")');
    await p.waitForFunction(() => window.__AID_MARKS__);
    await p.click('#b'); const before = await p.evaluate(() => window.cnt);
    await p.evaluate(() => window.__AID_MARKS__.setCommenting(true));
    await p.click('#b', { force: true }); const during = await p.evaluate(() => window.cnt);
    await p.keyboard.press('Escape'); await p.click('#b'); const after = await p.evaluate(() => window.cnt);
    await p.evaluate(() => { document.getElementById('m').scrollTop = 300; window.__AID_MARKS__.setCommenting(true); });
    await p.click('#target', { force: true, position: { x: 10, y: 5 } });
    await p.locator('#aid-live-panel textarea').last().fill('<img src=x onerror=\"window.pwn=1\">pozor');
    await p.locator('#aid-live-panel button', { hasText: 'Uložit' }).click();
    await p.waitForFunction(() => window.__AID_MARKS__.marks.length === 1);
    const listText = await p.evaluate(() => document.getElementById('aid-live-panel').shadowRoot.querySelector('.mk .t').textContent);
    await p.keyboard.press('Escape');
    // an area: a mouse drag over the target; then, with a bubble still open, Odeslat volby still sends (3.17.1 kept)
    await p.evaluate(() => window.__AID_MARKS__.setCommenting(true));
    const t = await p.locator('#target').boundingBox();
    await p.mouse.move(t.x + 60, t.y + 2); await p.mouse.down(); await p.mouse.move(t.x + 180, t.y + 15, { steps: 5 }); await p.mouse.up();   // beside the first pin
    await p.locator('#aid-live-panel .bubble textarea').fill('oblast');
    await p.locator('#aid-live-panel .bubble button', { hasText: 'Uložit' }).click();
    await p.waitForFunction(() => window.__AID_MARKS__.marks.length === 2);
    await p.mouse.click(t.x + 190, t.y + 3);                                     // a new bubble stays open
    const errs = []; p.on('pageerror', e => errs.push(e.message));
    await p.locator('#aid-live-panel button', { hasText: 'Odeslat volby' }).click(); await p.waitForTimeout(300);
    await p.keyboard.press('Escape');
    // delete the first mark with its ×
    await p.locator('#aid-live-panel .mk button').first().click();
    await p.waitForFunction(() => window.__AID_MARKS__.marks.length === 1);
    const druhy = await p.evaluate(() => window.__AID_MARKS__.marks.map(m => m.druh));
    const pinAt = async () => p.evaluate(() => { const pin = document.getElementById('aid-live-panel').shadowRoot.querySelector('.pin'); const t = document.getElementById('target').getBoundingClientRect();
      return pin ? { dy: parseFloat(pin.style.top) - t.top } : null; });
    await p.waitForTimeout(100); const a = await pinAt();
    await p.evaluate(() => { document.getElementById('m').scrollTop = 350; }); await p.waitForTimeout(150); const c = await pinAt();
    console.log(JSON.stringify({ before, during, after, a, c, pwn: await p.evaluate(() => window.pwn || null), listText, errs, druhy }));
    await b.close();"
  echo "$output"; [ "$status" -eq 0 ]
  local r; r="$(tail -1 <<< "$output")"
  [ "$(jq -c '[.before, .during, .after]' <<< "$r")" = '[1,1,2]' ]          # app click; swallowed in the mode; app again after Esc
  [ "$(jq -r '.pwn' <<< "$r")" = null ]
  [[ "$(jq -r '.listText' <<< "$r")" == '<img src=x onerror="window.pwn=1">pozor'* ]]
  local da dc; da="$(jq -r '.a.dy' <<< "$r")"; dc="$(jq -r '.c.dy' <<< "$r")"
  python3 -c "import sys; a, c = float('$da'), float('$dc'); sys.exit(0 if abs(a - c) < 2 else 1)"      # the pin keeps its place on the element
  [ "$(jq -r 'select(.type == "mark" and .druh == "bod") | .kotva.selector' "$D/answers.jsonl")" = '#target' ]
  [ "$(jq -c '.errs' <<< "$r")" = '[]' ]; [ "$(jq -c '.druhy' <<< "$r")" = '["oblast"]' ]
  [ "$(jq -r 'select(.type == "confirm") | .type' "$D/answers.jsonl" | wc -l)" -ge 1 ]
  [ "$(jq -r 'select(.type == "note") | .bod' "$D/answers.jsonl" | grep -c null || true)" = 0 ]   # the bubble text never became a note
}

_detect() { printf 'export default { server: { proxy: { "/api": {\n%s\n} } } }\n' "$1" > "$R/web/vite.config.ts"; run bash -c "set -euo pipefail; source '$AID_PLUGIN_PATH/scripts/lib/aid-ui-config.sh' && aid_ui_live_detect '$R' web"; echo "$output"; }
_live_ok() {  # the proposed block passes the kit's own check (liveEnv)
  local ui; ui="$(yq -o=json -I=0 '.ui' <<< "$output")"
  run node --input-type=module -e "import { liveEnv } from '$AID_PLUGIN_PATH/lib/brainstorm-server/kit-proto.mjs'; await liveEnv($ui, m => { console.log('DIE ' + m); process.exit(1); }); console.log('OK')"
  echo "$output"; [ "$status" -eq 0 ]
}

@test "ui.live is proposed from the app's proxy target only when its default resolves; otherwise a comment, never a guessed address" {
  _detect "server: { proxy: { '/api': { target: process.env.VITE_API_TARGET ?? 'http://127.0.0.1:3501' } } }"
  [ "$(yq '.ui.live.env.VITE_API_TARGET' <<< "$output")" = "http://127.0.0.1:3501" ]
  [ "$(yq -o=json -I=0 '.ui.live.allowed_api' <<< "$output")" = '["127.0.0.1"]' ]
  _live_ok
  _detect "target: process.env.VITE_API_TARGET ?? 'http://127.1:3501'"; [ "$(yq -o=json -I=0 '.ui.live.allowed_api' <<< "$output")" = '["127.0.0.1"]' ]; _live_ok
  _detect "destination: process.env.API_URL || \"http://localhost:8000/v1\""
  [ "$(yq '.ui.live.env.API_URL' <<< "$output")" = "http://localhost:8000/v1" ]; _live_ok
  local c; for c in "target: process.env.VITE_API ?? 'http://no-such-api.invalid:3501'" \
      "target: process.env.VITE_API" "target: process.env.VITE_API ?? 'http://u:p@127.0.0.1:1'" \
      "target: process.env.VITE_API ?? 'http://127.0.0.1:1/?key=x'" \
      "target: process.env.VITE_A ?? 'http://127.0.0.1:1', target: process.env.VITE_B ?? 'http://127.0.0.1:2'" \
      "target: process.env.API_TOKEN ?? 'http://127.0.0.1:1'" "'/x': 'http://127.0.0.1:3287'" \
      "// target: process.env.VITE_API ?? 'http://127.0.0.1:1'" "target: process.env.VITE_API ?? 'http://u:p@127.0.0.1:99999'"; do
    _detect "$c"; [ "$status" -eq 0 ]; [ "$(yq '.ui.live' <<< "$output")" = null ]; [[ "$output" == *"# live:"* ]]
    [[ "$output" != *"u:p@"* && "$output" != *"key=x"* ]]
  done
  _detect "target: process.env.VITE_A ?? 'http://127.0.0.1:1', target: process.env.VITE_B ?? 'http://127.0.0.1:2'"; [[ "$output" == *"VITE_A,VITE_B"* ]]
  # the kit refuses credentials in a URL without printing them
  run node --input-type=module -e "import { liveEnv } from '$AID_PLUGIN_PATH/lib/brainstorm-server/kit-proto.mjs'; await liveEnv({ live: { env: { VITE_API: 'http://u:secretpw@127.0.0.1:1' }, allowed_api: ['127.0.0.1'] } }, m => { console.log('DIE ' + m); process.exit(1); })"
  [ "$status" -eq 1 ]; [[ "$output" == *"user or password"* ]]; [[ "$output" != *secretpw* ]]
  run node --input-type=module -e "import { liveEnv } from '$AID_PLUGIN_PATH/lib/brainstorm-server/kit-proto.mjs'; await liveEnv({ live: { env: { VITE_API: 'http://u:secretpw@127.0.0.1:99999' }, allowed_api: ['127.0.0.1'] } }, m => { console.log('DIE ' + m); process.exit(1); })"
  [ "$status" -eq 1 ]; [[ "$output" != *secretpw* ]]
  _detect "target: process.env.api_token ?? 'http://127.0.0.1:1'"; [ "$(yq '.ui.live' <<< "$output")" = null ]   # a secret in any case
  # a target outside the proxy block is not the app's API
  printf 'export default {\n  server: { proxy: { "/api": "http://127.0.0.1:3287" } },\n  define: { x: { target: process.env.OTHER_URL ?? "http://127.0.0.1:9999" } },\n}\n' > "$R/web/vite.config.ts"
  run bash -c "set -euo pipefail; source '$AID_PLUGIN_PATH/scripts/lib/aid-ui-config.sh' && aid_ui_live_detect '$R' web"; echo "$output"
  [ "$status" -eq 0 ]; [ "$(yq '.ui.live' <<< "$output")" = null ]; [[ "$output" != *OTHER_URL* ]]
  # a config with no proxy at all, and no config, are a comment too (under set -euo pipefail)
  printf 'export default { define: { x: { target: process.env.VITE_API ?? "http://127.0.0.1:1" } } }\n' > "$R/web/vite.config.ts"
  run bash -c "set -euo pipefail; source '$AID_PLUGIN_PATH/scripts/lib/aid-ui-config.sh' && aid_ui_live_detect '$R' web"; [ "$status" -eq 0 ]; [[ "$output" == *"# live:"* ]]
  rm "$R/web/vite.config.ts"
  run bash -c "set -euo pipefail; source '$AID_PLUGIN_PATH/scripts/lib/aid-ui-config.sh' && aid_ui_live_detect '$R' web"; [ "$status" -eq 0 ]; [[ "$output" == *"# live:"* ]]
}

@test "up tells the agent whether the PM can see the real application (missing, incomplete, set ui.live), also when it reuses its server; stdout stays JSON" {
  (cd "$R" && bash "$AID_PLUGIN_PATH/scripts/aid-brainstorm-state.sh" init P970 --scope user_visible --topic-kind ui --no-worktree >/dev/null)
  _up() { run --separate-stderr bash "$C" up --plan P970 --project-dir "$R"; echo "$output / $stderr"; [ "$status" -eq 0 ]; jq -e .url <<< "$output" >/dev/null; }
  printf 'ui:\n  responsive: false\n' > "$R/.aid-o/config/project.yaml"
  _up; [[ "$stderr" != *"ui.live"* ]]                                                  # no ui.dir: not an app the kit copies
  printf 'ui:\n  dir: web\n' > "$R/.aid-o/config/project.yaml"
  _up; [[ "$stderr" == *"no ui.live"*"aid_ui_live_detect"*" web"* ]]
  printf 'ui:\n  dir: web\n  live:\n    env: {VITE_API: "http://127.0.0.1:1"}\n' > "$R/.aid-o/config/project.yaml"
  _up; [[ "$stderr" == *"ui.live is incomplete"* ]]; [ "$(jq -r .reused <<< "$output")" = true ]
  printf 'ui:\n  dir: web\n  live:\n    env: {VITE_API: "http://127.0.0.1:1"}\n    allowed_api: [127.0.0.1]\n' > "$R/.aid-o/config/project.yaml"
  _up; [[ "$stderr" == *"ui.live is set"*"proto --live"* ]]
}

@test "live writes the brainstorm gate's basis (marked, the project's viewports) and never overwrites one the captures made" {
  local B="$R/.aid-o/work/brainstorm/P970"; mkdir -p "$B"
  _live; [ "$status" -eq 0 ]
  source "$AID_PLUGIN_PATH/scripts/lib/aid-ui-proposal.sh"
  run aid_ui_proposal_basis_check "$B/proposal.json" "$R"; echo "$output"; [ "$status" -eq 0 ]
  [[ "$(jq -r .marked "$B/proposal.json")" == "NO LIVE BASELINE — live preview"* ]]
  [ "$(jq -r '.viewports | map(.name) | join(",")' "$B/proposal.json")" = "desktop,mobile" ]
  jq -n '{basis: "live-screen", companion_kit: {navrh: "x"}}' > "$B/proposal.json"
  _live; [ "$status" -eq 0 ]; [ "$(jq -r .reused <<< "$output")" = true ]; [ "$(jq -r .basis "$B/proposal.json")" = live-screen ]
}
