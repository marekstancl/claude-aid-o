---
name: aid-first-aid
description: Launch FIRST AID autonomous orchestration mode — process EPIC queue without PM interaction
user_invocable: true
---

Launch **FIRST AID** (Fully Integrated Autonomous Development) mode — autonomous EPIC queue execution with Steroids 💉 preset, agent-driven decision-making, and escalation-only PM interaction.

> **DISCLAIMER — Experimental Autonomous Mode**
>
> FIRST AID is an **experimental** feature. It requires the **Steroids 💉** preset (set via /aid-setup). The preset grants full access while a deny-list blocks destructive commands. The AI will execute commands, modify files, install
> packages, push code, create GitHub releases, and call MCP tools — **without asking for
> confirmation**. A hard-deny list blocks dangerous operations (`rm -rf /`,
> `git push --force`, `sudo`, `chmod 777`, etc.), but no automated safeguard is
> exhaustive. **You are responsible for all actions performed in your environment.**
>
> Before starting: review your EPIC queue (`/aid-epic-queue`) and run `--dry-run` to
> preview execution. Use `/aid-stop` as the emergency stop to halt autonomous execution
> at any point.

The PM approves the EPIC queue before invocation. Once started, the Orchestrator processes every queued EPIC end-to-end: plan, execute, gate, merge, pick up next. PM is only contacted on escalation (16 defined triggers). Requires Steroids 💉 preset.

This is the **top-level autonomous command** — it wraps the entire lifecycle: mode flag management, queue iteration, and cross-EPIC summary reporting.

## Usage

```
/aid-first-aid                  # Start auto-mode with current queue
/aid-first-aid --resume         # Resume a paused/crashed session
/aid-first-aid --dry-run        # Validate queue and preset without executing
```

**Examples:**
```
/aid-first-aid                  # Process all queued EPICs autonomously
/aid-first-aid --resume         # Resume from saved progress after crash or /aid-stop
/aid-first-aid --dry-run        # Preview what would happen
```

## Prerequisites

- `.aid-o/` workspace must exist (run `/aid-init` if not)
- EPIC queue must have at least one entry with status `queued` (use `/aid-epic-queue add`)
- `.claude/settings.json` must exist and be valid JSON (or will be auto-created)
- Steroids 💉 preset must be active (run `/aid-setup` to configure)

## Core Instruction

**Read the following skills BEFORE starting the loop:**
1. `skills/auto-escalation.md` — 16 escalation triggers, pause/resume, PM notification
2. `skills/epic-orchestration.md` — state machine (used by `/aid-run-epic` under the hood)
3. `skills/epic-queue.md` — queue operations, auto-pickup, safety guards

**Read `skills/slack-mcp.md` for PM communication.** Escalation notifications and the
final summary report use the Slack MCP protocol with chat fallback.

---

## State Machine

FIRST AID has its own state machine that wraps the per-EPIC orchestration loop.
The per-EPIC execution delegates to `/aid-run-epic` logic (the 11-state machine
from `skills/epic-orchestration.md`).

```
FIRST_AID_INIT → QUEUE_PROCESSING → [per-EPIC: IDLE→...→DONE] → QUEUE_ADVANCE → FIRST_AID_COMPLETE
                                                                       ↑               |
                                                                       └── more EPICs ──┘
```

On each state transition, append to the session-level `stage_log.jsonl`.

---

### State: FIRST_AID_INIT

**Trigger:** `/aid-first-aid` command invocation.

**Actions:**

#### 1. Validate Workspace

```
1. Check .aid-o/ directory exists
   - IF not: ABORT with message:
     "Workspace not initialized. Run /aid-init first."

2. Check .aid-o/04-engine/ directory exists
   - IF not: create it (mkdir -p .aid-o/04-engine/)
```

#### 2. Handle --dry-run Flag

```
IF $ARGUMENTS contains "--dry-run":
  1. Run all validation checks (steps 3-6) without side effects
  2. Display results:
     "DRY RUN — FIRST AID Validation
      ====================================
      Queue:       {N} EPICs queued ({epic_ids})
      Preset:      Steroids 💉 (verified)
      Settings:    .claude/settings.json ({status: valid|missing|invalid})
      Mode state:  {none|active session exists}

      Ready to start: {YES|NO — {reason}}"
  3. STOP (do not proceed to execution)
```

#### 3. Handle --resume Flag

```
IF $ARGUMENTS contains "--resume":
  → Jump to RESUME_SESSION protocol (see Section: Resume After /aid-stop)
  → Do NOT run fresh initialization
```

#### 4. Check for Active Session

```
1. Read .aid-o/04-engine/auto-mode-state.yaml
   - IF file exists AND session.mode in ["auto", "paused"]:
     → Active session detected.
     → Present to PM:
       "An active FIRST AID session exists.
        Session: {session_id}
        Mode: {mode}
        Progress: {epics_completed}/{epics_total} EPICs
        Current: {current_epic_id} at state {current_state}

        Options:
        A) Resume this session (/aid-first-aid --resume)
        B) Abort this session and start fresh
        C) Cancel (do nothing)"
     → Wait for PM response.
     → OPTION A: execute resume protocol
     → OPTION B: abort existing session (set mode: "aborted"), then continue fresh init
     → OPTION C: STOP
```

#### 5. Validate EPIC Queue

```
1. Read .aid-o/04-engine/epic-queue.yaml
   - IF file does not exist:
     → ABORT with message:
       "No EPIC queue found. Add EPICs to the queue first:
        /aid-epic-queue add <epic-path>"
   - IF file exists but is not valid YAML:
     → ABORT with message:
       "Queue file is corrupted: {parse_error}
        Fix .aid-o/04-engine/epic-queue.yaml manually."

2. Filter queue entries where status == "queued"
   - IF none:
     → ABORT with message:
       "Queue is empty (no EPICs with status 'queued').
        Add EPICs: /aid-epic-queue add <epic-path>"

3. Validate each queued EPIC:
   For each entry with status == "queued":
     a. Check EPIC file exists at entry.path
        - IF not: mark entry as "failed" in queue, log warning
     b. Check EPIC file has required sections (Goal, Scope, Constraints)
        - IF not: mark entry as "failed" in queue, log warning
   After validation:
   - IF all queued EPICs failed validation:
     → ABORT with message:
       "All queued EPICs failed validation. Fix EPIC files and try again."
   - IF some failed:
     → Log warnings for failed ones
     → Continue with remaining valid EPICs

4. Build queue snapshot:
   valid_epics = [list of valid queued epic_ids, sorted by priority then added_at]
```

#### 6. Verify Steroids Preset

```
CHECK_PRESET:
  1. Read .claude/settings.local.json → permissions.allow[]
  2. Load Steroids preset definition from .aid-o/03-config/policies/permissions.yaml
     (or defaults/policies/permissions.yaml if project-level missing)
  3. Check: does current allow[] contain Bash(*:*)?
     (Steroids key indicator — Aspirin does NOT have unrestricted Bash)
  4. IF yes:
     → Log: {"state": "FIRST_AID_INIT", "action": "preset_check",
        "preset": "steroids", "result": "pass"}
     → Continue
  5. IF no:
     → ABORT with message:
       "First Aid vyzaduje preset Steroids 💉
        Aktualni opravneni nejsou dostatecna.
        Spust /aid-setup a zvol Steroids, nebo nastav rucne.
        Destruktivni prikazy zustavaji zakazany (deny-list)."
```

#### 7. Initialize Auto-Mode State

Create `.aid-o/04-engine/auto-mode-state.yaml`:

