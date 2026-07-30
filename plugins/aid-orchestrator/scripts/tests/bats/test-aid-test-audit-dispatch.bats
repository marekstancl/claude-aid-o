#!/usr/bin/env bats
# test-aid-test-audit-dispatch.bats — P066 Step 11.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  DISPATCH="$AID_PLUGIN_PATH/scripts/aid-test-audit-dispatch.sh"
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-state.sh"

  CATALOG="$TEST_TMPDIR/catalog.json"
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-07-30T00:00:00Z", status:"proposed",
    run_units: [
      {run_unit_id:"bats:a/1", runner:"bats", source_paths:["a/1.bats"]},
      {run_unit_id:"bats:a/2", runner:"bats", source_paths:["a/2.bats"]},
      {run_unit_id:"bats:b/1", runner:"bats", source_paths:["b/1.bats"]},
      {run_unit_id:"npm:test", runner:"package-script", source_paths:["package.json"]},
      {run_unit_id:"gate:lint", runner:"declared-command", source_paths:["execution.yaml"]}
    ],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' > "$CATALOG"

  OUTPUT_DIR="$TEST_TMPDIR/audit-out"
}

teardown() {
  teardown_test_evidence_dir
}

@test "shard partitioning is deterministic across two runs" {
  # rendered_prompt_path is intentionally absolute and under --output-dir, so
  # comparison strips it — determinism here means the same shard/focus/
  # run_unit_id/batch assignment, not identical output_dir-derived paths.
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode measure --max-agents 2 --audit-id a1
  [ "$status" -eq 0 ]
  local first
  first="$(jq 'del(.entries[].rendered_prompt_path, .entries[].template)' <<<"$output")"
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$TEST_TMPDIR/out2" --mode measure --max-agents 2 --audit-id a1
  [ "$status" -eq 0 ]
  local second
  second="$(jq 'del(.entries[].rendered_prompt_path, .entries[].template)' <<<"$output")"
  [ "$first" = "$second" ]
}

@test "shard partitioning never assigns one run_unit_id to two shards (preflight-enforced)" {
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode measure --max-agents 2 --audit-id a1
  [ "$status" -eq 0 ]
  local all_ids unique_ids
  all_ids="$(echo "$output" | jq '[.entries[] | select(.focus == "shard_portfolio") | .run_unit_ids[]] | length')"
  unique_ids="$(echo "$output" | jq '[.entries[] | select(.focus == "shard_portfolio") | .run_unit_ids[]] | unique | length')"
  [ "$all_ids" = "$unique_ids" ]
  [ "$all_ids" -eq 5 ]
}

@test "an injected shard overlap is caught by the preflight check (direct primitive test)" {
  # aid-test-audit-dispatch.sh is a `set -euo pipefail` executable script,
  # not a sourceable lib (sourcing it would risk killing this test's own
  # shell on its own arg-parsing exit) — this exercises the exact overlap-
  # detection jq expression the script itself runs, against a contrived
  # overlapping shard set, the same idiom Step 4's collision test used.
  local overlapping_shards='[{"shard_id":"shard-0","run_unit_ids":["bats:a/1","bats:a/2"]},{"shard_id":"shard-1","run_unit_ids":["bats:a/2","bats:b/1"]}]'
  run jq -r '[.[].run_unit_ids[]] | group_by(.) | map(select(length > 1) | .[0]) | .[]' <<<"$overlapping_shards"
  [ "$status" -eq 0 ]
  [ "$output" = "bats:a/2" ]
}

@test "--mode static produces only Waves 1 and 3, never Wave 2 (skipped, not merely empty)" {
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode static --max-agents 10 --audit-id a2
  [ "$status" -eq 0 ]
  local waves
  waves="$(echo "$output" | jq -c '[.entries[].wave] | unique')"
  [ "$waves" = "[1,3]" ]
}

@test "--mode measure produces Waves 1, 2 (all 3 specialists), and 3" {
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode measure --max-agents 10 --audit-id a3
  [ "$status" -eq 0 ]
  local wave2_focuses
  wave2_focuses="$(echo "$output" | jq -c '[.entries[] | select(.wave == 2) | .focus] | sort')"
  [ "$wave2_focuses" = '["flake_isolation","parallel_safety","performance_cost"]' ]
}

