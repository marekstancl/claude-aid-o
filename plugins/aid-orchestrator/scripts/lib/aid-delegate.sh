#!/usr/bin/env bash
# =============================================================================
# aid-delegate.sh — escalations settled by an independent agent (P112 Step 7).
#
# PM 13. 10. 2026: in a plan that runs --auto every escalation that would stop
# the run on the PM (a dispute of a review finding, a finding left open after
# the rounds) is decided by an independent agent — Codex through the round's
# own runner, an independent Claude agent when Codex is unavailable or over
# its limit. The PM keeps what would change the brief, spend money or touch
# live data: a verdict of class brief|money|data goes to the PM's card, and
# --defer-criterion never takes a delegate (aid_pm_card_check refuses it).
#
#   aid_delegate_in_force <state_root> <plan_id>   0 when delegation applies:
#       evidence/<plan>/delegate.json (standing --delegate, a manual plan), or
#       the plan state's autonomy: auto while the PM has not stopped the run
#   aid_delegate_fp16 <fingerprint>                16 hex characters after sha256:
#   aid_delegate_prompt <round_dir> <finding-json> <kind> <brief> <out>
#   aid_delegate_check <verdict-file> <kind>       prints why a verdict is unusable
#   aid_delegate_ledger <state_root> <plan_id>     path of delegated-disputes.jsonl
#
# The command that runs, records and lists is aid-review-round.sh delegate.
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================

[[ -n "${_AID_DELEGATE_LOADED:-}" ]] && return 0
_AID_DELEGATE_LOADED=1
_AID_DLG_PLUGIN="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=aid-permissions.sh
source "${_AID_DLG_PLUGIN}/scripts/lib/aid-permissions.sh"   # _aid_auto_declared — a PM stop wins

aid_delegate_in_force() {
  local root="$1" pid="$2" auto
  [[ -n "$pid" ]] || return 1
  local dj="${root}/.aid-o/work/evidence/${pid}/delegate.json"
  # the PM's record as standing --delegate writes it, not any file at that path
  [[ -f "$dj" ]] && jq -e '.delegate == true and .by == "PM" and ((.words // "") | length >= 20)' "$dj" >/dev/null 2>&1 && return 0
  [[ "$(_aid_auto_declared "$root")" == manual ]] && return 1
  auto="$(yq -r '.autonomy // ""' "${root}/.aid-o/work/plan-state/${pid}/plan-state.yaml" 2>/dev/null)"
  [[ "$auto" == auto ]]
}

aid_delegate_fp16() { local f="${1#sha256:}"; printf '%s' "${f:0:16}"; }

aid_delegate_ledger() { printf '%s/.aid-o/work/evidence/%s/delegated-disputes.jsonl' "$1" "$2"; }

# aid_delegate_prompt <round_dir> <finding-json> <kind> <brief path> <out>
aid_delegate_prompt() {
  local dir="$1" finding="$2" kind="$3" brief="$4" out="$5"
  {
    cat "${_AID_DLG_PLUGIN}/defaults/templates/adjudicator-delegated.md"
    echo
    echo "## The escalation (${kind})"
    echo
    echo "Round: ${dir}"
    echo "Brief (the PM's points of done): ${brief:-none recorded}"
    echo
    echo '```json'
    jq '{fingerprint, severity, status, claim, evidence, command, fix, rule, reported_by, dispute}' <<< "$finding"
    echo '```'
    echo
    if [[ "$kind" == dispute ]]; then
      echo "The author disputes it: $(jq -r '.dispute.reason // "(no reason recorded)"' <<< "$finding")"
    else
      echo "Nobody disputed it; it is still open after the last review round the plan allows."
      jq -e '.delegated.answer == "fix"' <<< "$finding" >/dev/null 2>&1 \
        && echo "A delegate already granted one more fix round and the finding is still open: answer dismiss, or class brief if the plan would deliver less than the brief."
    fi
    echo
    local vf; vf="${dir}/adjudicator-delegated-$(aid_delegate_fp16 "$(jq -r .fingerprint <<< "$finding")").json"
    # Codex runs in a read-only sandbox and its LAST MESSAGE is what the runner saves (codex exec -o):
    # an instruction to write the file made it answer with a complaint instead (aidlab-apps 16. 10. 2026).
    echo "Your final message is ONE JSON object and nothing else. In a read-only sandbox do not try to write a file —"
    echo "your final message is saved to ${vf}. If you are a stand-in that can write files, write that JSON object to ${vf}."
    echo "Leave nothing behind in the repository: run checks in a temporary copy or remove what they create (uv.lock,"
    echo "__pycache__, build output) — a new file in the plan's worktree makes the step's return fail."
  } > "$out"
}

# aid_delegate_check <verdict-file> <kind> — nothing when usable, else the reason.
# A technical dispute carries the re-run of the disputed check (cmd, exit, output).
aid_delegate_check() {
  local v="$1" kind="$2"
  jq -e 'type == "object"' "$v" >/dev/null 2>&1 || { echo "the verdict is not one JSON object"; return 0; }
  local f
  for f in fingerprint kind answer class reason provider; do
    jq -e --arg f "$f" '(.[$f] // "") | type == "string" and length > 0' "$v" >/dev/null 2>&1 || { echo "the verdict has no ${f}"; return 0; }
  done
  jq -e '.provider | IN("codex", "claude")' "$v" >/dev/null || { echo "provider must be codex or claude"; return 0; }
  [[ "$(jq -r .kind "$v")" == "$kind" ]] || { echo "kind is $(jq -r .kind "$v"), the escalation is ${kind}"; return 0; }
  jq -e '.class | IN("technical", "brief", "money", "data")' "$v" >/dev/null || { echo "class must be technical, brief, money or data"; return 0; }
  if [[ "$kind" == dispute ]]; then
    jq -e '.answer | IN("accepted", "rejected")' "$v" >/dev/null || { echo "a dispute is answered accepted or rejected"; return 0; }
    if [[ "$(jq -r .class "$v")" == technical ]]; then
      jq -e '(.rerun.cmd // "" | type == "string" and length > 0) and (.rerun.exit | type == "number") and (.rerun.output_tail | type == "string")' "$v" >/dev/null 2>&1 \
        || { echo "a technical dispute carries the re-run of the check: rerun {cmd, exit (number), output_tail}"; return 0; }
    fi
  else
    jq -e '.answer | IN("dismiss", "fix")' "$v" >/dev/null || { echo "a finding open after the rounds is answered dismiss or fix"; return 0; }
  fi
  return 0
}