```yaml
session:
  session_id: "FA-{YYYYMMDDTHHMMSSZ}"
  mode: "auto"
  started_at: "{ISO 8601}"
  started_by: "pm"

  queue_snapshot:
    - "{epic_id_1}"
    - "{epic_id_2}"

  permissions:
    preset: "steroids"
    verified_at: "{ISO 8601}"

  escalation:
    budget: 3
    count: 0
    history: []

  progress:
    current_epic_id: null
    current_step_id: null
    current_state: "FIRST_AID_INIT"
    epics_completed: 0
    epics_total: {len(valid_epics)}

  context:
    epics_executed_this_context: []   # EPIC IDs the Controller actually dispatched in this execution context
    context_started_at: "{ISO 8601}"  # When this context began (set at QUEUE_PROCESSING entry)
    context_resume_count: 0           # How many times context was resumed (compaction/--resume)

  aggregate:
    epics_completed: 0
    epics_failed: 0
    epics_deferred_release: 0
    total_steps_executed: 0
    total_steps_skipped: 0
    total_gate_runs: 0
    total_gate_retries: 0
    total_escalations: 0
    total_curator_proposals: 0
    total_curator_implemented: 0
    total_curator_rejected: 0
    total_curator_deferred: 0
    total_lessons_learned: 0
    version_bumps: []
    total_duration_seconds: 0
    per_epic: []
```

#### 8. Display FIRST AID Startup Animation

Display the following 4-frame animation progressively. Output each frame with a
brief pause between them (the Controller outputs them sequentially). Replace all
`{placeholders}` in Frame 4 with actual session values. All frames MUST be output
exactly as shown (preserving alignment and box-drawing characters).

**Frame 1 -- Syringe appears (the instrument materializes):**

```
           ___________________
          |   A . I . D .     |
          |___________________|
               ||
               ||
               ||
              _||_
             |++++|
             |++++|
             |____|
```

**Frame 2 -- Syringe targets Claude Code (needle makes contact):**

```
           ___________________
          |   A . I . D .     |=====> [ CLAUDE CODE ]
          |___________________|
               ||
              _||_
             |++++|
             |____|
```

**Frame 3 -- Injection complete (steroids enter the system):**

```
      * * * * * * * * * * * * * * * * * * * *
      *                                     *
      *    ╔═══════════════════════════╗     *
      *    ║   A.I.D. STEROIDS        ║     *
      *    ║        INJECTED           ║     *
      *    ╚═══════════════════════════╝     *
      *                                     *
      * * * * * * * * * * * * * * * * * * * *
```

**Frame 4 -- Final static banner with session info (remains on screen):**

```
  ╔══════════════════════════════════════════════════════════════════════╗
  ║                                                                    ║
  ║         ╔═══╗    F I R S T   A I D                                 ║
  ║         ║ + ║    Fully Integrated Autonomous Development           ║
  ║         ╚═══╝    ═══════════════════════════════════               ║
  ║                  AUTONOMOUS MODE ACTIVE                            ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Session:      {session_id}                                        ║
  ║  Mode:         Autonomous                                          ║
  ║  EPICs queued: {count} ({total_estimated_steps} estimated steps)   ║
  ║  Preset:       Steroids 💉 (verified)                              ║
  ║  Escalation:   Budget {budget} | Used 0                            ║
  ║                                                                    ║
  ║  Queue:                                                            ║
  ║  ┌────┬────────────┬──────────────────────────┬─────────────────┐  ║
  ║  │ #  │ Priority   │ EPIC ID                  │ Title           │  ║
  ║  ├────┼────────────┼──────────────────────────┼─────────────────┤  ║
  ║  │ 1. │ {priority} │ {epic_id_1}              │ {title_1}       │  ║
  ║  │ 2. │ {priority} │ {epic_id_2}              │ {title_2}       │  ║
  ║  │ .. │            │                          │ ... and {N} more│  ║
  ║  └────┴────────────┴──────────────────────────┴─────────────────┘  ║
  ║                                                                    ║
  ║  ⚠ USE AT YOUR OWN RISK — Steroids 💉 preset active.                ║
  ║  Claude will execute commands without confirmation prompts.         ║
  ║  Stop command:  /aid-stop to disengage at any time                 ║
  ║                                                                    ║
  ╚══════════════════════════════════════════════════════════════════════╝
```

**Animation behavior:**
- Frames 1-3 are transient -- each is displayed briefly then cleared/overwritten
  by the next frame. The Controller outputs them sequentially with a short pause
  (~300ms per frame) to create a visual injection sequence.
- Frame 4 is the final static banner -- it remains on screen for the duration
  of the session and is the authoritative startup display.
- If the terminal does not support frame clearing, output all 4 frames
  sequentially (the visual effect degrades gracefully to a scrolling animation).

**Syringe visual language:**
- Frame 1: Full syringe (|++++| = loaded with steroids), needle pointing down
- Frame 2: Syringe rotated horizontally, needle aimed at [CLAUDE CODE] target,
  plunger partially depressed (barrel shrinks from 2 rows to 1)
- Frame 3: Burst effect (* border) confirms injection, steroids now in system
- Frame 4: The syringe icon reduces to the compact cross glyph (+ in a box)
  that persists as the FIRST AID brand mark throughout the session

**Banner variable reference (Frame 4):**

| Placeholder | Source |
|-------------|--------|
| `{session_id}` | `auto-mode-state.yaml` -> `session.session_id` |
| `{count}` | Length of `valid_epics` list |
| `{total_estimated_steps}` | Sum of estimated steps across queued EPICs (from EPIC files if available, otherwise `?`) |
| `{budget}` | `session.escalation.budget` |
| `{priority}` | Queue entry priority (`critical`, `high`, `medium`, `low`) |
| `{epic_id_N}` | EPIC ID from queue entry |
| `{title_N}` | EPIC title (first 17 chars, truncated with `...` if longer) |

**Alignment rules:**
- The entire Frame 4 banner is enclosed in a Unicode box-drawing frame (double-line outer, single-line inner table)
- The syringe cross icon (+ in a double-line box) appears beside the title for medical/aid branding
- Queue table columns are left-aligned; truncate long titles to fit within the frame
- If more than 5 EPICs are queued, show the first 5 and replace the last row with: `│ .. │            │                          │ ... and {N} more│`
- Right-pad all content lines with spaces to maintain consistent frame width (68 inner chars)
- Terminal width assumed: 80 columns (frame is 72 chars including 2-space left indent)

**Send Slack Status Update (Type G):**
`:rocket: FIRST AID started — {count} EPICs queued. Session {session_id}.`

#### 9. Create Session Evidence Directory

```
mkdir -p .aid-o/04-engine/evidence/FIRST-AID-{session_id}/
```

Save initial session state to `session-init.json` in this directory.

**Transition:** QUEUE_PROCESSING

**Evidence:** `session-init.json`, `stage_log.jsonl` entries.

---

### State: QUEUE_PROCESSING

**Trigger:** Transition from FIRST_AID_INIT, or from QUEUE_ADVANCE (next EPIC).

**Actions:**

#### 1. Read Mode Flag

```
READ_MODE:
  1. Read .aid-o/04-engine/auto-mode-state.yaml → session.mode
  2. IF mode != "auto":
     → Session was stopped or aborted externally
     → Transition to FIRST_AID_COMPLETE (with current progress)
  3. IF mode == "auto": continue
```

#### 2. Select Next EPIC

