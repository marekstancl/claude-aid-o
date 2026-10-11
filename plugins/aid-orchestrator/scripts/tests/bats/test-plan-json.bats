#!/usr/bin/env bats
# aid-tier: t0
# test-plan-json.bats — P111 Step 1: THE plan.json builder (lib/aid-plan-json.sh).
#
# The direct run builds plan.json of the WHOLE plan from the shared per-step
# reader; the EPIC path hands its parsed table over as a prepared step list.
# The EPIC path's byte identity is test-epic-to-json-regression.sh's job; this
# suite proves the direct path's shape and the refusals.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-plan-json.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/templates/plan.schema.json"
  LINT="$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh"
  export LIB SCHEMA LINT
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf 'gates:\n  docs_updated:\n    command: "true"\n  bats_all:\n    command: "true"\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  FOREIGN="$TEST_TMPDIR/docs"
  mkdir -p "$FOREIGN"
  git -C "$FOREIGN" init -q -b main
  git -C "$FOREIGN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  export FOREIGN
  PLAN="$TEST_PROJECT_ROOT/.aid-o/plans/P900-direct.md"
  export PLAN
}

teardown() {
  teardown_test_evidence_dir
}

# _write_plan [frontmatter-extra] — three steps: 1 alone, 2 and 3 in one wave.
_write_plan() {
  cat > "$PLAN" <<EOF
---
id: P900
type: regular
${1:-}
---

# Plan: direct fixture

## Implementation Steps

### Step 1: Build the parser library for the direct path

**Objective:** Build the parser library that both paths share.

**Files:**
- Create: \`scripts/lib/parser.sh\` — the parser
- Test: \`scripts/tests/test-parser.sh\` (tier: t0) — proves it

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] \`bash scripts/tests/test-parser.sh\` passes.

**AID Role:** backend

**Zavírá:** AC1

### Step 2: Document the parser for the plan readers

**Objective:** Document the parser in the command reference.

**Files:**
- Modify: \`docs/parser.md\` — the reference

**Parallel group:** wave-a

**Dependencies:**
- Depends on: Step 1

**Acceptance Criteria:**
- [ ] \`grep -q parser docs/parser.md\` exits 0.

**AID Role:** docs

**Zavírá:** AC2, AC3

### Step 3: Write the parser changelog entry for release

**Objective:** Write the changelog entry for the parser release.

**Files:**
- Modify: \`CHANGELOG.md\` — the entry

**Parallel group:** wave-a

**Dependencies:**
- Depends on: Step 1

**Acceptance Criteria:**
- [ ] \`grep -q parser CHANGELOG.md\` exits 0.

**AID Role:** release
EOF
}

# _build [frontmatter-extra] — steps from the plan + the direct builder.
_build() {
  _write_plan "${1:-}"
  bash -c '
    set -euo pipefail
    source "$AID_PLUGIN_PATH/scripts/lib/common.sh"
    source "$LIB"
    aid_plan_json_steps_from_plan "$PLAN" > "$TEST_TMPDIR/steps.json"
    aid_plan_repo_roots_json "$PLAN" P900 project > "$TEST_TMPDIR/rr.json"
    aid_plan_json_build --steps-json "$TEST_TMPDIR/steps.json" --out "$TEST_TMPDIR/plan.json" \
      --epic-id E-900-1_1 --plan "$PLAN" --direct \
      --execution "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" --repo-roots-json "$TEST_TMPDIR/rr.json"
  '
}

_schema_ok() {
  python3 -c 'import json,sys,jsonschema; jsonschema.validate(json.load(open(sys.argv[1])), json.load(open(sys.argv[2])))' "$1" "$SCHEMA"
}

@test "json: a three-step plan builds plan.json with plan_step, zavira, the wave, Files outputs and allowed paths, criteria and direct" {
  run _build
  [ "$status" -eq 0 ]
  P="$TEST_TMPDIR/plan.json"
  [ "$(jq -r '.epic_id' "$P")" = "E-900-1_1" ]
  [ "$(jq -r '.direct' "$P")" = "true" ]
  [ "$(jq -c '[.steps[].plan_step]' "$P")" = "[1,2,3]" ]
  [ "$(jq -c '[.steps[].id]' "$P")" = '["step_1_backend","step_2_docs","step_3_release"]' ]
  [ "$(jq -c '.steps[1].zavira' "$P")" = '["AC2","AC3"]' ]
  [ "$(jq -c '.steps[2].zavira' "$P")" = '[]' ]
  [ "$(jq -c '.parallel_groups' "$P")" = '[["step_2_docs","step_3_release"]]' ]
  [ "$(jq -c '.steps[0].allowed_paths' "$P")" = '["scripts/lib/parser.sh","scripts/tests/test-parser.sh"]' ]
  [ "$(jq -r '.steps[0].outputs[0]' "$P")" = 'Create: `scripts/lib/parser.sh` — the parser' ]
  [ "$(jq -r '.steps[0].acceptance_criteria[0]' "$P")" = '`bash scripts/tests/test-parser.sh` passes.' ]
  [ "$(jq -r '.source_plan_sha256' "$P")" = "$(sha256sum "$PLAN" | cut -d' ' -f1)" ]
  [ "$(jq -c '[.dependencies[] | [.before, .after]]' "$P")" = '[["step_1_backend","step_2_docs"],["step_1_backend","step_3_release"]]' ]
}

@test "json: the direct plan.json validates against plan.schema.json, repo_roots with its base included" {
  run _build "repo_roots:
  - name: docs
    path: ${FOREIGN}"
  [ "$status" -eq 0 ]
  run _schema_ok "$TEST_TMPDIR/plan.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.repo_roots[0].branch' "$TEST_TMPDIR/plan.json")" = "plan/P900-project" ]
  [ "$(jq -r '.repo_roots[0].worktree' "$TEST_TMPDIR/plan.json")" = "$(realpath "$FOREIGN")/.aid-worktrees/plan-P900--docs" ]
  [ "$(jq -r '.repo_roots[0].base' "$TEST_TMPDIR/plan.json")" = "$(git -C "$FOREIGN" rev-parse main)" ]
}

@test "json: the direct gates are what the project's execution.yaml defines (never empty when it declares one)" {
  run _build
  [ "$status" -eq 0 ]
  [ "$(jq -c '.gates' "$TEST_TMPDIR/plan.json")" = '["docs_updated"]' ]
  printf 'gates:\n  bats_all:\n    command: "true"\n' > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  run _build
  [ "$status" -eq 0 ]
  [ "$(jq -c '.gates' "$TEST_TMPDIR/plan.json")" = '[]' ]
}

@test "json: a prepared EPIC step list builds the EPIC slice with its own fields, no direct key" {
  cat > "$TEST_TMPDIR/steps.json" <<'EOF'
[{"number":1,"role":"backend","objective":"Prepared backend objective here","depends_on":"---","parallel_group":"---","zavira":["AC1"],"plan_step":4,
  "outputs":["Create: `a.sh` — x"],"acceptance_criteria":["a passes"],"allowed_paths":["a.sh"],"forbidden_paths":["b/"],"constraints":["c"],"ui_change_mode":null,"ui_change_contract":null},
 {"number":2,"role":"qa","objective":"Prepared qa objective for the slice","depends_on":"1","parallel_group":"---","zavira":[],"plan_step":5,
  "outputs":[],"acceptance_criteria":[],"allowed_paths":[],"forbidden_paths":[],"constraints":[],"ui_change_mode":null,"ui_change_contract":null}]
EOF
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_json_build --steps-json "$TEST_TMPDIR/steps.json" --out "$TEST_TMPDIR/plan.json" --epic-id E-900-2_2'
  [ "$status" -eq 0 ]
  P="$TEST_TMPDIR/plan.json"
  [ "$(jq -r 'has("direct")' "$P")" = "false" ]
  [ "$(jq -c '[.steps[].plan_step]' "$P")" = "[4,5]" ]
  [ "$(jq -c '.steps[0].forbidden_paths' "$P")" = '["b/"]' ]
  [ "$(jq -c '.steps[1].inputs' "$P")" = '["EPIC specification","Output from step_1_backend"]' ]
  [ "$(jq -r '.dependencies[0].reason' "$P")" = "Declared in EPIC steps table" ]
}

@test "json: a cyclic dependency is refused by name" {
  cat > "$TEST_TMPDIR/steps.json" <<'EOF'
[{"number":1,"role":"backend","objective":"Cycle step one objective","depends_on":"2","parallel_group":"---"},
 {"number":2,"role":"backend","objective":"Cycle step two objective","depends_on":"1","parallel_group":"---"}]
EOF
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_json_build --steps-json "$TEST_TMPDIR/steps.json" --out "$TEST_TMPDIR/plan.json" --epic-id E-900-1_1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Circular dependency"*"step_1_backend"* ]]
  [ ! -f "$TEST_TMPDIR/plan.json" ]
}

@test "json: a step without Files bullets gets empty outputs and allowed paths" {
  _write_plan
  python3 - "$PLAN" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=s.replace("**Files:**\n- Modify: `CHANGELOG.md` — the entry\n\n","")
open(p,'w').write(s)
PY
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_json_steps_from_plan "$PLAN"'
  [ "$status" -eq 0 ]
  [ "$(jq -c '.[2].outputs, .[2].allowed_paths' <<< "$output" | paste -sd' ')" = "[] []" ]
}

@test "json: a duplicate step number and an empty step list are refused" {
  echo '[{"number":1,"role":"backend","objective":"duplicate number one"},{"number":1,"role":"qa","objective":"duplicate number two"}]' > "$TEST_TMPDIR/steps.json"
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_json_build --steps-json "$TEST_TMPDIR/steps.json" --out "$TEST_TMPDIR/plan.json" --epic-id E-900-1_1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate step number"* ]]
  echo '[]' > "$TEST_TMPDIR/steps.json"
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_json_build --steps-json "$TEST_TMPDIR/steps.json" --out "$TEST_TMPDIR/plan.json" --epic-id E-900-1_1'
  [ "$status" -eq 2 ]
}

@test "json: a direct step without AID Role is refused naming the step" {
  _write_plan
  sed -i '0,/^\*\*AID Role:\*\* backend$/{/^\*\*AID Role:\*\* backend$/d}' "$PLAN"
  run bash -c 'set -e; source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_json_steps_from_plan "$PLAN" > "$TEST_TMPDIR/steps.json"; aid_plan_json_build --steps-json "$TEST_TMPDIR/steps.json" --out "$TEST_TMPDIR/plan.json" --epic-id E-900-1_1 --direct --execution "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Step 1 names no **AID Role:**"* ]]
}

@test "json: the lint refuses a repo_roots path that is not a git repository (repo_root_invalid)" {
  mkdir -p "$TEST_TMPDIR/not-a-repo"
  _write_plan "repo_roots:
  - name: docs
    path: $TEST_TMPDIR/not-a-repo"
  run bash "$LINT" "$PLAN"
  [[ "$output" == *"ERROR repo_root_invalid: repo_roots 'docs' path"*"is not a git repository"* ]]
  [ "$status" -eq 1 ]
}

@test "json: the lint and the builder refuse a repo_roots path inside the project (repo_root_invalid)" {
  mkdir -p "$TEST_PROJECT_ROOT/sub"
  _write_plan "repo_roots:
  - name: self
    path: $TEST_PROJECT_ROOT/sub"
  run bash "$LINT" "$PLAN"
  [[ "$output" == *"ERROR repo_root_invalid: repo_roots 'self'"*"inside it"* ]]
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_repo_roots_json "$PLAN" P900 project'
  [ "$status" -eq 1 ]
  [[ "$output" == *"repo_root_invalid"* ]]
}

@test "json: the lint accepts a valid repo_roots entry and refuses an unknown base_branch" {
  _write_plan "repo_roots:
  - name: docs
    path: ${FOREIGN}
    base_branch: nope"
  run bash "$LINT" "$PLAN"
  [[ "$output" == *"repo_root_invalid: repo_roots 'docs' base_branch 'nope' does not resolve"* ]]
  _write_plan "repo_roots:
  - name: docs
    path: ${FOREIGN}"
  run bash "$LINT" "$PLAN"
  [[ "$output" != *"repo_root_invalid"* ]]
}

@test "json: --direct derives repo_roots from the plan frontmatter itself (no prepared mapping)" {
  _write_plan "repo_roots:
  - name: docs
    path: ${FOREIGN}"
  run bash -c 'set -e; source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_json_steps_from_plan "$PLAN" > "$TEST_TMPDIR/steps.json"; aid_plan_json_build --steps-json "$TEST_TMPDIR/steps.json" --out "$TEST_TMPDIR/plan.json" --epic-id E-900-1_1 --plan "$PLAN" --direct --execution "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.repo_roots[0].name + " " + .repo_roots[0].branch' "$TEST_TMPDIR/plan.json")" = "docs plan/P900-project" ]
}

@test "json: a step list without prepared Files/criteria fields gets them from the plan's step section" {
  _write_plan
  echo '[{"number":2,"role":"docs","objective":"Document the parser reference","depends_on":"","parallel_group":"---"}]' > "$TEST_TMPDIR/steps.json"
  run bash -c 'source "$AID_PLUGIN_PATH/scripts/lib/common.sh"; source "$LIB"; aid_plan_json_build --steps-json "$TEST_TMPDIR/steps.json" --out "$TEST_TMPDIR/plan.json" --epic-id E-900-1_1 --plan "$PLAN"'
  [ "$status" -eq 0 ]
  [ "$(jq -c '.steps[0].allowed_paths' "$TEST_TMPDIR/plan.json")" = '["docs/parser.md"]' ]
  [ "$(jq -r '.steps[0].acceptance_criteria[0]' "$TEST_TMPDIR/plan.json")" = '`grep -q parser docs/parser.md` exits 0.' ]
}
