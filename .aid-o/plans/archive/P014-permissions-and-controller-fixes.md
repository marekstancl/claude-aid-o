---
id: P014
type: plan
status: done
created: 2026-02-27
author: PM + AI
---

# Plan: Aspirin & Steroids — Permission Simplification + Controller Fixes

## Context

### Permission Sandwich — Unnecessary Complexity

FIRST AID autonomous mode has a permission sandwich mechanism (backup → elevate → restore → crash recovery) that adds ~285 lines to `aid-first-aid.md`, requires a dedicated 750-line skill file (`permission-sandwich.md`), and introduces crash recovery complexity — all to temporarily elevate permissions for the duration of a session. This is unnecessary: if the user has the right permissions set permanently, the entire sandwich is wasted work.

The blast radius of the permission sandwich spans **11 files** across the plugin:
- `skills/permission-sandwich.md` — 750 lines, **DELETE entirely**
- `commands/aid-first-aid.md` — 20+ references (backup, elevate, restore, crash recovery, banners)
- `commands/aid-stop.md` — 10+ references (entire restore procedure in Step 3)
- `skills/first-aid-controller.md` — 2 major refs (elevation at start, restore at DONE/STOP)
- `skills/auto-done-state.md` — 4 refs (dependency list, RESTORE_PERMISSIONS call, crash recovery)
- `skills/epic-orchestration.md` — 1 ref (config references section)
- `commands/aid-help.md` — 2 refs (elevated permissions warnings)
- `defaults/policies/permissions-auto.yaml` — 164 lines, **DELETE entirely**
- `README.md` — 3 refs (sandwich description, skill table, policy table)
- `CHANGELOG.md` — 20+ refs across multiple versions (historical — leave as-is)
- `plugins/aid-orchestrator/CHANGELOG.md` — mirror of above

### Controller Bugs — FA-20260226T200000Z Post-Mortem

The FA-20260226T200000Z session exposed 4 critical bugs:
- **IMP-043:** Plan archival never executes at QUEUE_ADVANCE
- **IMP-044:** Version bump uses queue-level check instead of plan-level — solo plans never bump
- **IMP-045:** DONE state release sub-phase is silently skipped entirely
- **IMP-046:** Controller miscounts EPICs after context compaction; queue removal marks "completed" instead of "removed"

## Goal

Replace the permission sandwich with a two-preset system (Aspirin 💊 / Steroids 💉), eliminate all permission lifecycle management from FIRST AID, and fix the 4 critical Controller bugs.

## Scope

**In scope:**
- Remove Safe preset, rename Recommended → Aspirin, rename Advanced → Steroids
- Delete `permission-sandwich.md` skill and `permissions-auto.yaml`
- Strip all permission sandwich logic from FIRST AID (backup, elevate, restore, crash recovery)
- FIRST AID preset check: verify Steroids active, abort if not
- Update `/aid-setup` for new preset names
- Fix plan archival at QUEUE_ADVANCE (IMP-043)
- Fix version bump detection: plan-level, not queue-level (IMP-044)
- Fix release sub-phase execution in DONE state (IMP-045)
- Fix queue removal status + context boundary tracking (IMP-046)

**Out of scope:**
- GUI changes (P009)
- Token optimization (P013)
- Deny-list changes (already hardened in E-012, stays in settings.local.json)
- Writing-plans skill (separate plan)

## Approach

### Option A: Two EPICs — permissions + controller fixes (Chosen)

**EPIC 1: Aspirin & Steroids** — Permission simplification. Remove sandwich, new presets, simplify FIRST AID. Pure deletion/simplification.

**EPIC 2: Controller Bug Fixes** — Fix IMP-043, IMP-044, IMP-045, IMP-046. These are interconnected bugs in the DONE/QUEUE_ADVANCE code paths.

**Pros:**
- Clean separation: refactoring vs bug fixes
- Each EPIC gets its own version bump (appropriate — distinct logical changes)

**Cons:**
- Two EPICs, two bumps

### Decision

**Chosen:** Option A
**Rationale:** Permission simplification is structural refactoring, controller fixes are behavioral patches. Mixing them makes rollback harder and review unclear. EPIC 1 must come first (simplifies files that EPIC 2 patches).

## Detailed Steps

---

### EPIC 1: Aspirin & Steroids (Permission Simplification)

**Estimated steps:** 7 | **Complexity:** medium | **Risk:** low (pure deletion)

#### Step 1 — Rename presets in permissions.yaml (S)

**Files:** `defaults/policies/permissions.yaml`, `.aid-o/03-config/policies/permissions.yaml`, `skills/dispatch-protocol.md`, `commands/aid-setup.md`

**Current state:** Three presets: `safe`, `recommended`, `advanced` (lines 1-126 of permissions.yaml). `active_preset: "recommended"` with comment `# safe | recommended | advanced`.

