#!/usr/bin/env bash
# =============================================================================
# aid-plan-continue.sh — one finished EPIC forward. (P090 Step 3.)
#
# WHY THIS IS A PROGRAM AND NOT A PARAGRAPH. The sequence below is exactly the
# one `skills/pipeline.md` (steps 16a/16b) has been prescribing to a human:
# mirror the merge into the queue, ask what is next, claim it, start it. As
# prose it was a rule that had to be REMEMBERED, and a test could prove at most
# that the prose existed. As a script it can be run, and a test can drive it end
# to end. That is the whole difference this file makes.
#
# WHAT IT DOES NOT DO. It does not run the EPIC — `epic-start` registers the
# branch and the manifest record, the work is an agent's. It does not close a
# plan: on `none` it NAMES the closing sequence and stops, because closing is a
# decision. It has no loop and no cap of its own: one invocation moves a plan by
# one EPIC and exits.
#
# THE ORDER, AND WHY EACH LINK IS WHERE IT IS:
#
#   0. PROOF   `git merge-base --is-ancestor <task branch> plan/<plan>`.
#      Before anything is written. A queue entry with no `merge_target` is
#      judged by its status alone (lib/aid-queue-write.sh:_queue_dep_state), so
#      an unearned `merged_to_plan` there would falsely unblock a dependent.
#      No proof, no mirror.
#   1. MIRROR  `set-status <finished epic> merged_to_plan`. Skipped when the
#      entry already says so, which is what makes a second run harmless.
#      A refusal because the entry is terminal means queue and manifest
#      disagree: stop and report — never reconcile by hand.
#   2. ASK     `aid-plan-fsm.sh next-epic <plan>` — the READ from Step 2, which
#      changes nothing and leaves a timeline line. `none` or `blocked:` ends the
#      run HERE, with the queue never claimed.
#   3. CLAIM   `aid-queue-write.sh claim-next <plan>`. Between the ask and the
#      claim the queue can move; if the claim takes a different entry, that is
#      not an error, it is recorded.
#   4. START   `aid-plan-fsm.sh epic-start <plan> <the entry CLAIM took>`.
#
# IDEMPOTENCE KEYS ON THE QUEUE, not on any artifact: run it twice over the same
# finished EPIC and the second run skips the mirror and simply asks again.
#
# THE ONE STATE IT WILL NOT CLEAN UP SILENTLY. If the process dies between
# claim and start, the entry is left `running` with nothing running. `peek`
# deliberately does not return such an entry, and this script will not quietly
# reset one either — a `running` entry is either a crash or somebody else's live
# run, and taking it out from under a live run is worse than waiting. It is
# reported, and released only by an explicit, human-invoked
# `--reclaim <epic_id>`, which no automation calls.
#
# THE GUIDANCE FILE (P090 Step 4). `.aid-o/work/evidence/<plan>/continue-state.json`,
# schema `aid-plan-continue/1`. Written at the end of every run, read at the start of
# the next one. It is a GUIDANCE, not an authority: after a lost turn it says where the
# last run got to, and the next run still ASKS the queue, because what is merged can
# have changed in between. It is deliberately NOT the existing `aid-auto-resume/1`
# artifact — that one is written by aid-run-gates.sh about an unfinished GATE and read
# by aid-fsm.sh, and folding a queue answer into it would change a schema somebody else
# parses.
#
# Exit codes:
#   0  the plan moved on (or ended cleanly: `none` / `blocked:` / nothing owed)
#   1  something in the chain failed and was named; the plan did NOT move
#   2  usage
#   3  transient — a lock was unavailable. RETRY LATER; never treat as an end.
#
# **Last Updated:** 2026-08-27
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_LIB="${SCRIPT_DIR}/lib/aid-queue-write.sh"
PLAN_FSM="${SCRIPT_DIR}/aid-plan-fsm.sh"

# The queue library is SOURCED for its readers only — `_queue_resolve_dep_branch`
# is the one place that knows how an EPIC's task branch is found (conventional
# name first, then the branch its evidence recorded), and a second copy of that
# knowledge here is exactly how a proof starts disagreeing with the check it is
# meant to mirror. Every WRITE still goes through the CLI, one subprocess per
# transition, so this file never holds the queue lock.
# shellcheck disable=SC1090
source "$QUEUE_LIB"

