# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).**

You come with an idea, AID walks you through the entire process — from concept to reviewed, merged code.

---

## Why AID?

Today you chat with AI on a single thread, manually coordinate what it should do, and on anything bigger than a small feature it falls apart — you lose context, forget about tests, have no overview of what's done.

AID gives you an entire dev team under one command. You're the PM — you approve the plan and the final merge, everything else runs autonomously.

## How It Works

1. **You come with an idea** — `/aid-brainstorm "Build a REST API with auth and CRUD"`. AID walks you through a 9-step interactive dialog: asks about your stack, proposes approaches, compares trade-offs, and together you arrive at an architecture and plan.

2. **AID generates the task spec** — from the brainstorm, AID produces a structured specification (EPIC) with steps, dependencies, acceptance criteria, and quality gates. You just review and approve.

3. **You launch the pipeline** — `/run-epic` and AID takes over:
   - Generates an execution plan with dependency graph and parallel groups
   - Dispatches work to 9 role-based agents (architect → domain → backend + frontend → QA + security → docs → release)
   - Parallelizes what it can — backend + frontend run simultaneously on separate git worktrees
   - After each step, checks outputs and scope compliance
   - Runs quality gates (tests, lint, security scan) with auto-retry — gate-fixer agent patches and re-runs (max 3 attempts)
   - Requests your PM approval and merges

```
/aid-brainstorm "topic"       ← 9-step dialog: context → questions → approaches → design → plan
                              ← AID offers to generate an EPIC from the conclusions
/plan-epic path/to/epic.md   ← generates JSON plan + session file
/run-epic                     ← orchestrator takes control
```

The entire process is governed by a state machine: IDLE → PLANNING → PLAN_REVIEW → EXECUTING → PHASE_CHECK → GATES → PM_APPROVAL → DONE. The **control flow is deterministic** — defined by YAML/JSON configuration. The **content is AI-generated** — each agent produces code, tests, docs via LLM.

## Installation

