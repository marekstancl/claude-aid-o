Show AID documentation — commands, workflow, agent roles, configuration, and FAQ.

AID's self-knowledge command. Explains everything about how AID works, what commands are available, and how to use the orchestration system.

## Usage

```
/aid-help [topic]
```

**Topics:** `commands`, `workflow`, `epic`, `agents`, `planning`, `gates`, `evidence`, `config`, `slack`, `queue`

**Examples:**
```
/aid-help                   # full overview
/aid-help commands          # detail on every command
/aid-help workflow          # Plan → EPIC → Session flow
/aid-help epic              # how to write an EPIC
/aid-help agents            # 18 agent roles + specialists
/aid-help planning          # planner, parallelization, analysis groups
/aid-help gates             # quality gates + retry logic
/aid-help evidence          # evidence store structure
/aid-help config            # configuration files
/aid-help slack             # Slack integration + PM communication
/aid-help queue             # Epic queue + autonomous pipeline
```

## Flow

### Step 1: Check Environment

1. Check if `.aid-o/` exists in current project
2. If exists: note active EPICs count, sessions count (for dynamic info)
3. If not exists: include recommendation to run `/aid-init` or `/aid-setup`

### Step 2: Display Based on Topic

---

#### No topic (full overview)

Display the complete AID overview:

```
AID — AI Development Orchestrator
====================================
Version: 0.1.0

What is AID?
  AID is a multi-agent orchestration system for Claude Code. It takes
  an EPIC (detailed task specification) and autonomously dispatches
  specialized agents to complete it — with quality gates, retry logic,
  and PM escalation when needed.

  Think of it as a project manager that coordinates 9 specialist agents
  to deliver features end-to-end: architecture → implementation → testing
  → security → documentation → release.

Commands:
  /aid-init        Initialize .aid-o/ workspace
  /aid-setup       Interactive project onboarding
  /aid-help        This help
  /plan-epic       EPIC → Plan JSON + session file
  /run-epic        Start orchestration (state machine)
  /run-step        Run one step manually
  /epic-status     Show pipeline status
  /run-gates       Run EPIC quality gates (standalone or in /run-epic)
  /epic-queue      Manage EPIC execution queue (add, list, pause, resume)
  /quality-gates   6-gate pre-commit protocol
  /session-start   Start tracked session
  /session-end     Complete + archive session
  /handoff         Create handoff for next session
  /audit           Project health audit
  /coding-standards Load coding standards
  /testing         Load testing workflow
  /docs-protocol   Load docs protocol

Quick Start:
  1. /aid-setup                              ← first time only
  2. Create EPIC in .aid-o/02-epics/         ← your task spec
  3. /plan-epic .aid-o/02-epics/my-epic.md   ← generate plan
  4. /run-epic                               ← orchestrator takes over

Where things live:
  .aid-o/01-plans/      Plans (brainstorming)
  .aid-o/02-epics/      EPICs (task specs)
  .aid-o/03-config/     Configuration
  .aid-o/04-engine/     AI internals (sessions, evidence, memory)

Topics: /aid-help commands | workflow | epic | agents | planning | gates | evidence | config | slack | queue
{If .aid-o/ not found:}

  ⚠ No .aid-o/ workspace found. Run /aid-setup to get started.
{If .aid-o/ found:}

  Status: {N} active EPICs, {M} sessions
```

---

#### Topic: commands

