#!/usr/bin/env bash
# =============================================================================
# lib/aid-queue-continuation.sh — an autonomous plan keeps going until it
# needs the PM (P090 Step 5; the Stop rule became a bounded refusal in P099)
#
#   aid_queue_continuation_scan <state_root>       one line per autonomous plan
#   aid_hook_rule_queue_continuation_stop          (Stop-event handler)
#   aid_hook_rule_queue_continuation_start         (SessionStart-event handler)
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
# IT ASKS, IT NEVER TAKES. Queue reads go through `queue_peek_next`, never
# `claim-next`: a reminder that consumed the queue would leave an EPIC marked
# `running` with nothing running.
#
# WHERE "IS THIS PLAN AUTONOMOUS" COMES FROM. The plan-level `autonomy` field in
# `.aid-o/work/plan-state/<plan_id>/plan-state.yaml`, read from the FILE and
# never from the environment. Absence reads as manual.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-27
# =============================================================================
[[ -n "${_AID_QUEUE_CONTINUATION_SH_LOADED:-}" ]] && return 0
_AID_QUEUE_CONTINUATION_SH_LOADED=1

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

# Plans that owe nothing: a closed or abandoned plan has no next EPIC by
# definition, and reminding anyone about it is pure noise.
_AID_QC_TERMINAL='CLOSED ABORTED ROLLED_BACK'

