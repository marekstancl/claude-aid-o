---
name: aid-help
description: AID help with progressive disclosure (Level 0–3)
user_invocable: true
---

Show AID documentation with progressive disclosure — new users see 3 commands, power users see everything.

## Usage

```
/aid-help           # show your level (auto-detected from usage history)
/aid-help <topic>   # jump to topic: do, run, plan, status, gates, config, fsm
```

## Level Detection

Auto-detect user level from workspace state:

| Condition | Level |
|-----------|-------|
| No `.aid-o/` or 0 completed tasks | Level 0: Getting Started |
| 1–4 completed tasks (Q-NNN + done EPICs) | Level 1: Working with Tasks |
| 5+ completed tasks | Level 2: Configuration |
| Custom gates configured OR `autonomous_mode: true` | Level 3: Power User |

Count completed tasks:
- Quick logs: count files in `.aid-o/work/quick/Q-*.md`
- Task runs: count `state: DONE` in `.aid-o/work/evidence/*/*/fsm-state.yaml`

Show all levels up to and including the detected level.

## Level 0: Getting Started (0 tasks completed)

```
AID Orchestrator — Getting Started
====================================

Commands you need:
  /aid-do "task"    → Implement in < 2 min. No planning overhead.
  /aid-run          → Full pipeline. For complex multi-step work.
  /aid-status       → See what's running or queued.
  /aid-setup        → Configure permissions, integrations, CLAUDE.md.

Start here: /aid-do "your first task"
First time? Run /aid-setup to configure your project.
Need planning first? /aid-plan
```

## Level 1: Working with Tasks (1–4 tasks completed)

```
Queue management:
  /aid-status queue add .aid-o/tasks/E-001.md   → queue EPIC

Planning:
  /aid-plan                → brainstorm + write plan (auto-detect)
  /aid-plan write spec.md  → write plan from spec file
  /aid-plan epic plan.md   → generate EPICs from plan
```

## Level 2: Configuration (5+ tasks completed)

```
Setup: /aid-setup → configure permissions, integrations, CLAUDE.md, stack scan
  /aid-setup permissions    → choose autonomy level (autonomous/custom)
  /aid-setup integrations   → enable/disable MCP servers
  /aid-setup claude-md      → generate project context file
  /aid-setup scan           → re-detect tech stack

Gates: edit .aid-o/config/execution.yaml → customize test/lint/build commands
Project profile: .aid-o/config/project.yaml → stack, test/lint/build commands
Permissions: .aid-o/config/permissions.yaml → autonomous_mode: true for /aid-run --auto

Audit: /aid-audit → project health score (0-100) with recommendations
```

## Level 3: Power User (custom gates or autonomous mode)

```
FSM debugging:
  /aid-status <epic-id>                    → shows fsm-state.yaml FSM state
  cat .aid-o/work/evidence/{id}/*/timeline.jsonl | jq .  → full event log

Token monitoring:
  bash {plugin_path}/scripts/lib/aid-token-count.sh {plugin_path}/skills/*.md
  → shows token count per file (target: total < 50K)

Audit: /aid-audit → project health, gate failure rates, recommendations
Emergency: /aid-stop → halt running task and enter ESCALATION state
```

## Help Topics

Detailed documentation for specific areas:

```
/aid-help do        → /aid-do deep dive (scope detection, escalation triggers)
/aid-help run       → /aid-run deep dive (6-state FSM, PRE-FLIGHT, --auto mode)
/aid-help plan      → /aid-plan deep dive (brainstorm, write, epic modes)
/aid-help status    → /aid-status deep dive (overview, EPIC detail, queue)
/aid-help gates     → gate types, execution.yaml configuration, retry logic
/aid-help config    → project.yaml, execution.yaml, permissions.yaml reference
/aid-help setup     → /aid-setup deep dive (modules, presets, integrations)
/aid-help fsm       → 6-state FSM diagram, valid transitions, fsm-state.yaml format
```

### Topic: do

