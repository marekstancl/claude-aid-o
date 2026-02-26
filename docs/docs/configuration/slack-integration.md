---
sidebar_position: 4
title: "Slack Integration"
description: "How to configure AID to send PM communication through Slack — MCP server setup, slack-config.yaml reference, message types, and fallback behavior."
---

# Slack Integration

AID communicates with the PM through Slack when integration is enabled. All PM-facing messages — escalations, plan approvals, merge approvals, improvement proposals, audit summaries, and status updates — are sent to a single configured Slack channel. The PM responds by replying in thread or adding a reaction, and the Controller continues without requiring any action in the Claude Code terminal.

When Slack integration is not configured or is disabled, AID falls back to presenting all messages inline in the conversation.

---

## Prerequisites

### Slack Bot Scopes

Your Slack app needs these OAuth scopes:

**Required:**
- `chat:write` — post messages to channels
- `channels:read` — look up channel info
- `channels:history` — read replies and reactions
- `users:read` — resolve user IDs for `@mentions`

**Recommended:**
- `channels:join` — allow the bot to join channels automatically
- `groups:history` — read replies in private channels
- `groups:read` — look up private channel info

### MCP Server

AID does not implement a Slack MCP server itself. It expects an external server that provides three tools: `slack_send_message`, `slack_wait_for_reply`, and `slack_update_message`. The recommended server is `slack-mcp-server` by `@korotovsky`.

---

## Setup

### Step 1: Install the MCP server

Install `slack-mcp-server` by following its documentation. The server uses environment variables for authentication:

```bash
# Store in .env (never commit this file)
SLACK_MCP_XOXB_TOKEN=xoxb-...          # Bot User OAuth Token from your Slack app
SLACK_MCP_ADD_MESSAGE_TOOL=C0...        # Channel ID where AID posts messages
```

### Step 2: Configure .mcp.json

Register the server with a bash wrapper that loads your `.env` and suppresses stderr. A bare `node` invocation without the wrapper will expose your token in logs or fail to load environment variables.

```json
{
  "mcpServers": {
    "slack": {
      "command": "bash",
      "args": [
        "-c",
        "set -a && source .env && set +a && npx slack-mcp-server 2>/dev/null"
      ]
    }
  }
}
```

The `2>/dev/null` suppresses the MCP server's startup banner and connection messages, which would otherwise appear as noise in the Claude Code output.

### Step 3: Enable Slack in slack-config.yaml

Open `.aid-o/03-config/policies/slack-config.yaml` and set `enabled: true`, then configure your channel and PM user ID:

```yaml
slack:
  enabled: true
  channel: "#aid-orchestrator"
  pm_user_id: "U1234567"    # Find your user ID in Slack profile settings
```

### Step 4: Verify

Run `/aid-help` to confirm the plugin loads without errors, then start a small EPIC to verify AID posts to your Slack channel.

---

## slack-config.yaml Reference

**Location:** `.aid-o/03-config/policies/slack-config.yaml`

Full default configuration (source: `plugins/aid-orchestrator/defaults/policies/slack-config.yaml`):

```yaml
slack:
  enabled: false
  channel: "#aid-orchestrator"
  pm_user_id: ""

  timeouts:
    plan_approval_minutes: 1440
    escalation_minutes: 480
    merge_approval_minutes: 1440
    proposal_minutes: 4320

  reminders:
    enabled: true
    interval_minutes: 60
    max_reminders: 3

  timeout_actions:
    plan_approval: "wait"
    escalation: "wait"
    merge_approval: "wait"
    proposal: "defer"
```

### `slack.enabled`

`false` (default) — AID uses chat-based communication. No Slack MCP tools are called.

`true` — AID routes all PM communication through Slack.

### `slack.channel`

The Slack channel where AID posts all messages. Must include the `#` prefix. All message types — escalations, approvals, proposals, status updates — go to this single channel. Threads within the channel separate individual conversations.

### `slack.pm_user_id`

The PM's Slack user ID (format: `U` followed by alphanumeric characters). AID uses this for `@mention` on escalations and approval requests that require PM attention. Find it in Slack under your profile → "Copy member ID".

