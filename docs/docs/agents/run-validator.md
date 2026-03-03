---
sidebar_position: 8
title: "Run Validator Agent"
description: "Validate run files, state.yaml, evidence completeness, and quick log format."
---

# Run Validator Agent

The Run Validator checks that task evidence files are complete and correct. It validates FSM state files, timeline logs, quick logs (FAST MODE), and task files (EPIC MODE), producing a structured PASS/FAIL report.

## Role

The Run Validator is a **utility agent**. It does not modify any files — it reads and validates only. Used after completing a phase or before run end.

## When Dispatched

- After completing a phase, to verify evidence is correctly recorded
- Before run end, to confirm evidence completeness
- When the pipeline needs to validate run state at a checkpoint

## What It Validates

### 1. state.yaml (FSM State File)
- `epic_id` present and format-correct (`E-NNN` or `E-NNN-phase_total`)
- `state` is valid FSM state: READY, EXECUTE, GATES, ESCALATION, DONE, ERROR
- `current_step` within bounds (0 to `total_steps`)
- `mode` is "manual" or "auto"
- `started_at` is valid ISO 8601

### 2. timeline.jsonl (Event Log)
- File exists and is non-empty
- Each line is valid JSON with `timestamp`, `eventType`, `state`
- At least one `fsm_transition` or `step_dispatch` event
- Timestamps are non-decreasing (minute granularity)

### 3. Quick Log Q-NNN.md (FAST MODE only)
- Frontmatter has: `id`, `task`, `started_at`, `duration_s`, `files_changed`, `commit`
- `commit` is a valid git short SHA (7+ hex chars)

### 4. Task File (EPIC MODE only)
- File exists in `.aid-o/tasks/`
- Frontmatter `id` matches `epic_id` from state.yaml

## Output Format

```
RUN VALIDATION REPORT
=========================
Run: {epic_id}
Evidence: {evidence_dir}

RESULTS:
  [PASS|FAIL] state.yaml -- FSM state valid
  [PASS|FAIL] timeline.jsonl -- event log valid
  [PASS|FAIL] Quick log format (FAST MODE only)
  [PASS|FAIL] Task file present (EPIC MODE)

OVERALL: PASS | FAIL
```

## Key Behaviors

- **Read-only.** Validate evidence structure, never modify it.
- **Missing state.yaml = immediate FAIL.** Cannot validate without FSM state.
- **Empty timeline.jsonl = FAIL.** Every run must produce at least one event.
- **Model:** haiku (fast, lightweight validation)

## Related

- [Run Management Skill](../skills/run-management)
- [Pipeline Skill](../skills/pipeline)
