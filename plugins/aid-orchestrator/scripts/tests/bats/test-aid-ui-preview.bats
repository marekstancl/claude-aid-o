#!/usr/bin/env bats
# aid-tier: t1
# P113a step 6 (AC8) - aid-ui-preview.py: the static preview and its form receiver. A complete message is
# delivered to .aid-ui/inbox (mode 600) once, a repeat is not delivered again, an empty required field is 422 with
# its name, a filled spam trap is dropped, an oversized body is 413, other POSTs are 404, no config = no receiver;
# the log holds no sent value.

setup() {
  PV="$BATS_TEST_DIRNAME/../../aid-ui-preview.py"; T="$BATS_TEST_TMPDIR"; P="$T/p"; mkdir -p "$P/site" "$P/.aid-ui"
  echo '<html>x</html>' > "$P/site/index.html"; echo secret > "$P/site/.env"
  echo '{"endpoint": "/api/objednanie", "required": ["meno", "telefon"], "honeypot": "website", "max_field": 50}' > "$P/.aid-ui/form.json"
  PORT=$(( 37000 + RANDOM % 900 )); python3 "$PV" "$PORT" 127.0.0.1 "$P/site" "$P" 2>"$T/log" & SRV=$!
  U="http://127.0.0.1:$PORT"; for _ in $(seq 50); do curl -s "$U/" >/dev/null && return 0; sleep 0.1; done; return 1
}
teardown() { kill "$SRV" 2>/dev/null || true; }
post() { curl -s -o "$T/body" -w '%{http_code}' -X POST "$@"; }

@test "the receiver delivers once, refuses incomplete, drops spam, limits size; static stays static; the log is clean" {
  [ "$(post "$U/api/objednanie" -d 'meno=Jana Testová&telefon=+421905111222&sprava=bolí ma zub')" = 200 ]
  jq -e '.ok and (.id | length) == 8' "$T/body" >/dev/null
  f="$(ls "$P/.aid-ui/inbox/"*.json)"; [ "$(stat -c %a "$f")" = 600 ]
  jq -e '.fields.meno == "Jana Testová" and .fields.sprava == "bolí ma zub"' "$f" >/dev/null
  # the same message again: answered, not delivered twice; JSON and multipart are read too
  [ "$(post "$U/api/objednanie" -d 'meno=Jana Testová&telefon=+421905111222&sprava=bolí ma zub')" = 200 ]; jq -e '.duplicate == true' "$T/body" >/dev/null
  [ "$(ls "$P/.aid-ui/inbox" | wc -l)" -eq 1 ]
  [ "$(post "$U/api/objednanie" -H 'Content-Type: application/json' -d '{"meno": "Peter", "telefon": "0905"}')" = 200 ]
  [ "$(post "$U/api/objednanie" -F meno=Eva -F telefon=0911)" = 200 ]; [ "$(ls "$P/.aid-ui/inbox" | wc -l)" -eq 3 ]
  # incomplete, too long, spam, elsewhere
  [ "$(post "$U/api/objednanie" -d 'meno=Jana')" = 422 ]; jq -e '.field == "telefon"' "$T/body" >/dev/null
  [ "$(post "$U/api/objednanie" -d "meno=$(printf 'x%.0s' {1..60})&telefon=1")" = 422 ]
  [ "$(post "$U/api/objednanie" -d 'meno=Bot&telefon=1&website=http://spam')" = 200 ]; [ "$(ls "$P/.aid-ui/inbox" | wc -l)" -eq 3 ]
  head -c 40000 /dev/zero | tr '\0' 'a' > "$T/big"; [ "$(post "$U/api/objednanie" --data-binary "@$T/big" --max-time 5)" = 413 ]
  [ "$(post "$U/api/jine" -d 'a=b')" = 404 ]
  # a negative or a missing length is refused without reading the body; a full inbox refuses more
  [ "$(post "$U/api/objednanie" -H 'Content-Length: -5' -d '')" = 413 ] || [ "$(post "$U/api/objednanie" -H 'Content-Length: -5' -d '')" = 400 ]
  [ "$(post "$U/api/objednanie" -H 'Transfer-Encoding: chunked' -d 'meno=a&telefon=b')" = 411 ]
  for i in $(seq 1 497); do : > "$P/.aid-ui/inbox/x$i.json"; done
  [ "$(post "$U/api/objednanie" -d 'meno=Plna&telefon=9')" = 503 ]; rm "$P/.aid-ui/inbox/"x*.json
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$U/.env")" = 404 ]
  # no value in the log, only status and id
  ! grep -qE "Jana|421905111222|bolí|Peter|Eva|0911|Bot|spam" "$T/log"
  grep -q "FORM 200 delivered" "$T/log"; grep -q "FORM 200 spam dropped" "$T/log"; grep -q "FORM 422 missing telefon" "$T/log"
  # no form.json: no receiver
  rm "$P/.aid-ui/form.json"; [ "$(post "$U/api/objednanie" -d 'meno=a&telefon=b')" = 404 ]
}
