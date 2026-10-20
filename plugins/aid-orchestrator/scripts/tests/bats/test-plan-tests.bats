#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/lib/aid-plan-tests.sh
# P117 (17): the close runs the nightly tests a plan names and binds the result to the candidate. Defect it
# catches: a plan's t2/e2e tests never run at the close, or a hand-made or stale proof accepted in their place
# (WAN P111: "T2 without evidence" at CP7, twice).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  T="$BATS_TEST_TMPDIR/t"; RD="$BATS_TEST_TMPDIR/run"; mkdir -p "$T/tests" "$T/ui/e2e" "$RD"
  printf '#!/usr/bin/env bats\n# aid-tier: t2\n@test "x" { true; }\n' > "$T/tests/test-night.bats"
  printf '#!/usr/bin/env bats\n# aid-tier: t1\n@test "x" { true; }\n' > "$T/tests/test-day.bats"
  echo 'test("e2e", () => {})' > "$T/ui/e2e/flow.spec.ts"
  printf -- '---\nid: P950\n---\n# Plan\n\n### Step 1: one\n\n**Files:**\n- Test: `tests/test-night.bats` — the nightly suite\n- Test: `tests/test-day.bats` — a quick one\n- Create: `ui/e2e/flow.spec.ts` — the flow\n- Modify: `src/app.py` — code\n' > "$T/plan.md"
  EX="$T/execution.yaml"
  printf 'plan_tests:\n  - glob: "**/*.bats"\n    command: "echo ran {path}"\n  - glob: "ui/e2e/**"\n    command: "echo e2e {path}"\n    nightly: true\n' > "$EX"
  L() { run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-tests.sh'; $1"; }
}

@test "plan tests: the plan-named tests are found; the close runs the t2 suite and the nightly e2e, not the t1 one, and binds the result to the candidate" {
  L "aid_plan_tests_named '$T/plan.md'"; [ "$output" = $'tests/test-day.bats\ntests/test-night.bats\nui/e2e/flow.spec.ts' ]
  L "aid_plan_tests_run '$T' '$EX' '$T/plan.md' cafe '$RD'"; [ "$status" -eq 0 ]
  [ "$(jq -r '[.tests[].path] | join(" ")' "$RD/plan-tests.json")" = "tests/test-night.bats ui/e2e/flow.spec.ts" ]
  [ "$(jq -r '.tests[0] | "\(.command) \(.exit)"' "$RD/plan-tests.json")" = "echo ran tests/test-night.bats 0" ]
  grep -q '^ran tests/test-night.bats$' "$RD/$(jq -r '.tests[0].log' "$RD/plan-tests.json")"
  L "aid_plan_tests_bad '$RD' cafe"; [ "$status" -eq 0 ]
  L "aid_plan_tests_bad '$RD' beef"; [ "$status" -eq 1 ]; [[ "$output" == *"not cafe"* || "$output" == *"of candidate cafe"* ]]
  # decide's full check: the close's own record of writing it, and exactly the set the plan and execution.yaml ask
  L "aid_plan_tests_bad '$RD' cafe '$T' '$EX' '$T/plan.md'"; [ "$status" -eq 1 ]; [[ "$output" == *"no record of the close's produce stage"* ]]
  L "source '$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh'; cd '$RD' && aid_stage_writes_record '$RD' gates plan-tests.json plan-tests/1.log plan-tests/2.log"
  L "aid_plan_tests_bad '$RD' cafe '$T' '$EX' '$T/plan.md'"; [ "$status" -eq 1 ]; [[ "$output" == *"no record of the close's produce stage"* ]]   # another stage's record proves nothing
  L "source '$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh'; cd '$RD' && aid_stage_writes_record '$RD' produce plan-tests.json plan-tests/1.log plan-tests/2.log"
  L "aid_plan_tests_bad '$RD' cafe '$T' '$EX' '$T/plan.md'"; echo "$output"; [ "$status" -eq 0 ]
  printf -- '- Test: `tests/test-more.bats` — another\n' >> "$T/plan.md"; printf '# aid-tier: t2\n' > "$T/tests/test-more.bats"
  L "aid_plan_tests_bad '$RD' cafe '$T' '$EX' '$T/plan.md'"; [ "$status" -eq 1 ]; [[ "$output" == *"the plan changed after the close ran"* ]]
  git -C "$T" init -q 2>/dev/null; sed -i '$d' "$T/plan.md"; rm "$T/tests/test-more.bats"
  L "aid_plan_tests_bad '$RD' cafe '$T' '$EX' '$T/plan.md'"; [ "$status" -eq 0 ]
  echo "# a comment" >> "$EX"; L "aid_plan_tests_bad '$RD' cafe '$T' '$EX' '$T/plan.md'"; [ "$status" -eq 1 ]; [[ "$output" == *"execution.yaml changed"* ]]
  sed -i '$d' "$EX"
  echo tampered >> "$RD/plan-tests/1.log"; L "aid_plan_tests_bad '$RD' cafe"; [ "$status" -eq 1 ]; [[ "$output" == *"log changed"* ]]
}

@test "plan tests: a failing test, or one no plan_tests entry runs, fails the close; a hand-written file is not the close's" {
  printf 'plan_tests:\n  - glob: "**/*.bats"\n    command: "exit 3"\n' > "$EX"
  L "aid_plan_tests_run '$T' '$EX' '$T/plan.md' cafe '$RD'"
  L "aid_plan_tests_bad '$RD' cafe"; [ "$status" -eq 1 ]; [[ "$output" == *"tests/test-night.bats: exit 3"* ]]
  printf 'plan_tests:\n  - glob: "ui/**"\n    command: "true"\n    nightly: true\n' > "$EX"
  L "aid_plan_tests_run '$T' '$EX' '$T/plan.md' cafe '$RD'"
  L "aid_plan_tests_bad '$RD' cafe"; [ "$status" -eq 1 ]; [[ "$output" == *"tests/test-night.bats: no plan_tests entry"* ]]
  jq '.run_by = "me"' "$RD/plan-tests.json" > "$RD/p" && mv "$RD/p" "$RD/plan-tests.json"
  L "aid_plan_tests_bad '$RD' cafe"; [ "$status" -eq 1 ]; [[ "$output" == *"not written by the close"* ]]
}

@test "plan check B13: with plan_tests declared a plan-named test nothing runs blocks; without them a named t2 suite warns" {
  cd "$T"; git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm i
  mkdir -p .aid-o/config; printf 'plan_tests:\n  - glob: "**/*.bats"\n    command: "bats {path}"\n' > .aid-o/config/execution.yaml
  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" "$T/plan.md" --project-root "$T"; echo "$output"
  [[ "$output" == *"B13"*"ui/e2e/flow.spec.ts"*"no plan_tests entry"* ]]
  rm .aid-o/config/execution.yaml
  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" "$T/plan.md" --project-root "$T"; echo "$output"
  [[ "$output" == *"WARN  B13"*"tests/test-night.bats"* ]]; [[ "$output" != *"tests/test-day.bats"*"B13"* ]]
}
