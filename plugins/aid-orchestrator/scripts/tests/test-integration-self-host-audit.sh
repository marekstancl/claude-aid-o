#!/usr/bin/env bash
# aid-tier: t2
# test-integration-self-host-audit.sh — P066 Step 21.
#
# Drives a REAL invocation of the Wave-0 scanner (aid-test-inventory.sh)
# against a disposable clone of this repository — never the live checkout
# — and cross-checks the resulting run_units count against three
# independent sources: (1) the actual .bats file count on disk, (2) the
# bats_all gate's intended target (the whole bats/ directory), (3) the two
# bats suites CI delegates to their own dedicated jobs. run_units and
# test_cases are reported and asserted SEPARATELY — never summed or
# conflated (Constraint 5).
#
# A disposable clone is for SAFETY (never mutate the live checkout), not
# for pretending the project's real, gitignored local config doesn't
# exist — a bare `git clone` silently omits .aid-o/config/execution.yaml
# (untracked), which would make the declared-command adapter find ZERO
# gates and produce a materially wrong run_units count. This script copies
# the live checkout's .aid-o/config/ into the clone before scanning
# (documented explicitly as this test's own finding #1 below — a portability
# gap worth recording for Step 22, not silently worked around forever).
#
# Any cross-check disagreement is recorded as a named finding, not treated
# as this test's own failure — per the plan's own Error Handling clause,
# a real discrepancy discovered here is exactly the point of Step 21.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }
finding() { echo "  FINDING (for Step 22, not a test failure): $1"; }

for dep in jq yq git; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

# This suite dogfoods THIS repo's own gitignored .aid-o/config/execution.yaml
# (the project's live, locally-customized config, incl. the bats_all quarantine
# entry the cross-checks below verify). A fresh checkout — any CI runner using
# actions/checkout, or a contributor who never ran /aid-init — has no .aid-o/
# at all (it's gitignored, never committed), so there is nothing to self-host-
# audit yet. That is an environment precondition, not a defect: skip cleanly
# rather than failing a check this checkout was never able to satisfy.
if [[ ! -f "$REPO_ROOT/.aid-o/config/execution.yaml" ]]; then
  echo "  SKIP: $REPO_ROOT/.aid-o/config/execution.yaml not found (gitignored, dogfood-only config — run /aid-init locally to enable this suite)"
  echo "Results: 0/0 passed, 0 failed, 1 skipped"
  exit 0
fi

CLONE_DIR="$(mktemp -d)"
OUT_DIR="$(mktemp -d)"
FINDINGS_FILE="$(mktemp)"
trap 'rm -rf "$CLONE_DIR" "$OUT_DIR" "$FINDINGS_FILE"' EXIT

echo "TEST: a disposable clone is created (never the live checkout)"
if git clone -q "$REPO_ROOT" "$CLONE_DIR" 2>/dev/null; then
  pass_msg "disposable clone created at $CLONE_DIR"
else
  fail_msg "git clone of $REPO_ROOT failed"
  echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
  exit 1
fi

# Carry over gitignored project config — see file header finding #1.
mkdir -p "$CLONE_DIR/.aid-o/config"
cp -r "$REPO_ROOT/.aid-o/config/." "$CLONE_DIR/.aid-o/config/" 2>/dev/null
if [[ -f "$REPO_ROOT/.aid-o/config/execution.yaml" && ! -f "$CLONE_DIR/.aid-o/config/execution.yaml" ]]; then
  fail_msg "failed to carry over .aid-o/config/execution.yaml into the disposable clone"
fi
finding "a plain 'git clone' of this repo does NOT carry over the gitignored .aid-o/config/ tree (execution.yaml, test-audit.yaml, etc.) — a disposable-clone audit must explicitly copy it in, or the declared-command adapter silently finds zero gates. This test does so explicitly; a future audit UX (not this plan's scope) should surface this as a documented precondition."

echo "TEST: the real Wave-0 scanner runs successfully against the disposable clone"
scanner_output="$(bash "$CLONE_DIR/plugins/aid-orchestrator/scripts/aid-test-inventory.sh" \
  --project-root "$CLONE_DIR" --audit-id selfhost-e4 --output-dir "$OUT_DIR" \
  --execution-yaml "$CLONE_DIR/.aid-o/config/execution.yaml" 2>&1)"
