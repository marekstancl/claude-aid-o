---
id: overview
title: "Agent System Overview"
sidebar_label: "Agent System Overview"
description: "Overview of AID's 18 specialized agents and the multi-agent architecture."
---

# Agent System Overview

AID operates through a **Controller + Workers** architecture. When an EPIC runs, the Controller (implemented in the `epic-orchestration` skill) reads the execution plan and dispatches steps to specialized agents. Each agent has a defined role, a bounded scope of work, and a structured output format. Agents do not communicate with each other directly — they work through the Controller, reading prior step outputs from the evidence trail.

## Two Types of Agents

### Role Agents

Role agents are dispatched by the Controller during EPIC step execution. Each step in the plan specifies an `agent_role`, and the Controller dispatches the matching agent with a `step_spec` that includes the step description, allowed file paths, acceptance criteria, and context from prior steps.

Role agents produce a `step_output` YAML block that the Controller stores in the evidence trail. Other agents can reference these outputs as prior context.

### Specialist Agents

Specialist agents run outside the normal per-step flow. They are triggered by specific pipeline states or events — for example, the Auditor runs once after a completed EPIC is merged, and the Curator runs after all steps complete and quality gates pass. Specialist agents read evidence from the run but do not execute plan steps.

## Agent Table

| Agent | Type | Role | When Dispatched |
|-------|------|------|-----------------|
| [Architect](./architect) | Role | Design API contracts, event schemas, ADRs, module boundaries | When a step requires interface design or architectural decisions |
| [Auditor](./auditor) | Specialist | Post-Epic health audit — scoring across 6 categories | After Epic DONE + successful merge |
| [Backend](./backend) | Role | Implement server-side logic — APIs, services, data access | When a step requires backend implementation |
| [Code Reviewer](./code-reviewer) | Specialist | Review implementation against plan and coding standards | During PHASE_CHECK for step acceptance validation |
| [Curator](./curator) | Specialist | Collect improvement notes, deduplicate, propose improvements | During CURATOR_RESOLVE state, after gates pass |
| [Docs Reviewer](./docs-reviewer) | Specialist | Review documentation changes for compliance and completeness | During gate checks for documentation files |
| [Docs Writer](./docs-writer) | Role | Write and maintain documentation — API docs, guides, changelogs | When a step requires documentation authoring |
| [Domain](./domain) | Role | Model business domain — entities, aggregates, business rules | When a step requires domain modeling or business rule codification |
| [Frontend](./frontend) | Role | Implement UI — components, pages, client-side state | When a step requires frontend implementation |
| [Gate Fixer](./gate-fixer) | Utility | Fix failing quality gates with minimal targeted changes | During GATE_RETRY state when a gate fails |
| [Lessons Extractor](./lessons-extractor) | Specialist | Extract reusable knowledge and working commands from completed runs | During CURATOR_RESOLVE state, in parallel with Curator |
| [Observability](./observability) | Role | Add logging, metrics, tracing, health checks, alerting | When a step requires instrumentation |
| [Project Scanner](./project-scanner) | Specialist | Analyze project tech stack, architecture, and conventions | During `/aid-setup` (quick scan) or post-milestone (deep scan) |
| [QA](./qa) | Role | Write tests, validate quality, ensure coverage targets | When a step requires test authoring or coverage improvement |
| [Quality Gates Runner](./quality-gates-runner) | Utility | Run the 6-gate pre-commit quality protocol | Before any git commit |
| [Release](./release) | Role | Prepare releases — versioning, changelogs, migrations, CI/CD | When a step requires release preparation |
| [Run Validator](./run-validator) | Utility | Validate run file completeness at phase-end checkpoints | At phase-end or run-end checkpoints |
| [Security](./security) | Role | Audit security vulnerabilities, implement security controls | When a step requires security review or hardening |

## How Agents Communicate

Agents do not call each other directly. The communication path is always:

1. The Controller dispatches an agent with a `step_spec`.
2. The agent reads prior step outputs from the evidence trail (`prior_outputs` in `step_spec.context`).
3. The agent produces a `step_output` or specialist-specific output format.
4. The Controller stores the output and uses it to inform subsequent dispatches.

This design means every inter-agent dependency is explicit and traceable in the evidence trail.

## Scope Enforcement

Every agent receives an `allowed_paths` list and a `forbidden_paths` list. Agents are required to:

- Only modify files within `allowed_paths`
- Never touch files in `forbidden_paths`
- Report `status: blocked` if the task requires changes outside `allowed_paths`

This prevents agents from making unauthorized changes to unrelated parts of the codebase.

## Related

- [Skills Overview](../skills/overview)
- [Epic Orchestration Skill](../skills/epic-orchestration)
- [Quality Gates](../skills/quality-gates)
