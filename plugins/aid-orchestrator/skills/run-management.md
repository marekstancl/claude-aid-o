# Run Management - Instructions

**Skill:** run-management
**Dependencies:** agent-core

---

## TL;DR - MUST Rules

1. **READ active-work.md** at EVERY run start (authoritative over platform memory)
2. **READ command-history.md + lessons-learned.md** at EVERY run start
3. **CREATE run file** for non-trivial work (multi-change, multi-file) — use templates, not invented structure
4. **RUN = DETAILED WORK PLAN** — evolves with the code, captures what actually happened (see Document Hierarchy)
5. **UPDATE run file** after EVERY commit
6. **UPDATE active-work.md** at run end (current focus, recent work, next steps)
7. **ARCHIVE completed runs** to `{project.paths.runs_completed}/`
8. **FOLLOW lifecycle protocols** at each transition (brainstorming-end, run-start, phase-end, run-end)
9. **PHASE-END = HARD STOP** — stop, summarize what was done, wait for PM GO
10. **UPDATE project docs** at run-end (mandatory impact analysis per `playbooks/docs-{project.docs.platform}.md`)
11. **UPDATE workspace files** at run-end (command-history, lessons-learned, backlog)
12. **MONITOR context window** after each phase — warn PM if getting large
13. **REMIND yourself** of these rules periodically during long runs

---

## Document Hierarchy

**Plan, Epic, and Run have distinct roles. Do not confuse them.**

| Document | Purpose | When Created | How It Evolves |
|----------|---------|--------------|----------------|
| **Plan** | Forming ideas, rough approach | Brainstorming / PM assignment | Static — written once, referenced later |
| **Epic** | Complex tasks, more detail and context, breakdown into runs | Before the first run of a complex project | Updated after each run (progress, decisions) |
| **Run** | Detailed work plan for a single run | At the start of each run | **ACTIVELY EVOLVES WITH THE CODE** — that is the key benefit |

### Run file as a living document

The run file is not a static template — it is a **detailed work plan** that:
- At the start, describes WHAT will be done (based on Epic/Plan + what happened in previous runs)
- During work, gets updated (phases, changes, decisions, commits)
- At the end, captures WHAT ACTUALLY HAPPENED (not what was planned)
- Serves as context for the next run (AI reads it and knows where things left off)

### Where to store what

```
PM assigns a task:
├── One-off (1 run)
│   ├── Bug → debugging skill → run file
│   ├── Feature → brainstorming → run file
│   └── Refactoring → run file (safety officer role)
├── Multi-run (3+)
│   └── Epic → .aid-o/02-epics/
├── Design/plan (no implementation)
│   └── Plan → .aid-o/01-plans/
└── Brainstorming
    └── → result: Plan OR Run (PM decides)

NEVER:
- Epic into plans/
- Plan into epics/
- Run file into .aid-o/
```

**CRITICAL:** `.aid-o/01-plans/` is the ONLY location for plans. `.aid-o/02-epics/` is the ONLY location for epics. NEVER anywhere else.

---

## ID System

> **Authoritative reference:** `skills/epic-orchestration.md` → "ID Generation" section.
> This section is a summary. If in doubt, follow epic-orchestration.md.

### Format

IDs are sequential, derived from `.aid-o/03-config/counter.yaml`, and encode parent-child relationships.

```
Plan:              P{NNN}                        (P001, P006)
EPIC from plan:    E-{NNN}-{phase}_{total}       (E-005-1_4, E-006-1_1)
Ad-hoc EPIC:       E-{NNN}                       (E-001, E-002)
Run:               R-{EPIC_ID}-{run_number}      (R-005-1_4-1, R-001-1_1-1)

Where NNN = zero-padded 3-digit number from counter.yaml.

Examples:
- Plan P005 with 4 phases → E-005-1_4, E-005-2_4, E-005-3_4, E-005-4_4
- First run of E-005-1_4 → R-005-1_4-1
- Ad-hoc EPIC (no plan) → E-001 (epic counter incremented)
```

### Usage

