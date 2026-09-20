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
#   - An opponent that cannot be reached does not become agreement. Since P095
#     it does not become a monologue or a question either: when NO codex can be
#     reached (absent, outdated, over its usage limit), a claude agent answers
#     the same brief and the record says which provider answered and why (exit
#     4 and `--answer`). The three-attempt cap and the `ask_pm` decision remain
#     for the narrower case a codex answered the probe and then said nothing.
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
#   `aid_codex_probe` in the same file: the binary is chosen by version and the
#   usage limit is probed, because neither `command -v` nor a --version check
#   can see a codex that is installed and refusing to answer. What is NOT reused is C0's dispatch state
#   machine: attempts, ledgers and override artifacts belong to a gate that
#   blocks a release, and a brainstorm is not that.
#
#   Which model plays the opponent is CONFIGURATION (AID_C3_CODEX_MODEL /
#   CODEX_MODEL), not architecture. The vision says "an opponent from another
#   platform", not "Codex forever".
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-09-20
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

# How many attempts one run may spend on an unreachable opponent. THE THIRD
# FAILURE IS THE LAST: `ask_pm` is false from then on and the run carries on as
# a recorded monologue. Three means three — an earlier version wrote
# `ask_pm: (n <= cap)`, which let a FOURTH attempt through and made the promise
# in the CHANGELOG false. Measured motivation: Codex returned 529 three times in
# a row on 2026-08-24.
_AID_BO_MAX_ATTEMPTS=3

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

# _aid_bo_attempts <out> — how many unreachable attempts this run has recorded.
_aid_bo_attempts() {
  local f="$1"
  [[ -r "$f" ]] || { printf '0'; return 0; }
  local n; n="$(jq -r '.attempts // 0' "$f" 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}

# _aid_bo_write_unreached <out> <plan_id> <reason> <attempts>
#   Returns 1 when it could not write. "The artifact records that the opponent
#   was not reached" has to be a fact about a file, not about an intention: a
#   full disk would otherwise leave the run claiming a record it does not have.
_aid_bo_write_unreached() {
  jq -n --arg p "$2" --arg r "$3" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson n "${4:-1}" --argjson cap "$_AID_BO_MAX_ATTEMPTS" \
    '{opponent: "unreached", plan_id: $p, reason: $r, created_at: $at,
      attempts: $n, attempts_cap: $cap, ask_pm: ($n < $cap),
      agree: [], disagree: [], missing: []}' > "$1" 2>/dev/null || {
    echo "opponent: could not write ${1} — the run has no record of what happened" >&2
    return 1
  }
}

# _aid_bo_monologue <attempt> <what> — the one line the run prints when a codex
# that WAS reachable gave nothing back. The third failure is the last: from then
# on the run says so instead of asking the PM again.
_aid_bo_monologue() {
  if (( $1 >= _AID_BO_MAX_ATTEMPTS )); then
    echo "opponent not reached ${_AID_BO_MAX_ATTEMPTS}+ times — no longer asking; this brainstorm continues as a recorded monologue: $2" >&2
  else
    echo "opponent not reached — this brainstorm is a monologue and the artifact says so: $2" >&2
  fi
}

