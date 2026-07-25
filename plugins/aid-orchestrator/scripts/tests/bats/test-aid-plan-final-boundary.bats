#!/usr/bin/env bats
# test-aid-plan-final-boundary.bats — P068 "Plan-final release boundary"
# (EPIC E-068-1_2). THE single mandatory integration suite for this plan (see
# .aid-o/plans/P068-plan-final-release-boundary.md — this file is named and
# owned by the plan itself, not invented per-step). Every later step in this
# plan ADDS test blocks here rather than creating a sibling suite — keep new
# coverage inside the matching `# ─── <Command/Library> ───` describe-block
# below, adding a new block only for a genuinely new command under test.
#
# Step 1 seeds it with the boundary's opening half:
#   - aid-plan-fsm.sh plan-finalize --stage sync   (EPIC terminality + merge)
#   - aid-plan-fsm.sh plan-finalize --stage freeze (the immutable candidate)
#   - lib/aid-plan-manifest.sh's candidate freeze/clear pair (the atomic
#     candidate_sha + candidate_frozen_at write)
#   - aid-release.sh prepare-plan (version preparation, no tag, no sweep)
#
# Like test-aid-plan-release-boundary.bats, this suite creates a REAL Git
# repository per test and is deliberately NOT part of the aggregate
# `run-all-tests.sh` job — see .github/workflows/ci.yml's dedicated
# `plan-final-tests` job and run-all-tests.sh's DELEGATED exclusion.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_STATE_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh"
  PLAN_MANIFEST_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh"
  PLAN_FSM_CLI="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  RELEASE_CLI="$AID_PLUGIN_PATH/scripts/aid-release.sh"
  export PLAN_STATE_LIB PLAN_MANIFEST_LIB PLAN_FSM_CLI RELEASE_CLI

  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"

  # shellcheck disable=SC1090
  source "$PLAN_STATE_LIB"
  # shellcheck disable=SC1090
  source "$PLAN_MANIFEST_LIB"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixtures ────────────────────────────────────────────────────────────

PLAN_ID="P068"

# _manifest_field <plan_id> <field> — raw payload field, "null" when absent.
_manifest_field() {
  jq -r --arg f "$2" '.plan_boundary_manifest[$f]' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${1}/plan-boundary-manifest.json"
}

# _bootstrap <plan_id> — a plan branch + manifest + state file, built through
# the REAL library entry points (never a hand-written fixture manifest), so a
# drift between what the library writes and what these tests assume is caught
# by the bootstrap rather than hidden by it.
_bootstrap() {
  local plan_id="${1:-$PLAN_ID}"
  # Mirror production: `.aid-o/work/` is gitignored, so branch switching never
  # deletes the plan state or the manifest out from under the CLI.
  printf '.aid-o/work/\n' > "$TEST_PROJECT_ROOT/.gitignore"
  git -C "$TEST_PROJECT_ROOT" add -- .gitignore
  git -C "$TEST_PROJECT_ROOT" commit -q -m "gitignore the runtime area"
  local base; base="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  git -C "$TEST_PROJECT_ROOT" branch "plan/${plan_id}" "$base"
  plan_state_init "$plan_id" "plan_branch" "plan/${plan_id}" "main"
  plan_manifest_init "$plan_id" "plan/${plan_id}" "main" "$base" "$base" "plan_branch"
}

# _add_epic <plan_id> <epic_id> — one epic_runs[] entry, lineage proven.
_add_epic() {
  local plan_id="$1" epic_id="$2"
  local base; base="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/${plan_id}")"
  plan_manifest_add_epic "$plan_id" "$epic_id" "R-${epic_id}-1" \
    "task/${epic_id}/main" "$base" "plan/${plan_id}" \
    ".aid-o/work/evidence/${epic_id}/R-${epic_id}-1" "proven"
}

# _commit_on <branch> <file> <text> — one real commit, HEAD restored.
_commit_on() {
  local branch="$1" file="$2" text="$3" orig
  orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "$branch"
  printf '%s\n' "$text" > "$TEST_PROJECT_ROOT/$file"
  git -C "$TEST_PROJECT_ROOT" add -- "$file"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "$text"
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

# _finalize <plan_id> <stage> [extra...] — the CLI under test.
_finalize() {
  local plan_id="$1" stage="$2"; shift 2
  run bash "$PLAN_FSM_CLI" plan-finalize "$plan_id" --stage "$stage" \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-finalize --stage sync ──────────────────────────
# =============================================================================

# ─── AC3: sync refuses to proceed while any EPIC is pending or running,
#          NAMING it ────────────────────────────────────────────────────────
@test "AC3: --stage sync refuses while an EPIC is still running, and names it" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"     # created as `running`

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-terminal EPICs"* ]]
  [[ "$output" == *"E-068-1_2"* ]]
  [[ "$output" == *"running"* ]]

  # Nothing moved: still not PLAN_SYNC.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "PLAN_SYNC" ]
}

@test "AC3: --stage sync names a pending EPIC too (not only a running one)" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  # running → blocked is legal; blocked is equally non-terminal.
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "blocked"

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 1 ]
  [[ "$output" == *"E-068-1_2"* ]]
  [[ "$output" == *"blocked"* ]]
}

@test "--stage sync proceeds once every EPIC is terminal, and moves the plan to PLAN_SYNC" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  # A real merge commit is required for merged_to_plan; the plan branch head
  # is a legitimate commit to name here (this test is about sync, not about
  # re-proving epic-merge-to-plan's ancestry rules).
  local mc; mc="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "merged_to_plan" "$mc"

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]
}

# ─── Edge case: an abandoned EPIC with no recorded PM reason ──────────────
@test "--stage sync refuses an abandoned EPIC that carries no recorded reason" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  # Set the status directly, WITHOUT going through epic-complete --reason —
  # i.e. exactly the undocumented abandonment this guard exists to catch.
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "abandoned"

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 1 ]
  [[ "$output" == *"no recorded reason"* ]]
  [[ "$output" == *"E-068-1_2"* ]]
}

@test "--stage sync accepts an abandoned EPIC once a terminal_reason is recorded" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "abandoned"
  plan_manifest_update "$PLAN_ID" \
    '(.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == "E-068-1_2" then (.terminal_reason = "superseded by a different approach") else . end])'

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]
}

# ─── The merge is a MERGE, not a rebase (roadmap resolved decision 4) ─────
@test "--stage sync merges the target branch into the plan branch with --no-ff and preserves prior plan commits" {
  _bootstrap
  _commit_on "plan/$PLAN_ID" "plan-work.txt" "plan side work"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  _commit_on "main" "main-work.txt" "target side work"
  local target_head; target_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]

  local plan_after; plan_after="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  [ "$plan_after" != "$plan_before" ]

  # A merge commit: two parents, and BOTH prior heads are ancestors — a rebase
  # would have rewritten (and orphaned) the plan-side commit.
  run git -C "$TEST_PROJECT_ROOT" rev-parse "${plan_after}^2"
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$plan_before" "$plan_after"
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$target_head" "$plan_after"
  [ "$status" -eq 0 ]

  # HEAD is back where the operator left it.
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "main" ]
}

@test "--stage sync on a conflicting target transitions the plan to CONFLICT and exits 4" {
  _bootstrap
  _commit_on "plan/$PLAN_ID" "contested.txt" "plan version"
  _commit_on "main" "contested.txt" "target version"

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 4 ]
  [[ "$output" == *"MERGE CONFLICT"* ]]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CONFLICT" ]

  # No merge left half-done, and HEAD is restored.
  [ ! -f "$TEST_PROJECT_ROOT/.git/MERGE_HEAD" ]
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "main" ]
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-finalize --stage freeze ────────────────────────
# =============================================================================

# ─── AC4: after freeze, both SHAs are exact 40-hex and a new immutable run
#          directory exists ────────────────────────────────────────────────
@test "AC4: --stage freeze records candidate_sha + target_branch_head_at_candidate_freeze as exact 40-hex and creates the run directory" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]

  local plan_head target_head
  plan_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  target_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  run _manifest_field "$PLAN_ID" candidate_sha
  [[ "$output" =~ ^[0-9a-f]{40}$ ]]
  [ "$output" = "$plan_head" ]

  run _manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze
  [[ "$output" =~ ^[0-9a-f]{40}$ ]]
  [ "$output" = "$target_head" ]

  run _manifest_field "$PLAN_ID" plan_final_run_id
  [ "$output" = "R-${PLAN_ID}-final-1" ]
  run _manifest_field "$PLAN_ID" plan_final_evidence_dir
  [ "$output" = ".aid-o/work/evidence/${PLAN_ID}/R-${PLAN_ID}-final-1" ]
  [ -d "$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}/R-${PLAN_ID}-final-1" ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
  run _manifest_field "$PLAN_ID" plan_state
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC5: the SAME freeze write records candidate_frozen_at, atomically with
#          candidate_sha; the manifest is never valid with one set and the
#          other absent, in EITHER direction ────────────────────────────────
@test "AC5: the freeze write records candidate_frozen_at as an RFC 3339 UTC instant in the RUNTIME manifest" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  run _manifest_field "$PLAN_ID" candidate_frozen_at
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]

  # It lives in the RUNTIME plan-boundary manifest, deliberately NOT in the
  # .aid-lifecycle manifest (a different artifact with its own write path,
  # which cannot establish atomicity with the candidate write).
  if [[ -f "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/${PLAN_ID}.yaml" ]]; then
    run grep -c "candidate_frozen_at" "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/${PLAN_ID}.yaml"
    [ "$output" = "0" ]
  fi
}

@test "AC5: a manifest with candidate_sha set but candidate_frozen_at null is REJECTED by the validator" {
  _bootstrap
  # Reach past the public mutator on purpose: the invariant must hold against
  # any writer, including a hand edit or a future careless caller.
  local f="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  local head; head="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  jq --arg h "$head" '.plan_boundary_manifest.candidate_sha = $h
                      | .plan_boundary_manifest.candidate_frozen_at = null
                      | .plan_boundary_manifest.plan_state = "PLAN_GATES"' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"

  run plan_manifest_validate "$PLAN_ID"
  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate_sha and candidate_frozen_at must be null/non-null together"* ]]
}