**Action:**
- Delete `safe` preset entirely
- Rename `recommended` → `aspirin` with description: "Mirni bolest, ale na vsechno se zepta. Bezpecny default."
- Rename `advanced` → `steroids` with description: "Plny vykon, zadne otazky. Required for First Aid. Destruktivni prikazy jsou zakazany."
- Change `active_preset: "recommended"` → `active_preset: "aspirin"` with comment `# aspirin | steroids`
- Keep deny-list entries unchanged in both presets
- Sync project-level copy (`.aid-o/03-config/policies/permissions.yaml`)

**Cross-file preset name references (besides permission-sandwich.md and permissions-auto.yaml which are deleted in Steps 3-4):**

| File | Lines | Reference | Action |
|------|-------|-----------|--------|
| `defaults/policies/permissions.yaml` | 10 | `active_preset: "recommended"` + comment `# safe \| recommended \| advanced` | Rename preset keys + update comment |
| `skills/dispatch-protocol.md` | 23, 31, 37-38 | `active_preset`, fallback to `recommended` preset | Update to `aspirin`/`steroids` |
| `commands/aid-setup.md` | 314, 1062, 1074, 1089 | Option 7 description, `active_preset` write, comment, advanced description | Covered by Step 2 |
| `CHANGELOG.md` | multiple | Historical mentions (Safe / Recommended / Advanced) | Leave as-is (history) |

#### Step 2 — Update /aid-setup (S)

**Files:** `commands/aid-setup.md`

**Current state:**
- Option 7 (lines 309-314): 3 presets Safe/Recommended/Advanced
- Comparison matrix (lines ~1040-1054): 3-column table
- Dual write logic (lines 1058-1091): `active_preset` + `settings.local.json`
- Comment line 1074: `# safe | recommended | advanced`
- Line 1089: advanced-specific note

**Exact replacement text:**

**Option 7 — new description (lines 309-314):**
```
7. Permission Preset
   Controls what Claude Code can do without asking:
   - Aspirin 💊: edit files, run tests/linters, local git — VS Code asks for risky ops
   - Steroids 💉: full access, zero prompts — required for /aid-first-aid
   Both presets deny destructive commands (rm -rf /, git push --force, sudo, etc.)
   (Default: Aspirin 💊)
```

**Comparison matrix (lines ~1040-1054):**
```
  +-------------------+-------------+-------------+
  |                   | Aspirin 💊  | Steroids 💉 |
  +-------------------+-------------+-------------+
  | Read files        |      Y      |      Y      |
  | Edit/Write files  |      Y      |      Y      |
  | Git (local)       |      Y      |      Y      |
  | Git push          |      N      |      Y      |
  | Run tests/lint    |      Y      |      Y      |
  | Package install   |      N      |      Y      |
  | Bash (unrestricted)|     N      |      Y      |
  | All MCP servers   |      N      |      Y      |
  | Destructive cmds  |      N      |      N      |
  +-------------------+-------------+-------------+
  Note: Steroids 💉 is required for /aid-first-aid.
  Destructive commands are ALWAYS denied (both presets).

Select preset: (1/2) [1]
```

**Dual write comment (line 1074):**
```yaml
permission_preset: "aspirin"   # aspirin | steroids
```

**Steroids note (line 1089):**
```
- For "steroids": `Bash(*:*)` means VS Code never prompts for ANY bash command.
  Destructive commands are still blocked by deny[] in settings.local.json.
  Required for /aid-first-aid autonomous mode.
```

**Confirm message (lines 1077-1084):**
```
Permissions applied:
  - Preset: {Aspirin 💊 | Steroids 💉}
  - AID agents: .aid-o/03-config/policies/permissions.yaml
  - VS Code auto-allow: .claude/settings.local.json ({count} entries)
  - Deny list: destructive commands blocked ({deny_count} patterns)
  - VS Code will NOT prompt for commands in the allow list
```

#### Step 3 — Delete permission-sandwich.md (S)

**Action:** Delete `skills/permission-sandwich.md` (entire 750-line file) + fix 9 references across 6 files.

