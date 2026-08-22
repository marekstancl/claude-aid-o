#!/usr/bin/env bats
# aid-tier: t0
# test-aid-plan-summary.bats — the PM's page about a new plan (P084 Step 5).
#
# TESTABILITY BOUNDARY, STATED EXPLICITLY
#   aid_plan_summary_render writes an artifact BODY and nothing else. It never
#   publishes: the Artifact tool is a session-level act owned by the controller
#   instruction in commands/aid-plan.md, and nothing here claims to cover it —
#   the same boundary test-aid-plan-close-summary.bats and
#   test-aid-artifact-render.bats both draw.
#
#   The renderer underneath (lib/aid-artifact-render.sh) has its own suite; what
#   is proved HERE is this caller: that every number on the page is counted from
#   the plan, that a plan with nothing to say is refused rather than rendered
#   half-empty, and that the page states the ceremony band.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  AID_PLUGIN_PATH="$PLUGIN_ROOT"
  export AID_PLUGIN_PATH
  TMP="$(mktemp -d)"
  OUT="$TMP/plan-summary-artifact.html"
  # shellcheck disable=SC1090
  source "$PLUGIN_ROOT/scripts/lib/aid-plan-summary.sh"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

# write_plan <name> <first Files path> [extra step]
#   A plan with the sections the renderer reads: frontmatter, Goal, Context,
#   one step with a declared file, and a two-row Risks table.
write_plan() {
  local f="$TMP/$1.md" path="$2"
  cat > "$f" <<EOF
---
id: $1
type: plan
status: draft
---

# Plan: fixture

## Context

The classifier scanned prose and called every plan high-risk.

## Goal

Ceremony is proportional to what a plan actually touches.

## Implementation Steps

### Step 1: classify from paths

**Objective:** read the declared paths.

**Files:**
- Modify: \`$path\` — the subject
- Modify: \`CHANGELOG.md\` — entry

**Effort:** M
**AID Role:** backend

### Step 2: write it down

**Objective:** document it.

**Files:**
- Modify: \`docs/extending-aid.md\` — the contributor page

**Effort:** S
**AID Role:** docs

## Risks

| Riziko | P | Dopad | Zmírnění |
|---|---|---|---|
| Mapa podcení plán | M | vysoký | fail-closed na full |
| Zrušená kontrola chybí | S | střední | rozhoduje PM |

## Next Steps

- nothing
EOF
  printf '%s' "$f"
}

@test "AC15: the page is built from a plan fixture and lands on disk" {
  run aid_plan_summary_render "$(write_plan P950 'plugins/aid-orchestrator/scripts/aid-fsm.sh')" "$OUT"
  [ "$status" -eq 0 ]
  [ -s "$OUT" ]
  # A BODY, not a document: the Artifact tool supplies the skeleton.
  ! grep -qi '<!doctype\|<html' "$OUT"
}

@test "every number on the page is counted from the plan, not asserted" {
  aid_plan_summary_render "$(write_plan P951 'plugins/aid-orchestrator/scripts/aid-fsm.sh')" "$OUT"
  grep -q '2 kroků, 3 deklarovaných souborů' "$OUT"
  grep -q 'Rizika pojmenovaná v plánu: 2' "$OUT"
  grep -q 'backend, docs' "$OUT"
}

@test "the page states the ceremony band and why" {
  aid_plan_summary_render "$(write_plan P952 'plugins/aid-orchestrator/scripts/aid-fsm.sh')" "$OUT"
  grep -q 'Pásmo ceremonie: full' "$OUT"
  grep -q 'full_path:plugins/aid-orchestrator/scripts/aid-fsm.sh' "$OUT"
}

@test "a light plan says so on the same page" {
  aid_plan_summary_render "$(write_plan P953 'plugins/aid-orchestrator/commands/aid-help.md')" "$OUT"
  grep -q 'Pásmo ceremonie: light' "$OUT"
}

@test "a plan with no Goal is refused, naming the section — no half-empty page" {
  plan="$(write_plan P954 'plugins/aid-orchestrator/commands/aid-help.md')"
  sed -i '/^## Goal$/,+3d' "$plan"
  run aid_plan_summary_render "$plan" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"## Goal"* ]]
  [ ! -f "$OUT" ]
}

@test "a missing plan file is refused, not rendered from nothing" {
  run aid_plan_summary_render "$TMP/does-not-exist.md" "$OUT"
  [ "$status" -eq 1 ]
  [ ! -f "$OUT" ]
}

@test "usage without arguments fails instead of writing somewhere" {
  run aid_plan_summary_render
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}
