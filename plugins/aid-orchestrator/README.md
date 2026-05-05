# AID — AI Development Orchestrator

- **Plugin:** 2.10.0
- **License:** AGPL-3.0-only
- **Requires:** Claude Code with plugin support

## Requirements

System binaries used at runtime:

| Tool | Version | Required for | Install |
|------|---------|--------------|---------|
| `bash` | ≥ 4.0 | All FSM scripts | OS default |
| `git` | ≥ 2.20 | Branch enforcement, worktree handling | `apt install git` / `brew install git` |
| `jq` | ≥ 1.6 | JSON processing (state, gates, compliance) | `apt install jq` / `brew install jq` |
| `yq` | mikefarah ≥ 4.0 | execution.yaml parsing in `aid-run-gates.sh` | `apt install yq` (Debian) / `brew install yq` (macOS) — **NOT** the Python `yq` PyPI package, incompatible CLI |

Optional (development):

| Tool | Required for | Install |
|------|--------------|---------|
| `bats` ≥ 1.5 | Unit test suite under `scripts/tests/bats/` | `apt install bats` / `brew install bats-core` |
| `direnv` | Worktree `.envrc` auto-load | `apt install direnv` / `brew install direnv` |

Optional (Telegram alerts via `svc-mcp-tg-bot`):

| Tool | Required for | Install |
|------|--------------|---------|
| `docker` + `docker compose` | `svc-mcp-tg-bot` deployment | per Docker docs |
| `curl` | `try_telegram_alert` HTTP POST in FSM bash | OS default |

Pre-flight verification: `bash $AID_PLUGIN_PATH/scripts/aid-check-deps.sh`
(exits non-zero if a required dep is missing or the wrong variant).

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
