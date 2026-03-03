---
sidebar_position: 3
title: "integrations.yaml"
description: "Reference for integrations.yaml — Slack MCP integration, Qdrant vector memory, and knowledge acquisition configuration."
---

# integrations.yaml

**Location:** `.aid-o/config/integrations.yaml`

This file configures all external service integrations. It consolidates what v1 split across `slack-config.yaml` and `memory-config.yaml` into one file, and adds the knowledge acquisition system.

All integrations are **optional and disabled by default**. AID works fully without any external services — Slack falls back to inline chat, memory falls back to file-based context, and knowledge acquisition falls back to WebSearch.

---

## Full Default Configuration

Source: `plugins/aid-orchestrator/defaults/integrations.yaml`

```yaml
# AID Integrations Configuration (v2)
# Consolidated from: slack-config.yaml, memory-config.yaml
#
# Controls: Slack MCP integration, Qdrant memory, knowledge acquisition.
# Both integrations are optional — disabled by default.

# ─── Slack ───────────────────────────────────────────────────────────────
# See: skills/slack-mcp.md for protocol details.
# Requires: slack-mcp-server by @korotovsky in .mcp.json
slack:
  enabled: false
  channel: "#aid-orchestrator"
  pm_user_id: ""

  timeouts:
    plan_approval_minutes: 1440
    escalation_minutes: 480
    merge_approval_minutes: 1440
    proposal_minutes: 4320

  reminders:
    enabled: true
    interval_minutes: 60
    max_reminders: 3

  timeout_actions:
    plan_approval: wait
    escalation: wait
    merge_approval: wait
    proposal: defer

# ─── Memory (Qdrant) ────────────────────────────────────────────────────
# See: skills/memory-mcp.md for protocol details.
# Requires: Qdrant MCP server configured in .mcp.json
memory:
  enabled: false
  collection_name: "aid-memory"

  cross_project:
    enabled: true
    max_results: 3

  auto_index:
    run_end: true
    epic_done: true
    gate_results: false

  search:
    top_k: 3
    timeout_seconds: 5
    min_score: 0.4
    pre_step_search: true

# ─── Knowledge Acquisition ──────────────────────────────────────────────
# See: skills/knowledge-acquisition.md for protocol details.
# Primary source: Context7 MCP; fallback: WebSearch
knowledge:
  enabled: false
  primary_source: context7
  fallback_source: websearch

  context7:
    available: false
    scope: user

  research:
    default_depth: quick
    deep_on_demand_only: true
    max_frameworks_per_scan: 5
    max_urls_per_framework: 3
    max_chunks_per_source: 15

  quality:
    min_chunk_words: 50
    max_chunk_tokens: 2000
    dedup_threshold: 0.85
    merge_threshold: 0.70

  aging:
    documentation_ttl_days: 90
    pattern_ttl_days: 180
    lesson_ttl_days: 365
    stale_weight: 0.7
    expired_weight: 0.3
    exclude_after_days: 180
```

---

## Field Reference

### slack

Slack integration routes all PM communication (escalations, approvals, proposals, status updates) through a Slack channel instead of inline chat.

**Prerequisites:**
- Slack MCP server (`slack-mcp-server` by `@korotovsky`) configured in `.mcp.json`
- Bot OAuth scopes: `chat:write`, `channels:read`, `channels:history`, `users:read`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable Slack integration. When `false`, all PM messages appear inline in chat. |
| `channel` | string | `#aid-orchestrator` | Slack channel for all AID messages. Must include `#` prefix. |
| `pm_user_id` | string | `""` | PM's Slack user ID (format: `Uxxxxxxxxx`). Used for `@mention` on escalations. Leave empty to skip mentions. |

#### slack.timeouts

How long AID waits for a PM response before applying the timeout action.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `plan_approval_minutes` | integer | `1440` | Wait time for plan review (24 hours). |
| `escalation_minutes` | integer | `480` | Wait time for escalation response (8 hours). |
| `merge_approval_minutes` | integer | `1440` | Wait time for merge approval (24 hours). |
| `proposal_minutes` | integer | `4320` | Wait time for improvement proposal review (72 hours). |

#### slack.reminders

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Send periodic reminders for unanswered messages. |
| `interval_minutes` | integer | `60` | Minutes between reminders. |
| `max_reminders` | integer | `3` | Maximum reminders before applying timeout action. |

#### slack.timeout_actions

What AID does when a message reaches its timeout.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `plan_approval` | string | `wait` | Action on plan approval timeout. |
| `escalation` | string | `wait` | Action on escalation timeout. |
| `merge_approval` | string | `wait` | Action on merge approval timeout. |
| `proposal` | string | `defer` | Action on proposal timeout. |

**Available actions:**

| Action | Meaning | Valid for |
|--------|---------|-----------|
| `wait` | Keep waiting indefinitely | Any type |
| `skip` | Treat as "skip" from PM | Escalations only |
| `abort` | Treat as "abort" from PM | plan_approval, escalation, merge_approval |
| `defer` | Move to backlog | Proposals only |

