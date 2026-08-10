#!/usr/bin/env bash
# =============================================================================
# aid-selector-honesty-check.sh — a nightly failure the merge gate would have
# missed is a finding about the SELECTOR (P081 Step 9).
#
# WHY: once the merge path is T0+T1 only, the targeted selector is most of what
# stands between a change and a merge. A selector nobody can audit is worse
# than no selector, because it looks like coverage. This turns "the nightly
# went red" into the sharper question: would the last merge's own gate have
# caught it?
#
# THREE CLASSES, because they need three different fixes:
#   unmapped         — the selector picked NOTHING for the changed paths. The
#                      mapping has no opinion; extend it.
#   mapped_but_thin  — the selector picked suites, exited 0, and the suite that
#                      actually failed was not among them. This is the class
#                      that matters most after the merge path narrows: the
#                      exit-3 / exit-11 escalation is structurally unreachable
#                      for a path the mapping DOES claim, so a thin mapping
#                      fails silently and confidently.
#   unmappable       — no changed path could ever have selected this suite (a
#                      cross-cutting invariant). A distinct outcome, NOT a gap:
#                      nothing about the mapping would fix it.
#
# THE SAFETY NET COUNTS AS SELECTION. The selector's `unverifiable` (exit 3)
# and `mapping_gap` (exit 11) outcomes both escalate the merge to a fuller
# profile today, so a merge that ended in one of them DID run more than the
# targeted set. Counting those as misses would manufacture gaps that are not
# real, and a gap report nobody believes gets ignored.
#
# A MISS IS REPORTED, NEVER A JOB FAILURE. This tool always exits 0 when it
# could do its work; the nightly attaches its output.
#
# Usage:
#   aid-selector-honesty-check.sh [--dir DIR] [--artifact FILE]
#                                 [--since-date YYYY-MM-DD] [--repo DIR]
#
# Exit codes: 0 = a report was produced (gaps or not), 2 = usage / no artifact.
#
# **Last Updated:** 2026-08-10
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The seam exists so the classification above can be exercised against a
# selector whose verdict the test chooses; the real selector is still the
# default and is exercised end to end by one case.
SELECTOR="${AID_SELECT_TESTS:-$SCRIPT_DIR/aid-select-tests.sh}"

NIGHTLY_DIR="${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}"
ARTIFACT=""; SINCE_DATE=""; REPO="$PWD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)        NIGHTLY_DIR="${2:-}"; shift 2 ;;
    --artifact)   ARTIFACT="${2:-}"; shift 2 ;;
    --since-date) SINCE_DATE="${2:-}"; shift 2 ;;
    --repo)       REPO="${2:-}"; shift 2 ;;
    --help|-h)
      sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "aid-selector-honesty-check: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "$ARTIFACT" ]] || ARTIFACT="$NIGHTLY_DIR/latest.json"
[[ -f "$ARTIFACT" ]] || {
  echo "aid-selector-honesty-check: no nightly artifact at '$ARTIFACT' — nothing to evaluate" >&2
  exit 2; }

DATE="$(jq -r '.date' "$ARTIFACT")"
OUT="$NIGHTLY_DIR/${DATE}-selector-gaps.json"
mapfile -t failing < <(jq -r '.failed[]?.suite' "$ARTIFACT")

write_report() {
  jq -n --arg date "$DATE" --argjson merges "$1" --argjson gaps "$2" \
        --argjson unmappable "$3" --arg note "$4" \
    '{date:$date, evaluated_merges:$merges, gaps:$gaps,
      unmappable:$unmappable, note:$note}' > "$OUT"
  echo "aid-selector-honesty-check: $OUT ($(jq 'length' <<<"$2") gap(s))"
}

# ─── Which merges are we judging? ───────────────────────────────────────────
# The union of every merge since the previous nightly, so a night that covers
# three merges is not silently judged against only the last one.
since="${SINCE_DATE:-$(date -u -d '1 day ago' +%Y-%m-%d 2>/dev/null || echo "$DATE")}"
mapfile -t merges < <(git -C "$REPO" log --merges --since="$since" --format=%H 2>/dev/null)
merges_json="$(printf '%s\n' ${merges[@]+"${merges[@]}"} | jq -Rc 'select(length>0)' | jq -sc '.')"

if [[ "${#merges[@]}" -eq 0 ]]; then
  write_report "$merges_json" '[]' '[]' "no merge to evaluate since $since"
  exit 0
fi
if [[ "${#failing[@]}" -eq 0 ]]; then
  write_report "$merges_json" '[]' '[]' "the nightly was green — nothing to trace back to the selector"
  exit 0
fi

paths_file="$(mktemp)"; trap 'rm -f "$paths_file"' EXIT
for sha in "${merges[@]}"; do
  git -C "$REPO" diff --name-only "${sha}^1" "$sha" 2>/dev/null
done | sort -u > "$paths_file"

# ─── One replay for the whole change set ────────────────────────────────────
sel_json="$(bash "$SELECTOR" --paths-file "$paths_file" --dry-run 2>/dev/null)"
sel_exit=$?
selected="$(jq -c '.selected_tests // []' <<<"$sel_json" 2>/dev/null || echo '[]')"

if [[ "$sel_exit" -eq 3 || "$sel_exit" -eq 11 ]]; then
  write_report "$merges_json" '[]' '[]' \
    "the selector escalated (exit $sel_exit) for this change set, so the merge ran a fuller profile than the targeted one — no gap is manufactured from an escalation"
  exit 0
fi

# ─── The suites the selector's mapping can EVER name ────────────────────────
# Read from the mapping table itself. A suite the table never mentions could
# not have been selected by any path, which is `unmappable` rather than a gap.
# Reading the table over-reports rather than under-reports: a basename that
# appears only in a comment is treated as mappable, so its miss is still
# reported as a gap. Silence is the failure mode worth avoiding.
mappable="$(grep -oE 'test-[A-Za-z0-9_-]+\.(bats|sh)' "$SELECTOR" | sort -u | jq -Rc . | jq -sc '.')"

gaps='[]'; unmappable='[]'
for suite in "${failing[@]}"; do
  if [[ "$(jq --arg s "$suite" '[.[] | select(test("(^|/)" + $s + "\\.(bats|sh)$"))] | length' <<<"$selected")" -gt 0 ]]; then
    continue
  fi
  if [[ "$(jq --arg s "$suite" '[.[] | select(startswith($s + "."))] | length' <<<"$mappable")" -eq 0 ]]; then
    unmappable="$(jq -c --arg s "$suite" '. + [$s]' <<<"$unmappable")"
    continue
  fi
  class="mapped_but_thin"
  [[ "$(jq 'length' <<<"$selected")" -eq 0 ]] && class="unmapped"
  gaps="$(jq -c --arg s "$suite" --arg c "$class" --slurpfile p <(jq -Rs 'split("\n") | map(select(length>0))' "$paths_file") \
    '. + [{suite:$s, class:$c, changed_paths:$p[0]}]' <<<"$gaps")"
done

write_report "$merges_json" "$gaps" "$unmappable" \
  "$(jq 'length' <<<"$selected") suite(s) were selected for this change set"
exit 0
