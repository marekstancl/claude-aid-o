---
id: P-20260220-1988
type: plan
status: done
created: 2026-02-20
author: PM + AI
---

# Plan: Knowledge Acquisition Skill for AID Orchestrator

## Context

AID agents currently work only with information available in their context window and local project files. They have no mechanism to actively retrieve current framework documentation, API specifications, or leverage accumulated knowledge from previous projects during planning and implementation.

Three related needs converged into this plan:

1. **Documentation Research** — When AID analyzes a project or plans an EPIC, it should be able to look up current documentation for the detected tech stack (FastAPI, LangChain, React, etc.) instead of relying solely on model training data.
2. **Cross-Project Expertise** — AID already stores decisions, lessons, and patterns in Qdrant (via memory-mcp), but the brainstorming skill does not consume this knowledge. Past project experience should inform future design proposals.
3. **Framework Expertise Building** — Rather than hardcoding expertise for specific frameworks (e.g., LangChain/LangGraph), AID should be able to *become* an expert on any framework through its knowledge acquisition pipeline — making it tech-stack agnostic by design.

The existing memory-mcp skill provides ~70% of the infrastructure (Qdrant store/find, cross-project protocol). This plan addresses the missing 30%: active knowledge acquisition, quality-gated storage, and consumption integration into brainstorming and agent dispatch.

### Key Design Decisions from Brainstorming

- **Context7 MCP as primary source** — Provides curated, up-to-date documentation for 1000+ libraries. Much more reliable than WebSearch for framework docs. WebSearch is fallback only.
- **Dual storage** — Per-project YAML index (what THIS project uses) + global Qdrant store (actual documentation chunks shared across projects). YAML for structured reference data, Qdrant for semantic search.
- **Quality gates are non-negotiable** — Without them, Qdrant fills with noise that degrades agent performance. Every chunk must pass 4 gates before storage.
- **No per-project example directories** — Community templates live in plugin `defaults/examples/`. Project-specific patterns go into Qdrant (global). No `.aid-o/03-config/examples/` directory.
- **No hardcoded framework expertise** — AID becomes expert on ANY framework through knowledge acquisition, not through coded-in knowledge about specific stacks.
- **Manual sources via conversation** — PM tells AI "add docs for X", AI handles everything. No manual YAML editing.

## Goal

Add a knowledge-acquisition skill that enables AID to actively research framework documentation (primarily via Context7 MCP), store it with quality gates in Qdrant, and serve relevant knowledge to brainstorming sessions and agents — improving the quality of design proposals and implementation guidance across all projects.

## Scope

**In scope:**
- New skill: `knowledge-acquisition.md` (research, storage, consumption protocols)
- Context7 MCP integration in `/aid-setup` (detection, guided install, configuration)
- Docker MCP as recommended in `/aid-setup`
- New Qdrant document type: `documentation` (framework docs chunks)
- Quality gates for Qdrant storage (min value, deduplication, metadata completeness, confidence scoring)
- Knowledge consumption in brainstorming (Steps 1 and 3)
- Knowledge context injection into agent dispatch (via agent-core)
- Per-project reference index: `knowledge-base.yaml`
- Extended `memory-config.yaml` with knowledge section
- Command prefix refactor: rename 5 commands to `aid-*` prefix, delete 9 unused command files (logic stays in skills)
- New command: `/aid-research` for on-demand research (Phase 2)
- Aging protocol with TTL and freshness weighting (Phase 2)
- Manual source addition via conversational interface (Phase 2)
- Auto-extraction of example patterns from completed EPICs (Phase 3)
- Community example EPICs in `defaults/examples/` (Phase 3)
- New Qdrant document type: `example_epic` (Phase 3)
- Feedback tracking: retrieval counts and usefulness signals (Phase 3)

