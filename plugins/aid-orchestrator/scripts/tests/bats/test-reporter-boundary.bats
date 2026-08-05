#!/usr/bin/env bats
# test-reporter-boundary.bats — P073 Step 12: the immutable review boundary
# (P082).
#
# The Reporter contract ordered its delivery report and boundary manifest to be
# COMMITTED. That order was unexecutable three independent ways at once:
#   1. pipeline.md invalidates the plan-final review on ANY tracked write while
#      the review is in progress — so obeying the order destroyed the review;
#   2. the ordered path `.aid-o/reports/` is gitignored, so the commit could
#      not happen at all;
#   3. the reporter contract itself said so, two paragraphs below the order.
#
# The fix: the Reporter writes run-scoped evidence only, and the CONTROLLER
# renders the human/CI projections at plan-close — after merge, outside any
# freeze window, where a projection cannot cost a review.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  REPORTER="$AID_PLUGIN_PATH/agents/reporter.md"
  PIPELINE_SKILL="$AID_PLUGIN_PATH/skills/pipeline.md"
  export PFSM REPORTER PIPELINE_SKILL
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
}

teardown() {
  teardown_test_evidence_dir
}

# _render <plan_id> — drives the real projection renderer out of the FSM.
_render() {
  bash -c '
    set -uo pipefail
    SCRIPT_DIR="'"$AID_PLUGIN_PATH"'/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    eval "$(sed -n "/^_pfsm_render_close_projections()/,/^# _pfsm_lock_held /p" "'"$PFSM"'")"
    cd "'"$ROOT"'"
    _pfsm_render_close_projections "'"$ROOT"'" "$1"
  ' _ "$1"
}

# _seed_manifest_with_run <plan_id> — a manifest pointing at a plan-final run.
_seed_manifest_with_run() {
  local plan_id="$1"
  ( cd "$ROOT" && git init -q && git config user.email t@e.com && git config user.name T \
      && printf 'seed\n' > README.md && git add -A && git commit -qm seed ) >/dev/null 2>&1
  local head; head="$(cd "$ROOT" && git rev-parse HEAD)"
  local rel=".aid-o/work/evidence/${plan_id}/R-${plan_id}-final-1"
  mkdir -p "$ROOT/$rel"
  bash -c '
    set -uo pipefail
    SCRIPT_DIR="'"$AID_PLUGIN_PATH"'/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    cd "'"$ROOT"'"
    plan_manifest_init '"$plan_id"' plan/'"$plan_id"' main "'"$head"'" "'"$head"'" plan_branch >/dev/null
    # P073 Step 15 made the protected-path set part of the freeze contract:
    # arguments 7 and 8 are REQUIRED. This fixture predated that and called the
    # 6-argument form, so the freeze warned and recorded NOTHING — every test
    # below then failed on a missing run directory rather than on its subject.
    printf "%s\0" "scripts/a.sh" > "'"$BATS_TEST_TMPDIR"'/reporter-prot.nul"
    plan_manifest_freeze_candidate '"$plan_id"' "'"$head"'" "'"$head"'" \
      R-'"$plan_id"'-final-1 "'"$rel"'" "2026-08-05T00:00:00Z" \
      "'"$BATS_TEST_TMPDIR"'/reporter-prot.nul" true >/dev/null
  '
  echo "$ROOT/$rel"
}

_seed_delivery_json() {
  local dir="$1"
  jq -n --arg h "$(cd "$ROOT" && git rev-parse HEAD)" \
    '{summary:"Two EPICs delivered against the frozen candidate.",
      head:$h, candidate_sha:$h,
      epics:[{epic_id:"E-900-1_2", verdict:"pass"},{epic_id:"E-900-2_2", verdict:"pass"}],
      delivered_paths:["scripts/a.sh","scripts/b.sh"]}' > "$dir/delivery-report.json"
}

# ─── the contract no longer orders a commit ───────────────────────────────

@test "P073 Step 12: the Reporter contract no longer claims its outputs are committed" {
  run bash -c "sed -n '/^## Output Format/,/^## Constraints/p' '$REPORTER' | grep -c 'Committed'"
  [ "$output" = "0" ]
}

