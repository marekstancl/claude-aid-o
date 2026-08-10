---
id: P-20260221-6bde
type: plan
status: done
created: 2026-02-21
author: PM + AI
---

# Plan: AID Instruction Updates — Brainstorm Handoff, Plan-Epic Phases, Aid-Init Path

## Context

The AID Orchestrator plugin (v0.4.1) has several instruction files that need updates:
1. `/aid-init` supports an optional path parameter, but it's undocumented in Usage
2. The brainstorming handoff (Step 9) presents unhelpful "next steps" instead of interactive options
3. `/plan-epic` doesn't support generating EPICs for specific phases from a multi-phase plan
4. Several files use non-standard step numbering (0.5, 0.7, 2.5, 8b, 9a/9b)

These issues reduce usability and make cross-referencing between files error-prone.

## Goal

Update 7 AID instruction files to document the `[path]` parameter, replace the brainstorming handoff with interactive A-D options, add phase selection support, and clean up all non-standard step numbering.

## Scope

**In scope:**
- `commands/aid-init.md` — Usage section update
- `commands/aid-help.md` — /aid-init reference update
- `commands/aid-brainstorm.md` — Step renumbering + new handoff
- `commands/plan-epic.md` — Full step renumbering + phase support
- `skills/brainstorming.md` — Phase handling + re-open protocol
- `commands/run-epic.md` — Cross-reference updates
- `skills/epic-orchestration.md` — Cross-reference updates

**Out of scope:**
- `.venv` handling in run-epic (backlog item)
- `skills/planner.md` — no changes needed (own numbering)
- `CHANGELOG.md` — historical, not modified
- Marketplace cache — updated automatically from dev repo

## Approach

### Option A: Minimal Direct Edits (Recommended)

Edit all 7 files directly with targeted text changes. No new files created. All changes are instruction text updates (~50 edits across 7 files).

**Pros:**
- Minimal blast radius — only touches what needs changing
- No new abstractions or files
- Easy to review diff
- Follows YAGNI

**Cons:**
- Cross-reference updates require careful grep verification
- Many small edits across multiple files

### Option B: New Skill "plan-selector"

Extract phase selection logic into a dedicated skill file.

**Pros:**
- Centralized phase selection logic
- Reusable across commands

**Cons:**
- Over-engineered for the current need
- Adds a new file to maintain
- Violates YAGNI — only one consumer (brainstorming handoff)

### Decision

**Chosen:** Option A
**Rationale:** Direct edits are simpler, follow YAGNI, and all changes are instruction text. A new skill would add unnecessary complexity for a single consumer.

## High-Level Steps

| # | Step | Description | Estimated Effort |
|---|------|-------------|-----------------|
| 1 | aid-init.md path parameter | Update Usage section to document `[path]` parameter with examples | S |
| 2 | aid-help.md reference | Update `/aid-init` entry to show `[path]` parameter | S |
| 3 | plan-epic.md renumbering | Renumber all steps: 0.5→1, 0.7→2, 1→3, 2→4, 2.5→5, 3→6, 4→7, 5→8, 6→9 | M |
| 4 | plan-epic.md phase support | Add phase selection handling in Step 2 (Plan-to-EPIC Conversion) | S |
| 5 | aid-brainstorm.md renumbering | Renumber: 8b→9, 9→10 (9a/9b merged into single Step 10) | S |
| 6 | aid-brainstorm.md new handoff | Replace Step 10 with interactive A-D options (add items / all phases / specific phase / manual) | M |
| 7 | brainstorming.md updates | Add phase selection to EPIC Subagent Prompt Template + re-open protocol for Option A | M |
| 8 | Cross-reference updates | Update all plan-epic step references in aid-brainstorm.md, run-epic.md, epic-orchestration.md, brainstorming.md | M |
| 9 | Verification | Grep all files for old step numbers to confirm no references missed | S |

## Constraints

- All changes are markdown text edits — no code, no tests, no build
- Must not break existing command behavior — only instruction text changes
- Cross-references must be consistent across all 7 files after changes
- Marketplace cache is NOT edited directly — it syncs from dev repo

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Missed cross-reference | medium | medium | Full grep search performed, all refs catalogued in design doc |
| Phase detection unreliable at runtime | low | medium | Fallback: if phases unclear, default to all-phases EPIC |
| Re-open brainstorming complexity | low | low | Clear protocol with explicit state management in brainstorming.md |

## Success Criteria

- `/aid-init ./path` behavior is documented in Usage section with examples
- `/aid-help commands` shows `[path]` parameter for /aid-init
- `/aid-brainstorm` Step 10 presents A-D options (add items, all phases, specific phase, manual)
- Option A re-opens brainstorming with existing plan context
- Option B creates single EPIC covering all phases
- Option C creates EPIC for selected phase only
- Option D provides standard manual handoff
- No step numbers use decimals (0.5, 0.7, 2.5) or letters (8b, 9a, 9b) in any file
- All cross-references updated and verified across 7 files

## Next Steps

- [ ] Create EPIC from this plan
- [ ] Execute via /run-epic

---

**Last Updated:** 2026-02-21
