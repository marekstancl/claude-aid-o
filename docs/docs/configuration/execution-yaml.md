---
sidebar_position: 1
title: "execution.yaml"
description: "Reference for execution.yaml — quality gates, retry and escalation, budget, evidence, quality thresholds, auto-decisions, content quality, discovered issues, and acceptable debt."
---

# execution.yaml

**Location:** `.aid-o/config/execution.yaml`

This file is the single source of configuration for quality enforcement and decision-making during pipeline execution. It consolidates what v1 split across `gates.yaml` and `decision-policies.yaml` into one file.

The Controller reads `execution.yaml` at the start of every run. It defines:

- Which quality gates run after each step and before commit
- Retry and escalation behavior when gates fail
- Budget limits for LLM cost per run
- Evidence storage settings
- Quality thresholds agents must meet
- Autonomous decision rules (what the Controller decides without PM input)
- Escalation triggers (what always requires PM input)
- Content quality review rules
- Discovered issue triage policies
- Acceptable and not-acceptable technical debt

---

## Full Default Configuration

Source: `plugins/aid-orchestrator/defaults/execution.yaml`

```yaml
# AID Execution Configuration (v2)
# Consolidated from: gates.yaml, decision-policies.yaml
#
# Controls: quality gates, retry/escalation, decision policies, budget,
#           content quality, discovered issues triage, and acceptable debt.

# ─── Quality Gates ───────────────────────────────────────────────────────
gates:
  tests_pass:
    description: "All tests pass via project test runner"
    required: true
    command: "./plugins/aid-orchestrator/scripts/tests/run-all-tests.sh"
    timeout_seconds: 300
    pass_criteria: "exit code 0"

  security_scan_pass:
    description: "No high/critical security findings"
    required: true
    command: "bandit -q -r . -ll"
    timeout_seconds: 180
    pass_criteria: "exit code 0"

  docs_updated:
    description: "Documentation updated for changed APIs/models"
    required: true
    rule: "docs or CHANGELOG updated if code changes affect public API"
    pass_criteria: "manual or automated check"

  scope_check:
    description: "Verify changes are within EPIC scope"
    command: "plugins/aid-orchestrator/scripts/gates/scope-check.sh .aid-o/work/evidence/{epic_id}/allowed_paths.txt {base_commit}"
    required: true
    type: deterministic
    max_retries: 0

  lint_pass:
    description: "Code passes linting and formatting checks"
    required: false
    command: "ruff check . && ruff format --check ."
    timeout_seconds: 120
    when: "linting tools configured"

  type_check:
    description: "TypeScript type checking passes"
    required: false
    command: "npx tsc --noEmit"
    timeout_seconds: 120
    when: "frontend files changed"

  build_pass:
    description: "Project builds without errors"
    required: false
    command: "npm run build"
    timeout_seconds: 180
    when: "frontend files changed"

# ─── Retry & Escalation ─────────────────────────────────────────────────
retry:
  max_attempts: 3
  backoff:
    strategy: fixed
    delay_seconds: 5
  on_failure: escalate

escalation:
  method: inline
  message_template: |
    GATE FAILURE — Escalation to PM
    Gate: {gate_name}
    EPIC: {epic_id}
    Attempts: {attempt_count}/{max_attempts}
    Last error: {last_error}
    Action needed: Review and decide (fix / skip / abort)

# ─── Budget ──────────────────────────────────────────────────────────────
budget:
  max_llm_cost_per_epic_usd: 50
  warn_at_percentage: 80

# ─── Evidence ────────────────────────────────────────────────────────────
evidence:
  store_gate_results: true
  store_command_output: true
  store_retry_history: true
  output_dir: "evidence/{epic_id}/{run_id}/gates/"

# ─── Quality Thresholds ─────────────────────────────────────────────────
quality_thresholds:
  min_test_coverage_percent: 80
  min_review_score: 7
  max_todo_count: 0
  max_security_findings_high: 0
  max_security_findings_medium: 3

# ─── Auto-Decisions (Controller decides without PM) ──────────────────────
auto_decisions:
  - condition: "all gate results = pass"
    action: "proceed to next state"
  - condition: "gate fails AND retry_count < max_attempts"
    action: "generate fix instructions, dispatch retry"
  - condition: "step produces expected outputs"
    action: "proceed to next step"
  - condition: "agent modifies only allowed_paths"
    action: "accept changes"
  - condition: "agent modifies forbidden_paths"
    action: "reject changes, re-dispatch with warning"
  - condition: "LLM cost < budget.warn_at_percentage"
    action: "continue execution"

# ─── Escalation Triggers ────────────────────────────────────────────────
escalation_triggers:
  - trigger: "gate fails after max_attempts retries"
    action: "HARD STOP"
    options: ["fix manually", "skip gate", "abort EPIC"]
  - trigger: "LLM cost exceeds budget"
    action: "HARD STOP"
    options: ["increase budget", "abort EPIC"]
  - trigger: "agent produces no output or errors out"
    action: "HARD STOP"
    options: ["retry with different prompt", "skip step", "abort EPIC"]
  - trigger: "conflicting outputs from parallel agents"
    action: "HARD STOP"
    options: ["choose A", "choose B", "merge manually"]
  - trigger: "security finding classified as CRITICAL"
    action: "HARD STOP"
    options: ["fix before proceeding", "abort EPIC"]

# ─── Content Quality ────────────────────────────────────────────────────
content_quality:
  auto_accept_when:
    - "step role is: docs, config, release"
    - "step has <= 3 acceptance criteria"
  review_required_when:
    - "step role is: architect, backend, frontend, security"
    - "step has 5+ acceptance criteria"
  review_agent: code-reviewer
  max_review_fix_cycles: 2

# ─── Discovered Issues Triage ───────────────────────────────────────────
discovered_issues:
  critical:
    auto_fix_patterns:
      - { pattern: "migration.*fail", dispatch: backend }
      - { pattern: "dependency.*conflict", dispatch: backend }
      - { pattern: "security.*critical", dispatch: security }
    default_action: escalate_to_pm
    blocks_current_step: true
  high:
    forward_to_later_step: true
    create_backlog_entry: true
    blocks_current_step: false
  medium:
    log_to_improvement_notes: true
    blocks_current_step: false

# ─── Acceptable / Not-Acceptable Debt ────────────────────────────────────
acceptable_debt:
  - "TODO with issue reference (tracked in backlog)"
  - "missing edge case tests (core path tested)"
  - "placeholder error messages (replaced before release)"

not_acceptable:
  - "TODO/FIXME without issue reference"
  - "hardcoded credentials or API keys"
  - "disabled security checks"
  - "skipped tests without documented reason"
  - "changes to forbidden paths"
  - "console.log / print() in production code"
  - "empty catch blocks"

# ─── Curator Auto-Resolution ────────────────────────────────────────────
curator_auto_rules:
  always_approve:
    - { type: dx }
    - { type: security, priority: high }
    - { area: "docs/*" }
  always_defer:
    - { type: architecture }
  default_action: approve
  learning:
    enabled: true
    similarity_threshold: 0.80
    min_decisions: 3
```

