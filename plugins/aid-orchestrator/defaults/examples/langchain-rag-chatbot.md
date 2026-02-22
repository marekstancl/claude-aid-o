---
type: example
archetype: "rag-chatbot"
frameworks: [langchain, chromadb, fastapi]
complexity: medium
description: "RAG chatbot with document ingestion, vector store, and retrieval chain"
---

# Example EPIC: LangChain RAG Chatbot

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building a knowledge base Q&A system over static or semi-static documents
- Chatbot needs to answer questions from PDFs, markdown files, or web pages
- You want source citations in responses (RAG naturally provides retrieved context)
- Latency of 1-5s per query is acceptable

### When NOT to use
- Data changes in real-time (use streaming + live search instead)
- Questions require complex multi-hop reasoning across many documents (use agents)
- You need sub-500ms responses (vector search + LLM chain adds latency)
- Structured data queries (SQL or graph DBs are more appropriate)

Tech stack: LangChain 0.2+ + ChromaDB + FastAPI 0.100+ + OpenAI or Ollama.
Greenfield: new `{backend_dir}/rag/` module. No prior chatbot code assumed.
Pattern: async FastAPI endpoints, LCEL chain composition, SSE streaming.

## Goal

When complete, users can upload documents via API, which are chunked, embedded,
and stored in ChromaDB. A retrieval endpoint accepts questions, runs an LCEL
chain over retrieved chunks, and streams the response via Server-Sent Events.
Conversation history is maintained per session for multi-turn context.

## Scope

### Allowed files/paths
- `{backend_dir}/rag/` (new module)
  - `{backend_dir}/rag/ingestor.py` — document loading, chunking, embedding
  - `{backend_dir}/rag/retriever.py` — ChromaDB client, similarity search
  - `{backend_dir}/rag/chain.py` — LCEL chain, prompt template, LLM binding
  - `{backend_dir}/rag/memory.py` — conversation buffer, session store
  - `{backend_dir}/rag/routes.py` — FastAPI router (ingest + chat endpoints)
  - `{backend_dir}/rag/schemas.py` — Pydantic request/response models
- `{backend_dir}/tests/test_rag/`
- `{project_root}/docs/api/rag.md`
- `{project_root}/CHANGELOG.md`

### Forbidden zones
- `{backend_dir}/core/` (shared infrastructure — import but do not modify)
- `{backend_dir}/auth/` (authentication module — use existing middleware)
- `{project_root}/alembic/` (no DB migrations needed for ChromaDB)

## Artifacts

- endpoint: POST /api/v1/rag/ingest (upload + process documents)
- endpoint: GET /api/v1/rag/chat (SSE streaming chat with retrieval)
- endpoint: DELETE /api/v1/rag/session/{session_id} (clear conversation memory)
- model: ChromaDB collection per tenant/project
- config: `.env` keys — CHROMA_HOST, EMBED_MODEL, LLM_MODEL, CHUNK_SIZE
- doc: `docs/api/rag.md`, `CHANGELOG.md`

## Constraints

- Tenant-safe: yes (ChromaDB collection scoped by tenant_id)
- Audit trail: no (chat logs optional, not required)
- Outbox pattern: no
- Structured outputs: yes (streaming SSE chunks + final JSON summary)
- Budget: $20 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- docs_updated

## Acceptance Criteria

- [ ] [backend] POST /api/v1/rag/ingest accepts PDF and markdown, returns 202 with job_id
- [ ] [backend] Ingestor chunks documents at configurable size (default 512 tokens, overlap 50)
- [ ] [backend] ChromaDB collection contains embeddings within 30s of ingest for <10MB file
- [ ] [backend] GET /api/v1/rag/chat streams SSE events with role=assistant and source citations
- [ ] [backend] Chat endpoint returns 400 when question is empty or session_id missing
- [ ] [backend] Multi-turn: second question in same session_id has access to prior context
- [ ] [backend] DELETE /api/v1/rag/session/{id} clears memory and returns 204
- [ ] [qa] pytest covers ingestor chunking logic with 3 fixture documents (PDF, MD, TXT)
- [ ] [qa] Integration test: ingest → query returns at least 1 source citation
- [ ] [qa] ChromaDB tests use in-memory client (no external service required)
- [ ] [docs] `docs/api/rag.md` documents all 3 endpoints with request/response examples

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design ingestion pipeline + retrieval chain architecture + OpenAPI contracts for /ingest and /chat | — | — |
| 2 | backend | Implement document ingestor: load PDF/MD/TXT, recursive text splitter, embed with configured model, store in ChromaDB | 1 | — |
| 3 | backend | Implement FastAPI retrieval endpoint with LCEL chain (retriever → prompt → LLM) + SSE streaming response | 2 | — |
| 4 | backend | Implement conversation memory: per-session buffer store, inject history into chain prompt, DELETE session endpoint | 3 | — |
| 5 | qa | Write pytest suite: unit tests for chunking logic, integration tests for ingest→query flow using in-memory ChromaDB | 4 | — |
| 6 | docs | Write API reference (docs/api/rag.md) + deployment guide (env vars, ChromaDB setup, model selection) | 5 | — |

## Session Breakdown

This EPIC fits in a single orchestrated run.

### Session 1: Full RAG Implementation
**Goal:** Complete ingestion pipeline, retrieval chain, memory, tests, and docs.
**Deliverables:** All 3 endpoints live, pytest suite green, API docs written.

## Hints

- expected_steps: 6
- complexity: medium
- parallelism_potential: low (steps are sequential — each builds on prior)
- notes: >
    Step 2 (ingestor) must complete before step 3 (chain) because chain depends
    on ChromaDB collection structure. Use LangChain `RecursiveCharacterTextSplitter`
    for chunking. For SSE in FastAPI, use `StreamingResponse` with
    `text/event-stream` content type. In-memory ChromaDB: `chromadb.Client()`
    (no host needed for tests).
