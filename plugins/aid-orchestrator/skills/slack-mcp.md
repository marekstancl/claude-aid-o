# Slack MCP Integration — PM Communication Protocol

**Version:** 0.1.0
**Skill:** slack-mcp
**Dependencies:** epic-orchestration

---

## TL;DR

This skill defines how AID communicates with the PM via Slack. All PM-facing messages
(escalations, approvals, proposals, summaries) are sent through a Slack MCP server.
If Slack is not configured, the system falls back to chat-based communication.

**Principle:** Everything that goes to PM goes through Slack. Even rejections = info.

---

## MCP Server Interface

AID expects an external Slack MCP server to provide these three tools:

### `slack_send_message`

Send a formatted message to a Slack channel.

```
Input:
  channel: string         # Slack channel ID or name (from config)
  message_type: string    # One of the 7 message types defined below
  payload: object         # Type-specific content (see Message Types)
  thread_ts: string|null  # If replying to an existing thread

Output:
  message_id: string      # Slack message timestamp (ts) for tracking
  channel: string         # Resolved channel ID
  permalink: string       # Link to the message
```

### `slack_wait_for_reply`

Wait for PM to respond to a message (via thread reply or reaction).

```
Input:
  message_id: string              # From slack_send_message
  channel: string                 # Channel where message was posted
  timeout_minutes: number         # Max wait time (from config)
  reminder_interval_minutes: number  # How often to remind PM
  max_reminders: number           # Max reminders before timeout (from config)

Output:
  status: "received" | "timeout"
  response_type: string          # Parsed response (e.g., "go", "fix", "approve")
  response_value: string         # Raw PM text
  responder: string              # Slack user ID
  timestamp: string              # When PM responded
  latency_minutes: number        # Time from send to response
```

### `slack_update_message`

Update an existing Slack message (e.g., mark as resolved after PM responds).

```
Input:
  message_id: string      # Original message ts
  channel: string         # Channel ID
  updated_payload: object # New content (replaces original)

Output:
  success: boolean
```

---

## Configuration

Read from `.aid-o/03-config/policies/slack-config.yaml`:

```yaml
slack:
  enabled: true                           # false = fallback to chat
  channel: "#aid-orchestrator"            # Slack channel for AID messages
  pm_user_id: "U1234567"                 # PM's Slack user ID (for @mentions)

  timeouts:
    plan_approval_minutes: 1440           # 24h
    escalation_minutes: 480              # 8h
    merge_approval_minutes: 1440          # 24h
    proposal_minutes: 4320               # 72h (lower priority)

  reminders:
    enabled: true
    interval_minutes: 60                  # Remind every hour
    max_reminders: 3                      # Max 3 reminders before timeout action

  timeout_actions:
    plan_approval: "wait"                 # wait | abort
    escalation: "wait"                    # wait | skip | abort
    merge_approval: "wait"               # wait | abort
    proposal: "defer"                    # defer | wait
```

---

## PM Communication Protocol

All PM communication from `commands/aid-run-epic.md` and agent integration flows uses
these three functions. They provide the abstraction layer over Slack vs chat.

### `resolve_pm_channel()`

```
1. Read .aid-o/03-config/policies/slack-config.yaml
2. IF file exists AND slack.enabled = true:
     return { mode: "slack", config: <parsed yaml> }
3. ELSE:
     return { mode: "chat" }
```

### `send_pm_message(type, payload)`

```
channel_info = resolve_pm_channel()

IF channel_info.mode = "slack":
  formatted = format_message(type, payload)     # Per Message Types below
  result = slack_send_message(
    channel = channel_info.config.slack.channel,
    message_type = type,
    payload = formatted
  )
  log_to_slack_log(type, result.message_id, "sent")
  return { mode: "slack", message_id: result.message_id }

ELSE (chat fallback):
  Present message in chat using existing format (pre-Session 6 behavior)
  return { mode: "chat" }
```

### `wait_pm_response(message_ref, timeout_type)`

