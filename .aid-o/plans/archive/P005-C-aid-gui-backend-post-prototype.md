---
id: P005-C
type: plan
status: done
created: 2026-02-25
author: PM + AI
parent: P005
depends_on: []
supersedes_scope: P005-A
---

# Plan: AID GUI Dashboard — Backend & Infrastructure (Post-Prototype)

## Context

This plan replaces the scope of P005-A for the post-prototype reality. The AI Studio prototype (repo: `AID-GUI`) provides a working React frontend with 9 screens, mock Express server, and complete visual design system ("Orchestration Cinema"). The frontend code is solid but runs entirely on hardcoded mock data.

This plan covers: cleaning up AI Studio artifacts, building the real backend that reads `.aid-o/` files, WebSocket real-time streaming, and CLI entry point. The frontend remains as-is from AI Studio — P005-D handles connecting it to real data.

**Key difference from P005-A:** We already have a project scaffold, Express server, Vite config, and package.json. We don't build from scratch — we transform mock into real.

## Goal

Transform the AI Studio mock server into a production backend that watches `.aid-o/` directories, parses all file formats, exposes REST API + WebSocket event stream, and starts with `npx aid-gui`.

## Scope

**In scope:**
- Cleanup of AI Studio artifacts (Gemini refs, metadata, naming)
- Restructured server directory (`server/` with parsers, watchers, api, ws)
- Shared TypeScript parsers for all .aid-o/ file formats
- Chokidar file watcher on `.aid-o/` directories
- WebSocket server (ws library) for real-time events
- stage_log.jsonl tail-follow streaming
- REST API read endpoints for all .aid-o/ entities
- REST API write endpoints (decisions, queue, ideas)
- CLI entry point (`npx aid-gui` with flags)
- Multi-project registry
- Ideas CRUD storage
- CC usage tracking (token-based, from stage_log.jsonl)
- Queue scheduling engine
- Integration tests

**Out of scope:**
- Frontend visual changes (see P005-D)
- AI companion backend (deferred — requires Qdrant integration design)
- Authentication / multi-user
- Cloud deployment

## Approach

### Chosen: Transform Existing Scaffold

The AI Studio prototype already has Express + Vite + TypeScript. Instead of creating `packages/aid-gui/` in the monorepo (as P005-A proposed), we keep AID-GUI as a standalone repository. This is cleaner — it's an independent tool that reads from any `.aid-o/` directory.

**Rationale:** Standalone repo allows independent versioning, npm publishing, and usage across any AID project. The monorepo approach from P005-A is unnecessary for a consumer tool.

### Repository Location

- Source: `https://github.com/marekstancl/AID-GUI`
- Local: `/opt/_home/small-personal-projetcs/AID-GUI/`
- Target structure after refactoring:

```
AID-GUI/
├── bin/
│   └── aid-gui.ts                 # CLI entry point (commander.js)
├── server/
│   ├── index.ts                   # Express + Vite + WebSocket bootstrap
│   ├── types.ts                   # All shared TypeScript interfaces
│   ├── parsers/
│   │   ├── yaml.ts                # YAML parser (js-yaml)
│   │   ├── jsonl.ts               # JSONL line parser
│   │   ├── markdown.ts            # Markdown frontmatter (gray-matter)
│   │   └── json.ts                # JSON with schema validation
│   ├── watchers/
│   │   ├── file-watcher.ts        # Chokidar on .aid-o/ directories
│   │   └── stage-log-stream.ts    # Tail-follow stage_log.jsonl
│   ├── api/
│   │   ├── pipeline.ts            # GET pipeline state, steps, stage_log
│   │   ├── epics.ts               # GET epics list + detail
│   │   ├── plans.ts               # GET plans list + detail
│   │   ├── evidence.ts            # GET evidence tree + file content
│   │   ├── decisions.ts           # GET/POST pending + history
│   │   ├── queue.ts               # GET/POST/PUT queue management
│   │   ├── config.ts              # GET policies, playbooks, templates
│   │   ├── audit.ts               # GET audit reports + history
│   │   ├── usage.ts               # GET CC token usage
│   │   ├── ideas.ts               # CRUD ideas
│   │   ├── projects.ts            # CRUD multi-project registry
│   │   └── knowledge.ts           # GET agents, skills, commands
│   └── ws/
│       └── websocket.ts           # WebSocket server + topic subscriptions
├── src/                           # Frontend (existing from AI Studio, see P005-D)
│   └── ...
├── tests/
│   ├── server/
│   │   ├── parsers/
│   │   ├── api/
│   │   └── watchers/
│   └── fixtures/                  # Real .aid-o/ sample files for testing
├── package.json
├── tsconfig.json
├── vite.config.ts
└── .env.example
```

