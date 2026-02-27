# Knowledge Acquisition — Research, Storage, and Consumption Protocol

**Skill:** knowledge-acquisition
**Dependencies:** memory-mcp, run-management, epic-orchestration

---

## TL;DR

This skill defines how AID actively acquires, quality-gates, stores, and serves framework
documentation and technical knowledge. It extends the existing memory-mcp skill with a new
`documentation` document type, a multi-source research pipeline (Context7 primary, WebSearch
fallback), 4 mandatory quality gates, and consumption functions that feed knowledge into
brainstorming runs and agent dispatch.

**Principle:** Knowledge acquisition is non-blocking. Every operation degrades gracefully --
Context7 unavailable falls back to WebSearch, WebSearch fails falls back to in-run-only,
Qdrant unavailable means results are useful in the current run but not persisted. No
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
Qdrant MCP unavailable    -> knowledge is useful in-run only, not persisted
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

  # 4. Apply freshness weighting (aging protocol)
  #    Deprioritizes stale/expired entries, excludes ancient ones.
  #    Backward compatible: without aging config, all weights are 1.0.
  config = read_knowledge_config()
  IF config.knowledge.aging is not null:
    results = apply_freshness_weighting(results)
  # If no aging config, skip weighting (all entries keep original score)

  # 5. Sort by weighted score, limit to top_k
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

    # Aging configuration — TTL-based freshness weighting
    aging:
      ttl_days:
        documentation: 90
        pattern: 180
        lesson: 365
        command: 365
        audit_finding: 90
        decision: null            # never expires
        example_epic: null        # never expires (Phase 3)
      weights:
        active: 1.0               # before valid_until
        stale: 0.7                # 1-30 days past valid_until
        expired: 0.3              # 31-180 days past valid_until
        ancient: 0.0              # 180+ days past valid_until (excluded)
      exclude_after_days: 180     # entries older than this are excluded from results
      revalidate_on_setup: true   # run revalidation during /aid-setup

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

## Aging Protocol

TTL-based freshness weighting ensures stale documentation gets deprioritized in search results
and expired documentation is excluded. This keeps agents working with current knowledge while
preserving historical entries that may still have value.

**Principle:** Aging is non-destructive. Stale or expired entries are never deleted from Qdrant --
they are deprioritized or excluded at query time. Re-validation can restore them to active status.

### TTL by Document Type

Each document type has a defined Time-To-Live (TTL) measured from its `indexed_at` date.
The `valid_until` field is computed as `indexed_at + TTL`.

| Type | TTL (days) | Rationale |
|------|-----------|-----------|
| `documentation` | 90 | Framework docs change frequently with releases |
| `pattern` | 180 | Patterns evolve slower but still drift |
| `lesson` | 365 | Lessons are experience-based, long-lived |
| `command` | 365 | CLI commands and tool usage rarely change within a year |
| `audit_finding` | 90 | Audit findings reflect a point-in-time state, age quickly |
| `decision` | infinite | Decisions never expire (only superseded by newer decisions) |
| `example_epic` (Phase 3) | infinite | Reference architectures remain valuable indefinitely |

```
get_ttl_days(type):
  MATCH type:
    "documentation":   RETURN 90
    "pattern":         RETURN 180
    "lesson":          RETURN 365
    "command":         RETURN 365
    "audit_finding":   RETURN 90
    "decision":        RETURN null   # never expires
    "example_epic":    RETURN null   # never expires
    DEFAULT:           RETURN 90     # safe default for unknown types
```

### Freshness Weight Categories

After an entry's `valid_until` date passes, it moves through four freshness categories.
Each category carries a weight multiplier applied to the Qdrant similarity score.

| Category | Condition | Weight | Behavior |
|----------|-----------|--------|----------|
| **Active** | `now <= valid_until` | 1.0 | Full relevance, no label |
| **Stale** | `0 < days_past <= 30` | 0.7 | Reduced relevance, stale warning label |
| **Expired** | `30 < days_past <= 180` | 0.3 | Significantly reduced, expired label |
| **Ancient** | `days_past > 180` | 0.0 | Excluded from results entirely |

The final score used for ranking is:

```
final_score = qdrant_similarity_score * freshness_weight
```

### `compute_freshness_weight(entry)`

