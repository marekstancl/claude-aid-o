#!/usr/bin/env bash
# aid-test-audit-measure.sh — P066 Step 12.
#
# Gives `measure`/`full`-mode command execution safe process-group/deadline/
# streamed-log/terminal-receipt behavior by calling aid-job.sh directly, one
# command at a time. Explicitly NOT the reusable "execution unit" abstraction
# P069 builds (Constraint 7/8) — no new process-group/kill logic here at all;
# every safety property comes from aid-job.sh's own existing, real CLI,
# unmodified.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_TAM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TAM_JOB_SH="${_TAM_LIB_DIR}/../aid-job.sh"
# shellcheck source=aid-test-audit-command-allowlist.sh
source "${_TAM_LIB_DIR}/aid-test-audit-command-allowlist.sh"

# _tam_run_one <jobs_dir> <run_unit_id> <command_json> <deadline_seconds>
#   Runs ONE allowlisted command through aid-job.sh, waits for its terminal
#   receipt (polling — aid-job.sh run is itself asynchronous), and echoes
#   one normalized measurement JSON line: {run_unit_id, job_id, state,
#   exit_code, started_at, ended_at, duration_ms, stdout_path}. Never
#   returns before the terminal receipt is durably written.
_tam_run_one() {
  local jobs_dir="$1" run_unit_id="$2" command_json="$3" deadline="$4"
  local cmd_type
  cmd_type="$(jq -r '.type' <<<"$command_json")"

  # Our OWN wall-clock, captured around the whole run+poll lifecycle —
  # aid-job.sh's own started_at/ended_at are whole-second ISO8601 (no
  # sub-second component), so deriving duration_ms from them always ends in
  # "000" and quantizes real durations by up to ~1s (Codex review). This is
  # never a re-implementation of aid-job.sh's own timing/deadline logic —
  # just an external stopwatch around calls to its existing, unmodified CLI.
  local wall_start_ms
  wall_start_ms="$(date -u +%s%3N)"

  local job_id_out
  case "$cmd_type" in
    argv)
      # NUL-delimited decode, not line-based `read` — an approved argv
      # element containing an embedded newline (a valid POSIX path) would
      # otherwise be split across multiple `argv[]` entries by `jq -r`,
      # executing a DIFFERENT command than the exact allowlisted argv
      # (Codex review).
      local -a argv=()
      mapfile -d '' -t argv < <(jq -j '.argv[] | . + "\u0000"' <<<"$command_json")
      job_id_out="$(bash "$_TAM_JOB_SH" run --jobs-dir "$jobs_dir" --label test-audit --deadline "$deadline" -- "${argv[@]}")" \
        || { echo "aid-test-audit-measure: aid-job.sh run failed for $run_unit_id" >&2; return 1; }
      ;;
    shell)
      local shell_cmd
      shell_cmd="$(jq -r '.shell' <<<"$command_json")"
      job_id_out="$(bash "$_TAM_JOB_SH" run --jobs-dir "$jobs_dir" --label test-audit --deadline "$deadline" -- bash -c "$shell_cmd")" \
        || { echo "aid-test-audit-measure: aid-job.sh run failed for $run_unit_id" >&2; return 1; }
      ;;
    *)
      echo "aid-test-audit-measure: unknown command.type '$cmd_type' for $run_unit_id" >&2
      return 1
      ;;
  esac
  local job_id="$job_id_out"

  # Poll for the terminal receipt. `collect` exits 3 while non-terminal
  # (in_flight/lost) — never treated as evidence, per aid-job.sh's own
  # documented contract. Streamed log content (job.json's stdout_path) is
  # already readable during this loop, before the terminal receipt exists.
  #
  # Bounded, not infinite: a "lost" live_state (the aid-job.sh wrapper
  # itself died — OOM/SIGKILL — before writing result.json) can never
  # become terminal on its own, so this loop would otherwise spin forever,
  # silently removing the deadline's bound on the whole measurement run
  # (Codex review). Fails loudly once genuinely lost, or once wall-clock
  # exceeds deadline+buffer as a backstop against any other stuck case.
  local result_json rc live_state hard_deadline_epoch consecutive_lost=0
  hard_deadline_epoch=$(( $(date -u +%s) + deadline + 30 ))
  while true; do
    result_json="$(bash "$_TAM_JOB_SH" collect --jobs-dir "$jobs_dir" --id "$job_id" 2>/dev/null)"
    rc=$?
    [[ "$rc" -ne 3 ]] && break
    live_state="$(jq -r '.live_state // empty' <<<"$result_json" 2>/dev/null)"
    if [[ "$live_state" == "lost" ]]; then
      # Debounced, not acted on from a single reading: aid-job.sh's own
      # pre-PID handshake window (a job legitimately "started" but not yet
      # holding a recorded pid) can transiently read as indistinguishable
      # from "lost" under scheduling pressure. 3 consecutive "lost" readings
      # (~0.6s apart) before treating it as permanent avoids reacting to a
      # one-off misread while still bounding a genuinely dead wrapper.
      consecutive_lost=$((consecutive_lost + 1))
      if [[ "$consecutive_lost" -ge 3 ]]; then
        echo "aid-test-audit-measure: job '$job_id' for $run_unit_id is permanently lost (wrapper died before a terminal result) — aborting, never treated as evidence" >&2
        return 1
      fi
    else
      consecutive_lost=0
    fi
    if [[ "$(date -u +%s)" -ge "$hard_deadline_epoch" ]]; then
      echo "aid-test-audit-measure: job '$job_id' for $run_unit_id exceeded deadline+buffer (${deadline}s+30s) with no terminal result — aborting" >&2
      return 1
    fi
    sleep 0.2
  done

  local wall_end_ms duration_ms
  wall_end_ms="$(date -u +%s%3N)"
  duration_ms=$(( wall_end_ms - wall_start_ms ))

  local state exit_code started_at ended_at stdout_path
  state="$(jq -r '.state' <<<"$result_json")"
  exit_code="$(jq -r '.exit_code' <<<"$result_json")"
  started_at="$(jq -r '.started_at' <<<"$result_json")"
  ended_at="$(jq -r '.ended_at' <<<"$result_json")"
  stdout_path="$jobs_dir/$job_id/stdout.log"

  jq -nc \
    --arg run_unit_id "$run_unit_id" --arg job_id "$job_id" --arg state "$state" \
    --argjson exit_code "$exit_code" --arg started_at "$started_at" --arg ended_at "$ended_at" \
    --argjson duration_ms "$duration_ms" --arg stdout_path "$stdout_path" \
    '{run_unit_id:$run_unit_id, job_id:$job_id, state:$state, exit_code:$exit_code, started_at:$started_at, ended_at:$ended_at, duration_ms:$duration_ms, stdout_path:$stdout_path}'
}