_pc_say()  { printf '%s\n' "$*"; }
_pc_fail() { printf 'ERROR: aid-plan-continue: %s\n' "$*" >&2; }

_pc_usage() {
  cat <<'EOF'
Usage: aid-plan-continue.sh <plan_id> <finished_epic_id> [--project-root <path>]
       aid-plan-continue.sh --reclaim <epic_id> [--project-root <path>]

Moves a plan forward by one EPIC after a merge: proof -> mirror -> ask -> claim
-> start. Prints what it did at every step.

  --reclaim <epic_id>   Release an entry stuck at `running` with no live run
                        back to `pending`. HUMAN-INVOKED ONLY: automation must
                        never call it, because a `running` entry may be a live
                        run belonging to somebody else.
EOF
}

# _pc_queue <args...> — the queue CLI against the resolved root.
_pc_queue() { bash "$QUEUE_LIB" "$@" --project-root "$ROOT"; }

# _pc_timeline <event-json-fields...> — one line into the plan's timeline.
# Best-effort by design: the AUTHORITATIVE trace of what was asked is written
# by `next-epic` itself (which fails hard if it cannot record). These are the
# surrounding notes, and losing one must not undo a merge that already landed.
_pc_note() {
  local ev_dir="${ROOT}/.aid-o/work/evidence/${PLAN_ID}"
  local ev
  ev="$(jq -nc --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg plan "$PLAN_ID" \
        --arg event "$1" --arg epic "${2:-}" --arg detail "${3:-}" \
        '{event:$event, plan_id:$plan, epic_id:$epic, detail:$detail, at:$ts}' 2>/dev/null)" || return 0
  [[ -n "$ev" ]] || return 0
  mkdir -p "$ev_dir" 2>/dev/null || return 0
  printf '%s\n' "$ev" >> "${ev_dir}/timeline.jsonl" 2>/dev/null || true
  return 0
}

# ---------------------------------------------------------------------------
# The guidance file — one reader, one writer, both in this script. (Step 4.)
#
# An artifact with no reader causes nothing to resume, so the producer and the
# consumer are deliberately the same program.
# ---------------------------------------------------------------------------
_pc_state_path() { printf '%s/.aid-o/work/evidence/%s/continue-state.json' "$ROOT" "$PLAN_ID"; }

# _pc_state_read — sets _PC_GUIDE_JSON (empty when there is nothing usable) and
# _PC_GUIDE_NOTE (the line to print when there is not). Deliberately assigns to
# globals instead of echoing: a `$(...)` call runs in a subshell, and every
# variable it sets dies with it — which is exactly how a guidance can be read
# and then silently forgotten.
#
# Never half-interprets: anything that is not a well-formed object of THIS
# schema is treated as absent and said so, rather than mined for whichever
# fields happen to have survived.
_PC_GUIDE_JSON=""
_PC_GUIDE_NOTE=""
_pc_state_read() {
  _PC_GUIDE_JSON=""; _PC_GUIDE_NOTE=""
  local f; f="$(_pc_state_path)"
  if [[ ! -f "$f" ]]; then
    _PC_GUIDE_NOTE="guide:   none — this run starts from the queue alone"
    return 0
  fi
  _PC_GUIDE_JSON="$(jq -ec 'select(.schema == "aid-plan-continue/1")' "$f" 2>/dev/null)" || _PC_GUIDE_JSON=""
  if [[ -z "$_PC_GUIDE_JSON" ]]; then
    _PC_GUIDE_NOTE="guide:   ${f} is unreadable or not aid-plan-continue/1 — ignoring it and asking the queue instead"
  fi
  return 0
}

# _pc_state_write <last_result> [next_epic] — atomically. A crash mid-write must
# not leave half a file behind, so it is tmp + mv, exactly like every other
# durable write in this plugin.
_pc_state_write() {
  local last_result="$1" next_epic="${2:-}"
  local f; f="$(_pc_state_path)"
  mkdir -p "$(dirname "$f")" 2>/dev/null || { _pc_fail "cannot create $(dirname "$f") — the guidance was not written."; return 1; }
  local tmp="${f}.tmp.$$"
  if ! jq -n --arg plan "$PLAN_ID" --arg last "$FINISHED_EPIC" --arg res "$last_result" \
        --arg next "$next_epic" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{schema:"aid-plan-continue/1", plan_id:$plan, last_completed_epic:$last,
          last_result:$res, next_epic:$next, at:$at}' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    _pc_fail "could not stage the guidance at ${tmp}."
    return 1
  fi
  mv -- "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; _pc_fail "could not install the guidance at ${f}."; return 1; }
  return 0
}

