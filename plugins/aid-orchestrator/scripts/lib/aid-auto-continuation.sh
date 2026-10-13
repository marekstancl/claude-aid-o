#!/usr/bin/env bash
# =============================================================================
# lib/aid-auto-continuation.sh — an autonomous plan keeps going until it
# needs the PM (P090 Step 5; the Stop rule became a bounded refusal in P099;
# renamed by P114 from the queue continuation library, when the queue and its
# SessionStart reminder left with the EPIC path)
#
#   aid_hook_rule_auto_continuation_stop           (Stop-event handler)
#   aid_hook_rule_pm_reply_marker                  (UserPromptSubmit handler)
#
# THE STOP RULE REFUSES, WITH A BUDGET. The agent ended its turn in the middle
# of an autonomous run about ten times in P097 and waited for "pokračuj". When
# the session that drives an autonomous plan (`auto_session` in its plan-state,
# bound by `/aid-run --auto`) ends a turn with no hand-over card and no
# declared background wait, the rule refuses the stop and names the next
# action. Its registry row says `blocks_when_active: true`, so the refusal
# holds under `stop_hook_active` too — which is why the rule counts: after
# `autonomy.continuation_budget` refusals it lets the turn end and sends the
# PM one "agent is waiting" message. The PM's next prompt resets the count
# (`aid_hook_rule_pm_reply_marker`). Every other session is never refused.
#
# WHERE "IS THIS PLAN AUTONOMOUS" COMES FROM. The plan-level `autonomy` field in
# `.aid-o/work/plan-state/<plan_id>/plan-state.yaml`, read from the FILE and
# never from the environment. Absence reads as manual.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-27
# =============================================================================
[[ -n "${_AID_AUTO_CONTINUATION_SH_LOADED:-}" ]] && return 0
_AID_AUTO_CONTINUATION_SH_LOADED=1

_AID_QC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_QC_LIB_DIR}/aid-roots.sh"

# _aid_qc_state <state_root> <plan_id> — `<autonomy>\037<plan_state>\037<auto_session>`
# in ONE pass.
#
# Read with awk rather than by sourcing the plan-state library: this runs inside
# a hook, where the whole dispatch budget is fifteen seconds shared by every
# Stop rule, and the library would pull in the lock stack for two scalars. One
# awk and not two for the same reason — the two fields live on adjacent lines of
# the same small file, and two processes to read them is one too many on the
# hottest path in this plan.
_aid_qc_state() {
  local sf="$1/.aid-o/work/plan-state/$2/plan-state.yaml"
  # US (0x1f), never a tab: a tab is IFS *whitespace*, so a plan with no
  # `autonomy` line would collapse into one field and read its plan_state as
  # its autonomy. `lib/aid-worktree-registry.sh` carries the same note.
  [[ -f "$sf" ]] || { printf '\x1f\x1f'; return 0; }
  awk '
    /^autonomy:/     && a == "" { a = $2; gsub(/^"|"$/, "", a) }
    /^plan_state:/   && s == "" { s = $2; gsub(/^"|"$/, "", s) }
    /^auto_session:/ && x == "" { x = $2; gsub(/^"|"$/, "", x) }
    END { printf "%s\037%s\037%s\n", a, s, x }' "$sf" 2>/dev/null
}

# A closed or abandoned plan has no work left to continue.
_AID_QC_TERMINAL='CLOSED ABORTED ROLLED_BACK'

# The continuation counter lives in the session store, never in the tree.
# shellcheck source=aid-session-store.sh
source "${_AID_QC_LIB_DIR}/aid-session-store.sh"
# shellcheck source=aid-alert.sh
source "${_AID_QC_LIB_DIR}/aid-alert.sh"
# shellcheck source=aid-hook-rules-turn.sh
source "${_AID_QC_LIB_DIR}/aid-hook-rules-turn.sh"

# _aid_qc_root <event json> — the state root, or nothing (and a reason on
# stderr). Shared by the handlers.
_aid_qc_root() {
  local cwd
  cwd="$(jq -r '.cwd // ""' <<<"$1" 2>/dev/null)"
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  (cd "$cwd" && aid_state_root 2>/dev/null) || { echo "cwd is not inside an AID workspace" >&2; return 3; }
}

