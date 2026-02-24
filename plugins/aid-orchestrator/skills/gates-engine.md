# AID Gates Engine

**Purpose:** Parse `gates.yaml`, execute quality gates (command-based and rule-based),
generate structured `gates_report.json` with retry history, store evidence.

> **Not to be confused with** `quality-gates.md` — the pre-commit 6-gate protocol.
> This engine runs **after EPIC steps complete** (State 7: GATES in the Controller state machine).

---

## 1. Gates YAML Parsing Protocol

Read `.aid-o/03-config/policies/gates.yaml` and parse:

### 1.1 Gate Definition Structure

Each gate has these fields:

| Field | Required | Description |
|-------|----------|-------------|
| `description` | yes | Human-readable purpose |
| `required` | yes | `true` = blocking, `false` = warning only |
| `command` | if command gate | Shell command to execute |
| `rule` | if rule gate | Logical rule to evaluate |
| `timeout_seconds` | if command gate | Max execution time |
| `pass_criteria` | yes | What constitutes a pass |
| `when` | no | Condition for conditional gates |

### 1.2 Gate Types

**Command gate** — has a `command` field. Execute via Bash tool.
```yaml
tests_pass:
  command: "pytest -q --tb=short"
  timeout_seconds: 300
  pass_criteria: "exit code 0"
```

**Rule gate** — has a `rule` field. Evaluate via logic/inspection.
```yaml
docs_updated:
  rule: "{project.docs.path} or CHANGELOG.md must be updated if code changes affect public API"
  pass_criteria: "manual or automated check that relevant docs are current"
```

### 1.3 Gate Classification

Parse all gates and classify into three categories:

```
REQUIRED gates   — required: true, no `when` clause
                   → MUST execute, MUST pass
CONDITIONAL gates — required: false, has `when` clause
                   → Evaluate condition first, execute only if condition met
                   → If condition not met → status: SKIP
                   → If condition met but fails → WARNING (non-blocking)
SKIPPED gates    — conditional gate where `when` condition is false
                   → status: SKIP, not executed
```

### 1.4 Evaluating `when` Conditions

For each conditional gate with a `when` clause:

| `when` value | Evaluation method |
|-------------|-------------------|
| `"frontend files changed"` | Run `git diff --name-only HEAD~{step_count}` and check for files in frontend paths (e.g., `*.ts`, `*.tsx`, `*.js`, `*.jsx`, `*.vue`, `*.svelte`, `src/frontend/`, `frontend/`, `client/`, `app/`) |
| `"backend files changed"` | Check for `*.py`, `*.go`, `*.rs`, `*.java`, `src/backend/`, `backend/`, `server/`, `api/` |
| `"database files changed"` | Check for `*.sql`, `migrations/`, `alembic/` |

If the `when` value doesn't match known patterns, **default to executing the gate**
(conservative — better to run an extra gate than miss a problem).

---

## 2. Gate Execution Protocol

Execute gates in the order they appear in `gates.yaml`.

### 2.1 Command Gate Execution

```
For each command gate:

1. LOG state transition:
   → Append to stage_log.jsonl:
     {"state": "GATES", "action": "gate_start", "details": "Running gate: {name}"}

2. EXECUTE command:
   → Use Bash tool with timeout from gates.yaml
   → Capture: exit_code, stdout, stderr (combined)
   → If timeout exceeded → status: "error", output: "Timed out after {N}s"

3. EVALUATE pass_criteria:
   → "exit code 0": pass if exit_code == 0
   → "exit code 0, no HIGH or CRITICAL findings":
      pass if exit_code == 0 AND output does not contain "HIGH" or "CRITICAL"
   → If pass_criteria is ambiguous, default to exit_code == 0

4. STORE output:
   → Write raw output to: evidence/{epic_id}/{run_id}/gates/{gate_name}.txt
   → Format:
     ```
     Gate: {name}
     Command: {command}
     Timestamp: {ISO 8601}
     Exit code: {code}
     Duration: {seconds}s

     --- OUTPUT ---
     {stdout + stderr}
     ```

5. RECORD result in gates_report.json entry (see Section 3)

6. LOG completion:
   → Append to stage_log.jsonl:
     {"state": "GATES", "action": "gate_complete",
      "details": "{name}: {status}", "result": "{pass|fail|error}"}
```

