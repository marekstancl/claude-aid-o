#!/usr/bin/env bash
# aid-test-execution-unit.sh — P069 Step 1.
#
# Sourceable library wrapping aid-job.sh with an execution-unit-shaped
# input/output (see defaults/schemas/execution-unit.schema.json). aid-job.sh
# ITSELF IS NEVER MODIFIED — every invariant it already provides (owned-
# process-only completion, PID-reuse defeat, atomic job.json/result.json,
# process-group cancellation) is inherited unchanged; this file only
# translates between an execution unit's shape and aid-job.sh's own CLI/
# record shape.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-bats.sh's own header for the same idiom).

_EXEC_UNIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AID_JOB_SH="${_EXEC_UNIT_LIB_DIR}/../aid-job.sh"

# _execution_unit_sanitize_id <raw>
#   aid-job.sh's own JOB_ID_RE is '^[A-Za-z0-9._-]{1,128}$'. Real unit_ids
#   (e.g. "bats:scripts/tests/bats/foo.bats") contain ':' and '/', neither
#   allowed. Sanitization is DETERMINISTIC (never random) so the same
#   unit_id always maps to the same job_id family — required for Step 2's
#   retry/attempt-scoping to target it predictably.
#
#   A charset-mapping prefix ALONE is collision-prone (Codex review: "a:b"
#   and "a/b" both map to "a-b", and a naive truncation only makes this
#   worse) — two DISTINCT unit_ids must never produce the SAME job_id, since
#   aid-job.sh run rejects a second `run` under an already-existing id. A
#   short sha256 suffix of the ORIGINAL (pre-mapping) unit_id is appended so
#   collisions are cryptographically implausible regardless of prefix
#   truncation.
_execution_unit_sanitize_id() {
  local raw="$1" mapped hash
  mapped="$(printf '%s' "$raw" | tr -c 'A-Za-z0-9._-' '-')"
  hash="$(printf '%s' "$raw" | sha256sum | cut -c1-16)"
  printf '%s' "${mapped:0:100}-${hash}"
}

# execution_unit_run <unit_json> <jobs_dir> [job_id]
#   unit_json: a single execution-unit JSON object (string, e.g. `jq -c`
#   output). Builds the correct `aid-job.sh run` invocation from `command`
#   (P066's exact discriminated union: {type:argv,argv:[...]} or
#   {type:shell,shell:"..."}  — never a third shape) and `deadline_seconds`.
#   Emits the job_id to stdout on success (matches aid-job.sh run's own
#   stdout contract).
execution_unit_run() {
  local unit_json="$1" jobs_dir="$2" job_id="${3:-}"
  local unit_id deadline cmd_type

  unit_id="$(jq -r '.unit_id // empty' <<<"$unit_json")"
  deadline="$(jq -r '.deadline_seconds // empty' <<<"$unit_json")"
  cmd_type="$(jq -r '.command.type // empty' <<<"$unit_json")"

  [[ -n "$unit_id" ]] || { echo "execution_unit_run: unit_id required" >&2; return 1; }
  [[ "$deadline" =~ ^[0-9]+$ && "$deadline" -gt 0 ]] || {
    echo "execution_unit_run: deadline_seconds must be a positive integer" >&2
    return 1
  }

  [[ -n "$job_id" ]] || job_id="$(_execution_unit_sanitize_id "$unit_id")"

  case "$cmd_type" in
    argv)
      local -a argv=()
      # NUL-delimited decode (Codex review: a line-based `jq -r` + `mapfile
      # -t` silently splits any argv element containing an embedded
      # newline, which the schema permits, into two arguments — matching
      # the same NUL-safe idiom already used by
      # aid-test-audit-measure.sh:48).
      mapfile -d '' -t argv < <(jq -j '.command.argv[] | . + "\u0000"' <<<"$unit_json")
      [[ ${#argv[@]} -gt 0 ]] || { echo "execution_unit_run: command.argv must be non-empty" >&2; return 1; }
      bash "$_AID_JOB_SH" run --jobs-dir "$jobs_dir" --id "$job_id" \
        --deadline "$deadline" --label test-execution -- "${argv[@]}"
      ;;
    shell)
      local shell_cmd
      shell_cmd="$(jq -r '.command.shell' <<<"$unit_json")"
      bash "$_AID_JOB_SH" run --jobs-dir "$jobs_dir" --id "$job_id" \
        --deadline "$deadline" --label test-execution -- bash -c "$shell_cmd"
      ;;
    *)
      echo "execution_unit_run: unsupported command.type '$cmd_type' — must be argv|shell (P066's exact discriminated union)" >&2
      return 1
      ;;
  esac
}

