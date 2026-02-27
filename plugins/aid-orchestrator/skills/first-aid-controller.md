# FIRST AID Controller — Autonomous Execution and DONE State

**Skill:** first-aid-controller
**Dependencies:** epic-state-machine, gate-evaluation, dispatch-protocol, epic-orchestration (parent module)

---

## Overview

This module defines FIRST AID mode (autonomous execution) and the DONE state. FIRST AID mode allows the Controller to execute an EPIC queue autonomously without stopping for PM approval at each decision point. PM approves the queue once; the Controller runs all EPICs end-to-end with agent-driven quality checks replacing manual approval gates.

This module also contains the complete DONE state logic, which is tightly coupled with auto-mode behavior (queue transitions, completion summaries). Release logic (version bump, git tag, GitHub release) is delegated to `skills/auto-done-state.md` Section 2.

For the FSM definition and state diagram, **see:** `skills/epic-state-machine.md`
For agent dispatch protocol, **see:** `skills/dispatch-protocol.md`
For quality gate evaluation (manual-mode), **see:** `skills/gate-evaluation.md`

---

## Mode Storage

The current orchestration mode is stored in `.aid-o/04-engine/auto-mode-state.yaml`:

```yaml
mode: manual        # manual | auto | paused
started_at: ~       # ISO 8601 timestamp (set when mode becomes auto)
paused_at: ~        # ISO 8601 timestamp (set when mode becomes paused)
active_epic: ~      # epic_id currently executing
escalation_count: 0 # incremented on every escalation event
queue_position: ~   # index of currently executing EPIC in the queue
progress_snapshot: ~ # path to snapshot file saved before pausing
```

**Mode values:**
- `manual` — default; all PM decision points behave as documented (existing behavior)
- `auto` — autonomous execution; PM decision points use auto-mode logic (see below)
- `paused` — auto-mode was interrupted by an escalation; PM must resolve before resuming

## How the Controller Reads Mode

At every PM decision point (PLAN_REVIEW, PHASE_CHECK, PM_APPROVAL, DONE), the Controller:

1. Reads `.aid-o/04-engine/auto-mode-state.yaml`
2. Checks `mode` field
3. Routes to the appropriate branch (IF mode == auto / ELSE manual)
4. If file does not exist or is unreadable: defaults to `manual` mode (fail-safe)

## Starting and Stopping FIRST AID Mode

- **Start:** `/aid-first-aid` — PM confirms the EPIC queue; Controller verifies Steroids 💉 preset, sets `mode: auto`, and begins autonomous execution. See `commands/aid-first-aid.md`.
- **Stop:** `/aid-stop` — immediately sets `mode: manual` (or `paused` if mid-EPIC); Controller finishes the current step cleanly and then waits for PM. See `commands/aid-stop.md`.

## Escalation in Auto-Mode

When auto-mode cannot proceed autonomously (validation failures, guardrail violations, repeated fix cycles), it escalates to the PM and pauses. The PM receives extended options including `continue-manual` to switch back to manual mode at the natural pause point. See `skills/auto-escalation.md` for the full escalation protocol (16 trigger conditions, severity classification, escalation budget tracking).

---

## PLAN_REVIEW — Auto-Mode Behavior

```
IF mode == auto:
  1. Run plan validation:
     a. Schema validation: Plan JSON must conform to plan.schema.json
     b. Completeness: all required fields present (role, objective, inputs, outputs, acceptance)
     c. Dependency graph: no cycles, all dependencies reference valid step IDs
     d. Run file quality: passes all checks (objective 3+ sentences, scope IN/OUT lists,
        phase subsections complete, dependencies table present, one or more gates listed)
  2. IF all validations pass:
     → Auto-approve (GO)
     → Save pm_plan_approval.json with:
        { "approver": "auto-mode", "mode": "auto", "timestamp": "{ISO 8601}",
          "validation": { "schema": "pass", "completeness": "pass",
                          "dependency_graph": "pass", "run_file_quality": "pass" } }
     → Log: {"state": "PLAN_REVIEW", "action": "auto_approved", "mode": "auto"}
     → Transition to EXECUTING
  3. IF any validation fails:
     → ESCALATION (mandatory PM touchpoint — auto-mode cannot proceed with an invalid plan)
     → Escalation payload includes: which validation failed, specific errors, plan summary

ELSE (mode == manual):
  {existing manual behavior: send plan to PM via Slack/chat, wait for GO/REVISE/ABORT}
```

