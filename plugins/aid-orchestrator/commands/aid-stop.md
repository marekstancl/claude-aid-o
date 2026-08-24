---
name: aid-stop
description: Emergency stop — disengage FIRST AID auto-mode immediately
user_invocable: true
---

Immediately disengage FIRST AID autonomous orchestration mode. This is the emergency stop for auto-mode — it halts autonomous execution and returns control to the PM. Execution progress is already persisted by the FSM in `fsm-state.yaml`, so `/aid-run --resume` can pick up where it left off; `/aid-stop` itself does not save progress.

This command is designed to be **fast and non-blocking**. Every step is resilient to partial failures — the goal is always to return to manual mode, even if some cleanup steps encounter errors.

## Usage

> **Resolve `$AID_PLUGIN_PATH` before running anything below.** Nothing sets it
> for you — not the plugin, not the workspace, not your shell. Every command
> here would otherwise fail with "file not found", and the reader is left to
> work the path out (which is how this survived unnoticed: a model usually
> does). The workspace records it, and this is the same source
> `commands/aid-run.md` §PRE-FLIGHT already uses:
>
> ```bash
> _aid_installed="$(jq -r '.plugins["aid-orchestrator@claude-aid-o"][0].version' \
>                   ~/.claude/plugins/installed_plugins.json 2>/dev/null)"
> AID_PLUGIN_PATH="$(yq -r '.plugin_path' "$(git rev-parse --show-toplevel)/.aid-o/config/plugin.yaml")"
> # The workspace PINS a version and old copies stay on disk, so "the file is
> # there" is not "the file is current": on 2026-08-24 a session ran its first
> # commands against 2.89.1 while 2.90.0 was the installed one. Compare, do not
> # assume.
> [[ -n "$_aid_installed" && "$AID_PLUGIN_PATH" != *"/$_aid_installed" ]] \
>   && AID_PLUGIN_PATH="$HOME/.claude/plugins/cache/claude-aid-o/aid-orchestrator/$_aid_installed"
> test -f "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" || echo "no plugin at $AID_PLUGIN_PATH — run /aid-init"
> ```


```
/aid-stop
```

No arguments. No confirmation prompt. Immediate execution.

## Prerequisites

- FIRST AID auto-mode must be active (or at least partially active)
- State file: `.aid-o/work/auto-mode-state.yaml`

If auto-mode is not active, inform PM and exit gracefully (see Edge Cases).

## Core Instruction

**Read this stop sequence carefully.** Each step is independent — if one fails, log the failure and continue to the next.

## Stop Sequence

Execute these steps in order. Each step is independent — if one fails, log the failure and continue to the next. The sequence must always complete.

---

### Step 1: Verify Auto-Mode is Active

1. Read `.aid-o/work/auto-mode-state.yaml`
2. Check `mode` field:
   - If `mode: auto` → proceed with stop sequence
   - If `mode: manual` or file does not exist → auto-mode is not active. Display:
     ```
     FIRST AID is not active. Nothing to stop.
     Current mode: manual
     ```
     Exit command. Do not modify any files.

---

### Step 2: Disengage Auto-Mode (the critical write)

**This write halts the Controller — auto-pickup is gated on `mode == auto`, so flipping to
`mode: manual` stops it from dispatching the next agent.**

1. Write `.aid-o/work/auto-mode-state.yaml`:
   ```yaml
   mode: manual
   stopped_at: "{now ISO 8601}"
   stopped_by: "pm"
   stop_reason: "/aid-stop command"
   ```
2. If write fails:
   - Log ERROR: "Failed to update auto-mode-state.yaml: {error}"
   - Continue (do NOT abort).

> Execution progress (current EPIC, step, FSM state) is ALREADY persisted by the FSM in the
> run's `fsm-state.yaml` — `/aid-run --resume` reads it to continue. `/aid-stop` does not copy
> progress anywhere; it only flips the autonomous mode off.

---

### Step 3: Read Progress (for the stop event + status message)

Read the current run's `fsm-state.yaml` — the real fields:
- `epic_id`, `run_id`, `state`, `current_step`, `total_steps`

If `fsm-state.yaml` is missing or unreadable, use `unknown` for these fields and continue.
(Do NOT read `session.*` — no such block exists; the real progress is in `fsm-state.yaml`.)

---

### Step 4: Log Stop Event

Append a stop event to the run's timeline **via the logging helper** (NOT hand-written JSON —
the helper guarantees the canonical `{ts, event, ...}` schema + escaping + non-blocking append,
so a `jq`-by-`.event` consumer finds the event):

```bash
bash "$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh" log_event \
  ".aid-o/work/evidence/{epic_id}/{run_id}/timeline.jsonl" \
  aid_stop epic_id="{epic_id}" current_step="{current_step}" state="{state}" stopped_by=pm
```

If the helper or write fails → continue (non-blocking).

---

### Step 5: Display Status Message

After all steps complete, display the following status message to PM:

```
FIRST AID disengaged.
━━━━━━━━━━━━━━━━━━━━

Mode:        manual (auto-mode disengaged)

  EPIC:  {epic_id}
  Step:  {executing_step} of {total_steps} ({state})

  Run:   {run_id}

Resume options:
  /aid-run --resume      Resume from the saved FSM state (fsm-state.yaml)
  /aid-run {id}          Continue this EPIC manually (step by step)
  /aid-status {id}       Check current EPIC status
```

**Step rendering rule.** How a step number is rendered to a human, and which machine fields stay frozen, are defined by the Step rendering rule in skills/pipeline.md. Read it there and follow it; this surface deliberately carries the pointer and not the rule, so a correction to the definition cannot leave a stale copy behind here.


---

## Edge Cases

### Auto-mode not active

If `.aid-o/work/auto-mode-state.yaml` does not exist or `mode` is already `manual`:

```
FIRST AID is not active. Nothing to stop.
Current mode: manual
```

Exit without modifying any files.

### State file exists but is corrupted

If `auto-mode-state.yaml` exists but cannot be parsed:

1. Log ERROR about corrupted state file
2. Create a fresh state file with `mode: manual`
3. Display status with "unknown" for progress fields

### Currently executing agent step

The `/aid-stop` command does NOT attempt to interrupt a running agent. The agent will complete its current step, but:
- The Controller will not dispatch the next agent (mode is no longer `auto`)
- The completed step output is preserved in evidence

This is by design — killing an agent mid-execution could leave files in an inconsistent state.

### Queue has remaining EPICs

Remaining EPICs in `.aid-o/config/queue.yaml` are untouched. They remain queued. When PM resumes with `/aid-run`, the queue continues from where it stopped.

---

## Reference Files

- `skills/pipeline.md` — Controller state machine, evidence store structure
- `commands/aid-run.md` — The inverse command (start auto-mode / resume)
- `commands/aid-status.md` — Check EPIC progress after stopping

## Important

- This command is an **emergency stop**. It prioritizes speed and reliability over thoroughness. Every operation is designed to be non-blocking.
- Disengaging auto-mode (the `mode: manual` write in Step 2) is the most critical step — it stops the next dispatch. Execution progress is already persisted by the FSM in `fsm-state.yaml`, so `/aid-run --resume` can always pick up where it left off; `/aid-stop` does not save progress itself.
- Running agents are NOT interrupted. The stop prevents *future* dispatches, not current execution. This is intentional — mid-execution interruption risks leaving the codebase in a broken state.
- The stop sequence NEVER prompts for confirmation. When PM says stop, it stops. Immediately.


**Last Updated:** 2026-08-12
