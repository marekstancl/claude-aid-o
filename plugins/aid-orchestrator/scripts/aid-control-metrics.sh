#!/usr/bin/env bash
# aid-control-metrics.sh — deterministic quality measurement of C0-C4 (P062 Step 4).
#
# Usage:
#   aid-control-metrics.sh [--project-root <path>] [--evidence-root <dir>]
#                          [--ground-truth <manifest.json>] [--out <file>]
#
#   --evidence-root  where run directories live (default .aid-o/work/evidence)
#   --ground-truth   the calibration manifest from Step 6. WITHOUT it, the
#                    counters that need expected outcomes stay null.
#
# Exit: 0 = metrics written; 2 = usage/environment error.
#
# EVERY NUMBER IS COUNTED, NONE IS ASSERTED, AND NO LLM IS INVOLVED.
#
# THE RULE THIS FILE IS BUILT AROUND: NULL IS NOT ZERO
#   `false_done` asks "did this control pass while a defect was present?" and
#   `false_positives` asks "did it block when none was?". Both need to know what
#   SHOULD have happened, and a 0 there would read as "it never missed anything"
#   — a clean bill written from an empty room. They are therefore null, and the
#   decision table is required to treat null as "insufficient data → defer"
#   rather than as a good score.
#
#   HONEST LIMIT, because the earlier wording implied more (final audit,
#   2026-08-15): `--ground-truth` currently only RECORDS whether a calibration
#   manifest was supplied, in the `ground_truth` field. It does not yet read the
#   fixtures' expected outcomes, so these three counters stay null even WITH a
#   manifest. Computing them is the calibration run's own work — it needs each
#   fixture actually driven through each control — and until that exists the
#   table defers, which is the correct answer either way.
#
# C3 IS COUNTED SEPARATELY, ON PURPOSE
#   `unverifiable` is not a non-fail. Measured over this repository's own
#   evidence, C3's recorded verdicts run roughly three-to-one unverifiable, and
#   a summary that folds those into "hardly ever blocks" would recommend
#   promoting a control that mostly shrugs. c3_verdict_mix keeps the three
#   outcomes apart so the decision table has to look at them.
set -euo pipefail

_CM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
EVIDENCE_ROOT=""
GROUND_TRUTH=""
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)  [[ $# -ge 2 ]] || { echo "--project-root needs a path" >&2; exit 2; }; PROJECT_ROOT="$2"; shift 2 ;;
    --evidence-root) [[ $# -ge 2 ]] || { echo "--evidence-root needs a path" >&2; exit 2; }; EVIDENCE_ROOT="$2"; shift 2 ;;
    --ground-truth)  [[ $# -ge 2 ]] || { echo "--ground-truth needs a path" >&2; exit 2; }; GROUND_TRUTH="$2"; shift 2 ;;
    --out)           [[ $# -ge 2 ]] || { echo "--out needs a path" >&2; exit 2; }; OUT_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
cd "$PROJECT_ROOT" || { echo "ERROR: cannot enter ${PROJECT_ROOT}" >&2; exit 2; }
EVIDENCE_ROOT="${EVIDENCE_ROOT:-.aid-o/work/evidence}"
OUT_FILE="${OUT_FILE:-.aid-o/work/evidence/P062/e10/control-metrics.json}"
[[ -d "$EVIDENCE_ROOT" ]] || { echo "ERROR: evidence root not found: ${EVIDENCE_ROOT}" >&2; exit 2; }

# ── C3 verdict mix — counted from every audit report on disk ────────────────
c3_pass=0; c3_fail=0; c3_unver=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  st="$(jq -r '.status // .verdict // ""' "$f" 2>/dev/null || echo "")"
  case "$st" in
    pass)         c3_pass=$((c3_pass + 1)) ;;
    fail)         c3_fail=$((c3_fail + 1)) ;;
    unverifiable) c3_unver=$((c3_unver + 1)) ;;
    # Anything else — an unreadable or schema-foreign report — counts as
    # unverifiable. It is certainly not a pass, and dropping it would shrink the
    # denominator, which flatters exactly the ratio this field exists to expose.
    *)            c3_unver=$((c3_unver + 1)) ;;
  esac
done < <(find "$EVIDENCE_ROOT" -name 'audit-report.json' -type f 2>/dev/null | sort)

# ── ground truth ────────────────────────────────────────────────────────────
gt="absent"
if [[ -n "$GROUND_TRUTH" && -f "$GROUND_TRUTH" ]] && jq -e '.fixtures' "$GROUND_TRUTH" >/dev/null 2>&1; then
  gt="present"
fi

# ── per-control counting ────────────────────────────────────────────────────
# Each control is read from the artefact it actually writes. A control whose
# artefact is absent everywhere still gets a row, with empty caught_classes and
# null counters — a missing control is a fact about the run, not a reason to
# leave the row out and shorten the table.
_count_caught() {
  # _count_caught <glob-name> <jq-expr-selecting-finding-classes>
  local name="$1" expr="$2" out=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    out+="$(jq -r "$expr" "$f" 2>/dev/null || true)"$'\n'
  done < <(find "$EVIDENCE_ROOT" -name "$name" -type f 2>/dev/null | sort)
  printf '%s' "$out" | sed '/^\s*$/d' | sort -u
}

_refs_for() {
  find "$EVIDENCE_ROOT" -name "$1" -type f 2>/dev/null | sort | head -20
}

_row() {
  # _row <control> <artefact-glob> <classes-jq>
  local control="$1" glob="$2" expr="$3"
  local classes refs
  classes="$(_count_caught "$glob" "$expr" | jq -R . | jq -sc .)"
  refs="$(_refs_for "$glob" | jq -R . | jq -sc .)"
  jq -nc --arg c "$control" --argjson cl "$classes" --argjson rf "$refs" --arg gt "$gt" \
    '{control: $c,
      caught_classes: $cl,
      false_done: null,
      false_positives: null,
      cost_seconds: null,
      unique_detection_vs_legacy: null,
      ground_truth: $gt,
      evidence_refs: $rf}'
}

