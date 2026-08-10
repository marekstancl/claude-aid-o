#!/usr/bin/env bash
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
mapfile -t MAP_LINES < <(
  awk '/^declare -A DELEGATED_SUITES=\(/ { inside = 1; next }
       inside && /^\)/                    { exit }
       inside && /\["/                    { print }' "$RUNNER"
)
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
  # And the job actually runs THAT suite.
  if grep -rqF "tests/bats/${suite}" "$WORKFLOW_DIR" 2>/dev/null; then
    _pass "$suite is named in a workflow run line"
  else
    _fail "$suite is delegated but no workflow run line mentions it"
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
done

echo "---"
echo "Results: $((PASS+FAIL)) run, $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
