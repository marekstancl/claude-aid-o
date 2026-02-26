---
sidebar_position: 2
title: "decision-policies.yaml"
description: "Reference for decision-policies.yaml — quality thresholds, architecture principles, auto-decision rules, escalation triggers, acceptable technical debt, and Curator auto-resolution rules."
---

# decision-policies.yaml

**Location:** `.aid-o/03-config/policies/decision-policies.yaml`

This file is the policy center for the Controller. It defines what quality bar agents must meet, which architectural principles they must follow, when the Controller acts autonomously versus escalates to you, and what kinds of issues are never acceptable. The Controller reads this file at the start of every EPIC run.

**Goal:** 90%+ of decisions made autonomously, without PM intervention.

---

## Full Default Configuration

The default file installed by `/aid-init` (source: `plugins/aid-orchestrator/defaults/policies/decision-policies.yaml`):

```yaml
quality_thresholds:
  min_test_coverage_percent: 80
  min_review_score: 7
  max_todo_count: 0
  max_security_findings_high: 0
  max_security_findings_medium: 3

architecture_principles:
  - name: "contract-first"
    description: "API/event contracts must be defined before implementation"
    enforcement: "architect step must complete before backend/frontend steps"

  - name: "YAGNI"
    description: "Only implement what the EPIC requires, nothing more"
    enforcement: "scope enforcement via allowed_paths in plan steps"

  - name: "tenant-isolation"
    description: "All data access must be tenant-scoped when EPIC.constraints.tenant_safe = true"
    enforcement: "security agent validates tenant filtering"

  - name: "atomic-commits"
    description: "One logical change per commit"
    enforcement: "git-workflow skill validates commit scope"

  - name: "evidence-by-design"
    description: "Every state transition produces evidence artifacts"
    enforcement: "controller logs to evidence/ on every transition"

auto_decisions:
  - condition: "all gate results = pass"
    action: "proceed to PM_APPROVAL state"
    reason: "all quality criteria met"

  - condition: "gate fails AND retry_count < max_attempts"
    action: "generate fix instructions, dispatch retry"
    reason: "automatic retry within budget"

  - condition: "step produces expected outputs"
    action: "proceed to next step or parallel group"
    reason: "step completed successfully"

  - condition: "step has no dependencies blocking"
    action: "schedule for execution"
    reason: "dependency graph allows execution"

  - condition: "agent modifies only allowed_paths"
    action: "accept changes"
    reason: "within scope"

  - condition: "agent modifies forbidden_paths"
    action: "reject changes, re-dispatch with warning"
    reason: "scope violation"

  - condition: "LLM cost < budget.warn_at_percentage"
    action: "continue execution"
    reason: "within budget"

  - condition: "step output meets all acceptance criteria from plan"
    action: "proceed to next step"
    reason: "content quality verified"

  - condition: "acceptance criteria unclear, step is high-complexity"
    action: "dispatch code-reviewer for detailed review"
    reason: "orchestrator cannot verify domain-specific criteria"

  - condition: "acceptance criteria clearly NOT met after 2 fix cycles"
    action: "escalate to PM"
    reason: "automated fix attempts exhausted"

content_quality:
  auto_accept_when:
    - all acceptance criteria verifiable from output.md
    - step role is: docs, config, release
    - step has <= 3 acceptance criteria

  review_required_when:
    - step role is: architect, backend, frontend, security
    - step has 5+ acceptance criteria
    - step is target of analysis_group
    - orchestrator cannot determine if criterion is met

  review_agent: code-reviewer
  max_review_fix_cycles: 2

escalation_triggers:
  - trigger: "gate fails after max_attempts retries"
    action: "HARD STOP — present failure details to PM"
    options: ["fix manually", "skip gate (document why)", "abort EPIC"]

  - trigger: "LLM cost exceeds budget.max_llm_cost_per_epic_usd"
    action: "HARD STOP — present cost report to PM"
    options: ["increase budget", "abort EPIC"]

  - trigger: "agent produces no output or errors out"
    action: "HARD STOP — present error to PM"
    options: ["retry with different prompt", "skip step", "abort EPIC"]

  - trigger: "conflicting outputs from parallel agents"
    action: "HARD STOP — present both outputs to PM"
    options: ["choose version A", "choose version B", "merge manually"]

  - trigger: "EPIC acceptance criteria ambiguous"
    action: "ASK PM for clarification before planning"
    options: ["clarify criteria", "proceed with best interpretation"]

  - trigger: "architecture decision with multiple valid options"
    action: "present options with tradeoffs to PM"
    options: ["option A", "option B", "custom"]

  - trigger: "security finding classified as CRITICAL"
    action: "HARD STOP — immediate PM notification"
    options: ["fix before proceeding", "abort EPIC"]

  - trigger: "agent reports CRITICAL discovered issue"
    action: "HARD STOP — triage discovered issue"
    options: ["auto-fix (dispatch appropriate agent)", "skip (document risk)", "abort EPIC"]

discovered_issues:
  critical:
    auto_fix_patterns:
      - pattern: "migration.*fail"
        dispatch: backend
      - pattern: "dependency.*conflict"
        dispatch: backend
      - pattern: "security.*critical"
        dispatch: security
    default_action: escalate_to_pm
    blocks_current_step: true

  high:
    forward_to_later_step: true
    create_backlog_entry: true
    pm_notification: true
    blocks_current_step: false

  medium:
    log_to_improvement_notes: true
    blocks_current_step: false

  info:
    log_to_improvement_notes: true
    blocks_current_step: false

acceptable_debt:
  - type: "TODO with issue reference"
    example: "# TODO(AID-123): optimize query for large datasets"
    allowed: true
    condition: "tracked in backlog with severity and deadline"

  - type: "missing edge case tests"
    allowed: true
    condition: "core happy path tested, edge cases documented in backlog"

  - type: "placeholder error messages"
    allowed: true
    condition: "replaced before release run"

not_acceptable:
  - "TODO/FIXME without issue reference"
  - "hardcoded credentials or API keys"
  - "disabled security checks"
  - "skipped tests without documented reason"
  - "changes to forbidden paths"
  - "breaking contract changes without migration plan"
  - "console.log / print() in production code"
  - "empty catch blocks"

curator_auto_rules:
  always_approve:
    - { type: dx }
    - { type: security, priority: high }
    - { area: "docs/*" }

  always_reject: []

  always_defer:
    - { type: architecture }

  default_action: approve

  learning:
    enabled: true
    similarity_threshold: 0.80
    min_decisions: 3
```

