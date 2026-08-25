#!/usr/bin/env bash
# =============================================================================
# lib/aid-hook-rules-turn.sh — two rules about the course of a turn
# (P087 Step 5)
#
#   aid_turn_open_steps <state_root> [since_epoch]  (shared probe, read-only)
#   aid_hook_rule_turn_step_open                     (Stop-event handler)
#   aid_hook_rule_turn_write_scope                   (PreToolUse-event handler)
#
# RULE 1 — A TURN DOES NOT END ON A HALF-DONE STEP (Stop, controller, degree 2)
#   A step is OPEN when its dispatch contract exists (the controller handed
#   the packet out) and the run's `current_step` still points at it (the
#   controller never advanced). Ending the turn there leaves an agent's work
#   uncommitted, unverified and unmerged — the exact state a compaction or a
#   closed laptop turns into lost work. The rule refuses the Stop and names
#   what to do. Two honest exits: the turn HANDS OVER explicitly — its last
#   message is a Decision card or a Blocked card (the labels in
#   defaults/decision-card-labels.yaml) — or the run is no longer in EXECUTE.
#
#   Only THIS session's steps count. The probe takes the session's start (the
#   transcript's first timestamp) and looks at contracts written after it;
#   another session's half-done run is not this turn's to finish.
#
# RULE 2 — A WRITE OUTSIDE THE STEP'S PATHS IS NAMED (PreToolUse, any, degree 3)
#   The contract carries the allowed paths, so the moment a Write/Edit names
#   a path outside them the rule can say so — before the edit lands, with the
#   path and the list. It DELIVERS that as context and does not block: the
#   ecosystem standard and P086 both measured that this catch sees Write and
#   Edit and never a shell redirection, and a guard with a hole that size
#   must not be sold as a guard. What holds the line is the contract
#   validation at return time (lib/aid-dispatch-contract.sh), which sees the
#   disk. This is the earlier, cheaper feedback.
#
# NEITHER RULE WRITES ANYTHING. Both read the state root the event names.
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-25
# =============================================================================
[[ -n "${_AID_HOOK_RULES_TURN_SH_LOADED:-}" ]] && return 0
_AID_HOOK_RULES_TURN_SH_LOADED=1

_AID_HRT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_HRT_LIB_DIR}/aid-roots.sh"
# shellcheck source=aid-decision-card.sh
source "${_AID_HRT_LIB_DIR}/aid-decision-card.sh"
# shellcheck source=aid-dispatch-contract.sh
source "${_AID_HRT_LIB_DIR}/aid-dispatch-contract.sh"

# ---------------------------------------------------------------------------
# aid_turn_open_steps <state_root> [since_epoch]
#   Prints ONE tab-separated line per open step, current step first:
#     <epic_id> <run_id> <step_index> <step_id> <contract_path>
#   and returns 0; returns 1 when no step is open. With <since_epoch>, a
#   contract older than that instant is not this session's and is skipped.
#
#   A step is open when it has a contract and the run has not advanced past
#   it (index >= current_step). In a concurrent wave that is SEVERAL steps at
#   once, which is why this prints all of them — a rule that only knew the
#   current index would judge every other agent of the wave by the wrong
#   packet. "Active" is read from the runs' own state files, not from a
#   registry; a stale run is filtered by the session window, not bookkeeping.
# ---------------------------------------------------------------------------
aid_turn_open_steps() {
  local root="${1:?open-steps: state root required}" since="${2:-0}"
  local sf state epic run cur n i plan sid contract mtime found=0
  while IFS= read -r sf; do
    [[ -n "$sf" ]] || continue
    state="$(grep -m1 '^state:' "$sf" 2>/dev/null | awk '{print $2}')"
    [[ "$state" == "EXECUTE" ]] || continue
    cur="$(grep -m1 '^current_step:' "$sf" 2>/dev/null | awk '{print $2}')"
    [[ "$cur" =~ ^[0-9]+$ ]] || continue
    plan="$(dirname "$sf")/plan.json"
    [[ -f "$plan" ]] || continue
    n="$(jq -r '.steps | length' "$plan" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || continue
    epic="$(grep -m1 '^epic_id:' "$sf" | awk '{print $2}')"
    run="$(grep -m1 '^run_id:' "$sf" | awk '{print $2}')"
    for (( i=cur; i<n; i++ )); do
      sid="$(jq -r --argjson i "$i" '.steps[$i].id // ""' "$plan" 2>/dev/null)"
      [[ -n "$sid" ]] || continue
      contract="$(dirname "$sf")/steps/${sid}/contract.json"
      [[ -f "$contract" ]] || continue
      mtime="$(stat -c %Y "$contract" 2>/dev/null || echo 0)"
      (( mtime >= since )) || continue
      printf '%s\t%s\t%s\t%s\t%s\n' "$epic" "$run" "$i" "$sid" "$contract"
      found=1
    done
  done < <(find "${root}/.aid-o/work/evidence" -mindepth 3 -maxdepth 3 -name fsm-state.yaml 2>/dev/null | sort)
  (( found ))
}

# _aid_hrt_session_start <transcript> — the session's first timestamp as an
# epoch, or 0 when the transcript does not say.
_aid_hrt_session_start() {
  local ts
  ts="$(head -c 65536 "$1" 2>/dev/null | jq -r 'select(.timestamp != null) | .timestamp' 2>/dev/null | head -1)"
  [[ -n "$ts" ]] || { echo 0; return 0; }
  date -u -d "$ts" +%s 2>/dev/null || echo 0
}

