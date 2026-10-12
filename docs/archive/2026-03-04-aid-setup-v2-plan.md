# `/aid-setup` v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add modular `/aid-setup` command with 4 skill modules (permissions, integrations, claude-md, project-scan) to the AID Orchestrator plugin.

**Architecture:** Thin command router (`aid-setup.md`) dispatches to independent skill modules in `skills/setup/`. Each module reads/writes specific config files. No shared state between modules.

**Tech Stack:** Markdown command/skill files (Claude Code plugin format), YAML config files.

---

### Task 1: Update permissions.yaml defaults — add `autonomous` preset

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/policies/permissions.yaml`

**Step 1: Read current permissions.yaml**

Read `defaults/policies/permissions.yaml` to confirm current structure (aspirin + steroids presets).

**Step 2: Add `autonomous` preset between aspirin and steroids**

Add new preset. Key differences from aspirin:
- `Bash(*:*)` allowed (like steroids)
- All MCP tools allowed
- `auto_commit: true`, `auto_push: false`

Key differences from steroids:
- Destructive commands on deny list
- `auto_push: false`

```yaml
  autonomous:
    description: "Max autonomy without destructive operations. Recommended default."
    claude_code_permissions:
      - "Glob"
      - "Grep"
      - "Read"
      - "Edit"
      - "Write"
      - "NotebookEdit"
      - "Task"
      - "TodoWrite"
      - "WebSearch"
      - "WebFetch"
      - "Bash(*:*)"
      # MCP tools
      - "mcp__qdrant-memory__qdrant-store(*)"
      - "mcp__qdrant-memory__qdrant-find(*)"
      - "mcp__shared-github__*(*)"
      - "mcp__shared-minio__*(*)"
      - "mcp__shared-docker__*(*)"
      - "mcp__shared-playwright__*(*)"
      - "mcp__plugin_context7_context7__*(*)"
    claude_code_deny:
      - "Bash(rm -rf:*)"
      - "Bash(git push --force:*)"
      - "Bash(git push -f:*)"
      - "Bash(git reset --hard:*)"
      - "Bash(git clean -fd:*)"
      - "Bash(DROP TABLE:*)"
      - "Bash(DELETE FROM:*)"
      - "Bash(kill -9:*)"
      - "Bash(chmod 777:*)"
    notes: |
      Autonomous but safe. Agents can do anything except destructive operations.
      auto_commit: true, auto_push: false. PM reviews before push.
```

Change `active_preset: "aspirin"` → `active_preset: "autonomous"`.

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/defaults/policies/permissions.yaml
git commit -m "feat: add autonomous permissions preset as new default"
```

---

### Task 2: Create `skills/setup/` directory and permissions module

**Files:**
- Create: `plugins/aid-orchestrator/skills/setup/permissions.md`

**Step 1: Create directory**

```bash
mkdir -p plugins/aid-orchestrator/skills/setup
```

**Step 2: Write permissions.md**

```markdown
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
     (2) steroids — unrestricted, everything allowed
         auto_commit: true, auto_push: true
     (3) custom — configure each setting manually
   ```
4. If PM chooses (3) custom, ask interactively:
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
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/skills/setup/permissions.md
git commit -m "feat: add setup permissions module"
```

---

### Task 3: Create integrations module

**Files:**
- Create: `plugins/aid-orchestrator/skills/setup/integrations.md`

**Step 1: Write integrations.md**

```markdown
---
name: setup-integrations
description: Detect and configure MCP server integrations for AID
---

# Setup Module: Integrations

Detect installed MCP servers and enable/disable them in AID.

## Input

Called by `/aid-setup` router or `/aid-setup integrations`.

## Flow

1. Read `.claude/settings.json` — extract `mcpServers` keys
2. Read `.aid-o/config/integrations.yaml` — extract current enabled state
3. Build MCP status table:

For each MCP server found in settings.json:
- Check if it's in integrations.yaml → show [enabled] or [disabled]
- If not in integrations.yaml → show [available]

Present to PM:
```
MCP Integrations:
  [enabled]    qdrant-memory — project memory & semantic search
  [disabled]   context7 — library documentation lookup
  [available]  shared-docker — container management
  [available]  shared-slack — Slack notifications

  Not installed (install via .claude/settings.json):
  [not found]  shared-playwright — browser automation
```

4. For each [disabled] or [available] MCP → ask PM: "Enable {name}? (y/N)"
5. For each [enabled] MCP → ask PM: "Keep {name} enabled? (Y/n)"

6. Write updated `config/integrations.yaml`:
   - Set `enabled: true/false` for each integration section
   - If MCP name matches a known section (slack, memory, knowledge) → update that section
   - If MCP is unknown → add a generic `custom_mcps:` entry

