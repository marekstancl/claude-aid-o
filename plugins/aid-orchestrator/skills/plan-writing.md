---
name: plan-writing
description: Exhaustive plan document authoring with forbidden phrase detection, completeness gates, and traceability verification
user_invocable: false
---

# Plan Writing — Exhaustive Plan Document Authoring

**Skill:** plan-writing
**Dependencies:** brainstorming

---

## TL;DR

This skill defines how AID writes **exhaustive, implementation-ready plan documents**. It ensures that every detail from brainstorming (or a standalone specification) is captured in the plan — nothing is lost, nothing is summarized away, nothing is deferred to "see brainstorming notes."

The plan-writing skill is invoked in two modes:
1. **Post-brainstorming** — called by `/aid-plan brainstorm` Step 8 after PM approves all design sections. Receives approved sections as input.
2. **Standalone** — called by `/aid-plan write` command with a specification or requirements as input.

**Input:** Approved design sections from brainstorming OR specification document + codebase analysis
**Output:** Exhaustive plan document (`.aid-o/plans/P{NNN}-{topic}.md`)

### Writing a plan while another one is live

Never gate plan writing on another plan's state or on the PM's uncommitted
work. Each plan implements in its own git worktree (`.aid-worktrees/plan-<id>`),
so an active plan holds neither the PM's checkout nor its branch, and
`plan-start` no longer refuses on an unrelated dirty tree.

Orient once, from `git worktree list`, `.aid-o/work/plan-state/*/plan-state.yaml`
and `.aid-o/work/active-runs.json`, then report what is running and continue.
`commands/aid-plan.md` § "Working while another plan is live" carries the full
situation table (missing worktree, unregistered directory, three-plus streams).

One limit worth naming to the PM up front: concurrent plan GENERATION is
supported; *starting* a newly generated plan's EPIC while another stream is
live is not yet.

### Plan Types — Roadmap vs Executable

| Type | What it is | Where it lives | Plan ID? | Runs via /aid-run? |
|------|-----------|---------------|----------|-------------------|
| **Executable plan** | Single-phase implementation plan, spustitelný přes FSM | `.aid-o/plans/P{NNN}-{topic}.md` | YES — via `aid-fsm.sh alloc plan-id` (locked; never hand-edit counter.yaml) | YES |
| **Roadmap / MVP plan** | Multi-phase master plan with subfáze; NOT directly executable | `docs/plans/{project}-{topic}.md` | NO — no allocator call | NO — subfáze become executable plans |

**Detection:** If the brainstormed plan has 3+ phases (MVP phases, milestones), it is a **roadmap**.
Roadmaps are saved to `docs/plans/`, do NOT consume a plan ID, and are NOT tracked in `active.md`.
Each subfáze of the roadmap becomes a separate executable plan with its own P{NNN} ID when the PM
runs the `/aid-plan write` command from the generated session prompts.

**Why:** Roadmaps never "complete" in FSM terms. They are living reference documents.
Allocating plan IDs to them wastes counter space and creates phantom entries in plans/.

---

## Core Principle: Zero Information Loss

The plan document is the **single source of truth** for implementation. Agents receive plan sections during dispatch (via `plan_ref` injection in `skills/pipeline.md` § 4). Any detail missing from the plan is detail the agent will never see.

```
RULE: If it was discussed, decided, or approved — it MUST be in the plan.
      If it's not in the plan — it does not exist for execution.
```

This is not a summary document. This is not a high-level overview. This is the implementation specification that agents will follow line by line.

---

## Invocation Modes

### Mode A: Post-Brainstorming

Triggered by `/aid-plan brainstorm` Step 8 after PM approves all design sections.

**Input available:**
- All approved design sections from brainstorming Steps 5-6 (architecture, data model, API, implementation, testing, risks)
- PM's answers from Steps 3-4 (questions, approach selection)
- PM's modifications and corrections from incremental validation
- Project context from Step 1 (project profile, tech stack, existing code)

**Contract:** The skill receives ALL brainstorming context. It does NOT re-ask PM questions. It does NOT explore alternatives. It writes.

### Mode B: Standalone

Triggered by `/aid-plan write` command with a specification file or topic.

**Input available:**
- Specification document or PM-described requirements
- Codebase analysis (the skill performs deep-dive file reading)
- PM's answers to clarifying questions (max 5)

**Contract:** The skill conducts targeted codebase analysis, asks minimal clarifying questions, then writes the exhaustive plan.

---

## Plan Document Structure

The plan document uses an extended format that is a **superset** of the standard `defaults/templates/plan.md`. All existing sections are preserved (backward compatible), and new detailed step sections are added.

### Frontmatter (unchanged)

```yaml
---
id: P{NNN}
type: plan
status: draft
created: YYYY-MM-DD
author: PM + AI
---
```

### Sections

The plan MUST contain these sections in this order. All of them are written
for the AGENT that will execute the plan. The document for the PM is a separate,
rendered artifact — see MUST rule 17.

| Section | Content | Source |
|---------|---------|--------|
| `## Context` | Why this plan exists, what triggered it | Brainstorming context / spec |
| `## Goal` | One-sentence desired outcome | Brainstorming goal / spec |
| `## Scope` | In-scope and out-of-scope items | Brainstorming scope |
| `## Approach` | Chosen approach with alternatives summarized | Brainstorming approaches |
| `## Architecture` | Full architecture from approved design | Brainstorming architecture section |
| `## Data Model` | Entities, fields, types, relationships, invariants | Brainstorming data model section |
| `## API Design` | Endpoints, contracts, request/response schemas, errors | Brainstorming API section |
| `## Implementation Steps` | Detailed per-step breakdown (see format below) | Brainstorming implementation plan |
| `## Testing Strategy` | Which behaviour this plan verifies, why that behaviour, and where the verification goes. **Required, with content** — `aid-plan-lint.sh` refuses a plan without it. | Brainstorming testing section |
| `## Constraints` | Technical, business, timeline constraints | PM answers |
| `## Risks` | Risk table with probability, impact, mitigation | Brainstorming risks |
| `## Success Criteria` | Testable success criteria | PM answers |
| `## Next Steps` | Follow-up actions | Standard |

**Conditional sections** (include only when relevant, omit otherwise):
- `## Infrastructure` — Docker Compose, deployment, CI/CD (when Docker/infra was discussed)
- `## Security` — Auth, permissions, data protection (when security was discussed)
- `## UI Design` — Components, layouts, interactions (when frontend was discussed)
- `## Migration Plan` — Before/after, rollback, data migration (when migration was discussed)
- `## Visual Specification` — visual-spec.yaml, mockup source code references, component breakdown (when mockups exist in `plans/{plan_id}/mockups/`)

**source_type: companion** — HTML files from Visual Companion brainstorming session.
Extract CSS classes, layout structure (grid/flex/columns), color values, and component
structure from HTML. The companion HTML IS the mockup source code — agents receive it
verbatim, same as GitHub TSX/CSS source.

**Section omission rule:** If brainstorming did not discuss a topic (e.g., no frontend, no API), the corresponding section is omitted entirely. Do NOT add empty or placeholder sections. Do NOT invent content for sections that were not discussed.

### MVP/Roadmap Plans — Special Handling

When brainstorming produces a multi-phase MVP plan (detected by: 4+ weeks effort, 3+ phases, or PM explicitly requests "MVP plan"):

1. **Save to `docs/plans/`** — NOT `.aid-o/plans/`. MVP plans are roadmap documents, not executable plans. Do NOT allocate a plan ID (no `aid-fsm.sh alloc plan-id` call).
2. **Session prompts section** — after all phases, include `## Session Prompts for Detailed Plans`:
   - Per subfáze: `/aid-plan write {mvp-plan-path} {phase} {subfáze}` command
   - Context line for writer: 2-3 sentences describing scope, key references, gaps addressed
3. **Separate session prompts file** — generate `docs/plans/{project}-session-prompts.md` with detailed copy-paste prompts per subfáze (goal, items, files CREATE/MODIFY, reference docs, key decisions, rules, prerequisites)
4. **Important note at top of session prompts section:**
   > Before writing each detailed plan, the plan writer MUST read current state of existing code,
   > compare with architecture doc expectations, identify stubs vs working code, and adapt plan to reality.

---

## Phase Markers

When a plan spans multiple EPICs (phases), each phase must be delimited by a phase marker so the pipeline scripts can slice steps correctly. The marker format is:

```
**EPIC N: Steps M-P — Title**
```

Where:
- `N` is the phase number (1, 2, 3, ...)
- `M` is the first step number in this phase
- `P` is the last step number in this phase
- `Title` is a short human-readable label (optional but recommended)

