#!/usr/bin/env bash
# test-integration-quarantine-pm-decision.sh — P069 Step 18.
#
# Exercises aid-quarantine-decision-record.sh against a disposable fixture
# git repo (never this plugin repo's own real evidence — those bundles are
# consumed by the script's own auto-discovery only when explicitly running
# against REPO_ROOT, which this test does NOT do). Confirms:
#   - both evidence sources (Step 15 remediation bundle, Step 17 E2E proof)
#     are presented as standalone, independently-resolved artifacts;
#   - a schema-valid decision record is producible ONLY via explicit PM
#     input (--decision/--reviewed-by/--rationale all required);
#   - a wrong-scenario or failing E2E artifact is never accepted, even if
#     it is the most recently modified file in the directory;
#   - missing evidence (either source) fails closed, no record written;
#   - no code path writes to execution.yaml's quarantine: block, ever,
#     even when decision:lift exists;
#   - the written record is force-tracked into git despite .aid-o/ being
#     gitignored;
#   - a second invocation for the same gate_id without --supersede is
#     refused, naming the existing record;
#   - a correct --supersede succeeds and the new record's own supersedes
#     field names the prior record's decided_at exactly.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DECISION_SCRIPT="${PLUGIN_DIR}/scripts/aid-quarantine-decision-record.sh"
SCHEMAS_DIR="${PLUGIN_DIR}/defaults/schemas"
DECISION_SCHEMA="${SCHEMAS_DIR}/quarantine-decision.schema.json"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${PLUGIN_DIR}/scripts/lib/aid-test-adapter-contract.sh"

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }

for dep in jq git python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

FIXTURE="$(mktemp -d)"
cleanup() { rm -rf "$FIXTURE"; }
trap cleanup EXIT

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email "test@example.com"
git -C "$FIXTURE" config user.name "Test"
mkdir -p "${FIXTURE}/.aid-o/work/evidence/quarantine-remediation"
mkdir -p "${FIXTURE}/.aid-o/work/evidence/e2e-full-path-proof"
mkdir -p "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions"
echo ".aid-o/" > "${FIXTURE}/.gitignore"
git -C "$FIXTURE" add .gitignore
git -C "$FIXTURE" commit -q -m "initial"

# ─── Build a schema-valid Step 15 remediation bundle ──────────────────────
remediation_json='{
  "gate_id": "bats_all",
  "commit_sha": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "membership_agreement": {"run_units_expected": 3, "run_units_observed": 3, "cross_check_sources": ["fixture"]},
  "shared_state_findings": [],
  "streamed_diagnostics_proof": {"proven": true, "example_log_path": "fixture.log"},
  "resume_without_orphan_proof": {"proven": true, "evidence_path": "fixture.bats"},
  "measured_runtime_ms": {"sequential_ms": 1000, "scheduled_ms": 400, "mode_tested": "observe_parallel"},
  "quarantine_lift_blocked": false,
  "plan_diff_scope_note": "plan_diff is explicitly OUT OF SCOPE for this plan (P069). Its documented root cause (aid-plan-diff.sh'"'"'s outer gate timeout equals its own internal per-AC timeout, so nested bats invocations exhaust the budget) is a timeout-architecture problem, not a scheduling/parallelism problem, and remains unaddressed by this bundle or this plan.",
  "evaluated_at": "2026-08-01T00:00:00Z"
}'
echo "TEST: fixture setup — the remediation bundle used by this test is itself schema-valid"
if adapter_validate_schema "${SCHEMAS_DIR}/quarantine-remediation-evidence.schema.json" "$remediation_json"; then
  pass_msg "fixture remediation bundle is schema-valid"
else
  fail_msg "fixture remediation bundle is NOT schema-valid — test fixture itself is broken"
fi
echo "$remediation_json" > "${FIXTURE}/.aid-o/work/evidence/quarantine-remediation/bats_all-deadbeef.json"