| # | File | Line | Current text | Replace with |
|---|------|------|-------------|--------------|
| 1 | `skills/first-aid-controller.md` | 50 | `"Controller elevates permissions, sets mode: auto, and begins autonomous execution. See commands/aid-first-aid.md and skills/permission-sandwich.md."` | `"Controller verifies Steroids 💉 preset, sets mode: auto, and begins autonomous execution. See commands/aid-first-aid.md."` |
| 2 | `skills/first-aid-controller.md` | 508 | `"Restore permissions (permission sandwich teardown — see skills/permission-sandwich.md)"` | `"Set mode: manual in auto-mode-state.yaml (auto-mode ends with the queue)"` — delete lines 508-509 + 513 reference to permission teardown |
| 3 | `skills/auto-done-state.md` | 4 | `Dependencies: epic-orchestration, epic-queue, auto-escalation, permission-sandwich` | `Dependencies: epic-orchestration, epic-queue, auto-escalation` |
| 4 | `skills/auto-done-state.md` | 381-384 | Entire block "2. RESTORE permissions: → Execute RESTORE_PERMISSIONS from skills/permission-sandwich.md..." | Delete entire block (step 2). Renumber step 3 → 2. |
| 5 | `skills/auto-done-state.md` | 896 | `"permissions-backup.json exists → crash recovery per skills/permission-sandwich.md"` | Delete entire line (crash recovery not needed) |
| 6 | `skills/auto-done-state.md` | 944, 947 | MUST rules #7 ("ALWAYS restore permissions...") and #10 ("crash recovery restores permissions...") | Delete rule #7 entirely. Reformulate rule #10: `"NEVER auto-resume a crashed session — report to PM and require explicit /aid-first-aid --resume"` |
| 7 | `skills/epic-orchestration.md` | 114 | `"Permission lifecycle: skills/permission-sandwich.md — permission backup, elevation, restoration, crash recovery"` | Delete entire line |
| 8 | `commands/aid-help.md` | 217 | `"Skill: skills/permission-sandwich.md (Section 4: Restore Procedure)"` | `"Permissions: Steroids 💉 preset required (set via /aid-setup)"` |
| 9 | `README.md` | 107 | `"\| permission-sandwich \| FIRST AID permission management — backup, elevate, restore, learning \|"` | Delete entire line from table |

#### Step 4 — Delete permissions-auto.yaml (S)

**Action:** Delete both files + fix 5 remaining references.

**Delete:**
- `defaults/policies/permissions-auto.yaml` (164 lines)
- `.aid-o/03-config/policies/permissions-auto.yaml` (if exists in target project)

**Note:** `/aid-init` does NOT copy `permissions-auto.yaml` — confirmed clean. No upgrade logic needed.

| # | File | Line | Current text | Replace with |
|---|------|------|-------------|--------------|
| 1 | `commands/aid-first-aid.md` | 46 | `"- permissions-auto.yaml must exist (project, plugin defaults, or will be generated)"` | Delete entire line (prerequisite not needed) |
| 2 | `commands/aid-first-aid.md` | 1546 | `"- **PERMISSIONS:** defaults/policies/permissions-auto.yaml — default auto-mode permission template"` | Delete entire line from Reference Files |
| 3 | `commands/aid-help.md` | 207 | `"WARNING: Grants elevated permissions — review queue and permissions-auto.yaml first."` | `"WARNING: Requires Steroids 💉 preset. Set via /aid-setup. Destructive commands are always denied."` |
| 4 | `commands/aid-help.md` | 1181-1183 | `"WARNING: FIRST AID grants elevated auto-permissions. Review .aid-o/03-config/policies/permissions-auto.yaml before starting. Use /aid-stop at any time to halt and restore normal permissions."` | `"WARNING: Requires Steroids 💉 preset (set via /aid-setup). Destructive commands are always denied. Use /aid-stop at any time to halt."` |
| 5 | `README.md` | 195 | `"\| policies/permissions-auto.yaml \| FIRST AID permission template (allow/deny lists) \|"` | Delete entire line from table |

#### Step 5 — Strip permission sandwich from aid-first-aid.md (M)

**Files:** `commands/aid-first-aid.md` (~1574 lines → ~1200 estimated after cleanup)

**Current state:** FIRST_AID_INIT has steps 6-8 for permissions (temp cleanup, backup, elevate). FIRST_AID_COMPLETE has step 2 for restore. /aid-stop has restore. --resume has re-elevation. `auto-mode-state.yaml` template has full `permissions:` section.

**13 specific actions:**

**DELETE entire sections (line ranges):**

| # | Lines | Section | Reason |
|---|-------|---------|--------|
| 1 | 181-193 | `#### 6. Temp File Cleanup` | No temp files without sandwich |
| 2 | 195-217 | `#### 7. Execute Permission Sandwich — Backup` | No backup |
| 3 | 219-236 | `#### 8. Execute Permission Sandwich — Elevate` | No elevation |
| 4 | 987-1026 | `#### 2. Restore Permissions` (in FIRST_AID_COMPLETE) | No restore |
| 5 | 1428-1433 | `/aid-stop` step 3: Restore permissions | No restore |
| 6 | 1472-1477 | `ON_UNRECOVERABLE_ERROR` step 3: Restore permissions | No restore |

**REPLACE / ADD:**

**[7] Instead of steps 6-8 (lines 181-236) → new step 6: CHECK_PRESET:**
```
#### 6. Verify Steroids Preset

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

**[8] `auto-mode-state.yaml` template (lines 253-270) → reduce permissions section:**
```yaml
  permissions:
    preset: "steroids"
    verified_at: "{ISO 8601}"
