---
type: example
archetype: "data-extraction-pipeline"
frameworks: [langchain, fastapi, postgresql]
complexity: medium
description: "Structured data extraction from unstructured sources with validation and database storage"
platforms: [langchain]
ui: none
---

# Example EPIC: Data Extraction Pipeline

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Extracting structured entities from unstructured text (emails, reports, web pages)
- Need type-safe extraction with Pydantic schema validation
- Processing heterogeneous document formats (PDF, HTML, plain text)
- Building ETL pipelines where the "Transform" step requires NLP understanding

### When NOT to use
- Data is already structured (CSV, JSON, XML — use traditional parsers)
- Need real-time extraction at >1000 docs/second (use dedicated NER models)
- Extraction rules are simple and deterministic (regex/rules are cheaper)
- Sensitive data that cannot be sent to external LLMs

Tech stack: LangChain 0.2+ with_structured_output + FastAPI + PostgreSQL.
Greenfield: new `{backend_dir}/data_extraction/` module.
Pattern: document load → schema-driven LLM extraction → validation → DB storage.

## Goal

When complete, the system accepts documents via API, extracts entities matching
a user-defined schema (configurable per extraction job), validates the output
against the schema, and stores structured results in PostgreSQL. Supports batch
processing with progress tracking and error quarantine.

## Scope

### Allowed files/paths
- `{backend_dir}/data_extraction/`
  - `{backend_dir}/data_extraction/extractor.py` — LLM extraction with dynamic schemas
  - `{backend_dir}/data_extraction/loaders.py` — multi-format document loaders
  - `{backend_dir}/data_extraction/schemas.py` — base models + dynamic schema builder
  - `{backend_dir}/data_extraction/models.py` — SQLAlchemy models
  - `{backend_dir}/data_extraction/routes.py` — FastAPI endpoints
  - `{backend_dir}/data_extraction/service.py` — batch processing + error handling
- `{backend_dir}/alembic/versions/` (new migration)
- `{backend_dir}/tests/test_data_extraction/`

### Forbidden zones
- `{backend_dir}/core/` (import only)

## Artifacts

- endpoint: POST /api/v1/extract (submit document + schema, returns extracted data)
- endpoint: POST /api/v1/extract/batch (submit batch job)
- endpoint: GET /api/v1/extract/jobs/{job_id} (check batch progress)
- endpoint: GET /api/v1/extract/failed (quarantined extractions)
- model: extraction_jobs table + extraction_results table

## Constraints

- Tenant-safe: yes (tenant_id on all records)
- Structured outputs: yes (dynamic Pydantic schemas)
- Budget: $15 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] Accepts documents: PDF, HTML, TXT, DOCX formats
- [ ] [backend] User provides extraction schema as JSON (field names, types, descriptions)
- [ ] [backend] LLM extracts entities matching the provided schema using with_structured_output
- [ ] [backend] Validation rejects extractions where required fields are missing
- [ ] [backend] Batch endpoint processes up to 50 documents with progress tracking
- [ ] [backend] Failed extractions quarantined with error details for manual review
- [ ] [qa] Unit tests with 5 sample documents and 3 different schemas
- [ ] [qa] Integration test: submit PDF + schema → verify DB record matches expected extraction

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design extraction pipeline: dynamic schema support, loader strategy, batch processing model | — | — |
| 2 | backend | Implement multi-format document loaders + dynamic Pydantic schema builder | 1 | — |
| 3 | backend | Implement LLM extractor with with_structured_output + validation | 2 | — |
| 4 | backend | Implement batch processing service + SQLAlchemy models + Alembic migration | 3 | — |
| 5 | backend | Implement FastAPI endpoints: extract, batch, progress, failed | 4 | — |
| 6 | qa | Write tests with sample documents and schemas | 5 | — |
| 7 | docs | API docs + schema format reference | 6 | — |

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: extraction
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: extraction
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U extraction"]
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
      DATABASE_URL: postgresql://extraction:${POSTGRES_PASSWORD}@postgres:5432/extraction
      OPENAI_API_KEY: ${OPENAI_API_KEY}
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
```

## Notes

- Dynamic schemas: build Pydantic models at runtime from user-provided JSON field definitions
- Use `with_structured_output()` for guaranteed schema compliance
- For large documents, chunk and extract from each chunk, then merge/deduplicate
- UnstructuredLoader handles 25+ file types with automatic format detection
- Consider confidence scoring: ask the LLM to rate extraction confidence per field
- For batch jobs, use asyncio.gather() with semaphore to control concurrent LLM calls
