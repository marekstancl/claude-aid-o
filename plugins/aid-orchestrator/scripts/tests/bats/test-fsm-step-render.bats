#!/usr/bin/env bats
# aid-tier: t2
# test-fsm-step-render.bats — human "Plan Step N of T" rendering.
# Provenance: P073 Step 4 (original rendering), P080 Step 13 (wording +
# single-authority collapse).
#
# `current_step` in fsm-state.yaml is 0-BASED and counts COMPLETED steps, so
# an operator reading "current_step=2" for the third step has to do the
# arithmetic themselves. The operator-facing FSM messages append a human form
# AFTER the machine values (so existing greps still match), while every
# MACHINE surface — the field itself, the `verify-state` JSON payload,
# evidence filenames — stays 0-based and byte-identical.
#
# P080 Step 13 changed the wording to carry the disambiguator
# (`Plan Step N of T is next` / `all T steps complete`) and collapsed the six
# verbatim prose copies of the rule to one authoritative section in
# skills/pipeline.md plus five references to it.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
}

teardown() {
  teardown_test_evidence_dir
}

# ─── the four operator-facing messages ───────────────────────────────────

@test "P073 Step 4: EXECUTE→EXECUTE refusal at the last step carries the human form" {
  local sf; sf="$(seed_test_state_files EXECUTE 3 3)"
  run "$FSM" transition EXECUTE EXECUTE "$sf"
  [ "$status" -ne 0 ]
  # Machine values first (grep compatibility), human form appended.
  [[ "$output" == *"current_step=3 == total_steps=3"* ]]
  [[ "$output" == *"(human: all 3 steps complete)"* ]]
}

@test "P073 Step 4: EXECUTE→GATES refusal with steps remaining names the NEXT step in 1-based form" {
  local sf; sf="$(seed_test_state_files EXECUTE 2 7)"
  run "$FSM" transition EXECUTE GATES "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"current_step=2 < total_steps=7"* ]]
  [[ "$output" == *"(human: Plan Step 3 of 7 is next)"* ]]
}

@test "P073 Step 4: advance-to-gates refusal with steps remaining carries the human form" {
  local sf; sf="$(seed_test_state_files EXECUTE 1 5)"
  run "$FSM" advance-to-gates "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"current_step (1) >= total_steps (5)"* ]]
  [[ "$output" == *"(human: Plan Step 2 of 5 is next)"* ]]
}

@test "P073 Step 4: the malformed-state error explains the 0-based semantics" {
  local sf; sf="$(seed_test_state_files EXECUTE not-a-number 5)"
  run "$FSM" advance-to-gates "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be integers"* ]]
  [[ "$output" == *"0-based"* ]]
  # No arithmetic was attempted on the garbage value.
  [[ "$output" != *"(human:"* ]]
}

# ─── edge cases from the step spec ───────────────────────────────────────

@test "P073 Step 4: a degenerate plan (total_steps == 0) renders machine values only" {
  local sf; sf="$(seed_test_state_files EXECUTE 0 0)"
  run "$FSM" transition EXECUTE EXECUTE "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"current_step=0 == total_steps=0"* ]]
  [[ "$output" != *"(human:"* ]]
}

@test "P073 Step 4: the first step renders as 'step 1', never 'step 0'" {
  local sf; sf="$(seed_test_state_files EXECUTE 0 4)"
  run "$FSM" transition EXECUTE GATES "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"(human: Plan Step 1 of 4 is next)"* ]]
  [[ "$output" != *"Step 0 of"* ]]
  [[ "$output" != *"step 0 of"* ]]
}

# ─── machine compatibility surface is frozen ─────────────────────────────

@test "P073 Step 4: the verify-state JSON payload still reports the bare 0-based current_step" {
  local sf; sf="$(seed_test_state_files EXECUTE 2 7)"
  run "$FSM" verify-state "$sf"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.current_step')" = "2" ]
  [ "$(echo "$output" | jq -r '.total_steps')" = "7" ]
  # No human rendering leaked into the machine surface.
  [[ "$output" != *"human"* ]]
  # P080 Step 13: the new wording must not leak here either.
  [[ "$output" != *"Plan Step"* ]]
  [[ "$output" != *"steps complete"* ]]
  # The payload carries a BARE 0-based integer, not a quoted or rendered form.
  [[ "$output" == *'"current_step":2'* ]]
}