```
Delete: `backup_path`, `elevated_at`, `source`, `applied_permissions`, `applied_permissions_count`, `original_permissions_snapshot`, `learned_permissions`, `grant_log[]`

**[9] Intro text updates:**
- Line 7: `"with elevated permissions"` → `"with Steroids 💉 preset"`
- Lines 11-12: `"It grants Claude Code **elevated permissions** for the duration..."` → `"It requires the **Steroids 💉** preset (set via /aid-setup). The preset grants full access while a deny-list blocks destructive commands."`
- Line 22: `"Permissions are elevated for the duration and restored on completion."` → `"Requires Steroids 💉 preset."`
- Line 24: `"permission sandwich, mode flag management"` → `"mode flag management"`
- Prerequisites: delete lines 45-46, add: `"- Steroids 💉 preset must be active (run /aid-setup to configure)"`
- Core Instruction line 51: delete `"1. skills/permission-sandwich.md — ..."`. Renumber 2→1, 3→2, 4→3.

**[10] Banner updates:**
- Startup Frame 4: `"Permissions:  Elevated ({source}, {allow_count} entries)"` → `"Preset:       Steroids 💉 (verified)"`
- --dry-run: `"Permissions: {source} ({allow_count} allow, {deny_count} deny)"` → `"Preset: Steroids 💉 (verified)"`

**[11] --resume flow (lines 1336-1344):**
- Line 1337: `"- Re-elevate permissions (permission sandwich)"` → `"- Verify Steroids 💉 preset is still active"`
- Line 1344: `"a. Execute Permission Sandwich — Backup + Elevate (same as fresh init)"` → `"a. Verify Steroids 💉 preset (same as fresh init step 6)"`
- Line 1374: `"Permissions re-elevated. Syringe reloaded."` → `"Preset: Steroids 💉 (verified). Syringe reloaded."`

**[12] Summary report PERMISSIONS section (lines 1162-1169) → replace entire block:**
```
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  PERMISSIONS                                                       ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Preset: Steroids 💉 (verified at session start)                   ║
  ║                                                                    ║
```

**[13] Error handling + messages:**
- /aid-stop PM message (line 1446): delete `"Permissions restored to pre-auto-mode state."`
- ON_UNRECOVERABLE_ERROR PM message (line 1489): delete `"Permissions have been restored."`
- Per-State Error Table: delete rows for `Backup failure`, `Elevation failure`, `Restore failure`. Add: `"FIRST_AID_INIT | Steroids preset not active | ABORT with setup instructions"`
- Reference Files: delete `PERMISSION SANDWICH` and `PERMISSIONS` (permissions-auto.yaml) lines

#### Step 6 — Update first-aid-controller.md and aid-stop.md (S)

**first-aid-controller.md — 3 changes (2 already in Step 3 table, 1 new):**

| Line | Action | Detail |
|------|--------|--------|
| 50 | Step 3 #1 | See Step 3 table row 1 |
| 508 | Step 3 #2 | See Step 3 table row 2 |
| 513 | NEW | `"(including cross-EPIC summary aggregation and permission teardown sequence)."` → `"(including cross-EPIC summary aggregation)."` |

**aid-stop.md — comprehensive permission removal (18 line-level changes):**

| Line | Current text | Action |
|------|-------------|--------|
| 7 | `"halts autonomous execution, restores original permissions, saves progress"` | → `"halts autonomous execution, saves progress for later resume, and returns control to the PM."` |
| 23 | `"- Permission backup: .aid-o/03-config/permissions-backup.json"` | Delete line from Prerequisites |
| 29-30 | `"Read skills/permission-sandwich.md Section 4..."` | Delete block (no skill to read) |
| 42 | `"ensure permissions are restored"` | → `"proceed with full stop"` |
| 80 | `"do NOT abort — permission restore is more important"` | → `"do NOT abort — progress save is critical"` |
| 84-106 | Entire `### Step 3: Restore Permissions` (23 lines) | **Delete entire section.** Renumber Step 4 → Step 3, Step 5 → Step 4. |
| 127-129 | `permissions: restored: true\|false, restore_error:` | Delete 3 lines from state update |
| 151 | `"permissions_restored": true\|false` | Delete line from stage_log |
| 170 | `"Permissions: restored (or: REVIEW NEEDED)"` | Delete line from PM status message |
| 183-186 | Error variant `"Permissions: REVIEW NEEDED..."` | Delete block (4 lines) |
| 209 | `"Attempt permission restore anyway (Step 3)..."` | Delete line from edge case handling |
| 214-221 | `### Permission backup missing` section (8 lines) | Delete entire section |
| 239 | `"PRIMARY: skills/permission-sandwich.md Section 4"` | Delete line from Reference Files |
| 249 | `"The permission restore is the most critical step..."` | Delete line from Important notes |