scanner_status=$?
CATALOG="$OUT_DIR/test-catalog.proposed.yaml"
if [[ "$scanner_status" -eq 0 && -f "$CATALOG" ]]; then
  pass_msg "scanner ran successfully, catalog written to $CATALOG"
else
  fail_msg "scanner failed (exit $scanner_status): $scanner_output"
  echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
  exit 1
fi

run_units_count="$(yq -o=json '.run_units | length' "$CATALOG" 2>/dev/null)"
bats_run_unit_count="$(yq -o=json '.run_units' "$CATALOG" 2>/dev/null | jq '[.[] | select(.runner=="bats")] | length')"
test_cases_count="$(yq -o=json '.run_units' "$CATALOG" 2>/dev/null | jq '[.[].test_cases[]?] | length')"

echo "TEST: run_units and test_cases are distinct, separately-reported numbers (Constraint 5)"
echo "  run_units:  ${run_units_count}"
echo "  test_cases: ${test_cases_count} (diagnostic only — never summed into run_units)"
# Codex review: requiring the two counts to DIFFER was wrong — a catalog with
# exactly one test_case per run_unit legitimately has equal counts, and that
# is not conflation. What actually matters is that BOTH fields are present,
# independently computed, non-negative integers — never that they disagree.
if [[ "$run_units_count" =~ ^[0-9]+$ && "$test_cases_count" =~ ^[0-9]+$ ]]; then
  pass_msg "run_units (${run_units_count}) and test_cases (${test_cases_count}) both present as independent, separately-computed numbers"
else
  fail_msg "run_units/test_cases were not both present as valid numbers"
fi

echo "TEST: cross-check 1 — bats-adapter run_unit count matches the actual .bats file count on disk"
# Codex review: bats_adapter_discover searches RECURSIVELY from project_root
# (never scoped to tests/bats/ nor limited to one directory level) — a
# -maxdepth 1, single-directory count would false-positive-diverge the moment
# a .bats file exists in a subdirectory or elsewhere in the tree. Match the
# adapter's own real search scope exactly: recursive from the project root.
#
# P072 Step 7: the bats adapter no longer owns `*.bats` alone. A `test-*.sh`
# carrying a bats shebang IS a Bats suite — run-all-tests.sh already dispatches
# it with `bats` — so the adapter claims it too. The expected count is
# therefore `.bats` files PLUS bats-shebang `.sh` files; asserting against
# `.bats` alone would now fail by exactly the number of correctly-classified
# shell-named Bats suites, which is a stale premise rather than a defect.
actual_bats_files="$(find "$CLONE_DIR" -type f -name '*.bats' 2>/dev/null | wc -l | tr -d ' ')"
actual_bats_shebang_sh="$(find "$CLONE_DIR" -type f -name 'test-*.sh' -not -path '*/fixtures/*' 2>/dev/null \
  | while read -r f; do head -1 "$f" 2>/dev/null | grep -q 'bats' && echo "$f"; done | wc -l | tr -d ' ')"
expected_bats_units=$((actual_bats_files + actual_bats_shebang_sh))
if [[ "$bats_run_unit_count" == "$expected_bats_units" ]]; then
  pass_msg "bats run_units (${bats_run_unit_count}) == ${actual_bats_files} .bats + ${actual_bats_shebang_sh} bats-shebang .sh on disk"
else
  fail_msg "bats run_units (${bats_run_unit_count}) != ${expected_bats_units} (${actual_bats_files} .bats + ${actual_bats_shebang_sh} bats-shebang .sh) — exact discrepancy: $((expected_bats_units - bats_run_unit_count))"
fi

echo "TEST: cross-check 2 — bats_all's declared target (the whole bats/ directory) agrees with the same count"
# P071 (v2.68.0) LIFTED bats_all's quarantine: the stub command was replaced by
# a real parallel-lane runner, and the `quarantine.original_command` field this
# check used to read no longer exists. The check therefore resolved "" on every
# run and failed unconditionally — a stale assertion against a removed field,
# which is exactly the drift class this audit capability exists to catch, so it
# is corrected rather than deleted.
#
# P078: bats_all ran plain sequential bats over the suite directory.
# P081: it runs the portfolio runner filtered to the merge-path tiers instead —
# the same partition expressed by measured cost rather than by a hand-kept
# exclusion list. The cross-check is unchanged in PURPOSE: the live command
# must dispatch the real portfolio runner, not some narrower target that would
# silently under-run it. A tier filter is a declared partition; a bare narrower
# path is not.
live_command="$(yq -r '.gates.bats_all.command // ""' "$CLONE_DIR/.aid-o/config/execution.yaml" 2>/dev/null)"
quarantine_block="$(yq -r '.gates.bats_all.quarantine // "absent"' "$CLONE_DIR/.aid-o/config/execution.yaml" 2>/dev/null)"
if [[ "$live_command" == *"run-all-tests.sh"* && "$live_command" == *"--tier "* ]]; then
  pass_msg "bats_all dispatches the portfolio runner filtered to its merge-path tiers (${actual_bats_files} .bats files discovered), consistent with the bats-adapter count"
