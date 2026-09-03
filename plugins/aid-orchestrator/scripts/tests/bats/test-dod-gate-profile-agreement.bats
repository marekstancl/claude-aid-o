#!/usr/bin/env bats
# aid-tier: t0
#
# The DoD gate is chosen from execution.yaml's `gates:` map and written into
# plan.json; the GATES -> DONE precondition then judges the run against the
# `gate_profiles:` map. Nothing checked that the two agreed. A project with
# hand-authored profiles had `docs_updated` in `gates:` and not in `standard`,
# so every run the FSM auto-resolved to `standard` passed its gates and was
# then refused at the transition — after the whole gate run was paid for.
# (ACTA, 2026-09-02.)

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  FIXTURE="$AID_PLUGIN_PATH/scripts/tests/fixtures/plan-with-fenced-steps.md"
  EPIC_TEMPLATE="$AID_PLUGIN_PATH/defaults/templates/epic.md"
  OUTPUT_DIR="$TEST_TMPDIR/output"
  COUNTER="$TEST_TMPDIR/epic-counter.yaml"
  mkdir -p "$OUTPUT_DIR" "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'counter: 0\n' > "$COUNTER"
  EXEC="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

teardown() { teardown_test_evidence_dir; }

_generate() {
  run "$PLAN_TO_EPIC" --plan "$FIXTURE" --phase 1 --total 1 \
    --epic-template "$EPIC_TEMPLATE" --output-dir "$OUTPUT_DIR" \
    --counter-yaml "$COUNTER"
}

@test "generation refuses when an auto-resolvable profile excludes the DoD gate" {
  cat > "$EXEC" <<'YAML'
gates:
  docs_updated:
    command: "true"
gate_profiles:
  quick:
    include: [docs_updated]
  targeted:
    include: [docs_updated]
  standard:
    include: []
  full:
    include: [docs_updated]
YAML
  _generate
  [ "$status" -ne 0 ]
  [[ "$output" == *"docs_updated"* ]]
  [[ "$output" == *"standard"* ]]
}

@test "generation proceeds when every auto-resolvable profile includes it" {
  cat > "$EXEC" <<'YAML'
gates:
  docs_updated:
    command: "true"
gate_profiles:
  quick:
    include: [docs_updated]
  targeted:
    include: [docs_updated]
  standard:
    include: [docs_updated]
YAML
  _generate
  [ "$status" -eq 0 ]
}

@test "a canonical profile the config does not define is not required to list it" {
  # The FSM runs every gate when the resolved profile is absent, so an
  # undefined profile excludes nothing and must not be treated as a refusal.
  cat > "$EXEC" <<'YAML'
gates:
  docs_updated:
    command: "true"
gate_profiles:
  standard:
    include: [docs_updated]
YAML
  _generate
  [ "$status" -eq 0 ]
}

@test "full and release are not consulted — an EPIC boundary cannot resolve to them" {
  cat > "$EXEC" <<'YAML'
gates:
  docs_updated:
    command: "true"
gate_profiles:
  quick:
    include: [docs_updated]
  targeted:
    include: [docs_updated]
  standard:
    include: [docs_updated]
  full:
    include: []
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
  printf 'gates: {}\ngate_profiles:\n  standard:\n    include: []\n' > "$EXEC"
  _generate
  [ "$status" -eq 0 ]
}
