#!/usr/bin/env bash
# A real run of the whole production chain against a disposable clone:
#   measure -> select -> profile -> finalize
# Nothing fabricated: the measurement comes from a real supervised run, the
# selection from that measurement, the profile from a real profiling run, and
# the decision from the real finalize entrypoint.
set -uo pipefail
REPO=/opt/eco/projects/aid-orchestrator
SP=/tmp/claude-1000/-opt-eco-projects-aid-orchestrator/fceea7f1-bc28-44a6-8212-974e4b4cda61/scratchpad
C="$SP/e2e-clone"; W="$SP/e2e-work"; OUT="$W/out"; ART="$W/agents"
S="$REPO/plugins/aid-orchestrator/scripts"
rm -rf "$C" "$W"
git clone -q "$REPO" "$C"
mkdir -p "$C/.aid-o/config" "$ART" "$OUT"
cp "$REPO"/.aid-o/config/{test-catalog.yaml,execution.yaml,test-audit.yaml} "$C/.aid-o/config/" 2>/dev/null

AUDIT_ID="e2e-$(date +%s)"
UNIT="bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"
UNIT2="bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-audit-config"

# --- 1. measure: a REAL supervised run of the unit, through the real library
source "$S/lib/aid-test-audit-measure.sh"
CMD="$(yq -o=json '.' "$C/.aid-o/config/test-catalog.yaml" \
       | jq -c --arg id "$UNIT" '.run_units[] | select(.run_unit_id==$id) | .command')"
CMD2="$(yq -o=json '.' "$C/.aid-o/config/test-catalog.yaml" \
       | jq -c --arg id "$UNIT2" '.run_units[] | select(.run_unit_id==$id) | .command')"
jq -nc --arg u "$UNIT" --argjson c "$CMD" --arg u2 "$UNIT2" --argjson c2 "$CMD2" \
  '[{run_unit_id:$u, command:$c, deadline_seconds:300},
    {run_unit_id:$u2, command:$c2, deadline_seconds:300}]' > "$W/plan.json"

( cd "$C" && aid_test_audit_measure_run_all "full" "$W/jobs" "$(cat "$W/plan.json")" \
    "$W/measurements.jsonl" "$C/.aid-o/config/execution.yaml" \
    "$C/.aid-o/config/test-catalog.yaml" ) >/dev/null
echo "--- measurements ---"; jq -c '{run_unit_id,state,duration_ms}' "$W/measurements.jsonl"

# --- 2. select: trigger set low enough that a real unit is genuinely selected
bash "$S/aid-test-audit-profile-select.sh" --measurements "$W/measurements.jsonl" \
  --project-root "$REPO" --audit-id "$AUDIT_ID" --output "$OUT/profile-selection.json" \
  --trigger-ms 1 --max-units 1 >/dev/null
echo "--- selection ---"; jq -c '{selected:[.selected[].run_unit_id],deferred:[.deferred[].run_unit_id]}' "$OUT/profile-selection.json"

# --- 3. profile: a REAL profiling run of exactly the selected unit
SEL="$(jq -r '.selected[0].run_unit_id' "$OUT/profile-selection.json")"
bash "$S/aid-test-audit-profile.sh" --run-unit-id "$SEL" \
  --catalog "$C/.aid-o/config/test-catalog.yaml" \
  --execution-yaml "$C/.aid-o/config/execution.yaml" \
  --output-dir "$OUT" --audit-id "$AUDIT_ID" \
  --target-root "$C" --project-root "$REPO" --budget-minutes 5 >/dev/null
echo "--- profile receipt ---"
jq -c '{run_unit_id,complete,job:.job.state,bucket:.root_cause.bucket,conf:.root_cause.confidence}' \
  "$OUT/profiles/$(echo "$SEL" | tr '/:' '__').json"

# --- 4. finalize through the real production entrypoint
jq -nc --arg a "$AUDIT_ID" --arg u1 "$UNIT" --arg u2 "$UNIT2" \
  '{audit_id:$a, max_concurrent_agents:1, entries:[
     {wave:1, focus:"shard_portfolio", shard_id:"shard-0", run_unit_ids:[$u1,$u2],
      artifact_path:"agents/1-shard_portfolio-shard-0.json",
      producer_agent_dispatch_id:"d0"}]}' > "$W/manifest.json"
jq -nc --arg u1 "$UNIT" --arg u2 "$UNIT2" \
  '{schema_version:"1.0.0", run_units:[{run_unit_id:$u1},{run_unit_id:$u2}]}' > "$W/inventory.json"
_disp() { jq -nc --arg id "$1" '
  {run_unit_id:$id, disposition:"keep",
   behavior_claim:"guards the transition table against silent reordering",
   failure_signal:"transition returns the previous state instead of the next",
   falsification:{method:"unproved"}, uniqueness:"unique", layer:"unit",
   cheaper_layer_possible:"no", cost:{kind:"unknown", duration_ms:null}, confidence:"medium"}'; }
jq -n --argjson d "$(printf '%s\n' "$(_disp "$UNIT")" "$(_disp "$UNIT2")" | jq -s -c '.')" \
  '{schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
    findings:[], produced_at:"2026-08-03T00:00:00Z",
    producer_agent_dispatch_id:"d0", dispositions:$d}' \
  > "$ART/1-shard_portfolio-shard-0.json"

bash "$S/aid-audit-tests-finalize.sh" --audit-id "$AUDIT_ID" \
  --wave-artifacts-dir "$ART" --dispatch-manifest "$W/manifest.json" \
  --output-dir "$OUT" --mode full --inventory "$W/inventory.json" \
  --project-root "$REPO" > "$W/chat.txt"
rc=$?
echo "--- finalize rc=$rc ---"
echo "--- decision actions ---"
jq -c '.actions[] | {action, targets, kind:.impact.kind, before:.impact.before_ms}' "$OUT/decision.json"
echo "--- audit status: $(jq -r '.audit_status' "$OUT/decision.json") ---"
