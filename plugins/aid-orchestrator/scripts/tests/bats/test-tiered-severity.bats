#!/usr/bin/env bats
# aid-tier: t2
# test-tiered-severity.bats — P038 Phase 2 tiered severity + merge blocking smoke test.
# Extended by P042: compliance recovery alert (fixtures 7a-7c).
#
# Validates the AID-v3-principles.md §1 enforcement chain:
#   Step 1 (--blocked-checks audit-log array) →
#   Step 2 (failures[] schema + check-severity.yaml registry) →
#   Step 3 (cmd_done_advance review→release blocking precondition) →
#   Step 4 (cmd_promote_check + cmd_check_promotion_candidates)
#
# All fixtures isolate via `mktemp -d` and tear down reliably. Tests do NOT
# source aid-fsm.sh — they invoke it as a subprocess so the BASH_SOURCE
# guard's dispatcher runs and we exercise the real CLI surface (matches the
# Plan §1232 architecture note: "Bats tests do NOT run real done-advance —
# they invoke … via bash aid-fsm.sh done-advance ... subprocess, which gives
# faster + isolated test execution.").
#
# Why TZ=UTC: verify_provenance() inside aid-fsm.sh compares jq's
# fromdateiso8601 (which silently honours local TZ on jq <1.7) against UTC
# epochs from `date -d`. On CEST hosts this disagrees by 3600s and the
# interval-bracket provenance check misfires. See test-anti-fabrication.bats:14-20
# for the canonical write-up.
#
# Helpers used: shared `mktemp -d` pattern; no additions to test-helpers.bash
# (each fixture is self-contained).

setup() {
  export TZ=UTC
  # Suppress try_telegram_alert during fixture runs (P038 cmd_done_advance
  # precondition fires alert on blocking compliance failures; without this
  # guard each fixture would send a real Telegram message).
  export AID_TEST_MODE=1
  TMPDIR_TEST="$(mktemp -d)"
  PROJECT_ROOT="$TMPDIR_TEST"
  EPIC_ID="E-TEST-038"
  RUN_ID="R-TEST-038-1"
  EVIDENCE_DIR="${PROJECT_ROOT}/.aid-o/work/evidence/${EPIC_ID}/${RUN_ID}"
  STATE_FILE="${EVIDENCE_DIR}/fsm-state.yaml"
  CONFIG_DIR="${PROJECT_ROOT}/.aid-o/config"
  SEVERITY_YAML="${CONFIG_DIR}/check-severity.yaml"
  AUDIT_LOG="${PROJECT_ROOT}/.aid-o/work/audit-log.jsonl"

  mkdir -p "$EVIDENCE_DIR" "$CONFIG_DIR" "$(dirname "$AUDIT_LOG")"
  mkdir -p "${PROJECT_ROOT}/.aid-o/tasks"           # cmd_done_advance does `find .aid-o/tasks/`; missing dir → set -e crash
  mkdir -p "${EVIDENCE_DIR}/gates"

  # Explicit subagent dispatch_mode so fixtures 1-3 (provenance blocking / verified /
  # force override) keep testing interval-bracket provenance — not affected by the
  # agent_tool default change (P043). Fixture 2b removes this file to test the default;
  # fixtures that don't test provenance are unaffected either way.
  cat > "${CONFIG_DIR}/plugin.yaml" <<EOF
plugin_path: "${PROJECT_ROOT}"
dispatch_mode: subagent
EOF

  # Minimal fsm-state.yaml in DONE state, done_phase=review, branch matches task/E-* regex
  cat > "$STATE_FILE" <<EOF
epic_id: ${EPIC_ID}
run_id: ${RUN_ID}
branch: task/E-TEST-038/main
state: DONE
done_phase: review
created_at: 2026-05-13T10:00:00Z
total_steps: 3
current_step: 3
pm_decision: merge
EOF

  # Default check-severity.yaml: mirrors plugin defaults/check-severity.yaml
  # for the 3 dimensions exercised here (verifier_provenance + gates_generated_by
  # blocking, memory_substantive advisory). Other registry rows omitted — not
  # under test in this file.
  cat > "$SEVERITY_YAML" <<EOF
version: 1
checks:
  verifier_provenance:
    severity: blocking
    promoted_at: "2026-05-13"
    promoted_reason: "test fixture default"
  gates_generated_by:
    severity: blocking
    promoted_at: "2026-05-05"
    promoted_reason: "Session A grandfathered"
  plan_ac_match:
    severity: blocking
    promoted_at: "2026-05-13"
    promoted_reason: "test fixture default"
  memory_substantive:
    severity: advisory
    promoted_at: null
    promoted_reason: null
  dod_present:
    severity: advisory
    promoted_at: null
    promoted_reason: null
EOF

  # Satisfy non-provenance compliance dimensions so an unverifiable provenance
  # is the ONLY blocking failure in fixture 1 and there are NO blocking
  # failures in fixture 2:
  #   - execution_yaml_present requires .aid-o/config/execution.yaml
  #   - gates_generated_by requires evidence_dir/gates/gates_report.json with ._generated_by
  touch "${CONFIG_DIR}/execution.yaml"
  printf '{"_generated_by":"aid-run-gates.sh@test-fixture"}\n' > "${EVIDENCE_DIR}/gates/gates_report.json"

  # Minimal curator + auditor reports so the remaining cmd_done_advance
  # preconditions (curator-report, audit-report, CP5 blocking_findings) all pass.
  # blocking_findings: false MUST be at line-start (yaml_field line-start match,
  # E-046-1_3 Step 3 fail-closed). Plain "fixture auditor report" without this
  # field now triggers the fail-closed precondition.
  echo "fixture curator report" > "${EVIDENCE_DIR}/curator-report.md"
  printf 'blocking_findings: false\nfixture auditor report\n' > "${EVIDENCE_DIR}/audit-report.md"

  # Empty timeline + audit-log so fixtures can append controlled events.
  : > "${EVIDENCE_DIR}/timeline.jsonl"
  : > "$AUDIT_LOG"

  # Resolve absolute path to aid-fsm.sh from this test file's location.
  # Pattern mirrors test-anti-fabrication.bats _load_aid_fsm shim.
  AID_FSM_PATH="${BATS_TEST_DIRNAME}/../../aid-fsm.sh"
}