Computes the freshness weight for a single search result entry. Called by `knowledge_find()`
after Qdrant returns results.

```
compute_freshness_weight(entry):

  type = entry.metadata.type

  # Types that never expire
  IF type == "decision":
    RETURN { weight: 1.0, category: "active", label: null }
  IF type == "example_epic":
    RETURN { weight: 1.0, category: "active", label: null }

  # If no valid_until set (legacy entries or missing TTL config), treat as active
  IF entry.metadata.valid_until is null:
    RETURN { weight: 1.0, category: "active", label: null }

  valid_until = parse_date(entry.metadata.valid_until)
  days_past = (now() - valid_until).days

  # Active: before or at expiration
  IF days_past <= 0:
    RETURN { weight: 1.0, category: "active", label: null }

  # Stale: 1-30 days past valid_until
  IF days_past <= 30:
    indexed_date = entry.metadata.indexed_at[:10]
    framework = entry.metadata.framework OR entry.metadata.type
    version = entry.metadata.framework_version OR ""
    label = "Warning: Stale (indexed {date}, {fw} {ver} -- current may differ)".format(
      date = indexed_date,
      fw = framework,
      ver = version
    )
    RETURN { weight: 0.7, category: "stale", label: label }

  # Expired: 31-180 days past valid_until
  IF days_past <= 180:
    indexed_date = entry.metadata.indexed_at[:10]
    framework = entry.metadata.framework OR entry.metadata.type
    version = entry.metadata.framework_version OR ""
    label = "Warning: Expired (indexed {date}, {fw} {ver} -- likely outdated)".format(
      date = indexed_date,
      fw = framework,
      ver = version
    )
    RETURN { weight: 0.3, category: "expired", label: label }

  # Ancient: 180+ days past valid_until -> exclude
  RETURN { weight: 0.0, category: "ancient", label: null }
```

### `apply_freshness_weighting(results)`

Applies freshness weighting to a list of Qdrant search results. Called by `knowledge_find()`
as step 4 of the search pipeline.

```
apply_freshness_weighting(results):

  weighted_results = []

  FOR EACH r IN results:
    freshness = compute_freshness_weight(r)

    # Ancient entries are excluded entirely
    IF freshness.weight == 0.0:
      log("Excluding ancient entry: {type}/{framework}, indexed {date}".format(
        type = r.metadata.type,
        framework = r.metadata.framework OR "unknown",
        date = r.metadata.indexed_at[:10]
      ))
      CONTINUE

    # Apply weight to score
    r.original_score = r.score
    r.score = r.score * freshness.weight
    r.freshness_category = freshness.category
    r.freshness_label = freshness.label

    weighted_results.append(r)

  RETURN weighted_results
```

### `revalidate_knowledge_sources()`

Re-validates all knowledge sources during `/aid-setup`. Iterates `knowledge-base.yaml` entries,
checks freshness status, attempts to refresh stale sources, and marks unreachable ones as invalid.

**When called:** During `/aid-setup` onboarding, after MCP configuration and before new research.
**Non-blocking:** All refresh failures are logged but never block the setup flow.

