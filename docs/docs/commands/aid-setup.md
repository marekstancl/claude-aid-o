---
sidebar_position: 12
title: "/aid-setup"
description: "Interactive project onboarding — detect tech stack and configure AID"
---

# /aid-setup

Interactive project onboarding: AID scans your project's tech stack, presents a full analysis, and configures itself to match your tooling. This is the recommended first step for new projects, run after [`/aid-init`](./aid-init).

## Usage

```bash
/aid-setup
```

No arguments — runs in the current project root.

## Prerequisites

- Run in the root directory of your project (where `package.json`, `pyproject.toml`, `Cargo.toml`, etc. live)
- `.aid-o/` workspace is recommended but not required (Option 1 initializes it if missing)

## How It Works

### Step 1: Project Detection

AID scans indicator files to build a complete picture of your project:

| Detected | Examples |
|----------|---------|
| **Language** | TypeScript, Python, Go, Rust, Ruby, Java |
| **Framework** | Next.js, React, FastAPI, Django, Flask, Rails, Spring Boot |
| **Test framework** | Jest, Vitest, Pytest, Mocha, Cypress, Playwright |
| **Linter** | ESLint, Prettier, Ruff, Pylint, mypy |
| **CI/CD** | GitHub Actions, GitLab CI |
| **Database** | PostgreSQL, MongoDB (detected from docker-compose or deps) |
| **Docs platform** | Docusaurus, MkDocs, Sphinx, VitePress, mdBook |
| **Git** | Branch, remote URL, hosting (GitHub/GitLab/Bitbucket), visibility, organization |

### Step 2: Project Type Classification

Based on the scan, your project is classified as: Single app, Monorepo (split), Monorepo (workspace), Python project, Systems project, Custom, or New project.

### Step 3: Analysis Display

AID presents its findings for your review before asking you to choose setup options.

### Step 4: Setup Options

You can configure any combination of the following options:

| Option | Description | Recommended |
|--------|-------------|-------------|
| 1. Initialize `.aid-o/` | Create workspace directory structure | Always |
| 2. Customize `gates.yaml` | Set test/lint/security gate commands for your stack | Yes |
| 3. Populate `project-profile.yaml` | Save tech stack for agent context | Yes |
| 4. Generate/update `CLAUDE.md` | Add AID commands reference to CLAUDE.md | If desired |
| 5. Add `.aid-o/` to `.gitignore` | Exclude engine internals from version control | Yes |
| 6a. Qdrant MCP | Cross-project vector knowledge base | Recommended |
| 6b. Context7 MCP | Framework documentation via MCP | Recommended |
| 6c. Slack MCP | PM communication via Slack messages | If desired |
| 6d. Docker MCP | Container management via MCP | If desired |
| 7. Permission preset | Safe / Recommended / Advanced | Recommended preset |
| 8. Document language | Language for generated plans and EPICs (default: EN) | EN |
| 9. Parallel isolation strategy | Worktrees / Branches / Sequential | Worktrees |
| 10. Documentation platform setup | Scaffold docs directory and config | If no docs platform |
| 11. Skill conflict detection | Scan for plugin conflicts and auto-deny them | Yes |

When prompted, you can choose:
- **(A) All recommended** — applies the most useful options automatically
- **(B) Let me pick** — choose specific options by number
- **(C) Everything** — applies all options

## Gates Configuration (Option 2)

AID maps your detected tooling to the correct gate commands:

| Detected | Gate | Command |
|----------|------|---------|
| pytest | `tests_pass` | `pytest -q --tb=short` |
| jest | `tests_pass` | `npx jest --ci` |
| vitest | `tests_pass` | `npx vitest run` |
| ruff | `lint_pass` | `ruff check . && ruff format --check .` |
| eslint + prettier | `lint_pass` | `npx eslint . && npx prettier --check .` |
| TypeScript | `type_check` | `npx tsc --noEmit` |
| npm build script | `build_pass` | `npm run build` |

A diff of proposed changes is shown before anything is applied.

## MCP Server Onboarding (Option 6)

Qdrant is strongly recommended — it is the cross-project knowledge base that allows AID to reuse lessons, patterns, and decisions across all your projects. Without Qdrant, knowledge stays within a single run.

The setup wizard guides you through installing and configuring each MCP server in `~/.claude/claude_desktop_config.json`.

## Notes

- Option 1 (initialize `.aid-o/`) automatically configures `.gitignore` for runtime artifacts — Option 5 remains available for manual re-runs
- `.gitignore` is always appended to, never overwritten
- All gates configuration changes are previewed before application

## Related

- [`/aid-init`](./aid-init) — initialize or upgrade the workspace (without interactive onboarding)
- [`/aid-help`](./aid-help) — full AID documentation and workflow overview
- [`/aid-brainstorm`](./aid-brainstorm) — start your first feature brainstorm after setup
