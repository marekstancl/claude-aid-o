#!/usr/bin/env bats
# aid-tier: t2
# test-generation-authority.bats — P074 Step 13: CP1 runs ONCE per plan and the
# decision is sealed into a generation-authority receipt.
#
# THE FAILURE THIS PINS, observed live on 2026-08-04: aid-plan-to-epic.sh calls the CP1
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
load generation-fixture.bash

setup() {
  gen_setup
  gen_shadow_farm
  gen_cp1_counting_stub
  REASON="the PM accepts this bypass because the blocking condition is a known false positive"
  export REASON
}

teardown() { gen_teardown; }

_seed_plan() {   # <project> [risk]
  local d="$1" risk="${2:-}"
  # THE shared seeder (scripts/tests/aid-fixture-plan.sh): it satisfies every
  # generation precondition at once — execution.yaml, the plan committed, the PM
  # page rendered — so the next precondition is one edit there and not fifteen
  # here. A `risk:` variant re-seeds afterwards, because editing the plan makes
  # its page STALE and the obligation refuses a page older than its plan.
  aid_fixture_seed_plan "$d" "$FIXTURES/multi-phase-plan-numeric.md" P099-multi.md >/dev/null
  if [[ -n "$risk" ]]; then
    sed -i "0,/^author: /s//risk: ${risk}\nauthor: /" "$d/.aid-o/plans/P099-multi.md"
    aid_fixture_seed_plan "$d" "$d/.aid-o/plans/P099-multi.md" P099-multi.md >/dev/null
  fi
  printf '%s\n' "$d/.aid-o/plans/P099-multi.md"
}

_auth() { printf '%s\n' "$1/.aid-o/work/evidence/P099/generation/generation-authority.json"; }

# ─── the happy path: a sealed, verdict-bearing authority ─────────────────

@test "a passing plan writes a verdict-bearing authority bound to plan bytes, target head and phase set" {
  gen_mk_project "$TEST_TMPDIR/p"
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
  gen_mk_project "$TEST_TMPDIR/p"
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
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$plan' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  # Three phases were really generated (counted on disk — `run` merges stderr
  # into $output, so the stdout manifest is not parseable from here)...
  [ "$(ls "$TEST_TMPDIR/p/.aid-o/tasks"/E-099-*.md | wc -l | tr -d ' ')" = "3" ]
  # ...and the gate ran once, not once per phase.
  [ "$(gen_cp1_calls)" = "1" ]
}

# ─── the blocked path ────────────────────────────────────────────────────

@test "a blocked gate without --force refuses, prints the exact public force command, and generates nothing" {
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  run bash -c "cd '$TEST_TMPDIR/p' && AID_TEST_CP1_FAIL=1 bash '$PIPELINE' --plan '$plan' --queue-mode chain" 3>&-
  [ "$status" -ne 0 ]
  # P074 Step 18 relabelled this class: the stub's rc-1 refusal IS a CP1
  # condition verdict, which a deliberate --force CAN cover, so the honest
  # label is the force-required one. `aid_cp1_blocked` is now reserved for
  # refusals --force would NOT unblock (see test-generation-labels.bats).
  [[ "$output" == *"aid_generation_force_required"* ]]
  [[ "$output" == *"--force --reason"* ]]
  # No authority was sealed and no EPIC exists.
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/tasks'/E-099-*.md 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "--force without --reason, and with a short reason, both die with the P073-consistent message" {
  gen_mk_project "$TEST_TMPDIR/p"
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
  gen_mk_project "$TEST_TMPDIR/p"
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
  gen_mk_project "$TEST_TMPDIR/p"
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
  # An implementation that writes the authority first and treats
  # the audit-log append as best-effort, so an I/O error (or a kill) between
  # them left a valid `forced_override: true` authority with no P073 trail —
  # and resume ACCEPTS a valid authority without re-consulting the gate, making
  # the bypass permanent and invisible. No kill is needed to reach that window
  # any more: the records come first and are fail-closed, so an unwritable
  # audit path fails the run right there.
  gen_mk_project "$TEST_TMPDIR/p"
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
  gen_mk_project "$TEST_TMPDIR/p"
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
  gen_mk_project "$TEST_TMPDIR/p"
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
  gen_mk_project "$TEST_TMPDIR/p"
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p" high)"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$REPO_PLUGIN/scripts/aid-auto-pipeline.sh' --plan '$plan' --queue-mode chain" 3>&-
  [ "$status" -ne 0 ]
  # Missing CP1-deep evidence is the REAL gate's rc-1 condition verdict, so
  # P074 Step 18 labels it force-required, not hard-blocked.
  [[ "$output" == *"aid_generation_force_required"* ]]
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/tasks'/E-099-*.md 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}
