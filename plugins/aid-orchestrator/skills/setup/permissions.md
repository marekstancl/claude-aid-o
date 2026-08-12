---
name: setup-permissions
description: Configure AID permission preset and write to permissions.yaml + settings.local.json
---

# Setup Module: Permissions

Configure which permission preset AID uses for this project.

## Input

Called by `/aid-setup` router or `/aid-setup permissions`.

## Flow

1. Read `.aid-o/config/permissions.yaml` — extract `active_preset` and `autonomous_mode`
2. Show current state to PM, using the canonical rendering — **key present**:
   ```
   Current permissions: {active_preset} (preset) — autonomous_mode: {autonomous_mode}
   ```
   **key absent** (a workspace created before the key existed):
   ```
   Current permissions: autonomous (implicit — key missing, will be written on first change)
   ```
   Both strings are fixed and shared with `/aid-init` and `scripts/aid-config-summary.sh`. The
   preset alone is not the state: `autonomous` as a preset next to `autonomous_mode: false` is
   the contradiction this rendering exists to stop showing.
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

**Reading `active_preset`, including on a workspace that predates the key.** The menu's first
read is `active_preset` from `.aid-o/config/permissions.yaml`. Two cases, and the display
strings are fixed — the same two `/aid-init` seeds and `scripts/aid-config-summary.sh` prints,
so a PM never meets three phrasings of one state:

- key present → `<preset> (preset) — autonomous_mode: <value>`
- key absent → `autonomous (implicit — key missing, will be written on first change)`, and the
  menu offers to write it. Treat the absent key as `autonomous`; do NOT refuse, and do not
  silently rewrite the file just to add the key — it is written on the first change the PM
  actually makes.

If `defaults/policies/permissions.yaml` is missing from the workspace (a consumer project that
has not re-run `/aid-init` since it shipped), read the plugin's own copy at
`{plugin_path}/defaults/policies/permissions.yaml` — the plugin path is always resolvable.

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


**Last Updated:** 2026-08-12
