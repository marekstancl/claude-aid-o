---
name: brainstorming
description: Interactive 9-step design and planning — questions, approaches, risk assessment, design validation, context persistence
user_invocable: false
---

# Brainstorming — Interactive Design and Planning Skill

**Skill:** brainstorming
**Dependencies:** run-management, planner, plan-writing
**Attribution:** Inspired by [superpowers:brainstorming](https://github.com/jessevincent/claude-superpowers) (MIT License, Jesse Vincent)

---

## TL;DR

Invoked by `/aid-brainstorm`. Governs questioning protocol, approach exploration, incremental design validation, and plan document generation. Produces one artifact: a validated plan document. EPIC creation is a separate step via `/aid-plan --epic`.

**Input:** PM's idea or topic + interactive Q&A
**Output:** Plan document (`.aid-o/plans/P-*.md`)

---

## MUST Rules

1. **One question at a time** — never batch multiple questions in one message
2. **Prefer multiple choice** — open-ended only when options cannot be predicted
3. **Detailed output by default** — PM should never ask for more detail
4. **2-3 approaches always** — never present a single option
5. **Section-by-section approval** — never skip incremental validation
6. **Write files only after explicit PM approval** — Step 7 must be approved
7. **Follow the language split** — conversation in PM language, documents in configured language
8. **YAGNI** — do not add complexity the requirements do not demand
9. **Cross-reference** — plan references the topic and brainstorming decisions
10. **Never modify existing files** — brainstorming only creates a new plan file
11. **Initial analysis before first question** — see Initial Analysis Phase
12. **Delegate plan writing to plan-writing skill** — brainstorming collects and validates; plan-writing writes the document with quality gates
13. **Recommend Docker Compose when design reveals 2+ services** — PM can decline; if declined, record as constraint and do not raise again

---

## Key Principles

1. **Detail by Default** — Include field names, endpoint paths, error codes, data types, failure modes, and file structures without PM asking.
   - When in doubt, be more specific rather than less. PM can always say "simplify."
2. **Explore Alternatives** — Always offer 2-3 options with genuine tradeoffs, effort estimates (S/M/L), and risk. State the recommended option with reasoning.
   - Each option must be a real alternative, not a strawman. If PM asks "what do you recommend?", give a direct answer.
3. **Incremental Validation** — Validate at every stage: questions → approach selection → section-by-section review → final approval. Never write files without explicit PM approval.
4. **YAGNI** — Propose the simplest solution that meets stated requirements. Complexity is a cost; justify every layer of indirection.
   - Do not propose microservice architecture for a single-service problem. Default to simpler when scope is ambiguous.
5. **PM Attention is the Bottleneck** — One question at a time, multiple choice over open-ended, short summaries before detailed sections.
   - Accept brief answers and infer reasonable defaults.

---

## Initial Analysis Phase

Activates after reading PM's topic and all context, before questioning begins. Mandatory for every run. Presents a brief structured analysis to surface misinterpretations early.

### Analysis Protocol

```
RULE 1: After reading the PM's topic and all available context, SEARCH for related
        prior work: glob .aid-o/plans/*.md and .aid-o/epics/*.md for keyword overlap
        with the topic. If matches found, include a "Prior work found" line listing
        plan IDs and titles. If no matches, state "No prior plans overlap."
        Then PRESENT a structured analysis BEFORE asking any questions. Mandatory.
RULE 2: The analysis output must be 5-8 lines maximum. Conciseness is critical —
        PM's attention is the bottleneck.
RULE 3: Structure the analysis with these elements:
        - "Understanding" — paraphrase the request + key aspects identified
        - "Dimensions" — technical, organizational, integration, risk dimensions
        - "Challenges" — what could go wrong, what needs careful decisions
        - "To clarify" — preview of question areas (not the questions themselves)
        - "Prior work" — related plans/EPICs found (only if matches exist)
RULE 4: After presenting the analysis, WAIT for PM confirmation before proceeding.
        Ask: "Is this understanding correct, or should I adjust my focus?"
RULE 5: If PM corrects misunderstandings, ACKNOWLEDGE and restate corrected
        understanding, then proceed to questioning.
RULE 6: For trivial topics, keep analysis to 3-4 lines. Skip dimensions/challenges
        that don't apply.
RULE 7: No solution proposals or architecture suggestions — understanding and scoping only.
RULE 8: Reference any input files PM provided in .aid-o/inputs/ briefly in analysis.
```

**Mockup detection:** After scanning inputs, detect mockup files (PNG, JPG, TSX, CSS, HTML).
Present to PM: "Found {N} mockup files. Associate with this plan? (Y/N)". Note for copy in Step 8.
During conversation, PM may provide mockup references in 3 forms:
- **GitHub repo URL** → note as `source_type: github`
- **Google AI Studio URL** → note as `source_type: ai_studio`
- **Local file path** (image or source) → note as `source_type: image` or `github` (local source)
All mockup references are collected and processed in Step 8 before delegating to plan-writing.

```
RULE 9: ASSESS SCOPE SIZE. If the topic describes multiple independent subsystems
        (e.g., "platform with chat, file storage, billing, and analytics"), flag this
        BEFORE asking detail questions. Present decomposition: list independent pieces,
        relationships, and recommended build order. Each sub-project gets its own
        brainstorming → plan → EPIC cycle. Proceed with the first sub-project.
```

### Example Output

```
**Understanding:** Add webhook support for external services to subscribe to system events.
**Dimensions:** API design, event model, reliability (retry/delivery guarantees), security.
**Challenges:** At-least-once delivery without duplicates; scaling dispatch off main request path.
**To clarify:** Target consumers; expected volume; replaces or supplements polling APIs?

Is this understanding correct, or should I adjust my focus?
```

---

## Process Rules

### Questioning Protocol

```
RULE 1: ONE question at a time. Never ask 2+ questions in one message.
RULE 2: ALWAYS use MULTIPLE CHOICE with recommendation (A/B/C — recommended: X because Y).
        Open-ended ONLY for factual questions (names, URLs, numbers) where options
        cannot be predicted.
RULE 3: After each answer, ACKNOWLEDGE, SUMMARIZE, and BUILD on it — no redundant questions.
RULE 4: 3-7 questions total. Stop when you can propose approaches.
RULE 5: If PM gives a short answer, INFER defaults and CONFIRM:
        "I'll assume {default} — correct?"
RULE 6: If PM says "you decide" or "whatever you think", make a decision
        and state it clearly: "I'll go with X because {reason}."
RULE 7: Cover at least 3 of these categories: scope, users, constraints,
        patterns, scale, timeline, success criteria.
RULE 8: Every question involving a directional choice MUST present 2-3 structured
        options with labels (A/B/C), effort estimate (S/M/L), risk (L/M/H),
        and a recommendation with reasoning.
        For each recommended option, state why alternatives are less suitable.
        Use the Question Format Template below.
RULE 9: When the topic involves AI agents, workflows, or multi-service orchestration,
        ask about: platform/framework preferences, interaction model (chat vs. batch
        vs. event), and deployment strategy (Docker Compose recommended for 2+ services).
RULE 10: If PM's topic includes a specific solution (not just a problem), acknowledge
         the decision and reduce questioning to scope/constraints only (2-3 questions max).
         In approach exploration, present PM's solution as Approach A (recommended) plus
         1 meaningful alternative. Do NOT force the full question flow on pre-decided topics.
RULE 11: Before proposing approaches, present a brief MoSCoW prioritization of collected
         requirements (Must / Should / Could / Won't). Ask PM to confirm or adjust.
         This takes ONE question slot. Prioritization feeds into approach effort estimates
         and plan scope section.
```

### Question Format Template

Every directional question MUST follow this format:

```
=== Step {N}/{total}: {category} ===

{Context sentence explaining why this matters.}

(A) **{Option name}** — {1-line description}
    Effort: {S/M/L} | Risk: {L/M/H}
(B) **{Option name}** — {1-line description}
    Effort: {S/M/L} | Risk: {L/M/H}
(C) **{Option name}** — {1-line description}
    Effort: {S/M/L} | Risk: {L/M/H}

→ Recommended: **(B)** — {reason why B is best}
  Why not A: {1-line reason}
  Why not C: {1-line reason}
```

### Question Format Example

```
=== Step 3/7: Delivery Guarantees ===

Webhook reliability is the #1 concern for enterprise consumers.

(A) **Fire-and-forget** — Send once, no retry, consumer handles failures
    Effort: S | Risk: H
(B) **At-least-once with retry** — Exponential backoff, 3 retries, dead letter queue
    Effort: M | Risk: L
(C) **Exactly-once with idempotency** — Dedup keys, consumer ack, full delivery log
    Effort: L | Risk: L

→ Recommended: **(B)** — balances reliability with implementation effort
  Why not A: Enterprise consumers expect retries; fire-and-forget causes silent data loss
  Why not C: Exactly-once adds significant complexity; at-least-once with idempotent consumers achieves same practical result
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
RULE 8 (Hard Gate): COUNT(approaches) >= 2 before presenting. If fewer,
        loop back and generate more. No exceptions.
RULE 9 (Anti-Shortcut): NEVER skip approach exploration, even for "obvious" topics.
        Present lighter-weight or simpler variants as alternatives. No exceptions.
```

### Risk Assessment Protocol

```
RULE 1: After PM selects an approach (Step 4), present a structured risk table
        BEFORE starting design sections (Step 5).
        Format per risk: Name | Probability (L/M/H) | Impact (L/M/H) | Mitigation.
RULE 2: Include at least 3 risks. Cover at minimum: technical feasibility,
        integration complexity, and one domain-specific risk.
RULE 3: Ask PM to confirm, add, or remove risks. ONE question: "Any risks
        missing or overstated?" This feeds directly into the plan Risks section.
RULE 4: For trivial topics (S-effort, single-component), reduce to 2 risks minimum.
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
RULE 2: **Mockup processing (before plan-writing delegation):**
        - Create `plans/{plan_id}/mockups/` directory
        - Process by source type:
          - **github:** Read source files, copy TSX/CSS to mockups/
          - **ai_studio:** Playwright navigates to URL, downloads source code, saves to mockups/
          - **image:** Copy PNG/JPG to mockups/
        - Pass mockup paths, source type, and component mapping to plan-writing skill
RULE 3: Delegate plan writing to plan-writing skill (skills/plan-writing.md).
        Collect all approved content from Steps 3-7 (questions, chosen approach,
        risk table, design sections, PM modifications, final approval).
        Invoke plan-writing in Mode A (Post-Brainstorming), passing all collected
        sections + project context. Plan-writing handles document structure, quality
        gates, forbidden phrases, completeness verification, and handoff.
        After plan-writing completes, brainstorming is DONE.
RULE 4: Pass all approved design details to plan-writing — do not summarize or omit.
        If PM approved a modification, the modified version goes into the document.
RULE 5: Generate plan IDs per `skills/run-management.md` → ID System section:
        Plan: P{NNN} (from counter.yaml, pre-allocated at Step 1).
RULE 6: Brainstorming does NOT create EPICs. EPIC creation is handled by /aid-plan --epic
        (offered in plan-writing handoff), which delegates file creation to `aid-plan-to-epic.sh`.
```

---

## Language Handling

**Conversation:** Follow PM's language (detect from first message, follow switches).
**Documents:** Follow `.aid-o/config/language.yaml` → `document_language` (default: EN).

Resolution: config `document_language` → check `scope.plans` → fallback to EN.

If conversation and document languages differ, mention once at start:
"I'll respond in {PM language}, but the plan will be in {document language} per your config."

See `.aid-o/config/language.yaml` for full configuration options (scope per document type).

---

## Context Persistence (Interim Document)

Long brainstorming sessions can exceed the context window. The interim document preserves
full conversation detail so nothing is lost.

```
RULE 1: CREATE `.aid-o/work/interim-P{NNN}.md` at the START of /aid-plan (Step 1),
        using the pre-allocated plan ID. Initial content: topic, project context,
        PM's initial input, prior-plan references.
RULE 2: UPDATE after each completed step — append full detail, not summaries:
        - Each Q&A pair (question + PM answer + inferred defaults)
        - MoSCoW prioritization results
        - Chosen approach with full rationale and rejected alternatives
        - Risk assessment table
        - Each approved design section (complete content)
        - All PM modifications and decisions
RULE 3: Write for MACHINE CONSUMPTION — structure for reliable re-reading, not
        human aesthetics. Use consistent headers (## Step N: {name}) so the agent
        can parse on context resume.
RULE 4: On context resume (new session), READ interim doc first. Announce:
        "Found interim notes for P{NNN}. Resuming from Step {N}."
        Do NOT re-ask questions already answered in the interim doc.
RULE 5: DELETE the interim doc when plan-writing completes successfully.
        On abort, KEEP the interim doc (it serves as recovery artifact).
RULE 6: Before creating interim doc, CHECK if `.aid-o/work/interim-P*.md` already exists.
        If found, announce: "Active brainstorm in progress (P{NNN}). (A) Resume it,
        (B) Start new brainstorm with next ID." Prevents concurrent-session collisions.
```

---

## Brainstorming Run Lifecycle

### Starting a Brainstorming Run

Steps: (1) PM invokes `/aid-brainstorm [topic]` → (2) read project context → (3) Initial Analysis Phase → (4-7) questions, approaches, risk assessment, design, approval → (8) delegate to plan-writing skill → plan-writing presents next steps.

### Aborting a Brainstorming Run

PM aborts by saying "stop", "cancel", "abort", or similar.

- **Before Step 8** (no plan written): end gracefully, keep interim doc as recovery artifact.
- **During Step 8**: plan-writing handles cleanup; ask PM "Keep partial plan file? (Y/N)".
- **PM does not respond (new session):** Check `.aid-o/work/interim-P*.md` for interim doc from prior run. If found, offer: "(A) Resume from interim notes, (B) Start fresh." If no interim doc, check `.aid-o/plans/` for partial plan. If nothing found, start fresh.

### Re-opening a Brainstorming Run

When PM selects "Re-open brainstorming" in the plan-writing handoff:

1. Load the existing plan file and display already-approved sections
2. Return to Step 3 with existing context retained (previous answers are still valid)
3. New requirements **ADD** — never overwrite approved sections; only modified sections need re-approval
4. Re-write the plan file (Step 8) and return to handoff

**Abort during re-open:** Most recently written plan file is preserved. No rollback.

### Transitioning to Execution

Plan-writing skill presents the handoff (see `skills/plan-writing.md` → Post-Write Handoff for authoritative format). The handoff includes a summary of decisions made during brainstorming and 6 options: generate EPIC, run manual, run autonomous, review, re-open brainstorming, or stop.

---

## Design Section Templates

Use templates from `defaults/templates/design-sections.md` as guidance when presenting design sections in Step 5. Adapt based on the specific topic. Core sections: Architecture, Data Model, API. Add others as needed (Implementation, Testing, Security, Risks, Infrastructure, Migration).

**Mockup mapping:** If mockups are available, ask PM which mockups map to which components/pages.
Record component↔mockup mapping (e.g., "CompanyDashboard.tsx → dashboard page, lines 48-64 → stat cards").
This mapping is passed to plan-writing for per-step `visual_refs` assignment.

---

## Common Brainstorming Patterns

| Pattern | Questions Focus | Approaches Focus | Key Design Sections |
|---------|----------------|-------------------|---------------------|
| New Feature | integration, data model extension, UI | extend vs. new module, shared vs. isolated state | Architecture, Data Model, API, Implementation |
| Migration/Refactor | scope, backwards compat, rollback, downtime | big-bang vs. incremental, strangler fig | Architecture (before/after), Migration, Rollback, Testing |
| Infrastructure/DevOps | scale, existing infra, budget, expertise | managed vs. self-hosted, automation level | Architecture, Config, Deployment, Monitoring |
| AI/Multi-Tenant | tenant isolation, agent capabilities, privacy | single vs. multi-tenant DB, orchestration pattern | Architecture (hub-spoke), Data Model (per-tenant), API |
| Greenfield | user needs, business model, MVP scope | tech stack, architecture style, deploy target | Full suite: Architecture through Release |

---

## Reference Files

- `commands/aid-plan.md` — unified command that invokes this skill (9-step flow)
- `skills/plan-writing.md` — Step 8 delegation (exhaustive plan doc, quality gates, handoff)
- `commands/aid-plan.md --epic` — next step: EPIC creation from plan
- `scripts/aid-auto-pipeline.sh` — Plan.md → EPIC.md → plan.json → run.md → queue
- `defaults/templates/plan.md` — base plan document template
- `defaults/templates/design-sections.md` — design section templates for Step 5
- `skills/planner.md` — how plans become Plan JSON
- `skills/run-management.md` — lifecycle integration
- `.aid-o/config/language.yaml` — document language configuration

---

**Last Updated:** 2026-03-16
