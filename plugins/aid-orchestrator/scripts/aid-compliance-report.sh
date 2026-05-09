#!/usr/bin/env bash
# aid-compliance-report.sh — Pre/post Session A+B compliance aggregator.
#
# Reads all compliance.json files under one or more evidence roots and
# emits a trend table comparing deployment eras. Designed to be the data
# source for "Session A/B delivered X% improvement on dimension Y" claims.
#
# Read-only. Extended in v2.18.0 with --era semantic names, --compare, and
# --reflect force_override triple-condition detection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

# Hardcoded dimension list for Session A trend table (backward compat).
# Session B adds verifier_outputs as object — handled separately in reflect
# via auto-discovery (jq .checks | keys[]).
SESSION_A_DIMENSIONS=(branch_correct execution_yaml_present gates_generated_by)

usage() {
  cat <<EOF
Usage: $(basename "$0") [--since YYYY-MM-DD] [--era ERA] [--compare ERA1,ERA2]
                       [--output md|json] [--evidence-roots "path1 path2 ..."] [--reflect]

Aggregates compliance.json files into a deployment-era trend report.

Options:
  --since YYYY-MM-DD       Filter by .evaluated_at >= since (inclusive).
  --era ERA                Filter by deploy_era. Values:
                             pre-session-a, post-session-a, post-session-b,
                             latest (default, auto-resolves newest era in data),
                             all    (all eras),
                             pre    (alias: pre-session-a),
                             post   (alias: post-session-a + post-session-b),
                             both   (alias: all)
  --compare ERA1,ERA2      Side-by-side trend table for two eras. Overrides --era.
  --output md|json         md (default) renders pivot table; json emits grouped output.
  --evidence-roots "..."   Space-separated paths. Defaults to 5 ecosystem projects.
  --reflect                Append per-dimension breakdown + force_override triple-condition
                           pattern detection. Implies --output md.
  -h, --help               This help.

Examples:
  $(basename "$0")
  $(basename "$0") --since 2026-04-01 --era post-session-b
  $(basename "$0") --compare post-session-a,post-session-b
  $(basename "$0") --reflect --era post-session-b
  $(basename "$0") --era latest --reflect
  $(basename "$0") --output json | jq '.post_session_b | length'
EOF
}

# Extract a compliance check dimension value, handling object schema (verifier_outputs).
# For objects: returns .aggregate. For boolean/null: returns as-is.
_dim_value() {
  local checks_json=$1 dim=$2
  echo "$checks_json" | jq --arg d "$dim" \
    '.[$d] | if type == "object" then .aggregate else . end'
}

# Compute force override statistics for a given era.
compute_force_stat() {
  local stat=$1 era=$2 all=$3
  local total
  total=$(jq --arg e "$era" '[.[] | select(.deploy_era==$e)] | length' <<< "$all")
  if (( total == 0 )); then echo "0"; return 0; fi

  case "$stat" in
    avg)
      jq -r --arg e "$era" --argjson t "$total" \
        '[.[] | select(.deploy_era==$e) | (.force_override_count // 0)] | add // 0
         | (. / $t * 10 | round | . / 10 | tostring)' \
        <<< "$all" 2>/dev/null || echo "0"
      ;;
    max)
      jq -r --arg e "$era" \
        '[.[] | select(.deploy_era==$e) | (.force_override_count // 0)] | max // 0' \
        <<< "$all" 2>/dev/null || echo "0"
      ;;
    pct_with_override)
      local with_override
      with_override=$(jq -r --arg e "$era" \
        '[.[] | select(.deploy_era==$e and (.force_override_count // 0) > 0)] | length' \
        <<< "$all" 2>/dev/null || echo "0")
      echo $(( total > 0 ? with_override * 100 / total : 0 ))
      ;;
  esac
}

