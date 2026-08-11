#!/usr/bin/env bats
# aid-tier: t2
# test-selector-snapshot-readonly.bats — P066 Step 17.

load test-helpers.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  REPO_ROOT="$(cd "$AID_PLUGIN_PATH/../.." && pwd)"
  SNAPSHOT_SCRIPT="$AID_PLUGIN_PATH/scripts/aid-test-catalog-selector-snapshot.sh"
  SELECTOR_SCRIPT="$AID_PLUGIN_PATH/scripts/aid-select-tests.sh"
}

@test "aid-select-tests.sh bytes are provably unchanged after the snapshot script runs" {
  local before_hash
  before_hash="$(sha256sum "$SELECTOR_SCRIPT" | cut -d' ' -f1)"

  run "$SNAPSHOT_SCRIPT" --project-root "$REPO_ROOT"
  [ "$status" -eq 0 ]

  local after_hash
  after_hash="$(sha256sum "$SELECTOR_SCRIPT" | cut -d' ' -f1)"
  [ "$before_hash" = "$after_hash" ]
}

@test "the 5 known selector gap paths appear as recommendation:fix findings sourced from the real function" {
  run "$SNAPSHOT_SCRIPT" --project-root "$REPO_ROOT"
  [ "$status" -eq 0 ]

  local gap_ids
  gap_ids="$(echo "$output" | jq -r '.findings[].run_unit_id')"

  [[ "$gap_ids" == *"selector-gap:plugins/aid-orchestrator/scripts/aid-plan-fsm.sh"* ]]
  [[ "$gap_ids" == *"selector-gap:plugins/aid-orchestrator/scripts/lib/aid-queue-write.sh"* ]]
  [[ "$gap_ids" == *"selector-gap:plugins/aid-orchestrator/scripts/lib/aid-gate-profile.sh"* ]]
  [[ "$gap_ids" == *"selector-gap:plugins/aid-orchestrator/scripts/aid-queue-add.sh"* ]]
  [[ "$gap_ids" == *"selector-gap:plugins/aid-orchestrator/defaults/enforcement-registry.yaml"* ]]

  echo "$output" | jq -e '[.findings[] | select(.recommendation != "fix")] | length == 0' >/dev/null
  echo "$output" | jq -e '[.findings[] | select(.category != "selector-gap")] | length == 0' >/dev/null
}

@test "every gap finding has a real, checkable falsification_check (never empty)" {
  run "$SNAPSHOT_SCRIPT" --project-root "$REPO_ROOT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.findings[] | select((.falsification_check | length) == 0)] | length == 0' >/dev/null
}

@test "falsification_check references the real path, never the 'selector-snapshot:'-prefixed evidence_ref (Codex review: a synthetic path can never resolve, even after the real gap is fixed)" {
  run "$SNAPSHOT_SCRIPT" --project-root "$REPO_ROOT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    [.findings[] | select(.falsification_check | contains("selector-snapshot:"))] | length == 0
  ' >/dev/null
  echo "$output" | jq -e '
    .findings[0] as $f | $f.falsification_check | contains($f.run_unit_id | sub("^selector-gap:"; ""))
  ' >/dev/null
}

@test "reconstructed source_pattern_mappings[] reflects the real Initial-mapping case arms, every row status:proposed" {
  run "$SNAPSHOT_SCRIPT" --project-root "$REPO_ROOT"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '[.source_pattern_mappings[] | select(.status != "proposed")] | length == 0' >/dev/null

  local patterns
  patterns="$(echo "$output" | jq -r '.source_pattern_mappings[].path_pattern')"
  [[ "$patterns" == *"plugins/aid-orchestrator/scripts/aid-run-gates.sh"* ]]
  [[ "$patterns" == *"plugins/aid-orchestrator/scripts/aid-fsm.sh"* ]]
  [[ "$patterns" == *"plugins/aid-orchestrator/lib/ui-fidelity/"* ]]
}

@test "a nonexistent --project-root fails loudly, never silently defaults" {
  run "$SNAPSHOT_SCRIPT" --project-root "/no/such/dir"
  [ "$status" -ne 0 ]
}

@test "the output is deterministic and reproducible across repeated runs (ignoring generated_at)" {
  run "$SNAPSHOT_SCRIPT" --project-root "$REPO_ROOT"
  local first
  first="$(echo "$output" | jq -c 'del(.generated_at)')"
  run "$SNAPSHOT_SCRIPT" --project-root "$REPO_ROOT"
  local second
  second="$(echo "$output" | jq -c 'del(.generated_at)')"
  [ "$first" = "$second" ]
}
