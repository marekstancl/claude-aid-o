#!/usr/bin/env bash
# =============================================================================
# lib/aid-brainstorm-summary.sh — the PM's page about a brainstorm
# (P086 Step 9)
#
#   aid_brainstorm_summary_render <plan_id> <out_path>
#
# WHY A FOURTH CALLER OF THE SAME RENDERER
#   lib/aid-artifact-render.sh writes the body and enforces the ceilings;
#   lib/aid-plan-summary.sh renders a written PLAN, lib/aid-plan-close-summary.sh
#   a plan's CLOSE, lib/aid-gate-outcome-summary.sh a gate run. The input here is
#   different from all three — a topic, a vision, and what two models agreed and
#   disputed — so it is a caller, not a flag on one of them.
#
# THE SAME DIVISION OF LABOUR P084 SETTLED
#   Every NUMBER is counted from the run's own files: how many points the vision
#   has, how many conclusions the two models shared, how many they disputed, how
#   many were held back from the PM. The two prose blocks are the topic and the
#   vision's first thesis, cut at their first sentence. Nothing here writes a
#   sentence and nothing rewrites one.
#
# ABSENCE IS NAMED, NEVER RENDERED AS AN EMPTY BLOCK
#   A run with no approved vision says so on the page. A run with no disputes
#   has no dispute line at all — a "Disputes: 0" row and a missing vision are
#   different facts, and an empty row reads as an unanswered question rather
#   than an absent one.
#
# IT DOES NOT PUBLISH — the Artifact tool is a session-level act owned by the
# controller, the same boundary every other caller of this renderer draws.
#
# WHERE IT WILL WRITE, AND WHY THAT IS PART OF THE MECHANISM
#   Before the PM accepts the run, the page may only be written INSIDE the run's
#   own working directory. Without that, "artifacts leave the working directory
#   only once the PM accepts" was a sentence in scripts/aid-brainstorm-state.sh
#   that this renderer could walk straight past by being handed
#   `docs/brainstorm.html` — a page of an unaccepted run sitting in versioned
#   documentation, which is exactly what consensus K3 forbids. After acceptance
#   the caller may write it anywhere.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-24
# =============================================================================
[[ -n "${_AID_BRAINSTORM_SUMMARY_SH_LOADED:-}" ]] && return 0
_AID_BRAINSTORM_SUMMARY_SH_LOADED=1

_AID_BS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-artifact-render.sh
source "${_AID_BS_LIB_DIR}/aid-artifact-render.sh"
# shellcheck source=aid-roots.sh
source "${_AID_BS_LIB_DIR}/aid-roots.sh"

# Both helpers below are the renderer's, not this caller's: two copies of
# "where does a sentence end" is how two PM pages start cutting text
# differently. See lib/aid-artifact-render.sh.
_abs_first_sentence() { aid_artifact_first_sentence "${1-}"; }
_abs_num() { aid_artifact_number "${1-}"; }

