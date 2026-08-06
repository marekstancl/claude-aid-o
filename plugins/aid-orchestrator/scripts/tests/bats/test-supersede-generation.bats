#!/usr/bin/env bats
# test-supersede-generation.bats — P074 Step 16: PM recovery for an incomplete
# generation transaction.
#
# WHY IT IS A SEPARATE INVOCATION: a differing identity plainly REFUSES inside
# the pipeline (Step 15); archiving is a deliberate, separate act with its own
# audited reason. Mixing the two would make "regenerate" quietly discard a
# record of what was already produced.
#
# WHAT IT DOES NOT DO: it deletes nothing. Already-created EPIC files, task
# branches and queue entries stay exactly where they are, and cleanup remains
# with the lifecycle-safe recovery paths (`plan-rollback`, queue removal). That
# mirrors §16a's cancellation contract: record what was generated, never
# improvise destructive cleanup.
#
# ACTOR RULE, honestly classified (AID-v3 §1): "PM-only" is INSTRUCTION-ONLY —
# nothing distinguishes a PM from an agent at this boundary. The audit record
# IS the enforcement surface, which is why these tests pin the record, not an
# imaginary identity check.
#
# FD-3 HYGIENE: every pipeline invocation runs with `3>&-`; no `run` is handed
# a path that might not exist.
# After any edit, verify the result count:
#   bats --tap test-supersede-generation.bats | grep -cE '^(ok|not ok)'   # == 9

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  REPO_PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FIXTURES="$REPO_PLUGIN/scripts/tests/fixtures"
  TEST_TMPDIR="$(mktemp -d)"
  export REPO_PLUGIN FIXTURES TEST_TMPDIR
  unset AID_PROJECT_ROOT AID_PLAN_STATE_PROJECT_ROOT AID_PLAN_MANIFEST_PROJECT_ROOT
  _mk_shadow
  CP1_COUNT="$TEST_TMPDIR/cp1.count"; : > "$CP1_COUNT"
  export CP1_COUNT
  export AID_TEST_CP1_COUNTER="$CP1_COUNT"
  PROJ="$TEST_TMPDIR/p"
  _mk_project "$PROJ"
  PLAN="$PROJ/.aid-o/plans/P099-multi.md"
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$PLAN"
  GEN="$PROJ/.aid-o/work/evidence/P099/generation"
  TX="$GEN/transaction.json"
  AUTH="$GEN/generation-authority.json"
  REASON="the plan changed mid-generation and the PM accepts archiving the incomplete run"
  export PROJ PLAN GEN TX AUTH REASON
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

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
[[ -n "${AID_TEST_CP1_COUNTER:-}" ]] && printf 'call\n' >> "$AID_TEST_CP1_COUNTER"
echo "CP1 GATE: low-risk plan, no CP1-deep evidence required"
exit 0
STUB
  chmod +x "$SHADOW/scripts/aid-cp1-gate.sh"
  PIPELINE="$SHADOW/scripts/aid-auto-pipeline.sh"
  export SHADOW PIPELINE
}

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

_run_pipeline() { ( cd "$PROJ" && bash "$PIPELINE" --plan "$PLAN" --queue-mode chain 3>&- ); }

# _incomplete — a real, generated-then-crashed transaction: every phase exists
# on disk, but the receipt's queue-status rewrite never happened, which is
# exactly what makes a transaction INCOMPLETE.
_incomplete() {
  local out rc=0
  out="$(_run_pipeline 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || { echo "$out" >&2; return 1; }
  rm -f "$GEN/receipt.json"
}

# ─── the archive ─────────────────────────────────────────────────────────

@test "supersede archives BOTH files under one shared epoch and writes the audit record" {
  _incomplete
  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]

  # Live paths are clear; the pair is archived under ONE epoch.
  [ ! -f "$TX" ]
  [ ! -f "$AUTH" ]
  local ta aa epoch
  ta="$(ls "$GEN"/transaction.json.superseded-* | head -1)"
  aa="$(ls "$GEN"/generation-authority.json.superseded-* | head -1)"
  [ -n "$ta" ] && [ -n "$aa" ]
  epoch="${ta##*.superseded-}"
  [ "$epoch" = "${aa##*.superseded-}" ]

  # The audit record carries the reason, both identities, and both post-rename
  # paths with their hashes.
  local rec="$GEN/generation-superseded-${epoch}.json"
  [ -f "$rec" ]
  [ "$(jq -r '.reason' "$rec")" = "$REASON" ]
  [ "$(jq -r '.archived_transaction' "$rec")" = "$ta" ]
  [ "$(jq -r '.archived_authority' "$rec")" = "$aa" ]
  [ "$(jq -r '.transaction_sha256' "$rec")" = "$(sha256sum "$ta" | awk '{print $1}')" ]
  [ "$(jq -r '.authority_sha256' "$rec")" = "$(sha256sum "$aa" | awk '{print $1}')" ]
  [ -n "$(jq -r '.archived_identity' "$rec")" ]
  [ -n "$(jq -r '.current_identity' "$rec")" ]
  [ "$(jq -r '.deletes_nothing' "$rec")" = "true" ]
  [ "$(jq -r '.actor_semantics' "$rec")" = "instruction_only" ]

  # Records 2 and 3 of the P073 pattern.
  grep -q '"event":"generation_superseded"' "$GEN/timeline.jsonl"
  grep -q 'generation_superseded' "$PROJ/.aid-o/work/audit-log.jsonl"
}