---

## PHASE_CHECK — Auto-Mode Behavior

```
IF mode == auto:
  1. Run the same auto-decision logic as manual mode (unchanged — decisions are already automated)
  2. IF review needed (acceptance_unclear AND review_required_when matches):
     → Dispatch code-reviewer agent (same as manual mode)
     → Reviewer APPROVED → NEXT_PHASE
     → Reviewer REJECTED → re-dispatch original agent with feedback
     → Max review_fix_cycles reached (default 2) → attempt ONE "fresh approach" cycle:
        a. Re-dispatch the original agent with instruction:
           "Previous approach exhausted fix cycles. Take a completely different approach
            to satisfy the acceptance criteria."
        b. Dispatch code-reviewer on fresh-approach output
        c. Reviewer APPROVED → NEXT_PHASE
        d. Reviewer REJECTED → ESCALATION (mandatory PM touchpoint — fresh approach failed)
  3. All other paths (scope violation, no output, parallel conflict, CRITICAL findings):
     → Identical to manual mode auto-decision logic above

ELSE (mode == manual):
  {existing manual behavior: max_review_fix_cycles exhausted → ESCALATION without fresh-approach cycle}
```

---

## ESCALATION — Auto-Mode Behavior

```
IF mode == auto:
  1. Pause auto-mode immediately:
     a. Set mode: paused in auto-mode-state.yaml
     b. Set paused_at: {ISO 8601 timestamp}
  2. Save progress snapshot:
     a. Write snapshot file: .aid-o/04-engine/evidence/{epic_id}/{run_id}/interrupted_step_context.json
        {
          "epic_id": "{epic_id}",
          "run_id": "{run_id}",
          "interrupted_step": "{step_id}",
          "interrupted_at": "{ISO 8601}",
          "step_status_before": "running",
          "agent_partial_output": "{first 500 chars}",
          "git_stash_ref": "{stash ref}",
          "plan_progress_snapshot": "{plan_progress.json state}",
          "escalation_trigger": "{reason}"
        }
     b. Set auto-mode-state.yaml → progress_snapshot: {snapshot_path}
  3. Increment escalation counter:
     → escalation_count += 1 in auto-mode-state.yaml
  4. Notify PM with extended options (beyond standard fix/skip/abort/discussion):
     ```
     AUTO-MODE ESCALATION — {epic_id}
     ====================================
     Trigger: {trigger reason}
     Details: {failure details}
     Escalation count: {N}

     Options:
       A. Fix — provide guidance, auto-mode resumes after fix
       B. Skip — skip this step/gate, auto-mode continues
       C. Abort — stop execution entirely
       D. Continue manual — switch to manual mode at this point
          (auto-mode deactivated; all subsequent decisions require PM input)
       E. Discuss — ask questions (re-presents options after answer)
     ```
  5. Wait for PM response (same timeout handling as manual mode)
  6. Execute PM's choice:
     - Fix → apply fix, set mode: auto, resume from paused state
     - Skip → mark skipped, set mode: auto, continue
     - Abort → transition to DONE (status: aborted), set mode: manual
     - Continue manual → set mode: manual in auto-mode-state.yaml; continue from
       this natural pause point in manual mode (PM makes all subsequent decisions)
     - Discuss → incorporate PM text, re-present extended options

  See `skills/auto-escalation.md` for the full protocol:
  16 trigger conditions, severity classification, and escalation budget rules.

ELSE (mode == manual):
  {existing manual behavior: fix/skip/abort/discussion options as documented in skills/gate-evaluation.md}
```

---

## CURATOR_RESOLVE — Auto-Mode Behavior

