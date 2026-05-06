#!/usr/bin/env bash
# aid-compliance-report.sh — Pre vs post Session A compliance aggregator.
#
# Reads all compliance.json files under one or more evidence roots and
# emits a trend table comparing pre-Session-A baseline against post-deploy
# measured runs. Designed to be the data source for "Session A delivered X%
# improvement on dimension Y" claims in retrospectives.
#
# Read-only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

# Hardcoded dimension list for Session A. When Sessions B/C deploy and
# populate verifier_outputs / dod_present / memory_substantive, swap the
# loop below with auto-discovery (1-line change documented in plan §Step 5
# Edge Cases):
#
#   for dim in $(jq -r '.[0].checks | keys[]' <<< "$all_compliance"); do
#
# Hardcoded keeps the v2.16.0 report shape stable for downstream consumers
# (no schema drift between A and B/C deploy windows).
SESSION_A_DIMENSIONS=(branch_correct execution_yaml_present gates_generated_by)

usage() {
  cat <<EOF
Usage: $(basename "$0") [--since YYYY-MM-DD] [--era pre|post|both] [--output md|json]
                       [--evidence-roots "path1 path2 ..."]

Aggregates compliance.json files into a pre-vs-post trend report.

Options:
  --since YYYY-MM-DD       Filter by .evaluated_at >= since (inclusive).
                           Format: ISO date (lex compare against ISO 8601 ts).
  --era pre|post|both      Filter by .deploy_era. Default: both.
  --output md|json         md (default) renders pivot table; json emits
                           grouped {pre: [...], post: [...]}.
  --evidence-roots "..."   Space-separated paths. Defaults to 5 ekosystem
                           projects under /opt/eco/projects.
  -h, --help               This help.

Examples:
  $(basename "$0")
  $(basename "$0") --since 2026-04-01 --era post
  $(basename "$0") --output json | jq '.post | length'
EOF
}

main() {
  local since="" era="both" output="md"
  local -a evidence_roots=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)          since="$2"; shift 2 ;;
      --era)            era="$2"; shift 2 ;;
      --output)         output="$2"; shift 2 ;;
      --evidence-roots) read -ra evidence_roots <<< "$2"; shift 2 ;;
      -h|--help)        usage; exit 0 ;;
      *)                echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  case "$era" in
    pre|post|both) ;;
    *) echo "ERROR: --era must be 'pre', 'post', or 'both'" >&2; exit 1 ;;
  esac
  case "$output" in
    md|json) ;;
    *) echo "ERROR: --output must be 'md' or 'json'" >&2; exit 1 ;;
  esac

  if (( ${#evidence_roots[@]} == 0 )); then
    evidence_roots=(
      "/opt/eco/projects/vulcan/.aid-o/work/evidence"
      "/opt/eco/projects/sousto-na-miru/.aid-o/work/evidence"
      "/opt/eco/projects/krok/.aid-o/work/evidence"
      "/opt/eco/projects/wan/.aid-o/work/evidence"
      "/opt/eco/projects/aid-orchestrator/.aid-o/work/evidence"
    )
  fi

  # Collect all compliance.json files into a single JSON array.
  # Stream into one slurp at the end (one jq invocation per file would be O(N²)).
  local tmp_ndjson; tmp_ndjson=$(mktemp)
  trap 'rm -f "${tmp_ndjson:-}" 2>/dev/null || true' EXIT

  for root in "${evidence_roots[@]}"; do
    if [[ ! -d "$root" ]]; then
      log_warn "Evidence root not found, skipping: $root" >&2
      continue
    fi
    while IFS= read -r f; do
      # Each file is a single JSON object; cat into NDJSON.
      jq -c '.' "$f" 2>/dev/null >> "$tmp_ndjson" || log_warn "Skipping invalid JSON: $f"
    done < <(find "$root" -mindepth 3 -maxdepth 3 -name "compliance.json" 2>/dev/null)
  done

  # Apply --since + --era filters.
  local all_compliance
  all_compliance=$(jq -s \
    --arg since "$since" \
    --arg era "$era" \
    'map(
       select(($since == "" or (.evaluated_at >= $since))
              and ($era == "both" or .deploy_era == ($era + "-session-a")))
     )' "$tmp_ndjson")

  if [[ "$output" == "json" ]]; then
    jq --argjson all "$all_compliance" -n \
       '{
          pre:  [$all[] | select(.deploy_era == "pre-session-a")],
          post: [$all[] | select(.deploy_era == "post-session-a")]
        }'
    return 0
  fi

  # ─── Markdown trend table ──────────────────────────────────────────
  local pre_count post_count
  pre_count=$(jq -r '[.[] | select(.deploy_era == "pre-session-a")] | length' <<< "$all_compliance")
  post_count=$(jq -r '[.[] | select(.deploy_era == "post-session-a")] | length' <<< "$all_compliance")

  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat <<EOF
# AID Compliance Trend Report

Generated:           ${now}
Filter --since:      ${since:-<none>}
Filter --era:        ${era}
Pre-Session-A:       ${pre_count} EPICs
Post-Session-A:      ${post_count} EPICs

| Dimension | Pre (% pass) | Post (% pass) | Δ |
|-----------|------------:|--------------:|---:|
EOF

  local dim
  for dim in "${SESSION_A_DIMENSIONS[@]}"; do
    local pre_pass post_pass pre_pct post_pct delta
    pre_pass=$(jq -r --arg d "$dim" \
      '[.[] | select(.deploy_era == "pre-session-a") | .checks[$d]] | map(select(. == true)) | length' \
      <<< "$all_compliance")
    post_pass=$(jq -r --arg d "$dim" \
      '[.[] | select(.deploy_era == "post-session-a") | .checks[$d]] | map(select(. == true)) | length' \
      <<< "$all_compliance")
    pre_pct=$(( pre_count > 0 ? pre_pass * 100 / pre_count : 0 ))
    post_pct=$(( post_count > 0 ? post_pass * 100 / post_count : 0 ))
    delta=$(( post_pct - pre_pct ))
    printf "| %s | %d%% | %d%% | %+d%% |\n" "$dim" "$pre_pct" "$post_pct" "$delta"
  done

  if (( pre_count == 0 && post_count == 0 )); then
    cat <<EOF

_No compliance.json files found under requested evidence roots (and filter)._
Run \`aid-compliance-backfill.sh --deploy-date YYYY-MM-DDTHH:MM:SSZ\` first
to populate pre-Session-A baseline.
EOF
  fi
}

main "$@"
