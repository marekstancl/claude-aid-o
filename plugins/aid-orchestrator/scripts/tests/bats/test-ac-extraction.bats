#!/usr/bin/env bats
# aid-tier: t1
# P083 Step 2 — the shared AC extractor (aid-ac-extract.sh) must not drop
# continuation lines the way the two copy-pasted awk blocks in
# aid-plan-to-epic.sh did (flush-left-only bullet match truncated every
# multi-line criterion mid-sentence).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  AC_EXTRACT="$AID_PLUGIN_PATH/scripts/lib/aid-ac-extract.sh"
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  EPIC_TEMPLATE="$AID_PLUGIN_PATH/defaults/templates/epic.md"
  FIXTURE="$AID_PLUGIN_PATH/scripts/tests/fixtures/plan-with-multiline-ac.md"
  OUTPUT_DIR="$TEST_TMPDIR/output"
  COUNTER="$TEST_TMPDIR/epic-counter.yaml"
  mkdir -p "$OUTPUT_DIR"
  printf 'counter: 0\n' > "$COUNTER"
  # IMP-503: DoD gate resolution requires a real execution.yaml at the
  # project's state root (fail-closed). An empty gates: mapping is a valid
  # outcome; this fixture just needs to exist and parse.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'gates: {}\n' > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── Unit-level: aid_ac_extract_criteria directly ─────────────────────────

# _extract <line>... — feed the given markdown lines to the extractor under
# `run`, so each case reads as the input it is about.
_extract() {
  run bash -c 'source "$1"; shift; printf "%s\n" "$@" | aid_ac_extract_criteria' \
    aid-ac-extract "$AC_EXTRACT" "$@"
}

@test "reproduced P068 Step 2 criterion emerges whole" {
  _extract \
    "**Acceptance Criteria:**" \
    "- [ ] Every quarantined gate satisfied by a substitute has a matching" \
    "      \`quarantine_substitutes[]\` entry carrying \`gate_id\`, \`targeted_substitute\`," \
    "      \`receipt_path\` + \`receipt_sha256\`, \`command_sha256\`, \`base_sha\`," \
    "      \`head_sha == candidate_sha\`, \`substitute_scope\`, \`exit_code: 0\` and" \
    "      \`failed: 0\`; the stage rejects a substitute whose \`gate_id\` does not match" \
    "      the quarantined gate (one receipt cannot satisfy another gate) or whose" \
    "      \`head_sha != candidate_sha\`, and never rewrites the broad gate's own row to" \
    "      \`pass\`."
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"Every quarantined gate satisfied by a substitute has a matching \`quarantine_substitutes[]\` entry carrying"* ]]
  [[ "$output" == *"never rewrites the broad gate's own row to \`pass\`."* ]]
  # Not truncated mid-sentence (the pre-fix defect).
  [[ "$output" != *"matching\`quarantine_substitutes[]\`"* ]]  # sanity: space, not glued
}

@test "single-line criterion is byte-identical" {
  _extract "**Acceptance Criteria:**" "- A plain single-line criterion."
  [ "$status" -eq 0 ]
  [ "$output" = "A plain single-line criterion." ]
}

@test "code span with leading dash in continuation is joined, not split" {
  _extract \
    "**Acceptance Criteria:**" \
    "- First line of criterion" \
    "      \`- looks like a bullet but is indented\` continues here."
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "First line of criterion \`- looks like a bullet but is indented\` continues here." ]]
}

@test "empty line inside terminates the criterion" {
  _extract \
    "**Acceptance Criteria:**" \
    "- First criterion" \
    "" \
    "- Second criterion"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "First criterion" ]
  [ "${lines[1]}" = "Second criterion" ]
}

@test "flush-left non-bullet line terminates; a later indented line does not resume" {
  _extract \
    "**Acceptance Criteria:**" \
    "- First criterion stops here." \
    "This is flush-left prose." \
    "      an indented line that must NOT be appended to First criterion" \
    "- Second criterion"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "First criterion stops here." ]
  [ "${lines[1]}" = "Second criterion" ]
}

@test "a **-prefixed terminator stops the section" {
  _extract \
    "**Acceptance Criteria:**" \
    "- Only criterion." \
    "**Effort:** S" \
    "- Not AC, section already closed."
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "Only criterion." ]
}

@test "an INDENTED line that looks like a new section heading terminates, not absorbed" {
  # Error Handling: "A continuation line that itself looks like a new
  # section heading terminates the criterion rather than being absorbed" —
  # this applies even when the line is indented (a malformed/copy-pasted
  # section marker), not just a flush-left one.
  _extract \
    "**Acceptance Criteria:**" \
    "- First criterion" \
    "      **Effort:** S" \
    "- Second criterion"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "First criterion" ]
  [ "${lines[1]}" = "Second criterion" ]
}

@test "fenced block indented under a criterion is treated as continuation" {
  _extract \
    "**Acceptance Criteria:**" \
    "- Criterion with a fenced pattern" \
    '      ```yaml' \
    "      key: value" \
    '      ```'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *'```yaml key: value ```'* ]]
}

# ─── End-to-end: both aid-plan-to-epic.sh call sites agree ────────────────

@test "both call sites (flattened AC section and per-step ac[] scoping) produce the same criterion set" {
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

  # The multi-line criterion reaches the flattened ## Acceptance Criteria section whole.
  grep -q "Every quarantined gate satisfied by a substitute has a matching \`quarantine_substitutes\[\]\` entry carrying \`gate_id\`, \`targeted_substitute\`, \`receipt_path\` + \`receipt_sha256\`\." "$epic_file"

  # The per-step ac[] scoping comment carries the same whole criterion (unprefixed).
  local scoping_line
  scoping_line="$(grep '<!-- step-1: files=' "$epic_file")"
  [ -n "$scoping_line" ]
  [[ "$scoping_line" == *"Every quarantined gate satisfied by a substitute has a matching"*"receipt_sha256"* ]]

  # Terminator cases from Step 2: the flush-left-prose criterion and the
  # **-terminated criterion both appear, and the "Some Other Section" bullet
  # (outside any Acceptance Criteria block) does not leak in as an AC.
  grep -q "A criterion followed by a flush-left prose line stops there\." "$epic_file"
  grep -q "A criterion followed by a \`\*\*\`-prefixed terminator stops there\." "$epic_file"
  refute_grep -q "This must not be treated as AC" "$epic_file"
}
