#!/usr/bin/env bats
# test-aid-test-scheduler.bats — P069 Step 5.
#
# Proves aid-test-scheduler.sh's effective-status resolution, batching, and
# process-lifecycle contract:
#   - mode=sequential -> every batch size 1 regardless of computed status
#   - an all-unknown catalog (no overlay) -> N sequential size-1 batches
#   - a mixed safe/constrained/exclusive set -> expected batch shape
#   - a resource-lock conflict forces separate batches
#   - a unit lacking membership_verified is rejected before batching
#   - a unit with a stale membership_binding fingerprint is rejected likewise
#   - E2E: a real unknown unit becomes schedulable after promotion + approval
#   - a proposed-but-unapproved overlay entry is never authoritative
#   - a stale approved overlay entry falls back to the catalog's own value
#   - TERM mid-batch -> every outstanding unit reaches a terminal receipt via
#     real cancel, zero orphaned process groups
#   - two dispatches of the same run-id produce distinct job-ids (attempt1
#     vs attempt2), never colliding or overwriting a prior receipt

load test-helpers.bash

setup() {
  export TZ=UTC
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCRIPT="$AID_PLUGIN_PATH/scripts/aid-test-scheduler.sh"
  APPROVE="$AID_PLUGIN_PATH/scripts/aid-scheduler-overlay-approve.sh"
  setup_test_evidence_dir
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
}

teardown() {
  teardown_test_evidence_dir
}

# _catalog_with <status_a> <status_b> [exclusive_resources_a_json] [exclusive_resources_b_json]
_write_catalog() {
  local status_a="$1" status_b="$2" excl_a="${3:-[]}" excl_b="${4:-[]}"
  jq -n --arg sa "$status_a" --arg sb "$status_b" --argjson ea "$excl_a" --argjson eb "$excl_b" '
  {
    schema_version: "1.0.0", generated_at: "2026-08-02T00:00:00Z", status: "approved",
    run_units: [
      {run_unit_id:"bats:a", runner:"bats", source_paths:["a.bats"], production_surfaces:["a.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv",argv:["bash","-c","echo A; exit 0"]}, runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       parallel:{status:$sa, exclusive_resources:$ea, max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]},
      {run_unit_id:"bats:b", runner:"bats", source_paths:["b.bats"], production_surfaces:["b.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv",argv:["bash","-c","echo B; exit 0"]}, runtime:{fingerprint:"sha256:bbbbbbbbbbbb"},
       parallel:{status:$sb, exclusive_resources:$eb, max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
}

_write_units() {
  local shell_a="${1:-echo A; exit 0}" deadline_a="${2:-10}"
  jq -nc --arg sa "$shell_a" --argjson da "$deadline_a" '[
    {unit_id:"bats:a", command:{type:"shell",shell:$sa}, deadline_seconds:$da, resource_locks:[], parallel_eligible:false,
     membership_verified:true, dedup:false,
     membership_binding:{catalog_fingerprint:"sha256:aaaaaaaaaaaa", verified_at:"2026-08-02T00:00:00Z", verifier_run_id:"v1"}},
    {unit_id:"bats:b", command:{type:"argv",argv:["bash","-c","echo B; exit 0"]}, deadline_seconds:10, resource_locks:[], parallel_eligible:false,
     membership_verified:true, dedup:false,
     membership_binding:{catalog_fingerprint:"sha256:bbbbbbbbbbbb", verified_at:"2026-08-02T00:00:00Z", verifier_run_id:"v1"}}
  ]' > "$TEST_PROJECT_ROOT/units.json"
}

@test "mode=sequential produces size-1 batches even when catalog status is safe/safe" {
  _write_catalog "safe" "safe"
  _write_units
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r1" --units-json "$TEST_PROJECT_ROOT/units.json" --mode sequential
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.units[].co_scheduled_with] == [[],[]]'
}

@test "an all-unknown catalog (no overlay) produces N sequential-shaped size-1 batches" {
  _write_catalog "unknown" "unknown"
  _write_units
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r2" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.units[].co_scheduled_with] == [[],[]]'
}

@test "two safe units (mode!=sequential) are batched together, co_scheduled_with populated" {
  _write_catalog "safe" "safe"
  _write_units
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r3" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel --max-workers 4
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.units[] | select(.unit_id=="bats:a") | .co_scheduled_with) == ["bats:b"]'
}

@test "a resource-lock conflict between two constrained units forces separate batches" {
  _write_catalog "constrained" "constrained" '["db"]' '["db"]'
  _write_units
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r4" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel --max-workers 4
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.units[].co_scheduled_with] == [[],[]]'
}

