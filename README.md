# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v2.85.1

You describe what you want to build. AID brainstorms the design with you, generates a plan, dispatches agents, runs quality gates, and delivers reviewed code — you approve the plan and the merge, everything in between is autonomous.

---

## Disclaimer — Autonomous Mode & Elevated Permissions

> **USE AT YOUR OWN RISK.** AID's autonomous mode (`/aid-run --auto`) grants Claude Code **elevated permissions** for the duration of the session. This means Claude can autonomously edit files, run shell commands, install packages, push code to remote repositories, and interact with configured MCP services — **all without asking for confirmation**.
>
> **What Claude CANNOT do (hard-deny list, non-overridable):**
> - `rm -rf /`, `git push --force`, `git reset --hard`, `sudo`, `chmod 777`, `chown`
> - Access `~/.ssh`, `~/.aws`, `~/.gnupg`, `/etc`, or Claude's own config
>
> **Safety mechanisms exist** (deny-list, escalation triggers, scope checking), but they do not eliminate all risk. Autonomous AI agents can produce unexpected results. Always review your task queue before starting, use `--dry-run` to preview, and keep `/aid-stop` in mind.

## Quick Start

```bash
# Fast Mode — small task, < 2 min overhead
/aid-do "Add input validation to the login form"
# → implements, logs to Q-001.md, done

# Full Pipeline — plan + execute + gates
/aid-plan "Build a REST API with auth and CRUD"
# → brainstorm → architecture → plan.json

/aid-run
# → READY → EXECUTE (agents) → GATES (tests, lint, security) → DONE
```

Or go fully autonomous:

```bash
/aid-run --auto
# → processes EPIC queue unattended, pausing only on genuine escalations
```

## Installation

```bash
# In Claude Code CLI:
/plugin marketplace add marekstancl/claude-aid-o
/plugin install aid-orchestrator@claude-aid-o
/aid-init    # creates .aid-o/ workspace, detects your stack
```

## What You Get

**6-state bash FSM** — READY → EXECUTE → GATES → DONE (happy path), with ESCALATION and ERROR branches. State transitions enforced by bash scripts, not LLM instructions. Deterministic, auditable, crash-recoverable.

**Fast Mode (`/aid-do`)** — For tasks under 2 hours. < 2 min overhead. Creates a quick log (Q-NNN.md), skips the full EPIC pipeline.

**7 controller agents** — Implementer, Verifier, Gate-fixer, Curator, Auditor, Project-scanner, Run-validator — dispatched automatically based on your plan's dependency graph.

**Quality gates with auto-fix** — Tests, lint, build, security scan run via `aid-run-gates.sh`. Gate failures trigger the gate-fixer agent (up to 3 attempts) before escalating to you.

**Evidence trail** — Every event, gate result, and decision is recorded in `.aid-o/work/evidence/` as `timeline.jsonl`. Full auditability.

**~50K prompt tokens** — 87% reduction from v1's ~400K. Deterministic logic moved to bash scripts, skills consolidated, cross-references eliminated.

## Commands

| Command | What it does |
|---------|-------------|
| `/aid-do [task]` | Fast Mode — implement small task with < 2 min overhead |
| `/aid-plan [topic]` | Brainstorm → architecture → plan.json (merges old brainstorm + write-plan + plan-epic) |
| `/aid-run [id]` | Execute full pipeline: READY → EXECUTE → GATES → DONE. Use `--auto` for autonomous mode |
| `/aid-status [id]` | Pipeline status — FSM state, steps, gates, queue (merges old epic-status + epic-queue) |
| `/aid-init` | Create or upgrade the `.aid-o/` workspace — base manifest, stack auto-detection, idempotent |
| `/aid-setup [module]` | Configure what init created — permissions, integrations, CLAUDE.md, stack re-scan |
| `/aid-verify-plan` | Independent adversarial review of a plan before it goes to execution |
| `/aid-verify-implementation` | Independent adversarial DONE review of an implementation before it is trusted as complete |
| `/aid-audit` | Project health audit — code, docs, tests, dependencies |
| `/aid-audit-tests` | Test portfolio audit — inventory, safe measurement, and a plain-language recommendation |
| `/visual-companion` | Browser-based visual brainstorming companion — interactive mockups, per-question visual/text decision |
| `/aid-stop` | Emergency stop — save progress, restore permissions |
| `/aid-help [topic]` | Progressive help — Level 0 cheat sheet → Level 3 architecture deep-dive |

## How the Pipeline Works

```
/aid-plan → plan.json → /aid-run
                            │
                      ┌─────┴─────┐
                      ▼           ▼
                   READY    (aid-fsm.sh validates)
                      │
                      ▼
                   EXECUTE ◄──── dispatch agents (parallel where DAG allows)
                      │
                  all steps done
                      ▼
                    GATES ───► aid-run-gates.sh (tests, lint, build, security, scope)
                      │
               ┌──────┴──────┐
               ▼              ▼
           all pass      gate fails
               │              │
               ▼              ▼
             DONE      ESCALATION → gate-fixer (auto) or PM (manual)
               │              │
               ▼              └──► retry → GATES
          curator + archive
```

**Manual mode** — PM approves at READY and reviews at ESCALATION.
**Autonomous mode (`--auto`)** — Only genuine escalations require PM; all other checkpoints are agent-validated.

## Configuration

Init creates, setup configures: `/aid-init` writes the initial config files, `/aid-setup` owns
every change after that. Both live in `.aid-o/config/`:

| File | Controls | Changed by |
|------|----------|-----------|
| `execution.yaml` | Gate commands, retry limits, dispatch strategy | hand-edited; `/aid-init` only offers additive upgrades |
| `project.yaml` | Stack detection, project preferences | `/aid-setup scan` |
| `permissions.yaml` | Agent permission presets | `/aid-setup permissions` |
| `integrations.yaml` | MCP integrations (memory, …) | `/aid-setup integrations` |

## Changelog

- **v2.93.0** (current) — a page carries what its phase owes and cannot contradict itself (artifact profiles, a page for a finished EPIC, the obligation widened to three milestones), and a release is required by what changed rather than by what a commit message promised
- **v2.92.1** — one alert sender instead of two, and the first line of every message says whether it is about a running plan or last night's tests
- **v2.92.0** — agents run concurrently where the plan proves it safe (dispatch contract, per-step worktrees, conflict = retry), three hook rules and a gate-script check, UI proposals built from the application with responsiveness as a project fact
- **v2.91.0** — a plan's page finally says what the plan delivers, per EPIC and per step
- **v2.90.2** — a plan title with a dash or diacritics no longer produces an EPIC filename nothing can reproduce
- **v2.90.0** — brainstorming se ptá dvakrát místo pěti; spor o metodu si dva modely rozhodnou samy
- **v2.89.3** — 84 commands in nine instruction files could not be run as written
- **v2.87.0** — plan ceremony bands classified from declared paths, obligations graduated to match, and tests designed rather than counted

See [CHANGELOG.md](CHANGELOG.md) for full history.

## Requirements

- [Claude Code](https://claude.com/claude-code) >= 1.0.0
- Git repository

## License

AGPL-3.0-only — see [LICENSE](LICENSE)

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
