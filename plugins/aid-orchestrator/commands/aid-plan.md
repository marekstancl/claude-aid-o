---
name: aid-plan
description: Plan a task — brainstorm, write plan, or generate EPIC (auto-detected or forced)
user_invocable: true
---

Unified planning command — merges brainstorming, plan writing, and EPIC generation into a single entry point with auto-detection.

## Usage

> **Resolve `$AID_PLUGIN_PATH` before running anything below.** Nothing sets it
> for you — not the plugin, not the workspace, not your shell. Every command
> here would otherwise fail with "file not found", and the reader is left to
> work the path out (which is how this survived unnoticed: a model usually
> does). The workspace records it, and this is the same source
> `commands/aid-run.md` §PRE-FLIGHT already uses:
>
> ```bash
> _aid_installed="$(jq -r '.plugins["aid-orchestrator@claude-aid-o"][0].version' \
>                   ~/.claude/plugins/installed_plugins.json 2>/dev/null)"
> AID_PLUGIN_PATH="$(yq -r '.plugin_path' "$(git rev-parse --show-toplevel)/.aid-o/config/plugin.yaml")"
> # The workspace PINS a version and old copies stay on disk, so "the file is
> # there" is not "the file is current": on 2026-08-24 a session ran its first
> # commands against 2.89.1 while 2.90.0 was the installed one. Compare, do not
> # assume.
> [[ -n "$_aid_installed" && "$AID_PLUGIN_PATH" != *"/$_aid_installed" ]] \
>   && AID_PLUGIN_PATH="$HOME/.claude/plugins/cache/claude-aid-o/aid-orchestrator/$_aid_installed"
> test -f "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" || echo "no plugin at $AID_PLUGIN_PATH — run /aid-init"
> ```


```
/aid-plan [mode] [input]
```

**Modes:**
- `/aid-plan` — auto-detect: brainstorm if unclear, write plan if spec provided, generate EPIC if plan exists
- `/aid-plan brainstorm [topic]` — force 8-step interactive brainstorm
- `/aid-plan write [spec-file]` — force plan writing from specification
- `/aid-plan epic [plan-file]` — force EPIC generation from plan

Whichever mode runs, a `plan_branch` plan's LAST PM-facing turn is the one
described in **"Plan-final / close boundary"** below — a rendered card and page,
never a hand-written file listing. Read that section before closing a plan.

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

## Working while another plan is live

Planning a new plan never has to wait for another one. Each plan implements in
its own git worktree under `.aid-worktrees/plan-<id>`, so an active plan does
not hold the PM's checkout, and the PM's own uncommitted work does not block
plan creation. Say so plainly rather than asking the PM to stash or wait.

Brainstorming and generation get their own copies the same way —
`.aid-worktrees/brainstorm-<id>` and `.aid-worktrees/generation-<id>`, both
from `plan-scratch` (below). They are scratch checkouts: created before any
plan-state exists, recorded nowhere, released by whoever asked for them. What
they isolate is the TREE. State does not fork and is not meant to: `.aid-o/`
resolves to the primary checkout from every tree, so two streams share one
plan-id counter, one run history and one evidence tree.

**Orient before Step 1.** Four reads, all cheap:

```bash
git worktree list                       # every tree: the PM's, and one per active plan
ls .aid-o/work/plan-state/*/plan-state.yaml 2>/dev/null   # which plans exist and their phase
cat .aid-o/work/active-runs.json 2>/dev/null              # which EPICs are actually running
cat "${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}/latest.json" 2>/dev/null  # last nightly result
```

`/aid-status`'s `plan-rows`, `next-epic` and `nightly-line` recipes render
exactly this; reuse them rather than writing a second reader.

**The nightly read NEVER blocks planning.** The merge path runs T0+T1 only, so
the full portfolio's verdict arrives that night rather than at the gate — which
means a red night is something a PM should hear once, at the start, not
something that stops a plan being written. Report it in one line (the same
shape `/aid-status` renders) and carry on. No artifact at all: say nothing.

**What to tell the PM, by what you find:**

| What the reads show | What to say and do |
|---|---|
| No plan-state files, no `.aid-worktrees/` | Nothing else is running. Proceed silently — do not narrate an empty check. |
| Another plan active, its worktree present | Name it and its phase, say this plan can be written and generated anyway, proceed. |
| PM's checkout has uncommitted work | Irrelevant to planning and to `plan-start`. Do not ask them to clean it. |
| The plan file is not committed on `main` | `plan-start --plan-file` commits it for you (only that path, index untouched) when the checkout is ON `main`; from another branch it refuses and says so — do not commit plans by hand as a ritual. |
| A plan records `worktree_path` but the directory is gone | Name it and the repair — `aid-plan-fsm.sh plan-state <id> --recreate-worktree --reason "<why>"` — then continue; a broken sibling does not block a new plan. |
| A worktree directory exists that `git worktree list` does not know | Leftover from a crash plus a manual prune. Name it and `git worktree prune`; do not delete a directory you did not create. |
| `git worktree list` shows trees OUTSIDE `.aid-worktrees/` | Not AID's. Someone else's branch checkout, another session, a sibling clone. AID neither manages nor tears these down. Name them once so the PM knows what else is checked out, note which branch each is on, and leave them alone — in particular, a branch checked out there cannot be checked out again, which is the one way they can make a later `plan-start` or `--recreate-worktree` fail. |
| Three or more streams already active | Say how many and which, and ask whether to add another — this is a PM capacity question, not a technical limit. |
| The nightly artifact is red, stale or unreadable | One line, then continue. Naming it is the whole obligation: planning is never blocked by a test result, and a red night the PM never hears about is the failure this read exists to prevent. |

