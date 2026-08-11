#!/usr/bin/env bash
# aid-tier: t2
# =============================================================================
# test-run-all-delegation.sh — P079 Step 12 (IMP-483): every delegated suite is
# owned by exactly one CI job, and the inline runner really does skip it.
#
# THE FAILURE MODE THIS EXISTS FOR: delegation moves a suite OUT of the inline
# run. If the matching CI job is missing, renamed or duplicated, the suite stops
# being run by anything — and the inline run gets FASTER, which reads as
# success. Nobody notices a suite that quietly stopped existing.
#
# Two assertions, and the second is the one that matters:
#   1. run-all-tests.sh skips each mapped suite inline and names its owner.
#   2. every DELEGATED_SUITES value appears as a job name in exactly one
#      workflow file — not zero, not two.
#
# Exit: 0 all pass, 1 any fail.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
RUNNER="$SCRIPT_DIR/run-all-tests.sh"
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL+1)); }

[[ -f "$RUNNER" ]] || { echo "FAIL: run-all-tests.sh not found at $RUNNER" >&2; exit 1; }
[[ -d "$WORKFLOW_DIR" ]] || { echo "FAIL: no .github/workflows directory at $WORKFLOW_DIR" >&2; exit 1; }

# The map, read from the runner itself rather than restated here — a copy would
# pass while the two drifted.
# Comment lines inside the block are NOT entries — a commented-out delegation
# means the suite runs inline, and treating it as live would demand a CI job
# for a suite nothing delegates.
mapfile -t MAP_LINES < <(
  awk '/^declare -A DELEGATED_SUITES=\(/ { inside = 1; next }
       inside && /^\)/                    { exit }
       inside && /^[[:space:]]*#/          { next }
       inside && /\["/                    { print }' "$RUNNER"
)
# One declaration, or the map this test read is not the map the runner uses.
decl_blocks=$(grep -c '^declare -A DELEGATED_SUITES=(' "$RUNNER")
if [[ "$decl_blocks" -ne 1 ]]; then
  echo "FAIL: run-all-tests.sh declares DELEGATED_SUITES ${decl_blocks} times — this test reads the first block only, so it can no longer speak for the runner's effective map" >&2
  exit 1
fi
if [[ "${#MAP_LINES[@]}" -eq 0 ]]; then
  echo "FAIL: could not read DELEGATED_SUITES out of $RUNNER" >&2
  exit 1
fi

declare -A OWNER=()
for line in "${MAP_LINES[@]}"; do
  suite="${line#*\[\"}"; suite="${suite%%\"]*}"
  owner="${line#*\]=\"}"; owner="${owner%%\"*}"
  [[ -n "$suite" && -n "$owner" ]] || continue
  OWNER["$suite"]="$owner"
done
echo "Delegated suites: ${#OWNER[@]}"

# ── 1. every mapped suite has exactly one owning CI job ─────────────────────
for suite in "${!OWNER[@]}"; do
  job="${OWNER[$suite]}"
  hits=$(grep -rlE "^  ${job}:\s*\$" "$WORKFLOW_DIR" 2>/dev/null | wc -l)
  case "$hits" in
    1) _pass "$suite -> job '$job' defined in exactly one workflow file" ;;
    0) _fail "$suite is delegated to job '$job', but NO workflow defines that job — the suite is now run by nothing" ;;
    *) _fail "$suite is delegated to job '$job', which $hits workflow files define — one owner or none is a fact, two is a guess" ;;
  esac
  # And the job actually RUNS that suite — on a live line. A commented-out
  # `# run: bats …` mentions the suite and runs nothing, which is precisely the
  # silent-disappearance this test exists to prevent.
  live_hits=$(grep -rhF "tests/bats/${suite}" "$WORKFLOW_DIR" 2>/dev/null \
              | grep -vE '^\s*#' | grep -cE '(^|\s)run:' || true)
  if [[ "${live_hits:-0}" -ge 1 ]]; then
    _pass "$suite is named on a live (uncommented) workflow run line"
  else
    _fail "$suite is delegated but no UNCOMMENTED workflow run line runs it — it is now run by nothing"
  fi
  # A job disabled by `if: false` owns nothing either.
  if grep -rhA 3 "^  ${job}:\s*\$" "$WORKFLOW_DIR" 2>/dev/null | grep -qE '^\s*if:\s*(false|\$\{\{\s*false)'; then
    _fail "$suite is delegated to job '$job', which is disabled with 'if: false'"
  fi
done

# ── 2. the inline runner skips them and says who owns them ──────────────────
# --list is a dry enumeration: no suite is executed, so this stays a targeted
# test and never becomes a second full run.
listing="$(bash "$RUNNER" --list 2>&1)" || true
for suite in "${!OWNER[@]}"; do
  if grep -qF "$suite" <<<"$listing" && grep -qE "DELEGATED.*${suite}|${suite}.*DELEGATED" <<<"$listing"; then
    _pass "$suite is reported DELEGATED by the inline runner"
  elif ! grep -qF "$suite" <<<"$listing"; then
    _fail "$suite appears nowhere in the inline runner's listing — silently dropped rather than delegated"
  else
    _fail "$suite is listed by the inline runner without a DELEGATED marker"
  fi
  # P081 Step 5: tier filtering and delegation must COMPOSE. A delegated suite
  # keeps exactly one line in the listing — delegation wins, it runs in its own
  # job — and that line carries the tier column like every other.
  n="$(grep -cE "^(INLINE|DELEGATED): .*${suite}" <<<"$listing")"
  if [[ "$n" -eq 1 ]]; then
    _pass "$suite is listed exactly once (tier filtering did not duplicate it)"
  else
    _fail "$suite appears on $n listing lines — tier filtering and delegation disagree about who owns it"
  fi
  if grep -qE "DELEGATED: .*${suite}.* \[(t0|t1|t2|untagged)\]" <<<"$listing"; then
    _pass "$suite carries a tier column in the listing"
  else
    _fail "$suite is listed without a tier column"
  fi
done

echo "---"
echo "Results: $((PASS+FAIL)) run, $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
