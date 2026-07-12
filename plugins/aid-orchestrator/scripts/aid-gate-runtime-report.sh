#!/usr/bin/env bash
# aid-gate-runtime-report.sh — human-facing CLI over the gate runtime baseline
# library (P063 "Gate Runtime Baselines" EPIC, Step 4/4).
#
# WHY: Steps 1-3 make the baseline data exist (library), keep it flowing
# (aid-run-gates.sh + gitignore backfill), and enforce a policy on it (the
# repeated-timeout GATES:EXECUTE precondition) — but none of that lets a
# human just LOOK at "what does bats_all actually take, and what would the
# library recommend?" without hand-crafting a yq/jq one-liner against
# .aid-o/metrics/gate-runtime-baselines.yaml. This script is a thin
# presentation layer only: it never re-derives percentile or formatting
# logic — every number/recommendation it prints comes straight out of
# Step 1's public functions (gate_baseline_show / gate_baseline_report_json).
#
# Usage:
#   aid-gate-runtime-report.sh [--project-root <path>] [gate_name]
#
#   --project-root <path>   project root containing .aid-o/ (default: cwd).
#                            Parsed + cd'd into using the exact idiom
#                            aid-plan-close-check.sh uses (resolve, then a
#                            single explicit `cd`) so every relative path
#                            this script (and the library it sources) touches
#                            resolves against that root, never the caller's
#                            original cwd.
#   [gate_name]              optional. Given: prints that one gate's summary.
#                            Omitted: lists every gate that has at least one
#                            recorded sample.
#
# Exit codes:
#   0   success — includes the "no data yet" cases (a gate/project simply
#       hasn't run any gates yet is not an error condition).
#   1   usage error, or --project-root does not contain a .aid-o/ workspace
#       at all (distinct from "no data yet" — this is "not an AID project").
#   2   yq/jq missing (same convention as aid-plan-close-check.sh).
#
# Sourceable-safe convention: no top-level `set -e`/`set -euo pipefail` —
# this script sources aid-gate-runtime-baseline.sh, whose own header
# documents why guarded-per-call error handling (not a blanket `set -e`) is
# the required convention for anything that sources it.

usage() {
  cat >&2 <<'EOF'
Usage: aid-gate-runtime-report.sh [--project-root <path>] [gate_name]

  --project-root <path>   project root containing .aid-o/ (default: cwd)
  [gate_name]             optional; omit to list every gate with data

Exit codes: 0 success (incl. "no data yet"), 1 usage/not-an-AID-project,
2 yq/jq missing.
EOF
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/lib/aid-gate-runtime-baseline.sh"

PROJECT_ROOT="$(pwd)"
GATE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      [[ $# -ge 2 ]] || usage
      PROJECT_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      usage
      ;;
    *)
      [[ -z "$GATE_NAME" ]] || usage
      GATE_NAME="$1"
      shift
      ;;
  esac
done

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required (mikefarah/yq v4)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }

[[ -f "$LIB" ]] || { echo "ERROR: aid-gate-runtime-baseline.sh not found at $LIB" >&2; exit 2; }

# Explicit project-root cd — matches aid-plan-close-check.sh's exact
# resolve-then-cd contract (this is the architecture requirement AC14 tests).
cd "$PROJECT_ROOT" || { echo "ERROR: cannot cd into --project-root '$PROJECT_ROOT'" >&2; exit 1; }

if [[ ! -d ".aid-o" ]]; then
  echo "ERROR: '$PROJECT_ROOT' has no .aid-o/ workspace — not an AID project (run /aid-init first)" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$LIB"

# _report_sufficiency_note <gate_name>
#   Prints the one-line data-sufficiency note. Reuses gate_baseline_report_json
#   verbatim for every field (data_sufficient, non_censored_samples_count) —
#   never recomputes the >=3/>=5 sample thresholds itself (same AC4 rule as
#   Step 1: a value is either read straight from the library or explicitly
#   reported as insufficient, never derived from censored/timeout samples).
_report_sufficiency_note() {
  local gate_name="$1"
  local report_json non_censored data_sufficient
  report_json=$(gate_baseline_report_json "$gate_name")
  non_censored=$(jq -r '.non_censored_samples_count // 0' <<<"$report_json")
  data_sufficient=$(jq -r '.data_sufficient // false' <<<"$report_json")
  if [[ "$data_sufficient" == "true" ]]; then
    echo "  -> recommendation available (${non_censored} non-censored samples)"
  else
    echo "  -> only ${non_censored} non-censored sample(s) recorded — recommendation not yet available"
  fi
}

# _report_one_gate <gate_name>
#   Prints gate_baseline_show's own summary line, then the sufficiency note.
#   A gate with no entry at all gets the library's own "insufficient data (no
#   runs recorded yet)" line from gate_baseline_show — the "no data yet"
#   language Error Handling asks for is already exactly what that function
#   returns for an absent entry, so this never re-implements that message.
_report_one_gate() {
  local gate_name="$1"
  gate_baseline_show "$gate_name"
  _report_sufficiency_note "$gate_name"
}

BASELINE_FILE="$(_gbr_baseline_file)"

if [[ -n "$GATE_NAME" ]]; then
  _report_one_gate "$GATE_NAME"
  exit 0
fi

# No gate_name given: list every gate with at least one recorded sample.
if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "No gate runtime data yet — ${BASELINE_FILE} does not exist (no gate has run under this project root)."
  exit 0
fi

GATE_NAMES=$(yq -r '.gates // {} | keys | .[]' "$BASELINE_FILE" 2>/dev/null | sort)

if [[ -z "$GATE_NAMES" ]]; then
  echo "No gate runtime data yet — ${BASELINE_FILE} exists but records no gates."
  exit 0
fi

first=1
while IFS= read -r gate_name; do
  [[ -n "$gate_name" ]] || continue
  [[ "$first" -eq 1 ]] || echo
  first=0
  _report_one_gate "$gate_name"
done <<<"$GATE_NAMES"

exit 0
