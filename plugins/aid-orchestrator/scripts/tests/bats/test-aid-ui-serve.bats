#!/usr/bin/env bats
# aid-tier: t2
# test-aid-ui-serve.bats — aid-ui-serve.sh (P101 Step 2): the decision-page
# forward and the brand page run as aid-job.sh jobs and stop independently.
# t2: it starts processes and binds ports 39915-39917.

setup() {
  SERVE="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/aid-ui-serve.sh"
  export AID_UI_HOST=127.0.0.1 AID_UI_FORWARD_PORT=39915 AID_UI_BRAND_PORT=39916
  export AID_UI_JOBS_DIR="$BATS_TEST_TMPDIR/jobs" AID_UI_PROJECT="$BATS_TEST_TMPDIR"
  FOREIGN_PIDS=()
  BRAND="$BATS_TEST_TMPDIR/proj/docs/brand" BRAND2="$BATS_TEST_TMPDIR/proj2/docs/brand"
  mkdir -p "$BRAND" "$BRAND2" "$BATS_TEST_TMPDIR/page"
  echo brand-ok > "$BRAND/index.html"
  echo brand2-ok > "$BRAND2/index.html"
  touch "$BRAND/tokens.css" "$BRAND2/tokens.css"
  echo page-ok > "$BATS_TEST_TMPDIR/page/index.html"
}

teardown() {
  "$SERVE" stop forward || true
  "$SERVE" stop brand || true
  local p; for p in "${FOREIGN_PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}

# A server the test owns (not a job of ours); fd 3 closed so bats is not held.
# [argv0] renames the process's argv[0]; `impeccable-stub` is the stand-in for
# Impeccable (its /proc/<pid>/cmdline then starts with impeccable-stub).
foreign_server() {   # <port> <dir> [argv0]
  bash -c 'exec -a "$0" python3 -m http.server "$1" --bind 127.0.0.1 --directory "$2"' \
    "${3:-python3}" "$1" "$2" >/dev/null 2>&1 3>&- &
  FOREIGN_PIDS+=("$!")
  local i; for i in $(seq 1 50); do
    [[ -n "$(ss -ltnH "sport = :$1")" ]] && return 0; sleep 0.1
  done
  return 1
}

get() { curl -sf --max-time 3 "http://127.0.0.1:$1/"; }

@test "forward serves a loopback page through the forward port" {
  foreign_server 39917 "$BATS_TEST_TMPDIR/page" impeccable-stub
  [[ "$(tr '\0' ' ' < "/proc/${FOREIGN_PIDS[0]}/cmdline")" == impeccable-stub\ * ]]
  run "$SERVE" forward 39917
  [ "$status" -eq 0 ]
  [[ "$output" == *"URL: http://127.0.0.1:39915/"* ]]
  [[ "$output" == *"JOB: aid-ui-forward-39915"* ]]
  [ "$(get 39915)" = page-ok ]
}

# Stand-in for Impeccable's own host check: 403 unless Host is 127.0.0.1:<port>
# and Origin, when sent, is http://127.0.0.1:<port>; else echoes method and body.
# Every request it sees is appended to $BATS_TEST_TMPDIR/upstream.log.
strict_upstream() {   # <port>
  bash -c 'exec -a impeccable-stub python3 -c "$1" "$2" "$3"' _ '
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
local = "127.0.0.1:" + sys.argv[1]
class H(BaseHTTPRequestHandler):
    def reply(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        open(sys.argv[2], "a").write(self.command + " " + self.path + "\n")
        ok = self.headers["Host"] == local and self.headers.get("Origin", "http://" + local) == "http://" + local
        out = (self.command.encode() + b":" + body) if ok else b"forbidden"
        self.send_response(200 if ok else 403)
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
    do_GET = do_POST = reply
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
' "$1" "$BATS_TEST_TMPDIR/upstream.log" >/dev/null 2>&1 3>&- &
  FOREIGN_PIDS+=("$!")
  local i; for i in $(seq 1 50); do
    [[ -n "$(ss -ltnH "sport = :$1")" ]] && return 0; sleep 0.1
  done
  return 1
}

# The browser on the VPN sends Host/Origin/Referer = the forward's own address
# (here 127.0.0.1:39915, AID_UI_HOST:AID_UI_FORWARD_PORT); upstream is :39917.
@test "forward rewrites Host and Origin so a host-checking page answers through the VPN port" {
  strict_upstream 39917
  run curl -s --max-time 3 -H 'Host: 127.0.0.1:39915' "http://127.0.0.1:39917/"
  [ "$output" = forbidden ]   # the stand-in really refuses a foreign Host
  run "$SERVE" forward 39917
  [ "$status" -eq 0 ]
  [ "$(curl -sf --max-time 3 http://127.0.0.1:39915/q?x=1)" = "GET:" ]
  [ "$(curl -sf --max-time 3 -H 'Origin: http://127.0.0.1:39915' -H 'Referer: http://127.0.0.1:39915/' \
        -d 'pick=b' http://127.0.0.1:39915/answer)" = "POST:pick=b" ]
}

@test "forward refuses a foreign Origin, Referer or Host with 403 and upstream never sees it" {
  strict_upstream 39917
  "$SERVE" forward 39917
  run curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H 'Origin: http://evil.example' \
    -d 'pick=b' http://127.0.0.1:39915/evil-origin
  [ "$output" = 403 ]
  run curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H 'Referer: http://127.0.0.1:39915.evil.example/' \
    -d 'pick=b' http://127.0.0.1:39915/evil-referer
  [ "$output" = 403 ]
  run curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H 'Host: evil.example' http://127.0.0.1:39915/evil-host
  [ "$output" = 403 ]
  [ "$(curl -sf --max-time 3 http://127.0.0.1:39915/ok)" = "GET:" ]   # same proxy still serves
  ! grep -q evil "$BATS_TEST_TMPDIR/upstream.log"
  grep -q 'GET /ok' "$BATS_TEST_TMPDIR/upstream.log"
}

@test "brand serves a directory" {
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URL: http://127.0.0.1:39916/"* ]]
  [ "$(get 39916)" = brand-ok ]
}

@test "stop forward leaves the brand server answering" {
  foreign_server 39917 "$BATS_TEST_TMPDIR/page" impeccable-stub
  "$SERVE" forward 39917
  "$SERVE" brand "$BRAND"
  run "$SERVE" stop forward
  [ "$status" -eq 0 ]
  run get 39915; [ "$status" -ne 0 ]
  [ "$(get 39916)" = brand-ok ]
}

@test "forward, stop forward, forward: the fixed job id restarts and serves again" {
  foreign_server 39917 "$BATS_TEST_TMPDIR/page" impeccable-stub
  "$SERVE" forward 39917
  "$SERVE" stop forward
  run "$SERVE" forward 39917
  [ "$status" -eq 0 ]
  [ "$(get 39915)" = page-ok ]
  ls -d "$AID_UI_JOBS_DIR"/aid-ui-forward-39915.superseded-*
}

@test "brand twice returns the same URL; brand after stop brand answers again" {
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]; first="$output"
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  "$SERVE" stop brand
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
  [ "$(get 39916)" = brand-ok ]
}

@test "a port held by a foreign http.server: exit 1 naming the port, foreign alive" {
  foreign_server 39916 "$BATS_TEST_TMPDIR/page"
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 1 ]
  [[ "$output" == *"39916"* ]]
  kill -0 "${FOREIGN_PIDS[0]}"
  [ "$(get 39916)" = page-ok ]
}

