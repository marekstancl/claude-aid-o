---
sidebar_position: 1
title: "gates.yaml"
description: "Reference for every field in gates.yaml — gate commands, pass criteria, retry configuration, and how to override gates for your tech stack."
---

# gates.yaml

**Location:** `.aid-o/03-config/policies/gates.yaml`

This file defines the quality gates that run after every EPIC step completes and before PM approval is requested. The gates engine reads this file at State 7 (GATES) in the Controller state machine, executes each gate, and writes a `gates_report.json` to the evidence directory.

All gates with `required: true` must pass for the EPIC to proceed. A failing required gate triggers the retry engine, which dispatches the gate-fixer agent and re-runs the gate up to `max_attempts` times before escalating to the PM.

---

## Full Default Configuration

The default file installed by `/aid-init` (source: `plugins/aid-orchestrator/defaults/policies/gates.yaml`):

```yaml
gates:
  tests_pass:
    description: "All tests pass (unit + integration)"
    required: true
    command: "pytest -q --tb=short"
    timeout_seconds: 300
    pass_criteria: "exit code 0"

  lint_pass:
    description: "Code passes linting and formatting checks"
    required: true
    command: "ruff check . && ruff format --check ."
    timeout_seconds: 120
    pass_criteria: "exit code 0"

  security_scan_pass:
    description: "No high/critical security findings"
    required: true
    command: "bandit -q -r . -ll"
    timeout_seconds: 180
    pass_criteria: "exit code 0, no HIGH or CRITICAL findings"

  docs_updated:
    description: "Documentation updated for all changed APIs/models"
    required: true
    rule: "{project.docs.path} or CHANGELOG.md must be updated if code changes affect public API"
    pass_criteria: "manual or automated check that relevant docs are current"

  type_check:
    description: "TypeScript type checking passes"
    required: false
    command: "npx tsc --noEmit"
    timeout_seconds: 120
    pass_criteria: "exit code 0"
    when: "frontend files changed"

  build_pass:
    description: "Frontend builds without errors"
    required: false
    command: "npm run build"
    timeout_seconds: 180
    pass_criteria: "exit code 0"
    when: "frontend files changed"

retry:
  max_attempts: 3
  backoff:
    strategy: "fixed"
    delay_seconds: 5
  on_failure: "escalate"

escalation:
  method: "inline"
  message_template: |
    GATE FAILURE — Escalation to PM
    Gate: {gate_name}
    EPIC: {epic_id}
    Attempts: {attempt_count}/{max_attempts}
    Last error: {last_error}
    Action needed: Review and decide (fix / skip / abort)

budget:
  max_llm_cost_per_epic_usd: 50
  warn_at_percentage: 80

evidence:
  store_gate_results: true
  store_command_output: true
  store_retry_history: true
  output_dir: "evidence/{epic_id}/{run_id}/gates/"
```

---

## Gates Section

The `gates` map defines each gate by a unique key. Each gate entry has the following fields.

### `description`

Human-readable description of what this gate checks. Appears in the gates report, escalation messages, and Slack notifications.

### `required`

`true` or `false`. Required gates must pass for the EPIC to proceed. A failed required gate blocks the pipeline, triggers the retry engine, and eventually escalates to the PM. Non-required gates are warnings — they are logged in the gates report but do not block progress.

### `command`

The shell command to execute. The gates engine runs this command using the Bash tool, captures exit code and stdout/stderr, and compares against `pass_criteria`. Any gate with a `command` field is a **command gate**.

If you omit `command` and provide `rule` instead, the gate becomes a **rule gate** evaluated by inspection rather than shell execution (see `docs_updated` as an example).

### `timeout_seconds`

Maximum time in seconds the command is allowed to run. If the command exceeds this limit, the gate is marked failed with a timeout error. Increase this value for slow test suites or large codebases.

### `pass_criteria`

Human-readable description of what constitutes a pass. For command gates, this is typically `"exit code 0"`. The gates engine uses this field in the evidence report and escalation messages.

### `rule`

Present on rule gates (no `command`). Describes the logical condition to evaluate. Rule gates are checked through agent inspection rather than command execution. The `docs_updated` gate uses a rule because documentation coverage requires judgment rather than a simple exit code.

### `when`

