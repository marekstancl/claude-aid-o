#!/usr/bin/env bats
# aid-tier: t2
# test-aid-audit-tests-cli.bats — P066 Step 8.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PARSER="$AID_PLUGIN_PATH/scripts/aid-audit-tests-cli-parse.sh"

  FIXTURE_PROJECT="$TEST_TMPDIR/fixture-project"
  mkdir -p "$FIXTURE_PROJECT/tests"
  local at='@test'
  printf '#!/usr/bin/env bats\n%s "case" {\n  [ 1 -eq 1 ]\n}\n' "$at" > "$FIXTURE_PROJECT/tests/suite.bats"
}

teardown() {
  teardown_test_evidence_dir
}

@test "defaults: scope=repo, mode=static when no arguments given" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scope == "repo" and .mode == "static"' >/dev/null
}

@test "unknown option fails loudly with exit code 2" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --bogus-flag
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "nonexistent path: scope fails loudly with exit code 3" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:does/not/exist"
  [ "$status" -eq 3 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "a real, existing path: scope succeeds" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:tests"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scope == "path:tests"' >/dev/null
}

@test "--mode full without --budget-minutes is a hard error (exit code 4), never a default" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --mode full
  [ "$status" -eq 4 ]
  [[ "$output" == *"--budget-minutes"* ]]
}

@test "--mode full with --budget-minutes succeeds" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --mode full --budget-minutes 45
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "full" and .budget_minutes == 45' >/dev/null
}

@test "--max-agents 0 fails loudly with exit code 5" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --max-agents 0
  [ "$status" -eq 5 ]
}

@test "an unrecognized runner:<id> fails loudly (exit code 6) and lists the actually-discovered families" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "runner:nonexistent-runner"
  [ "$status" -eq 6 ]
  [[ "$output" == *"bats"* ]]
}

@test "a real, discovered runner:<id> succeeds" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "runner:bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scope == "runner:bats"' >/dev/null
}

@test "an invalid --mode value fails loudly with exit code 9" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --mode bogus
  [ "$status" -eq 9 ]
}

@test "a non-numeric --budget-minutes fails loudly with exit code 7" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --budget-minutes not-a-number
  [ "$status" -eq 7 ]
}

@test "a non-numeric --repeat fails loudly with exit code 8" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --repeat not-a-number
  [ "$status" -eq 8 ]
}

@test "an option missing its value fails loudly instead of crashing bash's own arity check" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --mode
  [ "$status" -eq 2 ]
  [[ "$output" == *"--mode requires a value"* ]]

  run "$PARSER" --project-root "$FIXTURE_PROJECT" --max-agents
  [ "$status" -eq 2 ]
  [[ "$output" == *"--max-agents requires a value"* ]]
}

@test "path: scope rejects a sibling directory outside the project root (path traversal)" {
  mkdir -p "$TEST_TMPDIR/sibling-project"
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:../sibling-project"
  [ "$status" -eq 3 ]
  [[ "$output" == *"outside project root"* ]]
}

@test "path: scope rejects the project root itself (must be a real subdirectory)" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:."
  [ "$status" -eq 3 ]
}

@test "path: scope rejects a regular file (must be a directory)" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:tests/suite.bats"
  [ "$status" -eq 3 ]
}

