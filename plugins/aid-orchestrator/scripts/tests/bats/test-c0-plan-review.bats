#!/usr/bin/env bats
# test-c0-plan-review.bats — P065 E-065-7_7 Step 18 behavioral red-green tests
# for scripts/lib/aid-c0-plan-review.sh.
#
# aid-c0-plan-review.sh is the plan-time analogue of aid-c3-dispatch.sh: it
# runs a fresh isolated `codex exec` over the FINAL plan (before it is turned
# into EPICs) and emits a SEPARATE `c0-plan-review.json` artifact — never a C3
# audit-report. It reuses ONLY the C3 transport (_run_codex_isolated, sourced
# from aid-c3-dispatch.sh) — the artifact/schema/prompt/manifest are C0's own.
#
# This file owns its OWN fake-codex fixture (inline, written at setup() time)
# because the C0 raw-response shape (artifact_type/reviewed_plan_hash/
# reviewed_head/input_manifest_hash) is DIFFERENT from the existing C3
# fixtures/fake-codex stub (reviewed_head/codex_brief_hash) — reusing that
# fixture would silently test the wrong contract.

load test-helpers.bash

setup() {
  setup_test_evidence_dir "P900-c0-test" "root"
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c0-plan-review.sh"
  export DISPATCH
  VALIDATE="$AID_PLUGIN_PATH/scripts/aid-protocol-validate.sh"
  export VALIDATE

  # C0_EVIDENCE_DIR is the PLAN-ID evidence ROOT (.aid-o/work/evidence/<plan_id>/),
  # a directory ABOVE the epic/run leaf setup_test_evidence_dir created.
  C0_EVIDENCE_DIR="$(dirname "$TEST_EVIDENCE_DIR")"
  export C0_EVIDENCE_DIR

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'project_id: test-c0-proj\n' > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml"
  mkdir -p "$TEST_PROJECT_ROOT/defaults/schemas"
  printf '{"type":"object"}\n' > "$TEST_PROJECT_ROOT/defaults/schemas/example-contract.schema.json"

  PLAN_FILE="$TEST_PROJECT_ROOT/plan-low.md"
  cat > "$PLAN_FILE" <<'EOF'
---
id: P900-c0-test
title: A harmless low-risk plan
risk: low
---
# Plan

This plan touches only documentation. See `defaults/schemas/example-contract.schema.json`
for the contract it cites.
EOF

  PLAN_FILE_HIGH="$TEST_PROJECT_ROOT/plan-high.md"
  cat > "$PLAN_FILE_HIGH" <<'EOF'
---
id: P900-c0-test
title: A high-risk plan
risk: high
---
# Plan

This plan adds an authenticate() handler.
EOF

  git add plan-low.md plan-high.md .aid-o/config/project.yaml defaults/schemas/example-contract.schema.json
  git commit -q -m "seed plans"
  HEAD_SHA="$(git rev-parse HEAD)"
  export HEAD_SHA

  MANIFEST="$C0_EVIDENCE_DIR/c0/codex/audit-input-manifest.json"
  export MANIFEST
  REPORT="$C0_EVIDENCE_DIR/c0-plan-review.json"
  export REPORT
  DJSON="$C0_EVIDENCE_DIR/c0/codex/c0-dispatch.json"
  export DJSON

  # ── inline fake-codex fixture (C0 response shape) ─────────────────────────
  FAKE_C0_DIR="$TEST_TMPDIR/fake-codex-c0"
  mkdir -p "$FAKE_C0_DIR"
  cat > "$FAKE_C0_DIR/codex" <<'FAKECODEX'
#!/usr/bin/env bash
set -euo pipefail
for _a in "$@"; do
  if [ "$_a" = "--version" ]; then printf 'fake-codex-c0 0.0.0\n'; exit 0; fi
done

LAST_MSG_FILE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message|-o) LAST_MSG_FILE="${2:-}"; shift; [ "$#" -gt 0 ] && shift ;;
    --output-schema|--cd|-m|--model|-c|--sandbox) shift; [ "$#" -gt 0 ] && shift ;;
    *) shift ;;
  esac
