---
sidebar_position: 2
title: "Plugin Structure"
description: "Directory layout of the aid-orchestrator plugin — every directory and file explained."
---

# Plugin Structure

All plugin content lives under `plugins/aid-orchestrator/`. This document explains every directory and file naming convention you will encounter when contributing.

## Top-Level Layout

```
plugins/aid-orchestrator/
  .claude-plugin/
    plugin.json           # Plugin manifest (name, version, description, author)
  agents/                 # 7 specialized agent definitions
  commands/               # 8 slash command definitions
  skills/                 # 8 core skills (+ extras outside manifest)
  scripts/                # Bash controller layer (FSM, gates, release, pipeline)
    aid-fsm.sh            # 6-state deterministic FSM
    aid-run-gates.sh      # Quality gate runner
    aid-release.sh        # Version bump + tag automation
    aid-auto-pipeline.sh  # Master orchestration (Plan → EPICs → plan.json → run → queue)
    aid-plan-to-epic.sh   # Plan.md → EPIC.md
    aid-epic-to-json.sh   # EPIC.md → plan.json
    aid-json-to-run.sh    # plan.json → run.md
    aid-queue-add.sh      # EPIC → queue entry
    gates/                # Gate-specific scripts (scope-check.sh)
    lib/                  # Shared bash utilities (aid-stage-log.sh, aid-token-count.sh, common.sh)
    tests/                # Script tests (run-all-tests.sh)
  defaults/               # Files copied into target projects by /aid-init
    execution.yaml        # Quality gates, retry, budget, decision policies
    orchestration.yaml    # Controller settings, FSM, dispatch, release
    integrations.yaml     # Slack, Qdrant, knowledge acquisition
    policies/             # Additional policy files (permissions.yaml)
    templates/            # EPIC, Plan, and Run file templates
    examples/             # Sample project prompts for /aid-plan
  README.md               # Plugin documentation (shown in Claude Code)
  CHANGELOG.md            # Version history (must mirror root CHANGELOG.md)
```

## Plugin Manifest

**`.claude-plugin/plugin.json`** — the Claude Code plugin manifest. It declares the plugin's name, version, author, license, description, and keywords. The `version` field here must match the version in the root `CHANGELOG.md` header and all other version locations listed in `CLAUDE.md`.

```json
{
  "name": "aid-orchestrator",
  "version": "2.0.0",
  "description": "AID — AI Development Orchestrator. ...",
  "author": {
    "name": "Marek Stancl"
  },
  "license": "AGPL-3.0-only",
  "keywords": ["orchestration", "multi-agent", "quality-gates", "epic-management"]
}
```

## `agents/`

Contains one Markdown file per agent. Each file defines the agent's identity, capabilities, constraints, input/output format, and workflow. There are 7 agents:

**Parametric agents** — dispatched by the Controller during pipeline execution with role-specific parameters:

| File | Agent Role |
|------|------------|
| `implementer.md` | Parametric implementation agent — accepts a role card (backend, frontend, architect, etc.) and executes accordingly |
| `verifier.md` | Parametric verification agent — validates step output against acceptance criteria with role-aware checks |

**Utility agents** — invoked at specific points in the pipeline:

| File | Agent Role |
|------|------------|
| `gate-fixer.md` | Attempt to fix failing gates in retry loop |
| `run-validator.md` | Validate run file completeness before execution |

**Specialist agents** — invoked for specific analytical tasks:

| File | Agent Role |
|------|------------|
| `curator.md` | Process improvement proposals into the backlog |
| `auditor.md` | Post-run health audit |
| `project-scanner.md` | Analyze project structure for `/aid-init` |

## `commands/`

Contains one Markdown file per slash command. Each file defines the command's behavior in natural language for Claude Code to execute. There are 8 commands:

| File | Command | Purpose |
|------|---------|---------|
| `aid-do.md` | `/aid-do` | Fast mode — implement a small task with minimal overhead |
| `aid-plan.md` | `/aid-plan` | Brainstorm and generate an execution plan |
| `aid-run.md` | `/aid-run` | Execute full pipeline: READY → EXECUTE → GATES → DONE |
| `aid-status.md` | `/aid-status` | Show pipeline status, FSM state, and queue |
| `aid-init.md` | `/aid-init` | Initialize or upgrade `.aid-o/` workspace |
| `aid-audit.md` | `/aid-audit` | Run project health audit |
| `aid-stop.md` | `/aid-stop` | Emergency stop — save progress and halt pipeline |
| `aid-help.md` | `/aid-help` | Progressive help documentation (Level 0-3) |

## `skills/`

Contains one Markdown file per skill. Skills are reusable modules loaded by agents and commands on demand. Unlike agents (which define a role) and commands (which define user-invocable actions), skills define **how** something is done — algorithms, protocols, and decision logic.

