#!/usr/bin/env bats
# aid-tier: t2
# test-dep-grammar.bats — P073 Step 5: one dependency grammar across both
# source-plan parsers.
#
# Before this step three parsers had three grammars: the canonical
# lib/aid-source-plan-graph.sh accepted only `---` (undocumented), while
# aid-plan-to-epic.sh silently DROPPED any token it did not recognise and
# rendered `none` as no-dependency — the exact interpretation plan-writing.md
# forbids. A typo therefore became "no dependency" and generation continued
# against a graph the author never wrote.
#
# The grammar is now: `Depends on: <refs> [— annotation]`, where <refs> is a
# comma-separated list of Step/Steps/Task/Tasks references OR one of the two
# no-dependency markers `none` and `---`. Everything after the first em dash
# is ignored; every token to its left must be recognised.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  GRAPH_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-source-plan-graph.sh"
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  export GRAPH_LIB PLAN_TO_EPIC
  PLAN="$TEST_PROJECT_ROOT/plan.md"
  export PLAN
}

teardown() {
  teardown_test_evidence_dir
}

# _write_plan <deps-line-for-step-2> [extra-lines-for-step-2-deps-block]
#   A minimal two-step, one-EPIC source plan. Step 1 never depends on
#   anything; Step 2 carries the declaration under test.
_write_plan() {
  local dep_line="$1" extra="${2:-}"
  cat > "$PLAN" <<EOF
---
id: P900
type: plan
status: ready
risk: low
---

# Plan: Dependency grammar fixture

## Goal

Exercise the dependency grammar.

## Implementation Steps

**EPIC 1: Steps 1-2 — Fixture**

### Step 1: First

**Objective:** Do the first thing.

**Files:**
- Modify: \`a.txt\`

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] It happened.

**Effort:** S
**AID Role:** backend

### Step 2: Second

**Objective:** Do the second thing.

**Files:**
- Modify: \`b.txt\`

**Dependencies:**
- Depends on: ${dep_line}
${extra}

**Acceptance Criteria:**
- [ ] It happened too.

**Effort:** S
**AID Role:** backend
EOF
}

# _graph — runs the canonical parser over $PLAN, printing its JSON or error.
# Sources the same three libs aid-generation-readiness.sh does (the graph lib
# calls build_plan_graph from lib/aid-plan-graph.sh).
_graph() {
  bash -c '
    set -euo pipefail
    d="$1"
    . "$d/common.sh"
    . "$d/aid-plan-graph.sh"
    . "$d/aid-source-plan-graph.sh"
    if aid_source_plan_graph "$2" 1; then :; else
      printf "%s\n" "${_aid_spg_error:-unset error}" >&2
      exit 1
    fi
  ' _ "$AID_PLUGIN_PATH/scripts/lib" "$PLAN"
}

# _to_epic — runs aid-plan-to-epic.sh over $PLAN with its real CLI.
_to_epic() {
  local out="$TEST_PROJECT_ROOT/epics"
  mkdir -p "$out"
  bash "$PLAN_TO_EPIC" \
    --plan "$PLAN" --phase 1 --total 1 \
    --epic-template "$AID_PLUGIN_PATH/defaults/templates/epic.md" \
    --output-dir "$out" \
    --counter-yaml "$TEST_PROJECT_ROOT/counter.yaml" \
    --project-root "$TEST_PROJECT_ROOT"
}

# ─── both no-dependency markers, in both parsers ──────────────────────────

@test "P073 Step 5: 'none' parses as no-dependency in the canonical parser" {
  _write_plan "none"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2")] | length')" = "0" ]
}

@test "P073 Step 5: 'NONE' (case-insensitive) parses as no-dependency" {
  _write_plan "NONE"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2")] | length')" = "0" ]
}

@test "P073 Step 5: '---' still parses as no-dependency (generated-canonical form)" {
  _write_plan "---"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2")] | length')" = "0" ]
}

@test "P073 Step 5: a real reference still produces its edge" {
  _write_plan "Step 1"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2" and .before == "step-1")] | length')" = "1" ]
}

# ─── loud failure on an unrecognised token ────────────────────────────────

@test "P073 Step 5: 'nothing' is rejected by the canonical parser, naming the token" {
  _write_plan "nothing"
  run _graph
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognised dependency token 'nothing'"* ]]
}

@test "P073 Step 5: a valid reference MIXED with an invalid token fails loudly (never a partial graph)" {
  _write_plan "Step 1, banana"
  run _graph
  [ "$status" -ne 0 ]
  [[ "$output" == *"banana"* ]]
}

@test "P073 Step 5: a no-dependency marker mixed with a real reference is contradictory and fails" {
  _write_plan "none, Step 1"
  run _graph
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognised dependency token"* ]]
}

# ─── em-dash annotation is supported syntax ───────────────────────────────

@test "P073 Step 5: an em-dash annotation after the references is ignored, not parsed" {
  _write_plan "Step 1 — needs the fixture file it creates"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2" and .before == "step-1")] | length')" = "1" ]
}

@test "P073 Step 5: an invalid token BEFORE the em dash still fails, annotation notwithstanding" {
  _write_plan "Step 1, banana — this annotation must not rescue it"
  run _graph
  [ "$status" -ne 0 ]
  [[ "$output" == *"banana"* ]]
}

@test "P073 Step 5: 'none — reason' is still a valid no-dependency declaration" {
  _write_plan "none — this step is independent of every other one"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2")] | length')" = "0" ]
}

# ─── the indented `Blocks:` continuation trap ─────────────────────────────

@test "P073 Step 5: an indented '- Blocks: Step N' is never folded into the depends set" {
  # Step 2 depends on Step 1 and BLOCKS nothing real — but the old continuation
  # fold absorbed the indented Blocks line, inventing a forward dependency on
  # a step that does not exist, which then failed the graph for the wrong
  # reason (or, with a valid number, silently added a wrong edge).
  _write_plan "Step 1" "- Blocks: Step 5"
  run _graph
  [ "$status" -eq 0 ]
  local deps
  deps="$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2") | .before] | sort | join(",")')"
  [ "$deps" = "step-1" ]
}

# ─── the second parser: aid-plan-to-epic.sh ───────────────────────────────

@test "P073 Step 5: aid-plan-to-epic.sh ABORTS on an unrecognised token with a non-zero exit and writes no EPIC" {
  _write_plan "nothing"
  run _to_epic
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognised dependency token 'nothing'"* ]]
  # No EPIC file was written for this plan (no partial output).
  run bash -c "ls '$TEST_PROJECT_ROOT/epics' 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "P073 Step 5: parse_step_deps itself returns non-zero on an unrecognised token (defence in depth behind the readiness precheck)" {
  # aid-plan-to-epic.sh runs aid-generation-readiness.sh first, so in practice
  # the canonical parser catches a bad token before parse_step_deps ever sees
  # it. This asserts the SECOND parser is loud on its own — the readiness
  # precheck must not be the only thing standing between a typo and a silently
  # emptied dependency.
  run bash -c '
    set -uo pipefail
    step_counter=2
    # Load only the function under test (its enclosing script runs work at
    # source time), bounded by the next function definition.
    eval "$(sed -n "/^parse_step_deps() {/,/^}/p" "$1")"
    parse_step_deps "Step 1, banana"
  ' _ "$PLAN_TO_EPIC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"step 2: unrecognised dependency token 'banana'"* ]]
}

@test "P073 Step 5: parse_step_deps accepts both no-dependency markers and a real reference" {
  run bash -c '
    set -uo pipefail
    step_counter=2
    eval "$(sed -n "/^parse_step_deps() {/,/^}/p" "$1")"
    parse_step_deps "none" && echo "none-ok"
    parse_step_deps "---" && echo "dashes-ok"
    printf "refs=%s\n" "$(parse_step_deps "Step 1, Steps 3-4")"
  ' _ "$PLAN_TO_EPIC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"none-ok"* ]]
  [[ "$output" == *"dashes-ok"* ]]
  [[ "$output" == *"refs=1, 3, 4"* ]]
}

@test "P073 Step 5: aid-plan-to-epic.sh accepts 'none' as no-dependency" {
  _write_plan "none"
  run _to_epic
  [ "$status" -eq 0 ]
}

@test "P073 Step 5: aid-plan-to-epic.sh accepts a real reference with an em-dash annotation" {
  _write_plan "Step 1 — needs the fixture file it creates"
  run _to_epic
  [ "$status" -eq 0 ]
}

@test "P073 Step 5: aid-plan-to-epic.sh rejects a valid reference mixed with an invalid token" {
  _write_plan "Step 1, banana"
  run _to_epic
  [ "$status" -ne 0 ]
  [[ "$output" == *"banana"* ]]
}

# ─── the readiness message names both markers ─────────────────────────────

@test "P073 Step 5: aid-generation-readiness.sh FAIL output names 'none' and '---'" {
  _write_plan "nothing"
  cd "$TEST_PROJECT_ROOT"
  run bash "$AID_PLUGIN_PATH/scripts/aid-generation-readiness.sh" "$PLAN" --total 2
  [ "$status" -ne 0 ]
  [[ "$output" == *"'none'"* ]]
  [[ "$output" == *"'---'"* ]]
}

@test "P073 Step 5: plan-writing.md documents both no-dependency forms" {
  run grep -c 'Depends on: none' "$AID_PLUGIN_PATH/skills/plan-writing.md"
  [ "$output" -ge 1 ]
}

# ─── Codex-review findings on the first cut of this step ───────────────────
# The adversarial review found two real defects:
#   1. The `Blocks:` guard matched the WORD anywhere on the line, so a normal
#      `- Depends on: Step 2 — Blocks: API work` was skipped entirely and its
#      dependency silently vanished. It now matches the FIELD prefix only.
#   2. The reference patterns were not end-anchored, so `Steps 1-3 and 5`
#      matched the valid prefix and silently discarded the 5.
# Anchoring alone rejected 5 plans in this repo's own corpus that previously
# generated, because the dominant real annotation form is a PARENTHETICAL
# ("Step 1 (visual_refs field in schema)"), so the annotation separator set
# was widened to em dash, en dash, ' - ' and ' ('. Measured over every plan in
# .aid-o/plans: pre-P073 accepted 25, this step now accepts 29, with ZERO
# newly rejected.

@test "P073 Step 5 (review finding 1): a Depends line whose ANNOTATION mentions 'Blocks:' keeps its dependency" {
  _write_plan "Step 1 — Blocks: API work downstream"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2" and .before == "step-1")] | length')" = "1" ]
}

@test "P073 Step 5 (review finding 2): 'Steps 1-3 and 5' fails loudly instead of silently dropping the 5" {
  _write_plan "Steps 1-1 and 5"
  run _graph
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognised dependency token"* ]]
  [[ "$output" == *"and 5"* ]]
}

@test "P073 Step 5 (review finding 2): a bare trailing note after a valid reference no longer passes unnoticed" {
  _write_plan "Step 1 plus whatever else"
  run _graph
  [ "$status" -ne 0 ]
  [[ "$output" == *"unrecognised dependency token"* ]]
}

@test "P073 Step 5: a PARENTHETICAL annotation is supported (the form this repo's plan corpus actually uses)" {
  _write_plan "Step 1 (creates the fixture file this step reads)"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2" and .before == "step-1")] | length')" = "1" ]
}

@test "P073 Step 5: an EN-DASH annotation is supported" {
  _write_plan "Step 1 – creates the fixture file this step reads"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2" and .before == "step-1")] | length')" = "1" ]
}

@test "P073 Step 5: a SPACED ASCII-hyphen annotation is supported, while an UNSPACED hyphen stays part of a range" {
  _write_plan "Step 1 - creates the fixture file this step reads"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2" and .before == "step-1")] | length')" = "1" ]

  # The unspaced form must still parse as a RANGE, not as an annotation.
  _write_plan "Steps 1-1"
  run _graph
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.edges[]? | select(.after == "step-2" and .before == "step-1")] | length')" = "1" ]
}

@test "P073 Step 5: parse_step_deps honours the same four annotation separators and anchoring" {
  run bash -c '
    set -uo pipefail
    step_counter=2
    eval "$(sed -n "/^parse_step_deps() {/,/^}/p" "$1")"
    printf "em=%s\n"    "$(parse_step_deps "Step 1 — note")"
    printf "en=%s\n"    "$(parse_step_deps "Step 1 – note")"
    printf "hyph=%s\n"  "$(parse_step_deps "Step 1 - note")"
    printf "paren=%s\n" "$(parse_step_deps "Step 1 (note)")"
    printf "range=%s\n" "$(parse_step_deps "Steps 1-3")"
    parse_step_deps "Steps 1-3 and 5" && echo "UNANCHORED-LEAK" || echo "anchored-ok"
  ' _ "$PLAN_TO_EPIC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"em=1"* ]]
  [[ "$output" == *"en=1"* ]]
  [[ "$output" == *"hyph=1"* ]]
  [[ "$output" == *"paren=1"* ]]
  [[ "$output" == *"range=1, 2, 3"* ]]
  [[ "$output" == *"anchored-ok"* ]]
  [[ "$output" != *"UNANCHORED-LEAK"* ]]
}
