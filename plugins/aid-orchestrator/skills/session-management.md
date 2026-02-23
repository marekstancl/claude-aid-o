# Session Management - Instructions

**Version:** 0.8.2
**Skill:** session-management
**Dependencies:** agent-core

---

## TL;DR - MUST Rules

1. **READ active-work.md** at EVERY session start (authoritative over platform memory)
2. **READ command-history.md + lessons-learned.md** at EVERY session start
3. **CREATE session file** for non-trivial work (multi-change, multi-file) — use templates, not invented structure
4. **SESSION = DETAILED WORK PLAN** — evolves with the code, captures what actually happened (see Document Hierarchy)
5. **UPDATE session file** after EVERY commit
6. **UPDATE active-work.md** at session end (current focus, recent work, next steps)
7. **ARCHIVE completed sessions** to `{project.paths.sessions_completed}/`
8. **FOLLOW lifecycle protocols** at each transition (brainstorming-end, session-start, phase-end, session-end)
9. **PHASE-END = HARD STOP** — stop, summarize what was done, wait for PM GO
10. **UPDATE project docs** at session-end (mandatory impact analysis per `playbooks/docs-{project.docs.platform}.md`)
11. **UPDATE workspace files** at session-end (command-history, lessons-learned, backlog)
12. **MONITOR context window** after each phase — warn PM if getting large
13. **REMIND yourself** of these rules periodically during long sessions

---

## Document Hierarchy

**Plan, Epic, and Session have distinct roles. Do not confuse them.**

| Document | Purpose | When Created | How It Evolves |
|----------|---------|--------------|----------------|
| **Plan** | Forming ideas, rough approach | Brainstorming / PM assignment | Static — written once, referenced later |
| **Epic** | Complex tasks, more detail and context, breakdown into sessions | Before the first session of a complex project | Updated after each session (progress, decisions) |
| **Session** | Detailed work plan for a single session | At the start of each session | **ACTIVELY EVOLVES WITH THE CODE** — that is the key benefit |

### Session file as a living document

The session file is not a static template — it is a **detailed work plan** that:
- At the start, describes WHAT will be done (based on Epic/Plan + what happened in previous sessions)
- During work, gets updated (phases, changes, decisions, commits)
- At the end, captures WHAT ACTUALLY HAPPENED (not what was planned)
- Serves as context for the next session (AI reads it and knows where things left off)

### Where to store what

```
PM assigns a task:
├── One-off (1 session)
│   ├── Bug → debugging skill → session file
│   ├── Feature → brainstorming → session file
│   └── Refactoring → session file (safety officer role)
├── Multi-session (3+)
│   └── Epic → .aid-o/02-epics/
├── Design/plan (no implementation)
│   └── Plan → .aid-o/01-plans/
└── Brainstorming
    └── → result: Plan OR Session (PM decides)

NEVER:
- Epic into plans/
- Plan into epics/
- Session file into .aid-o/
```

**CRITICAL:** `.aid-o/01-plans/` is the ONLY location for plans. `.aid-o/02-epics/` is the ONLY location for epics. NEVER anywhere else.

---

## ID System

### Format

```
{PREFIX}-{YYYYMMDD}-{4char-hash}

PREFIX:
- S = Session
- E = Epic

Hash generation:
  echo $(date +%s%N | md5sum | head -c 4)

Examples:
- S-20260210-a3f2
- E-20260210-b5c1
```

### Usage

- **Session file name:** `S-20260211-1f8c-session-mgmt-templates-debugging.md`
- **Epic file name:** `E-20260210-44f1-skills-refactoring-v4.md`
- **Frontmatter:** `id: S-20260211-1f8c`
- **Branch:** `session/S-20260211-1f8c-session-mgmt-templates-debugging`
- **Cross-reference:** `epic_id: E-20260210-44f1` in session file

---

## Session Types

| Type | When | Requires Session File | Action |
|------|------|:---------------------:|--------|
| Simple Task | Single conversation, < 3 changes | No | TodoList + active-work.md |
| Standard Session | Multiple changes, clear scope | Yes | Copy template, track progress |
| Epic Session | 3+ conversations needed | Yes + Epic file | Epic breakdown + sub-sessions |
| Verification | E2E testing, QA session | Yes | Test scenarios + results |
| Handoff | Work paused mid-implementation | Yes + Handoff block | Context preservation |
| Bug Save | Can't fix now, track later | No | bugs.md entry only |

