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

@test "a stack-detected workspace yields the four list profiles narrowest first, each naming only defined gates, release non-empty" {
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " typescript " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  # P097 Step 4: ordered list, no quick, no gate_profile_defaults,
  # default_profile standard, when_paths on full only.
  run yq -r '.gate_profiles | keys | join(",")' .aid-o/config/execution.yaml
  [ "$output" = "targeted,standard,full,release" ]
  run yq -r '.default_profile' .aid-o/config/execution.yaml
  [ "$output" = "standard" ]
  run yq '.gate_profile_defaults' .aid-o/config/execution.yaml
  [ "$output" = "null" ]
  run yq -r '[.gate_profiles[] | has("when_paths")] | join(",")' .aid-o/config/execution.yaml
  [ "$output" = "false,false,true,false" ]

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

@test "P083 Step 7 (Codex review finding): a target file that fails to parse gets an EMPTY ladder, never the unfiltered one" {
  # A parse failure is not the same as "no gates: mapping present" — the
  # target might define gates perfectly well and be broken elsewhere.
  # Falling back to unfiltered would risk naming an undefined gate; the
  # safe failure mode is an empty include[] everywhere, loudly warned.
  mkdir -p .aid-o/config
  cat > .aid-o/config/execution.yaml <<'EOF'
version: '1.0'
gates:
  ts_test:
    command: npm test
  this is not: [valid yaml
EOF
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  run render_gate_profiles_block "${stacks[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"*"did not parse as YAML"* ]]
  # Every candidate gate is filtered out (defined_gates stays empty), which
  # degenerates to the same "no stacks detected" fallback the zero-stacks
  # case uses — never the unfiltered ts_test/ts_lint/ts_type_check set.
  [[ "$output" == *"no stacks detected"* ]]
  refute_grep -q "ts_test" <(echo "$output")
}

@test "P083 Step 7 (whole-diff Codex review finding): compose_execution_yaml filters against its own output_file, not CWD" {
  # test-init-idempotency.sh's real shape: compose into an ARBITRARY path
  # while CWD is unrelated and has its OWN, DIFFERENT .aid-o/config/
  # execution.yaml sitting around. The pre-fix code hard-coded the
  # CWD-relative default, so it filtered against (or fell back to
  # unfiltered because of) the wrong file entirely.
  mkdir -p "$TEST_TMPDIR/cwd-with-unrelated-config/.aid-o/config"
  cat > "$TEST_TMPDIR/cwd-with-unrelated-config/.aid-o/config/execution.yaml" <<'EOF'
gates:
  totally_unrelated_gate:
    command: echo hi
EOF
  cd "$TEST_TMPDIR/cwd-with-unrelated-config"

  local fixture="$TEST_TMPDIR/fixture-project"
  mkdir -p "$fixture"
  touch "$fixture/package.json"
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$fixture")
  [[ " ${stacks[*]} " =~ " typescript " ]]

  local out="$TEST_TMPDIR/arbitrary-output-path.yaml"
  compose_execution_yaml "$fixture" "$out" "${stacks[@]}"

  # The composed file's own profiles are unfiltered (its own gates: mapping
  # was just truncated by the compose itself, so nothing to filter against) —
  # the full ts_test/ts_lint/ts_type_check set, never totally_unrelated_gate.
  run yq '.gate_profiles.full.include | join(",")' "$out"
  [ "$output" == "ts_test,ts_lint,ts_type_check" ]
  refute_grep -q "totally_unrelated_gate" "$out"

  # The unrelated CWD config is untouched.
  run yq '.gates.totally_unrelated_gate.command' "$TEST_TMPDIR/cwd-with-unrelated-config/.aid-o/config/execution.yaml"
  [ "$output" == "echo hi" ]
}

# ─── P097 Step 3: the upgrade over the eight project fixtures ────────────────