```
1. Read .aid-o/04-engine/epic-queue.yaml (from disk, not cached)
2. Call next() logic from skills/epic-queue.md:
   → Filter status in ["queued", "running"]
     (includes "running" as safety net — covers interrupted EPICs
      whose status was not reset during resume, e.g. crash mid-resume)
   → Prefer "running" entries first (they are interrupted EPICs that need to resume)
   → Then "queued" entries sorted by priority (critical > high > medium > low), then added_at (FIFO)
   → Return first entry
3. IF selected entry has status == "running":
   → Log: "Resuming interrupted EPIC {epic_id} (was still marked running)"
   → This is a safety net — normally RESUME_SESSION resets running → queued
4. IF no matching EPIC found:
   → Transition to FIRST_AID_COMPLETE
5. IF matching EPIC found:
   → Call start(epic_id) — set status: "running", started_at: now
     (if already "running", refresh started_at to mark the new attempt)
   → Update auto-mode-state.yaml:
     session.progress.current_epic_id = epic_id
     session.progress.current_state = "EXECUTING"
   → Append epic_id to auto-mode-state.yaml → session.context.epics_executed_this_context[]
```

#### 3. Multi-Agent Parallel Execution

Before executing the selected EPIC sequentially, check whether multiple queued
EPICs can be processed in parallel. Independent EPICs — those with non-overlapping
file scopes and no declared dependencies — can each run in an isolated git worktree
simultaneously, reducing total queue processing time.

**When to evaluate:** After selecting the next EPIC (step 2) and before executing
it (step 5). This check inspects the remaining queue for parallelism opportunities.

##### 3.1 Independence Detection Algorithm

```
DETECT_INDEPENDENT_EPICS(selected_epic, queue):
  1. Build candidate list:
     candidates = [selected_epic]
     remaining  = [entries in queue where status == "queued",
                   ordered by priority then added_at,
                   excluding selected_epic]

  2. For each candidate_epic in remaining (up to MAX_PARALLEL_AGENTS - 1 more):

     a. READ candidate EPIC file from its queue entry path
        - IF file missing or unreadable:
          → Skip candidate (uncertain scope — cannot prove independence)
          → Log: "Skipping {epic_id} for parallel detection: file unreadable"
          → Continue to next candidate

     b. EXTRACT scope sets:
        - allowed_paths = parse "### Allowed files/paths" section → set of path patterns
        - forbidden_zones = parse "### Forbidden zones" section → set of path patterns
        - dependencies = parse "## Dependencies" section → list of referenced EPIC IDs
        - IF "### Allowed files/paths" section is missing or empty:
          → Skip candidate (uncertain scope — fall back to sequential)
          → Log: "Skipping {epic_id} for parallel detection: no Allowed files/paths"
          → Continue to next candidate

     c. CHECK dependency declarations:
        For each existing member of candidates:
          - IF candidate_epic.dependencies references member.epic_id
            OR member.dependencies references candidate_epic.epic_id:
            → EPICs are dependent — skip candidate
            → Log: "Skipping {epic_id}: declared dependency on {member.epic_id}"
            → Continue to next candidate

     d. CHECK file scope overlap (pairwise against all current candidates):
        For each existing member of candidates:
          - overlap = candidate.allowed_paths INTERSECT member.allowed_paths
          - cross_forbidden_a = candidate.allowed_paths INTERSECT member.forbidden_zones
          - cross_forbidden_b = member.allowed_paths INTERSECT candidate.forbidden_zones
          - IF overlap is non-empty
            OR cross_forbidden_a is non-empty
            OR cross_forbidden_b is non-empty:
            → EPICs are NOT independent — skip candidate
            → Log: "Skipping {epic_id}: scope overlap with {member.epic_id}
                     (overlap: {overlap}, forbidden cross: {cross_a}, {cross_b})"
            → Continue to next candidate

     e. IF all checks pass:
        → Add candidate_epic to candidates list
        → Log: "EPIC {epic_id} is independent — eligible for parallel execution"

  3. Return candidates list
     - IF len(candidates) >= 2: parallelism opportunity detected
     - IF len(candidates) == 1: no parallelism — continue sequential
```

**Path intersection rules:**
- Paths are compared as directory prefixes. `src/api/` overlaps with `src/api/routes.py`.
- A specific file path (`src/api/auth.py`) overlaps with a directory path (`src/api/`)
  if the file is under that directory.
- Glob patterns (`src/**/*.ts`) are expanded conceptually: if two globs could match
  the same file, they overlap.
- When in doubt (complex globs, relative paths, symlinks), treat as overlapping
  (conservative — prefer sequential over incorrect parallel).

##### 3.2 Parallel Dispatch Protocol

```
PARALLEL_DISPATCH(candidates):
  Precondition: len(candidates) >= 2 AND len(candidates) <= MAX_PARALLEL_AGENTS

  1. Log to stage_log.jsonl:
     {"state": "QUEUE_PROCESSING", "epic_id": null,
      "action": "parallel_dispatch",
      "details": "Detected {N} independent EPICs, spawning parallel execution:
                  {[epic_ids]}",
      "result": "pending"}

  2. Send Slack Status Update (Type G):
     ":zap: Parallel execution: {N} independent EPICs detected.
      Spawning {N} isolated agents: {epic_id_1}, {epic_id_2}, ...
      Session {session_id}."

  3. Update auto-mode-state.yaml:
     session.progress.current_state = "PARALLEL_EXECUTING"
     session.parallel_execution = {
       active: true,
       started_at: "{ISO 8601}",
       agents: [
         { epic_id: "{epic_id_1}", worktree: null, status: "dispatching" },
         { epic_id: "{epic_id_2}", worktree: null, status: "dispatching" },
         ...
       ]
     }

  4. Mark all candidate EPICs as "running" in epic-queue.yaml:
     For each candidate:
       → Call start(epic_id) — set status: "running", started_at: now

  5. Spawn isolated agents:
     For each candidate epic in candidates:
       a. Dispatch a Task agent with worktree isolation:
          → Task tool call with description:
            "Execute EPIC {epic_id} in isolated worktree.
             Run the full /aid-run-epic orchestration loop.
             Auto-mode overrides apply (same as sequential execution).
             Report result as: completed | failed | aborted."
          → The Task agent:
            - Gets its own git worktree (isolated working copy)
            - Reads the EPIC file and runs the 11-state machine
            - Has read access to .aid-o/ for shared config
            - Writes evidence to its own evidence directory
            - Commits to its worktree branch independently

       b. Update auto-mode-state.yaml:
          session.parallel_execution.agents[i].status = "running"
          session.parallel_execution.agents[i].worktree = "{worktree_path}"

  6. Controller waits for ALL parallel agents to complete.
     → Each agent reports its result independently.
     → The Controller collects results as they arrive.
```

##### 3.3 Coordination Protocol

**Result collection and sequential merge:**

```
PARALLEL_COORDINATION(agents):
  1. WAIT for all agents to report completion (completed | failed | aborted).
     → Agents may complete at different times.
     → As each agent completes, log its result immediately:
        {"state": "QUEUE_PROCESSING", "epic_id": "{epic_id}",
         "action": "parallel_agent_completed",
         "details": "Agent for {epic_id} finished: {result}",
         "result": "{pass|fail}"}

  2. SEQUENTIAL MERGE — process completed agents one at a time:
     For each agent that reported "completed" (in original queue order):
       a. Switch to agent's worktree branch
       b. Merge worktree branch to main:
          → git checkout main
          → git merge {worktree_branch} --no-ff
              -m "merge: {epic_id} — parallel execution (session {session_id})"
       c. IF merge conflict:
          → Do NOT auto-resolve. Mark this EPIC as "failed" with reason
            "merge_conflict_after_parallel".
          → Log: "Merge conflict for {epic_id}. Marking failed."
          → Continue to next agent (other merges may still succeed).
       d. IF merge succeeds:
          → Log: "Successfully merged {epic_id} to main."

  3. COLLECT RESULTS — update aggregate metrics:
     For each agent:
       a. Read agent's final_report.md from its evidence directory
       b. Update auto-mode-state.yaml:
          - session.aggregate.per_epic[] += agent result data
          - Increment aggregate counters (steps, gates, escalations, etc.)
          - IF status == "completed": epics_completed += 1
          - IF status == "failed": epics_failed += 1

  4. UPDATE parallel execution state:
     session.parallel_execution.active = false
     session.parallel_execution.completed_at = "{ISO 8601}"
     For each agent:
       session.parallel_execution.agents[i].status = "{final_status}"
       session.parallel_execution.agents[i].merge_result = "merged|conflict|skipped"
```

