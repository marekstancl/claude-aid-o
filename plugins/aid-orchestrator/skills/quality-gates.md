# Quality Gates - Instructions

**Version:** 4.0.0
**Skill:** quality-gates
**Dependencies:** agent-core

---

## TL;DR - MUST Rules

1. **RUN all 6 gates** before EVERY commit (no exceptions)
2. **ANY gate fails** → Fix → Re-run from Gate 1
3. **ALL gates pass** → Commit allowed
4. **DOCUMENT** gate results in session file
5. **ESCALATE** uncertainties to PM (especially Gate 2)

---

## When to Run

**Before EVERY commit** that includes code, config, refactoring, bug fixes, or features.

```
Code ready → 6 Gates (in order) → ALL PASS → Commit → Push
                                → ANY FAIL → Fix → Re-run
```

**Time investment:** 3-5 minutes per commit
**Quick reference card:** See `checklist.md`

---

## The 6 Quality Gates

### Gate 1: Log Analysis + UI Smoke Test — CRITICAL

**Purpose:** Verify changes don't break runtime + UI renders correctly
**Time:** 60-120 seconds

#### 1a) Backend + Frontend Log Check

**Process:**
```bash
# Start frontend
cd {project.paths.frontend} && npm run dev  # Watch 30s

# Start backend
cd {project.paths.backend} && uvicorn app.main:app --reload  # Watch 30s
```

Replace commands per `{project.tech_stack}` (React → `npm run dev`, Vue → `npm run serve`, FastAPI → `uvicorn`, Express → `node server.js`, Django → `manage.py runserver`).

**Pass/Fail:**

| Pass | Fail |
|------|------|
| Frontend starts without errors | Any ERROR in logs |
| Backend starts without errors | Server crashes |
| No NEW warnings | Build fails |
| Server responds to requests | New critical warnings |

Pre-existing warnings: document in session file as "Known Warnings (Pre-Existing)".

**If fails:** Read error message → identify file + line → fix → re-run Gate 1.

#### 1b) Playwright UI Smoke Test (ONLY when UI changes)

**When to run:** Changes touch frontend components, pages, styles, or UI-related logic.
**When to skip:** Backend-only changes, config-only changes, docs-only changes, skill/workflow files.

**Process (Playwright MCP tools):**
1. `browser_navigate` → open the affected page(s)
2. `browser_console_messages` (level: "error") → check for JS runtime errors
3. `browser_snapshot` → verify page renders correctly (accessibility tree)
4. `browser_take_screenshot` → save visual evidence

**Pass/Fail:**

| Pass | Fail |
|------|------|
| Page loads without JS errors | Console shows runtime errors |
| Key elements visible in snapshot | Page blank or broken layout |
| No React/Vue error boundaries triggered | Error boundary displayed |
| Screenshot matches expected layout | Visual regression detected |

**If Playwright unavailable (MCP not connected, browser install fails):**

Fallback to manual QA proposal:
```
MANUAL QA NEEDED (Playwright unavailable):
1. Open [URL] in browser
2. Check browser console for JS errors
3. Verify [specific elements] are visible
4. Test [specific interaction] works
→ PM confirms: PASS or FAIL
```

**If fails:** Fix UI issue → re-run Gate 1 (both 1a and 1b).

---

### Gate 2: Documentation Impact Analysis — CRITICAL

**Purpose:** Keep documentation synchronized with code
**Time:** 2-5 minutes

**Process:**

1. `git diff --name-only` — list all changed files
2. For each file, determine documentation impact:

| Code Change | Usually Affects |
|-------------|-----------------|
| Database models | ERD, schema docs |
| API endpoints | API docs, integration guides |
| Core business logic | System overview, architecture |
| UI components | Component docs, UI guide |
| Configuration | Setup guide, deployment docs |
| Any `feat:` or `fix:` | CHANGELOG.md |
| Breaking changes | Migration guide |

3. Update ALL affected documentation
4. Verify examples/links still valid
5. Stage docs: `git add {project.paths.docs}/...`

**If `project.docs.format == mdx`:** Escape `<`, `>`, `{`, `}` in text. Test build: `{project.docs.build_command}` in `{project.docs.path}`.

**If uncertain which docs need updating:** Escalate to PM with list of changed files + potentially affected docs. Do NOT guess.

**Pass/Fail:**

| Pass | Fail |
|------|------|
| Impact analysis completed | Uncertain which docs need update |
| All affected docs updated | Doc updates incomplete |
| Docs staged in git | Docs not staged |
| CHANGELOG updated (if feat/fix) | CHANGELOG missing |

See `documentation-protocol` skill for full documentation rules.

---

### Gate 3: Code Cleanup — HIGH

**Purpose:** Remove temporary artifacts, debug code, sensitive data
**Time:** 1-2 minutes

**Check and clean:**

| Category | Find | Action |
|----------|------|--------|
| Temp files | `*.tmp`, `*.bak`, `*.swp`, `*~` | Delete |
| Debug statements | `console.log`, `print()`, `debugger`, `pdb.set_trace()` | Delete (keep `logger.*`) |
| Commented code | Large commented blocks | Delete (use git history) |
| TODO/FIXME | In production code | Move to bugs.md or session file |
| Hardcoded credentials | `password`, `api_key`, `secret` literals | Replace with `os.getenv()` / `process.env` |
| Test data | Mock data in production code | Move to tests/fixtures/ |

