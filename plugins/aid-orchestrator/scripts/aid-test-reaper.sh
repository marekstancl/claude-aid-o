#!/usr/bin/env bash
# =============================================================================
# aid-test-reaper.sh — once a month, the portfolio proposes what to delete
# (P081 Step 11).
#
# FIVE PLACES ADD TESTS AND NONE REMOVES THEM. That asymmetry is why the suite
# grew to three and a half hours. This is the way out, and it is deliberately
# the WEAKEST possible mechanism: it proposes, with a reason per row, and a
# human deletes through a normal reviewed PR. It performs no deletion itself.
#
# NO QUOTA. The tool never targets a number of candidates. A quota turns a
# clean-up into a hunt for something to sacrifice, and the suite that gets
# sacrificed is whichever one nobody understands — usually the valuable one.
#
# FOUR INPUTS, AND IT SAYS WHICH ONE IT DID NOT HAVE:
#   vacuous green  — the content scanner's weak-oracle finding (asserts that
#                    check almost nothing), minus the ones it already marks as
#                    legitimately status-only.
#   duplication    — the content scanner's duplicate-test-case pairs.
#   cost           — the durations journal: a suite carrying a large share of
#                    the whole portfolio's cost.
#   failure age    — how long since the suite last caught a REAL regression,
#                    within a window (AID_REAPER_FAILURE_WINDOW_DAYS, 180 by
#                    default) — a failure from years ago is not a defence.
#                    This has no source in the tree: `git log` gives CHANGE
#                    age, not failure age, and no per-suite failure history
#                    existed before the nightly journal started. It fills in
#                    as nightlies accumulate; until then the tool says the
#                    input is degraded rather than proposing from three inputs
#                    while implying four.
#
# A suite that failed recently is never a candidate — whatever else is true of
# it, it just did its job. A suite younger than the grace period is never a
# candidate either: there is nothing to judge yet.
#
# Usage:
#   aid-test-reaper.sh [--content-scan FILE] [--dir DIR] [--tests-dir DIR]
#                      [--repo DIR] [--json]
#
# Exit codes: 0 = a list was produced (possibly empty), 2 = usage.
#
# **Last Updated:** 2026-08-10
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-tier.sh
source "$SCRIPT_DIR/lib/aid-test-tier.sh"
# shellcheck source=lib/aid-test-durations.sh
source "$SCRIPT_DIR/lib/aid-test-durations.sh"

NIGHTLY_DIR="${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}"
CONTENT_SCAN=""; TESTS_DIR=""; REPO="$PWD"; AS_JSON=0
COST_SHARE="${AID_REAPER_COST_SHARE:-5}"      # percent of the portfolio's cost
GRACE_DAYS="${AID_REAPER_GRACE_DAYS:-30}"     # too young to judge
# "Failed RECENTLY" needs a window, or the veto is permanent: a suite that
# caught something once in 2020 would be shielded forever, which is exactly the
# suite the reaper exists to find.
FAILURE_WINDOW_DAYS="${AID_REAPER_FAILURE_WINDOW_DAYS:-180}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --content-scan) [[ $# -ge 2 ]] || { echo "aid-test-reaper: --content-scan needs a value" >&2; exit 2; }
                    CONTENT_SCAN="$2"; shift 2 ;;
    --dir) [[ $# -ge 2 ]] || { echo "aid-test-reaper: --dir needs a value" >&2; exit 2; }
           NIGHTLY_DIR="$2"; shift 2 ;;
    --tests-dir) [[ $# -ge 2 ]] || { echo "aid-test-reaper: --tests-dir needs a value" >&2; exit 2; }
                 TESTS_DIR="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || { echo "aid-test-reaper: --repo needs a value" >&2; exit 2; }
            REPO="$2"; shift 2 ;;
    --json)         AS_JSON=1; shift ;;
    --help|-h)
      sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "aid-test-reaper: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "$TESTS_DIR" ]] || TESTS_DIR="$(aid_test_default_tests_dir)"

MISSING_INPUTS=()

# ─── Input 1+2: the content scanner ─────────────────────────────────────────
vacuous='[]'; duplicates='[]'
if [[ -n "$CONTENT_SCAN" && -f "$CONTENT_SCAN" ]]; then
  # Keyed by BASENAME: the scanner reports repo-relative paths and this tool
  # walks absolute ones, and a suite basename is unique across the two
  # discovery globs by construction (`test-*.sh` vs `bats/test-*.bats`).
  #
  # Both reads are CHECKED. A malformed scan file read as an empty scan would
  # hide every candidate only that input can see, while the report still
  # claimed the input was available — proposing from fewer signals than it
  # says is the one thing this tool must never do.
  if ! vacuous="$(jq -c '[.checks.weak_oracle[]? | select(.likely_legitimate | not)
                          | .file | split("/") | last]' "$CONTENT_SCAN" 2>/dev/null)" \
     || ! duplicates="$(jq -c '[.checks.duplicate_test_cases[]? | select(.shared_cases > 0)
                                | .file_a, .file_b | split("/") | last] | unique' "$CONTENT_SCAN" 2>/dev/null)"; then
    vacuous='[]'; duplicates='[]'
    MISSING_INPUTS+=("content scan at '$CONTENT_SCAN' could not be read — its findings are NOT in this list")
  fi
else
  MISSING_INPUTS+=("content scan (vacuous-green and duplicate findings) — pass --content-scan")
fi

# ─── Input 3: cost ──────────────────────────────────────────────────────────
total_ms=0
declare -A COST=()
while IFS=$'\t' read -r base d; do
  COST["$base"]="$d"
  total_ms=$(( total_ms + d ))