# aid_test_audit_measure_run_all <mode> <jobs_dir> <commands_json_array> <output_jsonl> <execution_yaml> <approved_catalog_path>
#   Runs every {run_unit_id, command, deadline_seconds} entry in
#   <commands_json_array> STRICTLY SEQUENTIALLY — no concurrency, no
#   batching, no resource-lock logic (P069's job). The second entry never
#   starts before the first's terminal receipt is written. Appends one
#   normalized measurement line per entry to <output_jsonl>.
#
#   Every entry's command is checked against Step 13's
#   aid_test_audit_check_allowed BEFORE it is ever handed to aid-job.sh — a
#   real Codex review of this plan's whole EPIC 2 diff found an earlier
#   version executed every entry directly with no allowlist enforcement
#   anywhere in the production path, letting an arbitrary command from an
#   audit artifact reach real execution via bash -c. A rejected command is
#   never run — this function fails loudly instead (visible on stderr, per
#   the allowlist's own contract), never silently skipped.
aid_test_audit_measure_run_all() {
  local mode="$1" jobs_dir="$2" commands_json="$3" output_jsonl="$4" execution_yaml="$5" approved_catalog="$6"
  mkdir -p "$jobs_dir"
  mkdir -p "$(dirname "$output_jsonl")"
  : > "$output_jsonl"

  local count i entry run_unit_id command_json deadline line
  count="$(jq 'length' <<<"$commands_json")"
  for ((i = 0; i < count; i++)); do
    entry="$(jq -c ".[$i]" <<<"$commands_json")"
    run_unit_id="$(jq -r '.run_unit_id' <<<"$entry")"
    command_json="$(jq -c '.command' <<<"$entry")"
    deadline="$(jq -r '.deadline_seconds // 60' <<<"$entry")"

    if ! aid_test_audit_check_allowed "$mode" "$command_json" "$execution_yaml" "$approved_catalog"; then
      echo "aid-test-audit-measure: refusing to run disallowed command for $run_unit_id — aborting the whole measurement run" >&2
      return 1
    fi

    line="$(_tam_run_one "$jobs_dir" "$run_unit_id" "$command_json" "$deadline")" || return 1
    printf '%s\n' "$line" >> "$output_jsonl"
  done
  return 0
}
