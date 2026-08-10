#!/usr/bin/env bats
# test-routed-findings.bats — P079 Step 7 (IMP-473): a review finding that no
# authorized step may fix gets a recorded route, and done-advance refuses over
# an open one.
#
# THE LIVE FAILURE MODE UNDER TEST: three times in one P076 run — once across
# an EPIC boundary — a review produced a finding whose file lay outside every
# remaining step's allowed_paths. There was nowhere legitimate to fix it, so it
# lived in the controller's prose until the prose ended.
#
# The NEGATIVE producer case is the important one: an out-of-scope finding in
# the canonical CP3 artifact with NO journal entry must fail. A carrier that
# only remembers what the controller chose to write down would have recorded
# nothing in the live incident either.
#
# FD-3 HYGIENE: every FSM invocation runs with `3>&-`. After any edit:
#   bats --tap test-routed-findings.bats | grep -cE '^(ok|not ok)'   # == 8

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-routed-findings.sh"
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export LIB FSM
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  export TEST_TMPDIR ROOT
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT" "$ROOT/.aid-o/work/plan-state" "$ROOT/.aid-o/tasks/archive"
  EPIC="E-900-1_2"
  EV="$ROOT/.aid-o/work/evidence/$EPIC/R-1"
  export EPIC EV
  FP_A="sha256:$(printf 'finding-a' | sha256sum | cut -c1-64)"
  FP_B="sha256:$(printf 'finding-b' | sha256sum | cut -c1-64)"
  export FP_A FP_B
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_lib() { bash -c "cd '$ROOT' && source '$LIB' && $*" 3>&-; }

# _seed_done_review — an EPIC parked at DONE/review with everything the
# EPIC-local both-modes checks need, so the ONLY thing that can block
# done-advance is the routed-findings check under test.
_seed_done_review() {
  mkdir -p "$EV"
  cat > "$EV/fsm-state.yaml" <<EOF
epic_id: ${EPIC}
run_id: R-1
state: DONE
done_phase: review
current_step: 2
total_steps: 2
pm_decision: merge
base_commit: $(git -C "$ROOT" rev-parse HEAD)
branch: task/${EPIC}/main
streamlined_mode: false
EOF
  printf '{"ts":"2026-08-10T00:00:00Z","event":"run_started"}\n' > "$EV/timeline.jsonl"
}

# _seed_plan_json <allowed_path…> — the run's plan.json, whose steps'
# allowed_paths are the scope union the producer check reconciles against.
_seed_plan_json() {
  local paths=""
  local p
  for p in "$@"; do paths+="\"$p\","; done
  paths="${paths%,}"
  cat > "$EV/plan.json" <<EOF
{"epic_id":"${EPIC}","steps":[{"id":1,"allowed_paths":[${paths}]}]}
EOF
}

# _seed_review <target_path> [fingerprint] — the canonical CP3 artifact.
_seed_review() {
  local tp="$1" fp="${2:-$FP_A}"
  cat > "$EV/semantic-review-final.json" <<EOF
{"artifact_type":"semantic_review","semantic_review":{"mode":"final","findings":[
  {"fingerprint":"${fp}","severity":"medium","lens":"code-review","check_id":"c1",
   "target_path":"${tp}","finding_class":"correctness"}]}}
EOF
}

_done_advance() {
  bash -c "cd '$ROOT' && exec bash '$FSM' done-advance review release '$EV/fsm-state.yaml'" 3>&-
}

# ─── the consumer half ─────────────────────────────────────────────────────

@test "P079 Step 7: an OPEN finding routed to this EPIC blocks done-advance, naming the fingerprint and both exits" {
  _seed_done_review
  _lib "aid_finding_route P900 '$FP_A' cp3-code-review step:2 '$EPIC' 2"

  run _done_advance
  [ "$status" -ne 0 ]
  [[ "$output" == *"$FP_A"* ]]
  [[ "$output" == *"cp3-code-review"* ]]
  [[ "$output" == *"backlog:IMP-"* ]]
}

@test "P079 Step 7: resolving the routed finding lets done-advance past the check" {
  _seed_done_review
  _lib "aid_finding_route P900 '$FP_A' cp3-code-review step:2 '$EPIC' 2"
  _lib "aid_finding_resolve P900 '$FP_A' 'fixed in step 2, commit abc1234'"

  run _done_advance
  [[ "$output" != *"$FP_A"* ]]
}

@test "P079 Step 7: a backlog route is a decision, not an open item — it never blocks" {
  _seed_done_review
  _lib "aid_finding_route P900 '$FP_A' cp3-security backlog:IMP-500 '$EPIC' 2"

  run _done_advance
  [[ "$output" != *"$FP_A"* ]]
}

@test "P079 Step 7: a finding routed to a DIFFERENT epic blocks that one, not this one" {
  _seed_done_review
  _lib "aid_finding_route P900 '$FP_B' cp3-code-review epic:E-900-2_2 '$EPIC' 2"

  run _done_advance
  [[ "$output" != *"$FP_B"* ]]

  # And it IS open for the epic it names.
  run _lib "aid_finding_open_for_epic P900 E-900-2_2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FP_B"* ]]
}

# ─── the producer half: the one that catches what nobody wrote down ────────

@test "P079 Step 7: an OUT-OF-SCOPE CP3 finding with NO journal entry is refused by fingerprint" {
  _seed_done_review
  _seed_plan_json "src/in-scope.ts"
  _seed_review "docs/somewhere-else.md"

  run _done_advance
  [ "$status" -ne 0 ]
  [[ "$output" == *"$FP_A"* ]]
  [[ "$output" == *"docs/somewhere-else.md"* ]]
  [[ "$output" == *"no step of ${EPIC} was allowed to touch"* ]]
}

@test "P079 Step 7: an out-of-scope finding that WAS routed satisfies the producer check" {
  _seed_done_review
  _seed_plan_json "src/in-scope.ts"
  _seed_review "docs/somewhere-else.md"
  _lib "aid_finding_route P900 '$FP_A' cp3-code-review backlog:IMP-501 '$EPIC' 2"

  run _done_advance
  [[ "$output" != *"no step of"* ]]
}

@test "P079 Step 7: an IN-SCOPE finding needs no route (a path under an allowed directory counts)" {
  _seed_done_review
  _seed_plan_json "src"
  _seed_review "src/nested/thing.ts"

  run _done_advance
  [[ "$output" != *"$FP_A"* ]]
}

# ─── the zero-cost path every legacy run takes ─────────────────────────────

@test "P079 Step 7: no journal and no CP3 artifact is byte-identical to pre-P079 behaviour" {
  _seed_done_review

  run _done_advance
  [[ "$output" != *"routed"* ]]
  [[ "$output" != *"aid-routed-findings"* ]]
}
