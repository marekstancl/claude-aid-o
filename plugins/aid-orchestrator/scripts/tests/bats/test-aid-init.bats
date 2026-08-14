#!/usr/bin/env bats
# aid-tier: t0
# P032 Step 7 — execution.yaml composer + stack auto-detection (Step 1).
# 4 assertions covering the per-stack template fragment system.

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

@test "stack detection: pyproject.toml → python in detected stacks → execution.yaml has Python gates" {
  touch pyproject.toml
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " python " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"
  run yq '.gates | has("py_test")' .aid-o/config/execution.yaml
  [ "$output" == "true" ]
  run yq '.gates.py_test.command' .aid-o/config/execution.yaml
  [ "$output" == "pytest -q" ]
}

@test "stack detection: package.json → typescript in detected stacks → execution.yaml has TS gates" {
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " typescript " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"
  run yq '.gates | has("ts_test")' .aid-o/config/execution.yaml
  [ "$output" == "true" ]
  run yq '.gates.ts_lint.command' .aid-o/config/execution.yaml
  [[ "$output" =~ eslint ]]
}

@test "stack detection: bash threshold > 5 (6 *.sh files → bash detected, 5 → not detected)" {
  source "$HELPER"

  # 5 files: NOT detected
  for i in $(seq 1 5); do touch "s_${i}.sh"; done
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ ! " ${stacks[*]} " =~ " bash " ]]

  # 6th file: NOW detected
  touch s_6.sh
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " bash " ]]
}