@test "AC5: a manifest with candidate_frozen_at set but candidate_sha null is REJECTED too (both directions)" {
  _bootstrap
  local f="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  jq '.plan_boundary_manifest.candidate_frozen_at = "2026-07-25T10:00:00Z"
      | .plan_boundary_manifest.candidate_sha = null' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"

  run plan_manifest_validate "$PLAN_ID"
  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate_sha and candidate_frozen_at must be null/non-null together"* ]]
}

@test "AC5: a non-UTC / malformed candidate_frozen_at is refused by the writer AND by the invariant" {
  _bootstrap
  local head; head="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  # Writer: a local-offset instant is not accepted.
  run plan_manifest_freeze_candidate "$PLAN_ID" "$head" "$head" "R-x-1" \
    ".aid-o/work/evidence/${PLAN_ID}/R-x-1" "2026-07-25T10:00:00+02:00"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RFC 3339 UTC instant"* ]]
  # And nothing was written.
  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]

  # Invariant: the same value planted directly is rejected on validate.
  local f="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  jq --arg h "$head" '.plan_boundary_manifest.candidate_sha = $h
                      | .plan_boundary_manifest.candidate_frozen_at = "2026-07-25"
                      | .plan_boundary_manifest.plan_state = "PLAN_GATES"' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  run plan_manifest_validate "$PLAN_ID"
  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate_frozen_at"* ]]
}

# ─── AC1 (freeze/invalidation): a candidate change after freeze goes to
#          PLAN_FIX and clears ALL FOUR plan-final fields (plus the freeze
#          time, which is cleared with candidate_sha) ────────────────────────
@test "AC1: a candidate change after freeze transitions the plan to PLAN_FIX and clears every plan-final field" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local first_candidate; first_candidate="$(_manifest_field "$PLAN_ID" candidate_sha)"
  [[ "$first_candidate" =~ ^[0-9a-f]{40}$ ]]

  # The candidate CHANGES: the plan branch moves off the frozen commit.
  _commit_on "plan/$PLAN_ID" "late.txt" "a commit after the freeze"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 6 ]
  [[ "$output" == *"CANDIDATE INVALIDATED"* ]]

  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]
  run _manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze
  [ "$output" = "null" ]
  run _manifest_field "$PLAN_ID" plan_final_run_id
  [ "$output" = "null" ]
  run _manifest_field "$PLAN_ID" plan_final_evidence_dir
  [ "$output" = "null" ]
  # Cleared in the SAME write as candidate_sha — never left dangling.
  run _manifest_field "$PLAN_ID" candidate_frozen_at
  [ "$output" = "null" ]
  run _manifest_field "$PLAN_ID" candidate_invalidation_reason
  [ "$output" = "candidate_changed_after_freeze" ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_FIX" ]
}

@test "AC5: an invalidation clears candidate_sha and candidate_frozen_at TOGETHER — never one without the other" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  # Walk to AWAITING_PM — the state the stale-authorization resync is
  # discovered from, and the one PLAN_SYNC is legally reachable from.
  plan_state_transition "$PLAN_ID" "PLAN_GATES" "PLAN_REVIEW"
  plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "AWAITING_PM"

  # plan_final_invalidate lives in the CLI script, so it is sourced into a
  # subshell rather than into this bats process (the CLI sets `set -uo
  # pipefail`, which must not leak into the rest of the suite). Sourcing is
  # safe: the script only runs main() when executed directly.
  run bash -c 'source "$1"; plan_final_invalidate "$2" "$3" "$4"' \
    _ "$PLAN_FSM_CLI" "$PLAN_ID" "stale_pm_authorization" "PLAN_SYNC"
  [ "$status" -eq 0 ]

  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]
  run _manifest_field "$PLAN_ID" candidate_frozen_at
  [ "$output" = "null" ]
  # The target state is a PARAMETER: the same clearing serves the resync path.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]
  run _manifest_field "$PLAN_ID" candidate_invalidation_reason
  [ "$output" = "stale_pm_authorization" ]

  # And the manifest is still fully valid after the clear.
  run plan_manifest_validate "$PLAN_ID"
  [ "$status" -eq 0 ]
}

@test "plan_final_invalidate refuses an illegal target state and clears NOTHING" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local sha1; sha1="$(_manifest_field "$PLAN_ID" candidate_sha)"

  # PLAN_GATES → PLAN_SYNC is not a legal edge. Refusing (rather than writing
  # the manifest and silently failing the state transition) is what keeps the
  # two records of the same fact from diverging.
  run bash -c 'source "$1"; plan_final_invalidate "$2" "$3" "$4"' \
    _ "$PLAN_FSM_CLI" "$PLAN_ID" "wrong_target" "PLAN_SYNC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a legal plan-state transition"* ]]

  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$sha1" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

@test "a refreeze rewrites candidate_sha and candidate_frozen_at TOGETHER (both change, neither is stale)" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze --frozen-at "2026-07-25T10:00:00Z"
  [ "$status" -eq 0 ]
  local sha1 at1
  sha1="$(_manifest_field "$PLAN_ID" candidate_sha)"
  at1="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  [ "$at1" = "2026-07-25T10:00:00Z" ]

  _commit_on "plan/$PLAN_ID" "late.txt" "moves the candidate"
  _finalize "$PLAN_ID" freeze                   # invalidates → PLAN_FIX
  [ "$status" -eq 6 ]
  run plan_state_transition "$PLAN_ID" "PLAN_FIX" "PLAN_SYNC"
  [ "$status" -eq 0 ]
  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  _finalize "$PLAN_ID" freeze --frozen-at "2026-07-25T11:00:00Z"
  [ "$status" -eq 0 ]

  local sha2 at2
  sha2="$(_manifest_field "$PLAN_ID" candidate_sha)"
  at2="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  [ "$sha2" != "$sha1" ]
  [ "$at2" != "$at1" ]
  [ "$at2" = "2026-07-25T11:00:00Z" ]
}

# ─── AC7: a second freeze creates R-<plan_id>-final-2 and leaves final-1
#          byte-identical ──────────────────────────────────────────────────
@test "AC7: a second freeze allocates R-<plan_id>-final-2 and leaves R-<plan_id>-final-1 byte-identical" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  local ev="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}"
  [ -d "$ev/R-${PLAN_ID}-final-1" ]
  printf 'attempt one evidence\n' > "$ev/R-${PLAN_ID}-final-1/report.txt"
  local before; before="$(sha256sum "$ev/R-${PLAN_ID}-final-1/report.txt" | awk '{print $1}')"

  _commit_on "plan/$PLAN_ID" "fix.txt" "the review fix"
  _finalize "$PLAN_ID" freeze                   # invalidate → PLAN_FIX
  [ "$status" -eq 6 ]
  plan_state_transition "$PLAN_ID" "PLAN_FIX" "PLAN_SYNC"
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  [ -d "$ev/R-${PLAN_ID}-final-2" ]
  run _manifest_field "$PLAN_ID" plan_final_run_id
  [ "$output" = "R-${PLAN_ID}-final-2" ]

  # Attempt 1 is untouched — never deleted, never overwritten.
  [ -f "$ev/R-${PLAN_ID}-final-1/report.txt" ]
  local after; after="$(sha256sum "$ev/R-${PLAN_ID}-final-1/report.txt" | awk '{print $1}')"
  [ "$after" = "$before" ]
}

# ─── AC8: target-branch advance between sync and freeze returns the plan to
#          PLAN_SYNC instead of freezing ─────────────────────────────────────
@test "AC8: a target-branch advance between sync and freeze returns the plan to PLAN_SYNC and freezes nothing" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]

  # The hotfix lands on the target branch AFTER the sync merge.
  _commit_on "main" "hotfix.txt" "an urgent hotfix"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 1 ]
  [[ "$output" == *"target_drift_during_freeze"* ]]

  # Nothing frozen — recording the newer head and freezing anyway would bind a
  # candidate that does NOT contain the hotfix to a target head that DOES.
  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]
  run _manifest_field "$PLAN_ID" candidate_frozen_at
  [ "$output" = "null" ]
  [ ! -d "$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}/R-${PLAN_ID}-final-1" ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]

  # And the documented loop closes: sync again, then the freeze succeeds and
  # the candidate DOES contain the hotfix.
  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" "$cand"
  [ "$status" -eq 0 ]
}

@test "--stage freeze refuses a dirty worktree, so a half-applied prepare-plan can never be frozen over" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]

  # Simulate prepare-plan having written one version file and then failed.
  printf 'half-written\n' > "$TEST_PROJECT_ROOT/.gitkeep"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes present"* ]]
  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]
}

@test "--stage freeze refuses out of a state that is not PLAN_SYNC" {
  _bootstrap
  # Still OPEN — sync has not run.
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 1 ]
  [[ "$output" == *"freeze runs only out of PLAN_SYNC"* ]]
  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]
}

@test "--stage freeze re-run at the SAME plan head is an idempotent no-op — no second candidate, no second run dir" {
  _bootstrap
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local sha1 at1
  sha1="$(_manifest_field "$PLAN_ID" candidate_sha)"
  at1="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$sha1" ]
  [ "$(_manifest_field "$PLAN_ID" candidate_frozen_at)" = "$at1" ]
  [ ! -d "$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}/R-${PLAN_ID}-final-2" ]
}

# =============================================================================
# ─── aid-release.sh prepare-plan ─────────────────────────────────────────
# =============================================================================

