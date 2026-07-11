# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v2.54.0

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

- **v2.55.0** (current) — P060 false-green / stale-evidence hardening (E-060-2_2): 8 OBS-ledger fixes — gate-count integrity + undefined-gate reconciliation in `aid-run-gates.sh`, CP2 step-range prefilter, CP3 head-freshness check, runtime cache preflight (`scripts/lib/aid-cache-preflight.sh`, IMP-179 partial), commit-path guard hook, queue dependency revalidation, C4 `head_match` policy hook — plus the E11 enablement map with the mandatory K4×K8 binding and 8 new enforcement-registry rows (271→279)
- **v2.53.0** — E9 C4 Release Policy (P059): deterministic `scripts/aid-release-policy.sh` release-decision aggregator (no LLM), `scripts/aid-pm-brief.sh` PM decision brief + patch-back, FSM `done-advance` dual-run observe hook with 8-value `divergence_class` taxonomy + `release_policy_preempted` + force→waiver, protocol-v2 `release_decision`/`pm_decision_brief`/`waiver` schemas, D11 release-decision state model with Reporter/Simplifier CONDITIONAL gating, `docs/extending-aid.md` C4+D11 reference, IMP-177 invalidation-map live caller
- **v2.52.0** — E8 C3 Independent Audit (P057): risk-gated distrust-based `agents/auditor.md` C3 mode + legacy A-J compat, protocol-v2 `audit-report.json`/`audit-input-manifest.json`, `aid-audit-independence.sh` Codex capability detection, `c3-audit-policy.yaml`, fail-closed FSM done-advance hook, Curator now serial after C3 with content-ref sequencing guard, observe-only `invalidation-map.json` producer, behavioral red-green bats coverage

See [CHANGELOG.md](CHANGELOG.md) for full history.

## Requirements

- [Claude Code](https://claude.com/claude-code) >= 1.0.0
- Git repository

## License

AGPL-3.0-only — see [LICENSE](LICENSE)
