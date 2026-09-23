#!/usr/bin/env bash
# aid-run-gates-report.sh — merging two gate passes into one report.
#
# WHY THIS FILE EXISTS: when the `targeted_tests` gate cannot vouch for the
# selection it made (exit 3 or 11), the runner executes a second, complete
# `--profile full` pass. Two complete passes must become ONE gates_report.json
# without ever mixing their rows under one gate namespace (the runner's
# `processed == gate_count` integrity assert must always apply to exactly
# one complete pass). This file holds that one merge rule, so the runner and
# any reader agree on the shape: the full pass verbatim, plus a top-level
# `escalation` key carrying the targeted pass for audit.
#
# merge_escalation_report <targeted_report_json> <full_report_json> <reason>
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
# P097 Step 2: both passes' rows go through the one row contract
# (lib/aid-gate-row.sh, gate_rows_normalize) so the merged report never carries
# a version-1 row whichever runner produced either pass.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (same idiom as aid-test-adapter-bats.sh).

# shellcheck source=aid-gate-row.sh
[[ -n "${AID_GATE_ROW_JQ:-}" ]] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aid-gate-row.sh"

merge_escalation_report() {
  local targeted_report_json="$1" full_report_json="$2" reason="$3"
  jq -nc \
    --argjson full "$full_report_json" \
    --argjson targeted "$targeted_report_json" \
    --arg reason "$reason" \
    "${AID_GATE_ROW_JQ}"'
    def rows: if (.gates|type) == "object" then .gates |= gate_rows_normalize else . end;
    ($full | rows) + {escalation: {triggered_by: "targeted_tests", reason: $reason, targeted_run: ($targeted | rows)}}'
}
