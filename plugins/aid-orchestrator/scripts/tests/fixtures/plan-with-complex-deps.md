---
id: P-TEST-004
type: plan
status: draft
created: 2026-02-28
author: PM + AI
---

# Plan: Complex Dependencies Test Plan

## Context

This plan exercises advanced dependency parsing: trailing text after step
references, range notation, mixed formats, reversed ranges, and cross-phase
dependency stripping.

## Goal

Validate that the dependency parser correctly handles all supported dependency
formats, including edge cases.

## Scope

**In scope:**
- src/complex/

**Out of scope:**
- src/unrelated/

## Implementation Steps

**EPIC 1: Steps 1-3 — Foundation Phase**

### Step 1: Base configuration

**Objective:** Set up the base configuration for the project.

**AID Role:** backend

**Files:**
- Create: `src/complex/config.py`

**Acceptance Criteria:**
- [ ] Configuration loads correctly

### Step 2: Core module with trailing text dep

**Objective:** Implement core module that depends on base configuration.

**AID Role:** backend

**Files:**
- Create: `src/complex/core.py`

**Dependencies:**
- Depends on: Step 1 — provides the base configuration

**Acceptance Criteria:**
- [ ] Core module initializes

### Step 3: Integration with multiple deps

**Objective:** Wire up integration layer using both prior steps.

**AID Role:** backend

**Files:**
- Create: `src/complex/integration.py`

**Dependencies:**
- Depends on: Step 1, Step 2 — both needed for integration

**Acceptance Criteria:**
- [ ] Integration layer connects all components

**EPIC 2: Steps 4-6 — Implementation Phase**

### Step 4: Feature with range dep

**Objective:** Implement feature that depends on all foundation steps.

**AID Role:** backend

**Files:**
- Create: `src/complex/feature.py`

**Dependencies:**
- Depends on: Steps 1-3

**Acceptance Criteria:**
- [ ] Feature works end-to-end

### Step 5: Mixed format dep

**Objective:** Implement module using mixed dependency format.

**AID Role:** backend

**Files:**
- Create: `src/complex/mixed.py`

**Dependencies:**
- Depends on: Step 1, Steps 3-5

**Acceptance Criteria:**
- [ ] Mixed module loads

### Step 6: Module with reversed range dep

**Objective:** Module with a reversed range that should produce a warning.

**AID Role:** backend

**Files:**
- Create: `src/complex/reversed.py`

**Dependencies:**
- Depends on: Steps 14-1

**Acceptance Criteria:**
- [ ] Module exists

**EPIC 3: Steps 7-8 — Validation Phase**

### Step 7: Cross-phase dep test

**Objective:** This step depends on steps from EPIC 1 which are outside this phase.

**AID Role:** qa

**Files:**
- Create: `tests/test_cross_phase.py`

**Dependencies:**
- Depends on: Steps 1-6

**Acceptance Criteria:**
- [ ] Tests pass

### Step 8: Final validation

**Objective:** Final validation step with no dependencies.

**AID Role:** qa

**Files:**
- Create: `tests/test_final.py`

**Acceptance Criteria:**
- [ ] All validations pass

## Constraints

- Bash 4.0+ compatible
- No external dependencies

## Success Criteria

- All acceptance criteria verified

---

**Last Updated:** 2026-02-28
