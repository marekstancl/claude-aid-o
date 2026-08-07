#!/usr/bin/env bats
# test-plan-worktree-create.bats — P074 Step 7: `plan-start` creates the
# plan's execution worktree, records it, and COMPENSATES on any failure.
#
# THE GROUNDED FAILURE MODE UNDER TEST: plan-start used to create refs only.
# Once plan-linked commands are required to run inside the plan's own
# worktree (Step 8), a `plan/<id>` ref without its worktree strands every
# later command — and a half-created one strands it worse, because the
# plan-op ledger would still claim `git_applied` for a branch that was
# rolled back, which the NEXT plan-start hard-fails on (exit 5) instead of
# converging. So creation is transactional: branch -> worktree -> plan-state
# record, and a failure at any point leaves NOTHING behind — no worktree, no
# branch, no state pointer, and a ledger that no longer claims the branch.
#
# FD-3 HYGIENE: bats reports results over fd 3; a child that inherits and
# holds it truncates the suite's TAP output (missing results still exit 0).
# Every plan-FSM invocation below therefore runs with `3>&-`. A `run` child
# that exits 127 ALSO writes a bats warning to fd 3, which with `3>&-`
# destroys the whole file's output — so every invocation goes through a
# helper that can never be a missing command. After any edit verify:
#   bats --tap test-plan-worktree-create.bats | grep -cE '^(ok|not ok)'  # == 16

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_FSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PLAN_FSM
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  ROOT="$TEST_TMPDIR/project"
  export ROOT
  unset AID_PROJECT_ROOT
  export AID_PLAN_STATE_PROJECT_ROOT="$ROOT" AID_PLAN_MANIFEST_PROJECT_ROOT="$ROOT"
  _mk_project "$ROOT"
}

teardown() {
  cd /
  # A fixture may have left a directory read-only on purpose; make the tree
  # removable again before rm -rf.
  [[ -d "$TEST_TMPDIR" ]] && chmod -R u+rwX "$TEST_TMPDIR" 2>/dev/null || true
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

PLAN_ID="P900"

# _mk_project <dir> — a committed checkout carrying the plan source file and
# the tracked lifecycle manifest plan-start's own lifecycle write needs, so
# the tests below assert FULL success rather than "got past the preflight"
# (same seam test-scoped-preflights.bats' _seed_lifecycle documents).
_mk_project() {
  local d="$1"
  mkdir -p "$d/.aid-o/plans" "$d/.aid-o/config" "$d/.aid-o/work/evidence"
  printf '.aid-o/\n.aid-worktrees/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  printf '# %s\n\n**EPIC 1: the delivered one**\n' "$PLAN_ID" \
    > "$d/.aid-o/plans/${PLAN_ID}-lifecycle.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed project"
  )
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh'
            aid_lifecycle_ensure_manifest '$PLAN_ID' '$d' >/dev/null" >/dev/null 2>&1 || true
}

# _in_root <script> — run bash -c in the project root with the plan libs
# available. `bash -c` can never be a missing command, so no 127-on-fd-3.
_in_root() {
  bash -c "cd '$ROOT' || exit 9
           export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
           $1" 3>&-
}

# _pf <args...> — the real plan FSM, fd 3 closed.
_pf() {
  local q="" a
  for a in "$@"; do q+=" '${a}'"; done
  bash -c "cd '$ROOT' && exec bash '$PLAN_FSM'${q}" 3>&-
}

_wt() { printf '%s/.aid-worktrees/plan-%s' "$ROOT" "$PLAN_ID"; }

_recorded() {
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_get '$PLAN_ID' worktree_path 2>/dev/null || true"
}

_registered() {
  git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -qx "worktree $(_wt)"
}

_branch_exists() {
  git -C "$ROOT" rev-parse --verify --quiet "refs/heads/plan/${PLAN_ID}" >/dev/null 2>&1
}

