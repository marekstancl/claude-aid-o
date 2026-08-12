---
name: aid-help
description: AID help with progressive disclosure (Level 0–3)
user_invocable: true
---

Show AID documentation with progressive disclosure — a new user sees the four commands that get a project running, a power user sees every public surface.

## Usage

```
/aid-help           # show your level (auto-detected from usage history)
/aid-help <topic>   # jump to one topic (full list under "Help Topics" below)
```

## Level Detection

Auto-detect user level from workspace state:

| Condition | Level |
|-----------|-------|
| No `.aid-o/` or 0 completed tasks | Level 0: Getting Started |
| 1–4 completed tasks (Q-NNN + done EPICs) | Level 1: Working with Tasks |
| 5+ completed tasks | Level 2: Configuration |
| Custom gates configured OR `autonomous_mode: true` | Level 3: Power User |

Count completed tasks:
- Quick logs: count files in `.aid-o/work/quick/Q-*.md`
- Task runs: count `state: DONE` in `.aid-o/work/evidence/*/*/fsm-state.yaml`

Show all levels up to and including the detected level.

## Level 0: Getting Started (0 tasks completed)

```
AID Orchestrator — Getting Started
====================================
In this order:
  /aid-init         → create the .aid-o/ workspace. Nothing else runs without it.
  /aid-setup        → permissions, integrations, CLAUDE.md, stack scan.
  /aid-do "task"    → implement something small in < 2 min. No planning overhead.
  /aid-status       → see what is running, queued, or finished.

Start here: /aid-init, then /aid-setup, then /aid-do "your first task"
Bigger than one sitting? /aid-plan writes the plan, /aid-run executes it.
```

`/aid-setup` refuses to run before `/aid-init` — it configures a workspace that
`/aid-init` has to create first. The order above is the working order, not a
preference.

## Level 1: Working with Tasks (1–4 tasks completed)

```
Queue management:
  /aid-status queue add .aid-o/tasks/E-001.md   → queue EPIC

Planning:
  /aid-plan                → brainstorm + write plan (auto-detect)
  /aid-plan write spec.md  → write plan from spec file
  /aid-plan epic plan.md   → generate EPICs from plan

Before you trust either end:
  /aid-verify-plan             → adversarial review of the plan
  /aid-verify-implementation   → adversarial review of a claimed-done result
```

## Level 2: Configuration (5+ tasks completed)

```
Setup: /aid-setup → configure permissions, integrations, CLAUDE.md, stack scan
  /aid-setup permissions    → choose autonomy level (autonomous/custom)
  /aid-setup integrations   → enable/disable MCP servers
  /aid-setup claude-md      → generate project context file
  /aid-setup scan           → re-detect tech stack

Gates: edit .aid-o/config/execution.yaml → customize test/lint/build commands
Project profile: .aid-o/config/project.yaml → stack, test/lint/build commands
Permissions: .aid-o/config/permissions.yaml → autonomous_mode: true for /aid-run --auto

Health: /aid-audit       → project health score (0-100) with recommendations
Tests:  /aid-audit-tests → test portfolio inventory + recommendation
```

## Level 3: Power User (custom gates or autonomous mode)

```
FSM debugging:
  /aid-status <epic-id>                    → shows fsm-state.yaml FSM state
  cat .aid-o/work/evidence/{id}/*/timeline.jsonl | jq .  → full event log

Audit: /aid-audit → project health, gate failure rates, recommendations
Emergency: /aid-stop → halt auto-mode and return control to you
```

## Help Topics

Ask for any of these with `/aid-help <topic>`:

```
/aid-help do              → /aid-do deep dive (scope detection, escalation triggers)
/aid-help run             → /aid-run deep dive (6-state FSM, flags, what a run does)
/aid-help generation      → PRE-FLIGHT: plan → EPIC → plan.json as one transaction
/aid-help plan            → /aid-plan deep dive (brainstorm, write, epic modes)
/aid-help plan-lifecycle  → plan branches, release model, verification commands
/aid-help status          → /aid-status deep dive (overview, EPIC detail, queue)
/aid-help gates           → gate types, execution.yaml configuration, retry logic
/aid-help tests           → /aid-audit-tests, test tiers, what runs on the merge path
/aid-help audit           → /aid-audit project health audit (categories A–J)
/aid-help recovery        → /aid-stop, resume, escalation, PM overrides
/aid-help auto            → autonomous mode, background gates, resuming a dead run
/aid-help config          → project.yaml, execution.yaml, permissions.yaml reference
/aid-help init            → /aid-init workspace creation and upgrade
/aid-help setup           → /aid-setup deep dive (modules, presets, integrations)
/aid-help fsm             → 6-state FSM diagram, valid transitions, fsm-state.yaml format
```

### Topic: do

