# E2E Testing Playbook (Playwright)

## Mission

Browser-level verification of critical user flows. Screenshots as evidence.
This playbook is used by the QA agent when dispatched with role `e2e`.

## What to Test

1. **Critical user flows** -- login, main CRUD operations, navigation paths
2. **Visual rendering** -- pages load correctly, layout intact, no blank screens
3. **Form validation** -- required fields enforced, error messages display properly
4. **Responsive viewports** -- desktop (1280x720) + mobile (375x667) spot checks

## Playwright MCP Tools

Use these MCP tools for browser interactions:

| Tool | Purpose |
|------|---------|
| `playwright_navigate` | Load pages by URL |
| `playwright_screenshot` | Capture visual evidence |
| `playwright_click` | Click buttons, links, interactive elements |
| `playwright_fill` | Fill form fields |
| `playwright_evaluate` | Run JavaScript in browser context |

## Evidence Collection

All screenshots MUST be saved to the evidence directory:
```
evidence/{epic_id}/{run_id}/steps/{step_id}/screenshots/
```

Name screenshots descriptively:
- `01_login_page_loaded.png`
- `02_login_form_filled.png`
- `03_dashboard_after_login.png`
- `04_mobile_viewport_dashboard.png`

## Test Strategy

```
1. IDENTIFY critical flows from EPIC objective and frontend step outputs
2. PLAN 5-10 test scenarios (prioritize: auth > main CRUD > navigation > edge cases)
3. EXECUTE each scenario:
   a. Navigate to starting page
   b. Perform user actions (click, fill, submit)
   c. Verify expected outcome (page content, URL, visual state)
   d. Screenshot each significant state
4. REPORT results with pass/fail per scenario + screenshot references
```

## Constraints

- Do NOT write unit tests (QA agent handles those)
- Do NOT modify source code -- test files only (read-only + test evidence)
- Target 5-10 critical flows, not exhaustive coverage
- Each browser operation is slow (2-10s) -- minimize unnecessary navigation
- Do NOT install dependencies -- Playwright MCP handles browser automation
- If the application requires a running server, note it as a prerequisite
  in the output rather than attempting to start services

## Output Format

```yaml
e2e_result:
  step_id: "{step_id}"
  agent: "e2e"
  status: "completed|partial|blocked"
  scenarios_total: {N}
  scenarios_passed: {N}
  scenarios_failed: {N}
  screenshots: ["{path1}", "{path2}", ...]
  failures:
    - scenario: "{name}"
      expected: "{what should happen}"
      actual: "{what happened}"
      screenshot: "{path}"
  summary: "One paragraph describing E2E test results"
```
