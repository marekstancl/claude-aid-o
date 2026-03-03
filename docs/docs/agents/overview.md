---
sidebar_position: 1
title: "Agent System Overview"
description: "Overview of AID's 7 agents in v2 — parametric dispatch, role cards, and the Controller + Workers architecture."
---

# Agent System Overview

AID v2 operates through a **Controller + Workers** architecture with **7 agents** (down from 18 in v1). The key innovation is **parametric dispatch**: instead of one agent per role, AID uses two parametric agents — **implementer** and **verifier** — that adopt any role via role cards loaded at dispatch time.

## Parametric Dispatch

In v1, each role (architect, backend, frontend, QA, security, etc.) was a separate agent with its own instruction file. In v2, all implementation roles are handled by a single **implementer** agent that reads a role card from `role-cards.md` at dispatch time. Similarly, all verification roles (code review, docs review, QA, security review) are handled by a single **verifier** agent with focus cards.

This means adding a new role requires only a new card in `role-cards.md` — no new agent file, no manifest update, no documentation page.

## Agent Dispatch Flow

```mermaid
graph LR
    Pipeline["Pipeline (FSM)"] -->|dispatch step| Implementer
    Implementer -->|reads| RoleCard["Role Card<br/>(architect/backend/frontend/...)"]
    RoleCard --> Work["Execute Step"]
    Work --> Output["step output.md"]
    Output --> Pipeline2["Pipeline (FSM)"]
    Pipeline2 -->|dispatch review| Verifier
    Verifier -->|reads| FocusCard["Focus Card<br/>(qa/security/code-review/docs-review)"]
    FocusCard --> Review["Verify Output"]
    Review --> Verdict["PASS / FAIL / PASS_WITH_NOTES"]
```

## The 7 Agents

### Parametric Agents

| Agent | Type | Purpose | Cards |
|-------|------|---------|-------|
| [Implementer](./implementer) | Parametric | Execute plan steps — code, design, docs, instrumentation | 8 role cards (architect, backend, frontend, domain, observability, docs-writer, release, security) |
| [Verifier](./verifier) | Parametric | Verify step outputs — tests, reviews, security checks | 4 focus cards (qa, security-review, code-review, docs-review) |

### Specialist Agents

| Agent | Type | Purpose | When Dispatched |
|-------|------|---------|-----------------|
| [Auditor](./auditor) | Specialist | Post-Epic health audit — 8 categories, scoring, trends | After Epic DONE + merge |
| [Curator](./curator) | Specialist | Evaluate improvements, extract lessons, manage backlog | After gates pass, before PM approval |
| [Project Scanner](./project-scanner) | Specialist | Analyze codebase structure, tech stack, conventions | During `/aid-init` or on-demand |

### Utility Agents

| Agent | Type | Purpose | When Dispatched |
|-------|------|---------|-----------------|
| [Gate Fixer](./gate-fixer) | Utility | Fix failing quality gates with minimal changes | When gates fail during pipeline |
| [Run Validator](./run-validator) | Utility | Validate run files, state.yaml, evidence completeness | At phase-end or run-end checkpoints |

## How Agents Communicate

Agents do not call each other directly. The communication path is always:

1. The pipeline dispatches an agent with a task input (step objective, context files, allowed paths).
2. The agent reads the `agent-protocol` skill for input/output format.
3. The agent reads its role card or focus card from `role-cards.md`.
4. The agent reads prior step outputs from the evidence trail.
5. The agent produces structured output to `evidence/<epic_id>/<run_id>/steps/`.
6. The pipeline stores the output and uses it to inform subsequent dispatches.

Every inter-agent dependency is explicit and traceable in the evidence trail.

## Scope Enforcement

Every agent receives an `allowed_paths` list. Agents must:

- Only modify files within `allowed_paths`
- Report `result: escalate` if the task requires changes outside allowed paths
- A second violation triggers FSM transition to ESCALATION state

## Related

- [Skills Overview](../skills/overview)
- [Pipeline Skill](../skills/pipeline)
- [Role Cards Skill](../skills/role-cards)
- [Agent Protocol Skill](../skills/agent-protocol)
