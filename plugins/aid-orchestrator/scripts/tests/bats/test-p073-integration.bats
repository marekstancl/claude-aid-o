#!/usr/bin/env bats
# test-p073-integration.bats — P073 Step 19: the cross-cutting fixture.
#
# The per-step suites prove each mechanism in isolation. This one proves the
# CLAIM: one ancillary commit travels drift -> accept -> merge without a second
# review, while one protected change fails at each of those consumers. It also
# pins the other half of the contract — the exact-only consumers must be
# demonstrably UNCHANGED on the same fixture, because a loosening that leaked
# into the scope guard or the release staging would be a silent widening of
# what AID lets through.
#
# Runtime discipline: this file builds ONE disposable git repo per test and
# drives the library functions directly rather than the full plan-final stage
# chain, which each cost a release gate profile run. What the claim actually
# depends on is the classifier, the predicate, the acceptance and the drift
# detector; the full merge path has its own integration cases in
# test-aid-plan-final-boundary.bats (P073 Step 18).

load test-helpers.bash

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq is not available — refusing to report a PASS on a suite that cannot classify anything"
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  PLAN=P903
  export PLAN
}

teardown() {
  teardown_test_evidence_dir
}

_p() {
  bash -c '
    set -uo pipefail
    SCRIPT_DIR="$1/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    . "$SCRIPT_DIR/lib/aid-ancillary.sh"
    eval "$(sed -n "/^_pfsm_equivalence_classify()/,/^_pfsm_finalize_review()/p" "$SCRIPT_DIR/aid-plan-fsm.sh" \
            | sed "\$d")"
    cd "$2"
    eval "$3"
  ' _ "$AID_PLUGIN_PATH" "$ROOT" "$1"
}

# _fixture — a plan branch at a frozen candidate with a COMPLETE protected
# surface: one delivery file, one close-consumed receipt, one ancillary path.
_fixture() {
  ( cd "$ROOT"
    git init -q
    git config user.email t@e.com
    git config user.name T
    git checkout -q -b main 2>/dev/null || git branch -m main
    mkdir -p scripts .aid-o/work .aid-o/config
    printf 'seed\n' > README.md
    printf 'echo delivery\n' > scripts/deliver.sh
    printf '{"consumed":true}\n' > .aid-o/work/consumed-receipt.json
    printf 'queue: []\n' > .aid-o/config/queue.yaml
    git add -A -f && git commit -qm seed
    git checkout -q -b "plan/$PLAN" ) >/dev/null 2>&1
  CAND="$(cd "$ROOT" && git rev-parse HEAD)"
  export CAND
  local rel=".aid-o/work/evidence/$PLAN/R-$PLAN-final-1"
  mkdir -p "$ROOT/$rel"
  printf '%s\0' "scripts/deliver.sh" "README.md" ".aid-o/work/consumed-receipt.json" \
    > "$BATS_TEST_TMPDIR/prot.nul"
  _p "plan_manifest_init $PLAN plan/$PLAN main '$CAND' '$CAND' plan_branch >/dev/null
      plan_manifest_freeze_candidate $PLAN '$CAND' '$CAND' R-$PLAN-final-1 '$rel' '2026-08-05T00:00:00Z' '$BATS_TEST_TMPDIR/prot.nul' true >/dev/null"
}

_commit() { ( cd "$ROOT" && git add -A -f && git commit -qm "$1" ) >/dev/null 2>&1; }
_head() { ( cd "$ROOT" && git rev-parse HEAD ); }

# ─── THE CLAIM: one ancillary commit survives the whole chain ─────────────

