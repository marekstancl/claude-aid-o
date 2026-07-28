#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SCRIPTS="$ROOT/plugins/aid-orchestrator/scripts"
PLAN="$SCRIPTS/tests/fixtures/multi-phase-plan-numeric.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.aid-o/plans" "$tmp/.aid-o/tasks" "$tmp/.aid-o/config" "$tmp/.aid-o/work/evidence/P099/generation"
cp "$PLAN" "$tmp/.aid-o/plans/P099.md"
# Make the E2E path exercise the actual strict receipt consumer, not only the
# legacy-compatible path. The plan is still low risk; strictness is explicit.
sed -i '/^author:/a lifecycle_strict: true' "$tmp/.aid-o/plans/P099.md"
printf 'counter: 0\n' > "$tmp/.aid-o/config/counter.yaml"
git -C "$tmp" init -q
git -C "$tmp" config user.email aid-test@example.com
git -C "$tmp" config user.name "AID Test"
git -C "$tmp" checkout -q -b main
git -C "$tmp" commit --allow-empty -qm "seed"

bash "$SCRIPTS/aid-generation-readiness.sh" "$tmp/.aid-o/plans/P099.md" --total 3 \
  --write-provisional "$tmp/.aid-o/work/evidence/P099/generation/provisional-graph.json" >/dev/null
for phase in 1 2 3; do
  epic="$(bash "$SCRIPTS/aid-plan-to-epic.sh" --plan "$tmp/.aid-o/plans/P099.md" --phase "$phase" --total 3 --epic-template "$ROOT/plugins/aid-orchestrator/defaults/templates/epic.md" --output-dir "$tmp/.aid-o/tasks" --counter-yaml "$tmp/.aid-o/config/counter.yaml")"
  result="$(bash "$SCRIPTS/aid-epic-to-json.sh" --epic "$epic" --schema "$ROOT/plugins/aid-orchestrator/defaults/templates/plan.schema.json" --output-dir "$tmp/.aid-o" --plan-source "$tmp/.aid-o/plans/P099.md")"
  plan_json="$(jq -r '.plan_json' <<< "$result")"
  contract_dir="$tmp/.aid-o/work/evidence/P099/generation/epics/$(jq -r '.epic_id' "$plan_json")/c0"
  mkdir -p "$contract_dir"
  bash "$SCRIPTS/gates/aid-contract-validate.sh" "$plan_json" "$epic" > "$contract_dir/contract-validate.json"
  jq -n --argjson phase "$phase" --arg epic_id "$(jq -r '.epic_id' "$plan_json")" --arg epic_path "$epic" --arg plan_json "$plan_json" --arg contract_validate "$contract_dir/contract-validate.json" \
    '{phase:$phase,epic_id:$epic_id,epic_path:$epic_path,plan_json:$plan_json,contract_validate:$contract_validate}'
done | jq -s . > "$tmp/epics.json"

receipt="$tmp/.aid-o/work/evidence/P099/generation/receipt.json"
bash "$SCRIPTS/aid-generation-finalize.sh" --plan "$tmp/.aid-o/plans/P099.md" --total 3 --epics-json "$tmp/epics.json" --output "$receipt" >/dev/null
jq -e '.schema == "aid-generation-receipt/v1" and (.epics|length == 3)' "$receipt" >/dev/null
echo "PASS: complete generated package writes a receipt"

# This is the actual post-receipt half of the pipeline: before this point no
# FSM state or queue entry exists; after it all phases can be safely started.
for phase in 1 2 3; do
  entry="$(jq -c --argjson p "$phase" '.[] | select(.phase == $p)' "$tmp/epics.json")"
  epic_id="$(jq -r '.epic_id' <<< "$entry")"
  epic="$(jq -r '.epic_path' <<< "$entry")"
  plan_json="$(jq -r '.plan_json' <<< "$entry")"
  run_id="R-E099-${phase}"
  run_dir="$tmp/.aid-o/work/runs/$run_id"
  (cd "$tmp" && bash "$SCRIPTS/aid-json-to-run.sh" --plan-json "$plan_json" --run-template "$ROOT/plugins/aid-orchestrator/defaults/templates/run-new-feature.md" --epic "$epic" --output-dir "$run_dir" --run-id "$run_id" --generation-receipt "$receipt") >/dev/null
  (cd "$tmp" && bash "$SCRIPTS/aid-queue-add.sh" --epic-id "$epic_id" --epic-path "$epic" --priority medium --queue-yaml .aid-o/config/queue.yaml --plan-ref .aid-o/plans/P099.md) >/dev/null
done
[[ -f "$tmp/.aid-o/work/evidence/E-099-1_3/R-E099-1/fsm-state.yaml" && -f "$tmp/.aid-o/config/queue.yaml" ]]
[[ "$(grep -o 'E-099-[123]_3' "$tmp/.aid-o/config/queue.yaml" | sort -u | wc -l | tr -d ' ')" -eq 3 ]]
echo "PASS: receipt unlocks all FSM inits and queue entries"

jq '.[1].phase = 1' "$tmp/epics.json" > "$tmp/duplicate-phase.json"
if bash "$SCRIPTS/aid-generation-finalize.sh" --plan "$tmp/.aid-o/plans/P099.md" --total 3 --epics-json "$tmp/duplicate-phase.json" --output "$tmp/bad.json" >/dev/null 2>&1; then
  echo "FAIL: duplicate phase was accepted" >&2; exit 1
fi
echo "PASS: duplicate phase is rejected"

# Changing a generated EPIC after generation must not be silently sealed into
# a new receipt: its source-plan binding is independently re-derived.
tampered_epic="$(jq -r '.[0].epic_path' "$tmp/epics.json")"
sed -i 's/^source_step_ids: .*/source_step_ids: "999"/' "$tampered_epic"
if bash "$SCRIPTS/aid-generation-finalize.sh" --plan "$tmp/.aid-o/plans/P099.md" --total 3 --epics-json "$tmp/epics.json" --output "$tmp/tampered.json" >/dev/null 2>&1; then
  echo "FAIL: tampered EPIC source binding was accepted" >&2; exit 1
fi
echo "PASS: tampered EPIC source binding is rejected"