**Escalation handling during parallel execution:**

```
PARALLEL_ESCALATION:
  IF any parallel agent triggers an escalation (any of the 16 triggers from
  skills/auto-escalation.md):
    1. PAUSE ALL parallel agents:
       → Set session.mode = "paused" in auto-mode-state.yaml
       → All agents read mode from disk at their next decision point
       → Each agent pauses at its next mode check
    2. Notify PM with combined context:
       "Escalation during parallel execution.
        Triggering EPIC: {epic_id}
        Trigger: {escalation_trigger}
        Parallel EPICs in flight: {list of epic_ids and their current states}
        Session {session_id}."
    3. PM responds with standard 4 options:
       - Fix (A): resume ALL agents after fix applied
       - Skip (B): mark triggering EPIC as failed, resume others
       - Abort (C): abort ALL parallel agents, transition to QUEUE_ADVANCE
       - Continue Manual (D): abort parallel execution,
         PM drives remaining EPICs
    4. ON resume:
       → Set session.mode = "auto"
       → Agents resume at their next mode check

  Escalation budget is SHARED across parallel agents:
    → session.escalation.count increments regardless of which agent triggered
    → If budget is exceeded, E12 fires for all agents (same as sequential)
```

**Failure handling:**

```
PARALLEL_FAILURE:
  IF a parallel agent fails (EPIC reaches failed state):
    1. Only that EPIC is marked failed — other agents continue.
    2. The failed agent's worktree is cleaned up (step 3.4).
    3. The failed EPIC is NOT merged to main.
    4. After ALL agents complete, if ANY failed:
       → Queue auto-pauses (same as sequential failure in QUEUE_ADVANCE step 3)
       → PM is notified with the combined results:
         "Parallel execution complete with failures.
          Completed: {completed_epic_ids}
          Failed: {failed_epic_ids}
          Queue auto-paused. Session {session_id}."
       → PM decides: resume / abort / continue-manual
```

##### 3.4 Safety Guards

```
PARALLEL_SAFETY:
  1. MAX_PARALLEL_AGENTS = 3
     → Never spawn more than 3 parallel agents.
     → If 4+ independent EPICs are detected, process the first 3 in parallel,
       then process remaining in the next queue iteration.

  2. UNCERTAIN_SCOPE_FALLBACK:
     → If an EPIC has no "### Allowed files/paths" section: exclude from parallel.
     → If an EPIC's scope uses only wildcards with no directory prefix
       (e.g., "**/*.md"): exclude from parallel (too broad to prove independence).
     → If the candidate list reduces to 1 EPIC: fall back to sequential.

  3. WORKTREE_CLEANUP (mandatory):
     After each parallel agent completes (success or failure):
       a. Remove the agent's git worktree:
          → git worktree remove {worktree_path} --force
       b. Remove the agent's worktree branch (if not merged):
          → git branch -d {worktree_branch}  (only if merged)
          → git branch -D {worktree_branch}  (if failed / not merged)
       c. Verify cleanup:
          → git worktree list — confirm worktree is removed
       d. IF cleanup fails:
          → Log WARNING: "Worktree cleanup failed for {epic_id}: {error}"
          → Continue (non-blocking — manual cleanup may be needed)

  4. RESOURCE_GUARD:
     → Before spawning, verify disk space is sufficient for N worktrees
       (each worktree is a full copy of the repo's working tree).
     → Heuristic: check that available disk space > N * (repo size on disk).
     → IF insufficient: reduce parallel count or fall back to sequential.
     → Log: "Disk space check: {available}MB available, {needed}MB needed
             for {N} worktrees."
```

##### 3.5 Integration with QUEUE_PROCESSING Flow

```
After selecting next EPIC (step 2):
  1. Call DETECT_INDEPENDENT_EPICS(selected_epic, queue)
  2. IF len(candidates) >= 2:
     → Log: "Detected {N} independent EPICs, spawning parallel execution"
     → Call PARALLEL_DISPATCH(candidates)
     → Call PARALLEL_COORDINATION(dispatched_agents)
     → Perform WORKTREE_CLEANUP for all agents
     → IF any EPIC failed: execute PARALLEL_FAILURE handling
     → Transition to QUEUE_ADVANCE (skip steps 4-5 for these EPICs —
       they were already executed in parallel)
  3. IF len(candidates) == 1:
     → No parallelism opportunity
     → Log: "No independent EPICs found — continuing sequential execution"
     → Continue with step 4 (Check Escalation Budget Guardrail) as normal
```

**Evidence:** Parallel execution state in `auto-mode-state.yaml`,
per-agent evidence in `.aid-o/04-engine/evidence/{epic_id}/{run_id}/`,
`stage_log.jsonl` entries for dispatch/completion/merge events.

#### 4. Check Escalation Budget Guardrail

Per `skills/auto-escalation.md` Section 8:

```
1. Read session.escalation.count from auto-mode-state.yaml
2. IF count >= session.escalation.budget:
   → Trigger E12 (guardrail breached)
   → Execute escalation protocol per skills/auto-escalation.md Section 4
   → PM decides:
     a. "Continue auto with raised limit" → update budget, resume
     b. "Continue manual" → transition to manual mode, exit auto
     c. "Abort queue" → transition to FIRST_AID_COMPLETE (aborted)
3. IF count < budget: proceed
```

#### 5. Execute EPIC

Delegate to the `/aid-run-epic` orchestration loop. The Controller runs the full
11-state machine from `skills/epic-orchestration.md` with the following auto-mode
overrides:

```
EXECUTE_EPIC(epic_id):
  1. Load EPIC file from queue entry path
  2. Run /aid-run-epic logic with auto-mode context:
     - The Controller reads session.mode at each decision point (PLAN_REVIEW,
       PHASE_CHECK, PM_APPROVAL, DONE) per Section 5.3 of architect design
     - Auto-mode decision behaviors are defined in step_1_architect output,
       Section 1 (Decision Point Mapping)
     - Escalation triggers follow skills/auto-escalation.md
     - Steroids 💉 preset provides all needed permissions; deny-list enforced at all times
  3. On EPIC completion (DONE state reached):
     → The DONE state handles: release, merge, Curator, Auditor, memory indexing
     → auto-mode-specific DONE behaviors apply (auto-defer intermediate release,
       auto-approve merge, etc.)
  4. EPIC result: "completed" or "failed" or "aborted"
```

**Key auto-mode overrides within the per-EPIC loop:**

| Decision Point | Manual Behavior | Auto-Mode Behavior |
|----------------|----------------|-------------------|
| PLAN_REVIEW | PM approves GO/REVISE/ABORT | Auto-approve if validation passes; escalate on failure (E11) |
| PHASE_CHECK | Auto-decide or code-reviewer | Same + 1 extra "fresh approach" attempt; escalate after 3 total cycles (E1) |
| GATES | Auto-retry up to max_attempts | Identical to manual |
| PM_APPROVAL | PM approves APPROVE/REJECT/REVISE | Auto-approve; guardrail check on last EPIC (E12 if budget exceeded) |
| DONE release | PM chooses release now/defer | Auto-defer intermediate; mandatory bump on last EPIC |

**PM_APPROVAL Guardrail (auto-mode):**

The PM_APPROVAL auto-approve is conditional on the previous EPIC's audit quality.
The check reads the **previous** EPIC's audit report, not the current one (which
has not been generated yet at PM_APPROVAL time).

