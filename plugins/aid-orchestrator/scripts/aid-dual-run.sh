#!/usr/bin/env bash
# aid-dual-run.sh — new stack vs legacy, per calibration fixture (P062 Step 7).
#
# Usage:
#   aid-dual-run.sh --manifest <e10-calibration/manifest.json>
#                   [--outcomes <outcomes.json>] [--out <file>]
#
#   --outcomes  the MEASURED result of running each fixture through both
#               stacks: {"<fixture id>": {"old": "<caught|not_caught|blocked|not_blocked>",
#                                          "new": "<same vocabulary>"}}
#               Omitted, every pair is `unmeasured` and the report says so.
#
# Exit: 0 = report written; 1 = a legacy_unique_catch was found (see below);
#       2 = usage/environment error.
#
# WHY EXIT 1 ON legacy_unique_catch
#   That class means a legacy control caught something the new stack did not.
#   D8 forbids marking such a control as an E11 removal candidate, and the
#   decision table is downstream of this file — a non-zero exit is how the
#   finding reaches a caller that is not reading the JSON. It is a finding, not
#   an error: the report is still written.
#
# THE CLASSES, AND WHY EXPECTATIONS ARE NOT OUTCOMES
#   The manifest carries `expected_old` and `expected_new`. Comparing those two
#   to each other would produce a beautiful report about the PLAN, measuring
#   nothing. So the expectation and the measurement are kept apart: the
#   divergence class comes from the OUTCOMES, and the manifest's expectation is
#   carried alongside so a run can be seen to have confirmed or contradicted it.
#   Without an outcomes file there is no class — `unmeasured`, never `agree`.
set -euo pipefail