# _seed_version_project — a minimal but REAL version registry: a CHANGELOG,
# a plugin.json and .aid-o/config/project.yaml `versioning.files[]`, all
# committed on the plan branch.
_seed_version_project() {
  local plan_id="${1:-$PLAN_ID}"
  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${plan_id}"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" "$TEST_PROJECT_ROOT/pkg"
  cat > "$TEST_PROJECT_ROOT/CHANGELOG.md" <<'MD'
# Changelog

All notable changes.

## [1.2.3] — 2026-07-01

### Added

- Something.
MD
  printf '{\n  "version": "1.2.3"\n}\n' > "$TEST_PROJECT_ROOT/pkg/plugin.json"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml" <<'YML'
versioning:
  files:
    - path: pkg/plugin.json
      type: json
      field: version
    - path: CHANGELOG.md
      type: changelog
YML
  printf 'untouched\n' > "$TEST_PROJECT_ROOT/unrelated.txt"
  # Explicit paths, never `git add -A`: `.aid-o/work/` is the gitignored
  # runtime area in production, and committing it here would delete the plan
  # state and the manifest from the worktree on the next `git checkout main`.
  git -C "$TEST_PROJECT_ROOT" add -- CHANGELOG.md pkg/plugin.json \
    .aid-o/config/project.yaml unrelated.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "seed version registry"
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

# _prepare <plan_id> [extra...] — run prepare-plan ON the plan branch.
_prepare() {
  local plan_id="$1"; shift
  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${plan_id}"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE_CLI" prepare-plan "$plan_id" --bump patch \
    --plan-branch "plan/${plan_id}" --project-root "$TEST_PROJECT_ROOT" "$@"
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig" || true
}

# ─── AC6: tag-once — prepare-plan commits the version edits and creates NO
#          tag; tagging happens once, later, at merge time ──────────────────
@test "AC6: prepare-plan commits the version edits on the plan branch and creates NO tag" {
  _bootstrap
  _seed_version_project

  local tags_before; tags_before="$(git -C "$TEST_PROJECT_ROOT" tag | wc -l)"
  _prepare "$PLAN_ID"
  [ "$status" -eq 0 ]

  # The commit exists on the plan branch, with the contracted message.
  run git -C "$TEST_PROJECT_ROOT" log -1 --format=%s "plan/$PLAN_ID"
  [ "$output" = "release: prepare v1.2.4 for ${PLAN_ID}" ]

  # No tag was created — this is the tag-once guarantee.
  local tags_after; tags_after="$(git -C "$TEST_PROJECT_ROOT" tag | wc -l)"
  [ "$tags_after" -eq "$tags_before" ]
  run git -C "$TEST_PROJECT_ROOT" rev-parse -q --verify "refs/tags/v1.2.4"
  [ "$status" -ne 0 ]

  # And the version files really moved.
  run git -C "$TEST_PROJECT_ROOT" show "plan/${PLAN_ID}:pkg/plugin.json"
  [[ "$output" == *"1.2.4"* ]]
}

@test "AC6: prepare-plan stages ONLY the version files — an unrelated modification is refused, never swept in" {
  _bootstrap
  _seed_version_project

  # Dirt in the worktree that the legacy path's `git add -u` would have
  # folded into the release commit.
  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  printf 'accidental edit\n' > "$TEST_PROJECT_ROOT/unrelated.txt"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE_CLI" prepare-plan "$PLAN_ID" --bump patch \
    --plan-branch "plan/$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refuses to run with modified tracked files"* ]]
  [[ "$output" == *"unrelated.txt"* ]]

  # No commit was made.
  run git -C "$TEST_PROJECT_ROOT" log -1 --format=%s
  [ "$output" = "seed version registry" ]
  git -C "$TEST_PROJECT_ROOT" checkout -q -- unrelated.txt
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

@test "AC6: prepare-plan is idempotent under crash-resume — a second run reuses the existing commit and does not bump again" {
  _bootstrap
  _seed_version_project

  _prepare "$PLAN_ID"
  [ "$status" -eq 0 ]
  local head1; head1="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  _prepare "$PLAN_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already prepared"* ]]
  local head2; head2="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  [ "$head2" = "$head1" ]

  # Still 1.2.4 — a naive re-run would have produced 1.2.5.
  run git -C "$TEST_PROJECT_ROOT" show "plan/${PLAN_ID}:pkg/plugin.json"
  [[ "$output" == *"1.2.4"* ]]
  [[ "$output" != *"1.2.5"* ]]
}

@test "prepare-plan refuses to run anywhere but on the named plan branch (it never moves HEAD for you)" {
  _bootstrap
  _seed_version_project
  cd "$TEST_PROJECT_ROOT"   # still on main
  run bash "$RELEASE_CLI" prepare-plan "$PLAN_ID" --bump patch \
    --plan-branch "plan/$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must run on plan/${PLAN_ID}"* ]]
}

# ─── Edge case: the bump resolves to "no bump" ────────────────────────────
@test "prepare-plan with --bump auto and only chore/docs commits makes NO commit and exits 0" {
  _bootstrap
  _seed_version_project

  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  git -C "$TEST_PROJECT_ROOT" tag -a "v1.2.3" -m "Release v1.2.3"
  printf 'docs\n' > "$TEST_PROJECT_ROOT/docs.txt"
  git -C "$TEST_PROJECT_ROOT" add docs.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: a documentation-only change"
  local head_before; head_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"

  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE_CLI" prepare-plan "$PLAN_ID" --bump auto \
    --plan-branch "plan/$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no version bump needed"* ]]

  # No commit — the candidate is simply the current plan head.
  local head_after; head_after="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  [ "$head_after" = "$head_before" ]
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

# ─── Regression: the LEGACY entry point is unchanged by the restructure ────
@test "regression: the legacy aid-release.sh <bump> entry point still works exactly as before" {
  _bootstrap
  _seed_version_project
  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  cd "$TEST_PROJECT_ROOT"

  # --dry-run: reports the bump, writes nothing.
  run bash "$RELEASE_CLI" patch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bumping: 1.2.3 → 1.2.4 (patch)"* ]]
  [[ "$output" == *"[DRY RUN]"* ]]
  run git -C "$TEST_PROJECT_ROOT" status --porcelain
  [ -z "$output" ]

  # A bad bump type is still rejected with the original message.
  run bash "$RELEASE_CLI" nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"bump type must be auto|patch|minor|major"* ]]

  # The real legacy run still commits AND tags (unlike prepare-plan).
  run bash "$RELEASE_CLI" patch
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" rev-parse -q --verify "refs/tags/v1.2.4"
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" log -1 --format=%s
  [[ "$output" == "release: v1.2.4"* ]]

  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

# =============================================================================
# ─── the full Step 1 order: sync → prepare-plan → freeze ─────────────────
# =============================================================================

@test "the frozen candidate CONTAINS the version commit — sync, then prepare, then freeze" {
  _bootstrap
  _seed_version_project

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]

  # prepare-plan runs while the state is STILL PLAN_SYNC — it never needs a
  # candidate_sha that does not exist yet.
  _prepare "$PLAN_ID"
  [ "$status" -eq 0 ]
  local prepare_commit; prepare_commit="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  # The candidate IS the prepare commit: the release metadata is already
  # inside the thing that will be reviewed, so nothing must be committed once
  # the reviews start.
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  [ "$cand" = "$prepare_commit" ]
  run git -C "$TEST_PROJECT_ROOT" show "${cand}:pkg/plugin.json"
  [[ "$output" == *"1.2.4"* ]]
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-finalize --stage gates (Step 2) ────────────────
# =============================================================================
#
# AC2 — exactly ONE plan-final gate profile run against the frozen candidate,
# with a gates_report.json that PROVES no required gate was excluded, no broad
# suite ran twice, plan_diff really evaluated the plan, and no quarantined gate
# came back green.
#
# The fixture execution.yaml below is deliberately a MINIATURE of the real one
# (a required gate, a quarantined required gate, a non-quarantined
# `shell_pipeline_smoke`, `plan_diff` with the exit-2 Fast Mode convention, and
# `docs_updated`) — same shapes, sub-second commands. The gate ids that the
# stage treats specially (`plan_diff`, `shell_pipeline_smoke`) keep their real
# names; everything else is generic on purpose, so the test proves the
# MECHANISM rather than one hard-coded gate list.

# _write_exec_yaml [substitute_include_override]
#   Writes .aid-o/config/execution.yaml into the test project. When the first
#   argument is given it REPLACES the release_quarantine include[] block, so a
#   test can prove that a substitute which drops a non-quarantined release gate
#   is refused.
_write_exec_yaml() {
  local sub_include="${1:-}"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" <<'YAML'
version: '1.0'
gates:
  bats_fsm:
    command: "true"
    required: true
    timeout_seconds: 30
    max_retries: 0
  bats_all:
    quarantine:
      enabled: true
      authorized_by: "PM test"
      tracked_by: "P066"
      original_command: "bats tests/"
    command: "echo QUARANTINED >&2; exit 86"
    required: true
    timeout_seconds: 10
    max_retries: 0
  shell_pipeline_smoke:
    command: "true"
    required: false
    timeout_seconds: 30
    max_retries: 0
  plan_diff:
    command: "echo '{plan_path}' '{base_commit}' > .aid-o/work/plan_diff_args.txt; test '{plan_path}' != 'null' && test -f '{plan_path}' && git rev-parse --verify --quiet {base_commit} >/dev/null || exit 2"
    required: false
    pass_criteria: "exit 0 (all present) or exit 2 (Fast Mode graceful skip)"
    timeout_seconds: 30
    max_retries: 0
  docs_updated:
    command: "true"
    required: false
    timeout_seconds: 30
    max_retries: 0
gate_profiles:
  release:
    include:
      - bats_fsm
      - bats_all
      - shell_pipeline_smoke
      - plan_diff
      - docs_updated
  release_quarantine:
    include:
      - bats_fsm
      - shell_pipeline_smoke
      - plan_diff
      - docs_updated
YAML
  if [[ -n "$sub_include" ]]; then
    # Replace everything from the release_quarantine include marker onward.
    local f="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
    local keep; keep="$(awk '/^  release_quarantine:/{exit} {print}' "$f")"
    { printf '%s\n' "$keep"; printf '  release_quarantine:\n    include:\n'; printf '%s' "$sub_include"; } > "$f"
  fi
}

