---
id: P005-D
type: plan
status: done
created: 2026-02-25
author: PM + AI
parent: P005
depends_on: P005-C
supersedes_scope: P005-B
---

# Plan: AID GUI Dashboard — Frontend Integration & Interactivity (Post-Prototype)

## Context

This plan replaces the scope of P005-B for the post-prototype reality. The AI Studio prototype provides a complete visual frontend — all 9 screens are built with proper design system, animations, and layout. P005-B's visual design specs are already implemented in code.

**What P005-B defined (and AI Studio delivered):**
- Orchestration Cinema design language (dark canvas, glass morphism, grain texture, depth)
- FSM state-driven color system (12 colors as CSS custom properties)
- 9 core screens with correct layouts and visual hierarchy
- Sidebar navigation with collapse, Topbar with CC Usage gauge
- AI Companion with voice input and presets
- Sound system (Web Audio API synthesizer)
- Framer Motion animations (page transitions, hover effects, pulse)
- Recharts integration (Health Observatory, Queue Scheduler)

**What this plan adds:**
- Connect all screens to real backend API (P005-C)
- WebSocket integration for real-time updates
- Interactive features (drag-and-drop, EPIC launching, decision actions)
- Missing functionality (run replay, brainstorm canvas, knowledge graph)
- Polish and production readiness

## Goal

Transform the AI Studio prototype from a static visual demo into a fully functional, real-time dashboard connected to the AID orchestrator backend.

## Scope

**In scope:**
- Custom `useWebSocket` hook with auto-reconnect and topic subscriptions
- Expanded Zustand store for all real-time data
- API integration for all 9 screens (replace hardcoded mock data)
- EPIC launch functionality (trigger backend to spawn `claude` process)
- Decision approve/reject UI → POST to backend
- Queue management UI (reorder, add, remove, cooldown settings)
- Ideas CRUD in Kanban board
- Knowledge Base with real agent/skill/command data
- Run replay (play/pause/scrub from stage_log timestamps)
- Drag-and-drop in Ideas to Execution kanban (dnd-kit)
- Connection status indicator
- Error boundaries and loading states
- CC usage real-time updates

**Out of scope:**
- Visual design changes (AI Studio prototype is the approved design)
- Brainstorm Canvas interactive editor (deferred — placeholder is sufficient for MVP)
- AI Companion search results (deferred — requires Qdrant integration from P005-C future)
- Mobile responsive design
- Light theme

## Approach

### Screen-by-Screen Integration

Each screen gets connected to the real API in order of dependency and user value. The pattern for each screen is:
1. Create/update API hook (React Query or simple fetch + useEffect)
2. Replace hardcoded data with API response
3. Add WebSocket subscription for real-time updates
4. Add error/loading/empty states
5. Add interactive write operations where applicable

### State Management Strategy

Current `store.ts` has minimal state (project, fsmState, progress). Expand to:

```typescript
// Expanded store slices (Zustand)
interface DashboardStore {
  // Connection
  wsStatus: 'connecting' | 'connected' | 'disconnected';

  // Pipeline (real-time via WebSocket)
  pipeline: PipelineState | null;
  stageLog: StageLogEntry[];

  // Decisions (real-time via WebSocket)
  pendingDecisions: Decision[];
  decisionHistory: Decision[];

  // Evidence (loaded on demand)
  evidenceTree: EvidenceNode[] | null;

  // Queue (real-time via WebSocket)
  queue: QueueSchedule | null;

  // Usage (real-time via WebSocket)
  ccUsage: CCUsage | null;

  // Health (loaded on demand)
  auditReport: AuditReport | null;

  // Ideas (loaded on demand, CRUD)
  ideas: Idea[];

  // Knowledge (loaded once at startup)
  knowledge: { agents: Agent[]; skills: Skill[]; commands: Command[] } | null;

  // Projects
  projects: Project[];
  activeProject: Project | null;
}
```

## High-Level Steps

