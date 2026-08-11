#!/usr/bin/env bats
# aid-tier: t2
# test-generation-resume.bats — P074 Step 15: the transaction manifest,
# hash-derived resume, and the one-hold concurrency contract.
#
# THE FAILURES THIS PINS, both observed live on 2026-08-04: a rerun regenerated from
# phase 1, silently overwrote the outputs, and then DIED on phase 1's queue
# duplicate — leaving phases 2..N stranded with no state to resume from. And
# the generation receipt's per-EPIC `queue_status` stayed at the placeholder
# `pending_receipt` forever, because nothing rewrote it after stage 2.
#
# THE SHAPE UNDER TEST: status is DERIVED, never stored. Each phase's status
# comes from re-hashing the recorded outputs and reading queue membership, so
# the files and the queue are the truth and the manifest is only the binding
# that lets a rerun VERIFY rather than blindly redo. The completion
# short-circuit fires only AFTER the receipt's queue-status rewrite, so a crash
# anywhere before it always leaves the transaction resumable.
#
# ── HOW THE KILLS ARE INDUCED ──────────────────────────────────────────────
# Running a SUCCESSFUL pipeline and then hand-deleting artifacts to fabricate
# the post-crash state can only ever confirm the fabrication — it cannot expose
# a real write-ordering window, because no write ever raced anything. Every
# kill here is a REAL SIGKILL of the REAL pipeline process at a
# specific write boundary, delivered from inside a child the pipeline itself
# invokes: the shadow plugin substitutes a wrapper that runs the GENUINE script
# and then `kill -9 $PPID`. That parent IS the pipeline shell — these children
# are simple commands (or single-command substitutions), so bash execs them in
# a direct child of the pipeline. The windows covered:
#
#   AID_TEST_KILL_EPIC_TO_JSON=N   killed AFTER phase N's plan.json is written
#                                  and BEFORE the manifest records it
#                                  → output-before-manifest
#   AID_TEST_KILL_QUEUE_ADD=N      killed AFTER the Nth queue entry is durably
#                                  appended and BEFORE `queued: true` is
#                                  recorded → queue-add-before-manifest-update
#                                  (the adopt-from-queue path)
#   AID_TEST_KILL_FINALIZE_REWRITE killed BEFORE the `--rewrite` finalize runs
#                                  → receipt-rewrite window
#
# The authority-before-audit window lives in test-generation-authority.bats and
# needs no kill at all: with the audit records written first and fail-closed,
# an unwritable audit path makes the pipeline abort there by itself.
#
# FD-3 HYGIENE: every pipeline invocation runs with `3>&-`; no `run` is handed
# a path that might not exist (a 127 would write to fd 3 and, with fd 3 closed,
# destroy this file's whole TAP output).
# After any edit, verify the result count:
#   bats --tap test-generation-resume.bats | grep -cE '^(ok|not ok)'   # == 12

load test-helpers.bash
load generation-fixture.bash

setup() {
  gen_setup
  _mk_shadow
  export AID_TEST_E2J_COUNT="$TEST_TMPDIR/e2j.count"
  export AID_TEST_QADD_COUNT="$TEST_TMPDIR/qadd.count"
  PROJ="$TEST_TMPDIR/p"
  gen_mk_project "$PROJ"
  PLAN="$PROJ/.aid-o/plans/P099-multi.md"
  cp "$FIXTURES/multi-phase-plan-numeric.md" "$PLAN"
  GEN="$PROJ/.aid-o/work/evidence/P099/generation"
  TX="$GEN/transaction.json"
  QUEUE="$PROJ/.aid-o/config/queue.yaml"
  export PROJ PLAN GEN TX QUEUE
}

teardown() { gen_teardown; }