# _seed_gates_project — a plan branch whose candidate carries the plan file the
# gates evaluate, plus a gitignored runtime area.
_seed_gates_project() {
  _bootstrap
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '# %s\n\n## Acceptance Criteria\n- [ ] something\n' "$PLAN_ID" \
    > "$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-test-plan.md"
  git -C "$TEST_PROJECT_ROOT" add -- ".aid-o/plans/${PLAN_ID}-test-plan.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "the plan file"
  git -C "$TEST_PROJECT_ROOT" branch -f "plan/${PLAN_ID}" main
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
}

# _run_dir — the frozen candidate's plan-final evidence directory (absolute).
_run_dir() {
  printf '%s/%s' "$TEST_PROJECT_ROOT" "$(_manifest_field "$PLAN_ID" plan_final_evidence_dir)"
}

# _write_receipt <gate_id> [head_override] [exit_code] [failed]
#   A valid IMP-269-shaped targeted-run receipt (command_sha256 == sha256(cmd),
#   log_sha256 == sha256 of a real in-repo log) bound to the frozen candidate.
#   Echoes the receipt path.
_write_receipt() {
  local gate="$1" head="${2:-}" ec="${3:-0}" failed="${4:-0}"
  local dir; dir="$(_run_dir)/gates"
  mkdir -p "$dir"
  [[ -z "$head" ]] && head="$(_manifest_field "$PLAN_ID" candidate_sha)"
  local cmd="bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  printf 'ok 1 targeted substitute\n' > "$dir/${gate}-substitute.log"
  local csha lsha
  csha="$(printf '%s' "$cmd" | sha256sum | cut -d' ' -f1)"
  lsha="$(sha256sum "$dir/${gate}-substitute.log" | awk '{print $1}')"
  jq -nc --arg g "$gate" --arg c "$cmd" --arg cs "$csha" --arg h "$head" \
         --arg l "${gate}-substitute.log" --arg ls "$lsha" \
         --argjson ec "$ec" --argjson failed "$failed" \
    '{gate_id:$g, command:$c, command_sha256:$cs, head_sha:$h, log:$l,
      log_sha256:$ls, exit_code:$ec, passed:1, failed:$failed}' \
    > "$dir/${gate}-substitute.receipt.json"
  printf '%s' "$dir/${gate}-substitute.receipt.json"
}

# _gates [extra args...] — the stage under test.
_gates() {
  run bash "$PLAN_FSM_CLI" plan-finalize "$PLAN_ID" --stage gates \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# _report — the plan-final gates_report.json path.
_report() { printf '%s/gates_report.json' "$(_run_dir)"; }

# ─── AC2.1 + AC2.5: the resolved release-derived profile, head_sha ==
#     candidate, and NO non-quarantined release gate dropped ────────────────
@test "AC2: the plan-final report carries the release-derived profile, the candidate head, and every non-quarantined release gate" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  run jq -r '.profile' "$(_report)"
  [ "$output" = "release_quarantine" ]
  run jq -r '.revision.head_sha' "$(_report)"
  [ "$output" = "$cand" ]
  run jq -r '.overall' "$(_report)"
  [ "$output" = "pass" ]

  # Every non-quarantined release gate has a REAL result — notably
  # shell_pipeline_smoke, which the EPIC-scoped bats_all_quarantine profile omits.
  local g
  for g in bats_fsm shell_pipeline_smoke plan_diff docs_updated; do
    run jq -r --arg g "$g" '.gates[$g].result' "$(_report)"
    [ "$output" = "pass" ]
  done

  # ...and the stage transitioned PLAN_GATES -> PLAN_REVIEW.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_REVIEW" ]
}

# ─── AC2.7: plan_diff runs FOR REAL — not `--plan null`, not the exit-2 skip ─
@test "AC2: plan_diff evaluates the real plan file and the candidate range (never the Fast Mode exit-2 skip)" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  # `pass`, not `skip`: a skip is what an exit-2 `--plan null` would produce.
  run jq -r '.gates.plan_diff.result' "$(_report)"
  [ "$output" = "pass" ]
  run jq -r '.gates.plan_diff.exit_code' "$(_report)"
  [ "$output" = "0" ]
  # The gate SAW the real plan file and the real base commit — recorded by the
  # gate command itself, i.e. AFTER token substitution (the report's
  # _command_log keeps the raw, pre-substitution command by design).
  local base; base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  run cat "$TEST_PROJECT_ROOT/.aid-o/work/plan_diff_args.txt"
  [[ "$output" == *"${PLAN_ID}-test-plan.md"* ]]
  [[ "$output" == *"$base"* ]]
  [[ "$output" != *"null"* ]]
}

# ─── AC2.7 (negative): without the new flags the SAME gate is vacuous ───────
# This is the finding the C0 cross-provider review made, pinned as a test: with
# no --base-commit/--plan-path and no --state-file, plan_diff resolves to
# `--plan null`, exits 2, and execution.yaml's pass_criteria ACCEPTS it. The
# stage must never be able to reach that state.
@test "AC2: a plan-final gate run WITHOUT --plan-path degrades plan_diff to the accepted exit-2 skip (the vacuity the flags close)" {
  _seed_gates_project
  _write_exec_yaml
  local rd; rd="$(_run_dir)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
  run bash -c "cd '$TEST_PROJECT_ROOT' && '$AID_PLUGIN_PATH/scripts/aid-run-gates.sh' run-all \
      '$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml' '$PLAN_ID' 'R-vacuous' \
      '$rd/vacuous-timeline.jsonl' --report-file '$rd/vacuous.json' \
      --profile release_quarantine"
  run jq -r '.gates.plan_diff.result' "$rd/vacuous.json"
  [ "$output" = "skip" ]
  run jq -r '.gates.plan_diff.exit_code' "$rd/vacuous.json"
  [ "$output" = "2" ]
  # The gate literally received the string "null" as its plan.
  run cat "$TEST_PROJECT_ROOT/.aid-o/work/plan_diff_args.txt"
  [[ "$output" == "null "* ]]
}

# ─── AC2.9: existing EPIC-scoped callers are unaffected when the flags are
#     absent — the state file still supplies both tokens ────────────────────
@test "AC2: --base-commit/--plan-path are additive — omitted, the runner still reads the state file" {
  _seed_gates_project
  _write_exec_yaml
  local rd; rd="$(_run_dir)"
  local base; base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  local plan="$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-test-plan.md"
  cat > "$rd/fsm-state.yaml" <<EOF
state: GATES
base_commit: $base
plan_path: $plan
EOF
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
  run bash -c "cd '$TEST_PROJECT_ROOT' && '$AID_PLUGIN_PATH/scripts/aid-run-gates.sh' run-all \
      '$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml' '$PLAN_ID' 'R-legacy' \
      '$rd/legacy-timeline.jsonl' --state-file '$rd/fsm-state.yaml' \
      --report-file '$rd/legacy.json' --profile release_quarantine"
  run jq -r '.gates.plan_diff.result' "$rd/legacy.json"
  [ "$output" = "pass" ]
  run cat "$TEST_PROJECT_ROOT/.aid-o/work/plan_diff_args.txt"
  [[ "$output" == *"${PLAN_ID}-test-plan.md"* ]]
  [[ "$output" == *"$base"* ]]
}

# ─── AC2.3 + AC2.4: the quarantined gate is never green, and is satisfied
#     ONLY by a matching, candidate-bound, genuinely-green substitute ───────
@test "AC2: the quarantined gate is excluded, never 'pass', and carries a bound quarantine_substitutes[] entry" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  local cand base
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"

  run jq -r '.gates.bats_all.result // "profile_excluded"' "$(_report)"
  [ "$output" != "pass" ]
  run jq -r '.excluded_gates | index("bats_all") != null' "$(_report)"
  [ "$output" = "true" ]

  run jq -r '.quarantine_substitutes | length' "$(_report)"
  [ "$output" = "1" ]
  run jq -r '.quarantine_substitutes[0].gate_id' "$(_report)"
  [ "$output" = "bats_all" ]
  run jq -r '.quarantine_substitutes[0].targeted_substitute' "$(_report)"
  [ "$output" = "accepted" ]
  run jq -r '.quarantine_substitutes[0].head_sha' "$(_report)"
  [ "$output" = "$cand" ]
  run jq -r '.quarantine_substitutes[0].base_sha' "$(_report)"
  [ "$output" = "$base" ]
  run jq -e '.quarantine_substitutes[0]
             | (.receipt_sha256 | test("^sha256:[0-9a-f]{64}$"))
               and (.command_sha256 | test("^sha256:[0-9a-f]{64}$"))
               and (.receipt_path | length > 0)
               and (.substitute_scope | length > 0)
               and .exit_code == 0 and .failed == 0' "$(_report)"
  [ "$status" -eq 0 ]

  # receipt_sha256 is the SEALED hash of the receipt file itself.
  local actual; actual="$(sha256sum "$receipt" | awk '{print $1}')"
  run jq -r '.quarantine_substitutes[0].receipt_sha256' "$(_report)"
  [ "$output" = "sha256:${actual}" ]
}

# ─── AC2.4 (negative): no receipt at all — a quarantined gate is NOT satisfied
#     by simply being excluded, and a waiver alone would not help either ────
@test "AC2: a quarantined gate with NO substitute receipt fails the stage and leaves the plan in PLAN_GATES" {
  _seed_gates_project
  _write_exec_yaml

  _gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"no targeted-substitute receipt was supplied"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC2.4 (negative): a receipt for a DIFFERENT gate never satisfies this one ─
@test "AC2: a substitute receipt whose gate_id does not match is rejected (one receipt cannot satisfy another gate)" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_fsm)"   # wrong gate_id inside

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"one receipt can never satisfy a different gate"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC2.4 (negative): head_sha != candidate_sha is rejected ────────────────
@test "AC2: a substitute receipt bound to any head other than the frozen candidate is rejected" {
  _seed_gates_project
  _write_exec_yaml
  local other; other="$(git -C "$TEST_PROJECT_ROOT" rev-parse main~1)"
  local receipt; receipt="$(_write_receipt bats_all "$other")"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not bound to the frozen candidate"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC2.4 (negative): a RED substitute never stands in for a broad gate ────
@test "AC2: a substitute receipt with a non-zero exit_code or failed>0 is rejected" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all "" 1 2)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a passing run"* ]]
}

