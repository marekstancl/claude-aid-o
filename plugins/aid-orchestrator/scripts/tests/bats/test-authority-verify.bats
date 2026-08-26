#!/usr/bin/env bats
# aid-tier: t2
# test-authority-verify.bats — P074 Step 14: the phase generator VERIFIES the
# sealed generation authority instead of re-running the CP1 gate.
#
# WHAT IS ACTUALLY ENFORCED, stated honestly (AID-v3 §1): the authority file is
# an ordinary JSON file a Bash-capable actor can write. Nothing here claims
# otherwise. The enforcement is the BINDING — the receipt must match the real
# plan bytes, the real target head, this phase's independently re-derived ids,
# and the owning transaction's authority_sha256 — plus audit detectability. A
# leaked or replayed receipt is useless outside its own transaction, which is
# exactly what the linkage fixture below pins.
#
# MOST CASES ARE HAND-BUILT, deliberately: a fixture that constructs the
# authority/transaction pair itself can corrupt exactly one field and assert
# the failure NAMES that field. Two cases run the real pipeline end to end for
# the wiring proof (zero gate calls across 3 phases; standalone still gated).
#
# FD-3 HYGIENE: every heavyweight invocation runs with `3>&-`; no `run` is ever
# handed a path that might not exist (a 127 would write to fd 3 and, with fd 3
# closed, destroy this file's whole TAP output).
# After any edit, verify the result count:
#   bats --tap test-authority-verify.bats | grep -cE '^(ok|not ok)'   # == 14

load test-helpers.bash
load generation-fixture.bash

setup() {
  gen_setup
  gen_shadow_farm
  gen_cp1_counting_stub
}

teardown() { gen_teardown; }

# _seal <project> <plan> — hand-build a VALID authority/transaction pair for
# the 3-phase numeric fixture, exactly as the pipeline would seal it.
_seal() {
  local d="$1" plan="$2"
  local gen="$d/.aid-o/work/evidence/P099/generation"
  mkdir -p "$gen"
  local psha head draft
  psha="$(sha256sum "$plan" | awk '{print $1}')"
  head="$(git -C "$d" rev-parse main)"
  draft="$(jq -n --arg p "$psha" --arg h "$head" \
    '{schema:"aid-generation-authority/v1", plan_id:"P099", plan_path:"x",
      plan_sha256:$p, target_branch:"main", target_head:$h, mode:"chain",
      total_phases:3, phase_derivation_version:1, cp1:{verdict:"low_risk_pass"},
      forced_override:false, force_reason:null, invoker:"test",
      created_at:"2026-08-05T00:00:00Z", self_sha256:null}')"
  local self; self="$(printf '%s\n' "$draft" | jq -S -c '.self_sha256 = null' | sha256sum | awk '{print $1}')"
  jq --arg s "$self" '.self_sha256 = $s' <<< "$draft" > "$gen/generation-authority.json"
  jq -n --arg p "$psha" --arg h "$head" --arg a "$self" \
    '{schema:"aid-generation-transaction/v1", plan_id:"P099", plan_path:"x",
      plan_sha256:$p, target_branch:"main", target_head:$h,
      phase_derivation_version:1, total_phases:3, authority_sha256:$a,
      phases:{"1":{epic_id:"E-099-1_3", run_id:"R-E099-1"},
              "2":{epic_id:"E-099-2_3", run_id:"R-E099-2"},
              "3":{epic_id:"E-099-3_3", run_id:"R-E099-3"}},
      created_at:"2026-08-05T00:00:00Z", updated_at:"2026-08-05T00:00:00Z"}' \
    > "$gen/transaction.json"
  printf '%s\n' "$gen"
}

_setup_sealed() {
  gen_mk_project "$TEST_TMPDIR/p"
  # THE shared seeder — it satisfies every generation precondition at once, so
  # the fourth one is an edit there rather than in every fixture that generates
  # (scripts/tests/lib/aid-test-plan-fixture.sh).
  PLAN="$(aid_fixture_seed_plan "$TEST_TMPDIR/p" "$FIXTURES/multi-phase-plan-numeric.md" P099-multi.md)"
  GEN="$(_seal "$TEST_TMPDIR/p" "$PLAN")"
  export PLAN GEN
}

# ─── the happy path ──────────────────────────────────────────────────────

@test "a valid authority + transaction generates the phase with ZERO CP1 gate invocations" {
  _setup_sealed
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -eq 0 ]
  [ "$(gen_cp1_calls)" = "0" ]
  [[ "$output" == *"E-099-1_3"* ]]
}

