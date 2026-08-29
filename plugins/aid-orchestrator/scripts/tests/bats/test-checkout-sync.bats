#!/usr/bin/env bats
# aid-tier: t0
# _aid_lc_sync_checkout_of — a ref moved by plumbing must not leave the
# checkout that has the branch out at the pre-write state (WAN P099 #20:
# two one-file commits silently reverted a plan merge).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH AID_TEST_MODE=1
  T="$(mktemp -d)"; cd "$T"
  git init -q -b main primary && cd primary
  git config user.email t@t; git config user.name t
  echo one > a.txt; git add a.txt; git commit -qm one
  OLD="$(git rev-parse HEAD)"
  # a commit built by plumbing, published on main by update-ref — no checkout
  git worktree add -q ../side -b side >/dev/null 2>&1
  ( cd ../side && echo two > a.txt && echo new > b.txt && git add . && git commit -qm two )
  NEW="$(git -C ../side rev-parse HEAD)"
  git update-ref refs/heads/main "$NEW" "$OLD"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
}
teardown() { rm -rf "$T"; }

@test "the checkout holding the branch is brought forward, so its next commit does not revert the write" {
  [[ "$(cat a.txt)" == "one" ]]                       # stale before
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"brought forward"* ]]
  [[ "$(cat a.txt)" == "two" ]]; [[ -f b.txt ]]
  [[ -z "$(git status --porcelain)" ]]                  # index matches too
}

@test "an overlapping local edit is not overwritten — a loud warning names the command instead" {
  echo mine > a.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* && "$output" == *"reset --merge"* ]]
  [[ "$(cat a.txt)" == "mine" ]]
}

@test "a branch checked out nowhere is left alone" {
  git update-ref refs/heads/other "$OLD"
  run _aid_lc_sync_checkout_of "$T/side" other "$OLD" "$NEW"
  [ "$status" -eq 0 ]; [[ -z "$output" ]]
}