@test "a nonexistent --project-root fails loudly (exit code 10) even with the default repo scope" {
  # PM-confirmed blocker: project_root existence was previously checked
  # only for path:/runner: scopes — the default "repo" scope silently
  # accepted a nonexistent project root.
  run "$PARSER" --project-root "$TEST_TMPDIR/no/such/directory"
  [ "$status" -eq 10 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "a valid, existing --project-root is returned canonical in the result JSON" {
  # PM-confirmed blocker: project_root was never returned in the output at
  # all, so a downstream controller had no guaranteed value to pass to the
  # scanner/dispatch/measurement steps.
  run "$PARSER" --project-root "$FIXTURE_PROJECT"
  [ "$status" -eq 0 ]
  local returned_root canonical_root
  returned_root="$(echo "$output" | jq -r '.project_root')"
  canonical_root="$(cd "$FIXTURE_PROJECT" && pwd -P)"
  [ "$returned_root" = "$canonical_root" ]
}

@test "--write-plan and --resume are parsed correctly" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --write-plan --resume "audit-123"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.write_plan == true and .resume_id == "audit-123"' >/dev/null
}

# ─── P072 Step 8: the disposable-clone precondition ────────────────────────
#
# `.aid-o/` is gitignored, so a clone made for a disposable audit carries no
# config unless someone copied it. Without it every declared-command gate
# disappears from discovery and the audit reports a smaller portfolio than the
# project has — confidently, with nothing to show anything is missing.

# _clone_project <invoker> <clone> — a REAL clone of a REAL repo whose
# .aid-o/ is gitignored, which is the only shape that reproduces the defect.
# Every clone test goes through this, so none can pass without one.
_clone_project() {
  local invoker="$1" clone="$2"
  _cfg_project "$invoker"
  git -C "$invoker" init -q
  git -C "$invoker" config user.email t@t; git -C "$invoker" config user.name t
  printf '.aid-o/\n' > "$invoker/.gitignore"
  echo x > "$invoker/f"; git -C "$invoker" add -A; git -C "$invoker" commit -qm init
  git clone -q "$invoker" "$clone" 2>/dev/null
  [ ! -f "$clone/.aid-o/config/execution.yaml" ]
}

_cfg_project() {
  local d="$1"; mkdir -p "$d/.aid-o/config"
  printf 'gates:\n  x:\n    command: "true"\n' > "$d/.aid-o/config/execution.yaml"
}

@test "P072: a real CLONE with no config exits 12 with the exact cp command" {
  local invoker="$TEST_TMPDIR/invoker" clone="$TEST_TMPDIR/clone"
  _clone_project "$invoker" "$clone"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$clone'"
  [ "$status" -eq 12 ]
  [[ "$output" == *"cp -r '$invoker/.aid-o/config' '$clone/.aid-o/config'"* ]]
  [[ "$output" == *"silently vanish"* ]]
  [[ "$output" == *"checkout of this same repository"* ]]
}

@test "P072: a real clone that HAS been prepared passes" {
  # Must be a genuine clone, then given the config — otherwise it never
  # exercises the clone detection it claims to clear.
  local invoker="$TEST_TMPDIR/invoker2" clone="$TEST_TMPDIR/clone2"
  _clone_project "$invoker" "$clone"
  mkdir -p "$clone/.aid-o/config"
  cp "$invoker/.aid-o/config/execution.yaml" "$clone/.aid-o/config/"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$clone'"
  [ "$status" -eq 0 ]
}

@test "P072: --allow-missing-config downgrades exit 12 to a warning that names the consequence" {
  local invoker="$TEST_TMPDIR/invoker3" clone="$TEST_TMPDIR/clone3"
  _clone_project "$invoker" "$clone"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$clone' --allow-missing-config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"declared-command gate will be ABSENT"* ]]
}

@test "P072: an unreadable config exits 13, distinct from the missing-config 12" {
  # A broken symlink is 'present but unusable'. `-e` follows the link, so a
  # naive check reads it as absent and tells the operator to copy a config
  # over a file that is already there — the wrong fix for the wrong diagnosis.
  local invoker="$TEST_TMPDIR/invoker4" target="$TEST_TMPDIR/target4"
  _cfg_project "$invoker"
  mkdir -p "$target/.aid-o/config"
  ln -s /nonexistent/execution.yaml "$target/.aid-o/config/execution.yaml"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$target'"
  [ "$status" -eq 13 ]
  [[ "$output" == *"cannot be read"* ]]
  [[ "$output" != *"cp -r"* ]]
}

@test "P072: an UNRELATED un-configured project is audited silently, not failed" {
  # Auditing a project with no declared gates is ordinary. Failing it — or
  # warning on every such run — would break every fixture-based audit and
  # train people to ignore the two diagnostics that do matter.
  local invoker="$TEST_TMPDIR/invoker5" target="$TEST_TMPDIR/target5"
  _cfg_project "$invoker"; mkdir -p "$target"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$target'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"* ]]
  echo "$output" | jq -e '.project_root' >/dev/null
}

@test "P072: --allow-missing-config on a real clone downgrades the hard failure" {
  local invoker="$TEST_TMPDIR/invoker6" clone="$TEST_TMPDIR/clone6"
  _clone_project "$invoker" "$clone"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$clone' --allow-missing-config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
}

# ─── Step 8 hardening (Codex review) ───────────────────────────────────────

@test "P072: identity is the ROOT COMMIT, so an ssh-vs-https origin still detects the clone" {
  # Comparing origin URLs would miss this: `git@host:o/r` and a local path are
  # the same repository written two ways.
  local invoker="$TEST_TMPDIR/inv-ssh" clone="$TEST_TMPDIR/clone-ssh"
  _clone_project "$invoker" "$clone"
  git -C "$clone" remote set-url origin "git@example.com:org/repo.git"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$clone'"
  [ "$status" -eq 12 ]
}

@test "P072: invoking from a SUBDIRECTORY still resolves the invoking project correctly" {
  # `pwd` would look for the config in the subdirectory and find none.
  local invoker="$TEST_TMPDIR/inv-sub" clone="$TEST_TMPDIR/clone-sub"
  _clone_project "$invoker" "$clone"
  mkdir -p "$invoker/deep/nested"

  run bash -c "cd '$invoker/deep/nested' && bash '$PARSER' --project-root '$clone'"
  [ "$status" -eq 12 ]
}

@test "P072: an UNRELATED git repository is not mistaken for a clone" {
  local invoker="$TEST_TMPDIR/inv-unrel" other="$TEST_TMPDIR/other-repo"
  _cfg_project "$invoker"
  git -C "$invoker" init -q; git -C "$invoker" config user.email t@t; git -C "$invoker" config user.name t
  echo x > "$invoker/f"; git -C "$invoker" add -A; git -C "$invoker" commit -qm init
  mkdir -p "$other"; git -C "$other" init -q
  git -C "$other" config user.email t@t; git -C "$other" config user.name t
  echo y > "$other/g"; git -C "$other" add -A; git -C "$other" commit -qm other

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$other'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"* ]]
}

@test "P072: a non-traversable ancestor is exit 13, never the copy-the-config 12" {
  local invoker="$TEST_TMPDIR/inv-perm" target="$TEST_TMPDIR/target-perm"
  _cfg_project "$invoker"
  mkdir -p "$target/.aid-o/config"
  chmod 000 "$target/.aid-o"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$target'"
  chmod 755 "$target/.aid-o"
  [ "$status" -eq 13 ]
  [[ "$output" == *"permissions problem"* ]]
  [[ "$output" != *"cp -r"* ]]
}

@test "P072: a config path that is a DIRECTORY is exit 13" {
  local invoker="$TEST_TMPDIR/inv-dir" target="$TEST_TMPDIR/target-dir"
  _cfg_project "$invoker"
  mkdir -p "$target/.aid-o/config/execution.yaml"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$target'"
  [ "$status" -eq 13 ]
}

@test "P072: the suggested fix creates the parent and is shell-quoted" {
  local invoker="$TEST_TMPDIR/inv-fix" clone="$TEST_TMPDIR/clone-fix"
  _clone_project "$invoker" "$clone"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$clone'"
  [ "$status" -eq 12 ]
  [[ "$output" == *"mkdir -p '$clone/.aid-o'"* ]]
  [[ "$output" == *"cp -r '$invoker/.aid-o/config' '$clone/.aid-o/config'"* ]]
}

@test "P072: --allow-missing-config does NOT downgrade exit 13" {
  # A permissions or wrong-type problem is not something the operator can
  # choose to ignore: the config is there and broken, not absent.
  local invoker="$TEST_TMPDIR/inv-13" target="$TEST_TMPDIR/target-13"
  _cfg_project "$invoker"
  mkdir -p "$target/.aid-o/config"
  ln -s /nonexistent/x "$target/.aid-o/config/execution.yaml"

  run bash -c "cd '$invoker' && bash '$PARSER' --project-root '$target' --allow-missing-config"
  [ "$status" -eq 13 ]
}
