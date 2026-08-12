#!/usr/bin/env bash
# aid-gate-outcome-summary.sh — P080 Step 11.
#
# The gate-run boundary message, rendered DETERMINISTICALLY from the canonical
# gates report. One entry point:
#
#   aid_gate_outcome_render <gates_report_json> <run_dir> [waiver_dir]
#
#   gates_report_json  the runner-reported --report-file path when the caller
#                      has it (the preferred wiring), or empty to resolve.
#   run_dir            the run's evidence dir — resolution root and the place
#                      the artifact body is written.
#   waiver_dir         OPTIONAL receipts dir. It ENRICHES waiver detail only.
#                      Its absence can never hide a waiver.
#
#   Writes  <run_dir>/gate-outcome-artifact.html   (an artifact BODY)
#   Prints  the chat card on stdout, last line `Artifact: <path>`
#
# WHAT THIS IS NOT
#   It does not publish. Publication through the Artifact tool is the
#   controller's live act, wired in commands/aid-run.md and skills/pipeline.md
#   with the canonical publish-before-present clause from skills/communication.md.
#   Nothing here claims a page exists.
#
#   It also re-derives NOTHING. Every number it shows is computed from the
#   report it was handed; a recommendation is never rendered as a fact and a
#   waiver is never rendered as a passing gate.
#
# REPORT PATH IS NOT A CONSTANT
#   `aid-run-gates.sh` takes an arbitrary `--report-file` (:1629 only DEFAULTS
#   to the nested layout), and the repo carries both a nested and a flat
#   layout. Resolution stops at the first hit, in this order:
#     1. the exact path passed in as $1
#     2. <run_dir>/gates/gates_report.json      (nested)
#     3. <run_dir>/gates_report.json            (flat)
#   The resolved path is echoed in the artifact's provenance footer, so which
#   report was rendered is never ambiguous.
#
#   The targeted→full ESCALATION shape (lib/aid-run-gates-report.sh's
#   merge_escalation_report) is the full pass's report plus a top-level
#   `escalation` key — a superset, accepted here and surfaced in the core list.
#
# THE CARD FOLLOWS `.overall`, NEVER A PER-GATE VERDICT
#   Gate rows carry {gate, result, reason, exit_code, duration_ms, output,
#   attempts} and NO `required` key: required-ness lives in execution.yaml and
#   survives only in the envelope's `.overall`, which the runner already
#   computes (a failing non-required gate leaves overall=pass at :2001/:2259, a
#   waived required failure is treated as a pass at :2145, and skip /
#   profile_excluded never affect it). Deriving the card from individual rows
#   would tell the PM a run is blocked while the FSM advances.
#
# WAIVED IS NOT PASSED (D3)
#   `waived` is a first-class row result. The REPORT is the primary waiver
#   source: the runner rewrites a waived row to result:"waived" with a
#   `waiver_ref` (:2174-2176) and surfaces top-level `waived_gates[]`
#   (:1692-1694, :2512-2537) precisely so nothing downstream reconstructs
#   waivers from receipts. A waiver renders as PM risk acceptance, carrying the
#   literal `waived`; the string "passed" is never emitted by this file at all.
#   A waiver present but REJECTED leaves the row `fail` with
#   `waiver_rejected:<verdict>` — that renders in the failed section with its
#   verdict word and is never counted as waived-ok.
#
# NO PATH FROM GATE OUTPUT TO A HUMAN SURFACE SKIPS REDACTION
#   This file never embeds a row's raw `output`. For the controller's fallback
#   card (see Error Handling in the wiring), `aid_gate_outcome_redact` is the
#   callable entry point onto the SAME deterministic redactor the artifact lib
#   applies to everything it renders.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_AID_GOS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-artifact-render.sh
source "${_AID_GOS_LIB_DIR}/aid-artifact-render.sh"

_AID_GOS_ARTIFACT_BASENAME="gate-outcome-artifact.html"

# The exact public risk-acceptance command (P073 surface, pipeline.md §5).
_AID_GOS_FORCE_CMD="aid-fsm.sh transition GATES DONE <state_file> --force --reason '<≥20 chars — PM-authorized reason>'"
_AID_GOS_ADVANCE_CMD="aid-fsm.sh transition GATES DONE <state_file>"

# aid_gate_outcome_redact <text>
#   The callable redaction entry point for anything raw the CONTROLLER has to
#   put in front of the PM when this renderer could not run. Same detector
#   table, same replacements as the artifact body. Prints the redacted text.
aid_gate_outcome_redact() {
  local _t="$1" _n=0
  _aid_artifact_redact _t _n
  printf '%s' "$_t"
}

