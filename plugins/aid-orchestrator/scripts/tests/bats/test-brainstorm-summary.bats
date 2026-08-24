#!/usr/bin/env bats
# aid-tier: t1
#   MEASURED, not wished: each case runs the real artifact renderer, whose
#   secret scan costs ~2.5s per render — above the t0 per-case ceiling. Tier
#   follows the measurement, never the preference; it stays on the merge path.
# test-brainstorm-summary.bats — the PM's page about a brainstorm (P086 Step 9).
#
# TESTABILITY BOUNDARY, STATED EXPLICITLY
#   This renders a BODY and never publishes: the Artifact tool is a
#   session-level act owned by the controller, the same boundary
#   test-aid-plan-summary.bats and test-aid-artifact-render.bats both draw. The
#   renderer underneath has its own suite; what is proved HERE is this caller —
#   that every number comes from the run's files, that an absent vision is
#   named rather than left blank, and that a run nobody approved does not look
#   finished.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  BS="$PLUGIN_ROOT/scripts/aid-brainstorm-state.sh"
  TMP="$(mktemp -d)"
  ROOT="$TMP/project"
  mkdir -p "$ROOT/.aid-o/work"
  (
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    printf '.aid-o/\n' > .gitignore
    printf 'seed\n' > README.md
    git add -A && git commit -q -m seed
  )
  export AID_PROJECT_ROOT="$ROOT"
  export AID_PLUGIN_PATH="$PLUGIN_ROOT"
  RUN_DIR="$ROOT/.aid-o/work/brainstorm/P900"
  # Inside the run directory, because that is the only place an UNACCEPTED
  # run's page may be written — see the promotion boundary below.
  OUT="$RUN_DIR/brainstorm-summary-artifact.html"
  # shellcheck disable=SC1090
  source "$PLUGIN_ROOT/scripts/lib/aid-brainstorm-summary.sh"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

start_run() { bash "$BS" init P900 --scope "${1:-roadmap}" --topic "${2:-Hooks and two agents}" --no-worktree >/dev/null; }

approve_vision() {
  cat > "$TMP/vision.md" <<'V'
## Vision

- V1: Every rule AID enforces has a mechanism, not a sentence.
  - test: each enforcement row names a degree and a source.
- V2: A brainstorm ends in a page the PM can read in one sitting.
  - test: the page fits the artifact standard ceilings.
V
  bash "$BS" vision-propose P900 --file "$TMP/vision.md" >/dev/null
  bash "$BS" vision-approve P900 >/dev/null
}

dispute() { mkdir -p "$RUN_DIR"; printf '%s' "$1" > "$RUN_DIR/dispute.json"; }

@test "AC27: every number on the page is counted from the run, not asserted" {
  start_run
  approve_vision
  dispute '{"opponent":"answered","agree":[{"point":"a"},{"point":"b"},{"point":"c"}],"disagree":[{"point":"x"}],"missing":[],"to_pm":[{"point":"x"}],"held_back":0}'
  run aid_brainstorm_summary_render P900 "$OUT"
  [ "$status" -eq 0 ]
  [ -f "$OUT" ]
  grep -q "Vize: schválená, 2 bodů" "$OUT"
  grep -q "Oponent: odpověděl, 3 shod" "$OUT"
  grep -q "Sporů k rozhodnutí: 1" "$OUT"
}

@test "a run with no disputes renders no dispute line at all" {
  start_run
  approve_vision
  dispute '{"opponent":"answered","agree":[{"point":"a"}],"disagree":[],"missing":[],"to_pm":[],"held_back":0}'
  run aid_brainstorm_summary_render P900 "$OUT"
  [ "$status" -eq 0 ]
  # "0 disputes" and "no opponent ran" are different facts; a zero row answers
  # a question nobody asked.
  ! grep -q "Sporů k rozhodnutí" "$OUT"
}

