---
sidebar_position: 12
title: "Lessons Extractor Agent"
description: "Extract reusable lessons, working commands, and project-specific gotchas from completed EPIC runs."
---

# Lessons Extractor Agent

The Lessons Extractor agent analyzes a completed EPIC run and extracts reusable knowledge: new commands that were verified working, lessons learned about patterns and pitfalls, and project-specific gotchas to avoid in future runs. It does not modify workspace files directly — it produces a structured report, and the Controller writes the deduplicated output to the appropriate workspace files.

## Role

The Lessons Extractor is a **specialist agent**. It runs during CURATOR_RESOLVE state in parallel with the Curator agent. The two agents are independent — no coordination is needed between them. The Controller is responsible for applying deduplication and writing the lessons-extractor output to workspace files.

## When Dispatched

- During CURATOR_RESOLVE state, after all EPIC steps complete and quality gates pass
- Runs in parallel with the Curator agent
- Triggered by the `epic-orchestration` skill

## Capabilities

### Working Commands

Finds commands that were used successfully in the run and are not already in `.aid-o/04-engine/command-history.md`. Records exact syntax, purpose, and verification date. Only commands that were actually verified working are included — no theoretical commands.

### Lessons Learned

Finds new insights, gotchas, or patterns discovered during the run. Lessons must be actionable (not just "things happened") and include enough context to be useful in future runs.

### Known Gotchas

Identifies project-specific knowledge that will save future runs from repeating mistakes. Gotchas are specific to the current project and based on what actually happened.

### Deduplication

Before reporting, applies a three-layer deduplication check:

- **Layer 1 — Exact text match:** >90% character overlap with an existing entry → tagged `DUPLICATE: exact`
- **Layer 2 — Semantic overlap:** >80% semantic overlap with different wording → tagged `DUPLICATE: semantic`
- **Layer 3 — Qdrant cross-run:** similarity >0.85 in Qdrant. Same project → `DUPLICATE: qdrant-same-project`. Different project → `CROSS_PROJECT: {source_project}` (kept with cross-project tag, not treated as a duplicate)

Items tagged as duplicates are not written to workspace files. Items tagged as `CROSS_PROJECT` are included with their cross-project tag for enrichment.

## Tools Available

Read access to `.aid-o/04-engine/command-history.md`, `.aid-o/04-engine/lessons-learned.md`, the active run file, and git history. Does not modify any files.

## Key Behaviors

- **Read-only.** Does not modify workspace files — only reads and produces a structured report.
- **The Controller (CURATOR_RESOLVE state) writes the output** to `lessons-learned.md` and `command-history.md`, and optionally to Qdrant collection `aid-orchestration-log`.
- **Every item in the report must include a `dedup_status` field**: NEW, DUPLICATE (exact/semantic/qdrant-same-project), or CROSS_PROJECT.
- **Quality over quantity.** Only genuinely useful, actionable knowledge is extracted.
- If no new lessons or commands are found, outputs "None found" — the Controller skips the write.

## Related

- [Curator Agent](./curator)
- [Run Management Skill](../skills/run-management)
- [Epic Orchestration Skill](../skills/epic-orchestration)
