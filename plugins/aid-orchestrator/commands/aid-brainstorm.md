---
name: aid-brainstorm
description: 11-step interactive brainstorming flow
user_invocable: true
---

Interactive brainstorming run — collaborate with PM to explore an idea, design a solution, produce a validated plan, and generate an EPIC draft.

This command guides PM through a structured 11-step brainstorming flow. It asks questions one at a time, explores alternatives with tradeoffs, validates the design incrementally, writes the plan document, auto-generates an EPIC draft, and hands off to the next phase.

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

**Present to PM:**
```
Brainstorming: {topic}
====================================
Project: {name from project-profile.yaml or directory name}
Stack: {languages, frameworks from project-profile.yaml or "unknown"}
Recent: {last active EPIC or plan, or "no prior context"}

I'll help you explore this idea step by step.
Let's start with some questions to understand what you need.
```

### Step 2: Analysis

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

### Step 3: Questions

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

### Step 4: Approaches

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

### Step 5: Design

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

### Step 6: Sections

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

### Step 7: Approval

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

### Step 8: Document

Write the validated design to a plan file.

1. Generate plan ID: `P-{YYYYMMDD}-{4char-hash}` (hash: `echo $(date +%s%N | md5sum | head -c 4)`)
2. Generate topic slug from the brainstorming topic (lowercase, hyphens, max 40 chars)
3. Determine output language:
   - Read `.aid-o/03-config/language.yaml` → `document_language` (default: `EN`)
   - If `scope.plans: true`: write the plan document in the configured `document_language`
   - If `scope.plans: false` or config missing: write in English
   - **Note:** The conversation with PM stays in PM's language regardless of document language
4. Write plan to `.aid-o/01-plans/P-{YYYYMMDD}-{hash}-{topic}.md` using the plan template structure:
   - Frontmatter: id, type (plan), status (draft), created, author (PM + AI)
   - Context: why this plan exists (from Step 1-3)
   - Goal: one-sentence desired outcome
   - Scope: in-scope and out-of-scope items
   - Approach: chosen option with pros/cons, rejected alternatives summarized
   - Decision: which option and rationale
   - High-Level Steps: numbered steps with descriptions and effort estimates
   - Constraints: from PM answers
   - Risks: from design discussion
   - Success Criteria: from PM answers
   - Next Steps: suggest creating EPIC
5. Confirm to PM:
   ```
   Plan written: .aid-o/01-plans/P-{YYYYMMDD}-{hash}-{topic}.md
   ```

### Step 9: EPIC Subagent

Generate an EPIC draft from the approved plan using the EPIC subagent prompt template from `skills/brainstorming.md`.

1. Read the plan file just created (Step 8)
2. Read `skills/brainstorming.md` Section "EPIC Subagent Prompt Template"
3. Read `.aid-o/04-engine/memory/project-profile.yaml` for tech stack context
4. Read `.aid-o/03-config/templates/epic.md` for the EPIC template structure
5. Determine output language:
   - Same logic as Step 8: use `language.yaml` → `document_language` if `scope.plans: true`
6. Generate EPIC draft:
   - EPIC ID: `E-{YYYYMMDD}-{4char-hash}`
   - Fill all EPIC template sections from the approved plan:
     - **Context** — from plan Context + Approach Decision
     - **Goal** — from plan Goal (1-3 sentences, specific, testable)
     - **Scope** — Allowed files/paths and Forbidden zones derived from plan + project structure
     - **Artifacts** — concrete deliverables from plan High-Level Steps
     - **Constraints** — from plan Constraints + PM answers
     - **DoD Gates** — default (tests_pass, lint_pass, security_scan_pass, docs_updated) + conditional gates based on stack
     - **Acceptance Criteria** — from plan Success Criteria, expanded into testable checkboxes
     - **Dependencies** — from plan Constraints + project context
     - **Steps (Role Pipeline)** — map plan steps to AID roles (architect, backend, frontend, qa, etc.) with dependencies and parallel groups
     - **Run Breakdown** — estimate single vs. multi-run based on step count and complexity
   - Apply YAGNI: do not add steps or roles that the plan does not require
7. Write EPIC draft to `.aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md`
8. Confirm:
   ```
   EPIC draft written: .aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md
   ```

### Step 10: Execution Plan Option

After the EPIC draft is written, offer PM the option to generate the execution plan immediately.

1. Ask PM:
   ```
   EPIC draft written: .aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md

   Would you like to generate the execution plan now?
   (Y) Generate Plan JSON + Run file → ready for /aid-run-epic
   (N) Stop here → review the EPIC draft, then run /aid-plan-epic manually

   Generating now saves a step but skips manual EPIC review.
   ```

