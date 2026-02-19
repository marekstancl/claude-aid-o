# Memory MCP Integration — Long-Term Vector Memory Protocol

**Version:** 0.1.0
**Skill:** memory-mcp
**Dependencies:** session-management, epic-orchestration

---

## TL;DR

This skill defines how AID stores and retrieves knowledge across sessions using a Qdrant
MCP server. Agents auto-index decisions, lessons, patterns, and audit findings at session-end
and EPIC completion. Before dispatching an agent, the Controller retrieves relevant past
knowledge to augment the agent's context — enabling agents to learn from history.

**Principle:** File-based memory is authoritative. Qdrant is supplementary. Plugin works
identically without Qdrant — every memory operation has a graceful no-op fallback.

---

## MCP Server Interface

AID expects the official Qdrant MCP server (`mcp-server-qdrant`) providing two tools:

### `qdrant-store`

Store a piece of knowledge (text + metadata) into a Qdrant collection.
Embedding is handled server-side (FastEmbed, default: `sentence-transformers/all-MiniLM-L6-v2`).

```
Input:
  information: string        # The text to store (max ~2000 tokens recommended)
  metadata: object|null      # Structured metadata (see Document Types below)
  collection_name: string|null  # Override default collection (optional)

Output:
  (tool confirms storage; no explicit return schema)
```

### `qdrant-find`

Retrieve relevant knowledge via semantic search.

```
Input:
  query: string              # Natural language query
  collection_name: string|null  # Override default collection (optional)

Output:
  results: array             # Matching documents, ranked by relevance
    - information: string    # Stored text
      metadata: object       # Stored metadata
      score: number          # Similarity score (0-1)
```

---

## Configuration

Read from `.aid-o/03-config/policies/memory-config.yaml`:

```yaml
memory:
  enabled: false                        # true = use Qdrant MCP, false = file-based only
  collection_name: "aid-memory"         # Default Qdrant collection name

  auto_index:
    session_end: true                   # Index decisions + lessons at session end
    epic_done: true                     # Index EPIC summary + decisions at EPIC completion
    gate_results: false                 # Index gate pass/fail results (verbose, opt-in)

  search:
    top_k: 5                            # Max results to retrieve per query
    timeout_seconds: 5                  # Max wait for Qdrant response
    min_score: 0.4                      # Minimum similarity score to include result
    pre_step_search: true               # Search memory before agent dispatch

  document_types:
    - decision
    - lesson
    - pattern
    - command
    - audit_finding
```

---

## Document Types

AID indexes 5 types of knowledge. Each type has a defined metadata schema and indexing trigger.

### Type 1: Decision

Architectural, technical, or process decisions made during sessions or EPICs.

**Source:** Session log entries, `decisions.yaml`, architect agent outputs, ADRs
**Trigger:** Session-end, EPIC DONE
**Metadata schema:**

```json
{
  "type": "decision",
  "session_id": "S-20260217-2eec",
  "epic_id": "ADO-0001",
  "date": "2026-02-17",
  "area": "authentication",
  "decision": "Use JWT with refresh tokens",
  "context": "Brief context of why this decision was made",
  "alternatives_considered": ["session cookies", "OAuth2 only"]
}
```

**Text stored:** `"Decision: {decision}. Context: {context}. Area: {area}. Alternatives: {alternatives}."`

---

### Type 2: Lesson

Lessons learned from debugging, implementation challenges, or process improvements.

**Source:** `lessons-learned.md`, session completion notes, agent improvement_notes
**Trigger:** Session-end
**Metadata schema:**

```json
{
  "type": "lesson",
  "session_id": "S-20260217-2eec",
  "date": "2026-02-17",
  "category": "debugging|performance|testing|process|architecture",
  "severity": "gotcha|tip|warning",
  "tags": ["fastapi", "async", "database"]
}
```

**Text stored:** The lesson text as-is from `lessons-learned.md`.

---

### Type 3: Pattern

Code patterns, architectural patterns, or workflow patterns observed across EPICs.

**Source:** Agent outputs (from `## IMPROVEMENT NOTES`), code-reviewer findings,
architect agent design documents
**Trigger:** EPIC DONE
**Metadata schema:**

```json
{
  "type": "pattern",
  "epic_id": "ADO-0001",
  "agent_role": "backend",
  "date": "2026-02-17",
  "pattern_type": "code|architecture|workflow|testing",
  "language": "python",
  "tags": ["repository-pattern", "dependency-injection"]
}
```

