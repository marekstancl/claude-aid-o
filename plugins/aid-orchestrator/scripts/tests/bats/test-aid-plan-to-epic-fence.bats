#!/usr/bin/env bats
# aid-tier: t2
# F13 (NR 14 §4D) — aid-plan-to-epic.sh: ### Step headers and **EPIC**
# markers inside fenced code blocks must NOT be counted as real steps
# (regression for meta-plans that quote AID syntax).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  FIXTURE="$AID_PLUGIN_PATH/scripts/tests/fixtures/plan-with-fenced-steps.md"
  EPIC_TEMPLATE="$AID_PLUGIN_PATH/defaults/templates/epic.md"
  OUTPUT_DIR="$TEST_TMPDIR/output"
  COUNTER="$TEST_TMPDIR/epic-counter.yaml"
  mkdir -p "$OUTPUT_DIR"
  printf 'counter: 0\n' > "$COUNTER"
  # IMP-503: DoD gate resolution now requires a real execution.yaml at the
  # project's state root (fail-closed — a missing/unreadable config is no
  # longer indistinguishable from "this project chose no DoD gate"). An
  # empty gates: mapping is a valid, deliberate outcome; this fixture just
  # needs to exist and parse.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'gates: {}\n' > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── Assertion 1: real-step count is 2, not corrupted by fenced markers ──────

@test "aid-plan-to-epic skips ### Step headers inside fenced code blocks" {
  run "$PLAN_TO_EPIC" \
    --plan "$FIXTURE" \
    --phase 1 --total 1 \
    --epic-template "$EPIC_TEMPLATE" \
    --output-dir "$OUTPUT_DIR" \
    --counter-yaml "$COUNTER"
  [ "$status" -eq 0 ]

  local epic_file
  epic_file="$(ls "$OUTPUT_DIR"/E-*.md | head -1)"
  [ -f "$epic_file" ]

  # The Hints section reports expected_steps. Pre-fix this fixture would
  # fail entirely (fenced **EPIC 7** marker corrupts phase mapping); post-fix
  # it must report exactly 2 real steps.
  grep -q '^- expected_steps: 2$' "$epic_file"

  # The Steps table has exactly 2 data rows (lines starting with "| 1 " and "| 2 ").
  local row_count
  row_count="$(grep -cE '^\| [0-9]+ \|' "$epic_file" || true)"
  [ "$row_count" -eq 2 ]

  # And the table must NOT contain a row referencing fenced step 99/100/101/200.
  ! grep -qE '^\| (99|100|101|200) \|' "$epic_file"
}

# ─── Assertion 2: EPIC marker inside fence is not used as a phase boundary ───

@test "aid-plan-to-epic skips **EPIC N: Steps M-P** markers inside fenced blocks" {
  run "$PLAN_TO_EPIC" \
    --plan "$FIXTURE" \
    --phase 1 --total 1 \
    --epic-template "$EPIC_TEMPLATE" \
    --output-dir "$OUTPUT_DIR" \
    --counter-yaml "$COUNTER"
  [ "$status" -eq 0 ]

  local epic_file
  epic_file="$(ls "$OUTPUT_DIR"/E-*.md | head -1)"
  [ -f "$epic_file" ]

  # Acceptance Criteria must mention both real steps but not the fenced ones.
  grep -q 'Reference doc exists' "$epic_file"
  grep -q 'Example renders correctly' "$epic_file"
  # Fenced steps had no Acceptance Criteria, but the docs/aid-syntax.md /
  # docs/aid-syntax-example.md paths come from the two real steps.
  grep -q 'docs/aid-syntax.md' "$epic_file"
  grep -q 'docs/aid-syntax-example.md' "$epic_file"
}
