---
sidebar_position: 14
title: "Memory MCP"
description: "Long-term vector memory protocol using Qdrant — stores decisions, lessons, patterns, and audit findings across runs and retrieves relevant past knowledge before agent dispatch."
---

# Memory MCP

The memory MCP skill defines how AID uses a Qdrant MCP server for long-term semantic memory. Agents index decisions, lessons, patterns, and audit findings at run-end and EPIC completion. Before dispatching an agent, the Controller retrieves relevant past knowledge to augment context — enabling agents to learn from history across all projects.

## Purpose

File-based memory (active-work.md, lessons-learned.md) provides context for the current project. Vector memory extends this with semantic search across all past runs and all projects: "what did we learn about authentication patterns?" or "what security issues have we seen before?" These queries require meaning-based retrieval that keyword search cannot provide.

The key principle: file-based memory is authoritative; Qdrant is supplementary. Every memory operation has a graceful no-op fallback — the plugin works identically without Qdrant.

## When Used

- Knowledge is indexed at run-end (decisions, lessons) and EPIC completion (EPIC summary, patterns)
- Memory is searched at the start of every agent run when `pre_step_search: true`
- Referenced by `analytics` for querying execution metrics
- Used by `knowledge-acquisition` for storing and retrieving framework documentation
- The Lessons Extractor agent stores extracted lessons and commands via this skill

## Key Concepts

### Storage Architecture

Qdrant data is stored centrally, not per-project:
- Path: `~/.local/share/aid-orchestrator/qdrant-data`
- MCP scope: `user` (global — available in all projects)
- All projects write to the same `aid-memory` collection
- Entries are tagged with `project_name` for filtering
- Cross-project search works because all data is in one collection

### Two MCP Tools

**`qdrant-store`** — stores text plus structured metadata. Embedding is generated server-side using FastEmbed (`sentence-transformers/all-MiniLM-L6-v2`). The `information` field holds the text to embed (maximum ~2000 tokens recommended). The `metadata` field holds structured attributes for exact-match filtering.

**`qdrant-find`** — retrieves relevant knowledge via semantic search. Returns documents ranked by similarity score (0-1). Filters can be applied to limit results to specific `project_name`, `type`, or other metadata fields.

### Document Types

| Type | Stored At | Contains |
|---|---|---|
| `decision` | Run-end, EPIC completion | Architecture decisions, technology choices, design rationale |
| `lesson` | Run-end | Gotchas, debugging insights, best practices learned |
| `pattern` | EPIC completion | Reusable implementation patterns |
| `command` | Run-end | Working command sequences for the project |
| `audit_finding` | Auditor agent output | Post-EPIC audit findings |
| `documentation` | Knowledge acquisition | Framework documentation chunks |
| `example_epic` | DONE state | Successful EPIC structures for reference |
| `metric` | PHASE_CHECK, DONE | Execution metrics (agent performance, gate results, token profiles) |

### Memory-Augmented Context

When `pre_step_search: true`, the Controller searches memory before each agent dispatch:

```text
IF memory.enabled AND memory.search.pre_step_search:
  results = qdrant-find(query=step_objective, collection="aid-memory")
  filtered = [r for r in results if r.score >= min_score]
  IF filtered:
    Include as "## MEMORY CONTEXT (from past runs)" in agent context
```

This context is clearly labeled as historical reference, not current run state. Agents use it to avoid repeating past mistakes and to apply known-good patterns.

## How It Works

At run-end, the Lessons Extractor agent identifies decisions made, lessons learned, and working commands from the run file and conversation. It stores these as `decision`, `lesson`, and `command` entries in Qdrant.

At EPIC completion (DONE state), the Controller stores an `epic_summary` metric with performance data, a `pattern` entry capturing the EPIC's implementation approach if it was successful, and an `example_epic` if the plan structure was reusable.

The minimum similarity score (`min_score: 0.4` by default) filters out weak matches. The `top_k` limit (default 5, recommended 3 for speed) controls how many results are included in context.

## Configuration

All memory behavior is controlled by `.aid-o/03-config/policies/memory-config.yaml`:

```yaml
memory:
  enabled: false                      # true = use Qdrant MCP
  collection_name: "aid-memory"       # Qdrant collection name

  auto_index:
    run_end: true                     # Index decisions + lessons at run end
    epic_done: true                   # Index EPIC summary at completion
    gate_results: false               # Index gate results (verbose, opt-in)

  search:
    top_k: 5                          # Max results per query
    timeout_seconds: 5                # Max wait for Qdrant response
    min_score: 0.4                    # Minimum similarity threshold
    pre_step_search: true             # Search memory before agent dispatch
```

Memory is disabled by default (`enabled: false`). Enable it after installing and configuring the Qdrant MCP server.

## Related

- [Knowledge Acquisition](../skills/knowledge-acquisition)
- [Agent Core](../skills/agent-core)
- [Analytics](../skills/analytics)
- [Epic Orchestration](../skills/epic-orchestration)
- [Run Management](../skills/run-management)
