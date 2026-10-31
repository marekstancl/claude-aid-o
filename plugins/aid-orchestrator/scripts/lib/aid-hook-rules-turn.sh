#!/usr/bin/env bash
# =============================================================================
# lib/aid-hook-rules-turn.sh — two rules about the course of a turn
# (P087 Step 5)
#
#   aid_turn_open_steps <state_root> [transcript]   (shared probe, read-only)
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
#   Only THIS session's steps count: a step is the session's when its
#   transcript holds "Dispatch Contract (version <v>)" of the step's contract —
#   the header the controller pasted into the dispatch. Merely reading the
#   contract never matches; another session's half-done run, even one started
#   later in the same workspace, is not this turn's to finish (P100: a time
#   window blamed one session for another's step). A new transcript (/clear,
#   a new window) no longer holds the header, so its steps stop blocking — as
#   the time window did.
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
# aid_turn_open_steps <state_root> [transcript]
#   Prints ONE tab-separated line per open step, current step first:
#     <epic_id> <run_id> <step_index> <step_id> <contract_path>
#   and returns 0; returns 1 when no step is open. With <transcript>, only the
#   steps that session dispatched (its dispatch header, see RULE 1); the
#   transcript is searched once, however many steps are open.
#
#   A step is open when it has a contract and the run has not advanced past
#   it (index >= current_step). In a concurrent wave that is SEVERAL steps at
#   once, which is why this prints all of them — a rule that only knew the
#   current index would judge every other agent of the wave by the wrong
#   packet. "Active" is read from the runs' own state files, not from a
#   registry; another session's run is filtered by the transcript, not bookkeeping.
# ---------------------------------------------------------------------------
aid_turn_open_steps() {
  local root="${1:?open-steps: state root required}" transcript="${2:-}"
  local sf state epic run cur n i plan sid contract lines=""
  while IFS= read -r sf; do
    [[ -n "$sf" ]] || continue
    # The four fields of the run in one pass over its state file; each is the
    # FIRST line that declares it, as `grep -m1` would take it. Joined with US
    # (0x1f), never a tab: a tab is IFS whitespace, so an absent field would
    # collapse and the next one would be read in its place.
    IFS=$'\x1f' read -r state cur epic run < <(awk '
      /^state:/        && s == "" { s = $2 }
      /^current_step:/ && c == "" { c = $2 }
      /^epic_id:/      && e == "" { e = $2 }
      /^run_id:/       && r == "" { r = $2 }
      END { printf "%s\037%s\037%s\037%s\n", s, c, e, r }' "$sf" 2>/dev/null)
    [[ "$state" == "EXECUTE" ]] || continue
    [[ "$cur" =~ ^[0-9]+$ ]] || continue
    plan="$(dirname "$sf")/plan.json"
    [[ -f "$plan" ]] || continue
    n="$(jq -r '.steps | length' "$plan" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || continue
    for (( i=cur; i<n; i++ )); do
      sid="$(jq -r --argjson i "$i" '.steps[$i].id // ""' "$plan" 2>/dev/null)"
      [[ -n "$sid" ]] || continue
      contract="$(dirname "$sf")/steps/${sid}/contract.json"
      [[ -f "$contract" ]] || continue
      lines+="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$epic" "$run" "$i" "$sid" "$contract" \
        "Dispatch Contract (version $(jq -r '.version // ""' "$contract" 2>/dev/null))")"$'\n'
    done
  done < <(find "${root}/.aid-o/work/evidence" -mindepth 3 -maxdepth 3 -name fsm-state.yaml 2>/dev/null | sort)
  [[ -n "$lines" ]] || return 1
  if [[ -n "$transcript" ]]; then
    local said
    said="$(grep -oF -f <(cut -f6 <<< "$lines" | grep -v -e '(version )$' -e '^$') "$transcript" 2>/dev/null | sort -u)"
    lines="$(awk -F'\t' 'NR == FNR { s[$0] = 1; next } $6 in s' <(printf '%s\n' "$said") - <<< "$lines")"
  fi
  [[ -n "${lines//$'\n'/}" ]] || return 1
  cut -f1-5 <<< "$lines" | grep -v '^$'
}

