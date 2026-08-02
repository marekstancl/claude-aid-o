#!/usr/bin/env bash
# test-integration-quarantine-remediation-evidence.sh — P069 Step 15.
#
# Producer of the retained quarantine-remediation-evidence bundle
# (defaults/schemas/quarantine-remediation-evidence.schema.json) for this
# repository's own bats_all quarantine. Addresses every bats_all-specific
# quarantine-exit criterion with REAL measured data, never invented
# numbers, and explicitly states plan_diff is out of scope rather than
# silently omitting it (Constraint 9 / this plan's own scope narrowing).
#
# This script is a COLLECTOR, not the expensive measurement itself: the
# real, wall-clock-heavy work (running this repo's full ~83-unit bats_all
# suite sequentially AND scheduled, at least 3 times each, inside fresh
# disposable clones) is Step 7's aid-test-schedule-divergence-check.sh's
# own job — run separately, beforehand, via:
#   bash aid-test-schedule-divergence-check.sh run --project-root <repo> \
#     --unit-ids <full catalog run_unit_id CSV> --mode-tested observe_parallel
# repeated until 3 qualifying (pass:true) artifacts exist for the CURRENT
# commit. This script then locates that already-produced evidence and
# packages it into the schema-valid bundle — it does NOT itself trigger
# that expensive run, and correctly FAILS (never fabricates a bundle) when
# no qualifying evidence exists yet for the current commit.
#
# streamed_diagnostics_proof / resume_without_orphan_proof are properties
# of the scheduler/job mechanism itself (aid-job.sh / aid-test-scheduler.sh),
# not of this specific portfolio's contents — streamed_diagnostics_proof is
# established here directly (one real, fast, single-unit dispatch,
# proving a genuine per-unit stdout_path is produced); resume_without_orphan_proof
# cites the existing, already-passing "TERM mid-batch... zero orphaned
# process groups" test in test-aid-test-scheduler.bats rather than
# re-proving the identical property inline.
#
# Usage:
#   test-integration-quarantine-remediation-evidence.sh [--gate-id <id>] [--mode observe_parallel|parallel]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"
SCHEMA="${PLUGIN_DIR}/defaults/schemas/quarantine-remediation-evidence.schema.json"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${PLUGIN_DIR}/scripts/lib/aid-test-adapter-contract.sh"

gate_id="bats_all"
mode="observe_parallel"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gate-id) gate_id="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;;
    *) echo "unknown option '$1'" >&2; exit 2 ;;
  esac
done
case "$mode" in observe_parallel|parallel) ;; *) echo "--mode must be observe_parallel|parallel" >&2; exit 2 ;; esac

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }

for dep in jq yq git; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

REAL_CATALOG="${REPO_ROOT}/.aid-o/config/test-catalog.yaml"
if [[ ! -f "$REAL_CATALOG" ]]; then
  echo "  FAIL: ${REAL_CATALOG} does not exist — run aid-test-catalog-approve.sh first"
  echo "Results: 0/1 passed, 1 failed"
  exit 1
fi

commit_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
catalog_json="$(yq -o=json '.' "$REAL_CATALOG")"

# ALWAYS re-derived live — never a hardcoded constant (see schema comment:
# P066's own originally-planned "88" had already drifted to 83 by its
# release).
run_units_expected="$(jq '.run_units | length' <<<"$catalog_json")"
echo "TEST: run_units_expected is re-derived live from the current catalog, never hardcoded"
if [[ "$run_units_expected" -gt 0 ]]; then
  pass_msg "run_units_expected=${run_units_expected} (live from ${REAL_CATALOG})"
else
  fail_msg "catalog has zero run_units — nothing to measure"
fi

full_unit_ids_sorted_json="$(jq -cS '[.run_units[].run_unit_id] | sort' <<<"$catalog_json")"