**Resulting aid-stop.md flow (3 steps instead of 5):**
```
Step 1: Set mode flag (auto-mode-state.yaml → mode: "manual")
Step 2: Wait for current atomic operation to complete
Step 3: Save progress + inform PM
  → auto-mode-state.yaml, plan_progress.json, epic-queue.yaml
  → PM message:
    "FIRST AID stopped.
     Session:  {session_id}
     Progress: {epics_completed}/{epics_total} EPICs
     Current:  {current_epic_id} at state {current_state}

     Options:
     - Resume later: /aid-first-aid --resume
     - Continue this EPIC manually: /aid-run-epic {current_epic_id}
     - Check status: /aid-epic-status"
```

#### Step 7 — Cross-reference cleanup + CHANGELOG (M)

**Uncovered references (not handled by Steps 3-6):**

| # | File | Line | Text | Action |
|---|------|------|------|--------|
| 1 | `README.md` | 16 | `"Permissions elevated via permission sandwich (backup → elevate → restore)."` | → `"Requires Steroids 💉 preset (set via /aid-setup). Destructive commands always denied."` |
| 2 | `auto-done-state.md` | 685 | `"(by skills/permission-sandwich.md) and updated throughout the session."` | → `"and updated throughout the session."` |
| 3 | `auto-done-state.md` | 703-707 | `"# Permissions tracking (managed by permission-sandwich.md)"` + `backup_path`, `learned_permissions` in template | → Replace entire block: `permissions:\n  preset: "steroids"\n  verified_at: "{ISO 8601}"` |
| 4 | `auto-done-state.md` | 922 | `"\| skills/permission-sandwich.md \| Session complete \| Restore permissions \|"` | Delete line from integration table |
| 5 | `aid-first-aid.md` | 801-803 | Permission learning at PHASE_CHECK (3 lines) | Delete entire block |
| 6 | `aid-first-aid.md` | 1244 | `learned_count` variable reference in banner table | Delete line |
| 7 | `aid-first-aid.md` | 1556 | `"Permission sandwich is a SAFETY mechanism..."` | → `"Steroids 💉 preset is required. Destructive commands are always denied via deny-list."` |
| 8 | `aid-first-aid.md` | 1569 | `grant_log` reference in Important notes | Delete line |

**CHANGELOG — new entry (do not rewrite history):**

Add under new version `## [X.Y.Z]`:
```
### Removed
- **Permission Sandwich** — removed `skills/permission-sandwich.md` (750 lines) and
  `defaults/policies/permissions-auto.yaml` (164 lines); FIRST AID no longer backs up,
  elevates, or restores permissions — requires Steroids 💉 preset instead

### Changed
- **Permission presets** — Safe removed, Recommended renamed to Aspirin 💊,
  Advanced renamed to Steroids 💉; two-preset system with deny-list protection
- **FIRST AID startup** — permission sandwich steps (backup, elevate) replaced by
  single Steroids preset verification check
- **FIRST AID completion** — permission restore removed; /aid-stop simplified to
  3 steps (mode flag, wait, save progress)
```

**Verification grep (agent MUST run and confirm zero matches outside CHANGELOG):**
```
permission.sandwich|permissions.backup|RESTORE_PERMISSIONS|BACKUP_PERMISSIONS|ELEVATE_PERMISSIONS|elevated_at|restored_at|grant_log|learned_permissions|original_permissions_snapshot
```

---

### EPIC 2: Controller Bug Fixes

**Estimated steps:** 5 | **Complexity:** high | **Risk:** medium (behavioral changes in core state machine)

#### Step 1 — Fix plan archival at QUEUE_ADVANCE (IMP-043) (M)

**Files:** `commands/aid-first-aid.md` (QUEUE_ADVANCE state, lines ~895-918), `skills/first-aid-controller.md` (DONE state archive logic, lines ~360-385)

**Current broken logic:** Plan archival is defined in QUEUE_ADVANCE (lines 895-918) as a check that scans `02-epics/archive/` and `02-epics/` for plan_ref matches. But it also exists in DONE state (`first-aid-controller.md` lines 360-385, step 4: "Update Plan counter → archive if all done"). The two mechanisms are unsynchronized and neither actually executes.

**Root cause:** The QUEUE_ADVANCE archival check uses filesystem scanning (searching `02-epics/archive/` for matching `plan_ref`) which is fragile. The DONE state plan counter update uses frontmatter counters which may be stale. Neither is connected to a mandatory execution path — the Controller treats both as optional documentation.

**Fix — single source of truth in QUEUE_ADVANCE:**

Rewrite the QUEUE_ADVANCE Plan Archival Check (lines 895-918) to use the **queue** as ground truth instead of filesystem scanning:

```
QUEUE_ADVANCE — Plan Archival (SINGLE SOURCE OF TRUTH):

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
        * Log: {"state": "QUEUE_ADVANCE", "action": "archive_plan",
                "details": "Archived plan {plan_id} — all {total_count} EPICs done"}
        * Update auto-mode-state.yaml: session.aggregate.plans_archived += 1
      - IF move fails: log WARNING, continue (non-blocking)
   f. ELSE:
      - Log: "Plan {plan_id}: {done_count}/{total_count} EPICs done, archival deferred"
```

