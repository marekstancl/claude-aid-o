# Design: `/aid-setup` v2 — Modular Configuration

**Date:** 2026-03-04
**Status:** Approved

## Context

v1 `/aid-setup` was a 1555-line monolithic wizard that handled everything from stack detection to MCP configuration. v2.0.0 merged it into `/aid-init` but dropped most interactive functionality — only stack auto-detection survived.

Result: `/aid-init` creates a workspace with disabled integrations, basic permissions, and no CLAUDE.md. Users must manually edit YAML files to configure their project.

## Decision

Reintroduce `/aid-setup` as a **modular configuration command** separate from `/aid-init`.

- `/aid-init` = workspace structure (directories + template files, idempotent)
- `/aid-setup` = project configuration (interactive, modular, re-runnable)

## Architecture

### Command + Skill Modules

```
commands/
  aid-setup.md              # thin router + menu (~150 lines)
skills/
  setup/
    permissions.md          # module 1
    integrations.md         # module 2
    claude-md.md            # module 3
    project-scan.md         # module 4
```

Router dispatches to skill modules. Each module is self-contained, reads/writes specific config files.

### Invocation

```
/aid-setup                    → interactive menu (1-4)
/aid-setup permissions        → direct module 1
/aid-setup integrations       → direct module 2
/aid-setup claude-md          → direct module 3
/aid-setup scan               → direct module 4
/aid-setup all                → sequential: 4→1→2→3 (scan first, then configure)
```

## Module Specifications

### Module 1: Permissions (`config/permissions.yaml`)

**Reads:** `config/permissions.yaml`
**Writes:** `config/permissions.yaml`, `.claude/settings.local.json`

Three presets:

| Preset | Description | autonomous_mode | auto_commit | auto_push | Destructive |
|--------|-------------|-----------------|-------------|-----------|-------------|
| **autonomous** (default) | Max autonomy, no destructive ops | true | true | false | DENIED |
| **steroids** | Full power, everything allowed | true | true | true | allowed (with deny-list) |
| **custom** | User configures each setting | ask | ask | ask | ask |

**autonomous preset** (NEW — replaces aspirin as default):
- `Bash(*:*)` auto-allowed
- All MCP tools auto-allowed
- Deny list: `rm -rf`, `git push --force`, `git reset --hard`, `DROP TABLE`, `DELETE FROM` (without WHERE), `kill -9`
- `auto_commit: true`, `auto_push: false`
- This matches what the user currently uses across all projects

**Flow:**
1. Show current preset
2. Offer 3 choices (autonomous recommended)
3. If custom → ask each setting interactively
4. Dual-write: `permissions.yaml` + `.claude/settings.local.json`

### Module 2: Integrations (`config/integrations.yaml`)

**Reads:** `.claude/settings.json`, `config/integrations.yaml`
**Writes:** `config/integrations.yaml`

**Flow:**
1. Scan `.claude/settings.json` for installed MCP servers
2. For each detected MCP, show status:
   ```
   MCP Servers detected:
     [installed] qdrant-memory — Project memory & search
     [installed] context7 — Library documentation
     [installed] shared-docker — Container management
     [not found] shared-slack — PM notifications
   ```
3. For each installed MCP → ask: enable in AID? (Y/n)
4. For not-found MCPs → show install instructions (optional)
5. Write enabled integrations to `integrations.yaml`

**No hardcoded MCP list** — scanner reads what's available, presents it. New MCPs work automatically.

### Module 3: CLAUDE.md Generation

**Reads:** project root files, `config/project.yaml`
**Writes:** root `CLAUDE.md`

**Flow:**
1. Run `project-scanner` agent → detect stack, conventions, structure
2. Generate CLAUDE.md with sections:
   - Project overview (name, type, stack)
   - Directory structure
   - Development commands (test, lint, build)
   - AID workspace reference
   - Conventions (detected from existing code)
3. If CLAUDE.md exists → show diff, ask PM to approve merge
4. Preserve existing user content (append AID section, don't overwrite)

### Module 4: Project Scan (`config/project.yaml`)

**Reads:** project root files
**Writes:** `config/project.yaml`

**Flow:**
1. Re-detect: languages, frameworks, test_cmd, lint_cmd, build_cmd
2. Diff against existing `project.yaml`
3. Show changes, PM approves

## Token Budget

| Component | Estimated lines | Loaded when |
|-----------|----------------|-------------|
| Router (`aid-setup.md`) | ~150 | always |
| Selected module | ~100-150 | on demand |
| **Total per invocation** | ~250-300 | — |
| Old v1 `/aid-setup` | 1555 | always |

~80% reduction vs v1.

## Scalability

New module = new file in `skills/setup/` + one menu entry in router. No existing code changes needed.

## Prerequisites

- `/aid-init` must have run first (`.aid-o/` exists)
- Router checks for `.aid-o/` and suggests `/aid-init` if missing

## What This Does NOT Do

- Create `.aid-o/` structure → `/aid-init`
- Upgrade v1→v2 → `/aid-init --upgrade`
- Brainstorm/scaffold new projects → `/aid-plan`
- Styled banners → unnecessary token cost
- Skill conflict detection → removed (overly complex, rarely useful)
