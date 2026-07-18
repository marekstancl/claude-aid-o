#!/usr/bin/env bats
# test-c3-fix-loop.bats — P065 Step 17 (E-065-6_7): per-attempt evidence
# layering in aid-c3-dispatch.sh's cmd_dispatch.
#
# Step 16 (already merged) documented the fix->reverify LOOP's orchestration in
# pipeline.md §6a (a Claude Code controller loop, prose only — no bash driver
# script exists). Step 17 is the EVIDENCE-LAYERING PRIMITIVE such a loop calls
# repeatedly: an optional AID_C3_ATTEMPT env var tells a single `dispatch`
# invocation which attempt number it is, so each attempt's Codex-derived
# artifacts persist under c3/attempt-NN/ instead of being overwritten in place,
# while the canonical <evidence_dir>/audit-report.json — the path the FSM C3
# hook + Curator read, unchanged since Step 16 — always ends up holding the
# LAST attempt's report.
#
# This suite does NOT drive any loop-DECIDING logic (when to recheck, when to
# escalate) — that is out of scope per the plan (pipeline.md's controller-level
# prose, not this script). It only proves the PRIMITIVE cmd_dispatch now
# exposes: attempt-scoped layering, canonical-copy-of-the-last-attempt, a
# loop-summary.json accumulator, `verify --reference` against an individual
# attempt directory, and a fail-closed reaction when the canonical copy cannot
# be made durable.
#
# AID_C3_ATTEMPT UNSET is the legacy/default path (byte-for-byte pre-Step-17
# behavior) — proven unaffected by test-c3-audit.bats (27), test-aid-c3-dispatch.bats,
# test-c3-audit-prompt.bats (16) unmodified, plus one direct regression check
# below.
#
# Fixture conventions (setup_test_evidence_dir, AID_PLUGIN_PATH, an in-test
# codex CLI stub reading FAKE_*  env vars for its emitted report content)
# mirror test-c3-audit.bats's `_drive_clean_dispatch` / test-aid-c3-dispatch.bats's
# `_dispatch_seams` patterns rather than inventing a new style.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  DISPATCH="$AID_PLUGIN_PATH/scripts/lib/aid-c3-dispatch.sh"
  export DISPATCH

  # project.yaml so identity.project_id resolves to a real value (fingerprints).
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'project_id: test-c3-loop-proj\n' > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml"

  # Base commit + changed-paths seam (one repo-relative changed path per line).
  mkdir -p "$TEST_PROJECT_ROOT/src"
  printf 'export const a = 1;\n' > "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts .aid-o/config/project.yaml
  git -C "$TEST_PROJECT_ROOT" commit -q -m base
  BASE_SHA="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  export BASE_SHA
  printf 'src/app.ts\n' > "$TEST_TMPDIR/changed-paths.txt"
  export AID_CHANGED_PATHS="$TEST_TMPDIR/changed-paths.txt"

  # Independence pre-check spy → always available, so dispatch invokes codex.
  mkdir -p "$TEST_TMPDIR/indep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/indep/detect"
  chmod +x "$TEST_TMPDIR/indep/detect"
  export AID_C3_INDEPENDENCE_BIN="$TEST_TMPDIR/indep/detect"

  ORIGINAL_PATH="$PATH"
  export ORIGINAL_PATH
  _install_fake_codex_stub
}

teardown() {
  PATH="${ORIGINAL_PATH:-$PATH}"
  export PATH
  unset AID_C3_ATTEMPT AID_C3_INDEPENDENCE_BIN AID_CHANGED_PATHS
  unset FAKE_C3_HEAD FAKE_C3_BRIEF_HASH FAKE_C3_THREAD_ID FAKE_C3_BLOCKING FAKE_C3_FINDINGS FAKE_C3_INVOKE_LOG
  chmod -R u+rwx "$TEST_EVIDENCE_DIR" 2>/dev/null || true   # restore any chmod-555 seam dir
  teardown_test_evidence_dir
}

# ─── Fixture helpers ─────────────────────────────────────────────────────────

