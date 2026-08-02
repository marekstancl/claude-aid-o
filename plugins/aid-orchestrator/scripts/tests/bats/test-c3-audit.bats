#!/usr/bin/env bats
# E-057-2_2 Step 3 — EPIC-level red-green integration suite for the C3
# independent-audit pipeline. Exercises 4 scenarios from the plan, each with
# a positive (blocks) and negative (passes) control, via REAL subprocess
# dispatch to aid-fsm.sh (and aid-audit-independence.sh for scenario 2) —
# "reálný exit code, ne grep" (real exit code, not grep).
#
# The enforcement under test spans two EPICs already merged onto this branch:
#   - EPIC 1 (E-057-1_2) Step 4/5: the C3 done-advance hook in aid-fsm.sh
#     (risk-gated on review-profile.json; reads audit-report.json's
#     .audit_report.blocking_findings / .status / .audit_report.input_manifest_hash /
#     .revision.head_sha — see aid-fsm.sh around the "E-057-1_2 Step 4" comment).
#   - This EPIC (E-057-2_2) Step 1: the Curator content-ref sequencing guard
#     (curator-report.json's .curator.audit_report_ref must equal
#     `sha256:<sha256sum of audit-report.json content>` — see aid-fsm.sh around
#     the "E-057-2_2 Step 1" comment).
#
# Scenarios:
#   1. High→blocking            — .audit_report.blocking_findings == true blocks.
#   2. unavailable→unverifiable — codex absent + cross_provider required →
#      aid-audit-independence.sh reports unverifiable/exit 2, AND a
#      .status == "unverifiable" audit-report.json blocks done-advance.
#   3. no-provenance→fail       — missing .audit_report.input_manifest_hash blocks.
#   4. curator-before-audit→fail — curator-report.json's .curator.audit_report_ref
#      not matching sha256(audit-report.json content) blocks (E-057-2_2 Step 1).
#
# Fixture/harness conventions below are copied from test-aid-fsm.bats's
# "E-057-1_2 C3 hook: ..." tests (_seed_done_review_state pattern, AID_PLUGIN_PATH
# export, GIT_AUTHOR_DATE amend-HEAD idiom) so this suite matches established
# style rather than inventing a new one.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  INDEP="$AID_PLUGIN_PATH/scripts/lib/aid-audit-independence.sh"
  export INDEP
}

teardown() {
  unset GIT_DIR
  unset C3_AUDIT_POLICY
  teardown_test_evidence_dir
}

# _pin_c3_blocking
#   E-059-1_2 Step 1: the C3 independent-audit hook is now enforcement-gated —
#   c3-audit-policy.yaml ships `enforcement: observe` (staged wake), so the hook
#   emits c3_gate_would_block telemetry and lets the transition through instead
#   of blocking. Scenarios that assert the "C3 independent audit block" message
#   must pin the enforcement toggle to `blocking` via the C3_AUDIT_POLICY seam
#   (mirrors DELIVERY_GATE_POLICY in test-fsm-dg07-observe.bats). The per-profile
#   c3_required risk-gate still reads the installed default policy, so this
#   fixture only needs the enforcement key.
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

# ─── Shared fixture helper (copied/adapted from test-aid-fsm.bats) ──────────

# _seed_done_review_state <state_file>
#   Minimal DONE/review fsm-state.yaml + the supporting evidence/config files
#   that done-advance review→release always requires (gates_report.json,
#   audit-log.jsonl, plugin.yaml, pm_decision: merge). Does NOT create
#   curator-report.* / audit-report.* / review-profile.json — callers add
#   those to control exactly which precondition is under test.
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

# _write_clean_audit_json <path> <head_sha> [status] [blocking]
#   A fully-clean audit-report.json: blocking_findings=false, status=<status>
#   (default "pass"), a present input_manifest_hash, and revision.head_sha set
#   to the CURRENT HEAD so the freshness check also passes. Callers override
#   one field at a time to isolate a single failure mode per scenario.
_write_clean_audit_json() {
  local path="$1" head_sha="$2" status="${3:-pass}" blocking="${4:-false}"
  cat > "$path" <<JSON
{
  "audit_report": {
    "blocking_findings": ${blocking},
    "input_manifest_hash": "sha256:manifest-abc123"
  },
  "status": "${status}",
  "revision": {
    "head_sha": "${head_sha}"
  }
}
JSON
}

# ─── Scenario 1: High→blocking (blocking_findings == true) ──────────────────

@test "C3 EPIC scenario 1 (positive): blocking_findings == true → done-advance blocks" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  # curator-report.md/audit-report.md legacy-existence files (required
  # regardless of the JSON-path C3 hook). No curator-report.json here, so
  # the E-057-2_2 Step 1 sequencing guard stays a no-op for this scenario.
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"

  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "true"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *"blocking_findings == true"* ]]
}

@test "C3 EPIC scenario 1 (negative control): blocking_findings == false (medium-only) → passes" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"

  # Isolate: ONLY blocking_findings flips relative to the positive test above —
  # everything else (status, manifest hash, head_sha) stays clean.
  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "false"

  # E-057-2_2 Step 1: on high-risk profile, Curator is required to dual-emit
  # curator-report.json with a matching content-ref. Provide it to isolate the
  # C3 blocking_findings check.
  local actual_hash
  actual_hash="$(sha256sum "$TEST_EVIDENCE_DIR/audit-report.json" | awk '{print $1}')"
  cat > "$TEST_EVIDENCE_DIR/curator-report.json" <<JSON
{"curator": {"audit_report_ref": "sha256:${actual_hash}"}}
JSON

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 independent audit block"* ]]
}

# ─── Scenario 2: unavailable→unverifiable (spans aid-audit-independence.sh +
#     aid-fsm.sh downstream consumption) ──────────────────────────────────────

@test "C3 EPIC scenario 2 (positive, detection): codex absent + cross_provider required → unverifiable/exit 2" {
  # Real subprocess call, PATH scoped to exclude wherever codex lives on this
  # dev box (it is normally present) so detection genuinely fails check 1/4 —
  # not mocked, a real "binary not found" outcome.
  PATH="/usr/bin:/bin:/home/marekstancl/.local/bin" run "$INDEP" detect --required cross_provider
  [ "$status" -eq 2 ]
  [[ "$output" == *"unverifiable"* ]]
  [[ "$output" == *"codex binary not found in PATH"* ]]
}

@test "C3 EPIC scenario 2 (positive, FSM consequence): status == unverifiable → done-advance blocks" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # risk_profile "unverifiable" maps to required_independence_level: cross_provider
  # in c3-audit-policy.yaml — the scenario this profile models is exactly the
  # codex-absent detection outcome from the sibling test above.
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "unverifiable"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"

  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "unverifiable" "false"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *'status == "unverifiable"'* ]]
}

@test "C3 EPIC scenario 2 (negative control, detection): context_only required → available/exit 0" {
  PATH="/usr/bin:/bin:/home/marekstancl/.local/bin" run "$INDEP" detect --required context_only
  [ "$status" -eq 0 ]
  [[ "$output" == *"status=available"* ]]
  [[ "$output" == *"level=context_only"* ]]
}

@test "C3 EPIC scenario 2 (negative control, FSM consequence): clean status → passes" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"

  # Isolate: ONLY status flips relative to the positive FSM test above — clean
  # "pass" status (correspondingly achievable/confirmed independence level).
  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "false"

  # E-057-2_2 Step 1: on high-risk profile, provide curator-report.json with
  # matching content-ref to isolate the C3 status check.
  local actual_hash
  actual_hash="$(sha256sum "$TEST_EVIDENCE_DIR/audit-report.json" | awk '{print $1}')"
  cat > "$TEST_EVIDENCE_DIR/curator-report.json" <<JSON
{"curator": {"audit_report_ref": "sha256:${actual_hash}"}}
JSON

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 independent audit block"* ]]
}

# ─── Scenario 3: no-provenance→fail (missing input_manifest_hash) ───────────