**Decision tree:**
```
Single file + < 10 lines? → Simple task (TodoList only)
Complete in this conversation? → Standard session
Needs 3+ conversations? → Epic session
Testing/QA only? → Verification session
```

---

## Session Lifecycle

### Phase 1: Initialization (→ Session Start Protocol v4.0)

1. Read `{project.paths.active_work}` for context
2. Read `.aid-o/04-engine/command-history.md` for known working commands
3. Read `.aid-o/04-engine/lessons-learned.md` for gotchas and past lessons
4. Read `.aid-o/04-engine/memory/project-profile.yaml` for paths and conventions
5. Check `.aid-o/04-engine/memory/project-profile.yaml` — if missing or >7 days old, run `/aid-setup`
6. **Cross-project knowledge read** (per `skills/memory-mcp.md` Cross-Project Knowledge Protocol):
   - If `memory-config.yaml` -> `memory.enabled` AND `cross_project.read_at_idle: true`:
     a. `qdrant-find` with query = current session topic + tech_stack
     b. Exclude entries from current project (already in local .md files)
     c. If results found: display as informational context to PM:
        ```
        Cross-project insights (from Qdrant):
        - [{project}] {lesson_summary}
        ```
     d. If Qdrant unavailable: skip silently (no error, no warning)
7. Determine: NEW session or CONTINUATION of existing?
8. If NEW:
   a. **Assess complexity first:** Could this require 3+ sessions? If yes → suggest Epic workflow to PM before proceeding. PM decides.
   b. Generate session ID: `S-{YYYYMMDD}-{4char-hash}`
   c. Identify session type (see table above)
   d. Create session file from template:
      - Location: `{project.paths.sessions_active}/`
      - Naming: `{id}-{topic}.md` (e.g., `S-20260211-1f8c-session-mgmt-templates-debugging.md`)
      - Template: `{project.paths.templates}/session-{type}.md`
   e. Fill session file with DETAILED plan — objectives, approach, affected files, risks
   f. If epic session: reference epic file, note which session # this is, review what previous sessions accomplished
   g. Ask PM for approval to proceed
   h. After approval: create branch `session/{id}-{topic}`
9. If CONTINUATION:
   a. Load session file + plan/epic
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

Phases are defined in the session file (from plan or epic). They can be adjusted before starting each phase — announce adjustments to PM.

#### PHASE-END CHECKPOINT (HARD STOP — MANDATORY)

**Before continuing to the next phase, AI MUST:**

1. Update session file (phase = done, commit hash, changes)
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

### Session Closure Mandatory Steps (Controller MUST execute ALL during DONE state)

When the Controller transitions to DONE state for an EPIC, it MUST execute ALL
of the following steps. Failure to execute any step is a BUG in the Controller.

1. [ ] Update session frontmatter: `status: completed`, add `completed:` timestamp
2. [ ] Update Completion to `100%`
3. [ ] Run lessons-extractor agent
4. [ ] Write lessons-extractor output to `lessons-learned.md` (per-project, ALWAYS)
5. [ ] Write lessons-extractor output to `command-history.md` (per-project, ALWAYS)
6. [ ] Write lessons + commands to Qdrant with `project_name` tag (cross-project)
7. [ ] Archive session file to `sessions/archive/`
8. [ ] Append final DONE entry to `stage_log.jsonl` with `result: success`
9. [ ] Verify archived session shows `status: completed` (not `active`)

Step 6 (Qdrant) is skipped gracefully if Qdrant is not available.
Steps 4 and 5 (file-based writes) run ALWAYS, regardless of Qdrant availability.

### Phase 3: Session-End Protocol

1. Final quality gates (tests pass, no TODO/FIXME, no debug statements)
2. **UPDATE project documentation** — THIS IS MANDATORY:
   - Run documentation impact analysis against ALL changes in this session
   - Update affected docs in `{project.docs.path}` directory
   - Load platform playbook: `playbooks/docs-{project.docs.platform}.md`
   - If docs changed: verify build with `{project.docs.build_command}` (skip if null/none)
   - If no docs affected: document why not in session file
   - If `project.docs.platform == none`: skip docs update, note in session file
