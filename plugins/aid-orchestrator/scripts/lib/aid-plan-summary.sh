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
  # The heading rule lives in lib/aid-scoping.sh, once, for every reader of the
  # plan format; what is local here is that the PAGE wants prose — sub-headings
  # and blank lines are not sentences to render.
  # Stops at ANY heading, not just the next `## `: a `###` subsection is a
  # different topic, and its prose rendered as part of the parent section is how
  # a page starts saying something the plan did not.
  _aid_plan_section "$1" "$2" | awk '/^#/ { exit } /[^[:space:]]/'
}

# _aps_first_sentence / _aps_norm — thin names over the renderer's shared
# helpers (lib/aid-artifact-render.sh). The definitions moved there when a
# second summary caller needed the same two, because two copies of "where does
# a sentence end" is how two PM pages start cutting text differently.
_aps_first_sentence() { aid_artifact_first_sentence "$1"; }

# Every counter below normalises through _aps_norm, so the defence has one
# definition instead of one per counter.
_aps_norm() { aid_artifact_number "$1"; }

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

# _aps_standards <plan> — the standards the plan NAMES in its `## Standards`
# section, as a comma list of ids. Read out of the plan, not derived from the
# map: this file counts what the plan says, and "which standards SHOULD have
# been named" is the lint's judgement, not the PM page's (P085 Step 8).
# Empty when the section is absent — a project without a standards map has no
# such section, and an empty line on the page would read as a missing answer.
_aps_standards() {
  # Every stage that can legitimately match NOTHING is neutralised: this
  # library is sourced under the caller's `set -o pipefail`, where a `grep`
  # exiting 1 on zero matches aborts the render of a perfectly good plan —
  # the same trap _aps_count_risks and _aps_roles document above.
  _aps_section "$1" "Standards" \
    | { grep -oE '/ecosystem/specs/[A-Za-z0-9_-]+' || true; } \
    | sed 's#.*/##' | { grep . || true; } | sort -u | paste -sd, - | sed 's/,/, /g'
}

# _aps_reuse <plan> — "<evidenced>/<founding>": of the STEPS that found
# something new, how many carry a **Reuse check:** field. Per step, not per
# bullet: a step with three `Create:` bullets owes one field, and counting
# bullets against fields produced a ratio that could exceed 1.
# Rendered only when the plan founds anything at all.
_aps_reuse() {
  local plan="$1" founding=0 evidenced=0 s e _head
  while IFS=$'\t' read -r s e _head; do
    [[ -n "${s:-}" ]] || continue
    founding=$((founding+1))
    _aid_plan_step_field "$plan" "$s" "$e" "Reuse check" >/dev/null && evidenced=$((evidenced+1))
  done < <(_aid_plan_founding_steps "$plan")
  printf '%s/%s' "$evidenced" "$founding"
}

# aid_plan_summary_renderable <plan> — 0 when this plan CAN have a page, 1 when
# it cannot. Exposed because a second caller needs the same answer: the Stop
# rule that demands a page (lib/aid-artifact-obligation.sh) must not demand one
# for a plan this renderer refuses.
#
# Found live 2026-08-24: the hook demanded a page for a plan with no `## Goal`,
# the renderer refused to produce it, and the two mechanisms left a finding
# nobody could act on. An enforcement must not require the impossible — and the
# way to avoid it is to ASK the authority, not to keep a second copy of its
# rule in the rule that depends on it.
aid_plan_summary_renderable() {
  local plan="${1-}"
  [[ -f "$plan" ]] || return 1
  local goal; goal="$(_aps_section "$plan" "Goal")"
  [[ -n "${goal//[[:space:]]/}" ]]
}

