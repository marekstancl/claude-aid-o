#!/usr/bin/env bats
# aid-tier: t2
# test-aid-ui-serve.bats — aid-ui-serve.sh (P101 Step 2, P103 Step 3): the
# studio page and the brand page run as aid-job.sh jobs and stop independently.
# t2: it starts processes and binds ports 39915-39917.

setup() {
  SERVE="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/aid-ui-serve.sh"
  export AID_UI_HOST=127.0.0.1 AID_UI_STUDIO_PORT=39915 AID_UI_BRAND_PORT=39916
  export AID_UI_JOBS_DIR="$BATS_TEST_TMPDIR/jobs" AID_UI_PROJECT="$BATS_TEST_TMPDIR"
  export AID_UI_STATE_DIR="$BATS_TEST_TMPDIR/state"
  FOREIGN_PIDS=()
  BRAND="$BATS_TEST_TMPDIR/proj/docs/brand" BRAND2="$BATS_TEST_TMPDIR/proj2/docs/brand"
  mkdir -p "$BRAND" "$BRAND2" "$BATS_TEST_TMPDIR/page"
  echo brand-ok > "$BRAND/index.html"
  echo brand2-ok > "$BRAND2/index.html"
  touch "$BRAND/tokens.css" "$BRAND2/tokens.css"
  echo page-ok > "$BATS_TEST_TMPDIR/page/index.html"
}

teardown() {
  "$SERVE" stop studio || true
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

@test "studio serves the page on the studio port with a fresh token in the project" {
  run "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URL: http://127.0.0.1:39915/"* ]]
  [[ "$output" == *"JOB: aid-ui-studio-39915"* ]]
  tok="$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")"
  [[ "$tok" =~ ^[0-9a-f]{32}$ ]]
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")" = 600 ]
  get 39915 | grep -q "const TOKEN = \"$tok\""
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H "X-AID-Token: $tok" http://127.0.0.1:39915/state)" = 200 ]
}

@test "studio twice keeps the server and its token; studio after stop studio gets a new token" {
  "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  tok="$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")"
  run "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")" = "$tok" ]
  run "$SERVE" stop studio
  [ "$status" -eq 0 ]
  run get 39915; [ "$status" -ne 0 ]
  "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  [ "$(cat "$BATS_TEST_TMPDIR/proj/.aid-ui/studio.token")" != "$tok" ]
  get 39915 | grep -q "AID studio"
  ls -d "$AID_UI_JOBS_DIR"/aid-ui-studio-39915.superseded-*
}

@test "studio on a port held by a foreign server: exit 1 naming the port, foreign alive" {
  foreign_server 39915 "$BATS_TEST_TMPDIR/page"
  run "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  [ "$status" -eq 1 ]
  [[ "$output" == *"port 39915 in use"* ]]
  [ "$(get 39915)" = page-ok ]
}

@test "studio of a path that is not a directory: exit 2" {
  run "$SERVE" studio "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  [[ "$output" == ERROR:* ]]
}

@test "stop studio leaves the brand server answering" {
  "$SERVE" studio "$BATS_TEST_TMPDIR/proj"
  "$SERVE" brand "$BRAND"
  run "$SERVE" stop studio
  [ "$status" -eq 0 ]
  run get 39915; [ "$status" -ne 0 ]
  [ "$(get 39916)" = brand-ok ]
}

@test "brand serves a directory" {
  run "$SERVE" brand "$BRAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"URL: http://127.0.0.1:39916/"* ]]
  [ "$(get 39916)" = brand-ok ]
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

@test "stop brand from outside the project stops the server it started" {
  "$SERVE" brand "$BRAND"
  [ "$(get 39916)" = brand-ok ]
  run env -u AID_UI_JOBS_DIR -u AID_UI_PROJECT bash -c 'cd / && "$0" stop brand' "$SERVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped the brand server of project $(realpath "$BATS_TEST_TMPDIR")"* ]]
  for i in $(seq 1 50); do [[ -z "$(ss -ltnH "sport = :39916")" ]] && break; sleep 0.1; done
  [ -z "$(ss -ltnH "sport = :39916")" ]
}

@test "stop brand from another project refuses to stop this project's server, naming both" {
  "$SERVE" brand "$BRAND"
  other="$BATS_TEST_TMPDIR/proj2"; me="$(realpath "$BATS_TEST_TMPDIR")"
  run env AID_UI_PROJECT="$other" AID_UI_JOBS_DIR="$other/.aid-ui/jobs" "$SERVE" stop brand
  [ "$status" -eq 1 ]
  [[ "$output" == *"belongs to project $me, not $(realpath "$other")"* ]]
  git init -q "$other"   # cwd inside a git project, no AID_UI_PROJECT
  run env -u AID_UI_JOBS_DIR -u AID_UI_PROJECT bash -c 'cd "$1/docs" && "$0" stop brand' "$SERVE" "$other"
  [ "$status" -eq 1 ]
  [[ "$output" == *"belongs to project $me, not $(realpath "$other")"* ]]
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
