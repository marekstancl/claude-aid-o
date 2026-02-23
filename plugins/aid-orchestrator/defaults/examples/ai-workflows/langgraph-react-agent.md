---
type: example
archetype: "react-agent-tool-calling"
frameworks: [langgraph, langchain, fastapi]
complexity: medium
description: "ReAct agent with tool calling, streaming, and checkpointed memory using LangGraph"
platforms: [langgraph]
ui: gradio
---

# Example EPIC: LangGraph ReAct Agent with Tool Calling

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building an autonomous agent that reasons about which tools to use and when
- Need iterative tool calling where the LLM decides whether to search, calculate, query a database, or respond directly
- Want persistent conversation memory with checkpointed state for multi-turn interactions
- Use case requires web search, API calls, code execution, or database queries as agent tools
- Team wants the standard LangGraph ReAct pattern with prebuilt `create_react_agent`

### When NOT to use
- Simple Q&A over documents without tool calling (use LangChain RAG chain instead)
- Need multiple specialized agents with handoffs (use LangGraph Supervisor or Swarm)
- Predictable, deterministic pipeline where LLM should not decide the flow (use LCEL chains)
- Extremely latency-sensitive applications where tool-calling loop overhead is unacceptable
- Non-technical team needs to modify agent behavior (use LangFlow visual agent builder)

Tech stack: LangGraph 0.3+ with `create_react_agent` prebuilt, LangChain 0.3+, FastAPI 0.115+, Gradio 5+.
Greenfield: new `{project_root}/agent/` module. No prior agent code assumed.
Pattern: `create_react_agent(llm, tools, state_modifier=system_prompt)`, two-node cycle (llm_call -> tool_node -> llm_call), `MessagesState` with `add_messages` reducer, `MemorySaver` checkpointer, `stream_mode="messages"` for token-level streaming.

## Goal

When complete, a ReAct agent alternates between LLM reasoning and tool execution in a loop.
The agent is equipped with web search (Tavily), a calculator, and a database query tool.
The LLM decides which tool to call based on the user's question, executes it, reads the
result, and either calls another tool or provides a final answer. State is checkpointed
with `MemorySaver` (dev) or `AsyncPostgresSaver` (prod) for multi-turn memory. A Gradio
ChatInterface provides the streaming UI.

## Scope

### Allowed files/paths
- `{project_root}/agent/` (new module)
  - `{project_root}/agent/graph.py` — create_react_agent setup with tools and system prompt
  - `{project_root}/agent/tools/search.py` — Tavily search tool with @tool decorator
  - `{project_root}/agent/tools/calculator.py` — math evaluation tool
  - `{project_root}/agent/tools/database.py` — SQL query tool with read-only access
  - `{project_root}/agent/state.py` — MessagesState extension if custom fields needed
  - `{project_root}/agent/config.py` — model selection, tool registration, system prompt
- `{project_root}/api/routes/agent.py` — FastAPI streaming endpoint
- `{project_root}/ui/agent_chat.py` — Gradio ChatInterface with streaming
- `{project_root}/tests/test_agent/`
- `{project_root}/langgraph.json`
- `{project_root}/docker-compose.yml`

### Forbidden zones
- `{project_root}/core/` (import only)
- `{project_root}/auth/` (use existing middleware)
- Production databases (agent SQL tool must be read-only)

## Artifacts

- endpoint: POST /api/v1/agent/stream (SSE streaming with token-level output)
- endpoint: POST /api/v1/agent/invoke (synchronous invocation)
- endpoint: GET /api/v1/agent/threads/{thread_id}/state (inspect current state)
- model: checkpointer state in PostgreSQL (prod) or in-memory (dev)
- config: `.env` keys -- OPENAI_API_KEY, TAVILY_API_KEY, DATABASE_URL, LANGSMITH_API_KEY
- manifest: `langgraph.json`

## Constraints

- Tenant-safe: yes (thread_id scoped per session)
- Audit trail: yes (LangSmith traces every tool call and LLM decision)
- Budget: $30 max LLM cost
- Max tool iterations: 10 per invocation (prevent infinite loops via should_continue routing)

## DoD Gates

- tests_pass
- lint_pass
- type_check
- docs_updated

## Acceptance Criteria

