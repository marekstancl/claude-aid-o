#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/lib/aid-plan-dependency.sh
# P117 (3): plan-run holds a plan to the dependency CP1 reviewed it against. Defect it catches: a plan reviewed
# against an unmerged plan's worktree starts after that plan merged something else (WAN P112).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  R="$BATS_TEST_TMPDIR/r"; mkdir -p "$R/.aid-o/work/evidence/P900"; cd "$R"
  git init -q -b main .; git config user.email t@t; git config user.name t
  echo a > a.txt; git add -A; git commit -qm init
  git worktree add -q -b plan/P899 "$R/wt"; echo d > "$R/wt/d.txt"; git -C "$R/wt" add -A; git -C "$R/wt" commit -qm dep
}

_verify() {
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-roots.sh'; source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh'
    source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-dependency.sh'
    aid_plan_dep_verify '$R' P900 $1 && echo PASS || echo \"\$DEP_CODE: \$DEP_WHY\""
}
_bind() { jq -n --arg h "$1" --arg w "$R/wt" '{plan: "P899", worktree: $w, branch: "plan/P899", head: $h}' > "$R/.aid-o/work/evidence/P900/dependency-root.json"; }

@test "dependency at run: no binding passes; a merged dependency containing the reviewed HEAD passes; one that merged without it is dependency_moved" {
  _verify run; [ "$output" = PASS ]
  local reviewed; reviewed="$(git -C "$R/wt" rev-parse HEAD)"; _bind "$reviewed"
  _verify run; [[ "$output" == PASS ]]            # still unmerged and unmoved: the review binding holds
  git merge -q --no-edit plan/P899
  _verify run; [ "$output" = PASS ]
  # the dependency was rewritten after the review and merged without the reviewed commit
  git reset -q --hard HEAD~1; git -C "$R/wt" reset -q --hard HEAD~1
  echo other > "$R/wt/d.txt"; git -C "$R/wt" add -A; git -C "$R/wt" commit -qm other; git merge -q --no-edit plan/P899
  _verify run; [[ "$output" == "dependency_moved: CP1 checked P900 against P899 at ${reviewed:0:12}"* ]]
}

@test "dependency under review: the worktree gone is dependency_worktree_missing, a moved branch dependency_moved" {
  _bind "$(git -C "$R/wt" rev-parse HEAD)"
  echo e >> "$R/wt/d.txt"; git -C "$R/wt" commit -qam more
  _verify review; [[ "$output" == "dependency_moved: P899 moved from"* ]]
  git worktree remove --force "$R/wt"
  _verify review; [[ "$output" == "dependency_worktree_missing:"* ]]
}
