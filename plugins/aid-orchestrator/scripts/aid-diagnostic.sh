#!/usr/bin/env bash
# aid-diagnostic.sh — Reusable forensic analyzer (Krok 0 logic productized).
#
# Walks one or more --evidence-root paths and reports per-run state +
# aggregate frequency tables for AID v3 compliance dimensions.
#
# Output modes:
#   md   — human-readable markdown (default), suitable for paste into PR/issue
#   json — array of per-run objects, suitable for `jq` queries / pipelines
#
# Designed to run repeatedly (no side effects, read-only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--evidence-root <path>] [--output md|json] [--limit N]

Walk one or more evidence roots and report per-run state + aggregates.

Options:
  --evidence-root <path>   Repeatable. Defaults to 5 ekosystem projects under
                           /opt/eco/projects/{vulcan,sousto-na-miru,krok,
                           wan,aid-orchestrator}/.aid-o/work/evidence
  --output md|json         Report format. md (default) or json.
  --limit N                Process at most N runs total (debugging shortcut).
  -h, --help               This help.

Reported sections (markdown mode):
  - File counts (fsm-state.yaml, timeline.jsonl, gates_report.json, compliance.json,
    curator-report, audit-report, step-N-verify.md)
  - Branch hygiene distribution (task/E-* vs main vs other)
  - Gate authenticity (_generated_by present vs hand-written/missing)
  - Compliance overall verdict distribution
  - Top FSM fail reasons (fsm_precondition_fail + fsm_increment_fail + fsm_done_advance_fail)

Examples:
  $(basename "$0")                                          # all defaults
  $(basename "$0") --evidence-root /tmp/proj/.aid-o/work/evidence
  $(basename "$0") --output json | jq '[.[] | select(.has_compliance == false)]'
EOF
}

# Per-run collector — emits one compact JSON object on stdout.
collect_run() {
  local run_dir=$1
  local epic_id run_id state_file timeline gates_report compliance curator audit
  epic_id=$(basename "$(dirname "$run_dir")")
  run_id=$(basename "$run_dir")
  state_file="${run_dir}/fsm-state.yaml"
  [[ ! -f "$state_file" && -f "${run_dir}/state.yaml" ]] && state_file="${run_dir}/state.yaml"
  timeline="${run_dir}/timeline.jsonl"
  gates_report="${run_dir}/gates/gates_report.json"
  compliance="${run_dir}/compliance.json"
  curator="${run_dir}/curator-report.md"
  audit="${run_dir}/audit-report.md"

  local branch="" branch_kind="missing"
  local fsm_state="${run_dir}/fsm-state.yaml"
  if [[ -f "$fsm_state" ]]; then
    branch=$(grep '^branch:' "$fsm_state" 2>/dev/null | awk '{print $2}' || echo "")
    if [[ "$branch" =~ ^task/E- ]]; then
      branch_kind="task_e_prefix"
    elif [[ "$branch" =~ ^task/ ]]; then
      branch_kind="task_other_prefix"
    elif [[ "$branch" == "main" || "$branch" == "master" || "$branch" == "develop" ]]; then
      branch_kind="$branch"
    elif [[ -n "$branch" ]]; then
      branch_kind="other"
    fi
  fi

  local has_state has_timeline has_gates has_compliance has_curator has_audit verify_count
  has_state=$([[ -f "$state_file" ]] && echo true || echo false)
  has_timeline=$([[ -f "$timeline" ]] && echo true || echo false)
  has_gates=$([[ -f "$gates_report" ]] && echo true || echo false)
  has_compliance=$([[ -f "$compliance" ]] && echo true || echo false)
  has_curator=$([[ -f "$curator" || -f "${run_dir}/curator-report.yaml" ]] && echo true || echo false)
  has_audit=$([[ -f "$audit" || -f "${run_dir}/audit-report.yaml" ]] && echo true || echo false)
  verify_count=$(find "$run_dir" -maxdepth 1 -name 'step-*-verify.md' 2>/dev/null | wc -l)

  local gates_genby=false gates_overall="missing"
  if [[ "$has_gates" == "true" ]]; then
    if jq -e '._generated_by' "$gates_report" >/dev/null 2>&1; then
      gates_genby=true
    fi
    gates_overall=$(jq -r '.overall // "unknown"' "$gates_report" 2>/dev/null)
  fi

  local compliance_overall="missing" compliance_era="missing"
  if [[ "$has_compliance" == "true" ]]; then
    compliance_overall=$(jq -r '.overall // "unknown"' "$compliance" 2>/dev/null)
    compliance_era=$(jq -r '.deploy_era // "unknown"' "$compliance" 2>/dev/null)
  fi

  jq -nc \
    --arg epic "$epic_id" --arg run "$run_id" \
    --arg branch "$branch" --arg bk "$branch_kind" \
    --argjson hs "$has_state" --argjson ht "$has_timeline" --argjson hg "$has_gates" \
    --argjson hc "$has_compliance" --argjson hcu "$has_curator" --argjson ha "$has_audit" \
    --argjson vc "$verify_count" \
    --argjson ggb "$gates_genby" --arg go "$gates_overall" \
    --arg co "$compliance_overall" --arg ce "$compliance_era" \
    '{
      epic_id: $epic, run_id: $run,
      branch: $branch, branch_kind: $bk,
      has_state_yaml: $hs, has_timeline: $ht, has_gates_report: $hg,
      has_compliance: $hc, has_curator_report: $hcu, has_audit_report: $ha,
      verify_files_count: $vc,
      gates_generated_by: $ggb, gates_overall: $go,
      compliance_overall: $co, compliance_deploy_era: $ce
    }'
}

