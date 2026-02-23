---
type: example
archetype: "document-qa-chatbot"
frameworks: [langchain, chromadb, fastapi, streamlit]
complexity: medium
description: "Document Q&A chatbot with multi-format ingestion, vector retrieval, and streaming responses"
platforms: [langchain]
ui: streamlit
---

# Example EPIC: Document Q&A Chatbot

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building a knowledge base Q&A system over internal documents (PDFs, Word, Markdown)
- Users need natural language search over a document corpus with source citations
- Multi-format document support required (PDF, DOCX, TXT, CSV, HTML)
- Conversation memory needed for follow-up questions within a session

### When NOT to use
- Documents change in real-time (use live search or streaming ingestion)
- Need complex multi-hop reasoning across many documents (use LangGraph agents)
- Structured data queries (SQL databases are more appropriate)
- Sub-500ms latency required (vector search + LLM adds 1-5s)

Tech stack: LangChain 0.2+ + ChromaDB + FastAPI + Streamlit + OpenAI/Ollama.
Greenfield: new `{backend_dir}/docqa/` module.
Pattern: 4-stage ingestion (load → split → embed → store), LCEL retrieval chain, SSE streaming.

## Goal

When complete, users upload documents via Streamlit UI or API, which are chunked,
embedded, and stored in ChromaDB. A chat interface accepts questions, runs an LCEL
retrieval chain over relevant chunks, and streams responses with source citations.
Conversation memory is maintained per session for multi-turn context.

## Scope

### Allowed files/paths
- `{backend_dir}/docqa/`
  - `{backend_dir}/docqa/ingestor.py` — document loading with PyPDFLoader, UnstructuredLoader
  - `{backend_dir}/docqa/retriever.py` — ChromaDB client, similarity search
  - `{backend_dir}/docqa/chain.py` — LCEL chain with create_retrieval_chain
  - `{backend_dir}/docqa/memory.py` — ConversationSummaryBufferMemory per session
  - `{backend_dir}/docqa/routes.py` — FastAPI router (ingest + chat endpoints)
  - `{backend_dir}/docqa/schemas.py` — Pydantic models
- `{frontend_dir}/streamlit_app.py` — Streamlit chat UI with file upload
- `{backend_dir}/tests/test_docqa/`
- `{project_root}/docs/api/docqa.md`

### Forbidden zones
- `{backend_dir}/core/` (shared infrastructure — import only)
- `{backend_dir}/auth/` (use existing middleware)

## Artifacts

- endpoint: POST /api/v1/docqa/ingest (upload + process documents, returns 202)
- endpoint: GET /api/v1/docqa/chat (SSE streaming chat with retrieval)
- endpoint: DELETE /api/v1/docqa/session/{session_id} (clear memory)
- component: Streamlit chat interface with st.file_uploader + st.chat_message
- config: .env with CHROMA_HOST, EMBED_MODEL, LLM_MODEL, CHUNK_SIZE

## Constraints

- Tenant-safe: yes (ChromaDB collection scoped by tenant_id)
- Structured outputs: yes (SSE chunks + final JSON with sources)
- Budget: $15 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] POST /api/v1/docqa/ingest accepts PDF, DOCX, TXT, and MD files
- [ ] [backend] Ingestor uses RecursiveCharacterTextSplitter (chunk_size=1000, overlap=100)
- [ ] [backend] ChromaDB stores embeddings with metadata: source filename, page number, chunk index
- [ ] [backend] GET /api/v1/docqa/chat streams SSE events with content + source citations
- [ ] [backend] Multi-turn: follow-up questions in same session have prior context
- [ ] [frontend] Streamlit UI has file upload widget and chat interface with streaming display
- [ ] [qa] Integration test: ingest PDF → query → verify response contains relevant info
- [ ] [docs] API reference documents all endpoints with examples

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design ingestion pipeline + retrieval chain + API contracts | — | — |
| 2 | backend | Implement ingestor: multi-format loaders, text splitter, ChromaDB storage | 1 | — |
| 3 | backend | Implement LCEL retrieval chain with create_retrieval_chain + SSE streaming | 2 | — |
| 4 | backend | Implement conversation memory (ConversationSummaryBufferMemory) + session management | 3 | — |
| 5 | frontend | Build Streamlit chat UI with file upload + streaming display | 3 | group-1 |
| 6 | qa | Write tests: unit for chunking, integration for ingest→query flow | 4 | group-1 |
| 7 | docs | API docs + deployment guide | 5, 6 | — |

## Docker Compose

```yaml
services:
  chromadb:
    image: chromadb/chroma:latest
    ports:
      - "8000:8000"
    volumes:
      - chroma_data:/chroma/chroma
    environment:
      CHROMA_SERVER_AUTH_CREDENTIALS: ${CHROMA_TOKEN}
      CHROMA_SERVER_AUTH_CREDENTIALS_PROVIDER: token

  api:
    build:
      context: ./{backend_dir}
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      CHROMA_HOST: chromadb
      CHROMA_PORT: 8000
      CHROMA_TOKEN: ${CHROMA_TOKEN}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      EMBED_MODEL: text-embedding-3-small
      LLM_MODEL: gpt-4o-mini
    depends_on:
      - chromadb

  ui:
    build:
      context: ./{frontend_dir}
      dockerfile: Dockerfile
    command: streamlit run streamlit_app.py --server.port 8501
    ports:
      - "8501:8501"
    environment:
      API_URL: http://api:8080
    depends_on:
      - api

volumes:
  chroma_data:
```

## Notes

- Use `lazy_load()` for memory-efficient streaming of large document corpora
- PyPDFLoader for fast basic PDF extraction; UnstructuredPDFLoader for table/image awareness
- ConversationSummaryBufferMemory (max_token_limit=2000) is best for production chatbots
- ChromaDB in-memory client (`chromadb.Client()`) for tests — no external service needed
- For streaming in FastAPI, use `StreamingResponse` with `text/event-stream` content type
