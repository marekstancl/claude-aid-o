# AID Retry Engine

Version: 1.0.0 — Gate failure analysis, fix-agent dispatch, retry loop, escalation.

**Purpose:** When a quality gate fails, this skill defines how to analyze the failure,
dispatch a fix agent, re-run the gate, and escalate if retries are exhausted.

**Called by:** `skills/gates-engine.md` (when `next_action: "gate_retry"`)
and `/run-epic` (State 8: GATE_RETRY).

---

## 1. Retry Decision Protocol

When a gate reports `status: "fail"`:

```
1. READ retry config from gates.yaml:
   retry:
     max_attempts: 3       # default
     backoff:
       strategy: "fixed"   # or "exponential"
       delay_seconds: 5    # wait between retries
     on_failure: "escalate"

2. READ current attempt count from gates_report.json → gate.attempts[]

3. DECIDE:
   IF len(attempts) < max_attempts:
     → Proceed to FAILURE ANALYSIS (Section 2)
   IF len(attempts) >= max_attempts:
     → Proceed to ESCALATION (Section 5)
```

---

## 2. Failure Analysis Protocol

Before dispatching a fix agent, analyze the gate output to classify the failure
and provide actionable context.

### 2.1 tests_pass Failure

```
Parse test output (pytest format):

1. Extract failing test info:
   - Test names (e.g., test_user_login, test_api_auth)
   - File paths (e.g., tests/test_auth.py::test_user_login)
   - Error type: AssertionError, ImportError, AttributeError, TypeError, TimeoutError

2. Classify failure:
   | Pattern | Classification | Likely fix |
   |---------|---------------|------------|
   | AssertionError | Logic error | Fix assertion or implementation |
   | ImportError / ModuleNotFoundError | Missing dependency | Fix import or install |
   | AttributeError | API mismatch | Fix attribute/method reference |
   | TypeError | Type mismatch | Fix function signature or call |
   | TimeoutError | Performance | Optimize or increase timeout |
   | fixture not found | Test setup | Fix fixture definition |

3. Extract affected files from stack trace
4. Determine scope: are the failing files within allowed_paths?
```

### 2.2 lint_pass Failure

```
Parse linter output (ruff format):

1. Extract violations:
   - File:line:column rule_code message
   - Example: "api/routes.py:42:1 F401 'os' imported but unused"

2. Classify:
   | Rule prefix | Classification | Likely fix |
   |-------------|---------------|------------|
   | F4xx | Unused imports | Remove import |
   | E1xx-E5xx | Style/formatting | Auto-fixable (ruff format) |
   | W | Warnings | Usually auto-fixable |
   | C9xx | Complexity | Refactor (may need escalation) |
   | S | Security (via bandit rules) | Fix security issue |

3. Group violations by file
4. Note: many lint issues are auto-fixable with `ruff check --fix .`
```

### 2.3 security_scan_pass Failure

```
Parse security scanner output (bandit format):

1. Extract findings:
   - Severity: HIGH, MEDIUM, LOW
   - Confidence: HIGH, MEDIUM, LOW
   - File:line
   - Issue type (e.g., B105 hardcoded_password, B301 pickle_usage)

2. Classify:
   | Issue type | Auto-fixable? | Approach |
   |-----------|---------------|----------|
   | Hardcoded password/secret | Yes | Move to env var |
   | SQL injection | Maybe | Use parameterized queries |
   | Pickle usage | Yes | Use json/yaml instead |
   | Insecure hash (MD5/SHA1) | Yes | Use SHA256+ |
   | Subprocess shell=True | Yes | Use shell=False + list args |
   | Temp file issues | Yes | Use tempfile module |

3. Determine if fix requires architectural change (→ escalation) or local fix
```

### 2.4 docs_updated Failure

```
Analyze what API changes lack documentation:

1. Read the gate evaluation log from gates/{gate_name}.txt
2. Identify:
   - Which files changed public API
   - What kind of change (new endpoint, modified schema, removed field)
   - Which docs files should be updated

3. Generate doc update plan:
   - CHANGELOG.md entry
   - API docs update (if applicable)
   - README update (if applicable)
```

### 2.5 type_check Failure (TypeScript)

```
Parse TypeScript compiler output:

1. Extract errors:
   - File:line:col - error TS{code}: message
   - Example: "src/App.tsx(42,5): error TS2322: Type 'string' is not assignable to type 'number'"

2. Classify:
   | Error code range | Classification |
   |-----------------|---------------|
   | TS2300-2399 | Type mismatch |
   | TS2500-2599 | Missing declaration |
   | TS1000-1099 | Syntax error |
   | TS7000-7099 | Implicit any |

3. Group by file
```

### 2.6 build_pass Failure

```
Parse build output (npm/vite/webpack):

1. Identify error type:
   - Compilation error (syntax, missing module)
   - Bundle error (circular dependency, missing asset)
   - Config error (invalid vite/webpack config)

2. Extract:
   - Error message
   - File path
   - Suggested fix (if provided by bundler)
```

