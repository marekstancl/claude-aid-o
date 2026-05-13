#!/usr/bin/env bash
# aid-audit-log.sh — Append-only writer for cross-EPIC audit-log.jsonl.
# Used by aid-fsm.sh for fsm_force_override events. Never truncates.
# Schema: {"ts":"...","event":"...","epic_id":"...","run_id":"...","caller":"...","reason":"...","operator":"..."}
#
# Flag conventions (cmd_append):
#   --<key> <value>          — serializes as JSON string  "<key>":"<value>"
#   --<key>-array <csv>      — serializes as JSON array   "<key>":["a","b","c"]
#                              (P038: blocked_checks support; empty/whitespace → [])
#
# KEY_TIDY: dashes in flag names are normalized to underscores in the JSON
# key (e.g. --blocked-checks-array → "blocked_checks":[...]). Existing
# single-word keys (caller, reason, operator) are unaffected.
set -euo pipefail

main() {
  local cmd="${1:-}"
  [[ -z "$cmd" ]] && { echo "Usage: aid-audit-log.sh append --event <event> --output <file> [--key value ...]" >&2; exit 1; }
  shift
  case "$cmd" in
    append) cmd_append "$@" ;;
    *) echo "Unknown command: $cmd" >&2; exit 1 ;;
  esac
}

cmd_append() {
  local epic_id="" run_id="" event="" output=""
  local -a extra_kvs=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --epic-id)  epic_id="$2";  shift 2 ;;
      --run-id)   run_id="$2";   shift 2 ;;
      --event)    event="$2";    shift 2 ;;
      --output)   output="$2";   shift 2 ;;
      --*)
        local key="${1#--}" val="${2:-}"
        extra_kvs+=("${key}=${val}")
        shift 2
        ;;
      *) shift ;;
    esac
  done

  [[ -z "$output" ]] && { echo "ERROR: --output required" >&2; exit 1; }
  [[ -z "$event" ]]  && { echo "ERROR: --event required" >&2; exit 1; }

  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Build JSON manually — no jq dependency for this minimal writer
  local json
  json="{\"ts\":\"${now}\",\"event\":\"${event}\""
  json+=",\"epic_id\":\"${epic_id}\",\"run_id\":\"${run_id}\""

  for kv in "${extra_kvs[@]}"; do
    local k="${kv%%=*}" v="${kv#*=}"
    # KEY_TIDY: dashes → underscores for JSON key compatibility
    local json_key="${k//-/_}"

    if [[ "$k" == *-array ]]; then
      # -array suffix → serialize value as JSON array; strip suffix from key
      json_key="${json_key%_array}"
      if [[ -z "$v" ]]; then
        json+=",\"${json_key}\":[]"
      else
        # Use jq for safe JSON escaping in array elements (handles all control chars).
        # P038 CP3 security finding HIGH-1: hand-rolled escape misses TAB, CR, BEL, etc.
        # jq -Rs '.' produces a correctly-escaped JSON string literal per RFC 8259.
        # Use -c flag to ensure output is compact (single line for JSONL format).
        local arr_json
        arr_json=$(printf '%s\n' "${v//,/$'\n'}" | jq -Rsc 'split("\n") | map(select(length > 0))')
        json+=",\"${json_key}\":${arr_json}"
      fi
    else
      # Use jq for safe JSON escaping (handles all control chars: TAB, CR, BEL, etc).
      # P038 CP3 security finding HIGH-1: hand-rolled escape misses RFC 8259 requirements.
      local v_json
      v_json=$(printf '%s' "$v" | jq -Rs '.')
      json+=",\"${json_key}\":${v_json}"
    fi
  done

  json+="}"

  mkdir -p "$(dirname "$output")"
  # >> is atomic for short writes on Linux ext4/xfs — safe for concurrent appenders
  echo "$json" >> "$output" 2>/dev/null || {
    echo "[WARN] aid-audit-log.sh: failed to write to $output (non-fatal)" >&2
    return 0  # audit log failure must never abort primary FSM operation
  }
}

main "$@"