`/aid-do "task"` is Fast Mode — one small change, implemented and logged, with no
EPIC, no FSM and no evidence directory. It escalates to `/aid-plan` when the work
turns out to be bigger than Fast Mode should carry.

```
/aid-do — Fast Mode
====================================
Scope detection: estimates files + layers before implementation
  > 5 files OR 3+ layers → offers escalation to /aid-plan

Quick log: .aid-o/work/quick/Q-NNN.md (auto-increment)
Post-check: verifies actual scope after implementation, warns if exceeded
```

### Topic: run

`/aid-run` executes one EPIC through the 6-state FSM. Everything that happens
before the FSM starts — turning a plan into EPIC files and `plan.json` — is the
generation transaction; see `/aid-help generation`.

```
/aid-run — EPIC Pipeline
====================================
6-State FSM:
  READY → EXECUTE → GATES → DONE
                 ↘ ESCALATION ↗
                       ↓
                     ERROR

Flags:
  --auto    Autonomous mode (S-effort auto-fix, L-effort always escalates)
  --resume  Resume from fsm-state.yaml after crash
  --epic    Specify EPIC ID
```

### Topic: generation

Generation is what `/aid-run` does before the FSM exists, and what `/aid-plan epic`
drives directly: a plan becomes EPIC files, then `plan.json`, then a run.

```
PRE-FLIGHT (bash, before FSM):
  1. generation-readiness validates the source plan + provisional graph
  2. transaction skeleton written under the generation lock
  3. CP1 gate — ONCE per plan → generation-authority.json
  4. aid-plan-to-epic.sh → every EPIC file (verifies the authority,
     never re-runs the gate)
  5. aid-epic-to-json.sh → every plan.json + contract validation
  6. aid-generation-finalize.sh → one generation receipt
  7. aid-plan-fsm.sh epic-start → plan_branch plans ONLY: registers
     task/<epic>/main as a ref with lineage back to plan/<plan_id>,
     which init's lineage check requires (legacy plans skip this)
  8. aid-json-to-run.sh → execution.yaml + fsm-state.yaml, only after receipt

Generation is ONE TRANSACTION: one PM decision covers every phase, a crash
resumes instead of duplicating, and no FSM state or queue entry exists until
the complete EPIC package has been verified and sealed.

A FAILING init still restores the caller's branch before the failure is
reported — your checkout is never left on a task branch init auto-created on
its way to refusing.
```

### Topic: plan

`/aid-plan` brainstorms a topic, writes a plan from a spec, or generates EPICs
from a plan — the mode is auto-detected from what you pass. When a brainstorm is
about something visual, `/visual-companion` opens the browser-based mockup
companion; you can also invoke `/visual-companion` on its own as a smoke test.

```
/aid-plan — Brainstorm, Write, Generate
====================================
Three modes, auto-detected from what you pass:
  /aid-plan "topic"        → brainstorm (9 steps, interactive)
  /aid-plan write spec.md  → write a plan from a spec
  /aid-plan epic plan.md   → generate EPICs from a plan

Plan IDs come from the locked allocator, never a hand edit:
  aid-fsm.sh alloc plan-id     → prints the next P{NNN}

NOT YET SUPPORTED
Concurrent plan GENERATION works. STARTING a newly generated plan's EPIC
while another stream is live does not — that is a known limitation.
```

### Topic: plan-lifecycle

A plan owns a git worktree and a branch, and declares how it releases.
`/aid-verify-plan` reviews a plan before execution; `/aid-verify-implementation`
reviews a result that claims to be done. Both dispatch an independent agent in a
fresh context, so neither is grading its own homework.

**Release model.** A plan declares its mode in its committed lifecycle manifest
(`.aid-lifecycle/manifests/<plan_id>.yaml`, key `mode`):

- `plan_branch` — EPICs merge into the plan branch and **the plan releases once**,
  at the plan-final boundary.
- `legacy_epic_release_mode` — **each EPIC releases** as before.

New plans default to `plan_branch` only when the project declares a `gate_profiles`
table in `execution.yaml`. Declining that upgrade at `/aid-init` time therefore
selects legacy mode — silently, from the user's point of view: the fallback is
logged as `plan_branch_unavailable: no_gate_profiles`, not raised as a question.
If you are already mid-flight on a legacy plan, it stays legacy; the mode is never
retroactively re-declared as `plan_branch`.

```
Each plan implements in its own git worktree:

  <your checkout>                     you, on your branch, your edits
  .aid-worktrees/plan-P080/           one plan, on its plan/<id> branch
  .aid-worktrees/plan-P081/           another plan, on its own branch

So you can write and fully generate a new plan while another one implements —
with uncommitted work in your checkout, and without your HEAD moving. An edit
you make during another plan's review window no longer invalidates that review.

Plan-linked commands find the right tree themselves; you never cd. The
exception is plan-close and plan-rollback, which refuse to run from INSIDE
the worktree they are about to remove — run those from your own checkout.

See what is running:
  /aid-status                          both streams, per plan
  git worktree list                    every tree, including yours
  aid-fsm.sh active-runs list          which EPICs are live

If a plan's worktree is missing or broken:
  aid-plan-fsm.sh plan-state <id> --recreate-worktree --reason "<why>"
```

