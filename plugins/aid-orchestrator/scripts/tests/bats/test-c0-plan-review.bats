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
  LEDGER="$AID_PLUGIN_PATH/scripts/lib/aid-cp1-ledger.sh"
  export LEDGER

  # C0_EVIDENCE_DIR is the PLAN-ID evidence ROOT (.aid-o/work/evidence/<plan_id>/),
  # a directory ABOVE the epic/run leaf setup_test_evidence_dir created.
  C0_EVIDENCE_DIR="$(dirname "$TEST_EVIDENCE_DIR")"
  export C0_EVIDENCE_DIR

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'project_id: test-c0-proj\n' > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml"
  mkdir -p "$TEST_PROJECT_ROOT/defaults/schemas"
  printf '{"type":"object"}\n' > "$TEST_PROJECT_ROOT/defaults/schemas/example-contract.schema.json"

  # Initialize the CP1 ledger for plan P900-c0-test (used by all tests in this suite).
  # This is needed for Finding 1 fix: cmd_dispatch now calls ledger increment on every
  # genuine dispatch, so tests that dispatch must have a ledger ready.
  bash "$LEDGER" init --pre-enforcement --project-root "$TEST_PROJECT_ROOT" "P900-c0-test" >/dev/null 2>&1 || true

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

# _write_c0_override [pm_ref] [plan_id] — writes a genuine, claimable
# cp1-pm-escalation-override.json for the given plan_id (default
# P900-c0-test, this file's fixed test plan) at the exact path
# aid-cp1-ledger.sh's claim-pm-override subcommand reads. 9th DONE-review
# audit fix: the bounded-loop override is no longer a bare env var — it
# must be a real, single-use artifact.
_write_c0_override() {
  local pm_ref="${1:-PM approved this specific bypass, 2026-07-20 review}"
  local plan_id="${2:-P900-c0-test}"
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${plan_id}"
  mkdir -p "$dir"
  jq -nc --arg r "$pm_ref" '{pm_ref: $r}' > "$dir/cp1-pm-escalation-override.json"
}