# _mk_shadow — the shared symlink farm and counting CP1 stub, plus the three
# kill wrappers that belong to THIS suite alone. Every wrapper runs the GENUINE
# script; the only thing it adds is the signal.
_mk_shadow() {
  gen_shadow_farm
  gen_cp1_counting_stub

  rm -f "$SHADOW/scripts/aid-epic-to-json.sh"
  cat > "$SHADOW/scripts/aid-epic-to-json.sh" <<STUB
#!/usr/bin/env bash
# Runs the real converter, then — at the configured phase — SIGKILLs the
# pipeline. The outputs are on disk; the manifest update never happens.
"$REPO_PLUGIN/scripts/aid-epic-to-json.sh" "\$@"
_rc=\$?
if [[ -n "\${AID_TEST_KILL_EPIC_TO_JSON:-}" ]]; then
  printf 'x' >> "\$AID_TEST_E2J_COUNT"
  _n=\$(wc -c < "\$AID_TEST_E2J_COUNT" | tr -d ' ')
  if [[ "\$_n" == "\$AID_TEST_KILL_EPIC_TO_JSON" ]]; then
    kill -9 "\$PPID" 2>/dev/null
    sleep 5
  fi
fi
exit \$_rc
STUB

  rm -f "$SHADOW/scripts/aid-queue-add.sh"
  cat > "$SHADOW/scripts/aid-queue-add.sh" <<STUB
#!/usr/bin/env bash
# Runs the real queue-add (the entry IS durably appended), then SIGKILLs the
# pipeline before it can record \`queued: true\`.
"$REPO_PLUGIN/scripts/aid-queue-add.sh" "\$@"
_rc=\$?
if [[ -n "\${AID_TEST_KILL_QUEUE_ADD:-}" && "\$_rc" -eq 0 ]]; then
  printf 'x' >> "\$AID_TEST_QADD_COUNT"
  _n=\$(wc -c < "\$AID_TEST_QADD_COUNT" | tr -d ' ')
  if [[ "\$_n" == "\$AID_TEST_KILL_QUEUE_ADD" ]]; then
    kill -9 "\$PPID" 2>/dev/null
    sleep 5
  fi
fi
exit \$_rc
STUB

  rm -f "$SHADOW/scripts/aid-generation-finalize.sh"
  cat > "$SHADOW/scripts/aid-generation-finalize.sh" <<STUB
#!/usr/bin/env bash
# SIGKILLs the pipeline just before the receipt's queue-status rewrite, so the
# receipt is left at its pre-stage-2 placeholder values.
if [[ -n "\${AID_TEST_KILL_FINALIZE_REWRITE:-}" ]]; then
  for a in "\$@"; do
    if [[ "\$a" == "--rewrite" ]]; then kill -9 "\$PPID" 2>/dev/null; sleep 5; fi
  done
fi
exec "$REPO_PLUGIN/scripts/aid-generation-finalize.sh" "\$@"
STUB

  chmod +x "$SHADOW/scripts/aid-epic-to-json.sh" \
           "$SHADOW/scripts/aid-queue-add.sh" "$SHADOW/scripts/aid-generation-finalize.sh"
}

_run_pipeline() { ( cd "$PROJ" && bash "$PIPELINE" --plan "$PLAN" --queue-mode chain 3>&- ); }
# _run_killable — a run that is EXPECTED to die; its exit status is captured,
# never propagated (a killed process must not abort the test).
_run_killable() { local rc=0; ( cd "$PROJ" && bash "$PIPELINE" --plan "$PLAN" --queue-mode chain 3>&- ) >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }
_queue_count() { grep -c 'epic_id: "E-099' "$QUEUE" 2>/dev/null || echo 0; }
_epic_count() { ls "$PROJ/.aid-o/tasks"/E-099-*.md 2>/dev/null | wc -l | tr -d ' '; }

# ─── real kill 1: output written, manifest not yet updated ────────────────

