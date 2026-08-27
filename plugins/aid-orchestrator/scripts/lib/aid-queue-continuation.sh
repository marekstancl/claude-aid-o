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

# _aid_qc_autonomy <state_root> <plan_id> — `auto`, or nothing.
# Read with awk rather than by sourcing the plan-state library: this runs inside
# a hook, where the budget is seconds and the library would pull in the lock
# stack for a single scalar.
_aid_qc_autonomy() {
  local sf="$1/.aid-o/work/plan-state/$2/plan-state.yaml"
  [[ -f "$sf" ]] || return 0
  awk '/^autonomy:/ && a == "" { a = $2; gsub(/^"|"$/, "", a) } END { print a }' "$sf" 2>/dev/null
}

# _aid_qc_plan_state <state_root> <plan_id>
_aid_qc_plan_state() {
  local sf="$1/.aid-o/work/plan-state/$2/plan-state.yaml"
  [[ -f "$sf" ]] || return 0
  awk '/^plan_state:/ && s == "" { s = $2 } END { print s }' "$sf" 2>/dev/null
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
    autonomy="$(_aid_qc_autonomy "$root" "$plan_id")"
    [[ "$autonomy" == "auto" ]] || continue
    state="$(_aid_qc_plan_state "$root" "$plan_id")"
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
# aid_hook_rule_queue_continuation_stop — Stop handler.
#
# Returns 0 ALWAYS when it has something to say, and 3 when it does not. It
# never returns 2, and its registry row is `failure: open`, which is the
# declaration that says so where a reader will find it.
# ---------------------------------------------------------------------------
aid_hook_rule_queue_continuation_stop() {
  local input; input="$(cat)"
  local root; root="$(_aid_qc_root "$input")" || return 3

  local plan state result next n=0
  while IFS=$'\t' read -r plan state result next; do
    [[ -n "$plan" ]] || continue
    (( n == 0 )) && echo "AID — this turn is ending with an autonomous plan still open (nothing was changed, and this cannot stop a turn):"
    n=$((n+1))
    _aid_qc_line "$plan" "$state" "$result" "$next"
  done < <(aid_queue_continuation_scan "$root")

  if (( n == 0 )); then
    echo "no open autonomous plan in this workspace" >&2
    return 3
  fi
  echo "${n} open autonomous plan(s) named" >&2
  return 0
}

# ---------------------------------------------------------------------------
# aid_hook_rule_queue_continuation_start — SessionStart handler.
#
# The event that actually rescues a lost chain. When a controller dies, the
# `epic-merge-to-plan` that would have continued the plan never happens again —
# so the guidance Step 4 wrote would be read by nobody. This is who reads it.
# ---------------------------------------------------------------------------
aid_hook_rule_queue_continuation_start() {
  local input; input="$(cat)"
  local root; root="$(_aid_qc_root "$input")" || return 3

  local plan state result next n=0
  while IFS=$'\t' read -r plan state result next; do
    [[ -n "$plan" ]] || continue
    (( n == 0 )) && echo "AID — an autonomous plan from an earlier session is still open (nothing was changed):"
    n=$((n+1))
    _aid_qc_line "$plan" "$state" "$result" "$next"
  done < <(aid_queue_continuation_scan "$root")

  if (( n == 0 )); then
    echo "no open autonomous plan in this workspace" >&2
    return 3
  fi
  echo "  Continue it with: aid-plan-continue.sh <plan_id> <the EPIC that finished>"
  echo "${n} open autonomous plan(s) named" >&2
  return 0
}
