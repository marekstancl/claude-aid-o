#!/usr/bin/env bats
# aid-tier: t2
#
# P114 (3.0.0): the check lives in the shared plan.json builder
# (lib/aid-plan-json.sh aid_plan_json_gate_name), which plan-run calls; the
# cases ask it directly.
#
# The DoD gate is chosen from execution.yaml's `gates:` map and written into
# plan.json; the GATES -> DONE precondition then judges the run against the
# `gate_profiles:` map. Nothing checked that the two agreed. A project with
# hand-authored profiles had `docs_updated` in `gates:` and not in `standard`,
# so every run the FSM auto-resolved to `standard` passed its gates and was
# then refused at the transition — after the whole gate run was paid for.
# (ACTA, 2026-09-02.)
#
# P097 Step 4: the auto-resolvable set is read from the project's own table —
# every declared profile with `when_paths`, plus `default_profile`. No name is
# hard-coded; `release` (no when_paths) is never consulted.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export AID_PLUGIN_PATH
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  EXEC="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

teardown() { teardown_test_evidence_dir; }

# _generate — what plan-run's plan_json stage asks: the DoD gate it may write.
_generate() {
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-json.sh"; aid_plan_json_gate_name "$1"' _ "$EXEC"
}

@test "generation refuses when an auto-resolvable profile excludes the DoD gate" {
  cat > "$EXEC" <<'YAML'
gates:
  docs_updated:
    command: "true"
default_profile: standard
gate_profiles:
  targeted:
    include: [docs_updated]
    when_paths: ["src/*"]
  standard:
    include: []
  full:
    include: [docs_updated]
    when_paths: ["*/aid-fsm.sh"]
YAML
  _generate
  [ "$status" -ne 0 ]
  [[ "$output" == *"docs_updated"* ]]
  [[ "$output" == *"standard"* ]]
}

@test "generation refuses when a when_paths profile (not the default) excludes it" {
  cat > "$EXEC" <<'YAML'
gates:
  docs_updated:
    command: "true"
default_profile: standard
gate_profiles:
  standard:
    include: [docs_updated]
  full:
    include: []
    when_paths: ["*/aid-fsm.sh"]
YAML
  _generate
  [ "$status" -ne 0 ]
  [[ "$output" == *"[full]"* ]]
}

@test "generation proceeds when every auto-resolvable profile includes it" {
  cat > "$EXEC" <<'YAML'
gates:
  docs_updated:
    command: "true"
default_profile: standard
gate_profiles:
  targeted:
    include: [docs_updated]
    when_paths: ["src/*"]
  standard:
    include: [docs_updated]
YAML
  _generate
  [ "$status" -eq 0 ]
}

@test "a profile with no when_paths that is not the default is not consulted — nothing can resolve to it" {
  cat > "$EXEC" <<'YAML'
gates:
  docs_updated:
    command: "true"
default_profile: standard
gate_profiles:
  targeted:
    include: []
  standard:
    include: [docs_updated]
  release:
    include: []
YAML
  _generate
  [ "$status" -eq 0 ]
}

@test "a config with no gate_profiles at all is left alone" {
  printf 'gates:\n  docs_updated:\n    command: "true"\n' > "$EXEC"
  _generate
  [ "$status" -eq 0 ]
}

@test "a project that declares no DoD gate is unaffected" {
  printf 'gates: {}\ndefault_profile: standard\ngate_profiles:\n  standard:\n    include: []\n' > "$EXEC"
  _generate
  [ "$status" -eq 0 ]
}
