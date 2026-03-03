---
sidebar_position: 7
title: "Role Cards"
description: "8 implementer role cards and 4 verifier focus cards that define parametric agent behavior in AID v2."
---

# Role Cards

Role cards define the identity, capabilities, constraints, and model selection for AID's parametric agents. Instead of separate agent files per role (as in v1), all roles are defined as cards in a single `role-cards.md` file. The [Implementer](../agents/implementer) loads a role card; the [Verifier](../agents/verifier) loads a focus card.

## How Cards Work

1. Pipeline dispatches an implementer or verifier with a `role` or `focus` field
2. The agent reads `skills/role-cards.md` and finds the matching card section
3. The card defines: Identity, Capabilities, Constraints, Improvement Hints, Model, Max Parallel
4. The agent follows the card's rules in combination with [agent-protocol](./agent-protocol)

## Implementer Role Cards (8)

| Role | Identity | Model | Max Parallel |
|------|----------|-------|-------------|
| **architect** | Design API contracts, ADRs, module boundaries. Never implements. | opus | 1 |
| **backend** | Implement server-side code -- APIs, services, DB, integrations. | opus | 2 |
| **frontend** | Implement UI against contracts with RBAC guards. | opus | 2 |
| **domain** | Define domain model, invariants, state machines, business rules. | sonnet | 1 |
| **observability** | Add traces, structured logs, metrics instrumentation. | sonnet | 2 |
| **docs-writer** | Write and update technical documentation. | sonnet | 2 |
| **release** | Prepare releases -- version bump, changelog, tag. | sonnet | 1 |
| **security** | Verify authorization, run SAST, check for secrets, produce patches. | sonnet | 1 |

### Card Structure

Each role card contains:

- **Identity** -- one sentence defining the role's purpose and boundaries
- **Capabilities** -- what the role can do (5-6 bullet points)
- **Constraints** -- what the role must never do (hard rules)
- **Improvement Hints** -- what to look for when recording `improvement_notes`
- **Model** -- which LLM model to use (opus for complex, sonnet for structured)
- **Max Parallel** -- how many instances can run concurrently

### Model Selection Logic

```
architect, backend, frontend → opus
domain, observability, docs-writer, release, security → sonnet
```

## Verifier Focus Cards (4)

| Focus | Scope | Key Checks | Model |
|-------|-------|------------|-------|
| **qa** | Write tests, verify acceptance criteria | Coverage >80%, edge cases, error paths | sonnet |
| **security-review** | Read-only security analysis | AuthZ, secrets, injection, OWASP | sonnet |
| **code-review** | Code quality review | Module boundaries, DRY, type safety, N+1 | sonnet |
| **docs-review** | Documentation accuracy | Endpoint docs, code examples, CHANGELOG | sonnet |

An additional **e2e** focus card handles browser-level E2E testing via Playwright MCP.

### Verdict Format

All verifiers produce: **PASS**, **FAIL**, or **PASS_WITH_NOTES** with evidence.

## Specialty Role Cards

Additional role cards for specific project types:

| Role | Purpose | When Used |
|------|---------|-----------|
| **langgraph** | LangGraph agents -- StateGraph, Supervisor pattern, tools binding | `tech_stack` includes LangGraph |
| **python-async** | Async/await patterns -- event loops, async context managers | Python async projects |
| **sql-isolation** | Multi-tenant data isolation -- schema per tenant, query scoping | Multi-tenant databases |

Specialty cards are loaded alongside standard role cards when the project profile includes matching technology.

## Adding New Roles

To add a new role:
1. Add a new section to `skills/role-cards.md` following the card structure
2. No agent file changes, no manifest updates, no new documentation pages needed

This is the key advantage of parametric dispatch -- extensibility without infrastructure changes.

## Related

- [Implementer Agent](../agents/implementer)
- [Verifier Agent](../agents/verifier)
- [Agent Protocol](./agent-protocol)
