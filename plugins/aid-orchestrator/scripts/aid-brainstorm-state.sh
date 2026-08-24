#!/usr/bin/env bash
# =============================================================================
# aid-brainstorm-state.sh — the state a brainstorming run actually has
# (P086 Step 7)
#
#   aid-brainstorm-state.sh init <plan_id>
#         --scope roadmap|multi_plan|user_visible|single_plan [--topic <text>]
#   aid-brainstorm-state.sh vision-propose <plan_id> --file <vision.md>
#   aid-brainstorm-state.sh vision-approve <plan_id>
#   aid-brainstorm-state.sh vision-reject  <plan_id> --reason <text>
#   aid-brainstorm-state.sh gate <plan_id> --phase design|opponent|summary
#   aid-brainstorm-state.sh approve <plan_id>
#   aid-brainstorm-state.sh show <plan_id>
#
# WHY A STATE FILE AND NOT A SENTENCE IN THE SKILL
#   "Agree the vision before going further" written in skills/brainstorming.md
#   is degree 4 on the ecosystem scale — prose. The same rule with a transition
#   behind it is degree 1: `gate` refuses, and the phase does not start. The
#   difference is this file. A step of the plan that added the sentence without
#   the state would have added nothing.
#
#   Being honest about how far that reaches: `gate --phase opponent` is called
#   by code (lib/aid-brainstorm-opponent.sh) and therefore really does stop the
#   opponent. `gate --phase design` is called by the controller following the
#   skill, so for the design phase this is a checkable instruction rather than
#   a closed door. Both are worth having; only one of them is degree 1, and
#   saying otherwise would be the decoration this plan exists to remove.
#
# THE VISION'S FORM IS THESIS + TEST
#   A vision point with nothing that could show it false is a slogan. So the
#   file must carry, for every `- V<n>: <thesis>` line, a nested `test:` line —
#   and `vision-propose` refuses the file naming each point that has none. The
#   keyword is English because plan documents are (`document_language` in
#   defaults/orchestration.yaml); the thesis and the test are in whatever
#   language the document is written in.
#
# WHERE THE VISION IS REQUIRED
#   A roadmap, work split across several plans, and anything that CHANGES
#   BEHAVIOUR A USER MEETS (`user_visible`). Only work nobody outside the code
#   will notice — a refactor, a tidy-up — skips it, and the skip is RECORDED
#   with its reason rather than being silently absent.
#
#   `user_visible` was added because the original rule tied the vision to plan
#   COUNT, which is a proxy for the thing that actually matters: whether the
#   two of you can afford to have meant different things. A single plan that
#   changes what a user sees can afford that no better than a roadmap can.
#
# STATE LIVES WITH THE REST OF THE WORKSPACE (`.aid-o/work/brainstorm/<plan_id>/`)
#   — this is a command the controller runs, not a hook, so the rule against
#   hooks writing into the tree does not apply. The run id is the plan id: one
#   brainstorm per plan.
#
# EXIT CODES: 0 fine, 1 refused (reason on stderr), 2 usage.
#
# **Last Updated:** 2026-08-24
# =============================================================================
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/aid-roots.sh
source "${PLUGIN_ROOT}/scripts/lib/aid-roots.sh"

state_dir() {
  local plan_id="$1" root
  root="$(aid_state_root)" || return 1
  printf '%s/.aid-o/work/brainstorm/%s' "$root" "$plan_id"
}

state_file() { printf '%s/state.yaml' "$(state_dir "$1")"; }

require_state() {
  local f; f="$(state_file "$1")" || return 1
  if [[ ! -r "$f" ]]; then
    echo "ERROR: no brainstorming run for $1 — start one with: aid-brainstorm-state.sh init $1 --scope <roadmap|multi_plan|single_plan>" >&2
    return 1
  fi
  printf '%s' "$f"
}

get() { yq -r ".$2 // \"\"" "$1" 2>/dev/null; }

set_field() { # set_field <file> <key> <value>
  yq -i ".$2 = \"$3\" | .updated_at = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" "$1"
}

