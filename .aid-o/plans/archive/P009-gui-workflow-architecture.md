---
id: P009
type: plan
status: done
created: 2026-02-26
author: PM + AI
---

# Plan: GUI Workflow Architecture — Ideas to Execution Pipeline

## Context

AID GUI dashboard (9 screens) was built in EPICs E-005D-1..3 but has critical issues: 3 pages crash (QueueScheduler, KnowledgeBase, HealthObservatory), WebSocket is implemented but never connected (`useWebSocket()` not called in App.tsx), Ideas to Execution page doesn't load data from IDEAS.md, and there's no connection between the workflow stages (ideas → plans → EPICs → runs). The GUI is a set of isolated screens rather than an integrated workflow tool.

Playwright audit (2026-02-26) identified 11 bugs, and brainstorming with PM defined the vision: a kanban-based workflow where ideas flow through stages automatically, with an AI Companion chat (Claude Code proxy) enabling brainstorming directly in the GUI.

## Goal

Transform AID GUI from a broken monitoring dashboard into a functional workflow management tool where ideas flow through Ideas → Plan → EPIC → Running → Done with automatic status transitions, integrated Queue Scheduler, and AI Companion chat for brainstorming and command execution.

## Scope

**In scope:**
- Fix all 11 crash/display bugs from Playwright audit
- Connect WebSocket for real-time updates
- Rebuild Ideas to Execution as 5-column kanban (Ideas → Plan → EPIC → Running → Done)
- ideas.json as source of truth when web is running, IDEAS.md when not
- Multi-select ideas → "Create Plan" flow via AI Companion
- Drag plan → EPIC column triggers `/aid-plan-epic` with building animation
- EPIC actions: "Run Now" (immediate) and "Schedule" (Queue Scheduler)
- Queue Scheduler shows all EPICs, manages ordering/timing
- Automatic status transitions via WebSocket events
- AI Companion: dual-mode (CLI proxy default, Agent SDK opt-in) with CompanionService adapter pattern and session persistence
- Voice dictation (Czech) via Whisper API
- Hint commands (Brainstorm, Plan EPIC, Run, Audit, Explain, Fix, Free chat)
- Evidence Vault: grouped by date, collapsed, markdown preview, search
- Pipeline Theater: evidence-driven replay with run picker and timeline
- Decision Hub: audio + browser notifications
- Backlog & Lessons Learned panel in Ideas page
- Responsive sidebar (auto-collapse on mobile)

**Out of scope:**
- Agent SDK adapter implementation (v2 — interface prepared, adapter stub only)
- Brainstorm Canvas / mind map visualization (future)
- Multi-user / authentication
- EPIC editor in GUI (EPICs are created via AI, edited in CLI/IDE)
- Mobile-native app
- CI/CD integration

## Approach

### Option A: Bottom-Up — fixes → data flow → AI Companion (Chosen)

Fix crashes and WebSocket first (1 EPIC), then kanban + data flow (2 EPICs), then AI Companion + polish (2 EPICs). Each phase builds on the previous and is testable independently.

**Pros:**
- Each EPIC produces a functional, testable state
- WebSocket fix immediately unlocks real-time for all subsequent phases
- Kanban with automatic transitions works even without AI Companion
- Lowest risk — if you stop after phase 2, you have a usable product

**Cons:**
- AI Companion (the "wow" feature) comes last
- 5 EPICs total, longer overall timeline

### Option B: Feature-First — AI Companion first

Start with AI Companion chat, then wire kanban and data flow around it.

**Pros:**
- Most valuable feature first
- Motivating — see the "wow" feature quickly

**Cons:**
- Builds on broken foundation (WebSocket, crashes)
- High risk — Claude CLI proxy is uncharted territory

### Option C: Big Bang — everything in one mega-EPIC

One EPIC with 15+ steps covering everything at once.

**Pros:**
- Done at once, no intermediate states

**Cons:**
- Enormous scope, high failure risk
- Impossible to test incrementally

### Decision