# ---------------------------------------------------------------------------
# aid_brainstorm_opponent_run <plan_id> <brief_file> <out_dir>
#
#   0  the opponent answered — read <out_dir>/dispute.json for what it said
#   1  the vision gate refused, or the arguments are unusable
#   3  the opponent was not reached although a codex answered the probe; the
#      run continues as a monologue and the artifact records that it did
#   4  no codex could be reached at all: the STAND-IN line names the prompt the
#      controller must give a claude agent, whose answer comes back through
#      `--answer <file>`. The PM is told, never asked (PM instruction 2026-09-19).
#
#   aid_brainstorm_opponent_run <plan_id> <brief> <out_dir> [--answer <file>]
# ---------------------------------------------------------------------------
aid_brainstorm_opponent_run() {
  local plan_id="${1:?opponent: plan id required}"
  local brief="${2:?opponent: brief file required}"
  local out_dir="${3:?opponent: output directory required}"
  shift 3 || true
  local stand_in_answer=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --answer) stand_in_answer="${2:?opponent: --answer needs a file}"; shift 2 ;;
      *) echo "opponent: unknown option $1" >&2; return 1 ;;
    esac
  done

  [[ -r "$brief" ]] || { echo "opponent: cannot read the brief ${brief}" >&2; return 1; }
  mkdir -p "$out_dir" || { echo "opponent: cannot create ${out_dir}" >&2; return 1; }
  local dispute="${out_dir}/dispute.json"
  local standin="${out_dir}/stand-in.json"

  # The stand-in's answer comes back here. It is the same brief and the same
  # shape; only the provider differs, and the record says so.
  if [[ -n "$stand_in_answer" ]]; then
    [[ -r "$standin" ]] || { echo "opponent: --answer without a stand-in asked for (no ${standin})" >&2; return 1; }
    local why; why="$(jq -r '.reason // "unknown"' "$standin")"
    sed -e 's/^```json$//' -e 's/^```$//' "$stand_in_answer" > "${out_dir}/.stand-in-answer.json"
    if ! _aid_bo_valid "${out_dir}/.stand-in-answer.json"; then
      rm -f "${out_dir}/.stand-in-answer.json"
      _aid_bo_write_unreached "$dispute" "$plan_id" "stand_in_invalid: the stand-in answered outside the required shape" \
        "$(( $(_aid_bo_attempts "$dispute") + 1 ))" || return 1
      echo "opponent: the stand-in answered outside the required shape — dispatch it once more with --answer" >&2
      return 1
    fi
    jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg p "$plan_id" \
       --arg m "$(jq -r '.model // "unknown"' "$standin")" --arg why "$why" --argjson cap "$_AID_BO_MAX_TO_PM" \
       '{opponent: "answered", plan_id: $p, model: $m, provider: "claude", fallback_reason: $why, created_at: $at,
         agree: (.agree // []), disagree: (.disagree // []), missing: (.missing // []),
         to_pm: ((.disagree // [])[:$cap]),
         held_back: (((.disagree // []) | length) - $cap | if . < 0 then 0 else . end)}' \
       "${out_dir}/.stand-in-answer.json" > "$dispute" || {
      rm -f "${out_dir}/.stand-in-answer.json"
      echo "opponent: the stand-in answer could not be written to ${dispute}" >&2; return 1; }
    rm -f "${out_dir}/.stand-in-answer.json"
    echo "opponent answered by a claude stand-in (codex ${why}): $(jq -r '.agree | length' "$dispute") agreed, $(jq -r '.disagree | length' "$dispute") disputed" >&2
    return 0
  fi

  # The vision gate is the reason Step 7 is a transition and not a sentence:
  # the opponent is dispatched by code, so code can refuse to dispatch it.
  local gate_out gate_rc=0
  gate_out="$(bash "${_AID_BO_LIB_DIR}/../aid-brainstorm-state.sh" gate "$plan_id" --phase opponent 2>&1)" || gate_rc=$?
  if [[ "$gate_rc" -ne 0 ]]; then
    printf '%s\n' "$gate_out" >&2
    return 1
  fi

  # THE CAP IS CHECKED BEFORE THE ATTEMPT, not after it. An earlier version only
  # stopped ASKING once the cap was spent, so a fourth call still ran detection
  # and dispatch and recorded `attempts: 4` — "capped at three attempts per run"
  # was a sentence the code did not keep (found in review, twice: first the
  # off-by-one, then this). A cap that does not prevent the attempt is a counter.
  local prior; prior="$(_aid_bo_attempts "$dispute")"
  # The number this call would record if it fails — every unreached path
  # writes the same one, so it is worked out once.
  local attempt=$(( prior + 1 ))
  if (( prior >= _AID_BO_MAX_ATTEMPTS )); then
    echo "opponent: ${prior} attempts already spent on this run (cap ${_AID_BO_MAX_ATTEMPTS}) — not trying again; this brainstorm is a recorded monologue. To spend more, remove ${dispute} deliberately." >&2
    return 3
  fi

  # No codex is not a monologue any more: a claude agent answers the same brief.
  # The PM is told which provider answered and why, and is never asked to choose.
  local probe; probe="$(aid_codex_probe)"
  if [[ "$(jq -r '.available' <<< "$probe")" != true ]]; then
    local why; why="$(jq -r '.reason' <<< "$probe")"
    _aid_bo_prompt "$brief" > "${out_dir}/opponent-prompt.txt" \
      || { echo "opponent: cannot write ${out_dir}/opponent-prompt.txt" >&2; return 1; }
    jq -n --arg r "$why" --arg m "${AID_BO_STAND_IN_MODEL:-opus}" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{stand_in: "claude", reason: $r, model: $m, asked_at: $at}' > "$standin" \
      || { echo "opponent: cannot write ${standin}" >&2; return 1; }
    echo "STAND-IN: codex is unavailable (${why}); dispatch ${out_dir}/opponent-prompt.txt to a general-purpose agent (model ${AID_BO_STAND_IN_MODEL:-opus}) and pass its answer back with --answer <file>" >&2
    return 4
  fi

  local root; root="$(aid_state_root)" || root="$PWD"
  local tmp; tmp="$(mktemp -d)" || { echo "opponent: no temp dir" >&2; return 1; }
  _aid_bo_prompt "$brief" > "${tmp}/prompt.txt"

  local drc=0
  _run_codex_isolated "$root" "${tmp}/prompt.txt" \
    "${tmp}/events.jsonl" "${tmp}/stderr.txt" "${tmp}/answer.txt" || drc=$?

  if [[ "$drc" -ne 0 || ! -s "${tmp}/answer.txt" ]]; then
    _aid_bo_write_unreached "$dispute" "$plan_id" "the opponent did not answer (exit ${drc})" "$attempt" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    _aid_bo_monologue "$attempt" "the opponent did not answer (exit ${drc})"
    return 3
  fi

  # A fenced answer is still an answer; anything that is not one object is not.
  sed -e 's/^```json$//' -e 's/^```$//' "${tmp}/answer.txt" > "${tmp}/answer.json"
  if ! _aid_bo_valid "${tmp}/answer.json"; then
    _aid_bo_write_unreached "$dispute" "$plan_id" "the opponent answered outside the required shape — an answer that cannot be read is not agreement" "$attempt" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    _aid_bo_monologue "$attempt" "the opponent answered outside the required shape"
    return 3
  fi

  jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg p "$plan_id" \
     --arg m "${CODEX_MODEL:-unknown}" --argjson cap "$_AID_BO_MAX_TO_PM" \
     '{opponent: "answered", plan_id: $p, model: $m, provider: "codex", created_at: $at,
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
