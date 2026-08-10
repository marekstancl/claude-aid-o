---
id: P004
type: plan
status: completed
created: 2026-02-23
author: PM + AID
depends_on: P002
---

# Plan: Brainstorming Enhancement

## Context

AID's brainstorming skill (`skills/brainstorming.md`) and command (`commands/aid-brainstorm.md`)
work well as a foundation but need two key improvements:

1. **Deeper initial analysis:** Currently, after PM provides a topic, AI reads project context
   and immediately starts asking questions. There is no visible analysis phase where AI
   demonstrates understanding of the topic, identifies key aspects, risks, and dependencies
   before questioning begins. PM has no confidence that AI truly understood the assignment.

2. **3 options + recommendation at every decision point:** The brainstorming skill's Approach
   Exploration Protocol already requires 2-3 approaches in Step 3, but this pattern should
   extend to EVERY decision point throughout the brainstorming session — not just the main
   approach selection. Every question that involves a direction choice should present structured
   options with a recommendation.

3. **Example EPIC lookup is broken:** The lookup logic (added in E-c5de + E-00f3) has two bugs
   that cause it to silently skip all 19 example EPICs: (a) type filter expects `"example_epic"`
   but files use `type: "example"`, (b) flat directory scan misses files in subdirectories
   `ai-workflows/` and `common-projects/`.

These improvements were validated in a live brainstorming session (2026-02-23 roadmap review)
where the enhanced pattern was used manually and confirmed as the desired behavior.

## Goal

Update the brainstorming skill and command to include a mandatory deep analysis phase before
questioning and enforce the "3 options + recommendation" pattern at every decision point
throughout the session.

## Scope

**In scope:**
- New "Analysis Phase" between context gathering (Step 1) and questioning (Step 2)
- Updated questioning protocol: every directional question uses 3 options + recommendation
- Updated approach protocol: explicit requirement for deeper tradeoff analysis (why NOT the other options)
- Updates to `skills/brainstorming.md` (process rules, key principles, questioning protocol)
- Updates to `commands/aid-brainstorm.md` (step flow — insert analysis phase)

**Out of scope:**
- Workflow intelligence changes (WF1-WF7 inserts unchanged)
- Knowledge acquisition changes (search protocols unchanged)
- Docker/MCP preference changes (rules unchanged)
- EPIC subagent template changes
- Example EPIC lookup changes (beyond the bugfixes in Step 6 below)

## Approach

**Chosen: Extend existing skill with new phase + protocol updates**

Insert a new "Step 1.5: Initial Analysis" between context gathering and questioning.
Update the Questioning Protocol rules to mandate the options pattern. This preserves
all existing functionality while adding the desired behavior.

**Rejected alternatives:**
- *Rewrite brainstorming skill from scratch* — The skill is comprehensive and well-structured.
  A rewrite would risk losing the workflow intelligence integration, knowledge augmentation,
  and Docker/MCP preference rules that took multiple iterations to develop.
- *Separate "deep analysis" command* — Fragmenting the flow adds complexity. The analysis
  is a natural part of brainstorming, not a separate concern.

## Decision

Extend the existing brainstorming skill with a mandatory analysis phase and updated
questioning protocol. Minimal changes, maximum impact.

## High-Level Steps

1. **Add Initial Analysis Phase to brainstorming skill** — Insert new section in
   `skills/brainstorming.md` between "Key Principles" and "Process Rules". Define the
   analysis phase protocol:
   - AI reads PM's topic and all gathered context (project profile, knowledge, input files)
   - AI presents structured analysis to PM BEFORE asking any questions:
     - "What I understand from your topic" (paraphrase + key aspects identified)
     - "Key dimensions I see" (technical, organizational, integration, risk)
     - "Potential challenges" (what could go wrong, what needs careful decisions)
     - "What I need to clarify" (preview of question areas — not the questions themselves)
   - PM confirms understanding or corrects misunderstandings
   - Then questioning begins (more targeted because AI demonstrated understanding)
   Effort: S

