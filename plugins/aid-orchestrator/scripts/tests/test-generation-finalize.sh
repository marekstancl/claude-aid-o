#!/usr/bin/env bash
# aid-tier: t2
set -euo pipefail

# ─── P072 Step 9: canonical result line for the aggregate collector ─────────
#
# This suite is exit-code driven: it has no per-case counters, so it reports at
# SUITE granularity — 1/1 on success, 0/1 on failure. That is honest about what
# it knows, and it is the difference between "this suite passed" and the `0/0`
# the collector used to record, which was indistinguishable from a suite that
# crashed before running anything.
#
# Emitted from the EXIT trap so every exit path is covered. Where the suite
# already has an EXIT trap for cleanup, this COMPOSES with it — a shell has
# exactly one EXIT trap, and installing a second silently discards the first,
# which would leak every temp directory these suites create.
_p072_emit_results() {
  # errexit OFF for the duration: a failing `echo` (closed stdout, full disk)
  # would otherwise abort the trap before the cleanup that follows it.
  # Reporting is best-effort; cleanup is not optional.
  set +e
  local rc="${1:-$?}"
  if [[ "$rc" -eq 0 ]]; then
    echo "Results: 1/1 passed, 0 failed"
  else
    echo "Results: 0/1 passed, 1 failed"
  fi
  return 0
}


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SCRIPTS="$ROOT/plugins/aid-orchestrator/scripts"
PLAN="$SCRIPTS/tests/fixtures/multi-phase-plan-numeric.md"
tmp="$(mktemp -d)"; trap '_p072_rc=$?; _p072_emit_results "$_p072_rc"; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.aid-o/plans" "$tmp/.aid-o/tasks" "$tmp/.aid-o/config" "$tmp/.aid-o/work/evidence/P099/generation"
cp "$PLAN" "$tmp/.aid-o/plans/P099.md"
# Make the E2E path exercise the actual strict receipt consumer, not only the
# legacy-compatible path. The plan is still low risk; strictness is explicit.
sed -i '/^author:/a lifecycle_strict: true' "$tmp/.aid-o/plans/P099.md"
# A strict plan owes every step the three fields aid-plan-lint.sh demands
# (since 2026-08-22); the shared fixture is a legacy plan without them.
sed -i '/^### Step [0-9]/a\
\
**Architecture Context:** fixture step.\
**Error Handling:** none, fixture step.\
**Edge Cases:** none, fixture step.' "$tmp/.aid-o/plans/P099.md"
# Also exercise a legitimate phase-local edge (Step 1 -> Step 2), not only an
# empty dependency graph. The finalizer must translate the global source edge
# to the generated local step IDs and still accept the package.
sed -i '/^\*\*AID Role:\*\* domain$/a\
\
**Dependencies:**\
- Depends on: Step 1 (architect contracts)' "$tmp/.aid-o/plans/P099.md"
printf 'counter: 0\n' > "$tmp/.aid-o/config/counter.yaml"
# Generation is gated on the plan review and the PM page; this suite proves the
# finalizer, so the review is switched off and the page rendered.
mkdir -p "$tmp/.aid-o/config/policies"
printf 'review_checkpoints:\n  cp1_plan_review: false\n' > "$tmp/.aid-o/config/policies/review-checkpoints.yaml"
git -C "$tmp" init -q
git -C "$tmp" config user.email aid-test@example.com
git -C "$tmp" config user.name "AID Test"
git -C "$tmp" checkout -q -b main
# The files the fixture plan modifies exist, as aid-plan-check (A7) requires.
mkdir -p "$tmp/src/api" "$tmp/src/frontend" "$tmp/docs"
touch "$tmp/src/api/__init__.py" "$tmp/src/frontend/App.tsx" "$tmp/CHANGELOG.md" "$tmp/docs/api-reference.md"
git -C "$tmp" add src docs CHANGELOG.md
git -C "$tmp" commit -qm "seed"

(cd "$tmp" && source "$SCRIPTS/lib/aid-plan-summary.sh" \
  && aid_plan_summary_render "$tmp/.aid-o/plans/P099.md" "$tmp/.aid-o/work/evidence/P099/plan-summary-artifact.html") >/dev/null
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

# A phase marked delivered is re-proven by git (P100 Step 5): the manifest's word
# alone is refused. The proven case runs end to end in test-generation-resume.bats.
jq '.[0] = {phase: 1, epic_id: .[0].epic_id, status: "delivered", proven_by: "git", queue_status: "merged_to_plan", depends_on: []}' "$tmp/epics.json" > "$tmp/delivered.json"
if (cd "$tmp" && bash "$SCRIPTS/aid-generation-finalize.sh" --plan "$tmp/.aid-o/plans/P099.md" --total 3 --epics-json "$tmp/delivered.json" --output "$tmp/.aid-o/work/evidence/P099/generation/delivered-receipt.json") >/dev/null 2>&1; then
  echo "FAIL: a delivered phase git does not prove was accepted" >&2; exit 1
fi
echo "PASS: a delivered phase git does not prove is refused"

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

# A receipt is not merely a phase-count receipt: removing or inventing a
# phase-local dependency must disagree with the source-plan graph.
tampered_json="$(jq -r '.[0].plan_json' "$tmp/epics.json")"
jq '.dependencies += [{before:.steps[0].id, after:.steps[1].id, reason:"tampered"}]' "$tampered_json" > "$tmp/tampered-plan.json"
mv "$tmp/tampered-plan.json" "$tampered_json"
if bash "$SCRIPTS/aid-generation-finalize.sh" --plan "$tmp/.aid-o/plans/P099.md" --total 3 --epics-json "$tmp/epics.json" --output "$tmp/tampered-deps.json" >/dev/null 2>&1; then
  echo "FAIL: tampered plan.json dependencies were accepted" >&2; exit 1
fi
echo "PASS: tampered plan.json dependencies are rejected"
