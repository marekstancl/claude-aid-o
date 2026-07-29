#!/usr/bin/env bash
# aid-test-audit-state.sh — P066 Step 6.
#
# Interrupt-safe audit progress state machine (test-audit-state.schema.json,
# Step 1). Schema/mock level here — Step 11 (EPIC 2) re-validates this
# against a real multi-wave dispatch; that is a genuine, explicitly stated
# forward dependency, not hidden.
#
# Same durability pattern as aid-gate-runtime-baseline.sh: flock + atomic
# temp-file-then-mv writes, never a torn write. Every mutating operation
# (advance_wave, mark_interrupted, mark_done, resume) holds the flock across
# its ENTIRE read-modify-write — never just the final write — so two
# concurrent mutators can never race a read against each other's write.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell.

_TAS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fixed status order. A single status name can represent more than one wave
# for measure/full modes (e.g. "dispatching" covers both Wave 1 and Wave 2,
# skipped only in static mode) — advance_wave accordingly accepts either the
# immediate next status (a real phase transition) OR a repeat of the CURRENT
# status (one more wave completed within the same phase), always
# incrementing waves_completed by exactly 1. "done" is reached via
# audit_state_mark_done, never advance_wave directly.
_TAS_ORDER=(discovering sharding dispatching consolidating reporting)

_tas_state_file() { printf '%s/audit-state.json' "${1%/}"; }
_tas_lock_file() { printf '%s/.audit-state.lock' "${1%/}"; }

# _tas_waves_for_mode <mode> — the fixed total from Step 1's schema.
_tas_waves_for_mode() {
  case "$1" in
    static) echo 4 ;;
    measure) echo 5 ;;
    full) echo 6 ;;
    *) echo -1 ;;
  esac
}

