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
blocking Files-shape violations to CP1 or to EPIC generation. The plan review
(Step 9) hands the reviewers the plan check's warnings; it does not replace
either check.

**Deterministic plan check (automatic — the same moment, the same rule).** The
lint is one part of it. Run:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" ".aid-o/plans/P{NNN}-{topic}.md" \
  --json ".aid-o/work/evidence/P{NNN}/plan-check.json"
```

It decides everything about the plan that needs no model — the graph of
`Dependencies:`, step counts, forbidden phrases, paths and symbols against the
repository, `Resources Verification` claims, criteria already true on HEAD —
and hands the reviewers its warnings and the list of identifiers the repository
does not know. It never executes a \`cmd:\` criterion unless you pass
\`--run-cmds\` after reading every one of them: a plan is model-written text. `BLOCK` lines must be repaired before CP1; a `lifecycle_strict`
plan is blocked by every one of them, a legacy plan only by what would break
generation. The check is what `aid-generation-readiness.sh` runs, so a plan
that skips it here is refused there. After EVERY revision of the plan, run it
again with the snapshot of the plan as it was and the steps the revision was
allowed to touch:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" "<plan>" --snapshot "<plan-before-revision>" --fixes "3,7"
```

A revision that adds a step, a Files entry or an acceptance criterion outside
the fix list is refused: that is a design change, and a design change is the
PM's to make (cut it out, or bring it as a choice), not a fix to slip in.

### Step 9: Plan review (CP1)
Run "Plan review (CP1)" below, from item 1.
Output: `=== Step 9/9: Plan review ===`, then the PM card of its item 5.

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
9. **Plan review (CP1)** — run "Plan review (CP1)" below, from item 1.

Output: plan path, step count, quality gate results, plan review verdict.

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
| `aid_generation_force_required:` | The failure is a plan review condition — a missing or unclosed round, open blockers without a second round or an acceptance criterion, a plan changed after its last round. A PM may deliberately waive it. | Fix the conditions, or run the force command the label prints (it already carries your `--plan` and `--queue-mode`). |
| `aid_cp1_blocked:` | The failure is one `--force` cannot cover — the gate was mis-invoked, the plan's own identity is broken, the plan review configuration is invalid, or the round evidence is unreadable or tampered with. The hard condition is named first. | Fix the named condition. `--force` is **refused in the same place** on this class, not merely unadvertised: it seals no authority, writes no waiver, and says so by name. |

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

## Plan review (CP1)

Both modes end here, once `aid-plan-check.sh` passes on the written plan. Six
reviewer roles (`skills/plan-review-roles.md`) answer the same packet in at most
two rounds by default; `aid-review-round.sh` runs the rounds and
`aid-cp1-gate.sh` refuses EPIC generation until the evidence is complete. Every
item below is a command. You never write, edit or complete a reviewer's answer.

Skip this section when `review_checkpoints.cp1_plan_review` (or `enabled`) is
`false` in `.aid-o/config/policies/review-checkpoints.yaml`; tell the PM it was
skipped. The gate then passes with a notice.

`<plan>` is the plan path, `<plan_id>` its frontmatter id, and `R` stands for
`"$AID_PLUGIN_PATH/scripts/aid-review-round.sh"`.

1. The deterministic check passes and its report matches the plan (a revision
   makes it stale; rerun it after every edit):

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" <plan> --json .aid-o/work/evidence/<plan_id>/plan-check.json
   ```

2. Prepare round 1. It prints the round directory and one prompt per reviewer:

   ```bash
   bash "$R" prepare <plan> --round 1
   ```

3. Dispatch every reviewer of the round. A role with `provider: codex`:

   ```bash
   bash "$R" dispatch <plan> --round 1 --provider codex --role generalist_b
   ```

   Without Codex installed it prints that the role is recorded as not
   answered and exits 0; continue. Every
   role with `provider: claude` follows `scripts/lib/aid-plan-review-adapter-claude.md`,
   quoted here in full:

<!-- adapter:begin -->
# Claude reviewers of a review round — controller instruction

The Agent tool is not callable from bash, so the controller dispatches every
reviewer whose provider is `claude`, at every checkpoint: the plan review
(`commands/aid-plan.md` "Plan review (CP1)") and the step, EPIC and fast-mode
reviews (`commands/aid-run.md` "Step review (CP2) and EPIC review (CP3)",
`commands/aid-do.md`) include this text verbatim. `<round dir>` is the
directory `prepare` printed, and `prepare` prints each role's `<focus>` next
to its prompt: `cp1-<role>` for a plan, `cp2-step-<N>-<role>` for a step,
`cp3-<role>` for an EPIC, `cp6-<role>` in fast mode, the role with `_`
replaced by `-` (the dispatch wrapper allows no underscore in `--focus` or
`--agent-id`).

For EACH expected role with `provider: claude` in `<round dir>/round.json`,
one at a time:

1. Open the dispatch:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus <focus> \
     --agent-id aid-orchestrator:review --evidence-dir <round dir>
   ```