**Text stored:** Pattern description + code snippet (if applicable, max 500 tokens).

---

### Type 4: Command

Working commands discovered during sessions (build, test, deploy, lint).

**Source:** `command-history.md`, lessons-extractor output
**Trigger:** Session-end
**Metadata schema:**

```json
{
  "type": "command",
  "session_id": "S-20260217-2eec",
  "date": "2026-02-17",
  "tool": "pytest|npm|docker|git|custom",
  "category": "build|test|deploy|lint|database",
  "project_specific": true
}
```

**Text stored:** `"{command} — {description}. Context: {when_to_use}."`

---

### Type 5: Audit Finding

Findings from post-EPIC audits (code quality, security, documentation issues).

**Source:** `audit-report.md`, auditor agent output
**Trigger:** EPIC DONE
**Metadata schema:**

```json
{
  "type": "audit_finding",
  "epic_id": "ADO-0001",
  "date": "2026-02-17",
  "audit_category": "code_quality|security|documentation|frontend|database",
  "severity": "critical|warning|suggestion",
  "score": 85,
  "tags": ["sql-injection", "missing-docs"]
}
```

**Text stored:** Finding description + recommendation.

---

## Memory Protocol Functions

These functions provide the abstraction layer over Qdrant MCP. All consumers
(agent-core, session-management, run-epic) use these — never call `qdrant-store`
or `qdrant-find` directly.

### `check_memory_enabled()`

```
1. Read .aid-o/03-config/policies/memory-config.yaml
2. IF file exists AND memory.enabled = true:
     return { enabled: true, config: <parsed yaml> }
3. ELSE:
     return { enabled: false }
```

### `memory_store(document_type, text, metadata)`

```
mem = check_memory_enabled()
IF NOT mem.enabled:
  return  # Silent no-op

TRY:
  # AUTO-INJECT project_name for cross-project knowledge sharing
  project_profile = read_if_exists(".aid-o/04-engine/memory/project-profile.yaml")
  IF project_profile AND project_profile.project_name:
    metadata.project_name = project_profile.project_name
  ELSE:
    metadata.project_name = "unknown"  # Fallback — should not happen in initialized projects

  full_metadata = merge(metadata, {
    "type": document_type,
    "indexed_at": current_iso_timestamp()
  })

  qdrant-store(
    information = text,
    metadata = full_metadata,
    collection_name = mem.config.memory.collection_name
  )

  log_memory_event("store", document_type, "success")

CATCH (tool_not_found, timeout, any_error):
  log_memory_event("store", document_type, "failed", error_message)
  # Silent failure — never block workflow for memory indexing
```

**IMPORTANT:** The `project_name` field is MANDATORY in all Qdrant writes.
It enables cross-project knowledge sharing (see `epic-orchestration.md` DONE
state, Qdrant Project Tagging section). The auto-injection ensures all callers
get `project_name` without having to pass it explicitly.

### `memory_find(query, document_type_filter = null)`

```
mem = check_memory_enabled()
IF NOT mem.enabled:
  return []  # Empty results, caller proceeds without memory

IF NOT mem.config.memory.search.pre_step_search:
  return []  # Search disabled in config

TRY (timeout = mem.config.memory.search.timeout_seconds):
  results = qdrant-find(
    query = query,
    collection_name = mem.config.memory.collection_name
  )

  # Filter by minimum score
  filtered = [r for r in results if r.score >= mem.config.memory.search.min_score]

  # Filter by document type if specified
  IF document_type_filter:
    filtered = [r for r in filtered if r.metadata.type == document_type_filter]

  # Limit to top_k
  filtered = filtered[:mem.config.memory.search.top_k]

  log_memory_event("find", query[:50], "success", count=len(filtered))
  return filtered

CATCH (tool_not_found, timeout, any_error):
  log_memory_event("find", query[:50], "failed", error_message)
  return []  # Empty results, caller proceeds without memory
```

### `memory_index_session(session_file_path)`

Index knowledge from a completed session. Called by `session-end.md`.