There are 8 core skills registered in the plugin manifest:

| File | Purpose |
|------|---------|
| `pipeline.md` | Controller pipeline — the core orchestration loop |
| `agent-protocol.md` | Agent dispatch protocol — how agents are invoked and communicate |
| `role-cards.md` | Role card definitions for parametric implementer/verifier agents |
| `brainstorming.md` | Interactive brainstorming and design exploration |
| `planner.md` | Plan generation from EPIC specification |
| `quality-gates.md` | 6-gate pre-commit quality protocol |
| `run-management.md` | Run file lifecycle — create, update, archive |
| `memory.md` | Qdrant vector memory protocol |

Additional skills exist outside the manifest for internal use (analytics, improvement-proposals, plan-writing, token-estimator).

## `scripts/`

The bash controller layer provides deterministic operations that do not require LLM reasoning:

| File | Purpose |
|------|---------|
| `aid-fsm.sh` | Deterministic 6-state FSM (READY → EXECUTE → GATES → ESCALATION → DONE → ARCHIVED) |
| `aid-run-gates.sh` | Execute quality gates defined in `execution.yaml`, write `gates_report.json` |
| `aid-release.sh` | Version bump across all version files, git tag, GitHub release |
| `aid-auto-pipeline.sh` | Master orchestration: Plan → EPICs → plan.json → run → queue |
| `aid-plan-to-epic.sh` | Convert plan.md to EPIC.md |
| `aid-epic-to-json.sh` | Convert EPIC.md to plan.json |
| `aid-json-to-run.sh` | Convert plan.json to run.md |
| `aid-queue-add.sh` | Add EPIC to execution queue |
| `gates/scope-check.sh` | Deterministic scope validation gate |
| `lib/common.sh` | Shared bash functions |
| `lib/aid-stage-log.sh` | Pipeline stage logging |
| `lib/aid-token-count.sh` | Token counting utilities |

Scripts are invoked by skills and commands via the Bash tool. They handle file I/O, git operations, and gate execution — tasks where deterministic bash is more reliable than LLM-generated commands.

## `defaults/`

The `defaults/` directory contains files that are copied into target projects when users run `/aid-init`. The command scans this directory dynamically — every file you add here will automatically appear in new project workspaces.

### Top-level config files

Three YAML configuration files control all plugin behavior:

| File | Purpose |
|------|---------|
| `execution.yaml` | Quality gates, retry/escalation, budget, decision policies, content quality, acceptable debt |
| `orchestration.yaml` | Language, model tiers, dispatch strategy, FSM, release policy, skill conflicts |
| `integrations.yaml` | Slack MCP, Qdrant memory, knowledge acquisition — all optional, disabled by default |

These are copied to `.aid-o/config/` in target projects.

### `defaults/policies/`

Additional policy files that do not fit into the three main configs:

| File | Purpose |
|------|---------|
| `permissions.yaml` | Baseline tool permissions for agents |

### `defaults/templates/`

Markdown and JSON templates used to create EPIC files, Plan files, and Run files.

| File | Purpose |
|------|---------|
| `epic.md` | Template for writing an EPIC specification |
| `epic-example.md` | Annotated example EPIC for reference |
| `plan.md` | Template for a brainstorming plan document |
| `plan.schema.json` | JSON Schema for the Plan JSON generated by `/aid-plan` |
| `run-new-feature.md` | Run file template for new feature work |
| `run-bug-fix.md` | Run file template for bug fix work |
| `run-refactoring.md` | Run file template for refactoring work |
| `run-exploration.md` | Run file template for exploration/research |
| `inputs-readme.md` | README template for knowledge base inputs |
| `knowledge-base.yaml` | Knowledge base configuration template |

### `defaults/examples/`

Sample project prompts used by `/aid-plan` to give users concrete starting points. Organized into two subdirectories:

- `defaults/examples/common-projects/` — web app and API project starters (Next.js, FastAPI, SaaS, etc.)
- `defaults/examples/ai-workflows/` — AI pipeline project starters (LangChain, LangGraph, n8n, etc.)

## File Naming Conventions

- All files use **kebab-case** (e.g., `pipeline.md`, `quality-gates.md`, `run-validator.md`)
- Agent files are named after the agent role: `implementer.md`, `verifier.md`, `curator.md`
- Command files are named after the command: `aid-help.md`, `aid-run.md`
- Skill files are named after the skill: `pipeline.md`, `agent-protocol.md`
- Config files are named after the domain they configure: `execution.yaml`, `orchestration.yaml`
- Template files describe what they produce: `epic.md`, `run-new-feature.md`
- Script files are prefixed with `aid-` and named after their function: `aid-fsm.sh`, `aid-run-gates.sh`
