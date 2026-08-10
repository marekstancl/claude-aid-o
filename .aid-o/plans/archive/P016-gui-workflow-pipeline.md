---
id: P016
type: plan
status: done
created: 2026-02-27
author: PM + AI
---

# Plan: GUI Workflow — Ideas to Execution Pipeline

## Context

AID GUI dashboard (React 19 + Zustand + Tailwind v4, Express backend, WebSocket) has a stable foundation after P009 Phase 1 (E-009-1_5): all 9 pages load without crashes, WebSocket connects on page load, 11 bugs fixed, Playwright verified. The dashboard currently functions as a monitoring tool with isolated screens. This plan transforms it into an integrated workflow management tool where ideas flow through a kanban pipeline, AI Companion chat enables brainstorming directly in the GUI, and polished views provide evidence exploration and pipeline replay.

**Technical blockers resolved during brainstorming:**
- CLI proxy (`claude -p --output-format stream-json --verbose`): verified working with Max/Pro subscription auth, `apiKeySource: "none"`, no API key needed
- `ai-sdk-provider-claude-code` npm package: verified working — `generateText()` and `streamText()` use subscription auth, no API key required
- Agent SDK native (`@anthropic-ai/claude-agent-sdk`): requires `ANTHROPIC_API_KEY` (pay-per-token) — reserved for future v2

**Predecessor:** P009-gui-workflow-architecture.md (Phase 1 complete, phases 2-3 replaced by this plan)

## Goal

Transform AID GUI from a monitoring dashboard into a functional workflow management tool where ideas flow through Ideas → Plan → EPIC → Running → Done with automatic status transitions, integrated AI Companion chat (dual-mode: ai-sdk-provider primary, CLI proxy fallback), Queue Scheduler integration, voice dictation, and polished Evidence Vault / Pipeline Theater / Decision Hub views.

## Scope

**In scope:**
- Extend StoredIdea with `autoStatus` field for automatic lifecycle transitions
- IDEAS.md ↔ ideas.json migration service (startup import, shutdown export)
- Backlog and Lessons Learned API endpoints (parse existing markdown files)
- 5-column kanban rebuild (Ideas / Plan / EPIC / Running / Done)
- Multi-select ideas with "Create Plan" action
- Insights panel (Backlog + Lessons tabs with drag-to-kanban)
- WebSocket `ideas` topic for real-time kanban updates
- CompanionService with adapter pattern (ai-sdk-provider primary, CLI proxy fallback)
- Chat UI with Cmd+K slide-down panel, streaming responses, session persistence
- 7 hint commands (Brainstorm, Plan EPIC, Run, Audit, Explain, Fix, Free chat)
- Voice dictation via Whisper API with Web Speech API fallback
- EPIC lifecycle endpoints and EPIC column UI with building animation
- Queue Scheduler integration with "Run Now" and "Schedule" actions
- Automatic card transitions via WebSocket events
- Evidence Vault redesign (grouped by date, markdown preview, full-text search)
- Pipeline Theater replay (timeline visualization, replay controls, live mode)
- Decision Hub notifications (Web Audio + browser Notification API)
- Playwright smoke tests + Vitest unit tests after every phase

**Out of scope:**
- Agent SDK adapter implementation (v2 — interface prepared, adapter stub only)
- Brainstorm Canvas / mind map visualization (future)
- Multi-user / authentication
- EPIC editor in GUI (EPICs are created via AI, edited in CLI/IDE)
- Mobile-native app
- CI/CD integration

## Approach

### Option A: 3-Phase Bottom-Up (Chosen)

Phase 1: Data Layer + Kanban → Phase 2: AI Companion + EPIC Lifecycle → Phase 3: Polish. Each phase produces an independently testable state and builds on the previous one.

**Pros:**
- Each phase is shippable — after Phase 1, the kanban works; after Phase 2, the full workflow works
- Data layer foundation enables AI Companion to operate on real data
- Lowest risk — if Phase 3 is deferred, the product is still functional

**Cons:**
- AI Companion (the "wow" feature) comes in Phase 2, not Phase 1
- 3 EPICs total, longer overall timeline

### Option B: Feature-First (Rejected)

Start with AI Companion, then wire data flow around it. Rejected because it builds on incomplete data foundation and the CLI proxy integration is uncharted territory that benefits from a stable base.

### Option C: Big Bang (Rejected)

Everything in one mega-EPIC. Rejected because of enormous scope and inability to test incrementally.

**Decision:** Option A — the data layer must exist before the AI Companion can interact with ideas, plans, and EPICs meaningfully.

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────┐
│  Frontend (React 19 + Zustand)                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐│
│  │ Kanban   │ │ Chat UI  │ │ Evidence/Pipeline││
│  │ 5-column │ │ Cmd+K    │ │ Theater/Decision ││
│  │ + Insight│ │ + Hints  │ │ Hub              ││
│  └────┬─────┘ └────┬─────┘ └────────┬─────────┘│
│       │            │                │           │
│  ┌────┴────────────┴────────────────┴─────────┐ │
│  │  Zustand Store (15 slices)                 │ │
│  │  + CompanionSlice + InsightsSlice          │ │
│  └────┬───────────────────────────────────────┘ │
│       │ REST + WebSocket                        │
└───────┼─────────────────────────────────────────┘
        │
┌───────┼─────────────────────────────────────────┐
│  Backend (Express + ws)                         │
│  ┌────┴──────┐ ┌────────────┐ ┌───────────────┐│
│  │ Ideas     │ │ Companion  │ │ Evidence      ││
│  │ Routes    │ │ Service    │ │ Routes        ││
│  │ + migrate │ │ + adapters │ │ + search      ││
│  └───────────┘ └────────────┘ └───────────────┘│
│  ┌───────────┐ ┌────────────┐ ┌───────────────┐│
│  │ Backlog   │ │ EPIC       │ │ Pipeline      ││
│  │ + Lessons │ │ Lifecycle  │ │ Theater data  ││
│  │ Routes    │ │ Routes     │ │ Routes        ││
│  └───────────┘ └────────────┘ └───────────────┘│
│  ┌──────────────────────────────────────────┐   │
│  │ WsHandler (chokidar + topic pub/sub)    │   │
│  │ + ideas topic + companion.stream topic  │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### CompanionService Adapter Pattern

```
CompanionService (interface)
  ├── AiSdkAdapter (primary) — ai-sdk-provider-claude-code
  ├── CliProxyAdapter (fallback) — child_process.spawn('claude', ...)
  └── StubAdapter (v2 placeholder) — Agent SDK native
```

Auto-detection order: (1) Try `ai-sdk-provider-claude-code` import → (2) Check `claude` CLI in PATH → (3) Return setup instructions. Frontend never knows which adapter is active.

### WebSocket Topic Extensions

Current topics: `pipeline`, `pipeline.stage_log`, `evidence`, `decisions`, `config`, `queue`, `audit`, `usage`, `queue.schedule`, `system`.

New topics added by this plan:
- `ideas` — emitted when `ideas.json` changes (chokidar classification)
- `companion.stream` — streaming AI Companion response chunks
- `companion.session` — session lifecycle events (start, end, error)
- `epics` — emitted when EPIC files change in `.aid-o/02-epics/`

## Data Model

### StoredIdea (extended)

Existing fields preserved. New field added:

```typescript
interface StoredIdea {
  // Existing fields (unchanged)
  id: string;               // e.g., "idea-1709123456789-a1b2"
  title: string;
  description: string;      // Markdown
  tags: string[];
  priority: 'low' | 'medium' | 'high';
  status: 'idea' | 'exploring' | 'planned' | 'done';
  linkedPlan: string | null;   // Plan ID, e.g., "P016"
  linkedEpic: string | null;   // EPIC ID, e.g., "E-016-1_3"
  createdAt: string;         // ISO 8601
  updatedAt: string;         // ISO 8601

  // New field
  autoStatus: 'idea' | 'plan' | 'epic' | 'running' | 'done' | null;
  // Computed from linked resources:
  //   null → use `status` for display
  //   'plan' → linkedPlan is set, no EPIC yet
  //   'epic' → linkedEpic is set, not running
  //   'running' → linkedEpic is currently executing
  //   'done' → linkedEpic completed
}
```

Kanban column mapping: `autoStatus ?? status`. The `autoStatus` field takes precedence over `status` for column placement. When `autoStatus` is null, the idea appears in the column matching its `status` field (backward compatible — existing `idea`/`exploring`/`planned`/`done` statuses map to the Ideas column since they don't match `plan`/`epic`/`running`).

### BacklogEntry (new, parsed from backlog.md)

```typescript
interface BacklogEntry {
  id: string;           // e.g., "IMP-001", "PROP-20260219-001"
  area: string;         // e.g., "aid-setup", "CHANGELOG.md"
  suggestion: string;   // Full markdown text
  priority: 'critical' | 'high' | 'medium' | 'low';
  source: string;       // e.g., "audit (E-20260221-91c4 / H1)"
  status: 'pending' | 'proposed' | 'implemented' | 'deferred' | 'rejected';
  section: string;      // Parent section: "Bugs", "Features", "Refactoring / Tech Debt"
}
```

### LessonEntry (new, parsed from lessons-learned.md)

```typescript
interface LessonEntry {
  date: string;        // e.g., "2026-02-19"
  lesson: string;      // Full text
  context: string;     // e.g., "E-20260219-v030"
  category: 'lesson' | 'gotcha';
}
```

### CompanionSession (new)

```typescript
interface CompanionSession {
  id: string;           // UUID
  title: string;        // Auto-generated from first message or hint command
  createdAt: string;    // ISO 8601
  updatedAt: string;    // ISO 8601
  messages: CompanionMessage[];
  adapter: 'ai-sdk' | 'cli-proxy';  // Which adapter was used
}

interface CompanionMessage {
  id: string;           // UUID
  role: 'user' | 'assistant';
  content: string;      // Markdown
  timestamp: string;    // ISO 8601
  hintCommand?: string; // Which hint was used, if any
}
```

### EpicMetadata (new, parsed from EPIC frontmatter)

```typescript
interface EpicMetadata {
  epicId: string;         // e.g., "E-016-1_3"
  title: string;          // From `# EPIC:` header
  status: string;         // From frontmatter: "active", "completed", "paused", "failed"
  planRef: string;        // From frontmatter: plan file reference
  stepsTotal: number;     // Count of steps in Steps table
  roles: string[];        // Unique roles from Steps table
  runsTotal: number;      // From frontmatter
  runsCompleted: number;  // From frontmatter
}
```

## API Design

### New Endpoints

#### Ideas Link Endpoint

```
PUT /api/p/:projectId/ideas/:ideaId/link
Request: { linkedPlan?: string | null, linkedEpic?: string | null }
Response: { ok: true, data: StoredIdea }
Errors:
  404 — Project not found (code: "NOT_FOUND")
  404 — Idea not found (code: "NOT_FOUND")
  400 — Neither linkedPlan nor linkedEpic provided (code: "BAD_REQUEST")
Side effects:
  - Sets autoStatus based on linked resources
  - Triggers chokidar → WS 'ideas' topic event
```

#### Backlog Endpoint

```
GET /api/p/:projectId/backlog
Response: { ok: true, data: BacklogEntry[] }
Errors:
  404 — Project not found (code: "NOT_FOUND")
  200 — File not found returns empty array (graceful degradation)
Notes:
  - Parses .aid-o/04-engine/memory/backlog.md
  - Extracts rows from all markdown tables in sections: Bugs, Features, Refactoring / Tech Debt
  - Each row becomes a BacklogEntry with the parent section name in `section` field
```

#### Lessons Endpoint

```
GET /api/p/:projectId/lessons
Response: { ok: true, data: LessonEntry[] }
Errors:
  404 — Project not found (code: "NOT_FOUND")
  200 — File not found returns empty array (graceful degradation)
Notes:
  - Parses .aid-o/04-engine/lessons-learned.md
  - Main table rows get category: 'lesson'
  - Known Gotchas table rows get category: 'gotcha'
```

#### Companion Endpoints

```
POST /api/p/:projectId/companion/send
Request: { message: string, sessionId?: string, hintCommand?: string }
Response: SSE stream — Content-Type: text/event-stream
  data: { type: 'chunk', content: string }
  data: { type: 'done', sessionId: string, fullResponse: string }
  data: { type: 'error', message: string }
Errors:
  404 — Project not found
  503 — No companion adapter available (code: "COMPANION_UNAVAILABLE")

GET /api/p/:projectId/companion/sessions
Response: { ok: true, data: CompanionSession[] }

GET /api/p/:projectId/companion/sessions/:sessionId
Response: { ok: true, data: CompanionSession }
Errors:
  404 — Session not found

GET /api/p/:projectId/companion/status
Response: { ok: true, data: { adapter: 'ai-sdk' | 'cli-proxy' | 'none', available: boolean } }
```

#### Voice Dictation Endpoint

```
POST /api/p/:projectId/companion/transcribe
Request: multipart/form-data — field 'audio' (webm/opus blob), field 'language' (default: 'cs')
Response: { ok: true, data: { text: string, language: string, duration: number } }
Errors:
  400 — No audio file (code: "BAD_REQUEST")
  503 — Whisper API unavailable (code: "WHISPER_UNAVAILABLE")
  413 — Audio file too large, max 25MB (code: "PAYLOAD_TOO_LARGE")
