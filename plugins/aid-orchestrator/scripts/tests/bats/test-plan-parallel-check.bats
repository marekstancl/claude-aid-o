#!/usr/bin/env bats
# aid-tier: t0
# test-plan-parallel-check.bats — are the steps a plan declares as concurrent
# actually disjoint? (P085 Step 7)
#
# Pure text over temp files: the check reads a plan and compares declared paths,
# it runs nothing and writes nothing. The one thing worth stating up front is
# what a collision IS here — the same path in two steps of the SAME wave. The
# same path in two different waves is not a collision, and a suite that got that
# backwards would push every plan into one step per wave.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  CHECK="$AID_PLUGIN_PATH/scripts/aid-plan-parallel-check.sh"
  TEST_DIR="$(mktemp -d)"; cd "$TEST_DIR"
  mkdir -p .aid-o/plans
  PLAN=".aid-o/plans/P904-fixture.md"
}
teardown() { cd /; rm -rf "$TEST_DIR"; }

# _plan <risk> <step-spec>...   step-spec = "<group>[@<iface>[,<iface>]]|<bullet>[;<bullet>]"
_plan() {
  local risk="$1"; shift
  local n=0 spec group ifaces bullets b
  { printf -- '---\nid: P904\ntype: regular\nrisk: %s\nlifecycle_strict: true\n---\n' "$risk"
    printf '# Plan: P904\n\n## Implementation Steps\n\n'
    for spec in "$@"; do
      n=$((n+1))
      group="${spec%%|*}"; bullets="${spec#*|}"
      ifaces=""; [[ "$group" == *@* ]] && { ifaces="${group#*@}"; group="${group%%@*}"; }
      printf '### Step %d: work %d\n\n**Objective:** do the thing.\n\n**Files:**\n' "$n" "$n"
      while IFS= read -r b; do [[ -n "$b" ]] && printf -- '- %s\n' "$b"; done < <(printf '%s\n' "${bullets//;/$'\n'}")
      [[ "$group" != "NONE" ]] && printf '\n**Parallel group:** %s\n' "$group"
      [[ -n "$ifaces" ]] && printf '\n**Shared interfaces:** %s\n' "$ifaces"
      printf '\n'
    done
  } > "$PLAN"
}

# ── the collision this exists to find ───────────────────────────────────────
@test "parallel: two steps in one wave sharing a path are reported, with both steps named" {
  _plan low 'wave-1|Modify: `src/a.ts` — edit' 'wave-1|Modify: `src/a.ts` — also edit'
  run "$CHECK" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not disjoint"* ]]
  [[ "$output" == *"src/a.ts"* ]]
  [[ "$output" == *"Step 1"* ]]
  [[ "$output" == *"Step 2"* ]]
}

@test "parallel: the same pair in DIFFERENT waves passes" {
  _plan low 'wave-1|Modify: `src/a.ts` — edit' 'wave-2|Modify: `src/a.ts` — also edit'
  run "$CHECK" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"not disjoint"* ]]
}

@test "parallel: a wave whose steps touch different files passes" {
  _plan low 'wave-1|Modify: `src/a.ts` — edit' 'wave-1|Modify: `src/b.ts` — edit'
  run "$CHECK" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "parallel: every shared path is named, not just the first" {
  _plan low 'wave-1|Modify: `src/a.ts` — edit;Modify: `src/b.ts` — edit' \
            'wave-1|Modify: `src/a.ts` — edit;Modify: `src/b.ts` — edit'
  run "$CHECK" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"src/a.ts"* ]]
  [[ "$output" == *"src/b.ts"* ]]
}

# ── the standalone marker ───────────────────────────────────────────────────
@test "parallel: steps marked --- never collide, however much they overlap" {
  _plan low '---|Modify: `src/a.ts` — edit' '---|Modify: `src/a.ts` — edit'
  run "$CHECK" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "parallel: a missing field defaults to --- in a light plan and blocks nothing" {
  _plan low 'NONE|Modify: `src/a.ts` — edit' 'NONE|Modify: `src/a.ts` — edit'
  band="$(bash "$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh" --plan "$PLAN" --project-root "$TEST_DIR" --classify-only 2>/dev/null)"
  [ "$band" = "light" ]
  run "$CHECK" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "parallel: a missing field IS a finding in full/medium, where concurrency is declared deliberately" {
  _plan high 'NONE|Modify: `src/a.ts` — edit'
  run "$CHECK" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no **Parallel group:** field"* ]]
}

# ── shape ───────────────────────────────────────────────────────────────────
@test "parallel: a group name that is not a name is refused with the expected shape" {
  _plan high 'wave/1|Modify: `src/a.ts` — edit' 'wave/1|Modify: `src/b.ts` — edit'
  run "$CHECK" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a group name"* ]]
}

@test "parallel: an annotation after the wave name is ignored, not graded" {
  _plan low 'wave-1|Modify: `src/a.ts` — edit' 'wave-1|Modify: `src/b.ts` — edit'
  sed -i 's/^\*\*Parallel group:\*\* wave-1$/**Parallel group:** wave-1 — nothing in common with step 2/' "$PLAN"
  run "$CHECK" "$PLAN"
  [ "$status" -eq 0 ]
}

# ── the two severities ──────────────────────────────────────────────────────
@test "parallel: --advisory reports the same finding without failing" {
  _plan low 'wave-1|Modify: `src/a.ts` — edit' 'wave-1|Modify: `src/a.ts` — edit'
  run "$CHECK" "$PLAN" --advisory
  [ "$status" -eq 0 ]
  [[ "$output" == *"not disjoint"* ]]
  [[ "$output" == *"BLOCK before EPIC generation"* ]]
}

# ── the notes ───────────────────────────────────────────────────────────────
@test "parallel: a wave of one is valid, reported, and not a failure" {
  _plan low 'wave-1|Modify: `src/a.ts` — edit' '---|Modify: `src/b.ts` — edit'
  run "$CHECK" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has one step"* ]]
}

@test "parallel: a step declaring no file cannot collide" {
  _plan low 'wave-1|Modify: `src/a.ts` — edit' 'wave-1|'
  run "$CHECK" "$PLAN"
  [ "$status" -eq 0 ]
}

# ── usage ───────────────────────────────────────────────────────────────────
@test "parallel: a missing plan file is a usage error, not a pass" {
  run "$CHECK" /nonexistent/plan.md
  [ "$status" -eq 2 ]
}

# ── the second dimension: interfaces (P087 Step 3) ──────────────────────────
@test "parallel: AC7 — two steps in one wave naming the same interface collide, however different their files" {
  _plan low 'wave-1@/api/orders|Modify: `src/a.ts` — a' 'wave-1@api/orders/|Modify: `src/b.ts` — b'
  run "$CHECK" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"shares an interface"* ]]
  [[ "$output" == *"api/orders"* ]]
  [[ "$output" == *"Step 1"* && "$output" == *"Step 2"* ]]
}

@test "parallel: different interfaces in one wave pass, and the field is optional (AC9)" {
  _plan low 'wave-1@/api/orders, orders.schema|Modify: `src/a.ts` — a' 'wave-1@/api/users|Modify: `src/b.ts` — b' 'wave-1|Modify: `src/c.ts` — c'
  run "$CHECK" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}
