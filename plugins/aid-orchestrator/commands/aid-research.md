---
name: aid-research
description: On-demand knowledge research — topic, URL, or deep mode
user_invocable: true
---

Trigger on-demand research for any framework topic or documentation URL. Stores quality-gated chunks in the knowledge base for use by brainstorming and agent dispatch.

This command provides three modes: **topic** (quick research on a framework/topic), **URL** (fetch and index a specific documentation page), and **deep** (extended research with detailed API reference). All operations are non-blocking and degrade gracefully.

## Usage

```
/aid-research [--deep] <framework> [topic]
/aid-research <url>
```

**Examples:**
```
/aid-research FastAPI                       # quick research on FastAPI
/aid-research FastAPI WebSockets            # quick research on FastAPI WebSockets topic
/aid-research --deep LangGraph checkpointing  # deep research on LangGraph checkpointing
/aid-research https://docs.celery.dev/      # fetch, extract, and index a URL
```

## Prerequisites

- `.aid-o/` workspace should exist (run `/aid-init` first; if missing, warn but proceed with in-run-only results)
- For persistent storage: Qdrant MCP configured (see `/aid-setup` Option 6a)
- For Context7 source: Context7 MCP configured (see `/aid-setup` Option 6b)
- Without Qdrant: research results are useful in the current run but not persisted
- Without Context7: WebSearch fallback is used automatically

## Flow

### Step 1: Parse Arguments

Parse `$ARGUMENTS` to determine the research mode.

```
INPUT = $ARGUMENTS (trimmed)

IF INPUT is empty:
  -> Ask PM: "What would you like to research? Enter a framework name, topic, or URL."
  -> Wait for response, re-parse

IF INPUT starts with "http://" OR "https://":
  -> MODE = "url"
  -> url = INPUT

ELIF INPUT starts with "--deep":
  -> MODE = "deep"
  -> remaining = INPUT with "--deep" removed (trimmed)
  -> Parse remaining: first word = framework, rest = topic (may be empty)
  -> IF framework is empty:
     -> Ask PM: "What framework should I research in depth?"
     -> Wait for response, set framework

ELSE:
  -> MODE = "topic"
  -> Parse INPUT: first word = framework, rest = topic (may be empty)
```

**Parsing rules summary:**

| Input | Mode | Framework | Topic | Depth |
|-------|------|-----------|-------|-------|
| `FastAPI` | topic | FastAPI | (none -- general overview) | quick |
| `FastAPI WebSockets` | topic | FastAPI | WebSockets | quick |
| `--deep LangGraph checkpointing` | deep | LangGraph | checkpointing | deep |
| `--deep FastAPI` | deep | FastAPI | (none -- general overview) | deep |
| `https://docs.celery.dev/` | url | (from page) | (from page) | quick |

### Step 2: Load Configuration

1. Read `defaults/integrations.yaml` for knowledge configuration (memory + knowledge sections)
2. Configuration fields:
   - `knowledge.enabled` -- if false, warn PM and abort
   - `knowledge.context7.available` -- determines primary source
   - `knowledge.research.*` -- depth limits, chunk limits, source tiers
3. Read `.aid-o/work/knowledge-base.yaml` for existing source index
4. Check Qdrant availability:
   - If Qdrant unavailable: warn PM that results will be run-only, continue

**Present to PM:**
```
Research: {framework or URL}
====================================
Mode: {topic | deep | url}
{Framework: {framework} | URL: {url}}
{Topic: {topic} (if provided)}
Source: {context7 | websearch} (primary)
Storage: {qdrant | run-only}

Researching...
```

### Step 3: Execute Research (Topic / Deep Mode)

For MODE = "topic" or MODE = "deep":

1. **Check existing knowledge:**
   - Look up `framework` in `knowledge-base.yaml`
   - If entry exists with `status == "active"`:
     - If MODE == "topic" AND no specific topic AND `depth` >= requested depth:
       ```
       {framework} already researched ({chunks_in_qdrant} chunks, {source}).
       Use --deep to fetch extended API reference, or provide a specific topic.
       ```
       -> STOP (no re-fetch for general quick research)
     - If specific topic provided: proceed (topic-specific research is always allowed)
     - If MODE == "deep" AND existing depth == "quick": proceed (upgrade to deep)

