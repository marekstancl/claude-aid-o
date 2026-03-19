# Design Section Templates

Use these structures as guidance when presenting design sections during brainstorming Step 5.
Adapt based on the specific topic. Not all sections apply to every topic — omit irrelevant ones.

## Universal Format

Every design section follows this structure:

```
{Section Title}
====================================
Key Decisions: (what was decided and why)
Structure: (components, entities, endpoints, steps — topic-dependent)
Constraints: (limits, non-goals, compatibility requirements)
Open Questions: (anything needing PM input in this section)
```

## Section-Specific Templates

### Architecture

```
Architecture
====================================
Components:
  - {Component 1}: {responsibility}
  - {Component 2}: {responsibility}

Data Flow:
  {User/Client} → {Component 1} → {Component 2} → {Storage}

Integration Points:
  - {External service}: {how it connects}
  - {Existing module}: {dependency type}

Patterns:
  - {Pattern name}: {why it applies}

Design Principle:
  - Favor components with one clear purpose, well-defined interfaces,
    and independent testability. Each component should be describable
    in one sentence. If it cannot be, consider splitting it.
```

### Data Model

```
Data Model
====================================
Entities:
  {Entity 1}:
    - {field}: {type} {constraints}
    - {field}: {type} {constraints}
    Invariants: {business rules}

  {Entity 2}:
    - {field}: {type} {constraints}
    Relations: {Entity 1} → {Entity 2} (1:N)

Storage:
  - Database: {type}
  - Indexes: {fields for performance}
  - Migrations: {strategy}
```

### API Design

```
API Design
====================================
Base: /api/v1/{resource}

Endpoints:
  POST   /api/v1/{resource}      → 201 Created
  GET    /api/v1/{resource}      → 200 OK (paginated)
  GET    /api/v1/{resource}/{id} → 200 OK | 404 Not Found
  PATCH  /api/v1/{resource}/{id} → 200 OK | 404 Not Found
  DELETE /api/v1/{resource}/{id} → 204 No Content

Authentication: {method}
Error Format: { "error": "{code}", "message": "{detail}" }
Pagination: { "items": [...], "total": N, "page": N, "per_page": N }
```

### Other Applicable Sections

Use the Universal Format above for: Implementation Plan, Testing Strategy,
Risks & Mitigations, Security, Infrastructure, Migration Plan, Monitoring.

### E2E Verification Scenarios (auto-include if feature has user-facing output)

After Testing Strategy, propose end-to-end verification scenarios:

```
## E2E Verification

Layers: {auto-detected: Docker | DB | API | UI | AI logs}

### Scenario 1: {happy path flow name}
1. {Setup: create X, upload Y}
2. {Action: trigger Z}
3. {Verify: check DB entry, API response, UI display}

### Scenario 2: {error/edge case flow name}
1. {Setup: invalid input or missing dependency}
2. {Action: trigger flow}
3. {Verify: error handled, no corruption, UI shows error state}

Execution order: {Scenario 1 → 2 → ...} (if stateful: note which creates data for which)
```

Rules:
- At least 1 happy path + 1 negative/edge case scenario
- Note which layers are verified per scenario
- Note data dependencies between scenarios (stateful flows)
- PM approves scenarios in Step 6 (section-by-section)
