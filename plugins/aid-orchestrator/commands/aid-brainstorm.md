---
name: aid-brainstorm
description: 8-step interactive brainstorming flow
user_invocable: true
---

Interactive brainstorming run — collaborate with PM to explore an idea, design a solution, and produce a validated plan.

This command guides PM through a structured 8-step brainstorming flow. It asks questions one at a time, explores alternatives with tradeoffs, validates the design incrementally, and delegates plan writing to the plan-writing skill. EPIC creation is a separate step offered after plan completion.

## Critical Rules — Read BEFORE executing any step

These rules govern your behavior throughout the ENTIRE brainstorming session. Violating any rule is a hard failure.

1. **ONE question at a time** — never batch multiple questions into one message. Ask, wait for answer, then ask next.
2. **Multiple choice preferred** — use A/B/C options instead of open-ended questions. Open-ended only when options cannot be predicted.
3. **Present initial analysis BEFORE first question** — demonstrate understanding of the topic before asking anything (Step 2).
4. **2-3 approaches with recommendation** — never present a single option. Always explain why alternatives are less suitable.
5. **Section-by-section approval** — walk through design sections individually (Step 6). Never skip to final approval.
6. **Detail by default** — provide specific file names, endpoint paths, data types, error handling. PM should never need to say "add more detail."
7. **YAGNI** — propose the simplest solution meeting stated requirements. Do not add unrequested complexity.
8. **Delegate plan writing** — Step 8 delegates to `skills/plan-writing.md`. Do not write the plan document yourself.
9. **No files without approval** — never write plan or EPIC files until PM explicitly approves in Step 7.
10. **Follow ALL steps in order** — do not skip, merge, or reorder steps. Each step has a specific purpose.
11. **Progress output mandatory** — begin every step by outputting to PM: `=== Step N/8: {Name} ===`. This is not optional. If a step number is missing from the conversation, the step was skipped — which is a hard failure.

**After reading these rules:** proceed to Step 1 and follow the flow sequentially.

## Usage

```
/aid-brainstorm [topic]
```

**Examples:**
```
/aid-brainstorm                         # start open brainstorming
/aid-brainstorm user authentication     # start with a topic seed
/aid-brainstorm "migrate to PostgreSQL" # start with a specific idea
```

## Prerequisites

- `.aid-o/` workspace should exist (run `/aid-init` first; if missing, suggest it but proceed anyway)
- No EPIC or plan file required — this command creates them

## Flow

### Step 1: Context

Read project state to ground the brainstorming in reality.

1. Check if `.aid-o/` exists:
   - If yes: read `.aid-o/04-engine/memory/active-work.md` (current focus, recent work, blockers)
   - If yes: read `.aid-o/04-engine/memory/project-profile.yaml` (tech stack, architecture, conventions)
   - If yes: scan `.aid-o/01-plans/` and `.aid-o/02-epics/` for recent/active items (last 5 by date)
   - If no: note that workspace is not initialized; proceed with limited context
2. If `$ARGUMENTS` contains a topic: use it as the brainstorming seed
3. If `$ARGUMENTS` is empty: ask PM "What would you like to brainstorm?"
4. Read `skills/brainstorming.md` for process rules and key principles
5. Detect PM's language from their input — conversation will follow PM's language throughout
6. Read language configuration:
   - If `.aid-o/03-config/language.yaml` exists: use `document_language` for output documents
   - If not: default to `EN` for output documents
7. **Load sub-skills** (READ the files — do not skip):
   - Check if PM's topic contains workflow keywords (agent, chatbot, RAG, workflow, pipeline, automation, LangChain, LangGraph, N8N, LangFlow, multi-agent, AI workflow, LLM agent, tool-calling, assistant):
     - If yes: READ `skills/brainstorming-workflow.md` — follow its protocols throughout Steps 2-4
   - Check `.aid-o/03-config/policies/memory-config.yaml` → `knowledge.enabled`:
     - If true: READ `skills/brainstorming-knowledge.md` — follow its protocols in Steps 1 and 4
   - Even if no workflow detected: READ `skills/brainstorming-workflow.md` → "Docker/MCP Preference Rules" section (needed for Step 4 Docker evaluation)

