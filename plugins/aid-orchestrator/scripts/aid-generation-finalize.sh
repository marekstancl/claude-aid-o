#!/usr/bin/env bash
# =============================================================================
# aid-generation-finalize.sh — verify one complete generated EPIC package
#
# This is deliberately between generation and FSM init. It proves that every
# phase of one reviewed source plan has produced exactly one EPIC + plan.json.
# It never starts an EPIC and never mutates Git/FSM state.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/aid-plan-graph.sh"
source "${SCRIPT_DIR}/lib/aid-source-plan-graph.sh"
check_prerequisites

usage() {
  echo "Usage: $0 --plan PLAN --total N --epics-json FILE --output RECEIPT" >&2
}

plan="" total="" epics_file="" output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) plan="${2:-}"; shift 2 ;;
    --total) total="${2:-}"; shift 2 ;;
    --epics-json) epics_file="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -f "$plan" && -f "$epics_file" && -n "$output" && "$total" =~ ^[1-9][0-9]*$ ]] || { usage; exit 2; }

graph="$(aid_source_plan_graph "$plan" "$total")" || {
  echo "ERROR: cannot finalize an invalid source plan" >&2; exit 1;
}
plan_abs="$(realpath "$plan")"
plan_sha="sha256:$(sha256sum "$plan" | awk '{print $1}')"

jq -e --argjson total "$total" '
  type == "array" and length == $total and
  (([.[].epic_id] | length) == ([.[].epic_id] | unique | length))
' "$epics_file" >/dev/null 2>&1 || {
  echo "ERROR: generation manifest must contain exactly $total unique EPIC entries" >&2; exit 1;
}

