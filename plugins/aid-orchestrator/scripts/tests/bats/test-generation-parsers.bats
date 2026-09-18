#!/usr/bin/env bats
# aid-tier: t2
# test-generation-parsers.bats — P074 Step 17: parser and diagnosis defect
# fixes for the three generation defects found live on 2026-08-04.
#
#   1. (retired by P093: the CP1 gate no longer parses a free-text adjudicator
#      file; its round evidence is covered by test-cp1-gate.bats.)
#   2. aid-plan-to-epic.sh / aid-epic-to-json.sh — the steps-table cell
#      grammar is a two-rule escape (`\\` then `\|`), decoded by a
#      character-walk splitter; a short row is a hard arity error, never
#      silently padded with `---`.
#   3. aid-auto-pipeline.sh — an off-target-branch run (ensure_manifest rc=3)
#      is diagnosed as exactly that, with NO EPIC-grammar advice stacked on.
#
# fd-3 discipline: every heavyweight invocation runs with `3>&-`.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  EPIC_TO_JSON="$AID_PLUGIN_PATH/scripts/aid-epic-to-json.sh"
  PIPELINE="$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/templates/plan.schema.json"
  export PLAN_TO_EPIC EPIC_TO_JSON PIPELINE SCHEMA
}

teardown() {
  teardown_test_evidence_dir
}

# ─── steps-table escape grammar (plan-to-epic → epic-to-json) ──────────────

