#!/usr/bin/env bats
# test-aid-self-host-migrate-p071-gates.bats — P071 EPIC E-071-1_1 (PM review
# round 2).
#
# Covers aid-self-host-migrate-p071-gates.sh, the persistence mechanism for
# P071's execution.yaml changes (gitignored, so a clean checkout / fresh
# /aid-init would otherwise silently lose them). Three things must be true:
#   1. `verify` against a FRESH (unmigrated) execution.yaml fails loudly
#      (exit 1) and names every missing migration.
#   2. `apply` on that same fresh file adds all 6 migrations, and a
#      subsequent `verify` then passes.
#   3. `apply` is idempotent: running it twice produces a byte-identical
#      file (the second run applies zero migrations).
#   4. THE LIVE GUARD: `verify` against THIS REPO's real, current
#      `.aid-o/config/execution.yaml` passes RIGHT NOW. If a future clean
#      /aid-init, a reverted commit, or any other change silently drops
#      one of these gate migrations, this test (part of the normal suite)
#      fails loudly and names exactly what's missing — that is the whole
#      point of this mechanism.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../aid-self-host-migrate-p071-gates.sh"
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../../../.." && pwd)"
  TMP="$(mktemp -d)"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

_write_fresh_execution_yaml() {
  cat > "$1" <<'YAML'
version: '1.0'
gates:
  bats_fsm:
    command: bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats
    required: true
    timeout_seconds: 300
    max_retries: 1
  bats_all:
    command: "echo 'BATS_ALL_QUARANTINED' >&2; exit 86"
    required: true
    timeout_seconds: 10
    max_retries: 0
  shell_pipeline_smoke:
    command: bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh
    required: false
    timeout_seconds: 1900
    max_retries: 0
  plan_diff:
    command: plugins/aid-orchestrator/scripts/aid-plan-diff.sh --plan {plan_path}
    timeout_seconds: 120
    max_retries: 0
gate_profiles:
  full:
    include:
      - bats_fsm
      - bats_all
  release:
    include:
      - bats_fsm
      - bats_all
      - shell_pipeline_smoke
YAML
}

@test "verify: a fresh (unmigrated) execution.yaml fails loudly (exit 1), naming every missing migration" {
  local exec_yaml="$TMP/execution.yaml"
  _write_fresh_execution_yaml "$exec_yaml"

  run bash "$SCRIPT" verify --execution-yaml "$exec_yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"m1_plan_diff_timeout"* ]]
  [[ "$output" == *"m2_shell_pipeline_smoke_description"* ]]
  [[ "$output" == *"m3_bats_all_split"* ]]
  [[ "$output" == *"m4_bats_boundary_gate"* ]]
  [[ "$output" == *"m5_full_profile_has_boundary"* ]]
  [[ "$output" == *"m6_release_profile_has_boundary"* ]]
  [[ "$output" == *"6 P071 gate migration(s)"* ]]
}

@test "apply: adds all 6 migrations to a fresh execution.yaml, and verify then passes" {
  local exec_yaml="$TMP/execution.yaml"
  _write_fresh_execution_yaml "$exec_yaml"

  run bash "$SCRIPT" apply --execution-yaml "$exec_yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"6 migration(s) applied, 0 already present"* ]]

  run bash "$SCRIPT" verify --execution-yaml "$exec_yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 6 P071 gate migrations present"* ]]

  # Spot-check the actual resulting values, not just the verify verdict.
  [ "$(yq -r '.gates.plan_diff.timeout_seconds' "$exec_yaml")" = "300" ]
  [ "$(yq -r '.gates.bats_boundary.required' "$exec_yaml")" = "false" ]
  local full_include
  full_include="$(yq -r '.gate_profiles.full.include[]' "$exec_yaml")"
  [[ "$full_include" == *"bats_boundary"* ]]
}

@test "apply: writes a local receipt recording what was applied + a config sha256" {
  local exec_yaml="$TMP/.aid-o/config/execution.yaml"
  mkdir -p "$(dirname "$exec_yaml")"
  _write_fresh_execution_yaml "$exec_yaml"

  run bash "$SCRIPT" apply --execution-yaml "$exec_yaml"
  [ "$status" -eq 0 ]

  local receipt="$TMP/.aid-o/config/.p071-execution-migration-receipt.json"
  [ -f "$receipt" ]
  run jq -e '.schema_version == "1.0.0" and .migration == "P071-execution-yaml-gates"' "$receipt"
  [ "$status" -eq 0 ]
  run jq -e '.applied_this_run | length == 6' "$receipt"
  [ "$status" -eq 0 ]
  run jq -e '.config_sha256 | test("^sha256:[0-9a-f]{64}$")' "$receipt"
  [ "$status" -eq 0 ]
  local recorded_hash real_hash
  recorded_hash="$(jq -r '.config_sha256' "$receipt")"
  real_hash="sha256:$(sha256sum "$exec_yaml" | cut -d' ' -f1)"
  [ "$recorded_hash" = "$real_hash" ]
}