# ---------------------------------------------------------------------------
# validate_vision <file>
#
# Every `- V<n>: <thesis>` needs a `test:` line before the next one. Prints one
# line per point that has none; returns 1 when any does, 2 when the file has no
# vision points at all.
# ---------------------------------------------------------------------------
validate_vision() {
  local file="$1"
  [[ -r "$file" ]] || { echo "ERROR: cannot read the vision file $file" >&2; return 2; }
  awk '
    function flush() {
      if (point != "" && !has_test) { print point; bad++ }
    }
    /^[[:space:]]*-[[:space:]]*V[0-9]+[[:space:]]*:/ {
      flush()
      point = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", point)
      has_test = 0
      next
    }
    point != "" && tolower($0) ~ /(^|[^a-z])test[[:space:]]*:/ { has_test = 1 }
    # `point` empty at the end means no `- Vn:` line was ever seen — the file
    # carries no vision at all, which is a different refusal from "a point has
    # no test".
    END { flush(); if (point == "") exit 2; exit (bad > 0) }
  ' "$file"
}

cmd_init() {
  local plan_id="${1:?}" scope="" topic="" want_worktree=1
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scope) scope="${2:-}"; shift 2 ;;
      --topic) topic="${2:-}"; shift 2 ;;
      --no-worktree) want_worktree=0; shift ;;
      *) echo "ERROR: init: unknown flag '$1'" >&2; return 2 ;;
    esac
  done
  case "$scope" in
    roadmap|multi_plan|user_visible|single_plan) ;;
    *) echo "ERROR: --scope must be roadmap, multi_plan, user_visible or single_plan (got '${scope}')" >&2; return 2 ;;
  esac

  local dir; dir="$(state_dir "$plan_id")" || return 1
  mkdir -p "$dir" || { echo "ERROR: cannot create $dir" >&2; return 1; }

  local required=true skip=""
  if [[ "$scope" == "single_plan" ]]; then
    required=false
    skip="work no user will notice — a refactor or a tidy-up, where a shared assumption costs less than the ceremony of agreeing one"
  fi
  cat > "$(state_file "$plan_id")" <<Y
plan_id: "${plan_id}"
topic: "${topic//\"/}"
scope: "${scope}"
vision_required: ${required}
vision_state: "none"
vision_file: ""
run_state: "open"
skip_reason: "${skip}"
created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
updated_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
Y
  # The run's own working copy, from the same command that starts the run.
  # Left to a separate instruction it was a suggestion the flow could skip;
  # here it is simply what starting a brainstorm does, and the path is printed
  # for the controller to work in.
  local root workdir=""
  root="$(aid_state_root)" || return 1
  if [[ "$want_worktree" -eq 1 ]]; then
    # --project-root is passed EXPLICITLY: aid-plan-fsm.sh resolves its root
    # with its own resolver, and letting it infer one from this process's cwd
    # is how a run started from somewhere else creates a worktree in whichever
    # repository the shell happened to be standing in.
    workdir="$(bash "${PLUGIN_ROOT}/scripts/aid-plan-fsm.sh" plan-scratch "$plan_id" \
                 --phase brainstorm --project-root "$root" 2>/dev/null)" || workdir=""
  fi
  [[ -n "$workdir" ]] || workdir="$root"

  if [[ "$required" == "true" ]]; then
    echo "Brainstorming run ${plan_id} (${scope}) — a vision is required before the design phase."
  else
    echo "Brainstorming run ${plan_id} (${scope}) — no vision step: ${skip}"
  fi
  echo "workdir: ${workdir}"
}

cmd_vision_propose() {
  local plan_id="${1:?}" file=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="${2:-}"; shift 2 ;;
      *) echo "ERROR: vision-propose: unknown flag '$1'" >&2; return 2 ;;
    esac
  done
  [[ -n "$file" ]] || { echo "ERROR: vision-propose needs --file <vision.md>" >&2; return 2; }
  local sf; sf="$(require_state "$plan_id")" || return 1

  local missing rc=0
  missing="$(validate_vision "$file")" || rc=$?
  case "$rc" in
    0) ;;
    2) echo "REFUSED: ${file} carries no vision points at all. The form is '- V1: <thesis>' with a nested 'test:' line under each." >&2; return 1 ;;
    *)
      echo "REFUSED: every vision point needs a test — something that could show it false. These have none:" >&2
      printf '  %s\n' "$missing" >&2
      echo "A point with no test is a slogan, and a slogan cannot be disagreed with later." >&2
      return 1 ;;
  esac

  set_field "$sf" vision_state proposed
  set_field "$sf" vision_file "$file"
  echo "Vision proposed for ${plan_id} from ${file} — it now needs the PM's approval."
}