# _install_fake_codex_stub — a minimal, fully env-driven `codex` CLI stub
# (mirrors test-c3-audit.bats's `_drive_clean_dispatch` in-test heredoc stub
# rather than the shared scripts/tests/fixtures/fake-codex/codex fixture,
# because this suite needs a genuinely CLEAN (no findings) report — a mode the
# shared fixture does not offer — plus per-call control over thread_id/head/
# blocking so two sequential dispatch calls can emit deliberately DISTINCT
# provenance). Reads at invocation time (not bake time), so each test just sets
# these env vars differently before calling dispatch — same seam style as the
# shared fixture's FAKE_CODEX_MODE/FAKE_CODEX_THREAD_ID.
#   FAKE_C3_HEAD / FAKE_C3_BRIEF_HASH — echoed verbatim as reviewed_head /
#     codex_brief_hash (must match this call's manifest for a "dispatched"
#     provenance-bound report).
#   FAKE_C3_THREAD_ID   — the emitted thread.started thread_id (→ codex_session_id).
#   FAKE_C3_BLOCKING    — "true"/"false" (default false).
#   FAKE_C3_FINDINGS    — a JSON findings[] array (default "[]"). review_status
#     is derived: "pass" iff blocking==false AND findings==[] (schema-valid);
#     "findings" otherwise.
#   FAKE_C3_INVOKE_LOG  — if set, one "invoked" line is appended per REAL exec
#     invocation (never for --version), so a test can assert an exact
#     invocation count.
_install_fake_codex_stub() {
  local dir="$TEST_TMPDIR/fake-loop-codex"
  mkdir -p "$dir"
  cat > "$dir/codex" <<'CODEXEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "fake-loop-codex 0.0.0"; exit 0; fi
[[ -n "${FAKE_C3_INVOKE_LOG:-}" ]] && printf 'invoked\n' >> "$FAKE_C3_INVOKE_LOG"
last=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message|-o) last="$2"; shift 2 ;;
    *) shift ;;
  esac
done
blocking="${FAKE_C3_BLOCKING:-false}"
findings="${FAKE_C3_FINDINGS:-[]}"
review_status="findings"
if [[ "$blocking" == "false" && "$findings" == "[]" ]]; then review_status="pass"; fi
report="$(jq -nc \
  --arg h "${FAKE_C3_HEAD:-}" \
  --arg bh "${FAKE_C3_BRIEF_HASH:-}" \
  --arg rs "$review_status" \
  --argjson blocking "$blocking" \
  --argjson findings "$findings" \
  '{reviewed_head:$h, codex_brief_hash:$bh, review_status:$rs, blocking_findings:$blocking, findings:$findings}')"
jq -nc --arg t "${FAKE_C3_THREAD_ID:-019f0000-0000-7000-8000-000000000000}" '{type:"thread.started",thread_id:$t}'
printf '%s\n' '{"type":"turn.started"}'
jq -nc --arg t "$report" '{type:"item.completed",item:{id:"item_final",type:"agent_message",text:$t}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'
[[ -n "$last" ]] && printf '%s\n' "$report" > "$last"
exit 0
CODEXEOF
  chmod +x "$dir/codex"
  PATH="$dir:$PATH"
  export PATH
}

# _commit_change <suffix> — append a distinguishing line to src/app.ts and
# commit; echoes the new HEAD sha.
_commit_change() {
  printf 'export const x_%s = 1;\n' "$1" >> "$TEST_PROJECT_ROOT/src/app.ts"
  git -C "$TEST_PROJECT_ROOT" add src/app.ts
  git -C "$TEST_PROJECT_ROOT" commit -q -m "change $1"
  git -C "$TEST_PROJECT_ROOT" rev-parse HEAD
}

# _build_manifest <base_sha> <head_sha> [risk_profile] — real build-manifest run.
_build_manifest() {
  run bash "$DISPATCH" build-manifest "$TEST_EVIDENCE_DIR" "$1" "$2" "${3:-high}"
  [ "$status" -eq 0 ]
}