# Render side-by-side era comparison table (--compare ERA1,ERA2).
render_comparison() {
  local compare=$1 all=$2
  local era1 era2
  era1=$(echo "$compare" | cut -d, -f1)
  era2=$(echo "$compare" | cut -d, -f2)

  if [[ -z "$era1" || -z "$era2" ]]; then
    echo "ERROR: --compare requires two comma-separated era names (e.g., post-session-a,post-session-b)" >&2
    exit 1
  fi

  local total1 total2
  total1=$(jq --arg e "$era1" '[.[] | select(.deploy_era==$e)] | length' <<< "$all")
  total2=$(jq --arg e "$era2" '[.[] | select(.deploy_era==$e)] | length' <<< "$all")

  cat <<EOF
## Era Comparison: ${era1} vs ${era2}

n=${era1}: ${total1} EPICs | n=${era2}: ${total2} EPICs

| Dimension | ${era1} pass% | ${era2} pass% | Δ |
|-----------|$(printf -- '-%.0s' $(seq 1 ${#era1}))---:|$(printf -- '-%.0s' $(seq 1 ${#era2}))----:|----:|
EOF

  # Auto-discover dimensions from first compliance.json (handles both bool + object).
  local dimensions
  dimensions=$(jq -r 'map(.checks) | add | if . then keys[] else empty end' <<< "$all" 2>/dev/null | sort -u)

  for dim in $dimensions; do
    local pass1 pass2 pct1 pct2 delta
    pass1=$(jq --arg e "$era1" --arg d "$dim" \
      '[.[] | select(.deploy_era==$e) | .checks[$d] | if type == "object" then .aggregate else . end]
       | map(select(.==true)) | length' <<< "$all")
    pass2=$(jq --arg e "$era2" --arg d "$dim" \
      '[.[] | select(.deploy_era==$e) | .checks[$d] | if type == "object" then .aggregate else . end]
       | map(select(.==true)) | length' <<< "$all")
    pct1=$(( total1 > 0 ? pass1 * 100 / total1 : 0 ))
    pct2=$(( total2 > 0 ? pass2 * 100 / total2 : 0 ))
    delta=$(( pct2 - pct1 ))
    printf "| %s | %d%% | %d%% | %+d%% |\n" "$dim" "$pct1" "$pct2" "$delta"
  done

  cat <<EOF

## Force Overrides

| Metric                   | ${era1} | ${era2} |
|--------------------------|$(printf -- '-%.0s' $(seq 1 ${#era1}))--:|$(printf -- '-%.0s' $(seq 1 ${#era2}))---:|
EOF

  for stat in avg max pct_with_override; do
    local v1 v2
    v1=$(compute_force_stat "$stat" "$era1" "$all")
    v2=$(compute_force_stat "$stat" "$era2" "$all")
    printf "| %s | %s | %s |\n" "$stat" "$v1" "$v2"
  done
}

# Emit force_override triple-condition detection section for --reflect.
# Called after the per-dimension reflect table. Reports on post-session-b data only.
emit_reflect_force_override() {
  local all=$1
  local total
  total=$(jq '[.[] | select(.deploy_era=="post-session-b")] | length' <<< "$all")

  if (( total == 0 )); then
    cat <<EOF

## Force Overrides (post-session-b)

_No post-session-b EPICs found. Deploy Session B and run ≥1 EPIC to populate._
EOF
    return 0
  fi

  # avg_x100 = sum(force_override_count) * 100 / total to avoid float (bc may not be installed)
  local avg_x100 max_val pct_with_force_x100 low_quality
  avg_x100=$(jq -r --argjson t "$total" \
    '[.[] | select(.deploy_era=="post-session-b") | (.force_override_count // 0)]
     | add // 0 | (. * 100 / ($t | if . == 0 then 1 else . end)) | floor' \
    <<< "$all" 2>/dev/null | awk '{print int($1)}' || echo "0")
  max_val=$(jq '[.[] | select(.deploy_era=="post-session-b") | (.force_override_count // 0)] | max // 0' \
    <<< "$all" 2>/dev/null || echo "0")
  local with_force
  with_force=$(jq '[.[] | select(.deploy_era=="post-session-b" and (.force_override_count // 0) > 0)] | length' \
    <<< "$all" 2>/dev/null || echo "0")
  pct_with_force_x100=$(( total > 0 ? with_force * 100 / total : 0 ))
  low_quality=$(jq '[.[] | .force_override_reasons // [] | .[]
                    | select(. != "<pre-session-b legacy>")
                    | select((length < 30) or test("^(fix|bug|needed|done)$"; "i"))]
                   | length' <<< "$all" 2>/dev/null || echo "0")

  # Triple-condition pattern: avg > 1 OR max > 3 OR pct_with_force > 30% OR low_quality > 0
  local pattern="✅ green"
  if (( avg_x100 > 100 )) || (( max_val > 3 )) || (( pct_with_force_x100 > 30 )) || (( low_quality > 0 )); then
    pattern="🔴 SYSTEMATIC"
  fi

  local avg_display
  avg_display=$(( avg_x100 / 100 )).$(( avg_x100 % 100 / 10 ))

  # Per-condition status indicators
  local avg_status max_status pct_status lq_status
  avg_status=$(( avg_x100 > 100 ? 0 : 1 )) && avg_st="✅" || avg_st="🔴"
  (( avg_x100 <= 100 )) && avg_st="✅" || avg_st="🔴"
  (( max_val <= 3 ))    && max_st="✅" || max_st="🔴"
  (( pct_with_force_x100 <= 30 )) && pct_st="✅" || pct_st="🔴"
  (( low_quality == 0 )) && lq_st="✅" || lq_st="🔴"

  cat <<EOF

## Force Overrides (post-session-b, n=${total})

| Metric                       | Value | Threshold | Status |
|------------------------------|------:|----------:|:-------|
| avg per EPIC                 | ${avg_display} | ≤ 1 | ${avg_st} |
| max per single EPIC          | ${max_val} | ≤ 3 | ${max_st} |
| % EPICs with ≥1 override     | ${pct_with_force_x100}% | ≤ 30% | ${pct_st} |
| low-quality reasons count    | ${low_quality} | 0 | ${lq_st} |

Combined pattern: **${pattern}**
EOF

  if [[ "$pattern" == *"SYSTEMATIC"* ]]; then
    cat <<EOF

🔴 **STOP — investigate force_override usage before Session C brainstorm.**
At least one triple-condition threshold is breached. This indicates agents or PM
are systematically bypassing FSM preconditions.

Steps:
  1. Inspect timelines: \`jq -r 'select(.event=="fsm_force_override") | .reason' timeline.jsonl\`
  2. Check low-quality reasons: reasons < 30 chars or matching ^(fix|bug|needed|done) pattern.
  3. Identify if bypass is concentrated in one command (\`.caller\` field).
  4. Either patch the failing precondition OR enforce stricter review on force_override PRs.
EOF
  fi
}

main() {
  local since="" era="latest" output="md" reflect=false compare=""
  local -a evidence_roots=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since)          since="$2"; shift 2 ;;
      --era)            era="$2"; shift 2 ;;
      --compare)        compare="$2"; shift 2 ;;
      --output)         output="$2"; shift 2 ;;
      --evidence-roots) read -ra evidence_roots <<< "$2"; shift 2 ;;
      --reflect)        reflect=true; shift ;;
      -h|--help)        usage; exit 0 ;;
      *)                echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  # Backward compat aliases (M2 — pre-Session-B callers use pre|post|both)
  case "$era" in
    pre)   era="pre-session-a" ;;
    post)  era="post-session-a,post-session-b" ;;
    both)  era="all" ;;
    *) ;;
  esac

  # Validate era (after alias resolution)
  case "$era" in
    pre-session-a|post-session-a|post-session-b|latest|all|post-session-a,post-session-b) ;;
    *) echo "ERROR: --era must be pre-session-a, post-session-a, post-session-b, latest, all, pre, post, or both" >&2; exit 1 ;;
  esac

  case "$output" in
    md|json) ;;
    *) echo "ERROR: --output must be 'md' or 'json'" >&2; exit 1 ;;
  esac

  if "$reflect" && [[ "$output" == "json" ]]; then
    echo "ERROR: --reflect requires --output md (default). JSON output is unaffected." >&2
    exit 1
  fi

  # --compare overrides --era: include all eras so both sides have data
  if [[ -n "$compare" ]]; then
    era="all"
  fi

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
  local tmp_ndjson; tmp_ndjson=$(mktemp)
  trap 'rm -f "${tmp_ndjson:-}" 2>/dev/null || true' EXIT

  for root in "${evidence_roots[@]}"; do
    if [[ ! -d "$root" ]]; then
      log_warn "Evidence root not found, skipping: $root" >&2
      continue
    fi
    while IFS= read -r f; do
      jq -c '.' "$f" 2>/dev/null >> "$tmp_ndjson" || log_warn "Skipping invalid JSON: $f"
    done < <(find "$root" -mindepth 3 -maxdepth 3 -name "compliance.json" 2>/dev/null)
  done

  # Resolve "latest" dynamically from compliance.json data (M4 — no hardcode).
  if [[ "$era" == "latest" ]]; then
    local latest_era
    latest_era=$(jq -rs '[.[] | .deploy_era] | unique | map(select(startswith("post-session-"))) | sort | last // "post-session-a"' \
      "$tmp_ndjson" 2>/dev/null || echo "post-session-a")
    era="${latest_era}"
  fi

  # Build era filter array for jq
  local era_filter_json
  case "$era" in
    all) era_filter_json='["pre-session-a","post-session-a","post-session-b"]' ;;
    post-session-a,post-session-b) era_filter_json='["post-session-a","post-session-b"]' ;;
    *) era_filter_json='["'"$era"'"]' ;;
  esac

  # Apply --since + --era filters
  local all_compliance
  all_compliance=$(jq -s \
    --arg since "$since" \
    --argjson eras "$era_filter_json" \
    'map(
       select(($since == "" or (.evaluated_at >= $since))
              and (.deploy_era as $de | $eras | any(. == $de)))
     )' "$tmp_ndjson")

  # --compare: delegate to side-by-side renderer and exit
  if [[ -n "$compare" ]]; then
    render_comparison "$compare" "$all_compliance"
    return 0
  fi

  if [[ "$output" == "json" ]]; then
    jq --argjson all "$all_compliance" -n \
       '{
          "pre-session-a":   [$all[] | select(.deploy_era == "pre-session-a")],
          "post-session-a":  [$all[] | select(.deploy_era == "post-session-a")],
          "post-session-b":  [$all[] | select(.deploy_era == "post-session-b")]
        }'
    return 0
  fi

  # ─── Markdown trend table ──────────────────────────────────────────
  local pre_count post_a_count post_b_count
  pre_count=$(jq -r '[.[] | select(.deploy_era == "pre-session-a")] | length' <<< "$all_compliance")
  post_a_count=$(jq -r '[.[] | select(.deploy_era == "post-session-a")] | length' <<< "$all_compliance")
  post_b_count=$(jq -r '[.[] | select(.deploy_era == "post-session-b")] | length' <<< "$all_compliance")

  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat <<EOF
# AID Compliance Trend Report

Generated:             ${now}
Filter --since:        ${since:-<none>}
Filter --era:          ${era}
Pre-Session-A:         ${pre_count} EPICs
Post-Session-A:        ${post_a_count} EPICs
Post-Session-B:        ${post_b_count} EPICs

| Dimension | Pre-A (%) | Post-A (%) | Post-B (%) | Δ (A→B) |
|-----------|----------:|-----------:|-----------:|--------:|
EOF

  local dim
  for dim in "${SESSION_A_DIMENSIONS[@]}"; do
    local pre_pass post_a_pass post_b_pass pre_pct post_a_pct post_b_pct delta
    pre_pass=$(jq -r --arg d "$dim" \
      '[.[] | select(.deploy_era == "pre-session-a") | .checks[$d]] | map(select(. == true)) | length' \
      <<< "$all_compliance")
    post_a_pass=$(jq -r --arg d "$dim" \
      '[.[] | select(.deploy_era == "post-session-a") | .checks[$d]] | map(select(. == true)) | length' \
      <<< "$all_compliance")
    post_b_pass=$(jq -r --arg d "$dim" \
      '[.[] | select(.deploy_era == "post-session-b") | .checks[$d]
        | if type == "object" then .aggregate else . end] | map(select(. == true)) | length' \
      <<< "$all_compliance")
    pre_pct=$(( pre_count > 0 ? pre_pass * 100 / pre_count : 0 ))
    post_a_pct=$(( post_a_count > 0 ? post_a_pass * 100 / post_a_count : 0 ))
    post_b_pct=$(( post_b_count > 0 ? post_b_pass * 100 / post_b_count : 0 ))
    delta=$(( post_a_count > 0 || post_b_count > 0 ? post_b_pct - post_a_pct : 0 ))
    printf "| %s | %d%% | %d%% | %d%% | %+d%% |\n" \
      "$dim" "$pre_pct" "$post_a_pct" "$post_b_pct" "$delta"
  done

  # verifier_outputs aggregate row (Session B+)
  if (( post_b_count > 0 )); then
    local vo_pre_pct=0 vo_post_a_pct=0 vo_post_b_pass vo_post_b_pct vo_delta
    vo_post_b_pass=$(jq -r \
      '[.[] | select(.deploy_era == "post-session-b")
        | .checks.verifier_outputs | if type == "object" then .aggregate else . end]
       | map(select(. == true)) | length' <<< "$all_compliance")
    vo_post_b_pct=$(( post_b_count > 0 ? vo_post_b_pass * 100 / post_b_count : 0 ))
    vo_delta=$(( vo_post_b_pct - vo_post_a_pct ))
    printf "| %s | %d%% | %d%% | %d%% | %+d%% |\n" \
      "verifier_outputs.aggregate" "$vo_pre_pct" "$vo_post_a_pct" "$vo_post_b_pct" "$vo_delta"
  fi

  local total_all
  total_all=$(( pre_count + post_a_count + post_b_count ))
  if (( total_all == 0 )); then
    cat <<EOF

_No compliance.json files found under requested evidence roots (and filter)._
Run \`aid-compliance-backfill.sh --deploy-date YYYY-MM-DDTHH:MM:SSZ\` first
to populate pre-Session-A baseline.
EOF
    return 0
  fi

  # ─── --reflect: per-dimension breakdown + force_override triple-condition ──
  if ! "$reflect"; then
    return 0
  fi

  # Determine reflect era: use post-session-b if data has it, else post-session-a
  local reflect_era reflect_n
  if (( post_b_count > 0 )); then
    reflect_era="post-session-b"
    reflect_n=$post_b_count
  else
    reflect_era="post-session-a"
    reflect_n=$post_a_count
  fi

  if (( reflect_n == 0 )); then
    cat <<EOF

## Per-Dimension Reflect (${reflect_era})

_No ${reflect_era} EPICs found. Run at least 1 EPIC after deploy to populate
\`compliance.json\` files before \`--reflect\` produces meaningful output._
EOF
    return 0
  fi

  cat <<EOF

## Per-Dimension Reflect (${reflect_era}, n=${reflect_n})

| Dimension | Pass | Fail | Null | % Pass | Bar | Pattern |
|-----------|----:|----:|----:|-------:|:----|:--------|
EOF

  local any_systematic=false any_investigate=false

  # Build dimension list: SESSION_A_DIMENSIONS + verifier_outputs sub-fields if object schema
  local reflect_dims=("${SESSION_A_DIMENSIONS[@]}")

  # Auto-discover verifier_outputs sub-dimensions for post-session-b
  if [[ "$reflect_era" == "post-session-b" ]]; then
    local vo_sub_dims
    vo_sub_dims=$(jq -r \
      '[.[] | select(.deploy_era=="post-session-b") | .checks.verifier_outputs
        | if type == "object" then keys[] else empty end]
       | unique[]' <<< "$all_compliance" 2>/dev/null || true)
    while IFS= read -r sub; do
      [[ -n "$sub" ]] && reflect_dims+=("verifier_outputs.${sub}")
    done <<< "$vo_sub_dims"
  fi

  for dim in "${reflect_dims[@]}"; do
    local pass_n fail_n null_n pct

    # Handle nested verifier_outputs.* sub-dimensions
    if [[ "$dim" == verifier_outputs.* ]]; then
      local sub_key="${dim#verifier_outputs.}"
      pass_n=$(jq -r --arg e "$reflect_era" --arg k "$sub_key" \
        '[.[] | select(.deploy_era==$e)
          | .checks.verifier_outputs | if type == "object" then .[$k] else null end]
         | map(select(.==true))  | length' <<< "$all_compliance")
      fail_n=$(jq -r --arg e "$reflect_era" --arg k "$sub_key" \
        '[.[] | select(.deploy_era==$e)
          | .checks.verifier_outputs | if type == "object" then .[$k] else null end]
         | map(select(.==false)) | length' <<< "$all_compliance")
      null_n=$(jq -r --arg e "$reflect_era" --arg k "$sub_key" \
        '[.[] | select(.deploy_era==$e)
          | .checks.verifier_outputs | if type == "object" then .[$k] else null end]
         | map(select(. == null)) | length' <<< "$all_compliance")
    else
      pass_n=$(jq -r --arg e "$reflect_era" --arg d "$dim" \
        '[.[] | select(.deploy_era==$e) | .checks[$d]
          | if type == "object" then .aggregate else . end]
         | map(select(.==true))  | length' <<< "$all_compliance")
      fail_n=$(jq -r --arg e "$reflect_era" --arg d "$dim" \
        '[.[] | select(.deploy_era==$e) | .checks[$d]
          | if type == "object" then .aggregate else . end]
         | map(select(.==false)) | length' <<< "$all_compliance")
      null_n=$(jq -r --arg e "$reflect_era" --arg d "$dim" \
        '[.[] | select(.deploy_era==$e) | .checks[$d]
          | if type == "object" then .aggregate else . end]
         | map(select(. == null)) | length' <<< "$all_compliance")
    fi

    pct=$(( reflect_n > 0 ? pass_n * 100 / reflect_n : 0 ))

    local filled bar=""
    filled=$(( pct / 10 ))
    local i
    for ((i=0; i<10; i++)); do
      if (( i < filled )); then bar+="█"; else bar+="░"; fi
    done

    local pattern
    if   (( fail_n == 0 )); then pattern="✅ green"
    elif (( fail_n == 1 )); then pattern="⚠️ INVESTIGATE (1/${reflect_n} fail)"; any_investigate=true
    else                         pattern="🔴 SYSTEMATIC (${fail_n}/${reflect_n} fail)"; any_systematic=true
    fi

    printf "| %s | %d | %d | %d | %d%% | \`%s\` | %s |\n" \
      "$dim" "$pass_n" "$fail_n" "$null_n" "$pct" "$bar" "$pattern"
  done

  cat <<EOF

### Recommended next action

EOF

  if "$any_systematic"; then
    cat <<EOF
🔴 **STOP — investigate before next Session brainstorm.** At least one dimension
shows a systematic failure pattern (≥ 2 fails in ${reflect_era} EPICs). Session
enforcement has a hole on that dimension.

Steps:
  1. Inspect failing EPICs: \`jq -r 'select(.checks.<DIM> == false) | .epic_id' .../compliance.json\`
  2. Identify root cause — new bypass route, fixture bug, or enforcement gap?
  3. Either patch current Session (follow-up plan) OR fold into next Session scope.
EOF
  elif "$any_investigate"; then
    cat <<EOF
⚠️ **Proceed with caution.** One dimension has a single fail. This may be one-off
variance or the start of a pattern.

Steps:
  1. Inspect the failing EPIC manually — confirm root cause is non-systemic.
  2. If next 2-3 EPICs hit the same dimension → escalate to 🔴 SYSTEMATIC.
  3. If non-recurring → safe to brainstorm next Session.
EOF
  else
    cat <<EOF
✅ **Green light for next Session brainstorm.** All dimensions pass consistently
across ${reflect_n} ${reflect_era} EPICs. Foundation is solid; no bypass patterns detected.
EOF
  fi

  # Force override section (only for post-session-b data)
  emit_reflect_force_override "$all_compliance"
}

main "$@"