```
For the FIRST EPIC in the queue:
  → Auto-approve unconditionally (no previous EPIC exists to check).

For each subsequent EPIC:
  1. Identify the previous EPIC's ID from epic-queue.yaml ordering.
  2. Locate its audit report:
     .aid-o/04-engine/evidence/{prev_epic_id}/*/audit-report.md
     (use the most recent run_id if multiple exist)
  3. Read the audit score from the report.

  IF audit-report.md found AND audit score < 60:
    → Trigger E11 escalation:
      "Previous EPIC {prev_epic_id} had low audit score ({score}/100).
       Review quality before continuing with next EPIC."
    → PM receives standard 4 options (Fix / Skip / Abort / Continue Manual).

  IF audit-report.md NOT found (skipped, failed, or never generated):
    → Log WARNING in session log:
      "No audit report found for {prev_epic_id}. Auto-approving with caution."
    → Auto-approve and continue.

  IF audit-report.md found AND audit score >= 60:
    → Auto-approve, continue execution.
```

**On escalation during EPIC execution:**

Per `skills/auto-escalation.md`:
1. Auto-mode pauses (mode set to "paused")
2. Progress saved (plan_progress.json, git stash if needed)
3. PM notified with 4 options: Fix (A) / Skip (B) / Abort (C) / Continue Manual (D)
4. On PM response:
   - Fix/Skip: resume auto-mode, continue from interrupted state
   - Abort: mark EPIC failed, transition to QUEUE_ADVANCE
   - Continue Manual: exit auto-mode, PM drives completion

**Evidence:** Per-EPIC evidence in `.aid-o/04-engine/evidence/{epic_id}/{run_id}/`

**Transition:** QUEUE_ADVANCE (when EPIC reaches DONE or fails)

---

### State: QUEUE_ADVANCE

**Trigger:** Current EPIC completed or failed.

**Actions:**

#### 1. Record EPIC Result

```
1. Read EPIC result from completed DONE state
2. Update epic-queue.yaml:
   → Call complete(epic_id, result_status) from skills/epic-queue.md
   → result_status = "completed" | "failed"

3. Update auto-mode-state.yaml aggregate:
   a. per_epic[] += {
        epic_id, status, steps, gate_retries,
        escalations, duration_seconds, release_action
      }
   b. Increment aggregate counters from EPIC's final_report.md
   c. IF status == "completed": epics_completed += 1
   d. IF status == "failed": epics_failed += 1
   e. IF EPIC was archived in DONE state: epics_archived += 1
```

#### 2. Plan Archival Check

After each completed EPIC (before picking up next EPIC or transitioning to
FIRST_AID_COMPLETE), check if the parent plan should be archived.

The QUEUE is the single source of truth for plan completion -- not filesystem
scanning, not frontmatter counters.

```
1. Read the completed EPIC's `plan_ref` from EPIC frontmatter
2. IF no plan_ref: skip (standalone EPIC, no plan to archive)
3. IF plan_ref exists:
   a. Read epic-queue.yaml (from disk)
   b. Find ALL queue entries where plan_ref matches target plan
   c. Count entries with status IN ["completed", "failed", "removed"] → done_count
   d. Count ALL entries with matching plan_ref → total_count
   e. IF done_count == total_count (all EPICs for this plan are done):
      - Check if plan already archived: test -f .aid-o/01-plans/archive/{plan_file}
      - IF already archived: skip (idempotent), log info
      - IF not archived:
        * mkdir -p .aid-o/01-plans/archive/
        * mv .aid-o/01-plans/{plan_file} .aid-o/01-plans/archive/{plan_file}
        * Log: {"state": "QUEUE_ADVANCE", "action": "plan_archival_check",
                "details": "Archived plan {plan_id} — all {total_count} EPICs done",
                "result": "archived"}
        * Update auto-mode-state.yaml: session.aggregate.plans_archived += 1
      - IF move fails: log WARNING, continue (non-blocking)
   f. ELSE:
      - Log: {"state": "QUEUE_ADVANCE", "action": "plan_archival_check",
              "details": "Plan {plan_id}: {done_count}/{total_count} EPICs done",
              "result": "deferred"}
4. IF no plan_ref (step 2 skip):
   - Log: {"state": "QUEUE_ADVANCE", "action": "plan_archival_check",
           "result": "no_plan_ref"}
```

NOTE: Plan archival is exclusively handled here in QUEUE_ADVANCE.
DONE state only increments the plan's epics_completed counter (informative).
The queue is the single source of truth for plan completion -- not filesystem scanning.

#### 3. Handle Failed EPIC

Per `skills/epic-queue.md` Auto-Pickup Protocol step 4:

```
IF result_status == "failed":
  → Queue auto-pauses (safety guard):
    epic-queue.yaml → paused: true
  → Send Slack escalation:
    "EPIC {epic_id} failed. Queue auto-paused.
     {N} EPICs remaining. Session {session_id}.
     Investigate and /aid-epic-queue resume to continue."
  → Update auto-mode-state.yaml:
    session.mode = "paused"
    session.progress.current_state = "QUEUE_PAUSED_FAILURE"
  → Wait for PM:
    - "resume" → set paused: false, mode: auto, continue to next
    - "abort" → transition to FIRST_AID_COMPLETE
    - "continue-manual" → exit auto
```

#### 4. Check Queue

```
1. Read mode flag from disk (may have changed via /aid-stop)
   IF mode != "auto": → FIRST_AID_COMPLETE

2. Read epic-queue.yaml from disk
   IF paused == true: → wait (should not reach here, but safety check)

3. Filter status in ["queued", "running"]  (consistent with QUEUE_PROCESSING next() safety net)
   IF count > 0:
     → Send Slack Status Update:
       ":arrows_counterclockwise: EPIC {completed_epic_id} done.
        Starting next: {next_epic_id}. ({remaining} remaining)"
     → Transition to QUEUE_PROCESSING (next iteration)
   IF count == 0:
     → Transition to FIRST_AID_COMPLETE
```

**Evidence:** Updated `auto-mode-state.yaml`, `epic-queue.yaml`.

---

### State: FIRST_AID_COMPLETE

**Trigger:** Queue empty (all EPICs processed), PM abort, /aid-stop, or mode change.

**Actions:**

#### 1. Determine Completion Status

```
1. Read auto-mode-state.yaml
2. Determine final status:
   - IF all queued EPICs completed: status = "completed"
   - IF PM aborted: status = "aborted"
   - IF /aid-stop invoked: status = "stopped"
   - IF unrecoverable error: status = "error"
```

#### 2. Display Completion Banner and Generate Summary Report

First, display the completion banner. Then generate the full summary report.

**Completion Banner -- Depleted Syringe:**

The syringe is empty -- the steroids have been fully delivered. Display this
single-frame banner immediately when entering FIRST_AID_COMPLETE, before
generating the summary report. Replace `{placeholders}` with session values.

```
  ╔══════════════════════════════════════════════════════════════════════╗
  ║                                                                    ║
  ║         ╔═══╗    F I R S T   A I D   --   Complete                 ║
  ║         ║   ║    ═══════════════════════════════                   ║
  ║         ╚═══╝    Steroids depleted. Patient survived.              ║
  ║                                                                    ║
  ║  {completed}/{total} EPICs completed    Duration: {total_duration} ║
  ║                                                                    ║
  ║  CURATOR FINDINGS:                                                 ║
  ║    [OK] Implemented:  {curator_implemented}  (effort:S)            ║
  ║    [!!] Deferred:     {curator_deferred_review}  (effort:M/L)      ║
  ║    [..] Deferred:     {curator_deferred_low}  (low priority)       ║
  ║    [--] Rejected:     {curator_rejected}                           ║
  ║                                                                    ║
  ╚══════════════════════════════════════════════════════════════════════╝
```