# ─── AC2.4 (negative): a tampered receipt (command_sha256 no longer of
#     .command) is rejected — the fingerprint is not decorative ─────────────
@test "AC2: a substitute receipt whose command_sha256 is not sha256(.command) is rejected" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"
  jq '.command = "echo something else entirely"' "$receipt" > "${receipt}.t" && mv "${receipt}.t" "$receipt"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"command_sha256 is not sha256(.command)"* ]]
}

# ─── AC2.5: the substitute profile MUST be release-derived — a profile that
#     drops a non-quarantined release gate is refused BEFORE any gate runs ──
@test "AC2: a substitute profile that drops a non-quarantined release gate (shell_pipeline_smoke) is refused" {
  _seed_gates_project
  # Exactly the bats_all_quarantine shape: release minus bats_all AND minus
  # shell_pipeline_smoke. Correct-looking, silently one gate short.
  _write_exec_yaml "$(printf '      - bats_fsm\n      - plan_diff\n      - docs_updated\n')"
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not 'release' minus the quarantined gate"* ]]
  [[ "$output" == *"shell_pipeline_smoke"* ]]
  # Nothing ran: no report was written.
  [ ! -f "$(_report)" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC2.6: EXACTLY ONE gate_runner_start — no second broad run ────────────
@test "AC2: exactly one gate_runner_start event exists for the plan-final run" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  run grep -c '"event":"gate_runner_start"' "$(_run_dir)/timeline.jsonl"
  [ "$output" = "1" ]

  # A resume re-reads the passing report and completes ONLY the transition —
  # it never mints a second broad run.
  plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "PLAN_GATES" >/dev/null 2>&1 || \
    plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "PLAN_FIX" >/dev/null 2>&1
  _gates --substitute-receipt "bats_all=${receipt}"
  run grep -c '"event":"gate_runner_start"' "$(_run_dir)/timeline.jsonl"
  [ "$output" = "1" ]
}

# ─── AC2.8: a required gate reporting `skip` fails the stage ───────────────
@test "AC2: a result:skip on a required gate fails the stage rather than counting as satisfied" {
  _seed_gates_project
  _write_exec_yaml
  # bats_fsm is required:true; give it a null command so the runner records an
  # explicit skip row (no_command) rather than a pass.
  yq -i '.gates.bats_fsm.command = null' "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"never satisfied by a skip"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── the candidate binding: the stage refuses a head that is not the
#     frozen candidate, and refuses to run at all before the freeze ─────────
@test "AC2: --stage gates refuses when the plan branch has moved off the frozen candidate" {
  _seed_gates_project
  _write_exec_yaml
  _commit_on "plan/${PLAN_ID}" drift.txt "drift"

  _gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not the candidate"* ]]
  [ ! -f "$(_report)" ]
}

@test "AC2: --stage gates refuses out of any state other than PLAN_GATES" {
  _bootstrap
  _write_exec_yaml

  _gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"no frozen candidate"* ]]
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-finalize --stage review (Step 3) ───────────────
# =============================================================================
#
# AC3 — the plan-level review boundary. The FSM dispatches nothing; it declares
# the required outputs, blocks on exit 7 until they exist, refuses a stale /
# wrong-plan / wrong-candidate output with exit 1, and invalidates the candidate
# with exit 6 when a tracked write proves a fix was accepted.
#
# The fixtures below build REAL protocol-v2 artifacts (the same envelope
# aid-protocol-validate.sh enforces) rather than stubs, so a change to the
# validator's contract breaks these tests instead of silently passing them.

# _seed_review_project — a plan with ONE merged EPIC, gated green, in
# PLAN_REVIEW at a frozen candidate.
_seed_review_project() {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  local mc; mc="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "merged_to_plan" "$mc"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '# %s\n\n## Acceptance Criteria\n- [ ] something\n' "$PLAN_ID" \
    > "$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-test-plan.md"
  git -C "$TEST_PROJECT_ROOT" add -- ".aid-o/plans/${PLAN_ID}-test-plan.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "the plan file"
  git -C "$TEST_PROJECT_ROOT" branch -f "plan/${PLAN_ID}" main
  _write_exec_yaml
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  local receipt; receipt="$(_write_receipt bats_all)"
  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]
}

# _review [extra args...] — the stage under test.
_review() {
  # CP2 F1: the review boundary requires the worktree to BE the candidate — the
  # stage's drift detection is baselined on it and the plan-level specialists
  # review it. That is the CONTROLLER's job (it dispatches between the exit-7 and
  # the validating invocation), so this helper does what the controller must do.
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}" 2>/dev/null || true
  run bash "$PLAN_FSM_CLI" plan-finalize "$PLAN_ID" --stage review \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# _p2 <filename> <artifact_type> <payload_key> [jq_override]
#   One protocol-v2 artifact in the plan-final run directory, bound to the
#   frozen candidate and to this plan. `jq_override` is applied last, so a test
#   can corrupt exactly one binding and leave the rest valid.
_p2() {
  local fname="$1" atype="$2" pkey="$3" override="${4:-.}"
  local dir; dir="$(_run_dir)"
  mkdir -p "$dir"
  local cand base
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  # CP2 F2: stamp the ACTUAL plan-final run id, never a hard-coded -final-1 —
  # the stage now binds outputs to the attempt, so a re-frozen candidate in
  # R-<plan>-final-2 must carry that run id.
  local rid; rid="$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  local sh; sh="$(printf '%s' "$fname" | sha256sum | cut -d' ' -f1)"
  jq -n --arg t "$atype" --arg pk "$pkey" --arg h "$cand" --arg b "$base" \
        --arg plan "$PLAN_ID" --arg sh "sha256:${sh}" --arg rid "$rid" \
    '{schema_version:"aid-2.0", artifact_type:$t, producer:"aid-test@2.0",
      created_at:"2026-07-25T00:00:00Z", control_protocol:"aid-2.0",
      identity:{project_id:"aid-orchestrator", epic_id:null, plan_id:$plan,
                run_id:$rid},
      subject:{subject_hash:$sh},
      revision:{head_sha:$h, base_sha:$b, head_is_current:true, freshness:"current"},
      status:"pass", verdict:{kind:"none"},
      provenance:{dispatch_mode:"subagent", generated_by_tool:"aid-test"}}
     | .[$pk] = {}' \
    | jq "$override" > "${dir}/${fname}"
}

# _write_review_outputs — every required output, valid and correctly ordered
# (the Reporter's delivery-report.json written LAST).
_write_review_outputs() {
  local dir; dir="$(_run_dir)"
  local cand base
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"

  _p2 semantic-review-final.json semantic_review semantic_review \
    ".semantic_review.range = \"${base}..${cand}\""
  _p2 audit-report.json audit_report audit_report \
    ".audit_report.reviewed_head = \"${cand}\" | .audit_report.input_manifest_hash = \"sha256:deadbeef\" | .audit_report.blocking_findings = false | .audit_report.provider = \"test-provider\" | .audit_report.model = \"test-model\" | .audit_report.process_id = \"plan-final-audit\" | .audit_report.required_independence_level = \"context_only\" | .audit_report.independence_level = \"context_only\" | .audit_report.advisory = false"
  local ahash; ahash="$(sha256sum "${dir}/audit-report.json" | awk '{print $1}')"
  _p2 curator-report.json curator curator \
    ".curator.audit_report_ref = \"sha256:${ahash}\""
  printf '# Simplifier report\n\nHead: %s\n\nNo proposals.\n' "$cand" > "${dir}/simplifier-report.md"
  _p2 review-profile.json review_profile review_profile \
    '.review_profile.required_lenses = ["correctness"]'
  _p2 delivery-gate.json delivery_gate delivery_gate \
    '.sources = ["E-068-1_2"]'
  _p2 acceptance-evidence.json acceptance_evidence acceptance_evidence \
    '.sources = ["E-068-1_2"]'
  local drid; drid="$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  jq -n --arg c "$cand" --arg r "$drid" \
    '{candidate_sha:$c, run_id:$r,
      dispatches:[{agent:"auditor",count:1},{agent:"curator",count:1},
                  {agent:"simplifier",count:1},{agent:"reporter",count:1}],
      utilities:[{id:"scanner_memory_scan",count:1}]}' > "${dir}/dispatch-record.json"
  # The Reporter is dispatched LAST, after the final non-mutating pass.
  sleep 1
  _p2 delivery-report.json delivery_report delivery_report
}

# ─── AC3.3: the FSM dispatches nothing — it BLOCKS with exit 7 and names
#     exactly what the controller must produce ─────────────────────────────
@test "AC3: --stage review blocks with exit 7 and writes review-requirements.json naming every required output" {
  _seed_review_project

  _review
  [ "$status" -eq 7 ]
  [[ "$output" == *"awaiting_review_outputs"* ]]
  [[ "$output" == *"semantic-review-final.json"* ]]
  [[ "$output" == *"audit-report.json"* ]]
  [[ "$output" == *"curator-report.json"* ]]
  [[ "$output" == *"simplifier-report.md"* ]]
  [[ "$output" == *"delivery-report.json"* ]]
  [[ "$output" == *"review-profile.json"* ]]
  [[ "$output" == *"delivery-gate.json"* ]]
  [[ "$output" == *"acceptance-evidence.json"* ]]

  # The contract is on disk and carries the PLAN range, not an EPIC diff.
  local req="$(_run_dir)/review-requirements.json"
  [ -f "$req" ]
  local cand base
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  run jq -r '.review_range' "$req"
  [ "$output" = "${base}..${cand}" ]
  run jq -r '.required_outputs | length' "$req"
  [ "$output" = "9" ]

  # Blocked, not failed: the plan is still PLAN_REVIEW.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_REVIEW" ]
}

