---
id: P005
type: plan
status: done
created: 2026-02-23
author: PM + AI
---

# Plan: AID GUI Dashboard

## Context

AID Orchestrator is a multi-agent orchestration system for Claude Code, currently operating entirely through CLI and Slack for PM communication. As the system matures (v0.8.0, 18 agents, 11 commands, 12-state FSM), there is growing need for a visual interface to monitor pipeline execution, interact with PM checkpoints, manage EPICs/queue, browse evidence, and capture ideas — all without leaving the browser.

The `.aid-o/` directory structure provides a stable, file-based contract (YAML, JSON, Markdown, JSONL) that a GUI can consume directly. Qdrant memory adds cross-project analytics and knowledge search. The architecture is ready for a visual layer.

## Goal

Build a web-based GUI dashboard (`aid-gui`) that provides real-time visualization of AID pipeline execution, replaces Slack for PM interactions, enables EPIC/queue management, offers ideation and plan generation, and displays project health, audit results, configuration, and help — all as a standalone npm package in the existing monorepo.

## Scope

**In scope:**
- Real-time EPIC pipeline DAG visualization with step states
- PM interaction system (plan review, escalation, merge approval, curator proposals) replacing Slack
- EPIC editor with drag & drop steps, role picker, dependency/parallel group builder
- EPIC queue management with drag & drop reorder, pause/resume
- Ideas/brainstorming: capture ideas on web, generate plans, browse backlog, link to EPICs
- Plans browser with rendered Markdown
- Evidence explorer: file tree, content viewer, diff patches, stage log timeline, gates report
- Audit & health dashboard: scores, categories, findings, trend graphs, curator proposals
- Configuration viewer/editor: form-based editing of all .aid-o/ YAML configs
- Help page: rendered AID documentation, topics, playbook viewer
- Global project switcher for multi-project support
- CLI entry point: `npx aid-gui` with --port, --global, --project flags

**Out of scope:**
- Multi-user authentication / role-based access
- Cloud deployment / remote access (localhost only)
- Mobile responsive design (desktop-first)
- Replacing Claude Code CLI (GUI is supplementary, not replacement)
- Direct EPIC execution from GUI (AID plugin in Claude Code handles execution)

## Approach

### Option A: Monolithic SPA (Recommended)

Single Node.js process: Express/Fastify backend + React SPA (Vite) + WebSocket server. Backend watches `.aid-o/` directories via chokidar, parses YAML/JSON/MD, exposes REST API + WebSocket events. React SPA consumes both. Qdrant queried directly via its REST API (localhost:6333).

**Pros:**
- Single command: `npx aid-gui` opens browser
- Simplest deployment and distribution (npm publish)
- WebSocket provides real-time updates without polling
- Shared TypeScript types between server and client
- Hot reload in dev mode (Vite)

**Cons:**
- Backend and frontend are coupled (single process)
- Server crash takes down UI

### Option B: Separate Backend + Frontend

Two processes: standalone API server (Express) + React SPA (Vite dev server or static files). API server watches `.aid-o/`, SPA communicates via REST + WebSocket.

**Pros:**
- Clean separation: API usable without GUI (CLI clients, scripts)
- Frontend and backend can have independent dev cycles
- API testable in isolation

**Cons:**
- Two processes to manage (or wrapper script)
- More complex setup for users
- CORS configuration between ports

### Option C: Next.js Fullstack

Next.js app with API routes (server-side) + React pages (client-side). Single framework covers both.

**Pros:**
- One framework, one build pipeline
- SSR for fast initial load
- API routes co-located with pages

**Cons:**
- Heavier framework than needed (SSR unnecessary for localhost)
- Larger bundle size, slower start
- Non-standard WebSocket support in Next.js (custom server)
- npm publish as CLI tool less straightforward than plain Express

### Decision

**Chosen:** Option A — Monolithic SPA
**Rationale:** Solo developer tool on localhost — single process is ideal UX. `npx aid-gui` and done. React + Express + WebSocket + chokidar is a proven combination for file-watching dashboards. Shared TypeScript types eliminate server/client drift. If separation is needed later, refactor from A to B is straightforward.

## High-Level Steps