@test "disputes held back from the PM are stated, not hidden" {
  start_run
  approve_vision
  dispute '{"opponent":"answered","agree":[],"disagree":[{"point":"a"},{"point":"b"},{"point":"c"},{"point":"d"},{"point":"e"},{"point":"f"},{"point":"g"}],"to_pm":[],"held_back":2}'
  run aid_brainstorm_summary_render P900 "$OUT"
  [ "$status" -eq 0 ]
  grep -q "Sporů k rozhodnutí: 7 (2 mimo tuto stránku)" "$OUT"
}

@test "AC29: a missing vision is named on the page, never left as a blank block" {
  start_run
  run aid_brainstorm_summary_render P900 "$OUT"
  [ "$status" -eq 0 ]
  grep -q "Vize: zatím žádná" "$OUT"
  grep -q "Oponent: zatím neběžel" "$OUT"
}

@test "a run that needs no vision says that, rather than reporting one missing" {
  start_run single_plan "One short plan"
  run aid_brainstorm_summary_render P900 "$OUT"
  [ "$status" -eq 0 ]
  grep -q "Vize: nevyžaduje se" "$OUT"
}

@test "an opponent that was never reached is on the page as a monologue" {
  start_run
  approve_vision
  dispute '{"opponent":"unreached","reason":"codex not on PATH","agree":[],"disagree":[],"missing":[]}'
  run aid_brainstorm_summary_render P900 "$OUT"
  [ "$status" -eq 0 ]
  grep -q "Oponent: nedostupný" "$OUT"
  grep -q "monologem" "$OUT"
}

@test "a run nobody accepted does not look finished" {
  start_run
  approve_vision
  run aid_brainstorm_summary_render P900 "$OUT"
  grep -q "Nedokončeno" "$OUT"

  bash "$BS" approve P900 >/dev/null
  run aid_brainstorm_summary_render P900 "$OUT"
  grep -q "Odsouhlaseno" "$OUT"
  ! grep -q "Nedokončeno" "$OUT"
}

@test "AC28: an unaccepted run's page may not be written outside its working directory" {
  # Otherwise "artifacts leave the working directory only once the PM accepts"
  # is a sentence the renderer walks past by being handed another path.
  start_run
  approve_vision
  run aid_brainstorm_summary_render P900 "$TMP/anywhere.html"
  [ "$status" -eq 1 ]
  [ ! -f "$TMP/anywhere.html" ]
  [[ "$output" == *"has not been accepted by the PM"* ]]
}

@test "AC28: once accepted, the page may be written anywhere" {
  start_run
  approve_vision
  aid_brainstorm_summary_render P900 "$OUT"
  bash "$BS" approve P900 >/dev/null
  run aid_brainstorm_summary_render P900 "$TMP/anywhere.html"
  [ "$status" -eq 0 ]
  [ -f "$TMP/anywhere.html" ]
}

@test "AC28: the vision reaches the plans directory only once the PM accepts the run" {
  start_run
  approve_vision
  aid_brainstorm_summary_render P900 "$OUT"
  [ ! -f "$ROOT/.aid-o/plans/P900-vision.md" ]
  run bash "$BS" approve P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted:"* ]]
  [ -f "$ROOT/.aid-o/plans/P900-vision.md" ]
}

@test "a run with no page for the PM to read cannot be accepted" {
  start_run
  approve_vision
  run bash "$BS" approve P900
  [ "$status" -eq 1 ]
  [[ "$output" == *"no rendered page"* ]]
  [ ! -f "$ROOT/.aid-o/plans/P900-vision.md" ]
}

@test "accepting a run that no opponent argued with says so out loud" {
  start_run
  approve_vision
  aid_brainstorm_summary_render P900 "$OUT"
  run bash "$BS" approve P900
  [ "$status" -eq 0 ]
  [[ "$output" == *"monologue"* ]]
}

@test "AC28: a run whose vision was never agreed cannot be accepted" {
  start_run
  run bash "$BS" approve P900
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a run to accept"* ]]
  [ ! -f "$ROOT/.aid-o/plans/P900-vision.md" ]
}

@test "there is nothing to render for a run that never started" {
  run aid_brainstorm_summary_render P999 "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no brainstorming run"* ]]
  [ ! -f "$OUT" ]
}
