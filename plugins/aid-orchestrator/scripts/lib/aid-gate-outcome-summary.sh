#!/usr/bin/env bash
# aid-gate-outcome-summary.sh — the gate-boundary message.
#
# WHY THIS FILE EXISTS: when the gate runner returns, the PM gets one chat card, written by no model:
# this file renders it DETERMINISTICALLY from gates_report.json. Every number is
# computed from the report, the verdict follows the envelope's `.overall` and
# never a per-gate row, a waived gate is counted as PM risk acceptance and never
# as a pass, and nothing from the report reaches the card without the redactor.
# There is no page: the PM reads two pages per plan (P099 Step 4), and a gate
# run is not one of them. The controller sources this at the gates phase
# (commands/aid-run.md, skills/pipeline.md) and presents the card verbatim.
#
#   aid_gate_outcome_render <gates_report_json> <run_dir>
#
#   gates_report_json  the runner-reported --report-file path when the caller
#                      has it (the preferred wiring), or empty to resolve.
#   run_dir            the run's evidence dir — the resolution root.
#   Prints  the chat card on stdout.
#
# REPORT PATH IS NOT A CONSTANT
#   `aid-run-gates.sh` takes an arbitrary `--report-file`, and the repo carries
#   both a nested and a flat layout. Resolution stops at the first hit:
#     1. the exact path passed in as $1
#     2. <run_dir>/gates/gates_report.json      (nested)
#     3. <run_dir>/gates_report.json            (flat)
#   The targeted→full escalation shape (merge_escalation_report) is the full
#   pass's report plus a top-level `escalation` key — a superset, accepted here.
#
# THE CARD FOLLOWS `.overall`, NEVER A PER-GATE VERDICT
#   Gate rows are read through the version-2 contract (lib/aid-gate-row.sh,
#   P097 Step 2). The card follows the envelope's `.overall`, which the runner
#   computes (a failing non-required gate leaves overall=pass, a waived
#   required failure is treated as a pass, skip / not_in_profile never affect
#   it). Deriving the card from individual rows would tell the PM a run is
#   blocked while the FSM advances.
#
# FOUR CLOSED CATEGORIES (P089 Step 3): ověřeno · selhalo · neběželo ·
#   prominuto. A waiver is `waived: true` on a `fail` row, or a gate named in the
#   report's top-level `waived_gates[]`; a REJECTED waiver (`waiver_rejected`)
#   stays a failure.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_AID_GOS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-artifact-render.sh
source "${_AID_GOS_LIB_DIR}/aid-artifact-render.sh"
# shellcheck source=aid-gate-row.sh
source "${_AID_GOS_LIB_DIR}/aid-gate-row.sh"   # P097 Step 2 — the ONE row reader (gate_row_normalize)

# The exact public risk-acceptance command (P073 surface, pipeline.md §5).
_AID_GOS_FORCE_CMD="aid-fsm.sh transition GATES DONE <state_file> --force --reason '<≥20 chars — PM-authorized reason>'"
_AID_GOS_ADVANCE_CMD="aid-fsm.sh transition GATES DONE <state_file>"

# "DID NOT RUN" IS A MAPPING, NOT A GUESS (P089 Step 3). The runner has no
# separate status for "the harness stopped this gate before it could prove
# anything": such a row is a plain `fail` whose `reason` says so. The list is
# CLOSED; `undefined_gate` and `unknown_placeholder` are deliberately not in it
# — configuration defects count as failures, the conservative direction an
# unknown reason takes too.
_AID_GOS_NOT_RUN_REASONS=" service_unhealthy missing_script gate_row_stale job_lost "

# _aid_gos_not_run <reason> — true when the reason means the gate did not run.
_aid_gos_not_run() { [[ -n "${1-}" && "$_AID_GOS_NOT_RUN_REASONS" == *" $1 "* ]]; }