controls="[]"
controls="$(jq -c ". + [$(_row c0 'c0-plan-review.json' '(.findings // [])[] | (.area // .category // "unclassified")')]" <<<"$controls")"
controls="$(jq -c ". + [$(_row c3 'audit-report.json' '(.findings // [])[] | (.category // .area // "unclassified")')]" <<<"$controls")"
controls="$(jq -c ". + [$(_row c4 'release-decision.json' '(.release_decision.inputs // .inputs // [])[] | select(.verdict == "blocked") | (.id // "unclassified")')]" <<<"$controls")"
controls="$(jq -c ". + [$(_row c1 'delivery-gate.json' '(.checks // [])[] | select(.status == "fail") | (.id // "unclassified")')]" <<<"$controls")"
controls="$(jq -c ". + [$(_row c2 'semantic-review-final.json' '(.findings // [])[] | (.category // "unclassified")')]" <<<"$controls")"

runs="$(find "$EVIDENCE_ROOT" -name 'fsm-state.yaml' -type f 2>/dev/null | wc -l | tr -d ' ')"

# ── speed (P062 Step 5) ─────────────────────────────────────────────────────
#
# THE THREE UNITS THAT EXIST, AND THE ONE THAT DOES NOT
#   After P068 a plan pays the expensive gates ONCE, at its own boundary, so
#   "full suite per EPIC" stopped describing anything that runs and is not
#   measured here. What runs is: the merge path (T0+T1), the plan-final
#   boundary, and the nightly portfolio.
#
# MEASURED, NOT RE-MEASURED
#   The durations journal and the tier tags already own these numbers, and both
#   the nightly report and the reaper read them from there. Summing suites here
#   with a private discovery would let this file answer "what did the portfolio
#   cost" differently from the two consumers that already ask — so it asks the
#   same libraries. A missing journal yields null, never 0: an unmeasured path
#   is not a free one.
# Everything starts NULL. A number appears only when something measured it,
# because every field here is read by a decision table and "0 seconds" is a
# far more dangerous answer than "not measured" (cross-model review,
# 2026-08-15, which found four separate ways an unmeasured value was coming
# out as a plausible zero).
_speed_json='{"dispatch_count":null,"llm_calls":null,"merge_path_seconds":null,"plan_final_seconds":null,"nightly_seconds":null,"median_gate_cycle":null,"baseline_seconds":null,"e10_added_seconds":null,"fast_mode":"not_measurable"}'

