#!/usr/bin/env bash
# aid-test-scheduler.sh — P069 Step 5.
#
# Deterministic batch scheduler for P066 catalog run_units + this plan's
# membership-verified execution units (Step 1/2). Shipped behind a
# `sequential` default: with mode=sequential, every batch executes size-1
# regardless of computed parallel.status — this is the SAME code path
# observe_parallel/parallel modes later reuse, never a second "real"
# scheduler behind the sequential one.
#
# Effective-status resolution: for each unit, the status this scheduler
# batches by is the approved test-scheduler-parallel-overlay.yaml's
# promoted_status for that run_unit_id IF an approved, non-stale entry
# exists (catalog_fingerprint_at_promotion matches the unit's CURRENT
# catalog runtime.fingerprint); otherwise the catalog's own parallel.status,
# UNCHANGED. This repo's real catalog today has every unit at `unknown` —
# this scheduler correctly produces N sequential size-1 batches until an
# overlay entry is approved. That is the expected, safe starting state, not
# a defect.
#
# Process-lifecycle: every unit's aid-job.sh job record is written under one
# scheduler-owned directory
# (.aid-o/work/test-audits/<run-id>/scheduler-jobs/) per invocation. A TERM/
# INT received mid-batch cancels every outstanding unit (aid-job.sh cancel,
# which itself blocks until a terminal result exists) before re-raising/
# exiting — never an orphaned process group. A new dispatch is refused while
# any prior batch's jobs directory still has non-terminal entries.
#
# Job-id retry-scoping: every unit's aid-job.sh --id is
# "<run-id>-<unit_id>-attempt<N>" (sanitized) — a gate-level retry (same
# run-id, new --attempt) never reuses or collides with a prior attempt's
# job-id/terminal receipt for the same unit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-execution-unit.sh
source "${SCRIPT_DIR}/lib/aid-test-execution-unit.sh"
# shellcheck source=lib/aid-test-catalog-provenance.sh
source "${SCRIPT_DIR}/lib/aid-test-catalog-provenance.sh"

_die() { echo "aid-test-scheduler.sh: $2" >&2; exit "$1"; }

# _sched_jobs_dir <project_root> <run_id>
_sched_jobs_dir() {
  printf '%s' "${1}/.aid-o/work/test-audits/${2}/scheduler-jobs"
}

