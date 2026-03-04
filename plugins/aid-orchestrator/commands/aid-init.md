---
name: aid-init
description: Initialize or upgrade .aid-o/ workspace (10-file init, idempotent)
user_invocable: true
---

Initialize a new `.aid-o/` workspace or upgrade existing v1.x workspace to v2.0 structure. Merges the old `/aid-setup` interactive onboarding into this command.

## Usage

```
/aid-init                   # auto-detect mode (recommended)
/aid-init --upgrade         # upgrade existing v1 .aid-o/ to v2
```

## Files Created (10 total)

```
.aid-o/
  config/
    project.yaml          # auto-detected: name, type, languages, test_cmd, lint_cmd, build_cmd
    permissions.yaml      # default: autonomous_mode: false
  work/
    active.md             # current focus (empty template)
    backlog.md            # improvement backlog (categorized sections)
    timeline.jsonl        # empty — first event written by /aid-run
  plans/                  # empty directory (for P-NNN plan files)
  tasks/                  # empty directory (for EPIC task files, formerly 02-epics/)
  config/                 # (created above)
  work/quick/             # empty directory (for Q-NNN quick logs from /aid-do)
  work/evidence/          # empty directory (for run evidence)
```

Total: 5 files + 5 empty directories = 10 items.

## Auto-Detection Logic

Read project root to detect stack and populate `config/project.yaml`:

| File Found | Detected Stack | test_cmd | lint_cmd | build_cmd |
|-----------|---------------|----------|----------|-----------|
| `package.json` | TypeScript/JavaScript | `npm test` | `npm run lint` | `npm run build` |
| `pyproject.toml` | Python | `pytest` | `ruff check .` | — |
| `Cargo.toml` | Rust | `cargo test` | `cargo clippy` | `cargo build` |
| `go.mod` | Go | `go test ./...` | `golangci-lint run` | `go build ./...` |
| `pom.xml` | Java/Kotlin | `mvn test` | — | `mvn package` |

If multiple detected, list all. Commands are suggestions — PM can override in `project.yaml`.

### project.yaml template

```yaml
# Auto-detected by /aid-init — edit freely
project_name: "{directory name}"
languages: ["{detected}"]
test_cmd: "{detected or null}"
lint_cmd: "{detected or null}"
build_cmd: "{detected or null}"
initialized_at: "{ISO 8601}"
```

### permissions.yaml template

```yaml
# AID permissions — controls autonomous behavior
autonomous_mode: false    # set true to enable /aid-run --auto
auto_commit: false        # set true to allow auto-commits
auto_push: false          # set true to allow auto-push (requires auto_commit)
```

### active.md template

```markdown
# Active Work

_Initialized by /aid-init_

## Current Focus

_No active work_

## Recent Work

## Next Steps

## Blockers
```

### backlog.md template

```markdown
# AID Backlog

_Source: user | agent | curator | audit_

## Bugs
| ID | Priority | Source | Summary |
|----|----------|--------|---------|

## Features
| ID | Priority | Source | Summary |
|----|----------|--------|---------|

## Tech Debt
| ID | Priority | Source | Summary |
|----|----------|--------|---------|
```

## Lazy-Created (NOT at init time)

These files/dirs are created on first use of the feature that needs them:

| File | Created by | Trigger |
|------|-----------|---------|
| `config/execution.yaml` | `/aid-run` | First EPIC run |
| `config/queue.yaml` | `/aid-status queue add` | First queue entry |
| `config/orchestration.yaml` | `/aid-run` | First EPIC run with custom config |

## Idempotency

Safe to run multiple times:

- **Existing config files** → NOT overwritten (show diff proposal if defaults changed)
- **Existing work files** → NOT overwritten (never lose `active.md` progress)
- **New v2 dirs** → created if missing
- **Re-detection** → re-scans stack, shows proposed changes, asks PM before overwriting

```
/aid-init on existing workspace:
  [EXISTS] config/project.yaml — keeping existing
  [EXISTS] config/permissions.yaml — keeping existing
  [EXISTS] work/active.md — keeping existing (never overwrite)
  [CREATED] work/evidence/ — new directory
  Summary: 1 created, 4 already existed
```

## Upgrade (v1 → v2)

When `--upgrade` is passed or v1 structure detected (`.aid-o/04-engine/` exists):

### Path Migration

| v1 Path | v2 Path |
|---------|---------|
| `.aid-o/01-plans/` | `.aid-o/plans/` |
| `.aid-o/02-epics/` | `.aid-o/tasks/` |
| `.aid-o/03-config/` | `.aid-o/config/` |
| `.aid-o/04-engine/memory/` | `.aid-o/work/` |
| `.aid-o/04-engine/evidence/` | `.aid-o/work/evidence/` |
| `.aid-o/04-engine/epic-queue.yaml` | `.aid-o/config/queue.yaml` |
| `plan_progress.json` | `state.yaml` |
| `stage_log.jsonl` | `timeline.jsonl` |

### Upgrade Flow

1. Detect v1 structure (presence of `04-engine/`, `03-config/`, `02-epics/`)
2. Show migration plan to PM:
   ```
   v1 → v2 Migration Plan
   ====================================
   Move: .aid-o/01-plans/ → .aid-o/plans/
   Move: .aid-o/02-epics/ → .aid-o/tasks/
   Move: .aid-o/03-config/ → .aid-o/config/
   Move: .aid-o/04-engine/memory/ → .aid-o/work/
   Move: .aid-o/04-engine/evidence/ → .aid-o/work/evidence/
   Rename: config/project-profile.yaml → config/project.yaml (if exists)

   Proceed? (Y/N)
   ```
3. On PM approval → execute moves
4. Rename known v1 files inside moved directories:
   - `config/project-profile.yaml` → `config/project.yaml`
   - `plan_progress.json` → `state.yaml` (inside each evidence run dir)
   - `stage_log.jsonl` → `timeline.jsonl` (inside each evidence run dir)
5. Remove empty v1 directories
6. Run fresh-init logic (idempotent) — create any missing v2 template files:
   - `config/permissions.yaml`, `work/active.md`, `work/backlog.md`, etc.
   - Existing files are never overwritten

## Reference Files

- `skills/pipeline.md` — workspace structure reference
- `commands/aid-do.md` — uses `work/quick/` (lazy-created at init)
- `commands/aid-run.md` — uses `config/execution.yaml` (lazy-created)
- `commands/aid-status.md` — uses `config/queue.yaml` (lazy-created)

## Important

- **Idempotent** — safe to run repeatedly, never destroys existing data
- **10 items** — 5 files + 5 directories created on fresh init
- **Lazy creation** — advanced config created on first use, not at init
- **Auto-detect stack** — reads project root files to suggest test/lint/build commands
- **Upgrade path** — `--upgrade` migrates v1 paths to v2 with PM confirmation
- If `$ARGUMENTS` is empty → auto-detect mode (fresh init or upgrade)