```
IF message_ref.mode = "slack":
  config = resolve_pm_channel().config.slack
  timeout = config.timeouts[timeout_type + "_minutes"]
  reminder_interval = config.reminders.interval_minutes
  max_reminders = config.reminders.max_reminders

  response = slack_wait_for_reply(
    message_id = message_ref.message_id,
    channel = config.channel,
    timeout_minutes = timeout,
    reminder_interval_minutes = reminder_interval,
    max_reminders = max_reminders
  )

  IF response.status = "timeout":
    action = config.timeout_actions[timeout_type]
    log_to_slack_log(timeout_type, message_ref.message_id, "timeout", action)
    return { response_type: action, auto: true, reason: "timeout after " + timeout + " minutes" }

  log_to_slack_log(timeout_type, message_ref.message_id, "response", response.response_type)
  return response

ELSE (chat fallback):
  Wait for PM response in chat (existing behavior — blocking in conversation)
  return <chat response>
```

---

## Message Types

AID defines 7 message types. Each type specifies: format, sender context, whether it
expects a reply, and how PM responses are parsed.

### Type A: Escalation

**Expects reply:** Yes
**Sender:** Orchestrator (`commands/aid-run-epic.md` ESCALATION state)
**Timeout type:** `escalation`

**Format:**

```
:rotating_light: *ESCALATION — {trigger_reason}*
━━━━━━━━━━━━━━━━
*EPIC:* `{epic_id}` — {epic_title}
*State:* {current_state}

:clipboard: *Details:*
{failure_details — max 500 chars}

:dart: *Options:*
> :white_check_mark: *A)* {fix option — from decision-policies.yaml}
> :next_track_button: *B)* {skip option}
> :stop_sign: *C)* Abort EPIC

:bulb: *Recommendation:* {auto recommendation}

_Reply with A, B, or C (or start a thread for discussion)_
```

**Response parsing:**

| PM says | Parsed as |
|---------|-----------|
| `A`, `a`, `fix`, `retry` | `{ response_type: "fix" }` |
| `B`, `b`, `skip` | `{ response_type: "skip" }` |
| `C`, `c`, `abort` | `{ response_type: "abort" }` |
| Thread reply (other text) | `{ response_type: "discussion", message: "<text>" }` |

If `response_type: "discussion"`, the Orchestrator includes the PM's text as context
and re-presents options (do NOT auto-decide from discussion text).

---

### Type B: Plan Approval

**Expects reply:** Yes
**Sender:** Orchestrator (`commands/aid-run-epic.md` PLAN_REVIEW state)
**Timeout type:** `plan_approval`

**Format:**

```
:clipboard: *PLAN REVIEW — {epic_title}*
━━━━━━━━━━━━━━━━
*EPIC:* `{epic_id}`
*Steps:* {total_steps} ({parallel_groups} parallel groups, {analysis_groups} analysis groups)
*Agents:* {agent_role_list}

:bar_chart: *Plan Summary:*
{step_summary_table — numbered list, max 20 lines}

:gear: Full plan: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json`

_Reply: *GO* / *REVISE* / *ABORT*_
```

**Response parsing:**

| PM says | Parsed as |
|---------|-----------|
| `GO`, `go`, `approve`, :white_check_mark: reaction | `{ response_type: "go" }` |
| `REVISE` + text, `revise` + text | `{ response_type: "revise", feedback: "<text>" }` |
| `ABORT`, `abort`, :x: reaction | `{ response_type: "abort" }` |

---

### Type C: Merge Approval

**Expects reply:** Yes
**Sender:** Orchestrator (`commands/aid-run-epic.md` PM_APPROVAL state)
**Timeout type:** `merge_approval`

**Format:**

```
:white_check_mark: *EPIC COMPLETE — Ready for Merge*
━━━━━━━━━━━━━━━━
*EPIC:* `{epic_id}` — {epic_title}
*Steps:* {completed}/{total} completed
*Gates:* ALL PASS :white_check_mark:

:bar_chart: *Changes:*
• {file_count} files changed
• {commit_count} commits
• Branches: {branch_list}

:file_folder: Evidence: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/`

_Reply: *APPROVE* / *REJECT* / *REVISE*_
```

**Response parsing:**

| PM says | Parsed as |
|---------|-----------|
| `APPROVE`, `approve`, :white_check_mark: reaction | `{ response_type: "approve" }` |
| `REJECT` + text | `{ response_type: "reject", feedback: "<text>" }` |
| `REVISE` + text | `{ response_type: "revise", feedback: "<text>" }` |

