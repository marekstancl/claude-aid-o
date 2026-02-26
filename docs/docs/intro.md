---
id: intro
title: AID Orchestrator
sidebar_label: Introduction
sidebar_position: 1
slug: /
---

# AID Orchestrator

**Multi-Agent Development Orchestration for Claude Code.**

AID is a Claude Code plugin that implements a **Controller + Workers architecture** for AI-driven software development. It takes an EPIC specification, generates structured execution plans, dispatches specialized role-based agents, enforces quality gates, and maintains complete evidence trails.

## What You Will Find Here

- **Getting Started** -- Installation, quick start guide, and configuration reference.
- **Commands** -- Detailed documentation for all 13 slash commands.
- **Agents** -- Reference for all 18 specialized agents dispatched during EPIC execution.
- **Skills** -- Documentation for all 21 reusable orchestration skills.

## Quick Overview

```bash
# Install the plugin
/plugin marketplace add marekstancl/claude-aid-o
/plugin install aid-orchestrator@claude-aid-o

# Initialize a project
/aid-init

# Set up the project
/aid-setup

# Plan and run an EPIC
/aid-plan-epic
/aid-run-epic
```

## Architecture

AID follows a **Controller + Workers** pattern:

1. The **Controller** (epic-orchestration skill) reads the EPIC plan and dispatches steps to specialized agents.
2. **Agents** (architect, backend, frontend, QA, etc.) execute individual steps within defined boundaries.
3. **Quality Gates** enforce standards between phases -- code review, security checks, test coverage.
4. **Evidence Trails** capture every decision, artifact, and outcome for auditability.

---

*This documentation is a work in progress. Pages will be populated as the documentation site is built out.*