# _drive_two_attempts — commit+build+dispatch attempt 1 (blocking, one HIGH
# finding, thread-attempt-01) then a simulated external fix commit + attempt 2
# (clean, thread-attempt-02) — the exact shape pipeline.md §6a's loop body
# drives repeatedly. Sets HEAD1/HEAD2/BH1/BH2 for callers to assert on.
_drive_two_attempts() {
  HEAD1="$(_commit_change 1)"; export HEAD1
  _build_manifest "$BASE_SHA" "$HEAD1"
  BH1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export BH1
  export FAKE_C3_HEAD="$HEAD1" FAKE_C3_BRIEF_HASH="$BH1" FAKE_C3_THREAD_ID="thread-attempt-01" \
         FAKE_C3_BLOCKING=true \
         FAKE_C3_FINDINGS='[{"severity":"high","area":"correctness","finding":"Unchecked error path.","recommendation":"Add an explicit error branch.","action_owner":"implementer"}]'
  AID_C3_ATTEMPT=1 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  HEAD2="$(_commit_change 2)"; export HEAD2
  _build_manifest "$BASE_SHA" "$HEAD2"
  BH2="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export BH2
  export FAKE_C3_HEAD="$HEAD2" FAKE_C3_BRIEF_HASH="$BH2" FAKE_C3_THREAD_ID="thread-attempt-02" \
         FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'
  AID_C3_ATTEMPT=2 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
}

# ─── AC1: clean first audit → only attempt-01, no automatic second run ───────

@test "clean first audit produces only c3/attempt-01/, canonical status:pass, and exactly one codex invocation" {
  local head1; head1="$(_commit_change 1)"
  _build_manifest "$BASE_SHA" "$head1"
  local bh1; bh1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"

  FAKE_C3_INVOKE_LOG="$TEST_TMPDIR/invoke.log"; : > "$FAKE_C3_INVOKE_LOG"
  export FAKE_C3_INVOKE_LOG
  export FAKE_C3_HEAD="$head1" FAKE_C3_BRIEF_HASH="$bh1" FAKE_C3_THREAD_ID="thread-clean-01" \
         FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'

  AID_C3_ATTEMPT=1 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  [ -d "$TEST_EVIDENCE_DIR/c3/attempt-01" ]
  [ ! -d "$TEST_EVIDENCE_DIR/c3/attempt-02" ]

  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "pass" ]
  run jq -r '.audit_report.blocking_findings' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "false" ]

  # dispatch is a single-shot primitive: ONE invocation == exactly one codex
  # exec, never an automatic second run (the loop-DRIVING decision belongs to
  # the pipeline-level controller, out of scope for this script).
  run wc -l < "$FAKE_C3_INVOKE_LOG"
  [ "$output" = "1" ]
}

# ─── AC2: two distinct attempts, canonical == last ───────────────────────────

@test "two AID_C3_ATTEMPT dispatch calls produce attempt-01 + attempt-02 with distinct session_id/head; canonical == last attempt" {
  _drive_two_attempts

  [ -d "$TEST_EVIDENCE_DIR/c3/attempt-01" ]
  [ -d "$TEST_EVIDENCE_DIR/c3/attempt-02" ]

  run jq -r '.dispatch.codex_session_id' "$TEST_EVIDENCE_DIR/c3/attempt-01/c3/c3-dispatch.json"
  [ "$output" = "thread-attempt-01" ]
  run jq -r '.dispatch.codex_session_id' "$TEST_EVIDENCE_DIR/c3/attempt-02/c3/c3-dispatch.json"
  [ "$output" = "thread-attempt-02" ]

  run jq -r '.audit_report.reviewed_head' "$TEST_EVIDENCE_DIR/c3/attempt-01/audit-report.json"
  [ "$output" = "$HEAD1" ]
  run jq -r '.audit_report.reviewed_head' "$TEST_EVIDENCE_DIR/c3/attempt-02/audit-report.json"
  [ "$output" = "$HEAD2" ]
  [ "$HEAD1" != "$HEAD2" ]

  run jq -r '.status' "$TEST_EVIDENCE_DIR/c3/attempt-01/audit-report.json"
  [ "$output" = "fail" ]
  run jq -r '.status' "$TEST_EVIDENCE_DIR/c3/attempt-02/audit-report.json"
  [ "$output" = "pass" ]

  # canonical evidence-root report equals the LAST attempt's, byte for byte.
  diff <(jq -S . "$TEST_EVIDENCE_DIR/audit-report.json") <(jq -S . "$TEST_EVIDENCE_DIR/c3/attempt-02/audit-report.json")
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "pass" ]
  run jq -r '.audit_report.reviewed_head' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "$HEAD2" ]
}

