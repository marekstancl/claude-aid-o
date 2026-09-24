#!/usr/bin/env bats
# aid-tier: t0
# test-aid-plan-close-check.bats — aid-plan-close-check.sh (PM plugin-infra fix,
# branch fix/plan-close-consistency).
#
# Covers the fsm-state DONE-but-pending guard (Check 3), the queue.yaml /
# active.md revalidation (Check 4, reusing aid-fsm.sh's queue_revalidate) and
# the aggregate verdict. Fixtures build a real git repo, since Check 4 depends
# on real branch/merge state (as test-queue-revalidation.bats does).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCRIPT="$AID_PLUGIN_PATH/scripts/aid-plan-close-check.sh"
  export SCRIPT
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixture helpers ─────────────────────────────────────────────────────

# write_fsm_state <epic_id> <run_id> <state> <pending_count>
#   Writes a minimal fsm-state.yaml with a steps[] array of 2 entries, the
#   first N of which are "pending" (pending_count) and the rest "completed".
write_fsm_state() {
  local epic_id="$1" run_id="$2" state="$3" pending_count="$4"
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/${run_id}"
  mkdir -p "$dir"
  local s1="completed" s2="completed"
  [[ "$pending_count" -ge 1 ]] && s1="pending"
  [[ "$pending_count" -ge 2 ]] && s2="pending"
  cat > "$dir/fsm-state.yaml" <<EOF
epic_id: $epic_id
run_id: $run_id
state: $state
current_step: 2
total_steps: 2
steps:
  - id: 1
    status: $s1
  - id: 2
    status: $s2
EOF
}

# make_merged_epic_branch <epic_id>
#   Real merged branch (task/<epic_id>/main, --no-ff into main, branch kept)
#   — same construction test-queue-revalidation.bats's make_merged_dep uses.
make_merged_epic_branch() {
  local epic="$1"
  local br="task/${epic}/main"
  git checkout -q -b "$br"
  echo "$epic work" > "${epic//\//_}.txt"
  git add "${epic//\//_}.txt"
  git commit -q -m "feat: ${epic} work"
  git checkout -q main
  git merge -q --no-ff "$br" -m "merge: ${epic} into main"
}

write_queue_yaml() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml"
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 1 — DONE fsm-state with all steps pending → FAILS (Check 3)
# ═══════════════════════════════════════════════════════════════════════

@test "(1) DONE fsm-state with all steps pending -> self-check FAILS" {
  write_fsm_state "E-601-1_1" "R-1" "DONE" 2

  run "$SCRIPT" P601 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"state=DONE but 2 step(s) still status:pending"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 5 — queue/active claims blocked but branch is merged -> FAILS
# ═══════════════════════════════════════════════════════════════════════

@test "(5) queue.yaml claims blocked/waiting-for-merge but branch IS merged -> FAILS" {
  make_merged_epic_branch "E-605-1_2"

  write_queue_yaml <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-605-1_2
  path: p
  status: blocked
  depends_on: []
YAML

  run "$SCRIPT" P605 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"E-605-1_2"*"queue_revalidate confirms the branch IS merged"* ]]
}

@test "(5b) queue.yaml status genuinely unmerged -> PASSES (consistent)" {

  # E-606-1_2 branch exists but is NOT merged into main.
  git -C "$TEST_PROJECT_ROOT" checkout -q -b task/E-606-1_2/main
  echo wip > "$TEST_PROJECT_ROOT/wip.txt"
  git -C "$TEST_PROJECT_ROOT" add wip.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "wip: E-606-1_2"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  write_queue_yaml <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-606-1_2
  path: p
  status: blocked
  depends_on: []
YAML

  run "$SCRIPT" P606 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"*"check4"*"genuinely unmerged, consistent"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 6 — WAN-P062-like fixture (positive regression snapshot) -> PASS
# ═══════════════════════════════════════════════════════════════════════

@test "(6) three DONE EPICs with every step completed and a clean queue -> overall PASS" {
  # 3 EPICs, all DONE, all steps completed.
  write_fsm_state "E-062-1_3" "R-E062-1" "DONE" 0
  write_fsm_state "E-062-2_3" "R-E062-2" "DONE" 0
  write_fsm_state "E-062-3_3" "R-E062-3" "DONE" 0

  # queue.yaml: all 3 completed, no blocked/waiting claims.
  write_queue_yaml <<'YAML'
paused: false
last_modified: "x"
queue:
- epic_id: E-062-1_3
  path: p
  status: completed
  depends_on: []
- epic_id: E-062-2_3
  path: p
  status: completed
  depends_on: ["E-062-1_3"]
- epic_id: E-062-3_3
  path: p
  status: completed
  depends_on: ["E-062-2_3"]
YAML

  run "$SCRIPT" P062 --project-root "$TEST_PROJECT_ROOT"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OVERALL: PASS"* ]]
  ! [[ "$output" == *"FAIL"* ]]
}
