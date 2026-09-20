# AID Cockpit GUI

The `aid-gui` package is the web-based read-only monitoring PWA for the AID Cockpit — the managerial dashboard for the AID orchestrator. It provides a visual interface for monitoring project pipelines, plan execution, audit trends, compliance status, and backlog changes.

## What This Is

- **Pipeline Overview (Screen G)** — Infra-level view of all projects with active run status, health metrics, and high-level risk signals
- **Project Dashboard (Screen B)** — Project-scoped Brief, compliance matrix, activity timeline, and plan hierarchy
- **Plan Details (Screen C)** — Plan-scoped outcome, phase timeline, lessons learned, and audit trends
- **Managerial Brief** — Seven-block decision-focused summary: decisions needed, blockers, risk, watch-outs, what changed, what's next, and project overview (infra scope)

## Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- **aid-server running on port 3911** — the GUI is a front-end only; all data and AI features come from the server

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

The GUI connects to `http://localhost:3911` by default. If aid-server is on a different host or port, set the environment variable:

```bash
VITE_SERVER_URL=http://localhost:3911 npm run dev
```

## Build for Production

```bash
npm run build      # outputs to dist/
npm run preview    # preview the production build locally
```

## Package Location

This package lives at `packages/aid-gui/` in the monorepo. It is bundled separately from the plugin — the plugin (`plugins/aid-orchestrator/`) is a Claude Code extension and does not depend on this GUI.
