#!/usr/bin/env bats
# test-c3-activation.bats — E-059-1_2 Step 1 behavioral red-green suite for the
# IMP-177 C3 activation: producer wiring + deterministic mode substrate + FSM
# presence check (observe) + C3 gate enforcement toggle (observe/blocking).
#
# Grounding fact (why this suite exists): the C3 gate had NEVER fired in a live
# run — review-profile.json was produced only by tests, never by the DONE review
# flow, so the C3 hook in aid-fsm.sh was dead code from birth (E8/P057). This
# suite exercises the wake-up in OBSERVE mode: the gate now emits would_block
# telemetry and lets the transition through, and only blocks when enforcement is
# pinned to `blocking` via the C3_AUDIT_POLICY seam.
#
# Scenarios (map to the plan's (a)-(e) + AC2):
#   (a)  producer over the FULL diff → review-profile.json with a real
#        risk_profile (not the unverifiable-from-empty degenerate).
#   AC2  plan-time surface capture (resolvable epic) + fail-loud reason
#        (unresolvable epic) — silent diff-only profile is NOT acceptable.
#   (b)  aid-audit-mode.sh: high→c3, low→legacy_health, missing→exit 3.
#   (c)  FSM review-profile presence check: OBSERVE passes + would_block event;
#        simulated blocking (C3_AUDIT_POLICY override) → non-zero.
#   (d)  C3 gate: OBSERVE passes + c3_gate_would_block event; blocking → non-zero.
#   (e)  aid-prefilter.sh profile exit-22 (range_undetermined) → unverifiable
#        profile emitted, path is non-fatal.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  PREFILTER="$AID_PLUGIN_PATH/scripts/aid-prefilter.sh"
  export PREFILTER
  AUDIT_MODE="$AID_PLUGIN_PATH/scripts/lib/aid-audit-mode.sh"
  export AUDIT_MODE
  PIPELINE_MD="$AID_PLUGIN_PATH/skills/pipeline.md"
  export PIPELINE_MD
  INVMAP="$AID_PLUGIN_PATH/scripts/lib/aid-invalidation-map.sh"
  export INVMAP
  STAGE_LOG="$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh"
  export STAGE_LOG
  export AID_TEST_MODE=1
}

teardown() {
  unset GIT_DIR
  unset C3_AUDIT_POLICY
  unset INVALIDATION_MAP_ENFORCEMENT
  teardown_test_evidence_dir
}

# ─── Shared fixtures ────────────────────────────────────────────────────────

# _pin_c3_blocking — pin the C3 enforcement toggle to `blocking` (test override).
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

# _commit_scripts_core_diff — commit a high-risk (scripts_core) change so the
# base_commit..HEAD diff resolves to risk_profile=high, and record base_commit in
# fsm-state.yaml. Echoes nothing; leaves the repo one commit past base.
_commit_scripts_core_diff() {
  local base_commit; base_commit="$(git rev-parse HEAD)"
  mkdir -p plugins/aid-orchestrator/scripts/lib
  printf 'cmd_demo() { log_event x; }\nexit 0\n' > plugins/aid-orchestrator/scripts/lib/demo.sh
  git add -A && git commit -q -m "scripts_core change"
  cat > "$TEST_EVIDENCE_DIR/fsm-state.yaml" <<YAML
epic_id: E-test
run_id: R-test
project_id: testproj
base_commit: $base_commit
YAML
}

# _write_epic_file <path> — an EPIC task file whose Files section lists the same
# high-risk path, so plan-time surface capture is exercised.
_write_epic_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'MD'
# EPIC E-test

**Files:**
- `plugins/aid-orchestrator/scripts/lib/demo.sh`
MD
}

# _seed_clean_done_review <state_file> — a DONE/review state satisfying ALL
# done-advance review→release preconditions (mirrors test-fsm-dg07-observe.bats's
# clean seed) with NO pending child step, so the ONLY variable under test is the
# review-profile.json presence check.
_seed_clean_done_review() {
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
  mkdir -p "$TEST_EVIDENCE_DIR/gates" \
           "$TEST_PROJECT_ROOT/.aid-o/tasks" \
           "$TEST_PROJECT_ROOT/.aid-o/tasks/archive" \
           "$TEST_PROJECT_ROOT/.aid-o/work" \
           "$TEST_PROJECT_ROOT/.aid-o/config"
  touch "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-06-18T00:00:00Z","_command_log":[]}\n' \
    > "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/plugin.yaml" <<YAML
