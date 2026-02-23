---
type: example
archetype: "meeting-summarizer"
frameworks: [langchain, fastapi, openai]
complexity: low
description: "Meeting transcript summarizer with action item extraction and structured output"
platforms: [langchain]
ui: none
---

# Example EPIC: Meeting Summarizer

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Summarizing meeting transcripts from Zoom, Teams, or manual notes
- Extracting structured data: action items, decisions, attendees, key topics
- Need a simple chain (not an agent) — input is the full transcript text
- Output should be structured Markdown or JSON for integration with project tools

### When NOT to use
- Real-time transcription during meetings (use STT services directly)
- Transcript exceeds LLM context window (>100k tokens — need map-reduce)
- Need interactive Q&A about the meeting (use RAG chatbot pattern instead)
- Audio/video processing required (this handles text transcripts only)

Tech stack: LangChain 0.2+ + FastAPI + OpenAI (gpt-4o-mini for cost efficiency).
Greenfield: new `{backend_dir}/meeting_summarizer/` module.
Pattern: single LCEL chain with structured output — prompt → LLM → Pydantic parse.

## Goal

When complete, the API accepts meeting transcript text, produces a structured
summary with sections (overview, decisions, action items with assignees, key
topics), and returns it as both Markdown and JSON. Supports batch processing
of multiple transcripts.

## Scope

### Allowed files/paths
- `{backend_dir}/meeting_summarizer/`
  - `{backend_dir}/meeting_summarizer/chain.py` — LCEL summarization chain
  - `{backend_dir}/meeting_summarizer/schemas.py` — Pydantic output models
  - `{backend_dir}/meeting_summarizer/routes.py` — FastAPI endpoints
- `{backend_dir}/tests/test_meeting_summarizer/`
- `{project_root}/docs/api/meeting-summarizer.md`

### Forbidden zones
- `{backend_dir}/core/` (import only)

## Artifacts

- endpoint: POST /api/v1/meetings/summarize (submit transcript, returns summary)
- endpoint: POST /api/v1/meetings/summarize/batch (submit multiple transcripts)
- schema: MeetingSummary (overview, decisions[], action_items[], topics[])

## Constraints

- Tenant-safe: no (stateless processing)
- Structured outputs: yes (Pydantic with_structured_output)
- Budget: $8 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] POST /summarize accepts transcript text up to 50k tokens
- [ ] [backend] Response includes: overview (1-3 paragraphs), decisions[], action_items[], topics[]
- [ ] [backend] Each action_item has: description, assignee (extracted from transcript), due_date (if mentioned)
- [ ] [backend] Batch endpoint processes up to 10 transcripts, returns array of summaries
- [ ] [backend] Returns 422 if transcript is empty or exceeds token limit
- [ ] [qa] Unit tests with 3 sample transcripts of varying length
- [ ] [docs] API reference with example request/response

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design output schema (MeetingSummary Pydantic model) + prompt template | — | — |
| 2 | backend | Implement LCEL chain: prompt template → LLM with_structured_output → MeetingSummary | 1 | — |
| 3 | backend | Implement FastAPI endpoints: single + batch summarization | 2 | — |
| 4 | qa | Write tests with sample transcripts | 3 | — |
| 5 | docs | API docs with examples | 4 | — |

## Docker Compose

```yaml
services:
  api:
    build:
      context: ./{backend_dir}
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      LLM_MODEL: gpt-4o-mini
```

## Notes

- Use gpt-4o-mini for cost efficiency — meeting summaries don't need the largest model
- For transcripts exceeding context window, implement map-reduce: summarize chunks → merge
- `with_structured_output(MeetingSummary)` guarantees valid Pydantic output
- Consider adding a confidence score to each action item extraction
- LangFlow alternative: Meeting Notes Summarizer Agent template provides this as a visual flow