@test "the pipeline path verifies ONE authority across 3 phases — the gate is called once, for the seal only" {
  gen_mk_project "$TEST_TMPDIR/p"
  # THE shared seeder — scripts/tests/lib/aid-test-plan-fixture.sh. It satisfies
  # every generation precondition at once (execution.yaml, the plan committed
  # where the workspace tracks it, the PM page rendered and current), so the
  # fourth such precondition is one edit there rather than fifteen here.
  aid_fixture_seed_plan "$TEST_TMPDIR/p" "$FIXTURES/multi-phase-plan-numeric.md" P099-multi.md >/dev/null
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$PIPELINE' --plan '$TEST_TMPDIR/p/.aid-o/plans/P099-multi.md' --queue-mode chain" 3>&-
  [ "$status" -eq 0 ]
  # Counted on disk: `run` merges stderr into $output, so the stdout manifest
  # is not parseable from here.
  [ "$(ls "$TEST_TMPDIR/p/.aid-o/tasks"/E-099-*.md | wc -l | tr -d ' ')" = "3" ]
  # One call — the plan-scoped seal. Phases 1..3 verified it instead.
  [ "$(gen_cp1_calls)" = "1" ]
}

@test "standalone invocation WITHOUT the flags still runs the CP1 gate (legacy callers unchanged)" {
  _setup_sealed
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p'" 3>&-
  [ "$status" -eq 0 ]
  [ "$(gen_cp1_calls)" = "1" ]
}

# ─── every mismatch dies NAMING the exact field ──────────────────────────

@test "a tampered authority (one field edited) dies on self_sha256" {
  _setup_sealed
  jq '.invoker = "someone-else"' "$GEN/generation-authority.json" > "$GEN/t" && mv "$GEN/t" "$GEN/generation-authority.json"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"self_sha256 mismatch"* ]]
  [[ "$output" == *"modified after it was sealed"* ]]
}

@test "a plan EDITED after sealing dies on plan_sha256" {
  _setup_sealed
  printf '\nAn edit made after the authority was sealed.\n' >> "$PLAN"
  # Re-seed so the PM page follows the edited plan. Without this the run dies on
  # the STALE PAGE before it ever reaches the sha256 binding — a different, also
  # correct refusal, and not the one this case is about. Re-seeding refreshes
  # the page and leaves the sealed authority untouched, which is exactly the
  # state the subject needs: a current page over a plan the authority no longer
  # matches.
  aid_fixture_seed_plan "$TEST_TMPDIR/p" "$PLAN" P099-multi.md >/dev/null
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_sha256 does not match the plan on disk"* ]]
}

@test "a MOVED target head dies on target_head" {
  _setup_sealed
  ( cd "$TEST_TMPDIR/p" && printf 'more\n' >> README.md && git add -A && git commit -q -m "move main" )
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"target_head does not match main"* ]]
}

@test "an authority REPLAYED with a foreign transaction dies on the linkage (a leaked receipt is useless)" {
  _setup_sealed
  # A perfectly well-formed transaction for another generation: same plan bytes,
  # same head, same ids — but sealed under a DIFFERENT authority.
  jq '.authority_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
    "$GEN/transaction.json" > "$GEN/foreign.json"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/foreign.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"not bound to this authority"* ]]
  [[ "$output" == *"replayed or foreign receipt"* ]]
}

@test "a per-phase id that disagrees with the RE-DERIVED id dies naming both (derivation drift caught at verify time)" {
  _setup_sealed
  jq '.phases["1"].run_id = "R-E099-9"' "$GEN/transaction.json" > "$GEN/t" && mv "$GEN/t" "$GEN/transaction.json"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"run_id mismatch"* ]]
  [[ "$output" == *"R-E099-9"* ]]
  [[ "$output" == *"R-E099-1"* ]]
}

@test "an authority sealed under a different phase_derivation_version dies naming BOTH versions" {
  _setup_sealed
  # Re-seal at version 2 so the self-hash stays valid: this is a genuine
  # version difference, not a tamper.
  local draft self
  draft="$(jq '.phase_derivation_version = 2 | .self_sha256 = null' "$GEN/generation-authority.json")"
  self="$(printf '%s\n' "$draft" | jq -S -c '.self_sha256 = null' | sha256sum | awk '{print $1}')"
  jq --arg s "$self" '.self_sha256 = $s' <<< "$draft" > "$GEN/generation-authority.json"
  jq --arg a "$self" '.authority_sha256 = $a | .phase_derivation_version = 2' \
    "$GEN/transaction.json" > "$GEN/t" && mv "$GEN/t" "$GEN/transaction.json"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"sealed under phase_derivation_version 2"* ]]
  [[ "$output" == *"derives phases at version 1"* ]]
  [[ "$output" == *"supersede and regenerate"* ]]
}

