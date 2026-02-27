# Brainstorming — Knowledge Acquisition & File Analysis

**Skill:** brainstorming-knowledge
**Parent:** brainstorming
**Dependencies:** knowledge-acquisition

---

## TL;DR

Sub-skill of brainstorming. Contains knowledge-augmented brainstorming (pre-brainstorming knowledge search, approach-informed knowledge search, example EPIC lookup), sample file analysis from `.aid-o/05-inputs/`, and all non-blocking/graceful degradation guarantees. Loaded by the brainstorming skill when knowledge acquisition is configured.

---

## Knowledge-Augmented Brainstorming

When knowledge acquisition is configured, the brainstorming run is augmented with
relevant knowledge from past projects, stored documentation, patterns, and lessons learned.
This gives the brainstorming agent awareness of existing context before asking questions and
proposing approaches.

**Principle:** Knowledge retrieval is strictly non-blocking. It enriches the run when
available but never delays or degrades it when unavailable.

### Pre-Brainstorming Knowledge Search (Step 1 Integration)

Before the questioning phase begins, search for relevant knowledge about the PM's topic.
This informs which questions to ask and surfaces patterns from past work.

```
WHEN: Step 1 (Context Gathering), after reading project context but before first question.

mem_config = read(".aid-o/03-config/policies/memory-config.yaml")

IF mem_config.knowledge.enabled:
  topic = PM's stated topic or idea (from /aid-brainstorm [topic])
  tech_context = project-profile.yaml -> tech_stack (joined as string)

  results = knowledge_find(
    query = "{topic} {tech_context}",
    filters = { types: ["documentation", "pattern", "decision", "lesson"] }
  )
  TIMEOUT: 5 seconds. If slow, skip silently.

  IF results (non-empty):
    # --- PM-facing knowledge summary (concise, max 5 lines) ---
    doc_names = []
    FOR EACH result IN results (max 5):
      name = result.metadata.project_name OR result.metadata.framework OR result.metadata.type
      source = "Qdrant"   # Step 1 uses knowledge_find() which queries Qdrant
      doc_names.append('- "{name}" ({source})')

    Display to PM:
      "Knowledge context loaded:"
      "  Found {len(results)} relevant doc(s):"
      FOR EACH entry IN doc_names:
        "  {entry}"
    # --- end PM-facing summary ---

    Use results as context for questioning:
      - Skip questions whose answers are already known from past decisions
      - Ask more targeted questions informed by known patterns
      - Reference relevant documentation when framing options
      - Do NOT skip the questioning phase entirely -- past knowledge informs, not replaces

  IF results (empty) AND mem_config.knowledge.enabled:
    Display to PM:
      "No knowledge indexed yet. Use /aid-research to add project knowledge."

IF mem_config missing OR knowledge.enabled == false OR knowledge unavailable:
  -> Skip silently. Proceed to questioning as before. No error, no message.
```

### Sample File Analysis (Step 1 Integration)

After the knowledge search and before entering the questioning phase, scan the
`.aid-o/05-inputs/` directory for sample data files. File analysis gives the brainstorming
agent concrete awareness of the PM's data landscape — column names, schema shapes, document
structure — so that questions and approach proposals are grounded in real data rather than
abstract assumptions.

**Principle:** File scanning is best-effort and non-blocking. Missing directories, empty
directories, and unreadable files are all handled silently. The PM should never see an error
from this phase.

#### 05-inputs Auto-Scan Protocol

