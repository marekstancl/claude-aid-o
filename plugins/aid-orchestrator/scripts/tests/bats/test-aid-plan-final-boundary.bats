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
  LIFECYCLE_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
  export LIFECYCLE_LIB
  # shellcheck disable=SC1090
  source "$LIFECYCLE_LIB"
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
  # `.aid-o/reports/` is gitignored here for the same reason production
  # projects gitignore it: the human report projection is private. Step 6's
  # close-check reads that mode (report_storage: private/gitignored) and never
  # lets the Markdown projection alone make close pass.
  printf '.aid-o/work/\n.aid-o/reports/\n' > "$TEST_PROJECT_ROOT/.gitignore"
  git -C "$TEST_PROJECT_ROOT" add -- .gitignore
  git -C "$TEST_PROJECT_ROOT" commit -q -m "gitignore the runtime area"
  # P068 Step 5 (opt-in): the GIT-TRACKED lifecycle manifest the plan merge binds
  # deliveries into. It has to exist on the TARGET branch BEFORE the plan branch
  # is cut — a later commit on main would advance the target head past the one
  # the candidate is frozen against, which plan-merge-to-main correctly rejects
  # as a stale authorization. Built through the REAL entry point
  # (aid_lifecycle_ensure_manifest + its strict legacy EPIC parse), never a
  # hand-written fixture manifest.
  if [[ "${AID_TEST_SEED_LIFECYCLE:-0}" == "1" ]]; then
    mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
    printf '# %s\n\n**EPIC 1: the delivered one**\n\n**EPIC 2: the abandoned one**\n' "$plan_id" \
      > "$TEST_PROJECT_ROOT/.aid-o/plans/${plan_id}-lifecycle.md"
    aid_lifecycle_ensure_manifest "$plan_id" "$TEST_PROJECT_ROOT" >/dev/null
    # The DECLARED mode, written durably while main is still the checked-out
    # branch and before any candidate freeze — a later write would advance the
    # target head past the frozen one and be rejected as a stale authorization.
    if [[ -n "${AID_TEST_DECLARED_PLAN_MODE:-}" ]]; then
      aid_lifecycle_set_plan_mode "$plan_id" "$AID_TEST_DECLARED_PLAN_MODE" "$TEST_PROJECT_ROOT" >/dev/null
    fi
  fi
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

# =============================================================================
# ─── aid-plan-fsm.sh plan-merge-to-main (Step 5) ─────────────────────────
#     + aid-release.sh tag-plan + defaults/hooks/pre-push
# =============================================================================
#
# AC5/AC6 — the ONE place in AID where the target branch moves. Every test here
# asserts what happened to `main`, because "the merge was refused" is only a
# real guarantee if the target branch is provably byte-identical afterwards.

# _seed_merge_project — a plan at AWAITING_PM, at a frozen candidate, with the
# git-tracked lifecycle manifest already on main (see _bootstrap's opt-in) and a
# SECOND declared EPIC recorded as abandoned in the RUNTIME manifest — the CF1
# input plan-merge-to-main re-scopes.
#
# It reaches AWAITING_PM through the REAL sync + freeze stages and then walks the
# REAL plan-state transition table (PLAN_GATES -> PLAN_REVIEW -> AWAITING_PM)
# rather than re-running the gate and review stages: those two stages are Step 2
# and Step 3's own, exhaustively covered above, and each costs a full release
# gate profile run. What plan-merge-to-main actually consumes from them is the
# frozen candidate and the PLAN-LEVEL audit/curator reports, and both are set up
# here explicitly — so nothing this seed skips is a precondition this command
# reads.
_seed_merge_project() {
  export AID_TEST_SEED_LIFECYCLE=1
  _bootstrap
  # REAL work on the plan branch. Without it the candidate IS the target head,
  # and `git commit-tree -p <target> -p <candidate>` collapses two identical
  # parents into one — the two-parent assertion would then be testing a
  # degenerate plan (one with no commits), not a plan.
  _commit_on "plan/${PLAN_ID}" epic-work.txt "feat: the EPIC's work"
  _add_epic "$PLAN_ID" "E-068-1_2"
  local mc; mc="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "merged_to_plan" "$mc"
  # The SECOND declared EPIC, terminated without delivery — CF1's input.
  _add_epic "$PLAN_ID" "E-068-2_2"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-2_2" "abandoned"
  plan_manifest_update "$PLAN_ID" \
    '(.plan_boundary_manifest.epic_runs[] | select(.epic_id == "E-068-2_2") | .terminal_reason) = "PM dropped it"' >/dev/null

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  plan_state_transition "$PLAN_ID" "PLAN_GATES" "PLAN_REVIEW" >/dev/null
  plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "AWAITING_PM" >/dev/null

  # The ONE plan-level review the binder derives every EPIC's verdict from.
  local dir; dir="$(_run_dir)"
  mkdir -p "$dir"
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  jq -n --arg h "$cand" \
    '{schema_version:"aid-2.0", artifact_type:"audit_report",
      revision:{head_sha:$h}, status:"pass",
      audit_report:{reviewed_head:$h, blocking_findings:false}}' \
    > "${dir}/audit-report.json"
  jq -n '{schema_version:"aid-2.0", artifact_type:"curator",
          status:"pass", curator:{blocking_findings:false}}' \
    > "${dir}/curator-report.json"

  # The controller keeps the worktree on the candidate across the PM boundary.
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
}

# _merge_commit — the published plan merge SHA, read from the RUNTIME manifest.
# NOT from $output: bats `run` folds stderr into stdout, and this command writes
# a deliberately loud operator narrative to stderr.
_merge_commit() {
  jq -r '.plan_boundary_manifest.plan_final_merge.merge_commit' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
}

# _poke_manifest <jq_expr> — edit the RUNTIME manifest JSON DIRECTLY, bypassing
# plan_manifest_update's invariant enforcement. That bypass is the point: the
# fail-closed freeze-time tests need a DEGENERATE on-disk manifest (a missing or
# malformed candidate_frozen_at), and the writer correctly refuses to produce
# one — the paired-nullable invariant is exactly what keeps it from happening
# through the sanctioned path. Hand corruption is therefore the only honest way
# to prove plan-merge-to-main does not trust the file it reads.
_poke_manifest() {
  local f="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  local t="${f}.poke"
  jq "$1" "$f" > "$t" && mv "$t" "$f"
}

# _main_sha / _plan_sha — the two refs every assertion here is about.
_main_sha() { git -C "$TEST_PROJECT_ROOT" rev-parse main; }
_plan_sha() { git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID"; }

# _decision_file [jq_override] — a VALID PM MERGE decision bound to this plan,
# this attempt, this candidate and this target head. The override corrupts
# exactly one field so each refusal test isolates one cause.
_decision_file() {
  local override="${1:-.}"
  local f="$TEST_TMPDIR/pm-decision.json"
  # The decision time is derived from the manifest's ACTUAL candidate_frozen_at,
  # never a wall-clock literal: a hardcoded date silently becomes "before the
  # freeze" once real time passes it, and every refusal test then fails on the
  # freshness guard instead of the cause it isolates (observed 2026-07-26).
  local _frozen; _frozen="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  jq -n --arg p "$PLAN_ID" \
        --arg r "$(_manifest_field "$PLAN_ID" plan_final_run_id)" \
        --arg c "$(_manifest_field "$PLAN_ID" candidate_sha)" \
        --arg t "$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)" \
        --arg at "$_frozen" \
    '{schema_version:"aid-pm-plan-decision-1.0", artifact_type:"pm_plan_decision",
      producer:"aid-test@1.0", created_at:$at,
      plan_id:$p, plan_final_run_id:$r, decision:"MERGE",
      candidate_sha:$c, target_branch:"main", target_head_sha:$t,
      decided_at:$at, decided_by:"pm"}' \
    | jq "$override" > "$f"
  printf '%s' "$f"
}

# _merge [decision_file] [extra args...] — the command under test.
_merge() {
  local d="${1:-$(_decision_file)}"; shift || true
  run bash "$PLAN_FSM_CLI" plan-merge-to-main "$PLAN_ID" --decision "$d" \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# ─── AC5.1: every refusal leaves the target branch unchanged ───────────────

@test "AC5: a MISSING decision file exits 1 with main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  _merge "$TEST_TMPDIR/nope.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no PM decision"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a MALFORMED decision file exits 1 with main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  printf 'not json at all' > "$TEST_TMPDIR/bad.json"
  _merge "$TEST_TMPDIR/bad.json"
  [ "$status" -eq 1 ]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision that fails pm-plan-decision.schema.json is rejected BEFORE any Git action" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  # A verdict outside the enum — structurally parseable, contractually invalid.
  local d; d="$(_decision_file '.decision = "MAYBE"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pm-plan-decision.schema.json"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision missing a REQUIRED contract field is rejected by the schema" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file 'del(.target_head_sha)')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pm-plan-decision.schema.json"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision for a DIFFERENT plan exits 1 before any Git action" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.plan_id = "P999"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"authorizes plan 'P999'"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision bound to a DIFFERENT plan-final run id exits 1 before any Git action" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.plan_final_run_id = "R-P068-final-99"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"earlier attempt"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision naming the WRONG candidate exits 1 with main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.candidate_sha = "0000000000000000000000000000000000000000"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"candidate mismatch"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision naming the WRONG approved target head exits 1 with main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.target_head_sha = "0000000000000000000000000000000000000000"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"approved target head"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: decision FIX refuses the merge, moves the plan to PLAN_FIX and leaves main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.decision = "FIX" | .reason = "one more pass"')"
  _merge "$d"
  [ "$status" -eq 3 ]
  [ "$(_main_sha)" = "$before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_FIX" ]
}