teardown() {
  cd /
  [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST"
}

# ─── Fixture 1 ──────────────────────────────────────────────────────────
# Blocking compliance failure (unverifiable verifier provenance) MUST block
# done-advance review→release with exit 2 and a structured error message
# naming the offending check.
@test "fixture 1: blocking compliance failure blocks done-advance" {
  # Manufacture an unverifiable provenance: step-1-verify.md present (drives the
  # CP2 loop) + verifier-output-step-1.md present (validates the per-step
  # outputs schema check) + EMPTY timeline.jsonl (verify_provenance returns
  # "unverifiable" because no verifier_dispatch_start/_complete events match).
  cat > "${EVIDENCE_DIR}/step-1-verify.md" <<EOF
classification: RUN
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: 2025-01-01T00:00:00Z
classification: RUN
verdict: pass
EOF
  # Timeline already truncated in setup() → no dispatch events.

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"blocking compliance failure"* ]]
  [[ "$output" == *"verifier_provenance"* ]]
}

# ─── Fixture 2 ──────────────────────────────────────────────────────────
# Verified provenance + no blocking failures → release proceeds (exit 0).
# Inversion of fixture 1: manufacture matching timeline events for the
# verifier output so provenance_aggregate becomes "all_verified" and no
# synthetic verifier_provenance failure is generated. Advisory dimensions
# (memory_substantive, dod_present) report null and never reach failures[].
@test "fixture 2: advisory failure does NOT block done-advance (verified provenance)" {
  local GEN_AT="2026-05-13T12:00:00Z"
  local GEN_AT_MIN30="2026-05-13T11:59:30Z"
  local GEN_AT_PLUS30="2026-05-13T12:00:30Z"

  # Real timeline.jsonl with verifier_dispatch events INSIDE the ±60s window.
  cat > "${EVIDENCE_DIR}/timeline.jsonl" <<EOF
{"ts":"${GEN_AT_MIN30}","event":"verifier_dispatch_start","focus":"cp2-step-1","agentId":"aid-orchestrator:verifier","step_n":1,"evidence_dir":"${EVIDENCE_DIR}"}
{"ts":"${GEN_AT_PLUS30}","event":"verifier_dispatch_complete","focus":"cp2-step-1","agentId":"aid-orchestrator:verifier","step_n":1,"evidence_dir":"${EVIDENCE_DIR}","output_file":"${EVIDENCE_DIR}/verifier-output-step-1.md"}
EOF
  cat > "${EVIDENCE_DIR}/step-1-verify.md" <<EOF
classification: RUN
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: ${GEN_AT}
classification: RUN
verdict: pass
EOF

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -eq 0 ]

  # Compliance.json must exist with zero blocking failures.
  [ -f "${EVIDENCE_DIR}/compliance.json" ]
  local blocking_count
  blocking_count=$(jq '.failures | map(select(.severity=="blocking")) | length' "${EVIDENCE_DIR}/compliance.json")
  [ "$blocking_count" -eq 0 ]
}

