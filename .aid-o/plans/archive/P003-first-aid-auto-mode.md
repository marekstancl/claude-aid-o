---
id: P003
type: plan
status: done
created: 2026-02-23
author: PM + AID
depends_on: P002
---

# Plan: FIRST AID — Autonomous Orchestration Mode

## Context

AID Orchestrator currently requires extensive PM interaction during execution: approving
each step transition, handling PHASE_CHECK decisions, confirming DONE state actions, and
manually chaining EPICs by re-running `/aid-plan-epic` + `/aid-run-epic` for each one.

For a queue of 3 EPICs with 8 steps each, PM must click through ~30+ approval points.
This defeats the purpose of orchestration — PM becomes a bottleneck instead of a supervisor.

The DONE state already has curator/lessons-learned processing that routes findings to agents
for auto-fix before PM approval. This pattern proves that agent-driven quality checks can
replace manual PM intervention.

FIRST AID (Full Intelligent Run with Supervised Takeoff — AID) is an autonomous execution
mode where PM approves the queue once, AID executes all EPICs with agent-driven quality
checks, and PM receives a summary report at the end. PM can intervene at any time via
stop command or GUI.

## Goal

Implement FIRST AID mode: PM approves an EPIC queue, AID executes autonomously with
agent-driven guardrails, permissions are elevated for the duration and restored after
completion, and PM can monitor/stop at any time.

## Scope

**In scope:**
- New `/aid-first-aid` command (or `/aid-autopilot`) to start autonomous mode
- `/aid-stop` command to disengage at any time
- EPIC queue processing: sequential execution of queued EPICs without PM intervention
- Agent-driven quality checks replacing PM approval points (code-reviewer, QA, security)
- Escalation protocol: when agents cannot resolve an issue, escalate to PM
- Permission sandwich: elevate permissions on start, restore on completion
- Permission learning: when PM grants a new permission during auto mode, persist it
- FIRST AID banner/animation on start
- DONE state adaptation: automatic release decision (last EPIC = bump, intermediate = defer)
- Integration with existing EPIC queue (`epic-queue.yaml`)

**Out of scope:**
- GUI integration (GUI plan handles monitoring/stop UI separately)
- Fast mode (deferred — not part of this plan)
- Parallel EPIC execution (EPICs run sequentially; parallel steps within EPIC already supported)
- New agent creation (use existing agents: code-reviewer, QA, security, auditor)
- Slack/notification integration

## Approach

**Chosen: New command + state machine mode flag**

Add a `mode: auto | manual` flag to the orchestration state. When `mode: auto`, the
Controller skips PM approval points and delegates to agent checks instead. All existing
state machine logic remains — only the decision points change behavior.

**Rejected alternatives:**
- *Separate auto-orchestration skill* — Would duplicate the entire state machine logic.
  The difference between auto and manual is only at decision points, not in the flow itself.
- *Wrapper script that auto-approves* — Fragile, doesn't handle escalation, doesn't
  adapt agent behavior, and can't do permission management.
- *Always-on autonomy (remove manual mode)* — PM needs manual mode for learning, debugging,
  and sensitive projects. Both modes must coexist.

## Decision

New command `/aid-first-aid` that sets mode flag, manages permissions, processes the queue,
and provides escalation protocol. Manual mode remains the default.

## High-Level Steps

1. **Design FIRST AID state flow** — Map every PM decision point in the current state machine
   and define the auto-mode equivalent:
   - PLANNING → EXECUTING transition: auto (no PM confirm needed)
   - Step completion PHASE_CHECK: agent-driven (code-reviewer validates, QA checks)
   - GATE_CHECK: auto (gates are already automated)
   - BLOCKED/FAILED: escalation to PM (this is the only mandatory PM touchpoint)
   - PM_APPROVAL: auto for intermediate EPICs, auto with guardrails for last EPIC
   - DONE release sub-phase: auto (last EPIC = mandatory bump, intermediate = defer)
   - DONE → next EPIC in queue: auto
   Define escalation triggers: what constitutes a problem agents cannot resolve.
   Effort: M

2. **Implement permission sandwich** — Design the permission elevation flow:
   - On `/aid-first-aid` start: backup `.claude/settings.json` to
     `.aid-o/03-config/permissions-backup.json`
   - Apply auto-mode permissions from `.aid-o/03-config/permissions-auto.yaml`
   - On completion (or `/aid-stop`): restore backup to `.claude/settings.json`, delete backup
   - Permission learning: if PM grants new permission during auto mode, append pattern
     to `permissions-auto.yaml` so it's included next time
   - Safety: never elevate permissions for system directories, credentials, or git force-push
   Effort: S

3. **Implement `/aid-first-aid` command** — New command in `commands/aid-first-aid.md`:
   - Validate: EPIC queue has items, permissions-auto.yaml exists (or generate defaults)
   - Display FIRST AID banner with queue summary
   - Set `mode: auto` in orchestration state
   - Execute permission sandwich (elevate)
   - Begin queue processing: load first EPIC, run `/aid-run-epic` in auto mode
   - On EPIC completion: check queue for next EPIC, continue or finish
   - On finish: execute permission sandwich (restore), display summary report
   Effort: M