### memory

Qdrant vector memory enables cross-project knowledge sharing, automatic indexing of run results, and context-aware agent dispatch.

**Prerequisite:** Qdrant MCP server configured in `.mcp.json`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable Qdrant memory integration. |
| `collection_name` | string | `aid-memory` | Qdrant collection name for this project. |

#### memory.cross_project

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Search across all projects in the same Qdrant instance. |
| `max_results` | integer | `3` | Maximum cross-project results per query. |

#### memory.auto_index

Controls when AID automatically stores information in Qdrant.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `run_end` | boolean | `true` | Index run summary when a run completes. |
| `epic_done` | boolean | `true` | Index EPIC summary when all runs complete. |
| `gate_results` | boolean | `false` | Index individual gate results. Enable for large projects where gate patterns are valuable. |

#### memory.search

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `top_k` | integer | `3` | Number of results to retrieve per search. |
| `timeout_seconds` | integer | `5` | Maximum time for a memory search. Falls back to no-memory if exceeded. |
| `min_score` | float | `0.4` | Minimum similarity score (0.0-1.0) to include a result. |
| `pre_step_search` | boolean | `true` | Search memory before each step dispatch for relevant context. |

### knowledge

Knowledge acquisition provides agents with up-to-date documentation for frameworks and libraries used in the project.

**Primary source:** Context7 MCP server (if available). **Fallback:** WebSearch tool.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable knowledge acquisition. |
| `primary_source` | string | `context7` | Primary documentation source. |
| `fallback_source` | string | `websearch` | Fallback when primary is unavailable. |

#### knowledge.context7

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `available` | boolean | `false` | Whether Context7 MCP server is configured. Set to `true` after adding to `.mcp.json`. |
| `scope` | string | `user` | Context7 scope: `user` = user-level config, `project` = project-level config. |

#### knowledge.research

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `default_depth` | string | `quick` | Default research depth: `quick` (summary) or `deep` (comprehensive). |
| `deep_on_demand_only` | boolean | `true` | Only perform deep research when explicitly requested. |
| `max_frameworks_per_scan` | integer | `5` | Maximum frameworks to research per project scan. |
| `max_urls_per_framework` | integer | `3` | Maximum documentation URLs per framework. |
| `max_chunks_per_source` | integer | `15` | Maximum content chunks per documentation source. |

#### knowledge.quality

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `min_chunk_words` | integer | `50` | Minimum words per content chunk. Shorter chunks are discarded. |
| `max_chunk_tokens` | integer | `2000` | Maximum tokens per chunk. Longer chunks are split. |
| `dedup_threshold` | float | `0.85` | Similarity threshold for deduplication. Chunks above this are merged. |
| `merge_threshold` | float | `0.70` | Similarity threshold for merging related chunks. |

#### knowledge.aging

Controls how knowledge relevance decays over time.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `documentation_ttl_days` | integer | `90` | Days before documentation knowledge is marked stale. |
| `pattern_ttl_days` | integer | `180` | Days before pattern knowledge is marked stale. |
| `lesson_ttl_days` | integer | `365` | Days before lesson knowledge is marked stale. |
| `stale_weight` | float | `0.7` | Weight multiplier for stale knowledge in search results. |
| `expired_weight` | float | `0.3` | Weight multiplier for expired knowledge. |
| `exclude_after_days` | integer | `180` | Exclude knowledge entirely after this many days past TTL. |

---

## Customization Tips

### Enabling Slack

```yaml
slack:
  enabled: true
  channel: "#my-project-aid"
  pm_user_id: "U0123456789"  # Your Slack member ID
```

Also add the Slack MCP server to your `.mcp.json`:

```json
{
  "mcpServers": {
    "slack": {
      "command": "bash",
      "args": ["-c", "set -a && source .env && set +a && npx slack-mcp-server 2>/dev/null"]
    }
  }
}
```

### Enabling Qdrant memory

```yaml
memory:
  enabled: true
  collection_name: "my-project-memory"
```

### Making escalation timeouts more aggressive

For teams that review escalations quickly:

```yaml
slack:
  timeouts:
    escalation_minutes: 120  # 2 hours instead of 8
  timeout_actions:
    escalation: skip  # Auto-skip after timeout instead of waiting forever
```

### Enabling deep research by default

```yaml
knowledge:
  enabled: true
  research:
    default_depth: deep
    deep_on_demand_only: false
```

### Reducing knowledge aging for fast-moving projects

```yaml
knowledge:
  aging:
    documentation_ttl_days: 30   # Docs go stale faster
    pattern_ttl_days: 60
    exclude_after_days: 90
```

---

## Related

- [Memory system architecture](../architecture/memory-system) — how Qdrant memory integrates with the pipeline
- [execution.yaml](./execution-yaml) — quality gates and decision policies
- [orchestration.yaml](./orchestration-yaml) — Controller settings and FSM parameters