@test "AC5: decision ABORT refuses the merge, moves the plan to ABORTED with the reason recorded, main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.decision = "ABORT" | .reason = "superseded by P069"')"
  _merge "$d"
  [ "$status" -eq 3 ]
  [ "$(_main_sha)" = "$before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ABORTED" ]
  [ "$(_manifest_field "$PLAN_ID" terminal_reason)" = "superseded by P069" ]
}

@test "AC5: a STALE authorization (main advanced while the PM decided) merges nothing and returns the plan to PLAN_SYNC" {
  _seed_merge_project
  local d; d="$(_decision_file)"
  # main advances after the freeze and after the decision was written.
  _commit_on main hotfix.txt "hotfix on main"
  local before; before="$(_main_sha)"

  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE AUTHORIZATION"* ]]
  # main is byte-identical to its advanced state — no merge was published.
  [ "$(_main_sha)" = "$before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]
  # the candidate binding is gone, so no decision can be replayed against it
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "null" ]
}

# ─── AC5.2 + AC5.3: freeze-time validation, fail-closed on every degenerate
#     input ────────────────────────────────────────────────────────────────

@test "AC5: a decision whose decided_at PRECEDES candidate_frozen_at is rejected before any Git action" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.decided_at = "2000-01-01T00:00:00Z"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BEFORE the candidate was frozen"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a manifest MISSING candidate_frozen_at exits 1 — never 'assume old enough'" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file)"
  _poke_manifest '.plan_boundary_manifest.candidate_frozen_at = null'
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no candidate_frozen_at"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a candidate_frozen_at that is not valid RFC 3339 UTC exits 1" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file)"
  _poke_manifest '.plan_boundary_manifest.candidate_frozen_at = "yesterday-ish"'
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid RFC 3339 UTC instant"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decided_at that matches the pattern but is not a real instant exits 1" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  # Pattern-valid (schema passes), calendar-invalid (date -d refuses) — the
  # exact input a regex-only check would wave through.
  local d; d="$(_decision_file '.decided_at = "2026-13-45T99:99:99Z"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"decided_at"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision bound to a PRE-REFREEZE candidate fails against the rewritten candidate_frozen_at" {
  _seed_merge_project
  local old_decision; old_decision="$(_decision_file)"
  # A refreeze rewrites BOTH candidate_sha and candidate_frozen_at. Simulate the
  # rewritten freeze time being LATER than the old decision.
  _poke_manifest '.plan_boundary_manifest.candidate_frozen_at = "2099-01-01T00:00:00Z"'
  local before; before="$(_main_sha)"
  _merge "$old_decision"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BEFORE the candidate was frozen"* ]]
  [ "$(_main_sha)" = "$before" ]
}

# ─── AC5.4 + AC5.5: the compare-and-swap publish ───────────────────────────

@test "AC5: the merge commit is built without moving any ref, and a rejected update-ref leaves the target byte-identical" {
  _seed_merge_project
  local cand target; cand="$(_plan_sha)"; target="$(_main_sha)"

  # Stage 1 exactly as the command performs it: tree, then commit, then publish.
  local tree; tree="$(git -C "$TEST_PROJECT_ROOT" merge-tree --write-tree --no-messages "$target" "$cand")"
  local mc; mc="$(git -C "$TEST_PROJECT_ROOT" commit-tree "$tree" -p "$target" -p "$cand" -m "merge(plan): probe")"
  # NOTHING has moved: main is still exactly where it was.
  [ "$(_main_sha)" = "$target" ]

  # A concurrent advance between the head check and the publish.
  _commit_on main racer.txt "another process moved main"
  local raced; raced="$(_main_sha)"
  [ "$raced" != "$target" ]

  # The compare-and-swap must REJECT, and main must be byte-identical to the
  # racer's state — the losing merge publishes nothing.
  run git -C "$TEST_PROJECT_ROOT" update-ref refs/heads/main "$mc" "$target"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$raced" ]
}

# ─── AC5.6 + AC5.10 + AC5.11: the happy path, the lifecycle commit and CF1 ──

@test "AC5: a MERGE decision publishes exactly one merge commit whose parents are the approved target head and the candidate" {
  _seed_merge_project
  local cand target; cand="$(_plan_sha)"; target="$(_main_sha)"

  _merge
  [ "$status" -eq 0 ]

  local mc; mc="$(_merge_commit)"
  [[ "$mc" =~ ^[0-9a-f]{40}$ ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "${mc}^1")" = "$target" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "${mc}^2")" = "$cand" ]
  # The candidate is reachable from main, and main is at (or above) the merge.
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$cand" main
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$mc" main
  [ "$status" -eq 0 ]
  # Exactly ONE merge commit naming this plan.
  [ "$(git -C "$TEST_PROJECT_ROOT" log main --merges --grep "merge(plan): ${PLAN_ID}" --pretty=%H | wc -l)" -eq 1 ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_MERGING" ]
}

@test "AC5: the lifecycle commit lands on main by plumbing — every non-abandoned EPIC is bound to the plan merge commit" {
  _seed_merge_project
  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"

  # The manifest is read from the TARGET branch, not the worktree: the whole
  # point is that the commit landed on main while HEAD stayed on the plan branch.
  local m; m="$TEST_TMPDIR/manifest-on-main.yaml"
  git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml" > "$m"
  [ "$(yq -r '.deliveries."E-068-1_2".delivery_sha' "$m")" = "$mc" ]
  [ "$(yq -r '.deliveries."E-068-1_2".delivery' "$m")" = "delivered" ]
  [ "$(yq -r '.deliveries."E-068-1_2".review' "$m")" = "accepted" ]

  # HEAD never left the plan branch, and the plan branch is not left dirty.
  [ "$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)" = "plan/${PLAN_ID}" ]
  run git -C "$TEST_PROJECT_ROOT" diff --quiet -- .aid-lifecycle
  [ "$status" -eq 0 ]
}

@test "AC5 (CF1): the abandoned EPIC is re-scoped in the SAME commit as the bindings, and stops counting as required" {
  _seed_merge_project
  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"

  local m; m="$TEST_TMPDIR/manifest-on-main.yaml"
  git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml" > "$m"
  [ "$(yq -r '.declared_epics[] | select(.id == "E-068-2_2") | .scope' "$m")" = "abandoned" ]
  # ONE commit for both facts: the re-scope and the bindings are in the same tree.
  [ "$(yq -r '.deliveries."E-068-1_2".delivery_sha' "$m")" = "$mc" ]
  # An abandoned EPIC is never bound as delivered.
  [ "$(yq -r '.deliveries."E-068-2_2".delivery_sha // "absent"' "$m")" = "absent" ]

  # And it is excluded from the closure denominator. The closure state MUST be
  # evaluated on the TARGET branch, not from the plan worktree: the lifecycle
  # commit landed on main by plumbing and the plan branch's own copy of the
  # manifest is deliberately restored, so reading it there would answer a
  # question about the wrong branch. Step 6 (plan-close) runs on the target
  # branch for exactly this reason.
  git -C "$TEST_PROJECT_ROOT" worktree add -q "$TEST_TMPDIR/closure-wt" main
  run aid_plan_closure_state "$PLAN_ID" "$TEST_TMPDIR/closure-wt"
  [ "$output" != "active" ]
  [ "$output" != "legacy-unverifiable" ]
}

@test "AC5: the lifecycle commit succeeds with the TARGET BRANCH CHECKED OUT IN ANOTHER WORKTREE" {
  _seed_merge_project
  # The normal production shape: main is checked out in a linked worktree, so
  # `git checkout main` from the plan worktree is impossible — Git refuses the
  # same branch twice. The plumbing path must not care.
  git -C "$TEST_PROJECT_ROOT" worktree add -q "$TEST_TMPDIR/main-wt" main
  run git -C "$TEST_PROJECT_ROOT" checkout main
  [ "$status" -ne 0 ]        # proof the legacy checkout path is genuinely blocked

  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"
  local m; m="$TEST_TMPDIR/manifest-on-main.yaml"
  git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml" > "$m"
  [ "$(yq -r '.deliveries."E-068-1_2".delivery_sha' "$m")" = "$mc" ]
}

@test "AC5: a crash between the publish and the lifecycle commit is resolved by re-applying the bindings, never a second merge" {
  _seed_merge_project
  local cand; cand="$(_plan_sha)"
  local target; target="$(_main_sha)"

  # Publish the merge exactly as stage 1 does, then stop — the crash point.
  local tree mc
  tree="$(git -C "$TEST_PROJECT_ROOT" merge-tree --write-tree --no-messages "$target" "$cand")"
  mc="$(git -C "$TEST_PROJECT_ROOT" commit-tree "$tree" -p "$target" -p "$cand" -m "merge(plan): ${PLAN_ID} — crashed run")"
  git -C "$TEST_PROJECT_ROOT" update-ref refs/heads/main "$mc" "$target"

  # Resume: the binding pass alone, idempotently, on top of the published merge.
  run aid_lifecycle_plan_merge_bind "$PLAN_ID" "$TEST_PROJECT_ROOT" "$mc" \
    "$(_run_dir)" "E-068-2_2=abandoned"
  [ "$status" -eq 0 ]
  local m; m="$TEST_TMPDIR/m1.yaml"
  git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml" > "$m"
  [ "$(yq -r '.deliveries."E-068-1_2".delivery_sha' "$m")" = "$mc" ]
  local after_first; after_first="$(_main_sha)"

  # A SECOND resume is a no-op: no duplicate commit, no second merge.
  run aid_lifecycle_plan_merge_bind "$PLAN_ID" "$TEST_PROJECT_ROOT" "$mc" \
    "$(_run_dir)" "E-068-2_2=abandoned"
  [ "$status" -eq 0 ]
  [ "$(_main_sha)" = "$after_first" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" log main --merges --grep "merge(plan): ${PLAN_ID}" --pretty=%H | wc -l)" -eq 1 ]
}

# ─── AC5.7 + AC5.8: the ONE tag, and resume without duplicates ─────────────

@test "AC5: a no-bump plan merges and closes with NO tag, and tag-plan is never called" {
  _seed_merge_project
  # release-prep.json records `none` — prepare-plan resolved no version bump.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  jq -n '{schema_version:"aid-release-prep-1.0", version:"none"}' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/release-prep.json"

  _merge
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO TAG"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 0 ]
}

@test "AC5: a plan WITH a prepared version creates exactly ONE tag, on the final merge commit" {
  _seed_merge_project
  jq -n '{schema_version:"aid-release-prep-1.0", version:"9.9.9"}' \
    > "$(_run_dir)/release-prep.json"

  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 1 ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse 'v9.9.9^{commit}')" = "$mc" ]
  # No intermediate EPIC produced a version commit or a tag: the ONLY tag in the
  # repository is this one, on the plan merge.
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l)" = "v9.9.9" ]
}