```
/aid-do — Fast Mode
====================================
Scope detection: estimates files + layers before implementation
  > 5 files OR 3+ layers → offers escalation to /aid-plan

Quick log: .aid-o/work/quick/Q-NNN.md (auto-increment)
Post-check: verifies actual scope after implementation, warns if exceeded

No FSM, no EPIC, no evidence dir — just implement and log.
```

### Topic: run

```
/aid-run — EPIC Pipeline
====================================
PRE-FLIGHT (bash, before FSM):
  1. generation-readiness validates the source plan + provisional graph
  2. transaction skeleton written under the generation lock
  3. CP1 gate — ONCE per plan → generation-authority.json
  4. aid-plan-to-epic.sh → every EPIC file (verifies the authority,
     never re-runs the gate)
  5. aid-epic-to-json.sh → every plan.json + contract validation
  6. aid-generation-finalize.sh → one generation receipt
  7. aid-json-to-run.sh → execution.yaml + fsm-state.yaml, only after receipt

  Generation is ONE TRANSACTION: one PM decision covers every phase, a
  crash resumes instead of duplicating, and no FSM state or queue entry
  exists until the complete EPIC package has been verified and sealed.

6-State FSM:
  READY → EXECUTE → GATES → DONE
                 ↘ ESCALATION ↗
                       ↓
                     ERROR

Flags:
  --auto    Autonomous mode (S-effort auto-fix, L-effort always escalates)
  --resume  Resume from fsm-state.yaml after crash
  --epic    Specify EPIC ID
```

### Topic: gates

```
Quality Gates
====================================
Default gates (from config/project.yaml):
  test_cmd   → run tests
  lint_cmd   → run linter
  build_cmd  → run build

Custom gates (config/execution.yaml):
  - name: security_scan
    command: "npm audit --audit-level=high"
    required: true
    max_retries: 2

Gate retry: up to 2 attempts with gate-fixer agent between retries.
All retries exhausted → ESCALATION.
```

### Topic: config

```
Configuration Files
====================================
config/project.yaml       — project stack, commands (auto-detected by /aid-init)
config/permissions.yaml   — autonomous mode, auto-commit, auto-push
config/execution.yaml     — gate definitions (lazy-created on first /aid-run)
config/queue.yaml         — EPIC queue (lazy-created on first /aid-status queue add)
```

### Topic: fsm

```
6-State FSM Reference
====================================
Valid transitions:
  READY → EXECUTE         (PM or auto approve)
  EXECUTE → EXECUTE       (next step, internal)
  EXECUTE → GATES         (all steps done)
  EXECUTE → ESCALATION    (hard failure)
  GATES → DONE            (all gates pass)
  GATES → EXECUTE         (gate retry, max 2)
  GATES → ESCALATION      (retries exhausted)
  ESCALATION → EXECUTE    (fix applied, resume)
  ESCALATION → GATES      (skip gate)

State file: .aid-o/work/evidence/{id}/{run_id}/fsm-state.yaml
Event log: .aid-o/work/evidence/{id}/{run_id}/timeline.jsonl
```

### Topic: setup

```
/aid-setup — Project Configuration
====================================
Modular setup — run all or pick one module:

  /aid-setup permissions    → choose preset: autonomous (default) or custom
  /aid-setup integrations   → detect & enable MCP servers (Qdrant, Slack, ...)
  /aid-setup claude-md      → generate CLAUDE.md with project context
  /aid-setup scan           → re-detect tech stack, update project.yaml
  /aid-setup all            → run everything (recommended for first setup)

Permission presets:
  autonomous (default): Bash(*) + all non-destructive MCPs allowed, auto_commit: true
  custom: configure each setting manually

Prerequisite: /aid-init must run first (creates .aid-o/ workspace)
```

## Important

- **Progressive disclosure** — show only relevant levels, don't overwhelm new users
- **Level 0 = 3 commands** — /aid-do, /aid-run, /aid-status (that's all a beginner needs)
- **All commands in help exist** — never reference deleted v1 commands
- **Topics are deep dives** — show when PM asks `/aid-help <topic>`
- If `$ARGUMENTS` is empty → show auto-detected level overview
- If `$ARGUMENTS` matches a topic → show that topic section only


**Last Updated:** 2026-08-06
