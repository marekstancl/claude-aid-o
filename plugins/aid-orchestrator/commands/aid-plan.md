---
name: aid-plan
description: Plan a task — brainstorm, write plan, or generate EPIC (auto-detected or forced)
user_invocable: true
---

Unified planning command — merges brainstorming, plan writing, and EPIC generation into a single entry point with auto-detection.

## Usage

```
/aid-plan [mode] [input]
```

**Modes:**
- `/aid-plan` — auto-detect: brainstorm if unclear, write plan if spec provided, generate EPIC if plan exists
- `/aid-plan brainstorm [topic]` — force 8-step interactive brainstorm
- `/aid-plan write [spec-file]` — force plan writing from specification
- `/aid-plan epic [plan-file]` — force EPIC generation from plan

**Examples:**
```
/aid-plan                                    # auto-detect mode
/aid-plan "add user authentication"          # auto → brainstorm (topic, no spec)
/aid-plan brainstorm "migrate to PostgreSQL" # force brainstorm
/aid-plan write requirements.md              # write plan from spec file
/aid-plan write .aid-o/tasks/E-015.md        # write plan from EPIC draft
/aid-plan epic .aid-o/plans/P005-auth.md     # generate EPICs from plan
```

## Auto-Detection Logic

When mode is not specified, detect from input:

| Input | Detected Mode | Rationale |
|-------|--------------|-----------|
| No input | `brainstorm` | No context → explore interactively |
| Topic string (not a file) | `brainstorm` | Idea → needs exploration |
| Spec/requirements file | `write` | Has `type: spec` or no plan/epic markers |
| EPIC draft file | `write` | Has `type: epic` or `# EPIC:` header |
| Plan file | `epic` | Has `type: plan` or `# Plan:` header |

If detection is ambiguous, ask PM:
```
I found: {file_or_topic}

What would you like to do?
  (A) Brainstorm — explore the idea interactively
  (B) Write plan — create implementation plan from this input
  (C) Generate EPIC — create EPICs from this plan
```

## Mode: Brainstorm

Interactive 9-step brainstorming flow — collaborate with PM to explore an idea.

### Step 1: Context
1. If `.aid-o/` exists: read `config/project.yaml`, `work/active.md`, scan `plans/`
2. If topic provided: use as brainstorming seed; if empty: ask PM
3. Read `skills/brainstorming.md` for process rules
4. Detect PM's language → conversation follows PM's language
5. **Create interim document** — allocate plan ID (P{NNN} from counter.yaml) and write
   `.aid-o/work/interim-P{NNN}.md` with topic, project context, and PM's initial input.
   This doc persists full conversation detail across context window boundaries.

Present: `=== Step 1/9: Context ===` with project summary.

### Step 2: Analysis
Present structured analysis (understanding, dimensions, challenges, clarification areas).
Ask PM to confirm understanding. Output: `=== Step 2/9: Analysis ===`

### Step 3: Questions
Ask 3-7 clarifying questions ONE at a time (multiple choice preferred).
Cover: scope, users, constraints, patterns, success criteria. Output: `=== Step 3/9: Questions ===`

### Step 4: Approaches
Propose 2-3 approaches with pros/cons/effort/risk. State recommendation.
Ask PM to choose. Output: `=== Step 4/9: Approaches ===`

### Step 5: Design
Expand chosen approach: architecture, data model, API, implementation, testing, risks.
Output: `=== Step 5/9: Design ===`

### Step 6: Sections
Walk through design section by section, getting approval for each.
Track: `[x] approved`, `[ ] pending`. Output: `=== Step 6/9: Sections ===`

### Step 7: Approval
Present complete design summary. Ask PM for final approval (Y/N/X).
Output: `=== Step 7/9: Approval ===`

### Step 8: Document
Delegate to `skills/plan-writing.md` (Mode A — Post-Brainstorming).
Pass all approved sections. Plan written to `.aid-o/plans/P{NNN}-{topic}.md`.
Output: `=== Step 8/9: Document ===`

### Step 9: Plan Quality Review (CP1)
Dispatch verifier with `docs-review` focus on the written plan file.
Present findings to PM with full context (no auto-fix — design decisions).
Skip if `review_checkpoints.cp1_plan_review: false`.
Output:
```
=== Step 9/9: Review ===

Plan: .aid-o/plans/{plan_id}-{title}.md

Quality: {N} findings (Critical: {n}, High: {n}, Medium: {n})

{findings list with severity, area, recommendation}

Options:
  (A) Accept as-is → proceed to EPIC generation
  (B) Fix findings → apply recommendations, re-run review
  (C) Re-open brainstorming → interim doc preserved, focus on flagged sections
```

**Rules (hard failures if violated):**
1. ONE question at a time — never batch
2. Multiple choice preferred over open-ended
3. 2-3 approaches with recommendation — never single option
4. Section-by-section approval — never skip to final
5. Detail by default — specific file names, endpoints, data types
6. YAGNI — simplest solution meeting requirements
7. Follow ALL steps in order — no skipping

## Mode: Write Plan

Write an exhaustive implementation plan from specification or topic.

1. **Input resolution** — read spec file, detect format (EPIC/plan/free-form)
2. **Context** — read `config/project.yaml`, `work/active.md`, scan related plans
3. **Interim document** — allocate plan ID and create `.aid-o/work/interim-P{NNN}.md`
   with input, context, and analysis notes (same as brainstorm mode)
4. **Codebase analysis** — identify affected areas, read key files, note patterns
5. **Clarification** — max 5 questions if spec has gaps (skip if clear)
6. **Plan assembly** — write section by section per `skills/plan-writing.md` template
7. **Quality gates** — Forbidden Phrase Detection + Completeness Gate (16 checks)
8. **Write file** — write to `.aid-o/plans/P{NNN}-{topic}.md`, delete interim doc

Output: plan path, step count, quality gate results.

## Mode: Generate EPIC

Parse a Plan file, generate EPICs (one per phase), plan.json, run files, and queue entries.
All deterministic operations are bash pipeline scripts — LLM handles only dialog and validation.

1. **Validate** — confirm input is a Plan file (`type: plan` or `# Plan:` header)
2. **Analyze** — count phases, extract plan ID and title
3. **Queue mode** — ask PM: chain (A), separate (B), or custom (C) dependencies
4. **Run pipeline** — `bash {plugin_path}/scripts/aid-auto-pipeline.sh --plan <path> --queue-mode <mode>`
5. **Validate output** — check JSON manifest, verify all files created
6. **Report** — show created EPICs, queue status, next steps

**Next steps after EPIC generation:**
- `/aid-run` — start execution
- `/aid-run --auto` — start autonomous execution
- Review created files

## Reference Files

- `skills/brainstorming.md` — brainstorm process rules, principles, and context persistence (interim doc) protocol
- `skills/plan-writing.md` — plan writing quality gates and format
- `skills/planner.md` — dependency graph and parallel groups
- `{plugin_path}/scripts/aid-auto-pipeline.sh` — deterministic EPIC generation pipeline
- `defaults/templates/plan.md` — base plan template

## Important

- **Auto-detect by default** — mode selection only when explicitly specified or ambiguous
- **One output per mode** — brainstorm produces a plan; write produces a plan; epic produces EPICs + plan.json (interim docs are temporary)
- **Quality gates are mandatory** — plans not written until gates pass
- **Language split** — conversation in PM's language; documents per `config/project.yaml`
- **YAGNI** — never propose over-engineered solutions
- If PM aborts at any step → end gracefully, no final plan/EPIC files written (interim doc preserved for recovery)
- If `.aid-o/` missing → suggest `/aid-init` but proceed anyway
