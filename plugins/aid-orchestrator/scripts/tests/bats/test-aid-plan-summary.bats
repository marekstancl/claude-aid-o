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

@test "a plan with no Risks table and no AID Role still renders under a strict shell" {
  # Both counts used to run a pipeline whose `grep` exits 1 on zero matches;
  # under `set -o pipefail` that aborted the CALLER instead of rendering a
  # zero (codex review of EPIC 2, findings 1 and 2).
  plan="$(write_plan P955 'plugins/aid-orchestrator/commands/aid-help.md')"
  sed -i '/^## Risks$/,/^## Next Steps$/d' "$plan"
  sed -i '/^\*\*AID Role:\*\*/d' "$plan"
  run bash -c "set -euo pipefail
    source '$PLUGIN_ROOT/scripts/lib/aid-plan-summary.sh'
    aid_plan_summary_render '$plan' '$OUT'"
  [ "$status" -eq 0 ]
  grep -q 'Rizika pojmenovaná v plánu: 0' "$OUT"
  grep -q 'Role, kterým se bude zadávat: —' "$OUT"
}

@test "a step quoted inside a fenced block is not counted as a step" {
  # AID's own plans quote `### Step N:` in examples. Counting those inflates a
  # number the page presents as counted from the plan.
  plan="$(write_plan P956 'plugins/aid-orchestrator/commands/aid-help.md')"
  cat >> "$plan" <<'EOF'

## Appendix

```markdown
### Step 99: an example step, not a real one

**Files:**
- Modify: `nowhere.md` — illustration
```
EOF
  aid_plan_summary_render "$plan" "$OUT"
  grep -q '2 kroků' "$OUT"
}

@test "P085: the page names the standards the plan named, and the reuse-search count" {
  plan="$(write_plan P957 'plugins/aid-orchestrator/commands/aid-help.md')"
  # A Standards section with an annotated heading — `## Standards (V3)` is how
  # a real plan writes it, and exact heading equality used to skip it entirely.
  cat >> "$plan" <<'EOF'

## Standards (V3)

| Standard | Why it binds | Deviation |
|---|---|---|
| `/ecosystem/specs/test-standard` | the plan changes a suite | none |

### Step 9: found something

**Files:**
- Create: `src/brand-new.ts` — a new thing

**Reuse check:** searched: `grep -rn brandNew src/` → none — nothing like it exists
EOF
  run bash -c "set -euo pipefail
    source '$PLUGIN_ROOT/scripts/lib/aid-plan-summary.sh'
    aid_plan_summary_render '$plan' '$OUT'"
  [ "$status" -eq 0 ]
  grep -q 'test-standard' "$OUT"
  grep -q 'doloženým hledáním: 1/1' "$OUT"
}

@test "P085: a plan naming no standards and founding nothing renders neither row" {
  plan="$(write_plan P958 'plugins/aid-orchestrator/commands/aid-help.md')"
  run bash -c "set -euo pipefail
    source '$PLUGIN_ROOT/scripts/lib/aid-plan-summary.sh'
    aid_plan_summary_render '$plan' '$OUT'"
  [ "$status" -eq 0 ]
  # Absent, not empty: an empty row reads as an unanswered question.
  ! grep -q 'Standardy, na které' "$OUT"
  ! grep -q 'doloženým hledáním' "$OUT"
}