# ─── Fixture 2b ─────────────────────────────────────────────────────────
# agent_tool dispatch_mode + no timeline events → verifier_provenance must NOT block.
# (P043: default dispatch_mode changed from subagent to agent_tool so CC Agent tool
# users are no longer blocked on every EPIC.)
@test "fixture 2b: agent_tool dispatch_mode skips provenance check (no timeline events)" {
  # Remove setup's plugin.yaml entirely — exercises the true P043 default path
  # (CC Agent tool user with no dispatch_mode config at all).
  rm -f "${CONFIG_DIR}/plugin.yaml"

  # Same unverifiable setup as fixture 1: verifier output present, timeline empty.
  cat > "${EVIDENCE_DIR}/step-1-verify.md" <<EOF
classification: RUN
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: 2025-01-01T00:00:00Z
classification: RUN
verdict: pass
EOF
  # Timeline remains empty (no dispatch events) — agent_tool must not block.

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -eq 0 ]

  # compliance.json must have zero blocking failures (verifier_provenance not in blocking list)
  [ -f "${EVIDENCE_DIR}/compliance.json" ]
  local blocking_count
  blocking_count=$(jq '.failures | map(select(.severity=="blocking")) | length' "${EVIDENCE_DIR}/compliance.json")
  [ "$blocking_count" -eq 0 ]

  # Aggregate must report the mode-level sentinel, not a misleading "mixed".
  local prov_agg
  prov_agg=$(jq -r '.checks.verifier_outputs.provenance_aggregate' "${EVIDENCE_DIR}/compliance.json")
  [ "$prov_agg" = "agent_tool" ]
}

# ─── Fixture 3 ──────────────────────────────────────────────────────────
# --force --reason ≥20 chars --blocked-checks "a,b" bypasses the blocking
# precondition AND appends an fsm_force_override event to audit-log.jsonl
# with a structured `blocked_checks` JSON array (not a comma string).
@test "fixture 3: --force --reason --blocked-checks proceeds and writes audit-log JSON array" {
  # Manufacture a blocking failure so the override has something to override
  # (same unverifiable-provenance setup as fixture 1).
  cat > "${EVIDENCE_DIR}/step-1-verify.md" <<EOF
classification: RUN
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: 2025-01-01T00:00:00Z
classification: RUN
verdict: pass
EOF

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE" \
    --force \
    --reason "fixture-test override reason ≥20 chars OK" \
    --blocked-checks "verifier_provenance,gates_generated_by"
  [ "$status" -eq 0 ]

  # Audit-log must contain an fsm_force_override entry with the JSON array.
  [ -s "$AUDIT_LOG" ]
  local last_event
  last_event=$(grep '"event":"fsm_force_override"' "$AUDIT_LOG" | tail -1)
  [ -n "$last_event" ]

  # Strict shape: blocked_checks is an array of length 2 with the exact contents.
  echo "$last_event" | jq -e '
    .blocked_checks
    | (type == "array")
      and (length == 2)
      and (.[0] == "verifier_provenance")
      and (.[1] == "gates_generated_by")
  '
}

# ─── Fixture 4 ──────────────────────────────────────────────────────────
# --force with --reason <20 chars must be rejected. fsm_handle_force_override
# uses die() which exits 1 (verified by smoke test against aid-fsm.sh@81122da
# — see also Step 1 implementer's audit-log array tests which used 30+ char
# reasons throughout). The original P038 plan skeleton wrote `-ne 0`; we
# tighten it to `-eq 1` since the exit code is deterministic.
@test "fixture 4: --force with --reason <20 chars exits 1 (die)" {
  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE" \
    --force \
    --reason "too short" \
    --blocked-checks "verifier_provenance"
  [ "$status" -eq 1 ]
  [[ "$output" == *"min 20 characters"* ]]

  # No state mutation — done_phase still review (force aborts before sed).
  local current_phase
  current_phase=$(grep '^done_phase:' "$STATE_FILE" | awk '{print $2}')
  [ "$current_phase" = "review" ]
}

