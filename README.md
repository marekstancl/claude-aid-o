# AID — AI Development Orchestrator

**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).**

AID takes a structured task specification (EPIC), generates an execution plan, dispatches specialized role-based agents, enforces quality gates with auto-retry, and delivers reviewed code — with PM checkpoints and complete evidence trails.

---

## How It Works

```
Brainstorming (PM + AI)
  ↓  explore ideas, compare approaches, design decisions
Plan Document (.aid-o/01-plans/)
  ↓  PM converts plan into task spec
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

# Verify (shows all 17 commands)
/aid-help
```

## Quick Start

```bash
# 1. Initialize AID in your project
/aid-setup

# 2. Brainstorm with AI — explore approaches, make design decisions
#    Output: plan document in .aid-o/01-plans/

# 3. Write an EPIC from the plan (or use the template)
#    Edit .aid-o/02-epics/E-YYYYMMDD-xxxx-topic.md

# 4. Generate execution plan
/plan-epic .aid-o/02-epics/my-epic.md

# 5. Run the orchestrator
/run-epic
```

## Example: Bookmark Manager

The [`examples/bookmark-manager/`](examples/bookmark-manager/) directory contains a complete end-to-end example that produces a **working full-stack bookmark manager** (FastAPI + React + SQLite).

**What's included:**

| File | Description | Created by |
|------|-------------|------------|
| [`plan.md`](examples/bookmark-manager/plan.md) | Brainstorming output — design decisions, options considered, architecture | PM + AI brainstorming |
| [`EPIC.md`](examples/bookmark-manager/EPIC.md) | Task specification — 6 steps, 15 acceptance criteria, scope constraints | PM (derived from plan) |
| [`plan.json`](examples/bookmark-manager/plan.json) | Execution plan — dependency graph, 2 parallel groups, gates | `/plan-epic` (auto-generated) |

**What AID builds from this EPIC:**

```
Step 1: Architect    → API contracts, SQLite schema, component tree
                     ↓
Step 2: Backend  ────┤ (parallel)  → FastAPI endpoints, SQLite, URL fetcher
Step 3: Frontend ────┘             → React components, card grid, tag sidebar
                     ↓
Step 4: QA       ────┤ (parallel)  → pytest tests for API + edge cases
Step 5: Security ────┘             → SQL injection, SSRF, input validation review
                     ↓
Step 6: Docs         → API documentation + CHANGELOG
                     ↓
Gates                → tests_pass, lint_pass, docs_updated
                     ↓
PM Approval          → review and merge
```

**Result:** A bookmark manager where you can add/edit/delete bookmarks with tags, search, favicon auto-fetch, and a card-based grid UI.

See the [example README](examples/bookmark-manager/README.md) for step-by-step instructions.

## What's Inside

| Component | Count | Description |
|-----------|-------|-------------|
| **Commands** | 17 | `/aid-setup`, `/run-epic`, `/plan-epic`, `/run-gates`, `/epic-queue`, `/audit`... |
| **Agents** | 18 | 9 role + 3 specialist + 6 utility |
| **Skills** | 13 | State machine, planner, parallel dispatch, gates engine, Slack MCP... |
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

- **v0.2.0** — `/aid-brainstorm` command (guided brainstorming before EPIC writing), git worktrees for parallel dispatch isolation, Slack setup guide
- **v0.3.0** — Browser-based evidence viewer, EPIC templates library

## Requirements

- [Claude Code](https://claude.com/claude-code) >= 1.0.0
- Git repository

## License

MIT — v0.1.0
