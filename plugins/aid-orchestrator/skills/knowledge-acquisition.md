# Knowledge Acquisition — Research, Storage, and Consumption Protocol

**Version:** 0.5.0
**Skill:** knowledge-acquisition
**Dependencies:** memory-mcp, session-management, epic-orchestration

---

## TL;DR

This skill defines how AID actively acquires, quality-gates, stores, and serves framework
documentation and technical knowledge. It extends the existing memory-mcp skill with a new
`documentation` document type, a multi-source research pipeline (Context7 primary, WebSearch
fallback), 4 mandatory quality gates, and consumption functions that feed knowledge into
brainstorming sessions and agent dispatch.

**Principle:** Knowledge acquisition is non-blocking. Every operation degrades gracefully --
Context7 unavailable falls back to WebSearch, WebSearch fails falls back to in-session-only,
Qdrant unavailable means results are useful in the current session but not persisted. No
research failure ever blocks a workflow.

**Primary source:** Context7 MCP (curated, up-to-date documentation for 1000+ libraries).
**Fallback source:** WebSearch + WebFetch (official docs, GitHub READMEs).
**Storage:** Dual -- per-project YAML index (`knowledge-base.yaml`) + global Qdrant store
(`aid-memory` collection, `documentation` type).

---

## Storage Architecture

### Design Principle: Dual Storage

```
knowledge-base.yaml = per-project (in .aid-o/04-engine/memory/)
  -> "What THIS project needs to know"
  -> Reference index of frameworks relevant to THIS stack
  -> Never edited manually by PM -- AI manages it

Qdrant = global (in ~/.local/share/aid-orchestrator/)
  -> Actual content (documentation chunks)
  -> Shared across all projects
  -> Tag: project_name="global" for documentation chunks
```

**Why YAML for references:** URLs, versions, TTL, status -- these are structured attributes
requiring exact filtering (`status == active AND framework == FastAPI`), not semantic search.
YAML is simple, readable, and allows PM override if needed.

**Why Qdrant for documentation chunks:** Semantic search is essential. Agent asks "how to do
dependency injection in FastAPI" -- this requires meaning-based retrieval, not keyword matching.

### Cross-Project Sharing Flow

```
Project A: FastAPI + React
  .aid-o/04-engine/memory/knowledge-base.yaml:
    sources: [FastAPI, React, Pydantic]
  -> Research stores chunks in Qdrant with framework="FastAPI", project_name="global"

Project B: FastAPI + Vue
  .aid-o/04-engine/memory/knowledge-base.yaml:
    sources: [FastAPI, Vue, Pydantic]
  -> Research for FastAPI:
    knowledge_find("FastAPI documentation") -> FINDS chunks from Project A
    -> Skip re-fetch, just add reference to B's knowledge-base.yaml, NO re-fetch
    -> Research only Vue (new)

New project with FastAPI does NOT re-fetch -- it reuses existing global chunks.
```

### Per-Project Reference Index: `knowledge-base.yaml`

Location: `.aid-o/04-engine/memory/knowledge-base.yaml`
Template: `defaults/templates/knowledge-base.yaml`

```yaml
knowledge_base:
  last_updated: "2026-02-20T10:00:00Z"
  context7_available: true
  primary_source: "context7"    # context7 | websearch

  sources:
    - id: "kb-001"
      framework: "FastAPI"
      version: "0.115.x"
      type: "official_docs"         # official_docs | manual | community
      source: "context7"            # context7 | websearch | manual
      library_id: "/tiangolo/fastapi"  # Context7 library ID (null if websearch)
      url: "https://fastapi.tiangolo.com/"
      api_reference: "https://fastapi.tiangolo.com/reference/"
      indexed_at: "2026-02-20"
      valid_until: "2026-05-20"     # indexed_at + TTL
      status: "active"              # active | stale | invalid | pending_index
      depth: "quick"                # quick | deep
      chunks_in_qdrant: 12
      confidence: "high"            # high | medium | low
      quality:                      # Phase 3: feedback tracking
        times_retrieved: 0
        times_useful: 0
        avg_retrieval_score: 0.0
        last_quality_check: "2026-02-20"
```

### Qdrant Document Type: `documentation`

New document type extending the memory-mcp document type registry. Stored in the shared
`aid-memory` collection alongside existing types (decision, lesson, pattern, command,
audit_finding).

```json
{
  "information": "FastAPI Depends(): Use for dependency injection. Supports async. Nested deps resolved automatically. Use yield for cleanup (DB sessions). Example: async def get_db(): db = SessionLocal(); try: yield db; finally: db.close()",
  "metadata": {
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

### Future Document Type: `example_epic` (Phase 3)

```json
{
  "information": "RAG chatbot: LangChain + Chroma + FastAPI. Architecture: ingestion pipeline -> vector store -> retrieval chain -> LLM with conversation memory.",
  "metadata": {
    "type": "example_epic",
    "frameworks": ["langchain", "chromadb", "fastapi"],
    "source_epic_id": "E-20260215-a3f2",
    "source_project": "customer-support-bot",
    "indexed_at": "2026-02-20T10:00:00Z",
    "confidence": "high",
    "project_name": "global"
  }
}
```

This type will be implemented in Phase 3 (Auto-Extraction + Community Examples).

---

## Research Protocol

### Source Priority

```
IF context7_available (from memory-config.yaml):
  PRIMARY:  Context7 MCP (resolve-library-id -> query-docs)
  FALLBACK: WebSearch + WebFetch (if library not in Context7)