# ─── Fixture 5 ──────────────────────────────────────────────────────────
# promote-check mutates check-severity.yaml in place (advisory → blocking)
# and appends a `check_promoted` event to audit-log.jsonl with the required
# fields.
@test "fixture 5: promote-check advisory → blocking + audit-log entry" {
  cd "$PROJECT_ROOT"

  # Sanity: pre-promotion severity is advisory.
  local pre_severity
  pre_severity=$(yq -r '.checks.memory_substantive.severity' "$SEVERITY_YAML")
  [ "$pre_severity" = "advisory" ]

  run bash "$AID_FSM_PATH" promote-check memory_substantive \
    --reason "fixture-test promotion ≥20 chars OK"
  [ "$status" -eq 0 ]

  # Registry mutated in place.
  local new_severity new_promoted_at
  new_severity=$(yq -r '.checks.memory_substantive.severity' "$SEVERITY_YAML")
  new_promoted_at=$(yq -r '.checks.memory_substantive.promoted_at' "$SEVERITY_YAML")
  [ "$new_severity" = "blocking" ]
  [ -n "$new_promoted_at" ] && [ "$new_promoted_at" != "null" ]

  # Audit-log entry: structured shape verified via jq -e on the JSONL line.
  [ -s "$AUDIT_LOG" ]
  local entry
  entry=$(grep '"event":"check_promoted"' "$AUDIT_LOG" | tail -1)
  [ -n "$entry" ]
  echo "$entry" | jq -e '
    (.event == "check_promoted")
    and (.check == "memory_substantive")
    and (.previous_severity == "advisory")
    and (.new_severity == "blocking")
    and (.reason | test("≥20 chars"))
    and (.operator != null)
  '
}

# ─── Fixture 6 ──────────────────────────────────────────────────────────
# check-promotion-candidates identifies advisory checks meeting the
# AID-v3-principles.md §1 promotion criterion (epic_count >= 5 AND
# override_count/epic_count < 0.05). Pre-populate 5 distinct EPICs whose
# compliance.json failures[] include memory_substantive, with zero
# fsm_force_override events naming it.
@test "fixture 6: check-promotion-candidates identifies ready candidates" {
  # 5 distinct EPICs with memory_substantive in failures[]; audit-log empty
  # so override_count=0 → rate=0.00 < 0.05 → candidate=yes.
  for i in 1 2 3 4 5; do
    local edir="${PROJECT_ROOT}/.aid-o/work/evidence/E-TEST-${i}/R-TEST-${i}-1"
    mkdir -p "$edir"
    cat > "$edir/compliance.json" <<EOF
{"epic_id":"E-TEST-${i}","run_id":"R-TEST-${i}-1","failures":[{"check":"memory_substantive","severity":"advisory","evidence":"empty","promoted_at":null}],"overall":"fail"}
EOF
  done

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" check-promotion-candidates
  [ "$status" -eq 0 ]

  # Output table must list memory_substantive with candidate=yes.
  [[ "$output" == *"memory_substantive"* ]]
  # The candidate row format is fixed-width: `<name>  <epic_count>  <override_count>  <rate>  yes`.
  echo "$output" | grep -E 'memory_substantive +5 +0 +0\.00 +yes'
}

# ─── Recovery alert fixtures (P042) ─────────────────────────────────────────
# These fixtures reuse the fixture-2 clean-done-advance harness (verified
# provenance + no blocking failures). The observable signal is the
# fsm_done_advance_recovered event in timeline.jsonl — NOT the Telegram alert
# text (AID_TEST_MODE=1 suppresses try_telegram_alert unconditionally).

# Shared helper: write fixture-2-style verified-provenance files so done-advance
# exits 0. Caller must cd "$PROJECT_ROOT" first.
_setup_clean_done_advance() {
  local GEN_AT="2026-05-13T12:00:00Z"
  local GEN_AT_MIN30="2026-05-13T11:59:30Z"
  local GEN_AT_PLUS30="2026-05-13T12:00:30Z"

  cat >> "${EVIDENCE_DIR}/timeline.jsonl" <<EOF
{"ts":"${GEN_AT_MIN30}","event":"verifier_dispatch_start","focus":"cp2-step-1","agentId":"aid-orchestrator:verifier","step_n":1,"evidence_dir":"${EVIDENCE_DIR}"}
{"ts":"${GEN_AT_PLUS30}","event":"verifier_dispatch_complete","focus":"cp2-step-1","agentId":"aid-orchestrator:verifier","step_n":1,"evidence_dir":"${EVIDENCE_DIR}","output_file":"${EVIDENCE_DIR}/verifier-output-step-1.md"}
EOF
  cat > "${EVIDENCE_DIR}/step-1-verify.md" <<EOF
classification: RUN
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: ${GEN_AT}
classification: RUN
verdict: pass
EOF
}

