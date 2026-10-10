#!/usr/bin/env bats
# aid-tier: t1
# test-plan-diff-step.bats — the brief's points run after every step
# (aid-plan-diff.sh --step N --plan-json, P110 Step 2) and in isolation at the
# close (--isolated --cwd, P110 Step 3). Local commands only (true, false,
# sleep, a local listener); the namespace cases skip where the nested unshare
# probe is refused.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PD="$AID_PLUGIN_PATH/scripts/aid-plan-diff.sh"
  ROOT="$(mktemp -d)"; cd "$ROOT"
  git init -q .; git config user.email t@t; git config user.name t
  echo x > seed; git add seed; git commit -qm seed
  PLAN="$ROOT/plan.md"; EV="$ROOT/ev"; mkdir -p "$EV"
  _plan
}
teardown() { rm -rf "$ROOT"; }

# _blk <cmd> [timeout] — a verification_pattern block under the bullet before it
_blk() {
  printf '  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "%s"\n    expected_exit: 0\n' "$1"
  [[ -n "${2:-}" ]] && printf '    timeout: %s\n' "$2"
  printf '  ```\n'
}
# _plan — five steps; AC3 is named by steps 3 and 5; step 4 closes nothing but
# has its own labelled criterion; step 2 has neither.
_plan() {
  {
    printf -- '---\nid: P950\n---\n# Plan\n\n## Implementation Steps\n\n'
    printf '### Step 1: one\n\n- [ ] [backend] step one own check\n'; _blk "test -f one.txt"
    printf '\n**Zavírá:** AC1\n\n'
    printf '### Step 2: two\n\n**Zavírá:** —\n\n'
    printf '### Step 3: three\n\n**Zavírá:** AC3, AC2\n\n'
    printf '### Step 4: four\n\n- [ ] [backend] step four own check\n'; _blk "test -f four.txt"
    printf '\n**Zavírá:** —\n\n'
    printf '### Step 5: five\n\n**Zavírá:** AC3, AC4\n\n'
    printf '## Acceptance Criteria\n\n'
    printf -- '- [ ] AC1: one\n'; _blk "true"
    printf -- '- [ ] AC2: two fails\n'; _blk "false"
    printf -- '- [ ] AC3: three\n'; _blk "true"
    printf -- '- [ ] AC4: slow\n'; _blk "sleep 5" 2
  } > "$PLAN"
}
# _pj <plan_step:zavira>... — a plan.json with one step per argument ("1:AC1", "2:", "3:AC3,AC2")
_pj() {
  local a ps z out='[]'
  for a in "$@"; do
    ps="${a%%:*}"; z="${a#*:}"
    out="$(jq -c --arg ps "$ps" --arg z "$z" '. + [{id: "step_\($ps)_backend", plan_step: (if $ps == "null" then null else ($ps | tonumber) end), zavira: ($z | split(",") | map(select(. != "")))}]' <<< "$out")"
  done
  jq -n --argjson s "$out" '{steps: $s}' > "$ROOT/plan.json"
}
_run() { run bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD --plan-json "$ROOT/plan.json" "$@"; }
_out() { cat "$EV/cp2/step-$1/plan-diff.json"; }
# _card <text> [answered] — a Decision card quoting <text>; answered: a PM prompt after it
_card() {
  CARD="$ROOT/card-$RANDOM.md"; echo "Rozhodnutí 1: $1" > "$CARD"; touch -d '-10 seconds' "$CARD"
  export AID_HOOK_AUDIT="$ROOT/audit.jsonl"; : > "$AID_HOOK_AUDIT"
  [[ "${2:-}" == answered ]] && printf '{"ts":"%s","event":"UserPromptSubmit","rule":"pm_reply_marker"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$AID_HOOK_AUDIT"
  return 0
}

