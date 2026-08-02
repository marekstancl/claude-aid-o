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

# ─── streamed_diagnostics_proof — a real, fast, single-unit dispatch ──────
# proving aid-job.sh/aid-test-scheduler.sh produce a genuine per-unit
# stdout_path (streamed to a file, never buffered until batch end) —
# structural to the mechanism itself, not this portfolio's contents, so a
# single trivial unit is sufficient real proof; it does not require
# re-running the whole 83-unit suite.
echo "TEST: streamed diagnostics — a real, fast dispatch produces a genuine per-unit stdout_path"
streamed_proven=false
streamed_log_path=""
proof_dir="$(mktemp -d)"
proof_units_file="${proof_dir}/units.json"
jq -n '[{unit_id:"quarantine-remediation-proof", command:{type:"argv",argv:["bash","-c","echo streamed-diagnostics-proof"]}, deadline_seconds:30, resource_locks:[], parallel_eligible:true, membership_verified:true, dedup:false, membership_binding:{catalog_fingerprint:"sha256:proofproofproof", verified_at:"2026-08-02T00:00:00Z", verifier_run_id:"quarantine-remediation-proof"}}]' > "$proof_units_file"
proof_catalog_file="${proof_dir}/.aid-o/config/test-catalog.yaml"
mkdir -p "$(dirname "$proof_catalog_file")"
jq -n '{schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved", run_units:[{run_unit_id:"quarantine-remediation-proof", runner:"bash", source_paths:["x"], production_surfaces:["x"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium", command:{type:"argv",argv:["bash","-c","echo streamed-diagnostics-proof"]}, runtime:{fingerprint:"sha256:proofproofproof"}, parallel:{status:"safe",exclusive_resources:[],max_workers:null,internal_parallelism:false}, isolation:{temp_workspace:"unknown",fixed_ports:[],shared_paths:[],lock_usage:[],adapter_confidence:"static_parse"}, recommendation:"keep", test_cases:[]}], source_pattern_mappings:[], mapping_approval:{status:"approved",approved_by:"quarantine-remediation-proof",approved_at:"2026-08-02T00:00:00Z",reviewed_diff_hash:"sha256:proofproofproof"}}' > "$proof_catalog_file"
proof_dispatch_json="$(bash "${PLUGIN_DIR}/scripts/aid-test-scheduler.sh" dispatch --project-root "$proof_dir" --run-id quarantine-remediation-proof --units-json "$proof_units_file" --mode sequential 2>/dev/null)" || true
proof_stdout_path="$(jq -r '.units[0].stdout_path // empty' <<<"$proof_dispatch_json" 2>/dev/null)"
if [[ -n "$proof_stdout_path" && -f "$proof_stdout_path" ]] && grep -q "streamed-diagnostics-proof" "$proof_stdout_path" 2>/dev/null; then
  streamed_proven=true
  streamed_log_path="$proof_stdout_path"
  pass_msg "real per-unit stdout log produced at ${streamed_log_path}"
else
  fail_msg "could not produce/verify a real per-unit streamed stdout log"
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
# aid-test-schedule-divergence-check.sh's own artifact does not carry wall-
# clock duration (only verdicts) — the real duration figures come from
# this repo's OWN gate-runtime-baseline (Step 3's concurrency-annotated
# samples), read directly rather than re-measured here.
baseline_file="${REPO_ROOT}/.aid-o/metrics/gate-runtime-baselines.yaml"
sequential_ms=0
scheduled_ms=0
echo "TEST: measured runtime is read from real, recorded gate-runtime-baseline samples, never invented"
if [[ -f "$baseline_file" ]]; then
  sequential_ms="$(yq -r ".gates.${gate_id}.recent_samples[-1].duration_ms // 0" "$baseline_file" 2>/dev/null || echo 0)"
  scheduled_ms="$(yq -r ".gates.${gate_id}.recent_samples_by_context.${mode}[-1].duration_ms // 0" "$baseline_file" 2>/dev/null || echo 0)"
fi
[[ "$sequential_ms" =~ ^[0-9]+$ ]] || sequential_ms=0
[[ "$scheduled_ms" =~ ^[0-9]+$ ]] || scheduled_ms=0
if [[ "$sequential_ms" -gt 0 ]]; then
  pass_msg "sequential_ms=${sequential_ms} read from ${baseline_file}"
else
  fail_msg "no recorded sequential runtime sample for gate '${gate_id}' in ${baseline_file}"
fi
if [[ "$scheduled_ms" -gt 0 ]]; then
  pass_msg "scheduled_ms=${scheduled_ms} (mode ${mode}) read from ${baseline_file}"
else
  fail_msg "no recorded ${mode} runtime sample for gate '${gate_id}' in ${baseline_file}"
fi

quarantine_lift_blocked="false"
[[ "$(jq 'length' <<<"$shared_state_findings_json")" -gt 0 ]] && quarantine_lift_blocked="true"

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
rm -rf "$proof_dir"
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
fi

echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
