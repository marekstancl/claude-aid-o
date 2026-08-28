#!/usr/bin/env bats
# aid-tier: t0
# test-artifact-obligation.bats — a finished MILESTONE owes the PM a page
# (P086 Step 4, extended to three milestones by P089 Step 6).
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
  # A plan that OWES a page is one that can have one: since the rule asks the
  # renderer, a plan the renderer refuses owes nothing (see the case below).
  printf -- '---\nid: P900\ntype: plan\n---\n\n# Plan: fixture\n\n## Goal\n\nThe fixture has a goal, so it can be rendered.\n' > "$PLAN"
  # The milestone-2 and -3 cases call the checks directly; the Stop-rule cases
  # source the library in their own subshell, deliberately (see run_rule).
  # shellcheck disable=SC1090
  source "$PLUGIN_ROOT/scripts/lib/aid-artifact-obligation.sh"
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

@test "a plan the RENDERER refuses owes no page — enforcement must not require the impossible" {
  # Found live 2026-08-24: this rule demanded a page for a plan with no
  # `## Goal`, aid_plan_summary_render refused to produce one, and the session
  # was left with a finding nobody could act on.
  local nogoal="$ROOT/.aid-o/plans/P905-nogoal.md"
  printf -- '---\nid: P905\ntype: plan\n---\n\n# Plan: no goal\n\n## Context\n\nNothing.\n' > "$nogoal"
  run bash "$GATE" --plan "$nogoal"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot be rendered into a page"* ]]
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

@test "AC11: EPIC generation refuses a plan whose page was never rendered — the gate has a caller" {
  # The finding this test exists for: a gate nobody invokes is decoration. The
  # caller is aid-plan-to-epic.sh, at the point where a plan stops being a
  # document and becomes work.
  cat >> "$PLAN" <<'P'

## Implementation Steps

### Step 1: do the thing
**AID Role:** backend
P
  mkdir -p "$TMP/out"
  printf 'plan: 900\nepic: 0\n' > "$TMP/counter.yaml"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-to-epic.sh" --plan "$PLAN" --phase 1 --total 1 --epic-template "$PLUGIN_ROOT/defaults/templates/epic.md" --output-dir "$TMP/out" --counter-yaml "$TMP/counter.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no current PM page"* ]]
}

@test "the same generation proceeds past that check once the page is there" {
  cat >> "$PLAN" <<'P'

## Implementation Steps

### Step 1: do the thing
**AID Role:** backend
P
  render_page
  mkdir -p "$TMP/out"
  printf 'plan: 900\nepic: 0\n' > "$TMP/counter.yaml"
  run bash "$PLUGIN_ROOT/scripts/aid-plan-to-epic.sh" --plan "$PLAN" --phase 1 --total 1 --epic-template "$PLUGIN_ROOT/defaults/templates/epic.md" --output-dir "$TMP/out" --counter-yaml "$TMP/counter.yaml"
  # It may still fail further down for reasons this fixture does not satisfy —
  # what must not appear is the page refusal.
  [[ "$output" != *"no current PM page"* ]]
}

# ── The Stop rule: the same check, one turn earlier ────────────────────────
transcript() { # transcript <iso_timestamp> [plan_id...]
  # Since IMP-528 the rule only judges plans THIS session mentioned, so the
  # fixture transcript has to name them — exactly as a real session does the
  # moment it opens or renders one. Extra ids may be passed; the default names
  # the plan these cases use.
  printf '{"type":"user","timestamp":"%s","message":{"content":"go"}}\n' "$1" > "$TMP/transcript.jsonl"
  local _p
  for _p in "${@:2}"; do
    printf '{"type":"assistant","message":{"content":"pracuji na %s"}}\n' "$_p" >> "$TMP/transcript.jsonl"
  done
  [[ "$#" -gt 1 ]] || printf '{"type":"assistant","message":{"content":"pracuji na P900 P905"}}\n' >> "$TMP/transcript.jsonl"
  printf '%s' "$TMP/transcript.jsonl"
}

# The rule runs WITHOUT AID_PROJECT_ROOT: a hook gets its bearings from the
# event's cwd, and a test that leaves the override set would never exercise
# that. (The gate cases above do set it — they are invoked from bats' own cwd,
# which is a different checkout entirely.)
run_rule() { # run_rule <event_json>
  run env -u AID_PROJECT_ROOT bash -c "printf '%s' '$1' | bash -c 'source \"$PLUGIN_ROOT/scripts/lib/aid-artifact-obligation.sh\"; aid_hook_rule_milestone_artifact'"
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

# ── milestones 2 and 3: an EPIC's review, and a closed plan (P089 Step 6) ──

# _epic_run <done_phase> — a run state file at the layout the rule scans.
_epic_run() {
  mkdir -p "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A"
  cat > "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A/fsm-state.yaml" <<YAML
epic_id: E-900-1_1
run_id: R-A
state: DONE
branch: task/E-900-1_1/main
done_phase: ${1}
YAML
  printf '%s' "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A/fsm-state.yaml"
}
_epic_page() {
  mkdir -p "$ROOT/.aid-o/work/evidence/P900/E-900-1_1"
  printf '<h1>E-900-1_1</h1>\n' > "$ROOT/.aid-o/work/evidence/P900/E-900-1_1/epic-summary-artifact.html"
}

# _closed_plan <state> — a plan-state record at the layout the rule scans.
_closed_plan() {
  mkdir -p "$ROOT/.aid-o/work/plan-state/P900"
  printf 'plan_id: P900\nplan_state: %s\n' "${1}" \
    > "$ROOT/.aid-o/work/plan-state/P900/plan-state.yaml"
  printf '%s' "$ROOT/.aid-o/work/plan-state/P900/plan-state.yaml"
}
_close_page() {
  mkdir -p "$ROOT/.aid-o/work/evidence/P900/R-P900-final-1"
  printf '<h1>close</h1>\n' > "$ROOT/.aid-o/work/evidence/P900/R-P900-final-1/plan-close-artifact.html"
}

@test "AC16: a finished EPIC with no page stops the turn" {
  local sf; sf="$(_epic_run release)"
  run aid_artifact_obligation_epic_check "$ROOT" "$sf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"finished its review but its PM page was not rendered"* ]]
  [[ "$output" == *"P900/E-900-1_1/epic-summary-artifact.html"* ]]
}

@test "a finished EPIC with a current page passes" {
  local sf; sf="$(_epic_run release)"
  _epic_page
  run aid_artifact_obligation_epic_check "$ROOT" "$sf"
  [ "$status" -eq 0 ]
}

@test "an EPIC page older than the EPIC's own last commit is a finding" {
  local sf; sf="$(_epic_run release)"
  _epic_page
  # The branch the state file names, with a commit on it dated well after the
  # page — the EPIC moved after it was summarised.
  ( cd "$ROOT" && git checkout -q -b task/E-900-1_1/main \
      && printf 'x\n' > x.txt && git add x.txt && git commit -q -m "later work" \
      && git checkout -q main )
  touch -d "2019-01-01 00:00" "$ROOT/.aid-o/work/evidence/P900/E-900-1_1/epic-summary-artifact.html"
  run aid_artifact_obligation_epic_check "$ROOT" "$sf"
  [ "$status" -eq 1 ]
  [[ "$output" == *"posledního commitu EPICu"* ]]
}

@test "AC17: a run that has not finished its review owes nothing" {
  local sf; sf="$(_epic_run review)"
  run aid_artifact_obligation_epic_check "$ROOT" "$sf"
  [ "$status" -eq 3 ]
  [[ "$output" == *"has not finished its review"* ]]
}

@test "a closed plan with no closing page stops the turn" {
  local ps; ps="$(_closed_plan CLOSED)"
  run aid_artifact_obligation_close_check "$ROOT" "$ps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"was closed but its closing page was not rendered"* ]]
}

@test "a closed plan with its closing page passes, and the HIGHEST attempt is the one read" {
  local ps; ps="$(_closed_plan CLOSED)"
  _close_page
  mkdir -p "$ROOT/.aid-o/work/evidence/P900/R-P900-final-2"
  printf '<h1>close 2</h1>\n' > "$ROOT/.aid-o/work/evidence/P900/R-P900-final-2/plan-close-artifact.html"
  run aid_artifact_obligation_close_check "$ROOT" "$ps"
  [ "$status" -eq 0 ]
  run aid_artifact_obligation_close_page "$ROOT" P900
  [[ "$output" == *"R-P900-final-2"* ]]
}

@test "one touch on an old attempt does not make it the page that is read" {
  local ps; ps="$(_closed_plan CLOSED)"
  _close_page
  mkdir -p "$ROOT/.aid-o/work/evidence/P900/R-P900-final-2"
  printf '<h1>close 2</h1>\n' > "$ROOT/.aid-o/work/evidence/P900/R-P900-final-2/plan-close-artifact.html"
  # Attempt 1 is now the NEWEST file and still the wrong answer.
  touch "$ROOT/.aid-o/work/evidence/P900/R-P900-final-1/plan-close-artifact.html"
  run aid_artifact_obligation_close_page "$ROOT" P900
  [[ "$output" == *"R-P900-final-2"* ]]
}

@test "a plan that is still open owes no closing page" {
  local ps; ps="$(_closed_plan EPIC_INTEGRATION)"
  run aid_artifact_obligation_close_check "$ROOT" "$ps"
  [ "$status" -eq 3 ]
  [[ "$output" == *"is not closed"* ]]
}

@test "the Stop rule reports all three milestones, not only the plan" {
  render_page
  _epic_run release >/dev/null
  _closed_plan CLOSED >/dev/null
  local t; t="$(transcript "2020-01-01T00:00:00Z")"
  run_rule "{\"cwd\":\"$ROOT\",\"transcript_path\":\"$t\"}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"finished its review but its PM page was not rendered"* ]]
  [[ "$output" == *"was closed but its closing page was not rendered"* ]]
}

@test "AC18: the rule stays failure-closed in the registry, so the canary covers it" {
  run yq -r '.rules[] | select(.id == "milestone_artifact_rendered") | .failure' \
    "$PLUGIN_ROOT/defaults/hook-registry.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = "closed" ]
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

# ── corruption is not a way past an obligation (Codex, P089) ───────────────

@test "a finished review that names no usable EPIC id is a finding, not an exemption" {
  mkdir -p "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A"
  printf 'run_id: R-A\nstate: DONE\ndone_phase: release\n' \
    > "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A/fsm-state.yaml"
  run aid_artifact_obligation_epic_check "$ROOT" "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A/fsm-state.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"names no usable EPIC id"* ]]
}

@test "a CLOSED plan record that names no plan is a finding, not an exemption" {
  mkdir -p "$ROOT/.aid-o/work/plan-state/P900"
  printf 'plan_state: CLOSED\n' > "$ROOT/.aid-o/work/plan-state/P900/plan-state.yaml"
  run aid_artifact_obligation_close_check "$ROOT" "$ROOT/.aid-o/work/plan-state/P900/plan-state.yaml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"names no plan"* ]]
}

@test "a state value that merely STARTS with the milestone word does not activate the rule" {
  mkdir -p "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A" "$ROOT/.aid-o/work/plan-state/P900"
  printf 'epic_id: E-900-1_1\ndone_phase: release_pending\n' \
    > "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A/fsm-state.yaml"
  run aid_artifact_obligation_epic_check "$ROOT" "$ROOT/.aid-o/work/evidence/E-900-1_1/R-A/fsm-state.yaml"
  [ "$status" -eq 3 ]

  printf 'plan_id: P900\nplan_state: CLOSED_PENDING\n' \
    > "$ROOT/.aid-o/work/plan-state/P900/plan-state.yaml"
  run aid_artifact_obligation_close_check "$ROOT" "$ROOT/.aid-o/work/plan-state/P900/plan-state.yaml"
  [ "$status" -eq 3 ]
}

# --- IMP-528: a session is held only to the plans it worked on ------------
# PM, 2026-08-28: "potom mě to spamuje všechny okna a ne to který má". Several
# sessions share one workspace, so `find -newer` — a question about TIME — made
# every window liable for a plan edited in ANOTHER window.

@test "IMP-528: a plan this session never mentioned is not reported" {
  local ws="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$ws/.aid-o/plans" "$ws/.aid-o/work/evidence/P062" "$ws/.aid-o/work/evidence/P091"
  printf '{"timestamp":"2026-08-28T05:00:00Z"}\n{"text":"pracuju na P091"}\n' > "$ws/transcript.jsonl"
  for id in P062 P091; do
    printf -- "---\nid: %s\ntype: plan\n---\n# %s - x\n## Goal\nneco\n" "$id" "$id" > "$ws/.aid-o/plans/$id-x.md"
    echo "<html>x</html>" > "$ws/.aid-o/work/evidence/$id/plan-summary-artifact.html"
    touch -d "2026-08-27" "$ws/.aid-o/work/evidence/$id/plan-summary-artifact.html"
    touch -d "2026-08-28 12:00" "$ws/.aid-o/plans/$id-x.md"
  done
  ( cd "$ws" && git init -q . )

  run_rule "{\"cwd\":\"$ws\",\"transcript_path\":\"$ws/transcript.jsonl\"}"
  [[ "$output" == *"P091"* ]]
  [[ "$output" != *"P062"* ]]
}

@test "IMP-528: a transcript naming no plan reports nothing at all" {
  local ws="$BATS_TEST_TMPDIR/ws2"
  mkdir -p "$ws/.aid-o/plans" "$ws/.aid-o/work/evidence/P062"
  printf '{"timestamp":"2026-08-28T05:00:00Z"}\n{"text":"nic o planech"}\n' > "$ws/transcript.jsonl"
  printf -- "---\nid: P062\ntype: plan\n---\n# P062 - x\n## Goal\nneco\n" > "$ws/.aid-o/plans/P062-x.md"
  echo "<html>x</html>" > "$ws/.aid-o/work/evidence/P062/plan-summary-artifact.html"
  touch -d "2026-08-27" "$ws/.aid-o/work/evidence/P062/plan-summary-artifact.html"
  touch -d "2026-08-28 12:00" "$ws/.aid-o/plans/P062-x.md"
  ( cd "$ws" && git init -q . )

  run_rule "{\"cwd\":\"$ws\",\"transcript_path\":\"$ws/transcript.jsonl\"}"
  [[ "$output" != *"P062"* ]]
}
