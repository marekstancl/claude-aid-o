#!/usr/bin/env bats
# test-aid-test-audit-config.bats — P066 Step 5.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-config.sh"
  FIXTURE_PROJECT="$TEST_TMPDIR/config-fixture"
  mkdir -p "$FIXTURE_PROJECT/.aid-o/config"
}

teardown() {
  teardown_test_evidence_dir
}

@test "load_test_audit_config: config-absent path returns the exact hardcoded defaults, schema-valid" {
  run load_test_audit_config "$FIXTURE_PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.budget_minutes_default == 30' >/dev/null
  echo "$output" | jq -e '.max_read_only_audit_agents == 4' >/dev/null
  echo "$output" | jq -e '.allowed_runners == ["bats","package-script","declared-command","ci"]' >/dev/null
}

@test "load_test_audit_config: a present, valid config overrides the defaults correctly" {
  cat > "$FIXTURE_PROJECT/.aid-o/config/test-audit.yaml" <<'YAML'
budget_minutes_default: 60
max_read_only_audit_agents: 8
allowed_runners:
  - pytest
YAML
  run load_test_audit_config "$FIXTURE_PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.budget_minutes_default == 60' >/dev/null
  echo "$output" | jq -e '.max_read_only_audit_agents == 8' >/dev/null
  echo "$output" | jq -e '.allowed_runners == ["pytest"]' >/dev/null
}

@test "load_test_audit_config: a malformed present config fails closed with a named error, never a silent default fallback" {
  cat > "$FIXTURE_PROJECT/.aid-o/config/test-audit.yaml" <<'YAML'
budget_minutes_default: "not-an-integer"
max_read_only_audit_agents: 4
allowed_runners: []
YAML
  run load_test_audit_config "$FIXTURE_PROJECT"
  [ "$status" -eq 1 ]
  [ -z "$output" ] || [[ "$output" == *"failed schema validation"* ]]
}

@test "load_test_audit_config: fails closed (never silently accepts) a malformed present config when the schema validator is unavailable" {
  # Regression: an earlier version treated a missing python3/jsonschema
  # validator as "skip validation, assume valid" — accepting a genuinely
  # malformed present config (e.g. budget_minutes_default: "nope") instead
  # of refusing, matching aid-plan-fsm.sh's own fail-closed precedent.
  cat > "$FIXTURE_PROJECT/.aid-o/config/test-audit.yaml" <<'YAML'
budget_minutes_default: nope
max_read_only_audit_agents: 4
allowed_runners: []
YAML
  _tac_have_jsonschema() { return 1; }
  run load_test_audit_config "$FIXTURE_PROJECT"
  [ "$status" -eq 1 ]
  [ -z "$output" ] || [[ "$output" == *"validator unavailable"* ]]
}

@test "load_test_audit_config: an unparseable YAML file fails closed, never silently substitutes defaults" {
  printf ': this is not : valid yaml : at all :::\n' > "$FIXTURE_PROJECT/.aid-o/config/test-audit.yaml"
  run load_test_audit_config "$FIXTURE_PROJECT"
  [ "$status" -eq 1 ]
}

@test "load_test_audit_config: max_read_only_audit_agents is never read/written by code touching dispatch.max_parallel or dispatch.worktrees.max_parallel" {
  run grep -rn "max_read_only_audit_agents" "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-config.sh" "$AID_PLUGIN_PATH/defaults/schemas/test-audit-config.schema.json"
  [ "$status" -eq 0 ]
  ! grep -rn "dispatch\.max_parallel\|dispatch\.worktrees\.max_parallel" "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-config.sh"
}