aid_brainstorm_summary_render() {
  local plan_id="${1-}" out_path="${2-}"
  if [[ -z "$plan_id" || -z "$out_path" ]]; then
    echo "aid_brainstorm_summary_render: usage: aid_brainstorm_summary_render <plan_id> <out_path>" >&2
    return 1
  fi

  local root dir state
  root="$(aid_state_root)" || return 1
  dir="${root}/.aid-o/work/brainstorm/${plan_id}"
  state="${dir}/state.yaml"
  if [[ ! -r "$state" ]]; then
    echo "aid_brainstorm_summary_render: no brainstorming run for ${plan_id} (${state}) — there is nothing to render a page from" >&2
    return 1
  fi

  local topic scope vision_state vision_file run_state
  topic="$(yq -r '.topic // ""' "$state" 2>/dev/null)"
  scope="$(yq -r '.scope // ""' "$state" 2>/dev/null)"
  vision_state="$(yq -r '.vision_state // "none"' "$state" 2>/dev/null)"
  vision_file="$(yq -r '.vision_file // ""' "$state" 2>/dev/null)"
  run_state="$(yq -r '.run_state // "open"' "$state" 2>/dev/null)"
  [[ -n "$topic" ]] || topic="$plan_id"

  local vision_points=0 vision_first=""
  if [[ -n "$vision_file" && -r "$vision_file" ]]; then
    vision_points="$(_abs_num "$(grep -cE '^[[:space:]]*-[[:space:]]*V[0-9]+[[:space:]]*:' "$vision_file" 2>/dev/null || true)")"
    vision_first="$(sed -n 's/^[[:space:]]*-[[:space:]]*V[0-9]\+[[:space:]]*:[[:space:]]*//p' "$vision_file" 2>/dev/null | head -1)"
  fi

  local dispute="${dir}/dispute.json" opponent="not_run" agreed=0 disputed=0 held=0
  if [[ -r "$dispute" ]]; then
    opponent="$(jq -r '.opponent // "not_run"' "$dispute" 2>/dev/null)"
    agreed="$(_abs_num "$(jq -r '(.agree // []) | length' "$dispute" 2>/dev/null)")"
    disputed="$(_abs_num "$(jq -r '(.disagree // []) | length' "$dispute" 2>/dev/null)")"
    held="$(_abs_num "$(jq -r '.held_back // 0' "$dispute" 2>/dev/null)")"
  fi

  local result_value result_state
  case "$run_state" in
    approved) result_value="Odsouhlaseno";  result_state="ok" ;;
    *)        result_value="Nedokončeno";   result_state="warn" ;;
  esac

  local vision_line
  case "$vision_state" in
    approved) vision_line="Vize: schválená, ${vision_points} bodů" ;;
    proposed) vision_line="Vize: navržená, čeká na tvoje slovo (${vision_points} bodů)" ;;
    rejected) vision_line="Vize: zamítnutá — brainstorming se vrátil k podnětům" ;;
    *)        vision_line="$( [[ "$scope" == "single_plan" ]] \
                 && printf 'Vize: nevyžaduje se — jeden krátký plán' \
                 || printf 'Vize: zatím žádná — bez ní se nepokračuje k návrhu' )" ;;
  esac

  local opponent_line
  case "$opponent" in
    answered) opponent_line="Oponent: odpověděl, ${agreed} shod" ;;
    unreached) opponent_line="Oponent: nedostupný — návrh vznikl monologem" ;;
    *)        opponent_line="Oponent: zatím neběžel" ;;
  esac

  local items_json next_json links_json facts_json prose_json
  # The dispute row is CONDITIONAL: "0 sporů" and "no opponent ran" are
  # different facts, and a zero row would answer a question nobody asked.
  items_json="$(jq -n \
    --arg vision "$vision_line" --arg opp "$opponent_line" \
    --arg scope "$scope" --arg disputed "$disputed" --arg held "$held" '[
      $vision,
      $opp,
      "Rozsah: " + $scope
    ]
    + (if ($disputed | tonumber) > 0
       then ["Sporů k rozhodnutí: " + $disputed
             + (if ($held | tonumber) > 0 then " (" + $held + " mimo tuto stránku)" else "" end)]
       else [] end)')" || return 1

  next_json="$(jq -n --arg disputed "$disputed" '
    (if ($disputed | tonumber) > 0 then ["Rozhodnout spory, které ti předložím"] else [] end)
    + ["Odsouhlasit brainstorming (aid-brainstorm-state.sh approve)",
       "Nechat z něj napsat plán"]')"

  # NAMES, never paths (blocks 5 and 7). The working directory is in the
  # provenance footer, which already names it.
  links_json="$(jq -n '["Pracovní artefakty brainstormingu"]')"

  facts_json="$(jq -n \
    --arg plan_id "$plan_id" \
    --arg when "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg rv "$result_value" --arg rs "$result_state" \
    --arg agreed "$agreed" --arg disputed "$disputed" \
    --arg ds "$( (( disputed > 0 )) && echo warn || echo ok )" \
    --arg topic "$topic" \
    --argjson items "$items_json" --argjson next "$next_json" --argjson links "$links_json" \
    --arg dir "$dir" '{
      artifact_type: "brainstorming",
      eyebrow: "Brainstorming",
      title: ("Brainstorming " + $plan_id),
      when: $when,
      tiles: {
        result:     {value: $rv, state: $rs},
        duration:   {label: "Shod", value: $agreed},
        scope:      {label: "Téma", value: $topic, state: "ok"},
        unresolved: {label: "Sporů", value: $disputed, state: $ds}
      },
      items: $items,
      next_steps: $next,
      links: $links,
      detail: {label: "Technický detail brainstormingu"},
      footer: ("Vyrobil aid-brainstorm-summary.sh z " + $dir + ". Čísla jsou spočítaná z běhu, ne opsaná.")
    }')" || {
    echo "aid_brainstorm_summary_render: failed to build facts" >&2
    return 1
  }

  prose_json="$(jq -n \
    --arg s "$(_abs_first_sentence "$topic")" \
    --arg c "$(_abs_first_sentence "${vision_first:-$topic}")" \
    --arg a "$( (( disputed > 0 )) \
        && printf 'Rozhodni spory níž. Bez nich brainstorming neuzavřu.' \
        || printf 'Přečti stránku a řekni, jestli to takhle uzavřít.' )" \
    '{summary: $s, core: $c, ask: $a}')"

  # The promotion rule, enforced where the writing happens.
  if [[ "$run_state" != "approved" ]]; then
    local out_abs dir_abs
    out_abs="$(cd "$(dirname "$out_path")" 2>/dev/null && pwd -P)/$(basename "$out_path")" \
      || out_abs="$out_path"
    dir_abs="$(cd "$dir" 2>/dev/null && pwd -P)" || dir_abs="$dir"
    if [[ "$out_abs" != "${dir_abs}/"* ]]; then
      echo "aid_brainstorm_summary_render: ${plan_id} has not been accepted by the PM (run_state=${run_state}), so its page may only be written inside ${dir} — refusing ${out_path}. An unaccepted run's page outside the working directory reads as an agreed outcome." >&2
      return 1
    fi
  fi

  mkdir -p "$(dirname "$out_path")" 2>/dev/null
  aid_artifact_render outcome "$facts_json" "$prose_json" "$out_path"
}
