# P016 Specification — GUI Workflow: Ideas to Execution Pipeline

**Status:** DONE
**Source:** Brainstorming session 2026-02-27 (revision of P009 phases 2-3)
**Predecessor:** P009-gui-workflow-architecture.md (Phase 1 complete, phases 2-3 replaced by this plan)
**Archive:** E-009-2_5 → archive/ (replaced by new EPICs from this plan)

---

## Context

AID GUI dashboard (React 19 + Zustand + Tailwind v4, Express backend, WebSocket) has a stable foundation after P009 Phase 1 (E-009-1_5): all 9 pages load, WebSocket connected, 11 bugs fixed, Playwright verified. Now we need to build the workflow pipeline: ideas flowing through kanban stages, AI Companion chat for brainstorming, EPIC lifecycle management, and polished evidence/pipeline views.

**Technical blockers resolved:**
- CLI proxy (`claude -p --output-format stream-json --verbose`): works with Max/Pro subscription, `apiKeySource: "none"`, no API key needed
- `ai-sdk-provider-claude-code` npm package: `generateText()`/`streamText()` work with subscription auth, no API key
- Agent SDK native: requires `ANTHROPIC_API_KEY` (pay-per-token) — future v2 option

## Goal

Transform AID GUI from a monitoring dashboard into a functional workflow management tool where ideas flow through Ideas → Plan → EPIC → Running → Done with automatic status transitions, integrated AI Companion chat (dual-mode: ai-sdk-provider primary, CLI proxy fallback), Queue Scheduler integration, voice dictation, and polished Evidence Vault / Pipeline Theater / Decision Hub views.

## Architecture Decisions

1. **AI Companion dual-mode**: `ai-sdk-provider-claude-code` as primary adapter (better DX via `generateText()`/`streamText()`). CLI proxy (`child_process.spawn`) as fallback. Native Agent SDK as future v2 (API key required).
2. **Auto-detection**: (1) Try ai-sdk-provider → (2) CLI proxy fallback → (3) Show setup instructions in GUI.
3. **CompanionService interface**: Adapter pattern — frontend never knows which backend is active. Both adapters implement `send()`, `stream()`, `resume()`, `listSessions()`.
4. **3-phase approach**: Data Layer → AI Companion + EPIC lifecycle → Polish. Each phase independently testable.
5. **Testing strategy**: Playwright smoke tests + Vitest unit tests after every phase.

## Scope — 3 Phases

### Phase 1: Data Layer + Kanban (1 EPIC, ~8 steps)

**What:** Build the data foundation and rebuild the kanban UI.

- **IDEAS.md migration service**: Startup parse + merge into ideas.json (deduplicate by title), shutdown export back to IDEAS.md format. Register as server lifecycle hook.
- **StoredIdea type extension**: Add `linkedPlanId`, `linkedEpicId`, `autoStatus` fields. New `PUT /api/p/:id/ideas/:ideaId/link` endpoint. WebSocket `ideas.updated` event emission on all mutations.
- **Backlog endpoint**: `GET /api/p/:id/backlog` — parse `.aid-o/04-engine/memory/backlog.md` into structured JSON array.
- **Lessons endpoint**: `GET /api/p/:id/lessons` — parse `.aid-o/04-engine/lessons-learned.md` into structured JSON array.
- **5-column kanban rebuild**: Ideas / Plan / EPIC / Running / Done columns. Cards show linked plan/epic metadata.
- **Multi-select + Create Plan**: Checkbox selection on idea cards, "Create Plan" button appears when 1+ selected (stub action — actual creation via AI Companion in Phase 2).
- **Insights panel**: Below kanban, two tabs: Backlog (priority badges, status indicators) and Lessons Learned (categories, severity). Drag backlog entry onto kanban "Ideas" column creates new idea.
- **WebSocket subscription**: `ideas` topic in `useWebSocket.ts`, store updates on `ideas.updated` events.
- **Tests**: Playwright smoke (all pages load, kanban renders 5 columns, drag-drop works) + Vitest unit tests (migration service, backlog/lessons parsers, link endpoint).

### Phase 2: AI Companion + EPIC Lifecycle (1 EPIC, ~10 steps)

**What:** Add AI chat capabilities and EPIC workflow management.