@test "C3 EPIC scenario 3 (positive): missing input_manifest_hash → done-advance blocks" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"

  # Hand-built (not via the clean helper) so .audit_report.input_manifest_hash
  # is genuinely absent — the ONLY deviation from a clean report.
  cat > "$TEST_EVIDENCE_DIR/audit-report.json" <<JSON
{
  "audit_report": {
    "blocking_findings": false
  },
  "status": "pass",
  "revision": {
    "head_sha": "${head_sha}"
  }
}
JSON

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *"missing .audit_report.input_manifest_hash"* ]]
}

@test "C3 EPIC scenario 3 (negative control): present + valid input_manifest_hash → passes" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"

  # Isolate: ONLY input_manifest_hash flips (present now) relative to the
  # positive test above — everything else stays identical.
  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "false"

  # E-057-2_2 Step 1: on high-risk profile, provide curator-report.json with
  # matching content-ref to isolate the C3 manifest_hash check.
  local actual_hash
  actual_hash="$(sha256sum "$TEST_EVIDENCE_DIR/audit-report.json" | awk '{print $1}')"
  cat > "$TEST_EVIDENCE_DIR/curator-report.json" <<JSON
{"curator": {"audit_report_ref": "sha256:${actual_hash}"}}
JSON

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 independent audit block"* ]]
}

# ─── Scenario 4: curator-before-audit→fail (E-057-2_2 Step 1 content-ref) ───

@test "C3 EPIC scenario 4 (positive): audit_report_ref mismatched sha256 → done-advance blocks" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # No review-profile.json: the C3 risk-profile hook (scenarios 1–3) stays a
  # no-op here so this test isolates the E-057-2_2 Step 1 sequencing guard.
  # Legacy audit-report.md is clean so the fallback blocking_findings check
  # (which DOES run, since the JSON-path hook never fires without a
  # review-profile.json) doesn't itself cause the failure.
  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "false"

  # Deliberately WRONG ref — does not match sha256sum of the actual
  # audit-report.json content written above (proves Curator did not
  # genuinely consume that exact audit output).
  cat > "$TEST_EVIDENCE_DIR/curator-report.json" <<'JSON'
{"curator": {"audit_report_ref": "sha256:0000000000000000000000000000000000000000000000000000000000000000"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match sha256 of audit-report.json content"* ]]
  [[ "$output" == *"sequencing violation"* ]]
}

@test "C3 EPIC scenario 4 (negative control): audit_report_ref matches sha256 → passes" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "false"

  # Isolate: ONLY the ref value flips (now the REAL sha256 of the audit-report.json
  # content just written) relative to the positive test above.
  local actual_hash
  actual_hash="$(sha256sum "$TEST_EVIDENCE_DIR/audit-report.json" | awk '{print $1}')"
  cat > "$TEST_EVIDENCE_DIR/curator-report.json" <<JSON
{"curator": {"audit_report_ref": "sha256:${actual_hash}"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"sequencing violation"* ]]
}

# ─── Scenario 4b: curator-report.json missing on C3-required run → block (risk-gated) ─

@test "C3 EPIC scenario 4b (positive): curator-report.json absent on high-risk profile → done-advance blocks" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # High risk profile REQUIRES C3 and curator dual-emit. Absence of the entire
  # curator-report.json file is a hard block (fail-closed) on C3-required runs.
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "false"

  # Deliberately OMIT curator-report.json entirely (not even the .md file). The
  # existing .md/.yaml check (lines 2622–2626 in aid-fsm.sh) will catch this too,
  # but we're specifically testing the E-057-2_2 Step 1 fail-closed behavior for
  # the JSON file when C3 is required.
  # Touch only the legacy .md file to bypass the basic existence check, isolating
  # the JSON-level failure.
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"curator-report.json not found"* ]]
  [[ "$output" == *"risk profile 'high' requires C3 audit and dual-emitted curator report"* ]]
}

@test "C3 EPIC scenario 4b (fix verification): medium profile + valid audit-report.json + missing curator-report.json → blocks (secondary trigger fires)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # E-057-2_2 Step 1 fix verification: medium risk profile (primary trigger doesn't fire)
  # BUT a valid clean audit-report.json EXISTS (secondary trigger WILL fire after the fix).
  # The secondary trigger fires BEFORE the Curator guard, making c3_hook_fired="true",
  # which means curator-report.json is now REQUIRED and its absence blocks.
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "medium"}}
JSON
  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "false"

  # Omit curator-report.json and curator-report.md. We touch only the legacy .md file
  # to isolate the JSON-level behavior, but the fix now makes curator-report.json
  # required because the secondary trigger fires.
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  # After E-057-2_2 Step 1 fix: secondary trigger fires (valid audit-report.json present),
  # so curator-report.json absence MUST block (fail-closed).
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"curator-report.json not found"* ]]
}

@test "C3 EPIC scenario 4c (negative control): medium profile + NO audit-report.json + missing curator-report.json → passes (no-op)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # Genuinely-clean no-op: medium risk profile + review-profile.json exists BUT
  # no audit-report.json at all (C3 stage never ran). Secondary trigger doesn't fire.
  # Curator-report.json absence is a silent no-op.
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "medium"}}
JSON
  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  # DO NOT create audit-report.json — this is the true "C3 never ran" case.

  # Curator files: touch only legacy .md to pass basic existence check.
  # curator-report.json is absent, but secondary trigger never fires (no audit-report.json),
  # so this is a silent no-op.
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  # Should pass: no C3 report, so no requirement for curator JSON file.
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"curator-report.json not found"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# P065 Step 9 (E-065-3_7) — FSM done-advance C3 DISPATCH-PROVENANCE enforcement
#
# The C3 hook now runs a SECOND, strictly-additive gate (aid-fsm.sh, search:
# "C3 dispatch-provenance enforcement hook"): on a C3-required run it checks, in
# order, (1) c3/c3-dispatch.json present, (2) the dispatch genuinely succeeded
# cross_provider, (3) audit_report.process_id == dispatch codex_session_id,
# (4) audit_report.reviewed_head == current HEAD, and (5) — THE enforcement fix —
# shells out to `aid-c3-dispatch.sh verify`, treating any non-zero exit (the
# report↔raw faithful-transform binding broken) as a block reason. Enforcement is
# gated exactly like the independent-audit hook: blocking → PRECONDITION FAIL /
# errors++; observe (shipped default) → c3_dispatch_would_block telemetry only.
#
# These tests are additive; they do not touch the 13 scenarios above.
# ═══════════════════════════════════════════════════════════════════════════

# _write_clean_audit_json_prov <path> <head> <session> [reviewed_head]
#   A clean audit-report.json (blocking_findings=false, status=pass, present
#   input_manifest_hash, revision.head_sha=<head> so the EXISTING independent-audit
#   hook passes) PLUS the two provenance fields the dispatch hook reads:
#   .audit_report.process_id=<session> and .audit_report.reviewed_head
#   (default <head>). Callers deviate exactly one field per scenario so the ONLY
#   failing check is the one under test.
_write_clean_audit_json_prov() {
  local path="$1" head="$2" session="$3" reviewed_head="${4:-$2}"
  cat > "$path" <<JSON
{
  "audit_report": {
    "blocking_findings": false,
    "input_manifest_hash": "sha256:manifest-abc123",
    "process_id": "${session}",
    "reviewed_head": "${reviewed_head}"
  },
  "status": "pass",
  "revision": {
    "head_sha": "${head}"
  }
}
JSON
}

# _write_dispatch_json_min <path> <session> [invoked] [exit_code] [outcome] [events_valid]
#   Hand-built c3/c3-dispatch.json carrying only the .dispatch fields the hook's
#   checks 1–2 read. Defaults describe a genuine successful run; callers flip one
#   field to drive check 2. invoked/events_valid are JSON booleans, exit_code a
#   JSON number (written raw, not quoted).
_write_dispatch_json_min() {
  local path="$1" session="$2"
  local invoked="${3:-true}" exit_code="${4:-0}" outcome="${5:-dispatched}" events_valid="${6:-true}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{
  "dispatch": {
    "invoked": ${invoked},
    "exit_code": ${exit_code},
    "outcome": "${outcome}",
    "events_valid": ${events_valid},
    "codex_session_id": "${session}"
  }
}
JSON
}

