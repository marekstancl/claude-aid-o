#!/usr/bin/env bash
# =============================================================================
# lib/aid-artifact-obligation.sh — a finished MILESTONE owes the PM a page
# (P086 Step 4; extended from one milestone to three by P089 Step 6)
#
#   aid_artifact_obligation_check       <plan_file>          milestone 1
#   aid_artifact_obligation_epic_check  <root> <state_file>  milestone 2
#   aid_artifact_obligation_close_check <root> <state_file>  milestone 3
#   aid_hook_rule_milestone_artifact                (Stop-event registry handler)
#
# THREE MILESTONES, AND DELIBERATELY NOT MORE
#   The PM's rule is that a page belongs at the END OF A MILESTONE: after the
#   plan is written, after an EPIC's review, after the plan as a whole. A step
#   owes nothing, and a FAILED step owes nothing either ("NECHCI ARTIFACT
#   v tomto případě vůbec") — so neither activates this rule, and a test says
#   so rather than leaving it to be inferred from the absence of code.
#
# WHY THIS EXISTS
#   `commands/aid-plan.md` step 8p has told sessions to render the PM's page
#   since P084 and said so in its own text: "this is an INSTRUCTION, the
#   weakest form there is — nothing fails if a session skips it". The row
#   `plan_artifact_rendered` was filed in the enforcement registry as
#   `planned`, waiting for a mechanism. This is the mechanism.
#
# WHAT IS CHECKED IS A FILE, NEVER A TRANSCRIPT
#   The page must EXIST and be NEWER than the plan it describes. A page that
#   predates its plan is the more interesting failure of the two: the plan was
#   edited after it was summarised, so the PM is reading numbers that no longer
#   hold. That is a finding, not a quiet pass.
#
# THIS IS ALSO THE HOOK LAYER'S REUSE TEST
#   It is the third rule to arrive, and it arrives as a row in
#   defaults/hook-registry.yaml with NO change to scripts/aid-hook.sh. If a new
#   rule had needed the entry point edited, the layer would have been built for
#   its first consumer rather than for rules in general.
#
# THE SESSION WINDOW, and why the rule is not simply "every plan"
#   On a Stop event the rule may only judge what THIS session did. Anything
#   else and one un-rendered plan from last month would refuse every turn
#   forever. The window is read from the transcript's first timestamp — the
#   session's own start — and where that is unavailable the rule declines
#   rather than guessing.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-26
# =============================================================================
[[ -n "${_AID_ARTIFACT_OBLIGATION_SH_LOADED:-}" ]] && return 0
_AID_ARTIFACT_OBLIGATION_SH_LOADED=1

_AID_AO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_AO_LIB_DIR}/aid-roots.sh"
# shellcheck source=aid-plan-summary.sh
source "${_AID_AO_LIB_DIR}/aid-plan-summary.sh"
# shellcheck source=aid-epic-summary-page.sh
source "${_AID_AO_LIB_DIR}/aid-epic-summary-page.sh"

# The page commands/aid-plan.md step 8p renders, in the one place that spells
# it, so the instruction and the check cannot drift apart.
aid_artifact_obligation_page() {
  local plan_id="$1" root
  root="$(aid_state_root)" || return 1
  printf '%s/.aid-o/work/evidence/%s/plan-summary-artifact.html' "$root" "$plan_id"
}

