---
sidebar_position: 7
title: "Project Scanner Agent"
description: "Analyze projects to understand tech stack, architecture, and conventions. Produce a structured project.yaml."
---

# Project Scanner Agent

The Project Scanner agent understands a project's technology landscape, architecture patterns, and coding conventions. It operates in two modes: a quick scan for onboarding and a deep analysis for comprehensive quality assessment. Its output is the `project.yaml` that the pipeline and all other agents use to adapt their behavior.

## Role

The Project Scanner is a **specialist agent**. It is strictly read-only — it never creates, modifies, or deletes any project files. Its only write targets are designated paths in `.aid-o/`.

## When Dispatched

- During `/aid-init` for a quick scan (fast onboarding)
- By the pipeline post-milestone for a deep analysis
- On-demand when the pipeline determines a rescan is needed

## Two Modes

### Quick Scan

Reads root indicator files only (package.json, pyproject.toml, Cargo.toml, docker-compose.yml, tsconfig.json, CI/CD configs, etc.). Never reads source file contents. Detects:

- **Languages** and **frameworks** from config files and dependency files
- **Build system**, **test framework**, **CI/CD platform**, **docs platform**
- **App type** — classifies as web-app, api-service, cli-tool, desktop-app, mobile-app, library, plugin, script, monorepo, erp-module, or infrastructure
- **Architecture** — monorepo/single-app/microservices, by-feature/by-layer/hybrid
- **Conventions** — naming, commit style, branch strategy, code style

### Deep Analysis

Runs the full quick scan first, then adds:

- **Code quality metrics** — LOC, test coverage, complexity hotspots, duplication
- **Dependency audit** — outdated packages, CVEs, unused dependencies
- **Architecture analysis** — layer dependency violations, circular deps, module cohesion
- **Tech debt assessment** — TODO/FIXME/HACK counts, categorized debt areas

## Output

- **Quick scan:** `project.yaml` at `.aid-o/config/project.yaml`
- **Deep scan:** Extended `project.yaml` + `deep-analysis-report.md`

The Planner uses `app_type` from `project.yaml` to select appropriate roles, gates, parallel groups, and recommended MCPs.

## Key Behaviors

- **Strictly read-only.** Never runs install or build commands.
- **Quick scan reads only indicator files.** No source file contents.
- **Deep analysis uses representative sampling.** Not exhaustive.
- **Uncertain detections include `confidence` field.** Never guesses versions.
- **Model:** sonnet

## Related

- [Pipeline Skill](../skills/pipeline)
- [Auditor Agent](./auditor)
- [Planner Skill](../skills/planner)
