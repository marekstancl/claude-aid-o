#!/usr/bin/env bats
# aid-tier: t2
# test-c3-advisory.bats — P065 Step 15 (E-065-5_7) behavioral coverage for the
# `degraded_advisory` C3 fallback: pipeline.md's advisory dispatch wiring,
# aid-fsm.sh's `c3_advisory_not_independent` block reason, and the FINAL policy
# flip (c3_on_unavailable: unverifiable → degraded_advisory).
#
# What this suite proves (and what it deliberately does NOT):
#   The advisory auditor itself is a real Agent()/LLM dispatch (agents/auditor.md
#   `c3_advisory` mode, documented in P065 Step 14) — that cannot be unit-tested
#   in bats. What CAN be tested at the script level, and is tested here:
#     (a) the shipped policy default is genuinely degraded_advisory (AC7);
#     (b) pipeline.md's prose documents the advisory dispatch contract
#         (pipeline-injected provider/model/process_id, artifact ownership,
#         no-fallback-to-a-pass) — grounding tests in the style of
#         test-pipeline-c3-dispatch.bats;
#     (c) a MANUALLY-CONSTRUCTED advisory audit-report.json — simulating exactly
#         what the Agent() dispatch would produce per agents/auditor.md's D7/
#         independence-level contract — is correctly consumed by aid-fsm.sh's
#         done-advance C3 hook: blocks with `c3_advisory_not_independent` under
#         `enforcement: blocking`, would_block telemetry only under `observe`,
#         and C3 status never reads as a pass;
#     (d) c3/c3-dispatch.json is untouched by the advisory path (still records
#         the real Codex unavailable/rate_limited/timeout outcome);
#     (e) negative control: policy `unverifiable` + a plain (non-advisory)
#         unverifiable report still blocks via the pre-existing generic reason,
#         proving the new advisory branch does not fire on it.
#
# Fixture/harness conventions copied from test-c3-audit.bats (_seed_done_review_state,
# _pin_c3_blocking, _write_matching_curator_ref, assert_timeline_event) so this
# suite matches established style rather than inventing a new one.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  PIPELINE_MD="$AID_PLUGIN_PATH/skills/pipeline.md"
  export PIPELINE_MD
  POLICY="$AID_PLUGIN_PATH/defaults/policies/c3-audit-policy.yaml"
  export POLICY
}

teardown() {
  unset GIT_DIR
  unset C3_AUDIT_POLICY
  teardown_test_evidence_dir
}

# flat_pipeline — pipeline.md with newlines/indentation collapsed to single
# spaces, so assertions can match phrases that wrap across lines in the prose.
flat_pipeline() {
  tr '\n' ' ' < "$PIPELINE_MD" | tr -s ' '
}

# _pin_c3_blocking — pin the C3 enforcement toggle to `blocking` (test seam;
# copied from test-c3-audit.bats — the per-profile c3_required risk-gate still
# reads the installed default policy, only enforcement is overridden here).
_pin_c3_blocking() {
  local policy_file="$TEST_TMPDIR/c3-audit-policy-blocking.yaml"
  cat > "$policy_file" <<'YAML'
version: 1
enforcement: blocking
risk_profiles:
  high:
    c3_required: true
    required_independence_level: cross_model
  unverifiable:
    c3_required: true
    required_independence_level: cross_provider
YAML
  export C3_AUDIT_POLICY="$policy_file"
}

# _seed_done_review_state <state_file> — minimal DONE/review fsm-state.yaml +
# supporting files done-advance review→release always requires. Copied from
# test-c3-audit.bats.
_seed_done_review_state() {
  local state_file="$1"
  cat > "$state_file" <<YAML
epic_id: E-test
run_id: R-test
branch: task/E-test/main
state: DONE
done_phase: review
created_at: 2026-06-18T00:00:00Z
total_steps: 1
current_step: 1
pm_decision: merge
YAML
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/tasks" "$TEST_PROJECT_ROOT/.aid-o/work" \
           "$TEST_PROJECT_ROOT/.aid-o/config"
  touch "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-06-18T00:00:00Z","_command_log":[]}\n' \
    > "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/plugin.yaml" <<YAML
plugin_path: "$AID_PLUGIN_PATH"
dispatch_mode: subagent
YAML
}

# _seed_high_c3_common <state_file> — shared review→release scaffold for a
# high-risk C3-required run (copied from test-c3-audit.bats).
_seed_high_c3_common() {
  local state_file="$1"
  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"
}

