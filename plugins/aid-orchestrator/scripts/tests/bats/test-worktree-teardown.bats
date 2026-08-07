#!/usr/bin/env bats
# test-worktree-teardown.bats — P074 Step 11: worktree teardown and audited
# repair.
#
# THE GROUNDED FAILURE MODE UNDER TEST: Step 7 gives every plan its own
# execution worktree. Without teardown those accumulate, and a leftover
# REGISTRATION is worse than a leftover directory — it makes the next plan
# that wants the same path fail its `worktree add`. So `plan-close` and
# `plan-rollback` remove the worktree, prune the registration, and clear the
# plan-state pointer; and because a close is a terminal, durable transaction,
# a teardown that CANNOT complete downgrades to a warning naming the manual
# cleanup rather than blocking the close.
#
# The repair half — `plan-state <id> --recreate-worktree --reason` — is a
# TRANSACTION, not a force: it bypasses nothing, so it writes the P073 audit
# primitives (timeline event + audit-log append) and deliberately NO waiver
# artifact and no forced_override.
#
# Both close and rollback fixtures are built through the REAL library entry
# points and run the REAL commands (shape borrowed from
# test-active-index.bats' writer-3 / writer-4 cases), so this suite asserts
# wiring, not a hand-called helper.
#
# FD-3 HYGIENE: every plan-FSM invocation runs with `3>&-` (a child holding
# bats' report fd truncates the TAP stream), and every `run` goes through a
# `bash -c` helper that can never exit 127 on fd 3. After any edit verify:
#   bats --tap test-worktree-teardown.bats | grep -cE '^(ok|not ok)'   # == 15

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
}

