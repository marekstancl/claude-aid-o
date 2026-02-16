# AID — AI Development Orchestrator

A Claude Code plugin implementing **Controller + Workers** architecture for AI-driven software development.

## What It Does

1. Takes an **EPIC** specification (feature description with scope, constraints, acceptance criteria)
2. Generates a structured **Plan JSON** (steps, dependencies, parallel groups)
3. **Dispatches role-based agents** (Architect, Domain, Backend, Frontend, QA, Security, Observability, Docs, Release)
4. **Enforces quality gates** (tests, lint, security scan, docs) with retry logic
5. Maintains a complete **evidence trail** for every decision and action

## Installation

```bash
claude plugin install aid-orchestrator
```

## Quick Start

```bash
# Initialize .aid-o/ workspace in your project
/aid-init

# Create an EPIC from template
# Edit .aid-o/03-config/templates/epic.md with your feature spec

# Plan the EPIC (generates Plan JSON)
/plan-epic .aid-o/02-epics/my-epic.md

# Execute the EPIC
/run-epic .aid-o/02-epics/my-epic.md
```

## Plugin Structure

```
aid-orchestrator/
  .claude-plugin/plugin.json   # Plugin manifest
  agents/                      # 5 utility agents
    code-reviewer.md           # Reviews code against plan + standards
    docs-reviewer.md           # Reviews docs for MDX/frontmatter compliance
    quality-gates-runner.md    # Runs 6-gate pre-commit protocol
    session-validator.md       # Validates session file completeness
    lessons-extractor.md       # Extracts lessons from completed sessions
  commands/                    # 9 commands
    aid-init.md                # Initialize .aid-o/ workspace in target project
    quality-gates.md           # Run pre-commit quality gates
    session-start.md           # Start tracked session
    session-end.md             # Complete and archive session
    handoff.md                 # Create handoff for next AI session
    audit.md                   # Project health audit
    coding-standards.md        # Load coding standards
    testing.md                 # Load testing workflow
    docs-protocol.md           # Load documentation protocol
  skills/                      # 4 skills
    epic-orchestration.md      # Controller state machine
    agent-core.md              # Core agent behavior and routing
    quality-gates.md           # 6-gate quality protocol
    session-management.md      # Session lifecycle management
  defaults/                    # Copied to target project by /aid-init
    policies/
      gates.yaml               # Quality gate definitions + retry config
      decision-policies.yaml   # Autonomous decision rules
    templates/
      plan.md                  # Plan template
      epic.md                  # EPIC specification template
      plan.schema.json         # Plan JSON Schema (draft 2020-12)
      session-*.md             # 4 session type templates
    playbooks/                 # 9 role playbooks
      architect.md, domain.md, backend.md, frontend.md,
      qa.md, security.md, observability.md, docs.md, release.md
```

## What `/aid-init` Creates

```
.aid-o/
  01-plans/          # PM + AI brainstorming (archive/ for completed)
  02-epics/          # PM + AI detailed specs (archive/ for completed)
  03-config/         # PM-customizable config (policies, templates, playbooks)
  04-engine/         # AI internal (sessions, memory, backlog, evidence)
```

## Architecture

```
EPIC → Planner → Plan JSON → Scheduler → Agent Dispatch
                                              ↓
                               ┌──────────────┼──────────────┐
                               ↓              ↓              ↓
                          Architect      Backend+FE         QA
                               ↓              ↓              ↓
                          Contracts      Implementation    Tests
                               └──────────────┼──────────────┘
                                              ↓
                                     Quality Gates
                                              ↓
                                    PM Approval → Merge
```

## State Machine

```
IDLE → PLANNING → PLAN_REVIEW → EXECUTING → PHASE_CHECK
  → NEXT_PHASE / RETRY → GATES → GATE_RETRY / ESCALATION
  → PM_APPROVAL → DONE / REJECTED
```

## Configuration

After `/aid-init`, customize files in `.aid-o/03-config/`:
- `policies/gates.yaml` — quality gate definitions and thresholds
- `policies/decision-policies.yaml` — what the orchestrator decides autonomously vs. escalates
- `playbooks/*.md` — role-specific agent instructions

## Version

- **Plugin:** 0.1.0
- **Status:** Phase A — Foundation Controller
