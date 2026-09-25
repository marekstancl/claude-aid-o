#!/usr/bin/env bats
# aid-tier: t0
# P101 Step 5 — aid-ui-state.sh: the direction gate is code. A direction is
# recorded only from Impeccable's own `serve-question --wait` output (a stub
# CLI here); steps 4-6 refuse without it.
# P102 Step 1: state in docs/design/brand-state.json, chapter bodies, fonts,
# finish, migration from docs/brand/state.json.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../aid-ui-state.sh"
  PAGE="$BATS_TEST_DIRNAME/../../../skills/ui-design/brand-page"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/docs/brand"
  cp "$PAGE/index.html" "$PROJ/docs/brand/"
  "$SCRIPT" init "$PROJ" >/dev/null
  STATE="$PROJ/docs/design/brand-state.json"
  HTML="$PROJ/docs/brand/index.html"
  # Stub Impeccable: first prints $STUB_WAITS times "exit 3", then $STUB_OUT with $STUB_RC.
  IMP="$BATS_TEST_TMPDIR/impeccable"
  cat > "$IMP" <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2 $3 $4" == "serve-question --wait --key k1" && "$IMPECCABLE_QUESTION_FORCE" == 1 ]] || exit 9
n=$(cat "$BATS_TEST_TMPDIR/calls" 2>/dev/null || echo 0); echo $((n+1)) > "$BATS_TEST_TMPDIR/calls"
(( n < ${STUB_WAITS:-0} )) && { echo "serve-question: timed out with no answer"; exit 3; }
printf '%s\n' "${STUB_OUT:-}"; exit "${STUB_RC:-0}"
EOF
  chmod +x "$IMP"
  export STUB_WAITS=0 STUB_RC=0 STUB_OUT=""
}