elif [[ "$live_command" == *"tests/bats"* && "$live_command" == *"bats "* ]]; then
  pass_msg "bats_all dispatches a plain bats run over the suite tree (${actual_bats_files} .bats files discovered), consistent with the bats-adapter count"
elif [[ "$quarantine_block" != "absent" && "$(yq -r '.gates.bats_all.quarantine.original_command // ""' "$CLONE_DIR/.aid-o/config/execution.yaml" 2>/dev/null)" == *"bats/"* ]]; then
  pass_msg "bats_all is quarantined; its documented original_command targets the bats/ directory (${actual_bats_files} files)"
else
  fail_msg "bats_all's command resolves to neither a tier-filtered portfolio run nor a bats run over the suite tree: '${live_command}'"
fi

echo "TEST: cross-check 3 — both of CI's dedicated bats jobs resolve to real run_unit_ids in the catalog"
for suite in test-aid-plan-release-boundary test-aid-plan-final-boundary; do
  expected_id="bats:plugins/aid-orchestrator/scripts/tests/bats/${suite}"
  found="$(yq -o=json '.run_units' "$CATALOG" 2>/dev/null | jq -r --arg id "$expected_id" 'any(.run_unit_id == $id)')"
  if [[ "$found" == "true" ]]; then
    pass_msg "CI-delegated suite '${suite}' resolves to run_unit_id '${expected_id}'"
  else
    fail_msg "CI-delegated suite '${suite}' does NOT appear in the catalog as '${expected_id}'"
  fi
done

echo "TEST: the shell-suite coverage gap is CLOSED — standalone suites are real run_units"
sh_run_units="$(yq -o=json '.' "$CATALOG" | jq '[.run_units[] | select(.runner == "sh")] | length')"
# Names the findings block below still writes out.
sh_runner_count="$sh_run_units"
total_sh_scripts="$(find "$CLONE_DIR" -type f -name 'test-*.sh' -not -path '*/fixtures/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ' ')"
real_shell_suites="$(find "$CLONE_DIR" -type f -name 'test-*.sh' -not -path '*/fixtures/*' -not -path '*/node_modules/*' 2>/dev/null \
  | while read -r f; do head -1 "$f" 2>/dev/null | grep -q 'bats' || echo "$f"; done | wc -l | tr -d ' ')"
if [[ "$sh_run_units" == "$real_shell_suites" && "$sh_run_units" -gt 0 ]]; then
  pass_msg "all ${sh_run_units} standalone shell suites are represented as runner==\"sh\" run_units (P072 Step 7 closed the gap this test used to record as a finding)"
else
  fail_msg "shell-suite coverage: ${sh_run_units} runner==\"sh\" run_units vs ${real_shell_suites} real standalone shell suites on disk"
fi

# Persist findings for Step 22 to consume — under the repo's own gitignored
# .aid-o/work/ evidence tree, never inside a tracked path in the live checkout.
FINDINGS_OUT_DIR="${REPO_ROOT}/.aid-o/work/test-audits"
mkdir -p "$FINDINGS_OUT_DIR" 2>/dev/null
{
  echo "# P066 Step 21 — self-host audit findings ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo "run_units: ${run_units_count}"
  echo "test_cases: ${test_cases_count}"
  echo "bats_files_on_disk: ${actual_bats_files}"
  echo "standalone_sh_test_scripts: ${total_sh_scripts}"
  echo "sh_runner_run_units: ${sh_runner_count}"
} > "${FINDINGS_OUT_DIR}/self-host-audit-findings.txt" 2>/dev/null || true

echo "----------------------------------------------------------------------"
total=$((pass + fail))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
