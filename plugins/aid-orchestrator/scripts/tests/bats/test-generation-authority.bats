#!/usr/bin/env bats
# test-generation-authority.bats — P074 Step 13: CP1 runs ONCE per plan and the
# decision is sealed into a generation-authority receipt.
#
# THE GROUNDED FAILURE (F2, live 2026-08-04): aid-plan-to-epic.sh calls the CP1
# gate unconditionally PER INVOCATION and the gate's one-shot PM-override memo
# is function-local, so a 3-phase plan demanded 3 PM artifacts — worked around
# with a watcher, the anti-pattern §16a forbids normalizing. The pipeline now
# runs the gate once per plan, before any EPIC/plan.json/run/FSM/queue artifact
# exists, and seals the verdict (or the audited bypass) into a receipt bound to
# the exact plan bytes, target head and phase set.
#
# HONEST CLASSIFICATION (AID-v3 §1): the receipt is forgeable by a Bash-capable
# actor. What these tests pin is the BINDING and the AUDIT — not any claim of
# actor impossibility.
#
# GATE CALL COUNTING. The CP1 gate is resolved through the calling script's own
# SCRIPT_DIR, so counting invocations needs a shadow plugin: a directory of
# SYMLINKS to the real scripts/defaults with ONE real file substituted — the
# counting stub for aid-cp1-gate.sh. Symlinks, not a 32 MB copy, so setup stays
# cheap. Every other script is byte-identical to the shipped one.
#
# FD-3 HYGIENE: bats reports results over fd 3; a child holding it open
# truncates the suite's TAP output. Every pipeline invocation runs with `3>&-`.
# A `run` whose command is MISSING exits 127 and bats writes a warning to fd 3
# — with fd 3 closed that destroys the whole file's output, so no `run` here is
# ever handed a path that might not exist.
# After any edit, verify the result count:
#   bats --tap test-generation-authority.bats | grep -cE '^(ok|not ok)'   # == 11

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  REPO_PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FIXTURES="$REPO_PLUGIN/scripts/tests/fixtures"
  TEST_TMPDIR="$(mktemp -d)"
  export REPO_PLUGIN FIXTURES TEST_TMPDIR
  unset AID_PROJECT_ROOT AID_PLAN_STATE_PROJECT_ROOT AID_PLAN_MANIFEST_PROJECT_ROOT
  unset AID_TEST_CP1_FAIL
  _mk_shadow
  CP1_COUNT="$TEST_TMPDIR/cp1.count"; : > "$CP1_COUNT"
  export CP1_COUNT
  export AID_TEST_CP1_COUNTER="$CP1_COUNT"
  REASON="the PM accepts this bypass because the blocking condition is a known false positive"
  export REASON
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# _mk_shadow — symlink farm over the real plugin with a counting CP1 stub.
_mk_shadow() {
  SHADOW="$TEST_TMPDIR/plugin"
  mkdir -p "$SHADOW/scripts"
  local f b
  for f in "$REPO_PLUGIN/scripts"/*; do
    b="$(basename "$f")"
    [[ "$b" == "tests" ]] && continue
    ln -s "$f" "$SHADOW/scripts/$b"
  done
  ln -s "$REPO_PLUGIN/defaults" "$SHADOW/defaults"
  rm -f "$SHADOW/scripts/aid-cp1-gate.sh"
  cat > "$SHADOW/scripts/aid-cp1-gate.sh" <<'STUB'
#!/usr/bin/env bash
# Counting stub for the CP1 gate. AID_TEST_CP1_FAIL stands in for any blocking
# condition the real gate reports (unresolved accepted blockers, a blocking C0
# cross-provider plan review, an exhausted CP1 ledger budget) — which of them
# fired is the real gate's own suite's business, not this one's.
[[ -n "${AID_TEST_CP1_COUNTER:-}" ]] && printf 'call\n' >> "$AID_TEST_CP1_COUNTER"
if [[ -n "${AID_TEST_CP1_FAIL:-}" ]]; then
  echo "CP1 GATE FAIL: blocking C0 plan review with surviving blocking findings" >&2
  exit 1
fi
echo "CP1 GATE: low-risk plan, no CP1-deep evidence required"
exit 0
STUB
  chmod +x "$SHADOW/scripts/aid-cp1-gate.sh"
  PIPELINE="$SHADOW/scripts/aid-auto-pipeline.sh"
  export SHADOW PIPELINE
}

# _mk_project <dir> — a committed AID workspace with .aid-o gitignored.
_mk_project() {
  local d="$1"
  mkdir -p "$d/.aid-o/plans" "$d/.aid-o/tasks" "$d/.aid-o/config" \
           "$d/.aid-o/work/evidence" "$d/.aid-o/work/runs"
  printf 'counter: 0\n' > "$d/.aid-o/config/counter.yaml"
  printf '.aid-o/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed"
  )
}

_seed_plan() {   # <project> [risk]
  local d="$1" risk="${2:-}"
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$d/.aid-o/plans/P099-multi.md"
  if [[ -n "$risk" ]]; then
    sed -i "0,/^author: /s//risk: ${risk}\nauthor: /" "$d/.aid-o/plans/P099-multi.md"
  fi
  printf '%s\n' "$d/.aid-o/plans/P099-multi.md"
}

_auth() { printf '%s\n' "$1/.aid-o/work/evidence/P099/generation/generation-authority.json"; }
_cp1_calls() { wc -l < "$CP1_COUNT" | tr -d ' '; }

# ─── the happy path: a sealed, verdict-bearing authority ─────────────────

@test "a passing plan writes a verdict-bearing authority bound to plan bytes, target head and phase set" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$plan' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]

  local a; a="$(_auth "$TEST_TMPDIR/p")"
  [ -f "$a" ]
  [ "$(jq -r '.schema' "$a")" = "aid-generation-authority/v1" ]
  [ "$(jq -r '.cp1.verdict' "$a")" = "pass" ]
  [ "$(jq -r '.forced_override' "$a")" = "false" ]
  [ "$(jq -r '.total_phases' "$a")" = "3" ]
  [ "$(jq -r '.phase_derivation_version' "$a")" = "1" ]
  # Bound to the EXACT plan bytes and the target head, not to a name.
  [ "$(jq -r '.plan_sha256' "$a")" = "$(sha256sum "$plan" | awk '{print $1}')" ]
  [ "$(jq -r '.target_head' "$a")" = "$(git -C "$TEST_TMPDIR/p" rev-parse main)" ]
}

@test "the authority's self_sha256 is the canonical-JSON hash of itself with the field nulled" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$plan' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  local a; a="$(_auth "$TEST_TMPDIR/p")"
  local recorded computed
  recorded="$(jq -r '.self_sha256' "$a")"
  computed="$(jq -S -c '.self_sha256 = null' "$a" | sha256sum | awk '{print $1}')"
  [ "$recorded" = "$computed" ]
}

@test "the CP1 gate is invoked EXACTLY ONCE for a 3-phase plan (the F2 regression)" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$plan' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  # Three phases were really generated (counted on disk — `run` merges stderr
  # into $output, so the stdout manifest is not parseable from here)...
  [ "$(ls "$TEST_TMPDIR/p/.aid-o/tasks"/E-099-*.md | wc -l | tr -d ' ')" = "3" ]
  # ...and the gate ran once, not once per phase.
  [ "$(_cp1_calls)" = "1" ]
}

# ─── the blocked path ────────────────────────────────────────────────────

@test "a blocked gate without --force refuses, prints the exact public force command, and generates nothing" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && AID_TEST_CP1_FAIL=1 bash '$PIPELINE' --plan '$plan' --queue-mode chain" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"aid_cp1_blocked"* ]]
  [[ "$output" == *"--force --reason"* ]]
  # No authority was sealed and no EPIC exists.
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/tasks'/E-099-*.md 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "--force without --reason, and with a short reason, both die with the P073-consistent message" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$plan' --force" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$plan' --force --reason 'too short'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  [[ "$output" == *"forensic record"* ]]
  # A reason without a force records nothing and is refused rather than ignored.
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$plan' --reason '$REASON'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"without --force"* ]]
}

@test "a blocked gate WITH --force --reason writes a forced authority plus all three P073 audit records" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && AID_TEST_CP1_FAIL=1 bash '$PIPELINE' --plan '$plan' --queue-mode chain --force --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]

  local gen="$TEST_TMPDIR/p/.aid-o/work/evidence/P099/generation"
  # Record 0 — the authority itself records the bypass and every failed condition.
  [ "$(jq -r '.forced_override' "$gen/generation-authority.json")" = "true" ]
  [ "$(jq -r '.force_reason' "$gen/generation-authority.json")" = "$REASON" ]
  [[ "$(jq -r '.cp1.bypassed_conditions | join(" ")' "$gen/generation-authority.json")" == *"blocking C0 plan review"* ]]
  [ "$(jq -r '.cp1.verdict // "none"' "$gen/generation-authority.json")" = "none" ]

  # Record 1 — the HEAD-bound protocol-v2 waiver artifact (authoritative).
  local w; w="$(ls "$gen"/waiver-generation-*.json | head -1)"
  [ -n "$w" ]
  [ "$(jq -r '.artifact_type' "$w")" = "waiver" ]
  [ "$(jq -r '.forced_override' "$w")" = "true" ]
  [ "$(jq -r '.records' "$w")" = "precondition_bypass" ]
  [ "$(jq -r '.actor_semantics' "$w")" = "instruction_only" ]
  [ "$(jq -r '.revision.head_sha' "$w")" = "$(git -C "$TEST_TMPDIR/p" rev-parse HEAD)" ]
  [ "$(jq -r '.bypassed_preconditions | length' "$w")" -ge 1 ]

  # Record 2 — the timeline event.
  grep -q '"event":"generation_force_override"' "$gen/timeline.jsonl"
  # Record 3 — the cross-plan audit log.
  grep -q 'generation_force_override' "$TEST_TMPDIR/p/.aid-o/work/audit-log.jsonl"
}

@test "a forced run leaves the CP1 artifacts on disk BYTE-IDENTICAL (they are never rewritten as clean)" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  local ev="$TEST_TMPDIR/p/.aid-o/work/evidence/P099"
  mkdir -p "$ev/cp1-deep"
  printf 'stop_rule_blockers:\n- a real blocker\n' > "$ev/cp1-deep/cp1-lens-L1-behavior.md"
  printf 'verdict: revise\naccepted_blockers:\n- a real blocker\n'  > "$ev/cp1-deep/cp1-adjudicator.md"
  printf '{"review_status":"verified","blocking_findings":true}\n'  > "$ev/c0-plan-review.json"
  local before; before="$(find "$ev/cp1-deep" "$ev/c0-plan-review.json" -type f -exec sha256sum {} \; | sort)"

  run bash -c "cd '$TEST_TMPDIR/p' && AID_TEST_CP1_FAIL=1 bash '$PIPELINE' --plan '$plan' --queue-mode chain --force --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]

  local after; after="$(find "$ev/cp1-deep" "$ev/c0-plan-review.json" -type f -exec sha256sum {} \; | sort)"
  [ "$before" = "$after" ]
  # The bypass is recorded, and the evidence is referenced with its hash at
  # decision time rather than edited.
  [[ "$(jq -r '.cp1.evidence_refs[].path' "$(_auth "$TEST_TMPDIR/p")" | tr '\n' ' ')" == *"c0-plan-review.json"* ]]
}

@test "AUDIT-BEFORE-AUTHORITY: an unwritable audit log aborts the forced run and leaves NO authority behind" {
  # Codex round, BLOCKER 1. The first cut wrote the authority first and treated
  # the audit-log append as best-effort, so an I/O error (or a kill) between
  # them left a valid `forced_override: true` authority with no P073 trail —
  # and resume ACCEPTS a valid authority without re-consulting the gate, making
  # the bypass permanent and invisible. No kill is needed to reach that window
  # any more: the records come first and are fail-closed, so an unwritable
  # audit path fails the run right there.
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  # A DIRECTORY where the append expects a file: the write genuinely fails, and
  # aid-audit-log.sh swallows its own failure by design, so only the read-back
  # verification can catch it.
  mkdir -p "$TEST_TMPDIR/p/.aid-o/work/audit-log.jsonl"

  run bash -c "cd '$TEST_TMPDIR/p' && AID_TEST_CP1_FAIL=1 bash '$PIPELINE' --plan '$plan' --queue-mode chain --force --reason '$REASON'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not be read back"* ]]
  [[ "$output" == *"no authority was sealed"* ]]
  # THE POINT: no authority, so no later run can inherit an unrecorded bypass.
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  # And the half-written waiver was rolled back rather than left as a decoy.
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/work/evidence/P099/generation'/waiver-generation-*.json 2>/dev/null | wc -l"
  [ "$output" = "0" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/tasks'/E-099-*.md 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "AUDIT-BEFORE-AUTHORITY: an unwritable timeline aborts the forced run and leaves NO authority behind" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  local gen="$TEST_TMPDIR/p/.aid-o/work/evidence/P099/generation"
  mkdir -p "$gen/timeline.jsonl"    # a directory: the append cannot succeed

  run bash -c "cd '$TEST_TMPDIR/p' && AID_TEST_CP1_FAIL=1 bash '$PIPELINE' --plan '$plan' --queue-mode chain --force --reason '$REASON'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"timeline event"* ]]
  [[ "$output" == *"No authority was sealed"* ]]
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  run bash -c "ls '$gen'/waiver-generation-*.json 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "--force on a plan whose gate PASSES is recorded as UNUSED: no waiver, nothing claimed as bypassed" {
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$plan' --queue-mode chain --force --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]
  local gen="$TEST_TMPDIR/p/.aid-o/work/evidence/P099/generation"
  [ "$(jq -r '.forced_override' "$gen/generation-authority.json")" = "false" ]
  [ "$(jq -r '.cp1.force_unused' "$gen/generation-authority.json")" = "true" ]
  # A receipt for nothing would be noise in waivers_applied[] — none is written.
  run bash -c "ls '$gen'/waiver-generation-*.json 2>/dev/null | wc -l"
  [ "$output" = "0" ]
  grep -q '"force_unused":true' "$gen/timeline.jsonl"
}

# ─── the REAL gate, not the stub: the wiring is genuinely live ────────────

@test "with the REAL (unstubbed) gate a high-risk plan missing CP1 evidence is blocked before any EPIC exists" {
  # The stub proves counting and audit shape; this proves the pipeline really
  # calls the shipped gate and honours its refusal.
  _mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p" high)"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$REPO_PLUGIN/scripts/aid-auto-pipeline.sh' --plan '$plan' --queue-mode chain" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"aid_cp1_blocked"* ]]
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/tasks'/E-099-*.md 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}