**Extended form (with step range — preferred for multi-phase plans):**

```markdown
**EPIC 1: Steps 1-4 — Foundation**

### Step 1: ...
### Step 2: ...
### Step 3: ...
### Step 4: ...

**EPIC 2: Steps 5-8 — Feature Build**

### Step 5: ...
...
```

**Short form (without step range — for sequential simple plans):**

```markdown
**EPIC 1**

### Step 1: ...
### Step 2: ...

**EPIC 2**

### Step 3: ...
```

When the short form is used, the script assigns steps to phases by document order: every `### Step N:` header encountered after a `**EPIC N**` marker belongs to that phase, until the next marker.

**Rules:**

| Scenario | Rule |
|----------|------|
| Multi-phase plan (total phases > 1) | MUST include phase markers |
| Single-phase plan (total phases = 1) | Phase markers are NOT required — all steps belong to the single phase automatically |
| Marker placement | Place each marker on its own line, immediately before the first step of that phase |
| Step numbering | Step numbers in the marker range MUST match actual `### Step N:` headers; ranges with gaps are invalid |

**Do NOT use these formats — they will not be parsed:**

```markdown
# WRONG — uses heading syntax instead of bold text
## Phase 1: Foundation
### Phase 2: Build

# WRONG — uses dash list and wrong keyword
- Phase 1: Steps 1-4

# WRONG — missing asterisks, not bold
EPIC 1: Steps 1-4
*EPIC 1: Steps 1-4*

# WRONG — uses "Phase" keyword instead of "EPIC"
**Phase 1: Steps 1-4 — Foundation**

# WRONG — missing colon between EPIC N and Steps
**EPIC 1 Steps 1-4**
```

**Why format matters:** The `aid-plan-to-epic.sh` script uses a bash regex to identify phase boundaries:

```
^\*\*EPIC[[:space:]]+([0-9]+)(:[[:space:]]+Steps[[:space:]]+([0-9]+)-([0-9]+))?
```

Only lines that match this regex are recognised as phase markers. Any other format is silently ignored, causing the script to fall back to even step distribution across phases — which produces incorrect EPIC splits when steps are not evenly distributed.

---

## Detailed Step Format

The `## Implementation Steps` section replaces the old `## High-Level Steps` table. Each step gets its own subsection with mandatory fields.

### Per-Step Template

```markdown
### Step {N}: {Descriptive Name}

**Objective:** {What this step produces or changes — one sentence}

**Files:**
- Create: `exact/path/to/new-file.ts` — {what this file contains and why}
- Modify: `exact/path/to/existing-file.ts` (lines ~{start}-{end}) — {what changes and why}
- Test: `tests/exact/path/to/test-file.spec.ts` (tier: t1) — {what behavior this tests}
        *(a `Test:` bullet is OPTIONAL — see "Tests are designed, not counted" below)*

**Reuse check:** searched: `<read-only search command>` → <none | one match `path` |
several matching `paths` | several conflicting `paths`> — {why what exists does not suffice}
        *(REQUIRED for a step whose Files carry a `Create:` bullet — see "Reuse check" below)*

**Parallel group:** {wave name, e.g. `wave-1`} | `---` *(a step that runs alone)*

**Files-entry grammar (enforced — `aid-plan-lint.sh` runs at plan write time AND as a
hard pre-flight in `aid-plan-to-epic.sh`; a violation stops generation with the exact
line).** Each Files bullet MUST be exactly:

```
- <Create|Modify|Test|Rewrite>: `path` [ + `path`]* [(lines ~N-M)] [(tier: t0|t1|t2)] [— prose]
```

- The path(s) come FIRST, each in backticks, immediately after the `Verb:` label.
- Multiple files in one bullet ONLY via an explicit `` + `` between backtick paths.
- The only parentheticals allowed before the `—` are a `(lines ~N-M)` range and a
  `(tier: t0|t1|t2)` declaration; put every other note AFTER the `—`.
- A `Test:` bullet naming a suite that **does not exist yet** MUST declare its tier.
  Generation refuses without it (`aid-plan-to-epic.sh`), because a portfolio that can
  grow untiered is a portfolio that grows back onto the merge path. A bullet pointing
  at an EXISTING suite needs no declaration — it inherits that file's own
  `# aid-tier:` tag, which `aid-test-tier-lint.sh` guards. Adding a case to a suite
  that already exists is the cheapest and most encouraged move, and it stays free.
  Projects that have adopted no tiers at all are unaffected: the requirement
  activates only once some suite in the tree carries a tag.

NEVER (these are why plans used to blow up mid-generation):
- ❌ bold-wrap the bullet: `- **Modify: \`x\` …**` (the `**` breaks label parsing)
- ❌ start a bullet with a parenthetical: `- (note about something …)`
- ❌ a prose-only entry with no backtick path: `- Modify: the remaining version files`
- ❌ a word before the first backtick: `- Test: extend \`x\` (or …)`
- ❌ split the verb and its path across two lines (the path is silently dropped)

**Reuse-check grammar (enforced — `aid-plan-lint.sh`).** A step that founds
something new (any `Create:` bullet in its `Files:`) MUST carry a
`**Reuse check:**` field, in this shape:

```
**Reuse check:** searched: `<command>` → <result> — <why what exists does not suffice>
```

- The **command** is backticked and comes from the read-only search vocabulary:
  `grep`, `rg`, `ls`, `find`, `git grep`. Nothing else runs, and nothing that
  pipes, redirects or chains is accepted — the lint REPLAYS the command and
  compares the number of hits with the declared result, so a claim of `none`
  over a command that finds something today is a blocking finding. That replay
  is the whole difference between evidence and a formality.
- The **result** is read from AFTER the `→` (or `->`), and the arrow is
  required: without it the lint would have to guess whether a word in the
  sentence is a verdict or part of the search.
- The **result** is one of four, and each has a consequence:
  `none` (proceed), `one match` (use it — the bullet becomes `Modify:`),
  `several matching` (pick the canonical one and say why: newest, most used,
  best tested, the one that holds the standard), `several conflicting`
  (the N+1 rule below decides). Czech spellings `nic`, `jeden vzor`,
  `více shodných`, `více rozporných` are equally accepted.
- **A result other than `none` owes the third part**: why what already exists
  does not remove the need to create. `one match` and `several matching` are
  the N+1 rule one result further along — the step founds something over
  something that exists, and that sentence is the whole difference between
  reuse and duplication. The lint refuses a founding step without it. `none`
  owes no reason: nothing was found to explain away.
- An empty search result is written as `none`. The field is never omitted
  instead.
- Aim the search at the code, not at the repository root: a `grep` over `.`
  finds the plan's own sentence and reports a match that is not one.

**What the replay does NOT prove.** It proves the declared result matches what
the command returns — not that the search was wide enough. A narrowly aimed
`grep` with an honest `none` passes. Width is judged by the `reuse_evidence`
C0 lens, and only in the `full` band; `medium` and `light` keep the replay
alone. That is a deliberate boundary: a review costs a dispatch, and on a small
plan it is not worth one.

**The N+1 rule.** The field is about the thing the step FOUNDS — that is what
"of the same kind" means below, and it is why the rule can be checked at all: a
step that searched for what it is creating has already told the lint which
existing things are in the running. A plan never adds one more variant of
something that already exists. It uses one of them, or it unifies them. Where the found patterns
CONFLICT, `scripts/lib/aid-reuse-verdict.sh` decides between unifying now and
filing the work: unify inside this plan when every conflicting site already
lies inside the paths the plan declares AND the unification does not push the
step past its declared `Effort`; otherwise file a backlog item that LISTS the
sites (never "unify the components"). A borderline case goes to the PM. A plan
that deliberately founds a second variant must say so in the field, in those
words — **`deliberately founding a variant`** (Czech: `vědomě zakládám
variantu`) followed by the reason. A fixed phrase, because the question the
lint asks is "did the author make an argument", and only a phrase the author
had to type answers that mechanically. The rule is not switched off by
silence, only by an argument.

**Architecture Context:**
{How this step fits into the overall architecture. Which components it touches,
which data flows it implements or modifies. Reference the Architecture section.}

**Implementation Detail:**
{Concrete logic, algorithms, data transformations, API calls. This is the
"how" — specific enough that an agent can implement without guessing.
Include code patterns, function signatures, configuration values.}

**Error Handling:**
{Specific failure modes for this step. What can go wrong, how to detect it,
how to recover. Include error codes, fallback behavior, retry logic.}

