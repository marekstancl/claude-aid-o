#!/usr/bin/env bats
# test-invalidation-map.bats — E-057-2_2 Step 2 (E8 D3) behavioral red-green
# tests for scripts/lib/aid-invalidation-map.sh.
#
# The producer is observe-only: it derives affected_c1_checks[] (deterministic
# path-glob subset read from delivery-gate.yaml) and affected_c2_modes[]
# (conservative — any C2-relevant surface touched marks ALL canonical C2
# modes) from an applied fix's changed paths, emits invalidation-map.json +
# a timeline log_event, and MUST NOT trigger any re-run of delivery-gate or
# semantic-review.
#
# All fixtures run the REAL script (not a source grep). Policy files are
# test-local fixtures injected via DELIVERY_GATE_POLICY / REVIEW_PROFILE_POLICY
# (same env-override convention as test-fsm-dg07-observe.bats), so tests are
# independent of drift in the real defaults/policies/*.yaml content.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PRODUCER="$AID_PLUGIN_PATH/scripts/lib/aid-invalidation-map.sh"
  export PRODUCER
  export AID_TEST_MODE=1

  # ---- test-local delivery-gate.yaml: ONE check with changed_paths_match
  # (the deterministic C1 subset), ONE check with a non-path condition (out
  # of the deterministic subset, proving the producer only reads
  # changed_paths_match-declaring checks).
  DELIVERY_GATE_POLICY="$TEST_TMPDIR/delivery-gate-test.yaml"
  export DELIVERY_GATE_POLICY
  cat > "$DELIVERY_GATE_POLICY" <<'YAML'
version: 1
enforcement: observe
block_on_unverifiable: true
skip_reason_allowlist:
  - not_required
profiles:
  generic:
    detect: []
    commands: {}
checks:
  dg-lock:
    name: lockfile-consistency
    required_when:
      - changed_paths_match: ["package-lock.json", "yarn.lock"]
  dg-always:
    name: always-run
    required_when:
      - always: true
YAML

  # ---- test-local review-profiles.yaml: ONE C2-relevant surface (non-empty
  # lenses) matching scripts/**/*.sh, ONE non-C2 surface (empty lenses, e.g.
  # pure docs) so the "no C2 surface touched" fixture has something real to
  # not-match against.
  REVIEW_PROFILE_POLICY="$TEST_TMPDIR/review-profiles-test.yaml"
  export REVIEW_PROFILE_POLICY
  cat > "$REVIEW_PROFILE_POLICY" <<'YAML'
version: "1.0"
enforcement: observe
unknown_surface_profile: unverifiable
docs_allowlist:
  - "docs/**"
surfaces:
  scripts_core:
    match:
      path_globs:
        - "scripts/**/*.sh"
      content_signals: []
    risk: high
    lenses:
      - behavior_trace
    probes: []
  docs_content:
    match:
      path_globs:
        - "docs/**"
      content_signals: []
    risk: docs_trivial
    lenses: []
    probes: []
risk_profiles: {}
YAML
}

teardown() {
  unset DELIVERY_GATE_POLICY
  unset REVIEW_PROFILE_POLICY
  teardown_test_evidence_dir
}

_write_changed_paths() {
  local file="$TEST_TMPDIR/changed-paths.txt"
  printf '%s\n' "$@" > "$file"
  echo "$file"
}

# ---------------------------------------------------------------------------
# C1 deterministic subset — positive + negative control
# ---------------------------------------------------------------------------

@test "C1-glob-touching fixture (lockfile) -> affected_c1_checks non-empty" {
  local cp; cp="$(_write_changed_paths "package-lock.json")"

  run "$PRODUCER" --fix-ref "fix-lockfile-bump" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp"
  [ "$status" -eq 0 ]

  [ -f "$TEST_EVIDENCE_DIR/invalidation-map.json" ]
  local count
  count=$(jq '.invalidation_map.affected_c1_checks | length' "$TEST_EVIDENCE_DIR/invalidation-map.json")
  [ "$count" -gt 0 ]
  run jq -r '.invalidation_map.affected_c1_checks[]' "$TEST_EVIDENCE_DIR/invalidation-map.json"
  [[ "$output" == *"dg-lock"* ]]

  # non-path-condition check must NOT appear — deterministic subset only
  [[ "$output" != *"dg-always"* ]]
}

