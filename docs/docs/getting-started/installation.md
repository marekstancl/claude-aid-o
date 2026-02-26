---
sidebar_position: 1
title: "Installation"
description: "Install the AID Orchestrator plugin for Claude Code and verify your setup."
---

# Installation

AID Orchestrator is a Claude Code plugin. You install it through the Claude Code plugin marketplace with two commands, and it is ready to use in any of your projects.

## Prerequisites

Before installing, make sure you have the following:

- **Node.js 18 or later** — required by the Claude Code CLI. Check with `node --version`.
- **npm or bun** — for any projects where AID will run JavaScript/TypeScript gates. Either package manager works.
- **Claude Code CLI** — AID is a Claude Code plugin and requires Claude Code to run. Install or update it from [claude.ai/code](https://claude.ai/code).
- **A git repository** — AID requires an initialized git repository in your project. It uses git to manage worktrees for parallel agent execution and to track evidence. Run `git init` in your project root if you have not done so already.

## Install the Plugin

Open a terminal in any project directory and run these two commands inside Claude Code:

```
/plugin marketplace add marekstancl/claude-aid-o
```

This registers the AID marketplace source with your Claude Code installation. You only need to do this once — it is available for all future projects afterward.

```
/plugin install aid-orchestrator@claude-aid-o
```

This installs the AID Orchestrator plugin from the registered marketplace. Claude Code downloads the plugin and makes all AID commands available immediately.

## Verify the Installation

Run the help command to confirm the plugin loaded correctly:

```
/aid-help
```

You should see the AID documentation and a list of all 13 available commands. If you see `Unknown command: /aid-help`, the plugin did not load — try closing and reopening your terminal, then run the install command again.

## What Gets Installed

The plugin itself lives in Claude Code's plugin cache (`~/.claude/plugins/`). It adds 13 slash commands to your Claude Code session:

| Command | Purpose |
|---------|---------|
| `/aid-init` | Initialize the `.aid-o/` workspace in your project |
| `/aid-setup` | Interactive project onboarding |
| `/aid-brainstorm` | Collaborative brainstorming to create plans and EPICs |
| `/aid-plan-epic` | Generate an execution plan from an EPIC |
| `/aid-run-epic` | Execute the full EPIC orchestration pipeline |
| `/aid-first-aid` | Autonomous queue execution mode |
| `/aid-stop` | Emergency stop — restore permissions, save progress |
| `/aid-epic-queue` | Manage the EPIC execution queue |
| `/aid-epic-status` | Show pipeline status for a running EPIC |
| `/aid-analytics` | Performance metrics and optimization recommendations |
| `/aid-audit` | Project health audit (0–100 score) |
| `/aid-research` | On-demand documentation research |
| `/aid-help` | AID documentation and help |

The plugin does **not** write any files to your project until you run `/aid-init`. Installation is non-destructive.

## Next Steps

With the plugin installed, move to your project directory and follow the [Quick Start guide](./quick-start) to initialize your workspace and run your first EPIC.