**Generating AND starting both work.** A newly generated plan's EPICs are
registered (`epic-start`) and initialised inside that plan's own worktree, so a
second stream can be taken all the way to a queued, READY EPIC while the first
one implements — with the PM's checkout dirty and its HEAD unmoved throughout.
What still serializes is the CONTROLLER, not the streams: one session drives one
run at a time, so two streams progress by alternating or from two sessions —
inside a run, a wave may dispatch several agents at once (`pipeline.md §4`).

## Mode: Brainstorm

Interactive 9-step brainstorming flow — collaborate with PM to explore an idea.

### Step 1: Context
0. **Orient on the other streams first** — see "Working while another plan is
   live" below. Run the four reads, and if anything is active, tell the PM
   what is running and that this plan can proceed anyway. Never ask them to
   clean up or wait without a reason from those reads. The fourth read is the
   nightly result: report it in one line if there is one, and never let it
   block planning.
1. If `.aid-o/` exists: read `config/project.yaml`, `work/active.md` (generated index of active streams — read-only, never hand-write it), scan `plans/`
2. If topic provided: use as brainstorming seed; if empty: ask PM
3. Read `skills/brainstorming.md` for process rules
4. Detect PM's language → conversation follows PM's language
5. **Create interim document** — allocate plan ID via `bash {plugin_path}/scripts/aid-fsm.sh alloc plan-id`
   (locked; prints the new P{NNN} — never hand-edit counter.yaml) and write
   `.aid-o/work/interim-P{NNN}.md` with topic, project context, and PM's initial input.
   This doc persists full conversation detail across context window boundaries.
6. **Take this brainstorm's own working copy** — with the ID in hand:

   ```bash
   bash {plugin_path}/scripts/aid-plan-fsm.sh plan-scratch P{NNN} --phase brainstorm
   ```

   It prints the directory this brainstorm runs in; `cd` there and read code
   from it for the rest of the flow. It prints the primary checkout instead
   (with a warning saying why) when git cannot hand out a second tree — that
   is a working outcome, not a blocker, so never stop on it. State is not
   affected either way: `.aid-o/` always resolves to the primary checkout, so
   the interim document, the counter and every later run stay where they were.
   Release it when the plan is written: same command with `--release`.

Present: `=== Step 1/9: Context ===` with project summary.

### Step 2: Analysis
Present structured analysis (understanding, dimensions, challenges, clarification areas).
Ask PM to confirm understanding. Output: `=== Step 2/9: Analysis ===`

### Step 2a: Vision (roadmap and multi-plan work only)
Register the run and its scope — this also creates the brainstorm's own working
copy and prints it as `workdir:`:

```bash
bash {plugin_path}/scripts/aid-brainstorm-state.sh init P{NNN} --scope roadmap|multi_plan|user_visible|single_plan
```

`user_visible` is anything that changes behaviour a user meets — a flag, an
output format, a message. `single_plan` is only for work nobody outside the code
notices, a refactor or a tidy-up. Choosing `single_plan` for user-visible work is
how the vision quietly stops being owed (observed live on 2026-08-24, when the
flow filed a new CLI flag as `single_plan`).

For `single_plan` the step is skipped and the skip is recorded; say so in one
line and go to Step 3. Otherwise draft the vision as thesis + test (see
`skills/brainstorming.md` → Vision Step), propose it, and ask the PM to approve:

```bash
bash {plugin_path}/scripts/aid-brainstorm-state.sh vision-propose P{NNN} --file <vision.md>
bash {plugin_path}/scripts/aid-brainstorm-state.sh vision-approve P{NNN}   # after the PM says yes
```

`vision-propose` refuses a point with no test and names it — fix those before
asking the PM. If the PM declines, go back to Step 2; never continue without a
vision. Output: `=== Step 2a/9: Vision ===`

### Step 3: The single planned stop
This is the ONE place the flow waits for the PM. Present three things in one
message (see `skills/brainstorming.md` → "The Single Planned Stop"):

1. **How you understood the brief** — two sections, `Ověřeno` (each claim with
   the file and place it was checked in) and `Předpokládám`. No third section.
2. **The vision** as thesis + test, when this run owes one:
   ```bash
   bash {plugin_path}/scripts/aid-brainstorm-state.sh show P{NNN}   # vision_required?
   ```
3. **Every question at once**, as a decision batch. Only the five kinds in
   `skills/brainstorming.md` MUST 15 — what it is for, who for, risk accepted,
   backwards compatibility, anything irreversible. Anything else you answer
   yourself.

If the PM leaves part of it unanswered, ask again for those parts only.
**Never turn silence into an assumption** (MUST 17).
Output: `=== Step 3/9: Zastavení ===`

### Steps 4–7: The autonomous part
No PM here. Approaches, design, section validation and the opponent run without
stopping; agreements go straight into the interim, disagreements are collected
for the result.

```bash
rc=0
bash {plugin_path}/scripts/lib/aid-brainstorm-opponent.sh \
  P{NNN} <brief.md> .aid-o/work/brainstorm/P{NNN} || rc=$?
# rc=0 answered · rc=3 not reached → PRESENT IT AS A DECISION (exception 1),
# capped at three attempts per run · rc=1 the vision gate refused, or nothing
# could be recorded — stop and fix that.
```

The opponent gets **the brief**, not your conclusions: handing it your positions
anchors it, and an opponent that agrees because it was told what to think is a
second opinion in name only.

Section validation stays (`section-review` critic + ground-truth re-verification
by the author, MUST 5); what is gone is asking the PM to sign off each one.

**The only other interruption** is a fundamental unknown no assumption can
safely cover. Say that it IS an exception and why.
Output: `=== Steps 4-7/9: Autonomně ===`