**Present to PM:**
```
=== Step 1/8: Context ===

Brainstorming: {topic}
====================================
Project: {name from project-profile.yaml or directory name}
Stack: {languages, frameworks from project-profile.yaml or "unknown"}
Recent: {last active EPIC or plan, or "no prior context"}

I'll help you explore this idea step by step.
Let's start with some questions to understand what you need.
```

**Before moving to Step 2, verify:**
- [ ] Read `skills/brainstorming.md` (not skipped)
- [ ] Sub-skills loaded: `brainstorming-workflow.md` READ if workflow keywords detected (or Docker/MCP section READ for all projects); `brainstorming-knowledge.md` READ if knowledge enabled
- [ ] PM's language detected — conversation language set
- [ ] Context header presented to PM (topic, project, stack, recent)

### Step 2: Analysis

**Output to PM first:** `=== Step 2/8: Analysis ===`

Present a structured analysis of the PM's topic before asking any questions. Follow the Initial Analysis Phase protocol from `skills/brainstorming.md`.

1. Based on context gathered in Step 1, present a brief structured analysis (5-8 lines max):
   - **What I understand from your topic** — paraphrase + key aspects identified
   - **Key dimensions I see** — technical, organizational, integration, risk
   - **Potential challenges** — what could go wrong, what needs careful decisions
   - **What I need to clarify** — preview of question areas (not the questions themselves)
2. Ask PM: "Is this understanding correct, or should I adjust my focus before we continue?"
3. If PM corrects: acknowledge, restate corrected understanding, then proceed
4. If PM confirms: proceed to Step 3 (Questions)

**Transition:** When PM confirms understanding, move to Step 3.

**Before moving to Step 3, verify:**
- [ ] Presented structured analysis (4 areas: understanding, dimensions, challenges, clarify)
- [ ] Asked PM to confirm understanding
- [ ] PM confirmed (or corrections incorporated and re-confirmed)

### Step 3: Questions

**Output to PM first:** `=== Step 3/8: Questions ===`

Ask PM clarifying questions to understand requirements, constraints, and goals. Follow the questioning protocol from `skills/brainstorming.md`.

**Rules:**
- Ask ONE question at a time (never batch multiple questions)
- Prefer multiple-choice format (A/B/C options) over open-ended questions
- After each answer, acknowledge it and ask the next question
- Aim for 3-7 questions total (stop when you have enough context to propose approaches)
- Questions should cover: scope, users/audience, constraints, existing patterns, success criteria
- If PM gives a short answer, infer reasonable defaults and confirm: "I'll assume X — correct?"

**Question categories (cover at least 3):**

| Category | Example Question |
|----------|-----------------|
| **Scope** | "What's the boundary? (A) Just backend API (B) Full stack with UI (C) Infrastructure only" |
| **Users** | "Who uses this? (A) End users via UI (B) Other services via API (C) Internal team tooling" |
| **Constraints** | "Any hard constraints? (A) Must use existing DB (B) Must be backwards-compatible (C) No constraints" |
| **Patterns** | "Should this follow existing patterns in the project, or is a new approach acceptable?" |
| **Scale** | "Expected load? (A) Low (<100 req/min) (B) Medium (C) High (1000+ req/min)" |
| **Timeline** | "How urgent? (A) This sprint (B) This quarter (C) When it's ready" |
| **Success** | "How will you know this succeeded?" |

**Transition:** When enough context is gathered, summarize what you've learned and move to Step 4.

**Before moving to Step 4, verify:**
- [ ] Asked questions ONE at a time (not batched in a single message)
- [ ] Used multiple choice format where possible
- [ ] Covered at least 3 question categories from the table
- [ ] Summarized findings to PM before transitioning

### Step 4: Approaches

**Output to PM first:** `=== Step 4/8: Approaches ===`