## High-Level Steps

| # | Task | Description | Effort |
|---|------|-------------|--------|
| 1 | AI Studio cleanup | Remove `@google/genai` dep, `metadata.json`, Gemini refs in vite.config.ts. Rename package to `aid-gui`, fix index.html title. Clean `.env.example`. Verify `npm install && npm run dev` works locally. | S |
| 2 | Server directory structure | Create `server/`, `server/parsers/`, `server/watchers/`, `server/api/`, `server/ws/`, `tests/`, `tests/fixtures/`. Move and refactor `server.ts` into `server/index.ts`. | S |
| 3 | TypeScript types | `server/types.ts` — interfaces for all .aid-o/ entities: `StageLogEntry`, `PipelineState`, `EpicSpec`, `PlanJSON`, `PlanProgress`, `GatesReport`, `Decision`, `AuditReport`, `Idea`, `QueueSchedule`, `CCUsage`, `Project`. Reuse FSMState type from existing `src/store.ts`. | S |
| 4 | Shared parsers | `server/parsers/` — YAML (js-yaml), JSONL (line-by-line JSON.parse), Markdown frontmatter (gray-matter), JSON with defensive error handling. Each parser returns typed result or partial result with warnings. Unit tests with fixture files copied from real `.aid-o/`. | M |
| 5 | File watcher + event pipeline | `server/watchers/file-watcher.ts` — Chokidar watcher on `.aid-o/` root. Event pipeline: file change → detect type by path pattern → parse → normalize → emit typed internal event. Debounce rapid changes (50ms). Configurable ignore patterns (node_modules, .git, large binaries). Watch only active evidence directory. | M |
| 6 | stage_log.jsonl streaming | `server/watchers/stage-log-stream.ts` — Tail-follow active `stage_log.jsonl` using fs.watch + readline. Parse each new line. Buffer last 100 entries for replay on new client connect. Handle file rotation (new run = new stage_log detected via file watcher). Emit events to WebSocket broadcast. | M |
| 7 | WebSocket server | `server/ws/websocket.ts` — ws library. Protocol: `{type, topic, data}` JSON messages. Topics: `pipeline`, `pipeline.stage_log`, `evidence`, `decisions`, `config`, `queue`, `audit`, `usage`. Client subscribes by topic. Heartbeat every 30s. Auto-reconnect support (client-side in P005-D). Broadcast file change events from Step 5. Broadcast stage_log entries from Step 6. | M |
| 8 | REST API — Pipeline & Evidence | `server/api/pipeline.ts` — GET current pipeline state (find active run, parse plan.json + plan_progress.json + stage_log summary). `server/api/evidence.ts` — GET evidence tree for EPIC/run, GET file content with format-specific parsing (MD rendered, YAML parsed, JSONL as array, diff as-is). | M |
| 9 | REST API — EPICs, Plans, Config | `server/api/epics.ts` — list + detail from `02-epics/`. `server/api/plans.ts` — list + detail from `01-plans/`. `server/api/config.ts` — policies, playbooks, templates from `03-config/`. `server/api/knowledge.ts` — parse agent/skill/command markdown files from plugin directory, return structured inventory. | M |
| 10 | REST API — Decisions & Audit | `server/api/decisions.ts` — GET pending decisions (scan active evidence for missing pm_decision.json), GET history (all past decisions with timestamps). POST decision response (atomic write pm_decision.json). `server/api/audit.ts` — GET audit reports from evidence directories, parse audit-report.yaml. | M |
| 11 | REST API — Queue & Usage | `server/api/queue.ts` — GET/POST/PUT/DELETE for EPIC queue management. Reads/writes `epic-queue.yaml` or GUI-specific `~/.aid-gui/queue.json`. Reorder, add, remove, pause/resume. `server/api/usage.ts` — GET token usage aggregated from stage_log.jsonl entries. User-configured limit from `~/.aid-gui/cc-plan.json`. 7-day history, per-EPIC breakdown. | M |
| 12 | Ideas storage | `server/api/ideas.ts` — CRUD for ideas. Storage: `~/.aid-gui/ideas.json` (per-project keyed). Fields: id, title, description, tags, priority, status, linked_plan, linked_epic, created_at, updated_at. Atomic writes (temp → rename). | S |
| 13 | Queue scheduling engine | Timer-based engine in `server/api/queue.ts`: cooldown between EPICs, max concurrent (default 1), delayed start, auto-pause at CC limit. Schedule persists in `~/.aid-gui/schedules.json`. WebSocket topic `queue.schedule` broadcasts countdown updates. | M |
| 14 | Multi-project support | `server/api/projects.ts` — Project registry at `~/.aid-gui/projects.json`. Auto-register on startup. CRUD API. Watcher management: switch watchers when active project changes. | S |
| 15 | CLI entry point | `bin/aid-gui.ts` — commander.js CLI. Flags: `--port` (default 4200), `--project` (path to directory containing .aid-o/), `--no-open`, `--plugin-dir` (path to AID plugin for Knowledge Base). Auto-opens browser on start. Resolves `.aid-o/` from project path. | S |
| 16 | Integration tests | API tests against real .aid-o/ fixture data. WebSocket subscription + event tests. stage_log streaming test. Parser edge case tests (malformed YAML, empty JSONL, missing files). | M |

