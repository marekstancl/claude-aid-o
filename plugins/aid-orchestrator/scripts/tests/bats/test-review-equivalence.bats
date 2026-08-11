#!/usr/bin/env bats
# aid-tier: t2
# test-review-equivalence.bats — P073 Step 16: the equivalence predicate and
# the acceptance receipt.
#
# After freeze, ANY tracked write threw away a completed review — an audit-log
# append or a rendered report cost a full re-review cycle even though nothing
# about the delivery had changed. A head that differs from the candidate only
# in ANCILLARY paths still describes the same delivery, so its review applies.
# Anything touching the PROTECTED set is a fix and costs the review, as before.
#
# The predicate is PURE (no writes) and acceptance is a separate deliberate
# act; collapsing them would make every drift check quietly change state.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PFSM
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  PLAN=P900
  export PLAN
}

teardown() {
  teardown_test_evidence_dir
}

# _eq <body> — run <body> with the plan-FSM helpers in scope, inside $ROOT.
_eq() {
  bash -c '
    set -uo pipefail
    SCRIPT_DIR="$1/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    . "$SCRIPT_DIR/lib/aid-ancillary.sh"
    eval "$(sed -n "/^# ═*$/,/^_pfsm_review_candidate_drift() {/p" "$SCRIPT_DIR/aid-plan-fsm.sh" \
            | sed -n "/^_pfsm_equivalence_classify()/,/^_pfsm_review_candidate_drift() {/p" \
            | sed "\$d")"
    cd "$2"
    eval "$3"
  ' _ "$AID_PLUGIN_PATH" "$ROOT" "$1"
}

# _seed [protected-extra] — a repo with a plan branch, a frozen candidate and a
# protected set covering the delivery surface.
_seed() {
  ( cd "$ROOT"
    git init -q
    git config user.email t@e.com
    git config user.name T
    git checkout -q -b main 2>/dev/null || git branch -m main
    mkdir -p scripts .aid-o/work
    printf 'seed\n' > README.md
    printf 'echo a\n' > scripts/a.sh
    git add -A && git commit -qm seed
    git checkout -q -b "plan/$PLAN" ) >/dev/null 2>&1
  CAND="$(cd "$ROOT" && git rev-parse HEAD)"
  export CAND
  local rel=".aid-o/work/evidence/$PLAN/R-$PLAN-final-1"
  mkdir -p "$ROOT/$rel"
  printf '%s\0' "scripts/a.sh" "README.md" ".aid-lifecycle/manifests/$PLAN.yaml" > "$BATS_TEST_TMPDIR/prot.nul"
  _eq "plan_manifest_init $PLAN plan/$PLAN main '$CAND' '$CAND' plan_branch >/dev/null
       plan_manifest_freeze_candidate $PLAN '$CAND' '$CAND' R-$PLAN-final-1 '$rel' '2026-08-05T00:00:00Z' '$BATS_TEST_TMPDIR/prot.nul' true >/dev/null"
}

_commit() { ( cd "$ROOT" && git add -A && git commit -qm "$1" ) >/dev/null 2>&1; }
_head() { ( cd "$ROOT" && git rev-parse HEAD ); }
_receipts() { find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' 2>/dev/null | wc -l | tr -d ' '; }

# ─── the predicate ────────────────────────────────────────────────────────

@test "P073 Step 16: an unmoved head is trivially equivalent" {
  _seed
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 0 ]
}

@test "P073 Step 16: an ANCILLARY-only commit is equivalent" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary: audit log"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 0 ]
}

@test "P073 Step 16: a DELIVERY commit is not equivalent, and the offending path is named" {
  _seed
  printf 'echo changed\n' > "$ROOT/scripts/a.sh"
  _commit "fix: change a delivery file"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not equivalent"* ]]
  [[ "$output" == *"scripts/a.sh"* ]]
  [[ "$output" == *"PROTECTED"* ]]
}

@test "P073 Step 16: a MIXED commit (ancillary + protected) is not equivalent" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  printf 'echo changed\n' > "$ROOT/scripts/a.sh"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl scripts/a.sh ) >/dev/null 2>&1
  _commit "mixed"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"scripts/a.sh"* ]]
}