# _revise_plan_high <marker> — appends a unique line to PLAN_FILE_HIGH,
# commits it, rebuilds the manifest, and re-seeds the dispatch env. Used to
# give successive attempts a genuinely DIFFERENT reviewed_plan_hash (7th/8th
# DONE-review audit fix: the same-hash re-dispatch guard now applies in
# BOTH legacy and attempt-explicit mode, so tests that legitimately need
# multiple genuine dispatches — attempt-directory structure, verify,
# loop-summary accumulation, escalation detection — must revise the plan
# between attempts, exactly like a real bounded-review loop iteration
# would). The FAKE_C0_MODE codex spy's canned response content does not
# depend on plan content, so this does not change what Codex "reports" —
# only the plan_hash the ledger/guard see, which is the point.
_revise_plan_high() {
  local marker="$1"
  printf '\n<!-- revision: %s -->\n' "$marker" >> "$PLAN_FILE_HIGH"
  git -C "$TEST_PROJECT_ROOT" add plan-high.md
  git -C "$TEST_PROJECT_ROOT" commit -q -m "revise plan-high.md ($marker)"
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
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
  # P068 Step 1: with no plan-graph.json on disk (the pre-generation case this
  # fixture is in), plan_graph is the STATUS STRING, not a zero-byte seal.
  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph' "$MANIFEST"
  [ "$output" = "absent_pre_generation" ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.files | length'  "$MANIFEST"
  [ "$output" -ge 1 ]
}

# ─── P068 Step 1 (CF3 refinement): the plan_graph manifest entry ───────────
#
# The blocking half of CF3 was already resolved in code before this step (an
# absent input was sealed rather than failing), so these tests assert the
# SEMANTIC improvement on the bridge, never a review verdict: a review can be
# `unverifiable` for unrelated reasons (provider availability), so its status
# is not a deterministic signal.

@test "build-manifest: absent plan-graph is recorded as absent_pre_generation, NOT a zero-byte seal" {
  _build_low
  [ "$status" -eq 0 ]

  # The empty-file sha256 — the exact opaque value this step removes.
  local empty_sha="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph | type' "$MANIFEST"
  [ "$output" = "string" ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph' "$MANIFEST"
  [ "$output" = "absent_pre_generation" ]

  # No phantom zero-byte plan-graph entry survives anywhere in the sealed set,
  # and the allowlist does not offer a file that does not exist.
  run jq -r --arg e "$empty_sha" \
    '[.audit_input_manifest.c0_plan_review_input.files[] | select(.path | test("plan-graph\\.json$"))] | length' "$MANIFEST"
  [ "$output" = "0" ]
  run jq -r '[.audit_input_manifest.allowlist[] | select(test("plan-graph\\.json$"))] | length' "$MANIFEST"
  [ "$output" = "0" ]
}

@test "build-manifest: a PRESENT plan-graph is sealed and hashed exactly as before (object with path/sha256/size)" {
  mkdir -p "$C0_EVIDENCE_DIR/c0"
  printf '{"artifact_type":"plan_graph"}\n' > "$C0_EVIDENCE_DIR/c0/plan-graph.json"
  _build_low
  [ "$status" -eq 0 ]

  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph | type' "$MANIFEST"
  [ "$output" = "object" ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph.path' "$MANIFEST"
  [[ "$output" == *"c0/plan-graph.json" ]]
  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph.sha256' "$MANIFEST"
  [[ "$output" =~ ^sha256:[0-9a-f]{64}$ ]]
  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph.size' "$MANIFEST"
  [ "$output" -gt 0 ]

  # Present ⇒ it IS part of the hashed set and the allowlist again.
  run jq -r '[.audit_input_manifest.c0_plan_review_input.files[] | select(.path | test("plan-graph\\.json$"))] | length' "$MANIFEST"
  [ "$output" = "1" ]
}

@test "build-manifest: provisional source graph must bind to the reviewed plan bytes" {
  mkdir -p "$C0_EVIDENCE_DIR/generation"
  local plan_sha
  plan_sha="sha256:$(sha256sum "$PLAN_FILE" | awk '{print $1}')"
  jq -n --arg sha "$plan_sha" '{schema:"aid-source-plan-graph/v1",plan_sha256:$sha,steps:[],edges:[],topological_order:["step-1"],cycles:[]}' \
    > "$C0_EVIDENCE_DIR/generation/provisional-graph.json"
  _build_low
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.source_plan_graph.path' "$MANIFEST"
  [[ "$output" == *"generation/provisional-graph.json" ]]

  # A graph forged for different plan bytes must fail before it becomes a
  # sealed C0 input; valid JSON alone is not authority.
  jq '.plan_sha256="sha256:deadbeef"' "$C0_EVIDENCE_DIR/generation/provisional-graph.json" > "$C0_EVIDENCE_DIR/generation/tampered.json"
  mv "$C0_EVIDENCE_DIR/generation/tampered.json" "$C0_EVIDENCE_DIR/generation/provisional-graph.json"
  run bash "$DISPATCH" build-manifest "$PLAN_FILE" "$C0_EVIDENCE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"provisional plan graph hash does not match"* ]]
}

@test "build-manifest: source graph and per-EPIC graph remain distinct sealed inputs" {
  mkdir -p "$C0_EVIDENCE_DIR/c0" "$C0_EVIDENCE_DIR/generation"
  local plan_sha
  plan_sha="sha256:$(sha256sum "$PLAN_FILE" | awk '{print $1}')"
  printf '{"artifact_type":"plan_graph"}\n' > "$C0_EVIDENCE_DIR/c0/plan-graph.json"
  jq -n --arg sha "$plan_sha" '{schema:"aid-source-plan-graph/v1",plan_sha256:$sha,steps:[],edges:[],topological_order:[],cycles:[]}' \
    > "$C0_EVIDENCE_DIR/generation/provisional-graph.json"

  _build_low
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_graph.path' "$MANIFEST"
  [[ "$output" == *"c0/plan-graph.json" ]]
  run jq -r '.audit_input_manifest.c0_plan_review_input.source_plan_graph.path' "$MANIFEST"
  [[ "$output" == *"generation/provisional-graph.json" ]]
  run jq -r '[.audit_input_manifest.c0_plan_review_input.files[] | .path] | map(select(test("(c0/plan-graph|generation/provisional-graph)\\.json$"))) | length' "$MANIFEST"
  [ "$output" = "2" ]
}

@test "build-manifest: the sealed input_hash differs between the absent and present plan-graph shapes" {
  _build_low
  [ "$status" -eq 0 ]
  local absent_hash; absent_hash="$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")"
  [[ "$absent_hash" =~ ^sha256:[0-9a-f]{64}$ ]]

  mkdir -p "$C0_EVIDENCE_DIR/c0"
  printf '{"artifact_type":"plan_graph"}\n' > "$C0_EVIDENCE_DIR/c0/plan-graph.json"
  _build_low
  [ "$status" -eq 0 ]
  local present_hash; present_hash="$(jq -r '.audit_input_manifest.input_hash' "$MANIFEST")"

  [ "$absent_hash" != "$present_hash" ]
}

@test "build-manifest: a contract that exists only under plugins/<name>/defaults/ is captured (plugin-relative resolution)" {
  # The real layout of this repository: every schema and policy lives under
  # plugins/aid-orchestrator/defaults/, NOT at the repo root. Before P068
  # Step 1 the extractor tested the cited token against the repo root only,
  # so EVERY such citation failed the existence check and was silently
  # dropped — a plan citing a dozen schemas sealed an empty contracts[].
  mkdir -p "$TEST_PROJECT_ROOT/plugins/demo-plugin/defaults/policies"
  printf 'policy: demo\n' > "$TEST_PROJECT_ROOT/plugins/demo-plugin/defaults/policies/demo-policy.yaml"

  PLAN_PLUGIN="$TEST_PROJECT_ROOT/plan-plugin-contracts.md"
  cat > "$PLAN_PLUGIN" <<'EOF'
---
id: P900-c0-test
risk: low
---
Cites defaults/policies/demo-policy.yaml, which exists only under
plugins/demo-plugin/, and defaults/policies/nowhere.yaml, which exists nowhere.
EOF
  git add plan-plugin-contracts.md plugins
  git commit -q -m "add plugin-relative contract plan"

  run bash "$DISPATCH" build-manifest "$PLAN_PLUGIN" "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.contracts | length' "$MANIFEST"
  [ "$output" = "1" ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.contracts[0]' "$MANIFEST"
  [ "$output" = "plugins/demo-plugin/defaults/policies/demo-policy.yaml" ]

  # And it is genuinely sealed — a real sha256 over real bytes, not an
  # absent-input placeholder.
  run jq -r '[.audit_input_manifest.c0_plan_review_input.files[] | select(.path == "plugins/demo-plugin/defaults/policies/demo-policy.yaml") | .size] | first' "$MANIFEST"
  [ "$output" -gt 0 ]
}

@test "build-manifest: a repo-root contract still wins over a same-token plugin copy (no path moves for existing consumers)" {
  mkdir -p "$TEST_PROJECT_ROOT/plugins/demo-plugin/defaults/schemas"
  printf '{"type":"string"}\n' > "$TEST_PROJECT_ROOT/plugins/demo-plugin/defaults/schemas/example-contract.schema.json"
  git add plugins; git commit -q -m "add colliding plugin copy"

  _build_low
  [ "$status" -eq 0 ]
  run jq -r '.audit_input_manifest.c0_plan_review_input.contracts[0]' "$MANIFEST"
  [ "$output" = "defaults/schemas/example-contract.schema.json" ]
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

@test "dispatch: high-risk + Codex-reported unverifiable → status unverifiable with reasons, exit 2" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # 12th DONE-review audit fix ("C0 dispatch lifecycle / fail-closed exit
  # contract"): this test previously asserted exit 0 here, on the theory
  # that dispatch's exit code should reflect only transport-level success
  # (mirroring aid-c3-dispatch.sh's OWN, deliberately more nuanced
  # contract). That theory was never actually consistent with THIS file's
  # own _c0_process_response, which already returns non-zero for EVERY
  # unverifiable path uniformly — genuinely-Codex-reported unverifiable
  # included (see its `status == "unverifiable"` branch) — with no
  # distinction from a hash/head/schema-invalid response. C0's own spec
  # never asked for C3's nuance (see _c0_write_loop_summary's header
  # comment: "C0's spec never asked for that distinction"). The bug fixed
  # here was that cmd_dispatch's final exit decision ignored that signal
  # entirely; now that it doesn't, ANY unverifiable outcome — genuine or
  # invalid — correctly exits 2, matching what _c0_process_response always
  # intended to report.
  FAKE_C0_MODE=unverifiable run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
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

@test "dispatch: reviewed_plan_hash mismatch → hash_mismatch unverifiable, exit 2" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=hash_mismatch run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  # 12th DONE-review audit fix: a content-invalid response must not report
  # exit 0 just because the transport call itself succeeded.
  [ "$status" -eq 2 ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "hash_mismatch" ]
}

@test "dispatch: reviewed_head mismatch → head_mismatch unverifiable, exit 2" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=head_mismatch run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "head_mismatch" ]
}

@test "dispatch: a C3-shaped (audit_report) response is REJECTED by the C0 schema → invalid_output, exit 2" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=c3_shaped run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "invalid_output" ]
}

