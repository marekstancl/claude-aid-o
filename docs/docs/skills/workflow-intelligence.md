---
sidebar_position: 22
title: "Workflow Intelligence"
description: "Platform detection for AI workflow and agent projects, domain-specific brainstorming questions, platform recommendations, UI requirement derivation, and Docker architecture templates."
---

# Workflow Intelligence

When a brainstorming session involves an AI workflow, agent system, or automation pipeline, standard software questions are insufficient. Workflow intelligence adds domain-specific questions and guidance to the brainstorming flow: detecting the target platform, asking about agent design and state management, recommending between LangChain/LangGraph and N8N/LangFlow, deriving UI requirements from the workflow design, and generating Docker Compose architecture templates.

## Purpose

Building an AI workflow or multi-agent system involves decisions that do not arise in standard web development: which orchestration framework to use, how to handle state between agent steps, whether to use a graph-based or chain-based execution model, and what UI (if any) is needed for monitoring or control. Without specialized guidance, these decisions are made ad-hoc. Workflow intelligence makes them explicit and deliberate.

## When Used

- Activated automatically during `/aid-brainstorm` when Platform Detection identifies a workflow or agent project
- Supplements the standard brainstorming flow with 7 domain-specific question inserts (WF1-WF7)
- Does not replace or reorder the standard brainstorming flow — only adds to it
- Knowledge acquisition retrieves relevant platform documentation (LangChain, LangGraph, N8N, LangFlow) when configured

## Key Concepts

### Platform Detection

Detection runs at the start of Step 2 (Questions) in the brainstorming flow, before the first question is asked. It checks three sources in priority order:

1. **Explicit PM mention** — PM names a platform during conversation (highest priority, exact match)
2. **Project profile** — `project-profile.yaml` frameworks list contains a known platform name
3. **Conversation keywords** — topic description contains platform-indicative keywords:
   - `langchain`, `chain`, `LLM chain`, `runnable` → LangChain
   - `langgraph`, `graph`, `state machine`, `conditional edges` → LangGraph
   - `n8n`, `workflow nodes` → N8N
   - `langflow`, `flow builder` → LangFlow
   - `agent`, `chatbot`, `RAG`, `automation`, `AI workflow`, `multi-agent`, `tool-calling` → generic-workflow (platform TBD)

If no match from any source, workflow intelligence does not activate.

### Seven Workflow Questions (WF1-WF7)

These insert into the standard brainstorming question flow as domain-specific follow-ups:

- **WF1**: What is the primary workflow pattern? (sequential chain, parallel branches, conditional routing, iterative loop, human-in-the-loop)
- **WF2**: What are the key agents or steps, and what does each one do?
- **WF3**: How is state managed between steps? (memory, shared context, database, none)
- **WF4**: What are the input/output contracts for each agent? (data formats, schemas)
- **WF5**: What error handling is needed? (retries, fallbacks, circuit breakers)
- **WF6**: What are the performance requirements? (latency, throughput, concurrency)
- **WF7** (generic-workflow only): Which platform is preferred? (present LangGraph vs LangChain vs N8N vs LangFlow with tradeoffs and recommendation)

### Platform Recommendation

For `generic-workflow` (no specific platform detected), workflow intelligence recommends a platform based on the PM's answers to WF1-WF7:

- **LangGraph** — recommended for: complex agent systems with conditional routing, state machines, human-in-the-loop, iterative refinement
- **LangChain** — recommended for: linear chains, RAG pipelines, simple tool-calling agents
- **N8N** — recommended for: visual workflow building, non-developer teams, integration-heavy (API calls, webhooks)
- **LangFlow** — recommended for: rapid prototyping, visual LLM pipeline design

The recommendation includes rationale, tradeoffs, and a pointer to the relevant documentation.

### UI Derivation

Workflow intelligence derives UI requirements from the workflow design — the PM should not need to explicitly specify "I need a monitoring dashboard." Given the workflow structure, the skill proposes:

- **Monitoring UI** — if the workflow is long-running or has multiple parallel agents
- **Control UI** — if the workflow has human-in-the-loop steps
- **Debug UI** — if the workflow involves complex state that needs inspection
- **No UI needed** — if the workflow is fully automated and headless

Each UI type maps to a framework recommendation (React + Shadcn for control UIs, simple logging for headless).

### Docker Compose Template

For projects that need containerization, workflow intelligence generates a Docker Compose template based on the detected platform and derived architecture:

- LangGraph/LangChain: Python service + Redis (state) + optional Postgres
- N8N: N8N service + Postgres
- LangFlow: LangFlow service + Postgres + optional Redis

The template is included in the EPIC draft as a starting architecture.

## How It Works

When `workflow_detected == true`, workflow intelligence informs the PM in a single non-blocking line and inserts WF1-WF6 questions into the standard brainstorming flow at Step 2. If the platform is `generic-workflow`, WF7 is added to recommend a platform.

The PM's answers to workflow questions feed into the approach proposals (Step 3): each approach option reflects a different implementation strategy for the detected platform. The UI derivation and Docker template are folded into the plan document and EPIC draft.

All workflow intelligence output is integrated into the standard brainstorming artifacts — there is no separate workflow output. The plan and EPIC draft simply contain richer, more domain-specific content.

## Configuration

No specific configuration. Workflow intelligence activates automatically based on detection. Platform documentation is acquired via `knowledge-acquisition` when `knowledge.enabled: true` in `memory-config.yaml`.

## Related

- [Brainstorming](../skills/brainstorming)
- [Knowledge Acquisition](../skills/knowledge-acquisition)
- [Memory MCP](../skills/memory-mcp)
