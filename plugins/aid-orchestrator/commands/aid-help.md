---
name: aid-help
description: AID documentation and help topics
user_invocable: true
---

Show AID documentation — commands, workflow, agent roles, configuration, and FAQ.

AID's self-knowledge command. Explains everything about how AID works, what commands are available, and how to use the orchestration system.

## Usage

```
/aid-help [topic]
```

**Topics:** `commands`, `workflow`, `epic`, `agents`, `planning`, `gates`, `evidence`, `config`, `slack`, `queue`, `memory`, `analytics`, `inputs`, `examples`, `faq`

**Examples:**
```
/aid-help                   # full overview
/aid-help commands          # detail on every command
/aid-help workflow          # Plan → EPIC → Run flow
/aid-help epic              # how to write an EPIC
/aid-help agents            # 18 agent roles + specialists
/aid-help planning          # planner, parallelization, analysis groups
/aid-help gates             # quality gates + retry logic
/aid-help evidence          # evidence store structure
/aid-help config            # configuration files
/aid-help slack             # Slack integration + PM communication
/aid-help queue             # Epic queue + autonomous pipeline
/aid-help memory            # Qdrant vector memory + semantic search
/aid-help analytics          # performance analysis of orchestration metrics
/aid-help inputs            # input files for brainstorming
/aid-help examples          # interactive project prompts to try /aid-brainstorm
/aid-help faq               # frequently asked questions
```

## Flow

### Step 1: Check Environment

1. Check if `.aid-o/` exists in current project
2. If exists: note active EPICs count, runs count (for dynamic info)
3. If not exists: include recommendation to run `/aid-init` or `/aid-setup`

### Step 2: Display Based on Topic

---

#### No topic (full overview)

Display the complete AID overview:

```
AID — AI Development Orchestrator
====================================
Version: 0.6.0

What is AID?
  AID is a multi-agent orchestration system for Claude Code. It takes
  an EPIC (detailed task specification) and autonomously dispatches
  specialized agents to complete it — with quality gates, retry logic,
  and PM escalation when needed.

  Think of it as a project manager that coordinates 9 specialist agents
  to deliver features end-to-end: architecture → implementation → testing
  → security → documentation → release.

Commands (11):
  /aid-init          Initialize or upgrade .aid-o/ workspace
  /aid-setup         Interactive project onboarding
  /aid-brainstorm    9-step interactive brainstorming flow
  /aid-help          This help
  /aid-plan-epic     EPIC or Plan → Plan JSON + run file
  /aid-research      On-demand documentation research (topic, URL, --deep)
  /aid-run-epic      Start orchestration (state machine)
  /aid-epic-status   Show pipeline status
  /aid-epic-queue    Manage EPIC execution queue (add, list, pause, resume)
  /aid-audit         Project health audit
  /aid-analytics     Performance analysis of orchestration metrics

Quick Start:
  1. /aid-setup                                   ← first time only
  2. /aid-brainstorm                              ← explore ideas with AI
  3. Create EPIC in .aid-o/02-epics/              ← your task spec
  4. /aid-plan-epic .aid-o/02-epics/my-epic.md    ← generate plan
  5. /aid-run-epic                                ← orchestrator takes over

Where things live:
  .aid-o/01-plans/      Plans (brainstorming)
  .aid-o/02-epics/      EPICs (task specs)
  .aid-o/03-config/     Configuration
  .aid-o/04-engine/     AI internals (runs, evidence, memory)
  .aid-o/05-inputs/     Sample data files for brainstorming

Topics: /aid-help commands | workflow | epic | agents | planning | gates | evidence | config | slack | queue | memory | research | analytics | inputs | examples | faq
{If .aid-o/ not found:}

  ⚠ No .aid-o/ workspace found. Run /aid-setup to get started.
{If .aid-o/ found:}

  Status: {N} active EPICs, {M} runs
```

---

#### Topic: commands