@test "REAL KILL mid-phase-2 (output written, manifest not updated): the rerun resumes at phase 2 with identical ids and zero duplicates" {
  local rc
  rc="$(AID_TEST_KILL_EPIC_TO_JSON=2 _run_killable)"
  [ "$rc" -ne 0 ]                                                       # the run really died
  [ -f "$TX" ]                                                          # ...after the skeleton existed
  [ "$(jq -r '.phases["1"].epic_sha256 // "none"' "$TX")" != "none" ]    # phase 1 recorded
  [ "$(jq -r '.phases["2"].epic_sha256 // "none"' "$TX")" = "none" ]     # phase 2 NOT recorded
  [ ! -f "$GEN/receipt.json" ]                                          # stage 2 never ran
  local before1; before1="$(jq -r '.phases["1"].epic_sha256' "$TX")"
  : > "$CP1_COUNT"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"E-099-1_3 verified against the transaction"* ]]      # phase 1 skipped
  [[ "$output" != *"E-099-2_3 verified against the transaction"* ]]      # phase 2 regenerated
  [ "$(jq -r '.phases["1"].epic_sha256' "$TX")" = "$before1" ]
  [ "$(jq -r '.phases["2"].epic_id' "$TX")" = "E-099-2_3" ]
  [ "$(jq -r '.phases["2"].run_id' "$TX")" = "R-E099-2" ]
  [ "$(_epic_count)" = "3" ]
  [ "$(_queue_count)" = "3" ]
  [ "$(gen_cp1_calls)" = "0" ]                                             # sealed authority reused
}

# ─── real kill 2: queue entry durable, manifest unaware (adoption) ────────

@test "REAL KILL after the first queue-add (entry durable, manifest unaware): the rerun ADOPTS it instead of duplicating or failing" {
  local rc
  rc="$(AID_TEST_KILL_QUEUE_ADD=1 _run_killable)"
  [ "$rc" -ne 0 ]
  # The queue really holds phase 1's entry...
  [ "$(_queue_count)" = "1" ]
  # ...and the manifest never learned about it — the exact window under test.
  [ "$(jq -r '.phases["1"].queued // "absent"' "$TX")" = "absent" ]
  : > "$CP1_COUNT"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  # The queue is treated as truth: the entry is verified and adopted, neither
  # duplicated nor hard-failed (the 2026-08-04 stranding).
  [[ "$output" == *"E-099-1_3 already queued by this generation transaction"* ]]
  [ "$(jq -r '.phases["1"].queued' "$TX")" = "true" ]
  [ "$(_queue_count)" = "3" ]
  [ "$(_epic_count)" = "3" ]
  [ "$(gen_cp1_calls)" = "0" ]
}

# ─── real kill 3: receipt rewrite never happened ─────────────────────────

@test "REAL KILL before the receipt rewrite: the transaction is INCOMPLETE and the rerun finishes it without regenerating" {
  local rc
  rc="$(AID_TEST_KILL_FINALIZE_REWRITE=1 _run_killable)"
  [ "$rc" -ne 0 ]
  # Everything is generated and queued, but the receipt still carries the
  # placeholder — which is exactly what keeps the transaction resumable.
  [ -f "$GEN/receipt.json" ]
  run jq -e '[.epics[].queue_status] | any(. == "pending_receipt")' "$GEN/receipt.json"
  [ "$status" -eq 0 ]
  local before; before="$(jq -S -c '.phases | with_entries(.value |= del(.queued))' "$TX")"
  : > "$CP1_COUNT"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  [ "$(grep -c 'verified against the transaction' <<< "$output")" = "3" ]   # nothing regenerated
  [ "$(jq -S -c '.phases | with_entries(.value |= del(.queued))' "$TX")" = "$before" ]
  [ "$(jq -r '[.epics[].queue_status] | unique | join(",")' "$GEN/receipt.json")" = "pending" ]
  [ "$(_queue_count)" = "3" ]
  [ "$(gen_cp1_calls)" = "0" ]
}

# ─── corrupted output ────────────────────────────────────────────────────