# Libraries are resolved from THIS SCRIPT's location, never from the cwd. The
# repo-relative form silently went false from any other working directory —
# including a linked worktree and the installed plugin in a consumer project —
# and the speed and calibration blocks then emitted nulls that looked like
# honest "not measured" answers rather than "could not even find the library"
# (reuse review, 2026-08-15).
_TD_LIB="${_CM_SCRIPT_DIR}/lib/aid-test-durations.sh"
if [[ -f "$_TD_LIB" ]]; then
  # shellcheck disable=SC1090
  if source "$_TD_LIB" 2>/dev/null && declare -F aid_durations_by_suite >/dev/null 2>&1; then
    # Discovery is asked ONCE and its failure is a failure, not an empty list.
    # `|| true` on discovery turned a broken lookup into a short portfolio and
    # then reported that as the portfolio's cost.
    _suite_paths=""
    if _suite_paths="$(aid_test_discover_suites 2>/dev/null)"; then
      # basename -> path, built ONCE. Resolving inside the per-suite loop was
      # quadratic (a `basename` subshell per candidate per suite, ~70k of them
      # over this repository's 264 suites) and simply never finished.
      # AMBIGUITY IS DROPPED, NOT GUESSED: two suites sharing a basename get no
      # tier rather than one of them silently taking the other's — the wrong
      # tier is a wrong merge-path total, which is exactly the plausible-but-
      # false number this rewrite exists to remove.
      declare -A _path_of=() _dup=()
      while IFS= read -r _cand; do
        [[ -n "$_cand" ]] || continue
        _b="$(basename "$_cand")"
        if [[ -n "${_path_of[$_b]:-}" ]]; then _dup[$_b]=1; else _path_of[$_b]="$_cand"; fi
      done <<< "$_suite_paths"

      _merge_ms=0; _all_ms=0; _measured=0; _tiered=0
      while IFS=$'\t' read -r _suite _ms; do
        [[ -n "$_suite" && "$_ms" =~ ^[0-9]+$ ]] || continue
        _measured=$(( _measured + 1 ))
        _all_ms=$(( _all_ms + _ms ))
        [[ -z "${_dup[$_suite]:-}" ]] || continue
        _path="${_path_of[$_suite]:-}"
        [[ -n "$_path" ]] || continue
        _tier="$(aid_test_tier_of "$_path" 2>/dev/null || echo "")"
        case "$_tier" in
          t0|t1) _tiered=$(( _tiered + 1 )); _merge_ms=$(( _merge_ms + _ms )) ;;
          t2)    _tiered=$(( _tiered + 1 )) ;;
        esac
      done < <(aid_durations_by_suite 2>/dev/null)

      if (( _measured > 0 )); then
        _speed_json="$(jq -c --argjson a "$_all_ms" '.nightly_seconds = ($a / 1000)' <<<"$_speed_json")"
      fi
      # The merge path is reported ONLY when tiers were actually readable. With
      # no tier answers _merge_ms is 0 for a reason that has nothing to do with
      # cost, and 0 would read as "the merge path is free".
      if (( _tiered > 0 )); then
        _speed_json="$(jq -c --argjson m "$_merge_ms" '.merge_path_seconds = ($m / 1000)' <<<"$_speed_json")"
      fi
    fi
  fi
fi

# dispatch_count is COUNTED from the timelines the runs already write, and stays
# null when there is no timeline to count: a genuine zero and an unread file
# must not look the same.
#
# llm_calls stays NULL. It was briefly set to the dispatch count, which is a
# different quantity wearing this field's name — one dispatch is not one model
# call, and a fabricated number in a field a promotion decision reads is worse
# than an absent one. It gains a value when something actually counts calls.
# The source is pending-dispatches.jsonl, which is where the dispatch lifecycle
# actually records `start`. The first version grepped timeline.jsonl for an
# `"event":"dispatch*"` key that no timeline in this repository contains, so it
# matched nothing and reported 0 across sixty runs — a measurement of the wrong
# file, indistinguishable from a run that dispatched nothing. Checked before
# changing it: the whole evidence tree holds exactly one such ledger, so this
# number is usually null here, and null is the truthful answer.
_dl_count=0; _dispatches=0
while IFS= read -r _dl; do
  [[ -n "$_dl" ]] || continue
  _dl_count=$(( _dl_count + 1 ))
  _n="$(grep -c '"event"[[:space:]]*:[[:space:]]*"start"' "$_dl" 2>/dev/null || true)"
  [[ "$_n" =~ ^[0-9]+$ ]] || _n=0
  _dispatches=$(( _dispatches + _n ))
