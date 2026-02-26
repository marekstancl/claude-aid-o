---
sidebar_position: 4
title: "Adding an Agent"
description: "Step-by-step guide to adding a new specialized agent to the AID plugin."
---

# Adding an Agent

AID agents are specialized role definitions that the Controller dispatches during EPIC execution. Each agent is a single Markdown file in `plugins/aid-orchestrator/agents/`. The Controller (via `/aid-run-epic`) invokes agents by passing their file contents as the system prompt in a Claude Task call.

## Anatomy of an Agent File

The `qa.md` agent illustrates the complete structure every agent must follow. Here is a condensed view of its key sections:

```markdown
---
model: sonnet
---

# QA Engineer Agent

**Role:** Write tests, validate quality, ensure coverage targets are met.
**Type:** Role agent — dispatched by Controller during EPIC execution.
**Playbook:** `defaults/playbooks/qa.md`

---

## Identity

You are the **QA Engineer** agent. You are the guardian of correctness ...

---

## Capabilities

### Unit Test Writing
- Write focused unit tests for individual functions, methods, and classes
...

---

## Constraints — CRITICAL

These constraints are non-negotiable:

### Scope Enforcement
- **ONLY** modify files within `allowed_paths` provided in the step spec
- **NEVER** modify files in `forbidden_paths`
...

---

## Input

You receive from the Orchestrator:

\`\`\`yaml
step_spec:
  step_id: "{step_id}"
  title: "{step title}"
  ...
\`\`\`

---

## Output Format

\`\`\`yaml
step_output:
  step_id: "{step_id}"
  agent: "qa"
  status: "completed|partial|blocked"
  ...
\`\`\`

---

## Workflow

\`\`\`
1. RECEIVE step_spec from Orchestrator
2. READ your playbook (defaults/playbooks/qa.md)
...
\`\`\`

---

## Important

- You are the **last line of defense** before code reaches quality gates. ...
```

## Required Frontmatter

```yaml
---
model: sonnet
---
```

The `model` field specifies which Claude model to use when this agent is dispatched. Valid values are:

| Value | Model used |
|-------|------------|
| `sonnet` | Claude Sonnet (standard tasks — most agents) |
| `opus` | Claude Opus (complex reasoning — Architect, Orchestrator) |

Use `sonnet` for all new agents unless the task requires deep multi-step reasoning across large codebases. Using `opus` increases cost significantly.

## Required Sections

Every agent file must contain all of these sections in order:

### Header Block

```markdown
# {Agent Name} Agent

**Role:** {one-line description of the role}
**Type:** Role agent — dispatched by Controller during EPIC execution.
**Playbook:** `defaults/playbooks/{role}.md`
```

The `**Type:**` line must be exactly one of:
- `Role agent — dispatched by Controller during EPIC execution.`
- `Utility agent — invoked at specific pipeline checkpoints.`
- `Specialist agent — invoked for specific analytical tasks.`

The `**Playbook:**` line points to the playbook file under `defaults/playbooks/`. If you are adding a new role agent, you must also create the corresponding playbook.

### `## Identity`

One or two paragraphs written in second person ("You are the...") that establish the agent's role, mindset, and primary responsibility. Be explicit about what the agent does NOT do — this prevents scope creep.

Example from `qa.md`:

```markdown
You are the **QA Engineer** agent. You are the guardian of correctness — you write
tests that prove the system works as intended and catch regressions before they
reach users. ... You do NOT modify implementation code. If a test reveals a bug,
you document it clearly so the appropriate implementation agent can fix it.
```

### `## Capabilities`

List the agent's specific capabilities as subsections. Each subsection contains 3–5 bullet points. Be concrete — list what the agent produces, not just what it thinks about.

```markdown
## Capabilities

### Unit Test Writing
- Write focused unit tests for individual functions, methods, and classes
- Test happy paths, edge cases, and error conditions
- Use appropriate mocking/stubbing for external dependencies
- Follow Arrange-Act-Assert (AAA) pattern consistently
```

### `## Constraints — CRITICAL`

This section must contain three subsections: **Scope Enforcement**, **Role Boundaries**, and **Quality Standards**.

**Scope Enforcement** is identical for all agents:

```markdown
### Scope Enforcement
- **ONLY** modify files within `allowed_paths` provided in the step spec
- **NEVER** modify files in `forbidden_paths`
- If the task requires changes outside `allowed_paths`, report status: `blocked`
  with explanation
```

**Role Boundaries** defines what the agent must never do. These must be specific to the role. For example, the QA agent must never modify implementation code. The Architect agent must never write implementation code.

**Quality Standards** lists measurable criteria the agent's output must meet.

### `## Input`