@test "multi-stack: Python + TypeScript project → execution.yaml has both gate sections in correct order" {
  touch pyproject.toml package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " python " ]]
  [[ " ${stacks[*]} " =~ " typescript " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  # Both stacks present
  run yq '.gates | keys | join(",")' .aid-o/config/execution.yaml
  [[ "$output" =~ py_test ]]
  [[ "$output" =~ ts_test ]]

  # Order: detect_stacks lists python BEFORE typescript (order: python, ts, go, rust, bash).
  # Section comments preserve detection order.
  python_line=$(grep -n '# === Python' .aid-o/config/execution.yaml | head -1 | cut -d: -f1)
  ts_line=$(grep -n '# === Typescript' .aid-o/config/execution.yaml | head -1 | cut -d: -f1)
  [ "$python_line" -lt "$ts_line" ]
}

@test "P061 E1 Step 5: TypeScript fixture — execution.yaml has generic gate_profiles block, no self-host gate names" {
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " typescript " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  # gate_profile_defaults + gate_profiles block present, structurally correct
  # (same key names aid-run-gates.sh --profile / aid-fsm.sh plan-gate floor expect).
  run yq '.gate_profile_defaults.step' .aid-o/config/execution.yaml
  [ "$output" == "targeted" ]
  run yq '.gate_profile_defaults.epic' .aid-o/config/execution.yaml
  [ "$output" == "full" ]

  # Profiles reference ONLY gate names the TypeScript stack fragment itself
  # defines (ts_test/ts_lint/ts_type_check) — never self-host bats_* names —
  # plus the stack-independent targeted_tests gate (P069 Step 12), which is
  # added to `targeted` only, never `full`.
  run yq '.gate_profiles.targeted.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test,targeted_tests" ]
  run yq '.gate_profiles.full.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test,ts_lint,ts_type_check" ]

  # P083 Step 7: the full canonical ladder — quick < targeted < standard <
  # full < release. quick is empty; standard and release reuse full's set.
  run yq '.gate_profiles.quick.include | length' .aid-o/config/execution.yaml
  [ "$output" == "0" ]
  run yq '.gate_profiles.standard.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test,ts_lint,ts_type_check" ]
  run yq '.gate_profiles.release.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test,ts_lint,ts_type_check" ]

  # D3 consumer isolation (negative control): the composed file must never
  # contain self-host-only gate names, anywhere.
  run bash -c '! grep -qE "\bbats_fsm\b|\bbats_all\b|\bshell_pipeline_smoke\b" .aid-o/config/execution.yaml'
  [ "$status" -eq 0 ]
}

@test "P061 E1 Step 5: zero stacks detected — no gate_profiles block, execution.yaml still valid YAML" {
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [ "${#stacks[@]}" -eq 0 ]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  run yq -e '.gate_profiles' .aid-o/config/execution.yaml
  [ "$status" -ne 0 ] || [ "$output" == "null" ]
  run bash -c 'yq -e "." .aid-o/config/execution.yaml > /dev/null'
  [ "$status" -eq 0 ]
}

# --- P061 E1 Step 6: existing-project gate_profiles upgrade (D9) ---------

# Shared fixture builder: an existing execution.yaml with a hand-edited
# ts_test.command (different from the typescript.yaml stack default) and NO
# gate_profile_defaults/gate_profiles block yet.
_write_hand_edited_fixture() {
  mkdir -p .aid-o/config
  cat > .aid-o/config/execution.yaml <<'FIXTURE'
version: '1.0'
generated_by: manual override for TEST-FIXTURE
gates:
  ts_test:
    command: npm run test:custom -- --shard=1
    required: true
    timeout_seconds: 999
    max_retries: 2
  ts_lint:
    command: npm run lint:strict
    required: true
notifications:
  telegram:
    enabled: false
FIXTURE
  touch package.json
}

@test "P061 E1 Step 6: execution_yaml_has_gate_profiles — false on fixture without the block, true after append" {
  source "$HELPER"
  _write_hand_edited_fixture

  run execution_yaml_has_gate_profiles .aid-o/config/execution.yaml
  [ "$status" -eq 1 ]

  mapfile -t stacks < <(detect_stacks "$PWD")
  block="$(render_gate_profiles_block "${stacks[@]}")"
  append_gate_profiles_block .aid-o/config/execution.yaml "$block"

  run execution_yaml_has_gate_profiles .aid-o/config/execution.yaml
  [ "$status" -eq 0 ]
}

@test "P061 E1 Step 6: PM-confirmed upgrade — hand-edited gate command is byte-identical, only the profile block is added" {
  source "$HELPER"
  _write_hand_edited_fixture

  # Byte-exact snapshot of every line that existed BEFORE the upgrade.
  orig_line_count=$(wc -l < .aid-o/config/execution.yaml)
  cp .aid-o/config/execution.yaml .aid-o/config/execution.yaml.before

  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " typescript " ]]
  block="$(render_gate_profiles_block "${stacks[@]}")"

  # Simulate PM confirmation (Y) — this is the only call that writes.
  append_gate_profiles_block .aid-o/config/execution.yaml "$block"

  # Every original line is untouched, in place, unreordered: the first
  # orig_line_count lines of the upgraded file equal the pre-upgrade file
  # byte-for-byte.
  head -n "$orig_line_count" .aid-o/config/execution.yaml > .aid-o/config/execution.yaml.prefix-after
  run diff .aid-o/config/execution.yaml.before .aid-o/config/execution.yaml.prefix-after
  [ "$status" -eq 0 ]

  # The hand-edited command survived character-for-character (not just
  # "a value" — the exact custom flags/shard argument).
  run yq '.gates.ts_test.command' .aid-o/config/execution.yaml
  [ "$output" == "npm run test:custom -- --shard=1" ]
  run yq '.gates.ts_test.timeout_seconds' .aid-o/config/execution.yaml
  [ "$output" == "999" ]
  run yq '.gates.ts_lint.command' .aid-o/config/execution.yaml
  [ "$output" == "npm run lint:strict" ]

  # The profile block was actually added — but P083 Step 7 changed WHAT it
  # contains here: this fixture's hand-edited `gates:` mapping defines only
  # ts_test + ts_lint (no ts_type_check, no targeted_tests), and render_gate_
  # profiles_block now discovers that non-empty mapping and filters every
  # profile to gates the target file actually defines — never
  # named-and-undefined, which is the whole point of this step's "second
  # consumer" fix. (Contrast with the fresh-init test above, which composes
  # into a file with no pre-existing `gates:` and gets the UNFILTERED
  # stack-derived set, including targeted_tests and ts_type_check.)
  run yq '.gate_profile_defaults.step' .aid-o/config/execution.yaml
  [ "$output" == "targeted" ]
  run yq '.gate_profiles.targeted.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test" ]
  run yq '.gate_profiles.full.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test,ts_lint" ]
  run yq '.gate_profiles.standard.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test,ts_lint" ]
  run yq '.gate_profiles.release.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test,ts_lint" ]
  run yq '.gate_profiles.quick.include | length' .aid-o/config/execution.yaml
  [ "$output" == "0" ]
  # No profile names ts_type_check or targeted_tests — neither is in this
  # fixture's gates: mapping.
  refute_grep -qE "ts_type_check|targeted_tests" .aid-o/config/execution.yaml

  # File is still valid YAML after the additive write.
  run bash -c 'yq -e "." .aid-o/config/execution.yaml > /dev/null'
  [ "$status" -eq 0 ]
}

@test "P061 E1 Step 6: PM-NOT-confirmed — report computed but nothing written, file untouched" {
  source "$HELPER"
  _write_hand_edited_fixture

  before_hash=$(sha256sum .aid-o/config/execution.yaml | cut -d' ' -f1)

  # Report-only path: compute what WOULD be proposed, but the PM declines —
  # append_gate_profiles_block is never called. This mirrors the real
  # /aid-init flow's default-N-on-no-response rule (see aid-init.md).
  run execution_yaml_has_gate_profiles .aid-o/config/execution.yaml
  [ "$status" -eq 1 ]
  mapfile -t stacks < <(detect_stacks "$PWD")
  block="$(render_gate_profiles_block "${stacks[@]}")"
  [[ -n "$block" ]]
  pm_confirmed="N"
  if [[ "$pm_confirmed" == "Y" ]]; then
    append_gate_profiles_block .aid-o/config/execution.yaml "$block"
  fi

  after_hash=$(sha256sum .aid-o/config/execution.yaml | cut -d' ' -f1)
  [ "$before_hash" == "$after_hash" ]

  # Still has no gate_profiles block — the check would offer the upgrade
  # again on the next /aid-init run.
  run execution_yaml_has_gate_profiles .aid-o/config/execution.yaml
  [ "$status" -eq 1 ]
}

