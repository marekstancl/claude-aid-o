---
name: aid-write-plan
description: Write an exhaustive implementation plan from a specification or topic
user_invocable: true
---

Write an exhaustive, implementation-ready plan document from a specification file, EPIC draft, or free-form topic. This command produces a detailed plan where every step contains concrete file paths, implementation logic, error handling, edge cases, and testable acceptance criteria.

For post-brainstorming plan writing, this skill is invoked automatically by `/aid-brainstorm` Step 8. Use this command for **standalone** plan writing when you have requirements but skipped brainstorming.

## Usage

```
/aid-write-plan [spec-file-or-topic]
```

**Examples:**
```
/aid-write-plan .aid-o/02-epics/E-015-auth-system.md    # from EPIC draft
/aid-write-plan requirements.md                           # from spec file
/aid-write-plan "add webhook support to the API"          # from topic
/aid-write-plan                                           # interactive — asks for input
```

## Prerequisites

- `.aid-o/` workspace should exist (run `/aid-init` first; if missing, suggest it but proceed)
- No brainstorming session required — this command works independently

## Flow

### Step 1: Input Resolution

1. If `$ARGUMENTS` is a file path:
   - Read the file
   - Detect format: EPIC (has `# EPIC:` header or `type: epic` frontmatter), plan draft (has `type: plan`), or free-form specification
   - If EPIC: extract Context, Goal, Scope, Steps as input
   - If plan draft: read as starting point, enhance to detailed format
   - If free-form: use full content as requirements
2. If `$ARGUMENTS` is a topic string (not a file path):
   - Use it as the starting topic for codebase analysis
3. If `$ARGUMENTS` is empty:
   - Ask PM: "What would you like to plan? Provide a topic, paste requirements, or give me a file path."
4. Read `skills/plan-writing.md` for process rules and quality gates

### Step 2: Context Gathering

1. Read project state:
   - `.aid-o/04-engine/memory/project-profile.yaml` — tech stack, architecture, conventions
   - `.aid-o/04-engine/memory/active-work.md` — current focus, recent work
   - Scan `.aid-o/01-plans/` for related plans (avoid duplication)
2. Detect PM's language from their input — conversation follows PM's language
3. Read language configuration:
   - `.aid-o/03-config/language.yaml` → `document_language` for the plan document
   - Default to `EN` if config missing

### Step 3: Codebase Deep-Dive

Perform targeted codebase analysis to ground the plan in reality.

1. Identify which parts of the codebase are affected by the requirements
2. Read key files in those areas:
   - Existing source files that will be modified
   - Existing test files for the area
   - Configuration files (package.json, tsconfig, prisma schema, etc.)
   - Existing similar features (to understand patterns)
3. Note:
   - Current file structure and naming conventions
   - Existing patterns (error handling, validation, routing, testing)
   - Dependencies already in use
4. Build a concrete picture of what exists and what needs to change

**Present to PM:**
```
Plan: {topic}
====================================
Project: {name from project-profile.yaml or directory name}
Stack: {languages, frameworks}
Affected areas: {directories/modules identified}
Existing patterns: {key patterns found}

I'll analyze the requirements and write a detailed implementation plan.
```

### Step 4: Clarification (max 5 questions)

If the input specification has gaps or ambiguities:

1. Ask up to 5 targeted questions (one at a time, multiple choice preferred)
2. Focus on:
   - Scope boundaries (what's in, what's out)
   - Technical decisions (which approach for ambiguous requirements)
   - Integration points (how it connects to existing code)
3. Skip this step entirely if the specification is clear and complete
4. After each answer, acknowledge and move to next question or proceed

### Step 5: Plan Assembly

1. Determine plan structure based on requirements:
   - Which sections from `skills/plan-writing.md` → Plan Document Structure are needed
   - How many implementation steps are required
   - What the dependency chain looks like
2. Write the plan content section by section:
   - Follow the detailed step template from `skills/plan-writing.md`
   - Reference actual file paths discovered in Step 3
   - Use patterns and conventions found in the codebase
3. Populate every mandatory field in every step

### Step 6: Quality Gates

Run all quality gates from `skills/plan-writing.md` before writing:

1. **Forbidden Phrase Detection** — scan entire plan for forbidden shortcuts
2. **Completeness Gate** — verify all 16 checks pass
3. If any gate fails: fix and re-run (max 3 iterations)

### Step 7: Write Plan

1. Generate plan ID:
   - Read `.aid-o/03-config/counter.yaml` → increment `plan` counter → `P{NNN}`
   - If counter.yaml doesn't exist: start from P001
2. Generate topic slug (lowercase, hyphens, max 40 chars)
3. Write plan to `.aid-o/01-plans/{plan_id}-{topic}.md`
4. Present to PM:
   ```
   Plan written: .aid-o/01-plans/{plan_id}-{topic}.md

   {step_count} implementation steps
   Roles: {unique roles across steps}
   Estimated effort: {sum of S=1, M=3, L=5 points}

   Quality gates: passed (forbidden phrases: 0, completeness: 16/16)
   ```

### Step 8: Next Steps

The plan-writing skill handles the post-write handoff (see `skills/plan-writing.md` → Post-Write Handoff). It presents PM with options: create EPIC, review plan, brainstorm, or stop.

## Reference Files

- `skills/plan-writing.md` — process rules, quality gates, detailed step format, anti-circumvention rules
- `skills/brainstorming.md` — brainstorming skill (upstream when called from `/aid-brainstorm`)
- `commands/aid-plan-epic.md` — next step: convert plan to EPIC + Plan JSON
- `defaults/templates/plan.md` — base plan template (this command extends it)
- `.aid-o/03-config/language.yaml` — document language configuration

## Important

- **This command creates ONE file** — the plan document in `.aid-o/01-plans/`. It never modifies existing files.
- **Exhaustive detail by default** — the plan must be implementation-ready. Agents receive plan sections during dispatch.
- **Self-contained steps** — each step section must be readable and actionable in isolation (dispatch protocol extracts individual sections).
- **Language split** — conversation follows PM's language; plan document follows `language.yaml` configuration.
- **Quality gates are mandatory** — the plan is not written until Forbidden Phrase Detection and Completeness Gate both pass.
- If PM aborts at any step (says "stop", "cancel", "abort"), end gracefully without writing files.