2. If PM says N (or skip, later, no):
   → Proceed to Step 11 (handoff — present A-D options)

3. If PM says Y (or yes, go, generate):
   → Execute the plan-epic flow inline:
   a. Use the EPIC file just written in Step 9 as input
   b. Skip format detection (we know it's a valid EPIC — we just generated it)
   c. Follow `commands/aid-plan-epic.md` Steps 3-9 exactly:
      - Step 3: Load and Validate EPIC
      - Step 4: Analyze Steps, Dependencies, and Parallel Groups
      - Step 5: Generate Analysis Groups
      - Step 6: Build Plan JSON
      - Step 7: Save Plan JSON (plan.json + plan_progress.json + epic_input.md)
      - Step 8: Generate Run File
      - Step 9: Present Output
   d. After plan-epic completes → proceed to Step 11 (handoff — present A-D options)

### Step 11: Handoff

Present interactive options based on the completed brainstorming run.

1. Parse the plan's High-Level Steps and group them into logical phases (by dependency/domain)
2. Display phases:
   ```
   Phases detected:
     Phase 1: {steps 1-3} — {description}
     Phase 2: {steps 4-6} — {description}
     Phase 3: {steps 7-9} — {description}
   ```
3. Present options:
   ```
   Brainstorming Complete
   ====================================
   Plan:  .aid-o/01-plans/P-{id}-{topic}.md
   EPIC:  .aid-o/02-epics/E-{id}-{topic}.md (draft)
   Phases: {count} detected

   What's next?
   (A) Add more items to plan — re-open brainstorming
   (B) Create EPIC for all phases — single EPIC covering everything
   (C) Create EPIC for specific phase — pick a phase
   (D) Stop here — review files, run /aid-plan-epic manually later
   ```

**Option A — Re-open brainstorming:**
1. Load existing plan from Step 8
2. Display already-approved sections
3. Return to Step 3 with existing context
4. New requirements ADD to the plan (never overwrite approved sections)
5. Re-present modified sections for approval (Step 6)
6. Re-write plan file (Step 8)
7. Re-generate EPIC draft (Step 9)
8. Return to Step 11

**Option B — Create EPIC for all phases:**
1. Use the EPIC draft from Step 9 as-is (covers all High-Level Steps)
2. Proceed to Step 10 (Execution Plan Option) — ask if PM wants Plan JSON now
3. If Y: generate Plan JSON inline, present full pipeline handoff
4. If N: present plan + EPIC file paths

**Option C — Create EPIC for specific phase:**
1. Ask PM: "Which phase? (1/2/3/...)"
2. Generate a new EPIC covering only the selected phase's steps:
   - Restrict scope to phase-relevant files
   - Set `plan_epics_total` in EPIC frontmatter to total phase count
   - List external dependencies from other phases
   - Add context note: "This EPIC covers Phase {N} of {total}"
3. Save phase-specific EPIC to `.aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}-phase-{N}.md`
4. Proceed to Step 10 (Execution Plan Option)

**Option D — Stop here:**
```
Brainstorming complete. Files written:
  Plan: .aid-o/01-plans/P-{id}-{topic}.md
  EPIC: .aid-o/02-epics/E-{id}-{topic}.md (draft)

Next steps:
  1. Review the EPIC draft and refine if needed
  2. Run /aid-plan-epic {epic-path} to generate execution plan
  3. Run /aid-run-epic to start orchestration
```

## Reference Files

- `skills/brainstorming.md` — process rules, key principles, EPIC subagent prompt template, language handling
- `commands/aid-plan-epic.md` — plan-epic flow (Steps 3-9 used by Step 10 inline execution)
- `skills/planner.md` — plan generation logic (downstream from brainstorming)
- `defaults/templates/plan.md` — plan document template
- `defaults/templates/epic.md` — EPIC template
- `defaults/templates/epic-example.md` — EPIC example for reference
- `skills/run-management.md` — lifecycle protocols (End of Brainstorming Protocol)
- `.aid-o/03-config/language.yaml` — document language configuration

## Important

- **This command CREATES two files** — plan + EPIC draft. It never modifies existing files.
- **Detail by default** — brainstorming produces comprehensive output. PM should never need to ask for more detail.
- **One question at a time** — never batch questions. PM attention is the bottleneck.
- **Multiple choice preferred** — reduce PM cognitive load with options, not open-ended questions.
- **Language split** — conversation follows PM's language; output documents follow `language.yaml` configuration.
- **YAGNI** — do not propose over-engineered solutions. Start simple, PM can ask for complexity.
- If PM aborts at any step (says "stop", "cancel", "abort"), end gracefully without writing files.
- If `.aid-o/` does not exist, the command still works but writes plan/EPIC to current directory with a warning.