# ─── AC3: loop-summary.json accumulation ─────────────────────────────────────

@test "loop-summary.json accumulates both attempts and reflects the right recheck_count/outcome" {
  _drive_two_attempts
  local SUM="$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ -f "$SUM" ]

  run jq -r '.attempts | length' "$SUM"
  [ "$output" = "2" ]
  run jq -r '.attempts[0].n' "$SUM"; [ "$output" = "1" ]
  run jq -r '.attempts[0].session_id' "$SUM"; [ "$output" = "thread-attempt-01" ]
  run jq -r '.attempts[0].head' "$SUM"; [ "$output" = "$HEAD1" ]
  run jq -r '.attempts[0].outcome' "$SUM"; [ "$output" = "dispatched" ]
  run jq -r '.attempts[1].n' "$SUM"; [ "$output" = "2" ]
  run jq -r '.attempts[1].session_id' "$SUM"; [ "$output" = "thread-attempt-02" ]
  run jq -r '.attempts[1].head' "$SUM"; [ "$output" = "$HEAD2" ]
  run jq -r '.attempts[1].outcome' "$SUM"; [ "$output" = "dispatched" ]

  # 2 genuinely dispatched attempts → recheck_count = 2 - 1 = 1 (attempt-01 is
  # the initial audit, NOT a recheck; attempt-02 is the one recheck so far).
  run jq -r '.recheck_count' "$SUM"
  [ "$output" = "1" ]
  # latest attempt (attempt-02) is clean → top-level outcome:"clean".
  run jq -r '.outcome' "$SUM"
  [ "$output" = "clean" ]
}

# ─── AC4: `verify --reference` against an individual attempt directory ──────

@test "verify --reference works directly against an individual attempt directory (both attempt-01 and attempt-02)" {
  _drive_two_attempts

  run bash "$DISPATCH" verify --reference "$TEST_EVIDENCE_DIR/c3/attempt-01"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified — codex session thread-attempt-01"* ]]
  [[ "$output" == *"$HEAD1"* ]]

  run bash "$DISPATCH" verify --reference "$TEST_EVIDENCE_DIR/c3/attempt-02"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified — codex session thread-attempt-02"* ]]
  [[ "$output" == *"$HEAD2"* ]]

  # Live-mode verify against attempt-01 correctly FAILS — repo HEAD has since
  # moved to HEAD2 (attempt-02's commit), so attempt-01 is legitimately stale
  # under live freshness. --reference (above) is precisely what lets a
  # committed historical attempt still verify after HEAD moves on.
  run bash "$DISPATCH" verify "$TEST_EVIDENCE_DIR/c3/attempt-01"
  [ "$status" -eq 2 ]
}

# ─── AC5: canonical-copy failure → fail closed ──────────────────────────────

@test "canonical-copy-to-root prevented → dispatch fails closed (attempt evidence stays authoritative, exit 2, no stale/false canonical pass)" {
  local head1; head1="$(_commit_change 1)"
  _build_manifest "$BASE_SHA" "$head1"
  local bh1; bh1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export FAKE_C3_HEAD="$head1" FAKE_C3_BRIEF_HASH="$bh1" FAKE_C3_THREAD_ID="thread-blocked-copy" \
         FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'

  # Make ONLY the evidence-root directory unwritable (c3/ and c3/attempt-01/
  # underneath stay writable — the whole attempt pipeline runs and writes its
  # own evidence normally; only the FINAL copy-to-canonical-root step fails).
  chmod 555 "$TEST_EVIDENCE_DIR"
  AID_C3_ATTEMPT=1 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  chmod u+rwx "$TEST_EVIDENCE_DIR"   # restore immediately for the assertions below

  [ "$status" -eq 2 ]
  [[ "$output" == *"FATAL"* ]]
  [[ "$output" == *"canonical"* ]]

  # The attempt's OWN evidence is authoritative and intact despite the failure.
  [ -f "$TEST_EVIDENCE_DIR/c3/attempt-01/audit-report.json" ]
  run jq -r '.status' "$TEST_EVIDENCE_DIR/c3/attempt-01/audit-report.json"
  [ "$output" = "pass" ]

  # Canonical root was never left holding a stale/wrong SUCCESS: either it was
  # never written (this fixture's case — evidence_dir was unwritable for the
  # stomp-to-unverifiable attempt too) or, if present, it is honestly
  # status:unverifiable — never a silently-stale status:pass.
  if [ -f "$TEST_EVIDENCE_DIR/audit-report.json" ]; then
    run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
    [ "$output" = "unverifiable" ]
  fi
}

