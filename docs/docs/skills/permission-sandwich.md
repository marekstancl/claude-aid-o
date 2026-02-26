---
sidebar_position: 16
title: "Permission Sandwich"
description: "Permission lifecycle management for FIRST AID auto-mode: backup current settings, elevate to auto-mode permissions, restore on completion or crash."
---

# Permission Sandwich

The permission sandwich skill manages the Claude Code permission lifecycle around FIRST AID auto-mode sessions. Before autonomous execution begins, the current `.claude/settings.json` is backed up and permissions are elevated to the auto-mode superset. When execution completes — or if it crashes — the original permissions are restored. PM-granted permissions during auto-mode are learned and persisted for future sessions.

## Purpose

FIRST AID auto-mode needs broader permissions than normal interactive sessions to run commands, write files, and execute gates without stopping for confirmation. But these elevated permissions should not persist after the session ends. The permission sandwich guarantees this: **backup → elevate → run → restore**, with crash recovery if the session terminates unexpectedly.

## When Used

- Executed at the start of every `/aid-first-aid` command (FIRST_AID_INIT state)
- Restore runs at session complete, PM abort, PM manual takeover, and crash recovery
- The presence of `permissions-backup.json` signals an active or crashed auto-mode session
- Consumed by `auto-done-state` which calls `RESTORE_PERMISSIONS` at session completion

## Key Concepts

### The Four-Step Lifecycle

1. **Backup** — read `.claude/settings.json` and write a copy to `.aid-o/03-config/permissions-backup.json`. If `settings.json` does not exist, create a minimal default first. If `permissions-backup.json` already exists, a previous auto-mode session crashed — run crash recovery before proceeding.

2. **Elevate** — read the auto-mode permission template (`permissions-auto.yaml`) and replace the `permissions.allow[]` array in `settings.json` with the auto-mode superset. Hard-deny list items are never added, regardless of what the template contains.

3. **Run** — auto-mode executes with elevated permissions. The Controller tracks which permissions it actually uses in `auto-mode-state.yaml`.

4. **Restore** — write the backup back to `settings.json`, overwriting the elevated permissions. Delete `permissions-backup.json` to signal the session ended cleanly.

### Permission Learning

When the PM grants a permission during auto-mode (via an escalation response), that permission is:
1. Applied immediately (added to the current elevated set in `settings.json`)
2. Recorded in `auto-mode-state.yaml` under `permissions.learned_permissions`
3. At session end, the learned permission is added to `permissions-auto.yaml` for future sessions

This means permissions grow incrementally as the PM approves them — the auto-mode set expands to match the project's actual needs without the PM having to configure everything upfront.

### Hard-Deny List

Some permissions are never allowed in auto-mode regardless of configuration:
- `Bash(git push --force *)` — destructive push operations
- `Bash(git reset --hard *)` — destructive reset operations
- `Bash(rm -rf *)` — broad recursive deletion

These are hardcoded in the plugin and cannot be overridden by `permissions-auto.yaml`.

### Crash Recovery

If `permissions-backup.json` exists when a new session starts:

1. The previous session crashed without restoring permissions
2. The Controller does NOT auto-resume the previous session
3. Permissions are restored from the backup
4. A warning is presented: "Previous auto-mode session did not complete cleanly. N EPICs completed. Review auto-mode-state.yaml for details."
5. PM must decide whether to re-queue remaining EPICs and run `/aid-first-aid` again

## How It Works

The backup procedure validates that `settings.json` is valid JSON before creating the backup. An invalid `settings.json` causes FIRST_AID_INIT to abort with an error — the session does not start with an unreadable permission file.

The elevation procedure reads `permissions-auto.yaml` from `.aid-o/03-config/` (project override) or `defaults/policies/permissions-auto.yaml` (plugin default) and merges the permission sets. After elevation, `auto-mode-state.yaml` records the applied permissions list for audit purposes.

The restore procedure always runs at session end, including partial sessions. If the restore fails (file write error), it logs a warning to the PM but does not treat this as a blocking error — the auto-mode session itself has completed.

## Configuration

Permission templates:
- `.aid-o/03-config/permissions-auto.yaml` — project-specific auto-mode permissions (overrides plugin default)
- `defaults/policies/permissions-auto.yaml` — plugin default permission template

State tracking:
- `.aid-o/03-config/permissions-backup.json` — backup of `settings.json` (presence = active/crashed session)
- `.aid-o/04-engine/auto-mode-state.yaml` — applied and learned permissions

## Related

- [Epic Orchestration](../skills/epic-orchestration)
- [Auto Done State](../skills/auto-done-state)
- [Auto Escalation](../skills/auto-escalation)
- [Epic Queue](../skills/epic-queue)
