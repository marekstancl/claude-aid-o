#!/usr/bin/env bats
# test-aid-test-portfolio-analyst-focus.bats — P066 Step 9.
#
# test-portfolio-analyst.md is a prose agent card (LLM-facing instructions,
# not executable code) — the only mechanically-verifiable properties are
# structural/textual, matching how this repo treats other agent cards.
# Mirrors agents/auditor.md's audit_trigger.mode-absent precedent: no
# default fallback, an absent/unrecognized mode halts immediately.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CARD="$AID_PLUGIN_PATH/agents/test-portfolio-analyst.md"
}

teardown() {
  teardown_test_evidence_dir
}

@test "test-portfolio-analyst.md exists with the expected frontmatter" {
  [ -f "$CARD" ]
  run head -5 "$CARD"
  [[ "$output" == *"name: test-portfolio-analyst"* ]]
  [[ "$output" == *"model: sonnet"* ]]
}

@test "focus is documented as required with no default, and an absent/unrecognized value halts" {
  grep -q "never self-detect" "$CARD"
  grep -qi "no default fallback" "$CARD"
  grep -qi "halts immediately" "$CARD"
}

@test "all 6 focus enum values are named, each mapping to exactly one Step 10 prompt file" {
  local focuses=(shard_portfolio performance_cost flake_isolation parallel_safety adversarial_review consolidator)
  local f
  for f in "${focuses[@]}"; do
    grep -q "\`$f\`" "$CARD"
  done
  # Exactly 6 distinct focus values named in the mode-selection table — never
  # a 7th invented value, never fewer.
  local count
  count="$(grep -oE '`(shard_portfolio|performance_cost|flake_isolation|parallel_safety|adversarial_review|consolidator)`' "$CARD" | sort -u | wc -l)"
  [ "$count" -eq 6 ]
}

@test "constraints explicitly forbid editing/deleting/quarantining tests and touching execution.yaml" {
  grep -qi "MUST NOT edit" "$CARD"
  grep -qi "MUST NOT.*quarantine" "$CARD"
  grep -qi "execution.yaml" "$CARD"
}

@test "output contract references the real Step 1 wave-artifact schema, not an invented shape" {
  grep -q "test-audit-wave-artifact.schema.json" "$CARD"
}

@test "output contract lists schema_version as a required field (a document without it fails the real schema)" {
  # Regression: an earlier version enumerated the output shape without
  # schema_version, which the real schema requires (const "1.0.0") — an
  # agent following the card verbatim would produce an artifact the
  # controller's own schema check rejects, blocking the wave from advancing.
  grep -q '`schema_version`' "$CARD"
  local wave_schema="$AID_PLUGIN_PATH/defaults/schemas/test-audit-wave-artifact.schema.json"
  jq -e '.required | index("schema_version")' "$wave_schema" >/dev/null
}

@test "frontmatter matches this repo's real agent-card convention (name + model only, no invented fields)" {
  # Verified against gate-fixer.md/simplifier.md/reporter.md/curator.md — agent
  # cards carry only name+model, unlike skills/commands (which DO require
  # description/user_invocable). Agent cards are not a file type
  # aid-lint-skill.sh targets (it only classifies commands/ vs skill-shaped
  # files) — this asserts the REAL, observed sibling-file convention instead.
  run head -5 "$CARD"
  [[ "$output" == *"name: test-portfolio-analyst"* ]]
  [[ "$output" == *"model: sonnet"* ]]
  ! grep -q "^description:" <(head -5 "$CARD")
  ! grep -q "^user_invocable:" <(head -5 "$CARD")
}
