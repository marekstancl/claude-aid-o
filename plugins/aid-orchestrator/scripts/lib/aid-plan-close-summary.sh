#!/usr/bin/env bash
# aid-plan-close-summary.sh — P080 Step 12.
#
# The PM's plan-final / close boundary, rendered DETERMINISTICALLY:
#
#   aid_plan_close_render <pm_decision_brief_json> <release_decision_json> \
#                         <plan_id> <out_dir>
#
#   stdout                 the chat card (Decision-required or Finished, per
#                          skills/communication.md — this file never defines a
#                          card shape, it fills the one defined there).
#   <out_dir>/plan-close-artifact.html
#                          the artifact BODY, via scripts/lib/aid-artifact-render.sh.
#
# WHY TWO INPUTS AND NOT ONE
#   The brief does NOT carry the SHA / tag / EPIC facts. `build_brief_payload()`
#   in scripts/aid-pm-brief.sh (the jq object at :116-133) emits exactly 14 keys
#   and none of them is a SHA; the labelled plan-final identity reaches only the
#   human `pm-summary.md` (build_brief_md, :250-265). So the card reads:
#
#     from the BRIEF   release_ready, merge_mode, blockers, waivers_applied,
#                      evidence_verification_status, evidence_verified_at_head,
#                      summary_for_pm, delivered_summary_ref
#     from RELEASE-DECISION → .release_decision.plan_summary
#                      reviewed_candidate_sha, approved_target_sha, target_ref,
#                      final_merge_sha, release_tag_status, epics[],
#                      plan_final_gates.{report,result}, specialist_review,
#                      remaining_backlog
#                      (producer: scripts/aid-release-policy.sh:1107-1136,
#                      emitted in PLAN mode only — EPIC mode has plan_summary: null)
#
#   This is the SAME release-decision.json the brief was generated from, and NO
#   sibling evidence: the D6/D9 cycle-break aid-pm-brief.sh exists to enforce is
#   preserved — the presentation layer reads no more than the handoff pair.
#
# NUMBERS ARE COUNTED, NEVER ASSERTED
#   There is no EPIC total field. `epics | length` and the merged subset are
#   counted here from the array. There are no gate totals in this artifact
#   either: plan_summary carries ONE `plan_final_gates.result` verdict plus the
#   path to the report. This renderer shows the verdict and NAMES the report
#   path; it deliberately does not open that report, because doing so would
#   re-introduce the sibling-evidence read the cycle-break forbids.
#
# FAIL CLOSED, BOTH SHAPES — ON VALUES, NOT ON PRESENCE
#   A brief missing any one of the eight named fields, or carrying it as null /
#   the wrong type / an empty string; or a release-decision whose
#   `.release_decision.plan_summary` is absent, null, or present with dead
#   values — all exit 1 with the offending field NAMED on stderr. Presence
#   checks alone are not fail-closed: `has($k)` is satisfied by `null`, and a
#   summary of nine nulls rendered a confident, complete-looking page of
#   invented defaults. A degraded input therefore produces NO page at all rather
#   than a page that looks complete with em dashes where the SHAs should be.
#   The two fields whose null IS a state — `final_merge_sha` (nothing merged
#   yet) and `specialist_review` (did not run) — are exempt by name, plus
#   `delivered_summary_ref` on the brief side.
#
# TAG VOCABULARY — `not_tagged` (the default until the release step runs) /
#   `none` / `v<version>`. There is no `tagged` and no `pending`; the tile shows
#   the field verbatim and invents nothing.
#
# THE OPTION SET IS DERIVED, NOT READ
#   The brief has no `options` field. The offered options come from
#   `merge_mode` + `release_ready` + whether `final_merge_sha` is null, and are
#   reduced to the three commands this HEAD actually ships (verified in
#   scripts/aid-plan-fsm.sh):
#     plan-merge-to-main <plan_id> --decision <path>   (:7006)
#     plan-close <plan_id>                             (:7884)
#     plan-rollback <plan_id> --revert-commit <sha> [--reason <text>]  (:10149)
#   Rollback is offered ONLY when final_merge_sha is non-null — the revert
#   commit has no other source in these inputs, so while it is null the card
#   says the option is not applicable instead of printing an uninvocable
#   command. There is no plan-level defer command and no abandon command:
#   "defer" is expressed as TAKING NO ACTION (the plan simply stays open) and is
#   never dressed up as an invocation.
#
# TESTABILITY BOUNDARY, STATED EXPLICITLY
#   This file produces text on stdout and a body on disk. It never publishes.
#   Publication through the Artifact tool is a live, session-level act owned by
#   the controller instruction (commands/aid-plan.md, skills/pipeline.md §7.6),
#   and nothing here claims to cover it.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_APCS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-artifact-render.sh
source "${_APCS_LIB_DIR}/aid-artifact-render.sh"

