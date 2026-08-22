#!/usr/bin/env bash
# =============================================================================
# lib/aid-plan-summary.sh — the PM's page about a freshly written plan
# (P084 Step 5).
#
#   aid_plan_summary_render <plan_file> <out_path>
#
# WHY THIS EXISTS
#   A plan is written for the agent that will execute it. The PM needs a
#   different document — short, in human language, with the numbers computed
#   rather than asserted. Until now that document was a `## Stakeholder Brief`
#   SECTION inside the plan, which put two audiences in one file and made the
#   plan longer for the reader who was never going to read it. The section is
#   gone; this renders its replacement from the plan's own data.
#
# WHAT IT IS NOT
#   It does not publish. `aid_artifact_render` writes a BODY and the Artifact
#   tool is a session-level act owned by the controller (commands/aid-plan.md
#   Mode: Write Plan) — the same boundary lib/aid-plan-close-summary.sh draws.
#
#   It is also not a summariser, and here is the exact boundary, because "it
#   invents nothing" would be too strong a claim to make:
#     - every NUMBER is counted from the plan (steps, declared paths, risks,
#       roles) — none is asserted, and none comes from prose;
#     - the summary and core blocks are the plan's own `## Goal` and
#       `## Context`, cut at their first sentence and stripped of markdown
#       emphasis. No sentence is rewritten;
#     - the ask and the three next steps are FIXED LITERALS of this caller,
#       identical on every page it renders. They are the one thing here that
#       the plan did not say.
#
# WHY A THIRD CALLER AND NOT AN EXTENSION OF aid-plan-close-summary.sh
#   That one renders the plan's CLOSE from `release-decision.json` and refuses
#   to render without plan-final facts (:191, :197). Different input, different
#   moment, same renderer underneath.
#
# ERROR HANDLING
#   No `## Goal` with content → refuse, naming the section. A page whose core
#   block is empty is worse than no page: the skeleton's block 2 is mandatory,
#   and an empty mandatory block reads as "there is nothing to say".
#   An unreadable plan → exit 1. An unwritable out_path → the renderer's own
#   exit 3 is returned unchanged.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-22
# =============================================================================
[[ -n "${_AID_PLAN_SUMMARY_SH_LOADED:-}" ]] && return 0
_AID_PLAN_SUMMARY_SH_LOADED=1

_AID_PLAN_SUMMARY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-artifact-render.sh
source "${_AID_PLAN_SUMMARY_LIB_DIR}/aid-artifact-render.sh"
# shellcheck source=aid-plan-band.sh
source "${_AID_PLAN_SUMMARY_LIB_DIR}/aid-plan-band.sh"

# _aps_section <plan> <heading> — the body of one `## <heading>` section, with
# blank lines and sub-headings dropped. Empty when the section is absent.
_aps_section() {
  awk -v want="## $2" '
    $0 == want { inside = 1; next }
    /^#+[[:space:]]/ { inside = 0; next }
    inside && $0 ~ /[^[:space:]]/ { print }
  ' "$1"
}

# _aps_first_sentence <text> — the first sentence, trimmed of markdown emphasis
# so a bolded lead does not reach the page as asterisks. The renderer caps the
# length; this only decides where to stop.
_aps_first_sentence() {
  printf '%s' "$1" \
    | tr '\n' ' ' \
    | sed 's/[*_`]//g; s/^[[:space:]]*//' \
    | sed 's/\([.!?]\)[[:space:]].*/\1/' \
    | sed 's/[[:space:]]*$//'
}

# _aps_norm <text> — a count that is ONE number, whatever the producer did.
# `grep -c` prints 0 and exits 1 on no match, so the obvious
# `grep -c … || printf 0` emits "0\n0" and every later [[ -gt ]] on it is a
# syntax error, not a zero. Every counter below normalises through here, so
# the defence has one definition instead of one per counter.
_aps_norm() {
  local n="${1%%$'\n'*}"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}

# _aps_count <command...> — _aps_norm over a command's output. Counters that
# need a PIPE (not a single command) call _aps_norm directly.
_aps_count() { _aps_norm "$("$@" 2>/dev/null || true)"; }

# The two counts below read the plan with fenced blocks blanked
# (`_aid_blank_fenced`), and accept the same step-header spellings generation
# accepts: a quoted example must not inflate a number on the PM page.
_aps_count_steps() {
  _aps_count_stdin '^###?[[:space:]]+(Step|Task)[[:space:]]+[0-9]+' "$1"
}

# _aps_count_epics <plan> — `**EPIC N: …**` markers (0 is legitimate: a
# single-EPIC plan states no marker).
_aps_count_epics() {
  _aps_count_stdin '^\*\*EPIC[[:space:]]+[0-9]+' "$1"
}

# _aps_count_stdin <ere> <plan> — matches in the plan with fenced blocks blanked.
_aps_count_stdin() {
  local n
  n="$(_aid_blank_fenced < "$2" | grep -cE "$1")" || n=0
  printf '%s' "${n:-0}"
}

# _aps_declared_paths <plan> — the same declared paths the band is classified
# from, de-duplicated. One authority for "what does this plan touch".
_aps_declared_paths() {
  _aps_norm "$(_aid_band_declared_paths "$1" | sort -u | grep -c . || true)"
}