done

MODE="${FAKE_C0_MODE:-valid}"
THREAD_ID="${FAKE_C0_THREAD_ID:-019f0000-0000-7000-8000-0000000c0fed}"

emit_thread_started() { jq -nc --arg tid "$THREAD_ID" '{type:"thread.started",thread_id:$tid}'; }
emit_turn_started()   { printf '%s\n' '{"type":"turn.started"}'; }
emit_agent_message()  { jq -nc --arg id "$1" --arg text "$2" '{type:"item.completed",item:{id:$id,type:"agent_message",text:$text}}'; }
emit_turn_completed() { printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'; }
write_last_message()  { [ -n "$LAST_MSG_FILE" ] && printf '%s\n' "$1" > "$LAST_MSG_FILE"; return 0; }

build_findings() { # $1 severity+owner mode: with_owner|no_owner|none
  case "$1" in
    with_owner)
      jq -nc '[{severity:"high",area:"feasibility",finding:"Named resource does not exist.",recommendation:"Add a Create step.",action_owner:"implementer"}]' ;;
    no_owner)
      jq -nc '[{severity:"high",area:"feasibility",finding:"Named resource does not exist.",recommendation:"Add a Create step."}]' ;;
    *)
      printf '[]' ;;
  esac
}

build_report() { # $1 plan_hash $2 head $3 imh $4 status $5 blocking $6 findings
  jq -nc --arg ph "$1" --arg head "$2" --arg imh "$3" --arg status "$4" --argjson blocking "$5" --argjson findings "$6" \
    '{artifact_type:"c0_plan_review", reviewed_plan_hash:$ph, reviewed_head:$head, input_manifest_hash:$imh,
      review_status:$status, blocking_findings:$blocking, findings:$findings}'
}

flip() { # single-hex-digit flip, sha256:/40-hex aware
  local v="$1"
  local prefix="" hex="$v"
  case "$v" in sha256:*) prefix="sha256:"; hex="${v#sha256:}" ;; esac
  local first="${hex:0:1}" rest="${hex:1}" flipped
  case "$first" in 0) flipped="1" ;; *) flipped="0" ;; esac
  printf '%s%s%s\n' "$prefix" "$flipped" "$rest"
}