# _write_matching_curator_ref <audit_json>
#   On a high-risk (C3-required) run the Curator content-ref guard REQUIRES a
#   curator-report.json whose .curator.audit_report_ref == sha256(audit content).
#   Provide it (recomputed for the exact audit-report.json bytes) so the ONLY
#   block in these tests is the dispatch-provenance one under test — never the
#   sequencing guard. Also drops the legacy curator-report.md existence file.
_write_matching_curator_ref() {
  local audit_json="$1"
  local h; h="$(sha256sum "$audit_json" | awk '{print $1}')"
  cat > "$TEST_EVIDENCE_DIR/curator-report.json" <<JSON
{"curator": {"audit_report_ref": "sha256:${h}"}}
JSON
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"
}

# _seed_high_c3_common <state_file>  — the shared review→release scaffold for a
# high-risk C3-required run: DONE/review state, review-profile.json high, and the
# legacy audit-report.md existence file. Callers add audit-report.json (+ its
# curator ref) and the c3-dispatch.json under test.
_seed_high_c3_common() {
  local state_file="$1"
  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"
}

# _reset_review_state <state_file>  — restore done_phase=review so the same
# evidence dir can be re-run through done-advance a second time (a successful
# advance mutates done_phase review→release, which would otherwise fail the phase
# precondition on a second call). Used by the both-modes genuine test.
_reset_review_state() {
  cat > "$1" <<YAML
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
}

# _imp269_two_commit_repo — (IMP-269) seed a real 2-commit repo + project.yaml
# and an independence spy that reports available, exporting BASE_SHA / HEAD_SHA.
# Shared by the IMP-269 build-manifest tests below (ac_source classification +
# targeted-run receipt sealing) so each test asserts only its own behaviour.
_imp269_two_commit_repo() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'project_id: test-c3-proj\n' > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml"
  mkdir -p "$TEST_PROJECT_ROOT/src"
  printf 'export const a = 1;\n' > "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts .aid-o/config/project.yaml
  git -C "$TEST_PROJECT_ROOT" commit -q -m base
  BASE_SHA="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  printf 'export const b = 2;\n' >> "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts
  git -C "$TEST_PROJECT_ROOT" commit -q -m head
  HEAD_SHA="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  export BASE_SHA HEAD_SHA
  printf 'src/app.ts\n' > "$TEST_TMPDIR/changed-paths.txt"
  export AID_CHANGED_PATHS="$TEST_TMPDIR/changed-paths.txt"
  mkdir -p "$TEST_TMPDIR/indep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/indep/detect"
  chmod +x "$TEST_TMPDIR/indep/detect"
  export AID_C3_INDEPENDENCE_BIN="$TEST_TMPDIR/indep/detect"
}

# _imp269_write_review_profile <required_lenses_json>  — write a schema-valid
# review-profile.json into TEST_EVIDENCE_DIR with the given required_lenses[].
_imp269_write_review_profile() {
  local lenses="$1"
  jq -n --arg h "$HEAD_SHA" --argjson lenses "$lenses" '{
    schema_version:"aid-2.0", artifact_type:"review_profile", producer:"test",
    created_at:"2026-07-23T00:00:00Z", control_protocol:"aid-2.0",
    identity:{project_id:"test-c3-proj"},
    subject:{subject_hash:"sha256:1111111111111111111111111111111111111111111111111111111111111111"},
    revision:{head_sha:$h, head_is_current:true, freshness:"current"},
    status:"pass", verdict:{kind:"none", ready:false},
    provenance:{dispatch_mode:"deterministic", generated_by_tool:"test"},
    review_profile:{matched_surfaces:["s"], plan_time_surfaces:["s"],
      candidate_time_surfaces:["s"], required_lenses:$lenses, risk_profile:"high",
      ir_cadence:3, c2_authorities_max:3, llm_authorities_total_max:5,
      profile_hash:"sha256:0000000000000000000000000000000000000000000000000000000000000000"}
  }' > "$TEST_EVIDENCE_DIR/review-profile.json"
}

# _imp269_write_plan_diff [verdict]  — a plan-diff.json bound to BASE_SHA..
# HEAD_SHA (IMP-464/D2: required whenever an AC lens is armed).
_imp269_write_plan_diff() {
  local verdict="${1:-pass}"
  jq -n --arg b "$BASE_SHA" --arg h "$HEAD_SHA" --arg v "$verdict" \
    '{base_commit:$b, head_commit:$h, overall_verdict:$v, results:[], summary:{present_count:0,absent_count:0}}' \
    > "$TEST_EVIDENCE_DIR/plan-diff.json"
}

# _imp269_write_receipt <path> <head_before> <head_after>  — write a well-formed
# targeted-run receipt whose head fields are the given SHAs. Writes a REAL run
# log next to the receipt and records its true sha256, so the receipt genuinely
# proves the run (PM review 2026-07-24 log-binding).
_imp269_write_receipt() {
  local dir; dir="$(dirname "$1")"
  local log="$dir/$(basename "$1" .receipt.json).log"
  printf 'TAP version 13\n1..241\nok 241 done\n' > "$log"
  local logsha; logsha="$(sha256sum "$log" | awk '{print $1}')"
  local cmd="bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local cmdsha; cmdsha="$(printf '%s' "$cmd" | sha256sum | awk '{print $1}')"
  jq -n --arg hb "$2" --arg ha "$3" --arg c "$cmd" --arg cs "$cmdsha" \
    --arg lg "$(basename "$log")" --arg ls "$logsha" '{
    purpose:"PM-authorized targeted run",
    command:$c, command_sha256:$cs,
    head_sha_before:$hb, head_sha_after:$ha, exit_code:0, plan_line:"1..241",
    passed:241, failed:0, skipped:2,
    log:$lg, log_sha256:$ls
  }' > "$1"
}

# ─── IMP-269 Half 1: ac_source classification + fail-closed AC-lens gate ─────

@test "IMP-269: AID_PLAN_AC_FILE set → ac_source=plan; bundle authored from the plan" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# Impl summary (untrusted AC source)\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '# Plan\n\n## Acceptance Criteria\nAC1..AC5 real.\n' > "$TEST_PROJECT_ROOT/.aid-o/plans/plan.md"
  export AID_PLAN_AC_FILE="$TEST_PROJECT_ROOT/.aid-o/plans/plan.md"
  _imp269_write_review_profile '["ac_to_test_identity","requirement_test_drift"]'
  _imp269_write_plan_diff pass

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "plan" ]
  # bundle must come from the plan, NOT the implementation's final_report.md.
  run bash -c "diff -q '$TEST_EVIDENCE_DIR/final_report.md' '$TEST_EVIDENCE_DIR/c3/bundle-plan-ac.md'"
  [ "$status" -ne 0 ]
}

@test "IMP-269: AC lens required + AID_PLAN_AC_FILE unset → build-manifest FAILS CLOSED (no manifest)" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# Impl summary (would silently become the AC source)\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  _imp269_write_review_profile '["ac_to_test_identity"]'
  unset AID_PLAN_AC_FILE

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -ne 0 ]
  [[ "$output" == *"AC lens required"* ]]
  [[ "$output" == *"implementation-authored bundle"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json" ]
}

@test "IMP-269: no AC lens required + fallback → warns, proceeds, records ac_source=final_report_fallback" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# Impl summary\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  _imp269_write_review_profile '["behavior_trace","negative_case"]'
  unset AID_PLAN_AC_FILE

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "final_report_fallback" ]
}

@test "IMP-269: neither AC file nor final_report.md + no AC lens → ac_source=stub" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  # no final_report.md, no review-profile.json, no AID_PLAN_AC_FILE.
  unset AID_PLAN_AC_FILE
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "stub" ]
}