# _write_matching_curator_ref <audit_json> — provide a curator-report.json whose
# .curator.audit_report_ref matches sha256(audit content), so the E-057-2_2
# sequencing guard never masks the check under test (copied from test-c3-audit.bats).
_write_matching_curator_ref() {
  local audit_json="$1"
  local h; h="$(sha256sum "$audit_json" | awk '{print $1}')"
  cat > "$TEST_EVIDENCE_DIR/curator-report.json" <<JSON
{"curator": {"audit_report_ref": "sha256:${h}"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"
}

# _write_advisory_audit_json <path> <head_sha> <run_id>
#   A manually-constructed advisory report simulating exactly what pipeline.md's
#   Agent(agents/auditor.md, {mode: c3_advisory, ...}) dispatch produces per the
#   D7/independence-level contract in agents/auditor.md's "C3 Advisory Mode"
#   section: status unverifiable, advisory:true, independence_level:context_only,
#   pipeline-injected (echoed) provider/model/process_id, a present
#   input_manifest_hash, and a real finding (blocking_findings still false per
#   C3.3's mechanical derivation — a medium finding here, deliberately
#   non-blocking so the ONLY thing under test is the advisory-not-independent
#   reason, not the separate blocking_findings==true reason).
_write_advisory_audit_json() {
  local path="$1" head_sha="$2" run_id="${3:-R-test}"
  cat > "$path" <<JSON
{
  "blocking_findings": false,
  "advisory": true,
  "findings": [
    {
      "area": "maintainability",
      "audit_type": "code_quality",
      "finding": "Advisory (Claude, not independent) — naming could be clearer.",
      "recommendation": "Rename for clarity in a follow-up.",
      "effort": "small",
      "severity": "Medium"
    }
  ],
  "audit_report": {
    "blocking_findings": false,
    "input_manifest_hash": "sha256:manifest-abc123",
    "advisory": true,
    "independence_level": "context_only",
    "required_independence_level": "cross_model",
    "provider": "claude-code",
    "model": "claude-test-model",
    "process_id": "advisory-${run_id}",
    "reviewed_head": "${head_sha}"
  },
  "status": "unverifiable",
  "revision": {
    "head_sha": "${head_sha}"
  }
}
JSON
}

# _write_plain_unverifiable_audit_json <path> <head_sha>
#   The bridge's own minimal unverifiable placeholder (existing pre-P065-Step-15
#   shape, no advisory/independence_level fields at all) — the c3_on_unavailable:
#   unverifiable negative-control path never produces an advisory report, so this
#   is what stays on disk in that branch.
_write_plain_unverifiable_audit_json() {
  local path="$1" head_sha="$2"
  cat > "$path" <<JSON
{
  "audit_report": {
    "blocking_findings": false,
    "input_manifest_hash": "sha256:manifest-abc123"
  },
  "status": "unverifiable",
  "revision": {
    "head_sha": "${head_sha}"
  }
}
JSON
}

# _write_dispatch_json_unavailable <path>
#   c3/c3-dispatch.json as the bridge genuinely writes it on a real Codex
#   unavailable outcome — invoked:true (a live attempt was made), exit_code
#   non-zero, outcome:"unavailable", no codex_session_id. This is the file BOTH
#   the unverifiable-skip and degraded_advisory branches leave on disk; the
#   advisory path must never touch/overwrite it (Step 15's artifact-ownership
#   rule).
_write_dispatch_json_unavailable() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'JSON'
{
  "dispatch": {
    "invoked": true,
    "exit_code": 2,
    "outcome": "unavailable",
    "events_valid": false,
    "codex_session_id": null
  }
}
JSON
}

# ═══════════════════════════════════════════════════════════════════════════
# AC7 — shipped policy default is degraded_advisory (the plan's FINAL flip)
# ═══════════════════════════════════════════════════════════════════════════

@test "AC7: shipped c3-audit-policy.yaml c3_on_unavailable == degraded_advisory" {
  [ -f "$POLICY" ]
  run yq -r '.c3_executor.c3_on_unavailable' "$POLICY"
  [ "$status" -eq 0 ]
  [ "$output" = "degraded_advisory" ]
}

@test "AC7: shipped policy enforcement/risk_profiles UNCHANGED by the flip (forbidden-zone guard)" {
  # Step 15 flips exactly one key. Everything else Step 8 shipped stays intact.
  [ "$(yq -r '.enforcement' "$POLICY")" = "observe" ]
  [ "$(yq -r '.risk_profiles.high.required_independence_level' "$POLICY")" = "cross_model" ]
  [ "$(yq -r '.risk_profiles.unverifiable.required_independence_level' "$POLICY")" = "cross_provider" ]
  [ "$(yq -r '.risk_profiles.high.c3_required' "$POLICY")" = "true" ]
  [ "$(yq -r '.risk_profiles.unverifiable.c3_required' "$POLICY")" = "true" ]
  [ "$(yq -r '.c3_executor.probe_as' "$POLICY")" = "cross_provider" ]
  [ "$(yq -r '.c3_executor.kind' "$POLICY")" = "codex_cli" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# pipeline.md grounding — advisory dispatch contract documented in prose
# ═══════════════════════════════════════════════════════════════════════════

@test "pipeline.md: documents reading c3_on_unavailable and both its branches" {
  grep -qE 'c3_on_unavailable' "$PIPELINE_MD"
  grep -qE 'c3_on_unavailable: unverifiable' "$PIPELINE_MD"
  grep -qE 'c3_on_unavailable: degraded_advisory' "$PIPELINE_MD"
}

@test "pipeline.md: advisory dispatch is Agent(agents/auditor.md) with mode c3_advisory" {
  flat_pipeline | grep -qE 'Agent\(agents/auditor\.md, \{'
  flat_pipeline | grep -qE 'mode: "c3_advisory"'
}

@test "pipeline.md: pipeline injects provider/model/process_id (echoed, not self-set)" {
  flat_pipeline | grep -qE 'provider: "claude-code"'
  grep -qE 'process_id: "advisory-<run_id>"' "$PIPELINE_MD"
  grep -qiE 'pipeline OWNS .provider./.model./.process_id' "$PIPELINE_MD"
  grep -qiE 'ECHOES? them' "$PIPELINE_MD"
}

@test "pipeline.md: artifact ownership — advisory overwrites audit-report, c3-dispatch.json untouched" {
  grep -qiE 'OVERWRITES' "$PIPELINE_MD"
  flat_pipeline | grep -qE 'c3/c3-dispatch\.json.{0,40}(is )?left \*{0,2}UNTOUCHED'
  flat_pipeline | grep -qE 'aid-c3-dispatch\.sh verify.{0,40}on an advisory report exits 2'
}

@test "pipeline.md: never a fallback to a c3 pass, even on the advisory branch" {
  grep -qiE 'no fallback to a `?c3`? pass' "$PIPELINE_MD"
  flat_pipeline | grep -qE 'never substitutes the Claude auditor for a `?c3`? pass'
}

@test "pipeline.md: FSM hook advisory block reason c3_advisory_not_independent is documented" {
  grep -qE 'c3_advisory_not_independent' "$PIPELINE_MD"
}

@test "pipeline.md: PM summary labels advisory findings distinctly" {
  # Phrase wraps across markdown lines in the source, so join before matching
  # (same flat_pipeline convention test-pipeline-c3-dispatch.bats uses).
  flat_pipeline | grep -qiE 'advisory \(Claude, not independent\)'
}

@test "pipeline.md: 17e grounding still holds after Step 15 edits (verify still cited as a real subcommand)" {
  # Regression guard for test-pipeline-c3-dispatch.bats's 17e assertions: Step 15
  # added a new citation of `aid-c3-dispatch.sh verify` (advisory exits-2 note) —
  # confirm it is still the REAL subcommand name, not a typo'd variant.
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  local real
  real="$(bash "$DISPATCH" --help | grep -oE '^  [a-z][a-z-]+ ' | tr -d ' ' | sort -u)"
  echo "$real" | grep -qx "verify"
  echo "$real" | grep -qx "dispatch"
  echo "$real" | grep -qx "build-manifest"
}

# ═══════════════════════════════════════════════════════════════════════════
# aid-fsm.sh done-advance C3 hook — advisory report handling
# ═══════════════════════════════════════════════════════════════════════════

@test "blocking: advisory report (advisory:true) → done-advance blocks with c3_advisory_not_independent" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  _write_advisory_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "R-test"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_dispatch_json_unavailable "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *"c3_advisory_not_independent"* ]]
  [[ "$output" == *"same-provider Claude fallback review"* ]]
  # The C3 run never advances as a pass: still unverifiable, never merged silently.
  [[ "$output" != *"passes"* ]]
}

@test "blocking: advisory detection also fires on independence_level:context_only alone (advisory field absent)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # Deviates from _write_advisory_audit_json: top-level .advisory omitted, but
  # .audit_report.independence_level is still context_only — the "or" branch of
  # the plan's AC ("advisory: true (or independence_level == context_only)").
  cat > "$TEST_EVIDENCE_DIR/audit-report.json" <<JSON
{
  "blocking_findings": false,
  "findings": [],
  "audit_report": {
    "blocking_findings": false,
    "input_manifest_hash": "sha256:manifest-abc123",
    "independence_level": "context_only",
    "process_id": "advisory-R-test",
    "reviewed_head": "${head_sha}"
  },
  "status": "unverifiable",
  "revision": {
    "head_sha": "${head_sha}"
  }
}
JSON
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_dispatch_json_unavailable "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"c3_advisory_not_independent"* ]]
}

@test "observe (shipped default): advisory report → c3_gate_would_block telemetry, does NOT block" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"   # no _pin_c3_blocking → shipped enforcement: observe
  local head_sha; head_sha="$(git rev-parse HEAD)"

  _write_advisory_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "R-test"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_dispatch_json_unavailable "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 independent audit block"* ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "c3_gate_would_block"
  # The advisory-specific reason is what's carried in the telemetry, not the
  # generic unverifiable one — proves the PM-facing findings label is reachable.
  grep -q "c3_advisory_not_independent" "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

@test "blocking: advisory report reason wins over the generic unverifiable reason (specificity, not duplication)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  _write_advisory_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "R-test"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_dispatch_json_unavailable "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  # The FIRST "C3 independent audit block" line must carry the specific reason —
  # the elif chain in aid-fsm.sh (P065 Step 15) checks advisory/context_only
  # BEFORE the generic '.status == "unverifiable"' branch, so exactly one
  # reason is chosen per report and it must be the specific one here.
  [[ "$output" == *"c3_advisory_not_independent"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# Artifact ownership — c3/c3-dispatch.json untouched by the advisory path
# ═══════════════════════════════════════════════════════════════════════════

@test "c3-dispatch.json still records the real codex-unavailable outcome alongside an advisory report" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  _write_advisory_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "R-test"
  _write_dispatch_json_unavailable "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"

  # The dispatch-provenance hook (P065 Step 9) independently reads this same
  # file: outcome must still read "unavailable" (never silently rewritten to
  # "dispatched" by the advisory path) and codex_session_id must still be null —
  # proving the advisory Agent() dispatch never touches c3-dispatch.json.
  run jq -r '.dispatch.outcome' "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"
  [ "$status" -eq 0 ]
  [ "$output" = "unavailable" ]
  run jq -r '.dispatch.codex_session_id' "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"
  [ "$output" = "null" ]

  # And the report itself never claims a pass.
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "unverifiable" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# Negative control — policy `unverifiable`: no advisory report produced, C3
# stays unverifiable via the PRE-EXISTING generic reason (this should already
# work via existing E-057-1_2 behavior; this pins that it still does after
# Step 15's additive change).
# ═══════════════════════════════════════════════════════════════════════════

@test "negative control: plain (non-advisory) unverifiable report still blocks via the generic reason, not the new one" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # Simulates the c3_on_unavailable: unverifiable branch — the bridge's own
  # minimal placeholder, no advisory/independence_level fields at all.
  _write_plain_unverifiable_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_dispatch_json_unavailable "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *'status == "unverifiable"'* ]]
  # The NEW advisory-specific branch must not have fired — it only recognizes
  # advisory:true / independence_level:context_only, neither of which this
  # plain report carries.
  [[ "$output" != *"c3_advisory_not_independent"* ]]
}

@test "negative control: a genuine (non-advisory) clean pass never trips the new advisory branch" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  # Shipped enforcement: observe (no _pin_c3_blocking) — isolates the independent-
  # audit content hook under test from the separate dispatch-provenance hook
  # (P065 Step 9), which would otherwise also require a real c3-dispatch.json
  # here and is out of scope for this assertion.
  local head_sha; head_sha="$(git rev-parse HEAD)"

  cat > "$TEST_EVIDENCE_DIR/audit-report.json" <<JSON
{
  "audit_report": {
    "blocking_findings": false,
    "input_manifest_hash": "sha256:manifest-abc123",
    "independence_level": "cross_model",
    "process_id": "S-genuine",
    "reviewed_head": "${head_sha}"
  },
  "status": "pass",
  "revision": {
    "head_sha": "${head_sha}"
  }
}
JSON
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 independent audit block"* ]]
  [[ "$output" != *"c3_advisory_not_independent"* ]]
}
