---
type: example
archetype: "visual-rag-pipeline"
frameworks: [langflow, qdrant, openai]
complexity: low
description: "Visual RAG pipeline with document ingestion and retrieval using LangFlow's drag-and-drop interface"
platforms: [langflow]
ui: langflow
---

# Example EPIC: LangFlow Visual RAG Pipeline

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building a RAG pipeline and the team prefers visual, no-code flow design
- Rapid prototyping of retrieval-augmented generation without writing Python
- Non-engineers need to modify flow logic (chunking strategy, prompt templates)
- You want GitOps-style flow deployment with version-controlled JSON exports

### When NOT to use
- Need fine-grained control over chain composition (use LangChain LCEL instead)
- Complex multi-agent orchestration with custom state (use LangGraph)
- High-throughput production inference requiring custom optimizations
- Team is already proficient in Python and prefers code-first approach

Tech stack: LangFlow 1.7+ + Qdrant + PostgreSQL + OpenAI embeddings.
Greenfield: new LangFlow deployment with two flows (ingestion + retrieval).
Pattern: two-flow RAG architecture — Load Data Flow and Retriever Flow sharing a Qdrant collection.

## Goal

When complete, a LangFlow instance hosts two flows: (1) a Load Data Flow that
accepts PDF/text uploads, chunks documents, embeds them, and stores in Qdrant,
and (2) a Retriever Flow that accepts user questions, performs similarity search,
and generates answers with source citations via Chat Output. Flows are exported
as JSON and stored in version control for GitOps deployment.

## Scope

### Allowed files/paths
- `{project_root}/flows/` (exported flow JSON files)
  - `{project_root}/flows/load-data-flow.json`
  - `{project_root}/flows/retriever-flow.json`
- `{project_root}/custom_components/` (optional custom LangFlow components)
- `{project_root}/docker-compose.yml`
- `{project_root}/.env`
- `{project_root}/docs/`
- `{project_root}/CHANGELOG.md`

### Forbidden zones
- LangFlow source code (use official Docker image only)
- Qdrant internals (use REST API via LangFlow component)

## Artifacts

- flow: Load Data Flow (Read File → Split Text → OpenAI Embeddings → Qdrant ingest)
- flow: Retriever Flow (Chat Input → Embeddings → Qdrant search → Prompt → LLM → Chat Output)
- config: docker-compose.yml with langflow + qdrant + postgres services
- config: .env with API keys and Qdrant URL
- doc: `docs/deployment.md`, `CHANGELOG.md`

## Constraints

- Tenant-safe: no (single-tenant deployment)
- Audit trail: no
- Structured outputs: yes (Chat Output with source chunks)
- Budget: $8 max LLM cost

## DoD Gates

- tests_pass
- docs_updated

## Acceptance Criteria

- [ ] [architect] Load Data Flow accepts PDF and text files via File Upload component
- [ ] [architect] Split Text uses RecursiveCharacterTextSplitter with chunk_size=1000, overlap=100
- [ ] [architect] Qdrant collection stores embeddings with source metadata (filename, page number)
- [ ] [architect] Retriever Flow returns answers with retrieved context chunks visible
- [ ] [backend] Docker Compose starts all 3 services (langflow, qdrant, postgres) with `docker compose up`
- [ ] [backend] Flows auto-load on container start via LANGFLOW_LOAD_FLOWS_PATH
- [ ] [qa] End-to-end: upload a PDF → ask a question → receive relevant answer
- [ ] [docs] Deployment guide covers .env setup, Docker Compose, and flow export/import

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design flow architecture: component selection for both flows, Qdrant collection schema, embedding model choice | — | — |
| 2 | backend | Build Load Data Flow in LangFlow UI: Read File → Split Text → OpenAI Embeddings → Qdrant Vector Store (ingest mode) | 1 | — |
| 3 | backend | Build Retriever Flow: Chat Input → Embeddings → Qdrant (search mode) → Prompt template with context + question → LLM → Chat Output | 2 | — |
| 4 | backend | Configure Docker Compose with langflow + qdrant + postgres, set LANGFLOW_LOAD_FLOWS_PATH, export flows as JSON to /flows/ | 3 | — |
| 5 | qa | End-to-end test: upload document, query, verify answer relevance and source citations | 4 | — |
| 6 | docs | Write deployment guide + update CHANGELOG | 5 | — |

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: langflow
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: langflow
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U langflow"]
      interval: 5s
      timeout: 5s
      retries: 5

  qdrant:
    image: qdrant/qdrant:latest
    ports:
      - "6333:6333"
    volumes:
      - qdrant_data:/qdrant/storage

  langflow:
    image: langflowai/langflow:latest
    ports:
      - "7860:7860"
    environment:
      LANGFLOW_DATABASE_URL: postgresql://langflow:${POSTGRES_PASSWORD}@postgres:5432/langflow
      LANGFLOW_LOAD_FLOWS_PATH: /app/flows
      LANGFLOW_SECRET_KEY: ${LANGFLOW_SECRET_KEY}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      QDRANT_URL: http://qdrant:6333
      LANGFLOW_STORE_ENVIRONMENT_VARIABLES: "true"
    volumes:
      - ./flows:/app/flows
      - ./custom_components:/app/custom_components
    depends_on:
      postgres:
        condition: service_healthy
      qdrant:
        condition: service_started

volumes:
  postgres_data:
  qdrant_data:
```

## Notes

- LangFlow's two-flow RAG architecture cleanly separates ingestion from retrieval
- Export flows as JSON (`GET /api/v1/flows/{flow_id}`) and commit to git for version control
- LANGFLOW_LOAD_FLOWS_PATH imports all .json files on startup — enables GitOps deployment
- For observability, add LANGFUSE_SECRET_KEY, LANGFUSE_PUBLIC_KEY, LANGFUSE_HOST env vars
- The langflowai/langflow-backend image is available for API-only deployments without the UI