### Step 7a: Scope list — the PM sees the work before it is written
After the interim is written and BEFORE the plan is:

- **What the plan will deliver** — bullets, plain language, no jargon. If it
  runs past ten, that is a signal the plan is too big; say so.
- **What it deliberately leaves out** — this half matters more. Scope is checked
  at its EDGES; a list of contents alone reads as complete whatever is missing
  from it.

Goes in the chat, not on a page: it is a checkpoint answered on the spot, and
the artifact belongs to the finished plan (step 8p).

The PM accepts it, corrects it, or refuses it. **Refused → back to the stop in
Step 3; the plan is not written.** Something added → it goes back through the
autonomous part, it is not glued on.
Output: `=== Step 7a/9: Rozsah ===`

**Enforcement, stated honestly:** this is an INSTRUCTION. Nothing fails if a
session writes the plan without showing the list first — the same weakest form
`plan_artifact_rendered` had before the hook layer gave it a mechanism, and it
is registered at that strength rather than described as more.

### Step 8: Document
Delegate to `skills/plan-writing.md` (Mode A — Post-Brainstorming).
Pass all approved sections. Plan written to `.aid-o/plans/P{NNN}-{topic}.md`.
Output: `=== Step 8/9: Document ===`

**Files-shape lint (automatic — run BEFORE CP1, immediately after the plan is
written).** This is early feedback, not the enforcement of record: the hard
gate is the deterministic pre-flight inside `aid-plan-to-epic.sh` (which CANNOT
be skipped). Run:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh" ".aid-o/plans/P{NNN}-{topic}.md"
```

If it exits non-zero (ERROR-tier, or STRICT-tier on a `lifecycle_strict` plan),
fix the exact Files entries it names — per the grammar in `skills/plan-writing.md`
— and re-run until it passes, BEFORE proceeding to CP1. Do not hand a plan with
blocking Files-shape violations to CP1 or to EPIC generation. CP1 (Step 9) then
INCLUDES the lint's output in its review context but does not replace it.

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
If `timeline_file` cannot be resolved (e.g., `fsm-state.yaml` not yet created
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
Forbidden Phrase + Completeness Gate (28 checks: 16 original + #17 + 17a-e + #18 + #19 + 20a-c + #21) verification.

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
2. **Context** — read `config/project.yaml`, `work/active.md` (generated index — read-only), scan related plans
3. **Interim document** — allocate plan ID and create `.aid-o/work/interim-P{NNN}.md`
   with input, context, and analysis notes (same as brainstorm mode)
4. **Codebase analysis** — identify affected areas, read key files, note patterns
5. **Clarification** — max 5 questions if spec has gaps (skip if clear)
6. **Plan assembly** — write section by section per `skills/plan-writing.md` template
7. **Quality gates** — Forbidden Phrase Detection + Completeness Gate (28 checks: 16 original + #17 + 17a-e + #18 + #19 + 20a-c + #21; eight are band-scoped — see `skills/plan-writing.md`)
8. **Write file** — write to `.aid-o/plans/P{NNN}-{topic}.md`, delete interim doc
8p. **PM page (required, right after the write)** — render the plan's summary
    and show the PM that page, not the plan:
    ```bash
    source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-summary.sh"
    aid_plan_summary_render ".aid-o/plans/P{NNN}-{topic}.md" \
      ".aid-o/work/evidence/P{NNN}/plan-summary-artifact.html"
    ```
    Publish the rendered body with the Artifact tool (the renderer never
    publishes — same boundary as `lib/aid-plan-close-summary.sh`). Every figure
    on the page is counted from the plan, so do NOT restate it in prose and do
    NOT write a summary section into the plan itself — `plan-writing.md` MUST
    rule 17 forbids it and `aid-plan-lint.sh` reports it.

    **Enforcement, stated honestly:** this is an INSTRUCTION, the weakest form
    there is — nothing fails if a session skips it. The mechanism that will
    make it hard is the hook layer of Plan 3 (a `Stop` hook refusing to close a
    turn that wrote a plan without rendering its page). Until then it is a
    deliberately accepted risk, registered as `plan_artifact_rendered` with
    `severity: advisory` in the enforcement registry.
8a. **Files-shape lint (automatic, before CP1)** — run
    `bash "$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh" ".aid-o/plans/P{NNN}-{topic}.md"`.
    On a non-zero exit, fix the exact Files entries it names (per the grammar in
    `skills/plan-writing.md`) and re-run until it passes, BEFORE CP1. Early
    feedback only — the hard gate is the deterministic pre-flight in
    `aid-plan-to-epic.sh`, which cannot be skipped.
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

Parse a Plan file, generate every EPIC and plan.json first, verify one complete
generation receipt, then create run files/FSM state and queue entries.
All deterministic operations are bash pipeline scripts — LLM handles only dialog and validation.

0. **Take this generation's own working copy** — generation COMMITS (the plan,
   the lifecycle manifest, whatever EPIC files the project tracks), so two
   generations in one checkout collide on one index and one HEAD:

   ```bash
   bash {plugin_path}/scripts/aid-plan-fsm.sh plan-scratch <plan_id> --phase generation
   ```

   `cd` to what it prints and run the pipeline from there. A warning plus the
   primary checkout is a valid answer — generation proceeds, only a second
   concurrent stream is unsafe until the copy exists. Release it after the
   transaction completes (`--release`); a copy holding uncommitted work is
   refused rather than discarded.
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

### Generation is one transaction

Generation for a plan is a single transaction, not N independent phase runs.
Two files under `.aid-o/work/evidence/<plan_id>/generation/` hold it together:

| File | What it is |
|------|-----------|
| `generation-authority.json` | The CP1 decision, made **once per plan** before any output exists, sealed to the exact plan bytes, target head and phase set. Every phase verifies it instead of re-running the gate. |
| `transaction.json` | Identity plus one record per phase. Phase status is **derived** by re-hashing the recorded outputs and reading queue membership — the files and the queue are the truth. |

**CP1 blocked the plan.** Generation stops before anything is created. The
refusal carries one of exactly two AID-owned labels, and the gate's own output
follows it verbatim:

| Label | What it means | What to do |
|-------|---------------|-----------|
| `aid_generation_force_required:` | The failure is a CP1 condition verdict — evidence, adjudicator, C0 review or ledger. A PM may deliberately waive it. | Fix the conditions, or run the force command the label prints (it already carries your `--plan` and `--queue-mode`). |
| `aid_cp1_blocked:` | The failure is one `--force` cannot cover — the gate was mis-invoked, hit an I/O error, or the plan's own identity is broken. The hard condition is named first. | Fix the named condition. `--force` is **refused in the same place** on this class, not merely unadvertised: it seals no authority, writes no waiver, and says so by name. |

```bash
bash {plugin_path}/scripts/aid-auto-pipeline.sh --plan <path> --queue-mode <mode> --force --reason "<at least 20 characters>"
```

The force is invocation-scoped and audited three ways (timeline event,
cross-plan audit log, HEAD-bound waiver artifact). The CP1 evidence on disk is
never rewritten as clean. A `--force` on a plan that passes anyway is recorded
as unused and writes no waiver.

**A run was interrupted.** Just rerun the same command. Phases whose outputs
still verify are skipped, only what fails verification is regenerated, ids stay
identical, and an EPIC already in the queue is a verified idempotent skip rather
than a duplicate error.

**The plan changed.** A different identity (plan bytes, target head, phase
count, or derivation version) is never mixed with the old one:

- the previous transaction was **complete** → it rolls over automatically, the
  finished pair is archived to `.completed-<epoch>` siblings, and a fresh
  transaction starts;
- the previous transaction was **incomplete** → generation refuses, naming both
  identities. Archive it deliberately first:

```bash
bash {plugin_path}/scripts/aid-auto-pipeline.sh supersede-generation \
  --plan <path> --reason "<at least 20 characters>"