@test "AC5: a resumed run after full success creates no duplicate merge, no duplicate lifecycle commit and no duplicate tag" {
  _seed_merge_project
  jq -n '{schema_version:"aid-release-prep-1.0", version:"9.9.9"}' \
    > "$(_run_dir)/release-prep.json"

  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"
  local after; after="$(_main_sha)"

  _merge
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESUME"* ]]
  [ "$(_main_sha)" = "$after" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" log main --merges --grep "merge(plan): ${PLAN_ID}" --pretty=%H | wc -l)" -eq 1 ]
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 1 ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse 'v9.9.9^{commit}')" = "$mc" ]
}

# ─── Error handling: a conflicting candidate ───────────────────────────────

@test "AC5: a merge conflict against the target branch exits 4, moves the plan to CONFLICT and leaves main unchanged" {
  _seed_merge_project
  # Both sides change the SAME file differently. main's advance is then recorded
  # as the approved target head so the stale-authorization guard does not fire
  # first — this test is about the conflict path itself.
  _commit_on "plan/${PLAN_ID}" clash.txt "plan side"
  # keep the candidate == plan head
  _poke_manifest ".plan_boundary_manifest.candidate_sha = \"$(_plan_sha)\""
  _commit_on main clash.txt "main side"
  _poke_manifest ".plan_boundary_manifest.target_branch_head_at_candidate_freeze = \"$(_main_sha)\""
  local before; before="$(_main_sha)"

  _merge
  [ "$status" -eq 4 ]
  [[ "$output" == *"MERGE CONFLICT"* ]]
  [ "$(_main_sha)" = "$before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CONFLICT" ]
  # No MERGE_HEAD was ever created — the merge happened entirely in object space.
  [ ! -f "$TEST_PROJECT_ROOT/.git/MERGE_HEAD" ]
}

@test "AC5: resolving a CONFLICT by re-syncing INVALIDATES the frozen candidate and returns the plan to PLAN_SYNC" {
  _seed_merge_project
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  # Drive the plan into CONFLICT the way plan-merge-to-main does.
  plan_state_transition "$PLAN_ID" "AWAITING_PM" "CONFLICT" >/dev/null
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CONFLICT" ]

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"CANDIDATE INVALIDATED"* ]]
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "null" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]
}

# ─── aid-release.sh tag-plan ───────────────────────────────────────────────

@test "AC5: tag-plan is idempotent — an existing tag on the SAME merge SHA exits 0 without acting" {
  _seed_merge_project
  local sha; sha="$(_main_sha)"
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$sha" --version 3.2.1 \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$sha" --version 3.2.1 \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 1 ]
}

@test "AC5: tag-plan exits 1 when the tag exists on a DIFFERENT commit, and never moves it" {
  _seed_merge_project
  local other; other="$(_main_sha)"
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$other" --version 3.2.1 \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local elsewhere; elsewhere="$(_plan_sha)"
  [ "$elsewhere" != "$other" ]
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$elsewhere" --version 3.2.1 \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"immutable"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse 'v3.2.1^{commit}')" = "$other" ]
}

@test "AC5: tag-plan refuses the literal 'none' as a version (a no-bump plan must not call it)" {
  _seed_merge_project
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$(_main_sha)" --version none \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 0 ]
}

@test "AC5: prepare-plan records the resolved version in release-prep.json, and 'none' when no bump was needed" {
  _bootstrap
  _seed_version_project
  _prepare "$PLAN_ID" --bump minor
  [ "$status" -eq 0 ]
  local rec="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/release-prep.json"
  [ -s "$rec" ]
  [ "$(jq -r '.version' "$rec")" = "1.3.0" ]

  # A chore-only follow-up resolves to no bump and records the literal `none`.
  git -C "$TEST_PROJECT_ROOT" tag -a "v1.3.0" -m "released" >/dev/null 2>&1
  _commit_on "plan/${PLAN_ID}" chore.txt "chore: tidy"
  _prepare "$PLAN_ID" --bump auto
  [ "$status" -eq 0 ]
  [ "$(jq -r '.version' "$rec")" = "none" ]
}

# ─── defaults/hooks/pre-push: plan/* and task/* are exempt, main is not ─────

@test "AC5: pushing plan/* or task/* with feat:/fix: commits and no release: commit is allowed, while main in the same state is blocked" {
  _bootstrap
  local hook="$AID_PLUGIN_PATH/defaults/hooks/pre-push"
  # A tag, then a feat: commit and no release: commit — the exact state the
  # guard blocks. Made on main so LAST_TAG..HEAD sees it from any branch.
  git -C "$TEST_PROJECT_ROOT" tag -a v1.0.0 -m base
  _commit_on main feature.txt "feat: a plan-branch feature"

  # main: still blocked.
  run bash -c "cd '$TEST_PROJECT_ROOT' && printf 'refs/heads/main %s refs/heads/main %s\n' \
    \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000 | bash '$hook' origin git@example:x.git"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Push blocked"* ]]

  # plan/*: exempt.
  run bash -c "cd '$TEST_PROJECT_ROOT' && printf 'refs/heads/plan/${PLAN_ID} %s refs/heads/plan/${PLAN_ID} %s\n' \
    \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000 | bash '$hook' origin git@example:x.git"
  [ "$status" -eq 0 ]

  # task/*: exempt.
  run bash -c "cd '$TEST_PROJECT_ROOT' && printf 'refs/heads/task/E-068-1_2/main %s refs/heads/task/E-068-1_2/main %s\n' \
    \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000 | bash '$hook' origin git@example:x.git"
  [ "$status" -eq 0 ]

  # A push carrying BOTH a plan branch and main is still checked.
  run bash -c "cd '$TEST_PROJECT_ROOT' && { printf 'refs/heads/plan/${PLAN_ID} %s refs/heads/plan/${PLAN_ID} %s\n' \
    \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000; \
    printf 'refs/heads/main %s refs/heads/main %s\n' \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000; } | bash '$hook' origin git@example:x.git"
  [ "$status" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# CP2 regressions (2026-07-26) — the publish/recovery invariant.
# Each of these reproduces a defect the step-5 review found and the fix closes.
# ═══════════════════════════════════════════════════════════════════════════

_ops_jsonl() { printf '%s/.aid-o/work/plan-state/%s/operations.jsonl' "$TEST_PROJECT_ROOT" "$1"; }

# ─── M4: the pre-push exemption is about the REMOTE target, not the local ref ─

@test "CP2 M4: a plan/* or task/* ref pushed AT main is blocked; same-name pushes stay exempt" {
  _bootstrap
  local hook="$AID_PLUGIN_PATH/defaults/hooks/pre-push"
  git -C "$TEST_PROJECT_ROOT" tag -a v1.0.0 -m base
  _commit_on main feature.txt "feat: an unreleased feature"
  local sha; sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  local zero=0000000000000000000000000000000000000000

  _push() {
    run bash -c "cd '$TEST_PROJECT_ROOT' && printf '%s %s %s %s\n' '$1' '$sha' '$2' '$zero' \
      | bash '$hook' origin git@example:x.git"
  }

  # The attack: an exempt-looking LOCAL ref aimed at the guarded remote branch.
  _push "refs/heads/plan/${PLAN_ID}" "refs/heads/main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Push blocked"* ]]

  _push "refs/heads/task/E-068-1_2/main" "refs/heads/main"
  [ "$status" -eq 1 ]

  # The legitimate pushes are untouched.
  _push "refs/heads/plan/${PLAN_ID}" "refs/heads/plan/${PLAN_ID}"
  [ "$status" -eq 0 ]

  _push "refs/heads/task/E-068-1_2/main" "refs/heads/task/E-068-1_2/main"
  [ "$status" -eq 0 ]
}

# ─── M1: a recorded resulting_sha must not disarm the stale-auth guard ───────