teardown() {
  cd /
  [[ -d "$TEST_TMPDIR" ]] && chmod -R u+rwX "$TEST_TMPDIR" 2>/dev/null || true
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_libs() {
  printf "%s" "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
                source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh'
                source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh'"
}

_in_root() {
  bash -c "cd '$ROOT' || exit 9
           export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
           $1" 3>&-
}

_pf() {
  local q="" a
  for a in "$@"; do q+=" '${a}'"; done
  bash -c "cd '$ROOT' && exec bash '$PLAN_FSM'${q}" 3>&-
}

_wt() { printf '%s/.aid-worktrees/plan-%s' "$ROOT" "$1"; }

_recorded() {
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_get '$1' worktree_path 2>/dev/null || true"
}

_registered() {
  git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -qx "worktree $(_wt "$1")"
}

# _mk_project — committed checkout with .aid-o skeleton, .aid-worktrees/
# gitignored exactly as /aid-init installs it.
_mk_project() {
  mkdir -p "$ROOT/.aid-o/plans" "$ROOT/.aid-o/config" "$ROOT/.aid-o/work/evidence"
  printf '.aid-o/\n.aid-worktrees/\n' > "$ROOT/.gitignore"
  printf 'seed\n' > "$ROOT/README.md"
  (
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed project"
  )
}

# _seed_open_plan <plan_id> — an OPEN plan with a real branch, a real state
# file, and a real registered worktree recorded in plan-state.
_seed_open_plan() {
  local p="$1"
  _in_root "set -e
    $(_libs)
    base=\$(git -C '$ROOT' rev-parse main)
    git -C '$ROOT' branch plan/${p} \"\$base\"
    plan_state_init ${p} plan_branch plan/${p} main >/dev/null
    plan_manifest_init ${p} plan/${p} main \"\$base\" \"\$base\" plan_branch >/dev/null
    git -C '$ROOT' worktree add -q '$(_wt "$p")' plan/${p}
    plan_state_set_worktree_path ${p} '$(_wt "$p")'"
}

# _seed_aborted_plan <plan_id> — the writer-3 close fixture: a plan in
# ABORTED whose plan-close takes the abort path (no lifecycle receipt needed).
_seed_aborted_plan() {
  local p="$1"
  _seed_open_plan "$p"
  _in_root "set -e
    $(_libs)
    yq -i '.plan_state = \"ABORTED\"' '$ROOT/.aid-o/work/plan-state/${p}/plan-state.yaml'
    plan_manifest_update ${p} '.plan_boundary_manifest.plan_state = \"ABORTED\" | .plan_boundary_manifest.terminal_reason = \"test abort\"' >/dev/null"
}

# ─── 1. plan-close tears the worktree down ─────────────────────────────────

@test "P074 Step 11: plan-close removes the worktree, its registration, and the plan-state pointer" {
  _mk_project
  _seed_aborted_plan P901
  [ -d "$(_wt P901)" ]
  run _pf plan-close P901 --project-root "$ROOT" \
    --force --force-reason "test: exercise the plan-close worktree teardown path"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/.aid-o/work/plan-state/P901/plan-close-complete" ]
  [ ! -d "$(_wt P901)" ]
  ! _registered P901
  [ -z "$(_recorded P901)" ]
  [[ "$output" == *"Execution worktree torn down"* ]]
}

# ─── 2. plan-rollback tears it down likewise ───────────────────────────────

@test "P074 Step 11: plan-rollback removes the worktree, its registration, and the plan-state pointer" {
  _mk_project
  # The writer-4 rollback fixture: a real merge and a real revert on main.
  _in_root "set -e
    $(_libs)
    printf '# P902\n\n**EPIC 1: the delivered one**\n' > '$ROOT/.aid-o/plans/P902-lifecycle.md'
    aid_lifecycle_ensure_manifest P902 '$ROOT' >/dev/null
    aid_lifecycle_set_plan_mode P902 plan_branch '$ROOT' >/dev/null
    base=\$(git -C '$ROOT' rev-parse main)
    git -C '$ROOT' branch plan/P902 \"\$base\"
    git -C '$ROOT' checkout -q plan/P902
    printf 'delivered\n' > '$ROOT/epic-work.txt'
    git -C '$ROOT' add epic-work.txt && git -C '$ROOT' commit -q -m deliver
    cand=\$(git -C '$ROOT' rev-parse plan/P902)
    git -C '$ROOT' checkout -q main
    tb=\$(git -C '$ROOT' rev-parse main)
    git -C '$ROOT' merge -q --no-ff -m 'merge plan/P902' plan/P902
    mc=\$(git -C '$ROOT' rev-parse main)
    git -C '$ROOT' revert -m 1 --no-edit \"\$mc\" >/dev/null 2>&1
    git -C '$ROOT' rev-parse main > '$TEST_TMPDIR/rev.sha'
    plan_state_init P902 plan_branch plan/P902 main >/dev/null
    yq -i '.plan_state = \"PLAN_MERGING\"' '$ROOT/.aid-o/work/plan-state/P902/plan-state.yaml'
    plan_manifest_init P902 plan/P902 main \"\$base\" \"\$base\" plan_branch >/dev/null
    plan_manifest_update P902 \".plan_boundary_manifest.candidate_sha = \\\"\$cand\\\"
      | .plan_boundary_manifest.candidate_frozen_at = \\\"2026-08-06T00:00:00Z\\\"
      | .plan_boundary_manifest.plan_state = \\\"PLAN_MERGING\\\"
      | .plan_boundary_manifest.plan_final_merge = {\\\"result\\\":\\\"merged\\\",\\\"merge_commit\\\":\\\"\$mc\\\",\\\"target_head_before\\\":\\\"\$tb\\\"}\" >/dev/null
    git -C '$ROOT' worktree add -q '$(_wt P902)' plan/P902
    plan_state_set_worktree_path P902 '$(_wt P902)'"
  [ -d "$(_wt P902)" ]
  run bash -c "cd '$ROOT' && exec bash '$PLAN_FSM' plan-rollback P902 \
    --revert-commit \"\$(cat '$TEST_TMPDIR/rev.sha')\" \
    --reason 'test rollback drill' --project-root '$ROOT'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"ROLLED BACK: P902"* ]]
  [ ! -d "$(_wt P902)" ]
  ! _registered P902
  [ -z "$(_recorded P902)" ]
}

# ─── 3. a removal-BLOCKING worktree warns and the close still completes ────

@test "P074 Step 11: a worktree that cannot be removed warns with the verbatim manual cleanup, the close completes, and the worktree REMAINS" {
  _mk_project
  _seed_aborted_plan P901
  # `git worktree lock` is the removal-failure condition NO uid can bypass —
  # git itself refuses `remove --force` on a locked tree and names `-f -f`.
  # (The first version of this fixture used a read-only parent directory and
  # skipped under uid 0, so root-running CI — the common case — exercised the
  # warning path not at all: review F9.)
  git -C "$ROOT" worktree lock "$(_wt P901)"
  run _pf plan-close P901 --project-root "$ROOT" \
    --force --force-reason "test: teardown must never block a durable close"
  # The close itself completed.
  [ "$status" -eq 0 ]
  [ -f "$ROOT/.aid-o/work/plan-state/P901/plan-close-complete" ]
  # ...and the operator got the warning plus the exact recovery line, with
  # the DOUBLED -f a locked worktree needs.
  [[ "$output" == *"WARNING: could not remove the execution worktree"* ]]
  [[ "$output" == *"git worktree remove -f -f $(_wt P901) ; git worktree prune"* ]]
  [[ "$output" == *"Re-running plan-close"* ]]
  # The warning is TRUE: the tree and its registration are still there.
  [ -d "$(_wt P901)" ]
  _registered P901
  git -C "$ROOT" worktree unlock "$(_wt P901)" || true
}

@test "P074 Step 11: a HELD worktree lock DEFERS the destruction — the close completes, the worktree is left in place, and the recovery is named" {
  # Teardown must not treat a lock timeout as a
  # warning and DELETE ANYWAY, on the reasoning that a terminal operation must
  # never be blockable. That conflates two things: the CLOSURE is terminal and
  # must always complete; the DESTRUCTION is cleanup and can wait. Proceeding
  # to delete reopened the exact race the lock was added to close —
  # `--recreate-worktree` holds this lock while it creates and records a
  # replacement, so a concurrent close removed that tree mid-create and the
  # repair finished by recording a path close had just deleted.
  _mk_project
  _seed_aborted_plan P901
  local lock="$ROOT/.aid-o/work/plan-state/P901/plan-worktree.lock"
  # A REAL second process holding the REAL lock, writing its pid exactly as
  # aid_lock_acquire does, so the refusal can be checked to name the holder.
  bash -c "flock -x 9; echo \$\$ > '$lock'; sleep 8" 9>>"$lock" 3>&- &
  local holder=$!
  run bash -c "sleep 1
    cd '$ROOT'
    export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
    export AID_WORKTREE_LOCK_TIMEOUT_S=1
    exec bash '$PLAN_FSM' plan-close P901 --project-root '$ROOT' \
      --force --force-reason 'test: a close racing a worktree repair must not delete'" 3>&-
  local pid_in_lock; pid_in_lock="$(tr -d '[:space:]' < "$lock" 2>/dev/null || true)"
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  # The CLOSURE completed — that is the part that must never block.
  [ "$status" -eq 0 ]
  [ -f "$ROOT/.aid-o/work/plan-state/P901/plan-close-complete" ]
  # The DESTRUCTION was deferred, loudly, naming the holder and the cleanup.
  [[ "$output" == *"TEARDOWN DEFERRED"* ]]
  [[ "$output" == *"holder pid ${pid_in_lock}"* ]]
  [[ "$output" == *"LEFT IN PLACE"* ]]
  [[ "$output" == *"git worktree remove -f -f $(_wt P901) ; git worktree prune"* ]]
  [[ "$output" == *"re-run plan-close"* ]]
  [[ "$output" != *"Execution worktree torn down"* ]]
  # And the report is TRUE: nothing was deleted, nothing was unregistered, and
  # the pointer a concurrent repair may be rewriting was not cleared either.
  [ -d "$(_wt P901)" ]
  _registered P901
  [ "$(_recorded P901)" = "$(_wt P901)" ]

  # The deferral is reconcilable: with the lock free, a re-run finishes it.
  # (The re-run carries the same --force as the first: this fixture's plan has
  # no delivery report and no candidate binding, so plan-close revalidates the
  # marker and refuses without it — nothing to do with the teardown.)
  run _pf plan-close P901 --project-root "$ROOT" \
    --force --force-reason "test: reconcile the teardown that was deferred while the lock was held"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Execution worktree torn down"* ]]
  [ ! -d "$(_wt P901)" ]
  ! _registered P901
  [ -z "$(_recorded P901)" ]
}

@test "P074 Step 11: re-running plan-close on an ALREADY CLOSED plan retries the teardown it could not finish" {
  # THE PERMANENT-LEAK SHAPE (review F5): the close became durable — state
  # CLOSED, marker written — and then the process died (or the teardown
  # failed) before the worktree went. Every retry took the "ALREADY CLOSED …
  # no-op" exit and never came back to it, so the worktree and its
  # registration leaked forever. The fixture reconstructs exactly that state
  # rather than a full close, because that is what a kill leaves.
  _mk_project
  _seed_open_plan P901
  _in_root "yq -i '.plan_state = \"CLOSED\"' '$ROOT/.aid-o/work/plan-state/P901/plan-state.yaml'"
  printf 'plan_id=P901\nresult=closed\n' > "$ROOT/.aid-o/work/plan-state/P901/plan-close-complete"
  [ -d "$(_wt P901)" ]
  _registered P901

  run _pf plan-close P901 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALREADY CLOSED"* ]]
  # The leak is reconciled: tree gone, registration gone, pointer cleared.
  [ ! -d "$(_wt P901)" ]
  ! _registered P901
  [ -z "$(_recorded P901)" ]
}

@test "P074 Step 11: an already-closed plan with nothing left says so and changes nothing" {
  # The other half of the same path: idempotence must not invent work.
  _mk_project
  _seed_open_plan P901
  _in_root "yq -i '.plan_state = \"CLOSED\"' '$ROOT/.aid-o/work/plan-state/P901/plan-state.yaml'"
  printf 'plan_id=P901\nresult=closed\n' > "$ROOT/.aid-o/work/plan-state/P901/plan-close-complete"
  git -C "$ROOT" worktree remove --force "$(_wt P901)"
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_set_worktree_path P901 ''"
  run _pf plan-close P901 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALREADY CLOSED"* ]]
  [[ "$output" == *"No execution worktree to tear down"* ]]
}

# ─── 4. the audited repair ─────────────────────────────────────────────────

@test "P074 Step 11: --recreate-worktree restores a deleted worktree with HEAD on the plan branch" {
  _mk_project
  _seed_open_plan P901
  rm -rf "$(_wt P901)"
  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" \
    --reason "the worktree was deleted by hand during a disk cleanup"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RECREATED"* ]]
  [ -d "$(_wt P901)" ]
  _registered P901
  [ "$(_recorded P901)" = "$(_wt P901)" ]
  run bash -c "git -C '$(_wt P901)' symbolic-ref --short HEAD" 3>&-
  [ "$output" = "plan/P901" ]
}

