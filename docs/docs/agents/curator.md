---
id: curator
title: "Curator Agent"
sidebar_label: "Curator Agent"
description: "Collect improvement observations from agents, deduplicate against backlog, and propose actionable improvements."
---

# Curator Agent

The Curator agent runs once after all steps complete and quality gates pass, during the CURATOR_RESOLVE state. It collects improvement observations recorded by worker agents throughout the run, deduplicates them against the existing backlog, analyzes patterns across observations, and produces formal improvement proposals for the Orchestrator to evaluate.

## Role

The Curator is a **specialist agent**, not a role agent. It does not execute plan steps and does not communicate directly with the PM. All of its proposals route through the Orchestrator, which auto-evaluates them using rules from `decision-policies.yaml` before any reach the PM.

## When Dispatched

- During CURATOR_RESOLVE state, after all EPIC steps complete and quality gates pass
- Runs before PM_APPROVAL, in parallel with the Lessons Extractor agent
- Triggered by the `epic-orchestration` skill

## Capabilities

### Collection

Reads all `improvement_notes` arrays from every step output file at `evidence/{epic_id}/{run_id}/steps/*/step_output.json`. Merges them into a single flat list, tagging each note with its source agent and step.

### Deduplication

Compares each collected note against `.aid-o/04-engine/backlog.md`:
- **Exact match** (same type + area + >80% observation overlap): adds the source to the existing entry, does not create a duplicate
- **Similar match** (same area + related type): merges observations, keeps the more specific suggestion
- **New**: adds to the pending queue for proposal generation

### Pattern Analysis

- **Hotspot detection:** three or more notes targeting the same area flag it as a hotspot
- **Cross-agent consensus:** when multiple distinct agent roles report the same issue, the signal is weighted higher than one agent reporting it multiple times
- **Persistent issues:** notes that appeared in a previous run and remain unresolved are flagged as persistent

### Priority Escalation

- Three or more agents reporting the same area + type → escalate to `high`
- `security` type at any priority → minimum `medium`
- Same note persisting across two or more runs → escalate one level
- Note matching a `lessons-learned.md` pattern → flagged as "recurring — needs systemic fix"

Priority can only go up, never down.

### Proposal Generation

Generates a formal proposal for each note that is: priority `high`, reported by three or more independent sources, `security` type at medium/high, or persistent across two or more runs without resolution. Each proposal includes a title, rationale citing agent evidence, proposed action, effort estimate, and cost/benefit analysis.

### Backlog Management

Updates `.aid-o/04-engine/backlog.md` with new entries assigned sequential `IMP-{NNN}` IDs. Never deletes entries — they only change status. Proposals are written to the correct category section: Bugs, Features, Refactoring/Tech Debt, or Performance.

## Tools Available

Read access to all `evidence/{epic_id}/{run_id}/steps/*/step_output.json` files. Read/write access to `.aid-o/04-engine/backlog.md` and `.aid-o/04-engine/lessons-learned.md`. Optionally stores proposals in Qdrant for cross-project pattern detection (silently skipped if Qdrant is unavailable).

## Key Behaviors

- **Never modifies source code.** Analyzes and proposes only.
- **Never communicates directly with the PM.** Always routes through the Orchestrator.
- **Preserves backlog history.** Entries are never deleted, only status-changed.
- **IMP-{NNN} IDs are sequential and never reused**, even for rejected or implemented proposals.
- **Deduplication threshold is >80% observation overlap.** Below 80% is treated as a separate issue.
- The Orchestrator auto-evaluates proposals using a 3-tier algorithm: explicit YAML rules → Qdrant past-decision similarity → default action.
- Approved proposals may be fixed immediately within the same EPIC by dispatching fix agents during CURATOR_RESOLVE.
- At PM_APPROVAL, the PM sees a compact Curator summary and can override rejected proposals or teach new auto-rules.

## Related

- [Auditor Agent](./auditor)
- [Lessons Extractor Agent](./lessons-extractor)
- [Improvement Proposals Skill](../skills/improvement-proposals)
- [Epic Orchestration Skill](../skills/epic-orchestration)