# The eight fields the brief MUST carry, from build_brief_payload
# (scripts/aid-pm-brief.sh:116-133):
#
#   release_ready  merge_mode  blockers  waivers_applied
#   evidence_verification_status  evidence_verified_at_head
#   summary_for_pm  delivered_summary_ref
#
# Validated in aid_plan_close_render by VALUE, next to the message each failure
# produces — "brief malformed" is not an actionable message.

# The nine plan_summary fields this renderer READS, from the producer's field
# set (scripts/aid-release-policy.sh:1107-1136):
#
#   reviewed_candidate_sha  approved_target_sha  target_ref  release_tag_status
#   final_merge_sha  epics  plan_final_gates  specialist_review
#   remaining_backlog
#
# They are validated in aid_plan_close_render, by VALUE and not merely by
# presence — the check lives next to the failure message it produces, and the
# reasoning for each field's rule is written there.

_APCS_NO_RISK="Žádná materiální nejistota — brief nevede žádné nevyřešené blokátory."
_APCS_ROLLBACK_NA="Vrácení zpět: není použitelné — plán zatím není mergnutý do main."
_APCS_DEFER="nedělat nic — plán zůstává otevřený, žádný příkaz se nespouští."

# _apcs_json <path> — echoes the file when it parses, fails otherwise.
_apcs_json() {
  [[ -f "$1" ]] || return 1
  jq -e '.' "$1" >/dev/null 2>&1 || return 1
  cat "$1"
}

# _apcs_short <sha> — 12 chars, or the em dash when null/empty.
_apcs_short() {
  local s="${1:-}"
  if [[ -z "$s" || "$s" == "null" ]]; then printf '%s' "—"; else printf '%s' "${s:0:12}"; fi
}

