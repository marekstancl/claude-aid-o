#!/usr/bin/env bash
# =============================================================================
# lib/aid-brainstorm-opponent.sh — a second model argues with the design while
# it is being made (P086 Step 8)
#
#   aid_brainstorm_opponent_run <plan_id> <brief_file> <out_dir>
#
# WHY THIS EXISTS
#   Brainstorming has been a monologue. An opponent existed, but only AFTER the
#   plan was written (the C0 review), which is the expensive place to find a
#   wrong premise. This puts the second model INSIDE the design, where changing
#   your mind is still cheap.
#
# WHAT IT IS NOT
#   Not a reviewer, and not a vote. What the two models AGREE on is written
#   down without troubling the PM; what they DISAGREE on goes to the PM as a
#   decision with options. Neither model gets to overrule the other, and the
#   dispute artifact keeps both positions so what the PM saw stays checkable.
#
# THE HONEST LIMITS, WRITTEN DOWN BECAUSE THEY ARE EASY TO FORGET
#   - Two models agreeing on something WRONG is not caught here. Nothing in
#     this file looks for that; it is a known boundary of the design, not a
#     defect in it.
#   - An opponent that cannot be reached does not become agreement. The run
#     continues as a monologue and SAYS SO — the same refusal
#     lib/aid-audit-independence.sh makes for audits.
#   - An answer that is not in the required shape is treated as UNREACHED, for
#     the same reason: prose that could not be parsed is not consent.
#   - "They agreed" is the OPPONENT'S OWN CLAIM about the brief, not a
#     comparison this code performs. Nothing here checks that an `agree` entry
#     corresponds to a position the brief actually held, so an opponent that
#     agrees with something nobody said writes it down unchallenged. The shape
#     is validated; the correspondence is not.
#
# WHAT IS REUSED, AND WHAT IS NOT
#   The Codex transport is `_run_codex_isolated` from lib/aid-c3-dispatch.sh —
#   the shared, hardened launcher (fresh process, read-only sandbox, the
#   --output-schema trap already learned). Availability comes from
#   lib/aid-audit-independence.sh. What is NOT reused is C0's dispatch state
#   machine: attempts, ledgers and override artifacts belong to a gate that
#   blocks a release, and a brainstorm is not that.
#
#   Which model plays the opponent is CONFIGURATION (AID_C3_CODEX_MODEL /
#   CODEX_MODEL), not architecture. The vision says "an opponent from another
#   platform", not "Codex forever".
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-24
# =============================================================================
[[ -n "${_AID_BRAINSTORM_OPPONENT_SH_LOADED:-}" ]] && return 0
_AID_BRAINSTORM_OPPONENT_SH_LOADED=1

_AID_BO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-c3-dispatch.sh
source "${_AID_BO_LIB_DIR}/aid-c3-dispatch.sh"
# shellcheck source=aid-roots.sh
source "${_AID_BO_LIB_DIR}/aid-roots.sh"

# The most disagreements a PM is asked to decide in one sitting. The rest stay
# in the artifact: a list of twenty is not a decision, it is a document.
_AID_BO_MAX_TO_PM=5

# _aid_bo_prompt <brief_file> — the whole instruction, including the shape the
# answer must have. The shape is enforced by this file's own validator and not
# by --output-schema: Codex forwards a schema to strict structured output,
# which hard-fails on conditional keywords (see lib/aid-c3-dispatch.sh).
_aid_bo_prompt() {
  cat <<'INSTR'
You are the OPPONENT in a design conversation. Another model has drafted the
positions below. Your job is to disagree where you actually disagree and to
agree where you actually agree — not to be contrary, and not to be agreeable.

Read nothing from disk. Everything you need is in this prompt.

Answer with ONE JSON object and no other text:

{"agree":    [{"point": "<the position, in one sentence>",
               "why":   "<why you hold it too>"}],
 "disagree": [{"point":             "<what the disagreement is about>",
               "aid_position":      "<their position, stated fairly>",
               "opponent_position": "<yours>",
               "stake":             "<what it costs to get this wrong>"}],
 "missing":  ["<anything neither position covers, one line each>"]}

Any of the three arrays may be empty. State a disagreement only where the two
positions would lead to different work.

--- THE DRAFT POSITIONS ---
INSTR
  cat "$1"
}