Propose 2-3 distinct approaches with tradeoffs and a recommendation.

1. Based on the answers from Step 3, generate 2-3 approaches
2. Each approach MUST include:
   - **Name** — short descriptive label
   - **Summary** — 2-3 sentences explaining the approach
   - **Pros** — concrete advantages (3+ items)
   - **Cons** — concrete disadvantages (2+ items)
   - **Effort** — estimated relative effort (S/M/L)
   - **Risk** — key risk and mitigation
3. Clearly state which approach you recommend and why
4. Ask PM: "Which approach do you prefer? (A/B/C or suggest modifications)"

**Format:**
```
Approaches
====================================

Option A: {Name} (Recommended)
  {Summary}
  Pros:  {list}
  Cons:  {list}
  Effort: {S/M/L}
  Risk:  {risk + mitigation}

Option B: {Name}
  {Summary}
  Pros:  {list}
  Cons:  {list}
  Effort: {S/M/L}
  Risk:  {risk + mitigation}

Option C: {Name} (if applicable)
  ...

Recommendation: Option A because {reasoning}.

Which approach? (A/B/C/modify)
```

**If PM asks for modifications:** Incorporate feedback, present a revised option, and confirm.

**Before moving to Step 5, verify:**
- [ ] Presented 2-3 distinct approaches (not just one)
- [ ] Each approach has: Name, Summary, Pros (3+), Cons (2+), Effort, Risk
- [ ] Stated recommendation with reasoning why alternatives are less suitable
- [ ] PM chose an approach (or modifications incorporated)

### Step 5: Design

**Output to PM first:** `=== Step 5/8: Design ===`

Present the chosen approach as a structured design with PM input.

1. Take the chosen approach (or modified version) from Step 4
2. Expand it into a structured design covering:
   - **Architecture** — components, data flow, integration points
   - **Data model** — key entities, relationships, storage
   - **API / Interface** — endpoints, contracts, protocols
   - **Implementation plan** — high-level steps, order of work
   - **Testing strategy** — what to test, how
   - **Risks and mitigations** — detailed risk analysis
3. Present the design in a clear, organized format
4. Ask PM: "Does this design look right? Any changes before we go section by section?"

**Detail by default:** Provide comprehensive detail without PM asking for it. Include specifics like field names, endpoint paths, error handling strategies. PM can always say "simplify" but should never need to say "add more detail."

**Before moving to Step 6, verify:**
- [ ] Design covers all 6 areas: architecture, data model, API, implementation, testing, risks
- [ ] Includes specific details (field names, paths, protocols) — not vague descriptions
- [ ] Asked PM for overall feedback before section-by-section review

### Step 6: Sections

**Output to PM first:** `=== Step 6/8: Sections ===`

Walk through the design section by section, getting approval for each.

1. Present each design section individually (architecture, data model, API, etc.)
2. For each section:
   a. Show the detailed content
   b. Ask: "Approve this section? (Y/modify/skip)"
   c. If modify: incorporate changes, re-present, ask again
   d. If skip: mark as "needs review" and continue
   e. If approve: mark as approved, move to next section
3. Track approval status:
   ```
   Section Status:
     [x] Architecture — approved
     [x] Data Model — approved (modified: added soft-delete field)
     [ ] API Design — in progress
     [ ] Implementation Plan — pending
     [ ] Testing Strategy — pending
     [ ] Risks — pending
   ```
4. After all sections reviewed, move to Step 7

**Before moving to Step 7, verify:**
- [ ] Each section presented individually (not all at once)
- [ ] Each section got explicit response: approve / modify / skip
- [ ] Section Status tracker shown to PM with all statuses

### Step 7: Approval

**Output to PM first:** `=== Step 7/8: Approval ===`

Final design approval from PM.

1. Present the complete design summary with all section statuses
2. Highlight any sections that were modified or skipped
3. Ask PM for final approval:
   ```
   Design Summary
   ====================================
   All sections reviewed:
     {section statuses from Step 6}

   Ready to write the plan document?
   (Y) Approve and write plan
   (N) Go back to a section
   (X) Abort brainstorming
   ```
