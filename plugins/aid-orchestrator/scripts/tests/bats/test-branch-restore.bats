#!/usr/bin/env bats
# aid-tier: t2
# test-branch-restore.bats — P073 Step 6: hard stop with recovery instructions
# when batch generation cannot restore the original branch.
#
# `aid-json-to-run.sh` auto-inits the FSM, which checks out a `task/<epic>/...`
# branch, and then restores the branch generation started on. When that
# restore FAILED it only printed a WARNING, so every follow-on phase (queue,
# report, a further EPIC) kept generating against a checkout the operator
# never chose. The failure now exits 4 at the point of failure, and
# aid-auto-pipeline.sh propagates that distinctly. (4, not the 3 the plan
# named: aid-json-to-run.sh already returns 3 for ordinary I/O failures, so
# reusing it would make an unrelated I/O error print a misleading "git
# checkout" recovery instruction — found while reviewing this step.)
#
# FAULT INJECTION: the restore failure is produced by a real git mechanism, not
# a stub. A `post-checkout` hook deletes the original branch the moment the FSM
# switches to its task branch, so the subsequent `git checkout <original>`
# genuinely fails ("pathspec did not match"). That is exactly the plan's named
# fixture case: original branch deleted mid-run.
#
# The restore path is only REACHED when the FSM actually switches branches,
# which its PRE-FLIGHT does when generation starts on `main`. Starting on a
# feature branch, the FSM warns and stays put, so there is nothing to restore —
# both cases are asserted below.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PIPELINE="$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh"
  FIXTURES="$AID_PLUGIN_PATH/scripts/tests/fixtures"
  export PIPELINE FIXTURES
  WS="$TEST_PROJECT_ROOT/ws"
  export WS
}

teardown() {
  teardown_test_evidence_dir
}

# _make_ws <branch> — a committed, clean git workspace on <branch> with the
# .aid-o skeleton the pipeline expects.
_make_ws() {
  local branch="$1"
  mkdir -p "$WS/.aid-o/plans" "$WS/.aid-o/tasks" "$WS/.aid-o/config" \
           "$WS/.aid-o/work/evidence" "$WS/.aid-o/work/runs"
  printf 'counter: 0\n' > "$WS/.aid-o/config/counter.yaml"
  # IMP-503 (v2.85.1): DoD gate resolution refuses without a real execution.yaml.
  printf 'gates: {}\n' > "$WS/.aid-o/config/execution.yaml"
  printf 'seed\n' > "$WS/README.md"
  (
    cd "$WS"
    git init -q
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git checkout -q -b "$branch" 2>/dev/null || git branch -m "$branch"
    git add -A
    git commit -q -m "seed workspace"
  )
}

# _seed_plan — copy the fixture plan in AND COMMIT IT on the current branch.
#
# P073 Step 11 (2026-08-05) added a committed-source preflight: generation
# refuses a source plan that is not committed on the target branch, or that
# differs from the worktree copy. Every case here copied the plan in and left it
# uncommitted, so all seven have been failing with "source plan is not committed
# on main" ever since — unseen, because this suite is `aid-tier: t2` and the
# nightly has not completed since 2026-08-11.
# _seed_plan_unshared — the plan in, DELIBERATELY untracked.
#
# For the two cases whose workspace has no `main` at all (a feature branch, a
# detached HEAD), committing the plan is the wrong fixture: the preflight then
# correctly refuses with "source plan is tracked but the target branch 'main'
# does not exist". Its message names the other legitimate shape — "or gitignore
# the plan if it is deliberately unshared" — and that is what these two cases
# are: the branch is the subject, the plan is scenery.
_seed_plan_unshared() {
  printf '.aid-o/\n' > "$WS/.gitignore"
  git -C "$WS" add -- .gitignore
  git -C "$WS" commit -q -m "the runtime area is private to this workspace"
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$WS/.aid-o/plans/plan.md"
}

_seed_plan() {
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$WS/.aid-o/plans/plan.md"
  git -C "$WS" add -- .aid-o/plans/plan.md
  git -C "$WS" commit -q -m "the source plan, committed — the generator refuses an uncommitted one"
}

