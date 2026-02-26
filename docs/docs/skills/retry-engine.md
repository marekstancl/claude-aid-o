---
sidebar_position: 19
title: "Retry Engine"
description: "When a quality gate fails, analyzes the failure, dispatches the gate-fixer agent with targeted context, re-runs the gate, and escalates to PM if retries are exhausted."
---

# Retry Engine

The retry engine handles gate failures by analyzing the failure output, dispatching the gate-fixer agent with targeted context about what went wrong, re-running the gate, and escalating to the PM if the maximum retry count is reached. It is called from the GATE_RETRY state in the Controller state machine.

## Purpose

Not every gate failure is a signal to stop and ask for human help. Lint errors are often auto-fixable with a single command. Import errors point to a specific missing line. Test failures have a stack trace that identifies the exact file and line. The retry engine extracts this specific, actionable context and provides it to the gate-fixer agent — which fixes the problem much faster than a general re-dispatch would.

## When Used

- Called by the `gates-engine` skill when a gate returns `next_action: "gate_retry"`
- Invoked by the Controller during GATE_RETRY state (State 8 in the state machine)
- In auto-mode, gate failures after all retries are exhausted trigger escalation E4

## Key Concepts

### Retry Decision Protocol

When a gate reports `status: "fail"`:

1. Read retry configuration from `gates.yaml` (default: `max_attempts: 3`, backoff strategy: `fixed`, delay: 5 seconds)
2. Read the current attempt count from `gates_report.json` for this gate
3. If `attempts < max_attempts`: proceed to failure analysis and dispatch gate-fixer
4. If `attempts >= max_attempts`: proceed to escalation

### Failure Analysis by Gate Type

The retry engine analyzes failure output before dispatching a fix agent. The analysis is specific to the gate type:

**tests_pass failure** — parses pytest output to extract: failing test names and file paths, error type (AssertionError, ImportError, AttributeError, TypeError, TimeoutError), and stack trace to identify affected files. Classifies the error and determines whether the affected files are within the agent's `allowed_paths`.

**lint_pass failure** — parses ruff output to extract violations by file:line:column with rule codes. Classifies by rule prefix: F4xx (unused imports — remove), E1xx-E5xx (style — auto-fixable), S (security — must fix), C9xx (complexity — may need escalation). Notes which violations are auto-fixable with `ruff check --fix`.

**security_scan_pass failure** — parses bandit output to extract findings by severity (HIGH, MEDIUM, LOW) and confidence. Classifies by issue type: hardcoded secrets (move to env var), SQL injection (use parameterized queries), pickle usage (evaluate risk).

**docs_updated failure** — identifies which documentation files are missing or outdated based on the changed code files.

### Gate-Fixer Dispatch

The gate-fixer agent receives a structured prompt that includes:
- Gate name and type
- Failure output (parsed, not raw)
- Classified error type and recommended fix approach
- Specific file paths to examine
- Whether auto-fix commands are available (e.g., `ruff check --fix`)

The gate-fixer applies fixes within the current working tree and reports what was changed.

### Post-Fix Re-Run

After the gate-fixer reports completion:
1. Re-run the failing gate using the same command and configuration
2. Record the result as a new attempt in `gates_report.json`
3. If the gate passes: clear the failure, update `overall` status, return to GATES state
4. If the gate fails again: increment attempt count and repeat the cycle until max attempts

### Escalation

When `attempts >= max_attempts` and the gate is still failing:
- In auto-mode: trigger escalation E4 (gate fails after 3 retries); PM receives the full retry history including what was tried and why it failed
- In manual mode: present the failure history to PM with options to fix manually, skip the gate, or abort

## How It Works

The retry loop is:
```
Gate fails
→ retry-engine analyzes failure
→ dispatches gate-fixer with context
→ gate-fixer applies fix
→ re-run gate
→ PASS: done
→ FAIL: retry (up to max_attempts)
→ max reached: escalate to PM
```

Each attempt is recorded in `gates_report.json` with timestamp, exit code, output excerpt, and the fix applied. This produces a complete audit trail of what was tried before the PM is asked for help.

## Configuration

Retry configuration in `gates.yaml`:

```yaml
retry:
  max_attempts: 3
  backoff:
    strategy: "fixed"    # or "exponential"
    delay_seconds: 5
  on_failure: "escalate"
```

The default of 3 attempts balances thoroughness with avoiding infinite loops. For flaky tests or intermittent failures, `max_attempts` can be raised per gate.

## Related

- [Gates Engine](../skills/gates-engine)
- [Epic Orchestration](../skills/epic-orchestration)
- [Auto Escalation](../skills/auto-escalation)