@test "P074 Step 11: --recreate-worktree writes the repair audit trail and NO force waiver" {
  _mk_project
  _seed_open_plan P901
  rm -rf "$(_wt P901)"
  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" \
    --reason "restoring the execution worktree after an interrupted cleanup"
  [ "$status" -eq 0 ]
  # Record 1 — timeline event.
  run bash -c "grep -h plan_worktree_recreated '$ROOT/.aid-o/work/plan-final/P901/timeline.jsonl'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *'"action":"recreated"'* ]]
  [[ "$output" == *'"forced_override":false'* ]]
  [[ "$output" == *'"actor_semantics":"instruction_only"'* ]]
  # Record 2 — cross-plan audit log.
  run bash -c "grep -c plan_worktree_recreated '$ROOT/.aid-o/work/audit-log.jsonl'" 3>&-
  [ "$output" = "1" ]
  # ...and deliberately NO waiver artifact: nothing was bypassed.
  run bash -c "ls '$ROOT/.aid-o/work/plan-final/P901/' | grep -c '^waiver-' || true" 3>&-
  [ "$output" = "0" ]
}

@test "P074 Step 11: --recreate-worktree ADOPTS a registered-but-unrecorded worktree" {
  _mk_project
  _seed_open_plan P901
  # State-file loss + plan_state_init reconstruction: the path is gone from
  # state, but the worktree itself is alive and registered.
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_set_worktree_path P901 ''"
  [ -z "$(_recorded P901)" ]
  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" \
    --reason "plan-state lost its worktree record after a state-file restore"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADOPTED"* ]]
  [ "$(_recorded P901)" = "$(_wt P901)" ]
  [ -d "$(_wt P901)" ]
}

