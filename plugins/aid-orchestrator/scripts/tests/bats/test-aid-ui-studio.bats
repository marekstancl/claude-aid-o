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
           {"id": "b", "question": "q1", "title": "B", "preview": "../../secret"},
           {"id": "c", "question": "q1", "title": "C", "preview": "c.html"}]}
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
  [ "$(code -H 'Referer: http://evil.example/' "$URL/state")" = 403 ]            # data: same origin only
  [ "$(code -H 'Referer: https://claude.ai/' "$URL/")" = 403 ]                   # the page opens from another app
  grep -q "Otevřete odkaz ze zprávy agenta" "$BATS_TEST_TMPDIR/body"            # (no cookie: the no-access page)
  [ "$(code -H 'Host: evil.example' "$URL/")" = 403 ]
  ! grep -q "Otevřete odkaz" "$BATS_TEST_TMPDIR/body"
}

@test "without a cookie or a valid code the page says to open the agent's link and holds no token or state" {
  [ "$(code "$URL/")" = 403 ]
  grep -q "Otevřete odkaz ze zprávy agenta" "$BATS_TEST_TMPDIR/body"
  ! grep -q "$TOKEN" "$BATS_TEST_TMPDIR/body"
  ! grep -q "Vyberte směr" "$BATS_TEST_TMPDIR/body"
  [ "$(code "$URL/?k=wrongcode")" = 403 ]
  ! grep -q "$TOKEN" "$BATS_TEST_TMPDIR/body"
}

@test "the one-time code works once: cookie set, redirect to /, page without the token; reuse refused" {
  echo 99887766554433221100aabbccddeeff > "$P/.aid-ui/studio.code"
  J="$BATS_TEST_TMPDIR/jar"
  curl -s -D "$BATS_TEST_TMPDIR/h" -o /dev/null -c "$J" "$URL/?k=99887766554433221100aabbccddeeff"
  grep -q '^HTTP/1.[01] 303' "$BATS_TEST_TMPDIR/h"
  grep -qi '^location: /\s*$' "$BATS_TEST_TMPDIR/h"
  grep -qi '^set-cookie: aid_studio=.*HttpOnly.*SameSite=Strict' "$BATS_TEST_TMPDIR/h"
  [ ! -e "$P/.aid-ui/studio.code" ]
  [ "$(code -b "$J" "$URL/")" = 200 ]
  grep -q "AID studio" "$BATS_TEST_TMPDIR/body"
  ! grep -q "$TOKEN" "$BATS_TEST_TMPDIR/body"
  [ "$(code -b "$J" "$URL/state")" = 200 ]                                          # the page works via the cookie
  [ "$(code "$URL/?k=99887766554433221100aabbccddeeff")" = 403 ]                    # used once
  grep -q 'http-equiv="refresh" content="0;url=/"' "$BATS_TEST_TMPDIR/body"          # a signed-in PM lands on /
  ! grep -qi 'set-cookie' "$BATS_TEST_TMPDIR/body"
  [ "$(code "$URL/")" = 403 ]                                                       # no cookie: no access, no loop
  ! grep -q 'http-equiv="refresh"' "$BATS_TEST_TMPDIR/body"
}