# aid_artifact_obligation_check <plan_file>
#   0 the page is there and current
#   1 no page, or a page older than its plan (reason on stderr)
#   3 not applicable — no readable plan, or a file that is not a numbered plan
aid_artifact_obligation_check() {
  local plan="${1:?aid_artifact_obligation_check: plan file required}"
  if [[ ! -r "$plan" ]]; then
    echo "no readable plan at ${plan} — nothing owes a page" >&2
    return 3
  fi
  local base plan_id
  base="$(basename "$plan")"
  [[ "$base" =~ ^(P[0-9]+) ]] || {
    echo "${base} is not a numbered plan — no page is owed" >&2
    return 3
  }
  plan_id="${BASH_REMATCH[1]}"

  # A plan the renderer REFUSES has no page to owe. Found live 2026-08-24: this
  # rule demanded one for a plan with no `## Goal`, the renderer refused to
  # produce it, and the session was left with a finding nobody could act on. An
  # enforcement must not require the impossible, and the renderer is the
  # authority on what it can render — so it is asked, not second-guessed.
  if ! aid_plan_summary_renderable "$plan"; then
    echo "${base} cannot be rendered into a page (lib/aid-plan-summary.sh refuses it), so it owes none" >&2
    return 3
  fi

  local page; page="$(aid_artifact_obligation_page "$plan_id")" || {
    echo "cannot resolve the state root — the page location is unknown" >&2
    return 3
  }

  if [[ ! -f "$page" ]]; then
    echo "${plan_id} was written but its PM page was not rendered — expected ${page}. Render it: source \"\$AID_PLUGIN_PATH/scripts/lib/aid-plan-summary.sh\" && aid_plan_summary_render \"${plan}\" \"${page}\" (then publish it with the Artifact tool)." >&2
    return 1
  fi
  if [[ "$plan" -nt "$page" ]]; then
    echo "${plan_id}'s PM page ${page} is OLDER than the plan — the plan changed after it was summarised, so every figure on the page is a number the plan no longer holds. Re-render it." >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# MILESTONE 2 — a finished EPIC
# ---------------------------------------------------------------------------

# _aid_ao_epic_source_epoch <root> <state_file>
#   Fills _AID_AO_SRC_EPOCH with when the EPIC's work last moved, and
#   _AID_AO_SRC_WORD with the NAME of that moment; returns 1 when neither can
#   be determined.
#
#   The EPIC's own last commit is the right source: the page is rendered at the
#   release edge, so a commit landing AFTER it means the EPIC was re-worked and
#   every figure on the page is stale. The branch is read from the run's state
#   file. A merged-and-deleted branch has no commit to ask about any more, and
#   then the state file's own mtime is used and the message SAYS which of the
#   two was compared — an unstated fallback is how a weaker check gets mistaken
#   for the strong one.
#
#   TWO GLOBALS AND NOT A PACKED LINE. This used to print "<epoch>\t<word>" and
#   the caller unpacked it with `read`, which returns non-zero on input with no
#   trailing newline — so every freshness comparison took the "cannot tell"
#   branch and passed. The failure was silent and fail-open; the shape that
#   allowed it is gone.
_aid_ao_epic_source_epoch() {
  local root="$1" state="$2" branch epoch=""
  _AID_AO_SRC_EPOCH=""; _AID_AO_SRC_WORD=""
  branch="$(_esp_yaml "$state" branch)"
  if [[ -n "$branch" ]]; then
    epoch="$(git -C "$root" log -1 --format=%ct "$branch" -- 2>/dev/null)" || epoch=""
  fi
  if [[ "$epoch" =~ ^[0-9]+$ ]]; then
    _AID_AO_SRC_EPOCH="$epoch"
    _AID_AO_SRC_WORD="posledního commitu EPICu"
    return 0
  fi
  epoch="$(stat -c %Y "$state" 2>/dev/null || stat -f %m "$state" 2>/dev/null)" || epoch=""
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1
  _AID_AO_SRC_EPOCH="$epoch"
  _AID_AO_SRC_WORD="záznamu běhu (větev EPICu už neexistuje)"
  return 0
}

# aid_artifact_obligation_epic_check <root> <run_state_file>
#   0 the page is there and current
#   1 no page, or one older than the EPIC's last commit
#   3 not applicable — this run has not finished its review
aid_artifact_obligation_epic_check() {
  local root="${1:?aid_artifact_obligation_epic_check: root required}"
  local state="${2:?aid_artifact_obligation_epic_check: state file required}"
  [[ -r "$state" ]] || { echo "no readable run state at ${state}" >&2; return 3; }

  # THE MILESTONE IS THE REVIEW, NOT THE LAST STEP. `done_phase: release` is
  # the one line that says the review is over — a run still in `review`, or a
  # finished STEP, owes nothing.
  grep -qE '^done_phase:[[:space:]]*"?release"?[[:space:]]*$' "$state" 2>/dev/null || {
    echo "$(basename "$(dirname "$state")") has not finished its review — no page is owed yet" >&2
    return 3
  }

  local epic_id page
  epic_id="$(_esp_yaml "$state" epic_id)"
  # A FINISHED REVIEW WHOSE ID CANNOT BE READ IS A FINDING, NOT AN EXEMPTION.
  # Returning "not applicable" here would mean a corrupt or truncated run
  # record silently buys its way out of the obligation — the one input a
  # milestone cannot be trusted to supply about itself.
  page="$(aid_epic_summary_page_path "$root" "$epic_id")" || {
    echo "a run at ${state} says its review is finished but names no usable EPIC id ('${epic_id:-<none>}'), so its page cannot even be located — fix the run record, then render the page." >&2
    return 1
  }

  if [[ ! -f "$page" ]]; then
    echo "${epic_id} finished its review but its PM page was not rendered — expected ${page}. It is produced by 'aid-fsm.sh done-advance review release'; if that edge was crossed with the renderer unavailable, re-render it with aid_epic_summary_page_render (then publish it with the Artifact tool)." >&2
    return 1
  fi

  local page_epoch
  _aid_ao_epic_source_epoch "$root" "$state" || return 0
  page_epoch="$(stat -c %Y "$page" 2>/dev/null || stat -f %m "$page" 2>/dev/null)" || return 0
  if (( page_epoch < _AID_AO_SRC_EPOCH )); then
    echo "${epic_id}'s PM page ${page} is OLDER than the time of ${_AID_AO_SRC_WORD} — the EPIC moved after it was summarised, so the page describes work that is no longer what merged. Re-render it." >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# MILESTONE 3 — the plan as a whole
# ---------------------------------------------------------------------------

# aid_artifact_obligation_close_page <root> <plan_id>
#   The page of the HIGHEST-NUMBERED plan-final attempt, or nothing.
#
#   By attempt number and not by mtime: attempts are numbered, never deleted,
#   and mtime is a different ordering — one `touch` on attempt 1's directory and
#   the obligation would vouch for the wrong page. This is the same
#   derive-from-disk rule aid-plan-fsm.sh's attempt allocator uses; the boundary
#   manifest names the current run directory too, but reading it would pull the
#   manifest library into a hook path that otherwise needs nothing.
aid_artifact_obligation_close_page() {
  local root="$1" plan_id="$2" best="" best_n=-1 f n
  for f in "${root}/.aid-o/work/evidence/${plan_id}"/R-"${plan_id}"-final-*/plan-close-artifact.html; do
    [[ -f "$f" ]] || continue
    n="${f%/plan-close-artifact.html}"
    n="${n##*-final-}"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    if (( n > best_n )); then best_n="$n"; best="$f"; fi
  done
  [[ -n "$best" ]] || return 1
  printf '%s' "$best"
}

# aid_artifact_obligation_close_check <root> <plan_state_file>
#   0 the page is there and current
#   1 no page, or one older than the close
#   3 not applicable — the plan is not closed
aid_artifact_obligation_close_check() {
  local root="${1:?aid_artifact_obligation_close_check: root required}"
  local state="${2:?aid_artifact_obligation_close_check: plan state file required}"
  [[ -r "$state" ]] || { echo "no readable plan state at ${state}" >&2; return 3; }
  grep -qE '^plan_state:[[:space:]]*"?CLOSED"?[[:space:]]*$' "$state" 2>/dev/null || {
    echo "$(basename "$(dirname "$state")") is not closed — no closing page is owed yet" >&2
    return 3
  }
  local plan_id
  plan_id="$(_esp_yaml "$state" plan_id)"
  # Same as the EPIC case: a CLOSED record that names no plan is corrupt, and
  # corruption must not be the way past an obligation.
  [[ -n "$plan_id" ]] || {
    echo "the plan state at ${state} says CLOSED but names no plan, so its closing page cannot be located — fix the record, then render the page." >&2
    return 1
  }

  local page
  if ! page="$(aid_artifact_obligation_close_page "$root" "$plan_id")"; then
    echo "${plan_id} was closed but its closing page was not rendered — expected .aid-o/work/evidence/${plan_id}/R-${plan_id}-final-<N>/plan-close-artifact.html. Render it: source \"\$AID_PLUGIN_PATH/scripts/lib/aid-plan-close-summary.sh\" && aid_plan_close_render \"<evidence>/pm-decision-brief.json\" \"<evidence>/release-decision.json\" \"${plan_id}\" \"<evidence>\" (then publish it with the Artifact tool)." >&2
    return 1
  fi
  if [[ "$state" -nt "$page" ]]; then
    echo "${plan_id}'s closing page ${page} is OLDER than the close itself — it describes a state the plan has already left. Re-render it." >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# aid_hook_rule_milestone_artifact — the Stop-event handler.
#
# The earlier catch of what scripts/aid-turn-gate.sh checks after the CLI
# returns. Same check, same message; only the moment differs.
# ---------------------------------------------------------------------------
aid_hook_rule_milestone_artifact() {
  local input; input="$(cat)"
  local cwd transcript
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)"

  [[ -n "$cwd" && -d "$cwd" ]] || { echo "no usable cwd in the event" >&2; return 3; }
  [[ -n "$transcript" && -r "$transcript" ]] || { echo "no readable transcript — the session window is unknown" >&2; return 3; }

  # The workspace is the one the EVENT names, not the one this process happens
  # to stand in — a hook is started wherever the harness was started. Pinning
  # it for the rest of the rule keeps every later state read on the same root,
  # instead of the check resolving one workspace and the page another.
  local root plans
  root="$(cd "$cwd" && aid_state_root 2>/dev/null)" || { echo "cwd is not inside an AID workspace" >&2; return 3; }
  export AID_PROJECT_ROOT="$root"
  plans="${root}/.aid-o/plans"
  [[ -d "$plans" ]] || { echo "no plans directory — nothing owes a page" >&2; return 3; }

  # A marker file stamped with the session's start, so `find -newer` can ask
  # "written during this session" without parsing timestamps by hand.
  local started marker rc=0
  started="$(head -1 "$transcript" | jq -r '.timestamp // ""' 2>/dev/null)"
  [[ -n "$started" && "$started" != "null" ]] || { echo "the transcript carries no start timestamp — the rule declines rather than judging older plans" >&2; return 3; }
  marker="$(mktemp)" || { echo "no temp file for the session window" >&2; return 3; }
  touch -d "$started" "$marker" 2>/dev/null || { rm -f "$marker"; echo "unreadable session start '${started}'" >&2; return 3; }

  # THE THREE MILESTONES ARE A TABLE, NOT THREE LOOPS. What differs between
  # them is a root, a find depth, a filename and which check to call; the loop
  # body — read a line, ask the check, keep only a rc==1 finding, reset — is
  # the same three times, and its `rc` handling is exactly the kind of idiom
  # that gets fixed in one copy and left wrong in the others.
  #
  # The run state files live at evidence/<epic_id>/<run_id>/fsm-state.yaml —
  # depth 3. The EPIC pages live at evidence/<plan_id>/<epic_id>/ — depth 2,
  # and carry no state file, so the two never collide.
  local findings="" err

  # WHICH PLANS THIS SESSION ACTUALLY WORKED ON — not merely which files moved
  # while it happened to be running. `find -newer` answers a question about
  # TIME, and several sessions share one workspace: a plan edited in ANOTHER
  # window is newer than this session's start too, so the rule demanded a page
  # for work this session never touched (PM, 2026-08-28: "potom mě to spamuje
  # všechny okna a ne to který má"; observed on P062, edited in a different
  # window while this session worked on P091).
  #
  # The transcript is the only per-session record a hook is handed, so the plan
  # ids it mentions are what this session can honestly be held to. A session
  # that never names a plan owes nothing for it. When the transcript yields no
  # id at all, the rule reports nothing rather than falling back to "everything
  # recent" — silence is the safe failure here, since a false demand costs
  # another window its turn.
  local _ao_mine
  _ao_mine="$(grep -oE '\bP[0-9]{3}\b' "$transcript" 2>/dev/null | sort -u | tr '\n' ' ')"

  # _mine_only <path> — true when the path names a plan this session mentioned.
  # A path with no plan id in it (a run's fsm-state under an EPIC id) is judged
  # by its own plan_id where the check can resolve one; unresolvable means the
  # same "not mine".
  _mine_only() {
    local pth="$1" id
    id="$(grep -oE '\bP[0-9]{3}\b' <<< "$pth" | head -1)"
    # A run's state file lives under its EPIC id (evidence/E-900-1_1/R-…), which
    # carries the plan number without the P: derive it rather than treating the
    # whole milestone as nobody's.
    [[ -n "$id" ]] || id="$(grep -oE '\bE-[0-9]{3}-' <<< "$pth" | head -1 | sed 's/^E-/P/; s/-$//')"
    [[ -n "$id" ]] || return 1
    [[ " $_ao_mine " == *" $id "* ]]
  }

  # _scan <check_fn> <dir> <depth> <name> — the shared body. A check is called
  # with the workspace root first unless it takes only a file (milestone 1).
  _scan() {
    local fn="$1" dir="$2" depth="$3" name="$4" hit rc=0
    [[ -d "$dir" ]] || return 0
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      _mine_only "$hit" || continue
      if [[ "$fn" == "aid_artifact_obligation_check" ]]; then
        err="$("$fn" "$hit" 2>&1)" || rc=$?
      else
        err="$("$fn" "$root" "$hit" 2>&1)" || rc=$?
      fi
      [[ "$rc" -eq 1 ]] && findings+="${err}"$'\n'
      rc=0
    done < <(find "$dir" -mindepth "$depth" -maxdepth "$depth" -name "$name" -newer "$marker" 2>/dev/null)
  }

  _scan aid_artifact_obligation_check       "$plans"                            1 'P*.md'
  _scan aid_artifact_obligation_epic_check  "${root}/.aid-o/work/evidence"      3 'fsm-state.yaml'
  _scan aid_artifact_obligation_close_check "${root}/.aid-o/work/plan-state"    2 'plan-state.yaml'
  unset -f _scan

  rm -f "$marker"

  if [[ -n "$findings" ]]; then
    printf '%s' "$findings" >&2
    return 2
  fi
  echo "every milestone finished in this session has a current PM page" >&2
  return 3
}