@test "fix outside all C1 globs -> affected_c1_checks empty" {
  local cp; cp="$(_write_changed_paths "docs/some-notes.md")"

  run "$PRODUCER" --fix-ref "fix-docs-only" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp"
  [ "$status" -eq 0 ]

  local count
  count=$(jq '.invalidation_map.affected_c1_checks | length' "$TEST_EVIDENCE_DIR/invalidation-map.json")
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# C2 conservative derivation — positive + negative control
# ---------------------------------------------------------------------------

@test "C2-touching fixture -> affected_c2_modes = all relevant modes (conservative)" {
  local cp; cp="$(_write_changed_paths "scripts/lib/some-lib.sh")"

  run "$PRODUCER" --fix-ref "fix-scripts-core" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp"
  [ "$status" -eq 0 ]

  run jq -c '.invalidation_map.affected_c2_modes | sort' "$TEST_EVIDENCE_DIR/invalidation-map.json"
  [ "$status" -eq 0 ]
  [ "$output" = '["behavior","final","local","wiring"]' ]
}

@test "fix outside all C2 surfaces -> affected_c2_modes empty" {
  local cp; cp="$(_write_changed_paths "docs/some-notes.md")"

  run "$PRODUCER" --fix-ref "fix-docs-only" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp"
  [ "$status" -eq 0 ]

  local count
  count=$(jq '.invalidation_map.affected_c2_modes | length' "$TEST_EVIDENCE_DIR/invalidation-map.json")
  [ "$count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# require_rerun flag — derived, not hardcoded
# ---------------------------------------------------------------------------

@test "require_rerun is true when something was flagged, false when nothing was" {
  local cp_touch; cp_touch="$(_write_changed_paths "package-lock.json")"
  run "$PRODUCER" --fix-ref "fix-touch" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp_touch"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.invalidation_map.require_rerun' "$TEST_EVIDENCE_DIR/invalidation-map.json")" = "true" ]

  local cp_notouch; cp_notouch="$(_write_changed_paths "docs/some-notes.md")"
  run "$PRODUCER" --fix-ref "fix-notouch" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp_notouch"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.invalidation_map.require_rerun' "$TEST_EVIDENCE_DIR/invalidation-map.json")" = "false" ]
}

# ---------------------------------------------------------------------------
# Timeline event
# ---------------------------------------------------------------------------

@test "producer writes an invalidation_map_produced timeline event" {
  local cp; cp="$(_write_changed_paths "scripts/lib/some-lib.sh")"

  run "$PRODUCER" --fix-ref "fix-timeline-check" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp"
  [ "$status" -eq 0 ]

  [ -f "$TEST_EVIDENCE_DIR/timeline.jsonl" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "invalidation_map_produced"

  # fix_ref must be echoed verbatim into the event
  run jq -se --arg ref "fix-timeline-check" 'any(.[]; .event == "invalidation_map_produced" and .fix_ref == $ref)' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  [ "$output" = "true" ]
}

# ---------------------------------------------------------------------------
# Observe-only: producer NEVER triggers delivery-gate / semantic-review
# ---------------------------------------------------------------------------

@test "producer does NOT invoke delivery-gate or semantic-review as a side effect" {
  local cp; cp="$(_write_changed_paths "package-lock.json" "scripts/lib/some-lib.sh")"

  run "$PRODUCER" --fix-ref "fix-observe-only" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp"
  [ "$status" -eq 0 ]

  # No delivery-gate.json / semantic-review-*.json artifact appeared as a
  # side effect of running the invalidation-map producer alone.
  [ ! -f "$TEST_EVIDENCE_DIR/delivery-gate.json" ]
  run bash -c "ls '$TEST_EVIDENCE_DIR'/semantic-review-*.json 2>/dev/null"
  [ -z "$output" ]

  # Static confirmation: the producer's source never shells out (bash/source/
  # exec/`) to the delivery-gate or gates dispatchers. Comment/docstring
  # lines mentioning these tool names by name (e.g. "MUST NOT invoke
  # aid-delivery-gate.sh") are excluded — only actual invocation syntax
  # counts as a violation here.
  run bash -c "grep -v '^[[:space:]]*#' '$PRODUCER' | grep -E '(bash|source|exec|\\\$\\()[^|]*(aid-delivery-gate\\.sh|aid-run-gates\\.sh)'"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Usage errors
# ---------------------------------------------------------------------------

@test "missing required args -> usage error (exit 1), no artifact written" {
  run "$PRODUCER" --evidence-dir "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [ ! -f "$TEST_EVIDENCE_DIR/invalidation-map.json" ]
}

@test "missing --changed-paths file -> usage error (exit 1)" {
  run "$PRODUCER" --fix-ref "fix-x" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$TEST_TMPDIR/does-not-exist.txt"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# protocol-v2 validity
# ---------------------------------------------------------------------------

@test "emitted invalidation-map.json passes aid-protocol-validate.sh" {
  local cp; cp="$(_write_changed_paths "package-lock.json")"
  run "$PRODUCER" --fix-ref "fix-protocol-check" --evidence-dir "$TEST_EVIDENCE_DIR" --changed-paths "$cp"
  [ "$status" -eq 0 ]

  run "$AID_PLUGIN_PATH/scripts/aid-protocol-validate.sh" "$TEST_EVIDENCE_DIR/invalidation-map.json"
  [ "$status" -eq 0 ]
}
