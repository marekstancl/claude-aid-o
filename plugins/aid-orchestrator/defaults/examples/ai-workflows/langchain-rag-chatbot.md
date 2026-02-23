---
type: example
archetype: "rag-chatbot"
frameworks: [langchain, chromadb, fastapi, streamlit]
complexity: medium
description: "RAG chatbot with document ingestion, vector store, LCEL retrieval chain, and streaming UI"
platforms: [langchain]
ui: streamlit
---

# Example EPIC: LangChain RAG Chatbot

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building a knowledge base Q&A system over static or semi-static documents (PDFs, markdown, web pages)
- Chatbot needs to answer questions with source citations from retrieved context
- You want multi-turn conversation memory with history-aware retrieval
- Latency of 1-5s per query is acceptable and SSE streaming provides progressive response display
- Team prefers code-first Python over visual workflow builders

### When NOT to use
- Data changes in real-time requiring sub-second freshness (use streaming + live search)
- Questions require complex multi-hop reasoning across many documents (use LangGraph agentic RAG instead)
- You need sub-500ms responses (vector search + LLM chain adds latency)
- Structured data queries where SQL or graph DBs are more appropriate
- Non-technical team needs to modify RAG pipeline without code changes (use LangFlow)

Tech stack: LangChain 0.3+ with LCEL, ChromaDB 0.5+, FastAPI 0.115+, Streamlit 1.38+, OpenAI GPT-4o or Ollama.
Greenfield: new `{backend_dir}/rag/` module. No prior chatbot code assumed.
Pattern: LCEL chain composition (`retriever | prompt | llm | parser`), `create_retrieval_chain` + `create_stuff_documents_chain`, `RunnableWithMessageHistory` for session memory, SSE streaming via FastAPI `StreamingResponse`.

## Goal

When complete, users can upload documents via API or Streamlit UI. Documents are chunked
with `RecursiveCharacterTextSplitter`, embedded with `text-embedding-3-small`, and stored
in ChromaDB. A retrieval endpoint uses `create_history_aware_retriever` to rewrite questions
considering chat history before retrieval, then generates answers via an LCEL chain with SSE
streaming. Conversation history is persisted per session using `RedisChatMessageHistory`.

## Scope

### Allowed files/paths
- `{backend_dir}/rag/` (new module)
  - `{backend_dir}/rag/ingestor.py` — document loading (PyPDFLoader, TextLoader, WebBaseLoader), RecursiveCharacterTextSplitter, embedding pipeline
  - `{backend_dir}/rag/retriever.py` — ChromaDB client, history-aware retriever with create_history_aware_retriever
  - `{backend_dir}/rag/chain.py` — LCEL chain: create_stuff_documents_chain + create_retrieval_chain, ChatPromptTemplate with {context} and {input}
  - `{backend_dir}/rag/memory.py` — RedisChatMessageHistory with TTL, RunnableWithMessageHistory wrapper
  - `{backend_dir}/rag/routes.py` — FastAPI router: POST /ingest, GET /chat (SSE), DELETE /session
  - `{backend_dir}/rag/schemas.py` — Pydantic request/response models
- `{frontend_dir}/` — Streamlit chat UI with st.chat_input + st.chat_message + st.write_stream
- `{backend_dir}/tests/test_rag/`
- `{project_root}/docs/api/rag.md`
- `{project_root}/docker-compose.yml`

### Forbidden zones
- `{backend_dir}/core/` (shared infrastructure -- import but do not modify)
- `{backend_dir}/auth/` (authentication module -- use existing middleware)
- `{project_root}/alembic/` (no DB migrations needed for ChromaDB)

## Artifacts

- endpoint: POST /api/v1/rag/ingest (upload + process documents, returns 202 with job_id)
- endpoint: GET /api/v1/rag/chat (SSE streaming chat with retrieval, requires session_id)
- endpoint: DELETE /api/v1/rag/session/{session_id} (clear conversation memory)
- model: ChromaDB collection per tenant/project
- config: `.env` keys -- CHROMA_HOST, CHROMA_PORT, OPENAI_API_KEY, EMBED_MODEL, LLM_MODEL, CHUNK_SIZE, CHUNK_OVERLAP, REDIS_URL
- doc: `docs/api/rag.md`, `CHANGELOG.md`

## Constraints

- Tenant-safe: yes (ChromaDB collection scoped by tenant_id metadata filter)
- Audit trail: no (chat logs optional, not required)
- Structured outputs: yes (streaming SSE chunks + final JSON summary with source citations)
- Budget: $20 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- docs_updated

## Acceptance Criteria