```
AID Commands — Detailed Reference
====================================

SETUP COMMANDS:

  /aid-init [path]
    Initialize or upgrade .aid-o/ workspace.
    Usage: /aid-init [path]
    Optional path: target directory to initialize (defaults to current directory).
    Fresh install: creates directories, policies, templates, playbooks, engine files.
    Upgrade: detects version mismatch, classifies files (new/upgradable/custom/protected),
    asks PM for approval, updates only non-customized files.
    Tracks state via .aid-o/03-config/.aid-manifest.yaml (checksums + version).

  /aid-setup
    Interactive onboarding. Detects tech stack, configures AID.
    Usage: /aid-setup
    Flow: detect → analyze → present → configure
    Calls /aid-init internally if needed.

  /aid-brainstorm [topic]
    9-step interactive brainstorming flow.
    Usage: /aid-brainstorm "Build a REST API with auth and CRUD"
    Flow: context → questions → approaches → design → sections → approval
          → document → EPIC draft → handoff
    Output: Plan document in .aid-o/01-plans/ + optional EPIC draft

  /aid-help [topic]
    This help. Shows commands, workflow, FAQ.
    Topics: commands, workflow, epic, agents, gates, evidence, config, examples

  /aid-research [--deep] <framework> [topic]
  /aid-research <url>
    On-demand knowledge research. Researches framework documentation,
    stores quality-gated chunks in Qdrant for agent use.
    Three modes:
      topic: /aid-research FastAPI WebSockets         (quick overview)
      deep:  /aid-research --deep LangGraph            (extended API reference)
      url:   /aid-research https://docs.celery.dev/    (index specific page)
    Requires: .aid-o/ workspace. Optional: Qdrant, Context7 MCP.
    Stores: documentation chunks in Qdrant (or run-only without Qdrant).

ORCHESTRATION COMMANDS:

  /aid-plan-epic <path>
    Unified Plan→EPIC→Plan entry point: accepts an EPIC or a Plan file and
    generates a Plan JSON + run file ready for /aid-run-epic.
    Accepts:
      EPIC file: /aid-plan-epic .aid-o/02-epics/E-YYYYMMDD-xxxx.md  (standard)
      Plan file: /aid-plan-epic .aid-o/01-plans/2026-02-19-plan.md   (auto-generates EPIC first)
    Output: plan.json, plan_progress.json, run file
    When given a Plan, the command auto-generates an EPIC using the EPIC
    Subagent Template, shows it to PM for review, then proceeds with plan
    generation — all in one invocation. After plan generation, PM is asked
    whether to run the EPIC now, review the plan, or execute a single step.

  /aid-run-epic [epic-id]
    Start the Controller state machine.
    Usage: /aid-run-epic TEST-0001
    States: IDLE → PLANNING → PLAN_REVIEW → EXECUTING → PHASE_CHECK
            → GATES → CURATOR_RESOLVE → PM_APPROVAL → DONE
    PM checkpoints: plan review, escalation, final approval
    Auto-decisions: scope check, gate retry, step progression

  /aid-epic-status [epic-id]
    Show pipeline status.
    Usage: /aid-epic-status TEST-0001   (detailed)
           /aid-epic-status             (overview of all)
    Shows: step progress, gates, budget, recent activity

  /aid-epic-queue [subcommand]
    Manage EPIC execution queue for autonomous pipeline.
    Usage: /aid-epic-queue                        (show queue)
           /aid-epic-queue add <path> [--priority high]
           /aid-epic-queue remove <epic-id>
           /aid-epic-queue next                   (show next in line)
           /aid-epic-queue pause                  (pause auto-pickup)
           /aid-epic-queue resume                 (resume auto-pickup)
           /aid-epic-queue reorder <id> --priority <level>
    Auto-pickup: after EPIC DONE, next queued EPIC starts automatically.
    Skill: skills/epic-queue.md

ANALYTICS COMMANDS:

  /aid-analytics [scope]
    Analyze orchestration performance metrics from Qdrant.
    Usage: /aid-analytics E-20260219-v030   (single EPIC report)
           /aid-analytics project            (project trends)
           /aid-analytics global             (cross-project comparison)
           /aid-analytics                    (most recent EPIC)
    Requires: Qdrant configured, at least one completed EPIC.
    Output: executive summary, bottleneck analysis, recommendations.
    Skill: skills/analytics.md

QUALITY COMMANDS:

  /aid-audit         Project health audit
```

---

#### Topic: workflow

```
AID Workflow — Plan → EPIC → Run
====================================

The AID workflow has three layers:

  PLAN (brainstorming)
    ↓ PM + AI collaborate on approach
  EPIC (specification)
    ↓ PM + AI detail the task
  RUN (execution)
    ↓ AI executes autonomously

1. PLAN (.aid-o/01-plans/)
   - PM describes what they want
   - AI brainstorms approaches, trade-offs
   - Result: Plan document with chosen approach
   - Naming: P-{YYYYMMDD}-{hash}-{topic}.md

2. EPIC (.aid-o/02-epics/)
   - Detailed specification of the work
   - Sections: Goal, Scope, Constraints, DoD, Acceptance Criteria, Steps
   - Each step defines a role (architect, backend, qa, etc.)
   - Naming: E-{YYYYMMDD}-{hash}-{topic}.md

3. RUN (.aid-o/04-engine/runs/)
   - Auto-generated from EPIC by /aid-plan-epic
   - Tracks progress, commits, decisions
   - One run per EPIC run (or per sub-run for multi-run EPICs)
   - Naming: R-{YYYYMMDD}-{hash}-{topic}.md

Orchestration Flow:
  /aid-plan-epic → generates Plan JSON from EPIC
  /aid-run-epic  → executes plan (state machine):

    IDLE ──→ PLANNING ──→ PLAN_REVIEW (PM checkpoint)
                              │
                              ▼ PM says GO
                          EXECUTING ──→ PHASE_CHECK ──→ NEXT_PHASE
                              ▲                            │
                              └────────────────────────────┘
                                                           │
                                                    all steps done
                                                           │
                                                           ▼
                                            GATES ──→ GATE_RETRY (max 3)
                                              │
                                          all pass
                                              │
                                              ▼
                                      CURATOR_RESOLVE (auto-evaluate proposals)
                                              │
                                       proposals resolved
                                              │
                                              ▼
                                      PM_APPROVAL (PM checkpoint)
                                              │
                                          approved
                                              │
                                              ▼
                                            DONE

PM Interaction Points (via Slack or chat fallback):
  - PLAN_REVIEW: approve execution plan (GO / REVISE / ABORT)
  - ESCALATION: handle failures (fix / skip / abort)
  - PM_APPROVAL: approve merge, override rejected proposals ("fix IMP-{NNN}"),
    teach auto-rules ("always approve {type/area}") (APPROVE / REJECT / REVISE)
  - AUDITOR summary: informational (no reply needed)

Communication: skills/slack-mcp.md (Slack preferred, chat fallback)
Config: .aid-o/03-config/policies/slack-config.yaml

Epic Queue (autonomous pipeline):
  /aid-epic-queue add <path> → queue EPICs
  After DONE → auto-pickup next EPIC from queue
  /aid-epic-queue pause/resume → control auto-pickup

Multi-Run EPICs:
  For larger EPICs (7+ steps), the Planner automatically splits execution into
  multiple runs optimized for speed and quality. Each run runs
  independently with handoff state preserved. Use /aid-run-epic E-xxx --run N
  to run a specific run. The Planner decides the optimal split — PM approves.

Everything else is autonomous (auto-decisions from decision-policies.yaml).
```

