---
sidebar_position: 3
title: "/aid-brainstorm"
description: "11-step interactive brainstorming flow that produces a plan and EPIC draft"
---

# /aid-brainstorm

Collaborate with AID through an interactive 11-step brainstorming flow to explore an idea, design a solution, validate the approach section by section, and produce both a plan document and an EPIC draft — ready for execution.

## Usage

```bash
/aid-brainstorm [topic]
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `topic` | string | No | Initial topic or idea to explore. If omitted, you are asked to provide one. |

## Examples

```bash
# Start open brainstorming
/aid-brainstorm

# Start with a topic seed
/aid-brainstorm user authentication

# Start with a specific idea
/aid-brainstorm "migrate to PostgreSQL"
```

## Prerequisites

- `.aid-o/` workspace should exist (run [`/aid-init`](./aid-init) first). The command works without it but writes files to the current directory with a warning.
- No EPIC or plan file is required — this command creates them.

## How It Works

The command guides you through 11 structured steps:

| Step | Name | What Happens |
|------|------|--------------|
| 1 | Context | Reads workspace state (active-work, project-profile, recent EPICs) and detects your language |
| 2 | Analysis | Presents a structured analysis of your topic for confirmation |
| 3 | Questions | Asks clarifying questions one at a time (3–7 total, multiple-choice preferred) |
| 4 | Approaches | Proposes 2–3 approaches with pros, cons, effort estimate, and a recommendation |
| 5 | Design | Expands the chosen approach into architecture, data model, API, implementation plan, and risks |
| 6 | Sections | Walks through each design section for your approval (approve / modify / skip) |
| 7 | Approval | Final design approval before writing any files |
| 8 | Document | Writes the validated design to `.aid-o/01-plans/{plan_id}-{topic}.md` |
| 9 | EPIC Subagent | Generates an EPIC draft from the plan and saves it to `.aid-o/02-epics/{epic_id}-{topic}.md` |
| 10 | Execution Plan | Optionally generates Plan JSON inline (runs [`/aid-plan-epic`](./aid-plan-epic) logic) |
| 11 | Handoff | Presents options: add more items, create EPIC for all phases, pick a phase, or stop |

## Notes

- **One question at a time** — AID never batches questions. Each question waits for your answer before proceeding.
- **Language split** — the conversation follows your language; output documents follow the `document_language` setting in `.aid-o/03-config/language.yaml`.
- **YAGNI by default** — solutions start simple. You can ask for more complexity if needed.
- **Abort gracefully** — saying "stop", "cancel", or "abort" at any step ends the session without writing files.
- **This command creates two files**: a plan document and an EPIC draft. It never modifies existing files.

## Output Files

| File | Description |
|------|-------------|
| `.aid-o/01-plans/{plan_id}-{topic}.md` | Plan document with context, goal, approach, and high-level steps |
| `.aid-o/02-epics/{epic_id}-{topic}.md` | EPIC draft with role pipeline, gates, and acceptance criteria |

## Related

- [`/aid-plan-epic`](./aid-plan-epic) — generate execution Plan JSON from an EPIC or plan
- [`/aid-run-epic`](./aid-run-epic) — execute the EPIC orchestration pipeline
- [`/aid-init`](./aid-init) — initialize the workspace before brainstorming
