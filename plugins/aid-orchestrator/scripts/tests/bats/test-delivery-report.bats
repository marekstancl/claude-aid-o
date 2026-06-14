#!/usr/bin/env bats
# test-delivery-report.bats — P045 regression for fsm_eval_delivery_report_present.
#
# The helper echoes a JSON literal — null | true | false — for the plan-boundary
# delivery report (scripts/aid-fsm.sh):
#   null  — plan boundary NOT reached (no ca-review-complete marker in evidence_dir).
#   true  — at boundary AND .aid-o/reports/{plan_id}-delivery.md exists AND its
#           _test_evidence[] references >=1 file present on disk under evidence_dir.
#   false — at boundary AND report missing, OR no _test_evidence entry exists on disk.
# plan_id derives from epic_id (E-045-1_1 -> P045).
#
# Sourcing aid-fsm.sh requires a no-op dispatcher arg because the bottom of
# aid-fsm.sh is a top-level `case` that exits on unknown commands. We pre-set
# positional params to `verify-state <state_file>` so the dispatcher runs
# harmlessly (prints JSON, exits 0) and the function defs persist into scope.
# This mirrors test-anti-fabrication.bats's _load_aid_fsm shim.

setup() {
  export TZ=UTC
  export AID_TEST_MODE=1
  TMPDIR_TEST="$(mktemp -d)"
  EPIC_ID="E-045-1_1"                       # -> plan_id P045
  EVID="${TMPDIR_TEST}/.aid-o/work/evidence/${EPIC_ID}/R-E045-1"
  PROJECT_ROOT="$TMPDIR_TEST"
  REPORTS_DIR="${PROJECT_ROOT}/.aid-o/reports"
  mkdir -p "$EVID" "$REPORTS_DIR"

  # Minimal populated state file so the verify-state dispatcher runs cleanly when
  # aid-fsm.sh is sourced (output discarded — only function defs matter here).
  STATE_FILE="${EVID}/fsm-state.yaml"
  cat > "$STATE_FILE" <<EOF
epic_id: ${EPIC_ID}
run_id: R-E045-1
branch: task/${EPIC_ID}/main
state: GATES
created_at: 2026-05-12T14:00:00Z
current_step: 1
total_steps: 5
EOF
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# Source aid-fsm.sh safely (its bottom-of-file dispatcher would otherwise exit).
_load_aid_fsm() {
  local fsm="${BATS_TEST_DIRNAME}/../../aid-fsm.sh"
  set -- "verify-state" "$STATE_FILE"
  # shellcheck disable=SC1090
  source "$fsm" >/dev/null
}

@test "null before plan boundary (no ca-review-complete marker)" {
  _load_aid_fsm
  run fsm_eval_delivery_report_present "$EPIC_ID" "$EVID" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "true at boundary: report present + _test_evidence file exists on disk" {
  touch "${EVID}/ca-review-complete"
  # Report mirrors defaults/templates/delivery-report.md shape, WITH a leading HTML
  # comment block to prove the awk frontmatter extractor tolerates it.
  cat > "${REPORTS_DIR}/P045-delivery.md" <<'EOF'
<!--
  Delivery Report Template — machine-read frontmatter; do not rename keys.
-->
---
_generated_by: aid-orchestrator:reporter@E-045-1_1
_generated_at: "2026-05-12T14:30:00Z"
plan_id: "P045"
epics: ["E-045-1_1"]
test_outcome: pass
_test_evidence:
  - "reporter/smoke.txt"
---

# Delivery Report — P045

Plan P045 delivered.
EOF
  mkdir -p "${EVID}/reporter"
  echo "smoke ok" > "${EVID}/reporter/smoke.txt"

  _load_aid_fsm
  run fsm_eval_delivery_report_present "$EPIC_ID" "$EVID" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "false at boundary: report absent" {
  touch "${EVID}/ca-review-complete"
  # No P045-delivery.md written.

  _load_aid_fsm
  run fsm_eval_delivery_report_present "$EPIC_ID" "$EVID" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "false at boundary: _test_evidence references a file missing on disk" {
  touch "${EVID}/ca-review-complete"
  cat > "${REPORTS_DIR}/P045-delivery.md" <<'EOF'
---
_generated_by: aid-orchestrator:reporter@E-045-1_1
_generated_at: "2026-05-12T14:30:00Z"
plan_id: "P045"
epics: ["E-045-1_1"]
test_outcome: pass
_test_evidence:
  - "reporter/does-not-exist.txt"
---

# Delivery Report — P045

Plan P045 delivered.
EOF
  # reporter/does-not-exist.txt deliberately NOT created.

  _load_aid_fsm
  run fsm_eval_delivery_report_present "$EPIC_ID" "$EVID" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "false: _test_evidence path-traversal/absolute path is rejected (CP3 security hardening)" {
  touch "${EVID}/ca-review-complete"
  # An author-controlled _test_evidence that points OUTSIDE the evidence dir
  # (via `..`) at a real host file must NOT satisfy the check. /etc/hostname
  # exists on disk, so without the traversal guard the helper would echo `true`.
  cat > "${REPORTS_DIR}/P045-delivery.md" <<'EOF'
---
_generated_by: aid-orchestrator:reporter@E-045-1_1
_generated_at: "2026-05-12T14:30:00Z"
plan_id: "P045"
epics: ["E-045-1_1"]
test_outcome: pass
_test_evidence:
  - "../../../../../../etc/hostname"
  - "/etc/hostname"
---

# Delivery Report — P045

Plan P045 delivered.
EOF

  _load_aid_fsm
  run fsm_eval_delivery_report_present "$EPIC_ID" "$EVID" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