case "$MODE" in
  valid)
    ph="${FAKE_C0_EXPECT_PLAN_HASH:-BAD}"; head="${FAKE_C0_EXPECT_HEAD:-BAD}"; imh="${FAKE_C0_EXPECT_IMH:-BAD}"
    findings="$(build_findings none)"
    report="$(build_report "$ph" "$head" "$imh" "pass" "false" "$findings")"
    emit_thread_started; emit_turn_started
    emit_agent_message "item_pre" "Reviewing the plan against the repo."
    emit_agent_message "item_final" "$report"
    emit_turn_completed
    write_last_message "$report"
    exit 0 ;;
  findings)
    ph="${FAKE_C0_EXPECT_PLAN_HASH:-BAD}"; head="${FAKE_C0_EXPECT_HEAD:-BAD}"; imh="${FAKE_C0_EXPECT_IMH:-BAD}"
    findings="$(build_findings with_owner)"
    report="$(build_report "$ph" "$head" "$imh" "findings" "true" "$findings")"
    emit_thread_started; emit_turn_started
    emit_agent_message "item_pre" "Reviewing the plan against the repo."
    emit_agent_message "item_final" "$report"
    emit_turn_completed
    write_last_message "$report"
    exit 0 ;;
  missing_action_owner)
    ph="${FAKE_C0_EXPECT_PLAN_HASH:-BAD}"; head="${FAKE_C0_EXPECT_HEAD:-BAD}"; imh="${FAKE_C0_EXPECT_IMH:-BAD}"
    findings="$(build_findings no_owner)"
    report="$(build_report "$ph" "$head" "$imh" "findings" "true" "$findings")"
    emit_thread_started; emit_turn_started
    emit_agent_message "item_final" "$report"
    emit_turn_completed
    write_last_message "$report"
    exit 0 ;;
  unverifiable)
    ph="${FAKE_C0_EXPECT_PLAN_HASH:-BAD}"; head="${FAKE_C0_EXPECT_HEAD:-BAD}"; imh="${FAKE_C0_EXPECT_IMH:-BAD}"
    report="$(jq -nc --arg ph "$ph" --arg head "$head" --arg imh "$imh" \
      '{artifact_type:"c0_plan_review", reviewed_plan_hash:$ph, reviewed_head:$head, input_manifest_hash:$imh,
        review_status:"unverifiable", unverifiable_reasons:["insufficient evidence to assess feasibility"],
        blocking_findings:false, findings:[]}')"
    emit_thread_started; emit_turn_started
    emit_agent_message "item_final" "$report"
    emit_turn_completed
    write_last_message "$report"
    exit 0 ;;
  hash_mismatch)
    ph="$(flip "${FAKE_C0_EXPECT_PLAN_HASH:-sha256:0000000000000000000000000000000000000000000000000000000000000000}")"
    head="${FAKE_C0_EXPECT_HEAD:-BAD}"; imh="${FAKE_C0_EXPECT_IMH:-BAD}"
    findings="$(build_findings none)"
    report="$(build_report "$ph" "$head" "$imh" "pass" "false" "$findings")"
    emit_thread_started; emit_turn_started
    emit_agent_message "item_final" "$report"
    emit_turn_completed
    write_last_message "$report"
    exit 0 ;;
  head_mismatch)
    ph="${FAKE_C0_EXPECT_PLAN_HASH:-BAD}"
    head="$(flip "${FAKE_C0_EXPECT_HEAD:-0000000000000000000000000000000000000000}")"
    imh="${FAKE_C0_EXPECT_IMH:-BAD}"
    findings="$(build_findings none)"
    report="$(build_report "$ph" "$head" "$imh" "pass" "false" "$findings")"
    emit_thread_started; emit_turn_started
    emit_agent_message "item_final" "$report"
    emit_turn_completed
    write_last_message "$report"
    exit 0 ;;
  c3_shaped)
    # A misbehaving model emits a C3 audit_report shape instead of the C0 shape.
    head="${FAKE_C0_EXPECT_HEAD:-BAD}"
    report="$(jq -nc --arg head "$head" \
      '{reviewed_head:$head, codex_brief_hash:"sha256:0000000000000000000000000000000000000000000000000000000000000000",
        review_status:"pass", blocking_findings:false, findings:[]}')"
    emit_thread_started; emit_turn_started
    emit_agent_message "item_final" "$report"
    emit_turn_completed
    write_last_message "$report"
    exit 0 ;;
  no_stream)
    ph="${FAKE_C0_EXPECT_PLAN_HASH:-BAD}"; head="${FAKE_C0_EXPECT_HEAD:-BAD}"; imh="${FAKE_C0_EXPECT_IMH:-BAD}"
    findings="$(build_findings none)"
    report="$(build_report "$ph" "$head" "$imh" "pass" "false" "$findings")"
    emit_thread_started
    emit_agent_message "item_final" "$report"
    # no turn.completed → events_valid fails
    write_last_message "$report"
    exit 0 ;;
  rate_limited)
    blob='{"status":429,"error":{"code":"rate_limit_exceeded","message":"Rate limit reached. Please try again later."}}'
    emit_thread_started; emit_turn_started
    jq -nc --arg m "$blob" '{type:"error",message:$m}'
    jq -nc --arg m "$blob" '{type:"turn.failed",error:{message:$m}}'
    exit 1 ;;
  timeout)
    sleep 3600
    exit 0 ;;
  *)
    printf 'fake-codex-c0: unknown FAKE_C0_MODE=%s\n' "$MODE" >&2
    exit 2 ;;