**Edge Cases:**
- {Edge case 1 — what triggers it and expected behavior}
- {Edge case 2 — what triggers it and expected behavior}
- {Edge case 3 — what triggers it and expected behavior}

**Dependencies:**
- Depends on: Step {X} — {what it needs from that step: files, contracts, data}
- Blocks: Step {Y} — {what it produces that the next step needs}

**Dependency grammar (enforced before EPIC generation).** Put dependencies in
the `**Dependencies:**` block as `Depends on: Step N`, `Depends on: Step N,
Step M`, or `Depends on: Steps N-M`. The value may continue on an indented
line.

There are exactly two accepted ways to say “no dependency”, and both mean the
same thing: **`Depends on: none`** is the authoring form, and **`Depends on:
---`** is the generated-canonical form that EPIC generation emits. Nothing
else counts — `Depends on: nothing`, an empty value, or a marker mixed with a
real reference (`none, Step 3`) all block generation.

An optional human annotation may follow the references, introduced by an em
dash, an en dash, a spaced ASCII hyphen, or an opening parenthesis — all four
of these are equivalent:

```
- Depends on: Step 2 — needs the force helper
- Depends on: Step 2 – needs the force helper
- Depends on: Step 2 - needs the force helper
- Depends on: Step 2 (needs the force helper)
```

Both parsers split on the FIRST separator, grade only the reference list to
its left, and ignore the annotation. An UNSPACED hyphen is never a separator —
it is the range form, so `Steps 1-3` stays a range.

Every token to the left must be recognised IN FULL. `Depends on: Step 2,
banana` fails loudly rather than silently becoming `Step 2`, and
`Depends on: Steps 1-3 and 5` fails rather than silently dropping the 5 — put
that kind of prose in an annotation instead.

`Blocks:` lines live in the same block and are never folded into the depends
set, even when indented. A `Depends on:` line whose ANNOTATION happens to
mention "Blocks:" keeps its dependency.

A missing step, duplicate, self-reference, forward reference, reversed range,
or unrecognised token blocks generation; it is never interpreted as “no
dependency”. Run `aid-generation-readiness.sh <plan> --total <N>` after
writing and repair its exact diagnostics before CP1/C0.

**Acceptance Criteria:**
- [ ] {Testable criterion 1 — specific, measurable}
- [ ] {Testable criterion 2 — specific, measurable}
- [ ] {Testable criterion 3 — specific, measurable}

**Effort:** {S / M / L}
**AID Role:** {architect / domain / backend / frontend / qa / e2e / security / observability / docs-writer / release}
**Visual Refs:** `{path/to/mockup-source.tsx}` lines {start}-{end} — {what part this step implements} *(optional — only for frontend/UI steps with mockups)*
**UI Change Mode:** `existing_ui` | `new_ui` *(frontend steps that modify existing UI — omit for new UI/greenfield)*
**UI Change Contract:** `path: .aid-o/work/.../delta-contract.json | sha256: <hash> | schema_version: 1.0.0` *(REQUIRED when UI Change Mode is `existing_ui` — omitting this blocks controller dispatch; see plan.schema.json)*
```

> **Rule:** Every step with `AID Role: frontend` and `UI Change Mode: existing_ui` MUST include a `UI Change Contract` field. Plans missing this field emit `ui_change_contract: null` in plan.json. Without a contract the companion has no reference to compare against, so the verdict.json will be absent or unverifiable — and the FSM guard in `aid-fsm.sh cmd_increment_step` will then block the step with `frontend_visual_fidelity_block`. (The guard triggers on verdict result, not on null contract directly.)

### E2E Verification Step (auto-added as last step)

If the plan implements a feature with user-facing output (API, UI, data pipeline), the LAST step
of the LAST phase MUST be an E2E Pipeline Verification step with `role: e2e`:

```
### Step {N}: E2E Pipeline Verification

**Objective:** Verify the complete feature works end-to-end across all layers.
Expand the high-level E2E scenarios from the design section into concrete checks:
- Per scenario: specific DB queries, API calls, Playwright selectors, log patterns
- Per layer: Docker logs (grep patterns), DB (table.column values), API (endpoint + expected response), UI (selectors + expected state)

**E2E Scenarios (from design):**
{paste high-level scenarios from brainstorming Step 5}

**Acceptance Criteria:**
- [ ] All scenarios pass on a single full run with 0 failures
- [ ] At least 1 negative/edge case scenario included
- [ ] Infrastructure started and healthy before test execution
- [ ] Fix loop: any failures fixed and re-verified (max 3 cycles per check)

**Effort:** M
**AID Role:** e2e
```

Skip E2E step if: pure refactoring, docs-only, library with no runtime output.

### MVP Plans — Session Prompt Generation (auto-added for multi-phase plans)

When a plan has multiple phases/subfases (MVP plan, large EPIC with sub-phases), the plan writer
MUST generate TWO additional outputs:

**1. Commands section at end of plan** — per subfáze, one-liner command + context for writer:

```markdown
## Commands for Detailed Plan Generation

> **IMPORTANT:** Before writing each phase plan, the plan writer MUST:
> 1. Read current state of existing files referenced in the phase
> 2. Compare what design docs expect vs what actually exists in code
> 3. Identify stubs/placeholders vs working code
> 4. Adapt plan to reality — don't redo what works, fix what's broken
>
> Detailed session prompts: `docs/plans/{project}-session-prompts.md`

### {Phase Name}

\```
/aid-plan write {plan_file_path} {phase_id} {subfase_id}: {title}
\```
**Context for writer:** {2-3 sentences: what this subfase does, which files/dirs it touches,
which design doc sections to reference, which gaps it addresses, key decisions/risks}
```

**2. Session prompts file** — `docs/plans/{project}-session-prompts.md` with detailed prompts
per subfáze that can be copy-pasted into a new Claude Code window:

```markdown
# {Project} — Session Prompts for Claude Code

> Copy each block into a **new Claude Code window** (VSCode or CLI).
> Execute sequentially — each subfase depends on the previous.
> Commit changes after each subfase before starting the next.
> Master plan: `{plan_file_path}`

---

## {Phase}: {Title}

### {Subfase ID}: {Title}

\```
{Detailed prompt with:}
- Goal (1-2 sentences)
- Items to implement (bullet list, specific)
- Files CREATE: (exact paths)
- Files MODIFY: (exact paths, what to change)
- Reference documents: (paths + specific sections)
- Key decisions: (what to decide, constraints)
- Rules: (scope limits, what NOT to touch, commit conventions)
- After completion: (what to verify, how to commit)
\```

**Prerequisites:** {what must be done/installed before this subfase}
```

**When to generate:** Any plan with 3+ phases or 10+ steps. Skip for simple single-phase plans.
**Where to save:** Session prompts file at `docs/plans/{project}-session-prompts.md` (or `.aid-o/plans/` if no docs/ dir).
**Quality rule:** Each session prompt must be SELF-CONTAINED — a developer opening a new CC window
with zero context must be able to execute it. No "see previous phase" references without specifics.

### Tests are designed, not counted

A step does NOT need a `Test:` bullet. Generation has never required one, and
the habit of adding one per step produced a portfolio that grew with the step
count rather than with the behaviour at risk — measured across six live plans,
test items to steps ran at roughly 1:1 whatever the plan actually changed
(P073 21/19, P074 20/19, P076 18/17, P079 14/14, P083 10/10).

What the plan owes instead is one `## Testing Strategy` section answering three
questions in plain sentences:

1. **Which behaviour does this plan verify?** Name it. "The classifier returns
   `light` for a plan that only touches command texts" is a behaviour; "unit
   tests for step 3" is a count.
2. **Why that behaviour and not another?** Usually because the plan CHANGES a
   decision something else depends on. A plan that changes no behaviour says
   so — "no new verification, reason: …" is a complete and valid answer.
3. **Where does it go?** A case in an EXISTING suite is the preferred and
   cheapest move, and the plan should say so explicitly. A NEW suite is a
   decision that costs a tier declaration and a name, so it is stated as a
   decision, not slipped in.

Unchanged, deliberately: a `Test:` bullet naming a suite that does not exist yet
MUST declare its tier (`aid-plan-to-epic.sh` refuses without it). Making tests
optional per step and letting untiered suites in are two different things, and
only the first is intended here.

### Obligations by ceremony band

A plan's obligations are proportional to what it declares it will touch. The
**band** is classified from the plan's own `Files:` paths — ask the gate, never
re-derive it:

```bash
band="$(bash "$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh" --plan "$PLAN_FILE" \
        --project-root "$PROJECT_ROOT" --classify-only)"   # full | medium | light
```

