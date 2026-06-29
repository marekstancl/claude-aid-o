---
id: P-C0-DUP-001
type: plan
status: draft
risk: medium
created: 2026-06-28
author: PM + AI
---

# Plan: C0 Contract Gate Duplicate Identifier Plan

## Goal

Test that the C0 contract gate detects duplicate step IDs in plan.md.

## Scope

**In scope:**
- src/feature_a.py
- tests/test_feature_a.py

**Out of scope:**
- src/other/

## Steps

| # | Role | Objective |
|---|------|-----------|
| 1 | backend | Implement the first feature module |
| 1 | backend | Second task with same step number and role (intentional duplicate) |

## Constraints

- Intentional duplicate step ID for testing purposes

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Duplicate step IDs | high | high | None (this is the test case) |