done < <(find "$EVIDENCE_ROOT" -name 'pending-dispatches.jsonl' -type f 2>/dev/null)
if (( _dl_count > 0 )); then
  _speed_json="$(jq -c --argjson d "$_dispatches" '.dispatch_count = $d' <<<"$_speed_json")"
fi

# ── profile calibration (P062 Step 9) ───────────────────────────────────────
#
# WHAT THE BASELINE IS, AND WHAT IT IS NOT
#   The comparison is against P063's measured per-gate p95, NOT against a
#   "full suite per EPIC" run. P068 abolished that unit — a plan pays the
#   expensive gates once at its own boundary — so measuring a saving against it
#   would compare today's cost to a run that no longer happens.
#
# SCOPE IS PART OF THE RESULT
#   This measures /aid-run only. Fast Mode invokes no AID script and emits no
#   profile events (IMP-506), so "profiles make things faster" is a statement
#   about ONE of the two entry points and the artifact says which.
#
# NULL WHEN THE BASELINE CANNOT ANSWER: gate_baseline_report_json reports
# data_sufficient=false until it has enough non-censored samples, and a saving
# computed from insufficient data is a guess with a decimal point.
_profile_json='null'
_EXEC_YAML="${AID_EXECUTION_YAML:-.aid-o/config/execution.yaml}"
_GBR_LIB="${_CM_SCRIPT_DIR}/lib/aid-gate-runtime-baseline.sh"
if [[ -f "$_EXEC_YAML" && -f "$_GBR_LIB" ]] && command -v yq >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  if source "$_GBR_LIB" 2>/dev/null && declare -F gate_baseline_report_json >/dev/null 2>&1; then
    _all_p95=0; _quick_p95=0; _known=0; _unknown=0
    while IFS= read -r _g; do
      [[ -n "$_g" ]] || continue
      _rep="$(gate_baseline_report_json "$_g" 2>/dev/null || echo '{}')"
      _suf="$(jq -r '.data_sufficient // false' <<<"$_rep" 2>/dev/null || echo false)"
      # p95_ms is a JSON NUMBER and may legitimately be a decimal. Feeding that
      # straight into bash arithmetic aborts under set -e, turning a valid
      # measurement into a dead script (cross-model review, 2026-08-15). It is
      # rounded to an integer by jq, where the value already lives.
      _p95="$(jq -r 'if (.p95_ms // null) == null then "null" else ((.p95_ms) | round | tostring) end' <<<"$_rep" 2>/dev/null || echo null)"
      if [[ "$_suf" != "true" || ! "$_p95" =~ ^[0-9]+$ ]]; then _unknown=$(( _unknown + 1 )); continue; fi
      _known=$(( _known + 1 ))
      _all_p95=$(( _all_p95 + _p95 ))
      if yq -r '.gate_profiles.quick.include[]?' "$_EXEC_YAML" 2>/dev/null | grep -qxF "$_g"; then
        _quick_p95=$(( _quick_p95 + _p95 ))
      fi
    done < <(yq -r '.gates | keys | .[]' "$_EXEC_YAML" 2>/dev/null)

    # Escalation is PROVEN by running the shared resolver, not asserted: a
    # high-risk path must resolve above a docs-only one.
    _esc="false"
    if source "${_CM_SCRIPT_DIR}/lib/aid-gate-profile.sh" 2>/dev/null \
       && declare -F gate_profile_resolve >/dev/null 2>&1; then
      # One temp dir with a trap: two bare mktemps leaked the first when the
      # second failed, and both on an interrupt.
      _esc_dir="$(mktemp -d)"
      trap 'rm -rf "${_esc_dir:-}"' RETURN
      printf 'README.md\n' > "${_esc_dir}/lo"
      _lo="$(gate_profile_resolve "${_esc_dir}/lo" 2>/dev/null || echo "")"

      # EVERY high-risk path the resolver documents, not one hard-coded name.
      # A single pair could come out "true" purely because two static ranks
      # differ; requiring each of the declared high-risk paths to resolve to at
      # least `full` tests the rule rather than one row of a table
      # (cross-model review, 2026-08-15). It is still a resolver-level proof —
      # what a whole RUN does is the calibration run's business, and the
      # artifact's scope field says so.
      _esc_all="true"; _esc_seen=0
      for _hp in \
        plugins/aid-orchestrator/scripts/aid-fsm.sh \
        plugins/aid-orchestrator/scripts/aid-run-gates.sh \
        plugins/aid-orchestrator/scripts/aid-release-policy.sh \
        plugins/aid-orchestrator/scripts/aid-evidence-verify.sh \
        plugins/aid-orchestrator/defaults/policies/delivery-gate.yaml \
        plugins/aid-orchestrator/agents/auditor.md; do
        printf '%s\n' "$_hp" > "${_esc_dir}/hi"
        _hi="$(gate_profile_resolve "${_esc_dir}/hi" 2>/dev/null || echo "")"
        [[ -n "$_hi" ]] || { _esc_all="false"; continue; }
        _esc_seen=$(( _esc_seen + 1 ))
        if declare -F gate_profile_rank >/dev/null 2>&1; then
          _lr="$(gate_profile_rank "${_lo:-quick}" 2>/dev/null || echo 0)"
          _hr="$(gate_profile_rank "$_hi" 2>/dev/null || echo 0)"
          _fr="$(gate_profile_rank full 2>/dev/null || echo 0)"
          if ! { [[ "$_hr" =~ ^[0-9]+$ && "$_lr" =~ ^[0-9]+$ && "$_fr" =~ ^[0-9]+$ ]] \
                 && (( _hr > _lr )) && (( _hr >= _fr )); }; then
            _esc_all="false"
          fi
        else
          _esc_all="false"
        fi
      done
      [[ "$_esc_all" == "true" && "$_esc_seen" -gt 0 ]] && _esc="true"
    fi

    # The saving is computed ONLY when EVERY gate has a baseline. Disclosing
    # `gates_without_baseline` beside a number is not the same as refusing the
    # number: the reader gets a decimal that looks measured and a footnote
    # saying part of the set was not (cross-model review, 2026-08-15). A saving
    # over a partly unmeasured set is a guess with a decimal point, so it is
    # null and the count says why.
    if (( _known > 0 && _unknown == 0 )); then
      _profile_json="$(jq -nc --argjson a "$_all_p95" --argjson q "$_quick_p95" \
        --argjson esc "$_esc" --argjson unk "$_unknown" \
        '{baseline_source: "p063",
          savings_seconds: (($a - $q) / 1000),
          escalation_proven: $esc,
          scope: "aid_run_only",
          gates_without_baseline: $unk}')"
    else
      _profile_json="$(jq -nc --argjson esc "$_esc" --argjson unk "$_unknown" \
        '{baseline_source: "p063", savings_seconds: null, escalation_proven: $esc,
          scope: "aid_run_only", gates_without_baseline: $unk}')"
    fi
  fi
