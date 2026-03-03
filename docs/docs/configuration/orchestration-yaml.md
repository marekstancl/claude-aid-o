---
sidebar_position: 2
title: "orchestration.yaml"
description: "Reference for orchestration.yaml — language, model tiers, dispatch strategy, escalation, FSM, release policy, and skill conflict resolution."
---

# orchestration.yaml

**Location:** `.aid-o/config/orchestration.yaml`

This file configures the Controller itself: how it communicates, which models it assigns to agents, how it dispatches work, how the finite state machine operates, and how releases are managed. It consolidates what v1 split across `language.yaml`, `dispatch-config.yaml`, `dispatch-strategy.yaml`, `release-policy.yaml`, and `skill-conflicts.yaml`.

The Controller reads `orchestration.yaml` at the start of every session. Changes take effect on the next `/aid-run` or `/aid-plan` invocation.

---

## Full Default Configuration

Source: `plugins/aid-orchestrator/defaults/orchestration.yaml`

```yaml
# AID Orchestration Configuration (v2)
# Consolidated from: language.yaml, dispatch-config.yaml, dispatch-strategy.yaml,
#                    release-policy.yaml, skill-conflicts.yaml
#
# Controls: language, model tiers, dispatch strategy, escalation, FSM,
#           release policy, and skill conflict resolution.

# ─── Language ────────────────────────────────────────────────────────────
language:
  document_language: EN
  conversation_language: auto  # detected from PM input

# ─── Models ──────────────────────────────────────────────────────────────
# Simplified role→tier mapping. See dispatch-protocol skill for consumption.
models:
  opus: [architect, backend, frontend]
  sonnet: [qa, security, docs-writer, curator, auditor, implementer, verifier]
  haiku: [gate-fixer, run-validator]

# ─── Dispatch ────────────────────────────────────────────────────────────
dispatch:
  strategy: worktrees
  max_parallel: 4
  worktree_base: .claude/worktrees

# ─── Escalation ─────────────────────────────────────────────────────────
escalation:
  max_per_session: 3
  triggers:
    - gate_retry_exhausted
    - security_required_fail
    - scope_violation

# ─── FSM ─────────────────────────────────────────────────────────────────
fsm:
  states: [READY, EXECUTE, GATES, ESCALATION, DONE]
  state_file: .aid-o/work/evidence/{epic_id}/{run_id}/state.yaml
  timeline_file: .aid-o/work/evidence/{epic_id}/{run_id}/timeline.jsonl

# ─── Release Policy ─────────────────────────────────────────────────────
# Versioning, SemVer rules, and release automation settings.
release:
  versioning:
    mode: single
    changelog: CHANGELOG.md

  version_files:
    - path: ".claude-plugin/marketplace.json"
      field: "metadata.version"
      update_method: json_field
    - path: ".claude-plugin/marketplace.json"
      field: "plugins[0].version"
      update_method: json_field
    - path: "plugins/aid-orchestrator/.claude-plugin/plugin.json"
      field: "version"
      update_method: json_field
    - path: "plugins/aid-orchestrator/README.md"
      field: "plugin_version"
      update_method: regex
      pattern: '^\- \*\*Plugin:\*\* [\d.]+'
      replacement: '- **Plugin:** ${version}'
    - path: "README.md"
      field: "roadmap_current"
      update_method: regex
      pattern: '^\- \*\*v[\d.]+\*\* \(current\)'
      replacement: '- **v${version}** (current)'

  semver:
    pre_release: true
    changelog_header_pattern: '## \[(\d+\.\d+\.\d+)\]'

  multi_phase:
    last_epic: mandatory
    intermediate_epic: pm_choice
    standalone_epic: mandatory

  first_aid:
    intermediate_action: defer
    last_epic_action: release
    on_error: escalate

  settings:
    git_tag: true
    github_release: true
    draft_release: false
    auto_tag: true
    auto_release: true

  commit:
    message_template: "release: v${version} — ${summary}"

  skip_when:
    no_changelog_version: true
    versions_current: true

# ─── Skill Conflicts ────────────────────────────────────────────────────
# Known conflicts between plugins/skills. Used by /aid-setup.
skill_conflicts:
  - id: "brainstorming-duplicate"
    prefer: "aid-orchestrator:aid-brainstorm"
    deny: "superpowers:brainstorming"
    reason: "Both provide brainstorming workflow. AID version is integrated with orchestration pipeline."
    severity: high
```

---

## Field Reference

### language

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `document_language` | string | `EN` | Language for generated documentation, plans, and reports. |
| `conversation_language` | string | `auto` | Language for PM communication. `auto` detects from PM input. Set explicitly (e.g., `CS`, `DE`) to force a language. |

### models

Maps Claude model tiers to agent roles. The Controller uses this mapping when dispatching agents via the Task tool.

| Tier | Default roles | When to use |
|------|---------------|-------------|
| `opus` | architect, backend, frontend | Complex multi-step reasoning across large codebases. |
| `sonnet` | qa, security, docs-writer, curator, auditor, implementer, verifier | Standard tasks. Most agents belong here. |
| `haiku` | gate-fixer, run-validator | Simple, fast tasks with low complexity. |

