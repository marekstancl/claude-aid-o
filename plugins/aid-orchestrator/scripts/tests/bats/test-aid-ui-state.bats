#!/usr/bin/env bats
# aid-tier: t0
# P101 Step 5 — aid-ui-state.sh: the direction gate is code. A direction is
# recorded only from Impeccable's own `serve-question --wait` output (a stub
# CLI here); steps 4-6 refuse without it.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../aid-ui-state.sh"
  PAGE="$BATS_TEST_DIRNAME/../../../skills/ui-design/brand-page"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/docs/brand"
  cp "$PAGE/index.html" "$PROJ/docs/brand/"
  "$SCRIPT" init "$PROJ" >/dev/null
  STATE="$PROJ/docs/brand/state.json"
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

@test "chapter writes state.json and index.html together" {
  run "$SCRIPT" chapter "$PROJ" barvy schvaleno --by PM
  [ "$status" -eq 0 ]
  [ "$(jq -r .chapters.barvy.status "$STATE")" = schvaleno ]
  [ "$(jq -r .chapters.barvy.by "$STATE")" = PM ]
  grep -q '<section id="barvy" data-status="schvaleno">.*<p class="status">[0-9-]* · PM</p>' "$PROJ/docs/brand/index.html"
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
