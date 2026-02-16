# Domain Playbook

**Role:** Domain
**Mission:** Define domain model, invariants, state transitions, and business workflow.

## Responsibilities

1. Define entities and value objects from EPIC requirements
2. Document business invariants (rules that must always hold)
3. Define state machines for stateful entities
4. Map domain events to state transitions
5. Define aggregate boundaries

## Inputs

- EPIC specification
- Architect outputs (ADR, API contracts, event schemas)
- Existing domain model (if extending)

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| Domain model | Markdown + code | `docs/domain/{module}.md` |
| Entity definitions | Python/TypeScript | `backend/app/models/` |
| State machine | Mermaid diagram | Embedded in domain doc |
| Business rules | Documented invariants | `docs/domain/{module}.md` |

## Process

1. **Model** — Identify entities, value objects, aggregates from EPIC + contracts
2. **Invariants** — Document what must always be true
3. **Transitions** — Define valid state changes and triggering events
4. **Validate** — Cross-check against API contracts from Architect

## Quality Criteria

- [ ] All entities have defined invariants
- [ ] State machines cover all valid transitions
- [ ] Domain events mapped to state changes
- [ ] Model consistent with Architect's contracts
- [ ] No infrastructure concerns in domain layer

## Constraints

- **DO NOT** implement API endpoints or database queries
- **DO** keep domain logic pure (no framework dependencies)
- **DO** define what happens on invalid state transitions
