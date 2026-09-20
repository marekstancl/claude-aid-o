# AID Cockpit

A web UI over `.aid-o/` workspaces: projects, plans, EPIC runs and their evidence, read from a discovery root (`AID_PROJECTS_ROOT`). Three npm workspace packages:

- `packages/aid-contract` — the shapes the server and GUI agree on (built first)
- `packages/aid-server` — Express + WebSocket API on port 3911
- `packages/aid-gui` — the React frontend

It is not part of the plugin and has its own version (`package.json`, checked by `.github/workflows/version-sync.yml`) and its own [CHANGELOG](CHANGELOG.md).

```bash
cd cockpit
npm ci
npm run build -w @aid/contract
npm test                      # vitest across the workspaces
node check-path-validation.js # CWE-22 guard over server routes (CI: security-regression)
docker compose up -d --build  # container `aid-orchestrator`, GUI on http://localhost:3911
```

Moved here from the repository root on 2026-09-20 so the root carries only the plugin; the compose project name is pinned to `aid-orchestrator` so the container that was started from the old location is still the one this file manages. Compose reads `.env` from this directory: the untracked `.env` that used to sit in the repo root (`OPENAI_API_KEY`, `AID_HOST_ROOT`, …) has to move here on every checkout that runs the container, or the next `up` recreates it with empty keys.