esac
FAKECODEX
  chmod +x "$FAKE_C0_DIR/codex"

  ORIGINAL_PATH="$PATH"
  export ORIGINAL_PATH

  # Independence pre-check spy — always "available" unless a test overrides it.
  INDEP_SPY="$TEST_TMPDIR/indep-spy-c0"
  mkdir -p "$INDEP_SPY"
  INDEP_LOG="$TEST_TMPDIR/indep-c0.log"; : > "$INDEP_LOG"
  export INDEP_LOG
  cat > "$INDEP_SPY/detect" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$INDEP_LOG"
exit 0
EOF
  chmod +x "$INDEP_SPY/detect"
  export AID_C0_INDEPENDENCE_BIN="$INDEP_SPY/detect"
}

teardown() {
  PATH="${ORIGINAL_PATH:-$PATH}"
  export PATH
  unset FAKE_C0_MODE FAKE_C0_EXPECT_PLAN_HASH FAKE_C0_EXPECT_HEAD FAKE_C0_EXPECT_IMH FAKE_C0_THREAD_ID
  unset AID_C0_FORCE_REVIEW AID_C0_INDEPENDENCE_BIN AID_CODEX_ISOLATED_TIMEOUT_SECONDS
  teardown_test_evidence_dir
}

_build_low() {
  run bash "$DISPATCH" build-manifest "$PLAN_FILE" "$C0_EVIDENCE_DIR"
}
_build_high() {
  run bash "$DISPATCH" build-manifest "$PLAN_FILE_HIGH" "$C0_EVIDENCE_DIR"
}

# _seed_dispatch_env — install the codex spy on PATH + coherent EXPECT_* envs
# from the already-built $MANIFEST.
_seed_dispatch_env() {
  PATH="$FAKE_C0_DIR:$PATH"; export PATH
  export FAKE_C0_EXPECT_PLAN_HASH="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_plan_hash' "$MANIFEST")"
  export FAKE_C0_EXPECT_HEAD="$(jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_head' "$MANIFEST")"
  export FAKE_C0_EXPECT_IMH="sha256:$(sha256sum "$MANIFEST" | awk '{print $1}')"
}

# ═══════════════════════════════════════════════════════════════════════════
# build-manifest
# ═══════════════════════════════════════════════════════════════════════════