2. Dispatch the reviewer with this one-line prompt, never the file's content
   (a packet runs to hundreds of kilobytes; pasted copies would fill the
   controller's own context):

   ```
   Agent(subagent_type: "general-purpose", model: <the role's model from the checkpoint's reviewer block>,
         prompt: "Your complete instructions are in <round dir>/prompt-<role>.md. Read that whole file first and follow it exactly.")
   ```

   The reviewer writes `<round dir>/reviewer-<role>.json` itself. Note the
   `subagent_tokens` figure the Agent result reports; when the result shows
   none, the value is `unknown`.

3. Close the dispatch. `<answer>` is `<round dir>/reviewer-<role>.json`; when
   the reviewer wrote no file, create the empty marker
   `<round dir>/reviewer-<role>.missing` and use that path instead:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus <focus> \
     --output-file <answer> --evidence-dir <round dir>
   ```

   A step round's `close` refuses a reviewer file with no such start/complete
   bracket in `<round dir>/timeline.jsonl` (`no_dispatch_record`): a file
   nobody dispatched does not close a round. Only a round prepared with
   `--stub` by the acceptance suite skips that check, and the FSM refuses to
   advance on such a round.

After ALL reviewers of the round (claude and codex) have been dispatched, run
`collect`. Only when `collect` exits 0, run `close` once with a token value for
every claude role; when it reports the round invalid, retry the roles it names
first (`close` refuses an invalid round). `<review>` is `--plan <plan>` for
CP1, `--checkpoint cp2 --evidence-dir <run dir> --step <N>` for a step,
`--checkpoint cp3 --evidence-dir <run dir>` for an EPIC:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" collect <review> --round K
bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" close <review> --round K \
  --tokens <role>=<n|unknown> ...
```

When `close` reports `fail` on a step or EPIC round and a round remains
(`rounds_default`, or the PM's `override`), the fix is the step's own role's:

```
Agent(subagent_type: "aid-orchestrator:implementer", model: <the model of the step's role card in skills/role-cards.md>,
      prompt: "fix_of: <round dir>. Read <round dir>/merged.json, fix every finding with status open (blocker and major first), commit with the message prefix fix(review):, and report the finding ids you addressed. Touch nothing a finding does not name.")
```

Then `aid-step-check.sh` again (the range now ends at the fix commit) and
`prepare --round K+1`: the confirmation round asks only the reporters of what
stayed open and shows them the open findings and the fix diff. Record the
fixer's model and tokens on the next `close` with
`--fixer <role>=<model>:<tokens_in>:<tokens_out>`.

Never edit a reviewer's file, never write one on a reviewer's behalf, and never
dispatch a role twice: a role `collect` lists as invalid or missing goes
through `retry`, then this procedure for that role alone.
<!-- adapter:end -->

4. When `collect` reports the round invalid, retry only the roles it names,
   dispatch each of them again (item 3), then `collect` and `close`:

   ```bash
   bash "$R" retry <plan> --round 1 --role <role>
   ```

5. Show the PM one information card (`skills/communication.md`): the blockers
   and majors of `round-1/merged.json` in plain words, how many findings were
   rejected, and the round's cost from `measurement.json`. When you hold a
   finding to be wrong, dispute it and make the card a decision card; record the
   PM's answer in the PM's words:

   ```bash
   bash "$R" dispute <plan> --round 1 --fingerprint <fingerprint> --reason "<why the finding is wrong>"
   bash "$R" dispute <plan> --round 1 --fingerprint <fingerprint> --pm accepted --reason "<the PM's words>"
   ```

   A disputed blocker stays open until the PM accepts the dispute.

6. No blocker open: if you changed the plan after the round (fixing majors,
   say), run `finalize` (item 8) before the gate; otherwise go to item 9.
   Blockers open: fix the plan — only the steps the
   open blockers and majors name — then check the fix and prepare round 2:

   ```bash
   bash "$R" fix-check <plan> --round 1
   bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" <plan> --json .aid-o/work/evidence/<plan_id>/plan-check.json
   bash "$R" prepare <plan> --round 2
   ```

   `fix-check` refuses a fix that adds a step, a Files entry or an acceptance
   criterion to a step no finding named: cut it, or bring it to the PM as a
   design change. Round 2 asks only the reviewers whose findings touch a
   changed step, plus every reviewer that reported a blocker.

7. Run round 2 exactly as items 3 to 5, with `--round 2`.

8. Blockers still open after the last round: record any dispute first (item
   5), fix what the last round found, and add to each open blocker's step an
   acceptance criterion that quotes the finding's claim (at least its first
   eight words; a plan-level finding goes under `## Success Criteria`). Then
   snapshot the plan; this is the only edit allowed after the last round, and
   any later edit needs `finalize` again:

   ```bash
   bash "$R" finalize <plan>
   ```

9. Run the gate. Every failure names what is missing, for example
   `no plan review round-1 for P093; run: aid-review-round.sh prepare …`:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh" --plan <plan>
   ```

**Round count.** Two rounds is the default (`review_checkpoints.plan_review.rounds_default`).
Only when the PM says so, record one round, or a third:

```bash
bash "$R" override <plan> --rounds 3 --reason "<the PM's words, quoted>"
```

The record states that the PM said it; it cannot prove it, exactly like
`--force` and every waiver. Never run it on your own judgment. `--rounds 1` is
accepted once round 1 is closed, and its open blockers still need the
acceptance criteria of item 8; after it only the steps of round 1's open
findings and acceptance criteria may change before `finalize`. A third round runs only on what is still open.

**Codex unavailable.** The role is recorded as not answered and the round stays
valid while at least `min_answers` reviewers, one of them a generalist,
answered. Name the missing role on the PM card; never switch its provider
yourself — the provider is the project's configuration.

**Evidence.** `.aid-o/work/evidence/<plan_id>/cp1/`: `rounds.json`, one
`round-N/` per round (`round.json`, `packet/`, `prompt-<role>.md`,
`reviewer-<role>.json`, `collect.json`, `merged.json`, `rejected.json`,
`yield.json`, `measurement.json`, `fix-diff.json`, `plan-final.md`),
`override.json`, and `manual/` from `/aid-verify-plan`, which the gate never
reads.

## Plan-final / close boundary

**Which tree each input is read from** (ACTA #33): the source plan is read from the
**candidate worktree** when it has a copy (a plan branch that edited its own acceptance
criteria is judged on what it edited), else from the state root; `execution.yaml` and the
evidence are **always the state root's** — a plan branch's copy of `.aid-o/config` is never
read, edit it in the primary checkout. `--stage gates` prints both paths before it runs
anything; `--stage inputs` prints the plan it used (it reads no gate config).

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
- `skills/plan-review-roles.md` — the six plan reviewer roles, the evidence rule and the answer shape
- `{plugin_path}/scripts/aid-auto-pipeline.sh` — deterministic EPIC generation pipeline
- `{plugin_path}/scripts/aid-review-round.sh` — plan review rounds (prepare, dispatch, collect, close, retry, fix-check, dispute, finalize, override)
- `{plugin_path}/scripts/aid-plan-review-adjudicate.sh` — merges a round's answers, rejects findings without proof
- `{plugin_path}/scripts/aid-cp1-gate.sh` — the plan review gate (called once per generation transaction by aid-auto-pipeline.sh; per invocation by a standalone aid-plan-to-epic.sh)
- `{plugin_path}/scripts/lib/aid-plan-summary.sh` — renders the PM page for a freshly written plan (step 8p)
- `defaults/policies/review-checkpoints.yaml` — `plan_review`: reviewers, providers, models, rounds
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


**Last Updated:** 2026-09-18

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
