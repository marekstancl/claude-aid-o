---
name: plan-writing
description: Exhaustive plan document authoring with forbidden phrase detection, completeness gates, and traceability verification
user_invocable: false
---

# Plan Writing — Exhaustive Plan Document Authoring

**Skill:** plan-writing
**Dependencies:** brainstorming

---

## TL;DR

This skill defines how AID writes **exhaustive, implementation-ready plan documents**. It ensures that every detail from brainstorming (or a standalone specification) is captured in the plan — nothing is lost, nothing is summarized away, nothing is deferred to "see brainstorming notes."

The plan-writing skill is invoked in two modes:
1. **Post-brainstorming** — called by `/aid-plan brainstorm` Step 8 after PM approves all design sections. Receives approved sections as input.
2. **Standalone** — called by `/aid-write-plan` command with a specification or requirements as input.

**Input:** Approved design sections from brainstorming OR specification document + codebase analysis
**Output:** Exhaustive plan document (`.aid-o/plans/P{NNN}-{topic}.md`)

---

## Core Principle: Zero Information Loss

The plan document is the **single source of truth** for implementation. Agents receive plan sections during dispatch (via `plan_ref` injection in `skills/pipeline.md` § 4). Any detail missing from the plan is detail the agent will never see.

```
RULE: If it was discussed, decided, or approved — it MUST be in the plan.
      If it's not in the plan — it does not exist for execution.
```

This is not a summary document. This is not a high-level overview. This is the implementation specification that agents will follow line by line.

---

## Invocation Modes

### Mode A: Post-Brainstorming

Triggered by `/aid-plan brainstorm` Step 8 after PM approves all design sections.

**Input available:**
- All approved design sections from brainstorming Steps 5-6 (architecture, data model, API, implementation, testing, risks)
- PM's answers from Steps 3-4 (questions, approach selection)
- PM's modifications and corrections from incremental validation
- Project context from Step 1 (project profile, tech stack, existing code)
- Knowledge context (if knowledge acquisition was active)

**Contract:** The skill receives ALL brainstorming context. It does NOT re-ask PM questions. It does NOT explore alternatives. It writes.

### Mode B: Standalone

Triggered by `/aid-write-plan` command with a specification file or topic.

**Input available:**
- Specification document or PM-described requirements
- Codebase analysis (the skill performs deep-dive file reading)
- PM's answers to clarifying questions (max 5)

**Contract:** The skill conducts targeted codebase analysis, asks minimal clarifying questions, then writes the exhaustive plan.

---

## Plan Document Structure

The plan document uses an extended format that is a **superset** of the standard `defaults/templates/plan.md`. All existing sections are preserved (backward compatible), and new detailed step sections are added.

### Frontmatter (unchanged)

```yaml
---
id: P{NNN}
type: plan
status: draft
created: YYYY-MM-DD
author: PM + AI
---
```

### Sections

The plan MUST contain these sections in this order:

| Section | Content | Source |
|---------|---------|--------|
| `## Context` | Why this plan exists, what triggered it | Brainstorming context / spec |
| `## Goal` | One-sentence desired outcome | Brainstorming goal / spec |
| `## Scope` | In-scope and out-of-scope items | Brainstorming scope |
| `## Approach` | Chosen approach with alternatives summarized | Brainstorming approaches |
| `## Architecture` | Full architecture from approved design | Brainstorming architecture section |
| `## Data Model` | Entities, fields, types, relationships, invariants | Brainstorming data model section |
| `## API Design` | Endpoints, contracts, request/response schemas, errors | Brainstorming API section |
| `## Implementation Steps` | Detailed per-step breakdown (see format below) | Brainstorming implementation plan |
| `## Testing Strategy` | Test types, coverage targets, test plan | Brainstorming testing section |
| `## Constraints` | Technical, business, timeline constraints | PM answers |
| `## Risks` | Risk table with probability, impact, mitigation | Brainstorming risks |
| `## Success Criteria` | Testable success criteria | PM answers |
| `## Next Steps` | Follow-up actions | Standard |