---

#### Topic: epic

```
How to Write an EPIC
====================================

Template: .aid-o/03-config/templates/epic.md

Required Sections:

  ## Goal
  What must be true when this EPIC is complete.
  1-3 sentences. Specific and testable.

  ## Scope
  ### Allowed files/paths
  List of files/dirs the agents may modify.
  ### Forbidden zones
  Files/dirs agents must NOT touch.

  ## Constraints
  Budget, patterns, requirements, tenant safety, etc.

  ## DoD Gates
  Which quality gates apply: tests_pass, lint_pass,
  security_scan_pass, docs_updated

  ## Acceptance Criteria
  Specific, testable criteria. Use checkboxes.
  - [ ] Criterion 1
  - [ ] Criterion 2

  ## Steps (Role Pipeline)
  Table with columns: #, Role, Objective, Depends On, Parallel Group

  | # | Role | Objective | Depends On | Parallel Group |
  |---|------|-----------|------------|----------------|
  | 1 | architect | Design API contracts | — | — |
  | 2 | backend | Implement endpoints | architect | group-1 |
  | 3 | frontend | Build UI | architect | group-1 |
  | 4 | qa | Write tests | backend, frontend | — |

Available Roles:
  architect, domain, backend, frontend, qa,
  security, observability, docs, release

Tips:
  - Architect ALWAYS first (contracts before code)
  - Put backend + frontend in parallel groups
  - QA + Security + Observability can run in parallel
  - Docs after implementation, Release last
  - Keep scope tight — smaller EPICs are better
```

---

#### Topic: agents

```
AID Agents — 18 Total (9 Role + 3 Specialist + 6 Utility)
====================================

ROLE AGENTS (9) — dispatched per-step during EPIC execution:

  ARCHITECT (agents/architect.md, playbook: architect.md)
    Designs API contracts, ADRs, system architecture.
    Runs FIRST. Does NOT implement — only designs.
    Outputs: OpenAPI specs, ADR documents, architecture diagrams.

  DOMAIN (agents/domain.md, playbook: domain.md)
    Defines domain models, entities, business rules.
    Runs after Architect. Uses contracts to define models.
    Outputs: Entity definitions, invariants, domain events.

  BACKEND (agents/backend.md, playbook: backend.md)
    Implements server-side code, APIs, services.
    Can run in parallel with Frontend.
    Outputs: Endpoint implementations, services, migrations.

  FRONTEND (agents/frontend.md, playbook: frontend.md)
    Implements UI components, pages, client-side logic.
    Can run in parallel with Backend.
    Outputs: Components, pages, styles, client utilities.

  QA (agents/qa.md, playbook: qa.md)
    Writes tests — unit, integration, e2e.
    Does NOT implement features — only tests.
    Outputs: Test files, test fixtures, coverage reports.

  SECURITY (agents/security.md, playbook: security.md)
    Reviews code for vulnerabilities (OWASP, secrets, etc.).
    Can patch simple findings directly.
    Outputs: Security review, patches, recommendations.

  OBSERVABILITY (agents/observability.md, playbook: observability.md)
    Adds logging, metrics, tracing, health checks.
    Outputs: Logging setup, metric definitions, dashboards.

  DOCS-WRITER (agents/docs-writer.md, playbook: docs.md)
    Updates documentation — API docs, guides, changelogs.
    Runs after implementation steps.
    Outputs: Updated docs, API references, changelog entries.

  RELEASE (agents/release.md, playbook: release.md)
    Handles versioning, changelog, release notes.
    Runs LAST (after gates pass).
    Outputs: Version bump, release notes, deployment config.

  Every role agent produces improvement_notes in their output
  (observations about code outside their scope → Curator collects).

Default Execution Order:
  Architect → Domain → (Backend + Frontend) → (QA + Security + Obs) → Docs → Release

SPECIALIST AGENTS (3) — triggered by specific events:

  CURATOR (agents/curator.md)
    Triggered: CURATOR_RESOLVE state (after gates pass, before PM_APPROVAL)
    Collects improvement_notes from all role agents, deduplicates
    against backlog, analyzes patterns, proposes improvements.
    Flow: collect → deduplicate → analyze → propose → auto-evaluate
          → fix approved → PM sees summary at PM_APPROVAL
    Auto-evaluate: 3-tier (YAML rules → Qdrant history → default)
    PM can override rejections ("fix IMP-{NNN}") or teach rules
    ("always approve {type}") at PM_APPROVAL.
    Output: curator_resolve_report.json + backlog.md updates
    See: skills/improvement-proposals.md, decision-policies.yaml → curator_auto_rules

  AUDITOR (agents/auditor.md)
    Triggered: after Epic DONE (post-merge)
    Runs 5 audit types: Code, Security, Documentation,
    Frontend (conditional), Database (conditional).
    Scores project health (0-100), tracks trends vs previous audit.
    Output: audit_report (YAML + Markdown) in evidence/

  PROJECT-SCANNER (agents/project-scanner.md)
    Triggered: /aid-setup (quick scan) or on-demand (deep analysis)
    Quick scan: tech stack, structure, conventions → project-profile.yaml
    Deep analysis: + quality metrics, dependencies, tech debt
    Output: .aid-o/04-engine/memory/project-profile.yaml

UTILITY AGENTS (6) — support functions:

  code-reviewer, docs-reviewer, quality-gates-runner,
  run-validator, lessons-extractor, gate-fixer
```