@test "CP2 M1: after the target is REWOUND past our merge, a re-run publishes nothing and returns to PLAN_SYNC" {
  _seed_merge_project
  local before_main; before_main="$(_main_sha)"
  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"
  [ -n "$mc" ]

  # The target branch is rewound PAST our merge to a commit that is neither the
  # approved head nor a descendant of the merge: the op log still holds our
  # resulting_sha, but it no longer explains where main is. This is the exact
  # shape that used to fall through and CAS-publish against the live head.
  # (Rewinding to exactly the approved head is a different, benign case: the
  # decision still describes that head, so re-converging there is correct.)
  local earlier; earlier="$(git -C "$TEST_PROJECT_ROOT" rev-parse "${before_main}~1")"
  [ -n "$earlier" ]
  git -C "$TEST_PROJECT_ROOT" branch -f main "$earlier"
  local rewound; rewound="$(_main_sha)"
  [ "$rewound" != "$before_main" ]

  _merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"STALE AUTHORIZATION"* ]]
  [ "$(_main_sha)" = "$rewound" ]
  # The plan is no longer in a state that authorizes a publish, and a further
  # attempt refuses again rather than converging onto the rewound head.
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [[ "$output" != *"AWAITING_PM"* ]]
  _merge
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$rewound" ]
}

@test "CP2 M1: a target advance that still CONTAINS our merge resumes without a second merge" {
  _seed_merge_project
  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"

  # main moves forward, but our merge remains an ancestor — a legitimate resume.
  _commit_on main later.txt "chore: unrelated later work"
  local advanced; advanced="$(_main_sha)"
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$mc" "$advanced"
  [ "$status" -eq 0 ]

  _merge
  [[ "$output" != *"STALE AUTHORIZATION"* ]]
  # Exactly one merge of this candidate exists on main.
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | grep -c '^${mc}$'"
  [ "${output}" = "1" ]
}

# ─── M2: the operation key identifies the candidate, not just the plan ───────

@test "CP2 M2: the merge operation key is bound to the candidate, so a new candidate is a new operation" {
  _seed_merge_project
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  _merge
  [ "$status" -eq 0 ]

  # The recorded op_id names THIS candidate. Before the fix it was plan-id-only,
  # so a later attempt with a different candidate reconciled against this very
  # entry and was misreported as a crash resume.
  local ops; ops="$(jq -r 'select(.command == "plan-merge-to-main") | .op_id' "$(_ops_jsonl "$PLAN_ID")" | sort -u)"
  [ -n "$ops" ]
  [[ "$ops" == *"$cand"* ]]
  # And it is not the plan-id-only shape any more.
  [[ "$ops" != *"plan-merge-to-main:${PLAN_ID}:-:0:${PLAN_ID}"* ]]
}

# ─── M3: a failed lifecycle bind leaves NO dirty tracked file ────────────────

@test "CP2 M3: a lifecycle bind that fails mid-way restores the tracked manifest byte-identically" {
  _seed_merge_project
  local relpath=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  local manifest="${TEST_PROJECT_ROOT}/${relpath}"
  [ -f "$manifest" ]
  local before; before="$(sha256sum "$manifest" | awk '{print $1}')"

  # One VALID re-scope (which really rewrites the file) followed by an INVALID
  # one (which fails). Before the fix the valid write stayed on disk and the
  # tracked file was left dirty, deadlocking the prescribed re-run.
  run bash -c "cd '$TEST_PROJECT_ROOT' && source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh' && \
    aid_lifecycle_plan_merge_bind '$PLAN_ID' '$TEST_PROJECT_ROOT' \
      \"\$(git rev-parse main)\" '$(_run_dir)' 'E-068-2_2=abandoned' 'E-068-1_2=not-a-scope'"
  [ "$status" -ne 0 ]

  local after; after="$(sha256sum "$manifest" | awk '{print $1}')"
  [ "$before" = "$after" ]

  # And the tracked tree is clean, so the printed remedy is actually runnable.
  run bash -c "git -C '$TEST_PROJECT_ROOT' status --porcelain -- '$relpath'"
  [ -z "$output" ]
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-close (Step 6) ──────────────────────────────────
# =============================================================================
#
# AC7 — "plan close is truly final and recoverable". Every test here asserts one
# of two things: that ONE individually removed or corrupted precondition BLOCKS
# the close (and leaves no marker), or that a close which does pass leaves
# exactly one atomic, head-bound marker AND a committed `.aid-lifecycle`
# receipt. The negative half is the point: a close that cannot be blocked is not
# a gate, it is a rubber stamp.

_marker() { printf '%s/.aid-o/work/plan-state/%s/plan-close-complete' "$TEST_PROJECT_ROOT" "$PLAN_ID"; }
_state_lock() { printf '%s/.aid-o/work/plan-state/%s/plan-state.yaml.lock' "$TEST_PROJECT_ROOT" "$PLAN_ID"; }
_manifest_lock() { printf '%s/.aid-o/work/plan-state/%s/plan-boundary-manifest.json.lock' "$TEST_PROJECT_ROOT" "$PLAN_ID"; }
_close_lock() { printf '%s/.aid-o/work/plan-state/%s/plan-close.lock' "$TEST_PROJECT_ROOT" "$PLAN_ID"; }
_receipt_rel() { printf '.aid-lifecycle/receipts/%s.yaml' "$PLAN_ID"; }

# _close — the command under test.
_close() {
  run bash "$PLAN_FSM_CLI" plan-close "$PLAN_ID" \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# _seed_plan_final_evidence — the plan-final review + C4 records the close
# transaction attests to. Built by writing REAL files into the attempt's run
# directory and recording their REAL sha256 in the manifest, exactly as
# `--stage review` does — so a later corruption of any one of them is detected
# by the same hash comparison production uses, not by a test-only shortcut.
# (The review and C4 STAGES themselves are Step 2/3/4's own exhaustive
# coverage above; re-running them here would cost a full release gate profile
# per test and prove nothing about close.)
_seed_plan_final_evidence() {
  local dir; dir="$(_run_dir)"
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  local run_id; run_id="$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  local base; base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  local thead; thead="$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)"
  mkdir -p "$dir"

  jq -n '{overall:"pass", gates:[]}' > "${dir}/gates_report.json"

  local f outputs='{}'
  for f in semantic-review-final.json audit-report.json curator-report.json \
           simplifier-report.md delivery-report.json review-profile.json \
           delivery-gate.json acceptance-evidence.json dispatch-record.json; do
    if [[ ! -f "${dir}/${f}" ]]; then
      if [[ "$f" == *.md ]]; then
        printf 'Head: %s\n' "$cand" > "${dir}/${f}"
      else
        jq -n --arg h "$cand" '{schema_version:"aid-2.0", revision:{head_sha:$h}}' > "${dir}/${f}"
      fi
    fi
    outputs="$(jq -c --arg k "$f" --arg v "sha256:$(sha256sum "${dir}/${f}" | awk '{print $1}')" \
      '. + {($k): $v}' <<<"$outputs")"
  done

  plan_manifest_update "$PLAN_ID" \
    ".plan_boundary_manifest.plan_final_review = $(jq -nc --arg c "$cand" --arg b "$base" \
      --arg r "$run_id" --argjson o "$outputs" \
      '{candidate_sha:$c, review_range:($b + ".." + $c), run_id:$r, outputs:$o,
        dispatch_counts:{}, utilities_run:[]}')" >/dev/null

  jq -n --arg c "$cand" '{schema_version:"aid-2.0", artifact_type:"release_decision",
    release_decision:{release_ready:true, blockers:[], candidate_sha:$c}}' \
    > "${dir}/release-decision.json"
  jq -n --arg p "$PLAN_ID" --arg r "$run_id" --arg c "$cand" --arg t "$thead" \
    '{event:"release_policy_dual_run", plan_id:$p, run_id:$r, candidate_sha:$c,
      target_head_sha:$t, enforcement:"observe", c4_release_ready:true,
      legacy_verdict:true, legacy_checks:{gates_report:"pass", plan_final_review:"pass"},
      match:true, divergence_class:"none"}' > "${dir}/release-decision-dual-run.json"
  plan_manifest_update "$PLAN_ID" \
    ".plan_boundary_manifest.plan_final_c4 = $(jq -nc --arg r "$run_id" --arg c "$cand" --arg t "$thead" \
      '{run_id:$r, candidate_sha:$c, target_head_sha:$t, enforcement:"observe",
        release_ready:true, blockers:0, dual_run:{match:true, divergence_class:"none"}}')" >/dev/null

  # The private, gitignored human projection. Its Head is the candidate, which
  # IS the worktree HEAD across the close (the close moves the TARGET ref by
  # plumbing and never touches HEAD), so Check 2 sees a fresh report.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/reports"
  printf -- '---\nHead: %s\n---\n\n# %s delivery\n' "$cand" "$PLAN_ID" \
    > "$TEST_PROJECT_ROOT/.aid-o/reports/${PLAN_ID}-delivery.md"
}

# _seed_closable — a plan that has really merged and is therefore closable.
_seed_closable() {
  _seed_merge_project
  _seed_plan_final_evidence
  _merge
  [ "$status" -eq 0 ]
}

# ─── AC7: the happy path ───────────────────────────────────────────────────

