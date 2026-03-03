---
sidebar_position: 4
title: "Adding an Agent"
description: "Step-by-step guide to adding a new specialized agent to the AID plugin."
---

# Adding an Agent

AID v2 agents are specialized role definitions that the Controller dispatches during pipeline execution. Each agent is a single Markdown file in `plugins/aid-orchestrator/agents/`. The Controller (via `/aid-run`) invokes agents by passing their file contents as the system prompt in a Claude Task call.

## v2 Agent Architecture

AID v2 uses a **parametric agent pattern** instead of v1's one-agent-per-role approach:

- **Implementer** (`implementer.md`) — a single parametric agent that accepts a **role card** (from `skills/role-cards.md`) defining the specific role: backend, frontend, architect, domain, docs-writer, etc. The implementer reads the role card and adapts its behavior accordingly.
- **Verifier** (`verifier.md`) — a single parametric agent that validates step output against acceptance criteria. It also receives a role card to apply role-specific verification checks.

This design reduced v1's 18 agents to 7, while maintaining the same role coverage through role cards.

The 7 agents in v2 are:

| Agent | Type | Purpose |
|-------|------|---------|
| `implementer.md` | Parametric | Execute steps using role card parameters |
| `verifier.md` | Parametric | Verify step output using role card parameters |
| `gate-fixer.md` | Utility | Fix failing quality gates in retry loop |
| `run-validator.md` | Utility | Validate run file before execution |
| `curator.md` | Specialist | Process improvement proposals |
| `auditor.md` | Specialist | Post-run health audit |
| `project-scanner.md` | Specialist | Analyze project structure |

## Anatomy of an Agent File

The `verifier.md` agent illustrates the complete structure every agent must follow. Here is a condensed view of its key sections:

```markdown
---
model: sonnet
---

# Verifier Agent

**Role:** Validate step output against acceptance criteria with role-aware checks.
**Type:** Parametric agent — dispatched by Controller with a role card.

---

## Identity

You are the **Verifier** agent. You validate that step outputs meet all acceptance
criteria defined in the plan. You receive a role card that tells you what role-specific
quality checks to apply...

---

## Capabilities

### Output Validation
- Compare step artifacts against acceptance criteria
- Verify file changes match expected scope
...

---

## Constraints — CRITICAL

These constraints are non-negotiable:

### Scope Enforcement
- **ONLY** read files within `allowed_paths` provided in the step spec
- **NEVER** modify any files — you are a read-only validator
...

---

## Input

You receive from the Controller:

\`\`\`yaml
step_spec:
  step_id: "{step_id}"
  title: "{step title}"
  role_card: "{role card content from skills/role-cards.md}"
  ...
\`\`\`

---

## Output Format

\`\`\`yaml
verification_output:
  step_id: "{step_id}"
  agent: "verifier"
  verdict: "pass|fail|partial"
  ...
\`\`\`

---

## Workflow

\`\`\`
1. RECEIVE step_spec and role_card from Controller
2. READ role card to understand role-specific checks
3. READ step output artifacts
4. VALIDATE against acceptance criteria
5. APPLY role-specific quality checks
6. OUTPUT verification_output YAML block
\`\`\`

---

## Important

- You are read-only — **never modify files**, only report findings.
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
| `haiku` | Claude Haiku (simple, fast tasks — gate-fixer, run-validator) |

The model assignment must match the `models` mapping in `.aid-o/config/orchestration.yaml`. Use `sonnet` for all new agents unless the task requires deep multi-step reasoning or can be handled by the simplest model.

## Required Sections

Every agent file must contain all of these sections in order:

### Header Block

```markdown
# {Agent Name} Agent

**Role:** {one-line description of the role}
**Type:** {agent type — see below}
```

The `**Type:**` line must be exactly one of:
- `Parametric agent — dispatched by Controller with a role card.`
- `Utility agent — invoked at specific pipeline checkpoints.`
- `Specialist agent — invoked for specific analytical tasks.`

### `## Identity`

One or two paragraphs written in second person ("You are the...") that establish the agent's role, mindset, and primary responsibility. Be explicit about what the agent does NOT do.

### `## Capabilities`

List the agent's specific capabilities as subsections. Each subsection contains 3-5 bullet points. Be concrete — list what the agent produces, not just what it thinks about.

### `## Constraints — CRITICAL`

This section must contain at minimum: **Scope Enforcement** and **Role Boundaries**.

**Scope Enforcement** is identical for all agents:

```markdown
### Scope Enforcement
- **ONLY** modify files within `allowed_paths` provided in the step spec
- **NEVER** modify files in `forbidden_paths`
- If the task requires changes outside `allowed_paths`, report status: `blocked`
  with explanation
```

**Role Boundaries** defines what the agent must never do. These must be specific to the role.

### `## Input`

Show the exact YAML step spec the agent receives. For parametric agents, include the `role_card` field.

### `## Output Format`

Show the exact YAML output the agent must produce.

### `## Workflow`

A numbered list describing what the agent does in sequence.

### `## Important`

Two to four bullet points that reinforce the most critical behavioral requirements.

## Step-by-Step: Adding a New Agent

### 1. Decide: New Agent vs. New Role Card

Before creating a new agent, consider whether a new **role card** in `skills/role-cards.md` would suffice. The parametric implementer/verifier pattern handles most role-specific behavior through role cards.

Create a new agent only when:
- The agent has fundamentally different input/output contracts (not just different domain focus)
- The agent serves a utility or specialist purpose outside the implement/verify cycle
- The agent needs a different workflow structure than implement → verify

If the new role fits the implement/verify pattern, add a role card instead (see `skills/role-cards.md`).

### 2. Create the Agent File

```bash
touch plugins/aid-orchestrator/agents/summarizer.md
```

### 3. Write the Full Agent Definition

Follow the structure above. Do not omit sections — all sections are required.

### 4. Register the Model Tier

Add the agent to the appropriate tier in `defaults/orchestration.yaml`:

```yaml
models:
  sonnet: [qa, security, docs-writer, curator, auditor, implementer, verifier, summarizer]
```

### 5. Update CHANGELOG

Add an entry to both CHANGELOG files:

```markdown
### Added
- **Summarizer agent** — condenses completed run outputs into a consolidated
  project summary for retrospective review.
```

### 6. Add Documentation

Add `docs/docs/agents/{your-agent}.md` following the pattern of existing agent doc pages.

## Testing an Agent

Testing an agent means verifying it behaves correctly when dispatched during pipeline execution:

1. **Write a minimal task** that triggers your agent's dispatch.
2. **Run `/aid-run`** and observe the dispatched agent's behavior.
3. **Verify the output YAML** contains the correct `agent` field, valid `status`, and meaningful `artifacts`.
4. **Check scope enforcement** — verify the agent does not modify files outside `allowed_paths`.
5. **Check role boundaries** — verify the agent does not do things the Constraints section forbids.

Also test error conditions:
- What happens when `allowed_paths` is too narrow and the agent cannot complete the task? (It should report `blocked`.)
- What happens when prior step outputs are missing or incomplete? (It should work with what it has, or report `partial`.)