# ─── Additive regression proofs for THIS step's own new branches ────────────

@test "regression: AID_C3_ATTEMPT unset (legacy default) never creates c3/attempt-*/ or loop-summary.json" {
  local head1; head1="$(_commit_change 1)"
  _build_manifest "$BASE_SHA" "$head1"
  local bh1; bh1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export FAKE_C3_HEAD="$head1" FAKE_C3_BRIEF_HASH="$bh1" FAKE_C3_THREAD_ID="thread-legacy" \
         FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'

  run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  [ -f "$TEST_EVIDENCE_DIR/audit-report.json" ]
  [ -f "$TEST_EVIDENCE_DIR/c3/c3-dispatch.json" ]
  [ ! -d "$TEST_EVIDENCE_DIR/c3/attempt-01" ]
  [ ! -f "$TEST_EVIDENCE_DIR/c3/loop-summary.json" ]
}

@test "collision guard: reusing an AID_C3_ATTEMPT that already recorded a completed dispatch is a PRECONDITION FAIL" {
  # Deliberately BLOCKING (not clean) and below max_rechecks, so loop-summary
  # outcome stays null (neither "clean" nor "escalated") — this isolates the
  # attempt-number collision guard from the terminal-outcome check (own tests:
  # "escalation is terminal" / "clean is ALSO terminal").
  local head1; head1="$(_commit_change 1)"
  _build_manifest "$BASE_SHA" "$head1"
  local bh1; bh1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export FAKE_C3_HEAD="$head1" FAKE_C3_BRIEF_HASH="$bh1" FAKE_C3_THREAD_ID="thread-first" \
         FAKE_C3_BLOCKING=true \
         FAKE_C3_FINDINGS='[{"severity":"high","area":"correctness","finding":"Unchecked error path.","recommendation":"Add an explicit error branch.","action_owner":"implementer"}]'
  AID_C3_ATTEMPT=1 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  run jq -r '.outcome' "$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ "$output" = "null" ]

  # Same manifest/head still current; a second call reusing AID_C3_ATTEMPT=1
  # must be refused — attempt-01 already recorded a genuine dispatched outcome.
  AID_C3_ATTEMPT=1 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"already recorded a completed dispatch"* ]]
}

# ─── AC3 (cont): "escalated" once recheck_count reaches the policy budget ───

@test "loop-summary.json outcome == escalated once recheck_count reaches c3_fix_loop.max_rechecks while still blocking (no policy override — default max_rechecks:2)" {
  local heads=() bhs=()
  local i head bh
  for i in 1 2 3; do
    head="$(_commit_change "$i")"
    heads+=("$head")
    _build_manifest "$BASE_SHA" "$head"
    bh="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
    bhs+=("$bh")
    export FAKE_C3_HEAD="$head" FAKE_C3_BRIEF_HASH="$bh" FAKE_C3_THREAD_ID="thread-esc-$i" \
           FAKE_C3_BLOCKING=true \
           FAKE_C3_FINDINGS='[{"severity":"high","area":"correctness","finding":"Still unchecked.","recommendation":"Fix it.","action_owner":"implementer"}]'
    AID_C3_ATTEMPT="$i" run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
    [ "$status" -eq 0 ]
  done

  local SUM="$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  run jq -r '.attempts | length' "$SUM"; [ "$output" = "3" ]
  # attempt-01 = initial audit (not a recheck), attempt-02/03 = the 2 rechecks
  # the default policy's c3_fix_loop.max_rechecks:2 allows → recheck_count=2.
  run jq -r '.recheck_count' "$SUM"; [ "$output" = "2" ]
  run jq -r '.outcome' "$SUM"; [ "$output" = "escalated" ]

  # Every attempt's own report still holds status:fail (never silently
  # rewritten to look clean) — canonical == the LAST (3rd) attempt.
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "fail" ]
  run jq -r '.audit_report.reviewed_head' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "${heads[2]}" ]
}