```
IF mode == auto:
  1. Dispatch Curator + LE in parallel (same as manual — see skills/gate-evaluation.md sub-steps 1-2)
  2. Auto-evaluate proposals via 3-tier algorithm (same as manual — see skills/gate-evaluation.md sub-step 3)
  3. For each APPROVED proposal:
     - IF effort == S: dispatch fix agent inline (same as manual — see skills/gate-evaluation.md sub-step 5)
       - If fix fails: auto-defer the proposal
         (status: deferred, reason: "fix attempt failed in auto-mode")
         Continue with remaining proposals (non-blocking).
     - IF effort == M or L: auto-defer to backlog (do NOT dispatch fix agent)
       - Set urgency: HIGH for effort:M, MEDIUM for effort:L
       - Update backlog.md: status → "deferred", urgency → "{urgency}",
         reason → "auto-mode guardrail: effort:{effort} deferred to backlog"
       - Log:
         {"state": "CURATOR_RESOLVE", "action": "auto_defer",
          "proposal": "IMP-{NNN}", "effort": "{effort}", "urgency": "{urgency}",
          "reason": "auto-mode guardrail: effort:{effort} deferred to backlog"}
  4. Process LE output (same as manual — see skills/gate-evaluation.md sub-step 4)
  5. Compile curator_resolve_report.json (same format as manual — see skills/gate-evaluation.md sub-step 6)
     - Deferred entries include auto-mode reason when applicable
  6. Transition → PM_APPROVAL (auto-mode will auto-approve at PM_APPROVAL)

ELSE (mode == manual):
  {existing behavior: all approved proposals get fix agents regardless of effort size}
```

> **Rationale:** In auto-mode, only effort:S proposals are safe for inline fixes
> because they are small, low-risk, and fast. Effort:M/L proposals require human
> judgment on scope and timing, so they are deferred to the backlog with urgency
> tags for the PM to triage later. If even an effort:S fix fails, the proposal is
> silently deferred rather than escalating — this keeps auto-mode flowing.

---

## PM_APPROVAL — Auto-Mode Behavior

```
IF mode == auto:
  1. Determine EPIC position:
     → Call DETECT_EPIC_POSITION(epic_id) from skills/auto-done-state.md
     → Returns: "standalone", "last", or "intermediate"
     (Plan-based detection — see auto-done-state.md Section 2.4 for algorithm)

  2. IF position == "intermediate":
     → Auto-approve immediately (no guardrails required for intermediate EPICs)
     → Save pm_decision.json:
        { "approver": "auto-mode", "decision": "approve",
          "epic_position": "intermediate ({N}/{total})",
          "mode": "auto", "timestamp": "{ISO 8601}" }
     → Log: {"state": "PM_APPROVAL", "action": "auto_approved",
              "reason": "intermediate_epic", "position": "{N}/{total}"}
     → Transition to DONE

  3. IF position == "last" OR position == "standalone":
     → Run auto-mode guardrails:
        a. Gates passed: gates_report.json overall == "pass"                     required
        b. No unresolved CRITICAL issues: check backlog.md for open CRITICAL items required
        c. Escalation budget: escalation_count < 3 (from auto-mode-state.yaml)  required
        d. Auditor trend: Compare current audit overall score vs PRIOR EPIC      required
           (allows up to 5-point dip; beyond that indicates quality regression)
           - Read from MOST RECENT PRIOR EPIC:
             evidence/{prev_epic_id}/{prev_run_id}/audit-report.md
           - Extract prior overall score
           - IF no prior audit report exists:
             → Apply DEFAULT_BASELINE check instead of skipping:
               DEFAULT_BASELINE:
                 1. Read current EPIC's audit-report.md (from Auditor in POST-PROCESSING)
                 2. Extract overall score
                 3. IF overall_score >= 50: PASS (acceptable baseline for first EPIC)
                    Log: "No prior audit — DEFAULT_BASELINE applied: score {score}/100 >= 50 threshold"
                 4. IF overall_score < 50: FAIL — escalate E11
                    "First EPIC audit score ({score}/100) below minimum baseline (50).
                     No prior audit to compare against. Review quality before continuing."
               Rationale: First EPIC has no history to compare. A score of 50+ indicates
               fundamentally sound work. Below 50 suggests systemic issues requiring PM review.
           - IF prior exists: current_score >= prior_score - 5
     → IF all guardrails pass:
        → Auto-approve with guardrails
        → Save pm_decision.json:
           { "approver": "auto-mode", "decision": "approve",
             "epic_position": "last ({N}/{total})",
             "guardrails": { "gates": "pass", "no_critical": "pass",
                             "escalation_budget": "pass", "auditor_trend": "pass" },
             "mode": "auto", "timestamp": "{ISO 8601}" }
        → Log: {"state": "PM_APPROVAL", "action": "auto_approved",
                 "reason": "last_epic_guardrails_passed"}
        → Transition to DONE
     → IF any guardrail fails:
        → ESCALATION with guardrail failure details
           (mandatory PM touchpoint — auto-mode cannot approve final EPIC with guardrail failures)

  NOTE: Curator rule teaching (PM teaches "always approve {pattern}") is NOT available
  in auto-mode. Rule teaching requires deliberate PM interaction and is suppressed
  during autonomous execution. Existing auto-rules still apply via CURATOR_RESOLVE.

ELSE (mode == manual):
  {existing manual behavior: send final summary to PM via Slack/chat, wait for
   APPROVE/override/rule-teach/REJECT/REVISE/timeout — see skills/gate-evaluation.md}
```

