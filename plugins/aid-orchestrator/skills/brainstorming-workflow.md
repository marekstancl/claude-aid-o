# Brainstorming — Workflow Detection & Docker/MCP Integration

**Skill:** brainstorming-workflow
**Parent:** brainstorming
**Dependencies:** workflow-intelligence

---

## TL;DR

Sub-skill of brainstorming. Contains workflow detection integration (platform detection, WF1-WF7 question inserts, workflow-aware approaches) and cross-cutting Docker/MCP preference rules. Loaded by the brainstorming skill when relevant — non-workflow projects never see this content.

---

## Workflow Detection Integration

When a workflow/agent project is detected, the brainstorming run is supplemented with
workflow-specific questioning and platform recommendation. Detection runs automatically
before the first question. Non-workflow projects are completely unaffected.

**Principle:** Workflow detection is non-blocking and backward-compatible. When no workflow
is detected, the brainstorming run proceeds identically to its behavior before this
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
   - Activate WF7 platform recommendation for Step 2->3 transition

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

After Scope question  ->  + WF1: PURPOSE
                           "What should the agent/workflow do specifically?"
                           Follow-up: example scenario (user does X, agent returns Y)

After Users question  ->  + WF2: INTERACTION MODEL
                           "How will users communicate with the agent/workflow?"
                           Options: Chat / Upload & Process / Trigger-based /
                                    Dashboard / Combination

                      ->  + WF3: OUTPUT
                           "What is the output? What does the user get?"
                           Options: Text / Structured data / Action / File / Combination

                      ->  + WF4: DATA & INPUTS
                           Uses results from Sample File Analysis (Step 1).
                           If files were analyzed, reference them:
                             "I found data.csv (1,240 rows) and config.json
                              in your inputs. What other data will the
                              workflow process?"
                           If no files were analyzed, ask from scratch:
                             "What data will the workflow process?"
                           Probe: type, volume, format.

After Constraints     ->  + WF5: TOOLS & INTEGRATIONS
  question                "What external services or tools will the workflow connect to?"
                           Options: None / External APIs / Database /
                                    Cloud services / Other LLM/AI services
                           Derives MCP server recommendations from answer.

After Success         ->  + WF6: USABILITY SUCCESS
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
          in brainstorming-knowledge.md). Results are available to WF4.
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
     -> Confirm the detected platform to PM.
   - IF platform_hint == generic-workflow:
     -> AID decides based on complexity signals collected from WF1-WF6 answers.
     -> complex_signals >= 3 -> recommend LangChain/LangGraph (code-first)
     -> complex_signals < 3  -> recommend N8N or LangFlow (visual/low-code)

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
final authority. Once PM declines, the topic is closed for the remainder of the run.

### Docker Preference Rules

```
RULE D1: 2+ services -> Docker Compose recommended.
         "Services" includes: application server, database, cache, message queue,
         vector store, search engine, or any process that runs independently.

RULE D2: External dependencies (DB, cache, vector store) -> Docker recommended.
         Even a single-service app benefits from Docker when it depends on
         infrastructure that varies across developer machines.

RULE D3: Reproducibility important (team project, CI/CD) -> Docker recommended.
         If the project will be developed by more than one person, or if it uses
         CI/CD pipelines, Docker Compose ensures consistent environments.

RULE D4: Workflow/agent project -> Docker STRONGLY recommended.
         Amplified by workflow-intelligence.md. Workflow projects almost always have
         2+ services (app + vector store, app + database, multi-agent containers).

EVALUATION ORDER:
  1. Check RULE D1 first (service count is the strongest signal).
  2. If D1 does not trigger, check D2 (external dependencies).
  3. If D2 does not trigger, check D3 (reproducibility).
  4. D4 is an overlay — it elevates "recommended" to "STRONGLY recommended"
     when workflow_detected == true, but it never triggers on its own.
  5. If no rule triggers -> Docker is NOT recommended. Do not mention it.
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
   -> docker_recommended = true | false
   -> docker_strength = "recommended" | "strongly recommended"

3. IF docker_recommended:
   - Every approach includes Docker Compose as part of its architecture section.
   - The planner adds a "Docker Compose setup" step in the plan
     (after architect, before backend implementation).
   - Ask PM ONCE (before presenting approaches):
     "I recommend Docker Compose for this project ({reason}).
      Include in all approaches? (Y/N)"

   - IF PM says Y (or equivalent):
     -> Proceed. Docker Compose is part of all approaches.

   - IF PM says N (or equivalent):
     -> Record constraint: "PM decided: no Docker, local setup."
     -> Remove Docker from all approaches.
     -> Do not mention Docker again for this project.
     -> Planner omits the Docker Compose step.

4. IF docker_recommended == false:
   - Do not mention Docker. No step, no compose, no question.
   - Docker is invisible in the run.
```