# _sched_check_no_outstanding <jobs_dir> — fails closed, naming stuck job ids
# (or a live concurrent dispatch, via the .dispatch-active marker below).
_sched_check_no_outstanding() {
  local jobs_dir="$1"
  [[ -d "$jobs_dir" ]] || return 0

  # A live .dispatch-active marker means another dispatch process for this
  # SAME run-id is currently between "checked clear" and "finished writing
  # its first job record" — the narrow window the flock below closes. A
  # marker naming a DEAD pid is stale (a crashed prior dispatch) and is
  # cleared, never treated as a blocker.
  if [[ -f "$jobs_dir/.dispatch-active" ]]; then
    local marker_pid; marker_pid="$(cat "$jobs_dir/.dispatch-active" 2>/dev/null)"
    if [[ -n "$marker_pid" ]] && kill -0 "$marker_pid" 2>/dev/null; then
      echo "aid-test-scheduler.sh: refusing to dispatch — another dispatch (pid $marker_pid) is currently active for this run-id" >&2
      return 1
    fi
    rm -f "$jobs_dir/.dispatch-active" 2>/dev/null
  fi

  local d
  local -a stuck=()
  for d in "$jobs_dir"/*/; do
    [[ -f "$d/job.json" ]] || continue
    [[ -f "$d/result.json" ]] && continue
    stuck+=("$(basename "$d")")
  done
  if [[ ${#stuck[@]} -gt 0 ]]; then
    echo "aid-test-scheduler.sh: refusing to dispatch — prior batch's jobs directory still has non-terminal entries: ${stuck[*]}" >&2
    return 1
  fi
  return 0
}

# _sched_plan_batches <mode> <units_status_json> <max_workers>
#   units_status_json: [{unit_id, effective_status, resolved_locks[]}, ...]
#   in caller-determined (unit_id-sorted) order. Emits a JSON array of
#   batches (each a JSON array of unit_id strings) to stdout.
#
#   mode=sequential: every unit its own batch (Implementation Detail).
#   Otherwise: unknown/exclusive units are ALWAYS their own batch.
#   safe/constrained units are greedily appended to the immediately
#   preceding safe/constrained batch if it has spare capacity (< max_workers)
#   and none of this unit's resolved_locks overlap any already-batched
#   member's resolved_locks — a deliberate "append to the last compatible
#   batch only" simplification (documented, not a full bin-packing search
#   across all open batches), sufficient for this step's scope.
_sched_plan_batches() {
  local mode="$1" units_status_json="$2" max_workers="$3"

  if [[ "$mode" == "sequential" ]]; then
    jq -c '[.[] | [.unit_id]]' <<<"$units_status_json"
    return 0
  fi

  local n; n="$(jq 'length' <<<"$units_status_json")"
  local batches_json="[]"
  local last_kind="" i
  for ((i = 0; i < n; i++)); do
    local unit_id status locks_json
    unit_id="$(jq -r ".[$i].unit_id" <<<"$units_status_json")"
    status="$(jq -r ".[$i].effective_status" <<<"$units_status_json")"
    locks_json="$(jq -c ".[$i].resolved_locks" <<<"$units_status_json")"

    if [[ "$status" != "safe" && "$status" != "constrained" ]]; then
      batches_json="$(jq -c --arg u "$unit_id" '. + [[$u]]' <<<"$batches_json")"
      last_kind=""
      continue
    fi

    local appended=0
    local last_idx; last_idx=$(( $(jq 'length' <<<"$batches_json") - 1 ))
    if [[ -n "$last_kind" && "$last_idx" -ge 0 ]]; then
      local last_batch_json last_size
      last_batch_json="$(jq -c ".[$last_idx]" <<<"$batches_json")"
      last_size="$(jq 'length' <<<"$last_batch_json")"
      if [[ "$last_size" -lt "$max_workers" ]]; then
        local fits
        fits="$(jq -n --argjson locks "$locks_json" --argjson batch "$last_batch_json" --argjson su "$units_status_json" '
          ($batch | map(. as $m | ($su | map(select(.unit_id==$m)) | .[0].resolved_locks)) | flatten) as $existing_locks
          | ($locks | any(. as $l | $existing_locks | index($l) != null) | not)
        ')"
        if [[ "$fits" == "true" ]]; then
          batches_json="$(jq -c --argjson idx "$last_idx" --arg u "$unit_id" '.[$idx] += [$u]' <<<"$batches_json")"
          appended=1
        fi
      fi
    fi
    if [[ "$appended" -eq 0 ]]; then
      batches_json="$(jq -c --arg u "$unit_id" '. + [[$u]]' <<<"$batches_json")"
    fi
    last_kind="$status"
  done
  echo "$batches_json"
}

cmd_dispatch() {
  local project_root="" run_id="" units_file="" mode="sequential" max_workers=4 attempt=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="$2"; shift 2 ;;
      --run-id) run_id="$2"; shift 2 ;;
      --units-json) units_file="$2"; shift 2 ;;
      --mode) mode="$2"; shift 2 ;;
      --max-workers) max_workers="$2"; shift 2 ;;
      --attempt) attempt="$2"; shift 2 ;;
      *) _die 2 "dispatch: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$project_root" && -n "$run_id" && -n "$units_file" ]] || _die 2 "dispatch: --project-root, --run-id, --units-json are required"
  case "$mode" in sequential|observe_parallel|parallel) ;; *) _die 2 "dispatch: --mode must be sequential|observe_parallel|parallel" ;; esac
  [[ "$attempt" =~ ^[0-9]+$ && "$attempt" -ge 1 ]] || _die 2 "dispatch: --attempt must be a positive integer"
  # Codex review: an unvalidated --max-workers is later used as a bash
  # arithmetic operand ([[ ... -lt "$max_workers" ]]) — bash arithmetic
  # recursively evaluates array-subscript-shaped operands, including command
  # substitutions, so an unchecked value is a real injection surface.
  [[ "$max_workers" =~ ^[0-9]+$ && "$max_workers" -ge 1 ]] || _die 2 "dispatch: --max-workers must be a positive integer"
  # Codex review: run_id is interpolated directly into a filesystem path
  # (_sched_jobs_dir) and into every unit's aid-job.sh --id — same charset
  # discipline as aid-job.sh's own JOB_ID_RE, closing the path-traversal
  # surface a value like "../../etc" would otherwise open.
  [[ "$run_id" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || _die 2 "dispatch: --run-id must match ^[A-Za-z0-9._-]{1,128}\$"
  [[ "$run_id" != *..* ]] || _die 2 "dispatch: --run-id must not contain '..' (path-traversal guard)"

  project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "dispatch: --project-root does not exist"
  [[ -f "$units_file" ]] || _die 3 "dispatch: --units-json '$units_file' does not exist"
  local units_json; units_json="$(cat "$units_file")"
  jq -e 'type=="array" and length > 0' <<<"$units_json" >/dev/null 2>&1 || _die 1 "dispatch: --units-json must be a non-empty JSON array"

  # Membership-verification precondition (Step 2 dependency) — a unit
  # without it is rejected before batching, never silently scheduled.
  local unverified unv_count
  unverified="$(jq -c '[.[] | select(.membership_verified != true)]' <<<"$units_json")"
  unv_count="$(jq 'length' <<<"$unverified")"
  if [[ "$unv_count" -gt 0 ]]; then
    echo "aid-test-scheduler.sh: refusing to schedule ${unv_count} unit(s) without membership_verified:true:" >&2
    jq -r '.[].unit_id' <<<"$unverified" >&2
    exit 1
  fi

  local catalog_path="${project_root}/.aid-o/config/test-catalog.yaml"
  [[ -f "$catalog_path" ]] || _die 3 "dispatch: no approved catalog at $catalog_path"
  local catalog_json; catalog_json="$(yq -o=json '.' "$catalog_path")"

  # Stale membership_binding rejection — identical treatment to a missing stamp.
  local stale stale_count
  stale="$(jq -c --argjson cat "$catalog_json" '
    ($cat.run_units | map({(.run_unit_id): .runtime.fingerprint}) | add // {}) as $fp
    | [.[] | select((.membership_binding.catalog_fingerprint // null) != ($fp[.unit_id] // null))]
  ' <<<"$units_json")"
  stale_count="$(jq 'length' <<<"$stale")"
  if [[ "$stale_count" -gt 0 ]]; then
    echo "aid-test-scheduler.sh: refusing to schedule ${stale_count} unit(s) with a stale/missing membership_binding.catalog_fingerprint:" >&2
    jq -r '.[].unit_id' <<<"$stale" >&2
    exit 1
  fi

  local overlay_path="${project_root}/.aid-o/config/test-scheduler-parallel-overlay.yaml"
  local overlay_json='{"schema_version":"1.0.0","status":"approved","overlay":[]}'
  [[ -f "$overlay_path" ]] && overlay_json="$(yq -o=json '.' "$overlay_path")"

  # resource_locks resolution map — execution.yaml's
  # test_audit.scheduler.resource_locks (Step 1's authority). Absent config
  # means identity mapping (a lock name resolves to itself).
  local exec_yaml="${project_root}/.aid-o/config/execution.yaml"
  local locks_map_json='{}'
  if [[ -f "$exec_yaml" ]]; then
    locks_map_json="$(yq -o=json '.test_audit.scheduler.resource_locks // {}' "$exec_yaml" 2>/dev/null || echo '{}')"
    [[ -z "$locks_map_json" || "$locks_map_json" == "null" ]] && locks_map_json='{}'
  fi

  # Per-unit effective status + resolved locks, for exactly the requested units.
  # The effective status comes from the SHARED resolver, which applies the
  # provenance reversion rule first and the overlay only on top of it. Reading
  # `.parallel.status` here and applying the overlay locally made this a second
  # authority: the lane runner could retire a unit whose sources had moved
  # while this one still dispatched it as safe.
  local eff_map_json
  eff_map_json="$(aid_test_catalog_effective_status_map "$catalog_path" "$project_root" "$overlay_json" 2>/dev/null || echo '{}')"
  [[ -n "$eff_map_json" ]] || eff_map_json='{}'

  local units_status_json
  units_status_json="$(jq -c --argjson cat "$catalog_json" --argjson eff "$eff_map_json" --argjson lm "$locks_map_json" '
    ($cat.run_units | map({(.run_unit_id): .}) | add) as $by_id
    | [ .[] | .unit_id as $uid
        | ($by_id[$uid]) as $ru
        | (if $ru == null then error("dispatch: unit_id not found in catalog: " + $uid) else $ru end) as $ru
        | { unit_id: $uid, effective_status: ($eff[$uid] // "unknown"),
            resolved_locks: [ ($ru.parallel.exclusive_resources // [])[] | ($lm[.] // .) ] }
      ] | sort_by(.unit_id)
  ' <<<"$units_json")" || exit 1

  local batches_json
  batches_json="$(_sched_plan_batches "$mode" "$units_status_json" "$max_workers")"

  local jobs_dir; jobs_dir="$(_sched_jobs_dir "$project_root" "$run_id")"
  mkdir -p "$jobs_dir"

  # Codex review: "check no outstanding, then mkdir/dispatch" was
  # check-then-act with no mutex — two concurrent dispatches for the SAME
  # run_id could both pass the check before either creates a job. A flock
  # makes the check+claim atomic across processes — but it must be RELEASED
  # before any job is launched, never held for the whole dispatch: aid-job.sh
  # run's `setsid bash ... &` detaches a process that INHERITS this shell's
  # open file descriptors, so a lock "held" past that point would actually
  # keep being held by the detached wrapper long after this script exits
  # (verified: caused a real, reproducible false "dispatch already in
  # progress" failure on an immediately-following attempt in this repo's own
  # bats suite). The lock instead only guards writing a `.dispatch-active`
  # marker (this process's pid); _sched_check_no_outstanding treats a marker
  # naming a LIVE pid as a blocker (a real concurrent dispatch), and a marker
  # naming a dead pid as stale (cleared, never a blocker) — the real job
  # records this process goes on to create are what keep a genuinely
  # overlapping later dispatch out, exactly as before.
  local lockfile="${jobs_dir}.lock"
  local lock_fd
  exec {lock_fd}>"$lockfile"
  flock -n "$lock_fd" || _die 1 "dispatch: another dispatch is already in progress for run-id '$run_id' (lock held on $lockfile)"
  _sched_check_no_outstanding "$jobs_dir" || { flock -u "$lock_fd"; exit 1; }
  local dispatch_marker="${jobs_dir}/.dispatch-active"
  echo "$$" > "$dispatch_marker"
  flock -u "$lock_fd"
  exec {lock_fd}>&-
  # Double-quoted (expand NOW, not at trap time): $dispatch_marker is a
  # `local` to this function and would be an unbound variable under
  # `set -u` by the time the EXIT trap actually fires (after this function
  # has returned) if deferred via single-quoting.
  trap "rm -f '$dispatch_marker' 2>/dev/null" EXIT

  local -a outstanding_job_ids=()
  _sched_on_term() {
    echo "aid-test-scheduler.sh: signal received — cancelling ${#outstanding_job_ids[@]} outstanding unit(s)" >&2
    local jid
    for jid in "${outstanding_job_ids[@]}"; do
      bash "$_AID_JOB_SH" cancel --jobs-dir "$jobs_dir" --id "$jid" >/dev/null 2>&1 || true
      # aid-job.sh cancel already blocks (up to its own ~5s internal budget)
      # for a terminal result, but under real system load that budget can
      # elapse before the signalled wrapper finishes writing result.json —
      # the TERM was still delivered and IS still being honored, it just
      # hasn't landed yet. Poll a bit longer here so this scheduler's own
      # AC ("every outstanding unit reaches a terminal receipt before this
      # process exits") holds regardless of aid-job.sh's own timing, rather
      # than exiting the instant cancel's blocking call happens to return.
      local waited=0
      while [[ ! -f "$jobs_dir/$jid/result.json" && "$waited" -lt 300 ]]; do
        sleep 0.1
        waited=$((waited + 1))
      done
    done
    exit 143
  }
  trap _sched_on_term TERM INT

  local ctx="$mode"
  local receipts_json="[]"
  # Real dispatch-lifecycle span (Codex review, Step 8: both start_at and
  # ended_at were previously computed AFTER everything completed and set
  # to the SAME instant, so any downstream duration_ms derived from them
  # was always 0 — captured here, before any batch launches, so the batch
  # document's own timestamps mean what its schema/consumers assume).
  local batch_started_at; batch_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local num_batches; num_batches="$(jq 'length' <<<"$batches_json")"
  local bi
  for ((bi = 0; bi < num_batches; bi++)); do
    local batch_unit_ids_json; batch_unit_ids_json="$(jq -c ".[$bi]" <<<"$batches_json")"
    outstanding_job_ids=()
    local -A unit_to_job=()

    local -A run_failed=()
    local uid
    while IFS= read -r uid; do
      local unit_json job_id run_rc=0
      unit_json="$(jq -c --arg u "$uid" '.[] | select(.unit_id == $u)' <<<"$units_json")"
      job_id="$(_execution_unit_sanitize_id "${run_id}-${uid}-attempt${attempt}")"
      unit_to_job["$uid"]="$job_id"
      # Track this job-id as outstanding BEFORE launching it (real,
      # reproducible race found in this repo's own bats suite: appending
      # AFTER execution_unit_run returns leaves a narrow window — bash
      # checks for a pending trap between simple commands — where a TERM
      # arriving between the launch returning and this array append sees
      # ZERO outstanding jobs and cancels nothing, orphaning an already-
      # running unit). Cancelling a job-id that never actually got created
      # (see run_rc handling below) is harmless — aid-job.sh cancel fails
      # closed with "no such job" and this trap already ignores that (`||
      # true`).
      outstanding_job_ids+=("$job_id")
      # Codex review: a terminal_fail/timed_out/cancelled unit is an
      # EXPECTED, routine scheduling outcome, not a scheduler-level error —
      # under `set -e`, an unguarded nonzero exit from either call here
      # would abort the whole scheduler mid-batch, orphaning every other
      # still-running peer in this batch. Neither call is allowed to do
      # that; failures are recorded and the batch continues.
      execution_unit_run "$unit_json" "$jobs_dir" "$job_id" >/dev/null 2>&1 || run_rc=$?
      if [[ "$run_rc" -ne 0 ]]; then
        echo "aid-test-scheduler.sh: execution_unit_run failed for unit '$uid' (job-id $job_id never started) — recording as a failure, continuing the batch" >&2
        run_failed["$uid"]=1
        # Remove the optimistic tracking entry — no job was ever created,
        # so there is nothing for the TERM handler to cancel for this id.
        local -a _kept=()
        local _jid2
        for _jid2 in "${outstanding_job_ids[@]}"; do
          [[ "$_jid2" == "$job_id" ]] || _kept+=("$_jid2")
        done
        outstanding_job_ids=("${_kept[@]}")
        continue
      fi
    done < <(jq -r '.[]' <<<"$batch_unit_ids_json")

    while IFS= read -r uid; do
      if [[ -n "${run_failed[$uid]:-}" ]]; then
        local co_json_f r_f
        co_json_f="$(jq -c --arg u "$uid" '[.[] | select(. != $u)]' <<<"$batch_unit_ids_json")"
        r_f="$(jq -nc --arg u "$uid" --arg j "${unit_to_job[$uid]}" --argjson csw "$co_json_f" --arg cc "$ctx" \
          '{unit_id:$u, job_id:$j, state:"lost", duration_ms:null, concurrency_context:$cc, co_scheduled_with:$csw, stdout_path:null, exit_code:null}')"
        receipts_json="$(jq -c --argjson r "$r_f" '. + [$r]' <<<"$receipts_json")"
        continue
      fi
      local job_id="${unit_to_job[$uid]}"
      while [[ ! -f "$jobs_dir/$job_id/result.json" ]]; do
        sleep 0.2
      done
      local co_json r receipt_rc=0
      co_json="$(jq -c --arg u "$uid" '[.[] | select(. != $u)]' <<<"$batch_unit_ids_json")"
      r="$(execution_unit_receipt "$jobs_dir" "$job_id" "$uid" "$ctx" "$co_json")" || receipt_rc=$?
      receipts_json="$(jq -c --argjson r "$r" '. + [$r]' <<<"$receipts_json")"
    done < <(jq -r '.[]' <<<"$batch_unit_ids_json")

    outstanding_job_ids=()
  done

  trap - TERM INT

  local batch_id="${run_id}-attempt${attempt}"
  local started_at ended_at
  started_at="$batch_started_at"
  ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -nc --arg bid "$batch_id" --argjson units "$(jq -Sc 'sort_by(.unit_id)' <<<"$receipts_json")" \
    --arg sa "$started_at" --arg ea "$ended_at" \
    '{batch_id:$bid, units:$units, started_at:$sa, ended_at:$ea}'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    dispatch) shift; cmd_dispatch "$@" ;;
    *)
      echo "Usage: aid-test-scheduler.sh dispatch --project-root <path> --run-id <id> --units-json <file> [--mode sequential|observe_parallel|parallel] [--max-workers N] [--attempt N]" >&2
      exit 1
      ;;
  esac
fi
