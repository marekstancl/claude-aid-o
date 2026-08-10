#!/usr/bin/env bash
# aid-run-gates-report.sh — P069 Step 14.
#
# merge_escalation_report <targeted_report_json> <full_report_json> <reason>
#   Merges a targeted_tests-triggered escalation's two SEPARATE, complete
#   run_all_gates() passes into ONE final report — never a hybrid of two
#   passes' rows sharing one gate namespace (the existing `processed ==
#   gate_count` integrity assert must always apply to exactly one real,
#   complete profile run's rows at a time).
#
#   The FULL pass's report becomes the actual, verdict-bearing result
#   verbatim (its own gates/overall/processed/gate_count bookkeeping is
#   internally self-consistent because it is one complete, uncontaminated
#   run_all_gates() invocation) — a SEPARATE, additive top-level
#   `escalation` key is added on top, nesting the original targeted
#   attempt's own complete report as `targeted_run` purely for PM/audit
#   visibility. Nothing from the targeted pass's rows is ever merged
#   row-by-row into the full pass's `gates` object.
#
# Args:
#   $1 targeted_report_json — the complete gates_report.json-shaped object
#      from the original (targeted-profile) run_all_gates() pass
#   $2 full_report_json     — the complete gates_report.json-shaped object
#      from the escalation's separate --profile full run_all_gates() pass
#   $3 reason               — human-readable string naming the exit code +
#      triggering path (e.g. "exit_code 11: mapping_gap at scripts/foo.sh")
#
# Emits the merged report JSON to stdout.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (same idiom as aid-test-adapter-bats.sh).

merge_escalation_report() {
  local targeted_report_json="$1" full_report_json="$2" reason="$3"
  jq -nc \
    --argjson full "$full_report_json" \
    --argjson targeted "$targeted_report_json" \
    --arg reason "$reason" \
    '$full + {escalation: {triggered_by: "targeted_tests", reason: $reason, targeted_run: $targeted}}'
}