@test "P073 Step 16: a NON-ANCESTOR head (rewritten branch) is not equivalent" {
  _seed
  ( cd "$ROOT"
    git checkout -q --orphan rewritten
    git rm -rq --cached . 2>/dev/null || true
    printf 'different\n' > README.md
    git add -A && git commit -qm "rewritten history"
    git branch -M "plan/$PLAN" ) >/dev/null 2>&1
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an ancestor"* ]]
  [[ "$output" == *"rewritten, not appended"* ]]
}

@test "P073 Step 16: an UNTRACKED-only worktree does not break equivalence" {
  _seed
  printf 'scratch\n' > "$ROOT/scratch.txt"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 0 ]
}

@test "P073 Step 16: tracked dirt OUTSIDE the ancillary policy is not equivalent" {
  _seed
  printf 'echo dirty\n' > "$ROOT/scripts/a.sh"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted TRACKED changes"* ]]
}

# ─── unavailability (code 2) ──────────────────────────────────────────────

@test "P073 Step 16: a LEGACY freeze with no protected set reports UNAVAILABLE, not equivalent" {
  _seed
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  jq 'del(.plan_boundary_manifest.protected_paths) | del(.plan_boundary_manifest.protected_paths_complete)' \
    "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"equivalence unavailable"* ]]
  [[ "$output" == *"exactly as before P073"* ]]
}

@test "P073 Step 16: a PARTIAL protected set reports UNAVAILABLE — it can never authorise acceptance" {
  _seed
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  jq '.plan_boundary_manifest.protected_paths_complete = false' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"PARTIAL"* ]]
}

@test "P073 Step 16: no frozen candidate reports UNAVAILABLE" {
  ( cd "$ROOT" && git init -q && git config user.email t@e.com && git config user.name T \
      && printf 'x\n' > a && git add -A && git commit -qm s ) >/dev/null 2>&1
  local h; h="$(cd "$ROOT" && git rev-parse HEAD)"
  _eq "plan_manifest_init $PLAN plan/$PLAN main '$h' '$h' plan_branch >/dev/null"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no frozen candidate"* ]]
}

# ─── the predicate performs NO writes ─────────────────────────────────────

@test "P073 Step 16: the predicate writes nothing — manifest bytes and file count unchanged" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary"

  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  local before_sha before_count
  before_sha="$(sha256sum "$mf" | awk '{print $1}')"
  before_count="$(find "$ROOT/.aid-o" -type f | wc -l)"

  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 0 ]

  [ "$(sha256sum "$mf" | awk '{print $1}')" = "$before_sha" ]
  [ "$(find "$ROOT/.aid-o" -type f | wc -l)" = "$before_count" ]
}

# ─── acceptance ───────────────────────────────────────────────────────────

_accept() { ( cd "$ROOT" && bash "$PFSM" plan-finalize "$PLAN" --stage accept-ancillary --project-root "$ROOT" ); }

@test "P073 Step 16: acceptance writes ONE receipt and records accepted_head" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary"
  local new_head; new_head="$(_head)"

  run _accept
  [ "$status" -eq 0 ]
  [[ "$output" == *"accepted as review-equivalent"* ]]
  [ "$(_receipts)" = "1" ]

  local r; r="$(find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' | head -1)"
  [ "$(jq -r '.artifact_type' "$r")" = "review_equivalence_receipt" ]
  [ "$(jq -r '.candidate_sha' "$r")" = "$CAND" ]
  [ "$(jq -r '.accepted_head' "$r")" = "$new_head" ]
  [ "$(jq -r '.prior_accepted_head' "$r")" = "null" ]
  [[ "$(jq -r '.changed_paths | join(",")' "$r")" == *"audit-log.jsonl"* ]]
}

@test "P073 Step 16: candidate_sha is BYTE-IDENTICAL before and after acceptance — only accepted_head changes" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary"

  run _accept
  [ "$status" -eq 0 ]
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  [ "$(jq -r '.plan_boundary_manifest.candidate_sha' "$mf")" = "$CAND" ]
  [ "$(jq -r '.plan_boundary_manifest.accepted_head' "$mf")" = "$(_head)" ]
  # The manifest binding names the authoritative receipt.
  [ "$(jq -r '.plan_boundary_manifest.equivalence_receipt_path' "$mf")" != "null" ]
  local rp rs
  rp="$(jq -r '.plan_boundary_manifest.equivalence_receipt_path' "$mf")"
  rs="$(jq -r '.plan_boundary_manifest.equivalence_receipt_sha256' "$mf")"
  [ "$rs" = "sha256:$(sha256sum "$ROOT/$rp" | awk '{print $1}')" ]
}

