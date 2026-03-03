---
sidebar_position: 3
title: "Configuration"
description: "Three YAML files control AID v2 — execution, orchestration, and integrations."
---

# Configuration

AID v2 uses three YAML configuration files inside `.aid-o/config/`. When you run `/aid-init`, AID copies defaults and runs the project-scanner agent to detect your stack and customize commands accordingly.

All config is read fresh at the start of each pipeline run. Edit any file between runs and the changes take effect immediately.

## Config Files

```text
.aid-o/
  config/
    execution.yaml       Gates, retry policy, budget, quality thresholds
    orchestration.yaml   Language, dispatch strategy, FSM settings, release policy
    integrations.yaml    Slack, Qdrant memory, knowledge acquisition
    project.yaml         Auto-detected stack, conventions, paths (written by project-scanner)
```

---

## execution.yaml

**Purpose:** Controls what quality gates run, how failures are retried, and what the budget limits are.

### Gates

```yaml
gates:
  tests_pass:
    description: "All tests pass via project test runner"
    required: true
    command: "npm test"
    timeout_seconds: 300
    pass_criteria: "exit code 0"

  lint_pass:
    description: "Code passes linting and formatting checks"
    required: false
    command: "ruff check . && ruff format --check ."
    timeout_seconds: 120
    when: "linting tools configured"

  scope_check:
    description: "Verify changes are within EPIC scope"
    command: "plugins/aid-orchestrator/scripts/gates/scope-check.sh ..."
    required: true
    type: deterministic
    max_retries: 0

  security_scan_pass:
    description: "No high/critical security findings"
    required: true
    command: "bandit -q -r . -ll"
    timeout_seconds: 180

  docs_updated:
    description: "Documentation updated for changed APIs/models"
    required: true
    rule: "docs or CHANGELOG updated if code changes affect public API"

  build_pass:
    description: "Project builds without errors"
    required: false
    command: "npm run build"
    timeout_seconds: 180
    when: "frontend files changed"
```

Gates with `required: true` must pass for the pipeline to proceed. Gates with a `when` clause are conditional — skipped if the condition is false.

`/aid-init` runs the project-scanner agent to detect your test runner, linter, and build tool, then updates these commands to match your stack (e.g., `pytest` for Python, `vitest run` for Vite projects).

### Retry and Escalation

```yaml
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
    Attempts: {attempt_count}/{max_attempts}
    Last error: {last_error}
```

### Budget

```yaml
budget:
  max_llm_cost_per_epic_usd: 50
  warn_at_percentage: 80
```

### Quality Thresholds

```yaml
quality_thresholds:
  min_test_coverage_percent: 80
  min_review_score: 7
  max_todo_count: 0
  max_security_findings_high: 0
  max_security_findings_medium: 3
```

### Escalation Triggers

```yaml
escalation_triggers:
  - trigger: "gate fails after max_attempts retries"
    action: "HARD STOP"
  - trigger: "LLM cost exceeds budget"
    action: "HARD STOP"
  - trigger: "security finding classified as CRITICAL"
    action: "HARD STOP"
```

### Curator Rules

```yaml
curator_auto_rules:
  always_approve:
    - { type: dx }
    - { type: security, priority: high }
    - { area: "docs/*" }
  always_defer:
    - { type: architecture }
  default_action: approve
```

---

## orchestration.yaml

**Purpose:** Controls how the pipeline is structured — language, model tiers, dispatch strategy, FSM config, and release automation.

### Language

```yaml
language:
  document_language: EN
  conversation_language: auto
```

### Model Tiers

Maps agent roles to Claude model tiers:

```yaml
models:
  opus: [architect, backend, frontend]
  sonnet: [qa, security, docs-writer, curator, auditor, implementer, verifier]
  haiku: [gate-fixer, run-validator]
```

### Dispatch Strategy

```yaml
dispatch:
  strategy: worktrees       # worktrees | sequential
  max_parallel: 4
  worktree_base: .claude/worktrees
```

### FSM Configuration

```yaml
fsm:
  states: [READY, EXECUTE, GATES, ESCALATION, DONE]
  state_file: .aid-o/work/evidence/{epic_id}/{run_id}/state.yaml
  timeline_file: .aid-o/work/evidence/{epic_id}/{run_id}/timeline.jsonl
```

### Release Policy

```yaml
release:
  versioning:
    mode: single
    changelog: CHANGELOG.md
  version_files:
    - path: "package.json"
      field: "version"
      update_method: json_field
  settings:
    git_tag: true
    github_release: true
```

---

## integrations.yaml

**Purpose:** External service connections. Both are optional and disabled by default.

### Slack

```yaml
slack:
  enabled: false
  channel: "#aid-orchestrator"
  pm_user_id: ""
  timeouts:
    plan_approval_minutes: 1440
    escalation_minutes: 480
```

When enabled, escalations and approvals are sent to Slack. Requires the Slack MCP server configured in `.mcp.json`.

### Qdrant Memory

```yaml
memory:
  enabled: false
  collection_name: "aid-memory"
  search:
    top_k: 3
    timeout_seconds: 5
    min_score: 0.4
    pre_step_search: true
```

When enabled, decisions, lessons, and patterns are indexed in Qdrant for semantic search across runs and projects. See [Memory System](../architecture/memory-system) for details.

### Knowledge Acquisition

```yaml
knowledge:
  enabled: false
  primary_source: context7
  fallback_source: websearch
```

---

## project.yaml

**Location:** `.aid-o/config/project.yaml`

Auto-generated by the project-scanner agent during `/aid-init`. Describes your project to all agents.

```yaml
project_name: "my-api"
tech_stack:
  language: TypeScript
  framework: Next.js
  test_framework: Vitest
  linter: ESLint
  build: "npm run build"
architecture: monorepo
git:
  default_branch: main
  remote: "git@github.com:org/my-api.git"
conventions:
  commit_style: conventional
  naming: camelCase
  api_style: REST
```

Every agent reads this file at dispatch time. If the project-scanner detected something incorrectly, edit this file directly.

---

## Customization Tips

1. **Replace gate commands** with your project's actual tools. AID does not assume any specific test runner or linter.
2. **Set `required: false`** on gates that do not apply to your stack.
3. **Add custom gates** — any entry with a `command` field is executed by `aid-run-gates.sh`.
4. **Adjust timeouts** if your test suite is slow.
5. **Lower quality thresholds** during early development and tighten them as the project matures.

## Upgrading

When you update the AID plugin, run `/aid-init` again. AID detects which config files you have customized (by checksum comparison) and skips them. New defaults are added without overwriting your changes.