---

#### Topic: planning

```
Planning, Parallelization & Analysis Groups
====================================

The Planner transforms an EPIC into an executable Plan JSON with dependency
graph, parallel groups, and multi-perspective analysis groups.

Skills: planner.md, parallel-dispatch.md, analysis-merge.md

PLAN GENERATION (/aid-plan-epic):

  1. Parse EPIC steps (role, objective, dependencies)
  2. Build dependency graph (DAG — topological sort)
  3. Detect parallel groups (same-level independent steps)
  4. Auto-generate analysis groups (see below)
  5. Validate and output Plan JSON

  Skill: skills/planner.md (complete algorithm)

DEFAULT STEP ORDER (when EPIC doesn't specify):
  1. Architect (always first — contracts)
  2. Domain (needs contracts)
  3. Backend + Frontend (parallel — depend on contracts)
  4. QA + Security + Observability (parallel — depend on implementation)
  5. Docs (after implementation)
  6. Release (last — after gates)

  EPIC explicit ordering ALWAYS overrides defaults.

PARALLEL GROUPS (different agents, different work, concurrent):

  Parallel groups let independent steps run at the same time.
  Example: Backend + Frontend implement different features in parallel.

  Branch strategy (per parallel-dispatch.md):
    - Base: epic/{epic_id}/main (created from main at EPIC start)
    - Each parallel agent gets own branch
    - After all complete: merge one-by-one into epic/main
    - Git conflicts → ESCALATION (PM decides)

  Skill: skills/parallel-dispatch.md

ANALYSIS GROUPS (same target, different perspectives, read-only):

  Analysis groups let multiple agents review the SAME completed step
  from different angles. They are READ-ONLY (no code changes).

  Example: security + architect + backend review backend's auth code.

  Key difference from parallel groups:
    parallel_groups  → different work, code changes, branches
    analysis_groups  → same target, reports only, no branches

  Auto-trigger rules (Planner generates automatically):
    - Security-relevant step → [security] review (union)
    - High complexity step → [architect] review (weighted)
    - Database changes → [backend, security] validation (consensus)
    - API contract changes → [backend, frontend] validation (union)

  Manual: EPIC can define analysis_groups explicitly (overrides auto).

  3 Merge Strategies:
    union     — all findings collected, nothing lost (safest)
    consensus — only findings confirmed by 2+ agents (high confidence)
    weighted  — findings ranked by domain expertise (prioritized)

  Skill: skills/analysis-merge.md

ANALYSIS REPORT OUTPUT:

  Generated per analysis group → evidence/analysis/{group_id}/
  Contains: findings by severity, action items, statistics,
  improvement_notes (merged from all analysis agents).

  Critical findings → ESCALATION (PM must acknowledge)
  High findings → warning (non-blocking)

Plan JSON Schema:
  .aid-o/03-config/templates/plan.schema.json
  Includes: steps, dependencies, parallel_groups, analysis_groups,
  gates, budget.
```

---

#### Topic: gates