- **Run file name:** `R-005-1_4-1-gui-foundation.md`
- **Epic file name:** `E-005-1_4-gui-foundation.md`
- **Frontmatter:** `id: R-005-1_4-1`
- **Branch:** `run/R-005-1_4-1-gui-foundation`
- **Cross-reference:** `epic_id: E-005-1_4` in run file

---

## Run Types

| Type | When | Requires Run File | Action |
|------|------|:---------------------:|--------|
| Simple Task | Single conversation, < 3 changes | No | TodoList + active-work.md |
| Standard Run | Multiple changes, clear scope | Yes | Copy template, track progress |
| Epic Run | 3+ conversations needed | Yes + Epic file | Epic breakdown + sub-runs |
| Verification | E2E testing, QA run | Yes | Test scenarios + results |
| Handoff | Work paused mid-implementation | Yes + Handoff block | Context preservation |
| Bug Save | Can't fix now, track later | No | bugs.md entry only |

**Decision tree:**
```
Single file + < 10 lines? → Simple task (TodoList only)
Complete in this conversation? → Standard run
Needs 3+ conversations? → Epic run
Testing/QA only? → Verification run
```

---

## Run Lifecycle

### Phase 1: Initialization (→ Run Start Protocol v4.0)

1. Read `{project.paths.active_work}` for context
2. Read `.aid-o/04-engine/command-history.md` for known working commands
3. Read `.aid-o/04-engine/lessons-learned.md` for gotchas and past lessons
4. Read `.aid-o/04-engine/memory/project-profile.yaml` for paths and conventions
5. Check `.aid-o/04-engine/memory/project-profile.yaml` — if missing or >7 days old, run `/aid-setup`
6. **Cross-project knowledge read** (per `skills/memory-mcp.md` Cross-Project Knowledge Protocol):
   - If `memory-config.yaml` -> `memory.enabled` AND `cross_project.read_at_idle: true`:
     a. `qdrant-find` with query = current run topic + tech_stack
     b. Exclude entries from current project (already in local .md files)
     c. If results found: display as informational context to PM:
        ```
        Cross-project insights (from Qdrant):
        - [{project}] {lesson_summary}
        ```
     d. If Qdrant unavailable: skip silently (no error, no warning)
7. Determine: NEW run or CONTINUATION of existing?
8. If NEW:
   a. **Assess complexity first:** Could this require 3+ runs? If yes → suggest Epic workflow to PM before proceeding. PM decides.
   b. Generate run ID per `skills/epic-orchestration.md` ID Generation section
   c. Identify run type (see table above)
   d. Create run file from template:
      - Location: `{project.paths.runs_active}/`
      - Naming: `{id}-{topic}.md` (e.g., `R-005-1_4-1-gui-foundation.md`)
      - Template: `{project.paths.templates}/run-{type}.md`
      - **EPIC runs:** When an EPIC is being executed, the run file is pre-created by
        `plugins/aid-orchestrator/scripts/aid-json-to-run.sh` during the `/aid-plan-epic`
        pipeline. The Controller reads this pre-existing run file rather than creating one.
   e. Fill run file with DETAILED plan — objectives, approach, affected files, risks
   f. If epic run: reference epic file, note which run # this is, review what previous runs accomplished
   g. Ask PM for approval to proceed
   h. After approval: create branch `run/{id}-{topic}`
9. If CONTINUATION:
   a. Load run file + plan/epic
   b. Review last phase status and any handoff notes
   c. Announce what will be done next
   d. Ask PM for approval to continue

### Phase 2: Work Loop (Phase-based)

```
Loop until complete:
  1. Announce phase start (what will be done, optionally adjust scope)
  2. Implement phase
  3. Self-test
  4. --- PHASE-END CHECKPOINT (HARD STOP) ---
  5. PM says GO → run quality gates → commit (per git-workflow) → next phase
  6. PM says STOP → create handoff (see Phase 4)
```

Phases are defined in the run file (from plan or epic). They can be adjusted before starting each phase — announce adjustments to PM.

#### PHASE-END CHECKPOINT (HARD STOP — MANDATORY)