# Emit all FSM fail event reasons from a single run's timeline.
# Covers fsm_precondition_fail (gate/CP prereqs), fsm_increment_fail (verify
# file format errors — the most common category), and fsm_done_advance_fail.
collect_fsm_fail_reasons() {
  local timeline=$1
  [[ ! -f "$timeline" ]] && return 0
  jq -r 'select(.event | test("^fsm_precondition_fail$|^fsm_increment_fail$|^fsm_done_advance_fail$")) | .reason // "unspecified"' "$timeline" 2>/dev/null
}

main() {
  local output="md" limit=0
  local -a evidence_roots=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --evidence-root) evidence_roots+=("$2"); shift 2 ;;
      --output)        output="$2"; shift 2 ;;
      --limit)         limit="$2"; shift 2 ;;
      -h|--help)       usage; exit 0 ;;
      *)               echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
  done

  if [[ "$output" != "md" && "$output" != "json" ]]; then
    echo "ERROR: --output must be 'md' or 'json'" >&2; exit 1
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

  # Collect all runs into a tmp NDJSON file.
  # File-scope (not local) so the EXIT trap can reference them under `set -u`.
  tmp=$(mktemp)
  reasons_tmp=$(mktemp)
  trap 'rm -f "${tmp:-}" "${reasons_tmp:-}" 2>/dev/null || true' EXIT

  local processed=0
  for root in "${evidence_roots[@]}"; do
    if [[ ! -d "$root" ]]; then
      log_warn "Evidence root not found, skipping: $root" >&2
      continue
    fi
    while IFS= read -r epic_dir; do
      [[ ! -d "$epic_dir" ]] && continue
      while IFS= read -r run_dir; do
        if (( limit > 0 && processed >= limit )); then break 3; fi
        collect_run "$run_dir" >> "$tmp"
        collect_fsm_fail_reasons "${run_dir}/timeline.jsonl" >> "$reasons_tmp" || true
        processed=$((processed + 1))
      done < <(find "$epic_dir" -maxdepth 1 -mindepth 1 -type d -name "R-*")
    done < <(find "$root" -maxdepth 1 -mindepth 1 -type d -name "E-*")
  done

  if (( processed == 0 )); then
    if [[ "$output" == "md" ]]; then
      echo "# AID Diagnostic Report"
      echo
      echo "_No EPIC run dirs found under requested evidence roots._"
    else
      echo "[]"
    fi
    return 0
  fi

  if [[ "$output" == "json" ]]; then
    jq -s '.' "$tmp"
    return 0
  fi

  # ─── Markdown rendering ────────────────────────────────────────────
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat <<EOF
# AID Diagnostic Report