```
Quality Gates
====================================

AID has TWO gate systems:

1. AID Gates Engine (post-EPIC-steps)
   Invoked by: /aid-run-epic (GATES state)
   Config:   .aid-o/03-config/policies/gates.yaml
   Skills:   gates-engine.md, retry-engine.md
   Agent:    gate-fixer.md (auto-fix on failure)
   Purpose:  Validate entire EPIC output before PM approval

2. Pre-Commit Quality Gates
   Skill:    quality-gates.md
   Agent:    quality-gates-runner.md
   Purpose:  6-gate commit-level quality check

AID Gates Engine — Detail:

  Config: .aid-o/03-config/policies/gates.yaml

  4 Required Gates:
    1. tests_pass        All tests pass (unit + integration)
    2. lint_pass         Code passes linting + formatting
    3. security_scan     No high/critical security findings
    4. docs_updated      Documentation updated for changed APIs

  2 Conditional Gates (run only when condition met):
    5. type_check        TypeScript passes (when frontend files changed)
    6. build_pass        Frontend builds (when frontend files changed)

  Gate Types:
    - Command gates: execute a shell command, check exit code
    - Rule gates: evaluate a logical rule (e.g., "docs updated?")

  Retry Logic:
    - Each gate can fail up to 3 times (configurable in gates.yaml)
    - On failure: gate-fixer agent analyzes error, applies fix
    - After fix: re-run failed gate, then re-check ALL gates
    - After max retries: escalate to PM with options (skip/fix/abort)

  Gate Flow in /aid-run-epic:
    All steps done
        ↓
    GATES state: run all required gates
        ↓
    Any fail? → GATE_RETRY → gate-fixer → re-run gate
        ↓
    Max retries? → ESCALATION (PM decides: skip / manual fix / abort)
        ↓
    All pass → PM_APPROVAL

  Evidence (per gate run):
    gates_report.json           Structured report with retry history
    gates/tests_pass.txt        Raw command output
    gates/retry_lint_pass_1.md  Fix agent output (per attempt)

  Customization:
    Edit .aid-o/03-config/policies/gates.yaml to:
    - Change gate commands (e.g., pytest → jest, ruff → eslint)
    - Add/remove gates
    - Adjust retry limits (max_attempts, backoff)
    - Set budget constraints
    /aid-setup auto-configures gates for your tech stack.
```

---

#### Topic: evidence

```
Evidence Store
====================================

Location: .aid-o/04-engine/evidence/{epic_id}/{run_id}/

Structure:
  evidence/
    {epic_id}/
      {run_id}/
        epic_input.md           Original EPIC (immutable copy)
        plan.json               Execution plan (incl. analysis_groups)
        plan_progress.json      Step completion tracker
        pm_plan_approval.json   PM's plan approval
        pm_decision.json        PM decisions (escalations, final)
        stage_log.jsonl         State transition log
        gates_report.json       Gate results + retries
        final_report.md         Run summary
        prompts/                Agent prompts sent
          step_1_architect.md
          step_2_domain.md
        steps/                  Agent outputs
          step_1_architect/
            output.md
            diff.patch
          step_2_domain/
            output.md
            diff.patch
        parallel_groups/        Parallel execution evidence
          group_{N}/
            dispatch_log.json
            merge_log.json
            branch_status.json
        analysis/               Multi-perspective analysis results
          analysis_1_security_review/
            raw_security.yaml
            analysis_report.yaml
        gates/                  Gate command outputs + retry evidence
          tests_pass.txt
          lint_pass.txt
          retry_lint_pass_1.md  Fix agent attempt evidence

Key Files:
  plan_progress.json  — current state, which steps done/pending
  stage_log.jsonl     — every state transition (timestamped)
  gates_report.json   — gate pass/fail with retry history
  final_report.md     — human-readable summary of the run

Rules:
  - No secrets in evidence (redacted before saving)
  - Every state transition logged to stage_log.jsonl
  - Original EPIC is immutable — never modified
```

---

#### Topic: config

```
AID Configuration
====================================

All config lives in .aid-o/03-config/

Policies (.aid-o/03-config/policies/):

  gates.yaml
    Gate definitions, commands, retry config, budget.
    Customize: gate commands for your stack, retry limits.

  decision-policies.yaml
    What the Controller decides autonomously vs. escalates to PM.
    Sections:
    - quality_thresholds (coverage, review score, security)
    - architecture_principles (contract-first, YAGNI, etc.)
    - auto_decisions (7 rules — when Controller proceeds alone)
    - escalation_triggers (7 rules — when PM must decide)
    - acceptable_debt vs. not_acceptable

  slack-config.yaml
    Slack MCP integration settings.
    Set enabled: true to use Slack for PM communication.
    Configure: channel, timeouts, reminders, timeout actions.
    See: /aid-help slack

Templates (.aid-o/03-config/templates/):
  plan.md              Plan document template
  epic.md              EPIC template
  plan.schema.json     JSON schema for Plan JSON
  run-*.md         Run file templates (4 types)

Playbooks (.aid-o/03-config/playbooks/):
  9 role playbooks (architect.md through release.md) + e2e.md.
  Each defines: Role, Mission, Responsibilities, Process,
  Quality Criteria, Constraints.
  E2E playbook: Playwright browser testing (auto-added when frontend detected).

To customize AID for your project:
  1. /aid-setup (auto-configures for your stack)
  2. Edit gates.yaml (gate commands, retry limits)
  3. Edit decision-policies.yaml (autonomy level)
  4. Edit slack-config.yaml (Slack integration)
  5. Edit playbooks (agent behavior)
```

---

#### Topic: slack

