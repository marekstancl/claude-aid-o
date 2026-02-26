---
sidebar_position: 7
title: "Brainstorming"
description: "Interactive design and planning skill that guides the PM through structured questioning, approach exploration, and incremental validation to produce a plan document and EPIC draft."
---

# Brainstorming

The brainstorming skill governs how AID conducts interactive design sessions with the PM. It defines the questioning protocol, approach exploration format, incremental design validation, and automatic EPIC draft creation. The output is a validated plan document and an EPIC draft ready for execution.

## Purpose

Unstructured brainstorming produces vague output that becomes difficult to execute. This skill imposes a structured conversation flow that ensures shared understanding before solution design, explores alternatives with real tradeoffs, validates the design incrementally rather than presenting a fait accompli, and produces concrete artifacts (plan and EPIC) rather than just notes.

## When Used

- Invoked by the `/aid-brainstorm` command
- Applied whenever the PM wants to explore a new feature, architectural decision, or complex task before committing to an implementation approach
- Augmented with knowledge context when `knowledge-acquisition` is configured — relevant documentation, patterns, and past project lessons inform both questions and approach proposals

## Key Concepts

### Five Core Principles

**Detail by Default** — brainstorming produces comprehensive output without the PM having to ask for it. Specific field names, endpoint paths, error codes, file structures, and integration points are included proactively. PM can always say "simplify"; they should never need to say "add more detail."

**Explore Alternatives** — never present a single approach. Every proposal includes 2-3 genuine options with real tradeoffs, effort estimates (S/M/L), risk assessments, and a clear recommendation with reasoning.

**Incremental Validation** — the design is validated with PM at every stage: questions validate understanding, approach selection validates direction, section-by-section review validates details, and final approval validates the whole. No files are written without explicit PM approval.

**YAGNI** — propose the simplest solution that meets stated requirements. No microservices for single-service problems, no caching layers or message queues unless requirements demand them. Complexity is a cost that must be justified.

**PM Attention is the Bottleneck** — one question at a time, multiple choice over open-ended, short summaries before detailed sections, clear action items. Accept brief answers and infer reasonable defaults.

### Session Flow

1. **Initial Analysis** — before any questions, present a structured 5-8 line analysis: what was understood from the topic, key dimensions, potential challenges, and what needs clarification. Wait for PM confirmation before proceeding.

2. **Questions** (3-5 max) — ask one question at a time, framed as multiple choice. Each question informs the approach proposals. When workflow intelligence detects an AI/agent project, domain-specific questions (WF1-WF7) are inserted here.

3. **Approach Proposals** — present 2-3 approaches with tradeoffs. Each has a summary, pros/cons, effort estimate, and risk level. Include a clear recommendation.

4. **Section-by-Section Design** — after PM selects an approach, design each major section interactively. Review each section with PM before proceeding.

5. **Plan Document Generation** — write the plan to `.aid-o/01-plans/P-{ID}-{topic}.md` with full detail: objectives, scope, technical approach, file structure, integration points, acceptance criteria.

6. **EPIC Draft Generation** — automatically generate an EPIC draft at `.aid-o/02-epics/E-{ID}-{topic}.md` with run breakdown derived from the plan.

7. **Brainstorming-End Protocol** — present a summary and ask PM: "Plan or Run?" (use the plan as reference for a single run, or execute as an EPIC?).

## How It Works

The brainstorming skill is not just a conversation guide — it produces two concrete artifacts:

**Plan document** captures the design decision: objectives, approach, file structure, integration points, acceptance criteria, and open questions. It is the record of what was decided and why.

**EPIC draft** translates the plan into an executable specification: run breakdown, step objectives, dependencies, acceptance criteria per step, and quality gate configuration.

When knowledge acquisition is enabled, the session begins by searching Qdrant for relevant documentation, patterns from past projects, and applicable lessons. These results appear as a "KNOWLEDGE CONTEXT" block that informs the initial analysis and approach proposals.

## Configuration

Brainstorming produces output in:
- `.aid-o/01-plans/` — plan documents
- `.aid-o/02-epics/` — EPIC drafts

Knowledge augmentation is controlled by `.aid-o/03-config/policies/memory-config.yaml` with `knowledge.enabled: true`.

## Related

- [Planner](../skills/planner)
- [Run Management](../skills/run-management)
- [Workflow Intelligence](../skills/workflow-intelligence)
- [Knowledge Acquisition](../skills/knowledge-acquisition)
