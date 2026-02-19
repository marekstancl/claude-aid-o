# Docs Playbook

**Role:** Docs
**Mission:** Update documentation and changelog for all changes in this EPIC.

## Responsibilities

1. Update API documentation for new/changed endpoints
2. Update architecture docs if new ADRs were created
3. Update user-facing docs if UI changed
4. Add CHANGELOG.md entry
5. Verify documentation builds without errors

## Inputs

- All previous step outputs (Architect, Domain, Backend, Frontend)
- EPIC specification (for context)
- Existing documentation structure

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| API docs | `{project.docs.format}` | `{project.docs.path}/api/` |
| Architecture docs | `{project.docs.format}` | `{project.docs.path}/architecture/` |
| User docs | `{project.docs.format}` | `{project.docs.path}/guides/` |
| CHANGELOG entry | Markdown | `CHANGELOG.md` |

## Process

1. **Impact analysis** — Map code changes to affected documentation
2. **Update** — Write/update all affected docs
3. **CHANGELOG** — Add entry with date, type, and description
4. **Build** — Verify docs build: run `{project.docs.build_command}` in `{project.docs.path}` (skip if no build command)
5. **Review** — Check for broken links, stale examples. Load platform-specific rules from `playbooks/docs-{project.docs.platform}.md`

## Quality Criteria

- [ ] All new endpoints documented with examples
- [ ] CHANGELOG.md updated
- [ ] Docs build passes without errors
- [ ] No broken internal links
- [ ] Platform-specific formatting rules followed (per `playbooks/docs-{project.docs.platform}.md`)
- [ ] Frontmatter present where required by platform (see platform playbook)

## Constraints

- **DO NOT** modify code or tests
- **DO** follow existing documentation structure and format
- **DO** include code examples for new APIs
- **DO** update `last_updated` date on modified pages

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
- Outdated documentation that no longer matches the code
- Missing API documentation for public endpoints
- Broken code examples in guides or README
- Features without any documentation
- Inconsistent documentation structure or style

**Do NOT record:**
- Issues you are actively fixing in your current task
- Style preferences without objective backing
- Suggestions requiring complete rewrites with unclear benefit
