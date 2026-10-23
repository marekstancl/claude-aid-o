#!/usr/bin/env bats
# aid-tier: t2
# test-review-config.bats — the generic reader of review_checkpoints.<block>
# (lib/aid-review-config.sh). The CP1 cases of test-plan-review-config.bats run
# here against the generic library with plan_review as the block (the suite
# asserts its own CP1 case count equals the old suite's while both exist); a
# step_review block with one role loads; a role absent from the checkpoint's
# roles skill, a bad `when`, a block with only conditional roles, the master
# switch and the answer floor are covered; the removed EPIC review (CP3) keys warn (P114).
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

# ── the CP1 cases (mirror test-plan-review-config.bats; count asserted below) ──
@test "cp1: the plugin default loads with six roles and validates" {
  aid_review_config_load "$ROOT" plan_review "$PLAN_SKILL"
  [ "${#RC_ROLE[@]}" -eq 6 ]
  [ "$RC_ROUNDS_DEFAULT" = 1 ] && [ "$RC_MIN_ANSWERS" = 4 ]
  [ "$RC_SECOND_ROUND_WHEN" = blocker_and_fix_check ]
  aid_review_config_validate
}
@test "cp1: second_round_when is a known key; a value other than blocker_and_fix_check is refused by name (P109)" {
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-review-config.sh'; aid_review_config_load '$ROOT' plan_review '$PLAN_SKILL' 2>&1"
  [[ "$output" != *"second_round_when"* ]]   # known: no unknown-key notice
  _project '.review_checkpoints.plan_review.second_round_when = "sometimes"'
  run _load_cp1
  [ "$status" -eq 1 ]; [[ "$output" == *"second_round_when must be blocker_and_fix_check (got 'sometimes')"* ]]
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
@test "step_review: the plugin default asks both roles on every reviewed step (2.109.0) and the claims role on a documentation step (3.8.0); a gated role lowers the floor to the unconditional count" {
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL"
  [ "${#RC_ROLE[@]}" -eq 3 ]; [ "${RC_WHEN[0]}" = "" ]; [ "${RC_WHEN[1]}" = "" ]
  [ "${RC_ROLE[2]}" = final_claims ]; [ "${RC_WHEN[2]}" = docs_surface ]
  [ "$RC_MIN_ANSWERS" = 2 ]
  _project '.review_checkpoints.step_review.reviewers[1].when = "review+security"'
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL"
  [ "$RC_MIN_ANSWERS" = 1 ]; [ "$(aid_review_config_floor 2)" = 1 ]; [ "$(aid_review_config_floor 1)" = 1 ]
  [ "$RC_EXTRA_SKIP_THRESHOLD_FILES" = 3 ]; [ "$RC_EXTRA_SKIP_THRESHOLD_LINES" = 120 ]   # P110 threshold
  aid_review_config_validate
}
@test "step_review: a single-role block passes" {
  _project '.review_checkpoints.step_review.reviewers = [{"role":"step_generalist","provider":"claude","model":"opus"}]'
  run _load_step; [ "$status" -eq 0 ]
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
  _project '.review_checkpoints.step_review.reviewers[].when = "review+security"'
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
@test "stand_in_model: read into RC_STAND_IN_MODEL, opus when unset, refused when banned" {
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL" 2>/dev/null
  [ "$RC_STAND_IN_MODEL" = opus ]
  _project 'del(.review_checkpoints.step_review.stand_in_model)'
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL" 2>/dev/null; [ "$RC_STAND_IN_MODEL" = opus ]
  _project '.review_checkpoints.step_review.stand_in_model = "sonnet"'
  run aid_review_config_load "$ROOT" step_review "$STEP_SKILL"
  [ "$status" -eq 0 ]; [[ "$output" != *"unknown key"* ]]
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL" 2>/dev/null; [ "$RC_STAND_IN_MODEL" = sonnet ]
  _project '.review_checkpoints.step_review.stand_in_model = "haiku"'
  run _load_step
  [ "$status" -eq 1 ]; [[ "$output" == *"banned_models"* ]]
}

@test "effort: read into RC_EFFORT, medium when unset, a value outside low|medium|high refused" {
  _load_step
  [ "${RC_EFFORT[*]}" = "low low low" ]   # P110: the step roles light, security full via full_when (claims: 3.8.0)
  _load_cp1
  [ "${RC_EFFORT[0]}" = medium ]
  _project '.review_checkpoints.step_review.reviewers[0].effort = "extreme"'
  run _load_step
  [ "$status" -eq 1 ]; [[ "$output" == *"effort must be low, medium or high (got 'extreme')"* ]]
}

# ── final_review (CP7) ────────────────────────────────────────────────────────
@test "final_review: the default loads with two roles (P110); its toggle switches it off; a banned model is refused" {
  aid_review_config_load "$ROOT" final_review "$STEP_SKILL" && aid_review_config_validate
  [ "${RC_ROLE[*]}" = "final_criteria final_generalist" ]
  [ "$RC_ENABLED" = 1 ] && [ "$RC_STAND_IN_MODEL" = opus ]
  yq '.review_checkpoints.cp7_plan_final_review = false' "$DEFAULT" > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  aid_review_config_load "$ROOT" final_review "$STEP_SKILL"; [ "$RC_ENABLED" = 0 ]
  yq '.review_checkpoints.final_review.reviewers[0].model = "haiku"' "$DEFAULT" > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  aid_review_config_load "$ROOT" final_review "$STEP_SKILL"
  run aid_review_config_validate; [ "$status" -eq 1 ]; [[ "$output" == *"haiku"* ]]
}

@test "light_max_prompt_lines: 800 by default, a non-integer is refused" {
  aid_review_config_load "$ROOT" step_review "$STEP_SKILL"
  [ "$RC_LIGHT_MAX_PROMPT_LINES" = 800 ]
  _project '.review_checkpoints.step_review.light_max_prompt_lines = "lots"'
  run _load_step
  [ "$status" -eq 1 ]; [[ "$output" == *"light_max_prompt_lines must be a positive integer"* ]]
}

# ── P110: the step review sized by the change ──────────────────────────────
@test "second-round: open_finding_and_fix is the step_review default and is refused for plan_review" {
  _load_step
  [ "$RC_SECOND_ROUND_WHEN" = open_finding_and_fix ] && [ "$RC_ROUNDS_DEFAULT" = 1 ]
  _project '.review_checkpoints.plan_review.second_round_when = "open_finding_and_fix"'
  run _load_cp1
  [ "$status" -eq 1 ]; [[ "$output" == *"second_round_when must be blocker_and_fix_check (got 'open_finding_and_fix')"* ]]
  _project '.review_checkpoints.step_review.second_round_when = "blocker_and_fix_check"'
  run _load_step
  [ "$status" -eq 1 ]; [[ "$output" == *"second_round_when must be open_finding_and_fix"* ]]
}
@test "second-round: full_when is read per role (step_security on review+security); another value is refused by name" {
  _load_step
  i="$(aid_review_role_index step_security)"; [ "${RC_FULL_WHEN[$i]}" = "review+security" ]
  [ "${RC_EFFORT[$i]}" = low ]
  i="$(aid_review_role_index step_generalist)"; [ -z "${RC_FULL_WHEN[$i]}" ] && [ -z "${RC_WHEN[$i]}" ]
  _project '.review_checkpoints.step_review.reviewers[1].full_when = "review"'
  run _load_step
  [ "$status" -eq 1 ]; [[ "$output" == *"role step_security: full_when must be review+security (got 'review')"* ]]
}
@test "second-round: the open_finding_and_fix arm needs round n-1 closed with an open blocker or major and HEAD moved" {
  _load_step
  local cp="$ROOT/cp2/step-0"; mkdir -p "$cp/round-1"
  echo '{}' > "$cp/round-1/measurement.json"; echo '{"head_sha":"aaa"}' > "$cp/round-1/round.json"
  echo '{"findings":[{"severity":"major","status":"open"}]}' > "$cp/round-1/merged.json"
  aid_review_second_round_allowed "$cp" 2 bbb
  ! aid_review_second_round_allowed "$cp" 2 aaa          # HEAD has not moved
  ! aid_review_second_round_allowed "$cp" 3 bbb          # only rounds_default + 1
  echo '{"findings":[{"severity":"minor","status":"open"},{"severity":"major","status":"fixed"}]}' > "$cp/round-1/merged.json"
  ! aid_review_second_round_allowed "$cp" 2 bbb          # nothing open to confirm
}

@test "final_review: final_claims listed by a project is accepted (the role section stays optional)" {
  _project '.review_checkpoints.final_review.reviewers += [{"role": "final_claims", "provider": "claude", "model": "opus", "effort": "low"}]'
  aid_review_config_load "$ROOT" final_review "$STEP_SKILL" && aid_review_config_validate
  [ "${RC_ROLE[*]}" = "final_criteria final_generalist final_claims" ]
}

# ── 3.0.0 (P114): the EPIC review (CP3) is gone; its keys are legacy keys ──
@test "cp3-removed: a project that still sets cp3_integration_review: true loads with the legacy-key warning" {
  _project '.review_checkpoints.cp3_integration_review = true'
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-review-config.sh'; aid_review_config_load '$ROOT' step_review '$STEP_SKILL' && aid_review_config_validate"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignored legacy key cp3_integration_review"* ]]
}
@test "cp3-removed: a project epic_review block loads with the legacy-key warning and is never read" {
  _project '.review_checkpoints.epic_review = {"rounds_default": 2, "reviewers": [{"role":"epic_generalist","provider":"claude","model":"opus"}]}'
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-review-config.sh'; aid_review_config_load '$ROOT' step_review '$STEP_SKILL' && aid_review_config_validate && echo \"roles=\${RC_ROLE[*]}\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignored legacy key epic_review"* && "$output" != *epic_generalist* ]]
}
@test "cp3-removed: a project file whose only content is the removed key loads the plugin default and warns" {
  printf 'review_checkpoints:\n  cp3_integration_review: true\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-review-config.sh'; aid_review_config_load '$ROOT' step_review '$STEP_SKILL' && aid_review_config_validate && echo \"file=\$RC_CONFIG_FILE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignored legacy key cp3_integration_review"* ]]
  [[ "$output" == *"file=$DEFAULT"* ]]
}
@test "cp3-removed: aid-review-round.sh --checkpoint cp3 is refused naming CP2 and CP7" {
  mkdir -p "$ROOT/run"
  run bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" prepare --checkpoint cp3 --evidence-dir "$ROOT/run" --round 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"CP3 was removed in 3.0.0"* && "$output" == *CP2* && "$output" == *CP7* ]]
  run bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp3 --evidence-dir "$ROOT/run"
  [ "$status" -eq 2 ]; [[ "$output" == *"CP3 was removed in 3.0.0"* ]]
}
