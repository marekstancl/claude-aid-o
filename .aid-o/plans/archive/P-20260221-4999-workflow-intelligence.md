---
id: P-20260221-4999
type: plan
status: done
created: 2026-02-21
author: PM + AI
depends_on: P-20260220-1988
---

# Plan: Workflow Intelligence + Docker/MCP Preference for AID Orchestrator

## Context

AID Orchestrator currently treats all projects generically — the brainstorming and planning flows ask the same questions regardless of whether the user is building a simple REST API or a complex multi-agent AI workflow. This results in missed opportunities: AID doesn't guide users through workflow-specific decisions (input/output design, interaction model, platform selection), doesn't recommend Docker deployment when it clearly makes sense, and doesn't suggest MCP servers that would improve the development experience.

Three converging needs drive this plan:

1. **Workflow Intelligence** — When AID detects that a project involves AI agents, chatbots, RAG pipelines, or workflow automation (LangChain, LangGraph, N8N, LangFlow), it should activate domain-specific questioning that ensures the resulting workflow is functional, has real value, and good usability.
2. **Docker/MCP Preference** — For ANY project where it makes sense (2+ services, external dependencies, team collaboration), AID should recommend Docker Compose deployment and relevant MCP servers. This is a cross-cutting concern, not workflow-specific.
3. **Knowledge Base for AI Agent Building** — AID needs internal know-how about workflow platforms, architecture patterns, and common use-cases to make informed recommendations. This knowledge comes from Context7 docs (live), studied GitHub repositories (seed EPIC), and accumulated project experience (ongoing).

This plan depends on **P-20260220-1988 (Knowledge Acquisition MVP)** which provides the infrastructure: Context7 integration, Qdrant `documentation` type, `knowledge_find()`, and quality gates.

### Key Design Decisions from Brainstorming

- **Separate plan from P-20260220-1988** — Knowledge acquisition is infrastructure (pipeline); workflow intelligence is logic (what AID does with knowledge). Clean dependency, no data loss from the original plan.
- **Workflow questioning as INSERT into standard flow** — Standard brainstorming questions have value for every project. Workflow questions are injected at the right points, not a replacement.
- **Docker/MCP preference is cross-cutting** — Applies to ALL projects, not just workflow. Workflow intelligence amplifies it for workflow projects.
- **LangChain/LangGraph recommended, N8N/LangFlow as alternative** — Code-first platforms as default recommendation, no/zero-code as alternative offered to every user.
- **No-code platforms use their own UI** — N8N and LangFlow have built-in UI. Custom React UI only for code-first platforms (LangChain/LangGraph).
- **UI derived from workflow design** — No hardcoded UI type. AID analyzes interaction model + output type + data to propose the right UI.
- **Hybrid knowledge acquisition** — Seed EPIC for GitHub repos (deep, one-time), live Context7 for docs (inline during brainstorming), ongoing extraction from completed projects.
- **`.aid-o/05-inputs/`** — Dedicated directory for sample files, auto-scanned by brainstorming, plus arbitrary paths from PM.

## Goal

Add workflow-specific intelligence to AID's brainstorming and planning flows, implement cross-cutting Docker/MCP preference rules for all projects, and build a knowledge base from GitHub repositories and documentation that enables AID to guide users from idea to deployable workflow with UI — producing real, functional output rather than paper architecture.

## Scope

**In scope:**
- New skill: `workflow-intelligence.md` (platform detection, questioning protocol, UI derivation, platform knowledge, knowledge enrichment flow)
- Extend `brainstorming.md` — workflow detection + WF1-WF7 question inserts + Docker/MCP preference (general) + `.aid-o/05-inputs/` scan + example EPIC lookup
- Extend `planner.md` — Docker/MCP step injection for all projects
- Extend `aid-init.md` — create `.aid-o/05-inputs/` directory
- Extend `aid-help.md` — Input Files section
- Seed Research EPIC for LangChain/LangGraph, N8N, LangFlow repositories
- Example EPICs in `defaults/examples/` (AI workflows + common projects)
- Context7 live research integration for brainstorming

**Out of scope:**
- Modifying P-20260220-1988 (separate plan, dependency only)
- Building actual workflow projects (AID designs and plans them; subagents implement)
- Custom MCP server development (AID recommends existing MCP servers)
- Domain plugins framework (YAGNI — single skill per domain, no abstract framework)
- Real-time monitoring of GitHub repositories for updates
- Automated testing of generated Docker Compose files

