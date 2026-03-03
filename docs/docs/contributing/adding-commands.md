---
sidebar_position: 3
title: "Adding a Command"
description: "Step-by-step guide to adding a new slash command to the AID plugin."
---

# Adding a Command

AID commands are slash commands that users invoke directly in Claude Code (e.g., `/aid-help`, `/aid-run`). Each command is a single Markdown file in `plugins/aid-orchestrator/commands/`. Claude Code reads the file and executes the instructions it contains.

## v2 Command Structure

AID v2 has 8 commands (reduced from v1's 14) organized around core workflows:

| Command | Purpose | Complexity |
|---------|---------|------------|
| `/aid-do` | Fast mode — small task, minimal overhead | Low |
| `/aid-plan` | Brainstorm → architecture → plan.json | Medium |
| `/aid-run` | Execute full pipeline: READY → EXECUTE → GATES → DONE | High |
| `/aid-status` | Pipeline status, FSM state, queue | Low |
| `/aid-init` | Initialize or upgrade `.aid-o/` workspace | Medium |
| `/aid-audit` | Run project health audit | Medium |
| `/aid-stop` | Emergency stop — save progress | Low |
| `/aid-help` | Progressive help (Level 0-3) | Low |

V2 consolidated several v1 commands:
- `/aid-brainstorm` + `/aid-plan-epic` + `/aid-research` merged into `/aid-plan`
- `/aid-run-epic` + `/aid-first-aid` + `/aid-epic-queue` merged into `/aid-run`
- `/aid-epic-status` + `/aid-analytics` merged into `/aid-status`
- `/aid-setup` functionality absorbed into `/aid-init`

## Anatomy of a Command File

Open `plugins/aid-orchestrator/commands/aid-help.md` to see the full structure. The essential parts are:

### Required Frontmatter

Every command file must start with YAML frontmatter:

```yaml
---
name: aid-help
description: AID documentation and help topics
user_invocable: true
---
```

| Field | Type | Purpose |
|-------|------|---------|
| `name` | string | The command name, without the leading `/`. Must match the filename (minus `.md`). |
| `description` | string | One-line description shown in the Claude Code command picker. |
| `user_invocable` | boolean | Always `true` for user-facing commands. |

### Opening Summary

Immediately after the frontmatter, write one or two sentences explaining what the command does:

```markdown
Show AID documentation — commands, workflow, agent roles, configuration, and FAQ.

AID's self-knowledge command. Explains everything about how AID works, what commands
are available, and how to use the orchestration system.
```

### Usage Section

Document the command's syntax and all accepted arguments:

```markdown
## Usage

\`\`\`
/aid-help [topic]
\`\`\`

**Topics:** `commands`, `workflow`, `agents`, `planning`, `gates`

**Examples:**
\`\`\`
/aid-help                   # full overview
/aid-help commands          # detail on every command
/aid-help workflow          # Plan → Run flow
\`\`\`
```

### Flow / Behavior Section

Describe what Claude should do when the command runs. Use numbered steps, decision trees, or conditional logic as needed. This is the executable specification — Claude follows it literally.

For commands with conditional branches (like `/aid-init`'s fresh-init vs. upgrade logic), use clear headings and numbered steps so Claude can follow the logic unambiguously.

### Script Integration

V2 commands often delegate deterministic work to bash scripts in `plugins/aid-orchestrator/scripts/`. Document which scripts the command invokes:

```markdown
## Script Integration

This command invokes:
- `scripts/aid-fsm.sh` — to transition FSM state
- `scripts/aid-run-gates.sh` — to execute quality gates
```

### Important Section

End the file with an `## Important` section that lists non-negotiable behavioral rules:

```markdown
## Important

- **Fresh init NEVER overwrites** existing files
- **Dynamic file scanning** — do not hardcode the defaults file list
```

## Step-by-Step: Adding a New Command

### 1. Create the File

Create `plugins/aid-orchestrator/commands/aid-{your-command}.md`. Use kebab-case and prefix with `aid-`:

```bash
touch plugins/aid-orchestrator/commands/aid-summarize.md
```

### 2. Write the Frontmatter

```yaml
---
name: aid-summarize
description: Summarize all completed runs into a project summary
user_invocable: true
---
```

### 3. Write the Command Body

Write clear, unambiguous instructions. Claude Code will execute whatever you write here. Structure the body as:

1. **One-paragraph description** of what the command does
2. **`## Usage`** — syntax and arguments
3. **`## Flow`** — step-by-step execution logic
4. **`## Script Integration`** — which bash scripts the command invokes (if any)
5. **`## Important`** — rules Claude must not violate

### 4. Consider Script Delegation

V2 prefers deterministic bash scripts for file I/O, git operations, and gate execution. If your command needs to:
- Read/write YAML or JSON files reliably
- Execute git commands
- Run shell tools and check exit codes

...create a companion script in `plugins/aid-orchestrator/scripts/` and have the command invoke it via the Bash tool. See existing scripts for the pattern.

### 5. Update CHANGELOG

Add an entry to both `CHANGELOG.md` (root) and `plugins/aid-orchestrator/CHANGELOG.md`:

```markdown
## [X.Y.Z] — YYYY-MM-DD

### Added
- **`/aid-summarize` command** — summarizes completed runs into a consolidated
  project summary for retrospective review.
```

### 6. Add Documentation

Add a corresponding documentation page in `docs/docs/commands/aid-{your-command}.md`. Follow the frontmatter convention of existing command docs:

```yaml
---
sidebar_position: 9
title: "/aid-summarize"
description: "Summarize all completed runs into a project summary."
---
```

## Testing a Command

Because AID commands are Markdown files with natural language instructions, "testing" means verifying the command behaves as documented in a real Claude Code session:

1. **Install your local changes** — use the development installation path for your local plugin.
2. **Run the command** with each argument variant documented in `## Usage`.
3. **Verify the output** matches what the `## Flow` section specifies.
4. **Check edge cases** — missing `.aid-o/` workspace, no active runs, invalid arguments.

For commands that modify files (like `/aid-init`), verify that:
- Files are created/updated as documented
- Existing files are not overwritten when they should be preserved
- The workspace structure matches `.aid-o/config/`, `.aid-o/work/`, `.aid-o/tasks/`

For commands that invoke scripts, verify that:
- Scripts are called with the correct arguments
- Script output is captured and presented correctly
- Script failures are handled gracefully (error message to user, not silent failure)

## Conventions Checklist

Before submitting a PR for a new command:

- [ ] Filename is `aid-{name}.md` in kebab-case
- [ ] Frontmatter has `name`, `description`, and `user_invocable: true`
- [ ] Command name in frontmatter matches the filename
- [ ] `## Usage` section with syntax and examples
- [ ] `## Flow` section with numbered, unambiguous steps
- [ ] `## Script Integration` section (if scripts are invoked)
- [ ] `## Important` section with non-negotiable rules
- [ ] CHANGELOG updated (both root and plugin)
- [ ] Documentation page added in `docs/docs/commands/`
