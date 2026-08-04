#!/usr/bin/env bats
# test-force-anomalies.bats — P073 Step 9: the three inconsistencies in the
# force landscape.
#
#   1. `aid-fsm.sh plan-close` took three positionals and nothing else, so the
#      dispatcher handed it any `--force --reason ...` the operator typed and
#      it VANISHED. That is worse than a rejection: the operator believed they
#      had forced something.
#   2. `aid-fsm.sh init` had a silent `*)` sink for unknown flags, so a typo'd
#      or misplaced flag was indistinguishable from one that was honoured.
#   3. `aid-release.sh --force` was the ONE unaudited bypass in the codebase —
#      the FSM guard's own message recommended it, with no reason and no record.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  RELEASE="$AID_PLUGIN_PATH/scripts/aid-release.sh"
  export FSM RELEASE
  REASON="the ca-review marker is unreachable after a corrupted run and the plan must close"
  export REASON
}

teardown() {
  teardown_test_evidence_dir
}

# ─── anomaly 1: plan-close swallowed --force ──────────────────────────────

@test "P073 Step 9: aid-fsm.sh plan-close --force WITHOUT a reason now dies instead of silently proceeding" {
  run "$FSM" plan-close E-900-1_1 "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT" --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"--force requires --reason"* ]]
}

@test "P073 Step 9: aid-fsm.sh plan-close --force WITH a reason writes the audited records" {
  run "$FSM" plan-close E-900-1_1 "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT" \
      --force --reason "$REASON"
  # The command may still fail on its own downstream checks; what this asserts
  # is that the force was AUDITED rather than swallowed.
  [[ "$output" != *"Unknown flag"* ]]
  local logged=0
  [[ -s "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl" ]] && \
    grep -q 'fsm_force_override' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl" && logged=1
  local waived=0
  [[ -n "$(find "$TEST_EVIDENCE_DIR" -name 'waiver-*.json' 2>/dev/null)" ]] && waived=1
  [ "$(( logged + waived ))" -ge 1 ]
}

@test "P073 Step 9: aid-fsm.sh plan-close rejects an unknown flag by name" {
  run "$FSM" plan-close E-900-1_1 "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown flag for plan-close: --bogus"* ]]
}

@test "P073 Step 9: aid-fsm.sh plan-close --reason without --force is refused, not ignored" {
  run "$FSM" plan-close E-900-1_1 "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT" --reason "$REASON"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bypasses nothing"* ]]
}

@test "P073 Step 9: legacy positional-only plan-close is unchanged (no flags parsed, no regression)" {
  run "$FSM" plan-close E-900-1_1 "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  # Whatever it does on this bare fixture, it must not be a flag-parsing error.
  [[ "$output" != *"Unknown flag"* ]]
  [[ "$output" != *"--force requires --reason"* ]]
}

# ─── anomaly 2: init's silent unknown-flag sink ───────────────────────────

@test "P073 Step 9: aid-fsm.sh init rejects an unknown flag by name instead of ignoring it" {
  run "$FSM" init E-900-1_1 R-900-1 3 full main "$(git rev-parse HEAD 2>/dev/null || echo abc123)" \
      "$TEST_EVIDENCE_DIR/fsm-state.yaml" --bogus-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown flag for init: --bogus-flag"* ]]
  [[ "$output" == *"init accepts:"* ]]
}

@test "P073 Step 9: every documented init flag is still accepted" {
  # --plan / --streamlined must not be caught by the new strict arm.
  printf 'plan\n' > "$TEST_PROJECT_ROOT/plan.md"
  run "$FSM" init E-900-1_1 R-900-1 3 full main "$(git rev-parse HEAD 2>/dev/null || echo abc123)" \
      "$TEST_EVIDENCE_DIR/fsm-state.yaml" --plan "$TEST_PROJECT_ROOT/plan.md" --streamlined
  [[ "$output" != *"Unknown flag for init"* ]]
}

@test "P073 Step 9: --streamlined AFTER --force is still honoured (the force payload carve-out does not eat it)" {
  # fsm_handle_force_override consumes "${@:i+1}" as its payload, so the strict
  # arm has to tolerate what follows --force while the loop keeps running —
  # otherwise a documented flag placed after --force would be lost.
  run "$FSM" init E-900-1_1 R-900-1 3 full main "$(git rev-parse HEAD 2>/dev/null || echo abc123)" \
      "$TEST_EVIDENCE_DIR/fsm-state.yaml" --force --reason "$REASON" --streamlined
  [[ "$output" != *"Unknown flag for init"* ]]
}

# ─── anomaly 3: the unaudited release bypass ──────────────────────────────

