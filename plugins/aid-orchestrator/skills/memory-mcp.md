# Memory MCP Integration — Long-Term Vector Memory Protocol

**Version:** 0.5.0
**Skill:** memory-mcp
**Dependencies:** session-management, epic-orchestration

---

## Storage Architecture

Qdrant data is stored CENTRALLY, not per-project:

- Path: `~/.local/share/aid-orchestrator/qdrant-data`
- MCP scope: `user` (global — available in all projects)
- All projects write to the same `aid-memory` collection
- Entries are tagged with `project_name` in metadata for filtering
- Deleting a project does NOT delete its Qdrant entries
- Cross-project search works because all data is in one place

This is different from `.aid-o/` which is per-project.

## TL;DR

This skill defines how AID stores and retrieves knowledge across sessions using a Qdrant
MCP server. Agents auto-index decisions, lessons, patterns, audit findings, and documentation
at session-end, EPIC completion, and research triggers. Before dispatching an agent, the
Controller retrieves relevant past knowledge to augment the agent's context — enabling agents
to learn from history.

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
    - documentation
    - example_epic
```

---

## Document Types

AID indexes 8 types of knowledge. Each type has a defined metadata schema and indexing trigger.

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

### Type 6: Documentation

Framework and library documentation chunks acquired through the knowledge-acquisition
research pipeline (Context7 MCP primary, WebSearch fallback).

**Source:** Context7 MCP (`query-docs`), WebSearch + WebFetch (fallback), PM-provided URLs (Phase 2)
**Trigger:** `/aid-setup` onboarding, `/aid-brainstorm` framework detection, `/aid-research` (Phase 2)
**Quality gates:** All documentation chunks MUST pass the 4-gate quality protocol before storage
(see Documentation Quality Gate Protocol below). Other document types bypass quality gates.
**Metadata schema:**

```json
{
  "type": "documentation",
  "framework": "FastAPI",
  "framework_version": "0.115.x",
  "section": "dependency-injection",
  "source": "context7",
  "source_url": "https://fastapi.tiangolo.com/tutorial/dependencies/",
  "source_library_id": "/tiangolo/fastapi",
  "indexed_at": "2026-02-20T10:00:00Z",
  "valid_until": "2026-05-20T10:00:00Z",
  "project_name": "global",
  "confidence": "high",
  "depth": "quick"
}
```

**Field descriptions:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | yes | Always `"documentation"` for this document type |
| `framework` | string | yes | Framework/library name (e.g., `"FastAPI"`, `"React"`) |
| `framework_version` | string | recommended | Version string detected from docs (e.g., `"0.115.x"`) |
| `section` | string | recommended | Logical section within the framework docs (e.g., `"dependency-injection"`, `"authentication"`) |
| `source` | string | yes | Origin of the chunk: `"context7"`, `"websearch"`, or `"manual"` |
| `source_url` | string | recommended | URL of the original documentation page |
| `source_library_id` | string | auto | Context7 library ID (e.g., `"/tiangolo/fastapi"`), null for websearch |
| `indexed_at` | ISO 8601 | yes | Timestamp when the chunk was stored |
| `valid_until` | ISO 8601 | auto | Expiration timestamp: `indexed_at + 90 days` |
| `project_name` | string | auto | Always `"global"` for documentation (shared across projects) |
| `confidence` | string | auto | Quality confidence level: `"high"`, `"medium"`, or `"low"` (see Confidence Scoring) |
| `depth` | string | auto | Research depth that produced this chunk: `"quick"` or `"deep"` |

**Text stored:** Documentation chunk text — one concept, pattern, API endpoint, or code
snippet per chunk. Target size: 50-500 words, max ~2000 tokens.

**Example stored text:**
```
FastAPI Depends(): Use for dependency injection. Supports async. Nested deps resolved
automatically. Use yield for cleanup (DB sessions). Example:
  async def get_db():
    db = SessionLocal()
    try:
      yield db
    finally:
      db.close()