```
WHEN: Step 1 (Context Gathering), AFTER reading project context and knowledge search,
      BEFORE entering Step 2 (Questions).

1. Scan .aid-o/05-inputs/ directory:
   - Glob all files in .aid-o/05-inputs/ (recursive)
   - IF directory does not exist: skip silently, do NOT create it
   - IF directory is empty: skip silently
   - Maximum 10 files analyzed. If more than 10 files found:
     -> Analyze the first 10 (sorted alphabetically)
     -> Note to PM: "...and {N} more files (not analyzed)"

2. IF files found, analyze each by detected type:

   PDF files (.pdf):
     - Detect page count
     - Detect language (if determinable)
     - Extract structure summary (headings, form fields, tables)
     - Example result: "invoice.pdf (3 pages, Czech, structured form with tables)"

   CSV files (.csv, .tsv):
     - Read header row (column names)
     - Count total rows
     - Show sample data (first 3 rows)
     - Example result: "data.csv (1,240 rows: id, name, email, created_at)"

   JSON files (.json):
     - Detect schema structure (object vs. array at top level)
     - Show top-level keys and their value types
     - For arrays: show element count and element structure
     - Example result: "config.json (nested object: database{}, auth{}, features[])"

   Image files (.png, .jpg, .jpeg, .gif, .svg, .webp):
     - Describe visual content (use vision capabilities)
     - Note dimensions if determinable
     - Example result: "mockup.png (1200x800, UI wireframe with sidebar navigation)"

   Other files:
     - Note filename, extension, and file size
     - Attempt to read first few lines if text-based
     - Example result: "schema.xml (14 KB, XML document)"

3. Present summary to PM (ONE message, after all files analyzed):

   "Found sample files in .aid-o/05-inputs/:
    - invoice.pdf (3 pages, Czech, structured form)
    - data.csv (1,240 rows: id, name, email, created_at)
    - config.json (nested object: database, auth, features)
   I'll reference these during our discussion."

   IF no files found or directory missing: say nothing. No message to PM.

4. Store analysis results in brainstorming run state for use in:
   - WF4 (Data & Inputs) question — reference analyzed files instead of asking
     PM to describe data from scratch (see brainstorming-workflow.md -> WF4)
   - Step 3 (Approaches) — inform architecture proposals with data
     characteristics (volume, format, schema complexity)
   - Plan document — include data profile in Constraints or Context section

5. Accept arbitrary file paths from PM during the run:
   - IF PM says "also look at ./data/customers.json" or provides any file path:
     -> Read and analyze the file using the same type-detection logic above
     -> Add to the stored analysis results
     -> Present the single-file summary to PM
     -> Do NOT copy the file to .aid-o/05-inputs/
     -> Do NOT modify or move the original file
   - This can happen at any point in the run (not just Step 1)
```

#### File Analysis Rules

```
RULE F1: Directory .aid-o/05-inputs/ does not exist -> skip silently.
         Do NOT create the directory. Do NOT mention it to PM.
RULE F2: Directory .aid-o/05-inputs/ is empty -> skip silently.
         Do NOT mention it to PM.
RULE F3: File analysis is best-effort.
         If a file cannot be read or parsed, note filename and "unable to analyze"
         in the summary. Continue with remaining files.
RULE F4: Never modify input files.
         Read-only access. No renaming, no moving, no copying, no deleting.
RULE F5: Maximum 10 files analyzed per scan.
         Files beyond the limit are noted but not analyzed.
RULE F6: File scan must not block brainstorming.
         If file analysis takes longer than 10 seconds total, stop analysis,
         present partial results, and continue to Step 2.
RULE F7: PM-provided file paths are analyzed on demand.
         Same type-detection logic, same read-only constraint, no file limit
         (PM explicitly chose these files). Added to run state incrementally.
RULE F8: File analysis results carry forward to plan and EPIC.
         When writing the plan document, include a "Data Profile" or "Input Files"
         subsection summarizing the analyzed files if they influenced the design.
```

### Approach-Informed Knowledge Search (Step 3 Integration)

Before proposing approaches, search for relevant knowledge that can inform the proposals
with documentation-backed evidence and lessons from past projects.