plugin_path: "$AID_PLUGIN_PATH"
dispatch_mode: subagent
YAML
  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  printf '_generated_by: aid-orchestrator:verifier@cp4-c3act-test\n_generated_at: 2026-06-18T00:00:00Z\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp4-curator-validation.md"
}

# ─── Scenario (a): producer over the full diff → real risk_profile ──────────

@test "(a) producer over base_commit..HEAD → review-profile.json with real risk_profile (not unverifiable-from-empty)" {
  export AID_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  _commit_scripts_core_diff
  local epic="$TEST_PROJECT_ROOT/.aid-o/tasks/E-test_1_1.md"
  _write_epic_file "$epic"

  run bash "$PREFILTER" profile "$epic" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -f "$TEST_EVIDENCE_DIR/review-profile.json" ]

  local risk; risk="$(jq -r '.review_profile.risk_profile' "$TEST_EVIDENCE_DIR/review-profile.json")"
  [ "$risk" = "high" ]
  # Red baseline: today (pre-wiring) the gate never fired because this file was
  # never produced. Green: a real risk_profile computed over the full diff.
  [ "$risk" != "unverifiable" ]
}

# ─── AC2: plan-time surface capture + fail-loud on unresolvable epic ────────

@test "AC2 (positive): resolvable epic file → profile captures plan-time surface (not diff-only)" {
  export AID_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  _commit_scripts_core_diff
  local epic="$TEST_PROJECT_ROOT/.aid-o/tasks/E-test_1_1.md"
  _write_epic_file "$epic"

  run bash "$PREFILTER" profile "$epic" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  local plan_count
  plan_count="$(jq -r '.review_profile.plan_time_surfaces | length' "$TEST_EVIDENCE_DIR/review-profile.json")"
  [ "$plan_count" -ge 1 ]
  jq -e '.review_profile.plan_time_surfaces | index("scripts_core")' "$TEST_EVIDENCE_DIR/review-profile.json"
}

@test "AC2 (negative): unresolvable epic → SILENT profiler yields empty plan_time with NO reason (the anti-pattern)" {
  # Proves the danger the fail-loud path guards against: calling the profiler with
  # a path that doesn't exist silently emits plan_time_surfaces:[] with no marker.
  export AID_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  _commit_scripts_core_diff

  run bash "$PREFILTER" profile "$TEST_PROJECT_ROOT/.aid-o/tasks/DOES-NOT-EXIST.md" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  local plan_count; plan_count="$(jq -r '.review_profile.plan_time_surfaces | length' "$TEST_EVIDENCE_DIR/review-profile.json")"
  [ "$plan_count" -eq 0 ]
  # No explicit unresolved reason → this is exactly the "tichý pass" the pipeline
  # fail-loud producer must replace.
  run jq -e '.review_profile.plan_time_status' "$TEST_EVIDENCE_DIR/review-profile.json"
  [ "$status" -ne 0 ]
}

@test "AC2 (negative): fail-loud profile carries unresolved reason AND drives audit mode to c3 (fail-closed)" {
  # Emit the fail-loud profile per the pipeline.md producer contract (unresolvable
  # epic → risk_profile:unverifiable + explicit plan_time_status:unresolved), then
  # prove the mechanical consequence: aid-audit-mode.sh resolves it to c3, so an
  # unread EPIC forces the C3 audit instead of a silent legacy_health skip.
  jq -n --arg created_at "2026-06-18T00:00:00Z" '{
    schema_version: "aid-2.0", artifact_type: "review_profile",
    producer: "pipeline.md#review-profile-fail-loud", created_at: $created_at,
    control_protocol: "aid-2.0",
    provenance: {dispatch_mode: "deterministic", generated_by_tool: "pipeline.md#review-subphase"},
    review_profile: {
      matched_surfaces: [], plan_time_surfaces: [], candidate_time_surfaces: [],
      required_lenses: [], risk_profile: "unverifiable", plan_time_status: "unresolved",
      reason: "epic_task_file_not_found",
      ir_cadence: 3, c2_authorities_max: 3, llm_authorities_total_max: 5,
      profile_hash: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    }
  }' > "$TEST_EVIDENCE_DIR/review-profile.json"

  [ "$(jq -r '.review_profile.risk_profile' "$TEST_EVIDENCE_DIR/review-profile.json")" = "unverifiable" ]
  [ "$(jq -r '.review_profile.plan_time_status' "$TEST_EVIDENCE_DIR/review-profile.json")" = "unresolved" ]

  run bash "$AUDIT_MODE" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "c3" ]
}

