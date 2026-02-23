# Brainstorming — Interactive Design and Planning Skill

**Version:** 0.6.0
**Skill:** brainstorming
**Dependencies:** session-management, planner, workflow-intelligence
**Attribution:** Inspired by [superpowers:brainstorming](https://github.com/jessevincent/claude-superpowers) (MIT License, Jesse Vincent)

---

## TL;DR

This skill defines how AID conducts interactive brainstorming sessions with the PM. It governs the questioning protocol, approach exploration, incremental design validation, plan document generation, and automatic EPIC draft creation. When knowledge acquisition is configured, brainstorming is augmented with relevant documentation, patterns, and lessons from past projects to inform questions (Step 1) and approach proposals (Step 3).

The brainstorming skill is invoked by the `/aid-brainstorm` command and produces two artifacts: a validated plan document and an EPIC draft ready for `/aid-plan-epic`.

**Input:** PM's idea or topic + interactive Q&A (+ knowledge context when available)
**Output:** Plan document (`.aid-o/01-plans/P-*.md`) + EPIC draft (`.aid-o/02-epics/E-*.md`)

---

## Key Principles

### 1. Detail by Default

Brainstorming produces **comprehensive, detailed output** without PM asking for it. This is the most important principle.

- Include specific field names, endpoint paths, error codes, data types
- Describe failure modes and edge cases proactively
- Propose concrete file structures and directory layouts
- Specify integration points with existing code (reference actual files when known)
- PM should never need to say "add more detail" — they can always say "simplify"
- When in doubt, be more specific rather than less

### 2. Explore Alternatives

Never present a single approach. Always offer 2-3 options with genuine tradeoffs.

- Each option must be a real alternative, not a strawman
- Clearly state the recommended option and why
- Include effort estimates (S/M/L) and risk assessments
- Acknowledge when all options have similar tradeoffs
- If PM asks "what do you recommend?", give a direct answer with reasoning

### 3. Incremental Validation

Validate the design with PM at every stage, not just at the end.

- Questions validate understanding before proposing solutions
- Approach selection validates direction before detailed design
- Section-by-section review validates details before committing to paper
- Final approval validates the whole before writing files
- Never write files without explicit PM approval

### 4. YAGNI (You Aren't Gonna Need It)

Propose the simplest solution that meets PM's stated requirements.

- Do not add features PM did not ask for
- Do not propose microservice architecture for a single-service problem
- Do not add caching layers, message queues, or event sourcing unless the requirements demand it
- If the scope is ambiguous, default to simpler and ask PM
- Complexity is a cost — justify every layer of indirection

### 5. PM Attention is the Bottleneck

Minimize cognitive load on PM. Every interaction should be easy to process.

- One question at a time (never batch)
- Multiple choice over open-ended (A/B/C options)
- Short summaries before detailed sections
- Clear action items: what does PM need to decide?
- Accept brief answers and infer reasonable defaults

---

## Knowledge-Augmented Brainstorming

When knowledge acquisition is configured, the brainstorming session is augmented with
relevant knowledge from past projects, stored documentation, patterns, and lessons learned.
This gives the brainstorming agent awareness of existing context before asking questions and
proposing approaches.

**Principle:** Knowledge retrieval is strictly non-blocking. It enriches the session when
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
    Display to PM:
      "Found relevant knowledge from past sessions:"
      FOR EACH result IN results:
        - "[{result.metadata.type}] {result summary}"
          "Source: {result.metadata.project_name OR result.metadata.framework} ({result.metadata.indexed_at})"

    Use results as context for questioning:
      - Skip questions whose answers are already known from past decisions
      - Ask more targeted questions informed by known patterns
      - Reference relevant documentation when framing options
      - Do NOT skip the questioning phase entirely -- past knowledge informs, not replaces

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
     → Analyze the first 10 (sorted alphabetically)
     → Note to PM: "...and {N} more files (not analyzed)"

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

4. Store analysis results in brainstorming session state for use in:
   - WF4 (Data & Inputs) question — reference analyzed files instead of asking
     PM to describe data from scratch (see "Workflow Question Inserts" → WF4)
   - Step 3 (Approaches) — inform architecture proposals with data
     characteristics (volume, format, schema complexity)
   - Plan document — include data profile in Constraints or Context section

5. Accept arbitrary file paths from PM during the session:
   - IF PM says "also look at ./data/customers.json" or provides any file path:
     → Read and analyze the file using the same type-detection logic above
     → Add to the stored analysis results
     → Present the single-file summary to PM
     → Do NOT copy the file to .aid-o/05-inputs/
     → Do NOT modify or move the original file
   - This can happen at any point in the session (not just Step 1)
```

#### File Analysis Rules

```
RULE F1: Directory .aid-o/05-inputs/ does not exist → skip silently.
         Do NOT create the directory. Do NOT mention it to PM.
RULE F2: Directory .aid-o/05-inputs/ is empty → skip silently.
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
         (PM explicitly chose these files). Added to session state incrementally.
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
  FOR EACH file IN defaults/examples/:
    frontmatter = parse_frontmatter(file)
    # Expected frontmatter fields: type, archetype, frameworks, platforms,
    #   ui, complexity, description
    IF frontmatter.type != "example_epic":
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

### Non-Blocking Guarantee

```
RULE 1: All knowledge_find() calls use a 5-second timeout.
        If the call does not return within 5 seconds, discard it and proceed.
RULE 2: Knowledge retrieval failures are NEVER shown to PM as errors.
        No "knowledge unavailable" messages, no degraded UX indicators.
RULE 3: When knowledge is unavailable, brainstorming works exactly as before.
        The session is identical to a non-knowledge-augmented session.
RULE 4: Knowledge informs but never overrides PM input.
        If PM contradicts a past decision or known pattern, follow PM's direction.
RULE 5: Knowledge calls happen at most three times per session:
        (1) Step 1 pre-brainstorming search, (2) Step 3 approach-informed knowledge search,
        (3) Step 3 example EPIC lookup.
        No additional calls during questioning, design validation, or document generation.
RULE 6: File scan (.aid-o/05-inputs/) uses a 10-second total timeout.
        If scanning and analysis exceed 10 seconds, present partial results and proceed.
RULE 7: File scan failures are NEVER shown to PM as errors.
        Missing directory, empty directory, unreadable files — all handled silently.
        Individual file analysis failures are noted in the summary as "unable to analyze"
        but do not block the session.
RULE 8: File analysis from PM-provided paths follows the same non-blocking guarantee.
        If a PM-provided file cannot be read, inform PM briefly and continue.
```

### Graceful Degradation Scenarios

| Scenario | Behavior |
|----------|----------|
| `memory-config.yaml` missing | Skip all knowledge calls. Brainstorm normally. |
| `knowledge.enabled: false` | Skip all knowledge calls. Brainstorm normally. |
| Qdrant MCP unavailable | `knowledge_find()` returns empty. Brainstorm normally. |
| `knowledge_find()` times out (>5s) | Discard result. Brainstorm normally. |
| `knowledge_find()` returns empty | No knowledge displayed. Brainstorm normally. |
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
| PM-provided file path does not exist | Inform PM briefly ("File not found: {path}"). Continue session. |
| PM-provided file cannot be parsed | Note "unable to analyze" to PM. Continue session. |

In every degradation scenario, PM sees no difference from a standard brainstorming session.
The knowledge and file analysis layers are invisible when they have nothing to contribute.

---

## Workflow Detection Integration

When a workflow/agent project is detected, the brainstorming session is supplemented with
workflow-specific questioning and platform recommendation. Detection runs automatically
before the first question. Non-workflow projects are completely unaffected.

**Principle:** Workflow detection is non-blocking and backward-compatible. When no workflow
is detected, the brainstorming session proceeds identically to its behavior before this
integration existed.

For full protocol details, see `skills/workflow-intelligence.md`.

### Platform Detection (Step 2, Before First Question)

After the Pre-Brainstorming Knowledge Search (Step 1 Integration) completes and before
the first question is asked, run the Platform Detection Protocol.

```
WHEN: Step 2 (Questions), BEFORE the first question, AFTER Step 1 context gathering.

1. Run Platform Detection Protocol from workflow-intelligence.md:
   - Scan PM's topic for workflow keywords:
     agent, chatbot, RAG, workflow, pipeline, automation,
     LangChain, LangGraph, N8N, LangFlow, multi-agent,
     AI workflow, LLM agent, tool-calling, assistant
   - Check project-profile.yaml -> tech_stack.frameworks for platform matches
   - Check PM's explicit mentions during conversation
   - Determine detection result:
       workflow_detected: true | false
       platform_hint: langchain | langgraph | n8n | langflow | generic-workflow | null
       platform_confidence: high | medium | low

2. IF workflow_detected == true:
   - Inform PM (one line, non-blocking):
     "I detected this is a workflow/agent project ({platform_hint}).
      I'll include some workflow-specific questions alongside the standard ones."
   - Activate workflow question inserts for Step 2 (see below)
   - Activate WF7 platform recommendation for Step 2→3 transition

3. IF workflow_detected == false:
   - Say nothing. Standard brainstorming proceeds unchanged.
   - No workflow inserts activate. All downstream sections are skipped.
```

### Workflow Question Inserts (Step 2, Interleaved with Standard Questions)

When `workflow_detected == true`, workflow-specific questions (WF1-WF6) are inserted
at natural points in the standard questioning flow. Each insert follows naturally from
the preceding standard question's context. Inserts are supplements — standard questions
always run first.

See `skills/workflow-intelligence.md` -> Workflow Questioning Protocol for the full
question text, options, and follow-up logic for each insert.

```
STANDARD QUESTION        WORKFLOW INSERT (only if workflow_detected == true)
════════════════════     ════════════════════════════════════════════════════

After Scope question  →  + WF1: PURPOSE
                           "What should the agent/workflow do specifically?"
                           Follow-up: example scenario (user does X, agent returns Y)

After Users question  →  + WF2: INTERACTION MODEL
                           "How will users communicate with the agent/workflow?"
                           Options: Chat / Upload & Process / Trigger-based /
                                    Dashboard / Combination

                      →  + WF3: OUTPUT
                           "What is the output? What does the user get?"
                           Options: Text / Structured data / Action / File / Combination

                      →  + WF4: DATA & INPUTS
                           Uses results from Sample File Analysis (Step 1).
                           If files were analyzed, reference them:
                             "I found data.csv (1,240 rows) and config.json
                              in your inputs. What other data will the
                              workflow process?"
                           If no files were analyzed, ask from scratch:
                             "What data will the workflow process?"
                           Probe: type, volume, format.

After Constraints     →  + WF5: TOOLS & INTEGRATIONS
  question                "What external services or tools will the workflow connect to?"
                           Options: None / External APIs / Database /
                                    Cloud services / Other LLM/AI services
                           Derives MCP server recommendations from answer.

After Success         →  + WF6: USABILITY SUCCESS
  question                "Do agent decisions need to be explainable?"
                           Follow-up: human-in-the-loop requirement check.
```

```
WORKFLOW INSERT RULES:
  RULE 1: Each insert = max 1 question + max 1 follow-up.
  RULE 2: If the standard question already covered a workflow aspect, skip
          the corresponding insert (no redundancy).
  RULE 3: Total question count: standard (3-7) + workflow inserts (3-5) = max 12.
          WF7 does not count as a question.
  RULE 4: Transitions must be smooth — no abrupt topic changes.
          Each insert follows naturally from its standard question context.
  RULE 5: .aid-o/05-inputs/ scan happens in Step 1 (see "Sample File Analysis"
          in Knowledge-Augmented Brainstorming). Results are available to WF4.
```

### WF7 Platform Recommendation (Step 2 to Step 3 Transition)

After all questions are answered (standard + workflow inserts), before transitioning
to Step 3 (Approaches), run the WF7 Platform Recommendation.

WF7 is NOT a question — AID decides and presents the recommendation. PM can override.

```
WHEN: After the last question is answered, before Step 3 (Approaches).
CONDITION: workflow_detected == true.

1. Run WF7 Platform Recommendation Logic from workflow-intelligence.md:
   - IF platform_hint is exact (langchain/langgraph/n8n/langflow):
     → Confirm the detected platform to PM.
   - IF platform_hint == generic-workflow:
     → AID decides based on complexity signals collected from WF1-WF6 answers.
     → complex_signals >= 3 → recommend LangChain/LangGraph (code-first)
     → complex_signals < 3  → recommend N8N or LangFlow (visual/low-code)

2. Present recommendation to PM (one message):
   "Platform Recommendation
    ====================================
    Recommended: {recommended}
      Reason: {reason}
    Alternative: {alternative}
      Available if you prefer more {control | simplicity}.
    I'll include both variants in the approach proposals (Step 3)."

3. PM can override by stating a preference — follow PM's choice.

4. ALWAYS offer both platform variants in Step 3 approaches.
```

### Workflow-Aware Approaches (Step 3 Integration)

When `workflow_detected == true`, the Approach Exploration Protocol gains additional
requirements for how approaches are structured.

```
WHEN: Step 3 (Approaches), when workflow_detected == true.

ADDITIONAL RULES (supplement the standard Approach Exploration Protocol):

  RULE W1: ALWAYS include both platform variants as separate approaches.
           - Approach A: Recommended platform ({recommended_platform})
           - Approach B: Alternative platform ({alternative_platform})
           - Additional non-platform approaches may be added if genuinely different.

  RULE W2: Each platform approach uses platform-specific architecture from
           workflow-intelligence.md -> Platform-Specific Knowledge.
           - Architecture diagrams follow platform patterns.
           - Docker Compose templates use platform-specific templates.
           - Key files to generate follow platform conventions.

  RULE W3: UI derivation from workflow-intelligence.md -> UI Derivation Logic
           informs the frontend architecture of each approach.
           - Cross-reference WF2 (interaction model) and WF3 (output type)
             against the UI Derivation Table.
           - Include derived UI type and React components (if applicable).

  RULE W4: Knowledge enrichment from workflow-intelligence.md ->
           Knowledge Enrichment Flow informs approach pros/cons.
           - Add [Knowledge] or [Docs] labels where evidence is available.

  RULE W5: Standard approach rules still apply (pros, cons, effort, risk).
           Workflow rules are additions, not replacements.
```

---

## Docker/MCP Preference Rules

These rules are **cross-cutting** and apply to ALL projects, regardless of type. When
`workflow_detected == true`, the rules below are amplified by `skills/workflow-intelligence.md`
(Docker STRONGLY recommended, MCP servers for agent tools). For non-workflow projects the
same rules still apply based on service count, external dependencies, and reproducibility needs.

**Principle:** Docker and MCP recommendations are always presented as suggestions. PM has
final authority. Once PM declines, the topic is closed for the remainder of the session.

### Docker Preference Rules

```
RULE D1: 2+ services → Docker Compose recommended.
         "Services" includes: application server, database, cache, message queue,
         vector store, search engine, or any process that runs independently.

RULE D2: External dependencies (DB, cache, vector store) → Docker recommended.
         Even a single-service app benefits from Docker when it depends on
         infrastructure that varies across developer machines.

RULE D3: Reproducibility important (team project, CI/CD) → Docker recommended.
         If the project will be developed by more than one person, or if it uses
         CI/CD pipelines, Docker Compose ensures consistent environments.

RULE D4: Workflow/agent project → Docker STRONGLY recommended.
         Amplified by workflow-intelligence.md. Workflow projects almost always have
         2+ services (app + vector store, app + database, multi-agent containers).

EVALUATION ORDER:
  1. Check RULE D1 first (service count is the strongest signal).
  2. If D1 does not trigger, check D2 (external dependencies).
  3. If D2 does not trigger, check D3 (reproducibility).
  4. D4 is an overlay — it elevates "recommended" to "STRONGLY recommended"
     when workflow_detected == true, but it never triggers on its own.
  5. If no rule triggers → Docker is NOT recommended. Do not mention it.
```

### Docker in Step 3 (Approaches)

```
WHEN: Step 3 (Approaches), BEFORE presenting approaches to PM.

1. Analyze project requirements from Step 2 answers:
   - Count services needed (app, database, cache, vector store, etc.)
   - Identify external dependencies (third-party APIs, managed services)
   - Check if workflow_detected == true
   - Check if team_size > 1 or CI/CD is mentioned

2. Apply Docker Preference Rules (D1-D4):
   → docker_recommended = true | false
   → docker_strength = "recommended" | "strongly recommended"

3. IF docker_recommended:
   - Every approach includes Docker Compose as part of its architecture section.
   - The planner adds a "Docker Compose setup" step in the plan
     (after architect, before backend implementation).
   - Ask PM ONCE (before presenting approaches):
     "I recommend Docker Compose for this project ({reason}).
      Include in all approaches? (Y/N)"

   - IF PM says Y (or equivalent):
     → Proceed. Docker Compose is part of all approaches.

   - IF PM says N (or equivalent):
     → Record constraint: "PM decided: no Docker, local setup."
     → Remove Docker from all approaches.
     → Do not mention Docker again for this project.
     → Planner omits the Docker Compose step.

4. IF docker_recommended == false:
   - Do not mention Docker. No step, no compose, no question.
   - Docker is invisible in the session.
```

### MCP Server Preference Rules

```
RULE M1: Project uses database → Database MCP server recommended.
         (PostgreSQL MCP, MySQL MCP, SQLite MCP — match to the project's DB choice.)

RULE M2: Project has GitHub repository → GitHub MCP recommended.
         (For issue management, PR automation, code search during development.)

RULE M3: Project needs advanced file operations → Filesystem MCP recommended.
         (Bulk file manipulation, template generation, workspace scanning.)

RULE M4: Project needs web browsing or scraping → Playwright/Browser MCP recommended.
         (E2E testing, web scraping, page interaction.)

RULE M5: Project uses framework with docs on Context7 → Context7 MCP recommended.
         (Up-to-date framework documentation retrieval for agents.)

RULE M6: Workflow/agent project → MCP servers for agent tools.
         Amplified by workflow-intelligence.md. Specific MCP servers are derived from
         the WF5 (Tools & Integrations) answer during workflow questioning.

EVALUATION:
  - Apply each rule independently. Multiple rules can fire simultaneously.
  - Collect all recommendations into mcp_recommendations (list of MCP server names).
  - If no rule fires → mcp_recommendations is empty. Do not mention MCP.
```

### MCP + Docker Interaction

```
IF docker_recommended AND mcp_recommendations (non-empty):
  → Propose MCP servers INSIDE Docker Compose.
  → "MCP servers run in Docker containers alongside your application."
  → Docker Compose YAML includes MCP server service definitions.

IF docker_recommended == false AND mcp_recommendations (non-empty):
  → Propose MCP servers as local processes or configuration entries.
  → No Docker Compose involvement.

IF PM declines MCP:
  → Record constraint: "PM decided: no MCP servers, direct SDK/libraries."
  → Alternative: use native SDKs, client libraries, or direct API calls.
  → Do not mention MCP again for this project.

IF PM declines Docker but accepts MCP:
  → MCP servers run locally (not in containers).
  → Adjust setup instructions accordingly.
```

### Decision Matrix

```
┌──────────────────────────┬────────────────┬──────────────────┐
│ Situation                │ Docker         │ MCP servers      │
├──────────────────────────┼────────────────┼──────────────────┤
│ 1 service, no DB         │ —              │ —                │
│ 1 service + DB           │ recommended    │ DB MCP           │
│ 2+ services              │ recommended    │ as needed        │
│ 2+ services + DB + cache │ recommended    │ DB MCP + others  │
│ Workflow/agent project   │ STRONGLY rec.  │ STRONGLY rec.    │
│ Team project / CI/CD     │ recommended    │ as needed        │
│ PM declined Docker       │ —              │ as needed (local)│
│ PM declined MCP          │ as applicable  │ —                │
│ PM declined both         │ —              │ —                │
└──────────────────────────┴────────────────┴──────────────────┘

Legend:
  —           = not recommended / not mentioned
  recommended = suggested to PM, PM can decline
  STRONGLY    = suggested with emphasis, PM can still decline
  as needed   = only if specific rules (M1-M6) trigger
```

### Step 3 Integration (Docker/MCP Analysis)

```
WHEN: Step 3 (Approaches), BEFORE presenting approaches.
RUNS AFTER: Workflow Detection Integration (if applicable).
RUNS AFTER: Knowledge-Augmented Brainstorming Step 3 search (if applicable).
RUNS BEFORE: Approach presentation to PM.

PROCEDURE:

1. Analyze project requirements from Step 2 answers:
   - service_count = count of distinct services (app, DB, cache, vector store, queue, etc.)
   - external_deps = list of external dependencies (databases, caches, APIs)
   - workflow_detected = from Platform Detection Protocol (true/false)
   - team_project = true if PM mentioned team, CI/CD, or collaboration
   - pm_constraints = any constraints PM already stated

2. Apply Docker Preference Rules:
   docker_recommended = false
   docker_strength = null

   IF service_count >= 2:
     docker_recommended = true; docker_strength = "recommended"    # D1
   ELIF external_deps (non-empty):
     docker_recommended = true; docker_strength = "recommended"    # D2
   ELIF team_project:
     docker_recommended = true; docker_strength = "recommended"    # D3

   IF workflow_detected AND docker_recommended:
     docker_strength = "strongly recommended"                      # D4 overlay

   IF workflow_detected AND NOT docker_recommended:
     # Workflow projects typically have external deps. Double-check.
     # If truly no external deps and single service, do NOT force Docker.
     pass

3. Apply MCP Preference Rules:
   mcp_recommendations = []

   IF project uses DB:           mcp_recommendations.append("{db_type} MCP")     # M1
   IF project has GitHub repo:   mcp_recommendations.append("GitHub MCP")        # M2
   IF needs file operations:     mcp_recommendations.append("Filesystem MCP")    # M3
   IF needs web browsing:        mcp_recommendations.append("Playwright MCP")    # M4
   IF uses known framework:      mcp_recommendations.append("Context7 MCP")      # M5
   IF workflow_detected:         mcp_recommendations += workflow_mcp_list         # M6

4. IF docker_recommended:
   Ask PM ONCE:
     "I recommend Docker Compose for this project ({docker_strength}: {reason}).
      Include in all approaches? (Y/N)"
   IF PM says N:
     record_constraint("PM decided: no Docker, local setup.")
     docker_recommended = false

5. IF mcp_recommendations (non-empty):
   Include MCP servers in approach architectures.
   IF docker_recommended:
     MCP servers are services inside Docker Compose.
   ELSE:
     MCP servers are local processes.

6. Proceed to approach presentation with docker and MCP decisions applied.
```

### PM Decline Handling

```
RULE: PM's decision on Docker/MCP is final and respected immediately.

IF PM declines Docker:
  1. Record constraint: "PM decided: no Docker, local setup."
  2. Remove Docker Compose from all approach architectures.
  3. Remove "Docker Compose setup" from planner steps.
  4. If MCP was recommended: MCP servers run locally (not in containers).
  5. Do not mention Docker again in this brainstorming session.
  6. Do not ask again, do not hint, do not include as "optional."

IF PM declines MCP:
  1. Record constraint: "PM decided: no MCP servers, direct SDK/libraries."
  2. Remove MCP server references from all approach architectures.
  3. Replace with native SDK/library alternatives where applicable.
  4. Do not mention MCP again in this brainstorming session.

IF PM declines both:
  1. Record both constraints.
  2. Approaches use local setup with direct dependencies.
  3. Session proceeds as if Docker/MCP rules do not exist.

CONSTRAINT RECORDING:
  Constraints are stored in the brainstorming session state and carry forward to:
  - Plan document (Constraints section)
  - EPIC draft (Constraints section)
  - Planner step generation (omit Docker/MCP steps)
```

---

## Process Rules

### Questioning Protocol

```
RULE 1: ONE question at a time. Never ask 2+ questions in one message.
RULE 2: Prefer MULTIPLE CHOICE (A/B/C). Open-ended only when options are unknowable.
RULE 3: After each answer, ACKNOWLEDGE and SUMMARIZE before next question.
RULE 4: 3-7 questions total. Stop when you can propose approaches.
RULE 5: If PM gives a short answer, INFER defaults and CONFIRM:
        "I'll assume {default} — correct?"
RULE 6: If PM says "you decide" or "whatever you think", make a decision
        and state it clearly: "I'll go with X because {reason}."
RULE 7: Cover at least 3 of these categories: scope, users, constraints,
        patterns, scale, timeline, success criteria.
RULE 8: Questions must build on previous answers — no redundant questions.
RULE 9: When workflow_detected == true, interleave workflow inserts (WF1-WF6)
        at the points defined in "Workflow Question Inserts" above.
        Total questions (standard + workflow) must not exceed 12.
        See skills/workflow-intelligence.md for insert details.
```

### Approach Exploration Protocol

```
RULE 1: Always propose 2-3 approaches. Never propose just one.
RULE 2: Each approach must be genuinely different (not minor variations).
RULE 3: Every approach needs: name, summary, pros (3+), cons (2+), effort, risk.
RULE 4: State your recommendation explicitly with reasoning.
RULE 5: If PM modifies an approach, create a new combined option and confirm.
RULE 6: Never dismiss PM's suggestion — integrate it or explain why not.
RULE 7: If all approaches have similar tradeoffs, say so and explain what
        differentiates them (maintainability, performance, team familiarity, etc.).
RULE 8: When workflow_detected == true, apply "Workflow-Aware Approaches"
        rules (W1-W5) from the Workflow Detection Integration section.
        Both recommended and alternative platform variants are required.
```

### Design Validation Protocol

```
RULE 1: Present design sections ONE AT A TIME for approval.
RULE 2: Each section must be self-contained (readable without other sections).
RULE 3: Track approval status visually ([x] approved, [ ] pending, [~] modified).
RULE 4: If PM modifies a section, re-present the modified version for re-approval.
RULE 5: If a modification in one section affects another, flag the dependency:
        "This change also affects {other section} — I'll update that when we get there."
RULE 6: "Skip" means PM wants to review later — include in final review.
RULE 7: After all sections: present summary with statuses, ask for final approval.
```

### Document Generation Protocol

```
RULE 1: NEVER write files without explicit PM approval (Step 6 in command flow).
RULE 2: Plan document follows the plan template structure exactly.
RULE 3: EPIC draft follows the EPIC template structure exactly.
RULE 4: Include all design details from the approved sections — do not summarize
        or omit details that were approved.
RULE 5: If PM approved a modification, the modified version goes into the document
        (not the original).
RULE 6: Generate proper IDs (P-{YYYYMMDD}-{hash}, E-{YYYYMMDD}-{hash}).
RULE 7: Cross-reference: EPIC draft references the plan in its Context section.
```

---

## Language Handling

Brainstorming involves two language contexts that must be kept separate:

### Conversation Language

The conversation with PM **always follows PM's language**. Detect from PM's first message.

- If PM writes in Czech, respond in Czech
- If PM writes in English, respond in English
- If PM switches language mid-conversation, follow the switch
- Multiple-choice options use PM's language
- Summaries and status updates use PM's language

### Document Language

Output documents (plan, EPIC) follow the **configured document language**.

```
Resolution order:
1. Read .aid-o/03-config/language.yaml → document_language
2. Check scope flags:
   - scope.plans: true → plan document uses document_language
   - scope.plans: false → plan document uses English
3. If language.yaml does not exist → use English (EN)
4. If document_language is unsupported → use fallback_language from config
```

### Language Configuration Reference

```yaml
# .aid-o/03-config/language.yaml
language:
  document_language: "EN"                 # ISO 639-1 code for generated documents
  fallback_language: "EN"                 # Fallback if primary language is unsupported
  scope:
    plans: true                           # EPIC plans and step descriptions
    reports: true                         # PM reports and status summaries
    gate_reviews: true                    # Quality gate review narratives
    lessons_learned: true                 # Lessons-learned entries
    commit_messages: false                # Git commit messages (false = always English)
    code_comments: false                  # Inline code comments (false = always English)
```

### Practical Examples

| PM Language | document_language | Plan Written In | Conversation In |
|-------------|-------------------|-----------------|-----------------|
| Czech | CS | Czech | Czech |
| Czech | EN | English | Czech |
| English | EN | English | English |
| English | CS | Czech | English |
| German | EN | English | German |

**Key rule:** The language split is invisible to PM. They talk naturally, documents come out in the configured language. If these differ, mention it once at the start: "I'll respond in {PM language}, but the plan document will be written in {document language} per your configuration."

---

## EPIC Subagent Prompt Template

This template is used in Step 8 of `/aid-brainstorm` to auto-generate an EPIC draft from the approved plan. The brainstorming agent uses this template to construct an internal prompt that generates a well-formed EPIC.

### Template

```markdown
You are an EPIC authoring agent. Your task is to convert an approved brainstorming
plan into a well-formed EPIC specification that the AID Orchestrator can process
through /aid-plan-epic and /aid-run-epic.

## Input

### Approved Plan
{plan_content}

### Project Profile
{project_profile_yaml}

### EPIC Template
{epic_template}

### Document Language
{document_language}

## Instructions

1. Read the approved plan carefully. Every design decision in the plan is final —
   do not re-evaluate or change approaches.

2. Generate an EPIC following the template structure exactly. Fill all sections:

   ### Frontmatter
   - Set `plan_ref: {plan_filename}` (the source plan's filename, e.g., `P-20260219-task-mgmt.md`)
   - Set `plan_epics_total: 1` (or as specified in plan)
   - Set `sessions_total:` based on Session Breakdown rules

   ### Context
   - Reference the plan: "This EPIC implements Plan P-{plan_id}."
   - Summarize the problem and chosen approach from the plan.

   ### Goal
   - 1-3 sentences. Specific and testable.
   - Derived from the plan's Goal and Success Criteria.

   ### Scope
   - **Allowed files/paths:** Derive from plan's Implementation Plan.
     Use project-profile.yaml to infer correct directory structure.
     Be specific (e.g., `backend/app/tasks/` not just `backend/`).
   - **Forbidden zones:** Infer from project structure.
     Shared infrastructure, other bounded contexts, core modules.

   ### Artifacts
   - List concrete deliverables from ALL plan tasks/steps (not just high-level).
   - Type each artifact: endpoint:, model:, component:, config:, doc:
   - Include specific file paths from the plan where mentioned.

   ### Constraints
   - Copy from plan's Constraints section.
   - Add budget estimate based on step count:
     Steps 1-5: $15, Steps 6-9: $25, Steps 10+: $40

   ### DoD Gates
   - Default: tests_pass, lint_pass, security_scan_pass, docs_updated
   - Add type_check if TypeScript detected in project-profile.yaml
   - Add build_pass if frontend build detected in project-profile.yaml

   ### Acceptance Criteria
   - Expand plan's Success Criteria into specific, testable checkboxes.
   - Each criterion must be verifiable from code/tests/docs.
   - Minimum 5 criteria, maximum 15.
   - Format: "- [ ] {specific testable statement}"

   ### Dependencies
   - From plan's Constraints + project context.
   - List external services, other EPICs, or libraries needed.

   ### Steps (Role Pipeline)
   - Map ALL plan tasks to AID roles (each plan task = one EPIC step):
   - Preserve plan Task IDs in objective field (e.g., "Add gitignore (Plan: Task A)")
   - The source plan's implementation detail for each task is accessed via plan_ref
     during execution — the EPIC step is a structured summary, not a replacement.
   - Map roles using this table:
     | Plan Step Category | AID Role |
     |--------------------|----------|
     | Design, architecture, contracts | architect |
     | Domain model, entities, rules | domain |
     | Server-side, API, database | backend |
     | UI, components, client-side | frontend |
     | Tests, coverage | qa |
     | Security review, auth | security |
     | Logging, metrics, tracing | observability |
     | Documentation, changelog | docs |
     | Deployment, versioning | release |
   - Respect dependency order:
     architect first, domain second, impl parallel, verification parallel, docs, release last.
   - Assign parallel groups where possible (backend+frontend, qa+security+observability).
   - YAGNI: only include roles the plan requires. If no frontend work, omit frontend role.

   ### Session Breakdown
   - Steps 1-6: "single orchestrated run"
   - Steps 7-9: "consider 2 sessions"
   - Steps 10+: "recommend session split" with suggested grouping

3. Write in {document_language} language. Technical terms (API, REST, SQL, etc.)
   remain in English regardless of document language.

4. Apply YAGNI: do not add steps, roles, or constraints the plan does not require.
   If the plan describes a simple feature, the EPIC should be simple.

5. IMPORTANT — Zero Detail Loss (Variant B):
   The EPIC does NOT replace the source plan. It adds structure (roles, deps, gates, AC)
   on top of the plan's implementation detail. The plan_ref field ensures agents can
   always access the full plan. Do NOT try to compress all plan detail into the EPIC —
   instead, create a well-structured specification that references the plan.

6. Cross-reference the plan in the EPIC's Context section.

## Output Format

Output ONLY the EPIC markdown content, starting with the `# EPIC:` header.
Do not include any explanation or commentary outside the EPIC document.
```

### Template Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `{plan_content}` | Plan file from Step 7 | Full markdown content of the approved plan |
| `{project_profile_yaml}` | `.aid-o/04-engine/memory/project-profile.yaml` | Project tech stack, structure, conventions |
| `{epic_template}` | `.aid-o/03-config/templates/epic.md` | EPIC template structure |
| `{document_language}` | `.aid-o/03-config/language.yaml` → `document_language` | ISO 639-1 language code |
| `{plan_id}` | Generated in Step 7 | Plan ID (e.g., `P-20260218-a3f2`) |

### Role Mapping Rules

The EPIC subagent maps plan steps to AID roles using these rules:

```
1. KEYWORD MATCHING (primary):
   - "design", "architecture", "contract", "ADR" → architect
   - "domain", "entity", "model", "invariant", "business rule" → domain
   - "API", "endpoint", "server", "database", "migration", "service" → backend
   - "UI", "component", "page", "frontend", "client" → frontend
   - "test", "coverage", "QA", "integration test" → qa
   - "security", "auth", "RBAC", "vulnerability", "scan" → security
   - "logging", "metrics", "tracing", "monitoring", "health check" → observability
   - "documentation", "changelog", "API docs", "guide" → docs
   - "deploy", "release", "version", "CI/CD" → release

2. DEPENDENCY INFERENCE (secondary):
   - architect has no dependencies (always first)
   - domain depends on architect (needs contracts)
   - backend depends on domain or architect
   - frontend depends on architect (needs contracts)
   - qa depends on backend and/or frontend (needs implementation)
   - security depends on backend (needs code to review)
   - observability depends on backend (needs endpoints to instrument)
   - docs depends on backend and frontend (needs implementation to document)
   - release depends on qa and security (needs verification)

3. PARALLEL GROUP ASSIGNMENT:
   - backend + frontend → same parallel group (both depend on contracts)
   - qa + security + observability → same parallel group (all depend on impl)
   - docs + release → same parallel group only if no dependency between them
```

### Phase Selection

When generating an EPIC from a plan, the brainstorming handoff (Step 10) determines the scope:

**All phases (Option B — default):**
- Include ALL High-Level Steps from the plan in the EPIC
- No special handling needed — standard EPIC generation

**Specific phase (Option C):**
- Only include steps from the selected phase
- Set frontmatter: `plan_epics_total: {total_phase_count}`
- Restrict `Allowed files/paths` to files relevant to this phase only
- In `## Dependencies`, list steps from OTHER phases that this phase depends on as external dependencies
- Add to `## Context`: "This EPIC covers Phase {N} of {total} from plan {plan_id}. External dependencies from other phases are listed but not executed in this EPIC."
- EPIC filename includes phase: `E-{YYYYMMDD}-{hash}-{topic}-phase-{N}.md`

---

## Brainstorming Session Lifecycle

### Starting a Brainstorming Session

```
1. PM invokes /aid-brainstorm [topic]
2. Read project context (Step 1 of command flow)
3. Enter questioning phase (Step 2)
4. Continue through Steps 3-9 per command flow
5. End with handoff (Step 9)
```

### Aborting a Brainstorming Session

PM can abort at any point by saying "stop", "cancel", "abort", or similar.

```
If abort BEFORE Step 7 (no files written):
  → Acknowledge, end gracefully. No files created.
  → "Brainstorming ended. No files were created. Run /aid-brainstorm to start again."

If abort DURING Step 7 (plan partially written):
  → Delete the partial plan file. No files remain.

If abort AFTER Step 7 but BEFORE Step 8:
  → Plan file exists. Ask PM: "Keep the plan file? (Y/N)"
  → If Y: keep plan, skip EPIC generation.
  → If N: delete plan file.

If abort AFTER Step 8:
  → Both files exist. Both are drafts. PM can edit or delete manually.
```

### Re-opening a Brainstorming Session

When PM selects Option A ("Add more items to plan") in Step 10:

1. **Load existing plan** — Read the plan file written in Step 7
2. **Display approved sections** — Show PM which sections were already approved (from Step 5)
3. **Return to Step 2** — Resume questioning with existing context loaded
   - The brainstorming context from Step 1 is still valid (project state hasn't changed)
   - Previous answers from Step 2 are retained as context
4. **New requirements ADD** — Never overwrite approved sections. New answers supplement existing ones:
   - New scope items are APPENDED to the scope list
   - New constraints are APPENDED
   - If PM wants to MODIFY an approved section, they must explicitly say so
5. **Re-present modified sections** — Only sections that changed go through Step 5 approval again
   - Unchanged sections remain approved
   - Modified sections require re-approval
6. **Re-write plan file** — Update the plan document with additions (Step 7)
7. **Re-generate EPIC draft** — Generate a new EPIC from the updated plan (Step 8)
8. **Return to Step 10** — Present handoff options again

**State management:** The brainstorming session maintains a list of approved sections and their content. When re-opening, this list is loaded to prevent re-asking about already-decided items.

**Abort during re-open:** If PM says "stop" or "cancel" during a re-open loop, the most recently written plan file is preserved. No rollback occurs.

### Transitioning to Execution

After brainstorming completes, two paths are available:

```
/aid-brainstorm → Plan + EPIC draft
    ├── (Y at Step 9) Direct pipeline:
    │     EPIC → Plan JSON + Session → ready for /aid-run-epic
    │
    └── (N at Step 9) Manual review:
          PM reviews EPIC draft → /aid-plan-epic → /aid-run-epic
```

Additionally, `/aid-plan-epic` accepts Plan files directly:

```
PM writes plan in .aid-o/01-plans/
    → /aid-plan-epic → auto-generates EPIC → Plan JSON + Session → /aid-run-epic
```

---

## Design Section Templates

When presenting design sections in Step 5, use these structures as guidance. Adapt based on the specific topic being brainstormed.

### Architecture Section

```
Architecture
====================================
Components:
  - {Component 1}: {responsibility}
  - {Component 2}: {responsibility}

Data Flow:
  {User/Client} → {Component 1} → {Component 2} → {Storage}

Integration Points:
  - {External service}: {how it connects}
  - {Existing module}: {dependency type}

Patterns:
  - {Pattern name}: {why it applies}
```

### Data Model Section

```
Data Model
====================================
Entities:
  {Entity 1}:
    - {field}: {type} {constraints}
    - {field}: {type} {constraints}
    Invariants: {business rules}

  {Entity 2}:
    - {field}: {type} {constraints}
    Relations: {Entity 1} → {Entity 2} (1:N)

Storage:
  - Database: {type}
  - Indexes: {fields for performance}
  - Migrations: {strategy}
```

### API Section

```
API Design
====================================
Base: /api/v1/{resource}

Endpoints:
  POST   /api/v1/{resource}      → 201 Created
  GET    /api/v1/{resource}      → 200 OK (paginated)
  GET    /api/v1/{resource}/{id} → 200 OK | 404 Not Found
  PATCH  /api/v1/{resource}/{id} → 200 OK | 404 Not Found
  DELETE /api/v1/{resource}/{id} → 204 No Content

Authentication: {method}
Error Format: { "error": "{code}", "message": "{detail}" }
Pagination: { "items": [...], "total": N, "page": N, "per_page": N }
```

---

## Common Brainstorming Patterns

### Pattern: New Feature in Existing Project

```
Questions focus on: integration with existing code, data model extension, UI placement
Approaches focus on: extend vs. new module, shared vs. isolated state
Design sections: Architecture (integration), Data Model (relations), API, Implementation
Roles typically: architect → domain → backend + frontend → qa + security → docs
```

### Pattern: Migration / Refactoring

```
Questions focus on: scope, backwards compatibility, rollback strategy, downtime tolerance
Approaches focus on: big-bang vs. incremental, strangler fig, blue-green
Design sections: Architecture (before/after), Migration Plan, Rollback, Testing
Roles typically: architect → backend → qa → security → docs → release
```

### Pattern: Infrastructure / DevOps

```
Questions focus on: scale requirements, existing infra, budget, team expertise
Approaches focus on: managed vs. self-hosted, tool selection, automation level
Design sections: Architecture (infra diagram), Configuration, Deployment, Monitoring
Roles typically: architect → backend → security → observability → docs → release
```

### Pattern: New Greenfield Project

```
Questions focus on: user needs, business model, MVP scope, team size
Approaches focus on: tech stack selection, architecture style, deployment target
Design sections: full Architecture, Data Model, API, Frontend, Testing, Infrastructure
Roles typically: all roles (architect → domain → backend + frontend → qa + security + observability → docs → release)
```

### Pattern: Workflow / Agent Project

```
Detection: Platform Detection Protocol activates workflow_detected == true
Questions focus on: standard categories + WF1-WF6 inserts (purpose, interaction model,
  output type, data/inputs, tools/integrations, usability success)
Approaches focus on: recommended platform vs. alternative platform (always two variants)
  + platform-specific architecture, Docker Compose, UI derivation
Design sections: Architecture (platform + Docker Compose), Data Model, API,
  UI (derived from interaction model + output type), Implementation (platform-specific tasks)
Roles typically: architect → domain → backend + frontend (if UI derived) → qa + security → docs → release
Additional outputs: platform recommendation (WF7), MCP server recommendations (from WF5),
  Docker Compose template, UI type and components
Reference: skills/workflow-intelligence.md for full protocol details
```

---

## MUST Rules

1. **ALWAYS ask one question at a time** — never batch multiple questions in one message
2. **ALWAYS prefer multiple choice** — open-ended only when options cannot be predicted
3. **ALWAYS provide detailed output by default** — PM should never ask for more detail
4. **ALWAYS propose 2-3 approaches** — never present a single option
5. **ALWAYS get section-by-section approval** — never skip incremental validation
6. **ALWAYS write files only after explicit PM approval** — Step 6 must be approved
7. **ALWAYS follow the language split** — conversation in PM language, documents in configured language
8. **ALWAYS apply YAGNI** — do not add complexity the requirements do not demand
9. **ALWAYS cross-reference** — EPIC references the plan, plan references the topic
10. **NEVER modify existing files** — brainstorming only creates new plan + EPIC files
11. **ALWAYS run Platform Detection Protocol before the first question** — when workflow is detected, inserts activate transparently; when not, brainstorming is unchanged
12. **NEVER exceed 12 total questions** — standard questions (3-7) plus workflow inserts (0-5) combined
13. **ALWAYS recommend Docker Compose when project has 2+ services** — PM can decline but recommendation is mandatory; applies to ALL project types, not just workflows
14. **NEVER mention Docker/MCP again after PM declines** — record as constraint once, respect PM's decision for the entire session, do not hint or include as optional

---

## Reference Files

- `commands/aid-brainstorm.md` — command that invokes this skill (9-step flow)
- `defaults/templates/plan.md` — plan document template
- `defaults/templates/epic.md` — EPIC template
- `defaults/templates/epic-example.md` — EPIC example for reference
- `skills/planner.md` — how plans become Plan JSON (downstream from brainstorming)
- `skills/session-management.md` — End of Brainstorming Protocol (lifecycle integration)
- `skills/knowledge-acquisition.md` — knowledge pipeline: `knowledge_find()`, `find_relevant_examples()`, and `adapt_example()` used in Steps 1 and 3
- `skills/workflow-intelligence.md` — Platform Detection Protocol, Workflow Questioning Protocol (WF1-WF7), UI Derivation Logic, platform-specific knowledge
- `defaults/examples/` — community example EPICs (static files) for Step 3 example lookup; directory may be empty or missing until Phase 2 (handled silently)
- `.aid-o/03-config/language.yaml` — document language configuration
- `.aid-o/05-inputs/` — sample data directory auto-scanned in Step 1 (all projects); results used by WF4 (workflow projects) and Step 3 (approaches)

---

**Version:** 0.6.0
**Last Updated:** 2026-02-23