**Quick scan:**
```bash
grep -rn "console.log\|print(\|TODO\|FIXME\|debugger" --include="*.{js,jsx,ts,tsx,py}" .
grep -ri "password\|api_key\|secret" --include="*.{js,jsx,ts,tsx,py}" . | grep -v "test"
```

**Pass:** None of the above found in staged code.
**Fail:** Any found → clean up → re-check.

---

### Gate 4: Git Status Check — HIGH

**Purpose:** Verify correct files staged, no secrets
**Time:** 30 seconds

**Commands:**
```bash
git status
git diff --cached  # Review staged changes
```

**Verify:**

| SHOULD be staged | SHOULD NOT be staged |
|------------------|---------------------|
| All code files with changes | `.env` files |
| Updated documentation | `node_modules/` |
| CHANGELOG.md (if feat/fix) | `__pycache__/` |
| Session file (if session-based) | `.venv/` or `venv/` |
| Test files (if tests added) | `dist/` or `build/` |
| | `*.log`, secrets, `.DS_Store` |

**Wrong file staged?** `git reset HEAD path/to/file`
**Sensitive file staged?** `git reset HEAD .env && echo "/.env" >> .gitignore`

---

### Gate 5: Commit Message Format — MEDIUM

**Purpose:** Maintain clean, searchable git history
**Time:** 30 seconds

**Format:**
```
type(scope): description (YYYY-MM-DD HH:MM timezone)
```

**Types:** `feat` | `fix` | `docs` | `refactor` | `test` | `chore` | `style` | `perf` | `ci`

**Scope:** Project component (`api`, `ui`, `db`, `auth`, `parser`, `docs`, `config`, `tests`)

**Rules:**
- Imperative mood: "add" not "added"
- Lowercase start, no period at end
- Max 72 characters (first line)
- Timestamp mandatory with timezone
- Be specific: "fix login validation" not "fix bug"

**Examples:**
```
feat(api): add user profile endpoint (2026-02-06 14:30 CET)
fix(parser): resolve merged cell duplication bug (2026-02-06 15:00 CET)
docs(api): update authentication examples (2026-02-06 16:00 CET)
```

**Wrong format after commit?** `git commit --amend -m "corrected message"` (before push only)

---

### Gate 6: Testing (If Applicable) — MEDIUM

**Purpose:** Prevent regressions, verify functionality
**Time:** 30 seconds - 5 minutes

**When to run:** Code changes, features, bug fixes, refactoring, schema changes.
**When to skip (PM approval needed):** Docs-only, styling-only, config-only changes.

**Commands:**
```bash
# Backend
cd {project.paths.backend} && pytest tests/ -v --cov

# Frontend
cd {project.paths.frontend} && npm test
```

**Requirements:**

| Scenario | Requirement |
|----------|-------------|
| Any code change | All existing tests pass (100% pass rate) |
| New feature | Add unit + integration tests, >80% coverage for new code |
| Bug fix | Add regression test (reproduces bug, passes after fix) |
| Flaky tests | Re-run 3x, still flaky → document + create bug ticket |

**If tests fail:** Run with verbose (`pytest -vv`), identify failing test, fix code or fix test (document why), re-run. Do NOT commit failing tests without PM approval.

---

## Common Issues

| Problem | Gate | Solution |
|---------|------|----------|
| Frontend won't start | 1 | Check imports, run `npm install` |
| Don't know which docs to update | 2 | Use impact table above, escalate to PM |
| Tests failing | 6 | `pytest -vv`, identify issue, fix code or test |
| Wrong commit message | 5 | `git commit --amend` before push |
| Staged .env file | 4 | `git reset HEAD .env && echo "/.env" >> .gitignore` |
| Flaky tests | 6 | Re-run 3x, still flaky → bug ticket |
| Port already in use | 1 | Kill process: `pkill -f uvicorn` / `pkill -f node` |

---

## Configuration

From `.claude/project.json`:
```json
{
  "paths": {
    "workspace": "workspace/",
    "docs": "docs/",
    "frontend": "frontend/",
    "backend": "backend/"
  },
  "tech_stack": {
    "frontend": "React + TypeScript",
    "backend": "FastAPI + Python"
  },
  "quality_gates": {
    "test_coverage_threshold": 80,
    "skip_gates": []
  }
}
```

---

## Integration

| Skill | How |
|-------|-----|
| agent-core | Absolute Rule #0.2: "Quality gates before EVERY commit" |
| session-management | Gate checklist in session files, track metrics |
| git-workflow | Gate 5 enforces commit message format |
| documentation-protocol | Gate 2 references full documentation protocol |
| testing-workflow | Gate 6 integrates test requirements, Playwright UI testing details |
| debugging | Test failures in Gate 1/6 → use debugging skill (3 modes) |

---

**Version:** 4.0.0
**Last Updated:** 2026-02-11
