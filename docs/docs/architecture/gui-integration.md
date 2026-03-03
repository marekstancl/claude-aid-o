---
sidebar_position: 9
title: "GUI Integration"
description: "How the AID Dashboard (aid-gui + aid-server) integrates with Claude Code and the orchestration engine."
---

# GUI Integration

AID includes an optional web dashboard that provides real-time visibility into orchestration. The GUI is a **read + approve** layer — it observes what Claude Code and the bash controller are doing, and lets the PM make decisions without switching to the terminal.

## Who Does What

```mermaid
flowchart LR
    subgraph User["Project Manager"]
        PM_CLI["Terminal<br/>(Claude Code)"]
        PM_GUI["Browser<br/>(AID Dashboard)"]
    end

    subgraph AID["AID Plugin (Claude Code)"]
        CMD["Commands<br/>/aid-do, /aid-run, /aid-plan..."]
        SKILLS["Skills<br/>pipeline, planner, gates..."]
        AGENTS["Agents<br/>implementer, verifier..."]
        BASH["Bash Controller<br/>FSM, gates, scope"]
    end

    subgraph GUI["AID Dashboard"]
        SERVER["aid-server<br/>(Express + WebSocket)"]
        FRONTEND["aid-gui<br/>(React + Zustand)"]
    end

    subgraph FS[".aid-o/ Filesystem"]
        STATE["state.yaml"]
        TIMELINE["timeline.jsonl"]
        GATES_OUT["gates/ output"]
        CONFIG["config/*.yaml"]
    end

    PM_CLI -->|"invokes"| CMD
    CMD -->|"loads"| SKILLS
    SKILLS -->|"dispatches"| AGENTS
    SKILLS -->|"calls"| BASH
    BASH -->|"writes"| FS
    AGENTS -->|"writes"| FS

    SERVER -->|"watches"| FS
    SERVER -->|"broadcasts events"| FRONTEND
    FRONTEND -->|"displays"| PM_GUI
    PM_GUI -->|"approves decisions"| SERVER
    SERVER -->|"writes decision"| FS
    BASH -->|"reads"| FS
```

### Responsibility Matrix

| Responsibility | Claude Code + AID | AID Dashboard (GUI) |
|---|---|---|
| **Execute commands** (`/aid-run`, `/aid-do`) | Yes — sole executor | No — read-only view |
| **Generate code** | Yes — via agents | No |
| **Run quality gates** | Yes — `aid-run-gates.sh` | No — displays results |
| **FSM state transitions** | Yes — `aid-fsm.sh` | No — displays state |
| **Plan approval** | Yes — terminal prompt | Yes — decision UI |
| **Escalation decisions** | Yes — terminal prompt | Yes — decision UI |
| **View pipeline progress** | Limited (text logs) | Yes — real-time timeline |
| **Browse evidence** | Yes — file system | Yes — searchable vault |
| **Token/cost tracking** | No | Yes — usage charts |
| **Project health overview** | Yes — `/aid-audit` | Yes — health dashboard |

## Architecture Layers

```mermaid
flowchart TB
    subgraph L1["Layer 1: User Interface"]
        CLI["Claude Code CLI<br/>(primary interface)"]
        WEB["AID Dashboard<br/>(optional web UI)"]
    end

    subgraph L2["Layer 2: Orchestration Engine"]
        CMDS["8 Slash Commands"]
        SK["8 Skills (LLM instructions)"]
        AG["7 Agents (role definitions)"]
    end

    subgraph L3["Layer 3: Bash Controller"]
        FSM["aid-fsm.sh"]
        GATES["aid-run-gates.sh"]
        STAGE["aid-stage-log.sh"]
        AUTO["aid-auto-pipeline.sh"]
    end

    subgraph L4["Layer 4: Data Layer (.aid-o/)"]
        CFG["config/"]
        WRK["work/"]
        TSK["tasks/"]
        PLN["01-plans/"]
    end

    subgraph L5["Layer 5: GUI Backend"]
        SRV["aid-server (Express)"]
        WS["WebSocket Hub"]
        WATCH["File Watcher"]
    end

    CLI -->|"invokes"| CMDS
    CMDS -->|"loads"| SK
    SK -->|"dispatches"| AG
    SK & AG -->|"calls"| L3
    L3 -->|"reads/writes"| L4

    WATCH -->|"monitors"| L4
    WATCH -->|"triggers"| WS
    WS -->|"pushes events"| WEB
    WEB -->|"HTTP requests"| SRV
    SRV -->|"reads"| L4
```

## Data Flow: Real-Time Updates

When Claude Code executes a pipeline, the GUI receives updates in real-time through file watching:

```mermaid
sequenceDiagram
    participant PM as PM (Terminal)
    participant CC as Claude Code
    participant FSM as aid-fsm.sh
    participant FS as .aid-o/ files
    participant Watch as File Watcher
    participant WS as WebSocket
    participant GUI as Dashboard

    PM->>CC: /aid-run EPIC-001
    CC->>FSM: init EPIC-001
    FSM->>FS: write state.yaml (READY)
    FS-->>Watch: file change detected
    Watch-->>WS: emit("pipeline", {state: READY})
    WS-->>GUI: broadcast to subscribers

    CC->>CC: dispatch implementer agent
    CC->>FS: write timeline.jsonl (step started)
    FS-->>Watch: file change detected
    Watch-->>WS: emit("pipeline.stage_log", entry)
    WS-->>GUI: update timeline

    CC->>FSM: transition EXECUTE → GATES
    FSM->>FS: update state.yaml (GATES)
    FS-->>Watch: file change detected
    Watch-->>WS: emit("pipeline", {state: GATES})
    WS-->>GUI: update state indicator

    CC->>FS: write gate results
    FS-->>Watch: file change detected
    Watch-->>WS: emit("pipeline.stage_log", gate results)
    WS-->>GUI: show gate pass/fail
```