# ─── DONE-review C3 finding fixes: escalation-terminal enforcement + ────────
# ─── loop-summary write-failure fail-closed (E-065-6_7) ─────────────────────
#
# A real live Codex DONE-review audit of this EPIC found: (1) nothing
# mechanically stopped a 4th (or Nth) explicit-attempt dispatch from
# proceeding after c3/loop-summary.json already recorded outcome:"escalated"
# — the bounded-loop requirement was documented in pipeline.md prose only,
# never enforced in code; (2) _c3_finalize_attempt swallowed a
# _c3_write_loop_summary failure with `|| true`, so a successful
# canonical-copy could report overall dispatch success (exit 0) even when
# the recheck/escalation audit trail was never actually written.

@test "escalation is terminal: a 4th dispatch after outcome==escalated is rejected without an override" {
  local heads=() bhs=()
  local i head bh
  for i in 1 2 3; do
    head="$(_commit_change "$i")"
    heads+=("$head")
    _build_manifest "$BASE_SHA" "$head"
    bh="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
    bhs+=("$bh")
    export FAKE_C3_HEAD="$head" FAKE_C3_BRIEF_HASH="$bh" FAKE_C3_THREAD_ID="thread-term-$i" \
           FAKE_C3_BLOCKING=true \
           FAKE_C3_FINDINGS='[{"severity":"high","area":"correctness","finding":"Still unchecked.","recommendation":"Fix it.","action_owner":"implementer"}]'
    AID_C3_ATTEMPT="$i" run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
    [ "$status" -eq 0 ]
  done
  run jq -r '.outcome' "$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ "$output" = "escalated" ]

  # A 4th attempt (no PM-authorized override) must be rejected BEFORE any
  # codex invocation or evidence write for attempt-04.
  local head4; head4="$(_commit_change 4)"
  _build_manifest "$BASE_SHA" "$head4"
  local bh4; bh4="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export FAKE_C3_HEAD="$head4" FAKE_C3_BRIEF_HASH="$bh4" FAKE_C3_THREAD_ID="thread-term-4" \
         FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'
  AID_C3_ATTEMPT=4 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"escalated"* ]]
  [ ! -d "$TEST_EVIDENCE_DIR/c3/attempt-04" ]

  # The loop-summary and canonical report are UNCHANGED by the rejected call.
  run jq -r '.outcome' "$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ "$output" = "escalated" ]
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "fail" ]

  # A short (< 20 char) override is ALSO rejected — the reason must be real.
  AID_C3_FORCE_BEYOND_ESCALATION="too short" AID_C3_ATTEMPT=4 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  # A genuine, >=20-char, PM-authorized override DOES let the 4th attempt through.
  AID_C3_FORCE_BEYOND_ESCALATION="PM approved a 4th recheck 2026-07-17 per manual review" \
    AID_C3_ATTEMPT=4 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -d "$TEST_EVIDENCE_DIR/c3/attempt-04" ]
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "pass" ]
}

