---
sidebar_position: 1
title: "/aid-init"
description: "Initialize or upgrade the .aid-o/ workspace — 10-file structure, stack auto-detection, idempotent"
---

# /aid-init

Initialize a new `.aid-o/` workspace or upgrade an existing v1 workspace to v2 structure. Merges the v1 `/aid-setup` interactive onboarding into this command -- stack detection, gate configuration, and project profile are all handled automatically.

## Usage

```bash
/aid-init                   # Auto-detect mode (recommended)
/aid-init --upgrade         # Force upgrade from v1 to v2
```

### Examples

```bash
# Initialize in the current directory
/aid-init

# Force upgrade mode (skip version check)
/aid-init --upgrade
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `--upgrade` | flag | No | Skip fresh-init detection and go directly to v1 --> v2 upgrade mode |

## What It Does

### Fresh Init -- 10-Item Structure

Creates 5 files + 5 empty directories:

```text
.aid-o/
  config/
    project.yaml          # auto-detected: name, languages, test_cmd, lint_cmd, build_cmd
    permissions.yaml      # default: autonomous_mode: false
  work/
    active.md             # current focus (empty template)
    backlog.md            # improvement backlog (categorized sections)
    timeline.jsonl        # empty — first event written by /aid-run
  plans/                  # empty (for P-NNN plan files)
  tasks/                  # empty (for EPIC task files)
  work/quick/             # empty (for Q-NNN quick logs from /aid-do)
  work/evidence/          # empty (for run evidence)
```

### Stack Auto-Detection

Scans project root to populate `config/project.yaml`:

| File Found | Detected Stack | test_cmd | lint_cmd | build_cmd |
|-----------|---------------|----------|----------|-----------|
| `package.json` | TypeScript/JavaScript | `npm test` | `npm run lint` | `npm run build` |
| `pyproject.toml` | Python | `pytest` | `ruff check .` | -- |
| `Cargo.toml` | Rust | `cargo test` | `cargo clippy` | `cargo build` |
| `go.mod` | Go | `go test ./...` | `golangci-lint run` | `go build ./...` |
| `pom.xml` | Java/Kotlin | `mvn test` | -- | `mvn package` |

If multiple stacks detected, all are listed. Commands are suggestions -- PM can override in `project.yaml`.

### Generated Files

**`config/project.yaml`:**
```yaml
# Auto-detected by /aid-init — edit freely
project_name: "my-project"
languages: ["typescript"]
test_cmd: "npm test"
lint_cmd: "npm run lint"
build_cmd: "npm run build"
initialized_at: "2026-03-03T10:00:00Z"
```

**`config/permissions.yaml`:**
```yaml
# AID permissions — controls autonomous behavior
autonomous_mode: false    # set true to enable /aid-run --auto
auto_commit: false        # set true to allow auto-commits
auto_push: false          # set true to allow auto-push (requires auto_commit)
```

### Lazy-Created Files (NOT at init time)

These are created on first use of the feature that needs them:

| File | Created By | Trigger |
|------|-----------|---------|
| `config/execution.yaml` | `/aid-run` | First EPIC run |
| `config/queue.yaml` | `/aid-status queue add` | First queue entry |
| `config/orchestration.yaml` | `/aid-run` | First EPIC run with custom config |

## Idempotency

Safe to run multiple times:

- **Existing config files** -- NOT overwritten (show diff proposal if defaults changed)
- **Existing work files** -- NOT overwritten (never lose `active.md` progress)
- **New v2 dirs** -- created if missing
- **Re-detection** -- re-scans stack, shows proposed changes, asks PM before overwriting

```text
/aid-init on existing workspace:
  [EXISTS] config/project.yaml — keeping existing
  [EXISTS] config/permissions.yaml — keeping existing
  [EXISTS] work/active.md — keeping existing (never overwrite)
  [CREATED] work/evidence/ — new directory
  Summary: 1 created, 4 already existed
```

## Upgrade (v1 --> v2)

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
2. Show migration plan to PM for approval
3. On approval -- execute moves, create missing v2 directories, remove empty v1 directories

## CLAUDE.md Merge

`/aid-init` creates or updates `CLAUDE.md` using marker-based merge. It looks for `<!-- AID-O START -->` and `<!-- AID-O END -->` markers and replaces only the content between them -- all other content in `CLAUDE.md` is preserved.

## Key Behaviors

- **Idempotent** -- safe to run repeatedly, never destroys existing data
- **10 items** -- 5 files + 5 directories created on fresh init
- **Lazy creation** -- advanced config created on first use, not at init
- **Auto-detect stack** -- reads project root files to suggest test/lint/build commands
- **Upgrade path** -- `--upgrade` migrates v1 paths to v2 with PM confirmation

## Related Commands

- [`/aid-help`](./aid-help) -- AID documentation and help topics
- [`/aid-do`](./aid-do) -- quick tasks (first thing to try after init)
- [`/aid-plan`](./aid-plan) -- planning (second thing to try after init)
