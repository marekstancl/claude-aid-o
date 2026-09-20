#!/usr/bin/env bash
# =============================================================================
# lib/aid-epic-summary-page.sh — the PM's page about a FINISHED EPIC
# (P089 Step 4)
#
#   aid_epic_summary_page_path   <root> <epic_id>
#   aid_epic_summary_page_render <run_evidence_dir> <out_path>
#
# WHY THIS EXISTS
#   The PM learns from one page what a finished EPIC delivered and what its
#   review left open.
#
#   It renders when the phase is genuinely OVER — after the review, not after
#   the last step (PM, 2026-08-25: "až ve chvíli, kdy je to opravdu hotové").
#   Its production caller is `cmd_done_advance` on the review→release edge; an
#   instruction telling a session to render it would be exactly the kind of
#   rule that gets asked for and skipped.
#
# WHAT IT IS NOT
#   It does not publish, and it is not `aid-epic-summary.sh`. That one writes
#   `epic-summary.md` into the run's evidence — a technical record for the next
#   agent. This writes a page for a person, and both keep their own job.
#
# THE DATA CONTRACT, because the Step 6 obligation depends on it
#   inputs     the EPIC review round (`cp3/rounds.json` and the last round's
#              `merged.json`) from the RUN's evidence dir. Missing → the page is
#              still rendered and NAMES it. It never implies the review
#              was complete when it was not.
#   output     <root>/.aid-o/work/evidence/<plan_id>/<epic_id>/epic-summary-artifact.html
#              — the same convention as plan-summary-artifact.html, so
#              lib/aid-artifact-obligation.sh finds both with one rule.
#   freshness  the page must be newer than the EPIC's last commit. That, and
#              its existence, is ALL the Stop rule reads; it never parses the
#              page's content.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-09-20
# =============================================================================
[[ -n "${_AID_ESP_SH_LOADED:-}" ]] && return 0
_AID_ESP_SH_LOADED=1

_AID_ESP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-artifact-render.sh
source "${_AID_ESP_LIB_DIR}/aid-artifact-render.sh"

# aid_epic_summary_page_path <root> <epic_id>
#   The one place the page's location is spelled, so the renderer and the
#   obligation rule cannot drift apart. plan_id is derived from the epic id the
#   same way the rest of the FSM does it (E-089-1_3 → P089).
aid_epic_summary_page_path() {
  local root="${1-}" epic_id="${2-}" plan_id=""
  [[ -n "$root" && -n "$epic_id" ]] || return 1
  [[ "$epic_id" =~ ^E-([0-9]+) ]] || return 1
  plan_id="P${BASH_REMATCH[1]}"
  printf '%s/.aid-o/work/evidence/%s/%s/epic-summary-artifact.html' "$root" "$plan_id" "$epic_id"
}

# _esp_yaml <state_file> <key> — one scalar, the same grep the rest of the FSM
# tooling uses on this file. yq is not required for a page.
_esp_yaml() {
  local v
  v="$(grep -m1 "^${2}:" "$1" 2>/dev/null | sed "s/^${2}:[[:space:]]*//; s/^\"//; s/\"$//")" || v=""
  printf '%s' "$v"
}

# _esp_duration <started_at> <finished_at> — human h/m. Computed, never claimed.
_esp_duration() {
  local a b s
  a="$(date -u -d "${1:-}" +%s 2>/dev/null)" || a=""
  b="$(date -u -d "${2:-}" +%s 2>/dev/null)" || b=""
  if [[ -z "$a" || -z "$b" ]] || (( b < a )); then printf '—'; return 0; fi
  s=$(( b - a ))
  if (( s < 3600 )); then printf '%s min' "$(( (s + 59) / 60 ))"; return 0; fi
  printf '%s h %s min' "$(( s / 3600 ))" "$(( (s % 3600) / 60 ))"
}