@test "P097 Step 3: on every project fixture the upgrade changes nothing but the named removals and the two additions, and the result parses" {
  source "$HELPER"
  local fixtures="$AID_PLUGIN_PATH/scripts/tests/fixtures/gates/projects"
  # The semantic view of "only the named keys": the original minus the dead
  # keys must equal the upgraded file minus the two additions — every command,
  # include[], comment-free value and custom key survives.
  local strip_dead='del(.gate_profile_defaults, .baseline, .runtime_baseline, .needs_services, .services)
    | del(.gate_profiles.quick | select(. != null and (.include // [] | length == 0)))
    | (.gates // {})[] |= del(.required_when, .needs_services, .services, .quarantine, .baseline, .runtime_baseline)
    | del(.notifications.telegram.enabled, .notifications.telegram.chat_id, .notifications.telegram.alert_threshold, .notifications.telegram.alert_on_repeated_precondition_fail)
    | del(.notifications.telegram | select(length == 0))
    | del(.notifications | select(length == 0))'
  local strip_added='del(.default_profile, .gate_profiles.full.when_paths)'
  local name cfg out hash default_arg
  for name in acta agents aid-orchestrator aid-testbed krok sousto-na-miru vulcan wan; do
    cfg="$TEST_TMPDIR/$name.yaml"
    cp "$fixtures/$name.yaml" "$cfg"
    default_arg=()
    [[ "$name" == "agents" ]] && default_arg=(--default-profile full)   # declares no `standard`
    rc=0; out="$(execution_yaml_upgrade "$cfg" "${default_arg[@]}")" || rc=$?
    if [[ "$name" == "krok" ]]; then   # never had a dead key nor a profile table
      [ "$rc" -eq 0 ]; [[ "$out" == nothing\ to\ upgrade* ]]; continue
    fi
    [ "$rc" -eq 3 ]
    # Every added line is default_profile or the when_paths block, nothing else.
    run bash -c "printf '%s\n' \"\$1\" | grep -E '^\+[^+]' | grep -vE '^\+(default_profile: |    when_paths:|      - \")'" _ "$out"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    hash="$(printf '%s\n' "$out" | sed -n 's/^diff_hash: //p')"
    execution_yaml_upgrade "$cfg" --confirm-upgrade "$hash" "${default_arg[@]}"
    yq '.' "$cfg" >/dev/null
    [ "$(yq -o=json "$strip_dead" "$fixtures/$name.yaml")" == "$(yq -o=json "$strip_added" "$cfg")" ]
    # Nothing dead survives.
    [ "$(yq '[.. | select(tag == "!!map") | keys[] | select(test("^(required_when|needs_services|services|gate_profile_defaults|baseline.*|runtime_baseline|quarantine|enabled|chat_id|alert_threshold|alert_on_repeated_precondition_fail)$"))] | length' "$cfg")" -eq 0 ]
    if [[ "$(yq '.gate_profiles | type' "$cfg")" == "!!map" ]]; then
      [ "$(yq '.default_profile' "$cfg")" != "null" ]
      [[ "$(yq '.gate_profiles | has("full")' "$cfg")" == "false" ]] || [ "$(yq '.gate_profiles.full.when_paths | length' "$cfg")" -eq 14 ]
    fi
  done
}

@test "P097 Step 3: the upgraded when_paths agree with the old classifier's gate_profile_is_high_risk_path on ten changed-path sets" {
  source "$HELPER"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-ancillary.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-gate-profile.sh"
  cfg="$TEST_TMPDIR/acta.yaml"
  cp "$AID_PLUGIN_PATH/scripts/tests/fixtures/gates/projects/acta.yaml" "$cfg"
  hash="$(execution_yaml_upgrade "$cfg" | sed -n 's/^diff_hash: //p')"
  execution_yaml_upgrade "$cfg" --confirm-upgrade "$hash"
  mapfile -t globs < <(yq '.gate_profiles.full.when_paths[]' "$cfg")
  [ "${#globs[@]}" -eq 14 ]

  # Ten sets, one path per line; a set is high-risk iff one of its paths is.
  local -a sets=(
    "plugins/aid-orchestrator/scripts/aid-fsm.sh"
    "docs/plans/P097.md README.md"
    "scripts/aid-run-gates.sh scripts/lib/aid-gate-row.sh"
    "plugins/aid-orchestrator/defaults/schemas/plan.schema.json"
    "plugins/aid-orchestrator/defaults/policies/review-profiles.yaml"
    "plugins/aid-orchestrator/agents/implementer.md CHANGELOG.md"
    "scripts/lib/aid-fsm-helpers.sh scripts/tests/bats/test-aid-fsm.bats"
    "aid-release-policy.sh"
    "backend/app/main.py frontend/src/App.tsx"
    "aid-evidence-verify.sh defaults/schemas/x.json docs/agents/readme.md"
  )
  local set path old new g
  for set in "${sets[@]}"; do
    for path in $set; do
      old=0; gate_profile_is_high_risk_path "$path" && old=1
      new=0
      for g in "${globs[@]}"; do _aid_ancillary_glob_match "$path" "$g" && { new=1; break; }; done
      [ "$old" -eq "$new" ] || { echo "disagree on $path: classifier=$old when_paths=$new" >&2; return 1; }
    done
  done
  # Both sides of the split are exercised: high-risk and not.
  gate_profile_is_high_risk_path "scripts/aid-run-gates.sh"
  ! gate_profile_is_high_risk_path "backend/app/main.py"
}
