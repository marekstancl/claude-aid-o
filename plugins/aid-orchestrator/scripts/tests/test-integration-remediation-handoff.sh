#!/usr/bin/env bash
# test-integration-remediation-handoff.sh — P066 Step 22.
#
# Confirms the sanctioned handoff (Step 16) works end to end against a
# REAL brief built from Step 21's own self-host-audit finding: runs the
# real aid-test-audit-consolidate.sh (Step 14) on a genuine wave artifact,
# renders the real chat summary (Step 15, which persists the durable
# record), then asserts aid_test_audit_write_plan_bridge_check (Step 16)
# returns {ready:true,...} against this repo's own real, approved
# .aid-o/config/test-catalog.yaml.
#
# The controller's own subsequent `/aid-plan write` invocation (producing
# a new plan file under .aid-o/plans/, distinct from P066, tracing every
# item to a specific Step 21 finding) is a live, controller-performed
# action — same testability boundary as Step 24 Part B — and is NOT part
# of what this bash script can prove; it is performed once, separately, as
# real session evidence at this step's own authoring time.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }

for dep in jq yq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

REAL_CATALOG="${REPO_ROOT}/.aid-o/config/test-catalog.yaml"
if [[ ! -f "$REAL_CATALOG" ]]; then
  echo "  FAIL: ${REAL_CATALOG} does not exist — run aid-test-catalog-approve.sh first (Step 17)"
  echo "Results: 0/1 passed, 1 failed"
  exit 1
fi

# An anchor run_unit_id guaranteed to exist in this repo's own catalog —
# the audit CLI's own test suite, a genuine, stable, self-referential
# choice for a finding ABOUT the audit tooling itself.
ANCHOR_RUN_UNIT_ID="bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-audit-tests-cli"
echo "TEST: the anchor run_unit_id used by this handoff's real finding actually resolves in the real catalog"
resolved="$(yq -o=json '.run_units' "$REAL_CATALOG" | jq -r --arg id "$ANCHOR_RUN_UNIT_ID" 'any(.run_unit_id == $id)')"
if [[ "$resolved" == "true" ]]; then
  pass_msg "anchor run_unit_id '${ANCHOR_RUN_UNIT_ID}' resolves in ${REAL_CATALOG}"
else
  fail_msg "anchor run_unit_id '${ANCHOR_RUN_UNIT_ID}' does NOT resolve — catalog may have changed since this test was authored"
  echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
AGENTS_DIR="${WORK_DIR}/agents"
OUT_DIR="${WORK_DIR}/out"
mkdir -p "$AGENTS_DIR" "$OUT_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

# A REAL wave artifact built from Step 21's own actual, reproduced finding
# (the disposable-clone .aid-o/config/ portability gap) — never a
# fabricated/hand-waved example.
jq -n --arg ruid "$ANCHOR_RUN_UNIT_ID" '{
  schema_version: "1.0.0", focus: "shard_portfolio", wave: 1, shard_id: "shard-0",
  findings: [{
    run_unit_id: $ruid,
    category: "audit-tooling-portability",
    severity: "medium",
    evidence_refs: ["Step21:self-host-audit-finding-1", ".aid-o/work/test-audits/self-host-audit-findings.txt"],
    recommendation: "fix",
    confidence: "high",
    falsification_check: "a plain git clone of this repo, followed by running aid-test-inventory.sh against it WITHOUT first copying .aid-o/config/, produces zero declared-command run_units where the live checkout produces 8 — reproduced directly in Step 21'\''s own test (test-integration-self-host-audit.sh)."
  }],
  produced_at: "2026-07-30T13:38:26Z", producer_agent_dispatch_id: "e22-selfhost-1"
}' > "${AGENTS_DIR}/1-shard_portfolio-shard-0.json"

jq -n --arg path "${AGENTS_DIR}/1-shard_portfolio-shard-0.json" '{
  audit_id: "e22-remediation", max_concurrent_agents: 4,
  entries: [{wave:1, focus:"shard_portfolio", shard_id:"shard-0", artifact_path:$path, producer_agent_dispatch_id:"e22-selfhost-1"}]
}' > "${WORK_DIR}/dispatch-manifest.json"

echo "TEST: the real Step 14 consolidator runs successfully on this real finding"
if bash "${PLUGIN_DIR}/scripts/aid-test-audit-consolidate.sh" \
    --audit-id e22-remediation --wave-artifacts-dir "$AGENTS_DIR" \
    --dispatch-manifest "${WORK_DIR}/dispatch-manifest.json" --output-dir "$OUT_DIR" >/dev/null; then
  pass_msg "consolidate.sh produced consolidated-findings.json + implementation-plan-brief.{json,md}"
else
  fail_msg "aid-test-audit-consolidate.sh failed"
  echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
  exit 1
fi
[[ -f "${OUT_DIR}/implementation-plan-brief.json" ]] && pass_msg "implementation-plan-brief.json exists (this finding IS actionable/Medium+)" \
  || fail_msg "implementation-plan-brief.json missing — expected for a Medium 'fix' finding"

echo "TEST: the real Step 15 chat-summary renderer classifies this as 'remediation recommended' and persists the durable record"
chat_output="$(bash -c "source '${PLUGIN_DIR}/scripts/lib/aid-test-audit-chat-summary.sh'; aid_test_audit_render_chat_summary '${OUT_DIR}/consolidated-findings.json'")"
if [[ "$chat_output" == *"**Verdict:** remediation recommended"* ]]; then
  pass_msg "chat summary verdict: remediation recommended"
else
  fail_msg "expected 'remediation recommended', got: $chat_output"
fi
[[ -f "${OUT_DIR}/durable-record.json" ]] && pass_msg "durable-record.json was persisted" || fail_msg "durable-record.json missing"

echo "TEST: Step 16's validator returns {ready:true,...} for this REAL brief against this repo's REAL approved catalog"
# P072 Step 3: the bridge's decision gate applies to `full` mode only. These
# fixtures produce findings + brief but no decision artifact, which under the
# new contract is exactly a `measure`-mode audit — so the mode is now stated
# explicitly rather than relying on the default. A full-mode variant carrying
# a real decision artifact arrives with Steps 4-6, which are what make a
# per-unit disposition (and therefore a complete decision) exist at all.
bridge_output="$(bash -c "source '${PLUGIN_DIR}/scripts/lib/aid-test-audit-write-plan-bridge.sh'; aid_test_audit_write_plan_bridge_check '${OUT_DIR}' '${REAL_CATALOG}' measure")"
echo "  bridge result: ${bridge_output}"
if echo "$bridge_output" | jq -e '.ready == true' >/dev/null 2>&1; then
  pass_msg "bridge returned {ready:true,...} — the /aid-plan write handoff is genuinely reachable"
else
  fail_msg "bridge did not return ready:true: ${bridge_output}"
fi

brief_path="$(echo "$bridge_output" | jq -r '.brief_path // empty')"
[[ -n "$brief_path" && -f "$brief_path" ]] && pass_msg "bridge's returned brief_path exists on disk: ${brief_path}" \
  || fail_msg "bridge's returned brief_path is missing or does not exist"

echo "----------------------------------------------------------------------"
total=$((pass + fail))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
