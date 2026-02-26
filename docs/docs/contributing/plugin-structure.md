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
  agents/                 # 18 specialized agent definitions
  commands/               # 13 slash command definitions
  skills/                 # 20 reusable orchestration skills
  defaults/               # Files copied into target projects by /aid-init
    policies/             # YAML configuration defaults
    templates/            # EPIC, Plan, and Run file templates
    playbooks/            # Role-based execution playbooks
    examples/             # Sample project prompts for /aid-brainstorm
  README.md               # Plugin documentation (shown in Claude Code)
  CHANGELOG.md            # Version history (must mirror root CHANGELOG.md)
```

## Plugin Manifest

**`.claude-plugin/plugin.json`** — the Claude Code plugin manifest. It declares the plugin's name, version, author, license, description, and keywords. The `version` field here must match the version in the root `CHANGELOG.md` header and all other version locations listed in `CLAUDE.md`.

```json
{
  "name": "aid-orchestrator",
  "version": "0.9.3",
  "description": "AID — AI Development Orchestrator. ...",
  "author": {
    "name": "Marek Stancl"
  },
  "license": "AGPL-3.0-only",
  "keywords": ["orchestration", "multi-agent", "quality-gates", "epic-management"]
}
```

## `agents/`

Contains one Markdown file per agent. Each file defines the agent's identity, capabilities, constraints, input/output format, and workflow. There are 18 agents:

**Role agents** — dispatched by the Controller during EPIC execution:

| File | Agent Role |
|------|------------|
| `architect.md` | Design API contracts, event schemas, ADRs |
| `domain.md` | Model business rules and domain logic |
| `backend.md` | Implement server-side code |
| `frontend.md` | Implement UI and client-side code |
| `qa.md` | Write tests, validate coverage |
| `security.md` | Security review and hardening |
| `observability.md` | Add logging, metrics, and tracing |
| `docs-writer.md` | Write and maintain documentation |
| `release.md` | Prepare release artifacts |

**Utility agents** — invoked at specific points in the pipeline:

| File | Agent Role |
|------|------------|
| `run-validator.md` | Validate run file completeness |
| `quality-gates-runner.md` | Run the 6-gate quality protocol before commit |
| `docs-reviewer.md` | Check documentation format compliance |
| `code-reviewer.md` | Review code against the plan and standards |
| `lessons-extractor.md` | Extract lessons and commands at run end |
| `gate-fixer.md` | Attempt to fix failing gates in retry loop |

**Specialist agents** — invoked for specific analytical tasks:

| File | Agent Role |
|------|------------|
| `curator.md` | Process improvement proposals into the backlog |
| `auditor.md` | Post-EPIC health audit |
| `project-scanner.md` | Analyze project structure for `/aid-setup` |

## `commands/`

Contains one Markdown file per slash command. Each file defines the command's behavior in natural language for Claude Code to execute. There are 13 commands:

| File | Command | Purpose |
|------|---------|---------|
| `aid-init.md` | `/aid-init` | Initialize or upgrade `.aid-o/` workspace |
| `aid-setup.md` | `/aid-setup` | Interactive project onboarding |
| `aid-help.md` | `/aid-help` | Show AID documentation and help topics |
| `aid-plan-epic.md` | `/aid-plan-epic` | Parse EPIC or Plan into a Plan JSON |
| `aid-run-epic.md` | `/aid-run-epic` | Run full EPIC orchestration pipeline |
| `aid-epic-status.md` | `/aid-epic-status` | Show pipeline status for active EPICs |
| `aid-epic-queue.md` | `/aid-epic-queue` | Manage the EPIC execution queue |
| `aid-first-aid.md` | `/aid-first-aid` | Start autonomous FIRST AID mode |
| `aid-stop.md` | `/aid-stop` | Stop or pause autonomous execution |
| `aid-audit.md` | `/aid-audit` | Run a project health audit |
| `aid-brainstorm.md` | `/aid-brainstorm` | Interactive brainstorming session |
| `aid-research.md` | `/aid-research` | Research a topic and produce findings |
| `aid-analytics.md` | `/aid-analytics` | Analyze EPIC performance metrics |

## `skills/`

Contains one Markdown file per skill. Skills are reusable modules loaded by agents and commands on demand. Unlike agents (which define a role) and commands (which define user-invocable actions), skills define **how** something is done — algorithms, protocols, and decision logic.

Key skills include:

| File | Purpose |
|------|---------|
| `agent-core.md` | Run start/end protocols, absolute rules, file resolution |
| `epic-orchestration.md` | Controller state machine — the heart of EPIC execution |
| `quality-gates.md` | 6-gate pre-commit quality protocol |
| `gates-engine.md` | YAML-based post-step gate execution |
| `parallel-dispatch.md` | Parallel agent dispatch protocol |
| `planner.md` | Plan generation from EPIC specification |
| `retry-engine.md` | Gate failure retry loop |
| `run-management.md` | Run file lifecycle — create, update, archive |
| `memory-mcp.md` | Qdrant vector memory protocol |
| `knowledge-acquisition.md` | Framework documentation and knowledge retrieval |
| `slack-mcp.md` | Slack PM communication protocol |
| `epic-queue.md` | EPIC queue management |
| `cost-optimization.md` | Model selection and token cost management |
| `auto-escalation.md` | Autonomous escalation rules for FIRST AID mode |

## `defaults/`

The `defaults/` directory contains files that are copied into target projects when users run `/aid-init`. The `/aid-init` command scans this directory dynamically — every file you add here will automatically appear in new project workspaces.

### `defaults/policies/`

YAML configuration files that control how the Controller and agents behave. Users can customize these after initialization.

| File | Purpose |
|------|---------|
| `gates.yaml` | Quality gate definitions, retry config, budget limits |
| `decision-policies.yaml` | What the Controller decides autonomously vs. escalates to PM |
| `dispatch-strategy.yaml` | Agent dispatch ordering and parallelism rules |
| `permissions.yaml` | Baseline tool permissions for agents |
| `permissions-auto.yaml` | Extended permissions for FIRST AID autonomous mode |
| `memory-config.yaml` | Qdrant vector memory and knowledge acquisition settings |
| `slack-config.yaml` | Slack integration configuration |
| `release-policy.yaml` | Version file registry and release checklist |
| `language.yaml` | Language and locale settings |
| `skill-conflicts.yaml` | Skill conflict resolution rules |

### `defaults/templates/`

Markdown and JSON templates used to create EPIC files, Plan files, and Run files.

| File | Purpose |
|------|---------|
| `epic.md` | Template for writing an EPIC specification |
| `epic-example.md` | Annotated example EPIC for reference |
| `plan.md` | Template for a brainstorming plan document |
| `plan.schema.json` | JSON Schema for the Plan JSON generated by `/aid-plan-epic` |
| `run-new-feature.md` | Run file template for new feature work |
| `run-bug-fix.md` | Run file template for bug fix work |
| `run-refactoring.md` | Run file template for refactoring work |
| `run-exploration.md` | Run file template for exploration/research |
| `inputs-readme.md` | README template for `.aid-o/05-inputs/` |
| `knowledge-base.yaml` | Knowledge base configuration template |

### `defaults/playbooks/`

Playbooks are referenced by agents in their dispatch prompt. They provide domain-specific execution guidance beyond what the agent definition itself contains.

| File | Role |
|------|------|
| `architect.md` | Architecture design process |
| `backend.md` | Backend implementation process |
| `frontend.md` | Frontend implementation process |
| `domain.md` | Domain modeling process |
| `qa.md` | Test writing process |
| `security.md` | Security review process |
| `observability.md` | Observability implementation process |
| `release.md` | Release preparation process |
| `docs.md` | Generic documentation update process |
| `docs-docusaurus.md` | Docusaurus-specific documentation rules |
| `docs-generic.md` | Generic documentation rules (non-Docusaurus) |
| `e2e.md` | End-to-end test writing process |

### `defaults/examples/`

Sample project prompts used by `/aid-brainstorm` to give users concrete starting points. Organized into two subdirectories:

- `defaults/examples/common-projects/` — web app and API project starters (Next.js, FastAPI, SaaS, etc.)
- `defaults/examples/ai-workflows/` — AI pipeline project starters (LangChain, LangGraph, n8n, etc.)

## File Naming Conventions

- All files use **kebab-case** (e.g., `epic-orchestration.md`, `gates-engine.md`, `quality-gates-runner.md`)
- Agent files are named after the agent role: `backend.md`, `qa.md`, `docs-writer.md`
- Command files are named after the command: `aid-help.md`, `aid-run-epic.md`
- Skill files are named after the skill: `retry-engine.md`, `parallel-dispatch.md`
- Policy files are named after the domain they configure: `gates.yaml`, `memory-config.yaml`
- Template files describe what they produce: `epic.md`, `run-new-feature.md`