@test "AC2 (contrast): a silent low-risk diff-only profile would skip C3 (legacy_health) — why fail-loud matters" {
  # A diff-only profile that resolved to low risk (because the high-risk EPIC file
  # was never read) resolves to legacy_health — C3 is skipped. This is the exact
  # false-negative the fail-loud producer prevents.
  echo '{"review_profile":{"risk_profile":"low"}}' > "$TEST_EVIDENCE_DIR/review-profile.json"
  run bash "$AUDIT_MODE" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "legacy_health" ]
}

@test "AC2: pipeline.md documents the fail-loud producer contract" {
  # The prose producer is the source of the fail-loud profile; lock its presence
  # so it can't be silently dropped.
  grep -q "review_profile_epic_unresolved" "$PIPELINE_MD"
  grep -q "plan_time_status" "$PIPELINE_MD"
}

# ─── Scenario (b): aid-audit-mode.sh three branches ─────────────────────────

@test "(b) aid-audit-mode.sh: high risk_profile → c3 (exit 0)" {
  echo '{"review_profile":{"risk_profile":"high"}}' > "$TEST_EVIDENCE_DIR/review-profile.json"
  run bash "$AUDIT_MODE" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "c3" ]
}

@test "(b) aid-audit-mode.sh: low risk_profile → legacy_health (exit 0)" {
  echo '{"review_profile":{"risk_profile":"low"}}' > "$TEST_EVIDENCE_DIR/review-profile.json"
  run bash "$AUDIT_MODE" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "legacy_health" ]
}

@test "(b) aid-audit-mode.sh: missing review-profile.json → c3 + exit 3 (fail-closed, distinguishable)" {
  # No review-profile.json in the evidence dir. stdout is the mode; the warning
  # goes to stderr (redirected to a file, checked separately) so callers can tell
  # this apart from a profile that genuinely resolved to c3.
  run bash -c "'$AUDIT_MODE' '$TEST_EVIDENCE_DIR' 2>'$TEST_TMPDIR/audit-mode-err.log'"
  [ "$status" -eq 3 ]
  [ "$output" = "c3" ]
  grep -q "review-profile.json not found" "$TEST_TMPDIR/audit-mode-err.log"
}

# ─── Finding 1a: Missing "high" case when policy file exists ────────────────

@test "(Finding 1a) aid-audit-mode.sh: policy file with only unverifiable + risk_profile=high → c3 (fail-closed)" {
  # E-059-1_2 Step 1: Partial policy that defines only risk_profiles.unverifiable
  # (missing risk_profiles.high) + input risk_profile="high" must resolve to c3,
  # not legacy_health (the bug: the elif arm was missing "high").
  local policy_file="$TEST_TMPDIR/partial-policy.yaml"
  cat > "$policy_file" <<'YAML'
version: 1
risk_profiles:
  unverifiable:
    c3_required: true
YAML
  export C3_AUDIT_POLICY="$policy_file"

  echo '{"review_profile":{"risk_profile":"high"}}' > "$TEST_EVIDENCE_DIR/review-profile.json"
  run bash "$AUDIT_MODE" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "c3" ]  # Must be c3, not legacy_health (fail-closed)
}

# ─── Finding 1b: Injection prevention + fail-closed on unknown values ────────

@test "(Finding 1b) aid-audit-mode.sh: malformed risk_profile (injection attempt) → c3 (fail-closed)" {
  # E-059-1_2 Step 1: Input with injection-like character (literal quote) must
  # be validated and fall back to "unverifiable", which resolves to c3.
  echo '{"review_profile":{"risk_profile":"high\" | echo injected"}}' > "$TEST_EVIDENCE_DIR/review-profile.json"
  run bash "$AUDIT_MODE" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "c3" ]  # Malformed → validated to "unverifiable" → c3
}