@test "shard count never exceeds --max-agents, even with more natural groups than the ceiling" {
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode static --max-agents 1 --audit-id a4
  [ "$status" -eq 0 ]
  local shard_count
  shard_count="$(echo "$output" | jq '[.entries[] | select(.focus == "shard_portfolio")] | length')"
  [ "$shard_count" -eq 1 ]
}

@test "max-agents bound reads Step 5's config default when --max-agents is not given" {
  # No .aid-o/config/test-audit.yaml in this fixture project -> hardcoded
  # default (max_read_only_audit_agents: 4) applies.
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode static --project-root "$TEST_PROJECT_ROOT" --audit-id a5
  [ "$status" -eq 0 ]
  local shard_count
  shard_count="$(echo "$output" | jq '[.entries[] | select(.focus == "shard_portfolio")] | length')"
  [ "$shard_count" -le 4 ]
}

@test "max-agents bound honors a project's real test-audit.yaml override (from-file path)" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/test-audit.yaml" <<'YAML'
budget_minutes_default: 30
max_read_only_audit_agents: 1
allowed_runners: [bats]
YAML
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode static --project-root "$TEST_PROJECT_ROOT" --audit-id a6
  [ "$status" -eq 0 ]
  local shard_count
  shard_count="$(echo "$output" | jq '[.entries[] | select(.focus == "shard_portfolio")] | length')"
  [ "$shard_count" -eq 1 ]
}

@test "Wave 2's 3 specialists are batched so no more than max_concurrent_agents run at once" {
  # Regression: an earlier version always emitted all 3 Wave 2 specialists
  # with no batching info, so a max-agents:1 ceiling was silently violated
  # (3 simultaneous agents despite a ceiling of 1) — Codex review.
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode measure --max-agents 1 --audit-id a7
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.max_concurrent_agents == 1' >/dev/null
  local wave2_batches
  wave2_batches="$(echo "$output" | jq -c '[.entries[] | select(.wave == 2) | .batch] | sort')"
  [ "$wave2_batches" = "[0,1,2]" ]
}

@test "every manifest entry has a real rendered_prompt_path with no leftover {{ placeholder" {
  # Regression: an earlier version pointed entries at an unrendered template
  # with unresolved {{...}} variables and no way to construct them — Codex
  # review found a controller following the manifest could not actually
  # dispatch a usable prompt.
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode measure --max-agents 4 --audit-id a8
  [ "$status" -eq 0 ]
  local paths
  paths="$(echo "$output" | jq -r '.entries[].rendered_prompt_path')"
  local p
  while IFS= read -r p; do
    [ -f "$p" ]
    ! grep -q '{{' "$p"
  done <<<"$paths"
}

@test "Wave 3's rendered prompt references all Wave 1+2 artifact paths" {
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode measure --max-agents 4 --audit-id a9
  [ "$status" -eq 0 ]
  local wave3_prompt
  wave3_prompt="$(echo "$output" | jq -r '.entries[] | select(.focus == "adversarial_review") | .rendered_prompt_path')"
  grep -q "1-shard_portfolio-shard-0" "$wave3_prompt"
  grep -q "2-performance_cost" "$wave3_prompt"
}

@test "allowed_runners filters which run_units are ever dispatched (config actually enforced, not just loaded)" {
  # Regression: an earlier version loaded allowed_runners from config but
  # never applied it — a project override was silently ineffective (Codex
  # review).
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/test-audit.yaml" <<'YAML'
budget_minutes_default: 30
max_read_only_audit_agents: 4
allowed_runners: [bats]
YAML
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode static --project-root "$TEST_PROJECT_ROOT" --audit-id a10
  [ "$status" -eq 0 ]
  local dispatched_ids
  dispatched_ids="$(echo "$output" | jq -r '[.entries[] | select(.focus == "shard_portfolio") | .run_unit_ids[]] | join(",")')"
  [[ "$dispatched_ids" == *"bats:"* ]]
  [[ "$dispatched_ids" != *"npm:test"* ]]
  [[ "$dispatched_ids" != *"gate:lint"* ]]
}