# _aps_count_risks <plan> — data rows of the `## Risks` table (the header and
# its separator are not risks). The `|| true` is load-bearing under
# `set -o pipefail` (this library is sourced under the caller's strict shell):
# `grep -c` exits 1 when it counts zero, which would abort a caller rendering a
# plan that names no risks — a legitimate plan.
_aps_count_risks() {
  local rows
  rows="$(_aps_norm "$(_aps_section "$1" "Risks" | { grep -cE '^\|' || true; })")"
  # Minus the header row and its separator, which are not risks.
  (( rows > 2 )) && printf '%s' "$(( rows - 2 ))" || printf '0'
}

# _aps_roles <plan> — the distinct AID roles the plan dispatches to.
# Same pipefail care as above: a plan with no **AID Role:** line is renderable,
# and `grep .` finding nothing must not become the caller's exit status.
_aps_roles() {
  sed -n 's/^\*\*AID Role:\*\*[[:space:]]*\([a-z-]*\).*/\1/p' "$1" 2>/dev/null \
    | { grep . || true; } | sort -u | paste -sd, - | sed 's/,/, /g'
}

aid_plan_summary_render() {
  local plan="${1-}" out_path="${2-}"
  if [[ -z "$plan" || -z "$out_path" ]]; then
    echo "aid_plan_summary_render: usage: aid_plan_summary_render <plan_file> <out_path>" >&2
    return 1
  fi
  if [[ ! -f "$plan" ]]; then
    echo "aid_plan_summary_render: plan not found: ${plan}" >&2
    return 1
  fi

  local goal
  goal="$(_aps_section "$plan" "Goal")"
  if [[ -z "${goal//[[:space:]]/}" ]]; then
    echo "aid_plan_summary_render: the plan has no '## Goal' with content — refusing to render a page whose core block would be empty (${plan})" >&2
    return 1
  fi

  local plan_id status band_line band band_reason
  plan_id="$(_aid_fm_get "$plan" id)"; plan_id="${plan_id:-?}"
  status="$(_aid_fm_get "$plan" status)"; status="${status:-draft}"
  band_line="$(aid_plan_band "$plan")" || band_line=""
  band="${band_line%%$'\t'*}"; band="${band:-full}"
  band_reason="${band_line#*$'\t'}"

  local steps epics files risks roles context
  steps="$(_aps_count_steps "$plan")"
  epics="$(_aps_count_epics "$plan")"
  files="$(_aps_declared_paths "$plan")"
  risks="$(_aps_count_risks "$plan")"
  roles="$(_aps_roles "$plan")"; roles="${roles:-—}"
  context="$(_aps_section "$plan" "Context")"

  # Band decides the ceremony, so it is the headline fact, not a footnote.
  local band_value band_state
  case "$band" in
    full)   band_value="Plná ceremonie";   band_state="warn" ;;
    medium) band_value="Střední ceremonie"; band_state="ok" ;;
    *)      band_value="Lehká ceremonie";  band_state="ok" ;;
  esac

  local scope_label items_json next_json links_json facts_json prose_json
  scope_label="$( [[ "$epics" -gt 0 ]] && printf '%s kroků / %s EPIKŮ' "$steps" "$epics" || printf '%s kroků' "$steps" )"

  items_json="$(jq -n \
    --arg band "$band" --arg reason "$band_reason" \
    --arg steps "$steps" --arg files "$files" \
    --arg risks "$risks" --arg roles "$roles" --arg status "$status" '[
      "Pásmo ceremonie: " + $band + " (" + $reason + ")",
      "Rozsah: " + $steps + " kroků, " + $files + " deklarovaných souborů",
      "Rizika pojmenovaná v plánu: " + $risks,
      "Role, kterým se bude zadávat: " + $roles,
      "Stav plánu: " + $status
    ]')" || return 1

  next_json="$(jq -n '[
      "Přečíst plán a říct, co v něm chybí",
      "Nechat ho projít revizí podle pásma",
      "Pustit generaci EPIKŮ"
    ]')"

  links_json="$(jq -n --arg p "$plan" '["Plán: " + $p]')"

  facts_json="$(jq -n \
    --arg plan_id "$plan_id" \
    --arg when "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg bv "$band_value" --arg bs "$band_state" \
    --arg steps "$steps" --arg scope "$scope_label" \
    --arg risks "$risks" \
    --arg rs "$( [[ "$risks" -gt 0 ]] && echo warn || echo ok )" \
    --argjson items "$items_json" \
    --argjson next "$next_json" \
    --argjson links "$links_json" \
    --arg p "$plan" '{
      eyebrow: "Nový plán",
      title: ("Plán " + $plan_id),
      when: $when,
      tiles: {
        result:     {value: $bv, state: $bs},
        duration:   {label: "Kroků", value: $steps},
        scope:      {label: "Rozsah", value: $scope, state: "ok"},
        unresolved: {label: "Rizik", value: $risks, state: $rs}
      },
      items: $items,
      next_steps: $next,
      links: $links,
      detail: {label: ("Technický detail: " + $p)},
      footer: ("Vyrobil aid-plan-summary.sh z " + $p + ". Čísla jsou spočítaná z plánu, ne opsaná.")
    }')" || {
    echo "aid_plan_summary_render: failed to build facts" >&2
    return 1
  }

  prose_json="$(jq -n \
    --arg s "$(_aps_first_sentence "$goal")" \
    --arg c "$(_aps_first_sentence "${context:-$goal}")" \
    '{summary: $s, core: $c, ask: "Přečti plán a řekni, co v něm chybí. Do té doby nic negeneruju."}')"

  mkdir -p "$(dirname "$out_path")" 2>/dev/null
  aid_artifact_render outcome "$facts_json" "$prose_json" "$out_path"
}