@test "IMP-269: ac_source classification is preserved through to audit-report.json" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# Impl summary\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  _imp269_write_review_profile '["behavior_trace"]'
  unset AID_PLAN_AC_FILE

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  local brief_hash
  brief_hash="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"

  mkdir -p "$TEST_TMPDIR/codex-clean"
  cat > "$TEST_TMPDIR/codex-clean/codex" <<'CODEXEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "fake-clean-codex 0.0.0"; exit 0; fi
last=""
while [[ $# -gt 0 ]]; do case "$1" in --output-last-message|-o) last="$2"; shift 2 ;; *) shift ;; esac; done
report="$(jq -nc --arg h "$FAKE_HEAD" --arg bh "$FAKE_BRIEF_HASH" \
  '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:false,
    findings:[{severity:"medium",area:"maintainability",finding:"naming",recommendation:"rename later"}]}')"
jq -nc '{type:"thread.started",thread_id:"019f0000-0000-7000-8000-0000000ced09"}'
printf '%s\n' '{"type":"turn.started"}'
jq -nc --arg t "$report" '{type:"item.completed",item:{id:"item_final",type:"agent_message",text:$t}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'
[[ -n "$last" ]] && printf '%s\n' "$report" > "$last"
exit 0
CODEXEOF
  chmod +x "$TEST_TMPDIR/codex-clean/codex"
  export FAKE_HEAD="$HEAD_SHA" FAKE_BRIEF_HASH="$brief_hash"
  PATH="$TEST_TMPDIR/codex-clean:$PATH"

  run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.audit_report.ac_source' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "final_report_fallback" ]
}

# ─── IMP-269 Half 2: hash-bound targeted-run receipt channel ────────────────

@test "IMP-269: valid receipt at reviewed HEAD → sealed into evidence_hashes[] + allowlist[]" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  _imp269_write_receipt "$TEST_EVIDENCE_DIR/gates/boundary-suite.receipt.json" "$HEAD_SHA" "$HEAD_SHA"
  export AID_TEST_RECEIPT_FILE="$TEST_EVIDENCE_DIR/gates/boundary-suite.receipt.json"

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  # in allowlist[]
  run bash -c "jq -r '.audit_input_manifest.allowlist[]' '$TEST_EVIDENCE_DIR/audit-input-manifest.json' | grep -Fx 'gates/boundary-suite.receipt.json'"
  [ "$status" -eq 0 ]
  # sealed digest in evidence_hashes[]
  run jq -r '[.audit_input_manifest.evidence_hashes[] | select(.path=="gates/boundary-suite.receipt.json")] | length' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "1" ]
  run jq -r '.audit_input_manifest.evidence_hashes[] | select(.path=="gates/boundary-suite.receipt.json") | .sha256' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
}

@test "IMP-269: wrong-HEAD receipt → rejected at build time, NOT sealed (no manifest)" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  _imp269_write_receipt "$TEST_EVIDENCE_DIR/gates/stale.receipt.json" \
    "0000000000000000000000000000000000000000" "0000000000000000000000000000000000000000"
  export AID_TEST_RECEIPT_FILE="$TEST_EVIDENCE_DIR/gates/stale.receipt.json"

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid HEAD-bound targeted-run receipt"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json" ]
}

@test "IMP-269: malformed receipt (missing log_sha256) → rejected at build time" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  jq -n --arg h "$HEAD_SHA" '{command:"bats x", command_sha256:"8453bad3e8c6502dace501a594b36b8c583c82c2623d805450e1cb66559ac36b", head_sha:$h, exit_code:0, passed:1, failed:0}' \
    > "$TEST_EVIDENCE_DIR/gates/bad.receipt.json"
  export AID_TEST_RECEIPT_FILE="$TEST_EVIDENCE_DIR/gates/bad.receipt.json"

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -ne 0 ]
  [[ "$output" == *"targeted-run receipt"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json" ]
}

@test "IMP-269: single-field head_sha receipt shape is accepted (docs shape)" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  local cmd="bats x"
  local csha; csha="$(printf '%s' "$cmd" | sha256sum | awk '{print $1}')"
  printf 'ok 1\n1..1\n' > "$TEST_EVIDENCE_DIR/gates/single.log"
  local lsha; lsha="$(sha256sum "$TEST_EVIDENCE_DIR/gates/single.log" | awk '{print $1}')"
  jq -n --arg h "$HEAD_SHA" --arg c "$cmd" --arg cs "$csha" --arg ls "$lsha" \
    '{command:$c, command_sha256:$cs, head_sha:$h, exit_code:0, passed:1, failed:0, log:"single.log", log_sha256:$ls}' \
    > "$TEST_EVIDENCE_DIR/gates/single.receipt.json"
  export AID_TEST_RECEIPT_FILE="$TEST_EVIDENCE_DIR/gates/single.receipt.json"

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '[.audit_input_manifest.evidence_hashes[] | select(.path=="gates/single.receipt.json")] | length' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "1" ]
}

@test "IMP-269 F1: AID_PLAN_AC_FILE pointed AT final_report.md is NOT laundered into ac_source=plan" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# Impl summary of itself\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  # AC lens NOT required, so the run proceeds — the point is the CLASSIFICATION:
  # pointing the AC file at final_report.md must record final_report_fallback,
  # never plan, so the fail-closed gate cannot be bypassed one path over.
  _imp269_write_review_profile '["behavior_trace"]'
  export AID_PLAN_AC_FILE="$TEST_EVIDENCE_DIR/final_report.md"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "final_report_fallback" ]
  unset AID_PLAN_AC_FILE

  # And the byte-identical copy at a different path is likewise not `plan`.
  cp "$TEST_EVIDENCE_DIR/final_report.md" "$TEST_PROJECT_ROOT/ac-copy.md"
  export AID_PLAN_AC_FILE="$TEST_PROJECT_ROOT/ac-copy.md"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "final_report_fallback" ]
  unset AID_PLAN_AC_FILE
}

@test "IMP-269 F1: a genuinely distinct AID_PLAN_AC_FILE still records ac_source=plan" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# Impl summary of itself\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  # Canonical plan location (PM review 2026-07-24): a distinct plan under
  # .aid-o/plans still earns ac_source=plan.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '# The REAL plan\n\n## Acceptance Criteria\n- [ ] does X\n' > "$TEST_PROJECT_ROOT/.aid-o/plans/real-plan.md"
  _imp269_write_review_profile '["ac_to_test_identity"]'
  _imp269_write_plan_diff pass
  export AID_PLAN_AC_FILE="$TEST_PROJECT_ROOT/.aid-o/plans/real-plan.md"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "plan" ]
  unset AID_PLAN_AC_FILE
}

# ── IMP-269 canonical/revision hardening (PM review 2026-07-24) ─────────────
# Gap: ANY readable in-repo file earned ac_source=plan. Only a canonical
# .aid-o/plans or .aid-o/tasks file may; anything else downgrades so the
# AC-lens gate fails closed instead of trusting an arbitrary file.

@test "IMP-269 (canonical): a non-canonical readable in-repo file is NOT laundered into ac_source=plan" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# impl summary\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  _imp269_write_review_profile '["behavior_trace"]'   # no AC lens → run proceeds
  # A perfectly readable, committed, in-repo file that is NOT a plan (a source
  # file), and distinct from final_report.md. It must not be trusted as the AC.
  export AID_PLAN_AC_FILE="$TEST_PROJECT_ROOT/src/app.ts"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "final_report_fallback" ]
  unset AID_PLAN_AC_FILE
}

