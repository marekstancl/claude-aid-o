---
sidebar_position: 8
title: "/aid-help"
description: "Progressive disclosure help — Level 0 (cheat sheet) through Level 3 (architecture deep-dive)"
---

# /aid-help

Show AID documentation with progressive disclosure -- new users see 3 commands, power users see everything. Help level is auto-detected from workspace state.

## Usage

```bash
/aid-help               # Show your level (auto-detected from usage history)
/aid-help <topic>       # Jump to topic: do, run, plan, status, gates, config, fsm
```

### Examples

```bash
# Auto-detected level overview
/aid-help

# Deep dive into /aid-run
/aid-help run

# Quality gates reference
/aid-help gates

# Configuration files reference
/aid-help config

# 6-state FSM diagram and transitions
/aid-help fsm
```

## Progressive Disclosure Levels

Help level is auto-detected from workspace state:

| Condition | Level | What You See |
|-----------|-------|-------------|
| No `.aid-o/` or 0 completed tasks | **Level 0: Getting Started** | 3 commands: `/aid-do`, `/aid-run`, `/aid-status` |
| 1--4 completed tasks (Q-NNN + done EPICs) | **Level 1: Working with Tasks** | Queue management + planning modes |
| 5+ completed tasks | **Level 2: Configuration** | Gates, project profile, permissions |
| Custom gates configured OR `autonomous_mode: true` | **Level 3: Power User** | FSM debugging, token monitoring, analytics |

Completed task count is derived from:
- Quick logs: files in `.aid-o/work/quick/Q-*.md`
- Task runs: `state: DONE` in `.aid-o/work/evidence/*/*/state.yaml`

All levels up to and including the detected level are shown.

### Level 0: Getting Started

```text
AID Orchestrator — Getting Started
====================================

Commands you need:
  /aid-do "task"    → Implement in < 2 min. No planning overhead.
  /aid-run          → Full pipeline. For complex multi-step work.
  /aid-status       → See what's running or queued.

Start here: /aid-do "your first task"
Need planning first? /aid-plan
```

### Level 1: Working with Tasks

```text
Queue management:
  /aid-status queue add .aid-o/tasks/E-001.md   → queue task
  /aid-status queue pause | resume               → control auto-pickup

Planning:
  /aid-plan                → brainstorm + write plan (auto-detect)
  /aid-plan write spec.md  → write plan from spec file
  /aid-plan epic plan.md   → generate EPICs from plan
```

### Level 2: Configuration

```text
Gates: edit .aid-o/config/execution.yaml → customize test/lint/build commands
Project profile: .aid-o/config/project.yaml → stack, test/lint/build commands
Permissions: .aid-o/config/permissions.yaml → autonomous_mode: true for /aid-run --auto

Audit: /aid-audit → project health score (0-100) with recommendations
```

### Level 3: Power User

```text
FSM debugging:
  /aid-status <task-id>                    → shows state.yaml FSM state
  cat .aid-o/work/evidence/{id}/*/timeline.jsonl | jq .  → full event log

Token monitoring:
  bash scripts/aid-token-count.sh plugins/aid-orchestrator/skills/*.md
  → shows token count per file (target: total < 50K)

Emergency: /aid-stop → halt running task and enter ESCALATION state
```

## Help Topics

Detailed reference for specific areas, accessed via `/aid-help <topic>`:

| Topic | What It Covers |
|-------|---------------|
| `do` | Scope detection, escalation triggers, quick log format |
| `run` | 6-state FSM, PRE-FLIGHT pipeline, `--auto` mode |
| `plan` | Brainstorm, write, epic modes and auto-detection |
| `status` | Overview, task detail, queue management |
| `gates` | Gate types, `execution.yaml` configuration, retry logic |
| `config` | `project.yaml`, `execution.yaml`, `permissions.yaml` reference |
| `fsm` | 6-state FSM diagram, valid transitions, `state.yaml` format |

## Key Behaviors

- **Progressive disclosure** -- shows only relevant levels, avoids overwhelming new users
- **Level 0 = 3 commands** -- `/aid-do`, `/aid-run`, `/aid-status` (all a beginner needs)
- **All commands referenced exist** -- never references deleted v1 commands
- **Topics are deep dives** -- shown when PM asks `/aid-help <topic>`

## Related Commands

- [`/aid-init`](./aid-init) -- initialize workspace (if Level 0 detected)
- [`/aid-do`](./aid-do) -- the first command new users should try
