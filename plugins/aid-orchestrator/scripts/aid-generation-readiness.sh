#!/usr/bin/env bash
# =============================================================================
# aid-generation-readiness.sh — one deterministic readiness check before EPIC
# generation.  It explains the contract briefly and writes no project state
# unless --write-provisional is explicitly requested.
#
# It owns no rule of its own: it runs aid-plan-lint.sh and the source-plan
# dependency graph, and reports what they say. Since P084 the lint's findings
# are BAND-SCOPED (what a plan owes follows the paths it declares), so this
# check is band-aware by construction — there is no second classification here
# to drift from the gate's.
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
  echo "READINESS: FAIL — repair the lint findings; full grammar: skills/plan-writing.md" >&2
  exit 1
fi
# A PASSING lint still has things to say: legacy advisories are non-blocking BY
# DESIGN, and swallowing them here made "a loud advisory" silent everywhere the
# lint is reached through generation — which is everywhere it actually runs.
[[ -n "$lint_out" ]] && printf '%s\n' "$lint_out" >&2
if ! graph="$(aid_source_plan_graph "$plan" "$total")"; then
  # P084 Step 7 — the lint logs its own verdict; this is the OTHER stop this
  # script owns, so the two reasons a plan never reaches generation are both
  # countable instead of one being invisible.
  # shellcheck source=lib/aid-stage-log.sh
  source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
  # shellcheck source=lib/aid-plan-band.sh
  source "${SCRIPT_DIR}/lib/aid-plan-band.sh"
  _rd_id="$(awk 'NR==1 && $0!="---"{exit} NR==1{i=1;next} i&&$0=="---"{exit} i&&/^id:/{sub(/^id:[[:space:]]*/,"");sub(/[[:space:]]*$/,"");print;exit}' "$plan")"
  if [[ -n "${_rd_id:-}" ]]; then
    _rd_root="$(_aid_band_project_root "$plan")" || _rd_root=""
    if [[ -n "$_rd_root" ]] && _rd_tl="$(aid_plan_timeline "$_rd_root" "$_rd_id")"; then
      log_event "$_rd_tl" "plan_readiness_blocked" reason="dependency_grammar"
    fi
  fi
  printf '%s\n' "${_aid_spg_error:-dependency grammar is invalid}" >&2
  echo "READINESS: FAIL — canonical dependencies are 'Depends on: Step N[, Steps X-Y]', or one of the two no-dependency markers 'none' (authoring form) and '---' (generated-canonical form); an optional ' — annotation' after the references is ignored." >&2
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
