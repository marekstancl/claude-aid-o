#!/usr/bin/env bats
# aid-tier: t2
# test-generation-parsers.bats — P074 Step 17: parser and diagnosis defect
# fixes for the three generation defects found live on 2026-08-04.
#
#   1. aid-cp1-gate.sh — the adjudicator block-scalar empty-list forms
#      (`- []`, `- none`, `- (none)`) parse as EMPTY; a genuine item still
#      fails; a nested-only `accepted_blockers:`/`rejected_blockers:` key is a
#      loud structural error instead of a silent "no field" pass.
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
  GATE="$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh"
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  EPIC_TO_JSON="$AID_PLUGIN_PATH/scripts/aid-epic-to-json.sh"
  PIPELINE="$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/templates/plan.schema.json"
  export GATE PLAN_TO_EPIC EPIC_TO_JSON PIPELINE SCHEMA
}

teardown() {
  teardown_test_evidence_dir
}

# ─── adjudicator fixtures (aid-cp1-gate.sh) ────────────────────────────────

# _gate_fixture — a high-risk plan + full CP1-deep evidence + a clean C0
# review, with the C0-verify and ledger shell-outs stubbed to OK so the ONLY
# thing deciding pass/fail is the adjudicator read under test.
_gate_fixture() {
  GPROJ="$TEST_TMPDIR/gate-proj"
  GEV="$GPROJ/.aid-o/work/evidence/P902/cp1-deep"
  mkdir -p "$GEV" "$TEST_TMPDIR/stub"
  cat > "$GPROJ/plan.md" <<'EOF'
---
id: P902
type: plan
status: draft
risk: high
---

# Plan: Gate fixture

## Context

authenticate call present.
EOF
  local f
  for f in cp1-lens-L1-behavior.md cp1-lens-L2-feasibility.md cp1-lens-L3-enforcement.md; do
    printf 'findings: []\nstop_rule_blockers: []\n' > "$GEV/$f"
  done
  printf '{"schema_version":"aid-2.0","artifact_type":"c0_plan_review","review_status":"pass","blocking_findings":false,"findings":[]}\n' \
    > "$GPROJ/.aid-o/work/evidence/P902/c0-plan-review.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/stub/ok.sh"
  chmod +x "$TEST_TMPDIR/stub/ok.sh"
  export AID_CP1_GATE_C0_REVIEW_BIN="$TEST_TMPDIR/stub/ok.sh"
  export AID_CP1_GATE_LEDGER_BIN="$TEST_TMPDIR/stub/ok.sh"
  export GPROJ GEV
}

_run_gate() {
  run bash "$GATE" --plan "$GPROJ/plan.md" --project-root "$GPROJ" 3>&-
}

@test "P074 Step 17: adjudicator block item '- []' parses as EMPTY (pass)" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers:\n  - []\nrejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -eq 0 ]
}

@test "P074 Step 17: adjudicator block item '- none' parses as EMPTY, case- and whitespace-tolerant" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers:\n  -   None  \nrejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -eq 0 ]
}

@test "P074 Step 17: adjudicator block item '- (none)' parses as EMPTY (pass)" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers:\n  - (None)\nrejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -eq 0 ]
}

@test "P074 Step 17: inline 'accepted_blockers: []' (canonical form) still passes — regression" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers: []\nrejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -eq 0 ]
}

@test "P074 Step 17: a genuine '- <text>' blocker item still FAILS the gate" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers:\n  - auth bypass via direct db query at auth.py:42\nrejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved blockers"* ]]
  [[ "$output" == *"auth bypass"* ]]
}

@test "P074 Step 17: a nested-only 'accepted_blockers:' key is a LOUD structural error naming the line (was a silent no-field pass)" {
  _gate_fixture
  printf 'verdict: pass\nsummary:\n  accepted_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"INDENTED/nested 'accepted_blockers:'"* ]]
  [[ "$output" == *"line 3"* ]]
}

@test "P074 Step 17: a nested-only 'rejected_blockers:' key gets the same structural error" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers: []\nnested:\n  rejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"INDENTED/nested 'rejected_blockers:'"* ]]
  [[ "$output" == *"line 4"* ]]
}

@test "P074 Step 17 (review): a blank + comment line between '- []' and a REAL item does not hide the blocker" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers:\n  - []\n\n  # reviewer note\n  - auth bypass via direct db query at auth.py:42\nrejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved blockers"* ]]
  [[ "$output" == *"auth bypass"* ]]
}

@test "P074 Step 17 (review): blank and comment lines between EMPTY forms only still parse as EMPTY (pass)" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers:\n  - []\n\n  # nothing survived adjudication\n  - none\nrejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -eq 0 ]
}

@test "P074 Step 17 (review): an indented 'accepted_blockers:' duplicate errors loudly EVEN when a valid top-level key exists" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers: []\nmetadata:\n  accepted_blockers: real blocker hidden here\nrejected_blockers: []\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"INDENTED/nested 'accepted_blockers:'"* ]]
  [[ "$output" == *"line 4"* ]]
}

@test "P074 Step 17 (review 2): a REAL blocker on a no-final-newline last line still FAILS the gate" {
  _gate_fixture
  # printf WITHOUT a trailing \n: a wc-l-bounded walk would drop this line
  # and report EMPTY, silently passing a genuine blocker.
  printf 'verdict: pass\naccepted_blockers:\n  - auth bypass via direct db query at auth.py:42' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved blockers"* ]]
  [[ "$output" == *"auth bypass"* ]]
}

@test "P074 Step 17 (review 2): an EMPTY form on a no-final-newline last line still parses as EMPTY (pass)" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers:\n  - none' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -eq 0 ]
}

@test "P074 Step 17 (review): an indented 'rejected_blockers:' duplicate errors loudly EVEN when a valid top-level key exists" {
  _gate_fixture
  printf 'verdict: pass\naccepted_blockers: []\nrejected_blockers: []\nmetadata:\n  rejected_blockers: shadowed duplicate\n' > "$GEV/cp1-adjudicator.md"
  _run_gate
  [ "$status" -ne 0 ]
  [[ "$output" == *"INDENTED/nested 'rejected_blockers:'"* ]]
  [[ "$output" == *"line 5"* ]]
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