# _aid_qc_counter <plan_id> — the continuation counter file of this workspace's
# plan, in the session store (never in the tree).
_aid_qc_counter() {
  local dir; dir="$(aid_session_store_dir continuation)" || return 1
  printf '%s/%s_%s\n' "$dir" "$(_aid_alert_workspace | sha256sum | cut -c1-16)" "$1"
}

# _aid_qc_jobs_busy <root> <plan_id> — true when a background job AID owns for
# THIS plan (a gate run under evidence/E-<nnn>-*/<run>/jobs or the plan-final
# run's jobs) is still live. Another plan's job never excuses this plan's stop.
_aid_qc_jobs_busy() {
  local d n="${2#P}"
  while IFS= read -r d; do
    bash "${_AID_QC_LIB_DIR}/../aid-job.sh" watchdog --jobs-dir "$d" 2>/dev/null \
      | jq -e '.state == "busy"' >/dev/null 2>&1 && return 0
  done < <(find "$1/.aid-o/work/evidence" -mindepth 3 -maxdepth 3 -type d -name jobs \
             \( -path "*/E-${n}-*/*" -o -path "*/${2}/*" \) 2>/dev/null)
  return 1
}

# _aid_qc_bg_pending <transcript> — true when a tool call of this session that
# ran with run_in_background (an Agent or a Bash) has no completion notification
# yet: the harness answers each with a <task-notification> naming the call's
# <tool-use-id> (IMP-647).
_aid_qc_bg_pending() {
  # Two passes over the transcript whatever its length: the ids launched in the
  # background, minus the ids a notification answered.
  # An Agent call runs in the background BY DEFAULT, with no run_in_background
  # in its input (P103, agents P008): its tool_result then says it was launched
  # in the background. That text is the harness's, so both known phrasings are
  # accepted; a foreground Agent's result is its output and is never pending.
  [[ -n "$(comm -23 \
    <( { jq -r 'select(.type == "assistant") | .message.content[]? | select(.type? == "tool_use" and .input.run_in_background? == true) | .id' "$1" 2>/dev/null
         # only results of an Agent/Task call count: another tool's output may quote the phrase
         comm -12 \
           <(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type? == "tool_use" and (.name == "Agent" or .name == "Task")) | .id' "$1" 2>/dev/null | sort -u) \
           <(jq -r 'select(.type == "user") | .message.content | arrays | .[] | select(.type? == "tool_result")
                    | select((.content | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end)
                             | test("Async agent launched|working in the background")) | .tool_use_id' "$1" 2>/dev/null | sort -u)
       } | sort -u) \
    <(grep -o '<tool-use-id>[^<]*' "$1" | cut -d'>' -f2 | sort -u))" ]]
}