## Approach

### Option A: Workflow Intelligence Skill + Cross-cutting Docker/MCP (Chosen)

A new `workflow-intelligence.md` skill serves as the domain-specific knowledge center for workflow/agent projects. Docker/MCP preference rules are added as cross-cutting concerns to brainstorming and planner (applying to ALL projects). Knowledge is acquired through a hybrid model: seed EPIC for GitHub repos, live Context7 for docs, ongoing extraction from completed projects.

**Pros:**
- Clean separation — workflow logic in one skill, Docker/MCP as general rules
- Follows existing AID architecture (skills define protocols)
- Reusable — planner, brainstorming, and agent-core all read from the same skill
- Extensible — future domains follow the same pattern (new skill per domain)
- Docker/MCP benefits all projects, not just workflow

**Cons:**
- New skill file to coordinate
- Workflow intelligence skill will be large (~400-500 lines)

### Option B: Brainstorming Profiles (Rejected)

No new skill. Add "profiles" to brainstorming.md with domain-specific questioning.

**Rejected because:** brainstorming.md is already 550+ lines. Adding 300+ more creates an unmaintainable monolith. Planner can't access workflow logic independently.

### Option C: Domain Knowledge Packs (Rejected)

Abstract domain pack system with YAML-driven questions, preferences, and templates per domain.

**Rejected because:** YAGNI — we need one domain (workflow), not a framework for N domains. Infrastructure overhead not justified.

### Decision

**Chosen:** Option A with 2-phase delivery.
**Rationale:** Architecturally sound (dedicated skill + cross-cutting rules), pragmatically delivered. Phase 1 delivers the intelligence (skill + brainstorming/planner extensions). Phase 2 delivers the knowledge (seed research + example EPICs).

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    CROSS-CUTTING                         │
│                                                          │
│  brainstorming.md (extension)                            │
│  ├── Docker/MCP preference rules (general)               │
│  ├── Workflow detection → activate workflow-intelligence  │
│  └── .aid-o/05-inputs/ auto-scan                         │
│                                                          │
│  planner.md (extension)                                  │
│  ├── Docker/MCP preference injection into steps          │
│  └── "Recommend Docker Compose when 2+ services"         │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                 DOMAIN-SPECIFIC                           │
│                                                          │
│  workflow-intelligence.md (new skill)                     │
│  ├── Platform Detection Protocol                         │
│  │   (LangChain/LangGraph/N8N/LangFlow/generic)         │
│  ├── Workflow Questioning Protocol                        │
│  │   (WF1-WF7 inserts into standard brainstorming flow)  │
│  ├── UI Derivation Logic                                 │
│  │   (workflow design → UI type recommendation)          │
│  ├── Platform-Specific Patterns                          │
│  │   (Docker Compose templates, architecture, key        │
│  │    patterns — static fallback when Qdrant empty)      │
│  └── Example EPIC References                             │
│      (defaults/examples/ lookup)                         │
│                                                          │
├──────────────────────────────────────────────────────────┤
│                   KNOWLEDGE                              │
│                                                          │
│  knowledge-acquisition.md (P-20260220-1988)              │
│  ├── Context7 → platform docs (live, inline)             │
│  ├── GitHub repo study → patterns in Qdrant (seed EPIC)  │
│  └── Internal KB → accumulated from completed projects   │
│                                                          │
│  defaults/examples/                                      │
│  ├── ai-workflows/ (12 example EPICs)                    │
│  └── common-projects/ (7 example EPICs)                  │
│                                                          │
│  .aid-o/05-inputs/ (per-project)                         │
│  └── sample files from user                              │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Integration with P-20260220-1988

```
P-20260220-1988 (Knowledge Acquisition)
  ├── Phase 1: Context7 + Qdrant pipeline     ← MUST be done FIRST
  ├── Phase 2: /aid-research + aging
  └── Phase 3: Example extraction

THIS PLAN (Workflow Intelligence + Docker/MCP)
  ├── depends_on: P-20260220-1988 Phase 1
  ├── Phase 1: workflow-intelligence skill + Docker/MCP rules + 05-inputs
  └── Phase 2: GitHub repo study + example EPICs + knowledge enrichment
```

---

## Workflow Questioning Protocol