2. **Call `knowledge_research()`** following `skills/memory-mcp.md`:
   ```
   result = knowledge_research(
     framework = framework,
     depth = "deep" IF MODE == "deep" ELSE "quick",
     topic = topic OR null
   )
   ```

   This internally:
   - Checks Qdrant for existing global chunks (cross-project reuse)
   - Tries Context7 MCP (resolve-library-id -> query-docs)
   - Falls back to WebSearch if Context7 unavailable or library not found
   - Parses response into chunks (~300 words each)
   - Runs all 4 quality gates on each chunk (min value, dedup, metadata, size)
   - Stores passing chunks in Qdrant with `project_name="global"`
   - Updates `knowledge-base.yaml` with source reference

3. **Collect result:**
   ```
   result = {
     chunks_stored: N,
     chunks_rejected: M,
     source: "context7" | "websearch" | "reused_global",
     library_id: "/org/lib" | null,
     framework: "FrameworkName",
     status: "completed" | "already_indexed" | "reference_added"
   }
   ```

### Step 4: Execute Research (URL Mode)

For MODE = "url":

1. **Validate URL:**
   - Confirm URL starts with `http://` or `https://`
   - Extract domain for source tier classification (Tier 1 / Tier 2 / ignored)

2. **Fetch and extract:**
   ```
   TRY:
     content = WebFetch(
       url = url,
       prompt = "Extract key concepts, API reference, code snippets,
                 common patterns, and gotchas from this documentation page.
                 Include specific function/class/method names and parameters.
                 Preserve code examples."
     )
   CATCH (timeout, unreachable, error):
     -> Report to PM:
        "URL unreachable: {url}
         Error: {error_message}
         Research aborted for this URL."
     -> STOP
   ```

3. **Detect framework from content:**
   - Infer framework name from page title, headings, or URL path
   - If ambiguous, ask PM: "What framework does this URL document?"

4. **Parse into chunks:**
   - Split content by heading boundaries, code block boundaries, topic shifts
   - Target ~300 words max per chunk
   - Each chunk = 1 concept / pattern / API endpoint

5. **Assign confidence:**
   - Tier 1 domains (github.io, readthedocs.io, official framework sites) -> confidence: "high"
   - Tier 2 domains (github.com READMEs, pypi.org) -> confidence: "medium"
   - Unknown domains -> confidence: "medium" (PM vouched by providing the URL)

6. **Quality gate each chunk** (same 4 gates as topic mode):
   ```
   FOR EACH chunk IN chunks:
     result = run_quality_gates(chunk, source="manual")
     IF result.passed: approved_chunks.append(chunk)
     ELIF result.action == "merge": merge_with_existing(chunk, result.existing_match)
     ELSE: log("Chunk rejected: {result.gate}, reason: {result.reason}")
   ```

7. **Store passing chunks:**
   ```
   FOR EACH chunk IN approved_chunks:
     memory_store("documentation", chunk.text, {
       framework: detected_framework,
       framework_version: detected_version,
       section: inferred_section,
       source: "manual",
       source_url: url,
       source_library_id: null,
       indexed_at: now(),
       valid_until: now() + 90_days,
       project_name: "global",
       confidence: tier_confidence,
       depth: "quick"
     })
   ```

8. **Update knowledge-base.yaml:**
   ```
   source_entry = find_or_create_source(detected_framework)
   source_entry.source = "manual"
   source_entry.url = url
   source_entry.indexed_at = today()
   source_entry.valid_until = today() + 90_days
   source_entry.status = "active"
   source_entry.depth = "quick"
   source_entry.chunks_in_qdrant = len(approved_chunks)
   source_entry.confidence = tier_confidence
   write_knowledge_base_yaml()
   ```

### Step 5: Present Results

After research completes (any mode), present a PM-friendly summary.

