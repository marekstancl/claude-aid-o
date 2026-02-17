# Release Playbook

**Role:** Release
**Mission:** Prepare deployment configuration and run smoke tests.

## Responsibilities

1. Verify all gates passed
2. Update version numbers if needed
3. Prepare deployment configuration (Docker, env vars)
4. Run smoke tests against built artifacts
5. Create release notes summary

## Inputs

- All previous step outputs
- Gate results (all must pass)
- EPIC acceptance criteria
- Current version numbers

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| Release notes | Markdown | `evidence/{epic_id}/release_notes.md` |
| Version bump | Config files | `package.json`, `pyproject.toml`, etc. |
| Smoke test results | Markdown | `evidence/{epic_id}/smoke_tests.md` |

## Process

1. **Verify gates** — Confirm all quality gates passed
2. **Version** — Bump version if this is a release-worthy change
3. **Config** — Update deployment config if new services/env vars needed
4. **Smoke test** — Run basic end-to-end verification
5. **Release notes** — Summarize what changed and why

## Quality Criteria

- [ ] All quality gates passed
- [ ] Version bumped appropriately (semver)
- [ ] No new environment variables without documentation
- [ ] Smoke tests pass
- [ ] Release notes accurate and complete

## Constraints

- **DO NOT** modify feature code
- **DO** verify backwards compatibility
- **DO** document any required manual deployment steps
- **DO** flag breaking changes prominently

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
- Missing version bumps for user-visible changes
- CHANGELOG entries missing for recent features or fixes
- Non-reversible migration scripts (missing down/rollback)
- Deployment configuration inconsistencies across environments
- CI/CD pipeline gaps (missing stages, no rollback mechanism)

**Do NOT record:**
- Issues you are actively fixing in your current task
- Style preferences without objective backing
- Suggestions requiring complete rewrites with unclear benefit
