---
sidebar_position: 1
title: "How to Contribute"
description: "Fork, branch, develop, and submit a PR — the AID contribution workflow."
---

# How to Contribute

AID is licensed under [AGPL-3.0-only](https://www.gnu.org/licenses/agpl-3.0.html). Contributions are welcome via pull requests on GitHub.

## Before You Start

- Read the existing documentation and source files in `plugins/aid-orchestrator/` to understand how the plugin is structured.
- Check open issues and existing PRs to avoid duplicating work.
- For significant changes — new agents, new skills, new commands — open an issue first to discuss the design before writing code.

## Contribution Workflow

### 1. Fork the Repository

Fork `marekstancl/ai-orchestrator` on GitHub. Clone your fork locally:

```bash
git clone https://github.com/YOUR_USERNAME/ai-orchestrator.git
cd ai-orchestrator
```

### 2. Create a Branch

Branch from `main`. Name branches descriptively using kebab-case:

```bash
git checkout -b add-summarizer-agent
git checkout -b fix-gates-yaml-validation
git checkout -b docs-contributing-guide
```

Branch prefixes are not enforced by a hook, but the convention is:

| Prefix | Purpose |
|--------|---------|
| `add-` | New agent, command, skill, or feature |
| `fix-` | Bug fix |
| `docs-` | Documentation-only change |
| `refactor-` | Internal restructuring with no behavior change |
| `release-` | Version bump and release prep |

### 3. Develop

Make your changes inside `plugins/aid-orchestrator/`. The `plugins/` directory is where all plugin content lives. Do not modify files outside of it unless you are updating the root `README.md`, root `CHANGELOG.md`, or the marketplace manifest.

**Mandatory updates when modifying plugin files:**

When you change any file inside `plugins/aid-orchestrator/`, you must also:

1. Update `CHANGELOG.md` (root) and `plugins/aid-orchestrator/CHANGELOG.md` — these two files must always be identical. See [CHANGELOG Format](#changelog-format) below.
2. Update the `**Last Updated:**` footer date on any skill file you modified.
3. If you changed files under `defaults/` (policies, templates, playbooks), note the change in the CHANGELOG — projects that run `/aid-init --upgrade` will receive the updated defaults automatically.

### 4. Commit

Follow the conventional commit format the project uses throughout:

```
type(scope): description (YYYY-MM-DD HH:MM TZ)
```

**Types:**

| Type | When to use |
|------|-------------|
| `feat` | New agent, command, skill, or user-visible feature |
| `fix` | Bug fix |
| `docs` | Documentation-only changes |
| `refactor` | Code restructuring, no behavior change |
| `chore` | Tooling, CI, version bumps |
| `release` | Version releases (combines version bump + CHANGELOG) |

**Examples:**

```
feat(agents): add summarizer agent for EPIC output condensation (2026-02-26 14:30 UTC)
fix(gates): correct timeout_seconds type validation in gates.yaml (2026-02-26 09:15 UTC)
docs(contributing): add how-to-contribute guide (2026-02-26 18:00 UTC)
release: v0.9.4 — add summarizer agent and fix gate validation (2026-02-26 20:00 UTC)
```

Keep commits atomic — one logical change per commit. Do not bundle unrelated changes.

### 5. Open a Pull Request

Push your branch and open a PR against `main`:

```bash
git push origin add-summarizer-agent
gh pr create --title "feat(agents): add summarizer agent" \
  --body "Adds a summarizer agent for condensing EPIC outputs. ..."
```

In the PR description, explain:
- What you changed and why
- Which acceptance criteria or issue the PR addresses
- How to test the change (e.g., install the plugin and run a specific command)

### 6. Review Process

All PRs are reviewed by a maintainer. The review checks:

- **Correctness** — does the code/content do what it claims?
- **Consistency** — does it match the style and conventions of the surrounding code?
- **Completeness** — are the CHANGELOG and `Last Updated` dates updated?
- **Functionality** — for new agents or commands, is the behavior well-defined and consistent with how existing agents work?

Expect at least one round of feedback. Address review comments with new commits on the same branch — do not force-push after a review has started, as it makes the diff history hard to follow.

Once approved, a maintainer merges the PR using a squash-merge or merge commit (depending on the size of the change).

## CHANGELOG Format

Both `CHANGELOG.md` (root) and `plugins/aid-orchestrator/CHANGELOG.md` must always be identical. The format follows [Keep a Changelog](https://keepachangelog.com/):

```markdown
## [X.Y.Z] — YYYY-MM-DD

### Added
- **Feature Name** — description of what was added and why it matters

### Changed
- **Component Name** — what changed and the effect

### Fixed
- **Bug Name** — what was broken and how it was fixed

### Removed
- **Component Name** — what was removed and why
```

**Rules:**
- Every entry starts with `- **Bold Name** —` (em dash, not colon)
- Description is one sentence, specific enough to understand without reading code
- No trailing issue IDs in entries (those belong in commit messages)
- Group related changes into a single entry when they form one logical feature
- Sections appear in order: Added, Changed, Fixed, Removed (omit empty sections)
- Write from the user's perspective: "Added pagination to the users list API" rather than "Implemented PaginationService"

## Version Numbers

The CHANGELOG header (`## [X.Y.Z]`) is the single source of truth for the plugin version. When preparing a release, you must update all eight version locations listed in `CLAUDE.md`. If you are not preparing a release, do not bump version numbers — only maintainers cut releases.

## License

By submitting a pull request, you agree that your contribution will be licensed under AGPL-3.0-only, the same license as the project. There is no CLA to sign. The standard GitHub contribution workflow (fork + PR) serves as your agreement to the license terms.
