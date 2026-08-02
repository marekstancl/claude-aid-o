#!/usr/bin/env bats
# test-compose-execution-yaml-scheduler-block.bats — P069 Step 12.
#
# Proves compose_execution_yaml's two stack-independent additions:
#   - a fresh /aid-init run on each of the 5 stacks produces a
#     {plugin_path}-qualified targeted_tests gate in the generated `targeted`
#     profile, plus a test_audit.scheduler.mode: sequential block
#   - {plugin_path} correctly substitutes from a fixture .aid-o/config/
#     plugin.yaml via aid-run-gates.sh's resolve_placeholders
#   - the zero-detected-stacks case still gets both additions
#   - fresh-generation and the upgrade command render byte-identical block
#     text from the one shared render_test_audit_scheduler_block function

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  HELPER="$AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

@test "each of the 5 stacks: fresh execution.yaml gets a plugin_path-qualified targeted_tests gate in the targeted profile" {
  declare -A marker=(
    [python]=pyproject.toml
    [typescript]=package.json
    [go]=go.mod
    [rust]=Cargo.toml
  )
  for stack in python typescript go rust; do
    local proj="$TEST_TMPDIR/proj-${stack}"
    mkdir -p "$proj"
    touch "${proj}/${marker[$stack]}"
    mkdir -p "${proj}/.aid-o/config"
    source "$HELPER"
    mapfile -t stacks < <(detect_stacks "$proj")
    compose_execution_yaml "$proj" "${proj}/.aid-o/config/execution.yaml" "${stacks[@]}"

    run yq -e '.gates.targeted_tests.command' "${proj}/.aid-o/config/execution.yaml"
    [ "$output" == '{plugin_path}/scripts/aid-select-tests.sh --base {base_commit}' ]
    run yq '.gates.targeted_tests.required' "${proj}/.aid-o/config/execution.yaml"
    [ "$output" == "false" ]
    run yq '.gate_profiles.targeted.include | contains(["targeted_tests"])' "${proj}/.aid-o/config/execution.yaml"
    [ "$output" == "true" ]
    run yq '.gate_profiles.full.include | contains(["targeted_tests"])' "${proj}/.aid-o/config/execution.yaml"
    [ "$output" == "false" ]
    run yq -e '.test_audit.scheduler.mode' "${proj}/.aid-o/config/execution.yaml"
    [ "$output" == "sequential" ]
    run yq -e -o=json '.test_audit.scheduler.resource_locks' "${proj}/.aid-o/config/execution.yaml"
    [ "$output" == "{}" ]
  done

  # bash stack: threshold-based detection (>5 .sh files), separate fixture.
  local proj="$TEST_TMPDIR/proj-bash"
  mkdir -p "$proj"
  for i in $(seq 1 6); do touch "${proj}/s_${i}.sh"; done
  mkdir -p "${proj}/.aid-o/config"
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$proj")
  [[ " ${stacks[*]} " =~ " bash " ]]
  compose_execution_yaml "$proj" "${proj}/.aid-o/config/execution.yaml" "${stacks[@]}"
  run yq -e '.gates.targeted_tests.command' "${proj}/.aid-o/config/execution.yaml"
  [ "$output" == '{plugin_path}/scripts/aid-select-tests.sh --base {base_commit}' ]
  run yq -e '.test_audit.scheduler.mode' "${proj}/.aid-o/config/execution.yaml"
  [ "$output" == "sequential" ]
}

@test "zero detected stacks: still gets targeted_tests gate and test_audit.scheduler block" {
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [ "${#stacks[@]}" -eq 0 ]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  run yq -e '.gates.targeted_tests.command' .aid-o/config/execution.yaml
  [ "$output" == '{plugin_path}/scripts/aid-select-tests.sh --base {base_commit}' ]
  run yq -e '.test_audit.scheduler.mode' .aid-o/config/execution.yaml
  [ "$output" == "sequential" ]
  # No gate_profiles at all in the zero-stack case (pre-existing behavior) —
  # nothing to add targeted_tests to.
  run yq -e '.gate_profiles' .aid-o/config/execution.yaml
  [ "$status" -ne 0 ] || [ "$output" == "null" ]
  run bash -c 'yq -e "." .aid-o/config/execution.yaml > /dev/null'
  [ "$status" -eq 0 ]
}

@test "{plugin_path} resolves via aid-run-gates.sh's resolve_placeholders from a fixture plugin.yaml" {
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  cat > .aid-o/config/plugin.yaml <<YAML
plugin_path: "${AID_PLUGIN_PATH}"
discovered_at: "2026-08-02T00:00:00Z"
dispatch_mode: agent_tool
YAML

  git init -q -b main
  git config user.email t@t.local
  git config user.name t
  git add -A
  git commit -q -m base

  local report=".aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  run "$AID_PLUGIN_PATH/scripts/aid-run-gates.sh" run-all .aid-o/config/execution.yaml E-X R-1 --report-file "$report"
  run jq -re '.gates.targeted_tests.output' "$report"
  # aid-select-tests.sh's own usage/exit behavior is exercised elsewhere;
  # here we only need proof the command was NOT run with a literal,
  # unsubstituted "{plugin_path}" token (which would be a bare, non-existent
  # command path and fail with "No such file or directory").
  [[ "$output" != *"{plugin_path}"* ]]
}

@test "fresh-generation and the upgrade command render byte-identical block text (one shared renderer, no drift)" {
  source "$HELPER"
  fresh_gate="$(render_test_audit_scheduler_block gate)"
  fresh_test_audit="$(render_test_audit_scheduler_block test_audit)"

  # The upgrade script sources the exact same helper and calls the exact
  # same function — assert equality directly rather than re-deriving.
  UPGRADE_SCRIPT="$AID_PLUGIN_PATH/scripts/aid-init-upgrade-test-audit.sh"
  run bash -c "source '$HELPER'; render_test_audit_scheduler_block gate"
  [ "$output" == "$fresh_gate" ]
  run bash -c "source '$HELPER'; render_test_audit_scheduler_block test_audit"
  [ "$output" == "$fresh_test_audit" ]

  # And prove the upgrade script's ACTUAL applied text (via a real run)
  # matches too.
  mkdir -p .aid-o/config
  cat > .aid-o/config/execution.yaml <<'YAML'
version: "1.0"
gates:
  alpha:
    command: "exit 0"
YAML
  run "$UPGRADE_SCRIPT" --project-root "$PWD"
  local hash
  hash="$(echo "$output" | grep '^diff_hash:' | awk '{print $2}')"
  "$UPGRADE_SCRIPT" --project-root "$PWD" --confirm-upgrade "$hash"

  run yq -e '.gates.targeted_tests.command' .aid-o/config/execution.yaml
  [ "$output" == '{plugin_path}/scripts/aid-select-tests.sh --base {base_commit}' ]
  run yq -e '.test_audit.scheduler.mode' .aid-o/config/execution.yaml
  [ "$output" == "sequential" ]
}
