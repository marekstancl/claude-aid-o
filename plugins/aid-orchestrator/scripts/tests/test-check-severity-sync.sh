#!/usr/bin/env bash
# test-check-severity-sync.sh — registry sync guard for the compliance system.
#
# evaluate_compliance_checks (aid-fsm.sh) emits check dimensions; fsm_build_failures
# enriches each failure's severity from check-severity.yaml. A check MISSING from
# the registry silently defaults to "advisory" — it looks wired but can never block
# (the P026 failure mode; see AID-v3-principles.md §1, Detector without Enforcement
# is Decoration). This suite fails when a check emitted by the FSM has no registry
# entry, so a new detection capability cannot ship without an explicit severity
# decision in defaults/check-severity.yaml.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY="${PLUGIN_DIR}/defaults/check-severity.yaml"
AID_FSM="${PLUGIN_DIR}/scripts/aid-fsm.sh"

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass+1)); }

for dep in jq yq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "  FAIL: $dep not installed — cannot verify registry sync"
    echo "Results: 0/1 passed, 1 failed"
    exit 1
  fi
done

echo "TEST: defaults/check-severity.yaml parses with a .checks object"
registry_keys=$(yq -o=json eval '.checks // {}' "$REGISTRY" 2>/dev/null | jq -r 'keys[]' 2>/dev/null) || registry_keys=""
if [[ -n "$registry_keys" ]]; then
  pass_msg "registry parsed ($(wc -l <<<"$registry_keys" | tr -d ' ') checks)"
else
  fail_msg "registry missing or unparsable: $REGISTRY"
fi

echo "TEST: every check emitted by evaluate_compliance_checks has a registry entry"
# Run a minimal DONE-state fixture through done-advance review→release; the run
# writes compliance.json whose top-level .checks scalar keys are the live check
# names (object-valued keys like verifier_outputs are containers, not checks).
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export AID_TEST_MODE=1
EV="$TMP/.aid-o/work/evidence/E-SYNC-1/R-SYNC-1"
CFG="$TMP/.aid-o/config"
mkdir -p "$EV/gates" "$CFG" "$TMP/.aid-o/tasks" "$TMP/.aid-o/work"
cat > "$EV/fsm-state.yaml" <<EOF
epic_id: E-SYNC-1
run_id: R-SYNC-1
branch: task/E-SYNC-1/main
state: DONE
done_phase: review
created_at: 2026-05-13T10:00:00Z
total_steps: 1
current_step: 1
pm_decision: merge
EOF
cp "$REGISTRY" "$CFG/check-severity.yaml"
touch "$CFG/execution.yaml"
printf '{"_generated_by":"aid-run-gates.sh@sync-test","_generated_at":"2026-06-18T00:00:00Z","_command_log":[]}\n' > "$EV/gates/gates_report.json"
echo "sync-test curator report" > "$EV/curator-report.md"
# blocking_findings: false must be at line-start (Step 3 fail-closed — E-046-1_3)
printf 'blocking_findings: false\nsync-test auditor report\n' > "$EV/audit-report.md"
: > "$EV/timeline.jsonl"
: > "$TMP/.aid-o/work/audit-log.jsonl"
( cd "$TMP" && bash "$AID_FSM" done-advance review release "$EV/fsm-state.yaml" >/dev/null 2>&1 ) || true

if [[ ! -f "$EV/compliance.json" ]]; then
  fail_msg "fixture run produced no compliance.json — cannot verify sync"
else
  emitted=$(jq -r '.checks | to_entries[] | select(.value | type != "object") | .key' "$EV/compliance.json" 2>/dev/null)
  missing=0
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    if ! grep -qxF "$key" <<<"$registry_keys"; then
      fail_msg "check '${key}' emitted by the FSM but missing from defaults/check-severity.yaml (silently defaults to advisory — register it with an explicit severity)"
      missing=$((missing+1))
    fi
  done <<<"$emitted"
  if (( missing == 0 )); then
    pass_msg "all $(wc -l <<<"$emitted" | tr -d ' ') emitted checks registered"
  fi
fi

echo "TEST: synthetic failure check names are registered"
# Names injected by fsm_build_failures outside the checks template. Keep this list
# in sync with synthetic {check: "<name>"} entries in aid-fsm.sh.
for synth in verifier_provenance; do
  if grep -qxF "$synth" <<<"$registry_keys"; then
    pass_msg "synthetic '${synth}' registered"
  else
    fail_msg "synthetic check '${synth}' missing from registry"
  fi
done

echo "----------------------------------------------------------------------"
total=$(( pass + fail ))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
