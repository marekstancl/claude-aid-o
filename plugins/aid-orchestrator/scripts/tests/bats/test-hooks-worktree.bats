#!/usr/bin/env bats
# aid-tier: t2
# test-hooks-worktree.bats — P074 Step 2: worktree-safe git hooks.
#
# THE GROUNDED FAILURE MODE UNDER TEST: hooks live in the COMMON .git/hooks and
# therefore fire from every linked worktree, but the pre-P074 pre-commit
# template read `.aid-o` relative to $PWD. `.aid-o/` is gitignored, so a linked
# worktree has none — the run-discovery scan found nothing and the fail-open
# design turned a genuine scope violation into a silent no-op pass. The
# template now resolves the state root inline (`_aid_state_root`, a copy of
# lib/aid-roots.sh `aid_state_root` minus caching), so the guard genuinely
# fires from worktrees. These tests drive REAL `git commit` invocations against
# INSTALLED hooks — proving the hook fires with git's own cwd/stdin contract,
# not just when hand-invoked.
#
# Scenarios (map to the plan):
#   1. worktree commit violating the run scope IS blocked (regression closed)
#   2. worktree compliant commit passes
#   3. the same violation from the primary checkout is blocked identically
#   4. repo with no .aid-o anywhere keeps the fail-open pass, now DISCLOSED by
#      exactly one stderr warning line (AC wins over the byte-identical edge
#      case per controller decision); every path where .aid-o exists stays
#      warning-free
#   5. evidence-dir staging still in scope from the primary (relative-scope
#      preservation guard for the now-absolute evidence path)
#   6. pre-push: resolver preamble is comment-only — no behavioural change
#
# FD-3 HYGIENE: every `git commit` spawns the installed hook; run those with
# `3>&-` so no child can hold bats' report fd. After any edit verify:
#   bats --tap test-hooks-worktree.bats | grep -cE '^(ok|not ok)'   # == 6

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PRECOMMIT="$AID_PLUGIN_PATH/defaults/hooks/pre-commit"
  PREPUSH="$AID_PLUGIN_PATH/defaults/hooks/pre-push"
  export PRECOMMIT PREPUSH
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  unset AID_PROJECT_ROOT
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# _mk_primary <dir> — committed primary checkout, .aid-o skeleton gitignored
# exactly like a real AID project (so a linked worktree gets NO .aid-o).
_mk_primary() {
  local d="$1"
  mkdir -p "$d/.aid-o/work/evidence" "$d/.aid-o/work/runs" "$d/.aid-o/config"
  printf '.aid-o/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed primary"
  )
}

# _install_hooks <dir> — install both templates into the COMMON .git/hooks,
# exactly as /aid-init's template copy does.
_install_hooks() {
  cp "$PRECOMMIT" "$1/.git/hooks/pre-commit"
  cp "$PREPUSH" "$1/.git/hooks/pre-push"
  chmod +x "$1/.git/hooks/pre-commit" "$1/.git/hooks/pre-push"
}

# _seed_run <primary> <branch> — active EXECUTE run governed by <branch>:
# state file + plan.json in the PRIMARY .aid-o (step 0 scope = src/ok.txt).
_seed_run() {
  local d="$1" branch="$2" ev="$1/.aid-o/work/evidence/E-777-1_1/R-777"
  mkdir -p "$ev"
  cat > "$ev/plan.json" <<'JSON'
{ "steps": [ { "id": "s0", "allowed_paths": ["src/ok.txt"] } ] }
JSON
  {
    echo "epic_id: E-777-1_1"
    echo "run_id: R-777"
    echo "state: EXECUTE"
    echo "current_step: 0"
    echo "total_steps: 1"
    echo "branch: $branch"
    echo "base_commit: HEAD"
  } > "$ev/fsm-state.yaml"
}

# _stage_in <tree> <file> — create + git add <file> inside <tree>.
_stage_in() {
  mkdir -p "$1/$(dirname "$2")"
  printf 'x\n' > "$1/$2"
  git -C "$1" add "$2"
}

@test "worktree commit violating the run scope is BLOCKED by the installed hook (regression closed)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hooks "$TEST_TMPDIR/primary"
  _seed_run "$TEST_TMPDIR/primary" task/E-777/main
  git -C "$TEST_TMPDIR/primary" worktree add -q "$TEST_TMPDIR/wt" -b task/E-777/main
  # Sanity: the worktree really has NO .aid-o — pre-P074 this is exactly the
  # shape where the guard silently no-opped.
  [ ! -e "$TEST_TMPDIR/wt/.aid-o" ]
  _stage_in "$TEST_TMPDIR/wt" src/rogue.txt
  run bash -c "cd '$TEST_TMPDIR/wt' && git commit -m 'rogue from worktree'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"Commit blocked"* ]]
  [[ "$output" == *"outside EXECUTE step 0 scope"* ]]
  [[ "$output" == *"src/rogue.txt"* ]]
  [[ "$output" != *"guard skipped"* ]]   # .aid-o exists → no skip warning
  # And nothing was committed.
  run git -C "$TEST_TMPDIR/wt" log --oneline -1
  [[ "$output" == *"seed primary"* ]]
}

