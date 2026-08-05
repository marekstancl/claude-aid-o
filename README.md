# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v2.69.0

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
| `/aid-audit-tests` | Test portfolio audit — inventory, safe measurement, and a plain-language recommendation |
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

- **v2.70.7** (current) — what the audit proves about parallel safety finally reaches the catalog, and a bare `/aid-audit-tests` asks what you want instead of guessing. Plus v2.70.6 — a full audit of a large portfolio can actually finish: nothing that scales with the project goes through argv any more. Plus v2.70.5 — an audit whose evidence disappears mid-run gets it back and carries on. Plus v2.70.4 — the profiler validates its own receipts instead of reporting success on artifacts nothing can consume, and a unit whose catalog and execution.yaml commands disagree is refused. Plus v2.70.3 — an audit can no longer lose its own evidence to its own diagnostics, and a unit that times out is finally eligible for cost profiling. Plus v2.70.2 — the resource map no longer dies with "Argument list too long" on large test files. Plus v2.70.1 — the three defects a real full audit found: an inventory key producer and consumer disagreed on, a profiler that refused every gate unit, and a catalog that could not be approved. Plus v2.70.0 — test-portfolio decision quality: a full audit now produces a schema-bound decision artifact, parallel safety has one content-bound authority read by all three consumers, and an execution ledger catches a run unit dispatched by two gates.
- **v2.69.0** — fail-closed Files/Scope path parsing: the shared cleaner (`lib/aid-scoping.sh`) now rejects ambiguous multi-path entries (comma/conjunction-separated) instead of silently narrowing `allowed_paths` to the first path, enforced consistently across the per-step scoping block, the legacy Scope fallback, the generation-time preflight, and the D5 contract gate.
- **v2.68.0** — real, explicit-allowlist-based parallel bats execution for this repo's own `gate:bats_all` (replacing the quarantine stub), a separate `gate:bats_boundary` for the 2 too-expensive-to-pool files, an idempotent self-host execution.yaml migration + verify mechanism, and `plan_diff`/`shell_pipeline_smoke` gate fixes (P071).
- **v2.67.0** — opt-in test scheduler with staged rollout, real `aid-run-gates.sh` dispatch + escalation, a `bats_all` remediation-evidence collector + genuine E2E full-path proof, and a PM quarantine-decision-record mechanism (P069). This repo's own `bats_all` real measurement campaign remains deferred.

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