- [ ] [backend] POST /api/v1/rag/ingest accepts PDF, markdown, and TXT files, returns 202 with job_id
- [ ] [backend] Ingestor uses RecursiveCharacterTextSplitter with configurable chunk_size (default 1000) and chunk_overlap (default 100)
- [ ] [backend] ChromaDB collection contains embeddings within 30s of ingest for <10MB file
- [ ] [backend] GET /api/v1/rag/chat uses create_history_aware_retriever to rewrite questions considering chat history before retrieval
- [ ] [backend] Chat endpoint streams SSE events with role=assistant and includes source citation metadata (filename, page number)
- [ ] [backend] Multi-turn: second question in same session_id has access to prior context via RedisChatMessageHistory
- [ ] [frontend] Streamlit UI displays streaming responses using st.write_stream and shows source documents in expandable section
- [ ] [qa] pytest covers ingestor chunking logic with 3 fixture documents (PDF, MD, TXT) using in-memory ChromaDB client
- [ ] [qa] Integration test: ingest -> query returns at least 1 source citation
- [ ] [docs] docs/api/rag.md documents all 3 endpoints with request/response examples

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design ingestion pipeline + LCEL retrieval chain architecture + OpenAPI contracts for /ingest and /chat | — | — |
| 2 | backend | Implement document ingestor: PyPDFLoader/TextLoader, RecursiveCharacterTextSplitter (chunk_size=1000, overlap=100), embed with text-embedding-3-small, store in ChromaDB | 1 | A |
| 3 | backend | Implement LCEL retrieval chain: create_history_aware_retriever + create_stuff_documents_chain + create_retrieval_chain with ChatPromptTemplate | 1 | A |
| 4 | backend | Implement conversation memory: RedisChatMessageHistory with TTL, RunnableWithMessageHistory wrapper, DELETE session endpoint | 3 | — |
| 5 | backend | Implement FastAPI routes: POST /ingest (background task), GET /chat (SSE StreamingResponse with text/event-stream), error handling | 2, 4 | — |
| 6 | frontend | Build Streamlit chat UI: st.chat_input, st.chat_message, st.write_stream for streaming, file uploader for document ingestion | 5 | B |
| 7 | qa | Write pytest suite: unit tests for chunking, integration tests for ingest->query flow, in-memory ChromaDB + FakeChatModel | 5 | B |
| 8 | docs | Write API reference (docs/api/rag.md) + deployment guide (env vars, ChromaDB setup, model selection) | 7 | — |

## Docker Compose

```yaml
version: "3.9"

services:
  chroma:
    image: chromadb/chroma:latest
    ports:
      - "8000:8000"
    volumes:
      - chroma_data:/chroma/chroma
    environment:
      - CHROMA_SERVER_AUTH_CREDENTIALS_PROVIDER=token
      - CHROMA_SERVER_AUTH_TOKEN_TRANSPORT_HEADER=X-Chroma-Token
      - CHROMA_SERVER_AUTH_CREDENTIALS=${CHROMA_TOKEN:-secret-token}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/heartbeat"]
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
      chroma:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - CHROMA_HOST=chroma
      - CHROMA_PORT=8000
      - CHROMA_TOKEN=${CHROMA_TOKEN:-secret-token}
      - REDIS_URL=redis://redis:6379
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - EMBED_MODEL=text-embedding-3-small
      - LLM_MODEL=gpt-4o
      - CHUNK_SIZE=1000
      - CHUNK_OVERLAP=100
      - LANGCHAIN_TRACING_V2=${LANGCHAIN_TRACING_V2:-false}
      - LANGCHAIN_API_KEY=${LANGCHAIN_API_KEY:-}
    volumes:
      - ./app:/app
    command: uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload

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
    command: streamlit run streamlit_app/chat.py --server.port 8501 --server.address 0.0.0.0

volumes:
  chroma_data:
  redis_data:
```

## Notes

- **Advanced RAG techniques:** For improved retrieval quality, consider multi-query retrieval (generate 3-5 reformulations), HyDE (Hypothetical Document Embeddings), or RAPTOR (hierarchical clustering). These are documented in langchain-ai/rag-from-scratch.
- **Evaluation:** Use LangSmith evaluators for retrieval quality (context relevance, precision, recall) and generation quality (faithfulness, answer relevance). Enable with `LANGCHAIN_TRACING_V2=true`.
- **Agentic RAG:** If the chatbot needs to handle complex multi-hop questions, self-correct on irrelevant retrieval, or fall back to web search, consider upgrading to LangGraph agentic RAG (CRAG pattern) instead of pipeline RAG.
- **Embedding model:** `text-embedding-3-small` offers the best cost/quality balance. Use `text-embedding-3-large` (3072 dimensions) for high-stakes retrieval where accuracy is critical.
- **Alternative vector stores:** Swap ChromaDB for Qdrant (`langchain_qdrant.QdrantVectorStore`) or PostgreSQL pgvector for unified relational + vector storage.