Standard brainstorming flow runs always. When AID detects a workflow/agent project, domain-specific questions are **inserted at the right points** into the standard flow. PM sees a smooth flow, not two separate blocks.

### Integration into Standard Flow

```
STANDARD FLOW              WORKFLOW INSERT (if detected)
═══════════════              ═══════════════════════════════════

Q: Scope                     → + WF1: PURPOSE
"What's the scope?"             "What should the agent/workflow do specifically?
                                  What problem does it solve?"
                                 Follow-up: "Give an example: user does X,
                                  agent returns Y."

Q: Users                     → + WF2: INTERACTION MODEL
"Who uses this?"                "How will users communicate with the agent?"
                                 (A) Chat (B) Upload & Process
                                 (C) Trigger-based (D) Dashboard (E) Combination
                                + WF3: OUTPUT
                                 "What is the output? What does the user get?"
                                 (A) Text (B) Structured data (C) Action
                                 (D) File (E) Combination

                              → + WF4: DATA & INPUTS (new, after Users)
                                 "What data will it process?"
                                 Type, volume, format.
                                 Auto-scan .aid-o/05-inputs/.
                                 "Have sample files? Put in .aid-o/05-inputs/"

Q: Constraints               → + WF5: TOOLS & INTEGRATIONS
"Any constraints?"              "What external services/tools connect?"
                                 (A) None (B) API (C) Database
                                 (D) Services (E) Other LLM/AI
                                → Derive MCP servers from answer

Q: Patterns                   (unchanged)
Q: Scale                      (unchanged)
Q: Timeline                   (unchanged)

Q: Success                    → + WF6: USABILITY SUCCESS
                                 "Need explainability for agent decisions?"
                                 "Should output be validated by human?"
                                 (human-in-the-loop)

AFTER QUESTIONS:              → + WF7: PLATFORM RECOMMENDATION
                                 AID decides based on all answers:
                                 IF complex → LangChain/LangGraph (recommended)
                                 IF simple/integrations → N8N/LangFlow (alternative)
                                 ALWAYS offer both variants
                                 → Straight into Step 3 (Approaches)
```

### Rules

```
RULE 1: Standard flow runs ALWAYS — workflow inserts are supplements
RULE 2: Inserts activate ONLY if workflow/agent project detected
RULE 3: Each insert follows from standard question context — smooth transition
RULE 4: Each insert = max 1 question + max 1 follow-up
RULE 5: WF7 (platform recommendation) is NOT a question — AID decides
RULE 6: If standard question already covered a workflow aspect, skip the insert
RULE 7: .aid-o/05-inputs/ scan happens BEFORE WF4 (data question)
RULE 8: Total questions: standard (3-7) + workflow inserts (3-5) = max 12
```

---

## Docker/MCP Preference Rules (Cross-Cutting)

These rules apply to ALL projects, not just workflow.

### Docker Preference Rules

```
RULE 1: 2+ services → Docker Compose recommended
RULE 2: External dependencies (DB, cache, vector store) → Docker recommended
RULE 3: Reproducibility important (team project, CI/CD) → Docker recommended
RULE 4: Workflow/agent project → Docker STRONGLY recommended
         (workflow-intelligence amplifies general rule)

Presentation:
  IF Docker recommended:
    Every approach in Step 3 INCLUDES Docker Compose as part of architecture.
    Planner adds "Docker Compose setup" step (after architect, before backend).
    Alternative: local setup if PM declines.
  IF Docker NOT needed:
    Don't mention Docker. No step, no compose.
  IF PM declines Docker:
    Respect. Record as constraint: "PM decided: no Docker, local setup."
```

### MCP Server Preference Rules

```
RULE 1: Project uses DB → Database MCP recommended
RULE 2: Project has GitHub repo → GitHub MCP recommended
RULE 3: Project needs file operations → Filesystem MCP
RULE 4: Project needs web browsing → Playwright/Browser MCP
RULE 5: Project needs framework docs → Context7 MCP
RULE 6: Workflow/agent project → MCP servers for agent tools

RULE 7: IF Docker recommended AND MCP recommended:
  → Propose MCP servers INSIDE Docker Compose
  → "MCP servers run in Docker containers alongside your application."

IF PM declines MCP:
  Respect. Alternative: direct SDK/libraries.
  Record as constraint.
```

### Decision Matrix