# _tas_write_locked <file> <new_json> — tmp-then-mv. Caller MUST already
# hold the flock. Returns non-zero (and never touches the real file) on any
# failure — the caller must check this and never report success on a failed
# write.
_tas_write_locked() {
  local file="$1" new_json="$2"
  local tmp="${file}.tmp.$$"
  printf '%s\n' "$new_json" > "$tmp" || { rm -f "$tmp" 2>/dev/null; return 1; }
  jq -e '.' "$tmp" >/dev/null 2>&1 || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# audit_state_init <output_dir> <audit_id> <scope> <mode> <budget_minutes>
#   Validates mode (must be a real enum value with a known wave count) and
#   budget_minutes (must be a positive integer) BEFORE writing anything — a
#   bad CLI/config value must never persist an audit that no later
#   operation (mark_done in particular) could ever complete.
audit_state_init() {
  local output_dir="$1" audit_id="$2" scope="$3" mode="$4" budget_minutes="$5"
  local file lockfile new_json

  if [[ "$(_tas_waves_for_mode "$mode")" == "-1" ]]; then
    echo "aid-test-audit-state: invalid mode '$mode' (must be static|measure|full)" >&2
    return 1
  fi
  if [[ ! "$budget_minutes" =~ ^[1-9][0-9]*$ ]]; then
    echo "aid-test-audit-state: invalid budget_minutes '$budget_minutes' (must be a positive integer)" >&2
    return 1
  fi

  file="$(_tas_state_file "$output_dir")"
  lockfile="$(_tas_lock_file "$output_dir")"
  mkdir -p "$output_dir" 2>/dev/null
  new_json="$(jq -n \
    --arg id "$audit_id" --arg scope "$scope" --arg mode "$mode" --argjson budget "$budget_minutes" \
    '{schema_version:"1.0.0", audit_id:$id, scope:$scope, mode:$mode, status:"discovering", budget:{minutes:$budget}, waves_completed:0, resume_token:null}')"
  (
    flock -w 5 200 || { echo "aid-test-audit-state: could not acquire lock on $lockfile" >&2; exit 1; }
    _tas_write_locked "$file" "$new_json" || { echo "aid-test-audit-state: init write failed" >&2; exit 1; }
  ) 200>"$lockfile"
}

# audit_state_advance_wave <output_dir> <new_status>
#   Holds the lock across the ENTIRE read-validate-write — never re-reads a
#   value another concurrent mutator (mark_interrupted, another advance)
#   could have changed in between. new_status must be the current status
#   (one more wave within the same phase) or its immediate successor. Never
#   advances a status:interrupted/failed/done document — resume first.
audit_state_advance_wave() {
  local output_dir="$1" new_status="$2"
  local file lockfile
  file="$(_tas_state_file "$output_dir")"
  lockfile="$(_tas_lock_file "$output_dir")"
  mkdir -p "$output_dir" 2>/dev/null

  (
    flock -w 5 200 || { echo "aid-test-audit-state: could not acquire lock on $lockfile" >&2; exit 1; }

    local current current_status mode waves_completed expected idx cur_idx new_idx
    current="$(jq -e '.' "$file" 2>/dev/null)" || { echo "aid-test-audit-state: no/corrupt state to advance" >&2; exit 1; }
    current_status="$(jq -r '.status' <<<"$current")"

    case "$current_status" in
      interrupted|failed|done)
        echo "aid-test-audit-state: cannot advance from status '$current_status'" >&2
        exit 1
        ;;
    esac

    mode="$(jq -r '.mode' <<<"$current")"
    waves_completed="$(jq -r '.waves_completed' <<<"$current")"
    expected="$(_tas_waves_for_mode "$mode")"
    if [[ "$waves_completed" -ge "$expected" ]]; then
      echo "aid-test-audit-state: already at mode '$mode''s fixed wave count ($expected) — no further advance is valid, call mark_done" >&2
      exit 1
    fi

    cur_idx=-1 new_idx=-1
    for idx in "${!_TAS_ORDER[@]}"; do
      [[ "${_TAS_ORDER[$idx]}" == "$current_status" ]] && cur_idx=$idx
      [[ "${_TAS_ORDER[$idx]}" == "$new_status" ]] && new_idx=$idx
    done
    if [[ $new_idx -ne $cur_idx && $new_idx -ne $((cur_idx + 1)) ]]; then
      echo "aid-test-audit-state: cannot advance from '$current_status' to '$new_status' (must be the same phase or the immediate next wave)" >&2
      exit 1
    fi

    local updated
    updated="$(jq -c --arg s "$new_status" '.status = $s | .waves_completed += 1' <<<"$current")"
    _tas_write_locked "$file" "$updated" || { echo "aid-test-audit-state: advance_wave write failed" >&2; exit 1; }
  ) 200>"$lockfile"
}

# audit_state_mark_interrupted <output_dir>
#   Stores the pre-interrupt status in resume_token so audit_state_resume
#   can restore it — never re-dispatches a completed wave since
#   waves_completed is untouched. Lock-protected read-modify-write.
audit_state_mark_interrupted() {
  local output_dir="$1"
  local file lockfile
  file="$(_tas_state_file "$output_dir")"
  lockfile="$(_tas_lock_file "$output_dir")"
  mkdir -p "$output_dir" 2>/dev/null

  (
    flock -w 5 200 || { echo "aid-test-audit-state: could not acquire lock on $lockfile" >&2; exit 1; }

    local current current_status
    current="$(jq -e '.' "$file" 2>/dev/null)" || { echo "aid-test-audit-state: no/corrupt state to interrupt" >&2; exit 1; }
    current_status="$(jq -r '.status' <<<"$current")"
    case "$current_status" in
      done|failed|interrupted)
        echo "aid-test-audit-state: cannot interrupt a '$current_status' audit" >&2
        exit 1
        ;;
    esac
    local updated
    updated="$(jq -c --arg tok "$current_status" '.status = "interrupted" | .resume_token = $tok' <<<"$current")"
    _tas_write_locked "$file" "$updated" || { echo "aid-test-audit-state: mark_interrupted write failed" >&2; exit 1; }
  ) 200>"$lockfile"
}

