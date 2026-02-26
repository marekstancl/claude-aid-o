---
id: project-scanner
title: "Project Scanner Agent"
sidebar_label: "Project Scanner Agent"
description: "Analyze projects to understand tech stack, architecture, and conventions. Produce a structured project-profile.yaml."
---

# Project Scanner Agent

The Project Scanner agent understands a project's technology landscape, architecture patterns, and coding conventions. It operates in two modes: a quick scan for onboarding (fast, reads only indicator files) and a deep analysis for comprehensive quality assessment. Its output is the `project-profile.yaml` that the Orchestrator and all other agents use to adapt their behavior to the project.

## Role

The Project Scanner is a **specialist agent**. It is strictly read-only — it never creates, modifies, or deletes any project files. Its only write targets are the designated output paths in `.aid-o/04-engine/`. Its output feeds into the Orchestrator's decision-making, including which agents to dispatch, which gates to apply, and which tools to recommend.

## When Dispatched

- During `/aid-setup` for a quick scan (fast onboarding overview)
- By the Orchestrator post-milestone for a deep analysis
- On-demand when the Orchestrator determines a rescan is needed (based on `project-profile.yaml` scan timestamp)

## Capabilities

### Quick Scan Mode

Reads root indicator files only (package.json, pyproject.toml, Cargo.toml, docker-compose.yml, tsconfig.json, .gitignore, CI/CD configs, README, etc.). Never reads source file contents. Detects:

- **Languages** — from config files and file extensions
- **Frameworks** — from dependency files (package.json deps, pyproject.toml deps)
- **Build system, test framework, CI/CD platform**
- **Docs platform** — checks for docusaurus.config.js, mkdocs.yml, conf.py, .vitepress/config.*, book.toml
- **Directory structure** — maps top-level dirs, detects monorepo/single-app/microservices, identifies architecture pattern
- **App type** — classifies as web-app, api-service, cli-tool, desktop-app, mobile-app, library, plugin, script, monorepo, erp-module, or infrastructure
- **Conventions** — naming casing, commit style (conventional vs free-form), branch strategy (git-flow, trunk-based, github-flow), code style config

### Deep Analysis Mode

Runs the full quick scan first, then adds:

- **Code quality metrics** — LOC by language, test coverage, complexity hotspots, duplication estimate
- **Dependency audit** — total direct/transitive deps, outdated packages, known vulnerabilities, unused dependencies
- **Architecture analysis** — layer dependency check, circular dependency detection, module cohesion, API surface analysis
- **Tech debt assessment** — low/medium/high debt areas, TODO/FIXME/HACK comment counts

### Output

Produces `project-profile.yaml` at `.aid-o/04-engine/memory/project-profile.yaml`. Deep scans also produce `deep-analysis-report.md` at `.aid-o/04-engine/evidence/{context}/deep-analysis-report.md`.

## Tools Available

Read-only file access and read-only bash commands (`git log`, `git branch`, `ls`, `wc`, file reads). Never runs install or build commands.

## Key Behaviors

- **Strictly read-only.** Never modifies, creates, or deletes any project file. Never runs `npm install`, `pip install`, `npm run build`, or equivalent.
- **Quick scan reads only indicator files.** Does not read source file contents during a quick scan.
- **Deep analysis uses representative sampling.** Reads source files with reasonable limits, not exhaustively.
- **Never guesses versions.** Reads them from config files or reports `"unknown"`.
- **Uncertain detections include a `confidence: low|medium|high` field.** Honest uncertainty is better than false precision.
- **If app type is ambiguous**, sets `architecture.app_type_confidence: "low"` and lists candidates. The PM can override in `project-profile.yaml`.
- **`project-profile.yaml` is a living document.** Each scan overwrites the previous version.
- The Planner uses `app_type` to select appropriate agent roles, choose relevant gates, assign parallel groups, and recommend MCPs (e.g., Playwright for web-app, Docker for infrastructure).

## Related

- [Epic Orchestration Skill](../skills/epic-orchestration)
- [Auditor Agent](./auditor)
- [Quality Gates](../skills/quality-gates)
