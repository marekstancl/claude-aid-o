#!/usr/bin/env bats
# aid-tier: t2
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

@test "a committed file already on disk untracked and identical (the close's receipt) is taken in, the index ends clean" {
  # the receipt lives under .aid-lifecycle/ (3.13.0: only AID's generated records are taken in)
  ( cd ../side && mkdir -p .aid-lifecycle/receipts && echo r > .aid-lifecycle/receipts/P1.yaml && git add . && git commit -qm receipt )
  NEW="$(git -C ../side rev-parse HEAD)"; git update-ref refs/heads/main "$NEW"
  mkdir -p .aid-lifecycle/receipts; echo r > .aid-lifecycle/receipts/P1.yaml   # written before the plumbing commit
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"brought forward"* ]]
  [[ "$(cat a.txt)" == "two" ]]
  [[ -z "$(git status --porcelain)" ]]
}

@test "an overlapping local edit is not overwritten — a loud warning names the command instead" {
  echo mine > a.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"
  [ "$status" -eq 1 ]                                   # 3.13.0: an overlap is reported as a failure, never passed
  [[ "$output" == *"WARNING"* && "$output" == *"do not commit there"* && "$output" == *"a.txt"* ]]
  [[ "$(cat a.txt)" == "mine" ]]
}

@test "a branch checked out nowhere is left alone" {
  git update-ref refs/heads/other "$OLD"
  run _aid_lc_sync_checkout_of "$T/side" other "$OLD" "$NEW"
  [ "$status" -eq 0 ]; [[ -z "$output" ]]
}

@test "3.13.0: a mixed index (one written file at its old version, another edited) is refused and nothing changes" {
  ( cd ../side && echo three > a.txt && echo newer > b.txt && git add . && git commit -qm three )
  local N2; N2="$(git -C ../side rev-parse HEAD)"; git update-ref refs/heads/main "$N2"
  echo half > b.txt; git add b.txt                      # b.txt staged at a version none of the commits has
  local before; before="$(git ls-files -s | sha256sum)"
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"; echo "$output"
  [ "$status" -eq 1 ]; [[ "$output" == *"b.txt"* ]]
  [ "$(git ls-files -s | sha256sum)" = "$before" ]      # the real index is untouched
}

@test "3.13.0: an unrelated staged change of the user stays staged when the checkout is brought forward" {
  echo note > mine.txt; git add mine.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"; [ "$status" -eq 0 ]
  [[ "$(cat a.txt)" == "two" ]]; [ "$(git diff --cached --name-only)" = "mine.txt" ]
}

@test "3.13.0: a rename is checked on both sides — the index keeping the removed source is not 'at the tip'" {
  ( cd ../side && git mv b.txt c.txt && git commit -qm rename )
  local N2; N2="$(git -C ../side rev-parse HEAD)"; git update-ref refs/heads/main "$N2"
  git read-tree "$N2"; git update-index --add --cacheinfo "100644,$(git rev-parse "${NEW}:b.txt"),b.txt"   # tip's c.txt and the old b.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"; echo "$output"
  [ "$status" -eq 1 ]; [[ "$output" == *"b.txt"* ]]
}

@test "3.13.0: refusal, the printed repair, then the same call again: the checkout is at the tip and the user's edit is kept aside" {
  echo mine > a.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"; [ "$status" -eq 1 ]; [[ "$output" == *"Nothing was changed"* ]]
  git show :a.txt > a.txt.aid-staged; cp a.txt a.txt.aid-worktree
  GIT_LITERAL_PATHSPECS=1 git checkout -q "$NEW" -- a.txt; GIT_LITERAL_PATHSPECS=1 git reset -q -- a.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"; echo "$output"; [ "$status" -eq 0 ]
  [[ "$(cat b.txt)" == "new" ]]; [[ "$(cat a.txt)" == "two" ]]; [[ "$(cat a.txt.aid-worktree)" == "mine" ]]
}

@test "3.13.0: a write that only changes the executable bit is brought forward; a local mode change on a written file refuses" {
  ( cd ../side && chmod +x a.txt && git add a.txt && git commit -qm mode )
  local N2; N2="$(git -C ../side rev-parse HEAD)"; git update-ref refs/heads/main "$N2"
  git reset -q --hard "$NEW"; git update-ref refs/heads/main "$N2"
  run _aid_lc_sync_checkout_of "$T/side" main "$NEW" "$N2"; echo "$output"; [ "$status" -eq 0 ]
  [ -x a.txt ]; [ "$(git ls-files -s a.txt | cut -c1-6)" = 100755 ]
}

@test "3.13.0: a written file named like a pattern is that one file — another file it would match keeps its edit" {
  ( cd ../side && echo star > 'a*' && git add -- 'a*' && git commit -qm star )
  local N2; N2="$(git -C ../side rev-parse HEAD)"
  git reset -q --hard "$NEW"; echo "my edit" > a.txt; git update-ref refs/heads/main "$N2"
  run _aid_lc_sync_checkout_of "$T/side" main "$NEW" "$N2"; echo "$output"; [ "$status" -eq 0 ]
  [ "$(cat 'a*')" = star ]; [ "$(cat a.txt)" = "my edit" ]
}

@test "3.13.0: distinct staged and unstaged edits are both kept by the printed repair" {
  echo staged > a.txt; git add a.txt; echo unstaged > a.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"; [ "$status" -eq 1 ]
  [ "$(git show :a.txt)" = staged ]; [ "$(cat a.txt)" = unstaged ]                # nothing was changed
  git show :a.txt > a.txt.aid-staged; cp a.txt a.txt.aid-worktree
  GIT_LITERAL_PATHSPECS=1 git checkout -q "$NEW" -- a.txt; GIT_LITERAL_PATHSPECS=1 git reset -q -- a.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$OLD" "$NEW"; [ "$status" -eq 0 ]
  [ "$(cat a.txt.aid-staged)" = staged ]; [ "$(cat a.txt.aid-worktree)" = unstaged ]
}

@test "3.13.0: a local mode change on a file the write changed refuses; an unchanged symlink is not taken for a change" {
  ln -s a.txt link; git add link; git commit -qm link; local L; L="$(git rev-parse HEAD)"
  ( cd ../side && git merge -q --ff-only "$L" 2>/dev/null || git reset -q --hard "$L"; echo three > a.txt; git add a.txt; git commit -qm three )
  local N2; N2="$(git -C ../side rev-parse HEAD)"; git update-ref refs/heads/main "$N2"
  chmod +x a.txt                                         # the user's local mode change on the written file
  run _aid_lc_sync_checkout_of "$T/side" main "$L" "$N2"; echo "$output"; [ "$status" -eq 1 ]; [[ "$output" == *"a.txt"* ]]
  chmod -x a.txt
  run _aid_lc_sync_checkout_of "$T/side" main "$L" "$N2"; [ "$status" -eq 0 ]; [ "$(cat a.txt)" = three ]; [ -L link ]
}