---

### Type D: Improvement Proposal

**Expects reply:** Yes
**Sender:** Curator (via Orchestrator, `agents/curator.md` integration flow)
**Timeout type:** `proposal`

**Format:**

```
:bulb: *IMPROVEMENT PROPOSAL — {proposal_title}*
━━━━━━━━━━━━━━━━
*ID:* `{IMP-NNN}`
*Type:* {refactoring|performance|security|architecture|dx}
*Area:* `{area}`
*Priority:* {priority}
*Sources:* {agent_list} ({source_count} agents noticed this)

:clipboard: *Observation:*
{observation}

:dart: *Proposed Action:*
{proposed_action}

:stopwatch: *Estimated Effort:* {small|medium|large}
*Cost/Benefit:* {cost_benefit_analysis}

_Reply: *APPROVE* / *DEFER* / *REJECT*_
```

**Response parsing:**

| PM says | Parsed as |
|---------|-----------|
| `APPROVE`, `approve` | `{ response_type: "approve" }` |
| `DEFER` + optional reason | `{ response_type: "defer", reason: "<text>" }` |
| `REJECT` + optional reason | `{ response_type: "reject", reason: "<text>" }` |

**Batch handling:** When Curator generates multiple proposals, each is sent as a
separate Slack message. PM responds to each independently. The Orchestrator collects
all responses (parallel wait).

---

### Type E: Rejection Info

**Expects reply:** No
**Sender:** Orchestrator / Curator (informational)

**Format:**

```
:information_source: *PROPOSAL REJECTED by Orchestrator*
━━━━━━━━━━━━━━━━
*ID:* `{IMP-NNN}`
*Reason:* {rejection_reason}
_Status: Logged to backlog.md (orchestrator-rejected)_
```

No response parsing needed. Fire-and-forget.

---

### Type F: Audit Summary

**Expects reply:** No
**Sender:** Auditor (via Orchestrator, `agents/auditor.md` integration flow)

**Format:**

```
:bar_chart: *AUDIT SUMMARY — {epic_id}*
━━━━━━━━━━━━━━━━
*Overall Score:* {score}/100 ({trend_arrow} {delta} from previous)

:chart_with_upwards_trend: *Scores:*
• Code Quality: {score}/100
• Security: {score}/100
• Documentation: {score}/100
• Frontend: {score}/100 _(or N/A)_
• Database: {score}/100 _(or N/A)_

:red_circle: Critical Findings: {count}
:large_orange_diamond: Warnings: {count}
:white_check_mark: Suggestions: {count}

:file_folder: Full report: `.aid-o/04-engine/evidence/{epic_id}/audit-report.md`

{IF critical_count > 0:}
:warning: *Top Critical Findings:*
{top 3 critical findings — area + finding, one line each}
```

**Trend arrows:** `improving` = :arrow_up:, `declining` = :arrow_down:, `stable` = :left_right_arrow:, first audit = `:new:`

**Critical escalation:** If critical findings exist AND they match `escalation_triggers`
from `decision-policies.yaml`, the Orchestrator MAY send a separate Type A (Escalation)
message requiring PM acknowledgment. The Audit Summary itself is always informational.

---

### Type G: Status Update

**Expects reply:** No
**Sender:** Orchestrator (various states)

**Format:**

```
:pushpin: *STATUS — {epic_id}*
{status_message}
```

**Common status messages:**

| Event | Message |
|-------|---------|
| EPIC starts | `:rocket: EPIC started — {step_count} steps planned` |
| Step starts | `:zap: Step {N}/{total}: {role} started` |
| Step completes | `:white_check_mark: Step {N}/{total}: {role} done ({file_count} files)` |
| All steps done | `:mag: All steps complete — running gates...` |
| Gates pass | `:white_check_mark: All gates passed — awaiting merge approval` |
| EPIC completes | `:checkered_flag: EPIC completed — merged to main` |
| Queue pickup | `:arrows_counterclockwise: Auto-starting next EPIC: {next_epic_id}` |
| Queue empty | `:white_check_mark: Queue empty. Orchestrator idle.` |
| Queue paused | `:double_vertical_bar: Queue paused by PM` |

