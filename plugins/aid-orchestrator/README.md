# AID — AI Development Orchestrator

A Claude Code plugin implementing **Controller + Workers** architecture for multi-agent software development.

## What It Does

1. **Brainstorming** — PM + AI explore ideas, compare approaches, make design decisions → Plan document
2. **EPIC** — PM converts plan into a structured task specification (scope, constraints, acceptance criteria, steps)
3. **Plan Generation** — `/plan-epic` generates execution plan with dependency graph, parallel groups, analysis groups
4. **Agent Dispatch** — Controller sends work to role-based agents (Architect, Domain, Backend, Frontend, QA, Security, Observability, Docs, Release)
5. **Quality Gates** — tests, lint, security scan, docs check — with auto-fix retry logic
6. **PM Communication** — Slack MCP or chat fallback at key checkpoints (plan approval, escalation, merge approval)
7. **Evidence Trail** — every decision, prompt, output, and gate result is recorded
8. **EPIC Queue** — queue multiple EPICs for autonomous sequential execution

## Quick Start

```bash
# 1. Initialize and configure for your project
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

## Commands (19)

| Command | Description |
|---------|-------------|
| `/aid-init` | Initialize `.aid-o/` workspace with default config |
| `/aid-setup` | Interactive project onboarding — detect tech stack, configure AID |
| `/aid-brainstorm [topic]` | 9-step interactive brainstorming flow → plan + optional EPIC draft |
| `/aid-help [topic]` | Show AID documentation (commands, workflow, agents, FAQ) |
| `/aid-analytics [scope]` | Analyze orchestration performance metrics and get optimization recommendations |
| `/plan-epic <path>` | Parse EPIC → generate Plan JSON + session file |
| `/run-epic [id]` | Run Controller state machine for full EPIC orchestration |
| `/run-step <id> <step>` | Manually run one step from an existing plan |
| `/epic-status [id]` | Show EPIC pipeline status — steps, gates, budget |
| `/run-gates [id]` | Run quality gates for an EPIC |
| `/epic-queue [sub]` | Manage EPIC execution queue (add, remove, pause, resume) |
| `/quality-gates` | Run 6-gate pre-commit quality protocol |
| `/session-start` | Start a new tracked session |
| `/session-end` | Complete and archive current session |
| `/handoff` | Create handoff block for next AI session |
| `/audit` | Run project health audit |
| `/coding-standards` | Load project coding standards |
| `/testing` | Load testing workflow and standards |
| `/docs-protocol` | Load documentation protocol |

## Agents (18)

**Role Agents (9)** — dispatched per-step during EPIC execution:

| Agent | Role | When |
|-------|------|------|
| `architect` | API contracts, ADRs, system design | Always first |
| `domain` | Domain models, entities, invariants | After architect |
| `backend` | Server-side code, APIs, services | After domain |
| `frontend` | UI components, pages, client logic | After architect |
| `qa` | Unit, integration, e2e tests | After implementation |
| `security` | OWASP review, SAST, AuthZ | After implementation |
| `observability` | Logging, metrics, tracing, health | After implementation |
| `docs-writer` | API docs, guides, changelogs | After implementation |
| `release` | Versioning, deployment config | Last |

**Specialist Agents (3):**

| Agent | Purpose |
|-------|---------|
| `curator` | Collects improvement notes from agents, proposes improvements |
| `auditor` | Post-EPIC audit — code, security, docs, health scoring |
| `project-scanner` | Tech stack detection, project analysis → `project-profile.yaml` |

**Utility Agents (6):**

| Agent | Purpose |
|-------|---------|
| `code-reviewer` | Reviews code against plan + coding standards |
| `docs-reviewer` | Reviews docs for format compliance |
| `quality-gates-runner` | Runs 6-gate pre-commit protocol |
| `session-validator` | Validates session file completeness |
| `lessons-extractor` | Extracts lessons from completed sessions |
| `gate-fixer` | Analyzes gate failures, applies targeted fixes |

## Skills (16)

| Skill | Purpose |
|-------|---------|
| `epic-orchestration` | 11-state Controller FSM |
| `brainstorming` | 9-step brainstorming process, EPIC subagent prompt template |
| `agent-core` | Core agent behavior, roles, workflow routing |
| `quality-gates` | 6-gate pre-commit protocol |
| `session-management` | Session lifecycle, handoffs, epic tracking |
| `gates-engine` | Post-step gates — YAML parsing, execution, reporting |
| `retry-engine` | Gate failure retry — analysis, fix dispatch, escalation |
| `planner` | Plan generation — dependency graph, parallel groups, analysis groups |
| `parallel-dispatch` | Parallel agent dispatch — branches, conflict detection, merge |
| `analysis-merge` | Multi-perspective analysis — union, consensus, weighted strategies |
| `improvement-proposals` | Standard format for improvement notes, collection, deduplication |
| `slack-mcp` | Slack MCP integration — 7 message types, fallback, timeouts |
| `epic-queue` | EPIC queue management — add, remove, prioritize, auto-pickup |
| `memory-mcp` | Qdrant vector memory — semantic search, auto-indexing, agent context |
| `cost-optimization` | Model selection, file scoping, dispatch trimming, token tracking |
| `analytics` | Performance metrics analysis, bottleneck detection, trend reports |

## Controller State Machine

```
IDLE ──→ PLANNING ──→ PLAN_REVIEW ──→ EXECUTING ──→ PHASE_CHECK
                          ↑               ↑               │
                          │ revise        │ more steps     │
                          └───────────────┤               ↓
                                          └─── NEXT_PHASE
                                                          │
                                                   all steps done
                                                          ↓
                                          GATES ──→ GATE_RETRY (max 3)
                                            │              │
                                        all pass    retries exhausted
                                            ↓              ↓
                                      PM_APPROVAL    ESCALATION
                                            │         (PM decides)
                                        approved
                                            ↓
                                          DONE
                                    (Curator + Auditor)
                                            │
                                     queue not empty?
                                            ↓
                                    auto-start next EPIC
