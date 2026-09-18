#!/usr/bin/env bats
# aid-tier: t0
# test-cp1-gate-risk.bats — the ceremony band aid-cp1-gate.sh classifies a plan
# into (P084 Step 1).
#
# WHAT THIS SUITE IS ABOUT, AND WHAT IT IS NOT
#   Only the classification: which band a plan lands in, and why. What the
#   gate requires (plan-review round evidence, for every band) is asserted in
#   scripts/tests/bats/test-cp1-gate.bats. Here nothing is written, dispatched
#   or committed — every case is a plan file in a temp dir and one
#   `--classify-only` run, which is what makes it t0.
#
# The load-bearing distinction is prose vs declaration: before P084 the gate
# grepped the WHOLE document, so a plan that merely DESCRIBED the state machine
# was high-risk. The regression case below is exactly that shape.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
  GATE="$PLUGIN_ROOT/scripts/aid-cp1-gate.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

# write_plan <name> <frontmatter-risk-line|""> <files-block> [prose]
#   A plan file with exactly the two things the classifier reads — the
#   frontmatter and one **Files:** block — plus optional prose, which it must
#   NOT read.
write_plan() {
  local name="$1" risk_line="$2" files="$3" prose="${4:-}"
  {
    echo "---"
    echo "id: ${name}"
    echo "type: plan"
    [[ -n "$risk_line" ]] && echo "$risk_line"
    echo "---"
    echo ""
    echo "# Plan ${name}"
    echo ""
    echo "## Context"
    echo ""
    echo "${prose:-Nothing in particular.}"
    echo ""
    echo "## Implementation Steps"
    echo ""
    echo "### Step 1: do the thing"
    echo ""
    if [[ -n "$files" ]]; then
      echo "**Files:**"
      echo "$files"
    fi
  } > "$TMP/${name}.md"
  echo "$TMP/${name}.md"
}

band_of() {
  bash "$GATE" --plan "$1" --project-root "$TMP" --classify-only 2>/dev/null
}

reason_of() {
  bash "$GATE" --plan "$1" --project-root "$TMP" --classify-only 2>&1 >/dev/null
}

@test "AC1: a plan declaring scripts/aid-fsm.sh is full" {
  plan="$(write_plan P901 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — the state machine
- Modify: `CHANGELOG.md` — entry')"
  [ "$(band_of "$plan")" = "full" ]
  [[ "$(reason_of "$plan")" == *"full_path:plugins/aid-orchestrator/scripts/aid-fsm.sh"* ]]
}

@test "AC2: a plan declaring only commands/ and skills/ texts is light" {
  plan="$(write_plan P902 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — help text
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — protocol prose')"
  [ "$(band_of "$plan")" = "light" ]
}

@test "AC3: frontmatter risk: high raises a light plan to full" {
  plan="$(write_plan P903 "risk: high" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — help text')"
  [ "$(band_of "$plan")" = "full" ]
  [[ "$(reason_of "$plan")" == *"frontmatter_risk_high"* ]]
}

@test "AC4: release/ceremony files alone are not reach — the plan stays light" {
  plan="$(write_plan P904 "risk: medium" \
    '- Modify: `CHANGELOG.md` — entry
- Modify: `.claude-plugin/marketplace.json` — version
- Modify: `README.md` — roadmap line')"
  [ "$(band_of "$plan")" = "light" ]
  [[ "$(reason_of "$plan")" == *"only_excluded_paths"* ]]
}

@test "AC5: the hand-labelled reference set still agrees with the map" {
  run bash "$PLUGIN_ROOT/scripts/tests/check-classification-reference.sh" \
      "$REPO_ROOT/docs/plans/P084-classification-reference.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "a plan changing what a decision READS is medium; a test-only plan is light" {
  plan="$(write_plan P905 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/defaults/policies/review-checkpoints.yaml` — a toggle')"
  [ "$(band_of "$plan")" = "medium" ]
  # A test asserts a decision, it does not make one — and growing coverage is
  # meant to stay cheap (P081), so a test-only plan owes the checklist, not a
  # lens panel.
  tests_only="$(write_plan P905b "risk: medium" \
    '- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-thing.bats` (tier: t0) — the thing')"
  [ "$(band_of "$tests_only")" = "light" ]
}

@test "regression: prose about the state machine does not make a text plan full" {
  plan="$(write_plan P906 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-status.md` — describe the states' \
    'This plan explains how aid-fsm.sh transitions between states, how fsm-state
    is written, and how cmd_transition authorize()s the next state.')"
  [ "$(band_of "$plan")" = "light" ]
}

@test "a plan declaring no file at all is full, fail-closed" {
  plan="$(write_plan P907 "risk: medium" "")"
  [ "$(band_of "$plan")" = "full" ]
  [[ "$(reason_of "$plan")" == *"no_files_declared"* ]]
}

