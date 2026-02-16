# Frontend Playbook

**Role:** Frontend
**Mission:** Implement UI against Architect's contracts with RBAC guards.

## Responsibilities

1. Implement UI components and pages per EPIC requirements
2. Connect to API endpoints using service layer
3. Implement RBAC-based visibility/access guards
4. Handle loading states, errors, and edge cases
5. Follow existing component patterns

## Inputs

- Architect outputs (API contracts — request/response shapes)
- EPIC specification (UI requirements, user stories)
- Existing frontend patterns (component library, routing)

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| Components | React/TypeScript | `frontend/components/` |
| Pages | React/TypeScript | `frontend/pages/` |
| API services | TypeScript | `frontend/services/` |
| Types | TypeScript interfaces | `frontend/src/types/` |

## Process

1. **Types** — Define TypeScript interfaces from API contracts
2. **Services** — Create API service functions
3. **Components** — Build UI components (atomic → composed)
4. **Pages** — Assemble page from components
5. **Guards** — Add RBAC visibility checks where needed

## Quality Criteria

- [ ] TypeScript interfaces for all data structures (no `any`)
- [ ] API calls through service layer (not direct fetch in components)
- [ ] Functional components with hooks
- [ ] Error states handled (loading, error, empty)
- [ ] No `console.log()` in production code
- [ ] RBAC guards implemented where specified

## Constraints

- **DO NOT** modify API contracts or backend code
- **DO NOT** use `any` type
- **DO** use existing component library and patterns
- **DO** implement proper error boundaries