@test "(Finding 1b) aid-audit-mode.sh: unknown risk_profile value → c3 (fail-closed)" {
  # Input with unknown enum value (e.g., typo) must fall back to "unverifiable".
  echo '{"review_profile":{"risk_profile":"UNKNOWN_PROFILE"}}' > "$TEST_EVIDENCE_DIR/review-profile.json"
  run bash "$AUDIT_MODE" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "c3" ]  # Unknown → validated to "unverifiable" → c3
}

# ─── Scenario (c): FSM review-profile presence check (observe/blocking) ─────

@test "(c) FSM presence check OBSERVE: missing review-profile.json → done-advance PASSES + review_profile_would_block event" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  # No review-profile.json present; default enforcement is observe.

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "review_profile_would_block"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "release" ]
}

@test "(c) FSM presence check BLOCKING (C3_AUDIT_POLICY override): missing review-profile.json → done-advance REJECTED + fsm_done_advance_fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  _pin_c3_blocking

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_done_advance_fail"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "review" ]
}

# ─── Scenario (d): C3 gate enforcement toggle (observe/blocking) ────────────

# _seed_c3_gate_case — clean DONE/review state + high review-profile.json +
# a BLOCKING audit-report.json (blocking_findings:true) + matching
# curator-report.json, so the ONLY block reason is the C3 independent-audit hook.
_seed_c3_gate_case() {
  local state_file="$1"
  _seed_clean_done_review "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  cat > "$TEST_EVIDENCE_DIR/audit-report.json" <<JSON
{
  "audit_report": {"blocking_findings": true, "input_manifest_hash": "sha256:manifest-abc"},
  "status": "pass",
  "revision": {"head_sha": "${head_sha}"}
}
JSON
  # Curator content-ref must match sha256 of audit-report.json content so the
  # (separately-active, blocking) Curator sequencing guard passes and the C3 hook
  # is the sole variable under test.
  local actual_hash; actual_hash="$(sha256sum "$TEST_EVIDENCE_DIR/audit-report.json" | awk '{print $1}')"
  cat > "$TEST_EVIDENCE_DIR/curator-report.json" <<JSON
{"curator": {"audit_report_ref": "sha256:${actual_hash}"}}
JSON
}

@test "(d) C3 gate OBSERVE: blocking audit-report + high profile → done-advance PASSES + c3_gate_would_block event" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_c3_gate_case "$state_file"
  # Default enforcement observe (no C3_AUDIT_POLICY override).

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "c3_gate_would_block"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "release" ]
}

@test "(d) C3 gate BLOCKING (C3_AUDIT_POLICY override): blocking audit-report + high profile → done-advance REJECTED" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_c3_gate_case "$state_file"
  _pin_c3_blocking

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *"blocking_findings == true"* ]]
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "review" ]
}

# ─── Scenario (e): exit-22 (range_undetermined) → unverifiable, non-fatal ───

@test "(e) producer with no base_commit → exit 22 + unverifiable profile emitted (caller continues)" {
  export AID_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  # fsm-state.yaml WITHOUT base_commit → no diff range → range_undetermined.
  cat > "$TEST_EVIDENCE_DIR/fsm-state.yaml" <<YAML
epic_id: E-test
run_id: R-test
project_id: testproj
YAML
  local epic="$TEST_PROJECT_ROOT/.aid-o/tasks/E-test_1_1.md"
  _write_epic_file "$epic"

  run bash "$PREFILTER" profile "$epic" "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 22 ]
  [ -f "$TEST_EVIDENCE_DIR/review-profile.json" ]
  [ "$(jq -r '.review_profile.risk_profile' "$TEST_EVIDENCE_DIR/review-profile.json")" = "unverifiable" ]
}

# ─── Step 2 (E-059-1_2, IMP-177 invalidation half) ──────────────────────────
#
# HONEST FRAMING (do not overclaim coverage): the two AC1 scenarios below verify
# the SCRIPT (scripts/lib/aid-invalidation-map.sh) behaves correctly when handed
# the EXACT 3-arg CLI the pipeline.md "Invalidation-Map Post-Fix Hook" specifies
# — i.e. the flow-shaped args, materialized from a real git diff exactly as the
# hook does. The FSM scenarios verify aid-fsm.sh reacts to the gate_fixer_fix_applied
# substrate. What these CANNOT verify: that a live LLM controller actually FOLLOWS
# the pipeline.md prose at runtime (that it really runs the hook after each
# gate-fixer fix). That runtime adherence is an observe-telemetry concern
# (invalidation_map_expected_missing would_block fires when the wiring didn't run),
# NOT something a bats unit test can prove. This suite complements
# test-invalidation-map.bats (which drives the script with injected policy
# fixtures) by proving the pipeline-args contract against the REAL default policies.
# ($INVMAP / $STAGE_LOG are exported from setup() after AID_PLUGIN_PATH resolves.)

