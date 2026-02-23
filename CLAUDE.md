# AID — AI Development Orchestrator

## What is AID?

AID is a Claude Code plugin that implements **Controller + Workers architecture** for AI-driven software development. It takes an EPIC specification, generates structured execution plans, dispatches specialized role-based agents, enforces quality gates, and maintains complete evidence trails.

## Repository Structure

```
ai-orchestrator/
  .claude-plugin/
    marketplace.json            # Marketplace manifest
  plugins/aid-orchestrator/     # The plugin
    .claude-plugin/plugin.json  # Plugin manifest
    agents/                     # 18 specialized agents
    commands/                   # 11 slash commands
    skills/                     # 17 skills (orchestration, brainstorming, gates, etc.)
    defaults/                   # Files copied by /aid-init into target projects
      policies/                 # gates.yaml, decision-policies.yaml, slack-config.yaml, memory-config.yaml
      templates/                # plan.md, epic.md, plan.schema.json, session-*.md
      playbooks/                # 11 role-based playbooks
    README.md                   # Plugin documentation
  CHANGELOG.md                  # Version history
```

## Plugin Installation

```bash
# Add marketplace
/plugin marketplace add marekstancl/claude-aid-o

# Install plugin
/plugin install aid-orchestrator@claude-aid-o

# Verify
/aid-help
```

## What the Plugin Creates in Target Projects

When users run `/aid-init`, it creates:

```
.aid-o/
  01-plans/          # PM + AI brainstorming → plans (archive/ for completed)
  02-epics/          # PM + AI detail → specifications (archive/ for completed)
  03-config/         # PM-customizable (policies, templates, playbooks)
  04-engine/         # AI internal (sessions, memory, backlog, evidence)
```

## Key Commands

| Command | Purpose |
|---------|---------|
| `/aid-init` | Initialize or upgrade .aid-o/ workspace |
| `/aid-setup` | Interactive project onboarding |
| `/aid-help` | Show AID documentation |
| `/aid-plan-epic` | Parse EPIC or Plan → generate Plan JSON |
| `/aid-run-epic` | Run full EPIC orchestration pipeline |
| `/aid-epic-status` | Show pipeline status |
| `/aid-epic-queue` | Manage EPIC execution queue |
| `/aid-audit` | Run project health audit |

## Contributing

- **Language:** English for all plugin code and documentation
- **Plugin manifest:** `plugins/aid-orchestrator/.claude-plugin/plugin.json`
- **Testing:** Use `/plugin validate .` from repo root to validate marketplace

### On Plugin Changes — Mandatory Updates

When modifying plugin files (`plugins/aid-orchestrator/`), always update:

1. **Version numbers** — bump in `plugin.json`, `marketplace.json`, skill headers/footers, plugin README, `aid-help.md`
2. **CHANGELOG.md** — both root and `plugins/aid-orchestrator/CHANGELOG.md` — **must be identical** (see format below)
3. **README.md** — root `README.md` Roadmap section (move current version down, add new), plugin `README.md` version badge
4. **Skill footers** — update `Last Updated` date and version in modified skill files
5. **`defaults/` sync** — if defaults files changed, note in CHANGELOG; `.aid-o/` in target projects will catch up via `/aid-init` upgrade

### CHANGELOG Format Standard

Both CHANGELOGs (`CHANGELOG.md` root and `plugins/aid-orchestrator/CHANGELOG.md`) follow [Keep a Changelog](https://keepachangelog.com/) with this entry format:

```
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
- Every entry starts with `- **Bold Name** — description` (em dash, not colon)
- Description is one sentence, specific enough to understand without reading code
- No trailing Task/Issue IDs in entries (those belong in commit messages, not CHANGELOG)
- Group related changes into a single entry when they form one logical feature
- Root and plugin CHANGELOGs are **always identical** — write one, copy to the other
- Sections appear in order: Added → Changed → Fixed → Removed (omit empty sections)

### README Roadmap Update

When releasing a new version, update the `## Roadmap` section in root `README.md`:

```markdown
## Roadmap

- **vX.Y.Z** (current) — one-line summary of major features in this version
- **vA.B.C** — previous version summary
- ...
```

Keep the 3 most recent versions. Older versions are documented only in CHANGELOG.

## Release Workflow

1. Ensure all feature work is committed on a feature branch
2. Run `/plugin validate .` from repo root
3. Run `claude plugin validate plugins/aid-orchestrator`
4. Bump version in: `plugin.json`, `marketplace.json` (2 places), plugin `README.md`, `aid-help.md`, modified skill headers/footers
5. Write CHANGELOG entry in root `CHANGELOG.md`, copy to `plugins/aid-orchestrator/CHANGELOG.md`
6. Update root `README.md` Roadmap section
7. Commit release: `release: bump version to X.Y.Z`
8. Merge feature branch to main (use `--no-ff` for merge commit)
9. Tag: `git tag vX.Y.Z`
10. Push: `git push && git push --tags`
11. **Sync marketplace cache** (see below)

### Marketplace Cache Sync — MANDATORY after every release

Claude Code loads plugin commands from a **cached copy**, not from this dev repo.
If the cache is stale, commands will be missing new features (e.g., Steps 0.5/0.7 in `/aid-plan-epic`).

**Cache location:** `~/.claude/plugins/cache/claude-aid-o/aid-orchestrator/{version}/`
**Marketplace repo:** `~/.claude/plugins/marketplaces/claude-aid-o/` (git clone of `marekstancl/claude-aid-o`)

**After every release, run these steps:**

```bash
# 1. Sync marketplace repo with dev repo
cd ~/.claude/plugins/marketplaces/claude-aid-o
git pull origin main          # get latest from GitHub (after dev repo pushed)

# 2. Verify version matches
grep '"version"' plugins/aid-orchestrator/.claude-plugin/plugin.json
# Should show the new version

# 3. Force cache rebuild — delete old cache entries
rm -rf ~/.claude/plugins/cache/claude-aid-o/aid-orchestrator/

# 4. Restart Claude Code — it will recreate cache from marketplace repo
# (close and reopen the IDE/terminal session)
```

**Why this is needed:** Claude Code clones the marketplace repo from GitHub, caches a versioned snapshot, and loads commands from cache. If the dev repo is ahead of GitHub (unpushed commits), or if the cache wasn't invalidated after a version bump, Claude Code serves stale commands.

**Verification:** After restart, invoke any updated command (e.g., `/aid-plan-epic`) and check that new features are present in the loaded content.

<!-- AID-O START -->
## AID Orchestrator

This project uses AID for multi-agent orchestration.

**Workspace:** `.aid-o/`
**Commands:** `/aid-help` for full documentation
**Quick start:** `/aid-setup` → create EPIC → `/aid-run-epic`

**Key paths:**
- Plans: `.aid-o/01-plans/`
- EPICs: `.aid-o/02-epics/`
- Config: `.aid-o/03-config/`
- Engine: `.aid-o/04-engine/`
<!-- AID-O END -->
