---
id: P005-A
type: plan
status: done
created: 2026-02-24
author: PM + AI
parent: P005
---

# Plan: AID GUI Dashboard — Backend & Infrastructure

## Context

This plan covers the server-side infrastructure for the AID GUI Dashboard. It is derived from the original P005 plan, split into backend (P005-A) and frontend/UX (P005-B) to allow independent development and clear separation of concerns.

The backend provides: Express server, file system watchers, WebSocket real-time events, REST API for all .aid-o/ data, stage_log.jsonl streaming, AI companion backend (Qdrant + project context), CLI entry point, and multi-project support.

The frontend plan (P005-B) consumes this API and defines the visual experience.

## Goal

Build a Node.js backend that watches `.aid-o/` directories, parses all file formats (YAML, JSON, JSONL, Markdown), exposes a complete REST API + WebSocket event stream, provides AI companion context aggregation, and starts with a single `npx aid-gui` command.

## Scope

**In scope:**
- Express server with TypeScript
- Chokidar file watcher on `.aid-o/` directories
- WebSocket server (ws library) for real-time file change events
- stage_log.jsonl streaming — tail-follow new lines, broadcast via WebSocket
- REST API for all .aid-o/ entities (EPICs, plans, evidence, config, queue, audit, decisions, runs)
- Shared TypeScript parsers for all .aid-o/ file formats
- AI companion backend — Qdrant proxy + project context aggregation endpoint
- CLI entry point: `npx aid-gui` with flags (--port, --project, --no-open)
- Multi-project registry (~/.aid-gui/projects.json)
- Ideas CRUD storage (~/.aid-gui/ideas.json)
- Queue scheduling — delayed start, cooldown between EPICs, per-EPIC schedule
- CC usage tracking — proxy to Claude Code plan data, historical cost per run/EPIC
- Vite static file serving for production build
- npm package distribution

**Out of scope:**
- Frontend components (see P005-B)
- Visual design, animations, UX (see P005-B)
- Authentication / multi-user
- Cloud deployment
- Direct EPIC execution (AID plugin handles that)

## Approach

### Chosen: Monolithic SPA Backend (from P005)

Single Node.js process: Express backend + Vite static serving + WebSocket server. Backend watches `.aid-o/` directories via chokidar, parses files, exposes REST API + WebSocket events.

**Rationale:** Solo developer tool on localhost — single process is ideal UX. `npx aid-gui` and done.

## High-Level Steps