**Conditional sections** (include only when relevant, omit otherwise):
- `## Infrastructure` — Docker Compose, deployment, CI/CD (when Docker/infra was discussed)
- `## Security` — Auth, permissions, data protection (when security was discussed)
- `## UI Design` — Components, layouts, interactions (when frontend was discussed)
- `## Migration Plan` — Before/after, rollback, data migration (when migration was discussed)
- `## Visual Specification` — visual-spec.yaml, mockup source code references, component breakdown (when mockups exist in `plans/{plan_id}/mockups/`)

**source_type: companion** — HTML files from Visual Companion brainstorming session.
Extract CSS classes, layout structure (grid/flex/columns), color values, and component
structure from HTML. The companion HTML IS the mockup source code — agents receive it
verbatim, same as GitHub TSX/CSS source.

**Section omission rule:** If brainstorming did not discuss a topic (e.g., no frontend, no API), the corresponding section is omitted entirely. Do NOT add empty or placeholder sections. Do NOT invent content for sections that were not discussed.

---

## Phase Markers

When a plan spans multiple EPICs (phases), each phase must be delimited by a phase marker so the pipeline scripts can slice steps correctly. The marker format is:

```
**EPIC N: Steps M-P — Title**
```

Where:
- `N` is the phase number (1, 2, 3, ...)
- `M` is the first step number in this phase
- `P` is the last step number in this phase
- `Title` is a short human-readable label (optional but recommended)

**Extended form (with step range — preferred for multi-phase plans):**

```markdown
**EPIC 1: Steps 1-4 — Foundation**

### Step 1: ...
### Step 2: ...
### Step 3: ...
### Step 4: ...

**EPIC 2: Steps 5-8 — Feature Build**

### Step 5: ...
...
```

**Short form (without step range — for sequential simple plans):**

```markdown
**EPIC 1**

### Step 1: ...
### Step 2: ...

**EPIC 2**

### Step 3: ...
```

When the short form is used, the script assigns steps to phases by document order: every `### Step N:` header encountered after a `**EPIC N**` marker belongs to that phase, until the next marker.

**Rules:**

| Scenario | Rule |
|----------|------|
| Multi-phase plan (total phases > 1) | MUST include phase markers |
| Single-phase plan (total phases = 1) | Phase markers are NOT required — all steps belong to the single phase automatically |
| Marker placement | Place each marker on its own line, immediately before the first step of that phase |
| Step numbering | Step numbers in the marker range MUST match actual `### Step N:` headers; ranges with gaps are invalid |

**Do NOT use these formats — they will not be parsed:**

```markdown
# WRONG — uses heading syntax instead of bold text
## Phase 1: Foundation
### Phase 2: Build

# WRONG — uses dash list and wrong keyword
- Phase 1: Steps 1-4

# WRONG — missing asterisks, not bold
EPIC 1: Steps 1-4
*EPIC 1: Steps 1-4*

# WRONG — uses "Phase" keyword instead of "EPIC"
**Phase 1: Steps 1-4 — Foundation**

# WRONG — missing colon between EPIC N and Steps
**EPIC 1 Steps 1-4**
```

**Why format matters:** The `aid-plan-to-epic.sh` script uses a bash regex to identify phase boundaries:

```
^\*\*EPIC[[:space:]]+([0-9]+)(:[[:space:]]+Steps[[:space:]]+([0-9]+)-([0-9]+))?
```

Only lines that match this regex are recognised as phase markers. Any other format is silently ignored, causing the script to fall back to even step distribution across phases — which produces incorrect EPIC splits when steps are not evenly distributed.

---

## Detailed Step Format

The `## Implementation Steps` section replaces the old `## High-Level Steps` table. Each step gets its own subsection with mandatory fields.

### Per-Step Template

