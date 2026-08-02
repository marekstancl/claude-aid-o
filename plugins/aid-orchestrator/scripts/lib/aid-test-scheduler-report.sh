#!/usr/bin/env bash
# aid-test-scheduler-report.sh — P069 Step 8.
#
# Merges per-batch execution-unit receipts (Step 4's schema) into ONE row
# matching aid-run-gates.sh's REAL, verified per-gate shape (confirmed at
# aid-run-gates.sh:386,407,420,551): {gate, result, reason?, exit_code,
# duration_ms, output, attempts}. This is the single source of truth for
# scheduler-receipt -> gate-row translation — no other step reinterprets
# this mapping.
#
# result: "pass" only if EVERY expected unit_id resolves to a receipt with
# state:"terminal_pass". "fail" if any unit's state is terminal_fail/
# timed_out/cancelled, or if any expected unit_id has NO receipt at all
# (never silently dropped — the missing unit_id is named in `output` just
# like a real failure). A unit resolved to a non-terminal state (started/
# running/lost — the equivalent of aid-job.sh cmd_collect's exit code 3,
# covering BOTH its real in_flight/lost substates) is likewise "fail" — no
# evidence is never a pass.
#
# Units are sorted by stable unit_id before aggregation, so two runs with
# reordered batch completion produce a byte-identical row.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (same idiom as aid-test-adapter-bats.sh).

_STR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# scheduler_report_merge_gate_row <gate_name> <expected_unit_ids_json> <batches_json>
#   expected_unit_ids_json: JSON array of unit_id strings that SHOULD each
#     resolve to exactly one receipt.
#   batches_json: JSON array of Step 4 batch documents
#     ({batch_id, units[], started_at, ended_at}) — every batch this
#     scheduled gate dispatched across (normally one, but a gate-level
#     retry re-invoking the whole scheduled dispatch produces more than
#     one; ALL of them are merged into this single row).
#   Emits the merged gate row JSON object to stdout.
scheduler_report_merge_gate_row() {
  local gate_name="$1" expected_unit_ids_json="$2" batches_json="$3"

  # Flatten every batch's units[] into one receipts array, tagging each
  # receipt with its OWN batch's ended_at. Codex review, real finding: a
  # gate-level retry can dispatch the SAME unit_id across multiple batches
  # (attempt1 fails, attempt2 re-runs it) — a naive `sort_by(.unit_id) |
  # map({...}) | add` collapse picks whichever duplicate happens to sort
  # LAST in the CALLER-SUPPLIED batches_json array order, which is exactly
  # the reordering this function claims to be immune to (verified: reversing
  # two batches with conflicting duplicate-unit_id receipts flipped the
  # verdict). Selection is now keyed on each receipt's OWN batch ended_at
  # (the most RECENT attempt for a unit_id wins — the real retry semantics:
  # a later attempt's outcome supersedes an earlier one), with job_id as a
  # final, fully deterministic tiebreak — never on array/caller order.
  local receipts_json
  receipts_json="$(jq -cS '
    [ .[] as $b | $b.units[] | . + {_batch_ended_at: $b.ended_at} ]
    | group_by(.unit_id)
    | map(sort_by([.["_batch_ended_at"], .job_id]) | last | del(._batch_ended_at))
    | sort_by(.unit_id)
  ' <<<"$batches_json")"

  # Wall-clock span: earliest batch start to latest batch end, across every
  # batch this gate's scheduled dispatch touched.
  local started_at ended_at
  started_at="$(jq -r '[.[].started_at] | sort | .[0]' <<<"$batches_json")"
  ended_at="$(jq -r '[.[].ended_at] | sort | .[-1]' <<<"$batches_json")"
  local duration_ms=0
  if [[ -n "$started_at" && "$started_at" != "null" && -n "$ended_at" && "$ended_at" != "null" ]]; then
    local start_epoch end_epoch
    start_epoch="$(date -u -d "$started_at" +%s 2>/dev/null || echo 0)"
    end_epoch="$(date -u -d "$ended_at" +%s 2>/dev/null || echo 0)"
    duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
    [[ "$duration_ms" -ge 0 ]] || duration_ms=0
  fi

  # Per-expected-unit classification: missing entirely, or resolved to a
  # terminal_pass/anything-else state. Missing and non-terminal are BOTH
  # "fail" — never silently excluded, never treated as pass.
  local classified_json
  classified_json="$(jq -cS --argjson expected "$expected_unit_ids_json" \
    '. as $receipts
     | ($receipts | map({(.unit_id): .state}) | add // {}) as $by_id
     | [ $expected[] as $u
         | { unit_id: $u,
             ok: (($by_id[$u] // null) == "terminal_pass"),
             missing: ($by_id[$u] == null) }
       ]' <<<"$receipts_json")"

  local all_ok; all_ok="$(jq 'all(.[]; .ok)' <<<"$classified_json")"
  local result exit_code
  if [[ "$all_ok" == "true" ]]; then
    result="pass"; exit_code=0
  else
    result="fail"; exit_code=1
  fi

  local output=""
  if [[ "$result" == "fail" ]]; then
    output="$(jq -r '
      [.[] | select(.ok | not) | (if .missing then .unit_id + " (no receipt)" else .unit_id end)]
      | sort | "units causing fail: " + join(", ")
    ' <<<"$classified_json")"
  fi

  jq -nc \
    --arg gate "$gate_name" --arg result "$result" --argjson exit_code "$exit_code" \
    --argjson duration_ms "$duration_ms" --arg output "$output" \
    '{gate:$gate, result:$result, exit_code:$exit_code, duration_ms:$duration_ms, output:$output, attempts:1}'
}
