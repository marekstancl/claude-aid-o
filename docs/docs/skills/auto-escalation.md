---
sidebar_position: 6
title: "Auto Escalation"
description: "Defines the 16 escalation triggers, pause protocol, PM notification format, and decision handling for FIRST AID auto-mode — the only mandatory PM touchpoint during autonomous execution."
---

# Auto Escalation

In FIRST AID auto-mode, the vast majority of issues are resolved autonomously — lint errors auto-fixed, minor test failures retried, medium-severity discoveries logged for the Curator. Escalation is the safety valve: the small set of situations where autonomous resolution is inappropriate and human judgment is required. When an escalation triggers, auto-mode pauses cleanly, saves progress, and waits.

## Purpose

Autonomous execution is only safe if it knows its own limits. The auto-escalation skill defines exactly where those limits are: 16 specific trigger conditions that require PM input, the timing rules for how cleanly to pause (immediately for critical, at phase boundary for medium), and the complete protocol for resuming after the PM decides.

## When Used

- Active only during FIRST AID auto-mode sessions
- Triggered by the Controller when it detects one of the 16 escalation conditions
- Consumed by all parts of the Controller state machine: PHASE_CHECK, GATES, PLAN_REVIEW, EXECUTING, PM_APPROVAL
- The escalation budget is checked at every EPIC boundary by `auto-done-state`

## Key Concepts

### The 16 Escalation Triggers

**CRITICAL — immediate halt:**
- **E1**: Step fails twice, and a fresh approach also fails
- **E2**: Security agent reports a CRITICAL severity finding
- **E4**: A quality gate fails after 3 retries

**HIGH — pause after current atomic operation:**
- **E3**: Security agent reports a HIGH severity finding
- **E5**: Agent produces no output, times out, or errors
- **E6**: Merge conflict detected between parallel agent branches
- **E7**: Agent explicitly flags it cannot resolve the assigned task
- **E8**: Estimated LLM cost exceeds the configured budget limit

**MEDIUM — pause at next phase boundary:**
- **E9**: Agent violates scope (modifies forbidden paths) on a second attempt
- **E10**: Two agents produce contradictory decisions or designs
- **E11**: Auto-mode plan generation produces invalid or unvalidatable JSON
- **E12**: Session escalation count reaches `max_escalations_per_session` at an EPIC boundary
- **E13**: Architect agent outputs a decision requiring PM input with two or more valid options
- **E15**: Release sub-phase cannot determine the current version from configured version files
- **E16**: Planner or agent flags acceptance criteria as unparseable or contradictory

### Non-Escalation Conditions

Issues that agents handle silently include: low-severity security findings (logged), style/formatting lint failures (auto-fixed), minor test failures on first or second attempt (retried), medium/info discovered issues (added to Curator backlog), and conditional gate failures (logged as warning).

A non-escalation issue can promote to an escalation if it persists: minor test failures become E1 after two re-dispatches; lint failures become E4 after three retries.

### Four PM Options

Every escalation notification presents four options:
- **A — Fix**: PM provides guidance; auto-mode resets the retry counter and re-dispatches with PM's guidance prepended to the prompt
- **B — Skip**: Mark the failing item as `skipped_by_pm` and advance to the next step/gate
- **C — Abort**: Stop the EPIC immediately, run post-processing, pause the queue
- **D — Continue Manual**: Switch the current EPIC to manual orchestration; remaining queued EPICs stay paused until PM explicitly resumes

### Escalation Budget

Auto-mode tracks escalation frequency per session. The default budget is 3 escalations per session. When the budget is reached, trigger E12 fires at the next EPIC boundary — the PM must decide whether to raise the limit, switch to manual, or abort the queue.

The PM can tune the budget during any escalation response by including "set max escalations to N" in their reply.

## How It Works

When a trigger condition fires:

1. **Pause timing** is determined by severity (CRITICAL = immediate, HIGH = after current atomic operation, MEDIUM = after current step/phase)
2. **Progress is saved**: `plan_progress.json` is updated, uncommitted work is stashed with `git stash`, `epic-queue.yaml` marks the EPIC as paused
3. **Session escalation counter** is incremented in `auto-session.json`
4. **Escalation evidence** is written to `evidence/{epic_id}/{run_id}/escalations/escalation_{trigger}_{timestamp}.json`
5. **PM notification** is sent via Slack (or chat fallback) with the structured format
6. **Auto-mode waits** — no further execution until PM responds

When PM responds, auto-mode resumes from the appropriate state: E1 fix returns to EXECUTING; E4 fix returns to GATE_RETRY; E6 fix returns to PHASE_CHECK after the PM resolves the merge conflict.

All escalation events are also stored in Qdrant for cross-project learning — escalation patterns where the PM consistently skips or provides the same fix can eventually be automated.

## Configuration

Escalation budget and behavior are configured in `.aid-o/04-engine/auto-session.json`:

```json
{
  "max_escalations_per_session": 3,
  "escalation_count": 0,
  "guardrail_breached": false,
  "pm_tuned_max": null
}
```

The PM can adjust `max_escalations_per_session` during any escalation response. The default of 3 applies if no override is present.

## Related

- [Epic Orchestration](../skills/epic-orchestration)
- [Auto Done State](../skills/auto-done-state)
- [Epic Queue](../skills/epic-queue)
- [Retry Engine](../skills/retry-engine)
- [Gates Engine](../skills/gates-engine)
- [Slack MCP](../skills/slack-mcp)
