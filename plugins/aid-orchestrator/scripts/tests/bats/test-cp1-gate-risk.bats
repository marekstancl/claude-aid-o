#!/usr/bin/env bats
# aid-tier: t0
# test-cp1-gate-risk.bats — the ceremony band aid-cp1-gate.sh classifies a plan
# into (P084 Step 1).
#
# WHAT THIS SUITE IS ABOUT, AND WHAT IT IS NOT
#   Only the classification: which band a plan lands in, and why. The gate's
#   evidence/adjudicator/C0/ledger behaviour keeps living in
#   scripts/tests/test-cp1-gate.sh (t2, it needs git + ledger fixtures). Here
#   nothing is written, dispatched or committed — every case is a plan file in
#   a temp dir and one `--classify-only` run, which is what makes it t0.
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

@test "a plan touching tests/policies but no decision machinery is medium" {
  plan="$(write_plan P905 "risk: medium" \
    '- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-thing.bats` (tier: t0) — the thing
- Modify: `plugins/aid-orchestrator/defaults/policies/review-checkpoints.yaml` — a toggle')"
  [ "$(band_of "$plan")" = "medium" ]
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

@test "without a path map the gate falls back to the legacy document scan" {
  plan="$(write_plan P908 "risk: medium" \
    '- Modify: `plugins/aid-orchestrator/commands/aid-status.md` — describe the states' \
    'The state machine lives in aid-fsm.sh.')"
  mkdir -p "$TMP/empty-plugin"
  run env AID_PLUGIN_PATH="$TMP/empty-plugin" bash "$GATE" \
      --plan "$plan" --project-root "$TMP" --classify-only
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "full" ]]
  [[ "$output" == *"legacy_pattern_scan"* ]]
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
