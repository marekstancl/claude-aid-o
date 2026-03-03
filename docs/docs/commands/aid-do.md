---
sidebar_position: 2
title: "/aid-do"
description: "Fast Mode — implement small tasks with minimal overhead (<2 min)"
---

# /aid-do

Implement a task directly with minimal overhead. No planning, no EPIC, no FSM -- just do it and log it. For tasks estimated under 2 hours of work.

Creates a quick log entry (`Q-NNN.md`) and auto-escalates to `/aid-plan` if scope grows beyond threshold.

## Usage

```bash
/aid-do <task description>
```

### Examples

```bash
# Debug a specific flow
/aid-do "add a console.log to debug auth flow"

# Quick fix
/aid-do "fix typo in README"

# Small feature
/aid-do "add login button with Google OAuth"
```

If no task description is provided, AID asks what to implement.

## What It Does

```mermaid
flowchart TD
    A[/aid-do 'task'] --> B{.aid-o/ exists?}
    B -- No --> C[Auto-run /aid-init]
    C --> D
    B -- Yes --> D[Scope Estimate]
    D --> E{> 5 files OR 3+ layers?}
    E -- Yes --> F[Offer escalation to /aid-plan]
    E -- No --> G[Implement task]
    G --> H[Post-implementation check]
    H --> I{Actual scope exceeded?}
    I -- Yes --> J[Warn PM, suggest retroactive plan]
    I -- No --> K[Write Q-NNN.md quick log]
    J --> K
    K --> L[Git commit]
    L --> M["Done: Q-NNN (duration, files)"]
    F -- PM chooses B --> N[Hand off to /aid-plan]
    F -- PM chooses A --> G
```

### Step-by-step

1. **Auto-Init** -- if `.aid-o/` does not exist, runs `/aid-init` silently
2. **Scope Estimate** -- analyzes task description, estimates affected files and architectural layers (frontend, backend, DB, config, infra). If > 5 files or 3+ layers, offers escalation to `/aid-plan`
3. **Implement** -- writes code, modifies files, runs tests. Follows existing project patterns
4. **Post-Implementation Check** -- runs `git diff --stat` to verify actual scope. Warns if threshold exceeded
5. **Quick Log** -- writes `.aid-o/work/quick/Q-{NNN}.md` with task summary, duration, files changed, and commit hash
6. **Git Commit** -- stages and commits: `feat: {task description} (Q-{NNN})`

## Quick Log Format

Each `/aid-do` produces a log file at `.aid-o/work/quick/Q-{NNN}.md`:

```yaml
---
id: Q-001
task: "add login button with Google OAuth"
started_at: 2026-03-03T10:00:00Z
duration_s: 180
files_changed:
  - src/components/LoginButton.tsx
  - src/auth/google.ts
commit: a1b2c3d
escalated_to_epic: false
---

## What was done
Added Google OAuth login button to the auth page...
```

## Auto-Escalation Triggers

These conditions suggest the task should have been planned:

| Trigger | Detection | Action |
|---------|-----------|--------|
| > 5 files changed | `git diff --stat` post-implementation | Warn PM, suggest retroactive plan |
| 3+ layers touched | Path analysis of changed files | Warn PM, suggest retroactive plan |
| DB migration created | Migration file in changed files | Warn PM |
| PM says "this is bigger" | Explicit PM statement | Offer `/aid-plan` handoff |

Escalation is always a **suggestion** -- PM decides whether to act on it.

## Key Behaviors

- **No FSM** -- Fast Mode bypasses the state machine entirely
- **No EPIC** -- no evidence directory, no run file, no plan.json
- **Quick log only** -- `.aid-o/work/quick/Q-NNN.md` is the sole artifact
- **Auto-increment Q counter** -- scans existing files, never overwrites
- **Git commit is mandatory** -- every `/aid-do` produces exactly one commit

## Related Commands

- [`/aid-plan`](./aid-plan) -- escalation target when scope exceeds Fast Mode threshold
- [`/aid-init`](./aid-init) -- auto-invoked on first use if workspace missing
- [`/aid-status`](./aid-status) -- shows recent quick tasks in overview