@test "P073 Step 12: the Reporter contract no longer orders the boundary manifest to be committed (AC7)" {
  run bash -c "! grep -n 'boundary.md.*It must be committed' '$REPORTER'"
  [ "$status" -eq 0 ]
}

@test "P073 Step 12: the Reporter is told, in its constraints, never to write outside the run evidence dir" {
  run grep -c 'NEVER.*stage, commit, or write outside the run evidence directory' "$REPORTER"
  [ "$output" -ge 1 ]
}

@test "P073 Step 12: the Reporter writes delivery-report.json into the RUN evidence dir, not .aid-o/reports" {
  run grep -c '{evidence_dir}/delivery-report.json' "$REPORTER"
  [ "$output" -ge 1 ]
  # And it no longer names .aid-o/reports as ITS output path.
  run bash -c "sed -n '/^## Output Format/,/^## Constraints/p' '$REPORTER' | grep -c 'Write this file to \`.aid-o/reports'"
  [ "$output" = "0" ]
}

# ─── the rule lives in exactly one place ──────────────────────────────────

@test "P073 Step 12: pipeline.md states the boundary rule once, and role-cards REFERENCES it" {
  run grep -c 'THE PLAN-FINAL BOUNDARY RULE' "$PIPELINE_SKILL"
  [ "$output" = "1" ]
  run grep -c 'THE PLAN-FINAL BOUNDARY RULE' "$AID_PLUGIN_PATH/skills/role-cards.md"
  [ "$output" = "1" ]
  # The reference must not be a second copy of the rule's substance.
  run grep -c 'A tracked candidate write is a FIX' "$AID_PLUGIN_PATH/skills/role-cards.md"
  [ "$output" = "0" ]
}

# ─── the controller renders the projections ───────────────────────────────

@test "P073 Step 12: plan-close renders both projections from the run-scoped JSON" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  _seed_delivery_json "$dir"

  run _render P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"rendered human projections"* ]]

  [ -s "$ROOT/.aid-o/reports/P900-delivery.md" ]
  [ -s "$ROOT/.aid-o/reports/P900-boundary.md" ]
  run grep -c 'Two EPICs delivered against the frozen candidate' "$ROOT/.aid-o/reports/P900-delivery.md"
  [ "$output" = "1" ]
  run grep -c 'E-900-1_2: pass' "$ROOT/.aid-o/reports/P900-delivery.md"
  [ "$output" = "1" ]
  run grep -c 'scripts/a.sh' "$ROOT/.aid-o/reports/P900-delivery.md"
  [ "$output" = "1" ]
  run grep -c 'boundary_complete: true' "$ROOT/.aid-o/reports/P900-boundary.md"
  [ "$output" = "1" ]
}

@test "P073 Step 12: the projection records where the authoritative artifact lives" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  _seed_delivery_json "$dir"
  run _render P900
  [ "$status" -eq 0 ]
  run grep -c 'delivery-report.json' "$ROOT/.aid-o/reports/P900-delivery.md"
  [ "$output" -ge 1 ]
  run grep -c 'PROJECTION rendered at close' "$ROOT/.aid-o/reports/P900-delivery.md"
  [ "$output" = "1" ]
}

@test "P073 Step 12: rendering is idempotent — a re-close overwrites rather than accumulating" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  _seed_delivery_json "$dir"
  run _render P900
  [ "$status" -eq 0 ]
  run _render P900
  [ "$status" -eq 0 ]
  run bash -c "ls '$ROOT/.aid-o/reports' | wc -l"
  [ "$output" = "2" ]
}

# ─── the projection is NEVER a close blocker ──────────────────────────────

@test "P073 Step 12: a MISSING delivery-report.json warns and does not fail the close" {
  _seed_manifest_with_run P900 >/dev/null
  run _render P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"no verified delivery-report.json"* ]]
  [[ "$output" == *"not rendered"* ]]
}

@test "P073 Step 12: an UNPARSEABLE delivery-report.json warns and does not fail the close" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  printf 'not json at all\n' > "$dir/delivery-report.json"
  run _render P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a JSON object"* ]]
}