# aid_gate_outcome_redact <text>
#   The callable redaction entry point for anything raw the CONTROLLER has to
#   put in front of the PM when this renderer could not run. Same detector
#   table as every rendered page (lib/aid-artifact-render.sh). Prints the
#   redacted text.
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

# aid_gate_outcome_render <gates_report_json> <run_dir>
aid_gate_outcome_render() {
  local report_in="${1-}" run_dir="${2-}"

  if [[ -z "$run_dir" ]]; then
    echo "aid_gate_outcome_render: usage: aid_gate_outcome_render <gates_report_json> <run_dir>" >&2
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

  # `.gates` is REQUIRED and must be an object. Defaulting it to `{}` made a
  # report carrying no gate data at all indistinguishable from a profile that
  # legitimately ran nothing, and the difference is the whole message: the empty
  # profile says "nothing to block", while a report missing its gates says
  # "nobody knows what ran" — and the card would have claimed "0 z 0 prošlo"
  # with full confidence. Malformed input fails closed; only a real, present,
  # empty `{}` reaches the zero-gates wording below.
  if [[ "$(jq -r 'if (.gates | type) == "object" then "ok" else "no" end' <<<"$report" 2>/dev/null)" != "ok" ]]; then
    echo "aid_gate_outcome_render: gates report at ${report_path} carries no .gates object — refusing to render a card that would claim no gates ran" >&2
    return 1
  fi
  # The outer type is not the shape this file depends on. Every VALUE of the map
  # must be an object too: `{"gates":{"tests":"pass"}}` satisfied the check above
  # and then died inside the row conversion below ("Cannot index string with
  # string"), whose status nobody read — so the counters came out EMPTY and the
  # card printed `Hotovo: brány doběhly,  z  prošlo.` with exit 0. A malformed
  # row is refused here, by name, so the PM never sees a blank-counter pass.
  local bad_rows
  bad_rows="$(jq -r '[ .gates | to_entries[] | select((.value|type) != "object") | .key ] | join(", ")' <<<"$report" 2>/dev/null)" || bad_rows=""
  if [[ -n "$bad_rows" ]]; then
    echo "aid_gate_outcome_render: gates report at ${report_path} has non-object gate entries (${bad_rows}) — refusing to render a card whose counters would be blank" >&2
    return 1
  fi

  # ── counts, all COMPUTED from the report's .gates OBJECT (a map, not rows) ──
  # The conversion's STATUS is read. An unchecked jq here is how a malformed
  # report reached the card as empty counters instead of as a refusal.
  # Every row is read through the version-2 contract (P097 Step 2): a
  # version-1 row from older evidence is mapped, a version-2 row passes
  # through, and nothing below looks at `result` again.
  local rows
  if ! rows="$(jq -c "${AID_GATE_ROW_JQ}"'[ .gates | to_entries[] | select((.key|startswith("_")|not) and (.value|type) == "object") | (.value + {gate: (.value.gate // .key)}) | gate_row_normalize ]' <<<"$report" 2>/dev/null)" \
     || [[ -z "$rows" ]] \
     || [[ "$(jq -r 'if type == "array" then "ok" else "no" end' <<<"$rows" 2>/dev/null)" != "ok" ]]; then
    echo "aid_gate_outcome_render: gates report at ${report_path} could not be converted into gate rows — refusing to render a card from an unknown gate set" >&2
    return 1
  fi

  local total n_waived total_ms
  total="$(jq -r 'length' <<<"$rows")"
  total_ms="$(jq -r '[.[] | (.duration_ms // 0)] | add // 0' <<<"$rows")"

  # Every other count comes from the ONE classification loop below — two
  # spellings of one rule is how a card starts contradicting itself.

  # Waivers: the report is PRIMARY. The union of top-level waived_gates[] and
  # any row already stamped result:"waived" — either alone is enough.
  #
  # A REJECTED waiver is REMOVED from that union, wherever it was named. The
  # runner leaves such a row `fail` with `waiver_rejected`, but nothing stops
  # the same gate from still appearing in top-level `waived_gates[]` — and then
  # it would count as a failure AND as a waiver, over one gate.
  local waived_json
  waived_json="$(jq -c --argjson rows "$rows" '
    (((.waived_gates // []) + [$rows[] | select(.status == "fail" and .waived) | .gate]) | unique) as $w
    | [ $rows[] | select(has("waiver_rejected")) | .gate ] as $rejected
    | [ $w[] | select(. as $g | $rejected | index($g) | not) ]' <<<"$report")"
  n_waived="$(jq -r 'length' <<<"$waived_json")"

  # `.overall` is REQUIRED and must be one of the two verdicts the runner
  # actually writes. `// "unknown"` made an ABSENT verdict decide the card: it
  # is not "fail", so `blocked` stayed 0 and a report of nothing but failing
  # gates printed `Hotovo: brány doběhly`. Verified by deleting the field from a
  # real failing report. Since the card follows `.overall` and nothing else (see
  # the header), a report without a usable one is a report whose verdict nobody
  # knows — the same class as the malformed inputs refused above, and refused
  # the same way. The runner emits exactly "pass"/"fail" (aid-run-gates.sh:2454,
  # and :2613 for the merged escalation shape), so no legitimate producer loses
  # a card here.
  local overall
  overall="$(jq -r '.overall // ""' <<<"$report")"
  if [[ "$overall" != "pass" && "$overall" != "fail" ]]; then
    # The value is report-supplied text on its way to a human surface, so it
    # goes through the same detector table as everything else this file prints.
    echo "aid_gate_outcome_render: gates report at ${report_path} carries no usable .overall verdict ('$(aid_gate_outcome_redact "${overall:-<none>}")') — refusing to render a card that would read as a pass" >&2
    return 1
  fi
  local blocked=0
  [[ "$overall" == "fail" ]] && blocked=1

  local duration_human
  duration_human="$(_aid_gos_duration "$total_ms")"

  # ── classify every row once: passed, failed, did not run, waived ─────────
  local -a failed_gates=()
  local gate res reason waived_flag
  local n_pass=0 n_failed=0 n_not_run=0

  # THE SEPARATOR IS \x1f, NOT A TAB. Tab is an IFS *whitespace* character, so
  # bash collapses runs of it — and `reason` is routinely empty, which shifted
  # every later field one place left. `@tsv` escapes any tab inside a value, so
  # the only raw tabs in the stream are the delimiters.
  while IFS=$'\037' read -r gate res reason waived_flag; do
    [[ -n "$gate" ]] || continue
    case "$res" in
      fail)
        _aid_gos_not_run "$reason" && { n_not_run=$(( n_not_run + 1 )); continue; }
        # Still in the waiver set → counted as waived, not also as a failure.
        # (A rejected waiver is no longer in that set, so it stays a failure.)
        [[ "$waived_flag" == "1" ]] && continue
        failed_gates+=("$gate")
        n_failed=$(( n_failed + 1 ))
        ;;
      skip|not_in_profile) n_not_run=$(( n_not_run + 1 )) ;;
      pass) n_pass=$(( n_pass + 1 )) ;;
    esac
  # Every value is stripped of U+001F before it is joined: `@tsv` does not
  # escape it, so a gate name carrying one would forge a field boundary.
  done < <(jq -r --argjson w "$waived_json" '
      def clean: (. // "") | tostring | gsub("\u001f"; " ");
      .[]
      | [ ((.gate // "?")|clean),
          ((if .status == "fail" and .waived then "waived" elif .reason == "not_in_profile" then "not_in_profile" else .status end)|clean),
          (.reason|clean),
          (if ((.gate // "") as $g | $w | index($g)) then "1" else "0" end)
        ] | @tsv' <<<"$rows" | tr '\t' '\037')

  # ── the first failing gate and its reproduction command ───────────────────
  # Taken from the classification above, not re-derived: "the first REAL
  # failure" is the first thing that loop put in `failed_gates`.
  local first_fail="" first_fail_code repro=""
  (( ${#failed_gates[@]} > 0 )) && first_fail="${failed_gates[0]}"
  first_fail_code="$(jq -r --arg g "$first_fail" '[.[] | select(.gate == $g) | (.exit_code // 0)] | first // 0' <<<"$rows")"
  if [[ -n "$first_fail" ]]; then
    # The gate's OWN command, taken from the report's _command_log. Gate
    # definitions carry no remediation field anywhere in this repo, so the
    # reproduction step is the command itself — never an invented fix.
    repro="$(jq -r --arg g "$first_fail" '[(._command_log // [])[] | select(.name == $g) | .command] | first // ""' <<<"$report")"
  fi

  # ── the chat card (communication.md shapes 1 and 3) ────────────────────────
  # EVERY card value that comes from the report goes
  # through the same detector table here — the gate NAME (execution.yaml), the
  # reproduction command (the report's own _command_log) and the failing gate's
  # EXIT CODE, which is a jq passthrough of a report field and therefore a
  # string of the report's choosing, not a number this file computed. Redacting
  # two of the three was the same leak in a smaller hole. A command that redacts
  # to something uninvocable is the correct outcome: a command carrying a token
  # must not be pasted into a chat either.
  #
  # The remaining card values are COUNTS and durations this file computed from
  # the report (jq `length`, an integer sum), plus the two fixed command
  # constants — none of them can carry input text.
  first_fail="$(aid_gate_outcome_redact "$first_fail")"
  first_fail_code="$(aid_gate_outcome_redact "$first_fail_code")"
  [[ -z "$repro" ]] || repro="$(aid_gate_outcome_redact "$repro")"

  if (( blocked == 1 )); then
    if [[ -n "$first_fail" ]]; then
      printf 'Zastaveno: brána %s selhala (exit %s).\n' "$first_fail" "$first_fail_code"
    else
      printf 'Zastaveno: neselhala žádná brána, ale %s jich neproběhlo, takže verdikt zůstal fail.\n' "$n_not_run"
    fi
    printf 'Dopad: běh nepokračuje na DONE; ověřeno %s z %s bran, nic se nemerguje.\n' "$n_pass" "$total"
    if [[ -n "$repro" ]]; then
      printf 'Doporučené řešení: zopakuj bránu příkazem `%s` a oprav příčinu.\n' "$repro"
    elif [[ -n "$first_fail" ]]; then
      printf 'Doporučené řešení: oprav příčinu selhání brány %s a spusť brány znovu.\n' "$first_fail"
    else
      printf 'Doporučené řešení: zjisti, proč brány neproběhly, a spusť je znovu.\n'
    fi
    printf 'Pokud chceš převzít riziko: %s — přeskočí jen tuhle podmínku přechodu, ne samotnou bránu.\n' "$_AID_GOS_FORCE_CMD"
  else
    if (( n_failed == 0 )); then
      printf 'Hotovo: brány doběhly, nic neselhalo.\n'
    else
      printf 'Hotovo: brány doběhly, %s z nich selhalo (žádná z nich povinná).\n' "$n_failed"
    fi
    printf 'Změnilo se: nic v kódu — brány jen ověřily současný stav.\n'
    printf 'Ověřeno: %s z %s bran za %s (selhalo %s, neběželo %s, prominuto %s).\n' \
      "$n_pass" "$total" "$duration_human" "$n_failed" "$n_not_run" "$n_waived"
    if (( n_waived > 0 )); then
      printf 'Další krok: %s — ale %s z bran je prominutá, tedy tvoje riziko, ne prokázaný výsledek.\n' \
        "$_AID_GOS_ADVANCE_CMD" "$n_waived"
    else
      printf 'Další krok: %s.\n' "$_AID_GOS_ADVANCE_CMD"
    fi
  fi
  return 0
}