```
┌─────────────────────┬──────────┬─────────────┐
│ Situation            │ Docker   │ MCP servers │
├─────────────────────┼──────────┼─────────────┤
│ 1 service, no DB    │ —        │ —           │
│ 1 service + DB      │ recom.   │ DB MCP      │
│ 2+ services         │ recom.   │ as needed   │
│ Workflow/agent       │ strongly │ strongly    │
│ Team project         │ recom.   │ as needed   │
│ PM said "no"         │ —        │ —           │
└─────────────────────┴──────────┴─────────────┘
```

---

## UI Derivation Logic

AID derives the UI type from the workflow design based on brainstorming answers. No hardcoded default.

### Platform → UI Rule

```
LangChain/LangGraph → React UI (AID designs based on workflow)
N8N                 → N8N built-in UI (+ optional custom React frontend)
LangFlow            → LangFlow built-in UI (+ embedded chat widget)

For no-code platforms, AID asks:
  "N8N has its own visual editor and UI. Do you need a custom
   React frontend on top, or is the n8n UI sufficient?"
```

### Derivation Table

```
Interaction     Output           →  UI Type              React components
─────────────  ────────────────  ─  ──────────────────  ─────────────────────
Chat           Text/answer       →  Chat UI             Chat window, message list,
                                                         input box, typing indicator,
                                                         source citations

Chat           Structured data   →  Chat + Panel        Chat window + side panel
                                                         with tables/charts

Upload &       File/report       →  Process UI          Upload zone, progress bar,
Process                                                  result viewer, download

Upload &       Structured data   →  Process + Table     Upload zone + tabular
Process                                                  output with filtering

Trigger-based  Action            →  Dashboard UI        Status cards, run history,
                                                         trigger config, log viewer

Dashboard      Any               →  Full Dashboard      Metrics, charts, controls,
                                                         real-time status, log stream
```

### Special Rules

```
RULE 1: React is DEFAULT framework for code-first platforms
        If project-profile.yaml has different frontend framework → respect it
RULE 2: No UI for pure backend/API (offer monitoring dashboard optionally)
RULE 3: UI complexity matches project scale
        Personal → simple (1-3 pages)
        Team → standard (routing, auth, error handling)
        Production → full (responsive, accessibility, loading states)
RULE 4: UI is ALWAYS part of Docker Compose (if both exist)
RULE 5: UI design follows workflow, never the other way around
```

---

## Platform Knowledge & Detection

### Detection Protocol

```
SOURCES:
  1. Conversation keywords → platform hint
     langchain/chain/LLM           → langchain
     langgraph/graph/state machine  → langgraph
     n8n/workflow nodes              → n8n
     langflow/flow builder           → langflow
     agent/chatbot/RAG/automation    → generic-workflow (platform TBD)

  2. project-profile.yaml frameworks → exact platform

  3. Detection result:
     Explicit PM mention → exact platform
     project-profile.yaml → exact platform
     Generic keywords → generic-workflow (AID recommends in WF7)
     No match → NOT a workflow project
```

### Platform-Specific Knowledge (Static Fallback)

For each platform, the skill contains minimal architecture patterns and Docker Compose templates as fallback when Qdrant is empty.

**LangChain + LangGraph:** StateGraph, checkpointer, tool-calling, human-in-the-loop, multi-agent supervisor, RAG with citations, streaming. Docker: app + vectorstore + db + frontend.

**N8N:** Workflow JSON definitions, AI Agent node, trigger nodes, custom nodes, credentials management, sub-workflows. Docker: n8n + db + workers.

**LangFlow:** Visual flow builder, LangChain component mapping, JSON export/import, auto-generated API endpoints, embedded chat widget. Docker: langflow + db.

### Knowledge Enrichment Priority

```
Qdrant KB (seed EPIC + internal) > Context7 live > Static fallback in skill
```

---

## Knowledge Acquisition Timing

### Hybrid Model

