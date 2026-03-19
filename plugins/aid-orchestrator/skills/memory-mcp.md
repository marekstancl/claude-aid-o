---
name: memory-mcp
description: Qdrant vector memory protocol — store, find, entry schema, quality rules for per-project agent memory
user_invocable: false
---

# Memory MCP — Qdrant Vector Memory Protocol

## 1. Overview

Memory MCP provides long-term semantic memory for AID agents via Qdrant vector database.
Agents store architectural patterns, decisions, lessons, and code examples discovered during
EPIC execution. Before each step, the controller queries memory for relevant context,
giving agents institutional knowledge accumulated across runs.

**Collection design:**
- Single collection: `aid-agent-memory`
- Tenant isolation via `project_id` payload field
- Each project uses its directory name as `project_id` (e.g., `my-app`)
- Monorepos use `project/service-name` format (e.g., `my-app/api-gateway`)
- Cross-project search is supported when `integrations.yaml` → `memory.cross_project.enabled: true`

**Dependency:** Requires Qdrant MCP server configured in `.mcp.json`.
If Qdrant is unavailable, all workflows degrade gracefully — memory is never a blocker.

---

## 2. Entry Schema

Every memory entry stored in Qdrant follows this schema.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `entry_id` | string | Unique identifier, format: `{project_id}_{category}_{timestamp}` |
| `project` | string | Project identifier (tenant key) |
| `category` | enum | One of: `architecture`, `api`, `data`, `ui`, `config`, `testing`, `conventions`, `security`, `devops`, `cross-cutting` |
| `tags` | string[] | Minimum 3 descriptive tags for filtering and search refinement |
| `confidence` | enum | `high` / `medium` / `low` — reflects certainty of the pattern |
| `source_file` | string | Path to the file where the pattern was observed |
| `summary` | string | Minimum 20 words describing the pattern, decision, or lesson |
| `code_example` | string | 3-15 lines of real code demonstrating the pattern |
| `scan_type` | string | How the entry was created: `agent_discovery`, `project_scan`, `epic_completion`, `manual` |
| `created_at` | string | ISO 8601 timestamp |
| `status` | enum | `active` / `superseded` / `stale` |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `subcategory` | string | Finer classification within the category |
| `related_files` | string[] | Other files involved in this pattern |
| `line_range` | string | Line range in source_file (e.g., `48-64`) |
| `epic_id` | string | EPIC that produced this entry |
| `supersedes` | string | entry_id of the older entry this one replaces |
| `superseded_by` | string | entry_id of the newer entry that replaced this one |
| `git_commit` | string | Commit hash where the pattern was introduced |

---

## 3. Embedding Strategy

Embed **ONLY the `summary` field** for vector search.

- Summary should be 1-2 sentences, focused on the pattern or decision
- Do NOT concatenate multiple fields into the embedding text
- Short, focused text produces better semantic matches than long blobs
- The summary is what gets compared during `qdrant-find` queries

**Good summary:** "FastAPI dependency injection uses a factory pattern for database sessions, yielding the session in a context manager to ensure cleanup on both success and exception paths."

**Bad summary:** "Database stuff in the backend service file with some patterns."

---

## 4. Store Protocol

### Step 1: Query Before Storing (MANDATORY)

Before every store operation, run `qdrant-find` with the summary text:

```
existing = qdrant-find(query=summary, collection_name="aid-agent-memory")
if any result with score >= 0.85:
    → Supersede the existing entry (see §6 Supersede Pattern)
    → Do NOT create a duplicate
```

### Step 2: Validate Before Storing

All entries MUST pass validation before `qdrant-store`:

| Check | Rule |
|-------|------|
| Summary length | >= 20 words |
| Source file | Must exist in the project (verify with glob) |
| Tags | >= 3 tags |
| Code example | Present, non-empty, real code from the project |

### Step 3: Store

```
qdrant-store(
    collection_name="aid-agent-memory",
    content=summary,           # embedded text = summary only
    metadata={                 # all schema fields go in payload
        entry_id, project, category, tags, confidence,
        source_file, summary, code_example, scan_type,
        created_at, status, ...optional fields
    }
)
```

### Rejection Criteria

Do NOT store entries that are:

1. **Vague** — summary lacks specifics, could apply to any project
2. **Duplicate of project.yaml** — information already in `.aid-o/config/project.yaml`
3. **One-off** — a fix for a specific bug with no reusable pattern
4. **Fabricated** — code_example not from actual project files
5. **Generic** — textbook knowledge not specific to this project's implementation

---

## 5. Find Protocol

### Query Construction

