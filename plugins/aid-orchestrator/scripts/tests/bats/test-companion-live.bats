#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/aid-companion.sh live (lib/brainstorm-server/kit-live-server.mjs, kit-live-panel.js, kit-proto.mjs liveEnv)
# test-companion-live.bats — the live preview (3.17.0, PM 2A after WAN P121): the PM opens the real application
# through a proxy with the AID panel instead of captures. Proves: the copy needs ui.live.env and never a production
# host; HTML gets window.AID_VARIANT from ?v= and the panel, other responses pass as they are; the panel's answers
# land in answers.jsonl only from the proxy's own page; down stops the proxy. No browser, no real app: a python
# HTTP server stands in for the copy's dev server.

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
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$u/index.html?aid_t=$(printf 'ž%.0s' $(seq 48))")" = 403 ]
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