## New Dependencies (to add to package.json)

```
# Backend
chokidar          # File watching
ws                # WebSocket server
js-yaml           # YAML parsing
gray-matter       # Markdown frontmatter
commander         # CLI flags
open              # Auto-open browser

# Dev
@types/ws
vitest            # Testing (replace or add alongside existing)
```

## Dependencies to Remove

```
@google/genai     # AI Studio artifact — not needed
better-sqlite3    # AI Studio artifact — we use no database
dotenv            # Not needed if we use Vite env handling
```

## API Contract Summary

### REST Endpoints

```
GET  /api/health                              → { status, version, project }
GET  /api/projects                            → Project[]
POST /api/projects                            → Project (register new)

GET  /api/p/:id/pipeline                      → PipelineState
GET  /api/p/:id/pipeline/steps                → Step[]
GET  /api/p/:id/pipeline/stage-log            → StageLogEntry[] (last 100)

GET  /api/p/:id/epics                         → EpicSummary[]
GET  /api/p/:id/epics/:epicId                 → EpicDetail

GET  /api/p/:id/plans                         → PlanSummary[]
GET  /api/p/:id/plans/:planId                 → PlanDetail (rendered MD)

GET  /api/p/:id/evidence/:epicId              → Run[]
GET  /api/p/:id/evidence/:epicId/:runId       → FileTree
GET  /api/p/:id/evidence/:epicId/:runId/files/* → Raw file content

GET  /api/p/:id/decisions/pending             → Decision[]
GET  /api/p/:id/decisions/history             → Decision[]
POST /api/p/:id/decisions                     → { ok } (write pm_decision.json)

GET  /api/p/:id/config                        → { policies, playbooks, templates }
GET  /api/p/:id/audit                         → AuditReport[]

GET  /api/p/:id/queue                         → QueueSchedule
POST /api/p/:id/queue                         → QueueSchedule (add EPIC)
PUT  /api/p/:id/queue                         → QueueSchedule (reorder/update)
DELETE /api/p/:id/queue/:epicId               → { ok }

GET  /api/p/:id/usage                         → CCUsage
GET  /api/p/:id/usage/history                 → CCUsage.per_epic_history

GET  /api/p/:id/ideas                         → Idea[]
POST /api/p/:id/ideas                         → Idea
PUT  /api/p/:id/ideas/:ideaId                 → Idea
DELETE /api/p/:id/ideas/:ideaId               → { ok }

GET  /api/p/:id/knowledge                     → { agents, skills, commands }
```

### WebSocket Protocol

```typescript
// Client → Server
{ type: "subscribe", topics: ["pipeline", "pipeline.stage_log", "decisions", "queue", "usage"] }
{ type: "unsubscribe", topics: ["pipeline"] }

// Server → Client
{ type: "event", topic: "pipeline", data: StageLogEntry }
{ type: "event", topic: "pipeline.stage_log", data: StageLogEntry }
{ type: "event", topic: "decisions", data: { pending: boolean, decision: Decision } }
{ type: "event", topic: "evidence", data: { file: string, action: "created"|"modified", epic: string, run: string } }
{ type: "event", topic: "queue", data: QueueSchedule }
{ type: "event", topic: "usage", data: CCUsage }
{ type: "heartbeat" }
```

