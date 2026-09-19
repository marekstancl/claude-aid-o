---
name: aid-do
description: Fast Mode — implement small tasks with minimal overhead (<2 min)
user_invocable: true
---

Implement a task directly with minimal overhead. No planning, no EPIC, no FSM — just do it and log it.

For tasks estimated under 2 hours of work. Creates a quick log entry (`Q-NNN.md`) and auto-escalates to EPIC mode if scope grows beyond threshold.

## Usage

```
/aid-do <task description>
/aid-do --ui <task description>
```

**Examples:**
```
/aid-do "add a console.log to debug auth flow"
/aid-do "fix typo in README"
/aid-do "add login button with Google OAuth"
/aid-do --ui "redesign the ScreenG component"  # redirected to /aid-run
```

## Flags

| Flag | Behavior |
|------|----------|
| `--ui` | Marks task as existing_ui change -- redirects to /aid-run (contract enforcement required) |
| `--no-ui-check` | Bypass existing_ui detection (for tasks matching the pattern but not needing contract) |

## Flow

### Step 1: Auto-Init + Plugin Verification

1. If `.aid-o/` does not exist → run `/aid-init` automatically (silent, no PM interaction)
2. If `.aid-o/work/quick/` does not exist → `mkdir -p .aid-o/work/quick/`
3. Verify `plugin_path` from `.aid-o/config/plugin.yaml` — if missing or stale, re-discover via glob (see `skills/agent-protocol.md Script Execution section)

### Step 2: Scope Estimate

**Existing UI detection (first check):**

If the task description contains `existing_ui` OR the `--ui` flag was passed (and `--no-ui-check` was NOT passed):
- This indicates a change to existing frontend UI requiring a `ui_change_contract`
- `/aid-do` cannot safely scope-limit UI changes (no contract enforcement mechanism)
- **Refuse with redirect:**
  ```
  Use /aid-run for existing UI changes

  /aid-do cannot safely deliver existing UI changes -- they require a
  ui_change_contract envelope (path/sha256/schema_version) to enforce
  typed delta, which is only wired in the full EPIC pipeline.

  Redirect to /aid-run:
    /aid-plan "describe your UI change"  -- brainstorm -> plan with contract
    /aid-run                             -- execute with companion baseline + FSM guard

  Why this matters: undeclared visual changes cannot be verified against
  the baseline. /aid-run's existing_ui guard catches regressions; /aid-do
  bypasses it.

  False-positive tradeoff: if your description accidentally contains
  'existing_ui' but this is not a UI change, add --no-ui-check to bypass
  this detection.
  ```
- Stop. Do NOT proceed with implementation.

**Tradeoff:** explicit `existing_ui` text OR `--ui` flag triggers redirect; task descriptions
that modify UI components without this marker are NOT redirected (too many false positives
for UI fixes, typo corrections, and minor adjustments that do not need contract enforcement).

**Standard scope analysis (runs only if not redirected above):**

1. Identify affected files and architectural layers (frontend, backend, DB, config, infra)
2. Estimate file count and layer count from task description
3. If estimated scope > 5 files OR 3+ layers:
   - Present to PM:
     ```
     Scope estimate: ~{N} files across {M} layers ({layer_list})

     This looks like it might benefit from planning.
       (A) Continue with /aid-do (I know what I'm doing)
       (B) Escalate to /aid-plan (brainstorm + plan first)
     ```
   - If PM chooses (B) → hand off to `/aid-plan` with the task description, stop here
4. If within threshold → proceed directly

### Step 3: Implement

1. Record start time
2. Implement the task directly — write code, modify files, run tests
3. Follow existing project patterns and conventions
4. Run available test/lint commands if configured in `.aid-o/config/project.yaml`

### Step 4: Post-Implementation Check

After implementation, verify actual scope:

1. Run `git diff --stat` to count changed files
2. Detect layers from changed file paths:
   - `src/components/`, `src/pages/`, `*.tsx` → frontend
   - `src/api/`, `src/server/`, `routes/` → backend
   - `migrations/`, `prisma/`, `*.sql` → database
   - `*.yaml`, `*.json` (config), `Dockerfile` → config/infra
3. If actual changes > 5 files OR 3+ layers:
   - Warn PM:
     ```
     ⚠ Scope exceeded Fast Mode threshold
       Files: {N} (limit: 5) | Layers: {layer_list} (limit: 3)

     Task completed. Consider:
       • /aid-plan "{task}" — create retroactive plan
       • git diff HEAD~1 — review all changes
     ```

### Step 5: Review Check (CP6)

Fast mode is reviewed by the same mechanism as a step of a run (P094): a
deterministic step check over the working tree, then the reviewer round of
`skills/step-review-roles.md`, advisory. Skip this step only when
`review_checkpoints.cp6_fast_mode_review: false` (`prepare` then exits 3 and
says so).

1. Create this run's evidence directory. The id keeps two fast-mode runs
   apart: `<UTC timestamp>-<short HEAD sha>`.

   ```bash
   DO_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(git rev-parse --short HEAD)"
   DO_DIR="$(git rev-parse --show-toplevel)/.aid-o/work/evidence/do/${DO_ID}"
   mkdir -p "$DO_DIR"; printf '%s\n' "$ARGUMENTS" > "$DO_DIR/task.md"
   bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp6 --worktree \
     --dod-file "$DO_DIR/task.md" --evidence-dir "$DO_DIR"
   ```

   Inside a plan worktree the range is that checkout's working tree; the
   evidence directory resolves to the state root. Two runs in the same second
   on the same HEAD collide on the id: the step check refuses to overwrite a
   closed index and the command says to wait a second.

2. Read the verdict the step check printed:
   - `no_change` (clean tree) or `skip` (small, clean, no security pattern):
     say so in one line and dispatch nothing.
   - `review` / `review+security`: run the round under `${DO_DIR}/cp6/`
     exactly as the controller instruction in
     `scripts/lib/aid-review-adapter-claude.md` says, with
     `<review>` = `--checkpoint cp6 --evidence-dir "$DO_DIR"`:
     `prepare --round 1`, one dispatch per expected role (focus
     `cp6-<role>`), `collect`, `close`.

3. `close` reports the verdict. `pass` → continue to Step 6. `fail` →
   report to the PM (advisory, no ESCALATION in Fast Mode) and continue:
   ```
   ⚠ Code Review Issues (Advisory)

   Checkpoint CP6 found (${DO_DIR}/cp6/round-1/merged.json):
     - [{severity}] {claim} — {evidence}

   Options:
     • Fix: say "fix" — the implementer fixes the open findings (fix_of: <round dir>),
       then a confirmation round (prepare --round 2)
     • Review: git diff
     • Escalate: /aid-plan "{task}" for full pipeline
   ```
   When the PM says fix, the fix paragraph of the adapter applies with the
   cp6 round directory. Nothing in the FSM reads `evidence/do/`: a failed
   fast-mode round blocks no transition.

### Step 6: Quick Log

1. Determine next Q number:
   - Scan `.aid-o/work/quick/Q-*.md` for highest number
   - Increment by 1 (start at Q-001 if none exist)
2. Get commit hash from `git log -1 --format=%h` (after commit)
3. Write `.aid-o/work/quick/Q-{NNN}.md`:

```markdown
---
id: Q-{NNN}
task: "{task description}"
started_at: {ISO 8601}
duration_s: {seconds}
files_changed:
  - {file1}
  - {file2}
commit: {short_hash}
escalated_to_epic: false
---

## What was done
{implementation summary — 3-5 sentences}
```

### Step 7: Git Commit

1. Stage changed files: `git add {changed_files}`
2. Commit: `feat: {task description} (Q-{NNN})`
3. Pre-commit hooks run gates automatically (if configured)

### Step 8: Output

The final turn is the **Finished** card of `skills/communication.md` — that file
owns the card's fields and their order, and this one does not restate them. What
`/aid-do` adds is a single closing detail line carrying the quick-task id, the
counters, the commit and the log path:

```
Q-{NNN} · {file_count} files · {duration}s · commit {hash} · log .aid-o/work/quick/Q-{NNN}.md
```

It is the LAST line, under the card, never above it. Do not paste the diff or
the gate log. A filled-in example of the whole turn:

```
Hotovo: /aid-status už neukazuje smazané plány.
Změnilo se: přehled zobrazí jen plány, které mají živý worktree.
Ověřeno: test-status-recipes.bats (12/12) a lint prošly.
Další krok: nic dalšího není potřeba.

Q-041 · 2 files · 74s · commit 9f3c1ab · log .aid-o/work/quick/Q-041.md
```

If the task hit an auto-escalation trigger (below) the last line stays a
**suggestion**: name it in `Další krok`, never convert it into a blocking
question the PM did not ask for. If the task could not be finished, render the
**Blocked or failed** card instead — same file, same ordering rule.

## Auto-Escalation Triggers

These conditions suggest the task should have been an EPIC:

| Trigger | Detection | Action |
|---------|-----------|--------|
| > 5 files changed | `git diff --stat` post-impl | Warn PM, suggest retroactive plan |
| 3+ layers touched | Path analysis of changed files | Warn PM, suggest retroactive plan |
| DB migration created | Migration file in changed files | Warn PM |
| PM says "this is bigger" | Explicit PM statement | Offer `/aid-plan` handoff |

Escalation is always a **suggestion** — PM decides whether to act on it.

## Reference Files

- `skills/pipeline.md` — orchestration context (Fast Mode is outside FSM)
- `commands/aid-plan.md` — escalation target for complex tasks
- `commands/aid-init.md` — auto-init on first use

### Relationship to /aid-run --streamlined

/aid-do is Fast Mode for sub-2-minute tasks. It is *conceptually* analogous to
`/aid-run --streamlined` — a single low-overhead path with no per-step CP2
review round — but it bypasses the FSM entirely. Unlike `/aid-run
--streamlined`, /aid-do does NOT write `fsm-state.yaml` or `compliance.json`,
does NOT set `streamlined_mode` / `coverage_mode`, and is NOT subject to
`cmd_done_advance` Component D enforcement (streamlined integration-review or
abandoned-but-shipped checks). Its artifacts are `.aid-o/work/quick/Q-NNN.md`,
the review evidence under `.aid-o/work/evidence/do/<id>/` and one git commit. The `coverage_mode: "streamlined"` accounting and Component D
checks apply only to `/aid-run --streamlined`, which walks the full
plan→EPIC→run FSM pipeline.

## Important

- **No FSM** — Fast Mode bypasses the state machine entirely
- **No EPIC** — no run file, no plan.json; the only evidence directory is the
  review's, `.aid-o/work/evidence/do/<id>/` (Step 5)
- **Quick log** — `.aid-o/work/quick/Q-NNN.md` plus the review evidence
- **Auto-increment Q counter** — scan existing files, never overwrite
- **Git commit is mandatory** — every `/aid-do` produces exactly one commit
- **Escalation is advisory** — PM always has final say
- If `$ARGUMENTS` is empty → ask PM: "What task should I implement?"


**Last Updated:** 2026-09-19

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
