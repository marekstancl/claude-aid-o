# AID — AI Development Orchestrator

- **Plugin:** 2.66.1
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

## Worktree Development

When developing the plugin itself (not consuming it from another project), work
in a dedicated git worktree to avoid the chicken-and-egg problem where editing
plugin scripts mid-flight breaks any AID instance currently running in another
project (vulcan, sousto, etc.).

```bash
git worktree add ~/.claude-worktrees/<branch-name> -b feat/<branch-name>
cd ~/.claude-worktrees/<branch-name>
direnv allow                            # one-shot per worktree
# AID_PLUGIN_PATH automatically set to $(pwd)/plugins/aid-orchestrator
# scripts/ added to PATH so aid-fsm.sh, aid-run-gates.sh, etc. resolve directly
```

Other projects continue using the stable plugin from
`~/.claude/plugins/marketplaces/claude-aid-o/`. Once the worktree branch is
merged, run `claude plugin update aid-orchestrator@claude-aid-o` in those
projects to pick up the new version.

A committed `.envrc` template at the repo root pre-configures direnv for this
workflow:

```bash
export AID_PLUGIN_PATH="$(pwd)/plugins/aid-orchestrator"
PATH_add "$AID_PLUGIN_PATH/scripts"
```

## Documentation

- `/aid-help` — progressive help (Level 0-3)
- `CHANGELOG.md` — version history
- `scripts/README.md` — bash script documentation

## Plan-level release model

A plan declares its release model in its committed lifecycle manifest
(`.aid-lifecycle/manifests/<plan_id>.yaml`, key `mode`).

Under **`plan_branch`** an EPIC merges into the plan branch and releases nothing.
The plan releases once, at the plan-final boundary: one gate profile run against
a frozen candidate, one specialist review (Auditor, Curator, Simplifier,
Reporter), one PM authorization bound to that candidate, one compare-and-swap
merge to the target branch, at most one tag, and a committed lifecycle receipt
without which the plan cannot be declared closed.

Under **`legacy_epic_release_mode`** each EPIC releases as before.

New plans default to `plan_branch` when the project declares a `gate_profiles`
table in its `execution.yaml`, and otherwise fall back to legacy with a logged
`plan_branch_unavailable: no_gate_profiles`. Existing plans are never migrated:
`aid-plan-fsm.sh inventory --apply` stamps them explicitly instead.