```
revalidate_knowledge_sources():

  kb = read_knowledge_base_yaml()
  IF kb is null OR kb.sources is empty:
    RETURN { revalidated: 0, refreshed: 0, invalidated: 0 }

  config = read_knowledge_config()
  # If no aging config exists, skip revalidation entirely (backward compatible)
  IF config.knowledge.aging is null:
    log("No aging config found, skipping revalidation")
    RETURN { revalidated: 0, refreshed: 0, invalidated: 0 }

  stats = { revalidated: 0, refreshed: 0, invalidated: 0, unchanged: 0 }

  FOR EACH source IN kb.sources:

    # Skip types that never expire
    IF source.type == "decision" OR source.type == "example_epic":
      stats.unchanged += 1
      CONTINUE

    # Determine current freshness status
    IF source.valid_until is null:
      # Legacy entry without TTL -- compute and set valid_until
      ttl = get_ttl_days(source.type OR "documentation")
      IF ttl is not null:
        source.valid_until = source.indexed_at + ttl_days
      ELSE:
        stats.unchanged += 1
        CONTINUE

    days_past = (now() - parse_date(source.valid_until)).days

    # CASE 1: Still active -- no action needed
    IF days_past <= 0:
      stats.unchanged += 1
      CONTINUE

    stats.revalidated += 1

    # CASE 2: Past valid_until -- attempt refresh
    log("Source {id} ({framework}) is {days} days past valid_until, attempting refresh".format(
      id = source.id,
      framework = source.framework,
      days = days_past
    ))

    refresh_result = attempt_source_refresh(source, config)

    IF refresh_result.success:
      # Refresh succeeded -- update source entry
      source.indexed_at = now()
      source.valid_until = now() + get_ttl_days(source.type OR "documentation")
      source.status = "active"
      source.chunks_in_qdrant = refresh_result.chunks_stored
      stats.refreshed += 1
      log("Source {id} ({framework}) refreshed successfully, {n} chunks updated".format(
        id = source.id,
        framework = source.framework,
        n = refresh_result.chunks_stored
      ))

    ELSE:
      # Refresh failed -- mark as stale or invalid based on age
      IF days_past <= 30:
        source.status = "stale"
        log("Source {id} ({framework}) marked stale (refresh failed, {days}d past TTL)".format(
          id = source.id,
          framework = source.framework,
          days = days_past
        ))
      ELSE:
        source.status = "invalid"
        stats.invalidated += 1
        log("Source {id} ({framework}) marked invalid (refresh failed, {days}d past TTL)".format(
          id = source.id,
          framework = source.framework,
          days = days_past
        ))
        # Do NOT delete from Qdrant -- entries remain for potential manual recovery
        # Qdrant entries are deprioritized by freshness weighting at query time

  write_knowledge_base_yaml(kb)

  log("Revalidation complete: {revalidated} checked, {refreshed} refreshed, {invalidated} invalidated, {unchanged} unchanged".format(**stats))
  RETURN stats
```

### `attempt_source_refresh(source, config)`

Attempts to refresh a single knowledge source by re-fetching its documentation.
Tries the original source method first, then falls back.

```
attempt_source_refresh(source, config):

  # Strategy 1: Re-fetch via original source
  IF source.source == "context7" AND config.context7.available:
    TRY:
      result = research_via_context7(
        name = source.framework,
        depth = source.depth OR "quick",
        topic = null
      )
      IF result.chunks_stored > 0:
        RETURN { success: true, chunks_stored: result.chunks_stored }
    CATCH:
      log("Context7 refresh failed for {framework}, trying WebSearch".format(
        framework = source.framework
      ))

  # Strategy 2: Fall back to WebSearch
  IF source.source == "websearch" OR source.source == "context7":
    TRY:
      result = research_via_websearch(
        name = source.framework,
        depth = source.depth OR "quick",
        topic = null
      )
      IF result.chunks_stored > 0:
        RETURN { success: true, chunks_stored: result.chunks_stored }
    CATCH:
      log("WebSearch refresh failed for {framework}".format(
        framework = source.framework
      ))

  # Strategy 3: If source has a direct URL, try WebFetch
  IF source.url:
    TRY:
      content = WebFetch(source.url, prompt="Extract key concepts and API reference for {fw}".format(
        fw = source.framework
      ))
      IF content is not empty:
        chunks = parse_and_store_chunks(content, source)
        IF len(chunks) > 0:
          RETURN { success: true, chunks_stored: len(chunks) }
    CATCH:
      log("Direct URL fetch failed for {url}".format(url = source.url))

  # All strategies failed
  RETURN { success: false, chunks_stored: 0 }
```

### Re-validation Integration with `/aid-setup`

The re-validation step is inserted into the `/aid-setup` onboarding flow, after MCP configuration
and before new framework research.

```
/aid-setup onboarding flow (updated):

  1. Project scanner detects tech stack
  2. MCP configuration (Context7, Qdrant, etc.)
  3. >> revalidate_knowledge_sources() <<    # NEW: re-validate existing sources
  4. Research new frameworks (existing flow)
  5. Report results to PM
```

### Backward Compatibility

The aging protocol is fully backward compatible with projects that have no aging configuration.

