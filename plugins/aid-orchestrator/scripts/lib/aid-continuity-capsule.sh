#!/usr/bin/env bash
# =============================================================================
# lib/aid-continuity-capsule.sh — what a session must not forget when its
# context is compacted (P086 Step 5)
#
#   aid_hook_rule_continuity_capture   PreCompact handler — writes the capsule
#   aid_hook_rule_continuity_restore   SessionStart handler — puts it back
#
# WHY THIS EXISTS
#   After a compaction the session's own state — which plan, which run, which
#   tree, and the contract it owes the PM — is gone, and today it is found
#   again by hand. The capsule is written before the context is cut and read
#   back after.
#
# IT IS A DELIVERY, NOT A GUARANTEE — DEGREE 3, AND THAT IS THE WHOLE POINT
#   `SessionStart` injection puts text in front of a model. It does not make
#   the model use it, and in Codex an unapproved hook is skipped in silence, so
#   it may not even be delivered. That is why this does NOT replace the gate
#   that inserts the contract on the normal path: the gate keeps inserting, and
#   the capsule is cover for the runs that did not go through it. Anything that
#   treats the capsule as the contract's home has moved an obligation onto a
#   mechanism that cannot carry it.
#
# WHERE IT LIVES, AND WHY NOT IN THE WORKSPACE
#   The session store (lib/aid-session-store.sh), never `.aid-o/`. A hook does
#   not write into a repository (/ecosystem/specs/agent-hooks/ rule 6) and
#   `.aid-o/` is a working tree even though it is gitignored. The capsule is
#   ephemeral and per session; nothing but the restore reads it.
#
# WHICH TREE THE SESSION WAS IN
#   The capsule records both roots, because they are genuinely different
#   questions: `invoke_root` is the tree the session was working in — a plan's
#   worktree, a phase copy — and `state_root` is where `.aid-o/` lives, which
#   lib/aid-roots.sh always resolves to the primary checkout. A restored
#   session that knows only the second one goes back to work in the wrong tree.
#
# THE AGE IS ALWAYS SHOWN
#   A capsule is a snapshot, and a snapshot presented without its age is
#   presented as current. It is stated on the injected block, every time,
#   whether it is two minutes or two days old.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-24
# =============================================================================
[[ -n "${_AID_CONTINUITY_CAPSULE_SH_LOADED:-}" ]] && return 0
_AID_CONTINUITY_CAPSULE_SH_LOADED=1

_AID_CC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_CC_LIB_DIR}/aid-roots.sh"
# shellcheck source=aid-session-store.sh
source "${_AID_CC_LIB_DIR}/aid-session-store.sh"

# The one line the capsule carries about how AID must talk to the PM. It names
# the contract rather than restating it: a copy here would be a second
# definition of the cards, which skills/communication.md forbids.
_AID_CC_CONTRACT="Every message to the PM is one of the four cards in skills/communication.md; a card that asks for a decision needs options, a recommendation and its reason (scripts/aid-turn-gate.sh checks the written one)."

aid_continuity_capsule_path() {
  local session_id="${1:?capsule path: session id required}" dir
  dir="$(aid_session_store_dir continuity)" || return 1
  printf '%s/%s.json' "$dir" "$session_id"
}

# _aid_cc_runs <state_root> — the live runs, with the transitions the FSM
# itself says are allowed from each. The transitions are ASKED FOR
# (`aid-fsm.sh verify-state`), never re-derived here: a second copy of the
# transition table in a hook is a second authority, and the one that drifts is
# always the copy. A run whose state cannot be read keeps its state and loses
# only the transitions.
_aid_cc_runs() {
  local root="$1" runs="${1}/.aid-o/work/active-runs.json"
  [[ -r "$runs" ]] || { printf '[]'; return 0; }
  local fsm="${_AID_CC_LIB_DIR}/../aid-fsm.sh"
  local out="[]" epic state_file state rid
  while IFS=$'\t' read -r epic rid state state_file; do
    [[ -n "$epic" ]] || continue
    local allowed="[]"
    if [[ -x "$fsm" || -f "$fsm" ]] && [[ -f "$state_file" ]]; then
      allowed="$(timeout 10 bash "$fsm" verify-state "$state_file" 2>/dev/null \
                 | jq -c '.allowed_transitions // []' 2>/dev/null)" || allowed="[]"
      [[ -n "$allowed" ]] || allowed="[]"
    fi
    out="$(printf '%s' "$out" | jq -c --arg e "$epic" --arg r "$rid" --arg s "$state" \
            --arg f "$state_file" --argjson a "$allowed" \
            '. + [{epic_id:$e, run_id:$r, state:$s, state_file:$f, allowed_transitions:$a}]')"
  done < <(jq -r 'to_entries[] | [.key, (.value.run_id // ""), (.value.state // ""), (.value.state_file // "")] | @tsv' "$runs" 2>/dev/null)
  printf '%s' "$out"
}