**Before continuing to the next phase, AI MUST:**

1. Update run file (phase = done, commit hash, changes)
2. Update active-work.md (progress, decisions)
3. Write a summary: 2-3 sentences about what was done
4. If the phase contains testable changes:
   → Propose manual QA steps (specific, actionable)
5. If this is the last phase:
   → Testing proposal is MANDATORY
6. Check context window — if it is large, warn PM
7. **STOP and ask PM:**
   "Phase X completed. [summary]. Proceed to phase Y?"
8. **DO NOT CONTINUE until PM says GO**

**Violating this checkpoint = AI error.**

### Run Closure Mandatory Steps (Controller MUST execute ALL during DONE state)

When the Controller transitions to DONE state for an EPIC, it MUST execute ALL
of the following steps. Failure to execute any step is a BUG in the Controller.

1. [ ] Update run frontmatter: `status: completed`, add `completed:` timestamp
2. [ ] Update Completion to `100%`
3. [ ] Run lessons-extractor agent
4. [ ] Write lessons-extractor output to `lessons-learned.md` (per-project, ALWAYS)
5. [ ] Write lessons-extractor output to `command-history.md` (per-project, ALWAYS)
6. [ ] Write lessons + commands to Qdrant with `project_name` tag (cross-project)
7. [ ] Archive run file to `runs/archive/`
8. [ ] Append final DONE entry to `stage_log.jsonl` with `result: success`
9. [ ] Verify archived run shows `status: completed` (not `active`)

Step 6 (Qdrant) is skipped gracefully if Qdrant is not available.
Steps 4 and 5 (file-based writes) run ALWAYS, regardless of Qdrant availability.

### Phase 3: Run-End Protocol

1. Final quality gates (tests pass, no TODO/FIXME, no debug statements)
2. **UPDATE project documentation** — THIS IS MANDATORY:
   - Run documentation impact analysis against ALL changes in this run
   - Update affected docs in `{project.docs.path}` directory
   - Load platform playbook: `playbooks/docs-{project.docs.platform}.md`
   - If docs changed: verify build with `{project.docs.build_command}` (skip if null/none)
   - If no docs affected: document why not in run file
   - If `project.docs.platform == none`: skip docs update, note in run file
3. Update run file: Status = Completed, all commits listed, all files listed
4. Update active-work.md (see Active-Work Protocol)
5. Write final summary (duration, commits, files changed, what was accomplished)
6. **Update workspace files:**
   - `workspace/command-history.md` — add any new working commands discovered
   - `workspace/lessons-learned.md` — add lessons, gotchas, patterns from this run
   - `workspace/backlog.md` — update if run relates to a backlog item
7. **Memory indexing** (per `skills/memory-mcp.md` → `memory_index_run()`):
   - IF `memory-config.yaml` exists AND `memory.enabled` AND `memory.auto_index.run_end`:
     - Index decisions, lessons, commands from this run to Qdrant
   - IF disabled or fails → skip silently (non-blocking)
8. **Present PM with completion options** (REQUIRED format):

#### Standard Run (NOT last epic run):
```
If you agree, I will:
- move run to completed/
- commit changes
- merge to main
- write you a text for continuing the work in a new window

Or:
- did you find any issues that need to be resolved?
- do you want to proceed differently?
```

#### Last Run of Epic (last run of the epic):
```
If you agree, I will:
- move run to completed/
- move epic to .aid-o/02-epics/archive/
- update epic file (status = Completed)
- commit changes
- merge to main

Or:
- did you find any issues that need to be resolved?
- do you want to proceed differently?
```

8. If PM approves:
   a. Update active-work.md with final state
   b. Archive run: `mv {project.paths.runs_active}/{file} {project.paths.runs_completed}/{file}`
   c. If last epic run: `mv {project.paths.epics_active}/{epic-file} {project.paths.epics_completed}/{epic-file}`
   d. Update run log (`{project.paths.run_log}`) - add entry at TOP:
      ```
      ### YYYY-MM-DD - {Topic}
      - **Type:** {type} | **Summary:** {1-2 sentences}
      - **Files:** {count} | **Commits:** {count}
      - **Run:** [Link](runs/completed/{id}-{topic}.md)
      ```
   e. Commit + merge to main
   f. **Write continuation text** for PM to paste into new chat window:
      - Epic name + next run reference
      - Run file path (if continuation)
      - Key context (1-2 sentences)

