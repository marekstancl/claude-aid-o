#!/usr/bin/env bats
# aid-tier: t0
# test-plan-telemetry.bats — plan-time events actually get written (P084 Step 7).
#
# THE FINDING THIS SUITE GUARDS
#   `.aid-o/work/timeline.jsonl` — the file /aid-init creates at the workspace
#   root — was 0 lines. Not a broken writer: every caller of log_event passes a
#   per-RUN path, and plan-time events (band classification, a lint that stopped
#   a plan) had no home at all because they happen before any run exists. They
#   now land under `evidence/<plan_id>/timeline.jsonl`, next to the plan's other
#   evidence.
#
# t0: text and JSONL only — no git, no dispatch, no network.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH="$PLUGIN_ROOT"
  GATE="$PLUGIN_ROOT/scripts/aid-cp1-gate.sh"
  LINT="$PLUGIN_ROOT/scripts/aid-plan-lint.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/.aid-o/work/evidence"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

write_plan() {
  local id="$1" path="$2" extra="${3:-}"
  local f="$TMP/${id}.md"
  cat > "$f" <<EOF
---
id: ${id}
type: plan
status: draft
lifecycle_strict: true
---

# Plan ${id}

## Testing Strategy

No new verification — this fixture exercises telemetry.

## Implementation Steps

### Step 1: the step

**Objective:** do it.

**Files:**
- Modify: \`${path}\` — the subject
${extra}
**Effort:** S
**AID Role:** backend
EOF
  printf '%s' "$f"
}

timeline_of() { printf '%s/.aid-o/work/evidence/%s/timeline.jsonl' "$TMP" "$1"; }

@test "AC21: the gate writes the band it classified and why" {
  plan="$(write_plan P960 'plugins/aid-orchestrator/commands/aid-help.md')"
  bash "$GATE" --plan "$plan" --project-root "$TMP" >/dev/null 2>&1
  tl="$(timeline_of P960)"
  [ -s "$tl" ]
  run jq -r 'select(.event == "cp1_band_classified") | .band + " " + .reason' "$tl"
  [[ "$output" == light* ]]
  run jq -r 'select(.event == "cp1_gate_result") | .result' "$tl"
  [ "$output" = "not_applicable" ]
}

@test "the classify-only path is recorded as such, not as a gate run" {
  plan="$(write_plan P961 'plugins/aid-orchestrator/scripts/aid-fsm.sh')"
  bash "$GATE" --plan "$plan" --project-root "$TMP" --classify-only >/dev/null 2>&1
  tl="$(timeline_of P961)"
  run jq -r 'select(.event == "cp1_band_classified") | .classify_only | tostring' "$tl"
  [ "$output" = "true" ]
  run jq -r 'select(.event == "cp1_gate_result") | .result' "$tl"
  [ -z "$output" ]
}

@test "AC21: the lint records that it stopped a plan, and on what" {
  # A strict, full-band plan whose step omits the band-scoped fields.
  plan="$(write_plan P962 'plugins/aid-orchestrator/scripts/aid-fsm.sh')"
  mkdir -p "$TMP/.aid-o/work/evidence/P962"
  run bash "$LINT" "$plan"
  [ "$status" -eq 1 ]
  tl="$(timeline_of P962)"
  run jq -r 'select(.event == "plan_lint_result") | "\(.band) \(.blocked) \(.strict)"' "$tl"
  [ "$output" = "full true 1" ]
}

@test "a clean plan is recorded as not blocked — the counter needs both outcomes" {
  plan="$(write_plan P963 'plugins/aid-orchestrator/commands/aid-help.md')"
  run bash "$LINT" "$plan"
  [ "$status" -eq 0 ]
  run jq -r 'select(.event == "plan_lint_result") | "\(.band) \(.blocked)"' "$(timeline_of P963)"
  [ "$output" = "light false" ]
}

@test "AC23: two writers appending to one plan timeline do not lose an event" {
  plan_a="$(write_plan P964 'plugins/aid-orchestrator/commands/aid-help.md')"
  bash "$GATE" --plan "$plan_a" --project-root "$TMP" --classify-only >/dev/null 2>&1 &
  bash "$LINT" "$plan_a" >/dev/null 2>&1 &
  wait
  tl="$(timeline_of P964)"
  # Both events present, and every line still parses as JSON.
  run jq -r 'select(.event == "cp1_band_classified") | .event' "$tl"
  [ -n "$output" ]
  run jq -r 'select(.event == "plan_lint_result") | .event' "$tl"
  [ -n "$output" ]
  run bash -c "jq -e . '$tl' >/dev/null"
  [ "$status" -eq 0 ]
}

@test "no workspace means no telemetry and no failure" {
  outside="$(mktemp -d)"
  cp "$(write_plan P965 'plugins/aid-orchestrator/commands/aid-help.md')" "$outside/P965.md"
  run bash "$LINT" "$outside/P965.md"
  [ "$status" -eq 0 ]
  [ ! -e "$outside/.aid-o" ]
  rm -rf "$outside"
}

@test "AC21: a gate that REFUSES records the outcome, not only the band" {
  # The outcome comes from an EXIT trap: a line written only on the two happy
  # paths would count exactly the runs nobody needs counted (codex review of
  # EPIC 2, finding 3).
  plan="$(write_plan P966 'plugins/aid-orchestrator/scripts/aid-fsm.sh')"
  run bash "$GATE" --plan "$plan" --project-root "$TMP"
  [ "$status" -eq 1 ]
  run jq -r 'select(.event == "cp1_gate_result") | "\(.result) \(.exit_code)"' "$(timeline_of P966)"
  [ "$output" = "fail 1" ]
}

@test "a quoted frontmatter id writes to the plan's real evidence dir" {
  # `id: "P967"` is valid YAML; the path must not contain the quotes (codex
  # review of EPIC 2, finding 5).
  plan="$(write_plan P967 'plugins/aid-orchestrator/commands/aid-help.md')"
  sed -i 's/^id: P967$/id: "P967"/' "$plan"
  run bash "$LINT" "$plan"
  [ "$status" -eq 0 ]
  [ -s "$(timeline_of P967)" ]
}

@test "an id that is not a plain identifier writes no telemetry at all" {
  plan="$(write_plan P968 'plugins/aid-orchestrator/commands/aid-help.md')"
  sed -i 's|^id: P968$|id: ../escaped|' "$plan"
  run bash "$LINT" "$plan"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/.aid-o/work/evidence/../escaped" ]
}
