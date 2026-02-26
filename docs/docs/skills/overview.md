---
sidebar_position: 1
title: "Skills Reference Overview"
description: "Overview of AID's 21 skills — the behavioral modules that define how agents think, plan, execute, and coordinate during EPIC-driven development."
---

# Skills Reference Overview

Skills are the behavioral modules that give AID agents their capabilities. Where agents are roles (architect, backend, QA, and others), skills are the protocols those roles follow: how to plan before coding, how to run quality gates, how to dispatch agents in parallel, how to acquire knowledge, and how to communicate with the PM.

Skills are loaded on demand — agents load only the skills relevant to their current task rather than loading everything at startup. This keeps context windows lean and makes each agent's behavior explicit.

## How the Skill System Works

Every skill is a markdown file in `plugins/aid-orchestrator/skills/`. When an agent or the Controller needs a specific protocol, it loads the relevant skill and follows its instructions. The `agent-core` skill is the only skill loaded for every run by default — it defines the baseline rules and the on-demand loading table for all other skills.

Skills reference each other explicitly. For example, `epic-orchestration` calls `planner` for plan generation, `parallel-dispatch` for concurrent agents, `gates-engine` for gate execution, and `retry-engine` for gate failure recovery. This dependency structure is documented in each skill's "Related" section and in the skill's source file header.

## Skill Categories

### Core Pipeline

These skills form the backbone of every EPIC execution:

| Skill | Description |
|---|---|
| [Agent Core](./agent-core) | Foundational rules for all agents: run start protocol, role mindset framework, commit rules, on-demand skill loading |
| [Epic Orchestration](./epic-orchestration) | Controller state machine driving EPIC lifecycle from PLANNING through DONE |
| [Planner](./planner) | Converts EPIC specs into validated Plan JSON with dependency graphs, waves, and analysis groups |
| [Run Management](./run-management) | Run file lifecycle, document hierarchy (plan/epic/run), ID system, and lifecycle protocols |
| [Quality Gates](./quality-gates) | Pre-commit 6-gate protocol: log analysis, docs impact, cleanup, git status, commit format, tests |
| [Gates Engine](./gates-engine) | Post-step quality gates from `gates.yaml` — command and rule gates with structured reporting |
| [Retry Engine](./retry-engine) | Failure analysis and gate-fixer dispatch for gate retry cycles |

### Quality and Safety

These skills enforce quality, handle failures, and maintain improvement feedback loops:

| Skill | Description |
|---|---|
| [Improvement Proposals](./improvement-proposals) | Standard format for agent observations, Curator deduplication, and backlog integration |
| [Analysis Merge](./analysis-merge) | Consolidates multi-agent review findings using union, consensus, or weighted strategies |
| [Parallel Dispatch](./parallel-dispatch) | Branch management and concurrent agent execution with conflict detection |

### Intelligence and Optimization

These skills make AID smarter and faster over time:

| Skill | Description |
|---|---|
| [Memory MCP](./memory-mcp) | Long-term vector memory via Qdrant — stores and retrieves decisions, lessons, and patterns |
| [Knowledge Acquisition](./knowledge-acquisition) | Research pipeline for framework documentation with quality gates and dual storage |
| [Analytics](./analytics) | Execution metrics reports: bottleneck analysis, gate efficiency, token trends |
| [Cost Optimization](./cost-optimization) | Model selection, file scoping, and dispatch trimming for 30-50% speed improvement |
| [Brainstorming](./brainstorming) | Interactive design sessions with structured questions, approach exploration, and EPIC draft generation |
| [Workflow Intelligence](./workflow-intelligence) | Platform detection and domain-specific guidance for AI workflow and agent projects |

### Autonomous Execution (FIRST AID)

These skills power the FIRST AID autonomous execution mode:

| Skill | Description |
|---|---|
| [Epic Queue](./epic-queue) | Persistent YAML queue for autonomous multi-EPIC pipeline execution |
| [Auto Done State](./auto-done-state) | Autonomous DONE state: deterministic release decisions, queue transitions, session reports |
| [Auto Escalation](./auto-escalation) | 16-trigger escalation protocol for FIRST AID auto-mode — the only mandatory PM touchpoint |
| [Permission Sandwich](./permission-sandwich) | Permission lifecycle: backup, elevate, restore cycle around auto-mode sessions |

### Integration

These skills handle external system communication:

| Skill | Description |
|---|---|
| [Slack MCP](./slack-mcp) | PM communication via Slack MCP server with chat fallback for all orchestrator messages |

## All 21 Skills at a Glance

| Skill | Category | Purpose |
|---|---|---|
| [Agent Core](./agent-core) | Core Pipeline | Baseline rules for all agents |
| [Analysis Merge](./analysis-merge) | Quality and Safety | Multi-agent finding consolidation |
| [Analytics](./analytics) | Intelligence and Optimization | Execution metrics and bottleneck reports |
| [Auto Done State](./auto-done-state) | Autonomous Execution | FIRST AID DONE state behavior |
| [Auto Escalation](./auto-escalation) | Autonomous Execution | FIRST AID escalation protocol |
| [Brainstorming](./brainstorming) | Intelligence and Optimization | Interactive design and planning sessions |
| [Cost Optimization](./cost-optimization) | Intelligence and Optimization | Speed and token efficiency |
| [Epic Orchestration](./epic-orchestration) | Core Pipeline | Controller state machine |
| [Epic Queue](./epic-queue) | Autonomous Execution | Multi-EPIC pipeline queue |
| [Gates Engine](./gates-engine) | Core Pipeline | Post-step quality gate execution |
| [Improvement Proposals](./improvement-proposals) | Quality and Safety | Agent observations and backlog pipeline |
| [Knowledge Acquisition](./knowledge-acquisition) | Intelligence and Optimization | Framework documentation research |
| [Memory MCP](./memory-mcp) | Intelligence and Optimization | Long-term vector memory |
| [Parallel Dispatch](./parallel-dispatch) | Quality and Safety | Concurrent agent execution |
| [Permission Sandwich](./permission-sandwich) | Autonomous Execution | Auto-mode permission lifecycle |
| [Planner](./planner) | Core Pipeline | EPIC to Plan JSON conversion |
| [Quality Gates](./quality-gates) | Core Pipeline | Pre-commit 6-gate protocol |
| [Retry Engine](./retry-engine) | Core Pipeline | Gate failure retry and escalation |
| [Run Management](./run-management) | Core Pipeline | Run file lifecycle and protocols |
| [Slack MCP](./slack-mcp) | Integration | PM communication via Slack |
| [Workflow Intelligence](./workflow-intelligence) | Intelligence and Optimization | AI workflow project guidance |

## Loading Skills

Skills are loaded on demand. The `agent-core` skill's on-demand loading table lists which skill to load for each situation:

```text
Run start/end, handoffs          → run-management
Pre-commit quality check         → quality-gates
EPIC execution (Controller)      → epic-orchestration
Post-step quality gates          → gates-engine
Gate failure retry               → retry-engine
Plan generation from EPIC        → planner
Parallel agent dispatch          → parallel-dispatch
Multi-agent finding consolidation → analysis-merge
Curator improvement notes        → improvement-proposals
Slack PM communication           → slack-mcp
EPIC queue management            → epic-queue
Qdrant vector memory             → memory-mcp
Framework documentation research → knowledge-acquisition
Token and speed optimization     → cost-optimization
```

Load only what you need. Do not load all skills at once.
