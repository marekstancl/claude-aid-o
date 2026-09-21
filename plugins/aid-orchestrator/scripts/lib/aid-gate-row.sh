#!/usr/bin/env bash
# =============================================================================
# aid-gate-row.sh — job result → gate row mapping (P076 Step 2).
#
# ONE definition, two callers: the background poll loop in aid-run-gates.sh
# (this step) and the resume-time report patching (Step 5). Both need to turn
# an aid-job.sh terminal result into a row that is INDISTINGUISHABLE in shape
# from a row `run_gate` would have produced, so every existing downstream
# consumer (retry loop, waiver check, runtime-baseline sample, command_log,
# report assembly) needs zero changes to accept it.
#
# The three non-obvious mappings, and why:
#
#   duration_ms — an aid-job result record carries NO duration field. It is
#     composed here from the job's own started_at/ended_at stamps. Second
#     resolution is all those stamps have; a job that cannot be parsed yields
#     0 rather than a fabricated number.
#
#   exit_code 124 on timeout — the supervisor kills a deadline-exceeded command
#     with TERM then KILL, so the RAW exit code is 143/137. Every existing
#     timeout consumer in this repository keys on 124 (the `timeout(1)`
#     convention): the runtime baseline marks a sample censored iff exit_code
#     is 124, and the repeated-timeout policy block counts those censored
#     samples. A row carrying 143 would therefore silently stop counting toward
#     a timeout streak. So a `timed_out` job SYNTHESIZES 124 in `exit_code` and
#     preserves the real one in `job_exit_code`.
#
#   job_id / job_state — the durable binding from a gate row back to the job
#     directory that produced it. Present on background rows only; a foreground
#     row never gains a field.
#
# P097 Step 2 — the row is ONE contract (version 2), and this file is its only
# home. Every reader goes through `gate_row_normalize` (bash) or the jq def of
# the same name in $AID_GATE_ROW_JQ; nothing else inspects a row's `result`.
# The shape and the closed reason vocabulary are in
# defaults/schemas/gate-row.schema.json; the runner checks every row it writes
# against that vocabulary (`gate_row_check`).
#
# Sourceable only — this file defines functions and runs nothing.
# =============================================================================