# ─── Fixture 7a ─────────────────────────────────────────────────────────────
# blocked-then-cleared: prior fsm_done_advance_blocked in timeline + clean run
# → exactly ONE fsm_done_advance_recovered event written to timeline.
@test "fixture 7a: recovery: blocked-then-cleared writes exactly one recovered event" {
  # Seed a prior blocking event (simulates a previous blocked done-advance).
  printf '{"ts":"2026-05-13T10:00:00Z","event":"fsm_done_advance_blocked","blocking_count":1,"blocked_checks":"verifier_provenance"}\n' \
    >> "${EVIDENCE_DIR}/timeline.jsonl"

  _setup_clean_done_advance

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -eq 0 ]

  # Timeline must have exactly one fsm_done_advance_recovered event.
  local recovered_count
  recovered_count=$(jq -s '[.[] | select(.event=="fsm_done_advance_recovered")] | length' \
    "${EVIDENCE_DIR}/timeline.jsonl")
  [ "$recovered_count" -eq 1 ]

  # recovered_checks field must carry the original blocked check name.
  local recovered_checks
  recovered_checks=$(jq -rs '[.[] | select(.event=="fsm_done_advance_recovered")] | last | .recovered_checks' \
    "${EVIDENCE_DIR}/timeline.jsonl")
  [ "$recovered_checks" = "verifier_provenance" ]
}

# ─── Fixture 7b ─────────────────────────────────────────────────────────────
# no-prior-block: clean timeline (no fsm_done_advance_blocked event) + clean run
# → zero fsm_done_advance_recovered events written.
@test "fixture 7b: recovery: no prior block writes no recovered event" {
  # Timeline starts empty (no blocked event — setup() truncates it).
  _setup_clean_done_advance

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -eq 0 ]

  # No fsm_done_advance_recovered event must appear in the timeline.
  local recovered_count
  recovered_count=$(jq -s '[.[] | select(.event=="fsm_done_advance_recovered")] | length' \
    "${EVIDENCE_DIR}/timeline.jsonl")
  [ "$recovered_count" -eq 0 ]
}

# ─── Fixture 7c ─────────────────────────────────────────────────────────────
# dedup: timeline already has a blocked + recovered pair → second clean run
# must NOT write an additional fsm_done_advance_recovered event.
@test "fixture 7c: recovery: dedup — second clean run after recovery writes no new recovered event" {
  # Seed a blocked event followed immediately by a recovered event (already cleared).
  printf '{"ts":"2026-05-13T09:00:00Z","event":"fsm_done_advance_blocked","blocking_count":1,"blocked_checks":"verifier_provenance"}\n' \
    >> "${EVIDENCE_DIR}/timeline.jsonl"
  printf '{"ts":"2026-05-13T09:30:00Z","event":"fsm_done_advance_recovered","recovered_checks":"verifier_provenance"}\n' \
    >> "${EVIDENCE_DIR}/timeline.jsonl"

  _setup_clean_done_advance

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -eq 0 ]

  # Still exactly one fsm_done_advance_recovered event (the seeded one; no new one added).
  local recovered_count
  recovered_count=$(jq -s '[.[] | select(.event=="fsm_done_advance_recovered")] | length' \
    "${EVIDENCE_DIR}/timeline.jsonl")
  [ "$recovered_count" -eq 1 ]
}

# ─── Fixture 7e ─────────────────────────────────────────────────────────────
# force-path recovery (P044): a pending fsm_done_advance_blocked cleared via
# --force override must ALSO write the fsm_done_advance_recovered event —
# pairing every 🛑 blocked alert with a ✅ resolution regardless of which path
# cleared the block (clean re-run vs PM force-override).
@test "fixture 7e: recovery: force override after block writes exactly one recovered event" {
  # Seed a prior blocking event (simulates a previous blocked done-advance).
  printf '{"ts":"2026-05-13T10:00:00Z","event":"fsm_done_advance_blocked","blocking_count":1,"blocked_checks":"verifier_provenance"}\n' \
    >> "${EVIDENCE_DIR}/timeline.jsonl"

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE" \
    --force \
    --reason "PM approved merge despite provenance gap (fixture 7e)" \
    --blocked-checks "verifier_provenance"
  [ "$status" -eq 0 ]

  # Timeline must have exactly one fsm_done_advance_recovered event.
  local recovered_count
  recovered_count=$(jq -s '[.[] | select(.event=="fsm_done_advance_recovered")] | length' \
    "${EVIDENCE_DIR}/timeline.jsonl")
  [ "$recovered_count" -eq 1 ]

  # recovered_checks field must carry the original blocked check name.
  local recovered_checks
  recovered_checks=$(jq -rs '[.[] | select(.event=="fsm_done_advance_recovered")] | last | .recovered_checks' \
    "${EVIDENCE_DIR}/timeline.jsonl")
  [ "$recovered_checks" = "verifier_provenance" ]
}