Show the exact YAML step spec the agent receives. This is the same structure for all agents — copy it from an existing agent and update only the `agent_role` field:

```yaml
step_spec:
  step_id: "{step_id}"
  title: "{step title}"
  description: "{what to do}"
  agent_role: "{your-role-name}"
  allowed_paths: ["src/..."]
  forbidden_paths: ["src/other/..."]
  dependencies: ["{previous step IDs}"]
  acceptance_criteria:
    - "{criterion 1}"
    - "{criterion 2}"
  context:
    epic_id: "{epic_id}"
    epic_goal: "{high-level goal}"
    prior_outputs: ["{relevant prior step outputs}"]
```

### `## Output Format`

Show the exact YAML step output the agent must produce. The `agent` field must match the `agent_role` from the input:

```yaml
step_output:
  step_id: "{step_id}"
  agent: "{your-role-name}"
  status: "completed|partial|blocked"
  artifacts:
    - path: "path/to/created/file"
      type: "created|modified|deleted"
      description: "What this file is/what changed"
  summary: "One paragraph of what was done"
  decisions:
    - decision: "What was decided"
      rationale: "Why"
  improvement_notes:
    - type: refactoring|performance|security|architecture|dx
      area: "path/to/module"
      observation: "What you observed"
      suggestion: "What should be done"
      priority: low|medium|high
      source_agent: "{your-role-name}"
      source_step: "{step_id}"
```

Include the Status Values table:

```markdown
### Status Values

| Status | Meaning |
|--------|---------|
| `completed` | All acceptance criteria met |
| `partial` | Some criteria met, others need follow-up |
| `blocked` | Cannot proceed — needs input or scope change |
```

### `## Workflow`

A numbered list in a code block describing what the agent does in sequence:

```
1. RECEIVE step_spec from Orchestrator
2. READ your playbook (defaults/playbooks/{role}.md)
3. READ relevant context:
   - EPIC specification
   - Prior step outputs (from dependencies)
   - Existing code in allowed_paths
4. VALIDATE scope — confirm all needed files are in allowed_paths
5. EXECUTE task per playbook guidelines
6. VERIFY against acceptance_criteria
7. RECORD improvement_notes for issues observed
8. OUTPUT step_output YAML block
```

### `## Important`

Two to four bullet points that reinforce the most critical behavioral requirements — things that must never be forgotten or ignored. These directly follow the workflow and serve as final anchors.

## Step-by-Step: Adding a New Agent

### 1. Create the Agent File

```bash
touch plugins/aid-orchestrator/agents/summarizer.md
```

### 2. Write the Full Agent Definition

Follow the structure above. Do not omit sections — all sections are required.

### 3. Create the Playbook

Create `plugins/aid-orchestrator/defaults/playbooks/summarizer.md`. The playbook provides execution guidance specific to the role's tasks. At minimum, it needs:

- `## Responsibilities` — what the agent is expected to produce
- `## Inputs` — what prior outputs and files the agent reads
- `## Outputs` — artifact table (what, format, where)
- `## Process` — numbered steps
- `## Quality Criteria` — checklist

### 4. Update CHANGELOG

Add an entry to both CHANGELOG files:

```markdown
### Added
- **Summarizer agent** — condenses completed EPIC step outputs into a consolidated
  project summary for retrospective review.
```

### 5. Add Documentation

Add `docs/docs/agents/{your-agent}.md` following the pattern of existing agent doc pages.

## Tool Access Configuration

AID agents run as Claude Code subagents via the Task tool. They inherit the tool permissions set in `defaults/policies/permissions.yaml` (manual mode) and `defaults/policies/permissions-auto.yaml` (FIRST AID autonomous mode).

If your agent needs tools not already listed in these policies, update `permissions.yaml` with a comment explaining why the tool is needed. Tool permissions apply to all agents — there is no per-agent permission list at the policy level. Keep the permissions as narrow as the most restricted agent needs, and document exceptions clearly.

## Testing an Agent

Testing an agent means verifying it behaves correctly when dispatched during EPIC execution:

1. **Write a minimal EPIC** that triggers a step with your new agent's `agent_role`.
2. **Run `/aid-plan-epic`** to generate the plan JSON.
3. **Run `/aid-run-epic`** and observe the dispatched agent's behavior.
4. **Verify the step output YAML** contains the correct `agent` field, valid `status`, and meaningful `artifacts`.
5. **Check scope enforcement** — verify the agent does not modify files outside `allowed_paths`.
6. **Check role boundaries** — verify the agent does not do things the Constraints section forbids.

Also test error conditions:
- What happens when `allowed_paths` is too narrow and the agent cannot complete the task? (It should report `blocked`.)
- What happens when prior step outputs are missing or incomplete? (It should work with what it has, or report `partial`.)