```

**Key differences from other types:**
- Uses `project_name="global"` (not the current project name) because framework
  documentation is universal and shared across all projects.
- Requires 4-gate quality validation before storage (other types store directly).
- Has a `valid_until` TTL field (90 days default) for freshness tracking (Phase 2).
- Full research and storage protocol defined in `skills/knowledge-acquisition.md`.

---

### Type 7: Proposal

Structured proposals generated by agents for PM review — architectural approaches, technology
selections, or process changes that require human approval before implementation.

**Source:** Architect agent outputs, PM-requested proposals, brainstorming sessions
**Trigger:** Explicit proposal generation (not auto-indexed at session-end)
**Metadata schema:**

```json
{
  "type": "proposal",
  "epic_id": "ADO-0001",
  "session_id": "S-20260217-2eec",
  "date": "2026-02-17",
  "proposal_type": "architecture|technology|process|design",
  "status": "pending|approved|rejected",
  "area": "authentication",
  "tags": ["jwt", "oauth2", "security"]
}
```

**Text stored:** Proposal title + summary + rationale + options considered.

---

### Type 8: Example EPIC

Complete EPIC templates extracted from successfully completed EPICs. Represents a full
project archetype — step sequence, role assignments, architectural decisions — abstracted
from a real implementation. Unlike `pattern` (single reusable pattern from one step),
`example_epic` captures the complete orchestration shape of a project type.

**Source:** `extract_example_epic()` in `skills/knowledge-acquisition.md` (Phase 3)
**Trigger:** EPIC DONE state (step 9b), after Curator, requires PM approval
**Quality gates:** Eligibility check (completed EPIC only), PM approval, deduplication (0.85 threshold)
**TTL:** Never expires (`get_ttl_days("example_epic") → null`)

**Metadata schema:**

```json
{
  "type": "example_epic",
  "frameworks": ["langchain", "chromadb", "fastapi"],
  "archetype": "rag-chatbot",
  "source_epic_id": "E-20260215-a3f2",
  "source_project": "customer-support-bot",
  "step_count": 6,
  "roles": ["architect", "backend", "qa"],
  "complexity": "medium",
  "indexed_at": "2026-02-20T10:00:00Z",
  "confidence": "high",
  "project_name": "global"
}
```

**Field descriptions:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | yes | Always `"example_epic"` |
| `frameworks` | string[] | yes | Framework names from project-profile (lowercase, no version pins) |
| `archetype` | string | yes | Kebab-case archetype name (e.g., `"rag-chatbot"`, `"crud-api"`, `"dashboard"`) |
| `source_epic_id` | string | yes | EPIC ID that produced this example |
| `source_project` | string | yes | Project name from project-profile.yaml |
| `step_count` | integer | yes | Number of steps in the source EPIC |
| `roles` | string[] | yes | Ordered, deduplicated list of agent roles used |
| `complexity` | string | yes | `"simple"` (1-4 steps), `"medium"` (5-8), `"complex"` (9+) |
| `indexed_at` | ISO 8601 | yes | When the entry was stored |
| `confidence` | string | yes | Always `"high"` (only completed EPICs are stored) |
| `project_name` | string | yes | Always `"global"` (examples are cross-project) |

**Text stored:** `"{archetype}: {frameworks}. Architecture: {summary}. Steps ({N}): {role: objective list}. Key decisions: {decisions}. Patterns: {patterns}."`

**Difference from `pattern` type:**
- `pattern` = single reusable code/architecture pattern from one agent step
- `example_epic` = complete EPIC template covering an entire project archetype (multi-step, multi-role)

**Search protocol:**
```
search_example_epics(topic, tech_stack):
  query = "{topic} {tech_stack frameworks joined}"
  results = memory_find(query, document_type_filter="example_epic")
  RETURN results filtered by min_score > 0.4
```

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

  # Step 1: Filter by minimum score
  filtered = [r for r in results if r.score >= mem.config.memory.search.min_score]

  # Step 2: Filter by document type if specified
  IF document_type_filter:
    filtered = [r for r in filtered if r.metadata.type == document_type_filter]

  # Step 3: Apply freshness weighting (Phase 2 aging protocol)
  #   - Reads aging config from memory-config.yaml
  #   - If aging config exists: weight scores, exclude ancient, add stale/expired labels
  #   - If no aging config: skip entirely (backward compatible -- identical to Phase 1)
  filtered = apply_freshness_to_memory_results(filtered)

  # Step 4: Limit to top_k
  filtered = filtered[:mem.config.memory.search.top_k]

  log_memory_event("find", query[:50], "success", count=len(filtered))
  return filtered

  # Phase 3: Feedback tracking (fire-and-forget)
  # After returning results, schedule track_retrieval() to update knowledge-base.yaml
  # See: skills/knowledge-acquisition.md → Feedback Tracking Protocol
  IF mem.config.memory.feedback.track_retrieval == true:
    schedule_background(track_retrieval, filtered, knowledge_base_path)

CATCH (tool_not_found, timeout, any_error):
  log_memory_event("find", query[:50], "failed", error_message)
  return []  # Empty results, caller proceeds without memory
```

### `apply_freshness_to_memory_results(results)`

