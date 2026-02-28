# AID Dashboard GUI

The `aid-gui` package is the web-based dashboard for the AID — AI Development Orchestrator. It provides a visual interface for monitoring EPIC pipelines, managing the execution queue, reviewing evidence, and interacting with the AI Companion.

## What This Is

- **Command Center** — Kanban-style view of active EPICs, pipeline states, and step progress
- **AI Companion** — Chat interface backed by the aid-server companion API (multi-session, voice input)
- **Pipeline Theater** — SVG timeline visualization of orchestration state transitions
- **Evidence Vault** — Full-text search over step outputs, gate results, and audit logs
- **Decision Hub** — Notification center for PM approval checkpoints

## Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- **aid-server running on port 9911** — the GUI is a front-end only; all data and AI features come from the server

Start aid-server first:

```bash
# From the repository root
docker compose up aid-server
# or
cd packages/aid-server && npm install && npm run dev
```

## Run Locally

```bash
# Install dependencies
npm install

# Start the development server (Vite, default port 5173)
npm run dev
```

The GUI connects to `http://localhost:9911` by default. If aid-server is on a different host or port, set the environment variable:

```bash
VITE_SERVER_URL=http://localhost:9911 npm run dev
```

## Build for Production

```bash
npm run build      # outputs to dist/
npm run preview    # preview the production build locally
```

## Package Location

This package lives at `packages/aid-gui/` in the monorepo. It is bundled separately from the plugin — the plugin (`plugins/aid-orchestrator/`) is a Claude Code extension and does not depend on this GUI.
