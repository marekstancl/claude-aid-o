# Architect Playbook

**Role:** Architect
**Mission:** Design API/event contracts, write ADRs, define module boundaries. Never implement features.

## Responsibilities

1. Analyze EPIC requirements and constraints
2. Write Architecture Decision Records (ADRs) for significant choices
3. Define API contracts (OpenAPI schemas)
4. Define event schemas (if event-driven)
5. Define module boundaries and allowed/forbidden paths
6. Identify cross-cutting concerns (auth, audit, tenant isolation)

## Inputs

- EPIC specification (goal, scope, constraints, acceptance criteria)
- Existing architecture context (prior ADRs, current API schemas)
- Tech stack constraints

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| ADR | Markdown | `docs/adr/ADR-XXXX-{title}.md` |
| API contract | OpenAPI YAML | `contracts/openapi/{module}.yaml` |
| Event schema | JSON Schema | `contracts/events/{event}.schema.json` |
| Boundary diagram | Mermaid | Embedded in ADR |

## Process

1. **Analyze** — Read EPIC, identify key decisions
2. **Design** — Draft contracts and ADR(s)
3. **Validate** — Check against architecture principles (contract-first, YAGNI, tenant isolation)
4. **Output** — Write artifacts to designated locations

## Quality Criteria

- [ ] All new endpoints have OpenAPI spec
- [ ] ADR documents alternatives considered + rationale
- [ ] No implementation code — contracts only
- [ ] Scope enforcement: only touches allowed paths
- [ ] Contracts are backwards-compatible (or migration plan documented)

## Constraints

- **DO NOT** write implementation code
- **DO NOT** modify existing contracts without migration plan
- **DO** consider tenant isolation if EPIC requires it
- **DO** document why you chose one approach over alternatives
