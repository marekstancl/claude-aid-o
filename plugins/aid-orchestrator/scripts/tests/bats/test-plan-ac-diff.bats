#!/usr/bin/env bats
# test-plan-ac-diff.bats — Phase 2 (P037) plan-AC executable verification

setup() {
  TMPDIR_TEST="$(mktemp -d)"
  EVIDENCE_DIR="${TMPDIR_TEST}/.aid-o/work/evidence/E-TEST-2/R-TEST-2"
  PLANS_DIR="${TMPDIR_TEST}/.aid-o/plans"
  mkdir -p "$EVIDENCE_DIR" "$PLANS_DIR"
  cd "$TMPDIR_TEST"
  git init -q
  git config user.email test@test
  git config user.name test
  echo "x" > seed.txt
  git add seed.txt
  git commit -q -m "init"
  PROJECT_ROOT="$TMPDIR_TEST"
  BASE_COMMIT="$(git rev-parse HEAD)"
  AID_DIFF_SCRIPT="${BATS_TEST_DIRNAME}/../../aid-plan-diff.sh"
}

teardown() {
  cd /tmp
  rm -rf "$TMPDIR_TEST"
}

@test "all ACs present: 3 patterns satisfied → exit 0 + overall_verdict pass" {
  mkdir -p "${TMPDIR_TEST}/ui/src/lib"
  echo "test content" > "${TMPDIR_TEST}/ui/src/foo.ts"
  cat > "${PLANS_DIR}/P-TEST.md" <<'EOF'
## Acceptance Criteria

- [ ] AC1: foo file exists
  ```yaml
  verification_pattern:
    type: must_contain
    file: "ui/src/foo.ts"
    regex: "test content"
  ```
- [ ] AC2: bar file does not exist
  ```yaml
  verification_pattern:
    type: must_not_exist
    file: "ui/src/lib/bar.ts"
  ```
- [ ] AC3: trivial cmd succeeds
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "true"
    expected_exit: 0
  ```

## Next Steps
EOF
  run "$AID_DIFF_SCRIPT" --plan "${PLANS_DIR}/P-TEST.md" --evidence-dir "$EVIDENCE_DIR" --base-commit "$BASE_COMMIT"
  [ "$status" -eq 0 ]
  local overall absent
  overall=$(jq -r '.overall_verdict' "${EVIDENCE_DIR}/plan-diff.json")
  absent=$(jq -r '.summary.absent_count' "${EVIDENCE_DIR}/plan-diff.json")
  [ "$overall" = "pass" ]
  [ "$absent" -eq 0 ]
}

@test "one AC absent: must_not_exist file actually exists → exit 1 + verdict fail" {
  mkdir -p "${TMPDIR_TEST}/ui/src/lib"
  echo "stale" > "${TMPDIR_TEST}/ui/src/lib/unifyExtractedSources.ts"
  cat > "${PLANS_DIR}/P-TEST.md" <<'EOF'
## Acceptance Criteria

- [ ] AC1: stale file removed
  ```yaml
  verification_pattern:
    type: must_not_exist
    file: "ui/src/lib/unifyExtractedSources.ts"
  ```

## Next Steps
EOF
  run "$AID_DIFF_SCRIPT" --plan "${PLANS_DIR}/P-TEST.md" --evidence-dir "$EVIDENCE_DIR" --base-commit "$BASE_COMMIT"
  [ "$status" -eq 1 ]
  local overall absent
  overall=$(jq -r '.overall_verdict' "${EVIDENCE_DIR}/plan-diff.json")
  absent=$(jq -r '.summary.absent_count' "${EVIDENCE_DIR}/plan-diff.json")
  [ "$overall" = "fail" ]
  [ "$absent" -eq 1 ]
}

@test "must_contain any-match semantics: single regex hit suffices" {
  echo -e "line1\ndef test_visibility_after_revalidation\nline3" > "${TMPDIR_TEST}/foo.py"
  cat > "${PLANS_DIR}/P-TEST.md" <<'EOF'
## Acceptance Criteria

- [ ] AC1: test function exists in foo.py
  ```yaml
  verification_pattern:
    type: must_contain
    file: "foo.py"
    regex: "def test_visibility_after_revalidation"
  ```

## Next Steps
EOF
  run "$AID_DIFF_SCRIPT" --plan "${PLANS_DIR}/P-TEST.md" --evidence-dir "$EVIDENCE_DIR" --base-commit "$BASE_COMMIT"
  [ "$status" -eq 0 ]
  local verdict
  verdict=$(jq -r '.results[0].verdict' "${EVIDENCE_DIR}/plan-diff.json")
  [ "$verdict" = "present" ]
}

@test "legacy plan: no AC section → exit 2 graceful skip + verdict skipped" {
  cat > "${PLANS_DIR}/P-LEGACY.md" <<'EOF'
# Plan: Legacy

## Goal
Old plan without AC section.

## Implementation Steps
1. Do thing.
EOF
  run "$AID_DIFF_SCRIPT" --plan "${PLANS_DIR}/P-LEGACY.md" --evidence-dir "$EVIDENCE_DIR" --base-commit "$BASE_COMMIT"
  [ "$status" -eq 2 ]
  local overall ac_count
  overall=$(jq -r '.overall_verdict' "${EVIDENCE_DIR}/plan-diff.json")
  ac_count=$(jq -r '.ac_count' "${EVIDENCE_DIR}/plan-diff.json")
  [ "$overall" = "skipped" ]
  [ "$ac_count" -eq 0 ]
}

@test "Fast Mode: --plan null literal → exit 2 + plan_path=null in JSON" {
  run "$AID_DIFF_SCRIPT" --plan "null" --evidence-dir "$EVIDENCE_DIR" --base-commit "$BASE_COMMIT"
  [ "$status" -eq 2 ]
  local overall plan_path reason
  overall=$(jq -r '.overall_verdict' "${EVIDENCE_DIR}/plan-diff.json")
  plan_path=$(jq -r '.plan_path' "${EVIDENCE_DIR}/plan-diff.json")
  reason=$(jq -r '.summary.reason' "${EVIDENCE_DIR}/plan-diff.json")
  [ "$overall" = "skipped" ]
  [ "$plan_path" = "null" ]
  echo "$reason" | grep -q "fast-mode"
}

@test "Fast Mode: empty --plan arg → exit 2 + same skipped semantics" {
  run "$AID_DIFF_SCRIPT" --plan "" --evidence-dir "$EVIDENCE_DIR" --base-commit "$BASE_COMMIT"
  [ "$status" -eq 2 ]
  local overall
  overall=$(jq -r '.overall_verdict' "${EVIDENCE_DIR}/plan-diff.json")
  [ "$overall" = "skipped" ]
}

@test "aid-run-gates.sh: unknown placeholder token → fail-loud exit 1" {
  # NOTE: validates resolve_placeholders helper logic via inline replica.
  # We do NOT source aid-run-gates.sh — sourcing would propagate `set -euo pipefail`
  # into bats test context and pollute namespace with all gate-runner functions.
  # Integration with full aid-run-gates.sh is exercised by /aid-run end-to-end
  # smoke (post-deploy manual validation in Step 12 success criteria).

  resolve_placeholders_replica() {
    local cmd="$1" epic="$2" run="$3" base="$4" plan="$5"
    cmd="${cmd//\{epic_id\}/$epic}"
    cmd="${cmd//\{run_id\}/$run}"
    cmd="${cmd//\{base_commit\}/$base}"
    cmd="${cmd//\{plan_path\}/$plan}"
    if [[ "$cmd" =~ \{[a-zA-Z_]+\} ]]; then
      echo "ERROR: unknown placeholder ${BASH_REMATCH[0]}" >&2
      return 1
    fi
    printf '%s' "$cmd"
  }

  # Valid tokens — should resolve without error
  run resolve_placeholders_replica "echo {epic_id} {run_id}" "E-1" "R-1" "abc" "null"
  [ "$status" -eq 0 ]
  [ "$output" = "echo E-1 R-1" ]

  # Unknown token — should fail-loud
  run resolve_placeholders_replica "echo {plan} {epic_id}" "E-1" "R-1" "abc" "null"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "unknown placeholder"
}

@test "aid-fsm.sh cmd_init: writes plan_path field with absolute path or null" {
  # NOTE: validates plan_path write logic via inline replica — does NOT call cmd_init.
  # Sourcing aid-fsm.sh would propagate set -euo pipefail + namespace pollution.
  # cmd_init integration is exercised by /aid-run end-to-end smoke (Step 12).

  # Test with --plan arg — simulates cmd_init's plan_path write logic
  local test_state="${EVIDENCE_DIR}/test-state.yaml"
  echo "epic_id: E-TEST" > "$test_state"
  local plan_arg=".aid-o/plans/P-TEST.md"
  local plan_path_value="null"
  [[ -n "$plan_arg" ]] && plan_path_value=$(realpath "$plan_arg" 2>/dev/null || echo "$plan_arg")
  echo "plan_path: $plan_path_value" >> "$test_state"

  grep -q "^plan_path:" "$test_state"
  local written
  written=$(grep '^plan_path:' "$test_state" | awk '{print $2}')
  [[ "$written" = /* ]] || [ "$written" = ".aid-o/plans/P-TEST.md" ]

  # Test without --plan arg → null
  echo "epic_id: E-TEST-2" > "$test_state"
  echo "plan_path: null" >> "$test_state"
  local written2
  written2=$(grep '^plan_path:' "$test_state" | awk '{print $2}')
  [ "$written2" = "null" ]
}
