# Brainstorming — Interactive Design and Planning Skill

**Skill:** brainstorming
**Dependencies:** run-management, planner, plan-writing
**Attribution:** Inspired by [superpowers:brainstorming](https://github.com/jessevincent/claude-superpowers) (MIT License, Jesse Vincent)

---

## TL;DR

This skill defines how AID conducts interactive brainstorming runs with the PM. It governs the questioning protocol, approach exploration, incremental design validation, and plan document generation.

The brainstorming skill is invoked by the `/aid-brainstorm` command. It produces one artifact: a validated plan document. EPIC creation is a separate step via `/aid-plan-epic`.

**Input:** PM's idea or topic + interactive Q&A
**Output:** Plan document (`.aid-o/plans/P-*.md`)

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
11. **ALWAYS present initial analysis before first question** — the AI must demonstrate understanding of the topic before asking anything (see Initial Analysis Phase section)
12. **ALWAYS present 2-3 options with recommendation at every directional decision point** — questions involving direction, approach, or trade-off choices must use structured options with labeled alternatives and a recommended choice with reasoning
13. **ALWAYS explain why alternatives are less suitable** — for each recommendation, state not just why the chosen option is good but specifically why the other options are less appropriate for this context
14. **ALWAYS delegate plan writing to the plan-writing skill** — brainstorming collects and validates design; plan-writing skill writes the exhaustive plan document with quality gates, forbidden phrase detection, and completeness verification (see Document Generation Protocol RULE 8)

---

## Key Principles

1. **Detail by Default** — Include field names, endpoint paths, error codes, data types, failure modes, and file structures without PM asking. PM should never need to say "add more detail."
2. **Explore Alternatives** — Always offer 2-3 options with genuine tradeoffs, effort estimates (S/M/L), and risk. State the recommended option with reasoning.
3. **Incremental Validation** — Validate at every stage: questions → approach selection → section-by-section review → final approval. Never write files without explicit PM approval.
4. **YAGNI** — Propose the simplest solution that meets stated requirements. Complexity is a cost; justify every layer of indirection.
5. **PM Attention is the Bottleneck** — One question at a time, multiple choice over open-ended, short summaries before detailed sections.

---

## Initial Analysis Phase

Before asking any questions, the AI must present a brief structured analysis of the PM's topic. This ensures shared understanding, surfaces misinterpretations early, and makes subsequent questions more targeted.

### When It Triggers

This phase activates after the AI has read the PM's topic description and all gathered context (project profile, input files) but **before** the questioning phase (Step 1) begins. It is mandatory for every brainstorming run.

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
RULE 8: The analysis must reflect any input files provided. If PM provided files
        in .aid-o/05-inputs/, reference them briefly in the analysis.
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
RULE 9: Every question that involves a directional choice MUST present 2-3
        structured options with labels (A/B/C), descriptions, and a
        recommendation with reasoning.
RULE 10: For each recommended option, briefly state why the alternatives are
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
RULE 8 (Hard Gate): Before presenting approaches to PM, validate count >= 2.
        If fewer than 2 approaches generated, DO NOT proceed to presentation.
        Generate additional approaches until minimum 2 are available.
        This is a blocking validation — the approach presentation step cannot
        complete without at least 2 genuinely different approaches.
        Self-check: COUNT(approaches) >= 2 → proceed. Otherwise → loop back
        and generate more approaches. No exceptions.
RULE 9 (Anti-Shortcut): NEVER skip approach exploration, even for topics
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
RULE 6: PLAN-WRITING DELEGATION (Step 8) — Collect all approved content from Steps 3-7
        (questions, chosen approach, design sections, PM modifications, final approval).
        Invoke plan-writing skill in Mode A (Post-Brainstorming), passing all collected
        sections + project context. The plan-writing skill handles document structure,
        Forbidden Phrase Detection, Traceability Verification, Completeness Gate (16-point),
        writing the plan file, and post-write handoff. After plan-writing completes,
        brainstorming is DONE.
RULE 7: Brainstorming does NOT create EPICs. EPIC creation is handled by /aid-plan-epic
        (offered in plan-writing handoff), which delegates file creation to `aid-plan-to-epic.sh`.
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
1. Read .aid-o/config/language.yaml → document_language
2. Check scope flags:
   - scope.plans: true → plan document uses document_language
   - scope.plans: false → plan document uses English
3. If language.yaml does not exist → use English (EN)
4. If document_language is unsupported → use fallback_language from config
```

### Language Configuration Reference

```yaml
# .aid-o/config/language.yaml
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

Steps: (1) PM invokes `/aid-brainstorm [topic]` → (2) read project context → (3) Initial Analysis Phase → (4-7) questions, approaches, design, approval → (8) delegate to plan-writing skill → plan-writing presents next steps.

### Aborting a Brainstorming Run

PM aborts by saying "stop", "cancel", "abort", or similar.

- **Before Step 8** (no files written): end gracefully, no files created.
- **During Step 8**: plan-writing handles cleanup; ask PM "Keep partial plan file? (Y/N)".

### Re-opening a Brainstorming Run

When PM selects "Re-open brainstorming" in the plan-writing handoff:

1. Load the existing plan file and display already-approved sections
2. Return to Step 3 with existing context retained (previous answers are still valid)
3. New requirements **ADD** — never overwrite approved sections; new answers append
4. Only modified sections go through Step 6 re-approval; unchanged sections stay approved
5. Re-write the plan file (Step 8) and return to handoff

**Abort during re-open:** Most recently written plan file is preserved. No rollback.

### Transitioning to Execution

Plan-writing skill presents next steps: (A) Create EPIC via `/aid-plan-epic {plan_path}`, (B) Review plan first, (C) Re-open brainstorming, (D) Stop. `/aid-plan-epic` runs `aid-auto-pipeline.sh` to create all artifacts deterministically.

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

### Pattern: AI Platform / Multi-Tenant (e.g., VULCAN)

```
Questions focus on: tenant isolation model, agent capabilities, data privacy
Approaches focus on: single vs. multi-tenant DB, agent orchestration pattern
Design sections: Architecture (hub-and-spoke), Data Model (per-tenant schema), API
Roles typically: architect (opus) → backend (langgraph role) → security (sql-isolation) → qa
Note: Apply `langgraph`, `python-async`, `sql-isolation` role cards from role-cards.md
```

### Pattern: New Greenfield Project

```
Questions focus on: user needs, business model, MVP scope, team size
Approaches focus on: tech stack selection, architecture style, deployment target
Design sections: full Architecture, Data Model, API, Frontend, Testing, Infrastructure
Roles typically: all roles (architect → domain → backend + frontend → qa + security + observability → docs → release)
```

---

## Reference Files

- `commands/aid-brainstorm.md` — command that invokes this skill (8-step flow)
- `skills/plan-writing.md` — Step 8 delegation (exhaustive plan doc, quality gates, handoff)
- `commands/aid-plan-epic.md` — next step: EPIC creation from plan
- `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` — Plan.md → EPIC.md → plan.json → run.md → queue
- `defaults/templates/plan.md` — base plan document template
- `skills/planner.md` — how plans become Plan JSON
- `skills/run-management.md` — lifecycle integration
- `.aid-o/config/language.yaml` — document language configuration

---

**Last Updated:** 2026-03-03
