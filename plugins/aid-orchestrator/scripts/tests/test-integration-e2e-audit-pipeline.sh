#!/usr/bin/env bash
# test-integration-e2e-audit-pipeline.sh — P066 Step 24, Part A.
#
# Automated, subprocess-level E2E scenarios — what Bats/plain-bash CAN
# genuinely prove. Part B (a real controller session dispatching real
# agents + a real /aid-plan write invocation) is NOT provable here — same
# testability boundary as Steps 15/16/24 themselves state explicitly.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }

for dep in jq yq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# ─── Scenario 1: a freshly-scanned fixture project with ONLY a Vitest
#     package-script test (no Bats at all) still produces a non-empty,
#     schema-valid catalog — the audit works for a non-Bats project.
FIXTURE="${WORK_DIR}/vitest-only-project"
mkdir -p "$FIXTURE"
cat > "${FIXTURE}/package.json" <<'JSON'
{
  "name": "vitest-only-fixture",
  "scripts": {
    "test": "vitest run"
  }
}
JSON
( cd "$FIXTURE" && git init -q && git config user.email t@t.local && git config user.name T \
    && echo init > .gitkeep && git add .gitkeep package.json && git commit -q -m init )

FIXTURE_OUT="${WORK_DIR}/fixture-out"
mkdir -p "$FIXTURE_OUT"
echo "TEST: a Vitest-only project (no Bats) produces a non-empty, schema-valid catalog"
if bash "${PLUGIN_DIR}/scripts/aid-test-inventory.sh" \
    --project-root "$FIXTURE" --audit-id e2e-vitest-only --output-dir "$FIXTURE_OUT" >/dev/null; then
  catalog="${FIXTURE_OUT}/test-catalog.proposed.yaml"
  unit_count="$(yq -o=json '.run_units | length' "$catalog" 2>/dev/null)"
  if [[ "${unit_count:-0}" -gt 0 ]]; then
    pass_msg "non-Bats fixture project produced ${unit_count} run_unit(s) (package-script adapter)"
  else
    fail_msg "non-Bats fixture project produced zero run_units — expected at least the 'npm:test' package-script unit"
  fi
else
  fail_msg "aid-test-inventory.sh failed against the Vitest-only fixture"
fi

# ─── Scenario 2: invoke the REAL, mandatory production entrypoint
#     (aid-audit-tests-finalize.sh, Step 24's E4 release blocker) against a
#     synthetic-but-real wave artifact for this fixture — never the
#     individual consolidator/renderer functions directly. Codex review: an
#     earlier version of this scenario called consolidate.sh + the renderer
#     function separately, so it would stay green even if the finalizer
#     itself broke its own argument forwarding, stage ordering, or
#     durable-record failure handling — it never actually exercised the
#     entrypoint it claims to verify.
FINALIZE="${PLUGIN_DIR}/scripts/aid-audit-tests-finalize.sh"
AGENTS_DIR="${WORK_DIR}/agents"
mkdir -p "$AGENTS_DIR"
jq -n '{
  schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
  findings: [{run_unit_id:"npm:test", category:"cost", severity:"low", evidence_refs:["r1"], recommendation:"keep", confidence:"medium", falsification_check:"n/a"}],
  produced_at:"2026-07-30T00:00:00Z", producer_agent_dispatch_id:"e2e-1"
}' > "${AGENTS_DIR}/1-shard_portfolio-shard-0.json"
jq -n --arg path "${AGENTS_DIR}/1-shard_portfolio-shard-0.json" '{
  audit_id:"e2e-vitest-only", max_concurrent_agents:4,
  entries:[{wave:1, focus:"shard_portfolio", shard_id:"shard-0", artifact_path:$path, producer_agent_dispatch_id:"e2e-1"}]
}' > "${WORK_DIR}/manifest.json"

echo "TEST: the real production entrypoint (finalize.sh) produces correctly-shaped 5-part chat text for this fixture"
chat_text="$(bash "$FINALIZE" --audit-id e2e-vitest-only --wave-artifacts-dir "$AGENTS_DIR" \
  --dispatch-manifest "${WORK_DIR}/manifest.json" --output-dir "$FIXTURE_OUT")"