# _aid_cc_plans <state_root> — each open plan's phase and its worktree.
_aid_cc_plans() {
  local root="$1" out="[]" f
  for f in "${root}"/.aid-o/work/plan-state/*/plan-state.yaml; do
    [[ -r "$f" ]] || continue
    local id ps wt
    id="$(yq -r '.plan_id // ""' "$f" 2>/dev/null)"
    ps="$(yq -r '.plan_state // ""' "$f" 2>/dev/null)"
    wt="$(yq -r '.worktree_path // ""' "$f" 2>/dev/null)"
    [[ -n "$id" && "$ps" != "CLOSED" && "$ps" != "ABORTED" ]] || continue
    out="$(printf '%s' "$out" | jq -c --arg i "$id" --arg s "$ps" --arg w "$wt" \
            '. + [{plan_id:$i, plan_state:$s, worktree_path:$w}]')"
  done
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# PreCompact: write the capsule. NEVER refuses — a compaction blocked because
# a snapshot could not be written would be this rule causing the damage it
# exists to prevent.
# ---------------------------------------------------------------------------
aid_hook_rule_continuity_capture() {
  local input; input="$(cat)"
  local session_id cwd
  session_id="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"

  [[ -n "$session_id" ]] || { echo "no session id in the event — the capsule is per session and has nothing to key on" >&2; return 3; }
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }

  local invoke_root state_root
  invoke_root="$(cd "$cwd" && aid_invoke_root 2>/dev/null)" || invoke_root="$cwd"
  state_root="$(cd "$cwd" && aid_state_root 2>/dev/null)" || {
    echo "cwd is not inside an AID workspace — nothing to capture" >&2; return 3; }

  local file; file="$(aid_continuity_capsule_path "$session_id")" || {
    echo "the session store is not writable — the capsule was skipped and the compaction was not held up" >&2; return 3; }

  jq -n --arg sid "$session_id" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg ir "$invoke_root" --arg sr "$state_root" --arg c "$_AID_CC_CONTRACT" \
        --argjson plans "$(_aid_cc_plans "$state_root")" \
        --argjson runs "$(_aid_cc_runs "$state_root")" \
    '{session_id:$sid, written_at:$at, invoke_root:$ir, state_root:$sr,
      contract:$c, plans:$plans, runs:$runs}' > "$file" 2>/dev/null || {
    echo "the capsule could not be written to ${file} — the compaction was not held up" >&2; return 3; }

  echo "capsule written: ${file}" >&2
  return 0
}

# ---------------------------------------------------------------------------
# SessionStart: put it back — on a CONTINUATION only. A fresh start has
# nothing to continue, and injecting a stale block into one would be inventing
# a context the session does not have.
# ---------------------------------------------------------------------------
aid_hook_rule_continuity_restore() {
  local input; input="$(cat)"
  local session_id source
  session_id="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)"
  source="$(printf '%s' "$input" | jq -r '.source // ""' 2>/dev/null)"

  case "$source" in
    compact|resume|fork) ;;
    *) echo "start source '${source:-<none>}' is not a continuation — nothing to restore" >&2; return 3 ;;
  esac
  [[ -n "$session_id" ]] || { echo "no session id in the event" >&2; return 3; }

  local file; file="$(aid_continuity_capsule_path "$session_id")" || { echo "the session store is unreadable" >&2; return 3; }
  # Keyed on the session id exactly, and no fallback to "the newest capsule
  # lying around": a fork that gets a new id gets no capsule, which is a gap.
  # Handing it another session's state would be worse than the gap.
  [[ -r "$file" ]] || { echo "no capsule for session ${session_id} — this continuation has none to restore" >&2; return 3; }

  local written age_min
  written="$(jq -r '.written_at // ""' "$file" 2>/dev/null)"
  age_min="unknown"
  if [[ -n "$written" ]]; then
    local w n
    w="$(date -u -d "$written" +%s 2>/dev/null)" || w=""
    n="$(date -u +%s)"
    [[ -n "$w" ]] && age_min="$(( (n - w) / 60 ))"
  fi

  jq -r --arg age "$age_min" '
    "[AID continuity — restored from a capsule written \($age) minute(s) ago, at \(.written_at)]",
    "Working tree: \(.invoke_root)",
    "State root:   \(.state_root)",
    "Contract:     \(.contract)",
    (if (.plans | length) > 0
     then "Open plans:   " + ([.plans[] | "\(.plan_id) — \(.plan_state)" + (if .worktree_path != "" then " (worktree \(.worktree_path))" else "" end)] | join("; "))
     else "Open plans:   none" end),
    (if (.runs | length) > 0
     then "Live runs:    " + ([.runs[] | "\(.epic_id) \(.run_id) — \(.state)" + (if (.allowed_transitions | length) > 0 then ", next allowed: \(.allowed_transitions | join("/"))" else ", next allowed: unread" end)] | join("; "))
     else "Live runs:    none" end),
    "This is a snapshot, not the current state — re-read it before acting on it."
  ' "$file" 2>/dev/null || { echo "the capsule at ${file} is unreadable" >&2; return 3; }

  return 0
}
