#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/lib/aid-worktree-env.sh
# A new plan or step worktree gets the ignored files and the setup the project names (AID 3.13.0). Defects it
# catches: a step tree without .env or its dependencies (WAN P114 26. 10., P116 28. 10. 2026), a copy that
# overwrites, follows a symlink out or takes a tracked file, a setup that runs in the source checkout, a failed
# setup nobody sees.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  source "$AID_PLUGIN_PATH/scripts/lib/aid-worktree-env.sh"
  T="$BATS_TEST_TMPDIR"; S="$T/src"; mkdir -p "$S/.aid-o/config" "$S/ui"
  git -C "$S" init -q; git -C "$S" config user.email t@t; git -C "$S" config user.name t
  printf '.env\n.aid-o/\nui/node_modules/\nsecret-link\n' > "$S/.gitignore"; echo tracked > "$S/README.md"
  git -C "$S" add -A; git -C "$S" commit -qm base
  echo "KEY=1" > "$S/.env"; echo "loose" > "$S/loose.txt"
  W="$T/tree"; git -C "$S" worktree add -q "$W" HEAD 2>/dev/null
}

_cfg() { printf '%s\n' "$@" > "$S/.aid-o/config/project.yaml"; }

@test "without the keys nothing happens and no record is written" {
  aid_worktree_env_prepare "$S" "$W" "$S"
  [ ! -e "$W/.env" ]; [ ! -e "$(aid_worktree_env_record_path "$S" "$W")" ]
}

@test "an ignored untracked file is copied; tracked, not ignored, missing, existing or escaping paths are not" {
  echo "outside" > "$T/outside.txt"; ln -s "$T/outside.txt" "$S/secret-link"
  echo "already" > "$W/README.md.local"
  _cfg 'worktree:' '  copy_untracked: [".env", "README.md", "loose.txt", "nope.env", "secret-link", "../outside.txt"]'
  run aid_worktree_env_prepare "$S" "$W" "$S"; echo "$output"; [ "$status" -eq 0 ]
  [ "$(cat "$W/.env")" = "KEY=1" ]
  local rec; rec="$(aid_worktree_env_record_path "$S" "$W")"
  [ "$(jq -r '.copies[] | "\(.path)=\(.outcome | split(":")[0])"' "$rec" | paste -sd' ')" = ".env=copied README.md=refused loose.txt=refused nope.env=skipped secret-link=refused ../outside.txt=refused" ]
  [ ! -e "$W/secret-link" ]; [ ! -e "$W/loose.txt" ]
  # a second creation never overwrites
  echo "KEY=changed" > "$W/.env"; aid_worktree_env_prepare "$S" "$W" "$S"
  [ "$(cat "$W/.env")" = "KEY=changed" ]; jq -e '.copies[0].outcome | startswith("skipped")' "$rec"
}

@test "setup runs in the new tree, never in the source; a failure is recorded and does not fail the creation" {
  _cfg 'worktree:' '  setup: ["mkdir -p ui/node_modules && pwd > ui/node_modules/where", "exit 7"]'
  run aid_worktree_env_prepare "$S" "$W" "$S"; echo "$output"; [ "$status" -eq 0 ]
  [ "$(cat "$W/ui/node_modules/where")" = "$(realpath "$W")" ]; [ ! -e "$S/ui/node_modules" ]
  local rec; rec="$(aid_worktree_env_record_path "$S" "$W")"
  [ "$(jq -c '[.setup[].exit]' "$rec")" = "[0,7]" ]; [[ "$output" == *"setup failed"*"exit 7"* ]]
}

@test "a step worktree created by the parallel dispatch gets the project's files" {
  source "$AID_PLUGIN_PATH/scripts/lib/aid-parallel-dispatch.sh"
  _cfg 'worktree:' '  copy_untracked: [".env"]'
  local wt; wt="$(cd "$S" && aid_parallel_step_worktree "$S" step_1_backend HEAD .aid-worktrees 2>/dev/null)"
  [ -n "$wt" ]; [ "$(cat "$wt/.env")" = "KEY=1" ]
}

@test "a multi-line setup command runs as one shell; removing the keys removes the old record; two trees of one name keep their own" {
  printf 'worktree:\n  setup:\n    - |\n      cd ui\n      pwd > here\n' > "$S/.aid-o/config/project.yaml"
  mkdir -p "$W/ui"; aid_worktree_env_prepare "$S" "$W" "$S" 2>/dev/null
  [ "$(cat "$W/ui/here")" = "$(realpath "$W/ui")" ]
  local rec; rec="$(aid_worktree_env_record_path "$S" "$W")"; [ -f "$rec" ]
  : > "$S/.aid-o/config/project.yaml"; aid_worktree_env_prepare "$S" "$W" "$S"; [ ! -e "$rec" ]
  mkdir -p "$T/a" "$T/b"; [ "$(aid_worktree_env_record_path "$S" "$T/a/tree")" != "$(aid_worktree_env_record_path "$S" "$T/b/tree")" ]
}
