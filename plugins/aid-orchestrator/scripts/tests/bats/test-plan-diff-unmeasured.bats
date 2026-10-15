#!/usr/bin/env bats
# aid-tier: t1
# 2.114.0 — aid-plan-diff.sh counts what it does NOT measure: summary criteria
# without a verification pattern, summary bullets it never parses (no AC<N>:
# mark) and step-level **Acceptance Criteria:** bullets. Defect caught: a plan
# closed as "verified" while most of its criteria were never read by the gate
# (agents P010: 13 measured, ~57 step bullets unseen, nobody told).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  PD="$AID_PLUGIN_PATH/scripts/aid-plan-diff.sh"
  R="$(mktemp -d)"; cd "$R"; git init -q .; git config user.email t@t; git config user.name t
  mkdir -p .aid-o/plans ev; echo base > app.py; git add -A; git commit -qm base; BASE="$(git rev-parse HEAD)"
  echo "print('hello')" >> app.py; git commit -qam work
}
teardown() { rm -rf "$R"; }

@test "no verification pattern anywhere: graceful skip still counts the unparsed summary bullets and the step bullets" {
  printf -- '---\nid: P1\n---\n# Plan\n\n### Step 1: a\n\n**Acceptance Criteria:**\n- [ ] it greets\n- [ ] it exits 0\n\n**Effort:** S\n\n### Step 2: b\n\n**Acceptance Criteria:**\n- [ ] it logs\n\nprose\n\n## Success Criteria\n\n- it runs\n- it is fast\n' > .aid-o/plans/P1.md
  run bash "$PD" --plan .aid-o/plans/P1.md --evidence-dir ev --base-commit "$BASE"
  [ "$status" -eq 2 ]
  [ "$(jq -c .summary.unmeasured ev/plan-diff.json)" = '{"summary_prose":0,"summary_unparsed":2,"step_bullets":3}' ]
}

@test "a measured criterion beside a prose one: prose counted, measured not" {
  printf -- '---\nid: P2\n---\n# Plan\n\n### Step 1: a\n\n**Acceptance Criteria:**\n- [ ] it greets\n\n## Acceptance Criteria\n\n- [ ] AC1: hello is printed\n  ```yaml\n  type: cmd\n  cmd: grep -q hello app.py\n  ```\n- [ ] AC2: it feels fast\n' > .aid-o/plans/P2.md
  run bash "$PD" --plan .aid-o/plans/P2.md --evidence-dir ev --base-commit "$BASE"
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .ac_count ev/plan-diff.json)" = 2 ]
  [ "$(jq -c .summary.unmeasured ev/plan-diff.json)" = '{"summary_prose":1,"summary_unparsed":0,"step_bullets":1}' ]
}

@test "timeout: a point out of time is unmeasured (reason, limit, neměřeno), not a plain absent" {
  printf -- '---\nid: P3\n---\n# Plan\n\n## Acceptance Criteria\n\n- [ ] AC1: slow\n  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "sleep 5"\n    expected_exit: 0\n    timeout: 1\n  ```\n' > .aid-o/plans/P3.md
  run bash "$PD" --plan .aid-o/plans/P3.md --evidence-dir ev --base-commit "$BASE"; [ "$status" -eq 1 ]
  [ "$(jq -c '.results[0] | {verdict, unmeasured, reason, timeout_s}' ev/plan-diff.json)" = '{"verdict":"absent","unmeasured":true,"reason":"timeout","timeout_s":1}' ]
  [[ "$(jq -r '.results[0].evidence' ev/plan-diff.json)" == "neměřeno: limit 1 s"* ]]
}

@test "timeout: the close's sentence names the limit and the timeout: remedy (one sentence, lib/aid-unmeasured.sh)" {
  source "$AID_PLUGIN_PATH/scripts/lib/aid-unmeasured.sh"
  run aid_pd_unmeasured_line '{"ac_label":"AC4","reason":"timeout","timeout_s":120}'
  [[ "$output" == "AC4 (timeout: neměřeno, limit 120 s"*"AID_PLAN_DIFF_AC_TIMEOUT_FLOOR"*"timeout:)" ]]
  grep -q 'aid_pd_unmeasured_line' "$AID_PLUGIN_PATH/scripts/aid-release-policy.sh"
  [[ timeout =~ $AID_PD_UNMEASURED_RE ]]
}