```
Backward compatibility rules:

  1. No aging config in memory-config.yaml:
     -> compute_freshness_weight() returns weight=1.0 for ALL entries
     -> No stale/expired labels are added
     -> revalidate_knowledge_sources() is a no-op (skipped)
     -> knowledge_find() returns results as before (no score modification)

  2. Entries without valid_until metadata:
     -> Treated as active (weight=1.0)
     -> No label applied

  3. Types without defined TTL (unknown types):
     -> Default TTL of 90 days is applied
     -> Safe default prevents indefinite caching of untyped content

  4. Existing knowledge-base.yaml without status field:
     -> revalidate_knowledge_sources() computes valid_until from indexed_at + TTL
     -> Sets status based on computed freshness
```

---

## Phase 2-3 Extension Stubs

### On-Demand Research Command

The `/aid-research` command provides PM with direct on-demand access to research.
See `commands/aid-research.md` for the full command definition including argument parsing,
three modes (topic, URL, deep), result presentation, and error handling.

```
/aid-research FastAPI WebSockets            # topic mode (quick)
/aid-research --deep LangGraph checkpointing  # deep mode (extended)
/aid-research https://docs.celery.dev/      # URL mode (manual source)
```

All modes integrate with the existing research protocol. Topic and deep modes call
`knowledge_research()`. URL mode calls `research_via_url()` (see Manual Source Protocol below).

---

## Manual Source Protocol

Conversational flow for PM to add documentation sources without editing YAML. PM speaks
naturally or uses `/aid-research <url>` and AI handles everything: URL validation, content
fetching, chunk extraction, quality gating, Qdrant storage, and confirmation.

**Principle:** PM never edits `knowledge-base.yaml` directly. This file is an AI-managed
index. All additions, updates, and removals happen through conversational commands.

### Entry Points

Two ways for PM to trigger manual source addition:

1. **Via `/aid-research` URL mode:** `/aid-research https://wiki.company.com/auth-lib`
   (handled by `commands/aid-research.md` Step 4)
2. **Via conversation:** PM says "add docs for X at URL Y" during any run

### Conversational Trigger Detection

The AI detects manual source intent from natural language. These are semantic patterns,
not regex -- the AI understands variations and paraphrases.

```
Trigger patterns (detected by AI, not keyword matching):
  - "add docs for..."           -> extract framework + optional URL
  - "index this URL..."         -> extract URL
  - "add documentation from..." -> extract URL + framework
  - "research this page..."     -> extract URL
  - "add knowledge about..."    -> extract framework + optional URL
  - "index docs for..."         -> extract framework + optional URL

When detected:
  IF URL provided:
    -> manual_source_addition(url, framework_hint)
  ELIF framework provided but no URL:
    -> knowledge_research(framework, depth="quick")  # regular topic research
  ELSE:
    -> Ask PM: "What would you like to add? Provide a framework name or documentation URL."
```

### `research_via_url(url, framework_hint=null)`

Full protocol for researching a specific documentation URL and storing quality-gated chunks.
This is the core function behind both `/aid-research` URL mode and conversational triggers.

