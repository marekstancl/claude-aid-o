#!/usr/bin/env bash
# aid-stage-log.sh — Structured JSONL event logging
# Source this file, then call: log_event <timeline_file> <event> [key=value ...]
# NEVER exits non-zero (logging must not interrupt pipeline)

# Shared fatal-error helper for sourcing scripts (aid-fsm.sh overrides it with
# its own multi-line variant — that definition comes after the source line).
die() { echo "ERROR: $*" >&2; exit 1; }

log_event() {
  local timeline_file="$1"
  local event="$2"
  shift 2

  # Build timestamp
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Start JSON object
  local json="{\"ts\":\"${ts}\",\"event\":\"${event}\""

  # Parse key=value pairs, escape values for JSON
  local key val
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    # Raw JSON array/object detected BEFORE escaping — pass through as-is.
    # Used by aid-prefilter.sh for matched_rules (e.g. ["exec_keyword"]).
    if [[ "${val:0:1}" == "[" || "${val:0:1}" == "{" ]]; then
      json+=",\"${key}\":${val}"
      continue
    fi
    # Escape special JSON characters in plain string values
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    val="${val//$'\n'/\\n}"
    val="${val//$'\t'/\\t}"
    # Detect numeric values (int or float, no quoting)
    if [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
      json+=",\"${key}\":${val}"
    elif [[ "$val" == "true" || "$val" == "false" || "$val" == "null" ]]; then
      json+=",\"${key}\":${val}"
    else
      json+=",\"${key}\":\"${val}\""
    fi
  done

  json+="}"

  # Validate JSON before writing (requires jq)
  if command -v jq &>/dev/null; then
    if ! echo "$json" | jq -e . &>/dev/null; then
      # Invalid JSON: write error event instead, never block pipeline
      local err_json="{\"ts\":\"${ts}\",\"event\":\"log_error\",\"original_event\":\"${event}\",\"error\":\"invalid JSON generated\"}"
      echo "$err_json" >> "${timeline_file}" 2>/dev/null || true
      return 0
    fi
  fi

  # Atomic append (>> is atomic for short writes on Linux ext4/xfs)
  echo "$json" >> "${timeline_file}" 2>/dev/null || true
  return 0
}

# aid_plan_timeline <project_root> <plan_id> — the PLAN-scoped timeline file,
# created if needed. Echoes the path, or returns 1 when it cannot be made.
#
# WHY THIS EXISTS (P084 Step 7, and the finding that motivated it)
#   `.aid-o/work/timeline.jsonl` — the file /aid-init creates at the workspace
#   root — had 0 lines in this repository. The writer was never broken: every
#   caller of log_event passes a per-RUN path (`evidence/<epic>/<run>/timeline.jsonl`,
#   81 of them here, all non-empty), and NOTHING ever writes to the root file.
#   So the gap was not a logger bug but a missing home for PLAN-scoped events —
#   band classification, a lint that stopped a plan — which happen before any
#   run exists. They now land next to the plan's other evidence, under
#   `evidence/<plan_id>/`, which is the same root CP1/C0 already use.
aid_plan_timeline() {
  # ${1-}/${2-}, not $1/$2: a caller running under `set -u` would abort on the
  # expansion before this function could honour its own "returns 1" contract.
  local root="${1-}" plan_id="${2-}" dir
  [[ -n "$root" && -n "$plan_id" ]] || return 1
  dir="${root}/.aid-o/work/evidence/${plan_id}"
  [[ -d "${root}/.aid-o" ]] || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '%s/timeline.jsonl' "$dir"
}

# aid_plan_log <plan_file> <event> [key=value ...] — the plan-scoped verb.
#
# Resolves the plan's id and its workspace THE SAME WAY for every caller and
# writes one event. Never fails, never blocks: an unreadable id, a plan outside
# a workspace, an unwritable evidence dir and a logger error all end as a quiet
# `return 0`. Three call sites (the CP1 gate, the plan lint, the readiness
# check) each hand-rolled this four-step ritual and two of them had already
# drifted on which root they resolved.
#
# Requires lib/aid-plan-band.sh (for `_aid_plan_id_of` / `_aid_band_project_root`);
# callers that log plan events source it anyway to classify the band.
aid_plan_log() {
  local plan="${1-}" id root tl
  shift || return 0
  [[ -n "$plan" && $# -gt 0 ]] || return 0
  declare -F _aid_plan_id_of >/dev/null || return 0
  id="$(_aid_plan_id_of "$plan")" || return 0
  root="$(_aid_band_project_root "$plan")" || return 0
  tl="$(aid_plan_timeline "$root" "$id")" || return 0
  log_event "$tl" "$@" || true
}

# Severity-prefixed stderr loggers (P032 Step 1).
# Use these instead of bare `echo "..." >&2` so logs are greppable.
log_info() {
  echo "[INFO] $*" >&2
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

# Export for use in subshells
export -f log_event log_info log_warn log_error aid_plan_timeline aid_plan_log

# CLI dispatcher (P037 Phase 1) — allow `bash aid-stage-log.sh <fn> <args>` from
# LLM-rendered docs in pipeline.md / aid-plan.md without requiring a source step.
# Source-mode (BASH_SOURCE != $0) remains the canonical pattern for scripts.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ $# -gt 0 ]]; then
  fn="$1"; shift
  case "$fn" in
    # IMP-104 (v2.20.2 cleanup): all 4 functions are dispatchable, but only
    # log_event writes to the timeline file. log_info/log_warn/log_error are
    # stderr-only severity-prefixed echoes — useful for shell pipelines but
    # invisible to compliance check + downstream evidence consumers.
    log_event|log_info|log_warn|log_error|aid_plan_timeline|aid_plan_log) "$fn" "$@" ;;
    *)
      echo "ERROR: unknown function: $fn" >&2
      echo "Available: log_event, aid_plan_log (timeline writes), aid_plan_timeline (path only), log_info/log_warn/log_error (stderr only)" >&2
      echo "Library mode: source $0 && <fn> <args>" >&2
      exit 1
      ;;
  esac
fi