# _aid_hrt_hands_over <text_file> — does the turn's last message open a
# Decision card (validated by the card library) or a Blocked card (its label
# in any configured language)? 0 yes, 1 no.
_aid_hrt_hands_over() {
  local f="$1" rc=0
  aid_decision_card_validate "$f" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] && return 0
  local lang label
  while IFS= read -r lang; do
    [[ -n "$lang" ]] || continue
    label="$(_aid_dc_label "$lang" blocked)"
    [[ -n "$label" ]] && grep -q "^${label}:" "$f" 2>/dev/null && return 0
  done <<< "$(yq -r '.languages | keys | .[]' "$(_aid_dc_labels_file)" 2>/dev/null)"
  return 1
}

# ---------------------------------------------------------------------------
# aid_hook_rule_turn_step_open — Stop handler. 0 nothing open · 2 refuse ·
# 3 not applicable (no workspace, no transcript, or the turn hands over).
# ---------------------------------------------------------------------------
aid_hook_rule_turn_step_open() {
  local input; input="$(cat)"
  local cwd transcript
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)"
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  local root
  root="$(cd "$cwd" && aid_state_root 2>/dev/null)" || { echo "cwd is not inside an AID workspace" >&2; return 3; }

  local since=0
  if [[ -n "$transcript" && -r "$transcript" ]]; then
    since="$(_aid_hrt_session_start "$transcript")"
  else
    echo "no readable transcript — the session window is unknown, so no step can be attributed to this turn" >&2
    return 3
  fi

  local line
  line="$(aid_turn_open_steps "$root" "$since" | head -1)"
  [[ -n "$line" ]] || { echo "no step of this session is open" >&2; return 0; }
  local epic run idx sid
  IFS=$'\t' read -r epic run idx sid _ <<< "$line"

  local last tmp
  last="$(jq -rs '[.[] | select(.type == "assistant")] | last
                  | (.message.content // []) | map(select(.type == "text") | .text) | join("\n")' \
          "$transcript" 2>/dev/null)"
  if [[ -n "$last" && "$last" != "null" ]]; then
    tmp="$(mktemp)" || { echo "no temp file for the card check" >&2; return 3; }
    printf '%s\n' "$last" > "$tmp"
    if _aid_hrt_hands_over "$tmp"; then
      rm -f "$tmp"
      echo "step ${idx} (${sid}) of ${epic} is open, but the turn hands over explicitly with a card" >&2
      return 3
    fi
    rm -f "$tmp"
  fi

  echo "step ${idx} (${sid}) of ${epic}/${run} was dispatched under a contract and the run has not advanced past it. Finish it before the turn ends: extract and validate the agent's aid-return (lib/aid-dispatch-contract.sh), commit the accepted return, write step-${idx}-verify.md and run aid-fsm.sh increment-step — or hand over explicitly with a Decision card or a Blocked card." >&2
  return 2
}

# _aid_hrt_relative <path> <cwd> — a repo-relative path for the tree the
# write lands in. Absolute paths are made relative to that tree's top level;
# relative ones are taken as they are.
_aid_hrt_relative() {
  local path="$1" cwd="$2" top
  [[ "$path" == /* ]] || { printf '%s' "$path"; return 0; }
  top="$(cd "$(dirname "$path")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" \
    || top="$(cd "$cwd" && git rev-parse --show-toplevel 2>/dev/null)" || top="$cwd"
  printf '%s' "${path#"${top%/}/"}"
}

# ---------------------------------------------------------------------------
# aid_hook_rule_turn_write_scope — PreToolUse handler. 0 (with a notice on
# stdout when the path is outside the step's paths, silence when it is
# inside) · 3 not applicable.
# ---------------------------------------------------------------------------
aid_hook_rule_turn_write_scope() {
  local input; input="$(cat)"
  local tool path cwd
  tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)"
  case "$tool" in Write|Edit|MultiEdit|NotebookEdit) ;; *) echo "not a file write (${tool:-no tool})" >&2; return 3 ;; esac
  path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)"
  [[ -n "$path" ]] || { echo "the write names no path" >&2; return 3; }
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  local root
  root="$(cd "$cwd" && aid_state_root 2>/dev/null)" || { echo "cwd is not inside an AID workspace" >&2; return 3; }

  # The same session window as the Stop rule, when the payload names a
  # transcript; without one, any open step's contract is the best available
  # answer and the notice says which step it is.
  local since=0 transcript
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)"
  [[ -n "$transcript" && -r "$transcript" ]] && since="$(_aid_hrt_session_start "$transcript")"
  # The hook cannot tell WHICH agent of a wave is writing, so a path inside
  # ANY open step's paths is inside scope; the notice lists every open step
  # with its paths, and the return validation of the right step settles it.
  local lines
  lines="$(aid_turn_open_steps "$root" "$since")" || { echo "no step is open — nothing declares paths" >&2; return 3; }
  local rel sid contract allowed summary=""
  rel="$(_aid_hrt_relative "$path" "$cwd")"
  while IFS=$'\t' read -r _ _ _ sid contract; do
    [[ -n "$sid" ]] || continue
    allowed="$(jq -c '.allowed_paths // []' "$contract")"
    _aid_dc_path_allowed "$rel" "$allowed" "steps/${sid}" && return 0
    summary="${summary:+$summary; }${sid}: $(jq -r 'join(", ")' <<< "$allowed")"
  done <<< "$lines"
  printf 'AID: this write lands OUTSIDE the open step'"'"'s allowed paths — %s. Open steps may change: %s. An edit outside them will be named in the contract validation and the step refused; stop and re-check the packet before continuing.\n' \
    "$rel" "$summary"
  echo "write outside allowed paths: ${rel}" >&2
  return 0
}
