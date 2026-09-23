#!/usr/bin/env bats
# aid-tier: t1
#
# T1 BY MEASUREMENT (P099): 82 s over 6 cases (nightly journal, 2026-09-23) —
# every case runs the real generator; T0 is under 2 s per case.
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
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  # The plan lives in the test project, so generation resolves that workspace.
  FIXTURE="$TEST_PROJECT_ROOT/.aid-o/plans/plan-with-fenced-steps.md"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  cp "$AID_PLUGIN_PATH/scripts/tests/fixtures/plan-with-fenced-steps.md" "$FIXTURE"
  EPIC_TEMPLATE="$AID_PLUGIN_PATH/defaults/templates/epic.md"
  OUTPUT_DIR="$TEST_TMPDIR/output"
  COUNTER="$TEST_TMPDIR/epic-counter.yaml"
  mkdir -p "$OUTPUT_DIR" "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'counter: 0\n' > "$COUNTER"
  EXEC="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

teardown() { teardown_test_evidence_dir; }

_generate() {
  aid_fixture_seed_plan_review "$TEST_PROJECT_ROOT" "$FIXTURE" || return 1
  run "$PLAN_TO_EPIC" --plan "$FIXTURE" --phase 1 --total 1 \
    --epic-template "$EPIC_TEMPLATE" --output-dir "$OUTPUT_DIR" \
    --counter-yaml "$COUNTER"
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
