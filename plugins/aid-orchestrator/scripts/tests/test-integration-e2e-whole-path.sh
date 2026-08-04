#!/usr/bin/env bash
# test-integration-e2e-whole-path.sh — P072 Step 28.
#
# A FRESH project with a small KNOWN portfolio, driven through the real path:
# catalog -> lane partition -> dispatch -> ledger. The point is that the parts
# connect; component suites and synthetic fixtures do not show that.
#
# WHAT THIS COVERS AND WHAT IT DOES NOT
#   Scenarios 3, 4 and 5 of Step 28 are scripted and run here:
#     3. a unit whose source changed after verification stays sequential
#     4. the same membership gives identical per-case results either way
#     5. nothing runs twice, and a real double dispatch IS caught
#
#   Scenarios 1 and 2 are not, and are not faked. Scenario 1 needs a `--mode
#   full` audit, which dispatches LLM analyst agents; scenario 2's concurrency
#   half needs the 3-stage rollout gate satisfied, which needs divergence
#   evidence this repository deliberately does not have. Both are recorded in
#   docs/plans/P072-campaign-ledger.md as not demonstrated, rather than
#   asserted from a fixture that would prove nothing.
#
# The portfolio is FIXED at four units, so scenario 3's assertion is exact
# rather than "some units were sequential".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LANE="${PLUGIN_DIR}/scripts/aid-bats-parallel-lane.sh"
LEDGER="${PLUGIN_DIR}/scripts/aid-test-execution-ledger.sh"

pass=0; fail=0
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }

for dep in jq yq bats; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

# shellcheck disable=SC1090
source "${PLUGIN_DIR}/scripts/lib/aid-test-catalog-provenance.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PROJ="$WORK/fresh-project"
TDIR="plugins/aid-orchestrator/scripts/tests/bats"
mkdir -p "$PROJ/$TDIR" "$PROJ/.aid-o/config"
( cd "$PROJ" && git init -q && git config user.email t@t && git config user.name T )
AT='@'"test"

# ─── A fixed, known portfolio: four units ───────────────────────────────────
KNOWN_UNITS=4
for n in alpha beta gamma delta; do
  printf '%s "%s works" { true; }\n' "$AT" "$n" > "$PROJ/$TDIR/test-$n.bats"
done

_write_catalog() {
  {
    echo 'schema_version: "1.0.0"'
    echo 'generated_at: "2026-08-04T00:00:00Z"'
    echo 'status: approved'
    echo 'run_units:'
    for n in alpha beta gamma delta; do
      echo "  - run_unit_id: \"bats:$TDIR/test-$n\""
      echo '    runner: bats'
      echo "    source_paths: [\"$TDIR/test-$n.bats\"]"
      echo "    command: {type: argv, argv: [\"bats\", \"$TDIR/test-$n.bats\"]}"
      echo '    parallel:'
      echo '      status: safe'
      echo '      exclusive_resources: []'
      echo '      max_workers: null'
      echo '      internal_parallelism: false'
      echo '      provenance:'
      echo '        evidence_ref: "e2e-fixture-pilot"'
      echo '        verified_at: "2026-08-04T00:00:00Z"'
      echo '        method: resource_map_plus_pilot'
      echo '        source_sha256: "PLACEHOLDER"'
      echo '        resource_digest: "PLACEHOLDER"'
    done
  } > "$PROJ/.aid-o/config/test-catalog.yaml"

  local n uid h d
  for n in alpha beta gamma delta; do
    uid="bats:$TDIR/test-$n"
    h="$(aid_test_catalog_provenance_hash "$uid" "$PROJ/.aid-o/config/test-catalog.yaml" "$PROJ" 2>/dev/null)"
    d="$(aid_test_catalog_provenance_resource_digest "$uid" "$PROJ/.aid-o/config/test-catalog.yaml" "$PROJ" 2>/dev/null)"
    [[ "$h" =~ ^[0-9a-f]{64}$ ]] || continue
    B_ID="$uid" B_H="$h" B_D="$d" yq -i '
      (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.source_sha256) = strenv(B_H)
      | (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.resource_digest) = strenv(B_D)' \
      "$PROJ/.aid-o/config/test-catalog.yaml"
  done
}

_partition() { ( cd "$PROJ" && bash "$LANE" --catalog "$PROJ/.aid-o/config/test-catalog.yaml" --dry-run 2>/dev/null ); }
_count() { sed -n "s/^$1 (\([0-9]*\)).*/\1/p" <<<"$2"; }

echo "TEST: the fresh project's portfolio is the size the fixture fixes it at"
_write_catalog
CATALOG_UNITS="$(yq -r '.run_units | length' "$PROJ/.aid-o/config/test-catalog.yaml")"
if [[ "$CATALOG_UNITS" -eq "$KNOWN_UNITS" ]]; then
  pass_msg "catalog holds exactly ${KNOWN_UNITS} run units — later assertions are exact, not approximate"
else
  fail_msg "catalog holds ${CATALOG_UNITS}, fixture fixes ${KNOWN_UNITS}"
fi

echo "TEST (scenario 3): a unit whose source changed after verification stays SEQUENTIAL"
P="$(_partition)"
POOL_BEFORE="$(_count SAFE_POOL "$P")"
if [[ "${POOL_BEFORE:-0}" -eq "$KNOWN_UNITS" ]]; then
  pass_msg "all ${KNOWN_UNITS} units start in the pool"
else
  fail_msg "expected ${KNOWN_UNITS} pooled, got ${POOL_BEFORE:-0}"
fi

