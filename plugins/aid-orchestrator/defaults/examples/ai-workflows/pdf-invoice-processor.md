---
type: example
archetype: "document-extraction"
frameworks: [langchain, fastapi, postgresql]
complexity: medium
description: "PDF invoice extraction pipeline with structured output parsing and database storage"
platforms: [langchain]
ui: none
---

# Example EPIC: PDF Invoice Processor

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Extracting structured data from PDF invoices (vendor, amount, line items, dates)
- Need Pydantic-validated output with type-safe structured extraction
- Processing batches of invoices with error handling and retry logic
- Storing extracted data in a relational database for downstream processing

### When NOT to use
- Simple OCR-only extraction (use Tesseract/AWS Textract directly)
- Invoices are already in structured format (CSV, XML, EDI)
- Need real-time processing of >100 invoices/second (use dedicated OCR service)
- Handwritten invoices (requires specialized vision models)

Tech stack: LangChain 0.2+ with_structured_output + FastAPI + PostgreSQL + Alembic.
Greenfield: new `{backend_dir}/invoice_processor/` module.
Pattern: PDF load → LLM extraction with Pydantic schema → validation → DB storage.

## Goal

When complete, the system accepts PDF invoice uploads via API, extracts structured
data (vendor name, invoice number, date, total, line items) using LLM with
Pydantic with_structured_output, validates the extraction, and stores results
in PostgreSQL. Failed extractions are queued for manual review.

## Scope

### Allowed files/paths
- `{backend_dir}/invoice_processor/`
  - `{backend_dir}/invoice_processor/extractor.py` — PDF loading + LLM extraction
  - `{backend_dir}/invoice_processor/schemas.py` — Pydantic models for invoice data
  - `{backend_dir}/invoice_processor/models.py` — SQLAlchemy models
  - `{backend_dir}/invoice_processor/routes.py` — FastAPI endpoints
  - `{backend_dir}/invoice_processor/service.py` — business logic + validation
- `{backend_dir}/alembic/versions/` (new migration)
- `{backend_dir}/tests/test_invoice_processor/`

### Forbidden zones
- `{backend_dir}/core/` (import only)

## Artifacts

- endpoint: POST /api/v1/invoices/extract (upload PDF, returns extracted data)
- endpoint: GET /api/v1/invoices (list processed invoices)
- endpoint: GET /api/v1/invoices/failed (list failed extractions for review)
- model: invoices table + invoice_line_items table
- migration: Alembic revision

## Constraints

- Tenant-safe: yes (tenant_id on all records)
- Structured outputs: yes (Pydantic with_structured_output)
- Budget: $15 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] POST /api/v1/invoices/extract accepts PDF files up to 10MB
- [ ] [backend] Extraction uses with_structured_output(InvoiceSchema) for type-safe output
- [ ] [backend] InvoiceSchema includes: vendor_name, invoice_number, date, total, currency, line_items[]
- [ ] [backend] Each line_item has: description, quantity, unit_price, amount
- [ ] [backend] Validation rejects invoices where line_item totals don't sum to invoice total (±1%)
- [ ] [backend] Failed extractions stored with error reason, queryable via /failed endpoint
- [ ] [qa] Unit tests with 3 sample invoice PDFs (standard, multi-page, edge-case)
- [ ] [qa] Integration test: upload PDF → verify DB record matches expected values

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design extraction pipeline: PDF loader choice, Pydantic schemas, DB schema, error handling strategy | — | — |
| 2 | backend | Implement Pydantic schemas + SQLAlchemy models + Alembic migration | 1 | — |
| 3 | backend | Implement PDF extractor: PyPDFLoader + LLM with_structured_output + validation | 2 | — |
| 4 | backend | Implement FastAPI endpoints: extract, list, failed | 3 | — |
| 5 | qa | Write tests with sample invoice PDFs | 4 | — |
| 6 | docs | API docs + sample request/response | 5 | — |

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: invoices
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: invoices
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U invoices"]
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
      DATABASE_URL: postgresql://invoices:${POSTGRES_PASSWORD}@postgres:5432/invoices
      OPENAI_API_KEY: ${OPENAI_API_KEY}
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
```

## Notes

- Use `model.with_structured_output(InvoiceSchema)` for guaranteed Pydantic-validated output
- PyPDFLoader for basic PDFs; UnstructuredPDFLoader with `strategy="hi_res"` for complex layouts
- For batch processing, implement a queue (Redis + Celery) to avoid blocking the API
- Include `model_config = ConfigDict(from_attributes=True)` in Pydantic models for ORM mode
- Consider retry logic: if extraction confidence is low, retry with a more capable model
