#!/usr/bin/env bash
# =============================================================================
# lib/aid-decision-card.sh — the card that asks the PM for a decision, built
# rather than written (P086 Step 3)
#
#   aid_decision_card_render   <data.json|-> [out_file]
#   aid_decision_card_validate <card_file>
#
# WHY THIS EXISTS
#   Card 2 in skills/communication.md has been a skeleton to imitate: a turn
#   that asked the PM for a decision with no options and no recommendation
#   broke a MUST rule and nothing happened, because nothing was checking. The
#   card is now ASSEMBLED FROM DATA — a caller with no options list cannot
#   produce one, which is a stronger thing than a caller being told to include
#   options.
#
# THE DIVISION OF LABOUR, WHICH IS THE SAME ONE lib/aid-plan-summary.sh DRAWS
#   The STRUCTURE is the code's: which lines exist, in what order, how many
#   options, what is mandatory. The PROSE is the model's: the question, the
#   consequence, each option's text, the reason, the risk. Nothing here writes
#   a sentence, and nothing here rewrites one.
#
#   The LABELS are neither — they are per-language data in
#   defaults/decision-card-labels.yaml, because the card renders in the PM's
#   language and a renderer with Czech baked into it could not be reused.
#
# WHAT IT REFUSES, AND WHY THAT IS THE POINT
#   No question, no options, fewer than two options, no recommended option, a
#   recommendation without a reason, an unknown language: each is a refusal
#   naming the missing field. A card that asks "what do you want to do?" with
#   nothing to choose from is not a shorter card, it is a different and worse
#   act — it hands the work back.
#
#   MORE than five options is capped, not refused, and the card says how many
#   were dropped: a caller with eleven options has a problem the PM should see,
#   not a turn to lose.
#
# VALIDATION IS OF THE RENDERED CARD, not of the data — that is what
# scripts/aid-turn-gate.sh has after the fact, and what the Stop hook rule can
# read out of a transcript. A file matching no language's labels is NOT a
# decision card and validates as "not applicable": the gate must never invent a
# decision where a turn simply reported something.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-24
# =============================================================================
[[ -n "${_AID_DECISION_CARD_SH_LOADED:-}" ]] && return 0
_AID_DECISION_CARD_SH_LOADED=1

_AID_DC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AID_DC_LABELS_DEFAULT="${_AID_DC_LIB_DIR}/../../defaults/decision-card-labels.yaml"

# The most options a card may show. Beyond this the PM is not choosing, they
# are reading a list.
_AID_DC_MAX_OPTIONS=5

_aid_dc_labels_file() {
  printf '%s' "${AID_DECISION_CARD_LABELS:-$_AID_DC_LABELS_DEFAULT}"
}

# _aid_dc_label <lang> <key> — one label, or empty when the language is absent.
_aid_dc_label() {
  yq -r ".languages.\"$1\".\"$2\" // \"\"" "$(_aid_dc_labels_file)" 2>/dev/null
}