To move an agent to a different tier, edit the role lists:

```yaml
models:
  opus: [architect, backend, frontend, security]  # Promoted security to opus
  sonnet: [qa, docs-writer, curator, auditor, implementer, verifier]
  haiku: [gate-fixer, run-validator]
```

### dispatch

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `strategy` | string | `worktrees` | Isolation mechanism for parallel agents. Options: `worktrees`, `sequential`. |
| `max_parallel` | integer | `4` | Maximum concurrent agents. Tune based on machine resources. |
| `worktree_base` | string | `.claude/worktrees` | Directory where git worktrees are created for parallel isolation. |

### escalation

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_per_session` | integer | `3` | Maximum escalations per session before automatic abort. |
| `triggers` | list | *(see config)* | Named escalation trigger events. |

### fsm

The finite state machine (FSM) controls pipeline state transitions. The bash-based FSM runner (`scripts/aid-fsm.sh`) reads these settings.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `states` | list | `[READY, EXECUTE, GATES, ESCALATION, DONE]` | Ordered list of FSM states. |
| `state_file` | string | `.aid-o/work/evidence/{epic_id}/{run_id}/state.yaml` | Path to current state file. Placeholders interpolated at runtime. |
| `timeline_file` | string | `.aid-o/work/evidence/{epic_id}/{run_id}/timeline.jsonl` | Path to timeline event log. One JSON line per state transition. |

### release

Controls version management and release automation.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `versioning.mode` | string | `single` | Version strategy. `single` = one version for entire project. |
| `versioning.changelog` | string | `CHANGELOG.md` | Path to changelog file (source of truth for version). |
| `version_files` | list | *(see config)* | Registry of files containing version numbers. All must be in sync. |
| `semver.pre_release` | boolean | `true` | Allow pre-release versions (e.g., `2.0.0-rc.1`). |
| `semver.changelog_header_pattern` | string | `## \[(\d+\.\d+\.\d+)\]` | Regex to extract version from changelog headers. |
| `multi_phase.last_epic` | string | `mandatory` | Release behavior for the last EPIC in a multi-phase plan. |
| `multi_phase.intermediate_epic` | string | `pm_choice` | Release behavior for intermediate EPICs. PM decides. |
| `multi_phase.standalone_epic` | string | `mandatory` | Release behavior for standalone (single) EPICs. |
| `first_aid.intermediate_action` | string | `defer` | What FIRST AID mode does at intermediate EPICs. |
| `first_aid.last_epic_action` | string | `release` | What FIRST AID mode does at the last EPIC. |
| `first_aid.on_error` | string | `escalate` | Error handling during automated release. |
| `settings.git_tag` | boolean | `true` | Create git tag on release. |
| `settings.github_release` | boolean | `true` | Create GitHub release. |
| `settings.auto_tag` | boolean | `true` | Auto-create tag without PM confirmation. |
| `settings.auto_release` | boolean | `true` | Auto-create release without PM confirmation. |
| `commit.message_template` | string | `release: v${version} — ${summary}` | Template for release commit messages. |
| `skip_when.no_changelog_version` | boolean | `true` | Skip release if no new version in changelog. |
| `skip_when.versions_current` | boolean | `true` | Skip release if all version files already match. |

### skill_conflicts

Known conflicts between plugins. Used by `/aid-init` and `/aid-help` to warn users.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique conflict identifier. |
| `prefer` | string | Plugin:command that should be used. |
| `deny` | string | Plugin:command that should be disabled. |
| `reason` | string | Why this conflict exists. |
| `severity` | string | `high` = blocks setup, `low` = warning only. |

---

## Customization Tips

### Reducing parallelism for resource-constrained machines

```yaml
dispatch:
  strategy: worktrees
  max_parallel: 2  # Only 2 concurrent agents
```

### Disabling parallelism entirely

```yaml
dispatch:
  strategy: sequential
  max_parallel: 1
```

### Promoting an agent to a higher model tier

If the verifier agent needs deeper reasoning for your codebase:

```yaml
models:
  opus: [architect, backend, frontend, verifier]
  sonnet: [qa, security, docs-writer, curator, auditor, implementer]
  haiku: [gate-fixer, run-validator]
```

### Using a different conversation language

```yaml
language:
  document_language: EN
  conversation_language: CS  # Czech
```

### Customizing release for monorepo

```yaml
release:
  versioning:
    mode: single
    changelog: CHANGELOG.md
  version_files:
    - path: "package.json"
      field: "version"
      update_method: json_field
    - path: "pyproject.toml"
      field: "tool.poetry.version"
      update_method: toml_field
```

---

## Related

- [FSM architecture](../architecture/fsm) — state machine details and transition diagrams
- [Execution modes](../architecture/execution-modes) — how dispatch strategy affects pipeline behavior
- [execution.yaml](./execution-yaml) — quality gates and decision policies
- [integrations.yaml](./integrations-yaml) — external service configuration
