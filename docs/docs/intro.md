---
sidebar_position: 1
title: AID Orchestrator
description: "Multi-Agent Development Orchestration for Claude Code — Controller + Workers architecture for AI-driven software development."
slug: /
---

# AID Orchestrator

**Multi-Agent Development Orchestration for Claude Code.**

AID is a Claude Code plugin that implements a **Controller + Workers architecture** for AI-driven software development. It takes an EPIC specification, generates structured execution plans, dispatches specialized role-based agents, enforces quality gates, and maintains complete evidence trails.

## Features

- **13 slash commands** for planning, executing, auditing, and managing your development pipeline
- **18 specialized agents** (architect, backend, frontend, QA, security, and more) dispatched based on step requirements
- **21 reusable skills** encoding orchestration patterns, quality gates, retry logic, and memory management
- **Quality gates** enforced between phases — type checks, linting, tests, builds, security scans
- **FIRST AID mode** for fully autonomous EPIC queue execution with escalation-only PM interaction
- **Evidence trails** capturing every decision, artifact, and outcome for auditability
- **Qdrant vector memory** for cross-project knowledge persistence and retrieval

## Quick Start

```bash
# Install the plugin
/plugin marketplace add marekstancl/claude-aid-o
/plugin install aid-orchestrator@claude-aid-o

# Initialize and configure your project
/aid-init
/aid-setup

# Plan and execute an EPIC
/aid-brainstorm
/aid-plan-epic
/aid-run-epic
```

See the [Installation Guide](getting-started/installation) for prerequisites and detailed setup.

## How It Works

AID follows a **Controller + Workers** pattern:

1. **Planning** — The Controller reads your EPIC spec and generates a dependency-aware execution plan with parallel wave grouping.
2. **Dispatch** — Specialized agents (architect, backend, frontend, QA, etc.) are dispatched to execute individual steps within scoped boundaries.
3. **Quality Gates** — After each phase, 6 quality gates are enforced: type checks, linting, tests, builds, security scans, and documentation checks.
4. **Review** — The PM reviews completed work at key checkpoints. Failed steps trigger retry with automated analysis.
5. **Evidence** — Every step produces evidence artifacts (plans, reports, logs) stored in `.aid-o/04-engine/evidence/`.

## Documentation Sections

| Section | What You'll Find |
|---------|-----------------|
| [Getting Started](getting-started/installation) | Installation, first EPIC walkthrough, configuration |
| [Architecture](architecture/overview) | Pipeline design, state machine, quality gates, memory system, FIRST AID |
| [Commands](commands/aid-init) | Reference for all 13 slash commands |
| [Agents](agents/overview) | Reference for all 18 specialized agents |
| [Skills](skills/overview) | Reference for all 21 orchestration skills |
| [Configuration](configuration/gates-yaml) | Field-by-field reference for policy files |
| [Contributing](contributing/how-to-contribute) | How to add commands, agents, and contribute |
| [Troubleshooting](troubleshooting/common-issues) | Common issues and FAQ |