# _last_phase — the phase of the LAST operation-ledger record, or "" when
# there is no ledger at all. `bash -c` so a missing file can never be a 127.
_last_phase() {
  bash -c "f='$ROOT/.aid-o/work/plan-state/${PLAN_ID}/operations.jsonl'
           [[ -f \$f ]] || exit 0
           tail -1 \"\$f\" | jq -r '.phase // empty' 2>/dev/null || true" 3>&-
}

# _simulate_kill_after_branch — the exact F1 window: `git branch` landed, the
# ledger still says `intent` for the op plan-start will derive, and nothing
# else exists (no manifest, no state file, no worktree).
_simulate_kill_after_branch() {
  _in_root "set -e
    source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
    base=\$(git -C '$ROOT' rev-parse main)
    git -C '$ROOT' branch plan/${PLAN_ID} \"\$base\"
    op=\$(plan_op_key plan-start ${PLAN_ID} - 0 ${PLAN_ID})
    plan_op_begin ${PLAN_ID} \"\$op\" plan-start ${PLAN_ID} ''"
}

# ─── 1. the happy path ─────────────────────────────────────────────────────

@test "P074 Step 7: plan-start creates the plan branch, its worktree, and records the path" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  _branch_exists
  [ -d "$(_wt)" ]
  _registered
  [ "$(_recorded)" = "$(_wt)" ]
}

@test "P074 Step 7: the worktree's HEAD is the plan branch" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  run bash -c "git -C '$(_wt)' symbolic-ref --short HEAD" 3>&-
  [ "$status" -eq 0 ]
  [ "$output" = "plan/${PLAN_ID}" ]
}

@test "P074 Step 7: a second plan-start is idempotent — same worktree, no second registration" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  run bash -c "git -C '$ROOT' worktree list --porcelain | grep -c '^worktree '" 3>&-
  [ "$output" = "2" ]   # the primary checkout + exactly one plan worktree
}

# ─── 2. forced worktree-add failure -> full compensation ───────────────────

@test "P074 Step 7: a colliding UNREGISTERED directory refuses and leaves NO branch and NO plan-state entry" {
  # A crash plus a manual `git worktree prune` leaves exactly this shape.
  mkdir -p "$(_wt)"
  printf 'leftover\n' > "$(_wt)/stale.txt"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists but is NOT a registered worktree"* ]]
  [[ "$output" == *"git worktree prune"* ]]
  [[ "$output" == *"COMPENSATED"* ]]
  # Nothing survives: no branch, no state file, no registration.
  ! _branch_exists
  [ ! -f "$ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml" ]
  ! _registered
  # And the directory plan-start did NOT create is still there, untouched.
  [ -f "$(_wt)/stale.txt" ]
  # The ledger was rolled back WITH the branch: its last record for this op is
  # `aborted`, not the `git_applied` that would make the next plan-start
  # hard-fail (exit 5) on a branch that no longer exists.
  run bash -c "tail -1 '$ROOT/.aid-o/work/plan-state/${PLAN_ID}/operations.jsonl' | jq -r .phase" 3>&-
  [ "$output" = "aborted" ]
}

@test "P074 Step 7: a genuine 'git worktree add' failure is reported verbatim and compensates" {
  # `.aid-worktrees` as a regular FILE: mkdir cannot make the parent and git's
  # own add fails — the network-mount / no-worktree-support shape.
  printf 'not a directory\n' > "$ROOT/.aid-worktrees"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"git worktree add"* ]]
  [[ "$output" == *"COMPENSATED"* ]]
  ! _branch_exists
  [ ! -f "$ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml" ]
}

@test "P074 Step 7: re-running plan-start after compensation succeeds cleanly (the ledger was rolled back too)" {
  mkdir -p "$(_wt)"; printf 'leftover\n' > "$(_wt)/stale.txt"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  # The op ledger must NOT still claim git_applied for the deleted branch —
  # otherwise this re-run hard-fails at the exit-5 consistency check.
  rm -rf "$(_wt)"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  [[ "$output" != *"manual reconciliation required"* ]]
  _branch_exists
  _registered
  [ "$(_recorded)" = "$(_wt)" ]
}

# ─── 3. forced plan-state-write failure -> worktree AND branch rolled back ─

