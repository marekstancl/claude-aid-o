#!/usr/bin/env bats
# test-fsm-step-render.bats — P073 Step 4: human "Step N/T" rendering.
#
# `current_step` in fsm-state.yaml is 0-BASED and counts COMPLETED steps, so
# an operator reading "current_step=2" for the third step has to do the
# arithmetic themselves. The four operator-facing FSM messages now append a
# human form AFTER the machine values (so existing greps still match), while
# every MACHINE surface — the field itself, the `verify-state` JSON payload,
# evidence filenames — stays 0-based and byte-identical.

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
  [[ "$output" == *"(human: step 3 of 3 complete)"* ]]
}

@test "P073 Step 4: EXECUTE→GATES refusal with steps remaining names the NEXT step in 1-based form" {
  local sf; sf="$(seed_test_state_files EXECUTE 2 7)"
  run "$FSM" transition EXECUTE GATES "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"current_step=2 < total_steps=7"* ]]
  [[ "$output" == *"(human: step 3 of 7 is next)"* ]]
}

@test "P073 Step 4: advance-to-gates refusal with steps remaining carries the human form" {
  local sf; sf="$(seed_test_state_files EXECUTE 1 5)"
  run "$FSM" advance-to-gates "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"current_step (1) >= total_steps (5)"* ]]
  [[ "$output" == *"(human: step 2 of 5 is next)"* ]]
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
  [[ "$output" == *"(human: step 1 of 4 is next)"* ]]
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

@test "P073 Step 4: every enumerated prose surface renders the +1 form and states the rule" {
  local root="$AID_PLUGIN_PATH"
  local f
  for f in commands/aid-status.md commands/aid-run.md commands/aid-stop.md \
           skills/pipeline.md skills/memory.md; do
    run grep -c 'Step rendering rule' "$root/$f"
    [ "$output" -ge 1 ]
  done
  # No template still renders the bare 0-based value.
  run bash -c "grep -rn '{current_step}/{total_steps}' '$root/commands' '$root/skills' || true"
  [ -z "$output" ]
  run bash -c "grep -rn '{current_step} of {total_steps}' '$root/commands' '$root/skills' || true"
  [ -z "$output" ]
}