### 2.2 Rule Gate Execution

```
For each rule gate:

1. LOG: "Evaluating rule gate: {name}"

2. EVALUATE based on rule content:

   "docs_updated" rule:
   a. Run `git diff --name-only HEAD~{step_count}` to find changed files
   b. Check if any changed files affect public API:
      - New/modified endpoint files (routes, controllers, handlers)
      - New/modified model files (schemas, entities)
      - New/modified config that changes behavior
   c. If public API changed:
      - Check if `{project.docs.path}` or CHANGELOG.md is also in the changed files
      - If docs updated → PASS
      - If docs NOT updated → FAIL with justification:
        "API changes detected in {files} but {project.docs.path} and CHANGELOG.md not updated"
   d. If no public API changes → PASS with justification:
      "No public API changes detected"

   "scope_check" rule:
   a. Read plan step's allowed_paths and forbidden_paths
   b. Run `git diff --name-only` to find modified files
   c. Check each modified file against allowed/forbidden lists
   d. Any file in forbidden_paths → FAIL
   e. All files in allowed_paths → PASS

   Unknown rules:
   → FAIL with justification: "Unknown rule type — cannot auto-evaluate.
     Manual review required."

3. STORE evaluation log to: evidence/{epic_id}/{run_id}/gates/{gate_name}.txt
   → Format:
     ```
     Gate: {name}
     Type: rule
     Rule: {rule text}
     Timestamp: {ISO 8601}

     --- EVALUATION ---
     {justification and findings}

     Result: {PASS|FAIL}
     ```

4. RECORD result in gates_report.json entry
```

### 2.3 Conditional Gate Handling

```
For each gate with a `when` clause:

1. EVALUATE condition (per Section 1.4)
2. If condition FALSE:
   → status: "skip"
   → justification: "Condition not met: {when clause}"
   → Do NOT execute the gate command
3. If condition TRUE:
   → Execute normally (per 2.1 or 2.2)
   → But remember: required: false → failure is WARNING, not blocking
```

---

## 3. Gates Report Generation

After all gates execute, generate `gates_report.json`:

```json
{
  "epic_id": "{epic_id}",
  "run_id": "{run_id}",
  "timestamp": "{ISO 8601}",
  "gates_config": "gates.yaml",
  "gates": [
    {
      "name": "tests_pass",
      "type": "command",
      "required": true,
      "status": "pass",
      "command": "pytest -q --tb=short",
      "exit_code": 0,
      "output_file": "gates/tests_pass.txt",
      "output_summary": "45 passed in 3.2s",
      "duration_seconds": 3.2,
      "attempts": [
        {
          "attempt": 1,
          "timestamp": "{ISO 8601}",
          "status": "pass",
          "output_summary": "45 passed in 3.2s",
          "fix_applied": null
        }
      ]
    },
    {
      "name": "docs_updated",
      "type": "rule",
      "required": true,
      "status": "pass",
      "rule": "{project.docs.path} or CHANGELOG.md must be updated if public API changed",
      "justification": "No public API changes detected",
      "output_file": "gates/docs_updated.txt",
      "duration_seconds": 0.5,
      "attempts": [
        {
          "attempt": 1,
          "timestamp": "{ISO 8601}",
          "status": "pass",
          "output_summary": "No public API changes detected",
          "fix_applied": null
        }
      ]
    },
    {
      "name": "type_check",
      "type": "command",
      "required": false,
      "status": "skip",
      "justification": "Condition not met: frontend files changed",
      "attempts": []
    }
  ],
  "summary": {
    "total": 6,
    "passed": 4,
    "failed": 0,
    "skipped": 2,
    "errors": 0,
    "warnings": 0
  },
  "overall": "pass",
  "next_action": "proceed_to_pm_approval"
}
```

### 3.1 Status Values