@test "IMP-269 (canonical): a non-canonical AC file + required AC lens → build FAILS CLOSED" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# impl summary\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  _imp269_write_review_profile '["ac_to_test_identity"]'   # AC lens required
  export AID_PLAN_AC_FILE="$TEST_PROJECT_ROOT/src/app.ts"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -ne 0 ]
  [[ "$output" == *"AC lens required"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json" ]
  unset AID_PLAN_AC_FILE
}

@test "IMP-269 (revision): a canonical plan tracked at HEAD is bundled from the revision, not a dirtied worktree" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# impl summary\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '# The committed plan\n\n## Acceptance Criteria\n- [ ] does X\n' > "$TEST_PROJECT_ROOT/.aid-o/plans/plan.md"
  git -C "$TEST_PROJECT_ROOT" add .aid-o/plans/plan.md
  git -C "$TEST_PROJECT_ROOT" commit -q -m "add plan"
  HEAD_SHA="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"; export HEAD_SHA
  # Dirty the worktree copy AFTER committing — the bundle must use the committed
  # content at HEAD, never this tampered worktree copy.
  printf 'TAMPERED worktree content that never earns trust\n' > "$TEST_PROJECT_ROOT/.aid-o/plans/plan.md"
  _imp269_write_review_profile '["ac_to_test_identity"]'
  _imp269_write_plan_diff pass
  export AID_PLAN_AC_FILE="$TEST_PROJECT_ROOT/.aid-o/plans/plan.md"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "plan" ]
  run grep -q 'committed plan' "$TEST_EVIDENCE_DIR/c3/bundle-plan-ac.md"
  [ "$status" -eq 0 ]
  run grep -q 'TAMPERED' "$TEST_EVIDENCE_DIR/c3/bundle-plan-ac.md"
  [ "$status" -ne 0 ]
  unset AID_PLAN_AC_FILE
}

@test "IMP-269 F2: a PRESENT-but-unparseable review-profile.json fails closed on a non-plan bundle" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# Impl summary\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  printf '{ this is not valid json\n' > "$TEST_EVIDENCE_DIR/review-profile.json"
  unset AID_PLAN_AC_FILE
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -ne 0 ]
  [[ "$output" == *"unparseable"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json" ]
}

@test "IMP-269 F2: an ABSENT review-profile.json stays not-required (ordinary non-AC C3 run is not broken)" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  printf '# Impl summary\n' > "$TEST_EVIDENCE_DIR/final_report.md"
  rm -f "$TEST_EVIDENCE_DIR/review-profile.json"
  unset AID_PLAN_AC_FILE
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.ac_source' "$TEST_EVIDENCE_DIR/audit-input-manifest.json"
  [ "$output" = "final_report_fallback" ]
}

@test "IMP-269 F3: a receipt whose command_sha256 is not sha256(.command) is rejected, not sealed" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  # command says one thing, command_sha256 is a valid-shaped but WRONG hash.
  jq -n --arg h "$HEAD_SHA" '{command:"bats real-suite", command_sha256:"0000000000000000000000000000000000000000000000000000000000000000", head_sha:$h, exit_code:0, passed:1, failed:0, log_sha256:"e838b8e381bac6a532bb51e31736b50ef1231271167860547ca2545fa6964325"}' \
    > "$TEST_EVIDENCE_DIR/gates/forged.receipt.json"
  export AID_TEST_RECEIPT_FILE="$TEST_EVIDENCE_DIR/gates/forged.receipt.json"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  # An explicitly-supplied but forged receipt fails the build CLOSED (exit
  # non-zero, no manifest) — it is never sealed, and it never silently
  # degrades to a manifest missing its promised test evidence.
  [ "$status" -ne 0 ]
  [[ "$output" == *"command_sha256 does not match"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json" ]
  unset AID_TEST_RECEIPT_FILE
}

@test "IMP-269 (log): a receipt whose log_sha256 is not the hash of a real log is rejected, not sealed" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  local cmd="bats real-suite"
  local csha; csha="$(printf '%s' "$cmd" | sha256sum | cut -d' ' -f1)"
  # A real log exists, but log_sha256 is a decoy that does NOT hash it — the
  # "test ran" claim is unbacked.
  printf 'ok 1 something\n1..1\n' > "$TEST_EVIDENCE_DIR/gates/real-suite.log"
  jq -n --arg h "$HEAD_SHA" --arg c "$cmd" --arg cs "$csha" \
    '{command:$c, command_sha256:$cs, head_sha:$h, exit_code:0, passed:1, failed:0,
      log:"real-suite.log", log_sha256:"e838b8e381bac6a532bb51e31736b50ef1231271167860547ca2545fa6964325"}' \
    > "$TEST_EVIDENCE_DIR/gates/decoy.receipt.json"
  export AID_TEST_RECEIPT_FILE="$TEST_EVIDENCE_DIR/gates/decoy.receipt.json"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -ne 0 ]
  [[ "$output" == *"log_sha256 does not match"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json" ]
  unset AID_TEST_RECEIPT_FILE
}

@test "IMP-269 (log): a receipt with no .log field is rejected (log_sha256 is unbacked)" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  _imp269_two_commit_repo
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  local cmd="bats real-suite"
  local csha; csha="$(printf '%s' "$cmd" | sha256sum | cut -d' ' -f1)"
  jq -n --arg h "$HEAD_SHA" --arg c "$cmd" --arg cs "$csha" \
    '{command:$c, command_sha256:$cs, head_sha:$h, exit_code:0, passed:1, failed:0,
      log_sha256:"e838b8e381bac6a532bb51e31736b50ef1231271167860547ca2545fa6964325"}' \
    > "$TEST_EVIDENCE_DIR/gates/nolog.receipt.json"
  export AID_TEST_RECEIPT_FILE="$TEST_EVIDENCE_DIR/gates/nolog.receipt.json"
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$BASE_SHA" "$HEAD_SHA" high
  [ "$status" -ne 0 ]
  [[ "$output" == *"no .log"* || "$output" == *"log"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/audit-input-manifest.json" ]
  unset AID_TEST_RECEIPT_FILE
}

# _drive_clean_dispatch — run a GENUINE end-to-end clean C3 dispatch (real
# build-manifest + real aid-c3-dispatch.sh dispatch driven by an in-test codex
# stub that emits a schema-consistent, NON-blocking medium finding). Leaves a real
# evidence dir (c3/c3-dispatch.json + audit-report.json + codex-last-message.json +
# codex-events.jsonl + audit-input-manifest.json + rendered prompt) that
# `aid-c3-dispatch.sh verify` accepts unchanged — and a medium-finding tuple that
# AC4 can tamper. Does NOT modify the shipped fake-codex fixture (that file is out
# of scope for this step); the stub lives entirely under $TEST_TMPDIR.
_drive_clean_dispatch() {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"

  # project.yaml so identity.project_id resolves to a real value (fingerprints).
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'project_id: test-c3-proj\n' > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml"

  # Two commits with a real source change → base/head.
  mkdir -p "$TEST_PROJECT_ROOT/src"
  printf 'export const a = 1;\n' > "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts .aid-o/config/project.yaml
  git -C "$TEST_PROJECT_ROOT" commit -q -m base
  local base_sha; base_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  printf 'export const b = 2;\n' >> "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts
  git -C "$TEST_PROJECT_ROOT" commit -q -m head
  local head_sha; head_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"

  printf 'src/app.ts\n' > "$TEST_TMPDIR/changed-paths.txt"
  export AID_CHANGED_PATHS="$TEST_TMPDIR/changed-paths.txt"

  # Independence pre-check spy → available (exit 0), so dispatch invokes codex.
  mkdir -p "$TEST_TMPDIR/indep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/indep/detect"
  chmod +x "$TEST_TMPDIR/indep/detect"
  export AID_C3_INDEPENDENCE_BIN="$TEST_TMPDIR/indep/detect"

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$base_sha" "$head_sha" high
  [ "$status" -eq 0 ]
  local brief_hash
  brief_hash="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"

  # In-test clean codex stub (wins on PATH over any real codex): emits a genuine,
  # schema-consistent NON-blocking medium-finding report + a valid event stream.
  mkdir -p "$TEST_TMPDIR/codex-clean"
  cat > "$TEST_TMPDIR/codex-clean/codex" <<'CODEXEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "fake-clean-codex 0.0.0"; exit 0; fi
last=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message|-o) last="$2"; shift 2 ;;
    *) shift ;;
  esac
