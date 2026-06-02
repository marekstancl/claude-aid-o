---
name: run-management
description: Run lifecycle management — ID system, active work tracking, phase transitions, handoff protocol
user_invocable: false
---

# Run Management - Instructions

**Skill:** run-management
**Dependencies:** agent-protocol

---

## TL;DR - MUST Rules

1. **READ active.md** at EVERY run start (authoritative over platform memory)
2. **READ command-history.md + lessons-learned.md** at EVERY run start
3. **CREATE run file** for non-trivial work (multi-change, multi-file) — use templates, not invented structure
4. **RUN = DETAILED WORK PLAN** — evolves with the code, captures what actually happened
5. **UPDATE run file** after EVERY commit
6. **UPDATE active.md** at run end (current focus, recent work, next steps)
7. **ARCHIVE completed runs** to `.aid-o/work/tasks/archive/`
8. **FOLLOW lifecycle protocols** at each transition (brainstorming-end, run-start, phase-end, run-end)
9. **PHASE-END = HARD STOP** — stop, summarize what was done, wait for PM GO
10. **UPDATE project docs** at run-end (mandatory impact analysis per `playbooks/docs-{project.docs.platform}.md`)
11. **UPDATE workspace files** at run-end (command-history, lessons-learned, backlog)
12. **MONITOR context window** after each phase — warn PM if getting large

---

## Document Hierarchy

In v2: **Plan → Task → Quick** — three levels, no overlap.

| Document | Purpose | Location |
|----------|---------|----------|
| **Plan** | Forming ideas, rough approach | `.aid-o/plans/` |
| **Task** | Complex work (3+ runs), breakdown | `.aid-o/tasks/` |
| **Quick** | Single-conversation fast work | Q-NNN.md (FAST MODE) |
| **Run** | Detailed work plan for one run | `.aid-o/work/tasks/` |

NEVER save run files into `.aid-o/` root. NEVER mix Plan/Task/Run locations.

---

## ID System

IDs are sequential from `.aid-o/config/counter.yaml`:

```yaml
# .aid-o/config/counter.yaml
plan: 5       # next allocated: P006
epic: 12      # next allocated: E-013
run: 8        # next allocated: R-009
```

### ID Formats

```
Plan:           P{NNN}                     (P001)
EPIC from plan: E-{NNN}-{phase}_{total}    (E-005-1_4)
Ad-hoc EPIC:    E-{NNN}                    (E-001)
Run:            R-{EPIC_ID}-{run_number}   (R-005-1_4-1)
```

### Allocation Procedure

1. READ counter.yaml → get current value for the ID type
2. INCREMENT the counter by 1
3. WRITE incremented value back to counter.yaml **immediately**
4. USE the incremented value as the new ID

Pre-allocation (e.g., for interim docs in `/aid-plan`) follows the same procedure —
the counter is incremented at Step 1, not deferred to plan completion. If the plan
is aborted, the ID is "consumed" (counter is not rolled back). This prevents
collisions between concurrent sessions.

- Run file: `R-005-1_4-1-gui-foundation.md` — branch: `run/R-005-1_4-1-gui-foundation`
- Frontmatter: `id: R-005-1_4-1`, `epic_id: E-005-1_4`

---

## Run Types

| Type | When | Run File? | Action |
|------|------|:---------:|--------|
| Simple Task | < 3 changes, single file | No | TodoList + active.md |
| Standard Run | Multiple changes, clear scope | Yes | Copy template, track progress |
| Epic Run | 3+ conversations | Yes + Task file | Task breakdown + sub-runs |
| Verification | E2E testing / QA | Yes | Test scenarios + results |
| Handoff | Mid-implementation pause | Yes + Handoff block | Context preservation |

---

## Run Lifecycle

### Phase 1: Initialization

1. Read `.aid-o/work/active.md` — authoritative current state
2. Read `.aid-o/work/command-history.md` and `.aid-o/work/lessons-learned.md`
3. Read `.aid-o/config/project.yaml` — if missing or >7 days old, run `/aid-setup`
4. If NEW run:
   a. Assess complexity — 3+ runs needed? → suggest Epic workflow to PM first
   b. Generate run ID (see ID System section above)
   c. Create run file in `.aid-o/work/tasks/` from `.aid-o/config/templates/run-{type}.md`
      - **EPIC runs:** run file pre-created by `scripts/aid-json-to-run.sh`; Controller reads it
   d. Fill with DETAILED plan — objectives, affected files, approach, risks
   e. Ask PM for approval → create branch `run/{id}-{topic}`
5. If CONTINUATION:
   a. Load run file + plan/task, review last phase + handoff notes
   b. Announce next steps, ask PM for approval

### Phase 2: Work Loop

```
Loop:
  1. Announce phase start
  2. Implement + self-test
  3. PHASE-END CHECKPOINT (HARD STOP)
  4. PM GO → quality gates → commit → next phase
  5. PM STOP → create handoff (Phase 4)
```

#### PHASE-END CHECKPOINT (HARD STOP — MANDATORY)

**Before continuing to the next phase, AI MUST:**

1. Update run file (phase = done, commit hash, changes)
2. Update active.md (progress, decisions)
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