@test "a corrupted phase output (hash mismatch) is regenerated in place; the intact phases are not touched" {
  local out rc=0
  out="$(_run_pipeline 2>&1)" || rc=$?
  [ "$rc" -eq 0 ]
  local epic2; epic2="$(jq -r '.phases["2"].epic_path' "$TX")"
  local intact1 intact3
  intact1="$(jq -r '.phases["1"].epic_sha256' "$TX")"
  intact3="$(jq -r '.phases["3"].epic_sha256' "$TX")"
  printf '\ncorruption that nobody recorded\n' >> "$epic2"
  : > "$CP1_COUNT"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" != *"E-099-2_3 verified against the transaction"* ]]
  [[ "$output" == *"E-099-1_3 verified against the transaction"* ]]
  [[ "$output" == *"E-099-3_3 verified against the transaction"* ]]
  ! grep -q 'corruption that nobody recorded' "$epic2"
  [ "$(jq -r '.phases["2"].epic_sha256' "$TX")" = "$(sha256sum "$epic2" | awk '{print $1}')" ]
  [ "$(jq -r '.phases["1"].epic_sha256' "$TX")" = "$intact1" ]
  [ "$(jq -r '.phases["3"].epic_sha256' "$TX")" = "$intact3" ]
  [ "$(_queue_count)" = "3" ]
}

# ─── identity ────────────────────────────────────────────────────────────

@test "an edited plan over an INCOMPLETE transaction refuses, naming both identities and supersede-generation" {
  # Incomplete for real: killed before the receipt rewrite.
  local rc; rc="$(AID_TEST_KILL_FINALIZE_REWRITE=1 _run_killable)"
  [ "$rc" -ne 0 ]
  printf '\nA plan edit that changes the identity.\n' >> "$PLAN"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity mismatch"* ]]
  [[ "$output" == *"supersede-generation"* ]]
  [[ "$output" == *"plan_sha256|target_head|phase_derivation_version|total_phases"* ]]
  [ -f "$TX" ]
}

@test "an edited plan over a COMPLETE transaction rolls over to .completed-<epoch> siblings once the old queue entries are gone" {
  local out rc=0
  out="$(_run_pipeline 2>&1)" || rc=$?
  [ "$rc" -eq 0 ]
  local old_identity; old_identity="$(jq -r '.plan_sha256' "$TX")"
  # The previous generation's entries are removed — the queue holds one entry
  # per EPIC id, so the regenerated EPICs need those ids free (this is the
  # cleanup the refusal in the next test points the PM at).
  printf 'paused: false\nlast_modified: "x"\n\nqueue:\n' > "$QUEUE"
  printf '\nA plan edit after a completed generation.\n' >> "$PLAN"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"was COMPLETE and the plan identity changed"* ]]
  local ta aa
  ta="$(ls "$GEN"/transaction.json.completed-* | head -1)"
  aa="$(ls "$GEN"/generation-authority.json.completed-* | head -1)"
  [ -n "$ta" ] && [ -n "$aa" ]
  [ "${ta##*.completed-}" = "${aa##*.completed-}" ]
  [ "$(jq -r '.plan_sha256' "$ta")" = "$old_identity" ]
  [ "$(jq -r '.plan_sha256' "$TX")" = "$(sha256sum "$PLAN" | awk '{print $1}')" ]
}

@test "STALE-IDENTITY ADOPTION IS REFUSED: a completed generation whose queue entries still exist blocks the rollover before anything is regenerated" {
  # The new transaction derives the SAME epic ids from
  # the same plan file, so the pre-rollover entries used to look "owned" and
  # were silently skipped — leaving queue entries standing for content
  # regenerated under a different identity.
  local out rc=0
  out="$(_run_pipeline 2>&1)" || rc=$?
  [ "$rc" -eq 0 ]
  local epic1_sha_before; epic1_sha_before="$(jq -r '.phases["1"].epic_sha256' "$TX")"
  # Same phase count, different bytes.
  printf '\nAn edit that keeps the phase count but changes the bytes.\n' >> "$PLAN"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"still has queue entries"* ]]
  [[ "$output" == *"E-099-1_3 (pending)"* ]]
  [[ "$output" == *"one entry per EPIC id"* ]]
  [[ "$output" == *"Nothing was archived or regenerated"* ]]
  # Proof it refused BEFORE doing anything: nothing archived, nothing rewritten.
  run bash -c "ls '$GEN'/transaction.json.completed-* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
  [ "$(jq -r '.phases["1"].epic_sha256' "$TX")" = "$epic1_sha_before" ]
  [ "$(_queue_count)" = "3" ]
}