@test "(Step2-AC1) direct-CLI with flow-shaped args → invalidation-map.json + invalidation_map_produced event" {
  export AID_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  # Materialize changed-paths EXACTLY as the pipeline hook does: a real git diff
  # over a pre-fix..HEAD range.
  local pre_fix_ref; pre_fix_ref="$(git rev-parse HEAD)"
  mkdir -p plugins/aid-orchestrator/scripts/lib
  printf 'cmd_x() { :; }\n' > plugins/aid-orchestrator/scripts/lib/fixdemo.sh
  git add -A && git commit -q -m "gate-fixer fix"
  local changed="$TEST_TMPDIR/changed-paths.txt"
  git diff --name-only "${pre_fix_ref}..HEAD" > "$changed"

  # EXACTLY the 3-arg CLI the pipeline.md hook specifies.
  run bash "$INVMAP" --fix-ref "cp2-step-1-iter1" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$changed"
  [ "$status" -eq 0 ]
  [ -f "$TEST_EVIDENCE_DIR/invalidation-map.json" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "invalidation_map_produced"
  # fix_ref is echoed verbatim into the artifact (opaque label, stored as-is).
  [ "$(jq -r '.invalidation_map.applied_fix_ref' "$TEST_EVIDENCE_DIR/invalidation-map.json")" = "cp2-step-1-iter1" ]
}

@test "(Step2-AC1) missing --changed-paths → exit 1 (arg contract), no artifact written" {
  # The flow ALWAYS passes all three args; this proves the script's own contract
  # fails closed if a caller omits --changed-paths.
  run bash "$INVMAP" --fix-ref "cp2-step-1-iter1" --evidence-dir "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [ ! -f "$TEST_EVIDENCE_DIR/invalidation-map.json" ]
}

@test "(Step2) FSM invalidation_map_expected OBSERVE: gate_fixer_fix_applied present + no invalidation-map.json → done-advance PASSES + invalidation_map_expected_missing event" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  # Emit the substrate event the FSM check keys off (as the pipeline hook would),
  # but DO NOT produce invalidation-map.json — simulating the wiring not having run.
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp2-step-1-iter1"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "invalidation_map_expected_missing"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "release" ]
}

@test "(Step2) FSM invalidation_map_expected OBSERVE: gate_fixer_fix_applied present + invalidation_map_produced event → NO would_block" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp2-step-1-iter1"
  # The invalidation_map_produced event IS present → the expectation is satisfied, no would_block emitted.
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" invalidation_map_produced fix_ref="cp2-step-1-iter1" c1_count=0 c2_count=0 require_rerun=false

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  run assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "invalidation_map_expected_missing"
  [ "$status" -ne 0 ]   # event must NOT be present
}

@test "(Step2) FSM invalidation_map_expected OBSERVE: NO gate_fixer_fix_applied event → check is a no-op (no would_block even without artifact)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  # No gate_fixer_fix_applied event and no invalidation-map.json → no fix was applied,
  # so the check must NOT manufacture a would_block (fail-closed reads = no-op).
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  run assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "invalidation_map_expected_missing"
  [ "$status" -ne 0 ]
}

@test "(Step2) FSM invalidation_map_expected BLOCKING (INVALIDATION_MAP_ENFORCEMENT=blocking): gate_fixer_fix_applied + no artifact → done-advance REJECTED + fsm_done_advance_fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp2-step-1-iter1"
  export INVALIDATION_MAP_ENFORCEMENT=blocking

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_done_advance_fail"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "review" ]
}

# ─── Finding 2 (Regression): High-cardinality mismatch with real event shapes ──
# Regression for CP4 finding (attempt 1 bug): jq -R without -c pretty-prints,
# inflating wc -l count. This test uses 8 applied vs 6 produced to expose the bug:
# without -c, pretty-printing 8 events with 3+ fields each could inflate counts
# to 16+, failing to detect the real 8>6 mismatch. With -c (compact), counts
# resolve correctly to 8 and 6, and the mismatch is properly detected.