```
research_via_url(url, framework_hint=null):

  # 1. VALIDATE URL
  TRY:
    content = WebFetch(url, prompt="Is this a documentation page? What framework/library
              does it document? Extract the framework name and version if visible.")
  CATCH (timeout, unreachable, error):
    log("URL unreachable: {url}, error: {error}")
    RETURN {
      success: false,
      error: "url_unreachable",
      message: "URL unreachable: {url}. Check the URL and try again."
    }

  IF content is empty or too short (< 100 words):
    RETURN {
      success: false,
      error: "no_content",
      message: "No useful content found at {url}. Page may require authentication or be empty."
    }

  # 2. DETECT FRAMEWORK
  IF framework_hint is not null:
    framework = framework_hint
  ELSE:
    framework = infer_from_content(content)
    # Infer from: page title, H1 heading, URL domain/path, content keywords
    IF framework is null OR confidence_low:
      Ask PM: "What framework does this URL document?"
      framework = pm_response

  # 3. CONFIRM with PM (skip if called from /aid-research — PM already initiated)
  IF called_from_conversation (not from /aid-research command):
    Present to PM:
      "I'll index documentation from {url} for {framework}.
       This will fetch the page, extract key concepts, and store them
       in the knowledge base for use by agents.
       Proceed? (Y/N)"
    IF PM says N:
      log("PM declined manual source addition for {url}")
      RETURN { success: false, error: "pm_declined" }

  # 4. EXTRACT and CHUNK
  content = WebFetch(url, prompt="Extract key concepts, API references, code examples,
            common patterns, and gotchas for {framework}. Include specific function/class
            names and parameters. Preserve code examples with context.")

  chunks = split_into_chunks(content)
  # Rules: 1 chunk = 1 concept/pattern/API endpoint
  # Target: ~300 words max per chunk
  # Split by: heading boundaries, code block boundaries, topic shifts

  # 5. ASSIGN CONFIDENCE based on URL domain
  domain = extract_domain(url)
  IF domain IN source_tiers.tier1:   # github.io, readthedocs.io, official docs
    confidence = "high"
  ELIF domain IN source_tiers.tier2:  # github.com, pypi.org
    confidence = "medium"
  ELSE:
    confidence = "medium"   # PM vouched for relevance by providing the URL

  # 6. QUALITY GATE each chunk
  approved_chunks = []
  rejected_count = 0
  FOR EACH chunk IN chunks:
    result = run_quality_gates(chunk, source="manual")
    IF result.passed:
      approved_chunks.append(chunk)
    ELIF result.action == "merge":
      merge_with_existing(chunk, result.existing_match)
    ELSE:
      rejected_count += 1
      log("Chunk rejected: {result.gate}, reason: {result.reason}")

  # 7. STORE passing chunks
  FOR EACH chunk IN approved_chunks:
    memory_store("documentation", chunk.text, {
      framework: framework,
      framework_version: detected_version OR null,
      section: inferred_section,
      source: "manual",
      source_url: url,
      source_library_id: null,
      indexed_at: now(),
      valid_until: now() + 90_days,
      project_name: "global",
      confidence: confidence,
      depth: "quick"
    })

  # 8. UPDATE knowledge-base.yaml
  source_entry = find_or_create_source(framework)
  source_entry.type = "manual"
  source_entry.source = "manual"
  source_entry.url = url
  source_entry.library_id = null
  source_entry.indexed_at = today()
  source_entry.valid_until = today() + 90_days
  source_entry.status = "active"
  source_entry.depth = "quick"
  source_entry.chunks_in_qdrant = len(approved_chunks)
  source_entry.confidence = confidence
  write_knowledge_base_yaml()

  # 9. RETURN result
  RETURN {
    success: true,
    chunks_stored: len(approved_chunks),
    chunks_rejected: rejected_count,
    source: "manual",
    url: url,
    framework: framework,
    confidence: confidence
  }
```

### `remove_knowledge_source(framework)`

Allows PM to remove a knowledge source via conversation. Marks the source as removed
in knowledge-base.yaml but does NOT delete chunks from Qdrant (non-destructive).

```
remove_knowledge_source(framework):

  kb = read_knowledge_base_yaml()
  source = find_source(kb, framework)

  IF source is null:
    Report to PM: "No knowledge source found for '{framework}'."
    RETURN

  # Confirm with PM
  Present to PM:
    "Remove knowledge source for {framework}?
     Currently: {source.chunks_in_qdrant} chunks ({source.source}, indexed {source.indexed_at})
     Note: Qdrant chunks are NOT deleted -- they are deprioritized by aging.
     Remove reference? (Y/N)"

  IF PM says N:
    RETURN

  # Mark as removed (non-destructive)
  source.status = "removed"
  write_knowledge_base_yaml(kb)

  Report to PM:
    "Removed: {framework} knowledge source reference.
     Existing Qdrant chunks will age naturally and be excluded over time.
     To fully re-index later: /aid-research {framework}"
```

### Error Handling

All manual source operations follow the same non-blocking error policy:

```
URL unreachable       -> report to PM, abort that URL, suggest alternatives
No useful content     -> report to PM ("page may require auth or be empty")
No chunks pass gates  -> report to PM ("content too generic or already indexed")
Qdrant unavailable    -> display results in run, warn PM they are not persisted
PM declines           -> abort gracefully, log, no error
Framework ambiguous   -> ask PM to clarify before proceeding
```

### Example EPIC Extraction Protocol

Auto-extract abstracted patterns from completed EPICs and store as `example_epic` type in Qdrant.
This protocol runs in the DONE state of epic-orchestration (step 9b, after Curator, before Completion Summary).

#### `extract_example_epic(epic_id, run_id, epic_file, final_report)`