@test "clean is ALSO terminal: a 2nd explicit dispatch after outcome==clean is rejected without an override" {
  # AC1's fixture (a single clean attempt-01) reaches loop-summary outcome
  # "clean" — pipeline.md 6a documents this as the exit-to-Curator terminal
  # state, exactly as symmetric to "escalated". A second live DONE-review
  # audit of this fix (E-065-6_7, round 2) found the round-1 fix only ever
  # checked for "escalated", leaving "clean" free to be silently overwritten
  # by an unbudgeted extra dispatch — this test proves that gap is now closed.
  local head1; head1="$(_commit_change 1)"
  _build_manifest "$BASE_SHA" "$head1"
  local bh1; bh1="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export FAKE_C3_HEAD="$head1" FAKE_C3_BRIEF_HASH="$bh1" FAKE_C3_THREAD_ID="thread-clean-term-1" \
         FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'
  AID_C3_ATTEMPT=1 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  run jq -r '.outcome' "$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ "$output" = "clean" ]

  # A 2nd attempt (no PM-authorized override) must be rejected BEFORE any
  # codex invocation or evidence write for attempt-02.
  local head2; head2="$(_commit_change 2)"
  _build_manifest "$BASE_SHA" "$head2"
  local bh2; bh2="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export FAKE_C3_HEAD="$head2" FAKE_C3_BRIEF_HASH="$bh2" FAKE_C3_THREAD_ID="thread-clean-term-2" \
         FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'
  AID_C3_ATTEMPT=2 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"clean"* ]]
  [ ! -d "$TEST_EVIDENCE_DIR/c3/attempt-02" ]

  # The loop-summary and canonical report are UNCHANGED by the rejected call.
  run jq -r '.outcome' "$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ "$output" = "clean" ]
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "pass" ]
  run jq -r '.audit_report.reviewed_head' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "$head1" ]

  # A short (< 20 char) override is ALSO rejected — the reason must be real.
  AID_C3_FORCE_BEYOND_ESCALATION="too short" AID_C3_ATTEMPT=2 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  # A genuine, >=20-char, PM-authorized override DOES let the 2nd attempt through.
  AID_C3_FORCE_BEYOND_ESCALATION="PM approved an extra recheck 2026-07-18 review" \
    AID_C3_ATTEMPT=2 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]
  [ -d "$TEST_EVIDENCE_DIR/c3/attempt-02" ]
  run jq -r '.audit_report.reviewed_head' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "$head2" ]
}

@test "true dispatch failure (codex unavailable) never advances recheck_count and stays retriable forever — the documented 'not a loop iteration' path is unaffected by the unverifiable-budget fix" {
  # A THIRD live DONE-review audit found that repeated genuinely-dispatched
  # attempts producing invalid/unverifiable CONTENT had no escalation cap
  # (unlike "fail"). Fixing that must NOT regress the orthogonal, explicitly
  # documented case this test proves: a dispatch that never even reaches
  # Codex (cross_provider unavailable) records outcome "unavailable" (not
  # "dispatched") in loop-summary.json's attempts[], so it is EXCLUDED from
  # dispatched_count/recheck_count — pipeline.md 6a's "Not a loop iteration"
  # — and must remain retriable without limit or override.
  export AID_C3_INDEPENDENCE_BIN="$TEST_TMPDIR/indep/always-fail"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$AID_C3_INDEPENDENCE_BIN"
  chmod +x "$AID_C3_INDEPENDENCE_BIN"

  local head1; head1="$(_commit_change 1)"
  _build_manifest "$BASE_SHA" "$head1"

  for i in 1 2 3 4; do
    AID_C3_ATTEMPT="$i" run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
    [ "$status" -eq 2 ]
  done

  run jq -r '[.attempts[].outcome] | unique | .[]' "$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ "$output" = "unavailable" ]
  run jq -r '.recheck_count' "$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ "$output" = "0" ]
  run jq -r '.outcome' "$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  [ "$output" = "unverifiable" ]

  # A 5th attempt is STILL accepted without any override — never terminal.
  AID_C3_ATTEMPT=5 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
}