@test "dispatch: missing action_owner on a high-severity finding → invalid_output, exit 2" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=missing_action_owner run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
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

# ═══════════════════════════════════════════════════════════════════════════
# integration: aid-cp1-gate.sh consuming c0-plan-review.json + the CP1
# revision-limit ledger (P065 E-065-7_7 Step 20).
#
# These tests exercise the REAL, unstubbed chain: aid-cp1-gate.sh shells out
# to the REAL aid-c0-plan-review.sh verify (this file's own subject) and the
# REAL aid-cp1-ledger.sh check-budget — no AID_CP1_GATE_C0_REVIEW_BIN /
# AID_CP1_GATE_LEDGER_BIN test seam is set here (that seam exists for
# test-cp1-gate.sh's own lighter-weight unit tests). This is the genuine
# end-to-end proof that the gate's shell-out is load-bearing in production,
# using this file's fake-codex-c0 fixture as the only substitute (for the
# Codex CLI itself, exactly as the rest of this suite already does).
# ═══════════════════════════════════════════════════════════════════════════

# _write_passing_cp1_deep_evidence — the 4 L1/L2/L3/adjudicator files
# aid-cp1-gate.sh's PRE-EXISTING (Step 18/19-era) evidence check requires,
# independent of and unmodified by this step.
_write_passing_cp1_deep_evidence() {
  local dir="$C0_EVIDENCE_DIR/cp1-deep"
  mkdir -p "$dir"
  printf 'findings: []\nstop_rule_blockers: []\nconfidence: high\n' > "$dir/cp1-lens-L1-behavior.md"
  printf 'findings: []\nstop_rule_blockers: []\nconfidence: high\n' > "$dir/cp1-lens-L2-feasibility.md"
  printf 'findings: []\nstop_rule_blockers: []\nconfidence: high\n' > "$dir/cp1-lens-L3-enforcement.md"
  printf 'accepted_blockers: []\nrejected_blockers: []\nverdict: pass\nrevision_count: 0\n' > "$dir/cp1-adjudicator.md"
}

_setup_cp1_gate_paths() {
  GATE="$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh"
  export GATE
  LEDGER="$AID_PLUGIN_PATH/scripts/lib/aid-cp1-ledger.sh"
  export LEDGER
}

@test "integration: aid-cp1-gate.sh PASSES when C0 review is genuinely dispatched+clean and the ledger has budget" {
  _setup_cp1_gate_paths
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _write_passing_cp1_deep_evidence
  # Ledger is already initialized in setup() — no need to re-init here.

  run bash "$GATE" --plan "$PLAN_FILE_HIGH" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "integration: aid-cp1-gate.sh BLOCKS when C0 review genuinely dispatched but still has blocking findings" {
  _setup_cp1_gate_paths
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _write_passing_cp1_deep_evidence
  # Ledger is already initialized in setup().

  run bash "$GATE" --plan "$PLAN_FILE_HIGH" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking_findings"* ]]
}

@test "integration: aid-cp1-gate.sh BLOCKS when Codex was unavailable (unverifiable is not a loop iteration)" {
  _setup_cp1_gate_paths
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  cat > "$INDEP_SPY/detect" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "$INDEP_SPY/detect"
  run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  _write_passing_cp1_deep_evidence
  # Ledger is already initialized in setup().

  run bash "$GATE" --plan "$PLAN_FILE_HIGH" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unverifiable"* ]]
  # unverifiable is NOT a loop iteration — the ledger must stay untouched (0).
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "0" ]
}

@test "integration: aid-cp1-gate.sh BLOCKS a post-hoc tampered c0-plan-review.json even though its fields look clean" {
  _setup_cp1_gate_paths
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  # Tamper: flip blocking_findings to false and clear findings post-hoc,
  # WITHOUT re-dispatching Codex — the raw-binding/faithful-transform chain
  # verify() checks is now broken, even though the top-level fields alone
  # would otherwise satisfy the gate's cheaper field checks.
  tmp="$TEST_TMPDIR/tampered-cp1-report.json"
  jq '.blocking_findings = false | .findings = []' "$REPORT" > "$tmp"
  mv "$tmp" "$REPORT"
  _write_passing_cp1_deep_evidence
  # Ledger is already initialized in setup().

  run bash "$GATE" --plan "$PLAN_FILE_HIGH" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"verify failed"* ]]
}

@test "integration: aid-cp1-gate.sh BLOCKS when the CP1 ledger budget is exhausted, even with a clean C0 review" {
  _setup_cp1_gate_paths
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _write_passing_cp1_deep_evidence
  # Ledger is already initialized in setup() at attempts:0. Manually exhaust the budget.
  ledger_file="$TEST_PROJECT_ROOT/.aid-o/work/cp1-ledger/P900-c0-test.yaml"
  yq -i '.attempts = .max' "$ledger_file"

  run bash "$GATE" --plan "$PLAN_FILE_HIGH" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exhausted"* ]]
}