> **EPIC MODE note:** In EPIC MODE, phase-end checkpoints map to the FSM `EXECUTE → GATES`
> transition. The Controller enforces this boundary automatically — the checkpoint above is
> the human-facing equivalent. FAST MODE (Q-NNN.md tasks) has no phase checkpoints; the
> task file is written on completion and the FSM advances directly to GATES.

### Run Closure (DONE state)

1. [ ] Write `fsm-state.yaml`: `state: DONE`
2. [ ] Append to `timeline.jsonl`: `{"eventType": "fsm_transition", "state": "DONE"}`
3. [ ] Run Curator agent (post-gate hook)
4. [ ] Write lessons to `.aid-o/work/backlog.md`
5. [ ] Archive task file to `.aid-o/tasks/archive/`
6. [ ] Update `active.md`: remove from current focus, add to Recent Work

### Phase 3: Run-End Protocol

1. Final quality gates (tests pass, no TODO/FIXME, no debug statements)
2. **UPDATE project documentation** — MANDATORY:
   - Impact analysis on ALL changes; update affected docs in `{project.docs.path}`
   - Load `playbooks/docs-{project.docs.platform}.md`; run build if `{project.docs.build_command}` set
   - If no docs affected: document why in run file
3. Update run file: Status = Completed, all commits + files listed
4. Update `.aid-o/work/command-history.md`, `.aid-o/work/lessons-learned.md`, `.aid-o/work/backlog.md`
5. **Present PM with completion options** (REQUIRED format):

```
Standard run:
  If you agree: move to completed/, commit, merge to main, write continuation text
  Or: issues to resolve? proceed differently?

Last epic run:
  If you agree: move run + task to archive/, update task status, commit, merge
  Or: issues to resolve? proceed differently?
```

6. If PM approves: update active.md, archive run, update task (if last epic run), add entry to run-log.md, commit + merge

### Phase 4: Handoff (Optional)

**When:** Work paused mid-implementation, context too large, switching platforms.

**Handoff block must include:**

| Section | Content |
|---------|---------|
| Completed | Tasks done with commit hashes and files |
| Now Working On | Current task, progress %, files in progress, next step |
| Next Steps | Ordered list of remaining actions |
| Important Context | Decisions made, known issues/gotchas, dependencies |
| Key Locations | Config, tests, docs, logs paths |
| How to Test | Commands to verify current state |
| Branch | Branch name + last commit hash |

**Quality check:** Handoff is self-contained if next AI can continue without asking questions.

**Where to put:** Run file (Handoff Notes section) + active.md + task file (if epic).

---

## Lifecycle Protocols

### End of Brainstorming

1. Write summary of what was explored and decided
2. Assess scope: one run → Standard run; 3+ runs → Epic; design only → Plan
3. Present recommendation: "I recommend [Plan/Run/Epic] because [reason]. What do you prefer?"
4. PM chooses:
   - Plan → create in `.aid-o/plans/`
   - Epic → create Task file in `.aid-o/tasks/` from template
   - Run → proceed to Phase 1

### Context Window

After each phase: assess window size. If large → warn PM. PM decides whether to handoff. Never auto-handoff.

### Rules Reminder

Every 2-3 phases: re-read TL;DR, verify lifecycle steps not skipped, self-correct if needed.

---

## Epic Runs

**Epic = 3+ conversations.** Task file in `.aid-o/tasks/`, run files in `.aid-o/work/tasks/`.

```
.aid-o/tasks/E-005-1_4-gui-foundation.md   ← task file
.aid-o/work/tasks/R-005-1_4-1-*.md         ← run files (epic_id in frontmatter)
```

Workflow: create task file → per-run: create run file with `epic_id` reference → on run done: update task (run log, progress), append to `timeline.jsonl` → all runs done: move task to `.aid-o/tasks/archive/`.

---

## Bug Tracking

**Location:** `{project.paths.bugs}` | **When:** can't fix now, tech debt, non-critical issue.

```
| Date | ID | Bug | Severity | Status | Notes |
| YYYY-MM-DD | BUG-XXX | {Title} | High/Med/Low | Open | {Context} |
```

Discover → bugs.md → active.md Blockers (if blocking) → continue work → dedicated bug-fix run later.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Coding without run file | Create for multi-change work |
| Shallow run file | Fill with objectives, files, approach, risks |
| Forgetting run file updates | Update after EVERY commit |
| Skipping active.md | Read at start, update at end |
| Insufficient handoff | Self-contained — no questions needed |
| Skipping Phase-End HARD STOP | MUST stop and wait for PM GO |
| Skipping project docs at run-end | ALWAYS run impact analysis |
| Auto-handoff without PM consent | Only WARN, PM decides |
| Confusing Plan/Task/Run | Plan = idea, Task = context, Run = work plan |

---

## Integration

| Skill | How |
|-------|-----|
| agent-protocol | Run init protocol, role detection |
| pipeline.md | FSM states and transitions for EPIC orchestration |
| aid-json-to-run.sh | Generates run files from plan.json |

For `.aid-o/` workspace layout, see `commands/aid-init.md`.

---

**Last Updated:** 2026-03-03