Integration wrapper that applies the aging protocol's freshness weighting to memory search
results. Calls `compute_freshness_weight()` from `knowledge-acquisition.md` for each result.
Without aging config in `memory-config.yaml`, returns results unchanged (backward compatible).

```
apply_freshness_to_memory_results(results):

  config = read_knowledge_config()  # from memory-config.yaml knowledge: section
  IF config is null OR config.knowledge is null OR config.knowledge.aging is null:
    RETURN results  # No aging config -- backward compatible, identical to Phase 1

  weighted = []
  FOR EACH r IN results:
    freshness = compute_freshness_weight(r)  # from knowledge-acquisition.md

    # Ancient entries (weight == 0.0) are excluded entirely
    IF freshness.weight == 0.0:
      log("Excluding ancient entry from memory_find: {type}/{framework}, indexed {date}".format(
        type = r.metadata.type,
        framework = r.metadata.framework OR "unknown",
        date = r.metadata.indexed_at[:10] IF r.metadata.indexed_at ELSE "unknown"
      ))
      CONTINUE

    # Preserve original score, apply freshness weight
    r.original_score = r.score
    r.score = r.score * freshness.weight
    r.freshness_category = freshness.category

    # Attach stale/expired warning label if present
    IF freshness.label:
      r.freshness_label = freshness.label

    weighted.append(r)

  # Re-sort by weighted score (highest first)
  RETURN sorted(weighted, key=r.score, descending=True)
```

**Freshness label format** (generated by `compute_freshness_weight()` in knowledge-acquisition.md):
- Stale: `"Warning: Stale (indexed {date}, {framework} {version} -- current may differ)"`
- Expired: `"Warning: Expired (indexed {date}, {framework} {version} -- likely outdated)"`
- Active: no label (null)
- Ancient: excluded, no label needed

**Backward compatibility:** When `knowledge.aging` is absent from `memory-config.yaml`,
this function returns `results` unmodified. No scores are changed, no labels are added,
no entries are excluded. `memory_find()` behaves identically to Phase 1.

---

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
  # Display freshness warning label if present (stale or expired entries)
  IF r.freshness_label:
    context += "_" + r.freshness_label + "_\n"
  context += r.information + "\n"
  IF r.metadata.session_id:
    context += "_Source: " + r.metadata.session_id + "_\n"
  ELIF r.metadata.epic_id:
    context += "_Source: " + r.metadata.epic_id + "_\n"
  context += "\n"

return context
```

---

## Documentation Quality Gate Protocol

When `document_type == "documentation"`, all chunks MUST pass the 4-gate quality protocol
before being stored via `qdrant-store`. Other document types (decision, lesson, pattern,
command, audit_finding) bypass quality gates and store directly — existing behavior is
unchanged.

The authoritative definition of the research pipeline, chunking logic, and storage flow
lives in `skills/knowledge-acquisition.md`. This section defines the gate protocol that
`memory_store` enforces for the `documentation` type.

### Quality Gate Integration in `memory_store`

When `memory_store("documentation", text, metadata)` is called, the following gate sequence
runs before the `qdrant-store` call. If any gate rejects the chunk, storage is skipped and
the rejection is logged. Non-documentation types proceed directly to `qdrant-store` as before.

```
memory_store(document_type, text, metadata):

  # ... existing flow (check_memory_enabled, project_name injection) ...

  # DOCUMENTATION QUALITY GATES — only for documentation type
  IF document_type == "documentation":
    gate_result = run_documentation_quality_gates(text, metadata)

    IF NOT gate_result.passed:
      log_memory_event("store", "documentation", "rejected",
        gate=gate_result.gate, reason=gate_result.reason)
      RETURN gate_result  # Caller handles rejection (merge, split, or discard)

  # ... existing flow (qdrant-store call, logging) ...
```

### Gate 1: Minimum Informational Value

Purpose: Reject marketing fluff, navigation fragments, and content too vague to help agents.

```
gate_1_min_value(chunk_text):

  PASS if chunk contains at least one of:
    - Specific API/function/class/method with description
    - Code snippet (minimum 2 lines)
    - Concrete pattern/procedure with explanation
    - Specific constraint/gotcha/caveat with actionable detail

  REJECT if chunk is:
    - Marketing text ("FastAPI is the fastest framework...")
    - Too generic ("You can use databases with FastAPI")
    - Navigation/menu content ("Home > Docs > Tutorial > ...")
    - Shorter than 50 words AND contains no code snippet

  RETURN:
    { passed: true|false, gate: "min_value", reason: "description if failed" }