## WebSocket Protocol

The GUI connects to `ws://localhost:{port}/ws` and uses topic-based pub/sub:

```mermaid
flowchart LR
    subgraph Client["aid-gui (Browser)"]
        SUB["subscribe(['pipeline',<br/>'decisions', 'evidence'])"]
    end

    subgraph Server["aid-server"]
        HUB["WebSocket Hub"]
        TOPICS["Topics:<br/>pipeline<br/>pipeline.stage_log<br/>decisions<br/>evidence<br/>queue<br/>usage<br/>epics<br/>companion.stream"]
    end

    subgraph Sources["Event Sources"]
        FW["File Watcher<br/>(.aid-o/ changes)"]
        API["REST API<br/>(user actions)"]
    end

    Client -->|"subscribe"| HUB
    HUB -->|"event broadcasts"| Client
    Sources -->|"trigger"| HUB
```

### Topics

| Topic | Source | Content |
|-------|--------|---------|
| `pipeline` | File watch on `state.yaml` | FSM state changes |
| `pipeline.stage_log` | File watch on `timeline.jsonl` | Step start/complete, gate results |
| `decisions` | REST API + file watch | Pending approvals, PM responses |
| `evidence` | File watch on `evidence/` | New artifacts |
| `queue` | File watch on queue files | Queue additions, completions |
| `usage` | Computed from timeline | Token counts, cost estimates |
| `epics` | File watch on `tasks/` | EPIC lifecycle events |

## GUI Screens

```mermaid
flowchart TB
    subgraph Dashboard["AID Dashboard Screens"]
        CC_SCREEN["Command Center<br/>(main hub)"]
        EPIC_SCREEN["Epic Lifecycle<br/>(create/track EPICs)"]
        QUEUE_SCREEN["Queue Scheduler<br/>(task queue)"]
        ACTIVITY_SCREEN["Activity Stream<br/>(event timeline)"]
        DECISION_SCREEN["Decision Hub<br/>(pending approvals)"]
        EVIDENCE_SCREEN["Evidence Vault<br/>(artifacts)"]
        HEALTH_SCREEN["Health Observatory<br/>(project health)"]
        IDEAS_SCREEN["Ideas → Execution<br/>(idea management)"]
    end

    CC_SCREEN -->|"current state"| PIPELINE_DATA["Pipeline State<br/>(state.yaml)"]
    EPIC_SCREEN -->|"EPIC specs"| TASK_DATA["Tasks<br/>(tasks/)"]
    ACTIVITY_SCREEN -->|"events"| TIMELINE_DATA["Timeline<br/>(timeline.jsonl)"]
    DECISION_SCREEN -->|"approvals"| DECISION_DATA["Decisions<br/>(pending/)"]
    EVIDENCE_SCREEN -->|"artifacts"| EVIDENCE_DATA["Evidence<br/>(evidence/)"]
    HEALTH_SCREEN -->|"audit"| CONFIG_DATA["Config<br/>(config/)"]
```

## Claude vs AID vs GUI: Complete Picture

```mermaid
flowchart TB
    subgraph Claude["Claude Code (LLM)"]
        direction TB
        C1["Reads skill instructions"]
        C2["Generates code"]
        C3["Reviews and reasons"]
        C4["Makes creative decisions"]
        C5["Runs bash commands"]
    end

    subgraph AID["AID Plugin"]
        direction TB
        A1["Defines the workflow<br/>(skills = instructions)"]
        A2["Manages FSM states<br/>(bash scripts)"]
        A3["Enforces quality gates<br/>(bash scripts)"]
        A4["Structures evidence<br/>(JSONL, YAML)"]
        A5["Dispatches agents<br/>(role definitions)"]
    end

    subgraph GUI_BLOCK["AID Dashboard"]
        direction TB
        G1["Visualizes progress<br/>(real-time)"]
        G2["Presents decisions<br/>(approve/reject)"]
        G3["Tracks costs<br/>(token usage)"]
        G4["Searches evidence<br/>(artifact vault)"]
        G5["Monitors health<br/>(project audit)"]
    end

    Claude -->|"follows"| AID
    AID -->|"produces files"| FS2[".aid-o/"]
    FS2 -->|"watched by"| GUI_BLOCK

    style Claude fill:#4A90D9,color:#fff
    style AID fill:#7B68EE,color:#fff
    style GUI_BLOCK fill:#2ECC71,color:#fff
```

**In summary:**
- **Claude Code** is the brain — it reads, thinks, writes code, and makes decisions
- **AID Plugin** is the process — it defines what to do, in what order, with what checks
- **AID Dashboard** is the window — it shows what is happening and collects PM input

## Running the Dashboard

```bash
# Start the server (watches .aid-o/ in your project)
cd packages/aid-server && npm run dev

# Start the GUI (opens in browser)
cd packages/aid-gui && npm run dev

# Or use Docker Compose (both services)
docker-compose up
```

The dashboard is optional. All orchestration works fully through Claude Code CLI commands. The GUI adds visibility and a PM-friendly approval interface.