**Rewrite DONE state step 4** (`first-aid-controller.md` lines 378-381) — remove archival, keep counter as informative:
```
4. **Update Plan counter (informative only):**
   - IF EPIC archived AND `plan_ref` exists:
     - Increment `epics_completed += 1` in plan frontmatter
     - Log: "Plan {plan_id}: {epics_completed}/{epics_total} EPICs done"
     - NOTE: Plan archival is handled exclusively by QUEUE_ADVANCE — do NOT archive here.
       The frontmatter counter is informative (for human readers), not a decision input.
```

**Rewrite NOTE block** (`aid-first-aid.md` lines 920-924) — old text says "complements DONE state archival". Replace with:
```
NOTE: Plan archival is exclusively handled here in QUEUE_ADVANCE.
DONE state only increments the plan's epics_completed counter (informative).
```

**Add stage_log assertion:** After QUEUE_ADVANCE plan archival check completes, log `"action": "plan_archival_check"` with result `"archived"`, `"deferred"`, or `"no_plan_ref"`. This makes skipping detectable in audit.

#### Step 2 — Fix version bump detection (IMP-044) (M)

**Files:** `skills/auto-done-state.md` (DETECT_EPIC_POSITION, lines ~120-138), `skills/first-aid-controller.md` (PM_APPROVAL, lines ~196-252)

**Current broken logic:** Two inconsistent detection mechanisms:
1. `auto-done-state.md` lines 120-138 `DETECT_EPIC_POSITION()` — uses **queue position** (`remaining_queued == 0` → "last")
2. `first-aid-controller.md` PM_APPROVAL lines 200-205 — uses **EPIC frontmatter** (`plan_epics_total`, `runs_completed`)

Both are wrong. Queue position tells you queue order, not plan completion. Frontmatter tells you plan structure but may be stale. A queue can contain EPICs from 3 different plans — queue position says nothing about per-plan completion.

**Fix — unified plan-level detection:**

Replace `DETECT_EPIC_POSITION()` in `auto-done-state.md` (lines 120-138) with:

```
DETECT_EPIC_POSITION(epic_id):
  """
  Determines whether this EPIC triggers a version bump based on its PLAN,
  not its queue position. Single source of truth for both release and PM_APPROVAL.
  """

  1. Read EPIC frontmatter → plan_ref, plan_epics_total
  2. IF plan_ref is null (standalone EPIC, no plan):
     → RETURN "standalone"  (always bumps)
  3. IF plan_epics_total == 1 (solo plan):
     → RETURN "standalone"  (always bumps)
  4. IF plan_epics_total > 1 (multi-EPIC plan):
     a. Read epic-queue.yaml
     b. Find ALL queue entries with matching plan_ref
     c. Count entries with status IN ["completed"] → completed_for_plan
     d. The current EPIC (status: "running") counts as +1 → effective = completed_for_plan + 1
     e. IF effective >= plan_epics_total:
        → RETURN "last"  (triggers bump)
     f. ELSE:
        → RETURN "intermediate"  (defer bump)
  5. FALLBACK: RETURN "standalone"  (bump by default — safer than skipping)
```

**Also rewrite manual detection above DETECT_EPIC_POSITION** (`auto-done-state.md` lines 113-118) — this block reads frontmatter `plan_ref`, `plan_epics_total`, `runs_completed` and determines position for manual mode. Replace with a call to the same `DETECT_EPIC_POSITION()` so both modes use the same plan-level logic.

**Update PM_APPROVAL in `first-aid-controller.md` (lines 196-252):** Replace the frontmatter-based detection (lines 200-205) with:
```
  1. Call DETECT_EPIC_POSITION(epic_id) from auto-done-state.md Section 2.4
     → Returns: "standalone", "last", or "intermediate"
```
Remove the inline `plan_epics_total` / `runs_completed` logic. Rest of PM_APPROVAL (lines 207-243) stays — it already branches on intermediate vs last.

**Note:** PM_APPROVAL uses position for **guardrails** too (intermediate = no guardrails, last = full guardrails). Plan-level detection is correct for both use cases — an intermediate EPIC of one plan shouldn't trigger guardrails just because it's last in the queue.

**Add to `defaults/policies/release-policy.yaml`:**
```yaml
first_aid:
  intermediate_action: defer  # defer | ask
  # defer: intermediate EPICs auto-defer version bumps to plan's last EPIC
  # ask: escalate to PM (auto-mode pauses)
```

#### Step 3 — Fix release sub-phase execution (IMP-045) (M)

**Files:** `skills/first-aid-controller.md` (DONE state, lines ~278-284), `skills/auto-done-state.md` (Section 2, lines ~81-227)

**Current broken logic:** DONE state action 1b (lines 278-284) says "See `skills/auto-done-state.md` Section 2" but there's no explicit entry point, no mode branching, and no mandatory execution gate. The Controller treats this as a documentation reference, not an executable step. Result: the release sub-phase is silently skipped for every EPIC.

