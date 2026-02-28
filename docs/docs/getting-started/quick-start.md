---
sidebar_position: 2
title: "Quick Start"
description: "Run your first AID Orchestrator workflow in four commands — from initialization to EPIC execution."
---

# Quick Start

This guide walks you through your first AID workflow from start to finish. You will initialize a workspace, brainstorm a feature idea, generate an EPIC, and execute it — all within Claude Code.

## Before You Begin

Make sure you have:

- The AID plugin installed (see [Installation](./installation))
- Claude Code open in a project with a git repository
- A rough idea of something you want to build or change in the project

The whole workflow takes about 15 minutes the first time. After that, you can go from idea to running EPIC in under five minutes.

---

## Step 1 — Initialize the Workspace

Run `/aid-init` in your project root to create the `.aid-o/` workspace:

```text
/aid-init
```

AID creates the workspace directory structure and copies default configuration files:

```text
AID Workspace Initialized (.aid-o/)
====================================

Directories:
  [CREATED] .aid-o/01-plans/
  [CREATED] .aid-o/02-epics/
  [CREATED] .aid-o/03-config/
  [CREATED] .aid-o/04-engine/

Config files (.aid-o/03-config/):
  [CREATED] policies/gates.yaml
  [CREATED] policies/decision-policies.yaml
  [CREATED] playbooks/architect.md
  ... (18 files from plugin defaults)

Next steps:
  1. Run /aid-setup for interactive project onboarding
  2. Customize .aid-o/03-config/policies/ for your project
  3. Create your first Plan in .aid-o/01-plans/
```

After initialization, run `/aid-setup` to let AID scan your project's tech stack and configure the gates and tooling for your language and framework:

```text
/aid-setup
```

`/aid-setup` detects your package manager, test runner, linter, and build tool, then writes that information to `.aid-o/04-engine/memory/project-profile.yaml`. It also updates `gates.yaml` with the correct commands for your stack (e.g., `pytest` for Python, `npm test` for Node.js).

See [Configuration](./configuration) for details on what gets set up and how to customize it.

---

## Step 2 — Brainstorm and Create a Plan

Use `/aid-brainstorm` to explore an idea interactively and produce a plan document and EPIC draft:

```text
/aid-brainstorm "add pagination to the users API"
```

AID opens an 8-step structured brainstorming dialog. It asks you one question at a time — multiple choice where possible — to understand your requirements, propose approaches, and validate a design with you.

A typical session looks like this:

```text
Brainstorming: add pagination to the users API
====================================
Project: my-api
Stack: Python, FastAPI, PostgreSQL
Recent: no prior context

I'll help you explore this idea step by step.
Let's start with some questions to understand what you need.

──────────────────────────────────────
Question 1: What pagination style should we use?
  (A) Offset-based — page=1&per_page=20 (simple, familiar to clients)
  (B) Cursor-based — cursor=<token> (better for large datasets, no page drift)
  (C) No preference — let you recommend
```

After you answer 3–7 questions, AID proposes approaches, walks you through the design section by section for your approval, then writes two files:

- `Plan: .aid-o/01-plans/P001-add-pagination-to-users-api.md`
- `EPIC: .aid-o/02-epics/E-001-1_1-add-pagination-to-users-api.md (draft)`

At the end of brainstorming, AID offers to generate the execution plan immediately or let you review the EPIC draft first. For your first run, choose to review the draft — it is a good way to understand what AID produces.

See [`/aid-brainstorm` command reference](../commands/aid-brainstorm) for the full step-by-step flow.

---

## Step 3 — Generate the Execution Plan

Once you are happy with your EPIC draft, generate the execution plan:

```text
/aid-plan-epic .aid-o/02-epics/E-001-1_1-add-pagination-to-users-api.md
```

AID reads the EPIC, analyzes the steps and their dependencies, identifies which steps can run in parallel, and produces a Plan JSON:

```text
Plan Generated for EPIC: E-001-1_1
====================================
Steps: 5
Parallel groups: 1
Analysis groups: 1
Dependencies: 4
Roles: architect, backend, qa, security, docs
Gates: tests_pass, lint_pass, security_scan_pass, docs_updated
Budget: $50

Step sequence:
  1. [architect] Define API contract and pagination schema
  2. [backend]   Implement paginated query and response model (depends on: step 1)
  3. [qa]        Write unit and integration tests for pagination (depends on: step 2) ← parallel group 1
  4. [security]  Review input validation and injection risk (depends on: step 2) ← parallel group 1
  5. [docs]      Update API reference with pagination parameters (depends on: step 2)

Files created:
  - Plan:     .aid-o/04-engine/evidence/E-001-1_1/R-001-1_1-1/plan.json
  - Progress: .aid-o/04-engine/evidence/E-001-1_1/R-001-1_1-1/plan_progress.json
  - Run:      .aid-o/04-engine/runs/R-001-1_1-1-add-pagination.md

Ready to execute?
  Want to run this EPIC now?  → /aid-run-epic E-001-1_1
  Review plan first?          → open .aid-o/04-engine/evidence/E-001-1_1/R-001-1_1-1/plan.json
```

The plan respects the default role ordering: architect always runs first (contracts before implementation), then implementation agents, then QA and security in parallel, then docs. If your EPIC specifies a different order, that takes precedence.

See [`/aid-plan-epic` command reference](../commands/aid-plan-epic) for details on parallel groups, analysis groups, and Plan JSON structure.

---

## Step 4 — Execute the EPIC

Run the EPIC to start the orchestration pipeline:

```text
/aid-run-epic E-001-1_1
```

The Controller state machine takes over. It works through the steps in order, dispatching specialized agents, running quality gates between phases, and only pausing to ask you for input at the three PM touchpoints:

1. **Plan Review** — you approve the execution plan before any agents run
2. **Escalation** (if needed) — only if a gate fails after 3 auto-fix attempts, or a critical issue is found
3. **PM Approval** — you approve the final result before changes are merged

A typical run looks like this:

```text
EPIC E-001-1_1 — add pagination to the users API
====================================
State: PLAN_REVIEW

Step sequence:
  1. [architect]  Define API contract and pagination schema
  2. [backend]    Implement paginated query and response model
  3. [qa]         Write unit and integration tests
  4. [security]   Review input validation
  5. [docs]       Update API reference

Approve plan and begin execution? (Y/N)
> Y

State: EXECUTING — Step 1: architect
  Dispatching architect agent...
  [architect] Wrote: docs/api-contracts/pagination.yaml
  [architect] Wrote: docs/adr/ADR-001-pagination-cursor-vs-offset.md
  Step 1 complete. ✓

State: EXECUTING — Step 2: backend
  Dispatching backend agent...
  [backend] Modified: app/api/users.py
  [backend] Modified: app/models/pagination.py
  Step 2 complete. ✓

State: EXECUTING — Steps 3 + 4 (parallel group)
  Dispatching qa + security agents in parallel...
  [qa]       Written: tests/test_users_pagination.py (14 tests)
  [security] Review passed — no injection risks found
  Steps 3 + 4 complete. ✓

State: EXECUTING — Step 5: docs
  Dispatching docs agent...
  [docs] Updated: docs/api/users.md
  Step 5 complete. ✓

State: GATES
  Running: tests_pass     → PASS (14/14)
  Running: lint_pass      → PASS
  Running: security_scan  → PASS
  Running: docs_updated   → PASS

State: PM_APPROVAL
  All gates passed. Review the changes and approve merge.
  [View diff] [Approve] [Request changes]
```

When you approve at the PM_APPROVAL step, AID runs the Curator (collects improvement notes, runs post-EPIC analysis), archives the run, and transitions to DONE.

See [`/aid-run-epic` command reference](../commands/aid-run-epic) for the full state machine, escalation behavior, and FIRST AID autonomous mode.

---

## What's Next

Now that you have completed your first workflow:

- **[Configuration](./configuration)** — customize gates, coding standards, and project settings
- **[`/aid-first-aid`](../commands/aid-first-aid)** — autonomous queue mode for unattended execution
- **[`/aid-epic-queue`](../commands/aid-epic-queue)** — queue multiple EPICs and process them sequentially
- **[Agents](../agents)** — understand what each of the 18 agents does and when they are dispatched
