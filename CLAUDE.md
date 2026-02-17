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
    commands/                   # 17 slash commands
    skills/                     # 12 skills (orchestration, gates, session mgmt, etc.)
    defaults/                   # Files copied by /aid-init into target projects
      policies/                 # gates.yaml, decision-policies.yaml, slack-config.yaml
      templates/                # plan.md, epic.md, plan.schema.json, session-*.md
      playbooks/                # 11 role-based playbooks
    README.md                   # Plugin documentation
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
| `/plan-epic` | Parse EPIC → generate Plan JSON |
| `/run-epic` | Run full EPIC orchestration pipeline |
| `/run-step` | Manually run a single plan step |
| `/run-gates` | Run quality gates |
| `/epic-status` | Show pipeline status |
| `/epic-queue` | Manage EPIC execution queue |

## Contributing

- **Language:** English for all plugin code and documentation
- **Plugin manifest:** `plugins/aid-orchestrator/.claude-plugin/plugin.json`
- **Testing:** Use `/plugin validate .` from repo root to validate marketplace