**Success output:**
```
Research Complete: {framework}
====================================
Topic: {topic or "general overview"}
Mode: {quick | deep | url}
Source: {context7 | websearch | manual}
URL: {url (if URL mode)}

Chunks stored: {N} ({M} rejected by quality gates)
{Library ID: {id} (if Context7)}
Storage: {qdrant (persistent) | run-only}

{IF N > 0:}
Key topics indexed:
  - {section_1}: {brief description}
  - {section_2}: {brief description}
  - {section_3}: {brief description}
  {... up to 5 sections}

{IF M > 0:}
Rejected chunks: {M}
  Reasons: {summary of rejection reasons, e.g., "3 too short, 1 duplicate"}

Knowledge is now available for /aid-plan brainstorm and agent dispatch.
```

**Already indexed output:**
```
Research: {framework}
====================================
Already indexed: {chunks_in_qdrant} chunks ({source}, indexed {date})
Status: active (expires {valid_until})

To refresh: wait until expiration or re-run with a specific topic:
  /aid-research {framework} {suggested_topic}
To upgrade to deep: /aid-research --deep {framework}
```

**No quality sources output:**
```
Research: {framework}
====================================
No quality sources found.

Tried: {context7 | websearch | both}
{IF context7: "Library not found in Context7"}
{IF websearch: "No Tier 1/2 documentation pages found"}

Suggestions:
  - Provide a direct URL: /aid-research https://docs.example.com/
  - Check the framework name spelling
  - This framework may not have indexed documentation yet
```

**URL unreachable output:**
```
Research: {url}
====================================
URL unreachable.
Error: {error_description}

Suggestions:
  - Verify the URL is accessible in your browser
  - Check for authentication requirements (private docs are not supported)
  - Try an alternative documentation URL
```

**Qdrant unavailable output (appended to any result):**
```
Note: Qdrant is not available. Research results are useful in this
run only and will NOT be persisted for future runs or projects.
Run /aid-setup to configure Qdrant for persistent knowledge storage.
```

## Error Handling

All errors are non-blocking. No research failure ever blocks the PM workflow.

| Error | Handling |
|-------|----------|
| Context7 MCP unavailable | Fall back to WebSearch silently |
| Context7 library not found | Fall back to WebSearch for that framework |
| WebSearch returns no Tier 1/2 results | Report "no quality sources", store nothing |
| WebFetch fails for URL | Report "URL unreachable", abort that URL |
| Qdrant MCP unavailable | Results are run-only, warn PM |
| All sources fail | Report, proceed without knowledge |
| knowledge-base.yaml missing | Create it from template, continue |
| memory-config.yaml missing knowledge section | Use defaults (context7 if available, websearch otherwise) |
| Chunk rejected by quality gates | Log reason, continue with remaining chunks |

## Reference Files

- `skills/memory-mcp.md` -- full research protocol, quality gates, storage architecture
- `skills/memory-mcp.md` -- Qdrant storage protocol, memory_store / memory_find functions
- `commands/aid-setup.md` -- MCP configuration (Context7, Qdrant setup)
- `defaults/policies/memory-config.yaml` -- knowledge configuration schema
- `defaults/templates/knowledge-base.yaml` -- per-project reference index template

## Important

- **Non-blocking:** No research failure ever blocks PM. Every error degrades gracefully.
- **Quality gates are mandatory.** Every chunk must pass all 4 gates before storage. No data is better than bad data.
- **Global storage:** All documentation chunks use `project_name="global"`. Research done in one project benefits all projects.
- **No re-fetch:** If a framework is already actively indexed with sufficient depth, do not re-fetch unless a specific topic is requested or a depth upgrade is needed.
- **Cross-project reuse:** Before fetching, check Qdrant for existing global chunks from other projects. Reuse if sufficient.
- **URL mode is PM-initiated.** The PM vouches for URL relevance by providing it. Assign at least "medium" confidence.
- **Run-only fallback:** If Qdrant is unavailable, research still runs and results are displayed to PM. They are useful in the current run even without persistence.
- If `.aid-o/` does not exist, warn PM and proceed with run-only results (no YAML updates, no persistent storage).
