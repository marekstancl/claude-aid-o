#!/usr/bin/env bats
# test-aid-test-schedule-divergence-check.bats — P069 Step 7.
#
# Proves aid-test-schedule-divergence-check.sh:
#   - identical-membership/identical-verdict case passes, writes pass:true
#   - an injected single-unit-verdict difference blocks promotion, naming
#     that unit, and writes pass:false with the diff populated
#   - three consecutive invocations produce three distinct, non-overwriting
#     run_id-keyed files
#   - the written artifact validates against divergence-evidence.schema.json
#   - the artifact is force-tracked (git ls-files --error-unmatch)
#   - two genuinely concurrent invocations produce two distinct,
#     non-colliding files

load test-helpers.bash

setup() {
  export TZ=UTC
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CHECK="$AID_PLUGIN_PATH/scripts/aid-test-schedule-divergence-check.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/divergence-evidence.schema.json"
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
       recommendation:"keep", test_cases:[]},
      {run_unit_id:"safe2", runner:"shell", source_paths:["s2"], production_surfaces:["s2"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"shell", shell:"exit 0"}, runtime:{fingerprint:"sha256:bbbbbbbbbbbb"},
       parallel:{status:"safe", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  git add -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  git commit -q -m "add catalog"
}

@test "identical membership/verdicts passes and writes a schema-valid pass:true artifact" {
  _write_catalog
  run bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel
  [ "$status" -eq 0 ]

  local evdir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/scheduler-divergence"
  local f; f="$(ls "$evdir"/*.json | head -1)"
  run jq -r '.pass' "$f"
  [ "$output" = "true" ]
  run jq -r '.membership_diff | length' "$f"
  [ "$output" = "0" ]
  run jq -r '.verdict_diff | length' "$f"
  [ "$output" = "0" ]
  run jq -r '.worktree_kind' "$f"
  [ "$output" = "disposable_clone" ]

  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1 && {
    run python3 -c "
import sys, json
from jsonschema.validators import Draft202012Validator
schema = json.load(open('$SCHEMA'))
inst = json.load(open('$f'))
sys.exit(1 if list(Draft202012Validator(schema).iter_errors(inst)) else 0)
"
    [ "$status" -eq 0 ]
  }
}

@test "an injected verdict difference blocks promotion, naming the unit, writes pass:false with the diff populated" {
  # A candidate whose result depends on whether a file already exists in
  # the shared clone — the sequential dispatch creates it, so the SAME
  # clone's scheduled dispatch (which runs second) sees a different
  # starting state and fails, a genuine, deterministic divergence.
  _write_catalog '[ ! -f marker.txt ] && (touch marker.txt; exit 0) || exit 1'
  run bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel
  [ "$status" -ne 0 ]
  [[ "$output" == *"safe1"* ]]

  local evdir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/scheduler-divergence"
  local f; f="$(ls "$evdir"/*.json | head -1)"
  run jq -r '.pass' "$f"
  [ "$output" = "false" ]
  run jq -r '.verdict_diff | length' "$f"
  [ "$output" != "0" ]
  run jq -r '.verdict_diff[0].unit_id' "$f"
  [ "$output" = "safe1" ]
}

@test "three consecutive invocations produce three distinct, non-overwriting files" {
  _write_catalog
  bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel >/dev/null
  bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel >/dev/null
  bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel >/dev/null
  local evdir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/scheduler-divergence"
  run bash -c "ls '$evdir'/*.json | wc -l"
  [ "$output" -eq 3 ]
}

@test "the written artifact is force-tracked" {
  _write_catalog
  bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel >/dev/null
  local evdir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/scheduler-divergence"
  local f; f="$(ls "$evdir"/*.json | head -1)"
  local rel="${f#"$TEST_PROJECT_ROOT"/}"
  git -C "$TEST_PROJECT_ROOT" ls-files --error-unmatch "$rel"

  touch "$evdir/other-untracked-file.json"
  git -C "$TEST_PROJECT_ROOT" check-ignore "$evdir/other-untracked-file.json"
}

@test "duplicate --unit-ids are rejected before any clone is created (Codex regression)" {
  _write_catalog
  run bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe1" --mode-tested observe_parallel
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate"* ]]
}

@test "the disposable clone leaves no leftover EMPTY parent temp directory (Codex regression)" {
  # The original bug's exact signature: clone_path was a subdir of a fresh
  # `mktemp -d`, so cleanup removed only the child, leaving an EMPTY parent
  # behind on every single invocation. Filtering for `-empty` isolates
  # exactly that defect from unrelated concurrent activity elsewhere under
  # this shared /tmp (this sandbox runs other bats suites in parallel).
  _write_catalog
  local sentinel; sentinel="$(mktemp)"
  sleep 1.1  # ensure strictly-newer mtime comparison below has margin
  bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel >/dev/null
  run bash -c "find /tmp -maxdepth 1 -user \"\$(id -u)\" -type d -empty -newer '$sentinel' 2>/dev/null"
  [ -z "$output" ]
}

@test "an ARTIFACT_PATH stdout line is always emitted, on both pass and fail" {
  _write_catalog
  run bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel
  [[ "$output" == *"ARTIFACT_PATH="* ]]

  _write_catalog '[ ! -f marker.txt ] && (touch marker.txt; exit 0) || exit 1'
  run bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel
  [[ "$output" == *"ARTIFACT_PATH="* ]]
}

@test "two genuinely concurrent invocations against the same commit produce two distinct, non-colliding files" {
  _write_catalog
  bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel > "$TEST_PROJECT_ROOT/out1.log" 2>&1 &
  local pid1=$!
  bash "$CHECK" run --project-root "$TEST_PROJECT_ROOT" --unit-ids "safe1,safe2" --mode-tested observe_parallel > "$TEST_PROJECT_ROOT/out2.log" 2>&1 &
  local pid2=$!
  wait "$pid1"
  wait "$pid2"

  local evdir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/scheduler-divergence"
  run bash -c "ls '$evdir'/*.json | wc -l"
  [ "$output" -eq 2 ]
  # Distinct run_ids (no collision).
  run bash -c "jq -r '.run_id' '$evdir'/*.json | sort -u | wc -l"
  [ "$output" -eq 2 ]
}