@test "P061 E1 Step 6: gate_profiles already present — no-op, execution_yaml_has_gate_profiles short-circuits" {
  source "$HELPER"
  mkdir -p .aid-o/config
  touch package.json
  mapfile -t stacks < <(detect_stacks "$PWD")
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  before_hash=$(sha256sum .aid-o/config/execution.yaml | cut -d' ' -f1)

  run execution_yaml_has_gate_profiles .aid-o/config/execution.yaml
  [ "$status" -eq 0 ]
  # (Real /aid-init flow: has_gate_profiles == true → skip the report/append
  # entirely. Nothing should be called here.)

  after_hash=$(sha256sum .aid-o/config/execution.yaml | cut -d' ' -f1)
  [ "$before_hash" == "$after_hash" ]
}

@test "P061 E1 Step 6: append_gate_profiles_block refuses to write to a missing file" {
  source "$HELPER"
  run append_gate_profiles_block .aid-o/config/execution.yaml "gate_profiles:\n  full:\n    include: []"
  [ "$status" -eq 1 ]
  [ ! -f .aid-o/config/execution.yaml ]
}

@test "P061 E1 Step 6 (D9 HIGH FIX): partial-key state — only gate_profile_defaults present — no duplicate keys after upgrade" {
  source "$HELPER"
  mkdir -p .aid-o/config

  # Fixture: PM manually set gate_profile_defaults but NOT gate_profiles yet
  cat > .aid-o/config/execution.yaml <<'FIXTURE'
version: '1.0'
generated_by: manual override for PARTIAL-TEST
gates:
  ts_test:
    command: npm test
    required: true
gate_profile_defaults:
  step: full
  epic: full
notifications:
  telegram:
    enabled: false
FIXTURE
  touch package.json

  # Verify fixture is as expected: gate_profile_defaults present, gate_profiles absent
  run yq '.gate_profile_defaults.step' .aid-o/config/execution.yaml
  [ "$output" == "full" ]
  run yq '.gate_profiles' .aid-o/config/execution.yaml
  [ "$output" == "null" ]

  # With the fix (option a): execution_yaml_has_gate_profiles should return 0
  # (partial state exists, don't touch it)
  run execution_yaml_has_gate_profiles .aid-o/config/execution.yaml
  [ "$status" -eq 0 ]

  # Even if upgrade path is called anyway (backward compat or edge case),
  # ensure NO duplicate top-level keys are created.
  # Count occurrences of "gate_profile_defaults:" at column 0 (key name only).
  run bash -c 'grep -c "^gate_profile_defaults:" .aid-o/config/execution.yaml'
  [ "$output" -eq 1 ]

  # Verify hand-edited value is still accessible / not shadowed
  run yq '.gate_profile_defaults.step' .aid-o/config/execution.yaml
  [ "$output" == "full" ]
}

@test "P061 E1 Step 6 (D9 HIGH FIX): partial-key state — only gate_profiles present — no duplicate keys after upgrade" {
  source "$HELPER"
  mkdir -p .aid-o/config

  # Fixture: PM manually started gate_profiles but NOT gate_profile_defaults yet
  cat > .aid-o/config/execution.yaml <<'FIXTURE'
version: '1.0'
generated_by: manual override for PARTIAL-TEST
gates:
  ts_test:
    command: npm test
    required: true
gate_profiles:
  custom:
    include: [ts_test]
notifications:
  telegram:
    enabled: false
FIXTURE
  touch package.json

  # Verify fixture is as expected: gate_profiles present, gate_profile_defaults absent
  run yq '.gate_profiles.custom.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test" ]
  run yq '.gate_profile_defaults' .aid-o/config/execution.yaml
  [ "$output" == "null" ]

  # With the fix (option a): execution_yaml_has_gate_profiles should return 0
  # (partial state exists, don't touch it)
  run execution_yaml_has_gate_profiles .aid-o/config/execution.yaml
  [ "$status" -eq 0 ]

  # Even if upgrade path is called anyway (backward compat or edge case),
  # ensure NO duplicate top-level keys are created.
  # Count occurrences of "gate_profiles:" at column 0 (key name only).
  run bash -c 'grep -c "^gate_profiles:" .aid-o/config/execution.yaml'
  [ "$output" -eq 1 ]

  # Verify hand-edited value is still accessible / not shadowed
  run yq '.gate_profiles.custom.include | join(",")' .aid-o/config/execution.yaml
  [ "$output" == "ts_test" ]
}