@test "P073 Step 12: an UNWRITABLE reports directory warns and does not fail the close" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  _seed_delivery_json "$dir"
  mkdir -p "$ROOT/.aid-o/reports"
  chmod a-w "$ROOT/.aid-o/reports"
  run _render P900
  local rc="$status"
  chmod u+w "$ROOT/.aid-o/reports"
  [ "$rc" -eq 0 ]
  [[ "$output" == *"projection skipped"* || "$output" == *"cannot write"* ]]
  [[ "$output" == *"authoritative"* ]]
}

@test "P073 Step 12: a plan with no recorded plan-final run warns and does not fail the close" {
  ( cd "$ROOT" && git init -q && git config user.email t@e.com && git config user.name T \
      && printf 'seed\n' > README.md && git add -A && git commit -qm seed ) >/dev/null 2>&1
  run _render P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"no plan-final run directory"* ]]
}

# ─── a Reporter round moves nothing ───────────────────────────────────────

@test "P073 Step 12: a Reporter round writing ONLY run evidence leaves the candidate and the tree untouched" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  local candidate_before head_before
  candidate_before="$( cd "$ROOT" && bash -c '
    SCRIPT_DIR="'"$AID_PLUGIN_PATH"'/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"; . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    plan_manifest_get P900 ".plan_boundary_manifest.candidate_sha"' )"
  head_before="$(cd "$ROOT" && git rev-parse HEAD)"

  # Exactly what the corrected contract tells the Reporter to do.
  mkdir -p "$dir/reporter"
  printf 'screenshot\n' > "$dir/reporter/shot.txt"
  _seed_delivery_json "$dir"
  printf -- '---\nplan_id: "P900"\nboundary_complete: true\n---\n' > "$dir/P900-boundary.md"

  # Nothing tracked moved: no commit, and no tracked file is dirty.
  [ "$(cd "$ROOT" && git rev-parse HEAD)" = "$head_before" ]
  [ -z "$(cd "$ROOT" && git status --porcelain --untracked-files=no)" ]
  local candidate_after
  candidate_after="$( cd "$ROOT" && bash -c '
    SCRIPT_DIR="'"$AID_PLUGIN_PATH"'/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"; . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    plan_manifest_get P900 ".plan_boundary_manifest.candidate_sha"' )"
  [ "$candidate_after" = "$candidate_before" ]
}

# ─── Codex-review findings on the first cut of this step ──────────────────

@test "P073 Step 12 (review finding 1): a malformed delivery-report.json yields NO projection, not a partial one" {
  # The formatting jq calls used to run inside the redirection group with
  # errors sent to /dev/null, and a trailing printf made the group succeed —
  # so a report whose .epics was a string was published WITHOUT its verdict
  # section, misrepresenting the authoritative JSON as complete.
  local dir; dir="$(_seed_manifest_with_run P900)"
  jq -n '{summary:"Delivered.", epics:"not-an-array", delivered_paths:[]}' \
    > "$dir/delivery-report.json"

  run _render P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"does not have the expected shape"* ]]
  [ ! -e "$ROOT/.aid-o/reports/P900-delivery.md" ]
  [ ! -e "$ROOT/.aid-o/reports/P900-boundary.md" ]
}

@test "P073 Step 12 (review finding 1): no temp file is left behind by a refused projection" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  jq -n '{summary:"Delivered.", delivered_paths:"not-an-array"}' > "$dir/delivery-report.json"
  run _render P900
  [ "$status" -eq 0 ]
  run bash -c "ls '$ROOT/.aid-o/reports'/*.tmp.* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "P073 Step 12 (review finding 2): a newline in a JSON value cannot inject a frontmatter key" {
  # A `head` of "abc\nboundary_complete: false" used to become a second YAML
  # key, so a downstream consumer read a different document than was rendered.
  local dir; dir="$(_seed_manifest_with_run P900)"
  jq -n '{summary:"Delivered.",
          head:"abc\nboundary_complete: false",
          candidate_sha:"def\nplan_id: \"P999\"",
          epics:[], delivered_paths:[]}' > "$dir/delivery-report.json"

  run _render P900
  [ "$status" -eq 0 ]

  # The injected keys are inert: they sit inside a quoted scalar.
  run grep -c '^boundary_complete: false' "$ROOT/.aid-o/reports/P900-delivery.md"
  [ "$output" = "0" ]
  run grep -c '^plan_id: "P999"' "$ROOT/.aid-o/reports/P900-boundary.md"
  [ "$output" = "0" ]
  # The boundary manifest still says what the renderer meant it to say.
  run grep -c '^boundary_complete: true' "$ROOT/.aid-o/reports/P900-boundary.md"
  [ "$output" = "1" ]
  # And a YAML parser reads back the value as ONE scalar, not two keys.
  run bash -c "sed -e '1d' -e '/^---$/,\$d' '$ROOT/.aid-o/reports/P900-boundary.md' | yq -r '.plan_id'"
  [ "$output" = "P900" ]
  run bash -c "sed -e '1d' -e '/^---$/,\$d' '$ROOT/.aid-o/reports/P900-boundary.md' | yq -r '.boundary_complete'"
  [ "$output" = "true" ]
}

