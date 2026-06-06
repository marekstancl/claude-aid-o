# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v2.28.2

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
| `/aid-init` | Initialize `.aid-o/` workspace — 10-file structure, stack auto-detection, idempotent |
| `/aid-audit` | Project health audit — code, docs, tests, dependencies |
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

`/aid-init` auto-configures everything. Fine-tune in `.aid-o/config/`:

| File | Controls |
|------|----------|
| `execution.yaml` | Gate commands, retry limits, dispatch strategy |
| `project.yaml` | Stack detection, project preferences |
| `permissions.yaml` | Agent permission presets |

## Changelog

- **v2.28.2** (current) — fixed EPIC dependency renumbering: slicing a multi-EPIC plan into per-EPIC files kept global step numbers in the Depends On column (e.g. "step 2 depends on 4" in a 3-step EPIC), crashing EPIC-to-JSON validation; intra-EPIC dependencies and the Goal step list are now remapped to EPIC-local numbering
- **v2.28.1** — fixed the `aid-fsm.sh transition --force` crash (unbound `project_root` under `set -u`) that broke the manual-override escape hatch; CI now installs `bats` so the FSM/release/integration suites actually run (they were silently skipped), the stale bats + regression suites are repaired, and the FSM precondition layer gained real red/green coverage
- **v2.28.0** — P041 audit Wave 2: model + config-policy single-sourcing (role-cards, escalation, pre-filter), curator propose-only with CP4-after-apply, auditor + planner overhaul, verifier-provenance interval-bracket fix (honest `unverifiable` rename + anti-fabrication instruction), frontend Visual Anchoring enforcement, and promoted skill-writing + command-writing standards with a governance lint guard

See [CHANGELOG.md](CHANGELOG.md) for full history.

## Requirements

- [Claude Code](https://claude.com/claude-code) >= 1.0.0
- Git repository

## License

AGPL-3.0-only — see [LICENSE](LICENSE)
