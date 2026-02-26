---
sidebar_position: 18
title: "Run Validator Agent"
description: "Validate run file completeness at phase-end and run-end checkpoints."
---

# Run Validator Agent

The Run Validator agent checks that run files are complete and correct at phase-end and run-end checkpoints. It reads the run file and validates it against the AID run file requirements, producing a structured PASS/FAIL report.

## Role

The Run Validator is a **utility agent**. It does not modify any files — it reads and validates only. It is used at phase-end checkpoints and before run completion to verify the run file meets all AID requirements.

## When Dispatched

- After completing a phase, to verify the phase is correctly documented in the run file
- Before run end, to confirm the run file is complete and ready for finalization
- When the Controller needs to validate run file completeness at a checkpoint

## Capabilities

### Frontmatter Validation

- `id` present and matches format `S-YYYYMMDD-{4char}`
- `type` is one of: new-feature, bug-fix, refactoring, exploration, verification
- `status` is one of: active, blocked, completed
- `priority` present, `started` has a date, `ai_agent` present
- For EPIC runs: `epic_id`, `epic_run`, `epic_file` all present

### Completed Phases Validation

- Each completed phase has status "done" or equivalent marker
- Each completed phase has at least one commit hash referenced
- Changes table populated for completed phases (File, Description, Status columns)

### Content Completeness Validation

- Objective section is filled (not a template placeholder)
- At least one deliverable or requirement listed
- AI Run Log has at least one entry with a timestamp

### Testing Validation (mandatory for last phase)

- If this is the last phase of a run or EPIC, a testing proposal must exist
- Testing section has concrete steps, not just template placeholders

### No Empty Required Sections

- Objective, Requirements/Deliverables, and Implementation sections have content
- Template placeholders like `{Title}` or `{description}` are replaced

## Tools Available

Read access to the run file and `skills/run-management.md` for full run file requirements.

## Key Behaviors

- **Read-only.** Does not modify any files.
- **Produces a structured report** with PASS/FAIL per check, an overall verdict, and a list of specific issues with descriptions.
- **References `skills/run-management.md`** for full run file requirements if needed.

## Related

- [Run Management Skill](../skills/run-management)
- [Epic Orchestration Skill](../skills/epic-orchestration)
