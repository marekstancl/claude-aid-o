#!/usr/bin/env bats
# aid-tier: t0
#
# Which TREE aid-evidence-verify.sh judges.
#
# ACTA, 2026-08-31: the plan's candidate sat in its own worktree, and the tool
# reported main's head and failed `git_clean` on another session's unrelated
# work — because evidence root and working tree were one value. C4 is
# `enforcement: observe`, which is the only reason that was survivable; as a
# blocking check it could never have verified a plan-branch candidate at all.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TOOL="$PLUGIN_ROOT/scripts/aid-evidence-verify.sh"
  TMP="$(mktemp -d)"
  DIRTY="$TMP/dirty"; CLEAN="$TMP/clean"
  for d in "$DIRTY" "$CLEAN"; do
    mkdir -p "$d"
    git -C "$d" init -q .
    git -C "$d" config user.email t@t; git -C "$d" config user.name T
    git -C "$d" commit -q --allow-empty -m seed
  done
  printf 'uncommitted\n' > "$DIRTY/scratch.txt"     # only this tree is dirty
}
teardown() { rm -rf "$TMP"; }

@test "--tree decides which working tree is judged, not the evidence root" {
  run env AID_PROJECT_ROOT="$DIRTY" bash "$TOOL" --tree "$CLEAN"
  [[ "$output" == *"git_clean"* ]]
  [[ "$output" == *"pass"* ]]
  [[ "$output" != *"$DIRTY has uncommitted"* ]]
}

@test "the dirty tree still fails when it IS the tree under judgement" {
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" --tree "$DIRTY"
  [[ "$output" == *"has uncommitted changes"* ]]
}

@test "the report names the tree it looked at, and where that came from" {
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" --tree "$DIRTY"
  [[ "$output" == *"$DIRTY"* ]]
  [[ "$output" == *"tree from --tree"* ]]
}