```

#### EPIC Lifecycle Endpoints

```
GET /api/p/:projectId/epics
Response: { ok: true, data: EpicMetadata[] }
Notes:
  - Scans .aid-o/02-epics/*.md (excludes archive/)
  - Parses frontmatter + first heading for each file

POST /api/p/:projectId/epics/:epicId/run
Request: { mode?: 'now' | 'schedule' }
Response: { ok: true, data: { queued: true, epicId: string, position?: number } }
Errors:
  404 — EPIC not found
  409 — EPIC already running (code: "CONFLICT")
Notes:
  - mode 'now': adds to front of queue with priority 'critical'
  - mode 'schedule': adds to end of queue with priority 'medium'
```

#### Evidence Search Endpoint

```
GET /api/p/:projectId/evidence/search?q=:query&limit=:limit
Response: { ok: true, data: EvidenceSearchResult[] }
  EvidenceSearchResult: { epicId, runId, filePath, matchLine, context }
Errors:
  400 — Query parameter missing (code: "BAD_REQUEST")
Notes:
  - Searches file contents in .aid-o/04-engine/evidence/ recursively
  - Case-insensitive substring match
  - Returns max `limit` results (default 50, max 200)
  - Skips binary files (detected by null bytes in first 512 bytes)
```

#### Pipeline Theater Data Endpoint

```
GET /api/p/:projectId/pipeline/theater/:epicId/:runId
Response: { ok: true, data: PipelineTheaterData }
  PipelineTheaterData: {
    epicId, runId, startedAt, completedAt,
    steps: { id, role, objective, status, startedAt, completedAt }[],
    events: StageLogEntryResponse[],
    duration: number  // seconds
  }
Errors:
  404 — EPIC or run not found
Notes:
  - Combines plan.json steps with plan_progress.json status
  - Includes full stage_log.jsonl entries for the specific run
```

## Testing Strategy

### Per-Phase Testing

Each phase ends with a dedicated QA step that runs:

1. **Vitest unit tests** — test individual functions, parsers, store slices, API client methods
2. **Playwright smoke tests** — visit pages, verify rendering, test interactions

### Vitest Test Organization

```
packages/aid-gui/tests/
  server/
    parsers/
      backlog.test.ts        (Phase 1)
      lessons.test.ts        (Phase 1)
    services/
      migration.test.ts      (Phase 1)
      companion.test.ts      (Phase 2)
      evidence-search.test.ts (Phase 3)
    api/
      ideas-link.test.ts     (Phase 1)
      companion.test.ts      (Phase 2)
      epics.test.ts          (Phase 2)
  frontend/
    store-ideas-extended.test.ts   (Phase 1)
    store-companion.test.ts        (Phase 2)
    store-insights.test.ts         (Phase 1)
    api-client-companion.test.ts   (Phase 2)
```

### Playwright Test Organization

```
packages/aid-gui/tests/e2e/
  phase1-kanban.spec.ts     — 5-column render, drag-drop, multi-select, insights
  phase2-companion.spec.ts  — chat open/close, send message, hint buttons, EPIC column
  phase3-polish.spec.ts     — evidence search, pipeline timeline, decision notification
```

### Coverage Targets

- Vitest: all new backend parsers and services at 80%+ line coverage
- Playwright: every new UI feature has at least one smoke test
- Regression: existing CRUD operations (create idea, drag status, delete) verified in every phase

## UI Design

### 5-Column Kanban Layout

```
┌──────────┬──────────┬──────────┬──────────┬──────────┐
│  Ideas   │   Plan   │   EPIC   │ Running  │   Done   │
│          │          │          │          │          │
│ ☐ Card   │ Card     │ Card     │ ⟳ Card   │ ✓ Card   │
│ ☐ Card   │ Card     │          │          │ ✓ Card   │
│ ☐ Card   │          │          │          │          │
│          │          │          │          │          │
│ [+ New]  │          │          │          │          │
└──────────┴──────────┴──────────┴──────────┴──────────┘
  ☐ = checkbox (multi-select)    ⟳ = spinning    ✓ = completed

  [Create Plan from 2 selected ideas]     ← appears when ≥1 selected
```

### Insights Panel (below kanban)

```
┌─────────────────────────────────────────────────────┐
│ [Backlog] [Lessons Learned]                         │
├─────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────┐ │
│ │ 🔴 IMP-001 | CHANGELOG.md | high | pending     │ │
│ │    Cut v0.5.0 release entry in both...          │ │
│ │ ⟵ drag to Ideas column                         │ │
│ ├─────────────────────────────────────────────────┤ │
│ │ 🟡 IMP-012 | memory-mcp.md | medium | pending  │ │
│ │    memory_find() lacks metadata filtering...    │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### Chat UI (Cmd+K)

```
┌──────────────────────────────────────────────────────┐
│ AI Companion                              [×] [─]    │
├──────────────┬───────────────────────────────────────┤
│ Sessions     │ ┌─────────────────────────────────┐   │
│              │ │ 🤖 How can I help?              │   │
│ > Current    │ │                                 │   │
│   Session 2  │ │ 👤 Brainstorm auth for my API   │   │
│   Session 1  │ │                                 │   │
│              │ │ 🤖 Let me help you think about  │   │
│              │ │    authentication options...     │   │
│              │ │    ▌ (streaming)                 │   │
│              │ └─────────────────────────────────┘   │
│              │                                       │
│              │ [Brainstorm][Plan EPIC][Run][Audit]    │
│              │ [Explain][Fix][Free chat]              │
│              │ ┌─────────────────────────┐ [🎤] [→] │
│              │ │ Type a message...       │           │
│              │ └─────────────────────────┘           │
└──────────────┴───────────────────────────────────────┘
```

## Constraints

- Docker deployment — all changes must work in Docker container (multi-stage build in `Dockerfile`)
- WebSocket server in `packages/aid-server/src/ws/handler.ts` already exists — extend with new topics, do not replace
- `ideas.json` at `.aid-o/04-engine/ideas.json` is source of truth when server is running; IDEAS.md for offline use
- EPIC generation via `/aid-plan-epic` takes 15-30 seconds — UI must handle async gracefully with progress animation
- ai-sdk-provider uses subscription auth — no API key required; CLI proxy uses `claude` CLI in PATH
- CompanionService interface must be adapter-agnostic — frontend uses the same API regardless of backend adapter
- New npm dependencies allowed: `ai`, `ai-sdk-provider-claude-code` (both verified working)
- Existing ideas CRUD must keep working — all changes are additive
- Express body parser limit must be increased for voice audio upload (25MB max)
- Playwright requires `@playwright/test` dev dependency and `playwright.config.ts` — neither exists yet

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ai-sdk-provider breaking changes | medium | high | CLI proxy fallback; pin exact version in package.json; adapter pattern isolates blast radius |
| CLI proxy unavailable in Docker | medium | medium | ai-sdk-provider as primary does not need CLI in PATH; document Docker setup in README |
| Whisper API latency for voice | low | medium | Web Speech API fallback in frontend; async transcription with buffering; 10s timeout |
| IDEAS.md parser loses data during migration | medium | medium | Backup original file before migration; validate round-trip (parse → export → diff); log skipped entries |
| EPIC generation timeout in kanban | low | medium | 60s timeout with retry; "Building" progress animation manages user expectation |
| WebSocket reconnection storms | low | high | Exponential backoff already implemented in useWebSocket.ts (1s → 30s max with 20% jitter) |
| Full-text evidence search performance | low | medium | Limit to 200 results; skip binary files; debounce frontend input (300ms) |
| Playwright flaky tests in Docker | medium | medium | Use `webServer` config to start server; `--retries 1` flag; screenshot on failure |

## Implementation Steps

### Step 1: StoredIdea Extension + Link Endpoint + WebSocket Ideas Topic

**Objective:** Add `autoStatus` field to StoredIdea, create a dedicated link endpoint that sets autoStatus based on linked resources, and register `ideas` as a WebSocket topic so idea changes broadcast to subscribed clients.

**Files:**
- Modify: `packages/aid-server/src/routes/ideas.ts` (lines ~1-88) — add `autoStatus` field handling to POST and PUT handlers, add new PUT `/:ideaId/link` route
- Modify: `packages/aid-server/src/ws/handler.ts` (lines ~12-14, ~190-199) — add `'ideas'` to EVENT_TOPICS array, add `ideas` classification rule to `classifyFileChange()`
- Modify: `packages/aid-server/src/routes/types.ts` — reuse existing `IdeaParams` interface (already has `projectId` and `ideaId`); add `IdeaLinkBody` type for the link request body

**Architecture Context:**
This step extends the existing ideas CRUD routes in `packages/aid-server/src/routes/ideas.ts` with a new `autoStatus` field and a dedicated link endpoint. The WebSocket handler at `packages/aid-server/src/ws/handler.ts` currently classifies `ideas.json` file changes as the `system` topic (the default fallback in `classifyFileChange()` at line 199). Adding `ideas` to the topic list and classification enables real-time kanban updates in Phase 1 Step 7.

**Implementation Detail:**

1. Add `'ideas'` to the `EVENT_TOPICS` array at line 12 of `packages/aid-server/src/ws/handler.ts`:
   ```typescript
   const EVENT_TOPICS = [
     'pipeline', 'pipeline.stage_log', 'evidence', 'decisions',
     'config', 'queue', 'audit', 'usage', 'queue.schedule', 'ideas', 'system',
   ] as const;
   ```

2. Add classification rule in `classifyFileChange()` before the `return 'system'` fallback:
   ```typescript
   if (relPath.includes('ideas.json')) return 'ideas';
   ```

3. In `packages/aid-server/src/routes/ideas.ts`, modify the POST handler to include `autoStatus: null` in the new idea object (line ~42-52).

4. Add the link endpoint after the existing DELETE handler:
   ```typescript
   router.put('/:ideaId/link', async (req: Request<IdeaParams>, res) => {
     const fs = registry.getFsReader(req.params.projectId);
     if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

     const { linkedPlan, linkedEpic } = req.body;
     if (linkedPlan === undefined && linkedEpic === undefined) {
       return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'Provide linkedPlan or linkedEpic' } });
     }

     const ideas = await readIdeas(fs);
     const idx = ideas.findIndex((i: any) => i.id === req.params.ideaId);
     if (idx === -1) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Idea not found' } });

     const idea = ideas[idx];
     if (linkedPlan !== undefined) idea.linkedPlan = linkedPlan;
     if (linkedEpic !== undefined) idea.linkedEpic = linkedEpic;

     // Compute autoStatus from linked resources
     if (idea.linkedEpic) {
       idea.autoStatus = 'epic'; // Will be upgraded to 'running'/'done' by WebSocket events
     } else if (idea.linkedPlan) {
       idea.autoStatus = 'plan';
     } else {
       idea.autoStatus = null;
     }

     idea.updatedAt = new Date().toISOString();
     ideas[idx] = idea;
     await saveIdeas(ideas, fs.aidoPath);
     res.json({ ok: true, data: idea });
   });
   ```

**Error Handling:**
- If `readIdeas()` returns an empty array because `ideas.json` does not exist yet, the endpoint returns 404 for the specific idea. The file is created on first POST.
- If both `linkedPlan` and `linkedEpic` are undefined in the request body, return 400 with a descriptive message.
- File write errors from `saveIdeas()` propagate as 500 (Express default error handler).

**Edge Cases:**
- Setting `linkedPlan` to `null` explicitly unlinks the plan and resets `autoStatus` to `null` (if no `linkedEpic` is set)
- Setting both `linkedPlan` and `linkedEpic` in one request — `autoStatus` prioritizes `linkedEpic` over `linkedPlan`
- Concurrent writes to `ideas.json` — chokidar may emit multiple events; the frontend's optimistic update pattern (already used in `IdeasToExecution.tsx` line ~handleDragEnd) handles this gracefully by reverting on error

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] `PUT /api/p/default/ideas/:id/link` with `{ linkedPlan: "P016" }` sets `autoStatus` to `"plan"` and returns updated idea
- [ ] `PUT /api/p/default/ideas/:id/link` with `{ linkedEpic: "E-016-1_3" }` sets `autoStatus` to `"epic"` and returns updated idea
- [ ] `PUT /api/p/default/ideas/:id/link` with `{ linkedPlan: null }` resets `autoStatus` to `null` when no `linkedEpic` is set
- [ ] WebSocket clients subscribed to `ideas` topic receive events when `ideas.json` changes on disk
- [ ] `POST /api/p/default/ideas` creates idea with `autoStatus: null`
- [ ] Existing CRUD operations (GET, POST, PUT, DELETE) continue to work unchanged

**Effort:** M
**AID Role:** backend

---

### Step 2: IDEAS.md Migration Service

**Objective:** Implement a server lifecycle service that imports ideas from `IDEAS.md` into `ideas.json` on startup (deduplicating by title) and exports `ideas.json` back to `IDEAS.md` format on graceful shutdown.

**Files:**
- Create: `packages/aid-server/src/services/ideas-migration.ts` — migration service class with `importFromMarkdown()` and `exportToMarkdown()` methods
- Modify: `packages/aid-server/src/index.ts` (lines ~30-50 server setup, ~70-80 shutdown handler) — register migration service lifecycle hooks

**Architecture Context:**
The migration service bridges the gap between offline use (IDEAS.md in project root) and GUI use (ideas.json at `.aid-o/04-engine/ideas.json`). The service hooks into the Express server lifecycle in `packages/aid-server/src/index.ts`: `importFromMarkdown()` runs after the server starts listening, and `exportToMarkdown()` runs during the SIGINT/SIGTERM shutdown handler (before `process.exit()`). The service uses `FsReader` from `packages/aid-server/src/services/fs-reader.ts` for file operations.

**Implementation Detail:**

1. Create `IdeasMigrationService` class:
   ```typescript
   export class IdeasMigrationService {
     constructor(private projectRoot: string, private aidoPath: string) {}

     async importFromMarkdown(): Promise<{ imported: number, skipped: number }> {
       const ideasMdPath = join(this.projectRoot, 'IDEAS.md');
       const ideasJsonPath = join(this.aidoPath, '04-engine', 'ideas.json');

       // Read IDEAS.md
       const mdContent = await readFile(ideasMdPath, 'utf-8').catch(() => null);
       if (!mdContent) return { imported: 0, skipped: 0 };

       // Parse markdown: look for ## headings as idea titles, text below as description
       const parsed = this.parseIdeasMd(mdContent);

       // Read existing ideas.json
       const existing: any[] = JSON.parse(
         await readFile(ideasJsonPath, 'utf-8').catch(() => '[]')
       );
       const existingTitles = new Set(existing.map(i => i.title.toLowerCase().trim()));

       // Merge: add ideas from MD that don't exist in JSON (deduplicate by title)
       let imported = 0;
       let skipped = 0;
       for (const idea of parsed) {
         if (existingTitles.has(idea.title.toLowerCase().trim())) {
           skipped++;
           continue;
         }
         existing.push({
           id: `idea-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
           title: idea.title,
           description: idea.description,
           tags: idea.tags,
           priority: 'medium',
           status: 'idea',
           linkedPlan: null,
           linkedEpic: null,
           autoStatus: null,
           createdAt: new Date().toISOString(),
           updatedAt: new Date().toISOString(),
         });
         imported++;
       }

       await mkdir(join(this.aidoPath, '04-engine'), { recursive: true });
       await writeFile(ideasJsonPath, JSON.stringify(existing, null, 2), 'utf-8');
       return { imported, skipped };
     }

     async exportToMarkdown(): Promise<void> { /* reverse operation */ }

     private parseIdeasMd(content: string): Array<{ title: string, description: string, tags: string[] }> {
       // Parse ## headings as titles, body text as description
       // Tags extracted from lines starting with "Tags:" or "#tag" patterns
     }
   }
   ```

2. In `packages/aid-server/src/index.ts`, after `server.listen()` callback:
   ```typescript
   const migration = new IdeasMigrationService(config.projectRoot, aidoPath);
   migration.importFromMarkdown()
     .then(r => console.log(`[migration] Imported ${r.imported} ideas, skipped ${r.skipped} duplicates`))
     .catch(e => console.warn('[migration] Import failed:', e.message));
   ```

3. In shutdown handler (SIGINT/SIGTERM), before `process.exit()`:
   ```typescript
   migration.exportToMarkdown()
     .then(() => console.log('[migration] Exported ideas to IDEAS.md'))
     .catch(e => console.warn('[migration] Export failed:', e.message))
     .finally(() => process.exit(0));
   ```

**Error Handling:**
- If `IDEAS.md` does not exist, `importFromMarkdown()` returns `{ imported: 0, skipped: 0 }` silently — no error logged
- If `ideas.json` is malformed, `JSON.parse()` throws — catch and initialize with empty array, log warning
- If the SIGTERM handler's export fails (write permission error), log the error but still exit — do not hang the process
- Backup: before overwriting IDEAS.md during export, write to `IDEAS.md.bak` first

**Edge Cases:**
- IDEAS.md contains only plain text without `##` headings — each non-empty paragraph becomes one idea with the first line as title
- IDEAS.md has duplicate titles within itself — only the first occurrence is imported
- ideas.json already contains all IDEAS.md entries — `imported: 0`, all skipped
- Empty IDEAS.md file — no ideas imported, no error
- Server killed with SIGKILL — export does not run; ideas.json remains valid from last write

**Dependencies:**
- Depends on: Step 1 — StoredIdea now includes `autoStatus: null` field in the schema

**Acceptance Criteria:**
- [ ] On server startup, ideas from `IDEAS.md` not already in `ideas.json` are added (deduplicated by case-insensitive title match)
- [ ] On server shutdown (SIGTERM), `ideas.json` contents are exported back to `IDEAS.md` in markdown format
- [ ] If `IDEAS.md` does not exist, startup completes without error and logs no warning
- [ ] If `ideas.json` does not exist, it is created during import
- [ ] Round-trip test: original IDEAS.md → import → export → diff shows no data loss for titles and descriptions

**Effort:** M
**AID Role:** backend

---

### Step 3: Backlog + Lessons-Learned Endpoints

**Objective:** Create two GET endpoints that parse existing markdown files (`backlog.md` and `lessons-learned.md`) into structured JSON arrays, and register them in the Express router.

**Files:**
- Create: `packages/aid-server/src/routes/backlog.ts` — GET `/api/p/:projectId/backlog` route
- Create: `packages/aid-server/src/routes/lessons.ts` — GET `/api/p/:projectId/lessons` route
- Modify: `packages/aid-server/src/index.ts` (lines ~40-55 route mounting) — mount backlog and lessons routes

**Architecture Context:**
These endpoints follow the existing route pattern in `packages/aid-server/src/routes/` — each file exports a factory function that receives `ProjectRegistry` and returns a `Router`. The routes use `FsReader.readText()` to read raw markdown content from `.aid-o/04-engine/memory/backlog.md` and `.aid-o/04-engine/lessons-learned.md`, then parse them into structured JSON. The parsed data feeds the Insights panel (Step 6) via the API client.

**Implementation Detail:**

1. **Backlog parser** (`packages/aid-server/src/routes/backlog.ts`):
   ```typescript
   export function backlogRoutes(registry: ProjectRegistry): Router {
     const router = Router({ mergeParams: true });

     router.get('/', async (req: Request<ProjectParams>, res) => {
       const fs = registry.getFsReader(req.params.projectId);
       if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

       const content = await fs.readText(
         join(fs.aidoPath, '04-engine', 'memory', 'backlog.md')
       );
       if (!content) return res.json({ ok: true, data: [] });

       const entries = parseBacklogMd(content);
       res.json({ ok: true, data: entries });
     });

     return router;
   }
   ```

   `parseBacklogMd()` algorithm:
   - Split content by `## ` headings to identify sections (Bugs, Features, Refactoring / Tech Debt)
   - Within each section, find markdown table rows (lines starting with `|` that are not header/separator rows)
   - For each row, split by `|`, trim cells, map to `BacklogEntry` fields:
     - Cell 0: `id` (e.g., "IMP-001")
     - Cell 1: `area` (e.g., "`CHANGELOG.md`" — strip backticks)
     - Cell 2: `suggestion` (full text, preserve markdown bold)
     - Cell 3: `priority` (lowercase: "critical", "high", "medium", "low")
     - Cell 4: `source`
     - Cell 5: `status` (lowercase: "pending", "proposed", "implemented", "deferred", "rejected")
   - Add `section` field from parent heading name

2. **Lessons parser** (`packages/aid-server/src/routes/lessons.ts`):
   - Split by `## ` headings
   - Main table (before `## Known Gotchas`): parse rows into `LessonEntry` with `category: 'lesson'`
   - Known Gotchas table: parse rows into `LessonEntry` with `category: 'gotcha'`, using `area` as `context`
   - Row format: `| Date | Lesson | Context |` → `{ date, lesson, context, category }`

3. **Mount in `index.ts`**:
   ```typescript
   import { backlogRoutes } from './routes/backlog.js';
   import { lessonsRoutes } from './routes/lessons.js';
   // After existing route mounts:
   app.use('/api/p/:projectId/backlog', backlogRoutes(registry));
   app.use('/api/p/:projectId/lessons', lessonsRoutes(registry));
   ```

