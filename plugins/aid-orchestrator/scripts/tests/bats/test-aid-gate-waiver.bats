#!/usr/bin/env bats
# aid-tier: t1
# IMP-270 — Gate-scoped PM waiver.
#
# Three layers:
#   A. aid-gate-waiver.sh CLI    — issue / check / consume unit behavior
#   B. aid-run-gates.sh          — a failing required gate becomes result:waived
#                                  (never pass), overall stays pass, waived_gates[]
#   C. aid-fsm.sh GATES:DONE     — waived rows re-validate; non-waived fail blocks
#
# Backlog required negatives (all present below): one waiver cannot authorize a
# different gate / HEAD / run / command; a waived required gate stays visible in
# evidence; non-waived failures still block; replay of a single-use waiver is
# idempotent. Plus: expired, forged (hand-edited bound field), unknown gate at
# issue, reason <20 refused, unconsumed-overwrite refused.

setup() {
  export AID_TEST_MODE=1
  export AID_DEPLOY_DATE=2000-01-01
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WV="$PLUGIN_ROOT/scripts/aid-gate-waiver.sh"
  RG="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  FSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"

  PROJ="$TEST_TMPDIR/project"
  mkdir -p "$PROJ"
  cd "$PROJ"
  git init -q -b main
  git config user.email test@test.local
  git config user.name Test
  echo init > .gitkeep && git add .gitkeep && git commit -q -m initial
  HEAD_SHA=$(git rev-parse HEAD)

  mkdir -p .aid-o/config
  EXEC=".aid-o/config/execution.yaml"
  cat > "$EXEC" <<'YAML'
gates:
  bats_all:
    command: "exit 1"
    required: true
  plan_diff:
    command: "exit 0"
    required: false
YAML
  # sha256 of the raw bats_all command as stored in execution.yaml
  BATS_CMD_SHA=$(printf '%s' "exit 1" | sha256sum | cut -d' ' -f1)

  EV=".aid-o/work/evidence/E-1/R-1"
  mkdir -p "$EV/gates"
  REPORT="$EV/gates/gates_report.json"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# helper: issue a default valid waiver for bats_all in $EV
_issue_ok() {
  "$WV" issue bats_all --evidence-dir "$EV" \
    --reason 'bats_all deferred: CI image lacks bats runner, tracked in IMP' \
    --execution-yaml "$EXEC" "$@"
}

# helper: drive a fresh FSM state to GATES for E-1/R-1
_fsm_to_gates() {
  local sf="$EV/fsm-state.yaml"
  "$FSM" init E-1 R-1 1 manual main "$HEAD_SHA" "$sf" >/dev/null 2>&1
  sed -i 's/^state: .*/state: GATES/' "$sf"
  echo "$sf"
}

# ─── Layer A: CLI — issue ────────────────────────────────────────────────────

@test "issue: reason under 20 chars is refused" {
  run "$WV" issue bats_all --evidence-dir "$EV" --reason 'too short' --execution-yaml "$EXEC"
  [ "$status" -ne 0 ]
  [[ "$output" == *">=20 chars"* ]]
  [ ! -f "$EV/waivers/gate-waiver-bats_all.json" ]
}

@test "issue: unknown gate id is refused" {
  run "$WV" issue nonesuch --evidence-dir "$EV" \
    --reason 'a reason long enough to satisfy the min' --execution-yaml "$EXEC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown gate"* ]]
}

@test "issue: writes a well-formed waiver bound to gate/head/command" {
  _issue_ok
  local f="$EV/waivers/gate-waiver-bats_all.json"
  [ -f "$f" ]
  run jq -r '.gate_id' "$f";        [ "$output" = "bats_all" ]
  run jq -r '.artifact_type' "$f";  [ "$output" = "gate_waiver" ]
  run jq -r '.head_sha' "$f";       [ "$output" = "$HEAD_SHA" ]
  run jq -r '.command_sha256' "$f"; [ "$output" = "$BATS_CMD_SHA" ]
  run jq -r '.consumed.at' "$f";    [ "$output" = "null" ]
  run jq -e 'has("payload_sha256")' "$f"; [ "$status" -eq 0 ]
}