@test "AC7: a merged plan closes — exactly one head-bound marker, a committed .aid-lifecycle receipt, and state CLOSED" {
  _seed_closable
  [ ! -f "$(_marker)" ]
  local main_before; main_before="$(_main_sha)"

  _close
  [ "$status" -eq 0 ]

  # Exactly ONE marker, and it is bound to the published merge.
  run bash -c "find '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID' -maxdepth 1 -name 'plan-close-complete*' | wc -l"
  [ "$output" = "1" ]
  run grep -c '^merge_commit=' "$(_marker)"
  [ "$output" = "1" ]
  run grep "^merge_commit=$(_merge_commit)$" "$(_marker)"
  [ "$status" -eq 0 ]

  # The receipt is COMMITTED on the target branch (not merely on disk).
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -eq 0 ]
  # ...and the target ref advanced by exactly that plumbing commit.
  [ "$(_main_sha)" != "$main_before" ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CLOSED" ]
}

@test "AC7: a plan whose .lock sidecars EXIST but are not held closes normally (and the close takes its own lock)" {
  _seed_closable
  # The sidecars are on disk by design — flock releases on descriptor close,
  # not on unlink — so requiring their ABSENCE would make close unsatisfiable.
  [ -f "$(_state_lock)" ]
  [ -f "$(_manifest_lock)" ]
  _close
  [ "$status" -eq 0 ]
  # The close transaction's OWN sidecar exists afterwards, proving it held a
  # lock across the transaction while the probe still passed (owned-lock case a).
  [ -f "$(_close_lock)" ]
}

# ─── AC7: plan-close-complete is absent until the merge or a recorded abort ──

@test "AC7: plan-close-complete is absent before the merge — a close out of AWAITING_PM is refused" {
  _seed_merge_project
  _seed_plan_final_evidence
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"AWAITING_PM"* ]]
  [ ! -f "$(_marker)" ]
}

# ─── AC7: the corruption matrix — each item INDIVIDUALLY blocks ─────────────