@test "integration: the bounded C0 review loop — a plan revision (new hash) advances the ledger; a same-hash re-run is a no-op" {
  _setup_cp1_gate_paths
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  # Ledger is already initialized in setup() at attempts:0. The first dispatch
  # should have incremented it to 1.
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "1" ]

  plan_hash_1="$(jq -r '.reviewed_plan_hash' "$REPORT")"
  # Confirm: re-running with the same hash is a no-op (stays at 1).
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" --codex-session "session-1-retry" "P900-c0-test" "$plan_hash_1"
  [ "$status" -eq 0 ]
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "1" ]

  # A "fix" to the plan (a new commit) => new reviewed_plan_hash => new
  # dispatch => a genuinely new Codex session for the recheck.
  echo "fix attempt 2" >> "$PLAN_FILE_HIGH"
  git add plan-high.md
  git commit -q -m "revise plan (recheck 1)"

  run bash "$DISPATCH" build-manifest "$PLAN_FILE_HIGH" "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  plan_hash_2="$(jq -r '.reviewed_plan_hash' "$REPORT")"
  [ "$plan_hash_2" != "$plan_hash_1" ]

  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" --codex-session "session-2" "P900-c0-test" "$plan_hash_2"
  [ "$status" -eq 0 ]
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "2" ]

  # Re-running the SAME (unchanged) plan hash again is a no-op — never
  # inflates the count (mirrors C3's "not a loop iteration" carve-out, here
  # for the mechanical increment primitive itself).
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" --codex-session "session-2-retry" "P900-c0-test" "$plan_hash_2"
  [ "$status" -eq 0 ]
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "2" ]

  _write_passing_cp1_deep_evidence
  run bash "$GATE" --plan "$PLAN_FILE_HIGH" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "integration: Codex-unavailable during the loop does NOT increment the ledger / consume a recheck" {
  _setup_cp1_gate_paths
  # Ledger is already initialized in setup() at attempts:0.
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "0" ]

  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  cat > "$INDEP_SPY/detect" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "$INDEP_SPY/detect"
  run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "unavailable" ]

  # NOT a loop iteration: there is no genuinely-dispatched attempt to
  # increment on (no codex session, no trustworthy plan_hash echo) — the
  # ledger correctly stays at 0, matching pipeline.md §6a's carve-out.
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "0" ]
}

@test "integration: low-risk plan never requires c0-plan-review.json or a ledger at all" {
  _setup_cp1_gate_paths
  _write_passing_cp1_deep_evidence >/dev/null 2>&1 || true
  # Deliberately: no build-manifest/dispatch, no ledger init, no
  # c0-plan-review.json, and PLAN_FILE (risk: low) is used, not the high one.
  run bash "$GATE" --plan "$PLAN_FILE" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"low-risk"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# Finding 1 tests: dispatch increments the ledger
# ═══════════════════════════════════════════════════════════════════════════

@test "FINDING 1: dispatch with successful Codex response increments the ledger (attempts advances)" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # Set FAKE_C0_THREAD_ID explicitly (rather than relying on the fake
  # codex stub subprocess's own internal default) so THIS test's shell
  # scope has a real, known value to assert against afterward — CP2 found
  # a prior version of this assertion referenced a bare $THREAD_ID that
  # was never actually in scope here (only inside the stub subprocess's
  # own heredoc-defined script), making it silently match any string.
  export FAKE_C0_THREAD_ID="019f0000-0000-7000-8000-00000feedbee"
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Proof: the ledger's attempts counter must have advanced from 0 to 1.
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "1" ]
  # Proof: the attempts_log must record the plan_hash and codex session.
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts_log | length')" = "1" ]
  run bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test
  [[ "$output" == *"$FAKE_C0_THREAD_ID"* ]]
}

@test "FINDING 1: dispatch without a valid ledger fails closed (unverifiable), even though Codex is clean" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # Sabotage the ledger by deleting it (simulating a corruption/missing-ledger scenario).
  rm -f "$TEST_PROJECT_ROOT/.aid-o/work/cp1-ledger/P900-c0-test.yaml"
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  # dispatch must fail (exit 2) because the ledger increment failed, even though
  # Codex itself returned a clean response (outcome=dispatched in the dispatch.json).
  [ "$status" -eq 2 ]
  run jq -r '.review_status' "$REPORT"
  [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"
  [ "$output" = "ledger_increment_failed" ]
}

@test "FINDING 1 (CP2 round-4 re-review): a transport-genuine but content-invalid dispatch (hash_mismatch) does NOT increment the ledger" {
  # CP2 independently reproduced this exact scenario and found the ORIGINAL
  # fix's gate (bare `outcome == "dispatched"`) is too broad: `outcome` is a
  # pure transport-level signal (Codex's CLI stream was well-formed) and
  # says nothing about whether the response CONTENT then passed validation.
  # A hash-mismatch response still has outcome=="dispatched" (the transport
  # genuinely succeeded) but review_status=="unverifiable" (content invalid)
  # — the plan's own Step 20 spec groups this with true transport failures
  # ("Codex unavailable/timeout/invalid does not increment the ledger"),
  # so it must NOT consume a budget slot.
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=hash_mismatch run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"

  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "hash_mismatch" ]

  # The ledger must still be at attempts:0 — this content-invalid response
  # never consumed a budget slot despite the transport-level dispatch
  # succeeding.
  run bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test
  [ "$status" -eq 0 ]
  [ "$(jq -r '.attempts' <<<"$output")" = "0" ]
  [ "$(jq -r '.attempts_log | length' <<<"$output")" = "0" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# Finding 2 tests: increment rejects when budget exhausted with new hash
# ═══════════════════════════════════════════════════════════════════════════

@test "FINDING 2: increment at attempts==max with a new hash is REJECTED and ledger unchanged" {
  # Setup: init ledger and manually advance it to max (3).
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2"
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2" sha256:aaa >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2" sha256:bbb >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2" sha256:ccc >/dev/null
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-ledger-finding2 | jq -r '.attempts')" = "3" ]

  # Attempt to increment with a NEW hash while at max — must fail.
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2" sha256:ddd
  [ "$status" -ne 0 ]

  # Proof: the ledger must be UNCHANGED (still at attempts=3).
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-ledger-finding2 | jq -r '.attempts')" = "3" ]
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-ledger-finding2 | jq -r '.attempts_log | length')" = "3" ]
}

@test "FINDING 2: increment at attempts==max with the SAME hash is still a no-op (not rejected)" {
  # Setup: init and advance to max with three different hashes.
  bash "$LEDGER" init --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2-noop"
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2-noop" sha256:aaa >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2-noop" sha256:bbb >/dev/null
  bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2-noop" sha256:ccc >/dev/null
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-ledger-finding2-noop | jq -r '.attempts')" = "3" ]

  # Re-run with the LAST hash (unchanged) — must succeed and be a no-op.
  run bash "$LEDGER" increment --project-root "$TEST_PROJECT_ROOT" "P900-ledger-finding2-noop" sha256:ccc
  [ "$status" -eq 0 ]

  # Proof: attempts still 3, no new entry in log.
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-ledger-finding2-noop | jq -r '.attempts')" = "3" ]
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-ledger-finding2-noop | jq -r '.attempts_log | length')" = "3" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# P065 E-065-7_7 Step 18: AID_C0_ATTEMPT evidence layering
# ═══════════════════════════════════════════════════════════════════════════

