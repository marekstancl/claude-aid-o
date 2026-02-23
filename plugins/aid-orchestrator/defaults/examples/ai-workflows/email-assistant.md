---
type: example
archetype: "email-assistant"
frameworks: [langgraph, langchain, fastapi]
complexity: medium
description: "AI email assistant with classification, draft generation, and human-in-the-loop approval using LangGraph"
platforms: [langgraph]
ui: none
---

# Example EPIC: AI Email Assistant

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Automating email triage: classify incoming emails by intent and priority
- Generating draft responses that require human approval before sending
- Building an email workflow with human-in-the-loop using LangGraph interrupt()
- Need stateful, multi-step processing with persistence across failures

### When NOT to use
- Simple email forwarding or filtering (use traditional rules/filters)
- No human review needed (fully autonomous sending is risky for production)
- Email volume exceeds LLM rate limits (>1000/hour, use batch processing)
- Single-step classification only (a simple chain suffices, no graph needed)

Tech stack: LangGraph + LangChain + FastAPI + PostgresSaver for persistence.
Greenfield: new `{backend_dir}/email_assistant/` module.
Pattern: LangGraph StateGraph with interrupt() for human-in-the-loop approval.

## Goal

When complete, incoming emails are classified by intent (inquiry, complaint,
request, spam), a draft response is generated, and the draft is presented for
human approval via interrupt(). Upon approval, the response is sent. The full
workflow is persistent via PostgresSaver, surviving process restarts.

## Scope

### Allowed files/paths
- `{backend_dir}/email_assistant/`
  - `{backend_dir}/email_assistant/graph.py` — LangGraph StateGraph definition
  - `{backend_dir}/email_assistant/nodes.py` — classify, draft, send nodes
  - `{backend_dir}/email_assistant/state.py` — TypedDict state schema
  - `{backend_dir}/email_assistant/routes.py` — FastAPI endpoints
- `{backend_dir}/tests/test_email_assistant/`
- `{project_root}/docs/`

### Forbidden zones
- `{backend_dir}/core/` (import only)
- External email provider SDKs (abstract behind interface)

## Artifacts

- endpoint: POST /api/v1/email/process (submit email for processing)
- endpoint: POST /api/v1/email/approve/{thread_id} (approve/reject draft)
- endpoint: GET /api/v1/email/pending (list emails awaiting approval)
- graph: LangGraph StateGraph (classify → draft → human_review → send)

## Constraints

- Tenant-safe: yes (thread_id scoped per user)
- Budget: $12 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] Email classification returns one of: inquiry, complaint, request, spam
- [ ] [backend] Draft generation produces contextually appropriate response
- [ ] [backend] interrupt() pauses workflow and persists state via PostgresSaver
- [ ] [backend] Resume with Command(resume={"approved": True}) sends the email
- [ ] [backend] Resume with approved=False returns to draft node with feedback
- [ ] [backend] GET /pending returns list of emails awaiting human approval
- [ ] [qa] Unit tests for classification node with mock LLM responses
- [ ] [qa] Integration test: submit email → approve → verify send called

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design StateGraph: state schema, node contracts, interrupt placement, persistence strategy | — | — |
| 2 | backend | Implement nodes: classify_email, draft_response, human_review (interrupt), send_email | 1 | — |
| 3 | backend | Implement LangGraph StateGraph with edges and PostgresSaver checkpointer | 2 | — |
| 4 | backend | Implement FastAPI endpoints: process, approve, pending | 3 | — |
| 5 | qa | Write tests for classification, draft generation, and interrupt/resume flow | 4 | — |
| 6 | docs | API docs + workflow diagram | 5 | — |

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: email_assistant
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: email_assistant
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U email_assistant"]
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
      DATABASE_URL: postgresql://email_assistant:${POSTGRES_PASSWORD}@postgres:5432/email_assistant
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      LANGSMITH_API_KEY: ${LANGSMITH_API_KEY:-}
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
```

## Notes

- LangGraph interrupt() requires a checkpointer — PostgresSaver for production
- Resume paused workflows: `graph.invoke(Command(resume={"approved": True}), config)`
- Always validate human input before resuming; store feedback in state for auditability
- The interrupt value is serialized to checkpoint store, surviving process restarts
- Use LangGraph Studio for visual debugging of the email workflow during development