**Error Handling:**
- File not found: return `{ ok: true, data: [] }` — graceful degradation, not an error
- Malformed markdown table (missing columns, extra pipes): skip the row, continue parsing, do not throw
- Empty file: return empty array

**Edge Cases:**
- Backlog.md has sections with no table rows (only heading + text) — return empty array for that section
- Table rows with `|` characters inside cell text (e.g., in code snippets) — split only on top-level `|` separators
- Lessons-learned.md has additional sections beyond the known two (e.g., "Credit Exhaustion During FIRST AID") — parse any section with a table as `category: 'lesson'`
- Table header/separator rows (`|---|---|---| `) — filter by checking if all cells are dashes

**Dependencies:**
- No dependencies — can start independently (parallel group with Step 1)

**Acceptance Criteria:**
- [ ] `GET /api/p/default/backlog` returns parsed entries from `.aid-o/04-engine/memory/backlog.md` with correct `id`, `area`, `suggestion`, `priority`, `source`, `status`, and `section` fields
- [ ] `GET /api/p/default/lessons` returns parsed entries from `.aid-o/04-engine/lessons-learned.md` with correct `date`, `lesson`, `context`, and `category` fields
- [ ] Known Gotchas entries have `category: 'gotcha'`, main table entries have `category: 'lesson'`
- [ ] Missing markdown files return `{ ok: true, data: [] }` with HTTP 200
- [ ] Malformed table rows are skipped without crashing the parser

**Effort:** M
**AID Role:** backend

---

### Step 4: Frontend Type Extensions + API Client + Store Slices

**Objective:** Extend frontend TypeScript types with new data models, add API client methods for new endpoints, and create two new Zustand store slices (CompanionSlice stub and InsightsSlice) to prepare the frontend for kanban rebuild and Insights panel.

**Files:**
- Modify: `packages/aid-gui/src/types/api.ts` (lines ~712-758) — add `autoStatus` to StoredIdea, add BacklogEntry, LessonEntry types, update IdeaCreateRequest and IdeaUpdateRequest
- Modify: `packages/aid-gui/src/types/ws.ts` (lines ~1-20) — add `'ideas'` to EventTopic union
- Modify: `packages/aid-gui/src/types/store.ts` — add InsightsSlice interface
- Modify: `packages/aid-gui/src/api/client.ts` (lines ~end) — add `linkIdea()`, `getBacklog()`, `getLessons()` methods to ApiClient
- Modify: `packages/aid-gui/src/store.ts` — add InsightsSlice with backlog and lessons state, integrate into store composition

**Architecture Context:**
The frontend types at `packages/aid-gui/src/types/api.ts` mirror server-side types and are the source of truth for frontend type safety. The API client at `packages/aid-gui/src/api/client.ts` uses a factory pattern (`createApiClient(projectId)`) returning an `ApiClient` interface with typed methods. The Zustand store at `packages/aid-gui/src/store.ts` is composed from 13 slices — this step adds 1 new slice (InsightsSlice) and extends the IdeasSlice with autoStatus awareness.

**Implementation Detail:**

1. **Type changes** in `packages/aid-gui/src/types/api.ts`:
   ```typescript
   // Add to StoredIdea:
   autoStatus: 'idea' | 'plan' | 'epic' | 'running' | 'done' | null;

   // Add to IdeaUpdateRequest:
   autoStatus?: 'idea' | 'plan' | 'epic' | 'running' | 'done' | null;

   // New types (add after StoredIdea section):
   export interface BacklogEntry {
     id: string;
     area: string;
     suggestion: string;
     priority: 'critical' | 'high' | 'medium' | 'low';
     source: string;
     status: 'pending' | 'proposed' | 'implemented' | 'deferred' | 'rejected';
     section: string;
   }

   export interface LessonEntry {
     date: string;
     lesson: string;
     context: string;
     category: 'lesson' | 'gotcha';
   }

   export interface IdeaLinkRequest {
     linkedPlan?: string | null;
     linkedEpic?: string | null;
   }
   ```

2. **WebSocket type changes** in `packages/aid-gui/src/types/ws.ts`:
   Add `'ideas'` to `EventTopic` type.

3. **API client methods** in `packages/aid-gui/src/api/client.ts`:
   ```typescript
   // Add to ApiClient interface:
   linkIdea(ideaId: string, req: IdeaLinkRequest): Promise<ApiResult<StoredIdea>>;
   getBacklog(): Promise<ApiResult<BacklogEntry[]>>;
   getLessons(): Promise<ApiResult<LessonEntry[]>>;

   // Implementations:
   linkIdea: (ideaId, req) => typedRequest(`${base}/ideas/${ideaId}/link`, 'PUT', req),
   getBacklog: () => typedFetch(`${base}/backlog`),
   getLessons: () => typedFetch(`${base}/lessons`),
   ```

4. **InsightsSlice** in `packages/aid-gui/src/store.ts`:
   ```typescript
   interface InsightsSlice {
     backlogEntries: BacklogEntry[];
     lessonEntries: LessonEntry[];
     insightsLoading: boolean;
     insightsActiveTab: 'backlog' | 'lessons';
     setBacklogEntries: (entries: BacklogEntry[]) => void;
     setLessonEntries: (entries: LessonEntry[]) => void;
     setInsightsLoading: (loading: boolean) => void;
     setInsightsActiveTab: (tab: 'backlog' | 'lessons') => void;
   }
   ```
   Add to the store composition alongside existing slices.

**Error Handling:**
- API client methods use the existing `typedFetch`/`typedRequest` error handling — network errors return `ApiResult` with `ok: false`
- Store slice initializes with empty arrays — no null checks needed in components

**Edge Cases:**
- `autoStatus` is `null` for existing ideas created before this change — backward compatible, kanban column mapping falls back to `status`
- `getBacklog()` and `getLessons()` return empty arrays when files don't exist — frontend renders "No entries" message

**Dependencies:**
- Depends on: Step 1 — backend must accept `autoStatus` field
- Depends on: Step 3 — backlog and lessons endpoints must exist

**Acceptance Criteria:**
- [ ] `StoredIdea` type includes `autoStatus` field that accepts `null` or one of `'idea' | 'plan' | 'epic' | 'running' | 'done'`
- [ ] `BacklogEntry` and `LessonEntry` types compile without errors
- [ ] `ApiClient.linkIdea()` calls `PUT /api/p/:id/ideas/:ideaId/link` with correct payload
- [ ] `ApiClient.getBacklog()` and `ApiClient.getLessons()` return typed results
- [ ] `InsightsSlice` state initializes with empty arrays and `insightsLoading: false`
- [ ] TypeScript compilation passes with zero errors (`npx tsc --noEmit` in `packages/aid-gui/`)

**Effort:** M
**AID Role:** frontend

---

### Step 5: 5-Column Kanban Rebuild with Multi-Select

**Objective:** Rebuild the kanban board in `IdeasToExecution.tsx` from 4 columns (`idea`, `exploring`, `planned`, `done`) to 5 columns (`Ideas`, `Plan`, `EPIC`, `Running`, `Done`) with checkbox multi-select and a "Create Plan" action button that appears when ideas are selected.

**Files:**
- Modify: `packages/aid-gui/src/screens/IdeasToExecution.tsx` (lines ~1-end, full rewrite of column definitions, card rendering, and drag-drop logic)
- Modify: `packages/aid-gui/src/store.ts` — add `selectedIdeaIds: Set<string>` and `toggleIdeaSelection`/`clearIdeaSelection` to IdeasSlice

**Architecture Context:**
The current kanban at `packages/aid-gui/src/screens/IdeasToExecution.tsx` uses `@dnd-kit/core` with `PointerSensor` (8px activation distance) and `closestCorners` collision detection. Cards are wrapped in `SortableContext` per column. The column mapping is currently `['idea', 'exploring', 'planned', 'done']` which maps directly to the `status` field. The new 5-column layout maps to `autoStatus ?? status`, with a column-to-value mapping: `{ Ideas: ['idea', 'exploring'], Plan: ['plan', 'planned'], EPIC: ['epic'], Running: ['running'], Done: ['done'] }`. The old `exploring` and `planned` statuses map to Ideas and Plan columns respectively for backward compatibility.

**Implementation Detail:**

1. **Column definition** — replace the hardcoded `['idea', 'exploring', 'planned', 'done']` array:
   ```typescript
   const COLUMNS = [
     { id: 'ideas', label: 'Ideas', statuses: ['idea', 'exploring'] },
     { id: 'plan', label: 'Plan', statuses: ['plan', 'planned'] },
     { id: 'epic', label: 'EPIC', statuses: ['epic'] },
     { id: 'running', label: 'Running', statuses: ['running'] },
     { id: 'done', label: 'Done', statuses: ['done'] },
   ] as const;

   function getColumnForIdea(idea: StoredIdea): string {
     const effectiveStatus = idea.autoStatus ?? idea.status;
     const col = COLUMNS.find(c => c.statuses.includes(effectiveStatus as any));
     return col?.id ?? 'ideas'; // fallback to Ideas column
   }
   ```

2. **Multi-select state** — add to IdeasSlice in store:
   ```typescript
   selectedIdeaIds: string[];
   toggleIdeaSelection: (ideaId: string) => void;
   clearIdeaSelection: () => void;
   ```

3. **Card checkbox** — add to `SortableCard` component:
   ```tsx
   <input
     type="checkbox"
     checked={selectedIdeaIds.includes(idea.id)}
     onChange={(e) => { e.stopPropagation(); toggleIdeaSelection(idea.id); }}
     className="mr-2 h-4 w-4 rounded border-gray-600 bg-gray-700"
   />
   ```
   Only show checkboxes on cards in the `Ideas` column.

4. **"Create Plan" button** — render above the kanban when `selectedIdeaIds.length > 0`:
   ```tsx
   {selectedIdeaIds.length > 0 && (
     <div className="mb-4 flex items-center gap-3 rounded-lg bg-blue-500/10 border border-blue-500/30 px-4 py-3">
       <span className="text-sm text-blue-400">
         {selectedIdeaIds.length} idea{selectedIdeaIds.length > 1 ? 's' : ''} selected
       </span>
       <button
         onClick={() => {
           const titles = ideas
             .filter(i => selectedIdeaIds.includes(i.id))
             .map(i => i.title);
           if (confirm(`Create plan from:\n${titles.map(t => `• ${t}`).join('\n')}`)) {
             // Stub: actual plan creation via AI Companion in Phase 2
             clearIdeaSelection();
           }
         }}
         className="rounded-md bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500"
       >
         Create Plan
       </button>
     </div>
   )}
   ```

5. **Drag-drop update** — modify `handleDragEnd` to map column IDs back to status values:
   ```typescript
   // When dropping to a column, set status/autoStatus accordingly:
   const targetColumn = COLUMNS.find(c => c.id === overColumnId);
   if (targetColumn) {
     const newStatus = targetColumn.statuses[0]; // primary status for the column
     await client.updateIdea(ideaId, { status: newStatus as any });
   }
   ```

6. **Column styling** — each column gets a distinct header color:
   - Ideas: gray-500 border-top
   - Plan: blue-500 border-top
   - EPIC: purple-500 border-top
   - Running: amber-500 border-top with pulse animation on cards
   - Done: green-500 border-top

**Error Handling:**
- Drag-drop uses optimistic updates with rollback on API error (existing pattern from current `handleDragEnd`)
- If `autoStatus` is an unexpected value, `getColumnForIdea()` falls back to `'ideas'` column

**Edge Cases:**
- Ideas with `status: 'exploring'` (old value) appear in the Ideas column, not a separate column
- Ideas with `status: 'planned'` (old value) appear in the Plan column
- Selecting ideas across multiple columns — only Ideas column cards have checkboxes, so this cannot happen
- Empty columns render with minimum height and a subtle dashed border placeholder
- Dragging a card from Done back to Ideas — allowed, updates status to 'idea'

**Dependencies:**
- Depends on: Step 4 — frontend types must include `autoStatus`, `selectedIdeaIds` in store

**Acceptance Criteria:**
- [ ] Kanban renders 5 columns with labels: Ideas, Plan, EPIC, Running, Done
- [ ] Ideas are placed in columns based on `autoStatus ?? status` mapping
- [ ] Existing ideas with `status: 'idea'` appear in the Ideas column
- [ ] Existing ideas with `status: 'planned'` appear in the Plan column
- [ ] Checkbox appears on cards in the Ideas column only
- [ ] Selecting 1+ ideas shows "Create Plan" button with count and selected titles
- [ ] "Create Plan" shows confirmation dialog listing selected idea titles (stub action)
- [ ] Drag-and-drop between columns updates the idea's status via API call
- [ ] Empty columns show placeholder content

**Effort:** L
**AID Role:** frontend

---

### Step 6: Insights Panel

**Objective:** Build an Insights panel below the kanban with two tabs (Backlog and Lessons Learned) that displays parsed entries from the API and supports dragging backlog entries onto the kanban Ideas column to create new ideas.

**Files:**
- Create: `packages/aid-gui/src/components/InsightsPanel.tsx` — tabbed panel component with Backlog and Lessons tabs
- Modify: `packages/aid-gui/src/screens/IdeasToExecution.tsx` (lines ~end) — render InsightsPanel below the kanban board, wire drag-from-insights-to-kanban

**Architecture Context:**
The Insights panel is a new component rendered below the kanban in `IdeasToExecution.tsx`. It uses the `InsightsSlice` from the store (Step 4) for state and the API client methods `getBacklog()` and `getLessons()` for data fetching. The drag-to-kanban feature uses the existing `@dnd-kit/core` context from the kanban — the InsightsPanel lives inside the same `DndContext` and its entries act as draggable sources that drop into the kanban's Ideas column `SortableContext`.

**Implementation Detail:**

1. **InsightsPanel component**:
   ```tsx
   export function InsightsPanel({ projectId }: { projectId: string }) {
     const { backlogEntries, lessonEntries, insightsLoading,
             insightsActiveTab, setInsightsActiveTab,
             setBacklogEntries, setLessonEntries, setInsightsLoading } = useStore();
     const client = createApiClient(projectId);

     useEffect(() => {
       setInsightsLoading(true);
       Promise.all([client.getBacklog(), client.getLessons()])
         .then(([backlog, lessons]) => {
           if (backlog.ok) setBacklogEntries(backlog.data);
           if (lessons.ok) setLessonEntries(lessons.data);
         })
         .finally(() => setInsightsLoading(false));
     }, [projectId]);

     return (
       <div className="mt-6 rounded-xl border border-gray-700 bg-gray-800/50">
         {/* Tab headers */}
         <div className="flex border-b border-gray-700">
           <TabButton active={insightsActiveTab === 'backlog'} onClick={() => setInsightsActiveTab('backlog')}>
             Backlog ({backlogEntries.length})
           </TabButton>
           <TabButton active={insightsActiveTab === 'lessons'} onClick={() => setInsightsActiveTab('lessons')}>
             Lessons Learned ({lessonEntries.length})
           </TabButton>
         </div>
         {/* Tab content */}
         {insightsActiveTab === 'backlog' ? (
           <BacklogTab entries={backlogEntries} />
         ) : (
           <LessonsTab entries={lessonEntries} />
         )}
       </div>
     );
   }
   ```

2. **BacklogTab** — renders entries with priority badges (red for critical, orange for high, yellow for medium, gray for low), status indicator, and section label. Each entry is wrapped in a `useDraggable()` from dnd-kit so it can be dragged to the kanban.

3. **LessonsTab** — renders entries grouped by category (lessons vs gotchas). Each entry shows date, lesson text (truncated to 2 lines with expand), and context badge.

4. **Drag-to-kanban** — when a backlog entry is dropped on the Ideas column:
   ```typescript
   // In IdeasToExecution.tsx handleDragEnd:
   if (active.data.current?.type === 'backlog-entry') {
     const entry = active.data.current.entry as BacklogEntry;
     await client.createIdea({
       title: entry.id + ': ' + entry.area,
       description: entry.suggestion,
       tags: [entry.section.toLowerCase(), entry.priority],
       priority: entry.priority === 'critical' ? 'high' : entry.priority as any,
     });
   }
   ```

5. **Radix Tabs** — use `@radix-ui/react-tabs` (already a dependency in package.json) for accessible tab switching.

**Error Handling:**
- API fetch failure: show "Failed to load" message with retry button in the panel
- Empty data: show "No backlog entries" or "No lessons recorded" placeholder text

**Edge Cases:**
- Backlog.md does not exist: API returns empty array, panel shows "No backlog entries yet"
- Very long suggestion text in backlog entries: truncate to 3 lines with "Show more" toggle
- Dragging a backlog entry but dropping outside a valid column: no-op, entry returns to its position in the panel
- Duplicate drag: dragging the same backlog entry twice creates two separate ideas (acceptable — user can delete duplicates)

**Dependencies:**
- Depends on: Step 3 — backlog and lessons API endpoints must be available
- Depends on: Step 4 — InsightsSlice must exist in store
- Depends on: Step 5 — kanban must be rebuilt with DndContext that accepts external draggable sources

