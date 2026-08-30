#!/usr/bin/env bash
# =============================================================================
# lib/aid-session-store.sh — where hook-side state lives (P086 Step 1)
#
#   aid_session_store_dir <subdir>   prints (and creates) the directory
#
# WHY THIS EXISTS
#   Two ecosystem rules meet here. Hooks must not write into repositories
#   (/ecosystem/specs/agent-hooks/ rule 6), and AID's own state root
#   (`.aid-o/`) is a working tree even though it is gitignored. So hook-side
#   state — the audit trail, the canary verdict, the continuity capsule —
#   lives OUTSIDE any checkout, in the user's state directory.
#
#   It is deliberately NOT `lib/aid-roots.sh`: that lib answers "which
#   checkout owns this run's state" and every path it returns is inside a
#   working tree. This one answers "where does a hook write", and the correct
#   answer is "nowhere near the tree".
#
# LAYOUT
#   ${XDG_STATE_HOME:-$HOME/.local/state}/aid/<subdir>/
#     hooks/       audit.jsonl, trust.json  (Steps 1–2)
#     continuity/  <session_id>.json        (Step 5)
#
#   AID_SESSION_STORE overrides the base for tests and for hosts that keep
#   agent state elsewhere.
#
# ERROR HANDLING
#   An uncreatable directory returns 1 with a message on stderr. Callers
#   degrade — none of them may block work because state could not be written.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-24
# =============================================================================
[[ -n "${_AID_SESSION_STORE_SH_LOADED:-}" ]] && return 0
_AID_SESSION_STORE_SH_LOADED=1

aid_session_store_dir() {
  local subdir="${1:?aid_session_store_dir: subdir required}"
  local base="${AID_SESSION_STORE:-${XDG_STATE_HOME:-$HOME/.local/state}/aid}"
  local dir="${base}/${subdir}"
  if ! mkdir -p "$dir" 2>/dev/null; then
    echo "ERROR: cannot create AID session store directory '$dir'" >&2
    return 1
  fi
  printf '%s\n' "$dir"
}

# ===========================================================================
# aid_session_once <namespace> <session_key> <item_key>
#
# True (0) the FIRST time this session is asked about <item_key>, false (1)
# every time after. The point is not tidiness: a hook rule that repeats the
# same line at every turn teaches the reader to skip all of them, and then the
# one line that mattered is skipped too. Measured 2026-08-30 in a consumer
# project, where an open-plan reminder for a plan the session was not working
# on repeated for a dozen turns and drove the agent into answering "čekám na
# tebe" over and over.
#
# <session_key> is whatever identifies the session to the caller — a hook is
# handed its transcript path, which is per session. <item_key> should carry
# everything that makes the finding DIFFERENT, including the state that made
# it true, so a finding that becomes true again is said again.
#
# FAILURE IS OPEN, deliberately: if the store cannot be written, this returns 0
# (say it) rather than 1 (swallow it). A reminder repeated is a nuisance; a
# reminder lost can be the one that mattered.
# ===========================================================================
aid_session_once() {
  local ns="${1:?aid_session_once: namespace required}"
  local skey="${2-}" item="${3-}"
  [[ -n "$item" ]] || return 0

  # NO IDENTITY, NO MEMORY. An empty session key would hash to one shared file,
  # so session B would be silenced by something session A was told — a reminder
  # swallowed by a session that never received it (Codex, 2026-08-30). Unknown
  # identity therefore means "say it", never "assume it was said".
  [[ -n "$skey" ]] || return 0

  local dir file
  dir="$(aid_session_store_dir "$ns" 2>/dev/null)" || return 0
  file="${dir}/seen-$(printf '%s' "${skey}" | sha256sum 2>/dev/null | cut -c1-16)"
  [[ "$file" == */seen-?* ]] || return 0

  # THE MARKER IS TRUSTED ONLY IF IT CAN STILL BE WRITTEN. A read-only store
  # that already holds the item would otherwise suppress for ever while the
  # function claims to fail open: the read succeeds, the write never could, and
  # nothing new is ever recorded. Establish writability first, and treat its
  # absence as "no memory available" — which means say it.
  if [[ -e "$file" ]]; then
    [[ -w "$file" ]] || return 0
  else
    [[ -w "$dir" ]] || return 0
  fi

  if grep -qxF -- "$item" "$file" 2>/dev/null; then
    return 1
  fi
  printf '%s\n' "$item" >> "$file" 2>/dev/null || return 0
  return 0
}