```
mem = check_memory_enabled()
IF NOT mem.enabled OR NOT mem.config.memory.auto_index.session_end:
  return

session = read(session_file_path)

# 1. Index decisions from session log
decisions = extract_decisions(session.ai_session_log)
FOR EACH decision IN decisions:
  memory_store("decision", decision.text, {
    "session_id": session.id,
    "date": session.started,
    "area": decision.area,           # inferred from context
    "decision": decision.summary
  })

# 2. Index new lessons (from lessons-learned.md diff)
new_lessons = read_new_entries(".aid-o/04-engine/lessons-learned.md", since=session.started)
FOR EACH lesson IN new_lessons:
  memory_store("lesson", lesson.text, {
    "session_id": session.id,
    "date": session.started,
    "category": lesson.category,
    "severity": lesson.severity
  })

# 3. Index new commands (from command-history.md diff)
new_commands = read_new_entries(".aid-o/04-engine/command-history.md", since=session.started)
FOR EACH cmd IN new_commands:
  memory_store("command", cmd.text, {
    "session_id": session.id,
    "date": session.started,
    "tool": cmd.tool,
    "category": cmd.category
  })

log_memory_event("index_session", session.id, "success",
  counts={ decisions: len(decisions), lessons: len(new_lessons), commands: len(new_commands) })
```

### `memory_index_epic(epic_id, run_id, evidence_path)`

Index knowledge from a completed EPIC. Called by `run-epic.md` DONE state.

```
mem = check_memory_enabled()
IF NOT mem.enabled OR NOT mem.config.memory.auto_index.epic_done:
  return

# 1. Index EPIC summary
plan = read(evidence_path + "/plan.json")
progress = read(evidence_path + "/plan_progress.json")
memory_store("decision", build_epic_summary(plan, progress), {
  "epic_id": epic_id,
  "date": current_date(),
  "area": "epic-summary",
  "decision": plan.epic_title + " — completed"
})

# 2. Index architectural decisions (from architect step output)
architect_output = find_step_output(evidence_path, role="architect")
IF architect_output:
  decisions = extract_decisions(architect_output)
  FOR EACH d IN decisions:
    memory_store("decision", d.text, {
      "epic_id": epic_id,
      "date": current_date(),
      "area": d.area,
      "decision": d.summary
    })

# 3. Index patterns from agent outputs
FOR EACH step_output IN all_step_outputs(evidence_path):
  patterns = extract_patterns(step_output)
  FOR EACH p IN patterns:
    memory_store("pattern", p.text, {
      "epic_id": epic_id,
      "agent_role": step_output.role,
      "date": current_date(),
      "pattern_type": p.pattern_type
    })

# 4. Index audit findings (if audit report exists)
audit_report = read_if_exists(evidence_path + "/audit-report.md")
IF audit_report:
  findings = extract_findings(audit_report)
  FOR EACH f IN findings:
    memory_store("audit_finding", f.text, {
      "epic_id": epic_id,
      "date": current_date(),
      "audit_category": f.category,
      "severity": f.severity,
      "score": f.score
    })

# 5. Optionally index gate results
IF mem.config.memory.auto_index.gate_results:
  gates_report = read(evidence_path + "/gates_report.json")
  memory_store("audit_finding", build_gates_summary(gates_report), {
    "epic_id": epic_id,
    "date": current_date(),
    "audit_category": "gates",
    "severity": "suggestion"
  })

log_memory_event("index_epic", epic_id, "success")
```

### `memory_context_for_step(step, epic_context)`

Retrieve relevant memory context before dispatching an agent for a step.
Called by `run-epic.md` EXECUTING state.

```
mem = check_memory_enabled()
IF NOT mem.enabled OR NOT mem.config.memory.search.pre_step_search:
  return ""  # No memory context

# Build search queries from step context
queries = [
  step.objective,                              # What the step does
  step.role + " " + epic_context.area,        # Role + domain
]

# Collect results across queries, deduplicate
all_results = []
FOR EACH q IN queries:
  results = memory_find(q)
  all_results.extend(results)

# Deduplicate by information text (keep highest score)
unique = deduplicate_by_text(all_results, keep="highest_score")

# Limit total context
unique = unique[:mem.config.memory.search.top_k]

IF len(unique) == 0:
  return ""

# Format as context block for agent prompt
context = "## MEMORY CONTEXT (from past sessions)\n\n"
context += "_The following knowledge was retrieved from past sessions. "
context += "Use it as reference — do not blindly follow if project context has changed._\n\n"

FOR EACH r IN unique:
  context += "### " + r.metadata.type.title() + " (" + r.metadata.date + ")\n"
  context += r.information + "\n"
  IF r.metadata.session_id:
    context += "_Source: " + r.metadata.session_id + "_\n"
  ELIF r.metadata.epic_id:
    context += "_Source: " + r.metadata.epic_id + "_\n"
  context += "\n"

return context
```

