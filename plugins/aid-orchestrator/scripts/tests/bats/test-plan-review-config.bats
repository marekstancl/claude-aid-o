#!/usr/bin/env bats
# aid-tier: t0
# test-plan-review-config.bats — review_checkpoints.plan_review and its validator.
# The plugin default loads with six roles; every broken invariant is refused
# with its reason; a project block overrides the default; a missing yq fails
# closed; unknown keys are ignored with one line.
# Origin: P093 Step 2 (plan review rebuild).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-review-config.sh"
  ROOT="$(mktemp -d)"
  mkdir -p "$ROOT/.aid-o/config/policies"
}
teardown() { rm -rf "$ROOT"; }

# _project <yq expression applied to the plugin default> — writes the project override
_project() {
  yq "$1" "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" \
    > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
}
_load_validate() { aid_plan_review_config_load "$ROOT" && aid_plan_review_config_validate; }

@test "config: the plugin default loads with six roles and validates" {
  aid_plan_review_config_load "$ROOT"
  [ "${#PR_ROLE[@]}" -eq 6 ]
  [ "$PR_ROUNDS_DEFAULT" = 2 ] && [ "$PR_MIN_ANSWERS" = 4 ]
  aid_plan_review_config_validate
}
@test "config: a seventh role is refused" {
  _project '.review_checkpoints.plan_review.reviewers += [{"role":"lens_l1","provider":"claude","model":"opus"}]'
  run _load_validate
  [ "$status" -eq 1 ]; [[ "$output" == *"unknown role lens_l1"* ]]
}
@test "config: a missing role is refused" {
  _project 'del(.review_checkpoints.plan_review.reviewers[] | select(.role == "reuse"))'
  run _load_validate
  [ "$status" -eq 1 ]; [[ "$output" == *"missing role reuse"* ]]
}
@test "config: a duplicate role is refused" {
  _project '.review_checkpoints.plan_review.reviewers[1].role = "generalist_a"'
  run _load_validate
  [ "$status" -eq 1 ]; [[ "$output" == *"duplicate role generalist_a"* ]]
}
@test "config: a banned model is refused" {
  _project '.review_checkpoints.plan_review.reviewers[2].model = "haiku"'
  run _load_validate
  [ "$status" -eq 1 ]; [[ "$output" == *"model haiku is in banned_models"* ]]
}
@test "config: a provider other than claude or codex, and min_answers out of range, are refused" {
  _project '.review_checkpoints.plan_review.reviewers[0].provider = "gemini"'
  run _load_validate
  [ "$status" -eq 1 ]; [[ "$output" == *"provider must be claude or codex"* ]]
  _project '.review_checkpoints.plan_review.min_answers = 7'
  run _load_validate
  [ "$status" -eq 1 ]; [[ "$output" == *"min_answers must be 1..6"* ]]
}
@test "config: the project block wins over the plugin default; same models mark the round degraded" {
  _project '.review_checkpoints.plan_review.reviewers[1] = {"role":"generalist_b","provider":"claude","model":"opus"}'
  aid_plan_review_config_load "$ROOT"
  [ "$PR_CONFIG_FILE" = "$ROOT/.aid-o/config/policies/review-checkpoints.yaml" ]
  [ "${PR_PROVIDER[1]}" = claude ]
  [ "$PR_DEGRADED" = 1 ]
}
@test "config: a project file without a plan_review block falls back to the default" {
  printf 'review_checkpoints:\n  enabled: true\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  run aid_plan_review_config_load "$ROOT"
  [ "$status" -eq 0 ]; [[ "$output" == *"using plugin default"* ]]
}
@test "config: an unknown key under plan_review is ignored with one line" {
  _project '.review_checkpoints.plan_review.max_rechecks = 4'
  run _load_validate
  [ "$status" -eq 0 ]
  [ "$(grep -c 'ignored legacy key plan_review.max_rechecks' <<<"$output")" -eq 1 ]
}
@test "config: without yq the load fails closed naming yq" {
  run env PATH=/nonexistent /bin/bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-review-config.sh'; aid_plan_review_config_load '$ROOT'"
  [ "$status" -eq 2 ]; [[ "$output" == *"yq not installed"* ]]
}
