# Brainstorming — Interactive Design and Planning Skill

**Skill:** brainstorming
**Dependencies:** run-management, planner, workflow-intelligence, plan-writing
**Attribution:** Inspired by [superpowers:brainstorming](https://github.com/jessevincent/claude-superpowers) (MIT License, Jesse Vincent)

---

## TL;DR

This skill defines how AID conducts interactive brainstorming runs with the PM. It governs the questioning protocol, approach exploration, incremental design validation, and plan document generation. When knowledge acquisition is configured, brainstorming is augmented with relevant documentation, patterns, and lessons from past projects to inform questions (Step 1) and approach proposals (Step 3).

The brainstorming skill is invoked by the `/aid-brainstorm` command. It produces one artifact: a validated plan document. EPIC creation is a separate step via `/aid-plan-epic`.

**Input:** PM's idea or topic + interactive Q&A (+ knowledge context when available)
**Output:** Plan document (`.aid-o/01-plans/P-*.md`)

---

## MUST Rules

1. **ALWAYS ask one question at a time** — never batch multiple questions in one message
2. **ALWAYS prefer multiple choice** — open-ended only when options cannot be predicted
3. **ALWAYS provide detailed output by default** — PM should never ask for more detail
4. **ALWAYS propose 2-3 approaches** — never present a single option
5. **ALWAYS get section-by-section approval** — never skip incremental validation
6. **ALWAYS write files only after explicit PM approval** — Step 7 must be approved
7. **ALWAYS follow the language split** — conversation in PM language, documents in configured language
8. **ALWAYS apply YAGNI** — do not add complexity the requirements do not demand
9. **ALWAYS cross-reference** — plan references the topic and brainstorming decisions
10. **NEVER modify existing files** — brainstorming only creates a new plan file
11. **ALWAYS run Platform Detection Protocol before the first question** — when workflow is detected, inserts activate transparently; when not, brainstorming is unchanged
12. **NEVER exceed 12 total questions** — standard questions (3-7) plus workflow inserts (0-5) combined
13. **ALWAYS recommend Docker Compose when project has 2+ services** — PM can decline but recommendation is mandatory; applies to ALL project types, not just workflows
14. **NEVER mention Docker/MCP again after PM declines** — record as constraint once, respect PM's decision for the entire run, do not hint or include as optional
15. **ALWAYS present initial analysis before first question** — the AI must demonstrate understanding of the topic before asking anything (see Initial Analysis Phase section)
16. **ALWAYS present 2-3 options with recommendation at every directional decision point** — questions involving direction, approach, or trade-off choices must use structured options with labeled alternatives and a recommended choice with reasoning
17. **ALWAYS explain why alternatives are less suitable** — for each recommendation, state not just why the chosen option is good but specifically why the other options are less appropriate for this context
18. **ALWAYS delegate plan writing to the plan-writing skill** — brainstorming collects and validates design; plan-writing skill writes the exhaustive plan document with quality gates, forbidden phrase detection, and completeness verification (see Document Generation Protocol RULE 8)

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

## Initial Analysis Phase

Before asking any questions, the AI must present a brief structured analysis of the PM's topic. This ensures shared understanding, surfaces misinterpretations early, and makes subsequent questions more targeted.

### When It Triggers

This phase activates after the AI has read the PM's topic description and all gathered context (project profile, knowledge results, input files) but **before** the questioning phase (Step 1) begins. It is mandatory for every brainstorming run.

### Analysis Protocol

```
RULE 1: After reading the PM's topic and all available context, PRESENT a structured
        analysis BEFORE asking any questions. This is mandatory.
RULE 2: The analysis output must be 5-8 lines maximum. Conciseness is critical —
        PM's attention is the bottleneck.
RULE 3: Structure the analysis with these four elements:
        - "What I understand from your topic" — paraphrase the request + key aspects identified
        - "Key dimensions I see" — technical, organizational, integration, risk dimensions
        - "Potential challenges" — what could go wrong, what needs careful decisions
        - "What I need to clarify" — preview of question areas (not the questions themselves)
RULE 4: After presenting the analysis, WAIT for PM confirmation before proceeding
        to questions. Ask: "Is this understanding correct, or should I adjust
        my focus before we continue?"
RULE 5: If PM corrects misunderstandings, ACKNOWLEDGE the correction, briefly restate
        the corrected understanding, and then proceed to questioning.
RULE 6: For trivial or straightforward topics, state "Straightforward topic, minimal
        analysis needed" and keep the analysis to 3-4 lines. Skip dimensions or
        challenges that do not apply.
RULE 7: Do NOT turn this phase into a mini-brainstorm. No solution proposals,
        no architecture suggestions — only understanding and scoping.
RULE 8: The analysis must reflect knowledge context when available. If knowledge
        search returned relevant patterns or past decisions, reference them briefly
        (e.g., "I see a similar feature was built in project X").
```

### Example Output

```
**What I understand from your topic:** You want to add webhook support so external
services can subscribe to events in the system — primarily for integration partners.

**Key dimensions I see:** API design (endpoint structure, auth), event model (which
events, payload format), reliability (retry logic, delivery guarantees), security.

**Potential challenges:** Ensuring at-least-once delivery without duplicates; scaling
webhook dispatch without blocking the main request path; secret rotation for signatures.

**What I need to clarify:** Target consumers and their technical sophistication;
expected event volume; whether this replaces or supplements existing polling APIs.

Is this understanding correct, or should I adjust my focus before we continue?
```

---

## Knowledge-Augmented Brainstorming

**ACTION REQUIRED:** In Step 1, check if `memory-config.yaml` has `knowledge.enabled: true`. If yes, **READ `skills/brainstorming-knowledge.md`** and follow its protocols for knowledge search and file analysis. If knowledge is not configured, skip this section entirely.

When knowledge acquisition is configured, brainstorming is augmented with relevant documentation, patterns, and lessons from past projects. Knowledge is strictly non-blocking — when unavailable, brainstorming works identically to a non-augmented run.

**Integration points:**
- **Step 1** — READ `skills/brainstorming-knowledge.md` → run Pre-brainstorming Knowledge Search + Sample File Analysis (`.aid-o/05-inputs/`)
- **Step 3** — Follow `skills/brainstorming-knowledge.md` → Approach-Informed Knowledge Search + Example EPIC Lookup

**Key guarantees:** 5-second timeout per knowledge call, max 3 calls per run, graceful degradation for all failure scenarios, PM-provided file paths analyzed on demand.

---

## Workflow Detection & Docker/MCP Integration

**ACTION REQUIRED:** In Step 1, run the Platform Detection Protocol (scan PM's topic for workflow keywords: agent, chatbot, RAG, workflow, pipeline, automation, LangChain, LangGraph, N8N, LangFlow, multi-agent, AI workflow, LLM agent, tool-calling, assistant). If `workflow_detected == true`, **READ `skills/brainstorming-workflow.md`** and follow its protocols for workflow questioning (WF1-WF6), platform recommendation (WF7), and Docker/MCP analysis. If no workflow detected, **STILL READ `skills/brainstorming-workflow.md` → Docker/MCP Preference Rules** section to evaluate Docker recommendation based on service count.

Docker and MCP recommendations are cross-cutting (apply to ALL projects based on service count, external dependencies, and reproducibility needs). Workflow projects amplify these to "STRONGLY recommended."

**Integration points:**
- **Step 2** — READ `skills/brainstorming-workflow.md` → Platform Detection, workflow question inserts (WF1-WF6)
- **Step 2→3 transition** — Follow `skills/brainstorming-workflow.md` → WF7 Platform Recommendation
- **Step 3** — Follow `skills/brainstorming-workflow.md` → Workflow-aware approaches (W1-W5), Docker/MCP analysis

**Key guarantees:** PM's decline of Docker/MCP is final and respected immediately, constraints carry forward to plan document, non-workflow projects see zero difference.

---

## Process Rules

### Questioning Protocol

```
RULE 1: ONE question at a time. Never ask 2+ questions in one message.
RULE 2: ALWAYS use MULTIPLE CHOICE with recommendation (A/B/C — recommended: X because Y).
        Open-ended ONLY for factual questions (names, URLs, numbers) where options
        cannot be predicted.
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
        at the points defined in skills/brainstorming-workflow.md.
        Total questions (standard + workflow) must not exceed 12.
        See skills/workflow-intelligence.md for insert details.
RULE 10: Every question that involves a directional choice MUST present 2-3
         structured options with labels (A/B/C), descriptions, and a
         recommendation with reasoning.
RULE 11: For each recommended option, briefly state why the alternatives are
         less suitable — not just why the recommendation is good.
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
        rules (W1-W5) from skills/brainstorming-workflow.md.
        Both recommended and alternative platform variants are required.
RULE 9 (Hard Gate): Before presenting approaches to PM, validate count >= 2.
        If fewer than 2 approaches generated, DO NOT proceed to presentation.
        Generate additional approaches until minimum 2 are available.
        This is a blocking validation — the approach presentation step cannot
        complete without at least 2 genuinely different approaches.
        Self-check: COUNT(approaches) >= 2 → proceed. Otherwise → loop back
        and generate more approaches. No exceptions.
RULE 10 (Anti-Shortcut): NEVER skip approach exploration, even for topics
        that appear to have an obvious or clear-best-choice solution. Every
        topic gets 2-3 approaches with full trade-off analysis. "Obvious"
        solutions still have alternatives worth exploring — infrastructure
        choices, library options, architectural patterns, build-vs-buy.
        Skipping approach exploration is NEVER acceptable. If the topic seems
        trivial, the alternatives may be lighter-weight or simpler variants,
        but they must still be presented with pros, cons, effort, and risk.
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
RULE 1: NEVER write files without explicit PM approval (Step 7 in command flow).
RULE 2: Plan document is written by the plan-writing skill (skills/plan-writing.md).
        Brainstorming delegates plan writing to plan-writing, passing all approved
        sections as input. The plan-writing skill handles document structure, quality
        gates, forbidden phrase detection, and completeness verification.
RULE 3: Include all design details from the approved sections — do not summarize
        or omit details that were approved. The plan-writing skill enforces this
        through its Traceability Protocol and Completeness Gate.
RULE 4: If PM approved a modification, the modified version goes into the document
        (not the original).
RULE 5: Generate proper plan IDs per `skills/epic-orchestration.md` ID Generation section:
        Plan: P{NNN} (from counter.yaml).
RULE 6: PLAN-WRITING DELEGATION (Step 8) — When brainstorming reaches Step 8:
        1. Collect all approved sections from Steps 3-7:
           - Step 3 (Questions): PM's answers to every clarification question
           - Step 4 (Approaches): PM's chosen approach and any modifications
           - Step 5 (Design): Architecture, Data Model, API, Implementation,
             Testing, Risks — all approved content
           - Step 6 (Sections): PM's section-by-section approvals and modifications
           - Step 7 (Approval): PM's final approval
        2. Invoke the plan-writing skill in Mode A (Post-Brainstorming):
           - Pass ALL collected sections as input
           - Pass project context from Step 1
           - Pass knowledge context (if active)
        3. The plan-writing skill handles:
           - Exhaustive plan document structure (detailed per-step format)
           - Forbidden Phrase Detection (hard gate)
           - Traceability Verification (every brainstorming output → plan section)
           - Completeness Gate (16-point verification, hard gate)
           - Writing the plan file to .aid-o/01-plans/
           - Post-write handoff (next steps including EPIC creation offer)
        4. After plan-writing completes, brainstorming is DONE.
        This delegation ensures zero information loss between brainstorming
        discussions and the written plan document.
RULE 7: Brainstorming does NOT create EPICs. EPIC creation is handled by
        /aid-plan-epic, offered as an option in plan-writing's Post-Write Handoff.
        As of Plan P018, /aid-plan-epic delegates EPIC file creation to the
        `aid-plan-to-epic.sh` script — the LLM does not generate EPIC content
        inline. The script reads the plan document and writes EPIC files deterministically.
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

## Brainstorming Run Lifecycle

### Starting a Brainstorming Run

```
1. PM invokes /aid-brainstorm [topic]
2. Read project context (Step 1 of command flow)
3. Enter analysis and questioning phase (Steps 2-3)
4. Continue through Steps 4-7 per command flow (approaches, design, sections, approval)
5. Delegate plan writing to plan-writing skill (Step 8)
6. Plan-writing skill presents next steps (EPIC creation, review, etc.)
```

### Aborting a Brainstorming Run

PM can abort at any point by saying "stop", "cancel", "abort", or similar.

```
If abort BEFORE Step 8 (no files written):
  → Acknowledge, end gracefully. No files created.
  → "Brainstorming ended. No files were created. Run /aid-brainstorm to start again."

If abort DURING Step 8 (plan partially written):
  → Plan-writing skill handles cleanup. Ask PM: "Keep the partial plan file? (Y/N)"
  → If Y: keep plan file.
  → If N: delete plan file.
```

### Re-opening a Brainstorming Run

When PM selects "Re-open brainstorming" in the plan-writing handoff:

1. **Load existing plan** — Read the plan file written in Step 8
2. **Display approved sections** — Show PM which sections were already approved (from Step 6)
3. **Return to Step 3** — Resume questioning with existing context loaded
   - The brainstorming context from Step 1 is still valid (project state hasn't changed)
   - Previous answers from Step 3 are retained as context
4. **New requirements ADD** — Never overwrite approved sections. New answers supplement existing ones:
   - New scope items are APPENDED to the scope list
   - New constraints are APPENDED
   - If PM wants to MODIFY an approved section, they must explicitly say so
5. **Re-present modified sections** — Only sections that changed go through Step 6 approval again
   - Unchanged sections remain approved
   - Modified sections require re-approval
6. **Re-write plan file** — Update the plan document with additions (Step 8)
7. **Return to handoff** — Plan-writing skill presents next steps again

**State management:** The brainstorming run maintains a list of approved sections and their content. When re-opening, this list is loaded to prevent re-asking about already-decided items.

**Abort during re-open:** If PM says "stop" or "cancel" during a re-open loop, the most recently written plan file is preserved. No rollback occurs.

### Transitioning to Execution

After brainstorming completes, the plan-writing skill presents next steps:

```
/aid-brainstorm → Plan document
    ├── (A) Create EPIC → /aid-plan-epic {plan_path}
    ├── (B) Review plan first → PM edits, then /aid-plan-epic
    ├── (C) Re-open brainstorming → add more items
    └── (D) Stop here
```

`/aid-plan-epic` accepts Plan files directly — no separate EPIC authoring needed.
The command runs the `aid-auto-pipeline.sh` script which creates all artifacts:
EPIC files, plan.json, run.md, and queue entries — all deterministically from
the plan document without requiring LLM involvement in the file creation steps.

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
Reference: skills/brainstorming-workflow.md + skills/workflow-intelligence.md for full protocol details
```

---

## Reference Files

### Sub-Skills (loaded on demand)

- `skills/brainstorming-knowledge.md` — knowledge acquisition, file analysis, example EPIC lookup (loaded when knowledge is configured)
- `skills/brainstorming-workflow.md` — workflow detection, WF1-WF7 inserts, Docker/MCP preference rules (loaded when workflow detected or Docker/MCP evaluation needed)

### Related Files

- `commands/aid-brainstorm.md` — command that invokes this skill (8-step flow)
- `skills/plan-writing.md` — plan writing skill (Step 8 delegation — writes exhaustive plan document, presents next steps)
- `commands/aid-write-plan.md` — standalone plan writing command
- `commands/aid-plan-epic.md` — next step: create EPIC from plan (offered by plan-writing handoff); delegates to `aid-auto-pipeline.sh` for all file creation
- `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` — script that converts plan documents into EPIC files (invoked by `/aid-plan-epic`)
- `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` — orchestrates the full pipeline: Plan.md → EPIC.md → plan.json → run.md → queue
- `defaults/templates/plan.md` — base plan document template (extended by plan-writing skill)
- `skills/planner.md` — how plans become Plan JSON (downstream from brainstorming)
- `skills/run-management.md` — End of Brainstorming Protocol (lifecycle integration)
- `skills/knowledge-acquisition.md` — knowledge pipeline: `knowledge_find()`, `find_relevant_examples()`, and `adapt_example()`
- `skills/workflow-intelligence.md` — Platform Detection Protocol, Workflow Questioning Protocol (WF1-WF7), UI Derivation Logic
- `.aid-o/03-config/language.yaml` — document language configuration

---

**Last Updated:** 2026-02-28
