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
Run the cross-section-review cycle first (see `skills/brainstorming.md` → "Cross-Section Validation
(Step 7)"): dispatch the verifier with focus=cross-section-review over the assembled approved
sections, ground-truth-verify its claims, and present the consolidated cross-section verdict
(drift / decision-propagation / completeness / dependency / effort). If the verdict has open
findings, apply targeted fixes to the affected sections first. Then present the complete design
summary and ask PM for final approval (Y/N/X).
Output: `=== Step 7/9: Approval ===`

### Step 8: Document
Delegate to `skills/plan-writing.md` (Mode A — Post-Brainstorming).
Pass all approved sections. Plan written to `.aid-o/plans/P{NNN}-{topic}.md`.
Output: `=== Step 8/9: Document ===`

### Step 9: Plan Quality Review (CP1)
Dispatch verifier with `docs-review` focus on the written plan file.
Present findings to PM with full context (no auto-fix — design decisions).
Skip if `review_checkpoints.cp1_plan_review: false`.

**Before `Agent()` call — log `verifier_dispatch_start` event:**
```bash
bash "$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh" log_event \
  "$timeline_file" \
  "verifier_dispatch_start" \
  agentId="aid-orchestrator:verifier" \
  focus="cp1" \
  step_n="null" \
  evidence_dir="$evidence_dir"
```

**After `Agent()` returns — log `verifier_dispatch_complete` event:**
```bash
bash "$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh" log_event \
  "$timeline_file" \
  "verifier_dispatch_complete" \
  agentId="aid-orchestrator:verifier" \
  focus="cp1" \
  step_n="null" \
  evidence_dir="$evidence_dir" \
  output_file="$evidence_dir/verifier-output-cp1.md"
```

`<dispatch-focus>` substitution rule for CP1: `focus="cp1"`, `step_n="null"`.
If `timeline_file` cannot be resolved (e.g., `state.yaml` not yet created
for a brand-new plan), `log_event` is a silent no-op — pipeline continues.

**Codebase grounding pass (mandatory, added v2.17.0).**
The verifier MUST perform a flat-list extraction + verification step in addition
to the standard plan-writing.md checks. P032 retrospective showed CP1 has a
systematic blind spot for *absence* — reviewer can detect when something
mentioned in the plan looks wrong, but cannot detect that a helper / file /
port / service the plan presumes exists in fact does not (5 PM-authorized
resolutions in P032 — C1 through C5 — were all of this kind).

Verifier dispatch prompt MUST include:
1. Extract a flat list from the plan of every named:
   - function / helper (e.g., `log_info`, `fsm_check_grandfather`)
   - file path under Files entries (Create / Modify / Rewrite / Test)
   - port (e.g., `8818`)
   - service / container name (e.g., `svc-mcp-tg-bot`)
   - external command (e.g., `yq`, `bats`)
   - env var (e.g., `AID_PLUGIN_PATH`)
   - **backlog ID** (e.g., `T-132`) — extract via regex `\bT-[0-9]+\b` from the
     entire plan body (whole-plan scan, no specific field — `related_backlog`
     does not exist in current plan template)
   - **test path** (e.g., `tests/integration/<file>`) from step Files entries
   - **DB field reference** (e.g., `Session.validation_warnings`) extracted via
     regex `[A-Z][a-zA-Z]+\.[a-z_]+` from plan body
   - **file removal claim** (e.g., "delete X", `must_not_exist: true`) from plan body
2. For each item, verify against real codebase / running infra:
   - Functions/helpers: `grep -rn "^<fn>()\|^function <fn>" plugins/`
   - File paths: `ls <path>` (or note "Create step <N>" if Files entry creates it)
   - Ports: `docker ps --format '{{.Ports}}' | grep <port>` — flag conflicts
   - Services: `docker ps --format '{{.Names}}'` — flag collisions
   - Commands: `command -v <cmd>`
   - Env vars: `grep -rn "<VAR_NAME>"` for declarations / fallback handling
   - **Backlog IDs:** `git log --since="24 hours ago" --grep="T-NNN" --all` — flag conflicts
   - **Test paths:** `find tests/ -type f \( -name "*.py" -o -name "*.ts" -o -name "*.bats" \) -name "*<basename>*"` — flag existing analogs (POSIX `find`, no `fd` dependency)
   - **DB fields:** `grep "<field>" <project>/db/models.py` — verify stored vs computed semantics
   - **File removal:** `ls <path>` — verify file currently exists
3. Mark each: VERIFIED (with path:line or docker output) or ABSENT (with note
   "to be created in Step N" — must map to a Create step in the plan). Specific
   semantics for the new categories:
   - **Backlog ID:** VERIFIED (free) or ABSENT (reserved by commit `<SHA>`)
   - **Test path:** VERIFIED (no conflict) or ABSENT (analog exists at `<path>`)
   - **DB field:** VERIFIED (matches claim) or ABSENT (claim mismatch — actual: `<stored|computed>`)
   - **File removal:** VERIFIED (exists, can be deleted) or ABSENT (file not present)
4. Plan with ABSENT items NOT mapped to a Create step → REVISE_REQUIRED.
   Specific REVISE_REQUIRED conditions for the new categories:
   - **Backlog ID ABSENT** → REVISE_REQUIRED unless plan explicitly states
     "T-NNN to be allocated at plan-write time" (acceptable for plan-allocation candidates)
   - **Test path ABSENT (analog exists)** → REVISE_REQUIRED — plan must choose
     consistent location OR explicit "supersedes <existing path>"
   - **DB field ABSENT (claim mismatch)** → REVISE_REQUIRED — plan must update
     claim to match definition (stored → re-validation, computed → automatic)
   - **File removal ABSENT (file missing)** → REVISE_REQUIRED — claim "delete"
     is meaningless, file already does not exist

**EVIDENCE REQUIREMENT (added v2.20.0 — addresses CP1 false-memory blind spot):**

Before the reviewer marks ANY item VERIFIED, the review output MUST capture
concrete evidence in this format:

```yaml
item: <name>
verdict: VERIFIED | ABSENT
command_run: <exact command>
output_excerpt: <path:line of match, or "0 matches" if grep returned empty>
```

Examples:

VALID evidence (ABSENT):
```yaml
item: setup_test_evidence_dir (function)
verdict: ABSENT
command_run: grep -rn "^setup_test_evidence_dir()" plugins/aid-orchestrator/scripts/tests/bats/
output_excerpt: (0 matches)
```
→ ABSENT verdict; must map to a Create step or REVISE_REQUIRED.

VALID evidence (VERIFIED):
```yaml
item: cmd_transition (function)
verdict: VERIFIED
command_run: grep -n "^cmd_transition()" plugins/aid-orchestrator/scripts/aid-fsm.sh
output_excerpt: aid-fsm.sh:849:cmd_transition()
```
→ VERIFIED at known location.

INVALID evidence (REJECTED, requires retry):
```yaml
item: setup_test_evidence_dir (function)
verdict: VERIFIED
# (no command_run, no output_excerpt — "from memory")
```
→ REJECTED — false-memory pattern. Auto-retry with explicit "EVIDENCE REQUIRED"
reminder; max 2 retries, then ESCALATION.

Empirical evidence: P035 C3 (2026-05-10) — plan cited
`setup_test_evidence_dir`, `setup_passing_execution_yaml`,
`setup_failing_execution_yaml` as "existing helpers"; none existed. CP1
review would have caught this if the reviewer had dispatched the mandatory
greps; without the evidence requirement, the reviewer wrote "VERIFIED" from
memory.

This requirement applies to ALL #17 sub-checks (functions, files, ports,
services, commands, env vars, CLI invocations) + 17a-d (per P035 Phase 2)
+ 17e (CLI invocation grounding) + #19 design defeat — Q1/Q2/Q3 answers
MUST cite plan path:line + codebase path:line as evidence.

