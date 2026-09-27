#!/usr/bin/env bats
# aid-tier: t0
# test-aid-ui-studio.bats — the /aid-ui studio server (P103 Step 3) over real
# HTTP on a free loopback port: token and Host/Origin rule, answers only after
# the round opened, once, for the question's own kind and target, kept in
# memory only, re-roll opens a new question, /report escaped.

setup() {
  SERVER="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/lib/aid-ui-studio/server.py"
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/.aid-ui/studio"
  TOKEN=0123456789abcdef0123456789abcdef
  echo "$TOKEN" > "$P/.aid-ui/studio.token"
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  URL="http://127.0.0.1:$PORT"
  payload '2020-01-01T00:00:00Z'
  start_server
}

teardown() { kill "$SPID" 2>/dev/null || true; wait 2>/dev/null || true; }

start_server() {
  python3 "$SERVER" --project "$P" --host 127.0.0.1 --port "$PORT" \
    --token-file "$P/.aid-ui/studio.token" >"$BATS_TEST_TMPDIR/server.log" 2>&1 3>&- &
  SPID=$!
  local i; for i in $(seq 1 50); do curl -s -o /dev/null "$URL/" && return 0; sleep 0.1; done
  return 1
}

payload() {   # <opened_at of q1> [target of q1]
  cat > "$P/.aid-ui/studio/payload.json" <<JSON
{"steps": [{"id": "s1", "title": "Směr", "status": "current"}],
 "questions": [
   {"id": "q1", "kind": "direction", "target": "${2:-home@abc}", "opened_at": "$1", "title": "Vyberte směr"},
   {"id": "q2", "kind": "approve_page", "target": "home@abc", "opened_at": "2020-01-01T00:00:00Z"}],
 "cards": [{"id": "a", "question": "q1", "title": "A", "preview": "a.png"},
           {"id": "b", "question": "q1", "title": "B", "preview": "../../secret"}]}
JSON
}

# code <curl args...> -> HTTP status; body in $BATS_TEST_TMPDIR/body
code() { curl -s -o "$BATS_TEST_TMPDIR/body" -w '%{http_code}' --max-time 3 "$@"; }
answer() {   # <json> [extra curl args]
  local b="$1"; shift
  code -H "X-AID-Token: $TOKEN" -H 'Content-Type: application/json' -d "$b" "$@" "$URL/answer"
}
choose_a='{"question":"q1","kind":"direction","target":"home@abc","decision":"choose","choice":"a"}'

@test "token missing or wrong: POST and GET /answer and /state answer 403" {
  [ "$(code -d "$choose_a" "$URL/answer")" = 403 ]
  [ "$(code -H 'X-AID-Token: wrong' -d "$choose_a" "$URL/answer")" = 403 ]
  grep -q '"token"' "$BATS_TEST_TMPDIR/body"
  [ "$(code "$URL/answer?question=q1")" = 403 ]
  [ "$(code "$URL/state")" = 403 ]
  [ "$(answer "$choose_a")" = 200 ]   # the token itself works
}

@test "foreign Origin, Referer or Host: 403 and nothing recorded" {
  [ "$(answer "$choose_a" -H 'Origin: http://evil.example')" = 403 ]
  [ "$(answer "$choose_a" -H "Referer: http://127.0.0.1:$PORT.evil.example/")" = 403 ]
  [ "$(answer "$choose_a" -H 'Host: evil.example')" = 403 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/answer?question=q1")" = 404 ]
  [ "$(answer "$choose_a" -H "Origin: $URL" -H "Referer: $URL/")" = 200 ]
}

@test "the page is served with the session token embedded" {
  [ "$(code "$URL/")" = 200 ]
  grep -q "const TOKEN = \"$TOKEN\"" "$BATS_TEST_TMPDIR/body"
}

@test "an answer before opened_at is ignored: 409 while not open, and an older answer does not count for a reopened round" {
  payload '2999-01-01T00:00:00Z'
  [ "$(answer "$choose_a")" = 409 ]
  payload '2020-01-01T00:00:00Z'
  [ "$(answer "$choose_a")" = 200 ]
  sleep 0.01
  payload "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)"   # the agent reopens q1 now
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/answer?question=q1")" = 404 ]
  [ "$(answer "$choose_a")" = 200 ]
}