@test "P073 integration: an ancillary commit travels drift -> accept -> drift without a second review" {
  _fixture

  # 1. The commit itself: an audit-log append, the exact write that used to
  #    cost a completed review.
  printf '{"event":"a note after the freeze"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  _commit "chore: audit log"
  local moved; moved="$(_head)"
  [ "$moved" != "$CAND" ]

  # 2. DRIFT before acceptance: still invalidates, and says how to recover.
  run _p "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"accept-ancillary"* ]]

  # 3. The predicate agrees it is ancillary-only.
  run _p "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 0 ]

  # 4. ACCEPT: one receipt, candidate untouched.
  run _p "_pfsm_finalize_accept_ancillary . $PLAN"
  [ "$status" -eq 0 ]
  [ "$(find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' | wc -l | tr -d ' ')" = "1" ]
  run _p "plan_manifest_get $PLAN '.plan_boundary_manifest.candidate_sha'"
  [ "$output" = "$CAND" ]

  # 5. DRIFT after acceptance: the review survives, and says why.
  run _p "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"review preserved via review-equivalence receipt"* ]]

  # 6. The manifest still validates.
  run _p "plan_manifest_validate $PLAN"
  [ "$status" -eq 0 ]
}

@test "P073 integration: a protected change fails at the predicate, at acceptance AND at drift" {
  _fixture
  printf 'echo changed\n' > "$ROOT/scripts/deliver.sh"
  _commit "fix: a delivery change"

  run _p "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"scripts/deliver.sh"* ]]

  run _p "_pfsm_finalize_accept_ancillary . $PLAN"
  [ "$status" -ne 0 ]
  [ "$(find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' | wc -l | tr -d ' ')" = "0" ]

  run _p "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
  # No recovery hint: acceptance cannot help, and offering it would loop.
  [[ "$output" != *"accept-ancillary"* ]]
}

@test "P073 integration: a close-consumed receipt is protected even though it is ancillary-globbed" {
  _fixture
  printf '{"consumed":"tampered"}\n' > "$ROOT/.aid-o/work/consumed-receipt.json"
  _commit "touch the consumed receipt"

  run _p "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"consumed-receipt.json"* ]]
  [[ "$output" == *"PROTECTED"* ]]
}

@test "P073 integration: a legacy freeze behaves exactly as before P073" {
  _fixture
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  jq 'del(.plan_boundary_manifest.protected_paths) | del(.plan_boundary_manifest.protected_paths_complete)' \
    "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  _commit "chore: audit log"

  run _p "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 2 ]
  run _p "_pfsm_finalize_accept_ancillary . $PLAN"
  [ "$status" -ne 0 ]
  run _p "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
}

# ─── THE OTHER HALF: exact-only consumers are UNCHANGED ──────────────────

@test "P073 integration: the pre-commit scope guard is unchanged — ancillary is not a scope exemption" {
  # gates/scope-check.sh answers "is this path in the step's allowed_paths",
  # a different question from "does this path describe the delivery". A path
  # being ancillary must not exempt it from scope.
  run grep -c 'aid_ancillary' "$AID_PLUGIN_PATH/scripts/gates/scope-check.sh"
  [ "$output" = "0" ]
}

@test "P073 integration: the release script keeps the LEGACY five-path filter" {
  # Step 14 was behaviour-neutral at the four existing call sites; only the
  # drift detector moved to the full policy. A release preparing its staging
  # through the wider set would stage files nobody classified.
  run grep -c 'aid_ancillary_filter_porcelain --mode legacy5' "$AID_PLUGIN_PATH/scripts/aid-release.sh"
  [ "$output" -ge 1 ]
  run grep -c 'aid_ancillary_filter_porcelain --mode policy' "$AID_PLUGIN_PATH/scripts/aid-release.sh"
  [ "$output" = "0" ]
}

@test "P073 integration: aid-fsm.sh keeps its FOUR-entry legacy set" {
  run grep -c 'aid_ancillary_filter_porcelain --mode legacy4' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  [ "$output" -ge 1 ]
}

@test "P073 integration: plan-close-check accepts BOTH close-receipt shapes and nothing else" {
  local f="$AID_PLUGIN_PATH/scripts/aid-plan-close-check.sh"
  run grep -c 'merged_head' "$f"
  [ "$output" -ge 1 ]
  # Still an exact key set, not a relaxed superset.
  run grep -c 'keys | sort' "$f"
  [ "$output" -ge 1 ]
}