2. **Update Questioning Protocol** — Modify Process Rules in `skills/brainstorming.md`:
   - Add new rule: "Every question that involves a directional choice MUST present 2-3
     structured options with labels (A/B/C), descriptions, and a recommendation with reasoning."
   - Update existing Rule 2 ("Prefer MULTIPLE CHOICE") to be stronger: "ALWAYS use multiple
     choice with recommendation. Open-ended ONLY for factual questions (names, URLs, numbers)
     where options cannot be predicted."
   - Add rule: "For each recommended option, briefly state why the alternatives are less suitable."
   Effort: XS

3. **Update command flow** — Modify `commands/aid-brainstorm.md` Step 1→2 transition to include
   the analysis phase. Renumber steps if needed or insert as Step 1.5. Update the flow diagram
   in the command documentation.
   Effort: XS

4. **Update MUST Rules** — Add to the MUST Rules section in `skills/brainstorming.md`:
   - "ALWAYS present initial analysis before first question"
   - "ALWAYS present 3 options + recommendation at every directional decision point"
   - "ALWAYS explain why alternatives are less suitable (not just why recommended is good)"
   Effort: XS

5. **Fix Example EPIC Lookup bugs** — Two bugs prevent brainstorming from finding any examples:
   - **Type mismatch:** `brainstorming.md` line 309 filters `frontmatter.type != "example_epic"`
     but all 19 example files use `type: "example"`. Fix: change filter to `"example"`.
   - **Flat directory scan:** `brainstorming.md` line 305 scans `defaults/examples/` without
     recursion, but examples live in subdirectories `ai-workflows/` and `common-projects/`.
     Fix: change to recursive scan (`defaults/examples/**/*.md`).
   After fix, verify at least one example is matched when brainstorming a RAG chatbot topic.
   Effort: XS

6. **Verification** — Walk through a brainstorming scenario mentally against the updated
   instructions. Verify: analysis phase triggers, options appear at decision points,
   recommendations include reasoning, non-directional questions remain open-ended,
   example EPIC lookup finds and offers matching examples.
   Effort: XS

## Constraints

- Changes limited to `skills/brainstorming.md` and `commands/aid-brainstorm.md`
- Must not break workflow intelligence integration (WF1-WF7)
- Must not break knowledge augmentation or Docker/MCP rules
- Analysis phase must not add excessive delay — concise analysis, not essay
- "3 options" is a guideline: 2 options acceptable when only 2 genuine alternatives exist

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Analysis phase feels redundant for simple topics | Medium | Low | Keep analysis concise (5-8 lines max); for trivial topics AI can state "straightforward topic, minimal analysis needed" |
| Too many options overwhelms PM | Low | Medium | Cap at 3 options; for binary decisions, 2 is fine |
| AI ignores new rules (same as before) | Medium | Medium | Make rules prominent: MUST Rules section, bold formatting, explicit checklist |
| Longer brainstorming sessions | Low | Low | Analysis phase replaces exploratory questions — net time should be similar |

## Success Criteria

- [ ] Initial analysis phase appears BEFORE first question in every brainstorming session
- [ ] Analysis includes: topic understanding, key dimensions, potential challenges, clarification preview
- [ ] Every directional question presents 2-3 options with recommendation
- [ ] Recommendations include reasoning for choice AND why alternatives are less suitable
- [ ] Non-directional questions (factual) remain open-ended
- [ ] Workflow intelligence inserts (WF1-WF7) still function correctly
- [ ] Knowledge augmentation still functions correctly
- [ ] Example EPIC lookup type filter matches actual frontmatter (`type: "example"`)
- [ ] Example EPIC lookup scans subdirectories recursively
- [ ] MUST Rules section updated with new requirements

## Next Steps

- [ ] Create EPIC from this plan
- [ ] Run via `/aid-run-epic`