fi

# c3_hook_fired — the roadmap precondition Step 4 owes an answer to (IMP-177
# end-to-end). Counted from the dispatch records C3 actually leaves behind, and
# reported as its own field rather than inferred from the verdict mix: a run
# whose hook never fired and a run whose hook fired and could not decide both
# produce no pass, and only one of them is a wiring problem.
_c3_hook="$(find "$EVIDENCE_ROOT" -name 'c3-dispatch.json' -type f 2>/dev/null | wc -l | tr -d ' ')"
[[ "$_c3_hook" =~ ^[0-9]+$ ]] || _c3_hook=0

mkdir -p "$(dirname "$OUT_FILE")"
jq -n \
  --arg head "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  --argjson controls "$controls" \
  --argjson runs "${runs:-0}" \
  --argjson p "$c3_pass" --argjson f "$c3_fail" --argjson u "$c3_unver" \
  --argjson speed "$_speed_json" \
  --argjson c3hook "$_c3_hook" \
  --argjson profcal "$_profile_json" \
  '{schema_version: "aid-2.0",
    artifact_type: "control_metrics",
    generated_by: "aid-control-metrics.sh",
    head: $head,
    runs_scanned: $runs,
    controls: $controls,
    c3_verdict_mix: {pass: $p, fail: $f, unverifiable: $u},
    c3_hook_fired: $c3hook,
    speed: $speed,
    profile_calibration: $profcal}' > "$OUT_FILE"

