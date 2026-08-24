#!/usr/bin/env bash
# =============================================================================
# lib/aid-artifact-obligation.sh — a written plan owes the PM a page
# (P086 Step 4)
#
#   aid_artifact_obligation_check <plan_file>
#   aid_hook_rule_plan_artifact              (Stop-event registry handler)
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
# **Last Updated:** 2026-08-24
# =============================================================================
[[ -n "${_AID_ARTIFACT_OBLIGATION_SH_LOADED:-}" ]] && return 0
_AID_ARTIFACT_OBLIGATION_SH_LOADED=1

_AID_AO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_AO_LIB_DIR}/aid-roots.sh"
# shellcheck source=aid-plan-summary.sh
source "${_AID_AO_LIB_DIR}/aid-plan-summary.sh"

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
# aid_hook_rule_plan_artifact — the Stop-event handler.
#
# The earlier catch of what scripts/aid-turn-gate.sh checks after the CLI
# returns. Same check, same message; only the moment differs.
# ---------------------------------------------------------------------------
aid_hook_rule_plan_artifact() {
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

  local findings="" plan
  while IFS= read -r plan; do
    [[ -n "$plan" ]] || continue
    local err; err="$(aid_artifact_obligation_check "$plan" 2>&1)" || rc=$?
    [[ "$rc" -eq 1 ]] && findings+="${err}"$'\n'
    rc=0
  done < <(find "$plans" -maxdepth 1 -name 'P*.md' -newer "$marker" 2>/dev/null)
  rm -f "$marker"

  if [[ -n "$findings" ]]; then
    printf '%s' "$findings" >&2
    return 2
  fi
  echo "every plan written in this session has a current PM page" >&2
  return 3
}
