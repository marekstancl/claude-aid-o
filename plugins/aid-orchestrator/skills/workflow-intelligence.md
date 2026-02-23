# Workflow Intelligence — Platform Detection, Workflow Questioning, and UI Derivation

**Version:** 0.6.0
**Skill:** workflow-intelligence
**Dependencies:** brainstorming, knowledge-acquisition, memory-mcp

---

## TL;DR

This skill teaches AID how to detect workflow/agent projects, guide PM through
domain-specific questioning (WF1-WF7 as inserts into the standard brainstorming
flow), recommend platforms (LangChain/LangGraph as default, N8N/LangFlow as
alternative), derive UI requirements from workflow design, and produce
architecture proposals with Docker Compose templates.

Workflow intelligence activates transparently during `/aid-brainstorm` when a
workflow or agent project is detected. It supplements the standard questioning
flow with workflow-specific inserts — it never replaces or reorders the standard
flow.

**Activation:** Automatic during brainstorming when Platform Detection Protocol
identifies a workflow/agent project.
**Input:** PM's topic, conversation keywords, project-profile.yaml
**Output:** Platform recommendation, UI derivation, Docker architecture template
(all folded into the brainstorming plan and EPIC draft)

---

## Platform Detection Protocol

Detect whether the current brainstorming topic is a workflow/agent project and
determine the target platform. Detection runs once at the start of Step 2
(Questions) in the brainstorming flow, before the first question is asked.

### Source 1: Conversation Keywords

Scan PM's topic description and any initial context for platform-indicative
keywords. Match is case-insensitive.

```
KEYWORD → PLATFORM HINT MAP:

langchain, chain, LLM chain, runnable     → langchain
langgraph, graph, state machine,
  state graph, conditional edges           → langgraph
n8n, workflow nodes, n8n nodes             → n8n
langflow, flow builder, langflow flow      → langflow
agent, chatbot, RAG, automation,
  AI workflow, LLM agent, assistant,
  multi-agent, tool-calling                → generic-workflow (platform TBD)
```

### Source 2: Project Profile

Read `project-profile.yaml` frameworks list for exact platform match.

```
IF project-profile.yaml exists:
  frameworks = project-profile.yaml -> tech_stack.frameworks
  IF "langchain" IN frameworks     → langchain (exact)
  IF "langgraph" IN frameworks     → langgraph (exact)
  IF "n8n" IN frameworks           → n8n (exact)
  IF "langflow" IN frameworks      → langflow (exact)
```

### Source 3: PM Explicit Mention

