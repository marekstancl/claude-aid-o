Show AID documentation — commands, workflow, agent roles, configuration, and FAQ.

AID's self-knowledge command. Explains everything about how AID works, what commands are available, and how to use the orchestration system.

## Usage

```
/aid-help [topic]
```

**Topics:** `commands`, `workflow`, `epic`, `agents`, `gates`, `evidence`, `config`

**Examples:**
```
/aid-help                   # full overview
/aid-help commands          # detail on every command
/aid-help workflow          # Plan → EPIC → Session flow
/aid-help epic              # how to write an EPIC
/aid-help agents            # 9 agent roles + playbooks
/aid-help gates             # quality gates + retry logic
/aid-help evidence          # evidence store structure
/aid-help config            # configuration files
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

Topics: /aid-help commands | workflow | epic | agents | gates | evidence | config
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

  /run-step <epic-id> <step-id>
    Run one step manually (without full pipeline).
    Usage: /run-step TEST-0001 step_3_backend
    Useful for: debugging, re-running failed steps, testing agents

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

QUALITY COMMANDS:

  /quality-gates     Run 6-gate pre-commit protocol (C.I.C.E.R.O.)
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

PM Interaction Points:
  - PLAN_REVIEW: approve execution plan (GO / REVISE / ABORT)
  - ESCALATION: handle failures (fix / skip / abort)
  - PM_APPROVAL: approve merge (APPROVE / REJECT / REVISE)

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
AID Agent Roles
====================================

9 specialized agents, each with a playbook:

  ARCHITECT (.aid-o/03-config/playbooks/architect.md)
    Designs API contracts, ADRs, system architecture.
    Runs FIRST. Does NOT implement — only designs.
    Outputs: OpenAPI specs, ADR documents, architecture diagrams.

  DOMAIN (.aid-o/03-config/playbooks/domain.md)
    Defines domain models, entities, business rules.
    Runs after Architect. Uses contracts to define models.
    Outputs: Entity definitions, invariants, domain events.

  BACKEND (.aid-o/03-config/playbooks/backend.md)
    Implements server-side code, APIs, services.
    Can run in parallel with Frontend.
    Outputs: Endpoint implementations, services, migrations.

  FRONTEND (.aid-o/03-config/playbooks/frontend.md)
    Implements UI components, pages, client-side logic.
    Can run in parallel with Backend.
    Outputs: Components, pages, styles, client utilities.

  QA (.aid-o/03-config/playbooks/qa.md)
    Writes tests — unit, integration, e2e.
    Does NOT implement features — only tests.
    Outputs: Test files, test fixtures, coverage reports.

  SECURITY (.aid-o/03-config/playbooks/security.md)
    Reviews code for vulnerabilities (OWASP, secrets, etc.).
    Can patch simple findings directly.
    Outputs: Security review, patches, recommendations.

  OBSERVABILITY (.aid-o/03-config/playbooks/observability.md)
    Adds logging, metrics, tracing, health checks.
    Outputs: Logging setup, metric definitions, dashboards.

  DOCS (.aid-o/03-config/playbooks/docs.md)
    Updates documentation — API docs, guides, changelogs.
    Runs after implementation steps.
    Outputs: Updated docs, API references, changelog entries.

  RELEASE (.aid-o/03-config/playbooks/release.md)
    Handles versioning, changelog, release notes.
    Runs LAST (after gates pass).
    Outputs: Version bump, release notes, deployment config.

Default Execution Order:
  Architect → Domain → (Backend + Frontend) → (QA + Security + Obs) → Docs → Release
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

2. C.I.C.E.R.O. Quality Gates (pre-commit)
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
        plan.json               Execution plan
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
  4. Edit playbooks (agent behavior)
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
