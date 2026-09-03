#!/usr/bin/env bats
# aid-tier: t0
#
# A step may declare its dependencies on more than one line. Until 2026-09-02
# every declaration after the first was silently discarded: the collector
# joined them into one string and the annotation strip ran from the FIRST
# separator to end of string. Five of eleven steps in a real plan (ACTA P021)
# lost dependencies that way, and the loss surfaced only much later as an
# unexplained disagreement with plan.json.

setup() {
  PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  source "${PLUGIN_ROOT}/scripts/lib/aid-plan-graph.sh"
  source "${PLUGIN_ROOT}/scripts/lib/aid-source-plan-graph.sh"
  PLAN="${BATS_TEST_TMPDIR}/plan.md"
}

# Steps 1 and 2 exist so a dependency on them is not a forward reference.
preamble() {
  cat > "$PLAN" <<'EOF'
### Step 1 — first
**Dependencies:**
- Depends on: none

### Step 2 — second
**Dependencies:**
- Depends on: none

EOF
}

edges() { aid_source_plan_graph "$PLAN" | jq -c '[.edges[] | "\(.before)->\(.after)"] | sort'; }

@test "every Depends on: line is honoured, not just the first" {
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: Step 1 — the first reason
- Depends on: Step 2 — the second reason
EOF
  run edges
  [ "$status" -eq 0 ]
  [ "$output" = '["step-1->step-3","step-2->step-3"]' ]
}

@test "each declaration may use a different annotation separator" {
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: Step 1 — em dash
- Depends on: Step 2 – en dash
EOF
  run edges
  [ "$status" -eq 0 ]
  [ "$output" = '["step-1->step-3","step-2->step-3"]' ]

  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: Step 1 - spaced hyphen
- Depends on: Step 2 (parenthetical)
EOF
  run edges
  [ "$status" -eq 0 ]
  [ "$output" = '["step-1->step-3","step-2->step-3"]' ]
}

@test "a wrapped annotation that begins 'Depends on:' is prose, not a declaration" {
  # The boundary is structural — a list item, or an unindented field. Anything
  # else indented continues the declaration above it. Without this rule the
  # continuation below would open a second declaration and then fail on
  # 'the schema staying stable' as an unrecognised token.
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: Step 1 — rationale:
  Depends on: the schema staying stable before work starts
EOF
  run edges
  [ "$status" -eq 0 ]
  [ "$output" = '["step-1->step-3"]' ]
}

@test "a range on one line and a further reference on the next both survive" {
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: Steps 1-2 — the range form

### Step 4 — fourth
**Dependencies:**
- Depends on: Steps 1-2 — the range form
- Depends on: Step 3 — and this one
EOF
  run edges
  [ "$status" -eq 0 ]
  [ "$output" = '["step-1->step-3","step-1->step-4","step-2->step-3","step-2->step-4","step-3->step-4"]' ]
}

@test "naming the same step on two lines is caught as the duplicate it is" {
  # Proves the SECOND line is really parsed: if it were still being discarded
  # the duplicate could not be seen at all and this would pass silently.
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: Step 1 — once
- Depends on: Step 1 — and again
EOF
  run aid_source_plan_graph "$PLAN"
  [ "$status" -ne 0 ]
}

@test "a no-dependency marker mixed with a real reference is a loud failure" {
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: none
- Depends on: Step 1 — but also this
EOF
  run aid_source_plan_graph "$PLAN"
  [ "$status" -ne 0 ]
}

@test "the same marker declared twice is the same statement made twice" {
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: none
- Depends on: none
EOF
  run edges
  [ "$status" -eq 0 ]
  [ "$output" = '[]' ]
}

@test "a single unterminated marker is still recognised" {
  # The marker scan reads a comma-separated list whose last field has no
  # trailing newline; without the `|| [[ -n ]]` guard the loop body never ran
  # and a plain `none` fell through to the unrecognised-token error.
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: none
EOF
  run edges
  [ "$status" -eq 0 ]
  [ "$output" = '[]' ]
}

@test "a reserved control byte in the plan is refused, not parsed" {
  preamble
  printf '### Step 3 — third\n**Dependencies:**\n- Depends on: Step 1\035 Step 2\n' >> "$PLAN"
  run aid_source_plan_graph "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$_aid_spg_error" == *"reserved control byte"* ]] || true
}

@test "single-line declarations are unchanged" {
  preamble
  cat >> "$PLAN" <<'EOF'
### Step 3 — third
**Dependencies:**
- Depends on: Step 1, Step 2 — one line, two references
EOF
  run edges
  [ "$status" -eq 0 ]
  [ "$output" = '["step-1->step-3","step-2->step-3"]' ]
}
