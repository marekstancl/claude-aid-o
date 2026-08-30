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

    printf '%s\t%s\t%s\t%s\n' "$plan_id" "${state:-?}" "$result" "$next"
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

# _aid_qc_line <plan> <state> <result> <next> — one sentence, for either event.
_aid_qc_line() {
  local plan="$1" state="$2" result="$3" next="$4" tail=""
  [[ -n "$next" ]] && tail=" The last continuation left ${next} in flight."
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

  # WHOSE PLANS THIS SESSION IS TOLD ABOUT. Deduplicating was not enough: the
  # rule still named every open plan in the workspace, so an unrelated plan
  # moving produced a fresh end-of-turn reminder for work this session never
  # touched (Codex, 2026-08-30, finding 5 — and the PM's original complaint,
  # "info z jinýho plánu pořád"). A session hears about a plan it has actually
  # been in: one named in its own transcript. With no transcript to read, the
  # filter does not apply — a rule that cannot tell whose work it is says its
  # piece rather than staying silent about everything.
  # WHAT THIS DELIBERATELY DOES NOT COVER, and why it is the right trade.
  # A plan that becomes open DURING this session, and that this session never
  # mentions, is named at neither hook: SessionStart already happened, and Stop
  # filters it out (Codex, 2026-08-30, third round). That is accepted, for two
  # reasons. Whoever opened it has it in THEIR transcript, so it is reported —
  # just not here; and the next SessionStart in this workspace names it anyway,
  # so the loss is bounded by one session rather than permanent. The PM asked
  # for the opposite failure to stop: "info z jinýho plánu pořád" — an unrelated
  # plan named at every turn until the reminder itself stopped being read.
  # Between a reminder that arrives one session late and a reminder nobody
  # reads, this picks the first.
  #
  # …and it applies to the END of a turn only. SessionStart is the one moment
  # where hearing about the whole workspace is the point, so the overview is
  # not filtered there: a plan nobody has mentioned yet would otherwise never
  # be named at all (Codex, 2026-08-30, finding 5). Stop says only yours;
  # SessionStart says everything, once.
  local _qc_mine="" _qc_filter=0
  if [[ "${_qc_scope:-stop}" == "stop" && -n "$_qc_transcript" && -r "$_qc_transcript" ]]; then
    _qc_mine=" $(grep -oE '\bP[0-9]{3}\b' "$_qc_transcript" 2>/dev/null | sort -u | tr '\n' ' ')"
    [[ -n "${_qc_mine// /}" ]] && _qc_filter=1
  fi

  local plan state result next n=0
  while IFS=$'\t' read -r plan state result next; do
    [[ -n "$plan" ]] || continue
    if (( _qc_filter )) && [[ "$_qc_mine" != *" $plan "* ]]; then
      continue
    fi
    if (( _qc_once_ok )) && ! aid_session_once "queue-continuation" "$_qc_skey" "${plan}:${state}:${result}"; then
      continue
    fi
    (( n == 0 )) && echo "$heading"
    n=$((n+1))
    _aid_qc_line "$plan" "$state" "$result" "$next"
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
