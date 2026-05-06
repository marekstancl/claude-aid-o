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
                       [--evidence-roots "path1 path2 ..."] [--reflect]

Aggregates compliance.json files into a pre-vs-post trend report.

Options:
  --since YYYY-MM-DD       Filter by .evaluated_at >= since (inclusive).
                           Format: ISO date (lex compare against ISO 8601 ts).
  --era pre|post|both      Filter by .deploy_era. Default: both.
  --output md|json         md (default) renders pivot table; json emits
                           grouped {pre: [...], post: [...]}.
  --evidence-roots "..."   Space-separated paths. Defaults to 5 ekosystem
                           projects under /opt/eco/projects.
  --reflect                Append per-dimension breakdown with bar chart,
                           pattern detection (✅ / ⚠️ INVESTIGATE / 🔴 SYSTEMATIC),
                           and recommended next action. Lightweight /aid-reflect
                           per AID-013. Implies --output md.
  -h, --help               This help.

Examples:
  $(basename "$0")
  $(basename "$0") --since 2026-04-01 --era post
  $(basename "$0") --reflect --since 2026-05-06
  $(basename "$0") --output json | jq '.post | length'
EOF
}

main() {
  local since="" era="both" output="md" reflect=false
  local -a evidence_roots=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)          since="$2"; shift 2 ;;
      --era)            era="$2"; shift 2 ;;
      --output)         output="$2"; shift 2 ;;
      --evidence-roots) read -ra evidence_roots <<< "$2"; shift 2 ;;
      --reflect)        reflect=true; shift ;;
      -h|--help)        usage; exit 0 ;;
      *)                echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  if "$reflect" && [[ "$output" == "json" ]]; then
    echo "ERROR: --reflect requires --output md (default). JSON output is unaffected." >&2
    exit 1
  fi

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
    return 0
  fi

  # ─── --reflect: per-dimension breakdown + pattern detection ────────
  # Lightweight /aid-reflect (per AID-013). Inspects post-Session-A EPICs only;
  # detects systematic failure patterns (≥ 2 fails on same dimension) and emits
  # a recommended-next-action section. Replaces "stare at aggregate %" with
  # "stare at per-dimension trend" — addresses PM retrospective from P032
  # (aggregate ≥ 80 % can hide a single dimension failing systematically).
  if ! "$reflect"; then
    return 0
  fi

  if (( post_count == 0 )); then
    cat <<EOF

## Per-Dimension Reflect (post-Session-A focus)

_No post-Session-A EPICs found. Run at least 1 EPIC after Session A deploy
(\`aid-fsm.sh init …\` → full FSM cycle → \`done-advance\`) to populate live
\`compliance.json\` files before \`--reflect\` produces meaningful output._
EOF
    return 0
  fi

  cat <<EOF

## Per-Dimension Reflect (post-Session-A, n=${post_count})

| Dimension | Pass | Fail | Null | % Pass | Bar | Pattern |
|-----------|----:|----:|----:|-------:|:----|:--------|
EOF

  local any_systematic=false any_investigate=false
  for dim in "${SESSION_A_DIMENSIONS[@]}"; do
    local post_pass post_fail post_null pct
    post_pass=$(jq -r --arg d "$dim" \
      '[.[] | select(.deploy_era=="post-session-a") | .checks[$d]] | map(select(.==true))  | length' \
      <<< "$all_compliance")
    post_fail=$(jq -r --arg d "$dim" \
      '[.[] | select(.deploy_era=="post-session-a") | .checks[$d]] | map(select(.==false)) | length' \
      <<< "$all_compliance")
    post_null=$(jq -r --arg d "$dim" \
      '[.[] | select(.deploy_era=="post-session-a") | .checks[$d]] | map(select(.==null))  | length' \
      <<< "$all_compliance")
    pct=$(( post_count > 0 ? post_pass * 100 / post_count : 0 ))

    # 10-char text bar chart (each cell = 10 %).
    local filled=$(( pct / 10 )) bar=""
    local i
    for ((i=0; i<10; i++)); do
      if (( i < filled )); then bar+="█"; else bar+="░"; fi
    done

    # Pattern label per PM retrospective threshold (P032 follow-up):
    #   0 fails → ✅
    #   1 fail  → ⚠️ INVESTIGATE  (could be one-off)
    #   ≥ 2 fails → 🔴 SYSTEMATIC  (pattern)
    local pattern
    if   (( post_fail == 0 )); then pattern="✅ green"
    elif (( post_fail == 1 )); then pattern="⚠️ INVESTIGATE (1/${post_count} fail)"; any_investigate=true
    else                            pattern="🔴 SYSTEMATIC (${post_fail}/${post_count} fail)"; any_systematic=true
    fi

    printf "| %s | %d | %d | %d | %d%% | \`%s\` | %s |\n" \
      "$dim" "$post_pass" "$post_fail" "$post_null" "$pct" "$bar" "$pattern"
  done

  cat <<EOF

### Recommended next action

EOF

  if "$any_systematic"; then
    cat <<EOF
🔴 **STOP — investigate before Session B brainstorm.** At least one dimension
shows a systematic failure pattern (≥ 2 fails in post-Session-A EPICs). This
is not random variance; Session A enforcement has a hole on that dimension.

Steps:
  1. Run \`aid-diagnostic.sh --since <deploy-date> --output md\` and look for
     new cheat patterns in the failing dimension's EPICs.
  2. Inspect the failing EPICs manually:
     \`jq -r 'select(.checks.<DIM> == false) | .epic_id' .../compliance.json\`
  3. Identify root cause — agent found new bypass route, fixture bug, or genuine
     enforcement gap?
  4. Either patch Session A (small follow-up plan) OR fold the new pattern
     into Session B scope BEFORE brainstorming.

Do NOT proceed to Session B brainstorm until the failing dimension is green.
EOF
  elif "$any_investigate"; then
    cat <<EOF
⚠️ **Proceed with caution.** One dimension has a single fail in post-Session-A
EPICs. This may be one-off variance (test fixture issue, race condition,
manual PM intervention, …) or the start of a pattern.

Steps:
  1. Inspect the failing EPIC manually — confirm root cause is non-systemic.
  2. If next 2-3 EPICs hit the same dimension → escalate to 🔴 SYSTEMATIC.
  3. If non-recurring → safe to brainstorm Session B.

Session B brainstorm is OK to start; track the flagged dimension closely.
EOF
  else
    cat <<EOF
✅ **Green light for Session B.** All Session A dimensions pass consistently
across ${post_count} post-deploy EPICs. Foundation is solid; no bypass patterns
detected.

Recommended next steps before \`/aid-plan brainstorm\` for Session B:
  1. Run \`aid-diagnostic.sh --since <deploy-date>\` (round 0.b — look for
     NEW cheat surfaces that emerged after Session A deploy).
  2. Compare with original Krok 0 findings; document new patterns in
     \`docs/plans/AID-v3-diagnostic-findings-post-A.md\`.
  3. \`/aid-plan brainstorm "Session B — CP2/CP3 verifier dispatch enforcement"\`.
EOF
  fi
}

main "$@"