@test "the session cookie authorises POST /answer; the header token still works for GET /answer" {
  echo 00112233445566778899aabbccddeeff > "$P/.aid-ui/studio.code"
  J="$BATS_TEST_TMPDIR/jar"
  curl -s -o /dev/null -c "$J" "$URL/?k=00112233445566778899aabbccddeeff"
  [ "$(code -b 'aid_studio=forged' -H 'Content-Type: application/json' -d "$choose_a" "$URL/answer")" = 403 ]
  [ "$(code -b "$J" -H 'Content-Type: application/json' -H "Origin: $URL" -d "$choose_a" "$URL/answer")" = 200 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/answer?question=q1")" = 200 ]
  [ "$(jq -r .choice "$BATS_TEST_TMPDIR/body")" = a ]
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

@test "the answer keeps the cards as served when it was given; a later payload edit does not change them" {
  jq '.cards[0] += {url: "https://a.example", thesis: "písmo", palette: ["#000"]}' "$P/.aid-ui/studio/payload.json" > "$P/p.t" \
    && mv "$P/p.t" "$P/.aid-ui/studio/payload.json"
  printf 'PNG1' > "$P/.aid-ui/studio/a.png"; echo s > "$P/secret"
  [ "$(answer "$choose_a")" = 200 ]
  png="$(printf 'PNG1' | sha256sum | cut -d' ' -f1)"
  want='[{"id":"a","palette":["#000"],"preview":"a.png","preview_sha256":"'"$png"'","risk":null,"thesis":"písmo","title":"A","uniqueness":null,"url":"https://a.example"},{"id":"b","palette":null,"preview":"../../secret","preview_sha256":null,"risk":null,"thesis":null,"title":"B","uniqueness":null,"url":null},{"id":"c","palette":null,"preview":"c.html","preview_sha256":null,"risk":null,"thesis":null,"title":"C","uniqueness":null,"url":null}]'
  [ "$(jq -S -c .cards "$BATS_TEST_TMPDIR/body")" = "$want" ]
  sha="$(printf '%s' "$want" | sha256sum | cut -d' ' -f1)"
  [ "$(jq -r .cards_sha256 "$BATS_TEST_TMPDIR/body")" = "$sha" ]
  # the agent rewrites the chosen card's url, thesis and preview image, adds a card and drops one
  printf 'PNG2' > "$P/.aid-ui/studio/a.png"
  jq '.cards[0] += {url: "https://evil.example", thesis: "jiné"} | .cards[1].title = "X" | .cards |= (.[0:2] + [{id: "d", question: "q1"}])' \
    "$P/.aid-ui/studio/payload.json" > "$P/p.t" && mv "$P/p.t" "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/answer?question=q1")" = 200 ]
  [ "$(jq -S -c .cards "$BATS_TEST_TMPDIR/body")" = "$want" ]
  [ "$(jq -r .cards_sha256 "$BATS_TEST_TMPDIR/body")" = "$sha" ]
  # a question without cards keeps an empty list
  [ "$(answer '{"question":"q2","kind":"approve_page","target":"home@abc","decision":"approve"}')" = 200 ]
  [ "$(jq -c .cards "$BATS_TEST_TMPDIR/body")" = '[]' ]
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

@test "a preview that is not a raster image is refused (415); an image is sandboxed and nosniff" {
  echo '<script>alert(1)</script>' > "$P/.aid-ui/studio/c.html"
  [ "$(code "$URL/preview?question=q1&card=c")" = 415 ]
  echo png > "$P/.aid-ui/studio/a.png"
  curl -s -D "$BATS_TEST_TMPDIR/h" -o /dev/null "$URL/preview?question=q1&card=a"
  grep -qi '^content-type: image/png' "$BATS_TEST_TMPDIR/h"
  grep -qi '^x-content-type-options: nosniff' "$BATS_TEST_TMPDIR/h"
  grep -qi "^content-security-policy: sandbox; default-src 'none'" "$BATS_TEST_TMPDIR/h"
}

@test "every response forbids framing" {
  for path in / /state /nonexistent; do
    curl -s -D "$BATS_TEST_TMPDIR/h" -o /dev/null "$URL$path"
    grep -qi '^x-frame-options: DENY' "$BATS_TEST_TMPDIR/h"
    grep -qi "^content-security-policy: .*frame-ancestors 'none'" "$BATS_TEST_TMPDIR/h"
  done
}

@test "cards: an id twice in one question, an empty id or no question make the payload invalid (422, logged)" {
  q='{"id":"q1","kind":"direction","target":"home@abc","opened_at":"2020-01-01T00:00:00Z"}'
  for cards in '[{"id":"a","question":"q1","url":"https://a.example"},{"id":"a","question":"q1","url":"https://evil.example"}]' \
               '[{"id":"a","question":"q1"},{"id":"b","question":"q1"},{"id":"a","question":"q1"}]' \
               '[{"id":"","question":"q1"}]' '[{"question":"q1"}]' '[{"id":"a"}]' '["a"]'; do
    echo "{\"questions\":[$q],\"cards\":$cards}" > "$P/.aid-ui/studio/payload.json"
    [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 422 ]
    [ "$(answer "$choose_a")" = 422 ]
  done
  grep -q 'card id a twice in question q1' "$BATS_TEST_TMPDIR/server.log"
  grep -q 'invalid payload: payload.json: every card needs' "$BATS_TEST_TMPDIR/server.log"
  # the same id in two questions is fine: ids are unique per question
  echo "{\"questions\":[$q],\"cards\":[{\"id\":\"a\",\"question\":\"q1\"},{\"id\":\"a\",\"question\":\"q2\"}]}" \
    > "$P/.aid-ui/studio/payload.json"
  [ "$(answer "$choose_a")" = 200 ]
}

@test "an invalid payload: 422 naming the problem, the server logs it" {
  echo '{"questions":[{"id":"q1","kind":"nonsense","target":"x","opened_at":"2020-01-01T00:00:00Z"}]}' \
    > "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 422 ]
  grep -q 'unknown kind' "$BATS_TEST_TMPDIR/body"
  grep -q 'invalid payload' "$BATS_TEST_TMPDIR/server.log"
}

@test "reroll (Znovu) closes its question and opens <id>.r1 like reroll_safer/bolder" {
  [ "$(answer '{"question":"q1","kind":"direction","target":"home@abc","decision":"reroll"}')" = 200 ]
  [ "$(jq -r .next_question "$BATS_TEST_TMPDIR/body")" = q1.r1 ]
  [ "$(answer "$choose_a")" = 409 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -r '.questions[] | select(.id=="q1.r1") | "\(.kind) \(.target) \(.answered)"' "$BATS_TEST_TMPDIR/body")" = "direction home@abc false" ]
  [ "$(answer '{"question":"q1","kind":"direction","target":"home@abc","decision":"rerollx"}')" = 422 ]
}

@test "/state passes through now, steps[].description and questions[].next/body" {
  jq '.now = {title: "Teď", text: "Připravuji tři návrhy vzhledu…"} | .steps[0].description = "Vybíráte vzhled."
      | .questions[0] += {next: "Připravím stránky.", body: ["Věta jedna."]}' "$P/.aid-ui/studio/payload.json" > "$P/p.t" \
    && mv "$P/p.t" "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -r '.now.text' "$BATS_TEST_TMPDIR/body")" = "Připravuji tři návrhy vzhledu…" ]
  [ "$(jq -r '.steps[0].description' "$BATS_TEST_TMPDIR/body")" = "Vybíráte vzhled." ]
  [ "$(jq -r '.questions[0] | "\(.next) \(.body[0])"' "$BATS_TEST_TMPDIR/body")" = "Připravím stránky. Věta jedna." ]
  rm "$P/.aid-ui/studio/payload.json"   # no payload: now is null, not an error
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -c .now "$BATS_TEST_TMPDIR/body")" = null ]
}

