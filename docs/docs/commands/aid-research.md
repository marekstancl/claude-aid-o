---
sidebar_position: 10
title: "/aid-research"
description: "Research a framework, topic, or URL and store quality-gated chunks in the knowledge base"
---

# /aid-research

Trigger on-demand research for any framework topic or documentation URL. Fetches, quality-gates, and stores knowledge chunks in Qdrant for use by brainstorming and agent dispatch. All operations degrade gracefully — no research failure ever blocks your workflow.

## Usage

```bash
/aid-research [--deep] <framework> [topic]
/aid-research <url>
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `--deep` | flag | No | Extended research with detailed API reference (more chunks, slower) |
| `framework` | string | Conditional | Framework name to research (e.g., `FastAPI`, `LangGraph`) |
| `topic` | string | No | Specific topic within the framework (e.g., `WebSockets`, `checkpointing`) |
| `url` | string | Conditional | Full URL to fetch and index (`http://` or `https://`) |

## Examples

```bash
# Quick overview of FastAPI
/aid-research FastAPI

# Specific topic within a framework
/aid-research FastAPI WebSockets

# Deep research with extended API reference
/aid-research --deep LangGraph checkpointing

# Fetch and index a specific documentation page
/aid-research https://docs.celery.dev/
```

## Prerequisites

- `.aid-o/` workspace should exist (run [`/aid-init`](./aid-init) first). Without it, results are available in the current run only, with no YAML updates.
- For **persistent storage**: Qdrant MCP configured (see [`/aid-setup`](./aid-setup) Option 6a). Without Qdrant, results are run-only.
- For **Context7 source** (preferred): Context7 MCP configured (see [`/aid-setup`](./aid-setup) Option 6b). Without it, WebSearch is used automatically.

## Research Modes

| Input | Mode | Behavior |
|-------|------|----------|
| `FastAPI` | topic | Quick overview of FastAPI |
| `FastAPI WebSockets` | topic | Quick research on a specific topic |
| `--deep LangGraph checkpointing` | deep | Extended API reference |
| `https://docs.celery.dev/` | url | Fetch, extract, and index the page |

## How It Works

### Topic and Deep Mode

1. Checks existing knowledge in `knowledge-base.yaml` — skips re-fetching if already indexed at sufficient depth
2. Tries **Context7 MCP** first (resolve library ID → query docs), falls back to **WebSearch** automatically
3. Splits response into ~300-word chunks (one concept / pattern / API endpoint per chunk)
4. Runs **4 quality gates** on each chunk: minimum value, deduplication, metadata completeness, size
5. Stores passing chunks in Qdrant with `project_name="global"` (cross-project reuse)
6. Updates `.aid-o/04-engine/memory/knowledge-base.yaml`

### URL Mode

1. Fetches the URL using WebFetch
2. Infers the framework from page title, headings, or URL path
3. Splits content into chunks at heading and code-block boundaries
4. Assigns confidence: Tier 1 domains (official docs, readthedocs.io) get `high`; others get `medium`
5. Quality-gates and stores passing chunks in Qdrant

### Already Indexed

If the framework is already indexed at the requested depth, the command reports the existing index state and suggests refinements:

```
FastAPI already researched (42 chunks, context7).
Use --deep to fetch extended API reference, or provide a specific topic.
```

## Error Handling

All errors are non-blocking:

| Error | Handling |
|-------|----------|
| Context7 MCP unavailable | Falls back to WebSearch silently |
| Library not found in Context7 | Falls back to WebSearch for that framework |
| WebSearch returns no Tier 1/2 results | Reports "no quality sources", stores nothing |
| WebFetch fails for URL | Reports "URL unreachable", aborts that URL |
| Qdrant unavailable | Results are run-only; warns PM |
| Chunk rejected by quality gates | Logs reason, continues with remaining chunks |

## Notes

- **Global storage** — all chunks use `project_name="global"`. Research done in one project is available to all your projects.
- **Quality gates are mandatory** — every chunk must pass all 4 gates before storage. No data is better than bad data.
- **Cross-project reuse** — before fetching, Qdrant is checked for existing global chunks from other projects.
- **No re-fetch** — if a framework is already actively indexed with sufficient depth, it is not re-fetched unless you provide a specific topic or the `--deep` flag.

## Related

- [`/aid-setup`](./aid-setup) — configure Qdrant and Context7 MCP
- [`/aid-brainstorm`](./aid-brainstorm) — uses indexed knowledge during brainstorming
- [`/aid-analytics`](./aid-analytics) — analyze orchestration metrics (separate from research knowledge)