# aid_gate_outcome_resolve_report <explicit_path> <run_dir>
#   Prints the resolved report path, or nothing (exit 1) when none exists.
aid_gate_outcome_resolve_report() {
  local explicit="${1-}" run_dir="${2-}"
  if [[ -n "$explicit" && -f "$explicit" ]]; then printf '%s' "$explicit"; return 0; fi
  if [[ -n "$run_dir" && -f "${run_dir}/gates/gates_report.json" ]]; then
    printf '%s' "${run_dir}/gates/gates_report.json"; return 0
  fi
  if [[ -n "$run_dir" && -f "${run_dir}/gates_report.json" ]]; then
    printf '%s' "${run_dir}/gates_report.json"; return 0
  fi
  return 1
}

# _aid_gos_duration <total_ms> — human m/s. Computed, never asserted.
_aid_gos_duration() {
  local ms="${1:-0}" s m
  [[ "$ms" =~ ^[0-9]+$ ]] || ms=0
  s=$(( (ms + 999) / 1000 ))
  if (( s < 60 )); then printf '%s s' "$s"; return 0; fi
  m=$(( s / 60 )); s=$(( s % 60 ))
  printf '%s min %s s' "$m" "$s"
}

# _aid_gos_waiver_detail <waiver_dir> <gate>
#   Enrichment ONLY. Prints ", <reason-ish detail>" or nothing. A missing dir,
#   a missing file or a malformed file all yield nothing — never an error, and
#   never a reason to drop the waiver itself.
_aid_gos_waiver_detail() {
  local dir="${1-}" gate="${2-}" f detail=""
  [[ -n "$dir" && -d "$dir" ]] || return 0
  f="${dir}/gate-waiver-${gate}.json"
  [[ -f "$f" ]] || return 0
  detail="$(jq -r '
    [ (.authorized_by // empty),
      (if (.consumed.at // null) != null then "spotřebováno" else empty end),
      (if (.expires_at // null) != null then "platnost do " + (.expires_at|tostring) else empty end),
      (.reason // empty)
    ] | map(select(. != "")) | join(", ")' "$f" 2>/dev/null)" || detail=""
  [[ -n "$detail" && "$detail" != "null" ]] || return 0
  printf ', %s' "$detail"
}

# aid_gate_outcome_render <gates_report_json> <run_dir> [waiver_dir]
aid_gate_outcome_render() {
  local report_in="${1-}" run_dir="${2-}" waiver_dir="${3-}"

  if [[ -z "$run_dir" ]]; then
    echo "aid_gate_outcome_render: usage: aid_gate_outcome_render <gates_report_json> <run_dir> [waiver_dir]" >&2
    return 1
  fi

  local report_path
  if ! report_path="$(aid_gate_outcome_resolve_report "$report_in" "$run_dir")"; then
    echo "aid_gate_outcome_render: no gates report found (tried '${report_in:-<none>}', ${run_dir}/gates/gates_report.json, ${run_dir}/gates_report.json)" >&2
    return 1
  fi

  local report
  if ! report="$(jq -c '.' "$report_path" 2>/dev/null)"; then
    echo "aid_gate_outcome_render: invalid gates report JSON at ${report_path}" >&2
    return 1
  fi
  if [[ "$(jq -r 'if type == "object" then "ok" else "no" end' <<<"$report")" != "ok" ]]; then
    echo "aid_gate_outcome_render: gates report at ${report_path} is not an object" >&2
    return 1
  fi

  # ── counts, all COMPUTED from the report's .gates OBJECT (a map, not rows) ──
  local rows
  rows="$(jq -c '[ (.gates // {}) | to_entries[] | (.value + {gate: (.value.gate // .key)}) ]' <<<"$report")"

  local total n_pass n_fail n_skip n_excl n_waived total_ms
  total="$(jq -r 'length' <<<"$rows")"
  n_pass="$(jq -r '[.[] | select(.result == "pass")] | length' <<<"$rows")"
  n_fail="$(jq -r '[.[] | select(.result == "fail")] | length' <<<"$rows")"
  n_skip="$(jq -r '[.[] | select(.result == "skip")] | length' <<<"$rows")"
  n_excl="$(jq -r '[.[] | select(.result == "profile_excluded")] | length' <<<"$rows")"
  total_ms="$(jq -r '[.[] | (.duration_ms // 0)] | add // 0' <<<"$rows")"

  # Waivers: the report is PRIMARY. The union of top-level waived_gates[] and
  # any row already stamped result:"waived" — either alone is enough.
  local waived_json
  waived_json="$(jq -c --argjson rows "$rows" '
    ((.waived_gates // []) + [$rows[] | select(.result == "waived") | .gate]) | unique' <<<"$report")"
  n_waived="$(jq -r 'length' <<<"$waived_json")"

  local overall
  overall="$(jq -r '.overall // "unknown"' <<<"$report")"
  local blocked=0
  [[ "$overall" == "fail" ]] && blocked=1

  local escalated=0
  [[ "$(jq -r 'if (.escalation // null) != null then "1" else "0" end' <<<"$report")" == "1" ]] && escalated=1

  local duration_human
  duration_human="$(_aid_gos_duration "$total_ms")"

  # `unresolved` is fail + waived: both are gates this run did not prove.
  local n_unresolved=$(( n_fail + n_waived ))

  # ── the core list: everything that is not a plain first-attempt pass ───────
  local -a core_items=()
  local gate res code att detail

  while IFS=$'\t' read -r gate res code att; do
    [[ -n "$gate" ]] || continue
    case "$res" in
      fail)
        detail="$(jq -r --arg g "$gate" '
          [.[] | select(.gate == $g) | (.waiver_rejected // empty)] | first // ""' <<<"$rows")"
        if [[ -n "$detail" ]]; then
          core_items+=("brána ${gate}: selhala (exit ${code}), výjimka zamítnuta — ${detail}")
        else
          core_items+=("brána ${gate}: selhala (exit ${code})")
        fi
        ;;
      waived)
        core_items+=("brána ${gate}: waived — PM převzal riziko$(_aid_gos_waiver_detail "$waiver_dir" "$gate")")
        ;;
      skip)             core_items+=("brána ${gate}: přeskočena") ;;
      profile_excluded) core_items+=("brána ${gate}: mimo profil") ;;
      pass)
        if [[ "$att" =~ ^[0-9]+$ ]] && (( att > 1 )); then
          core_items+=("brána ${gate}: prošla až na ${att}. pokus")
        fi
        ;;
    esac
  done < <(jq -r '.[] | [(.gate // "?"), (.result // "?"), ((.exit_code // 0)|tostring), ((.attempts // 0)|tostring)] | @tsv' <<<"$rows")

  # A waiver named ONLY by top-level waived_gates[] (no matching row) still
  # renders — the absence of a row is never allowed to hide risk acceptance.
  local w
  while IFS= read -r w; do
    [[ -n "$w" ]] || continue
    if [[ "$(jq -r --arg g "$w" '[.[] | select(.gate == $g and .result == "waived")] | length' <<<"$rows")" == "0" ]]; then
      core_items+=("brána ${w}: waived — PM převzal riziko$(_aid_gos_waiver_detail "$waiver_dir" "$w")")
    fi
  done < <(jq -r '.[]' <<<"$waived_json")

  (( escalated == 1 )) && core_items+=("eskalace targeted → full: $(jq -r '.escalation.reason // "bez uvedeného důvodu"' <<<"$report")")
  (( total == 0 )) && core_items+=("profil nespustil žádnou bránu")

  local items_json
  items_json="$(printf '%s\n' "${core_items[@]+"${core_items[@]}"}" | jq -R . | jq -sc 'map(select(. != ""))')"

  # ── the first failing gate and its reproduction command ───────────────────
  local first_fail first_fail_code repro=""
  first_fail="$(jq -r '[.[] | select(.result == "fail") | .gate] | first // ""' <<<"$rows")"
  first_fail_code="$(jq -r --arg g "$first_fail" '[.[] | select(.gate == $g) | (.exit_code // 0)] | first // 0' <<<"$rows")"
  if [[ -n "$first_fail" ]]; then
    # The gate's OWN command, taken from the report's _command_log. Gate
    # definitions carry no remediation field anywhere in this repo, so the
    # reproduction step is the command itself — never an invented fix.
    repro="$(jq -r --arg g "$first_fail" '[(._command_log // [])[] | select(.name == $g) | .command] | first // ""' <<<"$report")"
  fi

  local -a next_steps=()
  if (( blocked == 1 )); then
    [[ -n "$repro" ]] && next_steps+=("Zopakuj bránu: ${repro}")
    next_steps+=("Oprav příčinu a spusť brány znovu")
    next_steps+=("Nebo převezmi riziko: ${_AID_GOS_FORCE_CMD}")
  else
    next_steps+=("Pokračuj na DONE: ${_AID_GOS_ADVANCE_CMD}")
  fi
  local next_json
  next_json="$(printf '%s\n' "${next_steps[@]}" | jq -R . | jq -sc '.')"

  # ── prose, computed — no model text at this boundary ───────────────────────
  local p_summary p_core p_ask
  if (( blocked == 1 )); then
    p_summary="Brány neprošly: ${n_fail} z ${total} selhalo, běh je zastavený před DONE."
  elif (( total == 0 )); then
    p_summary="Profil nespustil žádnou bránu, takže není co blokovat."
  else
    p_summary="Brány prošly: ${n_pass} z ${total}, běh může pokračovat na DONE."
  fi
  p_core="Prošlo ${n_pass}, selhalo ${n_fail}, přeskočeno ${n_skip}, mimo profil ${n_excl}, s výjimkou ${n_waived}. Celkem ${duration_human}."
  if (( blocked == 1 )); then
    p_ask="Rozhodni, jestli opravíme příčinu, nebo jestli přebíráš riziko force příkazem."
  elif (( n_waived > 0 )); then
    p_ask="Nic — jen ať víš, že ${n_waived} brána/y prošly s tvojí výjimkou, ne testem."
  else
    p_ask=""
  fi

  # ── facts + render ────────────────────────────────────────────────────────
  local out_path="${run_dir}/${_AID_GOS_ARTIFACT_BASENAME}"
  local facts prose
  facts="$(jq -nc \
    --arg title "Brány: $(jq -r '.epic_id // "?"' <<<"$report")" \
    --arg when "$(jq -r '.completed_at // ._generated_at // "—"' <<<"$report")" \
    --arg rv "${n_pass}/${total} prošlo" \
    --arg rs "$([[ $blocked -eq 1 ]] && echo critical || echo ok)" \
    --arg dv "$duration_human" \
    --arg sv "$total" \
    --arg uv "$n_unresolved" \
    --arg us "$([[ $n_unresolved -gt 0 ]] && echo warn || echo ok)" \
    --argjson items "$items_json" \
    --argjson next "$next_json" \
    --arg report_path "$report_path" \
    '{
      eyebrow: "Výsledek bran",
      title: $title,
      when: $when,
      tiles: {
        result:     {value: $rv, state: $rs},
        duration:   {value: $dv},
        scope:      {value: $sv},
        unresolved: {value: $uv, state: $us}
      },
      items: $items,
      next_steps: $next,
      links: [$report_path],
      detail: {label: ("technický detail: " + $report_path)},
      footer: ("Zdroj: " + $report_path + ". Vyrobil aid-gate-outcome-summary.sh.")
    }')" || { echo "aid_gate_outcome_render: failed to build facts" >&2; return 1; }

  prose="$(jq -nc --arg s "$p_summary" --arg c "$p_core" --arg a "$p_ask" \
    '{summary:$s, core:$c, ask:$a}')"

  local rc=0
  aid_artifact_render outcome "$facts" "$prose" "$out_path" || rc=$?
  if (( rc != 0 )); then
    echo "aid_gate_outcome_render: artifact render failed (exit ${rc}) for ${out_path}" >&2
    return "$rc"
  fi

  # ── the chat card (communication.md shapes 1 and 3) ────────────────────────
  # The card does NOT pass through aid_artifact_render, so it does not inherit
  # that renderer's redaction. Two of its values are tooling-controlled text —
  # the gate NAME (execution.yaml) and the reproduction command (the report's
  # own _command_log) — and P080 Step 15's malicious fixture proved both reach
  # the PM's chat verbatim. They go through the same detector table here. A
  # command that redacts to something uninvocable is the correct outcome: a
  # command carrying a token must not be pasted into a chat either.
  first_fail="$(aid_gate_outcome_redact "$first_fail")"
  [[ -z "$repro" ]] || repro="$(aid_gate_outcome_redact "$repro")"

  if (( blocked == 1 )); then
    printf 'Zastaveno: brána %s selhala (exit %s).\n' "$first_fail" "$first_fail_code"
    printf 'Dopad: běh nepokračuje na DONE; prošlo %s z %s, nic se nemerguje.\n' "$n_pass" "$total"
    if [[ -n "$repro" ]]; then
      printf 'Doporučené řešení: zopakuj bránu příkazem `%s` a oprav příčinu.\n' "$repro"
    else
      printf 'Doporučené řešení: oprav příčinu selhání brány %s a spusť brány znovu.\n' "$first_fail"
    fi
    printf 'Pokud chceš převzít riziko: %s — přeskočí jen tuhle podmínku přechodu, ne samotnou bránu.\n' "$_AID_GOS_FORCE_CMD"
  else
    printf 'Hotovo: brány doběhly, %s z %s prošlo.\n' "$n_pass" "$total"
    printf 'Změnilo se: nic v kódu — brány jen ověřily současný stav.\n'
    printf 'Ověřeno: %s bran za %s (selhalo %s, přeskočeno %s, mimo profil %s, waived %s).\n' \
      "$total" "$duration_human" "$n_fail" "$n_skip" "$n_excl" "$n_waived"
    if (( n_waived > 0 )); then
      printf 'Další krok: %s — ale %s brána/y jsou waived, tedy tvoje riziko, ne prokázaný výsledek.\n' \
        "$_AID_GOS_ADVANCE_CMD" "$n_waived"
    else
      printf 'Další krok: %s.\n' "$_AID_GOS_ADVANCE_CMD"
    fi
  fi
  printf 'Artifact: %s\n' "$out_path"
  return 0
}