# _write_rt_plan <step2-objective> — two-step, one-EPIC plan; Step 2 depends
# on Step 1 and carries the objective under test.
_write_rt_plan() {
  RTPROJ="$TEST_TMPDIR/rt-proj"
  mkdir -p "$RTPROJ/.aid-o/work/plan-state" "$RTPROJ/.aid-o/config" "$RTPROJ/epics"
  # IMP-503: DoD gate resolution requires a real execution.yaml at the
  # project's state root (fail-closed). An empty gates: mapping is a valid
  # outcome; this fixture just needs to exist and parse. rt-proj is not
  # itself a git repo (a plain tmpdir); aid_canonicalize_project_root's
  # "dogfood escape" honours an explicit root AS GIVEN when it carries
  # .aid-o/work/plan-state, without requiring a git-common-dir lookup.
  printf 'gates: {}\n' > "$RTPROJ/.aid-o/config/execution.yaml"
  export AID_PROJECT_ROOT="$RTPROJ"
  cat > "$RTPROJ/plan.md" <<EOF
---
id: P901
type: plan
status: ready
risk: low
---

# Plan: Round trip fixture

## Goal

Exercise the table escape grammar.

## Implementation Steps

**EPIC 1: Steps 1-2 — Fixture**

### Step 1: First

**Objective:** Do the first thing.

**Files:**
- Modify: \`a.txt\`

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] It happened.

**Effort:** S
**AID Role:** backend

### Step 2: Second

**Objective:** ${1}

**Files:**
- Modify: \`b.txt\`

**Dependencies:**
- Depends on: Step 1

**Acceptance Criteria:**
- [ ] It happened too.

**Effort:** S
**AID Role:** backend
EOF
  aid_fixture_seed_plan_review "$RTPROJ" "$RTPROJ/plan.md"
  export RTPROJ
}

# _round_trip — plan → EPIC → plan.json; leaves PLAN_JSON pointing at the result.
_round_trip() {
  ( cd "$RTPROJ" && bash "$PLAN_TO_EPIC" \
      --plan plan.md --phase 1 --total 1 \
      --epic-template "$AID_PLUGIN_PATH/defaults/templates/epic.md" \
      --output-dir epics --counter-yaml counter.yaml --project-root . ) 3>&-
  EPIC_FILE="$(ls "$RTPROJ"/epics/E-*.md | head -1)"
  ( cd "$RTPROJ" && bash "$EPIC_TO_JSON" \
      --epic "$EPIC_FILE" --schema "$SCHEMA" --output-dir out ) 3>&-
  PLAN_JSON="$(find "$RTPROJ/out" -name plan.json | head -1)"
  export EPIC_FILE PLAN_JSON
}

@test "P074 Step 17: an Objective with ONE pipe round-trips intact and depends_on lands correctly" {
  _write_rt_plan 'Choose between a|b at runtime.'
  _round_trip
  [ "$(jq -r '.steps[1].objective' "$PLAN_JSON")" = "Choose between a|b at runtime." ]
  # the dependency column survived the pipe in the objective column
  run jq -r '.steps[1].inputs[]' "$PLAN_JSON"
  [[ "$output" == *"step_1_backend"* ]]
}

@test "P074 Step 17: an Objective with TWO pipes AND a trailing literal backslash round-trips byte-identically" {
  _write_rt_plan 'Choose a|b then c|d and end with backslash \'
  _round_trip
  [ "$(jq -r '.steps[1].objective' "$PLAN_JSON")" = 'Choose a|b then c|d and end with backslash \' ]
  run jq -r '.steps[1].inputs[]' "$PLAN_JSON"
  [[ "$output" == *"step_1_backend"* ]]
}

@test "P074 Step 17: a legacy escape-free row decodes byte-identically" {
  _write_rt_plan 'A perfectly ordinary objective without special characters.'
  _round_trip
  [ "$(jq -r '.steps[1].objective' "$PLAN_JSON")" = "A perfectly ordinary objective without special characters." ]
}

@test "P074 Step 17: a hand-broken FOUR-field row dies naming the row and its field count vs five" {
  _write_rt_plan 'A perfectly ordinary objective without special characters.'
  _round_trip
  # break row 2 down to four fields (the old code silently padded with ---)
  sed -i 's/^| 2 | backend | A perfectly.*$/| 2 | backend | Broken objective row | 1 |/' "$EPIC_FILE"
  run bash -c "cd '$RTPROJ' && bash '$EPIC_TO_JSON' --epic '$EPIC_FILE' --schema '$SCHEMA' --output-dir out-broken" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"has 4 fields, expected 5"* ]]
  [[ "$output" == *"| 2 | backend | Broken objective row | 1 |"* ]]
}

# ─── branch diagnosis (aid-auto-pipeline.sh, ensure_manifest rc=3) ─────────

# _pipeline_repo [strict-epic-declaration] — a minimal repo on main with a
# gitignored .aid-o/ and a lifecycle_strict plan carrying the declaration.
_pipeline_repo() {
  local decl="${1:-**EPIC 1: alpha (Steps 1-1)**}"
  PREPO="$TEST_TMPDIR/pipe-repo"
  mkdir -p "$PREPO"
  ( cd "$PREPO"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email t@t.io; git config user.name T
    printf '.aid-o/\n' > .gitignore
    echo seed > seed; git add -A; git commit -q -m seed
    mkdir -p .aid-o/plans
    cat > .aid-o/plans/P900-x.md <<PLAN
---
id: P900
type: regular
risk: low
lifecycle_strict: true
---
# Plan: P900

$decl

### Step 1: backend — do alpha
**Files:**
- Create: \`src/a.py\`
PLAN
  )
  export PREPO
}

@test "P074 Step 17: an off-target-branch run is diagnosed as a branch problem with ZERO grammar advice" {
  _pipeline_repo
  ( cd "$PREPO" && git checkout -q -b side )
  run bash -c "cd '$PREPO' && bash '$PIPELINE' --plan .aid-o/plans/P900-x.md --queue-mode chain" 3>&-
  [ "$status" -eq 6 ]
  [[ "$output" == *"you are on 'side' but lifecycle writes require 'main'"* ]]
  [[ "$output" == *"git checkout main"* ]]
  [[ "$output" == *"plan-start commits them on the plan branch only"* ]]   # the old "run from its plan worktree" advice described a state that already held (WAN issue 1)
  [[ "$output" != *"grammar"* ]]
  [[ "$output" != *"EPIC N"* ]]
}

@test "P074 Step 17 (review 2): AID_LIFECYCLE_MIGRATION=1 does NOT reroute an off-target strict run into grammar advice" {
  _pipeline_repo
  ( cd "$PREPO" && git checkout -q -b side )
  run bash -c "cd '$PREPO' && AID_LIFECYCLE_MIGRATION=1 bash '$PIPELINE' --plan .aid-o/plans/P900-x.md --queue-mode chain" 3>&-
  [ "$status" -eq 6 ]
  [[ "$output" == *"you are on 'side' but lifecycle writes require 'main'"* ]]
  [[ "$output" != *"grammar"* ]]
  [[ "$output" != *"EPIC N"* ]]
}

@test "P074 Step 17 (review 2): a LEGACY off-target run keeps its P073 proceed contract but its WARN is branch-diagnosed and grammar-free" {
  _pipeline_repo
  # strip the strict opt-in → legacy plan, which proceeds under the audited
  # migration WARN instead of failing closed (P073 Step 6 contract)
  sed -i '/^lifecycle_strict: true$/d' "$PREPO/.aid-o/plans/P900-x.md"
  ( cd "$PREPO" && git checkout -q -b side )
  run bash -c "cd '$PREPO' && bash '$PIPELINE' --plan .aid-o/plans/P900-x.md --queue-mode chain" 3>&-
  [[ "$output" == *"AUDITED migration"* ]]
  [[ "$output" == *"you are on 'side' but lifecycle writes require 'main'"* ]]
  # the WARN line itself carries no grammar advice
  warn_line="$(printf '%s\n' "$output" | grep 'AUDITED migration' | head -1)"
  [[ "$warn_line" != *"grammar"* ]]
  [[ "$warn_line" != *"EPIC N"* ]]
}

@test "P074 Step 17: an on-target GRAMMAR failure keeps the grammar message" {
  _pipeline_repo '**EPIC 1 ambiguous no colon no backlog form**'
  run bash -c "cd '$PREPO' && bash '$PIPELINE' --plan .aid-o/plans/P900-x.md --queue-mode chain" 3>&-
  [ "$status" -eq 6 ]
  [[ "$output" == *"grammar"* ]]
  [[ "$output" == *"MUST have a durable"* ]]
  [[ "$output" != *"you are on"* ]]
}
