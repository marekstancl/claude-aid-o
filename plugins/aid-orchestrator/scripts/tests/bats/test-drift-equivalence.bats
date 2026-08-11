#!/usr/bin/env bats
# aid-tier: t2
# test-drift-equivalence.bats — P073 Step 17: equivalence wired into the
# candidate-drift detector, and through it into review, C4 and summary.
#
# `_pfsm_review_candidate_drift` is the single choke point all three stages
# call. Before this step it invalidated on ANY head movement and on any tracked
# dirt outside five hard-coded runtime paths. After it:
#   - the head may sit at the manifest's `accepted_head` (a recorded, receipted
#     acceptance) as well as at the candidate;
#   - dirt is classified through the full ancillary policy, PROTECTED FIRST;
#   - everything else invalidates exactly as before, and a legacy freeze
#     (no protected set) behaves byte-identically to pre-P073.
#
# The recovery hint is part of the contract: the operator must learn about
# `--stage accept-ancillary` at the moment of the failure, not after losing the
# review.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PFSM
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  PLAN=P901
  export PLAN
}

teardown() {
  teardown_test_evidence_dir
}

# _drift <body> — run <body> with the plan-FSM helpers sourced, inside $ROOT.
_drift() {
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

# _seed [--legacy] — a repo with a plan branch and a frozen candidate.
# `--legacy` freezes WITHOUT a protected set, i.e. a pre-P073 manifest.
_seed() {
  local legacy=""
  [[ "${1:-}" == "--legacy" ]] && legacy=1
  ( cd "$ROOT"
    git init -q
    git config user.email t@e.com
    git config user.name T
    git checkout -q -b main 2>/dev/null || git branch -m main
    mkdir -p scripts .aid-o/work
    printf 'seed\n' > README.md
    printf 'echo a\n' > scripts/a.sh
    printf 'r\n' > .aid-o/work/consumed-receipt.json
    git add -A -f && git commit -qm seed
    git checkout -q -b "plan/$PLAN" ) >/dev/null 2>&1
  CAND="$(cd "$ROOT" && git rev-parse HEAD)"
  export CAND
  local rel=".aid-o/work/evidence/$PLAN/R-$PLAN-final-1"
  mkdir -p "$ROOT/$rel"
  printf '%s\0' "scripts/a.sh" ".aid-o/work/consumed-receipt.json" > "$BATS_TEST_TMPDIR/prot.nul"
  _drift "plan_manifest_init $PLAN plan/$PLAN main '$CAND' '$CAND' plan_branch >/dev/null
          plan_manifest_freeze_candidate $PLAN '$CAND' '$CAND' R-$PLAN-final-1 '$rel' '2026-08-05T00:00:00Z' '$BATS_TEST_TMPDIR/prot.nul' true >/dev/null"
  if [[ -n "$legacy" ]]; then
    local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
    jq 'del(.plan_boundary_manifest.protected_paths) | del(.plan_boundary_manifest.protected_paths_complete)' \
      "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  fi
}

_commit() { ( cd "$ROOT" && git add -A -f && git commit -qm "$1" ) >/dev/null 2>&1; }
_head() { ( cd "$ROOT" && git rev-parse HEAD ); }

# _ancillary_commit — move the head by one ancillary-only commit.
_ancillary_commit() {
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  _commit "ancillary: audit log"
}

_accept() { _drift "_pfsm_finalize_accept_ancillary . $PLAN"; }

# ─── the head branch ──────────────────────────────────────────────────────

@test "P073 Step 17: an unmoved head still passes the detector" {
  _seed
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -eq 0 ]
}

@test "P073 Step 17: a head at the ACCEPTED head passes, naming the receipt" {
  _seed
  _ancillary_commit
  _accept >/dev/null 2>&1
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"review-equivalence receipt"* ]]
}

@test "P073 Step 17: a head moved WITHOUT acceptance still invalidates" {
  _seed
  _ancillary_commit
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"moved from the frozen candidate"* ]]
}

@test "P073 Step 17: an ancillary-shaped failure carries the accept-ancillary hint" {
  _seed
  _ancillary_commit
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"accept-ancillary"* ]]
}

@test "P073 Step 17: a DELIVERY-shaped failure carries NO accept-ancillary hint" {
  # The hint must not be offered where it cannot work — a protected-surface
  # change is a fix, and suggesting acceptance would send the operator into a
  # refusal loop.
  _seed
  printf 'echo changed\n' > "$ROOT/scripts/a.sh"
  _commit "fix: a delivery file"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
  [[ "$output" != *"accept-ancillary"* ]]
}

@test "P073 Step 17: the head one commit PAST the accepted head invalidates" {
  _seed
  _ancillary_commit
  _accept >/dev/null 2>&1
  printf '{"event":"y"}\n' >> "$ROOT/.aid-o/work/audit-log.jsonl"
  _commit "a further ancillary commit, unaccepted"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"accept-ancillary"* ]]
}