- [ ] [backend] Agent uses create_react_agent with bound tools and alternates between llm_call and tool_node
- [ ] [backend] Routing function should_continue returns "tool_node" when AIMessage has tool_calls, else END
- [ ] [backend] Tavily search tool returns web results with title, URL, and snippet
- [ ] [backend] Calculator tool safely evaluates mathematical expressions without arbitrary code execution
- [ ] [backend] Database tool executes read-only SQL queries and returns formatted results
- [ ] [backend] Streaming endpoint uses stream_mode="messages" for token-level SSE output
- [ ] [backend] Checkpointer persists state so follow-up questions in same thread_id have conversation context
- [ ] [frontend] Gradio ChatInterface displays streaming responses and handles conversation history automatically
- [ ] [qa] Unit tests use FakeListChatModel to verify tool routing (search query -> search tool, math -> calculator)
- [ ] [qa] Integration test: invoke agent with "What is the population of France?", verify Tavily tool was called

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design agent graph: tool inventory, system prompt, state schema, streaming protocol, safety guardrails | — | — |
| 2 | backend | Implement tools: Tavily search (@tool decorator), calculator (safe eval), database query (read-only SQL) | 1 | A |
| 3 | backend | Implement agent graph: create_react_agent with llm.bind_tools(tools), MessagesState, conditional should_continue edge | 1 | A |
| 4 | backend | Implement persistence: MemorySaver (dev), AsyncPostgresSaver (prod), thread_id config, langgraph.json manifest | 3 | — |
| 5 | backend | Implement FastAPI routes: /stream (SSE with stream_mode="messages"), /invoke (sync), /threads/{id}/state | 4 | — |
| 6 | frontend | Build Gradio UI: gr.ChatInterface with streaming callback, agent.astream for async token delivery | 5 | B |
| 7 | qa | Write tests: FakeListChatModel for deterministic routing, integration test with InMemorySaver, tool output validation | 5 | B |
| 8 | docs | Write docs: tool capability matrix, agent flow diagram, deployment guide, LangGraph Studio walkthrough | 7 | — |

## Docker Compose

```yaml
version: "3.9"

services:
  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=agent
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-agent_secret}
      - POSTGRES_DB=agent
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U agent"]
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
    environment:
      - DATABASE_URL=postgresql://agent:${POSTGRES_PASSWORD:-agent_secret}@postgres:5432/agent
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - TAVILY_API_KEY=${TAVILY_API_KEY}
      - LANGCHAIN_TRACING_V2=${LANGCHAIN_TRACING_V2:-false}
      - LANGCHAIN_API_KEY=${LANGCHAIN_API_KEY:-}
      - LANGCHAIN_PROJECT=react-agent
    command: uvicorn app.main:app --host 0.0.0.0 --port 8080

  ui:
    build:
      context: .
      dockerfile: Dockerfile.gradio
    ports:
      - "7860:7860"
    depends_on:
      - api
    environment:
      - API_URL=http://api:8080
    command: python ui/agent_chat.py

volumes:
  postgres_data:
```

## Notes

- **ReAct loop:** The agent alternates: LLM reasons -> decides tool -> tool executes -> LLM reads result -> decides next action or responds. The `should_continue` function checks `state["messages"][-1].tool_calls` to route between tool_node and END.
- **Streaming modes:** `stream_mode="messages"` streams individual tokens for real-time UI; `stream_mode="updates"` streams per-node state changes for debugging. Use `"messages"` for user-facing streaming, `"updates"` for development/testing.
- **Tool safety:** The calculator tool should use a sandboxed evaluator (e.g., `numexpr` or AST-based eval), never raw `eval()`. The database tool must enforce read-only access (use a read-only database user or `SET TRANSACTION READ ONLY`).
- **LangGraph Studio:** Run `langgraph dev` to visualize the ReAct loop with time-travel debugging. Step through each tool call, inspect intermediate state, and replay from any checkpoint.
- **Upgrading to multi-agent:** If the agent scope grows beyond what a single ReAct loop handles, promote it to a supervisor-worker architecture. Each current tool category (search, code, data) becomes a separate worker agent under a supervisor.
- **Prebuilt templates:** LangGraph provides `langgraph new react-agent` scaffold for quick project initialization with the standard ReAct pattern.