@test "supersede DELETES NOTHING: every generated EPIC, plan.json and queue entry survives" {
  _incomplete
  local epics_before queue_before
  epics_before="$(ls "$PROJ/.aid-o/tasks"/E-099-*.md | wc -l | tr -d ' ')"
  queue_before="$(grep -c 'epic_id: "E-099' "$PROJ/.aid-o/config/queue.yaml")"
  [ "$epics_before" = "3" ]

  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]
  [ "$(ls "$PROJ/.aid-o/tasks"/E-099-*.md | wc -l | tr -d ' ')" = "$epics_before" ]
  [ "$(grep -c 'epic_id: "E-099' "$PROJ/.aid-o/config/queue.yaml")" = "$queue_before" ]
  # And it says so, pointing at the commands that DO clean up.
  [[ "$output" == *"plan-rollback"* ]]
  [[ "$output" == *"NOT done here"* ]]
}

@test "supersede prints what was generated, listing the archived manifest's phases verbatim" {
  _incomplete
  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"phase 1: E-099-1_3 / R-E099-1 — generated"* ]]
  [[ "$output" == *"phase 2: E-099-2_3 / R-E099-2 — generated"* ]]
  [[ "$output" == *"phase 3: E-099-3_3 / R-E099-3 — generated"* ]]
  # The archived paths are named so the PM can find them.
  [[ "$output" == *"transaction.json.superseded-"* ]]
  [[ "$output" == *"generation-authority.json.superseded-"* ]]
}

@test "after supersede, the abandoned queue entries still block until cleaned up — then the new identity starts a fresh transaction" {
  _incomplete
  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]
  printf '\nThe plan edit that motivated the supersede.\n' >> "$PLAN"

  # Supersede deletes nothing, so the abandoned generation's queue entries are
  # still there. They belong to the OLD identity, and a new transaction must
  # never silently adopt them (Codex round, BLOCKER 3) — the command's own
  # output says cleanup stays with plan-rollback / queue removal.
  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"does NOT belong to this generation transaction"* ]]

  # Do the cleanup the command pointed at, then regenerate.
  printf 'paused: false\nlast_modified: "x"\n\nqueue:\n' > "$PROJ/.aid-o/config/queue.yaml"
  rm -f "$TX" "$AUTH"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  [ -f "$TX" ]
  [ "$(jq -r '.plan_sha256' "$TX")" = "$(sha256sum "$PLAN" | awk '{print $1}')" ]
  # The archived pair is still on disk, untouched.
  [ -n "$(ls "$GEN"/transaction.json.superseded-* 2>/dev/null)" ]
}

# ─── the refusals ────────────────────────────────────────────────────────

@test "supersede with a short reason dies before touching anything" {
  _incomplete
  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason 'too short'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  [ -f "$TX" ]
  run bash -c "ls '$GEN'/transaction.json.superseded-* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "supersede with NO transaction at all refuses with 'nothing to supersede'" {
  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"Nothing to supersede"* ]]
}

@test "supersede of a COMPLETE transaction refuses, naming the automatic rollover instead" {
  local out rc=0
  out="$(_run_pipeline 2>&1)" || rc=$?
  [ "$rc" -eq 0 ]
  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"is COMPLETE"* ]]
  [[ "$output" == *".completed-<epoch>"* ]]
  [[ "$output" == *"Nothing was archived"* ]]
  [ -f "$TX" ]
}

@test "--plan naming a DIFFERENT plan than the transaction records refuses, naming both ids" {
  _incomplete
  # A second, valid plan file with its own id, in the same workspace.
  local other="$PROJ/.aid-o/plans/P098-other.md"
  sed 's/^id: P099$/id: P098/' "$PLAN" > "$other"
  # Point the P098 generation dir's transaction at P099's record — the exact
  # cross-plan archive this refusal exists to prevent.
  mkdir -p "$PROJ/.aid-o/work/evidence/P098/generation"
  cp "$TX" "$PROJ/.aid-o/work/evidence/P098/generation/transaction.json"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$other' --reason '$REASON'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"P098"* ]]
  [[ "$output" == *"P099"* ]]
  [[ "$output" == *"cross-plan archive"* ]]
  [ -f "$PROJ/.aid-o/work/evidence/P098/generation/transaction.json" ]
}

# ─── half-archived recovery ──────────────────────────────────────────────

@test "a REPEATED supersede over a half-archived pair completes the missing rename under the ORIGINAL epoch" {
  _incomplete
  # The exact state a failed second rename leaves: the transaction archived,
  # its authority still live.
  local epoch=1750000000
  mv "$TX" "${TX}.superseded-${epoch}"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"half-archived"* ]]
  [[ "$output" == *"no fresh epoch"* ]]
  [ -f "${AUTH}.superseded-${epoch}" ]
  [ ! -f "$AUTH" ]
  # Exactly one epoch exists — no second archive was created.
  run bash -c "ls -d '$GEN'/*.superseded-* | sed 's/.*superseded-//' | sort -u | wc -l"
  [ "$output" = "1" ]
}