# ---------------------------------------------------------------------------
# aid_queue_continuation_scan <state_root>
#   For every plan whose state says `autonomy: auto` and which is not terminal,
#   one line:
#     <plan_id>\t<plan_state>\t<peek result>\t<guidance next_epic or "">
#   `peek result` is `queue_peek_next`'s own triple — `<epic_id>`,
#   `blocked:<id>:<reason>` or `none`.
#
#   A plan whose queue could NOT be read produces NO LINE AT ALL, and a note on
#   stderr saying so. That is the Step 5 contract, and the right one: this rule
#   speaks into a prompt, and a reminder built on "I do not know" is noise that
#   teaches a reader to skim past the ones that mean something. Silence here is
#   not a claim that the plan is finished — nothing is claimed — and the
#   stderr note is what an operator or the audit log reads afterwards.
#   Exit 0 always.
# ---------------------------------------------------------------------------
aid_queue_continuation_scan() {
  local root="${1:?continuation: state root required}"
  local sf plan_id state autonomy result guide next
  local qlib="${_AID_QC_LIB_DIR}/aid-queue-write.sh"
  [[ -f "$qlib" ]] || return 0

  for sf in "$root"/.aid-o/work/plan-state/*/plan-state.yaml; do
    [[ -f "$sf" ]] || continue
    plan_id="$(basename "$(dirname "$sf")")"
    IFS=$'\x1f' read -r autonomy state _ <<< "$(_aid_qc_state "$root" "$plan_id")"
    [[ "$autonomy" == "auto" ]] || continue
    [[ " $_AID_QC_TERMINAL " == *" ${state} "* ]] && continue

    local rc=0
    result="$(bash "$qlib" peek-next "$plan_id" --project-root "$root" 2>/dev/null)" || rc=$?
    # rc 3 is the lock; rc 2 a bad id. Either way the answer is "I don't know",
    # and 0/1 are the only codes that carry one. Say nothing, and record why.
    if [[ "$rc" -ne 0 && "$rc" -ne 1 ]] || [[ -z "$result" ]]; then
      echo "queue for ${plan_id} could not be read (peek-next rc=${rc}); saying nothing about it" >&2
      continue
    fi

    # The guidance is accepted only if it is OUR schema AND about THIS plan: a
    # file copied from another plan carries that plan's in-flight EPIC, and the
    # reminder would name it as this one's (Codex review, EPIC 2).
    next=""
    guide="${root}/.aid-o/work/evidence/${plan_id}/continue-state.json"
    if [[ -f "$guide" ]]; then
      next="$(jq -r --arg plan "$plan_id" '
                select(.schema == "aid-plan-continue/1")
                | select(.plan_id == $plan)
                | select((.next_epic | type) == "string")
                | .next_epic' "$guide" 2>/dev/null)" || next=""
    fi

    # `peek-next` answering `none` means "nothing CLAIMABLE", which is not the
    # same statement as "every EPIC finished". For a plan that has never had an
    # EPIC in its queue the two readings point in opposite directions, and the
    # hook used to advise closing a plan two minutes after plan-start. Ask how
    # many entries this plan owns, in any status, and let the renderer say
    # which of the two it is. An unreadable answer stays "I do not know": the
    # count is left empty and the existing wording is used, matching this
    # function's own policy of never turning an unknown into a claim.
    local qcount="" qrc=0
    if [[ "$result" == "none" ]]; then
      qcount="$(bash "$qlib" count-plan "$plan_id" --project-root "$root" 2>/dev/null)" || qrc=$?
      if [[ "$qrc" -ne 0 || ! "$qcount" =~ ^[0-9]+$ ]]; then
        echo "queue count for ${plan_id} could not be read (count-plan rc=${qrc}); not distinguishing 'before generation' from 'drained'" >&2
        qcount=""
      fi
    fi

    # \037 and not a tab: a TAB is IFS whitespace, so a run of them collapses
    # into one delimiter and an empty field in the MIDDLE of the record simply
    # disappears — the reader then takes the next value as `next`. That was
    # harmless while `next` was last and only ever empty at the end; adding a
    # field after it made the collapse visible (the count arrived as `next`).
    printf '%s\037%s\037%s\037%s\037%s\n' "$plan_id" "${state:-?}" "$result" "$next" "$qcount"
  done
  return 0
}

# The once-per-session memory lives in the session store, shared with the
# milestone rule rather than copied — two copies of "say it once" drift.
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

# _aid_qc_line <plan> <state> <result> <next> [queue_count] — one sentence.
# An empty queue_count means "not determined".
_aid_qc_line() {
  local plan="$1" state="$2" result="$3" next="$4" qcount="${5:-}" tail=""
  [[ -n "$next" ]] && tail=" The last continuation left ${next} in flight."
  # Zero entries is the plan BEFORE generation, or one interrupted during it —
  # never a plan that finished. The wording deliberately does not claim "no
  # EPIC was ever generated": generation can produce artifacts and then fail
  # before the queue insert, so the queue can only speak for the queue.
  if [[ "$result" == "none" && "$qcount" == "0" ]]; then
    printf -- '- %s (%s): no EPIC is recorded in this plan queue yet — the plan is before, or was interrupted during, generation; do not close it.%s\n' "$plan" "$state" "$tail"
    return 0
  fi
  case "$result" in
    none)       printf -- '- %s (%s): every EPIC is accounted for; the plan still needs closing (plan-finalize / plan-merge-to-main / plan-close).%s\n' "$plan" "$state" "$tail" ;;
    blocked:*)  printf -- '- %s (%s): nothing is claimable — %s.%s\n' "$plan" "$state" "$result" "$tail" ;;
    *)          printf -- '- %s (%s): %s is ready to be claimed — `aid-plan-continue.sh` takes it after the current EPIC merges.%s\n' "$plan" "$state" "$result" "$tail" ;;
  esac
}

# ---------------------------------------------------------------------------
# aid_hook_rule_queue_continuation_start — SessionStart handler, and the event
# that actually rescues a lost chain: when a controller dies, the
# `epic-merge-to-plan` that would have continued the plan never happens again,
# so the guidance it wrote would be read by nobody. This is who reads it.
#
# SAID ONCE PER WORKSPACE, PER PLAN, PER STATE. Five terminals open on one
# project announced the same open plan five times (PM, "hlásí to pořád v jiných
# oknech"); the memory is therefore keyed on the WORKSPACE, canonicalised so a
# symlinked spelling of the same checkout does not get its own memory, and it
# speaks again the moment the plan's state moves. An unusable root falls back
# to the session key, which merely repeats — the noisy failure, never the
# silent one. Returns 0 with something to say, 3 with nothing; never refuses.
# ---------------------------------------------------------------------------
aid_hook_rule_queue_continuation_start() {
  local input; input="$(cat)"
  local root; root="$(_aid_qc_root "$input")" || return 3
  local skey ws=""
  skey="$(printf '%s' "$input" | jq -r '[.transcript_path?, .session_id?] | map(select(type == "string" and . != "")) | first // ""' 2>/dev/null)"
  ws="$(cd -- "$root" 2>/dev/null && pwd -P)" || ws=""
  [[ -n "$ws" ]] && skey="workspace:${ws}"

  local plan state result next qcount n=0
  while IFS=$'\037' read -r plan state result next qcount; do
    [[ -n "$plan" ]] || continue
    aid_session_once "queue-continuation" "$skey" "${plan}:${state}:${result}" || continue
    (( n == 0 )) && echo "AID — an autonomous plan from an earlier session is still open (nothing was changed):"
    n=$((n+1))
    _aid_qc_line "$plan" "$state" "$result" "$next" "$qcount"
  done < <(aid_queue_continuation_scan "$root")

  if (( n == 0 )); then
    echo "no open autonomous plan in this workspace" >&2
    return 3
  fi
  echo "  Continue it with /aid-run --auto (it binds this session to the plan)."
  echo "${n} open autonomous plan(s) named" >&2
  return 0
}

# _aid_qc_counter <plan_id> — the continuation counter file of this workspace's
# plan, in the session store (never in the tree).
_aid_qc_counter() {
  local dir; dir="$(aid_session_store_dir continuation)" || return 1
  printf '%s/%s_%s\n' "$dir" "$(_aid_alert_workspace | sha256sum | cut -c1-16)" "$1"
}

# _aid_qc_jobs_busy <root> — true when a background job AID owns (a gate run
# under evidence/<epic>/<run>/jobs) is still live.
_aid_qc_jobs_busy() {
  local d
  while IFS= read -r d; do
    bash "${_AID_QC_LIB_DIR}/../aid-job.sh" watchdog --jobs-dir "$d" 2>/dev/null \
      | jq -e '.state == "busy"' >/dev/null 2>&1 && return 0
  done < <(find "$1/.aid-o/work/evidence" -mindepth 3 -maxdepth 3 -type d -name jobs 2>/dev/null)
  return 1
}

# ---------------------------------------------------------------------------
# aid_hook_rule_queue_continuation_stop — Stop handler.
#   2 refuse the stop (work is left and budget remains)
#   3 let the turn end: not this session's plan, a hand-over card, a declared
#     wait on a live background job, the budget spent, or the rule could not
#     read what it needs (it never refuses without knowing)
# The reason line starts `outcome=<refused|handed_over|wait|budget_spent|
# not_auto> plan=<id>`, which the dispatcher writes into the audit line.
# ---------------------------------------------------------------------------
aid_hook_rule_queue_continuation_stop() {
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

  [[ -n "$transcript" && -r "$transcript" ]] \
    || { echo "outcome=not_auto plan=${plan}: no readable transcript — the rule does not refuse without knowing" >&2; return 3; }
  local last tmp
  last="$(_aid_hrt_last_message "$transcript")"
  tmp="$(mktemp)" || { echo "outcome=not_auto plan=${plan}: no temp file" >&2; return 3; }
  printf '%s\n' "$last" > "$tmp"
  if _aid_hrt_hands_over "$tmp"; then
    rm -f "$tmp"
    aid_alert_waiting "$plan" "předal ti rozhodnutí nebo blokaci" "odpověz v session" || true
    echo "outcome=handed_over plan=${plan}: the turn ends with a card" >&2
    return 3
  fi
  rm -f "$tmp"
  if [[ "$(printf '%s' "$last" | grep -v '^[[:space:]]*$' | tail -1)" == AID-WAIT:* ]] && _aid_qc_jobs_busy "$root"; then
    echo "outcome=wait plan=${plan}: a declared wait on a live background job" >&2
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
  echo "outcome=refused plan=${plan}: AID — ${plan} runs autonomously (${state}) and this turn ended with work left (continuation $((n + 1)) of ${budget}). Continue the /aid-run --auto procedure from this state. To hand over, end with a Decision or Blocked card; to wait on a background gate job, end with a line \`AID-WAIT: <what>\`." >&2
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
