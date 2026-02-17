# Session Management - Instructions

**Version:** 4.0.0
**Skill:** session-management
**Dependencies:** agent-core

---

## TL;DR - MUST Rules

1. **READ active-work.md** at EVERY session start (authoritative over platform memory)
2. **READ command-history.md + lessons-learned.md** at EVERY session start
3. **CREATE session file** for non-trivial work (multi-change, multi-file) — use templates, not invented structure
4. **SESSION = DETAILED WORK PLAN** — evolvuje s kodem, zachycuje co se realne stalo (viz Document Hierarchy)
5. **UPDATE session file** after EVERY commit
6. **UPDATE active-work.md** at session end (current focus, recent work, next steps)
7. **ARCHIVE completed sessions** to `{project.paths.sessions_completed}/`
8. **FOLLOW lifecycle protocols** at each transition (brainstorming-end, session-start, phase-end, session-end)
9. **PHASE-END = HARD STOP** — zastav se, shrn co bylo udelano, cekej na PM GO
10. **UPDATE project docs** at session-end (mandatory impact analysis per `playbooks/docs-{project.docs.platform}.md`)
11. **UPDATE workspace files** at session-end (command-history, lessons-learned, backlog)
12. **MONITOR context window** after each phase — warn PM if getting large
13. **REMIND yourself** of these rules periodically during long sessions

---

## Document Hierarchy

**Plan, Epic a Session maji odlisne role. Neplest je.**

| Dokument | Ucel | Kdy vznikne | Jak se vyviji |
|----------|------|-------------|---------------|
| **Plan** | Formovani napadu, hruby postup | Brainstorming / PM zadani | Staticke — jednou napsany, referencuje se |
| **Epic** | Slozitejsi ulohy, vetsi detail a kontext, rozpad na sessions | Pred prvni session slozitejsiho projektu | Aktualizuje se po kazde session (progress, decisions) |
| **Session** | Detailni plan prace pro jednu session | Na zacatku kazde session | **AKTIVNE SE VYVIJI S KODEM** — to je klicovy benefit |

### Session file jako zivy dokument

Session file neni staticka sablona — je to **detailni plan prace**, ktery:
- Na zacatku popisuje CO se bude delat (na zaklade Epic/Plan + co se stalo v predchozich sessions)
- Behem prace se aktualizuje (faze, zmeny, rozhodnuti, commity)
- Na konci zachycuje CO SE REALNE STALO (ne co bylo planovano)
- Slouzi jako kontext pro dalsi session (AI si precte a vi kde se skoncilo)

### Kde co ukladat

```
PM zada ukol:
├── Jednorazovy (1 session)
│   ├── Bug → debugging skill → session file
│   ├── Feature → brainstorming → session file
│   └── Refaktoring → session file (safety officer role)
├── Vicesession (3+)
│   └── Epic → workspace/workflow/epics/active/
├── Design/plan (bez implementace)
│   └── Plan → workspace/workflow/plans/
└── Brainstorming
    └── → vysledek: Plan NEBO Session (PM rozhodne)

NIKDY:
- Epic do plans/
- Plan do epics/
- Session file do workflow/
```

**CRITICAL:** `workspace/workflow/plans/` je JEDINE misto pro plany. `workspace/workflow/epics/` je JEDINE misto pro epics. NIKDY jinam.

---

## ID System

### Format

```
{PREFIX}-{YYYYMMDD}-{4char-hash}

PREFIX:
- S = Session
- E = Epic

Hash generovani:
  echo $(date +%s%N | md5sum | head -c 4)

Priklady:
- S-20260210-a3f2
- E-20260210-b5c1
```

### Pouziti

- **Session file nazev:** `S-20260211-1f8c-session-mgmt-templates-debugging.md`
- **Epic file nazev:** `E-20260210-44f1-skills-refactoring-v4.md`
- **Frontmatter:** `id: S-20260211-1f8c`
- **Branch:** `session/S-20260211-1f8c-session-mgmt-templates-debugging`
- **Cross-reference:** `epic_id: E-20260210-44f1` v session file

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
2. Read `workspace/command-history.md` for known working commands
3. Read `workspace/lessons-learned.md` for gotchas and past lessons
4. Read `.claude/project.json` for paths and conventions
5. Check `.claude/project-context/` — if missing or >7 days old, run project-context-detection
6. Determine: NEW session or CONTINUATION of existing?
7. If NEW:
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
8. If CONTINUATION:
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

#### PHASE-END CHECKPOINT (HARD STOP — POVINNE)

**Pred pokracovanim na dalsi fazi AI MUSI:**

1. Aktualizovat session file (faze = done, commit hash, zmeny)
2. Aktualizovat active-work.md (progress, rozhodnuti)
3. Napsat shrnuti: 2-3 vety co bylo udelano
4. Pokud faze obsahuje testovatelne zmeny:
   → Navrhnout manualni QA kroky (konkretni, klikatelne)