```markdown
### Step {N}: {Descriptive Name}

**Objective:** {What this step produces or changes — one sentence}

**Files:**
- Create: `exact/path/to/new-file.ts` — {what this file contains and why}
- Modify: `exact/path/to/existing-file.ts` (lines ~{start}-{end}) — {what changes and why}
- Test: `tests/exact/path/to/test-file.spec.ts` — {what behavior this tests}

**Architecture Context:**
{How this step fits into the overall architecture. Which components it touches,
which data flows it implements or modifies. Reference the Architecture section.}

**Implementation Detail:**
{Concrete logic, algorithms, data transformations, API calls. This is the
"how" — specific enough that an agent can implement without guessing.
Include code patterns, function signatures, configuration values.}

**Error Handling:**
{Specific failure modes for this step. What can go wrong, how to detect it,
how to recover. Include error codes, fallback behavior, retry logic.}

**Edge Cases:**
- {Edge case 1 — what triggers it and expected behavior}
- {Edge case 2 — what triggers it and expected behavior}
- {Edge case 3 — what triggers it and expected behavior}

**Dependencies:**
- Depends on: Step {X} — {what it needs from that step: files, contracts, data}
- Blocks: Step {Y} — {what it produces that the next step needs}

**Acceptance Criteria:**
- [ ] {Testable criterion 1 — specific, measurable}
- [ ] {Testable criterion 2 — specific, measurable}
- [ ] {Testable criterion 3 — specific, measurable}

**Effort:** {S / M / L}
**AID Role:** {architect / domain / backend / frontend / qa / security / observability / docs / release}
**Visual Refs:** `{path/to/mockup-source.tsx}` lines {start}-{end} — {what part this step implements} *(optional — only for frontend/UI steps with mockups)*
```

### Mandatory Fields Per Step

Every step MUST have ALL of these fields populated:

| Field | Minimum Requirement |
|-------|-------------------|
| **Objective** | One clear sentence, no ambiguity |
| **Files** | At least 1 concrete file path (no placeholders like `src/...`) |
| **Architecture Context** | At least 2 sentences referencing the Architecture section |
| **Implementation Detail** | At least 1 paragraph with concrete logic OR 1 code snippet |
| **Error Handling** | At least 1 failure mode with recovery strategy |
| **Edge Cases** | At least 2 edge cases (3+ for M/L effort steps) |
| **Dependencies** | Explicit dependency statement (or "No dependencies — can start independently") |
| **Acceptance Criteria** | At least 2 testable criteria per step (3+ for M/L effort) |
| **Effort** | S, M, or L |
| **AID Role** | Exactly one role from the AID role set |

**Exception:** For S-effort steps that are purely mechanical (e.g., "add config entry"), Error Handling and Edge Cases may have 1 item each instead of the minimums above.

---

## Forbidden Shortcuts

These phrases indicate the AI is taking shortcuts instead of providing real detail. Their presence in a plan document is a **hard failure**.

| Forbidden Phrase | Why It Fails | What to Write Instead |
|---|---|---|
| "implement standard error handling" | What is "standard"? For whom? | Name specific error codes, response shapes, recovery strategies |
| "follow existing patterns" | Which patterns? In which files? | Cite the specific file path and line range as the pattern source |
| "add appropriate validation" | What rules? What types? What ranges? | List each validation rule: field X must be string, 1-255 chars, no HTML |
| "handle edge cases" | Which ones? | Name 2+ specific edge cases with expected behavior |
| "update tests accordingly" | Which tests? What assertions? | Name test file, test function, input value, expected output |
| "see brainstorming notes" | Plan must be self-contained | Copy the relevant detail directly into the plan |
| "similar to X component" | How similar? What differs? | Describe the specific implementation, noting differences from X |
| "and other necessary changes" | Hidden scope = missed work | List every change explicitly — if you can't name it, it's not planned |
| "as needed" | Undefined scope | Specify exactly what is needed and under what conditions |
| "standard REST/CRUD operations" | Which operations? What schemas? | List each endpoint: method, path, request body, response, errors |
| "proper logging/monitoring" | What is "proper"? | Specify what to log, at what level, with what fields |
| "handle authentication" | How? JWT? Session? OAuth? | Specify the auth mechanism, token format, validation steps |
| "refactor as necessary" | Unbounded scope | List each specific refactoring operation |
| "configure appropriately" | What values? | Specify exact configuration keys and values |
| "etc." / "and so on" / "..." | Hiding missing detail | Complete the list — if you can't, you don't know enough |
| "purple gradient banner" (or any text-only UI color/style description) | Vague — agent invents own design | Include exact CSS: `className="bg-gradient-to-r from-indigo-600 to-violet-600"` or reference visual-spec.yaml |
| "styled similar to mockup" | Which mockup? What styles? | Reference visual-spec.yaml component name + exact Tailwind classes |

