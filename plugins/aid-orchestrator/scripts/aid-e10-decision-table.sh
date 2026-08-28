#!/usr/bin/env bash
# aid-e10-decision-table.sh — one decision per control, from evidence (P062 Step 10, D8).
#
# Usage:
#   aid-e10-decision-table.sh --metrics <control-metrics.json>
#                             --dual-run <dual-run-report.json>
#                             [--preflight <e10-preflight.json>]
#                             [--imp201 <imp201-decision.json>]
#                             [--budget <merge-path-budget.json>]
#                             [--out <file>]
#
# Exit: 0 = table written; 2 = usage/environment error.
#
# ONE APPROVAL, ONE CONTROL
#   A row here names a control (c0..c4). The control inventory may hold several
#   promotable ROWS for one control — c4 has both the release decision and the
#   content verdict — and promoting all of them on one approval is broader than
#   "only the approved controls were promoted" (cross-model review,
#   2026-08-15). A row may therefore carry `inventory_ids` to name exactly which
#   rows it approves; the promotion step REFUSES an ambiguous control that names
#   none.
#
# THE SIX OUTCOMES, and why the sixth exists:
#   promote_to_blocking | keep_observe | keep_dual_run | defer |
#   remove_or_alias_in_E11_candidate | cannot_promote_runtime_budget
#
#   The sixth is not `defer`. `defer` means the data is missing; this one means
#   the data is there and the control would qualify, but the merge path is over
#   its budget and nothing may be added to it until that is decided. Collapsing
#   them would hide a project-level decision inside a per-control one.
#
# WHAT THIS FILE REFUSES TO DO
#   It never promotes on an absence. null in the metrics means "not measured",
#   and a control with nulls is deferred, never promoted for having no recorded
#   false positives. That inversion — no evidence read as good evidence — is the
#   single failure this table exists to prevent.
set -euo pipefail

