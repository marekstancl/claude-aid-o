#!/usr/bin/env bash
# aid-test-divergence-campaign.sh — P069 Step 7.
#
# Bounded orchestrator: repeatedly invokes aid-test-schedule-divergence-check.sh
# (each call a genuinely fresh disposable clone) until EITHER a required
# number of qualifying (pass:true, matching commit+catalog_fingerprint_set)
# runs are collected, OR a hard budget is exhausted — max_attempts (default
# 6) AND max_wall_clock_seconds (default 3600), whichever hits first. Never
# an unbounded, hours-long blocking loop.
#
# A single individual divergence check disagreeing (genuine pass:false) is a
# REAL FINDING — it counts against max_attempts but is never itself treated
# as evidence_incomplete. That state is reserved for "ran out of budget
# before collecting enough evidence."
#
# Pre-existing qualifying artifacts (from an earlier, possibly-interrupted
# campaign) are counted toward the target BEFORE launching new attempts —
# real prior evidence is never discarded.
#
# The campaign artifact itself is force-tracked via the same `git add -f`
# mechanism as the per-invocation divergence artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SH="${SCRIPT_DIR}/aid-test-schedule-divergence-check.sh"

_die() { echo "aid-test-divergence-campaign.sh: $2" >&2; exit "$1"; }