@test "P074 Step 7: a plan-state write failure leaves NO worktree and NO branch" {
  if [[ "$(id -u)" -eq 0 ]]; then skip "root ignores directory permissions"; fi
  # Pre-seed a VALID state file (so plan_state_init is skipped and the failure
  # lands on the worktree_path write), plus the lock and op log the earlier
  # steps append to, then make the directory itself unwritable — `tmp + mv`
  # cannot land there, which is exactly how the writer fails in the field
  # (full disk, read-only mount).
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_init '$PLAN_ID' legacy_epic_release_mode 'plan/${PLAN_ID}' main >/dev/null
            touch '$ROOT/.aid-o/work/plan-state/${PLAN_ID}/operations.jsonl'"
  [ -f "$ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml" ]
  chmod 555 "$ROOT/.aid-o/work/plan-state/${PLAN_ID}"

  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not be recorded in plan-state"* ]]
  [[ "$output" == *"removed again"* ]]

  chmod 755 "$ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  # Full compensation: the worktree it created is gone, so is the branch.
  [ ! -d "$(_wt)" ]
  ! _registered
  ! _branch_exists
  # The pre-existing state file was NOT deleted (this run did not create it),
  # and carries no pointer to a worktree that does not exist.
  [ -f "$ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml" ]
  [ -z "$(_recorded)" ]
  # THE LEDGER, not just the git state (review F3): the compensation claimed a
  # ledger rollback, so the last record must actually say `aborted` — the
  # earlier version of this case never looked, and would have passed while the
  # ledger still said git_applied for a branch that no longer exists.
  [ "$(_last_phase)" = "aborted" ]
  [[ "$output" == *"COMPENSATED:"* ]]
  [[ "$output" != *"PARTIALLY COMPENSATED"* ]]
  # ...and the re-run the compensation promises actually converges.
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  [[ "$output" != *"manual reconciliation required"* ]]
  _branch_exists
  _registered
  [ "$(_recorded)" = "$(_wt)" ]
}

@test "P074 Step 7: a compensation that cannot undo everything reports what SURVIVED instead of claiming nothing did" {
  # THE HONESTY CONTRACT, on the one step that can be made to fail for EVERY
  # uid: a LOCKED worktree refuses `worktree remove --force`, and because the
  # plan branch is still checked out in it, `branch -D` refuses too. The
  # compensation must then name both survivors with their manual cleanup and
  # must NOT append an `aborted` ledger record for a branch that still exists.
  #
  # Called directly rather than through a killed plan-start: no root-proof
  # fixture drives a real invocation into this exact state, and a case that
  # skips under uid 0 (as the first version of this suite's failure fixtures
  # did) exercises nothing in root-running CI.
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  git -C "$ROOT" worktree lock "$(_wt)"
  local op
  op="$(_in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
                  plan_op_key plan-start ${PLAN_ID} - 0 ${PLAN_ID}")"

  run bash -c "cd '$ROOT'
    export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
    source '$PLAN_FSM'
    _pfsm_plan_start_compensate '$ROOT' '$PLAN_ID' 'plan/${PLAN_ID}' '$op' 1 0" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTIALLY COMPENSATED"* ]]
  [[ "$output" != *"nothing from this plan-start survives"* ]]
  [[ "$output" == *"SURVIVED:"* ]]
  [[ "$output" == *"git worktree remove -f -f '$(_wt)'"* ]]
  [[ "$output" == *"branch -D"* ]]
  # It really did survive — and the ledger was NOT falsified to say aborted.
  _branch_exists
  _registered
  [ "$(_last_phase)" != "aborted" ]

  git -C "$ROOT" worktree unlock "$(_wt)" || true
}

# ─── 3b. the kill window F1: branch created, ledger still at `intent` ──────