# execution_unit_status <jobs_dir> <job_id>
#   Thin pass-through. The caller-visible state IS aid-job.sh's own state
#   vocabulary (started|running|terminal_pass|terminal_fail|timed_out|
#   cancelled|lost) — this step introduces no second, competing vocabulary.
execution_unit_status() {
  local jobs_dir="$1" job_id="$2"
  bash "$_AID_JOB_SH" status --jobs-dir "$jobs_dir" --id "$job_id"
}

# execution_unit_cancel <jobs_dir> <job_id>
#   Thin pass-through to aid-job.sh cancel (process-group signal + terminal
#   cancelled result). No execution-unit-specific behavior to add here.
execution_unit_cancel() {
  local jobs_dir="$1" job_id="$2"
  bash "$_AID_JOB_SH" cancel --jobs-dir "$jobs_dir" --id "$job_id"
}

# execution_unit_receipt <jobs_dir> <job_id> <unit_id> [concurrency_context=sequential] [co_scheduled_with_json=[]]
#   Normalizes aid-job.sh's record into a Step 4 execution-unit-receipt.schema.json
#   -shaped row: {unit_id, job_id, state, duration_ms, concurrency_context,
#   co_scheduled_with, stdout_path, exit_code}. concurrency_context/
#   co_scheduled_with default to "sequential"/[] (Codex review — a whole-EPIC
#   pass found this function's output, called standalone, could not satisfy
#   Step 4's canonical schema at all since it never emitted either field):
#   this function has no batch/scheduling knowledge of its own, so a
#   standalone call is, correctly, a sequential size-1 batch of one; Step 5's
#   (P078: the scheduler that once overrode both is removed — every caller
#   is sequential now, so the defaults are simply the truth.)
#
#   duration_ms/exit_code are null while non-terminal — never fabricated
#   from a partial run. Exit code mirrors aid-job.sh collect's own contract
#   (0 pass / 1 fail / 3 not-terminal) so callers can reuse the same
#   branching; classification of "not terminal yet" is by ABSENCE of a
#   terminal result.json, never a literal string match on a live-state name.
#
#   duration_ms is quantized to whole seconds (Codex review): aid-job.sh's
#   own result record has only integer-epoch started_epoch/ended_epoch —
#   the same second-granularity limitation aid-test-audit-measure.sh:32
#   already documents for its own duration_ms. This wrapper never touches
#   aid-job.sh, so it cannot add sub-second precision that isn't recorded.
#   ended_epoch is ALSO absent on some valid terminal records — the
#   pre-exec-handshake cancelled result (_wrap_write_cancelled_result,
#   aid-job.sh) never ran the command and carries no ended_epoch at all —
#   so duration_ms is null for those, never a failed arithmetic subtraction.
execution_unit_receipt() {
  local jobs_dir="$1" job_id="$2" unit_id="$3" concurrency_context="${4:-sequential}" co_scheduled_with_json="${5:-[]}"
  local job_dir="$jobs_dir/$job_id"
  [[ -d "$job_dir" && -f "$job_dir/job.json" ]] || {
    echo "execution_unit_receipt: no such job: $job_id (under $jobs_dir)" >&2
    return 2
  }

  local stdout_path started_epoch
  stdout_path="$(jq -r '.stdout_path' "$job_dir/job.json")"
  started_epoch="$(jq -r '.started_epoch' "$job_dir/job.json")"

  if [[ ! -f "$job_dir/result.json" ]]; then
    local live_state
    live_state="$(execution_unit_status "$jobs_dir" "$job_id")"
    jq -nc --arg u "$unit_id" --arg j "$job_id" --arg s "$live_state" --arg sp "$stdout_path" \
      --arg cc "$concurrency_context" --argjson csw "$co_scheduled_with_json" \
      '{unit_id:$u, job_id:$j, state:$s, duration_ms:null, concurrency_context:$cc, co_scheduled_with:$csw, stdout_path:$sp, exit_code:null}'
    return 3
  fi

  jq -c --arg u "$unit_id" --arg sp "$stdout_path" --argjson se "$started_epoch" \
    --arg cc "$concurrency_context" --argjson csw "$co_scheduled_with_json" \
    '{unit_id:$u, job_id:.id, state:.state, concurrency_context:$cc, co_scheduled_with:$csw,
      duration_ms:(if .ended_epoch == null then null else ((.ended_epoch - $se) * 1000) end),
      stdout_path:$sp, exit_code:.exit_code}' "$job_dir/result.json"

  local st; st="$(jq -r '.state' "$job_dir/result.json")"
  [[ "$st" == "terminal_pass" ]] && return 0 || return 1
}