| # | Task | Description | Effort |
|---|------|-------------|--------|
| 1 | Project scaffold | `packages/aid-gui/` with package.json, tsconfig.json, Vite config, npm workspaces in root package.json, .gitignore updates | S |
| 2 | CLI entry point | `bin/aid-gui` using commander.js — --port (default 4200), --project (path to .aid-o/), --no-open, --global. Auto-opens browser on start. | S |
| 3 | Shared parsers | .aid-o/ format parsers: YAML (js-yaml), Markdown frontmatter (gray-matter), JSONL line parser, JSON schema validators. TypeScript types for all entities: EPIC, Plan, Run, Evidence, Config, AuditReport, StageLogEntry, Decision, GatesReport, PlanProgress. Unit tests with real .aid-o/ fixture files. | M |
| 4 | File watcher + event pipeline | Chokidar watcher on .aid-o/ directories (configurable depth, ignore patterns for large files). Event pipeline: file change → detect type → parse → normalize → emit internal event. Debounce rapid changes (50ms). Watch only active evidence directory (not all archived runs). | M |
| 5 | WebSocket server | ws library WebSocket server. Protocol: JSON messages with `{type, topic, data}` structure. Topics: `pipeline`, `evidence`, `decisions`, `config`, `queue`, `audit`. Client subscription by topic. Heartbeat/reconnect support. Broadcast file change events from Step 4. | M |
| 6 | stage_log.jsonl streaming | Tail-follow active `stage_log.jsonl` file using fs.watch + readline. Parse each new line as JSON. Broadcast via WebSocket topic `pipeline.stage_log`. Buffer last 100 entries for new client connections (replay on connect). Handle file rotation (new run = new stage_log). | M |
| 7 | REST API — Read endpoints | GET endpoints for all .aid-o/ data: `/api/p/:projectId/epics` (list + detail), `/api/p/:projectId/plans` (list + detail, rendered MD), `/api/p/:projectId/pipeline` (plan.json + plan_progress.json + stage_log summary), `/api/p/:projectId/evidence/:epicId/:runId` (file tree + content), `/api/p/:projectId/evidence/:epicId/:runId/files/*` (raw file content), `/api/p/:projectId/config` (all policy YAML files), `/api/p/:projectId/queue` (epic-queue.yaml), `/api/p/:projectId/audit` (audit reports + history), `/api/p/:projectId/runs` (run list with status), `/api/p/:projectId/decisions/pending` (pending PM decisions), `/api/p/:projectId/decisions/history` (decision history), `/api/help` (AID documentation content). | L |
| 8 | REST API — Write endpoints | POST/PUT/DELETE endpoints: `/api/p/:projectId/decisions` (write pm_decision.json — atomic write via temp→rename), `/api/p/:projectId/queue` (reorder, add, remove, pause/resume — write epic-queue.yaml), `/api/projects` (CRUD for multi-project registry). File ownership rules enforced: GUI writes only decisions + queue + ideas; AID plugin owns evidence + logs. | M |
| 9 | Ideas storage | CRUD API for ideas: `/api/p/:projectId/ideas`. Storage: `~/.aid-gui/ideas.json` (per-project keyed). Fields: id, title, description, tags, priority, status (idea/planned/queued/done), linked_plan, linked_epic, created_at, updated_at. No database — simple JSON file with atomic writes. | S |
| 10 | AI companion backend | `/api/p/:projectId/companion/query` — POST endpoint that: (a) takes natural language query, (b) searches Qdrant via existing MCP proxy for relevant knowledge (decisions, lessons, patterns, commands), (c) aggregates project context (active-work.md, project-profile.yaml, backlog.md), (d) returns structured response with sources and relevance scores. Fallback: if Qdrant unavailable, return project context only with "memory unavailable" flag. Preset suggestions endpoint: `/api/p/:projectId/companion/presets` — returns contextual suggestions based on current project state. | M |
| 11 | Queue scheduling | `/api/p/:projectId/queue/schedule` — POST/PUT endpoint for queue execution schedule. Stores schedule in `~/.aid-gui/schedules.json`: per-EPIC start time, cooldown duration between EPICs (default 30min), max concurrent (default 1), auto-pause-at-limit flag. Schedule engine: Node.js setTimeout/setInterval that writes to `epic-queue.yaml` when an EPIC's scheduled time arrives, triggering FIRST AID pickup. WebSocket topic `queue.schedule` broadcasts countdown updates (every 30s). Cancel/modify schedule endpoints. | M |
| 12 | CC usage tracking | `/api/p/:projectId/usage` — GET endpoint that aggregates Claude Code usage data. Sources: (a) parse plan_progress.json `budget` fields from completed runs for cost-per-EPIC history, (b) read CC plan limits from environment or config (`~/.aid-gui/cc-plan.json`: plan_name, daily_limit, monthly_limit), (c) calculate: current spend, remaining budget, estimated EPICs remaining (avg cost), 7-day daily trend. `/api/p/:projectId/usage/history` — historical cost per run. Auto-pause logic: when usage crosses configurable threshold (default 90%), write pause flag to queue schedule. | M |
| 13 | Multi-project support | Project registry at `~/.aid-gui/projects.json` — list of registered projects with name, path, last_accessed. Auto-detect: on startup, register the --project path (or cwd). Watcher management: only watch active project, switch watchers when project changes. API: `/api/projects` CRUD. | S |
| 14 | Integration tests | API integration tests: start server, hit endpoints, verify responses against real .aid-o/ fixture data. WebSocket tests: connect, subscribe, trigger file change, verify event received. stage_log streaming test: append line to JSONL, verify WebSocket broadcast. Schedule engine tests: verify timer triggers queue writes. | M |

## Constraints

- Runtime: Node.js >= 18
- Language: TypeScript (strict mode)
- Location: `packages/aid-gui/` in ai-orchestrator monorepo
- Distribution: npm package with bin entry
- No own database — all data from .aid-o/ files + Qdrant (existing)
- GUI-specific storage: `~/.aid-gui/` (projects.json, ideas.json, preferences.json)
- Atomic writes for any .aid-o/ modifications (temp file → rename)
- File ownership: GUI writes only decisions, queue, ideas; AID plugin owns evidence, logs, config templates
- Default port: 4200
- CORS: not needed (same-origin, single process)

## API Contract Summary

### WebSocket Protocol

```typescript
// Client → Server
{ type: "subscribe", topics: ["pipeline", "evidence", "decisions", "queue.schedule", "usage"] }
{ type: "unsubscribe", topics: ["pipeline"] }

// Server → Client
{ type: "event", topic: "pipeline", data: { event: "step_complete", step: "step_1_architect", ... } }
{ type: "event", topic: "pipeline.stage_log", data: { timestamp, state, step, action, details, result } }
{ type: "event", topic: "decisions", data: { pending: true, decision_type: "plan_approval", ... } }
{ type: "event", topic: "evidence", data: { file: "output.md", action: "modified", step: "step_2_backend" } }
{ type: "event", topic: "queue.schedule", data: { next_epic: "E-005", starts_in_seconds: 1200, cooldown_remaining: 600 } }
{ type: "event", topic: "usage", data: { current_spend: 12.40, daily_limit: 50, pct: 24.8, estimated_remaining_epics: 7 } }
{ type: "heartbeat" }
```