---

## 3. Fix Agent Dispatch Protocol

After failure analysis, dispatch the `gate-fixer` agent to attempt a fix.

### 3.1 Agent Selection

Select the agent role for the fix based on gate type:

| Gate | Primary agent | Fallback |
|------|--------------|----------|
| `tests_pass` | `gate-fixer` (with QA context) | Original step's role agent |
| `lint_pass` | `gate-fixer` (auto-fix mode) | Original step's role agent |
| `security_scan_pass` | `gate-fixer` (with security context) | Security agent (Session 4) |
| `docs_updated` | `gate-fixer` (with docs context) | Docs-writer agent (Session 4) |
| `type_check` | `gate-fixer` (with TS context) | Frontend agent (Session 4) |
| `build_pass` | `gate-fixer` (with build context) | Frontend/backend agent |

> **Note:** Until Session 4 delivers role-specific agents, `gate-fixer` handles all fixes.

### 3.2 Fix Prompt Construction

Build the prompt for the fix agent:

```markdown
# GATE FIX REQUEST

## Context
- **EPIC:** {epic_id}
- **Run:** {run_id}
- **Gate:** {gate_name}
- **Attempt:** {N} of {max_attempts}

## Failure Details
- **Command:** `{gate command}`
- **Pass criteria:** {pass_criteria}
- **Exit code:** {exit_code}
- **Duration:** {duration}s

## Failure Output
```
{full gate output — truncated to last 200 lines if very long}
```

## Failure Analysis
- **Classification:** {failure classification from Section 2}
- **Affected files:** {list}
- **Likely root cause:** {analysis summary}
- **Suggested approach:** {from classification table}

## Your Task
Fix the issue so that the gate command passes. The gate will be re-run
after your fix.

## Constraints
- **Allowed paths:** {allowed_paths from plan step}
- **Forbidden paths:** {forbidden_paths from plan step}
- Minimal changes — fix the gate, do not refactor unrelated code
- Do NOT disable, skip, or suppress the check:
  - No `# noqa`, `# type: ignore` (unless truly correct)
  - No `@pytest.mark.skip` without documented reason
  - No removing failing tests
  - No lowering security thresholds
- If you cannot fix it, explain why clearly

## Previous Attempts
{For attempt > 1, list what was tried before and why it failed:}
- Attempt 1: {description of fix} → {outcome}
- Attempt 2: {description of fix} → {outcome}
```

### 3.3 Dispatch

```
1. DISPATCH fix agent:
   → Task(subagent_type="general-purpose", prompt="{fix prompt}")
   → The agent reads agents/gate-fixer.md as its role definition

2. COLLECT output:
   → Expect gate_fix_result YAML block in output
   → Parse: status (fixed|partial|unable), changes, explanation

3. STORE fix evidence:
   → Write to: evidence/{epic_id}/{run_id}/gates/retry_{gate_name}_{attempt}.md
   → Format:
     ```markdown
     # Gate Fix: {gate_name} — Attempt {N}

     ## Agent Output
     {agent's full response}

     ## Fix Result
     - Status: {fixed|partial|unable}
     - Changes: {list of files modified}
     - Explanation: {root cause and fix description}
     ```

4. LOG to stage_log.jsonl:
   → {"state": "GATE_RETRY", "action": "fix_dispatched",
      "details": "gate-fixer for {gate_name}, attempt {N}"}
```

---

## 4. Re-run Protocol

After the fix agent completes:

```
1. VERIFY changes were made:
   → Run `git diff --stat` to check for modifications
   → If NO changes:
     - Log: "Fix agent produced no changes"
     - Count as failed attempt
     - Increment attempt counter
     - Loop back to Section 1 (Retry Decision)

2. IF changes were made:
   a. Re-run ONLY the failed gate (not all gates)
      → Use same execution protocol from gates-engine.md Section 2
      → Store output to same gate file (overwrite)

   b. IF gate now passes:
      → Update gates_report.json:
        - Add new attempt with status: "pass"
        - Update gate status to "pass"
        - Update summary counts
        - Recalculate overall status
      → Transition: back to GATES state (re-check ALL gates)
        Why? The fix might have broken another gate.

   c. IF gate still fails:
      → Update gates_report.json:
        - Add new attempt with status: "fail" and fix_applied description
      → Increment attempt counter
      → Loop back to Section 1 (Retry Decision)

3. APPEND to stage_log.jsonl:
   → {"state": "GATE_RETRY", "action": "gate_rerun",
      "details": "{gate_name} attempt {N}: {pass|fail}"}
```

### 4.1 Full Re-check After Fix

When a gate fix succeeds, ALL gates must be re-checked:

```
Why: A lint fix might break tests. A test fix might introduce a security issue.

