#!/usr/bin/env bats
# aid-tier: t1
# =============================================================================
# test-gates-edge-matrix.bats — the edges the recorded runs never reached.
#
# WHY THIS FILE EXISTS: test-gates-replay.sh (t2) proves the rebuilt runner
# gives the recorded verdict on runs that really happened. Every one of those
# runs is a HAPPY path by construction — a project only keeps a gates report
# when the gates ran. The edges P097 actually changed (an unknown profile, a
# profile that can only skip, a dead key, a missing script, a timeout, a
# checkpointed row from another revision) appear in no report, so the replay
# can say nothing about them. This file is where each one is pinned, one case
# per edge, from the plan's own list.
#
# Each case asserts what the code DOES today. Where that is weaker than it
# should be, the case says so in a comment and names the gap — a test that
# quietly blesses a hole is worse than no test.
# =============================================================================

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$PROJECT/.aid-o/work/evidence/E-X/R-1/gates"
  cd "$PROJECT"
  git init -q -b main 2>/dev/null || git init -q
  git config user.email t@t.local
  git config user.name T
  echo init > .gitkeep && git add .gitkeep && git commit -q -m initial

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUN_GATES="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  YAML="$PROJECT/exec.yaml"
  REPORT="$PROJECT/.aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# _yaml <<<heredoc — write $YAML from stdin.
_yaml() { cat > "$YAML"; }

# _profiled — one required gate, one profile that includes it.
_profiled() {
  _yaml <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
default_profile: standard
gate_profiles:
  standard:
    include: ["alpha"]
YAML
}

# ─── 1. unknown profile ──────────────────────────────────────────────────────
@test "edge: an unknown --profile is refused with exit 2 and names the declared profiles" {
  _profiled
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT" --profile ghost
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown gate profile 'ghost'"* ]]
  [[ "$output" == *'["standard"]'* ]]        # the table, so the operator can pick
  [ ! -f "$REPORT" ]                          # refused BEFORE any gate ran
}

# ─── 2. a profile with no required gate ─────────────────────────────────────
@test "edge: a profile whose include[] carries no required gate is refused (exit 2)" {
  _yaml <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: false
default_profile: standard
gate_profiles:
  standard:
    include: ["alpha"]
YAML
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT" --profile standard
  [ "$status" -eq 2 ]
  [[ "$output" == *"includes no required gate"* ]]
  [ ! -f "$REPORT" ]
}

# ─── 3. a gate id in include[] that does not exist ──────────────────────────
@test "edge: include[] naming an undefined gate is refused (exit 1) and names the gate" {
  _yaml <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
default_profile: standard
gate_profiles:
  standard:
    include: ["alpha", "ghost"]
YAML
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT" --profile standard
  [ "$status" -eq 1 ]
  [[ "$output" == *"undefined gate 'ghost'"* ]]
  [ ! -f "$REPORT" ]
}

# ─── 4. missing script ──────────────────────────────────────────────────────
@test "edge: a gate whose script is not in the tree is fail/missing_script, never a pass" {
  _yaml <<'YAML'
gates:
  alpha:
    command: "bash scripts/not-here.sh"
    required: true
YAML
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.gates.alpha.status' "$REPORT")" = "fail" ]
  [ "$(jq -r '.gates.alpha.reason' "$REPORT")" = "missing_script" ]
  [ "$(jq -r '.overall' "$REPORT")" = "fail" ]
}

# ─── 5. timeout, with the process tree cleaned up ───────────────────────────
@test "edge: a timed-out COMPOUND command is job_timeout and leaves no child behind" {
  # A bare `sleep 30` would be exec'd by bash and killed directly, which proves
  # nothing about a tree. `<child>; true` forces a real bash parent with a
  # child, and `exec -a` gives the child a unique name pgrep can find, so a
  # surviving grandchild is visible after the runner has returned.
  local marker="aidedge$$"
  cat > "$YAML" <<YAML
gates:
  alpha:
    command: "bash -c 'exec -a ${marker}_child sleep 30'; true"
    required: true
    timeout_seconds: 2
YAML
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.gates.alpha.status' "$REPORT")" = "fail" ]
  [ "$(jq -r '.gates.alpha.reason' "$REPORT")" = "job_timeout" ]
  [ "$(jq -r '.gates.alpha.exit_code' "$REPORT")" = "124" ]
  sleep 1
  run pgrep -f "${marker}_child"
  [ "$status" -ne 0 ]                         # nothing of the tree survived
}

# ─── 6. invalid YAML ────────────────────────────────────────────────────────
@test "edge: an execution.yaml that does not parse is refused, not run half-way" {
  printf 'gates:\n  alpha:\n   command: "exit 0"\n  : : :\n' > "$YAML"
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not parse"* ]]
  [ ! -f "$REPORT" ]
}

# ─── 7. a duplicate gate id ─────────────────────────────────────────────────
@test "edge: a duplicated gate id resolves to the LAST definition and cannot report pass" {
  # KNOWN CEILING: yq takes the last of two identically-named keys and the
  # runner never sees the first, so a duplicate silently drops the earlier
  # (possibly stricter) definition instead of refusing the file. What IS
  # guaranteed, and what this case pins, is that the surviving definition is
  # really executed — the run cannot come out green because a duplicate
  # confused the counter. The refusal itself is a gap reported by P097 Step 8,
  # not something a test may invent.
  _yaml <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
  alpha:
    command: "exit 7"
    required: true
YAML
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.gates.alpha.status' "$REPORT")" = "fail" ]
  [ "$(jq -r '.gates.alpha.exit_code' "$REPORT")" = "7" ]
  [ "$(jq -r '.overall' "$REPORT")" = "fail" ]
  [ "$(jq -r '.gates._integrity // "absent"' "$REPORT")" = "absent" ]
}

