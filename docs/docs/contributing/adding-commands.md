---
sidebar_position: 3
title: "Adding a Command"
description: "Step-by-step guide to adding a new slash command to the AID plugin."
---

# Adding a Command

AID commands are slash commands that users invoke directly in Claude Code (e.g., `/aid-help`, `/aid-run-epic`). Each command is a single Markdown file in `plugins/aid-orchestrator/commands/`. Claude Code reads the file and executes the instructions it contains.

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

Immediately after the frontmatter, write one or two sentences explaining what the command does. This is the text Claude reads first before executing:

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

**Topics:** `commands`, `workflow`, `epic`, `agents`, `planning`, `gates`

**Examples:**
\`\`\`
/aid-help                   # full overview
/aid-help commands          # detail on every command
/aid-help workflow          # Plan → EPIC → Run flow
\`\`\`
```

### Flow / Behavior Section

Describe what Claude should do when the command runs. Use numbered steps, decision trees, or conditional logic as needed. This is the executable specification — Claude follows it literally.

For example, from `aid-help.md`:

```markdown
## Flow

### Step 1: Check Environment

1. Check if `.aid-o/` exists in current project
2. If exists: note active EPICs count, runs count (for dynamic info)
```

For commands that have conditional branches (like `aid-init`'s fresh-init vs. upgrade logic), use clear headings and numbered steps so Claude can follow the logic unambiguously.

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
description: Summarize all completed EPIC runs into a project summary
user_invocable: true
---
```

### 3. Write the Command Body

Write clear, unambiguous instructions. Claude Code will execute whatever you write here. Structure the body as:

1. **One-paragraph description** of what the command does
2. **`## Usage`** — syntax and arguments
3. **`## Flow`** — step-by-step execution logic
4. **`## Important`** — rules Claude must not violate

### 4. Register in `plugin.json`

Open `plugins/aid-orchestrator/.claude-plugin/plugin.json`. Commands are not explicitly registered in `plugin.json` (Claude Code discovers them automatically from the `commands/` directory), but the plugin manifest's `description` and `keywords` may need updating if you are adding a significant new capability.

### 5. Update CHANGELOG

Add an entry to both `CHANGELOG.md` (root) and `plugins/aid-orchestrator/CHANGELOG.md`:

```markdown
## [X.Y.Z] — YYYY-MM-DD

### Added
- **`/aid-summarize` command** — summarizes completed EPIC runs into a consolidated
  project summary for retrospective review.
```

### 6. Add Documentation

Add a corresponding documentation page in `docs/docs/commands/aid-{your-command}.md`. Follow the frontmatter convention of existing command docs:

```yaml
---
sidebar_position: 14
title: "/aid-summarize"
description: "Summarize all completed EPIC runs into a project summary."
---
```

## Testing a Command

Because AID commands are Markdown files with natural language instructions, "testing" means verifying the command behaves as documented in a real Claude Code session:

1. **Install your local changes** — use the development installation path for your local plugin.
2. **Run the command** with each argument variant documented in `## Usage`.
3. **Verify the output** matches what the `## Flow` section specifies.
4. **Check edge cases** — missing `.aid-o/` workspace, no active EPICs, invalid arguments.

For commands that modify files (like `/aid-init`), verify that:
- Files are created/updated as documented
- Existing files are not overwritten when they should be preserved
- The CLAUDE.md marker-based merge works correctly (if applicable)

## Conventions Checklist

Before submitting a PR for a new command:

- [ ] Filename is `aid-{name}.md` in kebab-case
- [ ] Frontmatter has `name`, `description`, and `user_invocable: true`
- [ ] Command name in frontmatter matches the filename
- [ ] `## Usage` section with syntax and examples
- [ ] `## Flow` section with numbered, unambiguous steps
- [ ] `## Important` section with non-negotiable rules
- [ ] CHANGELOG updated (both root and plugin)
- [ ] Documentation page added in `docs/docs/commands/`