**Fix — delete lines 278-284 entirely, replace with executable RELEASE_SUB_PHASE block:**

Rewrite DONE state action 1b in `first-aid-controller.md` (lines 278-284):

```
1b. RELEASE_SUB_PHASE (MANDATORY — between file status update and branch merge):

    Log: {"state": "DONE", "action": "release_sub_phase_start", "epic_id": "{id}"}

    1. Read mode: manual or first_aid (from auto-mode-state.yaml)
    2. Call DETECT_EPIC_POSITION(epic_id) → position
    3. Branch on position:

       IF position == "standalone" OR position == "last":
         → Execute full release protocol (auto-done-state.md Section 2.6-2.10):
           a. Detect version mismatch (Section 2.2)
           b. Determine bump type (patch/minor/major) from EPIC scope
           c. Update all version files (release-policy.yaml version_files[])
           d. Finalize CHANGELOG (move [Unreleased] → [vX.Y.Z])
           e. Commit version bump
           f. Create git tag
           g. IF mode == "first_aid": create GitHub release (auto)
              IF mode == "manual": ask PM
         → Log: {"action": "release_sub_phase_complete", "version": "vX.Y.Z"}

       IF position == "intermediate":
         → IF mode == "first_aid":
             Auto-defer per release-policy.yaml first_aid.intermediate_action
             Log: {"action": "release_sub_phase_deferred", "reason": "intermediate_epic"}
           IF mode == "manual":
             Ask PM: "Release now or defer to plan's last EPIC?"
             Log PM's decision

    4. IF any error in release sub-phase:
       → Log error, do NOT block merge (release is important but not merge-blocking)
       → Set release_status = "failed" in final_report
```

**Update `auto-done-state.md` Section 2:** Add "Entry Point" subsection at the top of Section 2 that clearly states:
- This section is called from DONE state action 1b in `first-aid-controller.md`
- It runs AFTER gate completion, BEFORE branch merge
- The caller provides `epic_id` and `mode` (manual/first_aid)
- The section MUST return with a stage_log entry (pass, deferred, or failed)

#### Step 4 — Fix queue removal + context tracking (IMP-046) (M)

**Files:** `skills/epic-queue.md` (remove operation, lines ~79-88; status values, lines ~45-54), `skills/auto-done-state.md` (auto-mode-state.yaml schema, lines ~689-769; session report, lines ~528-600), `commands/aid-first-aid.md` (auto-mode-state.yaml template)

**Background:** E-010-2_2 was accidentally added to the queue. PM requested removal. Instead of actual removal or a distinct status, the Controller marked it as "completed" — indistinguishable from genuinely executed EPICs. After context compaction, the Controller reported "3/3 EPICs completed" including E-010-2_2 which was never actually orchestrated.

**Fix part A — Queue removal sets "removed" status:**

Rewrite `remove(epic_id)` in `epic-queue.md` (lines 79-88):

```
### `remove(epic_id)`

Remove an EPIC from the queue (only if not running).

1. Find entry by epic_id
2. IF status == "running" → reject: "Cannot remove running EPIC. Use /epic-queue pause."
3. Update entry (DO NOT delete — preserve audit trail):
   status: "removed"
   removed_at: "{ISO 8601}"
4. Save epic-queue.yaml
5. Log: "EPIC {epic_id} removed from queue (was: {previous_status})"
```

Also update status comment on line 31: `# queued | running | completed | failed | paused` → `# queued | running | completed | failed | paused | removed`

Add "removed" to Status Values table (lines 45-54):

```
| Status | Meaning |
|--------|---------|
| queued | Waiting, ready to be picked up |
| running | Currently being executed |
| completed | Finished successfully |
| failed | Finished with failure |
| paused | Individually paused by PM |
| removed | Removed from queue by PM (/epic-queue remove) |
```

**Note on `add()` duplicate check** (line 66): checks `queued|running` only — a `removed` EPIC does NOT block re-adding the same EPIC. This is correct behavior (PM may re-add after mistaken removal). No change needed.

**Fix part B — Context boundary tracking:**

Add `context:` block to `auto-mode-state.yaml` template in **both** files:
- `aid-first-aid.md` (~line 253, inside the YAML template)
- `auto-done-state.md` (~line 703, inside the schema definition)

```yaml
  context:
    epics_executed_this_context: []   # EPIC IDs the Controller actually dispatched in this execution context
    context_started_at: "{ISO 8601}"  # When this context began (set at QUEUE_PROCESSING entry)
    context_resume_count: 0           # How many times context was resumed (compaction/--resume)
```