**Depleted syringe visual language:**
- The syringe symbol shows empty contents: `║   ║` (three spaces) instead of
  `║ + ║` (the loaded cross from the startup banner). This signals that the
  A.I.D. injection is spent -- all steroids have been consumed by the session.
- The tagline "Steroids depleted. Patient survived." reinforces the medical
  metaphor: Claude Code received its full treatment and the session is over.
- The CURATOR FINDINGS summary uses the status markers from the Curator agent
  report format ([OK], [!!], [..], [--]) to give the PM an instant read on
  which improvement proposals were handled and which need follow-up.

**Completion banner variable reference:**

| Placeholder | Source |
|-------------|--------|
| `{completed}` | `session.aggregate.epics_completed` |
| `{total}` | `session.progress.epics_total` |
| `{total_duration}` | Computed: `completed_at - started_at`, formatted as `Xh Ym Zs` |
| `{curator_implemented}` | `session.aggregate.total_curator_implemented` |
| `{curator_deferred_review}` | `session.aggregate.total_curator_deferred_review` |
| `{curator_deferred_low}` | `session.aggregate.total_curator_deferred_low` |
| `{curator_rejected}` | `session.aggregate.total_curator_rejected` |

---

**Full Summary Report:**

After the completion banner, generate the detailed summary report. Read aggregate
data from `auto-mode-state.yaml` and compile the report. Replace all
`{placeholders}` with actual session values. The report MUST be output exactly as
shown (preserving alignment and box-drawing characters).

**Status indicator:** Use the appropriate status icon based on session outcome:
- `completed` -> `[DONE]`
- `aborted` -> `[ABRT]`
- `stopped` -> `[STOP]`
- `error` -> `[ERR!]`

```
  ╔══════════════════════════════════════════════════════════════════════╗
  ║                                                                    ║
  ║          ┌───┐     FIRST AID  --  Session Report                   ║
  ║          │ + │     ════════════════════════════════                 ║
  ║          └───┘                                                     ║
  ║                                                                    ║
  ║  Session:   {session_id}                                           ║
  ║  Status:    {status_icon} {completed|aborted|stopped|error}        ║
  ║  Duration:  {total_duration} ({started_at} -> {completed_at})      ║
  ║  Mode:      Autonomous                                             ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  QUEUE RESULTS                                                     ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  EPICs completed:  {completed} / {total}  (session total)           ║
  ║  EPICs executed:   {executed_this_context}  (this context)         ║
  ║  EPICs failed:     {failed}                                        ║
  ║  EPICs removed:    {removed_count}                                 ║
  ║  EPICs remaining:  {remaining}                                     ║
  ║                                                                    ║
  ║  ┌─────┬──────────────────────┬───────┬───────┬──────┬──────────┐  ║
  ║  │ #   │ EPIC                 │ Steps │ Gates │ Esc  │ Release  │  ║
  ║  ├─────┼──────────────────────┼───────┼───────┼──────┼──────────┤  ║
  ║  │ 1   │ E-xxx (Title)        │ 3/3   │ 4/4   │ 0    │ deferred │  ║
  ║  │ 2   │ E-yyy (Title)        │ 5/5   │ 4/4   │ 1    │ deferred │  ║
  ║  │ 3   │ E-zzz (Title)        │ 2/2   │ 3/3   │ 0    │ v0.9.0   │  ║
  ║  │ !   │ E-aaa (Title)        │  --   │  --   │ --   │ removed  │  ║
  ║  ├─────┼──────────────────────┼───────┼───────┼──────┼──────────┤  ║
  ║  │ SUM │                      │ 10/10 │ 11/11 │ 1    │          │  ║
  ║  └─────┴──────────────────────┴───────┴───────┴──────┴──────────┘  ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  QUALITY METRICS                                                   ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Steps executed:     {executed} ({skipped} skipped)                ║
  ║  Gate runs:          {gate_runs} total ({gate_retries} retries)    ║
  ║  Escalations:        {escalation_count} / {escalation_budget}      ║
  ║  Curator proposals:  {curator_total}                               ║
  ║    Implemented:      {implemented}                                 ║
  ║    Rejected:         {rejected}                                    ║
  ║    Deferred:         {deferred}                                    ║
  ║  Lessons learned:    {lessons_count} new entries                    ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  CURATOR FINDINGS                                                  ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Total proposals:    {curator_total}                               ║
  ║    [OK] Implemented: {curator_implemented} (effort:S, inline fix)  ║
  ║    [!!] Deferred:    {curator_deferred_review} (effort:M/L)        ║
  ║    [..] Deferred:    {curator_deferred_low} (low priority)         ║
  ║    [--] Rejected:    {curator_rejected}                            ║
  ║                                                                    ║
  ║  Per-EPIC breakdown:                                               ║
  ║  {curator_per_epic_table}                                          ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  VERSION & RELEASE                                                 ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Version bump:     {version_info}                                  ║
  ║  Files updated:    {files_count}                                   ║
  ║  Git tag:          {tag_status}                                    ║
  ║  GitHub release:   {release_status}                                ║
  ║                                                                    ║
  ║  Version bumps this session:                                       ║
  ║  {version_bump_list_or_none}                                       ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  PERMISSIONS                                                       ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Preset: Steroids 💉 (verified at session start)                   ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  ARCHIVAL                                                          ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  EPICs archived:    {epics_archived_count} to 02-epics/archive/    ║
  ║  Plans archived:    {plans_archived_count} to 01-plans/archive/    ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  EVIDENCE ARTIFACTS                                                ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Session log:     .../FIRST-AID-{session_id}/stage_log.jsonl       ║
  ║  Session report:  .../FIRST-AID-{session_id}/summary-report.md     ║
  ║  Session state:   .aid-o/04-engine/auto-mode-state.yaml            ║
  ║                                                                    ║
  ║  Per-EPIC evidence:                                                ║
  ║    {epic_id_1}:  .../evidence/{epic_id_1}/{run_id_1}/             ║
  ║    {epic_id_2}:  .../evidence/{epic_id_2}/{run_id_2}/             ║
  ║    ...                                                             ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  WHAT'S NEXT?                                                      ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  1. Review changes  ->  git log --oneline, /aid-review             ║
  ║  2. Push to remote  ->  git push (if not auto-pushed)              ║
  ║  3. New queue       ->  /aid-epic-queue add, then /aid-first-aid   ║
  ║  4. Analytics       ->  /aid-analytics                             ║
  ║  5. Audit           ->  /aid-audit                                 ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  FIRST AID session {session_id} -- {status}                        ║
  ╚══════════════════════════════════════════════════════════════════════╝
```

**Evidence path shorthand:** In the report, `.../` is shorthand for `.aid-o/04-engine/evidence/`.
The full paths MUST be used in the saved `summary-report.md` file (Section 4 below). The
shorthand is only used in the terminal display to fit within the 70-char frame width.

**Summary report variable reference:**