# ─── Locate an already-produced, qualifying divergence-evidence artifact ──
# Qualifying: commit_sha matches CURRENT HEAD, mode_tested matches the
# requested mode, pass:true, and selected_unit_ids (sorted) equals the
# FULL current catalog's run_unit_id set exactly — this bundle represents
# the WHOLE bats_all portfolio, never a partial subset silently accepted
# as if it were complete.
evidence_dir="${REPO_ROOT}/.aid-o/work/evidence/scheduler-divergence"
qualifying_artifact=""
echo "TEST: a qualifying divergence-evidence artifact exists for the CURRENT commit, covering the FULL current catalog"
if [[ -d "$evidence_dir" ]]; then
  shopt -s nullglob
  for artifact in "${evidence_dir}"/*.json; do
    a_json="$(jq -c '.' "$artifact" 2>/dev/null)" || continue
    # Codex review: comparing fields via `jq -r` text output accepted a
    # malformed artifact with e.g. "pass":"true" (a STRING) exactly like
    # the real boolean. Validating against the artifact's own schema
    # first closes that off structurally — never re-implementing type
    # checks by hand for fields another schema already governs.
    adapter_validate_schema "${PLUGIN_DIR}/defaults/schemas/divergence-evidence.schema.json" "$a_json" >/dev/null 2>&1 || continue
    a_commit="$(jq -r '.commit_sha // empty' <<<"$a_json" 2>/dev/null)"
    a_mode="$(jq -r '.mode_tested // empty' <<<"$a_json" 2>/dev/null)"
    a_pass="$(jq -r '.pass // false' <<<"$a_json" 2>/dev/null)"
    [[ "$a_commit" == "$commit_sha" ]] || continue
    [[ "$a_mode" == "$mode" ]] || continue
    [[ "$a_pass" == "true" ]] || continue
    a_units_sorted="$(jq -cS '.selected_unit_ids // [] | sort' <<<"$a_json" 2>/dev/null)"
    [[ "$a_units_sorted" == "$full_unit_ids_sorted_json" ]] || continue
    qualifying_artifact="$artifact"
    break
  done
  shopt -u nullglob
fi

if [[ -z "$qualifying_artifact" ]]; then
  fail_msg "no qualifying divergence-evidence artifact found under ${evidence_dir} for commit ${commit_sha}, mode ${mode}, covering all ${run_units_expected} current run_units — run aid-test-schedule-divergence-check.sh first (this script is a collector, not the measurement itself)"
  echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
  exit 1
fi
pass_msg "found qualifying artifact: ${qualifying_artifact}"

artifact_json="$(jq -c '.' "$qualifying_artifact")"
membership_diff_len="$(jq '.membership_diff | length' <<<"$artifact_json")"
verdict_diff_len="$(jq '.verdict_diff | length' <<<"$artifact_json")"
run_units_observed="$(jq '.selected_unit_ids | length' <<<"$artifact_json")"

echo "TEST: membership/verdict agreement — any real divergence becomes a BLOCKING finding, never smoothed over"
shared_state_findings_json="[]"
if [[ "$membership_diff_len" -gt 0 || "$verdict_diff_len" -gt 0 ]]; then
  shared_state_findings_json="$(jq -nc --arg ref "$qualifying_artifact" '
    [{finding_id:"membership-or-verdict-divergence", description:"sequential and scheduled runs disagreed on unit membership and/or verdicts — see the cited divergence-evidence artifact for the exact unit(s)", severity:"blocking", evidence_ref:$ref}]
  ')"
  fail_msg "divergence detected (membership_diff=${membership_diff_len}, verdict_diff=${verdict_diff_len}) — recorded as a BLOCKING finding, not smoothed over"
else
  pass_msg "zero membership/verdict divergence — sequential and scheduled runs agreed exactly"
fi

# ─── streamed_diagnostics_proof — a real, fast, DIRECT aid-job.sh run ─────
# proving output is written to disk WHILE the process is still running
# (genuinely streamed), never buffered until exit — structural to the
# mechanism itself, not this portfolio's contents, so one trivial
# two-line/sleep-gapped unit is sufficient real proof; it does not
# require re-running the whole 83-unit suite. aid-job.sh's own `run` is
# asynchronous (returns immediately), letting this poll stdout.log mid-run.
#
# Codex review (HIGH): an earlier version cited a stdout path inside a
# tmp `proof_dir` that was then rm -rf'd before the bundle was even
# written — `proven:true` while citing a nonexistent log. The retained
# copy below (alongside the bundle, force-tracked into git) is what the
# bundle actually cites; a trap guarantees proof_dir itself is cleaned up
# on every exit path, including an early failure.
echo "TEST: streamed diagnostics — stdout is written to disk WHILE still running, never buffered until exit"
streamed_proven=false
streamed_log_path=""
proof_dir="$(mktemp -d)"
trap 'rm -rf "$proof_dir"' EXIT
proof_job_id="quarantine-remediation-streamed-proof"
bash "${PLUGIN_DIR}/scripts/aid-job.sh" run --jobs-dir "$proof_dir" --id "$proof_job_id" --deadline 30 \
  -- bash -c 'echo streamed-proof-line1; sleep 2; echo streamed-proof-line2' >/dev/null 2>&1
proof_stdout_path="${proof_dir}/${proof_job_id}/stdout.log"

# Bounded poll for line1 to land WHILE line2 has not yet appeared — the
# actual streaming proof.
saw_line1_early=false
for _ in $(seq 1 20); do
  if [[ -f "$proof_stdout_path" ]] && grep -q "streamed-proof-line1" "$proof_stdout_path" 2>/dev/null; then
    grep -q "streamed-proof-line2" "$proof_stdout_path" 2>/dev/null || saw_line1_early=true
    break
  fi
  sleep 0.1
done
# Bounded wait for the job's own terminal receipt before reading final content.
for _ in $(seq 1 300); do
  [[ -f "${proof_dir}/${proof_job_id}/result.json" ]] && break
  sleep 0.1
done

if $saw_line1_early && [[ -f "$proof_stdout_path" ]] \
   && grep -q "streamed-proof-line1" "$proof_stdout_path" 2>/dev/null \
   && grep -q "streamed-proof-line2" "$proof_stdout_path" 2>/dev/null; then
  streamed_log_path="${REPO_ROOT}/.aid-o/work/evidence/quarantine-remediation/${gate_id}-${commit_sha}-streamed-proof.log"
  mkdir -p "$(dirname "$streamed_log_path")"
  cp "$proof_stdout_path" "$streamed_log_path"
  streamed_proven=true
  pass_msg "stdout genuinely streamed (line1 visible before job completion) — retained at ${streamed_log_path}"
else
  fail_msg "could not prove genuine streamed (not buffered-until-exit) stdout writes"
fi

# ─── resume_without_orphan_proof — cites the existing, already-passing
# TERM-mid-batch test rather than re-proving the identical mechanism-level
# property inline.
echo "TEST: resume-without-orphan — the existing TERM-mid-batch regression test is present and names the right guarantee"
resume_proof_path="scripts/tests/bats/test-aid-test-scheduler.bats"
resume_proven=false
if [[ -f "${PLUGIN_DIR}/${resume_proof_path}" ]] && grep -q "zero orphaned process groups" "${PLUGIN_DIR}/${resume_proof_path}"; then
  resume_proven=true
  pass_msg "${resume_proof_path} contains the zero-orphaned-process-groups regression test"
else
  fail_msg "${resume_proof_path} missing or no longer names the zero-orphaned-process-groups guarantee"
fi

# Real measured runtime: this plan intentionally does NOT invent a number.
#
# EPIC 4 whole-diff review (HIGH): this previously read gate-runtime-
# baselines.yaml's concurrency_context samples — but those are ONLY ever
# recorded for a gate actually dispatched through aid-run-gates.sh's own
# scheduler integration (Step 14), which is scoped to the targeted_tests
# gate alone. bats_all (or any other quarantined gate this script is
# pointed at) never goes through that path, so its scheduled-mode
# duration could never actually exist there — a structural gap, not a
# "waiting for the real run" situation. Fixed by reading the duration
# directly from the qualifying divergence-evidence artifact itself
# (sequential_duration_ms/scheduled_duration_ms — added to that schema in
# this same whole-diff review), which is the ONE place a genuinely-
# measured full-selection runtime for an arbitrary gate can originate,
# since aid-test-schedule-divergence-check.sh performs and times both
# dispatches itself.
echo "TEST: measured runtime is read from the qualifying divergence-evidence artifact's own real measurement, never invented"
sequential_ms="$(jq -r '.sequential_duration_ms // 0' <<<"$artifact_json")"
scheduled_ms="$(jq -r '.scheduled_duration_ms // 0' <<<"$artifact_json")"
[[ "$sequential_ms" =~ ^[0-9]+$ ]] || sequential_ms=0
[[ "$scheduled_ms" =~ ^[0-9]+$ ]] || scheduled_ms=0
if [[ "$sequential_ms" -gt 0 ]]; then
  pass_msg "sequential_ms=${sequential_ms} read from ${qualifying_artifact}"
else
  fail_msg "no sequential_duration_ms recorded in ${qualifying_artifact}"
fi
if [[ "$scheduled_ms" -gt 0 ]]; then
  pass_msg "scheduled_ms=${scheduled_ms} (mode ${mode}) read from ${qualifying_artifact}"
else
  fail_msg "no scheduled_duration_ms recorded in ${qualifying_artifact}"
fi

# Codex review: length>0 flips true for an ADVISORY-only findings array
# too — the schema's own contract is specifically "ANY blocking finding",
# never "any finding at all".
quarantine_lift_blocked="false"
[[ "$(jq '[.[] | select(.severity == "blocking")] | length' <<<"$shared_state_findings_json")" -gt 0 ]] && quarantine_lift_blocked="true"

evaluated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
bundle_json="$(jq -nc \
  --arg gid "$gate_id" --arg csha "$commit_sha" \
  --argjson exp "$run_units_expected" --argjson obs "$run_units_observed" \
  --arg src "$qualifying_artifact" \
  --argjson findings "$shared_state_findings_json" \
  --argjson sproven "$streamed_proven" --arg slog "$streamed_log_path" \
  --argjson rproven "$resume_proven" --arg rpath "${resume_proof_path}" \
  --argjson seq_ms "$sequential_ms" --argjson sch_ms "$scheduled_ms" --arg mode "$mode" \
  --argjson blocked "$quarantine_lift_blocked" \
  --arg eat "$evaluated_at" \
  '{
    gate_id: $gid, commit_sha: $csha,
    membership_agreement: {run_units_expected: $exp, run_units_observed: $obs, cross_check_sources: [$src]},
    shared_state_findings: $findings,
    streamed_diagnostics_proof: {proven: $sproven, example_log_path: $slog},
    resume_without_orphan_proof: {proven: $rproven, evidence_path: $rpath},
    measured_runtime_ms: {sequential_ms: $seq_ms, scheduled_ms: $sch_ms, mode_tested: $mode},
    quarantine_lift_blocked: $blocked,
    plan_diff_scope_note: "plan_diff is explicitly OUT OF SCOPE for this plan (P069). Its documented root cause (aid-plan-diff.sh'\''s outer gate timeout equals its own internal per-AC timeout, so nested bats invocations exhaust the budget) is a timeout-architecture problem, not a scheduling/parallelism problem, and remains unaddressed by this bundle or this plan.",
    evaluated_at: $eat
  }')"

echo "TEST: the assembled bundle validates against quarantine-remediation-evidence.schema.json"
if ! adapter_validate_schema "$SCHEMA" "$bundle_json"; then
  fail_msg "bundle failed schema validation (or the validator itself is unavailable) — refusing to publish an unvalidated artifact"
  echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
  exit 1
fi
pass_msg "bundle validates against schema"

out_path="${REPO_ROOT}/.aid-o/work/evidence/quarantine-remediation/${gate_id}-${commit_sha}.json"
mkdir -p "$(dirname "$out_path")"
echo "$bundle_json" | jq '.' > "$out_path"
echo "  wrote ${out_path}"
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  rel="${out_path#"${REPO_ROOT}"/}"
  git -C "$REPO_ROOT" add -f -- "$rel"
  if [[ -n "$streamed_log_path" && -f "$streamed_log_path" ]]; then
    rel_log="${streamed_log_path#"${REPO_ROOT}"/}"
    git -C "$REPO_ROOT" add -f -- "$rel_log"
  fi
fi

echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