| # | Task | Description | Effort |
|---|------|-------------|--------|
| 1 | WebSocket hook | `src/hooks/useWebSocket.ts` — custom hook with auto-reconnect (exponential backoff), topic subscription/unsubscription, connection status tracking, message parsing. Integrates with Zustand store. | M |
| 2 | Expand Zustand store | Restructure `src/store.ts` into slices: connection, pipeline, decisions, evidence, queue, usage, ideas, knowledge, projects. Add actions for API responses and WebSocket events. Keep existing FSMState types and stateColors. | M |
| 3 | API client layer | `src/api/client.ts` — typed fetch wrappers for all REST endpoints from P005-C. Error handling (network errors, 404, 500). Base URL from environment or relative. Types imported from shared types (or duplicated if server/client can't share). | S |
| 4 | Connection status indicator | Topbar component update — show WebSocket connection status (green dot = connected, yellow = reconnecting, red = disconnected). Subtle, non-intrusive. | S |
| 5 | Command Center — real data | Replace hardcoded stats with API data. FSM state from pipeline WebSocket. Progress from plan_progress. Satellite metrics from real queue count, audit health score, pending decisions count. Active EPIC name + duration from pipeline state. | M |
| 6 | Pipeline Theater — real data | Fetch steps from `/api/p/:id/pipeline/steps`. Real-time step status updates via WebSocket `pipeline` topic. Step detail panel shows real agent output (from evidence). Step completion animations triggered by WebSocket events. Sound effects on real events. | M |
| 7 | Pipeline Theater — replay | Play/pause/scrub controls connected to stage_log data. Fetch full stage_log via REST. Reconstruct pipeline state at any point in time by replaying events. Playback speed (1x/2x/4x). Scrub bar mapped to timestamps. | L |
| 8 | Activity Stream — real data | Replace mock events with stage_log entries via WebSocket `pipeline.stage_log` topic. New events animate in (existing animation works). Filter toggles filter by stage_log action/state fields. Live indicator reflects WebSocket connection. Auto-scroll with manual override (scroll position tracking). | M |
| 9 | Decision Hub — real data | Fetch pending decisions from REST API. Display real context (steps completed, gates status, changes summary). APPROVE button → POST to `/api/p/:id/decisions` with `{decision: "approved"}`. REJECT button → POST with `{decision: "rejected", feedback: "..."}`. Past decisions from `/api/p/:id/decisions/history`. Real-time notification via WebSocket `decisions` topic when new decision arrives. | M |
| 10 | Evidence Vault — real data | Fetch EPIC list and run list from REST API. File tree from `/api/p/:id/evidence/:epic/:run`. File content viewer: fetch raw content, render based on type (MD → rendered HTML, YAML → syntax highlighted, JSONL → timeline view, JSON → formatted, diff → diff view). | M |
| 11 | Health Observatory — real data | Fetch audit report from `/api/p/:id/audit`. Parse scores (overall, code_quality, security, documentation, testing). Display real findings with severity. Trend data from historical audit reports. | M |
| 12 | Ideas to Execution — CRUD + DnD | Fetch ideas from `/api/p/:id/ideas`. Quick Capture → POST new idea. Drag-and-drop between columns using dnd-kit. Status change on drop → PUT idea. Delete idea. Link idea to EPIC/plan. Progress bar for running ideas reflects real pipeline progress. | L |
| 13 | Queue Scheduler — real data + controls | Fetch queue from `/api/p/:id/queue`. Timeline shows real EPICs with estimated durations. Drag-to-reorder → PUT queue. Queue Settings panel writes to real settings. LAUNCH QUEUE button → POST to start queue execution. CC Usage detail shows real token data from `/api/p/:id/usage`. Real-time countdown via WebSocket `queue` topic. | L |
| 14 | Knowledge Base — real data | Fetch agents, skills, commands from `/api/p/:id/knowledge`. Render as draggable nodes with proper types and colors. Detail panel shows real descriptions and relationships. Filter by type (agent/skill/command). Search across names and descriptions. | M |
| 15 | AI Companion — partial integration | Connect presets to real project context. Search sends query to REST endpoint (if AI companion backend exists in P005-C, otherwise show "coming soon"). Recent queries persisted in localStorage. Voice input already works (Web Speech API). | S |
| 16 | Project switcher | Topbar project selector fetches from `/api/projects`. Switch project → re-fetch all data, switch WebSocket subscriptions. Show project health indicator next to name. | S |
| 17 | EPIC launch | Button in Queue Scheduler or Ideas to Execution → POST to backend to spawn `claude -p "invoke skill aid-run-epic..."`. Backend starts process, GUI monitors via stage_log WebSocket. Launch confirmation dialog (are you sure?). | M |
| 18 | Error boundaries & loading states | Wrap each screen in error boundary with recovery action. Loading states use shimmer/skeleton (not spinner). Empty states for each screen (no EPICs, no decisions, no ideas, etc.) with helpful messages. Network error toast notifications. | M |
| 19 | Production build & polish | Verify `npm run build` produces correct production bundle. Font bundling (Inter + JetBrains Mono as woff2). Favicon and meta tags. Remove unused dependencies. Performance audit (bundle size < 500KB gzipped). | S |

## New Dependencies (to add to package.json)

```
# Frontend additions
@dnd-kit/core         # Drag and drop for Kanban
@dnd-kit/sortable     # Sortable lists for Queue
@dnd-kit/utilities    # DnD utilities
highlight.js          # Already present — syntax highlighting for Evidence Vault
```

## GUI Capabilities & Limitations

(Preserved from P005-B — these remain the ground truth)

### What GUI CAN do:
| Capability | Mechanism |
|------------|-----------|
| Display pipeline state in real-time | Read + watch stage_log.jsonl via backend WebSocket |
| Read all .aid-o/ files | Backend REST API |
| Display health score | Parse audit_report.yaml via backend |
| Manage Ideas (CRUD) | Read/write ideas.json via backend |
| Approve/Reject decisions | POST decision → backend writes pm_decision.json |
| Launch EPIC execution | Backend spawns `claude` process |
| Queue sequential EPICs | Backend orchestrates: start → wait → cooldown → next |
| Track token usage (estimated) | Backend parses stage_log.jsonl token counts |
| Voice input | Web Speech API (browser-native) |
| Browse Knowledge Base | Backend parses plugin markdown files |

### What GUI CANNOT do:
| Limitation | Reason |
|------------|--------|
| Stop a running EPIC gracefully | Claude Code has no graceful stop API |
| Send messages to a running agent | Agents are autonomous sessions |
| Get exact CC billing in dollars | No Anthropic billing API |
| Modify running pipeline config | plan.json locked during execution |

### CC Usage Tracking:
- Source: Sum token counts from stage_log.jsonl entries
- Limit: User-configured token budget (not from Anthropic)
- Display: Token-based (`42k / 100k`) not dollar-based
- Auto-pause: When estimated usage approaches limit → pause queue

## Constraints

- Depends on P005-C backend API being available
- Dark theme only in MVP
- Desktop-first, minimum 1280px viewport
- No external font CDN — bundle woff2
- No external API calls from frontend (all via backend proxy)
- Animations: 60fps, GPU-accelerated, reduced-motion support
- Accessibility: Radix primitives provide ARIA, keyboard navigation
- Bundle size target: < 500KB gzipped (excluding fonts)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Mock-to-real data shape mismatch | High | Medium | Define shared types early (P005-C Step 3), adapt frontend to match |
| Drag-and-drop complexity in Kanban | Medium | Medium | Use dnd-kit (battle-tested), start with simple column-to-column, add sorting later |
| Run replay timing accuracy | Low | Low | Use stage_log timestamps, accept approximate timing |
| WebSocket reconnect edge cases | Medium | Medium | Exponential backoff, state resync on reconnect (refetch all via REST) |
| Large evidence files blocking UI | Medium | Medium | Paginate evidence content, virtual scrolling for long stage_logs |
| AI Studio code quality issues | Medium | Low | Refactor as needed during integration, don't rewrite working code |

## Success Criteria

- All 9 screens display real data from `.aid-o/` files
- Pipeline state changes appear in UI within 1 second of file write
- Decision approve/reject workflow works end-to-end (GUI → file → AID pickup)
- EPIC launch from GUI starts real Claude Code execution
- Queue scheduler manages sequential EPIC execution with configurable cooldowns
- Kanban board supports drag-and-drop idea management
- Evidence Vault renders all file types correctly (MD, YAML, JSON, JSONL, diff)
- Knowledge Base displays all 18 agents, 20 skills, 13 commands with relationships
- Run replay plays back completed pipeline run with correct timing
- CC usage gauge shows estimated token consumption and warns at limit
- No hardcoded mock data remains in any screen

## Dependency Chain

```
P005-C (backend complete)
  → P005-D Steps 1-4 (WebSocket hook, store, API client, connection indicator)
    → P005-D Steps 5-6 (Command Center, Pipeline Theater) — highest user value
    → P005-D Steps 8-9 (Activity Stream, Decision Hub) — core functionality
      → P005-D Steps 10-14 (Evidence, Health, Ideas, Queue, Knowledge) — can parallel
        → P005-D Steps 15-17 (AI Companion, Project switcher, EPIC launch)
          → P005-D Steps 18-19 (Error handling, production build)
            → P005-D Step 7 (Replay — lowest priority, most complex)
```

---

**Last Updated:** 2026-02-25