### Forbidden Phrase Detection Protocol

```
BEFORE writing plan to disk:
  1. Scan the entire plan text for each forbidden phrase (case-insensitive)
  2. Also scan for these meta-patterns:
     - Any sentence ending with "etc." or "..."
     - Any bullet point that is less than 10 words (likely too vague)
     - Any "Files:" entry without a concrete file extension
     - Any "Acceptance Criteria" item without a measurable condition
  3. If ANY match is found:
     → Do NOT write the file
     → Fix the violation by replacing with specific detail
     → Re-scan after fix
     → Only proceed when zero violations remain
```

---

## Traceability Protocol

### Post-Brainstorming Mode (Mode A)

Every piece of information from brainstorming must map to a plan section. Use this mapping:

| Brainstorming Source | Plan Destination |
|---|---|
| Step 3 — PM answers to questions | `## Scope`, `## Constraints`, relevant step details |
| Step 4 — Chosen approach + rationale | `## Approach` (full section) |
| Step 4 — Rejected approaches (summary) | `## Approach` (alternatives subsection) |
| Step 5 — Architecture section | `## Architecture` (full section) |
| Step 5 — Data Model section | `## Data Model` (full section) |
| Step 5 — API section | `## API Design` (full section) |
| Step 5 — Implementation plan | `## Implementation Steps` (expanded into detailed steps) |
| Step 5 — Testing strategy | `## Testing Strategy` (full section) |
| Step 5 — Risks and mitigations | `## Risks` (full section) |
| Step 6 — PM modifications to sections | Applied to the respective plan sections |
| Step 6 — PM-added constraints | `## Constraints` + relevant step details |
| PM's stated success criteria | `## Success Criteria` |
| Docker/MCP decisions | `## Infrastructure` or `## Constraints` |
| Workflow detection results | `## Architecture`, step details |
| Knowledge context references | Inline citations in relevant sections |

### Traceability Verification

```
AFTER assembling plan content, BEFORE writing:
  FOR EACH row in the traceability table:
    1. Check if the brainstorming source was active (some sections may not apply)
    2. If active: verify the plan destination section contains the mapped content
    3. If content is missing: ADD it to the plan
    4. If content is present but summarized: EXPAND to full detail

  Report format (internal, not shown to PM):
    Trace: Step 3 answers → Scope ✓, Constraints ✓
    Trace: Architecture → Architecture ✓
    Trace: Data Model → Data Model ✓
    Trace: API → API Design ✓
    Trace: Implementation → Steps 1-8 ✓
    ...
    Result: ALL traces resolved. Proceeding to write.
```

---

## Completeness Gate

Before the plan document is written to disk, the AI MUST pass this gate. This is a **hard gate** — the file MUST NOT be written until all checks pass.

```
COMPLETENESS GATE — evaluate each check:

SECTION COMPLETENESS:
  1. Does every brainstorming-approved section have a corresponding plan section?
  2. Is every plan section populated (not empty, not placeholder)?
  3. Does the plan contain ALL conditional sections that are relevant?

STEP QUALITY:
  4. Does every step have ALL mandatory fields populated?
  5. Does every step have concrete file paths (not "src/..." or "path/to/...")?
  6. Does every step with effort M or L have ≥3 acceptance criteria?
  7. Does every step with effort M or L have ≥3 edge cases?
  8. Does every "Modify" file reference include approximate line ranges?

DETAIL QUALITY:
  9. Are ALL forbidden shortcut phrases absent from the plan?
  10. Does every API endpoint specify method, path, request schema, response schema, and error codes?
  11. Does every data model entity specify field names, types, and constraints?
  12. Does every implementation detail section contain concrete logic (not just "implement X")?

STRUCTURAL QUALITY:
  13. Are all step dependencies explicitly stated and consistent (no circular deps)?
  14. Are AID roles assigned to every step?
  15. Can Step 1 be executed with zero additional questions?

TRACEABILITY:
  16. Does the traceability verification report show all traces resolved?

EVALUATION:
  COUNT checks passed out of 16.
  IF all 16 pass → write plan to disk
  IF any check fails → fix the failing checks, re-evaluate, repeat until all pass
  DO NOT write a partial or incomplete plan. DO NOT skip failed checks.
  DO NOT tell PM "the plan is mostly complete" — it is complete or it is not.
```