---

## quality_thresholds

These thresholds define the minimum bar that agents are expected to meet. Agents read these values from the project profile and use them to self-assess their work.

### `min_test_coverage_percent`

Minimum percentage of code that must be covered by tests. Default is `80`. The code-reviewer agent compares coverage reports against this threshold. If coverage falls below this value, the step output is flagged for review or fix.

Customize this if your project is building up coverage incrementally:

```yaml
quality_thresholds:
  min_test_coverage_percent: 60  # Will increase to 80 by v2.0
```

### `min_review_score`

Minimum acceptable review score from the code-reviewer agent, on a scale of 1–10. Default is `7`. Scores below this threshold result in a fix cycle.

### `max_todo_count`

Maximum number of `TODO` or `FIXME` comments allowed in committed code without an issue reference. Default is `0` — zero bare TODOs are allowed. TODOs with a backlog reference (e.g., `TODO(AID-123)`) are tracked under `acceptable_debt` and not counted here.

### `max_security_findings_high`

Maximum number of high-severity security findings allowed. Default is `0` — any high finding blocks acceptance.

### `max_security_findings_medium`

Maximum number of medium-severity security findings allowed. Default is `3`. Adjust this based on your risk tolerance and the nature of the project.

---

## architecture_principles

A list of named principles that every agent reads before executing their step. Agents use these to resolve ambiguity when making implementation decisions. Adding your own principles here is one of the most effective ways to encode project-specific conventions into agent behavior.

Each entry has three fields:

- `name` — short identifier used in escalation messages and evidence
- `description` — the principle stated plainly
- `enforcement` — how the principle is checked or enforced in the pipeline

### Default principles

