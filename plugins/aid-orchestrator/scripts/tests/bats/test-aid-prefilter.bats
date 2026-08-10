#!/usr/bin/env bats
# P033 Step 9 — aid-prefilter.sh classify: SKIP/RUN/FAIL + output format (6 assertions)
# P060 Step 3 — cp2 step-boundary range resolution (F4 a-h) + fixture updates.
#   OBS-20260705-01: cp2 must classify from the STEP boundary, not the last commit.
#   Existing cp2 fixtures are updated with a base_commit source so their exit-code
#   asserts still hold under the new range resolution (step_commit | base_commit | exit 22).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PREFILTER="$AID_PLUGIN_PATH/scripts/aid-prefilter.sh"
  export PREFILTER
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
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

# P060 Step 3: cp2 now needs a range SOURCE (step_commit event OR base_commit).
# Seed a minimal fsm-state.yaml providing base_commit so the classic HEAD~1..HEAD
# range is reproduced for the pre-existing single-commit fixtures.
seed_base_commit() {
  local base="${1:-HEAD~1}"
  cat > "$TEST_EVIDENCE_DIR/fsm-state.yaml" <<EOF
epic_id: E-test
run_id: R-test
base_commit: $base
EOF
}

# P060 Step 3: append a step_commit event (producer format) to the timeline.
add_step_commit_event() {
  local sha="$1" step_n="${2:-0}"
  mkdir -p "$TEST_EVIDENCE_DIR"
  printf '{"ts":"2026-07-10T00:00:00Z","event":"step_commit","step_n":%s,"commit_sha":"%s"}\n' \
    "$step_n" "$sha" >> "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

# Fully-valid step-N-verify.md (mirrors test-aid-fsm.bats write_valid_step_verify).
write_valid_step_verify() {
  local file="$1" step="${2:-3}"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<VERIFY
# Step ${step} Verification

## Result: PASS

- [x] acceptance criterion met
- [x] output files match expected paths

Commit: abc1234def5678

## Memory Used
N/A — no prior memory applicable

## Memory Written
N/A — no new entries proposed
VERIFY
}

# A valid CP3 verifier output CARRYING checkpoint: cp3 (the F4h guard-placement fixture).
write_cp3_output() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
_generated_by: aid-orchestrator:verifier@test
_generated_at: 2026-07-10T00:00:00Z
classification: RUN
verdict: pass
checkpoint: cp3
EOF
}

# ─── SKIP ─────────────────────────────────────────────────────────────────────

@test "classify: docs-only diff (README.md) → SKIP (exit 0) + classification field" {
  make_commit "add readme" "README.md" "# Project overview"
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  grep -q 'classification: SKIP' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

# ─── RUN ──────────────────────────────────────────────────────────────────────

@test "classify: code change (.sh file) → RUN (exit 10)" {
  make_commit "add helper script" "lib/helper.sh" "#!/bin/bash"$'\n'"echo hello"
  seed_base_commit
  run "$PREFILTER" classify 2 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]
  grep -q 'classification: RUN' "$TEST_EVIDENCE_DIR/verifier-output-step-2.md"
}

@test "classify: empty diff (no parent commit) → RUN (exit 10, conservative)" {
  # Initial commit has no parent → git diff HEAD~1 HEAD returns empty → default RUN
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]
  grep -q 'reason: no_diff' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

@test "classify: mixed docs + code files → NOT SKIP (exit 10, match_all_files requires all)" {
  # docs_only rule has match_all_files: true — one non-matching file cancels SKIP
  make_commit "mixed change" "CHANGELOG.md" "## v1.0.0" "src/main.py" "print('hi')"
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]  # RUN — lib.sh does not match docs pattern
}

# ─── FAIL ─────────────────────────────────────────────────────────────────────

@test "classify: hardcoded secret pattern → FAIL (exit 20)" {
  # hardcoded_secret_pattern rule: (password|...) = '<16+ chars>'
  make_commit "add config" "settings.py" 'password = "supersecretvalue12345"'
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 20 ]
  grep -q 'classification: FAIL' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

# ─── FAIL: AID-052 migrated/routed patterns ────────────────────────────────────

@test "classify: debugger leftover (console.log) → FAIL (exit 20)" {
  make_commit "add ui code" "src/widget.ts" "export const x = () => { console.log('dbg') }"
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 20 ]
  grep -q 'classification: FAIL' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

@test "classify: bare print() does NOT trigger debug_leftover → RUN (exit 10)" {
  # print( is intentionally excluded from debug_leftover (too common in legit Python).
  make_commit "add py code" "src/calc.py" "def f():"$'\n'"    print('result')"
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]
}