### Gate Failure Recovery

```
IF Completeness Gate fails:
  1. Identify which checks failed
  2. For each failure:
     - If missing detail: add the detail from brainstorming context
     - If forbidden phrase: replace with specific content
     - If structural issue: fix the structure
  3. Re-run the gate
  4. Maximum 3 gate iterations. If still failing after 3:
     → Write the plan with a WARNING section at the top listing unresolved items
     → Ask PM to review the flagged items
```

---

## Standalone Mode Protocol (Mode B)

When invoked via `/aid-write-plan` without prior brainstorming:

### Phase 1: Input Analysis

```
1. Read the input specification (file path or inline text from PM)
2. Identify:
   - What is being built or changed
   - Which parts of the codebase are affected
   - What constraints exist
3. Present a brief analysis (3-5 lines) to PM for confirmation
```

### Phase 2: Codebase Deep-Dive

```
1. Read project.yaml for tech stack and conventions
2. Identify files that will be created or modified:
   - Glob for existing files in relevant directories
   - Read key files to understand current patterns
   - Note existing tests, configs, and documentation
3. Build a mental model of the affected code area
```

### Phase 3: Clarification (max 5 questions)

```
1. Ask up to 5 targeted questions (one at a time, multiple choice preferred)
2. Questions should cover gaps in the specification:
   - Ambiguous requirements
   - Missing scope boundaries
   - Unclear technical decisions
3. Skip this phase if the specification is unambiguous
```

### Phase 4: Plan Writing

```
1. Assemble plan content following the same Document Structure as Mode A
2. Fill all sections from the specification + codebase analysis + PM answers
3. Run Forbidden Phrase Detection
4. Run Completeness Gate
5. Write plan to disk
6. Present summary to PM
```

---

## Section Writing Guidelines

### Architecture Section

Do NOT write a generic architecture overview. Write a concrete, project-specific architecture that references actual files and components.

```
GOOD:
  "The webhook system adds three components to the existing Express app:
   - WebhookRegistry (src/webhooks/registry.ts) — stores subscriptions in PostgreSQL
     using the existing Prisma ORM. New model: WebhookSubscription.
   - WebhookDispatcher (src/webhooks/dispatcher.ts) — BullMQ job that reads pending
     events from the webhook_events table and delivers them via HTTP POST.
   - WebhookController (src/webhooks/controller.ts) — REST endpoints for CRUD
     operations on subscriptions. Mounts at /api/v1/webhooks."

BAD:
  "The webhook system will have a registry, dispatcher, and controller component
   following standard patterns."
```

### Data Model Section

Include EVERY field, type, constraint, and relationship. Not just entity names.

```
GOOD:
  "WebhookSubscription:
    - id: UUID (PK, auto-generated)
    - url: string (1-2048 chars, must be valid HTTPS URL)
    - events: string[] (non-empty, values from EventType enum)
    - secret: string (32-byte hex, auto-generated, used for HMAC-SHA256 signatures)
    - active: boolean (default: true)
    - created_at: timestamp (auto-set)
    - updated_at: timestamp (auto-updated)
    - owner_id: UUID (FK → users.id, ON DELETE CASCADE)
    Indexes: (owner_id), (events) using GIN
    Invariants: URL must be HTTPS in production, HTTP allowed in development"

BAD:
  "WebhookSubscription:
    - url, events, secret, active, timestamps
    Relations: belongs to User"
```

### Implementation Detail in Steps

Each step's Implementation Detail must contain enough information for an agent to write code without asking questions.

