#!/usr/bin/env bash
# =============================================================================
# lib/aid-queue-continuation.sh — the reminder that a plan is not finished
# (P090 Step 5)
#
#   aid_queue_continuation_scan <state_root>       one line per autonomous plan
#   aid_hook_rule_queue_continuation_stop          (Stop-event handler)
#   aid_hook_rule_queue_continuation_start         (SessionStart-event handler)
#
# DEGREE 3 ON PURPOSE, AND THIS IS THE WHOLE POINT OF THE FILE.
# `aid-hook.sh:315-319` sets `no_block=1` the moment the harness reports
# `stop_hook_active: true`: the rule still RUNS and still SPEAKS, but no
# refusal from it may stop the turn. A barrier built here would therefore hold
# exactly once and go quiet the second time — which is worse than not being a
# barrier at all, because everyone would believe it was one. So this rule never
# refuses anything. The real continuation is `aid-plan-continue.sh` (Step 3);
# actually running the next EPIC is Step 6. This is the net underneath: it says
# out loud what was left half-done.
#
# IT ASKS, IT NEVER TAKES. Every read goes through `queue_peek_next`, never
# `claim-next`: a reminder that consumed the queue would leave an EPIC marked
# `running` with nothing running — the exact failure P090 exists to remove.
#
# WHERE "IS THIS PLAN AUTONOMOUS" COMES FROM. The plan-level `autonomy` field in
# `.aid-o/work/plan-state/<plan_id>/plan-state.yaml`, written by `plan-start`,
# read from the FILE and never from the environment. The obvious alternative —
# `auto_controller` on the run record — cannot serve: a run removes its own
# entry on the `done-advance review→release` edge (aid-fsm.sh:286), so by the
# time a turn ends there may be nothing left to read. Absence reads as manual,
# so a pre-P090 plan is silent rather than noisy.
#
# TWO AUTONOMOUS PLANS ARE BOTH NAMED. It costs nothing — the rule blocks
# nothing — and staying quiet about one of them would be the only way to be
# actively wrong.
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

# _aid_qc_state <state_root> <plan_id> — `<autonomy>\t<plan_state>` in ONE pass.
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
  [[ -f "$sf" ]] || { printf '\x1f'; return 0; }
  awk '
    /^autonomy:/    && a == "" { a = $2; gsub(/^"|"$/, "", a) }
    /^plan_state:/  && s == "" { s = $2; gsub(/^"|"$/, "", s) }
    END { printf "%s\037%s\n", a, s }' "$sf" 2>/dev/null
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
    IFS=$'\x1f' read -r autonomy state <<< "$(_aid_qc_state "$root" "$plan_id")"
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

# _aid_qc_root <event json> — the state root, or nothing (and a reason on

# The once-per-session memory lives in the session store, shared with the
# milestone rule rather than copied — two copies of "say it once" drift.
# shellcheck source=aid-session-store.sh
source "${BASH_SOURCE[0]%/*}/aid-session-store.sh" 2>/dev/null || true

# stderr). Shared by both handlers.
_aid_qc_root() {
  local cwd
  cwd="$(jq -r '.cwd // ""' <<<"$1" 2>/dev/null)"
  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  (cd "$cwd" && aid_state_root 2>/dev/null) || { echo "cwd is not inside an AID workspace" >&2; return 3; }
}