@test "P074 Step 11: --recreate-worktree takes the per-plan worktree lock for the WHOLE transaction" {
  # Review F4: with no lock, two concurrent repairs both saw "no worktree" and
  # the loser's add-failure cleanup force-removed the WINNER's tree. The lock
  # is asserted by holding it: the repair must refuse and do nothing, not
  # proceed alongside whoever holds it.
  _mk_project
  _seed_open_plan P901
  rm -rf "$(_wt P901)"
  local lock="$ROOT/.aid-o/work/plan-state/P901/plan-worktree.lock"
  bash -c "flock -x 9; sleep 8" 9>"$lock" 3>&- &
  local holder=$!
  # Give the holder time to take it, then refuse fast instead of waiting 30s.
  run bash -c "sleep 1
    cd '$ROOT'
    export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
    export AID_WORKTREE_LOCK_TIMEOUT_S=1
    exec bash '$PLAN_FSM' plan-state P901 --recreate-worktree --project-root '$ROOT' \
      --reason 'a second repair racing the one that already holds the lock'" 3>&-
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  [ "$status" -ne 0 ]
  [[ "$output" == *"another worktree transaction"* ]]
  # It did nothing at all: the deleted tree was NOT recreated. (The stale
  # registration the `rm -rf` left behind is still there — only a prune or a
  # real repair clears it, and this refusal ran neither.)
  [ ! -d "$(_wt P901)" ]
}