**Acceptance Criteria:**
- [ ] Insights panel renders below the kanban with two tabs: "Backlog" and "Lessons Learned"
- [ ] Backlog tab shows entries with priority badges (color-coded: red/orange/yellow/gray) and status indicators
- [ ] Lessons tab shows entries grouped by category with date and context
- [ ] Tab headers show entry counts (e.g., "Backlog (28)")
- [ ] Dragging a backlog entry onto the Ideas kanban column creates a new idea with the entry's data
- [ ] Loading state shows skeleton animation during API fetch

**Effort:** L
**AID Role:** frontend

---

### Step 7: WebSocket Ideas Subscription

**Objective:** Subscribe to the `ideas` WebSocket topic in `useWebSocket.ts` so that idea changes made by other clients or server-side processes update the kanban in real-time without requiring a page refresh.

**Files:**
- Modify: `packages/aid-gui/src/hooks/useWebSocket.ts` (lines ~58-65 DEFAULT_TOPICS, ~120-233 dispatchEvent) — add `'ideas'` to default subscriptions and handle `ideas` topic events

**Architecture Context:**
The WebSocket hook at `packages/aid-gui/src/hooks/useWebSocket.ts` subscribes to a fixed list of topics (`DEFAULT_TOPICS` at line 58) on connection and dispatches incoming events to the Zustand store via `dispatchEvent()` at line 120. The `ideas` topic was registered on the server side in Step 1 (added to `EVENT_TOPICS` and `classifyFileChange()`). This step completes the circuit by subscribing the frontend and dispatching received data to the IdeasSlice.

**Implementation Detail:**

1. **Add topic** to `DEFAULT_TOPICS` at line 58:
   ```typescript
   const DEFAULT_TOPICS: EventTopic[] = [
     'pipeline',
     'pipeline.stage_log',
     'queue',
     'decisions',
     'usage',
     'audit',
     'ideas',  // NEW
   ];
   ```

2. **Add dispatch handler** in `dispatchEvent()` switch statement (after the `audit` case):
   ```typescript
   case 'ideas': {
     if (data.type === 'file_change' && data.parsedData != null) {
       const parsed = data.parsedData;
       if (Array.isArray(parsed)) {
         store.setIdeas(parsed as StoredIdea[]);
       }
     }
     break;
   }
   ```

3. **Add ideas resync** to `resyncFromRest()` — add `client.getIdeas()` to the `Promise.allSettled` call and dispatch result to `store.setIdeas()`.

**Error Handling:**
- If `parsedData` is not an array (e.g., file was partially written), silently ignore the event — the store retains its current ideas state
- If the ideas resync fails during reconnect, the store keeps the last known state — ideas will be refreshed on next user action

**Edge Cases:**
- Rapid successive file writes (e.g., migration importing 20 ideas) — chokidar may batch or debounce events; the frontend receives the final state since it reads the full `ideas.json` on each event
- Large `ideas.json` (100+ ideas) sent over WebSocket — the entire JSON array is transmitted; for typical usage this is under 50KB
- WebSocket disconnected during idea creation — the optimistic update in the kanban still shows the new idea; on reconnect, `resyncFromRest()` fetches the authoritative state

**Dependencies:**
- Depends on: Step 1 — server must emit `ideas` topic events when `ideas.json` changes
- Depends on: Step 4 — frontend `EventTopic` type must include `'ideas'`

**Acceptance Criteria:**
- [ ] WebSocket subscribe message includes `'ideas'` topic
- [ ] When `ideas.json` is modified on disk, all connected clients receive the updated ideas array via WebSocket
- [ ] Kanban updates in real-time when another process modifies `ideas.json` (no page refresh needed)
- [ ] On WebSocket reconnect, ideas are resynced from REST API

**Effort:** S
**AID Role:** frontend

---

### Step 8: Phase 1 Verification — Vitest + Playwright

**Objective:** Write Vitest unit tests for Phase 1 backend services (migration, parsers, link endpoint) and frontend slices, plus create the Playwright test infrastructure and a Phase 1 smoke test.

**Files:**
- Create: `packages/aid-gui/tests/server/services/migration.test.ts` — unit tests for IdeasMigrationService
- Create: `packages/aid-gui/tests/server/parsers/backlog.test.ts` — unit tests for backlog.md parser
- Create: `packages/aid-gui/tests/server/parsers/lessons.test.ts` — unit tests for lessons-learned.md parser
- Create: `packages/aid-gui/tests/server/api/ideas-link.test.ts` — unit tests for ideas link endpoint
- Create: `packages/aid-gui/tests/frontend/store-insights.test.ts` — unit tests for InsightsSlice
- Create: `packages/aid-gui/playwright.config.ts` — Playwright configuration
- Create: `packages/aid-gui/tests/e2e/phase1-kanban.spec.ts` — Playwright smoke test
- Modify: `packages/aid-gui/package.json` — add `@playwright/test` dev dependency and `test:e2e` script

**Architecture Context:**
Vitest tests follow the existing pattern in `packages/aid-gui/tests/` — server tests use direct function imports, frontend tests use `useStore.getState()` and `useStore.setState()` for store slice testing (as seen in `tests/frontend/store.test.ts`). Playwright is new to this project — the config file sets up a dev server, browser context, and base URL. The E2E test visits the Ideas page and verifies the kanban renders correctly.

**Implementation Detail:**

1. **Migration tests** (`migration.test.ts`):
   - Test: parse IDEAS.md with 3 ideas → returns 3 parsed entries
   - Test: import to empty ideas.json → all 3 imported
   - Test: import with 2 duplicates → only 1 imported, 2 skipped
   - Test: IDEAS.md not found → returns { imported: 0, skipped: 0 }
   - Test: export → IDEAS.md round-trip preserves titles and descriptions

2. **Backlog parser tests** (`backlog.test.ts`):
   - Test: parse sample backlog table → correct BacklogEntry fields
   - Test: parse multi-section file → entries have correct `section` field
   - Test: malformed row (missing columns) → row skipped
   - Test: empty file → returns empty array

3. **Lessons parser tests** (`lessons.test.ts`):
   - Test: parse main table → entries with `category: 'lesson'`
   - Test: parse Known Gotchas → entries with `category: 'gotcha'`
   - Test: empty file → returns empty array

4. **Ideas link endpoint test** (`ideas-link.test.ts`):
   - Test: link plan → autoStatus set to 'plan'
   - Test: link epic → autoStatus set to 'epic'
   - Test: unlink all → autoStatus set to null
   - Test: idea not found → 404
   - Test: no body fields → 400

5. **InsightsSlice tests** (`store-insights.test.ts`):
   - Test: initial state → empty arrays, loading false
   - Test: setBacklogEntries → updates state
   - Test: setInsightsActiveTab → toggles between 'backlog' and 'lessons'

6. **Playwright config** (`playwright.config.ts`):
   ```typescript
   import { defineConfig } from '@playwright/test';
   export default defineConfig({
     testDir: './tests/e2e',
     use: { baseURL: 'http://localhost:9911' },
     webServer: {
       command: 'cd ../.. && docker compose up --build -d && sleep 5',
       url: 'http://localhost:9911/api/health',
       reuseExistingServer: true,
       timeout: 120000,
     },
     retries: 1,
   });
   ```

7. **Playwright smoke test** (`phase1-kanban.spec.ts`):
   ```typescript
   test('kanban renders 5 columns', async ({ page }) => {
     await page.goto('/ideas');
     await expect(page.getByText('Ideas')).toBeVisible();
     await expect(page.getByText('Plan')).toBeVisible();
     await expect(page.getByText('EPIC')).toBeVisible();
     await expect(page.getByText('Running')).toBeVisible();
     await expect(page.getByText('Done')).toBeVisible();
   });

   test('insights panel renders with tabs', async ({ page }) => {
     await page.goto('/ideas');
     await expect(page.getByText('Backlog')).toBeVisible();
     await expect(page.getByText('Lessons Learned')).toBeVisible();
   });
   ```

**Error Handling:**
- Playwright `webServer` timeout set to 120s to allow Docker build time
- Vitest tests use `beforeEach` reset via `useStore.getInitialState()` pattern (existing convention)

**Edge Cases:**
- Docker not running when Playwright test starts — `webServer` command handles build; if Docker daemon is down, test fails with clear error message from `docker compose up`
- Port 9911 already in use — `reuseExistingServer: true` skips starting a new server

**Dependencies:**
- Depends on: Steps 1-7 — all Phase 1 features must be implemented

**Acceptance Criteria:**
- [ ] `npx vitest run` passes all new test files with zero failures
- [ ] Migration tests verify import, deduplication, and round-trip
- [ ] Backlog parser tests verify correct field extraction from markdown tables
- [ ] Lessons parser tests verify category assignment (lesson vs gotcha)
- [ ] Playwright config exists at `packages/aid-gui/playwright.config.ts`
- [ ] `npx playwright test tests/e2e/phase1-kanban.spec.ts` passes: 5-column kanban visible, insights panel tabs visible
- [ ] All existing tests continue to pass (regression)

**Effort:** L
**AID Role:** qa

---

### Step 9: CompanionService Interface + Adapter Architecture

**Objective:** Design and implement the CompanionService TypeScript interface, create the adapter directory structure, and implement the auto-detection service that selects the best available adapter at server startup.

**Files:**
- Create: `packages/aid-server/src/companion/types.ts` — CompanionService interface, CompanionMessage, CompanionSession types
- Create: `packages/aid-server/src/companion/index.ts` — barrel export
- Create: `packages/aid-server/src/companion/auto-detect.ts` — auto-detection logic: ai-sdk-provider → CLI proxy → none
- Create: `packages/aid-server/src/companion/session-store.ts` — JSONL-based session persistence

**Architecture Context:**
The companion directory at `packages/aid-server/src/companion/` is a new module following the existing service pattern (`packages/aid-server/src/services/`). The CompanionService interface defines the adapter contract that both the ai-sdk-provider adapter (Step 10) and CLI proxy adapter (Step 11) will implement. The auto-detection service runs once at server startup and caches the result — subsequent requests use the cached adapter. Session persistence uses JSONL files in `.aid-o/04-engine/companion-sessions/` for simplicity (no database dependency).

**Implementation Detail:**

1. **CompanionService interface** (`types.ts`):
   ```typescript
   import { Readable } from 'node:stream';

   export interface CompanionService {
     readonly adapterName: 'ai-sdk' | 'cli-proxy' | 'none';
     readonly available: boolean;

     send(message: string, options: SendOptions): Promise<CompanionResponse>;
     stream(message: string, options: SendOptions): AsyncGenerator<StreamChunk>;
     isAvailable(): Promise<boolean>;
   }

   export interface SendOptions {
     sessionId?: string;
     hintCommand?: string;
     projectRoot?: string;
   }

   export interface CompanionResponse {
     content: string;
     sessionId: string;
     adapter: 'ai-sdk' | 'cli-proxy';
   }

   export type StreamChunk =
     | { type: 'text'; content: string }
     | { type: 'done'; sessionId: string; fullContent: string }
     | { type: 'error'; message: string };
   ```

2. **Auto-detection** (`auto-detect.ts`):
   ```typescript
   export async function detectCompanionAdapter(): Promise<CompanionService> {
     // Strategy 1: Try ai-sdk-provider-claude-code
     try {
       const { claudeCode } = await import('ai-sdk-provider-claude-code');
       const { generateText } = await import('ai');
       // Quick probe: generate a single token to verify it works
       const probe = await generateText({
         model: claudeCode('sonnet'),
         prompt: 'Reply with OK',
         maxSteps: 1,
       });
       if (probe.text) {
         return new AiSdkAdapter(claudeCode, generateText, streamText);
       }
     } catch {
       // ai-sdk-provider not available or failed
     }

     // Strategy 2: Check if claude CLI is in PATH
     try {
       const { execFileSync } = await import('node:child_process');
       execFileSync('claude', ['--version'], { timeout: 5000, stdio: 'pipe' });
       return new CliProxyAdapter();
     } catch {
       // claude CLI not available
     }

     // Strategy 3: No adapter available
     return new StubAdapter();
   }
   ```

3. **Session store** (`session-store.ts`):
   ```typescript
   export class SessionStore {
     constructor(private sessionsDir: string) {}

     async save(session: CompanionSession): Promise<void> {
       const filePath = join(this.sessionsDir, `${session.id}.jsonl`);
       await mkdir(this.sessionsDir, { recursive: true });
       const lines = session.messages.map(m => JSON.stringify(m)).join('\n') + '\n';
       await writeFile(filePath, lines, 'utf-8');
     }

     async load(sessionId: string): Promise<CompanionSession | null> { /* read JSONL */ }
     async list(): Promise<CompanionSession[]> { /* list directory, read headers */ }
   }
   ```

**Error Handling:**
- Auto-detection probe timeout: 10s for ai-sdk-provider, 5s for CLI version check
- If ai-sdk-provider probe fails with network error: fall through to CLI proxy
- If both adapters fail: return StubAdapter that returns `available: false` and meaningful error messages
- Session store write failures: log warning but do not crash the server

**Edge Cases:**
- Server running in Docker without `claude` CLI installed: ai-sdk-provider may still work if `ai-sdk-provider-claude-code` is installed (it uses its own detection mechanism)
- Both adapters available: ai-sdk-provider takes priority (better DX)
- Session directory does not exist: `mkdir({ recursive: true })` creates it on first save
- Corrupt JSONL session file: skip malformed lines, return partial session

**Dependencies:**
- No dependencies — can start independently (first step of Phase 2)

**Acceptance Criteria:**
- [ ] `CompanionService` interface defines `send()`, `stream()`, `isAvailable()` methods with correct return types
- [ ] `detectCompanionAdapter()` returns `AiSdkAdapter` when `ai-sdk-provider-claude-code` is available
- [ ] `detectCompanionAdapter()` returns `CliProxyAdapter` when only `claude` CLI is available
- [ ] `detectCompanionAdapter()` returns `StubAdapter` when neither is available
- [ ] `SessionStore.save()` persists messages as JSONL to `.aid-o/04-engine/companion-sessions/`
- [ ] `SessionStore.list()` returns session metadata without loading full message history

**Effort:** M
**AID Role:** architect

---

### Step 10: ai-sdk-provider Adapter

**Objective:** Implement the primary CompanionService adapter using `ai-sdk-provider-claude-code` and the `ai` package, with streaming support via `streamText()` and session persistence.

**Files:**
- Create: `packages/aid-server/src/companion/ai-sdk-adapter.ts` — AiSdkAdapter class implementing CompanionService
- Modify: `packages/aid-server/package.json` — add `ai` and `ai-sdk-provider-claude-code` dependencies
- Modify: `packages/aid-gui/package.json` — add `ai` and `ai-sdk-provider-claude-code` dependencies (shared workspace)

**Architecture Context:**
The AiSdkAdapter is the primary CompanionService implementation, selected by the auto-detection in Step 9. It uses `ai-sdk-provider-claude-code` which provides `claudeCode()` model factory that works with Claude Code subscription auth (no API key needed). The `ai` package provides `generateText()` for single responses and `streamText()` for streaming. The adapter wraps these in the CompanionService interface and handles session persistence via SessionStore.

**Implementation Detail:**

1. **AiSdkAdapter class**:
   ```typescript
   import type { CompanionService, SendOptions, CompanionResponse, StreamChunk } from './types.js';
   import { SessionStore } from './session-store.js';
   import { randomUUID } from 'node:crypto';

   export class AiSdkAdapter implements CompanionService {
     readonly adapterName = 'ai-sdk' as const;
     readonly available = true;
     private sessionStore: SessionStore;

     constructor(
       private claudeCode: typeof import('ai-sdk-provider-claude-code').claudeCode,
       private generateTextFn: typeof import('ai').generateText,
       private streamTextFn: typeof import('ai').streamText,
       sessionsDir: string,
     ) {
       this.sessionStore = new SessionStore(sessionsDir);
     }

     async send(message: string, options: SendOptions): Promise<CompanionResponse> {
       const sessionId = options.sessionId ?? randomUUID();
       const prompt = this.buildPrompt(message, options);

       const result = await this.generateTextFn({
         model: this.claudeCode('sonnet'),
         prompt,
         maxSteps: 1,
       });

       await this.sessionStore.appendMessage(sessionId, {
         id: randomUUID(),
         role: 'user',
         content: message,
         timestamp: new Date().toISOString(),
         hintCommand: options.hintCommand,
       });
       await this.sessionStore.appendMessage(sessionId, {
         id: randomUUID(),
         role: 'assistant',
         content: result.text,
         timestamp: new Date().toISOString(),
       });

       return { content: result.text, sessionId, adapter: 'ai-sdk' };
     }

     async *stream(message: string, options: SendOptions): AsyncGenerator<StreamChunk> {
       const sessionId = options.sessionId ?? randomUUID();
       const prompt = this.buildPrompt(message, options);

       const result = this.streamTextFn({
         model: this.claudeCode('sonnet'),
         prompt,
         maxSteps: 1,
       });

       let fullContent = '';
       for await (const chunk of result.textStream) {
         fullContent += chunk;
         yield { type: 'text', content: chunk };
       }

       // Persist both messages
       await this.sessionStore.appendMessage(sessionId, {
         id: randomUUID(), role: 'user', content: message,
         timestamp: new Date().toISOString(), hintCommand: options.hintCommand,
       });
       await this.sessionStore.appendMessage(sessionId, {
         id: randomUUID(), role: 'assistant', content: fullContent,
         timestamp: new Date().toISOString(),
       });

       yield { type: 'done', sessionId, fullContent };
     }

     async isAvailable(): Promise<boolean> { return true; }

     private buildPrompt(message: string, options: SendOptions): string {
       if (options.hintCommand) {
         return HINT_TEMPLATES[options.hintCommand]?.replace('{message}', message) ?? message;
       }
       return message;
     }
   }
   ```