```

### Gate 2: Deduplication (0.85 Threshold)

Purpose: Prevent storing content that already exists in Qdrant.

```
gate_2_deduplication(chunk_text):

  existing = memory_find(chunk_text, min_score=0.70)

  IF match found with score > 0.85:
    RETURN { passed: false, gate: "dedup", action: "reject",
             reason: "duplicate (score {score})", existing_id: match.id }

  IF match found with score 0.70 - 0.85:
    RETURN { passed: false, gate: "dedup", action: "merge",
             reason: "partial_overlap (score {score})", existing_match: match }
    # Caller keeps the better version (longer, more specific, newer source)

  IF no match OR all scores < 0.70:
    RETURN { passed: true }

  # For documentation type: also check same source_library_id + section
  # to prevent duplicates from re-fetching the same Context7 library.
```

### Gate 3: Metadata Completeness

Purpose: Ensure every stored chunk has enough metadata for filtering and attribution.

```
gate_3_metadata(chunk_text, metadata):

  REQUIRED fields (reject without):
    - type                    # must be "documentation"
    - framework               # framework name (e.g., "FastAPI")
    - source                  # "context7" | "websearch" | "manual"
    - indexed_at              # ISO 8601 timestamp

  RECOMMENDED fields (warn in log but allow storage):
    - framework_version       # version string
    - section                 # logical section within docs
    - source_url              # URL of original page
    - valid_until             # expiration timestamp

  AUTO-COMPUTED fields (filled by protocol if missing):
    - valid_until:    indexed_at + 90 days (if not provided)
    - project_name:   "global" (always, for documentation type)
    - confidence:     based on source tier (see Confidence Scoring Table)
    - depth:          from research function parameter

  IF any REQUIRED field is missing:
    RETURN { passed: false, gate: "metadata", reason: "missing required: {field}" }

  IF any RECOMMENDED field is missing:
    log("Warning: chunk missing recommended field: {field}")

  RETURN { passed: true, auto_filled: [list of auto-computed fields added] }
```

### Gate 4: Size Limits (50-500 Words, 2000 Tokens Max)

Purpose: Keep chunks within the optimal size range for embedding quality and agent context.

```
gate_4_size(chunk_text):

  word_count = count_words(chunk_text)
  has_code = contains_code_block(chunk_text)

  # Minimum size check
  IF word_count < 50 AND NOT has_code:
    RETURN { passed: false, gate: "size", action: "reject",
             reason: "too_short ({word_count} words, no code)" }

  IF has_code AND count_code_lines(chunk_text) < 2:
    RETURN { passed: false, gate: "size", action: "reject",
             reason: "code_too_short (under 2 lines)" }

  # Maximum size check
  token_count = estimate_tokens(chunk_text)
  IF token_count > 2000:
    RETURN { passed: false, gate: "size", action: "split",
             reason: "too_large (~{token_count} tokens, split into sub-chunks)" }
    # Caller splits the chunk and re-runs all gates on each sub-chunk

  RETURN { passed: true }
```

### `run_documentation_quality_gates(text, metadata)`

Orchestrates the 4 gates in order. A chunk rejected at Gate N does not proceed to Gate N+1.

```
run_documentation_quality_gates(text, metadata):

  # Gate 1: Minimum informational value
  g1 = gate_1_min_value(text)
  IF NOT g1.passed:
    RETURN g1

  # Gate 2: Deduplication
  g2 = gate_2_deduplication(text)
  IF NOT g2.passed:
    RETURN g2

  # Gate 3: Metadata completeness
  g3 = gate_3_metadata(text, metadata)
  IF NOT g3.passed:
    RETURN g3
  # Apply auto-computed fields
  IF g3.auto_filled:
    apply_auto_fields(metadata, g3.auto_filled)

  # Gate 4: Size limits
  g4 = gate_4_size(text)
  IF NOT g4.passed:
    RETURN g4

  # All gates passed
  RETURN { passed: true, gates_run: 4 }