@test "classify: skipped test (.skip()) → FAIL (exit 20)" {
  make_commit "skip a test" "src/foo.test.ts" "it.skip('todo', () => {})"
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 20 ]
  grep -q 'classification: FAIL' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

@test "classify: disabled security check (verify=False) → FAIL (exit 20)" {
  make_commit "disable tls" "src/client.py" "r = requests.get(url, verify=False)"
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 20 ]
  grep -q 'classification: FAIL' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

@test "classify: unsafe deserialize (pickle.loads) → FAIL (exit 20) — ERE-safe rule fires" {
  # Regression for the former (?!_safe) lookahead that silently never matched.
  make_commit "load blob" "src/load.py" "obj = pickle.loads(blob)"
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 20 ]
  grep -q 'classification: FAIL' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

@test "classify: yaml.safe_load does NOT trigger deserialize_dangerous → RUN (exit 10)" {
  make_commit "safe load" "src/cfg.py" "cfg = yaml.safe_load(open('x.yaml'))"
  seed_base_commit
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]
}

# ─── Output format ────────────────────────────────────────────────────────────

@test "classify: output file has _generated_by, classification, verdict fields" {
  make_commit "add code" "app.sh" "#!/bin/bash"$'\n'"echo app"
  seed_base_commit
  run "$PREFILTER" classify 3 "$TEST_EVIDENCE_DIR"
  local out="$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
  [ -f "$out" ]
  grep -q '^_generated_by:' "$out"
  grep -q '^classification:' "$out"
  grep -q '^verdict:' "$out"
}

# ═══ P060 Step 3 — F4: cp2 step-boundary range resolution (a-h) ═════════════════

@test "F4a: production commit + docs bookkeeping on top → RUN (step-boundary, OBS-20260705-01)" {
  # RED before fix: HEAD~1..HEAD only sees the docs commit → false-green SKIP.
  # AFTER fix: range = step_commit(boundary)..HEAD includes the hidden production commit.
  local boundary; boundary=$(git rev-parse HEAD)   # end of previous step
  add_step_commit_event "$boundary" 0
  make_commit "production step" "src/app.py" "def run(): pass"
  make_commit "bookkeeping docs" "README.md" "# updated"
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 10 ]
  grep -q 'classification: RUN' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

@test "F4b: genuinely docs-only step → still SKIP" {
  local boundary; boundary=$(git rev-parse HEAD)
  add_step_commit_event "$boundary" 0
  make_commit "docs only step" "README.md" "# guide update"
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  grep -q 'classification: SKIP' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
}

@test "F4c: step-2 docs-only after a step_commit behind a production commit → SKIP" {
  # Kills lazy 'always base_commit..HEAD' (would include step-1 production → RUN)
  # and 'do nothing' (must anchor to the step_commit, not the run base).
  seed_base_commit "$(git rev-parse HEAD)"          # base_commit = initial (deliberately wide)
  make_commit "step 1 production" "src/core.py" "def core(): pass"
  local step1_end; step1_end=$(git rev-parse HEAD)
  add_step_commit_event "$step1_end" 1              # step_commit marks END of step 1
  make_commit "step 2 docs" "README.md" "# docs update"
  run "$PREFILTER" classify 2 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]                                # range = step1_end..HEAD = README.md only
  grep -q 'classification: SKIP' "$TEST_EVIDENCE_DIR/verifier-output-step-2.md"
}

@test "F4d producer: increment-step pass path logs step_commit event with HEAD sha" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"        # current_step: 3, epic E-test run R-test
  local head_sha; head_sha=$(git rev-parse HEAD)
  # --force skips per-step preconditions; the producer at the step-advance tail still runs.
  run "$FSM" increment-step "$state_file" --force --reason "P060 step3 producer test — verify step_commit emitted"
  [ "$status" -eq 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "step_commit"
  grep -q "\"commit_sha\":\"${head_sha}\"" "$TEST_EVIDENCE_DIR/timeline.jsonl"
  grep -q '"step_n":3' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

@test "F4e: no step_commit and no base_commit → exit 22 range_undetermined, no SKIP stub (blocking)" {
  make_commit "docs" "README.md" "# x"
  # No fsm-state.yaml, no step_commit event → blocking policy refuses to classify.
  run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 22 ]
  [ ! -f "$TEST_EVIDENCE_DIR/verifier-output-step-1.md" ]   # NO false SKIP stub
  [[ "$output" =~ range_undetermined ]]
}

@test "F4f bypass guard: cp4-produced stub does NOT satisfy CP2 increment precondition" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"        # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # A cp4 stub: valid frontmatter but checkpoint: cp4 (must be rejected at the increment call-site).
  cat > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md" <<EOF
