# Removed: Context7 references — archive (R2)

P041 fix Wave 1, Batch 1.3-R, Phase R2 (2026-06-01). Context7 existed in the AID plugin
ONLY as the source of the (now-removed, R1) knowledge layer — it had no other plugin use.
These are the orphaned Context7 references, archived here. **The Context7 MCP server itself
is NOT removed** (it's a general capability, not ours) — only AID's now-dead references to it.
To restore a reference, paste it back at the cited location.

---

### 1. `skills/setup/integrations.md:28` — example MCP list line
Removed line:
```
  [disabled]   context7 — library documentation lookup
```

### 2. `skills/setup/integrations.md:49` — Known MCP Mappings table row
Removed row (routed to the R1-removed `knowledge:` section — doubly dead):
```
| `*context7*` | `knowledge:` + `knowledge.context7:` | Library docs |
```

### 3. `skills/setup/integrations.md:59` — Output example
Changed: `  enabled: qdrant-memory, context7` → `  enabled: qdrant-memory`

### 4. `commands/aid-help.md:204` — integrations help line
Changed: `... MCP servers (Qdrant, Context7, Slack, ...)` → `... MCP servers (Qdrant, Slack, ...)`

### 5. `defaults/policies/permissions.yaml:41–43` — autonomous-preset Context7 allowlist
Removed block:
```yaml
      # ── Context7 (plugin-loaded) ──
      - "mcp__plugin_context7_context7__resolve-library-id"
      - "mcp__plugin_context7_context7__query-docs"
```
To restore: paste back between the `# vulcan-delete excluded` line and the `# ── GitHub` block.

---

**Why removed:** Context7 had no plugin use outside the knowledge layer (verified by grep,
3rd audit pass). See `docs/plans/AID-audit-2026-06/11-fix-proposals.md` Batch 1.3-R.
