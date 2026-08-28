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
# FOUR CLOSED CATEGORIES, AND THE PAGE COUNTS IN THEM (P089 Step 3)
#   ověřeno · selhalo · neběželo · prominuto. The headline is HOW MANY FAILED,
#   never a ratio of passes: "6/9 prošlo" beside zero failures is the sentence
#   that made the PM call this page worthless, and it is now impossible to
#   write — the renderer COMPOSES the result, verified and did-not-run tiles
#   from the four counts this file hands it (defaults/artifact-profiles.yaml,
#   `outcome_from_state`). Nothing here formats a verdict sentence at all.
#
#   The core list names WHICH gates ran and what each verified (its own command
#   from the report's `_command_log`), and for the ones that did not, why.
#
#   Blocks 5 and 7 carry NAMES. The report path used to be on this page three
#   times; it now lives only in the provenance footer.
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

# "DID NOT RUN" IS A MAPPING, NOT A GUESS (P089 Step 3)
#   The runner has no separate result for "the harness stopped this gate before
#   it could prove anything": such a row is a plain `fail` whose `reason` says
#   what happened (aid-run-gates.sh:2040, :2071, :2391, and _bg_fail_row at
#   :908). Counting those among the failures tells the PM the code broke when
#   the code was never run; counting an unexplained failure among them would
#   hide a real one. So the list is CLOSED and explicit, every entry is a reason
#   whose own row text says the gate did not run in this invocation, and the
#   page NAMES the reason it used.
#
#   `undefined_gate` and `unknown_placeholder` are deliberately NOT here. They
#   also mean nothing ran, but they are defects in the gate configuration and
#   belong in front of the PM as failures — the conservative direction, the same
#   one an unknown reason takes.
#   A PLAIN `key|label` ARRAY, and deliberately not an associative one. The
#   map reads better, but it needs `declare -gA` to survive: this library is
#   sourced from INSIDE a function by every bats suite, and a bare `declare`
#   there makes the array local to that function. `-g` arrived in bash 4.2,
#   and this plugin's stated floor is 4.0 — where the map would fail to load
#   at all. A plain array assignment is global from inside a function on every
#   bash there is, so the readable form loses to the one that runs.
_AID_GOS_NOT_RUN_REASONS=(
  'service_unhealthy|služba, kterou brána potřebuje, neběžela'
  'gate_script_missing_in_tree|skript brány ve stromu nebyl'
  'gate_row_stale|záznam brány patřil jiné revizi, v tomhle běhu neběžela'
  'job_lost|běh brány na pozadí se ztratil, žádný záznam o dokončení'
)

