#!/usr/bin/env bash
# test-integration-parallel-authority-e2e.sh — P072 EPIC 4.
#
# Drives the WHOLE parallel-safety chain from a clean clone, in the order a
# real user would hit it:
#
#   committed catalog -> lane partition -> helper drift -> the unit drops out
#   of EVERY consumer -> a valid pilot -> a decision proposal
#
# WHY THIS EXISTS AS A SEPARATE TEST
#   Every piece of this had a green unit suite while the chain as a whole was
#   broken in ways only the chain could show: the authoritative catalog was
#   never committed, so a clean clone had nothing eligible; the provenance hash
#   covered only a unit's own file, so a shared helper could acquire a lock
#   without revoking anything; and two of the three consumers read the raw
#   status and disagreed with the lane runner about the same unit.
#
#   A suite that exercises one component can never catch those. This one can,
#   because it starts from `git clone` and asks each consumer separately.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0
pass_msg() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
fail_msg() { echo "  FAIL: $1"; FAIL=$(( FAIL + 1 )); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CLONE="$TMP/clone"

# shellcheck disable=SC1090
source "$PLUGIN_DIR/scripts/lib/aid-test-catalog-provenance.sh"

echo "TEST: a clean clone carries the authoritative catalog"
git clone -q "$REPO_ROOT" "$CLONE" 2>/dev/null || { fail_msg "git clone failed"; exit 1; }
CAT="$CLONE/.aid-o/config/test-catalog.yaml"
if [[ -f "$CAT" ]]; then
  pass_msg "the catalog is present in a clean clone (it is tracked, not gitignored)"
else
  fail_msg "a clean clone has NO catalog at .aid-o/config/test-catalog.yaml — the authority is not committed"
  echo "Results: $PASS/$(( PASS + FAIL )) passed, $FAIL failed"; exit 1
fi

echo "TEST: the committed catalog actually carries eligible units"
SAFE_N="$(yq -r '[.run_units[] | select(.parallel.status == "safe")] | length' "$CAT" 2>/dev/null || echo 0)"
if [[ "$SAFE_N" -gt 0 ]]; then
  pass_msg "committed catalog carries $SAFE_N units with status=safe"
else
  fail_msg "committed catalog carries ZERO safe units — every test would run sequentially and the lane work would deliver nothing"
fi

# The lane runner needs the gitignored config siblings too.
mkdir -p "$CLONE/.aid-o/config"
cp -r "$REPO_ROOT/.aid-o/config/." "$CLONE/.aid-o/config/" 2>/dev/null

echo "TEST: the lane partition reproduces that pool from the clone"
PARTITION="$( cd "$CLONE" && bash "$CLONE/plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh" \
                --catalog "$CAT" --dry-run 2>/dev/null )"
POOL_N="$(sed -n 's/^SAFE_POOL (\([0-9]*\)).*/\1/p' <<<"$PARTITION")"
if [[ "${POOL_N:-0}" -gt 0 ]]; then
  pass_msg "lane --dry-run pools $POOL_N files from the committed catalog"
else
  fail_msg "lane --dry-run pooled nothing despite $SAFE_N safe units in the catalog"
fi

# Pick a pooled unit to drift.
VICTIM_FILE="$(sed -n '/^SAFE_POOL/,/^UNCLASSIFIED/p' <<<"$PARTITION" | sed -n '2p' | tr -d ' ')"
VICTIM_UNIT="bats:${VICTIM_FILE%.bats}"

echo "TEST: the chosen unit is eligible in EVERY consumer before the drift"
# Resolve ONLY the unit under test. Resolving the whole pool costs a closure
# hash per unit, and a shared-helper drift makes every dependent unit
# recompute — correct behaviour, but minutes of it, four times over.
ONLY="$TMP/only.txt"; printf '%s\n' "$VICTIM_UNIT" > "$ONLY"
_eff_of() {
  aid_test_catalog_effective_status_map "$CAT" "$CLONE" "" "$ONLY" 2>/dev/null \
    | jq -r --arg u "$VICTIM_UNIT" '.[$u] // "unknown"'
}
BEFORE="$(_eff_of)"
if [[ "$BEFORE" == "safe" ]]; then
  pass_msg "shared resolver reports '$VICTIM_UNIT' as safe"
else
  fail_msg "shared resolver reports '$VICTIM_UNIT' as '$BEFORE' before any drift"
fi

echo "TEST: a SHARED HELPER acquiring a lock revokes the unit"
# The unit's own file is deliberately untouched: this is the bypass that a
# declared-paths-only hash could not see.
HELPER="$CLONE/plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash"
VICTIM_BEFORE_SHA="$(sha256sum "$CLONE/$VICTIM_FILE" | cut -d' ' -f1)"
printf '\n# drift introduced by the e2e test\nflock /var/lock/aid-e2e.lock true 2>/dev/null || true\n' >> "$HELPER"
VICTIM_AFTER_SHA="$(sha256sum "$CLONE/$VICTIM_FILE" | cut -d' ' -f1)"

if [[ "$VICTIM_BEFORE_SHA" == "$VICTIM_AFTER_SHA" ]]; then
  pass_msg "the unit's own .bats file is byte-identical — only the shared helper changed"
else
  fail_msg "the test mutated the unit's own file, which would not prove the closure binding"
fi

AFTER="$(_eff_of)"
if [[ "$AFTER" == "unknown" ]]; then
  pass_msg "the shared resolver reverted '$VICTIM_UNIT' to unknown on a HELPER change alone"
else
  fail_msg "the shared resolver still reports '$AFTER' after its helper acquired a lock — the closure binding is not effective"
fi

echo "TEST: the lane runner drops it from the pool"
PARTITION2="$( cd "$CLONE" && bash "$CLONE/plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh" \
                 --catalog "$CAT" --dry-run 2>/dev/null )"
if sed -n '/^SAFE_POOL/,/^UNCLASSIFIED/p' <<<"$PARTITION2" | grep -qxF "  $VICTIM_FILE"; then
  fail_msg "the lane runner still pools '$VICTIM_FILE' after the helper drift"
else
  pass_msg "the lane runner no longer pools '$VICTIM_FILE'"
fi

echo "TEST: the SELECTOR agrees — no consumer keeps its own answer"
SEL_UNITS="$TMP/units.json"
jq -nc --arg u "$VICTIM_UNIT" '[{unit_id:$u}]' > "$SEL_UNITS"
SEL_EFF="$(_eff_of)"
if [[ "$SEL_EFF" == "unknown" ]]; then
  pass_msg "the resolver the selector and scheduler now share reports unknown for the same unit"
else
  fail_msg "the shared resolver reports '$SEL_EFF' — consumers would disagree with the lane runner"
fi

echo "TEST: an APPROVED overlay cannot rescue a unit provenance has revoked"
OVERLAY="$(jq -nc --arg u "$VICTIM_UNIT" '
  {status:"approved", overlay:[{run_unit_id:$u, promoted_status:"safe",
    catalog_fingerprint_at_promotion:"whatever"}]}')"
OV_EFF="$(aid_test_catalog_effective_status_map "$CAT" "$CLONE" "$OVERLAY" "$ONLY" 2>/dev/null \
           | jq -r --arg u "$VICTIM_UNIT" '.[$u] // "unknown"')"
if [[ "$OV_EFF" == "unknown" ]]; then
  pass_msg "provenance is a floor: an approved overlay did not promote a revoked unit"
else
  fail_msg "an overlay promoted a unit provenance had revoked (got '$OV_EFF') — the second authority is back"
fi

# Undo the drift so the rest of the chain runs against a clean tree.
git -C "$CLONE" checkout -- "plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash" 2>/dev/null

echo "TEST: a restored helper restores eligibility"
RESTORED="$(_eff_of)"
if [[ "$RESTORED" == "safe" ]]; then
  pass_msg "reverting the helper restored '$VICTIM_UNIT' to safe"
else
  fail_msg "the unit did not recover after the helper was restored (got '$RESTORED')"
fi

echo "Results: $PASS/$(( PASS + FAIL )) passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
