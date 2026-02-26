---
sidebar_position: 7
title: "/aid-help"
description: "Show AID documentation and help topics"
---

# /aid-help

Show AID documentation — commands, workflow, agent roles, configuration options, and FAQ. This is AID's self-knowledge command: it explains how the entire system works without requiring you to read the source files.

## Usage

```bash
/aid-help [topic]
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `topic` | string | No | Specific topic to display. If omitted, shows a full overview. |

## Available Topics

| Topic | What It Covers |
|-------|---------------|
| `commands` | Detail on every command |
| `workflow` | Plan → EPIC → Run flow |
| `epic` | How to write an EPIC |
| `agents` | 18 agent roles and specialists |
| `planning` | Planner, parallelization, analysis groups |
| `gates` | Quality gates and retry logic |
| `evidence` | Evidence store structure |
| `config` | Configuration files |
| `slack` | Slack integration and PM communication |
| `queue` | EPIC queue and autonomous pipeline |
| `memory` | Qdrant vector memory and semantic search |
| `analytics` | Performance analysis of orchestration metrics |
| `inputs` | Input files for brainstorming |
| `examples` | Interactive project prompts to try `/aid-brainstorm` |
| `faq` | Frequently asked questions |

## Examples

```bash
# Full overview of everything
/aid-help

# How the Plan → EPIC → Run workflow works
/aid-help workflow

# Details on all 18 agent roles
/aid-help agents

# How quality gates and retries work
/aid-help gates

# FAQ
/aid-help faq
```

## How It Works

The command checks whether a `.aid-o/` workspace exists in the current project, then presents the requested topic as formatted text in chat. If the workspace is initialized, it includes live counts of active EPICs and recent runs in the overview.

## Related

- [`/aid-setup`](./aid-setup) — interactive onboarding for new projects
- [`/aid-init`](./aid-init) — initialize the `.aid-o/` workspace
