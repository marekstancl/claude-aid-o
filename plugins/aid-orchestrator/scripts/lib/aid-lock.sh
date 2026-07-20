#!/usr/bin/env bash
# =============================================================================
# aid-lock.sh — generic flock-based sidecar lock/lease helper
# (P064 "Plan Branch Substrate", EPIC E-064-1_2, Step 1).
#
# WHY THIS EXISTS: three call sites already hand-roll the exact same
# sidecar-flock idiom — `scripts/aid-emit-dispatch.sh:130-140` (twice),
# `scripts/lib/aid-cp1-ledger.sh:424-428` and
# `scripts/lib/aid-gate-runtime-baseline.sh:129-131` (twice) — each opening a
# `<data_file>.lock` sidecar via `exec {fd}>lockfile` and calling
# `flock -x -w <n> <fd>` inside a subshell scoped to that one critical
# section. This file generalizes that idiom into two functions so the next
# consumers (`aid-plan-state.sh`, below; `lib/aid-queue-write.sh`, a later
# step; the P068 plan-final runner) don't re-derive it a fourth time.
#
# WHY A SIDECAR FILE, NEVER THE DATA FILE ITSELF: every writer in this
# codebase rotates its data file's inode on write (`mktemp` + `mv`, so the
# old inode is unlinked and a new one takes the path). If two processes
# opened the DATA file directly and one raced the other's mv, the second
# opener could land on the NEW inode and acquire a completely different
# (unrelated, already-satisfied) lock — a real race, documented in detail at
# `scripts/aid-emit-dispatch.sh:130-136` (the "H11" fix). The sidecar
# `<path>.lock` file is never rotated, so its inode is stable for the life of
# the lock file — this file is a generalization of that same reasoning, not a
# new decision.
#
# ── LIFETIME MODEL (why this is NOT a subshell-scoped `( flock ...; body )`
#    like the three ad-hoc call sites use) ───────────────────────────────────
# The existing call sites wrap the whole critical section in a subshell so
# the lock's fd and its release are both scoped to that one `( ... )`. This
# library instead exposes acquire/release as two separate calls so a caller
# can hold a lock across MULTIPLE statements (e.g. read-validate-write, or a
# read followed by an append) without having to nest its entire body inside
# one subshell. This only works because `aid_lock_acquire` is a *function*,
# not a subprocess: `exec {fd}>"$lock_path"` opens the descriptor in the
# CALLER's own shell (functions execute in the same process, only command
# substitution/pipelines fork), so the fd — and the flock held on it — stays
# open after `aid_lock_acquire` returns, until the caller explicitly calls
# `aid_lock_release`. Concretely, this means callers must invoke
# `aid_lock_acquire` as a plain statement, e.g.:
#   aid_lock_acquire "$lock_path" 10 || exit $?
#   fd="$AID_LOCK_FD"          # copy immediately — see AID_LOCK_FD note below
#   ... critical section ...
#   aid_lock_release "$fd"
# NEVER `fd=$(aid_lock_acquire ...)` — that forks a subshell, the fd would be
# opened and immediately closed with that subshell, and the lock would be
# released before the caller ever saw it.
#
# AID_LOCK_FD — the mechanism for returning the acquired descriptor. Bash
# redirection targets (`exec {fd}>path`) cannot be `printf`'d and re-consumed
# by a *different* shell/subshell without losing the open file description,
# so the fd is communicated back to the caller via this global, which
# `aid_lock_acquire` sets on success. Copy it into a local variable right
# away if you might call `aid_lock_acquire` again for a different lock before
# releasing the first one (each acquire call overwrites the global).
#
# ── SOURCEABLE-SAFE CONVENTION ───────────────────────────────────────────────
# NO top-level `set -e`/`set -euo pipefail` (matches aid-gate-runtime-baseline.sh,
# aid-gate-profile.sh, aid-cache-preflight.sh, aid-delivery-profile.sh,
# aid-review-signals.sh) — this file is sourced directly into callers running
# under their OWN `set -euo pipefail`, and an unguarded non-zero return here
# must not silently abort a caller's larger flow before it gets a chance to
# check the return code. Every public function returns an explicit code;
# nothing here relies on `set -e` to propagate failure.
#
# ── USAGE ────────────────────────────────────────────────────────────────────
#   Sourced (the real, intended usage):
#     source .../lib/aid-lock.sh
#     if aid_lock_acquire "$lock_path" 10; then
#       fd="$AID_LOCK_FD"
#       ...critical section...
#       aid_lock_release "$fd"
#     else
#       # rc 3: could not acquire within the timeout (or could not open the
#       # sidecar at all) — never blocks indefinitely.
#     fi
#
#   Standalone (debugging / bats convenience — see `main` below):
#     bash aid-lock.sh acquire <lock_path> [timeout_s]
#     bash aid-lock.sh hold    <lock_path> <hold_s> [acquire_timeout_s]
#
# Exit codes (functions, as `return`; standalone CLI mirrors them as `exit`):
#   aid_lock_acquire: 0 = lock held (AID_LOCK_FD set), 3 = any failure
#     (missing lock_path, invalid timeout, cannot open sidecar, or timed out
#     waiting for the lock) — always 3, never a hang.
#   aid_lock_release: 0 = closed, 1 = bad/missing fd argument or already closed.
#
# **Last Updated:** 2026-07-20
# =============================================================================

