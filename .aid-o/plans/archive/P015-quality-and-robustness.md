---
id: P015
type: plan
status: done
created: 2026-02-27
author: PM + AI
---

# Plan: Quality & Robustness

## Context

Deep qualitative audit of plans P009-P013 implementation revealed 17 quality issues across the AID orchestration engine. Original plans (P010, P011, P012) were written with vague instructions, resulting in implementations that are structurally present but contain runtime failures, silent wrong behavior, and cross-file inconsistencies. P014 (Aspirin & Steroids) covers permission sandwich removal and 4 controller bugs (IMP-043-046), leaving 15 issues for this plan (2 moved to backlog: hard-deny list patterns and --dry-run feature implementation).

## Goal

Fix all 15 quality and robustness issues identified in the P009-P013 audit, eliminating runtime failures in queue management and resume flow, correcting silent wrong behavior in approval guardrails and algorithm definitions, and establishing cross-file consistency for ID formats, untrusted content tagging, and single-source-of-truth references.

## Scope

**In scope:**
- Queue single-writer constraint and dependency validation (audit issues #1, #17)
- Resume filename mismatch fix (issue #2)
- PM_APPROVAL baseline and intermediate EPIC guardrail (issues #4, #5)
- Dry-run false promise removal (issue #6)
- adapt_example() simplification — merges issues #7 and #12 (undefined function + sequential PM questions)
- Setup idempotence (issue #8)
- OVERLAP_CHECK concrete algorithm (issue #9)
- Untrusted content tagging consistency (issue #10)
- CLAUDE.md count automation (issue #11)
- Credit exhaustion regex patterns (issue #13)
- Parallelism R1 concrete definition (issue #14)
- plan_ref matching stopping rule (issue #15)
- ID format standardization (issue #16)

**Out of scope:**
- P014 items (permission sandwich, IMP-043-046) — separate plan, EPICs already created (E-014-1_2, E-014-2_2)
- Hard-deny list pattern improvements (issue #3) — moved to backlog, requires security research beyond regex
- --dry-run feature implementation — moved to backlog with detailed spec (Step 5 creates the backlog entry)
- GUI workflow (P009) — separate plan revision
- Token optimization (P013) — separate plan revision
- New features or capabilities — this plan only fixes existing issues

## Approach

### Option A: Severity-First, 2 EPICs (Chosen)

Split into 2 EPICs by severity. EPIC 1 fixes all CRITICAL and HIGH issues (12 steps with 4 parallel groups). EPIC 2 fixes MEDIUM issues and adds queue infrastructure (4 steps). Gate checkpoint between EPIC 1 step 6 and step 7 ensures critical fixes are validated before proceeding.

**Pros:**
- Critical runtime failures (queue corruption, resume breakage) fixed first in EPIC 1 steps 1-3
- Parallel groups reduce effective execution time from 12 sequential dispatches to ~7
- Gate checkpoint at midpoint catches integration issues early
- EPIC 2 can be deferred if priorities change without leaving critical bugs unfixed

**Cons:**
- EPIC 1 has 12 steps (large for one EPIC, mitigated by 4 parallel groups)
- Some medium-priority issues deferred to EPIC 2

### Option B: File-Grouped (Rejected)

Group fixes by target file (all queue changes together, all controller changes together). Rejected because it mixes severity levels — a medium-priority CLAUDE.md fix would share an EPIC with a critical queue race condition fix, preventing priority-based execution.

### Option C: Single EPIC (Rejected)

All 16 steps in one EPIC. Rejected because 16 steps exceed recommended EPIC size (8-10 steps), provide no checkpoint for mid-execution validation, and a single failure blocks everything.

### Decision

**Chosen:** Option A — Severity-First, 2 EPICs
**Rationale:** Ensures critical runtime failures are fixed and validated before addressing medium-priority reliability improvements. Parallel groups keep EPIC 1 manageable despite 12 steps. Gate checkpoint at step 6 provides a natural validation point between critical and high-priority fixes.

## Architecture

### EPIC Structure

```
EPIC 1: Critical + High Fixes (12 steps)
  Group A (parallel): Steps 1, 2, 3 — Queue single-writer, Resume fix, PM_APPROVAL baseline
  Group B (parallel): Steps 4, 5, 6 — Intermediate guardrail, Dry-run removal, adapt_example()
  GATE CHECKPOINT (after step 6) — validate critical fixes before proceeding
  Group C (parallel): Steps 7, 8, 9 — Setup idempotence, OVERLAP_CHECK, Untrusted tags
  Group D (parallel): Steps 10, 11, 12 — R1 definition, plan_ref matching, ID format

EPIC 2: Medium Fixes + Queue Infrastructure (4 steps)
  Step 13: CLAUDE.md auto-count
  Step 14: Credit exhaustion regex
  Step 15: Queue dependency validation
  Step 16: Queue execution ordering (depends on Step 15)
```

### Design Principles

1. **Single-writer constraint** — Only the Controller (first-aid-controller.md) writes to epic-queue.yaml during FIRST AID auto-mode. Manual `/aid-epic-queue` commands may write when no FIRST AID session is active. This eliminates race conditions without file locking.

2. **Single source of truth** — Each constant, format, or pattern is defined in exactly one file. Other files reference the canonical source with explicit cross-references (e.g., "See `skills/epic-state-machine.md` > ID Format"). Changes propagate because there is only one definition to update.

3. **Concrete algorithms** — Every algorithm in the codebase has concrete pseudocode with defined inputs, outputs, stopping conditions, and edge case behavior. No vague descriptions like "expand globs" or "first match."

4. **Consistent tagging** — All dispatch templates wrap untrusted content (EPIC goals, step outputs, PM feedback) in `<untrusted_content>` tags. A single canonical list in dispatch-protocol.md defines which fields are untrusted. Both dispatch templates in aid-run-epic.md match this list exactly.

5. **Conservative defaults** — When an algorithm must decide between false positive and false negative, choose false positive. OVERLAP_CHECK returns CONFLICT when unsure. R1 classification treats ambiguous files as API CONTRACT. Keyword matching warns on low confidence.

### Affected Files

| File | Steps | Change Type |
|------|-------|-------------|
| `skills/epic-queue.md` | 1, 15, 16 | Major refactor: single-writer, depends_on field, execution ordering |
| `skills/first-aid-controller.md` | 1, 2, 3, 4 | Fix escalation snapshot, approval guardrails, auto-mode flag |
| `commands/aid-first-aid.md` | 2, 5 | Fix resume filename, remove dry-run promise |
| `skills/gate-evaluation.md` | 2, 14 | Fix resume reference, regex credit detection |
| `skills/knowledge-acquisition.md` | 6 | Simplify adapt_example() from 7 steps to 3 steps |
| `commands/aid-setup.md` | 7 | Add idempotence: re-run detection + section menu |
| `skills/planner.md` | 8, 10 | Concrete OVERLAP_CHECK algorithm, define R1 terms |
| `skills/dispatch-protocol.md` | 9, 11 | Canonical untrusted field list, plan_ref stopping rule |
| `commands/aid-run-epic.md` | 9 | Verify untrusted_content tag completeness in templates |
| `skills/epic-state-machine.md` | 12 | Formal ID Format section with canonical format + validation |
| `CLAUDE.md` | 13 | Replace hardcoded counts with verification instruction |
| `skills/epic-orchestration.md` | 13 | Add count verification to Release Sub-Phase |

## Implementation Steps

### Step 1: Queue Single-Writer Constraint

**Objective:** Refactor epic-queue.md so that only the Controller (first-aid-controller.md) performs write operations on epic-queue.yaml during FIRST AID auto-mode, eliminating race conditions from concurrent read-modify-write cycles.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-queue.md` (lines 60-78, 106-126) — refactor `add()`, `start()`, `complete()` to include conflict detection as Step 0
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (lines ~95-130) — add auto-mode flag creation at session start and deletion at session end

**Architecture Context:**
Currently, `add()` (line 60), `start()` (line 106), and `complete()` (line 117) in epic-queue.md all perform read-modify-write on epic-queue.yaml without any atomicity guarantee. When FIRST AID auto-mode runs alongside manual `/aid-epic-queue` commands, two agents can read the same YAML state, modify it independently, and write back — one agent's changes overwrite the other's. The single-writer constraint from the Architecture section ensures only the Controller writes during auto-mode, while manual commands can write when no auto-mode session is active.

**Implementation Detail:**
1. Add a `## Write Ownership` section at the top of epic-queue.md (after the file overview, before line 60):
   ```
   ## Write Ownership

   WRITE RULE: Only the Controller (first-aid-controller.md) may call
   add(), start(), complete(), remove(), pause(), resume() during FIRST AID
   auto-mode. Manual /aid-epic-queue commands may write when no FIRST AID
   session is active.

   CONFLICT DETECTION — must run as Step 0 of every write function:
   1. Read .aid-o/04-engine/auto-mode-active.flag
   2. IF flag exists AND caller is NOT Controller:
      → Check flag timestamp. IF older than 2 hours → treat as stale,
        log warning "Stale auto-mode flag detected (>2h), proceeding with write"
      → ELSE → REJECT with error:
        "Queue write rejected: FIRST AID session active. Use /aid-stop first."
   3. IF flag does not exist → proceed with write
   ```
2. Modify each write function (`add()` at line 60, `start()` at line 106, `complete()` at line 117) to include this conflict detection as Step 0 before the existing logic
3. In first-aid-controller.md, add flag file management:
   - At session start (after existing session initialization near line 95): create `.aid-o/04-engine/auto-mode-active.flag` containing `{"started_at": "<ISO timestamp>", "session_id": "<session_id>"}`
   - At session end (both normal completion and `/aid-stop`): delete the flag file
   - In `/aid-stop` command handler: explicitly delete the flag as part of emergency stop

**Error Handling:**
- Stale flag from crashed session: the flag file contains a `started_at` timestamp. If older than 2 hours, treat as stale — allow write with a warning log. The `/aid-stop` command also deletes this flag as part of its cleanup.
- epic-queue.yaml is malformed (corrupted by a previous race condition): each write function should validate YAML parse in its read step. If parse fails, log the error with the raw file content and refuse to write. PM must manually fix the corrupted file.

**Edge Cases:**
- Stale flag from crashed FIRST AID session — timestamp check (2-hour TTL) prevents permanent lockout. PM can also run `/aid-stop` to clear the flag manually.
- Two manual `/aid-epic-queue` calls in rapid succession (no FIRST AID active) — both proceed because no flag exists. The write window for manual commands is short enough that concurrent manual usage is impractical.
- Flag file deleted by another process mid-operation — current operation continues (flag was checked at Step 0). Next operation re-checks.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] `add()`, `start()`, `complete()` each contain conflict detection as Step 0
- [ ] `.aid-o/04-engine/auto-mode-active.flag` is created at FIRST AID session start with timestamp and session_id
- [ ] Flag is deleted at session end (normal completion) and by `/aid-stop` (emergency stop)
- [ ] When flag exists and caller is not Controller, manual `/aid-epic-queue add` returns rejection message: "Queue write rejected: FIRST AID session active. Use /aid-stop first."
- [ ] Stale flag (>2 hours old) is treated as absent with a warning log

**Effort:** M
**AID Role:** architect

---

### Step 2: Resume Filename Mismatch Fix

**Objective:** Align the escalation snapshot filename in first-aid-controller.md with the resume detection filename in aid-first-aid.md, so that partial work is correctly recovered after PM escalation.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (lines 119-124) — change snapshot filename from `auto-mode-state-snapshot-{epic_id}.json` to `interrupted_step_context.json`
- Modify: `plugins/aid-orchestrator/commands/aid-first-aid.md` (lines 1310, 1324) — verify resume detection reads `interrupted_step_context.json` (should already be correct)
- Modify: `plugins/aid-orchestrator/skills/gate-evaluation.md` — search for any references to either filename and align to `interrupted_step_context.json`

**Architecture Context:**
When FIRST AID escalates to PM (ultra-extreme scenario requiring human intervention), first-aid-controller.md saves progress to `auto-mode-state-snapshot-{epic_id}.json` (line 119). When the PM later resumes with `/aid-first-aid`, the RESUME_INTERRUPTED_STEP logic in aid-first-aid.md (line 1310) looks for `interrupted_step_context.json` in the evidence directory. These are different filenames — the resume logic never finds the snapshot, and partial work is silently lost. The canonical filename is `interrupted_step_context.json` because that is what the resume reader expects.

**Implementation Detail:**
1. In first-aid-controller.md (lines 119-124), replace the snapshot write:
   ```
   BEFORE:
     a. Write snapshot file: .aid-o/04-engine/auto-mode-state-snapshot-{epic_id}.json

   AFTER:
     a. Write snapshot file: evidence/{epic_id}/{run_id}/interrupted_step_context.json
   ```
2. Verify the JSON structure written by first-aid-controller.md matches what aid-first-aid.md (lines 1310-1327) expects. The structure must include at minimum: `epic_id`, `run_id`, `step_number`, `step_status`, `partial_outputs`, `escalation_reason`, `timestamp`.
3. In aid-first-aid.md (lines 1310, 1324), verify the path matches: `evidence/{epic_id}/{run_id}/interrupted_step_context.json`. The reader already expects this path — confirm it is correct.
4. Grep gate-evaluation.md for both `auto-mode-state-snapshot` and `interrupted_step_context` — align any references to the canonical name.
5. Grep all other plugin files for `auto-mode-state-snapshot` — replace any remaining references.

**Error Handling:**
- If both filenames exist in an evidence directory (from a partially-fixed state where the old code wrote one name and new code writes another): resume logic should check for both, prefer `interrupted_step_context.json`, and log a warning if `auto-mode-state-snapshot-*.json` is also found: "Legacy snapshot file found alongside canonical file — using interrupted_step_context.json"
- If the JSON structure written by the controller is missing fields that the reader expects: add a `schema_version: 1` field to the JSON. Reader validates schema_version before using data and rejects unknown versions with a clear error.

**Edge Cases:**
- Old snapshots with the previous filename exist in historical evidence directories — no migration needed. They are artifacts from runs where resume was already broken (the files were never successfully read). They can be ignored or deleted manually.
- PM escalation happens during a parallel step group — the snapshot must capture all in-progress step states, not just the failing one. Verify the JSON structure accommodates an array of step contexts.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] first-aid-controller.md writes `interrupted_step_context.json` (not `auto-mode-state-snapshot-*.json`)
- [ ] aid-first-aid.md RESUME_INTERRUPTED_STEP reads the same filename from the same path
- [ ] JSON structure written by controller includes all fields expected by the reader
- [ ] Grep for `auto-mode-state-snapshot` across all plugin files returns 0 matches

**Effort:** S
**AID Role:** architect

---

### Step 3: PM_APPROVAL Baseline for First EPIC

**Objective:** Add a default quality baseline when no prior audit report exists, so the first EPIC in a project's queue receives the same approval guardrails as subsequent EPICs instead of being silently skipped.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (lines 222-227) — replace "skip this guardrail" with default baseline logic

**Architecture Context:**
The PM_APPROVAL guardrail in first-aid-controller.md (line 225) checks `auditor_trend` from the previous EPIC's audit report to validate quality trajectory. When no prior audit report exists (first EPIC ever run in a project), the guardrail is skipped entirely with a log message "No prior audit report found — auditor_trend guardrail skipped." This means the first EPIC gets zero quality validation — the very EPIC that establishes the project's quality baseline. The fix introduces DEFAULT_BASELINE checks that apply when no historical comparison data is available.

**Implementation Detail:**
1. Add a DEFAULT_BASELINE constant block before the PM_APPROVAL section (before line 222):
   ```
   DEFAULT_BASELINE — applies when no prior audit report exists:
     Check 1: All acceptance criteria in the EPIC have explicit pass/fail status
              (no "pending" or "not evaluated" criteria remaining)
     Check 2: No step has status "skipped" without a PM-approved reason
              (skipped steps must have skip_reason field populated)
     Check 3: Evidence directory exists with at least one artifact per completed step
              (evidence/{epic_id}/{run_id}/ contains subdirectories or files)
   ```
2. Replace lines 225-226:
   ```
   BEFORE:
     - IF no prior audit report exists: skip this guardrail check with log
       "No prior audit report found — auditor_trend guardrail skipped"

   AFTER:
     - IF no prior audit report exists:
       → Apply DEFAULT_BASELINE guardrails (3 checks defined above)
       → Log: "No prior audit — applying default baseline (3 checks)"
       → IF all 3 checks pass: auto-approve with log
         "First EPIC passed default baseline — establishing quality reference point"
       → IF any check fails: escalate to PM for approval with details:
         "First EPIC failed default baseline: {list of failed checks}.
          PM approval required to proceed."
   ```

**Error Handling:**
- If evidence directory does not exist at all (not just empty but missing entirely): treat as hard failure for Check 3. This indicates the run infrastructure is broken, not just a first-EPIC quality issue. Escalate to PM with: "Evidence directory missing — run infrastructure may be broken."

**Edge Cases:**
- First EPIC is also the only EPIC (project has a single-plan single-phase setup) — default baseline still applies. PM approval is requested only if checks fail, not unconditionally.
- Prior audit report exists but is corrupted or unparseable YAML/JSON — treat same as "no prior audit," apply default baseline with a warning log: "Prior audit report unparseable — falling back to default baseline."

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] First EPIC without prior audit triggers DEFAULT_BASELINE checks (not skip)
- [ ] DEFAULT_BASELINE is defined as a named constant block with 3 specific checks
- [ ] When default checks pass, auto-approve with log message (no PM interruption)
- [ ] When default checks fail, PM is prompted with specific failure details

**Effort:** S
**AID Role:** architect

---

### Step 4: Intermediate EPIC Guardrail

**Objective:** Add a lightweight quality check for intermediate EPICs instead of unconditionally auto-approving them with zero validation.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (lines 205-213) — replace unconditional auto-approve with INTERMEDIATE_GUARDRAIL check

**Architecture Context:**
When an EPIC is in the "intermediate" position in the queue (not first, not last), first-aid-controller.md (line 207) auto-approves it immediately: "Auto-approve immediately (no guardrails required for intermediate EPICs)." The comment says "low-risk" but provides no justification. A failing intermediate EPIC cascades into queue failure because downstream EPICs may depend on files or state produced by the intermediate one. The fix adds a lightweight guardrail that catches obvious failures without the full PM_APPROVAL overhead.

**Implementation Detail:**
1. Add INTERMEDIATE_GUARDRAIL constant block alongside DEFAULT_BASELINE (from Step 3):
   ```
   INTERMEDIATE_GUARDRAIL — applies to EPICs in intermediate queue position:
     Check 1: All steps completed — no step has status "pending" or "blocked"
              (steps with status "completed" or "skipped" are acceptable)
     Check 2: No gate failures in the run — gate retries are OK (the retry succeeded),
              but a final gate failure (retry exhausted, gate still failing) is not
     Check 3: Evidence directory has at least 1 file per completed step
              (skipped steps are excluded from this check)
   ```
2. Replace lines 205-213:
   ```
   BEFORE:
     2. IF position == "intermediate":
        → Auto-approve immediately (no guardrails required for intermediate EPICs)

   AFTER:
     2. IF position == "intermediate":
        → Apply INTERMEDIATE_GUARDRAIL (3 checks defined above)
        → IF all 3 checks pass: auto-approve with log
          "Intermediate EPIC passed lightweight guardrail (3/3 checks)"
        → IF any check fails: escalate to PM with specific failure details:
          "Intermediate EPIC failed guardrail: {list of failed checks}.
           Downstream EPICs may be affected. PM approval required."
   ```

**Error Handling:**
- If step status tracking is inconsistent (step shows "completed" in the run file but has no evidence artifacts): flag as guardrail failure for Check 3. Escalate to PM — do not auto-approve with inconsistent state.

**Edge Cases:**
- Intermediate EPIC with all steps PM-approved-skipped — passes guardrail because "skipped" status is acceptable for Checks 1 and 3
- Intermediate EPIC where a gate retry succeeded on the second attempt — passes guardrail because Check 2 looks at final gate status (pass), not retry history
- Queue has only 2 EPICs (first + last, no intermediate position) — this code path never executes, which is correct behavior

**Dependencies:**
- No dependencies — can start independently (Step 3 adds DEFAULT_BASELINE in the same file but INTERMEDIATE_GUARDRAIL is a separate constant block)

**Acceptance Criteria:**
- [ ] Intermediate EPICs are no longer unconditionally auto-approved
- [ ] INTERMEDIATE_GUARDRAIL is a named constant block with 3 specific checks
- [ ] Failed intermediate guardrail escalates to PM with details including which checks failed
- [ ] Passed intermediate guardrail auto-approves with a log message confirming "3/3 checks"

**Effort:** S
**AID Role:** architect

---

### Step 5: Dry-Run False Promise Removal

**Objective:** Remove the misleading --dry-run documentation from aid-first-aid.md and replace the incomplete handler with a clear "not implemented" exit, while preserving the feature specification in a backlog file for future implementation.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-first-aid.md` (lines 17-18, 30, 92-95) — remove --dry-run from usage docs, update handler to exit with "not implemented" message
- Create: `.aid-o/04-engine/backlog/dry-run-feature.md` — detailed feature specification for future implementation

**Architecture Context:**
The aid-first-aid.md command advertises `--dry-run` in its usage section (line 17-18) and shows it in examples (line 30). Lines 92-95 contain a conditional check for the flag, but the implementation is incomplete — it does not actually simulate the pipeline without side effects. Users who run `--dry-run` expecting a safe preview get either partial output or the same behavior as a real run. Per PM decision, the false promise is removed now and the feature goes to the backlog with a detailed spec for future implementation.

**Implementation Detail:**
1. In aid-first-aid.md line 17-18: remove `--dry-run` from the flags/options documentation section
2. In line 30: remove the `--dry-run` example from the examples section
3. In lines 92-95, replace the incomplete handler with a clear exit:
   ```
   IF $ARGUMENTS contains "--dry-run":
     Output to PM: "--dry-run is not yet implemented."
     Output to PM: "Feature spec: .aid-o/04-engine/backlog/dry-run-feature.md"
     EXIT (do not proceed with any pipeline execution)
   ```
4. Create the backlog directory if it does not exist: `.aid-o/04-engine/backlog/`
5. Create `.aid-o/04-engine/backlog/dry-run-feature.md` with the following content:
   ```markdown
   # Feature: --dry-run Mode for FIRST AID

   **Status:** Backlog
   **Priority:** Medium
   **Source:** P015 audit, issue #6
   **Created:** 2026-02-27

   ## Description

   Add a --dry-run flag to /aid-first-aid that simulates the full orchestration
   pipeline without executing any agent dispatches or writing to run/evidence files.

   ## Expected Behavior

   - Parse EPIC and generate Plan JSON as normal (read-only operations)
   - Display which steps would execute and in what order
   - Display parallel group assignments with dependency information
   - Display which agent roles would be dispatched for each step
   - Display estimated token budget per step (from Plan JSON)
   - Do NOT: write run files, create evidence directories, modify epic-queue.yaml,
     dispatch any agents, or execute any gate evaluations

   ## Output Format

   Structured summary showing the execution plan:
   - Step execution order with parallel groups
   - Agent role assignments per step
   - Token budget estimates
   - Dependency chain visualization

   ## Implementation Notes

   - Requires dispatch-protocol.md to support a "simulate" mode that generates
     dispatch prompts but does not send them
   - Gate evaluation should output "would check: {criteria}" without executing
   - Queue operations should output "would update: {field} to {value}" without writing
   - The simulate mode must follow the same code paths as real execution to ensure
     the dry-run output accurately reflects what would happen
   ```

**Error Handling:**
- If user passes `--dry-run` combined with other flags (e.g., `--dry-run --force`): still output the "not implemented" message and exit immediately. Do not process any other flags or start the pipeline.

**Edge Cases:**
- User has muscle memory for `--dry-run` from reading old documentation — the clear message and backlog file reference help them understand the feature status and find the spec
- Backlog directory `.aid-o/04-engine/backlog/` does not exist in the target project — the step must create it before writing the backlog file

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] `--dry-run` no longer appears in aid-first-aid.md usage section or examples
- [ ] Running `/aid-first-aid --dry-run` outputs "not implemented" message and exits without any pipeline execution
- [ ] Backlog file exists at `.aid-o/04-engine/backlog/dry-run-feature.md` with complete feature spec (Description, Expected Behavior, Output Format, Implementation Notes)

**Effort:** S
**AID Role:** architect

---

### Step 6: Simplify adapt_example() to 3 Steps

**Objective:** Replace the broken 7-step adapt_example() function in knowledge-acquisition.md with a working 3-step version that removes the undefined `replace_tool_references()` calls and auto-infers paths from project-profile.yaml instead of asking PM sequential questions.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/knowledge-acquisition.md` (lines 1807-1814 function definition, lines 2018-2024 replace_tool_references calls) — rewrite adapt_example() from 7 steps to 3 steps

**Architecture Context:**
The current adapt_example() function has two compounding problems: (1) Step 4 of the 7-step process calls `replace_tool_references()` at lines 2018, 2021, and 2024 — a function that is never defined anywhere in the codebase. When an agent executing knowledge acquisition reaches this step, it gets stuck trying to resolve the undefined function. (2) Step 1 asks PM 10+ sequential questions to resolve path placeholders in examples, which is tedious and defeats the automation purpose. The simplified 3-step version auto-infers paths from project-profile.yaml and eliminates the undefined function entirely.

**Implementation Detail:**
1. Replace the entire adapt_example() function definition (starting at line 1807) and its step definitions through the function body with:
   ```
   adapt_example(example_path, project_profile):
     """Adapt a knowledge base example to match the target project's paths and tools."""

     INPUT: example_path (path to .md example file), project_profile (parsed project-profile.yaml)
     OUTPUT: adapted example content (string)

     Step 1 — PATH SUBSTITUTION:
       Read the example file content.
       Find all placeholder patterns matching the format {{PLACEHOLDER_NAME}}.
       Replace each recognized placeholder with the corresponding project_profile value:
         {{PROJECT_ROOT}} → project_profile.directories.root
         {{SRC_DIR}} → project_profile.directories.plugin (or project_profile.directories.root + "/src" if .plugin absent)
         {{TEST_DIR}} → project_profile.directories.root + "/tests" (or "tests" if not configured)
         {{LANGUAGE}} → project_profile.tech_stack.languages[0] (first language)
         {{FRAMEWORK}} → project_profile.tech_stack.frameworks[0] (first framework)
       IF a placeholder has no matching value in project_profile:
         Leave it unchanged and append an inline comment: <!-- TODO: replace {{X}} with actual path -->

     Step 2 — TOOL REFERENCE UPDATE:
       Read project_profile.tech_stack arrays: .test[], .lint[], .build[], .type_check[]
       In the example content, find lines containing tool command references:
         Lines matching patterns: "test:", "npm test", "pytest", "jest", "lint:", "eslint", "build:", "tsc"
       For each tool category (test, lint, build, type_check):
         IF the project has configured tools for this category:
           Replace the example's tool command with the project's actual command
           (e.g., replace "pytest" with project_profile.tech_stack.test[0])
         IF the project has no tools configured for this category (empty array):
           Comment out the line: <!-- No {category} tool configured: {original_line} -->

     Step 3 — VALIDATION:
       Grep the adapted content for remaining "{{" patterns → these are unresolved placeholders
       Grep for broken markdown links: "](" followed by ")" with nothing between → empty links
       IF unresolved placeholders found: log count as warning, content is still usable
       IF broken links found: log each broken link location as warning
       Return the adapted content string
   ```
2. Delete all three `replace_tool_references()` calls at lines 2018, 2021, and 2024
3. Delete the `replace_tool_references` function signature/reference if it appears anywhere else in the file
4. Remove any remaining references to the old 7-step process numbering

**Error Handling:**
- If project_profile.yaml is missing or cannot be parsed: return the example content unchanged with a warning comment prepended: `<!-- Warning: project-profile.yaml not found or unparseable — example not adapted. Run /aid-setup to create profile. -->`
- If example file at example_path does not exist or is unreadable: return an error message to the caller: `"Error: Example file not found at {example_path}"` — do not return empty string or fail silently

**Edge Cases:**
- Project has no test/lint/build tools configured (all arrays empty) — Step 2 comments out all tool reference lines instead of leaving commands that won't work
- Example contains nested placeholders like `{{SRC_DIR}}/{{FRAMEWORK}}/config.ts` — Step 1 replaces each placeholder independently from left to right. After substitution: `plugins/aid-orchestrator/React/config.ts`
- Example references a tool category not in the standard set (e.g., a `deploy:` command) — left unchanged by Step 2, no error raised

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] adapt_example() has exactly 3 named steps: PATH SUBSTITUTION, TOOL REFERENCE UPDATE, VALIDATION
- [ ] `replace_tool_references` does not appear anywhere in knowledge-acquisition.md (grep returns 0 matches)
- [ ] Grep for `replace_tool_references` across all plugin files returns 0 matches
- [ ] Missing project-profile.yaml produces a warning comment, not a crash or silent failure

**Effort:** M
**AID Role:** domain

---

**GATE CHECKPOINT** — After Step 6, validate before proceeding to Steps 7-12:
- Steps 1-6 acceptance criteria all pass
- Grep regression: `auto-mode-state-snapshot` returns 0 matches, `replace_tool_references` returns 0 matches
- No unintended changes to files outside the listed scope

---

### Step 7: Setup Idempotence

**Objective:** Make `/aid-setup` safe to re-run by detecting existing configuration and offering a section-by-section update menu instead of overwriting all settings.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (lines ~1490 area for existing check, plus adding detection logic near the beginning of the setup flow) — add re-run detection and section menu

**Architecture Context:**
Running `/aid-setup` a second time overwrites project-profile.yaml and all custom configurations without warning. Line 1490 has a minimal check: "If project-profile.yaml already has initialized: true, ask before overwriting." But this is a single yes/no prompt for the entire file — it does not preserve section-level customizations like manually added MCP servers or custom directory paths. The fix adds comprehensive re-run detection that shows which sections have been customized and lets PM choose which to update selectively.

**Implementation Detail:**
1. At the very beginning of the setup flow (before any tech stack detection or prompts), add a RE-RUN DETECTION section:
   ```
   RE-RUN DETECTION — execute before any other setup step:

   1. Check if .aid-o/04-engine/memory/project-profile.yaml exists AND has initialized: true
   2. IF yes (re-run detected):
      a. Read existing project-profile.yaml into memory
      b. Present to PM:
         "Existing AID configuration detected.
          Initialized: {scanned_at date from profile}
          Project: {project_name}

          Select sections to update (comma-separated numbers, or 'all'):
          (1) Tech Stack — re-detect languages, frameworks, tools
          (2) MCP Servers — re-scan available MCP servers
          (3) Directories — re-detect project directory structure
          (4) Memory — reconfigure memory provider settings
          (5) Knowledge — reconfigure knowledge/context7 settings
          (6) Full re-scan — re-detect everything from scratch (keeps custom values as defaults)
          (0) Cancel — keep current configuration, exit setup"
      c. Read PM's selection
      d. IF PM selects "0": exit setup without changes
      e. IF PM selects "6" or "all": run full setup but pre-populate prompts with existing values
         (PM sees current value as default, can press Enter to keep or type new value)
      f. IF PM selects specific sections (e.g., "1,3"):
         Run only those sections of the setup wizard
         Merge results into existing project-profile.yaml:
         - Update only the fields belonging to selected sections
         - Preserve all fields from unselected sections unchanged
         - Preserve any custom fields not in the standard schema
      g. Update scanned_at timestamp after any changes
   3. IF no (fresh install): proceed with full setup as before
   ```
2. Replace the single check at line 1490 with a reference to the new RE-RUN DETECTION block: "See RE-RUN DETECTION at the beginning of this flow — re-run safety is handled there."

**Error Handling:**
- If project-profile.yaml exists but is corrupted (invalid YAML): present to PM: "Existing project-profile.yaml is corrupted (parse error: {error}). Options: (A) Start fresh setup — overwrites corrupted file. (B) Abort — fix file manually first." Do not silently overwrite.
- If PM selects a section that depends on another (e.g., Knowledge section depends on MCP Servers for context7 availability): warn: "Knowledge configuration depends on MCP Servers. Recommended to update MCP Servers (2) as well. Proceed anyway? (Y/N)"

**Edge Cases:**
- PM runs setup, changes nothing, runs setup again immediately — re-run detection shows the menu, PM selects 0 (cancel), exits cleanly with no file modifications
- PM manually edited project-profile.yaml and added custom fields not in the standard schema (e.g., `custom_deploy_target: staging`) — custom fields must be preserved during merge because only known section fields are updated
- `.aid-o/` directory exists but project-profile.yaml does not (partial initialization from interrupted first run) — treat as fresh install for the profile, but note that workspace structure already exists

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Running `/aid-setup` when project-profile.yaml has `initialized: true` shows the section menu (not immediate overwrite)
- [ ] Selecting specific sections (e.g., "1,3") only updates Tech Stack and Directories in project-profile.yaml
- [ ] Custom fields in project-profile.yaml that are not part of any standard section are preserved after selective update
- [ ] Fresh install (no prior profile) still works identically to current behavior

**Effort:** M
**AID Role:** architect

---

### Step 8: OVERLAP_CHECK Concrete Algorithm

**Objective:** Replace the vague OVERLAP_CHECK algorithm in planner.md with concrete pseudocode that defines glob matching rules, handles all path comparison cases, and has an explicit conflict resolution strategy.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (lines 683-696) — replace vague algorithm with concrete pseudocode

**Architecture Context:**
The OVERLAP_CHECK algorithm in planner.md (line 683) is used during parallel step planning to detect when two steps modify the same files. If two parallel steps write to the same file, the results are unpredictable. The current algorithm says "expand globs" but does not define how glob expansion works. Comparing `src/api/**/*.py` against `src/api/routers/auth.py` has no defined outcome — does `**/*.py` match a nested path? The fix provides a complete algorithm with defined behavior for every case, following the conservative defaults principle from the Architecture section.

**Implementation Detail:**
Replace lines 683-696 entirely with:
```
OVERLAP_CHECK(step_A, step_B):
  """Detect file scope conflicts between two parallel steps.
  Returns: CONFLICT | SAFE
  Principle: Conservative — when in doubt, return CONFLICT (prefer false positive over false negative)."""

  INPUT: step_A.files[] and step_B.files[] — each entry is a file path (exact or glob pattern)
         Only "Create" and "Modify" entries participate. "Read" and "Test" entries are excluded
         (reading and testing are safe in parallel).

  1. EXTRACT writable paths:
     writable_A = [f.path for f in step_A.files if f.action in ("Create", "Modify")]
     writable_B = [f.path for f in step_B.files if f.action in ("Create", "Modify")]
     IF either list is empty → return SAFE (no write conflicts possible)

  2. NORMALIZE all paths:
     - Strip leading "./" or "/" (make relative to project root)
     - Normalize path separators to "/"
     - Case-insensitive comparison (accommodates macOS/Windows filesystems)

  3. For each pair (path_A from writable_A, path_B from writable_B):

     Case A — BOTH EXACT PATHS (no *, no **):
       IF lowercase(path_A) == lowercase(path_B) → CONFLICT
       ELSE → this pair is SAFE

     Case B — ONE GLOB, ONE EXACT:
       Test: does the exact path match the glob pattern?
       Glob matching rules:
         "*"  → matches any characters EXCEPT "/" (single directory level)
         "**" → matches zero or more path segments including "/" (recursive)
         "?"  → matches exactly one character except "/"
       Examples:
         "src/api/*.py" matches "src/api/auth.py" → CONFLICT
         "src/api/*.py" does NOT match "src/api/routers/auth.py" (no recursive)
         "src/api/**/*.py" matches "src/api/routers/auth.py" → CONFLICT
         "src/**" matches "src/any/nested/file.ts" → CONFLICT
       IF match → CONFLICT
       ELSE → this pair is SAFE

     Case C — BOTH GLOBS:
       Conservative heuristic (exact glob intersection is computationally expensive):
       1. Extract the fixed prefix of each glob (everything before the first * or **):
          "src/api/**/*.py" → prefix = "src/api/"
          "src/models/**/*.py" → prefix = "src/models/"
       2. IF neither prefix starts with the other → SAFE
          (different directory trees cannot overlap)
          "src/api/" and "src/models/" → SAFE
       3. IF one prefix starts with the other (or prefixes are identical):
          Check file extension filters (if present):
          "src/api/**/*.py" and "src/api/**/*.ts" → SAFE (different extensions)
          "src/api/**/*.py" and "src/api/**/*.py" → CONFLICT (same extension)
          "src/api/**/*" and "src/api/**/*.py" → CONFLICT (wildcard includes .py)
       4. IF ambiguous after prefix and extension checks → CONFLICT (conservative)

  4. IF any pair produces CONFLICT → return CONFLICT
  5. IF all pairs are SAFE → return SAFE

  NOTE: False positive (marking safe steps as conflicting) causes sequential execution —
  slower but correct. False negative (marking conflicting steps as safe) causes file
  corruption — fast but broken. Always prefer false positive.
```

**Error Handling:**
- If a file path is malformed (contains `..`, starts with `~`, or uses Windows backslashes): normalize by resolving `..` segments, expanding `~` to project root, and replacing `\` with `/`. If still malformed after normalization, treat as conflicting with everything (conservative).

**Edge Cases:**
- One step has an empty file list (documentation-only step with no file modifications) — writable paths list is empty, OVERLAP_CHECK returns SAFE immediately at step 1
- Step creates a directory (e.g., `src/api/`) while another modifies files inside it — directory creation and file modification are independent operations, but the step's file list should reference the directory as a "Create" entry. If `src/api/` is a Create and `src/api/auth.py` is a Modify, these don't conflict (creating a parent directory is a prerequisite, not a write conflict).
- Both steps only read the same file (both have "Read" entries) — excluded from comparison at step 1, returns SAFE

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] OVERLAP_CHECK has concrete pseudocode covering all 3 cases: exact-exact, glob-exact, glob-glob
- [ ] Glob matching rules define behavior for `*`, `**`, and `?` patterns explicitly
- [ ] Case C (both globs) uses prefix + extension heuristic with conservative fallback
- [ ] Grep for "expand globs" in planner.md returns 0 matches (vague phrasing removed)

**Effort:** M
**AID Role:** architect

---

### Step 9: Untrusted Content Tagging Consistency

**Objective:** Create a single canonical list of untrusted fields in dispatch-protocol.md and verify both dispatch templates in aid-run-epic.md wrap every listed field in `<untrusted_content>` tags.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines 107-139) — add explicit canonical field list with trusted/untrusted classification
- Modify: `plugins/aid-orchestrator/commands/aid-run-epic.md` (lines 189-241 base template, lines 259-319 re-dispatch template) — verify all untrusted fields are consistently wrapped

**Architecture Context:**
dispatch-protocol.md (lines 107-139) defines the security rules for wrapping untrusted content in `<untrusted_content>` tags to prevent prompt injection. aid-run-epic.md (lines 189-241 and 259-319) contains the two actual dispatch templates (initial dispatch and re-dispatch after gate failure). The audit found inconsistencies — some fields wrapped in one template but not the other, some fields mentioned in the security rules but not wrapped in templates. This step creates a definitive canonical list and ensures both templates match it exactly.

**Implementation Detail:**
1. In dispatch-protocol.md, replace or enhance the Security section (lines 107-139) with an explicit canonical list:
   ```
   ## Security — Untrusted Content Framing

   CANONICAL UNTRUSTED FIELD LIST — single source of truth for dispatch templates.
   Both templates in aid-run-epic.md MUST wrap these fields in <untrusted_content> tags.

   UNTRUSTED (wrap in <untrusted_content> tags — content originates from PM, external sources, or previous agent output):
     - epic_goal — PM-authored text, may contain injection attempts
     - step_objective — derived from plan (PM-influenced)
     - step_inputs — derived from plan (PM-influenced)
     - step_outputs — derived from plan (PM-influenced)
     - step_constraints — derived from plan (PM-influenced)
     - previous_step_outputs — agent-generated content from prior steps, may reflect injected content
     - acceptance_feedback — PM or auditor-written feedback on failed gate
     - memory_context — retrieved from vector store, may contain injected memories
     - knowledge_context — retrieved from external documentation sources

   TRUSTED (do NOT wrap — system-generated, not influenced by external input):
     - role_assignment — determined by dispatcher based on plan
     - playbook_content — loaded from plugin files (read-only)
     - tool_permissions — determined by permission policy (system-controlled)
     - gate_criteria — loaded from gates.yaml (system-controlled)
     - step_number — integer from plan execution order
     - plan_ref_content — loaded from plan file (PM-approved, treated as trusted post-approval)

   MAINTENANCE RULE: When adding new fields to dispatch templates, classify
   them here first. If the field's content can be influenced by PM input,
   user data, or external sources → UNTRUSTED. If purely system-generated → TRUSTED.
   ```
2. In aid-run-epic.md, audit both templates:
   - Base dispatch template (lines 189-241): verify every field from the UNTRUSTED list above is wrapped in `<untrusted_content>` tags. Add missing tags.
   - Re-dispatch template (lines 259-319): same verification. This template often has fewer tags because it was written later — ensure parity with base template.
3. Remove any tags wrapping TRUSTED fields (if present — unnecessary wrapping is harmless but confusing).

**Error Handling:**
- If a dispatch template references a field not in either the UNTRUSTED or TRUSTED list: add the field to the appropriate list with a classification rationale before deciding whether to wrap it.

**Edge Cases:**
- A field is empty or null at dispatch time — still wrap in tags: `<untrusted_content></untrusted_content>`. Empty tags maintain consistent structure and prevent the agent from misinterpreting field boundaries.
- New fields added to dispatch templates in future development — the MAINTENANCE RULE comment in the canonical list reminds developers to classify new fields before adding them to templates.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] dispatch-protocol.md has a single canonical UNTRUSTED FIELD LIST with 9 untrusted and 6 trusted fields, each with a classification rationale
- [ ] Every untrusted field in the base dispatch template (lines 189-241) is wrapped in `<untrusted_content>` tags
- [ ] Every untrusted field in the re-dispatch template (lines 259-319) is wrapped in `<untrusted_content>` tags
- [ ] No inconsistencies between the two templates (same fields wrapped in both)

**Effort:** S
**AID Role:** security

---

### Step 10: Parallelism Rule R1 Concrete Definition

**Objective:** Replace the subjective conditions in planner.md Rule R1 with concrete, file-type-based definitions of "API contract" and "data model" that agents can apply mechanically.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (lines 533-538) — replace vague R1 with precise definitions and determination algorithm

**Architecture Context:**
Rule R1 in planner.md says frontend work can parallelize with domain work when domain "only produces data models (no API contracts)." But it never defines what constitutes a "contract" vs a "model." An agent deciding whether to parallelize frontend and domain steps has no objective criteria — the decision becomes subjective, leading to inconsistent parallel group assignments. The fix provides explicit file-type-based definitions following the concrete algorithms principle from the Architecture section.

**Implementation Detail:**
Replace lines 533-538 with:
```
RULE R1: "Frontend can parallelize with Domain when Domain produces only data models"

DEFINITIONS:

  DATA MODEL — a step that ONLY creates or modifies:
    - Database schema files: *.prisma, *.sql, migrations/*, *.dbml
    - Type/interface definition files: types.ts, interfaces.ts, models.py, types.py
    - Entity/DTO class files that define data shape but NO callable methods
    - Configuration files: *.yaml, *.json, *.toml, *.env
    - Documentation files: *.md (no executable behavior)

  API CONTRACT — a step that creates or modifies ANY of:
    - Route/endpoint definitions: router.ts, urls.py, routes/, controllers/
    - Request/response validation schemas used at HTTP boundaries
      (e.g., zod schemas in route handlers, pydantic models in FastAPI endpoints)
    - Middleware, interceptors, or request pipeline components
    - OpenAPI/Swagger specification files: *.openapi.yaml, *.swagger.json
    - Service interfaces with public methods that other components call
      (e.g., AuthService with login(), register(), verify() methods)
    - WebSocket event handlers or message schemas
    - GraphQL schema definitions (*.graphql, schema.ts)

DETERMINATION ALGORITHM:
  1. List all files in the Domain step's "Files" section (Create + Modify entries only)
  2. For each file, classify as DATA MODEL or API CONTRACT using the definitions above
  3. IF all files classify as DATA MODEL → R1 applies, frontend step can run in parallel
  4. IF any file classifies as API CONTRACT → R1 does NOT apply, frontend must wait
  5. IF classification is ambiguous (file doesn't clearly match either category)
     → treat as API CONTRACT (conservative, consistent with OVERLAP_CHECK philosophy)

EXAMPLES:
  - Domain creates "prisma/schema.prisma" → DATA MODEL → parallelize OK
  - Domain creates "src/types/User.ts" (interface, no methods) → DATA MODEL → parallelize OK
  - Domain creates "src/api/routers/auth.ts" → API CONTRACT → frontend must wait
  - Domain creates "src/services/AuthService.ts" with public methods → API CONTRACT → must wait
  - Domain creates only migration files → DATA MODEL → parallelize OK
```

**Error Handling:**
- If a file's content mixes both data definitions and API contract elements (e.g., a file that defines both a Prisma model and an API route): classify as API CONTRACT because the API contract portion creates a dependency that frontend needs.

**Edge Cases:**
- Domain step creates only a migration file (e.g., `prisma/migrations/20260227_add_users/migration.sql`) — DATA MODEL classification, frontend can parallelize
- Domain step creates a service class with only private methods (internal logic, no public API) — DATA MODEL classification because no external contract is exposed
- Domain step's file list contains only "Read" entries (no Create or Modify) — no files to classify, R1 trivially applies (no write dependencies)

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] R1 has explicit DATA MODEL and API CONTRACT definitions listing specific file types and patterns
- [ ] 5-step determination algorithm replaces subjective "only data models" phrasing
- [ ] Conservative approach explicitly stated: ambiguous classification → API CONTRACT
- [ ] At least 5 concrete examples provided with expected classification

**Effort:** S
**AID Role:** architect

---

### Step 11: plan_ref Matching Stopping Rule

**Objective:** Add a defined stopping rule, tie-breaking logic, and confidence check to the plan_ref keyword matching strategy in dispatch-protocol.md so that agents reliably extract the correct plan section.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines 220-248) — replace vague Strategy 3 (keyword matching) with concrete algorithm including stopping rule

**Architecture Context:**
The plan_ref matching in dispatch-protocol.md uses 4 strategies in order: (1) explicit task reference, (2) step number mapping, (3) keyword matching, (4) no-match fallback. Strategy 3 (lines 239-242) is the fallback when plans lack standardized headers. It says "first match" but does not define: first by document order? First by relevance score? What happens when 5 sections match? An agent may extract the wrong plan section, causing it to implement the wrong step. The fix adds a complete matching algorithm with defined behavior for every case.

**Implementation Detail:**
Replace Strategy 3 in lines 239-242 with:
```
Strategy 3 — KEYWORD MATCHING (fallback for legacy plans without ### Step {N} headers):

  1. EXTRACT keywords from the current step's objective:
     - Split objective into words
     - Remove stop words (the, a, an, is, are, to, for, with, from, in, on, at, by)
     - Remove common verbs (create, add, update, implement, fix, modify, change)
     - Remaining words are the keyword set

  2. SCORE each plan section:
     For each section in the plan (identified by ## or ### headers), in document order:
       a. Combine section header text + first paragraph (first 3 sentences) into search text
       b. Count how many keywords from step 1 appear in the search text (case-insensitive)
       c. Record: {section_index, section_header, match_count}

  3. STOPPING RULE — select the best section:
     a. IF exactly 1 section has the highest match_count → select that section
     b. IF multiple sections tie for highest match_count:
        → Select the section with the lowest section_index (earliest in document order)
        → Rationale: primary/canonical sections tend to appear before secondary references
     c. IF all sections have match_count == 0 → fall through to Strategy 4 (no match)

  4. CONFIDENCE CHECK:
     - IF selected section's match_count < 2:
       → Include warning in dispatch log: "Low-confidence plan_ref match
         (only {match_count} keyword). Injecting section '{section_header}'
         but agent should verify against full plan context."
     - IF match_count >= 2 → proceed without warning (sufficient confidence)

  NOTE: Strategy 3 is a last-resort for legacy plans. Plans written with the
  plan-writing skill use "### Step {N}: {Name}" headers that enable Strategy 2
  (step number mapping) directly — Strategy 3 should rarely be needed.
```

**Error Handling:**
- If the plan document is empty, unreadable, or contains no section headers: fall through to Strategy 4 (no match), which dispatches the agent without plan_ref injection. Include a warning in the dispatch log: "Plan document has no parseable sections — dispatching without plan context."

**Edge Cases:**
- All sections score equally (e.g., match_count=1 for 8 sections) — tie-breaker selects the first section in document order with a low-confidence warning (match_count < 2 triggers the warning)
- Step objective contains only common/stop words (e.g., "Update the configuration for the system") — after filtering, keyword set may be very small (just "configuration" and "system"), leading to low-confidence matches. The warning mechanism handles this correctly.
- Plan has no section headers at all (flat document with no `##` or `###` markers) — the entire document is treated as one section, which always matches. Inject the full document content with a warning: "Plan has no section headers — injecting full document."

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Strategy 3 has an explicit 4-step algorithm: extract keywords, score sections, stopping rule, confidence check
- [ ] Stopping rule handles 3 cases: unique max, tied max (document order tie-break), zero matches (fallthrough)
- [ ] Confidence warning triggers when match_count < 2
- [ ] Strategy 3 is documented as legacy fallback with note that new plans use Strategy 2

**Effort:** M
**AID Role:** architect

---

### Step 12: ID Format Standardization

**Objective:** Establish `E-{plan_id}-{phase}_{total}` as the sole EPIC ID format with a formal definition section in epic-state-machine.md, add validation regex, and remove old format references from generation code.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-state-machine.md` — add formal "ID Format" section near the top with canonical format, components, validation regex, and legacy format documentation
- Modify: `plugins/aid-orchestrator/skills/epic-queue.md` — replace any inline ID format examples with cross-reference to epic-state-machine.md
- Modify: `CLAUDE.md` (repository root) — verify any EPIC ID examples use the canonical format

**Architecture Context:**
The codebase contains multiple ID format styles in examples and documentation: timestamp-based (`E-20260224-0001`), timestamp+hash+slug (`E-20260217-a1b2-user-auth`), and plan-linked (`E-009-1_5`). The plan-linked format is the current standard produced by the planner, but it lacks a formal definition. Old format examples in documentation confuse agents during EPIC creation — they may generate IDs in the wrong format. This step establishes a single formal definition following the single-source-of-truth principle from the Architecture section.

**Implementation Detail:**
1. In epic-state-machine.md, add a new `## ID Format` section near the top of the file (after the overview/introduction, before the state definitions):
   ```
   ## ID Format

   CANONICAL FORMAT: E-{plan_id}-{phase}_{total}

   Components:
   - "E-" — literal prefix, all EPIC IDs start with this
   - {plan_id} — 3+ digit plan number without "P" prefix, zero-padded
     (e.g., "015" from P015, "001" from P001)
   - {phase} — phase number within the plan, 1-indexed integer
   - {total} — total number of phases/EPICs created from this plan

   Format examples:
   - E-015-1_2 — Plan P015, phase 1 of 2
   - E-009-1_5 — Plan P009, phase 1 of 5
   - E-001-1_1 — Plan P001, single phase (1 of 1)

   VALIDATION REGEX: ^E-\d{3,}-\d+_\d+$

   AD-HOC EPICs (without a source plan):
   - Use ad-hoc counter from counter.yaml
   - Format: E-{ad_hoc_counter}-1_1 (always single phase)
   - Example: E-001-1_1 (first ad-hoc EPIC)

   LEGACY FORMATS — do NOT generate, read-only for historical evidence:
   - E-YYYYMMDD-NNNN (timestamp + sequential, pre-v1.0)
   - E-YYYYMMDD-XXXX-slug (timestamp + hash + description, pre-v1.0)
   These formats may appear in old evidence directories (.aid-o/04-engine/evidence/).
   Do not rename, migrate, or delete them. New EPICs MUST use the canonical format.

   VALIDATION: Before writing any new EPIC ID to a file (queue, run file, evidence path),
   validate against the regex. If validation fails, reject with error:
   "Invalid EPIC ID format: {id}. Expected: E-{plan_id}-{phase}_{total} (e.g., E-015-1_2)"
   ```
2. In epic-queue.md, find any lines that show ID format examples (e.g., line 28 area) and replace with a cross-reference: "EPIC IDs follow the canonical format defined in `skills/epic-state-machine.md` > ID Format: `E-{plan_id}-{phase}_{total}`"
3. In CLAUDE.md (repository root), search for any EPIC ID examples. Replace old-format examples with canonical format examples.
4. Grep across all plugin files for `E-\d{8}` patterns that appear as ID templates or generation instructions (not historical evidence references). Replace with canonical format or add "(legacy, do not generate)" annotation.

**Error Handling:**
- If an agent generates an ID that doesn't match the validation regex: the EPIC creation logic should reject it immediately with the error message specified above. Do not proceed with an invalid ID — it would create inconsistent evidence directories and queue entries.

**Edge Cases:**
- Plan ID exceeds 3 digits (e.g., P1000) — regex uses `\d{3,}` (3 or more digits), so E-1000-1_1 is valid. Plan ID zero-padding adjusts automatically.
- Single-phase plan — format is E-015-1_1 (phase 1 of 1), not E-015 or E-015-1. The `_{total}` suffix is always present.
- Ad-hoc EPIC without a plan — uses the separate ad-hoc counter from counter.yaml, not the plan counter. Format remains E-{counter}-1_1.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] epic-state-machine.md has a formal "ID Format" section with canonical format, component descriptions, validation regex, ad-hoc format, and legacy format documentation
- [ ] epic-queue.md references epic-state-machine.md for ID format (not inline definitions)
- [ ] Grep for old timestamp-based ID patterns (`E-\d{8}`) as generation instructions (not legacy evidence references) returns 0 matches
- [ ] Validation regex `^E-\d{3,}-\d+_\d+$` matches all current canonical IDs (E-015-1_2, E-009-1_5, E-001-1_1)

**Effort:** M
**AID Role:** architect

---

### Step 13: CLAUDE.md Auto-Count Verification

**Objective:** Replace hardcoded skill and command counts in CLAUDE.md with the actual current counts and add a verification step to the release workflow that prevents counts from going stale.

**Files:**
- Modify: `CLAUDE.md` (repository root, lines 16-17) — update hardcoded "13 slash commands" and "21 skills" to actual current counts with verification comments
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` — add count verification check to the Release Sub-Phase

**Architecture Context:**
CLAUDE.md (line 16) says "13 slash commands" and (line 17) says "21 skills" but the actual file counts have diverged as new commands and skills were added across P010-P012 work. Hardcoded counts go stale on every release that adds or removes files. The fix has two parts: (1) update the counts now, and (2) add a release-time verification step that catches stale counts before they reach the repository.

**Implementation Detail:**
1. Count the actual files:
   - Commands: count `.md` files in `plugins/aid-orchestrator/commands/` directory
   - Skills: count `.md` files in `plugins/aid-orchestrator/skills/` directory
2. In CLAUDE.md lines 16-17, update to the actual counts:
   ```
   BEFORE:
     commands/                   # 13 slash commands
     skills/                     # 21 skills (orchestration, brainstorming, gates, etc.)

   AFTER:
     commands/                   # {actual_count} slash commands (verify: ls commands/*.md | wc -l)
     skills/                     # {actual_count} skills (verify: ls skills/*.md | wc -l)
   ```
   The `(verify: ...)` comment tells future editors how to check the count.
3. In `plugins/aid-orchestrator/skills/epic-orchestration.md`, find the Release Sub-Phase section and add a verification check:
   ```
   RELEASE CHECK — CLAUDE.md Counts:
   1. actual_commands = count of .md files in plugins/aid-orchestrator/commands/
   2. actual_skills = count of .md files in plugins/aid-orchestrator/skills/
   3. Read CLAUDE.md lines containing "slash commands" and "skills"
   4. Extract the numbers from those lines
   5. IF actual_commands != extracted command count OR actual_skills != extracted skill count:
      → Update CLAUDE.md with correct counts before proceeding with release commit
      → Log: "CLAUDE.md counts updated: commands {old}→{new}, skills {old}→{new}"
   6. This check is part of the release checklist — release commit MUST NOT have stale counts
   ```

**Error Handling:**
- If `commands/` or `skills/` directory does not exist at the expected path: release check fails with error: "Expected directory not found: {path}. Verify plugin directory structure."

**Edge Cases:**
- A skill file exists but contains only a deprecation notice (not yet deleted) — still counts toward the total because it is still a file in the directory. The count reflects files present, not active features.
- A file has a non-`.md` extension in the commands or skills directory (e.g., a `.yaml` helper) — not counted by the `*.md` glob, which is correct behavior

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] CLAUDE.md shows correct command and skill counts matching actual `ls *.md | wc -l` output
- [ ] CLAUDE.md count lines include verification comments showing the command to check
- [ ] epic-orchestration.md Release Sub-Phase includes a 6-step count verification check
- [ ] Verification check specifies exact glob pattern (`*.md`) and behavior on mismatch (auto-update before release commit)

**Effort:** S
**AID Role:** docs

---

### Step 14: Credit Exhaustion Regex Patterns

**Objective:** Replace the 5 hardcoded credit exhaustion error strings in gate-evaluation.md with regex patterns that match a broader range of Claude API error phrasings.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/gate-evaluation.md` (lines 28-34) — replace exact string matching with 6 case-insensitive regex patterns

**Architecture Context:**
Credit exhaustion detection in gate-evaluation.md uses 5 hardcoded exact strings: "You've exceeded your usage limit", "rate limit exceeded", "insufficient credits", "usage cap reached", "token limit exceeded for your plan". Real Claude API error messages vary in phrasing across API versions, and the exact wording can change without notice. This step replaces brittle exact matching with regex patterns that capture the semantic meaning of credit/rate/usage exhaustion messages.

**Implementation Detail:**
Replace lines 28-34 with:
```
CREDIT EXHAUSTION DETECTION:

Match agent output against these patterns (case-insensitive regex).
IF any pattern matches → credit_exhaustion = true

Pattern 1: /exceed(ed)?\s+(your\s+)?(usage|token|rate)\s*(limit|cap|quota)/i
  Matches: "exceeded your usage limit", "exceed token quota", "exceeded rate cap"

Pattern 2: /insufficient\s+(credits?|funds|balance|quota)/i
  Matches: "insufficient credits", "insufficient quota", "insufficient balance"

Pattern 3: /(rate|usage|token)\s*(limit|cap|quota)\s*(reached|exceeded|hit)/i
  Matches: "rate limit reached", "usage cap exceeded", "token quota hit"

Pattern 4: /too\s+many\s+(requests|tokens|api\s+calls)/i
  Matches: "too many requests", "too many tokens", "too many API calls"

Pattern 5: /(billing|payment|subscription)\s*(issue|problem|error|required)/i
  Matches: "billing issue", "payment required", "subscription error"

Pattern 6: /429|rate.?limit/i
  Matches: HTTP 429 status codes in error messages, "rate-limit", "rate_limit"

ON MATCH:
  1. Set credit_exhaustion = true
  2. Log: "Credit exhaustion detected: pattern {N} matched on text: '{matched_substring}'"
  3. Trigger existing CREDIT_EXHAUSTION_HANDLER
  4. Do NOT match the same output against remaining patterns (short-circuit after first match)
```

**Error Handling:**
- If a regex pattern is somehow malformed at runtime (should not happen with static patterns, but defensive coding): fall back to exact string matching with the original 5 strings. Log warning: "Regex pattern {N} failed to compile — falling back to exact string match."

**Edge Cases:**
- Agent output contains a credit error in a quoted context (e.g., the agent discusses rate limiting as part of its implementation work, mentioning "rate limit exceeded" as a string literal in code) — this is a false positive. Acceptable because the consequence (triggering the credit exhaustion handler, which pauses and checks) is safe and the handler can be dismissed if the pause was unnecessary.
- Multiple patterns match the same agent output — first match triggers the handler and short-circuits. Only one detection event is logged.
- Non-English error messages from the API — not handled by these English patterns. Add a trailing comment: "NOTE: These patterns cover English error messages. Non-English API responses may require additional patterns."

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] All 5 original hardcoded exact strings are removed (grep for each exact string returns 0 matches)
- [ ] 6 regex patterns defined, each with at least 2 example matches documented inline
- [ ] All patterns are case-insensitive (each pattern ends with `/i` flag)
- [ ] Detection logic short-circuits after first match (no duplicate triggers)

**Effort:** S
**AID Role:** architect

---

### Step 15: Queue Dependency Validation

**Objective:** Add a `depends_on` field to epic-queue.yaml entries and implement Kahn's algorithm for cycle detection, preventing circular dependencies that would deadlock the queue.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-queue.md` (lines ~19 schema definition, lines 60-78 add() function) — extend schema with depends_on field, add validation to add()

**Architecture Context:**
epic-queue.yaml currently has no dependency tracking between queued EPICs. When EPIC B depends on outputs from EPIC A (e.g., B modifies files that A creates), there is no way to express or enforce this ordering. If A fails or is paused, B starts anyway based on priority/FIFO and fails with confusing file-not-found errors. This step adds dependency declaration and validation using Kahn's algorithm (topological sort) for cycle detection, preventing deadlock scenarios like A→B→C→A.

**Implementation Detail:**
1. Extend the epic-queue.yaml entry schema (near line 19) to include depends_on:
   ```
   # Epic Queue Entry Schema:
   - epic_id: E-015-1_2              # canonical EPIC ID (see epic-state-machine.md > ID Format)
     path: .aid-o/02-epics/E-015-1_2.md
     priority: normal                 # low | normal | high | critical
     status: queued                   # queued | running | completed | failed | paused
     depends_on: []                   # list of epic_ids that must complete before this starts
     added_at: 2026-02-27T10:00:00Z
   ```
2. In the `add()` function (starting at line 60), insert a DEPENDENCY VALIDATION step after the existing parameter validation and before the YAML write:
   ```
   add(epic_path, priority, depends_on=[]):
     Step 0: CONFLICT DETECTION (from Step 1 of this plan)
     Step 1: existing parameter validation
     Step 2: DEPENDENCY VALIDATION
       2a. For each dep_id in depends_on:
           - Search the queue for an entry with epic_id == dep_id
           - Also accept dep_id with status "completed" (dependency pre-satisfied)
           - IF dep_id not found in queue AND not in completed entries:
             → REJECT: "Dependency '{dep_id}' not found in queue. Add it first or remove the dependency."
       2b. CYCLE DETECTION — Kahn's Algorithm:
           Build the dependency graph:
             - Nodes: all entries in the queue + the new entry being added
             - Edges: for each entry, draw edge from entry → each entry in its depends_on list
           Run Kahn's Algorithm:
             1. Compute in_degree[node] for every node (count of incoming edges)
             2. Initialize processing_queue with all nodes where in_degree == 0
             3. sorted_count = 0
             4. WHILE processing_queue is not empty:
                a. Remove node from processing_queue
                b. sorted_count += 1
                c. For each neighbor (node that this node points to via depends_on):
                   - Decrement in_degree[neighbor] by 1
                   - IF in_degree[neighbor] == 0: add neighbor to processing_queue
             5. IF sorted_count < total_node_count:
                → CYCLE DETECTED
                → Find cycle members: nodes with in_degree > 0 after algorithm completes
                → REJECT: "Circular dependency detected: {cycle_member_ids joined with ' → '}"
                → Do NOT add the entry to the queue
           IF no cycle: proceed to write
     Step 3: Write entry to epic-queue.yaml (existing logic)
   ```
3. Update the `/aid-epic-queue add` command interface to accept an optional `--depends-on` parameter:
   ```
   /aid-epic-queue add <epic_path> [--priority <level>] [--depends-on <epic_id_1>,<epic_id_2>]
   ```

**Error Handling:**
- Cycle detection reports the specific cycle path, not just "cycle detected": trace which nodes have non-zero in_degree after Kahn's algorithm completes. Report as: "Circular dependency detected: E-015-1_2 → E-015-2_2 → E-015-1_2"
- If depends_on references a completed EPIC (already finished and in completed status): log "Dependency {dep_id} already completed — pre-satisfied" and accept the entry. The dependency is trivially met.
- If depends_on references a failed EPIC: accept the entry but log a warning: "Dependency {dep_id} has status 'failed'. This EPIC will be BLOCKED until the dependency is resolved (re-run or removed)."

**Edge Cases:**
- EPIC depends on itself (self-loop: A→A) — detected as a cycle by Kahn's algorithm (in_degree never reaches 0 for A). Rejected with: "Circular dependency detected: {epic_id} → {epic_id}"
- Empty depends_on array — no validation needed, skip Step 2 entirely. EPIC can start based on priority alone.
- Long dependency chain (A→B→C→D→E, 5 levels deep) — Kahn's algorithm handles arbitrary chain lengths correctly. The algorithm is O(V+E) where V is number of queue entries and E is number of dependency edges — fast for typical queue sizes (<50 entries).
- Dependency on an EPIC that is currently running — accepted. The dependency will be satisfied when the running EPIC completes. If it fails, the dependent EPIC becomes BLOCKED.

**Dependencies:**
- Depends on: Step 1 — the `add()` function modified here uses the single-writer conflict detection added in Step 1 as Step 0
- Blocks: Step 16 — execution ordering (next() function) reads the depends_on field added here

**Acceptance Criteria:**
- [ ] epic-queue.yaml schema includes `depends_on: []` field in the entry documentation
- [ ] `add()` function validates that all referenced dependency IDs exist in the queue (or are completed)
- [ ] Cycle detection uses Kahn's algorithm with concrete pseudocode (not vague "check for cycles")
- [ ] Circular dependency rejection includes the specific cycle path (e.g., "E-015-1_2 → E-015-2_2 → E-015-1_2")
- [ ] Self-dependency (epic depends on itself) is detected and rejected

**Effort:** M
**AID Role:** architect

---

### Step 16: Queue Execution Ordering

**Objective:** Implement dependency-aware execution ordering in the queue's `next()` function, combining dependency eligibility checks with priority-based selection so EPICs with unsatisfied dependencies are never started prematurely.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-queue.md` (the `next()` function or equivalent EPIC selection logic) — add dependency eligibility check and READY/WAITING/BLOCKED status computation

**Architecture Context:**
Currently, the queue selects the next EPIC based on priority level and FIFO order (added_at timestamp). With the `depends_on` field added in Step 15, the queue must now verify that all of an EPIC's dependencies have status "completed" before it can be started. An EPIC with pending or failed dependencies must not be selected, even if it has higher priority than other EPICs. This step adds a dependency eligibility layer on top of the existing priority/FIFO selection.

**Implementation Detail:**
1. Add or modify the `next()` function in epic-queue.md:
   ```
   next():
     """Select the next EPIC to execute from the queue.
     Returns: epic_id to start, or null if no EPIC is ready to execute."""

     1. Read epic-queue.yaml
     2. Filter: keep only entries with status == "queued"
        (exclude: running, completed, failed, paused)

     3. For each queued entry, compute DEPENDENCY ELIGIBILITY:
        a. IF depends_on is empty → entry is READY (no dependencies to check)
        b. FOR each dep_id in depends_on:
           - Find dep_id in the full queue (any status)
           - IF dep_id.status == "completed" → this dependency is satisfied
           - IF dep_id.status == "failed" → this dependency is BLOCKED
           - IF dep_id.status in ["queued", "running", "paused"] → this dependency is PENDING
           - IF dep_id not found in queue → this dependency is BLOCKED
             (treat missing dependency as unresolvable)
        c. Entry eligibility:
           - READY: all dependencies are satisfied (all completed or depends_on is empty)
           - BLOCKED: any dependency has status "failed" or is missing from queue
           - WAITING: not BLOCKED, but some dependencies are still "queued"/"running"/"paused"

     4. From READY entries only, select the next EPIC:
        a. Sort by priority: critical > high > normal > low
        b. Within same priority level: sort by added_at ascending (FIFO — oldest first)
        c. Return the first entry after sorting

     5. IF no READY entries exist:
        a. Count BLOCKED and WAITING entries
        b. IF BLOCKED > 0:
           Log: "No ready EPICs. {BLOCKED} blocked by failed dependencies: {blocked_epic_ids}"
        c. IF WAITING > 0:
           Log: "No ready EPICs. {WAITING} waiting on pending dependencies: {waiting_epic_ids}"
        d. Return null
   ```
2. Update the queue status display (used by `/aid-epic-queue list` and `/aid-epic-status`) to show dependency eligibility:
   ```
   Queue Status:
     1. [READY]    E-015-1_2  (high)   — no dependencies
     2. [WAITING]  E-015-2_2  (normal) — waiting on: E-015-1_2 (running)
     3. [BLOCKED]  E-013-1_1  (normal) — blocked by failed: E-012-1_1
     4. [READY]    E-009-2_5  (low)    — dependencies satisfied
   ```
3. The display format includes the eligibility status, EPIC ID, priority, and dependency reason for non-READY entries.

**Error Handling:**
- If depends_on references an epic_id that is not in the queue at all (deleted, never added, or typo): treat as BLOCKED dependency. Log: "Dependency {dep_id} not found in queue — treating as unresolvable." The entry becomes BLOCKED until the dependency is added to the queue or removed from depends_on.
- If all entries in the queue are BLOCKED (deadlock from cascading failure): report the full blocked chain to PM in the log: "Queue deadlock: all {N} queued EPICs are blocked. Root cause: {failed_epic_ids}. Resolve these failures to unblock the queue."

**Edge Cases:**
- Queue has only one entry with no dependencies — `next()` returns it immediately (identical behavior to pre-dependency queue logic)
- All EPICs are completed — filter at step 2 produces empty list, `next()` returns null (empty queue, normal completion)
- EPIC's dependency is paused (not failed, not completed) — dependency status is PENDING, entry is WAITING (not BLOCKED). PM can resume the paused dependency to unblock.
- High-priority EPIC depends on low-priority EPIC — the low-priority EPIC executes first because it is READY and the high-priority one is WAITING. This is correct: dependencies override priority. Priority only matters among READY entries.

**Dependencies:**
- Depends on: Step 15 — requires the `depends_on` field in epic-queue.yaml schema and the validated dependency data written by `add()`

**Acceptance Criteria:**
- [ ] `next()` function computes READY/WAITING/BLOCKED eligibility for each queued entry before selection
- [ ] Only READY entries participate in priority/FIFO selection
- [ ] BLOCKED entries are identified with the specific failed dependency that blocks them
- [ ] Queue status display shows eligibility status with dependency information for non-READY entries
- [ ] When no READY entries exist, log message distinguishes between BLOCKED (failed deps) and WAITING (pending deps)

**Effort:** M
**AID Role:** architect

## Testing Strategy

Since AID is a Claude Code plugin composed of Markdown instruction files (no compiled runtime code), testing uses these verification approaches:

| Test Type | What It Verifies | Method |
|-----------|-----------------|--------|
| **YAML syntax validation** | Queue schema changes parse correctly | Parse epic-queue.yaml after Steps 1, 15, 16 to verify YAML validity |
| **Grep-based regression** | Fixed issues do not recur | After each EPIC, grep for forbidden patterns: `auto-mode-state-snapshot` (should be 0 after Step 2), `replace_tool_references` (should be 0 after Step 6), old ID generation patterns `E-\d{8}` in non-legacy contexts (should be 0 after Step 12), vague phrasing like "expand globs" (should be 0 after Step 8) |
| **Cross-reference check** | Single source of truth integrity | Verify no file defines its own ID format (only epic-state-machine.md defines it), no file has its own untrusted field list (only dispatch-protocol.md defines it) |
| **End-to-end smoke test** | Full pipeline operates correctly | After EPIC 1: run a small test EPIC (1 step, no dependencies) through the full pipeline. Verify: queue add uses single-writer constraint, dispatch wraps untrusted fields, gate evaluates correctly, EPIC completes without errors |
| **Idempotence test** | `/aid-setup` re-run is safe | After Step 7: run `/aid-setup` twice consecutively, diff project-profile.yaml after each run. Second run should show the section menu and produce no changes if PM selects cancel (0). |
| **Cycle detection test** | Queue rejects circular dependencies | After Step 15: attempt to add entries forming A→B→C→A dependency chain. Verify rejection message includes the cycle path. |

**Per-EPIC acceptance criteria:**
- EPIC 1 completion: E2E smoke test passes, grep for all 12 fixed patterns returns 0 findings
- EPIC 2 completion: CLAUDE.md counts match actual file counts, cycle detection test rejects circular dependency with specific path

## Constraints

- **No runtime code** — all changes are Markdown instruction files parsed by Claude Code. No TypeScript compilation, no test suites to run.
- **Backward compatible with evidence** — existing evidence directories with old ID formats (E-20260224-0001) are not renamed, migrated, or deleted. Old formats are documented as read-only legacy.
- **No new external dependencies** — no new MCP servers, npm packages, Docker containers, or API integrations required.
- **P014 independence** — this plan does not modify permission-related files or address controller bugs IMP-043-046. P015 can execute before, after, or concurrently with P014 without conflicts.
- **Single-writer maintained** — all queue modifications in Steps 1, 15, and 16 preserve the single-writer constraint established in Step 1. No step introduces a second concurrent writer to epic-queue.yaml.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Single-writer constraint bypassed by future feature adding a second queue writer | Low | Queue file corruption from race condition | Write Ownership section in epic-queue.md with explicit rule + conflict detection validates caller |
| Resume filename fix untested in production (PM escalation is ultra-rare) | Medium | Bug persists in rarely-exercised edge case | Grep regression test catches filename reversion + edge case documented in code comments |
| CLAUDE.md counts go stale again on next release | High | Misleading contributor documentation | Release Sub-Phase verification check (Step 13) auto-updates counts before release commit |
| ID format migration breaks historical evidence trail | Low | Old evidence directories become inaccessible | No migration performed — old evidence stays untouched, only new generation uses canonical format |
| Queue dependency cycle detection adds overhead to add() | Low | Slower queue operations | Kahn's algorithm is O(V+E), queue size typically <50 entries — overhead is negligible |
| EPIC 1 scope (12 steps) is too large for one EPIC run | Medium | Context exhaustion or timeout during execution | 4 parallel groups reduce effective sequential dispatches to ~7. Gate checkpoint after step 6 provides recovery point. |

## Success Criteria

- Queue operations during FIRST AID auto-mode have zero race conditions (single-writer constraint prevents concurrent writes)
- Resume flow correctly recovers partial work after PM escalation (aligned filenames verified by grep returning 0 matches for old filename)
- First EPIC in any project receives DEFAULT_BASELINE quality checks (not silently skipped)
- Intermediate EPICs receive INTERMEDIATE_GUARDRAIL validation (not unconditionally auto-approved)
- All algorithms in planner.md and dispatch-protocol.md have concrete pseudocode with defined inputs, outputs, stopping conditions, and edge case behavior
- EPIC ID format is defined in exactly one location (epic-state-machine.md > ID Format) with validation regex
- Untrusted content tagging is consistent — canonical list in dispatch-protocol.md matches both templates in aid-run-epic.md
- CLAUDE.md counts match reality and are verified automatically on every release
- Grep for all 12 fixed patterns (across both EPICs) returns 0 findings

## Next Steps

- [ ] Create EPICs from this plan: `/aid-plan-epic .aid-o/01-plans/P015-quality-and-robustness.md`
- [ ] After P015 EPICs complete: proceed to P009 revision (GUI workflow phases 2-3)
- [ ] After P009 revision: proceed to P013 revision (flow optimization with realistic targets)
- [ ] After all 3 tasks from INTERIM-audit-findings.md complete: delete `.aid-o/01-plans/INTERIM-audit-findings.md`

---

**Last Updated:** 2026-02-27
