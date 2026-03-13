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
   - List directory structure (top 2 levels, excluding node_modules, .git, __pycache__, dist, build)
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
{tree output, top 2 levels}

## Conventions
{detected from code: naming style, import patterns, test file locations}

## AID Orchestrator
This project uses AID Orchestrator for task management.
- Workspace: `.aid-o/`
- Quick tasks: `/aid-do "description"`
- Planning: `/aid-plan`
- Execution: `/aid-run`
- Status: `/aid-status`
- Help: `/aid-help`

### Superpowers Conflict Resolution

When `.aid-o/` exists, AID commands replace equivalent Superpowers skills:

| Instead of | Use |
|-----------|-----|
| `superpowers:brainstorming` | `/aid-plan` |
| `superpowers:writing-plans` | `/aid-plan` (auto-delegates to plan-writing skill) |
| `superpowers:executing-plans` | `/aid-run` or `/aid-run --auto` |

Compatible skills (use normally): `test-driven-development`, `verification-before-completion`,
`requesting-code-review`, `systematic-debugging`, `dispatching-parallel-agents`.
```

4. If CLAUDE.md already exists:
   - Check if it has `## AID Orchestrator` section
   - If yes → update only the AID section, preserve everything else
   - If no → append AID section at the end
   - Show diff to PM, ask for approval before writing
5. If CLAUDE.md does not exist → show generated content, ask PM to confirm, then write

## Important

- NEVER overwrite user content in existing CLAUDE.md
- Always show diff/preview before writing
- AID section is clearly delimited so re-runs can find and update it

## Output

```
CLAUDE.md {created|updated}:
  - Project: {name}
  - Stack: {languages}
  - AID section: {added|updated}
```
