#!/usr/bin/env bash
# aid-test-audit-profile-select.sh — P072 Step 13 (production wiring).
#
# Decides, deterministically, WHICH run units a measure/full audit owes a cost
# profile for. It runs nothing; it reads the measurements the audit already
# produced and emits a selection the profiler and the consolidator both bind to.
#
# WHY THIS EXISTS AS A SCRIPT
#   The profiler was reachable only by hand. That made "was this slow suite
#   diagnosed?" a question about whether whoever ran the audit remembered to
#   diagnose it — which is the same class of gap as a detector with no
#   enforcement. With a selection artifact, the answer is checkable: the
#   consolidator refuses to finalize a full audit whose selected units have no
#   receipt.
#
# WHAT IT WILL NOT DO
#   * It never drops a unit silently. A unit over the trigger that does not fit
#     under `profile_max_units` appears in `deferred` WITH its measured cost,
#     so a reader sees what was not diagnosed and why.
#   * It never invents a measurement. A measurements file that is missing,
#     empty or unreadable is an error, not an empty selection — an empty
#     selection means "nothing was slow enough", and those two must not look
#     alike.
#
# Exit codes: 0 ok · 2 usage · 3 unreadable/absent measurements

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-audit-config.sh
source "${SCRIPT_DIR}/lib/aid-test-audit-config.sh"

_die() { echo "aid-test-audit-profile-select.sh: $2" >&2; exit "$1"; }

measurements="" project_root="" audit_id="" out_path="" trigger_ms="" max_units=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --measurements) [[ $# -ge 2 ]] || _die 2 "--measurements requires a value"; measurements="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --audit-id)     [[ $# -ge 2 ]] || _die 2 "--audit-id requires a value"; audit_id="$2"; shift 2 ;;
    --output)       [[ $# -ge 2 ]] || _die 2 "--output requires a value"; out_path="$2"; shift 2 ;;
    --trigger-ms)   [[ $# -ge 2 ]] || _die 2 "--trigger-ms requires a value"; trigger_ms="$2"; shift 2 ;;
    --max-units)    [[ $# -ge 2 ]] || _die 2 "--max-units requires a value"; max_units="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$measurements" ]] || _die 2 "--measurements is required"
[[ -f "$measurements" ]] || _die 3 "--measurements '$measurements' does not exist — an absent measurements file is not an empty selection"
[[ -n "$project_root" && -d "$project_root" ]] || _die 2 "--project-root is required and must exist"
[[ -n "$audit_id" ]] || _die 2 "--audit-id is required (the selection is bound to one audit, and so are the receipts that satisfy it)"
[[ -n "$out_path" ]] || _die 2 "--output is required"

[[ -n "$trigger_ms" ]] || trigger_ms="$(test_audit_decision_key profile_trigger_ms "$project_root")"
[[ -n "$max_units"  ]] || max_units="$(test_audit_decision_key profile_max_units "$project_root")"
[[ "$trigger_ms" =~ ^[0-9]+$ ]] || _die 2 "profile_trigger_ms must be a non-negative integer (got '$trigger_ms')"
[[ "$max_units"  =~ ^[0-9]+$ ]] || _die 2 "profile_max_units must be a non-negative integer (got '$max_units')"

# The measurements file is JSONL, one normalized measurement per line (see
# lib/aid-test-audit-measure.sh). A line that does not parse stops the run:
# quietly skipping it would remove a candidate from consideration and nobody
# would learn that a slow unit was never even weighed.
line_no=0
while IFS= read -r line; do
  line_no=$(( line_no + 1 ))
  [[ -z "$line" ]] && continue
  jq -e . >/dev/null 2>&1 <<<"$line" \
    || _die 3 "line ${line_no} of '$measurements' is not parseable JSON — refusing to select from a measurement set with a hole in it"
done < "$measurements"

selection="$(jq -sc \
  --argjson trigger "$trigger_ms" --argjson cap "$max_units" \
  --arg audit "$audit_id" '
  # Terminal measurements are candidates, and `timed_out` IS one of them.
  #
  # It used to be excluded on the reasoning that a job which never finished has
  # "no duration worth ranking". That is exactly backwards for a timeout: the
  # elapsed time is a LOWER BOUND, and a unit that exhausted its deadline is by
  # definition among the most expensive things in the portfolio. Dropping those
  # meant the single slowest gate was the one unit guaranteed never to get a
  # cost breakdown — found by a real audit, where `shell_pipeline_smoke` blew
  # through its cap at 73 of 151 suites and was then silently not profiled.
  #
  # `lost` and `cancelled` stay out: those have no duration at all, only an
  # absence.
  ( [ .[]
      | select(.run_unit_id != null and .duration_ms != null)
      | select(.state == "terminal_pass" or .state == "terminal_fail" or .state == "timed_out")
      | . + { measurement_kind: (if .state == "timed_out" then "lower_bound" else "measured" end) }
    ] ) as $all
  | ( [ $all[] | select(.duration_ms >= $trigger) ]
      | sort_by(-.duration_ms) ) as $over
  | {
      schema_version: "aid-test-profile-selection-v1",
      audit_id: $audit,
      policy: { profile_trigger_ms: $trigger, profile_max_units: $cap },
      measured_units: ($all | length),
      selected: [ $over[:$cap][]
                  | { run_unit_id, measured_ms: .duration_ms,
                      measurement_kind: .measurement_kind,
                      reason: (if .measurement_kind == "lower_bound"
                               then "ran at least " + (.duration_ms|tostring) + "ms before exhausting its deadline — a lower bound, and above the "
                                    + ($trigger|tostring) + "ms profiling trigger"
                               else "measured " + (.duration_ms|tostring) + "ms, at or above the "
                                    + ($trigger|tostring) + "ms profiling trigger" end) } ],
      deferred: [ $over[$cap:][]
                  | { run_unit_id, measured_ms: .duration_ms,
                      reason: ("over the " + ($trigger|tostring) + "ms trigger but past the "
                               + ($cap|tostring) + "-unit ceiling for this audit — not diagnosed, and not dismissed") } ]
    }' "$measurements")"

mkdir -p "$(dirname "$out_path")"
printf '%s\n' "$selection" > "$out_path"
printf '%s\n' "$out_path"
