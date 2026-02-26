---
sidebar_position: 11
title: "Gates Engine"
description: "Parses gates.yaml, executes command-based and rule-based quality gates after EPIC steps complete, and generates a structured gates_report.json with retry history."
---

# Gates Engine

The gates engine reads the project's `gates.yaml` configuration, classifies each gate as required or conditional, executes command and rule gates, and produces a structured `gates_report.json` with pass/fail status and retry history. It runs at State 7 (GATES) in the Controller state machine after EPIC steps complete.

## Purpose

Quality gates are the automated checkpoint between agent work and acceptance. Without a disciplined gates layer, agents can produce syntactically correct code that fails tests, introduces lint errors, or leaves documentation unupdated. The gates engine makes gate execution consistent, configurable, and auditable.

This skill is distinct from `quality-gates.md`, which defines the pre-commit 6-gate protocol for individual agents. The gates engine runs post-step gates defined by the project in `gates.yaml`.

## When Used

- Triggered by the Controller at GATES state after each EPIC step (or group of steps) completes
- Called from the EPIC orchestration state machine after PHASE_CHECK passes
- Gate failures trigger the `retry-engine` skill (dispatch gate-fixer, re-run, escalate at max attempts)
- Referenced by `analytics` when reporting gate efficiency metrics

## Key Concepts

### Gate Types

**Command gates** execute a shell command and check the exit code or output:

```yaml
tests_pass:
  description: "All tests must pass"
  required: true
  command: "pytest -q --tb=short"
  timeout_seconds: 300
  pass_criteria: "exit code 0"
```

**Rule gates** evaluate a logical condition through inspection rather than a shell command:

```yaml
docs_updated:
  description: "Documentation must be updated if API changes"
  required: false
  rule: "project.docs.path or CHANGELOG.md must be updated if code changes affect public API"
  pass_criteria: "manual or automated check that relevant docs are current"
```

### Gate Classification

Gates are classified into three categories during parsing:

| Category | Condition | Behavior |
|---|---|---|
| **Required** | `required: true`, no `when` clause | Must execute, must pass — failure blocks the pipeline |
| **Conditional** | `required: false`, has `when` clause | Evaluate condition first; execute only if condition met; failure is a warning (non-blocking) |
| **Skipped** | Conditional gate where `when` is false | Status: SKIP, not executed |

### Gates Report

After all gates run, the engine writes `gates_report.json` to the evidence directory:

```json
{
  "epic_id": "E-20260217-api-v2",
  "run_id": "20260217T140000Z",
  "gates": [
    {
      "name": "tests_pass",
      "type": "command",
      "required": true,
      "status": "pass",
      "attempts": [
        {"attempt": 1, "exit_code": 0, "duration_seconds": 12, "output": "..."}
      ]
    },
    {
      "name": "lint_pass",
      "type": "command",
      "required": true,
      "status": "pass",
      "attempts": [
        {"attempt": 1, "exit_code": 1, "output": "..."},
        {"attempt": 2, "exit_code": 0, "output": "..."}
      ]
    }
  ],
  "overall": "pass",
  "total_gates": 4,
  "passed": 4,
  "failed": 0,
  "skipped": 1,
  "warnings": 0
}
```

### Retry Integration

When a required gate fails, the engine sets `next_action: "gate_retry"` in the report. The Controller transitions to GATE_RETRY state and invokes the `retry-engine` skill, which dispatches the gate-fixer agent and re-runs the gate. After `max_attempts` (default 3) are exhausted without a pass, the retry engine escalates to the PM.

## How It Works

1. Read `.aid-o/03-config/policies/gates.yaml`
2. Parse and classify all gates (required, conditional, skipped)
3. For each required gate: execute and record result in `gates_report.json`
4. For each conditional gate: evaluate `when` condition, then execute if met
5. Write `gates_report.json` to evidence directory
6. Evaluate overall status:
   - All required gates pass → `overall: "pass"` → CURATOR_RESOLVE state
   - Any required gate fails → `overall: "fail"` → GATE_RETRY state

Gate execution for command gates uses the Bash tool with the configured timeout. Rule gates are evaluated through inspection or agent judgment. Each attempt is appended to the gate's `attempts[]` array.

## Configuration

Gates are defined in `.aid-o/03-config/policies/gates.yaml`. The default configuration (installed by `/aid-init`) includes gates for test pass, lint pass, docs updated, and optional security scan. Project owners customize this file to match their tech stack and quality requirements.

Retry configuration is also in `gates.yaml`:

```yaml
retry:
  max_attempts: 3
  backoff:
    strategy: "fixed"
    delay_seconds: 5
  on_failure: "escalate"
```

## Related

- [Retry Engine](../skills/retry-engine)
- [Epic Orchestration](../skills/epic-orchestration)
- [Quality Gates](../skills/quality-gates)
- [Analytics](../skills/analytics)