# ─── the receipt ─────────────────────────────────────────────────────────

@test "the final receipt carries REAL queue statuses, not the pending_receipt placeholder" {
  local out rc=0
  out="$(_run_pipeline 2>&1)" || rc=$?
  [ "$rc" -eq 0 ]
  [ -f "$GEN/receipt.json" ]
  [ "$(jq -r '[.epics[].queue_status] | unique | join(",")' "$GEN/receipt.json")" = "pending" ]
  run jq -e '[.epics[].queue_status] | any(. == "pending_receipt")' "$GEN/receipt.json"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.updated_at // "none"' "$GEN/receipt.json")" != "none" ]
}

@test "the receipt rewrite leaves aid-json-to-run.sh's consumer contract intact (schema, plan_sha256, per-EPIC binding)" {
  local out rc=0
  out="$(_run_pipeline 2>&1)" || rc=$?
  [ "$rc" -eq 0 ]
  local r="$GEN/receipt.json"
  [ "$(jq -r '.schema' "$r")" = "aid-generation-receipt/v1" ]
  [ "$(jq -r '.plan_sha256' "$r")" = "sha256:$(sha256sum "$PLAN" | awk '{print $1}')" ]
  local pj
  for pj in 1 2 3; do
    local eid path
    eid="$(jq -r --arg p "$pj" '.phases[$p].epic_id' "$TX")"
    path="$(jq -r --arg p "$pj" '.phases[$p].plan_json' "$TX")"
    run jq -e --arg eid "$eid" --arg psha "sha256:$(sha256sum "$path" | awk '{print $1}')" \
      'any(.epics[]; .epic_id == $eid and .plan_json_sha256 == $psha)' "$r"
    [ "$status" -eq 0 ]
  done
}

# ─── concurrency: ONE hold for the whole generation ──────────────────────

@test "a second invocation while the transaction lock is held refuses by name, with the holder pid, and generates nothing" {
  # Dropping the lock once the authority is
  # sealed, so a second invocation walked straight into the phase work and
  # raced the first on the counter, FSM init and the very files it hashes.
  mkdir -p "$GEN"
  : > "$TX.lock"
  ( exec 9<>"$TX.lock"; flock -x 9; echo "$BASHPID" > "$TX.lock"; sleep 20 ) &
  local holder=$!
  # Wait (bounded) until the lock is genuinely taken.
  local i=0
  while [ "$i" -lt 50 ] && flock -n -x "$TX.lock" true 2>/dev/null; do sleep 0.1; i=$((i+1)); done

  run bash -c "cd '$PROJ' && AID_GEN_LOCK_TIMEOUT=1 bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  [ "$status" -ne 0 ]
  [[ "$output" == *"generation already in progress for P099"* ]]
  [[ "$output" == *"holder pid"* ]]
  [[ "$output" == *"Never delete the .lock file"* ]]
  [ "$(_epic_count)" = "0" ]
  [ "$(_queue_count)" = "0" ]
}

# ─── honesty: a gate that CRASHES is not a verdict about the EPIC ────────