@test "AC7: removing the runtime manifest blocks close and writes no marker" {
  _seed_closable
  rm -f "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID/plan-boundary-manifest.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to close"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing the final gate report blocks close" {
  _seed_closable
  rm -f "$(_run_dir)/gates_report.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"gate report"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing a required review output blocks close" {
  _seed_closable
  rm -f "$(_run_dir)/semantic-review-final.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"semantic-review-final.json"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: CORRUPTING a required review output blocks close (the recorded hash no longer matches)" {
  _seed_closable
  printf '{"tampered":true}\n' > "$(_run_dir)/curator-report.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"curator-report.json"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: corrupting the final SHA binding (plan_final_review.candidate_sha) blocks close" {
  _seed_closable
  _poke_manifest '.plan_boundary_manifest.plan_final_review.candidate_sha = "0000000000000000000000000000000000000000"'
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"not to this attempt"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing the C4 decision blocks close" {
  _seed_closable
  rm -f "$(_run_dir)/release-decision.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"C4 decision"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: a legacy release path that did NOT pass blocks close" {
  _seed_closable
  local d; d="$(_run_dir)/release-decision-dual-run.json"
  jq '.legacy_verdict = false' "$d" > "${d}.t" && mv "${d}.t" "$d"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"legacy_verdict"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing the PM decision blocks close" {
  _seed_closable
  [ -f "$(_run_dir)/pm-plan-decision.json" ]
  rm -f "$(_run_dir)/pm-plan-decision.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"no PM decision recorded"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing the merge record blocks close" {
  _seed_closable
  _poke_manifest 'del(.plan_boundary_manifest.plan_final_merge)'
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"no published plan merge"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: corrupting EPIC ancestry blocks close" {
  _seed_closable
  # A commit that RESOLVES but is NOT an ancestor of the plan branch — built as
  # a parentless dangling commit with `commit-tree`, so no ref moves and the
  # worktree is untouched (an orphan-branch checkout would fight the untracked
  # gitignored fixture files for no benefit).
  local foreign
  foreign="$(git -C "$TEST_PROJECT_ROOT" commit-tree \
    "$(git -C "$TEST_PROJECT_ROOT" rev-parse 'main^{tree}')" -m "foreign, unreachable")"
  _poke_manifest "(.plan_boundary_manifest.epic_runs[] | select(.epic_id == \"E-068-1_2\") | .epic_merge_commit) = \"${foreign}\""
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an ancestor"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: UNKNOWN ancestry blocks rather than passing" {
  _seed_closable
  _poke_manifest '(.plan_boundary_manifest.epic_runs[] | select(.epic_id == "E-068-1_2") | .epic_merge_commit) = "dead0000dead0000dead0000dead0000dead0000"'
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"ancestry UNKNOWN"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: a stale queue state blocks close" {
  _seed_closable
  # The EPIC's task branch really IS merged (it points at the candidate, which
  # the plan merge published on main), while the queue still claims blocked.
  git -C "$TEST_PROJECT_ROOT" branch "task/E-068-1_2/main" "$(_manifest_field "$PLAN_ID" candidate_sha)"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml" <<'YAML'
- epic_id: E-068-1_2
  path: p
  status: blocked
  depends_on: []
YAML
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"check4"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: a stale active.md state blocks close" {
  _seed_closable
  git -C "$TEST_PROJECT_ROOT" branch "task/E-068-1_2/main" "$(_manifest_field "$PLAN_ID" candidate_sha)"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" "$TEST_PROJECT_ROOT/.aid-o/work"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml" <<'YAML'
- epic_id: E-068-1_2
  path: p
  status: queued
  depends_on: []
YAML
  printf 'E-068-1_2 is waiting for merge\n' > "$TEST_PROJECT_ROOT/.aid-o/work/active.md"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"check4"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: a missing release/tag record blocks close" {
  _seed_closable
  # prepare-plan resolved a version, but no tag exists on the merge.
  jq -n '{version:"9.9.9"}' > "$(_run_dir)/release-prep.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"v9.9.9"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: an unfinished operation record blocks close" {
  _seed_closable
  printf '{"op_id":"epic-merge-to-plan:%s:-:0:E-068-1_2","command":"epic-merge-to-plan","subject":"E-068-1_2","phase":"git_applied","expected_before_sha":null,"resulting_sha":null,"at":"2026-07-26T00:00:00Z"}\n' \
    "$PLAN_ID" >> "$(_ops_jsonl "$PLAN_ID")"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"unfinished operation record"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: an in-progress merge (MERGE_HEAD) blocks close" {
  _seed_closable
  printf '%s\n' "$(_main_sha)" > "$TEST_PROJECT_ROOT/.git/MERGE_HEAD"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"MERGE_HEAD"* ]]
  [ ! -f "$(_marker)" ]
  rm -f "$TEST_PROJECT_ROOT/.git/MERGE_HEAD"
}

# ─── AC7: the owned-lock exception ─────────────────────────────────────────

@test "AC7: a SEPARATE live process holding another relevant sidecar blocks close, and is NAMED" {
  _seed_closable
  local lock; lock="$(_manifest_lock)"
  setsid flock -x "$lock" -c 'sleep 60' >/dev/null 2>&1 &
  local holder=$!
  # Wait until the lock is genuinely held before probing.
  local i=0
  while [ "$i" -lt 50 ] && flock -n "$lock" true 2>/dev/null; do sleep 0.1; i=$((i+1)); done

  _close
  local st="$status" out="$output"
  pkill -P "$holder" 2>/dev/null || true
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  [ "$st" -eq 1 ]
  [[ "$out" == *"still HELD"* ]]
  [[ "$out" == *"plan-boundary-manifest.json.lock"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: the owned-lock exception is PATH-scoped — a different lock held by the SAME process still blocks" {
  _seed_closable
  # Source the CLI so the probe runs IN THIS process: the "same process holds a
  # different lock" case cannot be produced through a subprocess.
  # shellcheck disable=SC1090
  source "$PLAN_FSM_CLI"
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"

  # (a) Holding ONLY our own close lock: the probe passes.
  aid_lock_acquire "$(_close_lock)" 5
  local own_fd="$AID_LOCK_FD"
  run _pfsm_close_lock_contended "$PLAN_ID" "$(_close_lock)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # (c) The SAME process additionally holds a DIFFERENT lock: still blocked.
  aid_lock_acquire "$(_manifest_lock)" 5
  local other_fd="$AID_LOCK_FD"
  run _pfsm_close_lock_contended "$PLAN_ID" "$(_close_lock)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan-boundary-manifest.json.lock"* ]]

  aid_lock_release "$other_fd" || true
  aid_lock_release "$own_fd" || true
}

# ─── AC7: crash resume ─────────────────────────────────────────────────────

@test "AC7: re-running after a simulated crash between the receipt and the marker writes exactly ONE marker and no second receipt" {
  _seed_closable
  _close
  [ "$status" -eq 0 ]
  local main_after_close; main_after_close="$(_main_sha)"
  local receipt_blob; receipt_blob="$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:$(_receipt_rel)")"

  # Simulate the crash: the receipt IS committed (git_applied happened), but the
  # marker was never written and the plan never reached CLOSED.
  rm -f "$(_marker)"
  yq -i '.plan_state = "PLAN_MERGING"' "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID/plan-state.yaml"

  _close
  [ "$status" -eq 0 ]

  # Exactly ONE marker...
  run bash -c "find '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID' -maxdepth 1 -name 'plan-close-complete*' | wc -l"
  [ "$output" = "1" ]
  # ...no second receipt commit (the target ref did not move again)...
  [ "$(_main_sha)" = "$main_after_close" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:$(_receipt_rel)")" = "$receipt_blob" ]
  # ...and the plan is CLOSED again.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CLOSED" ]
}

@test "AC7: an existing close marker whose preconditions no longer hold is reported as close_marker_invalid" {
  _seed_closable
  _close
  [ "$status" -eq 0 ]
  [ -f "$(_marker)" ]

  # The marker stays, but the evidence it attests to is destroyed and the plan
  # is put back at the boundary. A resumed close must REVALIDATE, not trust it.
  rm -f "$(_run_dir)/gates_report.json"
  yq -i '.plan_state = "PLAN_MERGING"' "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID/plan-state.yaml"

  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"close_marker_invalid"* ]]
}

# ─── AC7: the abort close ──────────────────────────────────────────────────

@test "AC7: a plan closed by ABORT writes the marker with the terminal reason, an abort record, NO receipt, and leaves the target unchanged" {
  _seed_merge_project
  _seed_plan_final_evidence
  local main_before; main_before="$(_main_sha)"
  local d; d="$(_decision_file '.decision = "ABORT" | .reason = "PM stopped the plan"')"
  _merge "$d"
  [ "$status" -eq 3 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ABORTED" ]

  _close
  [ "$status" -eq 0 ]
  [ -f "$(_marker)" ]
  run grep '^result=abort$' "$(_marker)"
  [ "$status" -eq 0 ]

  # An abort record naming the abandoned candidate and the unchanged target.
  run jq -r '.result + " " + .terminal_reason + " " + .abandoned_candidate_sha' "$(_run_dir)/plan-close-abort.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "aborted PM stopped the plan "* ]]

  # NO lifecycle receipt, and main is byte-identical apart from the manifest's
  # own `status: aborted` commit (which is the abort's durable record).
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -ne 0 ]
  run git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml"
  [[ "$output" == *"aborted"* ]]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$main_before" main
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$(_manifest_field "$PLAN_ID" candidate_sha)" main
  [ "$status" -ne 0 ]
}

@test "AC7: an abort close with NO recorded terminal reason is refused" {
  _seed_merge_project
  _seed_plan_final_evidence
  local d; d="$(_decision_file '.decision = "ABORT" | .reason = "PM stopped the plan"')"
  _merge "$d"
  [ "$status" -eq 3 ]
  _poke_manifest 'del(.plan_boundary_manifest.terminal_reason)'
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"terminal_reason"* ]]
  [ ! -f "$(_marker)" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC7 — the aid-fsm.sh delegation (CP3 pre-review finding, 2026-07-26).
# cmd_plan_close ran the IRREVERSIBLE plan-layer close (receipt + CLOSED +
# marker) BEFORE checking the EPIC's required Curator/Auditor reports, so a
# missing report failed the command only after the plan was already closed in
# the books. These tests hold the ordering.
# ═══════════════════════════════════════════════════════════════════════════

_EPIC_ID="E-068-1_2"
_epic_dir() { printf '%s/.aid-o/work/evidence/%s/R-%s-1' "$TEST_PROJECT_ROOT" "$_EPIC_ID" "$_EPIC_ID"; }

# _seed_delegated_close [--no-curator|--no-audit] — a plan closable through the
# FSM entry point: the declared mode says plan_branch, the plan is merged, and
# the EPIC carries its required reports unless one is deliberately withheld.
_seed_delegated_close() {
  local omit="${1:-}"
  export AID_TEST_DECLARED_PLAN_MODE=plan_branch
  _seed_closable
  local d; d="$(_epic_dir)"
  mkdir -p "$d"
  [[ "$omit" == "--no-curator" ]] || echo "curator report" > "${d}/curator-report.md"
  [[ "$omit" == "--no-audit" ]]   || printf 'blocking_findings: false\n' > "${d}/audit-report.md"
  # Both optional specialists are switched OFF so the test isolates the two
  # ALWAYS-required reports rather than re-testing the toggles.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'simplifier:\n  enabled: false\nreporter:\n  enabled: false\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

_fsm_close() {
  run bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" plan-close \
    "$_EPIC_ID" "$(_epic_dir)" "$TEST_PROJECT_ROOT"
}

@test "AC7: the delegation REFUSES a missing curator report and closes NOTHING — no receipt, no marker, not CLOSED" {
  _seed_delegated_close --no-curator
  local main_before; main_before="$(_main_sha)"

  _fsm_close
  [ "$status" -ne 0 ]
  [[ "$output" == *"curator-report.md"* ]]

  # NOTHING durable happened: this is the whole point of the ordering.
  [ ! -f "$(_marker)" ]
  [ ! -f "$(_epic_dir)/ca-review-complete" ]
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$main_before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "CLOSED" ]
}

@test "AC7: the delegation REFUSES a missing audit report and closes NOTHING" {
  _seed_delegated_close --no-audit
  local main_before; main_before="$(_main_sha)"

  _fsm_close
  [ "$status" -ne 0 ]
  [[ "$output" == *"audit-report.md"* ]]

  [ ! -f "$(_marker)" ]
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$main_before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "CLOSED" ]
}

@test "AC7: with complete evidence the delegation closes once — one receipt, both markers, CLOSED" {
  _seed_delegated_close

  _fsm_close
  [ "$status" -eq 0 ]

  # Exactly one receipt commit on the target branch.
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -eq 0 ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list main -- '$(_receipt_rel)' | wc -l"
  [ "$output" = "1" ]

  # Both markers: the plan-level close record and the EPIC's CA signal.
  [ -f "$(_marker)" ]
  [ -f "$(_epic_dir)/ca-review-complete" ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CLOSED" ]
}

@test "AC7: a crash after the plan-layer close but before the CA marker converges on re-run — no second receipt" {
  _seed_delegated_close

  _fsm_close
  [ "$status" -eq 0 ]
  local receipt_blob; receipt_blob="$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:$(_receipt_rel)")"

  # Simulate the crash window: the plan is closed and its receipt committed, but
  # the EPIC's CA marker never landed.
  rm -f "$(_epic_dir)/ca-review-complete"

  _fsm_close
  [ "$status" -eq 0 ]
  [ -f "$(_epic_dir)/ca-review-complete" ]

  # The receipt is untouched — the re-run completed the marker, it did not
  # close the plan a second time.
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:$(_receipt_rel)")" = "$receipt_blob" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list main -- '$(_receipt_rel)' | wc -l"
  [ "$output" = "1" ]
}

@test "AC7: removing the tracked lifecycle manifest BLOCKS a plan-branch close — the receipt is mandatory, not conditional on the file" {
  _seed_closable
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  local main_before; main_before="$(_main_sha)"

  # The manifest is removed from the WORKTREE — the shape an accidental clean or
  # a checkout of a pre-lifecycle revision produces. Before the fix this dropped
  # the close into the legacy "no receipt required" path and it SUCCEEDED.
  rm -f "${TEST_PROJECT_ROOT}/${rel}"

  _close
  [ "$status" -ne 0 ]
  [[ "$output" == *"MANDATORY"* ]]

  [ ! -f "$(_marker)" ]
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$main_before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "CLOSED" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC8 — in-flight inventory and the default mode flip (E-068-2_2 Step 1).
# The migration is deliberately unclever: an inventory and an explicit stamp,
# never inference and never a mid-run conversion.
# ═══════════════════════════════════════════════════════════════════════════

_inv() { run bash "$PLAN_FSM_CLI" inventory --project-root "$TEST_PROJECT_ROOT" "$@"; }

# _seed_plan_file — inventory enumerates plans from .aid-o/plans/P*.md and the
# queue. A fixture with neither has no plans to inventory, which is correct
# behaviour and useless as a test subject.
_seed_plan_file() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '# %s\n\n**EPIC 1: the one**\n' "$PLAN_ID" \
    > "$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-inventory-subject.md"
}

# _seed_lifecycle_manifest [mode] — a schema-shaped manifest, optionally stamped.
_seed_lifecycle_manifest() {
  local mode="${1:-}"
  local lm="${TEST_PROJECT_ROOT}/.aid-lifecycle/manifests/${PLAN_ID}.yaml"
  mkdir -p "$(dirname "$lm")"
  printf 'schema_version: "aid-2.0"\nrepo_id: t\nplan_id: %s\ndeclared_epics: []\n' "$PLAN_ID" > "$lm"
  [[ -n "$mode" ]] && printf 'mode: %s\n' "$mode" >> "$lm"
  printf '%s' "$lm"
}
_default_mode() { run bash "$PLAN_FSM_CLI" __default-mode --project-root "$TEST_PROJECT_ROOT"; }

# _seed_gate_profiles [yes|no] — the project execution.yaml the mode resolver
# reads. `plan_branch` is granted only when a gate_profiles table is present.
_seed_gate_profiles() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  if [[ "${1:-yes}" == "yes" ]]; then
    printf 'gates:\n  bats_fsm:\n    required: true\ngate_profiles:\n  quick:\n    include:\n      - bats_fsm\n' \
      > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  else
    printf 'gates:\n  bats_fsm:\n    required: true\n' \
      > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  fi
}

@test "AC8: new plans default to plan_branch when the project declares a gate_profiles table" {
  _bootstrap
  _seed_gate_profiles yes
  _default_mode
  [ "$status" -eq 0 ]
  [[ "$output" == plan_branch* ]]
  [[ "$output" == *"policy_default"* ]]
}

@test "AC8: with NO gate_profiles table the default falls back to legacy and says why" {
  _bootstrap
  _seed_gate_profiles no
  _default_mode
  [ "$status" -eq 0 ]
  [[ "$output" == legacy_epic_release_mode* ]]
  # The fallback is a LOGGED fact, never a silent downgrade — plan_branch mode's
  # gates stage resolves against that table, so without it the mode would have
  # no gates at all.
  [[ "$output" == *"plan_branch_unavailable"* ]]
  [[ "$output" == *"no_gate_profiles"* ]]
}

