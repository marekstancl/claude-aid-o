# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v2.30.0

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

- **v2.48.0** (current) — E7-CAL calibration mechanism: real ScreenG Playwright capture, artifact persistence (8 files/case), standalone verifier, 15 false-green BATS tests, `image_dimension_mismatch` reason, auto-skip gates for non-calibration EPICs
- **v2.47.0** — E7A UI fidelity foundation: Playwright capture, pixelmatch comparison, typed contract schema, envelope validator, 5 calibration fixture sets, CI workflow
- **v2.46.0** — E6 C1 honest-minimal delivery probes: DG-15/17/18 + delivery-map foundation
- **v2.44.1** — C2 Semantic Review Engine (observe): 4-mode dual-emit, 12-lens catalog, wiring-gate, acceptance-evidence, consumption-proof, E3→E5 completed_lenses
- **v2.42.1** — E3 Adaptive Review Profile Detector: deterministic surface→lens resolver, observe FSM hook, 13-scenario test harness
- **v2.38.0** — `/aid-verify-plan` + `/aid-verify-implementation` manual PM commands: independent adversarial review of a plan (pre-execution) and an implementation (DONE), dispatched to a fresh-context agent
- **v2.37.0** — per-step Acceptance Criteria pre-flight in aid-epic-to-json.sh (multi-step EPIC needs >=1 AC per step)
- **v2.36.2** — stale aid-plan.md CP1 lenses synced; boundary manifest committed
- **v2.36.1** — CP1-deep empty-file bypass closed; L1/L2/L3 lens taxonomy; aid-init gitignore guidance
- **v2.36.0** — behavior-first review contracts; `behavior_trace` structural gate; CP1 risk-scaling + `aid-cp1-gate.sh`; `.gitignore` negation fix; CP1 gate `risk:low` precedence fix; frontmatter parser state machine
- **v2.35.0** — `plan-close` FSM command enforces all 4 boundary reports; toggle-skip for disabled specialists; boundary manifest committed artifact; CI floor check; force-override audit enrichment; 13 new bats assertions
- **v2.34.2** — `plan_diff` gate evidence truthfulness (exit 2 → `skip` not `pass`); `review_result` instruction drift cleaned up in `role-cards.md` + `gate-fixer.md`

See [CHANGELOG.md](CHANGELOG.md) for full history.

## Requirements

- [Claude Code](https://claude.com/claude-code) >= 1.0.0
- Git repository

## License

AGPL-3.0-only — see [LICENSE](LICENSE)
