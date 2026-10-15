#!/usr/bin/env bats
# aid-tier: t1
#
# Proves the worktree report classifies by OWNERSHIP, not by looks.
#
# Provenance: 2026-08-11. Two merged worktrees had sat outside the canonical
# path since 2 and 10 August, and two frozen CP3 trees exist that no script in
# this plugin has ever heard of. One such orphan took down the shell-suite
# adapter that morning. The first version of the finding claimed AID never
# cleans up at all — it does, for what it owns — so these cases pin the real
# distinction: owned trees are somebody's job, everything else is nobody's.

setup() {
  REPORT="${BATS_TEST_DIRNAME}/../../aid-worktree-report.sh"
  TMP="$(mktemp -d)"
  REPO="$TMP/repo"
  git init -q "$REPO"
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  echo x > "$REPO/f"
  git -C "$REPO" add f
  git -C "$REPO" commit -qm init
  git -C "$REPO" branch -M main
}

teardown() {
  # Remove worktrees before the tree, or git leaves registrations behind.
  git -C "$REPO" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' \
    | while read -r w; do [[ "$w" == "$REPO" ]] || git -C "$REPO" worktree remove --force "$w" 2>/dev/null; done
  rm -rf "$TMP"
}

@test "a lone main checkout has nothing to clean" {
  run bash "$REPORT" --root "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"zadna k uklizeni"* ]]
}

@test "a tree on the canonical path is 'owned' and never stale" {
  git -C "$REPO" branch -q plan/P001
  git -C "$REPO" worktree add -q "$REPO/.aid-worktrees/plan-P001" plan/P001
  run bash "$REPORT" --root "$REPO" --stale-days 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"owned"* ]]
  [[ "$output" != *"plan-P001"*"K UKLIZENI"* ]]
}

@test "a tree outside the canonical path is 'foreign'" {
  git -C "$REPO" branch -q side
  git -C "$REPO" worktree add -q "$TMP/elsewhere" side
  run bash "$REPORT" --root "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"foreign"* ]]
}

@test "a foreign tree is flagged only when merged, clean AND old enough" {
  git -C "$REPO" branch -q side
  git -C "$REPO" worktree add -q "$TMP/elsewhere" side   # merged (no new commits), clean
  # age 0 with a 7-day threshold: not yet stale
  run bash "$REPORT" --root "$REPO" --stale-days 7
  [[ "$output" != *"K UKLIZENI"* ]]
  # same tree, threshold 0: now stale
  run bash "$REPORT" --root "$REPO" --stale-days 0
  [[ "$output" == *"K UKLIZENI"* ]]
}

@test "a foreign tree with unmerged work is never flagged, however old" {
  git -C "$REPO" branch -q side
  git -C "$REPO" worktree add -q "$TMP/elsewhere" side
  echo new > "$TMP/elsewhere/g"
  git -C "$TMP/elsewhere" add g
  git -C "$TMP/elsewhere" commit -qm "unmerged work"
  run bash "$REPORT" --root "$REPO" --stale-days 0
  [[ "$output" != *"K UKLIZENI"* ]]
}

@test "a foreign tree with uncommitted changes is never flagged" {
  git -C "$REPO" branch -q side
  git -C "$REPO" worktree add -q "$TMP/elsewhere" side
  echo dirty > "$TMP/elsewhere/f"
  run bash "$REPORT" --root "$REPO" --stale-days 0
  [[ "$output" != *"K UKLIZENI"* ]]
}

@test "a frozen CP3 tree is classified as evidence and ages on time alone" {
  head="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" worktree add -q --detach "$REPO/.aid-worktrees/cp3-frozen-E-1_1" "$head"
  run bash "$REPORT" --root "$REPO" --stale-days 7
  [[ "$output" == *"frozen"* ]]
  [[ "$output" != *"K UKLIZENI"* ]]
  run bash "$REPORT" --root "$REPO" --stale-days 0
  [[ "$output" == *"K UKLIZENI"* ]]
  [[ "$output" == *"dukazni material"* ]]
}

@test "the report never deletes anything" {
  git -C "$REPO" branch -q side
  git -C "$REPO" worktree add -q "$TMP/elsewhere" side
  bash "$REPORT" --root "$REPO" --stale-days 0 >/dev/null
  [ -d "$TMP/elsewhere" ]
  run git -C "$REPO" worktree list
  [[ "$output" == *"elsewhere"* ]]
}

@test "a finding is not a failure of the reporter" {
  git -C "$REPO" branch -q side
  git -C "$REPO" worktree add -q "$TMP/elsewhere" side
  run bash "$REPORT" --root "$REPO" --stale-days 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"K UKLIZENI"* ]]
}

@test "--json emits a parseable object with the stale count" {
  git -C "$REPO" branch -q side
  git -C "$REPO" worktree add -q "$TMP/elsewhere" side
  run bash "$REPORT" --root "$REPO" --stale-days 0 --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stale_count == 1' >/dev/null
  echo "$output" | jq -e '[.worktrees[].kind] | index("foreign")' >/dev/null
}
