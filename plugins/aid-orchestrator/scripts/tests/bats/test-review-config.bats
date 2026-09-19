#!/usr/bin/env bats
# aid-tier: t0
# test-review-config.bats — the generic reader of review_checkpoints.<block>
# (lib/aid-review-config.sh). The CP1 cases of test-plan-review-config.bats run
# here against the generic library with plan_review as the block (the suite
# asserts its own CP1 case count equals the old suite's while both exist); a
# step_review block with one role loads; a role absent from the checkpoint's
# roles skill, a bad `when`, a block with only conditional roles, the master
# switch and the answer floor are covered.
# Origin: P094 Step 4 (step review rebuild); the old suite goes in Step 14.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  source "$AID_PLUGIN_PATH/scripts/lib/aid-review-config.sh"
  ROOT="$(mktemp -d)"
  mkdir -p "$ROOT/.aid-o/config/policies"
  PLAN_SKILL="$AID_PLUGIN_PATH/skills/plan-review-roles.md"
  STEP_SKILL="$AID_PLUGIN_PATH/skills/step-review-roles.md"
  DEFAULT="$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml"
}
teardown() { rm -rf "$ROOT"; }

# _project <yq expression applied to the plugin default> — writes the project override
_project() { yq "$1" "$DEFAULT" > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"; }
_load_cp1() { aid_review_config_load "$ROOT" plan_review "$PLAN_SKILL" && aid_review_config_validate; }
_load_step() { aid_review_config_load "$ROOT" step_review "$STEP_SKILL" && aid_review_config_validate; }
_load_epic() { aid_review_config_load "$ROOT" epic_review "$STEP_SKILL" && aid_review_config_validate; }

# ── the CP1 cases (mirror test-plan-review-config.bats; count asserted below) ──
@test "cp1: the plugin default loads with six roles and validates" {
  aid_review_config_load "$ROOT" plan_review "$PLAN_SKILL"
  [ "${#RC_ROLE[@]}" -eq 6 ]
  [ "$RC_ROUNDS_DEFAULT" = 2 ] && [ "$RC_MIN_ANSWERS" = 4 ]
  aid_review_config_validate
}
@test "cp1: a seventh role is refused" {
  _project '.review_checkpoints.plan_review.reviewers += [{"role":"lens_l1","provider":"claude","model":"opus"}]'
  run _load_cp1
  [ "$status" -eq 1 ]; [[ "$output" == *"unknown role lens_l1"* ]]
}
@test "cp1: a missing role is refused" {
  _project 'del(.review_checkpoints.plan_review.reviewers[] | select(.role == "reuse"))'
  run _load_cp1
  [ "$status" -eq 1 ]; [[ "$output" == *"missing role reuse"* ]]
}
@test "cp1: a duplicate role is refused" {
  _project '.review_checkpoints.plan_review.reviewers[1].role = "generalist_a"'
  run _load_cp1
  [ "$status" -eq 1 ]; [[ "$output" == *"duplicate role generalist_a"* ]]
}
@test "cp1: a banned model is refused" {
  _project '.review_checkpoints.plan_review.reviewers[2].model = "haiku"'
  run _load_cp1
  [ "$status" -eq 1 ]; [[ "$output" == *"model haiku is in banned_models"* ]]
}
@test "cp1: a provider other than claude or codex, and min_answers out of range, are refused" {
  _project '.review_checkpoints.plan_review.reviewers[0].provider = "gemini"'
  run _load_cp1
  [ "$status" -eq 1 ]; [[ "$output" == *"provider must be claude or codex"* ]]
  _project '.review_checkpoints.plan_review.min_answers = 7'
  run _load_cp1
  [ "$status" -eq 1 ]; [[ "$output" == *"min_answers must be 1..6"* ]]
}
@test "cp1: the project block wins over the plugin default; same models mark the round degraded" {
  _project '.review_checkpoints.plan_review.reviewers[1] = {"role":"generalist_b","provider":"claude","model":"opus"}'
  aid_review_config_load "$ROOT" plan_review "$PLAN_SKILL"
  [ "$RC_CONFIG_FILE" = "$ROOT/.aid-o/config/policies/review-checkpoints.yaml" ]
  [ "${RC_PROVIDER[1]}" = claude ]
  [ "$RC_DEGRADED" = 1 ]
}
@test "cp1: a project file without a plan_review block falls back to the default" {
  printf 'review_checkpoints:\n  enabled: true\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  run aid_review_config_load "$ROOT" plan_review "$PLAN_SKILL"
  [ "$status" -eq 0 ]; [[ "$output" == *"using plugin default"* ]]
}
@test "cp1: an unknown key under plan_review is ignored with one line" {
  _project '.review_checkpoints.plan_review.max_rechecks = 4'
  run _load_cp1
  [ "$status" -eq 0 ]
  [ "$(grep -c 'ignored unknown key plan_review.max_rechecks' <<<"$output")" -eq 1 ]
}
@test "cp1: without yq the load fails closed naming yq" {
  run env PATH=/nonexistent /bin/bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-review-config.sh'; aid_review_config_load '$ROOT' plan_review '$PLAN_SKILL'"
  [ "$status" -eq 2 ]; [[ "$output" == *"yq not installed"* ]]
}
@test "cp1: this suite carries every case of test-plan-review-config.bats while that suite exists" {
  local old="$BATS_TEST_DIRNAME/test-plan-review-config.bats"
  [ -f "$old" ] || skip "the old suite is gone (P094 Step 14)"
  [ "$(grep -c '^@test "cp1: ' "$BATS_TEST_FILENAME")" -ge "$(grep -c '^@test ' "$old")" ]
}

# ── the step and EPIC blocks ───────────────────────────────────────────────
@test "step_review: the plugin default loads with one unconditional and one conditional role; the floor is the unconditional count" {
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL"
  [ "${#RC_ROLE[@]}" -eq 2 ]; [ "${RC_WHEN[0]}" = "" ]; [ "${RC_WHEN[1]}" = "review+security" ]
  [ "$RC_MIN_ANSWERS" = 1 ]; [ "$(aid_review_config_floor 2)" = 1 ]; [ "$(aid_review_config_floor 1)" = 1 ]
  [ "$RC_EXTRA_SKIP_THRESHOLD_FILES" = 1 ]; [ "$RC_EXTRA_SKIP_THRESHOLD_LINES" = 50 ]
  aid_review_config_validate
}
@test "step_review: a single-role block passes; epic_review loads three roles" {
  _project '.review_checkpoints.step_review.reviewers = [{"role":"step_generalist","provider":"claude","model":"opus"}]'
  run _load_step; [ "$status" -eq 0 ]
  aid_review_config_load "$ROOT" epic_review "$STEP_SKILL"
  [ "${#RC_ROLE[@]}" -eq 3 ]; [ "$RC_MIN_ANSWERS" = 3 ]; aid_review_config_validate
}
@test "step_review: a role absent from step-review-roles.md is refused naming the skill" {
  _project '.review_checkpoints.step_review.reviewers[0].role = "reuse"'
  run _load_step
  [ "$status" -eq 1 ]; [[ "$output" == *"unknown role reuse"* ]]; [[ "$output" == *"step-review-roles.md"* ]]
}
@test "step_review: when must be review+security; a block with only conditional roles is refused" {
  _project '.review_checkpoints.step_review.reviewers[1].when = "sometimes"'
  run _load_step
  [ "$status" -eq 1 ]; [[ "$output" == *"when must be review+security"* ]]
  _project '.review_checkpoints.step_review.reviewers[0].when = "review+security"'
  run _load_step
  [ "$status" -eq 1 ]; [[ "$output" == *"no unconditional role"* ]]
}
@test "step_review: required_roles none — a subset is fine; plan_review requires all six" {
  _project 'del(.review_checkpoints.step_review.reviewers[1])'
  run _load_step; [ "$status" -eq 0 ]
  [ "$(yq --front-matter=extract -r .required_roles "$STEP_SKILL")" = none ]
  [ "$(yq --front-matter=extract -r .required_roles "$PLAN_SKILL")" = all ]
}
@test "RC_ENABLED: the checkpoint's own toggle and the master switch both disable it" {
  printf 'review_checkpoints:\n  cp2_step_review: false\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL" 2>/dev/null
  [ "$RC_ENABLED" = 0 ]
  printf 'review_checkpoints:\n  enabled: false\n  cp2_step_review: true\n  cp1_plan_review: true\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL" 2>/dev/null; [ "$RC_ENABLED" = 0 ]
  aid_review_config_load "$ROOT" plan_review "$PLAN_SKILL" 2>/dev/null; [ "$RC_ENABLED" = 0 ]
  printf 'review_checkpoints:\n  enabled: true\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL" 2>/dev/null; [ "$RC_ENABLED" = 1 ]
  RC_CHECKPOINT=cp6; printf 'review_checkpoints:\n  cp6_fast_mode_review: false\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL" 2>/dev/null; [ "$RC_ENABLED" = 0 ]
}
@test "a block may declare min_answers itself; without it the floor is the unconditional role count" {
  _project '.review_checkpoints.step_review.min_answers = 2'
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL" 2>/dev/null
  [ "$RC_MIN_ANSWERS" = 2 ]; [ "$(aid_review_config_floor 1)" = 1 ]
}
@test "a missing roles skill fails closed naming the path" {
  run aid_review_config_load "$ROOT" step_review "$ROOT/nope.md"
  [ "$status" -eq 1 ]; [[ "$output" == *"roles skill not found"* ]]
}
