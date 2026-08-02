#!/usr/bin/env bats
# test-aid-gate-runtime-baseline-concurrency.bats — P069 Step 3.
#
# Proves gate_baseline_update's optional 7th arg (concurrency_context):
#   - a sequential call (or a pre-Step-3 6-arg call) is BYTE-IDENTICAL to
#     this function's pre-Step-3 behavior
#   - a non-sequential (observe_parallel|parallel) sample NEVER enters
#     .recent_samples or the top-level percentile fields — asserted as
#     byte-identical .recent_samples content, not merely "same decision"
#   - percentiles_by_context.<ctx> is computed ONLY from
#     recent_samples_by_context.<ctx>
#   - every existing reader (gate_baseline_policy_check, and the
#     p95/timeout-recommendation fields aid-run-gates.sh reads) produces an
#     identical result on a mixed-context fixture as it would have before
#     this step
#   - a pre-migration entry (no concurrency fields at all) remains readable
#   - a gate's FIRST-EVER sample being non-sequential still produces a
#     valid, schema-consistent zero-sample sequential stub

setup() {
  export TZ=UTC
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  LIB="$PLUGIN_ROOT/scripts/lib/aid-gate-runtime-baseline.sh"
  WORK="$(mktemp -d)"
  export AID_GATE_BASELINE_FILE="$WORK/gate-runtime-baselines.yaml"
  # shellcheck disable=SC1090
  source "$LIB"
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

@test "an explicit 'sequential' 7th arg produces byte-identical output to a 6-arg call" {
  gate_baseline_update "gate_seq_a" "tpl" "resolved" 0 1000 60
  yq -o=json '.gates.gate_seq_a' "$AID_GATE_BASELINE_FILE" > "$WORK/six_arg.json"
  rm -f "$AID_GATE_BASELINE_FILE"

  gate_baseline_update "gate_seq_a" "tpl" "resolved" 0 1000 60 "sequential"
  yq -o=json '.gates.gate_seq_a' "$AID_GATE_BASELINE_FILE" > "$WORK/seven_arg.json"

  # last_updated/series_reset_at/recent_samples[].recorded_at are the only
  # fields expected to legitimately differ (wall-clock).
  _strip() { jq 'del(.last_updated, .series_reset_at) | .recent_samples |= map(del(.recorded_at))' "$1"; }
  diff <(_strip "$WORK/six_arg.json") <(_strip "$WORK/seven_arg.json")
}

@test "a non-sequential sample never enters .recent_samples — asserted byte-identical, not just same decision" {
  gate_baseline_update "gate_mix" "tpl" "resolved" 0 1000 60 "sequential"
  gate_baseline_update "gate_mix" "tpl" "resolved" 0 2000 60 "sequential"
  before="$(yq -o=json '.gates.gate_mix.recent_samples' "$AID_GATE_BASELINE_FILE")"

  gate_baseline_update "gate_mix" "tpl" "resolved" 0 999999 60 "parallel"

  after="$(yq -o=json '.gates.gate_mix.recent_samples' "$AID_GATE_BASELINE_FILE")"
  [ "$before" = "$after" ]

  # Top-level percentile fields are also untouched by the non-sequential call.
  run yq '.gates.gate_mix.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]
  run yq '.gates.gate_mix.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2000" ]
}

@test "percentiles_by_context.<ctx> is computed only from recent_samples_by_context.<ctx>" {
  gate_baseline_update "gate_ctx" "tpl" "resolved" 0 1000 60 "sequential"
  gate_baseline_update "gate_ctx" "tpl" "resolved" 0 5000 60 "parallel"
  gate_baseline_update "gate_ctx" "tpl" "resolved" 0 9000 60 "parallel"

  run yq '.gates.gate_ctx.percentiles_by_context.parallel.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]
  run yq '.gates.gate_ctx.percentiles_by_context.parallel.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "9000" ]
  # The sequential top-level series is untouched by the two parallel samples.
  run yq '.gates.gate_ctx.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
  run yq '.gates.gate_ctx.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1000" ]
  # observe_parallel context is untouched (never written).
  run yq '.gates.gate_ctx.percentiles_by_context.observe_parallel' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "null" ]
}

@test "existing readers produce an identical decision on a mixed-context fixture" {
  # 3 sequential timeouts at the current timeout_seconds -> gate_baseline_policy_check "block".
  gate_baseline_update "gate_block" "tpl" "resolved" 124 9999 30 "sequential"
  gate_baseline_update "gate_block" "tpl" "resolved" 124 9999 30 "sequential"
  gate_baseline_update "gate_block" "tpl" "resolved" 124 9999 30 "sequential"
  run gate_baseline_policy_check "gate_block" 30
  [ "$output" = "block" ]

  # A parallel sample recorded afterward must not change the verdict.
  gate_baseline_update "gate_block" "tpl" "resolved" 0 100 30 "parallel"
  run gate_baseline_policy_check "gate_block" 30
  [ "$output" = "block" ]
}

