---
sidebar_position: 5
title: "Auto Done State"
description: "Defines the DONE state behavior for FIRST AID auto-mode: autonomous release decisions, queue transitions between EPICs, and final session report generation."
---

# Auto Done State

In FIRST AID auto-mode, the DONE state must make release decisions without PM interaction, transition automatically to the next queued EPIC, and accumulate summary data for a final session report. This skill defines all of those behaviors as deterministic overrides on top of the standard DONE state.

## Purpose

The standard DONE state pauses for PM decisions at each EPIC boundary: ask about version bumps, present a completion summary, check the queue. In auto-mode, this defeats the purpose of autonomous execution. The auto done state replaces those interactive steps with deterministic rules while preserving all evidence-generating and archival actions unchanged.

## When Used

- Active only when `auto-mode-state.yaml` exists with `session_status: "running"`
- Invoked automatically by the Controller at the end of every EPIC in a FIRST AID session
- Controlled by the `/aid-first-aid` command (which starts auto-mode) and `/aid-stop` (which exits it)

## Key Concepts

### Release Decision Rules

The release decision is determined by the EPIC's position in the queue — no PM input:

| EPIC Position | Version Bump | Git Tag | GitHub Release |
|---|---|---|---|
| Standalone (1 EPIC in queue) | Yes, mandatory | Per `release-policy.yaml` `auto_tag` | Per `release-policy.yaml` `auto_release` |
| Intermediate (more EPICs queued) | Deferred | No | No |
| Last (no more EPICs queued) | Yes, mandatory | Per `release-policy.yaml` `auto_tag` | Per `release-policy.yaml` `auto_release` |

Intermediate EPICs defer their version bump so the last EPIC picks up the final CHANGELOG version (which may reflect changes from all intermediate EPICs). Deferred bumps are recorded in `auto-mode-state.yaml` for traceability.

### Queue Transition

After all DONE actions complete for the current EPIC, the Controller:
1. Aggregates the EPIC's metrics into the session summary
2. Marks the EPIC as complete in `epic-queue.yaml`
3. Checks guardrails (escalation budget, queue paused flag, EPIC failure status)
4. Finds the next queued EPIC and starts it, or executes the session complete protocol

If the queue is paused, or the escalation budget is exceeded, the Controller escalates to the PM before loading the next EPIC.

### Summary Aggregation

After each EPIC completes, the Controller extracts metrics from the EPIC's evidence (plan progress, gate results, stage log, final report) and appends them to `auto-mode-state.yaml`. The running session totals track: total EPICs, completed/failed counts, total steps, gate retries, escalation counts and types, version bumps, and estimated LLM cost.

### Final Session Report

When the queue empties (or the session is stopped), the Controller generates a comprehensive report at `.aid-o/04-engine/evidence/auto-session-report-{session_id}.md`. The report covers the session overview, a summary table of all metrics, version bump history (including deferred bumps), escalation details, and a per-EPIC breakdown with evidence paths.

This report is the only PM-facing summary for the entire auto-mode session. The PM sees it after all EPICs have been processed.

## How It Works

The Controller reads `auto-mode-state.yaml` at every DONE state decision point. If `session_status` is `"running"`, auto-mode logic applies; otherwise the standard manual flow runs.

The DONE state execution order in auto-mode:
1. Standard DONE actions execute unchanged (run file update, branch merge, archival, Qdrant metrics)
2. Release decision runs the deterministic algorithm instead of asking PM
3. Completion summary is logged to `auto-mode-state.yaml` rather than presented interactively
4. Brief Slack status update is sent ("EPIC complete N/total")
5. Queue transition runs: aggregate, check guardrails, find next EPIC or complete session

If the session ends early (PM abort or manual takeover), a partial session report is still generated with whatever data is available. The permission restore step always runs, regardless of how the session ends.

## Configuration

Key configuration files:

- `.aid-o/04-engine/epic-queue.yaml` — the EPIC queue with status tracking
- `.aid-o/04-engine/auto-mode-state.yaml` — session state, summary aggregation, EPIC summaries
- `.aid-o/03-config/release-policy.yaml` — controls `auto_tag` and `auto_release` behavior
- `.aid-o/04-engine/auto-session.json` — escalation budget tracking

## Related

- [Epic Orchestration](../skills/epic-orchestration)
- [Epic Queue](../skills/epic-queue)
- [Auto Escalation](../skills/auto-escalation)
- [Permission Sandwich](../skills/permission-sandwich)
- [Slack MCP](../skills/slack-mcp)