@test "two constrained units with DIFFERENT locks ARE batched together" {
  _write_catalog "constrained" "constrained" '["db"]' '["redis"]'
  _write_units
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r5" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel --max-workers 4
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.units[] | select(.unit_id=="bats:a") | .co_scheduled_with) == ["bats:b"]'
}

@test "a unit lacking membership_verified is rejected before batching" {
  _write_catalog "unknown" "unknown"
  jq -c '.[0].membership_verified = false' "$TEST_PROJECT_ROOT/units.json" > "$TEST_PROJECT_ROOT/units_bad.json" 2>/dev/null || _write_units
  _write_units
  jq '.[0].membership_verified = false' "$TEST_PROJECT_ROOT/units.json" > "$TEST_PROJECT_ROOT/units_bad.json"
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r6" --units-json "$TEST_PROJECT_ROOT/units_bad.json" --mode sequential
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats:a"* ]]
}

@test "a unit with a stale membership_binding.catalog_fingerprint is rejected before batching" {
  _write_catalog "unknown" "unknown"
  _write_units
  jq '.[0].membership_binding.catalog_fingerprint = "sha256:stalestalestale"' "$TEST_PROJECT_ROOT/units.json" > "$TEST_PROJECT_ROOT/units_stale.json"
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r7" --units-json "$TEST_PROJECT_ROOT/units_stale.json" --mode sequential
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats:a"* ]]
}

@test "E2E: a real unknown unit becomes schedulable in a multi-unit batch after promotion + approval" {
  _write_catalog "unknown" "unknown"
  _write_units

  # Before promotion: both isolated (unknown never batches).
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r8a" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel
  echo "$output" | jq -e '[.units[].co_scheduled_with] == [[],[]]'

  cat > "$TEST_PROJECT_ROOT/overlay.proposed.json" <<'JSON'
{"schema_version":"1.0.0","status":"proposed","overlay":[
  {"run_unit_id":"bats:a","promoted_status":"safe","catalog_fingerprint_at_promotion":"sha256:aaaaaaaaaaaa","promoted_at":"2026-08-02T00:00:00Z","evidence_run_id":"iso-1"},
  {"run_unit_id":"bats:b","promoted_status":"safe","catalog_fingerprint_at_promotion":"sha256:bbbbbbbbbbbb","promoted_at":"2026-08-02T00:00:00Z","evidence_run_id":"iso-1"}
]}
JSON
  local display_out hash
  display_out="$(bash "$APPROVE" --proposed "$TEST_PROJECT_ROOT/overlay.proposed.json" --project-root "$TEST_PROJECT_ROOT")"
  hash="$(echo "$display_out" | grep -oE 'sha256:[a-f0-9]+' | tail -1)"
  run bash "$APPROVE" --proposed "$TEST_PROJECT_ROOT/overlay.proposed.json" --project-root "$TEST_PROJECT_ROOT" --confirm-overlay "$hash"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r8b" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel --max-workers 4
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.units[] | select(.unit_id=="bats:a") | .co_scheduled_with) == ["bats:b"]'
}

