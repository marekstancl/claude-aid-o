#!/usr/bin/env bash
# plan-final-measure.sh — read-only measurement of every plan-final run on disk.
#
# Walks <projects root>/*/.aid-o/work/evidence/P*/R-P*final* and prints one JSON
# document: per project the attempts per plan, minutes per attempt, hours from
# the first attempt to the last, and tallies of what the close mechanisms said;
# plus the line count of the plan-final area of this plugin. It is the source of
# fixtures/plan-final/baseline.json and never writes anywhere but stdout.
#
# Usage:
#   plan-final-measure.sh --projects-root <dir> [--as-of <YYYY-MM-DD>]
#
#   --as-of   count only runs whose newest file is at or before the end of that
#             day (UTC), so a baseline can be reproduced after newer runs exist.
#
# Exit codes: 0 printed, 2 usage error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

projects_root="" as_of=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects-root) projects_root="${2:-}"; shift 2 ;;
    --as-of)         as_of="${2:-}"; shift 2 ;;
    *) echo "usage: plan-final-measure.sh --projects-root <dir> [--as-of <YYYY-MM-DD>]" >&2; exit 2 ;;
  esac
done
[[ -d "$projects_root" ]] || { echo "ERROR: --projects-root is not a directory: $projects_root" >&2; exit 2; }
cutoff=""
if [[ -n "$as_of" ]]; then
  [[ "$as_of" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "ERROR: --as-of must be YYYY-MM-DD" >&2; exit 2; }
  cutoff=$(date -u -d "$as_of 23:59:59" +%s)
fi

# One JSON line per run: what the run directory holds. A run with no files is
# an attempt with zero minutes; a run newer than the cut-off is left out.
_run_row() {
  local run="$1" project="$2" plan first last
  plan="$(basename "$(dirname "$run")")"
  read -r first last < <(find "$run" -maxdepth 1 -type f -printf '%T@\n' | sort -n | sed -n '1p;$p' | tr '\n' ' ') || true
  first="${first%.*}" last="${last%.*}"
  if [[ -n "$cutoff" && -n "$last" && "$last" -gt "$cutoff" ]]; then return 0; fi
  _field() { [[ -f "$run/$1" ]] && jq -c "$2" "$run/$1" 2>/dev/null || echo null; }
  jq -cn --arg project "$project" --arg plan "$plan" --arg run "$(basename "$run")" \
    --argjson first "${first:-null}" --argjson last "${last:-null}" \
    --argjson ready   "$(_field release-decision.json '.release_decision.release_ready')" \
    --argjson blockers "$(_field release-decision.json '[.release_decision.blockers[]?.input_id]')" \
    --argjson dg      "$(_field delivery-gate.json '.delivery_gate.summary.enforcement')" \
    --argjson ae      "$(_field acceptance-evidence.json '((.criteria // .acceptance_evidence.criteria // []) | length)')" \
    --argjson audit   "$(_field audit-report.json '[.findings[]?.severity | ascii_downcase]')" \
    --argjson profile "$(_field review-profile.json '(.review_profile.risk_profile // .risk_profile)')" \
    '{project:$project, plan:$plan, run:$run, first:$first, last:$last, release_ready:$ready,
      blockers:$blockers, delivery_gate_enforcement:$dg, acceptance_criteria:$ae,
      audit_severities:$audit, risk_profile:$profile}'
}

rows="$(
  for project_dir in "$projects_root"/*/; do
    project="$(basename "$project_dir")"
    for run in "$project_dir".aid-o/work/evidence/P*/R-P*final*; do
      [[ -d "$run" ]] && _run_row "$run" "$project"
    done
  done
)"

area_lines="$(
  cd "$PLUGIN_DIR"
  wc -l scripts/aid-plan-fsm.sh scripts/aid-release-policy.sh scripts/aid-evidence-verify.sh \
        scripts/aid-plan-close-check.sh scripts/aid-pm-brief.sh scripts/lib/aid-codex-transport.sh \
        agents/simplifier.md agents/auditor.md 2>/dev/null |
    awk '$2 != "total" {printf "%s\t%s\n", $2, $1}' | jq -Rn '[inputs | split("\t") | {(.[0]): (.[1] | tonumber)}] | add // {}'
)"

jq -n --argjson area "$area_lines" --arg as_of "${as_of:-}" \
  --arg command "plan-final-measure.sh --projects-root $projects_root${as_of:+ --as-of $as_of}" '
  def median: sort | if length == 0 then null else .[(length - 1) / 2 | floor] end;
  def p90:    sort | if length < 5 then null else .[(length * 0.9 | floor) - 1] end;
  def tally:  group_by(.) | map({(.[0] | tostring): length}) | add // {};
  [inputs] as $runs
  | {command: $command, as_of: (if $as_of == "" then null else $as_of end),
     projects: ($runs | group_by(.project) | map({(.[0].project): (
       . as $p | ($p | group_by(.plan)) as $plans
       | {plans: ($plans | length), runs: ($p | length),
          attempts_per_plan: ($plans | map(map(.run | capture("final-(?<n>[0-9]+)$").n | tonumber) | max) | sort),
          minutes_per_attempt: ($p | map(if .first then (.last - .first) / 60 else 0 end) | {median: (median | . * 10 | round / 10), p90: (p90 | if . then . * 10 | round / 10 else null end)}),
          first_to_last_hours_median: ($plans | map((map(.last // empty) | max) as $l | (map(.first // empty) | min) as $f | if $l then ($l - $f) / 3600 else 0 end) | median | . * 10 | round / 10),
          release_ready: ($p | map(.release_ready | select(. != null)) | tally),
          blockers: ($p | map(.blockers[]?) | tally),
          delivery_gate_enforcement: ($p | map(.delivery_gate_enforcement | select(. != null)) | tally),
          acceptance_evidence: ($p | map(.acceptance_criteria | select(. != null)) | {runs: length, empty: (map(select(. == 0)) | length)}),
          audit: ($p | map(.audit_severities | select(. != null)) | {runs: length, zero_findings: (map(select(length == 0)) | length), severities: (add // [] | tally)}),
          risk_profile: ($p | map(.risk_profile | select(. != null)) | tally)}
     )}) | add // {}),
     area_lines: $area, area_lines_total: ($area | add // 0)}' <<<"$rows"
