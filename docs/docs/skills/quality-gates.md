---
sidebar_position: 4
title: "Quality Gates"
description: "Bash-integrated gate reference: 6 quality gates, aid-run-gates.sh execution, per-project configuration."
---

# Quality Gates

The quality gates skill defines the 6 gates that run before every EPIC commit. In v2, gates are executed by `aid-run-gates.sh` (bash script), not by the LLM directly. Gate configuration lives in `.aid-o/config/execution.yaml`.

## When Gates Run

```
Code ready -> FSM: GATES -> aid-run-gates.sh run-all -> ALL PASS -> FSM: DONE
                                                      -> REQUIRED FAIL -> FSM: ESCALATION
```

## The 6 Gates

| Gate | Severity | Required | Max Retries | Purpose |
|------|----------|----------|-------------|---------|
| `tests_pass` | CRITICAL | Yes | 2 | Verify no regressions |
| `lint_pass` | CRITICAL | Yes | 0 | Enforce code style |
| `build_pass` | CRITICAL | Yes | 1 | Verify project builds |
| `security_scan` | HIGH | Yes | 2 | Detect vulnerabilities |
| `docs_updated` | MEDIUM | No | 1 | Keep docs synchronized (advisory) |
| `scope_check` | HIGH | Yes | 0 | Verify commit matches EPIC scope |

### Gate Details

**tests_pass** -- runs configured test command. Pass: exit 0. Fail: ESCALATION if retries exhausted.

**lint_pass** -- runs configured lint command. No retry loop (auto-fix formatters run in pre-commit).

**build_pass** -- runs configured build command. One retry allowed.

**security_scan** -- runs `npm audit` / `bandit` or configured scanner. Detects high/critical vulnerabilities.

**docs_updated** -- advisory gate. Failure logged as WARNING, does not block DONE state.

**scope_check** -- runs `scripts/gates/scope-check.sh`. Compares `git diff --cached --name-only` against EPIC scope. Deterministic result, no retries.

## Gate Execution

```bash
# Run all gates
aid-run-gates.sh run-all .aid-o/config/execution.yaml {epic_id} {run_id}

# Run single gate (debugging)
aid-run-gates.sh run-gate tests_pass .aid-o/config/execution.yaml {epic_id} {run_id}
```

Each gate execution:
1. Reads gate config from `execution.yaml`
2. Runs command in subprocess
3. Captures stdout/stderr + exit code
4. Appends structured entry to `timeline.jsonl`
5. Returns pass (exit 0) or fail (exit != 0)

## Configuration

Per-project in `.aid-o/config/execution.yaml`:

```yaml
gates:
  tests_pass:
    command: "pytest tests/ -v"
    required: true
    max_retries: 2
  lint_pass:
    command: "ruff check . && npx eslint src/"
    required: true
    max_retries: 0
  build_pass:
    command: "npx vite build"
    required: true
    max_retries: 1
  security_scan:
    command: "npm audit --audit-level=high"
    required: true
    max_retries: 2
  docs_updated:
    command: "bash scripts/gates/docs-check.sh"
    required: false
    max_retries: 1
  scope_check:
    command: "bash scripts/gates/scope-check.sh"
    required: true
    max_retries: 0
```

## Integration

| Component | Role |
|-----------|------|
| `aid-run-gates.sh` | Gate executor (runs commands, logs results) |
| `execution.yaml` | Per-project gate config |
| [Pipeline](./pipeline) GATES state | FSM state definition and transitions |
| `timeline.jsonl` | Structured gate result log |
| [Gate Fixer](../agents/gate-fixer) | Fixes gate failures when retries remain |

## Related

- [Pipeline](./pipeline) -- GATES state (section 5)
- [Gate Fixer Agent](../agents/gate-fixer)
- [Run Management](./run-management) -- evidence structure
