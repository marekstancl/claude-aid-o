#!/usr/bin/env bash
# gates-measure.sh — read-only measurement of the gate runner's use on disk.
#
# WHY THIS FILE EXISTS: P097 rebuilds the gate runner and deletes layers
# (profiles, required_when, runtime baselines, services). Every removal cites
# this record, so the record is written before anything changes. It walks
# <projects root>/<project>/.aid-o/work/evidence/**/gates_report.json (the
# runner's spelling; the hyphenated gates-report.json is only counted under
# other_names), reads each report with jq and prints one JSON document: per
# project the reports and runs in the window, rows by status and by reason,
# profiles with their profile_source, the runtime_baseline fields the rows
# carry, timeouts hit (job_timeout), the configuration layers of the project's
# execution.yaml, and a replay sample whose commits still resolve. It never
# writes anywhere but stdout. It is the source of fixtures/gates/*.json.
#
# Usage:
#   gates-measure.sh --projects-root <dir> [--since <days>] [--as-of <YYYY-MM-DD>]
#   gates-measure.sh --line-count
#
#   --since   window length in days, default 30
#   --as-of   end of the window (that day 23:59:59 UTC); default now. A report
#             is in the window by its file mtime, the same clock
#             plan-final-measure.sh uses.
#   --line-count  print only the line count of the gate area of this plugin
#             (the files Resources Verification of P097 names).
#
# ponytail: the window is by file mtime, not by completed_at — a copy or a
# checkout that touches the files moves them into or out of the window. The
# fixture records the cut-off so a later reader can tell. completed_at was
# rejected because krok's reports carry dates newer than their files.
#
# Exit codes: 0 printed, 2 usage error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Every file Resources Verification of P097 names, relative to the plugin dir.
AREA_FILES=(
  scripts/aid-run-gates.sh
  scripts/aid-fsm.sh
  scripts/aid-plan-fsm.sh
  scripts/aid-job.sh
  scripts/aid-gate-runtime-report.sh
  scripts/aid-test-catalog-selector-snapshot.sh
  scripts/lib/aid-gate-row.sh
  scripts/lib/aid-run-gates-report.sh
  scripts/lib/aid-gate-outcome-summary.sh
  scripts/lib/aid-gate-runtime-baseline.sh
  scripts/lib/aid-test-adapter-contract.sh
  scripts/lib/aid-lock.sh
  scripts/lib/aid-env-name-denylist.sh
  scripts/lib/aid-plan-manifest.sh
  scripts/lib/aid-init-execution-yaml.sh
  scripts/tests/bats/test-aid-gate-runtime-baseline.bats
  scripts/tests/bats/test-gate-baseline-sequential-only.bats
  scripts/tests/bats/test-aid-gate-runtime-report.bats
  scripts/tests/bats/test-aid-service.bats
  scripts/tests/bats/test-owned-jobs-integration.bats
  scripts/tests/bats/test-owned-jobs-review-regressions.bats
  scripts/tests/bats/test-owned-jobs-docs-closure.bats
  scripts/tests/bats/test-aid-plan-final-boundary.bats
  scripts/tests/test-enforcement-registry-cites.sh
  scripts/tests/test-control-boundary.sh
  scripts/tests/test-review-successors.sh
  commands/aid-run.md
  defaults/execution.yaml
  defaults/enforcement-registry.yaml
)

usage() { echo "usage: gates-measure.sh --projects-root <dir> [--since <days>] [--as-of <YYYY-MM-DD>] | --line-count" >&2; exit 2; }

projects_root="" as_of="" since=30 line_count=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects-root) projects_root="${2:-}"; shift 2 ;;
    --since)         since="${2:-}"; shift 2 ;;
    --as-of)         as_of="${2:-}"; shift 2 ;;
    --line-count)    line_count=1; shift ;;
    *) usage ;;
  esac
done