# Default wait, matching lib/aid-cp1-ledger.sh:427's established 10s budget.
AID_LOCK_DEFAULT_TIMEOUT_S=10

# Set by aid_lock_acquire on success; "" otherwise. See the lifetime-model
# note above for why this global exists and how to use it safely.
AID_LOCK_FD=""

_aid_lock_warn() {
  echo "WARN: aid-lock.sh: $*" >&2
}

# ---------------------------------------------------------------------------
# aid_lock_acquire <lock_path> [timeout_s]
#
# Opens (creating if needed) a dedicated sidecar lock file at <lock_path> —
# this must be a `.lock` sidecar next to the real data file, NEVER the data
# file itself (see header rationale) — and attempts an exclusive flock with a
# bounded wait. On success, records this process's pid inside the lock file
# (purely informational, see Edge Cases below) and sets AID_LOCK_FD to the
# open descriptor number.
#
# timeout_s defaults to AID_LOCK_DEFAULT_TIMEOUT_S (10) when omitted.
#
# Returns 0 on success (AID_LOCK_FD set). Returns 3 on ANY failure — a
# missing/empty lock_path, a non-numeric timeout, an unopenable sidecar path,
# or exceeding the wait — this function never blocks indefinitely.
# ---------------------------------------------------------------------------
aid_lock_acquire() {
  local lock_path="${1:-}"
  local timeout_s="${2:-$AID_LOCK_DEFAULT_TIMEOUT_S}"

  AID_LOCK_FD=""

  if [[ -z "$lock_path" ]]; then
    _aid_lock_warn "aid_lock_acquire: lock_path is required"
    return 3
  fi
  if ! [[ "$timeout_s" =~ ^[0-9]+$ ]]; then
    _aid_lock_warn "aid_lock_acquire: timeout_s must be a non-negative integer (got '$timeout_s')"
    return 3
  fi
  if ! command -v flock >/dev/null 2>&1; then
    _aid_lock_warn "aid_lock_acquire: flock not found on PATH"
    return 3
  fi

  local lock_dir
  lock_dir="$(dirname -- "$lock_path")"
  if [[ ! -d "$lock_dir" ]]; then
    mkdir -p -- "$lock_dir" 2>/dev/null || {
      _aid_lock_warn "aid_lock_acquire: cannot create lock directory $lock_dir"
      return 3
    }
  fi

  # Dynamic fd allocation (bash 4.1+): {fd} picks a free descriptor and binds
  # it to the variable `fd`. Opened `<>` (read+write, create-if-missing, NO
  # truncation) — NOT a plain `>` output redirect — because a `>` open would
  # truncate the sidecar to empty on EVERY acquire attempt, including a
  # losing/contending one, destroying the current holder's recorded pid
  # before we ever call flock and thus before we know we lost. `<>` creates
  # the file if needed but leaves existing content (the holder's pid, if
  # any) intact for a losing attempt to read back below. This opens in THIS
  # shell — see the lifetime-model note in the header for why this must not
  # run inside a subshell/command-sub.
  local fd
  if ! exec {fd}<>"$lock_path"; then
    _aid_lock_warn "aid_lock_acquire: cannot open lock sidecar $lock_path"
    return 3
  fi

  if ! flock -x -w "$timeout_s" "$fd"; then
    local holder
    holder="$(cat "$lock_path" 2>/dev/null)"
    [[ -n "$holder" ]] || holder="unknown"
    echo "PRECONDITION FAIL: lock timeout (${timeout_s}s) on $lock_path (pid recorded in lock file: ${holder})" >&2
    eval "exec ${fd}>&-" 2>/dev/null
    return 3
  fi

  # Record our pid — informational only (see Edge Cases: flock releases on
  # descriptor close including process death, so a stale pid here never
  # blocks the next acquire; it only helps a human/log reader see who last
  # held it, and is reported back to a losing acquirer on timeout above).
  # A plain truncating write to the PATH (not through $fd, which is opened
  # non-truncating) is safe here: it overwrites content in place without
  # rotating the inode (unlike this codebase's `mktemp`+`mv` data-file
  # convention), and the flock we hold is bound to the open file
  # description on $fd, not to the file's byte content, so rewriting the
  # content through a second, independent open cannot disturb it.
  printf '%s\n' "$$" > "$lock_path" 2>/dev/null || true

  AID_LOCK_FD="$fd"
  return 0
}

