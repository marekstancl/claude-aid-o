---
sidebar_position: 2
title: "FAQ"
description: "Frequently asked questions about AID Orchestrator — what it is, how it works, costs, and how to configure it."
---

# Frequently Asked Questions

---

## What is AID?

AID (AI Development Orchestrator) is a Claude Code plugin that implements a
**Controller + Workers architecture** for AI-driven software development. You
describe a feature or task as an EPIC specification, and AID takes it from there:
generating an execution plan, dispatching specialized role-based agents
(architect, backend, frontend, QA, security, docs), enforcing quality gates, and
maintaining a complete evidence trail of every decision and artifact.

The goal is to let you focus on what you want to build while AID coordinates the
multi-step implementation — stopping at defined checkpoints to ask for your input,
and handling routine failures (lint errors, test failures, minor code issues) autonomously.

---

## How does AID differ from just using Claude Code directly?

Using Claude Code directly is a single-agent, single-context approach. You and one
Claude instance work through a problem together, and the result quality depends on
how well you keep that context organized.

AID adds a structured layer on top:

| Aspect | Claude Code (raw) | AID |
|---|---|---|
| Agents | One session | 18 specialized agents dispatched per step |
| Planning | Informal | Structured EPIC + Plan JSON with dependency graph |
| Quality | Manual review | Automated gates (tests, lint, security, docs) run after each phase |
| Evidence | Chat history | Structured evidence trail: `stage_log.jsonl`, per-step outputs, gate reports |
| Failures | You handle them | Auto-retry with targeted gate-fixer agent (up to 3 attempts) |
| Parallel work | Sequential | Multiple agents run in parallel on isolated branches |
| Memory | Context window only | Optional Qdrant vector memory for cross-run knowledge |

AID is most useful for multi-step features where work naturally breaks into roles
(design, implement, test, document) and where quality consistency matters.

---

## Can I use AID with my existing project?

Yes. AID works with any project that has a git repository. It creates a `.aid-o/`
workspace directory alongside your project files, reads your tech stack via
`/aid-setup`, and configures its quality gates and agent behavior to match your
tooling.

There are no changes to your project structure, no new dependencies added to your
`package.json` or `pyproject.toml`, and no modifications to your existing
configuration files unless you explicitly configure gates to use them.

AID supports Python, TypeScript/JavaScript, Go, Rust, Ruby, Java, and any other
language whose test and lint commands can be expressed as shell commands.

---

## How much does AID cost in token usage?

AID is more token-intensive than a direct Claude Code session. A typical EPIC
run dispatches multiple agents, each with its own context, and the Controller
reads evidence files at every state transition.

Approximate token costs per EPIC:

| EPIC Complexity | Steps | Approximate Token Usage |
|---|---|---|
| Small (2–3 steps) | 2–3 agents | 50k–150k tokens |
| Medium (4–6 steps) | 4–6 agents | 150k–400k tokens |
| Large (7+ steps, parallel) | 7+ agents | 400k–1M+ tokens |

These are estimates. Actual costs depend on the size of your codebase (more files
the agents read = more tokens), whether gates trigger retries (each retry is
additional cost), and whether Qdrant memory context is included per step.

You can set a budget in your EPIC spec:

```yaml
budget_usd: 50
```

The Controller warns you when 80% of the budget is consumed and escalates (trigger
E8) if the limit is exceeded.

---

## What happens if a step fails?

The behavior depends on why it failed:

**Agent produces incorrect output**: the Controller dispatches the
code-reviewer agent to evaluate the output. If it fails acceptance criteria, the
agent is re-dispatched with the reviewer's feedback. After a second failure, the
same step is retried with a "fresh approach" instruction. After a third failure,
escalation E1 fires and the PM is notified.

**Quality gate fails after agents complete**: the retry engine analyzes the
failure, dispatches the gate-fixer agent with targeted context, and re-runs the
gate. Up to 3 attempts are made. If all attempts fail, escalation E4 fires.

**In FIRST AID auto-mode**: the same retry logic applies. The PM is only contacted
for the escalation triggers defined in the `auto-escalation` skill. Non-critical
failures are resolved autonomously.

In every case, the full retry history is written to `gates_report.json` in the
evidence directory, so you have a complete record of what was attempted.

---

## Can I skip quality gates?

Yes, in two ways:

**Per-gate on a single EPIC run**: when an escalation occurs for a failing gate,
respond with option B (Skip). The gate is marked `skipped_by_pm` and execution
continues.

**Permanently for a gate type**: set `required: false` in `gates.yaml`. A
non-required gate that fails produces a warning in the gate report but does not
block the pipeline.

```yaml
security_scan_pass:
  required: false    # warnings only, does not block
  command: "bandit -q -r . -ll"
```

You cannot disable the pre-commit 6-gate agent protocol (the quality gates that
agents run before every `git commit`) through configuration — that protocol is
enforced by the agent-core skill. However, you can add instructions to a playbook
to adjust what agents are expected to check.

