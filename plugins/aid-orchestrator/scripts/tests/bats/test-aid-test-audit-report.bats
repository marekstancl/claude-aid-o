#!/usr/bin/env bats
# aid-tier: t0
# test-aid-test-audit-report.bats — the ONE fixed-form report page.
#
# The contract is completeness: nine sections, always, whether or not the data
# behind a section exists. A missing section reads as "nothing to see here",
# and four days of fragmented outputs proved how much that lie costs.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  REPORT="$PLUGIN_DIR/scripts/aid-test-audit-report.sh"
  AD="$TEST_TMPDIR/audit"; mkdir -p "$AD/agents"
  PROJ="$TEST_TMPDIR/proj"; mkdir -p "$PROJ/.aid-o/config"
}
teardown() { teardown_test_evidence_dir; }

_sections_present() {   # <file>
  local s
  for s in "1 · Hlavní čísla" "2 · Prověřenost" "3 · Skupiny" "4 · Co žere čas" \
           "5 · Kolik ušetříme čím" "6 · Kvalita" "7 · Rizika" "8 · Spolehlivost" \
           "9 · Akce a plán" "10 · Nedokázáno" "11 · Zdroje"; do
    grep -q "$s" "$1" || { echo "chybí sekce: $s"; return 1; }
  done
}

@test "a populated audit renders all nine sections with its real numbers" {
  printf '{"schema_version":"1.0.0","generated_at":"t","runner_families":["bats"],"entries":[{"run_unit_id":"bats:tests/a","runner":"bats","adapter":"bats","confidence":"medium"},{"run_unit_id":"bats:tests/b","runner":"bats","adapter":"bats","confidence":"medium"}]}' > "$AD/inventory.json"
  printf '%s\n' '{"run_unit_id":"bats:tests/a","state":"terminal_pass","duration_ms":5000}' \
                '{"run_unit_id":"bats:tests/b","state":"timed_out","duration_ms":300000}' > "$AD/measurements.jsonl"
  jq -n '{schema_version:"1.0.0",focus:"shard_portfolio",wave:1,shard_id:"s0",findings:[],
          produced_at:"t",producer_agent_dispatch_id:"d0",
          dispositions:[
            {run_unit_id:"bats:tests/a",disposition:"fix",falsification:{method:"mutation",evidence_ref:"m.json"}},
            {run_unit_id:"bats:tests/b",disposition:"keep",falsification:{method:"unproved"}}]}' > "$AD/agents/1.json"
  jq -n '{schema_version:"aid-test-audit-decision-v1",audit_id:"A1",audit_status:"complete",
          actions:[{action:"fix",targets:["bats:tests/a"],priority:"critical",reason:"r",
                    evidence_refs:["e"],impact:{kind:"unknown",before_ms:null,after_ms:null,assumptions:[]}}],
          unresolved:[{run_unit_id:"bats:tests/b",missing_proof:"budget_exhausted",
                       next_measurement:"run it alone with a 10 minute budget"}]}' > "$AD/decision.json"

  run bash "$REPORT" --audit-dir "$AD" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  [ -f "$AD/report.html" ]
  run _sections_present "$AD/report.html"
  [ "$status" -eq 0 ]
  # The damning number is on the page: 1 of 2 units unexamined.
  grep -q "zatím neprověřeno do hloubky" "$AD/report.html"
  # The censored unit is named as a lower bound, not a measurement.
  grep -q "utnuto" "$AD/report.html"
}

@test "an EMPTY audit still renders all nine sections, each saying what is missing" {
  # No inventory, no measurements, no agents, no decision. The page must not
  # shrink — a section with no data says so instead of vanishing.
  run bash "$REPORT" --audit-dir "$AD" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  run _sections_present "$AD/report.html"
  [ "$status" -eq 0 ]
  grep -q "nehledalo se" "$AD/report.html" || grep -q "Inventura chybí" "$AD/report.html"
}

@test "unexamined keep is counted as NOT examined, never as health" {
  printf '{"schema_version":"1.0.0","generated_at":"t","runner_families":["bats"],"entries":[{"run_unit_id":"bats:tests/a","runner":"bats","adapter":"bats","confidence":"medium"}]}' > "$AD/inventory.json"
  jq -n '{schema_version:"1.0.0",focus:"shard_portfolio",wave:1,shard_id:"s0",findings:[],
          produced_at:"t",producer_agent_dispatch_id:"d0",
          dispositions:[{run_unit_id:"bats:tests/a",disposition:"keep",falsification:{method:"unproved"}}]}' > "$AD/agents/1.json"
  run bash "$REPORT" --audit-dir "$AD" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  # 1 unit, 0 examined, 1 unexamined — the page carries the honest split.
  grep -q "<b>0</b> prověřeno s důkazem, <b>1</b>" "$AD/report.html"
}

@test "risk and reliability sections consume the content scan when present" {
  printf '{"schema_version":"1.0.0","generated_at":"t","runner_families":["bats"],"entries":[]}' > "$AD/inventory.json"
  jq -n '{schema_version:"aid-test-content-scan-v1",
    checks:{duplicate_test_cases:[],weak_oracle:[],gate_overlap:[],unreferenced_tests:[],
      untested_surfaces:[{file:"src/pay/charge.ts",changes_90d:9}],
      test_freshness:{stale_180d:0,files:[]},
      gate_stability:[{gate:"plan_diff",samples:14,pass_rate:0,censored:0}]},
    counts:{untested_surfaces:1}}' > "$AD/content-scan.json"
  run bash "$REPORT" --audit-dir "$AD" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  grep -q "src/pay/charge.ts" "$AD/report.html"
  grep -q "nikdy neprošla" "$AD/report.html"
}

@test "the second round shows a trend against the first" {
  mkdir -p "$TEST_TMPDIR/rounds/r1" "$TEST_TMPDIR/rounds/r2"
  printf '{"audit_id":"R1","units":10,"examined":2,"unexamined":8,"measured_min":5.0,"censored":3,"actions":4}'     > "$TEST_TMPDIR/rounds/r1/round-summary.json"
  printf '{"schema_version":"1.0.0","generated_at":"t","runner_families":["bats"],"entries":[]}' > "$TEST_TMPDIR/rounds/r2/inventory.json"
  run bash "$REPORT" --audit-dir "$TEST_TMPDIR/rounds/r2" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  grep -q "Trend od minulého kola" "$TEST_TMPDIR/rounds/r2/report.html"
  grep -q "R1" "$TEST_TMPDIR/rounds/r2/report.html"
}