@test "AID_C0_ATTEMPT: single attempt=1 dispatch produces c0/attempt-01/ with raw evidence, canonical report matches" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Proof: attempt-01/ directory exists with its own evidence.
  [ -d "$C0_EVIDENCE_DIR/c0/attempt-01" ]
  [ -f "$C0_EVIDENCE_DIR/c0/attempt-01/c0/c0-dispatch.json" ]
  [ -f "$C0_EVIDENCE_DIR/c0/attempt-01/c0-plan-review.json" ]
  [ -f "$C0_EVIDENCE_DIR/c0/attempt-01/c0/audit-input-manifest.json" ]

  # Proof: canonical report exists and EQUALS the attempt's report.
  [ -f "$REPORT" ]
  run diff <(jq -S '.' "$C0_EVIDENCE_DIR/c0/attempt-01/c0-plan-review.json") <(jq -S '.' "$REPORT")
  [ "$status" -eq 0 ]
}

@test "AID_C0_ATTEMPT: two sequential attempts (1 then 2) produce both attempt-01/ and attempt-02/, canonical == last" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # First dispatch with attempt=1 — deliberately BLOCKING (not clean, Part B):
  # a "clean" first attempt would hit the terminal-outcome guard (Part B,
  # mirrors aid-c3-dispatch.sh) before a second attempt could ever run.
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  report_1="$REPORT"
  report_1_content="$(jq -S '.' "$report_1")"

  # Second dispatch with attempt=2, plan REVISED (new hash) — 8th DONE-review
  # audit fix: the same-hash re-dispatch guard now applies in attempt-explicit
  # mode too, so a genuine second attempt requires a revised plan.
  _revise_plan_high "attempt-2"
  FAKE_C0_MODE=valid AID_C0_ATTEMPT=2 run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  report_2="$REPORT"
  report_2_content="$(jq -S '.' "$report_2")"

  # Proof: both attempt directories exist with distinct sessions/content.
  [ -d "$C0_EVIDENCE_DIR/c0/attempt-01" ]
  [ -d "$C0_EVIDENCE_DIR/c0/attempt-02" ]
  [ -f "$C0_EVIDENCE_DIR/c0/attempt-01/c0-plan-review.json" ]
  [ -f "$C0_EVIDENCE_DIR/c0/attempt-02/c0-plan-review.json" ]

  # Proof: attempt-01 is different from attempt-02 (different content).
  run diff <(echo "$report_1_content") <(echo "$report_2_content")
  [ "$status" -ne 0 ]

  # Proof: canonical report equals the LAST (attempt-02's) content.
  [ "$report_2_content" = "$(jq -S '.' "$report_2")" ]
  run diff <(echo "$report_2_content") <(jq -S '.' "$REPORT")
  [ "$status" -eq 0 ]
}

@test "AID_C0_ATTEMPT regression: unset AID_C0_ATTEMPT never creates c0/attempt-*/ directories (byte-for-byte legacy)" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # Explicitly UNSET AID_C0_ATTEMPT (default behavior).
  unset AID_C0_ATTEMPT || true
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Proof: no attempt-*/ directory was ever created.
  [ ! -d "$C0_EVIDENCE_DIR/c0/attempt-01" ]
  [ ! -d "$C0_EVIDENCE_DIR/c0/attempt-02" ]

  # Proof: canonical report is still at the legacy path.
  [ -f "$REPORT" ]
  # Proof: dispatch.json is still at the legacy c0/codex/ path.
  [ -f "$C0_EVIDENCE_DIR/c0/codex/c0-dispatch.json" ]
}

@test "AID_C0_ATTEMPT collision guard: reusing outcome==dispatched slot is a PRECONDITION FAIL" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # First dispatch with attempt=1 — outcome will be "dispatched". Deliberately
  # BLOCKING (not clean, Part B): isolates the COLLISION guard (this test's
  # target) from the SEPARATE terminal-outcome guard, which a clean first
  # attempt would trip first and produce a different message.
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Proof: attempt-01/c0-dispatch.json records outcome==dispatched.
  [ "$(jq -r '.dispatch.outcome' "$C0_EVIDENCE_DIR/c0/attempt-01/c0/c0-dispatch.json")" = "dispatched" ]

  # Second dispatch WITH THE SAME AID_C0_ATTEMPT=1 — must FAIL.
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"already recorded a completed dispatch"* ]]
}

@test "AID_C0_ATTEMPT: retrying a non-dispatched slot (e.g., unavailable) is allowed" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # First dispatch with attempt=1 — make it UNAVAILABLE (independence check fails).
  cat > "$INDEP_SPY/detect" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
  chmod +x "$INDEP_SPY/detect"
  AID_C0_ATTEMPT=1 run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]

  # Proof: outcome is "unavailable", NOT "dispatched".
  [ "$(jq -r '.dispatch.outcome' "$C0_EVIDENCE_DIR/c0/attempt-01/c0/c0-dispatch.json")" = "unavailable" ]

  # Second dispatch with THE SAME AID_C0_ATTEMPT=1 (retry) — must SUCCEED and overwrite.
  cat > "$INDEP_SPY/detect" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$INDEP_SPY/detect"
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Proof: the second dispatch overwrote the first; outcome is now "dispatched".
  [ "$(jq -r '.dispatch.outcome' "$C0_EVIDENCE_DIR/c0/attempt-01/c0/c0-dispatch.json")" = "dispatched" ]
}

@test "AID_C0_ATTEMPT CP2 round-9 Finding 1: a genuinely valid response is recorded as review_status=pass, not unverifiable" {
  # CP2's round-9 review found _c0_process_response's last-message lookup
  # used a hardcoded two-level path (evidence_dir/c0/codex) that did not
  # match attempt mode's one-level work_c0_dir (attempt_dir/c0) — so EVERY
  # attempt-mode dispatch was unconditionally recorded unverifiable/
  # invalid_output regardless of the actual Codex response. The prior 5
  # tests never caught this because they only asserted file existence and
  # "attempt equals canonical" — both true whether the report says "pass"
  # or "unverifiable". Assert the actual semantic field values instead.
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  run jq -r '.review_status' "$C0_EVIDENCE_DIR/c0/attempt-01/c0-plan-review.json"
  [ "$output" = "pass" ]
  run jq -r '.outcome' "$C0_EVIDENCE_DIR/c0/attempt-01/c0-plan-review.json"
  [ "$output" = "dispatched" ]

  # Canonical report (finalized from the attempt) must show the same.
  run jq -r '.review_status' "$REPORT"; [ "$output" = "pass" ]
  run jq -r '.outcome' "$REPORT"; [ "$output" = "dispatched" ]

  # A genuinely valid attempt-mode dispatch must still advance the ledger.
  [ "$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')" = "1" ]
}