for phase in $(seq 1 "$total"); do
  entry="$(jq -c --argjson p "$phase" '.[] | select(.phase == $p)' "$epics_file")"
  [[ -n "$entry" ]] || { echo "ERROR: missing generated phase $phase" >&2; exit 1; }
  [[ "$(printf '%s\n' "$entry" | wc -l | tr -d ' ')" == "1" ]] || { echo "ERROR: duplicate generated phase $phase" >&2; exit 1; }
  epic_path="$(jq -r '.epic_path // empty' <<< "$entry")"
  plan_json="$(jq -r '.plan_json // empty' <<< "$entry")"
  contract_validate="$(jq -r '.contract_validate // empty' <<< "$entry")"
  [[ -f "$epic_path" && -f "$plan_json" && -f "$contract_validate" ]] || { echo "ERROR: phase $phase has missing EPIC, plan.json, or contract-validation evidence" >&2; exit 1; }
  jq -e '.result == "pass"' "$contract_validate" >/dev/null 2>&1 || { echo "ERROR: phase $phase contract validation is not a pass" >&2; exit 1; }
  epic_id="$(jq -r '.epic_id // empty' <<< "$entry")"
  [[ "$epic_id" =~ _${total}$ ]] || { echo "ERROR: phase $phase EPIC id has wrong total: $epic_id" >&2; exit 1; }
  [[ "$epic_id" =~ -${phase}_${total}$ ]] || { echo "ERROR: phase $phase EPIC id does not bind its phase: $epic_id" >&2; exit 1; }
  expected_steps="$(jq -r --argjson p "$phase" '[.steps[] | select(.epic == $p) | .step] | join(",")' <<< "$graph")"
  meta_sha="$(awk -F': ' '/^source_plan_sha256:/{print $2; exit}' "$epic_path")"
  meta_phase="$(awk -F': ' '/^source_phase:/{print $2; exit}' "$epic_path")"
  meta_steps="$(awk -F': ' '/^source_step_ids:/{gsub(/"/, "", $2); print $2; exit}' "$epic_path")"
  [[ "$meta_sha" == "$plan_sha" && "$meta_phase" == "$phase" && "$meta_steps" == "$expected_steps" ]] || {
    echo "ERROR: phase $phase EPIC source binding does not match the reviewed plan graph" >&2; exit 1;
  }
  actual_step_count="$(jq '.steps | length' "$plan_json")"
  expected_step_count="$(jq --arg s "$expected_steps" '$s | split(",") | map(select(length > 0)) | length' -n)"
  [[ "$actual_step_count" == "$expected_step_count" ]] || {
    echo "ERROR: phase $phase plan.json step count disagrees with source graph" >&2; exit 1;
  }
  # The source graph is global, while plan.json uses phase-local step IDs.
  # Preserve every edge whose two endpoints belong to this phase, translated
  # by the generated step order. Cross-phase edges are intentionally handled
  # by the EPIC/queue dependency layer and therefore do not appear here.
  actual_ids="$(jq -c '.steps | map(.id)' "$plan_json")"
  expected_dependencies="$(jq -c --argjson phase "$phase" --argjson actual "$actual_ids" '
    [.steps[] | select(.epic == $phase) | .step] as $source_steps |
    [(.edges // [])[]
      | . as $raw_edge
      | {before:($raw_edge.before | capture("^step-(?<n>[0-9]+)$").n | tonumber), after:($raw_edge.after | capture("^step-(?<n>[0-9]+)$").n | tonumber)}
      | . as $edge
      | ($source_steps | index($edge.before)) as $before_index
      | ($source_steps | index($edge.after)) as $after_index
      | select($before_index != null and $after_index != null)
      | {before:$actual[$before_index], after:$actual[$after_index]}
    ] | sort_by(.before, .after)
  ' <<< "$graph")"
  actual_dependencies="$(jq -c '[.dependencies[] | {before, after}] | sort_by(.before, .after)' "$plan_json")"
  [[ "$actual_dependencies" == "$expected_dependencies" ]] || {
    echo "ERROR: phase $phase plan.json dependencies disagree with the source-plan graph" >&2; exit 1;
  }
  source_plan="$(jq -r '.source_plan // empty' "$plan_json" 2>/dev/null || true)"
  [[ -n "$source_plan" && "$(realpath "$source_plan" 2>/dev/null || true)" == "$plan_abs" ]] || {
    echo "ERROR: phase $phase plan.json is not bound to this source plan" >&2; exit 1;
  }
done

provisional="$(dirname "$output")/provisional-graph.json"
[[ -f "$provisional" ]] || { echo "ERROR: missing provisional graph: $provisional" >&2; exit 1; }
jq -e --arg sha "$plan_sha" '.schema == "aid-source-plan-graph/v1" and .plan_sha256 == $sha' "$provisional" >/dev/null || {
  echo "ERROR: provisional graph is stale, malformed, or belongs to another plan" >&2; exit 1;
}
provisional_canonical="$(jq -S -c . "$provisional")"
final_canonical="$(jq -S -c . <<< "$graph")"
[[ "$provisional_canonical" == "$final_canonical" ]] || {
  echo "ERROR: provisional graph disagrees with the final source-plan graph" >&2; exit 1;
}

# Construct the durable artifact list in Bash, not from untrusted pre-filled
# hashes in the pipeline manifest.
artifact_entries='[]'
for phase in $(seq 1 "$total"); do
  entry="$(jq -c --argjson p "$phase" '.[] | select(.phase == $p)' "$epics_file")"
  epic_path="$(jq -r '.epic_path' <<< "$entry")"; plan_json="$(jq -r '.plan_json' <<< "$entry")"
  contract_validate="$(jq -r '.contract_validate' <<< "$entry")"
  artifact_entries="$(jq -c --argjson e "$entry" --arg es "sha256:$(sha256sum "$epic_path" | awk '{print $1}')" --arg ps "sha256:$(sha256sum "$plan_json" | awk '{print $1}')" --arg cs "sha256:$(sha256sum "$contract_validate" | awk '{print $1}')" \
    '. + [$e + {epic_sha256:$es, plan_json_sha256:$ps, contract_validate_sha256:$cs}]' <<< "$artifact_entries")"
done

mkdir -p "$(dirname "$output")"
tmp="${output}.tmp.$$"
jq -n --arg schema "aid-generation-receipt/v1" --arg plan "$plan_abs" --arg plan_sha "$plan_sha" \
  --arg provisional_sha "sha256:$(sha256sum "$provisional" | awk '{print $1}')" \
  --arg final_sha "sha256:$(printf '%s' "$final_canonical" | sha256sum | awk '{print $1}')" \
  --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson graph "$graph" --argjson epics "$artifact_entries" \
  '{schema:$schema, plan_path:$plan, plan_sha256:$plan_sha, provisional_graph_sha256:$provisional_sha, final_graph_sha256:$final_sha, created_at:$created, final_graph:$graph, epics:$epics}' > "$tmp"
mv "$tmp" "$output"
printf '%s\n' "$output"