Flow:
  gate_retry → fix → single gate passes
    → Return to GATES state
    → Re-execute ALL required gates
    → If all pass → proceed_to_pm_approval
    → If different gate fails → new retry cycle for that gate
```

---

## 5. Escalation Protocol

When `attempts >= max_attempts` for any required gate:

### 5.1 Compile Escalation Report

```
Gather:
1. Gate name, command, pass_criteria
2. All attempt outputs (from gates_report.json)
3. All fix attempts (from retry evidence files)
4. Other gates' status (context)
5. Remaining budget
```

### 5.2 Present to PM

```
GATE ESCALATION
====================================
EPIC: {epic_id}
Gate: {gate_name}
Attempts: {max_attempts}/{max_attempts} exhausted

Gate command: {command}
Pass criteria: {pass_criteria}

Last failure output:
{last attempt output — truncated to key error}

Fix attempts:
1. {attempt 1}: {fix description} → {outcome}
2. {attempt 2}: {fix description} → {outcome}
3. {attempt 3}: {fix description} → {outcome}

Other gates: {N} passed, {M} skipped

Options:
A) Skip this gate — proceed with warning (gate marked as skipped_by_pm)
B) Manual fix — you provide guidance, I'll retry (resets attempt counter)
C) Abort EPIC run — stop all execution

Recommendation: {based on context — e.g., "B" if the failure seems fixable
with human insight, "A" if it's a non-critical issue}
```

### 5.3 Handle PM Response

```
OPTION A — Skip gate:
  1. Update gates_report.json: gate status → "skipped_by_pm"
  2. Add PM decision to attempts: {status: "skipped_by_pm", pm_reason: "{reason}"}
  3. Log to stage_log.jsonl
  4. Recalculate overall → if no other failures → "pass"
  5. Save pm_decision.json
  6. Transition: → proceed (GATES re-check or PM_APPROVAL)

OPTION B — Manual fix with PM guidance:
  1. Save PM guidance to pm_decision.json
  2. Reset attempt counter for this gate to 0
  3. Build new fix prompt with PM's guidance prepended:
     "## PM Guidance\n{PM's instructions}\n\n{standard fix prompt}"
  4. Dispatch fix agent with enhanced prompt
  5. Re-run gate
  6. If still fails → new escalation cycle (new 3 attempts)

OPTION C — Abort:
  1. Save pm_decision.json with decision: "abort"
  2. Log to stage_log.jsonl
  3. Transition: → DONE (status: aborted, reason: "PM aborted after gate failure")
```

### 5.4 Escalation Evidence

Save to `pm_decision.json`:

```json
{
  "timestamp": "{ISO 8601}",
  "trigger": "gate_failure_max_retries",
  "gate": "{gate_name}",
  "attempts_exhausted": {max_attempts},
  "options_presented": ["skip", "manual_fix", "abort"],
  "pm_decision": "{chosen option}",
  "pm_feedback": "{guidance text if option B}",
  "pm_reason": "{reason for skip if option A}"
}
```

---

## 6. Multiple Gate Failures

When multiple required gates fail in the same run:

```
1. Process each failed gate independently
2. Start with the first failed gate (in gates.yaml order)
3. After fixing one gate → re-check ALL gates (Section 4.1)
4. If re-check reveals a different failure → retry that gate
5. If multiple gates fail simultaneously:
   - Retry them sequentially (not in parallel)
   - Each fix might resolve multiple gates
   - Track attempt counts per gate independently

Example:
  tests_pass: FAIL (attempt 1)
  lint_pass: FAIL (attempt 1)

  → Fix tests_pass first
  → Re-run all gates
  → If lint_pass also fixed by test fix → done
  → If lint_pass still fails → retry lint_pass
```

---

## 7. Backoff Strategy

Between retry attempts, apply the configured backoff:

```
strategy: "fixed"
  → Wait delay_seconds between each attempt
  → Attempt 1 → wait 5s → Attempt 2 → wait 5s → Attempt 3

strategy: "exponential"
  → delay_seconds * 2^(attempt-1)
  → Attempt 1 → wait 5s → Attempt 2 → wait 10s → Attempt 3 → wait 20s
```

> **Note:** In the current Claude Code environment, "waiting" means simply
> pausing before the next action. There is no sleep mechanism — the delay
> is advisory (documented for future Slack/async implementation in Session 6).

---

## MUST Rules

1. **ALWAYS analyze failure before dispatching fix** — never dispatch blind
2. **ALWAYS include previous attempts in fix prompt** — avoid repeating same fix
3. **ALWAYS re-check ALL gates after a fix** — fixes can cause regressions
4. **NEVER exceed max_attempts without escalation** — PM must decide
5. **NEVER let fix agent disable/skip gates** — enforce via constraints in prompt
6. **ALWAYS store retry evidence** — each attempt creates a file
7. **ALWAYS track attempts per gate independently** — gate A's retry count doesn't affect gate B
8. **ALWAYS present escalation with options** — never just say "failed"
