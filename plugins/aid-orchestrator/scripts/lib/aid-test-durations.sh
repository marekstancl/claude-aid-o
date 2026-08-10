#!/usr/bin/env bash
# =============================================================================
# aid-test-durations.sh — per-suite duration journal (P081 Step 1).
#
# WHY THIS EXISTS: tiers are assigned from measured cost, so the measurement
# needs somewhere durable to live. This is that place, and it is the ONLY
# reader/writer of it — the tier assigner, the tier lint and the reaper all
# come through here rather than each parsing the journal their own way.
#
# The journal lives under the STATE ROOT (`aid_state_root`), not under $PWD,
# for the same reason the plan FSM's journals do: a measurement run started
# from a linked worktree must land in the primary checkout, or it disappears
# with the worktree.
#
# CONTRACT
#   aid_durations_file
#     Prints the absolute journal path. Fails (exit 2) when the state root
#     cannot resolve — it NEVER falls back to a cwd-relative path.
#
#   aid_durations_append <suite> <runner> <duration_ms> <exit_code> \
#                        [source] [cases] [censored]
#     Appends ONE record. `source` is `bats_timing` or `wallclock` (default
#     `wallclock`) so a later reader can tell a measured per-case figure from
#     a bracketed wall clock. `cases` defaults to 1 — a `.sh` suite has no
#     case concept and counts as one. `censored` (`true`/`false`, default
#     `false`) marks a run cut short by a deadline, whose duration is a
#     partial and must never be tiered. The measuring HOST is stamped by the
#     writer, not passed in: a duration measured on a different machine than
#     the one it is quoted for is the defect the standard forbids, and it can
#     only be spotted if the record says where it came from.
#
#   aid_durations_latest <suite>          — newest duration_ms, or exit 1.
#   aid_durations_latest_json <suite>     — the whole newest record, or exit 1.
#
# FAIL CLOSED. A journal line this cannot parse aborts the read (exit 3)
# rather than being skipped: a skipped line reads as "this suite was never
# measured", which is exactly the state that lets a suite drift into a tier
# it has not earned.
#
# Records are single-line appends under 4 KB, so two concurrent runs
# interleave safely; ties on `at` are broken by file order (later wins).
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (aid-test-adapter-contract.sh header convention).
#
# Dependencies: bash, jq, git (through aid-roots.sh).
#
# **Last Updated:** 2026-08-10
# =============================================================================

if [[ -n "${_AID_TEST_DURATIONS_SH_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_AID_TEST_DURATIONS_SH_SOURCED=1

_AID_TD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_TD_LIB_DIR}/aid-roots.sh"

AID_DURATIONS_REL="${AID_DURATIONS_REL:-.aid-o/work/test-durations.jsonl}"

aid_durations_file() {
  local root=""
  root="$(aid_state_root)" || {
    echo "aid-test-durations: cannot resolve the state root — refusing to guess where the durations journal lives" >&2
    return 2
  }
  printf '%s\n' "${root}/${AID_DURATIONS_REL}"
}

aid_durations_append() {
  local suite="${1:?aid_durations_append: suite required}"
  local runner="${2:?aid_durations_append: runner required}"
  local duration_ms="${3:?aid_durations_append: duration_ms required}"
  local exit_code="${4:?aid_durations_append: exit_code required}"
  local source="${5:-wallclock}"
  local cases="${6:-1}"
  local censored="${7:-false}"

  [[ "$duration_ms" =~ ^[0-9]+$ ]] || {
    echo "aid-test-durations: duration_ms '$duration_ms' is not a whole number of milliseconds" >&2
    return 2
  }
  [[ "$cases" =~ ^[0-9]+$ ]] || {
    echo "aid-test-durations: cases '$cases' is not a count" >&2
    return 2
  }
  case "$source" in
    bats_timing|wallclock) ;;
    *) echo "aid-test-durations: source '$source' is not one of: bats_timing wallclock" >&2; return 2 ;;
  esac
  case "$censored" in
    true|false) ;;
    *) echo "aid-test-durations: censored '$censored' is not true or false" >&2; return 2 ;;
  esac

  local file; file="$(aid_durations_file)" || return $?
  mkdir -p "$(dirname "$file")" 2>/dev/null || true

  local line
  line="$(jq -nc --arg suite "$suite" --arg runner "$runner" \
    --argjson duration_ms "$duration_ms" --argjson exit_code "$exit_code" \
    --arg source "$source" --argjson cases "$cases" --argjson censored "$censored" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
    --arg host "$(hostname 2>/dev/null || echo unknown)" \
    '{suite:$suite, runner:$runner, duration_ms:$duration_ms, cases:$cases,
      exit_code:$exit_code, source:$source, censored:$censored,
      host:$host, at:$at}')" || return 1

  printf '%s\n' "$line" >> "$file" || {
    echo "aid-test-durations: cannot write '$file' — this measurement is lost" >&2
    return 1
  }
}

# _aid_durations_assert_readable <file> — exit 3 on any line this cannot read.
_aid_durations_assert_readable() {
  local file="$1" bad
  bad="$(jq -Rrn '
    [ inputs
      | select(length > 0)
      | select(
          ((fromjson? | select(type == "object")
            | has("suite") and has("duration_ms") and has("at")) // false) | not)
    ] | length' "$file" 2>/dev/null)" || bad=""
  if [[ -z "$bad" ]]; then
    echo "aid-test-durations: '$file' could not be read at all — refusing to report any suite as unmeasured on the strength of an unreadable journal" >&2
    return 3
  fi
  if [[ "$bad" -gt 0 ]]; then
    echo "aid-test-durations: '$file' has $bad malformed line(s) — refusing to read it; a skipped line looks identical to a suite that was never measured" >&2
    return 3
  fi
}

# aid_durations_readable — 0 when the journal can be read (or does not exist
# yet), 3 when it exists and cannot be. Callers probe ONCE at startup: without
# it, every per-suite read that returns 3 is indistinguishable from "this suite
# was never measured", and a corrupt journal reads as a portfolio nobody has
# ever measured — the fail-closed rule undone one caller at a time.
aid_durations_readable() {
  local file; file="$(aid_durations_file)" || return $?
  [[ -f "$file" ]] || return 0
  _aid_durations_assert_readable "$file"
}

aid_durations_latest_json() {
  local suite="${1:?aid_durations_latest_json: suite required}"
  local file; file="$(aid_durations_file)" || return $?
  [[ -f "$file" ]] || return 1
  _aid_durations_assert_readable "$file" || return $?
  local rec
  # sort_by is stable, so two records sharing a timestamp keep file order and
  # the later append wins.
  rec="$(jq -Rcn --arg s "$suite" '
    [inputs | select(length > 0) | fromjson | select(.suite == $s)]
    | sort_by(.at) | last // empty' "$file")" || return 1
  [[ -n "$rec" ]] || return 1
  printf '%s\n' "$rec"
}

aid_durations_latest() {
  local rec
  rec="$(aid_durations_latest_json "$@")" || return $?
  jq -r '.duration_ms' <<<"$rec"
}
