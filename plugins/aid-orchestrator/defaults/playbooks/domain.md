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
| Domain model | Markdown + code | `{project.docs.path}/domain/{module}.md` |
| Entity definitions | Python/TypeScript | `backend/app/models/` |
| State machine | Mermaid diagram | Embedded in domain doc |
| Business rules | Documented invariants | `{project.docs.path}/domain/{module}.md` |

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
- Domain logic leaking into infrastructure/presentation layers
- Business rules implemented inconsistently across modules
- Missing or unclear ubiquitous language terms
- Anemic domain models (logic in services instead of entities)
- Domain events that should exist but don't

**Do NOT record:**
- Issues you are actively fixing in your current task
- Style preferences without objective backing
- Suggestions requiring complete rewrites with unclear benefit

---

## Output Requirements

Your step output MUST end with an `## Execution Summary` block.
See `skills/agent-core.md` for the exact format. This is not optional.