METRICS=""; DUALRUN=""; PREFLIGHT=""; IMP201=""; BUDGET=""; OUT_FILE=""; INVENTORY=""
_DT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --metrics)   [[ $# -ge 2 ]] || { echo "--metrics needs a path" >&2; exit 2; };   METRICS="$2";   shift 2 ;;
    --dual-run)  [[ $# -ge 2 ]] || { echo "--dual-run needs a path" >&2; exit 2; };  DUALRUN="$2";   shift 2 ;;
    --preflight) [[ $# -ge 2 ]] || { echo "--preflight needs a path" >&2; exit 2; }; PREFLIGHT="$2"; shift 2 ;;
    --imp201)    [[ $# -ge 2 ]] || { echo "--imp201 needs a path" >&2; exit 2; };    IMP201="$2";    shift 2 ;;
    --budget)    [[ $# -ge 2 ]] || { echo "--budget needs a path" >&2; exit 2; };    BUDGET="$2";    shift 2 ;;
    --inventory) [[ $# -ge 2 ]] || { echo "--inventory needs a path" >&2; exit 2; }; INVENTORY="$2"; shift 2 ;;
    --out)       [[ $# -ge 2 ]] || { echo "--out needs a path" >&2; exit 2; };       OUT_FILE="$2";  shift 2 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
for f in "$METRICS" "$DUALRUN"; do
  [[ -n "$f" && -f "$f" ]] || { echo "ERROR: --metrics and --dual-run are required and must exist" >&2; exit 2; }
done
jq -e '.controls' "$METRICS" >/dev/null 2>&1 || { echo "ERROR: ${METRICS} carries no .controls" >&2; exit 2; }
jq -e '.pairs'    "$DUALRUN" >/dev/null 2>&1 || { echo "ERROR: ${DUALRUN} carries no .pairs" >&2; exit 2; }
OUT_FILE="${OUT_FILE:-.aid-o/work/evidence/P062/e10/e10-decision-table.json}"
INVENTORY="${INVENTORY:-${_DT_SCRIPT_DIR}/../defaults/policies/control-inventory.yaml}"
[[ -f "$INVENTORY" ]] || { echo "ERROR: control inventory not found: ${INVENTORY}" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required — the control inventory is YAML" >&2; exit 2; }
_inv_json="$(yq -o=json '.' "$INVENTORY" 2>/dev/null)" || { echo "ERROR: cannot parse ${INVENTORY}" >&2; exit 2; }

# ── the gates that constrain EVERY row, read once ───────────────────────────
#
# A missing gate artefact is NOT a satisfied gate. `unknown` propagates into
# the decision as a reason to defer, never as permission.
_pf="unknown"
[[ -n "$PREFLIGHT" && -f "$PREFLIGHT" ]] && _pf="$(jq -r '.verdict // "unknown"' "$PREFLIGHT" 2>/dev/null || echo unknown)"
_imp201="unknown"
[[ -n "$IMP201" && -f "$IMP201" ]] && _imp201="$(jq -r '.decision // "unknown"' "$IMP201" 2>/dev/null || echo unknown)"
_budget="undecided"
[[ -n "$BUDGET" && -f "$BUDGET" ]] && _budget="$(jq -r '.decision // "undecided"' "$BUDGET" 2>/dev/null || echo undecided)"

# ── IMP-179: which controls rest on subagent output ─────────────────────────
# Named explicitly rather than pattern-matched, because being wrong here means
# promoting a control whose inputs may have come from a stale plugin cache.
_subagent_controls='["c2","c3"]' 

table="$(jq -n \
  --slurpfile m "$METRICS" \
  --slurpfile d "$DUALRUN" \
  --arg pf "$_pf" --arg imp201 "$_imp201" --arg budget "$_budget" \
  --argjson inv "$_inv_json" \
  --argjson subagent "$_subagent_controls" '
  ($m[0]) as $met | ($d[0]) as $dual
  | ($met.c3_verdict_mix // {}) as $mix
  | [ $dual.legacy_unique_catch // [] ] | flatten as $luc
  | {
      generated_by: "aid-e10-decision-table.sh",
      schema_version: "aid-2.0",
      artifact_type: "e10_decision_table",
      gates: {preflight: $pf, imp201: $imp201, merge_path_budget: $budget},
      c3_verdict_mix: $mix,
      controls: [ $inv.controls[] as $row
        | ($row.control) as $id
        | (([$met.controls[] | select(.control == $id)] | first) // {control: $id}) as $c
        | ([$dual.pairs[]? | select(.expected_catcher == $id)]) as $pairs
        | ([$pairs[] | select(.divergence == "legacy_unique_catch")] | length) as $n_luc
        | (($c.false_done == null) or ($c.false_positives == null)
           or ($c.unique_detection_vs_legacy == null)) as $unmeasured
        | (($mix.unverifiable // 0) > (($mix.pass // 0) + ($mix.fail // 0))) as $c3_mostly_unverifiable
        | {
            control: $id,
            inventory_id: $row.id,
            promotable: ($row.promotable // false),
            evidence_refs: ($c.evidence_refs // []),
            caught_classes: ($c.caught_classes // []),
            false_done: $c.false_done,
            false_positives: $c.false_positives,
            cost_seconds: $c.cost_seconds,
            unique_detection_vs_legacy: $c.unique_detection_vs_legacy,
            decision:
              # PRECEDENCE. Every branch above `promote_to_blocking` is a reason
              # NOT to promote, and they are asked first on purpose.
              # A row that can NEVER be promoted says so before it says "no
              # data": "insufficient data" invites someone to go measure, and
              # for these rows measuring changes nothing (final audit ordering
              # fix, 2026-08-15).
              (if $n_luc > 0 then "keep_dual_run"
               elif ($row.promotable // false) == false then "keep_observe"
               elif $row.id == "c4_evidence_pack_freshness" and $imp201 != "fixed" then "keep_observe"
               elif $unmeasured then "defer"
               elif $id == "c3" and $c3_mostly_unverifiable then "keep_observe"
               elif $pf != "clean" and $pf != "excluded_by_pm" then "defer"
               elif $budget != "budget_raised" and $budget != "path_reduced" and $budget != "exception_recorded"
                    then "cannot_promote_runtime_budget"
               elif ($subagent | index($id)) != null then "keep_observe"
               elif ($c.unique_detection_vs_legacy // 0) == 0 and (($c.caught_classes // []) | length) == 0
                    then "remove_or_alias_in_E11_candidate"
               else "promote_to_blocking" end),
            reason:
              (if $n_luc > 0 then "legacy caught what this control did not (\($n_luc) fixture(s)); D8 forbids marking it for removal and it is not yet safe to promote"
               elif ($row.promotable // false) == false then ($row.not_promotable_reason // "the control inventory marks this row not promotable")
               elif $row.id == "c4_evidence_pack_freshness" and $imp201 != "fixed" then "IMP-201 is \($imp201): C4 freshness cannot block the trailing-commit class"
               elif $unmeasured then "insufficient data: at least one of false_done / false_positives / unique_detection_vs_legacy was not measured"
               elif $id == "c3" and $c3_mostly_unverifiable then "C3 returned unverifiable more often than it reached a verdict (\($mix.unverifiable // 0) vs \(($mix.pass // 0) + ($mix.fail // 0))); a dataset of shrugs is not evidence that it catches defects"
               elif $pf != "clean" and $pf != "excluded_by_pm" then "the bookkeeping preflight is \($pf); calibration over a layer nobody could read proves nothing"
               elif $budget != "budget_raised" and $budget != "path_reduced" and $budget != "exception_recorded"
                    then "the merge path is over budget and the decision is \($budget); nothing may be added to it until that is settled"
               elif ($subagent | index($id)) != null then "rests on subagent output while IMP-179 is open"
               elif ($c.unique_detection_vs_legacy // 0) == 0 and (($c.caught_classes // []) | length) == 0
                    then "caught nothing the legacy stack did not; a removal CANDIDATE, decided in E11"
               else "measured, gated and clear" end)
          } ],
      legacy_unique_catch: $luc
    }')" || { echo "ERROR: could not build the decision table" >&2; exit 2; }

mkdir -p "$(dirname "$OUT_FILE")"
printf '%s\n' "$table" | jq '.' > "$OUT_FILE"

# The human twin. Same data, rendered — never re-derived.
md="${OUT_FILE%.json}.md"
{
  echo "# E10 decision table"
  echo
  echo "Gates: preflight=$(jq -r '.gates.preflight' "$OUT_FILE"), IMP-201=$(jq -r '.gates.imp201' "$OUT_FILE"), merge-path budget=$(jq -r '.gates.merge_path_budget' "$OUT_FILE")."
  echo
  echo "| Control row | Control | Decision | Why |"
  echo "|---|---|---|---|"
  jq -r '.controls[] | "| \(.inventory_id) | \(.control) | \(.decision) | \(.reason) |"' "$OUT_FILE"
} > "$md"

echo "aid-e10-decision-table: $(jq -r '.controls | length' "$OUT_FILE") control(s) → ${OUT_FILE}"
jq -r '.controls[] | "  \(.inventory_id) (\(.control)): \(.decision)"' "$OUT_FILE"