@test "P074 Step 11: a close landing INSIDE a repair makes the repair refuse and undo — a terminal plan never ends up holding a worktree" {
  # The worktree lock does NOT serialize this repair
  # against a close's terminal STATE TRANSITION: close flips plan_state under
  # the PLAN-STATE lock and only then attempts the worktree lock, and on a
  # timeout it defers its teardown and returns success without ever holding
  # it. So a close can land entirely between this repair's OPEN check and its
  # record, and the repair would then hand a CLOSED plan a fresh, recorded
  # worktree that survives until someone runs another close.
  #
  # The interleaving is made DETERMINISTIC rather than raced: a post-checkout
  # hook flips the state to CLOSED from inside `git worktree add`, which is
  # exactly the window — after the precondition read, before the record. The
  # fix is a compare-and-set inside the plan-state critical section that does
  # the write, so no window is left for a re-check to miss.
  _mk_project
  _seed_open_plan P901
  rm -rf "$(_wt P901)"
  # Start from NO pointer, so "nothing recorded" below means this repair
  # recorded nothing, not that it happened to rewrite the same value.
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_set_worktree_path P901 ''"
  cat > "$ROOT/.git/hooks/post-checkout" <<EOF
#!/usr/bin/env bash
yq -i '.plan_state = "CLOSED"' '$ROOT/.aid-o/work/plan-state/P901/plan-state.yaml' 2>/dev/null || true
exit 0
EOF
  chmod +x "$ROOT/.git/hooks/post-checkout"

  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" \
    --reason "repairing the worktree while a close lands in the middle of it"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reached a terminal state"* ]]
  [[ "$output" == *"removed again"* ]]
  [[ "$output" != *"RECREATED"* ]]
  # Nothing recorded, and the tree it had just created is gone: the CLOSED
  # plan holds no execution worktree.
  [ -z "$(_recorded P901)" ]
  [ ! -d "$(_wt P901)" ]
  ! _registered P901
}