cmd_vision_approve() {
  local plan_id="${1:?}"
  local sf; sf="$(require_state "$plan_id")" || return 1
  local cur; cur="$(get "$sf" vision_state)"
  if [[ "$cur" != "proposed" ]]; then
    echo "REFUSED: ${plan_id}'s vision is '${cur}' — only a proposed vision can be approved, and a proposed one has already passed the thesis-and-test check." >&2
    return 1
  fi
  set_field "$sf" vision_state approved
  echo "Vision approved for ${plan_id}."
}

cmd_vision_reject() {
  local plan_id="${1:?}" reason=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      *) echo "ERROR: vision-reject: unknown flag '$1'" >&2; return 2 ;;
    esac
  done
  [[ -n "$reason" ]] || { echo "ERROR: vision-reject needs --reason <text>" >&2; return 2; }
  local sf; sf="$(require_state "$plan_id")" || return 1
  set_field "$sf" vision_state rejected
  set_field "$sf" skip_reason "${reason//\"/}"
  echo "Vision rejected for ${plan_id} — go back to the inputs; the run does not continue to design without one."
}

cmd_gate() {
  local plan_id="${1:?}" phase=""
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --phase) phase="${2:-}"; shift 2 ;;
      *) echo "ERROR: gate: unknown flag '$1'" >&2; return 2 ;;
    esac
  done
  case "$phase" in
    design|opponent|summary) ;;
    *) echo "ERROR: --phase must be design, opponent or summary (got '${phase}')" >&2; return 2 ;;
  esac
  local sf; sf="$(require_state "$plan_id")" || return 1

  local required state; required="$(get "$sf" vision_required)"; state="$(get "$sf" vision_state)"
  if [[ "$required" != "true" ]]; then
    echo "${phase}: allowed — this run has no vision step ($(get "$sf" skip_reason))."
    return 0
  fi
  if [[ "$state" == "approved" ]]; then
    echo "${phase}: allowed — the vision is approved."
    return 0
  fi
  echo "REFUSED: ${plan_id} may not enter '${phase}' — its vision is '${state}', not approved. A vision the PM has not agreed to is not a boundary, and everything after this phase would be built on it." >&2
  return 1
}