@test "AID_C0_ATTEMPT CP2 round-9 Finding 2: a content-invalid attempt-mode dispatch does NOT increment the ledger" {
  # CP2's round-9 review found the ledger-increment gate read
  # evidence_dir/c0-plan-review.json (the canonical root) instead of
  # work_evidence_dir's (the current attempt's own report) — in attempt
  # mode these diverge until _c0_finalize_attempt runs at the very end, so
  # the gate was checking a stale/prior report instead of this dispatch's
  # own. Prove the fix: a hash-mismatch (content-invalid, transport-genuine)
  # attempt-mode dispatch must leave the ledger untouched.
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=hash_mismatch run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  # 12th DONE-review audit fix: exit 2, not 0, for a content-invalid
  # attempt-mode dispatch (transport-genuine, ledger correctly untouched).
  [ "$status" -eq 2 ]

  run jq -r '.review_status' "$C0_EVIDENCE_DIR/c0/attempt-01/c0-plan-review.json"
  [ "$output" = "unverifiable" ]
  run jq -r '.outcome' "$C0_EVIDENCE_DIR/c0/attempt-01/c0-plan-review.json"
  [ "$output" = "hash_mismatch" ]
  run jq -r '.review_status' "$REPORT"; [ "$output" = "unverifiable" ]

  run bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test
  [ "$status" -eq 0 ]
  [ "$(jq -r '.attempts' <<<"$output")" = "0" ]
  [ "$(jq -r '.attempts_log | length' <<<"$output")" = "0" ]
}


# ═══════════════════════════════════════════════════════════════════════════
# P065 E-065-7_7 DONE-review Finding B: plain `verify` on the canonical
# evidence_dir after an AID_C0_ATTEMPT dispatch (mirrors aid-c3-dispatch.sh's
# test-c3-fix-loop.bats Finding B block).
# ═══════════════════════════════════════════════════════════════════════════

@test "Finding B: plain verify succeeds immediately after a SINGLE attempt-mode dispatch" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == verified* ]]
}

@test "Finding B: plain verify after two attempts checks attempt-02's raw evidence, not stale attempt-01's" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  # First attempt deliberately BLOCKING (Part B's terminal-outcome guard
  # would otherwise block the second attempt after a clean first one).
  export FAKE_C0_THREAD_ID="019f0000-0000-7000-8000-0000000a1111"
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _revise_plan_high "attempt-2"
  export FAKE_C0_THREAD_ID="019f0000-0000-7000-8000-0000000a2222"
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0000000a2222"* ]]
  [[ "$output" != *"0000000a1111"* ]]
}

@test "Finding B: tampering the CURRENT attempt's raw evidence makes plain verify fail" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _revise_plan_high "attempt-2"
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  jq '.findings = []' "$C0_EVIDENCE_DIR/c0/attempt-02/c0/codex-last-message.json" > "$TEST_TMPDIR/tampered.json"
  cp "$TEST_TMPDIR/tampered.json" "$C0_EVIDENCE_DIR/c0/attempt-02/c0/codex-last-message.json"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
}

@test "Finding B: tampering an OLD (non-current) attempt's raw evidence does NOT affect plain verify" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _revise_plan_high "attempt-2"
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  jq '.reviewed_plan_hash = "sha256:0000000000000000000000000000000000000000000000000000000000dd"' \
    "$C0_EVIDENCE_DIR/c0/attempt-01/c0/codex-last-message.json" > "$TEST_TMPDIR/tampered.json"
  cp "$TEST_TMPDIR/tampered.json" "$C0_EVIDENCE_DIR/c0/attempt-01/c0/codex-last-message.json"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
}

@test "Finding B: current_attempt pointing at a missing attempt directory fails closed" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  jq '.current_attempt = 9' "$C0_EVIDENCE_DIR/c0/loop-summary.json" > "$TEST_TMPDIR/ls.json"
  cp "$TEST_TMPDIR/ls.json" "$C0_EVIDENCE_DIR/c0/loop-summary.json"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"attempt-09"* ]]
  [[ "$output" == *"missing"* ]]
}

@test "Finding B: a non-integer current_attempt fails closed" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  jq '.current_attempt = "one"' "$C0_EVIDENCE_DIR/c0/loop-summary.json" > "$TEST_TMPDIR/ls.json"
  cp "$TEST_TMPDIR/ls.json" "$C0_EVIDENCE_DIR/c0/loop-summary.json"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a positive integer"* ]]
}

@test "Finding B: a canonical report hand-edited out of sync with the pointed-at attempt fails closed" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  jq '.reviewed_plan_hash = "sha256:0000000000000000000000000000000000000000000000000000000000dd"' \
    "$REPORT" > "$TEST_TMPDIR/canonical.json"
  cp "$TEST_TMPDIR/canonical.json" "$REPORT"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not match"* ]]
}

@test "Finding B: current_attempt's own raw evidence missing fails closed" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  rm -f "$C0_EVIDENCE_DIR/c0/attempt-01/c0/c0-dispatch.json"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"required artifact missing"* ]]
  [[ "$output" == *"attempt-01"* ]]
}

@test "Finding B regression: legacy (AID_C0_ATTEMPT unset) dispatch+verify is byte-for-byte unaffected" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$C0_EVIDENCE_DIR/c0/loop-summary.json" ]

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == verified* ]]
}

@test "CP2 round-9e: cmd_verify fails closed (not a crash) on a corrupted c0/loop-summary.json" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Valid JSON, but not an object — models a realistic truncated/partial
  # write, not a hand-crafted parse error (the old jq -e . alone would accept
  # this and slip past the pre-check, then crash the unguarded read below).
  printf '[]\n' > "$C0_EVIDENCE_DIR/c0/loop-summary.json"

  run bash "$DISPATCH" verify "$C0_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"NOT verified"* ]]
  [[ "$output" == *"loop-summary.json is not a valid JSON object"* ]]
}

