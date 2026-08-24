#!/usr/bin/env bash
# =============================================================================
# lib/aid-subagent-protocol.sh — telling a role agent its protocol is not the
# repository's (P086 Step 10)
#
#   aid_hook_rule_subagent_protocol   SubagentStart handler
#
# WHY THIS EXISTS
#   IMP-179, three separate times: a subagent's system prompt comes from the
#   INSTALLED plugin cache, not from the checkout it is working in. An Auditor
#   and a Curator both acted on a protocol that had already changed in the repo,
#   and neither could have known. The workaround has been to paste the current
#   protocol into every dispatch by hand.
#
# WHAT IS MEASURED, AND WHAT THAT ALLOWS
#   Claude Code 2.1.238: a `SubagentStart` hook printing on bare stdout runs,
#   succeeds and delivers NOTHING — the subagent asked about the injected marker
#   answered NO-MARKER. The same text in
#   `hookSpecificOutput.additionalContext` DID arrive. Delivery is therefore
#   real, and the envelope is built once in scripts/aid-hook.sh. Full write-up:
#   docs/plans/P086-subagent-protocol-probe.md.
#
# WHY A POINTER, AND WHY IT DOES NOT SAY "FOLLOW IT"
#   Injecting a role file's CONTENTS out of the working tree would make a
#   checked-out repository able to write part of an agent's instructions. But —
#   and an earlier version of this file got this wrong and said the opposite —
#   a pointer that TELLS the agent to read and follow that file is the same
#   thing with one extra step. Whoever controls the checkout controls what is
#   at the end of the pointer.
#
#   So the notice reports a FACT and asks for nothing: the two copies differ,
#   here are both paths, neither is automatically authoritative, take it to the
#   controller. That is genuinely all a subagent was missing — it could not know
#   its protocol was stale — and it is the most that can be said without
#   handing a repository a channel into an agent's instructions.
#
#   It is also cheap: a few lines whether the role file is two pages or twenty.
#
# IT SAYS NOTHING WHEN THERE IS NOTHING TO SAY
#   Identical copies inject nothing at all, which is the common case — a consumer
#   project has no `plugins/aid-orchestrator/agents/` in its tree, and a
#   dogfooding checkout in sync with its installed plugin has no divergence.
#   Degree 3: this is a delivery. Nothing here makes the subagent act on it.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-24
# =============================================================================
[[ -n "${_AID_SUBAGENT_PROTOCOL_SH_LOADED:-}" ]] && return 0
_AID_SUBAGENT_PROTOCOL_SH_LOADED=1

_AID_SP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AID_SP_PLUGIN_ROOT="$(cd "${_AID_SP_LIB_DIR}/../.." && pwd)"

aid_hook_rule_subagent_protocol() {
  local input; input="$(cat)"
  local agent_type cwd role
  agent_type="$(printf '%s' "$input" | jq -r '.agent_type // .subagent_type // ""' 2>/dev/null)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"

  [[ "$agent_type" == aid-orchestrator:* ]] || {
    echo "not an AID role agent (${agent_type:-<none>}) — nothing to say" >&2; return 3; }
  role="${agent_type#aid-orchestrator:}"
  [[ "$role" =~ ^[a-z][a-z0-9-]*$ ]] || {
    echo "unusable role name '${role}'" >&2; return 3; }
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }

  local installed="${_AID_SP_PLUGIN_ROOT}/agents/${role}.md"
  [[ -r "$installed" ]] || { echo "no installed protocol for role '${role}'" >&2; return 3; }

  local tree; tree="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "cwd is not inside a git checkout — no repository copy to compare against" >&2; return 3; }
  local live="${tree}/plugins/aid-orchestrator/agents/${role}.md"
  [[ -r "$live" ]] || {
    echo "this checkout carries no plugins/aid-orchestrator/agents/${role}.md — nothing to compare" >&2; return 3; }

  # The same file reached two ways is not a divergence.
  if [[ "$(cd "$(dirname "$installed")" && pwd -P)" == "$(cd "$(dirname "$live")" && pwd -P)" ]]; then
    echo "the installed plugin IS this checkout — no divergence possible" >&2; return 3
  fi
  if cmp -s "$installed" "$live"; then
    echo "role '${role}': installed protocol matches the repository's" >&2; return 3
  fi

  cat <<NOTICE
AID protocol notice for role '${role}': your instructions came from the INSTALLED
plugin, and they DIFFER from this checkout's copy of the same role.
  installed (what you were given): ${installed}
  this checkout: ${live}
NEITHER copy is automatically authoritative and this notice asks you to follow
neither. It exists because you could not otherwise know the two disagree. If the
difference matters to your task, say so and let the controller resolve it —
a checkout is not a source of your instructions, and the file's contents are
deliberately not injected here.
NOTICE
  return 0
}