### Phase 3b: Post-Merge Protocol

**After merge to main (whether during run-end or any time later):**

1. Update run file: status = completed, merge commit hash
2. Update active-work.md: remove from current focus, add to Recent Work
3. Update backlog.md: if run addressed a backlog item, update its status
4. Run ENDS — no further changes on the branch
5. Archive run file to completed/
6. Update run-log.md

### Phase 4: Handoff (Optional)

**When:** Work paused mid-implementation, context too large, switching platforms, complex epic or multi-phase run.

**Handoff block must include:**

| Section | Content |
|---------|---------|
| Completed | Tasks done with commit hashes and files |
| Now Working On | Current task, progress %, files in progress, next immediate step |
| Next Steps | Ordered list of remaining actions |
| Important Context | Decisions made, known issues/gotchas, dependencies |
| Key Locations | Config, tests, docs, logs paths |
| How to Test | Commands to verify current state |
| Branch | Branch name + last commit hash |

**Quality check:** Handoff is self-contained if next AI can continue without asking questions.

**Where to put:** Run file (Handoff Notes section) + active-work.md + epic file (if epic) + plan file (if exists).

---

## Lifecycle Protocols

### End of Brainstorming/Planning Protocol

When brainstorming or planning finishes, Claude MUST:

1. Write a summary of what was explored and decided
2. **Assess scope and complexity:**
   - Could this fit in a single run? → recommend Run
   - Does it need 3+ runs? → recommend Epic
   - Is it a design/plan without implementation? → recommend Plan document
3. Present recommendation to PM with reasoning:
   "Based on scope [reasoning], I recommend: [Plan / Run / Epic]. What do you prefer?"
   - **Plan** = design document for future run(s), stored in `.aid-o/01-plans/`
   - **Direct Run** = work fits in one run
   - **Epic** = complex work requiring 3+ runs, stored in `.aid-o/02-epics/`
4. If PM chooses Plan → create Plan document in `.aid-o/01-plans/`
5. If PM chooses Epic → create Epic file in `.aid-o/02-epics/` from template
6. If PM chooses Run → proceed to Run Start Protocol (Phase 1 above)

**CRITICAL: `.aid-o/01-plans/` is the ONLY location for plan/design documents. Epics go to `.aid-o/02-epics/`. NEVER save plans or epics anywhere else.**

### Context Window Monitoring

After each phase-end:
- Assess context window usage (conversation length, tool calls, code blocks reviewed)
- If getting large, notify PM: "Context window is getting large. Consider a handoff after this phase."
- **Do NOT auto-handoff** — PM decides
- If PM agrees: create handoff block per Phase 4

### Rules Compliance Reminder

During long runs (roughly every 2-3 phases or every major transition):
- Re-read the TL;DR rules at the top of this file
- Verify current behavior matches the lifecycle protocols
- Self-correct if any protocol step was missed

---

## Epic Runs

**Epic = Project requiring 3+ conversations.**

### Structure
```
.aid-o/02-epics/
└── E-{NNN}-{phase}_{total}-{topic}.md  # Epic file (plan + progress + run log)
```

Run files for epic runs are stored in the standard `{project.paths.runs_active}/` location, linked to the epic via `epic_id` in frontmatter.

### Workflow
1. Create epic file in `.aid-o/02-epics/` from `templates/epic.md`
2. For each run: create run file in `{project.paths.runs_active}/`, set `epic_id` in frontmatter
3. Run file must reference: epic file, run number, what previous runs accomplished
4. On run completion: update epic file (run log, progress)
5. Epic completion: all runs done, status = Completed, move to `.aid-o/02-epics/archive/`

### Cross-References
- **Run → Epic:** `epic_id: E-005-1_4` in frontmatter + link in References section
- **Epic → Runs:** Run Log section in epic file with links to each run file