@test "a proposed-but-unapproved overlay entry is never read as authoritative" {
  _write_catalog "unknown" "unknown"
  _write_units
  cat > "$TEST_PROJECT_ROOT/.aid-o/work/proposed_only.json" <<'JSON'
{"schema_version":"1.0.0","status":"proposed","overlay":[
  {"run_unit_id":"bats:a","promoted_status":"safe","catalog_fingerprint_at_promotion":"sha256:aaaaaaaaaaaa","promoted_at":"2026-08-02T00:00:00Z","evidence_run_id":"iso-1"}
]}
JSON
  # Never approved — simulate by writing the proposed file at the APPROVED
  # canonical path but with status:"proposed" left untouched (the scheduler
  # must never treat a document whose OWN status is "proposed" as
  # authoritative even if it happens to be at that path).
  cp "$TEST_PROJECT_ROOT/.aid-o/work/proposed_only.json" "$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml"
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r9" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.units[].co_scheduled_with] == [[],[]]'
}

@test "a stale (fingerprint-mismatched) approved overlay entry falls back to the catalog's own value" {
  _write_catalog "unknown" "unknown"
  _write_units
  jq -n '{schema_version:"1.0.0", status:"approved", overlay:[
    {run_unit_id:"bats:a", promoted_status:"safe", catalog_fingerprint_at_promotion:"sha256:STALESTALEST", promoted_at:"2026-08-02T00:00:00Z", evidence_run_id:"iso-1"}
  ]}' | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml"
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r10" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.units[].co_scheduled_with] == [[],[]]'
}

