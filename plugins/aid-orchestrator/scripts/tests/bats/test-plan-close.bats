#!/usr/bin/env bats
# aid-tier: t2
# test-plan-close.bats — cmd_plan_close in aid-fsm.sh: it runs
# aid-plan-close-check.sh and writes ca-review-complete only when that passes.
# The fixture is a real git repo, since the queue check reads branch state.

PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
AID_FSM="$PLUGIN_DIR/scripts/aid-fsm.sh"

# epic_id used in all tests — determines plan_id=P046 (nnn=046)
EPIC_ID="E-046-2_3"

setup() {
  export AID_TEST_MODE=1
  TMP=$(mktemp -d)
  export TMP
  # evidence_dir == project_root == TMP for simplicity.
  mkdir -p "$TMP/.aid-o/config" "$TMP/.aid-o/work"
  git -C "$TMP" init -q -b main
  git -C "$TMP" config user.email "test@test.local"
  git -C "$TMP" config user.name "Test"
  echo "init" > "$TMP/.gitkeep"
  git -C "$TMP" add .gitkeep
  git -C "$TMP" commit -q -m "initial"
}

teardown() {
  rm -rf "$TMP"
}

@test "plan-close: a clean state -> aid-plan-close-check.sh PASS, marker created, exit 0" {
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/ca-review-complete" ]
  [[ "$output" =~ "OVERALL: PASS" ]]
}

@test "plan-close: fsm-state.yaml DONE but steps[] pending -> exit 1, no marker" {
  mkdir -p "$TMP/.aid-o/work/evidence/E-046-2_3/R-test"
  cat > "$TMP/.aid-o/work/evidence/E-046-2_3/R-test/fsm-state.yaml" <<'YAML'
epic_id: E-046-2_3
run_id: R-test
state: DONE
current_step: 2
total_steps: 2
steps:
  - id: 1
    status: completed
  - id: 2
    status: pending
YAML
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
  [[ "$output" =~ "aid-plan-close-check.sh" ]]
}

@test "plan-close: queue.yaml claims blocked but the branch is merged -> exit 1, no marker" {
  # A branch for E-046-2_3 that IS an ancestor of current HEAD (merged), while
  # queue.yaml still claims it is blocked — the stale-queue drift Check 4 catches.
  git -C "$TMP" branch task/E-046-2_3/main HEAD
  cat > "$TMP/.aid-o/config/queue.yaml" <<'YAML'
- epic_id: E-046-2_3
  path: p
  status: blocked
  depends_on: []
YAML
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

@test "plan-close: a report nobody writes any more is not asked for" {
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" != *"required report not found"* ]]
  [[ "$output" != *"delivery"* ]]
}
