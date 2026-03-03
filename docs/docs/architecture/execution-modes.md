---
sidebar_position: 3
---

# Dual Execution Modes

AID v2.0 supports two execution modes to minimize overhead for small tasks while preserving full evidence trail for complex work.

```mermaid
flowchart LR
  INPUT[User request]
  INPUT -->|"/aid-do task"| FAST
  INPUT -->|"/aid-run"| EPIC

  subgraph FAST[FAST MODE]
    F1[Direct implementation]
    F2[Git hook gates]
    F3[Q-NNN.md quick log]
    F1 --> F2 --> F3
  end

  subgraph EPIC[EPIC MODE]
    E1[PRE-FLIGHT bash]
    E2[6-state FSM]
    E3[Multi-agent dispatch]
    E4[Full evidence trail]
    E1 --> E2 --> E3 --> E4
  end

  FAST -->|scope explodes\n>5 files, 3+ layers| EPIC
```

## Mode Comparison

| Feature | FAST MODE (/aid-do) | EPIC MODE (/aid-run) |
|---------|--------------------|--------------------|
| Overhead | < 2 min | 5–30 min (planning) |
| Evidence | Q-NNN.md quick log | Full timeline.jsonl |
| Gates | git pre-commit hooks | aid-run-gates.sh |
| Best for | 1-file fixes, small features | Multi-step, multi-role work |

## Escalation Rule

FAST MODE automatically escalates to EPIC MODE when scope expands beyond:
- More than 5 files changed
- Changes spanning 3+ architectural layers
- Task requires multi-agent coordination

---

*Last Updated: 2026-03-03 (Phase 0 baseline — execution modes diagram created as living document)*