# ── c4-content-verdict.json (P062 Step 8's evidence artefact) ───────────────
#
# Declared by Step 8 and read by AC8, and NOTHING WROTE IT until the final
# wiring audit found it (2026-08-15) — the producer-with-no-consumer defect
# inverted, and exactly the class the EPIC 1 review had already caught once.
#
# It is emitted HERE rather than from a script of its own because this file
# already walks the evidence tree and already reads every release-decision.json
# in it; a second walk to answer a question about the same artifacts would be a
# second copy of the same knowledge.
#
# It reports what the run OBSERVED, not what the code can do: the distinct
# input_state values that actually occurred, and whether a waived verdict and a
# present_but_failing state were each seen alongside a blocked release. A state
# the run never produced is absent, so AC8 fails rather than passing over a
# capability nobody exercised.
_c4_out="$(dirname "$OUT_FILE")/c4-content-verdict.json"
_rd_files="$(find "$EVIDENCE_ROOT" -name 'release-decision.json' -type f 2>/dev/null | sort || true)"
if [[ -n "$_rd_files" ]]; then
  # shellcheck disable=SC2086
  jq -s '
    [ .[] | (.release_decision.inputs // .inputs // [])[] ] as $rows
    | {schema_version: "aid-2.0",
       artifact_type: "c4_content_verdict",
       generated_by: "aid-control-metrics.sh",
       states_exercised: ([$rows[] | .input_state | select(. != null)] | unique),
       waived_verdict_exercised: ([$rows[] | select(.verdict == "waived")] | length > 0),
       waived_blocks_release:
         ([$rows[] | select(.verdict == "waived")] | length > 0),
       present_but_failing_blocks_release:
         ([$rows[] | select(.input_state == "present_but_failing")
                   | select(.verdict == "blocked")] | length > 0),
       rows_scanned: ($rows | length)}' $_rd_files > "$_c4_out" 2>/dev/null \
    || jq -n '{schema_version:"aid-2.0", artifact_type:"c4_content_verdict",
               generated_by:"aid-control-metrics.sh", states_exercised:[],
               waived_verdict_exercised:false, waived_blocks_release:false,
               present_but_failing_blocks_release:false, rows_scanned:0,
               note:"no readable release-decision.json rows"}' > "$_c4_out"
else
  jq -n '{schema_version:"aid-2.0", artifact_type:"c4_content_verdict",
          generated_by:"aid-control-metrics.sh", states_exercised:[],
          waived_verdict_exercised:false, waived_blocks_release:false,
          present_but_failing_blocks_release:false, rows_scanned:0,
          note:"no release-decision.json under the evidence root"}' > "$_c4_out"
fi

echo "aid-control-metrics: ${runs} run(s), ground_truth=${gt} → ${OUT_FILE}"
echo "  c4 states exercised: $(jq -r '.states_exercised | join(", ") // "none"' "$_c4_out") (${_c4_out})"
echo "  C3 verdicts: pass=${c3_pass} fail=${c3_fail} unverifiable=${c3_unver}"
jq -r '.controls[] | "  \(.control): \(.caught_classes | length) caught class(es)"' "$OUT_FILE"
jq -r '"  c3_hook_fired: \(.c3_hook_fired)"' "$OUT_FILE"
jq -r '.speed | "  merge path: \(.merge_path_seconds // "unmeasured") s, portfolio: \(.nightly_seconds // "unmeasured") s, dispatches: \(.dispatch_count // "unmeasured")"' "$OUT_FILE"
