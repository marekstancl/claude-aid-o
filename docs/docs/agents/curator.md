---
sidebar_position: 5
title: "Curator Agent"
description: "Collects improvement observations, deduplicates against backlog, proposes improvements, and extracts lessons learned."
---

# Curator Agent

The Curator agent runs once after all steps complete and quality gates pass. It collects improvement observations from worker agents, deduplicates them against the existing backlog, analyzes patterns, generates formal improvement proposals, and extracts reusable lessons from the completed run.

In v2, the Curator merges the responsibilities of the former Curator and Lessons Extractor agents into a single post-run specialist.

## Role

The Curator is a **specialist agent**. It does not execute plan steps and does not communicate directly with the PM. All proposals route through the pipeline, which auto-evaluates them using rules from `decision-policies.yaml`.

## When Dispatched

- During CURATOR_RESOLVE state, after all EPIC steps complete and quality gates pass
- Runs before PM_APPROVAL
- Triggered by the pipeline (see [Pipeline](../skills/pipeline))

## Capabilities

### Phase 1: Collect Improvement Notes
Reads all step outputs from `evidence/<epic_id>/<run_id>/steps/*/output.md`, extracts `improvement_notes` sections, and merges into a flat list with source agent and step metadata.

### Phase 2: Deduplicate Against Backlog
Compares each note against `.aid-o/work/backlog.md`:
- **Exact match** (same type + area + >80% overlap): adds source to existing entry
- **Similar** (same area + related type): merges, keeps more specific suggestion
- **New**: adds to pending queue for proposal generation

### Phase 3: Pattern Analysis
- **Hotspot:** 3+ notes on same area
- **Cross-agent consensus:** multiple distinct roles report same issue (higher weight)
- **Persistent:** same note across 2+ runs unresolved

### Phase 4: Generate Proposals
Formal proposals for notes with priority `high`, 3+ sources, `security` medium+, or persistent 2+ runs. Each includes title, rationale, proposed action, effort (S/M/L), and category.

### Phase 5: Pre-Flight Status Update
Status updates BEFORE implementation: write `status: implementing` to backlog.md, dispatch fix agent, update to `implemented` or `deferred: fix failed`.

### Phase 6: Auto-Evaluate (2-Tier)
- Tier 1: YAML rules from `decision-policies.yaml`
- Tier 2: Default — effort S: approve, effort M/L: defer (PM decides)

### Phase 7: Lessons Extraction
Extract reusable commands and insights not already in `command-history.md` or `lessons-learned.md`. Each item gets `dedup_status`: NEW, DUPLICATE, or CROSS_PROJECT.

## Key Behaviors

- **Never modifies source code.** Analyze and propose only.
- **Never communicates with PM.** Routes through pipeline.
- **Preserves backlog history.** Never deletes entries, only status changes.
- **Sequential IMP-NNN IDs** never reused.
- **Model:** sonnet

## Related

- [Auditor Agent](./auditor)
- [Pipeline Skill](../skills/pipeline)
- [Memory Skill](../skills/memory)