@test "a D5 gate that dies without a verdict is reported as a GATE failure, never as a malformed contract" {
  # GROUNDED (2026-08-06, under artificial CPU load): the gate's own
  # `_aid_parse_scoping_line | head -1` took SIGPIPE, so it exited 141 with
  # EMPTY stdout — and the pipeline told the operator their plan.json/EPIC.md
  # was "malformed" on a contract that passed cleanly on the very next run. The
  # SIGPIPE is fixed at its source; this test pins the REPORTING, which is what
  # protects the operator from every other way a gate can die.
  rm -f "$SHADOW/scripts/gates"
  mkdir -p "$SHADOW/scripts/gates"
  local g
  for g in "$REPO_PLUGIN/scripts/gates"/*; do ln -s "$g" "$SHADOW/scripts/gates/$(basename "$g")"; done
  rm -f "$SHADOW/scripts/gates/aid-contract-validate.sh"
  # Exit 141 with nothing on stdout — the exact shape of the observed abort.
  printf '#!/usr/bin/env bash\nexit 141\n' > "$SHADOW/scripts/gates/aid-contract-validate.sh"
  chmod +x "$SHADOW/scripts/gates/aid-contract-validate.sh"

  run bash -c "cd '$PROJ' && bash '$PIPELINE' --plan '$PLAN' --queue-mode chain" 3>&-
  [ "$status" -eq 5 ]                                        # not 4 — no contract verdict exists
  [[ "$output" == *"could NOT BE RUN"* ]]
  [[ "$output" == *"killed by signal 13"* ]]
  [[ "$output" == *"failure of the GATE"* ]]
  [[ "$output" != *"malformed plan.json/EPIC.md contract"* ]]   # the lie this test forbids
  [[ "$output" == *"UNKNOWN, not malformed"* ]]                 # ...and what it says instead
  # The artifact says the same thing in its own bytes — never a blank file.
  local cv="$PROJ/.aid-o/work/evidence/P099-multi/generation/epics/E-099-1_3/c0/contract-validate.json"
  [ -s "$cv" ]
  [ "$(jq -r '.result' "$cv")" = "gate_error" ]
  [ "$(jq -r '.gate_exit' "$cv")" = "141" ]
  [ "$(_queue_count)" = "0" ]                                # and nothing was queued on a non-verdict
}

@test "two CONCURRENT invocations: exactly one generates, the other resumes to a verified no-op, and there are no duplicate artifacts" {
  local o1="$TEST_TMPDIR/c1.log" o2="$TEST_TMPDIR/c2.log" r1=0 r2=0
  ( cd "$PROJ" && bash "$PIPELINE" --plan "$PLAN" --queue-mode chain 3>&- ) >"$o1" 2>&1 &
  local p1=$!
  ( cd "$PROJ" && bash "$PIPELINE" --plan "$PLAN" --queue-mode chain 3>&- ) >"$o2" 2>&1 &
  local p2=$!
  wait "$p1" || r1=$?
  wait "$p2" || r2=$?
  # On failure, the two logs are the only evidence of the interleaving — bats
  # shows this block's output, and without it a flake here is undiagnosable.
  if [ "$r1" -ne 0 ] || [ "$r2" -ne 0 ]; then
    echo "r1=$r1 r2=$r2"; echo "--- invocation 1"; cat "$o1"; echo "--- invocation 2"; cat "$o2"
  fi
  [ "$r1" -eq 0 ]
  [ "$r2" -eq 0 ]

  # Exactly one run did the generating; the other found a matching identity and
  # verified its way through. (Whichever won the lock, exactly one of the two
  # logs reports resuming.)
  local resumed=0
  grep -q 'resuming the existing transaction' "$o1" && resumed=$((resumed+1))
  grep -q 'resuming the existing transaction' "$o2" && resumed=$((resumed+1))
  [ "$resumed" -eq 1 ]

  # No interleaving: one gate call, three EPICs, three queue entries, and every
  # recorded hash still matches the file on disk (a race would have recorded a
  # hash for bytes the other run replaced).
  [ "$(gen_cp1_calls)" = "1" ]
  [ "$(_epic_count)" = "3" ]
  [ "$(_queue_count)" = "3" ]
  local pj
  for pj in 1 2 3; do
    local ep; ep="$(jq -r --arg p "$pj" '.phases[$p].epic_path' "$TX")"
    [ "$(jq -r --arg p "$pj" '.phases[$p].epic_sha256' "$TX")" = "$(sha256sum "$ep" | awk '{print $1}')" ]
  done
}