# aid_epic_summary_page_render <run_evidence_dir> <out_path>
aid_epic_summary_page_render() {
  local ev="${1-}" out="${2-}"
  if [[ -z "$ev" || -z "$out" ]]; then
    echo "aid_epic_summary_page_render: usage: aid_epic_summary_page_render <run_evidence_dir> <out_path>" >&2
    return 1
  fi
  local state="${ev}/fsm-state.yaml"
  [[ -f "$state" ]] || state="${ev}/state.yaml"
  if [[ ! -f "$state" ]]; then
    echo "aid_epic_summary_page_render: no fsm-state.yaml in ${ev} — refusing to render a page about a run it cannot identify" >&2
    return 1
  fi

  local epic_id total_steps gate_retries started_at finished_at
  epic_id="$(_esp_yaml "$state" epic_id)"
  total_steps="$(aid_artifact_number "$(_esp_yaml "$state" total_steps)")"
  gate_retries="$(aid_artifact_number "$(_esp_yaml "$state" gate_retries)")"
  started_at="$(_esp_yaml "$state" started_at)"
  finished_at="$(grep 'completed_at:' "$state" 2>/dev/null | tail -1 | sed 's/.*completed_at:[[:space:]]*//; s/^"//; s/"$//')"

  # ── WHAT THE EPIC ACTUALLY PRODUCED ───────────────────────────────────────
  # The page exists so the PM learns what came out of the EPIC. Until 2026-08-28
  # this renderer never asked: it read the review reports, and when
  # they were absent it said so and stopped — three near-identical pages for WAN
  # P099, none of which named a single thing the work produced.
  #
  # The text was there the whole time. Two files in the SAME evidence directory
  # carry it, written by the run itself:
  #   final_report.md   — "## Co EPIC dodal" / "## What the EPIC delivered"
  #   epic-summary.md   — "## ✅ Co bylo dodáno" / "## What was delivered"
  # Whichever exists is read, first heading wins, and its bullet lines become
  # the deliverables the profile now requires. Neither present → the field is
  # empty and the profile refuses the render, which is the honest outcome: a
  # page that cannot say what was delivered has nothing to tell the PM.
  local -a delivered=()
  local _dsrc _dline
  for _dsrc in "${ev}/final_report.md" "${ev}/epic-summary.md"; do
    [[ -f "$_dsrc" ]] || continue
    while IFS= read -r _dline; do
      [[ -n "$_dline" ]] || continue
      delivered+=("$_dline")
    done < <(awk '
      # The English alternatives are ANCHORED, not substrings: "delivered" alone
      # also matches "## Not delivered" and "## Undelivered items", whose
      # contents would then be published as what the EPIC produced (Codex,
      # 2026-08-28). Czech headings are affirmative by construction.
      /^##[[:space:]]*[^[:alnum:]]*([Cc]o (EPIC )?dodal|[Cc]o bylo dodáno|(What (the )?(EPIC|plan) delivered)|Delivered)[[:space:]]*$/ { grab=1; next }
      grab && /^##[[:space:]]/ { exit }
      # Both list grammars: "- item" and "1. item". final_report.md numbers its
      # deliverables, epic-summary.md bullets them, and taking only one form was
      # how the first version of this fell through to a list of commit hashes.
      grab && /^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+/ {
        sub(/^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+/, "");
        gsub(/\*\*/, "");           # bold markers
        gsub(/`/, "");               # code ticks
        gsub(/\]\([^)]*\)/, "");   # markdown link target …
        gsub(/\[/, "");            # … leaving just its text
        if (length($0) > 0) print
      }' "$_dsrc" 2>/dev/null | head -5)
    [[ "${#delivered[@]}" -gt 0 ]] && break
  done

  # ── the review's record; a missing one is NAMED, never implied away ───────
  # The EPIC round index (cp3/rounds.json) carries the verdict; what it left
  # open is in the last round's merged.json.
  local -a missing=() findings=()
  local n_blocking=0 n_open=0 rounds="${ev}/cp3/rounds.json" last_round
  last_round="$(ls -d "${ev}"/cp3/round-* 2>/dev/null | sort -V | tail -1)"
  if [[ -f "$rounds" ]] && jq -e '.verdict' "$rounds" >/dev/null 2>&1; then
    if [[ -f "${last_round}/merged.json" ]]; then
      n_open="$(aid_artifact_number "$(jq -r '[.findings[] | select(.status | IN("open", "disputed", "routed", "carried"))] | length' "${last_round}/merged.json" 2>/dev/null)")"
      n_blocking="$(aid_artifact_number "$(jq -r '[.findings[] | select((.status | IN("open", "disputed", "routed", "carried")) and .severity == "blocker")] | length' "${last_round}/merged.json" 2>/dev/null)")"
    fi
    case "$(jq -r '.verdict' "$rounds")" in
      pass|skip|no_change) findings+=("Revize EPICu prošla$( (( n_open > 0 )) && printf ', otevřených nálezů zůstává %s' "$n_open")") ;;
      *)                   findings+=("Revize EPICu neprošla: otevřených nálezů ${n_open}, z toho ${n_blocking} blokujících"); (( n_blocking > 0 )) || n_blocking=1 ;;
    esac
  else
    missing+=("záznam revize EPICu (cp3/rounds.json)")
  fi

  # ── the verdict, DERIVED ───────────────────────────────────────────────────
  local verdict verdict_state
  if (( ${#missing[@]} > 0 )); then
    verdict="Revize neúplná"; verdict_state="warn"
  elif (( n_blocking > 0 )); then
    verdict="Blokující nálezy"; verdict_state="critical"
  elif (( n_open > 0 )); then
    verdict="Hotovo, s otevřenými nálezy"; verdict_state="warn"
  else
    verdict="Hotovo, bez nálezů"; verdict_state="ok"
  fi

  # ── the core list; the order is the budget (the renderer caps it at five) ──
  local -a items=()
  local m
  for m in "${missing[@]+"${missing[@]}"}"; do
    items+=("CHYBÍ ${m} — revize neproběhla úplně a tahle stránka to nezamlčuje")
  done
  items+=("${findings[@]+"${findings[@]}"}")
  (( gate_retries > 1 )) && items+=("Brány musely běžet ${gate_retries}× — něco se opravovalo za pochodu")

  local items_json next_json
  items_json="$(printf '%s\n' "${items[@]+"${items[@]}"}" | jq -R . | jq -sc 'map(select(. != ""))')"

  # ── block 6: a decision when there is one, and nothing beside a command ────
  local ask=""
  local -a next_steps=()
  if (( ${#missing[@]} > 0 )); then
    next_steps+=("Revizi EPICu dokončit")
    next_steps+=("Nebo mergnout s vědomím, že revize je neúplná")
    ask="Rozhodni: dokončit revizi, nebo mergnout bez ní. Doporučuju dokončit — merge bez revize je jediná věc, kterou už zpětně nedoženeš. Dokud nerozhodneš, EPIC leží hotový a nemergnutý."
  elif (( n_blocking > 0 )); then
    next_steps+=("Vrátit k opravě blokujících nálezů")
    next_steps+=("Nebo mergnout s výhradami a nálezy odložit do backlogu")
    ask="Rozhodni: vrátit k opravě, nebo mergnout s výhradami. Doporučuju vrátit — blokující nález se po mergi opravuje dráž. Dokud nerozhodneš, EPIC leží hotový a nemergnutý."
  fi
  next_json="$(printf '%s\n' "${next_steps[@]+"${next_steps[@]}"}" | jq -R . | jq -sc 'map(select(. != ""))')"

  local summary core
  # The declension helper the renderer already carries, applied to the PROSE as
  # well as to the tiles — "1 kroků" beside a correctly declined tile is the
  # same defect the helper exists for, one line lower.
  summary="EPIC ${epic_id} je hotový: $(_aid_artifact_czech "$total_steps" "krok" "kroky" "kroků") za $(_esp_duration "$started_at" "$finished_at")."
  if (( ${#missing[@]} > 0 )); then
    core="Revize ale neproběhla celá — chybí $(printf '%s' "${missing[0]}"). Co je níž, platí jen pro tu část, která proběhla."
  elif (( n_blocking > 0 )); then
    core="Revize EPICu nechala otevřené $(_aid_artifact_czech "$n_blocking" "blokující nález" "blokující nálezy" "blokujících nálezů")."
  else
    core="Revize EPICu proběhla celá, blokující nález žádný."
  fi

  # The profile requires `deliverables`; shape it the way the plan page does —
  # one group whose steps carry the delivered lines — so the renderer's existing
  # region draws it without a second code path.
  local deliverables_json="[]" _dj
  if [[ "${#delivered[@]}" -gt 0 ]]; then
    _dj="$(printf '%s\n' "${delivered[@]}" | jq -R . | jq -sc \
      '[{epic: "", steps: [ to_entries[] | {n: (.key + 1 | tostring), text: .value} ]}]')" \
      && deliverables_json="$_dj"
  fi

  local facts prose
  facts="$(jq -nc \
    --arg epic "$epic_id" \
    --arg when "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg vv "$verdict" --arg vs "$verdict_state" \
    --arg dur "$(_esp_duration "$started_at" "$finished_at")" \
    --arg steps "$total_steps" \
    --arg blocking "$n_blocking" \
    --arg bs "$( (( n_blocking > 0 )) && echo warn || echo ok )" \
    --argjson items "$items_json" \
    --argjson next "$next_json" \
    --argjson deliv "$deliverables_json" \
    --arg ev "$ev" '{
      artifact_type: "epic_done",
      eyebrow: "Dokončený EPIC",
      title: ("EPIC " + $epic),
      when: $when,
      tiles: {
        result:     {label: "Výsledek",  value: $vv,  state: $vs},
        duration:   {label: "Trvalo",    value: $dur},
        scope:      {label: "Kroků",     value: $steps, state: "ok"},
        unresolved: {label: "Blokující", value: $blocking, state: $bs}
      },
      items: $items,
      deliverables: $deliv,
      next_steps: $next,
      detail: {label: "Technický detail běhu EPICu"},
      footer: ("Zdroj: " + $ev + ". Vyrobil aid-epic-summary-page.sh; čísla jsou spočítaná z evidence, ne opsaná.")
    }')" || { echo "aid_epic_summary_page_render: failed to build facts" >&2; return 1; }

  prose="$(jq -nc --arg s "$summary" --arg c "$core" --arg a "$ask" \
    '{summary:$s, core:$c, ask:$a}')"

  mkdir -p "$(dirname "$out")" 2>/dev/null
  aid_artifact_render outcome "$facts" "$prose" "$out"
}
