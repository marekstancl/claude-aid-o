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

---

## Pre-Output Quality Check (MANDATORY)

Before producing your step_output, run these checks on ALL files you created or modified:

1. **Auto-fix linting issues:**
   ```bash
   ruff check --fix {files_you_modified}
   ruff format {files_you_modified}
   ```
   If `ruff` is not available (non-Python project), use the project's configured linter
   from `project-profile.yaml` -> `tech_stack.lint`.

2. **Remove debugging artifacts:**
   - No `print()` statements (Python) or `console.log()` (JS/TS) in production code
   - No `import pdb` or `debugger` statements
   - No commented-out code blocks

3. **Verify imports:**
   - All imports are used
   - No wildcard imports (`from x import *`)
   - Imports are sorted (isort convention)

This step exists to prevent gate failures. A gate retry costs ~3000 tokens.
Running these checks locally costs ~50 tokens. Always run them.

---

## Git Discipline

- Commit after each meaningful change (not at the end of all work)
- Use conventional commit format: `type(scope): description`
- Types: feat, fix, refactor, test, docs, chore
- One logical change per commit
- If you see a GIT CONTEXT block in your dispatch prompt, follow its instructions
- Do NOT push to remote unless explicitly instructed
- Do NOT switch branches unless explicitly instructed

---

## Improvement Notes

During your work, record observations about code or architecture that is **outside your current task scope** but could be improved.

**Format:** (see `skills/improvement-proposals.md` for full specification)

```yaml
improvement_notes:
  - type: refactoring|performance|security|architecture|dx
    area: "path/to/affected/module"
    observation: "What you observed — be specific"
    suggestion: "Concrete, actionable suggestion"
    priority: low|medium|high
    source_agent: "{your_role}"
    source_step: "{step_id}"
```

## Discovered Issues

If you encounter problems **outside your task scope** during work, report them in your output using `## DISCOVERED ISSUES`:

```
## DISCOVERED ISSUES

- **[SEVERITY]** Description of the problem
  - Impact: What is affected
  - Recommendation: Fix now / defer / escalate
```

Severities:
- **CRITICAL** — blocks your work or other steps. Controller will auto-fix or escalate to PM.
- **HIGH** — should be addressed but doesn't block you. Goes to backlog + PM notification.
- **MEDIUM** — technical debt or minor improvement. Curator picks up later.
- **INFO** — for awareness only.

Only report genuine issues. Do not create this section if you found no issues.

**Record when you see:**
- Accessibility issues (missing alt text, no keyboard navigation, poor contrast)
- Performance problems (large bundle imports, unnecessary re-renders, missing lazy loading)
- Inconsistent component patterns (mixing styles, different state approaches)
- Missing loading or error states in UI components
- Responsive design gaps

**Do NOT record:**
- Issues you are actively fixing in your current task
- Style preferences without objective backing
- Suggestions requiring complete rewrites with unclear benefit

---

## Output Requirements

Your step output MUST end with an `## Execution Summary` block.
See `skills/agent-core.md` for the exact format. This is not optional.