finalize_status=$?
if [[ "$finalize_status" -eq 0 ]]; then
  ok=1
  for marker in '**Verdict:**' '**Reasons:**' '**Changed:**' '**Next action:**' '**Residual risk'; do
    [[ "$chat_text" == *"$marker"* ]] || ok=0
  done
  if [[ "$ok" -eq 1 ]]; then
    pass_msg "finalize.sh's chat text contains all 5 mandatory parts"
  else
    fail_msg "finalize.sh's chat text is missing one or more of the 5 mandatory parts: ${chat_text}"
  fi
else
  fail_msg "finalize.sh exited ${finalize_status} for the fixture's own wave artifact"
fi

# ─── Scenario 3: the finalizer's --write-plan path returns ready:true for a
#     real 'remediation recommended' brief, driven end to end through
#     finalize.sh itself (never the bridge function called separately).
echo "TEST: finalize.sh --write-plan returns ready:true for a real remediation-recommended brief"
REMEDIATION_AGENTS="${WORK_DIR}/remediation-agents"
REMEDIATION_OUT="${WORK_DIR}/remediation-out"
mkdir -p "$REMEDIATION_AGENTS" "$REMEDIATION_OUT"
jq -n '{
  schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0",
  findings: [{run_unit_id:"npm:test", category:"cost", severity:"high", evidence_refs:["r1"], recommendation:"fix", confidence:"medium", falsification_check:"x"}],
  produced_at:"2026-07-30T00:00:00Z", producer_agent_dispatch_id:"e2e-2"
}' > "${REMEDIATION_AGENTS}/1-shard_portfolio-shard-0.json"
jq -n --arg path "${REMEDIATION_AGENTS}/1-shard_portfolio-shard-0.json" '{
  audit_id:"e2e-remediation", max_concurrent_agents:4,
  entries:[{wave:1, focus:"shard_portfolio", shard_id:"shard-0", artifact_path:$path, producer_agent_dispatch_id:"e2e-2"}]
}' > "${WORK_DIR}/remediation-manifest.json"
mini_catalog="${WORK_DIR}/mini-catalog.yaml"
jq -n '{schema_version:"1.0.0", generated_at:"2026-07-30T00:00:00Z", status:"approved", run_units:[{run_unit_id:"npm:test"}], source_pattern_mappings:[], mapping_approval:{status:"proposed"}}' | yq -P '.' > "$mini_catalog"

finalize_output="$(bash "$FINALIZE" --audit-id e2e-remediation --wave-artifacts-dir "$REMEDIATION_AGENTS" \
  --dispatch-manifest "${WORK_DIR}/remediation-manifest.json" --output-dir "$REMEDIATION_OUT" \
  --catalog "$mini_catalog" --mode measure --write-plan)"
bridge_result="$(echo "$finalize_output" | tail -1)"
if echo "$bridge_result" | jq -e '.ready == true' >/dev/null 2>&1; then
  pass_msg "finalize.sh --write-plan returned ready:true for a real remediation-recommended brief"
else
  fail_msg "expected ready:true, got: ${bridge_result}"
fi

echo "TEST: Step 16 validator returns ready:false for a clean-verdict audit"
CLEAN_OUT="${WORK_DIR}/clean-out"
mkdir -p "$CLEAN_OUT"
bash -c "source '${PLUGIN_DIR}/scripts/lib/aid-test-audit-write-plan-bridge.sh'; aid_test_audit_write_plan_bridge_persist '${CLEAN_OUT}' 'e2e-clean' 'clean' 'no action needed'"
# P072 Step 3: the bridge's decision gate applies to `full` mode only. These
# fixtures produce findings + brief but no decision artifact, which under the
# new contract is exactly a `measure`-mode audit — so the mode is now stated
# explicitly rather than relying on the default. A full-mode variant carrying
# a real decision artifact arrives with Steps 4-6, which are what make a
# per-unit disposition (and therefore a complete decision) exist at all.
clean_result="$(bash -c "source '${PLUGIN_DIR}/scripts/lib/aid-test-audit-write-plan-bridge.sh'; aid_test_audit_write_plan_bridge_check '${CLEAN_OUT}' '${mini_catalog}' measure")"
if echo "$clean_result" | jq -e '.ready == false' >/dev/null 2>&1; then
  pass_msg "bridge returned ready:false for a clean-verdict audit"
else
  fail_msg "expected ready:false for clean verdict, got: ${clean_result}"
fi

