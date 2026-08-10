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
# Sourceable only — this file defines functions and runs nothing.
# =============================================================================

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

  if [[ ! -f "$result_file" ]]; then
    jq -nc \
      --arg gate "$gate_name" \
      --arg jid "$job_id" \
      --arg js "$live_state" \
      --arg out "$(_agr_stdout_excerpt "$job_dir")" \
      '{gate:$gate, result:"fail", exit_code:1, duration_ms:0,
        output:$out, reason:"job_lost", job_id:$jid, job_state:$js}'
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
    *)             result="fail"; reason="job_${state}" ;;
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
    '{gate:$gate, result:$res, exit_code:$ec, duration_ms:$dur,
      output:$out, job_id:$jid, job_state:$js}')"

  if (( synthesized )); then
    row="$(jq -c --argjson raw "$raw_exit" '. + {job_exit_code:$raw}' <<<"$row")"
  fi
  if [[ -n "$reason" ]]; then
    row="$(jq -c --arg r "$reason" '. + {reason:$r}' <<<"$row")"
  fi

  printf '%s\n' "$row"
  [[ "$result" == "pass" ]] && return 0 || return 1
}
