---
sidebar_position: 1
---

# Architecture Diagrams

All 8 architecture diagrams for AID Orchestrator v2.0. Updated throughout Phases 1–7 as implementation progresses.

---

## Diagram 1: Dual-Layer Architecture

*(Phase 1, Step 6)* — Two-layer separation: deterministic bash controller (Layer 1) and LLM prompt layer (Layer 2). Agents call bash scripts via Bash tool; bash scripts report back via exit codes and JSON.

```mermaid
graph TB
  subgraph "Layer 1: Bash Controller (deterministic)"
    FSM[aid-fsm.sh\nstate transitions]
    GATES[aid-run-gates.sh\ngate evaluation]
    LOG[aid-stage-log.sh\nJSONL logging]
    TOKEN[aid-token-count.sh\ntoken estimation]
  end
  subgraph "Layer 2: LLM Prompt Layer"
    SKILLS[8 Skills\npipeline.md, planner.md ...]
    AGENTS[8 Agents\nimplementer, verifier ...]
    CMDS[8 Commands\n/aid-do, /aid-plan ...]
  end
  FSM -->|exit codes| AGENTS
  AGENTS -->|Bash tool calls| FSM
  GATES -->|JSON report| SKILLS
  LOG -->|timeline.jsonl| SKILLS
```

---

## Diagram 2: 6-State FSM

*(Phase 1, Step 6)* — Deterministic state machine implemented in bash. All state transitions are code, not LLM instructions. See [fsm.md](./fsm.md) for full reference.

```mermaid
stateDiagram-v2
  [*] --> READY: PRE-FLIGHT bash
  READY --> EXECUTE: approve
  READY --> [*]: reject
  EXECUTE --> EXECUTE: next step
  EXECUTE --> GATES: all steps done
  EXECUTE --> ESCALATION: hard failure
  GATES --> DONE: all pass
  GATES --> EXECUTE: retry (max 2)
  GATES --> ESCALATION: retries exhausted
  ESCALATION --> EXECUTE: fix applied
  ESCALATION --> GATES: skip gate
  ESCALATION --> [*]: abort
  DONE --> [*]
```

---

## Diagram 3: Dual Execution Modes

*(Phase 4, Step 22)* — FAST MODE for small tasks (< 2 min overhead), EPIC MODE for multi-step work. See [execution-modes.md](./execution-modes.md) for comparison table.

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

---

## Diagram 4: PRE-FLIGHT Pipeline

*(Phase 4, Step 26)* — Three bash scripts convert a Plan file into a structured Run file. FSM enters READY state after PRE-FLIGHT completes; PM approval triggers EXECUTE.

```mermaid
flowchart LR
  PM[PM: /aid-run] --> P1
  P1[aid-plan-to-epic.sh] --> P2
  P2[aid-epic-to-json.sh\nKahn's DAG] --> P3
  P3[aid-json-to-run.sh] --> P4
  P4[run.md created] --> READY[FSM: READY]
  READY -->|PM approve| EXECUTE[FSM: EXECUTE]
```

---

## Diagram 5: Gate Evaluation Flow

*(Phase 1, Step 7)* — `aid-run-gates.sh` evaluates each gate command. Required gates that fail after retries trigger ESCALATION; PM decides fix / skip / abort.

```mermaid
flowchart TD
  GATES[FSM: GATES state]
  GATES --> RUN[aid-run-gates.sh\nrun each gate command]
  RUN -->|exit 0| PASS[gate: pass]
  RUN -->|exit ≠ 0| FAIL[gate: fail]
  FAIL -->|required=true\nretries exhausted| ESC[FSM: ESCALATION]
  FAIL -->|max_retries > 0| RETRY[retry gate\nmax 2×]
  RETRY --> RUN
  PASS --> CURATOR[Curator hook\npost-gate]
  CURATOR --> DONE[FSM: DONE]
  ESC -->|PM: fix| EXECUTE[FSM: EXECUTE]
  ESC -->|PM: skip| GATES
  ESC -->|PM: abort| END[end]
```

---

## Diagram 6: Curator Flow

*(Phase 3, Step 20)* — After gates pass, Curator agent reads improvement notes from step outputs, evaluates effort, and auto-dispatches S-effort fixes. Results written to backlog.md.

```mermaid
sequenceDiagram
  participant G as Gates (pass)
  participant C as Curator agent
  participant B as backlog.md
  participant I as implementer agent

  G->>C: post-gate hook trigger
  C->>B: read improvement_notes from step outputs
  C->>B: evaluate effort (S/M/L)
  C->>B: write status: "implementing" (pre-flight)
  C->>I: dispatch fix (S-effort only)
  I-->>C: fix result
  alt success
    C->>B: write status: "implemented"
  else fail
    C->>B: write status: "deferred: fix failed"
  end
```

---

## Diagram 7: Evidence Trail Structure

*(Phase 1, Step 4)* — Two evidence paths: FAST MODE uses `quick/Q-NNN.md`, EPIC MODE uses full `evidence/{epic_id}/{run_id}/` directory with JSONL timeline and per-step outputs.

```mermaid
graph LR
  subgraph ".aid-o/work/"
    S[state.yaml\nmutable, crash recovery]
    T[timeline.jsonl\nappend-only, evidence]
    subgraph "quick/"
      Q[Q-001.md\nQ-002.md\n...]
    end
    subgraph "evidence/E-003-1_2/R-001/"
      S2[state.yaml]
      T2[timeline.jsonl]
      subgraph "steps/"
        STEP1[step_1_architect/output.md]
        STEP2[step_2_backend/output.md]
      end
    end
  end
```

---

## Diagram 8: Agent Dispatch Pattern

*(Phase 3, Step 18)* — Controller loads role card, assembles context (plan section + role card + agent-protocol.md), dispatches agent. Agent result determines next FSM transition.

```mermaid
flowchart TD
  EXECUTE[FSM: EXECUTE\ncurrent_step=N]
  EXECUTE --> LOAD[Load role card\nfrom role-cards.md]
  LOAD --> CTX[Assemble context\nplan section + role card\n+ agent-protocol.md]
  CTX --> DISPATCH[Dispatch agent\nvia Agent tool]
  DISPATCH --> OUTPUT[Agent output\nresult: pass/fail\nimprovement_notes]
  OUTPUT -->|pass| NEXT[increment step\nFSM: EXECUTE N+1\nor GATES if last]
  OUTPUT -->|fail| ESC[FSM: ESCALATION]
```

---

*Last Updated: 2026-03-03 (Phase 0 baseline — diagrams 1–8 created as living document)*