@test "apply is idempotent: a second run on an already-migrated file is byte-identical and applies zero migrations" {
  local exec_yaml="$TMP/execution.yaml"
  _write_fresh_execution_yaml "$exec_yaml"
  run bash "$SCRIPT" apply --execution-yaml "$exec_yaml"
  [ "$status" -eq 0 ]

  local before_hash
  before_hash="$(sha256sum "$exec_yaml" | cut -d' ' -f1)"

  run bash "$SCRIPT" apply --execution-yaml "$exec_yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 migration(s) applied, 6 already present"* ]]

  local after_hash
  after_hash="$(sha256sum "$exec_yaml" | cut -d' ' -f1)"
  [ "$before_hash" = "$after_hash" ]
}

@test "apply preserves a hand-edited, unrelated gate untouched (PM customization survives)" {
  local exec_yaml="$TMP/execution.yaml"
  _write_fresh_execution_yaml "$exec_yaml"
  yq -i '.gates.docs_updated.command = "echo hand-written custom check"' "$exec_yaml"

  run bash "$SCRIPT" apply --execution-yaml "$exec_yaml"
  [ "$status" -eq 0 ]

  [ "$(yq -r '.gates.docs_updated.command' "$exec_yaml")" = "echo hand-written custom check" ]
}

@test "verify: a partially-migrated file (only m1 applied) names ONLY the remaining 5" {
  local exec_yaml="$TMP/execution.yaml"
  _write_fresh_execution_yaml "$exec_yaml"
  yq -i '.gates.plan_diff.timeout_seconds = 300' "$exec_yaml"

  run bash "$SCRIPT" verify --execution-yaml "$exec_yaml"
  [ "$status" -eq 1 ]
  [[ "$output" != *"m1_plan_diff_timeout"* ]]
  [[ "$output" == *"m2_shell_pipeline_smoke_description"* ]]
  [[ "$output" == *"m3_bats_all_split"* ]]
  [[ "$output" == *"m4_bats_boundary_gate"* ]]
  [[ "$output" == *"m5_full_profile_has_boundary"* ]]
  [[ "$output" == *"m6_release_profile_has_boundary"* ]]
  [[ "$output" == *"5 P071 gate migration(s)"* ]]
}

@test "REGRESSION: gates.bats_boundary.required: false is correctly detected as satisfied (jq's // falsy-false bug guard)" {
  # A naive `.required // ""` check would treat a real `false` as absent
  # (jq's `//` treats both null AND false as the "use the default" case) —
  # this test proves the migration check does NOT fall into that trap.
  local exec_yaml="$TMP/execution.yaml"
  _write_fresh_execution_yaml "$exec_yaml"
  run bash "$SCRIPT" apply --execution-yaml "$exec_yaml"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" verify --execution-yaml "$exec_yaml"
  [ "$status" -eq 0 ]
  [[ "$output" != *"m4_bats_boundary_gate"* ]]
}

# --- Usage / fail-closed CLI handling ---------------------------------------

@test "usage: no subcommand fails loudly (exit 2)" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "usage: unknown subcommand fails loudly (exit 2)" {
  run bash "$SCRIPT" bogus-subcommand
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

@test "usage: missing execution.yaml fails loudly (exit 2)" {
  run bash "$SCRIPT" verify --execution-yaml "$TMP/does-not-exist.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "usage: malformed (non-YAML) execution.yaml fails loudly (exit 2)" {
  local exec_yaml="$TMP/execution.yaml"
  printf 'not: [valid: yaml: at all\n' > "$exec_yaml"
  run bash "$SCRIPT" verify --execution-yaml "$exec_yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid YAML"* ]]
}

@test "usage: -h/--help exits 0 and prints usage" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# --- Live guard: THIS repo's own execution.yaml must pass, right now -------

@test "LIVE GUARD: this repo's real .aid-o/config/execution.yaml currently satisfies all 6 P071 migrations" {
  local real_exec_yaml="${REPO_ROOT}/.aid-o/config/execution.yaml"
  [ -f "$real_exec_yaml" ] || skip "no local .aid-o/config/execution.yaml in this checkout (never ran /aid-init here) — nothing to guard yet"

  run bash "$SCRIPT" verify --execution-yaml "$real_exec_yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 6 P071 gate migrations present"* ]]
}
