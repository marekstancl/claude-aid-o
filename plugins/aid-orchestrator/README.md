# AID — AI Development Orchestrator

- **Plugin:** 2.10.0
- **License:** AGPL-3.0-only
- **Requires:** Claude Code with plugin support

## Overview

AID is a Claude Code plugin implementing Controller + Workers architecture for AI-driven software development. It takes a task or EPIC specification, generates structured execution plans, dispatches specialized role-based agents, enforces quality gates via a 6-state bash FSM, and maintains complete evidence trails.

## Quick Start

```bash
# Install from marketplace
/plugin marketplace add marekstancl/claude-aid-o
/plugin install aid-orchestrator@claude-aid-o

# Initialize workspace
/aid-init

# Fast mode (small tasks)
/aid-do "fix the login bug"

# Full pipeline (complex tasks)
/aid-plan "add user authentication"
/aid-run --auto
```

## Documentation

- `/aid-help` — progressive help (Level 0-3)
- `CHANGELOG.md` — version history
- `scripts/README.md` — bash script documentation