@test "CP2 round-9f: collision guard on a CORRUPTED (torn-write) attempt c0-dispatch.json does not crash — treats it as retriable" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env

  # 8th DONE-review audit fix: the same-hash re-dispatch guard now applies
  # in attempt-explicit mode too, gated on the LEDGER's own recorded hash —
  # so this test no longer runs a genuine first dispatch (which would
  # increment the ledger for this hash and then have the guard correctly
  # reject the retry below, for an unrelated reason). Instead it directly
  # seeds the torn-write artifact a crashed PRIOR process would have left
  # behind — valid JSON, not an object, no genuine dispatch ever completed,
  # ledger never touched — isolating this test to what it actually proves:
  # the collision guard's read of .dispatch.outcome must not crash under
  # set -euo pipefail; it must treat this as "not dispatched" and allow the
  # attempt to proceed and overwrite it.
  mkdir -p "$C0_EVIDENCE_DIR/c0/attempt-01/c0"
  printf '[]\n' > "$C0_EVIDENCE_DIR/c0/attempt-01/c0/c0-dispatch.json"

  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
  run jq -r '.dispatch.outcome' "$C0_EVIDENCE_DIR/c0/attempt-01/c0/c0-dispatch.json"
  [ "$output" = "dispatched" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# P065 E-065-7_7 Part B: c0/loop-summary.json attempts history, same-
# fingerprint-survives detection, and the terminal ALLOWLIST guard. Mirrors
# aid-c3-dispatch.sh's already-6-round-hardened equivalent mechanism
# (test-c3-fix-loop.bats), minus the budget_exhausted escalation branch,
# which is deliberately NOT ported — see _c0_write_loop_summary's header
# comment (C0's real attempt-count bound is the CP1 ledger, a separate,
# already-tested mechanism; duplicating it here would be two independent
# copies of the same truth).
# ═══════════════════════════════════════════════════════════════════════════

@test "Part B: c0/loop-summary.json accumulates both attempts and reflects the right recheck_count/outcome" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  export FAKE_C0_THREAD_ID="thread-partb-01"
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _revise_plan_high "attempt-2"
  export FAKE_C0_THREAD_ID="thread-partb-02"
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  local SUM="$C0_EVIDENCE_DIR/c0/loop-summary.json"
  [ -f "$SUM" ]
  run jq -r '.attempts | length' "$SUM"; [ "$output" = "2" ]
  run jq -r '.attempts[0].n' "$SUM"; [ "$output" = "1" ]
  run jq -r '.attempts[0].outcome' "$SUM"; [ "$output" = "dispatched" ]
  run jq -r '.attempts[1].n' "$SUM"; [ "$output" = "2" ]
  run jq -r '.attempts[1].outcome' "$SUM"; [ "$output" = "dispatched" ]

  # attempt-01 = initial review (not a recheck), attempt-02 = the one recheck.
  run jq -r '.recheck_count' "$SUM"; [ "$output" = "1" ]
  # latest attempt (attempt-02) is clean → top-level outcome:"clean".
  run jq -r '.outcome' "$SUM"; [ "$output" = "clean" ]
  run jq -r '.current_attempt' "$SUM"; [ "$output" = "2" ]
}

@test "Part B: the SAME blocking-finding fingerprint surviving a recheck escalates immediately" {
  # The shared fake-codex fixture's FAKE_C0_MODE=findings always emits the
  # SAME fixed finding text (build_findings with_owner) — dispatching it
  # twice in a row is exactly the "fix ineffective, same finding still
  # blocking" scenario this mechanism exists to catch.
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _revise_plan_high "attempt-2"
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  local SUM="$C0_EVIDENCE_DIR/c0/loop-summary.json"
  run jq -r '.outcome' "$SUM"; [ "$output" = "escalated" ]
  run jq -r '.escalation_reason' "$SUM"; [ "$output" = "same_fingerprint_survived" ]
}

@test "8th DONE-review audit fix: attempt-explicit mode — a blocking (non-terminal) prior attempt plus an UNCHANGED plan_hash is rejected, Codex is never invoked, and the ledger does not change" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  # Genuinely dispatched + blocking (not "unverifiable") → the ledger WAS
  # incremented for this hash (FINDING 1 fix). Confirm the pre-state before
  # the rejected retry, so "ledger does not change" below is a real proof,
  # not an assumption.
  attempts_before="$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')"
  [ "$attempts_before" -ge 1 ]

  # loop-summary outcome after a blocking (non-escalated) result is null —
  # NOT terminal under the existing ALLOWLIST guard, so THAT guard alone
  # would let this through; the same-hash guard is what must catch it.
  run jq -r '.outcome' "$C0_EVIDENCE_DIR/c0/loop-summary.json"; [ "$output" = "null" ]

  # No plan revision — same manifest, same reviewed_plan_hash. Must be
  # rejected BEFORE any codex invocation or ledger mutation.
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"already has a recorded ledger attempt at this exact hash"* ]]

  # Proof: Codex was never invoked for attempt-02 — no raw evidence exists.
  [ ! -f "$C0_EVIDENCE_DIR/c0/attempt-02/c0/codex-events.jsonl" ]
  [ ! -f "$C0_EVIDENCE_DIR/c0/attempt-02/c0/c0-dispatch.json" ]

  # Proof: the ledger did not change (still exactly attempts_before).
  attempts_after="$(bash "$LEDGER" read --project-root "$TEST_PROJECT_ROOT" P900-c0-test | jq -r '.attempts')"
  [ "$attempts_after" = "$attempts_before" ]

  # Proof: a genuine, claimed PM override still gets through, exactly as in
  # legacy mode — but now it must be a real artifact, not a bare env var.
  _write_c0_override
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
}

@test "Part B: clean is terminal — a 2nd explicit dispatch after outcome==clean is rejected without an override" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.outcome' "$C0_EVIDENCE_DIR/c0/loop-summary.json"; [ "$output" = "clean" ]

  # A 2nd attempt (no PM-authorized override) must be rejected BEFORE any
  # codex invocation or evidence write for attempt-02.
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"clean"* ]]
  [ ! -d "$C0_EVIDENCE_DIR/c0/attempt-02" ]

  # 9th DONE-review audit fix: an arbitrary 20+-char environment variable no
  # longer bypasses anything — only a genuine, claimable artifact does. A
  # too-short pm_ref inside a REAL artifact is ALSO rejected (mirrors
  # aid-cp1-ledger.sh's own >=20-char pm_ref requirement).
  AID_C0_FORCE_BEYOND_ESCALATION="this is 20+ characters but is NOT a real artifact" \
    AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  _write_c0_override "too short"
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  # A genuine, >=20-char, single-use claimed override DOES let the 2nd
  # attempt through.
  _write_c0_override "PM approved an extra recheck 2026-07-19 review"
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -d "$C0_EVIDENCE_DIR/c0/attempt-02" ]

  # And it is now consumed — a THIRD attempt without a fresh artifact is
  # rejected again (single-use proven).
  AID_C0_ATTEMPT=3 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
}