# ─── Build a schema-valid, pass:true, observe_parallel_full_path E2E proof ──
e2e_pass_json='{
  "run_id": "e2e-observe_parallel_full_path-fixture",
  "scenario": "observe_parallel_full_path",
  "pass": true,
  "stages_verified": [{"stage": "fixture_stage", "pass": true}],
  "commit_sha": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "evaluated_at": "2026-08-01T00:00:00Z"
}'
echo "TEST: fixture setup — the E2E proof used by this test is itself schema-valid"
if adapter_validate_schema "${SCHEMAS_DIR}/e2e-full-path-proof.schema.json" "$e2e_pass_json"; then
  pass_msg "fixture E2E proof is schema-valid"
else
  fail_msg "fixture E2E proof is NOT schema-valid — test fixture itself is broken"
fi
echo "$e2e_pass_json" > "${FIXTURE}/.aid-o/work/evidence/e2e-full-path-proof/e2e-observe_parallel_full_path-fixture.json"

# A NEWER, but wrong-scenario/failing artifact — must never be picked over
# the valid one above, even though it has a later mtime.
sleep 1.1
e2e_wrong_scenario_json='{
  "run_id": "e2e-sequential_regression-fixture",
  "scenario": "sequential_regression",
  "pass": true,
  "stages_verified": [{"stage": "fixture_stage", "pass": true}],
  "commit_sha": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "evaluated_at": "2026-08-01T00:00:05Z"
}'
echo "$e2e_wrong_scenario_json" > "${FIXTURE}/.aid-o/work/evidence/e2e-full-path-proof/e2e-sequential_regression-fixture.json"
e2e_failing_json='{
  "run_id": "e2e-observe_parallel_full_path-fixture-failing",
  "scenario": "observe_parallel_full_path",
  "pass": false,
  "stages_verified": [{"stage": "fixture_stage", "pass": false}],
  "commit_sha": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "evaluated_at": "2026-08-01T00:00:06Z"
}'
echo "$e2e_failing_json" > "${FIXTURE}/.aid-o/work/evidence/e2e-full-path-proof/e2e-observe_parallel_full_path-fixture-failing.json"

# ─── A dummy execution.yaml with a quarantine: block — must survive byte-for-byte ──
execution_yaml_before='gates:
  bats_all:
    quarantine:
      quarantined: true
      reason: pre-existing
'
mkdir -p "${FIXTURE}/.aid-o/config"
printf '%s' "$execution_yaml_before" > "${FIXTURE}/.aid-o/config/execution.yaml"
# Re-read via the SAME `cat` command substitution used for later comparisons
# below, so a trailing-newline stripping difference between "how the
# baseline was assigned" and "how it's read back" can never itself cause a
# false failure.
execution_yaml_before="$(cat "${FIXTURE}/.aid-o/config/execution.yaml")"