# _aid_gos_not_run_reason <reason> — the Czech name when the reason means the
# gate did not run; nothing (exit 1) otherwise. `|` is the delimiter and no
# label may contain one.
_aid_gos_not_run_reason() {
  local want="${1-}" entry
  [[ -n "$want" ]] || return 1
  for entry in "${_AID_GOS_NOT_RUN_REASONS[@]}"; do
    [[ "${entry%%|*}" == "$want" ]] || continue
    printf '%s' "${entry#*|}"
    return 0
  done
  return 1
}

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
  local rows
  if ! rows="$(jq -c '[ .gates | to_entries[] | (.value + {gate: (.value.gate // .key)}) ]' <<<"$report" 2>/dev/null)" \
     || [[ -z "$rows" ]] \
     || [[ "$(jq -r 'if type == "array" then "ok" else "no" end' <<<"$rows" 2>/dev/null)" != "ok" ]]; then
    echo "aid_gate_outcome_render: gates report at ${report_path} could not be converted into gate rows — refusing to render a card from an unknown gate set" >&2
    return 1
  fi

  local total n_waived total_ms
  total="$(jq -r 'length' <<<"$rows")"
  total_ms="$(jq -r '[.[] | (.duration_ms // 0)] | add // 0' <<<"$rows")"

  # EVERY OTHER COUNT COMES FROM THE CLASSIFICATION LOOP BELOW, and that is the
  # point. The counts used to be computed here in jq and the same rows sorted
  # into their categories again, in bash, further down — two spellings of one
  # rule. A change to the did-not-run table or to the waiver union then landed
  # in one of them and the page contradicted itself: tiles saying one thing,
  # the list under them another. Which is the exact defect this whole step
  # exists to make impossible.

  # Waivers: the report is PRIMARY. The union of top-level waived_gates[] and
  # any row already stamped result:"waived" — either alone is enough.
  #
  # A REJECTED waiver is REMOVED from that union, wherever it was named. The
  # runner leaves such a row `fail` with `waiver_rejected`, but nothing stops
  # the same gate from still appearing in top-level `waived_gates[]` — and then
  # the page counted it as a failure AND as a waiver, over one gate.
  local waived_json
  waived_json="$(jq -c --argjson rows "$rows" '
    (((.waived_gates // []) + [$rows[] | select(.result == "waived") | .gate]) | unique) as $w
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

  local escalated=0
  [[ "$(jq -r 'if (.escalation // null) != null then "1" else "0" end' <<<"$report")" == "1" ]] && escalated=1

  local duration_human
  duration_human="$(_aid_gos_duration "$total_ms")"

  # ── the core list: WHICH gates ran, and what each of them verified ────────
  # It used to list only what was not a plain first-attempt pass, which is how
  # a page could say "6/9 passed" and never name a single gate. The order is
  # the budget: the renderer caps the list at five and says how many it
  # dropped, so failures come first and plain passes last.
  local -a it_failed=() it_waived=() it_not_run=() it_passed=() failed_gates=()
  local gate res code att reason rejected cmd waived_flag human
  local n_pass=0 n_failed=0 n_not_run=0

  # ONE jq feeds the loop with everything a row is judged on, including the
  # gate's own command from `_command_log` and whether the waiver union names
  # it. Both used to be a jq fork PER ROW over the whole report.
  # THE SEPARATOR IS \x1f, NOT A TAB. Tab is an IFS *whitespace* character, so
  # bash collapses runs of it — and four of these eight fields are routinely
  # empty (reason, waiver_rejected, command). With tabs, two empty fields in a
  # row silently vanished and every later field shifted one place left: a gate's
  # command was read as its reason. `@tsv` already escapes any tab inside a
  # value, so the only raw tabs in the stream are the delimiters, and the
  # translation below is exact.
  while IFS=$'\037' read -r gate res code att reason rejected waived_flag cmd; do
    [[ -n "$gate" ]] || continue
    case "$res" in
      fail)
        if human="$(_aid_gos_not_run_reason "$reason")"; then
          it_not_run+=("brána ${gate} neběžela: ${human}")
          n_not_run=$(( n_not_run + 1 ))
          continue
        fi
        # Still in the waiver set → it is the waiver's line to render, below,
        # and not a failure line here as well. (A rejected waiver is no longer
        # in that set, so it falls through and stays a failure.)
        if [[ "$waived_flag" == "1" ]]; then continue; fi
        failed_gates+=("$gate")
        n_failed=$(( n_failed + 1 ))
        if [[ -n "$rejected" ]]; then
          it_failed+=("brána ${gate}: selhala (exit ${code}), výjimka zamítnuta — ${rejected}")
        elif [[ -z "$reason" ]]; then
          it_failed+=("brána ${gate}: selhala (exit ${code}), důvod neznámý")
        else
          it_failed+=("brána ${gate}: selhala (exit ${code}), důvod: ${reason}")
        fi
        ;;
      waived)
        it_waived+=("brána ${gate}: prominuta — PM převzal riziko$(_aid_gos_waiver_detail "$waiver_dir" "$gate")")
        ;;
      skip)
        it_not_run+=("brána ${gate} neběžela: přeskočena"); n_not_run=$(( n_not_run + 1 )) ;;
      profile_excluded)
        it_not_run+=("brána ${gate} neběžela: mimo profil"); n_not_run=$(( n_not_run + 1 )) ;;
      pass)
        n_pass=$(( n_pass + 1 ))
        if [[ "$att" =~ ^[0-9]+$ ]] && (( att > 1 )); then
          it_passed+=("brána ${gate}: prošla až na ${att}. pokus${cmd:+ — ověřila: ${cmd}}")
        else
          it_passed+=("brána ${gate}: prošla${cmd:+ — ověřila: ${cmd}}")
        fi
        ;;
    esac
  #
  # `select(.name != null)` is load-bearing: an entry with no `name` makes jq
  # fail while building an object key, and this jq runs inside a process
  # substitution where its failure is invisible — the loop would simply receive
  # nothing and every counter would come out zero over a run that passed.
  #
  # Every value is stripped of U+001F before it is joined. `@tsv` escapes tabs,
  # newlines and backslashes but not this character, so a gate name carrying one
  # would otherwise forge a field boundary and be read as a different category.
  done < <(jq -r --argjson rep "$report" --argjson w "$waived_json" '
      def clean: (. // "") | tostring | gsub("\u001f"; " ");
      (($rep._command_log // []) | map(select(.name != null)) | map({(.name|tostring): .command}) | add // {}) as $cmds
      | .[]
      | [ ((.gate // "?")|clean),
          ((.result // "?")|clean),
          ((.exit_code // 0)|tostring|clean),
          ((.attempts // 0)|tostring|clean),
          (.reason|clean),
          (.waiver_rejected|clean),
          (if ((.gate // "") as $g | $w | index($g)) then "1" else "0" end),
          ($cmds[((.gate // "")|tostring)]|clean)
        ] | @tsv' <<<"$rows" | tr '\t' '\037')

  # A waiver named ONLY by top-level waived_gates[] (no matching row) still
  # renders — the absence of a row is never allowed to hide risk acceptance.
  # The orphans are computed in ONE jq rather than one per waived name.
  local w
  while IFS= read -r w; do
    [[ -n "$w" ]] || continue
    it_waived+=("brána ${w}: prominuta — PM převzal riziko$(_aid_gos_waiver_detail "$waiver_dir" "$w")")
  done < <(jq -r --argjson rows "$rows" \
    '([$rows[] | select(.result == "waived") | .gate]) as $have | .[] | select(. as $g | $have | index($g) | not)' \
    <<<"$waived_json")

  local -a core_items=()
  core_items+=("${it_failed[@]+"${it_failed[@]}"}")
  core_items+=("${it_waived[@]+"${it_waived[@]}"}")
  core_items+=("${it_not_run[@]+"${it_not_run[@]}"}")
  core_items+=("${it_passed[@]+"${it_passed[@]}"}")

  (( escalated == 1 )) && core_items+=("eskalace targeted → full: $(jq -r '.escalation.reason // "bez uvedeného důvodu"' <<<"$report")")
  (( total == 0 )) && core_items+=("profil nespustil žádnou bránu, takže se nic neověřilo")

  local items_json
  items_json="$(printf '%s\n' "${core_items[@]+"${core_items[@]}"}" | jq -R . | jq -sc 'map(select(. != ""))')"

  # ── the first failing gate and its reproduction command ───────────────────
  # Taken from the classification above, not re-derived: "the first REAL
  # failure" is precisely the first thing that loop put in `failed_gates`, and
  # asking jq the same question a second way is how the card and the list start
  # naming different gates.
  local first_fail="" first_fail_code repro=""
  (( ${#failed_gates[@]} > 0 )) && first_fail="${failed_gates[0]}"
  first_fail_code="$(jq -r --arg g "$first_fail" '[.[] | select(.gate == $g) | (.exit_code // 0)] | first // 0' <<<"$rows")"
  if [[ -n "$first_fail" ]]; then
    # The gate's OWN command, taken from the report's _command_log. Gate
    # definitions carry no remediation field anywhere in this repo, so the
    # reproduction step is the command itself — never an invented fix.
    repro="$(jq -r --arg g "$first_fail" '[(._command_log // [])[] | select(.name == $g) | .command] | first // ""' <<<"$report")"
  fi

  # A COMMAND MAY NEVER STAND BESIDE "nothing is expected" (PM, 2026-08-25).
  # A run that is not blocked asks nothing of the PM — the controller advances
  # on its own — so the list is EMPTY and block 6 says so. The renderer refuses
  # the contradiction outright (P089 Step 2), so this is enforced, not asked for.
  local -a next_steps=()
  if (( blocked == 1 )); then
    [[ -n "$repro" ]] && next_steps+=("Zopakuj bránu: ${repro}")
    next_steps+=("Oprav příčinu a spusť brány znovu")
    next_steps+=("Nebo převezmi riziko: ${_AID_GOS_FORCE_CMD}")
  fi
  local next_json
  next_json="$(printf '%s\n' "${next_steps[@]+"${next_steps[@]}"}" | jq -R . | jq -sc 'map(select(. != ""))')"

  # ── prose, computed — no model text at this boundary ───────────────────────
  # Every sentence below is composed from the same four counters the tiles are
  # composed from, so the page cannot disagree with itself.
  local p_summary p_core p_ask
  if (( n_failed > 0 )); then
    p_summary="Selhalo ${n_failed} z ${total} bran, běh je zastavený před DONE."
  elif (( blocked == 1 )); then
    p_summary="Neselhala žádná brána, ale běh je zastavený: ${n_not_run} bran neproběhlo, takže verdikt zůstal fail."
  elif (( total == 0 )); then
    p_summary="Profil nespustil žádnou bránu, takže se nic neověřilo a není co blokovat."
  elif (( n_pass == 0 )); then
    p_summary="Neselhalo nic, ale ani se nic neověřilo: všech ${n_not_run} bran neběželo."
  else
    p_summary="Ověřeno ${n_pass} z ${total} bran, nic neselhalo."
  fi
  p_core="Ověřeno ${n_pass}, selhalo ${n_failed}, neběželo ${n_not_run}, prominuto ${n_waived}. Celkem ${duration_human}."
  if (( blocked == 1 )); then
    p_ask="Rozhodni, jestli příčinu opravíme, nebo jestli riziko přebíráš. Doporučuju opravit — prominutá brána není ověřená. Dokud nerozhodneš, běh stojí před DONE."
  elif (( n_waived > 0 )); then
    p_ask="Nerozhoduješ nic. Jen ať víš, že ${n_waived} z bran prošlo tvojí výjimkou, ne testem."
  else
    p_ask=""
  fi

  # ── facts + render ────────────────────────────────────────────────────────
  local out_path="${run_dir}/${_AID_GOS_ARTIFACT_BASENAME}"
  local facts prose
  # The result, "verified" and "did not run" tiles are NOT written here: the
  # renderer composes them from the four counts below, which is what makes a
  # headline like "6/9 passed" beside zero failures impossible rather than
  # merely discouraged. Blocks 5 and 7 carry NAMES: the report path lives in
  # the provenance footer, where it already was, and nowhere else — it was on
  # this page three times.
  facts="$(jq -nc \
    --arg title "Brány: $(jq -r '.epic_id // "?"' <<<"$report")" \
    --arg when "$(jq -r '.completed_at // ._generated_at // "—"' <<<"$report")" \
    --arg dv "$duration_human" \
    --argjson pass "$n_pass" \
    --argjson failed "$n_failed" \
    --argjson not_run "$n_not_run" \
    --argjson waived "$n_waived" \
    --argjson blocked "$blocked" \
    --argjson items "$items_json" \
    --argjson next "$next_json" \
    --arg report_path "$report_path" \
    '{
      artifact_type: "gates",
      eyebrow: "Výsledek bran",
      title: $title,
      when: $when,
      outcome: {
        passed_count: $pass,
        failed_count: $failed,
        not_run_count: $not_run,
        waived_count: $waived,
        blocked: ($blocked == 1)
      },
      tiles: {duration: {label: "Trvalo", value: $dv}},
      items: $items,
      next_steps: $next,
      detail: {label: "Technický detail běhu bran"},
      footer: ("Zdroj: " + $report_path + ". Vyrobil aid-gate-outcome-summary.sh.")
    }')" || { echo "aid_gate_outcome_render: failed to build facts" >&2; return 1; }

  prose="$(jq -nc --arg s "$p_summary" --arg c "$p_core" --arg a "$p_ask" \
    '{summary:$s, core:$c, ask:$a}')"

  # ── WHETHER THIS RUN OWES THE PM A PAGE AT ALL ────────────────────────────
  # PM, 2026-08-28: a page is owed when the plan is written and approved, at the
  # end of a milestone after every check — "PŘÍPADNĚ dříve, jen za předpokladu,
  # že se po mě chtějí nějaká rozhodnutí". Gates run many times per EPIC and a
  # passing run decides nothing: WAN produced 17 pages in two days for one the
  # PM wanted, and the gates page said, in its own ask block, "Nic — ozvu se, až
  # bude hotovo". A page that states it wants nothing should not have been made.
  #
  # So: gates render a page only when they BLOCK. The chat card below is printed
  # either way, so a passing run still reports — it just does not leave a page
  # nobody asked for. `AID_ARTIFACT_ALWAYS=1` restores the old behaviour for a
  # caller that genuinely wants the record (the test suite uses it).
  if (( ! blocked )) && [[ "${AID_ARTIFACT_ALWAYS:-0}" != "1" ]]; then
    echo "aid_gate_outcome_render: gates passed — no page rendered (nothing is being asked of the PM); the card below reports the run" >&2
    out_path=""
  fi

  local rc=0
  if [[ -n "$out_path" ]]; then
    aid_artifact_render outcome "$facts" "$prose" "$out_path" || rc=$?
    if (( rc != 0 )); then
      echo "aid_gate_outcome_render: artifact render failed (exit ${rc}) for ${out_path}" >&2
      return "$rc"
    fi
  fi

  # ── the chat card (communication.md shapes 1 and 3) ────────────────────────
  # The card does NOT pass through aid_artifact_render, so it does not inherit
  # that renderer's redaction. EVERY card value that comes from the report goes
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
  # No page, no Artifact line — a caller that publishes what this prints must
  # not be handed a path that was deliberately not written.
  [[ -n "$out_path" ]] && printf 'Artifact: %s\n' "$out_path"
  return 0
}