# _aps_deliverables <plan> — one line per step, grouped by EPIC, as JSON.
#
# THIS IS THE BLOCK THE PM ASKED FOR (2026-08-25): "it mainly has to list, in
# human language, in bullets, in detail, what the plan delivers — per EPIC, per
# step." The page before this carried a fact list and a truncated paragraph of
# the plan's Context; nothing on it said what the plan would actually do.
#
# The line per step is its **Objective**, verbatim-ish. That is not a paraphrase
# of intent: `skills/plan-writing.md:282` defines the field as "What this step
# produces or changes — one sentence", so it is the deliverable, written by the
# author, in the author's words. A cross-provider review read it as mere intent;
# the contract says otherwise, and the alternative — deriving a deliverable from
# the Files list — would put paths on a page whose whole point is plain language.
#
# Every step is listed. NO cap and no "and N more": a 10-step plan whose tail is
# collapsed hides exactly the part the PM opened the page to judge. The count of
# acceptance criteria rides along on each line, because "what it delivers" and
# "how I will know it is done" are one question asked twice.
_aps_deliverables() {
  local plan="${1-}" line epic_title="" out="[]" n obj acs
  [[ -f "$plan" ]] || { printf '[]'; return 0; }
  # One pass: EPIC markers open a group, step headers add a row to it.
  local cur_epic=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^\*\*EPIC[[:space:]]+([0-9]+)(.*)\*\*[[:space:]]*$ ]]; then
      # The marker is `**EPIC N: Steps A-B — Title**`; the step range is a
      # generation detail and never reaches the page. Stripping it with a
      # bracket set would eat the "1-4" hyphen and leave "4 — Title" behind,
      # which is what the first render did.
      epic_title="${BASH_REMATCH[2]}"
      epic_title="${epic_title#:}"
      epic_title="$(printf '%s' "$epic_title" | sed -E 's/^[[:space:]]*Steps[[:space:]]+[0-9]+-[0-9]+[[:space:]]*//; s/^[[:space:]]*(—|–|-)[[:space:]]*//; s/[[:space:]]*$//')"
      cur_epic="EPIC ${BASH_REMATCH[1]}"
      [[ -n "$epic_title" ]] && cur_epic="$cur_epic — $epic_title"
      out="$(jq -c --arg e "$cur_epic" '. + [{epic: $e, steps: []}]' <<<"$out")"
    elif [[ "$line" =~ ^###[[:space:]]+Step[[:space:]]+([0-9]+):[[:space:]]*(.*)$ ]]; then
      n="${BASH_REMATCH[1]}"
      obj="$(_aps_step_objective "$plan" "$n")"
      acs="$(_aps_step_acs "$plan" "$n")"
      [[ -n "$obj" ]] || obj="${BASH_REMATCH[2]}"
      # A plan with no EPIC markers still lists its steps: open an implicit group.
      if [[ "$out" == "[]" ]]; then
        out="$(jq -c '. + [{epic: "Kroky", steps: []}]' <<<"$out")"
      fi
      out="$(jq -c --arg n "$n" --arg o "$obj" --arg a "$acs" \
        '(.[-1].steps) += [{n: $n, text: $o, acs: $a}]' <<<"$out")"
    fi
  done < "$plan"
  printf '%s' "$out"
}

# _aps_step_objective <plan> <n> — the Objective line of step <n>, unmarked.
_aps_step_objective() {
  awk -v want="$2" '
    $0 ~ "^### Step " want ":" { inside = 1; next }
    inside && /^### Step /     { exit }
    inside && /^\*\*Objective:\*\*/ {
      sub(/^\*\*Objective:\*\*[[:space:]]*/, ""); print; exit
    }
  ' "$1" 2>/dev/null | head -1
}

# _aps_step_acs <plan> <n> — how many acceptance criteria step <n> declares.
_aps_step_acs() {
  awk -v want="$2" '
    $0 ~ "^### Step " want ":" { inside = 1; next }
    inside && /^### Step /     { exit }
    inside && /^- \[ \] /     { c++ }
    END { print c + 0 }
  ' "$1" 2>/dev/null
}

# _aps_plan_name <plan> <plan_id> — the plan's own title, for use as a NAME.
_aps_plan_name() {
  local t
  t="$(awk '/^# /{ sub(/^# /, ""); print; exit }' "$1" 2>/dev/null)"
  printf '%s' "${t:-$2}"
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

  if ! aid_plan_summary_renderable "$plan"; then
    echo "aid_plan_summary_render: the plan has no '## Goal' with content — refusing to render a page whose core block would be empty (${plan})" >&2
    return 1
  fi
  local goal; goal="$(_aps_section "$plan" "Goal")"

  local plan_id status band_line band band_reason
  plan_id="$(_aid_fm_get "$plan" id)"; plan_id="${plan_id:-?}"
  status="$(_aid_fm_get "$plan" status)"; status="${status:-draft}"
  band_line="$(aid_plan_band "$plan")" || band_line=""
  band="${band_line%%$'\t'*}"; band="${band:-full}"
  band_reason="${band_line#*$'\t'}"

  local steps epics files risks roles context standards reuse
  steps="$(_aps_count_steps "$plan")"
  epics="$(_aps_count_epics "$plan")"
  files="$(_aps_declared_paths "$plan")"
  risks="$(_aps_count_risks "$plan")"
  roles="$(_aps_roles "$plan")"; roles="${roles:-—}"
  # An AID Role outside the valid set is not a role, it is a defect that stops
  # EPIC generation later (P087, 2026-08-25: `docs` instead of `docs-writer`
  # refused generation after both EPICs had been built). The page said the role
  # as if it were fine; it now says what it is and what it will cost.
  local bad_roles=""
  bad_roles="$(printf '%s' "$roles" | tr ',' '\n' | sed 's/^ *//;s/ *$//' \
    | grep -vxE 'architect|domain|backend|frontend|qa|security|observability|docs-writer|release|e2e|—' \
    | paste -sd', ' - 2>/dev/null || true)"
  context="$(_aps_section "$plan" "Context")"
  standards="$(_aps_standards "$plan")" || standards=""
  reuse="$(_aps_reuse "$plan")" || reuse="0/0"

  # Band decides the ceremony, so it is the headline fact, not a footnote.
  local band_value band_state
  case "$band" in
    full)   band_value="Plná ceremonie";   band_state="warn" ;;
    medium) band_value="Střední ceremonie"; band_state="ok" ;;
    *)      band_value="Lehká ceremonie";  band_state="ok" ;;
  esac

  local scope_label items_json next_json links_json facts_json prose_json
  scope_label="$( [[ "$epics" -gt 0 ]] && printf '%s kroků / %s EPIKŮ' "$steps" "$epics" || printf '%s kroků' "$steps" )"

  # The two P085 rows are CONDITIONAL: a project with no standards map has no
  # `## Standards` section, and a plan that founds nothing has no reuse search.
  # An empty row would read as an unanswered question rather than an absent one.
  # ORDER IS THE BUDGET. The renderer caps the list at five items and says how
  # many it dropped; appending the two P085 rows at the END would have meant a
  # plan that names standards never showing them. They go above `roles` and
  # `status`, which are the two a PM can reconstruct from the plan in seconds.
  # Raising the cap was the alternative and is not ours to take — it is the
  # artifact standard's ceiling, and a page nobody finishes reading is the
  # thing it exists to prevent.
  items_json="$(jq -n \
    --arg band "$band" --arg reason "$band_reason" \
    --arg steps "$steps" --arg files "$files" \
    --arg risks "$risks" --arg roles "$roles" --arg status "$status" \
    --arg standards "$standards" --arg reuse "$reuse" --arg bad "$bad_roles" '[
      "Pásmo ceremonie: " + $band + " (" + $reason + ")",
      "Rozsah: " + $steps + " kroků, " + $files + " deklarovaných souborů",
      "Rizika pojmenovaná v plánu: " + $risks
    ]
    + (if $standards == "" then [] else ["Standardy, na které se plán odvolává: " + $standards] end)
    + (if ($reuse | endswith("/0")) then [] else ["Kroky, které něco zakládají, s doloženým hledáním: " + $reuse] end)
    + (if $bad == "" then [] else ["VADA: role \"" + $bad + "\" v AID neexistuje — generace EPIKŮ ji odmítne, dokud se neopraví"] end)
    + [
      "Role, kterým se bude zadávat: " + $roles,
      "Stav plánu: " + $status
    ]')" || return 1

  next_json="$(jq -n '[
      "Přečíst plán a říct, co v něm chybí",
      "Nechat ho projít revizí podle pásma",
      "Pustit generaci EPIKŮ"
    ]')"

  # NAMES, never paths — the ecosystem standard says so for blocks 5 and 7, and
  # a path is not something a reader of a published page can act on. The path
  # itself survives in the provenance footer, which already names the source.
  local plan_name
  plan_name="$(_aps_plan_name "$plan" "$plan_id")"
  links_json="$(jq -n --arg n "$plan_name" '["Plán " + $n]')"

  facts_json="$(jq -n \
    --arg plan_id "$plan_id" \
    --arg when "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg bv "$band_value" --arg bs "$band_state" \
    --arg steps "$steps" --arg scope "$scope_label" --arg files "$files" \
    --argjson deliverables "$(_aps_deliverables "$plan")" \
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
        result:     {value: $bv, state: $bs, label: "Pásmo"},
        duration:   {label: "Kroků", value: $steps},
        scope:      {label: "Souborů", value: $files, state: "ok"},
        unresolved: {label: "Rizik", value: $risks, state: $rs}
      },
      items: $items,
      deliverables: $deliverables,
      next_steps: $next,
      links: $links,
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