await() { run "$SCRIPT" await-direction "$PROJ" --imp "$IMP" --key k1 --page-url http://10.20.20.22:3915/; }

@test "step 4 without a recorded direction: exit 1, names step 3" {
  run "$SCRIPT" step "$PROJ" 4
  [ "$status" -eq 1 ]
  [[ "$output" == *"step 3"* ]]
  [ "$(jq .step "$STATE")" = 0 ]
}

@test "reroll answer: exit 3, no direction" {
  STUB_OUT='ANSWER: {"optionId":"reroll","steer":""}'
  await
  [ "$status" -eq 3 ]
  [ "$(jq .direction "$STATE")" = null ]
  [ ! -e "$PROJ/.aid-ui/direction-answer.json" ]
}

@test "valid answer after two waits: direction recorded, require-direction and step 4 pass" {
  STUB_WAITS=2 STUB_OUT='ANSWER: {"optionId":"b","steer":"tmavší"}'
  await
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = 3 ]
  [ "$(jq -r .direction.option_id "$STATE")" = b ]
  [ "$(jq -r .direction.page_url "$STATE")" = http://10.20.20.22:3915/ ]
  [[ "$(jq -r .direction.answered_at "$STATE")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  [ "$(jq -r .decisions[0].what "$STATE")" = "direction b" ]
  run "$SCRIPT" require-direction "$PROJ"
  [ "$status" -eq 0 ]
  run "$SCRIPT" step "$PROJ" 4
  [ "$status" -eq 0 ]
  [ "$(jq .step "$STATE")" = 4 ]
}

@test "page closed unanswered (exit 4): direction_pending recorded, exit 1" {
  STUB_RC=4
  await
  [ "$status" -eq 1 ]
  [ "$(jq -r .direction_pending.key "$STATE")" = k1 ]
  [ "$(jq .direction "$STATE")" = null ]
}

@test "await-direction run from another directory: Impeccable is asked from the project" {
  # Impeccable reads .impeccable/questions/<key> from its cwd; elsewhere it says the server is gone (exit 2).
  cat > "$IMP" <<'EOF'
#!/usr/bin/env bash
[[ "$PWD" == "$STUB_PROJ" ]] || { echo "question server is gone"; exit 2; }
echo 'ANSWER: {"optionId":"a","steer":""}'
EOF
  export STUB_PROJ="$PROJ"
  cd "$BATS_TEST_TMPDIR"
  await
  [ "$status" -eq 0 ]
  [ "$(jq -r .direction.option_id "$STATE")" = a ]
}

@test "unparseable output: exit 1, nothing recorded" {
  STUB_OUT='BUILD PATH FLIPPED'
  await
  [ "$status" -eq 1 ]
  [ "$(jq .direction "$STATE")" = null ]
}

@test "answer file edited after recording: require-direction exit 1" {
  STUB_OUT='ANSWER: {"optionId":"a"}'
  await
  echo '{"optionId":"c"}' > "$PROJ/.aid-ui/direction-answer.json"
  run "$SCRIPT" require-direction "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *changed* ]]
}

@test "recorded direction plus a newer pending round: require-direction exit 1 with URL and key" {
  STUB_OUT='ANSWER: {"optionId":"a"}'
  await
  "$SCRIPT" pending-direction "$PROJ" --key k2 --page-url http://10.20.20.22:3915/?r=2
  run "$SCRIPT" require-direction "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"http://10.20.20.22:3915/?r=2"* && "$output" == *k2* ]]
}

@test "recorded direction plus a new round answered reroll: require-direction and step 4 refuse" {
  STUB_OUT='ANSWER: {"optionId":"a"}'
  await
  rm -f "$BATS_TEST_TMPDIR/calls"
  STUB_OUT='ANSWER: {"optionId":"reroll","steer":""}'
  await
  [ "$status" -eq 3 ]
  [ "$(jq -r .direction_pending.key "$STATE")" = k1 ]
  run "$SCRIPT" require-direction "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"http://10.20.20.22:3915/"* ]]
  run "$SCRIPT" step "$PROJ" 4
  [ "$status" -eq 1 ]
  STUB_OUT='ANSWER: {"optionId":"b"}'
  await
  [ "$status" -eq 0 ]
  [ "$(jq .direction_pending "$STATE")" = null ]
  run "$SCRIPT" require-direction "$PROJ"
  [ "$status" -eq 0 ]
}

@test "no verb records a direction from a caller-supplied file" {
  echo '{"optionId":"a"}' > "$BATS_TEST_TMPDIR/fake.json"
  run "$SCRIPT" set "$PROJ" direction '{"option_id":"a"}'
  [ "$status" -eq 2 ]
  run "$SCRIPT" record-direction "$PROJ" "$BATS_TEST_TMPDIR/fake.json"
  [ "$status" -eq 2 ]
  [ "$(jq .direction "$STATE")" = null ]
}

@test "set refs writes; set direction exit 2" {
  run "$SCRIPT" set "$PROJ" refs '[{"url":"https://x.example","why":"písmo","picked":true}]'
  [ "$status" -eq 0 ]
  [ "$(jq -r .refs[0].url "$STATE")" = https://x.example ]
  run "$SCRIPT" set "$PROJ" impeccable.seed_key '"s1"'
  [ "$(jq -r .impeccable.seed_key "$STATE")" = s1 ]
  run "$SCRIPT" set "$PROJ" direction '{}'
  [ "$status" -eq 2 ]
}

@test "roles writes var() aliases; unknown color exit 1" {
  "$BATS_TEST_DIRNAME/../../aid-ui-design-to-css.sh" "$BATS_TEST_DIRNAME/../fixtures/aid-ui/DESIGN.md" "$PROJ/docs/brand/tokens.css"
  run "$SCRIPT" roles "$PROJ" bg=paper,ink=print,accent=print,display=display,body=display
  [ "$status" -eq 0 ]
  grep -qF -- '--brand-bg: var(--color-paper);' "$PROJ/docs/brand/roles.css"
  grep -qF -- '--brand-body-family: var(--font-display-family);' "$PROJ/docs/brand/roles.css"
  [ "$(jq -r .roles.accent "$STATE")" = print ]
  run "$SCRIPT" roles "$PROJ" bg=paper,ink=ghost,accent=print,display=display,body=display
  [ "$status" -eq 1 ]
  [[ "$output" == *ghost* ]]
}

@test "roles aliases only the font suffixes tokens.css defines" {
  "$BATS_TEST_DIRNAME/../../aid-ui-design-to-css.sh" "$BATS_TEST_DIRNAME/../fixtures/aid-ui/DESIGN.md" "$PROJ/docs/brand/tokens.css"
  printf ':root {\n  --font-text-family: Inter, sans-serif;\n  --font-text-size: 1rem;\n}\n' >> "$PROJ/docs/brand/tokens.css"
  run "$SCRIPT" roles "$PROJ" bg=paper,ink=print,accent=print,display=display,body=text
  [ "$status" -eq 0 ]
  grep -qF -- '--brand-body-family: var(--font-text-family);' "$PROJ/docs/brand/roles.css"
  grep -qF -- '--brand-body-size: var(--font-text-size);' "$PROJ/docs/brand/roles.css"
  ! grep -q -- '--brand-body-letter-spacing' "$PROJ/docs/brand/roles.css" || false
  grep -qF -- '--brand-display-letter-spacing: var(--font-display-letter-spacing);' "$PROJ/docs/brand/roles.css"
}

@test "chapter writes state.json and index.html together" {
  run "$SCRIPT" chapter "$PROJ" barvy schvaleno --by PM
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = schvaleno ]
  [ "$(jq -r .chapters.barvy.by "$STATE")" = PM ]
  grep -q '<section id="barvy" data-status="schvaleno">.*<p class="status"><!-- status:barvy -->[0-9-]* · PM<!-- /status:barvy --></p>' "$PROJ/docs/brand/index.html"
  grep -q '<section id="logo" data-status="ceka">' "$PROJ/docs/brand/index.html"
}

@test "reset-approvals turns schvaleno into navrh" {
  "$SCRIPT" chapter "$PROJ" barvy schvaleno --by PM
  run "$SCRIPT" reset-approvals "$PROJ" barvy typografie
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = navrh ]
  [ "$(jq -r .chapters.typografie.status "$STATE")" = ceka ]
  grep -q '<section id="barvy" data-status="navrh">' "$PROJ/docs/brand/index.html"
}

@test "unknown chapter id: exit 2" {
  run "$SCRIPT" chapter "$PROJ" nope navrh
  [ "$status" -eq 2 ]
  run "$SCRIPT" reset-approvals "$PROJ" nope
  [ "$status" -eq 2 ]
}

# --- P102 Step 1 -----------------------------------------------------------

record_direction() { STUB_OUT='ANSWER: {"optionId":"a"}'; await; [ "$status" -eq 0 ]; }

@test "body replaces only its section and is idempotent" {
  echo '<p>Vize projektu</p>' > "$BATS_TEST_TMPDIR/b.html"
  before_logo="$(grep -o '<section id="logo".*</section>' "$HTML")"
  run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/b.html"
  [ "$status" -eq 0 ]
  grep -qF '<!-- body:vize --><p>Vize projektu</p>' "$HTML"
  [ "$(grep -o '<section id="logo".*</section>' "$HTML")" = "$before_logo" ]
  cp "$HTML" "$BATS_TEST_TMPDIR/once.html"
  "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/b.html"
  cmp "$HTML" "$BATS_TEST_TMPDIR/once.html"
  [ -z "$(ls -A "$PROJ/docs/brand" | grep -v '^index.html$')" ]
}

@test "body refuses script, onclick, section and a marker; unknown id exit 2" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in '<script>x()</script>' '<a href="#" onclick="x()">a</a>' '<section id="x"></section>' '<!-- status:logo -->'; do
    printf '%s\n' "$bad" > "$BATS_TEST_TMPDIR/bad.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/bad.html"
    [ "$status" -eq 1 ]
    [[ "$output" == ERROR:*vize* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  run "$SCRIPT" body "$PROJ" nope --file "$BATS_TEST_TMPDIR/bad.html"
  [ "$status" -eq 2 ]
}

@test "body refuses an entity-encoded, split or vbscript/data URL scheme" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in '<a href="jav&#x61;script:alert(1)">a</a>' '<a href="&#106;avascript:alert(1)">a</a>' \
             $'<a href="java\tscript:alert(1)">a</a>' '<a href="javascript&colon;alert(1)">a</a>' \
             '<a href="vbscript:x">a</a>' '<a href="&#100;ata:text/html,x">a</a>'; do
    printf '%s\n' "$bad" > "$BATS_TEST_TMPDIR/bad.html"
    run "$SCRIPT" body "$PROJ" vize --file "$BATS_TEST_TMPDIR/bad.html"
    [ "$status" -eq 1 ]
    [[ "$output" == ERROR:*vize*refused* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
}

@test "a later chapter call leaves a written body byte-identical" {
  printf '<div class="swatch">a</div>\n<p class="note">b</p>\n' > "$BATS_TEST_TMPDIR/b.html"
  "$SCRIPT" body "$PROJ" barvy --file "$BATS_TEST_TMPDIR/b.html"
  body() { sed -n '/<!-- body:barvy -->/,/<!-- \/body:barvy -->/p' "$HTML" | sed -e 's/.*<!-- body:barvy -->//' -e 's/<!-- \/body:barvy -->.*//'; }
  b1="$(body)"
  run "$SCRIPT" chapter "$PROJ" barvy schvaleno --by PM
  [ "$status" -eq 0 ]
  [ "$(body)" = "$b1" ]
  grep -q '<section id="barvy" data-status="schvaleno">' "$HTML"
}

@test "chapter vize accepted" {
  run "$SCRIPT" chapter "$PROJ" vize navrh
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.vize.status "$STATE")" = navrh ]
  grep -q '<section id="vize" data-status="navrh">' "$HTML"
}

# A P101 project: old state.json, old index.html without vize/seo and markers, a written body.
p101_project() {
  rm -rf "$PROJ"; mkdir -p "$PROJ/docs/brand"
  git -C "$BATS_TEST_DIRNAME" show b095ba7f:plugins/aid-orchestrator/skills/ui-design/brand-page/index.html > "$HTML" 2>/dev/null \
    || sed -e 's/<!-- \/\?\(body\|status\):[a-z]* -->//g' -e '/<!-- \/\?fonts -->/d' -e '/id="vize"\|id="seo"\|#vize\|#seo/d' "$PAGE/index.html" > "$HTML"
  sed -i 's|<section id="barvy" data-status="ceka"><h2>Barvy</h2><p class="status"></p><div class="body"></div>|<section id="barvy" data-status="navrh"><h2>Barvy</h2><p class="status">2026-09-24</p><div class="body"><div class="swatch">x</div></div>|' "$HTML"
  jq '.step = 2 | del(.chapters.vize, .chapters.seo, .options, .finished)' "$PAGE/state.template.json" > "$PROJ/docs/brand/state.json"
}

@test "init migrates an old state.json and index.html, keeps bodies" {
  p101_project
  ! grep -q 'id="vize"' "$HTML" || false
  run "$SCRIPT" init "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq .step "$STATE")" = 2 ]
  [ "$(jq -r .chapters.seo.status "$STATE")" = ceka ]
  [ "$(jq -c .options "$STATE")" = '{"vision":false,"identity":false,"seo":false,"images":false}' ]
  [ ! -e "$PROJ/docs/brand/state.json" ]
  [ -f "$PROJ/.aid-ui/state.json.migrated" ]
  [ "$(grep -c '<section ' "$HTML")" -eq 11 ]
  grep -qF '<div class="body"><!-- body:barvy --><div class="swatch">x</div><!-- /body:barvy --></div>' "$HTML"
  grep -qF '<p class="status"><!-- status:barvy -->2026-09-24<!-- /status:barvy --></p>' "$HTML"
  grep -qF '<!-- fonts -->' "$HTML"
  grep -qF '<li><a href="#seo">SEO</a></li>' "$HTML"
  cp "$HTML" "$BATS_TEST_TMPDIR/once.html"
  "$SCRIPT" init "$PROJ"
  cmp "$HTML" "$BATS_TEST_TMPDIR/once.html"
}

@test "retry after an interrupted migration (new file present, markers missing) adds the markers" {
  p101_project
  jq -s '.[0] * .[1]' "$PAGE/state.template.json" "$PROJ/docs/brand/state.json" > "$BATS_TEST_TMPDIR/new.json"
  mkdir -p "$PROJ/docs/design"; mv "$BATS_TEST_TMPDIR/new.json" "$STATE"
  rm "$PROJ/docs/brand/state.json"
  run "$SCRIPT" init "$PROJ"
  [ "$status" -eq 0 ]
  grep -qF '<!-- body:vize -->' "$HTML"
  grep -qF '<!-- status:schvaleni -->' "$HTML"
}

@test "both files present: the new one wins, the old one is renamed" {
  "$SCRIPT" step "$PROJ" 3
  echo '{"step": 1}' > "$PROJ/docs/brand/state.json"
  run "$SCRIPT" init "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq .step "$STATE")" = 3 ]
  [ ! -e "$PROJ/docs/brand/state.json" ]
  [ "$(jq .step "$PROJ/.aid-ui/state.json.migrated")" = 1 ]
}

@test "init with the new file, no index.html and an old state.json moves the old file" {
  rm -rf "$PROJ/.aid-ui" "$HTML"
  echo '{"step": 1}' > "$PROJ/docs/brand/state.json"
  run "$SCRIPT" init "$PROJ"
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/docs/brand/state.json" ]
  [ "$(jq .step "$PROJ/.aid-ui/state.json.migrated")" = 1 ]
}

@test "fonts refuses foreign hosts and paths outside docs/brand/fonts; writes a Google Fonts link idempotently" {
  cp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  for bad in https://evil.example/ https://fonts.googleapis.com.evil.example/css http://fonts.googleapis.com/css \
             https://fonts.googleapis.com@evil.example/ docs/brand/tokens.css ../x.css; do
    run "$SCRIPT" fonts "$PROJ" "$bad"
    [ "$status" -eq 1 ]
    [[ "$output" == ERROR:* ]]
  done
  cmp "$HTML" "$BATS_TEST_TMPDIR/orig.html"
  url='https://fonts.googleapis.com/css2?family=Gloock&family=Inter:wght@400;700&display=swap'
  run "$SCRIPT" fonts "$PROJ" "$url"
  [ "$status" -eq 0 ]
  "$SCRIPT" fonts "$PROJ" "$url"
  [ "$(grep -c 'rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Gloock&amp;family=Inter' "$HTML")" -eq 1 ]
  mkdir -p "$PROJ/docs/brand/fonts"; echo '@font-face{}' > "$PROJ/docs/brand/fonts/local.css"
  run "$SCRIPT" fonts "$PROJ" docs/brand/fonts/local.css
  [ "$status" -eq 0 ]
  grep -qF '<link rel="stylesheet" href="fonts/local.css">' "$HTML"
  ! grep -q 'googleapis' "$HTML" || false
}

@test "finish: before step 6 exit 1, with an open choice exit 1, after that finished set" {
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]
  record_direction
  "$SCRIPT" step "$PROJ" 6
  jq '.choice_pending = {kind: "slogan", key_or_screen: "s", page_url: "http://x/"}' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *slogan* ]]
  jq '.choice_pending = null' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
  run "$SCRIPT" finish "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$(jq -r .finished "$STATE")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