Leave empty to skip `@mentions`. Messages are still posted, but the PM is not notified directly.

---

## Timeouts

How long AID waits for a PM response before taking the configured timeout action.

### `timeouts.plan_approval_minutes`

Time to wait for PM to respond to a plan review message (GO / REVISE / ABORT). Default is `1440` minutes (24 hours). Increase this if your PM reviews plans less frequently.

### `timeouts.escalation_minutes`

Time to wait for PM to respond to an escalation (gate failure, agent error, etc.). Default is `480` minutes (8 hours). Escalations are higher priority than proposals, so this timeout is shorter.

### `timeouts.merge_approval_minutes`

Time to wait for PM to approve the final merge after all steps and gates pass. Default is `1440` minutes (24 hours).

### `timeouts.proposal_minutes`

Time to wait for PM to respond to an improvement proposal. Default is `4320` minutes (72 hours). Proposals are lowest priority — they do not block EPIC execution and can wait several days.

---

## Reminders

When enabled, AID sends reminder messages to Slack if the PM has not responded to a waiting message.

### `reminders.enabled`

`true` (default) — AID sends periodic reminders. Set to `false` to disable all reminders; AID waits silently until the timeout.

### `reminders.interval_minutes`

How often to send a reminder. Default is `60` minutes (hourly). AID sends a brief follow-up message in the same thread.

### `reminders.max_reminders`

Maximum number of reminders to send before stopping and applying the `timeout_action`. Default is `3`. After three reminders (3 hours on the default schedule), if the PM has not responded, the configured timeout action takes effect.

---

## Timeout Actions

What AID does when a message reaches its timeout after all reminders are exhausted. The available actions depend on the message type.

```yaml
timeout_actions:
  plan_approval: "wait"
  escalation: "wait"
  merge_approval: "wait"
  proposal: "defer"
```

### Action options

| Action | Meaning | Valid for |
|---|---|---|
| `wait` | Keep waiting indefinitely — take no action without PM response | Any type |
| `skip` | Treat as a "skip" response from the PM | Escalations only |
| `abort` | Treat as an "abort" response | plan_approval, escalation, merge_approval |
| `defer` | Move proposal to backlog | Proposals only |

### Defaults explained

All PM-blocking message types (`plan_approval`, `escalation`, `merge_approval`) default to `"wait"` — AID never auto-approves, auto-aborts, or auto-merges without explicit PM input. This is a conservative default that prevents autonomous decisions on high-stakes actions.

Proposals default to `"defer"` — if a proposal has not been reviewed in 72 hours, it is automatically moved to the backlog. Proposals are informational and deferral is safe.

### Adjusting for asynchronous teams

If your team reviews plans daily and escalations same-day, you can keep the defaults. If your PM is less available and you want AID to proceed more autonomously:

```yaml
timeout_actions:
  plan_approval: "wait"    # Never auto-proceed without plan review
  escalation: "skip"       # After 8h + 3 reminders, skip the failing gate and continue
  merge_approval: "wait"   # Never auto-merge
  proposal: "defer"        # Auto-defer proposals after 72h
```

---

## Message Types

AID defines seven message types. Each type has a specific format, response protocol, and urgency level.

### Type A: Escalation

Sent when the Controller hits a hard stop: gate failure after retries, agent error, critical security finding, or conflicting parallel outputs. Requires PM response.

PM responds with: `A` (fix), `B` (skip), `C` (abort). In auto-mode, option `D` (continue manual) is also available.

**Blocks pipeline:** Yes — EPIC pauses until PM responds.

### Type B: Plan Approval

Sent after `/aid-plan-epic` generates an execution plan, before any steps begin. Summarizes the planned steps, agent roles, and parallel groups. Requires PM response.

PM responds with: `GO`, `REVISE` + feedback text, or `ABORT`.

**Blocks pipeline:** Yes — execution does not start until PM approves.

### Type C: Merge Approval

Sent after all EPIC steps complete and all quality gates pass. Summarizes changed files, commit count, and branch list. Requires PM response.