@test "/state shows what was decided for answered questions: decision, chosen card title, comment" {
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -c '.questions[0].answer' "$BATS_TEST_TMPDIR/body")" = null ]      # open: no answer field
  [ "$(answer '{"question":"q1","kind":"direction","target":"home@abc","decision":"choose","choice":"b"}')" = 200 ]
  [ "$(answer '{"question":"q2","kind":"approve_page","target":"home@abc","decision":"return","comment":"menší logo"}')" = 200 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -S -c '.questions[] | select(.id=="q1") | .answer' "$BATS_TEST_TMPDIR/body")" = '{"choice":"b","choice_title":"B","comment":"","decision":"choose"}' ]
  [ "$(jq -S -c '.questions[] | select(.id=="q2") | .answer' "$BATS_TEST_TMPDIR/body")" = '{"choice":null,"choice_title":null,"comment":"menší logo","decision":"return"}' ]
  # the title is the one the PM saw, not a later payload edit
  jq '.cards[1].title = "X"' "$P/.aid-ui/studio/payload.json" > "$P/p.t" && mv "$P/p.t" "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -r '.questions[] | select(.id=="q1") | .answer.choice_title' "$BATS_TEST_TMPDIR/body")" = B ]
}

@test "/brand/ serves the project's brand page with the studio tabs, only with auth and only its own files" {
  mkdir -p "$P/docs/brand/assets" "$P/docs/brand/sub"
  printf '<!doctype html><body><h1>X</h1></body>' > "$P/docs/brand/index.html"
  printf 'body{}' > "$P/docs/brand/base.css"
  printf 'x' > "$P/docs/brand/assets/logo.svg"
  printf '{}' > "$P/docs/brand/state.json"
  printf 'x' > "$P/docs/brand/sub/a.css"
  printf 's' > "$P/secret.css"
  [ "$(code "$URL/brand/")" = 403 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/brand/")" = 200 ]
  grep -q 'class="studio-tabs"' "$BATS_TEST_TMPDIR/body"
  grep -q '<h1>X</h1>' "$BATS_TEST_TMPDIR/body"
  ! grep -q 'studio-tabs' "$P/docs/brand/index.html" || false
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/brand/base.css")" = 200 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/brand/assets/logo.svg")" = 200 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/brand/state.json")" = 404 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/brand/sub/a.css")" = 404 ]
  [ "$(code -H "X-AID-Token: $TOKEN" --path-as-is "$URL/brand/../../secret.css")" = 404 ]
  curl -s -D "$BATS_TEST_TMPDIR/h" -o /dev/null -H "X-AID-Token: $TOKEN" "$URL/brand/"
  grep -qi "content-security-policy: default-src 'none'" "$BATS_TEST_TMPDIR/h"
}