```
WHEN: Step 3 (Approach Exploration), after gathering enough context but before presenting approaches.

IF mem_config.knowledge.enabled:
  FOR EACH approach being considered:
    approach_query = "{approach keywords} {relevant framework or technology}"

    results = knowledge_find(
      query = approach_query,
      filters = { types: ["documentation", "pattern", "lesson"] }
    )
    TIMEOUT: 5 seconds per query. If slow, skip that query.

    IF results (non-empty):
      Inform the approach's pros/cons with knowledge-backed evidence:
        - Add "[Knowledge]" label to pros/cons items that come from stored knowledge
        - Reference specific documentation when recommending a pattern
        - Surface lessons learned (both positive and negative) from past projects
        - Include framework version context when relevant

  Example output:
    Approach A: JWT Authentication with FastAPI OAuth2
      Pros:
        - [Knowledge] FastAPI docs recommend OAuth2PasswordBearer for simple auth (v0.115.x)
        - [Knowledge] Project crm-backend used this pattern successfully (2026-01)
        - Standard, well-supported approach
      Cons:
        - [Knowledge] Lesson from invoice-api: token refresh requires careful CORS config
        - Requires secure token storage on client side

IF mem_config missing OR knowledge.enabled == false OR knowledge unavailable:
  -> Skip silently. Propose approaches based on general knowledge only.
  -> Output is identical to pre-knowledge brainstorming behavior.
```

### Example EPIC Lookup (Step 3 Integration)

After the approach-informed knowledge search, search for community example EPICs that match
the PM's topic and selected approach. Example EPICs offer a concrete, pre-validated starting
point that PM can adapt to the current project or use as inspiration.

When `workflow_detected == true` and WF7 has produced a platform recommendation, the lookup
prioritizes workflow-related and platform-specific examples. This cross-reference ensures that
the best-matching example reflects both the PM's topic and the recommended platform.

