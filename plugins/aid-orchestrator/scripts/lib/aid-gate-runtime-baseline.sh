#!/usr/bin/env bash
# =============================================================================
# aid-gate-runtime-baseline.sh — proposes a gate's `timeout_seconds` from
# recorded history (P097 Step 5).
#
# WHY THIS FILE EXISTS: a gate's deadline is `timeout_seconds` in
# execution.yaml and nothing else — the same configuration and the same code
# give the same deadline on every host. Measured history informs the number in
# the file, not the run: this library reads the `gates_rows/<gate>.json` rows
# the runner checkpoints under a project's evidence root and prints the number
# the written rule gives. It never runs during a gate run and never writes.
#
# The rule (defaults/execution.yaml, comment on `timeout_seconds`):
#   2 × p95 of the last 20 `duration_ms` of that gate, rows with reason
#   `job_timeout` excluded (their duration is the deadline, not a measurement),
#   rounded up to a multiple of 30 s, minimum 60 s, maximum 3 600 s.
#   Fewer than five measured durations → `insufficient_history`, exit 0.
#
# Usage:
#   Sourced:    gate_baseline_propose <evidence root> <gate id>
#   Standalone: bash aid-gate-runtime-baseline.sh propose <evidence root> <gate id>
#
# Sourceable-safe: no top-level `set -e` (callers source under their own
# strict shell); every fallible call is guarded.
# =============================================================================

_gbr_warn() {
  echo "WARN: aid-gate-runtime-baseline.sh: $*" >&2
}

# _gbr_percentiles_json <samples_json>
#   Nearest-rank percentiles + sample counts over the non-censored subset of
#   `[{duration_ms, censored}]`: index = ceil(P/100 * N) - 1, clamped.
_gbr_percentiles_json() {
  local samples_json="$1"
  jq -c '
    def nearest_rank(P; arr):
      (arr|length) as $n
      | if $n == 0 then null
        else
          ((( (P/100*$n) | ceil) - 1)) as $idx0
          | (if $idx0 < 0 then 0 elif $idx0 > ($n-1) then ($n-1) else $idx0 end) as $idx
          | arr[$idx]
        end;
    (map(select(.censored==false))) as $nc
    | ($nc | map(.duration_ms) | sort) as $durs
    | {
        samples_count: length,
        non_censored_samples_count: ($nc|length),
        p50_ms: nearest_rank(50; $durs),
        p90_ms: nearest_rank(90; $durs),
        p95_ms: nearest_rank(95; $durs),
        max_ms: (if ($durs|length) > 0 then ($durs|last) else null end)
      }
  ' <<<"$samples_json"
}

# gate_baseline_propose <evidence root> <gate id>
#   Prints `<gate> proposed_timeout_seconds=<n> (p95 <ms> ms over the last <k>
#   measured durations, <x> job_timeout rows excluded)` or
#   `<gate> insufficient_history (<k> measured durations, 5 needed, <x>
#   job_timeout rows excluded)`. Exit 0 either way; exit 2 on bad arguments.
#   The last 20 durations are the 20 newest measured rows by `completed_at`
#   (file mtime when a row carries none) across every `gates_rows/<gate>.json`
#   under the root; `job_timeout` rows are dropped before the window is cut
#   and counted in the message.
gate_baseline_propose() {
  local root="${1:-}" gate="${2:-}"
  [[ -n "$root" && -n "$gate" ]] || {
    echo "ERROR: aid-gate-runtime-baseline.sh: propose needs <evidence root dir> <gate id>" >&2
    return 2
  }
  # A root that does not exist yet is a project with no history: not an error.
  case "$gate" in */*|*..*) echo "ERROR: aid-gate-runtime-baseline.sh: gate id '${gate}' is not a name" >&2; return 2 ;; esac
  command -v jq >/dev/null 2>&1 || { _gbr_warn "jq not found on PATH"; return 2; }

  # One JSON array of {duration_ms, censored, at}: `at` orders the rows.
  local rows
  rows="$(find "$root" -path "*/gates_rows/${gate}.json" -type f -printf '%T@ %p\n' 2>/dev/null \
    | while read -r mtime path; do
        jq -c --arg m "$mtime" '
          select(type == "object" and ((.duration_ms // null) | type) == "number")
          | {duration_ms: (.duration_ms | floor),
             censored: (.reason == "job_timeout"),
             at: (.completed_at // $m)}' "$path" 2>/dev/null
      done | jq -sc 'sort_by(.at)')"
  [[ -n "$rows" ]] || rows='[]'

  local excluded window stats p95 measured
  excluded="$(jq -r 'map(select(.censored)) | length' <<<"$rows")"
  window="$(jq -c 'map(select(.censored | not)) | .[-20:]' <<<"$rows")"
  stats="$(_gbr_percentiles_json "$window")"
  p95="$(jq -r '.p95_ms // "null"' <<<"$stats")"
  measured="$(jq -r '.non_censored_samples_count' <<<"$stats")"

  if (( measured < 5 )) || [[ "$p95" == "null" ]]; then
    echo "${gate} insufficient_history (${measured} measured durations, 5 needed, ${excluded} job_timeout rows excluded)"
    return 0
  fi
  # 2 × p95, up to the next 30 s, clamped to 60–3600 s (integer arithmetic on ms).
  local secs=$(( (2 * p95 + 29999) / 30000 * 30 ))
  (( secs < 60 )) && secs=60
  (( secs > 3600 )) && secs=3600
  echo "${gate} proposed_timeout_seconds=${secs} (p95 ${p95} ms over the last ${measured} measured durations, ${excluded} job_timeout rows excluded)"
  return 0
}

# ── Standalone dispatch (skipped when sourced) ──────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    propose) gate_baseline_propose "${2:-}" "${3:-}" ;;
    *)
      echo "Usage: aid-gate-runtime-baseline.sh propose <evidence root dir> <gate id>" >&2
      exit 1
      ;;
  esac
fi
