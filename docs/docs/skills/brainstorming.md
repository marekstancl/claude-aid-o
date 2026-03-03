---
sidebar_position: 5
title: "Brainstorming"
description: "Interactive design exploration skill: 8-step flow with structured questioning, approach alternatives, and plan document generation."
---

# Brainstorming

The brainstorming skill governs how AID conducts interactive design sessions with the PM. It defines the questioning protocol, approach exploration, incremental design validation, and plan document generation. The output is a validated plan document ready for EPIC creation.

## Purpose

Unstructured brainstorming produces vague output that is difficult to execute. This skill imposes a structured conversation flow: shared understanding before solution design, genuine alternatives with tradeoffs, incremental validation at every stage, and concrete artifacts (plan document) rather than just notes.

## When Used

- Invoked by the `/aid-brainstorm` command
- Applied for new features, architectural decisions, or complex tasks before committing to an implementation approach

## Key Principles

1. **Detail by Default** -- field names, endpoint paths, error codes, data types, file structures. PM should never say "add more detail."
2. **Explore Alternatives** -- always 2-3 options with genuine tradeoffs, effort (S/M/L), risk, and a clear recommendation.
3. **Incremental Validation** -- validate at every stage: questions, approach selection, section-by-section review, final approval. Never write files without PM approval.
4. **YAGNI** -- simplest solution that meets requirements. Complexity is a cost.
5. **PM Attention is the Bottleneck** -- one question at a time, multiple choice over open-ended.

## Session Flow (8 Steps)

1. **Read project context** -- project profile, input files
2. **Initial Analysis** -- 5-8 line structured analysis before any questions: understanding, dimensions, challenges, what needs clarification. Wait for PM confirmation.
3. **Questions** (3-7) -- one at a time, multiple choice with recommendation. Cover scope, users, constraints, patterns, scale.
4. **Approach Proposals** -- 2-3 genuinely different approaches with pros/cons/effort/risk. Hard gate: minimum 2 approaches.
5. **Section-by-Section Design** -- present each design section for PM approval. Track status: approved/pending/modified.
6. **Final Approval** -- summary with all section statuses.
7. **PM Approval to Write** -- explicit approval before writing any files.
8. **Delegate to plan-writing skill** -- plan-writing handles document structure, quality gates, forbidden phrase detection, and completeness verification.

## Language Handling

- **Conversation:** follows PM's language (auto-detected)
- **Documents:** follows configured `document_language` from `.aid-o/03-config/language.yaml`
- If they differ, mention once at the start

## Aborting and Re-opening

- **Abort before Step 8:** no files created
- **Re-open:** load existing plan, return to Step 3 with retained context. New answers ADD, never overwrite approved sections.

## Output

Plan document written to `.aid-o/01-plans/P-NNN-topic.md`. EPIC creation is a separate step via `/aid-plan-epic`, which runs `aid-auto-pipeline.sh`.

## Related

- [Planner](./planner) -- EPIC to plan.json conversion
- [Run Management](./run-management) -- lifecycle integration
- [Pipeline](./pipeline) -- execution after planning