An optional condition controlling whether the gate runs at all. When `when` is present and evaluates to false (the condition does not apply to this step's changes), the gate is marked `SKIP` and does not execute. Examples:

- `"frontend files changed"` — only run for steps that touched frontend code
- `"database migration files changed"` — only run after schema changes

When `when` is absent, the gate runs unconditionally.

---

## Retry Section

Controls how the retry engine behaves when a required gate fails.

### `retry.max_attempts`

Total number of attempts per gate (including the initial attempt). Default is `3`. With `max_attempts: 3`, a gate gets one initial run plus two retries before escalation.

### `retry.backoff.strategy`

Retry delay strategy. Currently supports `"fixed"` (constant delay between retries). Future: `"exponential"`.

### `retry.backoff.delay_seconds`

Seconds to wait between retry attempts. Default is `5`. Increase this if the failing command needs time to recover (e.g., waiting for a port to be released).

### `retry.on_failure`

What happens when all retries are exhausted. `"escalate"` is the only supported value — the Controller escalates to the PM with the full failure details and available options (fix manually / skip gate with explanation / abort EPIC).

---

## Escalation Section

Configures the message format used when a gate exhausts its retries.

### `escalation.method`

`"inline"` — the escalation message is presented directly in the current conversation (chat) or sent via Slack if Slack integration is enabled.

### `escalation.message_template`

Template for the escalation message. Interpolated fields: `{gate_name}`, `{epic_id}`, `{attempt_count}`, `{max_attempts}`, `{last_error}`. This template is used for both chat and Slack escalations.

---

## Budget Section

### `budget.max_llm_cost_per_epic_usd`

Maximum allowed LLM cost for a single EPIC run in USD. If the running cost estimate exceeds this value, the Controller escalates to the PM immediately with options to increase the budget or abort. Default is `$50`.

### `budget.warn_at_percentage`

Threshold percentage of the budget at which a warning is logged. Default is `80` — the Controller logs a cost warning when estimated spend reaches 80% of `max_llm_cost_per_epic_usd`.

---

## Evidence Section

### `evidence.store_gate_results`

`true` — write each gate's pass/fail status to `gates_report.json`.

### `evidence.store_command_output`

`true` — include command stdout/stderr output in `gates_report.json`. Set to `false` to reduce storage if gate output is verbose.

### `evidence.store_retry_history`

`true` — include all retry attempts (not just the final result) in `gates_report.json`.

### `evidence.output_dir`

Directory path for gate evidence, relative to the project root. The `{epic_id}` and `{run_id}` placeholders are interpolated at runtime.

---

## Customizing for Your Tech Stack

The defaults are Python-centric (`pytest`, `ruff`, `bandit`). `/aid-setup` updates the gate commands automatically when it detects your stack, but you can also edit the file directly.

### Node.js / TypeScript project

```yaml
gates:
  tests_pass:
    description: "All tests pass"
    required: true
    command: "npm test -- --run"
    timeout_seconds: 300
    pass_criteria: "exit code 0"

  lint_pass:
    description: "Code passes ESLint"
    required: true
    command: "npx eslint src --max-warnings 0"
    timeout_seconds: 120
    pass_criteria: "exit code 0"

  type_check:
    description: "TypeScript type checking passes"
    required: true
    command: "npx tsc --noEmit"
    timeout_seconds: 120
    pass_criteria: "exit code 0"

  build_pass:
    description: "Project builds without errors"
    required: true
    command: "npm run build"
    timeout_seconds: 180
    pass_criteria: "exit code 0"
```

### Go project

```yaml
gates:
  tests_pass:
    description: "All tests pass"
    required: true
    command: "go test ./... -count=1"
    timeout_seconds: 300
    pass_criteria: "exit code 0"

  lint_pass:
    description: "golangci-lint passes"
    required: true
    command: "golangci-lint run"
    timeout_seconds: 180
    pass_criteria: "exit code 0"

  build_pass:
    description: "Project builds"
    required: true
    command: "go build ./..."
    timeout_seconds: 120
    pass_criteria: "exit code 0"
```

### Rust project

```yaml
gates:
  tests_pass:
    description: "All tests pass"
    required: true
    command: "cargo test --workspace"
    timeout_seconds: 600
    pass_criteria: "exit code 0"

  lint_pass:
    description: "Clippy passes with no warnings"
    required: true
    command: "cargo clippy -- -D warnings"
    timeout_seconds: 300
    pass_criteria: "exit code 0"

  format_check:
    description: "rustfmt formatting is correct"
    required: true
    command: "cargo fmt --check"
    timeout_seconds: 60
    pass_criteria: "exit code 0"
```

---

## Adding a Custom Gate

Any key under `gates:` is a gate. To add a gate for database migration safety:

```yaml
gates:
  migration_safe:
    description: "No destructive migrations without corresponding up/down pair"
    required: true
    command: "python scripts/check_migrations.py"
    timeout_seconds: 30
    pass_criteria: "exit code 0"
```

To add a rule-based gate (agent inspection, no command):

```yaml
gates:
  api_contract_updated:
    description: "OpenAPI spec updated when endpoint signatures change"
    required: true
    rule: "openapi.yaml must be updated when any file in src/routes/ changes"
    pass_criteria: "manual or automated check that openapi.yaml reflects all current endpoint signatures"
```

---

## Disabling a Gate

To disable a gate that does not apply to your project, set `required: false` and add a `when` condition that never triggers. The simplest approach is to delete the gate entirely. Alternatively, if you want to keep it visible for reference:

```yaml
  security_scan_pass:
    description: "No high/critical security findings"
    required: false       # Changed from true — project uses a separate security pipeline
    command: "bandit -q -r . -ll"
    timeout_seconds: 180
    pass_criteria: "exit code 0, no HIGH or CRITICAL findings"
```

---

## Related

- [Gates Engine](../skills/gates-engine) — how this file is parsed and executed
- [Retry Engine](../skills/retry-engine) — what happens when a gate fails
- [Quality Gates](../skills/quality-gates) — per-commit 6-gate protocol (different scope)
- [decision-policies.yaml](./decision-policies) — escalation triggers that use gate results