```
┌──────────────────────┬────────────┬──────────────────────────────────┐
│ Knowledge type       │ When       │ How                              │
├──────────────────────┼────────────┼──────────────────────────────────┤
│ Context7 docs        │ LIVE       │ Inline in brainstorming Step 1.  │
│ (current framework   │ (10-15s)   │ If Qdrant empty, fetch and       │
│  documentation)      │            │ store automatically.             │
├──────────────────────┼────────────┼──────────────────────────────────┤
│ GitHub repo patterns │ PRE-SEED   │ Seed research EPIC (one-time).   │
│ (architecture,       │ (minutes)  │ Studies repos, extracts          │
│  examples, best      │            │ patterns, stores in Qdrant.      │
│  practices)          │            │ Runs once per domain.            │
├──────────────────────┼────────────┼──────────────────────────────────┤
│ Internal KB          │ ONGOING    │ Accumulated from completed       │
│ (our experience,     │ (post-EPIC)│ EPICs. Curator extracts          │
│  lessons, patterns)  │            │ patterns after each EPIC.        │
├──────────────────────┼────────────┼──────────────────────────────────┤
│ Static fallback      │ ALWAYS     │ Hardcoded in                     │
│ (minimal patterns    │ (0s)       │ workflow-intelligence.md.         │
│  in skill)           │            │ Docker templates, basic arch.    │
└──────────────────────┴────────────┴──────────────────────────────────┘
```

### Live Context7 During Brainstorming

```
Brainstorming Step 1 (Context):
  1. Detect platform (e.g., "langchain")
  2. knowledge_find("langchain patterns architecture") → Qdrant
  3. IF Qdrant empty for this framework:
     → Notify PM: "No LangChain knowledge found. Fetching docs..."
     → Context7: resolve-library-id → query-docs
     → Parse → quality gate → store in Qdrant
     → Notify PM: "LangChain documentation studied (N chunks)."
  4. Continue brainstorming with knowledge available
```

---

## .aid-o/05-inputs/

### Directory Structure

```
.aid-o/
├── 01-plans/
├── 02-epics/
├── 03-config/
├── 04-engine/
└── 05-inputs/              ← NEW
    ├── README.md            ← short description of what goes here
    └── (user files)
```

### Brainstorming Integration

```
Step 1 (Context):
  1. Scan .aid-o/05-inputs/ (glob all files)
  2. IF files found:
     - Detect type (PDF, CSV, JSON, image, ...)
     - Read/summarize: PDF→structure, CSV→header+sample, JSON→schema, image→visual
     - Present to PM: "Found in 05-inputs/: invoice.pdf (3 pages, Czech), data.csv (1240 rows)"
  3. IF no files: don't mention (ask in WF4 if context unclear)
  4. Accept arbitrary paths from PM: "look at ./data/customers.json"
     → Read and analyze, do NOT copy to 05-inputs/
```

### /aid-init Extension

Add `mkdir -p .aid-o/05-inputs` and create README.md with usage instructions.

### /aid-help Extension

Add "Input Files" section explaining 05-inputs/ purpose, supported formats, and arbitrary path alternative.

---

## GitHub Repo Study & Example EPICs

### Seed Research EPIC

One-time EPIC that studies GitHub repositories and stores extracted patterns in Qdrant.

### Repositories per Platform

**LangChain/LangGraph (~12 repos):** langchain, langgraph, langgraphjs, langgraph-example, react-agent, open-agent-platform, awesome-LangGraph, langserve, chat-langchain, opengpts, razamehar/langgraph-workflow-orchestration, open-swe

**N8N (~8 repos):** n8n, n8n-nodes-starter, self-hosted-ai-starter-kit, n8n-workflow-templates, AWESOME-n8n-Examples, n8n-ai-automations, n8n-automation-2025-AI-Agent-Suite, n8n-workflows

**LangFlow (~5 repos):** langflow, langflow-embedded-chat, langflow-client-ts, openrag, langflow-twilio-voice

### Extraction per Repo

1. Architecture patterns (directory structure, entrypoint, config, docker-compose)
2. Code patterns (agent/workflow/chain definition, tools, state, error handling)
3. Docker patterns (services, volumes, env vars, health checks)
4. UI patterns (React components, backend communication, key features)
5. Best practices & gotchas (README warnings, recommended configs)

### Example EPICs

```
defaults/examples/
├── ai-workflows/
│   ├── langchain-rag-chatbot.md
│   ├── langgraph-multi-agent.md
│   ├── langgraph-react-agent.md
│   ├── n8n-ai-automation.md
│   ├── langflow-rag-pipeline.md
│   ├── doc-qa-chatbot.md
│   ├── email-assistant.md
│   ├── pdf-invoice-processor.md
│   ├── meeting-summarizer.md
│   ├── content-generator.md
│   ├── code-review-agent.md
│   └── data-extraction-pipeline.md
│
└── common-projects/
    ├── fastapi-crud-service.md
    ├── nextjs-fullstack.md
    ├── react-dashboard.md
    ├── landing-page.md
    ├── saas-starter.md
    ├── ecommerce-store.md
    └── api-with-auth.md
```