```

`supersede-generation` archives the authority/transaction pair to
`.superseded-<epoch>` siblings, writes the audit record, and prints what the
abandoned generation had already produced. **It deletes nothing** — removing
EPIC files, branches or queue entries stays with `plan-rollback` and the
queue-removal path.

It takes the same per-plan generation lock the pipeline takes, so it refuses
by name (`a generation is in progress for <plan_id> (holder pid N)`) while a
generation for that plan is running, and archives nothing. It also refuses
when the supersession cannot be recorded — the audit trail is what makes this
command accountable, so an unrecordable archive is not performed.

## CP1 Mode Selection

Risk classification runs automatically during CP1 before EPIC generation. It applies to any plan processed by `/aid-plan`.

### Band classification

The plan's **ceremony band** is classified from the paths its steps DECLARE in
their `**Files:**` blocks — never from prose anywhere in the document. Ask the
gate; do not re-derive it:

```bash
band="$(bash "$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh" \
        --plan "$PLAN_FILE" --project-root "$PROJECT_ROOT" --classify-only)"
```

| Band | What the plan declares it touches | What runs |
|---|---|---|
| `full` | decision machinery: state machines, gate runner, generation chain, release boundary, `skills/plan-writing.md`, auth, migrations, dependency manifests | CP1-light + CP1-deep (3 lenses + 6 C0 lenses + adjudicator) + the C0 cross-provider loop |
| `medium` | the DATA those decisions read: policies, schemas, templates, machine-read config, CI | CP1-light + CP1-deep (3 lenses + adjudicator); **no C0 lenses, no cross-provider loop** |
| `light` | everything else — documentation, help, commands, skills, tests, ordinary feature code | CP1-light only — **dispatch no lens at all** |

Ordinary code being `light` surprises people, so it is worth saying plainly:
the band measures whose DECISIONS a plan changes, not whether it changes code.
Code is reviewed where reviewing code works — per step at CP2/CP3, against a
real diff. A plan-time lens panel earns its cost on the machinery no later
checkpoint gets a second chance at.

Frontmatter `risk: high` raises a band to `full`. Nothing lowers a band except
changing what the plan declares it will touch. A plan that declares no file, a
missing or unparseable path map (`defaults/policies/risk-paths.yaml`) and a host
without `yq` all classify as `full` — fail-closed, with no prose-guessing
fallback.

What each band REQUIRES as evidence is a table, not prose:
`defaults/policies/review-checkpoints.yaml` → `review_checkpoints.ceremony_bands`.
`aid-cp1-gate.sh` reads that same table, so a band you dispatch for and a band
the gate checks for can never be two different things.

### CP1-light (every band)

Runs the standard `plan-writing.md` completeness checklist. If no
`REVISE_REQUIRED` findings, proceed to EPIC generation. For `light` this is the
whole of CP1.

### CP1-deep (bands `full` and `medium`)

Extends CP1-light with parallel review lenses and an adjudicator: 9 lenses for
`full` (L1/L2/L3 blocking + 6 C0 observe), the 3 L1/L2/L3 lenses for `medium`.
The 4 L1/L2/L3+adjudicator evidence files must exist before EPIC generation is
allowed; the C0 lens FINDINGS are observe-only (E4). One C0 lens file is
nevertheless required to exist in `full` — `c0-lens-reuse_evidence.md` (P085):
what it reports stays advisory, that it ran does not.

**Flow:**

```
Plan input → classify band (--classify-only) → CP1-light OR CP1-deep

