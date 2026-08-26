#!/usr/bin/env bats
# aid-tier: t2
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
#   bats --tap test-supersede-generation.bats | grep -cE '^(ok|not ok)'   # == 13

load test-helpers.bash
load generation-fixture.bash

setup() {
  gen_setup
  gen_shadow_farm
  gen_cp1_counting_stub
  PROJ="$TEST_TMPDIR/p"
  gen_mk_project "$PROJ"
  # THE shared seeder — scripts/tests/lib/aid-test-plan-fixture.sh. It satisfies
  # every generation precondition at once (execution.yaml, the plan committed
  # where the workspace tracks it, the PM page rendered and current), so the
  # fourth such precondition is one edit there rather than fifteen here.
  PLAN="$(aid_fixture_seed_plan "$PROJ" "$FIXTURES/multi-phase-plan-numeric.md" P099-multi.md)"
  GEN="$PROJ/.aid-o/work/evidence/P099/generation"
  TX="$GEN/transaction.json"
  AUTH="$GEN/generation-authority.json"
  REASON="the plan changed mid-generation and the PM accepts archiving the incomplete run"
  export PROJ PLAN GEN TX AUTH REASON
}

teardown() { gen_teardown; }

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
  # An edited plan leaves its PM page stale, and generation refuses that BEFORE
  # it reaches the queue-ownership refusal this case is about. Re-seeding keeps
  # the page current while the plan identity still changes — which is the whole
  # point of the edit here.
  aid_fixture_seed_plan "$PROJ" "$PLAN" P099-multi.md >/dev/null

  # Supersede deletes nothing, so the abandoned generation's queue entries are
  # still there. They belong to the OLD identity, and a new transaction must
  # never silently adopt them — the command's own
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

@test "a half-archived pair completed by a retry produces the FULL audit trail, not a silent rename" {
  # A recovery path that renames the remaining file and returns SUCCESS having
  # written no forensic record, no timeline event and no audit-log entry makes
  # "first call's second rename fails, operator retries" a route to an
  # UNAUDITED supersession, in the one mechanism whose enforcement surface IS
  # the audit trail.
  _incomplete
  local epoch=1750000000
  mv "$TX" "${TX}.superseded-${epoch}"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]
  [ -f "${AUTH}.superseded-${epoch}" ]

  # Record 1 — the forensic artifact, under the ORIGINAL epoch, and the
  # command printed the path it actually wrote.
  local rec="$GEN/generation-superseded-${epoch}.json"
  [ -f "$rec" ]
  [[ "$output" == *"audit record: ${rec}"* ]]
  [ "$(jq -r '.schema' "$rec")" = "aid-generation-supersede/v1" ]
  [ "$(jq -r '.reason' "$rec")" = "$REASON" ]
  [ "$(jq -r '.archived_transaction' "$rec")" = "${TX}.superseded-${epoch}" ]
  [ "$(jq -r '.archived_authority' "$rec")" = "${AUTH}.superseded-${epoch}" ]
  [ "$(jq -r '.transaction_sha256' "$rec")" = "$(sha256sum "${TX}.superseded-${epoch}" | awk '{print $1}')" ]
  [ "$(jq -r '.generated | length' "$rec")" = "3" ]

  # Records 2 and 3 — both carry the SAME epoch, so the trail is joinable.
  run bash -c "grep -c '\"epoch\":\"${epoch}\"' '$GEN/timeline.jsonl'" 3>&-
  [ "$output" = "1" ]
  run bash -c "grep -c '\"epoch\":\"${epoch}\"' '$PROJ/.aid-o/work/audit-log.jsonl'" 3>&-
  [ "$output" = "1" ]

  # And it is IDEMPOTENT: a third call adds no duplicate records.
  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  run bash -c "grep -c '\"epoch\":\"${epoch}\"' '$PROJ/.aid-o/work/audit-log.jsonl'" 3>&-
  [ "$output" = "1" ]
}

@test "with the audit log unwritable, supersede REFUSES and archives nothing at all" {
  # The other half of the same contract: the three audit writes must not be
  # `|| true` while the success message prints an audit-record path. An unrecordable
  # supersession must not happen — and must not leave a half-archived pair
  # that a later retry would then complete as if it had been audited.
  _incomplete
  rm -f "$PROJ/.aid-o/work/audit-log.jsonl"
  # A directory where a file must be appended: unwritable for EVERY uid,
  # including root (the shape test-worktree-teardown.bats' F8 case uses).
  mkdir -p "$PROJ/.aid-o/work/audit-log.jsonl"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"audit-log.jsonl"* ]]
  [[ "$output" == *"NOTHING was archived"* ]]
  # Nothing moved, nothing half-moved, and no record claiming otherwise.
  [ -f "$TX" ]
  [ -f "$AUTH" ]
  run bash -c "ls '$GEN'/*.superseded-* 2>/dev/null | wc -l" 3>&-
  [ "$output" = "0" ]
  run bash -c "ls '$GEN'/generation-superseded-*.json 2>/dev/null | wc -l" 3>&-
  [ "$output" = "0" ]
}

