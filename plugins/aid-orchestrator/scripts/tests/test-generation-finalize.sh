#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SCRIPTS="$ROOT/plugins/aid-orchestrator/scripts"
PLAN="$SCRIPTS/tests/fixtures/multi-phase-plan-numeric.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.aid-o/plans" "$tmp/.aid-o/tasks" "$tmp/.aid-o/config" "$tmp/.aid-o/work/evidence/P099/generation"
cp "$PLAN" "$tmp/.aid-o/plans/P099.md"
printf 'counter: 0\n' > "$tmp/.aid-o/config/counter.yaml"

bash "$SCRIPTS/aid-generation-readiness.sh" "$tmp/.aid-o/plans/P099.md" --total 3 \
  --write-provisional "$tmp/.aid-o/work/evidence/P099/generation/provisional-graph.json" >/dev/null
for phase in 1 2 3; do
  epic="$(bash "$SCRIPTS/aid-plan-to-epic.sh" --plan "$tmp/.aid-o/plans/P099.md" --phase "$phase" --total 3 --epic-template "$ROOT/plugins/aid-orchestrator/defaults/templates/epic.md" --output-dir "$tmp/.aid-o/tasks" --counter-yaml "$tmp/.aid-o/config/counter.yaml")"
  result="$(bash "$SCRIPTS/aid-epic-to-json.sh" --epic "$epic" --schema "$ROOT/plugins/aid-orchestrator/defaults/templates/plan.schema.json" --output-dir "$tmp/.aid-o" --plan-source "$tmp/.aid-o/plans/P099.md")"
  plan_json="$(jq -r '.plan_json' <<< "$result")"
  jq -n --argjson phase "$phase" --arg epic_id "$(jq -r '.epic_id' "$plan_json")" --arg epic_path "$epic" --arg plan_json "$plan_json" \
    '{phase:$phase,epic_id:$epic_id,epic_path:$epic_path,plan_json:$plan_json}'
done | jq -s . > "$tmp/epics.json"

receipt="$tmp/.aid-o/work/evidence/P099/generation/receipt.json"
bash "$SCRIPTS/aid-generation-finalize.sh" --plan "$tmp/.aid-o/plans/P099.md" --total 3 --epics-json "$tmp/epics.json" --output "$receipt" >/dev/null
jq -e '.schema == "aid-generation-receipt/v1" and (.epics|length == 3)' "$receipt" >/dev/null
echo "PASS: complete generated package writes a receipt"

jq '.[1].phase = 1' "$tmp/epics.json" > "$tmp/duplicate-phase.json"
if bash "$SCRIPTS/aid-generation-finalize.sh" --plan "$tmp/.aid-o/plans/P099.md" --total 3 --epics-json "$tmp/duplicate-phase.json" --output "$tmp/bad.json" >/dev/null 2>&1; then
  echo "FAIL: duplicate phase was accepted" >&2; exit 1
fi
echo "PASS: duplicate phase is rejected"
