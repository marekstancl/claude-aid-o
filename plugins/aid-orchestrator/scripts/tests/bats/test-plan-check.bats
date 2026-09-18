#!/usr/bin/env bats
# aid-tier: t1
# test-plan-check.bats — the deterministic plan check (aid-plan-check.sh).
# One fixture per check: a clean plan passes; each sabotage is refused by the
# check that owns it, in strict mode; the legacy tier downgrades what it says
# it downgrades; the revision (C) checks read a snapshot and a fix list.
# Origin: 2026-09-17 ACTA P025 + Agents P005 pilots (docs/plans/cp1-skriptove-kontroly.md).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1 AID_PLAN_CHECK_RUN_CMDS=0
  CHECK="$AID_PLUGIN_PATH/scripts/aid-plan-check.sh"
  TEST_DIR="$(mktemp -d)"; cd "$TEST_DIR"
  mkdir -p .aid-o/work/plan-state src tests
  printf 'def existing_helper():\n    return 1\n' > src/a.py
  printf 'x\n%.0s' $(seq 1 50) > src/b.py
  printf 'ok\n' > tests/test_a.py
  git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init
}
teardown() { rm -rf "$TEST_DIR"; }

# A whole, valid plan. Arguments override the step-2 Dependencies line and the
# step-1 Files block so each test sabotages exactly one thing.
_plan() { # <file> <strict|legacy> [dep2] [files1...]
  local f="$1" strict="$2" dep2="${3:-- Depends on: Step 1}"; shift 3 2>/dev/null || shift $#
  local sflag=""; [[ "$strict" == "strict" ]] && sflag=$'\nlifecycle_strict: true'
  {
    printf -- '---\nid: P900\ntype: regular\nrisk: low%s\n---\n# Plan: P900\n\n## Goal\n\nMake the thing work.\n\n## Testing Strategy\n\nOne case in tests/test_a.py.\n\n## Resources Verification\n\n- [ ] Functions/helpers: `existing_helper` (`src/a.py:1`)\n- [ ] Environment variables: `NEW_FLAG` (nová, Step 1)\n\n**EPIC 1: Steps 1-2**\n\n### Step 1: first\n\n**Objective:** do the first thing.\n\n**Files:**\n' "$sflag"
    if [[ $# -gt 0 ]]; then printf '%s\n' "$@"; else printf -- '- Modify: `src/a.py` (lines ~1-2) — extend `existing_helper`\n- Create: `src/new.py` — the new module\n'; fi
    printf '\n**Reuse check:** searched: `find src -name "new*"` → none — nothing exists yet\n\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nnone\n\n**Edge Cases:**\n- one\n- two\n- three\n\n**Dependencies:**\n- Depends on: none\n\n**Acceptance Criteria:**\n- [ ] `src/new.py` exists\n- [ ] `existing_helper` still returns 1\n- [ ] tests pass\n\n**Effort:** M\n**AID Role:** backend\n\n### Step 2: second\n\n**Objective:** do the second thing.\n\n**Files:**\n- Modify: `src/new.py` — use it\n\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nnone\n\n**Edge Cases:** (a) one; (b) two; (c) three\n\n**Dependencies:**\n%s\n\n**Acceptance Criteria:**\n- [ ] one\n- [ ] two\n- [ ] three\n\n**Effort:** S\n**AID Role:** backend\n' "$dep2"
  } > "$f"
}

@test "plan-check: a whole valid plan passes (strict)" {
  _plan p.md strict
  run "$CHECK" p.md; echo "$output"; [ "$status" -eq 0 ]
}
@test "plan-check A1: a dependency on a step that does not exist blocks" {
  _plan p.md strict '- Depends on: Step 7'
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A1"* ]]
}
@test "plan-check A1: a dependency cycle blocks, even on a legacy plan" {
  _plan p.md legacy '- Depends on: Step 1'
  sed -i 's/^- Depends on: none$/- Depends on: Step 2/' p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"cycle"* ]]
}
@test "plan-check A3: an M step with two edge cases blocks (strict) and only warns (legacy)" {
  _plan p.md strict; sed -i '0,/^- three$/{/^- three$/d}' p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A3"* ]]
  _plan p.md legacy; sed -i '0,/^- three$/{/^- three$/d}' p.md
  run "$CHECK" p.md; [ "$status" -eq 0 ]; [[ "$output" == *"[WARN legacy] A3"* ]]
}
@test "plan-check A4: a forbidden shortcut phrase blocks, in English and in Czech" {
  _plan p.md strict; sed -i 's/^Make the thing work\.$/Make the thing work, handle edge cases as needed./' p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A4"* ]]
  _plan p.md strict; sed -i 's/^Make the thing work\.$/Uděláme validaci, logování atd./' p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A4"* ]]
}
@test "plan-check A4: a phrase inside a fenced code block is not a finding" {
  _plan p.md strict; printf '\n```\n# etc. and so on inside code\n```\n' >> p.md
  run "$CHECK" p.md; [ "$status" -eq 0 ]
}
@test "plan-check A5: an acceptance criterion naming an undeclared, missing path blocks" {
  _plan p.md strict; sed -i 's/^- \[ \] tests pass$/- [ ] `src\/ghost.py` is green/' p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A5"* ]]
}
@test "plan-check A6: a verification_pattern with a placeholder or a bad type blocks even legacy" {
  _plan p.md legacy; printf '\n## Acceptance Criteria\n\n- [ ] AC1\n  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "test -f <placeholder>"\n  ```\n' >> p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A6"*placeholder* ]]
  _plan p.md legacy; printf '\n## Acceptance Criteria\n\n- [ ] AC1\n  ```yaml\n  verification_pattern:\n    type: magic\n  ```\n' >> p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A6"* ]]
}
@test "plan-check A7: modifying a file that neither exists nor is created earlier blocks" {
  _plan p.md strict '- Depends on: Step 1' '- Modify: `src/nothere.py` (lines ~1-2) — edit'
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A7"* ]]
}
@test "plan-check A7: modifying a file an EARLIER step creates is fine" {
  _plan p.md strict
  run "$CHECK" p.md; [ "$status" -eq 0 ]   # Step 2 modifies src/new.py, created in Step 1
}
@test "plan-check A8: an empty section blocks" {
  _plan p.md strict; sed -i 's/^Make the thing work\.$//' p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A8"*"empty section"* ]]
}
@test "plan-check A10: two Files bullets with one copied description block" {
  local d='— the very same long description copied twice into two bullets of one step for real'
  _plan p.md strict '- Depends on: Step 1' "- Modify: \`src/a.py\` $d" "- Modify: \`src/b.py\` $d"
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK A10"* ]]
}
@test "plan-check A9: a plan over the size threshold warns and still passes" {
  _plan p.md strict; for i in $(seq 1 820); do echo "filler line $i"; done >> p.md
  run "$CHECK" p.md; [ "$status" -eq 0 ]; [[ "$output" == *"WARN  A9"* ]]
}
@test "plan-check B1: a prose path that exists nowhere blocks; a tail of a real path is fine" {
  _plan p.md strict; sed -i 's/^Make the thing work\.$/See `src\/vanished.py` and `a.py`./' p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK B1"*vanished* ]]; [[ "$output" != *"BLOCK B1"*'`a.py`'* ]]
}
@test "plan-check B1: a path whose first directory is not in this repo only warns" {
  _plan p.md strict; sed -i 's/^Make the thing work\.$/Reuse `otherrepo\/lib\/x.py`./' p.md
  run "$CHECK" p.md; [ "$status" -eq 0 ]; [[ "$output" == *"WARN  B1"*"not in this repository"* ]]
}
@test "plan-check B2: a line range past the end of the file warns" {
  _plan p.md strict '- Depends on: Step 1' '- Modify: `src/b.py` (lines ~40-120) — edit' '- Create: `src/new.py` — new'
  run "$CHECK" p.md; [ "$status" -eq 0 ]; [[ "$output" == *"WARN  B2"*"50 lines"* ]]
}
@test "plan-check B3: must_not_exist on a file that is already absent blocks" {
  _plan p.md strict; printf '\n## Acceptance Criteria\n\n- [ ] gone\n  ```yaml\n  verification_pattern:\n    type: must_not_exist\n    file: "src/never.py"\n  ```\n' >> p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK B3"* ]]
}
@test "plan-check B4: a Resources entry claimed as existing but absent blocks; one marked new does not" {
  _plan p.md strict; sed -i 's/`existing_helper` (`src\/a.py:1`)/`existing_helper` (`src\/a.py:1`); `phantom_helper` (`src\/a.py:9`)/' p.md
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK B4"*phantom_helper* ]]; [[ "$output" != *NEW_FLAG* ]]
}
@test "plan-check B7: a must_contain that already holds on HEAD warns" {
  _plan p.md strict; printf '\n## Acceptance Criteria\n\n- [ ] there\n  ```yaml\n  verification_pattern:\n    type: must_contain\n    file: "src/a.py"\n    regex: "existing_helper"\n  ```\n' >> p.md
  run "$CHECK" p.md; [ "$status" -eq 0 ]; [[ "$output" == *"WARN  B7"* ]]
}
@test "plan-check B8: creating a file that already exists blocks even legacy" {
  _plan p.md legacy '- Depends on: Step 1' '- Create: `src/a.py` — again'
  run "$CHECK" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK B8"* ]]
}
@test "plan-check B9: a new test file sharing a basename with an existing one warns" {
  mkdir -p tests/other; printf 'ok\n' > tests/other/test_a.py; git add -A
  _plan p.md strict '- Depends on: Step 1' '- Test: `tests/new/test_a.py` — cases' '- Create: `src/new.py` — new'
  run "$CHECK" p.md; [ "$status" -eq 0 ]; [[ "$output" == *"WARN  B9"* ]]
}
@test "plan-check B10: removing a file that others still reference warns" {
  printf 'from src import existing_helper\n' > src/user.py; printf 'import existing_helper\n' > src/user2.py
  mv src/a.py src/existing_helper.py; git add -A
  _plan p.md strict '- Depends on: Step 1' '- Modify: `src/b.py` (lines ~1-2) — edit'
  printf '\n## Acceptance Criteria\n\n- [ ] gone\n  ```yaml\n  verification_pattern:\n    type: must_not_exist\n    file: "src/existing_helper.py"\n  ```\n' >> p.md
  run "$CHECK" p.md; [[ "$output" == *"WARN  B10"*"still referenced by"* ]]
}
@test "plan-check C: --snapshot without --fixes is a usage error (C1)" {
  _plan p.md strict; cp p.md old.md
  run "$CHECK" p.md --snapshot old.md; [ "$status" -eq 2 ]
}
@test "plan-check C2: a path the revision added and nothing creates blocks" {
  _plan p.md strict; cp p.md old.md; sed -i 's/^Make the thing work\.$/Now also `src\/added.py`./' p.md
  run "$CHECK" p.md --snapshot old.md --fixes 1; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK C2"*added* ]]
}
@test "plan-check C3: a token the revision retired in one place but kept elsewhere warns" {
  _plan p.md strict; sed -i 's/^Make the thing work\.$/Uses `old_name_fn`./; s/^One case in tests\/test_a\.py\.$/Covers `old_name_fn` too./' p.md; cp p.md old.md
  sed -i 's/^Uses `old_name_fn`\.$/Uses `new_name_fn`./' p.md
  run "$CHECK" p.md --snapshot old.md --fixes 1; [[ "$output" == *"WARN  C3"*old_name_fn* ]]
}
@test "plan-check C4/C5: a revision touching a step outside the fix list warns; adding an AC there blocks" {
  _plan p.md strict; cp p.md old.md
  sed -i 's/^- \[ \] three$/- [ ] three\n- [ ] four/' p.md
  run "$CHECK" p.md --snapshot old.md --fixes 1; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK C5"* ]]; [[ "$output" == *"WARN  C4"*"Step 2"* ]]
  run "$CHECK" p.md --snapshot old.md --fixes 1,2; [ "$status" -eq 0 ]
}
@test "plan-check C5: a revision that adds a whole step blocks even legacy" {
  _plan p.md legacy; cp p.md old.md
  printf '\n### Step 3: extra\n\n**Objective:** more.\n\n**Files:**\n- Modify: `src/b.py` — x\n\n**Dependencies:**\n- Depends on: none\n\n**Acceptance Criteria:**\n- [ ] a\n\n**Effort:** S\n**AID Role:** backend\n' >> p.md
  run "$CHECK" p.md --snapshot old.md --fixes 1; [ "$status" -eq 1 ]; [[ "$output" == *"BLOCK C5"*"added step"* ]]
}
@test "plan-check C: --fixes none is accepted with --snapshot and passes an unchanged plan" {
  _plan p.md strict; cp p.md old.md
  run "$CHECK" p.md --snapshot old.md --fixes none --json out.json; [ "$status" -eq 0 ]
  [ "$(jq -c '.steps_changed' out.json)" = '[]' ]; [ "$(jq -c '.added_outside_fixes' out.json)" = '[]' ]
}
@test "plan-check C: --json names steps_changed and an AC added outside the fix list as kind ac" {
  _plan p.md strict; cp p.md old.md
  sed -i 's/^- \[ \] three$/- [ ] three\n- [ ] four/' p.md
  run "$CHECK" p.md --snapshot old.md --fixes 1 --json out.json; [ "$status" -eq 1 ]
  [ "$(jq -c '.steps_changed' out.json)" = '[2]' ]
  jq -e '.added_outside_fixes == [{step: 2, kind: "ac", text: "- [ ] four"}]' out.json
}
@test "plan-check C2: a plan-review evidence path added by a revision is not a missing file" {
  _plan p.md strict; cp p.md old.md; sed -i 's/^Make the thing work\.$/Reads `cp1\/round-2\/merged.json`./' p.md
  run "$CHECK" p.md --snapshot old.md --fixes 1; [[ "$output" != *"BLOCK C2"* ]]
}
@test "plan-check --json: report carries sha256, mode, findings and the pass verdict" {
  _plan p.md strict '- Depends on: Step 7'
  run "$CHECK" p.md --json out.json --quiet; [ "$status" -eq 1 ]
  [ "$(jq -r .pass out.json)" = "false" ]; [ "$(jq -r .mode out.json)" = "strict" ]
  [ "$(jq -r '.blocking[0].id' out.json)" = "A1" ]; [ "$(jq -r .plan_sha256 out.json)" = "$(sha256sum p.md | cut -d' ' -f1)" ]
}
@test "readiness: generation readiness refuses a plan the check blocks" {
  _plan p.md strict '- Depends on: Step 7'
  run "$AID_PLUGIN_PATH/scripts/aid-generation-readiness.sh" p.md; [ "$status" -eq 1 ]; [[ "$output" == *"aid-plan-check"* ]]
}
@test "readiness: a passing check writes plan-check.json into the plan's evidence directory" {
  mkdir -p .aid-o/plans; _plan .aid-o/plans/P900.md strict
  run "$AID_PLUGIN_PATH/scripts/aid-generation-readiness.sh" .aid-o/plans/P900.md; [ "$status" -eq 0 ]
  [ -f .aid-o/work/evidence/P900/plan-check.json ]
  [ "$(jq -r .pass .aid-o/work/evidence/P900/plan-check.json)" = "true" ]
}
@test "plan-check B7: cmd criteria are NOT executed unless --run-cmds is given" {
  _plan p.md strict; printf '\n## Acceptance Criteria\n\n- [ ] side\n  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "touch SIDE_EFFECT"\n    expected_exit: 0\n  ```\n' >> p.md
  run "$CHECK" p.md; [ ! -e SIDE_EFFECT ]
  run "$CHECK" p.md --run-cmds; [ -e SIDE_EFFECT ]; [[ "$output" == *"WARN  B7"* ]]
}
@test "plan-check: a plan with no step sections does not crash" {
  printf -- '---\nid: P900\n---\n# x\n\n## Goal\n\nno steps\n' > p.md
  run "$CHECK" p.md; [[ "$output" != *"unbound variable"* ]]
}