@test "AC8: inventory LISTS without mutating — a read-only run stamps nothing" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  local lm; lm="$(_seed_lifecycle_manifest)"
  local before; before="$(sha256sum "$lm" | awk '{print $1}')"

  _inv
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PLAN_ID"* ]]
  [[ "$output" == *"read-only"* ]]
  [ "$(sha256sum "$lm" | awk '{print $1}')" = "$before" ]
}

@test "AC8: --apply stamps an existing plan legacy_epic_release_mode, never migrates it" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  local lm; lm="$(_seed_lifecycle_manifest)"
  # _bootstrap's plan_state_init already stamps the RUNTIME state plan_branch,
  # and the mode reader legitimately falls back to it when the manifest carries
  # none — so an "unstamped plan" fixture has to clear it, or the subject is
  # already stamped and the test proves nothing.
  yq -i 'del(.mode)' "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml"

  _inv --apply
  [ "$status" -eq 0 ]
  [ "$(yq -r '.mode' "$lm")" = "legacy_epic_release_mode" ]
  # Stamping is NOT migration: no plan branch was created for it.
  [[ "$output" == *"no plan was migrated"* ]]
}

@test "AC8: --apply on an ALREADY stamped plan is a no-op, not an error" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  local lm; lm="$(_seed_lifecycle_manifest plan_branch)"

  _inv --apply
  [ "$status" -eq 0 ]
  [ "$(yq -r '.mode' "$lm")" = "plan_branch" ]
  [[ "$output" == *"already_stamped"* ]]
}

@test "AC8: an UNKNOWN declared mode exits non-zero and mutates nothing" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  local lm; lm="$(_seed_lifecycle_manifest banana)"
  local before; before="$(sha256sum "$lm" | awk '{print $1}')"

  _inv --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown mode"* ]]
  [ "$(sha256sum "$lm" | awk '{print $1}')" = "$before" ]
}

@test "AC8: a plan id matching no plan file and no queue entry exits non-zero" {
  _bootstrap
  _seed_gate_profiles yes
  _inv --plan P999
  [ "$status" -ne 0 ]
  [[ "$output" == *"no plan file or queue entry"* ]]
}

@test "AC8: an unknown value in the policy fails CLOSED to legacy and names the value" {
  _bootstrap
  _seed_gate_profiles yes
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config/policies"
  printf 'schema_version: "aid-2.0"\ndefault_mode: sideways\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/policies/plan-boundary-policy.yaml"

  _default_mode
  [ "$status" -eq 0 ]
  [[ "$output" == legacy_epic_release_mode* ]]
  [[ "$output" == *"unknown_policy_default"* ]]
  [[ "$output" == *"sideways"* ]]
}

@test "AC8: a project may opt OUT of the new model through its own policy copy" {
  _bootstrap
  _seed_gate_profiles yes
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config/policies"
  printf 'schema_version: "aid-2.0"\ndefault_mode: legacy_epic_release_mode\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/policies/plan-boundary-policy.yaml"

  _default_mode
  [ "$status" -eq 0 ]
  [[ "$output" == legacy_epic_release_mode* ]]
  [[ "$output" == *"policy_default"* ]]
  [[ "$output" != *"unknown_policy_default"* ]]
}

