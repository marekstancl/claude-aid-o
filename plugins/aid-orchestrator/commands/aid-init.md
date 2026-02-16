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
| `backlog.md` | `# Backlog\n\n_Managed by AID Curator agent_\n\n## Active Proposals\n\n| ID | Type | Area | Suggestion | Priority | Source | Status |\n|----|------|------|------------|----------|--------|--------|\n\n## Deferred\n\n| ID | Type | Area | Suggestion | Reason | Date |\n|----|------|------|------------|--------|------|\n\n## Rejected\n\n| ID | Type | Area | Suggestion | Rejected by | Reason | Date |\n|----|------|------|------------|-------------|--------|------|\n\n## Implemented\n\n| ID | Type | Area | Epic Ref | Date |\n|----|------|------|----------|------|` |
| `lessons-learned.md` | `# Lessons Learned\n\n| Date | Lesson | Context |\n|------|---------|---------|` |
| `command-history.md` | `# Command History\n\n| Command | Purpose | Verified |\n|---------|---------|----------|` |
| `evidence/.gitkeep` | _(empty file)_ |

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
5. Print summary of what was created vs. skipped

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

## Important

- **NEVER delete or overwrite** existing files
- If `$ARGUMENTS` contains a path, use that as the target directory instead of current directory
- After initialization, remind the user to customize `03-config/policies/` files for their project
- Naming conventions: Plans `P-{YYYYMMDD}-{hash}`, Epics `E-{YYYYMMDD}-{hash}`, Sessions `S-{YYYYMMDD}-{hash}`
