---
type: example
archetype: "content-generator"
frameworks: [langgraph, langchain, fastapi]
complexity: medium
description: "AI content generation pipeline with multi-step drafting, review, and refinement using LangGraph"
platforms: [langgraph]
ui: none
---

# Example EPIC: AI Content Generator

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Generating marketing copy, blog posts, or documentation with iterative refinement
- Need a multi-step workflow: outline → draft → review → refine → final
- Self-correction loop: LLM reviews its own output and improves quality
- Human-in-the-loop approval before publishing

### When NOT to use
- Simple one-shot text generation (a single LLM call suffices)
- Real-time chat responses (use a chatbot pattern instead)
- Content requires domain expertise beyond the LLM's knowledge (add RAG)
- High-volume content generation >100 pieces/hour (batch with queue)

Tech stack: LangGraph + LangChain + FastAPI + PostgresSaver.
Greenfield: new `{backend_dir}/content_generator/` module.
Pattern: LangGraph self-correcting loop — generate → review → refine (max 3 iterations).

## Goal

When complete, the API accepts content briefs (topic, tone, length, audience),
generates an outline, drafts content, runs a self-review loop for quality
improvement, and presents the final draft for human approval via interrupt().
The workflow tracks iteration count and stops after max_iterations.

## Scope

### Allowed files/paths
- `{backend_dir}/content_generator/`
  - `{backend_dir}/content_generator/graph.py` — LangGraph StateGraph
  - `{backend_dir}/content_generator/nodes.py` — outline, draft, review, refine nodes
  - `{backend_dir}/content_generator/state.py` — TypedDict state schema
  - `{backend_dir}/content_generator/routes.py` — FastAPI endpoints
- `{backend_dir}/tests/test_content_generator/`

### Forbidden zones
- `{backend_dir}/core/` (import only)

## Artifacts

- endpoint: POST /api/v1/content/generate (submit brief, starts workflow)
- endpoint: POST /api/v1/content/approve/{thread_id} (approve/request changes)
- endpoint: GET /api/v1/content/status/{thread_id} (check generation status)
- graph: LangGraph StateGraph (outline → draft → review → refine → human_approval)

## Constraints

- Tenant-safe: yes (thread_id per user)
- Budget: $15 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] Accepts content brief with: topic, tone, target_length, audience
- [ ] [backend] Generates outline before full draft (visible in state)
- [ ] [backend] Self-review loop runs up to max_iterations=3, improving quality each pass
- [ ] [backend] Review node produces quality_score; loop exits when score >= 0.8
- [ ] [backend] interrupt() pauses for human approval before marking as final
- [ ] [backend] State persists via PostgresSaver — survives process restarts
- [ ] [qa] Unit tests for each node with mock LLM responses
- [ ] [qa] Integration test: submit brief → auto-refine → approve → get final content

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design graph: state schema with iterations counter, conditional routing for review loop, interrupt placement | — | — |
| 2 | backend | Implement nodes: generate_outline, write_draft, review_content, refine_content, human_approval | 1 | — |
| 3 | backend | Implement LangGraph StateGraph with conditional edges and PostgresSaver | 2 | — |
| 4 | backend | Implement FastAPI endpoints | 3 | — |
| 5 | qa | Write tests | 4 | — |
| 6 | docs | API docs + workflow diagram | 5 | — |

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: content
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: content
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U content"]
      interval: 5s
      timeout: 5s
      retries: 5

  api:
    build:
      context: ./{backend_dir}
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      DATABASE_URL: postgresql://content:${POSTGRES_PASSWORD}@postgres:5432/content
      OPENAI_API_KEY: ${OPENAI_API_KEY}
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
```

## Notes

- Self-correcting pattern: review node scores quality, conditional edge routes back to refine if < 0.8
- Always include max_iterations counter in state to prevent unbounded loops
- Use LangGraph Studio to visualize and debug the generation → review → refine cycle
- Nodes must be idempotent for time-travel replay — avoid side effects
- Consider different LLM models per node: cheaper model for drafting, better model for review