# _pc_report_stranded — every entry of this plan sitting at `running`.
#
# AC12. Such an entry is either a crash between claim and start, or somebody
# else's live run; the two are indistinguishable from here, which is exactly why
# it is REPORTED and never collected. `peek` already refuses to return one, so
# without this the plan would simply go quiet about it.
_pc_report_stranded() {
  local file; file="$(queue_write_path)"
  [[ -f "$file" ]] || return 0
  local id ids
  ids="$(queue_entry_ids "$file")"
  while IFS= read -r id; do
    [[ -n "$id" ]] && _queue_valid_id "$id" || continue
    [[ "$(queue_get_field "$id" plan_id "$file")" == "$PLAN_ID" ]] || continue
    [[ "$(queue_get_status "$id" "$file")" == "running" ]] || continue
    _pc_say "stuck:   ${id} is 'running'. If no run is behind it, it is a crash between claim and start;"
    _pc_say "         nothing here will collect it, because it may be a live run. Release it yourself with:"
    _pc_say "           aid-plan-continue.sh --reclaim ${id}"
  done <<< "$ids"
  return 0
}

# _pc_is_merged <epic_id> — the same ancestry question as link 0, but silent and
# as a predicate. Used to judge the guidance, never as the proof itself.
_pc_is_merged() {
  local branch; branch="$(_queue_resolve_dep_branch "$1" "$ROOT")"
  [[ -n "$branch" ]] || return 1
  git -C "$ROOT" merge-base --is-ancestor "$branch" "plan/${PLAN_ID}" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# _pc_prove_merged <plan_id> <epic_id> — link 0.
# Returns 0 when the EPIC's work is provably an ancestor of plan/<plan_id>.
# ---------------------------------------------------------------------------
_pc_prove_merged() {
  local plan_id="$1" epic_id="$2"
  local plan_branch="plan/${plan_id}"
  if ! git -C "$ROOT" show-ref --verify --quiet "refs/heads/${plan_branch}"; then
    _pc_fail "there is no ${plan_branch} in ${ROOT} — nothing can be proven merged into it."
    return 1
  fi
  local branch; branch="$(_queue_resolve_dep_branch "$epic_id" "$ROOT")"
  if [[ -z "$branch" ]]; then
    _pc_fail "cannot find the task branch for ${epic_id} (neither task/${epic_id}/main nor a branch recorded in its evidence) — refusing to mirror a merge it cannot prove."
    return 1
  fi
  if ! git -C "$ROOT" merge-base --is-ancestor "$branch" "$plan_branch" >/dev/null 2>&1; then
    _pc_fail "${branch} is not an ancestor of ${plan_branch} — ${epic_id} is not merged, so nothing is mirrored. Run 'aid-plan-fsm.sh epic-merge-to-plan ${plan_id} ${epic_id}' first."
    return 1
  fi
  _pc_say "proof:   ${branch} is an ancestor of ${plan_branch}"
  return 0
}

# ---------------------------------------------------------------------------
# _pc_reclaim <epic_id> — the deliberately manual door.
# ---------------------------------------------------------------------------
_pc_reclaim() {
  local epic_id="$1"
  local cur; cur="$(_pc_queue get "$epic_id" status)" || cur=""
  if [[ "$cur" != "running" ]]; then
    _pc_fail "--reclaim only releases an entry stuck at 'running'; ${epic_id} is '${cur:-<absent>}'. Nothing written."
    return 1
  fi
  local rc=0
  _pc_queue set-status "$epic_id" pending >/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _pc_fail "could not return ${epic_id} to pending (rc=${rc})."
    return "$rc"
  fi
  _pc_say "reclaim: ${epic_id} running -> pending; it can be claimed again."
  return 0
}

main() {
  local plan_id="" epic_id="" root_opt="" reclaim_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) root_opt="${2:-}"; shift 2 ;;
      --reclaim)      reclaim_id="${2:-}"; shift 2 ;;
      -h|--help)      _pc_usage; return 0 ;;
      -*)             _pc_usage >&2; _pc_fail "unknown option: $1"; return 2 ;;
      *)
        if   [[ -z "$plan_id" ]]; then plan_id="$1"
        elif [[ -z "$epic_id" ]]; then epic_id="$1"
        else _pc_fail "unexpected argument: $1"; return 2; fi
        shift ;;
    esac
  done

  ROOT="$(cd "${root_opt:-$PWD}" 2>/dev/null && pwd)" || ROOT="${root_opt:-$PWD}"
  export AID_QUEUE_WRITE_PROJECT_ROOT="$ROOT"

  if [[ -n "$reclaim_id" ]]; then
    if [[ -n "$plan_id" || -n "$epic_id" ]]; then
      _pc_fail "--reclaim takes no positional arguments."
      return 2
    fi
    if ! _queue_valid_id "$reclaim_id"; then
      _pc_fail "--reclaim: '${reclaim_id}' is not an epic id."
      return 2
    fi
    PLAN_ID=""
    _pc_reclaim "$reclaim_id"
    return $?
  fi

  if [[ -z "$plan_id" || -z "$epic_id" ]]; then
    _pc_usage >&2
    return 2
  fi
  if [[ ! "$plan_id" =~ ^P[0-9]{3}$ ]]; then
    _pc_fail "'${plan_id}' is not a plan id (expected P<NNN>)."
    return 2
  fi
  if ! _queue_valid_id "$epic_id"; then
    _pc_fail "'${epic_id}' is not an epic id."
    return 2
  fi
  PLAN_ID="$plan_id"
  FINISHED_EPIC="$epic_id"

  # ── the guidance, first: what the last run got to (Step 4) ──────────────
  # Read BEFORE anything is written, and used only to refuse an out-of-sequence
  # mirror. Everything else this run decides, it decides by asking the queue —
  # what is merged can have changed while the last turn was gone.
  local guide_next=""
  _pc_state_read
  if [[ -n "$_PC_GUIDE_JSON" ]]; then
    guide_next="$(jq -r '.next_epic // ""' <<<"$_PC_GUIDE_JSON" 2>/dev/null)" || guide_next=""
    local guide_last guide_at
    guide_last="$(jq -r '.last_completed_epic // ""' <<<"$_PC_GUIDE_JSON" 2>/dev/null)"
    guide_at="$(jq -r '.at // ""' <<<"$_PC_GUIDE_JSON" 2>/dev/null)"
    _pc_say "guide:   last run finished ${guide_last:-<none>} and left ${guide_next:-<nothing>} in flight (${guide_at:-<no time>})"
  else
    _pc_say "$_PC_GUIDE_NOTE"
  fi
  if [[ -n "$guide_next" && "$guide_next" != "$epic_id" ]] \
     && ! _pc_is_merged "$guide_next"; then
    _pc_fail "the guidance says ${guide_next} was started and it is not in plan/${plan_id} yet, but this run was told ${epic_id} finished. Those two cannot both be true in a plan that runs one EPIC at a time. Nothing was mirrored — check which EPIC actually finished."
    return 1
  fi

  # ── 0. proof ────────────────────────────────────────────────────────────
  _pc_prove_merged "$plan_id" "$epic_id" || return 1

  # ── 1. mirror ───────────────────────────────────────────────────────────
  local cur; cur="$(_pc_queue get "$epic_id" status)" || cur=""
  cur="$(queue_status_normalize "$cur")"
  if [[ "$cur" == "merged_to_plan" ]]; then
    _pc_say "mirror:  ${epic_id} already merged_to_plan — skipped"
  else
    local mrc=0
    _pc_queue set-status "$epic_id" merged_to_plan >/dev/null || mrc=$?
    case "$mrc" in
      0) _pc_say "mirror:  ${epic_id} ${cur:-<absent>} -> merged_to_plan" ;;
      3) _pc_fail "the queue lock was unavailable while mirroring ${epic_id} — nothing written. Retry."; return 3 ;;
      1) _pc_fail "the queue refuses to move ${epic_id} to merged_to_plan: it is at a terminal status while the plan branch says it merged. Queue and manifest disagree — a human decides which is wrong. Nothing was written and nothing else was attempted."
         return 1 ;;
      *) _pc_fail "could not mirror ${epic_id} into the queue (rc=${mrc})."; return 1 ;;
    esac
  fi

  # ── 2. ask ──────────────────────────────────────────────────────────────
  local peeked prc=0
  peeked="$(bash "$PLAN_FSM" next-epic "$plan_id" --project-root "$ROOT")" || prc=$?
  case "$prc" in
    0) _pc_say "ask:     next is ${peeked}" ;;
    1)
      _pc_state_write "$peeked" "" || true
      _pc_report_stranded
      if [[ "$peeked" == none ]]; then
        _pc_say "ask:     none — every EPIC of ${plan_id} is accounted for."
        _pc_say ""
        _pc_say "The plan is exhausted, but this script does not close plans. Closing is a"
        _pc_say "decision, and in this repository it is three commands:"
        _pc_say "  aid-plan-fsm.sh plan-finalize ${plan_id} --stage <sync|freeze|gates|inputs|review|c4|summary>"
        _pc_say "  aid-plan-fsm.sh plan-merge-to-main ${plan_id} --decision <path>"
        _pc_say "  aid-plan-fsm.sh plan-close ${plan_id}"
      else
        _pc_say "ask:     ${peeked}"
        _pc_say "Nothing is claimable yet and that is not an error — the reason above says"
        _pc_say "what is being waited on. The queue was not claimed."
      fi
      return 0
      ;;
    *) _pc_fail "could not ask what is next for ${plan_id} (next-epic exited ${prc}) — the queue was NOT claimed. Retry."; return 3 ;;
  esac

  # ── 3. claim ────────────────────────────────────────────────────────────
  local claimed crc=0
  claimed="$(_pc_queue claim-next "$plan_id")" || crc=$?
  case "$crc" in
    0) ;;
    1)
      # The queue moved between the ask and the claim. Not an error; the ask
      # was a question, not a reservation.
      _pc_say "claim:   ${claimed} — the queue changed between the question and the claim; nothing was started."
      _pc_note "queue_claim_raced" "" "peeked=${peeked} claimed=${claimed}"
      _pc_state_write "$claimed" "" || true
      return 0
      ;;
    *) _pc_fail "could not claim the next EPIC of ${plan_id} (rc=${crc}) — nothing was started. Retry."; return 3 ;;
  esac
  if [[ "$claimed" != "$peeked" ]]; then
    _pc_say "claim:   ${claimed} (the question had said ${peeked}; the claim wins)"
    _pc_note "queue_claim_raced" "$claimed" "peeked=${peeked} claimed=${claimed}"
  else
    _pc_say "claim:   ${claimed}"
  fi

  # ── 4. start ────────────────────────────────────────────────────────────
  local srrc=0
  bash "$PLAN_FSM" epic-start "$plan_id" "$claimed" --project-root "$ROOT" || srrc=$?
  if [[ "$srrc" -ne 0 ]]; then
    # The claim succeeded, so the entry is `running` with nothing running.
    # Reconcile it back to `pending` HERE — this is the one case where the
    # script may, because it is the process that made the claim moments ago and
    # therefore knows there is no live run behind it.
    local rrc=0
    _pc_queue set-status "$claimed" pending >/dev/null || rrc=$?
    if [[ "$rrc" -eq 0 ]]; then
      _pc_fail "epic-start failed for ${claimed} (rc=${srrc}); the claim was undone (back to pending) so the next attempt can take it."
      _pc_note "continue_start_failed" "$claimed" "epic-start rc=${srrc}; claim reverted to pending"
    else
      _pc_fail "epic-start failed for ${claimed} (rc=${srrc}) AND the claim could not be undone (rc=${rrc}) — the entry is left 'running' with nothing running. Release it with: aid-plan-continue.sh --reclaim ${claimed}"
      _pc_note "continue_start_failed" "$claimed" "epic-start rc=${srrc}; claim NOT reverted (rc=${rrc})"
    fi
    return 1
  fi

  _pc_say "start:   ${claimed} is registered and ready to run."
  _pc_note "continue_advanced" "$claimed" "after=${epic_id}"
  # Last, and only now: the run got all the way through, so the guidance can
  # name what is in flight. Written after the start, never before — a guidance
  # naming an EPIC that was never started is worse than none.
  _pc_state_write "$claimed" "$claimed" || true
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
