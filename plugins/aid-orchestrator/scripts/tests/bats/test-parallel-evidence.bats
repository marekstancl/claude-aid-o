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

# _agent <idx> <file> — "the agent" leaves its artifact and its return
_agent() {
  aid_dispatch_contract_build "$TEST_EVIDENCE_DIR/plan.json" "$1" "c$1.json"
  printf 'content %s\n' "$1" > "$2"
  jq -n --arg v "$(jq -r .version "c$1.json")" --arg f "$2" \
    '{contract_version: $v, changed_files: [$f], gates: [], step_status: "done"}' > "r$1.json"
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

@test "evidence: AC4 — two returns handled one after the other make two commits, each holding only its own files" {
  _agent 0 a.txt; _agent 1 b.txt
  before="$(git rev-list --count HEAD)"
  aid_dispatch_contract_validate c0.json r0.json . >/dev/null
  sha0="$(aid_dispatch_contract_commit . c0.json r0.json "step 1: a")"
  aid_dispatch_contract_validate c1.json r1.json . >/dev/null
  sha1="$(aid_dispatch_contract_commit . c1.json r1.json "step 2: b")"
  [ "$(git rev-list --count HEAD)" -eq $((before + 2)) ]
  [ "$(git show --name-only --format= "$sha0")" = "a.txt" ]
  [ "$(git show --name-only --format= "$sha1")" = "b.txt" ]
}

@test "evidence: a step that changed nothing makes no commit, and says so" {
  aid_dispatch_contract_build "$TEST_EVIDENCE_DIR/plan.json" 0 c0.json
  jq -n --arg v "$(jq -r .version c0.json)" '{contract_version: $v, changed_files: [], gates: [], step_status: "done"}' > r0.json
  before="$(git rev-list --count HEAD)"
  run aid_dispatch_contract_commit . c0.json r0.json "step 1: nothing"
  [ "$status" -eq 0 ]
  [ "$output" = "nothing to commit" ]
  [ "$(git rev-list --count HEAD)" -eq "$before" ]
}

@test "evidence: AC6 — a return that wrote into another step's directory is refused" {
  aid_dispatch_contract_build "$TEST_EVIDENCE_DIR/plan.json" 0 c0.json
  jq -n --arg v "$(jq -r .version c0.json)" \
    '{contract_version: $v, changed_files: ["a.txt", ".aid-o/work/evidence/E-par/R-par/steps/step_2_frontend/output.md"], gates: [], step_status: "done"}' > r0.json
  : > a.txt
  run aid_dispatch_contract_validate c0.json r0.json .
  [ "$status" -eq 1 ]
  [[ "$output" == *"another step's directory"* ]]
  [[ "$output" == *"steps/step_2_frontend/output.md"* ]]
}