done
report="$(jq -nc --arg h "$FAKE_HEAD" --arg bh "$FAKE_BRIEF_HASH" \
  '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"findings",blocking_findings:false,
    findings:[{severity:"medium",area:"maintainability",
               finding:"Naming in the touched module could be clearer.",
               recommendation:"Rename for clarity in a follow-up."}]}')"
jq -nc '{type:"thread.started",thread_id:"019f0000-0000-7000-8000-0000000ced01"}'
printf '%s\n' '{"type":"turn.started"}'
jq -nc --arg t "$report" '{type:"item.completed",item:{id:"item_final",type:"agent_message",text:$t}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'
[[ -n "$last" ]] && printf '%s\n' "$report" > "$last"
exit 0
CODEXEOF
  chmod +x "$TEST_TMPDIR/codex-clean/codex"
  export FAKE_HEAD="$head_sha" FAKE_BRIEF_HASH="$brief_hash"
  PATH="$TEST_TMPDIR/codex-clean:$PATH"

  run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -f "$TEST_EVIDENCE_DIR/audit-report.json" ]
  # P065 E-065-7_7 Finding B follow-up: a caller may set AID_C3_ATTEMPT before
  # invoking this helper, in which case c3-dispatch.json lives under
  # c3/attempt-NN/c3/, not the legacy root — legacy (unset) callers are
  # completely unaffected by this branch.
  if [[ -n "${AID_C3_ATTEMPT:-}" ]]; then
    local _attempt_nn; _attempt_nn="$(printf '%02d' "$AID_C3_ATTEMPT")"
    [ -f "$TEST_EVIDENCE_DIR/c3/attempt-${_attempt_nn}/c3/c3-dispatch.json" ]
  else
    [ -f "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" ]
  fi
}

# ─── AC1: enforcement=blocking blocks each provenance anomaly (distinct FAIL) ─

@test "step9/AC1 (blocking): absent c3-dispatch.json → done-advance blocks (check 1)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # Clean report so the EXISTING independent-audit hook passes; NO c3-dispatch.json.
  _write_clean_audit_json_prov "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "S-genuine"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 dispatch provenance block"* ]]
  [[ "$output" == *"c3/c3-dispatch.json not found"* ]]
}

@test "step9/AC1 (blocking): dispatch events_valid:false → done-advance blocks (check 2)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  _write_clean_audit_json_prov "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "S-genuine"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  # Present dispatch json, but the stream never satisfied events_valid.
  _write_dispatch_json_min "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" "S-genuine" true 0 dispatched false

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 dispatch provenance block"* ]]
  [[ "$output" == *"does not prove a successful Codex run"* ]]
  [[ "$output" == *"events_valid=false"* ]]
}

@test "step9/AC1 (blocking): process_id != dispatch session → done-advance blocks (check 3)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # Report's process_id is S-report; dispatch session is S-dispatch → mismatch.
  _write_clean_audit_json_prov "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "S-report"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_dispatch_json_min "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" "S-dispatch" true 0 dispatched true

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 dispatch provenance block"* ]]
  [[ "$output" == *"process_id"* ]]
  [[ "$output" == *"codex_session_id"* ]]
}

@test "step9/AC1 (blocking): reviewed_head != HEAD → done-advance blocks (check 4)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  _pin_c3_blocking
  local head_sha; head_sha="$(git rev-parse HEAD)"
  local stale="0000000000000000000000000000000000000000"

  # revision.head_sha stays current (existing hook passes) but the dispatch-hook
  # provenance field reviewed_head is stale → check 4 fires.
  _write_clean_audit_json_prov "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "S-genuine" "$stale"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_dispatch_json_min "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" "S-genuine" true 0 dispatched true

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 dispatch provenance block"* ]]
  [[ "$output" == *"reviewed_head"* ]]
  [[ "$output" == *"stale audit"* ]]
}

# ─── AC2: enforcement=observe (shipped default) → telemetry only, no block ────

@test "step9/AC2 (observe): absent c3-dispatch.json → c3_dispatch_would_block, does NOT block" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"   # no _pin_c3_blocking → shipped enforcement: observe
  local head_sha; head_sha="$(git rev-parse HEAD)"

  _write_clean_audit_json_prov "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "S-genuine"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 dispatch provenance block"* ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "c3_dispatch_would_block"
}

@test "step9/AC2 (observe): dispatch events_valid:false → would_block telemetry, does NOT block" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_high_c3_common "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  _write_clean_audit_json_prov "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "S-genuine"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_dispatch_json_min "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" "S-genuine" true 0 dispatched false

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 dispatch provenance block"* ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "c3_dispatch_would_block"
}

# ─── AC3: a genuine, fully-consistent dispatched run passes under BOTH modes ──

@test "step9/AC3: genuine clean dispatched run → done-advance passes (observe AND blocking)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _drive_clean_dispatch
  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  # Mode 1: observe (shipped default policy). Passes; dispatch hook finds nothing.
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 dispatch provenance block"* ]]

  # Mode 2: blocking. A successful advance mutated done_phase → reset it first.
  _reset_review_state "$state_file"
  _pin_c3_blocking
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 dispatch provenance block"* ]]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
}

# ─── P065 E-065-7_7 DONE-review Finding B follow-up: this hook must be
#     attempt-aware too, mirroring aid-c3-dispatch.sh's own cmd_verify fix ───
#     (found by CP2 while independently verifying that fix — the hook read
#     c3/c3-dispatch.json from the legacy root, which AID_C3_ATTEMPT layering
#     never writes to; only c3/attempt-NN/c3/c3-dispatch.json exists).

@test "Finding B follow-up: an AID_C3_ATTEMPT-mode dispatch → done-advance passes (observe AND blocking)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  export AID_C3_ATTEMPT=1
  _drive_clean_dispatch
  unset AID_C3_ATTEMPT

  # Proof this genuinely exercises attempt-mode layering, not the legacy path.
  [ -f "$TEST_EVIDENCE_DIR/c3/loop-summary.json" ]
  [ -f "$TEST_EVIDENCE_DIR/c3/attempt-01/c3/c3-dispatch.json" ]
  [ ! -f "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" ]

  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  # Mode 1: observe (shipped default policy).
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 dispatch provenance block"* ]]

  # Mode 2: blocking — THE regression this test guards: before this fix, this
  # failed closed with "c3/c3-dispatch.json not found" even though a genuine
  # clean dispatch had just happened, purely because the hook looked at the
  # wrong (legacy) path.
  _reset_review_state "$state_file"
  _pin_c3_blocking
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 dispatch provenance block"* ]]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
}

@test "Finding B follow-up: a tampered CURRENT attempt's raw evidence still BLOCKS under blocking (check 5 is unaffected)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  export AID_C3_ATTEMPT=1
  _drive_clean_dispatch
  unset AID_C3_ATTEMPT
  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"
  _pin_c3_blocking

  # Tamper the CURRENT attempt's raw last-message post-dispatch. This must
  # still get caught by CHECK 5 (the `verify` shell-out), not by checks 1-4
  # incidentally finding a wrong path — CP2 round-9d found the prior generic
  # assertion here couldn't distinguish the two, so this now asserts the
  # check-5-specific reason text.
  jq '.findings = []' "$TEST_EVIDENCE_DIR/c3/attempt-01/c3/codex-last-message.json" \
    > "$TEST_TMPDIR/tampered.json"
  cp "$TEST_TMPDIR/tampered.json" "$TEST_EVIDENCE_DIR/c3/attempt-01/c3/codex-last-message.json"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 dispatch provenance block"* ]]
  [[ "$output" == *"aid-c3-dispatch.sh verify failed"* ]]
  [[ "$output" == *"faithful-transform binding broken"* ]]
}