@test "P080 Step 13: evidence filenames stay 0-based — plan step 1 is step-0-verify.md" {
  local sf; sf="$(seed_test_state_files EXECUTE 0 4)"
  run "$FSM" increment-step "$sf"
  [ "$status" -ne 0 ]
  # The precondition names the frozen 0-based filename for plan step 1 …
  [[ "$output" == *"step-0-verify.md"* ]]
  # … and never renames it to the human 1-based form.
  [[ "$output" != *"step-1-verify.md"* ]]
}

@test "P073 Step 4: the state file itself is untouched by a refused transition" {
  local sf; sf="$(seed_test_state_files EXECUTE 2 7)"
  local before; before="$(sha256sum "$sf" | awk '{print $1}')"
  run "$FSM" transition EXECUTE GATES "$sf"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$sf" | awk '{print $1}')" = "$before" ]
  [ "$(grep '^current_step:' "$sf")" = "current_step: 2" ]
}

# ─── prose surfaces carry the rendering rule, not just the template ──────

@test "P080 Step 13: the full rule lives in exactly ONE file; the other five sites reference it" {
  local root="$AID_PLUGIN_PATH"
  # The rule must define the CAP, not just the +1 — a bare +1 renders
  # "T+1 of T" for a completed run (Codex review finding on the first cut).
  # This literal is unique to the authoritative definition.
  local full='executing_step = min(current_step + 1, total_steps)'
  local ref='Step rendering rule in skills/pipeline.md'
  local f

  # (a) Exactly one FILE carries the full definition, exactly once.
  run bash -c "grep -rl '$full' '$root/commands' '$root/skills'"
  [ "$status" -eq 0 ]
  [ "$output" = "$root/skills/pipeline.md" ]
  run bash -c "grep -c '$full' '$root/skills/pipeline.md'"
  [ "$output" -eq 1 ]

  # (b) All five prose surfaces point at that one section.
  for f in commands/aid-status.md commands/aid-run.md commands/aid-stop.md \
           skills/pipeline.md skills/memory.md; do
    run bash -c "grep -c '$ref' '$root/$f'"
    [ "$output" -ge 1 ]
  done

  # (c) The four non-authoritative files restate nothing.
  for f in commands/aid-status.md commands/aid-run.md commands/aid-stop.md \
           skills/memory.md; do
    run bash -c "grep -c '$full' '$root/$f' || true"
    [ "$output" -eq 0 ]
  done

  # (d) The authoritative section states the disambiguated wording, so the
  # prose and the _fsm_human_step helper cannot drift apart again.
  run bash -c "grep -c 'is next' '$root/skills/pipeline.md'"
  [ "$output" -ge 1 ]
  run bash -c "grep -c 'steps complete' '$root/skills/pipeline.md'"
  [ "$output" -ge 1 ]
  # No template still renders the bare 0-based value.
  run bash -c "grep -rn '{current_step}/{total_steps}' '$root/commands' '$root/skills' || true"
  [ -z "$output" ]
  run bash -c "grep -rn '{current_step} of {total_steps}' '$root/commands' '$root/skills' || true"
  [ -z "$output" ]
  # And no template applies an UNCAPPED +1 either.
  run bash -c "grep -rn '{current_step + 1}' '$root/commands' '$root/skills' || true"
  [ -z "$output" ]
}

# ─── every covered seam speaks the new wording, none the old ─────────────

@test "P080 Step 13: no FSM seam emits the pre-P080 bare wording" {
  local sf out

  sf="$(seed_test_state_files EXECUTE 3 3)"
  run "$FSM" transition EXECUTE EXECUTE "$sf"; out="$output"
  [[ "$out" != *"(human: step "* ]]
  [[ "$out" == *"(human: all 3 steps complete)"* ]]

  sf="$(seed_test_state_files EXECUTE 2 7)"
  run "$FSM" transition EXECUTE GATES "$sf"; out="$output"
  [[ "$out" != *"(human: step "* ]]
  [[ "$out" == *"(human: Plan Step 3 of 7 is next)"* ]]

  sf="$(seed_test_state_files EXECUTE 1 5)"
  run "$FSM" advance-to-gates "$sf"; out="$output"
  [[ "$out" != *"(human: step "* ]]
  [[ "$out" == *"(human: Plan Step 2 of 5 is next)"* ]]
}