Use the current step's objective text as the search query:

```
results = qdrant-find(
    query=step_objective,
    collection_name="aid-agent-memory",
    filter={ project: project_id }   # or omit filter for cross-project
)
```

### 2-Tier Context Injection

Results are injected into agent context at two levels:

| Tier | Entries | Included Fields |
|------|---------|-----------------|
| Summary tier | Top 10 results | `summary`, `category`, `tags`, `source_file` |
| Detail tier | Top 3 results | All of summary tier + `code_example`, `related_files` |

### Token Budget

Total memory context injection: **~1500 tokens maximum**.
If results exceed budget, truncate from the bottom of the summary tier first.

### Graceful Degradation

```
try:
    results = qdrant-find(query, collection_name, timeout=5s)
except (ConnectionError, Timeout, MCPUnavailable):
    log_warning("Qdrant unavailable — proceeding without memory context")
    results = []
    # Continue execution — memory is NEVER a blocker
```

If Qdrant is disabled in `integrations.yaml` → skip the query entirely, no warning needed.

---

## 6. Supersede Pattern

Qdrant MCP does not support entry deletion. Use the supersede pattern instead.

### To Update an Entry

1. Create a new entry with `status: active` and `supersedes: "old_entry_id"`
2. The old entry remains in Qdrant but is conceptually replaced
3. When querying, prefer entries with `status: active` over `superseded` or `stale`

### To Mark an Entry as Outdated

Store a new version with:
- `status: active`
- `supersedes: old_entry_id`
- Updated summary, code_example, and metadata

The old entry's `superseded_by` field should be set in the new entry's reference
(since we cannot modify the old entry in place).

### Stale Entries

When a pattern is no longer observed but not explicitly replaced:
- Create a minimal update entry with `status: stale`, `confidence: low`
- Reference the original via `supersedes`

---

## 7. Agent memory_writes Format

Agents report memory-worthy discoveries in their output using the `memory_writes` block:

```yaml
memory_writes:
  - type: component|pattern|decision|lesson|api|model
    summary: "≥20 words describing the pattern"
    source_file: "path/to/file.py"
    tags: ["tag1", "tag2", "tag3"]
    code_example: |
      # 3-15 lines of real code from the project
      class SessionFactory:
          def create(self) -> Session:
              session = Session(bind=self.engine)
              try:
                  yield session
                  session.commit()
              except Exception:
                  session.rollback()
                  raise
              finally:
                  session.close()
```

**N/A is acceptable** for non-code steps (documentation, planning, research):

```yaml
memory_writes: N/A
memory_writes_reason: "Step was documentation-only, no code patterns discovered"
```

---

## 8. Quality Gate

The controller validates every `memory_writes` block after an agent returns output.

### Validation Checks

| # | Check | Rule |
|---|-------|------|
| 1 | Summary length | >= 20 words |
| 2 | Source file exists | Verify with glob — file must exist in the project |
| 3 | Tag count | >= 3 tags |
| 4 | Code example | Present and >= 3 lines |

### On Failure

If any memory_write entry fails validation:
- **Reject the agent output** — do not proceed to the next step
- **Re-dispatch** the agent with an error message specifying which validation failed
- The agent must fix the memory_writes block and resubmit

### N/A Handling

`memory_writes: N/A` is accepted if:
- A `memory_writes_reason` is provided explaining why no patterns were found
- The step is genuinely non-code (docs, planning, config-only changes)

`memory_writes: N/A` is rejected if:
- No reason is provided
- The step involved code changes (files_changed contains `.py`, `.ts`, `.js`, etc.)

**Re-dispatch on validation failure:**
When memory_writes fails validation, re-dispatch the agent with:
```
MEMORY VALIDATION FAILED: {specific failure reason}
Your output was rejected because memory_writes {is missing | has summary < 20 words | has non-existent source_file | ...}.
Re-submit your output with corrected memory_writes section. All other output is preserved.
Original step objective: {objective}
```
Max 1 re-dispatch for memory_writes failure. If second attempt also fails → accept output with warning logged to timeline.

---

## 9. Reference

- **Configuration:** `.aid-o/config/integrations.yaml` → `memory` section (collection name, search params, auto-index triggers)
- **Project scanner:** `agents/project-scanner.md` — initial project scan that seeds memory with architecture patterns
- **Pipeline integration:** `skills/pipeline.md` §4 (pre-step memory query) and §7 (post-EPIC memory indexing)
- **File-based memory:** `skills/memory.md` — complementary file-based context (project.yaml, active.md, backlog)

---

**Last Updated:** 2026-03-19