```
GOOD:
  "Create POST /api/v1/webhooks endpoint:
   1. Validate request body with Zod schema: { url: z.string().url(), events: z.array(z.nativeEnum(EventType)).min(1) }
   2. Generate secret: crypto.randomBytes(32).toString('hex')
   3. Create WebhookSubscription via Prisma: prisma.webhookSubscription.create({ data: { ...validated, secret, ownerId: req.user.id } })
   4. Return 201 with { id, url, events, active, created_at } — do NOT return secret in response
   5. If URL is not HTTPS and NODE_ENV === 'production': return 422 with error 'HTTPS required for webhook URLs'"

BAD:
  "Create the webhook creation endpoint following REST conventions.
   Validate input, generate a secret, save to database, return the result."
```

---

## Anti-Circumvention Rules

These rules exist because AI systems systematically try to skip detail work. Each rule addresses a known failure mode.

```
RULE AC-1: DO NOT summarize approved sections.
  Failure mode: AI condenses a 20-line architecture discussion into 3 lines.
  Fix: Copy the full approved content. Expand, never compress.

RULE AC-2: DO NOT use the plan template's "High-Level Steps" table format.
  Failure mode: AI reverts to the simple table format because it's easier.
  Fix: Every step MUST use the detailed per-step template from this skill.

RULE AC-3: DO NOT defer detail to the EPIC.
  Failure mode: AI writes "details will be specified in the EPIC."
  Fix: The plan IS the detail source. The EPIC is a structural wrapper.

RULE AC-4: DO NOT skip sections because "it's obvious."
  Failure mode: AI omits error handling because "standard HTTP errors."
  Fix: Write the specific error handling for THIS feature.

RULE AC-5: DO NOT generate the plan in a single pass.
  Failure mode: AI writes the entire plan in one shot and misses details.
  Fix: Write section by section. After each section, verify it against
       the brainstorming source before moving to the next.

RULE AC-6: DO NOT claim the gate passed without actually checking.
  Failure mode: AI says "Completeness Gate: all checks pass" without verifying.
  Fix: Enumerate each check with its result. Show the work.

RULE AC-7: DO NOT use relative references like "as described above."
  Failure mode: Agent dispatch extracts individual sections — "above" doesn't exist.
  Fix: Each step section must be self-contained. Repeat key details or use
       explicit section references ("see ## Architecture → Components").

RULE AC-8: DO NOT merge multiple logical changes into one step.
  Failure mode: AI writes "Step 3: Implement API endpoints and add validation
                and write tests and update documentation."
  Fix: Each step = one logical unit of work for one AID role. Split if needed.

RULE AC-9: DO NOT omit file paths because "the agent will figure it out."
  Failure mode: AI writes "Create the migration file" without specifying where.
  Fix: "Create: prisma/migrations/20260227_add_webhooks/migration.sql"

RULE AC-10: DO NOT provide less detail for "simple" steps.
  Failure mode: AI writes detailed steps for complex work but one-liners for
               "simple" steps like config changes or docs updates.
  Fix: ALL steps use the same detailed template. Even S-effort steps get
       concrete file paths, acceptance criteria, and implementation detail.
```

---

## MUST Rules

1. **ALWAYS use the detailed per-step template** — never fall back to the high-level steps table
2. **ALWAYS populate all mandatory fields per step** — no empty or placeholder fields
3. **ALWAYS run the Completeness Gate before writing** — hard gate, no exceptions
4. **ALWAYS run Forbidden Phrase Detection before writing** — hard gate, no exceptions
5. **ALWAYS run Traceability Verification in post-brainstorming mode** — every brainstorming output must map to a plan section
6. **NEVER summarize or compress approved brainstorming sections** — copy and expand, never condense
7. **NEVER defer detail to the EPIC or other documents** — the plan is self-contained
8. **NEVER skip sections that were discussed in brainstorming** — if it was discussed, it's in the plan
9. **NEVER use any phrase from the Forbidden Shortcuts table** — hard failure
10. **NEVER write the plan without verifying AC-1 through AC-10** — each rule must be satisfied
11. **ALWAYS make each step section self-contained** — agents receive individual sections, not the whole plan
12. **ALWAYS follow the language split** — plan document in configured document_language, conversation in PM's language
13. **ALWAYS write the plan to `.aid-o/plans/`** — never to any other location
14. **ALWAYS generate proper plan IDs** — per `skills/run-management.md` → ID System (pre-allocated at brainstorming Step 1)
15. **ALWAYS delete the interim document after successful plan write** — remove `.aid-o/work/interim-P{NNN}.md` if it exists (cleanup from brainstorming context persistence)