@test "Finding B follow-up (CP2 round-9d Finding 1): a malformed c3/loop-summary.json never crashes done-advance — observe stays non-blocking, blocking gets a clean reason" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  export AID_C3_ATTEMPT=1
  _drive_clean_dispatch
  unset AID_C3_ATTEMPT
  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  # Corrupt loop-summary.json: valid JSON, but not an object (models a
  # realistic truncated/partial-write, not a hand-crafted parse error) — jq
  # '.current_attempt' on a bare array exits non-zero.
  printf '[]\n' > "$TEST_EVIDENCE_DIR/c3/loop-summary.json"

  # observe (shipped default): must stay non-blocking — this is the CRITICAL
  # regression CP2 found: pre-fix, the unguarded jq substitution crashed the
  # whole done-advance call under set -e BEFORE the observe/blocking branch
  # was ever reached, defeating "observe is never supposed to block."
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 dispatch provenance block"* ]]

  # blocking: a malformed pointer falls back to the legacy path (which is
  # genuinely absent for an attempt-mode dispatch), so this correctly BLOCKS
  # via check 1 — but with an honest "not found"/PRECONDITION FAIL reason,
  # never a raw crash (the pre-fix bug: exit 5, no PRECONDITION FAIL message
  # at all, because the whole process aborted before reaching this branch).
  _reset_review_state "$state_file"
  _pin_c3_blocking
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"C3 dispatch provenance block"* ]]
  [[ "$output" == *"c3/c3-dispatch.json not found"* ]]
}

# ─── DONE-review #4 finding: evidence_paths (allowlist) entries under the
#     evidence dir must resolve to project_root-relative paths in the ACTUAL
#     rendered prompt — not just in the template's own explanatory text (V8
#     in test-c3-audit-prompt.bats covers that half; this is the end-to-end
#     proof that a real build-manifest + dispatch against a real
#     gates/gates_report.json file produces a correctly resolved reference). ─

@test "DONE-review #4 finding: a real gates/gates_report.json in the evidence dir renders as evidence_dir/gates/gates_report.json, resolvable from project_root" {
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  printf '{"overall":"pass"}\n' > "$TEST_EVIDENCE_DIR/gates/gates_report.json"

  _drive_clean_dispatch
  [ "$status" -eq 0 ]

  local expected_rel
  expected_rel="$(realpath -m --relative-to="$TEST_PROJECT_ROOT" "$TEST_EVIDENCE_DIR/gates/gates_report.json")"
  # Sanity: the expected path is genuinely evidence_dir-prefixed, not a bare
  # "gates/gates_report.json" (which is what the pre-fix bug rendered).
  [[ "$expected_rel" == *".aid-o/work/evidence/"*"/gates/gates_report.json" ]]

  run grep -F "$expected_rel" "$TEST_EVIDENCE_DIR/c3/codex-prompt.txt"
  [ "$status" -eq 0 ]
  # The bare, unresolved form must NOT appear on its own inside the
  # evidence_paths line (it legitimately appears once inside the
  # evidence_dir_path disambiguation sentence's own example text).
  run grep -c "\`gates/gates_report.json, " "$TEST_EVIDENCE_DIR/c3/codex-prompt.txt"
  [ "$output" = "0" ]
}

# ─── AC4: THE critical test — a fabricated report (edited AFTER dispatch, with an
#     intact c3-dispatch.json that passes checks 1–4) is BLOCKED under blocking
#     because verify's report↔raw faithful-transform binding fails. This proves
#     the enforcement is real CODE, not prose duplicated from pipeline.md. ──────

@test "step9/AC4 (blocking): fabricated report (findings edited post-dispatch) → verify shell-out BLOCKS" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _drive_clean_dispatch
  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"
  _pin_c3_blocking

  # Tamper the normalized report's finding text AFTER the genuine dispatch. This
  # keeps blocking_findings=false / status=pass / manifest / head / process_id /
  # reviewed_head all intact — so the EXISTING independent-audit hook AND the
  # dispatch hook's checks 1–4 all PASS. Only verify's report↔raw tuple-set
  # binding can catch it.
  jq '.findings[0].finding="FABRICATED text injected after dispatch"' \
    "$TEST_EVIDENCE_DIR/audit-report.json" > "$TEST_EVIDENCE_DIR/audit-report.json.t"
  mv "$TEST_EVIDENCE_DIR/audit-report.json.t" "$TEST_EVIDENCE_DIR/audit-report.json"
  # Recompute the curator ref for the tampered bytes so the sequencing guard also
  # passes — isolating verify (check 5) as the SOLE blocker.
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 dispatch provenance block"* ]]
  [[ "$output" == *"aid-c3-dispatch.sh verify failed"* ]]
  [[ "$output" == *"faithful-transform binding broken"* ]]
}

@test "step9/AC4 (observe): same fabricated report → would_block telemetry, does NOT block" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _drive_clean_dispatch
  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"

  jq '.findings[0].finding="FABRICATED text injected after dispatch"' \
    "$TEST_EVIDENCE_DIR/audit-report.json" > "$TEST_EVIDENCE_DIR/audit-report.json.t"
  mv "$TEST_EVIDENCE_DIR/audit-report.json.t" "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"C3 dispatch provenance block"* ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "c3_dispatch_would_block"
}

# ═══════════════════════════════════════════════════════════════════════════
# E-065-4_7 — SECURITY REGRESSION FIX (CP3 finding): cmd_verify's Step 5
# "faithful-transform equality" block never bound the top-level `.status`,
# `.audit_report.review_status`, `.audit_report.outcome`, or
# `.audit_report.unverifiable_reasons` fields to the raw Codex response — a
# report with ONLY its top-level `.status` hand-edited (e.g. a genuine
# "pass" flipped to "unverifiable", or vice versa) still verified clean, and
# the FSM done-advance merge gate (which shells out to `verify`) advanced on
# the tampered copy. Fixed by `_derive_report_semantics` (single shared
# function) + additive Step 5 checks in cmd_verify. These 3 tests prove the
# fix actually closes the gap: reverting the fix locally and re-running them
# makes all 3 fail (see implementer notes in the final report).
# ═══════════════════════════════════════════════════════════════════════════

@test "E-065-4_7 CP3 fix: top-level .status tampered (pass→unverifiable, rest intact) → verify exits non-zero" {
  _drive_clean_dispatch
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"

  # _drive_clean_dispatch produces a genuine review_status:"findings",
  # blocking_findings:false → status:"pass" report. Tamper ONLY the top-level
  # .status field, leaving audit_report.review_status/blocking_findings/
  # findings/reviewed_head/codex_brief_hash/process_id all untouched.
  jq '.status = "unverifiable"' "$TEST_EVIDENCE_DIR/audit-report.json" \
    > "$TEST_EVIDENCE_DIR/audit-report.json.t"
  mv "$TEST_EVIDENCE_DIR/audit-report.json.t" "$TEST_EVIDENCE_DIR/audit-report.json"

  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"audit_report.status != expected-from-raw"* ]]
}

@test "E-065-4_7 CP3 fix: .audit_report.review_status tampered (findings→unverifiable, .status left as pass) → verify exits non-zero" {
  _drive_clean_dispatch
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"

  # Same clean pass/findings report. Tamper ONLY .audit_report.review_status;
  # top-level .status stays "pass" (internally inconsistent, but isolates this
  # ONE field so the top-level-status check above cannot be what catches it).
  jq '.audit_report.review_status = "unverifiable"' "$TEST_EVIDENCE_DIR/audit-report.json" \
    > "$TEST_EVIDENCE_DIR/audit-report.json.t"
  mv "$TEST_EVIDENCE_DIR/audit-report.json.t" "$TEST_EVIDENCE_DIR/audit-report.json"

  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"audit_report.review_status != expected-from-raw"* ]]
}