# ─── AC3.1 + AC3.4 + AC3.5: a full, valid review pass ─────────────────────
@test "AC3: a complete review pass transitions PLAN_REVIEW -> AWAITING_PM and leaves candidate_sha and the worktree unchanged" {
  _seed_review_project
  local cand_before; cand_before="$(_manifest_field "$PLAN_ID" candidate_sha)"
  local head_before; head_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  _write_review_outputs

  _review
  [ "$status" -eq 0 ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "AWAITING_PM" ]

  # AC3.5: candidate and product worktree untouched by a full review pass.
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$cand_before" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")" = "$head_before" ]
  run git -C "$TEST_PROJECT_ROOT" status --porcelain --untracked-files=no
  [ -z "$output" ]
}

# ─── AC3.1: the C2 final review's recorded range covers the FIRST EPIC's
#     commit even though it is detected only after the LAST one is
#     integrated ─────────────────────────────────────────────────────────
@test "AC3: the recorded C2 range spans plan_base_commit..candidate, so a defect from the first EPIC is still in range after the last EPIC merges" {
  _seed_review_project
  # Two more commits on the plan branch AFTER the seeded one — the analogue of
  # a second and third EPIC landing. The candidate is re-frozen over them.
  _commit_on "plan/${PLAN_ID}" defect.txt "the defect seeded by the first EPIC"
  _commit_on "plan/${PLAN_ID}" later.txt "a later EPIC's change"
  _finalize "$PLAN_ID" freeze   # invalidates: the candidate moved
  [ "$status" -eq 6 ]
  _finalize "$PLAN_ID" sync
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local receipt; receipt="$(_write_receipt bats_all)"
  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  local base cand
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"

  # The defect commit is INSIDE base..candidate — the range the stage requires
  # the C2 final review to record.
  run git -C "$TEST_PROJECT_ROOT" log --format=%s "${base}..${cand}"
  [[ "$output" == *"the defect seeded by the first EPIC"* ]]

  _write_review_outputs
  _review
  [ "$status" -eq 0 ]

  run jq -r '.plan_boundary_manifest.plan_final_review.review_range' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  [ "$output" = "${base}..${cand}" ]
}

@test "AC3: a C2 final review recording an EPIC-sized range (not plan_base_commit) is refused" {
  _seed_review_project
  _write_review_outputs
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  _p2 semantic-review-final.json semantic_review semantic_review \
    ".revision.base_sha = \"${cand}\" | .semantic_review.range = \"${cand}..${cand}\""

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected plan_base_commit"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_REVIEW" ]
}

# ─── AC3.2: dispatch counts — exactly once each, utilities counted
#     explicitly ─────────────────────────────────────────────────────────
@test "AC3: each plan-boundary specialist must dispatch exactly once — a second Curator dispatch is refused" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  jq '.dispatches |= map(if .agent == "curator" then .count = 2 else . end)' \
    "${dir}/dispatch-record.json" > "${dir}/dr.tmp" && mv "${dir}/dr.tmp" "${dir}/dispatch-record.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 dispatch(es) of 'curator'"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_REVIEW" ]
}

@test "AC3: a missing specialist dispatch (0 for the reporter) is refused" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  jq '.dispatches |= map(select(.agent != "reporter"))' \
    "${dir}/dispatch-record.json" > "${dir}/dr.tmp" && mv "${dir}/dr.tmp" "${dir}/dispatch-record.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"0 dispatch(es) of 'reporter'"* ]]
}

@test "AC3: a registered plan utility that did not run blocks, and a successful pass counts it explicitly in utilities_run[]" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  jq '.utilities = []' "${dir}/dispatch-record.json" > "${dir}/dr.tmp" \
    && mv "${dir}/dr.tmp" "${dir}/dispatch-record.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"scanner_memory_scan"* ]]

  # Restored → the pass records it explicitly.
  jq '.utilities = [{id:"scanner_memory_scan",count:1}]' "${dir}/dispatch-record.json" \
    > "${dir}/dr.tmp" && mv "${dir}/dr.tmp" "${dir}/dispatch-record.json"
  _review
  [ "$status" -eq 0 ]
  run jq -c '.plan_boundary_manifest.plan_final_review.utilities_run' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  [ "$output" = '[{"id":"scanner_memory_scan","count":1}]' ]
  run jq -c '.plan_boundary_manifest.plan_final_review.dispatch_counts' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  [ "$output" = '{"auditor":1,"curator":1,"simplifier":1,"reporter":1}' ]
}

@test "AC3: a utility registered in execution.yaml but never run blocks the stage (registration is config, enforcement is not optional)" {
  _seed_review_project
  _write_review_outputs
  printf '\nplan_final_utilities:\n  - scanner_memory_scan\n  - some_new_utility\n' \
    >> "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"some_new_utility"* ]]
}

# ─── AC3.3: stale / wrong-plan / wrong-candidate outputs ─────────────────
@test "AC3: an output bound to any head other than the frozen candidate is refused, never warned" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  jq '.revision.head_sha = "0000000000000000000000000000000000000000"' \
    "${dir}/audit-report.json" > "${dir}/x.tmp" && mv "${dir}/x.tmp" "${dir}/audit-report.json"
  # keep the curator ref consistent so ONLY the head binding is wrong
  local ah; ah="$(sha256sum "${dir}/audit-report.json" | awk '{print $1}')"
  jq --arg a "sha256:${ah}" '.curator.audit_report_ref = $a' "${dir}/curator-report.json" \
    > "${dir}/x.tmp" && mv "${dir}/x.tmp" "${dir}/curator-report.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected the frozen candidate"* ]]
  [[ "$output" == *"stale evidence"* ]]
}

@test "AC3: an EPIC evidence pack copied in (no identity.plan_id) cannot satisfy a requirement" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  # exactly the shape of a per-EPIC artifact: epic_id set, plan_id absent
  jq 'del(.identity.plan_id) | .identity.epic_id = "E-068-1_2"' \
    "${dir}/delivery-gate.json" > "${dir}/x.tmp" && mv "${dir}/x.tmp" "${dir}/delivery-gate.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"identity.plan_id"* ]]
  [[ "$output" == *"bound to the PLAN"* ]]
}

@test "AC3: an output belonging to ANOTHER plan is refused" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  jq '.identity.plan_id = "P999"' "${dir}/review-profile.json" \
    > "${dir}/x.tmp" && mv "${dir}/x.tmp" "${dir}/review-profile.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"P999"* ]]
  [[ "$output" == *"does not belong to this plan"* ]]
}

@test "AC3: a Curator report referencing a DIFFERENT audit report is refused" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  jq '.curator.audit_report_ref = "sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
    "${dir}/curator-report.json" > "${dir}/x.tmp" && mv "${dir}/x.tmp" "${dir}/curator-report.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"reviewed a DIFFERENT audit report"* ]]
}

@test "AC3: a Simplifier report whose Head: provenance line is not the candidate is refused" {
  _seed_review_project
  _write_review_outputs
  printf '# Simplifier report\n\nHead: 1111111111111111111111111111111111111111\n' \
    > "$(_run_dir)/simplifier-report.md"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"provenance line"* ]]
}

@test "AC3: an output that fails aid-protocol-validate.sh is refused with the validator's exit code echoed" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  jq '.subject.subject_hash = "not-a-hash"' "${dir}/semantic-review-final.json" \
    > "${dir}/x.tmp" && mv "${dir}/x.tmp" "${dir}/semantic-review-final.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"aid-protocol-validate.sh"* ]]
  [[ "$output" == *"validator exit 7"* ]]
}

# ─── AC3.4: the plan-level aggregates C4 consumes ────────────────────────
@test "AC3: the plan-final run carries review-profile, delivery-gate and acceptance-evidence bound to the PLAN (epic_id null, plan_id set)" {
  _seed_review_project
  _write_review_outputs
  _review
  [ "$status" -eq 0 ]

  local dir f; dir="$(_run_dir)"
  for f in review-profile.json delivery-gate.json acceptance-evidence.json; do
    [ -f "${dir}/${f}" ]
    run jq -r '.identity.epic_id' "${dir}/${f}"
    [ "$output" = "null" ]
    run jq -r '.identity.plan_id' "${dir}/${f}"
    [ "$output" = "$PLAN_ID" ]
  done
  # review-profile.json is a satisfiable input for lib/review-profile-check.sh
  # (_c3_gate_active): required_lenses[] is present, so it is not "unverifiable".
  run jq -r '.review_profile.required_lenses | length' "${dir}/review-profile.json"
  [ "$output" = "1" ]
}

@test "AC3: the plan-level delivery-gate validates against the widened delivery-gate schema (identity.epic_id string-or-null)" {
  run jq -e '.properties.identity.properties.epic_id.type | index("null")' \
    "$AID_PLUGIN_PATH/defaults/schemas/delivery-gate.schema.json"
  [ "$status" -eq 0 ]
  run jq -e '.properties.identity.required | index("epic_id")' \
    "$AID_PLUGIN_PATH/defaults/schemas/delivery-gate.schema.json"
  [ "$status" -eq 0 ]
}

@test "AC3: an aggregate missing a contributing EPIC is a blocker that NAMES that EPIC" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  jq '.sources = ["E-999-1_1"]' "${dir}/acceptance-evidence.json" \
    > "${dir}/x.tmp" && mv "${dir}/x.tmp" "${dir}/acceptance-evidence.json"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing a per-EPIC contribution for: E-068-1_2"* ]]
}