## Known MCP Mappings

| MCP Server Key | integrations.yaml Section | Description |
|---|---|---|
| `qdrant-memory` or `qdrant-brain` | `memory:` | Qdrant semantic search |
| `*context7*` | `knowledge:` + `knowledge.context7:` | Library docs |
| `*slack*` | `slack:` | PM notifications |
| `*docker*` | (no section — just note) | Container management |
| `*playwright*` | (no section — just note) | Browser testing |
| `*github*` | (no section — just note) | GitHub API |
| Other | `custom_mcps:` | Generic entry |

## Output

```
Integrations updated:
  enabled: qdrant-memory, context7
  disabled: shared-slack
Written to: .aid-o/config/integrations.yaml
```
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/skills/setup/integrations.md
git commit -m "feat: add setup integrations module"
```

---

### Task 4: Create claude-md module

**Files:**
- Create: `plugins/aid-orchestrator/skills/setup/claude-md.md`

**Step 1: Write claude-md.md**

```markdown
---
name: setup-claude-md
description: Generate or update CLAUDE.md with project context for Claude Code
---

# Setup Module: CLAUDE.md Generation

Generate project-aware CLAUDE.md so Claude Code understands the project.

## Input

Called by `/aid-setup` router or `/aid-setup claude-md`.

## Flow

1. Read `config/project.yaml` — get project_name, languages, test_cmd, lint_cmd, build_cmd
2. Scan project root:
   - Read `package.json`, `pyproject.toml`, `Cargo.toml` etc. for dependencies
   - Read directory structure (top 2 levels)
   - Read existing CLAUDE.md if present
3. Generate CLAUDE.md content with these sections:

```markdown
# {project_name}

## Project Overview
{type} project using {languages}.

## Development Commands
- Test: `{test_cmd}`
- Lint: `{lint_cmd}`
- Build: `{build_cmd}`

## Project Structure
{tree output, top 2 levels, excluding node_modules/.git/etc}

## Conventions
{detected from code: naming, import style, test patterns}

## AID Orchestrator
This project uses AID Orchestrator for task management.
- Workspace: `.aid-o/`
- Commands: `/aid-do`, `/aid-plan`, `/aid-run`, `/aid-status`
- Config: `.aid-o/config/`
```

4. If CLAUDE.md already exists:
   - Check if it has `## AID Orchestrator` section
   - If yes → update only the AID section
   - If no → append AID section at the end
   - Show diff to PM, ask for approval before writing
5. If CLAUDE.md does not exist → write full generated content

## Output

```
CLAUDE.md {created|updated}:
  - Project: {name}
  - Stack: {languages}
  - AID section: {added|updated}
```
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/skills/setup/claude-md.md
git commit -m "feat: add setup claude-md module"
```

---

### Task 5: Create project-scan module

**Files:**
- Create: `plugins/aid-orchestrator/skills/setup/project-scan.md`

**Step 1: Write project-scan.md**

```markdown
---
name: setup-project-scan
description: Re-detect project stack and update config/project.yaml
---

# Setup Module: Project Scan

Re-detect project tech stack and update project.yaml.

## Input

Called by `/aid-setup` router or `/aid-setup scan`.

## Flow

1. Read current `config/project.yaml`
2. Scan project root for stack indicators:

| File | Detected | Fields |
|------|----------|--------|
| `package.json` | Node.js/TypeScript | languages, test_cmd, lint_cmd, build_cmd |
| `tsconfig.json` | TypeScript | languages += TypeScript |
| `pyproject.toml` | Python | languages, test_cmd, lint_cmd |
| `Cargo.toml` | Rust | languages, test_cmd, build_cmd |
| `go.mod` | Go | languages, test_cmd, lint_cmd, build_cmd |
| `pom.xml` | Java/Kotlin | languages, test_cmd, build_cmd |
| `docker-compose.yml` | Docker | note in project.yaml |
| `.github/workflows/` | CI/CD | note in project.yaml |

3. Compare detected values with existing project.yaml
4. Show diff to PM:
   ```
   Project scan results:
     languages: [TypeScript, Python] → [TypeScript, Python, Go] (CHANGED)
     test_cmd: "npm test" (unchanged)
     lint_cmd: "npm run lint" (unchanged)
     build_cmd: null → "go build ./..." (NEW)

   Apply changes? (Y/n)
   ```
5. On approval → write updated `config/project.yaml`
6. Update `scanned_at` timestamp

## Output