Requires [Claude Code](https://claude.com/claude-code) CLI.

```bash
# Add marketplace
/plugin marketplace add marekstancl/claude-aid-o

# Install plugin
/plugin install aid-orchestrator@claude-aid-o

# Onboarding — detects tech stack, configures gates, sets permissions
/aid-setup
```

## Quick Start

```bash
# Brainstorm with AI — 9-step interactive flow
/aid-brainstorm "Build a REST API with auth and CRUD operations"

# AID generates EPIC from your brainstorm → review and approve
# Or write one manually from the template in .aid-o/02-epics/

# Generate execution plan
/plan-epic .aid-o/02-epics/my-epic.md

# Run the orchestrator
/run-epic
```

**Try one of these prompts:**

| Prompt | What you get |
|--------|-------------|
| `"Build a REST API with database, auth, and CRUD operations"` | Endpoints, DB schema, auth strategy, 6-8 step EPIC |
| `"Build a CLI tool that does X"` (fill in X) | Command structure, flags, config, 4-6 step EPIC |
| `"Build a full-stack web app with React frontend and API backend"` | Components, API contracts, DB design, 8-10 step EPIC |

Run `/aid-help examples` for detailed walkthroughs.

## What's Inside

| Component | Count | Description |
|-----------|-------|-------------|
| **Commands** | 19 | `/aid-setup`, `/aid-brainstorm`, `/run-epic`, `/plan-epic`, `/aid-analytics`, `/run-gates`, `/epic-queue`, `/audit`... |
| **Agents** | 18 | 9 role + 3 specialist + 6 utility |
| **Skills** | 16 | State machine, planner, brainstorming, parallel dispatch, gates engine, cost optimization, analytics... |
| **Playbooks** | 11 | Role-specific instructions (customizable per project) |

### Role Agents

| Agent | Responsibility | Runs |
|-------|---------------|------|
| **Architect** | API contracts, ADRs, system design | Always first |
| **Domain** | Domain models, entities, invariants | After architect |
| **Backend** | Server-side code, APIs, services | Parallel with frontend |
| **Frontend** | UI components, pages, client logic | Parallel with backend |
| **QA** | Unit, integration, e2e tests | After implementation |
| **Security** | OWASP review, vulnerability scanning | After implementation |
| **Observability** | Logging, metrics, tracing | After implementation |
| **Docs** | API docs, guides, changelogs | After implementation |
| **Release** | Versioning, deployment config | Last |

### Specialist Agents

| Agent | Purpose |
|-------|---------|
| **Curator** | After each EPIC, collects improvement notes from all agents, deduplicates, proposes improvements to backlog |
| **Auditor** | Post-EPIC audit (code, security, docs, process compliance) with scoring |
| **Project Scanner** | Analyzes tech stack, structure, conventions → `project-profile.yaml` |

## Integrations

- **Slack MCP** — PM communication via Slack (plan approval, escalation, merge approval, 7 message types with timeout/reminder logic). Chat fallback when Slack is not configured.
- **Qdrant Memory** (optional) — Agents remember past decisions and lessons learned, improving with every EPIC. File-based fallback when Qdrant is unavailable.
- **Epic Queue** — `/epic-queue add` to stack EPICs, AID processes them one by one autonomously.
- **Project Scanner** — `/aid-setup` analyzes your project (tech stack, structure, conventions) → generates `project-profile.yaml`, configures gates for your stack.

## Controller State Machine

```
IDLE → PLANNING → PLAN_REVIEW → EXECUTING → PHASE_CHECK → NEXT_PHASE
                      ↑               ↑                        │
                      │ revise         └────────────────────────┘
                      │                                         │
                      │                                  all steps done
                      │                                         ↓
                      │                         GATES → GATE_RETRY (max 3)
                      │                           │
                      │                       all pass
                      │                           ↓
                      │                     PM_APPROVAL
                      │                           │
                      │                       approved
                      │                           ↓
                      │                         DONE
                      │                    (Curator + Auditor)
                      │                           │
                      │                    queue not empty?
                      │                           ↓
                      │                  auto-start next EPIC
                      └──── PM says REVISE
```

**PM checkpoints** (via Slack or chat fallback):
- **PLAN_REVIEW** — approve execution plan (GO / REVISE / ABORT)
- **ESCALATION** — handle failures (Fix / Skip / Abort)
- **PM_APPROVAL** — approve merge (APPROVE / REJECT / REVISE)

## Configuration

Everything is customizable via YAML/JSON configs in `.aid-o/03-config/`:

| File | Controls |
|------|----------|
| `gates.yaml` | Which gates run, commands, retry limits, budget |
| `decision-policies.yaml` | What Controller decides autonomously vs. escalates to PM |
| `slack-config.yaml` | Slack channel, timeouts, reminder intervals |
| `memory-config.yaml` | Qdrant vector memory settings |
| `dispatch-strategy.yaml` | Parallel isolation — worktrees / branches / sequential |
| `language.yaml` | Document language — ISO 639-1 code (default: EN) |
| `playbooks/*.md` | Role-specific agent behavior for your project |

`/aid-setup` auto-configures everything based on your detected tech stack.

## Workspace Structure

`/aid-init` creates in your project:

```
.aid-o/
  01-plans/              Plans (brainstorming output)
  02-epics/              EPICs (task specifications)
  03-config/
    policies/            gates.yaml, decision-policies.yaml, slack-config.yaml
    templates/           EPIC template, session templates, plan schema
    playbooks/           11 role playbooks (customizable)
  04-engine/
    sessions/            Active + archived session files
    memory/              project-profile.yaml, active-work.md
    evidence/            Execution evidence (per EPIC, per run)
```

## Evidence Trail

Every EPIC run produces in `.aid-o/04-engine/evidence/{epic_id}/{run_id}/`:

```
epic_input.md           Original EPIC (immutable copy)
plan.json               Execution plan
plan_progress.json      Step completion tracker
stage_log.jsonl         State transition log (every event timestamped)
gates_report.json       Gate results with retry history
final_report.md         Human-readable summary
prompts/                Agent prompts sent
steps/                  Agent outputs + diffs
gates/                  Gate command outputs
```

## All Commands

| Command | Description |
|---------|-------------|
| `/aid-init` | Initialize `.aid-o/` workspace |
| `/aid-setup` | Interactive project onboarding (tech stack detection) |
| `/aid-brainstorm [topic]` | 9-step interactive brainstorming flow → plan + optional EPIC draft |
| `/aid-help [topic]` | Documentation (commands, workflow, agents, gates, config...) |
| `/plan-epic <path>` | EPIC → Plan JSON + session file |
| `/run-epic [id]` | Full orchestration pipeline |
| `/run-step <id> <step>` | Run single step manually |
| `/epic-status [id]` | Pipeline status (steps, gates, budget) |
| `/run-gates [id]` | Run quality gates standalone |
| `/epic-queue [sub]` | EPIC queue management (add, remove, pause, resume) |
| `/quality-gates` | 6-gate pre-commit protocol |
| `/session-start` | Start tracked session |
| `/session-end` | Complete + archive session |
| `/handoff` | Create handoff for next AI session |
| `/audit` | Project health audit (0-100 score) |
| `/coding-standards` | Load coding standards |
| `/testing` | Load testing workflow |
| `/docs-protocol` | Load documentation protocol |

## Roadmap

- **v0.3.0-rc.1** (current) — Cost optimization, per-agent metrics, multi-session EPICs, cross-project Qdrant knowledge, `/aid-analytics`, auto-archive, Playwright E2E, chat-first setup, permission dual-write, DONE state fixes. *Release candidate — needs validation on an external project.*
- **v0.2.0** — `/aid-brainstorm` command, MCP server onboarding, permission presets, git worktree parallel isolation, orchestration logging, CLAUDE.md marker merge, interactive examples, configurable document language
- **v0.4.0** (planned) — Browser-based evidence viewer, EPIC templates library, benchmark framework

## Requirements

- [Claude Code](https://claude.com/claude-code) >= 1.0.0
- Git repository

## License

MIT — v0.3.0-rc.1