done < <(aid_durations_by_suite "$TESTS_DIR")
[[ "$total_ms" -gt 0 ]] || MISSING_INPUTS+=("durations journal (cost) — run run-all-tests.sh --timing")

# ─── Input 4: failure age, from whatever nightly history exists ─────────────
declare -A LAST_FAILED=()
history=0
for artifact in "$NIGHTLY_DIR"/[0-9]*.json; do
  [[ -f "$artifact" ]] || continue
  history=$(( history + 1 ))
  d="$(jq -r '.date' "$artifact" 2>/dev/null)" || continue
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    [[ -z "${LAST_FAILED[$s]:-}" || "${LAST_FAILED[$s]}" < "$d" ]] && LAST_FAILED["$s"]="$d"
  done < <(jq -r '.failed[]?.suite' "$artifact" 2>/dev/null)
done
if [[ "$history" -eq 0 ]]; then
  MISSING_INPUTS+=("failure age — no nightly history yet; this input fills in as nightlies accumulate")
fi

# _days_since <YYYY-MM-DD> — whole days from that date to today.
_days_since() {
  local then_s
  then_s="$(date -u -d "$1" +%s 2>/dev/null)" || { echo 99999; return 0; }
  echo $(( ( $(date -u +%s) - then_s ) / 86400 ))
}

# ─── first_seen_days <path> — age of the file's oldest commit ───────────────
#
# `--follow`, so a RENAMED suite keeps its history. Without it, renaming a
# suite would reset its age and hide it from the reaper forever — the gaming
# path the standard names explicitly.
#
# A path git knows nothing about (untracked) is reported as ancient rather
# than as new: "new" here means "recently committed", and an untracked file
# is not part of the portfolio the reaper is judging in the first place.
first_seen_days() {
  local ts path="$1"
  # Git pathspecs are REPOSITORY-relative. Discovery yields absolute paths, and
  # an absolute pathspec matches nothing, so every suite looked ancient and the
  # grace-period veto never fired at all.
  case "$path" in
    "$REPO"/*) path="${path#"$REPO"/}" ;;
  esac
  ts="$(git -C "$REPO" log --follow --format=%at -- "$path" 2>/dev/null | tail -1)"
  [[ "$ts" =~ ^[0-9]+$ ]] || { echo 99999; return 0; }
  echo $(( ( $(date -u +%s) - ts ) / 86400 ))
}

# ─── Assemble ───────────────────────────────────────────────────────────────
rows='[]'
while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  base="$(basename "$suite")"
  reasons=()

  [[ "$(jq --arg f "$base" '[.[] | select(. == $f)] | length' <<<"$vacuous")" -gt 0 ]] \
    && reasons+=("vacuous green — its asserts check little more than an exit code")
  [[ "$(jq --arg f "$base" '[.[] | select(. == $f)] | length' <<<"$duplicates")" -gt 0 ]] \
    && reasons+=("duplicate — it shares test cases with another suite")

  cost="${COST[$base]:-0}"
  if [[ "$total_ms" -gt 0 && "$cost" -gt 0 ]]; then
    share=$(( cost * 100 / total_ms ))
    [[ "$share" -ge "$COST_SHARE" ]] \
      && reasons+=("expensive — ${share}% of the whole portfolio's measured cost")
  fi

  [[ "${#reasons[@]}" -eq 0 ]] && continue

  # Two vetoes, in order of how loudly they say "not this one".
  name_no_ext="${base%.bats}"; name_no_ext="${name_no_ext%.sh}"
  if [[ -n "${LAST_FAILED[$name_no_ext]:-}" ]] \
     && [[ "$(_days_since "${LAST_FAILED[$name_no_ext]}")" -lt "$FAILURE_WINDOW_DAYS" ]]; then
    continue
  fi
  [[ "$(first_seen_days "$suite")" -lt "$GRACE_DAYS" ]] && continue

  rows="$(jq -c --arg s "$base" --argjson r "$(printf '%s\n' "${reasons[@]}" | jq -Rc . | jq -sc '.')" \
    --argjson cost "$cost" '. + [{suite:$s, reasons:$r, duration_ms:$cost}]' <<<"$rows")"
done < <(aid_test_discover_suites "$TESTS_DIR")

missing_json="$(printf '%s\n' ${MISSING_INPUTS[@]+"${MISSING_INPUTS[@]}"} | jq -Rc 'select(length>0)' | jq -sc '.')"
report="$(jq -nc --arg date "$(date -u +%Y-%m-%d)" --argjson candidates "$rows" \
  --argjson unavailable_inputs "$missing_json" \
  '{date:$date, candidates:$candidates, unavailable_inputs:$unavailable_inputs,
    note:"proposals only — this tool deletes nothing"}')"

if mkdir -p "$NIGHTLY_DIR" 2>/dev/null; then
  printf '%s\n' "$report" > "$NIGHTLY_DIR/$(date -u +%Y-%m-%d)-reaper.json"
fi

if [[ "$AS_JSON" -eq 1 ]]; then
  printf '%s\n' "$report"
  exit 0
fi

echo "Reaper candidates ($(jq '.candidates | length' <<<"$report")) — proposals only, nothing is deleted"
jq -r '.candidates[] | "  - \(.suite) (\(.duration_ms) ms)\n" + (.reasons | map("      · " + .) | join("\n"))' <<<"$report"
if [[ "$(jq '.unavailable_inputs | length' <<<"$report")" -gt 0 ]]; then
  echo ""
  echo "  Inputs this list did NOT have (so it proposes from fewer signals than the full four):"
  jq -r '.unavailable_inputs[] | "    - " + .' <<<"$report"
fi
exit 0