---

## Field Reference

### gates

The `gates` map defines each quality gate by a unique key.

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Human-readable description. Appears in reports, escalations, and Slack messages. |
| `required` | boolean | `true` = must pass for pipeline to proceed. `false` = warning only, logged but not blocking. |
| `command` | string | Shell command to execute. Exit code 0 = pass. Omit for rule-based gates. |
| `rule` | string | Logical condition for agent-inspected gates (no shell command). Used when verification requires judgment. |
| `timeout_seconds` | integer | Maximum execution time for the command. Gate fails with timeout error if exceeded. |
| `pass_criteria` | string | Human-readable pass description. Used in evidence reports and escalation messages. |
| `type` | string | Gate type. `deterministic` gates have no retry (e.g., scope check). Default: retryable. |
| `max_retries` | integer | Per-gate retry override. `0` = no retries even if global `retry.max_attempts` is higher. |
| `when` | string | Optional condition. Gate is skipped (`SKIP` status) when condition does not apply to current changes. |

### retry

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_attempts` | integer | `3` | Total attempts per gate (initial + retries). |
| `backoff.strategy` | string | `fixed` | Retry delay strategy. Currently `fixed` only. |
| `backoff.delay_seconds` | integer | `5` | Seconds between retry attempts. |
| `on_failure` | string | `escalate` | Action when all retries exhausted. Only `escalate` is supported. |

### escalation

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `method` | string | `inline` | Escalation delivery. `inline` = present in chat or Slack (if enabled). |
| `message_template` | string | *(see above)* | Template with placeholders: `{gate_name}`, `{epic_id}`, `{attempt_count}`, `{max_attempts}`, `{last_error}`. |

### budget

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_llm_cost_per_epic_usd` | number | `50` | Maximum LLM cost per run in USD. Exceeding triggers HARD STOP. |
| `warn_at_percentage` | integer | `80` | Cost warning threshold as percentage of budget. |

### evidence

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `store_gate_results` | boolean | `true` | Write pass/fail status to `gates_report.json`. |
| `store_command_output` | boolean | `true` | Include command stdout/stderr in report. |
| `store_retry_history` | boolean | `true` | Include all retry attempts in report. |
| `output_dir` | string | `evidence/{epic_id}/{run_id}/gates/` | Evidence directory (relative to `.aid-o/work/`). |