Each example EPIC follows the standard EPIC template with an added `## Inspiration` section referencing source repositories and key patterns.

### Brainstorming Usage

In Step 3 (Approaches): match PM topic against `defaults/examples/` frontmatter. If match found, offer PM: "(A) Use as base and adapt (B) Use as inspiration (C) Ignore template".

---

## High-Level Steps

### Phase 1 — Workflow Intelligence + Docker/MCP Preference

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | Create `workflow-intelligence.md` skill | New skill with: Platform Detection Protocol (keywords → platform hint, project-profile.yaml detection, detection result logic). Workflow Questioning Protocol (WF1-WF7 inserts into standard brainstorming flow, rules RULE 1-8). UI Derivation Logic (derivation table interaction×output → UI type, React default for code-first, native UI for no-code, special rules RULE 1-5). Platform-Specific Knowledge (static fallback: LangChain/LangGraph arch + Docker Compose template, N8N arch + template, LangFlow arch + template). Knowledge Enrichment Flow (priority: Qdrant > Context7 live > static fallback). | L |
| 2 | Extend `brainstorming.md` — workflow detection + inserts | In Step 1 (Context): add platform detection from conversation. If detected → activate workflow questioning protocol from `workflow-intelligence.md`. In Step 2 (Questions): insert WF1-WF6 at correct points in standard flow (after Scope→WF1, after Users→WF2+WF3, new WF4 after Users, after Constraints→WF5, after Success→WF6). After questions: WF7 platform recommendation (not a question, AID decides). In Step 3 (Approaches): integrate platform-specific architecture from workflow-intelligence.md. | M |
| 3 | Extend `brainstorming.md` — Docker/MCP preference (general) | Cross-cutting rules for ALL projects. In Step 3 (Approaches): if 2+ services or external dependencies → Docker Compose as part of every approach. If DB/filesystem/browser needed → recommend corresponding MCP servers. Docker+MCP combo rule: MCP servers inside Docker Compose. Decision matrix. If PM declines → record as constraint. Workflow-intelligence amplifies these rules for workflow projects. | M |
| 4 | Extend `planner.md` — Docker/MCP step injection | If Docker recommended (from brainstorming context): add step "Docker Compose setup" to plan (after architect, before backend). MCP setup as part of Docker step (never separate step). If workflow project: Docker Compose template per platform (from workflow-intelligence.md). | S |
| 5 | Extend `brainstorming.md` — .aid-o/05-inputs/ scan | In Step 1 (Context): scan `.aid-o/05-inputs/` automatically. If files found → analyze (PDF: structure, CSV: header+sample, JSON: schema, image: visual). Present PM summary of found files. In WF4 (Data): reference analyzed files. Accept paths outside 05-inputs/ from PM. | S |
| 6 | Extend `aid-init.md` — create 05-inputs/ | Add `mkdir -p .aid-o/05-inputs` to init process. Create `.aid-o/05-inputs/README.md` with description (what goes here, supported formats, read-only). | S |
| 7 | Extend `aid-help.md` — Input Files section | Add new section "Input Files" to help: what is 05-inputs/, how to use it, supported formats, alternative with arbitrary paths. | S |
| 8 | Extend `brainstorming.md` — example EPIC lookup | In Step 3 (Approaches): match PM topic against `defaults/examples/` (frontmatter search: platforms, ui, complexity). If match → offer PM: "(A) Use as base (B) Use as inspiration (C) Ignore". If A → adapt template to project-profile (paths, versions, Docker config). | S |

