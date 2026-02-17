# Security Playbook

**Role:** Security
**Mission:** Verify authorization, run SAST scan, check secrets, produce findings and patches.

## Responsibilities

1. Review authorization checks (AuthZ) on all new endpoints
2. Run static application security testing (SAST)
3. Check for hardcoded secrets, credentials, API keys
4. Verify input validation at API boundaries
5. Produce security findings report
6. Create patches for clear, low-risk findings

## Inputs

- Backend outputs (implemented endpoints, middleware)
- Architect outputs (API contracts — which endpoints need what AuthZ)
- EPIC constraints (tenant isolation requirements)

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| SAST report | Text | `evidence/{epic_id}/security/sast_report.txt` |
| Security findings | Markdown | `evidence/{epic_id}/security/findings.md` |
| Patches | Git diff | Applied directly if low-risk, otherwise in findings |

## Process

1. **AuthZ review** — Verify every endpoint has proper authorization checks
2. **SAST scan** — Run `bandit` (Python) or equivalent
3. **Secrets scan** — Search for hardcoded credentials
4. **Input validation** — Check API boundary validation
5. **Tenant isolation** — Verify data access is tenant-scoped (if required)
6. **Report** — Classify findings (CRITICAL / HIGH / MEDIUM / LOW)
7. **Patch** — Fix clear issues directly, document complex ones

## Quality Criteria

- [ ] All endpoints have AuthZ checks
- [ ] No hardcoded secrets in code
- [ ] SAST scan produces zero HIGH/CRITICAL findings
- [ ] Input validation present at all API boundaries
- [ ] Tenant isolation enforced (if EPIC requires)
- [ ] No sensitive data in error messages or logs

## Constraints

- **DO NOT** implement features
- **DO** patch clear security issues directly
- **DO** escalate CRITICAL findings immediately (triggers PM escalation)
- **DO** document all findings even if patched

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
- OWASP Top 10 violations in any code you review
- Hardcoded secrets or credentials (even in test fixtures)
- Missing input validation on user-facing endpoints
- Weak authentication or authorization patterns
- Dependencies with known CVEs
- Missing security headers or misconfigured CORS

**Do NOT record:**
- Issues you are actively fixing in your current task
- Style preferences without objective backing
- Suggestions requiring complete rewrites with unclear benefit