**Out of scope:**
- Modifying Qdrant MCP server itself (external dependency)
- Crawling/scraping documentation sites (we use Context7 or single-page WebFetch)
- Real-time documentation monitoring / version watch
- Hardcoded framework expertise (against AID's agnostic design)
- Per-project example directories (community templates only)
- UI components or dashboard for knowledge management

## Approach

### Option A: Standalone Skill + New Command (Chosen, Phased)

A new `knowledge-acquisition.md` skill serves as the central definition for the entire knowledge pipeline. A new `/aid-research` command provides PM with direct on-demand research access. Five existing components are extended to integrate the knowledge pipeline. Implementation is split into 3 phases (each a separate EPIC) to deliver value incrementally and validate the approach.

**Pros:**
- Clear separation of concerns — knowledge has its own skill file
- `/aid-research` gives PM direct access to research on-demand
- Self-contained documentation for contributors
- Quality gates, aging, research protocol — all defined in one place
- Community examples in `defaults/examples/` as part of plugin distribution
- Phased delivery: Phase 1 covers ~80% of value at a fraction of effort

**Cons:**
- More files to coordinate (skill + command + 5 extensions)
- Larger total scope (3 EPICs across phases)
- Phase 1 will be functional but incomplete until phases 2-3

### Option B: Extend memory-mcp Only (Rejected)

Integrate everything into existing `memory-mcp.md`. No new skill file.

**Pros:** Fewer files, simpler dependency graph.
**Cons:** memory-mcp would grow to 1000+ lines, mixing passive memory with active acquisition. Poor contributor experience.

**Rejected because:** Conceptually, passive memory (what happened) and active acquisition (go find out) are different domains. Mixing them creates an unmaintainable monolith.

### Option C: Full Delivery in One EPIC (Rejected)

Deliver everything in a single EPIC instead of 3 phases.

**Pros:** Complete feature in one pass.
**Cons:** Large scope, high risk, no opportunity to validate before investing in advanced features.

**Rejected because:** Phased approach delivers immediate value (Context7 + brainstorming) and allows course correction based on real usage.

### Decision

**Chosen:** Option A with phased delivery (3 EPICs).
**Rationale:** Architecturally sound (standalone skill), pragmatically delivered (MVP first). Phase 1 provides Context7 integration + brainstorming knowledge consumption — the highest-value features. Phases 2-3 add sophistication on a validated foundation.

---

## Architecture

### Component Diagram

```
                    ┌──────────────────────────┐
                    │  knowledge-acquisition.md │
                    │  (skill — central def.)   │
                    └──────────┬───────────────┘
                               │ defines protocols
          ┌────────────────────┼─────────────────────┐
          ▼                    ▼                      ▼
   Research Protocol    Storage Protocol       Consumption Protocol
   (how to acquire)     (where & how to store) (how to serve)
          │                    │                      │
          ▼                    ▼                      ▼
  ┌───────────────┐   ┌──────────────┐    ┌──────────────────┐
  │ Context7 MCP  │   │ Qdrant       │    │ brainstorming.md │
  │ (primary)     │   │ (global)     │    │ (Step 1 + 3)     │
  ├───────────────┤   ├──────────────┤    ├──────────────────┤
  │ WebSearch     │   │ knowledge-   │    │ agent-core.md    │
  │ (fallback)    │   │ base.yaml    │    │ (context inject) │
  ├───────────────┤   │ (per-project)│    ├──────────────────┤
  │ PM verbal     │   └──────────────┘    │ /aid-research    │
  │ ("add X")     │                       │ (PM on-demand)   │
  └───────────────┘                       └──────────────────┘
```

The skill is NOT registered as an agent (no step in EPIC pipeline). Instead, it defines protocols that existing components call at the right moment.

### Component Responsibilities by Phase

| Component | Phase 1 | Phase 2 | Phase 3 |
|---|---|---|---|
| `knowledge-acquisition.md` (skill) | Create (core: research, storage, consumption) | Extend (aging, manual sources) | Extend (example extraction, feedback) |
| `aid-setup.md` (command) | Context7 + Docker MCP recommended | — | — |
| `memory-mcp.md` (skill) | +documentation type, +quality gates | +aging protocol in find | +example_epic type, +feedback tracking |
| `brainstorming.md` (skill) | +knowledge_find in Step 1+3 | — | +example EPIC lookup in Step 3 |
| `agent-core.md` (skill) | +knowledge context injection | — | — |
| `aid-research.md` (command) | — | Create | — |
| `memory-config.yaml` (default) | +knowledge section | +aging config | +feedback config |
| `defaults/examples/` | — | — | Create community EPICs |
| **Command files** (19 → 10) | Rename 5 commands (`aid-` prefix), delete 9 unused commands, update all references | — | — |

---

## Storage Architecture

### Design Principle: Dual Storage

```
knowledge-base.yaml = per-project (in .aid-o/)
  → "What THIS project needs to know"
  → Reference index of frameworks relevant to THIS stack
  → Never edited manually by PM — AI manages it

Qdrant = global (in ~/.local/share/aid-orchestrator/)
  → Actual content (documentation chunks, patterns)
  → Shared across all projects
  → Tag: project_name="global" for docs, project_name="xyz" for patterns
```

**Why YAML and not Qdrant for references:** URLs, versions, TTL, status — these are structured attributes requiring exact filtering (`status == active AND framework == FastAPI`), not semantic search. YAML is simple, readable, and allows PM override if needed.

**Why Qdrant for documentation chunks:** Semantic search is essential. Agent asks "how to do dependency injection in FastAPI" — this requires meaning-based retrieval, not keyword matching.

### Cross-Project Sharing Flow

```
Project A: FastAPI + React
  .aid-o/knowledge-base.yaml:
    sources: [FastAPI, React, Pydantic]
  → Research stores chunks in Qdrant with framework="FastAPI", project_name="global"

Project B: FastAPI + Vue
  .aid-o/knowledge-base.yaml:
    sources: [FastAPI, Vue, Pydantic]
  → Research for FastAPI:
    knowledge_find("FastAPI") → FINDS chunks from Project A
    → Skip re-fetch, just add reference to B's knowledge-base.yaml
    → Research only Vue (new)

New project with FastAPI does NOT re-fetch — it reuses existing global chunks.
```

### Per-Project Reference Index: `knowledge-base.yaml`

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
        times_retrieved: 34
        times_useful: 28
        avg_retrieval_score: 0.72
        last_quality_check: "2026-02-20"
```

### Qdrant Document Types

**New type: `documentation`**

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

**New type: `example_epic` (Phase 3)**

```json
{
  "information": "RAG chatbot: LangChain + Chroma + FastAPI. Architecture: ingestion pipeline → vector store → retrieval chain → LLM with conversation memory. Key decisions: ConversationBufferWindowMemory (not full buffer), Chroma for simplicity, LangChain Expression Language for chain composition.",
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

---

## Research Protocol

### Source Priority

```
IF context7_available:
  PRIMARY:  Context7 MCP (resolve-library-id → query-docs)
  FALLBACK: WebSearch + WebFetch (if library not in Context7)
ELSE:
  PRIMARY:  WebSearch + WebFetch
  MANUAL:   PM provides URL → AI fetches + indexes
```

### Context7 Research Flow

```
research_framework(name, depth="quick", topic=null):

  1. RESOLVE library:
     lib = resolve-library-id(
       libraryName = name,
       query = topic or "How to use {name} - setup, API, common patterns"
     )

     IF lib NOT found:
       → log: "{name} not in Context7"
       → FALLBACK to websearch_research(name, depth, topic)
       → RETURN

  2. QUERY documentation:
     IF depth == "quick":
       query = topic or "{name} key concepts, common patterns, best practices, gotchas"
     ELIF depth == "deep":
       query = topic or "{name} detailed API reference, all parameters, edge cases"

     docs = query-docs(libraryId=lib.id, query=query)

  3. PARSE into chunks:
     chunks = parse_context7_response(docs)
     Each chunk = 1 concept/pattern/API, max ~300 words

  4. QUALITY GATE each chunk (see Quality Gates section)

  5. STORE passing chunks:
     FOR EACH chunk that passed gates:
       qdrant-store(
         information = chunk.text,
         metadata = {
           type: "documentation",
           framework: name,
           framework_version: detected_version,
           section: inferred_section,
           source: "context7",
           source_library_id: lib.id,
           indexed_at: now(),
           valid_until: now() + 90 days,
           project_name: "global",
           confidence: "high",
           depth: depth
         }
       )

  6. UPDATE knowledge-base.yaml:
     Add or update source entry with chunks_in_qdrant count

  7. RETURN: { chunks_stored: N, source: "context7", library_id: lib.id }
```

### WebSearch Fallback Flow

```
websearch_research(name, depth="quick", topic=null):

  1. SEARCH:
     query = "{name} official documentation {topic} {current_year}"
     results = WebSearch(query)

  2. PRIORITIZE sources:
     Tier 1 (high confidence):  Official docs (github.io, readthedocs, framework homepage)
     Tier 2 (medium confidence): GitHub README, API reference pages
     Tier 3 (low, ignore):      Random blogs, Stack Overflow, Medium articles

     Select top 3 Tier 1-2 URLs

  3. FETCH & EXTRACT:
     FOR EACH url IN selected (max 3):
       content = WebFetch(url)

       IF fetch fails → skip, log, continue

       Extract:
         - Key concepts (what the framework does, main API)
         - Code snippets (max 500 tokens per chunk)
         - Common patterns (best practices, recommended approaches)
         - Gotchas/caveats (what doesn't work intuitively)

       Split into chunks (1 chunk = 1 concept/pattern, max ~300 words)

  4. QUALITY GATE each chunk

  5. STORE passing chunks with confidence based on tier:
     Tier 1 source → confidence: "high"
     Tier 2 source → confidence: "medium"

  6. UPDATE knowledge-base.yaml

  7. RETURN: { chunks_stored: N, source: "websearch" }
```

### Two-Level Research Depth

```
Level 1 — "quick" (default, always):
  What:  Key concepts, common patterns, gotchas, best practices
  How many: 5-15 chunks per framework
  When:  At onboarding (/aid-setup), automatically
  For whom: Brainstorming, architect, planner
  Example: "FastAPI uses Depends() for DI, supports async natively"

Level 2 — "deep" (on-demand, Phase 2):
  What:  Detailed API reference, parameters, edge cases
  How many: 20-50 chunks per framework
  When:  On request (/aid-research --deep FastAPI authentication)
  For whom: Backend/frontend agent during implementation
  Example: "OAuth2PasswordBearer(tokenUrl='token', scheme_name='JWT',
           auto_error=True). When auto_error=False, returns None
           instead of raising 401."
```

### Research Failure Handling

```
WebFetch fails       → skip URL, log, continue with next
No quality sources   → log warning, store nothing (no data > bad data)
Context7 unavailable → fall back to WebSearch silently
Qdrant unavailable   → knowledge usable in-session only, not persisted
Never block workflow  → all research failures are non-blocking
```

---

## Quality Gates for Storage

Every chunk MUST pass all 4 gates before being stored in Qdrant.

### Gate 1: Minimum Informational Value

```
PASS if chunk contains at least one of:
  - Specific API/function/class/method with description
  - Code snippet (min 2 lines)
  - Concrete pattern/procedure with explanation
  - Specific constraint/gotcha/caveat

REJECT if chunk is:
  - Marketing text ("FastAPI is the fastest framework...")
  - Too generic ("You can use databases with FastAPI")
  - Navigation/menu content ("Home > Docs > Tutorial > ...")
  - Shorter than 50 words without code snippet
```

### Gate 2: Deduplication

```
existing = memory_find(chunk_text, min_score=0.85)

IF match found with score > 0.85:
  → REJECT (duplicate — already stored)

IF match found with score 0.70-0.85:
  → MERGE (add metadata, keep better version of the two)

IF no match or score < 0.70:
  → PASS (new content)

For documentation type: also deduplicate against same source_id
(re-fetch must not create duplicates)
```

### Gate 3: Metadata Completeness

```
REQUIRED fields (reject without):
  - type
  - framework (for documentation type)
  - indexed_at
  - source (context7 | websearch | manual | project)

RECOMMENDED fields (warn but store):
  - framework_version
  - section
  - source_url
  - valid_until

AUTO-COMPUTED fields (filled automatically):
  - valid_until: now() + TTL based on type (if missing)
  - project_name: "global" for docs, project name for patterns
  - confidence: based on source tier (see table below)
```

### Gate 4: Size Limits

```
Minimum: 50 words OR code snippet >= 2 lines
Maximum: ~500 words / ~2000 tokens
If larger: split into sub-chunks with own metadata
```

### Confidence Scoring

| Source | Default Confidence | Notes |
|---|---|---|
| Context7 | high | Curated documentation |
| Official docs (WebFetch) | high | Tier 1 source |
| GitHub README | medium | May be outdated |
| WebSearch result | medium | Mixed quality |
| PM manual URL | medium | PM vouches for relevance |
| Project pattern (completed EPIC) | high | Validated by practice |
| Project pattern (partial EPIC) | low | Unfinished |
| Project pattern (failed EPIC) | excluded | Do not store |

---

## Triggers — When Research Happens

### Trigger 1: Onboarding (`/aid-setup`)

```
project-scanner detects stack → [Python, FastAPI, SQLAlchemy, Pydantic]

knowledge-acquisition activation:
  FOR EACH framework IN tech_stack (max 5):
    Check knowledge-base.yaml — source exists?
    → YES + status=active: skip (already have it)
    → YES + status=stale: re-validate (Phase 2: aging)
    → NO:
      Check Qdrant for existing global chunks:
        knowledge_find("{framework} documentation", type="documentation")
        → Found active chunks: just add reference to knowledge-base.yaml, NO re-fetch
        → Not found: run Research Protocol

Output: updated knowledge-base.yaml + new chunks in Qdrant
```

### Trigger 2: Brainstorming (`/aid-brainstorm`)

```
Step 1 (Context):
  knowledge_find(topic + tech_stack)
  → Returns: relevant patterns, decisions, documentation from past projects
  → Displayed as context for PM:
    "From knowledge base: in similar projects, [pattern X] worked well..."

Step 3 (Approaches):
  knowledge_find(approach_keywords)
  → Informs approach generation:
    "Project X used JWT auth with refresh tokens (lesson: worked well)"
    "FastAPI docs recommend OAuth2PasswordBearer for simple auth cases"
```

### Trigger 3: Agent Dispatch (`run-epic` EXECUTING)

```
Extension of existing memory_context_for_step():

Existing: searches decisions, lessons, patterns, commands
New:       + searches documentation chunks relevant to step objective

Example: backend agent gets step "Implement authentication endpoint"
  → memory_find("FastAPI authentication endpoint implementation")
  → Returns:
    - [documentation] FastAPI OAuth2 tutorial snippet
    - [pattern] JWT refresh token pattern from project X
    - [lesson] "Don't forget CORS middleware with auth" from project Y
  → Formatted as KNOWLEDGE CONTEXT block in agent prompt
```

### Trigger 4: Plan/EPIC Content Detection

```
Research triggered not just from project-profile.yaml tech_stack,
but also from content of plans and EPICs:

At /aid-brainstorm:
  PM mentions "I want to use Celery" →
  Parse text for framework/library mentions →
  Compare with knowledge-base.yaml →
  If unknown → automatic research BEFORE continuing →
  PM gets notification: "No knowledge about Celery found.
    Running research... Found: official docs, 8 chunks stored."

At /plan-epic:
  EPIC contains artifacts referencing unknown framework →
  Same detection and research flow
```

### Trigger 5: On-Demand (`/aid-research`) — Phase 2

```
/aid-research FastAPI WebSocket authentication
  1. Context7 query → store results → report to PM

/aid-research https://docs.celery.dev/
  1. Fetch URL → extract → quality gate → store → report

/aid-research --deep LangGraph checkpointing
  1. Deep research (more chunks, detailed API) → store → report
```

### Trigger 6: Post-EPIC Enrichment (`run-epic` DONE) — Phase 3

```
After EPIC completion:
  1. Curator collects patterns (existing behavior)
  2. NEW: knowledge-acquisition enriches patterns with framework tags
     - Pattern "repository pattern for SQLAlchemy" → tag framework=SQLAlchemy
     - Pattern "LangGraph StateGraph with checkpointer" → tag framework=LangGraph
  3. PM approval: "Save this project as template for future {framework} projects? (Y/N)"
  4. If Y: store abstracted EPIC pattern in Qdrant as type=example_epic
  5. Available for ALL future projects via semantic search
```

---

## Consumption API

### `knowledge_find(query, filters={})`

Extension of existing `memory_find()` with new document type support:

```
knowledge_find(
  query = "FastAPI dependency injection with async database session",
  filters = {
    framework: "FastAPI",                              # optional
    types: ["documentation", "pattern", "lesson"],     # default: all
    min_freshness: "active"                            # active | stale | any (Phase 2)
  }
)

Protocol:
  1. memory_find(query) with extended type support including "documentation"
  2. Apply freshness weighting (Phase 2: aging protocol)
  3. Return unified results sorted by score * freshness_weight
  4. Results include: documentation chunks + patterns + lessons — all in one list
```

### `knowledge_context_for_agent(step, epic_context)`

Extension of existing `memory_context_for_step()`:

```
Protocol:
  1. Build queries from step.objective + step.role + epic.tech_stack
  2. knowledge_find() for each query
  3. Deduplicate, limit to top_k
  4. Format output:

## KNOWLEDGE CONTEXT

### Framework Documentation
_FastAPI v0.115.x (indexed 2026-02-20, source: official docs)_

Dependency injection with Depends(): Use `async def get_db()` with
`yield` for session lifecycle management. FastAPI resolves nested
dependencies automatically.

### Patterns from Past Projects
_Project: crm-backend (2026-01-15)_

Repository pattern for SQLAlchemy async: Abstract DB access behind
repository classes, inject via Depends(). Tested pattern, works well
with FastAPI.

### Lessons
_Project: invoice-api (2025-12-01) ⚠ Stale_

SQLAlchemy async: Always call `await db.refresh(obj)` after
`db.commit()` or lazy-loaded relations won't work.
```

### `knowledge_references(framework=None)`

For PM / architect — structured list of documentation sources:

```
knowledge_references("FastAPI")

→ Returns:
  - FastAPI Official Docs: https://fastapi.tiangolo.com/ (active, v0.115.x)
  - FastAPI API Reference: https://fastapi.tiangolo.com/reference/ (active)
  - Pydantic v2 Integration: https://docs.pydantic.dev/latest/ (stale)
```

### `knowledge_research(framework, depth, topic)`

Orchestrates the full research flow:

```
knowledge_research(framework="FastAPI", depth="quick", topic=null)

Protocol:
  1. IF context7_available:
       lib = resolve-library-id(libraryName=framework, query=topic or "overview")
       IF lib found: context7_research(lib, depth, topic)
       ELSE: websearch_research(framework, depth, topic)
     ELSE:
       websearch_research(framework, depth, topic)
  2. Parse → chunk → quality gate → store
  3. Update knowledge-base.yaml
  4. Return: { chunks_stored: N, source: "context7"|"websearch", library_id: ... }
```

---

## Aging Protocol (Phase 2)

### TTL by Document Type

```
documentation:  90 days   (frameworks evolve quickly)
pattern:        180 days  (patterns are more stable)
lesson:         365 days  (lessons last longer)
decision:       ∞         (decisions are never deleted, only superseded)
```

### Freshness Weighting in Search Results

```
When knowledge_find() returns results:

  freshness_weight calculation:
    active (before valid_until):     1.0
    stale (0-30 days past):          0.7
    expired (30-180 days past):      0.3
    ancient (180+ days past):        EXCLUDE from results

  final_score = qdrant_similarity_score * freshness_weight

  If returning a stale result, label it:
    "⚠ Stale (indexed 2025-11-01, FastAPI 0.109.x — current may differ)"
```

### Re-Validation at `/aid-setup`

```
1. Iterate knowledge-base.yaml sources
2. For each source where status != "active":
   a) Fetch URL → still works?
      → Yes: refresh metadata (url, date)
      → No: status = "invalid", mark chunks as expired
   b) Compare version → new major version?
      → Yes: invalidate existing chunks, run fresh research
      → No: extend valid_until
3. Never delete from Qdrant automatically
   Only lower weight and exclude from results
   PM can manually edit knowledge-base.yaml status if needed
```

---

## Context7 MCP Setup in `/aid-setup`

New Option 6b in the MCP Server Onboarding section:

### Setup Order in `/aid-setup` Option 6

```
6a. Qdrant Memory (cross-project knowledge)        — Recommended
6b. Context7 Documentation (framework docs)         — Recommended  ← NEW
6c. Slack PM Communication                          — Optional
6d. Docker MCP (container management)               — Recommended  ← ELEVATED
6e. Auto-detect Tech MCPs (GitHub, Playwright, etc.) — Conditional
6f. Custom MCP                                      — Optional
```

### Context7 Setup Flow

```
**6b. Context7 — Framework Documentation Access (Recommended)**

Package: @upstash/context7-mcp
Context7 provides curated, up-to-date documentation for 1000+ libraries.
AID uses it as primary source for framework knowledge acquisition.

1. AUTO-DETECT: Check if Context7 MCP is already configured
   → Test: attempt resolve-library-id(libraryName="react", query="test")
   → If responds: "Context7 MCP detected and working." → skip to step 5
   → If tool_not_found: proceed to step 2

2. PRESENT to PM:
   Context7 — Framework Documentation
   ====================================

   Context7 gives AID access to up-to-date documentation for
   popular frameworks (React, FastAPI, LangChain, Next.js, ...).

   When AID plans or implements, it can look up current API docs
   instead of relying on training data that may be outdated.

   - Free, no API key needed
   - Runs locally via npx
   - Used by: brainstorming, architect, backend, frontend agents

   Install Context7? (Recommended)
   (A) Yes — automatic setup
   (B) No — AID will use WebSearch as fallback (less reliable)

3. IF A: Determine scope
   MCP scope for Context7:
   (A) Global — available in all projects (Recommended)
   (B) This project only

   IF Global:
     claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest

   IF Project:
     Add to .mcp.json:
     {
       "context7": {
         "type": "stdio",
         "command": "npx",
         "args": ["-y", "@upstash/context7-mcp@latest"]
       }
     }

4. VERIFY installation:
   TRY: resolve-library-id(libraryName="fastapi", query="test query")

   IF responds with library ID:
     → "Context7 installed and verified successfully."

   IF tool_not_found or error:
     → "Context7 installation could not be verified.
        This may be a timing issue — try restarting Claude Code.
        AID will fall back to WebSearch until Context7 is available."
     → Set context7.status: "pending_verification"

5. UPDATE configuration:

   memory-config.yaml:
     knowledge:
       enabled: true
       primary_source: "context7"
       context7:
         available: true
         scope: "user"    # or "project"
         installed_at: "2026-02-20"
       fallback_source: "websearch"

   project-profile.yaml:
     mcp_servers:
       - name: "context7"
         purpose: "framework-documentation"
         scope: "user"
         status: "active"

Common issues:
- "npx not found" → Node.js required. Suggest: brew install node or nvm install --lts
- "ETIMEOUT on first call" → Context7 cold start, normal. Retry after 5s.
- "Library not found" → Not all libraries indexed. Falls back to WebSearch for that library.
```

---

## Manual Source Addition (Phase 2)

PM does NOT edit YAML. The flow is conversational:

```
PM: "Add documentation for our internal auth library at https://wiki.company.com/auth-lib"

knowledge-acquisition:
  1. Validate URL (reachable?)
  2. Fetch → extract content → split into chunks
  3. Quality gate each chunk
  4. Store passing chunks in Qdrant with source="manual", confidence="medium"
  5. Update knowledge-base.yaml with new source entry (type="manual", status="active")
  6. Respond: "Added: internal-auth-lib, 6 chunks indexed.
              Agents now have access to auth-lib documentation."
```

Also works via `/aid-research` (Phase 2):

```
/aid-research https://wiki.company.com/auth-lib
/aid-research "Celery task queue best practices"
/aid-research --deep FastAPI WebSockets
```

knowledge-base.yaml is NEVER edited manually — it is an internal index managed by AI.

---

## Configuration

### Extended `memory-config.yaml`

```yaml
memory:
  enabled: true
  collection_name: "aid-memory"

  # ... existing auto_index and search sections ...

  # NEW: Knowledge acquisition configuration
  knowledge:
    enabled: true
    primary_source: "context7"        # context7 | websearch
    fallback_source: "websearch"

    context7:
      available: true                 # set during /aid-setup
      scope: "user"                   # user | project
      installed_at: "2026-02-20"

    research:
      default_depth: "quick"          # quick | deep
      deep_on_demand_only: true       # deep only via /aid-research --deep
      max_frameworks_per_scan: 5      # limit at onboarding
      max_urls_per_framework: 3       # WebSearch: max URLs to fetch
      max_chunks_per_source: 15       # max chunks stored per framework
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

    # Phase 2:
    aging:
      documentation_ttl_days: 90
      pattern_ttl_days: 180
      lesson_ttl_days: 365
      stale_weight: 0.7               # multiplier for stale results
      expired_weight: 0.3             # multiplier for expired results
      exclude_after_days: 180         # exclude results older than this past TTL

    # Phase 3:
    feedback:
      track_retrieval: true           # count times_retrieved
      track_usefulness: false         # opt-in future: track if agent used the knowledge
```

---

## Community Templates (Phase 3)

### Location: Plugin Distribution Only

```
plugins/aid-orchestrator/defaults/examples/
  langchain-rag-chatbot.md          ← example EPIC
  langgraph-multi-agent.md          ← example EPIC
  fastapi-crud-service.md           ← example EPIC
  react-dashboard.md                ← example EPIC
  nextjs-fullstack.md               ← example EPIC
```

NO per-project example directories. NO `.aid-o/03-config/examples/`.

### How Examples Are Consumed

In brainstorming Step 3 (Approaches):

```
PM: "I want to build a RAG chatbot"

knowledge-acquisition:
  1. Search defaults/examples/ — finds langchain-rag-chatbot.md
  2. Search Qdrant type="example_epic" — finds patterns from past projects
  3. Offer PM:
     "I have an example EPIC for LangChain RAG chatbot
      and 3 relevant patterns from previous projects.
      Use as inspiration? (A) Yes, adapt (B) No, start from scratch"

  If A:
    → Load example EPIC
    → Adapt to current project-profile (paths, framework versions)
    → Offer as Approach A with note "based on proven template"
```

### How New Examples Are Created

**From completed projects (Phase 3):**
```
After EPIC DONE:
  1. Extract abstracted pattern from successful EPIC
  2. Store in Qdrant as type="example_epic" (global, semantic search)
  3. PM approval required: "Save as template for future projects? (Y/N)"
```

**Community contribution:**
PM contributes to `defaults/examples/` in plugin repo (PR/commit).
All plugin users get the example on update.

---

## Integration Points with Existing Components

| Existing Component | Current State | Changes Needed |
|---|---|---|
| **project-scanner** (`agents/project-scanner.md`) | Detects stack, writes project-profile.yaml | No changes. Knowledge-acquisition reads project-profile after scanner runs. |
| **memory-mcp** (`skills/memory-mcp.md`) | 5 document types, store/find protocol, cross-project | +`documentation` type with schema. +Quality gate validation in `memory_store`. +`knowledge_find()` extending `memory_find()` with freshness. Phase 3: +`example_epic` type. |
| **brainstorming** (`skills/brainstorming.md`) | 9-step flow, no Qdrant consumption | Step 1: +call `knowledge_find(topic + tech_stack)` for context. Step 3: +call `knowledge_find(approach_keywords)` for informed proposals. Phase 3: +example EPIC lookup. |
| **agent-core** (`skills/agent-core.md`) | Context loading for agents, MEMORY CONTEXT block | +Extend `memory_context_for_step()` to include `documentation` type. +Format as KNOWLEDGE CONTEXT block alongside existing MEMORY CONTEXT. |
| **aid-setup** (`commands/aid-setup.md`) | MCP onboarding (Qdrant, Slack, auto-detect, custom) | +Option 6b: Context7 MCP (detect, install, scope, verify, configure). +Docker MCP elevated to recommended (6d). +Adjust "All recommended" selection to include Context7 and Docker. |
| **epic-orchestration** (`skills/epic-orchestration.md`) | DONE state indexes to Qdrant | Phase 3: +trigger example extraction after EPIC completion. |
| **curator** (`agents/curator.md`) | Collects improvement notes, stores proposals in Qdrant | Phase 3: +tag patterns with framework metadata for better retrieval. |

---

## Storage Model Summary

```
┌─────────────────────────────────────────────────┐
│                   GLOBAL                         │
│                                                  │
│  Qdrant (aid-memory collection)                  │
│  ├── documentation (framework docs) ← NEW        │
│  ├── example_epic (EPIC patterns)   ← Phase 3    │
│  ├── pattern (from projects)        ← existing    │
│  ├── decision (arch decisions)      ← existing    │
│  ├── lesson (learnings)             ← existing    │
│  ├── command (working commands)     ← existing    │
│  └── audit_finding (audit results)  ← existing    │
│                                                  │
│  Plugin defaults/examples/ (community templates) │
│  └── Static example EPICs shipped with AID       │
│                                                  │
├─────────────────────────────────────────────────┤
│                PER-PROJECT                       │
│                                                  │
│  .aid-o/04-engine/memory/                        │
│  ├── knowledge-base.yaml (reference index) ← NEW │
│  ├── project-profile.yaml          ← existing    │
│  └── active-work.md                ← existing    │
│                                                  │
│  .aid-o/04-engine/                               │
│  ├── lessons-learned.md            ← existing    │
│  ├── command-history.md            ← existing    │
│  └── backlog.md                    ← existing    │
│                                                  │
│  No examples/ directories. No extra storage.     │
└─────────────────────────────────────────────────┘
```

---

## High-Level Steps

### Phase 1 — Knowledge Acquisition MVP

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | Create `knowledge-acquisition.md` skill | Core skill with: Research Protocol (Context7 primary flow, WebSearch fallback flow, source tier prioritization, chunk extraction), Storage Protocol (4 quality gates with pseudocode, confidence scoring table, dual storage architecture), Consumption Protocol (knowledge_find, knowledge_context_for_agent, knowledge_references with pseudocode). Define all integration points. | L |
| 2 | Extend `aid-setup.md` — Context7 MCP | Add Option 6b with full setup flow: auto-detect existing Context7 → present value proposition → install with scope selection (user/project) → verify via resolve-library-id → configure memory-config.yaml and project-profile.yaml. Include common issues section. | M |
| 3 | Extend `aid-setup.md` — Docker MCP recommended | Elevate Docker MCP from auto-detect (6e) to recommended (6d). Adjust option ordering: Qdrant (6a), Context7 (6b), Slack (6c), Docker (6d), auto-detect (6e), custom (6f). Update "All recommended" selection. | S |
| 4 | Extend `memory-mcp.md` — documentation type + quality gates | Add `documentation` document type with full metadata schema. Add quality gate protocol to storage: Gate 1 (min value), Gate 2 (dedup at 0.85), Gate 3 (metadata completeness with required/recommended/auto-computed fields), Gate 4 (size limits). Add confidence scoring table. | M |
| 5 | Extend `brainstorming.md` — knowledge integration | In Step 1 (Context): call `knowledge_find(topic + tech_stack)` before questioning, display relevant past knowledge. In Step 3 (Approaches): call `knowledge_find(approach_keywords)` to inform proposals with documentation + past decisions + patterns. | M |
| 6 | Extend `agent-core.md` — knowledge context injection | Extend `memory_context_for_step()` to include `documentation` type in queries. Format results as KNOWLEDGE CONTEXT block (framework docs section + patterns section + lessons section with source attribution and staleness labels). | S |
| 7 | Create `knowledge-base.yaml` template | Template in `defaults/templates/` with: header (last_updated, context7_available, primary_source), sources list structure (id, framework, version, type, source, library_id, url, indexed_at, valid_until, status, depth, chunks_in_qdrant, confidence, quality tracking). | S |
| 8 | Extend `memory-config.yaml` — knowledge section | Add complete `knowledge:` section with: enabled, primary_source, context7 config, research subsection (default_depth, limits, source_tiers), quality subsection (thresholds, required_metadata). Stub aging and feedback sections for Phase 2-3. | S |
| 9 | Command prefix refactor — standardize `aid-` naming | **Rename 5 commands** (add `aid-` prefix): `run-epic` → `aid-run-epic`, `plan-epic` → `aid-plan-epic`, `epic-status` → `aid-epic-status`, `epic-queue` → `aid-epic-queue`, `audit` → `aid-audit`. Update `name:` field in YAML frontmatter of each. **Delete 9 command files** that PM doesn't use and agents don't invoke (they use skills directly): `session-start`, `session-end`, `handoff`, `coding-standards`, `docs-protocol`, `testing`, `quality-gates`, `run-gates`, `run-step`. **Update all references** across: `aid-help.md` (command listing), `aid-brainstorm.md` (mentions `/plan-epic`, `/run-epic`, `/epic-status`), `epic-orchestration.md` (mentions `/run-gates`, `/audit`), `session-management.md` (mentions `/session-start`, `/session-end`, `/handoff`), `README.md` (command table), and any other files referencing old command names. Result: 10 PM commands, all with `aid-` prefix, easily discoverable. | M |
| 10 | Update `/aid-plan-epic` command — clarify auto-EPIC generation flow | Update the `/aid-plan-epic` skill/command description and documentation to accurately reflect that: **(a)** when given a Plan file as input, the command **auto-generates the EPIC first** (Step 0.7: Plan-to-EPIC conversion) and then immediately proceeds to generate the execution plan (plan.json + session file) — this is a single-command workflow, not two separate steps; **(b)** at the end of successful plan generation (Step 6), the command **asks PM: "Want to run this EPIC now? (`/aid-run-epic {epic_id}`)"** instead of just printing "Next: Run /run-epic..."; **(c)** update the "Usage" section, examples, and the `## Important` section at the bottom of the command file to reflect this unified Plan→EPIC→Plan flow. Update `aid-help.md` description of `/aid-plan-epic` accordingly. The current Step 0.5 + 0.7 logic is already correct — this step only fixes the **documentation and UX text** to match actual behavior. | S |

### Phase 2 — On-Demand Research + Aging

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | Create `aid-research.md` command | `/aid-research [topic\|URL] [--deep]`. Topic mode: Context7/WebSearch → store → report. URL mode: fetch → extract → quality gate → store → report. Deep mode: extended chunk count + detailed API reference. | M |
| 2 | Extend `knowledge-acquisition.md` — aging protocol | TTL per type (docs 90d, patterns 180d, lessons 365d). Freshness weight formula (active=1.0, stale=0.7, expired=0.3, ancient=exclude). Re-validation flow at /aid-setup. | M |
| 3 | Extend `knowledge-acquisition.md` — manual source protocol | Conversational flow: PM says "add docs for X" → validate URL → fetch → chunk → quality gate → store → confirm. No YAML editing by PM. | S |
| 4 | Extend `memory-mcp.md` — aging in find | Apply freshness_weight to search results (score * freshness_weight). Exclude ancient entries (180+ days past TTL). Add stale warning labels to returned results. | M |
| 5 | Register command in plugin.json | Add `/aid-research` command registration and agent definition. | S |

### Phase 3 — Auto-Extraction + Community Examples

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | Extend `knowledge-acquisition.md` — example extraction | Protocol for post-EPIC extraction: abstract EPIC pattern → PM approval → store as example_epic in Qdrant. Tag with frameworks and source project. | M |
| 2 | Extend `epic-orchestration.md` — DONE state extraction | In DONE state: trigger example extraction after curator runs. PM confirmation required. Only from completed (not partial/failed) EPICs. | M |
| 3 | Create `defaults/examples/` — community templates | Write 3-5 example EPICs: langchain-rag-chatbot, langgraph-multi-agent, fastapi-crud-service, react-dashboard, nextjs-fullstack. Follow EPIC template format. | M |
| 4 | Extend `brainstorming.md` — example EPIC lookup | In Step 3: search defaults/examples/ + Qdrant example_epic type. Offer PM: "Use as inspiration?" Adapt to current project-profile if accepted. | S |
| 5 | Extend `memory-mcp.md` — example_epic type + feedback | Add `example_epic` document type with schema (frameworks, source_epic_id, source_project). Add feedback tracking: times_retrieved counter in knowledge-base.yaml quality section. | S |

## Constraints

- **Context7 is external** — AID defines the integration protocol but does not control Context7 availability or library coverage. WebSearch fallback is mandatory.
- **Qdrant is optional** — Knowledge acquisition must gracefully degrade without Qdrant (Context7 results still useful in-session, just not persisted).
- **No breaking changes** — All extensions to existing skills must be backward-compatible. Projects without knowledge config must work identically to today.
- **Plugin documentation language** — All plugin files (skills, commands, agents) are written in English per CLAUDE.md convention.
- **Quality over quantity** — Better to store 10 high-quality chunks than 100 noisy ones. Quality gates are non-negotiable.
- **Budget** — Phase 1: ~$25, Phase 2: ~$15, Phase 3: ~$15. Total: ~$55 across 3 EPICs.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Context7 unavailable or missing library | Medium | Medium | WebSearch fallback always available. Graceful degradation. |
| Low-quality Qdrant chunks pollute agent context | High (without gates) | High | Quality gates before every store: min value, dedup, confidence scoring. |
| knowledge-base.yaml desync with Qdrant | Low | Low | YAML is index only; Qdrant is source of truth. Rebuild YAML from Qdrant if needed. |
| Too many chunks overwhelm agent context | Medium | Medium | top_k limit + min_score threshold + freshness weighting. |
| Brainstorming latency from Qdrant calls | Low | Low | 5s timeout, skip if slow. Non-blocking. |
| Phase 1 design incompatible with Phase 2-3 | Low | High | Skill file designed for extension from day one. Aging and feedback are additive, not restructuring. |

## Success Criteria

- [ ] Context7 MCP can be installed and configured via `/aid-setup` with guided flow (detect → install → scope → verify → configure)
- [ ] `/aid-brainstorm` for a FastAPI project shows relevant FastAPI documentation in approach proposals
- [ ] Backend agent receives KNOWLEDGE CONTEXT block with framework docs before implementation
- [ ] Quality gates reject: marketing text, chunks <50 words, duplicates (>0.85 match), chunks missing required metadata
- [ ] System works without Context7 (WebSearch fallback) and without Qdrant (in-session only)
- [ ] New project with FastAPI reuses existing global Qdrant chunks without re-fetching
- [ ] No regression: projects without knowledge config behave identically to current behavior
- [ ] (Phase 2) `/aid-research FastAPI WebSockets` stores relevant chunks and reports to PM
- [ ] (Phase 2) PM says "add docs for X" and AI handles the full flow without YAML editing
- [ ] (Phase 2) Stale documentation chunks get lower relevance scores (score * 0.7)
- [ ] (Phase 3) Completed EPIC generates abstracted example pattern in Qdrant (with PM approval)
- [ ] (Phase 3) Brainstorming offers relevant community examples when available

## Next Steps

- [ ] Create EPIC for Phase 1 (Knowledge Acquisition MVP) — see EPIC draft
- [ ] After Phase 1 completion and validation: create EPIC for Phase 2
- [ ] After Phase 2 completion: create EPIC for Phase 3
- [ ] Add Context7 and Docker MCP to "All recommended" default in `/aid-setup`

---

**Last Updated:** 2026-02-20
