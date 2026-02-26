# AID — AI Development Orchestrator

A Claude Code plugin implementing **Controller + Workers** architecture for multi-agent software development. v1.0.0

## How It Works

1. **Brainstorm** — `/aid-brainstorm` runs a 9-step dialog: context, questions, approaches, trade-offs, architecture, plan
2. **EPIC** — structured task specification (scope, constraints, acceptance criteria, steps)
3. **Plan** — `/aid-plan-epic` generates execution plan with dependency graph and parallel groups
4. **Dispatch** — Controller sends work to role-based agents on separate git worktrees
5. **Gates** — tests, lint, security scan — with auto-fix retry (gate-fixer agent, max 3 attempts)
6. **Curator** — post-EPIC improvement proposals, auto-evaluated and applied
7. **PM approval** — via Slack MCP or chat fallback
8. **Queue** — stack EPICs with `/aid-epic-queue`, AID processes them sequentially

**FIRST AID mode** (`/aid-first-aid`) — autonomous queue execution. PM approvals replaced by agent-driven checks. Permissions elevated via permission sandwich (backup → elevate → restore). Only escalation requires PM interaction. Disengage anytime with `/aid-stop`.

> **Disclaimer:** FIRST AID mode grants Claude Code elevated permissions to execute commands **without confirmation prompts**. This includes file edits, shell commands, package installs, git push, GitHub releases, and MCP tool calls. A hard-deny list prevents the most dangerous operations (`rm -rf /`, `git push --force`, `sudo`, etc.), but autonomous execution carries inherent risk. **Use at your own risk.** Always review your EPIC queue before starting, use `--dry-run` to preview, and keep `/aid-stop` available. See `permissions-auto.yaml` for the full permission list. You are responsible for all actions performed in your environment.

## Quick Start

```bash
/aid-setup                              # detect stack, configure gates
/aid-brainstorm "Build X with Y"        # explore design → plan + EPIC
/aid-run-epic                           # orchestrate

# Or autonomous:
/aid-epic-queue add epic1.md epic2.md
/aid-first-aid                          # process queue unattended
```

## Commands (13)

| Command | Description |
|---------|-------------|
| `/aid-init` | Initialize `.aid-o/` workspace |
| `/aid-setup` | Interactive project onboarding — detect tech stack, configure AID |
| `/aid-brainstorm [topic]` | 9-step interactive brainstorming → plan + optional EPIC |
| `/aid-plan-epic <path>` | Parse EPIC or Plan → Plan JSON + run file |
| `/aid-run-epic [id]` | Run Controller state machine for full EPIC orchestration |
| `/aid-first-aid` | Start FIRST AID autonomous mode (EPIC queue with guardrails) |
| `/aid-stop` | Emergency stop — restore permissions, save progress |
| `/aid-epic-queue [sub]` | Queue management (add, remove, pause, resume) |
| `/aid-epic-status [id]` | Pipeline status — steps, gates, budget |
| `/aid-analytics [scope]` | Performance metrics and optimization recommendations |
| `/aid-audit` | Project health audit (0-100 score) |
| `/aid-research [topic\|url]` | On-demand documentation research |
| `/aid-help [topic]` | AID documentation and help |

## Agents (18)

**Role Agents (9)** — dispatched per-step:

| Agent | Role | When |
|-------|------|------|
| `architect` | API contracts, ADRs, system design | Always first |
| `domain` | Domain models, entities, invariants | After architect |
| `backend` | Server-side code, APIs, services | Parallel with frontend |
| `frontend` | UI components, pages, client logic | Parallel with backend |
| `qa` | Tests (unit, integration, e2e) | After implementation |
| `security` | OWASP review, SAST, AuthZ | After implementation |
| `observability` | Logging, metrics, tracing | After implementation |
| `docs-writer` | API docs, guides, changelogs | After implementation |
| `release` | Versioning, deployment config | Last |

**Specialist Agents (3):**

| Agent | Purpose |
|-------|---------|
| `curator` | Collects improvement notes, auto-evaluates, dispatches fixes |
| `auditor` | Post-EPIC audit — code, security, docs, process (0-100 score) |
| `project-scanner` | Tech stack detection → `project-profile.yaml` |

**Utility Agents (6):**

| Agent | Purpose |
|-------|---------|
| `code-reviewer` | Reviews code against plan + standards |
| `docs-reviewer` | Reviews docs for format compliance |
| `quality-gates-runner` | Runs 6-gate pre-commit protocol |
| `gate-fixer` | Analyzes gate failures, applies targeted fixes |
| `run-validator` | Validates run file completeness |
| `lessons-extractor` | Extracts lessons from completed runs |

## Skills (21)