---

## How do I add a custom gate?

Add a new entry to `.aid-o/03-config/policies/gates.yaml`. Any entry with a
`command` field is executed as a shell command; any entry with a `rule` field is
evaluated by agent judgment.

**Command gate example** (runs a shell command):

```yaml
e2e_pass:
  description: "End-to-end tests pass against the staging environment"
  required: false
  command: "npx playwright test --reporter=line"
  timeout_seconds: 300
  pass_criteria: "exit code 0"
  when: "e2e/ files changed"
```

**Rule gate example** (evaluated by the Controller, not a shell command):

```yaml
api_contract_updated:
  description: "OpenAPI spec must be updated if endpoint signatures change"
  required: true
  rule: "docs/api/openapi.yaml must be updated when src/api/ files change"
  pass_criteria: "git diff includes docs/api/openapi.yaml"
```

After adding a gate, it takes effect on the next EPIC run. No restart or reload
is required.

---

## How does the permission sandwich work?

The permission sandwich is the mechanism that makes FIRST AID auto-mode safe.
Before autonomous execution begins, AID:

1. **Backs up** your current `~/.claude/settings.json` to `permissions-backup.json`
2. **Elevates** permissions using the allow-list in `permissions-auto.yaml`
3. **Runs** the EPIC queue with the elevated permissions
4. **Restores** your original `settings.json` when the session ends — or when `/aid-stop`
   is called, or after a crash (crash recovery detects the leftover backup file)

The hard-deny list is never overridden regardless of what is in `permissions-auto.yaml`:
`git push --force`, `git reset --hard`, and `rm -rf /` are permanently blocked.

Permissions grow incrementally: when you manually approve a new permission during
an auto-mode escalation, that permission is added to `permissions-auto.yaml`
automatically so you are not prompted again in future sessions.

---

## What are escalation triggers?

Escalation triggers are the 16 specific conditions under which FIRST AID auto-mode
pauses and requires PM input. Outside of these conditions, the pipeline runs
autonomously.

The 16 triggers by severity:

**CRITICAL (immediate halt)**:
- E1 — Step fails after two re-dispatches and a fresh approach attempt
- E2 — Security agent reports a CRITICAL severity finding
- E4 — Quality gate fails after all retry attempts (default: 3)

**HIGH (pause after current operation)**:
- E3 — Security agent reports a HIGH severity finding
- E5 — Agent produces no output, times out, or errors
- E6 — Merge conflict detected between parallel agent branches
- E7 — Agent explicitly flags it cannot resolve the assigned task
- E8 — Estimated token cost exceeds the configured budget limit

**MEDIUM (pause at next phase boundary)**:
- E9 — Agent violates scope on a second attempt
- E10 — Two agents produce contradictory decisions or designs
- E11 — Plan JSON is invalid or cannot be validated
- E12 — Session escalation count reaches the configured maximum
- E13 — Architect outputs a decision requiring PM input with two or more valid options
- E15 — Release sub-phase cannot determine the current version from version files
- E16 — Planner flags acceptance criteria as unparseable or contradictory

Every escalation pauses the queue, saves progress (including a `git stash`),
and sends a notification via Slack (if configured) or in chat. The PM chooses from
four options: Fix, Skip, Abort, or Continue Manual.

---

## Can I run multiple EPICs at once?

Not in parallel. AID processes EPICs sequentially from the queue — one at a time,
in priority order. This is a deliberate design choice: parallel EPICs would
share the git repository and risk unresolvable conflicts between independent branches.

You can queue as many EPICs as you like and let FIRST AID process them sequentially
unattended:

```text
/aid-epic-queue add .aid-o/02-epics/E-001-auth.md --priority high
/aid-epic-queue add .aid-o/02-epics/E-002-api.md --priority medium
/aid-epic-queue add .aid-o/02-epics/E-003-frontend.md --priority medium
/aid-first-aid
```

AID will work through all three EPICs in sequence, pausing only for escalation triggers.

---

## How do I reset a stuck pipeline?

If the orchestration pipeline is unresponsive or stuck in a state it cannot leave
on its own:

1. **In FIRST AID mode**: run `/aid-stop` to cleanly disengage auto-mode and
   restore your permissions. Progress is saved.

2. **In manual mode**: re-run the same command (`/aid-run-epic {epic_id}`). The
   Controller reads `plan_progress.json` and resumes from the last completed step.

3. **If the pipeline is stuck on a specific gate**: respond to the current escalation
   with option B (Skip) to bypass the failing gate, or option C (Abort) to stop
   the EPIC entirely.

4. **Nuclear reset** — if `plan_progress.json` is corrupted and `stage_log.jsonl`
   is unreadable, you can manually edit `plan_progress.json` to mark completed steps
   with `"status": "done"` and re-run `/aid-run-epic`. The Controller will skip
   steps marked done.