PM responds with: `APPROVE`, `REJECT` + feedback, or `REVISE` + feedback.

**Blocks pipeline:** Yes — merge does not happen until PM approves.

### Type D: Improvement Proposal

Sent by the Curator agent with improvement suggestions identified during the EPIC (refactoring opportunities, performance issues, security improvements, DX improvements). Multiple proposals are sent as separate messages. Requires PM response on each.

PM responds with: `APPROVE`, `DEFER` + optional reason, or `REJECT` + optional reason.

**Blocks pipeline:** No — proposals are sent after EPIC completion and do not hold up any execution.

### Type E: Rejection Info

Sent by the Orchestrator or Curator when a proposal is rejected at the auto-evaluation stage (before it reaches the PM). Informational only — no response expected.

**Blocks pipeline:** No.

### Type F: Audit Summary

Sent by the Auditor agent after running `/aid-audit`. Contains overall score, per-category scores, and critical/warning/suggestion counts. Informational only — no response expected, unless critical findings trigger a separate Type A escalation.

**Blocks pipeline:** No (the summary itself does not block; an escalation triggered by critical findings does).

### Type G: Status Update

Short progress messages sent throughout EPIC execution: when the EPIC starts, when each step begins and completes, when gates run, and when the queue picks up the next EPIC. Informational only — no response expected.

AID never blocks EPIC execution for a failed status update. If `slack_send_message` fails for a Type G message, AID silently skips it and continues.

**Blocks pipeline:** Never.

---

## Fallback Protocol

### When Slack is disabled or not configured

If `slack.enabled = false` (or the config file does not exist), AID presents all messages in the conversation. Behavior is identical to pre-Slack versions of AID — the PM sees messages inline and responds in the chat session.

### When the Slack MCP server is unavailable

If `slack_send_message` fails:

1. AID retries 3 times with exponential backoff (1s, 5s, 15s)
2. After 3 failures:
   - **Messages that require a reply** (Types A, B, C, D): fall back to chat — the message is presented inline in the conversation, and AID waits for a chat response
   - **Informational messages** (Types E, F, G): silently skipped — AID logs the failure and continues EPIC execution

AID never stops an EPIC because Slack is down.

### When the PM does not respond (timeout)

After the timeout period plus all reminders are exhausted:

1. AID reads `timeout_actions` from `slack-config.yaml`
2. Executes the configured action
3. Logs the timeout event to `slack_log.jsonl` in the evidence directory
4. Sends a final message to Slack: `"Timeout reached for {message_type}. Auto-action: {action}"`

---

## Evidence Logging

Every Slack interaction is logged to:

```text
.aid-o/04-engine/evidence/{epic_id}/{run_id}/slack_log.jsonl
```

Each line is a JSON object:

```json
{"ts": "2026-02-17T10:00:00Z", "type": "plan_approval", "action": "sent", "message_id": "1708171200.000100", "channel": "#aid-orchestrator"}
{"ts": "2026-02-17T10:05:00Z", "type": "plan_approval", "action": "reminder_sent", "message_id": "1708171200.000100", "reminder_number": 1}
{"ts": "2026-02-17T10:42:00Z", "type": "plan_approval", "action": "response_received", "message_id": "1708171200.000100", "response_type": "go", "responder": "U1234567", "latency_minutes": 42}
{"ts": "2026-02-17T11:00:01Z", "type": "status_update", "action": "send_failed", "error": "Slack MCP unavailable", "fallback": "skipped"}
```

This log is the audit trail for all PM communication in an EPIC run. It records when messages were sent, when reminders fired, when the PM responded, and the PM's response type.

---

## Related

- [Slack MCP Skill](../skills/slack-mcp) — full protocol specification and message format details
- [Epic Orchestration](../skills/epic-orchestration) — state machine that sends Type A, B, C messages
- [Curator Agent](../agents/curator) — sends Type D (improvement proposals)
- [Auditor Agent](../agents/auditor) — sends Type F (audit summaries)
- [decision-policies.yaml](./decision-policies) — escalation triggers that produce Type A messages