@test "issue: refuses to overwrite an existing UNCONSUMED waiver" {
  _issue_ok
  run "$WV" issue bats_all --evidence-dir "$EV" \
    --reason 'a second attempt with a long enough reason' --execution-yaml "$EXEC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to overwrite"* ]]
}

@test "issue: MAY overwrite an already-consumed waiver" {
  _issue_ok
  "$WV" consume bats_all --evidence-dir "$EV" --by-run R-1 >/dev/null
  run "$WV" issue bats_all --evidence-dir "$EV" \
    --reason 're-issue after the previous one was consumed' --execution-yaml "$EXEC"
  [ "$status" -eq 0 ]
  run jq -r '.consumed.at' "$EV/waivers/gate-waiver-bats_all.json"
  [ "$output" = "null" ]
}

# ─── Layer A: CLI — check (the required negatives) ────────────────────────────

@test "check: valid for the exact gate/head/command/run" {
  _issue_ok
  run "$WV" check bats_all --evidence-dir "$EV" --head "$HEAD_SHA" \
    --command-sha "$BATS_CMD_SHA" --epic E-1 --run R-1
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
}

@test "check: a DIFFERENT gate is not authorized (file missing)" {
  _issue_ok
  run "$WV" check plan_diff --evidence-dir "$EV" --head "$HEAD_SHA"
  [ "$status" -ne 0 ]
  [ "$output" = "missing" ]
}

@test "check: a DIFFERENT HEAD is rejected (head_mismatch)" {
  _issue_ok
  run "$WV" check bats_all --evidence-dir "$EV" \
    --head 0000000000000000000000000000000000000000 --command-sha "$BATS_CMD_SHA"
  [ "$status" -ne 0 ]
  [ "$output" = "head_mismatch" ]
}

@test "check: a DIFFERENT command is rejected (command_mismatch)" {
  _issue_ok
  run "$WV" check bats_all --evidence-dir "$EV" \
    --head "$HEAD_SHA" --command-sha deadbeefdeadbeef
  [ "$status" -ne 0 ]
  [ "$output" = "command_mismatch" ]
}

@test "check: a waiver copied into a DIFFERENT run is rejected (cross-run)" {
  _issue_ok
  local ev2=".aid-o/work/evidence/E-1/R-OTHER"
  mkdir -p "$ev2/waivers"
  cp "$EV/waivers/gate-waiver-bats_all.json" "$ev2/waivers/"
  run "$WV" check bats_all --evidence-dir "$ev2" --head "$HEAD_SHA" --command-sha "$BATS_CMD_SHA"
  [ "$status" -ne 0 ]
  [ "$output" = "forged" ]
}

@test "check: a hand-edited bound field is rejected (forged)" {
  _issue_ok
  local f="$EV/waivers/gate-waiver-bats_all.json"
  # flip reason without recomputing payload_sha256
  jq '.reason = "TAMPERED but still twenty+ chars long"' "$f" > "$f.x" && mv "$f.x" "$f"
  run "$WV" check bats_all --evidence-dir "$EV" --head "$HEAD_SHA" --run R-1
  [ "$status" -ne 0 ]
  [ "$output" = "forged" ]
}