Run this FIRST, before revising the plan against anything below.
`aid-plan-lint.sh` enforces the same split from the SAME classifier — it sources
`lib/aid-plan-band.sh` directly rather than shelling out to the gate, because
the gate is consulted exactly once per plan — so the band you write against and
the band the lint checks are one classification, never two.

| Obligation | `full` | `medium` | `light` |
|---|---|---|---|
| `Files:` in the canonical grammar | required | required | required |
| **Objective** | required | required | required |
| **Acceptance Criteria** | required | required | required |
| **Dependencies** | required | required | required |
| **Effort**, **AID Role** | required | required | required |
| Tier on a `Test:` bullet naming a NEW suite | required | required | required |
| `## Testing Strategy` with content | required | required | required |
| **Reuse check** on a step with a `Create:` bullet | required | required | **required** |
| A step naming the help/docs path a behaviour change needs | required | required | — |
| **Parallel group** per step | required | required | defaults to `---` |
| **Architecture Context** | required | required | — |
| **Error Handling** | required | required | — |
| **Edge Cases** | required | required | **not required at all** |
| **Implementation Detail** | a paragraph or a code snippet | a paragraph or a code snippet | one sentence is enough |
| `verification_pattern` on plan-level AC | required | required | — |
| C0 cross-provider review round | required | — | — |

The three fields marked "—" for `light` are not "nice to have there" — they are
**not asked for**, and a light plan that omits them is complete. That is the
whole point of the band: a plan that changes a help text was answering questions
about failure modes it does not have.

Nothing here lowers a band. A plan that wants the full ceremony says so with
`risk: high` in its frontmatter; a plan that wants less says so by touching less.

### Declaring what can run at the same time

Each step says which **wave** it belongs to:

```
**Parallel group:** wave-2
**Parallel group:** ---        # this step runs alone
```

A wave name is one word (`[A-Za-z0-9_-]`); `---` is the same "nothing here"
marker the dependency grammar uses, so a plan has one spelling for it, not two.
An explanation may follow the name — only the first word is graded.

`aid-plan-parallel-check.sh` proves the declaration safe by the one mechanical
measure there is: **two steps in the same wave must not name the same file.**
The check is advisory while the plan is being written (`--advisory`) and
BLOCKING inside `aid-generation-readiness.sh`, which is the last point before
the plan becomes EPICs — the same two-stage model the `Files:` grammar has.

Compute the waves by hand from the declared `Files:` and `Depends on:` — the
check VERIFIES a schedule, it does not produce one, and verification is not a
substitute for having thought about it. Then put the result in a table:

| Wave | Steps | Waits for | Why |
|---|---|---|---|
| 1 | 1, 4 | — | no path in common |

**`max_parallel: 1` does not make this ceremony.** Nothing runs concurrently
today; the table is the evidence of safety for the moment the brake comes off,
and evidence gathered after the fact is evidence nobody trusts.

Two steps touching the same file in DIFFERENT waves are fine — that is what
waves are for. A wave with one step is valid and does nothing; the check says
so and does not fail.

### Documentation, help and screenshots

A plan that changes what a user meets owes the way in: **the file and the
section**, declared in a `Files:` bullet like any other work. Not "update the
documentation" — that sentence has never once caused documentation to be
updated.

What the project HAS is not rediscovered every time a plan is written.
`/aid-init` and `/aid-setup` record it once in `project.yaml`:

```yaml
documentation:
  in_app_help: src/app/napoveda          # the in-app help surface, if any
  docusaurus: docs/docs/myproject        # the documentation site, if any
  screenshot_tool: "node lib/ui-fidelity/ui-capture.mjs <url> <out.png>"
```

- **A project with neither owes nothing here**, and `aid-plan-lint.sh` records
  that it asked nothing — so the silence does not read as an omission.
- **A project with one of the two owes only that half.**
- **`type: refactor` and `type: docs` are exempt by definition.** That is the
  machine-readable form of "this plan changes nothing a user meets", and it is
  read from the frontmatter the plan already carries rather than guessed at
  from its prose. A plan that changes behaviour and claims `refactor` to dodge
  the obligation is lying in a field a reviewer can see.
- **Where a screenshot is needed, name the command that takes it** — the one in
  `documentation.screenshot_tool`. A missing tool is not a reason to block the
  plan: the plan states how to install it and that is enough, since blocking on
  a missing tool would also block acquiring it.
- **Never a screenshot of production data.** Where a shot would capture
  anything real, the plan says so and uses a fixture.

The tooling for screenshots is not written per plan: `lib/ui-fidelity/`
already carries `ui-capture.mjs`, `screeng-capture.mjs` and `ui-compare.mjs`.

### Mandatory Fields Per Step

Per the table above, "every step" below means every step of a `full` or `medium`
plan. A `light` plan owes the universal rows only.

Every step MUST have ALL of these fields populated:

| Field | Minimum Requirement |
|-------|-------------------|
| **Objective** | One clear sentence, no ambiguity |
| **Files** | At least 1 concrete file path (no placeholders like `src/...`) |
| **Tier** (`Test:` bullets naming a NEW suite) | `(tier: t0\|t1\|t2)` — chosen from cost and scope, never from importance: **t0** under 2 s per case (the whole tier under 2 min), **t1** under 30 s per case (the whole tier under 10 min, and this is what blocks a merge), **t2** everything else AND anything cross-component. Into **t2 only with a stated reason** in the prose — t2 runs nightly, so a suite parked there is one nobody is waiting on. |
| **Reuse check** (steps with a `Create:` bullet) | A replayable read-only search command, one of the four results, and why what exists does not suffice. Required in EVERY band — founding a duplicate is exactly what small plans do. |
| **Architecture Context** | At least 2 sentences referencing the Architecture section |
| **Implementation Detail** | At least 1 paragraph with concrete logic OR 1 code snippet |
| **Error Handling** | At least 1 failure mode with recovery strategy |
| **Edge Cases** | At least 2 edge cases (3+ for M/L effort steps) |
| **Dependencies** | Explicit dependency statement (or "No dependencies — can start independently") |
| **Acceptance Criteria** | At least 2 testable criteria per step (3+ for M/L effort) |
| **Effort** | S, M, or L |
| **AID Role** | Exactly one role from the AID role set |

**Exception:** For S-effort steps that are purely mechanical (e.g., "add config entry"), Error Handling and Edge Cases may have 1 item each instead of the minimums above.

---

## Forbidden Shortcuts

These phrases indicate the AI is taking shortcuts instead of providing real detail. Their presence in a plan document is a **hard failure**.

| Forbidden Phrase | Why It Fails | What to Write Instead |
|---|---|---|
| "implement standard error handling" | What is "standard"? For whom? | Name specific error codes, response shapes, recovery strategies |
| "follow existing patterns" | Which patterns? In which files? | Cite the specific file path and line range as the pattern source |
| "add appropriate validation" | What rules? What types? What ranges? | List each validation rule: field X must be string, 1-255 chars, no HTML |
| "handle edge cases" | Which ones? | Name 2+ specific edge cases with expected behavior |
| "update tests accordingly" | Which tests? What assertions? | Name test file, test function, input value, expected output |
| "see brainstorming notes" | Plan must be self-contained | Copy the relevant detail directly into the plan |
| "similar to X component" | How similar? What differs? | Describe the specific implementation, noting differences from X |
| "and other necessary changes" | Hidden scope = missed work | List every change explicitly — if you can't name it, it's not planned |
| "as needed" | Undefined scope | Specify exactly what is needed and under what conditions |
| "standard REST/CRUD operations" | Which operations? What schemas? | List each endpoint: method, path, request body, response, errors |
| "proper logging/monitoring" | What is "proper"? | Specify what to log, at what level, with what fields |
| "handle authentication" | How? JWT? Session? OAuth? | Specify the auth mechanism, token format, validation steps |
| "refactor as necessary" | Unbounded scope | List each specific refactoring operation |
| "configure appropriately" | What values? | Specify exact configuration keys and values |
| "etc." / "and so on" / "..." | Hiding missing detail | Complete the list — if you can't, you don't know enough |
| "purple gradient banner" (or any text-only UI color/style description) | Vague — agent invents own design | Include exact CSS: `className="bg-gradient-to-r from-indigo-600 to-violet-600"` or reference visual-spec.yaml |
| "styled similar to mockup" | Which mockup? What styles? | Reference visual-spec.yaml component name + exact Tailwind classes |
| "appropriate AC" | What is "appropriate"? | List each acceptance criterion explicitly with measurable condition |
| "edge cases handled" | Which edge cases? | Enumerate each edge case: input, trigger condition, expected behavior |
| "as appropriate" | Trigger condition undefined | Specify exactly when and why this applies |
| "as the case may be" | Same vagueness as "as appropriate" | Specify which case, under what condition |

