#!/usr/bin/env bats
# aid-tier: t1
# P083 Step 7 — a stack-detected /aid-init workspace must yield the FULL
# canonical gate-profile ladder (quick < targeted < standard < full <
# release), with a non-empty `release`, so a fresh consumer project can
# reach plan-finalize without hitting an empty `release` profile.

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  cd "$TEST_TMPDIR"
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  HELPER="$AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh"
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

@test "a stack-detected workspace yields all five profiles, each naming only defined gates, release non-empty" {
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " typescript " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  for profile in quick targeted standard full release; do
    run yq -e ".gate_profiles.${profile}" .aid-o/config/execution.yaml
    [ "$status" -eq 0 ]
  done

  run yq '.gate_profiles.release.include | length' .aid-o/config/execution.yaml
  [ "$output" -gt 0 ]

  # Every gate named in every profile is actually defined under .gates.
  local defined_gates all_named name
  defined_gates="$(yq -r '.gates | keys | .[]' .aid-o/config/execution.yaml)"
  all_named="$(yq -r '.gate_profiles[].include[]' .aid-o/config/execution.yaml | sort -u)"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    # Whole-line membership, in bash — no `grep -q` in a pipeline (its early
    # exit races SIGPIPE against pipefail and can fail spuriously).
    [[ $'\n'"$defined_gates"$'\n' == *$'\n'"$name"$'\n'* ]]
  done <<< "$all_named"
}

@test "_pfsm_profile_include resolves release against the composed file to a non-empty set (not gate_profile_max)" {
  # gate_profile_max reads a static rank map and would pass vacuously even
  # if `release` had no include[] at all — this must drive the ACTUAL
  # composed file's release profile.
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  run bash -c '
    source "'"$PFSM"'" 2>/dev/null
    _pfsm_profile_include ".aid-o/config/execution.yaml" "release"
  '
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "zero stacks detected: no gate_profiles table, and the audited legacy fallback still fires with its named reason" {
  # No package.json/pyproject.toml/etc — no stack detected.
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [ "${#stacks[@]}" -eq 0 ]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  run yq -e '.gate_profiles' .aid-o/config/execution.yaml
  [ "$status" -ne 0 ]

  run bash -c '
    source "'"$PFSM"'" 2>/dev/null
    _pfsm_has_gate_profiles "'"$TEST_TMPDIR"'"
  '
  [ "$status" -ne 0 ]

  run bash -c '
    source "'"$PFSM"'" 2>/dev/null
    _pfsm_default_mode "'"$TEST_TMPDIR"'"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"legacy_epic_release_mode"* ]]
  [[ "$output" == *"no_gate_profiles"* ]]
}

@test "an upgrade against a hand-authored config with a narrower gate set omits undefined gates from every profile" {
  mkdir -p .aid-o/config
  cat > .aid-o/config/execution.yaml <<'EOF'
version: '1.0'
gates:
  ts_test:
    command: npm test
    required: true
EOF
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " typescript " ]]
  local block
  block="$(render_gate_profiles_block "${stacks[@]}")"
  append_gate_profiles_block .aid-o/config/execution.yaml "$block"

  run yq '.gate_profiles.full.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test" ]
  run yq '.gate_profiles.release.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test" ]
  refute_grep -qE "ts_lint|ts_type_check|targeted_tests" .aid-o/config/execution.yaml

  # File is still valid YAML after the additive, filtered write.
  run bash -c 'yq -e "." .aid-o/config/execution.yaml > /dev/null'
  [ "$status" -eq 0 ]
}