5. **Queue reset**: if the queue itself is stuck with `paused: true`, run:

```text
/aid-epic-queue resume
```

---

## Does AID work offline?

Partially. AID is a Claude Code plugin, so it requires Claude Code (and therefore
internet access to Anthropic's API) to dispatch agents and run the Controller.

The following features work offline once the plugin is installed:

- Reading and editing `.aid-o/` files directly
- Running gate commands manually (pytest, eslint, etc.)
- Reviewing evidence files and run logs

The following features require internet access:

- Any `/aid-*` command that dispatches an agent or the Controller
- Qdrant memory operations (the Qdrant MCP server itself can run locally, but
  the Claude API call that uses it requires connectivity)
- Slack MCP notifications

If you are working in an environment with intermittent connectivity, the queue
and evidence files persist across sessions. When connectivity is restored, run
`/aid-first-aid --resume` to continue from the last saved state.

---

## Can I use AID with other AI models?

AID is built specifically for Claude Code and the Claude family of models. It
uses Claude Code's slash command system, the Task tool for agent dispatch, and
the Bash/Read/Write tools that are built into Claude Code.

The plugin cannot be ported to other AI coding assistants (GitHub Copilot,
Cursor, Gemini CLI) without significant re-implementation, as those systems do
not expose equivalent plugin or slash command mechanisms.

Within the Claude ecosystem, AID works with any Claude model available through
Claude Code. The quality of agent outputs will vary by model capability, but
the orchestration infrastructure works the same way.

---

## How do I contribute to AID?

The AID Orchestrator repository is at `marekstancl/claude-aid-o`. Contributions
are welcome in the following areas:

- **New agents**: add a new role agent by creating a playbook in `defaults/playbooks/`
  and registering it in `plugins/aid-orchestrator/.claude-plugin/plugin.json`
- **New commands**: add a new slash command as a Markdown file in `plugins/aid-orchestrator/commands/`
- **Bug reports**: open an issue with the EPIC ID, the relevant `stage_log.jsonl` entries,
  and the full gate failure output from `gates_report.json`
- **Documentation**: documentation lives in `docs/docs/` and is built with Docusaurus v3

Before contributing, read the contributing guide at `docs/docs/contributing/` and
review the plugin structure documentation at `docs/docs/contributing/plugin-structure/`
to understand the directory layout and conventions.

All plugin changes require updating `CHANGELOG.md` (both root and
`plugins/aid-orchestrator/CHANGELOG.md` — they must be identical) and the `Last Updated`
date in any modified skill or agent files.

---

## Where are evidence files stored?

Evidence files are stored in the `.aid-o/04-engine/evidence/` directory, organized
by EPIC ID and run ID:

```text
.aid-o/04-engine/evidence/
  {epic_id}/
    {run_id}/
      plan.json                    Execution plan with step dependency graph
      plan_progress.json           Live step completion tracker
      epic_input.md                Copy of the EPIC file used for this run
      stage_log.jsonl              Timestamped log of every state machine transition
      gates_report.json            Gate results with retry history and attempt details
      pm_plan_approval.json        PM plan review decision
      pm_decision.json             PM escalation and merge approval decisions
      curator_resolve_report.json  Curator proposal evaluation outcomes
      final_report.md              Post-run summary with decisions and outcomes
      steps/
        step_{N}_{role}/
          prompt.md                Agent dispatch prompt
          output.md                Agent step output (step_output YAML)
          diff.patch               File changes from this step
          review.md                Code-reviewer feedback (if dispatched)
      escalations/
        escalation_{trigger}_{timestamp}.json
```

Evidence files are never deleted during normal operation. Completed runs are
archived when the EPIC moves to DONE state — the evidence directory remains
accessible at the same path.

To find evidence for a specific EPIC run:

```bash
ls .aid-o/04-engine/evidence/
```

If the EPIC has been archived (moved to `.aid-o/02-epics/archive/`), its evidence
directory remains in `.aid-o/04-engine/evidence/` and is not moved.

---

## Why is my EPIC not starting when I run `/aid-run-epic`?

The most common reasons:

1. **EPIC file not found**: verify the path. EPIC files live in `.aid-o/02-epics/`.
   Completed EPICs are in `.aid-o/02-epics/archive/` and cannot be re-run from there
   without copying them back.

2. **Plan JSON missing**: if the EPIC has no `plan.json` yet, the Controller
   generates one automatically at PLANNING state. This is not an error.

3. **Queue is paused**: if you are using `/aid-epic-queue`, check whether the
   queue's `paused` flag is set. Run `/aid-epic-queue resume` to unpause.

4. **Git not initialized**: AID requires a git repository. Run `git init` in the
   project root if you have not done so already.

5. **Workspace not initialized**: run `/aid-init` to create the `.aid-o/` structure
   if it does not exist.