# jq: `gate_row_normalize` — a version-1 row becomes a version-2 row; a
# version-2 row passes through untouched. Readers that already run jq over a
# report prepend this string to their filter.
#
# Version-1 mapping (plan P097 Data Model): pass → pass/exit_0; fail → fail/
# <its reason, else exit_<n>>; job_* result → fail/job_*; skip → skip/<its
# reason, else legacy_row>; profile_excluded → skip/not_in_profile; waived →
# fail/exit_<n> + waived:true; no result at all → skip/legacy_row; anything
# else → fail/legacy_row (the direction that cannot hide a broken run). The two
# renamed reasons (profile_excluded, gate_script_missing_in_tree) map to their
# version-2 names. `result` stays on the row for one release, DERIVED from
# status/waived, so a reader not yet moved keeps working.
# shellcheck disable=SC2016
AID_GATE_ROW_JQ='
def gate_row_normalize:
  if (.row_version // 0) == 2 then . else
    (.result // null) as $r
    | ((.reason // "") | if . == "profile_excluded" then "not_in_profile"
                         elif . == "gate_script_missing_in_tree" then "missing_script"
                         else . end) as $rs
    | ("exit_\(.exit_code // 1)") as $exit
    | (if $r == "pass" then {status:"pass", reason:"exit_0", waived:false}
       elif $r == "fail" then {status:"fail", reason:(if $rs != "" then $rs else $exit end), waived:false}
       elif ($r|type) == "string" and ($r|startswith("job_")) then {status:"fail", reason:$r, waived:false}
       elif $r == "waived" then {status:"fail", reason:(if $rs != "" then $rs else $exit end), waived:true}
       elif $r == "skip" then {status:"skip", reason:(if $rs != "" then $rs else "legacy_row" end), waived:false}
       elif $r == "profile_excluded" then {status:"skip", reason:"not_in_profile", waived:false}
       elif $r == null then {status:"skip", reason:"legacy_row", waived:false}
       else {status:"fail", reason:"legacy_row", waived:false} end) as $m
    | . + $m
    + {row_version: 2, exit_code: (.exit_code // null), duration_ms: (.duration_ms // 0),
       started_at: (.started_at // null), completed_at: (.completed_at // null),
       evidence: (.evidence // null), required: (.required // false),
       reused_from: (.reused_from // null)}
    | .result = (if .status == "fail" and .waived then "waived" else .status end)
  end;
def gate_rows_normalize:
  with_entries(if (.key|startswith("_")) or (.value|type) != "object" then . else .value |= gate_row_normalize end);
'

# gate_row_normalize [row_json]
#   stdin (or $1): one row. stdout: the version-2 row (one line).
gate_row_normalize() {
  if (( $# )); then jq -c "${AID_GATE_ROW_JQ} gate_row_normalize" <<<"$1"
  else jq -c "${AID_GATE_ROW_JQ} gate_row_normalize"; fi
}

# gate_row_check <gate_name> <row_json>
#   Exit 0 iff the version-2 row carries the required keys, a known status
#   and a reason inside the closed vocabulary — read from the schema file so
#   the vocabulary lives in ONE place. A runner that invents reasons is the
#   defect; the caller names the gate and exits 1.
#   ponytail: a jq check of the keys/status/reason, not a full JSON-Schema
#   validation — the suite validates whole rows with adapter_validate_schema;
#   the runner must not depend on python3+jsonschema at every project.
gate_row_check() {
  local gate_name="$1" row="$2"
  local schema="${AID_GATE_ROW_SCHEMA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../defaults/schemas" && pwd)/gate-row.schema.json}"
  local err
  err="$(jq -r --slurpfile s "$schema" '
    ($s[0]) as $schema | . as $row
    | [$schema.required[] | select(in($row) | not)] as $missing
    | if ($missing|length) > 0 then "missing field(s): \($missing|join(", "))"
      elif ($schema.properties.status.enum | index($row.status)) == null then "unknown status \($row.status|tojson)"
      elif (($row.reason|type) != "string") or (($row.reason|test($schema.properties.reason.pattern)) | not)
        then "reason \($row.reason|tojson) is outside the closed vocabulary"
      else empty end' <<<"$row" 2>&1)" || err="row is not valid JSON"
  [[ -z "$err" ]] && return 0
  echo "ERROR: aid-gate-row.sh: gate '${gate_name}' row rejected — ${err} (defaults/schemas/gate-row.schema.json)" >&2
  return 1
}

# _agr_epoch <iso8601> — echo epoch seconds, or nothing if unparseable.
_agr_epoch() {
  local ts="${1:-}"
  [[ -n "$ts" && "$ts" != "null" ]] || return 0
  date -u -d "$ts" +%s 2>/dev/null || true
}

# _agr_job_duration_ms <started_at_iso> <ended_at_iso>
#   Composed duration in ms, floored at 0. 0 when either stamp is missing or
#   unparseable — an honest "not measured", never an invented value.
_agr_job_duration_ms() {
  local s e se ee
  s="$1"; e="$2"
  se="$(_agr_epoch "$s")"; ee="$(_agr_epoch "$e")"
  if [[ -n "$se" && -n "$ee" ]]; then
    local d=$(( (ee - se) * 1000 ))
    (( d < 0 )) && d=0
    printf '%s' "$d"
  else
    printf '0'
  fi
}

# _agr_stdout_excerpt <job_dir>
#   The first 2000 characters of the job's captured stdout — the SAME
#   truncation discipline run_gate() applies to a foreground gate's output, so
#   a background row's `output` field means exactly what a foreground row's
#   does. jq does the escaping in the caller.
_agr_stdout_excerpt() {
  local job_dir="$1" raw=""
  [[ -f "$job_dir/stdout.log" ]] && raw="$(cat "$job_dir/stdout.log" 2>/dev/null || true)"
  printf '%s' "${raw:0:2000}"
}

# gate_row_from_job <gate_name> <job_dir> <job_id> [live_state]
#   stdout: one line of gate-row JSON.
#
#   With a terminal result present, maps it (see the header). With NO terminal
#   result — the owned process vanished without recording an outcome — emits
#   the explicit `job_lost` fail row: a job that proves no outcome must never
#   read as a pass, and must never read as an ordinary command failure either.
#   Returns 0 iff the row's result is "pass".
gate_row_from_job() {
  local gate_name="$1" job_dir="$2" job_id="$3" live_state="${4:-lost}"
  local result_file="$job_dir/result.json"

  # The job's own stdout, relative to the run's evidence directory (jobs/<id>/
  # is where run_background_gate puts every job): the row's `evidence`.
  local evidence="null"
  [[ -f "$job_dir/stdout.log" ]] && evidence="$(jq -nc --arg e "jobs/$(basename "$job_dir")/stdout.log" '$e')"

  if [[ ! -f "$result_file" ]]; then
    jq -nc \
      --arg gate "$gate_name" \
      --arg jid "$job_id" \
      --arg js "$live_state" \
      --arg out "$(_agr_stdout_excerpt "$job_dir")" \
      --argjson ev "$evidence" \
      '{gate:$gate, result:"fail", exit_code:1, duration_ms:0, evidence:$ev,
        output:$out, reason:"job_lost", job_id:$jid, job_state:$js}' | gate_row_normalize
    return 1
  fi

  local state raw_exit started_at ended_at duration_ms
  state="$(jq -r '.state // "unknown"' "$result_file")"
  raw_exit="$(jq -r '.exit_code // 1' "$result_file")"
  [[ "$raw_exit" =~ ^-?[0-9]+$ ]] || raw_exit=1
  started_at="$(jq -r '.started_at // ""' "$result_file")"
  ended_at="$(jq -r '.ended_at // ""' "$result_file")"
  duration_ms="$(_agr_job_duration_ms "$started_at" "$ended_at")"

  local result="fail" effective_exit="$raw_exit" reason="" synthesized=0
  case "$state" in
    terminal_pass) result="pass"; effective_exit=0 ;;
    terminal_fail) result="fail" ;;
    timed_out)     result="fail"; effective_exit=124; synthesized=1; reason="job_timeout" ;;
    cancelled)     result="fail"; reason="job_cancelled" ;;
    # A record whose state is not terminal proves no outcome — that is
    # `job_lost` in the closed vocabulary; the raw state stays in `job_state`.
    *)             result="fail"; reason="job_lost" ;;
  esac

  local row
  row="$(jq -nc \
    --arg gate "$gate_name" \
    --arg res "$result" \
    --argjson ec "$effective_exit" \
    --argjson dur "$duration_ms" \
    --arg out "$(_agr_stdout_excerpt "$job_dir")" \
    --arg jid "$job_id" \
    --arg js "$state" \
    --arg sa "$started_at" --arg ea "$ended_at" --argjson ev "$evidence" \
    '{gate:$gate, result:$res, exit_code:$ec, duration_ms:$dur,
      started_at:(if $sa == "" then null else $sa end),
      completed_at:(if $ea == "" then null else $ea end), evidence:$ev,
      output:$out, job_id:$jid, job_state:$js}')"

  if (( synthesized )); then
    row="$(jq -c --argjson raw "$raw_exit" '. + {job_exit_code:$raw}' <<<"$row")"
  fi
  if [[ -n "$reason" ]]; then
    row="$(jq -c --arg r "$reason" '. + {reason:$r}' <<<"$row")"
  fi

  gate_row_normalize "$row"
  [[ "$result" == "pass" ]] && return 0 || return 1
}