@test "stop brand with no job of ours leaves a foreign listener alive, exit 0" {
  foreign_server 39916 "$BATS_TEST_TMPDIR/page"
  run "$SERVE" stop brand
  [ "$status" -eq 0 ]
  kill -0 "${FOREIGN_PIDS[0]}"
  [ "$(get 39916)" = page-ok ]
}

@test "forward to a port that is not Impeccable: exit 2, only pid and name, nothing exposed" {
  foreign_server 39917 "$BATS_TEST_TMPDIR/page"
  AID_UI_FORWARD_PROC=python3 run "$SERVE" forward 39917   # the old override is gone
  [ "$status" -eq 2 ]
  [[ "$output" == ERROR:*39917* ]]
  [[ "$output" == *"pid ${FOREIGN_PIDS[0]}, python3)"* ]]
  [[ "$output" != *http.server* && "$output" != *"$BATS_TEST_TMPDIR"* ]]
  run get 39915; [ "$status" -ne 0 ]
  run "$SERVE" forward 39918
  [ "$status" -eq 2 ]
}

@test "brand of a directory that is not a brand page: exit 2, nothing served" {
  run "$SERVE" brand "$BATS_TEST_TMPDIR/page"
  [ "$status" -eq 2 ]
  [[ "$output" == ERROR:* ]]
  run get 39916; [ "$status" -ne 0 ]
}

@test "brand outside a docs/brand dir, even with index.html and tokens.css or via a docs/brand symlink: exit 2" {
  cp -r "$BRAND" "$BATS_TEST_TMPDIR/elsewhere"
  run "$SERVE" brand "$BATS_TEST_TMPDIR/elsewhere"
  [ "$status" -eq 2 ]; [[ "$output" == ERROR:* ]]
  mkdir -p "$BATS_TEST_TMPDIR/proj3/docs"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$BATS_TEST_TMPDIR/proj3/docs/brand"
  run "$SERVE" brand "$BATS_TEST_TMPDIR/proj3/docs/brand"
  [ "$status" -eq 2 ]; [[ "$output" == ERROR:* ]]
  run get 39916; [ "$status" -ne 0 ]
}

@test "brand of a folder holding state.json: exit 2 naming it, nothing served" {
  echo '{}' > "$BRAND/state.json"
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$BRAND/state.json"*"state.json must not be served"* ]]
  run get 39916; [ "$status" -ne 0 ]
}

@test "brand of a folder with a leftover temp file or a foreign file: exit 2 naming it" {
  mkdir -p "$BRAND/assets" "$BRAND/fonts"
  touch "$BRAND/assets/a.png" "$BRAND/fonts/f.woff2" "$BRAND/base.css"
  for f in index.html.Ab3xZ9 assets/x.tmp notes.md sub/y.css; do
    mkdir -p "$(dirname "$BRAND/$f")"; touch "$BRAND/$f"
    run "$SERVE" brand "$BRAND"
    [ "$status" -eq 2 ]
    [[ "$output" == *"$BRAND/$f"* ]]
    rm "$BRAND/$f"
  done
  run get 39916; [ "$status" -ne 0 ]
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
}

@test "brand of a folder holding a symlink: exit 2 naming it, nothing served" {
  mkdir -p "$BRAND/assets"
  echo secret > "$BATS_TEST_TMPDIR/secret"
  ln -s "$BATS_TEST_TMPDIR/secret" "$BRAND/assets/x.png"
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$BRAND/assets/x.png is a symlink"* ]]
  run get 39916; [ "$status" -ne 0 ]
}

@test "brand of another directory while one is served: restarts on the new one" {
  "$SERVE" brand "$BRAND"
  run "$SERVE" brand "$BRAND2"
  [ "$status" -eq 0 ]
  [ "$(get 39916)" = brand2-ok ]
}

@test "stop without a role exits 2" {
  run "$SERVE" stop
  [ "$status" -eq 2 ]
}