### Forbidden Phrase Detection Protocol

```
BEFORE writing plan to disk:
  1. Scan the entire plan text for each forbidden phrase (case-insensitive)
  2. Also scan for these meta-patterns:
     - Any sentence ending with "etc." or "..."
     - Any bullet point that is less than 10 words (likely too vague)
     - Any "Files:" entry without a concrete file extension
     - Any "Acceptance Criteria" item without a measurable condition
  3. If ANY match is found:
     → Do NOT write the file
     → Fix the violation by replacing with specific detail
     → Re-scan after fix
     → Only proceed when zero violations remain
```

---

## Traceability Protocol

### Post-Brainstorming Mode (Mode A)

Every piece of information from brainstorming must map to a plan section. Use this mapping:

| Brainstorming Source | Plan Destination |
|---|---|
| Step 3 — PM answers to questions | `## Scope`, `## Constraints`, relevant step details |
| Step 4 — Chosen approach + rationale | `## Approach` (full section) |
| Step 4 — Rejected approaches (summary) | `## Approach` (alternatives subsection) |
| Step 5 — Architecture section | `## Architecture` (full section) |
| Step 5 — Data Model section | `## Data Model` (full section) |
| Step 5 — API section | `## API Design` (full section) |
| Step 5 — Implementation plan | `## Implementation Steps` (expanded into detailed steps) |
| Step 5 — Testing strategy | `## Testing Strategy` (full section) |
| Step 5 — Risks and mitigations | `## Risks` (full section) |
| Step 6 — PM modifications to sections | Applied to the respective plan sections |
| Step 6 — PM-added constraints | `## Constraints` + relevant step details |
| PM's stated success criteria | `## Success Criteria` |
| Docker/MCP decisions | `## Infrastructure` or `## Constraints` |
| Workflow detection results | `## Architecture`, step details |

### Traceability Verification

```
AFTER assembling plan content, BEFORE writing:
  FOR EACH row in the traceability table:
    1. Check if the brainstorming source was active (some sections may not apply)
    2. If active: verify the plan destination section contains the mapped content
    3. If content is missing: ADD it to the plan
    4. If content is present but summarized: EXPAND to full detail

  Report format (internal, not shown to PM):
    Trace: Step 3 answers → Scope ✓, Constraints ✓
    Trace: Architecture → Architecture ✓
    Trace: Data Model → Data Model ✓
    Trace: API → API Design ✓
    Trace: Implementation → Steps 1-8 ✓
    ...
    Result: ALL traces resolved. Proceeding to write.
```

---

## Completeness Gate

Before the plan document is written to disk, the AI MUST pass this gate. This is a **hard gate** — the file MUST NOT be written until all checks pass.

**First move: classify the band** (`aid-cp1-gate.sh --classify-only`, see
"Obligations by ceremony band" above). Eight of the checks below are band-scoped
and a `light` plan does not owe them; the verdict per check is tabulated after
the gate.

