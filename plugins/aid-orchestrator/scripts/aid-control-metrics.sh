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
#   SHOULD have happened. Without the calibration dataset nobody knows, and a 0
#   there would read as "it never missed anything" — a clean bill written from
#   an empty room. So they are null, `ground_truth` says `absent`, and the
#   decision table is required to treat null as "insufficient data → defer"
#   rather than as a good score.
#
# C3 IS COUNTED SEPARATELY, ON PURPOSE
#   `unverifiable` is not a non-fail. Measured over this repository's own
#   evidence, C3's recorded verdicts run roughly three-to-one unverifiable, and
#   a summary that folds those into "hardly ever blocks" would recommend
#   promoting a control that mostly shrugs. c3_verdict_mix keeps the three
#   outcomes apart so the decision table has to look at them.
set -euo pipefail

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

_TD_LIB="plugins/aid-orchestrator/scripts/lib/aid-test-durations.sh"
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
  '{schema_version: "aid-2.0",
    artifact_type: "control_metrics",
    generated_by: "aid-control-metrics.sh",
    head: $head,
    runs_scanned: $runs,
    controls: $controls,
    c3_verdict_mix: {pass: $p, fail: $f, unverifiable: $u},
    c3_hook_fired: $c3hook,
    speed: $speed}' > "$OUT_FILE"

echo "aid-control-metrics: ${runs} run(s), ground_truth=${gt} → ${OUT_FILE}"
echo "  C3 verdicts: pass=${c3_pass} fail=${c3_fail} unverifiable=${c3_unver}"
jq -r '.controls[] | "  \(.control): \(.caught_classes | length) caught class(es)"' "$OUT_FILE"
jq -r '"  c3_hook_fired: \(.c3_hook_fired)"' "$OUT_FILE"
jq -r '.speed | "  merge path: \(.merge_path_seconds // "unmeasured") s, portfolio: \(.nightly_seconds // "unmeasured") s, dispatches: \(.dispatch_count // "unmeasured")"' "$OUT_FILE"