@test "step: --step 0 runs the step's brief point and its own criterion and writes cp2/step-0/plan-diff.json bound to HEAD" {
  _pj "1:AC1" "2:" "3:AC3,AC2"
  touch one.txt
  _run --step 0; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_out 0 | jq -r .scope)" = step ] && [ "$(_out 0 | jq -r .plan_step)" = 1 ] && [ "$(_out 0 | jq -r .step)" = 0 ]
  [ "$(_out 0 | jq -r .head_commit)" = "$(git rev-parse HEAD)" ]
  [ "$(_out 0 | jq -c '[.results[] | .verdict]')" = '["present","present"]' ]
  [ "$(_out 0 | jq -r '.results[0].ac_label')" = AC1 ]
}
@test "step: an EPIC whose first step is plan step 4 reads the ### Step 4: section" {
  _pj "4:" "5:AC3,AC4"
  _run --step 0; echo "$output"; [ "$status" -eq 1 ]
  [ "$(_out 0 | jq -r .plan_step)" = 4 ]
  [ "$(_out 0 | jq -r '.results[0].ac_text')" = "step four own check" ]
  [ "$(_out 0 | jq -r '.results[0].verdict')" = absent ]
}
@test "step: a point a later plan step also names is deferred_to_step there, read from the plan file not plan.json" {
  _pj "1:AC1" "2:" "3:AC3,AC2"
  _run --step 2; echo "$output"; [ "$status" -eq 1 ]
  [ "$(_out 2 | jq -r '.results[] | select(.ac_label == "AC3") | .deferred_to_step')" = 5 ]
  [ "$(_out 2 | jq -r '.results[] | select(.ac_label == "AC3") | .verdict')" = skipped ]
  [ "$(_out 2 | jq -r '.results[] | select(.ac_label == "AC2") | .verdict')" = absent ]
}
@test "step: a step with neither points nor own criteria writes unmeasured_step and exits 2" {
  _pj "1:AC1" "2:"
  _run --step 1; echo "$output"; [ "$status" -eq 2 ]
  [ "$(_out 1 | jq -r .unmeasured_step)" = true ]
}
@test "step: a step that closes no point runs its own labelled block" {
  _pj "4:"
  touch four.txt
  _run --step 0; [ "$status" -eq 0 ]
  [ "$(_out 0 | jq -r '.results | length')" = 1 ] && [ "$(_out 0 | jq -r '.results[0].verdict')" = present ]
}
@test "step: a failing cmd is absent with its exit code" {
  _pj "3:AC2"
  _run --step 0; [ "$status" -eq 1 ]
  [[ "$(_out 0 | jq -r '.results[0].evidence')" == "exit=1"* ]]
}
@test "step: a block's timeout: is used — sleep 5 with timeout 2 is absent (reason=timeout)" {
  _pj "5:AC4"
  _run --step 0; [ "$status" -eq 1 ]
  [[ "$(_out 0 | jq -r '.results[] | select(.ac_label == "AC4") | .evidence')" == *"timeout after 2s (reason=timeout)"* ]]
}
@test "step: timeout: 2000 is refused by the shared validator, 900 accepted" {
  source "$AID_PLUGIN_PATH/scripts/lib/aid-verification-pattern.sh"
  run _aid_vp_validate $'AC1\x1ft\x1fcmd\x1ftrue\x1f\x1f\x1f0\x1f2000'
  [ "$status" -eq 1 ]; [[ "$output" == *"timeout '2000' must be whole seconds from 1 to 1800"* ]]
  run _aid_vp_validate $'AC1\x1ft\x1fcmd\x1ftrue\x1f\x1f\x1f0\x1f900'
  [ "$status" -eq 0 ]
}
@test "step: a deferred.json entry whose card the PM never answered is dropped and the point refuses" {
  _pj "3:AC2"
  _card AC2
  mkdir -p "$EV/cp2/step-0"
  jq -n --arg c "$CARD" '{AC2: {by: "pm", reason: "the PM moved this point to the close", card: $c}}' > "$EV/cp2/step-0/deferred.json"
  _run --step 0; echo "$output"; [ "$status" -eq 1 ]
  [[ "$output" == *"deferral of AC2 not honoured: no PM prompt after"* ]]
  [ "$(_out 0 | jq -r '.results[0].deferred')" = null ]
}
@test "step: an answered deferral is merged into the results after a re-measurement, and the point no longer refuses" {
  _pj "3:AC2"
  _card AC2 answered
  mkdir -p "$EV/cp2/step-0"
  jq -n --arg c "$CARD" '{AC2: {by: "pm", reason: "the PM moved this point to the close", card: $c}}' > "$EV/cp2/step-0/deferred.json"
  _run --step 0; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_out 0 | jq -r '.results[0].verdict')" = absent ]
  [ "$(_out 0 | jq -r '.results[0].deferred.by')" = pm ]
  [ "$(_out 0 | jq -r '.summary.absent_count')" = 0 ]
}
