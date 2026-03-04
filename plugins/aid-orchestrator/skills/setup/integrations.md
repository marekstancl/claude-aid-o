---
name: setup-integrations
description: Detect and configure MCP server integrations for AID
---

# Setup Module: Integrations

Detect installed MCP servers and enable/disable them in AID.

## Input

Called by `/aid-setup` router or `/aid-setup integrations`.

## Flow

1. Read `.claude/settings.json` — extract `mcpServers` keys
2. Read `.aid-o/config/integrations.yaml` — extract current enabled state
3. Build MCP status table:

For each MCP server found in settings.json:
- Check if it maps to an integrations.yaml section → show [enabled] or [disabled]
- If not mapped → show [available]

Present to PM:
```
MCP Integrations:
  [enabled]    qdrant-memory — project memory & semantic search
  [disabled]   context7 — library documentation lookup
  [available]  shared-docker — container management
  [available]  shared-slack — Slack notifications

  Not installed (add to .claude/settings.json to use):
  [not found]  shared-playwright — browser automation
```

4. For each [disabled] or [available] MCP → ask PM: "Enable {name}? (y/N)"
5. For each [enabled] MCP → ask PM: "Keep {name} enabled? (Y/n)"

6. Write updated `config/integrations.yaml`:
   - Set `enabled: true/false` for each integration section
   - If MCP name matches a known section (slack, memory, knowledge) → update that section
   - If MCP is unknown → note in output but don't create arbitrary config sections

## Known MCP Mappings

| MCP Server Key | integrations.yaml Section | Description |
|---|---|---|
| `qdrant-memory` or `qdrant-brain` | `memory:` | Qdrant semantic search |
| `*context7*` | `knowledge:` + `knowledge.context7:` | Library docs |
| `*slack*` | `slack:` | PM notifications |
| `*docker*` | (note only) | Container management |
| `*playwright*` | (note only) | Browser testing |
| `*github*` | (note only) | GitHub API |

## Output

```
Integrations updated:
  enabled: qdrant-memory, context7
  disabled: shared-slack
Written to: .aid-o/config/integrations.yaml
```