# audit_state_resume <output_dir>
#   Validates schema version + resume_token, restores the pre-interrupt
#   status, clears resume_token, and echoes the resumed state — waves_
#   completed is NEVER modified by resume, so no completed wave is
#   re-dispatched. A concurrent second resume on the same audit-id fails
#   loudly (non-blocking flock) rather than queuing and silently double-
#   processing. `--resume` on a status:failed document refuses without an
#   explicit override. Never echoes a "resumed" state unless the write that
#   persists it actually succeeded.
audit_state_resume() {
  local output_dir="$1"
  local file lockfile
  file="$(_tas_state_file "$output_dir")"
  lockfile="$(_tas_lock_file "$output_dir")"
  mkdir -p "$output_dir" 2>/dev/null

  (
    flock -n 200 || { echo "aid-test-audit-state: another resume is already in progress for this audit" >&2; exit 1; }

    local current schema_version current_status resume_token
    current="$(jq -e '.' "$file" 2>/dev/null)" || { echo "aid-test-audit-state: no/corrupt state to resume" >&2; exit 1; }
    schema_version="$(jq -r '.schema_version // empty' <<<"$current")"
    [[ "$schema_version" == "1.0.0" ]] || { echo "aid-test-audit-state: unsupported/missing schema_version" >&2; exit 1; }

    current_status="$(jq -r '.status' <<<"$current")"
    if [[ "$current_status" == "failed" ]]; then
      echo "aid-test-audit-state: refusing to resume a 'failed' audit without an explicit override" >&2
      exit 1
    fi
    if [[ "$current_status" != "interrupted" ]]; then
      # Idempotent: nothing to resume, current state already reflects it —
      # echo unchanged, never re-process, no write attempted.
      printf '%s\n' "$current"
      exit 0
    fi

    resume_token="$(jq -r '.resume_token // empty' <<<"$current")"
    [[ -n "$resume_token" ]] || { echo "aid-test-audit-state: interrupted state has no resume_token" >&2; exit 1; }

    local updated
    updated="$(jq -c --arg s "$resume_token" '.status = $s | .resume_token = null' <<<"$current")"
    if ! _tas_write_locked "$file" "$updated"; then
      echo "aid-test-audit-state: resume write failed — audit-state.json remains '$current_status', NOT resumed" >&2
      exit 1
    fi
    printf '%s\n' "$updated"
  ) 200>"$lockfile"
}

# audit_state_mark_done <output_dir>
#   Sets status:done only if (a) current status is exactly "reporting" —
#   never "interrupted" or anything else, so an interruption can never be
#   silently converted into a completed audit — AND (b) waves_completed
#   matches the FIXED count for this document's own mode (4/5/6).
audit_state_mark_done() {
  local output_dir="$1"
  local file lockfile
  file="$(_tas_state_file "$output_dir")"
  lockfile="$(_tas_lock_file "$output_dir")"
  mkdir -p "$output_dir" 2>/dev/null

  (
    flock -w 5 200 || { echo "aid-test-audit-state: could not acquire lock on $lockfile" >&2; exit 1; }

    local current current_status mode waves_completed expected
    current="$(jq -e '.' "$file" 2>/dev/null)" || { echo "aid-test-audit-state: no/corrupt state to complete" >&2; exit 1; }
    current_status="$(jq -r '.status' <<<"$current")"
    if [[ "$current_status" != "reporting" ]]; then
      echo "aid-test-audit-state: cannot mark done from status '$current_status' (must be 'reporting')" >&2
      exit 1
    fi
    mode="$(jq -r '.mode' <<<"$current")"
    waves_completed="$(jq -r '.waves_completed' <<<"$current")"
    expected="$(_tas_waves_for_mode "$mode")"
    if [[ "$waves_completed" -ne "$expected" ]]; then
      echo "aid-test-audit-state: waves_completed ($waves_completed) does not match mode '$mode''s fixed count ($expected)" >&2
      exit 1
    fi
    local updated
    updated="$(jq -c '.status = "done"' <<<"$current")"
    _tas_write_locked "$file" "$updated" || { echo "aid-test-audit-state: mark_done write failed" >&2; exit 1; }
  ) 200>"$lockfile"
}