### Key Types

```typescript
interface StageLogEntry {
  timestamp: string;
  state: FSMState;
  step: string | null;
  action: string;
  details: string;
  result: "pass" | "fail" | "pending" | "skip" | "success";
}

interface PipelineState {
  epic_id: string;
  run_id: string;
  fsm_state: FSMState;
  current_step: string | null;
  progress: { total_steps: number; completed: number; percentage: number };
  duration: string;
  stage_log: StageLogEntry[];
}

// Token-based usage tracking (estimated from stage_log.jsonl)
interface CCUsage {
  current_tokens: number;
  daily_limit_tokens: number;
  usage_pct: number;
  estimated_remaining_epics: number;
  avg_tokens_per_epic: number;
  daily_history: Array<{ date: string; tokens: number }>;
  per_epic_history: Array<{ epic_id: string; tokens: number; steps: number; completed_at: string }>;
  auto_paused: boolean;
}

interface Idea {
  id: string;
  title: string;
  description: string;
  tags: string[];
  priority: "low" | "medium" | "high";
  status: "idea" | "planned" | "queued" | "done";
  linked_plan?: string;
  linked_epic?: string;
  created_at: string;
  updated_at: string;
}

interface QueueSchedule {
  epics: Array<{
    epic_id: string;
    scheduled_at?: string;
    estimated_duration_min: number;
    status: "pending" | "cooldown" | "running" | "done" | "paused";
  }>;
  settings: {
    cooldown_minutes: number;
    max_concurrent: number;
    auto_pause_at_pct: number;
    start_at?: string;
  };
}
```

## Constraints

- Runtime: Node.js >= 18
- Language: TypeScript (strict mode)
- Repository: Standalone (`AID-GUI`), not in ai-orchestrator monorepo
- Distribution: npm package with bin entry (`npx aid-gui`)
- No own database — all data from .aid-o/ files
- GUI-specific storage: `~/.aid-gui/` (projects.json, ideas.json, schedules.json, cc-plan.json)
- Atomic writes for any .aid-o/ modifications (temp file → rename)
- File ownership: GUI writes only decisions + queue + ideas; AID plugin owns evidence, logs, config
- Default port: 4200
- CORS: not needed (same-origin, single process)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Fragile .aid-o/ parsers | High | Medium | Defensive parsing with partial results + warnings, test fixtures from real files |
| Race condition: GUI vs Claude Code writes | Medium | High | Atomic writes (temp→rename), clear file ownership, read-retry on parse error |
| Chokidar performance with large evidence | Low | Medium | Watch only active evidence, lazy load archives, configurable ignore patterns |
| stage_log.jsonl format changes | Medium | Medium | Loose parsing — extract known fields, pass unknown through |
| CC usage token estimation inaccuracy | Medium | Low | Show as "~estimated", allow manual override in cc-plan.json |
| Plugin directory location varies | Medium | Medium | CLI flag `--plugin-dir`, auto-detect from common paths |

## Success Criteria

- `npx aid-gui --project /path/to/project` starts server and opens browser
- All REST endpoints return correctly parsed .aid-o/ data from real project
- WebSocket broadcasts file changes within 100ms of write
- stage_log.jsonl streaming delivers new events to clients in real-time
- Decision POST writes pm_decision.json atomically, pipeline picks it up
- Queue scheduling with cooldowns works across server restarts
- CC usage shows estimated token consumption with 7-day history
- Knowledge Base endpoint returns all 18 agents, 20 skills, 13 commands
- Integration tests pass against real .aid-o/ fixture data

## Dependency Chain

```
P005-C Steps 1-2 (cleanup, structure)
  → P005-C Steps 3-4 (types, parsers)
    → P005-C Steps 5-7 (watchers, WebSocket) — can parallel with Steps 8-11
    → P005-C Steps 8-11 (REST API) — can parallel with Steps 5-7
      → P005-C Steps 12-15 (ideas, queue, multi-project, CLI)
        → P005-C Step 16 (integration tests)
          → P005-D (frontend integration)
```

---

**Last Updated:** 2026-02-25