@test "a document that violates its SCHEMA is rejected by the schema check, naming the offending path" {
  # Field-presence spot checks would let an unknown field, a
  # wrong type, or a missing required key through. Both documents are now
  # validated against the shipped schemas (required / type / const / pattern /
  # additionalProperties: false), so "fails its schema" is a real statement.
  # Re-sealed so the self-hash still matches: this is a schema violation, not a
  # tamper, and it must be caught on its own merits.
  _setup_sealed
  local draft self
  draft="$(jq '.smuggled_field = "not in the schema" | .self_sha256 = null' "$GEN/generation-authority.json")"
  self="$(printf '%s\n' "$draft" | jq -S -c '.self_sha256 = null' | sha256sum | awk '{print $1}')"
  jq --arg s "$self" '.self_sha256 = $s' <<< "$draft" > "$GEN/generation-authority.json"
  jq --arg a "$self" '.authority_sha256 = $a' "$GEN/transaction.json" > "$GEN/t" && mv "$GEN/t" "$GEN/transaction.json"

  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"fails its schema"* ]]
  [[ "$output" == *"smuggled_field"* ]]
  [[ "$output" == *"additionalProperties"* ]]
  [ "$(gen_cp1_calls)" = "0" ]

  # And a MISSING required key is caught too.
  draft="$(jq 'del(.invoker) | .self_sha256 = null' "$GEN/generation-authority.json")"
  self="$(printf '%s\n' "$draft" | jq -S -c '.self_sha256 = null' | sha256sum | awk '{print $1}')"
  jq --arg s "$self" '.self_sha256 = $s' <<< "$draft" > "$GEN/generation-authority.json"
  jq --arg a "$self" '.authority_sha256 = $a' "$GEN/transaction.json" > "$GEN/t" && mv "$GEN/t" "$GEN/transaction.json"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"invoker: required property is missing"* ]]
}

@test "an authority sealed for a DIFFERENT target_branch is rejected even when the head happens to match" {
  _setup_sealed
  # A branch that points at exactly the same commit as main: only comparing
  # target_head would accept this authority.
  ( cd "$TEST_TMPDIR/p" && git branch other-integration main )
  local draft self
  draft="$(jq '.target_branch = "other-integration" | .self_sha256 = null' "$GEN/generation-authority.json")"
  self="$(printf '%s\n' "$draft" | jq -S -c '.self_sha256 = null' | sha256sum | awk '{print $1}')"
  jq --arg s "$self" '.self_sha256 = $s' <<< "$draft" > "$GEN/generation-authority.json"
  jq --arg a "$self" '.authority_sha256 = $a' "$GEN/transaction.json" > "$GEN/t" && mv "$GEN/t" "$GEN/transaction.json"

  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"target_branch is 'other-integration'"* ]]
  [[ "$output" == *"configured integration branch is 'main'"* ]]
}

@test "a TRANSACTION carrying a stale identity is rejected even though the authority itself is intact and linked" {
  # authority_sha256 only proves the transaction NAMES
  # this authority. A transaction whose own identity tuple has drifted — a
  # hand-edited or stale manifest — used to pass on that linkage alone.
  _setup_sealed
  jq '.total_phases = 4' "$GEN/transaction.json" > "$GEN/t" && mv "$GEN/t" "$GEN/transaction.json"

  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"transaction identity"* ]]
  [[ "$output" == *"does not match authority identity"* ]]
  [ "$(gen_cp1_calls)" = "0" ]
}

@test "--generation-authority without --transaction dies (both or neither)" {
  _setup_sealed
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be passed together"* ]]
  [ "$(gen_cp1_calls)" = "0" ]
}

@test "an authority whose transaction file was DELETED between phases dies naming the missing path — never a gate-less fallback" {
  _setup_sealed
  rm -f "$GEN/transaction.json"
  run bash -c "cd '$TEST_TMPDIR/p' && bash '$P2E' --plan '$PLAN' --phase 1 --total 3 \
    --epic-template '$REPO_PLUGIN/defaults/templates/epic.md' \
    --output-dir '$TEST_TMPDIR/p/.aid-o/tasks' --counter-yaml '$TEST_TMPDIR/p/.aid-o/config/counter.yaml' \
    --project-root '$TEST_TMPDIR/p' \
    --generation-authority '$GEN/generation-authority.json' --transaction '$GEN/transaction.json'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"generation transaction not readable"* ]]
  [[ "$output" == *"$GEN/transaction.json"* ]]
  [[ "$output" == *"never implicitly recreated"* ]]
  # Fail-closed: the gate was NOT quietly run instead.
  [ "$(gen_cp1_calls)" = "0" ]
}