@test "the default (unconfigured) allowed_runners includes the real adapter labels, not framework names that would exclude every non-Bats project" {
  run "$DISPATCH" --catalog "$CATALOG" --output-dir "$OUTPUT_DIR" --mode static --project-root "$TEST_PROJECT_ROOT" --audit-id a11
  [ "$status" -eq 0 ]
  local dispatched_ids
  dispatched_ids="$(echo "$output" | jq -r '[.entries[] | select(.focus == "shard_portfolio") | .run_unit_ids[]] | join(",")')"
  [[ "$dispatched_ids" == *"npm:test"* ]]
  [[ "$dispatched_ids" == *"gate:lint"* ]]
}

@test "max-agents ceiling is independent of dispatch.max_parallel / dispatch.worktrees.max_parallel" {
  ! grep -q "dispatch\.max_parallel\|dispatch\.worktrees\.max_parallel" "$DISPATCH"
}

@test "no dispatch call in this script ever invokes aid-emit-dispatch.sh (grep-verified, comments excluded)" {
  # The script's own header PROSE explains why aid-emit-dispatch.sh is
  # deliberately not used (so a bare substring grep would false-positive on
  # that explanation) — this checks for an actual invocation instead: a
  # non-comment line naming it as a command.
  ! grep -vE '^\s*#' "$DISPATCH" | grep -q "aid-emit-dispatch"
}

@test "a wave artifact failing Step 1's schema halts advance_wave, naming the exact focus/shard" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  local bad_artifact="$TEST_TMPDIR/1-shard_portfolio-shard-0.json"
  jq -n '{schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:null, findings:[], produced_at:"2026-07-30T00:00:00Z", producer_agent_dispatch_id:"d1"}' > "$bad_artifact"
  run audit_state_advance_wave "$OUTPUT_DIR" "sharding" "$bad_artifact"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$bad_artifact"* ]]
  jq -e '.status == "discovering"' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "a schema-valid artifact from the WRONG wave/focus is rejected, not silently accepted" {
  # Regression: an earlier version validated only the artifact's schema, not
  # whether its focus actually matches the phase being advanced — a valid
  # Wave 2 performance_cost artifact could be passed while advancing the
  # Wave 1 "sharding" phase, silently recording the wrong wave as complete
  # (Codex review).
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  local wrong_wave_artifact="$TEST_TMPDIR/2-performance_cost.json"
  jq -n '{schema_version:"1.0.0", focus:"performance_cost", wave:2, shard_id:null, findings:[], produced_at:"2026-07-30T00:00:00Z", producer_agent_dispatch_id:"d1"}' > "$wrong_wave_artifact"
  run audit_state_advance_wave "$OUTPUT_DIR" "sharding" "$wrong_wave_artifact"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expects one of"* ]]
  jq -e '.status == "discovering"' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "a missing wave artifact halts advance_wave, naming the exact path" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  local missing_artifact="$TEST_TMPDIR/does-not-exist.json"
  run audit_state_advance_wave "$OUTPUT_DIR" "sharding" "$missing_artifact"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$missing_artifact"* ]]
}

@test "advance_wave accepts a valid wave artifact and proceeds normally" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  local good_artifact="$TEST_TMPDIR/1-shard_portfolio-shard-0.json"
  jq -n '{schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0", findings:[], produced_at:"2026-07-30T00:00:00Z", producer_agent_dispatch_id:"d1"}' > "$good_artifact"
  run audit_state_advance_wave "$OUTPUT_DIR" "sharding" "$good_artifact"
  [ "$status" -eq 0 ]
  jq -e '.status == "sharding" and .waves_completed == 1' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "resume-after-interrupt during a real multi-wave dispatch: no duplicate specialist invocation" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null
  audit_state_mark_interrupted "$OUTPUT_DIR" >/dev/null

  run audit_state_resume "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  # Resumed exactly where it was interrupted (dispatching, waves_completed=2)
  # — never re-processes the already-completed sharding/first-dispatching
  # wave, i.e. no duplicate specialist invocation.
  jq -e '.status == "dispatching" and .waves_completed == 2' "$OUTPUT_DIR/audit-state.json" >/dev/null
}