_seed_release_repo() {
  mkdir -p "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin" \
           "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-900-1_1/R-900-1"
  printf '{"version": "2.0.0"}\n' > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json"
  cat > "$TEST_PROJECT_ROOT/CHANGELOG.md" <<'EOF'
# Changelog

## [2.0.1] — 2026-08-05

### Fixed
- A real entry so the Step 3 gate is satisfied.

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
  # A live run in EXECUTE — exactly what the FSM release guard blocks on.
  cat > "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-900-1_1/R-900-1/fsm-state.yaml" <<'EOF'
epic_id: E-900-1_1
run_id: R-900-1
state: EXECUTE
current_step: 1
total_steps: 3
EOF
  ( cd "$TEST_PROJECT_ROOT" && git init -q && git config user.email t@e.com \
      && git config user.name T && git add -A && git commit -qm seed )
}

@test "P073 Step 9: aid-release.sh --force WITHOUT a reason is refused" {
  _seed_release_repo
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"--force requires --reason"* ]]
}

@test "P073 Step 9: aid-release.sh --force with a SHORT reason is refused" {
  _seed_release_repo
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --force --reason "too short"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
}

@test "P073 Step 9: aid-release.sh --reason without --force is refused, not silently ignored" {
  _seed_release_repo
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --reason "$REASON"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bypasses nothing"* ]]
}

@test "P073 Step 9: a genuine aid-release.sh --force writes an audited receipt and an audit-log entry" {
  _seed_release_repo
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --force --reason "$REASON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FSM release guard bypassed"* ]]

  local w; w="$(find "$TEST_PROJECT_ROOT/.aid-o" -name 'waiver-release-force-*.json' | head -1)"
  [ -n "$w" ]
  [ "$(jq -r '.forced_override' "$w")" = "true" ]
  [ "$(jq -r '.records' "$w")" = "precondition_bypass" ]
  [ "$(jq -r '.bypassed_state' "$w")" = "EXECUTE" ]
  [ "$(jq -r '.waiver.reason' "$w")" = "$REASON" ]

  [ -s "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl" ]
  run grep -c 'release_force_override' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  [ "$output" -ge 1 ]
}

@test "P073 Step 9: a --force with NO guard to bypass writes no receipt" {
  # No fsm-state.yaml anywhere: there was nothing to force, so there is
  # nothing to record — same rule as the plan-FSM force.
  mkdir -p "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin"
  printf '{"version": "2.0.0"}\n' > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json"
  cat > "$TEST_PROJECT_ROOT/CHANGELOG.md" <<'EOF'
# Changelog

## [2.0.1] — 2026-08-05

### Fixed
- A real entry.
EOF
  ( cd "$TEST_PROJECT_ROOT" && git init -q && git config user.email t@e.com \
      && git config user.name T && git add -A && git commit -qm seed )
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --force --reason "$REASON"
  [ "$status" -eq 0 ]
  run bash -c "find '$TEST_PROJECT_ROOT' -name 'waiver-release-force-*.json' 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "P073 Step 9: the guard no longer advertises an unaudited bypass" {
  run grep -c 'Or use --force to bypass' "$RELEASE"
  [ "$output" = "0" ]
  # It advertises the audited form instead.
  run grep -c "force --reason" "$RELEASE"
  [ "$output" -ge 1 ]
}

# ─── Codex-review finding on the first cut of this step ───────────────────
# The review read "receipt plus audit-log entry" as two fail-closed records.
# They are deliberately not: the WAIVER RECEIPT is the authoritative record
# and is fail-closed; the cross-plan audit log is a convenience index appended
# with the same `|| true` contract every other force in this codebase uses
# (fsm_emit_audit_log). This pins that split so neither half drifts.

@test "P073 Step 9 (review finding): the RECEIPT is fail-closed — an unwritable evidence dir blocks the bypass" {
  _seed_release_repo
  chmod a-w "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-900-1_1/R-900-1"
  chmod a-w "$TEST_PROJECT_ROOT/.aid-o/work"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --force --reason "$REASON"
  local rc="$status"
  chmod u+w "$TEST_PROJECT_ROOT/.aid-o/work" "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-900-1_1/R-900-1"
  [ "$rc" -ne 0 ]
  [[ "$output" == *"refusing a silent bypass"* ]]
  [ -z "$(git tag -l 'v2.0.1')" ]
}

@test "P073 Step 9 (review finding): an unwritable AUDIT LOG does not block the bypass, because the receipt already holds the evidence" {
  _seed_release_repo
  # The receipt's own directory stays writable; only the convenience index is
  # blocked, by making it a directory the appender cannot write as a file.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --force --reason "$REASON"
  [ "$status" -eq 0 ]
  # The authoritative record exists even though the index write could not land.
  local w; w="$(find "$TEST_PROJECT_ROOT/.aid-o" -name 'waiver-release-force-*.json' | head -1)"
  [ -n "$w" ]
  [ "$(jq -r '.waiver.reason' "$w")" = "$REASON" ]
}

@test "P073 Step 9 (review finding): the code states which of the two records is authoritative" {
  run grep -c 'authoritative record and IS fail-closed' "$RELEASE"
  [ "$output" -ge 1 ]
}