# ---------------------------------------------------------------------------
# aid_hook_rule_auto_continuation_stop — Stop handler.
#   2 refuse the stop (work is left and budget remains)
#   3 let the turn end: not this session's plan, a hand-over card, a declared
#     wait on a live AID job or a background call still unreported, the budget spent, or the rule could not
#     read what it needs (it never refuses without knowing)
# The reason line starts `outcome=<refused|handed_over|wait|budget_spent|
# not_auto> plan=<id>`, which the dispatcher writes into the audit line.
# ---------------------------------------------------------------------------
aid_hook_rule_auto_continuation_stop() {
  local input; input="$(cat)"
  local root; root="$(_aid_qc_root "$input")" || return 3
  cd "$root" || return 3
  local sid transcript
  IFS=$'\x1f' read -r sid transcript < <(jq -r '[.session_id // "", .transcript_path // ""] | join("\u001f")' <<< "$input" 2>/dev/null)
  [[ -n "$sid" ]] || { echo "outcome=not_auto: the event carries no session_id" >&2; return 3; }

  local sf plan="" state autonomy bound
  for sf in "$root"/.aid-o/work/plan-state/*/plan-state.yaml; do
    [[ -f "$sf" ]] || continue
    IFS=$'\x1f' read -r autonomy state bound <<< "$(_aid_qc_state "$root" "$(basename "$(dirname "$sf")")")"
    [[ "$autonomy" == auto && "$bound" == "$sid" && " $_AID_QC_TERMINAL " != *" ${state} "* ]] || continue
    plan="$(basename "$(dirname "$sf")")"; break
  done
  [[ -n "$plan" ]] || { echo "outcome=not_auto: this session drives no open autonomous plan" >&2; return 3; }
  yq -e '.plan_id' "$root/.aid-o/work/plan-state/${plan}/plan-state.yaml" >/dev/null 2>&1 \
    || { echo "outcome=not_auto plan=${plan}: plan-state.yaml does not parse — the rule does not refuse without knowing" >&2; return 3; }

  [[ -n "$transcript" && -r "$transcript" ]] \
    || { echo "outcome=not_auto plan=${plan}: no readable transcript — the rule does not refuse without knowing" >&2; return 3; }
  local last tmp
  last="$(_aid_hrt_last_message "$transcript")" \
    || { echo "outcome=not_auto plan=${plan}: the transcript does not parse — the rule does not refuse without knowing" >&2; return 3; }
  tmp="$(mktemp)" || { echo "outcome=not_auto plan=${plan}: no temp file" >&2; return 3; }
  printf '%s\n' "$last" > "$tmp"
  if _aid_hrt_hands_over "$tmp"; then
    rm -f "$tmp"
    aid_alert_waiting "$plan" "předal ti rozhodnutí nebo blokaci" "odpověz v session" || true
    echo "outcome=handed_over plan=${plan}: the turn ends with a card" >&2
    return 3
  fi
  rm -f "$tmp"
  if [[ "$(printf '%s' "$last" | grep -v '^[[:space:]]*$' | tail -1)" == AID-WAIT:* ]] \
     && { _aid_qc_jobs_busy "$root" "$plan" || _aid_qc_bg_pending "$transcript"; }; then
    echo "outcome=wait plan=${plan}: a declared wait on a live background job or agent" >&2
    return 3
  fi

  local budget counter n=0
  budget="$(aid_orchestration_value "$root" .autonomy.continuation_budget | cut -f1)" || budget=""
  [[ "$budget" =~ ^[0-9]+$ ]] || budget=0
  counter="$(_aid_qc_counter "$plan")" || { echo "outcome=not_auto plan=${plan}: the session store is unwritable" >&2; return 3; }
  [[ -r "$counter" ]] && n="$(cat "$counter" 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if (( n >= budget )); then
    aid_alert_waiting "$plan" "vyčerpal ${budget} pokračování bez tvé odpovědi" "zkontroluj session a odpověz" || true
    echo "outcome=budget_spent plan=${plan}: ${n} of ${budget} continuations used" >&2
    return 3
  fi
  printf '%s\n' "$((n + 1))" > "$counter" || { echo "outcome=not_auto plan=${plan}: the counter cannot be written" >&2; return 3; }
  echo "outcome=refused plan=${plan}: AID — ${plan} runs autonomously (${state}) and this turn ended with work left (continuation $((n + 1)) of ${budget}). Continue the /aid-run --auto procedure from this state. To hand over, end with a Decision or Blocked card; to wait on a background gate job or agent, end with a line \`AID-WAIT: <what>\`." >&2
  return 2
}

# ---------------------------------------------------------------------------
# aid_hook_rule_pm_reply_marker — UserPromptSubmit handler. The PM answered:
# every plan this session drives gets its continuation budget back and its
# waiting message re-armed. The dispatcher's audit line of this event is what
# marks the PM's reply in time. Returns 3 (nothing to inject).
# ---------------------------------------------------------------------------
aid_hook_rule_pm_reply_marker() {
  local input; input="$(cat)"
  local root; root="$(_aid_qc_root "$input")" || return 3
  cd "$root" || return 3
  local sid sf plan autonomy state bound n=0
  sid="$(jq -r '.session_id // ""' <<< "$input" 2>/dev/null)"
  [[ -n "$sid" ]] || { echo "no session_id in the event" >&2; return 3; }
  for sf in "$root"/.aid-o/work/plan-state/*/plan-state.yaml; do
    [[ -f "$sf" ]] || continue
    plan="$(basename "$(dirname "$sf")")"
    IFS=$'\x1f' read -r autonomy state bound <<< "$(_aid_qc_state "$root" "$plan")"
    [[ "$bound" == "$sid" ]] || continue
    rm -f "$(_aid_qc_counter "$plan")"
    aid_alert_waiting_clear "$plan"
    n=$((n + 1))
  done
  echo "pm reply: ${n} plan(s) re-armed" >&2
  return 3
}
