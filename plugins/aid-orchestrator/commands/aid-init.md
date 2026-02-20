---
name: aid-init
description: Initialize .aid-o/ workspace structure
user_invocable: true
---

Initialize AID workspace (`.aid-o/`) in the current project.

This command creates the recommended workspace structure and copies default configuration files from the plugin's `defaults/` directory. It is **idempotent** — running it again will not overwrite existing files.

## Usage

```
/aid-init
```

## What It Creates

### Directory Structure

Create the following directories (skip if they already exist):

```
.aid-o/
  01-plans/
    archive/
  02-epics/
    archive/
  03-config/
    policies/
    templates/
    playbooks/
  04-engine/
    sessions/
      archive/
    memory/
    evidence/
```

### Config Files (from plugin defaults/)

Copy these files from the plugin's `defaults/` directory into `.aid-o/03-config/`. **Do NOT overwrite existing files** — if a file already exists, skip it and note "already exists" in the output.

| Source (plugin defaults/) | Destination (.aid-o/03-config/) |
|---------------------------|--------------------------------|
| `policies/gates.yaml` | `policies/gates.yaml` |
| `policies/decision-policies.yaml` | `policies/decision-policies.yaml` |
| `policies/slack-config.yaml` | `policies/slack-config.yaml` |
| `policies/memory-config.yaml` | `policies/memory-config.yaml` |
| `policies/dispatch-strategy.yaml` | `policies/dispatch-strategy.yaml` |
| `policies/language.yaml` | `policies/language.yaml` |
| `policies/permissions.yaml` | `policies/permissions.yaml` |
| `templates/plan.md` | `templates/plan.md` |
| `templates/epic.md` | `templates/epic.md` |
| `templates/plan.schema.json` | `templates/plan.schema.json` |
| `templates/session-bug-fix.md` | `templates/session-bug-fix.md` |
| `templates/session-new-feature.md` | `templates/session-new-feature.md` |
| `templates/session-refactoring.md` | `templates/session-refactoring.md` |
| `templates/session-exploration.md` | `templates/session-exploration.md` |
| `playbooks/architect.md` | `playbooks/architect.md` |
| `playbooks/domain.md` | `playbooks/domain.md` |
| `playbooks/backend.md` | `playbooks/backend.md` |
| `playbooks/frontend.md` | `playbooks/frontend.md` |
| `playbooks/qa.md` | `playbooks/qa.md` |
| `playbooks/security.md` | `playbooks/security.md` |
| `playbooks/observability.md` | `playbooks/observability.md` |
| `playbooks/docs.md` | `playbooks/docs.md` |
| `playbooks/release.md` | `playbooks/release.md` |

### Engine Files

Create these empty tracking files in `.aid-o/04-engine/` (skip if they already exist):

| File | Initial Content |
|------|----------------|
| `memory/active-work.md` | `# Active Work\n\n_Initialized by /aid-init_\n\n## Current Focus\n\n_No active work_\n\n## Context for Next Session\n\n## Recent Work\n\n## Next Steps\n\n## Blockers` |
| `memory/project-profile.yaml` | `# Project Profile\n# Auto-populated by /aid-setup or Project Scanner agent\n\nproject_name: ""\ntech_stack: {}\narchitecture: ""\ninitialized: false` |
| `memory/decisions.yaml` | `# Key Decisions\n# ADR-lite format — recorded by Orchestrator\n\ndecisions: []` |
| `backlog.md` | See **Backlog Template** below |
| `lessons-learned.md` | `# Lessons Learned\n\n| Date | Lesson | Context |\n|------|---------|---------|` |
| `command-history.md` | `# Command History\n\n| Command | Purpose | Verified |\n|---------|---------|----------|` |
| `evidence/.gitkeep` | _(empty file)_ |

### Backlog Template

The `backlog.md` file uses categorized sections for different proposal types.
**Source values:** `user` (submitted by PM), `agent` (discovered by AI agent during EPIC),
`curator` (proposed by Curator post-processing), `audit` (found by Auditor).

Initial content for `backlog.md`:

```markdown
# AID Backlog

_Managed by AID Curator agent. Source: user | agent | curator | audit_

## Active Proposals

### Bugs
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Features
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Refactoring / Tech Debt
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Performance
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

## Deferred
| ID | Type | Priority | Source | Summary | Reason |
|----|------|----------|--------|---------|--------|

## Rejected
| ID | Type | Source | Summary | Reason |
|----|------|--------|---------|--------|

## Implemented
| ID | Type | Source | Summary | Implemented In |
|----|------|--------|---------|----------------|
```

## Implementation Steps

1. Determine the plugin's `defaults/` directory location (relative to this command file: `../defaults/`)
2. For each directory in the structure above:
   - Check if it exists → if yes, skip
   - If no, create it with `mkdir -p`
3. For each config file to copy:
   - Check if destination exists → if yes, skip and log "already exists"
   - If no, read source from plugin defaults/ and write to destination
4. For each engine file:
   - Check if it exists → if yes, skip
   - If no, create with initial content
5. Update CLAUDE.md in the project root with the AID section (see **CLAUDE.md Marker-Based Merge** below)
6. Print summary of what was created vs. skipped

## Output Format

```
AID Workspace Initialized (.aid-o/)
====================================

Directories:
  [CREATED] .aid-o/01-plans/
  [CREATED] .aid-o/01-plans/archive/
  [EXISTS]  .aid-o/02-epics/
  ...

Config files (.aid-o/03-config/):
  [CREATED] policies/gates.yaml
  [EXISTS]  policies/decision-policies.yaml
  ...

Engine files (.aid-o/04-engine/):
  [CREATED] memory/active-work.md
  [CREATED] backlog.md
  [EXISTS]  lessons-learned.md
  ...

Summary: {N} created, {M} already existed

Next steps:
  1. Run /aid-setup for interactive project onboarding
  2. Customize .aid-o/03-config/policies/ for your project
  3. Create your first Plan in .aid-o/01-plans/
```

## CLAUDE.md Marker-Based Merge

Step 5 of the implementation handles creating or updating `CLAUDE.md` in the project root so that AID information is always present and up to date, without destroying any user-written content.

### Markers

The AID section is delimited by exactly these HTML comment markers:

```
<!-- AID-O START -->
<!-- AID-O END -->
```

### AID Section Content

The full block (including markers) that is written:

```markdown
<!-- AID-O START -->
## AID Orchestrator

This project uses AID for multi-agent orchestration.

**Workspace:** `.aid-o/`
**Commands:** `/aid-help` for full documentation
**Quick start:** `/aid-setup` → create EPIC → `/run-epic`

**Key paths:**
- Plans: `.aid-o/01-plans/`
- EPICs: `.aid-o/02-epics/`
- Config: `.aid-o/03-config/`
- Engine: `.aid-o/04-engine/`
<!-- AID-O END -->
```

### Merge Logic

1. **Generate** the AID section content (the block above).
2. **Check** if `CLAUDE.md` exists in the project root.
3. **If CLAUDE.md exists:**
   a. Read the entire file content.
   b. Search for `<!-- AID-O START -->` and `<!-- AID-O END -->` markers.
   c. **If both markers are found:** replace everything from `<!-- AID-O START -->` through `<!-- AID-O END -->` (inclusive) with the new AID section content. All content before and after the markers is preserved exactly as-is.
   d. **If markers are NOT found:** append a blank line followed by the AID section content at the end of the file.
   e. Log `[UPDATED] CLAUDE.md (markers replaced)` or `[UPDATED] CLAUDE.md (section appended)`.
4. **If CLAUDE.md does not exist:**
   a. Create `CLAUDE.md` with the AID section content as its sole content.
   b. Log `[CREATED] CLAUDE.md`.

### Output Format Addition

Add to the initialization output after the Engine files block:

```
CLAUDE.md:
  [CREATED]  CLAUDE.md
```

or

```
CLAUDE.md:
  [UPDATED] CLAUDE.md (markers replaced)
```

or

```
CLAUDE.md:
  [UPDATED] CLAUDE.md (section appended)
```

## Important

- **NEVER delete or overwrite** existing files
- If `$ARGUMENTS` contains a path, use that as the target directory instead of current directory
- After initialization, remind the user to customize `03-config/policies/` files for their project
- Naming conventions: Plans `P-{YYYYMMDD}-{hash}`, Epics `E-{YYYYMMDD}-{hash}`, Sessions `S-{YYYYMMDD}-{hash}`