---

## Fallback Protocol

### When Qdrant MCP is not configured

```
IF .aid-o/03-config/policies/memory-config.yaml does not exist
   OR memory.enabled = false:

  → All memory_* functions return immediately (no-op / empty results)
  → File-based memory continues to work as before (active-work.md, lessons-learned.md, etc.)
  → No MCP tool calls are made
  → No log messages (completely transparent)
```

### When Qdrant MCP server is unavailable

```
IF qdrant-store or qdrant-find tool call fails:

  → For memory_store: silently skip, log warning to memory_log.jsonl
  → For memory_find: return empty results, log warning
  → NEVER block any workflow (session-end, EPIC execution, agent dispatch)
  → NEVER retry memory operations (unlike Slack which retries 3x)
    Rationale: memory is supplementary, not critical-path
  → Log once per session: "Qdrant MCP unavailable — proceeding with file-based memory only"
```

### When results are empty or low quality

```
IF memory_find returns 0 results OR all results below min_score:

  → Agent is dispatched without memory context (normal behavior)
  → No warning needed (empty memory is expected for new projects)
```

---

## Evidence Logging

Memory operations are logged to:

```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/memory_log.jsonl
```

For non-EPIC sessions, log to:

```
.aid-o/04-engine/memory/memory_log.jsonl
```

Format (one JSON object per line):

```json
{"ts": "2026-02-17T10:00:00Z", "action": "store", "type": "decision", "status": "success", "collection": "aid-memory"}
{"ts": "2026-02-17T10:00:01Z", "action": "store", "type": "lesson", "status": "success", "collection": "aid-memory"}
{"ts": "2026-02-17T10:00:02Z", "action": "find", "query": "authentication patterns", "status": "success", "results": 3, "collection": "aid-memory"}
{"ts": "2026-02-17T10:00:05Z", "action": "store", "type": "pattern", "status": "failed", "error": "Qdrant MCP unavailable", "collection": "aid-memory"}
{"ts": "2026-02-17T10:01:00Z", "action": "index_session", "session_id": "S-20260217-2eec", "status": "success", "counts": {"decisions": 3, "lessons": 2, "commands": 5}}
{"ts": "2026-02-17T11:00:00Z", "action": "index_epic", "epic_id": "ADO-0001", "status": "success"}
```

---

## Reference Files

- `skills/agent-core.md` — Context loading protocol (consumer: memory-augmented context)
- `skills/session-management.md` — Session completion protocol (consumer: session-end indexing)
- `skills/epic-orchestration.md` — DONE state definition (consumer: EPIC DONE indexing)
- `commands/run-epic.md` — EXECUTING state (consumer: pre-step memory retrieval) + DONE state (consumer: EPIC indexing)
- `commands/session-end.md` — Session-end command (consumer: session-end indexing)
- `commands/aid-setup.md` — Qdrant detection during onboarding
- `commands/aid-init.md` — Memory config file creation
- `defaults/policies/memory-config.yaml` — Configuration file
- `agents/lessons-extractor.md` — Produces lessons + commands (indexed by memory_index_session)

---

## Important

- The Qdrant MCP server is **external** to the AID plugin. AID defines the protocol
  and document schemas; it does not implement the MCP server itself.
- All memory operations are **non-blocking**. A Qdrant failure must NEVER interrupt
  session completion, EPIC execution, or agent dispatch.
- File-based memory (`active-work.md`, `lessons-learned.md`, `command-history.md`,
  `decisions.yaml`) remains the **primary** and **authoritative** source of truth.
  Qdrant adds semantic search on top of this — it does not replace it.
- Memory context injected into agent prompts is clearly labeled as
  `## MEMORY CONTEXT (from past sessions)` so agents know it's historical reference,
  not current session state.
- The `min_score` threshold (default 0.4) prevents irrelevant results from polluting
  agent context. Tune per project in `memory-config.yaml`.
- Embedding runs locally via FastEmbed (`sentence-transformers/all-MiniLM-L6-v2`).
  No external API calls, no cost, no API keys needed for embeddings.
- Collection management (create, delete, inspect) is done via Qdrant's own dashboard
  or REST API — not via MCP tools. The `qdrant-store` tool auto-creates collections.