echo "TEST: Step 16 validator returns ready:false for a stale run_unit_id"
stale_catalog="${WORK_DIR}/stale-catalog.yaml"
jq -n '{schema_version:"1.0.0", generated_at:"2026-07-30T00:00:00Z", status:"approved", run_units:[{run_unit_id:"npm:something-else"}], source_pattern_mappings:[], mapping_approval:{status:"proposed"}}' | yq -P '.' > "$stale_catalog"
stale_result="$(bash -c "source '${PLUGIN_DIR}/scripts/lib/aid-test-audit-write-plan-bridge.sh'; aid_test_audit_write_plan_bridge_check '${REMEDIATION_OUT}' '${stale_catalog}' measure")"
if echo "$stale_result" | jq -e '.ready == false' >/dev/null 2>&1 && [[ "$stale_result" == *"stale run_unit_id"* ]]; then
  pass_msg "bridge returned ready:false with a named stale run_unit_id"
else
  fail_msg "expected ready:false/stale run_unit_id, got: ${stale_result}"
fi

echo "TEST: finalize.sh fails closed on an incomplete wave set (missing declared Wave 3) — no chat text, no durable record"
INCOMPLETE_AGENTS="${WORK_DIR}/incomplete-agents"
INCOMPLETE_OUT="${WORK_DIR}/incomplete-out"
mkdir -p "$INCOMPLETE_AGENTS" "$INCOMPLETE_OUT"
jq -n '{schema_version:"1.0.0", focus:"shard_portfolio", wave:1, shard_id:"shard-0", findings:[], produced_at:"2026-07-30T00:00:00Z", producer_agent_dispatch_id:"e2e-3"}' > "${INCOMPLETE_AGENTS}/1-shard_portfolio-shard-0.json"
jq -n --arg p1 "${INCOMPLETE_AGENTS}/1-shard_portfolio-shard-0.json" --arg p3 "${INCOMPLETE_AGENTS}/3-adversarial_review.json" '{
  audit_id:"e2e-incomplete", max_concurrent_agents:4,
  entries:[
    {wave:1, focus:"shard_portfolio", shard_id:"shard-0", artifact_path:$p1, producer_agent_dispatch_id:"e2e-3"},
    {wave:3, focus:"adversarial_review", shard_id:null, artifact_path:$p3, producer_agent_dispatch_id:"e2e-4"}
  ]
}' > "${WORK_DIR}/incomplete-manifest.json"
if bash "$FINALIZE" --audit-id e2e-incomplete --wave-artifacts-dir "$INCOMPLETE_AGENTS" \
    --dispatch-manifest "${WORK_DIR}/incomplete-manifest.json" --output-dir "$INCOMPLETE_OUT" >/dev/null 2>&1; then
  fail_msg "finalize.sh exited 0 for an incomplete wave set — expected a hard failure"
else
  no_artifacts="$(find "$INCOMPLETE_OUT" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$no_artifacts" -eq 0 ]]; then
    pass_msg "finalize.sh failed closed on an incomplete wave set — no consolidated-findings.json, no durable record, nothing written"
  else
    fail_msg "finalize.sh failed but left ${no_artifacts} file(s) behind in ${INCOMPLETE_OUT}"
  fi
fi

# ─── Negative scenario: aid-audit-tests is never wired into any FSM/gate/
#     release dispatch path (test_audit_never_auto_invoked, Step 19).
echo "TEST: aid-audit-tests is absent from pipeline.md's DONE-state dispatch and aid-fsm.sh's done-advance/plan-final paths"
if ! grep -qi "aid-audit-tests" "${PLUGIN_DIR}/skills/pipeline.md"; then
  pass_msg "skills/pipeline.md never mentions aid-audit-tests"
else
  fail_msg "skills/pipeline.md mentions aid-audit-tests — this command must never be wired into the EPIC dispatch lifecycle"
fi
if ! grep -qi "aid-audit-tests" "${PLUGIN_DIR}/scripts/aid-fsm.sh"; then
  pass_msg "scripts/aid-fsm.sh never mentions aid-audit-tests (done-advance/plan-final code paths clean)"
else
  fail_msg "scripts/aid-fsm.sh mentions aid-audit-tests — this command must never be wired into done-advance or plan-final"
fi

echo "----------------------------------------------------------------------"
total=$((pass + fail))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