# aid_decision_card_render <data.json|-> [out_file]
#
# Prints the card on stdout, and writes it to <out_file> as well when given —
# the file is what scripts/aid-turn-gate.sh validates after the CLI returns.
# Returns 0 rendered, 1 the data cannot make a card (reason on stderr).
aid_decision_card_render() {
  local src="${1:?aid_decision_card_render: data file required}" out="${2:-}"
  local data
  if [[ "$src" == "-" ]]; then data="$(cat)"; else
    data="$(cat "$src" 2>/dev/null)" || { echo "decision card: cannot read ${src}" >&2; return 1; }
  fi
  if ! printf '%s' "$data" | jq -e . >/dev/null 2>&1; then
    echo "decision card: the data is not valid JSON" >&2; return 1
  fi

  local lang question why_now risk
  lang="$(printf '%s' "$data" | jq -r '.lang // ""')"
  question="$(printf '%s' "$data" | jq -r '.question // ""')"
  why_now="$(printf '%s' "$data" | jq -r '.why_now // ""')"
  risk="$(printf '%s' "$data" | jq -r '.risk // ""')"

  [[ -n "$lang" ]] || { echo "decision card: no 'lang' — the card renders in the PM's language and the renderer will not guess it" >&2; return 1; }
  local l_question; l_question="$(_aid_dc_label "$lang" question)"
  [[ -n "$l_question" ]] || { echo "decision card: language '${lang}' has no labels in $(_aid_dc_labels_file) — add a block there rather than rendering in another language" >&2; return 1; }
  [[ -n "$question" ]] || { echo "decision card: no 'question' — a decision card without the question is a status line" >&2; return 1; }

  local count recommended
  count="$(printf '%s' "$data" | jq -r '(.options // []) | length')"
  if (( count < 2 )); then
    echo "decision card: 'options' has ${count} entr$( ((count==1)) && echo y || echo ies) — a decision needs at least two, or it is an announcement" >&2
    return 1
  fi
  recommended="$(printf '%s' "$data" | jq -r '[(.options // [])[] | select(.recommended == true)] | length')"
  if (( recommended != 1 )); then
    echo "decision card: exactly one option must carry \"recommended\": true (found ${recommended}) — a card that recommends nothing hands the work back, and one that recommends everything says nothing" >&2
    return 1
  fi
  local reason; reason="$(printf '%s' "$data" | jq -r '[(.options // [])[] | select(.recommended == true)] | .[0].reason // ""')"
  [[ -n "$reason" ]] || { echo "decision card: the recommended option has no 'reason' — a recommendation the PM cannot check is an instruction" >&2; return 1; }

  # Options in declared order, capped. The recommended one is named on its own
  # line; the rest are the alternatives.
  local shown=$(( count > _AID_DC_MAX_OPTIONS ? _AID_DC_MAX_OPTIONS : count ))
  local dropped=$(( count - shown ))
  local rec_line alt_line
  rec_line="$(printf '%s' "$data" | jq -r --argjson n "$shown" \
    '[(.options // [])[:$n][] | select(.recommended == true)] | .[0] | "\(.key // "A") — \(.text // "")"')"
  alt_line="$(printf '%s' "$data" | jq -r --argjson n "$shown" \
    '[(.options // [])[:$n][] | select(.recommended != true) | "\(.key // "?") — \(.text // "")"] | join("; ")')"

  # A cap that hid the recommended option would render a card recommending
  # nothing — refuse rather than mislead.
  [[ -n "$rec_line" && "$rec_line" != "null"* ]] || {
    echo "decision card: the recommended option is beyond the first ${_AID_DC_MAX_OPTIONS} — put it in the first ${_AID_DC_MAX_OPTIONS}" >&2; return 1; }

  local card
  card="$(printf '%s: %s\n' "$l_question" "$question")"
  [[ -n "$why_now" ]] && card+="$(printf '\n%s: %s' "$(_aid_dc_label "$lang" why_now)" "$why_now")"
  card+="$(printf '\n%s: %s' "$(_aid_dc_label "$lang" recommendation)" "$rec_line")"
  card+="$(printf '\n%s: %s' "$(_aid_dc_label "$lang" reason)" "$reason")"
  card+="$(printf '\n%s: %s' "$(_aid_dc_label "$lang" alternatives)" "$alt_line")"
  (( dropped > 0 )) && card+="$(printf ' (+%d)' "$dropped")"
  [[ -n "$risk" ]] && card+="$(printf '\n%s: %s' "$(_aid_dc_label "$lang" risk)" "$risk")"

  printf '%s\n' "$card"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$card" > "$out" || { echo "decision card: cannot write ${out}" >&2; return 1; }
  fi
  return 0
}

# aid_decision_card_validate <card_file>
#
# Returns 0 a complete card, 1 a card missing mandatory lines (each named on
# stderr), 3 not a decision card at all (no language's labels match).
aid_decision_card_validate() {
  local file="${1:?aid_decision_card_validate: card file required}"
  [[ -r "$file" ]] || { echo "decision card: cannot read ${file}" >&2; return 1; }

  local langs lang="" l_question=""
  langs="$(yq -r '.languages | keys | .[]' "$(_aid_dc_labels_file)" 2>/dev/null)"
  local candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    l_question="$(_aid_dc_label "$candidate" question)"
    [[ -n "$l_question" ]] || continue
    if grep -qF "${l_question}:" "$file"; then lang="$candidate"; break; fi
  done <<< "$langs"

  if [[ -z "$lang" ]]; then
    echo "not a decision card: no language's opening line appears in ${file}" >&2
    return 3
  fi

  local missing=() key
  for key in question recommendation reason alternatives; do
    local label; label="$(_aid_dc_label "$lang" "$key")"
    grep -qF "${label}:" "$file" || missing+=("$key (\"${label}:\")")
  done
  # An alternatives line that is present but empty is the same defect as a
  # missing one — it is the options list, and an empty list is no choice.
  if grep -qF "$(_aid_dc_label "$lang" alternatives):" "$file" \
     && ! grep -qE "$(_aid_dc_label "$lang" alternatives): *[^ ]" "$file"; then
    missing+=("alternatives (the line is there but lists nothing)")
  fi

  if (( ${#missing[@]} > 0 )); then
    printf 'decision card %s is incomplete — missing: %s\n' "$file" "$(IFS='; '; echo "${missing[*]}")" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# aid_hook_rule_decision_card — the Stop-event registry handler.
#
# THE SECOND LAYER, NOT THE FIRST. scripts/aid-turn-gate.sh validates the
# written card after the CLI returns and works in every run mode, including the
# ones with no `Stop` event at all and the sessions that are killed. This rule
# catches the same defect EARLIER, while the turn can still be fixed. Where the
# event does not exist, nothing is lost.
#
# It reads the last assistant message out of the session transcript, so it needs
# no cooperation from the turn it is checking. A message that is not a decision
# card at all exits 3 — the rule does not activate, which is the whole of
# "a turn that asks for nothing is not checked".
# ---------------------------------------------------------------------------
aid_hook_rule_decision_card() {
  local input; input="$(cat)"
  local transcript; transcript="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)"
  if [[ -z "$transcript" || ! -r "$transcript" ]]; then
    echo "no readable transcript in the event — nothing to check" >&2
    return 3
  fi

  local last
  last="$(jq -rs '[.[] | select(.type == "assistant")] | last
                  | (.message.content // []) | map(select(.type == "text") | .text) | join("\n")' \
          "$transcript" 2>/dev/null)"
  if [[ -z "$last" || "$last" == "null" ]]; then
    echo "no assistant text in the transcript — nothing to check" >&2
    return 3
  fi

  local tmp; tmp="$(mktemp)" || { echo "no temp file for the card check" >&2; return 3; }
  printf '%s\n' "$last" > "$tmp"
  local err rc=0
  err="$(aid_decision_card_validate "$tmp" 2>&1)" || rc=$?
  rm -f "$tmp"

  case "$rc" in
    0) return 0 ;;
    3) echo "the turn does not ask for a decision" >&2; return 3 ;;
    *) printf '%s\n' "$err" >&2; return 2 ;;
  esac
}