# ─── AC3.6: an accepted fix that changes the candidate ───────────────────
@test "AC3: an accepted Curator fix that changes the candidate invalidates the gate report and every review output, and the FULL loop re-runs" {
  _seed_review_project
  _write_review_outputs
  local cand1 run1
  cand1="$(_manifest_field "$PLAN_ID" candidate_sha)"
  run1="$(_manifest_field "$PLAN_ID" plan_final_evidence_dir)"

  # The Curator's fix is ACCEPTED and committed on the plan branch.
  _commit_on "plan/${PLAN_ID}" curator-fix.txt "accepted curator fix"

  _review
  [ "$status" -eq 6 ]
  [[ "$output" == *"CANDIDATE INVALIDATED"* ]]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_FIX" ]
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "null" ]
  [ "$(_manifest_field "$PLAN_ID" candidate_frozen_at)" = "null" ]
  [ "$(_manifest_field "$PLAN_ID" plan_final_evidence_dir)" = "null" ]

  # The prior run directory — gate report AND review outputs — is left
  # byte-identical, but it is no longer authoritative for any candidate.
  [ -f "$TEST_PROJECT_ROOT/${run1}/gates_report.json" ]
  [ -f "$TEST_PROJECT_ROOT/${run1}/delivery-report.json" ]

  # THE FULL LOOP, not just the transition: gates and every review output must
  # re-run against the NEW candidate, in a NEW run directory.
  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local cand2 run2
  cand2="$(_manifest_field "$PLAN_ID" candidate_sha)"
  run2="$(_manifest_field "$PLAN_ID" plan_final_evidence_dir)"
  [ "$cand2" != "$cand1" ]
  [ "$run2" != "$run1" ]

  # The stale outputs did not follow the candidate: the new run blocks on 7.
  _review
  [ "$status" -eq 1 ]           # still PLAN_GATES — gates come before reviews
  [[ "$output" == *"runs only out of PLAN_REVIEW"* ]]

  local receipt; receipt="$(_write_receipt bats_all)"
  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]
  _review
  [ "$status" -eq 7 ]
  [[ "$output" == *"awaiting_review_outputs"* ]]

  _write_review_outputs
  _review
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "AWAITING_PM" ]
}

@test "AC3: an UNCOMMITTED tracked write during the review boundary invalidates the candidate rather than being reported as a dirty tree" {
  _seed_review_project
  _write_review_outputs
  # A utility wrote a tracked file and did not commit it.
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
  printf 'utility touched this\n' >> "$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-test-plan.md"

  _review
  [ "$status" -eq 6 ]
  [[ "$output" == *"uncommitted TRACKED changes"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_FIX" ]
}

@test "AC3: outputs written ONLY into the run directory are not a candidate change — untracked run-dir writes never invalidate" {
  _seed_review_project
  local cand_before; cand_before="$(_manifest_field "$PLAN_ID" candidate_sha)"
  _write_review_outputs

  _review
  [ "$status" -eq 0 ]
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$cand_before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "AWAITING_PM" ]
}

# ─── Edge case: the Reporter must be LAST ────────────────────────────────
@test "AC3: a delivery report older than the Simplifier report is refused — the Reporter re-runs last" {
  _seed_review_project
  _write_review_outputs
  # A Simplifier fix accepted AFTER the Reporter already ran.
  sleep 1
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  printf '# Simplifier report\n\nHead: %s\n\nOne proposal, applied.\n' "$cand" \
    > "$(_run_dir)/simplifier-report.md"

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"Reporter must be dispatched last"* ]]
}

# ─── State machine ───────────────────────────────────────────────────────
@test "AC3: --stage review refuses out of any state other than PLAN_REVIEW" {
  _bootstrap
  _write_exec_yaml

  _review
  [ "$status" -eq 1 ]
  [[ "$output" == *"no frozen candidate"* ]]
}

@test "AC3: a re-run in AWAITING_PM is an idempotent no-op — nothing is re-validated into a second pass" {
  _seed_review_project
  _write_review_outputs
  _review
  [ "$status" -eq 0 ]

  _review
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in AWAITING_PM"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "AWAITING_PM" ]
}

# ── CP2 F2 regression: outputs are bound to the ATTEMPT, not only the candidate ──
# The verifier's concrete attack: a review pass completes in R-<plan>-final-1, a
# stray tracked write triggers invalidation, the operator REVERTS it instead of
# committing a fix, so sync/freeze re-freeze the SAME commit into
# R-<plan>-final-2 — and copying the old directory reproduces every file with
# matching heads, a self-consistent curator ref and preserved mtimes.
@test "CP2 F2: a previous attempt's outputs copied into a new run dir are refused (run_id binding)" {
  _seed_review_project
  _write_review_outputs
  _review
  [ "$status" -eq 0 ]
  local first_dir; first_dir="$(_run_dir)"

  # A stray tracked write, then a REVERT (not a fix): the candidate commit is
  # unchanged, so the re-freeze mints the SAME sha under a new attempt.
  echo "stray" >> "$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-test-plan.md"
  _review
  [ "$status" -eq 6 ]
  git -C "$TEST_PROJECT_ROOT" checkout -- ".aid-o/plans/${PLAN_ID}-test-plan.md"

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local receipt; receipt="$(_write_receipt bats_all)"
  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  local second_dir; second_dir="$(_run_dir)"
  [ "$second_dir" != "$first_dir" ]

  # Carry the whole previous attempt over, mtimes preserved.
  cp -rp "$first_dir"/. "$second_dir"/

  _review
  [ "$status" -ne 0 ]
  [[ "$output" == *"run_id"* ]]
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-finalize --stage c4 / --stage summary ───────────
#     (P068 Step 4 — the plan-mode C4 decision + the plan-level PM summary)
# =============================================================================

# _write_plan_c0 [head_override] — the plan's OWN C0 review at the canonical path
# aid-c0-plan-review.sh writes (.aid-o/work/evidence/<plan_id>/c0-plan-review.json).
# Stamped at plan_base_commit by default: a plan-time artifact is stale by
# construction, so the aggregator's basis for it is ANCESTRY, not equality.
_write_plan_c0() {
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}"
  mkdir -p "$dir"
  local h="${1:-$(_manifest_field "$PLAN_ID" plan_base_commit)}"
  jq -n --arg h "$h" --arg p "$PLAN_ID" \
    '{schema_version:"aid-2.0", artifact_type:"plan_review", producer:"aid-c0-plan-review.sh@1.0",
      created_at:"2026-07-25T00:00:00Z", control_protocol:"aid-2.0",
      identity:{project_id:"aid-orchestrator", plan_id:$p, epic_id:null, run_id:"C0-1", step_id:null},
      subject:{subject_hash:"sha256:c0"},
      revision:{head_sha:$h, head_is_current:true, freshness:"current"},
      status:"pass", verdict:{kind:"none", ready:true},
      provenance:{dispatch_mode:"subagent", generated_by_tool:"aid-c0-plan-review.sh"},
      plan_review:{review_status:"reviewed", blocking_findings:false}}' \
    > "$dir/c0-plan-review.json"
}

# _seed_c4_project — a plan that has passed the FULL review boundary, plus the two
# things C4 reads that the review stage does not produce: the plan's own C0 review
# and the per-EPIC evidence directories the roll-up checks for on disk.
_seed_c4_project() {
  _seed_review_project
  _write_review_outputs
  _review
  [ "$status" -eq 0 ]
  _write_plan_c0
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-068-1_2/R-E-068-1_2-1"
  # The at-HEAD verifier subprocess is stubbed (double-gated seam) — this suite
  # exercises the plan-mode RESOLUTION layer, not aid-evidence-verify.sh itself,
  # which has its own suite and costs ~9s per invocation.
  export AID_TEST_MODE=1
  export AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=pass
}

# _c4 / _summary — the stages under test. The controller keeps the worktree on the
# candidate across the whole review->c4->summary boundary; _review already did the
# checkout, so these do not move HEAD.
_c4()      { run bash "$PLAN_FSM_CLI" plan-finalize "$PLAN_ID" --stage c4      --project-root "$TEST_PROJECT_ROOT" "$@"; }
_summary() { run bash "$PLAN_FSM_CLI" plan-finalize "$PLAN_ID" --stage summary --project-root "$TEST_PROJECT_ROOT" "$@"; }
_decision() { printf '%s/release-decision.json' "$(_run_dir)"; }

# ─── AC4.1: every plan-mode input names the plan, the attempt, the candidate,
#     the target ref and the target head ─────────────────────────────────────
@test "AC4: the plan-mode C4 decision names plan id, run id, candidate SHA, target ref and target head SHA" {
  _seed_c4_project
  local cand thead run
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  thead="$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)"
  run="$(_manifest_field "$PLAN_ID" plan_final_run_id)"

  _c4
  [ "$status" -eq 0 ]

  local d; d="$(_decision)"
  [ -f "$d" ]
  # identity: the PLAN, this attempt, and epic_id explicitly null.
  [ "$(jq -r '.identity.plan_id' "$d")" = "$PLAN_ID" ]
  [ "$(jq -r '.identity.run_id' "$d")" = "$run" ]
  [ "$(jq -r '.identity.epic_id' "$d")" = "null" ]
  [ "$(jq -r '.revision.head_sha' "$d")" = "$cand" ]
  # the five identity facts, as data the PM brief renders from
  [ "$(jq -r '.release_decision.plan_summary.plan_id' "$d")" = "$PLAN_ID" ]
  [ "$(jq -r '.release_decision.plan_summary.plan_final_run_id' "$d")" = "$run" ]
  [ "$(jq -r '.release_decision.plan_summary.reviewed_candidate_sha' "$d")" = "$cand" ]
  [ "$(jq -r '.release_decision.plan_summary.target_ref' "$d")" = "main" ]
  [ "$(jq -r '.release_decision.plan_summary.approved_target_sha' "$d")" = "$thead" ]
  # and in the PM-facing one-liner, so a summary can never be read plan-agnostically
  [[ "$(jq -r '.release_decision.summary_for_pm' "$d")" == *"plan=${PLAN_ID}"* ]]
  [[ "$(jq -r '.release_decision.summary_for_pm' "$d")" == *"reviewed_candidate=${cand}"* ]]

  # a complete plan-final pack releases
  [ "$(jq -r '.release_decision.release_ready' "$d")" = "true" ]
  [ "$(jq -r '.release_decision.blockers | length' "$d")" = "0" ]

  # dual-run evidence, exactly as the EPIC hook emits it
  local dr; dr="$(_run_dir)/release-decision-dual-run.json"
  [ -f "$dr" ]
  [ "$(jq -r '.event' "$dr")" = "release_policy_dual_run" ]
  [ "$(jq -r '.candidate_sha' "$dr")" = "$cand" ]
  [ "$(jq -r '.target_head_sha' "$dr")" = "$thead" ]
  [ "$(jq -r '.enforcement' "$dr")" = "observe" ]

  # the stage does not move the plan on: PM authorization is Step 5's
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "AWAITING_PM" ]
}

