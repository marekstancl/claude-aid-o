#!/usr/bin/env bats
# P033 Step 9 — aid-prefilter.sh classify: SKIP/RUN/FAIL + output format (6 assertions)

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PREFILTER="$AID_PLUGIN_PATH/scripts/aid-prefilter.sh"
  export PREFILTER
}

teardown() {
  teardown_test_evidence_dir
}

# Helper: commit one or more files (pairs of <path> <content>).
# Must be called from TEST_PROJECT_ROOT (done by setup_test_evidence_dir).
make_commit() {
  local message="$1"; shift
  while [[ $# -ge 2 ]]; do
    local file="$1" content="$2"
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$content" > "$file"
    git add "$file"
    shift 2
  done
  git commit -q -m "$message"
}

# ─── SKIP ─────────────────────────────────────────────────────────────────────

@test "classify: docs-only diff (README.md) → SKIP (exit 0) + classification field" {
  make_commit "add readme" "README.md" "# Project overview"
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  grep -q 'classification: SKIP' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

# ─── RUN ──────────────────────────────────────────────────────────────────────

@test "classify: code change (.sh file) → RUN (exit 10)" {
  make_commit "add helper script" "lib/helper.sh" "#!/bin/bash"$'\n'"echo hello"
  run "$PREFILTER" classify 2 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]
  grep -q 'classification: RUN' "$TEST_EVIDENCE_DIR/verifier-output-step-2.md"
}

@test "classify: empty diff (no parent commit) → RUN (exit 10, conservative)" {
  # Initial commit has no parent → git diff HEAD~1 HEAD returns empty → default RUN
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]
  grep -q 'reason: no_diff' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

@test "classify: mixed docs + code files → NOT SKIP (exit 10, match_all_files requires all)" {
  # docs_only rule has match_all_files: true — one non-matching file cancels SKIP
  make_commit "mixed change" "CHANGELOG.md" "## v1.0.0" "src/main.py" "print('hi')"
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]  # RUN — lib.sh does not match docs pattern
}

# ─── FAIL ─────────────────────────────────────────────────────────────────────

@test "classify: hardcoded secret pattern → FAIL (exit 20)" {
  # hardcoded_secret_pattern rule: (password|...) = '<16+ chars>'
  make_commit "add config" "settings.py" 'password = "supersecretvalue12345"'
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 20 ]
  grep -q 'classification: FAIL' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

# ─── Output format ────────────────────────────────────────────────────────────

@test "classify: output file has _generated_by, classification, verdict fields" {
  make_commit "add code" "app.sh" "#!/bin/bash"$'\n'"echo app"
  run "$PREFILTER" classify 3 "$TEST_EVIDENCE_DIR"
  local out="$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
  [ -f "$out" ]
  grep -q '^_generated_by:' "$out"
  grep -q '^classification:' "$out"
  grep -q '^verdict:' "$out"
}
