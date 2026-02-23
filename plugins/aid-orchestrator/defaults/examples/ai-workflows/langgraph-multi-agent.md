---
type: example
archetype: "multi-agent-supervisor"
frameworks: [langgraph, langchain, fastapi]
complexity: high
description: "Multi-agent supervisor system with specialized workers and tool-based handoffs using LangGraph"
platforms: [langgraph]
ui: streamlit
---

# Example EPIC: LangGraph Multi-Agent Supervisor System

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Complex workflows requiring multiple specialized agents (research, coding, data analysis, writing)
- Hierarchical decision-making where a central supervisor routes tasks to the right specialist
- Need orchestrated handoffs between agents with shared state and conversation memory
- Building systems like customer support triage, research assistants, or multi-domain Q&A
- Team wants checkpointed execution with time-travel debugging via LangGraph Studio

### When NOT to use
- Simple single-purpose chatbot or Q&A (use basic LangChain RAG chain instead)
- Peer-to-peer agent collaboration without central oversight (use LangGraph Swarm pattern)
- Visual/low-code team that cannot maintain Python agent code (use N8N or LangFlow)
- Latency-critical applications where multi-agent overhead is unacceptable (<1s response requirement)
- Budget-constrained projects where multiple LLM calls per query is too expensive

Tech stack: LangGraph 0.3+, langgraph-supervisor-py, LangChain 0.3+, FastAPI 0.115+, PostgreSQL 16 (checkpointer), Redis 7 (state store).
Greenfield: new `{project_root}/agents/` module. No prior agent code assumed.
Pattern: `create_supervisor` with `create_react_agent` workers, `handoff_to_{agent}` auto-generated tools, `AsyncPostgresSaver` checkpointer, `stream_mode="updates"` for step-by-step streaming.

## Goal

When complete, a supervisor agent orchestrates specialized worker agents (research, code, data analysis)
via tool-based handoffs. The supervisor decides which worker to delegate to based on the user query.
Workers use `create_react_agent` with domain-specific tools (Tavily search, code execution sandbox,
pandas DataFrame analysis). State is checkpointed with `AsyncPostgresSaver` for fault tolerance and
time-travel debugging. The system exposes a FastAPI streaming endpoint and optional Streamlit UI.

## Scope

### Allowed files/paths
- `{project_root}/agents/` (new module)
  - `{project_root}/agents/supervisor.py` — create_supervisor with worker registration and routing prompt
  - `{project_root}/agents/workers/research.py` — create_react_agent with Tavily search + web scraping tools
  - `{project_root}/agents/workers/coder.py` — create_react_agent with code execution sandbox tool
  - `{project_root}/agents/workers/analyst.py` — create_react_agent with pandas/SQL analysis tools
  - `{project_root}/agents/tools/` — custom tool definitions (search, execute_code, query_db)
  - `{project_root}/agents/state.py` — shared state schema (MessagesState extension)
  - `{project_root}/agents/config.py` — agent configuration, model selection, tool registration
- `{project_root}/api/routes/agents.py` — FastAPI routes for agent invocation
- `{project_root}/ui/multi_agent.py` — Streamlit multi-agent chat UI
- `{project_root}/tests/test_agents/`
- `{project_root}/langgraph.json` — deployment manifest
- `{project_root}/docker-compose.yml`

### Forbidden zones
- `{project_root}/core/` (shared infrastructure -- import only)
- `{project_root}/auth/` (authentication -- use existing middleware)
- External LLM provider configurations (use env vars only)

## Artifacts

- endpoint: POST /api/v1/agents/invoke (synchronous multi-agent invocation)
- endpoint: POST /api/v1/agents/stream (SSE streaming with step-by-step updates)
- endpoint: GET /api/v1/agents/threads/{thread_id}/history (execution history for time-travel)
- model: PostgreSQL checkpoints table for state persistence
- config: `.env` keys -- OPENAI_API_KEY, TAVILY_API_KEY, DATABASE_URL, REDIS_URL, LANGSMITH_API_KEY
- manifest: `langgraph.json` for LangGraph Platform deployment

## Constraints

- Tenant-safe: yes (thread_id scoped per user/session)
- Audit trail: yes (full execution trace via LangSmith + checkpointer history)
- Budget: $50 max LLM cost (multiple agents = higher token usage)
- Max iterations: 25 per supervisor invocation (prevent infinite loops)

## DoD Gates

- tests_pass
- lint_pass
- type_check
- docs_updated

## Acceptance Criteria