# ─── AC4.2: the Reporter and Simplifier are MANDATORY here — the EPIC
#     `ca-review-complete` marker must not be able to make them a silent skip ──
@test "AC4: C4 reads the run-scoped delivery-report.json — a ca-review-complete marker cannot demote a missing Reporter to not_applicable" {
  _seed_c4_project
  # The EPIC-mode escape hatch, planted deliberately: marker present, report gone.
  rm -f "$(_run_dir)/delivery-report.json"
  : > "$(_run_dir)/ca-review-complete"

  _c4
  [ "$status" -eq 0 ]   # observe mode records the decision; it does not fail the stage
  local d; d="$(_decision)"
  [ "$(jq -r '.release_decision.reporter_status' "$d")" = "missing" ]
  [ "$(jq -r '.release_decision.release_ready' "$d")" = "false" ]
  run jq -r '[.release_decision.blockers[].input_id] | join(",")' "$d"
  [[ "$output" == *"reporter"* ]]
  # and NOT the EPIC-mode inversion
  [ "$(jq -r '.release_decision.reporter_reason' "$d")" != "not_plan_boundary" ]
}

@test "AC4: a Simplifier report whose Head: provenance is not the candidate blocks, never skips" {
  _seed_c4_project
  printf '# Simplifier report\n\nHead: %s\n' "$(_manifest_field "$PLAN_ID" plan_base_commit)" \
    > "$(_run_dir)/simplifier-report.md"

  _c4
  [ "$status" -eq 0 ]
  local d; d="$(_decision)"
  [ "$(jq -r '.release_decision.simplifier_status' "$d")" = "fail" ]
  [ "$(jq -r '.release_decision.release_ready' "$d")" = "false" ]
}

# ─── AC4.3: identity validation — an EPIC evidence directory, and a copy of a
#     valid EPIC pack placed at the plan path ────────────────────────────────
@test "AC4: passing an EPIC evidence directory fails plan-mode identity validation and writes NO decision" {
  _seed_c4_project
  local epic_dir=".aid-o/work/evidence/E-068-1_2/R-E-068-1_2-1"
  local out="$TEST_PROJECT_ROOT/${epic_dir}/release-decision.json"

  run env AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" \
    bash "$AID_PLUGIN_PATH/scripts/aid-release-policy.sh" \
      --plan "$PLAN_ID" --run-id "$(_manifest_field "$PLAN_ID" plan_final_run_id)" \
      --evidence-dir "$epic_dir" \
      --candidate-sha "$(_manifest_field "$PLAN_ID" candidate_sha)" \
      --target-ref main \
      --target-head-sha "$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)" \
      --out "$out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"IDENTITY MISMATCH"* ]]
  [[ "$output" == *"not the plan-final run directory recorded in the manifest"* ]]
  [ ! -f "$out" ]
}

@test "AC4: a mismatched --target-head-sha exits 1 regardless of policy mode, and reads no evidence" {
  _seed_c4_project
  run env AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" \
    bash "$AID_PLUGIN_PATH/scripts/aid-release-policy.sh" \
      --plan "$PLAN_ID" --run-id "$(_manifest_field "$PLAN_ID" plan_final_run_id)" \
      --evidence-dir "$(_manifest_field "$PLAN_ID" plan_final_evidence_dir)" \
      --candidate-sha "$(_manifest_field "$PLAN_ID" candidate_sha)" \
      --target-ref main \
      --target-head-sha "0000000000000000000000000000000000000000"
  [ "$status" -eq 1 ]
  [[ "$output" == *"target_branch_head_at_candidate_freeze"* ]]
  [ ! -f "$(_decision)" ]
}

@test "AC4: a copy of a valid EPIC artifact placed at the plan path is blocked on identity, not accepted" {
  _seed_c4_project
  # A complete, protocol-valid delivery-gate — but an EPIC's, carrying identity.epic_id
  # and the EPIC's run id. The path is right; the binding is not.
  local dir; dir="$(_run_dir)"
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  jq --arg e "E-068-1_2" --arg r "R-E-068-1_2-1" \
     '.identity.epic_id = $e | .identity.run_id = $r | del(.identity.plan_id)' \
     "$dir/delivery-gate.json" > "$dir/delivery-gate.json.tmp"
  mv "$dir/delivery-gate.json.tmp" "$dir/delivery-gate.json"

  _c4
  [ "$status" -eq 0 ]
  local d; d="$(_decision)"
  [ "$(jq -r '.release_decision.release_ready' "$d")" = "false" ]
  run jq -r '[.release_decision.blockers[] | select(.input_id == "delivery_gate") | .reason] | join(" ")' "$d"
  [[ "$output" == *"not bound to this plan-final attempt"* ]]
}

# ─── AC4: the per-EPIC roll-up blocker NAMES the EPIC ──────────────────────
@test "AC4: an EPIC whose roll-up contribution is missing is a blocker naming that EPIC" {
  _seed_c4_project
  local dir; dir="$(_run_dir)"
  jq '.sources = []' "$dir/acceptance-evidence.json" > "$dir/ae.tmp" && mv "$dir/ae.tmp" "$dir/acceptance-evidence.json"

  _c4
  [ "$status" -eq 0 ]
  local d; d="$(_decision)"
  run jq -r '[.release_decision.blockers[].input_id] | join(",")' "$d"
  [[ "$output" == *"epic_rollup:E-068-1_2"* ]]
  [ "$(jq -r '.release_decision.release_ready' "$d")" = "false" ]
}

# ─── AC4.4: a retry writes -final-2 and leaves run 1 byte-identical ─────────
@test "AC4: a retry after a PLAN_FIX writes R-<plan>-final-2 and never overwrites run 1's decision" {
  _seed_c4_project
  _c4
  [ "$status" -eq 0 ]
  local first_dir; first_dir="$(_run_dir)"
  local first_sha; first_sha="$(sha256sum "$first_dir/release-decision.json" | awk '{print $1}')"
  [[ "$(_manifest_field "$PLAN_ID" plan_final_run_id)" == *"-final-1" ]]

  # A fix lands on the plan branch → the candidate is invalidated on the next stage.
  _commit_on "plan/${PLAN_ID}" fix.txt "an accepted specialist fix"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
  _c4
  [ "$status" -eq 6 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_FIX" ]

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  [ "$(_manifest_field "$PLAN_ID" plan_final_run_id)" = "R-${PLAN_ID}-final-2" ]
  local second_dir; second_dir="$(_run_dir)"
  [ "$second_dir" != "$first_dir" ]

  # Run 1 is untouched by everything that followed it.
  [ "$(sha256sum "$first_dir/release-decision.json" | awk '{print $1}')" = "$first_sha" ]
  [ ! -f "$second_dir/release-decision.json" ]
}

# ─── AC4.5: the PM summary keeps the four facts SEPARATE ───────────────────
@test "AC4: the PM plan-final summary renders reviewed candidate, approved target, final merge SHA and tag status as four distinct fields" {
  _seed_c4_project
  _c4
  [ "$status" -eq 0 ]

  _summary
  [ "$status" -eq 0 ]

  local md; md="$(_run_dir)/pm-summary.md"
  [ -f "$md" ]
  local cand thead
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  thead="$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)"

  grep -Fq "Reviewed candidate SHA:" "$md"
  grep -Fq "Approved target SHA:" "$md"
  grep -Fq "Final main merge SHA:" "$md"
  grep -Fq "Release / tag status:" "$md"
  grep -Fq "$cand" "$md"
  grep -Fq "$thead" "$md"
  # the merge has NOT happened — the summary must say so, not imply a release
  grep -Fq "Final main merge SHA:** _not yet recorded_" "$md"
  grep -Fq "not_tagged" "$md"
  # roadmap §8 sections
  grep -Fq "## What the plan delivered" "$md"
  grep -Fq "### Skipped at EPIC level" "$md"
  grep -Fq "## Plan-final gate results" "$md"
  grep -Fq "## Specialist review summary" "$md"
  grep -Fq "## Remaining backlog" "$md"
  grep -Fq "## Merge decision" "$md"
  # and it is the PLAN's summary, never an EPIC's
  grep -Fq "# PM Plan-Final Summary — ${PLAN_ID}" "$md"
  grep -Fq "E-068-1_2" "$md"

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "AWAITING_PM" ]
}

@test "AC4: --stage summary refuses when no plan-mode decision exists (it reports the decision, never substitutes for it)" {
  _seed_c4_project
  _summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"run '--stage c4' first"* ]]
}

@test "AC4: --stage summary refuses a decision bound to another plan-final attempt" {
  _seed_c4_project
  _c4
  [ "$status" -eq 0 ]
  local d; d="$(_decision)"
  jq '.identity.run_id = "R-P068-final-9"' "$d" > "${d}.tmp" && mv "${d}.tmp" "$d"

  _summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"never be able to imply an intermediate EPIC was released"* ]]
}

# ─── the release-decision schema's blockers[].input_id oneOf ───────────────
@test "AC4: blockers[].input_id accepts canonical ids and well-formed epic_rollup ids, and rejects both malformed branches" {
  local schema="$AID_PLUGIN_PATH/defaults/schemas/release-decision.schema.json"
  run python3 - "$schema" <<'PY'
import json, sys
from jsonschema import Draft202012Validator
schema = json.load(open(sys.argv[1]))
sub = schema["properties"]["release_decision"]["properties"]["blockers"]["items"]["properties"]["input_id"]
v = Draft202012Validator(sub)
cases = {
    "delivery_gate": True,          # canonical (branch 1)
    "delivery_report": True,        # plan-mode Reporter input (branch 1)
    "epic_rollup:E-068-1_2": True,  # well-formed EPIC id (branch 2)
    "epic_rollup:E-999-12_34": True,
    "delivery_gates": False,        # typo in a canonical id still fails
    "epic_rollup:E-68-1_2": False,  # malformed EPIC id still fails
    "epic_rollup:*": False,
}
bad = [k for k, want in cases.items() if v.is_valid(k) != want]
print("MISMATCH:", bad) if bad else print("ALL_OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALL_OK"* ]]
}