### Topic: status

`/aid-status` is the one place that answers "what is happening". It has four
sub-surfaces, and its overview is grouped by plan stream — two concurrent plans
show as two streams.

```
/aid-status                                  overview: active plans + EPICs + queue
/aid-status <epic-id>                        one EPIC in detail (reads fsm-state.yaml)
/aid-status queue                            queue management view
/aid-status queue add <path> [--priority]    add an EPIC to the queue
```

**What to do next:** run `/aid-status` — its next-EPIC line is computed by the
shipped `next-epic` recipe from real state files, so it is the answer, not a
guess to be re-derived by hand.

### Topic: gates

Gates are the quality checks between `GATES` and `DONE`. They come from
`config/project.yaml` and `config/execution.yaml`, and `/aid-run` runs them.

```
Quality Gates
====================================
Default gates (from config/project.yaml):
  test_cmd   → run tests
  lint_cmd   → run linter
  build_cmd  → run build

Custom gates (config/execution.yaml):
  - name: security_scan
    command: "npm audit --audit-level=high"
    required: true
    max_retries: 2

Gate retry: up to 2 attempts with gate-fixer agent between retries.
All retries exhausted → ESCALATION.
```

### Topic: tests

`/aid-audit-tests` inventories the test portfolio, optionally measures a bounded
subset of it, and ends with a plain-language recommendation. It never edits,
deletes or quarantines a test, and it never runs itself — you have to ask.
This is about **tests**; for the project's overall health score see
`/aid-help audit`, which covers the differently-named `/aid-audit`.

```
/aid-audit-tests                  bare invocation ASKS which mode + budget
  --mode static                   discovery only, executes nothing (minutes)
  --mode measure                  measures runtimes (tens of minutes)
  --mode full                     the complete audit (hours)

Tiers: t0 = the pulse, t1 = what blocks a merge, t2 = nightly.
The merge path runs t0 + t1; the full portfolio runs nightly.
```

### Topic: audit

`/aid-audit` scores the whole project's health from 0 to 100 across categories
A–J — code, security, docs, process, tokens, frontend, database, instruction
quality, standards and memory — and returns recommendations. It is **not** the
test-portfolio audit: for tests, `/aid-help tests` covers `/aid-audit-tests`.

```
/aid-audit        project health score (0-100) + prioritized recommendations
```

### Topic: recovery

Something is stuck, wrong, or running when it should not be. `/aid-stop`
disengages autonomous mode immediately and hands control back to you. The FSM has
already written the run's position (EPIC, completed step, state) to
`fsm-state.yaml`, so `/aid-run --resume` picks it up — `/aid-stop` itself saves
nothing. The step that was mid-flight is not checkpointed and runs again on
resume, so check what it had already done before you resume.

```
Stop an autonomous run:
  /aid-stop                     immediate, no confirmation, always completes

Pick it back up:
  /aid-run --resume             continue from fsm-state.yaml
  /aid-status <epic-id>         where it actually stopped, and why

When a precondition blocks you and you are sure:
  --force --reason '<at least 20 characters>'
```

`--force` is a PM decision, never an agent's: it is logged to the audit trail, it
never rewrites a failing result as clean, and some failure classes refuse it
outright and say so by name. ESCALATION means a person is expected — the run
waits rather than inventing a way past.

### Topic: auto

`/aid-run --auto` hands the run to an autonomous controller: S-effort failures are
auto-fixed, L-effort always escalates to you.

```
AUTO MODE, BACKGROUND GATES AND RESUME
A gate whose execution.yaml entry says run_mode: background is started as a
supervised job (aid-job.sh) instead of a plain in-line command, and the gate
runner polls that job to completion in the same invocation — so nothing is
fire-and-forget, and a run killed mid-gate re-attaches to the still-live job
next time instead of paying the whole suite twice. Before spawning, the run
writes ONE continuation pointer, .aid-o/work/evidence/<epic>/<run>/
auto_resume_required.json, and deletes it only on a clean terminal collect.

  aid-fsm.sh resume <epic-id>

claims that pointer exactly once, collects the job's terminal result, records
it as a gate-row checkpoint the next run-all assembles, and prints what it
found, what it recorded and the next action. A job still running is a
read-only status report — nothing is claimed. It never invents a result: a
missing job record, a lost job or a stale result each come back as such, with
the rerun instruction.

Run state lives in .aid-o/work/active-runs.json as auto_controller:
  active           an autonomous controller is alive and owns the run
  manual           a human drives it (the default for a non-AUTO run)
  blocked_for_pm   the run stopped at a PM-authority decision and waits for a
                   person; written by aid_ladder_escalate
                   (lib/aid-recovery-ladder.sh) when a class's recovery
                   terminus reaches escalation
  awaiting_host_resume
                   DERIVED, never stored — the pointer is still on disk and
                   nothing has signalled liveness. A dead controller cannot
                   write a flag on its way out, so consumers compute this one
                   instead; the writer rejects any attempt to store it.

  aid-fsm.sh active-runs stalled     which runs look stuck, and why
```