- [ ] [backend] Supervisor agent routes queries to correct worker based on intent (research -> research_agent, code -> coder_agent, data -> analyst_agent)
- [ ] [backend] Workers use create_react_agent with domain-specific tools and return results to supervisor via handoff mechanism
- [ ] [backend] Handoff tools are auto-generated with naming pattern handoff_to_{agent_name}
- [ ] [backend] State persists across invocations via AsyncPostgresSaver with thread_id-based isolation
- [ ] [backend] Streaming endpoint emits per-node state updates (stream_mode="updates") showing supervisor -> worker -> supervisor flow
- [ ] [backend] Max iterations (25) prevents infinite supervisor-worker loops
- [ ] [backend] Hierarchical nesting supported: research_team supervisor can be a worker of top-level supervisor
- [ ] [qa] Unit tests mock LLM with FakeListChatModel and verify routing logic
- [ ] [qa] Integration test: invoke supervisor with research query, verify research_agent tool was called
- [ ] [docs] Architecture diagram showing supervisor-worker topology and handoff flow

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design multi-agent topology: supervisor prompt, worker specializations, tool inventory, state schema, handoff protocol | — | — |
| 2 | backend | Implement worker agents: create_react_agent for research (Tavily), coder (sandbox), analyst (pandas) with domain-specific system prompts and tools | 1 | A |
| 3 | backend | Implement supervisor: create_supervisor with worker list, routing prompt, message_history_mode="last_message", max_iterations=25 | 1 | A |
| 4 | backend | Implement persistence: AsyncPostgresSaver checkpointer, InMemoryStore for cross-thread memory, langgraph.json manifest | 2, 3 | — |
| 5 | backend | Implement FastAPI routes: /invoke (sync), /stream (SSE with stream_mode="updates"), /threads/{id}/history (state replay) | 4 | — |
| 6 | frontend | Build Streamlit UI: multi-agent chat with agent indicator badges, step-by-step execution visualization | 5 | B |
| 7 | qa | Write test suite: mock workers with FakeListChatModel, verify routing, test handoff chain, integration with InMemorySaver | 5 | B |
| 8 | docs | Write architecture docs: topology diagram, agent capability matrix, deployment guide, LangGraph Studio setup | 7 | — |

## Docker Compose

```yaml
version: "3.9"

services:
  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=langgraph
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-langgraph_secret}
      - POSTGRES_DB=langgraph
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U langgraph"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - DATABASE_URL=postgresql://langgraph:${POSTGRES_PASSWORD:-langgraph_secret}@postgres:5432/langgraph
      - REDIS_URL=redis://redis:6379
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - TAVILY_API_KEY=${TAVILY_API_KEY}
      - LANGCHAIN_TRACING_V2=${LANGCHAIN_TRACING_V2:-false}
      - LANGCHAIN_API_KEY=${LANGCHAIN_API_KEY:-}
      - LANGCHAIN_PROJECT=multi-agent-supervisor
    command: uvicorn app.main:app --host 0.0.0.0 --port 8080

  ui:
    build:
      context: .
      dockerfile: Dockerfile.streamlit
    ports:
      - "8501:8501"
    depends_on:
      - api
    environment:
      - API_URL=http://api:8080
    command: streamlit run ui/multi_agent.py --server.port 8501 --server.address 0.0.0.0

volumes:
  postgres_data:
  redis_data:
```

## Notes

- **Supervisor vs Swarm:** Use supervisor pattern when you need centralized oversight and hierarchical delegation. Use swarm pattern (`create_swarm`) for peer-to-peer handoffs where agents transfer directly to each other without central coordination (e.g., customer support disambiguation -> service agent flows).
- **Message history modes:** `full_history` passes all messages to workers (more context, higher cost); `last_message` passes only the final response back (cheaper, less context). Start with `last_message` and upgrade if workers need more context.
- **Hierarchical nesting:** For complex organizations, nest supervisors: `research_team = create_supervisor([web_agent, paper_agent]).compile(); top_supervisor = create_supervisor([research_team, writing_team]).compile()`.
- **LangGraph Studio:** Run `langgraph dev` locally with the `langgraph.json` manifest for visual graph debugging with time-travel. Requires `LANGSMITH_API_KEY`.
- **A2A Protocol:** For cross-framework agent interop, wrap LangGraph agents as A2A HTTP endpoints to communicate with agents built in CrewAI, AutoGen, or Vertex AI Agents.
- **Testing:** Use `FakeListChatModel` for deterministic routing tests. Save `graph.get_graph().draw_mermaid()` output as a snapshot test to detect unexpected topology changes.
