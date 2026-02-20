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
    commands/                   # 18 slash commands
    skills/                     # 14 skills (orchestration, brainstorming, gates, etc.)
    defaults/                   # Files copied by /aid-init into target projects
      policies/                 # gates.yaml, decision-policies.yaml, slack-config.yaml, memory-config.yaml
      templates/                # plan.md, epic.md, plan.schema.json, session-*.md
      playbooks/                # 11 role-based playbooks
    README.md                   # Plugin documentation
  CHANGELOG.md                  # Version history
  docs/                         # User-facing documentation
    MULTIAGENT_GUIDE.md         # Multi-agent architecture guide
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
| `/aid-init` | Initialize .aid-o/ workspace |
| `/aid-setup` | Interactive project onboarding |
| `/aid-help` | Show AID documentation |
| `/plan-epic` | Parse EPIC or Plan → generate Plan JSON |
| `/run-epic` | Run full EPIC orchestration pipeline |
| `/run-step` | Manually run a single plan step |
| `/run-gates` | Run quality gates |
| `/epic-status` | Show pipeline status |
| `/epic-queue` | Manage EPIC execution queue |

## Contributing

- **Language:** English for all plugin code and documentation
- **Plugin manifest:** `plugins/aid-orchestrator/.claude-plugin/plugin.json`
- **Testing:** Use `/plugin validate .` from repo root to validate marketplace

### On Plugin Changes — Mandatory Updates

When modifying plugin files (`plugins/aid-orchestrator/`), always update:

1. **Version numbers** — bump in `plugin.json`, `marketplace.json`, skill headers/footers, README, `aid-help.md`
2. **CHANGELOG.md** — both root and `plugins/aid-orchestrator/CHANGELOG.md` (keep in sync)
3. **README.md** — both root (Roadmap section) and `plugins/aid-orchestrator/README.md` (if features/commands change)
4. **Skill footers** — update `Last Updated` date in modified skill files

## Release Workflow

1. Ensure all changes are committed
2. Run `/plugin validate .` from repo root to validate marketplace structure
3. Run `claude plugin validate plugins/aid-orchestrator` to validate the plugin
4. Update version in `plugins/aid-orchestrator/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
5. Update `CHANGELOG.md` with new version entry
6. Create git tag: `git tag v{version}`
7. Push: `git push && git push --tags`