3. Update session file: Status = Completed, all commits listed, all files listed
4. Update active-work.md (see Active-Work Protocol)
5. Write final summary (duration, commits, files changed, what was accomplished)
6. **Update workspace files:**
   - `workspace/command-history.md` — add any new working commands discovered
   - `workspace/lessons-learned.md` — add lessons, gotchas, patterns from this session
   - `workspace/backlog.md` — update if session relates to a backlog item
7. **Memory indexing** (per `skills/memory-mcp.md` → `memory_index_session()`):
   - IF `memory-config.yaml` exists AND `memory.enabled` AND `memory.auto_index.session_end`:
     - Index decisions, lessons, commands from this session to Qdrant
   - IF disabled or fails → skip silently (non-blocking)
8. **Present PM with completion options** (REQUIRED format):

#### Standard Session (NOT last epic session):
```
If you agree, I will:
- move session to completed/
- commit changes
- merge to main
- write you a text for continuing the work in a new window

Or:
- did you find any issues that need to be resolved?
- do you want to proceed differently?
```

#### Last Session of Epic (last session of the epic):
```
If you agree, I will:
- move session to completed/
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
   b. Archive session: `mv {project.paths.sessions_active}/{file} {project.paths.sessions_completed}/{file}`
   c. If last epic session: `mv {project.paths.epics_active}/{epic-file} {project.paths.epics_completed}/{epic-file}`
   d. Update session log (`{project.paths.session_log}`) - add entry at TOP:
      ```
      ### YYYY-MM-DD - {Topic}
      - **Type:** {type} | **Summary:** {1-2 sentences}
      - **Files:** {count} | **Commits:** {count}
      - **Session:** [Link](sessions/completed/{id}-{topic}.md)
      ```
   e. Commit + merge to main
   f. **Write continuation text** for PM to paste into new chat window:
      - Epic name + next session reference
      - Session file path (if continuation)
      - Key context (1-2 sentences)

### Phase 3b: Post-Merge Protocol

**After merge to main (whether during session-end or any time later):**

1. Update session file: status = completed, merge commit hash
2. Update active-work.md: remove from current focus, add to Recent Work
3. Update backlog.md: if session addressed a backlog item, update its status
4. Session ENDS — no further changes on the branch
5. Archive session file to completed/
6. Update session-log.md

### Phase 4: Handoff (Optional)

**When:** Work paused mid-implementation, context too large, switching platforms, complex epic or multi-phase session.

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

**Where to put:** Session file (Handoff Notes section) + active-work.md + epic file (if epic) + plan file (if exists).

---

## Lifecycle Protocols

### End of Brainstorming/Planning Protocol

When brainstorming or planning finishes, Claude MUST:

1. Write a summary of what was explored and decided
2. **Assess scope and complexity:**
   - Could this fit in a single session? → recommend Session
   - Does it need 3+ sessions? → recommend Epic
   - Is it a design/plan without implementation? → recommend Plan document
3. Present recommendation to PM with reasoning:
   "Based on scope [reasoning], I recommend: [Plan / Session / Epic]. What do you prefer?"
   - **Plan** = design document for future session(s), stored in `.aid-o/01-plans/`
   - **Direct Session** = work fits in one session
   - **Epic** = complex work requiring 3+ sessions, stored in `.aid-o/02-epics/`
4. If PM chooses Plan → create Plan document in `.aid-o/01-plans/`
5. If PM chooses Epic → create Epic file in `.aid-o/02-epics/` from template
6. If PM chooses Session → proceed to Session Start Protocol (Phase 1 above)

**CRITICAL: `.aid-o/01-plans/` is the ONLY location for plan/design documents. Epics go to `.aid-o/02-epics/`. NEVER save plans or epics anywhere else.**

### Context Window Monitoring

After each phase-end:
- Assess context window usage (conversation length, tool calls, code blocks reviewed)
- If getting large, notify PM: "Context window is getting large. Consider a handoff after this phase."
- **Do NOT auto-handoff** — PM decides
- If PM agrees: create handoff block per Phase 4

### Rules Compliance Reminder

During long sessions (roughly every 2-3 phases or every major transition):
- Re-read the TL;DR rules at the top of this file
- Verify current behavior matches the lifecycle protocols
- Self-correct if any protocol step was missed

---

## Epic Sessions

**Epic = Project requiring 3+ conversations.**

### Structure
```
.aid-o/02-epics/
└── E-{YYYYMMDD}-{hash}-{topic}.md    # Epic file (plan + progress + session log)
```

Session files for epic sessions are stored in the standard `{project.paths.sessions_active}/` location, linked to the epic via `epic_id` in frontmatter.

### Workflow
1. Create epic file in `.aid-o/02-epics/` from `templates/epic-breakdown.md`
2. For each session: create session file in `{project.paths.sessions_active}/`, set `epic_id` in frontmatter
3. Session file must reference: epic file, session number, what previous sessions accomplished
4. On session completion: update epic file (session log, progress)
5. Epic completion: all sessions done, status = Completed, move to `.aid-o/02-epics/archive/`

### Cross-References
- **Session → Epic:** `epic_id: E-20260210-44f1` in frontmatter + link in References section
- **Epic → Sessions:** Session Log section in epic file with links to each session file

---

## Multi-Session EPIC Flow

### How It Works

For EPICs with 7+ steps, the Planner automatically splits execution into
multiple sessions optimized for speed and quality (see `skills/planner.md`
Section 11 -- Session Split Decision).

```
Session 1: /aid-run-epic E-xxx
  -> Controller reads plan.json, sees Session 1 steps
  -> Executes steps 1-5 (respecting dependencies + parallelism)
  -> Runs gates on session 1 outputs
  -> PM approval -> session archived -> handoff created
  -> EPIC stays active (sessions_completed: 1/2)