@test "P073 Step 12 (review finding 3): the renderer refuses to write while the plan is not CLOSED" {
  # The caller reaches the renderer after the CLOSED transition, but the
  # manifest mirror update above it is best-effort — so an unexpected state
  # here means a review may still be open, and writing into .aid-o/reports/
  # would be exactly the tracked write this step exists to keep out of a
  # freeze window.
  local dir; dir="$(_seed_manifest_with_run P900)"
  _seed_delivery_json "$dir"
  # A real plan-state record in OPEN. (A manifest alone carries no plan state,
  # and with no record at all the guard deliberately does not block — there is
  # nothing to contradict.)
  run bash -c '
    set -uo pipefail
    SCRIPT_DIR="'"$AID_PLUGIN_PATH"'/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    cd "'"$ROOT"'"
    plan_state_init P900 plan_branch plan/P900 main >/dev/null
  '
  [ "$status" -eq 0 ]

  run _render P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"not CLOSED"* ]]
  [[ "$output" == *"after the review boundary has closed"* ]]
  [ ! -e "$ROOT/.aid-o/reports/P900-delivery.md" ]
}

# ─── Regression caught by the plan-final boundary suite ───────────────────
# The renderer writes to exactly the two paths aid-plan-close-check.sh check2
# reads a `Head:` field from to verify freshness. Emitting it only when the
# JSON happened to carry one — and never in the boundary manifest — meant
# rendering OVERWROTE reports that had it and broke the very close this
# renderer runs inside. It passed at the pre-P073 baseline and failed after
# Step 12, so it was ours.

@test "P073 Step 12 (regression): BOTH projections always carry a Head field" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  _seed_delivery_json "$dir"
  run _render P900
  [ "$status" -eq 0 ]
  run grep -c '^Head: ' "$ROOT/.aid-o/reports/P900-delivery.md"
  [ "$output" = "1" ]
  run grep -c '^Head: ' "$ROOT/.aid-o/reports/P900-boundary.md"
  [ "$output" = "1" ]
}

@test "P073 Step 12 (regression): a report JSON with NO head still yields a Head field, from the live HEAD" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  jq -n '{summary:"Delivered.", epics:[], delivered_paths:[]}' > "$dir/delivery-report.json"
  run _render P900
  [ "$status" -eq 0 ]
  local live; live="$(cd "$ROOT" && git rev-parse HEAD)"
  run bash -c "sed -e '1d' -e '/^---$/,\$d' '$ROOT/.aid-o/reports/P900-delivery.md' | yq -r '.Head'"
  [ "$output" = "$live" ]
  run bash -c "sed -e '1d' -e '/^---$/,\$d' '$ROOT/.aid-o/reports/P900-boundary.md' | yq -r '.Head'"
  [ "$output" = "$live" ]
}

@test "P073 Step 12 (regression): the report's OWN head wins over the live HEAD, so a stale report still reads stale" {
  local dir; dir="$(_seed_manifest_with_run P900)"
  jq -n '{summary:"Delivered.", head:"0000000000000000000000000000000000000000",
          epics:[], delivered_paths:[]}' > "$dir/delivery-report.json"
  run _render P900
  [ "$status" -eq 0 ]
  run bash -c "sed -e '1d' -e '/^---$/,\$d' '$ROOT/.aid-o/reports/P900-delivery.md' | yq -r '.Head'"
  [ "$output" = "0000000000000000000000000000000000000000" ]
}