@test "without a path map the plan is full — never guessed from its prose" {
  # The replaced whole-document scan would have called this plan LOW risk (its
  # prose mentions the state machine but matches no pattern) while it declares
  # only a text file. A fallback that can answer `light` for a plan nobody could
  # classify is the one direction this gate must never take.
  plan="$(write_plan P908 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-status.md` — describe the states' \
    'The state machine lives in aid-fsm.sh.')"
  mkdir -p "$TMP/empty-plugin"
  run env AID_PLUGIN_PATH="$TMP/empty-plugin" bash "$GATE" \
      --plan "$plan" --project-root "$TMP" --classify-only
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "full" ]]
  [[ "$output" == *"no_risk_map"* ]]
}

@test "the classifier itself and the plan lint are full-band paths" {
  # A plan that rewrites the code deciding the ceremony must not be able to
  # classify its own change as cheap (codex review of EPIC 1, finding 2).
  plan="$(write_plan P914 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-band.sh` — the classifier
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-lint.sh` — the contract checker')"
  [ "$(band_of "$plan")" = "full" ]
}

@test "money and credential CODE is full-band; a document about it is not" {
  plan="$(write_plan P915 "risk: medium" \
    '- Modify: `src/billing/charge.py` — money
- Modify: `src/lib/auth_token.py` — credentials')"
  [ "$(band_of "$plan")" = "full" ]
  docs="$(write_plan P916 "risk: medium" \
    '- Create: `docs/security/review-2026-02.md` — the write-up')"
  [ "$(band_of "$docs")" = "light" ]
  # An ordinary request handler is NOT full: it is code, and code is reviewed
  # per step against a real diff.
  handler="$(write_plan P917 "risk: medium" \
    '- Create: `src/api/routes.py` — the endpoints')"
  [ "$(band_of "$handler")" = "light" ]
}

@test "a project may override the shipped path map" {
  plan="$(write_plan P909 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — help text')"
  mkdir -p "$TMP/.aid-o/config/policies"
  cat > "$TMP/.aid-o/config/policies/risk-paths.yaml" <<'YAML'
full_paths:
  - '(^|/)commands/[^/]+\.md$'
medium_paths: []
excluded_paths: []
YAML
  [ "$(band_of "$plan")" = "full" ]
}

# ─── the band no longer decides what a plan owes ────────────────────────────
# Every plan owes plan-review round evidence (P093); the round evidence itself
# is asserted in scripts/tests/bats/test-cp1-gate.bats.

@test "a light plan without round evidence fails the gate naming round-1" {
  mkdir -p "$TMP/.aid-o"
  plan="$(write_plan P910 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — help text')"
  [ "$(band_of "$plan")" = "light" ]
  run bash "$GATE" --plan "$plan" --project-root "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no plan review round-1"* ]]
}

# ─── fail-closed: the ways a classification can be WRONG rather than absent ──
#
# Each of these was a live fail-open found by the final cross-provider review:
# the map answers, but from information it knows is incomplete.

@test "a map that parses but names no full path is not an answer — full" {
  mkdir -p "$TMP/.aid-o/config/policies"
  printf 'full_paths: []\nmedium_paths: []\nexcluded_paths: []\n' \
    > "$TMP/.aid-o/config/policies/risk-paths.yaml"
  plan="$(write_plan P919 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — help text')"
  [ "$(band_of "$plan")" = "full" ]
  [[ "$(reason_of "$plan")" == *"empty_risk_map"* ]]
}

@test "a malformed regex in a project override is a map failure, not a non-match" {
  mkdir -p "$TMP/.aid-o/config/policies"
  printf 'full_paths:\n  - "scripts/[unclosed"\nmedium_paths: []\nexcluded_paths: []\n' \
    > "$TMP/.aid-o/config/policies/risk-paths.yaml"
  plan="$(write_plan P920 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — help text')"
  [ "$(band_of "$plan")" = "full" ]
  [[ "$(reason_of "$plan")" == *"bad_regex_in_risk_map"* ]]
}

@test "a non-canonical bullet still classifies from the path it does declare" {
  # `\`a\`, \`b\`` is a grammar error the LINT refuses; the gate must not answer
  # `light` just because the cleaner rejected the entry that named aid-fsm.sh.
  plan="$(write_plan P921 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh`, `docs/x.md` — comma list')"
  [ "$(band_of "$plan")" = "full" ]
  [[ "$(reason_of "$plan")" == *"full_path:plugins/aid-orchestrator/scripts/aid-fsm.sh"* ]]
}

@test "a bullet with no readable path at all fails the whole classification closed" {
  plan="$(write_plan P922 "risk: medium" \
    '- Modify: `path with spaces` — nothing usable
- Modify: `docs/x.md` — a real one')"
  [ "$(band_of "$plan")" = "full" ]
  [[ "$(reason_of "$plan")" == *"unparseable_files_entry"* ]]
}