cmd_run() {
  local project_root="" unit_ids_csv="" mode_tested="" commit="" \
        required=3 max_attempts=6 max_wall_clock_seconds=3600
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="$2"; shift 2 ;;
      --unit-ids) unit_ids_csv="$2"; shift 2 ;;
      --mode-tested) mode_tested="$2"; shift 2 ;;
      --commit) commit="$2"; shift 2 ;;
      --required) required="$2"; shift 2 ;;
      --max-attempts) max_attempts="$2"; shift 2 ;;
      --max-wall-clock-seconds) max_wall_clock_seconds="$2"; shift 2 ;;
      *) _die 2 "run: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$project_root" && -n "$unit_ids_csv" ]] || _die 2 "run: --project-root and --unit-ids are required"
  case "$mode_tested" in observe_parallel|parallel) ;; *) _die 2 "run: --mode-tested must be observe_parallel|parallel" ;; esac
  [[ "$required" =~ ^[0-9]+$ && "$required" -ge 1 ]] || _die 2 "run: --required must be a positive integer"
  [[ "$max_attempts" =~ ^[0-9]+$ && "$max_attempts" -ge 1 ]] || _die 2 "run: --max-attempts must be a positive integer"
  [[ "$max_wall_clock_seconds" =~ ^[0-9]+$ && "$max_wall_clock_seconds" -ge 1 ]] || _die 2 "run: --max-wall-clock-seconds must be a positive integer"

  project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "run: --project-root does not exist"
  git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1 || _die 3 "run: --project-root is not a git repository"

  [[ -n "$commit" ]] || commit="HEAD"
  local commit_sha
  commit_sha="$(git -C "$project_root" rev-parse --verify "${commit}^{commit}" -- 2>/dev/null)" \
    || _die 1 "run: --commit '$commit' does not resolve to a real commit object"

  local evidence_dir="${project_root}/.aid-o/work/evidence/scheduler-divergence"
  mkdir -p "$evidence_dir"

  local -a unit_ids=()
  IFS=',' read -r -a unit_ids <<<"$unit_ids_csv"
  local expected_unit_ids_json; expected_unit_ids_json="$(printf '%s\n' "${unit_ids[@]}" | sort -u | jq -R . | jq -sc .)"

  # Expected catalog_fingerprint_set for THIS exact commit+unit-set — read
  # directly from the commit object (no clone needed just to validate),
  # using the IDENTICAL formula aid-test-schedule-divergence-check.sh uses.
  # Codex review: pre-existing-evidence qualification previously matched
  # only the filename's commit_sha/mode_tested prefix — an artifact for a
  # DIFFERENT unit selection at the SAME commit would incorrectly qualify.
  local catalog_json
  catalog_json="$(git -C "$project_root" show "${commit_sha}:.aid-o/config/test-catalog.yaml" 2>/dev/null | yq -o=json '.' 2>/dev/null)" \
    || _die 3 "run: could not read .aid-o/config/test-catalog.yaml at commit $commit_sha"
  local fp_list="" uid
  for uid in "${unit_ids[@]}"; do
    local fp
    fp="$(jq -r --arg id "$uid" '.run_units[] | select(.run_unit_id == $id) | .runtime.fingerprint' <<<"$catalog_json")"
    [[ -n "$fp" ]] || _die 1 "run: run_unit_id '$uid' not found in the catalog at commit $commit_sha"
    fp_list+="${fp}"$'\n'
  done
  local expected_fingerprint_set
  expected_fingerprint_set="sha256:$(printf '%s' "$fp_list" | sort | sha256sum | cut -d' ' -f1)"

  # _campaign_artifact_qualifies <path> — true only if pass:true AND this
  # exact unit-set AND this exact catalog_fingerprint_set match.
  _campaign_artifact_qualifies() {
    local path="$1"
    [[ -f "$path" ]] || return 1
    local pass uids fps
    pass="$(jq -r '.pass' "$path" 2>/dev/null)"
    uids="$(jq -cS '.selected_unit_ids | sort' "$path" 2>/dev/null)"
    fps="$(jq -r '.catalog_fingerprint_set' "$path" 2>/dev/null)"
    [[ "$pass" == "true" && "$uids" == "$(jq -cS 'sort' <<<"$expected_unit_ids_json")" && "$fps" == "$expected_fingerprint_set" ]]
  }

  # Count PRE-EXISTING qualifying artifacts toward the target first — never
  # discard real prior evidence from an earlier/interrupted campaign.
  local -a qualifying_run_ids=()
  local f
  for f in "$evidence_dir/${commit_sha}-${mode_tested}-"*.json; do
    [[ -f "$f" ]] || continue
    _campaign_artifact_qualifies "$f" && qualifying_run_ids+=("$(jq -r '.run_id' "$f")")
  done

  local started_at_epoch; started_at_epoch="$(date -u +%s)"
  local started_at_iso; started_at_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local attempts_made=0
  local budget_exhausted_reason=""

  while [[ "${#qualifying_run_ids[@]}" -lt "$required" ]]; do
    if [[ "$attempts_made" -ge "$max_attempts" ]]; then
      budget_exhausted_reason="max_attempts"
      break
    fi
    local now_epoch remaining_seconds
    now_epoch="$(date -u +%s)"
    remaining_seconds=$(( max_wall_clock_seconds - (now_epoch - started_at_epoch) ))
    if [[ "$remaining_seconds" -le 0 ]]; then
      budget_exhausted_reason="max_wall_clock"
      break
    fi

    attempts_made=$((attempts_made + 1))
    # Codex review: the wall-clock budget was previously checked only
    # BEFORE launching each attempt — a single slow check could run well
    # past max_wall_clock_seconds before the loop ever noticed. `timeout`
    # bounds THIS attempt to whatever budget remains, making the total
    # campaign wall-clock a real, enforced ceiling, not just a polling
    # interval.
    local check_out check_rc=0
    check_out="$(timeout "${remaining_seconds}s" bash "$CHECK_SH" run --project-root "$project_root" --unit-ids "$unit_ids_csv" \
      --mode-tested "$mode_tested" --commit "$commit_sha" 2>/dev/null)" || check_rc=$?
    if [[ "$check_rc" -eq 124 ]]; then
      # This attempt was killed by `timeout` for exceeding the remaining
      # budget — the loop's own top-of-iteration check will report
      # max_wall_clock on the next pass; nothing to attribute here.
      continue
    fi

    # Codex review: identify the EXACT artifact this attempt wrote via its
    # own machine-parseable stdout line — never a global newest-mtime guess
    # (`ls -t`), which could misattribute an unrelated pre-existing or
    # concurrently-written artifact.
    local artifact_path
    artifact_path="$(grep -o 'ARTIFACT_PATH=.*' <<<"$check_out" | tail -1 | cut -d= -f2-)"
    if [[ -n "$artifact_path" ]] && _campaign_artifact_qualifies "$artifact_path"; then
      qualifying_run_ids+=("$(jq -r '.run_id' "$artifact_path")")
    fi
  done

  if [[ "${#qualifying_run_ids[@]}" -ge "$required" ]]; then
    echo "aid-test-divergence-campaign.sh: collected ${#qualifying_run_ids[@]} qualifying run(s) within budget (${attempts_made} attempt(s)): ${qualifying_run_ids[*]}"
    exit 0
  fi

  # Budget exhausted without enough qualifying evidence — a distinct,
  # terminal, PM-visible state. If the loop exited due to hitting required
  # via a race just above, this path is unreachable; otherwise derive the
  # reason from whichever budget was hit (attempts checked first above).
  [[ -n "$budget_exhausted_reason" ]] || budget_exhausted_reason="max_attempts"

  local campaign_json
  campaign_json="$(jq -nc \
    --arg status "evidence_incomplete" --argjson attempts "$attempts_made" \
    --argjson qualifying "${#qualifying_run_ids[@]}" --arg reason "$budget_exhausted_reason" \
    '{campaign_status:$status, attempts_made:$attempts, qualifying_runs_collected:$qualifying, budget_exhausted_reason:$reason}')"
  local campaign_path="${evidence_dir}/campaign-${mode_tested}-${started_at_iso}.json"
  printf '%s' "$campaign_json" | jq '.' > "$campaign_path"

  if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
    local rel="${campaign_path#"${project_root}"/}"
    git -C "$project_root" add -f -- "$rel"
  fi

  echo "aid-test-divergence-campaign.sh: evidence_incomplete — ${#qualifying_run_ids[@]}/${required} qualifying runs after ${attempts_made} attempt(s), budget_exhausted_reason=${budget_exhausted_reason}" >&2
  exit 2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    run) shift; cmd_run "$@" ;;
    *)
      echo "Usage: aid-test-divergence-campaign.sh run --project-root <path> --unit-ids <id1,id2,...> --mode-tested observe_parallel|parallel [--commit <sha>] [--required 3] [--max-attempts 6] [--max-wall-clock-seconds 3600]" >&2
      exit 1
      ;;
  esac
fi