```
WHEN: Step 3 (Approach Exploration), after approach-informed knowledge search, before presenting approaches.
RUNS AFTER: WF7 Platform Recommendation (if workflow_detected == true).

topic       = PM's stated topic or idea
tech_stack  = project-profile.yaml -> tech_stack.frameworks (list)
profile     = project-profile.yaml (full: paths, versions, docker, conventions)

# Workflow context — enriches the search when a workflow project is detected.
IF workflow_detected == true:
  platform_hint  = from Platform Detection Protocol (e.g., langchain, n8n, null)
  wf7_platform   = from WF7 recommendation (e.g., "LangGraph", "N8N", null)
ELSE:
  platform_hint  = null
  wf7_platform   = null

--- SOURCE 1: Static files in defaults/examples/ ---

examples_static = []

IF defaults/examples/ directory does NOT exist OR is empty:
  -> Skip SOURCE 1 silently. No error, no log, no message to PM.
  -> Proceed to SOURCE 2.
ELSE:
  FOR EACH file IN defaults/examples/**/*.md:
    frontmatter = parse_frontmatter(file)
    # Expected frontmatter fields: type, archetype, frameworks, platforms,
    #   ui, complexity, description
    IF frontmatter.type != "example":
      SKIP file

    score = 0

    # Primary match: topic keywords against description and archetype
    IF topic keywords overlap frontmatter.description OR frontmatter.archetype:
      score += 3

    # Framework match: project tech stack against example frameworks
    IF any(fw IN frontmatter.frameworks for fw IN tech_stack):
      score += 2

    # Platform match (workflow projects): platform_hint or WF7 recommendation
    IF platform_hint != null AND frontmatter.platforms (non-empty):
      IF platform_hint IN frontmatter.platforms:
        score += 2
      ELIF wf7_platform != null AND wf7_platform IN frontmatter.platforms:
        score += 2

    # Complexity match: project complexity signal against example complexity
    IF frontmatter.complexity is set:
      # complexity values: simple, moderate, complex
      # Prefer examples whose complexity matches the project signal from Step 2 answers
      IF project_complexity_signal matches frontmatter.complexity:
        score += 1

    # UI match: project UI type against example UI type
    IF frontmatter.ui is set AND project has UI requirements from Step 2:
      IF frontmatter.ui matches project_ui_type:
        score += 1

    IF score > 0:
      examples_static.APPEND({ file, score })

  # Sort static examples by score descending — best match first
  examples_static.SORT(by = score, descending)

--- SOURCE 2: Qdrant example_epic (if available) ---

examples_qdrant = []
IF mem_config.knowledge.enabled:
  # Build query — include platform context for workflow projects
  query_parts = [topic, tech_stack frameworks joined]
  IF platform_hint != null:
    query_parts.APPEND(platform_hint)
  IF wf7_platform != null AND wf7_platform != platform_hint:
    query_parts.APPEND(wf7_platform)
  query = " ".join(query_parts)

  examples_qdrant = memory_find(
    query  = query,
    filter = { type: "example_epic" },
    min_score = 0.4
  )
  TIMEOUT: 5 seconds. If slow, skip silently.

--- MERGE AND DEDUPLICATE ---

all_examples = examples_static + examples_qdrant
deduplicated = {}
FOR EACH ex IN all_examples:
  archetype = ex.frontmatter.archetype OR ex.metadata.archetype
  IF archetype NOT IN deduplicated:
    deduplicated[archetype] = ex           # first seen wins (static file preferred)
  ELIF ex is from examples_static AND deduplicated[archetype] is from examples_qdrant:
    deduplicated[archetype] = ex           # static file overrides Qdrant on conflict

top_examples = first 3 of deduplicated.values()

--- PRESENT TO PM (if results found) ---

IF top_examples (non-empty):
  Display to PM (ONE message, non-blocking):
    "I found an example EPIC for {top_examples[0].archetype}."
    "Use as inspiration? (A) Adapt to your project  (B) Browse all examples  (C) Start fresh"

  IF PM selects (A):
    chosen = top_examples[0]
    adapt_example(chosen, profile)   # defined in knowledge-acquisition.md
    -> adapt_example() adapts the example to the current project using project-profile.yaml:
         1. Path placeholders: replaces generic paths (e.g., src/, app/) with
            project-profile.yaml -> project_structure paths.
         2. Framework versions: updates framework references to match
            project-profile.yaml -> tech_stack.frameworks (name + version).
         3. Docker configuration: if docker_recommended == true, retains or adds
            Docker Compose sections using project-profile.yaml -> docker config.
            If docker_recommended == false, removes Docker Compose sections.
         4. Platform alignment (workflow projects): if workflow_detected == true,
            ensures the example's platform references match the WF7 recommendation.
         5. Project-specific constraints: merges constraints from
            project-profile.yaml -> conventions and PM's Step 2 answers.
         6. Step count: asks PM about desired step count and adjusts.
         7. Writes the adapted EPIC to .aid-o/02-epics/ after PM approval.
    -> After adaptation, continue brainstorming normally (PM can still refine).

  IF PM selects (B):
    List ALL available examples (all_examples, not just top 3):
      FOR EACH ex IN all_examples:
        "- [{ex.archetype}] {ex.description}  ({ex.frameworks joined})"
    Ask: "Which would you like to use? Enter archetype name or (C) to skip."
    IF PM picks one:
      chosen = that example
      adapt_example(chosen, profile)
      -> Continue brainstorming normally after adaptation.
    IF PM enters (C) or skips:
      -> Continue normal brainstorming.

  IF PM selects (C):
    -> Skip silently. Continue normal brainstorming.

IF top_examples (empty) OR examples search unavailable:
  -> Skip silently. Continue normal brainstorming.
  -> No message shown to PM. Step 3 behavior is identical to Phase 1.
```

---

## Non-Blocking Guarantee