CP1-light:
  → run plan-writing.md checklist
  → if REVISE_REQUIRED: revise, retry
  → if pass: generate EPIC

CP1-deep:
  → run plan-writing.md checklist (same as light)
  → classify the band from the plan's declared Files (aid-cp1-gate.sh --classify-only)
  → dispatch the lenses the band owes, in parallel (full: all 9; medium: L1/L2/L3 only;
    light: none — see review-checkpoint-contracts.md §CP1-deep and §C0 Semantic Lenses):
      L1 behavior:                  request→branch→sink flow, undeclared outcomes, user-visible regressions, edge cases
      L2 feasibility:               touched files, output contracts, parser/producer ordering, implementation feasibility
      L3 enforcement:               gitignored artifacts, remote CI visibility, test runner execution, release/CI breakage
      C0 reuse_compat:              incompatible component reuse — output to c0-lens-reuse_compat.md
      C0 reuse_evidence:            was each founding step's reuse search WIDE enough (the half the lint's replay cannot reach) — output to c0-lens-reuse_evidence.md
      C0 planned_call_feasibility:  calls to outputs/APIs that the plan doesn't clearly produce — output to c0-lens-planned_call_feasibility.md
      C0 dep_api_grounding:         dependency API mismatch against actual version/interface — output to c0-lens-dep_api_grounding.md
      C0 idempotency_matrix:        non-idempotent mutations against at-most-once AC — output to c0-lens-idempotency_matrix.md
      C0 authority_runtime_matrix:  mutations crossing ownership/tenant boundary — output to c0-lens-authority_runtime_matrix.md
  → L1/L2/L3 each produce: stop_rule_blockers[] (required field), findings[], confidence: high|medium|low
  → C0 lenses each produce: stop_rule_blockers[] (advisory/observe in E4), findings[], confidence: high|medium|low
  → the reuse_evidence dispatch is given two inputs the other lenses do not need, both quoted VERBATIM:
      (a) every founding step's **Reuse check:** field, exactly as written — the lens judges the search, so a paraphrase is not the artifact
      (b) the standards this plan's paths bind — RUN the derivation and paste its output, do not describe it:
          bash "$AID_PLUGIN_PATH/scripts/lib/aid-standards-map.sh" --derive "$PLAN_FILE"
          Exit 1 = the project has no standards map, so this input legitimately does not exist.
          Exit 2 = a map is configured but unreadable; pass that fact to the lens rather than an empty list.
      If either input is unavailable, the lens still runs and RECORDS that the input was missing — it never guesses one.
  → adjudicator reviews all 9 lenses: accepts blocker only if it has command/artifact + file:line evidence (L1/L2/L3 blocking; C0 advisory — see review-checkpoint-contracts.md §C0 Adjudicator Addendum)
  → adjudicator produces: verdict: pass|fail|revise (required field), accepted_blockers[], rejected_blockers[]
  → if verdict=revise AND revision_count < 2: auto-revise plan, re-run CP1-deep (max 2 iterations)
  → if revision_count >= 2 AND accepted_blockers survive: escalate to PM (not pass)
  → if band=full AND verdict=pass: run the C0 cross-provider Codex review loop (below) —
    MUST complete before EPIC generation, independent of the L1/L2/L3 adjudicator loop above
  → if verdict=pass AND accepted_blockers=[] AND (band is not full OR the C0 review loop exited clean): generate EPIC
```

### C0 Cross-Provider Review Loop (band `full` only)

After the L1/L2/L3 adjudicator produces `verdict: pass` for a `full`-band plan, a
SEPARATE, mandatory cross-provider (Codex) pass over the FINAL plan runs before
EPIC generation is allowed — see `review-checkpoint-contracts.md` §"C0
Cross-Provider Plan Review — Adjudicator MUST-Consume Contract" for the full
contract this loop implements, and `pipeline.md` §6a for the DONE-phase C3
fix→reverify loop this one mirrors at plan level (same bounded-loop shape,
same "not a loop iteration" carve-out, same fingerprint-survives vs.
conflicting-findings escalation split). `medium` and `light` plans skip this
loop entirely, and with it the ledger the loop initialises; a PM marking a plan
`risk: high` brings it into scope from that point on.

**First pass:**
```bash
bash "$AID_PLUGIN_PATH/scripts/lib/aid-cp1-ledger.sh" init --pre-enforcement \
  --project-root "$PROJECT_ROOT" "$PLAN_ID"   # or plain 'init' for a provably new plan
bash "$AID_PLUGIN_PATH/scripts/lib/aid-c0-plan-review.sh" build-manifest \
  "$PLAN_FILE" "$PLAN_EVIDENCE_ROOT"