| Placeholder | Source |
|-------------|--------|
| `{session_id}` | `auto-mode-state.yaml` -> `session.session_id` |
| `{status_icon}` | Mapped from session status (see status indicator above) |
| `{total_duration}` | Computed: `completed_at - started_at`, formatted as `Xh Ym Zs` |
| `{started_at}` | `session.started_at` |
| `{completed_at}` | Now (ISO 8601) |
| `{completed}` | `session.aggregate.epics_completed` |
| `{total}` | `session.progress.epics_total` |
| `{failed}` | `session.aggregate.epics_failed` |
| `{remaining}` | `total - completed - failed - removed_count` |
| `{executed_this_context}` | `session.context.epics_executed_this_context` length — count of EPICs actually dispatched in the current execution context |
| `{removed_count}` | Count of entries in `epic-queue.yaml` with `status: "removed"` |
| `{executed}` | `session.aggregate.total_steps_executed` |
| `{skipped}` | `session.aggregate.total_steps_skipped` |
| `{gate_runs}` | `session.aggregate.total_gate_runs` |
| `{gate_retries}` | `session.aggregate.total_gate_retries` |
| `{escalation_count}` | `session.escalation.count` |
| `{escalation_budget}` | `session.escalation.budget` |
| `{curator_total}` | `session.aggregate.total_curator_proposals` |
| `{implemented}` | `session.aggregate.total_curator_implemented` |
| `{rejected}` | `session.aggregate.total_curator_rejected` |
| `{deferred}` | `session.aggregate.total_curator_deferred` |
| `{curator_implemented}` | `session.aggregate.total_curator_implemented` (same as `{implemented}`, used in CURATOR FINDINGS section) |
| `{curator_deferred_review}` | `session.aggregate.total_curator_deferred_review` — count of effort:M/L proposals deferred for PM review |
| `{curator_deferred_low}` | `session.aggregate.total_curator_deferred_low` — count of low-priority proposals deferred |
| `{curator_rejected}` | `session.aggregate.total_curator_rejected` (same as `{rejected}`, used in CURATOR FINDINGS section) |
| `{curator_per_epic_table}` | Formatted table: one row per EPIC showing implemented/deferred/rejected counts. Format: `{epic_id}: {impl} implemented, {def} deferred, {rej} rejected`. Fallback: `"(no curator proposals this session)"` |
| `{lessons_count}` | `session.aggregate.total_lessons_learned` |
| `{version_info}` | `"No version bump (all deferred)"` or `"v{old} -> v{new}"` |
| `{files_count}` | Count of files in version bump commits |
| `{tag_status}` | `"created (v{version})"` or `"skipped"` |
| `{release_status}` | `"created"` or `"skipped"` |
| `{version_bump_list_or_none}` | Bulleted list from `session.aggregate.version_bumps[]` or `"  (none -- all releases deferred)"` |
| `{epics_archived_count}` | `session.aggregate.epics_archived` — count of EPICs moved to `02-epics/archive/` during this session. Incremented in DONE state archive logic. |
| `{plans_archived_count}` | `session.aggregate.plans_archived` — count of plans moved to `01-plans/archive/` during this session. Incremented in QUEUE_ADVANCE plan archival check or DONE state archive logic. |

**Table formatting rules:**
- EPIC column: show EPIC ID and title. Truncate title at 20 chars with `...` if longer
- Steps column: `{completed}/{total}` from per-EPIC data
- Gates column: `{passed}/{total}` from per-EPIC data
- Esc column: integer count of escalations for that EPIC
- Release column: `deferred` or `v{X.Y.Z}` (the version bumped to)
- SUM row: aggregates across all EPICs; Release cell left blank in SUM row
- If an EPIC failed, prefix its row with a `!` indicator: `| !3  | E-zzz (Title) ...`
- Removed EPICs show `!` in the `#` column, `--` in Steps/Gates/Esc columns, and `removed` in the Release column
- Note: the Duration column is omitted from the terminal table to fit within the
  72-column frame. Per-EPIC duration is available in the per-EPIC evidence and
  `auto-mode-state.yaml` → `session.aggregate.per_epic[]`.

#### 3. Save Summary Report

```
1. Write report to:
   .aid-o/04-engine/evidence/FIRST-AID-{session_id}/summary-report.md

2. Store session summary to Qdrant (if available):
   qdrant-store({
     type: "metric",
     metric_kind: "first_aid_session",
     project_name: "{project}",
     session_id: "{session_id}",
     epics_completed: N,
     epics_failed: M,
     escalations: K,
     duration_seconds: T
   })
```

#### 4. Update Auto-Mode State

```
1. Update .aid-o/04-engine/auto-mode-state.yaml:
   session.mode = "completed"  (or "aborted" or "stopped")
   session.completed_at = {now ISO 8601}
   DO NOT delete the file — useful for /aid-analytics and /aid-audit

2. Log: {"state": "FIRST_AID_COMPLETE", "action": "session_ended",
   "session_id": "{id}", "status": "{status}",
   "epics_completed": N, "total_duration": "{duration}"}
```

#### 5. Send Final Slack Notification

```
IF status == "completed":
  ":checkered_flag: FIRST AID complete — {completed}/{total} EPICs done.
   Session {session_id}. Duration: {duration}."
IF status == "aborted" or "stopped":
  ":stop_sign: FIRST AID {status} — {completed}/{total} EPICs done.
   Session {session_id}. {remaining} EPICs remain in queue."
```

#### 6. Present Report to PM

Display the summary report in the conversation (or via Slack Type F).

**Evidence:** `summary-report.md`, final `auto-mode-state.yaml`.

---

## Resume After /aid-stop

When `/aid-stop` is invoked during auto-mode, it sets `session.mode: "manual"`.
The queue and EPIC progress are preserved.

When `/aid-first-aid --resume` is invoked later:

```
RESUME_SESSION:
  1. Read .aid-o/04-engine/auto-mode-state.yaml
     - IF file does not exist:
       → ABORT: "No session to resume. Start fresh with /aid-first-aid."
     - IF session.mode == "completed":
       → ABORT: "Previous session completed. Start fresh with /aid-first-aid."
     - IF session.mode not in ["manual", "aborted", "paused", "stopped"]:
       → ABORT: "Cannot resume from mode '{mode}'."

  2. Present session state to PM:
     "Resume FIRST AID session?
      Session:     {session_id}
      Last status: {mode}
      Progress:    {epics_completed}/{epics_total} EPICs
      Last EPIC:   {current_epic_id} at state {current_state}
      Queue:       {remaining} EPICs remaining

      This will:
      - Verify Steroids 💉 preset is still active
      - Resume from the next queued EPIC (or retry the paused one)
      - Continue autonomous execution

      Proceed? (yes/no)"

  3. IF PM confirms:
     a. Verify Steroids 💉 preset (same as fresh init step 6)
     b. **Reset interrupted EPIC status** — scan `epic-queue.yaml` for entries with `status: "running"`:
        - If found: reset status to `"queued"`, log: `"Reset interrupted EPIC {epic_id} from running → queued for resume pickup"`
        - This ensures QUEUE_PROCESSING next() finds the interrupted EPIC
     c. Set session.mode = "auto"
     d. Increment session.context.context_resume_count += 1
     e. Reset session.context.epics_executed_this_context = []
     f. Set session.context.context_started_at = "{ISO 8601}" (new context start)
     g. Set session.progress.current_state = "QUEUE_PROCESSING"
     h. Log: {"state": "FIRST_AID_RESUME", "action": "session_resumed",
        "session_id": "{id}", "epics_remaining": N,
        "context_resume_count": session.context.context_resume_count}
     i. Display resume banner (re-injection theme):

        The syringe is partially refilled -- re-loading for continued treatment.
        The `~` symbol inside the syringe represents a fluid level that is being
        topped up (partial fill), distinguishing it from the full `+` of a fresh
        start and the empty `   ` of a completed session.

        ```
          ╔══════════════════════════════════════════════════════════════════════╗
          ║                                                                    ║
          ║         ╔═══╗    F I R S T   A I D   --   Resuming                 ║
          ║         ║ ~ ║    Re-injecting from saved state...                  ║
          ║         ╚═══╝    ══════════════════════════════                    ║
          ║                                                                    ║
          ╠══════════════════════════════════════════════════════════════════════╣
          ║                                                                    ║
          ║  Session:    {session_id}                                          ║
          ║  Resuming:   {current_epic_id} (step {current_step})               ║
          ║  Progress:   {completed}/{total} EPICs done                        ║
          ║  Remaining:  {N} EPICs ({estimated_steps} estimated steps)         ║
          ║  Escalation: Budget {budget} | Used {used}                         ║
          ║                                                                    ║
          ║  Preset: Steroids 💉 (verified). Syringe reloaded.                 ║
          ║  Stop command:  /aid-stop to disengage                             ║
          ║                                                                    ║
          ╚══════════════════════════════════════════════════════════════════════╝
        ```

        **Resume banner syringe states across the session lifecycle:**
        - Startup:    `║ + ║`  -- full syringe, loaded and ready
        - Resume:     `║ ~ ║`  -- partially refilled, re-loading
        - Completion: `║   ║`  -- empty/depleted, treatment finished
     j. Transition to QUEUE_PROCESSING

  4. IF PM declines:
     → STOP (no changes)

RESUME_INTERRUPTED_STEP:
  1. Check for interrupted_step_context.json in evidence/{epic_id}/{run_id}/
  2. IF found:
     a. Read interrupted context
     b. Log: "Detected interrupted step: {step_id} (reason: {reason})"
     c. Recover git state:
        - Run `git stash list` to find the stash
        - Run `git stash pop` to restore uncommitted work
        - If stash pop fails (conflict): log WARNING, continue without stashed changes
     d. Update plan_progress.json: step status → "running" (was "interrupted")
     e. Re-dispatch the interrupted step's agent with:
        - Full original prompt
        - Additional context: "This is a RESUME after credit exhaustion.
          Previous partial output (if any): {partial_output}.
          Continue from where you left off."
     f. Delete interrupted_step_context.json after successful re-dispatch
     g. Continue normal orchestration loop
  3. IF not found:
     Continue normal resume (no interrupted step)
```