```
extract_example_epic(epic_id, run_id, epic_file, final_report):

  # STAGE 1 — ELIGIBILITY CHECK
  frontmatter = read_yaml_frontmatter(epic_file)

  IF frontmatter.status != "completed":
    log("extract_example_epic: skipped — status={status}, not completed")
    RETURN null

  IF frontmatter.runs_completed < frontmatter.runs_total:
    log("extract_example_epic: skipped — runs incomplete")
    RETURN null

  stage_log = read_jsonl(evidence_path + "/stage_log.jsonl")
  IF any entry WHERE entry.result == "aborted":
    log("extract_example_epic: skipped — EPIC was aborted")
    RETURN null

  # STAGE 2 — EXTRACT
  goal = read_section(epic_file, "## Goal")
  profile = read_yaml(".aid-o/04-engine/memory/project-profile.yaml")
  frameworks = profile.tech_stack.frameworks OR []
  project_name = profile.project_name OR "unknown"

  architect_output = find_step_output(evidence_path, role="architect")
  architecture_summary = summarize_architecture(architect_output)  # 1-2 sentences

  step_pattern = []
  FOR EACH step IN read_json(evidence_path + "/plan.json").steps:
    step_pattern.append({ role: step.role, objective: step.objective })

  key_decisions = extract_key_decisions(architect_output)  # 2-3 most significant

  # STAGE 3 — ABSTRACT
  # Replace project paths with placeholders: {source_dir}/, {backend_dir}/
  # Remove EPIC IDs, run IDs, credentials, URLs
  # Keep: framework names, architectural patterns, role assignments, step ordering

  # STAGE 4 — BUILD information text (max 500 words)
  detected_archetype = infer_archetype(goal, frameworks, step_pattern)
  # Examples: "rag-chatbot", "crud-api", "dashboard", "auth-service"

  step_count = len(step_pattern)
  roles_list = deduplicated_ordered([s.role for s in step_pattern])

  information_text = """
  {archetype}: {frameworks joined with " + "}.
  Architecture: {architecture_summary}.
  Steps ({step_count}): {numbered "role: objective" list}.
  Key decisions: {key_decisions, semicolon-separated}.
  Patterns: {notable implementation patterns}.
  """.strip()

  # STAGE 5 — PM APPROVAL
  complexity = "simple" if step_count <= 4 else "medium" if step_count <= 8 else "complex"

  Present to PM:
  "This EPIC produced a reusable pattern:
    Archetype: {detected_archetype}
    Frameworks: {frameworks}
    Steps: {step_count} ({roles_list})
    Complexity: {complexity}

    Save as template for future {primary_framework} projects? (Y/N)"

  IF PM says N: RETURN { stored: false, reason: "pm_declined" }
  IF no PM response in 60s: RETURN { stored: false, reason: "no_pm_response" }

  # STAGE 6 — DEDUP CHECK
  existing = memory_find(information_text, document_type_filter="example_epic")
  IF any result with score > 0.85:
    log("Similar example exists, skipping")
    RETURN { stored: false, reason: "duplicate" }

  # STAGE 7 — STORE
  memory_store(
    document_type = "example_epic",
    text = information_text,
    metadata = {
      type: "example_epic",
      frameworks: frameworks,
      archetype: detected_archetype,
      source_epic_id: epic_id,
      source_project: project_name,
      step_count: step_count,
      roles: roles_list,
      complexity: complexity,
      indexed_at: current_iso_timestamp(),
      confidence: "high",
      project_name: "global"
    }
  )
  RETURN { stored: true, archetype: detected_archetype }
```

### Community Example EPICs

Static example EPICs shipped with the plugin in `defaults/examples/`. These are curated templates
for common project archetypes, always available even without Qdrant.

**Location:** `plugins/aid-orchestrator/defaults/examples/`

**Available examples:**
- `langchain-rag-chatbot.md` — RAG chatbot with LangChain + vector store
- `fastapi-crud-service.md` — REST API with FastAPI + SQLAlchemy
- `react-dashboard.md` — Dashboard with React + charting + REST API

**Required frontmatter for example files:**
```yaml
type: example
archetype: "descriptive-name"
frameworks: [framework1, framework2]
complexity: simple|medium|complex
description: "One-line description for search"
```

