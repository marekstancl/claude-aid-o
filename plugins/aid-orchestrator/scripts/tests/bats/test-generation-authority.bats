#!/usr/bin/env bats
# aid-tier: t2
# test-generation-authority.bats — P074 Step 13, on the direct path since P114
# (3.0.0): CP1 is consulted ONCE per plan and the decision is sealed into a
# generation-authority receipt by `plan-run` (lib/aid-generation-authority.sh
# aid_gen_seal), before any run state exists.
#
# HONEST CLASSIFICATION (AID-v3 §1): the receipt is forgeable by a Bash-capable
# actor. What these tests pin is the BINDING and the AUDIT — not any claim of
# actor impossibility.
#
# GATE CALL COUNTING. The CP1 gate is resolved through the calling script's own
# SCRIPT_DIR, so counting invocations needs a shadow plugin: a directory of
# SYMLINKS to the real scripts/defaults with ONE real file substituted — the
# counting stub for aid-cp1-gate.sh.
#
# FD-3 HYGIENE: every plan-run invocation runs with `3>&-`.

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  REPO_PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FIXTURES="$REPO_PLUGIN/scripts/tests/fixtures"
  TEST_TMPDIR="$(mktemp -d)"; export REPO_PLUGIN FIXTURES TEST_TMPDIR
  unset AID_PROJECT_ROOT AID_PLAN_STATE_PROJECT_ROOT AID_PLAN_MANIFEST_PROJECT_ROOT AID_TEST_CP1_FAIL
  # the shadow plugin: symlinks, with aid-cp1-gate.sh replaced by the counting stub
  SHADOW="$TEST_TMPDIR/plugin"; mkdir -p "$SHADOW/scripts"
  local f b
  for f in "$REPO_PLUGIN/scripts"/*; do b="$(basename "$f")"; [[ "$b" == tests ]] || ln -s "$f" "$SHADOW/scripts/$b"; done
  ln -s "$REPO_PLUGIN/defaults" "$SHADOW/defaults"
  rm -f "$SHADOW/scripts/aid-cp1-gate.sh"
  cat > "$SHADOW/scripts/aid-cp1-gate.sh" <<'STUB'
#!/usr/bin/env bash
[[ -n "${AID_TEST_CP1_COUNTER:-}" ]] && printf 'call\n' >> "$AID_TEST_CP1_COUNTER"
if [[ -n "${AID_TEST_CP1_FAIL:-}" ]]; then
  echo "CP1-gate FAIL: round-1 left 1 blocker(s) open and there is no round-2" >&2
  exit 1
fi
echo "CP1-gate: plan PASS — round 1 closed"
exit 0
STUB
  chmod +x "$SHADOW/scripts/aid-cp1-gate.sh"
  PFSM="$SHADOW/scripts/aid-plan-fsm.sh"
  CP1_COUNT="$TEST_TMPDIR/cp1.count"; : > "$CP1_COUNT"; export AID_TEST_CP1_COUNTER="$CP1_COUNT"
  REASON="the PM accepts this bypass because the blocking condition is a known false positive"
  export REASON SHADOW PFSM
}

teardown() { cd /; [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"; }

_cp1_calls() { wc -l < "$CP1_COUNT" | tr -d ' '; }

# _seed_plan <project> — a git project with the direct fixture plan bound to its
# brief and a closed CP1 round (the shared seeder of test-plan-run.bats).
_seed_plan() {
  local d="$1"
  mkdir -p "$d" && git -C "$d" init -q -b main && git -C "$d" config user.email t@t && git -C "$d" config user.name t
  mkdir -p "$d/src/core" "$d/prirucka" "$d/.aid-o/config"
  echo "def tally(i): pass" > "$d/src/core/counter.py"; echo "# Příručka" > "$d/prirucka/README.md"
  printf 'gates:\n  docs_updated:\n    command: "true"\n' > "$d/.aid-o/config/execution.yaml"
  git -C "$d" add -A && git -C "$d" commit -qm init
  ( export AID_PLUGIN_PATH="$REPO_PLUGIN"; source "$REPO_PLUGIN/scripts/tests/lib/aid-test-plan-fixture.sh"
    aid_fixture_seed_plan "$d" "$FIXTURES/plan-direct-two-step.md" P900-direct.md >/dev/null )
  printf '%s\n' "$d/.aid-o/plans/P900-direct.md"
}
_run_pr() { run bash -c "cd '$TEST_TMPDIR/p' && $* bash '$PFSM' plan-run P900 ${PR_ARGS:-}" 3>&-; }
_state() { printf '%s\n' "$TEST_TMPDIR/p/.aid-o/work/evidence/E-900-1_1/R-E900-1/fsm-state.yaml"; }

_auth() { printf '%s\n' "$1/.aid-o/work/evidence/P900/generation/generation-authority.json"; }

# ─── the happy path: a sealed, verdict-bearing authority ─────────────────

@test "a passing plan writes a verdict-bearing authority bound to plan bytes, target head and phase set" {
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  _run_pr
  [ "$status" -eq 0 ]

  local a; a="$(_auth "$TEST_TMPDIR/p")"
  [ -f "$a" ]
  [ "$(jq -r '.schema' "$a")" = "aid-generation-authority/v1" ]
  [ "$(jq -r '.cp1.verdict' "$a")" = "pass" ]
  [ "$(jq -r '.forced_override' "$a")" = "false" ]
  [ "$(jq -r '.total_phases' "$a")" = "1" ]   # one run per plan (P111)
  [ "$(jq -r '.phase_derivation_version' "$a")" = "1" ]
  # Bound to the EXACT plan bytes and the target head, not to a name.
  [ "$(jq -r '.plan_sha256' "$a")" = "$(sha256sum "$plan" | awk '{print $1}')" ]
  [ "$(jq -r '.target_head' "$a")" = "$(git -C "$TEST_TMPDIR/p" rev-parse main)" ]
}

@test "the authority's self_sha256 is the canonical-JSON hash of itself with the field nulled" {
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  _run_pr
  [ "$status" -eq 0 ]
  local a; a="$(_auth "$TEST_TMPDIR/p")"
  local recorded computed
  recorded="$(jq -r '.self_sha256' "$a")"
  computed="$(jq -S -c '.self_sha256 = null' "$a" | sha256sum | awk '{print $1}')"
  [ "$recorded" = "$computed" ]
}

@test "the CP1 gate is invoked EXACTLY ONCE per plan (the F2 regression)" {
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  _run_pr
  [ "$status" -eq 0 ]
  [ -f "$(_state)" ]
  [ "$(_cp1_calls)" = "1" ]
}

# ─── the blocked path ────────────────────────────────────────────────────

@test "a blocked gate without --force refuses, prints the exact public force command, and generates nothing" {
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  _run_pr AID_TEST_CP1_FAIL=1
  [ "$status" -ne 0 ]
  # P074 Step 18 relabelled this class: the stub's rc-1 refusal IS a CP1
  # condition verdict, which a deliberate --force CAN cover, so the honest
  # label is the force-required one. `aid_cp1_blocked` is now reserved for
  # refusals --force would NOT unblock (see test-generation-labels.bats).
  [[ "$output" == *"aid_generation_force_required"* ]]
  [[ "$output" == *"--force --reason"* ]]
  # No authority was sealed and no EPIC exists.
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/tasks'/E-900-*.md 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "--force without --reason, and with a short reason, both die with the P073-consistent message" {
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  PR_ARGS="--force" _run_pr
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  PR_ARGS="--force --reason 'too short'" _run_pr
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  # A reason without a force records nothing and is refused rather than ignored.
  PR_ARGS="--reason '$REASON'" _run_pr
  [ "$status" -ne 0 ]
  [[ "$output" == *"without --force"* ]]
}

@test "a blocked gate WITH --force --reason writes a forced authority plus all three P073 audit records" {
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  PR_ARGS="--force --reason '$REASON'" _run_pr AID_TEST_CP1_FAIL=1
  [ "$status" -eq 0 ]

  local gen="$TEST_TMPDIR/p/.aid-o/work/evidence/P900/generation"
  # Record 0 — the authority itself records the bypass and every failed condition.
  [ "$(jq -r '.forced_override' "$gen/generation-authority.json")" = "true" ]
  [ "$(jq -r '.force_reason' "$gen/generation-authority.json")" = "$REASON" ]
  [[ "$(jq -r '.cp1.bypassed_conditions | join(" ")' "$gen/generation-authority.json")" == *"no round-2"* ]]
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
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  local ev="$TEST_TMPDIR/p/.aid-o/work/evidence/P900"
  # A round that left a blocker open: the evidence a forced run bypasses.
  jq '.findings = [{fingerprint: "f", step: 1, severity: "blocker", claim: "a real blocker", status: "open", reported_by: ["reuse"]}] | .blockers_open = 1' \
    "$ev/cp1/round-1/merged.json" > "$ev/m" && mv "$ev/m" "$ev/cp1/round-1/merged.json"
  local before; before="$(find "$ev/cp1" -type f -exec sha256sum {} \; | sort)"

  PR_ARGS="--force --reason '$REASON'" _run_pr AID_TEST_CP1_FAIL=1
  [ "$status" -eq 0 ]

  local after; after="$(find "$ev/cp1" -type f -exec sha256sum {} \; | sort)"
  [ "$before" = "$after" ]
  # The bypass is recorded, and the evidence is referenced with its hash at
  # decision time rather than edited.
  [[ "$(jq -r '.cp1.evidence_refs[].path' "$(_auth "$TEST_TMPDIR/p")" | tr '\n' ' ')" == *"cp1/rounds.json"* ]]
  [ "$(jq -r '.cp1.evidence_refs[0].sha256' "$(_auth "$TEST_TMPDIR/p")")" != null ]
}

@test "AUDIT-BEFORE-AUTHORITY: an unwritable audit log aborts the forced run and leaves NO authority behind" {
  # An implementation that writes the authority first and treats
  # the audit-log append as best-effort, so an I/O error (or a kill) between
  # them left a valid `forced_override: true` authority with no P073 trail —
  # and resume ACCEPTS a valid authority without re-consulting the gate, making
  # the bypass permanent and invisible. No kill is needed to reach that window
  # any more: the records come first and are fail-closed, so an unwritable
  # audit path fails the run right there.
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  # A DIRECTORY where the append expects a file: the write genuinely fails, and
  # aid-audit-log.sh swallows its own failure by design, so only the read-back
  # verification can catch it.
  mkdir -p "$TEST_TMPDIR/p/.aid-o/work/audit-log.jsonl"

  PR_ARGS="--force --reason '$REASON'" _run_pr AID_TEST_CP1_FAIL=1
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not be read back"* ]]
  [[ "$output" == *"no authority was sealed"* ]]
  # THE POINT: no authority, so no later run can inherit an unrecorded bypass.
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  # And the half-written waiver was rolled back rather than left as a decoy.
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/work/evidence/P900/generation'/waiver-generation-*.json 2>/dev/null | wc -l"
  [ "$output" = "0" ]
  run bash -c "ls '$TEST_TMPDIR/p/.aid-o/tasks'/E-900-*.md 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "AUDIT-BEFORE-AUTHORITY: an unwritable timeline aborts the forced run and leaves NO authority behind" {
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  local gen="$TEST_TMPDIR/p/.aid-o/work/evidence/P900/generation"
  mkdir -p "$gen/timeline.jsonl"    # a directory: the append cannot succeed

  PR_ARGS="--force --reason '$REASON'" _run_pr AID_TEST_CP1_FAIL=1
  [ "$status" -ne 0 ]
  [[ "$output" == *"timeline event"* ]]
  [[ "$output" == *"No authority was sealed"* ]]
  [ ! -f "$(_auth "$TEST_TMPDIR/p")" ]
  run bash -c "ls '$gen'/waiver-generation-*.json 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "--force on a plan whose gate PASSES is recorded as UNUSED: no waiver, nothing claimed as bypassed" {
  local plan; plan="$(_seed_plan "$TEST_TMPDIR/p")"
  PR_ARGS="--force --reason '$REASON'" _run_pr
  [ "$status" -eq 0 ]
  local gen="$TEST_TMPDIR/p/.aid-o/work/evidence/P900/generation"
  [ "$(jq -r '.forced_override' "$gen/generation-authority.json")" = "false" ]
  [ "$(jq -r '.cp1.force_unused' "$gen/generation-authority.json")" = "true" ]
  # A receipt for nothing would be noise in waivers_applied[] — none is written.
  run bash -c "ls '$gen'/waiver-generation-*.json 2>/dev/null | wc -l"
  [ "$output" = "0" ]
  grep -q '"force_unused":true' "$gen/timeline.jsonl"
}

# The REAL (unstubbed) gate refusing a plan without a review round is pinned
# by test-plan-run.bats ("a plan without a passed CP1 round is refused by the gate").
