---
name: setup-permissions
description: Configure AID permission preset and write to permissions.yaml + settings.local.json
---

# Setup Module: Permissions

Configure which permission preset AID uses for this project.

## Input

Called by `/aid-setup` router or `/aid-setup permissions`.

## Flow

1. Read `.aid-o/config/permissions.yaml` — extract `active_preset`
2. Show current state to PM:
   ```
   Current permissions: {active_preset}
   ```
3. Ask PM to choose:
   ```
   Permission presets:
     (1) autonomous (recommended) — full autonomy, destructive ops denied
         auto_commit: true, auto_push: false
     (2) custom — configure each setting manually
   ```
4. If PM chooses (2) custom, ask interactively:
   - `autonomous_mode` (true/false)
   - `auto_commit` (true/false)
   - `auto_push` (true/false)
   - Which destructive commands to deny

5. Write results:

### Write 1: `config/permissions.yaml`

Update `active_preset` field to chosen preset name.
If custom: write `active_preset: "custom"` and add a `custom:` block under `presets:`.

### Write 2: `.claude/settings.local.json`

Read existing `.claude/settings.local.json` (or create `{}`).
Merge `permissions.allow` and `permissions.deny` arrays from the chosen preset's `claude_code_permissions` and `claude_code_deny` lists.

```json
{
  "permissions": {
    "allow": ["Glob", "Grep", "Read", "Edit", "Write", "Bash(*:*)"],
    "deny": ["Bash(rm -rf:*)", "Bash(git push --force:*)"]
  }
}
```

**Important:** Preserve any existing keys in `settings.local.json` that are NOT `permissions`.

## Reference

- Preset definitions: `defaults/policies/permissions.yaml`
- Two presets: autonomous (default), custom

## Output

Confirm to PM:
```
Permissions set to: {preset_name}
  allow: {count} rules
  deny: {count} rules
Written to:
  - .aid-o/config/permissions.yaml
  - .claude/settings.local.json
```


**Last Updated:** 2026-03-04