---

## Multi-Run EPIC Flow

### How It Works

For EPICs with 7+ steps, the Planner automatically splits execution into
multiple runs optimized for speed and quality (see `skills/planner.md`
Section 11 -- Run Split Decision).

```
Run 1: /aid-run-epic E-xxx
  -> Controller reads plan.json, sees Run 1 steps
  -> Executes steps 1-5 (respecting dependencies + parallelism)
  -> Runs gates on run 1 outputs
  -> PM approval -> run archived -> handoff created
  -> EPIC stays active (runs_completed: 1/2)

Run 2: /aid-run-epic E-xxx --run 2
  -> Controller reads plan_progress.json (knows steps 1-5 are done)
  -> Reads Run 1 handoff for context
  -> Executes steps 6-8
  -> Runs gates on ALL outputs (cumulative)
  -> PM approval -> run archived -> EPIC completed (2/2)
```

### Controller Behavior

- EPIC has `Run Breakdown` -> Controller follows it automatically
- No `Run Breakdown` -> single run (all steps)
- At run boundary: save `plan_progress.json`, create handoff block, commit, stop
- Next run: read `plan_progress.json` to resume from correct step
- Prior step outputs from Run 1 are available on disk (same branch)

### Handoff Between Runs

At run end, Controller writes to `plan_progress.json`:
```json
{
  "run_completed": 1,
  "steps_done": ["step_1_architect", "step_2_domain", "step_3_backend"],
  "next_run_starts_at": "step_4_qa",
  "handoff_notes": "API complete, 24 endpoints, auth working. Tests needed."
}
```

### Archive Behavior

- Each run is archived independently on completion
- EPIC `runs_completed` counter incremented after each run archive
- EPIC archived to `.aid-o/02-epics/archive/` only when `runs_completed == runs_total`
- Plan archived to `.aid-o/01-plans/archive/` only when `epics_completed == epics_total`
- See `skills/epic-orchestration.md` DONE state item 8 for full archive logic

---

## Active-Work Protocol

**Purpose:** Filesystem-based "external memory" that works across ALL platforms (Copilot, Claude Desktop, Cursor, Cline). Single source of truth for run state.

**Location:** `{project.paths.active_work}` (default: `workspace/active-work.md`)

**Template:** `{project.paths.templates}/active-work-template.md`

### When to Read

**ALWAYS at run start**, regardless of platform memory capabilities. Active-work.md is authoritative for: current focus, recent work (last 3 runs), next steps, blockers, key decisions.

### When to Update

| Event | What to Update |
|-------|---------------|
| Task transition | Current Focus progress |
| Major decision | Known Context section |
| Blocker encountered | Blockers section |
| Run complete | Mark focus complete, add to Recent Work (top), update Next Steps, clear resolved blockers, update timestamp |
| Handoff | Add handoff details to Current Focus, update Context for Next AI |

### Key Rules

- Keep under 500 lines
- Archive older runs (keep last 3 in Recent Work)
- If stale (>7 days), ask PM for update
- Always use `{project.*}` placeholders, not hardcoded paths

### Relationship to Other Files

| File | Purpose | Read Order |
|------|---------|:----------:|
| active-work.md | Current snapshot | 1st |
| command-history.md | Known working commands | 2nd |
| lessons-learned.md | Gotchas and past lessons | 3rd |
| run file | Detailed run plan + reality | 4th |
| plan file | High-level approach | 5th |
| run-log.md | Historical archive | On demand |
| bugs.md | Bug tracking | On demand |

---

## Bug Tracking

**When:** Can't fix now, non-critical issue found during other work, technical debt identified.

**Location:** `{project.paths.bugs}`

**Format:**
```
| Date | ID | Bug | Severity | Status | Notes |
|------|-----|-----|----------|--------|-------|
| YYYY-MM-DD | BUG-XXX | {Title} | High/Med/Low | Open | {Context} |
```

**Workflow:** Discover → Add to bugs.md (top) → Add to active-work.md Blockers (if blocking) → Add to run Known Issues → Continue primary work → Later: create dedicated bug-fix run.