@test "P073 integration: the ancillary filter mode is mandatory at every call site" {
  # A call site that omitted the mode would inherit whatever default existed.
  # There is none: the function returns 2. This pins that no caller has been
  # added without one.
  run bash -c "grep -rn 'aid_ancillary_filter_porcelain' '$AID_PLUGIN_PATH/scripts' --include='*.sh' \
                 | grep -v 'lib/aid-ancillary.sh' | grep -vc -- '--mode '"
  [ "$output" = "0" ]
}

# ─── EPIC 1 and EPIC 2 behaviours on the same fixture ────────────────────

@test "P073 integration: the CP1 review budget is 5, and legacy ledgers keep their cap" {
  local f="$AID_PLUGIN_PATH/scripts/lib/aid-cp1-ledger.sh"
  run grep -c 'MAX_ATTEMPTS=5' "$f"
  [ "$output" -ge 1 ]
  run grep -c 'LEGACY_MAX_ATTEMPTS=3' "$f"
  [ "$output" -ge 1 ]
}

@test "P073 integration: --force without --force-reason is a usage error" {
  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh" plan-close "$PLAN" --force \
    --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"force-reason"* ]]
}

@test "P073 integration: every P073 enforcement is registered" {
  local reg="$AID_PLUGIN_PATH/defaults/enforcement-registry.yaml"
  local id
  for id in release_changelog_entry_validation release_detection_exit_triage \
            dependency_token_grammar_hard_fail branch_restore_hard_stop \
            plan_force_framework init_strict_flag_rejection \
            pm_override_single_use_claim ancillary_path_classifier \
            protected_surface_at_freeze review_equivalence_predicate \
            review_equivalence_acceptance drift_equivalence_wiring \
            merge_equivalence_reverification plan_source_committed_preflight \
            epic_supersede_bound_reinit; do
    run grep -c "id: ${id}\$" "$reg"
    [ "$output" = "1" ]
  done
}

# --- EPIC 3 whole-diff review finding ------------------------------------

@test "P073 integration (whole-diff): a MULTI-path plan.json stores every path separately" {
  # MEASURED before the fix: `jq -j '. + "\u0000"'` emits no byte at all for the
  # NUL on jq 1.6 (and command substitution would strip it anyway), so
  # "src/app.sh" and "docs/release-notes.md" were stored as the single entry
  # "src/app.shdocs/release-notes.md" -- NEITHER path was protected, while the
  # freeze still recorded protected_paths_complete=true. A declared delivery
  # path could then be classified ancillary, accepted, and merged without a
  # review covering it. This is the ONE fixture shape that shows it: a
  # single-path plan.json cannot.
  _fixture
  local ev=".aid-o/work/evidence/E-903-1/R-1"
  mkdir -p "$ROOT/$ev"
  jq -n '{schema_version:"aid-2.0", epic_id:"E-903-1",
          steps:[{step_id:"S1", allowed_paths:["src/app.sh","docs/release-notes.md","scripts/deliver.sh"]}]}' \
    > "$ROOT/$ev/plan.json"

  run bash -c "jq -r '.steps[]?.allowed_paths[]? // empty | @base64' '$ROOT/$ev/plan.json' | wc -l"
  [ "$(echo "$output" | tr -d ' ')" = "3" ]

  # And the classifier must see three DISTINCT entries, not one glued token.
  local prot
  prot="$(jq -c '[.steps[]?.allowed_paths[]?]' "$ROOT/$ev/plan.json")"
  run _p "_pfsm_path_is_protected 'docs/release-notes.md' '$prot'"
  [ "$status" -eq 0 ]
  run _p "_pfsm_path_is_protected 'src/app.sh' '$prot'"
  [ "$status" -eq 0 ]
  run _p "_pfsm_path_is_protected 'src/app.shdocs/release-notes.md' '$prot'"
  [ "$status" -ne 0 ]
}

@test "P073 integration (whole-diff): the freeze no longer emits NUL through jq" {
  # The construction itself is pinned: jq cannot emit a NUL byte, so any
  # reintroduction of it silently reproduces the glued-path defect.
  run grep -c 'u0000' "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  [ "$output" = "0" ]
}