Session 2: /aid-run-epic E-xxx --session 2
  -> Controller reads plan_progress.json (knows steps 1-5 are done)
  -> Reads Session 1 handoff for context
  -> Executes steps 6-8
  -> Runs gates on ALL outputs (cumulative)
  -> PM approval -> session archived -> EPIC completed (2/2)
```

### Controller Behavior

- EPIC has `Session Breakdown` -> Controller follows it automatically
- No `Session Breakdown` -> single session (all steps)
- At session boundary: save `plan_progress.json`, create handoff block, commit, stop
- Next session: read `plan_progress.json` to resume from correct step
- Prior step outputs from Session 1 are available on disk (same branch)

### Handoff Between Sessions

At session end, Controller writes to `plan_progress.json`:
```json
{
  "session_completed": 1,
  "steps_done": ["step_1_architect", "step_2_domain", "step_3_backend"],
  "next_session_starts_at": "step_4_qa",
  "handoff_notes": "API complete, 24 endpoints, auth working. Tests needed."
}
```

### Archive Behavior

- Each session is archived independently on completion
- EPIC `sessions_completed` counter incremented after each session archive
- EPIC archived to `.aid-o/02-epics/archive/` only when `sessions_completed == sessions_total`
- Plan archived to `.aid-o/01-plans/archive/` only when `epics_completed == epics_total`
- See `skills/epic-orchestration.md` DONE state item 8 for full archive logic

---

## Active-Work Protocol

**Purpose:** Filesystem-based "external memory" that works across ALL platforms (Copilot, Claude Desktop, Cursor, Cline). Single source of truth for session state.

**Location:** `{project.paths.active_work}` (default: `workspace/active-work.md`)

**Template:** `{project.paths.templates}/active-work-template.md`

### When to Read

**ALWAYS at session start**, regardless of platform memory capabilities. Active-work.md is authoritative for: current focus, recent work (last 3 sessions), next steps, blockers, key decisions.

### When to Update

| Event | What to Update |
|-------|---------------|
| Task transition | Current Focus progress |
| Major decision | Known Context section |
| Blocker encountered | Blockers section |
| Session complete | Mark focus complete, add to Recent Work (top), update Next Steps, clear resolved blockers, update timestamp |
| Handoff | Add handoff details to Current Focus, update Context for Next AI |

### Key Rules

- Keep under 500 lines
- Archive older sessions (keep last 3 in Recent Work)
- If stale (>7 days), ask PM for update
- Always use `{project.*}` placeholders, not hardcoded paths

### Relationship to Other Files

| File | Purpose | Read Order |
|------|---------|:----------:|
| active-work.md | Current snapshot | 1st |
| command-history.md | Known working commands | 2nd |
| lessons-learned.md | Gotchas and past lessons | 3rd |
| session file | Detailed session plan + reality | 4th |
| plan file | High-level approach | 5th |
| session-log.md | Historical archive | On demand |
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

**Workflow:** Discover → Add to bugs.md (top) → Add to active-work.md Blockers (if blocking) → Add to session Known Issues → Continue primary work → Later: create dedicated bug-fix session.

**Resolution:** Update bugs.md status to Resolved, add notes, remove from active-work.md Blockers.

---

## Project Context Detection

On first session with a project, check if `.aid-o/04-engine/memory/project-profile.yaml` exists. If not, run `/aid-setup` to detect project context. See `commands/aid-setup.md` for details.

---

## Templates Reference

Located in: `{project.paths.templates}`

| Template | Use Case |
|----------|----------|
| session-bug-fix.md | Bug investigation and fixes |
| session-new-feature.md | Feature development |
| session-refactoring.md | Code cleanup with before/after tracking |
| session-exploration.md | Research and investigation |
| epic-breakdown.md | Multi-phase projects (3+ sessions) |
| active-work-template.md | Initial active-work.md setup |

**Note:** Templates serve as STARTING POINT. Session file must be filled with detailed, specific content — objectives, affected files, approach, risks. A session file with only template placeholders is incomplete.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Coding without session file | Create file for multi-change work |
| Shallow session file (only placeholders) | Fill with detailed plan — session file = your work plan |
| Forgetting session file updates | Update after EVERY commit |
| Session file for tiny changes | Use TodoList instead |
| Skipping active-work.md | Read at start, update at end |
| Skipping command-history + lessons-learned | Read at start, update at end |
| Insufficient handoff | Make self-contained (no questions needed) |
| Hardcoded paths | Use `{project.*}` placeholders |
| Not archiving | Move to completed/ + update session-log.md |
| Skipping Phase-End HARD STOP | **MUST stop and wait for PM GO** — this is not optional |
| Continuing without PM approval | NEVER proceed to next phase without explicit GO |
| Skipping project docs at session-end | ALWAYS run impact analysis before final commit (per docs platform playbook) |
| Auto-handoff without PM consent | Only WARN about context window, PM decides |
| Committing without PM asking | Always ask PM before commit and PR/merge |
| Saving plans outside .aid-o/01-plans/ | **ONLY** `.aid-o/01-plans/` — no other location, ever |
| Confusing Plan/Epic/Session | Plan = idea, Epic = context, Session = detailed work plan |

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
    templates/                       # session templates, plan template, epic template
    playbooks/                       # role playbooks, docs playbooks
  04-engine/                         # AI internal
    sessions/                        # Active session files
      archive/                       # Completed sessions
    memory/
      active-work.md                 # Current state, recent work
      project-profile.yaml           # Project config (from /aid-setup)
      decisions.yaml                 # Key decisions log
    backlog.md                       # Improvement backlog
    lessons-learned.md               # Lessons from sessions
    command-history.md               # Known working commands
    evidence/                        # EPIC execution evidence
```

**Conventions:**
- Session file: `{id}-{topic}.md` (e.g., `S-20260211-1f8c-user-auth.md`)
- Session ID: `S-{YYYYMMDD}-{4char-hash}`
- Epic ID: `E-{YYYYMMDD}-{4char-hash}`
- Branch: `session/{id}-{topic}`

---

## Integration

| Skill | How |
|-------|-----|
| agent-core | Session init protocol, role detection informs session type |
| quality-gates | Pre-commit checks in work loop, final gates at completion |
| git-workflow | Branch naming from session conventions, commit discipline |
| documentation-protocol | Doc updates in work loop, same-commit principle |
| debugging | Bug triage and fix workflows (3 modes) |
| project-context-detection | Auto-detects project architecture at first session |

---

**Version:** 0.8.2
**Last Updated:** 2026-02-23