@test "P073 Step 17: an accepted head whose RECEIPT is gone invalidates" {
  # The manifest field alone is not proof. A binding whose receipt vanished
  # must not keep a review alive.
  _seed
  _ancillary_commit
  _accept >/dev/null 2>&1
  find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' -delete
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
}

# ─── the dirty branch ─────────────────────────────────────────────────────

@test "P073 Step 17: dirt on a POLICY-ancillary path no longer invalidates" {
  # `.aid-o/work/**` is ancillary policy but was NOT one of the five legacy
  # runtime paths, so this used to throw the review away.
  _seed
  printf 'note\n' > "$ROOT/.aid-o/work/notes.md"
  ( cd "$ROOT" && git add -f .aid-o/work/notes.md && git commit -qm notes ) >/dev/null 2>&1
  _accept >/dev/null 2>&1 || true
  printf 'note2\n' > "$ROOT/.aid-o/work/notes.md"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$(_head)'"
  [ "$status" -eq 0 ]
}

@test "P073 Step 17: dirt on a PROTECTED path invalidates even though it is ancillary-globbed" {
  _seed
  printf 'tampered\n' > "$ROOT/.aid-o/work/consumed-receipt.json"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"consumed-receipt.json"* ]]
}

@test "P073 Step 17: dirt on a plain delivery path invalidates" {
  _seed
  printf 'echo dirty\n' > "$ROOT/scripts/a.sh"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/a.sh"* ]]
}

@test "P073 Step 17: untracked files never invalidate" {
  _seed
  printf 'scratch\n' > "$ROOT/scratch.txt"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -eq 0 ]
}

# ─── legacy freezes behave exactly as before P073 ─────────────────────────

@test "P073 Step 17 (legacy): a legacy freeze still invalidates on ANY head movement" {
  _seed --legacy
  _ancillary_commit
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
}

@test "P073 Step 17 (legacy): a legacy freeze cannot be rescued by acceptance" {
  _seed --legacy
  _ancillary_commit
  run _accept
  [ "$status" -ne 0 ]
  [[ "$output" == *"unavailable"* ]]
}

@test "P073 Step 17 (legacy): a legacy freeze still tolerates the five runtime paths" {
  _seed --legacy
  mkdir -p "$ROOT/.aid-o/config"
  printf 'q: 1\n' > "$ROOT/.aid-o/config/queue.yaml"
  ( cd "$ROOT" && git add -f .aid-o/config/queue.yaml && git commit -qm q ) >/dev/null 2>&1
  local h; h="$(_head)"
  printf 'q: 2\n' > "$ROOT/.aid-o/config/queue.yaml"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$h'"
  [ "$status" -eq 0 ]
}

@test "P073 Step 17 (legacy): a legacy freeze still invalidates on delivery dirt" {
  _seed --legacy
  printf 'echo dirty\n' > "$ROOT/scripts/a.sh"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
}

# ─── the C4 decision record surfaces equivalence ──────────────────────────

@test "P073 Step 17: the C4 manifest record carries accepted_head and review_equivalence" {
  run grep -c 'review_equivalence' "$PFSM"
  [ "$output" -ge 1 ]
}

# ─── Codex round-1 findings on this step ──────────────────────────────────

@test "P073 Step 17 (F1): an accepted head whose receipt names ANOTHER candidate is not honoured" {
  # The receipt hash proves the file is unaltered, not that it describes this
  # freeze. A mixed manifest could otherwise carry an acceptance forward.
  _seed
  _ancillary_commit
  _accept >/dev/null 2>&1
  local r
  r="$(find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' | head -1)"
  jq '.candidate_sha = "ffffffffffffffffffffffffffffffffffffffff"' "$r" > "$r.tmp" && mv "$r.tmp" "$r"
  # Re-bind the manifest to the tampered receipt's real hash so ONLY the
  # candidate binding is wrong.
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  jq --arg s "sha256:$(sha256sum "$r" | awk '{print $1}')" \
     '.plan_boundary_manifest.equivalence_receipt_sha256 = $s' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
}

@test "P073 Step 17 (F1): an acceptance recorded against a PARTIAL protected set is not honoured" {
  _seed
  _ancillary_commit
  _accept >/dev/null 2>&1
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  jq '.plan_boundary_manifest.protected_paths_complete = false' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _drift "_pfsm_review_candidate_drift . $PLAN '$CAND'"
  [ "$status" -ne 0 ]
}

@test "P073 Step 17 (F3): acceptance at an UNMOVED head writes no receipt" {
  # Measured before the fix: it minted one, and C4 then reported
  # review_equivalence:true for a plan whose head never left the candidate.
  _seed
  run _accept
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to accept"* ]]
  [ "$(find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' | wc -l | tr -d ' ')" = "0" ]
}

@test "P073 Step 17 (F3): the C4 flag compares accepted_head against the candidate" {
  run grep -c 'review_equivalence:($ah != "" and $ah != $cand)' "$PFSM"
  [ "$output" = "1" ]
}