bash "$AID_PLUGIN_PATH/scripts/lib/aid-c0-plan-review.sh" dispatch "$PLAN_EVIDENCE_ROOT"
bash "$AID_PLUGIN_PATH/scripts/lib/aid-c0-plan-review.sh" verify   "$PLAN_EVIDENCE_ROOT"
```
`PLAN_EVIDENCE_ROOT` is `.aid-o/work/evidence/<plan_id>/` (one level above
`cp1-deep/` — the same root `lib/aid-c0-plan-review.sh` and `aid-cp1-gate.sh` both
read). `init` runs once per plan, before the first C0 dispatch of its
lifetime.

**The ledger `increment` is now MECHANICAL, not a step the orchestrator
performs.** `dispatch` itself calls `aid-cp1-ledger.sh increment` internally
— the orchestrator does NOT need (and should NOT) call `increment`
separately. The gate is TWO conditions, both required: (1) the dispatch was
a genuine, well-formed transport-level exchange (`outcome == "dispatched"`
in `c0/codex/c0-dispatch.json` — Codex's CLI stream itself was valid), AND
(2) the WRITTEN `c0-plan-review.json`'s own `review_status` is NOT
`"unverifiable"`. Condition (2) exists because `outcome == "dispatched"`
alone says nothing about whether the response CONTENT then passed
validation — a transport-genuine-but-content-invalid response (a hash or
head mismatch, a malformed/C3-shaped reply, etc.) still reaches
`outcome == "dispatched"` but must NOT consume a budget slot, matching
"Not a loop iteration" below exactly (which groups content-invalid
responses alongside true transport failures for C0, unlike C3's sibling
EPIC 6 system, which evolved a deliberately different, more nuanced rule
for its own case). If the ledger increment itself fails (missing/corrupt/
exhausted) once BOTH conditions hold, `dispatch` fails closed too —
`c0-plan-review.json` is overwritten to report `status: unverifiable` even
if Codex's own response was otherwise clean, and `verify` will correctly
refuse to bless it. This closes a live DONE-review finding (E-065-7_7's own
2nd audit dispatch, refined across two follow-up rounds after the first fix
attempt's gate proved too broad): the increment used to be prose-only, so a
session that didn't perfectly follow this instruction could dispatch
indefinitely with the ledger never actually advancing.

**Not a loop iteration.** `dispatch` returning `unavailable`/`rate_limited`/
`timeout`/`invalid_output` (Codex never genuinely dispatched a well-formed,
raw-bound response) yields `review_status: unverifiable`. This blocks
EPIC generation for the `full`-band plan pending a PM decision, but it is NOT a
loop iteration — do NOT call `aid-cp1-ledger.sh increment` for it, and do not
treat it as consuming one of the 4 rechecks. Retry it freely (transient
Codex unavailability), exactly like C3's own carve-out.

**A genuine dispatch with blocking findings enters the bounded loop** (while
blocking AND `cp1-ledger.sh check-budget` reports budget available,
the shipped budget of 5 sessions, documented in `review-checkpoints.yaml`
→ `cp1_codex_review.max_rechecks: 4`, whose mechanical authority is
`MAX_ATTEMPTS` in `scripts/lib/aid-cp1-ledger.sh` — that YAML key is
documentation only and no consumer reads it).
**Caution on `check-budget`'s meaning after an override-authorized attempt:**
once `attempts > max` via a PM-override-claimed increment (see below),
`check-budget` reports `available` again — but this describes the CURRENT
tip's attempt as retrospectively authorized (what the gate needs), NOT a
standing "you may loop again" grant. The override was single-use and is
already consumed; if THIS attempt is still blocking, do not re-enter the
loop body below without confirming a FRESH override is present first —
`aid-cp1-ledger.sh increment` will correctly reject a further attempt with
no fresh artifact, but check that before spending a real gate-fixer +
Codex dispatch on an attempt that will fail closed anyway.
1. Dispatch gate-fixer (S/M effort) or implementer (L effort) to revise the
   SPECIFIC accepted/blocking finding(s) by `fingerprint` — a targeted plan
   revision, never a general rewrite — producing a new commit.
   - Revision fails, or produces no diff (plan file unchanged) → exit to PM
     escalation immediately (cannot make progress / would re-review the
     identical plan text).
2. Re-run the C0 review on the revised plan — a fresh `reviewed_plan_hash`
   and a genuinely new Codex session, never a reuse of the prior attempt:
   ```bash
   bash "$AID_PLUGIN_PATH/scripts/lib/aid-c0-plan-review.sh" build-manifest \
     "$PLAN_FILE" "$PLAN_EVIDENCE_ROOT"        # new reviewed_plan_hash
   bash "$AID_PLUGIN_PATH/scripts/lib/aid-c0-plan-review.sh" dispatch "$PLAN_EVIDENCE_ROOT"
   bash "$AID_PLUGIN_PATH/scripts/lib/aid-c0-plan-review.sh" verify   "$PLAN_EVIDENCE_ROOT"
   ```
   `dispatch` already records this attempt on the ledger internally (see
   "The ledger `increment` is now MECHANICAL" above) — no separate step
   needed here. A re-run with an UNCHANGED plan hash is a no-op inside
   `increment` (the ledger never advances on it) — this is what makes "each
   recheck = a new plan hash" mechanically enforced, not just documented.
   Once the ledger is genuinely exhausted (`attempts >= max`), `increment`
   itself now refuses to advance further on a new hash too — not just
   `check-budget`'s read-only report.
3. Re-evaluate the new `c0-plan-review.json`:
   - Clean (`review_status: pass`, `blocking_findings: false`) → exit the
     loop, proceed to EPIC generation.
   - Still blocking AND the SAME finding `fingerprint` survived this
     recheck (the revision didn't actually fix it) → **PM escalation**
     immediately — do not spend the remaining budget on a non-converging
     fix. This is mechanically decidable (fingerprints are deterministic
     content hashes over the finding); compare this attempt's blocking
     fingerprints against the immediately-prior dispatched attempt's.
   - Still blocking AND the findings are mutually conflicting (a judgment
     call this loop cannot make mechanically) → **PM escalation**
     immediately; durably record this as the escalation reason (never leave
     it as unrecorded prose — a later stray revision attempt must not
     silently reopen the loop).
   - Still blocking, fingerprint(s) differ, findings don't conflict (the
     revision introduced a NEW blocking finding — counts against this SAME
     budget) → loop again if budget remains, else fall through below.

**Exit conditions (exactly one applies):**
- **Clean** → proceed to EPIC generation as normal.
- **`aid-cp1-ledger.sh check-budget` reports `exhausted`** (initial review +
  4 rechecks = 5 Codex runs consumed, still blocking) →
  **`PM_ESCALATION_REQUIRED`**: execution halts, surfaced to the PM;
  `aid-cp1-gate.sh` refuses EPIC generation. A 6th review run requires an
  explicit PM-escalation override artifact (below) — never automatic
  re-entry into this loop.
- **Same fingerprint survives a recheck, or conflicting findings** (see step
  4 above) → **`PM_ESCALATION_REQUIRED`** immediately, regardless of
  remaining budget.

**PM-escalation override.** When the PM explicitly authorizes proceeding past
a blocked state (budget exhausted, unverifiable persisting, or a judgment
call the loop cannot resolve), write:
`.aid-o/work/evidence/<plan_id>/cp1-pm-escalation-override.json` with a
non-empty `pm_ref` field (>= 20 characters — same reasoned-override
convention as this project's other `*_FORCE_*` escalation overrides,
recording who/what/why). `aid-cp1-gate.sh` checks for this artifact only
AFTER determining the C0 review and/or ledger budget check actually failed
— a present override is never touched on a clean pass, so it stays
available for a run that genuinely needs it. Only once a bypass is
genuinely required does the gate claim it, renaming it to a
`.consumed-<epoch>` sibling.

**Which loop this override belongs to.** It authorizes exactly one more
GATE INVOCATION (covering whichever of the two checks failed in that same
run), never a standing bypass — and during PLAN REVIEW that is exactly the
ledger/recheck loop described above, unchanged. **EPIC GENERATION is a
different consumer:** `aid-auto-pipeline.sh` runs the gate once per plan
and seals the result in `generation-authority.json`, which every phase
verifies, so one authority covers the whole generation and the
`.consumed-<epoch>` per-invocation claim only bites on standalone
`aid-plan-to-epic.sh` calls. At generation time the PM's route is the
pipeline's own `--force --reason` (see "CP1 blocked the plan." above) —
audited three ways, invocation-scoped, and recorded in the authority with
every bypassed condition verbatim. Using either always leaves the
unresolved findings on record; neither is ever a silent pass.

**Gate enforcement.** `aid-cp1-gate.sh` — called once per generation
transaction by `aid-auto-pipeline.sh`, and per invocation by a standalone
`aid-plan-to-epic.sh` — is the mechanical backstop for all of the above: it
independently re-checks `c0-plan-review.json`'s presence/status/blocking_findings,
re-runs `aid-c0-plan-review.sh verify` itself (never trusting the file's
fields alone), and re-checks `aid-cp1-ledger.sh check-budget` — EPIC
generation is blocked if any of these fail, override or no override for
that specific failure.

**Required evidence files** (must exist, be non-empty, and contain required fields in `.aid-o/work/evidence/<plan_id>/cp1-deep/`):

| File | Produced by | Required field | Gate |
|------|-------------|----------------|------|
| `cp1-lens-L1-behavior.md` | L1 behavior lens agent | `stop_rule_blockers:` at line-start | blocking |
| `cp1-lens-L2-feasibility.md` | L2 feasibility lens agent | `stop_rule_blockers:` at line-start | blocking |
| `cp1-lens-L3-enforcement.md` | L3 enforcement lens agent | `stop_rule_blockers:` at line-start | blocking |
| `cp1-adjudicator.md` | adjudicator agent | `verdict:` at line-start | blocking |
| `c0-lens-reuse_compat.md` | C0 reuse_compat lens | `stop_rule_blockers:` at line-start | observe (E4) |
| `c0-lens-reuse_evidence.md` | C0 reuse_evidence lens | `stop_rule_blockers:` at line-start | findings observe (E4); the FILE is required by the gate in band `full` |
| `c0-lens-planned_call_feasibility.md` | C0 planned_call_feasibility lens | `stop_rule_blockers:` at line-start | observe (E4) |
| `c0-lens-dep_api_grounding.md` | C0 dep_api_grounding lens | `stop_rule_blockers:` at line-start | observe (E4) |
| `c0-lens-idempotency_matrix.md` | C0 idempotency_matrix lens | `stop_rule_blockers:` at line-start | observe (E4) |
| `c0-lens-authority_runtime_matrix.md` | C0 authority_runtime_matrix lens | `stop_rule_blockers:` at line-start | observe (E4) |
| `c0-plan-review.json` | C0 cross-provider (Codex) plan review (`lib/aid-c0-plan-review.sh`) | `review_status`/`blocking_findings` fields + a passing `verify` | **blocking (band `full` only)** |

Evidence location for L1/L2/L3/adjudicator: `.aid-o/work/evidence/<plan_id>/cp1-deep/`
Evidence location for C0 lenses: `.aid-o/work/evidence/<plan_id>/c0/`
Evidence location for the C0 cross-provider plan review: `.aid-o/work/evidence/<plan_id>/c0-plan-review.json` (the canonical, latest-attempt review result, stored at the plan evidence ROOT — one level above `cp1-deep/`). Note: raw Codex evidence (dispatch.json, codex-events.jsonl, codex-last-message.json) is not retained per-attempt; only the final canonical review survives.
Ledger location (band `full` only): `.aid-o/work/cp1-ledger/<plan_id>.yaml` (`lib/aid-cp1-ledger.sh`).

EPIC generation gate (`scripts/aid-cp1-gate.sh`) enforces all of this: missing L1/L2/L3/adjudicator files, unresolved accepted blockers, a missing/unverifiable/still-blocking C0 review, or an exhausted CP1 ledger budget each cause a non-zero exit — see "C0 Cross-Provider Review Loop" above for the full contract.

**Adjudicator acceptance rule:** A `stop_rule_blocker` is accepted ONLY if it has a command/artifact reference (function name, file path, SQL query, config key) AND file:line evidence or an explicit quote from the plan. Vague or hypothetical blockers are rejected with a `rejection_reason`.

**PM escalation:** After 2 auto-revisions with surviving accepted blockers, execution halts and the PM must resolve or waive the blockers before EPIC generation can proceed. For a `full`-band plan, the SAME halt-and-resolve rule applies independently to the C0 cross-provider review loop (see above) once its own budget is exhausted or it hits a mechanically-detected non-convergence.

## Plan-final / close boundary

**Which tree each input is read from** (ACTA #33): the source plan is read from the
**candidate worktree** when it has a copy (a plan branch that edited its own acceptance
criteria is judged on what it edited), else from the state root; `execution.yaml` and the
evidence are **always the state root's** — a plan branch's copy of `.aid-o/config` is never
read, edit it in the primary checkout. `plan-finalize --stage gates|inputs` prints both paths
before it runs anything.

Under `plan_branch`, the plan-final boundary is the PM's decision moment — so it
gets a card and a one-screen page, not a file listing. After `aid-pm-brief.sh`
has produced the handoff pair, render both from it:

```bash
source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-close-summary.sh"
aid_plan_close_render "$evidence_dir/pm-decision-brief.json" \
                      "$evidence_dir/release-decision.json" "$plan_id" "$evidence_dir"