---

## /aid-stop Integration

The `/aid-stop` command is the PM's mechanism to interrupt auto-mode at any time.
When invoked during a FIRST AID session:

```
AID_STOP (during FIRST AID):
  1. Set auto-mode-state.yaml → session.mode = "manual"
     (Controller reads mode from disk at each decision point — this takes
      effect at the next mode check, per Section 5.3 of architect design)

  2. Wait for current atomic operation to complete:
     - IF mid-step dispatch: wait for agent to finish current step
     - IF mid-gate: wait for current gate command to finish
     - This prevents partial state corruption

  3. Save progress:
     → auto-mode-state.yaml already has latest progress
     → plan_progress.json has per-EPIC step progress
     → epic-queue.yaml has queue state

  4. Inform PM:
     "FIRST AID stopped.
      Session:  {session_id}
      Progress: {epics_completed}/{epics_total} EPICs
      Current:  {current_epic_id} at state {current_state}

      Options:
      - Resume later: /aid-first-aid --resume
      - Continue this EPIC manually: /aid-run-epic {current_epic_id}
      - Check status: /aid-epic-status"
```

---

## Error Handling

### Unrecoverable Errors

If the Controller encounters an error it cannot handle:

```
ON_UNRECOVERABLE_ERROR(error):
  1. Log error to stage_log:
     {"state": "{current_state}", "action": "unrecoverable_error",
      "error": "{error message}"}

  2. Save progress snapshot (same as escalation pause):
     → Write current state to auto-mode-state.yaml
     → Stash uncommitted work if dirty working tree

  3. Update state:
     → session.mode = "aborted"
     → session.progress.current_state = "ERROR"

  4. Notify PM:
     "FIRST AID encountered an unrecoverable error.
      Error: {error}
      EPIC: {current_epic_id}
      State: {current_state}

      Session progress is saved.

      To investigate: /aid-epic-status {current_epic_id}
      To resume: /aid-first-aid --resume"

  5. STOP
```

### Per-State Error Table

| State | Error Condition | Action |
|-------|----------------|--------|
| FIRST_AID_INIT | Workspace missing | ABORT (no cleanup needed) |
| FIRST_AID_INIT | Queue empty | ABORT (no cleanup needed) |
| FIRST_AID_INIT | Steroids preset not active | ABORT with setup instructions |
| QUEUE_PROCESSING | Mode changed externally | Transition to FIRST_AID_COMPLETE |
| QUEUE_PROCESSING | EPIC file missing | Mark EPIC failed, advance queue |
| QUEUE_PROCESSING | Escalation budget exceeded | E12 trigger, PM decides |
| QUEUE_ADVANCE | Failed EPIC | Auto-pause queue, notify PM |
| FIRST_AID_COMPLETE | Summary generation failure | Log error, continue (non-blocking) |

---

## Evidence Logging

Every state transition MUST append a line to the session-level stage log at
`.aid-o/04-engine/evidence/FIRST-AID-{session_id}/stage_log.jsonl`:

```json
{"timestamp": "{ISO 8601}", "state": "{FIRST_AID state}", "epic_id": "{current or null}", "action": "{what happened}", "details": "{context}", "result": "{pass|fail|pending}"}
```

**Examples:**
```json
{"timestamp": "2026-02-24T16:00:00Z", "state": "FIRST_AID_INIT", "epic_id": null, "action": "session_start", "details": "3 EPICs queued, Steroids preset verified", "result": "pass"}
{"timestamp": "2026-02-24T16:00:05Z", "state": "QUEUE_PROCESSING", "epic_id": "E-20260224-a1b2", "action": "epic_start", "details": "Starting EPIC 1/3: E-20260224-a1b2 (high)", "result": "pending"}
{"timestamp": "2026-02-24T17:30:00Z", "state": "QUEUE_ADVANCE", "epic_id": "E-20260224-a1b2", "action": "epic_completed", "details": "EPIC 1/3 completed. 5 steps, 0 escalations.", "result": "pass"}
{"timestamp": "2026-02-24T17:30:05Z", "state": "QUEUE_PROCESSING", "epic_id": "E-20260224-c3d4", "action": "epic_start", "details": "Starting EPIC 2/3: E-20260224-c3d4 (medium)", "result": "pending"}
{"timestamp": "2026-02-24T19:00:00Z", "state": "FIRST_AID_COMPLETE", "epic_id": null, "action": "session_ended", "details": "3/3 EPICs completed. Duration: 3h. 1 escalation.", "result": "pass"}
```

Per-EPIC execution also logs to the EPIC-specific stage log at
`.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl` (handled by
`/aid-run-epic` logic).

---

## Reference Files

- **ESCALATION:** `skills/auto-escalation.md` — 16 triggers, pause/resume, PM notification format, escalation budget
- **ORCHESTRATION:** `skills/epic-orchestration.md` — 11-state machine (used inside each EPIC run)
- **QUEUE:** `skills/epic-queue.md` — queue format, operations, auto-pickup, safety guards
- **PM COMMS:** `skills/slack-mcp.md` — Slack MCP protocol, message types, fallback, timeouts
- **MODE FLAG:** `.aid-o/04-engine/auto-mode-state.yaml` — session state, mode, aggregate metrics

---

## Important

- **Read the three skills listed in Core Instruction BEFORE starting.** They are the
  authoritative sources. This command file is the execution protocol; the skills define
  the rules.
- **Steroids 💉 preset is required.** Destructive commands are always denied via deny-list.
- **The mode flag is read from disk at every decision point, never cached.** This is how
  `/aid-stop` takes immediate effect.
- **Escalation is the ONLY mandatory PM touchpoint.** Everything else is automated.
  The 16 triggers in `skills/auto-escalation.md` are the exhaustive list.
- **Failed EPICs auto-pause the queue.** The PM must investigate and resume. The queue
  does not silently skip failures.
- **Evidence is mandatory.** Every transition logs to `stage_log.jsonl`. Every EPIC
  produces a `final_report.md`. The session produces a `summary-report.md`.
- **The hard-deny list is non-negotiable.** It cannot be overridden by configuration,
  by PM grants, or by any other mechanism.
- If `$ARGUMENTS` is empty: start fresh auto-mode with current queue (equivalent to
  no flags).
