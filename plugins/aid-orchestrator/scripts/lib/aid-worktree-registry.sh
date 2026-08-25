#!/usr/bin/env bash
# =============================================================================
# lib/aid-worktree-registry.sh — what the plan-state records about execution
# worktrees, read back and judged (P087 Step 7)
#
#   aid_worktree_registry_scan <state_root>     one line per recorded tree
#   aid_hook_rule_worktree_registry              (SessionStart-event handler)
#
# WHY THIS EXISTS
#   Registration already happens: `plan-start` records the plan's worktree in
#   plan-state (P074) and `plan-close` / `plan-rollback` clear it. What did
#   not exist is anyone READING the record when it matters — at the start of
#   a session, after a crash, when a tree is gone or a closed plan's tree is
#   still on disk because its teardown was deferred. This is the reader.
#
# THE RECORD IS JUDGED, NEVER ACTED ON
#   Every verdict here is a sentence and a command the operator can run.
#   Nothing deletes a tree, ever: a missing one is offered `--recreate-worktree`
#   (the audited repair), a leftover one is offered `plan-close` (the audited
#   teardown) — and a tree that exists may hold work nobody has looked at.
#   The hook runs inside a session start, where /ecosystem/specs/agent-hooks/
#   rule 6 forbids writing anyway; the same restraint holds for the CLI form.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-25
# =============================================================================
[[ -n "${_AID_WORKTREE_REGISTRY_SH_LOADED:-}" ]] && return 0
_AID_WORKTREE_REGISTRY_SH_LOADED=1

_AID_WR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_WR_LIB_DIR}/aid-roots.sh"

# Terminal plan states: a plan in one of these owes no execution tree.
_AID_WR_TERMINAL='CLOSED ABORTED ROLLED_BACK'

# _aid_wr_registered <root> <path> — does git know <path> as a worktree?
_aid_wr_registered() {
  local root="$1" want phys line
  want="$(cd "$2" 2>/dev/null && pwd -P)" || want="$2"
  while IFS= read -r line; do
    [[ "$line" == worktree\ * ]] || continue
    phys="$(cd "${line#worktree }" 2>/dev/null && pwd -P)" || phys="${line#worktree }"
    [[ "$phys" == "$want" ]] && return 0
  done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
  return 1
}

# ---------------------------------------------------------------------------
# aid_worktree_registry_scan <state_root>
#   For every plan whose state records a worktree_path, one line:
#     <plan_id>\t<plan_state>\t<worktree_path>\t<verdict>\t<what to do>
#   verdict: live     the tree exists and git knows it — nothing to do
#            missing  recorded, but the directory or its registration is gone
#            leftover the plan is terminal and its tree is still there
#   Exit 0 always; nothing recorded prints nothing.
# ---------------------------------------------------------------------------
aid_worktree_registry_scan() {
  local root="${1:?registry: state root required}" sf plan_id state wt verdict hint
  for sf in "$root"/.aid-o/work/plan-state/*/plan-state.yaml; do
    [[ -f "$sf" ]] || continue
    plan_id="$(basename "$(dirname "$sf")")"
    wt="$(grep -m1 '^worktree_path:' "$sf" 2>/dev/null | sed 's/^worktree_path:[[:space:]]*//; s/^"//; s/"$//')"
    [[ -n "$wt" && "$wt" != "null" ]] || continue
    state="$(grep -m1 '^plan_state:' "$sf" 2>/dev/null | awk '{print $2}')"
    [[ "$wt" == /* ]] || wt="${root}/${wt}"
    if [[ ! -d "$wt" ]] || ! _aid_wr_registered "$root" "$wt"; then
      verdict="missing"
      hint="the record points at a tree that is not there — repair it (audited, nothing is deleted): aid-plan-fsm.sh plan-state ${plan_id} --recreate-worktree --reason \"<why it went missing>\""
    elif [[ " $_AID_WR_TERMINAL " == *" ${state} "* ]]; then
      verdict="leftover"
      hint="the plan is ${state} but its tree is still on disk (a deferred teardown) — finish it with: aid-plan-fsm.sh plan-close ${plan_id}; inspect ${wt} first, it is never removed automatically"
    else
      verdict="live"; hint=""
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$plan_id" "${state:-?}" "$wt" "$verdict" "$hint"
  done
  return 0
}

# ---------------------------------------------------------------------------
# aid_hook_rule_worktree_registry — SessionStart handler. Injects one notice
# per tree that needs attention; silent (0, no output) when every record is
# live; 3 when the event names no AID workspace.
# ---------------------------------------------------------------------------
aid_hook_rule_worktree_registry() {
  local input; input="$(cat)"
  local cwd root
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  root="$(cd "$cwd" && aid_state_root 2>/dev/null)" || { echo "cwd is not inside an AID workspace" >&2; return 3; }

  local plan state wt verdict hint n=0
  while IFS=$'\t' read -r plan state wt verdict hint; do
    [[ -n "$plan" && "$verdict" != "live" ]] || continue
    (( n == 0 )) && echo "AID worktree registry — records that need a decision (nothing was changed):"
    n=$((n+1))
    printf -- '- %s (%s): %s %s — %s\n' "$plan" "$state" "$verdict" "$wt" "$hint"
  done < <(aid_worktree_registry_scan "$root")
  echo "${n} worktree record(s) need attention" >&2
  return 0
}
