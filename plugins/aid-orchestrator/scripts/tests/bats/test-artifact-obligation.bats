#!/usr/bin/env bats
# aid-tier: t0
# test-artifact-obligation.bats — a written plan owes the PM a page (P086 Step 4).
#
# THE GROUNDED FAILURE MODE: `commands/aid-plan.md` step 8p has asked sessions
# to render the page since P084 and said in its own text that nothing fails if
# they skip it. The enforcement registry carried `plan_artifact_rendered` as
# `planned` for exactly that reason. What is proved here is the mechanism that
# retires the word.
#
# WHY THE GATE MATTERS MORE THAN THE HOOK, and why both are tested: the `Stop`
# event does not exist in Codex's review modes and never arrives from a killed
# session — which is when a turn is most likely to have left the page
# un-rendered. The file check survives all of that; the hook only gets there
# first.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  GATE="$PLUGIN_ROOT/scripts/aid-turn-gate.sh"
  TMP="$(mktemp -d)"
  ROOT="$TMP/project"
  mkdir -p "$ROOT/.aid-o/plans" "$ROOT/.aid-o/work/evidence"
  (
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    printf '.aid-o/\n' > .gitignore
    git add -A && git commit -q -m seed
  )
  export AID_PROJECT_ROOT="$ROOT"
  PLAN="$ROOT/.aid-o/plans/P900-hooks.md"
  PAGE="$ROOT/.aid-o/work/evidence/P900/plan-summary-artifact.html"
  printf -- '---\nid: P900\ntype: plan\n---\n\n# Plan: fixture\n' > "$PLAN"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

render_page() {
  mkdir -p "$(dirname "$PAGE")"
  printf '<h1>P900</h1>\n' > "$PAGE"
}

@test "a plan with a current page passes" {
  render_page
  run bash "$GATE" --plan "$PLAN"
  [ "$status" -eq 0 ]
}

@test "AC11: a plan with no page is stopped, and the refusal names how to render it" {
  run bash "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PM page was not rendered"* ]]
  [[ "$output" == *"aid_plan_summary_render"* ]]
}

@test "a page older than its plan is a finding, not a quiet pass" {
  render_page
  touch -d "2020-01-01 00:00" "$PAGE"
  run bash "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"OLDER than the plan"* ]]
}

@test "a file that is not a numbered plan owes nothing" {
  local other="$ROOT/.aid-o/plans/IDEAS.md"
  printf 'notes\n' > "$other"
  run bash "$GATE" --plan "$other"
  [ "$status" -eq 0 ]
}

@test "a plan written and then deleted does not activate the rule" {
  rm -f "$PLAN"
  run bash "$GATE" --plan "$PLAN"
  [ "$status" -eq 0 ]
}

# ── The Stop rule: the same check, one turn earlier ────────────────────────
transcript() { # transcript <iso_timestamp>
  printf '{"type":"user","timestamp":"%s","message":{"content":"go"}}\n' "$1" > "$TMP/transcript.jsonl"
  printf '%s' "$TMP/transcript.jsonl"
}

# The rule runs WITHOUT AID_PROJECT_ROOT: a hook gets its bearings from the
# event's cwd, and a test that leaves the override set would never exercise
# that. (The gate cases above do set it — they are invoked from bats' own cwd,
# which is a different checkout entirely.)
run_rule() { # run_rule <event_json>
  run env -u AID_PROJECT_ROOT bash -c "printf '%s' '$1' | bash -c 'source \"$PLUGIN_ROOT/scripts/lib/aid-artifact-obligation.sh\"; aid_hook_rule_plan_artifact'"
}

@test "the Stop rule refuses a session that wrote a plan and no page" {
  local t; t="$(transcript "2020-01-01T00:00:00Z")"
  run_rule "{\"cwd\":\"$ROOT\",\"transcript_path\":\"$t\"}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"PM page was not rendered"* ]]
}

@test "the Stop rule passes when the page is there" {
  render_page
  local t; t="$(transcript "2020-01-01T00:00:00Z")"
  run_rule "{\"cwd\":\"$ROOT\",\"transcript_path\":\"$t\"}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"current PM page"* ]]
}

@test "the Stop rule judges only plans this session wrote" {
  # The plan predates the session — an un-rendered plan from last month must
  # not refuse every turn from now on.
  touch -d "2019-01-01 00:00" "$PLAN"
  local t; t="$(transcript "2020-01-01T00:00:00Z")"
  run_rule "{\"cwd\":\"$ROOT\",\"transcript_path\":\"$t\"}"
  [ "$status" -eq 3 ]
}

@test "the Stop rule declines rather than guessing when the session start is unknown" {
  printf '{"type":"user","message":{"content":"go"}}\n' > "$TMP/no-ts.jsonl"
  run_rule "{\"cwd\":\"$ROOT\",\"transcript_path\":\"$TMP/no-ts.jsonl\"}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no start timestamp"* ]]
}

@test "the Stop rule outside an AID workspace is not applicable" {
  local t; t="$(transcript "2020-01-01T00:00:00Z")"
  run_rule "{\"cwd\":\"$TMP\",\"transcript_path\":\"$t\"}"
  [ "$status" -eq 3 ]
}