### MCP Server Preference Rules

```
RULE M1: Project uses database -> Database MCP server recommended.
         (PostgreSQL MCP, MySQL MCP, SQLite MCP — match to the project's DB choice.)

RULE M2: Project has GitHub repository -> GitHub MCP recommended.
         (For issue management, PR automation, code search during development.)

RULE M3: Project needs advanced file operations -> Filesystem MCP recommended.
         (Bulk file manipulation, template generation, workspace scanning.)

RULE M4: Project needs web browsing or scraping -> Playwright/Browser MCP recommended.
         (E2E testing, web scraping, page interaction.)

RULE M5: Project uses framework with docs on Context7 -> Context7 MCP recommended.
         (Up-to-date framework documentation retrieval for agents.)

RULE M6: Workflow/agent project -> MCP servers for agent tools.
         Amplified by workflow-intelligence.md. Specific MCP servers are derived from
         the WF5 (Tools & Integrations) answer during workflow questioning.

EVALUATION:
  - Apply each rule independently. Multiple rules can fire simultaneously.
  - Collect all recommendations into mcp_recommendations (list of MCP server names).
  - If no rule fires -> mcp_recommendations is empty. Do not mention MCP.
```

### MCP + Docker Interaction

```
IF docker_recommended AND mcp_recommendations (non-empty):
  -> Propose MCP servers INSIDE Docker Compose.
  -> "MCP servers run in Docker containers alongside your application."
  -> Docker Compose YAML includes MCP server service definitions.

IF docker_recommended == false AND mcp_recommendations (non-empty):
  -> Propose MCP servers as local processes or configuration entries.
  -> No Docker Compose involvement.

IF PM declines MCP:
  -> Record constraint: "PM decided: no MCP servers, direct SDK/libraries."
  -> Alternative: use native SDKs, client libraries, or direct API calls.
  -> Do not mention MCP again for this project.

IF PM declines Docker but accepts MCP:
  -> MCP servers run locally (not in containers).
  -> Adjust setup instructions accordingly.
```

### Decision Matrix

```
+--------------------------+----------------+------------------+
| Situation                | Docker         | MCP servers      |
+--------------------------+----------------+------------------+
| 1 service, no DB         | —              | —                |
| 1 service + DB           | recommended    | DB MCP           |
| 2+ services              | recommended    | as needed        |
| 2+ services + DB + cache | recommended    | DB MCP + others  |
| Workflow/agent project   | STRONGLY rec.  | STRONGLY rec.    |
| Team project / CI/CD     | recommended    | as needed        |
| PM declined Docker       | —              | as needed (local)|
| PM declined MCP          | as applicable  | —                |
| PM declined both         | —              | —                |
+--------------------------+----------------+------------------+

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
  5. Do not mention Docker again in this brainstorming run.
  6. Do not ask again, do not hint, do not include as "optional."

IF PM declines MCP:
  1. Record constraint: "PM decided: no MCP servers, direct SDK/libraries."
  2. Remove MCP server references from all approach architectures.
  3. Replace with native SDK/library alternatives where applicable.
  4. Do not mention MCP again in this brainstorming run.

IF PM declines both:
  1. Record both constraints.
  2. Approaches use local setup with direct dependencies.
  3. Run proceeds as if Docker/MCP rules do not exist.

CONSTRAINT RECORDING:
  Constraints are stored in the brainstorming run state and carry forward to:
  - Plan document (Constraints section)
  - Planner step generation (omit Docker/MCP steps)
```

---

## Reference Files

- `skills/brainstorming.md` — parent skill (core process rules and protocols)
- `skills/brainstorming-knowledge.md` — knowledge acquisition and file analysis sub-skill
- `skills/workflow-intelligence.md` — Platform Detection Protocol, Workflow Questioning Protocol (WF1-WF7), UI Derivation Logic, platform-specific knowledge

---

**Last Updated:** 2026-02-27