@test "check: an expired waiver is rejected (expired)" {
  # expire 1 second in the... issue with a tiny window then wait is flaky; instead
  # issue then hand-set expires_at into the past AND re-sign so only expiry trips.
  _issue_ok
  local f="$EV/waivers/gate-waiver-bats_all.json"
  # rebuild payload_sha256 over the past-dated payload so integrity passes and
  # ONLY the expiry check fires (isolates the 'expired' verdict).
  local past="2000-01-01T00:00:00Z"
  local payload newhash
  payload=$(jq -c '.expires_at = "'"$past"'"
    | {schema_version,artifact_type,gate_id,project_id,epic_id,run_id,head_sha,command_sha256,authorized_by,reason,issued_at,expires_at,single_use}' "$f")
  newhash=$(printf '%s' "$payload" | jq -Sc '{schema_version,artifact_type,gate_id,project_id,epic_id,run_id,head_sha,command_sha256,authorized_by,reason,issued_at,expires_at,single_use}' | sha256sum | cut -d' ' -f1)
  jq --arg h "$newhash" --arg e "$past" '.expires_at=$e | .payload_sha256=$h' "$f" > "$f.x" && mv "$f.x" "$f"
  run "$WV" check bats_all --evidence-dir "$EV" --head "$HEAD_SHA" --command-sha "$BATS_CMD_SHA" --run R-1
  [ "$status" -ne 0 ]
  [ "$output" = "expired" ]
}

# ─── Layer A: CLI — consume + idempotent replay ──────────────────────────────

@test "consume: marks consumed once, replay returns already_consumed idempotently" {
  _issue_ok
  run "$WV" consume bats_all --evidence-dir "$EV" --by-run R-1
  [ "$status" -eq 0 ]
  [ "$output" = "consumed" ]
  run jq -r '.consumed.by_run' "$EV/waivers/gate-waiver-bats_all.json"
  [ "$output" = "R-1" ]
  # replay
  run "$WV" consume bats_all --evidence-dir "$EV" --by-run R-1
  [ "$status" -eq 0 ]
  [ "$output" = "already_consumed" ]
}

@test "check: a consumed single-use waiver is valid for ITS OWN run, consumed for others" {
  _issue_ok
  "$WV" consume bats_all --evidence-dir "$EV" --by-run R-1 >/dev/null
  # same run: self-consumption is acceptable evidence
  run "$WV" check bats_all --evidence-dir "$EV" --head "$HEAD_SHA" --command-sha "$BATS_CMD_SHA" --run R-1
  [ "$status" -eq 0 ]
  [ "$output" = "valid" ]
  # copied into another run: rejected as consumed
  local ev2=".aid-o/work/evidence/E-1/R-1"  # same path, override expected run
  run "$WV" check bats_all --evidence-dir "$EV" --head "$HEAD_SHA" --command-sha "$BATS_CMD_SHA" --run R-2
  [ "$status" -ne 0 ]
  # run mismatch trips the context (forged) check before consumed; either way rejected
  [[ "$output" == "forged" || "$output" == "consumed" ]]
}

# ─── Layer B: aid-run-gates.sh ───────────────────────────────────────────────

@test "run-gates: failing required gate with NO waiver → overall=fail" {
  run "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT"
  [ "$status" -ne 0 ]
  run jq -r '.overall' "$REPORT"; [ "$output" = "fail" ]
  run jq -r '.gates.bats_all.result' "$REPORT"; [ "$output" = "fail" ]
  run jq -c '.waived_gates' "$REPORT"; [ "$output" = "[]" ]
}

@test "run-gates: failing required gate with a VALID waiver → result waived, overall pass, visible, consumed" {
  _issue_ok
  run "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT"
  [ "$status" -eq 0 ]
  run jq -r '.overall' "$REPORT"; [ "$output" = "pass" ]
  # reported as waived, NEVER pass
  run jq -r '.gates.bats_all.result' "$REPORT"; [ "$output" = "waived" ]
  run jq -r '.gates.bats_all.waiver_ref' "$REPORT"; [ "$output" = "waivers/gate-waiver-bats_all.json" ]
  # visible top-level
  run jq -c '.waived_gates' "$REPORT"; [ "$output" = '["bats_all"]' ]
  # consumed by this run
  run jq -r '.consumed.by_run' "$EV/waivers/gate-waiver-bats_all.json"; [ "$output" = "R-1" ]
}

@test "run-gates: a waiver bound to a DIFFERENT command does not waive (waiver_rejected)" {
  _issue_ok
  # change the gate's command AFTER issuing → command fingerprint no longer matches
  cat > "$EXEC" <<'YAML'
gates:
  bats_all:
    command: "exit 3 # changed after waiver issued"
    required: true
  plan_diff:
    command: "exit 0"
    required: false
YAML
  run "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT"
  [ "$status" -ne 0 ]
  run jq -r '.overall' "$REPORT"; [ "$output" = "fail" ]
  run jq -r '.gates.bats_all.result' "$REPORT"; [ "$output" = "fail" ]
  run jq -r '.gates.bats_all.waiver_rejected' "$REPORT"; [ "$output" = "command_mismatch" ]
}

# ─── Layer C: aid-fsm.sh GATES:DONE ──────────────────────────────────────────

@test "fsm GATES:DONE: accepts a report whose required gate was validly waived" {
  _issue_ok
  "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT" >/dev/null 2>&1
  local sf; sf=$(_fsm_to_gates)
  run "$FSM" transition GATES DONE "$sf"
  [ "$status" -eq 0 ]
  run bash -c "grep '^state:' '$sf'"
  [[ "$output" == *"DONE"* ]]
}

@test "fsm GATES:DONE: rejects a waived row whose waiver was tampered (forged)" {
  _issue_ok
  "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT" >/dev/null 2>&1
  local sf; sf=$(_fsm_to_gates)
  # tamper a bound field of the (now consumed) waiver
  local f="$EV/waivers/gate-waiver-bats_all.json"
  jq '.head_sha = "1111111111111111111111111111111111111111"' "$f" > "$f.x" && mv "$f.x" "$f"
  run "$FSM" transition GATES DONE "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"waiver_revalidation_failed"* ]]
  run bash -c "grep '^state:' '$sf'"; [[ "$output" == *"GATES"* ]]
}

@test "fsm GATES:DONE: rejects a waived row when the waiver file is gone (missing)" {
  _issue_ok
  "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT" >/dev/null 2>&1
  local sf; sf=$(_fsm_to_gates)
  rm -f "$EV/waivers/gate-waiver-bats_all.json"
  run "$FSM" transition GATES DONE "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"waiver_revalidation_failed"* ]]
}

@test "fsm GATES:DONE: rejects a hand-forged report claiming waived with no waiver_ref" {
  # Build a report by hand: overall pass, bats_all result waived but NO waiver_ref.
  cat > "$REPORT" <<JSON
{
  "epic_id":"E-1","run_id":"R-1","overall":"pass",
  "gates":{"bats_all":{"gate":"bats_all","result":"waived","exit_code":1,"attempts":1}},
  "_generated_by":"aid-run-gates.sh@vtest",
  "revision":{"head_sha":"$HEAD_SHA"},
  "waived_gates":["bats_all"]
}
JSON
  local sf; sf=$(_fsm_to_gates)
  run "$FSM" transition GATES DONE "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"carries no waiver_ref"* ]]
}

@test "fsm GATES:DONE (IMP-270): a waived report with NO revision.head_sha is rejected, not validated against current HEAD" {
  _issue_ok
  "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT" >/dev/null 2>&1
  local sf; sf=$(_fsm_to_gates)
  # Strip the report's revision binding. HEAD has NOT moved, so the tool's
  # --head fallback would resolve the same (valid) HEAD and let the waiver pass.
  # The FSM must instead fail closed: a report that cannot name its revision is
  # untrusted regardless of what is currently checked out.
  jq 'del(.revision.head_sha)' "$REPORT" > "$REPORT.x" && mv "$REPORT.x" "$REPORT"
  run "$FSM" transition GATES DONE "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"revision.head_sha"* ]]
  run bash -c "grep '^state:' '$sf'"; [[ "$output" == *"GATES"* ]]
}

@test "fsm GATES:DONE (IMP-270): a waived report with a malformed revision.head_sha is rejected" {
  _issue_ok
  "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT" >/dev/null 2>&1
  local sf; sf=$(_fsm_to_gates)
  jq '.revision.head_sha = "not-a-sha"' "$REPORT" > "$REPORT.x" && mv "$REPORT.x" "$REPORT"
  run "$FSM" transition GATES DONE "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"revision.head_sha"* ]]
}

@test "fsm GATES:DONE: a non-waived required failure still blocks (overall=fail)" {
  # No waiver → overall fail → DONE must be refused.
  "$RG" run-all "$EXEC" E-1 R-1 --report-file "$REPORT" >/dev/null 2>&1 || true
  local sf; sf=$(_fsm_to_gates)
  run "$FSM" transition GATES DONE "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"overall=fail"* ]]
  run bash -c "grep '^state:' '$sf'"; [[ "$output" == *"GATES"* ]]
}
