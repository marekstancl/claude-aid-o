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
  teardown_test_evidence_dir
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

@test "C3 EPIC scenario 4b (negative control): curator-report.json absent on medium-risk profile → passes (no-op)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  local head_sha; head_sha="$(git rev-parse HEAD)"

  # Medium risk profile does NOT require C3, so curator-report.json is optional.
  # Absence is a silent no-op — the run should pass (only the legacy .md check).
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{"review_profile": {"risk_profile": "medium"}}
JSON
  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  _write_clean_audit_json "$TEST_EVIDENCE_DIR/audit-report.json" "$head_sha" "pass" "false"

  # Omit both curator-report.json AND curator-report.md. The basic existence check
  # will block. So we touch the legacy .md file to only isolate the JSON-level behavior.
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  # Isolate: with medium profile (C3 not required), curator-report.json missing
  # should NOT block at the JSON level. The .md file satisfies the base requirement.
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"curator-report.json not found"* ]]
}
