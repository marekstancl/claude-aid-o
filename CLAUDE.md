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
    agents/                     # 7 controller agents
    commands/                   # 8 slash commands
    skills/                     # 8 core skills (+ extras outside manifest)
    scripts/                    # Bash controller layer
      aid-fsm.sh                # 6-state deterministic FSM
      aid-run-gates.sh          # Quality gate runner
      aid-release.sh            # Version bump + tag automation
      aid-auto-pipeline.sh      # Master orchestration (Plan → EPICs → plan.json → run → queue)
      aid-plan-to-epic.sh       # Plan.md → EPIC.md
      aid-epic-to-json.sh       # EPIC.md → plan.json
      aid-json-to-run.sh        # plan.json → run.md
      aid-queue-add.sh          # EPIC → queue entry
      lib/                      # aid-stage-log.sh, aid-token-count.sh, common.sh
      gates/scope-check.sh      # Scope validation gate
    defaults/                   # Files copied by /aid-init into target projects
      execution.yaml            # Gates + dispatch config
      orchestration.yaml        # Controller settings
      integrations.yaml         # External service config
      templates/                # plan.md, epic.md, plan.schema.json
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
  plans/             # PM + AI brainstorming → plans (archive/ for completed)
  tasks/             # PM + AI detail → EPIC specifications (archive/ for completed)
  config/            # PM-customizable (policies, templates, playbooks)
  work/              # AI internal (active, backlog, evidence, timeline)
```

## Key Commands

| Command | Purpose |
|---------|---------|
| `/aid-do [task]` | Fast Mode — implement small task with < 2 min overhead |
| `/aid-plan [topic]` | Brainstorm → architecture → plan.json |
| `/aid-run [id]` | Execute full pipeline: READY → EXECUTE → GATES → DONE |
| `/aid-status [id]` | Pipeline status, FSM state, queue |
| `/aid-init` | Initialize or upgrade .aid-o/ workspace (10-file structure) |
| `/aid-audit` | Run project health audit |
| `/aid-stop` | Emergency stop — save progress |
| `/aid-help [topic]` | Progressive help (Level 0–3) |

## Contributing

- **Language:** English for all plugin code and documentation
- **Plugin manifest:** `plugins/aid-orchestrator/.claude-plugin/plugin.json`
- **Testing:** Use `/plugin validate .` from repo root to validate marketplace

### On Plugin Changes — Mandatory Updates

When modifying plugin files (`plugins/aid-orchestrator/`), always update:

1. **CHANGELOG.md** — both root and `plugins/aid-orchestrator/CHANGELOG.md` — **must be identical** (see format below)
2. **`Last Updated` date** — in modified skill files (footer `**Last Updated:** YYYY-MM-DD`)
3. **`defaults/` sync** — if defaults files changed, note in CHANGELOG; `.aid-o/` in target projects will catch up via `/aid-init` upgrade

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

## Version Management

### Single Source of Truth

The **CHANGELOG header** (`## [X.Y.Z]`) is the single source of truth for the plugin version.
Individual skill/agent/command files do NOT contain version numbers — only `**Last Updated:**` dates.

### Version File Registry — ALL files that contain a version number

Every push to main MUST ensure these 8 locations are in sync:

| # | File | Field | Update Method |
|---|------|-------|---------------|
| 1 | `CHANGELOG.md` | `## [X.Y.Z]` header | Manual (source of truth) |
| 2 | `plugins/aid-orchestrator/CHANGELOG.md` | `## [X.Y.Z]` header | Manual (copy of #1) |
| 3 | `.claude-plugin/marketplace.json` | `metadata.version` | JSON field |
| 4 | `.claude-plugin/marketplace.json` | `plugins[0].version` | JSON field |
| 5 | `plugins/aid-orchestrator/.claude-plugin/plugin.json` | `version` | JSON field |
| 6 | `plugins/aid-orchestrator/README.md` | `- **Plugin:** X.Y.Z` | Regex |
| 7 | `README.md` | `- **vX.Y.Z** (current)` | Regex |
| 8 | `README.md` | `AGPL-3.0-only — see [LICENSE](LICENSE)` | Exact |

These are also defined in `defaults/policies/release-policy.yaml` → `version_files[]`.
The Release Sub-Phase in `skills/pipeline.md` §7 automates this during EPIC runs.

**Pre-push check:** Before every `git push`, verify all 8 files show the same version:
```bash
grep -n '"version"' .claude-plugin/marketplace.json plugins/aid-orchestrator/.claude-plugin/plugin.json
grep -n 'Plugin:' plugins/aid-orchestrator/README.md
grep -n '(current)' README.md
head -6 CHANGELOG.md plugins/aid-orchestrator/CHANGELOG.md
```

## Release Workflow

1. Write CHANGELOG entry in root `CHANGELOG.md` with new `## [X.Y.Z]` header
2. Copy entry to `plugins/aid-orchestrator/CHANGELOG.md` (must be identical)
3. Bump version in all 6 remaining files (#3-#8 from registry above)
4. Update root `README.md` Roadmap section (add new version line, move previous down)
5. Commit: `release: vX.Y.Z — one-line summary`
6. Tag: `git tag vX.Y.Z`
7. GitHub Release: `gh release create vX.Y.Z --title "vX.Y.Z — summary" --notes "{CHANGELOG section for this version}"`
8. Push: `git push && git push --tags`
9. **Update plugin in all projects** (see below)

### Plugin Update — MANDATORY after every push

After pushing to GitHub, update the plugin cache in every project that uses it:

```bash
# Step 1: Try the standard update command
claude plugin update aid-orchestrator@claude-aid-o

# Step 2: If step 1 reports "already at latest" but version is wrong, force-refresh:
git -C ~/.claude/plugins/marketplaces/claude-aid-o fetch origin && git -C ~/.claude/plugins/marketplaces/claude-aid-o reset --hard origin/main
```

Then restart Claude Code (close and reopen IDE/terminal) to load the new version.

**Why:** Claude Code caches plugins as shallow git clones in `~/.claude/plugins/marketplaces/`.
The `plugin update` command runs `git fetch` but may not update the working tree (known issue).
The force-refresh command resets the cached clone to match the remote.

**Verification:** After restart, run `/aid-help` and check the version matches.

<!-- AID-O START -->
## AID Orchestrator

This project uses AID v2.0 for multi-agent orchestration.

**Workspace:** `.aid-o/`
**Commands:** `/aid-help` for full documentation
**Quick start:** `/aid-init` → `/aid-plan "topic"` → `/aid-run`
**Fast mode:** `/aid-do "small task"` (< 2 min overhead)

**Key paths:**
- Plans: `.aid-o/plans/`
- Tasks: `.aid-o/tasks/`
- Config: `.aid-o/config/`
- Work: `.aid-o/work/`
<!-- AID-O END -->

## Ecosystem pravidla (závazná)

Tento projekt je součástí VULCAN ekosystému. Následující dokumenty jsou závazné:

- **Ecosystem Docs:** `http://10.0.77.10:8800`
- **Guardrails:** `http://10.0.77.10:8800/ecosystem/guardrails`
- **Architektonicka rozhodnuti:** `http://10.0.77.10:8800/ecosystem/decisions`
- **Infrastruktura:** `http://10.0.77.10:8800/ecosystem/infrastructure`
- **MCP Servery:** `http://10.0.77.10:8800/ecosystem/mcp-servers`

Klíčová pravidla:
- G-008: Port rozsah 3910-3919, offset +1 = app (3911). Host port = interní port.
- G-009: docker-compose.yml pouze vlastní služby, shared-infra network external.
- G-015: Jeden Dockerfile (prod-ready), docker-compose.override.yml pro dev.