MANIFEST=""
OUTCOMES=""
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) [[ $# -ge 2 ]] || { echo "--manifest needs a path" >&2; exit 2; }; MANIFEST="$2"; shift 2 ;;
    --outcomes) [[ $# -ge 2 ]] || { echo "--outcomes needs a path" >&2; exit 2; }; OUTCOMES="$2"; shift 2 ;;
    --out)      [[ $# -ge 2 ]] || { echo "--out needs a path" >&2; exit 2; };      OUT_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
[[ -n "$MANIFEST" && -f "$MANIFEST" ]] || { echo "ERROR: --manifest is required and must exist" >&2; exit 2; }
jq -e '.fixtures' "$MANIFEST" >/dev/null 2>&1 || { echo "ERROR: ${MANIFEST} carries no .fixtures" >&2; exit 2; }
OUT_FILE="${OUT_FILE:-.aid-o/work/evidence/P062/e10/dual-run-report.json}"

outcomes_json='{}'
if [[ -n "$OUTCOMES" ]]; then
  [[ -f "$OUTCOMES" ]] || { echo "ERROR: outcomes file not found: ${OUTCOMES}" >&2; exit 2; }
  outcomes_json="$(jq -c '.' "$OUTCOMES" 2>/dev/null)" || { echo "ERROR: outcomes file is not valid JSON" >&2; exit 2; }

  # The VOCABULARY is validated, not just the JSON syntax. An unrecognised word
  # used to fall through the classification chain and land in a class that
  # looked like a real answer — which could hide a legacy-only catch behind a
  # typo (cross-model review, 2026-08-15).
  #
  # An explicit null is EXEMPT here so it reaches the one-sided check below,
  # which diagnoses it as what it actually is: half a comparison. Rejecting it
  # as a vocabulary error would be true but unhelpful.
  _bad="$(jq -r '
    to_entries[]
    | .key as $k
    | (.value | to_entries[])
    | select((.key | IN("old","new")) | not) // empty
    | "\($k).\(.key) is not old/new"' <<<"$outcomes_json" 2>/dev/null || true)"
  _bad+="$(jq -r '
    to_entries[] | .key as $k | (.value | to_entries[])
    | select(.key | IN("old","new"))
    | select(.value != null)
    | select((.value | type) != "string" or ((.value | IN("caught","not_caught","blocked","not_blocked")) | not))
    | "\($k).\(.key)=\(.value|tostring)"' <<<"$outcomes_json" 2>/dev/null || true)"
  if [[ -n "${_bad//[[:space:]]/}" ]]; then
    echo "ERROR: outcomes use words outside the vocabulary (caught|not_caught|blocked|not_blocked):" >&2
    printf '  %s\n' $_bad >&2
    exit 2
  fi

  # A HALF-measured pair is refused. Epistemically `unmeasured` would be
  # correct, but it is unsafe for this file's purpose: a caller would see no
  # legacy_unique_catch and proceed on a comparison that never happened on one
  # side.
  _partial="$(jq -r 'to_entries[] | select((.value.old == null) != (.value.new == null)) | .key' <<<"$outcomes_json" 2>/dev/null || true)"
  if [[ -n "${_partial//[[:space:]]/}" ]]; then
    echo "ERROR: these fixtures have an outcome for only ONE stack; a one-sided comparison cannot show a legacy-only catch:" >&2
    printf '  %s\n' $_partial >&2
    exit 2
  fi
fi

# The classification. Kept in ONE jq expression so the precedence is readable in
# one place rather than spread across shell branches.
#
#   unmeasured        — no outcome for this pair. Never `agree`: two unknowns
#                       are not an agreement.
#   verification_only — the divergence is the known git-dirty verification
#                       artefact class from P059. Filtered OUT of the signal
#                       counts below, because it drowned real findings before.
#   agree             — both stacks reached the same result.
#   new_unique_catch  — new caught it, legacy did not.
#   legacy_unique_catch — legacy caught it, new did not. The one that blocks a
#                       removal recommendation.
#   new_stricter / legacy_stricter — both acted, one more severely.
report="$(jq -n \
  --slurpfile man "$MANIFEST" \
  --argjson out "$outcomes_json" '
  ($man[0].fixtures) as $fx
  | [ $fx[] | select(.grounded) | . as $f
      | ($out[$f.id] // null) as $o
      | ($o.old // null) as $old
      | ($o.new // null) as $new
      | {
          fixture: $f.id,
          expected_catcher: $f.expected_catcher,
          control: $f.control,
          expected_old: $f.expected_old,
          expected_new: $f.expected_new,
          old_result: $old,
          new_result: $new,
          divergence:
            # PRECEDENCE, and it is not the obvious one.
            #
            # `verification_only` used to be tested SECOND, which meant a
            # verification-only fixture measured as old=caught / new=not_caught
            # was filtered away as noise and never reached D8 — the class this
            # whole harness exists for, suppressed by the noise filter
            # (cross-model review, 2026-08-15). The unique-catch tests now come
            # first; verification_only still exists and is still kept out of the
            # aggregate counts, but it can no longer swallow a measured
            # legacy-only catch.
            #
            # ACTED-vs-ACTED is not a strictness ordering. `caught` and
            # `blocked` are two different actions with no declared severity
            # between them, so a pair where both sides acted differently is
            # `both_acted`, not a confident "new_stricter" in either direction.
            (if $old == null and $new == null then "unmeasured"
             elif $old == null or $new == null then "partial"
             elif $old == $new then "agree"
             elif ($old | test("^(caught|blocked)$")) and ($new | test("^not_")) then "legacy_unique_catch"
             elif ($new | test("^(caught|blocked)$")) and ($old | test("^not_")) then "new_unique_catch"
             elif ($f.failure_class // "") == "verification_only" then "verification_only"
             elif ($old | test("^(caught|blocked)$")) and ($new | test("^(caught|blocked)$")) then "both_acted"
             else "unclassified" end),
          expectation_held:
            (if $old == null or $new == null then null
             else ($old == $f.expected_old and $new == $f.expected_new) end)
        } ]
  | . as $pairs
  | {schema_version: "aid-2.0",
     artifact_type: "dual_run_report",
     generated_by: "aid-dual-run.sh",
     pairs: $pairs,
     status: (if ([$pairs[] | select(.divergence == "legacy_unique_catch")] | length) > 0
              then "legacy_unique_catch_found" else "ok" end),
     legacy_unique_catch: [ $pairs[] | select(.divergence == "legacy_unique_catch") | .fixture ],
     unmeasured: [ $pairs[] | select(.divergence == "unmeasured") | .fixture ],
     signal:
       ($pairs
        | map(select(.divergence != "verification_only" and .divergence != "unmeasured"))
        | group_by(.divergence)
        | map({key: .[0].divergence, value: length})
        | from_entries)}')" || { echo "ERROR: could not build the dual-run report" >&2; exit 2; }

mkdir -p "$(dirname "$OUT_FILE")"
printf '%s\n' "$report" | jq '.' > "$OUT_FILE"

n_luc="$(jq -r '.legacy_unique_catch | length' "$OUT_FILE")"
n_unm="$(jq -r '.unmeasured | length' "$OUT_FILE")"
echo "aid-dual-run: $(jq -r '.pairs | length' "$OUT_FILE") pair(s) → ${OUT_FILE}"
jq -r '.signal | to_entries[] | "  \(.key): \(.value)"' "$OUT_FILE"
(( n_unm > 0 )) && echo "  unmeasured: ${n_unm} (no outcome supplied — not counted as agreement)"

# Exit 1 is the FINDING, and `status` in the report says the same thing for a
# caller that cannot tell exit 1 from an ordinary command failure under set -e.
if (( n_luc > 0 )); then
  echo "FINDING: legacy caught what the new stack did not, for: $(jq -r '.legacy_unique_catch | join(", ")' "$OUT_FILE")" >&2
  echo "  D8 forbids marking such a legacy control an E11 removal candidate." >&2
  exit 1
fi
exit 0
