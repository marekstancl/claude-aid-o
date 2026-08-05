#!/usr/bin/env bash
# aid-test-audit-chat-summary.sh — P066 Step 15.
#
# Renders the mandatory SIX-part plain-language chat message — P072 Step 19.
#
# THE ORDER IS THE POINT
#   1. What to do now
#   2. What to fix, merge, split or remove
#   3. What can run in parallel
#   4. What must remain serial
#   5. Test time now, and after the proposed work
#   6. What is not proved yet
#   + Technical evidence (appendix)
#
#   The five-part predecessor led with a verdict and a severity-ranked list of
#   findings, so a reader met the evidence before the decision and had to
#   assemble the answer themselves. A test-portfolio audit exists to answer
#   "what should I do about my tests"; that answer goes first, and the
#   evidence goes in an appendix underneath it.
#
#   Sections 2-6 render the NAMED ID SETS from the decision artifact — keep,
#   rewrite_unit, merge_groups, remove, lanes, unresolved — rather than a
#   top-five list. Five findings ranked by severity tell a reader what is
#   loudest, not what is left to do.
#
# EVERY HEADING ALWAYS RENDERS
#   Including when its section is empty, with an explicit statement of that.
#   A missing heading reads as an omission; "nothing here" is a finding and
#   has to be said.
#
# Verdict classification remains a PURE FUNCTION of the artifacts —
# reproducible, never an LLM judgment call.
#
# Testability boundary, stated explicitly: this renderer's OUTPUT TEXT is
# ordinary, deterministic code — fully Bats-testable. The controller's act of
# presenting that text as the session's actual final turn is a live,
# session-level behavior verified once at release (Step 24 Part B), never
# claimed as covered by this script's own test suite.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_TACS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-test-adapter-contract.sh
source "${_TACS_LIB_DIR}/aid-test-adapter-contract.sh"
# shellcheck source=aid-test-audit-write-plan-bridge.sh
source "${_TACS_LIB_DIR}/aid-test-audit-write-plan-bridge.sh"
# shellcheck source=aid-test-audit-config.sh
source "${_TACS_LIB_DIR}/aid-test-audit-config.sh"
# shellcheck source=aid-test-audit-decision.sh
source "${_TACS_LIB_DIR}/aid-test-audit-decision.sh"
_TACS_FINDINGS_SCHEMA="${_TACS_LIB_DIR}/../../defaults/schemas/test-audit-consolidated-findings.schema.json"

# _tacs_classify_verdict <findings_json>
#   Pure function: "remediation recommended" if any Medium+ finding
#   recommends fix/split/merge/remove/quarantine; else "needs measurement"
#   if any finding recommends "measure" (inconclusive without real data);
#   else "clean". A static-mode-only run can still reach "remediation
#   recommended" from static analysis alone.
_tacs_classify_verdict() {
  local findings_json="$1"
  local has_actionable has_measure
  has_actionable="$(jq -r '
    [.[] | select(.severity != "low" and (.recommendation | IN("fix","split","merge","remove","quarantine")))] | length > 0
  ' <<<"$findings_json")"
  if [[ "$has_actionable" == "true" ]]; then
    echo "remediation recommended"
    return 0
  fi
  has_measure="$(jq -r '[.[] | select(.recommendation == "measure")] | length > 0' <<<"$findings_json")"
  if [[ "$has_measure" == "true" ]]; then
    echo "needs measurement"
    return 0
  fi
  echo "clean"
}