# _aid_bo_valid <json_file> — the answer's shape. Anything else is treated as
# an opponent that was not reached.
_aid_bo_valid() {
  jq -e 'type == "object"
         and (.agree | type == "array")
         and (.disagree | type == "array")
         and ((.missing // []) | type == "array")
         and all(.agree[]; type == "object" and has("point"))
         and all(.disagree[]; type == "object"
                 and has("point") and has("aid_position") and has("opponent_position"))' \
     "$1" >/dev/null 2>&1
}

# _aid_bo_write_unreached <out> <reason>
#   Returns 1 when it could not write. "The artifact records that the opponent
#   was not reached" has to be a fact about a file, not about an intention: a
#   full disk would otherwise leave the run claiming a record it does not have.
_aid_bo_write_unreached() {
  jq -n --arg r "$2" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{opponent: "unreached", reason: $r, created_at: $at,
      agree: [], disagree: [], missing: []}' > "$1" 2>/dev/null || {
    echo "opponent: could not write ${1} — the run has no record of what happened" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# aid_brainstorm_opponent_run <plan_id> <brief_file> <out_dir>
#
#   0  the opponent answered — read <out_dir>/dispute.json for what it said
#   1  the vision gate refused, or the arguments are unusable
#   3  the opponent was not reached; the run continues as a monologue and the
#      artifact records that it did
# ---------------------------------------------------------------------------
aid_brainstorm_opponent_run() {
  local plan_id="${1:?opponent: plan id required}"
  local brief="${2:?opponent: brief file required}"
  local out_dir="${3:?opponent: output directory required}"

  [[ -r "$brief" ]] || { echo "opponent: cannot read the brief ${brief}" >&2; return 1; }
  mkdir -p "$out_dir" || { echo "opponent: cannot create ${out_dir}" >&2; return 1; }
  local dispute="${out_dir}/dispute.json"

  # The vision gate is the reason Step 7 is a transition and not a sentence:
  # the opponent is dispatched by code, so code can refuse to dispatch it.
  local gate_out gate_rc=0
  gate_out="$(bash "${_AID_BO_LIB_DIR}/../aid-brainstorm-state.sh" gate "$plan_id" --phase opponent 2>&1)" || gate_rc=$?
  if [[ "$gate_rc" -ne 0 ]]; then
    printf '%s\n' "$gate_out" >&2
    return 1
  fi

  local avail rc=0
  avail="$(bash "${_AID_BO_LIB_DIR}/aid-audit-independence.sh" detect --required cross_provider 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _aid_bo_write_unreached "$dispute" "$avail" || return 1
    echo "opponent not reached — this brainstorm is a monologue and the artifact says so: ${avail}" >&2
    return 3
  fi

  local root; root="$(aid_state_root)" || root="$PWD"
  local tmp; tmp="$(mktemp -d)" || { echo "opponent: no temp dir" >&2; return 1; }
  _aid_bo_prompt "$brief" > "${tmp}/prompt.txt"

  local drc=0
  _run_codex_isolated "$root" "${tmp}/prompt.txt" \
    "${tmp}/events.jsonl" "${tmp}/stderr.txt" "${tmp}/answer.txt" || drc=$?

  if [[ "$drc" -ne 0 || ! -s "${tmp}/answer.txt" ]]; then
    _aid_bo_write_unreached "$dispute" "the opponent did not answer (exit ${drc})" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    echo "opponent not reached (exit ${drc}) — continuing as a monologue" >&2
    return 3
  fi

  # A fenced answer is still an answer; anything that is not one object is not.
  sed -e 's/^```json$//' -e 's/^```$//' "${tmp}/answer.txt" > "${tmp}/answer.json"
  if ! _aid_bo_valid "${tmp}/answer.json"; then
    _aid_bo_write_unreached "$dispute" "the opponent answered outside the required shape — an answer that cannot be read is not agreement" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    echo "opponent answered outside the required shape — treated as not reached" >&2
    return 3
  fi

  jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg p "$plan_id" \
     --arg m "${CODEX_MODEL:-unknown}" --argjson cap "$_AID_BO_MAX_TO_PM" \
     '{opponent: "answered", plan_id: $p, model: $m, created_at: $at,
       agree: (.agree // []), disagree: (.disagree // []), missing: (.missing // []),
       to_pm: ((.disagree // [])[:$cap]),
       held_back: (((.disagree // []) | length) - $cap | if . < 0 then 0 else . end)}' \
     "${tmp}/answer.json" > "$dispute" 2>/dev/null || {
    rm -rf "$tmp"
    echo "opponent: the answer could not be written to ${dispute} — nothing is recorded, so nothing is claimed" >&2
    return 1
  }
  rm -rf "$tmp"

  local agreed disputed held
  agreed="$(jq -r '.agree | length' "$dispute")"
  disputed="$(jq -r '.disagree | length' "$dispute")"
  held="$(jq -r '.held_back' "$dispute")"
  printf 'opponent answered: %s agreed, %s disputed' "$agreed" "$disputed" >&2
  (( held > 0 )) && printf ' (%s beyond the %s shown to the PM, all in %s)' "$held" "$_AID_BO_MAX_TO_PM" "$dispute" >&2
  printf '\n' >&2
  return 0
}

# Runnable as well as sourceable — the same guard lib/aid-c3-dispatch.sh uses,
# so sourcing this file never launches a dispatch.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  aid_brainstorm_opponent_run "$@"
fi