### Topic: config

The config files you will actually touch live under `.aid-o/config/`. `/aid-init`
creates them at workspace setup — except `queue.yaml`, which appears on the first
`/aid-status queue add` — and `/aid-setup` is what changes them afterwards. The
full list of what a fresh init produces is in `/aid-help init`; the four below are
the ones worth knowing by name.

```
Configuration Files
====================================
config/project.yaml       — project stack, commands (auto-detected by /aid-init)
config/permissions.yaml   — autonomous mode, auto-commit, auto-push
config/execution.yaml     — gate definitions (generated eagerly by /aid-init;
                            aid-fsm.sh init recreates it if it is missing)
config/queue.yaml         — EPIC queue (lazy-created on first /aid-status queue add)
```

`/aid-init` never overwrites an existing `execution.yaml` — a project's gate
config is its own, and an upgrade only offers to append what is missing.

### Topic: init

`/aid-init` creates the `.aid-o/` workspace, or upgrades an existing one. It is
idempotent: run it again after every plugin update. Run it before `/aid-setup`.

```
/aid-init         create or upgrade .aid-o/ (plans, tasks, config, work)

Creates: config/project.yaml, config/permissions.yaml, config/execution.yaml,
         config/plugin.yaml, config/check-severity.yaml, config/test-audit.yaml
         and, only when Qdrant memory is detected, config/integrations.yaml
Upgrade: offers the gate_profiles block if execution.yaml predates it —
         declining keeps the project on per-EPIC releases (see plan-lifecycle)
Re-installs the git hooks, so run it again after upgrading the plugin.
```

### Topic: setup

`/aid-setup` is modular project configuration — run everything, or one module at
a time. It requires `/aid-init` to have run first.

```
/aid-setup — Project Configuration
====================================
  /aid-setup permissions    → choose preset: autonomous (default) or custom
  /aid-setup integrations   → detect & enable MCP servers (Qdrant, Slack, ...)
  /aid-setup claude-md      → generate CLAUDE.md with project context
  /aid-setup scan           → re-detect tech stack, update project.yaml
  /aid-setup all            → run everything (recommended for first setup)

Permission presets:
  autonomous (default): Bash(*) + all non-destructive MCPs allowed, auto_commit: true
  custom: configure each setting manually
```

### Topic: fsm

The six states an EPIC run moves through. `/aid-status <epic-id>` shows where a run
currently sits. The list below is the normal path; on top of it, READY, EXECUTE, GATES
and ESCALATION can each go to the terminal `ERROR` state on an unrecoverable failure
or a PM abort.

```
6-State FSM Reference
====================================
Valid transitions:
  READY → EXECUTE         (PM or auto approve)
  EXECUTE → EXECUTE       (next step, internal)
  EXECUTE → GATES         (all steps done)
  EXECUTE → ESCALATION    (hard failure)
  GATES → DONE            (all gates pass)
  GATES → EXECUTE         (gate retry, max 2)
  GATES → ESCALATION      (retries exhausted)
  ESCALATION → EXECUTE    (fix applied, resume)
  ESCALATION → GATES      (skip gate)
  READY → ERROR           (PM abort)
  EXECUTE → ERROR         (unrecoverable failure)
  GATES → ERROR           (unrecoverable failure)
  ESCALATION → ERROR      (PM abort)

State file: .aid-o/work/evidence/{id}/{run_id}/fsm-state.yaml
Event log: .aid-o/work/evidence/{id}/{run_id}/timeline.jsonl
```

## Important

- **Progressive disclosure** — show only relevant levels, don't overwhelm new users
- **Level 0 = 4 commands** — /aid-init, /aid-setup, /aid-do, /aid-status, in that order
- **All commands in help exist** — never reference deleted v1 commands
- **The index is the authority** — `defaults/help-index.yaml` lists every public
  surface; every routed one has a `### Topic:` section here that names it in prose
- **Topics are deep dives** — show when PM asks `/aid-help <topic>`
- If `$ARGUMENTS` is empty → show auto-detected level overview
- If `$ARGUMENTS` matches a topic → show that topic section only


**Last Updated:** 2026-08-12