4. **Implement `/aid-stop` command** — New command in `commands/aid-stop.md`:
   - Immediately set `mode: manual` in orchestration state
   - Restore permissions from backup
   - Save current progress (which EPIC, which step)
   - Display status: "FIRST AID disengaged. Progress saved. Resume with /aid-first-aid."
   - PM can resume auto mode or continue manually with `/aid-run-epic`
   Effort: S

5. **Implement escalation protocol** — Define in `skills/epic-orchestration.md`:
   - Escalation triggers: step fails 2x (retry exhausted), security finding with severity HIGH,
     agent explicitly flags "cannot resolve", merge conflict, test suite red after fix attempt
   - Escalation flow: pause auto mode → notify PM with context → PM resolves → PM chooses
     "resume auto" or "continue manual"
   - Non-escalation: low-severity findings, style issues, minor test failures that agent
     can fix → agent handles autonomously
   Effort: S

6. **Implement auto-mode DONE state behavior** — Extend DONE state in `epic-orchestration.md`:
   - Curator findings → route to agents for auto-fix (already implemented)
   - Release decision: last EPIC in queue → mandatory version bump (no PM ask),
     intermediate EPIC → defer (no PM ask)
   - Queue transition: after DONE, check `epic-queue.yaml` for next EPIC → auto-load and start
   - Summary collection: aggregate results across all EPICs for final report
   Effort: S

7. **Create permissions-auto.yaml defaults** — Default auto-mode permission template in
   `defaults/policies/permissions-auto.yaml`:
   - Allow: Edit/Write within project directory
   - Allow: Bash for git, npm/pip, test runners, linters
   - Deny: System directories (/etc, /usr, ~/.ssh, ~/.aws)
   - Deny: git push --force, git reset --hard, rm -rf /
   - Deny: Network access to non-localhost (except configured MCP servers)
   - Aid-setup generates project-specific version on first run
   Effort: S

8. **FIRST AID banner and summary report** — Design the startup banner (ASCII art: syringe
   injecting Claude Code with steroids theme, queue info, mode info, stop command).
   Design completion summary report: EPICs completed, steps executed, issues found/resolved,
   escalations, version bumps, total evidence artifacts.
   Effort: XS

9. **Update epic-orchestration.md** — Add auto-mode sections to every state that has PM
   decision points. Use conditional format:
   ```
   IF mode == auto:
     {auto behavior}
   ELSE:
     {existing manual behavior}
   ```
   This preserves manual mode while adding auto capability.
   Effort: M

10. **Verification** — Walk through a 3-EPIC queue scenario mentally:
    EPIC 1 (3 steps) → DONE → EPIC 2 (5 steps, one fails) → escalation → PM resolves →
    resume → DONE → EPIC 3 (2 steps) → DONE → final report.
    Verify: permissions elevated/restored, escalation works, queue transitions,
    release decisions, summary report accurate.
    Effort: S

## Constraints

- Manual mode remains the default — FIRST AID is opt-in
- PM can always disengage with `/aid-stop`
- Permission elevation is sandboxed (project directory only, never system-wide)
- Permission backup must be atomic (temp file → rename)
- Escalation is the ONLY mandatory PM touchpoint in auto mode
- FIRST AID must work without GUI (CLI-only is valid)
- Queue is sequential (no parallel EPIC execution)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Permission elevation too broad (security risk) | Medium | High | Strict defaults in permissions-auto.yaml; deny-list for dangerous operations; PM reviews on first run |
| Agent quality checks miss issues PM would catch | Medium | High | Escalation protocol as safety net; summary report for post-hoc review; PM can always /aid-stop |
| Permission restoration fails (crash during auto mode) | Low | High | Backup file persists; on next CC start, check for orphaned backup and restore |
| Queue processing fails mid-way (context limit, CC crash) | Medium | Medium | Progress saved per-EPIC; PM can resume with /aid-first-aid from where it stopped |
| Escalation too aggressive (PM interrupted too often) | Medium | Medium | Tune thresholds; start conservative, loosen based on experience |
| Escalation too lenient (issues slip through) | Low | High | Summary report catches post-hoc; auditor runs at DONE |

## Success Criteria

- [ ] `/aid-first-aid` starts autonomous mode with banner and queue summary
- [ ] `/aid-stop` disengages immediately, restores permissions, saves progress
- [ ] EPIC queue processes sequentially without PM intervention
- [ ] Agent-driven quality checks replace PM approval at PHASE_CHECK
- [ ] Escalation triggers correctly for: 2x retry fail, HIGH security finding, merge conflict
- [ ] Escalation pauses auto mode and waits for PM decision
- [ ] Permissions elevated on start, restored on completion (or stop)
- [ ] New permissions learned and persisted to permissions-auto.yaml
- [ ] DONE state: auto-release for last EPIC, auto-defer for intermediate
- [ ] Summary report shows: EPICs completed, steps, issues, escalations, version bumps
- [ ] Manual mode unaffected — default behavior unchanged

## Future Enhancements (not in this plan)

- GUI integration: real-time monitoring dashboard, stop button, escalation modal
- Fast mode: lightweight pipeline with reduced gates
- Parallel EPIC execution: run independent EPICs concurrently
- Scheduled execution: cron-like EPIC scheduling
- Notification hooks: Slack/email on escalation or completion

## Next Steps

- [ ] Create EPIC from this plan
- [ ] Implement C4 (Core Structure Refactoring) first — prerequisite
- [ ] Run via `/aid-run-epic`