# ─── 8. an empty command ────────────────────────────────────────────────────
@test "edge: an empty command is skip/no_command outside a profile, exit 1 inside one" {
  _yaml <<'YAML'
gates:
  alpha:
    command: ""
    required: false
  beta:
    command: "exit 0"
    required: true
YAML
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.gates.alpha.status' "$REPORT")" = "skip" ]
  [ "$(jq -r '.gates.alpha.reason' "$REPORT")" = "no_command" ]

  # The same gate NAMED BY A PROFILE is a configuration error, not a silent skip.
  _yaml <<'YAML'
gates:
  alpha:
    command: ""
    required: false
  beta:
    command: "exit 0"
    required: true
default_profile: standard
gate_profiles:
  standard:
    include: ["alpha", "beta"]
YAML
  rm -f "$REPORT"
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT" --profile standard
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no command"* ]]
  [ ! -f "$REPORT" ]
}

# ─── 9. an unwritable evidence directory ────────────────────────────────────
@test "edge: a report that cannot be written names the path, and leaves no report behind" {
  # KNOWN CEILING, reported by P097 Step 8 and NOT fixed here (this suite may
  # not change production code): the write failure is a raw redirect error and
  # the runner still returns the gate verdict's own exit code, so a caller that
  # only checks `$?` sees success. What stops a false green downstream is the
  # ABSENCE of the file — aid-plan-fsm.sh's plan-final stage refuses with
  # "produced no report" — which is exactly what this case pins.
  _yaml <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
YAML
  mkdir -p "$PROJECT/readonly"
  chmod 500 "$PROJECT/readonly"
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$PROJECT/readonly/gates_report.json"
  chmod 700 "$PROJECT/readonly"
  [ ! -f "$PROJECT/readonly/gates_report.json" ]
  [[ "$output" == *"readonly/gates_report.json"* ]]
  [[ "$output" == *"Permission denied"* ]]
}

# ─── 10. reused_from with a missing or hash-mismatched source row ───────────
@test "edge: a reuse row is taken only from a real earlier attempt whose definition still matches" {
  source "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  _yaml <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
YAML
  local runs="$PROJECT/.aid-o/work/evidence/P999"
  mkdir -p "$runs/R-P999-final-1" "$runs/R-P999-final-2"
  local head; head="$(git rev-parse HEAD)"

  # (a) MISSING source row: no attempt 1 report at all → nothing is reused.
  run _pfsm_gate_reuse_rows "$PROJECT" "$runs/R-P999-final-2" "$YAML" "$head" alpha
  [ "$status" -eq 0 ]
  [ "$(jq -r '.from' <<<"$output")" = "null" ]
  [ "$(jq -r '.rows | length' <<<"$output")" = "0" ]

  # (b) HASH-MISMATCHED source row: attempt 1 passed alpha, but under a
  # different gate definition. A row that did not run this definition is not
  # this definition's evidence.
  jq -n --arg h "$head" '{_generated_by:"aid-run-gates.sh@v2",
      revision:{head_sha:$h}, overall:"pass",
      gates:{alpha:{gate:"alpha", row_version:2, status:"pass", reason:"exit_0",
                    exit_code:0, duration_ms:1, started_at:null, completed_at:null,
                    evidence:null, required:true, waived:false, reused_from:null,
                    definition_sha256:"deadbeef"}}}' \
    > "$runs/R-P999-final-1/gates_report.json"
  run _pfsm_gate_reuse_rows "$PROJECT" "$runs/R-P999-final-2" "$YAML" "$head" alpha
  [ "$status" -eq 0 ]
  [ "$(jq -r '.rows | length' <<<"$output")" = "0" ]

  # (c) the control: the SAME definition is reused, so (b) failed on the hash
  # and not because reuse never works.
  local sha; sha="$(_pfsm_gate_definition_sha "$YAML" alpha)"
  jq --arg d "$sha" '.gates.alpha.definition_sha256 = $d' \
    "$runs/R-P999-final-1/gates_report.json" > "$runs/tmp.json"
  mv "$runs/tmp.json" "$runs/R-P999-final-1/gates_report.json"
  run _pfsm_gate_reuse_rows "$PROJECT" "$runs/R-P999-final-2" "$YAML" "$head" alpha
  [ "$(jq -r '.rows | length' <<<"$output")" = "1" ]
  [ "$(jq -r '.from' <<<"$output")" = "R-P999-final-1" ]
}

# ─── 11. a leftover services.json ───────────────────────────────────────────
@test "edge: a pre-2.103 services.json is reported once and otherwise ignored" {
  local ev="$PROJECT/.aid-o/work/evidence/E-X/R-1"
  printf '{"services":{"api":{"job_id":"j-1"}}}\n' > "$ev/services.json"

  # The note must have real callers — a function nothing calls would let this
  # case pass while a leftover registry went unmentioned in a live run.
  run grep -c '^\s*_fsm_pre_2103_services_note "' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  [ "$output" -ge 2 ]

  source "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  run _fsm_pre_2103_services_note "$ev" "edge-matrix"
  [ "$status" -eq 0 ]
  [[ "$output" == *"services.json is a service registry from a pre-2.103 run"* ]]
  [[ "$output" == *"ignored"* ]]

  # And the gate runner itself neither reads nor trips over it.
  _yaml <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
YAML
  run "$RUN_GATES" run-all "$YAML" E-X R-1 --report-file "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.overall' "$REPORT")" = "pass" ]
  [ -f "$ev/services.json" ]                  # untouched: nothing owns it now
}