```
Slack Integration — PM Communication
====================================

AID communicates with PM via Slack using an external MCP server.
When Slack is disabled (default), all communication is chat-based.

Skill: skills/slack-mcp.md
Config: .aid-o/03-config/policies/slack-config.yaml

SETUP:

  1. Install slack-mcp-server by @korotovsky:
     Configure in .mcp.json (see /aid-setup for full guide)
     Required scopes: chat:write, channels:read, channels:history, users:read
  2. Edit .aid-o/03-config/policies/slack-config.yaml:
     - Set slack.enabled: true
     - Set slack.channel: "#your-channel"
     - Set slack.pm_user_id: "U1234567"
  3. AID will now send all PM messages to Slack

7 MESSAGE TYPES:

  Type A — Escalation (expects reply)
    When: gate failure, agent error, scope violation, budget exceeded
    PM options: Fix (A) / Skip (B) / Abort (C)

  Type B — Plan Approval (expects reply)
    When: Plan JSON generated, needs PM approval
    PM options: GO / REVISE / ABORT

  Type C — Merge Approval (expects reply)
    When: all gates pass, EPIC ready for merge
    Includes: Curator Resolution summary (implemented/rejected/deferred)
    PM options: APPROVE / REJECT / REVISE / Override ("fix IMP-{NNN}")
               / Teach rule ("always approve {type}")

  Type D — Improvement Proposal (expects reply)
    When: Curator proposes improvement, Orchestrator approved
    PM options: APPROVE / DEFER / REJECT

  Type E — Rejection Info (no reply)
    When: Orchestrator rejects a Curator proposal (informational)

  Type F — Audit Summary (no reply)
    When: post-EPIC audit completes (project health scores + findings)

  Type G — Status Update (no reply)
    When: EPIC starts, step completes, gates pass, queue events

TIMEOUTS:

  If PM doesn't respond within configured timeout:
  - Reminders sent at interval (default: every 60 min, max 3)
  - After timeout: configurable action per type:
    plan_approval:  wait (default)
    escalation:     wait (default)
    merge_approval: wait (default)
    proposal:       defer (default — lower priority)

FALLBACK:

  If Slack MCP unavailable or not configured:
  - Messages presented in chat (pre-Slack behavior)
  - Retry 3x on Slack failure, then fall back to chat
  - Status updates silently skipped on failure (non-critical)
```

---

#### Topic: queue

```
Epic Queue — Autonomous Pipeline
====================================

The Epic Queue lets you queue multiple EPICs for sequential execution.
After each EPIC completes, the Orchestrator auto-picks the next one.

Skill: skills/epic-queue.md
Command: /aid-epic-queue
File: .aid-o/04-engine/epic-queue.yaml

USAGE:

  /aid-epic-queue                                     Show queue
  /aid-epic-queue add <path> [--priority high]        Add EPIC
  /aid-epic-queue remove <epic-id>                    Remove from queue
  /aid-epic-queue next                                Show next in line
  /aid-epic-queue pause                               Pause auto-pickup
  /aid-epic-queue resume                              Resume auto-pickup
  /aid-epic-queue reorder <id> --priority <level>     Change priority

PRIORITY LEVELS:

  critical > high > medium (default) > low
  Within same priority: FIFO (first added, first executed)

HOW IT WORKS:

  1. PM queues EPICs:
     /aid-epic-queue add .aid-o/02-epics/E-auth.md --priority high
     /aid-epic-queue add .aid-o/02-epics/E-api-v2.md
     /aid-epic-queue add .aid-o/02-epics/E-dashboard.md --priority low

  2. Start first EPIC:
     /aid-run-epic    (picks up highest priority queued EPIC)

  3. Autonomous loop:
     EPIC 1 → DONE → auto-start EPIC 2 → DONE → auto-start EPIC 3 → DONE → idle

  PM only interacts via Slack (plan approval, escalation, merge approval).

SAFETY:

  - Max 1 EPIC runs at a time (no parallel EPIC execution)
  - Failed EPIC → queue auto-pauses (PM must investigate)
  - /aid-epic-queue pause → stops next pickup (running EPIC continues)
  - Queue persists in YAML (survives run restarts)
```

#### Topic: memory

```
Memory — Qdrant Vector Memory (Optional)
====================================

AID can use Qdrant MCP for long-term semantic memory across runs.
Agents learn from past decisions, patterns, and lessons automatically.

Skill: skills/memory-mcp.md
Config: .aid-o/03-config/policies/memory-config.yaml

SETUP:

  1. Install Qdrant MCP server:
     claude mcp add qdrant-memory \
       -e QDRANT_URL="http://localhost:6333" \
       -e COLLECTION_NAME="aid-memory" \
       -- uvx mcp-server-qdrant

  2. Enable in config:
     Set memory.enabled: true in .aid-o/03-config/policies/memory-config.yaml

  3. Or auto-detect during /aid-setup
     (AID probes for qdrant-find tool availability)

WHAT GETS INDEXED:

  At run-end:
    - Decisions from run log (type: decision)
    - Lessons learned (type: lesson)
    - Working commands (type: command)

  At EPIC completion:
    - Architectural decisions (type: decision)
    - Code/architecture patterns (type: pattern)
    - Audit findings (type: audit_finding)

  On-demand research:
    /aid-research <topic>        Quick framework research
    /aid-research --deep <topic> Extended API reference
    /aid-research <url>          Index specific documentation URL

HOW AGENTS USE IT:

  Before each agent dispatch in EXECUTING state:
    1. Controller searches Qdrant for relevant past knowledge
    2. Results injected as "## MEMORY CONTEXT (from past runs)"
    3. Agent uses as reference (not blindly followed)
    4. If Qdrant unavailable → skip silently, agent works normally

TOOLS (from Qdrant MCP server):

  qdrant-store   Store text + metadata (embedding via FastEmbed, local)
  qdrant-find    Semantic search (returns ranked results with scores)

WITHOUT QDRANT:

  Plugin works identically — file-based memory (active-work.md,
  lessons-learned.md, command-history.md) is always the primary source.
  Qdrant adds semantic search on top, never replaces files.
```