5. Pokud je to posledni faze:
   → Testing proposal je POVINNY
6. Zkontrolovat context window — pokud je velky, upozornit PM
7. **ZASTAVIT SE a zeptat PM:**
   "Faze X dokoncena. [shrnuti]. Pokracovat na fazi Y?"
8. **NEPOKRACOVAT dokud PM nerekne GO**

**Poruseni tohoto checkpointu = chyba AI.**

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
7. **Present PM with completion options** (REQUIRED format):

#### Standard Session (NOT last epic session):
```
Pokud souhlasis, tak:
- presunu session do completed/
- commitnu zmeny
- mergnu do main
- napisu ti text pro zadani pokracovani prace v novem okne

Nebo:
- nasel jsi nejake nedostatky, ktere je treba vyresit?
- chces postupovat jinak?
```

#### Last Session of Epic (posledni session epicu):
```
Pokud souhlasis, tak:
- presunu session do completed/
- presunu epic do workspace/workflow/epics/completed/
- aktualizuji epic file (status = Completed)
- commitnu zmeny
- mergnu do main

Nebo:
- nasel jsi nejake nedostatky, ktere je treba vyresit?
- chces postupovat jinak?
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

**Po merge do main (at uz behem session-end nebo kdykoli pozdeji):**

1. Update session file: status = completed, merge commit hash
2. Update active-work.md: remove from current focus, add to Recent Work
3. Update backlog.md: pokud session resila backlog item, aktualizovat jeho status
4. Session KONCI — zadne dalsi zmeny na branchi
5. Archive session file do completed/
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
   - **Plan** = design document for future session(s), stored in `workspace/workflow/plans/`
   - **Direct Session** = work fits in one session
   - **Epic** = complex work requiring 3+ sessions, stored in `workspace/workflow/epics/active/`
4. If PM chooses Plan → create Plan document in `workspace/workflow/plans/`
5. If PM chooses Epic → create Epic file in `workspace/workflow/epics/active/` from template
6. If PM chooses Session → proceed to Session Start Protocol (Phase 1 above)

**CRITICAL: `workspace/workflow/plans/` is the ONLY location for plan/design documents. Epics go to `workspace/workflow/epics/`. NEVER save plans or epics anywhere else.**

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
workspace/workflow/epics/active/
└── E-{YYYYMMDD}-{hash}-{topic}.md    # Epic file (plan + progress + session log)
```

Session files for epic sessions are stored in the standard `{project.paths.sessions_active}/` location, linked to the epic via `epic_id` in frontmatter.

### Workflow
1. Create epic file in `workspace/workflow/epics/active/` from `templates/epic-breakdown.md`
2. For each session: create session file in `{project.paths.sessions_active}/`, set `epic_id` in frontmatter
3. Session file must reference: epic file, session number, what previous sessions accomplished
4. On session completion: update epic file (session log, progress)
5. Epic completion: all sessions done, status = Completed, move to `workspace/workflow/epics/completed/`

### Cross-References
- **Session → Epic:** `epic_id: E-20260210-44f1` in frontmatter + link in References section
- **Epic → Sessions:** Session Log section in epic file with links to each session file

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

On first session with a project, check if `.claude/project-context/` exists. If not, load `project-context-detection` skill and run detection protocol. See that skill for details.

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
| Saving plans outside workspace/workflow/plans/ | **ONLY** `workspace/workflow/plans/` — no other location, ever |
| Confusing Plan/Epic/Session | Plan = idea, Epic = context, Session = detailed work plan |

---

## Configuration

From `.claude/project.json`:
```json
{
  "paths": {
    "workspace": "workspace/",
    "sessions": "workspace/sessions/",
    "sessions_active": "workspace/sessions/active/",
    "sessions_completed": "workspace/sessions/completed/",
    "templates": ".claude/skills/session-management/templates/",
    "epics": "workspace/workflow/epics/",
    "epics_active": "workspace/workflow/epics/active/",
    "epics_completed": "workspace/workflow/epics/completed/",
    "plans": "workspace/workflow/plans/",
    "bugs": "workspace/bugs.md",
    "session_log": "workspace/session-log.md",
    "active_work": "workspace/active-work.md",
    "command_history": "workspace/command-history.md",
    "lessons_learned": "workspace/lessons-learned.md",
    "backlog": "workspace/backlog.md"
  },
  "conventions": {
    "session_file_format": "{id}-{topic}.md",
    "session_id_format": "S-{YYYYMMDD}-{4char-hash}",
    "epic_id_format": "E-{YYYYMMDD}-{4char-hash}",
    "branch_format": "session/{id}-{topic}"
  }
}
```

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

**Version:** 4.0.0
**Last Updated:** 2026-02-11
