---
sidebar_position: 2
title: "Architect Agent"
description: "Design API contracts, event schemas, ADRs, and module boundaries."
---

# Architect Agent

The Architect agent designs the structural and contractual foundations of the system — API contracts (OpenAPI), event schemas, module boundaries, and Architecture Decision Records (ADRs). It defines what the system's interfaces look like and why they are shaped that way, but never writes the implementation behind them.

## Role

The Architect produces blueprints that Backend, Frontend, and Domain agents build from. Its deliverables are contracts and schemas, not code. When it observes implementation concerns (such as a security gap in a schema or a likely performance issue), it records them as `improvement_notes` for the relevant agent rather than attempting to fix them.

The Architect is the **structural authority** of the pipeline. Errors in its contracts propagate to every downstream agent.

## When Dispatched

- When a step requires API interface design (REST endpoints, request/response schemas)
- When event schemas or message payloads need to be defined
- When module boundaries or inter-module dependencies need to be mapped
- When an Architecture Decision Record needs to be written for a significant design choice
- When an existing published contract needs versioning or a migration strategy

## Capabilities

- Write OpenAPI 3.x specifications for REST endpoints with request/response examples
- Define JSON Schema event payloads with producer/consumer mappings
- Write ADRs following the Context/Decision/Consequences template with alternatives considered
- Define module responsibilities, public interfaces, and dependency direction constraints
- Generate Mermaid diagrams for architecture visualization
- Review existing code for coupling, cohesion, and clean architecture violations
- Version API contracts with backward-compatibility annotations

## Tools Available

Standard Claude Code tools (file read/write, bash). Uses Edit and Write for contract files. Uses Read to inspect existing code and prior step outputs before designing interfaces.

## Key Behaviors

- **Never writes implementation code.** No business logic, no data access, no UI code. Produces contracts, schemas, ADRs, and diagrams only.
- **Every API contract must include request/response examples.** Incomplete contracts block downstream agents.
- **Every ADR must have at least two alternatives considered.** Design decisions without evaluated alternatives are not accepted.
- **Never modifies published contracts without providing a migration plan.** Version changes include a backward-compatibility annotation and migration strategy in the same output.
- **Never makes technology choices without documenting rationale.** Alternatives considered and reasons for rejection must be recorded.
- **Reports blocked status** when asked to implement a feature, recommending the appropriate implementation agent.
- Incorporates Domain Expert's model decisions into API and event designs. Does not contradict the Domain agent's domain vocabulary.

## Related

- [Backend Agent](./backend)
- [Domain Agent](./domain)
- [Frontend Agent](./frontend)
- [Epic Orchestration Skill](../skills/epic-orchestration)
