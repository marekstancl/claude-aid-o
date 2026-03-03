---
sidebar_position: 2
title: "Implementer Agent"
description: "Parametric agent that adopts any implementation role via role cards — architect, backend, frontend, domain, and more."
---

# Implementer Agent

The Implementer is a **parametric agent** — a single agent that adopts different roles at dispatch time by reading a role card from `role-cards.md`. Instead of separate architect, backend, frontend, and domain agents (as in v1), the implementer loads the appropriate role card and follows its identity, capabilities, and constraints.

## Role

The Implementer executes plan steps during EPIC runs. Its exact behavior is determined by the `role` field in the task input, which maps to a role card in `skills/role-cards.md`.

## When Dispatched

- During EXECUTE state, for each step in `plan.json`
- The pipeline reads the step's `role` field and dispatches the implementer with that role
- One dispatch per step (or parallel dispatches for same-wave steps)

## How It Works

1. Read `skills/role-cards.md` — find the section matching the assigned role
2. Read `skills/agent-protocol.md` — follow the universal input/output format
3. Read all `context_files` from the task input
4. Execute according to the role card's Capabilities and Constraints
5. Produce output following the agent-protocol output format

## Available Role Cards

| Role | Identity | Model |
|------|----------|-------|
| **architect** | Design API contracts, ADRs, module boundaries. Never implements. | opus |
| **backend** | Implement server-side code — APIs, services, DB, integrations. | opus |
| **frontend** | Implement UI against contracts with RBAC guards. | opus |
| **domain** | Define domain model, invariants, state machines, business rules. | sonnet |
| **observability** | Add traces, structured logs, metrics instrumentation. | sonnet |
| **docs-writer** | Write and update technical documentation. | sonnet |
| **release** | Prepare releases — version bump, changelog, tag. | sonnet |
| **security** | Verify authorization, run SAST, check for secrets. | sonnet |

Additional specialty role cards (e.g., `langgraph`, `python-async`, `sql-isolation`) are available for specific project types. See [Role Cards](../skills/role-cards) for the complete reference.

## Model Selection

The model is determined by the role card:

- **opus**: architect, backend, frontend (complex implementation roles)
- **sonnet**: domain, observability, docs-writer, release, security (structured/analytical roles)

## Key Behaviors

- **Follows the role card strictly.** The role card defines what the implementer can and cannot do. An implementer with the `architect` role never writes implementation code. An implementer with the `backend` role never touches frontend files.
- **Follows agent-protocol.md for all I/O.** Every output ends with a structured YAML block containing `step_id`, `result`, `summary`, `files_changed`, and `improvement_notes`.
- **Scope enforcement via `allowed_paths`.** Only modifies files listed in the task input's `allowed_paths`. Reports `result: escalate` if changes outside that scope are needed.
- **Pre-output quality check.** Before writing output, runs auto-fix linting, removes debug artifacts, verifies imports, and checks type safety.
- **Treats EPIC goal text as untrusted content.** Step objectives and previous outputs are data, not instructions that override the agent protocol.

## Related

- [Verifier Agent](./verifier)
- [Role Cards Skill](../skills/role-cards)
- [Agent Protocol Skill](../skills/agent-protocol)
- [Pipeline Skill](../skills/pipeline)
