# Removed: knowledge / research layer — archive (R1)

P041 fix Wave 1, Batch 1.3-R, Phase R1 (2026-06-01). The aid-research command + the
knowledge-acquisition layer were removed because they were never wired (no producer
completed, no consumer in pipeline). **Nothing here is deleted permanently — this file +
the moved whole-files in this `removed/` dir are the archive. To restore, copy back.**

Context7 references (R2) are archived separately when R2 runs.

---

## Moved whole files (full content preserved)
- `removed/aid-research.md` ← was `plugins/aid-orchestrator/commands/aid-research.md`
  Restore: `git mv docs/plans/AID-audit-2026-06/removed/aid-research.md plugins/aid-orchestrator/commands/aid-research.md`
- `removed/knowledge-base.yaml` ← was `plugins/aid-orchestrator/defaults/templates/knowledge-base.yaml`
  Restore: `git mv docs/plans/AID-audit-2026-06/removed/knowledge-base.yaml plugins/aid-orchestrator/defaults/templates/knowledge-base.yaml`

---

## Excised fragments (cut from files that stay)

### 1. `defaults/integrations.yaml` — the whole `knowledge:` block (was lines 81–112)
Restore: paste back after the `memory:` section's `max_results: 3` line.
```yaml
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
Also: `integrations.yaml:4` comment changed from
`# Controls: Slack MCP integration, Qdrant memory, knowledge acquisition.`
→ `# Controls: Slack MCP integration, Qdrant memory.`

### 2. `defaults/templates/plan.schema.json` — `context_scope.knowledge` property (was lines 92–96)
Restore: paste back as the first property inside `context_scope.properties`, before `memory`.
```json
              "knowledge": {
                "type": "boolean",
                "default": true,
                "description": "Whether to inject knowledge base context"
              },
```

### 3. `skills/plan-writing.md` — two knowledge mentions
- was line 66: `- Knowledge context (if knowledge acquisition was active)`
- was line 464 (table row): `| Knowledge context references | Inline citations in relevant sections |`

### 4. `skills/setup/integrations.md` — line 41
Was: `   - If MCP name matches a known section (slack, memory, knowledge) → update that section`
Now: `   - If MCP name matches a known section (slack, memory) → update that section`

### 5. `.aid-o/config/policies/dispatch-config.yaml` (this repo's local runtime config)
Removed the per-tier + fallback `knowledge:` context toggles and the dead-ref Fields-doc line.
Restore: re-add a `knowledge: <bool>` line to each tier under `context_defaults` + `fallback`,
and the Fields-doc comment line.
- Fields-doc line (was ~:89): `#   knowledge    — Include knowledge context from Qdrant (skills/knowledge-acquisition.md)`
- `context_defaults.opus.knowledge: true` (was ~:98)
- `context_defaults.sonnet.knowledge: true` (was ~:103)
- `context_defaults.haiku.knowledge: false` (was ~:108)
- `fallback.knowledge: true` (was ~:248)
- Descriptive comments at ~:8, :19, :231 had "knowledge=true, memory=true, previous_outputs=all"; the "knowledge=true, " was dropped.

---

**Why removed:** see `docs/plans/AID-audit-2026-06/04-decisions.md` + `09-command-audit.md`
(aid-research was aspirational/never-wired; knowledge layer had no consumer).
