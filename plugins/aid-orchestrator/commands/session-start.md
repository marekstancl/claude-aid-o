---
name: session-start
description: Start a tracked session
user_invocable: true
---

Start a new tracked session.

Read `skills/session-management.md` and follow the Initialization protocol.

## Session Creation Protocol

### Step 1: Gather Sources

Before creating the session file, read ALL available sources:

1. **`active-work.md`** (`.aid-o/04-engine/memory/active-work.md`) — current project state, recent sessions, next steps
2. **EPIC file** (if exists — `.aid-o/02-epics/`) — provides scope and goal. If an EPIC exists for this work, use it as primary source.
3. **Plan file** (if exists — `.aid-o/01-plans/`) — broader project context
4. **$ARGUMENTS or task description** — what PM wants done
5. **Relevant source code** — read key files mentioned in the task to understand current state
6. **Previous sessions** (if relevant — `.aid-o/04-engine/sessions/`) — what was done before, lessons learned

### Step 2: Determine Session Type

Based on $ARGUMENTS or task description:
- `bug-fix` → use `.aid-o/03-config/templates/session-bug-fix.md`
- `new-feature` → use `.aid-o/03-config/templates/session-new-feature.md`
- `refactoring` → use `.aid-o/03-config/templates/session-refactoring.md`
- `exploration` → use `.aid-o/03-config/templates/session-exploration.md`

### Step 3: Create Session File

Create at: `.aid-o/04-engine/sessions/S-{YYYYMMDD}-{4char-hash}-{topic}.md`

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
- If EPIC exists, use it as primary source for scope and goal (user request adds detail/priority)
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
- [ ] Context: references to previous work or "greenfield" statement
- [ ] Scope: IN (3+ items) and OUT (2+ items)
- [ ] Phases: each has all 6 subsections (Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance)
- [ ] Dependencies: present (even if "No inter-phase dependencies")
- [ ] Quality Gates: at least one gate listed
- [ ] Session Log: initialized

### Step 6: Ask PM for Approval

Present the session file to PM. Wait for approval before starting implementation.
If PM requests changes, update the session file and re-present.

Templates: `.aid-o/03-config/templates/`
