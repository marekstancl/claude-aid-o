# AID — AI Development Orchestrator

## Project Overview

AID is a Claude Code marketplace plugin that implements Controller + Workers architecture for AI-driven software development. It takes an EPIC specification, generates structured execution plans, dispatches specialized role-based agents, enforces quality gates, and maintains complete evidence trails.

## Structure

```
ai-orchestrator/
  marketplace.json              # Plugin registry
  plugins/aid-orchestrator/     # The plugin
    .claude-plugin/plugin.json  # Plugin manifest
    agents/                     # 5 utility agents (+ 3 planned: curator, auditor, scanner)
    commands/                   # 9 commands (incl. /aid-init)
    skills/                     # 4 skills (incl. epic-orchestration)
    defaults/                   # Files copied by /aid-init
      policies/                 # gates.yaml, decision-policies.yaml
      templates/                # plan.md, epic.md, plan.schema.json, session-*.md
      playbooks/                # 9 role playbooks
  _unzipped/                    # Reference specs (read-only)
  workspace/                    # AID project workspace (own development)
  docs/                         # Documentation
```

## What `/aid-init` Creates in Target Projects

```
.aid-o/
  01-plans/          # PM + AI brainstorming → plány (archive/ for completed)
  02-epics/          # PM + AI detail → zadání (archive/ for completed)
  03-config/         # PM-customizable (policies, templates, playbooks)
  04-engine/         # AI internal (sessions, memory, backlog, evidence)
```

## Key Conventions

- **Language:** Czech for session/workspace files, English for code/plugin files
- **Session management:** Follow `skills/session-management.md`
- **Quality gates:** Run before every commit via `skills/quality-gates.md`
- **Commits:** `type(scope): description (YYYY-MM-DD HH:MM TZ)`
- **Branches:** `session/{session-id}-{topic}`
- **Naming:** Plans: `P-{YYYYMMDD}-{hash}`, Epics: `E-{YYYYMMDD}-{hash}`, Sessions: `S-{YYYYMMDD}-{hash}`

## Current Epic

EPIC-ADO-0001: Build AID Orchestrator (8 sessions)
See: `workspace/workflow/epics/active/EPIC-ADO-0001-BUILD-ORCHESTRATOR.md`

## Design Plan

P-20260216-b3a1: AID v2 — Workspace Redesign, New Agents, Memory
See: `workspace/workflow/plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md`

## Reference Documentation

- Architecture: `_unzipped/ai_dev_orchestrator_docs/01_ARCHITECTURE_OVERVIEW.md`
- Starter Kit: `_unzipped/ado_starter_kit/01_MASTER_SPEC.md`
- Multi-agent Guide: `docs/MULTIAGENT_GUIDE.md`