---

#### Topic: analytics

```
Analytics — Performance Analysis
====================================

AID tracks detailed orchestration metrics in Qdrant. The /aid-analytics
command queries these metrics and produces actionable performance reports.

Command: /aid-analytics [scope]
Skill: skills/analytics.md
Requires: Qdrant configured, at least one completed EPIC with metrics

USAGE:

  /aid-analytics E-20260219-v030   Analyze a specific EPIC
  /aid-analytics project           Trends across all EPICs in current project
  /aid-analytics global            Compare across all projects
  /aid-analytics                   Defaults to most recently completed EPIC

3 REPORT TYPES:

  1. EPIC Report (single EPIC)
     - Step-by-step timeline with duration bars
     - Bottleneck analysis with root cause explanation
     - Gate performance (retries, time cost)
     - Token profile (model usage, per-step estimates)
     - Specific recommendations for improving this EPIC's pattern

  2. Project Trends (across EPICs in one project)
     - Duration trends: improving or regressing?
     - Common bottlenecks: consistently slow roles
     - Gate efficiency: which gates retry most
     - Token trends: cost trajectory
     - Systemic improvement recommendations

  3. Cross-Project Comparison
     - Project ranking by efficiency metrics
     - Best practices from fastest projects
     - Knowledge transfer opportunities

METRICS TRACKED:

  agent_execution   Per-step: duration, complexity, bottleneck, errors
  epic_summary      Per-EPIC: total duration, step count, gate retries
  gate_result       Per-gate: pass/fail, retries, duration
  token_profile     Per-EPIC: token estimates, model distribution

RECOMMENDATIONS:

  Each recommendation includes a confidence level:
    HIGH   — clear pattern from multiple data points
    MEDIUM — emerging pattern, needs more data
    LOW    — insufficient data, speculative

WHEN TO USE:

  - After completing an EPIC: identify what went well and what to improve
  - Before starting a similar EPIC: learn from past performance
  - Periodically: track project health trends
  - When optimizing: find the biggest bottlenecks to address

Related: skills/memory-mcp.md (metric storage), skills/cost-optimization.md
```

---

#### Topic: inputs

```
Input Files — Sample Data for Brainstorming
====================================

Place sample data files in .aid-o/05-inputs/ for AID to analyze during
brainstorming runs.

SUPPORTED FORMATS:

  PDF      AID detects page count, language, and document structure
  CSV      AID reads headers, counts rows, and shows a sample
  JSON     AID detects schema structure and top-level keys
  Images   (PNG, JPG, etc.) AID describes visual content
  Other    text files — AID notes filename and size

HOW IT WORKS:

  - During /aid-brainstorm, AID automatically scans .aid-o/05-inputs/ in Step 1
  - Found files are analyzed and summarized:
      PDF:  structure, page count, language
      CSV:  headers + sample rows
      JSON: schema + top-level keys
  - You can also point AID to files outside this directory during brainstorming
  - Files are read-only — AID never modifies or moves your input files
  - Maximum 10 files are analyzed per run

ALTERNATIVE:

  You can reference any file by path during brainstorming.
  Just say "look at ./data/customers.json" and AID will analyze it.

SETUP:

  Created automatically by /aid-init.
  Or create manually: mkdir -p .aid-o/05-inputs
```

---

#### Topic: examples