---

## Integration with Dispatch Protocol

The plan document is consumed by `skills/pipeline.md` § 4 → Source Plan Integration (Variant B). The dispatch protocol:

1. Reads the plan via `plan_ref` or `source_plan` field
2. Matches the current step to a plan section using header patterns: `### Step {N}`, `## Step {N}`, keyword matching
3. Extracts the matched section and injects it into the agent prompt

**Implication for this skill:** Step headers MUST follow the pattern `### Step {N}: {Name}` to enable reliable section matching. The `{N}` must be a sequential integer starting from 1.

---

## Post-Write Handoff

After the plan is written to disk and confirmed to PM, present next steps. This handoff applies to BOTH Mode A (post-brainstorming) and Mode B (standalone).

**Present to PM — Handoff Summary:**
```
Plan {plan_id} complete. Here's what was decided:

Topic: {topic}
Approach: {chosen approach name} — {1-line summary}
Scope: {N} design sections approved | Effort: {S/M/L} | Risk: {L/M/H}
Key decisions:
  - {most significant decision 1}
  - {most significant decision 2}
  - {most significant decision 3}

Plan: .aid-o/plans/{plan_id}-{topic}.md
Steps: {step_count} | Roles: {unique roles}
Quality gates: passed (forbidden phrases: 0, completeness: {N}/{total})

Next Steps:
(A) /aid-plan --epic {plan_path} — generate EPIC + execution artifacts
(B) /aid-run {plan_path} — generate EPIC and start execution (manual mode)
(C) /aid-run --auto {plan_path} — generate EPIC and start autonomous execution
    ⚠ Requires autonomous_mode: true in .aid-o/config/permissions.yaml
(D) Review plan — open .aid-o/plans/{plan_id}-{topic}.md
(E) Re-open brainstorming — add/modify requirements (interim doc preserved)
(F) Stop — plan saved, resume anytime with /aid-plan --resume {plan_id}
```

**Option A — Generate EPIC:**
Runs `aid-auto-pipeline.sh` (via Script Execution Protocol) which creates all artifacts
deterministically: EPIC files, plan.json, run.md, and queue entries.

**Option B — Manual Execution:**
Generates EPIC (same as A) then immediately starts `/aid-run` in manual mode.
PM approves each escalation.

**Option C — Autonomous Execution:**
Generates EPIC then starts `/aid-run --auto`. S-effort fixes auto-approved,
M-effort uses defaults, L-effort always escalates to PM.
Requires `autonomous_mode: true` in `.aid-o/config/permissions.yaml`.

**Option D — Review plan:**
PM reviews the plan file, makes edits if needed, then runs option A/B/C when ready.

**Option E — Re-open brainstorming (Mode A only):**
If invoked from brainstorming, return to brainstorming Step 3 with existing context.
New requirements ADD to the plan (never overwrite approved sections).
If invoked standalone (Mode B), suggest `/aid-plan` to explore alternatives.

**Option F — Stop here:**
```
Plan saved: .aid-o/plans/{plan_id}-{topic}.md
Resume anytime: /aid-plan --resume {plan_id}
Or generate EPIC later: /aid-plan --epic {plan_path}
```

---

## Reference Files

- `commands/aid-plan.md` — unified command that invokes this skill (write mode or brainstorm Step 8)
- `skills/brainstorming.md` — brainstorming skill (upstream — provides approved sections)
- `skills/pipeline.md` § 4 — agent dispatch (downstream — injects plan sections into agent prompts)
- `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` — pipeline script that creates EPIC files, plan.json, run.md, and queue entries from the plan document
- `defaults/templates/plan.md` — base plan template (this skill extends it)
- `skills/run-management.md` — plan lifecycle (archiving, location rules)
- `.aid-o/config/language.yaml` — document language configuration

---

**Last Updated:** 2026-03-17