Status updates are fire-and-forget. If Slack send fails, silently skip (never block
EPIC execution for a status update failure).

---

## Fallback Protocol

### When Slack is not configured

```
IF .aid-o/03-config/policies/slack-config.yaml does not exist
   OR slack.enabled = false:

  → Use chat-based communication (pre-Session 6 behavior)
  → All message types fall back to presenting content in the conversation
  → No Slack MCP tools are called
  → Log once: "Slack MCP not configured, using chat fallback"
```

### When Slack MCP is unavailable

```
IF slack_send_message tool call fails:

  → Retry 3 times with exponential backoff (1s, 5s, 15s)
  → After 3 failures:
    - For messages expecting reply (Types A, B, C, D):
      → Fall back to chat (present message in conversation, wait for chat response)
      → Log warning: "Slack MCP unavailable, fell back to chat for {type}"
    - For informational messages (Types E, F, G):
      → Silently skip (non-critical)
      → Log: "Slack MCP unavailable, skipped {type} message"
  → Continue EPIC execution (never block due to Slack outage)
```

### When PM does not respond (timeout)

```
IF slack_wait_for_reply returns status: "timeout":

  → Read timeout_actions from slack-config.yaml
  → Execute the configured action:
    - "wait"   → keep waiting indefinitely (no auto-action, log warning)
    - "skip"   → treat as "skip" response (only valid for escalation)
    - "abort"  → treat as "abort" response
    - "defer"  → treat as "defer" response (only valid for proposals)
  → Log timeout event to slack_log.jsonl
  → Send final reminder: "⏰ Timeout reached for {message_type}. Auto-action: {action}"
```

---

## Evidence Logging

Every Slack interaction is logged to:

```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/slack_log.jsonl
```

Format (one JSON object per line):

```json
{"ts": "2026-02-17T10:00:00Z", "type": "plan_approval", "action": "sent", "message_id": "1708171200.000100", "channel": "#aid-orchestrator"}
{"ts": "2026-02-17T10:05:00Z", "type": "plan_approval", "action": "reminder_sent", "message_id": "1708171200.000100", "reminder_number": 1}
{"ts": "2026-02-17T10:42:00Z", "type": "plan_approval", "action": "response_received", "message_id": "1708171200.000100", "response_type": "go", "responder": "U1234567", "latency_minutes": 42}
{"ts": "2026-02-17T11:00:00Z", "type": "status_update", "action": "sent", "message_id": "1708174800.000200", "channel": "#aid-orchestrator"}
{"ts": "2026-02-17T11:00:01Z", "type": "status_update", "action": "send_failed", "error": "Slack MCP unavailable", "fallback": "skipped"}
```

---

## Reference Files

- `commands/aid-run-epic.md` — PLAN_REVIEW, ESCALATION, PM_APPROVAL states (consumers)
- `skills/epic-orchestration.md` — State machine definitions (authoritative)
- `agents/curator.md` — Curator → Orchestrator → PM flow (proposal consumer)
- `agents/auditor.md` — Auditor → Orchestrator → PM flow (summary consumer)
- `defaults/policies/decision-policies.yaml` — escalation_triggers, auto_decisions
- `workspace/workflow/plans/WORKFLOWS.md` WF-13 — Slack Integration workflow

---

## Important

- The Slack MCP server is **external** to the AID plugin. AID defines the protocol
  and message formats; it does not implement the MCP server itself.
- All messages are sent to a single channel (configured in `slack-config.yaml`).
  Thread replies are used for PM responses; reactions are supported as shortcuts.
- Messages expecting a reply use `slack_wait_for_reply` which blocks the Orchestrator
  until PM responds or timeout occurs. This is by design — PM decisions gate progress.
- Status updates (Type G) are always non-blocking. A Slack failure on a status update
  must never interrupt EPIC execution.
- When falling back to chat, the message content is the same — only the delivery
  mechanism changes. Evidence logging still records the interaction.
- Timeout defaults are conservative: most actions default to "wait" (do nothing
  without PM). Only proposals default to "defer" (lower priority, safe to postpone).