# ---------------------------------------------------------------------------
# approve — the PM accepts the brainstorm as a whole, and ONLY THEN does its
# VISION leave the working directory.
#
# WHAT MOVES AND WHAT DOES NOT: the vision is copied next to the plans, because
# that is the document later plans are built inside. Everything else — the
# dispute artifact, the rendered page, the state file — deliberately STAYS in
# `.aid-o/work/brainstorm/<plan_id>/`, and the command says so. The page's own
# boundary is enforced by lib/aid-brainstorm-summary.sh, which refuses to write
# an unaccepted run's page outside that directory.
#
# WHY PROMOTION IS A SEPARATE ACT: a run the PM never accepted must not have
# left a vision document sitting next to the plans as though it had been agreed
# — a half-finished brainstorm that looks finished is worse than one that is
# visibly unfinished.
# ---------------------------------------------------------------------------
cmd_approve() {
  local plan_id="${1:?}"
  local sf; sf="$(require_state "$plan_id")" || return 1

  local required state; required="$(get "$sf" vision_required)"; state="$(get "$sf" vision_state)"
  if [[ "$required" == "true" && "$state" != "approved" ]]; then
    echo "REFUSED: ${plan_id}'s vision is '${state}' — a run whose vision was never agreed is not a run to accept." >&2
    return 1
  fi

  local root dir vision promoted=""
  root="$(aid_state_root)" || return 1
  dir="$(state_dir "$plan_id")" || return 1

  # A run cannot be accepted before the PM has been given something to read.
  # Without this, "accepted" could mean a state field was set while the page the
  # decision rests on was never rendered.
  if ! compgen -G "${dir}/*.html" > /dev/null; then
    echo "REFUSED: ${plan_id} has no rendered page in ${dir} — there is nothing the acceptance could be based on. Render it first: source scripts/lib/aid-brainstorm-summary.sh && aid_brainstorm_summary_render ${plan_id} ${dir}/brainstorm-summary-artifact.html" >&2
    return 1
  fi

  # THE OPPONENT LEAVES A RECORD OR THE RUN DOES NOT CLOSE (P088 Step 5).
  # A MONOLOGUE IS A LEGITIMATE OUTCOME — `unreached` closes the run fine. What
  # cannot happen is closing with no record at all, because then "two models
  # went over this" is a sentence nobody can check.
  #
  # WHAT THIS DOES NOT PROVE, and the row in the enforcement registry says the
  # same: that a second platform was really called, that it answered, or that it
  # is independent of the first. A file check cannot show any of that. What it
  # does is make pretending DELIBERATE — the record has to be written on purpose
  # — which is worth having and is not the same as proof.
  local dispute="${dir}/dispute.json" opp=""
  if [[ ! -r "$dispute" ]]; then
    echo "REFUSED: ${plan_id} has no record of the opponent (${dispute}). A monologue is a fine outcome, but it has to be written down: run scripts/lib/aid-brainstorm-opponent.sh, which records 'unreached' when the second model cannot be had." >&2
    return 1
  fi
  opp="$(jq -r '.opponent // ""' "$dispute" 2>/dev/null)" || opp=""
  case "$opp" in
    answered|unreached) ;;
    *)
      echo "REFUSED: ${dispute} is unreadable or carries opponent='${opp:-<none>}' — a damaged record is not a record. Expected 'answered' or 'unreached'." >&2
      return 1 ;;
  esac
  # The record must be THIS run's. Without the check a file dropped into the
  # directory — or copied from another run — closes the run just as well, and
  # the whole point of requiring a record is that it is about this work.
  local rec_plan; rec_plan="$(jq -r '.plan_id // ""' "$dispute" 2>/dev/null)" || rec_plan=""
  if [[ "$rec_plan" != "$plan_id" ]]; then
    echo "REFUSED: ${dispute} records plan_id='${rec_plan:-<none>}', not ${plan_id} — a record from another run (or none) does not close this one." >&2
    return 1
  fi
  [[ "$opp" == "unreached" ]] && echo "NOTE: the opponent was never reached for ${plan_id} — this design was a monologue, and the page says so." >&2
  vision="$(get "$sf" vision_file)"
  if [[ -n "$vision" && -r "$vision" ]]; then
    mkdir -p "${root}/.aid-o/plans" || { echo "ERROR: cannot create ${root}/.aid-o/plans" >&2; return 1; }
    cp "$vision" "${root}/.aid-o/plans/${plan_id}-vision.md" || {
      echo "ERROR: could not promote the vision to ${root}/.aid-o/plans/${plan_id}-vision.md" >&2; return 1; }
    promoted="${root}/.aid-o/plans/${plan_id}-vision.md"
  fi

  set_field "$sf" run_state approved
  echo "Brainstorming run ${plan_id} accepted."
  [[ -n "$promoted" ]] && echo "promoted: ${promoted}"
  echo "working artifacts remain in ${dir}"
}

cmd_show() {
  local sf; sf="$(require_state "${1:?}")" || return 1
  cat "$sf"
}

main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] && shift
  case "$cmd" in
    init)            cmd_init "$@" ;;
    vision-propose)  cmd_vision_propose "$@" ;;
    vision-approve)  cmd_vision_approve "$@" ;;
    vision-reject)   cmd_vision_reject "$@" ;;
    gate)            cmd_gate "$@" ;;
    approve)         cmd_approve "$@" ;;
    show)            cmd_show "$@" ;;
    *)
      cat >&2 <<'EOF'
Usage: aid-brainstorm-state.sh <command> <plan_id> [flags]

  init <plan_id> --scope roadmap|multi_plan|single_plan [--topic <text>]
  vision-propose <plan_id> --file <vision.md>
  vision-approve <plan_id>
  vision-reject <plan_id> --reason <text>
  gate <plan_id> --phase design|opponent|summary
  approve <plan_id>
  show <plan_id>
EOF
      return 2 ;;
  esac
}

main "$@"