---

## DONE State

> **NOTE:** Curator dispatch, Lessons-Extractor dispatch, and lessons/command-history
> file writes have been moved to the CURATOR_RESOLVE state (see `skills/gate-evaluation.md`).
> They now run BEFORE PM_APPROVAL, not after it. The Auditor remains in DONE because it
> audits the final state including any Curator fixes.

**Actions:**
1. If approved:
   a. **Run File Status Update** (BEFORE archive — MANDATORY):
      1. Read the active run file from `.aid-o/04-engine/runs/S-*.md`
      2. Update YAML frontmatter:
         - `status: completed`
         - `completed: {ISO 8601 timestamp}`
      3. Update the `Completion:` line in the body to `100%`
      4. Update the last phase status to `done`
      5. Write the updated run file
      6. THEN proceed with archive (copy to archive/ directory)

      The archived copy MUST reflect the completed status. Never archive a run
      that still shows `status: active`.

   b. **RELEASE_SUB_PHASE** (MANDATORY — between gate completion and branch merge):

      Log: `{"state": "DONE", "action": "release_sub_phase_start", "epic_id": "{id}"}`

      1. Read mode: manual or first_aid (from auto-mode-state.yaml if it exists, otherwise "manual")
      2. Call `DETECT_EPIC_POSITION(epic_id)` from `skills/auto-done-state.md` → position
      3. Branch on position:

         IF position == "standalone" OR position == "last":
           → Execute full release protocol (`auto-done-state.md` Sections 2.6-2.10):
             a. Detect version mismatch (Section 2.2)
             b. Determine bump type (patch/minor/major) from EPIC scope
             c. Update all version files (`release-policy.yaml` `version_files[]`)
             d. Finalize CHANGELOG (move `[Unreleased]` → `[vX.Y.Z]`)
             e. Commit version bump
             f. Create git tag
             g. IF mode == "first_aid": create GitHub release (auto)
                IF mode == "manual": ask PM whether to create GitHub release
           → Log: `{"state": "DONE", "action": "release_sub_phase_complete",
                   "epic_id": "{id}", "version": "vX.Y.Z", "result": "pass"}`

         IF position == "intermediate":
           → IF mode == "first_aid":
               Auto-defer per `release-policy.yaml` → `first_aid.intermediate_action`
               Log: `{"state": "DONE", "action": "release_sub_phase_deferred",
                       "epic_id": "{id}", "reason": "intermediate_epic", "result": "deferred"}`
             IF mode == "manual":
               Ask PM: "This is an intermediate EPIC ({completed}/{total} for plan {plan_id}). Release now or defer to plan's last EPIC?"
               Log PM's decision

      4. IF any error in release sub-phase:
         → Log: `{"state": "DONE", "action": "release_sub_phase_error",
                 "epic_id": "{id}", "error": "{message}", "result": "failed"}`
         → Set `release_status = "failed"` in final_report
         → Do NOT block merge (release is important but not merge-blocking)

   c. **Run Branch Merge** (if git available):
      If a run branch was created (check plan_progress.json -> branch):
      1. Verify all gates passed and PM approved
      2. Switch to base branch: `git checkout {default_branch}`
      3. Merge run branch: `git merge epic/{epic_id} --no-ff -m "feat: complete EPIC {epic_id}"`
      4. If merge conflict: escalate to PM (do NOT auto-resolve)
      5. Delete run branch: `git branch -d epic/{epic_id}`
      6. Log to stage_log

      If no run branch (git not available): skip this step.

   d. Update EPIC file status to "Completed"
   e. Archive run file to `.aid-o/04-engine/runs/archive/`
   f. Update `.aid-o/04-engine/memory/active-work.md`
2. Generate final report
3. **POST-PROCESSING (Auditor):**

   a. Dispatch **Auditor agent** (`agents/auditor.md`) — runs 5 audit types
      (code, security, docs, frontend, database), scores project health,
      tracks trend vs previous audit. Report -> `evidence/{epic_id}/audit-report.md`
   b. Auditor summary -> PM via Slack Type F (Audit Summary, no reply)
      - If critical findings match `escalation_triggers` -> additional Type A (Escalation)

