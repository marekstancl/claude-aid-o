#!/usr/bin/env bash
# =============================================================================
# lib/aid-hook-canary.sh — the proof-of-life rule (P086 Step 2)
#
#   aid_hook_canary   registry handler for SessionStart
#
# WHY A RULE THAT DOES NOTHING IS THE POINT
#   /ecosystem/specs/agent-hooks/ rule 1 ("ověření, ne víra") asks for a hook
#   that writes a record on every run, plus a check that the record appeared.
#   This is that hook. Its whole effect is the dispatcher's audit line: if the
#   line is there, a harness really did call AID; if it is not, every claim the
#   hook layer makes about enforcement is unfounded — which is exactly what
#   `scripts/aid-hook-verify.sh --canary` goes looking for.
#
#   It exits 3 (not applicable) rather than 0 so the audit line carries a
#   reason string, and so it can never inject a word into a model's prompt: a
#   rule whose only job is to leave a trace has no business writing to stdout.
#
# COST: one bash function per session start, no I/O of its own. It is
# deliberately not registered for a per-turn event.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-24
# =============================================================================
[[ -n "${_AID_HOOK_CANARY_SH_LOADED:-}" ]] && return 0
_AID_HOOK_CANARY_SH_LOADED=1

aid_hook_canary() {
  cat > /dev/null
  echo "canary: the AID hook layer was reached for ${AID_HOOK_EVENT:-<unknown event>}" >&2
  return 3
}
