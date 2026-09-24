#!/usr/bin/env bash
# =============================================================================
# aid-generation-readiness.sh — one deterministic readiness check before EPIC
# generation.  It explains the contract briefly and writes no project state
# unless --write-provisional is explicitly requested.
#
# It owns no rule of its own: it runs aid-plan-lint.sh, aid-plan-check.sh, the
# parallel check and the source-plan dependency graph, and reports what they say
# — all of them, then one verdict. The plan author runs it too (commands/aid-plan.md
# Step 8), so a plan that passes the author's check passes generation.
#
# Usage: aid-generation-readiness.sh <plan.md> [--total N] [--json] [--write-provisional <path>]
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/aid-plan-graph.sh"
source "${SCRIPT_DIR}/lib/aid-source-plan-graph.sh"
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"
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

# Every part runs and prints, and the verdict comes after all of them: an
# author who fixes one finding and reruns should not meet the next one only
# then (ACTA P024, WAN P101). `fails` collects one guidance line per part.
fails=()
# The lint runs the wave check in its advisory mode; here it is run BLOCKING
# below, so the lint is told to skip it rather than print the same findings twice.
# A PASSING lint still has things to say (legacy advisories), so its output is
# printed either way.
lint_out="$(AID_LINT_SKIP_PARALLEL=1 "${SCRIPT_DIR}/aid-plan-lint.sh" "$plan" 2>&1)" \
  || fails+=("repair the lint findings; full grammar: skills/plan-writing.md")
if [[ -n "$lint_out" ]]; then printf '%s\n' "$lint_out" >&2; fi
# The deterministic plan check (aid-plan-check.sh): internal consistency, the
# plan against the repository, and — when a snapshot is recorded — the claims
# the last revision added. Its report lands next to the plan's other evidence
# when the plan carries an id and lives in a workspace.
_pc_id="$(sed -n '1,/^---$/{/^---$/!p}' "$plan" | awk -F': *' '/^id:/{print $2; exit}' | tr -d '"' )"
_pc_root="$(dirname "$(realpath "$plan")")"; while [[ "$_pc_root" != "/" && ! -d "$_pc_root/.aid-o" ]]; do _pc_root="$(dirname "$_pc_root")"; done
_pc_json=()
if [[ -n "$_pc_id" && -d "$_pc_root/.aid-o" ]]; then _pc_json=(--json "$_pc_root/.aid-o/work/evidence/${_pc_id}/plan-check.json"); fi
if ! check_out="$(AID_PLAN_CHECK_RUN_CMDS=0 "${SCRIPT_DIR}/aid-plan-check.sh" "$plan" "${_pc_json[@]}" 2>&1)"; then
  aid_plan_log "$plan" "plan_readiness_blocked" reason="plan_check"
  fails+=("repair the aid-plan-check findings; the check list: skills/plan-writing.md §Completeness Gate (pipeline.md §When AID refuses: plan_check)")
fi
if [[ -n "$check_out" ]]; then printf '%s\n' "$check_out" >&2; fi
# Disjointness of the declared waves (P085 Step 7): a property of the step
# GRAPH, and the point where a wave that shares a file becomes two agents in one.
if ! par_out="$("${SCRIPT_DIR}/aid-plan-parallel-check.sh" "$plan" 2>&1)"; then
  aid_plan_log "$plan" "plan_readiness_blocked" reason="parallel_group_collision"
  fails+=("steps declared in one wave must not name the same file; full grammar: skills/plan-writing.md (pipeline.md §When AID refuses: parallel_group_collision)")
fi
if [[ -n "$par_out" ]]; then printf '%s\n' "$par_out" >&2; fi
if ! graph="$(aid_source_plan_graph "$plan" "$total")"; then
  aid_plan_log "$plan" "plan_readiness_blocked" reason="dependency_grammar"
  printf '%s\n' "${_aid_spg_error:-dependency grammar is invalid}" >&2
  fails+=("canonical dependencies are 'Depends on: Step N[, Steps X-Y]', or one of the two no-dependency markers 'none' (authoring form) and '---' (generated-canonical form); an optional ' — annotation' after the references is ignored (pipeline.md §When AID refuses: dependency_grammar)")
fi
if (( ${#fails[@]} )); then
  printf 'READINESS: FAIL — %s\n' "${fails[@]}" >&2
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