4. **Qdrant Project Tagging** (MANDATORY for all Qdrant writes):
   Every `qdrant-store` call in the DONE state MUST include `project_name` in metadata:

   ```json
   {
     "collection_name": "aid-orchestration-log",
     "data": "{lesson_text}",
     "metadata": {
       "project_name": "{from project-profile.yaml -> project_name}",
       "epic_id": "{epic_id}",
       "step_id": "{step_id}",
       "type": "lesson|command|decision|pattern",
       "category": "{category}",
       "timestamp": "{ISO 8601}"
     }
   }
   ```

   If Qdrant is unavailable: skip gracefully (non-blocking), log warning.

5. **EPIC-Level Metrics to Qdrant (DONE state)**

   Aggregate all step metrics into an EPIC summary metric:

   ```json
   {
     "collection_name": "aid-memory",
     "data": "EPIC {epic_id} completed: {step_count} steps, {total_duration}s total, {gate_retries} gate retries. Slowest: {slowest_step} ({slowest_duration}s). Most errors: {most_errors_step}.",
     "metadata": {
       "type": "metric",
       "metric_kind": "epic_summary",
       "project_name": "{project_name}",
       "epic_id": "{epic_id}",
       "total_duration_seconds": "{sum of all step durations}",
       "step_count": "{count}",
       "gate_retries": "{count}",
       "slowest_step": "{step_id}",
       "most_errors_step": "{step_id}",
       "timestamp": "{ISO 8601}"
     }
   }
   ```

   Also store gate results and token consumption profiles as metrics (per-step and EPIC-level).

   The Controller estimates execution tokens from:
   - `duration_seconds x ops_per_minute_estimate x avg_tokens_per_op`
   - Where ops_per_minute ~ 3, avg_tokens_per_op ~ 2600 (from BMK-001 baseline)

   If Qdrant unavailable: skip metric writes gracefully, log warning.

6. **Archive Logic** (runs AFTER all file writes, BEFORE final commit):

   1. **Archive run:**
      - Ensure archive directory: `mkdir -p .aid-o/04-engine/runs/archive/`
      - Update frontmatter: `status: completed`, `completed: {timestamp}`
      - Move to `.aid-o/04-engine/runs/archive/{filename}`

   2. **Update EPIC counter:**
      - Increment `runs_completed += 1` in EPIC frontmatter

   3. **Archive EPIC (conditional):**
      - IF `runs_completed == runs_total`:
        - Set `status: completed`, `completed: {timestamp}`
        - Move to `.aid-o/02-epics/archive/{filename}`
      - ELSE: EPIC stays active

      NOTE: Evidence directory is NOT moved.

   4. **Update Plan counter (informative only):**
      - IF EPIC archived AND `plan_ref` exists:
        - Increment `epics_completed += 1` in plan frontmatter
        - Log: "Plan {plan_id}: {epics_completed}/{epics_total} EPICs done"
        - NOTE: Plan archival is handled exclusively by QUEUE_ADVANCE -- do NOT archive here.
          The frontmatter counter is informative (for human readers), not a decision input.

   5. **Stage log**
   6. **Final commit:** `git add -A && git commit -m "done({epic_id}): completed, archived [list]"`

   Archive = MOVE (not copy). Active directories contain only pending work.

7. **Example EPIC Extraction (optional — when Qdrant enabled)**

   Call `extract_example_epic()` from `skills/knowledge-acquisition.md`.
   Error handling: if extraction fails, log warning and continue (non-blocking).

8. **Completion Summary and Next Steps** (presented to PM — LAST before queue check)

   ```
   EPIC Complete: {epic_id}
   ====================================

   Summary:
     - Steps completed: {completed_count}/{total_count}
     - Gates passed: {passed_gates}/{total_gates} ({retry_count} retries)
     - Duration: {total_duration}
     - Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/

   Key outputs:
     {list of main artifacts created -- files, endpoints, components}

   What's next?
     1. Review the code -- run /aid-review or examine the changes manually
     2. Start new work -- run /aid-brainstorm to explore a new idea
     3. Continue building -- run /aid-plan-epic with a new EPIC
     4. Check quality -- run /aid-audit for a project health assessment
     5. Analyze performance -- run /aid-analytics to see bottlenecks and optimization tips
     6. Archive -- the run has been archived to runs/archive/

   Lessons learned: processed in CURATOR_RESOLVE (see curator_resolve_report.json)
   Backlog proposals: {proposal_count} new entries (review with /aid-backlog)
   Example pattern: {archetype} saved to knowledge base  ← only if extraction stored
   ```

   The summary MUST include concrete artifact names (not generic descriptions).