If PM explicitly names a platform during conversation (e.g., "I want to build
this with LangGraph"), that overrides all other detection.

### Detection Result

Apply sources in priority order. First match wins.

```
DETECTION PRIORITY:
  1. Explicit PM mention during conversation → exact platform
  2. project-profile.yaml frameworks match   → exact platform
  3. Keyword match to specific platform      → exact platform
  4. Keyword match to generic-workflow       → generic-workflow
     (AID recommends platform in WF7)
  5. No match from any source               → NOT a workflow project
     (workflow inserts do NOT activate)

STORE detection result as:
  workflow_detected: true | false
  platform_hint: langchain | langgraph | n8n | langflow | generic-workflow | null
  platform_source: explicit | profile | keyword | null
  platform_confidence: high (explicit/profile) | medium (specific keyword) | low (generic keyword)
```

### Detection Timing

```
WHEN: Step 2 (Questions) of /aid-brainstorm, BEFORE the first question.
      After reading project context (Step 1) but before asking anything.

IF workflow_detected == true:
  Inform PM (one line, non-blocking):
    "I detected this is a workflow/agent project ({platform_hint}).
     I'll include some workflow-specific questions alongside the standard ones."

IF workflow_detected == false:
  Say nothing. Standard brainstorming proceeds unchanged.
```

---

## Workflow Questioning Protocol

When `workflow_detected == true`, the standard brainstorming questioning flow
(Step 2 of `/aid-brainstorm`) is supplemented with workflow-specific inserts
WF1 through WF7. These are NOT replacements — they are additions that follow
naturally from the standard question context.

### Integration Map

The left column shows the standard brainstorming question category (from
`skills/brainstorming.md` and `commands/aid-brainstorm.md` Step 2). The right
column shows the workflow insert that activates after that standard question.

```
STANDARD QUESTION CATEGORY     WORKFLOW INSERT (if workflow_detected)
══════════════════════════     ═══════════════════════════════════════

Scope                          → + WF1: PURPOSE
  "What's the boundary?"          "What should the agent/workflow do
                                   specifically? What problem does it solve?"
                                  Follow-up: "Give an example: user does X,
                                   agent returns Y."

Users                          → + WF2: INTERACTION MODEL
  "Who uses this?"                "How will users communicate with the
                                   agent/workflow?"
                                  (A) Chat — conversational back-and-forth
                                  (B) Upload & Process — submit data, get result
                                  (C) Trigger-based — event/schedule triggers action
                                  (D) Dashboard — monitor and control
                                  (E) Combination — describe which

                               → + WF3: OUTPUT
                                  "What is the output? What does the user get?"
                                  (A) Text — natural language answer/summary
                                  (B) Structured data — JSON, table, report
                                  (C) Action — side effect (send email, update DB)
                                  (D) File — generated document, export, download
                                  (E) Combination — describe which

                               → + WF4: DATA & INPUTS
                                  (new question, inserted after Users/WF2/WF3)
                                  Pre-scan: read .aid-o/05-inputs/ before asking.
                                  "What data will the workflow process?"
                                  Probe: type, volume, format.
                                  IF .aid-o/05-inputs/ contains files:
                                    "I found sample files in .aid-o/05-inputs/:
                                     {list files}. Are these representative?"
                                  IF .aid-o/05-inputs/ is empty or missing:
                                    "Have sample data files? Place them in
                                     .aid-o/05-inputs/ and I can analyze them."

Constraints                    → + WF5: TOOLS & INTEGRATIONS
  "Any hard constraints?"         "What external services or tools will
                                   the workflow connect to?"
                                  (A) None — self-contained
                                  (B) External APIs — describe which
                                  (C) Database — type and purpose
                                  (D) Cloud services — AWS/GCP/Azure specifics
                                  (E) Other LLM/AI services — describe which
                                  → Derive MCP server recommendations from answer
                                    (see MCP Derivation Table below)

Patterns                       (no workflow insert — unchanged)

Scale                          (no workflow insert — unchanged)

Timeline                       (no workflow insert — unchanged)

Success                        → + WF6: USABILITY SUCCESS
  "How will you know              "Do agent decisions need to be explainable?
   this succeeded?"                Should outputs include reasoning/sources?"
                                  Follow-up (if applicable):
                                  "Should a human validate the output before
                                   it takes effect? (human-in-the-loop)"

AFTER ALL QUESTIONS            → + WF7: PLATFORM RECOMMENDATION
  (transition to Step 3)          AID decides the platform based on all
                                  answers collected. This is NOT a question —
                                  AID presents its recommendation.
                                  (see Platform Recommendation Logic below)
```

### WF7: Platform Recommendation Logic

WF7 runs after all questions are answered, before transitioning to Step 3
(Approaches). AID decides the platform based on the collected answers.

```
IF platform_hint is exact (langchain | langgraph | n8n | langflow):
  → Use the detected platform. Confirm to PM:
    "Based on your project profile / stated preference, I'll design
     for {platform}."

IF platform_hint == generic-workflow:
  → AID decides based on complexity signals:

  COMPLEXITY SIGNALS (from WF1-WF6 answers):
    complex_signals = 0

    IF WF1 (purpose) mentions: multi-step reasoning, conditional logic,
       branching, state management, multi-agent, human-in-the-loop
      → complex_signals += 1

    IF WF2 (interaction) == Chat OR Combination
      → complex_signals += 1

    IF WF3 (output) == Combination OR Action + Text
      → complex_signals += 1

    IF WF4 (data) mentions: large volume, streaming, real-time
      → complex_signals += 1

    IF WF5 (tools) mentions: multiple APIs, other LLM services, database + API
      → complex_signals += 1

    IF WF6 (usability) mentions: explainability, human-in-the-loop, audit trail
      → complex_signals += 1

  DECISION:
    IF complex_signals >= 3:
      recommended = "LangChain/LangGraph"
      alternative = "N8N or LangFlow"
      reason = "Complex workflow with {list matching signals} benefits from
               code-first orchestration with full control over state and logic."

    IF complex_signals < 3:
      recommended = "N8N or LangFlow"
      alternative = "LangChain/LangGraph"
      reason = "Straightforward workflow suits visual/low-code orchestration
               for faster iteration. Code-first available if needs grow."

  PRESENT TO PM (one message):
    "Platform Recommendation
     ====================================
     Recommended: {recommended}
       Reason: {reason}

     Alternative: {alternative}
       Available if you prefer more {control | simplicity}.

     I'll include both variants in the approach proposals (Step 3)."

  ALWAYS offer both variants in Step 3 approaches.
  PM can override by stating a preference — follow PM's choice.
```

### MCP Derivation Table

When WF5 (Tools & Integrations) answers are collected, derive MCP server
recommendations to include in the plan.

```
WF5 ANSWER                → MCP SERVER RECOMMENDATION
══════════════════════     ═══════════════════════════
(B) External APIs          → Context7 MCP (for API docs)
(C) Database               → Database MCP (PostgreSQL/SQLite MCP)
(D) Cloud services         → Relevant cloud MCP (if available)
(E) Other LLM/AI           → Context7 MCP (for framework docs)
Any file operations        → Filesystem MCP
GitHub repository          → GitHub MCP
Web browsing needed        → Playwright/Browser MCP
Framework docs needed      → Context7 MCP
Workflow/agent project     → MCP servers for agent tools (per platform)
```

### Questioning Rules

These rules govern how workflow inserts interact with the standard brainstorming
flow. They are non-negotiable.

```
RULE 1: Standard flow runs ALWAYS.
        Workflow inserts are supplements, never replacements.
        If workflow_detected == false, no inserts activate.

RULE 2: Inserts activate ONLY if workflow_detected == true.
        Each insert checks workflow_detected before executing.

RULE 3: Each insert follows naturally from its standard question context.
        Transition must be smooth — no abrupt topic changes.
        Example: after "Who uses this?" → "How will they communicate
        with the agent?" is a natural follow-up.

RULE 4: Each insert = maximum 1 question + maximum 1 follow-up.
        Never ask 2+ workflow questions in a single insert.
        If the insert has a follow-up, it counts as the follow-up,
        not as a separate question.

RULE 5: WF7 (platform recommendation) is NOT a question.
        AID decides and presents the recommendation.
        PM can override but is not asked to choose.

RULE 6: If the standard question already covered a workflow aspect, skip
        the corresponding insert.
        Example: if PM answered the Scope question with "the agent should
        process PDFs and return summaries," WF1 (purpose) is already
        answered — skip it.

RULE 7: .aid-o/05-inputs/ scan happens BEFORE WF4 (data question).
        Scan the directory first, then present findings as part of the
        WF4 question. If the directory does not exist, mention it as an
        option but do not create it.

RULE 8: Total question count: standard (3-7) + workflow inserts (3-5) = max 12.
        If the standard flow used 7 questions, workflow inserts are limited to 5.
        If the standard flow used 3 questions, workflow inserts can use up to 5.
        Never exceed 12 total questions in a single brainstorming session.
        WF7 does not count as a question (RULE 5).
```

---

## UI Derivation Logic

After WF7 determines the platform and Step 3 (Approaches) confirms the
direction, derive the UI requirements from the workflow design. UI derivation
is deterministic — it follows the interaction model and output type chosen by
PM to produce a concrete UI specification.

### Platform to UI Framework Rule

The platform determines which UI framework is used.

```
PLATFORM              → UI FRAMEWORK RULE
════════════════════  ═══════════════════════════════════════════════════
LangChain/LangGraph   → React UI (AID designs based on workflow)
                        Custom React frontend. AID generates component
                        list based on interaction model and output type.

N8N                   → N8N built-in UI (primary)
                        + optional custom React frontend if PM needs
                        features beyond N8N's built-in dashboard.

LangFlow              → LangFlow built-in UI (primary)
                        + embedded chat widget for end-user interaction.
                        Custom frontend only if PM explicitly requests it.
```

### Derivation Table

Cross-reference the interaction model (from WF2) and output type (from WF3) to
determine the UI type and React components needed for code-first platforms.

```
INTERACTION     OUTPUT            → UI TYPE           REACT COMPONENTS
═════════════  ═════════════════  ═ ════════════════  ══════════════════════════

Chat           Text/answer        → Chat UI           Chat window, message list,
                                                       input box, typing indicator,
                                                       source citations panel

Chat           Structured data    → Chat + Panel      Chat window + collapsible
                                                       side panel with tables,
                                                       charts, data viewer

Upload &       File/report        → Process UI        Upload drop zone, progress
Process                                                bar, result viewer,
                                                       download button

Upload &       Structured data    → Process + Table   Upload drop zone + tabular
Process                                                output with sorting,
                                                       filtering, pagination

Trigger-based  Action             → Dashboard UI      Status cards, run history
                                                       table, trigger config
                                                       panel, log viewer

Dashboard      Any                → Full Dashboard    Metrics cards, charts
                                                       (time series, bar),
                                                       control panel, real-time
                                                       status, log stream,
                                                       settings page

Combination    Combination        → Composite UI      Combine components from
                                                       matching rows above.
                                                       Use tabbed or split layout.
```

### UI Derivation Procedure

```
1. READ WF2 answer → interaction_model
2. READ WF3 answer → output_type
3. LOOKUP derivation table → ui_type, react_components
4. APPLY platform → UI framework rule:
   IF platform == langchain OR langgraph:
     → Include react_components in plan Architecture section
     → Add frontend role to EPIC steps
   IF platform == n8n:
     → Note "N8N built-in UI" in plan
     → IF PM needs custom features: add optional React frontend
     → Frontend role is optional in EPIC
   IF platform == langflow:
     → Note "LangFlow built-in UI + chat widget" in plan
     → Frontend role is optional in EPIC
5. APPLY scale rule (see UI Special Rules below)
6. INCLUDE ui_type and components in:
   - Plan → Architecture section → UI subsection
   - Plan → Implementation Plan → frontend tasks
   - EPIC → Artifacts → frontend components
   - EPIC → Steps → frontend role (if applicable)
```

### UI Special Rules

```
RULE 1: React is the DEFAULT framework for code-first platforms
        (LangChain, LangGraph). Do not propose Angular, Vue, or Svelte
        unless PM explicitly requests it or project-profile.yaml shows
        an existing frontend framework.

RULE 2: No UI for pure backend/API workflows.
        IF WF2 (interaction) indicates no user-facing interaction
        (e.g., purely internal pipeline, cron job, API-only):
          → Do not generate UI components.
          → Offer a monitoring dashboard optionally:
            "This is a backend workflow. Want a monitoring dashboard
             to track runs and logs? (Y/N)"

RULE 3: UI complexity matches project scale.
        READ scale from standard brainstorming Scale question.
          personal / prototype → simple UI (minimal components, no auth)
          team / internal      → standard UI (auth, basic dashboard)
          production / public  → full UI (auth, dashboard, error handling,
                                  loading states, responsive design)

RULE 4: UI is ALWAYS part of Docker Compose when both exist.
        If the plan includes Docker Compose AND a frontend, the
        frontend container is included in the Compose file.
        Never deploy UI separately from the workflow backend.

RULE 5: UI design follows the workflow, never the other way around.
        The workflow architecture is decided first (WF1-WF7, Step 3).
        UI is derived from it. Never change workflow design to
        accommodate a UI preference.
```

---

## Platform-Specific Knowledge (Static Fallback)

This section contains hardcoded knowledge for each supported platform. It serves
as the lowest-priority fallback when Qdrant KB and Context7 are unavailable.
This knowledge is always available (0 seconds latency) and ensures AID can
produce useful architecture proposals even without external knowledge sources.

### LangChain + LangGraph

**When to use:** Complex workflows requiring code-first orchestration, multi-step
reasoning, conditional branching, multi-agent coordination, human-in-the-loop
patterns, or fine-grained control over LLM interactions.

**Core Concepts:**
- **StateGraph** — defines workflow as a directed graph with typed state. Nodes are
  functions that read and write state. Edges define transitions (conditional or
  unconditional).
- **Checkpointer** — persistence layer for graph state. Enables pause/resume,
  human-in-the-loop, and crash recovery. Use `MemorySaver` for dev,
  `SqliteSaver` or `PostgresSaver` for production.
- **Tool-calling** — LLM decides which tools to invoke based on descriptions.
  Tools are Python functions decorated with `@tool`. LangChain provides
  built-in tools for search, math, code execution.
- **Human-in-the-loop** — interrupt graph execution at any node to wait for
  human input. Use `interrupt_before` or `interrupt_after` on nodes.
  Checkpointer saves state; `graph.update_state()` resumes.
- **Multi-agent supervisor** — one LLM (supervisor) routes tasks to
  specialized agent sub-graphs. Each agent has its own tools and system
  prompt. Supervisor decides which agent to call and when to finish.
- **RAG with citations** — retrieval-augmented generation. Vector store
  retriever → context injection → LLM generation with source tracking.
  Use `create_retrieval_chain` or custom graph nodes.
- **Streaming** — token-by-token output via `astream_events` or `astream`.
  Supports streaming from intermediate nodes in a graph.

**Architecture Pattern:**
```
┌────────────┐     ┌──────────────┐     ┌─────────────┐
│  Frontend   │────▶│  API Server  │────▶│  LangGraph  │
│  (React)    │◀────│  (FastAPI)   │◀────│  StateGraph  │
└────────────┘     └──────┬───────┘     └──────┬──────┘
                          │                     │
                   ┌──────▼───────┐     ┌──────▼──────┐
                   │  PostgreSQL  │     │ Vector Store │
                   │  (state +   │     │ (Chroma /    │
                   │   checkpts) │     │  Qdrant)     │
                   └─────────────┘     └─────────────┘
```

**Docker Compose Template:**
```yaml
services:
  app:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/app
      - VECTORSTORE_URL=http://vectorstore:6333
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    depends_on:
      - db
      - vectorstore

  frontend:
    build: ./frontend
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://localhost:8000
    depends_on:
      - app

  db:
    image: postgres:16
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=pass
      - POSTGRES_DB=app
    volumes:
      - postgres_data:/var/lib/postgresql/data

  vectorstore:
    image: qdrant/qdrant:latest
    ports:
      - "6333:6333"
    volumes:
      - qdrant_data:/qdrant/storage

volumes:
  postgres_data:
  qdrant_data:
```

**Key Files to Generate:**
- `app/graph.py` — StateGraph definition (nodes, edges, state schema)
- `app/nodes/` — individual node functions
- `app/tools/` — tool definitions
- `app/api.py` — FastAPI endpoints exposing the graph
- `app/checkpointer.py` — checkpointer configuration
- `frontend/` — React application (if UI required)

### N8N

**When to use:** Integration-heavy workflows, simple automation chains,
trigger-based processing, or when the team prefers visual workflow building
over code. Good for connecting existing services with minimal custom logic.

**Core Concepts:**
- **Workflow JSON** — N8N workflows are defined as JSON with nodes and
  connections. Each node has a type, parameters, and position. Workflows
  can be exported/imported as JSON files.
- **AI Agent node** — built-in node for LLM-powered agent logic. Supports
  tool-calling, memory, and multi-step reasoning within the N8N visual editor.
- **Trigger nodes** — start workflows based on events: webhook, cron schedule,
  file change, email received, database change, or manual trigger.
- **Custom nodes** — extend N8N with TypeScript/JavaScript custom nodes for
  project-specific logic. Package as npm modules.
- **Credentials management** — centralized credential store for API keys,
  OAuth tokens, database connections. Encrypted at rest.
- **Sub-workflows** — call other workflows as sub-routines. Enables
  modular workflow composition and reuse.

**Architecture Pattern:**
```
┌────────────┐     ┌──────────────┐     ┌─────────────┐
│ N8N Editor  │────▶│  N8N Server  │────▶│  Workflows  │
│ (built-in  │◀────│  (Node.js)   │◀────│  (JSON)     │
│  web UI)   │     └──────┬───────┘     └──────┬──────┘
└────────────┘            │                     │
                   ┌──────▼───────┐     ┌──────▼──────┐
                   │  PostgreSQL  │     │  External   │
                   │  (workflow   │     │  Services   │
                   │   + creds)  │     │  (APIs)     │
                   └─────────────┘     └─────────────┘
```

**Docker Compose Template:**
```yaml
services:
  n8n:
    image: n8nio/n8n:latest
    ports:
      - "5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=user
      - DB_POSTGRESDB_PASSWORD=pass
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      - db

  db:
    image: postgres:16
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=pass
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data

  # Optional: workers for scaling execution
  # n8n-worker:
  #   image: n8nio/n8n:latest
  #   command: worker
  #   environment:
  #     - EXECUTIONS_MODE=queue
  #     - QUEUE_BULL_REDIS_HOST=redis
  #   depends_on:
  #     - n8n
  #     - redis

  # redis:
  #   image: redis:7-alpine
  #   volumes:
  #     - redis_data:/data

volumes:
  n8n_data:
  postgres_data:
  # redis_data:
```

**Key Files to Generate:**
- `workflows/` — exported N8N workflow JSON files
- `custom-nodes/` — custom N8N node packages (if needed)
- `docker-compose.yml` — N8N + database stack
- `.env` — credentials and configuration
- `README.md` — workflow documentation and setup instructions

### LangFlow

**When to use:** Visual flow building with LangChain components, rapid
prototyping, when the team wants a GUI for LangChain chain construction,
or when the final product includes an embedded chat interface.

**Core Concepts:**
- **Visual flow builder** — drag-and-drop editor for building LangChain
  chains and agents. Each component maps to a LangChain class.
- **Component mapping** — LangFlow components correspond 1:1 to LangChain
  abstractions: LLMs, prompts, chains, agents, tools, memory, retrievers.
  Configuration is done through the visual editor.
- **JSON export/import** — flows are stored as JSON. Can be version-controlled,
  shared, and imported into other LangFlow instances.
- **Auto-generated API endpoints** — every flow automatically gets a REST API
  endpoint. No additional server code needed. Supports streaming responses.
- **Embedded chat widget** — built-in chat widget that can be embedded in
  external web pages via iframe or JavaScript snippet. Connects directly
  to the flow's API endpoint.

**Architecture Pattern:**
```
┌────────────┐     ┌──────────────┐     ┌─────────────┐
│  LangFlow  │────▶│  LangFlow    │────▶│   Flows     │
│  Editor    │◀────│  Server      │◀────│   (JSON)    │
│ (built-in  │     │  (Python)    │     └──────┬──────┘
│  web UI)   │     └──────┬───────┘            │
└────────────┘            │              ┌─────▼──────┐
                   ┌──────▼───────┐     │  LangChain │
   ┌──────────┐   │  PostgreSQL  │     │  Runtime   │
   │  Chat    │   │  (flows +   │     └────────────┘
   │  Widget  │   │   config)   │
   │ (embed)  │   └─────────────┘
   └──────────┘
```

**Docker Compose Template:**
```yaml
services:
  langflow:
    image: langflowai/langflow:latest
    ports:
      - "7860:7860"
    environment:
      - LANGFLOW_DATABASE_URL=postgresql://user:pass@db:5432/langflow
      - LANGFLOW_SECRET_KEY=${LANGFLOW_SECRET_KEY}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
    volumes:
      - langflow_data:/app/langflow
    depends_on:
      - db

  db:
    image: postgres:16
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=pass
      - POSTGRES_DB=langflow
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  langflow_data:
  postgres_data:
```

**Key Files to Generate:**
- `flows/` — exported LangFlow flow JSON files
- `docker-compose.yml` — LangFlow + database stack
- `.env` — API keys and configuration
- `embed/` — chat widget embedding code (if end-user chat needed)
- `README.md` — flow documentation and setup instructions

---

## Docker and MCP Preference Rules

When generating the plan and EPIC for a workflow project, apply these rules to
determine whether Docker Compose and MCP servers should be recommended.

### Docker Preference

```
RULE 1: 2+ services → Docker Compose recommended.
        All workflow platforms involve at least 2 services
        (app + database), so Docker is virtually always recommended.

RULE 2: External dependencies (DB, cache, vector store) → Docker recommended.
        Reproducible environment for all team members.

RULE 3: Reproducibility important → Docker recommended.
        If PM mentions "reproducible," "portable," or "deployable,"
        Docker Compose is strongly recommended.

RULE 4: Workflow/agent project → Docker STRONGLY recommended.
        For any project detected by the Platform Detection Protocol,
        include Docker Compose in the plan by default.
        PM can opt out explicitly.
```

### MCP Preference

```
RULE 1: Project uses DB                → Database MCP recommended
RULE 2: Project has GitHub repo        → GitHub MCP recommended
RULE 3: Project needs file operations  → Filesystem MCP recommended
RULE 4: Project needs web browsing     → Playwright/Browser MCP recommended
RULE 5: Project needs framework docs   → Context7 MCP recommended
RULE 6: Workflow/agent project         → MCP servers for agent tools
         (derived from WF5 answers, see MCP Derivation Table above)
```

---

## Knowledge Enrichment Flow

Workflow intelligence uses a three-tier knowledge system. Each tier is tried in
priority order. The first tier that returns useful results is used. Lower tiers
serve as fallback.

### Priority Chain

```
PRIORITY 1: Qdrant Knowledge Base (seed EPIC + internal KB)
  → Fastest for repeat queries. Contains indexed documentation
    from past research, completed EPICs, and seed research.
  → Latency: ~1-2 seconds
  → Query: knowledge_find(query="{platform} {topic}", filters={types: ["documentation", "pattern"]})

PRIORITY 2: Context7 Live Documentation
  → Fresh, curated documentation for 1000+ libraries.
  → Latency: 10-15 seconds
  → Query: resolve-library-id(libraryName="{platform}") → query-docs(query="{specific question}")

PRIORITY 3: Static Fallback (this skill file)
  → Always available, zero latency.
  → Contains the Platform-Specific Knowledge section above.
  → Used when both Qdrant and Context7 are unavailable or return empty results.
```

### Enrichment Timing

Knowledge enrichment happens at two points during workflow brainstorming:

```
ENRICHMENT POINT 1: During WF7 (Platform Recommendation)
  BEFORE presenting the recommendation:
    1. TRY Qdrant: knowledge_find("{platform_hint} architecture patterns")
       TIMEOUT: 5 seconds. If slow or empty, continue.
    2. IF Qdrant returned useful results:
       → Enrich recommendation with specific patterns and lessons.
       → Skip Context7 (Qdrant is sufficient).
    3. IF Qdrant returned nothing:
       TRY Context7:
         a. resolve-library-id(libraryName="{platform_hint}")
            TIMEOUT: 5 seconds. If slow, skip to static.
         b. query-docs(libraryId="{resolved_id}", query="architecture patterns getting started")
            TIMEOUT: 10 seconds. If slow, skip to static.
       → IF Context7 returned results:
         Enrich recommendation with live documentation references.
       → IF Context7 returned nothing:
         Use static fallback from Platform-Specific Knowledge section.
    4. ALWAYS have platform knowledge available (static fallback guarantees this).

ENRICHMENT POINT 2: During Step 3 (Approaches) — platform-specific approach details
  BEFORE presenting approaches:
    1. TRY Qdrant: knowledge_find("{platform_hint} {topic} best practices")
       TIMEOUT: 5 seconds.
    2. IF Qdrant returned useful results:
       → Add [Knowledge] labels to approach pros/cons.
       → Skip Context7.
    3. IF Qdrant returned nothing:
       TRY Context7:
         query-docs(libraryId="{resolved_id}", query="{approach-specific question}")
         TIMEOUT: 10 seconds.
       → IF Context7 returned results:
         Add [Docs] labels to approach pros/cons.
       → IF Context7 returned nothing:
         Use static fallback for approach details.
    4. ALWAYS have something to say (static fallback guarantees this).
```

### Inline Research Protocol

When workflow intelligence needs platform-specific information during
brainstorming that is not covered by the enrichment points above, use this
lightweight inline research protocol.

```
INLINE RESEARCH (for specific questions during design, Step 4-5):
  1. Check static fallback first (this file, 0 seconds).
  2. IF static is insufficient for the specific question:
     TRY Context7: query-docs(libraryId="{resolved_id}", query="{specific question}")
     TIMEOUT: 10 seconds.
  3. IF Context7 returned nothing:
     Note in plan: "Requires further research: {specific question}"
     Do NOT block the brainstorming session.

RULES:
  - Inline research happens AT MOST twice per brainstorming session.
  - Never block PM waiting for research results.
  - If research takes >10 seconds, skip and note for later.
  - Research results are informational — PM makes the final decision.
```

### Graceful Degradation

```
| Scenario                              | Behavior                                    |
|---------------------------------------|---------------------------------------------|
| Qdrant unavailable                    | Skip to Context7. No error shown to PM.     |
| Context7 unavailable                  | Skip to static fallback. No error shown.    |
| Both Qdrant and Context7 unavailable  | Use static fallback only. Full functionality |
|                                       | preserved with hardcoded knowledge.          |
| Qdrant returns stale results          | Use them (stale > nothing). Note staleness   |
|                                       | internally for potential re-research.        |
| Context7 returns irrelevant results   | Discard. Fall through to static.             |
| All enrichment times out              | Use static fallback. Session unaffected.     |
```

In every degradation scenario, the brainstorming session proceeds without
interruption. PM never sees error messages related to knowledge retrieval.
The static fallback in this skill file guarantees that AID always has platform
knowledge available.

---

## Integration with Brainstorming Flow

This section summarizes how workflow-intelligence.md integrates with the
existing brainstorming skill and command.

### Activation

```
ACTIVATION POINT: Step 2 (Questions) of /aid-brainstorm
TRIGGER: Platform Detection Protocol returns workflow_detected == true
DEACTIVATION: If workflow_detected == false, this entire skill is dormant.
```

### What This Skill Modifies

```
MODIFIES (supplements):
  - Step 2 (Questions): adds WF1-WF6 inserts between standard questions
  - Step 2→3 transition: adds WF7 platform recommendation
  - Step 3 (Approaches): requires two variants (recommended + alternative platform)
  - Step 4 (Design): adds UI derivation subsection to Architecture
  - Step 7 (Document): plan includes platform, UI type, Docker template
  - Step 8 (EPIC Subagent): EPIC includes platform-specific roles and artifacts

DOES NOT MODIFY:
  - Step 1 (Context): unchanged
  - Step 5 (Sections): unchanged (workflow sections are part of Step 4 design)
  - Step 6 (Approval): unchanged
  - Step 9 (Execution Plan Option): unchanged
  - Step 10 (Handoff): unchanged
```

### Data Flow

```
PM's topic
  │
  ▼
Platform Detection Protocol (Step 2, before questions)
  │
  ├─ workflow_detected: true
  │   ├─ platform_hint
  │   ├─ platform_source
  │   └─ platform_confidence
  │
  ▼
Standard Questions + WF1-WF6 Inserts (Step 2)
  │
  ├─ WF1: purpose
  ├─ WF2: interaction_model
  ├─ WF3: output_type
  ├─ WF4: data_inputs
  ├─ WF5: tools_integrations → MCP recommendations
  └─ WF6: usability_success → human-in-the-loop flag
  │
  ▼
WF7: Platform Recommendation (Step 2→3 transition)
  │
  ├─ recommended_platform
  ├─ alternative_platform
  └─ complexity_signals
  │
  ▼
UI Derivation (Step 4, within Design)
  │
  ├─ ui_type (from derivation table)
  ├─ ui_framework (from platform rule)
  └─ react_components (if applicable)
  │
  ▼
Plan Document (Step 7)
  │
  ├─ Architecture section includes:
  │   - Platform choice + rationale
  │   - UI type + components
  │   - Docker Compose template
  │   - MCP server recommendations
  └─ Implementation Plan includes platform-specific tasks
  │
  ▼
EPIC Draft (Step 8)
  │
  ├─ Platform-specific roles and artifacts
  ├─ Docker Compose as artifact
  ├─ Frontend role (if UI derived)
  └─ MCP servers in dependencies
```

---

## MUST Rules

1. **ALWAYS run Platform Detection Protocol before the first question** — detection
   is a prerequisite for all workflow inserts
2. **ALWAYS follow the standard brainstorming flow** — workflow inserts supplement,
   never replace or reorder
3. **ALWAYS offer both platform variants in Step 3** — recommended and alternative
4. **ALWAYS use the derivation table for UI** — do not improvise UI components
5. **ALWAYS include Docker Compose for workflow projects** — PM can opt out but
   default is Docker
6. **ALWAYS try knowledge enrichment in priority order** — Qdrant > Context7 > static
7. **NEVER block brainstorming waiting for knowledge retrieval** — timeouts are strict
8. **NEVER exceed 12 total questions** — standard + workflow inserts combined
9. **NEVER change workflow design to accommodate UI preferences** — workflow first,
   UI derived
10. **NEVER skip static fallback** — it is always the final safety net

---

## Reference Files

- `commands/aid-brainstorm.md` — command flow where workflow inserts activate
- `skills/brainstorming.md` — standard questioning and approach protocols
- `skills/knowledge-acquisition.md` — knowledge pipeline (`knowledge_find()`, Context7 integration)
- `skills/memory-mcp.md` — Qdrant memory protocol
- `.aid-o/04-engine/memory/project-profile.yaml` — tech stack detection for platform matching
- `.aid-o/05-inputs/` — sample data directory scanned by WF4

---

**Version:** 0.6.0
**Last Updated:** 2026-02-23