@test "E-065-4_7 CP3 fix: done-advance review release rejects a status-only-tampered report under enforcement:blocking" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _drive_clean_dispatch
  _seed_done_review_state "$state_file"
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "high"}}
JSON
  echo "auditor report" > "$TEST_EVIDENCE_DIR/audit-report.md"
  _pin_c3_blocking

  # Tamper ONLY the top-level .status (pass→unverifiable) AFTER the genuine
  # dispatch — the same bypass reproduction the CP3 finding described. All of
  # checks 1-4 (dispatch presence/success/process_id/reviewed_head) and the
  # existing report<->raw tuple/hash checks still pass; only the fixed Step 5
  # status binding can catch this.
  jq '.status = "unverifiable"' "$TEST_EVIDENCE_DIR/audit-report.json" \
    > "$TEST_EVIDENCE_DIR/audit-report.json.t"
  mv "$TEST_EVIDENCE_DIR/audit-report.json.t" "$TEST_EVIDENCE_DIR/audit-report.json"
  _write_matching_curator_ref "$TEST_EVIDENCE_DIR/audit-report.json"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 dispatch provenance block"* ]]
  [[ "$output" == *"aid-c3-dispatch.sh verify failed"* ]]
  [[ "$output" == *"audit_report.status != expected-from-raw"* ]]
}

# ─── IMP-245 follow-up: verify's unverifiable-branch discard binding ─────────
#
# A real live dogfood run under c3-audit-prompt-v2 got Codex to return a
# SCHEMA-VALID combination previously never exercised: review_status
# "unverifiable" alongside real, non-empty findings (Codex may report
# concrete partial findings while still declining an overall firm verdict).
# The writer (_write_unverifiable, via _derive_report_semantics) intentionally
# discards those findings/blocking_findings — but cmd_verify's Step 5 used to
# compare the report against raw unconditionally, breaking on exactly this
# valid case. Fixed to assert the writer's own known discard
# (blocking_findings:false, findings:[]) instead, only for the unverifiable
# branch. These tests pin that fix as a durable regression.

@test "IMP-245 follow-up: raw unverifiable+findings → report correctly discards, verify passes" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'project_id: test-c3-proj\n' > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml"
  mkdir -p "$TEST_PROJECT_ROOT/src"
  printf 'export const a = 1;\n' > "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts .aid-o/config/project.yaml
  git -C "$TEST_PROJECT_ROOT" commit -q -m base
  local base_sha; base_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  printf 'export const b = 2;\n' >> "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts
  git -C "$TEST_PROJECT_ROOT" commit -q -m head
  local head_sha; head_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"

  printf 'src/app.ts\n' > "$TEST_TMPDIR/changed-paths.txt"
  export AID_CHANGED_PATHS="$TEST_TMPDIR/changed-paths.txt"
  mkdir -p "$TEST_TMPDIR/indep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/indep/detect"
  chmod +x "$TEST_TMPDIR/indep/detect"
  export AID_C3_INDEPENDENCE_BIN="$TEST_TMPDIR/indep/detect"

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$base_sha" "$head_sha" high
  [ "$status" -eq 0 ]
  local brief_hash
  brief_hash="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"

  # Fake codex stub: unverifiable, but with real (schema-valid) findings + a
  # claimed blocking_findings:true — exactly the combination that broke
  # verify before this fix.
  mkdir -p "$TEST_TMPDIR/codex-unverifiable-findings"
  cat > "$TEST_TMPDIR/codex-unverifiable-findings/codex" <<'CODEXEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "fake-unverifiable-findings-codex 0.0.0"; exit 0; fi
last=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message|-o) last="$2"; shift 2 ;;
    *) shift ;;
  esac
done
report="$(jq -nc --arg h "$FAKE_HEAD" --arg bh "$FAKE_BRIEF_HASH" \
  '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"unverifiable",
    unverifiable_reasons:["no committed gate artifact for this range"],
    blocking_findings:true,
    findings:[{severity:"high",area:"scope",finding:"partial concern noted",
               recommendation:"fix and re-audit",action_owner:"implementer"}]}')"
jq -nc '{type:"thread.started",thread_id:"019f0000-0000-7000-8000-0000000ced02"}'
printf '%s\n' '{"type":"turn.started"}'
jq -nc --arg t "$report" '{type:"item.completed",item:{id:"item_final",type:"agent_message",text:$t}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'
[[ -n "$last" ]] && printf '%s\n' "$report" > "$last"
exit 0
CODEXEOF
  chmod +x "$TEST_TMPDIR/codex-unverifiable-findings/codex"
  export FAKE_HEAD="$head_sha" FAKE_BRIEF_HASH="$brief_hash"
  PATH="$TEST_TMPDIR/codex-unverifiable-findings:$PATH"

  run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]  # dispatch's exit code reflects capture success, not report trustworthiness

  # The writer must have discarded the raw findings/blocking_findings.
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "unverifiable" ]
  run jq -r '.audit_report.blocking_findings' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "false" ]
  run jq -r '.findings | length' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "0" ]

  # verify must accept this as faithful (the discard is the correct,
  # documented behavior, not evidence of tampering).
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == verified* ]]
}

@test "IMP-245 follow-up: unverifiable report with blocking_findings tampered to true → verify rejects" {
  local DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'project_id: test-c3-proj\n' > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml"
  mkdir -p "$TEST_PROJECT_ROOT/src"
  printf 'export const a = 1;\n' > "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts .aid-o/config/project.yaml
  git -C "$TEST_PROJECT_ROOT" commit -q -m base
  local base_sha; base_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  printf 'export const b = 2;\n' >> "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts
  git -C "$TEST_PROJECT_ROOT" commit -q -m head
  local head_sha; head_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"

  printf 'src/app.ts\n' > "$TEST_TMPDIR/changed-paths.txt"
  export AID_CHANGED_PATHS="$TEST_TMPDIR/changed-paths.txt"
  mkdir -p "$TEST_TMPDIR/indep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/indep/detect"
  chmod +x "$TEST_TMPDIR/indep/detect"
  export AID_C3_INDEPENDENCE_BIN="$TEST_TMPDIR/indep/detect"

  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$base_sha" "$head_sha" high
  [ "$status" -eq 0 ]
  local brief_hash
  brief_hash="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"

  mkdir -p "$TEST_TMPDIR/codex-unverifiable-plain"
  cat > "$TEST_TMPDIR/codex-unverifiable-plain/codex" <<'CODEXEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "fake-unverifiable-plain-codex 0.0.0"; exit 0; fi
last=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message|-o) last="$2"; shift 2 ;;
    *) shift ;;
  esac
done
report="$(jq -nc --arg h "$FAKE_HEAD" --arg bh "$FAKE_BRIEF_HASH" \
  '{reviewed_head:$h,codex_brief_hash:$bh,review_status:"unverifiable",
    unverifiable_reasons:["no committed gate artifact for this range"],
    blocking_findings:false,findings:[]}')"
jq -nc '{type:"thread.started",thread_id:"019f0000-0000-7000-8000-0000000ced03"}'
printf '%s\n' '{"type":"turn.started"}'
jq -nc --arg t "$report" '{type:"item.completed",item:{id:"item_final",type:"agent_message",text:$t}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'
[[ -n "$last" ]] && printf '%s\n' "$report" > "$last"
exit 0
CODEXEOF
  chmod +x "$TEST_TMPDIR/codex-unverifiable-plain/codex"
  export FAKE_HEAD="$head_sha" FAKE_BRIEF_HASH="$brief_hash"
  PATH="$TEST_TMPDIR/codex-unverifiable-plain:$PATH"

  run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]  # dispatch's exit code reflects capture success, not report trustworthiness

  # Tamper the genuinely-unverifiable report AFTER dispatch: claim
  # blocking_findings:true with no findings — must still be rejected.
  jq '.audit_report.blocking_findings = true' "$TEST_EVIDENCE_DIR/audit-report.json" \
    > "$TEST_EVIDENCE_DIR/audit-report.json.t"
  mv "$TEST_EVIDENCE_DIR/audit-report.json.t" "$TEST_EVIDENCE_DIR/audit-report.json"

  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking_findings != false"* ]]
}