@test "P074 Step 11: --recreate-worktree fails loudly when the repair CANNOT be audited" {
  # Review F8: both audit writes were `|| true`, so a repair with no forensic
  # trail at all still printed "Repair logged". Both sinks are made
  # unwritable for every uid (a directory where a file must be appended).
  _mk_project
  _seed_open_plan P901
  rm -rf "$(_wt P901)"
  mkdir -p "$ROOT/.aid-o/work/plan-final/P901/timeline.jsonl"
  mkdir -p "$ROOT/.aid-o/work/audit-log.jsonl"
  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" \
    --reason "restoring the worktree while the audit sinks are unwritable"
  [ "$status" -ne 0 ]
  [[ "$output" != *"Repair logged"* ]]
  [[ "$output" == *"AUDIT INCOMPLETE"* ]]
  [[ "$output" == *"timeline.jsonl"* ]]
  [[ "$output" == *"audit-log.jsonl"* ]]
  # The repair itself is NOT rolled back — it is applied, recorded, unaudited.
  [ -d "$(_wt P901)" ]
  [ "$(_recorded P901)" = "$(_wt P901)" ]
}

@test "P074 Step 11: --recreate-worktree refuses a canonical worktree that is NOT on the plan branch" {
  # Review F6: "something is registered here" was accepted as proof it was the
  # plan's tree, so a checkout of another branch at the canonical path got
  # recorded as the plan's execution worktree.
  _mk_project
  _seed_open_plan P901
  _in_root "git -C '$(_wt P901)' checkout -q -b sidetrack"
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_set_worktree_path P901 ''"
  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" \
    --reason "trying to adopt a tree that wandered off the plan branch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not plan/P901"* ]]
  [ -z "$(_recorded P901)" ]
  # Neither adopted nor destroyed.
  run bash -c "git -C '$(_wt P901)' symbolic-ref --short HEAD" 3>&-
  [ "$output" = "sidetrack" ]
}

@test "P074 Step 11: --recreate-worktree on a CLOSED plan refuses" {
  _mk_project
  _seed_aborted_plan P901
  run _pf plan-close P901 --project-root "$ROOT" \
    --force --force-reason "test: close the plan so recreate has a terminal plan to refuse"
  [ "$status" -eq 0 ]
  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" \
    --reason "trying to resurrect a worktree for a plan that is already done"
  [ "$status" -ne 0 ]
  [[ "$output" == *"a terminal plan has no execution left to do"* ]]
  [ ! -d "$(_wt P901)" ]
}

@test "P074 Step 11: --recreate-worktree refuses a missing plan branch and a throwaway reason" {
  _mk_project
  _seed_open_plan P901
  # Reason discipline first (nothing else has run yet).
  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" --reason "too short"
  [ "$status" -eq 2 ]
  [[ "$output" == *"at least 20 characters"* ]]
  # Branch gone (post-merge cleanup already deleted it).
  git -C "$ROOT" worktree remove --force "$(_wt P901)"
  git -C "$ROOT" branch -D plan/P901
  run _pf plan-state P901 --recreate-worktree --project-root "$ROOT" \
    --reason "the plan branch was cleaned up after the merge landed"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing to execute; this plan needs no worktree"* ]]
}