@test "P074 Step 7: a plan-start killed after 'git branch' but before the ledger record RESUMES instead of stranding the plan" {
  _simulate_kill_after_branch
  _branch_exists
  [ "$(_last_phase)" = "intent" ]
  [ ! -d "$(_wt)" ]

  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  [[ "$output" == *"completing a plan-start that was killed"* ]]
  # The SAME branch is kept (not deleted and re-made), and the plan is now
  # whole: worktree registered, path recorded, ledger committed.
  _branch_exists
  _registered
  [ "$(_recorded)" = "$(_wt)" ]
  [ "$(_last_phase)" = "state_committed" ]
}

@test "P074 Step 7: the intent-window resume refuses a branch that carries work (it is not that window)" {
  _simulate_kill_after_branch
  # Someone committed on the stranded branch: it is no longer the pristine
  # branch the kill window leaves, so it is never silently adopted.
  _in_root "set -e
    git -C '$ROOT' worktree add -q '$TEST_TMPDIR/side' plan/${PLAN_ID}
    cd '$TEST_TMPDIR/side'
    printf 'work\n' > work.txt
    git add work.txt
    git -c user.email=t@example.com -c user.name=T commit -q -m work"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"is NOT contained in"* ]]
  _branch_exists
}

# ─── 4. resume shapes ──────────────────────────────────────────────────────

@test "P074 Step 7: a recorded-but-missing worktree refuses and names --recreate-worktree" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  rm -rf "$(_wt)"
  git -C "$ROOT" worktree prune
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"--recreate-worktree"* ]]
  # A refusal on the resume path creates and destroys nothing.
  _branch_exists
}

@test "P074 Step 7: a REGISTERED but UNRECORDED worktree is adopted, never treated as a legacy plan" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  # The kill window: `worktree add` landed, the plan-state record did not.
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_set_worktree_path '$PLAN_ID' ''"
  [ -z "$(_recorded)" ]
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  [[ "$output" == *"adopting the already-registered worktree"* ]]
  [ "$(_recorded)" = "$(_wt)" ]
  _registered
}

@test "P074 Step 7: a registered worktree at the canonical path on ANOTHER branch is NOT adopted" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  # Somebody else's tree at this plan's path: registered, but not on
  # plan/<id>. Registration alone used to be enough to adopt it, which gave
  # the plan a path pointer and no execution worktree (review F6).
  _in_root "git -C '$(_wt)' checkout -q -b sidetrack"
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_set_worktree_path '$PLAN_ID' ''"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"its HEAD is not plan/${PLAN_ID}"* ]]
  [[ "$output" == *"NOT adopted and NOT deleted"* ]]
  # Nothing was recorded, and the foreign tree is untouched.
  [ -z "$(_recorded)" ]
  run bash -c "git -C '$(_wt)' symbolic-ref --short HEAD" 3>&-
  [ "$output" = "sidetrack" ]
}

@test "P074 Step 7: a RECORDED worktree that has left the plan branch refuses instead of running there" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  _in_root "git -C '$(_wt)' checkout -q -b sidetrack"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"its HEAD is not plan/${PLAN_ID}"* ]]
  [[ "$output" == *"--recreate-worktree"* ]]
}

@test "P074 Step 7: plan-state refuses a traversing or out-of-root worktree_path" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  # `../outside` used to be accepted (review F7) — a record every consumer,
  # teardown above all, would then act on outside the repository.
  run _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
                plan_state_set_worktree_path '$PLAN_ID' '../outside'"
  [ "$status" -ne 0 ]
  run _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
                plan_state_set_worktree_path '$PLAN_ID' '$TEST_TMPDIR/elsewhere'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"inside the state root"* ]]
  # The real record survived both refusals untouched.
  [ "$(_recorded)" = "$(_wt)" ]
}

# ─── 5. the installed template ─────────────────────────────────────────────

@test "P074 Step 7: .aid-worktrees/ is in the installed gitignore template and the aid-init upgrade note" {
  grep -qx '\.aid-worktrees/' "$AID_PLUGIN_PATH/defaults/.gitignore"
  grep -q '\.aid-worktrees/' "$AID_PLUGIN_PATH/commands/aid-init.md"
  grep -qi 'upgrade note' "$AID_PLUGIN_PATH/commands/aid-init.md"
}