9. Send Status Update (Type G): `:checkered_flag: EPIC completed — merged to main`
10. **EPIC QUEUE CHECK** (per `skills/epic-queue.md`):
   a. Read `.aid-o/04-engine/epic-queue.yaml`
   b. IF queue is not paused AND next EPIC exists (status: "queued"):
      - Mark current EPIC as "completed" in queue
      - Mark next EPIC as "running"
      - Transition: DONE -> IDLE (with next EPIC)
   c. IF queue is paused OR empty:
      - Mark current EPIC as "completed" in queue (if in queue)
      - Remain in terminal DONE state

11. **Final Stage Log Entry** (MUST be the LAST action in DONE state):
   ```json
   {"state": "DONE", "timestamp": "{ISO 8601}", "result": "success", "epic_id": "{epic_id}", "run_id": "{run_id}", "summary": "EPIC completed successfully. {step_count} steps, {gate_count} gates, {retry_count} retries."}
   ```

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/final_report.md`:
```markdown
# EPIC Run Report: {epic_id}

## Summary
- Status: {completed/aborted}
- Duration: {start} → {end}
- Steps: {completed}/{total}
- Gates: {pass_count}/{total_count}
- Retries: {count}
- Escalations: {count}
- LLM Cost: ${estimated}

## Steps
| # | Role | Status | Duration | Branch |
|---|------|--------|----------|--------|
| 1 | architect | done | ... | epic/{epic_id}/step_1_architect |

## Gate Results
| Gate | Status | Attempts |
|------|--------|----------|
| tests_pass | pass | 1 |

## Evidence
All artifacts stored in: .aid-o/04-engine/evidence/{epic_id}/{run_id}/
```

### Enriched Report Generation from Qdrant

When generating the `final_report.md`, the orchestrator enriches it with data from Qdrant if available:

```
1. Check Qdrant MCP availability
2. IF Qdrant available:
   a. Query collection "aid-orchestration-log" for all events matching this epic_id
   b. Extract per-step timing, retry counts, strategy usage
   c. Include in final_report.md
3. IF Qdrant unavailable:
   a. Fall back to stage_log.jsonl data
   b. Note in report: "Timing data from stage_log.jsonl (Qdrant unavailable)"
```

---

## DONE — Auto-Mode Behavior

```
IF mode == auto:

  RELEASE (version bump decision):
    → See skills/auto-done-state.md Section 2 for the complete release protocol.
    → All release decisions (bump, defer, tag, GitHub release) are deterministic
      in auto-mode — no PM interaction.

  COMPLETION SUMMARY (action 8 above):
    → Still presented (non-blocking Slack Type G or chat message)
    → "What's next?" section is suppressed or condensed — no interactive prompts
    → Aggregate EPIC summary is written to auto-mode-state.yaml:
       { "last_completed_epic": "{epic_id}", "completed_at": "{ISO 8601}",
         "steps": {N}, "gates": {N}, "retries": {N}, "escalations": {N} }

  QUEUE TRANSITION (action 10 above):
    → IF next EPIC exists in epic-queue.yaml (status: "queued"):
       - Auto-load next EPIC (same as existing queue check behavior)
       - Update auto-mode-state.yaml: active_epic: {next_epic_id}
       - Increment queue_position by 1
       - DONE -> IDLE transition happens automatically (no PM confirmation needed)
    → IF queue is empty:
       - Set mode: manual in auto-mode-state.yaml (auto-mode ends with the queue)
       - Send final summary to PM: "FIRST AID complete — queue exhausted. {N} EPICs completed."
       - Remain in terminal DONE state

  See `skills/auto-done-state.md` for the full auto-mode DONE state protocol
  (including cross-EPIC summary aggregation).

ELSE (mode == manual):
  {existing behavior: completion summary presented interactively, queue check proceeds,
   PM chooses next action from the "What's next?" options}
```

---

**Last Updated:** 2026-02-27