**Controller behavior:**
- At QUEUE_PROCESSING, when starting an EPIC: append `epic_id` to `epics_executed_this_context[]`
- At --resume: increment `context_resume_count`, reset `epics_executed_this_context: []`, set new `context_started_at`
- In completion report: show both:
  - "Session total: {epics_completed}/{epics_total}" (cumulative)
  - "This context: {len(epics_executed_this_context)} EPICs executed" (actual work)

**Fix part C — Completion report:**

Update the session report template in FIRST_AID_COMPLETE to include:

```
  EPICs completed:  {completed} / {total}  (session total)
  EPICs executed:   {executed_this_context}  (this context)
  EPICs removed:    {removed_count}
```

And in the per-EPIC table, add a `!` prefix for removed EPICs and show status "removed" instead of steps/gates.

#### Step 5 — Cross-reference + CHANGELOG (S)

**Action:**
- Verify all 4 fixes are consistent across files (grep for `DETECT_EPIC_POSITION`, `plan_archival`, `release_sub_phase`, `"removed"` status)
- Verify `DETECT_EPIC_POSITION` is called from exactly 2 places: PM_APPROVAL (first-aid-controller.md) and RELEASE_SUB_PHASE (first-aid-controller.md DONE state)
- Update both CHANGELOGs with new version entry:
```
### Fixed
- **Plan archival** — QUEUE_ADVANCE now uses queue as ground truth for plan archival
  instead of filesystem scanning; DONE state no longer attempts archival (single source)
- **Version bump detection** — uses plan-level completion (`plan_epics_total`) instead of
  queue position; solo plans always bump, multi-EPIC plans bump on last EPIC
- **Release sub-phase** — DONE state now explicitly calls RELEASE_SUB_PHASE with mandatory
  stage_log entry; skipping is no longer possible without audit trail
- **Queue removal** — `/epic-queue remove` sets status "removed" (not "completed");
  context boundary tracking distinguishes session total from actually-executed EPICs
```
- Close IMP-043, IMP-044, IMP-045, IMP-046 in backlog → move to Implemented table with `epic_ref: E-014-2_2`, `version: {release version}`

**Verification greps (agent MUST run and confirm expected match counts):**

| Grep pattern | Expected matches | Where |
|-------------|-----------------|-------|
| `DETECT_EPIC_POSITION` | exactly 3 files | `auto-done-state.md` (definition + manual call), `first-aid-controller.md` (PM_APPROVAL + DONE RELEASE_SUB_PHASE) — 2 call sites, 1 definition |
| `plan_archival` | only `aid-first-aid.md` | QUEUE_ADVANCE single source of truth; DONE state mentions it as "handled by QUEUE_ADVANCE" |
| `"removed"` status | `epic-queue.md` + report templates | Status Values table, remove() operation, report template rows |
| `epics_executed_this_context` | `auto-done-state.md` + `aid-first-aid.md` | Schema definition + YAML template + completion report |

---

## Constraints

- All changes in `plugins/aid-orchestrator/` (skills, commands, defaults)
- EPIC 1 is pure simplification — no new features, only removal + rename
- EPIC 2 bug fixes must work with the simplified permission model from EPIC 1
- Deny-list stays in `.claude/settings.local.json` — not affected by permission simplification
- Execution order: EPIC 1 → EPIC 2 (sequential, EPIC 1 simplifies files that EPIC 2 patches)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Orphaned references to permission-sandwich after deletion | medium | low | Comprehensive grep scan in EPIC 1 Step 7; cross-reference check in gate |
| Release sub-phase fix introduces regression in manual mode | medium | medium | Test both auto-mode and manual paths; keep release logic in single source (`auto-done-state.md`) |
| Plan archival check misses EPICs not in queue | low | medium | Queue is source of truth; EPICs outside queue are not managed by FIRST AID |
| DETECT_EPIC_POSITION edge case with mixed plan/standalone EPICs in queue | low | medium | Fallback returns "standalone" — safer than skipping version bump |

## Success Criteria

- `permission-sandwich.md` deleted, zero references remain in plugin (verified by grep)
- `permissions-auto.yaml` deleted, zero references remain
- `aid-first-aid.md` has zero backup/elevate/restore logic — only a preset check
- `/aid-setup` shows Aspirin 💊 and Steroids 💉 as the two presets
- FIRST AID aborts with clear message if Steroids not active
- Plan archival executes automatically when all EPICs of a plan are done (verified via stage_log `"action": "plan_archival_check"`)
- Solo plans trigger version bump on their single EPIC completion
- Multi-EPIC plans trigger version bump on their last EPIC completion
- Release sub-phase (version bump, tag, CHANGELOG) executes in DONE state with mandatory stage_log
- Queue removal uses `"removed"` status distinct from `"completed"`
- Completion report distinguishes session total vs. actually-executed EPICs

## Next Steps

- [ ] Create EPIC E-013 for permission simplification (EPIC 1)
- [ ] Create EPIC E-014 for controller bug fixes (EPIC 2)
- [ ] Queue: E-013 → E-014 (sequential)

---

**Last Updated:** 2026-02-27