| Name | What it means |
|---|---|
| `contract-first` | API and event contracts are defined by the Architect before any implementation step begins |
| `YAGNI` | Agents only implement what the current EPIC requires — no speculative features |
| `tenant-isolation` | When `EPIC.constraints.tenant_safe = true`, all database queries must be tenant-scoped |
| `atomic-commits` | Each commit covers exactly one logical change |
| `evidence-by-design` | Every Controller state transition writes evidence artifacts to `04-engine/evidence/` |

### Adding project-specific principles

```yaml
architecture_principles:
  - name: "repository-pattern"
    description: "All database access goes through repository classes in src/repositories/"
    enforcement: "backend agent validates no direct DB calls from services or controllers"

  - name: "openapi-first"
    description: "All REST endpoints must have a corresponding OpenAPI spec entry before implementation"
    enforcement: "architect step must update openapi.yaml, backend step reads from it"

  - name: "no-side-effects-in-constructors"
    description: "Class constructors must not perform I/O or async operations"
    enforcement: "code-reviewer agent checks constructor bodies"
```

---

## auto_decisions

An ordered list of conditions the Controller evaluates autonomously — no PM input required. When a condition matches, the Controller takes the listed action immediately.

These rules cover the full lifecycle of step execution: scheduling, output validation, scope enforcement, cost tracking, and content quality. The Controller evaluates them from top to bottom; the first matching condition determines the action.

| Condition | Action |
|---|---|
| All gate results pass | Proceed to PM_APPROVAL state |
| Gate fails, retry count below limit | Dispatch gate-fixer, retry |
| Step produces expected outputs | Proceed to next step |
| Step has no blocking dependencies | Schedule for execution |
| Agent modified only allowed paths | Accept changes |
| Agent modified forbidden paths | Reject, re-dispatch with warning |
| LLM cost below warning threshold | Continue |
| All acceptance criteria met | Proceed to next step |
| Criteria unclear, high-complexity step | Dispatch code-reviewer for review |
| Criteria not met after 2 fix cycles | Escalate to PM |

You do not edit `auto_decisions` for day-to-day customization. These rules are the Controller's core logic. The sections you tune most often are `quality_thresholds`, `architecture_principles`, `not_acceptable`, and `curator_auto_rules`.

---

## content_quality

Controls when the Controller auto-accepts a step's output versus when it dispatches the code-reviewer agent for a detailed review.

### `auto_accept_when`

The step output is accepted automatically when any of these conditions is true:

- All acceptance criteria can be verified from the step's `output.md` file
- The step's agent role is `docs`, `config`, or `release` (lower-risk output types)
- The step has three or fewer acceptance criteria (easy to verify mechanically)

### `review_required_when`

The code-reviewer agent is dispatched when any of these conditions is true:

- The step's agent role is `architect`, `backend`, `frontend`, or `security`
- The step has five or more acceptance criteria
- The step is the target of an analysis group in the plan
- The Controller cannot determine whether a criterion is met from the output alone

### `max_review_fix_cycles`

Maximum number of review-then-fix cycles before escalating to the PM. Default is `2`. After two cycles, if the code-reviewer still scores the output below `min_review_score`, the Controller escalates.

---

## escalation_triggers

Conditions that always cause a hard stop and require PM input. These cannot be bypassed by `auto_decisions`. Each trigger lists the options presented to the PM.

| Trigger | Type | Options |
|---|---|---|
| Gate fails after all retries | Hard stop | fix manually / skip / abort |
| LLM cost exceeds budget | Hard stop | increase budget / abort |
| Agent produces no output or errors | Hard stop | retry / skip step / abort |
| Conflicting outputs from parallel agents | Hard stop | choose A / choose B / merge |
| EPIC acceptance criteria ambiguous | Ask PM | clarify / proceed with interpretation |
| Architecture decision with multiple valid options | Present options | option A / option B / custom |
| Security finding classified CRITICAL | Hard stop (immediate) | fix first / abort |
| Agent reports CRITICAL discovered issue | Hard stop | auto-fix / skip with risk note / abort |

---

## discovered_issues