```

**PM Checkpoints** (via Slack or chat fallback):
- **PLAN_REVIEW**: approve execution plan (GO / REVISE / ABORT)
- **ESCALATION**: handle failures (Fix / Skip / Abort)
- **PM_APPROVAL**: approve merge (APPROVE / REJECT / REVISE)

## Memory (Optional)

AID supports **long-term vector memory** via Qdrant MCP server. When enabled, agents
can search past decisions, lessons, and patterns semantically — improving output quality
over time.

**Setup:**
```bash
# Install Qdrant MCP server
claude mcp add qdrant-memory \
  -e QDRANT_URL="http://localhost:6333" \
  -e COLLECTION_NAME="aid-memory" \
  -- uvx mcp-server-qdrant

# Enable in AID config
# Set memory.enabled: true in .aid-o/03-config/policies/memory-config.yaml
```

**What gets indexed:**
- Session-end: decisions, lessons learned, working commands
- EPIC completion: architectural decisions, code patterns, audit findings
- Per-agent metrics: step duration, complexity, bottleneck flags

**What agents receive:** Before each step, the Controller searches memory for relevant
past knowledge and injects it as `## MEMORY CONTEXT (from past sessions)` in the agent prompt.

**Cross-project knowledge:** All Qdrant entries include `project_name` metadata. When
multiple projects share the same Qdrant collection, agents can discover patterns and
lessons from related projects. Use `/aid-analytics global` to compare across projects.

**Without Qdrant:** Plugin works identically using file-based memory only (active-work.md,
lessons-learned.md, command-history.md). Qdrant is supplementary, never required.

## Multi-Session EPICs

For larger EPICs (7+ steps), the Planner automatically splits execution into multiple
sessions optimized for speed and quality. Each session runs independently with handoff
state preserved between them. Use `/run-epic E-xxx --session N` to run a specific session.
The Planner decides the optimal split based on dependency analysis and parallel opportunity
detection — PM approves the session plan.

## Cost Optimization

AID optimizes token usage and model costs through 4 axes:
- **Model selection** — QA, Security, and Docs agents use Sonnet; Utility agents use Haiku
- **File scoping** — agents receive only the files relevant to their step, not the entire codebase
- **Dispatch trimming** — agent prompts include deps-only context, EPIC summary, and playbook reference
- **Token tracking** — per-step and per-EPIC token estimates stored in Qdrant for trend analysis

Use `/aid-analytics` to review cost trends and identify optimization opportunities.

## Workspace Structure

`/aid-init` creates in your project:

```
.aid-o/
  01-plans/              Plans (PM + AI brainstorming)
  02-epics/              EPICs (task specifications)
  03-config/
    policies/            gates.yaml, decision-policies.yaml, slack-config.yaml, memory-config.yaml
    templates/           EPIC template, session templates, plan schema
    playbooks/           9 role playbooks + 2 docs platform playbooks
  04-engine/
    sessions/            Active + archived session files
    memory/              project-profile.yaml, active-work.md, decisions.yaml
    evidence/            EPIC execution evidence (per epic, per run)
    backlog.md           Discovered issues backlog
    lessons-learned.md   Accumulated lessons
    command-history.md   Known working commands
```

## Configuration

After `/aid-setup`, customize in `.aid-o/03-config/`:

| File | What to customize |
|------|-------------------|
| `policies/gates.yaml` | Gate commands, retry limits, budget |
| `policies/decision-policies.yaml` | Autonomy level — what Controller decides vs. escalates |
| `policies/slack-config.yaml` | Slack channel, timeouts, reminder intervals |
| `policies/memory-config.yaml` | Qdrant vector memory — collection, auto-index triggers, search |
| `policies/dispatch-strategy.yaml` | Parallel isolation — worktrees / branches / sequential |
| `policies/language.yaml` | Document language — ISO 639-1 code (default: EN) |
| `playbooks/*.md` | Role-specific agent instructions for your project |

`/aid-setup` also configures **permission presets** (Safe / Recommended / Advanced) and **document language** (ISO 639-1) during onboarding.

## Version

- **Plugin:** 0.3.0-rc.1
- **Requires:** Claude Code >= 1.0.0
- **License:** MIT