**AI Companion:**
- **CompanionService interface**: `packages/aid-server/src/companion/` — `CompanionService` interface with `send()`, `stream()`, `resume()`, `listSessions()`.
- **ai-sdk-provider adapter** (primary): Use `ai-sdk-provider-claude-code` package. `streamText()` for streaming responses, session persistence to `.jsonl` files.
- **CLI proxy adapter** (fallback): `child_process.spawn('claude', ['-p', '--output-format', 'stream-json', '--verbose'])`. NDJSON parsing, session persistence.
- **Auto-detection service**: Check ai-sdk-provider availability → CLI proxy → setup instructions. Config in settings.
- **WebSocket bridge**: Stream companion responses to frontend via WebSocket events.
- **Chat UI**: Cmd+K slide-down panel, docked right-third, message bubbles with markdown rendering, streaming typewriter effect, session list sidebar.
- **Hint commands**: Pill buttons above input: Brainstorm, Plan EPIC, Run, Audit, Explain, Fix, Free chat. Context-aware (selected kanban card data pre-filled). Each hint = prompt template sent via CompanionService.
- **Voice dictation**: Whisper API proxy in backend, microphone button in chat input, push-to-talk, Czech language default, settings page for language/provider. Fallback to Web Speech API.

**EPIC Lifecycle:**
- **EPIC lifecycle endpoints**: `GET /api/p/:id/epics` (metadata from `.aid-o/02-epics/`), `POST /api/p/:id/epics/:epicId/run`, `POST /api/p/:id/commands/plan-epic`.
- **EPIC column UI**: Drag plan → EPIC triggers plan-epic command. "Building" animation (progress texts, pulsing border, settle animation). EPIC cards with step count and role badges.
- **Queue Scheduler integration**: All EPICs visible in Queue Scheduler page, "Run Now" and "Schedule" actions on EPIC cards, drag reordering in queue.
- **Automatic transitions**: WebSocket listeners for `epic.status_changed`, `run.started`, `run.completed` → animate card movement between columns.
- **Tests**: Playwright smoke (companion chat opens, sends message, receives response; EPIC column works; queue shows EPICs) + Vitest unit tests (CompanionService adapters, auto-detection, EPIC endpoints, hint command templates).

### Phase 3: Polish (1 EPIC, ~6 steps)

**What:** Improve existing views with richer functionality.

- **Evidence Vault redesign**: Grouped by date (collapsed sections), markdown preview toggle, full file paths displayed, full-text search (backend endpoint + frontend search input).
- **Pipeline Theater replay**: Run picker dropdown, timeline visualization (time × steps axis), color-coded events by role, replay controls (play/pause/speed), detail panel on click, live mode via WebSocket for active runs.
- **Decision Hub notifications**: Web Audio API sound on new pending decision, browser Notification API for background tab alerts, pulse animation on sidebar badge.
- **Tests**: Playwright smoke (Evidence search returns results, Pipeline timeline renders, Decision Hub badge pulses) + Vitest unit tests (Evidence search endpoint, Pipeline timeline data transform, notification service).

## Constraints

- Docker deployment — all changes must work in Docker container (multi-stage build)
- No external services besides Whisper API for dictation (fallback to Web Speech API)
- WebSocket server already exists — extend, don't replace
- ideas.json is source of truth when server running; IDEAS.md for offline
- EPIC generation via `/aid-plan-epic` takes 15-30s — UI must handle async gracefully
- ai-sdk-provider v1 uses subscription auth — no API key required
- CompanionService interface must be adapter-agnostic
- New npm dependencies allowed: `ai`, `ai-sdk-provider-claude-code` (verified working)
- Existing ideas CRUD must keep working — additive changes only

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ai-sdk-provider breaking changes | medium | high | CLI proxy fallback; pin version; monitor npm package |
| CLI proxy unavailable in Docker | medium | medium | ai-sdk-provider as primary doesn't need CLI in PATH; document setup |
| Whisper API latency | low | medium | Web Speech API fallback; async transcription with buffering |
| IDEAS.md parser data loss | medium | medium | Backup original; validate round-trip; PM review |
| EPIC generation timeout in kanban | low | medium | 60s timeout with retry; progress animation |
| WebSocket reconnection storms | low | high | Exponential backoff already implemented |
| Full-text search performance | low | medium | Limit to recent evidence; pagination; debounce input |

## Success Criteria

- Ideas kanban: create idea → link to plan → generate EPIC → run → done — full flow works
- AI Companion: open chat, brainstorm a topic, receive streaming response, dictate in Czech
- EPIC cards: drag plan → EPIC column → building animation → EPIC card appears
- Queue Scheduler: view all EPICs, schedule order, launch run
- Evidence Vault: search past runs, view markdown-rendered reports, grouped by date
- Pipeline Theater: select past run, replay timeline with color-coded events
- Decision Hub: receive audio + browser notification when pending decision arrives
- All Playwright + Vitest tests pass after each phase

## Estimated Size

- **Total steps:** ~24 across 3 EPICs
- **Complexity:** High (AI Companion is uncharted territory, significant UI work)
- **Dependencies:** P009 Phase 1 complete (confirmed), Docker running

---

**Created:** 2026-02-27