2. **Model selection** — use `'sonnet'` as the default model name (verified working in brainstorming session). Model names for `ai-sdk-provider-claude-code` are short aliases: `opus`, `sonnet`, `haiku`.

3. **npm dependencies** — add to `packages/aid-server/package.json`:
   ```json
   "ai": "^4.3.0",
   "ai-sdk-provider-claude-code": "^0.1.0"
   ```

**Error Handling:**
- `streamText()` network error mid-stream: yield `{ type: 'error', message: 'Connection lost during streaming' }` and close the generator
- `generateText()` timeout: wrap in `Promise.race()` with 60s timeout, return error response
- ai-sdk-provider auth failure (subscription expired): catch and yield descriptive error chunk

**Edge Cases:**
- Very long responses (>10K tokens): streaming handles this naturally, no buffer overflow
- Concurrent requests to the same session: session store uses append-only JSONL, concurrent writes are safe at the line level
- Empty message string: return error response "Message cannot be empty"

**Dependencies:**
- Depends on: Step 9 — CompanionService interface and SessionStore must exist

**Acceptance Criteria:**
- [ ] `AiSdkAdapter.send()` returns a complete response with `content`, `sessionId`, and `adapter: 'ai-sdk'`
- [ ] `AiSdkAdapter.stream()` yields text chunks followed by a `done` chunk with the full content
- [ ] Session messages are persisted to JSONL files in `.aid-o/04-engine/companion-sessions/`
- [ ] `ai` and `ai-sdk-provider-claude-code` are listed in `package.json` dependencies
- [ ] Model name `'sonnet'` is used (not full model ID)

**Effort:** M
**AID Role:** backend

---

### Step 11: CLI Proxy Fallback Adapter

**Objective:** Implement the fallback CompanionService adapter that spawns `claude -p` as a child process, parses NDJSON stream output, and provides the same interface as the ai-sdk-provider adapter.

**Files:**
- Create: `packages/aid-server/src/companion/cli-proxy-adapter.ts` — CliProxyAdapter class implementing CompanionService

**Architecture Context:**
The CliProxyAdapter is the fallback adapter when `ai-sdk-provider-claude-code` is not available. It spawns `claude -p "prompt" --output-format stream-json --verbose --max-turns 1` as a child process using Node.js `child_process.spawn()`. The `--output-format stream-json` flag produces NDJSON (newline-delimited JSON) on stdout where each line is a JSON object with a `type` field. The adapter parses this stream and maps it to the `StreamChunk` type. Session persistence uses the same `SessionStore` as the ai-sdk adapter.

**Implementation Detail:**

1. **CliProxyAdapter class**:
   ```typescript
   import { spawn } from 'node:child_process';
   import { randomUUID } from 'node:crypto';
   import type { CompanionService, SendOptions, CompanionResponse, StreamChunk } from './types.js';
   import { SessionStore } from './session-store.js';

   export class CliProxyAdapter implements CompanionService {
     readonly adapterName = 'cli-proxy' as const;
     readonly available = true;
     private sessionStore: SessionStore;

     constructor(sessionsDir: string) {
       this.sessionStore = new SessionStore(sessionsDir);
     }

     async *stream(message: string, options: SendOptions): AsyncGenerator<StreamChunk> {
       const sessionId = options.sessionId ?? randomUUID();
       const prompt = this.buildPrompt(message, options);

       const proc = spawn('claude', [
         '-p', prompt,
         '--output-format', 'stream-json',
         '--verbose',
         '--max-turns', '1',
       ], {
         stdio: ['pipe', 'pipe', 'pipe'],
         env: { ...process.env },
         timeout: 60000,
       });

       let fullContent = '';

       // Parse NDJSON from stdout
       let buffer = '';
       for await (const chunk of proc.stdout) {
         buffer += chunk.toString();
         const lines = buffer.split('\n');
         buffer = lines.pop() ?? ''; // keep incomplete line in buffer

         for (const line of lines) {
           if (!line.trim()) continue;
           try {
             const parsed = JSON.parse(line);
             if (parsed.type === 'assistant' && parsed.message?.content) {
               for (const block of parsed.message.content) {
                 if (block.type === 'text') {
                   fullContent += block.text;
                   yield { type: 'text', content: block.text };
                 }
               }
             }
           } catch {
             // Skip unparseable lines (CLI banners, debug prefixes, empty lines)
           }
         }
       }

       // Handle remaining buffer
       if (buffer.trim()) {
         try {
           const parsed = JSON.parse(buffer);
           if (parsed.type === 'assistant' && parsed.message?.content) {
             for (const block of parsed.message.content) {
               if (block.type === 'text') {
                 fullContent += block.text;
                 yield { type: 'text', content: block.text };
               }
             }
           }
         } catch { /* ignore */ }
       }

       // Persist session
       await this.sessionStore.appendMessage(sessionId, {
         id: randomUUID(), role: 'user', content: message,
         timestamp: new Date().toISOString(), hintCommand: options.hintCommand,
       });
       await this.sessionStore.appendMessage(sessionId, {
         id: randomUUID(), role: 'assistant', content: fullContent,
         timestamp: new Date().toISOString(),
       });

       yield { type: 'done', sessionId, fullContent };
     }

     async send(message: string, options: SendOptions): Promise<CompanionResponse> {
       let result: CompanionResponse = { content: '', sessionId: '', adapter: 'cli-proxy' };
       for await (const chunk of this.stream(message, options)) {
         if (chunk.type === 'done') {
           result = { content: chunk.fullContent, sessionId: chunk.sessionId, adapter: 'cli-proxy' };
         }
       }
       return result;
     }

     async isAvailable(): Promise<boolean> {
       try {
         const { execFileSync } = await import('node:child_process');
         execFileSync('claude', ['--version'], { timeout: 5000, stdio: 'pipe' });
         return true;
       } catch { return false; }
     }
   }
   ```

2. **NDJSON parsing** — the `--output-format stream-json` output format produces lines like:
   ```json
   {"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}
   ```
   The parser extracts `text` blocks from `message.content` array.

3. **Environment** — the spawned process inherits `process.env` but does NOT inherit `CLAUDECODE` env var (which would trigger nested session detection). Filter it out:
   ```typescript
   const env = { ...process.env };
   delete env.CLAUDECODE;
   delete env.CLAUDE_CODE_ENTRYPOINT;
   ```

**Error Handling:**
- Process exits with non-zero code: yield `{ type: 'error', message: 'CLI proxy failed with exit code X' }`
- Process timeout (60s): kill the process and yield error chunk
- stderr output: collect and include in error message if process fails
- `claude` not in PATH: `isAvailable()` returns false, auto-detection skips this adapter

**Edge Cases:**
- Claude CLI prompts for authentication interactively: `--max-turns 1` and pipe stdin prevent hanging; process timeout catches any remaining cases
- Very long prompts (>10K chars): pass via `-p` argument; if argument too long, write to temp file and use `cat prompt.txt | claude -p`
- NDJSON lines mixed with non-JSON debug output (when `--verbose` is used): JSON.parse try/catch skips non-JSON lines
- Multiple `assistant` message objects in the stream: concatenate all text blocks

**Dependencies:**
- Depends on: Step 9 — CompanionService interface and SessionStore must exist

**Acceptance Criteria:**
- [ ] `CliProxyAdapter.stream()` spawns `claude -p` with `--output-format stream-json --verbose --max-turns 1`
- [ ] Text chunks from NDJSON are yielded as `{ type: 'text', content }` followed by `{ type: 'done' }`
- [ ] Session messages are persisted to the same JSONL format as AiSdkAdapter
- [ ] `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` env vars are removed from the spawned process environment
- [ ] Process timeout of 60s kills the child process and yields an error chunk
- [ ] `isAvailable()` returns false when `claude` is not in PATH

**Effort:** M
**AID Role:** backend

---

### Step 12: Companion Routes + WebSocket Bridge

**Objective:** Create Express routes for the companion API (send, sessions, status, transcribe) and a WebSocket bridge that streams companion responses to connected frontend clients in real-time.

**Files:**
- Create: `packages/aid-server/src/routes/companion.ts` — companion API routes (SSE streaming, sessions, status)
- Modify: `packages/aid-server/src/index.ts` (lines ~40-55) — mount companion routes, initialize CompanionService at startup
- Modify: `packages/aid-server/src/ws/handler.ts` (lines ~12-14) — add `'companion.stream'` and `'companion.session'` to EVENT_TOPICS

**Architecture Context:**
The companion routes follow the existing Express route pattern but introduce SSE (Server-Sent Events) for streaming responses. The `POST /companion/send` endpoint uses SSE instead of returning a single JSON response — this allows the frontend to receive text chunks as they arrive from the adapter. The WebSocket bridge is an alternative streaming path: companion response chunks are also broadcast on the `companion.stream` WebSocket topic so other connected clients can see the conversation in real-time.

**Implementation Detail:**

1. **Companion routes** (`companion.ts`):
   ```typescript
   export function companionRoutes(registry: ProjectRegistry, companion: CompanionService): Router {
     const router = Router({ mergeParams: true });

     // POST /api/p/:projectId/companion/send — SSE streaming
     router.post('/send', async (req, res) => {
       const { message, sessionId, hintCommand } = req.body;
       if (!message) return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'message is required' } });
       if (!companion.available) return res.status(503).json({ ok: false, error: { code: 'COMPANION_UNAVAILABLE', message: 'No AI companion adapter available' } });

       // SSE headers
       res.writeHead(200, {
         'Content-Type': 'text/event-stream',
         'Cache-Control': 'no-cache',
         'Connection': 'keep-alive',
       });

       try {
         for await (const chunk of companion.stream(message, { sessionId, hintCommand, projectRoot: registry.get(req.params.projectId)?.path })) {
           res.write(`data: ${JSON.stringify(chunk)}\n\n`);
         }
       } catch (err) {
         res.write(`data: ${JSON.stringify({ type: 'error', message: String(err) })}\n\n`);
       }
       res.end();
     });

     // GET /companion/sessions — list sessions
     router.get('/sessions', async (req, res) => { /* ... */ });

     // GET /companion/sessions/:sessionId — get session
     router.get('/sessions/:sessionId', async (req, res) => { /* ... */ });

     // GET /companion/status — adapter status
     router.get('/status', async (req, res) => {
       res.json({ ok: true, data: {
         adapter: companion.adapterName,
         available: companion.available,
       }});
     });

     return router;
   }
   ```

2. **Server initialization** in `index.ts`:
   ```typescript
   import { detectCompanionAdapter } from './companion/auto-detect.js';
   // After server setup:
   const companion = await detectCompanionAdapter();
   console.log(`[companion] Adapter: ${companion.adapterName}, available: ${companion.available}`);
   app.use('/api/p/:projectId/companion', companionRoutes(registry, companion));
   ```

3. **WebSocket topics** — add to `EVENT_TOPICS` in `handler.ts`:
   ```typescript
   'companion.stream', 'companion.session'
   ```

**Error Handling:**
- SSE connection drops mid-stream: the `for await` loop completes normally, `res.end()` is called, no server crash
- Companion adapter throws during streaming: catch block writes error chunk to SSE, then ends the response
- Client disconnects before stream completes: Express handles this gracefully, no action needed
- No adapter available (StubAdapter): return 503 immediately without attempting to stream

**Edge Cases:**
- Multiple concurrent companion requests: each request gets its own adapter stream, no shared state conflicts
- Very long streaming response (>30s): SSE keeps the connection alive, no timeout (unlike normal HTTP requests)
- Session ID not provided: auto-generate UUID, return it in the `done` chunk so frontend can reference it later

**Dependencies:**
- Depends on: Step 9 — CompanionService interface must exist
- Depends on: Step 10 or Step 11 — at least one adapter must be implemented

**Acceptance Criteria:**
- [ ] `POST /api/p/default/companion/send` with `{ message: "hello" }` returns SSE stream with text chunks
- [ ] `GET /api/p/default/companion/status` returns `{ adapter, available }` reflecting the detected adapter
- [ ] `GET /api/p/default/companion/sessions` returns list of past sessions
- [ ] SSE stream ends with a `done` chunk containing `sessionId` and `fullContent`
- [ ] `companion.stream` and `companion.session` are registered WebSocket topics
- [ ] 503 returned when no adapter is available

**Effort:** M
**AID Role:** backend

---

### Step 13: Whisper API Voice Dictation Proxy

**Objective:** Create a backend endpoint that receives audio blobs from the frontend, forwards them to the Whisper API for transcription, and returns the transcribed text.

**Files:**
- Create: `packages/aid-server/src/routes/voice.ts` — POST `/api/p/:projectId/companion/transcribe` route with multipart upload
- Modify: `packages/aid-server/src/routes/companion.ts` — mount voice sub-route
- Modify: `packages/aid-server/package.json` — add `multer` for multipart file upload handling
- Modify: `packages/aid-server/src/index.ts` — increase body parser limit for audio uploads

**Architecture Context:**
The voice endpoint is a sub-route of the companion API at `packages/aid-server/src/routes/companion.ts`. It uses `multer` for multipart file upload parsing (accepting `audio/webm` and `audio/wav` content types). The endpoint forwards the audio buffer to OpenAI's Whisper API (`https://api.openai.com/v1/audio/transcriptions`) using a standard `fetch()` request with `FormData`. The Whisper API key is read from `OPENAI_API_KEY` environment variable. If the env var is missing, the endpoint returns 503 with a message suggesting Web Speech API fallback.

**Implementation Detail:**

1. **Voice route** (`voice.ts`):
   ```typescript
   import multer from 'multer';

   const upload = multer({
     storage: multer.memoryStorage(),
     limits: { fileSize: 25 * 1024 * 1024 }, // 25MB
     fileFilter: (req, file, cb) => {
       if (file.mimetype.startsWith('audio/')) cb(null, true);
       else cb(new Error('Only audio files accepted'));
     },
   });

   export function voiceRoutes(): Router {
     const router = Router({ mergeParams: true });

     router.post('/transcribe', upload.single('audio'), async (req, res) => {
       if (!req.file) return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'No audio file provided' } });

       const apiKey = process.env.OPENAI_API_KEY;
       if (!apiKey) return res.status(503).json({ ok: false, error: { code: 'WHISPER_UNAVAILABLE', message: 'OPENAI_API_KEY not configured. Use browser Web Speech API as fallback.' } });

       const language = (req.body.language as string) ?? 'cs';

       const formData = new FormData();
       formData.append('file', new Blob([req.file.buffer], { type: req.file.mimetype }), 'audio.webm');
       formData.append('model', 'whisper-1');
       formData.append('language', language);
       formData.append('response_format', 'json');

       const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
         method: 'POST',
         headers: { 'Authorization': `Bearer ${apiKey}` },
         body: formData,
       });

       if (!response.ok) {
         const errorText = await response.text();
         return res.status(502).json({ ok: false, error: { code: 'WHISPER_ERROR', message: `Whisper API error: ${response.status} ${errorText}` } });
       }

       const result = await response.json() as { text: string };
       res.json({ ok: true, data: { text: result.text, language, duration: req.file.size / 16000 } });
     });

     return router;
   }
   ```

2. **Mount in companion routes**: `router.use('/', voiceRoutes());`

3. **Body parser limit** in `index.ts`: `app.use(express.json({ limit: '1mb' }));` (JSON limit stays small; multer handles the large audio uploads separately).

**Error Handling:**
- `OPENAI_API_KEY` not set: return 503 with clear message suggesting Web Speech API fallback
- Whisper API returns non-200: forward the error status and message as a 502 response
- File too large (>25MB): multer rejects with 413 before reaching the handler
- Non-audio file type: multer fileFilter rejects with 400
- Network error to Whisper API: catch fetch error, return 502

**Edge Cases:**
- Empty audio file (0 bytes): Whisper API handles this, returns empty text
- Very short audio (<0.5s): Whisper may return empty text — frontend should show "No speech detected"
- Language parameter missing: defaults to `'cs'` (Czech, per PM requirement)
- Concurrent transcription requests: each request is independent, no shared state

**Dependencies:**
- Depends on: Step 12 — companion routes must exist to mount voice sub-route

**Acceptance Criteria:**
- [ ] `POST /api/p/default/companion/transcribe` with audio file returns `{ text, language, duration }`
- [ ] Czech language (`cs`) is the default when language parameter is not provided
- [ ] 503 returned when `OPENAI_API_KEY` environment variable is not set
- [ ] 400 returned when no audio file is attached
- [ ] 413 returned when audio file exceeds 25MB
- [ ] `multer` is added to `packages/aid-server/package.json` dependencies

**Effort:** M
**AID Role:** backend

---

### Step 14: EPIC Lifecycle Endpoints

**Objective:** Create API endpoints for listing EPIC metadata from `.aid-o/02-epics/` and triggering EPIC execution (adding to the queue).