When agents report issues they discover during their step (not the EPIC's primary objective), this section controls how those issues are handled based on severity.

### `critical`

Blocks the current step. The Controller attempts auto-fix for known patterns (migration failures, dependency conflicts, critical security issues). Unrecognized critical issues escalate to the PM immediately.

### `high`

Does not block the current step. The issue is forwarded to a later step in the plan, a backlog entry is created, and the PM receives a notification. Work continues.

### `medium`

Logged as an improvement note in the step output. Does not block or notify.

### `info`

Logged as an improvement note. No further action.

---

## acceptable_debt

Technical debt the Controller tolerates, subject to conditions. Agents consult this list when deciding whether to flag a pattern as a blocker or log it as a note.

The default entries allow:
- TODOs that reference a backlog item
- Missing edge case tests when the happy path is covered and edge cases are backlogged
- Placeholder error messages before a release run

To add a project-specific acceptable pattern:

```yaml
acceptable_debt:
  - type: "legacy module without types"
    allowed: true
    condition: "module is in src/legacy/ and has a tracking issue for migration"
```

---

## not_acceptable

Patterns that are never tolerated, regardless of `acceptable_debt`. If an agent's output contains any of these, the step is failed and a fix is required before proceeding.

Default blockers:

- `TODO/FIXME without issue reference`
- `hardcoded credentials or API keys`
- `disabled security checks`
- `skipped tests without documented reason`
- `changes to forbidden paths`
- `breaking contract changes without migration plan`
- `console.log / print() in production code`
- `empty catch blocks`

To add project-specific blockers:

```yaml
not_acceptable:
  - "TODO/FIXME without issue reference"
  - "hardcoded credentials or API keys"
  - "disabled security checks"
  - "skipped tests without documented reason"
  - "changes to forbidden paths"
  - "breaking contract changes without migration plan"
  - "console.log / print() in production code"
  - "empty catch blocks"
  - "direct SQL queries outside of repository classes"    # project-specific
  - "import from ../../../ (use path aliases)"            # project-specific
```

---

## curator_auto_rules

After each EPIC, the Curator agent generates improvement proposals. This section controls which proposals the Curator auto-approves, auto-rejects, or auto-defers before they reach you.

This reduces the number of proposals requiring your attention.

### `always_approve`

Proposals matching these rules are approved automatically:

```yaml
always_approve:
  - { type: dx }                         # All DX improvements — always safe to apply
  - { type: security, priority: high }   # High-priority security issues — apply immediately
  - { area: "docs/*" }                   # All documentation improvements — always safe
```

You can teach the Curator new auto-approval rules during PM approval. When you respond `"always approve {type: performance}"` at a PM_APPROVAL prompt, the Curator adds it here.

### `always_reject`

Proposals matching these rules are rejected without review. Empty by default. Example use:

```yaml
always_reject:
  - { type: refactoring, area: "legacy/*" }  # Never refactor legacy/ — it's being replaced
```

### `always_defer`

Proposals matching these rules are deferred to the backlog for future planning:

```yaml
always_defer:
  - { type: architecture }  # Architecture changes need a dedicated EPIC, not inline fixes
```

### `default_action`

What happens when no rule matches and the Qdrant learning system has no history for this proposal. Options: `approve`, `defer`, or `reject`. Default is `approve`.

### `learning`

The Curator uses Qdrant vector memory to learn from your past decisions. When you approve or reject a proposal, that decision is stored. Future proposals similar to past decisions are handled automatically.

- `enabled` — set to `false` to disable learning (all decisions go through `always_*` rules or `default_action`)
- `similarity_threshold` — minimum vector similarity score (0.0–1.0) for a past decision to be applied automatically. `0.80` means 80% similar or higher is enough to reuse the pattern
- `min_decisions` — minimum number of past decisions with the same action before the pattern is trusted. Default `3` prevents a single outlier from becoming a rule

---

## Related

- [gates.yaml](./gates-yaml) — gate commands that produce the results these policies act on
- [dispatch-strategy.yaml](./dispatch-strategy) — parallel execution configuration
- [Curator Agent](../agents/curator) — the agent that applies `curator_auto_rules`
- [Epic Orchestration](../skills/epic-orchestration) — Controller state machine that reads these policies
- [Improvement Proposals](../skills/improvement-proposals) — how proposals are generated and evaluated
