#!/usr/bin/env bash
# aid-plan-review-summary.sh — one line on what a plan's review rounds cost.
#
# aid_plan_review_summary <plan_id> <project_root>
#   Reads every .aid-o/work/evidence/<plan_id>/cp1/round-N/measurement.json and
#   prints one line of at most 120 characters, for /aid-status (recipe
#   review-line):
#     review: none
#     review: legacy evidence
#     review: 2 rounds, 812000 tokens, 1 unknown, missing: generalist_b, degraded: yes
#     review: 2 rounds, 812000 tokens, 0 unknown, missing: none, degraded: no, round 2 not closed
#     review: 2 rounds, measurement unreadable (round 1)
#   A token value a reviewer could not report is counted as unknown, never
#   summed as zero, so an unmeasured round never looks free.

aid_plan_review_summary() {
  local id="${1:?aid_plan_review_summary: plan id required}" root="${2:?aid_plan_review_summary: project root required}"
  local ev="${root}/.aid-o/work/evidence/${id}" d n rounds=() open="" m
  if [[ ! -d "${ev}/cp1" ]]; then
    [[ -d "${ev}/cp1-deep" ]] && echo "review: legacy evidence" || echo "review: none"
    return 0
  fi
  for d in "${ev}"/cp1/round-*/; do
    [[ -d "$d" ]] || continue
    n="${d%/}"; n="${n##*-}"; [[ "$n" =~ ^[0-9]+$ ]] && rounds+=("$n")
  done
  (( ${#rounds[@]} )) || { echo "review: none"; return 0; }
  mapfile -t rounds < <(printf '%s\n' "${rounds[@]}" | sort -n)

  local files=()
  for n in "${rounds[@]}"; do
    m="${ev}/cp1/round-${n}/measurement.json"
    if [[ ! -f "$m" ]]; then open="${open:+${open}, }round ${n} not closed"; continue; fi
    jq -e '.reviewers | type == "object"' "$m" >/dev/null 2>&1 \
      || { echo "review: ${#rounds[@]} rounds, measurement unreadable (round ${n})"; return 0; }
    files+=("$m")
  done

  local line="review: ${#rounds[@]} round$( (( ${#rounds[@]} == 1 )) || echo s)"
  if (( ${#files[@]} )); then
    line+="$(jq -rs '
      [.[].reviewers[]] as $r
      | ([$r[] | .tokens | select(type == "number")] | add // 0) as $sum
      | ([$r[] | select((.tokens | type) != "number")] | length) as $unknown
      | ", \($sum) tokens, \($unknown) unknown"' "${files[@]}")"
    line+=", missing: $(jq -rs '[.[].reviewers | to_entries[] | select(.value.answered == false) | .key] | unique
                               | if length == 0 then "none" else join(", ") end' "${files[@]}")"
    line+=", degraded: $(jq -rs 'if any(.[]; .degraded == true) then "yes" else "no" end' "${files[@]}")"
  fi
  [[ -n "$open" ]] && line+=", ${open}"
  printf '%s\n' "${line:0:120}"
}
