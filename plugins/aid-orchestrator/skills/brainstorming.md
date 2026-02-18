# Brainstorming — Interactive Design and Planning Skill

**Version:** 0.2.0
**Skill:** brainstorming
**Dependencies:** session-management, planner
**Attribution:** Inspired by [superpowers:brainstorming](https://github.com/jessevincent/claude-superpowers) (MIT License, Jesse Vincent)

---

## TL;DR

This skill defines how AID conducts interactive brainstorming sessions with the PM. It governs the questioning protocol, approach exploration, incremental design validation, plan document generation, and automatic EPIC draft creation.

The brainstorming skill is invoked by the `/aid-brainstorm` command and produces two artifacts: a validated plan document and an EPIC draft ready for `/plan-epic`.

**Input:** PM's idea or topic + interactive Q&A
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
through /plan-epic and /run-epic.

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
   - List concrete deliverables from the plan's High-Level Steps.
   - Include: endpoints, tables, components, docs, configs.

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
   - Map plan's High-Level Steps to AID roles:
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

5. Cross-reference the plan in the EPIC's Context section.

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

### Transitioning to Execution

After brainstorming completes, the standard AID workflow continues:

```
/aid-brainstorm → Plan + EPIC draft
    ↓
PM reviews and edits EPIC draft
    ↓
/plan-epic .aid-o/02-epics/E-*.md → Plan JSON + Session file
    ↓
/run-epic → Orchestrated execution
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

---

## Reference Files

- `commands/aid-brainstorm.md` — command that invokes this skill (9-step flow)
- `defaults/templates/plan.md` — plan document template
- `defaults/templates/epic.md` — EPIC template
- `defaults/templates/epic-example.md` — EPIC example for reference
- `skills/planner.md` — how plans become Plan JSON (downstream from brainstorming)
- `skills/session-management.md` — End of Brainstorming Protocol (lifecycle integration)
- `.aid-o/03-config/language.yaml` — document language configuration

---

**Version:** 0.2.0
**Last Updated:** 2026-02-18