@test "TWO PLANS superseding under the SAME epoch each get their own verified audit-log entry" {
  # The audit log is CROSS-PLAN and the epoch is only second-resolution, while
  # two plans superseding at the same moment hold DIFFERENT per-plan generation
  # locks and genuinely run concurrently. An epoch-only verification lets plan B
  # match plan A's line, skip its own append, and report success with no entry
  # of its own — an unaudited supersession produced by the very code meant to
  # make one impossible.
  #
  # The shared epoch is made deterministic (not raced) by driving both plans
  # through the half-archived recovery path, which records under the epoch
  # already on disk.
  _incomplete
  local epoch=1750000000
  mv "$TX" "${TX}.superseded-${epoch}"
  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]

  # A SECOND plan whose own half-archived pair carries the SAME epoch.
  local other="$PROJ/.aid-o/plans/P098-other.md"
  sed 's/^id: P099$/id: P098/' "$PLAN" > "$other"
  local gen2="$PROJ/.aid-o/work/evidence/P098/generation"
  mkdir -p "$gen2"
  jq '.plan_id = "P098"' "${TX}.superseded-${epoch}" > "${gen2}/transaction.json.superseded-${epoch}"
  cp "${AUTH}.superseded-${epoch}" "${gen2}/generation-authority.json"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' supersede-generation --plan '$other' --reason '$REASON'" 3>&-
  [ "$status" -eq 0 ]
  [ -f "${gen2}/generation-authority.json.superseded-${epoch}" ]

  # Each plan has its OWN record and its OWN audit-log entry under that epoch.
  [ -f "$GEN/generation-superseded-${epoch}.json" ]
  [ -f "${gen2}/generation-superseded-${epoch}.json" ]
  [ "$(jq -r '.plan_id' "${gen2}/generation-superseded-${epoch}.json")" = "P098" ]
  local alog="$PROJ/.aid-o/work/audit-log.jsonl"
  run bash -c "grep -c '\"plan_id\":\"P099\".*\"epoch\":\"${epoch}\"' '$alog'" 3>&-
  [ "$output" = "1" ]
  run bash -c "grep -c '\"plan_id\":\"P098\".*\"epoch\":\"${epoch}\"' '$alog'" 3>&-
  [ "$output" = "1" ]
}

@test "a HELD generation lock makes supersede refuse by name and archive NOTHING" {
  # Without taking the per-plan generation lock, this command could rename a
  # running pipeline's live transaction and authority out from under it while
  # that pipeline was producing phases: the generator then died on its next manifest update having
  # already created EPIC files and queue entries no transaction records.
  _incomplete
  local lock="$GEN/transaction.json.lock"
  # A REAL second process holding the REAL lock (the shape
  # test-worktree-teardown.bats uses for the worktree lock), writing its pid
  # exactly as aid_lock_acquire does so the refusal can name it.
  bash -c "flock -x 9; echo \$\$ > '$lock'; sleep 8" 9>>"$lock" 3>&- &
  local holder=$!
  run bash -c "sleep 1
    cd '$PROJ'
    export AID_GEN_LOCK_TIMEOUT=1
    exec bash '$PIPELINE' supersede-generation --plan '$PLAN' --reason '$REASON'" 3>&-
  local pid_in_lock; pid_in_lock="$(tr -d '[:space:]' < "$lock" 2>/dev/null || true)"
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  [ "$status" -ne 0 ]
  [[ "$output" == *"a generation is in progress"* ]]
  [[ "$output" == *"holder pid ${pid_in_lock}"* ]]
  [[ "$output" == *"NOTHING was archived"* ]]
  # It archived nothing and recorded nothing.
  [ -f "$TX" ]
  [ -f "$AUTH" ]
  run bash -c "ls '$GEN'/*.superseded-* 2>/dev/null | wc -l" 3>&-
  [ "$output" = "0" ]
  run bash -c "ls '$GEN'/generation-superseded-*.json 2>/dev/null | wc -l" 3>&-
  [ "$output" = "0" ]
}
