---
id: P-TEST-F13
type: plan
status: draft
created: 2026-05-31
author: PM + AI
---

# Plan: F13 fence regression fixture

## Context

Meta-plan that quotes AID syntax. Used to verify aid-plan-to-epic.sh does
NOT count ### Step / **EPIC** lines inside fenced code blocks.

Pre-fix behaviour: the fenced **EPIC 7: Steps 99-100** marker corrupts
phase boundaries → phase 1 fails with "No steps found for phase 1".
Post-fix: only the real ### Step 1 / ### Step 2 are recognised.

## Goal

Document AID step syntax. Real implementation has exactly 2 steps.

## Scope

**In scope:**
- docs/

**Out of scope:**
- src/

## Implementation Steps

The reference doc should explain that real step headers look like this:

```markdown
### Step 99: This is INSIDE a fence and must NOT be counted
### Step 100: Another fenced quoted header
**EPIC 7: Steps 99-100 — Fenced marker that must NOT be counted**
## Task 101: Also fenced — must NOT be counted
```

And nested example with 4-backtick outer fence:

````markdown
### Step 200: Nested-fence quoted header — must NOT be counted
````

### Step 1: Write the syntax reference doc

**Objective:** Produce a syntax reference showing how AID parses step headers.

**AID Role:** docs-writer

**Files:**
- Create: `docs/aid-syntax.md`

**Acceptance Criteria:**
- [ ] Reference doc exists

### Step 2: Add a worked example

**Objective:** Provide a runnable worked example demonstrating the parser.

**AID Role:** docs-writer

**Files:**
- Create: `docs/aid-syntax-example.md`

**Acceptance Criteria:**
- [ ] Example renders correctly

## Constraints

- Documentation only, no code changes.
