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
# shellcheck source=lib/aid-plan-band.sh
source "${SCRIPT_DIR}/lib/aid-plan-band.sh"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
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

# The lint runs the wave check in its advisory mode; here it is run BLOCKING a
# few lines below, so the lint is told to skip it rather than parse the plan for
# waves twice and print the same findings twice.
if ! lint_out="$(AID_LINT_SKIP_PARALLEL=1 "${SCRIPT_DIR}/aid-plan-lint.sh" "$plan" 2>&1)"; then
  printf '%s\n' "$lint_out" >&2
  echo "READINESS: FAIL — repair the lint findings; full grammar: skills/plan-writing.md" >&2
  exit 1
fi
# A PASSING lint still has things to say: legacy advisories are non-blocking BY
# DESIGN, and swallowing them here made "a loud advisory" silent everywhere the
# lint is reached through generation — which is everywhere it actually runs.
# `if`, not `[[ … ]] && …`: a bare AND-list is the script's last command status
# under `set -e`, so an empty lint_out would abort a PASSING readiness check.
if [[ -n "$lint_out" ]]; then printf '%s\n' "$lint_out" >&2; fi
# The deterministic plan check (aid-plan-check.sh): internal consistency, the
# plan against the repository, and — when a snapshot is recorded — the claims
# the last revision added. Same two tiers as the lint. BLOCKING here for the
# same reason the lint is: this is the last point before the plan becomes
# EPICs, and every one of these findings is something a model reviewer was
# paid to find in the 2026-09 pilots.
# The report lands next to the plan's other evidence when the plan carries an
# id and lives in a workspace; a plan outside one is still checked, just unreported.
_pc_id="$(sed -n '1,/^---$/{/^---$/!p}' "$plan" | awk -F': *' '/^id:/{print $2; exit}' | tr -d '"' )"
_pc_root="$(dirname "$(realpath "$plan")")"; while [[ "$_pc_root" != "/" && ! -d "$_pc_root/.aid-o" ]]; do _pc_root="$(dirname "$_pc_root")"; done
_pc_json=()
if [[ -n "$_pc_id" && -d "$_pc_root/.aid-o" ]]; then _pc_json=(--json "$_pc_root/.aid-o/work/evidence/${_pc_id}/plan-check.json"); fi
if ! check_out="$(AID_PLAN_CHECK_RUN_CMDS=0 "${SCRIPT_DIR}/aid-plan-check.sh" "$plan" "${_pc_json[@]}" 2>&1)"; then
  printf '%s\n' "$check_out" >&2
  aid_plan_log "$plan" "plan_readiness_blocked" reason="plan_check"
  echo "READINESS: FAIL — repair the aid-plan-check findings; the check list: skills/plan-writing.md §Completeness Gate" >&2
  exit 1
fi
if [[ -n "$check_out" ]]; then printf '%s\n' "$check_out" >&2; fi
# Disjointness of the declared waves (P085 Step 7). Here rather than in the
# lint because it is a property of the step GRAPH, which is what this script
# already grades; and BLOCKING here because this is the last point before the
# plan becomes EPICs, which is where a wave that shares a file stops being a
# note and starts being two agents in one file.
if ! par_out="$("${SCRIPT_DIR}/aid-plan-parallel-check.sh" "$plan" 2>&1)"; then
  printf '%s\n' "$par_out" >&2
  aid_plan_log "$plan" "plan_readiness_blocked" reason="parallel_group_collision"
  echo "READINESS: FAIL — steps declared in one wave must not name the same file; full grammar: skills/plan-writing.md" >&2
  exit 1
fi
if [[ -n "$par_out" ]]; then printf '%s\n' "$par_out" >&2; fi
if ! graph="$(aid_source_plan_graph "$plan" "$total")"; then
  # P084 Step 7 — the lint logs its own verdict; this is the OTHER stop this
  # script owns, so the two reasons a plan never reaches generation are both
  # countable instead of one being invisible.
  aid_plan_log "$plan" "plan_readiness_blocked" reason="dependency_grammar"
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
  echo "  Files grammar: canonical; dependencies: canonical; graph: acyclic; declared waves: disjoint."
  echo "  Full authoring contract: plugins/aid-orchestrator/skills/plan-writing.md"
  echo "  Generation contract: plugins/aid-orchestrator/skills/planner.md"
  [[ -n "$out" ]] && echo "  Provisional graph: $out"
fi
exit 0
