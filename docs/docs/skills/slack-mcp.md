---
sidebar_position: 21
title: "Slack MCP"
description: "PM communication protocol — routes all orchestrator messages (escalations, approvals, proposals, summaries) through a Slack MCP server with chat fallback."
---

# Slack MCP

The Slack MCP skill defines how AID communicates with the PM. All PM-facing messages — escalations, plan approvals, merge approvals, improvement proposals, and status updates — are sent through a Slack MCP server. If Slack is not configured, every message falls back to chat-based communication with the same content.

## Purpose

EPIC execution can take minutes to hours. The PM does not need to watch the chat window the entire time. By routing all PM communication through Slack with configurable timeouts and reminders, AID can work asynchronously: run steps, hit a decision point, notify the PM via Slack, wait for a response, and then continue. The chat fallback ensures the skill works without any Slack setup.

## When Used

- Every PM-facing message from the Controller goes through this skill
- Used by `auto-escalation` for escalation notifications in FIRST AID auto-mode
- Used by `auto-done-state` for session status updates and the final session report
- Used by `epic-queue` for queue transition notifications
- Used throughout `epic-orchestration` for plan approval, phase summaries, and merge approval

## Key Concepts

### Three MCP Tools

**`slack_send_message`** — sends a formatted message to a Slack channel. Takes a `message_type` (one of the seven message types below), a type-specific `payload`, and an optional `thread_ts` for threading replies. Returns a `message_id` (Slack timestamp) used for tracking and updates.

**`slack_wait_for_reply`** — waits for the PM to reply to a sent message via thread reply or reaction. Configurable timeout, reminder interval, and maximum reminders. Returns the PM's response (parsed response type and raw text) or a timeout status.

**`slack_update_message`** — updates an existing message (for example, marking an escalation as resolved after the PM responds).

### Seven Message Types

| Type | When Used | Wait for Reply? |
|---|---|---|
| `escalation` (Type A) | Agent blocked, critical issue, PM must decide | Yes — blocking |
| `plan_approval` (Type B) | PM must approve generated plan before execution | Yes — blocking |
| `phase_summary` (Type C) | Each phase completes in manual mode | Yes — wait for GO |
| `merge_approval` (Type D) | PM must approve EPIC for merge | Yes — blocking |
| `proposal` (Type E) | Curator proposes backlog items | Yes — non-blocking (deferred timeout) |
| `lessons_summary` (Type F) | Lessons extracted at run-end | No — informational |
| `status_update` (Type G) | Progress notifications in auto-mode | No — informational |

### Fallback Behavior

When `slack.enabled: false` (or `slack-config.yaml` does not exist), all messages are presented in the chat conversation using the same structured format. The PM replies in chat instead of Slack. The abstraction layer (`send_pm_message` / `wait_pm_response`) makes this transparent to the rest of the system.

### Timeout Actions

For each message type, `timeout_actions` in `slack-config.yaml` defines what happens if the PM does not respond within the timeout window:

- `wait` — keep waiting, send additional reminder, do not proceed
- `skip` — skip the current item and continue (for non-critical escalations)
- `abort` — stop the current EPIC and pause the queue
- `defer` — defer the item to the next session (for improvement proposals)

## How It Works

The communication protocol uses three functions:

**`resolve_pm_channel()`** — reads `slack-config.yaml` and returns either `{mode: "slack", config: ...}` or `{mode: "chat"}`.

**`send_pm_message(type, payload)`** — formats the message for the given type, sends via `slack_send_message` (or presents in chat), and returns a message reference with the mode and message ID.

**`wait_pm_response(message_ref, timeout_type)`** — waits for PM reply with the configured timeout. In Slack mode, calls `slack_wait_for_reply`; in chat mode, pauses and waits for the PM to type. On timeout, applies the configured `timeout_action` for this message type.

The escalation message type (Type A) is extended in auto-mode with a fourth option (D: continue-manual) and session progress context, as defined in the `auto-escalation` skill.

## Configuration

Configuration lives in `.aid-o/03-config/policies/slack-config.yaml`:

```yaml
slack:
  enabled: true
  channel: "#aid-orchestrator"
  pm_user_id: "U1234567"

  timeouts:
    plan_approval_minutes: 1440     # 24h
    escalation_minutes: 480         # 8h
    merge_approval_minutes: 1440    # 24h
    proposal_minutes: 4320          # 72h

  reminders:
    enabled: true
    interval_minutes: 60
    max_reminders: 3

  timeout_actions:
    escalation: "wait"
    merge_approval: "wait"
    proposal: "defer"
```

Slack is disabled by default. Set `enabled: true` and configure `channel` and `pm_user_id` to activate Slack notifications.

## Related

- [Epic Orchestration](../skills/epic-orchestration)
- [Auto Escalation](../skills/auto-escalation)
- [Auto Done State](../skills/auto-done-state)
- [Epic Queue](../skills/epic-queue)