### quality_thresholds

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `min_test_coverage_percent` | integer | `80` | Minimum code coverage. Below triggers review or fix. |
| `min_review_score` | integer | `7` | Minimum review score (1-10 scale). Below triggers fix cycle. |
| `max_todo_count` | integer | `0` | Maximum bare TODO/FIXME comments (without issue reference). |
| `max_security_findings_high` | integer | `0` | Maximum high-severity findings. Any = blocks acceptance. |
| `max_security_findings_medium` | integer | `3` | Maximum medium-severity findings. |

### auto_decisions

Ordered list of conditions the Controller evaluates autonomously. First matching condition determines the action.

| Condition | Action |
|-----------|--------|
| All gate results pass | Proceed to next state |
| Gate fails, retry count below limit | Generate fix instructions, dispatch retry |
| Step produces expected outputs | Proceed to next step |
| Agent modified only allowed paths | Accept changes |
| Agent modified forbidden paths | Reject, re-dispatch with warning |
| LLM cost below warning threshold | Continue |

These are core Controller logic. You typically do not edit `auto_decisions` directly; tune `quality_thresholds`, `not_acceptable`, and `curator_auto_rules` instead.

### escalation_triggers

Conditions that always cause a HARD STOP requiring PM input.

| Trigger | Options presented to PM |
|---------|------------------------|
| Gate fails after all retries | fix manually / skip gate / abort |
| LLM cost exceeds budget | increase budget / abort |
| Agent produces no output or errors | retry with different prompt / skip step / abort |
| Conflicting parallel outputs | choose A / choose B / merge manually |
| Critical security finding | fix before proceeding / abort |

### content_quality

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `auto_accept_when` | list | *(see config)* | Conditions for automatic step acceptance. |
| `review_required_when` | list | *(see config)* | Conditions that trigger code-reviewer dispatch. |
| `review_agent` | string | `code-reviewer` | Agent dispatched for review. |
| `max_review_fix_cycles` | integer | `2` | Maximum review-then-fix cycles before escalation. |

### discovered_issues

| Severity | Blocks step? | Default action |
|----------|-------------|----------------|
| `critical` | Yes | Auto-fix known patterns, escalate unknown to PM. |
| `high` | No | Forward to later step, create backlog entry. |
| `medium` | No | Log to improvement notes. |

### acceptable_debt / not_acceptable

`acceptable_debt` lists technical debt patterns the Controller tolerates (e.g., TODOs with issue references). `not_acceptable` lists patterns that always fail the step (e.g., hardcoded credentials, empty catch blocks).

### curator_auto_rules

| Field | Description |
|-------|-------------|
| `always_approve` | Proposal types auto-approved (e.g., DX improvements, docs changes). |
| `always_defer` | Proposal types deferred to backlog (e.g., architecture changes). |
| `default_action` | Fallback when no rule matches: `approve`, `defer`, or `reject`. |
| `learning.enabled` | Enable Qdrant-based learning from PM decisions. |
| `learning.similarity_threshold` | Minimum vector similarity (0.0-1.0) to reuse a past decision. |
| `learning.min_decisions` | Minimum past decisions before pattern is trusted. |

---

## Customization Tips

### Adapting gates for your tech stack

The default gates are polyglot. Override `command` values to match your project:

**Node.js / TypeScript:**
```yaml
gates:
  tests_pass:
    command: "npm test -- --run"
    required: true
  lint_pass:
    command: "npx eslint src --max-warnings 0"
    required: true
  type_check:
    command: "npx tsc --noEmit"
    required: true
```

**Go:**
```yaml
gates:
  tests_pass:
    command: "go test ./... -count=1"
    required: true
  lint_pass:
    command: "golangci-lint run"
    required: true
```

**Rust:**
```yaml
gates:
  tests_pass:
    command: "cargo test --workspace"
    required: true
  lint_pass:
    command: "cargo clippy -- -D warnings"
    required: true
```

### Adding a custom gate

Any key under `gates:` defines a gate:

```yaml
gates:
  migration_safe:
    description: "No destructive migrations without up/down pair"
    required: true
    command: "python scripts/check_migrations.py"
    timeout_seconds: 30
    pass_criteria: "exit code 0"
```

### Disabling a gate

Set `required: false` or delete the gate entirely:

```yaml
gates:
  security_scan_pass:
    required: false  # Project uses a separate security pipeline
```

### Adjusting budget for large projects

```yaml
budget:
  max_llm_cost_per_epic_usd: 100  # Doubled for large EPIC
  warn_at_percentage: 70           # Earlier warning
```

### Relaxing coverage during ramp-up

```yaml
quality_thresholds:
  min_test_coverage_percent: 60  # Will increase to 80 by v2.1
```

---

## Related

- [Quality Gates architecture](../architecture/quality-gates) — how gates fit into the pipeline
- [orchestration.yaml](./orchestration-yaml) — Controller settings and FSM parameters
- [integrations.yaml](./integrations-yaml) — Slack and Qdrant configuration