**Chosen:** Option A — Bottom-Up
**Rationale:** The foundation is broken (3 crashing pages, dead WebSocket, hidden CC Usage). Until these work, anything built on top is unstable. Phase 1 takes 1 EPIC and immediately gives a functional dashboard. Phase 2 gives Ideas real value. Phase 3 adds the AI Companion on top of a working system. Each phase is testable — after phase 1, run 2 test EPICs and verify in UI with Playwright.

## High-Level Steps

### Phase 1: Stabilization

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | API fallback fix | `app.all('/api/*')` returns 404 JSON before static fallback — no more HTML responses for API routes | S |
| 2 | Null guard crash fixes | QueueScheduler.tsx (lines 330,384,433), KnowledgeBase.tsx (line 53), HealthObservatory.tsx (line 58) — add `?? []` and null checks | S |
| 3 | WebSocket connection | Add `useWebSocket(activeProject?.id)` to App.tsx, verify connection established | S |
| 4 | CC Usage always visible | Topbar.tsx — show gauge regardless of wsStatus, remove `hidden md:flex` from connection banner | S |
| 5 | UI polish fixes | Project selector z-index, Pipeline Theater empty state, notifications/settings buttons (hide or "coming soon"), sidebar responsive auto-collapse < 768px | M |
| 6 | Playwright verification | Automated Playwright test visiting all 9 pages, verifying no crashes, WebSocket connected, data displayed | M |