@test "Part B: the terminal guard is an ALLOWLIST — any unrecognized/corrupted outcome value is treated as terminal too" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 FAKE_C0_MODE=findings run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Directly corrupt the recorded outcome to an unrecognized value — not
  # reachable through any normal write path, simulating a corrupted file or
  # a future schema value this guard was never updated for.
  local SUM="$C0_EVIDENCE_DIR/c0/loop-summary.json"
  jq '.outcome = "bogus_unrecognized_state"' "$SUM" > "$TEST_TMPDIR/bogus.json"
  cp "$TEST_TMPDIR/bogus.json" "$SUM"

  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"bogus_unrecognized_state"* ]]
  [ ! -d "$C0_EVIDENCE_DIR/c0/attempt-02" ]

  _write_c0_override "PM approved proceeding past a corrupted state"
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
}

@test "Part B regression: legacy (AID_C0_ATTEMPT unset) dispatch never creates or checks c0/loop-summary.json" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$C0_EVIDENCE_DIR/c0/loop-summary.json" ]

  # 7th DONE-review audit fix ("C0 bounded review lifecycle"): a second
  # legacy dispatch of the SAME unchanged plan_hash must now be REJECTED by
  # the same-hash re-dispatch guard — it is NOT blocked by the (still
  # inapplicable-in-legacy-mode) loop-summary terminal-outcome guard, but by
  # a separate, unconditional check against the ledger's own last recorded
  # hash. Before this fix, this same assertion block asserted status 0 with
  # no PRECONDITION FAIL — that was the exact budget-free "re-dispatch an
  # unrevised plan hoping for a favorable review" gap the audit found.
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"already has a recorded ledger attempt at this exact hash"* ]]
  [ ! -f "$C0_EVIDENCE_DIR/c0/loop-summary.json" ]

  # Still legacy mode, still no loop-summary.json involved: revising the
  # plan (new plan_hash) is NOT blocked — the guard is per-hash, not a
  # sticky lockout. Proves legacy mode retains its original freedom to
  # dispatch again once the plan actually changes.
  cat > "$PLAN_FILE_HIGH" <<'EOF'
---
id: P900-c0-test
title: A high-risk plan (revised)
risk: high
---
# Plan

This plan adds an authenticate() handler, revised after review.
EOF
  git -C "$TEST_PROJECT_ROOT" add plan-high.md
  git -C "$TEST_PROJECT_ROOT" commit -q -m "revise plan-high.md"
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
  [ ! -f "$C0_EVIDENCE_DIR/c0/loop-summary.json" ]
}

@test "9th DONE-review audit fix: same-hash re-dispatch guard is overridable via a genuine, single-use claimed PM override (NOT a bare env var)" {
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  # Without override: rejected (same assertion as the regression test above).
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  # An arbitrary 20+-char env var alone does NOT let it through anymore.
  AID_C0_FORCE_BEYOND_ESCALATION="this is 20+ characters but is NOT a real artifact" \
    FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  # With a genuine, claimed PM override artifact: proceeds, and the claimed
  # reason + consumed_path is echoed to the log for traceability.
  _write_c0_override "deliberate re-review, PM-authorized"
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"same-hash re-dispatch"* ]]
  [[ "$output" == *"deliberate re-review, PM-authorized"* ]]
  [[ "$output" == *"consumed:"* ]]

  # Single-use: the artifact is gone, a fresh (third, still same-hash)
  # attempt without a new artifact is rejected again.
  run jq -r '.audit_input_manifest.c0_plan_review_input.plan_id' "$MANIFEST"
  local plan_id="$output"
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/work/evidence/${plan_id}/cp1-pm-escalation-override.json" ]
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
}

@test "7th DONE-review audit fix: a plan_id with no ledger yet (first-ever dispatch) is not blocked by the same-hash guard" {
  bash "$LEDGER" init --pre-enforcement --project-root "$TEST_PROJECT_ROOT" "P901-c0-fresh" >/dev/null 2>&1 || true
  PLAN_FILE_HIGH="$TEST_PROJECT_ROOT/plan-high-901.md"
  cat > "$PLAN_FILE_HIGH" <<'EOF'
---
id: P901-c0-fresh
title: A brand-new high-risk plan
risk: high
---
# Plan

This plan has never been dispatched before.
EOF
  git -C "$TEST_PROJECT_ROOT" add plan-high-901.md
  git -C "$TEST_PROJECT_ROOT" commit -q -m "seed plan-high-901.md"
  run bash "$DISPATCH" build-manifest "$PLAN_FILE_HIGH" "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
}

@test "Part B CP2 finding: a skipped (low-risk, Codex never invoked) attempt does NOT get recorded as terminal 'clean'" {
  # A low-risk plan attempt genuinely skips Codex (review_status:"skipped",
  # _c0_write_skipped) — CP2's self-verify of Part B found this fell through
  # to report_status:"pass" -> loop-summary outcome:"clean" (TERMINAL),
  # permanently blocking the plan's first REAL review once it's later
  # revised into high-risk territory (same evidence dir, rebuilt manifest —
  # exactly what a plan revision does).
  _build_low
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=1 run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  run jq -r '.review_status' "$C0_EVIDENCE_DIR/c0-plan-review.json"; [ "$output" = "skipped" ]

  # Proof: the skip is recorded as "unverifiable" (non-terminal — the same
  # allowlisted, freely-retriable value a true dispatch failure gets), NOT
  # the terminal "clean".
  run jq -r '.outcome' "$C0_EVIDENCE_DIR/c0/loop-summary.json"
  [ "$output" = "unverifiable" ]

  # The plan is revised into high-risk territory — a real second attempt on
  # the SAME evidence dir must proceed WITHOUT needing a PM override.
  _build_high
  [ "$status" -eq 0 ]
  _seed_dispatch_env
  AID_C0_ATTEMPT=2 FAKE_C0_MODE=valid run bash "$DISPATCH" dispatch "$C0_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
  [ -d "$C0_EVIDENCE_DIR/c0/attempt-02" ]
}
