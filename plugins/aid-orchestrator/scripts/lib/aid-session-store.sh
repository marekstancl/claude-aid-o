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