```
Project scan complete:
  {N} fields updated, {M} unchanged
Written to: .aid-o/config/project.yaml
```
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/skills/setup/project-scan.md
git commit -m "feat: add setup project-scan module"
```

---

### Task 6: Create the router command `aid-setup.md`

**Files:**
- Create: `plugins/aid-orchestrator/commands/aid-setup.md`

**Step 1: Write aid-setup.md**

```markdown
---
name: aid-setup
description: Modular project configuration — permissions, integrations, CLAUDE.md, stack scan
user_invocable: true
---

Configure AID for this project. Modular — run all or pick one module.

## Usage

```
/aid-setup                    # interactive menu
/aid-setup permissions        # configure permission preset
/aid-setup integrations       # enable/disable MCP integrations
/aid-setup claude-md          # generate/update CLAUDE.md
/aid-setup scan               # re-detect project stack
/aid-setup all                # run all modules sequentially
```

## Prerequisites

`.aid-o/` must exist. If not, run `/aid-init` first.

```
CHECK: Does .aid-o/config/project.yaml exist?
  NO  → "Workspace not initialized. Run /aid-init first." → EXIT
  YES → continue
```

## Routing

Parse `$ARGUMENTS`:

| Argument | Action |
|----------|--------|
| (empty) | Show menu, ask PM to pick |
| `permissions` | Read `skills/setup/permissions.md`, execute |
| `integrations` | Read `skills/setup/integrations.md`, execute |
| `claude-md` | Read `skills/setup/claude-md.md`, execute |
| `scan` | Read `skills/setup/project-scan.md`, execute |
| `all` | Execute sequentially: scan → permissions → integrations → claude-md |

## Interactive Menu

When no argument provided:

```
AID Setup — Project Configuration
==================================
  (1) Permissions     — choose autonomy level (current: {active_preset})
  (2) Integrations    — enable MCP servers (current: {enabled_count} enabled)
  (3) CLAUDE.md       — generate project context file
  (4) Project Scan    — re-detect tech stack
  (A) All             — run everything (recommended for first setup)
  (0) Exit

Select:
```

Read `active_preset` from `config/permissions.yaml` for current display.
Count enabled integrations from `config/integrations.yaml` for display.

## Module Execution

For each module:
1. Read the skill file from `skills/setup/{module}.md`
2. Follow its Flow section exactly
3. Report result
4. If running `all` → continue to next module

## After All Modules

```
Setup complete. Configuration written to:
  - .aid-o/config/permissions.yaml
  - .aid-o/config/integrations.yaml
  - .claude/settings.local.json
  - CLAUDE.md (if selected)
  - .aid-o/config/project.yaml (if scanned)
```
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-setup.md
git commit -m "feat: add /aid-setup command router"
```

---

### Task 7: Update aid-help.md — add /aid-setup references

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-help.md`

**Step 1: Read aid-help.md to find where commands are listed**

Read the full file and find the command listing sections at each level.

**Step 2: Add /aid-setup to appropriate help levels**

- Level 0 (Getting Started): Add `/aid-setup` right after `/aid-init`:
  ```
  /aid-init   — initialize workspace
  /aid-setup  — configure permissions, integrations, CLAUDE.md
  ```
- Level 2 (Configuration): Add detailed `/aid-setup` section with sub-commands

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-help.md
git commit -m "docs: add /aid-setup to help documentation"
```

---

### Task 8: Update aid-init.md — suggest /aid-setup after init

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-init.md`

**Step 1: Add post-init suggestion**

At the end of the init flow (after "Summary: N created, M already existed"), add:

```
Next step: Run /aid-setup to configure permissions, integrations, and generate CLAUDE.md.
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-init.md
git commit -m "docs: suggest /aid-setup after init completion"
```

---

### Task 9: Final verification and combined commit

**Step 1: Verify all files exist**

```bash
ls -la plugins/aid-orchestrator/commands/aid-setup.md
ls -la plugins/aid-orchestrator/skills/setup/permissions.md
ls -la plugins/aid-orchestrator/skills/setup/integrations.md
ls -la plugins/aid-orchestrator/skills/setup/claude-md.md
ls -la plugins/aid-orchestrator/skills/setup/project-scan.md
```

**Step 2: Verify permissions.yaml has 3 presets**

```bash
grep "aspirin\|autonomous\|steroids" plugins/aid-orchestrator/defaults/policies/permissions.yaml
```

**Step 3: Verify aid-help references /aid-setup**

```bash
grep "aid-setup" plugins/aid-orchestrator/commands/aid-help.md
```

**Step 4: Grep for stale references**

```bash
grep -rn "aid-setup" plugins/aid-orchestrator/ | grep -v CHANGELOG | grep -v "commands/aid-setup.md"
```

Ensure no stale v1 `/aid-setup` references remain (except in CHANGELOG which is historical).