@test "an accepted answer is kept in the history with the question, its cards and a copy of the preview; /history serves it" {
  printf 'PNG1' > "$P/.aid-ui/studio/a.png"
  payload '2020-01-01T00:00:00Z'
  [ "$(answer "$choose_a")" = 200 ]
  [ -f "$P/.aid-ui/studio/history.jsonl" ]
  jq -e 'select(.question.id == "q1") | .answer.decision == "choose" and .answer.choice == "a"
         and (.cards | length) == 3 and .step == "Směr"' "$P/.aid-ui/studio/history.jsonl" >/dev/null
  kept="$(jq -r 'select(.question.id == "q1") | .cards[] | select(.id == "a") | .preview' "$P/.aid-ui/studio/history.jsonl")"
  [ "$kept" = "history/q1/a.png" ]
  # a later change of the live preview does not change what the history shows
  printf 'PNG2' > "$P/.aid-ui/studio/a.png"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/history/preview?question=q1&card=a")" = 200 ]
  [ "$(cat "$BATS_TEST_TMPDIR/body")" = PNG1 ]
  # cards whose preview is not a raster file inside the studio keep no preview
  [ "$(jq -r 'select(.question.id == "q1") | [.cards[] | select(.id != "a") | .preview] | map(. == null) | all' "$P/.aid-ui/studio/history.jsonl")" = true ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/history")" = 200 ]
  jq -e 'length == 1 and .[0].question.title == "Vyberte směr"' "$BATS_TEST_TMPDIR/body" >/dev/null
  [ "$(code "$URL/history")" = 403 ]
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/history/preview?question=q1&card=b")" = 404 ]
}

@test "overview: passed through /state; a wrong type or a non-http site_url makes the payload invalid" {
  jq '.overview = {site_url: "http://10.20.20.22:3913/", todo: [{what: "Portrét", how: "Pošlete fotku", blocking: false}]}' \
    "$P/.aid-ui/studio/payload.json" > "$P/p.json" && mv "$P/p.json" "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 200 ]
  [ "$(jq -r .overview.todo[0].what "$BATS_TEST_TMPDIR/body")" = "Portrét" ]
  jq '.overview.site_url = "javascript:alert(1)"' "$P/.aid-ui/studio/payload.json" > "$P/p.json" && mv "$P/p.json" "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 422 ]
  jq '.overview = {todo: [{what: "x", blocking: "ano"}]}' "$P/.aid-ui/studio/payload.json" > "$P/p.json" && mv "$P/p.json" "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 422 ]
  jq '.overview = {todo: [{how: "x"}]}' "$P/.aid-ui/studio/payload.json" > "$P/p.json" && mv "$P/p.json" "$P/.aid-ui/studio/payload.json"
  [ "$(code -H "X-AID-Token: $TOKEN" "$URL/state")" = 422 ]
}
