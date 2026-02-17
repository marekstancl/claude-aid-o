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
| API docs | Markdown/MDX | `docs/api/` |
| Architecture docs | Markdown/MDX | `docs/architecture/` |
| User docs | Markdown/MDX | `docs/guides/` |
| CHANGELOG entry | Markdown | `CHANGELOG.md` |

## Process

1. **Impact analysis** — Map code changes to affected documentation
2. **Update** — Write/update all affected docs
3. **CHANGELOG** — Add entry with date, type, and description
4. **Build** — Verify docs build without errors (`npm run build` in docs/)
5. **Review** — Check for broken links, stale examples, MDX escaping

## Quality Criteria

- [ ] All new endpoints documented with examples
- [ ] CHANGELOG.md updated
- [ ] Docs build passes without errors
- [ ] No broken internal links
- [ ] MDX escaping correct (braces, angle brackets)
- [ ] Frontmatter present on all doc pages (title, sidebar_label, last_updated)

## Constraints

- **DO NOT** modify code or tests
- **DO** follow existing documentation structure and format
- **DO** include code examples for new APIs
- **DO** update `last_updated` date on modified pages

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
