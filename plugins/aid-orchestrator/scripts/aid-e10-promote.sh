#!/usr/bin/env bash
# aid-e10-promote.sh — flip approved controls to blocking (P062 Step 11).
#
# Usage:
#   aid-e10-promote.sh --decision-table <e10-decision-table.json>
#                      [--preflight <e10-preflight.json>]
#                      [--imp201 <imp201-decision.json>]
#                      [--inventory <control-inventory.yaml>]
#                      [--policy-dir <dir>] [--apply]
#
# Without --apply this is a DRY RUN: it prints what it would do and changes
# nothing. That is the default on purpose — the last step of a calibration plan
# should not be the easiest thing in it to trigger by accident.
#
# Exit: 0 = the run completed (dry or applied); 1 = a gate refused the
#       promotion; 2 = usage/environment error.
#
# WHAT IT REFUSES, AND WHY EACH REFUSAL IS SEPARATE
#   * the bookkeeping preflight is not `clean`/`excluded_by_pm` — including
#     `unproven`, which means nobody could read the layer at all;
#   * a control the inventory says is not promotable;
#   * a control whose decision is anything other than promote_to_blocking;
#   * C4 freshness while IMP-201 is not `fixed`.
#   They are asked one at a time so the refusal names its own cause. A single
#   "not ready" would send the reader looking.
set -euo pipefail

TABLE=""; PREFLIGHT=""; IMP201=""; INVENTORY=""; POLICY_DIR=""; APPLY=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --decision-table) [[ $# -ge 2 ]] || { echo "--decision-table needs a path" >&2; exit 2; }; TABLE="$2"; shift 2 ;;
    --preflight)      [[ $# -ge 2 ]] || { echo "--preflight needs a path" >&2; exit 2; }; PREFLIGHT="$2"; shift 2 ;;
    --imp201)         [[ $# -ge 2 ]] || { echo "--imp201 needs a path" >&2; exit 2; }; IMP201="$2"; shift 2 ;;
    --inventory)      [[ $# -ge 2 ]] || { echo "--inventory needs a path" >&2; exit 2; }; INVENTORY="$2"; shift 2 ;;
    --policy-dir)     [[ $# -ge 2 ]] || { echo "--policy-dir needs a path" >&2; exit 2; }; POLICY_DIR="$2"; shift 2 ;;
    --apply)          APPLY=1; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required" >&2; exit 2; }
[[ -n "$TABLE" && -f "$TABLE" ]] || { echo "ERROR: --decision-table is required and must exist" >&2; exit 2; }
jq -e '.controls' "$TABLE" >/dev/null 2>&1 || { echo "ERROR: ${TABLE} carries no .controls" >&2; exit 2; }

INVENTORY="${INVENTORY:-${SCRIPT_DIR}/../defaults/policies/control-inventory.yaml}"
POLICY_DIR="${POLICY_DIR:-${SCRIPT_DIR}/../defaults/policies}"
[[ -f "$INVENTORY" ]] || { echo "ERROR: control inventory not found: ${INVENTORY}" >&2; exit 2; }

# shellcheck source=lib/aid-control-enforcement.sh
source "${SCRIPT_DIR}/lib/aid-control-enforcement.sh"

rc=0

# ── gate 1: the bookkeeping preflight ───────────────────────────────────────
pf="unknown"
[[ -n "$PREFLIGHT" && -f "$PREFLIGHT" ]] && pf="$(jq -r '.verdict // "unknown"' "$PREFLIGHT" 2>/dev/null || echo unknown)"
if [[ "$pf" != "clean" && "$pf" != "excluded_by_pm" ]]; then
  echo "REFUSED: the bookkeeping preflight is '${pf}' — calibration over a layer nobody could read proves nothing." >&2
  [[ "$pf" == "unproven" ]] && echo "  'unproven' means the checks could not RUN. It is not a clean result." >&2
  [[ "$pf" == "unknown"  ]] && echo "  No preflight artefact was supplied. A missing gate is not a satisfied gate." >&2
  echo "  Nothing was promoted." >&2
  exit 1
fi

imp201="unknown"
[[ -n "$IMP201" && -f "$IMP201" ]] && imp201="$(jq -r '.decision // "unknown"' "$IMP201" 2>/dev/null || echo unknown)"

# ── per control ─────────────────────────────────────────────────────────────
promoted=0; refused=0
while IFS=$'\t' read -r ctl decision; do
  [[ -n "$ctl" ]] || continue

  # Map the decision-table control (c0..c4) onto the inventory rows that
  # implement it. A control with no inventory row is refused, not guessed at.
  mapfile -t rows < <(yq -r ".controls[] | select(.control == \"${ctl}\") | .id" "$INVENTORY" 2>/dev/null)
  if (( ${#rows[@]} == 0 )); then
    echo "refused  ${ctl}: no row in the control inventory — the inventory is the authority on what exists" >&2
    refused=$(( refused + 1 )); rc=1; continue
  fi

  for id in "${rows[@]}"; do
    [[ -n "$id" ]] || continue
    if [[ "$decision" != "promote_to_blocking" ]]; then
      echo "skipped  ${id}: decision is '${decision}'"
      continue
    fi
    if ! aid_control_promotable "$INVENTORY" "$id"; then
      reason="$(yq -r ".controls[] | select(.id == \"${id}\") | .not_promotable_reason // \"not promotable\"" "$INVENTORY" 2>/dev/null | tr '\n' ' ')"
      echo "refused  ${id}: ${reason}" >&2
      refused=$(( refused + 1 )); rc=1; continue
    fi
    if [[ "$id" == "c4_evidence_pack_freshness" && "$imp201" != "fixed" ]]; then
      echo "refused  ${id}: IMP-201 is '${imp201}'" >&2
      refused=$(( refused + 1 )); rc=1; continue
    fi

    pf_rel="$(yq -r ".controls[] | select(.id == \"${id}\") | .policy_file" "$INVENTORY" 2>/dev/null)"
    key="$(yq -r ".controls[] | select(.id == \"${id}\") | .policy_key // \"enforcement\"" "$INVENTORY" 2>/dev/null)"
    if [[ -z "$pf_rel" || "$pf_rel" == "null" ]]; then
      echo "refused  ${id}: no policy file — it cannot be promoted through the per-control maps" >&2
      refused=$(( refused + 1 )); rc=1; continue
    fi
    pf_path="${POLICY_DIR}/$(basename "$pf_rel")"
    [[ -f "$pf_path" ]] || { echo "refused  ${id}: policy file not found at ${pf_path}" >&2; refused=$(( refused + 1 )); rc=1; continue; }

    if (( APPLY == 1 )); then
      yq -i ".controls.\"${id}\".enforcement = \"blocking\"" "$pf_path"
      echo "promoted ${id}: ${key} -> blocking in $(basename "$pf_path")"
    else
      echo "would promote ${id}: ${key} -> blocking in $(basename "$pf_path")  [dry run]"
    fi
    promoted=$(( promoted + 1 ))
  done
done < <(jq -r '.controls[] | [.control, .decision] | @tsv' "$TABLE")

echo "aid-e10-promote: ${promoted} promotion(s)$( (( APPLY == 0 )) && printf ' (dry run — nothing changed)'), ${refused} refusal(s)"
exit "$rc"