@test "a pre-migration entry (no concurrency_context fields at all) remains readable" {
  local real_fp; real_fp="$(gate_baseline_fingerprint "gate_legacy" "legacy-tpl")"
  cat > "$AID_GATE_BASELINE_FILE" <<YAML
gates:
  gate_legacy:
    command_fingerprint: $real_fp
    command_template: legacy-tpl
    last_resolved_command: legacy-tpl
    samples_count: 1
    non_censored_samples_count: 1
    recent_samples:
      - duration_ms: 1000
        exit_code: 0
        timeout_seconds: 60
        censored: false
        recorded_at: "2026-01-01T00:00:00.000Z"
    p50_ms: 1000
    p90_ms: 1000
    p95_ms: 1000
    max_ms: 1000
    last_duration_ms: 1000
    last_exit_code: 0
    last_attempt_result: pass
    policy_result: none
    last_timeout_seconds: 60
    timeout_recommended_seconds: null
    run_mode_recommended: null
    retryable: true
    operator_action: null
    last_updated: "2026-01-01T00:00:00.000Z"
    series_reset_at: null
YAML

  run gate_baseline_policy_check "gate_legacy" 60
  [ "$output" = "no-block" ]

  gate_baseline_update "gate_legacy" "legacy-tpl" "legacy-tpl" 0 1200 60 "sequential"
  run yq '.gates.gate_legacy.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]

  gate_baseline_update "gate_legacy" "legacy-tpl" "legacy-tpl" 0 500 60 "parallel"
  run yq '.gates.gate_legacy.percentiles_by_context.parallel.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "500" ]
  # The legacy sequential series is untouched by the parallel sample.
  run yq '.gates.gate_legacy.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]
}

@test "a gate's first-ever sample being non-sequential still produces a valid zero-sample sequential stub" {
  gate_baseline_update "gate_first_parallel" "tpl" "resolved" 0 4000 60 "observe_parallel"

  run yq '.gates.gate_first_parallel.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "0" ]
  run yq '.gates.gate_first_parallel.recent_samples | length' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "0" ]
  run yq '.gates.gate_first_parallel.p50_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "null" ]
  run yq '.gates.gate_first_parallel.percentiles_by_context.observe_parallel.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
  run yq '.gates.gate_first_parallel.percentiles_by_context.observe_parallel.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "4000" ]
  run gate_baseline_policy_check "gate_first_parallel" 60
  [ "$output" = "no-block" ]
}

@test "an invalid concurrency_context is rejected (fail open, skip write) — existing entry untouched" {
  gate_baseline_update "gate_invalid_ctx" "tpl" "resolved" 0 1000 60 "sequential"
  run gate_baseline_update "gate_invalid_ctx" "tpl" "resolved" 0 2000 60 "bogus_context"
  [ "$status" -eq 0 ]  # fail-open, matching every other validation in this function
  run yq '.gates.gate_invalid_ctx.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]  # the bogus call never wrote anything
}

@test "a non-sequential sample under a changed command_template NEVER destroys existing sequential history (Codex regression)" {
  gate_baseline_update "gate_hostile_reset" "tpl-v1" "resolved" 0 1000 60 "sequential"
  gate_baseline_update "gate_hostile_reset" "tpl-v1" "resolved" 0 2000 60 "sequential"
  run yq '.gates.gate_hostile_reset.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]

  # A parallel sample arrives claiming a DIFFERENT command_template — must
  # be refused, never silently wiping the real sequential history/policy
  # state (the original bug: it was treated exactly like a brand-new gate).
  run gate_baseline_update "gate_hostile_reset" "tpl-v2-DIFFERENT" "resolved" 0 500 60 "parallel"
  [ "$status" -eq 0 ]  # fail-open (warn + skip), matching this function's convention

  run yq '.gates.gate_hostile_reset.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2" ]
  run yq '.gates.gate_hostile_reset.max_ms' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "2000" ]
  run yq '.gates.gate_hostile_reset.command_fingerprint' "$AID_GATE_BASELINE_FILE"
  [[ "$output" != "null" ]]
  # A genuine sequential reset (same call, sequential context) still works.
  gate_baseline_update "gate_hostile_reset" "tpl-v2-DIFFERENT" "resolved" 0 500 60 "sequential"
  run yq '.gates.gate_hostile_reset.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
}

@test "the CLI 'update' subcommand forwards the 8th concurrency_context arg (Codex regression)" {
  bash "$LIB" update "gate_cli_ctx" "tpl" "resolved" 0 1000 60 "parallel"
  run yq '.gates.gate_cli_ctx.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "0" ]
  run yq '.gates.gate_cli_ctx.percentiles_by_context.parallel.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]
}

@test "a fingerprint reset clears recent_samples_by_context/percentiles_by_context too" {
  gate_baseline_update "gate_reset_ctx" "tpl-v1" "resolved" 0 1000 60 "sequential"
  gate_baseline_update "gate_reset_ctx" "tpl-v1" "resolved" 0 2000 60 "parallel"
  run yq '.gates.gate_reset_ctx.percentiles_by_context.parallel.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "1" ]

  gate_baseline_update "gate_reset_ctx" "tpl-v2-EDITED" "resolved" 0 3000 60 "sequential"

  run yq '.gates.gate_reset_ctx.percentiles_by_context' "$AID_GATE_BASELINE_FILE"
  [ "$output" = "{}" ]
}