@test "genuinely-dispatched-but-invalid-content attempts DO advance recheck_count and escalate at the policy budget, closing the round-3 gap" {
  # Distinguishes from the test above: here the codex CLI stream is well-formed
  # (a real dispatch, events_valid) but the report content fails provenance
  # validation each time (reviewed_head mismatch → _process_response writes an
  # unverifiable report) — attempts[].outcome=="dispatched" for every one of
  # these, so recheck_count DOES advance, and once it reaches max_rechecks
  # (default 2) the loop must escalate exactly like the "fail" path already
  # does, subjecting further attempts to the same terminal guard.
  local WRONG_HEAD="0000000000000000000000000000000000dead"
  local i head bh
  for i in 1 2 3; do
    head="$(_commit_change "$i")"
    _build_manifest "$BASE_SHA" "$head"
    bh="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
    # Deliberately WRONG reviewed_head → provenance mismatch → unverifiable
    # report, even though the dispatch itself is genuinely well-formed.
    export FAKE_C3_HEAD="$WRONG_HEAD" FAKE_C3_BRIEF_HASH="$bh" FAKE_C3_THREAD_ID="thread-inval-$i" \
           FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'
    AID_C3_ATTEMPT="$i" run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
    [ "$status" -eq 0 ]
  done

  local SUM="$TEST_EVIDENCE_DIR/c3/loop-summary.json"
  run jq -r '[.attempts[].outcome] | unique | .[]' "$SUM"
  [ "$output" = "dispatched" ]
  run jq -r '.recheck_count' "$SUM"
  [ "$output" = "2" ]
  run jq -r '.outcome' "$SUM"
  [ "$output" = "escalated" ]
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "unverifiable" ]

  # A 4th attempt (no override) is now rejected by the SAME terminal guard
  # rounds 1-2 built for "escalated" — no new code path, just a correctly
  # populated outcome field reaching it.
  local head4; head4="$(_commit_change 4)"
  _build_manifest "$BASE_SHA" "$head4"
  local bh4; bh4="$(jq -r '.audit_input_manifest.codex_brief_hash' "$TEST_EVIDENCE_DIR/audit-input-manifest.json")"
  export FAKE_C3_HEAD="$head4" FAKE_C3_BRIEF_HASH="$bh4" FAKE_C3_THREAD_ID="thread-inval-4" \
         FAKE_C3_BLOCKING=false FAKE_C3_FINDINGS='[]'
  AID_C3_ATTEMPT=4 run bash "$DISPATCH" dispatch "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"escalated"* ]]
}

@test "loop-summary write failure fails the whole attempt closed, even when the canonical report copy succeeded" {
  # Filesystem-permission injection cannot isolate JUST the loop-summary write
  # from a full `dispatch` CLI run: c3/attempt-NN/ and c3/loop-summary.json
  # are siblings under the same c3/ directory, and both must exist by the time
  # `mv` overwrites an existing DIRECTORY by moving into it rather than
  # failing (verified empirically), so a directory-collision trick doesn't
  # work either. Test the function directly instead: source the script and
  # call _c3_finalize_attempt with a real, valid, pre-built attempt_dir
  # (living OUTSIDE the evidence dir entirely, so its own construction is
  # unaffected by the permission change below) while evidence_dir/c3/ itself
  # is read-only — canonical-copy (a evidence_dir ROOT-level write) succeeds,
  # the loop-summary write (evidence_dir/c3/loop-summary.json, a NEW file in
  # a now-unwritable directory) genuinely fails.
  local head1; head1="$(_commit_change 1)"
  _build_manifest "$BASE_SHA" "$head1"

  local attempt_src="$TEST_TMPDIR/prebuilt-attempt-01"
  mkdir -p "$attempt_src"
  jq -n --arg h "$head1" \
    '{schema_version:"aid-2.0",artifact_type:"audit_report",status:"pass",
      audit_report:{review_status:"pass",blocking_findings:false,reviewed_head:$h}}' \
    > "$attempt_src/audit-report.json"
  printf '# report\n' > "$attempt_src/audit-report.md"

  mkdir -p "$TEST_EVIDENCE_DIR/c3"
  chmod 555 "$TEST_EVIDENCE_DIR/c3"

  # shellcheck disable=SC1090
  source "$DISPATCH"
  run _c3_finalize_attempt "$TEST_EVIDENCE_DIR" "$attempt_src" \
    "$TEST_EVIDENCE_DIR/audit-input-manifest.json" 1 "01" "thread-summary-fail" "$head1" dispatched
  chmod u+rwx "$TEST_EVIDENCE_DIR/c3"   # restore immediately for the assertions below

  [ "$status" -eq 1 ]
  [[ "$output" == *"FATAL"* ]]
  [[ "$output" == *"loop-summary.json"* ]]

  # The canonical report copy DID succeed (evidence_dir root stayed
  # writable) — but the function must not report overall success (rc 1
  # above) once the audit-trail write failed, and the canonical report was
  # stomped to unverifiable — NEVER left as a silently-successful "pass"
  # when the loop-summary write failed.
  run jq -r '.status' "$TEST_EVIDENCE_DIR/audit-report.json"
  [ "$output" = "unverifiable" ]
}