4. If PM says Y: proceed to Step 8
5. If PM says N: ask which section to revisit, return to Step 6 for that section
6. If PM says X: end brainstorming, no files written

**Before moving to Step 8, verify:**
- [ ] Complete design summary shown with all section statuses
- [ ] PM explicitly approved (said Y) — not assumed or implied

### Step 8: Document (Plan-Writing Delegation)

**Output to PM first:** `=== Step 8/8: Document ===`

Write the validated design to an exhaustive plan file by delegating to the plan-writing skill.

1. Collect all approved sections from the brainstorming session:
   - Step 3 (Questions): PM's answers to every clarification question
   - Step 4 (Approaches): PM's chosen approach, rationale, and rejected alternatives
   - Step 5 (Design): All design sections — architecture, data model, API, implementation, testing, risks
   - Step 6 (Sections): PM's section-by-section approvals and all modifications
   - Step 7 (Approval): PM's final approval
   - Project context from Step 1 (project profile, tech stack, knowledge context)
2. Invoke `skills/plan-writing.md` in **Mode A (Post-Brainstorming)**:
   - Pass ALL collected sections as input
   - The plan-writing skill handles:
     - Plan ID generation (from counter.yaml)
     - Topic slug generation
     - Language configuration (from language.yaml)
     - Exhaustive plan document structure with detailed per-step format
     - Forbidden Phrase Detection (hard gate — no vague shortcuts)
     - Traceability Verification (every brainstorming output → plan section)
     - Completeness Gate (16-point verification, hard gate)
     - Writing the plan file to `.aid-o/01-plans/{plan_id}-{topic}.md`
3. The plan-writing skill confirms to PM:
   ```
   Plan written: .aid-o/01-plans/{plan_id}-{topic}.md

   {step_count} implementation steps
   Quality gates: passed (forbidden phrases: 0, completeness: 16/16)
   ```

**Important:** The plan-writing skill writes detailed per-step sections (not the old high-level steps table). Each step includes file paths, implementation detail, error handling, edge cases, dependencies, and acceptance criteria. This ensures agents receive full implementation context during dispatch.

**Step 8 is the FINAL step of brainstorming.** After plan-writing completes, it presents next steps (EPIC creation, review, re-open). Brainstorming does NOT create EPICs — that is `/aid-plan-epic`'s job. `/aid-plan-epic` delegates all deterministic operations (EPIC generation, plan.json construction, run file creation, queue entry) to bash/jq pipeline scripts, ensuring reproducible output without LLM variance.

## Reference Files

- `skills/brainstorming.md` — process rules, key principles, language handling
- `skills/plan-writing.md` — plan writing skill (Step 8 delegation — writes plan, presents next steps including EPIC creation)
- `commands/aid-write-plan.md` — standalone plan writing command
- `commands/aid-plan-epic.md` — create EPIC from plan (offered by plan-writing handoff)
- `skills/planner.md` — plan generation logic (downstream from brainstorming)
- `defaults/templates/plan.md` — base plan document template (extended by plan-writing skill)
- `skills/run-management.md` — lifecycle protocols (End of Brainstorming Protocol)
- `.aid-o/03-config/language.yaml` — document language configuration

## Important

- **This command CREATES one file** — the plan document. EPIC creation is a separate step via `/aid-plan-epic`.
- **Detail by default** — brainstorming produces comprehensive output. PM should never need to ask for more detail.
- **One question at a time** — never batch questions. PM attention is the bottleneck.
- **Multiple choice preferred** — reduce PM cognitive load with options, not open-ended questions.
- **Language split** — conversation follows PM's language; output documents follow `language.yaml` configuration.
- **YAGNI** — do not propose over-engineered solutions. Start simple, PM can ask for complexity.
- If PM aborts at any step (says "stop", "cancel", "abort"), end gracefully without writing files.
- If `.aid-o/` does not exist, the command still works but writes plan to current directory with a warning.

**Last Updated:** 2026-02-28