**Resolution:** Update bugs.md status to Resolved, add notes, remove from active-work.md Blockers.

---

## Project Context Detection

On first run with a project, check if `.aid-o/04-engine/memory/project-profile.yaml` exists. If not, run `/aid-setup` to detect project context. See `commands/aid-setup.md` for details.

---

## Templates Reference

Located in: `{project.paths.templates}`

| Template | Use Case |
|----------|----------|
| run-bug-fix.md | Bug investigation and fixes |
| run-new-feature.md | Feature development |
| run-refactoring.md | Code cleanup with before/after tracking |
| run-exploration.md | Research and investigation |
| epic.md | Multi-phase projects (3+ runs) |
| active-work-template.md | Initial active-work.md setup |

**Note:** Templates serve as STARTING POINT. Run file must be filled with detailed, specific content — objectives, affected files, approach, risks. A run file with only template placeholders is incomplete.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Coding without run file | Create file for multi-change work |
| Shallow run file (only placeholders) | Fill with detailed plan — run file = your work plan |
| Forgetting run file updates | Update after EVERY commit |
| Run file for tiny changes | Use TodoList instead |
| Skipping active-work.md | Read at start, update at end |
| Skipping command-history + lessons-learned | Read at start, update at end |
| Insufficient handoff | Make self-contained (no questions needed) |
| Hardcoded paths | Use `{project.*}` placeholders |
| Not archiving | Move to completed/ + update run-log.md |
| Skipping Phase-End HARD STOP | **MUST stop and wait for PM GO** — this is not optional |
| Continuing without PM approval | NEVER proceed to next phase without explicit GO |
| Skipping project docs at run-end | ALWAYS run impact analysis before final commit (per docs platform playbook) |
| Auto-handoff without PM consent | Only WARN about context window, PM decides |
| Committing without PM asking | Always ask PM before commit and PR/merge |
| Saving plans outside .aid-o/01-plans/ | **ONLY** `.aid-o/01-plans/` — no other location, ever |
| Confusing Plan/Epic/Run | Plan = idea, Epic = context, Run = detailed work plan |

---

## Configuration

Standard `.aid-o/` paths (created by `/aid-init`):

```
.aid-o/
  01-plans/                          # Plans
    archive/
  02-epics/                          # EPICs
    archive/
  03-config/                         # PM-customizable config
    policies/                        # gates.yaml, decision-policies.yaml, slack-config.yaml
    templates/                       # run templates, plan template, epic template
    playbooks/                       # role playbooks, docs playbooks
  04-engine/                         # AI internal
    runs/                        # Active run files
      archive/                       # Completed runs
    memory/
      active-work.md                 # Current state, recent work
      project-profile.yaml           # Project config (from /aid-setup)
      decisions.yaml                 # Key decisions log
    backlog.md                       # Improvement backlog
    lessons-learned.md               # Lessons from runs
    command-history.md               # Known working commands
    evidence/                        # EPIC execution evidence
```

**Conventions:**
- Run file: `{id}-{topic}.md` (e.g., `R-005-1_4-1-user-auth.md`)
- Run ID: `R-{EPIC_ID}-{run_number}` (e.g., `R-005-1_4-1`)
- Epic ID: `E-{NNN}-{phase}_{total}` or `E-{NNN}` for ad-hoc (e.g., `E-005-1_4`)
- Branch: `run/{id}-{topic}`

---

## Integration

| Skill | How |
|-------|-----|
| agent-core | Run init protocol, role detection informs run type |
| quality-gates | Pre-commit checks in work loop, final gates at completion |
| git-workflow | Branch naming from run conventions, commit discipline |
| documentation-protocol | Doc updates in work loop, same-commit principle |
| debugging | Bug triage and fix workflows (3 modes) |
| project-context-detection | Auto-detects project architecture at first run |
| aid-json-to-run.sh | Script that generates run files from plan.json for EPIC runs (invoked by `/aid-plan-epic` pipeline) |

---

**Last Updated:** 2026-02-28
