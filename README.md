# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).**

AID takes a structured task specification (EPIC), generates an execution plan, dispatches specialized role-based agents, enforces quality gates with auto-retry, and delivers reviewed code — with PM checkpoints and complete evidence trails.

---

## How It Works

```
/aid-brainstorm (PM + AI)
  ↓  9-step interactive flow: context → questions → approaches → design
Plan Document (.aid-o/01-plans/)
  ↓  PM converts plan into task spec (or uses auto-generated EPIC draft)
EPIC (.aid-o/02-epics/)
  ↓  /plan-epic generates execution plan
Plan JSON (dependency graph, parallel groups, gates)
  ↓  PM approves plan (GO / REVISE / ABORT)
Dispatch Agents (architect → backend + frontend → QA + security → docs)
  ↓  each agent follows role-specific playbook
Quality Gates (tests, lint, security scan, docs check)
  ↓  auto-fix on failure, retry up to 3x
PM Approval → Merge → Done
  ↓
Next EPIC from queue (autonomous pipeline)
```

The **control flow is deterministic** — defined by YAML/JSON configuration (EPIC structure, gates.yaml, decision-policies.yaml). The **content is AI-generated** — each agent produces code, tests, docs via LLM.

## Installation

Requires [Claude Code](https://claude.com/claude-code) CLI.

```bash
# Add marketplace
/plugin marketplace add marekstancl/claude-aid-o

# Install plugin
/plugin install aid-orchestrator@claude-aid-o

# Verify (shows all 18 commands)
/aid-help
```

## Quick Start

```bash
# 1. Initialize AID in your project
/aid-setup

# 2. Brainstorm with AI — 9-step interactive flow
/aid-brainstorm "Build a REST API with auth and CRUD operations"

# 3. Write an EPIC from the plan (or use the template)
#    Edit .aid-o/02-epics/E-YYYYMMDD-xxxx-topic.md

# 4. Generate execution plan
/plan-epic .aid-o/02-epics/my-epic.md

# 5. Run the orchestrator
/run-epic
```

## Getting Started with Brainstorming

The `/aid-brainstorm` command walks you through a **9-step interactive flow** to go from idea to execution plan:

```
/aid-brainstorm "Build a REST API with database, auth, and CRUD operations"
```

**The 9 steps:**

1. **Context** — AI asks about your tech stack, preferences, constraints
2. **Questions** — Clarifying questions to narrow the design space
3. **Approaches** — Compare options (frameworks, patterns, trade-offs)
4. **Design** — Architecture decisions, API contracts, data models
5. **Sections** — Plan outline for your review
6. **Approval** — You approve or request changes
7. **Document** — Full plan written to `.aid-o/01-plans/`
8. **EPIC draft** — Optional EPIC generated from the plan
9. **Handoff** — Summary of decisions and next steps

**Try one of these prompts to get started:**

| Prompt | What you get |
|--------|-------------|
| `"Build a REST API with database, auth, and CRUD operations"` | Endpoints, DB schema, auth strategy, 6-8 step EPIC |
| `"Build a CLI tool that does X"` (fill in X) | Command structure, flags, config, 4-6 step EPIC |
| `"Build a full-stack web app with React frontend and API backend"` | Components, API contracts, DB design, 8-10 step EPIC |

Run `/aid-help examples` for detailed walkthroughs of each prompt.

## What's Inside

| Component | Count | Description |
|-----------|-------|-------------|
| **Commands** | 18 | `/aid-setup`, `/aid-brainstorm`, `/run-epic`, `/plan-epic`, `/run-gates`, `/epic-queue`, `/audit`... |
| **Agents** | 18 | 9 role + 3 specialist + 6 utility |
| **Skills** | 14 | State machine, planner, brainstorming, parallel dispatch, gates engine, Slack MCP... |
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
| **Curator** | Collects improvement notes from all agents, proposes improvements to PM |
| **Auditor** | Post-EPIC health audit (code, security, docs) with 0-100 scoring |
| **Project Scanner** | Analyzes tech stack, structure, conventions → `project-profile.yaml` |

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

AID is fully customizable via YAML/JSON configs in `.aid-o/03-config/`:

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

## Optional: Vector Memory (Qdrant)

AID supports long-term semantic memory via Qdrant MCP. Past decisions, lessons, and patterns are searchable by agents — improving quality over time.

```bash
claude mcp add qdrant-memory \
  -e QDRANT_URL="http://localhost:6333" \
  -e COLLECTION_NAME="aid-memory" \
  -- uvx mcp-server-qdrant
```

Works without Qdrant using file-based memory (active-work.md, lessons-learned.md).

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

- **v0.2.0** (done) — `/aid-brainstorm` command, MCP server onboarding, permission presets, git worktree parallel isolation, orchestration logging, CLAUDE.md marker merge, interactive examples, configurable document language
- **v0.3.0** — Browser-based evidence viewer, EPIC templates library, multi-project workspace support

## Requirements

- [Claude Code](https://claude.com/claude-code) >= 1.0.0
- Git repository

## License

MIT — v0.2.0