@test "(Finding 2 Regression) FSM invalidation_map_expected OBSERVE: 8 fixes applied vs 6 produced (high-cardinality, real event shapes) → would_block" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"

  # Emit 8 gate_fixer_fix_applied events with real multi-field structure
  for i in {1..8}; do
    bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" \
      gate_fixer_fix_applied fix_ref="cp2-step-${i}-iter1" \
      enforcement="observe" reason="gate_fixer_fix_applied_event_${i}"
  done

  # Emit 6 invalidation_map_produced events with real multi-field structure
  for i in {1..6}; do
    bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" \
      invalidation_map_produced fix_ref="cp2-step-${i}-iter1" \
      c1_count=$((i % 2)) c2_count=$((i % 3)) require_rerun=$([[ $((i % 2)) -eq 0 ]] && echo "true" || echo "false")
  done

  # Verify exact counts (8 and 6, not pretty-print inflated multiples like 16+ and 12+)
  local applied_count produced_count
  applied_count=$(jq -Rc 'fromjson? | select(.event=="gate_fixer_fix_applied")' "$TEST_EVIDENCE_DIR/timeline.jsonl" 2>/dev/null | wc -l)
  produced_count=$(jq -Rc 'fromjson? | select(.event=="invalidation_map_produced")' "$TEST_EVIDENCE_DIR/timeline.jsonl" 2>/dev/null | wc -l)
  [ "$applied_count" -eq 8 ]
  [ "$produced_count" -eq 6 ]

  # FSM check must detect the mismatch (8 > 6) in OBSERVE mode and emit would_block
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "invalidation_map_expected_missing"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "release" ]
}

@test "(Finding 2 Regression) FSM invalidation_map_expected BLOCKING: 8 fixes vs 6 produced (high-cardinality) → reject" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  export INVALIDATION_MAP_ENFORCEMENT=blocking

  # Emit 8 applied, 6 produced (high-cardinality mismatch)
  for i in {1..8}; do
    bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" \
      gate_fixer_fix_applied fix_ref="cp2-step-${i}-iter1" enforcement="observe"
  done
  for i in {1..6}; do
    bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" \
      invalidation_map_produced fix_ref="cp2-step-${i}-iter1" c1_count=0 c2_count=0 require_rerun=false
  done

  # With BLOCKING enforcement, the mismatch must reject the transition
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_done_advance_fail"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "review" ]
}

# ─── Finding 2: Event count mismatch detection (multiple fixes) ───────────────

@test "(Finding 2) FSM invalidation_map_expected OBSERVE: 2 fixes applied, only 1 invalidation-map event → would_block" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  # Simulate 2 gate-fixer fixes applied (CP2 + CP3) but only 1 invalidation_map_produced
  # event was emitted (CP2 ran, CP3's hook skipped). The check must detect this count
  # mismatch and emit invalidation_map_expected_missing (Finding 2 fix).
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp2-step-1-iter1"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp3-step-1-iter1"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" invalidation_map_produced fix_ref="cp2-step-1-iter1" c1_count=1 c2_count=0 require_rerun=true
  # Only 1 invalidation_map_produced vs 2 gate_fixer_fix_applied.

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "invalidation_map_expected_missing"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "release" ]
}

@test "(Finding 2) FSM invalidation_map_expected OBSERVE: equal counts (2 fixes, 2 events) → no would_block" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  # Now both fixes have corresponding invalidation_map_produced events.
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp2-step-1-iter1"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp3-step-1-iter1"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" invalidation_map_produced fix_ref="cp2-step-1-iter1" c1_count=1 c2_count=0 require_rerun=true
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" invalidation_map_produced fix_ref="cp3-step-1-iter1" c1_count=0 c2_count=1 require_rerun=true
  # Counts match: 2 fixes, 2 events.

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  run assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "invalidation_map_expected_missing"
  [ "$status" -ne 0 ]   # event must NOT be present (counts match, no would_block)
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "release" ]
}