@test "TERM mid-batch cancels every outstanding unit to a terminal receipt, zero orphaned process groups" {
  _write_catalog "unknown" "unknown"
  _write_units "sleep 30 & echo \$! > $TEST_PROJECT_ROOT/child.pid; wait" 60
  bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r11" --units-json "$TEST_PROJECT_ROOT/units.json" --mode sequential &
  local sched_pid=$!
  # Wait for the job directory + child pid file to appear before signalling.
  for ((i = 0; i < 50; i++)); do
    [[ -f "$TEST_PROJECT_ROOT/child.pid" ]] && break
    sleep 0.1
  done
  kill -TERM "$sched_pid"
  local rc=0
  wait "$sched_pid" || rc=$?
  [ "$rc" -eq 143 ]

  local jobs_dir="$TEST_PROJECT_ROOT/.aid-o/work/test-audits/r11/scheduler-jobs"
  local d
  for d in "$jobs_dir"/*/; do
    [[ -f "$d/job.json" ]] || continue
    run jq -r '.state' "$d/result.json"
    [ "$output" = "cancelled" ]
  done

  if [[ -f "$TEST_PROJECT_ROOT/child.pid" ]]; then
    local child_pid; child_pid="$(cat "$TEST_PROJECT_ROOT/child.pid")"
    run kill -0 "$child_pid"
    [ "$status" -ne 0 ]
  fi
}

@test "two dispatches of the same run-id produce distinct job-ids and never overwrite the first attempt's receipt" {
  _write_catalog "unknown" "unknown"
  _write_units
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r12" --units-json "$TEST_PROJECT_ROOT/units.json" --mode sequential --attempt 1
  [ "$status" -eq 0 ]
  local job_id_1; job_id_1="$(echo "$output" | jq -r '.units[] | select(.unit_id=="bats:a") | .job_id')"

  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r12" --units-json "$TEST_PROJECT_ROOT/units.json" --mode sequential --attempt 2
  [ "$status" -eq 0 ]
  local job_id_2; job_id_2="$(echo "$output" | jq -r '.units[] | select(.unit_id=="bats:a") | .job_id')"

  [ "$job_id_1" != "$job_id_2" ]
  local jobs_dir="$TEST_PROJECT_ROOT/.aid-o/work/test-audits/r12/scheduler-jobs"
  [ -f "$jobs_dir/$job_id_1/result.json" ]
  [ -f "$jobs_dir/$job_id_2/result.json" ]
}

@test "an unvalidated --max-workers is rejected, not evaluated as a bash arithmetic expression (Codex regression)" {
  _write_catalog "safe" "safe"
  _write_units
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r14" --units-json "$TEST_PROJECT_ROOT/units.json" --mode observe_parallel --max-workers 'x[$(touch '"$TEST_PROJECT_ROOT"'/pwned)]'
  [ "$status" -ne 0 ]
  [ ! -f "$TEST_PROJECT_ROOT/pwned" ]
}

@test "a --run-id containing '..' is rejected before it is ever used as a path (Codex regression: path traversal)" {
  _write_catalog "unknown" "unknown"
  _write_units
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "../../etc" --units-json "$TEST_PROJECT_ROOT/units.json" --mode sequential
  [ "$status" -ne 0 ]
  [ ! -d "$TEST_PROJECT_ROOT/.aid-o/work/test-audits/../../etc" ]
}

@test "a run_unit that fails (terminal_fail) does not abort the scheduler or orphan its batch peer (Codex regression)" {
  _write_catalog "safe" "safe"
  jq -nc '[
    {unit_id:"bats:a", command:{type:"shell",shell:"exit 1"}, deadline_seconds:10, resource_locks:[], parallel_eligible:false,
     membership_verified:true, dedup:false,
     membership_binding:{catalog_fingerprint:"sha256:aaaaaaaaaaaa", verified_at:"2026-08-02T00:00:00Z", verifier_run_id:"v1"}},
    {unit_id:"bats:b", command:{type:"argv",argv:["bash","-c","echo B; exit 0"]}, deadline_seconds:10, resource_locks:[], parallel_eligible:false,
     membership_verified:true, dedup:false,
     membership_binding:{catalog_fingerprint:"sha256:bbbbbbbbbbbb", verified_at:"2026-08-02T00:00:00Z", verifier_run_id:"v1"}}
  ]' > "$TEST_PROJECT_ROOT/units_fail.json"
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r15" --units-json "$TEST_PROJECT_ROOT/units_fail.json" --mode observe_parallel --max-workers 4
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.units | length) == 2 and (.units[] | select(.unit_id=="bats:a") | .state) == "terminal_fail" and (.units[] | select(.unit_id=="bats:b") | .state) == "terminal_pass"'
}

@test "two truly concurrent dispatches for the SAME run-id never both proceed (Codex regression: TOCTOU race)" {
  _write_catalog "unknown" "unknown"
  _write_units "sleep 2; exit 0" 10
  bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r16" --units-json "$TEST_PROJECT_ROOT/units.json" --mode sequential > "$TEST_PROJECT_ROOT/out1.json" &
  local pid1=$!
  bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r16" --units-json "$TEST_PROJECT_ROOT/units.json" --mode sequential > "$TEST_PROJECT_ROOT/out2.json" &
  local pid2=$!
  local rc1=0 rc2=0
  wait "$pid1" || rc1=$?
  wait "$pid2" || rc2=$?
  # Exactly one of the two must have succeeded; the other must have been
  # refused (never silently double-dispatched the same run-id).
  [[ ( "$rc1" -eq 0 && "$rc2" -ne 0 ) || ( "$rc1" -ne 0 && "$rc2" -eq 0 ) ]]
}

@test "a dispatch is refused while a prior batch's jobs directory still has non-terminal entries" {
  _write_catalog "unknown" "unknown"
  _write_units
  local jobs_dir="$TEST_PROJECT_ROOT/.aid-o/work/test-audits/r13/scheduler-jobs"
  mkdir -p "$jobs_dir/stuck-job"
  jq -n '{schema:"aid-job/1", id:"stuck-job", state:"running"}' > "$jobs_dir/stuck-job/job.json"
  run bash "$SCRIPT" dispatch --project-root "$TEST_PROJECT_ROOT" --run-id "r13" --units-json "$TEST_PROJECT_ROOT/units.json" --mode sequential
  [ "$status" -ne 0 ]
  [[ "$output" == *"stuck-job"* ]]
}
