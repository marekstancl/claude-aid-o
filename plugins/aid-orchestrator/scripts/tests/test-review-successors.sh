#!/usr/bin/env bash
# aid-tier: t2
# test-review-successors.sh — every registry id that P094 removed or retired
# has a successor on record. Reads the id list of the registry at the commit
# before the P094 branch (scripts/tests/fixtures/review-successors/
# registry-ids-pre-P094.txt, committed), compares it with the live registry
# and requires a row in reference/review-successors.md for every id that is
# gone or `removed_scoped`, whose successor cell is an ACTIVE registry id or
# a recorded decision of the form `none (<who, when or where>)`. Fails when the fixture is missing:
# a comparison against nothing proves nothing.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REG="${PLUGIN}/defaults/enforcement-registry.yaml"
FIX="${SCRIPT_DIR}/fixtures/review-successors/registry-ids-pre-P094.txt"
TABLE="${PLUGIN}/reference/review-successors.md"
pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
trap 'echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"' EXIT

echo "TEST: the pre-P094 id fixture and the successor table exist"
[[ -f "$FIX" ]] && ok "fixture present ($(wc -l < "$FIX") ids)" || { bad "fixture missing: ${FIX}"; exit 1; }
[[ -f "$TABLE" ]] && ok "successor table present" || { bad "successor table missing: ${TABLE}"; exit 1; }

live_active="$(yq -r '.enforcements[] | select(.status == "active") | .id' "$REG" | sort -u)"
live_all="$(yq -r '.enforcements[].id' "$REG" | sort -u)"
retired="$(yq -r '.enforcements[] | select(.status == "removed_scoped") | .id' "$REG" | sort -u)"
gone="$(comm -23 <(sort -u "$FIX") <(printf '%s\n' "$live_all"))"
# retired ids that the fixture knew (P087's max_parallel_one predates this table and is exempt by name)
retired_p094="$(comm -12 <(sort -u "$FIX") <(printf '%s\n' "$retired") | grep -v '^max_parallel_one$' \
  | grep -vE '^(scheduler_|test_audit_|test_catalog_|test_lane_|plan_start_clean|epic_start_clean|plan_merge_to_main|delegated_suite)' || true)"

echo "TEST: every removed or retired id has a successor row"
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  row="$(grep -E "^\| \`${id}\` \|" "$TABLE" || true)"
  if [[ -z "$row" ]]; then bad "no successor row for ${id}"; continue; fi
  succ="$(printf '%s' "$row" | awk -F'|' '{print $3}' | sed 's/^ *//;s/ *$//;s/`//g')"
  if [[ "$succ" == "none ("*")" ]]; then ok "${id} → ${succ}"
  elif grep -qxF "$succ" <<< "$live_active"; then ok "${id} → ${succ} (active)"
  else bad "${id} → '${succ}' is neither an active registry id nor a recorded 'none (…)' decision"; fi
done <<< "$(printf '%s\n%s\n' "$gone" "$retired_p094" | sort -u)"

echo "TEST: the table names no successor that does not exist"
while IFS= read -r succ; do
  [[ -n "$succ" && "$succ" != "none ("*")" ]] || continue
  grep -qxF "$succ" <<< "$live_all" && ok "successor ${succ} exists" || bad "successor ${succ} is not a registry id"
done <<< "$(awk -F'|' '/^## Mechanisms/ { skip = 1 } /^## Registry ids/ { skip = 0 } !skip && /^\| `/ { print $3 }' "$TABLE" | sed 's/^ *//;s/ *$//;s/`//g' | grep -v '^Successor$' | sort -u)"
[[ "$fail" -eq 0 ]]