**Files:**
- Create: `packages/aid-server/src/routes/epics.ts` — GET `/api/p/:projectId/epics` and POST `/api/p/:projectId/epics/:epicId/run`
- Modify: `packages/aid-server/src/index.ts` (lines ~40-55) — mount epics routes
- Modify: `packages/aid-server/src/ws/handler.ts` (lines ~190-199 classifyFileChange) — add `epics` topic classification for `.aid-o/02-epics/` changes

**Architecture Context:**
The EPIC lifecycle endpoints follow the existing route pattern. The GET endpoint scans `.aid-o/02-epics/` directory (excluding `archive/` subdirectory), reads YAML frontmatter from each `.md` file, and extracts the `# EPIC:` heading for the title. The POST run endpoint reads the EPIC queue file at `.aid-o/03-config/epic-queue.yaml` (using `js-yaml` which is already a dependency), adds the EPIC to the queue, and writes back. The WebSocket handler gets a new `epics` topic classification for file changes in `02-epics/`.

**Implementation Detail:**

1. **EPIC list endpoint**:
   ```typescript
   router.get('/', async (req: Request<ProjectParams>, res) => {
     const fs = registry.getFsReader(req.params.projectId);
     if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

     const epicsDir = join(fs.aidoPath, '02-epics');
     const files = await fs.listDir('02-epics').catch(() => []);
     const mdFiles = files.filter(f => f.endsWith('.md') && !f.startsWith('archive/'));

     const epics: EpicMetadata[] = [];
     for (const file of mdFiles) {
       const content = await fs.readText(join(epicsDir, file));
       if (!content) continue;
       // Parse frontmatter (between first pair of ---)
       const fmMatch = content.match(/^---\n([\s\S]*?)\n---/);
       const frontmatter = fmMatch ? yaml.load(fmMatch[1]) as Record<string, any> : {};
       // Parse title from first # EPIC: heading
       const titleMatch = content.match(/^# EPIC:\s*(.+)$/m);
       const title = titleMatch?.[1]?.trim() ?? file.replace('.md', '');
       // Count steps from Steps table
       const stepsMatch = content.match(/\|\s*\d+\s*\|/g);
       const stepsTotal = stepsMatch?.length ?? 0;
       // Extract roles from Steps table
       const roleMatches = [...content.matchAll(/\|\s*\d+\s*\|\s*(\w+)\s*\|/g)];
       const roles = [...new Set(roleMatches.map(m => m[1]))];

       epics.push({
         epicId: file.replace('.md', ''),
         title,
         status: frontmatter.status ?? 'active',
         planRef: frontmatter.plan_ref ?? '',
         stepsTotal,
         roles,
         runsTotal: frontmatter.runs_total ?? 0,
         runsCompleted: frontmatter.runs_completed ?? 0,
       });
     }

     res.json({ ok: true, data: epics });
   });
   ```

2. **EPIC run endpoint**: Reads `epic-queue.yaml`, adds entry with specified priority, writes back.

3. **WebSocket classification** — add before `return 'system'`:
   ```typescript
   if (relPath.startsWith('02-epics') && !relPath.includes('archive')) return 'epics';
   ```

**Error Handling:**
- EPIC file with malformed frontmatter: skip YAML parse, use defaults (status: 'active', empty planRef)
- `02-epics/` directory does not exist: return empty array
- EPIC already in queue: return 409 Conflict with message "EPIC already queued"
- Queue file does not exist: create it with the single new entry

**Edge Cases:**
- EPIC files in `archive/` subdirectory: excluded from listing
- EPIC file without `# EPIC:` heading: use filename (minus `.md`) as title
- EPIC with no Steps table: `stepsTotal` is 0
- Empty `02-epics/` directory: return `{ ok: true, data: [] }`

**Dependencies:**
- Depends on: Step 1 — WebSocket handler must support adding new topic classifications

**Acceptance Criteria:**
- [ ] `GET /api/p/default/epics` returns array of EpicMetadata with correct `epicId`, `title`, `status`, `stepsTotal`, `roles`
- [ ] Files in `archive/` are excluded from the listing
- [ ] `POST /api/p/default/epics/:epicId/run` with `{ mode: 'now' }` adds EPIC to front of queue with `priority: 'critical'`
- [ ] `POST /api/p/default/epics/:epicId/run` with `{ mode: 'schedule' }` adds EPIC to end of queue with `priority: 'medium'`
- [ ] 409 returned when EPIC is already in the queue
- [ ] WebSocket clients subscribed to `epics` topic receive events when files in `02-epics/` change

**Effort:** M
**AID Role:** backend

---

### Step 15: Chat UI

**Objective:** Rebuild the existing AICompanion modal into a full chat interface with slide-down panel, message bubbles with markdown rendering, streaming typewriter effect, and session management sidebar.

**Files:**
- Modify: `packages/aid-gui/src/components/AICompanion.tsx` (full rewrite) — transform from search modal to chat panel
- Modify: `packages/aid-gui/src/types/api.ts` — add CompanionSession, CompanionMessage, CompanionStatus types
- Modify: `packages/aid-gui/src/types/store.ts` — add CompanionSlice interface
- Modify: `packages/aid-gui/src/store.ts` — add CompanionSlice with messages, sessions, streaming state
- Modify: `packages/aid-gui/src/api/client.ts` — add companion API methods (sendCompanion, getSessions, getCompanionStatus)
- Modify: `packages/aid-gui/src/App.tsx` — change Cmd+K handler to toggle chat panel instead of modal

**Architecture Context:**
The current `AICompanion.tsx` at `packages/aid-gui/src/components/` is a Cmd+K command palette modal with preset queries and localStorage history. This step replaces it with a chat panel that docks to the right third of the screen. The panel slides down from the top (using Framer Motion `motion/react` which is already imported as `motion`). Messages stream from the `POST /companion/send` SSE endpoint. The Zustand store gets a new CompanionSlice for messages, sessions, and streaming state.

**Implementation Detail:**

1. **CompanionSlice** in store:
   ```typescript
   interface CompanionSlice {
     companionOpen: boolean;
     companionMessages: CompanionMessage[];
     companionSessions: CompanionSession[];
     companionSessionId: string | null;
     companionStreaming: boolean;
     companionStreamBuffer: string;
     companionAdapter: 'ai-sdk' | 'cli-proxy' | 'none';
     setCompanionOpen: (open: boolean) => void;
     toggleCompanion: () => void;
     addCompanionMessage: (msg: CompanionMessage) => void;
     setCompanionStreaming: (streaming: boolean) => void;
     appendToStreamBuffer: (text: string) => void;
     clearStreamBuffer: () => void;
     setCompanionSessions: (sessions: CompanionSession[]) => void;
     setCompanionSessionId: (id: string | null) => void;
     setCompanionAdapter: (adapter: 'ai-sdk' | 'cli-proxy' | 'none') => void;
   }
   ```

2. **Chat panel component** — slide-down from top, docked right third:
   ```tsx
   <AnimatePresence>
     {companionOpen && (
       <motion.div
         initial={{ y: -600, opacity: 0 }}
         animate={{ y: 0, opacity: 1 }}
         exit={{ y: -600, opacity: 0 }}
         className="fixed top-14 right-0 w-1/3 h-[calc(100vh-3.5rem)] bg-gray-900 border-l border-gray-700 z-40 flex flex-col"
       >
         {/* Header */}
         {/* Session sidebar (collapsible) */}
         {/* Messages area (scrollable) */}
         {/* Input area with hint buttons */}
       </motion.div>
     )}
   </AnimatePresence>
   ```

3. **Streaming message display** — while streaming, show the buffer with a blinking cursor:
   ```tsx
   {companionStreaming && (
     <div className="text-gray-300 whitespace-pre-wrap">
       {companionStreamBuffer}<span className="animate-pulse">▌</span>
     </div>
   )}
   ```

4. **SSE client** — use `EventSource` or `fetch()` with ReadableStream for the SSE endpoint:
   ```typescript
   async function sendCompanionMessage(projectId: string, message: string, sessionId?: string) {
     const res = await fetch(`/api/p/${projectId}/companion/send`, {
       method: 'POST',
       headers: { 'Content-Type': 'application/json' },
       body: JSON.stringify({ message, sessionId }),
     });
     const reader = res.body!.getReader();
     const decoder = new TextDecoder();
     while (true) {
       const { done, value } = await reader.read();
       if (done) break;
       const text = decoder.decode(value);
       // Parse SSE data lines
       for (const line of text.split('\n')) {
         if (line.startsWith('data: ')) {
           const chunk = JSON.parse(line.slice(6));
           if (chunk.type === 'text') store.appendToStreamBuffer(chunk.content);
           if (chunk.type === 'done') { /* finalize message */ }
           if (chunk.type === 'error') { /* show error */ }
         }
       }
     }
   }
   ```

5. **Markdown rendering** — use the existing approach in the codebase (inline HTML rendering or a lightweight markdown library). Since no markdown library is currently installed, render code blocks with `<pre>` and basic formatting with regex replacements for bold/italic/links.

**Error Handling:**
- SSE connection drops: show "Connection lost" message with retry button
- Adapter unavailable (503): show setup instructions panel with link to documentation
- Empty message submission: prevent form submit, no API call

**Edge Cases:**
- Very long messages that overflow the chat area: auto-scroll to bottom on new chunks
- Multiple rapid messages: queue them — disable input while streaming
- Session switch while streaming: cancel current stream, load new session's messages
- Cmd+K while chat is open: close the panel (toggle behavior)

**Dependencies:**
- Depends on: Step 12 — companion SSE endpoint must be available
- Depends on: Step 4 — frontend types must compile

**Acceptance Criteria:**
- [ ] Cmd+K toggles the chat panel (open/close)
- [ ] Chat panel slides down from top, docked to right third of screen
- [ ] Typing a message and pressing Enter sends it to `POST /companion/send` and displays streaming response
- [ ] Streaming response shows with blinking cursor animation
- [ ] Session sidebar lists past sessions and allows switching between them
- [ ] "No companion available" message shown when adapter status is `'none'`
- [ ] Messages render markdown (code blocks, bold, links)

**Effort:** L
**AID Role:** frontend

---

### Step 16: Hint Commands

**Objective:** Add 7 hint command pill buttons above the chat input that pre-fill prompt templates with context from the selected kanban card.

**Files:**
- Modify: `packages/aid-gui/src/components/AICompanion.tsx` (lines ~bottom, input area) — add hint buttons row above input
- Create: `packages/aid-gui/src/components/companion/HintButtons.tsx` — hint button component with prompt templates
- Modify: `packages/aid-gui/src/store.ts` — add `selectedKanbanCard: StoredIdea | null` to IdeasSlice for context passing

**Architecture Context:**
Hint commands are contextual shortcuts in the Chat UI that pre-fill the input with a prompt template. The templates reference the currently selected kanban card (if any) to provide context-aware prompts. The 7 hints are: Brainstorm, Plan EPIC, Run, Audit, Explain, Fix, Free chat. When a hint is clicked, the template is sent with `hintCommand` field set, which the backend passes to the adapter's `buildPrompt()` method for template expansion.

**Implementation Detail:**

1. **Hint definitions**:
   ```typescript
   const HINTS = [
     { id: 'brainstorm', label: 'Brainstorm', icon: Lightbulb,
       template: (card?: StoredIdea) => card
         ? `Brainstorm implementation approaches for: "${card.title}". ${card.description}`
         : 'Help me brainstorm a new feature idea for this project.' },
     { id: 'plan-epic', label: 'Plan EPIC', icon: FileText,
       template: (card?: StoredIdea) => card
         ? `Create an EPIC plan for: "${card.title}". Consider the following: ${card.description}`
         : 'Help me plan a new EPIC for this project.' },
     { id: 'run', label: 'Run', icon: Play,
       template: (card?: StoredIdea) => card?.linkedEpic
         ? `Run EPIC ${card.linkedEpic}. What should I expect?`
         : 'What EPICs are ready to run?' },
     { id: 'audit', label: 'Audit', icon: Shield,
       template: () => 'Run a health audit on this project and summarize the findings.' },
     { id: 'explain', label: 'Explain', icon: HelpCircle,
       template: (card?: StoredIdea) => card
         ? `Explain the current status and next steps for: "${card.title}"`
         : 'Explain the current project status and what needs attention.' },
     { id: 'fix', label: 'Fix', icon: Wrench,
       template: (card?: StoredIdea) => card
         ? `Help me fix issues related to: "${card.title}". ${card.description}`
         : 'Help me identify and fix issues in this project.' },
     { id: 'free', label: 'Free chat', icon: MessageSquare,
       template: () => '' },
   ] as const;
   ```

2. **Hint button row** — render as pill buttons with icons:
   ```tsx
   <div className="flex flex-wrap gap-2 px-4 py-2 border-t border-gray-700">
     {HINTS.map(hint => (
       <button
         key={hint.id}
         onClick={() => {
           const prompt = hint.template(selectedKanbanCard ?? undefined);
           if (hint.id === 'free') { inputRef.current?.focus(); return; }
           sendCompanionMessage(projectId, prompt, companionSessionId, hint.id);
         }}
         className="flex items-center gap-1.5 rounded-full bg-gray-700 px-3 py-1.5 text-xs text-gray-300 hover:bg-gray-600 transition-colors"
       >
         <hint.icon className="h-3.5 w-3.5" />
         {hint.label}
       </button>
     ))}
   </div>
   ```

3. **Context passing** — add `selectedKanbanCard` to IdeasSlice:
   ```typescript
   selectedKanbanCard: StoredIdea | null;
   setSelectedKanbanCard: (card: StoredIdea | null) => void;
   ```
   Set on card click in kanban, clear on click elsewhere.

**Error Handling:**
- Hint button clicked while streaming: button is disabled (same as input field)
- Selected card has no description: template uses title only

**Edge Cases:**
- No card selected: templates use generic project-level prompts
- "Free chat" hint: focuses the input field without sending a message
- Very long card description (>500 chars): truncate to first 500 chars in template to avoid prompt bloat

**Dependencies:**
- Depends on: Step 15 — Chat UI must exist
- Depends on: Step 5 — kanban must support card selection

**Acceptance Criteria:**
- [ ] 7 pill buttons render above the chat input: Brainstorm, Plan EPIC, Run, Audit, Explain, Fix, Free chat
- [ ] Clicking a hint button sends the template text as a companion message with `hintCommand` field set
- [ ] When a kanban card is selected, hint templates include the card's title and description
- [ ] When no card is selected, hint templates use generic project-level prompts
- [ ] "Free chat" focuses the input field without sending a message
- [ ] Hint buttons are disabled while a response is streaming

**Effort:** M
**AID Role:** frontend

---

### Step 17: Voice Dictation UI

**Objective:** Add a microphone button to the chat input that records audio via the browser MediaRecorder API, sends it to the Whisper transcribe endpoint, and inserts the transcribed text into the chat input.

**Files:**
- Create: `packages/aid-gui/src/components/companion/VoiceButton.tsx` — microphone button with push-to-talk recording
- Modify: `packages/aid-gui/src/components/AICompanion.tsx` — render VoiceButton next to chat input
- Modify: `packages/aid-gui/src/api/client.ts` — add `transcribeAudio()` method

**Architecture Context:**
The VoiceButton component manages the browser's `MediaRecorder` API lifecycle. When pressed (mousedown/touchstart), it starts recording audio into a `webm/opus` Blob. When released (mouseup/touchend), it stops recording and sends the blob to `POST /companion/transcribe` via `FormData`. The transcribed text is inserted into the chat input field. If the Whisper endpoint returns 503 (no API key), the component falls back to the Web Speech API (`window.SpeechRecognition`) for browser-native transcription.

**Implementation Detail:**

1. **VoiceButton component**:
   ```tsx
   export function VoiceButton({ onTranscribed, language = 'cs' }: VoiceButtonProps) {
     const [recording, setRecording] = useState(false);
     const mediaRecorderRef = useRef<MediaRecorder | null>(null);
     const chunksRef = useRef<Blob[]>([]);

     const startRecording = async () => {
       const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
       const recorder = new MediaRecorder(stream, { mimeType: 'audio/webm;codecs=opus' });
       chunksRef.current = [];
       recorder.ondataavailable = (e) => chunksRef.current.push(e.data);
       recorder.onstop = async () => {
         const blob = new Blob(chunksRef.current, { type: 'audio/webm' });
         stream.getTracks().forEach(t => t.stop());
         // Send to backend
         const result = await transcribeAudio(projectId, blob, language);
         if (result.ok) onTranscribed(result.data.text);
         else if (result.error.code === 'WHISPER_UNAVAILABLE') {
           // Fallback to Web Speech API
           fallbackWebSpeech(language, onTranscribed);
         }
       };
       recorder.start();
       mediaRecorderRef.current = recorder;
       setRecording(true);
     };

     const stopRecording = () => {
       mediaRecorderRef.current?.stop();
       setRecording(false);
     };

     return (
       <button
         onMouseDown={startRecording}
         onMouseUp={stopRecording}
         onTouchStart={startRecording}
         onTouchEnd={stopRecording}
         className={`p-2 rounded-lg ${recording ? 'bg-red-600 animate-pulse' : 'bg-gray-700 hover:bg-gray-600'}`}
       >
         <Mic className="h-4 w-4" />
       </button>
     );
   }
   ```