| Skill | Purpose |
|-------|---------|
| `epic-orchestration` | 12-state Controller FSM (includes FIRST AID auto-mode conditionals) |
| `brainstorming` | 9-step brainstorming process |
| `workflow-intelligence` | Workflow/agent project detection, domain questioning (WF1-WF7), platform recommendations, UI derivation |
| `agent-core` | Core agent behavior, roles, workflow routing |
| `planner` | Plan generation — dependency graph, parallel groups, analysis groups |
| `parallel-dispatch` | Parallel agent dispatch — branches, conflict detection, merge |
| `gates-engine` | Post-step gates — YAML parsing, execution, reporting |
| `retry-engine` | Gate failure retry — analysis, fix dispatch, escalation |
| `quality-gates` | 6-gate pre-commit protocol |
| `run-management` | Run lifecycle, handoffs, epic tracking |
| `analysis-merge` | Multi-perspective analysis — union, consensus, weighted strategies |
| `improvement-proposals` | Improvement note format, collection, deduplication |
| `slack-mcp` | Slack MCP integration — 7 message types, fallback, timeouts |
| `epic-queue` | EPIC queue management — add, remove, prioritize, auto-pickup |
| `memory-mcp` | Qdrant vector memory — semantic search, auto-indexing |
| `cost-optimization` | Model selection, file scoping, dispatch trimming |
| `analytics` | Performance metrics, bottleneck detection, trend reports |
| `knowledge-acquisition` | Research pipeline, quality gates, aging protocol |
| `permission-sandwich` | FIRST AID permission management — backup, elevate, restore, learning |
| `auto-escalation` | FIRST AID escalation triggers, pause/resume, PM interaction format |
| `auto-done-state` | FIRST AID DONE state — auto-release, queue transitions, summary |

## Controller State Machine

```
/aid-run-epic (manual)            /aid-first-aid (autonomous queue)
       │                                    │
       ├────────────────────────────────────┘
       ↓
IDLE → PLANNING → PLAN_REVIEW ──────────────────────┐
                      │                              │
              Manual: PM approves           Auto: validated by AI
                      │                              │
                      ├──────────────────────────────┘
                      ↓
EXECUTING ←──── NEXT_PHASE ←── PHASE_CHECK
    │                                │
dispatch agents            check outputs + scope
(parallel where possible)
    │
all steps done
    ↓
GATES ──→ GATE_RETRY (auto-fix, max 3) ──→ ESCALATION (PM always)
    │
all pass
    ↓
CURATOR_RESOLVE (improvement proposals, lessons learned)
    ↓
PM_APPROVAL ────────────────────────────────┐
    │                                       │
Manual: PM approves merge          Auto: 4 guardrails check
    │                                       │
    ├───────────────────────────────────────┘
    ↓
DONE (auditor, release, archive, next EPIC from queue)
```

**Manual mode** — 3 PM touchpoints: PLAN_REVIEW, ESCALATION, PM_APPROVAL.
**FIRST AID mode** — only ESCALATION requires PM; plan review and merge are agent-validated.

## Memory (Optional)

Qdrant MCP server enables long-term vector memory. Agents search past decisions, patterns, and lessons before each step.

```bash
claude mcp add qdrant-memory \
  -e QDRANT_URL="http://localhost:6333" \
  -e COLLECTION_NAME="aid-memory" \
  -- uvx mcp-server-qdrant
```

Set `memory.enabled: true` in `.aid-o/03-config/policies/memory-config.yaml`.

Without Qdrant, the plugin works identically using file-based memory (active-work.md, lessons-learned.md, command-history.md).

## Workspace Structure

```
.aid-o/
  01-plans/              Plans (brainstorming output)
  02-epics/              EPICs (task specifications)
  03-config/
    policies/            gates.yaml, decision-policies.yaml, slack-config.yaml, ...
    templates/           EPIC template, run templates, plan schema
    playbooks/           11 role playbooks (customizable per project)
  04-engine/
    runs/                Active + archived run files
    memory/              project-profile.yaml, active-work.md
    evidence/            Execution evidence (per EPIC, per run)
    backlog.md           Discovered issues backlog
    lessons-learned.md   Accumulated lessons
    command-history.md   Known working commands
```

## Configuration

`/aid-setup` auto-configures everything. Fine-tune in `.aid-o/03-config/`:

| File | Controls |
|------|----------|
| `policies/gates.yaml` | Gate commands, retry limits, budget |
| `policies/decision-policies.yaml` | Autonomy level — what Controller decides vs. escalates |
| `policies/dispatch-strategy.yaml` | Parallel isolation — worktrees / branches / sequential |
| `policies/slack-config.yaml` | Slack channel, timeouts, reminders |
| `policies/memory-config.yaml` | Qdrant vector memory settings |
| `policies/release-policy.yaml` | Version files, SemVer rules, git tag/release settings |
| `policies/permissions-auto.yaml` | FIRST AID permission template (allow/deny lists) |
| `playbooks/*.md` | Role-specific agent instructions |

## Version

- **Plugin:** 1.0.0
- **Requires:** Claude Code >= 1.0.0
- **License:** AGPL-3.0-only