| # | Task | Description | Effort |
|---|------|-------------|--------|
| A | Scaffold project | packages/aid-gui/ with package.json, tsconfig, Vite config, bin/aid-gui CLI entry point (commander.js), Express server skeleton, npm workspaces in root | S |
| B | Shared parsers | .aid-o/ format parsers (YAML→JSON, MD frontmatter, JSONL), TypeScript types for all entities, unit tests | M |
| C | File watcher + WebSocket | Chokidar watcher on .aid-o/ dirs, WebSocket server (ws library), event pipeline: file change → parse → broadcast, multi-project registry (~/.aid-gui/projects.json) | M |
| D | React shell | Layout (topbar + sidebar + main), React Router (9 routes), project switcher, WebSocket hook, shadcn/ui components | M |
| E | Dashboard page | Health card (audit report), active EPIC mini-view (plan_progress.json), queue summary, recent sessions list | S |
| F | Pipeline visualization | DAG renderer (React Flow or dagre + custom SVG), colored step nodes, parallel group swim lanes, step detail panel, controller state indicator, real-time WebSocket updates | L |
| G | Evidence browser | File tree navigation, content renderers (MD→HTML, YAML/JSON syntax highlight, diff patch viewer), stage log timeline, gates report visualization | M |
| H | Audit & Health page | Audit report renderer (score per category), findings table, health trend chart (recharts), curator proposals view | M |
| I | Help page | AID help content renderer (MD→HTML), topic navigation, playbook viewer | S |
| J | PM Decision system | Polling/WebSocket for pending decisions, decision modal (context + action buttons), notification badge, POST → pm_decision.json write, decision history | M |
| K | Config editor | YAML→form renderer for each config file, form elements (toggle, slider, text, select), diff view (current vs default), save → YAML write, reset to default | M |
| L | Queue management | Sortable list (dnd-kit), priority badges, drag & drop reorder, add/remove EPICs, pause/resume buttons | S |
| M | EPIC editor | Form mapping EPIC template, steps table with drag & drop, role picker, dependency editor, parallel group visual builder, preview (form→rendered MD), save → .md file | L |
| N | Ideas & Plans page | Ideas backlog CRUD with tags/priority, "Generate Plan" action, plans browser with rendered MD, linking: idea → plan → EPIC | M |
| O | Memory search | Search bar with Qdrant proxy, results with score/text/metadata, type filters (decision, lesson, pattern, command) | S |
| P | UX polish | Loading states, error boundaries, responsive layout (collapsible sidebar), dark/light theme, keyboard shortcuts | M |
| Q | CLI polish | npx aid-gui: auto-open browser, --port/--global/--project/--no-open flags | S |
| R | Documentation | README.md with quickstart, /help page with GUI-specific docs | S |

## Constraints

- Tech stack: React (Vite) + Express + WebSocket + chokidar + TypeScript
- UI library: shadcn/ui (copy components, no heavy dependency)
- Location: packages/aid-gui/ in ai-orchestrator monorepo
- Distribution: npm package, CLI entry point `npx aid-gui`
- No own database: all data from .aid-o/ files + Qdrant (existing)
- GUI-specific storage: ~/.aid-gui/ (projects.json, preferences.json, ideas.json)
- Single user, no authentication
- Localhost only, default port 4200
- Plugin integration: standalone package, AID plugin detects and recommends in /aid-setup
- Global mode: project switcher, multi-project watcher via ~/.aid-gui/projects.json

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Fragile .aid-o/ parsers | High | Medium | Defensive parsing with partial results + warnings, fallback to raw content, test fixtures from real files, version-aware parsers |
| Race condition: GUI vs Claude Code writes | Medium | High | Atomic writes (temp→rename), clear file ownership (GUI owns decisions+config, AID owns evidence+logs) |
| Chokidar performance with large evidence | Low | Medium | Watch only active evidence (current run), lazy load archives, ignored patterns for large files |
| Plugin version drift | Medium | Medium | Read .aid-manifest.yaml for version, graceful degradation for unknown fields, monorepo enables coordinated updates |
| PM decision timing (GUI not open) | Medium | Low | Slack fallback remains functional, GUI is additional channel not replacement in MVP |
| Qdrant unavailable | Low | Low | Empty results instead of errors, "Memory unavailable" badge, rest of GUI fully functional |

## Success Criteria

- Real-time pipeline visualization: DAG shows step states, updates live during EPIC execution
- PM interactions work end-to-end: pending decision appears → PM clicks action → AID plugin picks up response and continues
- EPIC editor produces valid .md files that /aid-plan-epic can process
- Queue management: reorder, add, remove, pause/resume reflected in epic-queue.yaml
- Ideas captured on web, linked to generated plans and EPICs
- Audit health score and findings visible with trend over time
- Config changes via form editor correctly written back as YAML
- Help documentation browsable and searchable
- Multi-project switcher works: register projects, switch between them, isolated data
- Single command startup: `npx aid-gui` opens working dashboard

## Next Steps

- [ ] Create EPIC from this plan
- [ ] Generate Plan JSON via /aid-plan-epic
- [ ] Execute via /aid-run-epic

---

**Last Updated:** 2026-02-23