# ---------------------------------------------------------------------------
# aid_lock_release <fd>
#
# Closes the file descriptor previously returned via AID_LOCK_FD, releasing
# the flock held on it (flock releases automatically when the last fd
# referencing the open file description is closed).
#
# Returns 0 on success. Returns 1 if <fd> is missing/not a plain integer, or
# if the close itself fails (e.g. already closed).
# ---------------------------------------------------------------------------
aid_lock_release() {
  local fd="${1:-}"
  if [[ -z "$fd" ]] || ! [[ "$fd" =~ ^[0-9]+$ ]]; then
    _aid_lock_warn "aid_lock_release: fd argument must be a file descriptor number (got '${fd:-<empty>}')"
    return 1
  fi

  # `exec N>&-` closes fd N. The `[n]` slot in a redirection is not
  # parameter-expanded by bash's parser (only a literal integer or a `{name}`
  # is accepted there), so a variable holding the fd number requires `eval`.
  # `fd` was validated above to be digits-only, so this is not an injection
  # vector.
  if ! eval "exec ${fd}>&-" 2>/dev/null; then
    _aid_lock_warn "aid_lock_release: failed to close fd $fd (already closed?)"
    return 1
  fi

  [[ "$AID_LOCK_FD" == "$fd" ]] && AID_LOCK_FD=""
  return 0
}

# ===========================================================================
# Standalone CLI — debugging / bats convenience only (mirrors the idiom in
# aid-gate-runtime-baseline.sh). The real, intended usage is sourcing this
# file (see header). `acquire` runs in a single throwaway subprocess so it
# cannot demonstrate the "hold across multiple statements" lifetime model —
# it exists so a test can assert acquire/timeout behavior from a subprocess.
# `hold` is the more useful one: it lets a bats test background a REAL,
# separate process holding the lock, to exercise aid_lock_acquire's timeout
# path (rc 3) against genuine contention rather than same-process trickery.
# ===========================================================================
_aid_lock_usage() {
  cat <<'EOF'
Usage: aid-lock.sh <subcommand> [args...]

Subcommands:
  acquire <lock_path> [timeout_s]
      Try to acquire the lock once, print "OK <fd>" and release it
      immediately. Exit 0 on success, 3 on failure/timeout.

  hold <lock_path> <hold_s> [acquire_timeout_s]
      Acquire the lock, print "HELD <pid>", sleep for hold_s seconds, then
      release. Intended to be backgrounded by a test so a separate,
      concurrent process genuinely holds the lock.
EOF
}

main() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    acquire)
      local path="${1:?lock_path required}" timeout="${2:-$AID_LOCK_DEFAULT_TIMEOUT_S}"
      if aid_lock_acquire "$path" "$timeout"; then
        echo "OK $AID_LOCK_FD"
        aid_lock_release "$AID_LOCK_FD"
        exit 0
      fi
      exit 3
      ;;
    hold)
      local path="${1:?lock_path required}" hold_s="${2:?hold_s required}" timeout="${3:-$AID_LOCK_DEFAULT_TIMEOUT_S}"
      if aid_lock_acquire "$path" "$timeout"; then
        echo "HELD $$"
        sleep "$hold_s"
        aid_lock_release "$AID_LOCK_FD"
        exit 0
      fi
      exit 3
      ;;
    -h|--help|"")
      _aid_lock_usage
      [[ -z "$sub" ]] && exit 2
      exit 0
      ;;
    *)
      _aid_lock_usage >&2
      echo "ERROR: unknown subcommand: $sub" >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
