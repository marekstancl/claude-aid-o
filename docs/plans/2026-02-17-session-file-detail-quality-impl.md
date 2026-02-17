# Session File Detail Quality — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make session files consistently detailed by improving templates with guidance comments, expanding orchestrated flow instructions (plan-epic.md Step 5), adding quality checks (epic-orchestration.md PLANNING), and expanding non-orchestrated flow instructions (session-start.md).

**Architecture:** No new files created. 7 existing files modified: 4 session templates + 3 commands/skills. All changes are markdown prompt engineering (no executable code).

**Tech Stack:** Markdown, YAML frontmatter, HTML comments for guidance markers

**Design doc:** `docs/plans/2026-02-17-session-file-detail-quality-design.md`

---

## Task 1: Rework `session-new-feature.md` Template

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/session-new-feature.md` (171 lines → ~200 lines)

**Step 1: Add guidance comments + restructure Objective section**

Current (line 19-20):
```markdown
## Objective
> One-sentence description of the new feature
```

Replace with:
```markdown
## Objective
<!-- MIN: 3-5 sentences. State WHAT you're building, WHY it's needed, and what SUCCESS looks like.
     Bad:  "Add dark mode"
     Good: "Add dark mode toggle to application settings. Users have requested reduced eye strain
            for evening use (Issue #42). This enables theme switching via a persistent user
            preference stored in localStorage. Success: toggle works, preference persists across
            sessions, all components respect the theme." -->
```

**Step 2: Add Context section (new — after Objective)**

Insert after Objective:
```markdown
## Context
<!-- What preceded this work. Reference previous sessions, state of the codebase, dependencies.
     For orchestrated sessions: which EPIC session is this, what was delivered before.
     For non-orchestrated: what's the current project state, any related ongoing work. -->

**Previous work:** {reference prior sessions or "N/A — greenfield"}
**Current state:** {what exists now that this session builds on}
**Dependencies:** {external systems, libraries, or other sessions this depends on}
```

**Step 3: Add Scope section (new — after Context)**

Insert after Context:
```markdown
## Scope
<!-- Explicit IN/OUT lists prevent scope creep. Be specific — name files, components, areas. -->

**In Scope:**
<!-- MIN: 3 items -->
- {what WILL be done}
- {what WILL be done}
- {what WILL be done}

**Out of Scope:**
<!-- MIN: 2 items -->
- {what will NOT be done in this session}
- {what will NOT be done in this session}
```

**Step 4: Replace Requirements/Design/Implementation with Phases section**

Replace the Requirements (lines 22-44), Design (lines 48-73), and Implementation (lines 76-86) sections with a Phases section. Keep Testing, Impact, Documentation Updates, References, AI Session Log, Completion Checklist, and Next Steps.

New Phases section:
```markdown
## Phases

<!-- Each phase = one logical chunk of work. Map from plan.json steps (orchestrated)
     or decompose the task yourself (non-orchestrated).
     Every phase MUST have all 6 subsections below. Do not skip any. -->

### Phase 1: {Phase Title}

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters in the session context. -->
{Describe what this phase solves — not just "implement X" but why, what it enables, what changes.}

**Agent / Role:** {role name — e.g., backend, frontend, architect, security, qa}

**Inputs:**
<!-- Files, context, or outputs from previous phases that this phase needs. -->
- {file path or description}

**Outputs:**
<!-- Files produced, artifacts created. Include expected file paths. -->
- {file path or description}

**Constraints:**
<!-- Boundaries: allowed/forbidden paths, backward compatibility, performance limits. -->
- {constraint}

**Acceptance:**
<!-- MIN: 3 items. How we verify this phase is done. -->
- [ ] {criterion 1}
- [ ] {criterion 2}
- [ ] {criterion 3}
```

**Step 5: Add Dependencies section (new — after Phases)**

Insert after Phases, before Testing:
```markdown
## Dependencies

<!-- Which phases depend on which and why. For single-phase sessions, write "No inter-phase dependencies." -->

| Phase | Depends On | Reason |
|-------|-----------|--------|
| Phase 2 | Phase 1 | {why — e.g., "needs API contract from Phase 1"} |
```

**Step 6: Add Quality Gates section (new — after Dependencies)**

Insert after Dependencies, before Testing:
```markdown
## Quality Gates

<!-- What automated checks run after this session's work. Reference specific gate names. -->

- **{gate name}** — {what it verifies}
```

**Step 7: Commit**

```bash
git add plugins/aid-orchestrator/defaults/templates/session-new-feature.md
git commit -m "feat(templates): rework session-new-feature.md with guidance comments, phases, scope"
```

---

## Task 2: Rework `session-bug-fix.md` Template

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/session-bug-fix.md` (158 lines)

**Step 1: Apply same pattern as Task 1**

Keep bug-fix-specific sections (Discovery, Investigation Steps, Solution with Root Cause) but:
- Add guidance comments with MIN markers to Objective
- Add Context section (after Objective)
- Add Scope section (after Context)
- Add Phases section with 6 required subsections (replace or restructure the Investigation Steps + Solution flow)
- Add Dependencies section
- Add Quality Gates section
- Keep Testing, Impact, Documentation, References, AI Session Log, Completion Checklist, Next Steps

**Key difference from new-feature:** Bug-fix keeps its unique Discovery section (severity, symptom, expected vs current behavior) — this is valuable context. Phases section follows Discovery.

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/defaults/templates/session-bug-fix.md
git commit -m "feat(templates): rework session-bug-fix.md with guidance comments, phases, scope"
```

---

## Task 3: Rework `session-refactoring.md` Template

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/session-refactoring.md` (178 lines)

**Step 1: Apply same pattern as Task 1**

Keep refactoring-specific sections (Motivation with risk assessment, Architecture Changes with before/after diagrams) but:
- Add guidance comments with MIN markers to Objective
- Add Context section
- Add Scope section (refactoring already has In/Out scope — enhance with MIN markers and guidance)
- Add Phases section with 6 required subsections
- Add Dependencies section
- Add Quality Gates section
- Keep before/after metrics in Testing section

**Key difference:** Refactoring template already has Scope (In/Out) — enhance it with guidance comments and MIN markers rather than replacing.

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/defaults/templates/session-refactoring.md
git commit -m "feat(templates): rework session-refactoring.md with guidance comments, phases, scope"
```

---

## Task 4: Rework `session-exploration.md` Template

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/session-exploration.md` (168 lines)

**Step 1: Apply same pattern as Task 1**

Keep exploration-specific sections (Research Question, Time Budget, Options Analysis, Prototype, Recommendations) but:
- Add guidance comments with MIN markers to Research Question (equivalent of Objective)
- Add Context section
- Scope already exists as Time Budget & Scope — enhance with guidance
- Add Phases section (Research → Analysis → Prototype → Recommendation phases)
- Add Dependencies section
- Quality Gates less relevant for exploration — replace with "Completion Criteria" referencing Success Criteria

**Key difference:** Exploration sessions are research-oriented. Phases map to research stages rather than implementation steps. Agent/Role may be "researcher" or "analyst" rather than specific dev roles.

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/defaults/templates/session-exploration.md
git commit -m "feat(templates): rework session-exploration.md with guidance comments, phases, scope"
```

---

## Task 5: Expand `plan-epic.md` Step 5 — Session Creation Protocol

**Files:**
- Modify: `plugins/aid-orchestrator/commands/plan-epic.md:201-217`

**Step 1: Replace Step 5 content**

Current Step 5 (lines 201-217, ~17 lines) replaced with ~70 lines:

```markdown
### Step 5: Generate Session File

#### 5a. Gather Sources

Before creating the session file, read ALL of the following:

1. **EPIC file** (already loaded from Step 1) — goal, scope, constraints, affected areas
2. **Plan JSON** (generated in Step 3) — steps, dependencies, parallel_groups, analysis_groups, gates, budget
3. **Plan file** (`.aid-o/01-plans/` or `workspace/workflow/plans/` if referenced in EPIC) — broader project context
4. **Previous session** (if `epic_session > 1`) — context, what was delivered, lessons learned
5. **Relevant source code** — scan inputs/outputs from plan steps, read key files to understand current state
6. **Decision policies** (`.aid-o/03-config/policies/decision-policies.yaml`) — understand auto_decisions and escalation_triggers

#### 5b. Create Session File

1. Generate session ID: `S-{YYYYMMDD}-{4char-hash}`
2. Use template from `.aid-o/03-config/templates/session-new-feature.md` (or type-appropriate template)
3. Fill in frontmatter:
   ```yaml
   id: S-{YYYYMMDD}-{hash}
   type: new-feature
   status: active
   priority: {from EPIC}
   started: {YYYY-MM-DD}
   epic_id: {epic_id}
   epic_session: {N}
   plan_ref: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
   orchestrated: true
   ```

#### 5c. Map Plan JSON to Session Phases

For EACH step in plan.json, create a Phase in the session file:

1. `step.objective` → **Phase Goal** — expand the objective into a full paragraph explaining what the phase accomplishes and why
2. `step.role` → **Agent / Role** — the agent role that will execute this phase
3. `step.inputs` → **Inputs** — translate file paths to readable descriptions with paths
4. `step.outputs` → **Outputs** — describe expected deliverables with file paths
5. `step.constraints` → **Constraints** — list as bullet points
6. `step.allowed_paths` + `step.forbidden_paths` → add to Constraints as scope boundaries
7. Check `analysis_groups` — if this step is the target of an analysis group, add to the phase: "Post-phase review: {agent roles} will perform {mode} analysis (merge strategy: {merge_strategy})"
8. Create **Acceptance** checklist from outputs (each output = one checkbox) + constraints that can be verified

#### 5d. Fill Remaining Sections

- **Objective:** 3-5 sentences from EPIC goal + scope. Include success criteria.
- **Context:** Reference previous sessions (if epic_session > 1), current code state, what was delivered before.
- **Scope:** IN list from EPIC scope (min 3 items), OUT list from EPIC constraints/exclusions (min 2 items).
- **Dependencies:** Table from plan.json dependencies array — "Phase X depends on Phase Y because Z".
- **Quality Gates:** List from plan.json gates array + relevant entries from decision-policies.yaml.
- **Session Log:** Initialize with `| {date} | Session created from EPIC {epic_id}, {step_count} phases planned |`

#### 5e. Quality Check

Before saving, verify the session file contains:
- [ ] Objective: 3+ sentences (not just a one-liner)
- [ ] Context: references to previous work or "greenfield" statement
- [ ] Scope: IN list (3+ items) and OUT list (2+ items)
- [ ] Phases: each phase has all 6 subsections (Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance)
- [ ] Dependencies: table with at least one entry (or "No inter-phase dependencies" if truly none)
- [ ] Quality Gates: at least one gate listed
- [ ] Session Log: initialized

If any check fails, fix before proceeding.

#### 5f. Save

Save to: `.aid-o/04-engine/sessions/S-{YYYYMMDD}-{hash}-{topic}.md`
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/commands/plan-epic.md
git commit -m "feat(plan-epic): expand Step 5 with Session Creation Protocol"
```

---

## Task 6: Update `epic-orchestration.md` PLANNING State

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md:102-119` (PLANNING state)
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md:539-556` (Integration with Session Management)

**Step 1: Add session file generation to PLANNING state actions**

Current PLANNING state actions (lines 104-109):
```markdown
**Actions:**
1. Analyze EPIC to identify required roles and their sequence
2. Build dependency graph (which steps depend on which)
3. Identify parallel groups (steps that can run concurrently)
4. Generate Plan JSON conforming to `.aid-o/03-config/templates/plan.schema.json`
5. Validate Plan JSON against schema
```

Add action 6:
```markdown
6. Generate session file following Session Creation Protocol (`commands/plan-epic.md` Step 5)
7. Validate session file completeness (see quality check below)
```

Add after Evidence line:
```markdown
**Session File Quality Check:**
Before transitioning to PLAN_REVIEW, verify the session file passes:
- Objective: 3+ sentences with success criteria
- Scope: explicit IN (3+ items) and OUT (2+ items) lists
- Phases: each phase has Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance (3+ items)
- Dependencies: table present
- Quality Gates: at least one gate listed

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json` + session file
```

**Step 2: Update Integration with Session Management section**

Current (lines 541-555) — replace with more detailed version that references the Session Creation Protocol:

```markdown
## Integration with Session Management

The Controller creates and maintains a session file for each EPIC run:

1. **On PLANNING:** Create session file following Session Creation Protocol (`commands/plan-epic.md` Step 5):
   - Read sources: EPIC, Plan JSON, Plan file, previous session, source code, decision policies
   - Map plan.json steps → session phases (1:1, with all 6 subsections per phase)
   - Fill Objective, Context, Scope, Dependencies, Quality Gates, Session Log
   - Validate completeness before proceeding to PLAN_REVIEW

2. **On each PHASE_CHECK:** Update session file:
   - Mark completed phase acceptance items as checked
   - Add step status + commit hash to Session Log

3. **On analysis complete:** Log analysis_report summary to Session Log

4. **On GATES:** Update session file:
   - Add gate results to Quality Gates section (pass/fail per gate)
   - Update Session Log

5. **On DONE:** Complete session file:
   - Set status: completed in frontmatter
   - Final Session Log entry
   - Archive to completed/

Session file frontmatter:
```yaml
id: S-{YYYYMMDD}-{hash}
type: new-feature
status: active
epic_id: {epic_id}
plan_ref: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
orchestrated: true
```
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md
git commit -m "feat(orchestration): add session file quality checks to PLANNING state"
```

---

## Task 7: Expand `session-start.md` — Non-Orchestrated Flow

**Files:**
- Modify: `plugins/aid-orchestrator/commands/session-start.md` (18 lines → ~80 lines)

**Step 1: Rewrite with Session Creation Protocol for non-orchestrated flow**

Replace entire content with:

```markdown
Start a new tracked session.

## Prerequisites

Read `.claude/skills/session-management/instructions.md` and follow the Initialization protocol (if it exists).

## Session Creation Protocol

### Step 1: Gather Sources

Before creating the session file, read ALL available sources:

1. **`workspace/active-work.md`** — current project state, recent sessions, next steps
2. **EPIC file** (if exists — `.aid-o/02-epics/` or `workspace/workflow/epics/`) — provides scope and goal. If an EPIC exists for this work, use it as primary source.
3. **Plan file** (if exists — `.aid-o/01-plans/` or `workspace/workflow/plans/`) — broader project context
4. **$ARGUMENTS or task description** — what PM wants done
5. **Relevant source code** — read key files mentioned in the task to understand current state
6. **Previous sessions** (if relevant — `workspace/sessions/`) — what was done before, lessons learned

### Step 2: Determine Session Type

Based on $ARGUMENTS or task description:
- `bug-fix` → use `templates/session-bug-fix.md`
- `new-feature` → use `templates/session-new-feature.md`
- `refactoring` → use `templates/session-refactoring.md`
- `exploration` → use `templates/session-exploration.md`

### Step 3: Create Session File

Create at: `workspace/sessions/active/YYYY-MM-DD-{type}-{topic}.md`

### Step 4: Fill Session File with Detail

**Do NOT just fill in template placeholders.** Analyze the task and produce a detailed operational document.

**Required sections and minimum detail:**

| Section | Minimum Detail | Where to Find It |
|---------|---------------|-------------------|
| **Objective** | 3-5 sentences: what, why, success criteria. Never just "Implement X". | EPIC goal (if exists) + task description |
| **Context** | Previous sessions, code state, dependencies. Reference concrete files. | active-work.md, previous sessions, git log |
| **Scope** | IN list (3+ items), OUT list (2+ items). Name specific files/components. | EPIC scope (if exists) + task analysis |
| **Phases** | Decompose task into phases. Each phase: Goal (paragraph), Agent/Role, Inputs, Outputs, Constraints, Acceptance (3+ items). | Task analysis — see decomposition rules below |
| **Dependencies** | Which phases depend on which and why. | Phase analysis |
| **Quality Gates** | What checks verify the work is correct. | Project standards, test suites |
| **Session Log** | Initialize with "Session created" entry. | — |

**Task Decomposition Rules:**
- Don't just write one big phase — break work into logical chunks
- If task spans multiple areas (backend + frontend + tests), each is a separate phase
- For each phase, determine the type of work: coding, testing, configuration, documentation
- Each phase should be completable independently (with its dependencies met)
- If you're unsure how to decompose, AskUserQuestion BEFORE creating the session file

**Phase detail — each phase MUST have:**
```
### Phase N: {Title}

**Goal:** {Full paragraph — what this phase accomplishes and why}

**Agent / Role:** {who does this work}

**Inputs:**
- {files, context, or outputs from previous phases}

**Outputs:**
- {files produced, with expected paths}

**Constraints:**
- {boundaries, compatibility requirements}

**Acceptance:**
- [ ] {how we know it's done — min 3 items}
- [ ] {criterion}
- [ ] {criterion}
```

### Step 5: Quality Check

Before presenting to PM, verify the session file:
- [ ] Objective: 3+ sentences (not a one-liner)
- [ ] Scope: IN (3+ items) and OUT (2+ items)
- [ ] Phases: each has all 6 subsections
- [ ] Dependencies: present (even if "none")
- [ ] Session Log: initialized

### Step 6: Ask PM for Approval

Present the session file to PM. Wait for approval before starting implementation.
If PM requests changes, update the session file and re-present.

Templates: `{project.paths.templates}`
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/commands/session-start.md
git commit -m "feat(session-start): expand with Session Creation Protocol and detail requirements"
```

---

## Task 8: Cross-Reference Verification

**Files:**
- Read: all 7 modified files

**Step 1: Verify consistency across all files**

Check that:
1. All 4 templates reference the same 7 required sections (Objective, Context, Scope, Phases, Dependencies, Quality Gates, Session Log)
2. All 4 templates use the same Phase subsection structure (Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance)
3. `plan-epic.md` Step 5 references the same minimum detail table
4. `epic-orchestration.md` PLANNING state references `plan-epic.md` Step 5
5. `session-start.md` uses the same Phase structure as templates
6. MIN markers are consistent (3-5 sentences for Objective, 3+ items for IN scope, 2+ items for OUT scope, 3+ items for Acceptance)

**Step 2: Final commit with all files**

If any inconsistencies found, fix them and commit:

```bash
git add -A plugins/aid-orchestrator/
git commit -m "chore: fix cross-reference inconsistencies in session templates"
```

---

## Verification

After all tasks complete:

1. **Read each template** — confirm guidance comments with MIN markers are present in every required section
2. **Read plan-epic.md Step 5** — confirm 5a-5f substeps with sources, mapping, quality check
3. **Read epic-orchestration.md** — confirm PLANNING state has session file actions (6, 7) and quality check
4. **Read session-start.md** — confirm 6-step protocol with sources list, detail table, decomposition rules
5. **Count** — 7 required sections referenced consistently across all files
6. **Grep** — search for `<!-- MIN:` markers in all 4 templates to confirm they exist