@test "(Finding 2) FSM invalidation_map_expected BLOCKING: count mismatch → done-advance REJECTED + fsm_done_advance_fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_clean_done_review "$state_file"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp2-step-1-iter1"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" gate_fixer_fix_applied fix_ref="cp3-step-1-iter1"
  bash "$STAGE_LOG" log_event "$TEST_EVIDENCE_DIR/timeline.jsonl" invalidation_map_produced fix_ref="cp2-step-1-iter1" c1_count=1 c2_count=0 require_rerun=true
  # 2 fixes applied, only 1 event produced; enforcement=blocking.
  export INVALIDATION_MAP_ENFORCEMENT=blocking

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_done_advance_fail"
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "review" ]
}

# ─── P065 Step 8/15: Policy — executor-first, level accounting, degraded_advisory ──
#
# These assert the DEFAULT policy the bridge/FSM/build-manifest/pipeline.md read
# (defaults/policies/c3-audit-policy.yaml). The c3_executor block records the Codex
# executor, the executor-first probe (always cross_provider), the satisfies-rule
# (a real cross_provider pass is a superset of the weaker levels). Step 8 shipped
# c3_on_unavailable: unverifiable (degraded_advisory deferred until the c3_advisory
# auditor capability existed); Step 15 (P065's FINAL action) flips it to
# degraded_advisory now that agents/auditor.md's c3_advisory mode + the pipeline
# dispatch + the FSM c3_advisory_not_independent hook all exist.
# enforcement stays observe and risk_profiles.* are unchanged (superset).

# _default_c3_policy — path to the real shipped default policy (not a test override).
_default_c3_policy() {
  echo "$AID_PLUGIN_PATH/defaults/policies/c3-audit-policy.yaml"
}

@test "(Step8-AC1) default policy: c3_executor.probe_as = cross_provider AND .kind = codex_cli" {
  local pol; pol="$(_default_c3_policy)"
  [ -f "$pol" ]
  [ "$(yq -r '.c3_executor.probe_as' "$pol")" = "cross_provider" ]
  [ "$(yq -r '.c3_executor.kind' "$pol")" = "codex_cli" ]
  # dispatch_script points at the E-065-1/2 dispatch entrypoint.
  [ "$(yq -r '.c3_executor.dispatch_script' "$pol")" = "scripts/lib/aid-c3-dispatch.sh" ]
}

@test "(Step15-AC1) default policy: c3_on_unavailable = degraded_advisory (FINAL P065 flip) AND enforcement = observe" {
  local pol; pol="$(_default_c3_policy)"
  # SHIPPED value as of Step 15 — the c3_advisory fallback capability now exists.
  [ "$(yq -r '.c3_executor.c3_on_unavailable' "$pol")" = "degraded_advisory" ]
  [ "$(yq -r '.c3_executor.c3_on_unavailable' "$pol")" != "unverifiable" ]
  # enforcement stays observe (this step does not touch it).
  [ "$(yq -r '.enforcement' "$pol")" = "observe" ]
}

@test "(Step8-AC3) default policy: c3_executor.satisfies_levels includes cross_model AND cross_provider (executor-first superset)" {
  local pol; pol="$(_default_c3_policy)"
  # A live cross_provider Codex pass satisfies the weaker required levels too.
  [ "$(yq -r '.c3_executor.satisfies_levels | contains(["cross_model"])' "$pol")" = "true" ]
  [ "$(yq -r '.c3_executor.satisfies_levels | contains(["cross_provider"])' "$pol")" = "true" ]
  # context_only is the weakest floor and is also covered by the superset.
  [ "$(yq -r '.c3_executor.satisfies_levels | contains(["context_only"])' "$pol")" = "true" ]
}

@test "(Step8-superset) default policy: risk_profiles.* required_independence_level UNCHANGED (high=cross_model, unverifiable=cross_provider)" {
  # Forbidden-zone guard: Step 8 must not alter per-profile independence levels.
  local pol; pol="$(_default_c3_policy)"
  [ "$(yq -r '.risk_profiles.high.required_independence_level' "$pol")" = "cross_model" ]
  [ "$(yq -r '.risk_profiles.unverifiable.required_independence_level' "$pol")" = "cross_provider" ]
  [ "$(yq -r '.risk_profiles.high.c3_required' "$pol")" = "true" ]
  [ "$(yq -r '.risk_profiles.unverifiable.c3_required' "$pol")" = "true" ]
}