# aid_plan_close_render <brief_json> <release_decision_json> <plan_id> <out_dir>
aid_plan_close_render() {
  local brief_path="${1-}" decision_path="${2-}" plan_id="${3-}" out_dir="${4-}"

  if [[ -z "$brief_path" || -z "$decision_path" || -z "$plan_id" || -z "$out_dir" ]]; then
    echo "aid_plan_close_render: usage: aid_plan_close_render <pm_decision_brief_json> <release_decision_json> <plan_id> <out_dir>" >&2
    return 1
  fi

  # ── input 1: the brief ────────────────────────────────────────────────────
  local brief_raw
  if ! brief_raw="$(_apcs_json "$brief_path")"; then
    echo "aid_plan_close_render: plan-close brief missing or unparseable at ${brief_path} — run aid-pm-brief.sh" >&2
    return 1
  fi
  # Accept the protocol-v2 envelope or a bare payload; the payload is the thing.
  local brief
  brief="$(jq -c '.pm_decision_brief // .' <<<"$brief_raw")" || return 1

  # By VALUE, for the same reason the plan_summary check below is: `has($k)` is
  # satisfied by `null`, and a null `summary_for_pm` reached the card as the
  # literal word "null" in the PM's summary line. The producer
  # (aid-pm-brief.sh's build_brief_payload, :116-133) defaults every one of
  # these, so a null here means the brief was not built by it.
  # `delivered_summary_ref` is the ONE field whose null is a real state (no
  # delivery ref recorded); it renders as the em dash. A boolean written as the
  # string "true"/"false" is accepted because the renderer compares the
  # stringified value either way — what is refused is null, the wrong shape and
  # the empty string.
  local missing=""
  missing="$(jq -r '
    def bad($k; $why): "\($k) (\($why))";
    def str_req($k): if (has($k) | not) then bad($k; "missing")
                     elif (.[$k] == null) then bad($k; "null")
                     elif ((.[$k] | type) != "string") then bad($k; "not a string")
                     elif ((.[$k] | length) == 0) then bad($k; "empty")
                     else empty end;
    def bool_req($k): if (has($k) | not) then bad($k; "missing")
                      elif ((.[$k] | type) == "boolean") then empty
                      elif ((.[$k] | tostring) == "true" or (.[$k] | tostring) == "false") then empty
                      else bad($k; "not a true/false value") end;
    def arr_req($k): if (has($k) | not) then bad($k; "missing")
                     elif ((.[$k] | type) != "array") then bad($k; "not an array")
                     else empty end;
    if type != "object" then ["brief (not an object)"]
    else
      [ bool_req("release_ready"),
        str_req("merge_mode"),
        arr_req("blockers"),
        arr_req("waivers_applied"),
        str_req("evidence_verification_status"),
        bool_req("evidence_verified_at_head"),
        str_req("summary_for_pm"),
        (if (has("delivered_summary_ref") | not) then bad("delivered_summary_ref"; "missing")
         else empty end) ]
    end | join(", ")' <<<"$brief" 2>/dev/null)" || missing="brief (unreadable)"
  if [[ -n "$missing" ]]; then
    echo "aid_plan_close_render: brief at ${brief_path} is missing required field(s): ${missing} — refusing to render a page that would look complete" >&2
    return 1
  fi

  # ── input 2: the release decision this brief was generated from ───────────
  local decision_raw
  if ! decision_raw="$(_apcs_json "$decision_path")"; then
    echo "aid_plan_close_render: release-decision.json missing or unparseable at ${decision_path} — the SHA/tag/EPIC facts have no other source" >&2
    return 1
  fi
  local ps
  ps="$(jq -c '.release_decision.plan_summary // empty' <<<"$decision_raw" 2>/dev/null)"
  if [[ -z "$ps" || "$ps" == "null" ]]; then
    echo "aid_plan_close_render: ${decision_path} carries no .release_decision.plan_summary (EPIC-mode decisions have plan_summary: null) — refusing to render a plan-close page without plan-final facts" >&2
    return 1
  fi

  # Present is not the same as populated, and `has()` cannot tell them apart:
  # all nine keys with `null` values, `epics: []` and `plan_final_gates: {}`
  # satisfied a has()-only check and then rendered a confident "Připraveno k
  # uzavření" page whose SHAs were em dashes, whose tag was the invented
  # `not_tagged` and whose gate verdict was the invented `unknown`. So each
  # field is checked against the VALUE this renderer actually depends on:
  #
  #   4 identity strings — non-null, non-empty. The producer always writes them
  #     (aid-release-policy.sh:1107-1136); null means the decision was built
  #     from an incomplete manifest, not that the plan has no identity.
  #   final_merge_sha — null is LEGITIMATE (nothing merged yet) but a present
  #     value must be a non-empty string, because it is interpolated into the
  #     rollback command this card offers.
  #   specialist_review — null is LEGITIMATE and renders as "neproběhl".
  #   epics / remaining_backlog — arrays; `epics: "none"` counted zero EPIKŮ
  #     just as silently as a missing key.
  #   plan_final_gates — an object that CARRIES ITS VERDICT: `{}` is not a gate
  #     result, it is the absence of one, and "unknown" is this file's default,
  #     never the report's word.
  local ps_missing=""
  ps_missing="$(jq -r '
    def bad($k; $why): "\($k) (\($why))";
    def str_req($k): if (has($k) | not) then bad($k; "missing")
                     elif (.[$k] == null) then bad($k; "null")
                     elif ((.[$k] | type) != "string") then bad($k; "not a string")
                     elif ((.[$k] | length) == 0) then bad($k; "empty")
                     else empty end;
    if type != "object" then ["plan_summary (not an object)"]
    else
      [ str_req("reviewed_candidate_sha"),
        str_req("approved_target_sha"),
        str_req("target_ref"),
        str_req("release_tag_status"),
        (if (has("final_merge_sha") | not) then bad("final_merge_sha"; "missing")
         elif (.final_merge_sha != null)
              and (((.final_merge_sha | type) != "string") or ((.final_merge_sha | length) == 0))
         then bad("final_merge_sha"; "present but not a usable sha") else empty end),
        (if (has("specialist_review") | not) then bad("specialist_review"; "missing") else empty end),
        (if (has("epics") | not) then bad("epics"; "missing")
         elif ((.epics | type) != "array") then bad("epics"; "not an array") else empty end),
        (if (has("remaining_backlog") | not) then bad("remaining_backlog"; "missing")
         elif ((.remaining_backlog | type) != "array") then bad("remaining_backlog"; "not an array")
         else empty end),
        (if (has("plan_final_gates") | not) then bad("plan_final_gates"; "missing")
         elif ((.plan_final_gates | type) != "object") then bad("plan_final_gates"; "not an object")
         elif ((.plan_final_gates.result // "") | tostring | length) == 0
         then bad("plan_final_gates.result"; "no verdict — the page would invent \"unknown\"")
         elif ((.plan_final_gates | has("report")) | not)
         then bad("plan_final_gates.report"; "missing") else empty end) ]
    end | join(", ")' <<<"$ps" 2>/dev/null)" || ps_missing="plan_summary (unreadable)"
  if [[ -n "$ps_missing" ]]; then
    echo "aid_plan_close_render: ${decision_path} plan_summary is missing required field(s): ${ps_missing} — refusing to render a page that would look complete with invented defaults" >&2
    return 1
  fi

  # ── brief facts ───────────────────────────────────────────────────────────
  local release_ready merge_mode ev_status ev_at_head summary_for_pm delivered_ref waivers_n
  release_ready="$(jq -r '.release_ready | tostring' <<<"$brief")"
  merge_mode="$(jq -r '.merge_mode | tostring' <<<"$brief")"
  ev_status="$(jq -r '.evidence_verification_status | tostring' <<<"$brief")"
  ev_at_head="$(jq -r '.evidence_verified_at_head | tostring' <<<"$brief")"
  summary_for_pm="$(jq -r '.summary_for_pm | tostring' <<<"$brief")"
  delivered_ref="$(jq -r '.delivered_summary_ref // "—" | tostring' <<<"$brief")"
  waivers_n="$(jq -r '(.waivers_applied // []) | length' <<<"$brief")"

  # Blockers, as readable lines. Objects carry input_id + reason (see
  # defaults/schemas/release-decision.schema.json); a bare string is honoured too.
  local blockers_json blockers_n
  blockers_json="$(jq -c '(.blockers // []) | map(if type == "object"
        then ((.input_id // "blocker") + ": " + (.reason // "bez uvedeného důvodu"))
        else tostring end)' <<<"$brief")"
  blockers_n="$(jq -r 'length' <<<"$blockers_json")"

  # ── plan_summary facts ────────────────────────────────────────────────────
  local cand_sha target_sha target_ref merge_sha tag_status gates_result gates_report
  cand_sha="$(jq -r '.reviewed_candidate_sha // "" | tostring' <<<"$ps")"
  target_sha="$(jq -r '.approved_target_sha // "" | tostring' <<<"$ps")"
  target_ref="$(jq -r '.target_ref // "" | tostring' <<<"$ps")"
  merge_sha="$(jq -r 'if .final_merge_sha == null then "" else (.final_merge_sha | tostring) end' <<<"$ps")"
  tag_status="$(jq -r '.release_tag_status // "not_tagged" | tostring' <<<"$ps")"
  gates_result="$(jq -r '.plan_final_gates.result // "unknown" | tostring' <<<"$ps")"
  gates_report="$(jq -r '.plan_final_gates.report // "" | tostring' <<<"$ps")"

  # EPIC totals are COUNTED from the array — there is no total field to trust.
  local epics_total epics_merged epics_skipped backlog_n
  epics_total="$(jq -r '(.epics // []) | length' <<<"$ps")"
  epics_merged="$(jq -r '[(.epics // [])[] | select((.skipped // false) != true)] | length' <<<"$ps")"
  epics_skipped=$(( epics_total - epics_merged ))
  backlog_n="$(jq -r '(.remaining_backlog // []) | length' <<<"$ps")"

  local specialist
  specialist="$(jq -r 'if .specialist_review == null then "neproběhl"
                       elif (.specialist_review | type) == "object"
                       then (.specialist_review.status // .specialist_review.verdict // "zaznamenán" | tostring)
                       else (.specialist_review | tostring) end' <<<"$ps")"

  # ── card class ────────────────────────────────────────────────────────────
  # Decision-required when the plan is not release-ready, or the merge mode is
  # not the auto-merge value. Otherwise this is recording a completed close.
  local card_kind="finished"
  if [[ "$release_ready" != "true" || "$merge_mode" != "auto" ]]; then
    card_kind="decision"
  fi

  # ── the derived option set ────────────────────────────────────────────────
  local cmd_merge="aid-plan-fsm.sh plan-merge-to-main ${plan_id} --decision ${decision_path}"
  local cmd_close="aid-plan-fsm.sh plan-close ${plan_id}"
  local cmd_rollback=""
  [[ -n "$merge_sha" ]] && cmd_rollback="aid-plan-fsm.sh plan-rollback ${plan_id} --revert-commit ${merge_sha} --reason \"<důvod vrácení>\""

  # Each option is a LABEL plus (optionally) the exact invocation. The card
  # carries both — §14's "exact public command" rule lives there. The artifact's
  # "Jak pokračovat" list carries the LABEL only, deliberately: a full 40-hex
  # revert SHA trips aid-artifact-render.sh's high_entropy_blob detector and
  # would reach the page as <redacted:…>, i.e. an uninvocable command on a
  # shareable page. Plain steps on the page, exact commands in the card.
  local lab_a lab_b lab_c opt_a opt_b opt_c
  if [[ -n "$merge_sha" ]]; then
    # Already merged to main — the remaining decisions are close or revert.
    lab_a="uzavřít plán"           ; opt_a="${lab_a} — \`${cmd_close}\`"
    lab_b="vrátit merge zpět"      ; opt_b="${lab_b} — \`${cmd_rollback}\`"
    lab_c="${_APCS_DEFER}"         ; opt_c="${lab_c}"
  elif [[ "$release_ready" == "true" ]]; then
    lab_a="mergnout plán do main"  ; opt_a="${lab_a} — \`${cmd_merge}\`"
    lab_b="uzavřít plán bez merge" ; opt_b="${lab_b} — \`${cmd_close}\`"
    lab_c="${_APCS_DEFER}"         ; opt_c="${lab_c}"
  else
    lab_a="${_APCS_DEFER}"         ; opt_a="${lab_a}"
    lab_b="mergnout plán do main i tak, na vlastní riziko"
    opt_b="${lab_b} — \`${cmd_merge}\`"
    lab_c="uzavřít plán bez merge" ; opt_c="${lab_c} — \`${cmd_close}\`"
  fi

  # Why now — implied by release_ready + merge_mode, never invented.
  local why
  if [[ -n "$merge_sha" ]]; then
    why="Merge do main je hotový ($(_apcs_short "$merge_sha")), ale plán je pořád otevřený — dokud ho nezavřeš, drží worktree a větev."
  elif [[ "$release_ready" == "true" && "$merge_mode" == "manual" ]]; then
    why="Plán je připravený k merge, ale režim je manual — bez tvého rozhodnutí se nic nemergne."
  elif [[ "$release_ready" == "true" ]]; then
    why="Plán je připravený k merge (režim ${merge_mode}) — čeká jen na potvrzení."
  elif [[ "$merge_mode" == "blocked" ]]; then
    why="Plán NENÍ připravený k release a režim je blocked (${blockers_n} blokátorů) — merge by přenesl neuzavřené nálezy do main."
  else
    why="Plán NENÍ připravený k release (${blockers_n} blokátorů, režim ${merge_mode}) — merge by přenesl neuzavřené nálezy do main."
  fi

  local risk
  if (( blockers_n > 0 )); then
    risk="$(jq -r '.[0:5] | join("; ")' <<<"$blockers_json")"
    (( blockers_n > 5 )) && risk+="; $(_aid_artifact_overflow "$(( blockers_n - 5 ))")"
  else
    risk="$_APCS_NO_RISK"
  fi

  # ── artifact facts: everything computed above, nothing restated ───────────
  local result_value result_state unresolved_state
  if [[ "$card_kind" == "finished" ]]; then
    result_value="Připraveno k uzavření"; result_state="ok"
  elif [[ "$merge_mode" == "blocked" ]]; then
    result_value="Blokováno"; result_state="critical"
  else
    result_value="Čeká na rozhodnutí"; result_state="warn"
  fi
  if (( blockers_n > 0 )); then unresolved_state="critical"; else unresolved_state="ok"; fi

  local items_json next_json links_json
  items_json="$(jq -n \
    --arg cand "$(_apcs_short "$cand_sha")" \
    --arg tgt "$(_apcs_short "$target_sha")" \
    --arg tref "${target_ref:-—}" \
    --arg merge "$(_apcs_short "$merge_sha")" \
    --arg gres "$gates_result" \
    --arg grep_ "${gates_report:-—}" \
    --arg spec "$specialist" \
    --arg ev "$ev_status" --arg evh "$ev_at_head" \
    --arg wv "$waivers_n" --arg bl "$backlog_n" '[
      "Recenzovaný kandidát: " + $cand + " → schválený cíl " + $tgt + " (" + $tref + ")",
      "Merge do main: " + $merge,
      "Plan-final brány: " + $gres + " (report: " + $grep_ + ")",
      "Specialistická revize: " + $spec,
      "Evidence: " + $ev + " (ověřeno na HEAD: " + $evh + "), waiverů " + $wv + ", zbývá v backlogu " + $bl
    ]')"

  if [[ "$card_kind" == "finished" ]]; then
    next_json="$(jq -n --arg a "$lab_a" '[$a]')"
  else
    next_json="$(jq -n --arg a "$lab_a" --arg b "$lab_b" --arg c "$lab_c" '[$a, $b, $c]')"
  fi

  links_json="$(jq -n --arg g "$gates_report" --arg d "$delivered_ref" '
    [ (if ($g | length) > 0 then "Report plan-final bran: " + $g else empty end),
      (if $d != "—" and ($d | length) > 0 then "Dodané shrnutí: " + $d else empty end) ]')"

  local facts_json
  facts_json="$(jq -n \
    --arg plan "$plan_id" \
    --arg when "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg rv "$result_value" --arg rs "$result_state" \
    --arg tag "$tag_status" \
    --arg scope "${epics_merged}/${epics_total} EPIKŮ" \
    --arg scope_state "$([[ "$epics_skipped" -eq 0 ]] && echo ok || echo warn)" \
    --arg unres "$blockers_n" --arg us "$unresolved_state" \
    --argjson items "$items_json" \
    --argjson next "$next_json" \
    --argjson links "$links_json" \
    --arg brief "$brief_path" --arg dec "$decision_path" '{
      eyebrow: "Uzávěrka plánu",
      title: ("Plán " + $plan + " — plan-final boundary"),
      when: $when,
      tiles: {
        result:     {value: $rv, state: $rs},
        duration:   {label: "Tag", value: $tag},
        scope:      {label: "EPIKY", value: $scope, state: $scope_state},
        unresolved: {label: "Blokátory", value: $unres, state: $us}
      },
      items: $items,
      next_steps: $next,
      links: $links,
      detail: {label: ("Technický detail: " + $brief + " + " + $dec)},
      footer: ("Vyrobil aid-plan-close-summary.sh z " + $brief + " a " + $dec + ".")
    }')" || {
    echo "aid_plan_close_render: failed to build facts" >&2
    return 1
  }

  local prose_json
  if [[ "$card_kind" == "finished" ]]; then
    prose_json="$(jq -n --arg s "$summary_for_pm" --arg c "$why" '{summary: $s, core: $c, ask: ""}')"
  else
    prose_json="$(jq -n --arg s "$summary_for_pm" --arg c "$why" --arg a "$lab_a" \
      '{summary: $s, core: $c, ask: ("Rozhodni, jak plán uzavřít. Doporučení: " + $a)}')"
  fi

  mkdir -p "$out_dir" 2>/dev/null
  local out_path="${out_dir}/plan-close-artifact.html"
  local rc=0
  aid_artifact_render outcome "$facts_json" "$prose_json" "$out_path" || rc=$?
  if (( rc != 0 )); then
    echo "aid_plan_close_render: artifact body not written to ${out_path} (renderer exit ${rc})" >&2
    return "$rc"
  fi

  # ── the chat card (skeletons defined in skills/communication.md) ──────────
  # The card does NOT pass through aid_artifact_render and so does not inherit
  # its redaction. EVERY card value carrying free text an input wrote goes
  # through the same detector table here — not just `risk` (the brief's blocker
  # reasons), but the gate REPORT PATH, the gate verdict, the tag status and the
  # two evidence-verification fields, all of them verbatim passthroughs of
  # decision/brief strings, and `why`, which interpolates the brief's
  # `merge_mode`. Redacting one of them was the same leak in a smaller hole.
  # The remaining card values are counts this file computed and the plan_id it
  # was handed.
  #
  # The OPTION lines are deliberately left alone: they carry a 40-hex revert
  # SHA, which the high_entropy_blob detector would blur into an uninvocable
  # command — the same reason the page carries labels only.
  #
  # This runs AFTER the artifact render on purpose: the page renders from the
  # unredacted values and does its own redaction (and its own counting) inside
  # aid_artifact_render.
  local _card_redactions=0
  _aid_artifact_redact risk         _card_redactions
  _aid_artifact_redact gates_report _card_redactions
  _aid_artifact_redact gates_result _card_redactions
  _aid_artifact_redact tag_status   _card_redactions
  _aid_artifact_redact ev_status    _card_redactions
  _aid_artifact_redact ev_at_head   _card_redactions
  _aid_artifact_redact why          _card_redactions

  if [[ "$card_kind" == "finished" ]]; then
    printf 'Hotovo: plán %s je připravený k uzavření.\n' "$plan_id"
    printf 'Změnilo se: %s z %s EPIKŮ je v plánu, merge do main %s, tag %s.\n' \
      "$epics_merged" "$epics_total" "$(_apcs_short "$merge_sha")" "$tag_status"
    printf 'Ověřeno: plan-final brány %s (report %s); evidence %s, ověřeno na HEAD: %s.\n' \
      "$gates_result" "${gates_report:-—}" "$ev_status" "$ev_at_head"
    printf 'Další krok: %s\n' "$opt_a"
  else
    printf 'Potřebuji tvoje rozhodnutí: jak uzavřít plán %s?\n' "$plan_id"
    printf 'Proč teď: %s\n' "$why"
    printf 'Doporučení: A — %s\n' "$opt_a"
    printf 'Alternativy: B — %s; C — %s\n' "$opt_b" "$opt_c"
    [[ -n "$merge_sha" ]] || printf '%s\n' "$_APCS_ROLLBACK_NA"
    printf 'Riziko / co není ověřeno: %s\n' "$risk"
  fi
  printf 'Artifact body: %s\n' "$out_path"
  return 0
}