```
AID Commands — Detailed Reference
====================================

SETUP COMMANDS:

  /aid-init
    Initialize .aid-o/ workspace with default config.
    Usage: /aid-init
    Creates: directories, policies, templates, playbooks, engine files.
    Idempotent — safe to run multiple times.

  /aid-setup
    Interactive onboarding. Detects tech stack, configures AID.
    Usage: /aid-setup
    Flow: detect → analyze → present → configure
    Calls /aid-init internally if needed.

  /aid-help [topic]
    This help. Shows commands, workflow, FAQ.
    Topics: commands, workflow, epic, agents, gates, evidence, config

ORCHESTRATION COMMANDS:

  /plan-epic <path>
    Parse EPIC → generate Plan JSON + session file.
    Usage: /plan-epic .aid-o/02-epics/E-YYYYMMDD-xxxx.md
    Output: plan.json, plan_progress.json, session file
    Validates EPIC structure, builds dependency graph.

  /run-epic [epic-id]
    Start the Controller state machine.
    Usage: /run-epic TEST-0001
    States: IDLE → PLANNING → PLAN_REVIEW → EXECUTING → PHASE_CHECK
            → GATES → PM_APPROVAL → DONE
    PM checkpoints: plan review, escalation, final approval
    Auto-decisions: scope check, gate retry, step progression

  /run-step <epic-id> <step-id> [--analysis-group <group-id>]
    Run one step or analysis group manually (without full pipeline).
    Usage: /run-step TEST-0001 step_3_backend
           /run-step TEST-0001 --analysis-group analysis_1_security_review
    Useful for: debugging, re-running failed steps, manual analysis

  /epic-status [epic-id]
    Show pipeline status.
    Usage: /epic-status TEST-0001   (detailed)
           /epic-status             (overview of all)
    Shows: step progress, gates, budget, recent activity

SESSION COMMANDS:

  /session-start     Start tracked session with file + branch
  /session-end       Archive session, update workspace files
  /handoff           Create handoff block for next AI

GATES COMMANDS:

  /run-gates [epic-id]
    Run EPIC quality gates — standalone or integrated with /run-epic.
    Usage: /run-gates TEST-0001    (run gates for EPIC)
           /run-gates --dry-run    (preview which gates would run)
           /run-gates              (run all gates standalone)
    Gates: tests_pass, lint_pass, security_scan, docs_updated (+conditionals)
    On failure: auto-fix via gate-fixer agent, retry up to 3x, then escalate.
    Config: .aid-o/03-config/policies/gates.yaml

  /epic-queue [subcommand]
    Manage EPIC execution queue for autonomous pipeline.
    Usage: /epic-queue                        (show queue)
           /epic-queue add <path> [--priority high]
           /epic-queue remove <epic-id>
           /epic-queue next                   (show next in line)
           /epic-queue pause                  (pause auto-pickup)
           /epic-queue resume                 (resume auto-pickup)
           /epic-queue reorder <id> --priority <level>
    Auto-pickup: after EPIC DONE, next queued EPIC starts automatically.
    Skill: skills/epic-queue.md

QUALITY COMMANDS:

  /quality-gates     Run 6-gate pre-commit protocol
  /audit             Project health audit
  /coding-standards  Load coding standards
  /testing           Load testing workflow
  /docs-protocol     Load documentation protocol
```

---

#### Topic: workflow

```
AID Workflow — Plan → EPIC → Session
====================================

The AID workflow has three layers:

  PLAN (brainstorming)
    ↓ PM + AI collaborate on approach
  EPIC (specification)
    ↓ PM + AI detail the task
  SESSION (execution)
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

3. SESSION (.aid-o/04-engine/sessions/)
   - Auto-generated from EPIC by /plan-epic
   - Tracks progress, commits, decisions
   - One session per EPIC run (or per sub-session for multi-session EPICs)
   - Naming: S-{YYYYMMDD}-{hash}-{topic}.md

Orchestration Flow:
  /plan-epic → generates Plan JSON from EPIC
  /run-epic  → executes plan (state machine):

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
                                      PM_APPROVAL (PM checkpoint)
                                              │
                                          approved
                                              │
                                              ▼
                                            DONE

PM Interaction Points (via Slack or chat fallback):
  - PLAN_REVIEW: approve execution plan (GO / REVISE / ABORT)
  - ESCALATION: handle failures (fix / skip / abort)
  - PM_APPROVAL: approve merge (APPROVE / REJECT / REVISE)
  - CURATOR proposals: approve/defer/reject improvements
  - AUDITOR summary: informational (no reply needed)

Communication: skills/slack-mcp.md (Slack preferred, chat fallback)
Config: .aid-o/03-config/policies/slack-config.yaml

Epic Queue (autonomous pipeline):
  /epic-queue add <path> → queue EPICs
  After DONE → auto-pickup next EPIC from queue
  /epic-queue pause/resume → control auto-pickup

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
    Triggered: after session-end (POST_PROCESSING)
    Collects improvement_notes from all role agents, deduplicates
    against backlog, analyzes patterns, proposes improvements.
    Flow: collect → deduplicate → analyze → propose → Orchestrator → PM
    Output: curator_report + backlog.md updates
    See: skills/improvement-proposals.md

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
  session-validator, lessons-extractor, gate-fixer
```