@test "P073 Step 16: acceptance REFUSES a protected-surface change, naming every offender" {
  _seed
  printf 'echo changed\n' > "$ROOT/scripts/a.sh"
  _commit "fix"
  run _accept
  [ "$status" -ne 0 ]
  [[ "$output" == *"not review-equivalent"* ]]
  [[ "$output" == *"scripts/a.sh"* ]]
  [[ "$output" == *"is a FIX"* ]]
  [ "$(_receipts)" = "0" ]
}

@test "P073 Step 16: acceptance with NOTHING frozen is refused" {
  ( cd "$ROOT" && git init -q && git config user.email t@e.com && git config user.name T \
      && printf 'x\n' > a && git add -A && git commit -qm s && git checkout -q -b "plan/$PLAN" ) >/dev/null 2>&1
  local h; h="$(cd "$ROOT" && git rev-parse HEAD)"
  _eq "plan_manifest_init $PLAN plan/$PLAN main '$h' '$h' plan_branch >/dev/null"
  run _accept
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing is frozen"* ]]
}

@test "P073 Step 16: a SECOND ancillary commit gets a second acceptance and a suffixed receipt" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"one"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary one"
  run _accept
  [ "$status" -eq 0 ]
  local first_head; first_head="$(_head)"

  printf '{"event":"two"}\n' >> "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary two"
  run _accept
  [ "$status" -eq 0 ]

  [ "$(_receipts)" = "2" ]
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  [ "$(jq -r '.plan_boundary_manifest.accepted_head' "$mf")" = "$(_head)" ]
  # The second receipt records what it superseded.
  local r2; r2="$(find "$ROOT/.aid-o" -name 'review-equivalence-receipt-1.json' | head -1)"
  [ -n "$r2" ]
  [ "$(jq -r '.prior_accepted_head' "$r2")" = "$first_head" ]
  # candidate_sha STILL has not moved.
  [ "$(jq -r '.plan_boundary_manifest.candidate_sha' "$mf")" = "$CAND" ]
}

@test "P073 Step 16: accepting the SAME head twice is idempotent — no duplicate receipt" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary"
  run _accept
  [ "$status" -eq 0 ]
  run _accept
  [ "$status" -eq 0 ]
  [[ "$output" == *"already the accepted head"* ]]
  [ "$(_receipts)" = "1" ]
}

@test "P073 Step 16: acceptance on an UNAVAILABLE plan is refused, never silently granted" {
  _seed
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  jq '.plan_boundary_manifest.protected_paths_complete = false' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _accept
  [ "$status" -ne 0 ]
  [[ "$output" == *"equivalence is unavailable"* ]]
  [ "$(_receipts)" = "0" ]
}

@test "P073 Step 16: the resulting manifest passes validation" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary"
  run _accept
  [ "$status" -eq 0 ]
  run _eq "plan_manifest_validate $PLAN"
  [ "$status" -eq 0 ]
}

@test "P073 Step 16: the stage is dispatchable and documented in the usage" {
  run grep -c 'accept-ancillary' "$PFSM"
  [ "$output" -ge 3 ]
  run bash -c "cd '$ROOT' && bash '$PFSM' plan-finalize $PLAN --stage bogus 2>&1 | head -2"
  [[ "$output" == *"stage"* ]]
}

# ─── Codex round-1 findings, each reproduced before it was fixed ───────────
# Every test below failed against the code as first written.

@test "P073 Step 16 (F2): a RENAME of a delivery file INTO an ancillary directory is not equivalent" {
  # Measured on the code as first written: git's default rename detection
  # reported only the ancillary destination, so the disappearance of the
  # protected delivery path was invisible and the move read as ancillary-only.
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  ( cd "$ROOT" && git mv scripts/a.sh .aid-o/work/a.sh ) >/dev/null 2>&1
  _commit "rename a delivery file into an ancillary directory"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"scripts/a.sh"* ]]
}

