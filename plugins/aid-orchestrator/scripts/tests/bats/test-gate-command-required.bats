#!/usr/bin/env bats
# aid-tier: t1
# P083 Step 5 — a gate that appears in an active profile's include[] with no
# `command:` is a configuration refusal, checked upfront (before any gate
# runs), not the `skip/no_command` row it used to fall through to.

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT/.aid-o/work/evidence/E-X/R-1/gates"
  cd "$TEST_PROJECT"

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUN_GATES="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  PLAN_DIFF="$AID_PLUGIN_PATH/scripts/aid-plan-diff.sh"

  EXEC_YAML="$TEST_PROJECT/exec.yaml"
  REPORT="$TEST_PROJECT/.aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

@test "a profile including a command-less gate fails the runner, naming the gate and the profile" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  plan_diff:
    required: false
  docs_updated:
    command: "exit 0"
    required: false

gate_profiles:
  standard:
    include: [plan_diff, docs_updated]
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" --profile standard
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_diff"* ]]
  [[ "$output" == *"standard"* ]]
  [[ "$output" == *"no command"* ]]
  # No gate ran — the refusal is upfront, before any dispatch.
  [ ! -f "$REPORT" ]
}

@test "a gate absent from every profile with no command is ignored (unchanged skip behavior)" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  plan_diff:
    command: "exit 0"
    required: false
  docs_updated:
    required: false

gate_profiles:
  standard:
    include: [plan_diff]
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" --profile standard
  [ "$status" -eq 0 ]
  run jq -re '.gates.plan_diff.result' "$REPORT"
  [ "$output" == "pass" ]
  # docs_updated is excluded from the active profile, so it never reaches
  # the command check at all — profile_excluded, not a refusal.
  run jq -re '.gates.docs_updated.result' "$REPORT"
  [ "$output" == "profile_excluded" ]
}

@test "a command-less gate with no --profile at all is unchanged (legacy skip/no_command)" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  plan_diff:
    required: false
  docs_updated:
    command: "exit 0"
    required: false
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.gates.plan_diff.result' "$REPORT"
  [ "$output" == "skip" ]
  run jq -re '.gates.plan_diff.reason' "$REPORT"
  [ "$output" == "no_command" ]
}

@test "the shipped defaults name no command-less gate in any profile (forward guard)" {
  # P064 deliberately ships defaults/execution.yaml WITHOUT a gate_profiles
  # table (recorded at aid-plan-fsm.sh:9861-9868), so this loop is empty
  # today and the assertion is a forward guard: the day a table is added
  # there, every gate it names must carry a command or the new refusal
  # breaks every consumer on upgrade.
  local defaults="$AID_PLUGIN_PATH/defaults/execution.yaml"
  [ -f "$defaults" ]
  local profile gate cmd
  while IFS= read -r profile; do
    [[ -z "$profile" ]] && continue
    while IFS= read -r gate; do
      [[ -z "$gate" ]] && continue
      cmd="$(GATE="$gate" yq '.gates[strenv(GATE)].command' "$defaults")"
      [ -n "$cmd" ]
      [ "$cmd" != "null" ]
    done < <(GATE="$profile" yq -o=json '.gate_profiles[strenv(GATE)].include // []' "$defaults" | jq -r '.[]')
  done < <(yq '.gate_profiles // {} | keys | .[]' "$defaults")
}

@test "the refusal is present in the enforcement registry" {
  local registry="$AID_PLUGIN_PATH/defaults/enforcement-registry.yaml"
  run bash -c "yq -e '.enforcements[] | select(.id == \"gate_command_required\")' '$registry'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "plan_diff's restored command, driven over a small FIXTURE plan, yields ac_count > 0 with every ac_label non-empty" {
  # Never over THIS plan (P083 itself) — that would re-enter every AC
  # including itself and never terminate (the recursion trap this plan's
  # own AC6 pins).
  local plan="$TEST_PROJECT/fixture-plan.md"
  cat > "$plan" <<'EOF'
---
id: P900-fixture
type: plan
status: draft
created: 2026-08-13
author: test
risk: low
---

# Plan: Fixture for plan_diff

## Acceptance Criteria

- [ ] AC1: A fixture criterion that is trivially satisfied.
```yaml
verification_pattern:
  type: cmd
  cmd: "true"
  expected_exit: 0
```
EOF
  ( cd "$TEST_PROJECT" && git init -q && git config user.email t@example.com \
      && git config user.name T && git add -A && git commit -qm init )
  local ev_dir="$TEST_TMPDIR/plan-diff-ev"
  mkdir -p "$ev_dir"
  run bash "$PLAN_DIFF" --plan "$plan" --evidence-dir "$ev_dir" --base-commit HEAD
  [ "$status" -eq 0 ]
  run jq -re '.ac_count' "$ev_dir/plan-diff.json"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  run jq -e '[.rows[]?.ac_label // .ac_labels[]? // empty] | all(length > 0)' "$ev_dir/plan-diff.json"
  [ "$status" -eq 0 ]
}