```
COMPLETENESS GATE — evaluate each check:

SECTION COMPLETENESS:
  1. Does every brainstorming-approved section have a corresponding plan section?
  2. Is every plan section populated (not empty, not placeholder)?
  3. Does the plan contain ALL conditional sections that are relevant?

STEP QUALITY:
  4. Does every step have ALL mandatory fields populated?
  5. Does every step have concrete file paths (not "src/..." or "path/to/...")?
  6. Does every step with effort M or L have ≥3 acceptance criteria?
  7. Does every step with effort M or L have ≥3 edge cases?
  8. Does every "Modify" file reference include approximate line ranges?

DETAIL QUALITY:
  9. Are ALL forbidden shortcut phrases absent from the plan?
  10. Does every API endpoint specify method, path, request schema, response schema, and error codes?
  11. Does every data model entity specify field names, types, and constraints?
  12. Does every implementation detail section contain concrete logic (not just "implement X")?

STRUCTURAL QUALITY:
  13. Are all step dependencies explicitly stated and consistent (no circular deps)?
  14. Are AID roles assigned to every step?
  15. Can Step 1 be executed with zero additional questions?

TRACEABILITY:
  16. Does the traceability verification report show all traces resolved?

CODEBASE GROUNDING (added v2.17.0 — addresses CP1 systematic blind spot
                    where reviewer cannot detect absence of helpers/files
                    that the plan presumes exist):
  17. Has every named external resource in the plan been verified to actually
      exist in the real codebase (or explicitly mapped to a Create step)?
      Resources to ground:
        • Functions, helpers, library exports (e.g., log_info, fsm_check_grandfather)
            → grep for definition; pass with "VERIFIED: defined at <path:line>" or
              "ABSENT: will be created in Step <N>" — never "presumably exists" or
              "should be in <some lib>".
        • File paths referenced in Modify entries
            → ls / stat; pass with "VERIFIED: exists" or "ABSENT: created in Step <N>".
        • Ports (e.g., 8818, 8817)
            → cross-check with running infra (`docker ps`) and existing 88XX
              catalog; flag conflicts BEFORE plan write, not at deploy.
        • Service / container names (e.g., svc-mcp-tg-bot, infra-postgres)
            → docker ps; flag if name collides with running service.
        • External commands (e.g., yq, bats, direnv, docker)
            → command -v; mark as required dependency (Constraints) if not
              already in repo's bootstrap.
        • Env vars (e.g., AID_PLUGIN_PATH, TELEGRAM_ALERT_BOT_TOKEN)
            → grep for export/declaration; document expected source if
              user-supplied.
      Hand-wave like "presumably exists in some lib" or "should be available"
      is a hard fail — replace with concrete grep output or Create-step mapping.

  17a. Backlog ID grounding — for every `T-NNN` ID found in the plan body
       (whole-plan regex `\bT-[0-9]+\b`, no specific field required):
       → `git log --since="24 hours ago" --grep="T-NNN" --all`
       → pass: zero matches in last 24h commits, OR plan explicitly states
         "T-NNN to be allocated at plan-write time"
       → fail: REVISE_REQUIRED with conflict list (commit SHA + msg),
         propose T-NNN reassignment
       Empirical evidence: P021 measure 2026-05-09 — T-132/T-133 reserved by
       commit 1907e77 same morning in wan repo, plan didn't catch it.

  17b. Test directory convention grounding — for every `tests/<dir>/<file>`
       reference in the plan:
       → `find tests/ -type f \( -name "*.py" -o -name "*.ts" -o -name "*.bats" \) -name "*<basename>*"`
         (POSIX `find` — no `fd` dependency)
       → pass: no analog in a sibling test sub-directory
       → fail: REVISE_REQUIRED with consistent location proposal (e.g.,
         "tests/unit/<file> already exists, plan should place new test in
          unit/ not integration/")
       Empirical evidence: P021 — plan said "tests/integration/test_canonical_view.py",
       reality: existing "tests/unit/test_canonical_view.py" with SimpleNamespace.

  17c. DB-field semantics grounding — for every "auto-recompute|automatic"
       claim about a DB field (`<Model>.<field>` regex `[A-Z][a-zA-Z]+\.[a-z_]+`):
       → grep "<field>" in `<project>/db/models.py` or schema files
       → `Column = stored` (requires re-validation for changes)
       → `@property | computed = computed-on-read`
       → pass: claim matches definition
       → fail: REVISE_REQUIRED with correction note (e.g., "validation_warnings
         is a Column (stored), fix requires re-validation of existing records")
       Empirical evidence: P021 — plan assumed automatic visibility of fix,
       reality: stored Column, requires re-validation.

  17d. File removal grounding — for every "delete <file>" claim or
       `must_not_exist: true` assertion:
       → `ls <path>` — file MUST currently exist (otherwise the claim is meaningless)
       → pass: file exists OR mapped to "Create then immediately delete" pattern
       → fail: REVISE_REQUIRED — file does not exist, "delete" is a no-op or
         pre-condition is unmet
       Empirical evidence: P019 — plan said "must_not_exist:
       unifyExtractedSources.ts after fix", reality: file existed with 374 lines
       after EPIC completion, was not deleted.

  17e. CLI invocation grounding — for every cited shell command with arguments
       in Implementation Detail blocks or step examples:
       → Extract pattern: `bash <script> <args>` or `$ <script> <args>`
       → Get actual interface:
            <script> --help      (preferred — exit 0 indicates CLI parse OK)
            head -100 <script>   (fallback — grep usage()/case statements)
       → Compare cited args vs interface — flag mismatches:
            cited:  aid-run-gates.sh --state-file <X>
            actual: aid-run-gates.sh run-all <exec> <epic> <run>
            → REVISE_REQUIRED — proposal: "use aid-run-gates.sh run-all execution.yaml E-XXX-Y_Z R-EXXX-Y"
       Edge cases:
         • Script lacks --help support → fallback to head + grep usage(); if
           even fallback yields no output, mark MANUAL REVIEW + REVISE_REQUIRED
         • Cited script not in codebase (already covered by #17 file paths) →
           skip 17e to avoid double reporting
         • Positional-arg scripts (e.g., aid-fsm.sh transition <from> <to>) →
           parse case statement patterns from head
         • Placeholder args with `<>` brackets → still flag if the flag/subcommand
           itself is not in the interface
         • Same script cited 5× with identical args → flag once (deduplicate)
       Empirical evidence: P035 C1 (2026-05-10) — plan cited --state-file flag
       which does not exist in aid-run-gates.sh; CP1 review caught this defect
       on the 2nd pass — without it, EXECUTE would have failed with
       "Unknown command: --state-file".

STEP OUTPUTS CONCRETENESS (added v2.18.0 — addresses verifier deprivation quality):
  18. Does every plan step's `step.outputs` array contain concrete file paths
      (no `src/**` wildcards, no `*` glob patterns)?
      Wildcards devolve nuanced verifier deprivation (Session B CP2) toward total
      deprivation, defeating the false-positive-prevention purpose.
      REJECT:
        • src/**
        • tests/**/*.test.ts
        • **
      ACCEPT:
        • src/lib/aid-init-execution-yaml.sh
        • services/mcp-tg-bot/server.py
      EXCEPTION: integration test plans where coverage is genuinely directory-
      wide may use suffix patterns (e.g., tests/unit/*.bats) BUT must include
      explicit `step.expected_count` field stating the expected file count.

DESIGN DEFEAT DETECTION (added v2.20.0 — addresses systematic semantic gap
                        where fix paths bypass own validation; activates only
                        for type: bug-fix plans or via mechanical pre-screen):
  19. For plans with `type: bug-fix` in frontmatter, the verifier MUST answer:
      Q1: Which precondition/validation does this plan promise to fix?
          (cite from plan ## Goal or ## Context)
      Q2: Is the new code-path validated by the same precondition (not bypassing it)?
          (analyze Implementation Detail blocks — does new code go through
           the same wrapper/function as the broken path?)
      Q3: If Q2 is "no" — is the bypass explicit + justified in plan body?
          (e.g., "we skip cmd_transition because XYZ — alternate validation in YYY")

      VERDICT MATRIX:
        Q2: yes                          → PASS (new path properly validated)
        Q2: no, Q3: yes (justified)     → PASS_WITH_NOTES (PM judgment call)
        Q2: no, Q3: no (silent bypass)  → REVISE_REQUIRED — design defeat detected

      Empirical evidence: P035 C2 (2026-05-10) — plan promised to fix
      gates_no_generated_by precondition fail. Implementation Detail proposed
      `yq -i '.state = "GATES"'` as transition mechanism — bypassing
      cmd_transition() and therefore bypassing the very validation the plan
      promised to enforce. CP1 review caught C2 on the 3rd pass; without it,
      the fix would have silently failed its own purpose.

      Pre-screening heuristic (mechanical, before LLM judgment) — narrowed
      to STATE-mutation patterns only (NOT release/version mutations):
        IF plan goal/context contains: fix|fail|bypass|precondition|validation
        AND Implementation Detail contains state-mutation in protected files:
              - yq -i ... fsm-state.yaml
              - yq -i ... state.yaml
              - sed -i ... fsm-state.yaml
              - sed -i ... state.yaml
              - direct file write to .aid-o/work/evidence/, work/active.md
            EXPLICIT EXCLUDE (release/version mutations are NOT design defeat):
              - sed -i on CHANGELOG.md, README.md
              - sed/jq on .claude-plugin/*.json, plugin.json, marketplace.json
              - any mutation to files listed in .aid-o/config/policies/release-policy.yaml
                version_files[] (version bump targets — policy file installed by /aid-init)
        AND NO cmd_<wrapper> invocation in same code block
        → AUTOMATIC #19 activation regardless of frontmatter type

      Edge cases:
        • Plan has `type: bug-fix` but does not fix a precondition (e.g., string
          typo) → Q1 returns "no precondition involved" → SKIP #19 graceful
        • Plan fixes 2 different preconditions — answer Q1/Q2/Q3 per-precondition;
          output table instead of single verdict
        • Mixed Q3 evidence (some bypasses justified, some silent) →
          REVISE_REQUIRED for the unjustified parts only
        • Q1 ambiguous (no clear precondition) → escalate to PM clarification
          before #19 verdict

PLAN-AC EXECUTABLE VERIFICATION (added 2026-05 — P037 Phase 2 — addresses
                                  goalpost shift class identified in P019 F1+F2,
                                  P021 F4, P022 F6, P023 F7; orthogonal to #17e
                                  CLI grounding and #19 Design Defeat):
  20. Plan-level AC section ## Acceptance Criteria must use executable verification_pattern.
      Three sub-rules — all must pass:

      20a. Every AC checkbox má sibling verification_pattern yaml block.
           → Extract AC labels: `grep "^- \[ \] AC" <plan>` → list
           → For each AC label: locate next ```yaml fenced block within 5 lines
           → Block must start with `verification_pattern:`
           → Missing block → REVISE_REQUIRED — list ACs missing patterns

      20b. Every verification_pattern.type je jeden z 3 valid values.
           → Valid types: "cmd" | "must_not_exist" | "must_contain"
           → Invalid type (typo like "cmnd" or unsupported "must_match") →
             REVISE_REQUIRED — list invalid AC labels + valid types

      20c. Every pattern arguments are self-contained — no placeholder brackets.
           → REJECT regex matches: `<[a-z_]+>` in cmd/file/regex/expected_exit fields
                (e.g., `cmd: "test <path>"` is REJECT; `cmd: "test ./tests/"` is ACCEPT)
           → REJECT unresolved shell variable refs: `\$[A-Z_]+` without explicit local
             resolution in pattern context (e.g., `$REPO_ROOT/tests/` is REJECT;
             `tests/` is ACCEPT)
           → Placeholder/unresolved → REVISE_REQUIRED with concrete example

      Edge cases:
        • Legacy plans (P001-P036) bez ## Acceptance Criteria section nebo bez
          verification_pattern bloků → CHECK #20 SKIPS (no violation). Detection:
          if plan grep returns 0 AC labels → mark "plan_diff: skipped (legacy)".
        • Plan has ## Acceptance Criteria section but 0 AC checkboxes → REVISE_REQUIRED
          (section is template placeholder — must populate or remove).
        • AC label has yaml block but missing `verification_pattern:` key (just other
          yaml content) → REVISE_REQUIRED for that AC.

      Empirical evidence: P022 F6 (2026-05-09) — plan Step 7 AC specified Playwright
      E2E verification for Aneta+Hana sessions. Implementation substituted backend
      API introspection without recording goalpost shift. tests_pass + scope_check
      passed; DONE reached. Without #20-style executable AC check, the substitution
      was invisible to gates.

      CRITICAL-PATH BRANCH COVERAGE (added 2026-06 — E-046-3_3 — addresses undeclared branches
                                      in handler-adding plans identified in P046 CP1 flow trace):
  21. Every plan step that introduces a new request handler or branch point must declare
      an explicit outcome for every branch (success path, error path, edge cases).
      Undeclared branches → REVISE_REQUIRED.

      Three sub-rules:

      21a. For every handler-pattern match in Implementation Detail, identify the branch
           structure (success / auth-fail / validation-fail / error). Every branch listed
           must have a named outcome (return code, response, side-effect, or log entry).

      21b. For every branch: either it has an explicit outcome in the plan, OR the plan
           explicitly marks it N/A with a one-line justification.
           Silent omission (no outcome, no N/A) → REVISE_REQUIRED.

      21c. "Undeclared branch" verdict is LLM-judgment — not hard-gated. Frame it
           honestly: "Possible undeclared branch detected — PM should confirm or add
           explicit outcome." Do NOT block EPIC generation on #21 alone.

      Pre-screening heuristic (mechanical, before LLM judgment) — auto-activates on
      handler-adding diffs (same pattern as #19 handler regex):
        IF Implementation Detail or Artifacts contains any of:
              - @app\.<method>\(
              - @router\.<method>\(
              - add_route(
              - def \w+\(.*request
              - async def \w+\(.*request
        → AUTOMATIC #21 activation regardless of plan type

      Verdict matrix:
        All branches declared                  → PASS
        Some branches declared, some N/A       → PASS
        Silent omission (no outcome, no N/A)   → REVISE_REQUIRED (advisory — see 21c, PM can override)
        LLM uncertain about branch count       → PASS_WITH_NOTES (PM confirmation)

      Empirical anchor: P046 CP1 flow trace — request→auth-gate→execution→sink had
      an undeclared auth-fail branch that was caught only post-implementation when
      missing error handling caused silent data loss on auth-fail path.

      Test fixture (for #21 pre-screen activation test): see
      `scripts/tests/bats/test-plan-writing-rules.bats` fixture `handler_fixture.md`
      — a minimal plan with a FastAPI handler that activates the pre-screen.

EVALUATION:
  COUNT checks passed out of 28 (24 existing + 20a + 20b + 20c + 21).
  Band-scoped checks (4, 6, 7, 8, 12, 20a, 20b, 20c) are N/A for a `light`
  plan and count as PASS — see "Which checks apply to which band" below.
  IF all 28 pass → write plan to disk
  Note: Check #19 activates only for `type: bug-fix` plans or via pre-screening
  heuristic above. For non-applicable plans, mark #19 as N/A (counts as PASS).
  Note: Check #20 skips for legacy plans (no AC section found); not a violation.
  Note: Check #21 activates only when handler patterns are detected in Implementation Detail or Artifacts. For non-applicable plans, mark #21 as N/A (counts as PASS). LLM-judgment only — verdict is advisory, not hard-gated.
  IF any check fails → fix the failing checks, re-evaluate, repeat until all pass
  DO NOT write a partial or incomplete plan. DO NOT skip failed checks.
  DO NOT tell PM "the plan is mostly complete" — it is complete or it is not.
```

### Which checks apply to which band

Every one of the 28 checks carries a verdict. A check is **universal** (it runs
whatever the plan touches) or **band-scoped** (it runs for `full` and `medium`,
and is not asked of a `light` plan). No check is silently "universal by default":
a check with no verdict here is a defect in this document, not a permission.

| Check | Verdict | Why |
|---|---|---|
| 1, 2, 3 — section completeness | universal | an empty or missing section is a hole at any size |
| 4 — mandatory fields per step | band-scoped | the field SET itself differs by band (table above) |
| 5 — concrete file paths | universal | the paths are what the band is classified FROM |
| 6 — ≥3 AC for M/L steps | band-scoped | |
| 7 — ≥3 edge cases for M/L steps | band-scoped | `light` owes no edge cases at all |
| 8 — line ranges on Modify entries | band-scoped | *cancellation candidate — see below* |
| 9 — no forbidden phrases | universal | |
| 10, 11 — API and data-model completeness | universal | both already activate only when the section exists |
| 12 — concrete implementation detail | band-scoped | `light` may answer in one sentence |
| 13, 14, 15 — structural quality | universal | generation reads these; a broken graph breaks at any size |
| 16 — traceability report | universal | |
| 17, 17a, 17b, 17c, 17d, 17e — codebase grounding | universal | a plan that names something that does not exist is wrong at any size; this is the anti-fabrication core |
| 18 — concrete step outputs | universal | |
| 19 — design-defeat detection | universal | already conditional (`type: bug-fix` or its own pre-screen) |
| 20a, 20b, 20c — executable plan-level AC | band-scoped | |
| 21 — critical-path branch coverage | universal | already conditional (handler pre-screen), and advisory |

**Cancellation candidates — PM decides, per item, never the plan author.**
Check **8** (line ranges on `Modify` entries) has never been mechanically
enforced and a stale range is worse than none. It is proposed for cancellation
and stays in force until the PM says otherwise.

### Gate Failure Recovery

```
IF Completeness Gate fails:
  1. Identify which checks failed
  2. For each failure:
     - If missing detail: add the detail from brainstorming context
     - If forbidden phrase: replace with specific content
     - If structural issue: fix the structure
  3. Re-run the gate
  4. Maximum 3 gate iterations. If still failing after 3:
     → Write the plan with a WARNING section at the top listing unresolved items
     → Ask PM to review the flagged items
```

---

## Standalone Mode Protocol (Mode B)

When invoked via `/aid-plan write` without prior brainstorming:

### Phase 1: Input Analysis

```
1. Read the input specification (file path or inline text from PM)
2. Identify:
   - What is being built or changed
   - Which parts of the codebase are affected
   - What constraints exist
3. Present a brief analysis (3-5 lines) to PM for confirmation
```

### Phase 2: Codebase Deep-Dive

```
1. Read project.yaml for tech stack and conventions
2. Identify files that will be created or modified:
   - Glob for existing files in relevant directories
   - Read key files to understand current patterns
   - Note existing tests, configs, and documentation
3. Build a mental model of the affected code area
```

### Phase 3: Clarification (max 5 questions)

```
1. Ask up to 5 targeted questions (one at a time, multiple choice preferred)
2. Questions should cover gaps in the specification:
   - Ambiguous requirements
   - Missing scope boundaries
   - Unclear technical decisions
3. Skip this phase if the specification is unambiguous
```

### Phase 4: Plan Writing

```
1. Assemble plan content following the same Document Structure as Mode A
2. Fill all sections from the specification + codebase analysis + PM answers
3. Run Forbidden Phrase Detection
4. Run Completeness Gate
5. Write plan to disk
6. Present summary to PM
```

---

## Section Writing Guidelines

### Architecture Section

Do NOT write a generic architecture overview. Write a concrete, project-specific architecture that references actual files and components.

```
GOOD:
  "The webhook system adds three components to the existing Express app:
   - WebhookRegistry (src/webhooks/registry.ts) — stores subscriptions in PostgreSQL
     using the existing Prisma ORM. New model: WebhookSubscription.
   - WebhookDispatcher (src/webhooks/dispatcher.ts) — BullMQ job that reads pending
     events from the webhook_events table and delivers them via HTTP POST.
   - WebhookController (src/webhooks/controller.ts) — REST endpoints for CRUD
     operations on subscriptions. Mounts at /api/v1/webhooks."

BAD:
  "The webhook system will have a registry, dispatcher, and controller component
   following standard patterns."
```

### Data Model Section

Include EVERY field, type, constraint, and relationship. Not just entity names.

```
GOOD:
  "WebhookSubscription:
    - id: UUID (PK, auto-generated)
    - url: string (1-2048 chars, must be valid HTTPS URL)
    - events: string[] (non-empty, values from EventType enum)
    - secret: string (32-byte hex, auto-generated, used for HMAC-SHA256 signatures)
    - active: boolean (default: true)
    - created_at: timestamp (auto-set)
    - updated_at: timestamp (auto-updated)
    - owner_id: UUID (FK → users.id, ON DELETE CASCADE)
    Indexes: (owner_id), (events) using GIN
    Invariants: URL must be HTTPS in production, HTTP allowed in development"

BAD:
  "WebhookSubscription:
    - url, events, secret, active, timestamps
    Relations: belongs to User"
```

### Implementation Detail in Steps

Each step's Implementation Detail must contain enough information for an agent to write code without asking questions.

```
GOOD:
  "Create POST /api/v1/webhooks endpoint:
   1. Validate request body with Zod schema: { url: z.string().url(), events: z.array(z.nativeEnum(EventType)).min(1) }
   2. Generate secret: crypto.randomBytes(32).toString('hex')
   3. Create WebhookSubscription via Prisma: prisma.webhookSubscription.create({ data: { ...validated, secret, ownerId: req.user.id } })
   4. Return 201 with { id, url, events, active, created_at } — do NOT return secret in response
   5. If URL is not HTTPS and NODE_ENV === 'production': return 422 with error 'HTTPS required for webhook URLs'"

BAD:
  "Create the webhook creation endpoint following REST conventions.
   Validate input, generate a secret, save to database, return the result."
```

---

## Anti-Circumvention Rules

These rules exist because AI systems systematically try to skip detail work. Each rule addresses a known failure mode.

```
RULE AC-1: DO NOT summarize approved sections.
  Failure mode: AI condenses a 20-line architecture discussion into 3 lines.
  Fix: Copy the full approved content. Expand, never compress.

RULE AC-2: DO NOT use the plan template's "High-Level Steps" table format.
  Failure mode: AI reverts to the simple table format because it's easier.
  Fix: Every step MUST use the detailed per-step template from this skill.

RULE AC-3: DO NOT defer detail to the EPIC.
  Failure mode: AI writes "details will be specified in the EPIC."
  Fix: The plan IS the detail source. The EPIC is a structural wrapper.

RULE AC-4: DO NOT skip sections because "it's obvious."
  Failure mode: AI omits error handling because "standard HTTP errors."
  Fix: Write the specific error handling for THIS feature.

RULE AC-5: DO NOT generate the plan in a single pass.
  Failure mode: AI writes the entire plan in one shot and misses details.
  Fix: Write section by section. After each section, verify it against
       the brainstorming source before moving to the next.

RULE AC-6: DO NOT claim the gate passed without actually checking.
  Failure mode: AI says "Completeness Gate: all checks pass" without verifying.
  Fix: Enumerate each check with its result. Show the work.

RULE AC-7: DO NOT use relative references like "as described above."
  Failure mode: Agent dispatch extracts individual sections — "above" doesn't exist.
  Fix: Each step section must be self-contained. Repeat key details or use
       explicit section references ("see ## Architecture → Components").

RULE AC-8: DO NOT merge multiple logical changes into one step.
  Failure mode: AI writes "Step 3: Implement API endpoints and add validation
                and write tests and update documentation."
  Fix: Each step = one logical unit of work for one AID role. Split if needed.

RULE AC-9: DO NOT omit file paths because "the agent will figure it out."
  Failure mode: AI writes "Create the migration file" without specifying where.
  Fix: "Create: prisma/migrations/20260227_add_webhooks/migration.sql"

RULE AC-10: DO NOT provide less detail for "simple" steps.
  Failure mode: AI writes detailed steps for complex work but one-liners for
               "simple" steps like config changes or docs updates.
  Fix: ALL steps use the same detailed template. Even S-effort steps get
       concrete file paths, acceptance criteria, and implementation detail.
```

---

## MUST Rules

1. **ALWAYS use the detailed per-step template** — never fall back to the high-level steps table
2. **ALWAYS populate all mandatory fields per step** — no empty or placeholder fields
3. **ALWAYS run the Completeness Gate before writing** — hard gate, no exceptions
4. **ALWAYS run Forbidden Phrase Detection before writing** — hard gate, no exceptions
5. **ALWAYS run Traceability Verification in post-brainstorming mode** — every brainstorming output must map to a plan section
6. **NEVER summarize or compress approved brainstorming sections** — copy and expand, never condense
7. **NEVER defer detail to the EPIC or other documents** — the plan is self-contained
8. **NEVER skip sections that were discussed in brainstorming** — if it was discussed, it's in the plan
9. **NEVER use any phrase from the Forbidden Shortcuts table** — hard failure
10. **NEVER write the plan without verifying AC-1 through AC-10** — each rule must be satisfied
11. **ALWAYS make each step section self-contained** — agents receive individual sections, not the whole plan
12. **ALWAYS follow the language split** — plan document in configured document_language, conversation in PM's language
13. **ALWAYS write the plan to `.aid-o/plans/`** — never to any other location
14. **ALWAYS generate proper plan IDs** — per `skills/run-management.md` → ID System (pre-allocated at brainstorming Step 1)
15. **ALWAYS delete the interim document after successful plan write** — remove `.aid-o/work/interim-P{NNN}.md` if it exists (cleanup from brainstorming context persistence)
16. **ALWAYS include a documentation update step** — if the plan changes API, models, architecture, or workflow, the LAST implementation step (before E2E) MUST update shared documentation (Docusaurus, README, API docs). For vulcan ecosystem projects, this means updating `/opt/eco/docs/docs/` or project-level docs. No exceptions — undocumented changes are incomplete changes.
17. **NEVER write a summary section for a human into the plan** — no `Stakeholder Brief`, `Executive Summary`, `Human Review Summary` or `Shrnutí pro PM`. The PM's page is RENDERED from the plan's own facts (`lib/aid-plan-summary.sh`, published by `/aid-plan`), so a hand-written one is a second copy that nothing checks and that is free to flatter the plan. `aid-plan-lint.sh` reports all four headings.

---

## Integration with Dispatch Protocol

The plan document is consumed by `skills/pipeline.md` § 4 → Source Plan Integration (Variant B). The dispatch protocol:

1. Reads the plan via `plan_ref` or `source_plan` field
2. Matches the current step to a plan section using header patterns: `### Step {N}`, `## Step {N}`, keyword matching
3. Extracts the matched section and injects it into the agent prompt

**Implication for this skill:** Step headers MUST follow the pattern `### Step {N}: {Name}` to enable reliable section matching. The `{N}` must be a sequential integer starting from 1.

**Pipeline compatibility:** The bash pipeline scripts (`aid-auto-pipeline.sh`, `aid-plan-to-epic.sh`) require:
- A `## Implementation Steps` (or `## High-Level Steps`) section header — or at minimum step/task headers directly in the document
- Step headers as `### Step {N}: {Descriptive Name}` (preferred) — `## Task {N}:` and `## Step {N}:` are also accepted but not recommended
- Each step should have an `**Objective:**` field — the pipeline falls back to the header text after the colon, then to the first non-empty line of step content

---

## Post-Write Handoff

After the plan is written to disk and confirmed to PM, present next steps. This handoff applies to BOTH Mode A (post-brainstorming) and Mode B (standalone).

**Present to PM — Handoff Summary:**
```
Plan {plan_id} complete. Here's what was decided:

Topic: {topic}
Approach: {chosen approach name} — {1-line summary}
Scope: {N} design sections approved | Effort: {S/M/L} | Risk: {L/M/H}
Key decisions:
  - {most significant decision 1}
  - {most significant decision 2}
  - {most significant decision 3}

Plan: .aid-o/plans/{plan_id}-{topic}.md
Steps: {step_count} | Roles: {unique roles}
Quality gates: passed (forbidden phrases: 0, completeness: {N}/{total})

Next Steps:
(A) /aid-plan --epic {plan_path} — generate EPIC + execution artifacts
(B) /aid-run {plan_path} — generate EPIC and start execution (manual mode)
(C) /aid-run --auto {plan_path} — generate EPIC and start autonomous execution
    ⚠ Requires autonomous_mode: true in .aid-o/config/permissions.yaml
(D) Review plan — open .aid-o/plans/{plan_id}-{topic}.md
(E) Re-open brainstorming — add/modify requirements (interim doc preserved)
(F) Stop — plan saved, resume anytime with /aid-plan --resume {plan_id}
```

**Option A — Generate EPIC:**
Runs `aid-auto-pipeline.sh` (via Script Execution Protocol) which creates all artifacts
deterministically: EPIC files, plan.json, run.md, and queue entries.

**Option B — Manual Execution:**
Generates EPIC (same as A) then immediately starts `/aid-run` in manual mode.
PM approves each escalation.

**Option C — Autonomous Execution:**
Generates EPIC then starts `/aid-run --auto`. S-effort fixes auto-approved,
M-effort uses defaults, L-effort always escalates to PM.
Requires `autonomous_mode: true` in `.aid-o/config/permissions.yaml`.

**Option D — Review plan:**
PM reviews the plan file, makes edits if needed, then runs option A/B/C when ready.

**Option E — Re-open brainstorming (Mode A only):**
If invoked from brainstorming, return to brainstorming Step 3 with existing context.
New requirements ADD to the plan (never overwrite approved sections).
If invoked standalone (Mode B), suggest `/aid-plan` to explore alternatives.

**Option F — Stop here:**
```
Plan saved: .aid-o/plans/{plan_id}-{topic}.md
Resume anytime: /aid-plan --resume {plan_id}
Or generate EPIC later: /aid-plan --epic {plan_path}
```

---

## Reference Files

- `commands/aid-plan.md` — unified command that invokes this skill (write mode or brainstorm Step 8)
- `skills/brainstorming.md` — brainstorming skill (upstream — provides approved sections)
- `skills/pipeline.md` § 4 — agent dispatch (downstream — injects plan sections into agent prompts)
- `{plugin_path}/scripts/aid-auto-pipeline.sh` — pipeline script that creates EPIC files, plan.json, run.md, and queue entries from the plan document
- `defaults/templates/plan.md` — base plan template (this skill extends it)
- `skills/run-management.md` — plan lifecycle (archiving, location rules)
- `defaults/orchestration.yaml` — `language.document_language`, the only home of the document
  language setting (there is no `language.yaml`)

---

**Last Updated:** 2026-08-22

## Plan-boundary note

Under `plan_branch` the Auditor, Curator, Simplifier and Reporter are
**plan-final** roles: dispatched once per plan, at the boundary, against the
frozen candidate. CP2 and CP3 remain per EPIC. Under
`legacy_epic_release_mode` the previous per-EPIC cadence is unchanged. Mode is
read from the plan's committed lifecycle manifest, never inferred.