@test "worktree compliant commit passes through the installed hook" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hooks "$TEST_TMPDIR/primary"
  _seed_run "$TEST_TMPDIR/primary" task/E-777/main
  git -C "$TEST_TMPDIR/primary" worktree add -q "$TEST_TMPDIR/wt" -b task/E-777/main
  _stage_in "$TEST_TMPDIR/wt" src/ok.txt
  run bash -c "cd '$TEST_TMPDIR/wt' && git commit -m 'in-scope from worktree'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" != *"guard skipped"* ]]   # .aid-o exists → no skip warning
  run git -C "$TEST_TMPDIR/wt" log --oneline -1
  [[ "$output" == *"in-scope from worktree"* ]]
}

@test "the same scope violation from the PRIMARY checkout is blocked identically (behaviour parity)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hooks "$TEST_TMPDIR/primary"
  _seed_run "$TEST_TMPDIR/primary" task/E-777/main
  git -C "$TEST_TMPDIR/primary" checkout -q -b task/E-777/main
  _stage_in "$TEST_TMPDIR/primary" src/rogue.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'rogue from primary'" 3>&-
  [ "$status" -ne 0 ]
  # Identical guard identity: same block banner, same scope label, same file.
  [[ "$output" == *"Commit blocked"* ]]
  [[ "$output" == *"outside EXECUTE step 0 scope"* ]]
  [[ "$output" == *"src/rogue.txt"* ]]
  [[ "$output" != *"guard skipped"* ]]   # .aid-o exists → no skip warning
}

@test "repo with no .aid-o anywhere keeps the fail-open pass AND discloses the skip in one warning line" {
  local d="$TEST_TMPDIR/plain"
  mkdir -p "$d"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m seed
  )
  _install_hooks "$d"
  _stage_in "$d" src/anything.txt
  run bash -c "cd '$d' && git commit -m 'no aid workspace'" 3>&-
  [ "$status" -eq 0 ]
  # Exactly ONE disclosure line, naming the resolved root ($PWD fallback here).
  [[ "$output" == *"AID pre-commit: no .aid-o workspace found at"* ]]
  [[ "$output" == *"guard skipped (fail-open)"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'guard skipped')" -eq 1 ]
  run git -C "$d" log --oneline -1
  [[ "$output" == *"no aid workspace"* ]]
}

@test "evidence-dir staging stays IN scope from the primary (absolute root did not break relative scope matching)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hooks "$TEST_TMPDIR/primary"
  _seed_run "$TEST_TMPDIR/primary" task/E-777/main
  git -C "$TEST_TMPDIR/primary" checkout -q -b task/E-777/main
  # Evidence files are gitignored in this fixture — force-add one, exactly the
  # shape a consumer with tracked evidence commits. The evidence dir is "always
  # in scope"; the resolver must not have turned that entry absolute-only.
  printf 'note\n' > "$TEST_TMPDIR/primary/.aid-o/work/evidence/E-777-1_1/R-777/note.md"
  git -C "$TEST_TMPDIR/primary" add -f .aid-o/work/evidence/E-777-1_1/R-777/note.md
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'evidence note'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" != *"guard skipped"* ]]   # .aid-o exists → no skip warning
}

@test "pre-push resolver preamble is comment-only: syntax-clean and no behavioural change" {
  # Every _aid_state_root/_AID_ROOT line in the pre-push template must be a
  # comment (the helper is shipped ready-to-use, NOT wired — the hook reads no
  # .aid-o paths today).
  run bash -c "grep -n '_aid_state_root\|_AID_ROOT' '$PREPUSH' | grep -v '^[0-9]*:#'"
  [ "$status" -ne 0 ]   # zero uncommented matches
  bash -n "$PREPUSH"
  # Behaviour: tag-less repo, empty stdin → exit 0, exactly as before.
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hooks "$TEST_TMPDIR/primary"
  run bash -c "cd '$TEST_TMPDIR/primary' && printf '' | bash .git/hooks/pre-push origin file:///dev/null" 3>&-
  [ "$status" -eq 0 ]
}
