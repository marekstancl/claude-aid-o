---
sidebar_position: 12
title: "Improvement Proposals"
description: "Defines the standard format for improvement_notes, the collection protocol across EPIC steps, deduplication rules, and integration with backlog.md and the Curator agent."
---

# Improvement Proposals

Every role agent observes issues during its work that are not blocking but are worth addressing: duplicated logic, missing abstractions, security risks, developer experience gaps. The improvement proposals skill defines how agents record these observations, how the Curator agent collects and deduplicates them across an EPIC, and how they flow into the project backlog.

## Purpose

Agents often spot problems that are outside their current assignment scope. Without a standard way to capture and route these observations, they get mentioned in prose and then lost. The improvement proposals skill creates a structured pipeline from observation to backlog entry, with deduplication to prevent the same issue from being flagged repeatedly across steps.

## When Used

- Every role agent includes `improvement_notes` in its `step_output` (always present, empty list if nothing observed)
- The Controller collects improvement notes at PHASE_CHECK from each step's output
- Analysis merge reports also produce improvement notes (merged from all analysis agents)
- The Curator agent runs at CURATOR_RESOLVE state and processes all collected notes into backlog proposals
- The Orchestrator evaluates Curator proposals against `decision-policies.yaml` for auto-approval or PM routing

## Key Concepts

### Improvement Note Format

Every note must include these fields:

```yaml
improvement_notes:
  - type: refactoring|performance|security|architecture|dx
    area: "path/to/file-or-module"
    observation: "What you observed — describe the problem factually"
    suggestion: "Concrete suggestion — what should be done"
    priority: low|medium|high
    source_agent: "{agent_role}"
    source_step: "{step_id}"
```

**Type categories:**

| Type | Description | Examples |
|---|---|---|
| `refactoring` | Code that works but should be restructured | Duplicated logic, god classes, deep nesting |
| `performance` | Performance bottleneck or inefficiency | N+1 queries, missing cache, unnecessary re-renders |
| `security` | Security risk or vulnerability | Hardcoded secrets, missing input validation, weak auth |
| `architecture` | Architectural concern or pattern violation | Wrong layer dependency, missing abstraction, contract drift |
| `dx` | Developer experience issue | Missing types, unclear API, missing docs, poor error messages |

**Priority levels:**

| Priority | Criteria |
|---|---|
| `low` | Nice to have, no immediate impact, can wait |
| `medium` | Causes friction or minor risk, should be addressed |
| `high` | Significant impact on quality, security, or maintainability — address soon |

### Deduplication

The Curator deduplicates improvement notes across all steps of an EPIC before creating backlog proposals. Two notes are considered duplicates if they share the same `type`, overlap significantly in `area`, and have similar `observation` and `suggestion` text. When duplicates are found, the highest-priority version is kept and the sources are merged.

### Backlog Integration

High-priority proposals that the Curator approves (via `decision-policies.yaml` auto-evaluation or PM override) become entries in `.aid-o/04-engine/backlog.md` with assigned IDs (`IMP-{NNN}`). The Orchestrator may route high-priority proposals back to agents for auto-fix within the current EPIC before PM_APPROVAL.

### Agent Rules

- `improvement_notes` must always be present in `step_output` — use `[]` if nothing was observed
- Never pad with invented issues
- Focus on observations made during the actual work, not general best practices
- The `observation` field describes what was seen (factual); the `suggestion` field describes what to do (actionable)

## How It Works

During an EPIC:
1. Each agent completes its step and includes `improvement_notes[]` in its output
2. The Controller collects all notes at PHASE_CHECK
3. After all steps, CURATOR_RESOLVE dispatches the Curator agent with all notes
4. The Curator deduplicates, evaluates against `decision-policies.yaml` and Qdrant history, and produces a Curator report
5. Auto-approvable proposals (matching auto-rules in Qdrant) are sent directly to agents for fixing
6. PM-required proposals are surfaced at PM_APPROVAL
7. Approved proposals flow to `backlog.md` as IMP entries

## Configuration

The Curator's auto-evaluation behavior is configured in `.aid-o/03-config/policies/decision-policies.yaml`. Rules define which proposal types and severities are auto-approved, auto-rejected, or routed to PM.

## Related

- [Epic Orchestration](../skills/epic-orchestration)
- [Analysis Merge](../skills/analysis-merge)
- [Agent Core](../skills/agent-core)