@test "build-manifest: exits 0 and the manifest passes aid-protocol-validate.sh" {
  _build_low
  [ "$status" -eq 0 ]
  [ -f "$MANIFEST" ]
  run bash "$VALIDATE" "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "build-manifest: records reviewed_plan_hash / reviewed_head / plan_id / risk_profile" {
  _build_low
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_plan_hash' "$MANIFEST"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run jq -r '.audit_input_manifest.c0_plan_review_input.reviewed_head' "$MANIFEST"
  [ "$output" = "$HEAD_SHA" ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_id' "$MANIFEST"
  [ "$output" = "P900-c0-test" ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.risk_profile' "$MANIFEST"
  [ "$output" = "low" ]
}

@test "build-manifest: risk: high frontmatter is detected as high-risk" {
  _build_high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.risk_profile' "$MANIFEST"
  [ "$output" = "high" ]
}

@test "build-manifest: high-risk PATTERN in body (no frontmatter risk:) is still detected as high-risk" {
  PLAN_PATTERN="$TEST_PROJECT_ROOT/plan-pattern.md"
  cat > "$PLAN_PATTERN" <<'EOF'
---
id: P900-c0-test
title: pattern-triggered
---
# Plan
Adds a stripe billing integration.
EOF
  git add plan-pattern.md; git commit -q -m "add pattern plan"
  run bash "$DISPATCH" build-manifest "$PLAN_PATTERN" "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.risk_profile' "$MANIFEST"
  [ "$output" = "high" ]
}

@test "build-manifest: cited existing contract path is captured; a non-existent one is not" {
  PLAN_CONTRACTS="$TEST_PROJECT_ROOT/plan-contracts.md"
  cat > "$PLAN_CONTRACTS" <<'EOF'
---
id: P900-c0-test
risk: low
---
Cites defaults/schemas/example-contract.schema.json and
defaults/schemas/does-not-exist.schema.json (never created).
EOF
  git add plan-contracts.md; git commit -q -m "add contracts plan"
  run bash "$DISPATCH" build-manifest "$PLAN_CONTRACTS" "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.contracts | length' "$MANIFEST"
  [ "$output" = "1" ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.contracts[0]' "$MANIFEST"
  [ "$output" = "defaults/schemas/example-contract.schema.json" ]
}

@test "build-manifest: plan citing no contracts still lists plan + plan-graph + C0 evidence (empty contracts[])" {
  _build_high
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.contracts | length' "$MANIFEST"
  [ "$output" = "0" ]
  run jq -e '.audit_input_manifest.c0_plan_review_input.plan_graph.path' "$MANIFEST"
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.files | length'  "$MANIFEST"
  [ "$output" -ge 2 ]
}

@test "build-manifest: picks up existing cp1-deep lens files as C0 evidence" {
  mkdir -p "$C0_EVIDENCE_DIR/cp1-deep"
  printf 'stop_rule_blockers: []\n' > "$C0_EVIDENCE_DIR/cp1-deep/cp1-lens-L1-behavior.md"
  _build_low
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.c0_evidence | length' "$MANIFEST"
  [ "$output" -ge 1 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.c0_evidence[]' "$MANIFEST"
  [[ "$output" == *"cp1-lens-L1-behavior.md"* ]]
}

@test "build-manifest: missing 'id' frontmatter is a PRECONDITION FAIL (exit 1)" {
  PLAN_NOID="$TEST_PROJECT_ROOT/plan-noid.md"
  cat > "$PLAN_NOID" <<'EOF'
---
risk: low
---
No id field.
EOF
  git add plan-noid.md; git commit -q -m "add noid plan"
  run bash "$DISPATCH" build-manifest "$PLAN_NOID" "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch — risk gate
# ═══════════════════════════════════════════════════════════════════════════

@test "dispatch: low-risk plan is skipped WITHOUT invoking codex (outcome skipped(profile), exit 0)" {
  _build_low
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  CODEX_CALL_LOG="$TEST_TMPDIR/codex-call.log"
  # Overwrite PATH's codex entry with a canary that would fail the test if invoked.
  cat > "$FAKE_C0_DIR/codex" <<EOF
#!/usr/bin/env bash
echo "CALLED" >> "$CODEX_CALL_LOG"
exit 0
EOF
  chmod +x "$FAKE_C0_DIR/codex"
  run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$CODEX_CALL_LOG" ]
  [ -f "$REPORT" ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "skipped" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "skipped(profile)" ]
  # Independence pre-check must not have been probed either.
  [ ! -s "$INDEP_LOG" ]
}

@test "dispatch: AID_C0_FORCE_REVIEW forces Codex to run even on a low-risk plan" {
  _build_low
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_FORCE_REVIEW=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "dispatched" ]
  [ -s "$INDEP_LOG" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# dispatch — high-risk, real dispatch path
# ═══════════════════════════════════════════════════════════════════════════

@test "dispatch: high-risk + valid codex response → c0-plan-review.json pass, NOT an audit_report shape" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -f "$REPORT" ]

  run jq -r '.artifact_type' "$REPORT"; [ "$output" = "c0_plan_review" ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "pass" ]
  run jq -r '.blocking_findings' "$REPORT"; [ "$output" = "false" ]
  run jq -r '.reviewed_plan_hash' "$REPORT"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run jq -r '.reviewed_head' "$REPORT"; [ "$output" = "$HEAD_SHA" ]
  run jq -r '.input_manifest_hash' "$REPORT"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run jq -r '.codex.session_id' "$REPORT"
  [[ "$output" =~ ^[0-9a-f-]{36}$ ]]
  run jq -r '.codex.provider' "$REPORT"; [ "$output" = "codex" ]

  # NOT a C3 audit_report — neither key set nor artifact_type collide.
  run jq -r 'has("codex_brief_hash")' "$REPORT"
  [ "$output" = "false" ]
  run jq -r '.artifact_type != "audit_report"' "$REPORT"
  [ "$output" = "true" ]
}

@test "dispatch: high-risk + findings-with-owner response → blocking findings, fingerprinted, occurrence_id c0-<plan_id>-N" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "findings" ]
  run jq -r '.blocking_findings' "$REPORT"; [ "$output" = "true" ]
  run jq -r '.findings | length' "$REPORT"; [ "$output" = "1" ]
  run jq -r '.findings[0].occurrence_id' "$REPORT"; [ "$output" = "c0-P900-c0-test-0" ]
  run jq -r '.findings[0].fingerprint' "$REPORT"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run jq -r '.findings[0].action_owner' "$REPORT"; [ "$output" = "implementer" ]
}

@test "dispatch: high-risk + Codex-reported unverifiable → status unverifiable with reasons" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # NOTE (mirrors aid-c3-dispatch.sh's OWN contract, see its cmd_dispatch Step 9
  # comment): dispatch's EXIT CODE reflects whether Codex genuinely dispatched a
  # well-formed stream (transport-level), NOT whether the review content itself
  # was trustworthy — an honestly-unverifiable-but-well-formed response is still
  # exit 0; the untrustworthiness lives in c0-plan-review.json's own fields.
  FAKE_C0_MODE=unverifiable run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.unverifiable_reasons | length' "$REPORT"
  [ "$output" -ge 1 ]
}

@test "dispatch: high-risk + independence pre-check fails → unverifiable, exit 2, codex never invoked" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  cat > "$INDEP_SPY/detect" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "$INDEP_SPY/detect"
  CODEX_CALL_LOG="$TEST_TMPDIR/codex-call2.log"
  cat > "$FAKE_C0_DIR/codex" <<EOF
#!/usr/bin/env bash
echo "CALLED" >> "$CODEX_CALL_LOG"
exit 0
EOF
  chmod +x "$FAKE_C0_DIR/codex"
  run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  [ ! -f "$CODEX_CALL_LOG" ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "unavailable" ]
}