### Key Types

```typescript
interface StageLogEntry {
  timestamp: string;        // ISO 8601
  state: FSMState;          // IDLE | PLAN_REVIEW | EXECUTING | PHASE_CHECK | GATES | PM_APPROVAL | DONE | ...
  step: string | null;      // step_1_architect, etc.
  action: string;           // load_epic, transition, dispatch_agent, check_outputs, gates_start, ...
  details: string;          // Human-readable description
  result: "pass" | "fail" | "pending" | "skip";
}

interface PipelineState {
  epic_id: string;
  run_id: string;
  fsm_state: FSMState;
  current_step: string | null;
  progress: PlanProgress;
  stage_log: StageLogEntry[];  // Last 100 entries
  plan: PlanJSON;
}

interface Idea {
  id: string;
  title: string;
  description: string;
  tags: string[];
  priority: "low" | "medium" | "high";
  status: "idea" | "planned" | "queued" | "done";
  linked_plan?: string;     // P005, etc.
  linked_epic?: string;     // E-005-1_1, etc.
  scheduled_at?: string;   // ISO 8601 — delayed start time
  created_at: string;
  updated_at: string;
}

interface QueueSchedule {
  epics: Array<{
    epic_id: string;
    scheduled_at?: string;     // ISO 8601 — specific start time (null = after previous + cooldown)
    estimated_duration_min: number;  // From historical avg or step count heuristic
    status: "pending" | "cooldown" | "running" | "done" | "paused";
  }>;
  settings: {
    cooldown_minutes: number;        // Default 30, pause between EPICs
    max_concurrent: number;          // Default 1
    auto_pause_at_pct: number;       // Default 90 — pause queue at this CC usage %
    start_at?: string;               // ISO 8601 — delayed start for entire queue
  };
  created_at: string;
  updated_at: string;
}

// Token-based usage tracking (estimated from stage_log.jsonl)
// NOT dollar-based — Anthropic has no billing API accessible from CLI
interface CCUsage {
  current_tokens: number;            // Sum of tokens from today's stage_log entries
  daily_limit_tokens: number;        // User-configured token budget
  usage_pct: number;                 // 0-100
  estimated_remaining_epics: number; // Based on avg tokens per EPIC
  avg_tokens_per_epic: number;
  daily_history: Array<{             // Last 7 days
    date: string;
    tokens: number;
  }>;
  per_epic_history: Array<{          // Last 10 EPICs
    epic_id: string;
    tokens: number;
    steps: number;
    completed_at: string;
  }>;
  auto_paused: boolean;              // True if queue paused due to limit
}
// NOTE: Token counts are estimated. If stage_log doesn't contain token
// data, estimate from step count × avg_tokens_per_step heuristic.
```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Fragile .aid-o/ parsers | High | Medium | Defensive parsing with partial results + warnings, fallback to raw content, test fixtures from real files |
| Race condition: GUI vs Claude Code writes | Medium | High | Atomic writes (temp→rename), clear file ownership, read-retry on parse error |
| Chokidar performance with large evidence | Low | Medium | Watch only active evidence directory, lazy load archives, configurable ignore patterns |
| stage_log.jsonl growing unbounded | Low | Medium | Only tail last N lines on connect, stream new lines only, old entries available via REST |
| Qdrant unavailable for AI companion | Medium | Low | Graceful degradation — return project context only, "memory unavailable" flag |
| CC usage data accuracy | Medium | Medium | Best-effort from plan_progress.json budget fields; allow manual override in cc-plan.json; warn when data is stale |
| Schedule timer drift (long cooldowns) | Low | Low | Use absolute timestamps not relative delays; recalculate on server restart; persist schedule state |

## Success Criteria

- `npx aid-gui` starts server on localhost:4200 and opens browser
- All REST endpoints return correctly parsed .aid-o/ data
- WebSocket broadcasts file changes within 100ms of write
- stage_log.jsonl streaming delivers new events to connected clients in real-time
- AI companion endpoint returns Qdrant results + project context
- Multi-project: register, switch, isolated data per project
- Ideas CRUD works with persistent JSON storage
- Queue scheduling: set cooldown, delayed start, auto-pause — schedule persists across server restart
- CC usage endpoint returns current spend, limit, estimated remaining EPICs, 7-day history
- Auto-pause triggers when CC usage crosses threshold, queue resumes when limit resets
- Integration tests pass against real .aid-o/ fixture data

## Dependencies on P005-B

P005-B (Frontend) depends on this plan's API being stable. Recommended flow:
1. Complete P005-A Steps 1-8 (core backend)
2. Start P005-B frontend development against the API
3. P005-A Steps 9-12 (ideas, AI companion, multi-project, tests) can proceed in parallel with P005-B

---

**Last Updated:** 2026-02-24
