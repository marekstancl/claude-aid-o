# ADR-004: CLI Interface, Storage Schemas & Scheduling Engine

## Status
Accepted

## Context
EPIC E-005-4_4 adds the final layer of features to the AID GUI backend:
- Ideas CRUD with persistent JSON storage
- Queue scheduling engine with cooldowns and auto-pause
- Multi-project support with watcher management
- CLI entry point (`npx aid-gui`)

## CLI Interface Design

### Command
```bash
npx aid-gui [options]
```

### Flags
| Flag | Default | Description |
|------|---------|-------------|
| `--port <number>` | `4200` | HTTP server port |
| `--project <path>` | `.` | Path to project root (resolves `.aid-o/` from it) |
| `--no-open` | `false` | Skip auto-opening browser |
| `--plugin-dir <path>` | `null` | Override knowledge base source directory |

### Resolution Logic
1. `--project /path/to/project` → resolves to `/path/to/project/.aid-o/`
2. If `--project` not given, use `process.cwd()`
3. Validate `.aid-o/` exists at resolved path; warn if missing

### Startup Sequence
1. Parse CLI args with commander.js
2. Resolve project path → `.aid-o/` path
3. Auto-register project in `~/.aid-gui/projects.json`
4. Start Express server on `--port`
5. Start file watcher + stage log stream
6. Auto-open browser (unless `--no-open`)
7. Print banner with URL and project info

## Storage Schemas

### ~/.aid-gui/ideas.json
Per-project keyed ideas storage. Lives in user home dir, not inside `.aid-o/`.

```json
{
  "version": 1,
  "projects": {
    "/abs/path/to/project": {
      "counter": 3,
      "ideas": [
        {
          "id": "idea-1",
          "title": "Add dark mode",
          "description": "Support dark theme in the GUI",
          "tags": ["ui", "feature"],
          "priority": "medium",
          "status": "idea",
          "linkedPlan": null,
          "linkedEpic": null,
          "createdAt": "2026-02-25T15:00:00Z",
          "updatedAt": "2026-02-25T15:00:00Z"
        }
      ]
    }
  }
}
```

**Fields:**
- `id`: Auto-generated `idea-{counter}` (per-project counter)
- `title`: Required string
- `description`: Optional string (default "")
- `tags`: String array (default [])
- `priority`: "low" | "medium" | "high" (default "medium")
- `status`: "idea" | "exploring" | "planned" | "done" (default "idea")
- `linkedPlan`: Optional plan reference string
- `linkedEpic`: Optional EPIC reference string
- `createdAt`: ISO 8601 (set on creation)
- `updatedAt`: ISO 8601 (updated on any mutation)

### ~/.aid-gui/schedules.json
Queue scheduling configuration. Persists across server restarts.

```json
{
  "version": 1,
  "schedules": {
    "/abs/path/to/project": {
      "enabled": true,
      "cooldownSeconds": 30,
      "maxConcurrent": 1,
      "delayedStartAt": null,
      "autoPauseAtCcLimit": true,
      "ccLimitThreshold": 100,
      "lastRunCompletedAt": null
    }
  }
}
```

### ~/.aid-gui/projects.json
Multi-project registry. Auto-created on first startup.

```json
{
  "version": 1,
  "projects": [
    {
      "id": "proj-1",
      "name": "ai-orchestrator",
      "path": "/path/to/project",
      "aidoPath": "/path/to/project/.aid-o",
      "active": true,
      "registeredAt": "2026-02-25T15:00:00Z",
      "lastActivityAt": "2026-02-25T15:30:00Z",
      "accessible": true
    }
  ]
}
```

## Scheduling Engine Algorithm

The scheduler manages automatic execution timing for the EPIC queue.

### Timer Loop (1-second tick)
```
ON_TICK:
  1. Read schedule config for active project
  2. IF not enabled → skip
  3. IF delayedStartAt is set AND now < delayedStartAt → broadcast countdown, skip
  4. IF cooldown active (lastRunCompletedAt + cooldownSeconds > now) → broadcast remaining, skip
  5. IF max concurrent reached → skip
  6. IF autoPauseAtCcLimit AND cc usage > threshold → auto-pause queue, skip
  7. ELSE → signal "ready to start next EPIC"
```

### WebSocket Broadcasting
- Topic: `queue.schedule` (new topic, added to EventTopic union)
- Events: countdown timer updates, schedule state changes
- Broadcast interval: every second during countdown, every 10s when idle

### Persistence
- Schedule config read from `~/.aid-gui/schedules.json` on startup
- Written back atomically on any mutation
- Timer state (countdown remaining) is ephemeral (not persisted)

## Atomic Write Protocol
All three storage files use the same write pattern:
1. Write to `{file}.tmp` (same directory)
2. Validate temp file is valid JSON
3. `fs.rename(tmpPath, targetPath)` (atomic on POSIX)
4. On error: delete temp file, return error

## Decisions
- **User-level storage** (`~/.aid-gui/`): Ideas, schedules, and projects are
  user-level concerns, not per-run evidence. They belong outside `.aid-o/`.
- **Per-project keyed ideas**: One file with project path as key. Simpler than
  per-project directories.
- **1-second tick**: Provides smooth countdown UX without excessive CPU usage.
- **No actual EPIC execution**: The scheduler only signals readiness. Actual
  execution is handled by the orchestrator (`/aid-first-aid`).