```

Publish the artifact body via the Artifact tool, then present the chat card verbatim.

Card shapes come from `skills/communication.md`: Decision-required when the plan
is not release-ready or `merge_mode` is not `auto`, Finished when recording a
completed close. Every number on the page is counted by the renderer from
`release-decision.json`; state none of them yourself. The offered options are
derived from `merge_mode`, `release_ready` and whether the plan is already
merged — `plan-rollback` appears only once a final merge SHA exists, and
"defer" is taking no action, never a fabricated command.

The renderer exits 1 without writing a page when the brief lacks one of its
eight required fields or the decision carries no
`.release_decision.plan_summary`. If the brief is missing entirely, report the
Blocked card "plan-close brief missing — run aid-pm-brief.sh" rather than
assembling a summary from evidence files. `legacy_epic_release_mode` plans keep
their existing per-EPIC release text unchanged.

## The PM page goes stale with every plan edit

`aid-plan-to-epic.sh` refuses to generate when the PM page is older than the plan file
("has no current PM page"). That is by design — the page is what the PM approved — so after
every plan edit, re-render it with the command the refusal prints before running generation
again.

## When AID itself misbehaves

A gate that refuses a valid plan, a script that crashes, a message that tells you to do what is already true — write it to `.aid-o/work/aid-plugin-issues.md` (date → what happened → what it caused → what you did), not to the project backlog. Rule text: `skills/agent-protocol.md` §"Problems with AID itself".

## Reference Files

- `skills/brainstorming.md` — brainstorm process rules, principles, and context persistence (interim doc) protocol
- `skills/plan-writing.md` — plan writing quality gates and format
- `skills/planner.md` — dependency graph and parallel groups
- `skills/review-checkpoint-contracts.md` — CP1-deep contract
- `{plugin_path}/scripts/aid-auto-pipeline.sh` — deterministic EPIC generation pipeline
- `{plugin_path}/scripts/aid-cp1-gate.sh` — CP1-deep evidence gate, incl. the C0 review + CP1 ledger checks (called once per generation transaction by aid-auto-pipeline.sh; per invocation by a standalone aid-plan-to-epic.sh)
- `{plugin_path}/scripts/lib/aid-c0-plan-review.sh` — C0 cross-provider (Codex) plan review bridge (build-manifest/dispatch/verify)
- `{plugin_path}/scripts/lib/aid-cp1-ledger.sh` — CP1 revision-limit ledger (init/increment/read/check-budget)
- `{plugin_path}/scripts/lib/aid-plan-summary.sh` — renders the PM page for a freshly written plan (step 8p)
- `defaults/policies/review-checkpoints.yaml` — `ceremony_bands` (what each band requires) + `cp1_codex_review` bounded-loop policy (`max_rechecks`)
- `defaults/policies/risk-paths.yaml` — the curated path map the band is classified from
- `defaults/templates/plan.md` — base plan template

## Important

- **Auto-detect by default** — mode selection only when explicitly specified or ambiguous
- **One output per mode** — brainstorm produces a plan; write produces a plan; epic produces EPICs + plan.json (interim docs are temporary)
- **Quality gates are mandatory** — plans not written until gates pass
- **Language split** — conversation in PM's language; documents per `config/project.yaml`
- **YAGNI** — never propose over-engineered solutions
- If PM aborts at any step → end gracefully, no final plan/EPIC files written (interim doc preserved for recovery)
- If `.aid-o/` missing → suggest `/aid-init` but proceed anyway

### Streamlined Mode Advisory

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


**Last Updated:** 2026-08-30

## Plan mode

A plan declares its release model in its committed lifecycle manifest
(`.aid-lifecycle/manifests/<plan_id>.yaml`, key `mode`). Under `plan_branch` an
EPIC merges into the plan branch and only the plan releases, once, at the
plan-final boundary; under `legacy_epic_release_mode` each EPIC releases as
before. New plans default to `plan_branch` when the project declares a
`gate_profiles` table, and otherwise fall back to legacy with a logged
`plan_branch_unavailable: no_gate_profiles`. Fast Mode (`/aid-do`) neither
creates nor releases a plan branch. Reinstall the Git hooks after upgrading
(`/aid-init`) so the commit-scope and pre-push guards match the new model.
