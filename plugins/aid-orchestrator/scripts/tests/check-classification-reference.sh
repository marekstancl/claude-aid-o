#!/usr/bin/env bash
# =============================================================================
# check-classification-reference.sh — the hand-labelled reference set and the
# ceremony-band classifier still agree (P084 Step 1, SC1).
#
# The reference set (docs/plans/P084-classification-reference.md) is a table of
# real plans of this repository, each labelled BY HAND before the classifier
# ever ran over it. This script re-runs `aid-cp1-gate.sh --classify-only` over
# the fixture that reproduces each plan's Files declarations and compares.
#
# Two kinds of disagreement, and they are not equally bad. Which one it is
# depends on DIRECTION, not on the hand label — `medium` labelled and `light`
# classified is under-classification too, and an earlier version of this script
# counted it as over-classification, which reported the dangerous direction as
# the harmless one:
#   UNDER-classified — the classifier lands BELOW the hand label. Ceremony
#                    disappears where it was wanted. Reported separately,
#                    always fails.
#   over-classified — the classifier lands ABOVE the hand label. Expensive, not
#                    dangerous. Also fails, because a map nobody keeps honest
#                    stops being a map.
#
# Orphan fixtures (a file in fixtures/plan-risk/ that no table row names) fail
# too: a reference set that silently ignores half its own fixtures proves
# nothing.
#
# WHAT IT ACTUALLY CLASSIFIES: the fixture that REPRODUCES each real plan's
# frontmatter id and Files bullets, not the plan file itself — `.aid-o/` is
# gitignored, so the real plans are not in the repository and a check that
# needed them would only run on one machine.
#
# NOT a discovered suite (the name does not match `test-*.sh`) — it is invoked
# by name from test-cp1-gate-risk.bats, so it runs on the merge path, and by
# SC1 of the plan.
#
# Usage: check-classification-reference.sh [reference.md]
# Exit:  0 = every row agrees   1 = disagreement   2 = usage / missing input
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
GATE="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-cp1-gate.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/plan-risk"

REFERENCE="${1:-$REPO_ROOT/docs/plans/P084-classification-reference.md}"
[[ $# -le 1 ]] || { echo "Usage: $(basename "$0") [reference.md]" >&2; exit 2; }
[[ -f "$REFERENCE" ]] || { echo "check-classification-reference: reference not found: $REFERENCE" >&2; exit 2; }
[[ -d "$FIXTURE_DIR" ]] || { echo "check-classification-reference: fixture dir not found: $FIXTURE_DIR" >&2; exit 2; }

# Band order — the only thing that decides which direction a disagreement went.
_band_rank() {
  case "$1" in
    light)  echo 0 ;;
    medium) echo 1 ;;
    full)   echo 2 ;;
    *)      echo -1 ;;
  esac
}

declare -A seen=()
rows=0 agreed=0 under=0 over=0 missing=0
declare -A dist=([full]=0 [medium]=0 [light]=0)

# Table rows only: "| ref-<id> | <source plan> | <band> | <why> |". The header
# and the separator row are skipped by the ref- prefix requirement.
while IFS='|' read -r _ fixture source band _rest; do
  fixture="$(echo "$fixture" | xargs)"
  band="$(echo "$band" | xargs)"
  source="$(echo "$source" | xargs)"
  [[ "$fixture" == ref-* ]] || continue
  rows=$(( rows + 1 ))
  seen["$fixture"]=1

  case "$band" in
    full|medium|light) dist[$band]=$(( dist[$band] + 1 )) ;;
    *) echo "FAIL ${fixture}: '${band}' is not a band (full|medium|light)" >&2
       under=$(( under + 1 )); continue ;;
  esac

  local_fixture="$FIXTURE_DIR/${fixture}.md"
  if [[ ! -f "$local_fixture" ]]; then
    echo "FAIL ${fixture}: reference row has no fixture at ${local_fixture}" >&2
    missing=$(( missing + 1 )); continue
  fi

  # --project-root is explicit: without it the gate defaults to $(pwd), and the
  # 23 reference rows would be checked against whatever policy override the
  # caller happens to be standing in rather than against the shipped map.
  actual="$(bash "$GATE" --plan "$local_fixture" --project-root "$REPO_ROOT" --classify-only 2>/dev/null)"
  if [[ "$actual" == "$band" ]]; then
    agreed=$(( agreed + 1 ))
    continue
  fi
  if [[ "$(_band_rank "$actual")" -lt "$(_band_rank "$band")" ]]; then
    echo "FAIL ${fixture} (${source}): UNDER-CLASSIFIED — hand label ${band}, classifier says ${actual}" >&2
    under=$(( under + 1 ))
  else
    echo "FAIL ${fixture} (${source}): over-classified — hand label ${band}, classifier says ${actual}" >&2
    over=$(( over + 1 ))
  fi
done < "$REFERENCE"

orphans=0
for f in "$FIXTURE_DIR"/ref-*.md; do
  [[ -e "$f" ]] || continue
  name="$(basename "$f" .md)"
  [[ -n "${seen[$name]:-}" ]] && continue
  echo "FAIL ${name}: fixture exists but no row in ${REFERENCE} labels it" >&2
  orphans=$(( orphans + 1 ))
done

if [[ "$rows" -eq 0 ]]; then
  echo "check-classification-reference: no reference rows parsed from ${REFERENCE}" >&2
  exit 1
fi

echo "check-classification-reference: ${agreed}/${rows} rows agree (full=${dist[full]} medium=${dist[medium]} light=${dist[light]})."
failures=$(( under + over + missing + orphans ))
if [[ "$failures" -gt 0 ]]; then
  echo "check-classification-reference: FAIL — ${under} under-classified, ${over} over-classified, ${missing} missing fixture(s), ${orphans} orphan fixture(s)." >&2
  exit 1
fi
echo "check-classification-reference: PASS — the map and the hand labels agree."
exit 0
