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

Every module **mutates files created by `/aid-init`**; `/aid-setup` never creates the workspace and
never runs migrations or upgrades — those are init-owned.

## Where setup writes

The state root is the **primary checkout**, resolved per `lib/aid-roots.sh` semantics — never a
linked worktree. Running `/aid-setup` from inside `.aid-worktrees/plan-*` therefore edits the
**primary checkout's** `.aid-o/config/`, not a copy local to the worktree. `CLAUDE.md` is the one
target outside `.aid-o/`; it is written at the primary checkout's project root for the same reason.

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

## File ownership

Each file below is created by `/aid-init`; subsequent changes are owned by the `/aid-setup` module
named here. `/aid-init` re-runs never rewrite them.

| File | Created by | Later changes owned by | Notes |
|------|-----------|------------------------|-------|
| `.aid-o/config/permissions.yaml` | `/aid-init` (from template) | `/aid-setup permissions` | preset and per-setting changes |
| `.aid-o/config/project.yaml` | `/aid-init` (auto-detection) | `/aid-setup scan` | one delegated writer: `agents/project-scanner.md` (Quick Scan Mode A, triggered by this module; Deep Analysis Mode B, Orchestrator-triggered post-milestone, extends the same auto-detected sections). Merge rule from `skills/setup/project-scan.md` governs: auto-detected sections are replaced, PM-added custom fields are never overwritten. `skills/memory.md`'s "NEVER write to project.yaml" binds memory agents, not the scanner. |
| `.aid-o/config/integrations.yaml` | `/aid-init` (only `memory.enabled: true`) | `/aid-setup integrations` | every enable/disable after creation |
| `CLAUDE.md` | not created by `/aid-init` | `/aid-setup claude-md` | sole AID writer; never overwrites PM-authored content |

**Not here: `gate_profiles` upgrade for an existing `execution.yaml`.** `(4) Project Scan` /
`scan` re-detects `test_cmd`/`lint_cmd`/`build_cmd` in `project.yaml` — it does not touch
`config/execution.yaml`. The non-destructive, PM-confirmed `gate_profile_defaults`/`gate_profiles`
upgrade for a project's existing `execution.yaml` (P061 D9) is owned entirely by `/aid-init`
(see `commands/aid-init.md` → "Existing Project — gate_profiles Upgrade"), since `/aid-init` is
already the sole writer of that file's initial content — keeping both the create and the upgrade
path in one command avoids two commands independently deciding what belongs in `gates:`.

## Important

- **Requires /aid-init first** — setup configures, init creates
- **Re-runnable** — safe to run any module multiple times
- **Non-destructive** — always shows changes and asks PM before writing
- **Modular** — each module is independent, load only what's needed


**Last Updated:** 2026-08-11