@test "the first answer closes its question: GET /answer returns it, a second answer 409" {
  [ "$(answer "$choose_a")" = 200 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/answer?question=q1")" = 200 ]
  run jq -r '[.question, .kind, .target, .decision, .choice, (.at|length > 0)] | join(" ")' "$BATS_TEST_TMPDIR/body"
  [ "$output" = "q1 direction home@abc choose a true" ]
  [ "$(answer '{"question":"q1","kind":"direction","target":"home@abc","decision":"choose","choice":"b"}')" = 409 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/answer?question=q1")" = 200 ]
  [ "$(jq -r .choice "$BATS_TEST_TMPDIR/body")" = a ]
  [ "$(answer '{"question":"q2","kind":"approve_page","target":"home@abc","decision":"approve"}')" = 200 ]   # answers never cross
}

@test "an answer for another kind or target, a superseded question or a foreign card is refused" {
  [ "$(answer '{"question":"q1","kind":"variant","target":"home@abc","decision":"choose","choice":"a"}')" = 409 ]
  [ "$(answer '{"question":"q1","kind":"direction","target":"home@old","decision":"choose","choice":"a"}')" = 409 ]
  [ "$(answer '{"question":"gone","kind":"direction","target":"home@abc","decision":"approve"}')" = 409 ]
  [ "$(answer '{"question":"q1","kind":"direction","target":"home@abc","decision":"choose","choice":"zz"}')" = 422 ]
  [ "$(answer '{"question":"q2","kind":"approve_page","target":"home@abc","decision":"return"}')" = 422 ]
  [ "$(answer "$choose_a")" = 200 ]
  payload '2020-01-01T00:00:00Z' home@new   # the agent changes q1's target
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/answer?question=q1")" = 404 ]
}

@test "a re-roll closes its question and opens a new id with the same kind and target" {
  [ "$(answer '{"question":"q1","kind":"direction","target":"home@abc","decision":"reroll_bolder","comment":"víc kontrastu"}')" = 200 ]
  [ "$(jq -r .next_question "$BATS_TEST_TMPDIR/body")" = q1.r1 ]
  [ "$(answer "$choose_a")" = 409 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -r '.questions[] | select(.id=="q1.r1") | "\(.kind) \(.target)"' "$BATS_TEST_TMPDIR/body")" = "direction home@abc" ]
  [ "$(answer '{"question":"q1.r1","kind":"direction","target":"home@abc","decision":"reroll_safer"}')" = 200 ]
  [ "$(jq -r .next_question "$BATS_TEST_TMPDIR/body")" = q1.r2 ]
}

@test "a restart forgets an unrecorded answer and the question is open again" {
  [ "$(answer "$choose_a")" = 200 ]
  kill "$SPID"; wait "$SPID" 2>/dev/null || true
  start_server
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/answer?question=q1")" = 404 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -r '.questions[] | select(.id=="q1") | .answered' "$BATS_TEST_TMPDIR/body")" = false ]
  [ "$(answer "$choose_a")" = 200 ]
}

@test "/report renders the compliance report HTML-escaped, 404 without it" {
  [ "$(code "$URL/report")" = 404 ]
  mkdir -p "$P/docs/design"
  printf '# Soulad\n<script>alert(1)</script> & <b>\n' > "$P/docs/design/soulad-se-standardy.md"
  [ "$(code "$URL/report")" = 200 ]
  grep -q '&lt;script&gt;alert(1)&lt;/script&gt; &amp; &lt;b&gt;' "$BATS_TEST_TMPDIR/body"
  ! grep -q '<script>' "$BATS_TEST_TMPDIR/body"
}

@test "a preview is 404 (pending) until its file exists, and never outside the studio dir" {
  [ "$(code "$URL/preview?question=q1&card=a")" = 404 ]
  echo png > "$P/.aid-ui/studio/a.png"
  [ "$(code "$URL/preview?question=q1&card=a")" = 200 ]
  echo secret > "$P/secret"
  [ "$(code "$URL/preview?question=q1&card=b")" = 404 ]
}

@test "an invalid payload: 422 naming the problem, the server logs it" {
  echo '{"questions":[{"id":"q1","kind":"nonsense","target":"x","opened_at":"2020-01-01T00:00:00Z"}]}' \
    > "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 422 ]
  grep -q 'unknown kind' "$BATS_TEST_TMPDIR/body"
  grep -q 'invalid payload' "$BATS_TEST_TMPDIR/server.log"
}