**Content rules:**
- Paths use placeholders: `{project_root}/`, `{source_dir}/`, `{backend_dir}/`
- Framework versions use ranges: `FastAPI 0.100+`, `React 18+`
- Step objectives must be specific and realistic
- Context section includes "When to use" and "When NOT to use"
- Follow standard EPIC template format

**Consumed in brainstorming Step 3:**
```
find_relevant_examples(topic, project_profile):
  1. Search defaults/examples/ for framework/keyword matches in frontmatter
  2. Search Qdrant for type=example_epic (if Qdrant available)
  3. Merge results, deduplicate by archetype (prefer file over Qdrant)
  4. Present top 3 to PM: (A) Adapt, (B) Browse all, (C) Start fresh
```

**Adaptation protocol:**

```
adapt_example(example_path, project_profile):
  """Adapt a knowledge base example to match the target project's paths and tools."""

  INPUT: example_path (path to .md example file), project_profile (parsed project-profile.yaml)
  OUTPUT: adapted example content (string)

  # LOAD INPUTS
  IF project_profile is missing or unparseable:
    RETURN example content unchanged with prepended warning:
      "<!-- Warning: project-profile.yaml not found or unparseable — example not adapted. Run /aid-setup to create profile. -->"
  IF example_path does not exist or is unreadable:
    RETURN error: "Error: Example file not found at {example_path}"

  example_content = read_file(example_path)

  # ──────────────────────────────────────────────
  # STEP 1 — PATH SUBSTITUTION
  # ──────────────────────────────────────────────
  # Find all placeholder patterns matching {{PLACEHOLDER_NAME}}.
  # Replace each recognized placeholder with the corresponding project_profile value:
  #   {{PROJECT_ROOT}} → project_profile.directories.root
  #   {{SRC_DIR}}      → project_profile.directories.plugin (or .root + "/src" if absent)
  #   {{TEST_DIR}}     → project_profile.directories.root + "/tests" (or "tests" if not configured)
  #   {{LANGUAGE}}     → project_profile.tech_stack.languages[0] (first language)
  #   {{FRAMEWORK}}    → project_profile.tech_stack.frameworks[0] (first framework)
  #
  # IF a placeholder has no matching value in project_profile:
  #   Leave it unchanged and append an inline comment:
  #   <!-- TODO: replace {{X}} with actual path -->

  placeholders = regex_find_all(example_content, r"\{\{[A-Z_]+\}\}")
  mapping = {
    "{{PROJECT_ROOT}}": project_profile.directories.root OR ".",
    "{{SRC_DIR}}":      project_profile.directories.plugin OR (project_profile.directories.root + "/src"),
    "{{TEST_DIR}}":     project_profile.directories.root + "/tests" OR "tests",
    "{{LANGUAGE}}":     project_profile.tech_stack.languages[0] OR null,
    "{{FRAMEWORK}}":    project_profile.tech_stack.frameworks[0] OR null,
  }

  FOR EACH placeholder IN deduplicate(placeholders):
    IF placeholder IN mapping AND mapping[placeholder] is not null:
      example_content = replace_all(example_content, placeholder, mapping[placeholder])
    ELSE:
      example_content = replace_all(example_content, placeholder,
        placeholder + " <!-- TODO: replace " + placeholder + " with actual path -->")

  # ──────────────────────────────────────────────
  # STEP 2 — TOOL REFERENCE UPDATE
  # ──────────────────────────────────────────────
  # Read project_profile.tech_stack arrays: .test[], .lint[], .build[], .type_check[]
  # In the example content, find lines containing tool command references:
  #   Lines matching patterns: "test:", "npm test", "pytest", "jest", "lint:",
  #   "eslint", "build:", "tsc"
  # For each tool category (test, lint, build, type_check):
  #   IF the project has configured tools for this category:
  #     Replace the example's tool command with the project's actual command
  #     (e.g., replace "pytest" with project_profile.tech_stack.test[0])
  #   IF the project has no tools configured for this category (empty array):
  #     Comment out the line: <!-- No {category} tool configured: {original_line} -->

  tool_categories = {
    "test":       { source: project_profile.tech_stack.test OR [],
                    patterns: ["pytest", "jest", "vitest", "npm test", "bun test"] },
    "lint":       { source: project_profile.tech_stack.lint OR [],
                    patterns: ["eslint", "ruff", "flake8", "pylint", "biome lint"] },
    "build":      { source: project_profile.tech_stack.build OR [],
                    patterns: ["webpack", "vite", "tsc --build", "npm run build"] },
    "type_check": { source: project_profile.tech_stack.type_check OR [],
                    patterns: ["mypy", "tsc", "pyright"] },
  }

  FOR EACH category, config IN tool_categories:
    IF config.source is not empty:
      target_tool = config.source[0]
      FOR EACH pattern IN config.patterns:
        IF pattern != target_tool AND pattern IN example_content:
          example_content = replace_all(example_content, pattern, target_tool)
    ELSE:
      FOR EACH pattern IN config.patterns:
        IF pattern IN example_content:
          # Comment out lines containing this tool pattern
          FOR EACH line IN example_content containing pattern:
            example_content = replace(line,
              "<!-- No " + category + " tool configured: " + line.strip() + " -->")

  # ──────────────────────────────────────────────
  # STEP 3 — VALIDATION
  # ──────────────────────────────────────────────
  # Grep the adapted content for remaining "{{" patterns → unresolved placeholders
  # Grep for broken markdown links: "](" followed by ")" with nothing between
  # IF unresolved placeholders found: log count as warning, content is still usable
  # IF broken links found: log each broken link location as warning
  # Return the adapted content string

  unresolved = regex_find_all(example_content, r"\{\{[A-Z_]+\}\}")
  broken_links = regex_find_all(example_content, r"\]\(\)")

  IF len(unresolved) > 0:
    log_warning("adapt_example: {len(unresolved)} unresolved placeholders remain: {unresolved}")
  IF len(broken_links) > 0:
    log_warning("adapt_example: {len(broken_links)} broken markdown links found")

  RETURN example_content
```

