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
  mkdir -p "$BATS_TEST_TMPDIR/brand" "$BATS_TEST_TMPDIR/page"
  echo brand-ok > "$BATS_TEST_TMPDIR/brand/index.html"
  echo page-ok > "$BATS_TEST_TMPDIR/page/index.html"
}

teardown() {
  "$SERVE" stop forward || true
  "$SERVE" stop brand || true
  local p; for p in "${FOREIGN_PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  wait 2>/dev/null || true
}

# A server the test owns (not a job of ours); fd 3 closed so bats is not held.
foreign_server() {   # <port> <dir>
  python3 -m http.server "$1" --bind 127.0.0.1 --directory "$2" >/dev/null 2>&1 3>&- &
  FOREIGN_PIDS+=("$!")
  local i; for i in $(seq 1 50); do
    [[ -n "$(ss -ltnH "sport = :$1")" ]] && return 0; sleep 0.1
  done
  return 1
}

get() { curl -sf --max-time 3 "http://127.0.0.1:$1/"; }

@test "forward serves a loopback page through the forward port" {
  foreign_server 39917 "$BATS_TEST_TMPDIR/page"
  run "$SERVE" forward 39917
  [ "$status" -eq 0 ]
  [[ "$output" == *"URL: http://127.0.0.1:39915/"* ]]
  [[ "$output" == *"JOB: aid-ui-forward-39915"* ]]
  [ "$(get 39915)" = page-ok ]
}

@test "brand serves a directory" {
  run "$SERVE" brand "$BATS_TEST_TMPDIR/brand"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URL: http://127.0.0.1:39916/"* ]]
  [ "$(get 39916)" = brand-ok ]
}

@test "stop forward leaves the brand server answering" {
  foreign_server 39917 "$BATS_TEST_TMPDIR/page"
  "$SERVE" forward 39917
  "$SERVE" brand "$BATS_TEST_TMPDIR/brand"
  run "$SERVE" stop forward
  [ "$status" -eq 0 ]
  run get 39915; [ "$status" -ne 0 ]
  [ "$(get 39916)" = brand-ok ]
}

@test "forward, stop forward, forward: the fixed job id restarts and serves again" {
  foreign_server 39917 "$BATS_TEST_TMPDIR/page"
  "$SERVE" forward 39917
  "$SERVE" stop forward
  run "$SERVE" forward 39917
  [ "$status" -eq 0 ]
  [ "$(get 39915)" = page-ok ]
  ls -d "$AID_UI_JOBS_DIR"/aid-ui-forward-39915.superseded-*
}

@test "brand twice returns the same URL; brand after stop brand answers again" {
  run "$SERVE" brand "$BATS_TEST_TMPDIR/brand"
  [ "$status" -eq 0 ]; first="$output"
  run "$SERVE" brand "$BATS_TEST_TMPDIR/brand"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  "$SERVE" stop brand
  run "$SERVE" brand "$BATS_TEST_TMPDIR/brand"
  [ "$status" -eq 0 ]
  [ "$(get 39916)" = brand-ok ]
}

@test "a port held by a foreign http.server: exit 1 naming the port, foreign alive" {
  foreign_server 39916 "$BATS_TEST_TMPDIR/page"
  run "$SERVE" brand "$BATS_TEST_TMPDIR/brand"
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

@test "stop without a role exits 2" {
  run "$SERVE" stop
  [ "$status" -eq 2 ]
}