# _aid_hrt_step_call_pending <transcript> <contract file> <session id> — 0 when something works on THIS step now:
#   its takeover — the step's land.json (next to the contract) says `running`, was started by THIS session
#     (session_id, from CLAUDE_CODE_SESSION_ID) and its pid is aid-step-land.sh, and this session has an unanswered
#     background Bash that runs aid-step-land.sh (the command's text cannot name the run: controllers pass the
#     state file through a variable, quoted or not — so the record does);
#   or its agent — an Agent/Task launched in the background whose prompt carries this step's contract header.
_aid_hrt_step_call_pending() {
  local t="$1" c="$2" sess="${3:-}" idx="${4:-}" ver rec pid
  # 3.13.0: a reviewer or fixer of THIS step dispatched in the background by THIS session (WAN P114 26. 10. 2026: the
  # turn was refused while the CP2 reviewers ran, AID-WAIT knew only aid-job.sh). It counts when, for its focus, the
  # LAST start among all rounds of the step is still in its round's pending ledger (complete and cancel remove exactly
  # their line) with this step and round dir, is younger than its own time limit, and the line it printed —
  # `nonce=… focus=… evidence=<that round>` — is the RESULT of this transcript's own `aid-emit-dispatch.sh start` call
  # (matched by tool_use_id; one pass over the transcript, text the model wrote is never read).
  if [[ "$idx" =~ ^[0-9]+$ ]]; then
    local run_dir printed now f nonce ts exp rdir
    run_dir="$(dirname "$(dirname "$(dirname "$c")")")"; now="$(date -u +%s)"
    if compgen -G "${run_dir}/cp2/step-${idx}/round-*/pending-dispatches.jsonl" >/dev/null; then
      printed="$(grep -E 'aid-emit-dispatch\.sh|nonce=' "$t" 2>/dev/null | jq -rRn '
          [inputs | fromjson? | select(.type == "assistant" or .type == "user")] as $l
          | ([$l[] | select(.type == "assistant") | .message.content[]?
               | select(.type? == "tool_use" and .name == "Bash" and ((.input.command // "") | test("aid-emit-dispatch\\.sh\"? +start ")))
               | .id] | map({(.): true}) | add // {}) as $starts
          | $l[] | select(.type == "user") | .message.content | if type == "array" then .[] else empty end
          | select(.type? == "tool_result" and ($starts[.tool_use_id // ""] // false))
          | .content | if type == "array" then (map(.text? // "") | join("\n")) else tostring end' 2>/dev/null \
        | grep -oE 'nonce=[^ ]+ focus=[^ ]+ evidence=[^ "\\]+' | sort -u)"
      if [[ -n "$printed" ]]; then
        while IFS=$'\t' read -r f nonce ts exp rdir; do
          [[ -n "$nonce" ]] || continue
          grep -qxF "nonce=${nonce} focus=${f} evidence=$(realpath -m -- "$rdir")" <<< "$printed" || continue
          ts="$(date -u -d "$ts" +%s 2>/dev/null)" || continue
          [[ "$exp" =~ ^[0-9]+$ ]] || exp=3600
          (( now - ts <= exp )) && return 0
        done < <(
          for rd in "${run_dir}/cp2/step-${idx}"/round-*; do
            [[ -f "${rd}/timeline.jsonl" ]] || continue
            jq -c --arg rd "$rd" --arg r "${rd##*round-}" 'select(.event == "verifier_dispatch_start") + {rd: $rd, rn: ($r | tonumber? // 0)}' "${rd}/timeline.jsonl" 2>/dev/null
          done | jq -rs --arg i "$idx" --slurpfile pend <(cat "${run_dir}/cp2/step-${idx}"/round-*/pending-dispatches.jsonl 2>/dev/null) '
            [.[] | select(.focus | test("^(cp2-step-" + $i + "-|fix-cp2-" + $i + "-r)"))]
            | group_by(.focus)[] | sort_by(.ts, .rn) | last as $s
            | $pend[] | select(.event == "start" and .nonce == $s.nonce and .focus == $s.focus
                               and ((.step_n // -1) | tostring) == $i)
            | "\(.focus)\t\(.nonce)\t\(.ts)\t\(.expected_duration_max // "")\t\($s.rd)"')
      fi
    fi
  fi
  ver="$(jq -r '.version // ""' "$c" 2>/dev/null)"; rec="$(dirname "$c")/land.json"
  local candidates answered
  candidates="$( { grep -F 'aid-step-land.sh' "$t" 2>/dev/null \
      | jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]?
          | select(.type? == "tool_use" and .name == "Bash" and .input.run_in_background? == true
                   and ((.input.command // "") | contains("aid-step-land.sh")) and .id != null) | "land\t\(.id)"' 2>/dev/null
    if [[ -n "$ver" ]]; then
      grep -F "Dispatch Contract (version ${ver})" "$t" 2>/dev/null \
        | jq -rR --arg h "Dispatch Contract (version ${ver})" 'fromjson? | select(.type == "assistant") | .message.content[]?
            | select(.type? == "tool_use" and (.name == "Agent" or .name == "Task") and ((.input.prompt // "") | contains($h))
                     and .id != null) | "agent\t\(.id)"' 2>/dev/null
    fi; } )"
  answered="$(grep -o '<tool-use-id>[^<]*' "$t" | cut -d'>' -f2 | sort -u)"
  local kind id
  while IFS=$'\t' read -r kind id; do
    [[ -n "$id" ]] || continue
    grep -qxF "$id" <<< "$answered" && continue
    # an agent counts only once the harness said it went to the background (a foreground one is answered by its result)
    [[ "$kind" == agent ]] && grep -F "\"tool_use_id\":\"${id}\"" "$t" 2>/dev/null | grep -qE 'Async agent launched|working in the background' && return 0
    if [[ "$kind" == land && -n "$sess" && "$(jq -r '"\(.status // "")\t\(.session_id // "")"' "$rec" 2>/dev/null)" == "running"$'\t'"$sess" ]]; then
      pid="$(jq -r '.pid // ""' "$rec" 2>/dev/null)"
      [[ "$pid" =~ ^[0-9]+$ ]] && tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null | grep -q 'aid-step-land\.sh' && return 0
    fi
  done <<< "$candidates"
  return 1
}

# _aid_hrt_last_message <transcript> — the text of the turn's last assistant
# message (empty when there is none). Shared by every Stop rule that reads it.
# Read from the END: a long session's transcript runs to hundreds of MB (WAN 25. 10. 2026: 186 MB, and
# slurping it took 4.5 s on every Stop). jq stops at the first assistant line it meets; tac's broken pipe
# is not a failure, a line jq cannot parse before that point still is.
_aid_hrt_last_message() {
  [[ -r "$1" ]] || return 1
  { tac "$1" 2>/dev/null || true; } \
    | jq -rn 'first(inputs | select(.type == "assistant"))
              | (.message.content // []) | map(select(.type == "text") | .text) | join("\n")' 2>/dev/null
}

# _aid_hrt_hands_over <text_file> — does the turn's last message open a
# Decision card (validated by the card library), the ecosystem's decision
# block, or a Blocked card (its label in any configured language)? 0 yes, 1 no.
_aid_hrt_hands_over() {
  local f="$1"
  aid_decision_card_validate "$f" >/dev/null 2>&1 && return 0
  # The ecosystem's own decision block (/opt/eco/CLAUDE.md, part 5): a numbered
  # decision or finding, at least two options and a recommendation.
  grep -Eq '^[[:space:]*#]*(Rozhodnutí|Nález) [0-9]+:' "$f" 2>/dev/null \
    && (( $(grep -Ec '^[[:space:]*]*[A-Z]\)' "$f") >= 2 )) \
    && grep -Eq '^[[:space:]*]*Doporučuju' "$f" && return 0
  local lang label
  while IFS= read -r lang; do
    [[ -n "$lang" ]] || continue
    label="$(_aid_dc_label "$lang" blocked)"
    [[ -n "$label" ]] && grep -q "^${label}:" "$f" 2>/dev/null && return 0
  done < <(yq -r '.languages | keys | .[]' "$(_aid_dc_labels_file)" 2>/dev/null)
  return 1
}

# ---------------------------------------------------------------------------
# aid_hook_rule_turn_step_open — Stop handler. 0 nothing open · 2 refuse ·
# 3 not applicable (no workspace, no transcript, or the turn hands over).
# ---------------------------------------------------------------------------
aid_hook_rule_turn_step_open() {
  local input; input="$(cat)"
  local cwd transcript sess
  IFS=$'\x1f' read -r cwd transcript sess < <(jq -r '[.cwd // "", .transcript_path // "", .session_id // ""] | join("\u001f")' <<< "$input" 2>/dev/null)
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  local root
  root="$(cd "$cwd" && aid_state_root 2>/dev/null)" || { echo "cwd is not inside an AID workspace" >&2; return 3; }
  [[ -n "$transcript" && -r "$transcript" ]] \
    || { echo "no readable transcript — no step can be attributed to this turn" >&2; return 3; }

  local line
  line="$(aid_turn_open_steps "$root" "$transcript" | head -1)"
  [[ -n "$line" ]] || { echo "no step of this session is open" >&2; return 0; }
  local epic run idx sid
  IFS=$'\t' read -r epic run idx sid _ <<< "$line"

  local last tmp
  last="$(_aid_hrt_last_message "$transcript")"
  if [[ -n "$last" && "$last" != "null" ]]; then
    tmp="$(mktemp)" || { echo "no temp file for the card check" >&2; return 3; }
    printf '%s\n' "$last" > "$tmp"
    local hands=1; _aid_hrt_hands_over "$tmp" || hands=0
    rm -f "$tmp"
    if (( hands )); then
      echo "step ${idx} (${sid}) of ${epic} is open, but the turn hands over explicitly with a card" >&2
      return 3
    fi
    # AID 3.11.0: the step is being taken over in the background (its record says running, its process lives) or
    # the agent dispatched with its packet still works — a declared wait on THAT, unanswered, ends the turn; the
    # notification starts the next one. Any other background call does not excuse an open step.
    if [[ "$(printf '%s' "$last" | grep -v '^[[:space:]]*$' | tail -1)" == AID-WAIT:* ]]; then
      if _aid_hrt_step_call_pending "$transcript" "$(cut -f5 <<< "$line")" "$sess" "$idx"; then
        echo "step ${idx} (${sid}) of ${epic} is open; the turn waits on a background call (AID-WAIT)" >&2
        return 3
      fi
    fi
  fi

  echo "step ${idx} (${sid}) of ${epic}/${run} was dispatched under a contract and the run has not advanced past it. Finish it before the turn ends: take it over in the background (scripts/aid-step-land.sh, run_in_background, then end with \`AID-WAIT: převzetí kroku ${idx}\`) or by hand (validate the aid-return, commit), write step-${idx}-verify.md and run aid-fsm.sh increment-step — or hand over explicitly with a Decision card or a Blocked card, rendered by aid_decision_card_render (scripts/lib/aid-decision-card.sh), never written by hand." >&2
  return 2
}

# _aid_hrt_relative <path> <cwd> — a repo-relative path for the tree the
# write lands in. Absolute paths are made relative to that tree's top level;
# relative ones are taken as they are.
_aid_hrt_relative() {
  local path="$1" cwd="$2" top
  [[ "$path" == /* ]] || { printf '%s' "$path"; return 0; }
  # a new folder does not exist yet: its nearest existing parent names the tree
  local d; d="$(dirname "$path")"; while [[ ! -d "$d" && "$d" != / ]]; do d="$(dirname "$d")"; done
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" \
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
  local tool path cwd transcript
  # Joined with US (0x1f), never a tab — see aid_turn_open_steps: an absent
  # field between two present ones would otherwise collapse.
  IFS=$'\x1f' read -r tool cwd transcript path < <(jq -r '[.tool_name // "", .cwd // "", .transcript_path // "",
    (.tool_input.file_path // .tool_input.notebook_path // "")] | join("\u001f")' <<< "$input" 2>/dev/null)
  case "$tool" in Write|Edit|MultiEdit|NotebookEdit) ;; *) echo "not a file write (${tool:-no tool})" >&2; return 3 ;; esac
  [[ -n "$path" ]] || { echo "the write names no path" >&2; return 3; }
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  local root
  root="$(cd "$cwd" && aid_state_root 2>/dev/null)" || { echo "cwd is not inside an AID workspace" >&2; return 3; }
  # A reviewer writes its answer into the review round's own directory while
  # the step is still open; that is the round's path, not the step's.
  case "$path" in
    *.aid-o/work/evidence/*/cp[267]/*) echo "a review round's own directory" >&2; return 3 ;;
  esac

  # The same attribution as the Stop rule, when the payload names a readable
  # transcript; without one, any open step's contract is the best available
  # answer and the notice says which step it is.
  [[ -r "$transcript" ]] || transcript=""
  # The hook cannot tell WHICH agent of a wave is writing, so a path inside
  # ANY open step's paths is inside scope; the notice lists every open step
  # with its paths, and the return validation of the right step settles it.
  local lines
  lines="$(aid_turn_open_steps "$root" "$transcript")" || { echo "no step is open — nothing declares paths" >&2; return 3; }
  local rel sid contract allowed summary=""
  rel="$(_aid_hrt_relative "$path" "$cwd")"
  while IFS=$'\t' read -r _ _ _ sid contract; do
    [[ -n "$sid" ]] || continue
    allowed="$(aid_dispatch_contract_allowed "$contract")"   # packet + any amend-scope record
    _aid_dc_path_allowed "$rel" "$allowed" "steps/${sid}" && return 0
    summary="${summary:+$summary; }${sid}: $(jq -r 'join(", ")' <<< "$allowed")"
  done <<< "$lines"
  printf 'AID: this write lands OUTSIDE the open step'"'"'s allowed paths — %s. Open steps may change: %s. An edit outside them will be named in the contract validation and the step refused; stop and re-check the packet before continuing.\n' \
    "$rel" "$summary"
  echo "write outside allowed paths: ${rel}" >&2
  return 0
}