```
Interactive Project Prompts — Try /aid-brainstorm
====================================

Pick a project below and run /aid-brainstorm with the prompt to see the
9-step brainstorming flow in action. All examples demonstrate full-stack
development — AID orchestrates backend AND frontend in parallel.

-------------------------------------------------------------
1. REST API + Database + Admin UI
-------------------------------------------------------------

  Prompt:
    /aid-brainstorm "Build a task management API with PostgreSQL storage
    and a React admin dashboard for managing tasks, users, and analytics"

  What happens:
    Step 1 — Context: AI asks about your tech stack, DB preference, auth method
    Step 2 — Questions: Clarifying questions (REST vs GraphQL? ORM? Deploy target?)
    Step 3 — Approaches: Compare options (monolith vs separate services)
    Step 4 — Design: API contracts, database schema, React components, routing
    Step 5 — Sections: Plan outline for PM review
    Step 6 — Approval: PM approves or requests changes
    Step 7 — Document: Full plan written to .aid-o/01-plans/
    Step 8 — EPIC draft: Optional EPIC generated from the plan
    Step 9 — Handoff: Summary of decisions + next steps

  Result: A detailed plan covering API endpoints, database schema, React
  dashboard components, authentication, and a ready-to-execute EPIC with steps:
  architect -> domain -> backend + frontend (parallel) -> qa + security -> docs

-------------------------------------------------------------
2. CLI Tool + Interactive TUI
-------------------------------------------------------------

  Prompt:
    /aid-brainstorm "Create a git repository analytics CLI tool with
    an interactive terminal UI showing commit stats, contributor graphs,
    and branch visualization"

  What happens:
    Step 1 — Context: AI asks about target platform, language, distribution
    Step 2 — Questions: Interactivity level? Output format? Dependencies?
    Step 3 — Approaches: Compare (pure CLI vs TUI framework: textual/rich/blessed)
    Step 4 — Design: Command structure, data pipeline, TUI layout, chart rendering
    Step 5 — Sections: Plan outline for PM review
    Step 6 — Approval: PM approves or requests changes
    Step 7 — Document: Full plan written to .aid-o/01-plans/
    Step 8 — EPIC draft: Optional EPIC generated from the plan
    Step 9 — Handoff: Summary of decisions + next steps

  Result: A plan covering CLI architecture, data extraction pipeline, TUI
  component layout, chart rendering, and a ready-to-execute EPIC with
  appropriate roles for both backend logic and interactive UI.

-------------------------------------------------------------
3. Full-Stack SaaS Application
-------------------------------------------------------------

  Prompt:
    /aid-brainstorm "Build a bookmark manager with tagging, full-text
    search, a responsive web UI with dark mode, and browser extension
    for one-click saving"

  What happens:
    Step 1 — Context: AI asks about auth method, search engine, UI framework
    Step 2 — Questions: Browser targets? Sync strategy? Offline support?
    Step 3 — Approaches: Tech stack options, architecture patterns, deployment
    Step 4 — Design: Complete full-stack architecture including REST API,
             database, React/Vue frontend with responsive layouts,
             browser extension manifest
    Step 5 — Sections: Plan outline for PM review
    Step 6 — Approval: PM approves or requests changes
    Step 7 — Document: Full plan written to .aid-o/01-plans/
    Step 8 — EPIC draft: Optional EPIC generated from the plan
    Step 9 — Handoff: Summary of decisions + next steps

  Result: A comprehensive plan covering all layers — API, database, web UI,
  browser extension — with a ready-to-execute EPIC covering the full pipeline:
  architect -> domain -> backend + frontend (parallel) -> qa + security
  + e2e (parallel) -> docs

-------------------------------------------------------------

Tip: You can brainstorm ANY project — these are just starting points.
     Run /aid-brainstorm with your own idea to begin.
```

---

#### Topic: faq

```
Frequently Asked Questions
====================================

How does AID handle different application types?
-------------------------------------------------

AID auto-detects your app type from project indicators (web-app, API, CLI,
library, plugin, etc.) and adapts the orchestration pipeline accordingly:

- Web apps:     Full pipeline with frontend + backend parallel, Playwright E2E testing
- APIs/CLIs:    Backend-focused, skip frontend roles
- Libraries:    Emphasis on architect + domain + qa, skip deployment
- Scripts:      Minimal pipeline -- just QA and docs
- Monorepos:    Multi-package orchestration with workspace awareness
- Desktop apps: Custom pipeline with platform-specific testing
- Mobile apps:  Custom pipeline with device testing considerations
- Plugins:      Adapted to host platform conventions
- ERP modules:  Domain-heavy pipeline with strict conventions
- Infra:        DevOps-focused roles (no frontend/backend split)

Your app type is stored in project-profile.yaml -> architecture.app_type.
To override: edit the file or re-run /aid-setup.

Supported types (11): web-app, api-service, cli-tool, desktop-app,
mobile-app, library, plugin, script, monorepo, erp-module, infrastructure.

What if my project doesn't fit any type?
-----------------------------------------

AID defaults to the closest match with low confidence. You can:
1. Edit project-profile.yaml -> architecture.app_type manually
2. Re-run /aid-setup to re-detect
3. The Planner always respects EPIC-level role specifications over auto-detection

Can I change the pipeline after detection?
-------------------------------------------

Yes. The app type influences default behavior, but EPIC-level specifications
always take priority. If you define frontend steps in your EPIC for a CLI
project, AID will execute them.
```

## Reference Files

- `skills/epic-orchestration.md` — state machine, evidence, dispatch
- `skills/memory-mcp.md` — vector memory protocol, document types, fallback
- `.claude-plugin/plugin.json` — registered commands, agents, skills
- Plan P-20260216-b3a1, section D-008 (/aid-help)

## Important

- This is a **read-only** command — never modifies files
- Content is generated dynamically (reads plugin.json for command list, checks .aid-o/ for status)
- If a topic is not recognized, show the full overview with available topics listed
- Keep output concise but complete — this is the user's primary reference