| Status | Meaning |
|--------|---------|
| `pass` | Gate passed on this attempt |
| `fail` | Gate failed (required gate → blocking) |
| `skip` | Conditional gate — condition not met |
| `error` | Gate execution error (timeout, command not found) |
| `skipped_by_pm` | PM chose to skip during escalation |

### 3.2 Overall Status Calculation

```
IF any required gate has status "fail" or "error":
  → overall: "fail"
ELSE:
  → overall: "pass"

Note: conditional gates (required: false) do NOT affect overall status.
      skipped_by_pm gates do NOT affect overall status.
```

### 3.3 Next Action Determination

Apply decision logic from `decision-policies.yaml`:

```
IF overall == "pass":
  → next_action: "proceed_to_pm_approval"

IF overall == "fail":
  FOR each failed required gate:
    Read retry config from gates.yaml
    Count existing attempts in gates_report.json
    IF attempts < max_attempts:
      → next_action: "gate_retry"
    ELSE:
      → next_action: "escalation"
```

---

## 4. Evidence Storage

### 4.1 Directory Structure

```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/
  gates_report.json              # Structured report (created/updated per run)
  gates/
    tests_pass.txt               # Raw command output
    lint_pass.txt                # Raw command output
    security_scan_pass.txt       # Raw command output
    docs_updated.txt             # Rule evaluation log
    type_check.txt               # Conditional (only if ran)
    build_pass.txt               # Conditional (only if ran)
    retry_lint_pass_1.md         # Fix agent output (attempt 1)
    retry_lint_pass_2.md         # Fix agent output (attempt 2)
```

### 4.2 Evidence Rules

1. **Always overwrite** gate output files on re-run (latest output matters)
2. **Never delete** retry evidence — each attempt is preserved
3. **Append** to `gates_report.json` attempts array on retry
4. **Append** to `stage_log.jsonl` on every gate start/complete

---

## 5. Integration Points

### 5.1 Called From

| Caller | Mode | Notes |
|--------|------|-------|
| `/aid-run-epic` (GATES state) | Non-interactive | Follows protocol, decides automatically |
| `/aid-run-epic` (manual gate run) | Interactive | Shows progress, offers retry options |

### 5.2 Calls To

| Target | When |
|--------|------|
| `skills/retry-engine.md` | When a required gate fails and retries remain |
| `agents/gate-fixer.md` | Dispatched by retry-engine for fixes |
| `decision-policies.yaml` | For auto-decision logic |

### 5.3 Consumed By

| Consumer | What it reads |
|----------|--------------|
| `/aid-epic-status` | `gates_report.json` for display |
| `/aid-run-epic` PM_APPROVAL | Gate results for final summary |
| `/aid-run-epic` DONE | Gate results for final report |
| Auditor agent (Run 4) | Gate history for trend tracking |

---

## 6. Error Handling

| Error | Response |
|-------|----------|
| `gates.yaml` not found | FAIL with: "Gates config not found at .aid-o/03-config/policies/gates.yaml. Run /aid-init first." |
| Command not found (e.g., pytest not installed) | status: "error", output: "Command not found: {cmd}. Install the tool or update gates.yaml." |
| Timeout exceeded | status: "error", output: "Timed out after {N}s." |
| Evidence directory doesn't exist | Create it: `mkdir -p evidence/{epic_id}/{run_id}/gates/` |
| Permission denied on command | status: "error", output: "Permission denied. Check file permissions." |

---

## MUST Rules

1. **ALWAYS read gates.yaml before executing** — never hardcode gate definitions
2. **ALWAYS store evidence** — every gate run produces a file in `gates/`
3. **ALWAYS generate gates_report.json** — even if all gates pass on first try
4. **NEVER skip a required gate** — only PM can authorize skipping (via escalation)
5. **NEVER modify gates.yaml** during execution — it's a PM-owned config
6. **ALWAYS append to stage_log.jsonl** — every gate start and complete
7. **ALWAYS evaluate `when` conditions** before executing conditional gates
8. **NEVER treat conditional gate failure as blocking** — it's a warning