@test "a backward step clears finished; step 7 and step done exit 2" {
  record_direction
  "$SCRIPT" step "$PROJ" 6
  "$SCRIPT" finish "$PROJ"
  "$SCRIPT" step "$PROJ" 6
  [ "$(jq -r .finished "$STATE")" != null ]
  "$SCRIPT" step "$PROJ" 5
  [ "$(jq .finished "$STATE")" = null ]
  run "$SCRIPT" step "$PROJ" 7
  [ "$status" -eq 2 ]
  run "$SCRIPT" step "$PROJ" done
  [ "$status" -eq 2 ]
}

# --- P102 Step 3: options, the companion choice gate, composition ----------

# curl stub on PATH: logs its URL; $STUB_CONFIRM set -> prints it, else 404 (exit 22).
curl_stub() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'EOS'
#!/usr/bin/env bash
echo "${@: -1}" >> "$BATS_TEST_TMPDIR/curl.log"
[[ -n "${STUB_CONFIRM:-}" ]] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
printf '%s\n' "$STUB_CONFIRM"
EOS
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" STUB_CONFIRM=""
}
choice() { run "$SCRIPT" await-choice "$PROJ" --kind "$1" --screen "$2" --page-url http://localhost:3916/; }
confirm() { STUB_CONFIRM="{\"screen\":\"$1\",\"selected\":$2,\"at\":\"$3\"${4:+,\"text\":\"$4\"}}"; }
NEW=2999-01-01T00:00:00.000Z OLD=2000-01-01T00:00:00.000Z

@test "await-choice slogan: 404 pending, older confirm pending, newer recorded once, only /aid/confirmed asked" {
  curl_stub
  choice slogan slogan-1.html
  [ "$status" -eq 1 ]
  [ "$(jq -r .choice_pending.kind "$STATE")" = slogan ]
  [ "$(jq -r .choice_pending.key_or_screen "$STATE")" = slogan-1.html ]
  confirm slogan-1.html '["s2"]' "$OLD"
  choice slogan slogan-1.html
  [ "$status" -eq 1 ]
  [[ "$output" == *predates* ]]
  [ "$(jq .choices.slogan "$STATE")" = null ]
  confirm slogan-1.html '["s2"]' "$NEW"
  choice slogan slogan-1.html
  [ "$status" -eq 0 ]
  [ "$(jq -r .choices.slogan.id "$STATE")" = s2 ]
  [ "$(jq .choice_pending "$STATE")" = null ]
  f="$(jq -r .choices.slogan.answer_file "$STATE")"
  [ "$(sha256sum "$PROJ/$f" | cut -d' ' -f1)" = "$(jq -r .choices.slogan.answer_sha256 "$STATE")" ]
  choice slogan slogan-1.html
  [ "$status" -eq 0 ]
  [ "$(jq '[.decisions[] | select(.what | startswith("slogan"))] | length' "$STATE")" = 1 ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/curl.log")" = "http://localhost:3916/aid/confirmed?screen=slogan-1.html" ]
  [ ! -e "$PROJ/.aid-o/work/companion" ]
}

@test "await-choice: own slogan text recorded; zero cards for logo pending, for pages accepted" {
  curl_stub
  confirm slogan-1.html '[]' "$NEW" "Vaříme po svém"
  choice slogan slogan-1.html
  [ "$status" -eq 0 ]
  [ "$(jq -r .text "$PROJ/$(jq -r .choices.slogan.answer_file "$STATE")")" = "Vaříme po svém" ]
  confirm logo-1.html '[]' "$NEW"
  choice logo logo-1.html
  [ "$status" -eq 1 ]
  [ "$(jq .choices.logo "$STATE")" = null ]
  confirm logo-1.html '["l1"]' "$NEW"
  choice logo logo-1.html
  [ "$status" -eq 0 ]
  confirm pages-1.html '[]' "$NEW" "úvod, ceník"
  choice pages pages-2.html
  [ "$status" -eq 1 ]
  [[ "$output" == *malformed* ]]
  confirm pages-2.html '[]' "$NEW" "úvod, ceník"
  choice pages pages-2.html
  [ "$status" -eq 0 ]
  [ "$(jq -r .choices.pages.screen "$STATE")" = pages-2.html ]
}

@test "await-choice: an open round of another kind refuses exit 1; the same kind's new round replaces it" {
  curl_stub
  choice slogan slogan-1.html
  [ "$status" -eq 1 ]
  choice logo logo-1.html
  [ "$status" -eq 1 ]
  [[ "$output" == *"slogan round is still open on slogan-1.html"* ]]
  [ "$(jq -r .choice_pending.key_or_screen "$STATE")" = slogan-1.html ]
  jq '.choice_pending = {kind: "composition", key_or_screen: "k1", page_url: "http://x/", at: "2000"}' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
  choice pages pages-1.html
  [ "$status" -eq 1 ]
  [[ "$output" == *"composition round is still open on k1"* ]]
  jq '.choice_pending = {kind: "slogan", key_or_screen: "slogan-1.html", page_url: "http://x/", at: "2000"}' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
  choice slogan slogan-2.html
  [ "$status" -eq 1 ]
  [[ "$output" == *"no confirm on slogan-2.html"* ]]
  [ "$(jq -r .choice_pending.key_or_screen "$STATE")" = slogan-2.html ]
}

@test "await-choice: --page-url other than this machine's http server exit 2, nothing asked" {
  curl_stub
  for u in http://evil.example/ -K/etc/passwd https://localhost:3916/ http://localhost.evil.example/; do
    run "$SCRIPT" await-choice "$PROJ" --kind slogan --screen slogan-1.html --page-url "$u"
    [ "$status" -eq 2 ]
  done
  [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
  [ "$(jq .choice_pending "$STATE")" = null ]
}

@test "await-choice composition: another kind's open round refuses exit 1, Impeccable never asked" {
  curl_stub
  choice slogan slogan-1.html
  run "$SCRIPT" await-choice "$PROJ" --kind composition --imp "$IMP" --key k1 --page-url http://10.20.20.22:3915/
  [ "$status" -eq 1 ]
  [[ "$output" == *"slogan round is still open on slogan-1.html"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
  [ "$(jq -r .choice_pending.kind "$STATE")" = slogan ]
}

@test "await-choice: unreachable server and malformed answer record nothing; bad screen name exit 2" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/usr/bin/env bash\nexit 7\n' > "$BATS_TEST_TMPDIR/bin/curl"; chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" choice logo logo-1.html
  [ "$status" -eq 1 ]
  [[ "$output" == *unreachable*"http://localhost:3916/"* ]]
  curl_stub
  STUB_CONFIRM='not json'
  choice logo logo-1.html
  [ "$status" -eq 1 ]
  [ "$(jq .choices "$STATE")" = '{}' ]
  choice logo slogan-1.html
  [ "$status" -eq 2 ]
  run "$SCRIPT" await-choice "$PROJ" --kind nope --screen x --page-url http://x/
  [ "$status" -eq 2 ]
}

@test "set options: validated, refused after step 0" {
  run "$SCRIPT" set "$PROJ" options '{"vision":true,"colour":true}'
  [ "$status" -eq 2 ]
  run "$SCRIPT" set "$PROJ" options '{"identity":true}'
  [ "$status" -eq 2 ]
  run "$SCRIPT" set "$PROJ" options '{"vision":true,"identity":"package","seo":false}'
  [ "$status" -eq 0 ]
  [ "$(jq -c .options "$STATE")" = '{"vision":true,"identity":"package","seo":false,"images":false}' ]
  "$SCRIPT" step "$PROJ" 1
  run "$SCRIPT" set "$PROJ" options '{"vision":false}'
  [ "$status" -eq 1 ]
  [ "$(jq .options.vision "$STATE")" = true ]
}

@test "step gates: open choice blocks any step; enabled options need their choice from step 2" {
  curl_stub
  "$SCRIPT" set "$PROJ" options '{"vision":true,"identity":"package","seo":true}'
  run "$SCRIPT" step "$PROJ" 1
  [ "$status" -eq 0 ]
  run "$SCRIPT" step "$PROJ" 2
  [ "$status" -eq 1 ]
  [[ "$output" == *slogan* && "$output" == *"page list"* && "$output" != *logo* ]]
  choice slogan slogan-1.html
  run "$SCRIPT" step "$PROJ" 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"choice is open"* ]]
  confirm slogan-1.html '["s1"]' "$NEW"; choice slogan slogan-1.html
  confirm pages-1.html '["uvod"]' "$NEW"; choice pages pages-1.html
  run "$SCRIPT" step "$PROJ" 2
  [ "$status" -eq 0 ]
}

@test "identity new needs a logo before step 2" {
  "$SCRIPT" set "$PROJ" options '{"identity":"new"}'
  run "$SCRIPT" step "$PROJ" 3
  [ "$status" -eq 1 ]
  [[ "$output" == *logo* ]]
}

@test "step 5 with build path comp needs a composition; await-choice composition behaves like await-direction" {
  record_direction
  jq '.direction.build_path = "comp"' "$STATE" > "$STATE.t" && mv "$STATE.t" "$STATE"
  "$SCRIPT" step "$PROJ" 4
  run "$SCRIPT" step "$PROJ" 5
  [ "$status" -eq 1 ]
  [[ "$output" == *composition* ]]
  comp() { run "$SCRIPT" await-choice "$PROJ" --kind composition --imp "$IMP" --key k1 --page-url http://10.20.20.22:3915/; }
  STUB_OUT='ANSWER: {"optionId":"reroll","steer":""}'
  comp
  [ "$status" -eq 3 ]
  STUB_RC=4 STUB_OUT=''
  comp
  [ "$status" -eq 1 ]
  [ "$(jq -r .choice_pending.kind "$STATE")" = composition ]
  run "$SCRIPT" step "$PROJ" 5
  [ "$status" -eq 1 ]
  STUB_RC=0 STUB_OUT='ANSWER: {"optionId":"c2"}'
  comp
  [ "$status" -eq 0 ]
  [ "$(jq -r .choices.composition.id "$STATE")" = c2 ]
  [ "$(jq .choice_pending "$STATE")" = null ]
  [ "$(jq -r .direction.option_id "$STATE")" = a ]
  run "$SCRIPT" step "$PROJ" 5
  [ "$status" -eq 0 ]
}