### Phase 2 — Knowledge Seed + Example EPICs

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | Seed Research — LangChain/LangGraph repos | Study ~12 repos. Extract: architecture patterns, code patterns, Docker patterns, UI patterns, best practices. Quality gate → store in Qdrant (~50-80 chunks). | L |
| 2 | Seed Research — N8N repos | Study ~8 repos. Extract: workflow patterns, AI node patterns, Docker setup, custom node patterns. Quality gate → Qdrant (~30-50 chunks). | M |
| 3 | Seed Research — LangFlow repos | Study ~5 repos. Extract: flow patterns, deployment patterns, embedding patterns. Quality gate → Qdrant (~20-30 chunks). | M |
| 4 | Create example EPICs — AI workflows | Based on studied patterns, create 12 example EPICs: langchain-rag-chatbot, langgraph-multi-agent, langgraph-react-agent, n8n-ai-automation, langflow-rag-pipeline, doc-qa-chatbot, email-assistant, pdf-invoice-processor, meeting-summarizer, content-generator, code-review-agent, data-extraction-pipeline. Each EPIC: context, goal, scope, steps, Docker Compose. Save to `defaults/examples/ai-workflows/`. | L |
| 5 | Create example EPICs — common projects | Create 7 example EPICs: fastapi-crud-service, nextjs-fullstack, react-dashboard, landing-page, saas-starter, ecommerce-store, api-with-auth. Source: Context7 docs + best practices. Save to `defaults/examples/common-projects/`. | M |
| 6 | Context7 live research — verification | For each platform, run Context7 query for current docs. Store in Qdrant as type=documentation. Update knowledge-base.yaml. Verify that live query works during brainstorming Step 1. | S |

## Constraints

- **Depends on P-20260220-1988 Phase 1** — Knowledge acquisition infrastructure (Context7, Qdrant documentation type, knowledge_find(), quality gates) must be implemented first.
- **Plugin documentation language** — All plugin files (skills, commands, agents) are written in English per CLAUDE.md convention.
- **No breaking changes** — All extensions to existing skills must be backward-compatible. Projects without workflow context behave identically to today.
- **YAGNI** — One skill per domain, no abstract domain plugin framework.
- **Docker is recommended, never forced** — PM can always decline Docker. Record as constraint, continue without it.
- **Budget** — Phase 1: ~$25-30, Phase 2: ~$30-40. Total: ~$55-70 across 2 EPICs.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| workflow-intelligence.md grows too large (500+ lines) | Medium | Medium | Clear section structure, each protocol is self-contained. Split into sub-skills if needed. |
| GitHub repos are archived/broken | Low | Low | Quality gate: reject repos with last commit >6 months. Fallback to static knowledge. |
| Context7 doesn't have a library | Medium | Low | WebSearch fallback (from P-20260220-1988). Static fallback in skill. |
| Workflow detection false positives | Low | Low | Conservative keyword matching. Generic keywords → only activate if 2+ match. |
| Example EPICs become outdated | Medium | Medium | Aging protocol from P-20260220-1988 Phase 2. Re-seed periodically. |
| Docker/MCP recommendation annoys users who don't want it | Low | Low | Single mention, PM declines → never mentioned again for this project. |

## Success Criteria

- [ ] AID detects workflow/agent project from conversation keywords and activates domain-specific questioning
- [ ] Workflow brainstorming walks PM through purpose, interaction, I/O, data, tools, scale — producing a functional workflow design
- [ ] AID recommends LangChain/LangGraph as default for complex agents, N8N/LangFlow as alternative for no/zero-code
- [ ] UI type is derived from workflow design (chat, dashboard, process UI) — not hardcoded
- [ ] No-code platforms (N8N, LangFlow) use their built-in UI — React only for code-first
- [ ] Docker Compose is recommended for ANY project with 2+ services or external dependencies
- [ ] MCP servers are recommended when DB, filesystem, or browser access is needed
- [ ] Docker + MCP combo: MCP servers proposed inside Docker Compose
- [ ] PM can decline Docker/MCP — recorded as constraint, never mentioned again
- [ ] `.aid-o/05-inputs/` is created by /aid-init and scanned by brainstorming automatically
- [ ] PM can reference files outside 05-inputs/ by path
- [ ] (Phase 2) Qdrant contains patterns from ~25 GitHub repositories across 3 platforms
- [ ] (Phase 2) 12 AI workflow example EPICs + 7 common project example EPICs exist in defaults/examples/
- [ ] (Phase 2) Brainstorming offers matching example EPICs when available
- [ ] (Phase 2) Context7 live research works inline during brainstorming (<15s)

## Next Steps

- [ ] Create EPIC for Phase 1 (Workflow Intelligence + Docker/MCP Preference)
- [ ] After Phase 1 completion: create EPIC for Phase 2 (Knowledge Seed + Example EPICs)
- [ ] Ensure P-20260220-1988 Phase 1 is implemented first (dependency)

---

**Last Updated:** 2026-02-21
