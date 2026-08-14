#!/usr/bin/env bash
# dg07-state-consistency.sh — FSM state consistency delivery check
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: (none — reads from env)
# Env:
#   AID_PROJECT_ROOT — project root directory
#   AID_EPIC_ID      — EPIC ID (e.g. E-050-1_1)
#   AID_RUN_ID       — Run ID (e.g. R-E050-1)
#
# Rule: parent DONE/release with non-complete child step OR open pending
#       dispatch counter OR compliance.json overall:fail → status: fail
#
# DG-07 EXTENDS (does not duplicate) evaluate_compliance_checks(). It reads
# the same state files but adds only the delivery-specific rule not already
# covered by the existing compliance block in cmd_done_advance.

set -uo pipefail

# ---------------------------------------------------------------------------
# Guard: required env vars
# ---------------------------------------------------------------------------
if [[ -z "${AID_EPIC_ID:-}" || -z "${AID_RUN_ID:-}" ]]; then
  echo "dg07: unverifiable — AID_EPIC_ID or AID_RUN_ID not set" >&2
  exit 2
fi

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
EVIDENCE_DIR="${ROOT}/.aid-o/work/evidence/${AID_EPIC_ID}/${AID_RUN_ID}"
STATE_FILE="${EVIDENCE_DIR}/fsm-state.yaml"

# The step counter this check prints is the 0-BASED `current_step`, and every
# line below reported it raw — `step=2/3` for a run with one step left. The
# wording that disambiguates it is defined once, in lib/aid-human-step.sh; this
# check renders through that function rather than restating it. The machine
# values keep their exact position and format, so greps on these lines still
# match; the suffix is appended after them.
# shellcheck source=../aid-human-step.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/aid-human-step.sh"

echo "dg07: checking state consistency for ${AID_EPIC_ID}/${AID_RUN_ID}"

# ---------------------------------------------------------------------------
# Guard: state file must exist
# ---------------------------------------------------------------------------
if [[ ! -f "$STATE_FILE" ]]; then
  echo "dg07: unverifiable — fsm-state.yaml not found: ${STATE_FILE}" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Read FSM state fields (pure bash — no eval, no jq dependency for yaml)
# ---------------------------------------------------------------------------
yaml_field_local() {
  local file="$1" key="$2" line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    if [[ "$line" == "${key}:"* ]]; then
      line="${line#"${key}:"}"
      line="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
      line="${line%%[[:space:]]*}"               # strip trailing whitespace
      # Strip surrounding YAML quotes
      if [[ ${#line} -ge 2 && "${line:0:1}" == '"' && "${line: -1}" == '"' ]]; then
        line="${line:1:${#line}-2}"
      elif [[ ${#line} -ge 2 && "${line:0:1}" == "'" && "${line: -1}" == "'" ]]; then
        line="${line:1:${#line}-2}"
      fi
      printf '%s\n' "$line"
      return 0
    fi
  done < "$file"
  return 0
}

current_state=$(yaml_field_local "$STATE_FILE" state)
current_step=$(yaml_field_local  "$STATE_FILE" current_step)
total_steps=$(yaml_field_local   "$STATE_FILE" total_steps)
done_phase=$(yaml_field_local    "$STATE_FILE" done_phase)

echo "dg07: state=${current_state} done_phase=${done_phase:-<none>} step=${current_step:-?}/${total_steps:-?}$(_fsm_human_step "${current_step:-}" "${total_steps:-}")"

FAIL=0
FAIL_REASONS=()

# ---------------------------------------------------------------------------
# Check 1: parent DONE/release with non-complete child step
# ---------------------------------------------------------------------------
# Only meaningful when the FSM is transitioning into release (done_phase=review
# at the point done-advance review release is called — but the delivery gate
# runs from aid-delivery-gate.sh before the write, so done_phase may still be
# review here). We check the step counter regardless: if current_step < total_steps
# the EPIC has incomplete work.
if [[ -n "${current_step}" && -n "${total_steps}" ]]; then
  if [[ "$current_step" =~ ^[0-9]+$ && "$total_steps" =~ ^[0-9]+$ ]]; then
    if [[ "$current_step" -lt "$total_steps" ]]; then
      FAIL=1
      FAIL_REASONS+=("parent DONE/release with non-complete child step (step=${current_step} total=${total_steps})")
      echo "dg07: FAIL — parent DONE/release with non-complete child step (step=${current_step} total=${total_steps})$(_fsm_human_step "$current_step" "$total_steps")"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Check 2: compliance.json overall = fail
# ---------------------------------------------------------------------------
COMPLIANCE_FILE="${EVIDENCE_DIR}/compliance.json"
if [[ -f "$COMPLIANCE_FILE" ]]; then
  if command -v jq >/dev/null 2>&1; then
    overall=$(jq -r '.overall // empty' "$COMPLIANCE_FILE" 2>/dev/null || echo "")
    # compliance.json overall is bool (true/false) or string "pass"/"fail"
    if [[ "$overall" == "fail" || "$overall" == "false" ]]; then
      FAIL=1
      FAIL_REASONS+=("compliance.json overall=${overall} (delivery gate cannot proceed)")
      echo "dg07: FAIL — compliance.json overall=${overall} (delivery gate cannot proceed)"
    fi
  fi
  # jq not available: skip this check (fail-open — missing jq is not our fault)
fi

# ---------------------------------------------------------------------------
# Check 3: open pending dispatches (conservative: existence + non-empty)
# ---------------------------------------------------------------------------
PENDING_FILE="${EVIDENCE_DIR}/pending-dispatches.jsonl"
if [[ -f "$PENDING_FILE" && -s "$PENDING_FILE" ]]; then
  # Count start events that have no matching complete event.
  # Fail-safe: if jq is absent, skip this check.
  if command -v jq >/dev/null 2>&1; then
    open_count=0
    open_count=$(jq -s '
      [.[] | select(.event == "start") | .focus] as $starts |
      [.[] | select(.event == "complete") | .focus] as $completes |
      [$starts[] | select(. as $f | $completes | index($f) | not)] | length
    ' "$PENDING_FILE" 2>/dev/null || echo "0")
    if [[ "$open_count" =~ ^[0-9]+$ && "$open_count" -gt 0 ]]; then
      FAIL=1
      FAIL_REASONS+=("open pending dispatches (count=${open_count})")
      echo "dg07: FAIL — open pending dispatches (count=${open_count})"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [[ "$FAIL" -eq 0 ]]; then
  echo "dg07: pass — state consistent (step=${current_step:-?}/${total_steps:-?}$(_fsm_human_step "${current_step:-}" "${total_steps:-}"), compliance=pass, no open pending dispatches)"
  exit 0
else
  reason_csv=$(printf '%s; ' "${FAIL_REASONS[@]}")
  reason_csv="${reason_csv%; }"
  echo "dg07: fail — ${reason_csv}" >&2
  exit 1
fi
