#!/usr/bin/env bats
# aid-tier: t0
# test-standards-map.bats — deriving ecosystem standards from a plan's paths
# (P085 Step 4).
#
# The map under test is a FIXTURE, not the live ecosystem page: this suite must
# assert the derivation, and a suite whose expectations move when someone edits
# a Docusaurus page is a suite that fails for reasons unrelated to AID. That the
# derivation still agrees with the LIVE map is a separate, deliberately
# invocation-time claim — `aid-standards-map.sh --self-test`.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  LINT="$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh"
  TEST_DIR="$(mktemp -d)"; cd "$TEST_DIR"
  mkdir -p .aid-o/plans .aid-o/config scripts/tests
  PLAN=".aid-o/plans/P902-fixture.md"
  MAP="$TEST_DIR/standards-map.md"
  _write_map
  _write_config "$MAP"
}
teardown() { cd /; rm -rf "$TEST_DIR"; }

_write_map() {   # a map in the real shape: prose, then the machine block last
  cat > "$MAP" <<'EOF'
# Standards map

Prose a human reads. The block below is what the tool reads.

```yaml
schema_version: 1
tags:
  testy: "founding, changing and retiring tests"
  dokumentace: "where documentation lives"
standards:
  - id: test-standard
    path: /ecosystem/specs/test-standard
    tags: [testy]
    status: active
  - id: llm-test-cost-control
    path: /ecosystem/specs/llm-test-cost-control
    tags: [testy]
    status: active
  - id: documentation-placement
    path: /ecosystem/specs/documentation-placement
    tags: [dokumentace]
    status: active
  - id: retired-standard
    path: /ecosystem/specs/retired-standard
    tags: [dokumentace]
    status: deprecated
  - id: hook-standard
    path: /ecosystem/specs/hook-standard
    tags: [agent-hooks-tag-not-in-vocabulary]
    status: active
```
EOF
}

_write_config() { printf 'standards:\n  active: vulcan\n  map_path: %s\n' "$1" > .aid-o/config/project.yaml; }

# _plan <bullet> [standards-section-lines…]
_plan() {
  local bullet="$1"; shift
  { printf -- '---\nid: P902\ntype: regular\nrisk: high\nlifecycle_strict: true\n---\n'
    printf '# Plan: P902\n\n## Testing Strategy\n\nNo new verification — this fixture exercises the standards derivation only.\n\n'
    if [[ $# -gt 0 ]]; then printf '## Standards\n\n'; printf '%s\n' "$@"; printf '\n'; fi
    printf '**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n'
    printf -- '- %s\n' "$bullet"
    printf '\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nn/a\n\n**Edge Cases:**\n- none\n'
  } > "$PLAN"
  # `risk: high` puts the fixture in `full`, where the obligation lives.
}

# ── AC11: the derived standard must be named ────────────────────────────────
@test "standards: a plan changing tests without naming a testy standard is refused" {
  _plan 'Modify: `scripts/tests/x.bats` — edit'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"touches the 'testy' area"* ]]
  [[ "$output" == *"test-standard"* ]]
}

@test "standards: naming one standard from the area satisfies it" {
  _plan 'Modify: `scripts/tests/x.bats` — edit' \
    '| Standard | Why it binds | Deviation |' '|---|---|---|' \
    '| `/ecosystem/specs/test-standard` | the plan changes a suite | none |'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

# ── AC12: a deviation passes when it says why ───────────────────────────────
@test "standards: a deviation with a written reason passes" {
  _plan 'Modify: `scripts/tests/x.bats` — edit' \
    '| Standard | Why it binds | Deviation |' '|---|---|---|' \
    '| `/ecosystem/specs/test-standard` | the plan changes a suite | the suite stays t2 because it drives docker, and the standard assumes a pure unit |'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "standards: a deviation marked but not explained is refused" {
  _plan 'Modify: `scripts/tests/x.bats` — edit' \
    '| Standard | Why it binds | Deviation |' '|---|---|---|' \
    '| `/ecosystem/specs/test-standard` | the plan changes a suite | yes |'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"with no reason"* ]]
}

# ── AC13: no map, no obligation — and it is recorded ────────────────────────
@test "standards: a project with no map owes no section, and the lint records it" {
  printf 'standards:\n  active: general\n' > .aid-o/config/project.yaml
  _plan 'Modify: `scripts/tests/x.bats` — edit'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no standards map configured"* ]]
}

@test "standards: a configured but unreadable map is a broken environment, not an absent one" {
  _write_config "$TEST_DIR/no-such-map.md"
  _plan 'Modify: `scripts/tests/x.bats` — edit'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be read"* ]]
}

@test "standards: a map whose machine block does not parse is the broken case, not the absent one" {
  printf '# Map\n\n```yaml\nstandards: [ this is not: valid yaml\n```\n' > "$MAP"
  _plan 'Modify: `scripts/tests/x.bats` — edit'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be read"* ]]
}

# ── AC14: a defect of the map is reported, and stops nothing ────────────────
@test "standards: a tag missing from the map's own vocabulary is reported, not blocking" {
  _plan 'Modify: `scripts/tests/x.bats` — edit' \
    '| Standard | Why it binds | Deviation |' '|---|---|---|' \
    '| `/ecosystem/specs/test-standard` | the plan changes a suite | none |'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-hooks-tag-not-in-vocabulary"* ]]
  [[ "$output" == *"defect of the map"* ]]
}

# ── the shape of the derivation itself ──────────────────────────────────────
@test "standards: a deprecated standard is never required" {
  # `dokumentace` carries one active standard and one deprecated one; naming
  # the active one is enough, and the deprecated one is never demanded.
  _plan 'Modify: `docs/plans/x.md` — edit' \
    '| Standard | Why it binds | Deviation |' '|---|---|---|' \
    '| `/ecosystem/specs/documentation-placement` | a new document | none |'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"retired-standard"* ]]
}

@test "standards: a path bound to nothing in the map owes no section" {
  _plan 'Modify: `src/unmapped-area.ts` — edit'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"'## Standards' section names none"* ]]
}

@test "standards: a light-band plan is not asked" {
  # Same untagged-by-band situation, but classified `light`: no risk: high, and
  # only ordinary source code declared.
  { printf -- '---\nid: P902\ntype: regular\nrisk: low\nlifecycle_strict: true\n---\n'
    printf '# Plan: P902\n\n## Testing Strategy\n\nnone\n\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly.\n\n**Files:**\n- Modify: `scripts/tests/x.bats` — edit\n'
  } > "$PLAN"
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"touches the 'testy' area"* ]]
}

# ── the drift check gets a caller ───────────────────────────────────────────
# `--self-test` asks whether the derivation still agrees with the LIVE map —
# a document edited by people who never run AID. Without a caller it could only
# fire when someone remembered it, which is what an unenforced check is worth.
# It SKIPS rather than fails when the map is unreachable: a foreign live
# document must never fail a contributor's suite for being offline, while a
# real derivation drift must.
@test "standards: the live-map drift check runs, and skips cleanly when there is no map" {
  run bash "$AID_PLUGIN_PATH/scripts/lib/aid-standards-map.sh" --self-test
  if [[ "$output" == *"self-test SKIP"* || "$output" == *"unreachable"* ]]; then
    skip "no standards map reachable from this checkout"
  fi
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-test PASS"* ]]
}