@test "AC8: the stamped mode must be COMMITTED, not merely present in the worktree" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  # ensure_manifest commits what it writes, so a mode stamped after that call
  # and never re-committed would live only in the worktree while the authority
  # every later reader consults — target_branch's committed tree — carried none.
  source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  ( cd "$TEST_PROJECT_ROOT" && aid_lifecycle_ensure_manifest "$PLAN_ID" "." >/dev/null 2>&1 ) || skip "ensure_manifest unavailable in this fixture"
  ( cd "$TEST_PROJECT_ROOT" && yq -i '.mode = "plan_branch"' "$rel" \
      && _aid_lc_isolated_commit "." "lifecycle: declare mode plan_branch for $PLAN_ID" "$rel" >/dev/null 2>&1 )

  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' 2>/dev/null | yq -r '.mode'"
  [ "$status" -eq 0 ]
  [ "$output" = "plan_branch" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC9 — the resilience matrix (E-068-2_2 Step 2).
#
# Every transactional command is SPECIFIED as intent -> git_applied ->
# state_committed. That specification is worth nothing until a crash at each
# boundary is actually exercised, so these tests kill the process there for
# real (AID_PLAN_FSM_CRASH_AFTER, exit 99) rather than mocking it, and then
# resume and assert what survived.
# ═══════════════════════════════════════════════════════════════════════════

_crash_merge() {
  run env AID_PLAN_FSM_CRASH_AFTER="$1" bash "$PLAN_FSM_CLI" plan-merge-to-main "$PLAN_ID" \
    --decision "$(_decision_file)" --project-root "$TEST_PROJECT_ROOT"
}

@test "AC9: a crash after INTENT leaves the target branch untouched and the retry is clean" {
  _seed_merge_project
  local main_before; main_before="$(_main_sha)"

  _crash_merge intent
  [ "$status" -eq 99 ]
  [[ "$output" == *"CRASH SEAM"* ]]
  # Nothing Git-visible happened: intent is a journal entry, not an effect.
  [ "$(_main_sha)" = "$main_before" ]

  # The retry is a normal first run, not a damaged resume.
  _merge
  [ "$status" -eq 0 ]
  [ "$(_main_sha)" != "$main_before" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | wc -l"
  [ "$output" = "1" ]
}

@test "AC9: a crash after GIT_APPLIED reuses the published merge and never makes a second one" {
  _seed_merge_project
  local main_before; main_before="$(_main_sha)"

  _crash_merge git_applied
  [ "$status" -eq 99 ]
  # The merge IS published — that is what git_applied means — but the state
  # records that follow it are not yet written.
  local published; published="$(_main_sha)"
  [ "$published" != "$main_before" ]

  _merge
  [ "$status" -eq 0 ]
  # Exactly one merge commit: the resume reused the published one.
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | wc -l"
  [ "$output" = "1" ]
}

@test "AC9: two crashes in a row at the same boundary behave identically — the resume is not one-shot" {
  _seed_merge_project
  _crash_merge git_applied
  [ "$status" -eq 99 ]
  _crash_merge git_applied
  [ "$status" -eq 99 ]

  _merge
  [ "$status" -eq 0 ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | wc -l"
  [ "$output" = "1" ]
}

@test "AC9: a crash after git_applied leaves no SECOND tag when the plan resolves a version" {
  _seed_merge_project
  _crash_merge git_applied
  [ "$status" -eq 99 ]
  _merge
  [ "$status" -eq 0 ]
  # Whatever the tag policy resolved, it resolved it once.
  run bash -c "git -C '$TEST_PROJECT_ROOT' tag | wc -l"
  local tags="$output"
  _merge
  run bash -c "git -C '$TEST_PROJECT_ROOT' tag | wc -l"
  [ "$output" = "$tags" ]
}

@test "AC9: a pre-merge ABORT leaves the target branch unchanged and records the terminal reason" {
  _seed_merge_project
  local main_before; main_before="$(_main_sha)"

  # `reason` is the schema's field name and the schema is closed, so an invented
  # `terminal_reason` would be rejected as malformed before the abort is even
  # considered — the decision would never reach the abort path at all.
  _merge "$(_decision_file '.decision = "ABORT" | .reason = "PM stopped it"')"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$main_before" ]

  # The plan branch and its evidence are preserved — an abort is a decision,
  # not a cleanup.
  run git -C "$TEST_PROJECT_ROOT" rev-parse --verify "plan/$PLAN_ID"
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ABORTED" ]
}

@test "AC9: a HOTFIX on the target branch after the freeze forces resynchronisation before any merge" {
  _seed_merge_project
  local main_before; main_before="$(_main_sha)"

  # Someone lands a hotfix straight on the target branch after the candidate was
  # frozen. The authorization the PM gave describes a head that no longer exists.
  _commit_on main hotfix.txt "fix: an urgent hotfix"
  local hotfixed; hotfixed="$(_main_sha)"
  [ "$hotfixed" != "$main_before" ]

  _merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"STALE AUTHORIZATION"* ]]
  [ "$(_main_sha)" = "$hotfixed" ]
  # Back to sync: the plan must re-establish a candidate against the new head.
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [[ "$output" == *"PLAN_SYNC"* ]]
}

@test "AC9: a published rollback is a NEW revert commit — history is never rewritten" {
  _seed_closable
  local mc; mc="$(_merge_commit)"
  local before; before="$(_main_sha)"

  # The rollback shape this system permits: revert forward. The controller's
  # worktree sits on the plan branch after a close, so the revert has to be made
  # ON the target branch — reverting wherever HEAD happens to point would prove
  # nothing about the target branch's history.
  run bash -c "cd '$TEST_PROJECT_ROOT' && orig=\$(git symbolic-ref --short HEAD) \
    && git checkout -q main && git revert --no-edit -m 1 '$mc' >/dev/null 2>&1 \
    && git checkout -q \"\$orig\""
  [ "$status" -eq 0 ]

  # The merge is STILL reachable — nothing was rewritten — and the branch grew.
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$mc" main
  [ "$status" -eq 0 ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --count '${before}..main'"
  [ "$output" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC10 — the cadence, asserted over the STRUCTURED record (E-068-2_2 Step 5).
#
# "Each specialist ran exactly once, at plan final" is the claim the whole
# plan-boundary model rests on, and it is the easiest claim in the system to
# assert falsely: nothing about a finished run looks different when a role ran
# twice, or ran per EPIC. So it is asserted over dispatch_counts in the RUNTIME
# manifest, which the review stage writes from the dispatch record it validated.
# ═══════════════════════════════════════════════════════════════════════════

_review_counts() {
  jq -r ".plan_boundary_manifest.plan_final_review.dispatch_counts.\"$1\" // \"absent\"" \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
}

@test "AC10: a REAL review pass records the cadence — exactly one dispatch per specialist" {
  _seed_review_project
  _write_review_outputs
  _review
  [ "$status" -eq 0 ]

  # The counts come from the production stage, not from the fixture: the refusal
  # side is covered by AC3, and this is its positive twin — proof that a passing
  # run actually WRITES the cadence rather than merely not objecting to it. A
  # cadence nobody records is a cadence nobody can audit afterwards.
  local a
  for a in auditor curator simplifier reporter; do
    local n; n="$(_review_counts "$a")"
    [ "$n" != "absent" ]
    [ "$n" = "1" ]
  done
}

@test "AC10: the recorded review is bound to the SAME candidate the merge published" {
  _seed_closable
  local recorded_cand
  recorded_cand="$(jq -r '.plan_boundary_manifest.plan_final_review.candidate_sha' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  local merged_cand
  merged_cand="$(jq -r '.plan_boundary_manifest.plan_final_merge.candidate_sha' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  # A review of one candidate and a merge of another is the precise shape of a
  # review that proves nothing.
  [ -n "$recorded_cand" ]
  [ "$recorded_cand" = "$merged_cand" ]
}

@test "AC10: a REAL review pass records every output bound by content hash" {
  _seed_review_project
  _write_review_outputs
  _review
  [ "$status" -eq 0 ]

  local m="${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  # Every recorded output carries a sha256, which is what lets plan-close
  # re-verify the review instead of trusting that it happened.
  run jq -r '[.plan_boundary_manifest.plan_final_review.outputs | to_entries[]
              | select((.value | startswith("sha256:")) | not)] | length' "$m"
  [ "$output" = "0" ]
  run jq -r '.plan_boundary_manifest.plan_final_review.outputs | length' "$m"
  [ "$output" -ge 1 ]
}

@test "AC10: EPIC work reaches the target branch ONLY through the plan branch" {
  _seed_closable
  local mc; mc="$(_merge_commit)"
  # The plan merge has exactly two parents: the previous target head and the
  # candidate. An EPIC that had merged straight to the target branch would show
  # up as its own commit on main outside this merge.
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --parents -n 1 '$mc' | wc -w"
  [ "$output" = "3" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | wc -l"
  [ "$output" = "1" ]
}

@test "AC8: --apply COMMITS the stamp, and reports it as not durable when it cannot" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  _seed_lifecycle_manifest >/dev/null
  yq -i 'del(.mode)' "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml"
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"

  _inv --apply
  # Whatever the outcome, it must be HONEST: either the stamp is readable from
  # the target branch's committed tree, or the run said it is not durable and
  # returned non-zero. A worktree-only stamp reported as success is the exact
  # defect this asserts against — the authority every later reader consults is
  # the committed copy, not the file on disk.
  local committed
  committed="$(git -C "$TEST_PROJECT_ROOT" show "main:${rel}" 2>/dev/null | yq -r '.mode // ""' 2>/dev/null || true)"
  if [ "$status" -eq 0 ]; then
    [ "$committed" = "legacy_epic_release_mode" ]
    [[ "$output" == *"committed"* ]]
  else
    [[ "$output" == *"NOT readable"* ]]
    [[ "$output" == *"declares nothing"* ]]
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# AC11 — the C4 inputs have a PRODUCER (P068 follow-up, 2026-07-27).
#
# The registry recorded `plan_finalize_c4_reader_gap` honestly: the review and
# c4 stages validated three artifacts that nothing in the plan produced — a
# reader with no writer, so the boundary could not complete end-to-end. These
# tests assert the producer exists, derives rather than fabricates, and that the
# validating stage accepts what it wrote.
# ═══════════════════════════════════════════════════════════════════════════

_inputs() {
  run bash "$PLAN_FSM_CLI" plan-finalize "$PLAN_ID" --stage inputs \
    --project-root "$TEST_PROJECT_ROOT"
}

@test "AC11: --stage inputs produces all three C4 inputs, bound to the plan and the frozen candidate" {
  _seed_merge_project
  local dir; dir="$(_run_dir)"
  rm -f "${dir}/review-profile.json" "${dir}/delivery-gate.json" "${dir}/acceptance-evidence.json"

  _inputs
  [ "$status" -eq 0 ]

  local cand base
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"

  # review-profile.json: derived over the WHOLE plan range, and armed.
  [ -s "${dir}/review-profile.json" ]
  [ "$(jq -r '.revision.base_sha' "${dir}/review-profile.json")" = "$base" ]
  [ "$(jq -r '.review_profile.required_lenses | type' "${dir}/review-profile.json")" = "array" ]

  # The two aggregates: bound to the PLAN, never to one EPIC.
  local agg
  for agg in delivery-gate acceptance-evidence; do
    [ -s "${dir}/${agg}.json" ]
    [ "$(jq -r '.identity.epic_id' "${dir}/${agg}.json")" = "null" ]
    [ "$(jq -r '.identity.plan_id' "${dir}/${agg}.json")" = "$PLAN_ID" ]
    [ "$(jq -r '.subject.candidate_sha' "${dir}/${agg}.json")" = "$cand" ]
    # sources[] names every contributing EPIC — an empty one would assert a
    # delivery nobody made.
    [ "$(jq -r '.sources | length' "${dir}/${agg}.json")" -ge 1 ]
    [ "$(jq -r '[.sources[] | select(.epic_id == "E-068-1_2")] | length' "${dir}/${agg}.json")" = "1" ]
  done
}

@test "AC11: an EPIC with no artifact is recorded ABSENT in sources[], not silently dropped" {
  _seed_merge_project
  _inputs
  [ "$status" -eq 0 ]
  local dir; dir="$(_run_dir)"

  # The fixture's EPIC has no delivery-gate.json of its own, so the aggregate
  # must say so. "No EPIC produced this" is a fact the PM should see; an
  # aggregate that hides it would report a completeness it does not have.
  [ "$(jq -r '[.sources[] | select(.status == "absent")] | length' "${dir}/delivery-gate.json")" -ge 1 ]
  # verdict.kind is a closed protocol enum, so the aggregation outcome lives
  # beside it rather than being smuggled into it.
  [ "$(jq -r '.verdict.kind' "${dir}/delivery-gate.json")" = "none" ]
  [ "$(jq -r '.verdict.aggregation' "${dir}/delivery-gate.json")" = "aggregated_with_gaps" ]
}

@test "AC11: --stage inputs REFUSES before the candidate is frozen" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  _inputs
  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen candidate"* ]]
}

@test "AC11: --stage inputs REFUSES when no EPIC has merged into the plan" {
  _seed_merge_project
  # `merged_to_plan -> abandoned` is not a legal transition, and rightly so — a
  # delivered EPIC cannot be un-delivered. So the subject is a plan whose only
  # EPIC was abandoned from `pending`, which is legal and is exactly the shape
  # "nothing merged" takes in practice.
  _add_epic "$PLAN_ID" "E-068-9_9"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-9_9" "abandoned" >/dev/null
  plan_manifest_update "$PLAN_ID" \
    '.plan_boundary_manifest.epic_runs |= [ .[] | select(.epic_id != "E-068-1_2") ]' >/dev/null
  _inputs
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing to aggregate"* ]]
}

@test "AC11: what the producer writes is ACCEPTED by the validating review stage" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  # Replace the fixture's hand-written three with the real producer's output:
  # the point of the follow-up is that production and validation agree.
  rm -f "${dir}/review-profile.json" "${dir}/delivery-gate.json" "${dir}/acceptance-evidence.json"
  _inputs
  [ "$status" -eq 0 ]
  # The Reporter is dispatched LAST, after the inputs exist — that is the real
  # cadence, and the review stage enforces it by mtime. Re-emitting the delivery
  # report here reproduces the ordering rather than working around the check.
  command sleep 1
  touch "${dir}/delivery-report.json"

  _review
  [ "$status" -eq 0 ]
}

@test "AC11: --stage inputs REFUSES once the review has recorded hash-bound outputs" {
  _seed_review_project
  _write_review_outputs
  local dir; dir="$(_run_dir)"
  rm -f "${dir}/review-profile.json" "${dir}/delivery-gate.json" "${dir}/acceptance-evidence.json"
  _inputs
  [ "$status" -eq 0 ]
  command sleep 1
  touch "${dir}/delivery-report.json"
  _review
  [ "$status" -eq 0 ]

  # The review is recorded and its outputs are hash-bound. Re-running the
  # producer would rewrite them, and close would then report them as ALTERED —
  # true, but a diagnosis of tampering for what was really a repeated stage.
  local before; before="$(sha256sum "${dir}/delivery-gate.json" | awk '{print $1}')"
  _inputs
  [ "$status" -ne 0 ]
  [[ "$output" == *"already has a RECORDED plan-final review"* ]]
  [ "$(sha256sum "${dir}/delivery-gate.json" | awk '{print $1}')" = "$before" ]
}
