# AID — AI Development Orchestrator

- **Plugin:** 2.70.5
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

## Test portfolio audit (`/aid-audit-tests`)

Inventories a project's tests, optionally measures a bounded subset, and ends
with a six-part plain-language summary that answers **what to do** before it
shows any evidence: what to do now, what to fix or remove, what can run in
parallel, what must stay serial, test time now and after, and what is not
proved yet.

**It recommends; it does not act.** The audit never edits a test, never writes
the catalog's `parallel.status`, never changes `execution.yaml` and never
changes a scheduler mode. What a `full` run produces is a decision artifact
whose lanes and actions are proposals — acting on one is a separate, explicit
step you take.

Two properties are worth knowing before you run it:

- An audit that did not finish deciding says so (`audit_status: incomplete`)
  and **refuses** to hand over a remediation plan. A plan built on the part it
  skipped would make those units read as examined-and-healthy.
- Parallel safety has exactly one authority — the catalog's `parallel` block,
  bound to the content it was verified against, read by every consumer through
  one resolver. See
  [`docs/plans/P072-authority-boundary.md`](../../docs/plans/P072-authority-boundary.md).

## Test scheduler (opt-in, staged rollout)

Every generated `execution.yaml` carries a `targeted_tests` gate plus a
`test_audit.scheduler` block:

```yaml
test_audit:
  scheduler:
    mode: sequential        # sequential | observe_parallel | parallel
    resource_locks: {}
```

`sequential` (the default) runs targeted_tests exactly as before this
plan — one selected test at a time, no scheduler involved. Moving to
`observe_parallel`/`parallel` is a project's own opt-in decision, but the
mode written here is only a *request*: `aid-scheduler-rollout-gate.sh`
resolves the actual *effective* mode on every run, and can force it back
down to `sequential` if the evidence isn't there yet.

**Staged rollout (never configure-your-way-past-it):**

1. Run `aid-test-schedule-divergence-check.sh` against the project's own
   full test-catalog run_unit set, in both sequential and the target
   mode, inside a fresh disposable clone, at least 3 times, until 3
   `pass:true` artifacts exist for the current commit.
2. `observe_parallel` unlocks once 3 such artifacts (mode_tested:
   `observe_parallel`, covering the *entire* current catalog — a partial
   subset never counts) exist for the current commit.
3. `parallel` additionally requires 3 *separate* qualifying artifacts
   with mode_tested: `parallel` — evidence from one stage never
   substitutes for the other.

Missing, stale, or partial-coverage evidence fails closed to
`sequential`, never open. `aid-run-gates.sh` records the real mode each
`targeted_tests` run actually executed under in the gate's own
runtime-baseline sample (`concurrency_context`) — every other gate is
always recorded as `sequential`, since only `targeted_tests` ever goes
through the scheduler at all.

A `targeted_tests` run that hits exit 3 (unverifiable path) or exit 11
(no approved-catalog mapping row) never resolves silently — it escalates
to a genuinely-executed `full`-profile substitute, folded into the
top-level `gates_report.json` alongside the original attempt (kept as
`escalation.targeted_run`), so the run's real verdict is never a bare
pass built on a selector that verified nothing.

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