# ─── Scenario 1: missing evidence entirely fails closed ───────────────────
echo "TEST: with NO evidence present at all, the script refuses and writes nothing"
EMPTY_FIXTURE="$(mktemp -d)"
git -C "$EMPTY_FIXTURE" init -q
git -C "$EMPTY_FIXTURE" config user.email "test@example.com"
git -C "$EMPTY_FIXTURE" config user.name "Test"
out="$(bash "$DECISION_SCRIPT" --project-root "$EMPTY_FIXTURE" --gate-id bats_all \
  --decision lift --reviewed-by "Marek" --rationale "test" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && ! find "${EMPTY_FIXTURE}" -path "*/quarantine-decisions/*.json" 2>/dev/null | grep -q .; then
  pass_msg "refused with no evidence present (exit ${rc}), no record written"
else
  fail_msg "did not refuse cleanly with no evidence present (exit ${rc}): ${out}"
fi
rm -rf "$EMPTY_FIXTURE"

# ─── Scenario 2: remediation bundle present, E2E proof missing ────────────
echo "TEST: with remediation evidence but NO E2E proof, the script refuses"
PARTIAL_FIXTURE="$(mktemp -d)"
git -C "$PARTIAL_FIXTURE" init -q
git -C "$PARTIAL_FIXTURE" config user.email "test@example.com"
git -C "$PARTIAL_FIXTURE" config user.name "Test"
mkdir -p "${PARTIAL_FIXTURE}/.aid-o/work/evidence/quarantine-remediation"
echo "$remediation_json" > "${PARTIAL_FIXTURE}/.aid-o/work/evidence/quarantine-remediation/bats_all-deadbeef.json"
out="$(bash "$DECISION_SCRIPT" --project-root "$PARTIAL_FIXTURE" --gate-id bats_all \
  --decision lift --reviewed-by "Marek" --rationale "test" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -qi "e2e" <<<"$out" \
   && ! find "${PARTIAL_FIXTURE}" -path "*/quarantine-decisions/*.json" 2>/dev/null | grep -q .; then
  pass_msg "refused with missing E2E proof (exit ${rc}), message names the E2E gap, no record written"
else
  fail_msg "did not refuse correctly with missing E2E proof (exit ${rc}): ${out}"
fi

# Wrong-gate-id renamed remediation file: a remediation bundle for a
# DIFFERENT gate_id, filename-renamed to match this gate_id's glob, must
# never be picked up just because its filename matches.
echo "TEST: a remediation bundle whose OWN gate_id disagrees with its filename is excluded from discovery"
wrong_gate_remediation="$(jq -c '.gate_id = "some_other_gate"' <<<"$remediation_json")"
echo "$wrong_gate_remediation" > "${PARTIAL_FIXTURE}/.aid-o/work/evidence/quarantine-remediation/bats_all-wronggate.json"
mkdir -p "${PARTIAL_FIXTURE}/.aid-o/work/evidence/e2e-full-path-proof"
out_wg="$(bash "$DECISION_SCRIPT" --project-root "$PARTIAL_FIXTURE" --gate-id bats_all \
  --decision lift --reviewed-by "Marek" --rationale "test" 2>&1)"
rc_wg=$?
# Still refused (this fixture still has no E2E proof), but for the RIGHT
# reason — the real remediation bundle IS present and should be found; only
# the wrong-gate one should be skipped. Assert it's still the E2E gap that
# blocks, never a false "no remediation bundle found".
if [[ $rc_wg -ne 0 ]] && grep -qi "e2e" <<<"$out_wg" && ! grep -qi "no schema-valid quarantine-remediation-evidence bundle" <<<"$out_wg"; then
  pass_msg "wrong-gate-id file correctly excluded; the real bats_all bundle was still found (blocked on E2E only)"
else
  fail_msg "wrong-gate-id exclusion did not behave as expected (exit ${rc_wg}): ${out_wg}"
fi
rm -rf "$PARTIAL_FIXTURE"

# ─── Scenario 2b: omitting any required PM-input flag refuses, no record written ──
echo "TEST: omitting --decision refuses and writes no record"
out_nodec="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --reviewed-by "Marek" --rationale "test" 2>&1)"
[[ $? -ne 0 ]] && pass_msg "refused without --decision" || fail_msg "did not refuse without --decision: ${out_nodec}"

echo "TEST: omitting --reviewed-by refuses and writes no record"
out_norb="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision lift --rationale "test" 2>&1)"
[[ $? -ne 0 ]] && pass_msg "refused without --reviewed-by" || fail_msg "did not refuse without --reviewed-by: ${out_norb}"

echo "TEST: omitting --rationale refuses and writes no record"
out_norat="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision lift --reviewed-by "Marek" 2>&1)"
[[ $? -ne 0 ]] && pass_msg "refused without --rationale" || fail_msg "did not refuse without --rationale: ${out_norat}"

record_count_before_happy_path="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" 2>/dev/null | wc -l | tr -d ' ')"
echo "TEST: none of the omitted-flag invocations above wrote a record"
if [[ "$record_count_before_happy_path" -eq 0 ]]; then
  pass_msg "zero records written by any of the omitted-flag invocations"
else
  fail_msg "expected zero records, found ${record_count_before_happy_path}"
fi

# ─── Scenario 2c: a --supersede given with NO existing record is a dangling reference, refused ──
echo "TEST: --supersede given when no decision record exists yet for gate_id is refused (dangling reference)"
out_dangling="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision lift --reviewed-by "Marek" --rationale "test" --supersede "2020-01-01T00:00:00.000Z" 2>&1)"
rc_dangling=$?
record_count_after_dangling="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" 2>/dev/null | wc -l | tr -d ' ')"
if [[ $rc_dangling -ne 0 && "$record_count_after_dangling" -eq 0 ]]; then
  pass_msg "refused dangling --supersede with no existing record (exit ${rc_dangling}), no record written"
else
  fail_msg "did not refuse a dangling --supersede when no record exists yet (exit ${rc_dangling}, records=${record_count_after_dangling}): ${out_dangling}"
fi

# ─── Scenario 3: full happy path — both evidence sources present ─────────
echo "TEST: with both evidence sources present, the script succeeds and cites both standalone paths"
out="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision lift --reviewed-by "Marek" --rationale "quarantine lift approved after E2E proof" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "evidence_ref:" <<<"$out" && grep -q "e2e_evidence_ref:" <<<"$out"; then
  pass_msg "succeeded and printed both evidence_ref and e2e_evidence_ref"
else
  fail_msg "did not succeed / did not present both evidence sources (exit ${rc}): ${out}"
fi

first_record_path="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" | head -1)"
echo "TEST: a decision record file was actually written"
if [[ -n "$first_record_path" && -f "$first_record_path" ]]; then
  pass_msg "record written at ${first_record_path}"
else
  fail_msg "no record file found under quarantine-decisions/"
fi

echo "TEST: the written record correctly cites the fixture's OWN remediation bundle (never the wrong-scenario/failing E2E files)"
if [[ -n "$first_record_path" ]]; then
  record_json="$(jq -c '.' "$first_record_path")"
  ev_ref="$(jq -r '.evidence_ref' <<<"$record_json")"
  e2e_ref="$(jq -r '.e2e_evidence_ref' <<<"$record_json")"
  if [[ "$ev_ref" == *"bats_all-deadbeef.json" ]] && [[ "$e2e_ref" == *"e2e-observe_parallel_full_path-fixture.json" ]]; then
    pass_msg "evidence_ref and e2e_evidence_ref correctly resolved (wrong-scenario/failing files excluded)"
  else
    fail_msg "evidence_ref/e2e_evidence_ref resolved incorrectly: ev=${ev_ref} e2e=${e2e_ref}"
  fi
else
  fail_msg "cannot check citations — no record file found"
fi

echo "TEST: the record is schema-valid"
if [[ -n "$first_record_path" ]] && adapter_validate_schema "$DECISION_SCHEMA" "$(cat "$first_record_path")"; then
  pass_msg "record validates against quarantine-decision.schema.json"
else
  fail_msg "record failed schema validation"
fi

echo "TEST: the record's decision/reviewed_by/rationale match exactly what was passed on the command line"
if [[ -n "$first_record_path" ]]; then
  record_json="$(jq -c '.' "$first_record_path")"
  d="$(jq -r '.decision' <<<"$record_json")"
  rb="$(jq -r '.reviewed_by' <<<"$record_json")"
  rat="$(jq -r '.rationale' <<<"$record_json")"
  if [[ "$d" == "lift" && "$rb" == "Marek" && "$rat" == "quarantine lift approved after E2E proof" ]]; then
    pass_msg "decision/reviewed_by/rationale match exactly"
  else
    fail_msg "mismatch: decision=${d} reviewed_by=${rb} rationale=${rat}"
  fi
fi

echo "TEST: the record was force-tracked into git despite .aid-o/ being gitignored"
if [[ -n "$first_record_path" ]]; then
  rel="${first_record_path#"${FIXTURE}"/}"
  staged="$(git -C "$FIXTURE" status --porcelain -- "$rel")"
  if [[ "$staged" == A* ]]; then
    pass_msg "record shows as staged-added ('A') despite .gitignore covering .aid-o/"
  else
    fail_msg "record was not force-tracked (git status: '${staged}')"
  fi
fi

echo "TEST: execution.yaml's quarantine: block was never touched, byte-for-byte"
execution_yaml_after="$(cat "${FIXTURE}/.aid-o/config/execution.yaml")"
if [[ "$execution_yaml_after" == "$execution_yaml_before" ]]; then
  pass_msg "execution.yaml is byte-for-byte unchanged — no automatic quarantine: write ever occurred"
else
  fail_msg "execution.yaml was modified! No code path in this script should ever write to it"
fi

# ─── Scenario 4: second invocation for the SAME gate_id without --supersede is refused ──
echo "TEST: a second decision for the SAME gate_id, without --supersede, is refused and names the existing record"
out2="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision keep --reviewed-by "Marek" --rationale "changed my mind" 2>&1)"
rc2=$?
# Codex re-review: a bare `grep -qF "$(basename "$first_record_path")"` is
# tautologically true if first_record_path were ever empty (basename ""
# yields "." which then matches almost any output). The explicit
# non-empty guard makes this assertion meaningful.
if [[ -n "$first_record_path" ]] && [[ $rc2 -ne 0 ]] && grep -qF "$(basename "$first_record_path")" <<<"$out2"; then
  pass_msg "refused (exit ${rc2}) and named the existing record ${first_record_path}"
else
  fail_msg "did not refuse correctly or did not name the existing record (exit ${rc2}): ${out2}"
fi

record_count_after_refusal="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" | wc -l | tr -d ' ')"
echo "TEST: the refused second invocation wrote NO additional record file"
if [[ "$record_count_after_refusal" -eq 1 ]]; then
  pass_msg "still exactly 1 record file after the refused invocation"
else
  fail_msg "expected exactly 1 record file, found ${record_count_after_refusal}"
fi

# ─── Scenario 5: wrong --supersede value is refused ───────────────────────
echo "TEST: --supersede naming a decided_at that does NOT match the current record is refused, unchanged record count"
out3="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision keep --reviewed-by "Marek" --rationale "changed my mind" \
  --supersede "1999-01-01T00:00:00.000Z" 2>&1)"
rc3=$?
record_count_after_wrong_supersede="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" | wc -l | tr -d ' ')"
if [[ $rc3 -ne 0 ]] && grep -qi "supersede" <<<"$out3" && [[ "$record_count_after_wrong_supersede" -eq 1 ]]; then
  pass_msg "refused wrong --supersede value (exit ${rc3}), diagnostic mentions supersede, record count unchanged"
else
  fail_msg "did NOT refuse a wrong --supersede value correctly (exit ${rc3}, records=${record_count_after_wrong_supersede}): ${out3}"
fi

# ─── Scenario 6: correct --supersede succeeds, even fired IMMEDIATELY
# (no sleep) — proving millisecond-precision decided_at genuinely prevents
# same-second filename collisions rather than relying on wall-clock luck.
echo "TEST: correct --supersede (matching the CURRENT record's own decided_at), fired with no delay, succeeds without collision"
first_decided_at="$(jq -r '.decided_at' "$first_record_path")"
out4="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision keep --reviewed-by "Marek" --rationale "decided to keep quarantined after all" \
  --supersede "$first_decided_at" 2>&1)"
rc4=$?
if [[ $rc4 -eq 0 ]]; then
  pass_msg "succeeded with correct --supersede (exit ${rc4})"
else
  fail_msg "did NOT succeed with a correct --supersede value (exit ${rc4}): ${out4}"
fi

second_record_path="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" | grep -v -F "$first_record_path" | head -1)"
echo "TEST: the new record's own supersedes field names the prior record's decided_at exactly"
if [[ -n "$second_record_path" ]]; then
  supersedes_field="$(jq -r '.supersedes // empty' "$second_record_path")"
  if [[ "$supersedes_field" == "$first_decided_at" ]]; then
    pass_msg "new record's supersedes == '${first_decided_at}'"
  else
    fail_msg "new record's supersedes field ('${supersedes_field}') does not match prior decided_at ('${first_decided_at}')"
  fi
else
  fail_msg "no second record file found after the successful --supersede invocation"
fi

record_count_final="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" | wc -l | tr -d ' ')"
echo "TEST: the superseded (prior) record file was NOT deleted"
if [[ "$record_count_final" -eq 2 && -f "$first_record_path" ]]; then
  pass_msg "both records still present on disk (${record_count_final} files) — superseded record retained, never deleted"
else
  fail_msg "expected 2 record files with the original preserved, found ${record_count_final}"
fi

# ─── Scenario 7: fork prevention — superseding a NON-leaf (already-superseded) record is refused ──
# At this point the chain is: first_record_path (A) -> second_record_path (B, current leaf).
# Attempting to supersede A again (instead of the current leaf B) must be refused, closing the
# "A -> B, then also A -> C, both B and C look authoritative" fork Codex identified.
echo "TEST: attempting to supersede an already-superseded (non-leaf) record is refused"
out5="$(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision defer --reviewed-by "Marek" --rationale "attempt to fork from a stale ancestor" \
  --supersede "$first_decided_at" 2>&1)"
rc5=$?
record_count_after_fork_attempt="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" | wc -l | tr -d ' ')"
if [[ $rc5 -ne 0 ]] && [[ "$record_count_after_fork_attempt" -eq 2 ]]; then
  pass_msg "refused superseding a non-leaf ancestor (exit ${rc5}), record count still 2 — no fork created"
else
  fail_msg "did NOT refuse a fork attempt off a non-leaf record (exit ${rc5}, records=${record_count_after_fork_attempt}): ${out5}"
fi

# ─── Scenario 7b: genuine concurrency — two invocations racing to supersede the SAME current leaf ──
# Codex re-review (HIGH): the leaf-only guard above is only correct for
# SEQUENTIAL invocations — without serialization, two concurrent processes
# can both observe the current leaf, both pass the --supersede check, and
# both write a new record, producing two leaves (a fork). Fired genuinely
# in parallel (both backgrounded, waited on together) rather than
# sequentially, to actually exercise the flock added around discovery-
# through-write, not just assert it exists in the source.
echo "TEST: two invocations racing to supersede the SAME current leaf — exactly one succeeds, no fork is created"
current_leaf_decided_at="$(jq -r '.decided_at' "$second_record_path")"
race_out_a="$(mktemp)"; race_out_b="$(mktemp)"
(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision keep --reviewed-by "RaceA" --rationale "racing invocation A" \
  --supersede "$current_leaf_decided_at" > "$race_out_a" 2>&1; echo $? >> "$race_out_a") &
race_pid_a=$!
(bash "$DECISION_SCRIPT" --project-root "$FIXTURE" --gate-id bats_all \
  --decision keep --reviewed-by "RaceB" --rationale "racing invocation B" \
  --supersede "$current_leaf_decided_at" > "$race_out_b" 2>&1; echo $? >> "$race_out_b") &
race_pid_b=$!
wait "$race_pid_a" "$race_pid_b" 2>/dev/null

race_rc_a="$(tail -1 "$race_out_a")"
race_rc_b="$(tail -1 "$race_out_b")"
race_successes=0
[[ "$race_rc_a" == "0" ]] && race_successes=$((race_successes + 1))
[[ "$race_rc_b" == "0" ]] && race_successes=$((race_successes + 1))
rm -f "$race_out_a" "$race_out_b"

if [[ "$race_successes" -eq 1 ]]; then
  pass_msg "exactly one of the two racing invocations succeeded (rc_a=${race_rc_a}, rc_b=${race_rc_b})"
else
  fail_msg "expected exactly 1 success among the racing invocations, got ${race_successes} (rc_a=${race_rc_a}, rc_b=${race_rc_b})"
fi

echo "TEST: after the race, the chain still has exactly ONE unsuperseded leaf (no fork)"
all_records_json="$(find "${FIXTURE}/.aid-o/work/evidence/quarantine-decisions" -name "bats_all-*.json" -exec jq -c '.' {} \; | jq -cs '.')"
leaves_after_race="$(jq -c '
  ([.[].supersedes // empty]) as $superseded
  | [.[] | select(([.decided_at] - $superseded) | length > 0)]
' <<<"$all_records_json")"
leaf_count_after_race="$(jq 'length' <<<"$leaves_after_race")"
if [[ "$leaf_count_after_race" -eq 1 ]]; then
  pass_msg "exactly 1 unsuperseded leaf remains after the race — no fork was created"
else
  fail_msg "expected exactly 1 leaf after the race, found ${leaf_count_after_race}"
fi

# ─── Scenario 8: a malformed existing decision record fails closed rather than being silently ignored ──
echo "TEST: a malformed (non-schema-valid) existing decision-record file causes a fail-closed refusal, never silent ignoring"
CORRUPT_FIXTURE="$(mktemp -d)"
git -C "$CORRUPT_FIXTURE" init -q
git -C "$CORRUPT_FIXTURE" config user.email "test@example.com"
git -C "$CORRUPT_FIXTURE" config user.name "Test"
mkdir -p "${CORRUPT_FIXTURE}/.aid-o/work/evidence/quarantine-remediation" \
         "${CORRUPT_FIXTURE}/.aid-o/work/evidence/e2e-full-path-proof" \
         "${CORRUPT_FIXTURE}/.aid-o/work/evidence/quarantine-decisions"
echo "$remediation_json" > "${CORRUPT_FIXTURE}/.aid-o/work/evidence/quarantine-remediation/bats_all-deadbeef.json"
echo "$e2e_pass_json" > "${CORRUPT_FIXTURE}/.aid-o/work/evidence/e2e-full-path-proof/e2e-observe_parallel_full_path-fixture.json"
echo '{"gate_id":"bats_all","decided_at":"2026-08-01T00:00:00.000Z"}' > "${CORRUPT_FIXTURE}/.aid-o/work/evidence/quarantine-decisions/bats_all-corrupt.json"
out_corrupt="$(bash "$DECISION_SCRIPT" --project-root "$CORRUPT_FIXTURE" --gate-id bats_all \
  --decision lift --reviewed-by "Marek" --rationale "test" --supersede "2026-08-01T00:00:00.000Z" 2>&1)"
rc_corrupt=$?
if [[ $rc_corrupt -ne 0 ]] && grep -qi "not schema-valid" <<<"$out_corrupt"; then
  pass_msg "refused due to malformed existing record (exit ${rc_corrupt}), diagnostic names the schema-validity problem"
else
  fail_msg "did not fail closed on a malformed existing decision record (exit ${rc_corrupt}): ${out_corrupt}"
fi
rm -rf "$CORRUPT_FIXTURE"

echo "TEST: execution.yaml is STILL byte-for-byte unchanged after all decision writes (lift, refusals, supersede)"
execution_yaml_final="$(cat "${FIXTURE}/.aid-o/config/execution.yaml")"
if [[ "$execution_yaml_final" == "$execution_yaml_before" ]]; then
  pass_msg "execution.yaml remains byte-for-byte unchanged after the full scenario sequence"
else
  fail_msg "execution.yaml was modified at some point during the scenario sequence!"
fi

echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
