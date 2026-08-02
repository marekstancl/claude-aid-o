#!/usr/bin/env bats
# test-aid-test-divergence-campaign.bats — P069 Step 7.
#
# Proves aid-test-divergence-campaign.sh:
#   - collecting the required qualifying passes within budget exits 0
#   - a fixture that never qualifies exhausts max_attempts, writes
#     campaign_status: "evidence_incomplete" with budget_exhausted_reason:
#     "max_attempts", never looping past the configured limit
#   - a fixture that would need more wall-clock than allowed exhausts
#     max_wall_clock_seconds instead, with the matching reason
#   - both budget-exhaustion cases exit promptly

load test-helpers.bash

setup() {
  export TZ=UTC
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CAMPAIGN="$AID_PLUGIN_PATH/scripts/aid-test-divergence-campaign.sh"
  setup_test_evidence_dir
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"

  cat > "$TEST_PROJECT_ROOT/.gitignore" <<'EOF'
.aid-o/
**/.aid-o/
EOF
  git add .gitignore
  git commit -q -m "add gitignore"
}

teardown() {
  teardown_test_evidence_dir
}

_write_catalog() {
  local shell_a="${1:-exit 0}"
  jq -n --arg sh "$shell_a" '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved",
    run_units: [
      {run_unit_id:"safe1", runner:"shell", source_paths:["s1"], production_surfaces:["s1"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:$sh}, runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       parallel:{status:"safe", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  git add -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  git commit -q -m "add catalog"
}

@test "a campaign that collects the required qualifying passes within budget exits 0" {
  _write_catalog
  run bash "$CAMPAIGN" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1" --mode-tested observe_parallel --required 2 --max-attempts 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"collected 2 qualifying"* ]]
}

@test "a campaign whose fixture always diverges exhausts max_attempts, writes evidence_incomplete" {
  # Always-diverging: the sequential dispatch creates the marker inside the
  # shared clone, so the scheduled dispatch (same clone, runs second)
  # always observes it already present and fails — a real, deterministic
  # divergence every single attempt.
  _write_catalog '[ ! -f marker.txt ] && (touch marker.txt; exit 0) || exit 1'
  run bash "$CAMPAIGN" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1" --mode-tested observe_parallel --required 2 --max-attempts 3 --max-wall-clock-seconds 3600
  [ "$status" -eq 2 ]
  [[ "$output" == *"evidence_incomplete"* ]]
  [[ "$output" == *"max_attempts"* ]]

  local evdir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/scheduler-divergence"
  local campaign_file; campaign_file="$(ls "$evdir"/campaign-*.json | head -1)"
  [ -f "$campaign_file" ]
  run jq -r '.campaign_status' "$campaign_file"
  [ "$output" = "evidence_incomplete" ]
  run jq -r '.attempts_made' "$campaign_file"
  [ "$output" = "3" ]
  run jq -r '.budget_exhausted_reason' "$campaign_file"
  [ "$output" = "max_attempts" ]
}

@test "a campaign exhausts max_wall_clock_seconds instead of max_attempts when time runs out first, exits promptly" {
  _write_catalog '[ ! -f marker.txt ] && (touch marker.txt; exit 0) || exit 1'
  local start; start=$(date +%s)
  run bash "$CAMPAIGN" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1" --mode-tested observe_parallel --required 2 --max-attempts 1000 --max-wall-clock-seconds 1
  local end; end=$(date +%s)
  [ "$status" -eq 2 ]
  [[ "$output" == *"max_wall_clock"* ]]
  # Promptly: well under the max_attempts budget's own natural runtime.
  [ "$(( end - start ))" -lt 60 ]

  local evdir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/scheduler-divergence"
  local campaign_file; campaign_file="$(ls "$evdir"/campaign-*.json | head -1)"
  run jq -r '.budget_exhausted_reason' "$campaign_file"
  [ "$output" = "max_wall_clock" ]
}

@test "a pre-existing qualifying artifact for a DIFFERENT unit set does not satisfy this campaign (Codex regression)" {
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved",
    run_units: [
      {run_unit_id:"safe1", runner:"shell", source_paths:["s1"], production_surfaces:["s1"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:"exit 0"}, runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       parallel:{status:"safe", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]},
      {run_unit_id:"other1", runner:"shell", source_paths:["o1"], production_surfaces:["o1"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:"exit 0"}, runtime:{fingerprint:"sha256:cccccccccccc"},
       parallel:{status:"safe", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  git add -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  git commit -q -m "add catalog"

  # A campaign for "other1" alone collects its own qualifying evidence.
  bash "$CAMPAIGN" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "other1" --mode-tested observe_parallel --required 1 --max-attempts 2 >/dev/null

  # A campaign for "safe1" alone (a DIFFERENT unit set, same commit) must
  # NOT be satisfied by that unrelated "other1" evidence — it needs its own.
  run bash "$CAMPAIGN" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1" --mode-tested observe_parallel --required 1 --max-attempts 2
  [ "$status" -eq 0 ]
  [[ "$output" != *"(0 attempt(s))"* ]]
}

@test "a campaign's evidence artifact is force-tracked" {
  _write_catalog '[ ! -f marker.txt ] && (touch marker.txt; exit 0) || exit 1'
  bash "$CAMPAIGN" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1" --mode-tested observe_parallel --required 2 --max-attempts 2 || true
  local evdir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/scheduler-divergence"
  local campaign_file; campaign_file="$(ls "$evdir"/campaign-*.json | head -1)"
  local rel="${campaign_file#"$TEST_PROJECT_ROOT"/}"
  git -C "$TEST_PROJECT_ROOT" ls-files --error-unmatch "$rel"
}

@test "pre-existing qualifying artifacts from an earlier campaign count toward the target" {
  _write_catalog
  # First campaign collects 1 qualifying run (required=1).
  bash "$CAMPAIGN" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1" --mode-tested observe_parallel --required 1 --max-attempts 2 >/dev/null
  # A second campaign requiring only 1 total should need ZERO new attempts
  # since the prior qualifying artifact already satisfies it.
  run bash "$CAMPAIGN" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1" --mode-tested observe_parallel --required 1 --max-attempts 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"(0 attempt(s))"* ]]
}