2. **API client method**:
   ```typescript
   async transcribeAudio(blob: Blob, language?: string): Promise<ApiResult<{ text: string; language: string; duration: number }>> {
     const formData = new FormData();
     formData.append('audio', blob, 'recording.webm');
     if (language) formData.append('language', language);
     const res = await fetch(`${base}/companion/transcribe`, { method: 'POST', body: formData });
     return res.json();
   }
   ```

3. **Web Speech API fallback**:
   ```typescript
   function fallbackWebSpeech(language: string, onResult: (text: string) => void) {
     const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
     if (!SpeechRecognition) return;
     const recognition = new SpeechRecognition();
     recognition.lang = language === 'cs' ? 'cs-CZ' : language;
     recognition.onresult = (e) => onResult(e.results[0][0].transcript);
     recognition.start();
   }
   ```

**Error Handling:**
- Microphone permission denied: show toast "Microphone access required for voice dictation"
- MediaRecorder not supported (old browser): hide the microphone button entirely
- Whisper API timeout (>10s): show toast "Transcription timed out, try again"
- Empty recording (button clicked and immediately released): skip API call

**Edge Cases:**
- User holds button for >60s: limit recording to 60s max, auto-stop and transcribe
- Background noise without speech: Whisper returns empty text, show "No speech detected" toast
- Browser does not support `audio/webm;codecs=opus`: fallback to `audio/webm` without codec specification
- Mobile touch events: `onTouchStart`/`onTouchEnd` handle mobile push-to-talk

**Dependencies:**
- Depends on: Step 13 — Whisper transcribe endpoint must exist
- Depends on: Step 15 — Chat UI must have input area to render the button

**Acceptance Criteria:**
- [ ] Microphone button appears next to the chat input
- [ ] Press-and-hold records audio (red pulsing indicator while recording)
- [ ] Release stops recording and sends audio to `/companion/transcribe`
- [ ] Transcribed text is inserted into the chat input field
- [ ] If Whisper returns 503, falls back to Web Speech API
- [ ] If browser does not support MediaRecorder, microphone button is hidden
- [ ] Recording auto-stops after 60 seconds

**Effort:** M
**AID Role:** frontend

---

### Step 18: EPIC Column UI + Queue Scheduler + Auto-Transitions

**Objective:** Add EPIC-specific functionality to the kanban: drag plan → EPIC column triggers plan-epic action with building animation, EPIC cards show step count and role badges, Queue Scheduler shows all EPICs with "Run Now" and "Schedule" actions, and WebSocket events automatically transition cards between Running and Done columns.

**Files:**
- Modify: `packages/aid-gui/src/screens/IdeasToExecution.tsx` — add EPIC column drag handler, building animation, EPIC card rendering
- Modify: `packages/aid-gui/src/screens/QueueScheduler.tsx` — add "Run Now" and "Schedule" buttons to EPIC cards
- Modify: `packages/aid-gui/src/types/api.ts` — add EpicMetadata type
- Modify: `packages/aid-gui/src/api/client.ts` — add `getEpics()`, `runEpic()` methods
- Modify: `packages/aid-gui/src/store.ts` — add EpicsSlice with epic metadata state
- Modify: `packages/aid-gui/src/hooks/useWebSocket.ts` — add `epics` topic subscription, handle `pipeline` events for auto-transitions
- Modify: `packages/aid-gui/src/types/ws.ts` — add `'epics'` to EventTopic

**Architecture Context:**
This step bridges the kanban (Step 5) with the EPIC lifecycle endpoints (Step 14) and the existing Queue Scheduler page. When a user drags an idea from the Plan column to the EPIC column, the frontend calls `POST /epics/:epicId/run` (or shows a "building" animation while the EPIC is being generated). The auto-transition logic listens for WebSocket `pipeline` events: when `currentEpicId` matches a linked EPIC, the card moves to Running; when the EPIC completes, it moves to Done. The Queue Scheduler page gets "Run Now" and "Schedule" action buttons on each EPIC card.

**Implementation Detail:**

1. **EPIC column drag handler** in `IdeasToExecution.tsx`:
   ```typescript
   // In handleDragEnd, when dropping to 'epic' column:
   if (targetColumnId === 'epic' && idea.linkedPlan && !idea.linkedEpic) {
     // Show building animation
     setBuildingIdeaId(idea.id);
     // Stub: actual EPIC generation would call /aid-plan-epic
     // For now, show animation for 3s then prompt user to link EPIC manually
     setTimeout(() => setBuildingIdeaId(null), 3000);
   }
   ```

2. **Building animation** — card in EPIC column shows pulsing border and progress text:
   ```tsx
   {buildingIdeaId === idea.id && (
     <div className="absolute inset-0 rounded-lg border-2 border-purple-500 animate-pulse flex items-center justify-center bg-gray-900/80">
       <span className="text-sm text-purple-400">Building EPIC...</span>
     </div>
   )}
   ```

3. **EPIC card rendering** — when an idea has `linkedEpic`, show EPIC metadata:
   ```tsx
   {idea.linkedEpic && epicMetadata[idea.linkedEpic] && (
     <div className="mt-2 flex items-center gap-2 text-xs text-gray-400">
       <span>{epicMetadata[idea.linkedEpic].stepsTotal} steps</span>
       {epicMetadata[idea.linkedEpic].roles.map(role => (
         <span key={role} className="rounded bg-gray-700 px-1.5 py-0.5">{role}</span>
       ))}
     </div>
   )}
   ```

4. **Auto-transitions** via WebSocket in `useWebSocket.ts`:
   ```typescript
   // In pipeline event handler, after updating pipeline state:
   const epicId = parsed.currentEpicId ?? parsed.epicId;
   if (epicId) {
     // Find ideas linked to this EPIC and update autoStatus
     const ideas = store.ideas;
     const updated = ideas.map(idea =>
       idea.linkedEpic === epicId
         ? { ...idea, autoStatus: 'running' as const }
         : idea
     );
     if (JSON.stringify(updated) !== JSON.stringify(ideas)) {
       store.setIdeas(updated);
     }
   }
   // On EPIC completion (state === 'DONE'):
   const fsm = parsed.currentState ?? parsed.state;
   if (fsm === 'DONE' && epicId) {
     const ideas = store.ideas;
     const updated = ideas.map(idea =>
       idea.linkedEpic === epicId
         ? { ...idea, autoStatus: 'done' as const }
         : idea
     );
     store.setIdeas(updated);
   }
   ```

5. **Queue Scheduler buttons** — add to each EPIC card in `QueueScheduler.tsx`:
   ```tsx
   <button onClick={() => client.runEpic(epicId, 'now')} className="...">Run Now</button>
   <button onClick={() => client.runEpic(epicId, 'schedule')} className="...">Schedule</button>
   ```

**Error Handling:**
- EPIC generation timeout (>60s): cancel building animation, show error toast
- `runEpic()` returns 409 (already queued): show toast "EPIC already in queue"
- Auto-transition receives unknown EPIC ID: no matching idea found, update is skipped

**Edge Cases:**
- EPIC completes while user is on a different page: auto-transition still fires via WebSocket, kanban updates when user returns
- Multiple ideas linked to the same EPIC: all move to Running/Done simultaneously
- Drag idea directly to Running or Done column: allowed, sets status manually (overrides auto-transition)
- Queue Scheduler page already shows queue entries — the "Run Now" and "Schedule" buttons add EPICs that are not yet in the queue

**Dependencies:**
- Depends on: Step 5 — kanban must have 5-column layout with drag-drop
- Depends on: Step 14 — EPIC lifecycle endpoints must exist
- Depends on: Step 7 — WebSocket ideas subscription must be active

**Acceptance Criteria:**
- [ ] Dragging an idea from Plan to EPIC column shows a building animation (pulsing purple border, "Building EPIC..." text)
- [ ] Ideas with `linkedEpic` show step count and role badges on their kanban card
- [ ] When a linked EPIC starts executing (pipeline state change via WebSocket), the idea card auto-moves to Running column
- [ ] When a linked EPIC completes (pipeline state DONE via WebSocket), the idea card auto-moves to Done column
- [ ] Queue Scheduler page shows "Run Now" and "Schedule" buttons on EPIC entries
- [ ] "Run Now" adds EPIC to front of queue with critical priority
- [ ] "Schedule" adds EPIC to end of queue with medium priority

**Effort:** L
**AID Role:** frontend

---

### Step 19: Phase 2 Verification — Vitest + Playwright

**Objective:** Write Vitest unit tests for Phase 2 services (companion adapters, auto-detection, EPIC endpoints, voice proxy) and Playwright smoke tests for the Chat UI, hint commands, and EPIC column.

**Files:**
- Create: `packages/aid-gui/tests/server/services/companion.test.ts` — unit tests for CompanionService adapters and auto-detection
- Create: `packages/aid-gui/tests/server/api/companion.test.ts` — unit tests for companion routes (SSE, sessions, status)
- Create: `packages/aid-gui/tests/server/api/epics.test.ts` — unit tests for EPIC list and run endpoints
- Create: `packages/aid-gui/tests/frontend/store-companion.test.ts` — unit tests for CompanionSlice
- Create: `packages/aid-gui/tests/frontend/api-client-companion.test.ts` — unit tests for companion API client methods
- Create: `packages/aid-gui/tests/e2e/phase2-companion.spec.ts` — Playwright smoke test for Chat UI and EPIC column

**Architecture Context:**
Phase 2 tests follow the same patterns established in Step 8. Companion adapter tests mock the external dependencies (`ai-sdk-provider-claude-code` and `child_process`) to test the adapter logic in isolation. The Playwright test verifies the Chat UI opens, hint buttons render, and the EPIC column appears in the kanban.

**Implementation Detail:**

1. **Companion adapter tests**: Mock `generateText`/`streamText` and verify the adapter correctly transforms results into `StreamChunk` types. Mock `execFileSync` for CLI availability check.

2. **EPIC endpoint tests**: Create sample EPIC markdown files in a temp directory, verify the parser extracts correct frontmatter, title, step count, and roles.

3. **Playwright smoke test**:
   ```typescript
   test('chat panel opens with Cmd+K', async ({ page }) => {
     await page.goto('/ideas');
     await page.keyboard.press('Meta+k');
     await expect(page.getByText('AI Companion')).toBeVisible();
   });

   test('hint buttons render', async ({ page }) => {
     await page.goto('/ideas');
     await page.keyboard.press('Meta+k');
     await expect(page.getByText('Brainstorm')).toBeVisible();
     await expect(page.getByText('Plan EPIC')).toBeVisible();
     await expect(page.getByText('Free chat')).toBeVisible();
   });

   test('EPIC column visible in kanban', async ({ page }) => {
     await page.goto('/ideas');
     await expect(page.getByText('EPIC')).toBeVisible();
     await expect(page.getByText('Running')).toBeVisible();
   });
   ```

**Error Handling:**
- Mocked adapter tests: verify error paths (network failure, timeout, auth failure) produce correct error chunks

**Edge Cases:**
- Playwright test runs without a companion adapter: companion status endpoint returns `adapter: 'none'`, test verifies the "unavailable" message appears

**Dependencies:**
- Depends on: Steps 9-18 — all Phase 2 features must be implemented

**Acceptance Criteria:**
- [ ] `npx vitest run` passes all new Phase 2 test files
- [ ] Companion adapter tests verify send, stream, and error handling paths
- [ ] EPIC endpoint tests verify metadata extraction from sample EPIC files
- [ ] CompanionSlice tests verify state management (open/close, messages, streaming)
- [ ] Playwright test verifies Chat UI opens, hint buttons render, EPIC column visible
- [ ] All Phase 1 tests continue to pass (regression)

**Effort:** L
**AID Role:** qa

---

### Step 20: Evidence Search Endpoint + Pipeline Theater Data

**Objective:** Create a full-text search endpoint for the Evidence Vault and a data aggregation endpoint for the Pipeline Theater that combines plan steps with execution progress and stage log events.

**Files:**
- Create: `packages/aid-server/src/routes/evidence-search.ts` — GET `/api/p/:projectId/evidence/search` with query parameter
- Modify: `packages/aid-server/src/routes/evidence.ts` — mount search sub-route
- Modify: `packages/aid-server/src/routes/pipeline.ts` — add GET `/api/p/:projectId/pipeline/theater/:epicId/:runId` endpoint

**Architecture Context:**
The evidence search endpoint scans `.aid-o/04-engine/evidence/` recursively, reading text files and searching for the query string (case-insensitive substring match). The pipeline theater endpoint combines data from three sources for a specific run: `plan.json` (step definitions), `plan_progress.json` (step execution status), and `stage_log.jsonl` (event timeline). Both endpoints use the existing `FsReader` service.

**Implementation Detail:**

1. **Evidence search**:
   ```typescript
   router.get('/search', async (req, res) => {
     const query = req.query.q as string;
     if (!query) return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'q parameter required' } });

     const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
     const evidenceDir = join(fs.aidoPath, '04-engine', 'evidence');
     const results: EvidenceSearchResult[] = [];

     // Recursive file walk
     const walkDir = async (dir: string) => {
       const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);
       for (const entry of entries) {
         if (results.length >= limit) return;
         const fullPath = join(dir, entry.name);
         if (entry.isDirectory()) { await walkDir(fullPath); continue; }
         // Skip binary files
         const sample = await readFile(fullPath, { encoding: null }).catch(() => null);
         if (!sample || sample.slice(0, 512).includes(0)) continue;
         // Search content
         const content = sample.toString('utf-8');
         const lines = content.split('\n');
         for (let i = 0; i < lines.length; i++) {
           if (lines[i].toLowerCase().includes(query.toLowerCase())) {
             const relPath = relative(evidenceDir, fullPath);
             const parts = relPath.split('/');
             results.push({
               epicId: parts[0] ?? '',
               runId: parts[1] ?? '',
               filePath: parts.slice(2).join('/'),
               matchLine: i + 1,
               context: lines.slice(Math.max(0, i - 1), i + 2).join('\n'),
             });
             if (results.length >= limit) return;
             break; // one match per file
           }
         }
       }
     };

     await walkDir(evidenceDir);
     res.json({ ok: true, data: results });
   });
   ```

2. **Pipeline theater data**:
   ```typescript
   router.get('/theater/:epicId/:runId', async (req, res) => {
     const { epicId, runId } = req.params;
     const runDir = join(fs.aidoPath, '04-engine', 'evidence', epicId, runId);

     const [plan, progress, stageLog] = await Promise.all([
       fs.readJson(join(runDir, 'plan.json')),
       fs.readJson(join(runDir, 'plan_progress.json')),
       fs.readJsonl(join(runDir, 'stage_log.jsonl')),
     ]);

     if (!plan) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Run not found' } });

     const steps = (plan.steps ?? []).map((step: any) => ({
       id: step.id, role: step.role, objective: step.objective,
       status: progress?.steps?.[step.id]?.status ?? 'pending',
       startedAt: progress?.steps?.[step.id]?.startedAt ?? null,
       completedAt: progress?.steps?.[step.id]?.completedAt ?? null,
     }));

     const events = (stageLog ?? []) as StageLogEntryResponse[];
     const startedAt = events[0]?.timestamp ?? null;
     const completedAt = events[events.length - 1]?.timestamp ?? null;
     const duration = startedAt && completedAt
       ? Math.round((new Date(completedAt).getTime() - new Date(startedAt).getTime()) / 1000)
       : 0;

     res.json({ ok: true, data: { epicId, runId, startedAt, completedAt, steps, events, duration } });
   });
   ```

**Error Handling:**
- Evidence directory does not exist: return empty search results
- Binary file detection: skip files where first 512 bytes contain null byte (0x00)
- Plan.json not found for theater endpoint: return 404
- plan_progress.json missing: all steps show status 'pending'

**Edge Cases:**
- Evidence directory is very large (100+ runs): search stops at `limit` results, no full scan
- Search query is a single character: returns many results, capped at limit
- Run directory has no stage_log.jsonl: events array is empty, duration is 0
- JSONL parse error on individual lines: `readJsonl()` from `FsReader` skips malformed lines

**Dependencies:**
- No dependencies — can start independently (first step of Phase 3)

**Acceptance Criteria:**
- [ ] `GET /api/p/default/evidence/search?q=error` returns matching files with `epicId`, `runId`, `filePath`, `matchLine`, and `context`
- [ ] Search results are capped at `limit` parameter (default 50, max 200)
- [ ] Binary files are skipped during search
- [ ] `GET /api/p/default/pipeline/theater/:epicId/:runId` returns combined step data with execution status
- [ ] Theater data includes `duration` in seconds calculated from first to last stage log event
- [ ] 404 returned when run directory or plan.json does not exist

**Effort:** M
**AID Role:** backend

---

### Step 21: Evidence Vault Redesign

**Objective:** Redesign the Evidence Vault page with entries grouped by date (collapsed sections), markdown preview toggle, full file paths displayed, and a full-text search input connected to the search endpoint.

**Files:**
- Modify: `packages/aid-gui/src/screens/EvidenceVault.tsx` (full rewrite) — grouped display, search, markdown preview
- Modify: `packages/aid-gui/src/api/client.ts` — add `searchEvidence()` method
- Modify: `packages/aid-gui/src/store.ts` — extend EvidenceSlice with `evidenceSearchQuery`, `evidenceSearchResults`