```
RULE 1: All knowledge_find() calls use a 5-second timeout.
        If the call does not return within 5 seconds, discard it and proceed.
RULE 2: Knowledge retrieval failures are NEVER shown to PM as errors.
        No "knowledge unavailable" messages, no degraded UX indicators.
RULE 3: When knowledge is unavailable, brainstorming works exactly as before.
        The run is identical to a non-knowledge-augmented run.
RULE 4: Knowledge informs but never overrides PM input.
        If PM contradicts a past decision or known pattern, follow PM's direction.
RULE 5: Knowledge calls happen at most three times per run:
        (1) Step 1 pre-brainstorming search, (2) Step 3 approach-informed knowledge search,
        (3) Step 3 example EPIC lookup.
        No additional calls during questioning, design validation, or document generation.
RULE 6: File scan (.aid-o/05-inputs/) uses a 10-second total timeout.
        If scanning and analysis exceed 10 seconds, present partial results and proceed.
RULE 7: File scan failures are NEVER shown to PM as errors.
        Missing directory, empty directory, unreadable files — all handled silently.
        Individual file analysis failures are noted in the summary as "unable to analyze"
        but do not block the run.
RULE 8: File analysis from PM-provided paths follows the same non-blocking guarantee.
        If a PM-provided file cannot be read, inform PM briefly and continue.
```

## Graceful Degradation Scenarios

| Scenario | Behavior |
|----------|----------|
| `memory-config.yaml` missing | Skip all knowledge calls. Brainstorm normally. |
| `knowledge.enabled: false` | Skip all knowledge calls. Brainstorm normally. |
| Qdrant MCP unavailable | `knowledge_find()` returns empty. Brainstorm normally. |
| `knowledge_find()` times out (>5s) | Discard result. Brainstorm normally. |
| `knowledge_find()` returns empty | Display "No knowledge indexed yet" to PM (Step 1). Brainstorm normally. |
| Partial results (Step 1 works, Step 3 times out) | Use Step 1 results, skip Step 3 enrichment. |
| `defaults/examples/` directory missing | Skip static example lookup silently. Qdrant lookup still runs (if enabled). |
| `defaults/examples/` directory empty | Skip static example lookup silently. Qdrant lookup still runs (if enabled). |
| `defaults/examples/` has no keyword or framework matches | No example offered. Continue brainstorming normally. |
| `workflow_detected == true` but no platform-specific examples found | Fall back to topic/framework matching only. Platform hint does not filter out results — it only boosts score. |
| Qdrant example_epic search times out (>5s) | Discard Qdrant results. Static file results still used (if any). |
| Qdrant example_epic returns empty, static files found | Present static file examples only. |
| Static files found, Qdrant returns results for same archetype | Static file takes precedence (deduplication rule). |
| PM selects (C) Start fresh at example prompt | Skip silently. Continue normal brainstorming. No record kept. |
| No examples found from either source | Skip silently. Step 3 identical to Phase 1 behavior. |
| `.aid-o/05-inputs/` directory missing | Skip file scan silently. Do not create directory. No message to PM. |
| `.aid-o/05-inputs/` directory empty | Skip file scan silently. No message to PM. |
| File in `.aid-o/05-inputs/` unreadable | Note "unable to analyze" for that file. Continue with remaining files. |
| File scan exceeds 10-second timeout | Present partial results for files analyzed so far. Continue to Step 2. |
| More than 10 files in `.aid-o/05-inputs/` | Analyze first 10 (alphabetical). Note remaining count to PM. |
| PM-provided file path does not exist | Inform PM briefly ("File not found: {path}"). Continue run. |
| PM-provided file cannot be parsed | Note "unable to analyze" to PM. Continue run. |

In every degradation scenario, PM sees no difference from a standard brainstorming run.
The knowledge and file analysis layers are invisible when they have nothing to contribute.

---

## Reference Files

- `skills/brainstorming.md` — parent skill (core process rules and protocols)
- `skills/brainstorming-workflow.md` — workflow detection and Docker/MCP sub-skill
- `skills/knowledge-acquisition.md` — knowledge pipeline: `knowledge_find()`, `find_relevant_examples()`, and `adapt_example()`
- `defaults/examples/` — community example EPICs (static files) for Step 3 example lookup
- `.aid-o/05-inputs/` — sample data directory auto-scanned in Step 1

---

**Last Updated:** 2026-02-27