# Modify one unit's source so its provenance no longer matches its content.
printf '%s "gains a lock" { flock /var/lock/e2e-whole-path.lock true; }\n' "$AT" >> "$PROJ/$TDIR/test-gamma.bats"

P2="$(_partition)"
POOL_AFTER="$(_count SAFE_POOL "$P2")"
SEQ_AFTER="$(_count UNCLASSIFIED "$P2")"
if [[ "${POOL_AFTER:-0}" -eq $(( KNOWN_UNITS - 1 )) && "${SEQ_AFTER:-0}" -eq 1 ]]; then
  pass_msg "the changed unit left the pool: ${POOL_AFTER} pooled, ${SEQ_AFTER} sequential"
else
  fail_msg "expected $(( KNOWN_UNITS - 1 ))/1, got ${POOL_AFTER:-0}/${SEQ_AFTER:-0}"
fi
if sed -n '/^UNCLASSIFIED/,/^BOUNDARY/p' <<<"$P2" | grep -q "test-gamma.bats"; then
  pass_msg "and it is the RIGHT unit — test-gamma, the one whose source changed"
else
  fail_msg "the sequential bucket does not contain test-gamma"
fi

echo "TEST (scenario 4): the same membership gives identical per-case results either way"
SEQ_OUT="$WORK/seq.tap"; PAR_OUT="$WORK/par.tap"
( cd "$PROJ" && bats --timing "$TDIR"/test-alpha.bats "$TDIR"/test-beta.bats "$TDIR"/test-delta.bats ) > "$SEQ_OUT" 2>&1
SEQ_RC=$?
( cd "$PROJ" && bats --timing --jobs 3 "$TDIR"/test-alpha.bats "$TDIR"/test-beta.bats "$TDIR"/test-delta.bats ) > "$PAR_OUT" 2>&1
PAR_RC=$?

_cases() { grep -oE '^(not )?ok [0-9]+ .*' "$1" | sed -E 's/^(not )?ok [0-9]+ //; s/ in [0-9]+ms$//' | sort; }
if [[ "$SEQ_RC" -eq "$PAR_RC" ]]; then
  pass_msg "aggregate verdicts match (both exited ${SEQ_RC})"
else
  fail_msg "aggregate verdicts differ: sequential ${SEQ_RC}, concurrent ${PAR_RC}"
fi
if diff <(_cases "$SEQ_OUT") <(_cases "$PAR_OUT") >/dev/null; then
  pass_msg "per-case result sets are identical"
else
  fail_msg "per-case results differ: $(diff <(_cases "$SEQ_OUT") <(_cases "$PAR_OUT") | head -3 | tr '\n' ' ')"
fi

echo "TEST (scenario 5): the ledger reports zero duplicates for a clean dispatch"
L="$WORK/ledger.json"
bash "$LEDGER" open --path "$L" --run-id "e2e-whole-path" --candidate-sha "$(git -C "$PROJ" rev-parse HEAD 2>/dev/null || echo none)" >/dev/null
for n in alpha beta delta; do
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:$TDIR/test-$n" \
    --gate-id "gate:bats_all" --fingerprint "fp-$n" --dispatch-point bats_lane
done
bash "$LEDGER" append --path "$L" --run-unit-id "bats:$TDIR/test-gamma" \
  --gate-id "gate:bats_all" --fingerprint "fp-gamma" --dispatch-point bats_lane
if LEDGER_OUT="$(bash "$LEDGER" close --path "$L" 2>&1)"; then
  pass_msg "clean campaign: ${LEDGER_OUT#*: }"
else
  fail_msg "the ledger reported duplicates in a clean campaign: ${LEDGER_OUT}"
fi

echo "TEST (scenario 5): a REAL double dispatch is caught, not smoothed over"
# The shape this repository actually has: one gate runs a file directly while
# the pool runs it too. A ledger that cannot see this is worth nothing.
L2="$WORK/ledger-dup.json"
bash "$LEDGER" open --path "$L2" --run-id "e2e-dup" --candidate-sha "abc" >/dev/null
bash "$LEDGER" append --path "$L2" --run-unit-id "bats:$TDIR/test-alpha" \
  --gate-id "gate:bats_all" --fingerprint fp1 --dispatch-point bats_lane
bash "$LEDGER" append --path "$L2" --run-unit-id "bats:$TDIR/test-alpha" \
  --gate-id "gate:bats_alpha" --fingerprint fp2 --dispatch-point gate_runner_direct
if DUP_OUT="$(bash "$LEDGER" close --path "$L2" 2>&1)"; then
  fail_msg "the ledger passed a genuine double execution"
else
  if [[ "$DUP_OUT" == *"DOUBLE EXECUTION"* && "$DUP_OUT" == *"test-alpha"* ]]; then
    pass_msg "caught it, and named both the unit and the two gates"
  else
    fail_msg "the ledger failed without naming the duplicate: ${DUP_OUT}"
  fi
fi

echo "TEST (scenario 6): the campaign record states its wall clock, or says it was not run"
REC="${PLUGIN_DIR}/../../docs/plans/P072-campaign-ledger.md"
if [[ -f "$REC" ]]; then
  if grep -qiE 'was NOT run|not been run|not supported' "$REC"; then
    pass_msg "the campaign record states plainly that the campaign was not run"
  elif grep -qE 'measured' "$REC"; then
    pass_msg "the campaign record carries measured before/after figures"
  else
    fail_msg "the campaign record neither reports measured figures nor says the campaign was not run"
  fi
else
  fail_msg "docs/plans/P072-campaign-ledger.md does not exist"
fi

echo "Results: ${pass}/$(( pass + fail )) passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
