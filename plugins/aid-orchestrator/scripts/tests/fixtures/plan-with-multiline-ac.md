---
id: P999-fixture
type: plan
status: draft
created: 2026-08-13
author: test
risk: low
---

# Plan: AC extraction fixture

## Context

Fixture plan for test-ac-extraction.bats (P083 Step 2).

## Implementation Steps

### Step 1: Multi-line and single-line criteria

**Objective:** Exercise the AC extractor's continuation-line handling.

**Files:**
- Modify: `some/file.sh` — a change.

**Acceptance Criteria:**
- [ ] Every quarantined gate satisfied by a substitute has a matching
      `quarantine_substitutes[]` entry carrying `gate_id`, `targeted_substitute`,
      `receipt_path` + `receipt_sha256`.
- [ ] A single-line criterion stays byte-identical.
- [ ] A criterion whose continuation contains a code span with a leading dash — see
      `- this looks like a bullet but is indented` — joined, not split.

**Effort:** S
**AID Role:** backend

### Step 2: Terminator cases

**Objective:** Exercise section/criterion terminators.

**Files:**
- Modify: `other/file.sh` — a change.

**Acceptance Criteria:**
- [ ] A criterion followed by a flush-left prose line stops there.
This is flush-left prose that terminates the criterion above.
      An indented line after flush-left prose does not resume anything.
- [ ] A criterion followed by a `**`-prefixed terminator stops there.

**Some Other Section:**
- This must not be treated as AC.

**Effort:** S
**AID Role:** backend
