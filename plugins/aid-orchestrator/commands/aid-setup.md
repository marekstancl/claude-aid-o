---
name: aid-setup
description: Modular project configuration — permissions, integrations, CLAUDE.md, stack scan
user_invocable: true
---

Configure AID for this project. Modular — run all or pick one module.

## Usage

```
/aid-setup                    # interactive menu
/aid-setup permissions        # configure permission preset
/aid-setup integrations       # enable/disable MCP integrations
/aid-setup claude-md          # generate/update CLAUDE.md
/aid-setup scan               # re-detect project stack
/aid-setup all                # run all modules sequentially
```

## Prerequisites

`.aid-o/` must exist. If not, run `/aid-init` first.

```
CHECK: Does .aid-o/config/project.yaml exist?
  NO  → "Workspace not initialized. Run /aid-init first." → EXIT
  YES → continue
```

## Routing

Parse `$ARGUMENTS`:

| Argument | Action |
|----------|--------|
| (empty) | Show menu, ask PM to pick |
| `permissions` | Read `skills/setup/permissions.md`, execute |
| `integrations` | Read `skills/setup/integrations.md`, execute |
| `claude-md` | Read `skills/setup/claude-md.md`, execute |
| `scan` | Read `skills/setup/project-scan.md`, execute |
| `all` | Execute sequentially: scan → permissions → integrations → claude-md |

## Interactive Menu

When no argument provided:

1. Read `active_preset` from `.aid-o/config/permissions.yaml`
2. Count enabled integrations from `.aid-o/config/integrations.yaml` (count keys where `enabled: true`)
3. Check if `CLAUDE.md` exists in project root

Present:

```
AID Setup — Project Configuration
==================================
  (1) Permissions     — choose autonomy level (current: {active_preset})
  (2) Integrations    — enable MCP servers ({enabled_count} enabled)
  (3) CLAUDE.md       — generate project context file ({exists|missing})
  (4) Project Scan    — re-detect tech stack
  (A) All             — run everything (recommended for first setup)
  (0) Exit

Select:
```

## Module Execution

For each selected module:
1. Read the skill file from `skills/setup/{module}.md`
2. Follow its Flow section exactly
3. Report result to PM
4. If running `all` → continue to next module automatically

## Reference Files

- `skills/setup/permissions.md` — permission preset configuration
- `skills/setup/integrations.md` — MCP server detection and enablement
- `skills/setup/claude-md.md` — CLAUDE.md generation
- `skills/setup/project-scan.md` — tech stack re-detection
- `defaults/policies/permissions.yaml` — preset definitions (autonomous, aspirin, steroids)
- `defaults/integrations.yaml` — integration config template

## Important

- **Requires /aid-init first** — setup configures, init creates
- **Re-runnable** — safe to run any module multiple times
- **Non-destructive** — always shows changes and asks PM before writing
- **Modular** — each module is independent, load only what's needed


**Last Updated:** 2026-03-04
