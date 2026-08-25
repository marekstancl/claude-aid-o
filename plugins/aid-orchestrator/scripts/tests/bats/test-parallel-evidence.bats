#!/usr/bin/env bats
# aid-tier: t0
# test-parallel-evidence.bats — two steps returning at once leave two evidence
# directories and two commits, never one of either (P087 Step 2).
#
# What is under test is the controller's serial point: every accepted return
# gets its OWN subdirectory (aid-fsm.sh step-evidence-dir) and its OWN commit
# (aid_dispatch_contract_commit), and a return that wrote into another step's
# directory is refused before any of that. No agent runs; the two "agents" are
# two files written by the test.

load test-helpers.bash

setup() {
  setup_test_evidence_dir E-par R-par
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-dispatch-contract.sh"
  cat > "$TEST_EVIDENCE_DIR/plan.json" <<'JSON'
{"steps":[
  {"id":"step_1_backend","role":"backend","objective":"write a","outputs":["Create: `a.txt` — a"],"allowed_paths":["a.txt"]},
  {"id":"step_2_frontend","role":"frontend","objective":"write b","outputs":["Create: `b.txt` — b"],"allowed_paths":["b.txt"]}
],"dependencies":[]}
JSON
  printf 'epic_id: E-par\nrun_id: R-par\nstate: EXECUTE\ncurrent_step: 0\ntotal_steps: 2\n' > "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  STATE="$TEST_EVIDENCE_DIR/fsm-state.yaml"
}
teardown() { teardown_test_evidence_dir; }

# _agent <idx> <file> — "the agent" leaves its artifact and its return, in
# the step's own evidence directory (inside .aid-o, which the disk check
# excludes — evidence is state, not a change to the tree).
_agent() {
  local dir; dir="$(bash "$FSM" step-evidence-dir "$STATE" "$1")"
  aid_dispatch_contract_build "$TEST_EVIDENCE_DIR/plan.json" "$1" "$dir/contract.json" "$TEST_EVIDENCE_DIR"
  printf 'content %s\n' "$1" > "$2"
  jq -n --arg v "$(jq -r .version "$dir/contract.json")" --arg f "$2" \
    '{contract_version: $v, changed_files: [$f], gates: [], step_status: "done"}' > "$dir/return.json"
  printf '%s' "$dir"
}

@test "evidence: AC5 — each step gets its own subdirectory under the run, named by step id" {
  # At the state root the path is printed RELATIVE, like every other evidence
  # path aid-fsm.sh prints there; compared physically.
  run bash "$FSM" step-evidence-dir "$STATE" 0
  [ "$status" -eq 0 ]
  [ "$(realpath "$output")" = "$(realpath "$TEST_EVIDENCE_DIR")/steps/step_1_backend" ]
  run bash "$FSM" step-evidence-dir "$STATE" 1
  [ "$(realpath "$output")" = "$(realpath "$TEST_EVIDENCE_DIR")/steps/step_2_frontend" ]
  [ -d "$TEST_EVIDENCE_DIR/steps/step_1_backend" ]
  [ -d "$TEST_EVIDENCE_DIR/steps/step_2_frontend" ]
}

@test "evidence: a step index the plan does not have is an error, not an empty directory" {
  run bash "$FSM" step-evidence-dir "$STATE" 7
  [ "$status" -eq 1 ]
  [[ "$output" == *"no step at index 7"* ]]
  [ ! -d "$TEST_EVIDENCE_DIR/steps" ]
}

@test "evidence: AC4 — the whole serial point, twice: own directory, contract, return, validation, commit — two commits, each holding only its own files" {
  before="$(git rev-list --count HEAD)"
  d0="$(_agent 0 a.txt)"
  [[ "$d0" == *"/steps/step_1_backend" ]]
  sha0="$(aid_dispatch_contract_commit . "$d0/contract.json" "$d0/return.json" "step 1: a")"
  d1="$(_agent 1 b.txt)"
  [[ "$d1" == *"/steps/step_2_frontend" ]]
  sha1="$(aid_dispatch_contract_commit . "$d1/contract.json" "$d1/return.json" "step 2: b")"
  [ "$(git rev-list --count HEAD)" -eq $((before + 2)) ]
  [ "$(git show --name-only --format= "$sha0")" = "a.txt" ]
  [ "$(git show --name-only --format= "$sha1")" = "b.txt" ]
  [ -z "$(git status --porcelain --untracked-files=no)" ]
}

@test "evidence: a step that changed nothing makes no commit, and says so" {
  : > a.txt; git add a.txt; git commit -q -m "a.txt already there"   # the promised artifact exists
  d0="$(bash "$FSM" step-evidence-dir "$STATE" 0)"
  aid_dispatch_contract_build "$TEST_EVIDENCE_DIR/plan.json" 0 "$d0/contract.json"
  jq -n --arg v "$(jq -r .version "$d0/contract.json")" '{contract_version: $v, changed_files: [], gates: [], step_status: "done"}' > "$d0/return.json"
  before="$(git rev-list --count HEAD)"
  run aid_dispatch_contract_commit . "$d0/contract.json" "$d0/return.json" "step 1: nothing"
  [ "$status" -eq 0 ]
  [ "$output" = "nothing to commit" ]
  [ "$(git rev-list --count HEAD)" -eq "$before" ]
}

@test "evidence: AC6 — a return that wrote into another step's directory is refused" {
  d0="$(bash "$FSM" step-evidence-dir "$STATE" 0)"
  aid_dispatch_contract_build "$TEST_EVIDENCE_DIR/plan.json" 0 "$d0/contract.json"
  jq -n --arg v "$(jq -r .version "$d0/contract.json")" \
    '{contract_version: $v, changed_files: ["a.txt", ".aid-o/work/evidence/E-par/R-par/steps/step_2_frontend/output.md"], gates: [], step_status: "done"}' > "$d0/return.json"
  : > a.txt
  run aid_dispatch_contract_validate "$d0/contract.json" "$d0/return.json" .
  [ "$status" -eq 1 ]
  [[ "$output" == *"another step's directory"* ]]
  [[ "$output" == *"steps/step_2_frontend/output.md"* ]]
}

@test "evidence: increment-step refuses a contracted step without an accepted return" {
  d0="$(bash "$FSM" step-evidence-dir "$STATE" 0)"
  aid_dispatch_contract_build "$TEST_EVIDENCE_DIR/plan.json" 0 "$d0/contract.json" "$TEST_EVIDENCE_DIR"
  # a verify file that satisfies every older precondition
  printf '# Step 0\n- [x] AC1 — PASS\n%s\n## Memory Used\nN/A\n## Memory Written\nN/A\n## Result: PASS\n' "$(git rev-parse HEAD)" > "$TEST_EVIDENCE_DIR/step-0-verify.md"
  run bash "$FSM" increment-step "$STATE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no return was recorded"* ]]
  jq -n '{contract_version: "stale0000000", changed_files: [], gates: [], step_status: "done"}' > "$d0/return.json"
  run bash "$FSM" increment-step "$STATE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not accepted against its contract"* ]]
  [ "$(bash "$FSM" get-field current_step "$STATE")" = "0" ]
}