### Phase 2a: Ideas + Plans Data Layer

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 7 | ideas.json source of truth | Backend: startup migration (IDEAS.md → ideas.json), shutdown export (ideas.json → IDEAS.md), file watcher for sync | M |
| 8 | StoredIdea type extension | Add `linkedPlanId`, `linkedEpicId`, `autoStatus` fields, new link endpoint, WebSocket events | S |
| 9 | Backlog & lessons endpoints | `GET /api/p/:id/backlog` (parse .aid-o/04-engine/backlog/*.md), `GET /api/p/:id/lessons` (parse lessons-learned.md) | M |
| 10 | Kanban rebuild | 5 columns (Ideas/Plan/EPIC/Running/Done), multi-select with "Create Plan" button, Insights panel (backlog + lessons tabs with drag-to-kanban) | L |

### Phase 2b: EPIC Column + Queue + Auto Transitions

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 11 | EPIC lifecycle endpoints | `GET /api/p/:id/epics` (metadata from .aid-o/02-epics/), `POST /api/p/:id/epics/:epicId/run`, `POST /api/p/:id/commands/plan-epic` | M |
| 12 | EPIC column UI | Drag plan → EPIC triggers plan-epic, "Building" animation (progress texts, pulsing border, settle animation), EPIC cards with step count and role badges | L |
| 13 | Queue Scheduler integration | All EPICs visible in Queue Scheduler, "Run Now" and "Schedule" actions on EPIC cards, drag reordering in queue | M |
| 14 | Automatic transitions | WebSocket listeners for epic.status_changed, run.started, run.completed → animate card movement between columns | M |

### Phase 3a: AI Companion

**Architecture decision:** Dual-mode CompanionService with adapter pattern.
- **Primary (v1):** CLI Proxy — `claude -p "..." --output-format stream-json` via child process. Works with Claude Code subscription (Max/Pro), no API key needed. This is the default.
- **Future (v2):** Agent SDK adapter — `@anthropic-ai/claude-agent-sdk` `query()` with native streaming, sessions, subagents, hooks. Requires `ANTHROPIC_API_KEY` (API billing). Optional upgrade for power users/teams.
- **Auto-detection:** If `ANTHROPIC_API_KEY` set → SDK mode; else if `claude` CLI in PATH → CLI mode; else → setup instructions in GUI.

Both adapters implement `CompanionService` interface (send, stream, resume, listSessions). Frontend doesn't know which adapter is active.

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 15 | CompanionService + CLI proxy | `packages/aid-server/src/companion/` — CompanionService interface, CLIProxyAdapter (spawn `claude -p --output-format stream-json`, stdout JSON stream parsing, session persistence to .jsonl), WebSocket bridge for streaming to frontend. Agent SDK adapter left as stub for v2. | L |
| 16 | Chat UI | Cmd+K slide-down panel, docked right-third, message bubbles with markdown, streaming typewriter, session list sidebar | L |
| 17 | Hint commands | Pill buttons above input (Brainstorm, Plan EPIC, Run, Audit, Explain, Fix, Free chat), context-aware (selected card data pre-filled). Each hint = prompt template sent via CompanionService. | M |
| 18 | Voice dictation | Whisper API proxy in backend, microphone button in chat input, push-to-talk, Czech language default, settings page for language/provider | M |

### Phase 3b: Evidence + Pipeline + Decision Polish

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 19 | Evidence Vault redesign | Grouped by date (collapsed), markdown preview toggle, full file paths, working search (full-text backend endpoint) | M |
| 20 | Pipeline Theater replay | Run picker dropdown, timeline visualization (time × steps), color-coded events, replay controls functional, detail panel on click, live mode via WebSocket | L |
| 21 | Decision Hub notifications | Web Audio API sound on new pending decision, browser Notification API for background tab, pulse animation on sidebar badge | S |

## Constraints

- Docker deployment — all changes must work in Docker container (Dockerfile multi-stage build)
- No external services besides Whisper API for dictation (fallback to Web Speech API)
- WebSocket server already exists in backend — extend, don't replace
- ideas.json and IDEAS.md must never coexist — one or the other
- EPIC generation via `/aid-plan-epic` takes 15-30 seconds — UI must handle async gracefully
- AI Companion v1 uses CLI proxy (`claude` CLI in PATH) — no API key required, works with CC subscription
- Agent SDK (`@anthropic-ai/claude-agent-sdk`) is optional v2 upgrade — requires `ANTHROPIC_API_KEY` (API billing per token)
- CompanionService interface must be adapter-agnostic — frontend never knows which backend is active
- No new npm dependency for v1 (CLI proxy uses child_process); `claude-agent-sdk` added only when v2 is implemented

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Claude CLI proxy instability | medium | high | `--output-format stream-json` provides structured output; graceful error handling; session recovery; v2 Agent SDK adapter as alternative |
| CLI proxy not available in Docker | medium | medium | `claude` CLI must be in PATH inside container or accessible via volume mount; document setup in README |
| Agent SDK API costs for v2 users | low | medium | v2 is opt-in; clear cost warning in settings; CLI proxy (free with CC subscription) is default |
| Whisper API latency for dictation | low | medium | Fallback to Web Speech API; async transcription with buffering |
| IDEAS.md parser loses data during migration | medium | medium | Backup original file; validate round-trip (parse → export → diff); PM review |
| EPIC generation timeout in kanban | low | medium | 60s timeout with retry; progress animation manages user expectation |
| WebSocket reconnection storms | low | high | Exponential backoff already implemented in useWebSocket hook |

## Success Criteria

- All 9 dashboard pages load without crashes or console errors
- WebSocket connects on page load, real-time events flow to all screens
- Ideas kanban: create idea → create plan → generate EPIC → run → done — full flow works
- AI Companion: open chat, brainstorm a topic, receive streaming response, dictate in Czech
- Evidence Vault: find a past run by search, view markdown-rendered report
- Pipeline Theater: select a past run, replay timeline with events
- Decision Hub: receive audio notification when pending decision arrives
- Queue Scheduler: view all EPICs, schedule order, launch run

## Next Steps

- [x] Create EPIC for Phase 1 (Stabilization) → E-009-1_5
- [x] Generate execution plan for E-009-1_5 → plan.json + run.md ready
- [ ] Run Phase 1 EPIC via `/aid-run-epic`
- [ ] After Phase 1: run 2 test EPICs, verify in UI with Playwright (PM watching live)
- [ ] Create EPICs for Phase 2a and 2b
- [ ] Create EPICs for Phase 3a (CLI proxy + CompanionService interface) and 3b
- [ ] Phase 3a v2: Agent SDK adapter (when demand exists)
- [ ] Update project-profile.yaml with TypeScript/React in tech stack

---

**Last Updated:** 2026-02-26
