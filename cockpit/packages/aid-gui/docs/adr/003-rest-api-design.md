# ADR-003: REST API Design

**Status:** Accepted
**Date:** 2026-02-25
**EPIC:** E-005-3_4-gui-rest-api

## Context

The AID GUI Dashboard needs a REST API to serve parsed `.aid-o/` data to the
React frontend. The API must expose all entity types defined in `server/types.ts`,
support multi-project contexts, and handle both read-only data access and write
operations (decisions, queue management).

## Decision

### 1. URL Structure

All API routes are namespaced under `/api/p/:projectId/` where `:projectId`
identifies the target project. For single-project mode (the default), the client
uses `default` as the projectId.

```
/api/p/:projectId/pipeline          — Pipeline state
/api/p/:projectId/pipeline/steps    — Step list from plan
/api/p/:projectId/pipeline/stage-log — Stage log entries (last N)
/api/p/:projectId/evidence          — EPIC list with runs
/api/p/:projectId/evidence/:epicId  — Runs for a specific EPIC
/api/p/:projectId/evidence/:epicId/:runId       — Run detail + file tree
/api/p/:projectId/evidence/:epicId/:runId/files/* — Raw file content
/api/p/:projectId/epics             — EPIC spec list
/api/p/:projectId/epics/:epicId     — Single EPIC spec detail
/api/p/:projectId/plans             — Plan list
/api/p/:projectId/plans/:planId     — Single plan detail
/api/p/:projectId/config            — Config summary
/api/p/:projectId/knowledge         — Agent/skill/command inventory
/api/p/:projectId/decisions         — Decision history
/api/p/:projectId/decisions/pending — Pending decisions (missing pm_decision.json)
/api/p/:projectId/decisions         — POST: write a decision response
/api/p/:projectId/audit             — Audit reports
/api/p/:projectId/queue             — Queue state (GET, POST, PUT, DELETE)
/api/p/:projectId/usage             — Token usage summary
```

### 2. Response Envelope

All successful responses use a consistent envelope:

```typescript
interface ApiResponse<T> {
  ok: true;
  data: T;
  meta?: {
    total?: number;      // For list endpoints
    warnings?: string[]; // Parser warnings propagated
  };
}
```

Error responses:

```typescript
interface ApiError {
  ok: false;
  error: {
    code: string;        // Machine-readable (e.g., "NOT_FOUND", "PARSE_ERROR")
    message: string;     // Human-readable description
    details?: unknown;   // Additional context
  };
}
```

HTTP status codes:
- `200` — Success
- `201` — Created (POST decision, POST queue item)
- `400` — Bad request (malformed body, missing required fields)
- `404` — Resource not found (EPIC, run, file does not exist)
- `500` — Server error (unexpected failures)

### 3. Project Resolution

The middleware resolves `:projectId` to an `.aid-o/` directory path:

- `"default"` → use the `AID_PROJECT_PATH` env var or default monorepo path
- Other IDs → look up in `~/.aid-gui/projects.json` (future multi-project)

The resolved path is attached to `req.aidoPath` via Express middleware.

### 4. Endpoint → File Path Mapping

| Endpoint | .aid-o/ Path | Parser | Notes |
|----------|-------------|--------|-------|
| GET /pipeline | `04-engine/auto-mode-state.yaml` + active `plan_progress.json` | yaml + json | Composite response |
| GET /pipeline/steps | Active `plan.json` → steps[] | json | |
| GET /pipeline/stage-log | Active `stage_log.jsonl` | jsonl | Last 100 entries |
| GET /evidence | `04-engine/evidence/` dir listing | — | Directory scan |
| GET /evidence/:epicId | `04-engine/evidence/{epicId}/` subdirs | — | Run directory scan |
| GET /evidence/:epicId/:runId | `04-engine/evidence/{epicId}/{runId}/` | — | File tree |
| GET /evidence/.../files/* | Direct file path | Extension-based | MD→parsed, YAML→parsed, JSON→parsed, JSONL→array |
| GET /epics | `02-epics/*.md` | epicSpec | Frontmatter + sections |
| GET /epics/:epicId | `02-epics/{epicId}.md` | epicSpec | Full parse |
| GET /plans | `01-plans/*.md` | markdown | Frontmatter only for list |
| GET /plans/:planId | `01-plans/{planId}.md` | markdown | Full content |
| GET /config | `03-config/` scan | yaml | All YAML files parsed |
| GET /knowledge | `plugins/aid-orchestrator/` scan | markdown | Parse agent/skill MD |
| GET /decisions | `04-engine/evidence/**/pm_decision.json` | json | Recursive scan |
| GET /decisions/pending | Evidence dirs missing `pm_decision.json` | — | Directory diff logic |
| POST /decisions | Write `pm_decision.json` to specified path | — | Atomic write |
| GET /audit | `04-engine/evidence/**/audit-report.*` | yaml/md | Both formats |
| GET /queue | `04-engine/epic-queue.yaml` | yaml | |
| POST /queue | Append to queue | yaml | Write back |
| PUT /queue/:epicId | Update queue entry | yaml | |
| DELETE /queue/:epicId | Remove from queue | yaml | |
| GET /usage | Computed from `stage_log.jsonl` files | jsonl | Aggregation |

### 5. File Serving Rules (Evidence files/*)

| Extension | Content-Type | Behavior |
|-----------|-------------|----------|
| `.md` | `application/json` | Parse with gray-matter, return `{frontmatter, content}` |
| `.yaml`, `.yml` | `application/json` | Parse to JSON |
| `.json` | `application/json` | Parse and return |
| `.jsonl` | `application/json` | Parse each line, return as array |
| `.txt`, `.diff`, `.log` | `text/plain` | Return raw content |
| Other | `application/octet-stream` | Return raw content |

### 6. Atomic Write Protocol (Decisions)

POST /decisions writes `pm_decision.json` atomically:
1. Validate request body against Decision schema
2. Build target path: `.aid-o/04-engine/evidence/{epicId}/{runId}/pm_decision.json`
3. Write to `{target}.tmp`
4. Rename `{target}.tmp` → `{target}`
5. Return 201 with the written decision

### 7. Router Organization

Each domain gets its own Express Router file:
- `server/api/pipeline.ts` — pipeline + stage-log
- `server/api/evidence.ts` — evidence tree + file serving
- `server/api/epics.ts` — EPIC specs
- `server/api/plans.ts` — Plan documents
- `server/api/config.ts` — Configuration files
- `server/api/knowledge.ts` — Agent/skill/command inventory
- `server/api/decisions.ts` — Decision read + write
- `server/api/audit.ts` — Audit reports
- `server/api/queue.ts` — Queue CRUD
- `server/api/usage.ts` — Usage tracking

All routers are mounted behind a project-resolution middleware.

### 8. Active Run Resolution

Several endpoints need to find the "active" run (the most recent running or
completed run). Resolution strategy:

1. Read `auto-mode-state.yaml` → extract `current_epic_id` and find latest run
2. Scan `evidence/` directories by modification time as fallback
3. Cache the result for 5 seconds (simple TTL) to avoid repeated fs scans

## Consequences

- Consistent `/api/p/:projectId/` prefix future-proofs multi-project support
- Response envelope makes error handling uniform for the frontend
- Atomic writes prevent partial state corruption
- File serving with format-specific parsing avoids raw file handling in frontend
- Separate router files keep each module focused and testable