@test "P073 Step 16 (F3): a FAILING diff reports UNAVAILABLE, never 'nothing changed'" {
  # NOTE ON REACHABILITY: at the PREDICATE level a bogus candidate is caught
  # one step earlier by the ancestry check (also fail-closed), so this asserts
  # the fix where the failure is actually reachable — the classifier itself,
  # which is what a corrupt object store or an unreadable repo would hit.
  # Before the fix its `|| true` turned a failed diff into zero lines, i.e.
  # "no changes", i.e. equivalent. Measured: `git diff --name-only <bogus>..HEAD`
  # prints nothing and the error was swallowed.
  _seed
  run _eq "_pfsm_equivalence_classify . $PLAN deadbeefdeadbeefdeadbeefdeadbeefdeadbeef '$CAND'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unavailable"* ]]
  [[ "$output" != *"ancillary"* ]]
}

@test "P073 Step 16 (F1): uncommitted dirt on a PROTECTED path that is ALSO ancillary is not equivalent" {
  # `.aid-o/work/**` is an ancillary glob, so the shared ancillary filter alone
  # exempted a protected receipt living under it.
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
  local rel=".aid-o/work/evidence/$PLAN/R-$PLAN-final-1"
  mkdir -p "$ROOT/$rel"
  printf '%s\0' "scripts/a.sh" ".aid-o/work/consumed-receipt.json" > "$BATS_TEST_TMPDIR/prot.nul"
  _eq "plan_manifest_init $PLAN plan/$PLAN main '$CAND' '$CAND' plan_branch >/dev/null
       plan_manifest_freeze_candidate $PLAN '$CAND' '$CAND' R-$PLAN-final-1 '$rel' '2026-08-05T00:00:00Z' '$BATS_TEST_TMPDIR/prot.nul' true >/dev/null"

  printf 'tampered\n' > "$ROOT/.aid-o/work/consumed-receipt.json"
  run _eq "plan_final_review_equivalent . $PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"consumed-receipt.json"* ]]
  [[ "$output" == *"PROTECTED"* ]]
}

@test "P073 Step 16 (F4): the manifest binding is a CAS — a moved candidate refuses the write" {
  _seed
  run _eq "plan_manifest_set_accepted_head $PLAN '$(printf 'a%.0s' {1..40})' .aid-o/r.json 'sha256:$(printf 'b%.0s' {1..64})' 'ffffffffffffffffffffffffffffffffffffffff' ''"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CAS FAILED"* ]]
}

@test "P073 Step 16 (F4): the CAS also refuses when another acceptance already won" {
  _seed
  # A prior acceptance is on record; this caller thinks there was none.
  local mf="$ROOT/.aid-o/work/plan-state/$PLAN/plan-boundary-manifest.json"
  jq --arg h "$(printf 'c%.0s' {1..40})" \
     '.plan_boundary_manifest.accepted_head = $h
      | .plan_boundary_manifest.equivalence_receipt_path = "x.json"
      | .plan_boundary_manifest.equivalence_receipt_sha256 = "sha256:'"$(printf 'd%.0s' {1..64})"'"' \
     "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _eq "plan_manifest_set_accepted_head $PLAN '$(printf 'a%.0s' {1..40})' .aid-o/r.json 'sha256:$(printf 'b%.0s' {1..64})' '$CAND' ''"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CAS FAILED"* ]]
}

@test "P073 Step 16 (F6): a DELETED acceptance receipt is refused, not reported as accepted" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary"
  run _accept
  [ "$status" -eq 0 ]
  find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' -delete
  run _accept
  [ "$status" -ne 0 ]
  [[ "$output" == *"receipt"* ]]
}

@test "P073 Step 16 (F6): a TAMPERED acceptance receipt is refused" {
  _seed
  mkdir -p "$ROOT/.aid-o/work"
  printf '{"event":"x"}\n' > "$ROOT/.aid-o/work/audit-log.jsonl"
  ( cd "$ROOT" && git add -f .aid-o/work/audit-log.jsonl ) >/dev/null 2>&1
  _commit "ancillary"
  run _accept
  [ "$status" -eq 0 ]
  local r
  r="$(find "$ROOT/.aid-o" -name 'review-equivalence-receipt*.json' | head -1)"
  printf '{"tampered":true}\n' > "$r"
  run _accept
  [ "$status" -ne 0 ]
  [[ "$output" == *"no longer hashes"* ]]
}