ELSE:
  PRIMARY:  WebSearch + WebFetch
  MANUAL:   PM provides URL -> AI fetches + indexes (Phase 2)
```

Context7 is the preferred source because it provides curated, up-to-date documentation
with high confidence. WebSearch is a fallback for libraries not covered by Context7 or
when Context7 MCP is not installed.

### Two-Level Research Depth

```
Level 1 -- "quick" (default, Phase 1):
  What:     Key concepts, common patterns, gotchas, best practices
  Chunks:   5-15 per framework
  When:     At onboarding (/aid-setup), automatically
  For whom: Brainstorming, architect, planner
  Example:  "FastAPI uses Depends() for DI, supports async natively"

Level 2 -- "deep" (on-demand, Phase 2):
  What:     Detailed API reference, parameters, edge cases
  Chunks:   20-50 per framework
  When:     On request (/aid-research --deep FastAPI authentication)
  For whom: Backend/frontend agent during implementation
  Example:  "OAuth2PasswordBearer(tokenUrl='token', scheme_name='JWT',
            auto_error=True). When auto_error=False, returns None
            instead of raising 401."
```

Phase 1 implements only "quick" depth. "deep" is stubbed for Phase 2.

### Context7 Research Flow

```
research_via_context7(name, depth="quick", topic=null):

  1. RESOLVE library:
     lib = resolve-library-id(
       libraryName = name,
       query = topic OR "How to use {name} - setup, API, common patterns"
     )

     IF lib NOT found:
       log("{name} not in Context7, falling back to WebSearch")
       RETURN research_via_websearch(name, depth, topic)

  2. QUERY documentation:
     IF depth == "quick":
       query = topic OR "{name} key concepts, common patterns, best practices, gotchas"
     ELIF depth == "deep":
       query = topic OR "{name} detailed API reference, all parameters, edge cases"

     docs = query-docs(libraryId = lib.id, query = query)

  3. PARSE into chunks:
     chunks = parse_context7_response(docs)
     Each chunk = 1 concept/pattern/API endpoint, target ~300 words max
     Split by: heading boundaries, code block boundaries, topic shifts

  4. QUALITY GATE each chunk:
     FOR EACH chunk IN chunks:
       result = run_quality_gates(chunk, source="context7")
       IF result.passed:
         approved_chunks.append(chunk)
       ELIF result.action == "merge":
         merge_with_existing(chunk, result.existing_match)
       ELSE:
         log("Chunk rejected: {result.gate}, reason: {result.reason}")

  5. STORE passing chunks:
     FOR EACH chunk IN approved_chunks:
       memory_store("documentation", chunk.text, {
         framework: name,
         framework_version: detected_version,
         section: inferred_section,
         source: "context7",
         source_library_id: lib.id,
         source_url: null,
         indexed_at: now(),
         valid_until: now() + 90_days,
         project_name: "global",
         confidence: "high",
         depth: depth
       })

  6. UPDATE knowledge-base.yaml:
     source_entry = find_or_create_source(name)
     source_entry.source = "context7"
     source_entry.library_id = lib.id
     source_entry.indexed_at = today()
     source_entry.valid_until = today() + 90_days
     source_entry.status = "active"
     source_entry.depth = depth
     source_entry.chunks_in_qdrant = len(approved_chunks)
     source_entry.confidence = "high"
     write_knowledge_base_yaml()

  7. RETURN:
     {
       chunks_stored: len(approved_chunks),
       chunks_rejected: len(chunks) - len(approved_chunks),
       source: "context7",
       library_id: lib.id,
       framework: name
     }
