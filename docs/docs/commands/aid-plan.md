---
sidebar_position: 3
title: "/aid-plan"
description: "Unified planning — brainstorm, write plan, or generate EPICs (auto-detected or forced)"
---

# /aid-plan

Unified planning command -- merges brainstorming, plan writing, and EPIC generation into a single entry point with auto-detection. Replaces the v1 `/aid-brainstorm`, `/aid-plan-epic`, and `/aid-write-plan` commands.

## Usage

```bash
/aid-plan [mode] [input]
```

### Modes

| Mode | Usage | What It Does |
|------|-------|-------------|
| _(auto)_ | `/aid-plan` | Auto-detect: brainstorm if unclear, write plan if spec provided, generate EPIC if plan exists |
| `brainstorm` | `/aid-plan brainstorm "topic"` | Force 8-step interactive brainstorm |
| `write` | `/aid-plan write spec.md` | Force plan writing from specification |
| `epic` | `/aid-plan epic plan.md` | Force EPIC generation from plan |

### Examples

```bash
# Auto-detect mode (recommended)
/aid-plan

# Topic string → auto-detects brainstorm
/aid-plan "add user authentication"

# Force brainstorm mode
/aid-plan brainstorm "migrate to PostgreSQL"

# Write plan from a spec file
/aid-plan write requirements.md

# Write plan from an EPIC draft
/aid-plan write .aid-o/tasks/E-015.md

# Generate EPICs from a completed plan
/aid-plan epic .aid-o/plans/P005-auth.md
```

## What It Does

```mermaid
flowchart TD
    A[/aid-plan input] --> B{Mode specified?}
    B -- Yes --> C{Which mode?}
    B -- No --> D[Auto-detect from input]

    D --> E{Input type?}
    E -- No input or topic string --> F[Brainstorm]
    E -- Spec/requirements file --> G[Write Plan]
    E -- Plan file --> H[Generate EPIC]
    E -- Ambiguous --> I[Ask PM to choose]

    C -- brainstorm --> F
    C -- write --> G
    C -- epic --> H

    F --> J[8-step interactive flow]
    J --> K[Plan written to .aid-o/plans/]

    G --> L[Codebase analysis + clarification]
    L --> M[Quality gates: Forbidden Phrases + 16 checks]
    M --> K

    H --> N[Parse plan, extract phases]
    N --> O[Ask PM: chain / separate / custom deps]
    O --> P[Run bash pipeline: aid-auto-pipeline.sh]
    P --> Q[EPICs + plan.json created in .aid-o/tasks/]
```

### Auto-Detection Logic

When mode is not specified, AID detects from input:

| Input | Detected Mode | Rationale |
|-------|--------------|-----------|
| No input | `brainstorm` | No context -- explore interactively |
| Topic string (not a file) | `brainstorm` | Idea -- needs exploration |
| Spec/requirements file | `write` | Has `type: spec` or no plan/epic markers |
| EPIC draft file | `write` | Has `type: epic` or `# EPIC:` header |
| Plan file | `epic` | Has `type: plan` or `# Plan:` header |

If detection is ambiguous, AID asks PM to choose (A) Brainstorm, (B) Write plan, or (C) Generate EPIC.

## Mode: Brainstorm

Interactive 8-step flow to explore an idea and produce a plan document.

| Step | Name | What Happens |
|------|------|-------------|
| 1 | Context | Reads workspace state, detects PM language |
| 2 | Analysis | Structured analysis of topic, PM confirms understanding |
| 3 | Questions | 3-7 clarifying questions, one at a time, multiple-choice preferred |
| 4 | Approaches | 2-3 approaches with pros/cons/effort/risk + recommendation |
| 5 | Design | Expands chosen approach: architecture, data model, API, risks |
| 6 | Sections | Section-by-section approval (`[x] approved` / `[ ] pending`) |
| 7 | Approval | Final design summary, PM approves (Y/N) |
| 8 | Document | Delegates to plan-writing skill, writes `.aid-o/plans/P{NNN}-{topic}.md` |

**Hard rules:**
- ONE question at a time -- never batch
- 2-3 approaches with recommendation -- never single option
- Section-by-section approval -- never skip to final
- YAGNI -- simplest solution meeting requirements

## Mode: Write Plan

Write an exhaustive implementation plan from specification or topic.

1. **Input resolution** -- read spec file, detect format
2. **Context** -- read `config/project.yaml`, `work/active.md`, scan related plans
3. **Codebase analysis** -- identify affected areas, read key files, note patterns
4. **Clarification** -- max 5 questions if spec has gaps (skip if clear)
5. **Plan assembly** -- write section by section
6. **Quality gates** -- Forbidden Phrase Detection + Completeness Gate (16 checks)
7. **Write file** -- generate plan ID (`P{NNN}`), write to `.aid-o/plans/{id}-{topic}.md`

## Mode: Generate EPIC

Parse a Plan file and generate EPICs (one per phase), plan.json, run files, and queue entries.

1. **Validate** -- confirm input is a Plan file
2. **Analyze** -- count phases, extract plan ID and title
3. **Queue mode** -- ask PM: chain (A), separate (B), or custom (C) dependencies
4. **Run pipeline** -- `bash scripts/aid-auto-pipeline.sh --plan <path> --queue-mode <mode>`
5. **Validate output** -- check JSON manifest, verify all files created
6. **Report** -- show created EPICs, queue status, next steps

## Output Files

| Mode | Output |
|------|--------|
| Brainstorm | `.aid-o/plans/P{NNN}-{topic}.md` |
| Write Plan | `.aid-o/plans/P{NNN}-{topic}.md` |
| Generate EPIC | `.aid-o/tasks/E-{id}.md` + `plan.json` per phase |

## Key Behaviors

- **Auto-detect by default** -- mode selection only when explicitly specified or ambiguous
- **Quality gates are mandatory** -- plans not written until gates pass
- **Language split** -- conversation in PM's language; documents per `config/project.yaml`
- **YAGNI** -- never proposes over-engineered solutions
- If PM aborts at any step, the command ends gracefully with no files written

## Related Commands

- [`/aid-do`](./aid-do) -- for tasks too small to need planning
- [`/aid-run`](./aid-run) -- execute EPICs generated by this command
- [`/aid-status`](./aid-status) -- check queue after EPIC generation
- [`/aid-init`](./aid-init) -- initialize workspace (suggested if `.aid-o/` missing)
