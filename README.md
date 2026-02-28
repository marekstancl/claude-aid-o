# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v1.5.0

You describe what you want to build. AID brainstorms the design with you, generates a plan, dispatches specialized agents, runs quality gates, and delivers reviewed code — you approve the plan and the merge, everything in between is autonomous.

---

## Disclaimer — FIRST AID & Elevated Permissions

> **USE AT YOUR OWN RISK.** FIRST AID mode (`/aid-first-aid`) grants Claude Code **elevated permissions** for the duration of the session. This means Claude can autonomously edit files, run shell commands, install packages, push code to remote repositories, create GitHub releases, and interact with configured MCP services — **all without asking for confirmation**.
>
> **What "elevated permissions" means in practice:**
> - FIRST AID requires the **Steroids** preset (set via `/aid-setup`), which grants broad tool permissions
> - This includes `git push`, `npm install`, `gh release create`, and many others
> - The full list is in `defaults/policies/permissions.yaml` → `steroids` preset
>
> **What Claude CANNOT do (hard-deny list, non-overridable):**
> - `rm -rf /`, `git push --force`, `git reset --hard`, `sudo`, `chmod 777`, `chown`
> - Access `~/.ssh`, `~/.aws`, `~/.gnupg`, `/etc`, or Claude's own config
>
> **Safety mechanisms exist** (deny-list, 16 escalation triggers, Steroids preset verification), but they do not eliminate all risk. Autonomous AI agents can produce unexpected results. Always review your EPIC queue before starting, use `--dry-run` to preview, and keep `/aid-stop` in mind. You are responsible for the actions performed in your environment.

## 30-Second Demo

```bash
/aid-brainstorm "Build a REST API with auth and CRUD"
# → 9-step interactive dialog: context, approaches, trade-offs, architecture, plan

/aid-run-epic
# → AID takes over: architect → backend + frontend (parallel) → QA → gates → merge
```

Or go fully autonomous:

```bash
/aid-epic-queue add epic1.md epic2.md epic3.md
/aid-first-aid
# → AID processes the entire queue unattended, pausing only on genuine issues
```

## Installation

```bash
# In Claude Code CLI:
/plugin marketplace add marekstancl/claude-aid-o
/plugin install aid-orchestrator@claude-aid-o
/aid-setup    # detects your stack, configures gates and permissions
```

## What You Get

**9 role agents** — Architect, Domain, Backend, Frontend, QA, Security, Observability, Docs, Release — dispatched automatically based on your plan's dependency graph. Backend and Frontend run in parallel on separate git worktrees.

**Quality gates with auto-fix** — tests, lint, security scan run after implementation. Gate failures trigger a fixer agent that patches and re-runs (up to 3 attempts) before escalating to you.

**FIRST AID mode** — `/aid-first-aid` starts autonomous queue execution. PM approvals are replaced by agent-driven checks. Permissions are elevated for the session and restored on completion or `/aid-stop`. The only mandatory human touchpoint is escalation on genuine failures.

**Evidence trail** — every prompt, output, gate result, and PM decision is recorded in `.aid-o/04-engine/evidence/`. Full auditability.

**Qdrant memory** (optional) — agents learn from past runs. Decisions, patterns, and lessons are indexed and injected into future agent prompts. Works without Qdrant using file-based fallback.

## Commands

| Command | What it does |
|---------|-------------|
| `/aid-brainstorm [topic]` | 9-step interactive brainstorming → plan + optional EPIC |
| `/aid-plan-epic <path>` | Generate execution plan from EPIC or Plan |
| `/aid-run-epic [id]` | Run the full orchestration pipeline |
| `/aid-first-aid` | Start autonomous mode (EPIC queue execution with guardrails) |
| `/aid-stop` | Emergency stop — restore permissions, save progress |
| `/aid-setup` | Project onboarding — detect stack, configure AID |
| `/aid-init` | Initialize `.aid-o/` workspace |
| `/aid-epic-queue [sub]` | Queue management (add, remove, pause, resume) |
| `/aid-epic-status [id]` | Pipeline status — steps, gates, budget |
| `/aid-analytics [scope]` | Performance metrics and optimization recommendations |
| `/aid-audit` | Project health audit (0-100 score) |
| `/aid-research [topic]` | On-demand documentation research |
| `/aid-help [topic]` | AID documentation and help |

## How the Pipeline Works

```
/aid-brainstorm → Plan → EPIC → /aid-run-epic       OR  /aid-first-aid (autonomous queue)
                                      │                         │
                                      ├─────────────────────────┘
                                      ↓
                      IDLE → PLANNING → PLAN_REVIEW ──────────────────┐
                                          │                           │
                                  Manual: PM approves        Auto: validated by AI
                                          │                           │
                                          ├───────────────────────────┘
                                          ↓
                      EXECUTING ←──── NEXT_PHASE ←── PHASE_CHECK
                         │                                │
                    dispatch agents              check outputs + scope
                    (parallel where possible)
                         │
                   all steps done
                         ↓
                      GATES → GATE_RETRY (auto-fix, max 3) → ESCALATION (PM always)
                         │
                     all pass
                         ↓
                  CURATOR_RESOLVE (improvement proposals, lessons learned)
                         ↓
                   PM_APPROVAL ───────────────────────────┐
                         │                                │
                 Manual: PM approves merge       Auto: 4 guardrails check
                         │                                │
                         ├────────────────────────────────┘
                         ↓
                       DONE (auditor, release, archive, next EPIC from queue)
```

**Manual mode** — 3 PM touchpoints: PLAN_REVIEW, ESCALATION, PM_APPROVAL (via Slack or chat).
**FIRST AID mode** — only ESCALATION requires PM; plan review and merge are agent-validated.

## Configuration

`/aid-setup` auto-configures everything. Fine-tune in `.aid-o/03-config/`:

| File | Controls |
|------|----------|
| `gates.yaml` | Gate commands, retry limits, budget |
| `decision-policies.yaml` | What the Controller decides vs. escalates |
| `dispatch-strategy.yaml` | Parallel isolation — worktrees / branches / sequential |
| `slack-config.yaml` | Slack channel, timeouts, reminders |
| `memory-config.yaml` | Qdrant vector memory settings |
| `playbooks/*.md` | Role-specific agent instructions |

## Changelog

- **v1.5.0** (current) — Token efficiency: model tiering, selective context injection, dispatch prompt trimming, usage tracking, efficiency audit
- **v1.4.0** — GUI Dashboard: Ideas-to-Execution Kanban, AI Companion Chat, Evidence Vault full-text search, Pipeline Theater SVG timeline, Decision Hub notifications, 1014 tests
- **v1.3.1** — Audit-driven fixes: Curator evidence path bug, broken cross-ref, Czech→English translations, stale template references

See [CHANGELOG.md](CHANGELOG.md) for full history.

## Requirements

- [Claude Code](https://claude.com/claude-code) >= 1.0.0
- Git repository

## License

AGPL-3.0-only — see [LICENSE](LICENSE)