---

#### Topic: planning

```
Planning, Parallelization & Analysis Groups
====================================

The Planner transforms an EPIC into an executable Plan JSON with dependency
graph, parallel groups, and multi-perspective analysis groups.

Skills: planner.md, parallel-dispatch.md, analysis-merge.md

PLAN GENERATION (/plan-epic):

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
   Command:  /run-gates
   Config:   .aid-o/03-config/policies/gates.yaml
   Skills:   gates-engine.md, retry-engine.md
   Agent:    gate-fixer.md (auto-fix on failure)
   Purpose:  Validate entire EPIC output before PM approval

2. Pre-Commit Quality Gates
   Command:  /quality-gates
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

  Gate Flow in /run-epic:
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

  Standalone Usage:
    /run-gates                  Run all gates
    /run-gates TEST-0001        Run gates for specific EPIC
    /run-gates --dry-run        Preview which gates would run

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
  session-*.md         Session file templates (4 types)

Playbooks (.aid-o/03-config/playbooks/):
  9 role playbooks (architect.md through release.md).
  Each defines: Role, Mission, Responsibilities, Process,
  Quality Criteria, Constraints.

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

  1. Install a Slack MCP server (e.g., @anthropic/slack-mcp)
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
    PM options: APPROVE / REJECT / REVISE

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
Command: /epic-queue
File: .aid-o/04-engine/epic-queue.yaml

USAGE:

  /epic-queue                                     Show queue
  /epic-queue add <path> [--priority high]        Add EPIC
  /epic-queue remove <epic-id>                    Remove from queue
  /epic-queue next                                Show next in line
  /epic-queue pause                               Pause auto-pickup
  /epic-queue resume                              Resume auto-pickup
  /epic-queue reorder <id> --priority <level>     Change priority

PRIORITY LEVELS:

  critical > high > medium (default) > low
  Within same priority: FIFO (first added, first executed)

HOW IT WORKS:

  1. PM queues EPICs:
     /epic-queue add .aid-o/02-epics/E-auth.md --priority high
     /epic-queue add .aid-o/02-epics/E-api-v2.md
     /epic-queue add .aid-o/02-epics/E-dashboard.md --priority low

  2. Start first EPIC:
     /run-epic    (picks up highest priority queued EPIC)

  3. Autonomous loop:
     EPIC 1 → DONE → auto-start EPIC 2 → DONE → auto-start EPIC 3 → DONE → idle

  PM only interacts via Slack (plan approval, escalation, merge approval).

SAFETY:

  - Max 1 EPIC runs at a time (no parallel EPIC execution)
  - Failed EPIC → queue auto-pauses (PM must investigate)
  - /epic-queue pause → stops next pickup (running EPIC continues)
  - Queue persists in YAML (survives session restarts)
```

## Reference Files

- `skills/epic-orchestration.md` — state machine, evidence, dispatch
- `.claude-plugin/plugin.json` — registered commands, agents, skills
- Plan P-20260216-b3a1, section D-008 (/aid-help)

## Important

- This is a **read-only** command — never modifies files
- Content is generated dynamically (reads plugin.json for command list, checks .aid-o/ for status)
- If a topic is not recognized, show the full overview with available topics listed
- Keep output concise but complete — this is the user's primary reference