# ─── Fixture 7f ─────────────────────────────────────────────────────────────
# force-path no-op (P044): --force with NO pending blocked event must not
# fabricate a recovered event (nothing to pair).
@test "fixture 7f: recovery: force override with no prior block writes no recovered event" {
  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE" \
    --force \
    --reason "PM approved merge with no prior block (fixture 7f)" \
    --blocked-checks ""
  [ "$status" -eq 0 ]

  local recovered_count
  recovered_count=$(jq -s '[.[] | select(.event=="fsm_done_advance_recovered")] | length' \
    "${EVIDENCE_DIR}/timeline.jsonl")
  [ "$recovered_count" -eq 0 ]
}

# ─── Fixture 7d ─────────────────────────────────────────────────────────────
# gate-disabled: alert_on_compliance_recovery=false in execution.yaml → alert
# suppressed, but the fsm_done_advance_recovered event is still written (log_event
# is unconditional; only try_telegram_alert is gated).
@test "fixture 7d: recovery: gate disabled suppresses alert but still writes recovered event" {
  # Seed a prior blocking event.
  printf '{"ts":"2026-05-13T10:00:00Z","event":"fsm_done_advance_blocked","blocking_count":1,"blocked_checks":"verifier_provenance"}\n' \
    >> "${EVIDENCE_DIR}/timeline.jsonl"

  # Disable the alert gate in execution.yaml (4-space indent, under notifications.telegram).
  cat >> "${CONFIG_DIR}/execution.yaml" <<EOF
notifications:
  telegram:
    enabled: false
    alert_on_compliance_recovery: false
EOF

  _setup_clean_done_advance

  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -eq 0 ]

  # The recovered event MUST still be written (dedup marker is unconditional).
  local recovered_count
  recovered_count=$(jq -s '[.[] | select(.event=="fsm_done_advance_recovered")] | length' \
    "${EVIDENCE_DIR}/timeline.jsonl")
  [ "$recovered_count" -eq 1 ]
}

# ─── E-046-1_3 Step 3: CP5 blocking_findings four-case matrix ─────────────────
# Regression for the `grep -ciE` false-positive parser replaced by yaml_field
# line-start match (fail-closed on absence). All four behaviours must hold.

# Shared helper for CP5 tests: _setup_clean_done_advance already exists for
# fixture 7 series. We reuse it and then overwrite audit-report.md per-test.

@test "CP5: blocking_findings: true at line-start → done-advance blocked (fail)" {
  _setup_clean_done_advance
  printf 'blocking_findings: true\nsome prose body\n' > "${EVIDENCE_DIR}/audit-report.md"
  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking_findings"* ]]
}

@test "CP5: blocking_findings: false at line-start → done-advance passes" {
  _setup_clean_done_advance
  printf 'blocking_findings: false\nsome prose body\n' > "${EVIDENCE_DIR}/audit-report.md"
  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "CP5: blocking_findings field absent (no top-level key) → fail-closed (blocked)" {
  _setup_clean_done_advance
  # Only body prose, no blocking_findings key at line-start
  printf '# Audit Report\nNo blocking findings found today.\n' > "${EVIDENCE_DIR}/audit-report.md"
  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing canonical top-level"* ]]
}

@test "CP5: blocking_findings: true only in body (indented) → NOT a block (line-start only)" {
  # This is the false-positive case the old grep -ciE would have caught.
  # yaml_field matches only line-start → indented value is invisible → no block.
  _setup_clean_done_advance
  printf 'blocking_findings: false\naudit_report:\n  blocking_findings: true\n  prose: body\n' \
    > "${EVIDENCE_DIR}/audit-report.md"
  cd "$PROJECT_ROOT"
  run bash "$AID_FSM_PATH" done-advance review release "$STATE_FILE"
  # Top-level says false → should pass despite nested true
  [ "$status" -eq 0 ]
}