Generated: ${now}
Evidence roots: ${evidence_roots[*]}
Runs analyzed: ${processed}

## File Counts (per-artifact presence across all runs)

| Artifact | Count | % of runs |
|----------|------:|----------:|
EOF
  local field
  for field in has_state_yaml has_timeline has_gates_report has_compliance has_curator_report has_audit_report; do
    local n pct
    n=$(jq -r --arg f "$field" 'select(.[$f] == true) | .epic_id' "$tmp" | wc -l)
    pct=$(( n * 100 / processed ))
    printf "| %s | %d | %d%% |\n" "$field" "$n" "$pct"
  done

  # Verify-file count distribution
  local verify_total
  verify_total=$(jq -r '.verify_files_count' "$tmp" | awk '{s+=$1} END {print s+0}')
  echo "| step-*-verify.md (total across runs) | ${verify_total} | — |"

  cat <<EOF

## Branch Hygiene (fsm-state.yaml.branch distribution)

| Branch kind | Count | % of runs |
|-------------|------:|----------:|
EOF
  local kind
  for kind in task_e_prefix task_other_prefix main master develop other missing; do
    local n pct
    n=$(jq -r --arg k "$kind" 'select(.branch_kind == $k) | .epic_id' "$tmp" | wc -l)
    [[ $n -eq 0 ]] && continue
    pct=$(( n * 100 / processed ))
    printf "| %s | %d | %d%% |\n" "$kind" "$n" "$pct"
  done

  cat <<EOF

## Gate Authenticity

| Status | Count | % of runs |
|--------|------:|----------:|
EOF
  local n_genby n_no_genby n_no_report pct
  n_genby=$(jq -r 'select(.gates_generated_by == true) | .epic_id' "$tmp" | wc -l)
  n_no_genby=$(jq -r 'select(.has_gates_report == true and .gates_generated_by == false) | .epic_id' "$tmp" | wc -l)
  n_no_report=$(jq -r 'select(.has_gates_report == false) | .epic_id' "$tmp" | wc -l)
  printf "| _generated_by present (real runner output) | %d | %d%% |\n" "$n_genby" $(( n_genby * 100 / processed ))
  printf "| Hand-written / no _generated_by | %d | %d%% |\n" "$n_no_genby" $(( n_no_genby * 100 / processed ))
  printf "| No gates_report.json | %d | %d%% |\n" "$n_no_report" $(( n_no_report * 100 / processed ))

  cat <<EOF

## Compliance Verdicts

| Overall | Count | % of runs |
|---------|------:|----------:|
EOF
  local verdict
  for verdict in pass fail missing unknown; do
    local n pct
    n=$(jq -r --arg v "$verdict" 'select(.compliance_overall == $v) | .epic_id' "$tmp" | wc -l)
    [[ $n -eq 0 ]] && continue
    pct=$(( n * 100 / processed ))
    printf "| %s | %d | %d%% |\n" "$verdict" "$n" "$pct"
  done

  cat <<EOF

## Compliance Deploy Era

| Era | Count | % of runs |
|-----|------:|----------:|
EOF
  local era
  for era in pre-session-a post-session-a post-session-b missing unknown; do
    local n pct
    n=$(jq -r --arg e "$era" 'select(.compliance_deploy_era == $e) | .epic_id' "$tmp" | wc -l)
    [[ $n -eq 0 ]] && continue
    pct=$(( n * 100 / processed ))
    printf "| %s | %d | %d%% |\n" "$era" "$n" "$pct"
  done

  # Top FSM fail reasons (all event types)
  if [[ -s "$reasons_tmp" ]]; then
    cat <<EOF

## Top FSM Fail Reasons

| Reason | Count |
|--------|------:|
EOF
    sort "$reasons_tmp" | uniq -c | sort -rn | head -10 \
      | while read -r count reason; do
          printf "| %s | %d |\n" "$reason" "$count"
        done
  fi
}

main "$@"