Edge cases:
  • Item cannot be verified with current command (e.g., docker port but
    docker not running) → mark "PENDING — docker not running"; PM decides
    accept-as-trust or block.
  • Expensive command (~10s+) — orchestrator may batch greps into a single
    multi-pattern command.
  • Multiple matches per item → output_excerpt is first match + count
    "+N more matches".

This is in addition to (not replacing) the standard plan-writing.md
Forbidden Phrase + Completeness Gate (24 checks: 16 original + #17 + 17a-e + #18 + #19) verification.

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
7. **Quality gates** — Forbidden Phrase Detection + Completeness Gate (24 checks: 16 original + #17 + 17a-e + #18 + #19)
8. **Write file** — write to `.aid-o/plans/P{NNN}-{topic}.md`, delete interim doc
9. **Plan Quality Review (CP1)** — dispatch verifier with `docs-review` focus
   on the written plan file. **Identical to Mode: Brainstorm Step 9** —
   perform the codebase grounding pass (mandatory), include the EVIDENCE
   REQUIREMENT for every #17/17a-e/#19 verification, and save the review to
   `.aid-o/work/cp1-review-{plan_id}.md`. Activate #19 (Design Defeat
   Detection) when frontmatter `type: bug-fix` (per `skills/plan-writing.md`)
   or pre-screening heuristic matches.

   **Before `Agent()` call — log `verifier_dispatch_start` event:**
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh" log_event \
     "$timeline_file" \
     "verifier_dispatch_start" \
     agentId="aid-orchestrator:verifier" \
     focus="cp1" \
     step_n="null" \
     evidence_dir="$evidence_dir"
   ```

   **After `Agent()` returns — log `verifier_dispatch_complete` event:**
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/lib/aid-stage-log.sh" log_event \
     "$timeline_file" \
     "verifier_dispatch_complete" \
     agentId="aid-orchestrator:verifier" \
     focus="cp1" \
     step_n="null" \
     evidence_dir="$evidence_dir" \
     output_file="$evidence_dir/verifier-output-cp1.md"
   ```

   `<dispatch-focus>` substitution rule for CP1: `focus="cp1"`, `step_n="null"`.
   Same retry semantics as CP2/CP3 — if the verifier is re-dispatched
   (e.g., PM chose option B "Fix findings"), the start/complete pair is
   re-emitted; last pair is authoritative.

   Present PM with options:
     (A) Accept as-is → proceed to EPIC generation
     (B) Fix findings → apply recommendations, re-run review
     (C) Re-open spec — return to step 1 with annotated spec

   Skip if `review_checkpoints.cp1_plan_review: false` in
   `.aid-o/config/policies/review-checkpoints.yaml`.

Output: plan path, step count, quality gate results, CP1 review verdict.

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

### Streamlined Mode Advisory (P040, v2.25.0+)

`--streamlined` mode (P040 Component D) is appropriate for low-risk EPICs that
skip per-step CP2 in favor of a single integration-review checkpoint at
`done-advance`. These criteria are advisory — the planner surfaces them as a
recommendation; the PM decides whether to pass `--streamlined` to `/aid-run`.

An EPIC is a candidate for streamlined mode when ALL of the following hold:

- **0 logic-changing files** — only docs, config, fixtures, or pure data edits;
  no changes to control-flow or business logic.
- **`< 5` files modified** — small, reviewable blast radius.
- **`< 100` LOC delta** — net additions + deletions stay under one screen of review.
- **0 security-sensitive paths** — nothing under auth, crypto, secrets, payment,
  or other paths flagged `security_sensitive` in project config.

When any criterion is exceeded, prefer full mode so per-step CP2 verification
runs. Streamlined mode never relaxes the integration-review, orphan-dispatch, or
abandoned-run enforcement at `done-advance`.


**Last Updated:** 2026-05-31