```

### Confidence Scoring Reference Table

Confidence is auto-assigned based on the source that produced the chunk. It affects
retrieval ranking: when multiple chunks match a query, higher-confidence chunks are
preferred in the results ordering.

| Source | Default Confidence | Notes |
|--------|-------------------|-------|
| Context7 MCP | high | Curated, up-to-date documentation |
| Official docs (WebFetch Tier 1) | high | github.io, readthedocs, framework homepage |
| GitHub README (WebFetch Tier 2) | medium | May be outdated or incomplete |
| WebSearch result (Tier 2) | medium | Mixed quality, version uncertain |
| PM manual URL (Phase 2) | medium | PM vouches for relevance |

### Quality Gate Evidence Logging

Quality gate results for documentation chunks are logged to the standard memory log:

```json
{"ts": "2026-02-20T10:00:00Z", "action": "store", "type": "documentation", "status": "success", "collection": "aid-memory", "gates": "4/4 passed"}
{"ts": "2026-02-20T10:00:01Z", "action": "store", "type": "documentation", "status": "rejected", "gate": "dedup", "reason": "duplicate (score 0.91)", "collection": "aid-memory"}
{"ts": "2026-02-20T10:00:02Z", "action": "store", "type": "documentation", "status": "rejected", "gate": "size", "reason": "too_short (23 words, no code)", "collection": "aid-memory"}
{"ts": "2026-02-20T10:00:03Z", "action": "store", "type": "documentation", "status": "rejected", "gate": "min_value", "reason": "marketing text", "collection": "aid-memory"}
{"ts": "2026-02-20T10:00:04Z", "action": "store", "type": "documentation", "status": "rejected", "gate": "size", "action": "split", "reason": "too_large (~3200 tokens)", "collection": "aid-memory"}
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

## Cross-Project Knowledge Protocol

Qdrant serves as the SINGLE cross-project knowledge store. Every entry is
tagged with `project_name` so knowledge from Project A can inform Project B.

### Architecture

```
Project A (.aid-o/)              Project B (.aid-o/)
  lessons-learned.md               lessons-learned.md
  command-history.md               command-history.md
        | write                          | write
  +---------------------------------------------+
  |         Qdrant: aid-memory collection       |
  |  entry: { data, project_name, type, ... }   |
  |                                             |
  |  Semantic search across ALL projects        |
  +---------------------------------------------+
        ^ read                           ^ read
  Project C (starting)             Project D (planning)
```

### Write Protocol (DONE state)

Every `qdrant-store` call includes mandatory metadata:

```json
{
  "collection_name": "aid-memory",
  "data": "{lesson/command/decision text}",
  "metadata": {
    "project_name": "{from project-profile.yaml}",
    "epic_id": "{epic_id}",
    "type": "lesson|command|decision|pattern|audit_finding|documentation|example_epic",
    "category": "{category}",
    "timestamp": "{ISO 8601}",
    "tech_stack": "{languages + frameworks from project-profile}"
  }
}
```

The `tech_stack` field enables filtering: when Project B uses FastAPI,
it can find lessons tagged with "Python, FastAPI" from Project A.

### Read Protocol (IDLE state + EXECUTING state)

**At IDLE (before planning):**
1. If Qdrant available: `qdrant-find` with query = EPIC goal + tech stack
2. Filter: `type IN (lesson, pattern, decision)`, exclude current project's entries
   (those are already in local .md files)
3. Include top 3 cross-project results in Planner context:
   ```
   CROSS-PROJECT KNOWLEDGE (from Qdrant):
   - [project-A] Async SQLAlchemy: use db.refresh() after mutations
   - [project-B] ruff --fix + format resolves all F401 issues automatically
   - [project-C] Slack MCP requires users:read scope or crashes at startup
   ```

**At EXECUTING (before agent dispatch):**
1. If `memory.search.pre_step_search: true`:
2. `qdrant-find` with query = step objective + role
3. Include top 3 results (cross-project + same-project) in agent dispatch prompt:
   ```
   RELEVANT KNOWLEDGE (from memory):
   - {lesson} (source: {project_name})
   ```

### No Qdrant = No Cross-Project (Graceful Degradation)

If Qdrant is not configured or unavailable:
- Local .md files work normally (per-project)
- Cross-project search returns empty results
- No error, no warning (beyond initial IDLE log)
- This is an expected state for users who do not want or need Qdrant

---

## Reference Files

- `skills/agent-core.md` — Context loading protocol (consumer: memory-augmented context)
- `skills/session-management.md` — Session completion protocol (consumer: session-end indexing)
- `skills/epic-orchestration.md` — DONE state definition (consumer: EPIC DONE indexing)
- `commands/aid-run-epic.md` — EXECUTING state (consumer: pre-step memory retrieval) + DONE state (consumer: EPIC indexing)
- `skills/session-management.md` — Session-end protocol (consumer: session-end indexing)
- `skills/knowledge-acquisition.md` — Research pipeline, chunking, storage flow for documentation type; **Aging Protocol** section defines `compute_freshness_weight()` and `apply_freshness_weighting()` used by `apply_freshness_to_memory_results()` in this file
- `commands/aid-setup.md` — Qdrant detection during onboarding, triggers knowledge research
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