_generated_by: aid-pre-filter.sh@v3
_generated_at: 2026-07-10T00:00:00Z
classification: SKIP
reason: docs_only
checkpoint: cp4
EOF
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "checkpoint 'cp4'" ]]
  # current_step NOT incremented (still 3)
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
}

@test "F4g: observe policy → cp2_range_fallback event + loud stderr + still classifies (HEAD~1)" {
  make_commit "docs" "README.md" "# x"
  CP2_RANGE_POLICY=observe run "$PREFILTER" classify 1 "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]                                # HEAD~1..HEAD fallback → README.md only → SKIP
  grep -q 'classification: SKIP' "$TEST_EVIDENCE_DIR/verifier-output-step-1.md"
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "cp2_range_fallback"
  [[ "$output" =~ "LOUD FALLBACK" ]]
}

@test "F4h cp3 regression: checkpoint:cp3 on cp3 consumers still PASSES (guard is increment-only)" {
  seed_test_state_files "EXECUTE" "5" "5"
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  # cp3 outputs carrying checkpoint: cp3 — the increment-only guard must NOT reject these.
  write_cp3_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  write_cp3_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$state_file"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$state_file" | awk '{print $2}')" = "GATES" ]
}

# ─── profile (C3 risk-surface matching) ────────────────────────────────────

@test "profile: e2e/evidence/** fixture files classify under 'fixtures' surface (low), not unknown_surface_profile" {
  make_commit "base" "README.md" "base"
  local base_sha; base_sha="$(git rev-parse HEAD)"
  make_commit "add e2e evidence fixture" \
    "plugins/aid-orchestrator/scripts/tests/e2e/evidence/dummy-fixture/output.json" '{"k":"v"}'
  local head_sha; head_sha="$(git rev-parse HEAD)"
  run "$PREFILTER" profile "README.md" "$TEST_EVIDENCE_DIR" --range "${base_sha}..${head_sha}"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "risk_profile=low" ]]
  run jq -r '.review_profile.risk_profile' "$TEST_EVIDENCE_DIR/review-profile.json"
  [ "$output" = "low" ]
  run jq -r '.review_profile.matched_surfaces[]' "$TEST_EVIDENCE_DIR/review-profile.json"
  [[ "$output" == *"fixtures"* ]]
}

# ─── P079 Step 9 (IMP-474): one seeding rule, pinned by shape ────────────────
#
# A live run seeded step 0 by hand and let classify seed every other step. No
# code path ever made step 0 special — the inconsistency was controller
# behaviour — so the fix is the instruction (pipeline.md) plus this pin: any
# future change that made classify's product differ by step number, or stopped
# it being idempotent, fails here.

@test "P079 Step 9: classify produces the SAME seed shape for step 0 and step 3 (no step-0 special case)" {
  make_commit "add helper script" "lib/helper.sh" "#!/bin/bash"$'\n'"echo hello"
  seed_base_commit
  run "$PREFILTER" classify 0 "$TEST_EVIDENCE_DIR"; [ "$status" -eq 10 ]
  run "$PREFILTER" classify 3 "$TEST_EVIDENCE_DIR"; [ "$status" -eq 10 ]

  local f0="$TEST_EVIDENCE_DIR/verifier-output-step-0.md"
  local f3="$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
  [ -f "$f0" ] && [ -f "$f3" ]
  # Field SETS, not bytes — timestamps and the step number legitimately differ.
  local keys0 keys3
  keys0="$(grep -oE '^[a-z_]+:' "$f0" | sort -u)"
  keys3="$(grep -oE '^[a-z_]+:' "$f3" | sort -u)"
  [ "$keys0" = "$keys3" ]
  [ -n "$keys0" ]
  grep -q '^_generated_by:' "$f0"
  grep -q '^_generated_by:' "$f3"
}

@test "P079 Step 9: re-running classify for the same step is idempotent in shape" {
  make_commit "add helper script" "lib/helper.sh" "#!/bin/bash"$'\n'"echo hello"
  seed_base_commit
  run "$PREFILTER" classify 2 "$TEST_EVIDENCE_DIR"; [ "$status" -eq 10 ]
  local first; first="$(grep -oE '^[a-z_]+:' "$TEST_EVIDENCE_DIR/verifier-output-step-2.md" | sort -u)"
  run "$PREFILTER" classify 2 "$TEST_EVIDENCE_DIR"; [ "$status" -eq 10 ]
  local second; second="$(grep -oE '^[a-z_]+:' "$TEST_EVIDENCE_DIR/verifier-output-step-2.md" | sort -u)"
  [ "$first" = "$second" ]
}