# _aid_qc_line <plan> <state> <result> <next> [queue_count] — one sentence,
# for either event. An empty queue_count means "not determined".
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
# _aid_qc_emit <heading> [footer] — the body both handlers share.
#
# TWO HANDLERS AND ONE BODY, deliberately. The registry keys `handler` per
# `event`, and one handler branching on the event name would hide from a reader
# of `hook-registry.yaml` that these are two rules with two failure modes — the
# house pattern is exactly this pair shape (`continuity_capture` /
# `continuity_restore`). What the two must NOT have is two copies of the loop:
# that is how they start behaving differently while two tests each assert one of
# them.
#
# Returns 0 with something to say, 3 with nothing. Never 2 — this rule has no
# refusal to make, and its registry rows say `failure: open` so that a reader
# finds that out where it is recorded rather than by reading this file.
_aid_qc_emit() {
  local heading="$1" footer="${2:-}"
  local input; input="$(cat)"
  local root; root="$(_aid_qc_root "$input")" || return 3

  # SAY IT ONCE PER SESSION, PER PLAN, PER STATE. This rule reads every
  # plan-state record in the workspace, so in a project with four open plans it
  # named all four at EVERY turn — including plans the session was not working
  # on. Measured 2026-08-30 in a consumer project: the reminder repeated for a
  # dozen turns and the agent answered "čekám na tebe" to each one, which is
  # what a rule that repeats teaches. The key carries the plan AND its state, so
  # a plan that MOVES is named again — that is news; standing still is not.
  # `//` in jq falls back on null and false, NOT on an empty string, so an
  # event carrying `"transcript_path": ""` never reached session_id and every
  # such session shared one memory (Codex, 2026-08-30). Pick the first field
  # that is actually non-empty.
  # The session KEY and the TRANSCRIPT are two different things: a session_id
  # that happens to name a readable file must never be read as a transcript
  # (Codex, 2026-08-30). The key identifies, the transcript is evidence.
  local _qc_transcript
  _qc_transcript="$(printf '%s' "$input" | jq -r '.transcript_path? // "" | if type == "string" then . else "" end' 2>/dev/null)"
  local _qc_skey
  _qc_skey="$(printf '%s' "$input" | jq -r '[.transcript_path?, .session_id?] | map(select(type == "string" and . != "")) | first // ""' 2>/dev/null)"
  local _qc_once_ok=1
  command -v aid_session_once >/dev/null 2>&1 || _qc_once_ok=0

  # WHOSE "once" IS IT. Stop already speaks only about plans this session has
  # been in, so a per-session marker is right there. SessionStart speaks about
  # the whole workspace, and a per-session marker made it repeat in EVERY new
  # window: five terminals open on one project meant the same open plan
  # announced five times, which was the PM's complaint ("hlásí to pořád
  # v jiných oknech"). At SessionStart the memory is therefore keyed on the
  # WORKSPACE — the first window to open says it, the rest stay quiet — and it
  # speaks again the moment the plan's state actually moves, because the state
  # is part of the remembered item.
  #
  # NOT a per-day repeat. An earlier version added the date to the item so a
  # dormant plan would be re-announced daily; that is a retention policy
  # smuggled in as a key trick, and it nags about plans nobody is touching
  # while growing the marker file by a line a day (Codex, 2026-09-03). The
  # window that is genuinely working on the plan still hears about it at every
  # Stop, so nothing is forgotten by staying quiet here.
  #
  # THE KEY MUST BE A REAL WORKSPACE, or not be shared at all.
  # `workspace:${root}` is non-empty even when root is empty, which would hash
  # every workspace on the machine onto ONE marker file — the cross-workspace
  # silencing aid_session_once explicitly warns about, arrived at from the
  # other direction. An unusable root therefore leaves the per-session key in
  # place, which merely repeats: the failure this code may have is the noisy
  # one, never the silent one. The path is canonicalised first so a symlinked
  # spelling of the same checkout does not get its own memory.
  if [[ "${_qc_scope:-stop}" == "all" ]]; then
    local _qc_ws=""
    if [[ -n "$root" && -d "$root" ]]; then
      _qc_ws="$(cd -- "$root" 2>/dev/null && pwd -P)" || _qc_ws=""
    fi
    [[ -n "$_qc_ws" ]] && _qc_skey="workspace:${_qc_ws}"
  fi

  local _qc_mine="" _qc_filter=0
  if [[ "${_qc_scope:-stop}" == "stop" && -n "$_qc_transcript" && -r "$_qc_transcript" ]]; then
    _qc_mine=" $(grep -oE '\bP[0-9]{3}\b' "$_qc_transcript" 2>/dev/null | sort -u | tr '\n' ' ')"
    [[ -n "${_qc_mine// /}" ]] && _qc_filter=1
  fi

  local plan state result next qcount n=0
  while IFS=$'\037' read -r plan state result next qcount; do
    [[ -n "$plan" ]] || continue
    if (( _qc_filter )) && [[ "$_qc_mine" != *" $plan "* ]]; then
      continue
    fi
    if (( _qc_once_ok )) && ! aid_session_once "queue-continuation" "$_qc_skey" "${plan}:${state}:${result}"; then
      continue
    fi
    (( n == 0 )) && echo "$heading"
    n=$((n+1))
    _aid_qc_line "$plan" "$state" "$result" "$next" "$qcount"
  done < <(aid_queue_continuation_scan "$root")

  if (( n == 0 )); then
    echo "no open autonomous plan in this workspace" >&2
    return 3
  fi
  [[ -n "$footer" ]] && echo "$footer"
  echo "${n} open autonomous plan(s) named" >&2
  return 0
}

# aid_hook_rule_queue_continuation_stop — Stop handler. Names every autonomous
# plan that still has work when a turn ends.
aid_hook_rule_queue_continuation_stop() {
  _aid_qc_emit "AID — this turn is ending with an autonomous plan still open (nothing was changed, and this cannot stop a turn):"
}

# aid_hook_rule_queue_continuation_start — SessionStart handler, and the event
# that actually rescues a lost chain: when a controller dies, the
# `epic-merge-to-plan` that would have continued the plan never happens again,
# so the guidance Step 4 wrote would be read by nobody. This is who reads it.
aid_hook_rule_queue_continuation_start() {
  # `all`: the start of a session is exactly where the whole workspace is worth
  # hearing about — including a plan this session has not been in yet.
  local _qc_scope=all
  _aid_qc_emit \
    "AID — an autonomous plan from an earlier session is still open (nothing was changed):" \
    "  Continue it with: aid-plan-continue.sh <plan_id> <the EPIC that finished>"
}