```

### WebSearch Fallback Flow

```
research_via_websearch(name, depth="quick", topic=null):

  1. SEARCH:
     query = "{name} official documentation {topic} {current_year}"
     results = WebSearch(query)

  2. PRIORITIZE sources:
     Tier 1 (high confidence):  Official docs (github.io, readthedocs, framework homepage)
     Tier 2 (medium confidence): GitHub README, API reference pages
     Tier 3 (low, skip):        Random blogs, Stack Overflow, Medium articles

     selected = top 3 URLs from Tier 1 + Tier 2 results
     IF no Tier 1-2 URLs found:
       log("No quality sources found for {name}")
       RETURN { chunks_stored: 0, source: "websearch", reason: "no_quality_sources" }

  3. FETCH and EXTRACT:
     FOR EACH url IN selected (max 3):
       TRY:
         content = WebFetch(url, prompt="Extract key concepts, code snippets,
                   common patterns, and gotchas for {name}")
       CATCH:
         log("WebFetch failed for {url}, skipping")
         CONTINUE

       Extract from fetched content:
         - Key concepts (what the framework does, main API surface)
         - Code snippets (max 500 tokens per chunk)
         - Common patterns (best practices, recommended approaches)
         - Gotchas/caveats (what does not work intuitively)

       Split into chunks (1 chunk = 1 concept/pattern, target ~300 words max)

       # Assign confidence based on source tier
       chunk_confidence = "high" IF url matches Tier 1
       chunk_confidence = "medium" IF url matches Tier 2

  4. QUALITY GATE each chunk:
     FOR EACH chunk IN all_chunks:
       result = run_quality_gates(chunk, source="websearch")
       IF result.passed:
         approved_chunks.append(chunk)
       ELIF result.action == "merge":
         merge_with_existing(chunk, result.existing_match)
       ELSE:
         log("Chunk rejected: {result.gate}, reason: {result.reason}")

  5. STORE passing chunks:
     FOR EACH chunk IN approved_chunks:
       memory_store("documentation", chunk.text, {
         framework: name,
         framework_version: detected_version,
         section: inferred_section,
         source: "websearch",
         source_url: chunk.source_url,
         source_library_id: null,
         indexed_at: now(),
         valid_until: now() + 90_days,
         project_name: "global",
         confidence: chunk.confidence,
         depth: depth
       })

  6. UPDATE knowledge-base.yaml:
     source_entry = find_or_create_source(name)
     source_entry.source = "websearch"
     source_entry.library_id = null
     source_entry.url = primary_url
     source_entry.indexed_at = today()
     source_entry.valid_until = today() + 90_days
     source_entry.status = "active"
     source_entry.depth = depth
     source_entry.chunks_in_qdrant = len(approved_chunks)
     source_entry.confidence = best_confidence_from_chunks
     write_knowledge_base_yaml()

  7. RETURN:
     {
       chunks_stored: len(approved_chunks),
       chunks_rejected: total_chunks - len(approved_chunks),
       source: "websearch",
       framework: name
     }
```

### Research Failure Handling

All research failures are non-blocking. No research operation ever stops a workflow.

```
WebFetch fails for URL    -> skip that URL, log, continue with next URL
No quality sources found  -> log warning, store nothing (no data > bad data)
Context7 MCP unavailable  -> fall back to WebSearch silently
Context7 library not found -> fall back to WebSearch for that library
Qdrant MCP unavailable    -> knowledge is useful in-session only, not persisted
All sources fail          -> log warning, proceed without knowledge
                             (brainstorming and agents work without it)

Never block workflow -- all research failures are non-blocking.
Never retry research operations -- unlike Slack which retries 3x.
```

---

## Quality Gates for Storage

Every documentation chunk MUST pass all 4 gates before being stored in Qdrant. Gates are
evaluated in order; a chunk rejected at Gate 1 does not proceed to Gate 2.

### Gate 1: Minimum Informational Value

Purpose: Reject marketing fluff, navigation fragments, and content too vague to help agents.

```
gate_1_min_value(chunk):

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
    { passed: true|false, reason: "description of rejection if failed" }
```

### Gate 2: Deduplication

Purpose: Prevent storing content that already exists in Qdrant.

```
gate_2_deduplication(chunk):

  existing = memory_find(chunk.text, min_score=0.70)

  IF match found with score > 0.85:
    RETURN { passed: false, action: "reject", reason: "duplicate",
             existing_id: match.id }

  IF match found with score 0.70 - 0.85:
    RETURN { passed: false, action: "merge", reason: "partial_overlap",
             existing_match: match }
    # Caller keeps the better version (longer, more specific, newer source)

  IF no match OR all scores < 0.70:
    RETURN { passed: true }

  For documentation type: also check same source_library_id + section
  to prevent duplicates from re-fetching the same Context7 library.
```

### Gate 3: Metadata Completeness

Purpose: Ensure every stored chunk has enough metadata for filtering and attribution.

```
gate_3_metadata(chunk, metadata):

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
    - confidence:     based on source tier (see Confidence Scoring table)
    - depth:          from research function parameter

  IF any REQUIRED field is missing:
    RETURN { passed: false, reason: "missing required field: {field_name}" }

  IF any RECOMMENDED field is missing:
    log("Warning: chunk missing recommended field: {field_name}")

  RETURN { passed: true, auto_filled: [list of auto-computed fields added] }
```

### Gate 4: Size Limits

Purpose: Keep chunks within the optimal size range for embedding quality and agent context.

```
gate_4_size(chunk):

  word_count = count_words(chunk.text)
  has_code = contains_code_block(chunk.text)

  # Minimum size check
  IF word_count < 50 AND NOT has_code:
    RETURN { passed: false, reason: "too_short",
             detail: "{word_count} words, no code" }

  IF has_code AND count_code_lines(chunk.text) < 2:
    RETURN { passed: false, reason: "code_too_short",
             detail: "code snippet under 2 lines" }

  # Maximum size check
  token_count = estimate_tokens(chunk.text)
  IF token_count > 2000:
    RETURN { passed: false, action: "split",
             reason: "too_large",
             detail: "~{token_count} tokens, split into sub-chunks" }
    # Caller splits the chunk and re-runs all gates on each sub-chunk

  RETURN { passed: true }
```

### Confidence Scoring Table

| Source | Default Confidence | Notes |
|--------|-------------------|-------|
| Context7 | high | Curated, up-to-date documentation |
| Official docs (WebFetch Tier 1) | high | github.io, readthedocs, framework homepage |
| GitHub README (WebFetch Tier 2) | medium | May be outdated or incomplete |
| WebSearch result (Tier 2) | medium | Mixed quality, version uncertain |
| PM manual URL (Phase 2) | medium | PM vouches for relevance |
| Project pattern (completed EPIC) | high | Validated by practice |
| Project pattern (partial EPIC) | low | Unfinished, unvalidated |
| Project pattern (failed EPIC) | excluded | Do not store |

Confidence affects retrieval ranking: when multiple chunks match a query, higher-confidence
chunks are preferred in the results ordering.

---

## Consumption Protocol

These functions define how other components retrieve and use stored knowledge. They extend
the existing memory-mcp protocol functions -- they are not replacements.

### `knowledge_research(framework, depth="quick", topic=null)`

Orchestrates the full research flow for a given framework. This is the primary entry point
for all research triggers.

```
knowledge_research(framework, depth="quick", topic=null):

  config = read_knowledge_config()  # from memory-config.yaml

  # 1. Check if already researched
  kb = read_knowledge_base_yaml()
  existing = find_source(kb, framework)
  IF existing AND existing.status == "active":
    log("{framework} already researched (active, {existing.chunks_in_qdrant} chunks)")
    RETURN { chunks_stored: 0, source: existing.source, status: "already_indexed" }

  # 2. Check Qdrant for existing global chunks (from other projects)
  global_chunks = knowledge_find(
    query = "{framework} documentation",
    filters = { framework: framework, types: ["documentation"] }
  )
  IF len(global_chunks) >= config.research.min_chunks_to_skip_research:  # default: 3
    # Sufficient chunks exist globally -- just add reference, do not re-fetch
    add_source_reference(kb, framework, global_chunks)
    RETURN { chunks_stored: 0, source: "reused_global", status: "reference_added" }

  # 3. Research via preferred source
  IF config.context7.available:
    result = research_via_context7(framework, depth, topic)
    IF result.chunks_stored > 0:
      RETURN result
    # If Context7 found nothing, fall through to WebSearch

  # 4. WebSearch fallback
  result = research_via_websearch(framework, depth, topic)
  RETURN result
```

**Example input:**
```
knowledge_research(framework="FastAPI", depth="quick")
```

**Example output:**
```json
{
  "chunks_stored": 12,
  "chunks_rejected": 3,
  "source": "context7",
  "library_id": "/tiangolo/fastapi",
  "framework": "FastAPI"
}
```

### `knowledge_find(query, filters={})`

Semantic search across stored documentation and other knowledge types. Extends the existing
`memory_find()` with documentation type support and optional filtering.

```
knowledge_find(query, filters={}):

  mem = check_memory_enabled()
  IF NOT mem.enabled:
    RETURN []

  # 1. Search Qdrant via existing memory_find
  results = memory_find(query)

  # 2. Apply type filter
  IF filters.types:
    results = [r for r in results if r.metadata.type IN filters.types]
  ELSE:
    # Default: include all types (documentation + pattern + lesson + decision + ...)
    pass

  # 3. Apply framework filter
  IF filters.framework:
    results = [r for r in results
               if r.metadata.framework == filters.framework
               OR r.metadata.type != "documentation"]
    # Non-documentation types (lessons, patterns) are not filtered by framework
    # because a lesson from FastAPI project may be relevant to any Python project

  # 4. Apply freshness filter (Phase 2: aging protocol)
  # IF filters.min_freshness:
  #   results = apply_freshness_weighting(results, filters.min_freshness)

  # 5. Sort by score, limit to top_k
  results = sorted(results, key=lambda r: r.score, reverse=True)
  results = results[:mem.config.memory.search.top_k]

  RETURN results
```

**Example input:**
```
knowledge_find(
  query = "FastAPI dependency injection with async database session",
  filters = {
    framework: "FastAPI",
    types: ["documentation", "pattern", "lesson"]
  }
)
```

**Example output:**
```json
[
  {
    "information": "FastAPI Depends(): Use for dependency injection...",
    "metadata": { "type": "documentation", "framework": "FastAPI", "confidence": "high" },
    "score": 0.89
  },
  {
    "information": "Repository pattern for SQLAlchemy async...",
    "metadata": { "type": "pattern", "framework": "FastAPI", "confidence": "high" },
    "score": 0.76
  },
  {
    "information": "Always call await db.refresh(obj) after db.commit()...",
    "metadata": { "type": "lesson", "tags": ["sqlalchemy", "async"] },
    "score": 0.71
  }
]
```

### `knowledge_context_for_agent(step, epic_context)`

Builds a KNOWLEDGE CONTEXT block for agent dispatch. This extends the existing
`memory_context_for_step()` from memory-mcp by adding a dedicated section for
framework documentation alongside existing memory context.

```
knowledge_context_for_agent(step, epic_context):

  mem = check_memory_enabled()
  IF NOT mem.enabled:
    RETURN ""

  # 1. Build search queries from step context
  queries = [
    step.objective,
    step.role + " " + epic_context.area,
  ]

  # Add framework-specific queries if tech_stack known
  IF epic_context.tech_stack:
    FOR EACH framework IN epic_context.tech_stack:
      queries.append(framework + " " + step.objective)

  # 2. Search for documentation + patterns + lessons
  all_results = []
  FOR EACH q IN queries:
    results = knowledge_find(q, filters={
      types: ["documentation", "pattern", "lesson"]
    })
    all_results.extend(results)

  # 3. Deduplicate (keep highest score per unique information text)
  unique = deduplicate_by_text(all_results, keep="highest_score")
  unique = unique[:mem.config.memory.search.top_k]

  IF len(unique) == 0:
    RETURN ""

  # 4. Group by type
  docs = [r for r in unique if r.metadata.type == "documentation"]
  patterns = [r for r in unique if r.metadata.type == "pattern"]
  lessons = [r for r in unique if r.metadata.type == "lesson"]

  # 5. Format as KNOWLEDGE CONTEXT block
  context = "## KNOWLEDGE CONTEXT\n\n"
  context += "_Retrieved from knowledge base. Use as reference -- do not blindly follow "
  context += "if project context has changed._\n\n"

  IF docs:
    context += "### Framework Documentation\n\n"
    FOR EACH r IN docs:
      version_info = " v" + r.metadata.framework_version IF r.metadata.framework_version ELSE ""
      source_info = r.metadata.source
      context += "_{framework}{version} (source: {source}, indexed {date})_\n\n".format(
        framework = r.metadata.framework,
        version = version_info,
        source = source_info,
        date = r.metadata.indexed_at[:10]
      )
      context += r.information + "\n\n"

  IF patterns:
    context += "### Patterns from Past Projects\n\n"
    FOR EACH r IN patterns:
      project = r.metadata.project_name OR "unknown"
      context += "_Project: {project} ({date})_\n\n".format(
        project = project,
        date = r.metadata.date OR r.metadata.indexed_at[:10]
      )
      context += r.information + "\n\n"

  IF lessons:
    context += "### Lessons\n\n"
    FOR EACH r IN lessons:
      project = r.metadata.project_name OR "unknown"
      context += "_Project: {project} ({date})_\n\n".format(
        project = project,
        date = r.metadata.date OR r.metadata.indexed_at[:10]
      )
      context += r.information + "\n\n"

  RETURN context
```

**Example output (formatted block injected into agent prompt):**

```markdown
## KNOWLEDGE CONTEXT

_Retrieved from knowledge base. Use as reference -- do not blindly follow if project context has changed._

### Framework Documentation

_FastAPI v0.115.x (source: context7, indexed 2026-02-20)_

Dependency injection with Depends(): Use `async def get_db()` with
`yield` for session lifecycle management. FastAPI resolves nested
dependencies automatically.

### Patterns from Past Projects

_Project: crm-backend (2026-01-15)_

Repository pattern for SQLAlchemy async: Abstract DB access behind
repository classes, inject via Depends(). Tested pattern, works well
with FastAPI.

### Lessons

_Project: invoice-api (2025-12-01)_

SQLAlchemy async: Always call `await db.refresh(obj)` after
`db.commit()` or lazy-loaded relations will not work.
```

### `knowledge_references(framework=null)`

Returns a structured list of documentation sources for PM or architect use.
Reads from `knowledge-base.yaml` -- no Qdrant call needed.

```
knowledge_references(framework=null):

  kb = read_knowledge_base_yaml()
  IF kb is null OR kb.sources is empty:
    RETURN "No knowledge sources indexed yet. Run /aid-setup to research your tech stack."

  sources = kb.sources
  IF framework:
    sources = [s for s in sources if s.framework == framework]

  output = "## Knowledge Sources\n\n"
  FOR EACH s IN sources:
    status_label = s.status
    output += "- **{framework}** ({version}): {url} — chunks={n}, confidence={c}, {status}, source: {source}\n".format(
      framework = s.framework,
      version = s.version OR "version unknown",
      url = s.url OR s.library_id OR "no URL",
      n = s.chunks_in_qdrant,
      c = s.confidence,
      status = status_label,
      source = s.source
    )

  RETURN output
```

**Example output:**

```
## Knowledge Sources

- **FastAPI** (0.115.x): https://fastapi.tiangolo.com/ — chunks=12, confidence=high, active, source: context7
- **SQLAlchemy** (2.0.x): https://docs.sqlalchemy.org/ — chunks=8, confidence=high, active, source: websearch
- **Pydantic** (2.6.x): /pydantic/pydantic-docs — chunks=10, confidence=high, active, source: context7
```

---

## Triggers -- When Research Happens

### Trigger 1: Onboarding (`/aid-setup`)

When: After project-scanner detects the tech stack in `/aid-setup`.
Who calls: `aid-setup.md` command, after MCP configuration.

```
project-scanner detects stack -> [Python, FastAPI, SQLAlchemy, Pydantic]

FOR EACH framework IN tech_stack (max 5 per memory-config.yaml):

  Check knowledge-base.yaml for existing source:

  CASE source exists AND status == "active":
    -> skip (already have it)

  CASE source exists AND status == "stale":
    -> re-validate (Phase 2: aging protocol)
    -> For now (Phase 1): skip, treat as active

  CASE source does not exist:
    -> Check Qdrant for existing global chunks:
       knowledge_find("{framework} documentation", filters={ types: ["documentation"] })

       IF found active chunks (>= 3):
         -> Add reference to knowledge-base.yaml, NO re-fetch
       ELSE:
         -> knowledge_research(framework, depth="quick")

Output: updated knowledge-base.yaml + new chunks in Qdrant
```

### Trigger 2: Brainstorming (`/aid-brainstorm`)

When: During brainstorming Steps 1 (Context) and 3 (Approaches).
Who calls: `brainstorming.md` skill.

```
Step 1 (Context Gathering):
  knowledge_find(topic + tech_stack)
  -> Returns: relevant documentation, patterns, decisions from past projects
  -> Displayed as context for PM:
    "From knowledge base: in similar projects, [pattern X] worked well..."

Step 3 (Approach Exploration):
  knowledge_find(approach_keywords)
  -> Informs approach generation with real documentation and past experience:
    "FastAPI docs recommend OAuth2PasswordBearer for simple auth cases"
    "Project X used JWT auth with refresh tokens (lesson: worked well)"
```

### Trigger 3: Agent Dispatch (`/aid-run-epic` EXECUTING)

When: Before dispatching each agent step during EPIC execution.
Who calls: `agent-core.md` skill, extending `memory_context_for_step()`.

```
Extension of existing memory_context_for_step():

  Existing behavior: searches decisions, lessons, patterns, commands
  New behavior:      + searches documentation chunks relevant to step objective

  Example: backend agent gets step "Implement authentication endpoint"
    -> knowledge_find("FastAPI authentication endpoint implementation")
    -> Returns:
      - [documentation] FastAPI OAuth2 tutorial snippet
      - [pattern] JWT refresh token pattern from project X
      - [lesson] "Don't forget CORS middleware with auth" from project Y
    -> Formatted as KNOWLEDGE CONTEXT block in agent prompt
       (see knowledge_context_for_agent pseudocode above)
```

### Trigger 4: Plan/EPIC Content Detection

When: During `/aid-brainstorm` or `/aid-plan-epic` when PM mentions an unknown framework.
Who calls: `brainstorming.md` skill or `planner.md` skill.

```
PM mentions "I want to use Celery" during brainstorming:

  1. Parse text for framework/library mentions
  2. Compare with knowledge-base.yaml
  3. IF framework is unknown (no source entry):
     -> Notify PM: "No knowledge about Celery found. Running research..."
     -> knowledge_research(framework="Celery", depth="quick")
     -> Report: "Found: official docs, 8 chunks stored."
  4. Continue brainstorming with Celery knowledge now available

Same flow applies when /aid-plan-epic encounters unknown frameworks in EPIC content.
```

### Trigger 5: On-Demand Research (`/aid-research`) -- Phase 2

```
/aid-research FastAPI WebSocket authentication
  -> knowledge_research(framework="FastAPI", depth="quick", topic="WebSocket authentication")

/aid-research https://docs.celery.dev/
  -> Fetch URL -> extract -> quality gate -> store -> report to PM

/aid-research --deep LangGraph checkpointing
  -> knowledge_research(framework="LangGraph", depth="deep", topic="checkpointing")
```

This trigger will be implemented as a separate `/aid-research` command in Phase 2.

### Trigger 6: Post-EPIC Enrichment (`/aid-run-epic` DONE) -- Phase 3

```
After EPIC completion:
  1. Curator collects patterns (existing behavior)
  2. knowledge-acquisition enriches patterns with framework tags
     - Pattern "repository pattern for SQLAlchemy" -> tag framework=SQLAlchemy
  3. PM approval: "Save this project as template? (Y/N)"
  4. If Y: store abstracted EPIC pattern in Qdrant as type=example_epic
  5. Available for ALL future projects via semantic search
```

This trigger will be implemented in Phase 3 (Auto-Extraction + Community Examples).

---

## Configuration Reference

Knowledge acquisition reads its configuration from `.aid-o/03-config/policies/memory-config.yaml`,
under the `knowledge:` section. This section is added by `/aid-setup` when Context7 or
knowledge acquisition is configured.

```yaml
memory:
  enabled: true
  collection_name: "aid-memory"

  # ... existing auto_index and search sections (see memory-mcp.md) ...

  # Knowledge acquisition configuration
  knowledge:
    enabled: true
    primary_source: "context7"        # context7 | websearch
    fallback_source: "websearch"

    context7:
      available: true                 # set during /aid-setup
      scope: "user"                   # user | project
      installed_at: "2026-02-20"

    research:
      default_depth: "quick"          # quick | deep (deep = Phase 2)
      deep_on_demand_only: true       # deep only via /aid-research --deep
      max_frameworks_per_scan: 5      # limit at onboarding
      max_urls_per_framework: 3       # WebSearch: max URLs to fetch
      max_chunks_per_source: 15       # max chunks stored per framework (quick)
      source_tiers:
        tier1: ["github.io", "readthedocs.io", "docs.python.org"]
        tier2: ["github.com", "pypi.org"]
        ignored: ["medium.com", "dev.to", "w3schools.com"]

    quality:
      min_chunk_words: 50             # reject chunks shorter than this (unless has code)
      max_chunk_tokens: 2000          # split chunks larger than this
      dedup_threshold: 0.85           # reject if existing match > this score
      merge_threshold: 0.70           # merge if existing match between this and dedup
      required_metadata:              # reject without these fields
        - "type"
        - "framework"
        - "source"
        - "indexed_at"

    # Phase 2: aging configuration (stub)
    # aging:
    #   documentation_ttl_days: 90
    #   pattern_ttl_days: 180
    #   lesson_ttl_days: 365
    #   stale_weight: 0.7
    #   expired_weight: 0.3
    #   exclude_after_days: 180

    # Phase 3: feedback tracking (stub)
    # feedback:
    #   track_retrieval: true
    #   track_usefulness: false
```

---

## Integration Points

This section maps which existing components call which knowledge-acquisition protocols,
and what changes are needed in each component.

| Component | Calls | Changes Needed (Phase 1) |
|-----------|-------|--------------------------|
| `commands/aid-setup.md` | `knowledge_research()` | +Context7 MCP setup (Option 6b), +research detected stack after scanner |
| `skills/brainstorming.md` | `knowledge_find()` | +call in Step 1 (context), +call in Step 3 (approaches) |
| `skills/agent-core.md` | `knowledge_context_for_agent()` | +extend `memory_context_for_step()` to include documentation type |
| `skills/memory-mcp.md` | (extended by this skill) | +`documentation` type in document types, +quality gate protocol in `memory_store` |
| `skills/epic-orchestration.md` | (no changes Phase 1) | Phase 3: +trigger example extraction after EPIC DONE |
| `agents/curator.md` | (no changes Phase 1) | Phase 3: +tag patterns with framework metadata |

### Data Flow Diagram

```
                     /aid-setup (Trigger 1)
                          |
                          v
              +---------------------------+
              | knowledge_research()      |
              | (orchestrates full flow)  |
              +---------------------------+
                   |              |
                   v              v
          +----------------+  +------------------+
          | Context7 MCP   |  | WebSearch +      |
          | resolve-lib-id |  | WebFetch         |
          | query-docs     |  | (fallback)       |
          +----------------+  +------------------+
                   |              |
                   v              v
              +---------------------------+
              | parse_into_chunks()       |
              +---------------------------+
                          |
                          v
              +---------------------------+
              | Quality Gates (4 gates)   |
              | 1. Min Value              |
              | 2. Deduplication          |
              | 3. Metadata Completeness  |
              | 4. Size Limits            |
              +---------------------------+
                    |            |
                    v            v
               (passed)     (rejected)
                    |            |
                    v            v
          +-----------------+  (logged,
          | memory_store()  |   discarded)
          | (Qdrant global) |
          +-----------------+
                    |
                    v
          +-----------------+
          | knowledge-      |
          | base.yaml       |
          | (per-project    |
          |  reference)     |
          +-----------------+

         --- Consumption ---

  /aid-brainstorm              /aid-run-epic
  (Triggers 2, 4)             (Trigger 3)
       |                           |
       v                           v
  knowledge_find()        knowledge_context_for_agent()
       |                           |
       v                           v
  Qdrant semantic search    Qdrant semantic search
       |                           |
       v                           v
  Results shown to PM       KNOWLEDGE CONTEXT block
  in brainstorming          injected into agent prompt
```

---

## Phase 2-3 Extension Stubs

### Phase 2: Aging Protocol (Stub)

TTL-based freshness weighting for search results. Stale documentation gets lower relevance
scores; expired documentation is excluded from results.

```
TTL by document type:
  documentation:  90 days
  pattern:        180 days
  lesson:         365 days
  decision:       never expires (only superseded)

Freshness weight formula:
  active (before valid_until):     1.0
  stale (0-30 days past):          0.7
  expired (30-180 days past):      0.3
  ancient (180+ days past):        EXCLUDE from results

  final_score = qdrant_similarity_score * freshness_weight

Re-validation at /aid-setup:
  Iterate knowledge-base.yaml sources, check status, refresh or invalidate.
```

Implementation deferred to Phase 2 EPIC.

### Phase 2: On-Demand Research Command (Stub)

New `/aid-research` command allowing PM to trigger research interactively.

```
/aid-research [topic|URL] [--deep]

Modes:
  Topic:   knowledge_research(framework, depth, topic)
  URL:     fetch -> extract -> quality gate -> store -> report
  Deep:    extended chunk count + detailed API reference
```

Implementation deferred to Phase 2 EPIC.

### Phase 2: Manual Source Addition (Stub)

Conversational flow for PM to add documentation sources without editing YAML.

```
PM: "Add documentation for our internal auth library at https://wiki.company.com/auth-lib"

Flow: validate URL -> fetch -> extract -> chunk -> quality gate -> store -> update YAML -> confirm
```

Implementation deferred to Phase 2 EPIC.

### Phase 3: Example EPIC Extraction (Stub)

Auto-extract abstracted patterns from completed EPICs and store as `example_epic` type.

```
After EPIC DONE:
  Extract pattern -> PM approval -> store in Qdrant as type=example_epic
  Available for future projects via semantic search in brainstorming Step 3
```

Implementation deferred to Phase 3 EPIC.

### Phase 3: Community Templates (Stub)

Static example EPICs shipped with the plugin in `defaults/examples/`.

```
Location: plugins/aid-orchestrator/defaults/examples/
  langchain-rag-chatbot.md
  fastapi-crud-service.md
  react-dashboard.md
  ...

Consumed in brainstorming Step 3: search examples + Qdrant example_epic type.
```

Implementation deferred to Phase 3 EPIC.

### Phase 3: Feedback Tracking (Stub)

Track how often knowledge chunks are retrieved and whether agents found them useful.

```
knowledge-base.yaml quality section:
  times_retrieved: N
  times_useful: N
  avg_retrieval_score: 0.XX

Used to prioritize high-value chunks and deprecate unused ones.
```

Implementation deferred to Phase 3 EPIC.

---

## Fallback Protocol

### When Context7 MCP is not configured

```
IF memory-config.yaml knowledge.context7.available = false
   OR Context7 MCP tools not found:

  -> All research uses WebSearch fallback automatically
  -> No error, no warning beyond initial log at /aid-setup
  -> knowledge-base.yaml sources will have source="websearch"
  -> System is fully functional, just with different source confidence
```

### When Qdrant MCP is not configured

```
IF memory.enabled = false OR Qdrant MCP unavailable:

  -> Research still runs (Context7 or WebSearch)
  -> Results are useful IN-SESSION only (displayed to PM, used by current agents)
  -> NOT persisted to Qdrant (no cross-session or cross-project knowledge)
  -> knowledge-base.yaml is NOT updated (no reference index without Qdrant)
  -> No error, no warning (consistent with memory-mcp fallback behavior)
```

### When knowledge config does not exist

```
IF memory-config.yaml has no knowledge: section:

  -> All knowledge_* functions return immediately (no-op / empty results)
  -> Brainstorming works identically to current behavior (no knowledge injection)
  -> Agent dispatch works identically to current behavior (MEMORY CONTEXT only)
  -> No regression for projects without knowledge configuration
```

---

## Reference Files

- `skills/memory-mcp.md` -- Base Qdrant protocol (this skill extends it)
- `skills/brainstorming.md` -- Consumes `knowledge_find()` in Steps 1 and 3
- `skills/agent-core.md` -- Consumes `knowledge_context_for_agent()` for agent dispatch
- `skills/epic-orchestration.md` -- Phase 3: triggers example extraction at EPIC DONE
- `commands/aid-setup.md` -- Triggers research at onboarding, configures Context7 MCP
- `defaults/policies/memory-config.yaml` -- Configuration file with knowledge section
- `defaults/templates/knowledge-base.yaml` -- Template for per-project reference index

---

## Important

- This skill is the **central definition** for the entire knowledge pipeline. Other components
  (brainstorming, agent-core, aid-setup) call protocols defined here -- they do not define
  their own research or storage logic.
- The Context7 MCP server is **external** to the AID plugin. AID defines the integration
  protocol; it does not control Context7 availability or library coverage.
- All knowledge operations are **non-blocking**. A research or storage failure must NEVER
  interrupt brainstorming, EPIC execution, or agent dispatch.
- Quality gates are **non-negotiable**. Every chunk must pass all 4 gates before storage.
  No data is better than bad data -- noisy chunks degrade agent performance.
- Documentation chunks use `project_name="global"` because framework documentation is
  universal. This enables cross-project sharing without re-fetching.
- The `knowledge-base.yaml` is an **AI-managed index**. PM never edits it manually.
  Qdrant is the source of truth for content; YAML is the source of truth for references.

---

**Version:** 0.5.0
**Last Updated:** 2026-02-22