**Architecture Context:**
The current Evidence Vault at `packages/aid-gui/src/screens/EvidenceVault.tsx` displays a flat tree of EPIC → Run → Files. This redesign groups runs by date (extracted from run directory timestamps), makes each date group collapsible, adds a search bar that calls `GET /evidence/search`, and adds a markdown preview toggle for evidence files. The existing `EvidenceSlice` in the store manages the tree data; this step extends it with search state.

**Implementation Detail:**

1. **Date grouping**: Transform the `evidenceEpics` array into a `Map<string, EvidenceEpicEntry[]>` keyed by date (YYYY-MM-DD extracted from run directory name or creation timestamp). Render each group as a collapsible `<details>` element, defaulting to collapsed except the most recent date.

2. **Search bar**: Debounced input (300ms) that calls `searchEvidence(query)`. Results render in a separate panel above the tree, showing matched file paths with highlighted context snippets.

3. **Markdown preview**: Toggle button on each file that switches between raw content (existing behavior) and rendered markdown. Use simple regex-based markdown rendering (same as Chat UI in Step 15) for headers, bold, code blocks, and links.

4. **Full file paths**: Display the complete relative path (`epicId/runId/filename`) instead of just the filename.

**Error Handling:**
- Search API returns error: show "Search failed" message with retry
- Evidence directory empty: show "No evidence collected yet" message
- File content load failure: show "Unable to load file" in preview area

**Edge Cases:**
- 100+ runs: date groups prevent overwhelming list; only recent dates expanded
- Search query matches files across many EPICs: results grouped by EPIC for clarity
- Very large markdown files (>100KB): truncate preview to first 10KB with "Show full file" link
- File with unknown format: display as raw text

**Dependencies:**
- Depends on: Step 20 — evidence search endpoint must exist

**Acceptance Criteria:**
- [ ] Evidence entries grouped by date with collapsible sections
- [ ] Most recent date group expanded by default, older groups collapsed
- [ ] Search input filters evidence with debounced API calls (300ms)
- [ ] Search results show file path, line number, and context snippet
- [ ] Markdown preview toggle renders headers, bold, code blocks, and links
- [ ] Full relative paths displayed (epicId/runId/filename)

**Effort:** M
**AID Role:** frontend

---

### Step 22: Pipeline Theater Replay

**Objective:** Rebuild the Pipeline Theater page with a run picker dropdown, timeline visualization showing steps on a time axis with color-coded role events, replay controls (play/pause/speed), detail panel on click, and live mode via WebSocket for active runs.

**Files:**
- Modify: `packages/aid-gui/src/screens/PipelineTheater.tsx` (full rewrite) — timeline, replay controls, live mode
- Modify: `packages/aid-gui/src/api/client.ts` — add `getTheaterData()` method
- Modify: `packages/aid-gui/src/store.ts` — extend ReplaySlice with theater data fields

**Architecture Context:**
The current Pipeline Theater at `packages/aid-gui/src/screens/PipelineTheater.tsx` has basic replay functionality using the `ReplaySlice` in the store. This redesign replaces the current list-based replay with an SVG-based timeline visualization (time × steps axis, color-coded by role), a run picker dropdown that fetches data from the theater endpoint (Step 20), and live mode that subscribes to `pipeline.stage_log` WebSocket events for active runs.

**Implementation Detail:**

1. **Run picker**: Dropdown populated from `GET /evidence` (list of EPICs and runs). On selection, fetch `GET /pipeline/theater/:epicId/:runId` and populate the timeline.

2. **Timeline visualization**: SVG-based timeline with:
   - X-axis: time (seconds from run start)
   - Y-axis: steps (one row per step)
   - Colored bars: step execution duration, color-coded by role (architect=blue, backend=green, frontend=purple, qa=orange, docs=gray)
   - Event dots: stage log events positioned on the timeline
   - Current position indicator (vertical line during replay)

3. **Replay controls**:
   ```tsx
   <div className="flex items-center gap-4">
     <button onClick={togglePlayback}>{playing ? <Pause /> : <Play />}</button>
     <select value={playbackSpeed} onChange={e => setPlaybackSpeed(Number(e.target.value))}>
       <option value={0.5}>0.5×</option>
       <option value={1}>1×</option>
       <option value={2}>2×</option>
       <option value={4}>4×</option>
     </select>
     <input type="range" min={0} max={duration} value={currentTime} onChange={seek} />
     <span>{formatTime(currentTime)} / {formatTime(duration)}</span>
   </div>
   ```

4. **Live mode**: When the selected run is currently active (pipeline state is EXECUTING), subscribe to `pipeline.stage_log` events and append them to the timeline in real-time. The timeline auto-scrolls to show the latest event.

5. **Detail panel**: Click on an event dot or step bar to show details in a side panel: timestamp, state, action, details text, result badge.

**Error Handling:**
- Theater data endpoint returns 404: show "Run data not found" message
- No runs available: show "No pipeline runs yet" empty state
- SVG rendering performance: limit visible events to 500, paginate older events

**Edge Cases:**
- Run with only 1 step: timeline shows single bar, replay is instant
- Run with 0 events (stage_log empty): timeline shows step bars only, no event dots
- Live mode with no active run: live toggle disabled, tooltip explains "No active run"
- Very long run (>1 hour): timeline auto-scales time axis, minute markers instead of second markers

**Dependencies:**
- Depends on: Step 20 — pipeline theater data endpoint must exist

**Acceptance Criteria:**
- [ ] Run picker dropdown shows available EPICs and runs
- [ ] Selecting a run renders a timeline visualization with step bars and event dots
- [ ] Steps are color-coded by role (architect=blue, backend=green, frontend=purple, qa=orange, docs=gray)
- [ ] Play/pause button controls replay animation along the timeline
- [ ] Speed selector offers 0.5×, 1×, 2×, 4× playback speeds
- [ ] Clicking an event dot shows detail panel with timestamp, action, and result
- [ ] Live mode auto-scrolls timeline when new stage log events arrive via WebSocket

**Effort:** L
**AID Role:** frontend

---

### Step 23: Decision Hub Notifications

**Objective:** Add audio and browser notification support to the Decision Hub page so the PM is alerted when new pending decisions arrive, even in a background tab.

**Files:**
- Modify: `packages/aid-gui/src/screens/DecisionHub.tsx` — add notification trigger on new pending decisions
- Create: `packages/aid-gui/src/hooks/useNotifications.ts` — notification hook with Web Audio API sound and browser Notification API
- Modify: `packages/aid-gui/src/components/Sidebar.tsx` — add pulse animation on DecisionHub badge when pending > 0
- Modify: `packages/aid-gui/src/hooks/useWebSocket.ts` — trigger notification on new pending decision event

**Architecture Context:**
The Decision Hub page at `packages/aid-gui/src/screens/DecisionHub.tsx` already displays pending decisions from the `DecisionsSlice`. This step adds notifications when new decisions arrive via WebSocket. The notification hook manages two channels: (1) Web Audio API generates a short notification sound, and (2) browser Notification API shows a system notification when the tab is in the background. The sidebar badge for Decision Hub pulses when `pendingDecisions > 0`.

**Implementation Detail:**

1. **useNotifications hook**:
   ```typescript
   export function useNotifications() {
     const playSound = useCallback(() => {
       const ctx = new AudioContext();
       const oscillator = ctx.createOscillator();
       const gain = ctx.createGain();
       oscillator.connect(gain);
       gain.connect(ctx.destination);
       oscillator.frequency.value = 880; // A5 note
       gain.gain.value = 0.3;
       oscillator.start();
       gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.5);
       oscillator.stop(ctx.currentTime + 0.5);
     }, []);

     const showBrowserNotification = useCallback((title: string, body: string) => {
       if (Notification.permission === 'granted' && document.hidden) {
         new Notification(title, { body, icon: '/favicon.ico' });
       }
     }, []);

     const requestPermission = useCallback(async () => {
       if (Notification.permission === 'default') {
         await Notification.requestPermission();
       }
     }, []);

     return { playSound, showBrowserNotification, requestPermission };
   }
   ```

2. **WebSocket integration** — in `useWebSocket.ts`, in the `decisions` case of `dispatchEvent()`:
   ```typescript
   case 'decisions': {
     // ... existing logic ...
     // Trigger notification for new pending decisions
     if (Array.isArray(parsed) && parsed.length > prevPendingCount) {
       const { playSound, showBrowserNotification } = useNotifications();
       playSound();
       showBrowserNotification('New Decision Required', `${parsed.length} pending decision(s) awaiting your review`);
     }
   }
   ```

3. **Sidebar pulse animation** — in `Sidebar.tsx`, add badge to Decision Hub nav item:
   ```tsx
   {pendingDecisions > 0 && (
     <span className="absolute -top-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-red-600 text-xs font-bold text-white animate-pulse">
       {pendingDecisions}
     </span>
   )}
   ```

4. **Permission request** — on Decision Hub page mount, request notification permission if not yet granted.

**Error Handling:**
- AudioContext not available (very old browser): skip sound, log warning
- Notification permission denied: browser notification silently skipped, sound still plays
- Service worker not available: `Notification` API may not work — graceful degradation

**Edge Cases:**
- Tab is focused: skip browser notification, only play sound
- Multiple rapid decision events: debounce sound (max 1 per 3 seconds) to avoid annoying rapid beeping
- Decision count decreases (PM resolved a decision): no notification, badge updates silently
- Page reload: re-request notification permission if needed

**Dependencies:**
- Depends on: Step 7 — WebSocket decisions subscription must be active (already exists from Phase 1)

**Acceptance Criteria:**
- [ ] Audio notification plays when a new pending decision arrives via WebSocket
- [ ] Browser notification shown when new decision arrives while tab is in background
- [ ] Sidebar Decision Hub badge shows pending count with pulse animation when > 0
- [ ] Sound is debounced (max once per 3 seconds)
- [ ] Notification permission requested on first visit to Decision Hub page
- [ ] No notification when pending count decreases

**Effort:** M
**AID Role:** frontend

---

### Step 24: Phase 3 Verification — Vitest + Playwright

**Objective:** Write Vitest unit tests for Phase 3 backend services (evidence search, pipeline theater data) and Playwright smoke tests for the Evidence Vault search, Pipeline Theater timeline, and Decision Hub notifications.

**Files:**
- Create: `packages/aid-gui/tests/server/services/evidence-search.test.ts` — unit tests for evidence search logic
- Create: `packages/aid-gui/tests/server/api/pipeline-theater.test.ts` — unit tests for theater data endpoint
- Create: `packages/aid-gui/tests/frontend/store-evidence-extended.test.ts` — unit tests for extended EvidenceSlice
- Create: `packages/aid-gui/tests/e2e/phase3-polish.spec.ts` — Playwright smoke test

**Architecture Context:**
Phase 3 tests follow the established patterns. Evidence search tests create temp evidence directories with sample files, verify search finds correct matches and respects limits. Pipeline theater tests verify correct data merging from plan.json + plan_progress.json + stage_log.jsonl. Playwright tests visit all three redesigned pages.

**Implementation Detail:**

1. **Evidence search tests**:
   - Test: search finds matching text in evidence files
   - Test: search respects limit parameter
   - Test: search skips binary files
   - Test: empty evidence directory returns empty results

2. **Pipeline theater tests**:
   - Test: theater data merges plan steps with progress status
   - Test: duration calculated from stage log timestamps
   - Test: missing plan_progress.json defaults all steps to pending
   - Test: missing stage_log.jsonl returns empty events

3. **Playwright smoke test**:
   ```typescript
   test('evidence search returns results', async ({ page }) => {
     await page.goto('/evidence');
     const search = page.getByPlaceholder('Search evidence');
     await search.fill('error');
     await page.waitForTimeout(500); // debounce
     // Verify results appear or "no results" message
   });

   test('pipeline theater renders timeline', async ({ page }) => {
     await page.goto('/pipeline');
     // If runs exist, verify timeline elements
     await expect(page.getByText('Pipeline Theater')).toBeVisible();
   });

   test('decision hub has notification badge', async ({ page }) => {
     await page.goto('/decisions');
     await expect(page.getByText('Decision Hub')).toBeVisible();
   });
   ```

**Error Handling:**
- Tests with no evidence data: verify empty state messages render correctly

**Edge Cases:**
- Playwright test timing: use `waitForTimeout` for debounced search, `waitForSelector` for dynamic content

**Dependencies:**
- Depends on: Steps 20-23 — all Phase 3 features must be implemented

**Acceptance Criteria:**
- [ ] `npx vitest run` passes all new Phase 3 test files
- [ ] Evidence search tests verify correct matching, limit, and binary skip behavior
- [ ] Pipeline theater tests verify data merging from 3 source files
- [ ] Playwright tests verify Evidence search UI, Pipeline Theater page, Decision Hub page
- [ ] All Phase 1 and Phase 2 tests continue to pass (regression)

**Effort:** M
**AID Role:** qa

---

### Step 25: CHANGELOG + Documentation

**Objective:** Update both CHANGELOG files with all Phase 1-3 features and update the root README Roadmap section.

**Files:**
- Modify: `CHANGELOG.md` — add P016 feature entries under a new version header
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical copy of root CHANGELOG entry
- Modify: `README.md` — update Roadmap section with new version summary

**Architecture Context:**
Per CLAUDE.md, both CHANGELOGs must be identical and follow the Keep a Changelog format. Each entry starts with `- **Bold Name** — description`. The README Roadmap section shows the 3 most recent versions. This step runs after all 3 phases are complete and all tests pass.

**Implementation Detail:**

1. **CHANGELOG entry** (template — version determined at release time):
   ```markdown
   ## [X.Y.Z] — YYYY-MM-DD

   ### Added
   - **5-Column Kanban** — Ideas flow through Ideas → Plan → EPIC → Running → Done with automatic status transitions via WebSocket
   - **IDEAS.md Migration** — Server startup imports from IDEAS.md, shutdown exports back; deduplication by title
   - **Insights Panel** — Backlog and Lessons Learned tabs below kanban with drag-to-kanban for backlog entries
   - **AI Companion Chat** — Cmd+K slide-down panel with dual-mode adapter (ai-sdk-provider primary, CLI proxy fallback)
   - **Hint Commands** — 7 context-aware prompt buttons: Brainstorm, Plan EPIC, Run, Audit, Explain, Fix, Free chat
   - **Voice Dictation** — Whisper API transcription with push-to-talk and Web Speech API fallback
   - **EPIC Lifecycle** — EPIC metadata endpoints, building animation, Queue Scheduler integration
   - **Auto-Transitions** — WebSocket-driven card movement between kanban columns based on EPIC execution state
   - **Evidence Vault Search** — Full-text search across evidence files with grouped-by-date display and markdown preview
   - **Pipeline Theater Replay** — Timeline visualization with color-coded roles, replay controls, and live mode
   - **Decision Hub Notifications** — Web Audio sound and browser Notification API for pending decisions

   ### Changed
   - **StoredIdea Type** — Added autoStatus field for automatic kanban column placement
   - **WebSocket Topics** — Added ideas, epics, companion.stream, companion.session topics
   ```

2. **README Roadmap** — add new version line at top, move previous down, keep 3 most recent.

**Error Handling:**
- Version number not yet determined: use placeholder `[X.Y.Z]` — the release step will replace it

**Edge Cases:**
- CHANGELOG entry exceeds typical size: acceptable for a 3-phase plan; each feature gets one line
- Previous version entry references must not be modified

**Dependencies:**
- Depends on: Steps 1-24 — all features must be implemented and tested

**Acceptance Criteria:**
- [ ] Root `CHANGELOG.md` has a new version section with all P016 features listed
- [ ] `plugins/aid-orchestrator/CHANGELOG.md` is identical to the root CHANGELOG entry
- [ ] Each CHANGELOG entry follows format: `- **Bold Name** — description` (em dash)
- [ ] README.md Roadmap section updated with new version summary
- [ ] No other files modified in this step

**Effort:** S
**AID Role:** docs

## Success Criteria

- Ideas kanban: create idea → link to plan → generate EPIC → run → done — full flow works with automatic column transitions
- AI Companion: open chat with Cmd+K, brainstorm a topic, receive streaming response, dictate in Czech via push-to-talk
- EPIC cards: drag from Plan column → building animation → EPIC card with step count and role badges
- Queue Scheduler: view all EPICs, "Run Now" for immediate execution, "Schedule" for queue placement
- Evidence Vault: search past runs by text query, view markdown-rendered reports grouped by date
- Pipeline Theater: select past run, see timeline with color-coded role events, use replay controls
- Decision Hub: receive audio + browser notification when pending decision arrives
- All Playwright + Vitest tests pass after each phase with zero regressions

## Next Steps

- [ ] Archive E-009-2_5 to `.aid-o/02-epics/archive/`
- [ ] Create EPIC for Phase 1 → `/aid-plan-epic .aid-o/01-plans/P016-gui-workflow-pipeline.md`
- [ ] Run Phase 1 EPIC via `/aid-run-epic`
- [ ] After Phase 1: verify kanban in browser, run Playwright test
- [ ] Create EPIC for Phase 2
- [ ] Create EPIC for Phase 3

---

**Last Updated:** 2026-02-27