# _break_restore <branch> — install a post-checkout hook that deletes <branch>
# as soon as the FSM switches to its task branch, so the restore genuinely
# cannot succeed. The hook removes itself so it fires exactly once.
_break_restore() {
  local branch="$1"
  mkdir -p "$WS/.git/hooks"
  cat > "$WS/.git/hooks/post-checkout" <<EOF
#!/usr/bin/env bash
# Fires after aid-fsm.sh init switches to task/<epic>/... — delete the branch
# generation started on so the restore has nothing to check out.
new_branch="\$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
case "\$new_branch" in
  task/*)
    rm -f "\$(git rev-parse --git-dir)/hooks/post-checkout"
    git branch -D "$branch" >/dev/null 2>&1 || true
    ;;
esac
exit 0
EOF
  chmod +x "$WS/.git/hooks/post-checkout"
}

_run_pipeline() {
  ( cd "$WS" && bash "$PIPELINE" --plan "$1" --queue-mode chain )
}

# ─── the failure path ─────────────────────────────────────────────────────

@test "P073 Step 6: a failed branch restore exits 4 with a git-checkout recovery instruction" {
  _make_ws "main"
  _seed_plan
  _break_restore "main"

  run _run_pipeline "$WS/.aid-o/plans/plan.md"
  [ "$status" -eq 4 ]
  [[ "$output" == *"instead of 'main'"* ]]
  [[ "$output" == *"git checkout main"* ]]
}

@test "P073 Step 6: after a failed restore the queue phase does NOT run" {
  _make_ws "main"
  _seed_plan
  _break_restore "main"

  run _run_pipeline "$WS/.aid-o/plans/plan.md"
  [ "$status" -eq 4 ]
  # The pipeline names the phases it skipped rather than continuing silently.
  [[ "$output" == *"were NOT run"* || "$output" == *"no further phase was initialised"* ]]
  # No queue entry was written for the aborted run.
  if [[ -f "$WS/.aid-o/config/queue.yaml" ]]; then
    run grep -c 'epic_id' "$WS/.aid-o/config/queue.yaml"
    [ "$output" = "0" ]
  fi
}

@test "P073 Step 6: the generated artifacts from the COMPLETED phase are left in place" {
  # Only continuation is stopped — what was generated is valid and is not
  # rolled back, so the operator can rerun the follow-on action after fixing
  # the checkout rather than regenerating from scratch.
  _make_ws "main"
  _seed_plan
  _break_restore "main"

  run _run_pipeline "$WS/.aid-o/plans/plan.md"
  [ "$status" -eq 4 ]
  run bash -c "find '$WS/.aid-o' -name 'plan.json' | wc -l"
  [ "$output" -ge 1 ]
}

# ─── the success path is unchanged ────────────────────────────────────────

@test "P073 Step 6: a run started on a feature branch ends on that branch with exit 0 (the FSM never switches, so no restore is needed)" {
  _make_ws "feature/x"
  _seed_plan_unshared

  run _run_pipeline "$WS/.aid-o/plans/plan.md"
  [ "$status" -eq 0 ]
  run bash -c "cd '$WS' && git rev-parse --abbrev-ref HEAD"
  [ "$output" = "feature/x" ]
}

@test "P073 Step 6: a run started on main is restored to main, reported as a restore and never as an ERROR" {
  _make_ws "main"
  _seed_plan

  run _run_pipeline "$WS/.aid-o/plans/plan.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"restored generation branch 'main'"* ]]
  [[ "$output" != *"could not restore branch"* ]]
  run bash -c "cd '$WS' && git rev-parse --abbrev-ref HEAD"
  [ "$output" = "main" ]
}

# ─── detached HEAD ────────────────────────────────────────────────────────

@test "P073 Step 6: a detached-HEAD start is refused BEFORE any generation, so no restore is ever attempted" {
  # The plan's edge-case note expected the restore guard to skip silently on a
  # detached HEAD; the real behaviour is stricter and better — aid-json-to-run
  # refuses up front, so there is no window in which a restore could fail.
  _make_ws "feature/x"
  _seed_plan_unshared
  ( cd "$WS" && git checkout -q --detach HEAD )

  run _run_pipeline "$WS/.aid-o/plans/plan.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached HEAD"* || "$output" == *"cannot determine current git branch"* ]]
  # Not the restore-failure code — this is a different, earlier refusal.
  [ "$status" -ne 4 ]
}

# ─── Codex-review findings on the first cut of this step ───────────────────

@test "P073 Step 6 (review finding): an ordinary I/O failure keeps its own exit 3 and never claims a branch-restore problem" {
  # aid-json-to-run.sh already used 3 for I/O failures. Had the restore
  # failure reused it, this run would print the pipeline's "Branch restore
  # failed / git checkout" instruction for a completely unrelated fault.
  _make_ws "main"
  _seed_plan

  run bash -c "cd '$WS' && bash '$AID_PLUGIN_PATH/scripts/aid-json-to-run.sh' \
      --plan-json '$FIXTURES/minimal-plan.json' \
      --run-template '$AID_PLUGIN_PATH/defaults/templates/run-new-feature.md' \
      --epic '$FIXTURES/E-TEST-001-1_1-minimal-test-plan.md' \
      --output-dir /proc/definitely-not-writable \
      --run-id R-TEST-1"
  [ "$status" -ne 4 ]
  [[ "$output" != *"git checkout"* ]]
}

@test "P073 Step 6 (review finding): the restore failure is diagnosed WITHOUT a second checkout attempt" {
  # An earlier cut re-ran `git checkout` purely to surface the error text.
  # That retry is stateful: if it succeeded, the branch was actually restored
  # while the script still reported failure and stopped the pipeline. The
  # error is now captured from the single attempt.
  run grep -c 'git checkout "$fsm_branch" >&2' "$AID_PLUGIN_PATH/scripts/aid-json-to-run.sh"
  [ "$output" = "0" ]
  run grep -c 'fsm_restore_err="$(git checkout "$fsm_branch" 2>&1)"' "$AID_PLUGIN_PATH/scripts/aid-json-to-run.sh"
  [ "$output" = "1" ]
}