### Feedback Tracking Protocol

Track how often knowledge chunks are retrieved to surface underused sources and optimize
the knowledge base. This is a passive, zero-latency tracking mechanism.

**Counters per source in knowledge-base.yaml:**
```yaml
quality:
  times_retrieved: 0         # incremented on memory_find() returning chunks from this source
  times_useful: 0            # future opt-in (Phase 4+), always 0 in Phase 3
  avg_retrieval_score: 0.0   # running average of similarity scores
  last_quality_check: null   # ISO date, used by deprecation logic
```

**`track_retrieval(results, knowledge_base_path)`**

Called after `memory_find()` returns results. Fire-and-forget — does not delay the return.

```
track_retrieval(results, knowledge_base_path):
  IF results is empty: RETURN

  # Group by framework, only documentation type
  results_by_framework = group_by(
    [r for r in results if r.metadata.type == "documentation"],
    key = lambda r: r.metadata.framework
  )
  IF results_by_framework is empty: RETURN

  TRY:
    kb = read_yaml(knowledge_base_path)

    FOR EACH framework, chunks IN results_by_framework:
      source = find(kb.sources, WHERE source.framework == framework)
      IF source is null: CONTINUE

      IF source.quality is null:
        source.quality = { times_retrieved: 0, times_useful: 0,
                          avg_retrieval_score: 0.0, last_quality_check: null }

      FOR EACH chunk IN chunks:
        source.quality.times_retrieved += 1
        n = source.quality.times_retrieved
        source.quality.avg_retrieval_score = (
          (source.quality.avg_retrieval_score * (n-1) + chunk.score) / n
        )
      source.quality.last_quality_check = today_iso_date()

    write_yaml(knowledge_base_path, kb)
  CATCH any error:
    log_warning("track_retrieval: failed — {error}")  # Non-critical, continue
```

**Configuration (memory-config.yaml):**
```yaml
feedback:
  track_retrieval: true               # count times_retrieved
  track_usefulness: false             # future opt-in (Phase 4+)
  deprecate_unused_after_days: 180    # surface in /aid-analytics
```

**Deprecation signal (passive, no auto-deletion):**
Sources with `times_retrieved == 0` AND `last_quality_check` 180+ days old are surfaced
in `/aid-analytics` as optimization candidates. PM must manually decide.

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
  -> Results are useful IN-RUN only (displayed to PM, used by current agents)
  -> NOT persisted to Qdrant (no cross-run or cross-project knowledge)
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

**Last Updated:** 2026-02-27
