#!/usr/bin/env bash
# aid-run-gates.sh — Deterministic gate runner
# Usage:
#   aid-run-gates.sh run-gate <gate_name> <command> <timeout_s> <log_file>
#   aid-run-gates.sh run-all <execution_yaml> <epic_id> <run_id> [timeline_file]

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/aid-stage-log.sh"

run_gate() {
  local gate_name="$1"
  local command="$2"
  local timeout_s="${3:-60}"
  local log_file="${4:-/dev/null}"

  local start_ms
  start_ms=$(date +%s%3N)

  local output exit_code=0
  output=$(LC_ALL=C timeout "$timeout_s" bash -c "$command" 2>&1) || exit_code=$?

  local end_ms
  end_ms=$(date +%s%3N)
  local duration_ms=$(( end_ms - start_ms ))

  local result="pass"
  [[ $exit_code -ne 0 ]] && result="fail"

  # Truncate output to 2000 chars for JSON safety
  local output_truncated="${output:0:2000}"
  # Escape for JSON
  output_truncated="${output_truncated//\\/\\\\}"
  output_truncated="${output_truncated//\"/\\\"}"
  output_truncated="${output_truncated//$'\n'/\\n}"
  output_truncated="${output_truncated//$'\t'/\\t}"

  local json="{\"gate\":\"${gate_name}\",\"result\":\"${result}\",\"exit_code\":${exit_code},\"duration_ms\":${duration_ms},\"output\":\"${output_truncated}\"}"
  echo "$json"

  # Log to file if provided
  [[ "$log_file" != "/dev/null" ]] && echo "$json" >> "$log_file"

  [[ $exit_code -eq 0 ]] && return 0 || return 1
}

run_all_gates() {
  local execution_yaml="$1"
  local epic_id="$2"
  local run_id="$3"
  local timeline_file="${4:-.aid-o/work/evidence/${epic_id}/${run_id}/timeline.jsonl}"

  [[ -f "$execution_yaml" ]] || { echo "ERROR: execution_yaml not found: $execution_yaml" >&2; exit 1; }

  local overall="pass"
  local gates_json="{"
  local first=true

  # Extract gate names from YAML (awk-based, no yq dependency)
  # Use local variable to avoid gsub rebuilding $0 and breaking p=0 guard
  local gate_names
  gate_names=$(awk '/^gates:/{p=1;next} p && /^  [a-z]/{name=$1; gsub(/:.*$/,"",name); print name} /^[^ ]/{p=0}' "$execution_yaml")

  while IFS= read -r gate_name; do
    [[ -z "$gate_name" ]] && continue

    # Extract gate properties (print lines after gate header until next 2-space key)
    local command required max_retries
    command=$(awk "/^  ${gate_name}:/{p=1;next} p && /^  [a-z]/{exit} p{print}" "$execution_yaml" | grep 'command:' | sed 's/.*command: *//' | tr -d '"')
    required=$(awk "/^  ${gate_name}:/{p=1;next} p && /^  [a-z]/{exit} p{print}" "$execution_yaml" | grep 'required:' | awk '{print $2}')
    max_retries=$(awk "/^  ${gate_name}:/{p=1;next} p && /^  [a-z]/{exit} p{print}" "$execution_yaml" | grep 'max_retries:' | awk '{print $2}')
    max_retries="${max_retries:-1}"

    log_event "$timeline_file" "gate_start" gate="$gate_name" epic_id="$epic_id"

    local gate_result="" attempt=0 gate_exit=0
    for (( attempt=1; attempt<=max_retries+1; attempt++ )); do
      gate_exit=0
      gate_result=$(run_gate "$gate_name" "$command" 60 /dev/null) || gate_exit=$?
      local r
      r=$(echo "$gate_result" | jq -r '.result')
      [[ "$r" == "pass" ]] && break
      [[ $attempt -le $max_retries ]] && echo "Gate ${gate_name} failed (attempt ${attempt}/${max_retries}), retrying..." >&2
    done

    local final_result
    final_result=$(echo "$gate_result" | jq -r '.result')
    log_event "$timeline_file" "gate_complete" gate="$gate_name" result="$final_result" attempt="$attempt"

    # Add to gates JSON
    $first || gates_json+=","
    first=false
    gates_json+="\"${gate_name}\":$(echo "$gate_result" | jq ". + {\"attempts\":${attempt}}")"

    # Mark overall fail if required gate fails
    if [[ "$final_result" == "fail" && "${required:-false}" == "true" ]]; then
      overall="fail"
    fi
  done <<< "$gate_names"

  gates_json+="}"

  local completed_at
  completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local report="{\"epic_id\":\"${epic_id}\",\"run_id\":\"${run_id}\",\"overall\":\"${overall}\",\"completed_at\":\"${completed_at}\",\"gates\":${gates_json}}"
  echo "$report"

  log_event "$timeline_file" "gates_complete" overall="$overall" epic_id="$epic_id"

  [[ "$overall" == "pass" ]] && return 0 || return 1
}

# Dispatch
case "${1:-}" in
  run-gate)  shift; run_gate "$@" ;;
  run-all)   shift; run_all_gates "$@" ;;
  *)
    # Source mode — functions available to caller
    [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
    echo "Usage: aid-run-gates.sh <run-gate|run-all> [args...]" >&2; exit 1 ;;
esac
