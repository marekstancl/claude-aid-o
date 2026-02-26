---
sidebar_position: 13
title: "Knowledge Acquisition"
description: "Research pipeline for acquiring, quality-gating, storing, and serving framework documentation and technical knowledge to brainstorming sessions and agent dispatches."
---

# Knowledge Acquisition

The knowledge acquisition skill defines how AID researches framework documentation and technical knowledge, validates it against quality gates, stores it in dual storage (per-project YAML index plus global Qdrant), and serves it to brainstorming sessions and agent dispatches. Knowledge acquisition is non-blocking: every step degrades gracefully if a source is unavailable.

## Purpose

Agents and brainstorming sessions are more effective when they have access to up-to-date framework documentation, patterns from past projects, and applicable lessons. Without a structured acquisition pipeline, knowledge either comes from the model's (possibly stale) training data or requires manual research on every run. This skill automates that research and makes knowledge reusable across projects.

## When Used

- Triggered at the start of brainstorming sessions when `knowledge.enabled: true` in `memory-config.yaml`
- Called before agent dispatch when `pre_step_search` is enabled — the Controller builds a `KNOWLEDGE CONTEXT` block
- Invoked automatically when the Planner detects frameworks in the project profile that are not yet indexed
- Referenced by `agent-core` (Run Start Protocol step for knowledge-augmented context)

## Key Concepts

### Research Pipeline

Knowledge is acquired from two sources in priority order:

1. **Context7 MCP** — curated, up-to-date documentation for 1000+ libraries. Given a library identifier (e.g., `/tiangolo/fastapi`), Context7 returns authoritative documentation chunks ready to store.

2. **WebSearch + WebFetch** (fallback) — official documentation sites and GitHub READMEs when Context7 is unavailable or does not cover the framework.

Before fetching, the system checks whether chunks for this framework already exist in Qdrant (`type: "documentation"`, `framework: "FastAPI"`). If they do and they are not stale, the framework is skipped — new projects sharing a stack reuse existing global chunks rather than re-fetching.

### Dual Storage Architecture

Knowledge uses two storage layers:

**`knowledge-base.yaml`** (per-project, at `.aid-o/04-engine/memory/`) — a reference index of frameworks relevant to this project. Tracks: framework name, version, source URL, indexed date, TTL, status (active/stale/invalid), and chunk count. Structured attributes like staleness and status are best served by exact YAML filtering, not semantic search.

**Qdrant** (global, at `~/.local/share/aid-orchestrator/`) — the actual documentation chunks, stored with `type: "documentation"` and `project_name: "global"` so all projects can access them. New projects with shared frameworks find existing chunks in Qdrant and only add a reference entry to their `knowledge-base.yaml`.

### Quality Gates

Acquired documentation passes four mandatory gates before storage:

1. **Relevance** — does the content address the queried topic? (score threshold)
2. **Freshness** — is the version current relative to the project's declared version?
3. **Completeness** — are the minimum required sections present (API reference, examples)?
4. **Deduplication** — is this substantially different from already-stored chunks?

Documentation that fails any gate is either discarded or flagged as `status: "invalid"` in `knowledge-base.yaml`.

### Consumption Functions

Knowledge is served through two functions:

**`knowledge_context_for_agent(query)`** — returns a formatted `## KNOWLEDGE CONTEXT` block with three sections: Framework Documentation (staleness threshold: >90 days), Patterns from Past Projects (staleness threshold: >180 days), and Lessons (staleness threshold: >365 days). This is included in agent dispatch prompts.

**Brainstorming augmentation** — at the start of a brainstorming session, searches Qdrant for documentation and patterns relevant to the PM's topic and incorporates findings into the initial analysis and approach proposals.

## How It Works

When knowledge acquisition is triggered:

1. Read `knowledge-base.yaml` to see which frameworks are already indexed
2. For each missing or stale framework, attempt Context7 fetch first, then WebSearch fallback
3. Run four quality gates on acquired content
4. Store passing chunks to Qdrant with `type: "documentation"`, `project_name: "global"`
5. Update `knowledge-base.yaml` with the new reference entry
6. When serving knowledge, query Qdrant semantically and return the most relevant chunks above `min_score`

If Qdrant is unavailable, results from the current research session are useful in the current run but are not persisted. If both Context7 and WebSearch fail, the workflow continues without knowledge augmentation — a warning is logged but nothing blocks.

## Configuration

Controlled by `.aid-o/03-config/policies/memory-config.yaml`:

```yaml
knowledge:
  enabled: true
  staleness_thresholds:
    framework_docs: 90     # days before re-fetching documentation
    patterns: 180          # days before patterns are considered stale
    lessons: 365           # days before lessons need refresh
```

## Related

- [Memory MCP](../skills/memory-mcp)
- [Brainstorming](../skills/brainstorming)
- [Agent Core](../skills/agent-core)
- [Epic Orchestration](../skills/epic-orchestration)