@test "dispatch: high-risk + codex timeout → unverifiable(timeout), exit 2" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_CODEX_ISOLATED_TIMEOUT_SECONDS=1 FAKE_C0_MODE=timeout run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "timeout" ]
}

@test "dispatch: high-risk + rate_limited → unverifiable(rate_limited), exit 2" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=rate_limited run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "rate_limited" ]
}

@test "dispatch: no_stream (missing turn.completed) → invalid_output unverifiable, exit 2" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=no_stream run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "invalid_output" ]
}

@test "dispatch: reviewed_plan_hash mismatch → hash_mismatch unverifiable" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=hash_mismatch run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "hash_mismatch" ]
}

@test "dispatch: reviewed_head mismatch → head_mismatch unverifiable" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=head_mismatch run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "head_mismatch" ]
}

@test "dispatch: a C3-shaped (audit_report) response is REJECTED by the C0 schema → invalid_output" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=c3_shaped run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "invalid_output" ]
}

@test "dispatch: missing action_owner on a high-severity finding → invalid_output" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=missing_action_owner run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "invalid_output" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# verify
# ═══════════════════════════════════════════════════════════════════════════

@test "verify: a genuinely dispatched, untampered review verifies clean (exit 0)" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == verified* ]]
}

@test "verify: --reference mode still verifies after HEAD moves; live mode fails stale" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Move HEAD forward.
  echo "more" >> "$PLAN_FILE_HIGH"
  git add plan-high.md
  git commit -q -m "advance head"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]

  run bash "$DISPATCH" verify --reference "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
}

@test "verify: a tampered finding (edited post-hoc) fails verify (exit 2)" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  tmp="$TEST_TMPDIR/tampered-report.json"
  jq '.findings[0].finding = "a different finding text than what codex actually reported"' "$REPORT" > "$tmp"
  mv "$tmp" "$REPORT"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "verify: fails closed when required artifacts are missing (no dispatch ever ran)" {
  _build_high
  [ "$status" -eq 0 ]
  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}