if (( line_count )); then
  cd "$PLUGIN_DIR"
  # scripts/gates/*, the profile libraries (old classifier until Step 9, new
  # resolver) and the service library (until Step 9) join the named files by
  # glob, so the list survives the removal; a file a later step deleted counts
  # 0 (wc's rc is not the measurement). The applicability library and the three
  # service/required_when suites Step 6 deleted are no longer named: 0 lines.
  { wc -l "${AREA_FILES[@]}" scripts/lib/aid-gate-profile*.sh scripts/lib/aid-service*.sh scripts/gates/* 2>/dev/null || true; } |
    awk '$2 != "total" {printf "%s\t%s\n", $2, $1}' |
    jq -Rn --arg commit "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
      '{command: "gates-measure.sh --line-count", commit: $commit,
        files: ([inputs | split("\t") | {(.[0]): (.[1] | tonumber)}] | add // {})}
       | .total = (.files | add // 0)'
  exit 0
fi

[[ -d "$projects_root" ]] || { echo "ERROR: --projects-root is not a directory: $projects_root" >&2; usage; }
[[ "$since" =~ ^[0-9]+$ ]] || { echo "ERROR: --since must be a whole number of days" >&2; usage; }
if [[ -n "$as_of" ]]; then
  [[ "$as_of" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "ERROR: --as-of must be YYYY-MM-DD" >&2; usage; }
  window_end=$(date -u -d "$as_of 23:59:59" +%s)
else
  window_end=$(date -u +%s)
fi
window_start=$(( window_end - since * 86400 ))

# One JSON line per report inside the window: the fields the tallies need.
_report_row() {
  local path="$1" project="$2" mtime="$3" run_dir
  run_dir="$(dirname "$path")"; [[ "$(basename "$run_dir")" == gates ]] && run_dir="$(dirname "$run_dir")"
  local sha_source="" sha
  if ! jq -e 'type == "object"' "$path" >/dev/null 2>&1; then
    jq -cn --arg project "$project" --arg path "$path" '{project: $project, path: $path, unreadable: true}'
    return 0
  fi
  sha="$(jq -r '.revision.head_sha // empty' "$path")"
  if [[ -n "$sha" ]]; then sha_source="report.revision.head_sha"
  elif [[ -f "$run_dir/fsm-state.yaml" ]]; then
    sha="$(sed -n 's/^base_commit: *//p' "$run_dir/fsm-state.yaml" | head -1)"
    [[ -n "$sha" ]] && sha_source="fsm-state.yaml.base_commit"
  fi
  local resolves=false
  [[ -n "$sha" ]] && git -C "$projects_root/$project" cat-file -e "$sha^{commit}" 2>/dev/null && resolves=true
  jq -c --arg project "$project" --arg path "$path" --arg run_dir "$(basename "$run_dir")" \
     --argjson mtime "$mtime" --arg sha "$sha" --arg sha_source "$sha_source" --argjson resolves "$resolves" '
    {project: $project, path: $path, mtime: $mtime, unreadable: false,
     run_id: (.run_id // $run_dir), profile: .profile, profile_source: .profile_source, overall: .overall,
     sha: (if $sha == "" then null else $sha end), sha_source: (if $sha_source == "" then null else $sha_source end),
     sha_resolves: $resolves,
     gates_is_object: ((.gates | type) == "object"),
     rows: ((.gates // {}) | if type == "object" then to_entries | map({
        id: .key,
        status: (.value | if type == "object" then (.status // .result // "legacy_row") else "legacy_row" end),
        reason: (.value | if type == "object" then .reason else null end),
        keys: (.value | if type == "object" then keys else [] end),
        baseline: (.value | if type == "object" then .runtime_baseline else null end)}) else [] end)}' "$path"
}

# Configuration layers of one project's execution.yaml, as JSON.
_config_row() {
  local project="$1" cfg="$projects_root/$1/.aid-o/config/execution.yaml"
  local baselines="$projects_root/$1/.aid-o/metrics/gate-runtime-baselines.yaml"
  if [[ ! -f "$cfg" ]]; then jq -cn --arg project "$project" '{project: $project, execution_yaml: false}'; return 0; fi
  local doc; doc="$(yq -o=json '.' "$cfg" 2>/dev/null || echo '{}')"
  local bl_gates='[]'
  [[ -f "$baselines" ]] && bl_gates="$(yq -o=json '.gates // {} | keys' "$baselines" 2>/dev/null || echo '[]')"
  jq -c --arg project "$project" --argjson mentions "$(grep -c baseline "$cfg" || true)" --argjson bl "$bl_gates" '
    {project: $project, execution_yaml: true,
     gates: ((.gates // {}) | length),
     gate_profiles: ((.gate_profiles // {}) | keys),
     required_when: ([(.gates // {})[]? | select(type == "object" and has("required_when")) | .required_when]),
     services: ((.services // {}) | length),
     baseline_mentions_in_execution_yaml: $mentions,
     runtime_baseline_file_gates: $bl}' <<<"$doc"
}

reports="$(
  for project_dir in "$projects_root"/*/; do
    project="$(basename "$project_dir")"
    [[ -d "$project_dir.aid-o" ]] || continue
    evidence="$project_dir.aid-o/work/evidence"
    _config_row "$project"
    [[ -d "$evidence" ]] || continue
    # The hyphenated spelling is an inventory of stray names, so no window applies.
    find "$evidence" -type f -name 'gates-report.json' -printf '.\n' | while read -r _; do
      jq -cn --arg project "$project" '{project: $project, other_name: true}'
    done
    find "$evidence" -type f -name 'gates_report.json' -printf '%T@ %p\n' | while read -r t path; do
      t="${t%.*}"; (( t > window_start && t <= window_end )) || continue
      _report_row "$path" "$project" "$t"
    done
  done
)"

jq -n --arg root "$projects_root" --argjson since "$since" --arg as_of "${as_of:-}" \
  --argjson window_start "$window_start" --argjson window_end "$window_end" \
  --arg command "gates-measure.sh --projects-root $projects_root --since $since${as_of:+ --as-of $as_of}" '
  def tally: group_by(.) | map({(.[0] | tostring): length}) | add // {};
  [inputs] as $all
  | ($all | map(select(has("execution_yaml")))) as $configs
  | ($all | map(select(has("path")))) as $reports
  | ($reports | map(select(.unreadable | not))
     # A run with two reports counts once: the newest by mtime.
     | group_by([.project, .run_id]) | map(max_by(.mtime))) as $runs
  | ($runs | map(select(.project == "wan" or .project == "acta"))) as $sample_pool
  | {command: $command, as_of: (if $as_of == "" then null else $as_of end), since_days: $since,
     window: {from: ($window_start | todate), to: ($window_end | todate), by: "file mtime"},
     projects: ($configs | map(.project as $p
       | ($runs | map(select(.project == $p))) as $pr
       | ($pr | map(.rows[]) ) as $rows
       | {($p): {
           reports: ($reports | map(select(.project == $p and (.unreadable | not))) | length),
           runs: ($pr | length),
           other_names: ($all | map(select(.project == $p and .other_name?)) | length),
           unreadable: ($reports | map(select(.project == $p and .unreadable) | .path)),
           empty_reports: ($pr | map(select((.rows | length) == 0) | .path)),
           rows: {total: ($rows | length),
                  by_status: ($rows | map(.status) | tally),
                  by_reason: ($rows | map(.reason | select(. != null)) | tally),
                  legacy_row_keys: ($rows | map(select(.status == "legacy_row") | .keys | join(",")) | tally)},
           profiles: ($pr | map({profile: (.profile // "none"), profile_source: (.profile_source // "none")})
                      | group_by(.) | map(.[0] + {runs: length})),
           overall: ($pr | map(.overall // "none") | tally),
           timeouts_hit: ($rows | map(select(.status == "job_timeout")) | length),
           runtime_baseline: {rows_with_baseline: ($rows | map(select(.baseline != null)) | length),
                              policy_result: ($rows | map(.baseline.policy_result? // empty) | tally),
                              timeout_recommended_present: ($rows | map(select(.baseline.timeout_recommended_seconds? != null)) | length),
                              run_mode_recommended: ($rows | map(.baseline.run_mode_recommended? // empty) | tally)},
           config: ($configs | map(select(.project == $p)) | .[0] | del(.project)),
           sample_excluded: ($sample_pool | map(select(.project == $p and (.sha_resolves | not))) | length)
         }}) | add // {}),
     totals: {runs: ($runs | length), rows: ($runs | map(.rows[]) | length),
              by_status: ($runs | map(.rows[].status) | tally),
              unreadable: ($reports | map(select(.unreadable)) | length)},
     sample: ($sample_pool | map(select(.sha_resolves)) | sort_by(.project, .path) | map(
        {project, run_id, report_path: (.path | ltrimstr($root + "/")), sha, sha_source, profile, overall,
         rows: (.rows | map(select(.status != "legacy_row")) | map({(.id): .status}) | add // {})}))}' <<<"$reports"
