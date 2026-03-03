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
```

**Examples:**
```
/aid-do "add a console.log to debug auth flow"
/aid-do "fix typo in README"
/aid-do "add login button with Google OAuth"
```

## Flow

### Step 1: Auto-Init

1. If `.aid-o/` does not exist → run `/aid-init` automatically (silent, no PM interaction)
2. If `.aid-o/work/quick/` does not exist → `mkdir -p .aid-o/work/quick/`

### Step 2: Scope Estimate

Analyze the task description to estimate scope:

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
     ⚠ Scope exceeded Fast Mode threshold:
       Files changed: {N} (threshold: 5)
       Layers: {layer_list} (threshold: 3)

     Task completed but consider creating a retroactive plan for documentation.
     ```

### Step 5: Quick Log

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

### Step 6: Git Commit

1. Stage changed files: `git add {changed_files}`
2. Commit: `feat: {task description} (Q-{NNN})`
3. Pre-commit hooks run gates automatically (if configured)

### Step 7: Output

```
Done: Q-{NNN} ({duration}s, {file_count} files)
Log: .aid-o/work/quick/Q-{NNN}.md
Commit: {hash}
```

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

## Important

- **No FSM** — Fast Mode bypasses the state machine entirely
- **No EPIC** — no evidence directory, no run file, no plan.json
- **Quick log only** — `.aid-o/work/quick/Q-NNN.md` is the only artifact
- **Auto-increment Q counter** — scan existing files, never overwrite
- **Git commit is mandatory** — every `/aid-do` produces exactly one commit
- **Escalation is advisory** — PM always has final say
- If `$ARGUMENTS` is empty → ask PM: "What task should I implement?"