# aid_test_audit_render_chat_summary <consolidated_findings_path> [changed_text]
#   Echoes the 5-part message. A missing/malformed findings file produces an
#   explicit "audit did not complete cleanly" statement, never a fabricated
#   "clean" verdict.
aid_test_audit_render_chat_summary() {
  local findings_path="$1" changed_text="${2:-nothing (no separately approved step ran)}"
  # P072 Step 3 — the mode the audit actually ran in, recorded into the
  # durable record so the write-plan bridge can refuse a caller that
  # relabels a full audit as `measure` to slip past the decision gate.
  local _tacs_audit_mode="${3-}"
  # P072 EPIC 1 correction — the decision artifact, for full-mode audits. The
  # renderer used to classify from findings ALONE, so an audit whose decision
  # said `incomplete` but whose findings happened to be empty was rendered to
  # the user as "Verdict: clean". Without --write-plan the bridge never runs,
  # so nothing downstream corrected it: the user was told the portfolio was
  # healthy while units had gone undecided. `incomplete` therefore outranks
  # findings classification here, at the only place the user actually reads.
  local _tacs_decision_path="${4-}"

  if [[ ! -f "$findings_path" ]]; then
    echo "**Audit did not complete cleanly** — no consolidated findings file was produced ($findings_path missing). This is not a clean result; something failed before consolidation."
    return 1
  fi

  local whole_doc
  whole_doc="$(jq -e '.' "$findings_path" 2>/dev/null)" || {
    echo "**Audit did not complete cleanly** — $findings_path is not valid JSON. This is not a clean result."
    return 1
  }

  # Schema-validate the WHOLE document before classification — Codex
  # review: a syntactically-valid-JSON-but-wrong-shape file (e.g.
  # findings: {} instead of an array) previously slipped past a bare
  # `.findings` extraction and was silently treated as empty, producing a
  # fabricated "clean" verdict over a corrupted/incompatible consolidation
  # output instead of failing closed.
  adapter_validate_schema "$_TACS_FINDINGS_SCHEMA" "$whole_doc" || {
    echo "**Audit did not complete cleanly** — $findings_path failed schema validation (test-audit-consolidated-findings.schema.json). This is not a clean result."
    return 1
  }

  local findings_json
  findings_json="$(jq -c '.findings' <<<"$whole_doc")"

  local verdict
  verdict="$(_tacs_classify_verdict "$findings_json")"

  # ─── incomplete outranks everything the findings say ──────────────────────
  local _tacs_incomplete="false" _tacs_reason="" _tacs_missing="" _tacs_next=""
  if [[ -n "$_tacs_decision_path" && -f "$_tacs_decision_path" ]]; then
    local _tacs_status
    _tacs_status="$(jq -r '.audit_status // empty' "$_tacs_decision_path" 2>/dev/null)" || _tacs_status=""
    if [[ "$_tacs_status" == "incomplete" ]]; then
      _tacs_incomplete="true"
      verdict="incomplete"
      _tacs_reason="$(jq -r '.incomplete_reason // "unspecified"' "$_tacs_decision_path" 2>/dev/null)"
      _tacs_missing="$(jq -r '
        (.portfolio_coverage.missing_run_unit_ids // []) as $m
        | if ($m | length) == 0 then "(none — the gap is not a missing unit)"
          else ($m[0:10] | join(", ")) + (if ($m|length) > 10 then " (+\(($m|length) - 10) more)" else "" end)
          end' "$_tacs_decision_path" 2>/dev/null)"
      _tacs_next="$(jq -r '
        if ((.unresolved // []) | length) > 0
        then (.unresolved[0].next_measurement // "re-run this audit with a larger budget")
        else "decide the units listed above, then re-run this audit" end' "$_tacs_decision_path" 2>/dev/null)"
    fi
  fi

  # 3-5 evidenced reasons: top findings by severity (critical>high>medium>low), then finding_id.
  local reasons_text
  reasons_text="$(jq -r '
    def sev_rank: {"critical":0,"high":1,"medium":2,"low":3}[.severity] // 4;
    [.[]] | sort_by([sev_rank, .finding_id]) | .[0:5] | to_entries |
    map("\(.key + 1). [\(.value.severity)] \(.value.category) on `\(.value.run_unit_id)` → \(.value.recommendation) (evidence: \(.value.evidence_refs | join(", ")))") |
    join("\n")
  ' <<<"$findings_json")"
  [[ -n "$reasons_text" ]] || reasons_text="(no findings to report)"

  local next_action
  if [[ "$_tacs_incomplete" == "true" ]]; then
    next_action="This audit is NOT finished — $_tacs_next. A remediation plan cannot be created from it (the --write-plan handoff refuses an incomplete audit)."
  else
  case "$verdict" in
    "remediation recommended")
      next_action="Reply \"vytvoř plán oprav\" (or run \`--write-plan\`) to generate a remediation plan from this audit's findings."
      ;;
    "needs measurement")
      next_action="Re-run with \`--mode measure\` (or \`--mode full\`) to get real measured data before deciding anything further."
      ;;
    *)
      next_action="No action needed."
      ;;
  esac
  fi

  local has_conflict residual_risk
  has_conflict="$(jq -r '[.[] | select(.unresolved_conflict == true)] | length > 0' <<<"$findings_json")"
  if [[ "$has_conflict" == "true" ]]; then
    residual_risk="One or more findings disagree with each other (unresolved_conflict) — this needs a PM decision on which to trust."
  else
    residual_risk="No PM decision required."
  fi

  # Persist the durable record for the same-conversation continuation /
  # --write-plan bridge (Codex review: this renderer previously had no
  # production caller of aid_test_audit_write_plan_bridge_persist, so a
  # normal completed audit never created durable-record.json and the
  # handoff could never be reached no matter how the audit concluded).
  #
  # PM whole-EPIC-3 review, real gap: this call's exit status was
  # previously discarded — a persist failure (e.g. an unwritable output_dir)
  # would still let this function print a successful-looking chat verdict
  # with no durable record behind it, silently breaking the handoff exactly
  # as badly as if this call never existed. Now fails closed: a persist
  # failure is a failed audit turn, never a "done" one.
  local audit_id
  audit_id="$(jq -r '.audit_id' <<<"$whole_doc")"
  if ! aid_test_audit_write_plan_bridge_persist "$(dirname "$findings_path")" "$audit_id" "$verdict" "$next_action" "$_tacs_audit_mode"; then
    # BOTH channels. This function's contract is that its stdout IS the
    # user-facing turn, so a failure explained only on stderr leaves the caller
    # presenting nothing — or worse, an earlier success-looking message.
    local _persist_msg="**Audit did not complete cleanly** — failed to persist the durable audit record (durable-record.json) for $findings_path. This is not a clean result; do not rely on it and do not attempt \`--write-plan\`, whose handoff cannot be reached without it."
    echo "$_persist_msg"
    echo "$_persist_msg" >&2
    return 1
  fi

  # ─── The six sections ─────────────────────────────────────────────────────
  #
  # `_d` is the decision artifact when there is one. Without it — a static or
  # measure audit — the sections that describe portfolio decisions say so
  # rather than rendering an empty set that would read as "nothing to do".
  local _d="" _have_decision="false"
  if [[ -n "$_tacs_decision_path" && -f "$_tacs_decision_path" ]]; then
    # VALIDATED, not merely present. A `{}` or wrong-shaped artifact used to
    # sail through: every jq query returned null, every null became an
    # affirmative default, and the reader was told "everything reached a
    # decision it can defend" over a file containing nothing at all.
    if aid_test_audit_decision_read "$_tacs_decision_path" >/dev/null 2>&1; then
      _d="$_tacs_decision_path"; _have_decision="true"
    else
      echo "**Audit did not complete cleanly** — the decision artifact at ${_tacs_decision_path} is invalid or incompatible (\`aid-test-audit-decision-v1\`). No decision, parallelization or proof-completeness claim can be made from it. Do not attempt \`--write-plan\`."
      return 1
    fi
  fi

  # A full audit OWES a decision artifact. Rendering one without it produced
  # "No action needed." over an audit that had decided nothing — the single
  # most misleading sentence this renderer can emit.
  if [[ "$_tacs_audit_mode" == "full" && "$_have_decision" != "true" ]]; then
    echo "**Audit did not complete cleanly** — a full audit requires a decision artifact and none was produced. Findings may exist below, but the portfolio decisions, the parallel-safety assessment and the remediation handoff are NOT established. Do not attempt \`--write-plan\`."
    return 1
  fi

  local max_ids=25
  if [[ "$_have_decision" == "true" ]]; then
    max_ids="$(test_audit_decision_key chat_render_max_ids "$(dirname "$(dirname "$_d")")" 2>/dev/null || echo 25)"
    [[ "$max_ids" =~ ^[0-9]+$ ]] || max_ids=25
  fi


  # _tacs_proposed_actions — the concrete remediation list, ranked and capped.
  # An audit emitting four hundred proposals has produced zero; the artifact
  # keeps everything, the render shows the top slice and says how many more
  # there are. Declined-previously rows are counted, never re-litigated.
  _tacs_proposed_actions() {
    local cap=15
    [[ -n "$_tacs_decision_path" && -f "$_tacs_decision_path" ]] || { echo "(no decision artifact)"; return 0; }
    jq -r --argjson cap "$cap" '
      ([.actions[]? | select(.change != null)]) as $props
      | ([$props[] | select(.declined_previously == true)]) as $declined
      | ([$props[] | select(.declined_previously != true)]
         | sort_by((["critical","high","medium","low"] | index(.priority)),
                   (if .impact.kind == "measured" then 0 elif .impact.kind == "estimated" then 1 else 2 end))) as $live
      | if ($props | length) == 0 then
          "No concrete remediation was proposed — findings that could not carry an honest change/benefit/effort stayed findings."
        else
          ( [ $live[:$cap][]
              | "- **" + .action + "** " + (.targets | join(", "))
                + (if .effort then " — effort " + .effort.bucket
                     + (if (.effort.repeat_count // 1) > 1 then " x" + (.effort.repeat_count|tostring) else "" end)
                     + (if .effort.verify_bucket then " (verify " + .effort.verify_bucket + ")" else "" end)
                   else "" end)
                + (if .impact.kind == "measured" and .impact.after_ms then ", saves ~" + ((.impact.after_ms/1000)|floor|tostring) + "s on the critical path (measured)"
                   elif .impact.kind == "estimated" and .impact.after_ms then ", ~" + ((.impact.after_ms/1000)|floor|tostring) + "s (estimated)"
                   elif .impact.kind == "unknown" then ", benefit unknown"
                   else "" end)
                + (if ((.conflicts_with // []) | length) > 0 then " — CONFLICTS with " + (.conflicts_with | join(", ")) else "" end)
                + "\n  " + (.change // .reason)
            ] | join("\n") )
          + (if ($live | length) > $cap then "\n- … and " + (($live | length) - $cap | tostring) + " more in decision.json" else "" end)
          + (if ($declined | length) > 0 then "\n- (" + ($declined | length | tostring) + " previously declined — kept in decision.json, not re-proposed)" else "" end)
        end
    ' "$_tacs_decision_path"
  }

  # _tacs_id_set <jq-path> <label> — the named set, truncated with an EXACT
  # remaining count and a path to the full list. A silent truncation would let
  # a reader act on a partial set believing it complete.
  _tacs_id_set() {
    local expr="$1" label="$2"
    [[ "$_have_decision" == "true" ]] || { printf -- '- %s: (requires a full audit)\n' "$label"; return 0; }
    # `--arg lbl`, not `--arg label`: `label` is a jq keyword, and binding it
    # made every one of these sets render as "(unreadable)".
    jq -r --argjson n "$max_ids" --arg lbl "$label" --arg path "$(basename "$_d")" "
      ($expr) as \$ids
      | if (\$ids | length) == 0 then \"- \" + \$lbl + \": none\"
        else \"- \" + \$lbl + \" (\" + ((\$ids|length)|tostring) + \"): \"
             + (\$ids[0:\$n] | join(\", \"))
             + (if (\$ids|length) > \$n
                then \" — and \" + (((\$ids|length) - \$n)|tostring) + \" more, in \" + \$path
                else \"\" end)
        end" "$_d" 2>/dev/null || printf -- '- %s: (unreadable)\n' "$label"
  }

  # Merge groups render GROUP BY GROUP. Flattening them into one id set turned
  # two separate two-unit merges into what reads as a single four-unit merge —
  # a different instruction, and an unsafe one to execute.
  _tacs_merge_groups() {
    [[ "$_have_decision" == "true" ]] || { printf -- '- Merge: (requires a full audit)\n'; return 0; }
    jq -r --argjson n "$max_ids" '
      (.portfolio_change.merge_groups // []) as $g
      | if ($g | length) == 0 then "- Merge: none"
        else ( ["- Merge (" + (($g|length)|tostring) + " group(s)):"]
               + ( $g[0:$n] | to_entries
                   | map("  - group " + ((.key + 1)|tostring) + ": " + (.value | join(", "))) )
               + ( if ($g|length) > $n
                   then ["  - and " + ((($g|length) - $n)|tostring) + " more group(s), in decision.json"]
                   else [] end ) ) | join("\n")
        end' "$_d" 2>/dev/null || printf -- '- Merge: (unreadable)\n'
  }

  # 1 — What to do now.
  local section_now
  if [[ "$_tacs_incomplete" == "true" ]]; then
    # A bounded next diagnostic action, never a suggestion to plan remediation.
    section_now="$(jq -r '
      if (.parallelization.smallest_safe_pilot // null) != null
      then "Run the smallest bounded pilot that would settle the most units: "
           + (.parallelization.smallest_safe_pilot.run_unit_ids | join(", "))
           + " (at " + ((.parallelization.smallest_safe_pilot.workers)|tostring) + " workers, repeated "
           + ((.parallelization.smallest_safe_pilot.repeat)|tostring) + " times)."
      elif ([.actions[] | select(.action == "measure")] | length) > 0
      then "Measure before deciding anything else: "
           + ([.actions[] | select(.action == "measure")] | sort_by(.priority) | .[0].reason)
      else "Decide the units listed as undecided below, then re-run this audit."
      end' "$_d" 2>/dev/null)"
    [[ -n "$section_now" ]] || section_now="Re-run this audit with a larger budget."
    section_now="This audit did NOT finish (\`audit_status: incomplete\` — ${_tacs_reason}). ${section_now}
A remediation plan cannot be created from it: the \`--write-plan\` handoff refuses an incomplete audit."
  else
    # When there IS a decision, the action comes from it — not from a
    # findings-severity classification that can contradict it. "No action
    # needed" printed directly above "Remove (1): bats:legacy" is one message
    # disagreeing with itself.
    local _proposed=""
    if [[ "$_have_decision" == "true" ]]; then
      _proposed="$(jq -r '
        [ (if ((.portfolio_change.remove // []) | length) > 0
           then "remove " + (((.portfolio_change.remove) | length)|tostring) + " unit(s)" else empty end),
          (if ((.portfolio_change.rewrite_unit // []) | length) > 0
           then "rewrite " + (((.portfolio_change.rewrite_unit) | length)|tostring) + " unit(s)" else empty end),
          (if ((.portfolio_change.merge_groups // []) | length) > 0
           then "merge " + (((.portfolio_change.merge_groups) | length)|tostring) + " group(s)" else empty end),
          (if ([.parallelization.lanes[]? | select(.disposition == "proposed_parallel")] | length) > 0
           then "adopt " + (([.parallelization.lanes[]? | select(.disposition == "proposed_parallel")] | length)|tostring) + " parallel lane(s)" else empty end)
        ] | join(", ")' "$_d" 2>/dev/null)"
    fi
    if [[ -n "$_proposed" ]]; then
      # The findings-derived next action is REPLACED, not appended: "No action
      # needed" trailing a list of proposed removals is the same contradiction
      # in a longer sentence.
      [[ "$next_action" == "No action needed." ]] \
        && next_action="Reply \"vytvoř plán oprav\" (or run \`--write-plan\`) to turn these into a remediation plan."
      section_now="This audit proposes: ${_proposed} — see section 2 for the exact units. ${next_action}"
      # The appendix verdict must not read `clean` next to an explicit change.
      [[ "$verdict" == "clean" ]] && verdict="remediation recommended"
    else
      section_now="${next_action}"
    fi
  fi

  # 5 — Test time, with the impact label attached so an estimate is never read
  # as a measurement.
  local section_time
  if [[ "$_have_decision" == "true" ]]; then
    section_time="$(jq -r '
      (.portfolio_change.runtime_before_ms) as $b
      | (.portfolio_change.runtime_after_ms) as $a
      | (.portfolio_change.impact_kind // "unknown") as $k
      | if $b == null and $a == null
        then "Not measured. No before-and-after figure was produced by this audit."
        else "Now: " + (if $b == null then "not measured" else (($b/1000)|floor|tostring) + "s" end)
             + " — after the proposed work: "
             + (if $a == null then "not projected" else (($a/1000)|floor|tostring) + "s" end)
             + " (" + $k + ")"
             + (if $k == "estimated" then " — an ESTIMATE, not a measured saving." else "" end)
        end' "$_d" 2>/dev/null)"
    if [[ "$_tacs_incomplete" == "true" && "$section_time" != "Not measured."* ]]; then
      section_time="${section_time}
NOT a decision-grade portfolio figure: this audit is incomplete, so the \"after\" side describes work that was never fully decided."
    fi
  else
    section_time="Not measured. A full audit is required to produce a before-and-after figure."
  fi
  [[ -n "$section_time" ]] || section_time="Not measured."

  # The units this audit never decided. `_tacs_missing` was computed and then
  # never rendered, so the text said "decide the units listed above" with no
  # such list anywhere.
  local _tacs_undecided_line=""
  if [[ "$_tacs_incomplete" == "true" && -n "$_tacs_missing" ]]; then
    _tacs_undecided_line="
**Undecided — no disposition was reached for these:** ${_tacs_missing}
Treat every one of them as unexamined, not as healthy."
  fi

  # 6 — What is not proved yet.
  local section_unproved
  if [[ "$_have_decision" == "true" ]]; then
    section_unproved="$(jq -r '
      ([ .unresolved[]? | "- " + .run_unit_id + ": " + (.missing_proof // "unstated")
                          + " — next: " + (.next_measurement // "unstated") ]
       + [ .portfolio_change.keep[]? | select(. != null) | empty ]) as $lines
      | if ($lines | length) == 0 then "Everything this audit examined reached a decision it can defend."
        else ($lines | join("\n")) end' "$_d" 2>/dev/null)"
  else
    section_unproved="This audit did not produce a decision artifact, so nothing here is proved to the standard a full audit applies."
  fi
  [[ -n "$section_unproved" ]] || section_unproved="Everything this audit examined reached a decision it can defend."

  # 3/4 — Lanes.
  local section_parallel section_serial
  if [[ "$_have_decision" == "true" ]]; then
    section_parallel="$(jq -r '
      [ .parallelization.lanes[]? | select(.disposition == "proposed_parallel") ] as $l
      | if ($l | length) == 0
        then "Nothing is proposed to run in parallel on current evidence."
        else ($l | map("- " + .lane_id + ": " + (.run_unit_ids | join(", "))
                       + " (evidence: " + ((.evidence_refs // []) | join(", ")) + ")") | join("\n"))
        end' "$_d" 2>/dev/null)"
    section_serial="$(jq -r '
      [ .parallelization.lanes[]? | select(.disposition != "proposed_parallel") ] as $l
      | if ($l | length) == 0
        then "Nothing was found that must stay serial."
        else ($l | map("- " + (.run_unit_ids | join(", ")) + " — " + .disposition
                       + (if ((.resource_basis // []) | length) > 0
                          then " (" + (.resource_basis | join(", ")) + ")" else "" end)) | join("\n"))
        end' "$_d" 2>/dev/null)"
  else
    section_parallel="Not assessed. Parallel safety requires a full audit."
    section_serial="Not assessed. Parallel safety requires a full audit."
  fi

  # 2 — The portfolio sets, plus the exact no-removal sentence.
  local removal_line=""
  if [[ "$_have_decision" == "true" ]]; then
    if [[ "$(jq -r '(.portfolio_change.remove // []) | length' "$_d" 2>/dev/null)" == "0" ]]; then
      removal_line="No test is recommended for removal on current evidence."
    fi
  fi

  # An incomplete audit's later sections are PROVISIONAL. Rendering them
  # unlabelled presented a partial result as an instruction set: `Remove (1):
  # legacy-suite` under an audit that never finished deciding reads exactly
  # like one that did.
  local provisional=""
  if [[ "$_tacs_incomplete" == "true" ]]; then
    provisional="
> **Provisional — this audit did not finish.** Everything below is a partial
> observation, not an instruction. Do not execute these changes or rely on
> these lanes and timings until the audit is completed."
  fi

  cat <<EOF
## 1. What to do now

${section_now}
${provisional}

## 2. What to fix, merge, split or remove

$(_tacs_id_set '[.portfolio_change.keep[]?]' 'Keep as-is')
$(_tacs_id_set '[.portfolio_change.rewrite_unit[]?]' 'Rewrite')
$(_tacs_merge_groups)
$(_tacs_id_set '[.portfolio_change.remove[]?]' 'Remove')
${removal_line}

**Proposed changes** (ranked; the full set is in decision.json):

$(_tacs_proposed_actions)

## 3. What can run in parallel

${section_parallel}

## 4. What must remain serial

${section_serial}

## 5. Test time now, and after the proposed work

${section_time}

## 6. What is not proved yet

${section_unproved}
${_tacs_undecided_line}

---

### Technical evidence

**Verdict:** ${verdict}

**Findings** (evidence, not a to-do list):
${reasons_text}

**Changed:** ${changed_text}

**Residual risk / PM decision:** ${residual_risk}
EOF
}
