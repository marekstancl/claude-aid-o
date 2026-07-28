#!/usr/bin/env bash
# =============================================================================
# aid-generation-readiness.sh — one deterministic readiness check before EPIC
# generation.  It explains the contract briefly and writes no project state
# unless --write-provisional is explicitly requested.
#
# Usage: aid-generation-readiness.sh <plan.md> [--total N] [--json] [--write-provisional <path>]
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/aid-plan-graph.sh"
source "${SCRIPT_DIR}/lib/aid-source-plan-graph.sh"
check_prerequisites

plan="" total="" json=0 out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --total) total="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --write-provisional) out="$2"; shift 2 ;;
    -*) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
    *) [[ -z "$plan" ]] || { echo "ERROR: one plan path expected" >&2; exit 2; }; plan="$1"; shift ;;
  esac
done
[[ -n "$plan" && -f "$plan" ]] || { echo "ERROR: plan file not found" >&2; exit 2; }
[[ -z "$total" || "$total" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --total must be a positive integer" >&2; exit 2; }

if ! lint_out="$("${SCRIPT_DIR}/aid-plan-lint.sh" "$plan" 2>&1)"; then
  printf '%s\n' "$lint_out" >&2
  echo "READINESS: FAIL — repair Files: entries; full grammar: skills/plan-writing.md" >&2
  exit 1
fi
if ! graph="$(aid_source_plan_graph "$plan" "$total")"; then
  printf '%s\n' "${_aid_spg_error:-dependency grammar is invalid}" >&2
  echo "READINESS: FAIL — canonical dependencies are 'Depends on: Step N[, Steps X-Y]'." >&2
  exit 1
fi
if [[ -n "$out" ]]; then
  mkdir -p "$(dirname "$out")"
  printf '%s\n' "$graph" > "$out"
fi
if (( json )); then
  jq -n --arg plan "$(realpath "$plan")" --arg instructions "plugins/aid-orchestrator/skills/plan-writing.md" --argjson graph "$graph" '{status:"ready",plan:$plan,instructions:$instructions,provisional_graph:$graph}'
else
  echo "READINESS: PASS — source plan is safe to generate."
  echo "  Files grammar: canonical; dependencies: canonical; graph: acyclic."
  echo "  Full authoring contract: plugins/aid-orchestrator/skills/plan-writing.md"
  echo "  Generation contract: plugins/aid-orchestrator/skills/planner.md"
  [[ -n "$out" ]] && echo "  Provisional graph: $out"
fi
exit 0
