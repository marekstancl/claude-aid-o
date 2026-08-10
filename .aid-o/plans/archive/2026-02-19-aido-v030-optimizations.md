# AIDo v0.3.0 — Optimizations & Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all critical bugs in the orchestration engine, optimize token consumption and speed, complete the lifecycle management, improve UX/onboarding, and add cross-project knowledge sharing.

**Architecture:** All changes are to markdown/YAML files within the `plugins/aid-orchestrator/` directory (agents, commands, skills, defaults). No compiled code. Verification is via `claude plugin validate` and manual command testing.

**Tech Stack:** Markdown, YAML, JSON (Claude Code plugin system)

**Source feedback:** User backlog (14 items), test-aid-project lessons (10 entries), ai-orchestrator PROP-001 to PROP-013 (13 proposals), active-work.md (3 next steps). Total: 31 unique items consolidated into 25 tasks across 5 phases.

---

## Phase 1: Fix Broken Core (P1 — Critical Bugs)

These fixes address fundamental engine failures that make the orchestration unreliable. Nothing else should be implemented until these work.

---

### Task 1: Fix DONE State — Lessons-Learned, Command-History, Session Status, Stage Log

**Why:** After a successful EPIC run, lessons-learned.md stays empty (PROP-001), command-history.md stays empty (PROP-003), session status remains "active" with 0% completion (PROP-002), and stage_log.jsonl ends with `"result": "pending"` (PROP-010). The DONE state in epic-orchestration.md is missing critical file-write operations.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (DONE state section)
- Modify: `plugins/aid-orchestrator/agents/lessons-extractor.md` (output handling)
- Modify: `plugins/aid-orchestrator/skills/session-management.md` (session closure)

**Step 1: Read current DONE state implementation**

Read the DONE state section in `skills/epic-orchestration.md`. Identify what currently happens vs. what's missing.

Current DONE state actions (from code review):
- Merge branches
- Update EPIC status
- Archive session
- Generate final_report.md
- Dispatch Curator + Auditor in parallel
- Index to memory (if enabled)
- Send completion status
- Check epic-queue

Missing actions (the bugs):
- Write lessons to `lessons-learned.md` file (only writes to Qdrant, fallback JSONL, but never the .md file)
- Write commands to `command-history.md`
- Update session frontmatter `status: completed` and `Completion: 100%`
- Write final DONE entry to `stage_log.jsonl` with `"result": "success"`

**Step 2: Add file-based lessons-learned write to DONE state**

In `skills/epic-orchestration.md`, locate the DONE state section. After the Qdrant indexing block (or its JSONL fallback), add an explicit step that ALWAYS writes to lessons-learned.md regardless of Qdrant availability:

```markdown
### Lessons-Learned File Update (ALWAYS — independent of Qdrant)

After dispatching lessons-extractor agent, parse its output and append new entries
to `.aid-o/04-engine/lessons-learned.md`:

1. Read current `lessons-learned.md`
2. Parse lessons-extractor output for the "Lessons Learned" table rows
3. For each new lesson:
   - Check for duplicates (>80% text overlap with existing entries)
   - If not duplicate: append row to the markdown table
4. Write updated `lessons-learned.md`

```yaml
# Example append format:
| {date} | {lesson_text} | {context_from_epic_id} |
```

This step runs ALWAYS, even if Qdrant indexing succeeded. The .md file is
the durable, human-readable record. Qdrant is the searchable index.
```

**Step 3: Add file-based command-history write to DONE state**

In the same DONE state section, after the lessons-learned write, add:

```markdown
### Command-History File Update

After dispatching lessons-extractor agent, parse its output and append new entries
to `.aid-o/04-engine/command-history.md`:

1. Read current `command-history.md`
2. Parse lessons-extractor output for the "Working Commands" table rows
3. For each new command:
   - Check for duplicates (exact command string match)
   - If not duplicate: append row to the markdown table
4. Write updated `command-history.md`

```yaml
# Example append format:
| {command} | {purpose} | Yes |
```
```

**Step 4: Add session status update before archive**

In the DONE state section, BEFORE the "Archive session" step, add:

```markdown
### Session File Status Update (before archive)

Before archiving the session file:

1. Read the active session file from `.aid-o/04-engine/sessions/S-*.md`
2. Update YAML frontmatter:
   - `status: completed`
   - `completed: {ISO 8601 timestamp}`
3. Update the `Completion:` line in the body to `100%`
4. Update the last phase status to `done`
5. Write the updated session file
6. THEN proceed with archive (copy to archive/ directory)

The archived copy MUST reflect the completed status. Never archive a session
that still shows `status: active`.
```

**Step 5: Add final stage_log entry**

In the DONE state section, at the very end (after all other actions), add:

```markdown
### Final Stage Log Entry

Append the closing DONE entry to `stage_log.jsonl`:

```json
{"state": "DONE", "timestamp": "{ISO 8601}", "result": "success", "epic_id": "{epic_id}", "run_id": "{run_id}", "summary": "EPIC completed successfully. {step_count} steps, {gate_count} gates, {retry_count} retries."}
```

This MUST be the last line in the stage log. The `result` field MUST be
`"success"` (not `"pending"`).
```

**Step 6: Fix Qdrant project tagging (cross-project knowledge)**

All Qdrant writes in the DONE state MUST include `project_name` metadata.
This is critical for cross-project knowledge sharing (see Task 22).

In `skills/epic-orchestration.md`, update the Qdrant store calls in the
Lessons Learned Collection section:

```markdown
### Qdrant Project Tagging (MANDATORY for all writes)

Every `qdrant-store` call MUST include `project_name` in metadata:

```json
{
  "collection_name": "aid-orchestration-log",
  "data": "{lesson_text}",
  "metadata": {
    "project_name": "{from project-profile.yaml → project_name}",
    "epic_id": "{epic_id}",
    "step_id": "{step_id}",
    "type": "lesson|command|decision|pattern",
    "category": "{category}",
    "timestamp": "{ISO 8601}"
  }
}
```

**Why:** Qdrant is the cross-project knowledge store. Without `project_name`,
lessons from different projects are indistinguishable. Agents reading Qdrant
at IDLE/EXECUTING states filter by relevance but display source project for
traceability.
```

Also update `skills/memory-mcp.md` — the `memory_store()` abstraction function
must accept and pass through `project_name`:

```
memory_store(type, content, metadata):
  metadata.project_name = read_project_profile().project_name  # AUTO-INJECT
  ...proceed with qdrant-store or file fallback...
```

**Decision rationale:** PM decided that Qdrant serves as the global cross-project
knowledge database. Local .md files remain per-project (human-readable, offline backup).
Qdrant entries tagged with project_name enable semantic search across all projects.

**Step 7: Update lessons-extractor agent to clarify write responsibility**

In `agents/lessons-extractor.md`, update the "Important" section to clarify the responsibility chain:

Change:
```
- Do NOT modify any files — only read and report; parent agent updates workspace files
```

To:
```
- Do NOT modify workspace files directly — only read and report
- The Controller (DONE state) is responsible for writing your output to:
  - `.aid-o/04-engine/lessons-learned.md` (lessons table — per-project)
  - `.aid-o/04-engine/command-history.md` (commands table — per-project)
  - Qdrant collection `aid-orchestration-log` (cross-project, tagged with project_name)
- Your output format MUST match the table schemas in those files exactly
- If no new lessons/commands found, output "None found" — Controller skips the write
```

**Step 8: Update session-management.md session closure checklist**

In `skills/session-management.md`, in the Phase 3 Session-End section, add an explicit requirement:

```markdown
### Session Closure Mandatory Steps (Controller MUST execute ALL)

1. [ ] Update session frontmatter: `status: completed`, add `completed:` timestamp
2. [ ] Update Completion to `100%`
3. [ ] Run lessons-extractor agent
4. [ ] Write lessons-extractor output to `lessons-learned.md` (per-project)
5. [ ] Write lessons-extractor output to `command-history.md` (per-project)
6. [ ] Write lessons + commands to Qdrant with `project_name` tag (cross-project)
7. [ ] Archive session file to `sessions/archive/`
8. [ ] Append final DONE entry to `stage_log.jsonl` with `result: success`
9. [ ] Verify archived session shows `status: completed` (not `active`)

Failure to execute any of these steps is a BUG in the Controller.
Step 6 (Qdrant) is skipped gracefully if Qdrant is not available.
```

**Step 9: Verify changes**

Run: `cd /opt/_home/small-personal-projetcs/ai-orchestrator && grep -n "lessons-learned.md" plugins/aid-orchestrator/skills/epic-orchestration.md`
Expected: Multiple matches including the new DONE state file-write section.

Run: `cd /opt/_home/small-personal-projetcs/ai-orchestrator && grep -n "status: completed" plugins/aid-orchestrator/skills/epic-orchestration.md`
Expected: Match in the new session status update section.

**Step 10: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md \
       plugins/aid-orchestrator/agents/lessons-extractor.md \
       plugins/aid-orchestrator/skills/session-management.md \
       plugins/aid-orchestrator/skills/memory-mcp.md
git commit -m "fix(orchestration): DONE state writes lessons, commands, session status, stage_log, and Qdrant project tags

Fixes PROP-001, PROP-002, PROP-003, PROP-010. The DONE state now:
- Writes lessons-extractor output to lessons-learned.md (always, per-project)
- Writes command-history to command-history.md (always, per-project)
- Writes to Qdrant with project_name tag (cross-project knowledge)
- Updates session frontmatter to status:completed before archiving
- Appends final stage_log.jsonl entry with result:success"
```

---

### Task 2: Fix Permissions — Agent Dispatch + Claude Code Auto-Allow (merged with Task 4)

**Why:** Two related problems:
1. Permission presets (Safe/Recommended/Advanced) from /aid-setup are saved to `permissions.yaml` but never read or applied during agent dispatch (PROP-011)
2. Presets don't update `.claude/settings.local.json` — so even with "full" selected, VS Code still prompts for confirmation on every Bash command

**Decision rationale:** PM confirmed these are two sides of the same coin. Both must be in sync:
- `permissions.yaml` → tells agents what they're ALLOWED to do (prompt-level)
- `.claude/settings.local.json` → tells Claude Code what to AUTO-ALLOW without prompting (enforcement-level)
For "advanced/full" preset: user wants zero confirmation dialogs in VS Code.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/policies/permissions.yaml` (preset definitions)
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (EXECUTING state — agent dispatch)
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (Option 7 — dual write)
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` (copy permissions.yaml)

**Step 1: Create default permissions.yaml**

Create `plugins/aid-orchestrator/defaults/policies/permissions.yaml`:

```yaml
# AID Permission Presets
# Two targets: (1) agent dispatch prompts, (2) .claude/settings.local.json
# Selected via /aid-setup, customizable per project

active_preset: "recommended"  # safe | recommended | advanced

presets:
  safe:
    description: "Read-only exploration, no file modifications"
    # Claude Code auto-allow entries (written to .claude/settings.local.json)
    claude_code_permissions:
      - "Glob"
      - "Grep"
      - "Read"
      - "Task"
      - "TodoWrite"
      - "WebSearch"
      - "Bash(git status:*)"
      - "Bash(git log:*)"
      - "Bash(git diff:*)"
      - "Bash(ls:*)"
    notes: "VS Code will prompt for any file modifications"

  recommended:
    description: "Edit files, run local git, tests, and linters — no push, no install"
    claude_code_permissions:
      # Tools
      - "Glob"
      - "Grep"
      - "Read"
      - "Edit"
      - "Write"
      - "NotebookEdit"
      - "Task"
      - "TodoWrite"
      - "WebSearch"
      - "WebFetch"
      # Git (local only)
      - "Bash(git add:*)"
      - "Bash(git commit:*)"
      - "Bash(git branch:*)"
      - "Bash(git checkout:*)"
      - "Bash(git diff:*)"
      - "Bash(git log:*)"
      - "Bash(git status:*)"
      - "Bash(git stash:*)"
      - "Bash(git merge:*)"
      - "Bash(git worktree:*)"
      # Testing & Linting
      - "Bash(pytest:*)"
      - "Bash(python -m pytest:*)"
      - "Bash(ruff check:*)"
      - "Bash(ruff format:*)"
      - "Bash(npm test:*)"
      - "Bash(npm run build:*)"
      - "Bash(npx vitest:*)"
      - "Bash(npx tsc:*)"
      # Filesystem (read + basic write)
      - "Bash(ls:*)"
      - "Bash(mkdir:*)"
      - "Bash(cp:*)"
      - "Bash(mv:*)"
      - "Bash(cat:*)"
      - "Bash(head:*)"
      - "Bash(tail:*)"
      - "Bash(find:*)"
      - "Bash(grep:*)"
      - "Bash(wc:*)"
      - "Bash(diff:*)"
      # MCP tools
      - "mcp__plugin_context7_context7__*"
    notes: "No git push, no package install, no rm, no network commands"

  advanced:
    description: "Full access — zero VS Code prompts, agents can do anything"
    claude_code_permissions:
      # Everything from recommended, plus:
      - "Glob"
      - "Grep"
      - "Read"
      - "Edit"
      - "Write"
      - "NotebookEdit"
      - "Task"
      - "TodoWrite"
      - "WebSearch"
      - "WebFetch"
      - "Bash(*:*)"
      - "mcp__*"
    notes: "Use with caution — agents can push, install packages, delete files"

# Role-specific overrides (merged with active_preset)
role_overrides:
  security:
    additional_permissions:
      - "Bash(bandit:*)"
      - "Bash(npm audit:*)"
      - "Bash(pip-audit:*)"
  qa:
    additional_permissions:
      - "Bash(pytest:*)"
      - "Bash(coverage:*)"
  release:
    additional_permissions:
      - "Bash(git tag:*)"
      - "Bash(git push:*)"
```

**Step 2: Add permission loading to EXECUTING state**

In `skills/epic-orchestration.md`, in the EXECUTING state, add before the Task tool call:

```markdown
### Permission Context for Agent Dispatch

Before dispatching any agent, load the permission context:

1. Read `.aid-o/03-config/policies/permissions.yaml`
2. Resolve `active_preset` to the preset definition
3. Check `role_overrides` for the agent's role
4. Merge: preset.claude_code_permissions + role_override.additional_permissions
5. Include the resolved permissions in the agent's dispatch prompt as a
   PERMISSIONS CONTEXT block:

```
PERMISSIONS CONTEXT:
- Preset: {active_preset}
- Allowed Bash commands: {merged_permissions_list}
- If a command is not in the allowed list, DO NOT execute it.
  Report status: blocked with the command you need.
```

If `permissions.yaml` does not exist or `active_preset` is not set,
default to `recommended` preset behavior.
```

**Step 3: Update /aid-setup Option 7 — Dual Write**

In `commands/aid-setup.md`, update Permission preset section to write BOTH files:

```markdown
### Option 7: Permission Preset — Dual Write

When PM selects a preset:

1. Write preset to `.aid-o/03-config/policies/permissions.yaml` (AID internal —
   tells agents what they're allowed to do via prompt)

2. Update `.claude/settings.local.json` (Claude Code enforcement —
   controls what VS Code auto-allows without prompting):

   a. Read existing `.claude/settings.local.json` (create `{"permissions":{"allow":[]}}` if missing)
   b. Read the selected preset's `claude_code_permissions` array from permissions.yaml
   c. Merge into `permissions.allow[]`, preserving existing user entries, avoiding duplicates
   d. Write updated `.claude/settings.local.json`

3. Confirm to PM:
   ```
   Permissions applied:
     - Preset: {name}
     - AID agents: .aid-o/03-config/policies/permissions.yaml
     - VS Code auto-allow: .claude/settings.local.json ({count} entries)
     - VS Code will NOT prompt for commands in the allow list
   ```

**Important:**
- NEVER overwrite existing user entries in `.claude/settings.local.json`
- Read → merge → write (additive, never destructive)
- For "advanced": `Bash(*:*)` means VS Code never prompts for ANY bash command
- Target file is `.claude/settings.local.json` (NOT `.claude/settings.json`)
```

**Step 4: Update /aid-init to copy permissions.yaml**

In `commands/aid-init.md`, add `permissions.yaml` to the list of policy files copied from defaults:

```markdown
- policies/: gates.yaml, decision-policies.yaml, slack-config.yaml, memory-config.yaml, dispatch-strategy.yaml, language.yaml, permissions.yaml
```

**Step 5: Verify**

Run: `grep -n "settings.local.json" plugins/aid-orchestrator/commands/aid-setup.md`
Expected: Matches in the updated Option 7 section.

Run: `grep -n "permissions.yaml" plugins/aid-orchestrator/skills/epic-orchestration.md plugins/aid-orchestrator/commands/aid-init.md`
Expected: Matches in both files.

**Step 6: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md \
       plugins/aid-orchestrator/defaults/policies/permissions.yaml \
       plugins/aid-orchestrator/commands/aid-setup.md \
       plugins/aid-orchestrator/commands/aid-init.md
git commit -m "feat(permissions): dual-write presets to permissions.yaml + .claude/settings.local.json

Fixes PROP-011 + user-reported 'full preset has no effect'. Permission presets now:
1. Write to permissions.yaml (agent dispatch prompt instructions)
2. Write to .claude/settings.local.json (Claude Code auto-allow enforcement)
Advanced preset adds Bash(*:*) so VS Code never prompts for confirmation."
```

---

### Task 3: Fix Git Branch/Worktree/Commit Behavior During EPIC Execution

**Why:** User reported that agents don't create git branches, worktrees, or commits during EPIC execution. The parallel-dispatch.md defines a branch strategy but the Controller never actually creates a branch for the session. Also, when git is not initialized or .gitignore is missing, the behavior is undefined.

**Decision rationale:** PM decided on a simpler branch model than per-step branching:
- **One branch per EPIC session** (not per step) — e.g. `epic/{epic_id}`
- **Agents commit throughout** their work within that single branch
- **No branch-per-step overhead** — cleaner history, simpler merge in DONE state
- If no git: skip branch, agents just work without version control

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (IDLE state — branch creation, DONE state — merge)
- Modify: `plugins/aid-orchestrator/skills/parallel-dispatch.md` (reference session branch)
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (git detection + .gitignore)
- Modify: `plugins/aid-orchestrator/defaults/playbooks/*.md` (all 9 — git discipline)

**Step 1: Add session branch creation to IDLE state**

In `skills/epic-orchestration.md`, in the IDLE state (after resolving EPIC file, before PLANNING):

```markdown
### Session Branch Creation (IDLE state)

1. Check if git is initialized:
   - Run `git rev-parse --is-inside-work-tree` (suppress errors)
   - If not a git repo: skip branch management, log to stage_log:
     `{"state": "IDLE", "warning": "git not initialized — branch management disabled"}`
     Proceed without branching.

2. If git is available:
   a. Ensure working tree is clean: `git status --porcelain`
      - If dirty: warn PM, suggest committing or stashing first
   b. Create session branch from current HEAD:
      `git checkout -b epic/{epic_id}`
   c. Log to stage_log:
      `{"state": "IDLE", "action": "branch_created", "branch": "epic/{epic_id}"}`
   d. Record branch in plan_progress.json:
      ```json
      "branch": "epic/{epic_id}",
      "base_commit": "{HEAD sha before branch}"
      ```

3. All subsequent agent dispatches include in their prompt:
   ```
   GIT CONTEXT:
   - You are on branch: epic/{epic_id}
   - Commit your changes after each meaningful piece of work
   - Use conventional commits: type(scope): description
   - Types: feat, fix, refactor, test, docs, chore
   - Do NOT push to remote
   - Do NOT switch branches
   ```
```

**Step 2: Add branch merge to DONE state**

In `skills/epic-orchestration.md`, in the DONE state, before archive:

```markdown
### Session Branch Merge (DONE state)

If a session branch was created (check plan_progress.json → branch):

1. Verify all gates passed and PM approved
2. Switch to base branch: `git checkout {default_branch}`
3. Merge session branch: `git merge epic/{epic_id} --no-ff -m "feat: complete EPIC {epic_id}"`
4. If merge conflict: escalate to PM (do NOT auto-resolve)
5. Delete session branch: `git branch -d epic/{epic_id}`
6. Log to stage_log:
   `{"state": "DONE", "action": "branch_merged", "branch": "epic/{epic_id}"}`

If no session branch (git not available): skip this step.
```

**Step 3: Improve git detection in /aid-setup**

In `commands/aid-setup.md`, in Step 1 (Project Detection), add comprehensive git handling:

```markdown
### Git Detection and Health Check

1. Check if `.git/` exists in project root

2. If NOT a git repo:
   - Display warning:
     ```
     Git Status: Not initialized
     ====================================
     AID works best with git for branch isolation, evidence tracking,
     and diff generation. Without git, these features are disabled.
     ```
   - Ask PM:
     ```
     Initialize git in this project?
     (A) Yes — run `git init` and create initial commit (Recommended)
     (B) No — proceed without git (branch isolation disabled)
     ```
   - If A: run `git init`, create `.gitignore` (see below), initial commit
   - If B: log decision, force `dispatch-strategy: sequential`

3. If IS a git repo — check for .gitignore:
   - If `.gitignore` does NOT exist: create it with sensible defaults
   - If `.gitignore` exists but missing `.aid-o/04-engine/` entries:
     append AID-specific patterns

   Default .gitignore additions for AID:
   ```
   # AID Engine (internal state — not for version control)
   .aid-o/04-engine/sessions/
   .aid-o/04-engine/evidence/
   .aid-o/04-engine/memory/
   .aid-o/logs/

   # Environment
   .env
   .env.local
   ```

4. Record git status in project-profile.yaml:
   ```yaml
   git:
     initialized: true|false
     default_branch: "main"  # or detected from remote
     remote: ""              # or detected
     gitignore: true|false
   ```
```

**Step 4: Add commit instruction to all role playbooks**

In each playbook file (`defaults/playbooks/*.md`), add to the Process section:

```markdown
## Git Discipline

- Commit after each meaningful change (not at the end of all work)
- Use conventional commit format: `type(scope): description`
- Types: feat, fix, refactor, test, docs, chore
- One logical change per commit
- If you see a GIT CONTEXT block in your dispatch prompt, follow its instructions
```

Note: This should be added to ALL 9 role playbooks: architect.md, domain.md, backend.md, frontend.md, qa.md, security.md, observability.md, docs.md, release.md.

**Step 4: Verify**

Run: `grep -rn "GIT CONTEXT" plugins/aid-orchestrator/skills/epic-orchestration.md`
Expected: Match in the new EXECUTING state section.

Run: `grep -rn "Git Discipline" plugins/aid-orchestrator/defaults/playbooks/`
Expected: Match in all 9 playbook files.

**Step 5: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md \
       plugins/aid-orchestrator/skills/parallel-dispatch.md \
       plugins/aid-orchestrator/commands/aid-setup.md \
       plugins/aid-orchestrator/defaults/playbooks/*.md
git commit -m "feat(orchestration): one branch per EPIC session with per-agent commits

Fixes user-reported issue: Controller creates epic/{epic_id} branch at IDLE,
all agents commit within it, branch merges back at DONE. /aid-setup detects
missing git (offers init) and missing .gitignore (creates with AID defaults).
All 9 playbooks now include Git Discipline section."
```

---

### ~~Task 4: MERGED into Task 2~~ (Permission persistence now handled in Task 2 dual-write)

---

## Phase 2: Performance & Token Optimization (P2)

These changes reduce token consumption, eliminate wasted retry cycles, and add timing metrics.

---

### Task 5: Enforce Pre-Lint in Agent Playbooks (Eliminate Gate Retries)

**Why:** QA agent produced 3 unused imports and 13 files with formatting issues, triggering a full gate retry cycle. If agents run `ruff check --fix && ruff format` before declaring their output complete, the retry is eliminated entirely. This saves ~1 full gate cycle worth of tokens.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/playbooks/backend.md`
- Modify: `plugins/aid-orchestrator/defaults/playbooks/frontend.md`
- Modify: `plugins/aid-orchestrator/defaults/playbooks/qa.md`
- Modify: `plugins/aid-orchestrator/defaults/playbooks/domain.md`
- Modify: `plugins/aid-orchestrator/defaults/playbooks/security.md`

**Step 1: Add pre-output quality step to all code-producing playbooks**

In each of the playbooks listed above, add a new section before the Output Format section:

```markdown
## Pre-Output Quality Check (MANDATORY)

Before producing your step_output, run these checks on ALL files you created or modified:

1. **Auto-fix linting issues:**
   ```bash
   ruff check --fix {files_you_modified}
   ruff format {files_you_modified}
   ```
   If `ruff` is not available (non-Python project), use the project's configured linter
   from `project-profile.yaml` → `tech_stack.lint`.

2. **Remove debugging artifacts:**
   - No `print()` statements (Python) or `console.log()` (JS/TS) in production code
   - No `import pdb` or `debugger` statements
   - No commented-out code blocks

3. **Verify imports:**
   - All imports are used
   - No wildcard imports (`from x import *`)
   - Imports are sorted (isort convention)

This step exists to prevent gate failures. A gate retry costs ~3000 tokens.
Running these checks locally costs ~50 tokens. Always run them.
```

**Step 2: Verify**

Run: `grep -rn "Pre-Output Quality Check" plugins/aid-orchestrator/defaults/playbooks/`
Expected: Match in backend.md, frontend.md, qa.md, domain.md, security.md.

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/defaults/playbooks/backend.md \
       plugins/aid-orchestrator/defaults/playbooks/frontend.md \
       plugins/aid-orchestrator/defaults/playbooks/qa.md \
       plugins/aid-orchestrator/defaults/playbooks/domain.md \
       plugins/aid-orchestrator/defaults/playbooks/security.md
git commit -m "perf(playbooks): add mandatory pre-output lint/format check to code-producing agents

Eliminates unnecessary gate retry cycles. Agents now run ruff check --fix &&
ruff format before declaring step output, preventing lint gate failures."
```

---

### Task 6: Per-Agent Metrics — Timing, Self-Report, Qdrant Storage

**Why:** plan_progress.json shows identical started_at/completed_at for all parallel agents (PROP-006). But timing alone ("backend was slow") is useless without knowing WHY. We need both Controller-measured timing AND agent-reported execution context.

**Decision rationale:** PM confirmed:
- Agent self-report adds ~50 tokens overhead (negligible)
- Qdrant metric writes are async/non-blocking (zero latency impact)
- Analytics skill (Task 26) will consume these metrics — data must be rich enough
- `/aid-analytics` will be one of the recommended post-EPIC options (Task 8)

**Files:**
- Modify: `plugins/aid-orchestrator/skills/parallel-dispatch.md` (dispatch log schema)
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (PHASE_CHECK + DONE metric writes)
- Modify: `plugins/aid-orchestrator/skills/agent-core.md` (mandatory self-report block)
- Modify: `plugins/aid-orchestrator/defaults/playbooks/*.md` (all 9 — self-report template)

**Step 1: Add mandatory Execution Summary to agent-core.md**

In `skills/agent-core.md`, add to the Output Format section:

```markdown
### Execution Summary (MANDATORY — last block of every agent output)

Every agent MUST end its step output with this structured block.
The Controller parses this for metrics and Qdrant storage.

```markdown
## Execution Summary
- Files read: {count}
- Files created: {count}
- Files modified: {count}
- Bash commands run: {count}
- Errors encountered: {count} ({brief list of each error and resolution})
- Self-reported complexity: low | medium | high
- Bottleneck: {what took the most time/effort and why}
```

Rules:
- This block MUST appear even if the step was trivial (just put zeros)
- "Bottleneck" is the most valuable field — be specific:
  BAD:  "writing tests"
  GOOD: "writing integration tests — had to read 4 existing test files to match patterns"
- "Errors encountered" must include what happened AND how you fixed it
- Do NOT omit this block. The Controller will reject step output without it.
```

**Step 2: Add per-agent timing to dispatch event schema**

In `skills/parallel-dispatch.md`, update the dispatch_log.json schema:

```markdown
### Enhanced Dispatch Log with Per-Agent Metrics

```json
{
  "parallel_group": "group-1",
  "dispatched_at": "2026-02-19T10:00:00Z",
  "agents": [
    {
      "step_id": "step_3_backend",
      "role": "backend",
      "dispatched_at": "2026-02-19T10:00:00Z",
      "completed_at": "2026-02-19T10:05:23Z",
      "duration_seconds": 323,
      "status": "completed",
      "prompt_size_chars": 4200,
      "output_size_chars": 12500,
      "self_report": {
        "files_read": 12,
        "files_created": 3,
        "files_modified": 5,
        "bash_commands": 8,
        "errors": 2,
        "error_details": ["import error → fixed unused import", "test timeout → increased timeout"],
        "complexity": "high",
        "bottleneck": "writing integration tests — read 4 test files for patterns"
      }
    }
  ]
}
```
```

**Step 3: Add timing + self-report capture to PHASE_CHECK**

In `skills/epic-orchestration.md`, in the PHASE_CHECK state, add:

```markdown
### Per-Agent Metrics Capture (PHASE_CHECK)

For each completed step (sequential or parallel):

1. **Controller-measured metrics:**
   - `completed_at`: timestamp when Task tool returned
   - `duration_seconds`: completed_at - dispatched_at
   - `prompt_size_chars`: length of dispatch prompt
   - `output_size_chars`: length of step output

2. **Agent self-reported metrics:**
   - Parse the `## Execution Summary` block from step output
   - Extract: files_read, files_created, files_modified, bash_commands,
     errors, error_details, complexity, bottleneck
   - If Execution Summary block is missing: log warning, proceed with
     controller-only metrics

3. **Update evidence files:**
   - `dispatch_log.json`: per-agent entry with all metrics
   - `plan_progress.json`: per-step timing + complexity
   - `stage_log.jsonl`: timing summary with bottleneck identification:
     ```json
     {"state": "PHASE_CHECK", "step_id": "step_3_backend", "duration_seconds": 323, "complexity": "high", "bottleneck": "writing integration tests", "errors": 2}
     ```

4. **Qdrant metric write (async, non-blocking):**
   If Qdrant available, store execution metric:
   ```json
   {
     "collection_name": "aid-memory",
     "data": "Agent backend completed step_3 in 323s. Complexity: high. Bottleneck: writing integration tests — read 4 test files for patterns. Errors: 2 (import fix, timeout retry).",
     "metadata": {
       "type": "metric",
       "metric_kind": "agent_execution",
       "project_name": "{project_name}",
       "epic_id": "{epic_id}",
       "step_id": "step_3_backend",
       "role": "backend",
       "duration_seconds": 323,
       "complexity": "high",
       "errors": 2,
       "timestamp": "{ISO 8601}"
     }
   }
   ```
```

**Step 4: Add EPIC-level metrics to DONE state**

In `skills/epic-orchestration.md`, in the DONE state, add after Curator dispatch:

```markdown
### EPIC-Level Metrics to Qdrant (DONE state)

Aggregate all step metrics into an EPIC summary metric:

```json
{
  "collection_name": "aid-memory",
  "data": "EPIC {epic_id} completed: {step_count} steps, {total_duration}s total, {gate_retries} gate retries. Slowest: {slowest_step} ({slowest_duration}s). Most errors: {most_errors_step}.",
  "metadata": {
    "type": "metric",
    "metric_kind": "epic_summary",
    "project_name": "{project_name}",
    "epic_id": "{epic_id}",
    "total_duration_seconds": "{sum of all step durations}",
    "step_count": "{count}",
    "gate_retries": "{count}",
    "slowest_step": "{step_id}",
    "most_errors_step": "{step_id}",
    "timestamp": "{ISO 8601}"
  }
}
```

Also store gate results as metrics:
```json
{
  "type": "metric",
  "metric_kind": "gate_result",
  "gate_name": "tests_pass",
  "passed": true,
  "retries": 0,
  "duration_seconds": 45
}
```
```

**Step 5: Add self-report template to all playbooks**

In each playbook (`defaults/playbooks/*.md`), add reference to Execution Summary:

```markdown
## Output Requirements

Your step output MUST end with an `## Execution Summary` block.
See `skills/agent-core.md` for the exact format. This is not optional.
```

**Step 6: Commit**

```bash
git add plugins/aid-orchestrator/skills/parallel-dispatch.md \
       plugins/aid-orchestrator/skills/epic-orchestration.md \
       plugins/aid-orchestrator/skills/agent-core.md \
       plugins/aid-orchestrator/defaults/playbooks/*.md
git commit -m "feat(metrics): per-agent timing, self-report, and Qdrant metric storage

Fixes PROP-006. Every agent now produces a mandatory Execution Summary with
files/commands/errors/bottleneck. Controller captures timing + parses self-report.
All metrics stored in Qdrant (type:metric) for cross-project analytics.
EPIC-level and gate-level summaries also stored at DONE state."
```

---

### ~~Task 7: Speed & Efficiency Optimization~~ (MOVED to v0.4.0 plan)

**Reason:** BMK-001 analýza ukázala, že 89.3% tokenů je inherentní práce agentů (čtení/psaní/testování). Přímé optimalizace (dispatch trimming, file scoping) řeší jen ~11%. Hlavní páka je lepší plánování (Task 10). Komplexní řešení vyžaduje vlastní plán s analýzou a testováním. Přesunuto do v0.4.0 spolu s Task 24 a 25.

**Klíčová data z BMK-001 (zachovat pro v0.4.0):**

| Component | Tokens | Podíl |
|---|---:|---:|
| Agent execution (tool calls) | 3,095,697 | 89.3% |
| Controller | 189,476 | 5.5% |
| Dispatch prompty | 115,794 | 3.3% |
| Controller skills (sunk cost) | 48,938 | 1.4% |
| Utility agenti | 16,075 | 0.5% |
| **CELKEM** | **~3.5M** | **140 min active compute, ~$95** |

MAX plan = flat rate, cena irelevantní, řešit jen rychlost.

**Plánované osy optimalizace (pro v0.4.0):**
1. Model selection: Sonnet pro QA/Security/Docs (rychlejší), Haiku pro utility
2. Agent file scoping: `relevant_files` v dispatch, méně Glob/Grep
3. Dispatch prompt trimming: deps-only, EPIC summary, playbook ref
4. Token tracking: per-EPIC + per-step profiling do Qdrant
5. Lepší plánování (synergy s Task 10): méně kroků, chytřejší paralelizace
*(Detailní implementační kroky budou v plánu v0.4.0)*

---

## Phase 3: Lifecycle & Evidence (P3 + P4)

Complete the lifecycle from EPIC start through completion, archiving, and reporting.

---

### Task 8: Add EPIC Completion Summary and Continuation Options

**Why:** User expects a clear summary and actionable next-step options after EPIC completion, not just a status message. AI should know to suggest brainstorming skill, /plan-epic, review, etc.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (DONE state — completion output)
- Modify: `plugins/aid-orchestrator/commands/run-epic.md` (DONE state output format)

**Step 1: Add completion summary format to DONE state**

In `skills/epic-orchestration.md`, in the DONE state, after all file writes and agent dispatches, add:

```markdown
### Completion Summary and Next Steps (presented to PM)

After all DONE state actions complete, present this summary to PM:

```
EPIC Complete: {epic_id}
====================================

Summary:
  - Steps completed: {completed_count}/{total_count}
  - Gates passed: {passed_gates}/{total_gates} ({retry_count} retries)
  - Duration: {total_duration}
  - Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/

Key outputs:
  {list of main artifacts created — files, endpoints, components}

What's next?
  1. Review the code — run /aid-review or examine the changes manually
  2. Start new work — run /aid-brainstorm to explore a new idea
  3. Continue building — run /plan-epic with a new EPIC
  4. Check quality — run /audit for a project health assessment
  5. Analyze performance — run /aid-analytics to see bottlenecks and optimization tips
  6. Archive — the session has been archived to sessions/archive/

Lessons learned: {count} new entries added to lessons-learned.md
Backlog proposals: {count} new entries (review with /aid-backlog)
```

The summary MUST include concrete artifact names (not generic descriptions).
Read the step outputs to list actual files created/modified.
```

**Step 2: Update run-epic.md to reference the new summary format**

In `commands/run-epic.md`, in the DONE state section, replace the current brief output with a reference:

```markdown
- **DONE:** [...existing actions...], present the Completion Summary from
  `skills/epic-orchestration.md` DONE state section. This is the last thing
  the PM sees — make it informative and actionable.
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md \
       plugins/aid-orchestrator/commands/run-epic.md
git commit -m "feat(orchestration): add structured completion summary with next-step options

After EPIC completion, PM now sees a detailed summary with artifact list,
metrics, and 5 actionable next-step options including brainstorming and review."
```

---

### Task 9: Auto-Archive Completed Plans and EPICs (with multi-EPIC/multi-session awareness)

**Why:** Completed plans and EPICs stay in active directories. They should be archived after DONE state. But a plan can spawn multiple EPICs, and an EPIC can have multiple sessions — archiving must respect these relationships.

**Decision rationale:** PM confirmed:
- Plan archivovat jen když VŠECHNY jeho EPICs jsou done (`epics_completed == epics_total`)
- EPIC archivovat jen když VŠECHNY jeho sessions jsou done (`sessions_completed == sessions_total`)
- Countery zapsat do frontmatter při tvorbě plánu/EPIC (ne zpětně číst)
- Archive operace proběhnou PŘED finálním DONE commitem — vše v jednom čistém commitu

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (DONE state — archive logic)
- Modify: `plugins/aid-orchestrator/skills/planner.md` (write counters during plan/EPIC creation)
- Modify: `plugins/aid-orchestrator/defaults/templates/epic.md` (frontmatter with counters)

**Step 1: Add counters to plan and EPIC frontmatter**

In `skills/planner.md`, when generating plan and EPIC files:

```markdown
### Plan Frontmatter (extended)

```yaml
# In .aid-o/01-plans/{plan}.md frontmatter:
status: done
epics_total: 3           # how many EPICs this plan spawns
epics_completed: 0       # incremented at each EPIC DONE
```

### EPIC Frontmatter (extended)

```yaml
# In .aid-o/02-epics/{epic}.md frontmatter:
status: done
plan_ref: bookmark-plan.md   # parent plan (null for standalone)
plan_epics_total: 3      # copied from plan for quick reference
sessions_total: 1        # from Session Breakdown (1 = single session)
sessions_completed: 0    # incremented at each session DONE
```

If EPIC has `## Session Breakdown` with N sessions → `sessions_total: N`.
Otherwise default `sessions_total: 1`.
```

**Step 2: Add archive logic to DONE state**

In `skills/epic-orchestration.md`, DONE state — runs AFTER all file writes
(lessons, commands, metrics) and BEFORE the final commit:

```markdown
### Archive Logic (DONE state — before final commit)

1. **Archive session:**
   - Move to `.aid-o/04-engine/sessions/archive/{filename}`
   - Update frontmatter: `status: completed`, `completed: {timestamp}`

2. **Update EPIC counter:**
   - Increment `sessions_completed += 1` in EPIC frontmatter

3. **Archive EPIC (conditional):**
   - IF `sessions_completed == sessions_total`:
     - Set `status: completed`, `completed: {timestamp}`
     - Move to `.aid-o/02-epics/archive/{filename}`
   - ELSE: EPIC stays active, log "session {N}/{total} done"

4. **Update Plan counter (conditional):**
   - IF EPIC archived AND `plan_ref` exists:
     - Increment `epics_completed += 1` in plan frontmatter
     - IF `epics_completed == epics_total`:
       - Set `status: completed`, move to `.aid-o/01-plans/archive/`
     - ELSE: plan stays active, log "plan: {N}/{total} EPICs done"

5. **Stage log:**
   ```json
   {"state": "DONE", "action": "archive", "session_archived": true,
    "epic_archived": true, "epic_sessions": "2/2",
    "plan_archived": false, "plan_epics": "1/3"}
   ```

6. **Final commit** (includes all archive moves + all DONE writes):
   `git add -A && git commit -m "done({epic_id}): completed, archived [list]"`

Archive = MOVE (copy + delete original). Active dirs = only pending work.
All archive ops happen BEFORE commit — one clean commit for entire DONE state.
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md \
       plugins/aid-orchestrator/skills/planner.md \
       plugins/aid-orchestrator/defaults/templates/epic.md
git commit -m "feat(orchestration): auto-archive with multi-EPIC/multi-session awareness

Plans track epics_total/epics_completed, EPICs track sessions_total/sessions_completed.
Archive only when all children complete. Counters written at creation time.
All archive moves included in single DONE commit."
```

---

### Task 10: Multi-Session Flow — Planner as Optimization Engine

**Why:** Multi-session flow nebyl definován. Planner je klíčový komponent — musí plánovat práci tak, aby se vykonala co nejrychleji, nejefektivněji a nejkvalitněji.

**Decision rationale:** PM confirmed:
- Planner je engine, který rozhoduje optimální strukturu (kroky, paralelizaci, sessions)
- Optimalizační priority: **rychlost → kvalita → efektivita**
- Uživatel je na MAX plánu — cena tokenů je irelevantní, tokeny řešit jen pokud ovlivňují latenci
- PM nemusí ručně definovat sessions — Planner to optimalizuje sám, PM jen schvaluje/upraví

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (core optimization logic)
- Modify: `plugins/aid-orchestrator/skills/session-management.md` (multi-session section)
- Modify: `plugins/aid-orchestrator/defaults/templates/epic.md` (Session Breakdown)
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` (workflow topic)

**Step 1: Add Planner optimization strategy to planner.md**

In `skills/planner.md`, add/rewrite the planning strategy section:

```markdown
## Planner Optimization Strategy

The Planner's job is to produce a plan.json + EPIC that the Controller can
execute as FAST, EFFICIENTLY, and with as HIGH QUALITY as possible.

### Optimization Priorities (in order)

1. **Speed** — minimize wall-clock time to completion
   - Maximize parallelization: identify independent steps, group them
   - Minimize sequential chain length (critical path)
   - Prefer more parallel steps over fewer sequential steps
   - Token count matters ONLY if it affects latency (larger context = slower)
   - Cost is NOT a factor (MAX plan — flat rate)

2. **Quality** — ensure outputs meet acceptance criteria
   - Every step has clear, verifiable acceptance criteria
   - Dependencies are explicit — no implicit ordering assumptions
   - Security and QA steps always run AFTER implementation (not before)
   - Gates validate cumulative quality, not just last step

3. **Efficiency** — avoid wasted work
   - No redundant steps (don't split what one agent can do well)
   - File scoping: each step knows exactly which files to read (relevant_files)
   - Dependency outputs are explicit — agents don't guess what prior steps did

### Step Planning Rules

1. **Architect is always step 1** — scaffolds structure, defines contracts
2. **Domain + Backend can sometimes parallelize** if architect provides clear
   enough contracts (models vs. routes are independent)
3. **QA + Security + Docs ALWAYS parallelize** — they read existing code, don't
   conflict
4. **Frontend + Backend parallelize** when contracts are defined by architect
5. **Maximum parallel group size: 4** — more causes context window pressure
   on the Controller tracking all outputs

### Session Split Decision

The Planner decides session boundaries automatically:

| Steps | Sessions | Rationale |
|-------|----------|-----------|
| 1-6 | 1 | Fits comfortably in single context window |
| 7-9 | 2 | Split at natural breakpoint (implementation → verification) |
| 10-14 | 2-3 | Split by domain (backend session → frontend session → quality) |
| 15+ | 3+ | Rare; split at dependency-free boundaries |

Rules for split placement:
- NEVER split inside a parallel group
- ALWAYS split AFTER a gate-worthy milestone (something that can be validated)
- Each session should produce independently testable deliverables
- First session always includes architect + core implementation
- Last session always includes QA + Security + Docs

### Session Breakdown Generation

The Planner writes `## Session Breakdown` into the EPIC file:

```markdown
## Session Breakdown

### Session 1: Core Implementation (steps 1-5)
**Goal:** Build working API with data model
**Steps:** architect → domain → backend → frontend (parallel: domain+backend)
**Deliverables:** Working endpoints, database, basic UI
**Estimated duration:** 30-45 min

### Session 2: Quality & Release (steps 6-8)
**Goal:** Verify, secure, document, release
**Steps:** qa + security + docs (all parallel)
**Deliverables:** Test suite (90%+ coverage), security review, documentation
**Estimated duration:** 20-30 min
```

And sets EPIC frontmatter: `sessions_total: 2`
```

**Step 2: Add multi-session flow to session-management.md**

In `skills/session-management.md`:

```markdown
## Multi-Session EPIC Flow

### How It Works

```
Session 1: /run-epic E-xxx
  → Controller reads plan.json, sees Session 1 steps
  → Executes steps 1-5 (respecting dependencies + parallelism)
  → Runs gates on session 1 outputs
  → PM approval → session archived → handoff created
  → EPIC stays active (sessions_completed: 1/2)

Session 2: /run-epic E-xxx --session 2
  → Controller reads plan_progress.json (knows steps 1-5 are done)
  → Reads Session 1 handoff for context
  → Executes steps 6-8
  → Runs gates on ALL outputs (cumulative)
  → PM approval → session archived → EPIC completed (2/2)
```

### Controller Behavior

- EPIC has `Session Breakdown` → Controller follows it automatically
- No `Session Breakdown` → single session (all steps)
- At session boundary: save `plan_progress.json`, create handoff block, commit, stop
- Next session: read `plan_progress.json` to resume from correct step
- Prior step outputs from Session 1 are available on disk (same branch)

### Handoff Between Sessions

At session end, Controller writes to `plan_progress.json`:
```json
{
  "session_completed": 1,
  "steps_done": ["step_1_architect", "step_2_domain", "step_3_backend"],
  "next_session_starts_at": "step_4_qa",
  "handoff_notes": "API complete, 24 endpoints, auth working. Tests needed."
}
```
```

**Step 3: Update aid-help.md**

```markdown
### Multi-Session EPICs

For larger EPICs (7+ steps), the Planner automatically splits execution into
multiple sessions optimized for speed and quality. Each session runs
independently with handoff state preserved. Use `/run-epic E-xxx --session N`
to run a specific session. The Planner decides the optimal split — PM approves.
```

**Step 4: Commit**

```bash
git add plugins/aid-orchestrator/skills/planner.md \
       plugins/aid-orchestrator/skills/session-management.md \
       plugins/aid-orchestrator/defaults/templates/epic.md \
       plugins/aid-orchestrator/commands/aid-help.md
git commit -m "feat(planner): planner as optimization engine with auto session splitting

Planner optimizes for speed→quality→efficiency (cost irrelevant on MAX plan).
Auto-splits sessions at dependency-free boundaries. Generates Session Breakdown
in EPIC. Controller follows session plan, creates handoffs between sessions."
```

---

### Task 11: Generate diff.patch for File-Modifying Steps

**Why:** Only step_1 (design-only) had a diff.patch artifact. Steps 2-6 all modified files but have no diff artifacts (PROP-004). Diffs are essential for code review and auditing.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (PHASE_CHECK state)

**Step 1: Add diff generation to PHASE_CHECK**

In `skills/epic-orchestration.md`, in the PHASE_CHECK state, after verifying outputs:

```markdown
### Diff Generation (after output verification)

For each completed step that modified files:

1. Generate diff:
   - If on a step branch: `git diff main...HEAD > diff.patch`
   - If on main branch: `git diff HEAD~{commit_count}..HEAD > diff.patch`
   - If git not available: skip, log warning
2. Save to evidence: `evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/diff.patch`
3. Record in plan_progress.json:
   ```json
   "step_3_backend": {
     "diff_patch": "evidence/{epic_id}/{run_id}/steps/step_3_backend/diff.patch",
     "files_modified": 15,
     "lines_added": 423,
     "lines_removed": 12
   }
   ```

If the diff is empty (step produced no file changes), record:
```json
"diff_patch": null,
"files_modified": 0
```
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md
git commit -m "feat(evidence): generate diff.patch for all file-modifying steps in PHASE_CHECK

Fixes PROP-004. Each step's evidence directory now includes a diff.patch
with stats (files modified, lines added/removed)."
```

---

### Task 12: Reconcile plan.json Gates with gates.yaml

**Why:** plan.json listed only `["lint_pass", "docs_updated"]` but gates.yaml defines 3+ gates including `tests_pass` and `security_scan_pass` (PROP-005). The planner ignores gates from gates.yaml.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (gate inclusion logic)

**Step 1: Update planner to read gates.yaml**

In `skills/planner.md`, in the Plan JSON generation section (Step 3), update the gates handling:

```markdown
### Gate Inclusion (Step 3.gates)

The plan MUST include ALL gates from the project's `gates.yaml`:

1. Read `.aid-o/03-config/policies/gates.yaml`
2. For each gate definition:
   - If `required: true`: ALWAYS include in plan.json gates
   - If `required: false` AND `when` condition evaluates to true based on
     EPIC scope: include in plan.json gates
   - If `required: false` AND `when` condition evaluates to false: exclude
3. The plan.json `gates` array MUST match gates.yaml required gates exactly

**Validation rule V-16 (NEW):** `plan.gates` MUST contain ALL gates from
`gates.yaml` where `required: true`. Missing required gates = validation failure.

Example:
```yaml
# gates.yaml has:
tests_pass:     required: true    → MUST be in plan.json
lint_pass:      required: true    → MUST be in plan.json
security_scan:  required: true    → MUST be in plan.json
docs_updated:   required: true    → MUST be in plan.json
type_check:     required: false   → include IF frontend files in scope
build_pass:     required: false   → include IF frontend files in scope
```

```json
// plan.json gates (correct):
"gates": ["tests_pass", "lint_pass", "security_scan_pass", "docs_updated"]
// + conditionally: "type_check", "build_pass"
```

**NEVER** hardcode the gates list. ALWAYS read from gates.yaml.
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/skills/planner.md
git commit -m "fix(planner): include ALL required gates from gates.yaml in plan.json

Fixes PROP-005. Planner now reads gates.yaml and includes all required gates.
Adds validation rule V-16 to reject plans with missing required gates."
```

---

### Task 13: Add Curator Auto-Invocation to Pipeline

**Why:** Curator currently runs as a manual post-hoc step (PROP-007). Should be an automatic post-DONE phase that always runs after EPIC completion.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (DONE state)

**Step 1: Make Curator dispatch mandatory in DONE state**

In `skills/epic-orchestration.md`, in the DONE state, the Curator dispatch already exists but as an optional/parallel step. Make it mandatory and structured:

```markdown
### Curator Post-Processing (MANDATORY in DONE state)

After generating final_report.md and BEFORE presenting the completion summary:

1. Dispatch Curator agent with:
   - All step outputs from `evidence/{epic_id}/{run_id}/steps/*/step_output.json`
   - Gate results from `evidence/{epic_id}/{run_id}/gates_report.json`
   - Final report from `evidence/{epic_id}/{run_id}/final_report.md`
2. Wait for Curator output (do NOT dispatch in background)
3. Process Curator proposals:
   - Write new proposals to `.aid-o/04-engine/backlog.md`
   - Include proposal count in the completion summary
4. If Slack is enabled: send each proposal as a Type D message for PM review
5. If Slack is disabled: list proposals in the completion summary for PM to review

The Curator runs SYNCHRONOUSLY before the completion summary so that the
summary can include the proposal count and any high-priority findings.

Curator dispatch prompt template:
```
You are the Curator agent. Analyze the completed EPIC evidence and produce
improvement proposals for the backlog.

EPIC: {epic_id}
Evidence: {evidence_dir}
Step count: {step_count}
Gate retries: {retry_count}
Duration: {total_duration}

Read: skills/improvement-proposals.md for proposal format.
Read: agents/curator.md for your full specification.
```
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md
git commit -m "feat(orchestration): make Curator post-processing mandatory and synchronous in DONE state

Fixes PROP-007. Curator now always runs after EPIC completion, proposals are
written to backlog.md, and proposal count is included in the completion summary."
```

---

## Phase 4: UX & Onboarding (P5 + P6)

Improve the first-run experience, setup flow, and examples.

---

### Task 14: Improve /aid-setup — Chat-First Flow with Details

**Why:** User wants /aid-setup to first display all options with details in chat, then ask which ones to select — not jump straight into an interactive checklist.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (Step 4 flow)

**Step 1: Restructure Step 4 to chat-first**

In `commands/aid-setup.md`, replace the current Step 4 (interactive checklist) with:

```markdown
### Step 4: Present Options with Details (Chat-First)

BEFORE asking PM to select options, present ALL options with detailed descriptions:

```
Setup Options Available
====================================

1. Initialize .aid-o/ workspace
   Creates the directory structure for plans, epics, sessions, and evidence.
   Required for all AID features. (Recommended: always)

2. Customize gates.yaml
   Configures quality gates for your tech stack:
   - Tests: {detected_test_framework or "none detected"}
   - Linting: {detected_linter or "none detected"}
   - Security: {detected_security_tool or "none detected"}
   (Recommended: yes)

3. Populate project-profile.yaml
   Saves your project's tech stack, architecture, and conventions for agents.
   Detected: {languages}, {frameworks}
   (Recommended: yes)

4. Generate/update CLAUDE.md
   Adds AID commands reference and workspace info to your CLAUDE.md.
   (Recommended: if CLAUDE.md exists or you want one)

5. Add .aid-o/ to .gitignore
   Prevents committing evidence and engine files to git.
   (Recommended: yes for most projects)

6. MCP Servers
   a. Qdrant — vector memory for cross-session knowledge
   b. Slack — PM communication via Slack messages
   c. Auto-detect — {list detected MCPs based on stack}
   d. Custom — add your own MCP servers
   (Recommended: at minimum Qdrant local)

7. Permission Preset
   Controls what agents can do:
   - Safe: read-only, no file changes
   - Recommended: edit files, run tests/linters, local git (no push)
   - Advanced: full access including git push and package install
   (Recommended: Recommended preset)

8. Document Language
   Language for generated plans, EPICs, and reports.
   Default: EN (English). Conversation always follows your language.
   (Recommended: EN unless you prefer another)

9. Parallel Isolation Strategy
   How agents are isolated when running in parallel:
   - Worktrees: full filesystem isolation (recommended, requires git)
   - Branches: lighter isolation, shared filesystem
   - Sequential: no parallelism (safest, slowest)
   (Recommended: Worktrees if git available, Sequential otherwise)
```

THEN ask PM:
```
Which options would you like to configure?
(A) All recommended (options 1,2,3,6a,7,8,9)
(B) Let me pick specific options
(C) Everything (all options)
```

If (B): present a numbered list for PM to select from.
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-setup.md
git commit -m "feat(setup): chat-first option presentation with details before selection

/aid-setup now shows all options with descriptions, detected values, and
recommendations before asking PM to select. Reduces cognitive load."
```

---

### ~~Task 15: MERGED into Task 3~~ (Git init + .gitignore handling now in Task 3 Step 3)

---

### Task 16: Post-Setup Next-Step Guidance

**Why:** After `/aid setup` completes, user expected guidance about brainstorming skill, /plan-epic, and /aid-help — not just "Your project is ready."

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (Step 7 — Summary)

**Step 1: Replace generic summary with actionable guidance**

In `commands/aid-setup.md`, replace Step 7 with:

```markdown
### Step 7: Summary and Next Steps

After all selected options are configured:

```
Setup Complete
====================================
Configured: {list of completed options}
Workspace:  .aid-o/ (ready)
Profile:    {detected_stack_summary}

What to do next:
====================================

If you have an idea but aren't sure how to build it:
  → /aid-brainstorm "your idea"
  This starts an interactive design session. AID asks questions,
  explores approaches, and produces a plan + EPIC draft.

If you already know what to build:
  → Create an EPIC file in .aid-o/02-epics/ (see template)
  → /plan-epic .aid-o/02-epics/your-epic.md
  → /run-epic

For help and examples:
  → /aid-help           — full documentation
  → /aid-help examples  — step-by-step example workflows
  → /aid-help commands  — all available commands

Tip: Start with /aid-brainstorm — it's the best way to explore ideas
     and let AID help you design before coding.
```

**Do NOT** end with just "Your project is ready." Always provide concrete,
actionable next steps with command examples.
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-setup.md
git commit -m "feat(setup): actionable post-setup guidance with brainstorming recommendation

Replaces generic 'ready' message with concrete next-step commands including
/aid-brainstorm recommendation, /plan-epic, and /aid-help references."
```

---

### Task 17: Streamline Slack MCP Onboarding

**Why:** Slack MCP setup caused 2 session pauses during testing. Wrong package names, missing scopes, env var confusion, stderr interference. The setup guide must be bulletproof.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (Option 6b — Slack)
- Modify: `plugins/aid-orchestrator/defaults/policies/slack-config.yaml` (comments)

**Step 1: Rewrite Slack MCP setup in /aid-setup**

In `commands/aid-setup.md`, replace Option 6b (Slack) with:

```markdown
### Option 6b: Slack MCP Server

**Package:** `slack-mcp-server` by @korotovsky
(NOT `@anthropic/mcp-slack` — does not exist. NOT `@kazuph/mcp-slack` — has Linux platform bug.)

**Setup flow:**

1. Ask PM: "Do you want Slack integration for PM notifications?"
   If no: skip, set `slack.enabled: false` in slack-config.yaml

2. If yes, display requirements:
   ```
   Slack Setup Requirements
   ====================================

   You need a Slack Bot with these scopes:
     Required:
       - chat:write        (send messages)
       - channels:read     (find channels)
       - channels:history  (read channel messages)
       - users:read        (CRITICAL: server crashes without this)
     Recommended:
       - channels:join     (auto-join channels)
       - groups:history    (private channel access)
       - groups:read       (private channel discovery)

   Setup steps:
     1. Go to https://api.slack.com/apps
     2. Select your app (or create one)
     3. Go to OAuth & Permissions → Bot Token Scopes
     4. Add ALL required scopes listed above
     5. Reinstall app to workspace if you changed scopes
     6. Copy the Bot User OAuth Token (xoxb-...)
     7. In Slack, type: /invite @YourAppName in your channel
   ```

3. Ask PM for bot token: "Paste your Bot Token (xoxb-...):"

4. Ask PM for channel: "Which channel? (e.g., #aid-orchestrator):"

5. Ask PM for channel ID (for add_message tool):
   "Channel ID for sending messages (e.g., C0AFP2GP459):"
   "Find it in Slack: right-click channel name → View channel details → scroll down"

6. Create `.env` file (if not exists) with:
   ```
   SLACK_MCP_XOXB_TOKEN=xoxb-...
   SLACK_MCP_ADD_MESSAGE_TOOL=C0AFP2GP459
   ```

7. Add `.env` to `.gitignore` (if not already there)

8. Configure MCP server in `.mcp.json`:
   ```json
   {
     "slack": {
       "type": "stdio",
       "command": "bash",
       "args": [
         "-c",
         "[ -f .env ] && set -a && source .env && set +a; exec npx -y slack-mcp-server 2>/dev/null"
       ]
     }
   }
   ```
   Note: `2>/dev/null` suppresses stderr logs that interfere with VSCode MCP protocol.

9. Update `slack-config.yaml`:
   ```yaml
   slack:
     enabled: true
     channel: "#aid-orchestrator"
     pm_user_id: ""  # Optional: PM's Slack user ID for @mentions
   ```

10. Verify: Test MCP connection by asking Claude to list Slack channels.
    If it fails, check: scopes, token, channel invite, .env file.

**Common issues:**
- "FATAL: users:read scope required" → Add `users:read` scope in Slack app settings, reinstall
- "conversations_add_message disabled" → Set `SLACK_MCP_ADD_MESSAGE_TOOL` env var
- MCP stderr JSON logs → Already handled by `2>/dev/null` in config
```

**Step 2: Verify Slack MCP package before committing**

Before committing, verify the recommended package actually works:
1. `npm view slack-mcp-server` — confirm package exists, check latest version
2. Test MCP initialization with a minimal config (token + channel)
3. Confirm all documented scopes are correct against current Slack API docs
4. If package changed or was deprecated since BMK-001 testing, update the guide

This step is MANDATORY — we will not ship unverified MCP instructions again.

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-setup.md \
       plugins/aid-orchestrator/defaults/policies/slack-config.yaml
git commit -m "feat(setup): bulletproof Slack MCP onboarding with correct package and scopes

Replaces Slack setup with battle-tested config: uses slack-mcp-server package,
lists all required scopes, handles .env secrets, suppresses stderr, and documents
common failure modes. Package verified against npm registry."
```

---

### Task 18: Add Playwright MCP + E2E Agent as Optional Parallel Step

**Why:** User requested Playwright for UI testing. But Playwright is slow (browser ops 2-10s each) — embedding it into QA would slow the critical path.

**Decision rationale:** PM confirmed:
- Playwright = samostatný agent (`step_N_e2e`), NIKDY zabudovaný do QA
- Planner rozhodne zda ho zařadit (has_frontend + Playwright MCP available)
- Pokud zařazen → běží paralelně s QA+Security+Docs
- Při implementaci ověřit, že `@anthropic/mcp-playwright` package funguje

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (Option 6c — Auto-detect)
- Modify: `plugins/aid-orchestrator/skills/planner.md` (E2E step inclusion logic)
- Create: `plugins/aid-orchestrator/defaults/playbooks/e2e.md` (E2E playbook)
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` (config topic)

**Step 1: Add Playwright to auto-detect MCPs in /aid-setup**

In `commands/aid-setup.md`, Option 6c:

```markdown
- **Playwright MCP** — if frontend files detected (package.json with
  react/vue/angular/svelte, or .tsx/.jsx/.vue files):
  ```
  Playwright MCP detected as recommended for your frontend project.
  Enables browser-based E2E testing, screenshots, and visual verification.
  Install: claude mcp add playwright -- npx -y @anthropic/mcp-playwright
  ```
```

**Step 2: Add E2E step logic to planner.md**

```markdown
### E2E Step (Playwright)

Planner adds E2E step when ALL conditions met:
1. `project-profile.yaml` → `has_frontend: true`
2. Playwright MCP is configured (available in MCP tools)
3. EPIC includes frontend implementation or UI changes

E2E step:
- Role: `e2e` (uses QA agent with E2E playbook)
- Dependencies: depends on frontend + backend steps
- Parallel group: runs alongside QA, Security, Docs
- Model: sonnet (browser interactions are structured)

If conditions NOT met → no E2E step added.
```

**Step 3: Create E2E playbook**

Create `plugins/aid-orchestrator/defaults/playbooks/e2e.md`:

```markdown
# E2E Testing Playbook (Playwright)

## Mission
Browser-level verification of critical user flows. Screenshots as evidence.

## What to Test
1. Critical user flows — login, main CRUD, navigation
2. Visual rendering — pages load, layout correct
3. Form validation — required fields, error messages
4. Responsive — desktop + mobile viewport

## Playwright Usage
- `playwright_navigate` → load pages
- `playwright_screenshot` → visual evidence
- `playwright_click` / `playwright_fill` → interactions
- Screenshots → `evidence/{epic_id}/{run_id}/steps/{step_id}/screenshots/`

## Constraints
- Do NOT write unit tests (QA handles those)
- Do NOT modify source code (read-only + test files only)
- 5-10 critical flows, not exhaustive
- Each browser op is slow (2-10s) — minimize unnecessary navigation
```

**Step 4: Verify package + Commit**

Before committing: `npm view @anthropic/mcp-playwright` — confirm exists & works.

```bash
git add plugins/aid-orchestrator/commands/aid-setup.md \
       plugins/aid-orchestrator/skills/planner.md \
       plugins/aid-orchestrator/defaults/playbooks/e2e.md \
       plugins/aid-orchestrator/commands/aid-help.md
git commit -m "feat(e2e): Playwright MCP as optional parallel E2E step

Planner auto-adds E2E step when frontend + Playwright detected.
Solo parallel agent (not in QA) to avoid slowing critical path.
New E2E playbook with focused browser testing guidelines."
```

---

### Task 19: Update Examples to Include Full UI

**Why:** User wants all examples to show full-stack development (UI + backend), not just backend.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` (examples topic)

**Step 1: Update examples topic**

In `commands/aid-help.md`, in the `examples` topic, update all 3 interactive prompts to explicitly include UI components:

```markdown
### Examples

**Example 1: REST API + Database + Admin UI**
  Try: `/aid-brainstorm "Build a task management API with PostgreSQL storage
  and a React admin dashboard for managing tasks, users, and analytics"`

  What happens:
  1. AID asks 5-7 questions about your requirements
  2. Proposes 2-3 architectural approaches (monolith vs. separate services)
  3. Designs: API contracts, database schema, React components, routing
  4. Generates a plan + EPIC draft with steps:
     architect → domain → backend + frontend (parallel) → qa + security → docs

**Example 2: CLI Tool + Interactive TUI**
  Try: `/aid-brainstorm "Create a git repository analytics CLI tool with
  an interactive terminal UI showing commit stats, contributor graphs, and
  branch visualization"`

  What happens:
  1. AID explores: output format, interactivity level, dependencies
  2. Proposes approaches: pure CLI vs. TUI framework (textual/rich/blessed)
  3. Designs: command structure, data pipeline, TUI layout, chart rendering
  4. Generates plan + EPIC with appropriate roles

**Example 3: Full-Stack SaaS Application**
  Try: `/aid-brainstorm "Build a bookmark manager with tagging, full-text
  search, a responsive web UI with dark mode, and browser extension for
  one-click saving"`

  What happens:
  1. AID asks about: auth method, search engine, UI framework, browser targets
  2. Proposes: tech stack options, architecture patterns, deployment strategy
  3. Designs: complete full-stack architecture including REST API, database,
     React/Vue frontend with responsive layouts, browser extension manifest
  4. Generates plan + EPIC covering all layers
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-help.md
git commit -m "feat(help): update examples to show full-stack development with UI components

All 3 examples now explicitly include frontend/UI work alongside backend,
demonstrating AID's full-stack orchestration capabilities."
```

---

### Task 20: App Type Detection and Multi-Type Support

**Why:** User asked how AID handles different app types (web, ERP, custom app, local plugin, script). Need to document the approach and improve project-profile detection.

**Files:**
- Modify: `plugins/aid-orchestrator/agents/project-scanner.md` (app type detection)
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` (FAQ section)

**Step 1: Add app type classification to project-scanner**

In `agents/project-scanner.md`, in Step 2 (Detect Project Type), expand the classification:

```markdown
### Extended App Type Classification

Detect the primary application type from project indicators:

| Type | Indicators | AID Behavior |
|------|-----------|--------------|
| `web-app` | package.json + React/Vue/Angular/Svelte | Full frontend+backend pipeline, Playwright MCP |
| `api-service` | FastAPI/Express/Flask, no frontend framework | Backend-focused, skip frontend role |
| `cli-tool` | argparse/click/commander, `bin` in package.json | Backend-focused, skip frontend role |
| `desktop-app` | Electron/Tauri, tkinter/PyQt | Custom pipeline, platform-specific testing |
| `mobile-app` | React Native/Flutter/Swift/Kotlin | Custom pipeline, device testing |
| `library` | No entry point, just src + tests | Backend-focused, emphasis on API design |
| `plugin` | Plugin manifest (claude-plugin, vscode extension, etc.) | Adapt to host platform conventions |
| `script` | Single file or small collection, no framework | Minimal pipeline, maybe just QA + docs |
| `monorepo` | Workspaces in package.json/pnpm-workspace.yaml | Multi-package orchestration |
| `erp-module` | ERP framework indicators (Odoo, SAP, etc.) | Domain-heavy, strict conventions |
| `infrastructure` | Terraform/Pulumi/CloudFormation, Dockerfile only | DevOps-focused roles |

Store as `architecture.app_type` in project-profile.yaml.

The Planner uses `app_type` to:
- Select appropriate roles (skip frontend for CLI tools)
- Choose relevant gates (skip build_pass for libraries)
- Assign parallel groups (backend+frontend only for web-app)
- Recommend MCPs (Playwright for web-app, Docker for infrastructure)
```

**Step 2: Add FAQ entry to /aid-help**

In `commands/aid-help.md`, add to the FAQ or create a new FAQ topic:

```markdown
### How does AID handle different application types?

AID auto-detects your app type from project indicators (web-app, API, CLI,
library, plugin, etc.) and adapts the orchestration pipeline accordingly:

- **Web apps:** Full pipeline with frontend + backend parallel, Playwright testing
- **APIs/CLIs:** Backend-focused, skip frontend roles
- **Libraries:** Emphasis on architect + domain + qa, skip deployment
- **Scripts:** Minimal pipeline — just QA and docs
- **Monorepos:** Multi-package orchestration with workspace awareness

Your app type is stored in `project-profile.yaml → architecture.app_type`.
To override: edit the file or re-run `/aid-setup`.
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/agents/project-scanner.md \
       plugins/aid-orchestrator/commands/aid-help.md
git commit -m "feat(scanner): extended app type classification with pipeline adaptation

Project scanner now detects 11 app types (web-app, api-service, cli-tool,
desktop, mobile, library, plugin, script, monorepo, erp-module, infrastructure)
and stores as architecture.app_type for pipeline customization."
```

---

### Task 21: Auto-Scaffold Step in /plan-epic

**Why:** When /plan-epic generates a plan, it should read project-profile.yaml and auto-prepend a "step 0 — scaffold" for new projects (PROP-013).

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (step generation)

**Step 1: Add auto-scaffold logic to planner**

In `skills/planner.md`, after Step 2 (dependency analysis), add:

```markdown
### Step 2.1: Auto-Scaffold Detection

Check if the project needs scaffolding (step 0):

1. Read `project-profile.yaml → initialized` field
2. If `initialized: false` OR project-profile has no `tech_stack.test` configured:
   - Detect needed scaffold from `tech_stack.languages`:
     - Python: `python -m venv .venv && pip install -r requirements.txt`
     - Node.js: `npm init -y && npm install`
     - Go: `go mod init {module_name}`
     - Rust: `cargo init`
   - Generate "step_0_scaffold" with:
     ```json
     {
       "step_id": "step_0_scaffold",
       "role": "architect",
       "objective": "Initialize project structure, virtual environment, and dependencies",
       "depends_on": [],
       "outputs": ["project scaffold", "dependency manifest", "test configuration"],
       "acceptance_criteria": [
         "Project structure matches conventions",
         "Dependencies installed and importable",
         "Test runner configured and executable"
       ]
     }
     ```
   - Add as first step (all other steps depend on it)

3. If `initialized: true` AND test framework configured: skip scaffold step

4. Present scaffold plan to PM for confirmation:
   ```
   Auto-scaffold detected: {language} project needs initialization.
   Step 0 will set up: {scaffold_description}
   Include this step? (Y/N)
   ```
   If PM says N: skip scaffold step.
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/skills/planner.md
git commit -m "feat(planner): auto-scaffold step 0 for uninitialized projects

Fixes PROP-013. Planner detects uninitialized projects via project-profile.yaml
and prepends a scaffold step (venv, npm init, etc.) with PM confirmation."
```

---

## Phase 5: Knowledge & Validation (P7 + P8)

Cross-project knowledge sharing, backlog improvements, and validation.

---

### Task 22: Cross-Project Knowledge via Qdrant

**Why:** Lessons learned, commands, and decisions are stored per-project in `.aid-o/04-engine/` as .md files. Knowledge from one project isn't available when working on another. Need a cross-project knowledge mechanism.

**Decision rationale:** PM decided on a dual-store architecture:
- **.md files = local per-project** (human-readable, offline backup, always works)
- **Qdrant = global cross-project store** (semantic search, tagged with `project_name`)

This avoids a third file-based global store (`~/.aid-o/global/`) which would be
unsearchable and hard to deduplicate. Qdrant is already a dependency for memory —
making it THE cross-project store is a natural extension, not added complexity.
If Qdrant is not available, cross-project knowledge simply isn't available
(graceful degradation — local .md files still work fine per-project).

**Files:**
- Modify: `plugins/aid-orchestrator/skills/memory-mcp.md` (cross-project search/store protocol)
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (IDLE state — cross-project read, DONE state — already has project tagging from Task 1)
- Modify: `plugins/aid-orchestrator/skills/session-management.md` (startup — cross-project read)
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (explain WHY Qdrant matters)
- Modify: `plugins/aid-orchestrator/defaults/policies/memory-config.yaml` (cross-project settings)

**Step 1: Update memory-mcp.md with cross-project protocol**

In `skills/memory-mcp.md`, add a new section:

```markdown
## Cross-Project Knowledge Protocol

Qdrant serves as the SINGLE cross-project knowledge store. Every entry is
tagged with `project_name` so knowledge from Project A can inform Project B.

### Architecture

```
Project A (.aid-o/)              Project B (.aid-o/)
  lessons-learned.md               lessons-learned.md
  command-history.md               command-history.md
        ↓ write                          ↓ write
  ┌─────────────────────────────────────────────┐
  │         Qdrant: aid-memory collection       │
  │  entry: { data, project_name, type, ... }   │
  │                                             │
  │  Semantic search across ALL projects        │
  └─────────────────────────────────────────────┘
        ↑ read                           ↑ read
  Project C (starting)             Project D (planning)
```

### Write Protocol (DONE state, per Task 1 Step 6)

Every `qdrant-store` call includes mandatory metadata:

```json
{
  "collection_name": "aid-memory",
  "data": "{lesson/command/decision text}",
  "metadata": {
    "project_name": "{from project-profile.yaml}",
    "epic_id": "{epic_id}",
    "type": "lesson|command|decision|pattern",
    "category": "{category}",
    "timestamp": "{ISO 8601}",
    "tech_stack": "{languages + frameworks from project-profile}"
  }
}
```

The `tech_stack` field enables filtering: when Project B uses FastAPI,
it can find lessons tagged with "Python, FastAPI" from Project A.

### Read Protocol (IDLE state + EXECUTING state)

**At IDLE (before planning):**
1. If Qdrant available: `qdrant-find` with query = EPIC goal + tech stack
2. Filter: `type IN (lesson, pattern, decision)`, exclude current project's entries
   (those are already in local .md files)
3. Include top 3 cross-project results in Planner context:
   ```
   CROSS-PROJECT KNOWLEDGE (from Qdrant):
   - [project-A] Async SQLAlchemy: use db.refresh() after mutations
   - [project-B] ruff --fix + format resolves all F401 issues automatically
   - [project-C] Slack MCP requires users:read scope or crashes at startup
   ```

**At EXECUTING (before agent dispatch):**
1. If `memory.search.pre_step_search: true`:
2. `qdrant-find` with query = step objective + role
3. Include top 3 results (cross-project + same-project) in agent dispatch prompt:
   ```
   RELEVANT KNOWLEDGE (from memory):
   - {lesson} (source: {project_name})
   ```

### No Qdrant = No Cross-Project (graceful degradation)

If Qdrant is not configured or unavailable:
- Local .md files work normally (per-project)
- Cross-project search returns empty results
- No error, no warning (beyond initial IDLE log)
- This is an expected state for users who don't want/need Qdrant
```

**Step 2: Update /aid-setup to explain WHY Qdrant**

In `commands/aid-setup.md`, Option 6a (Qdrant), update the description:

```markdown
### Option 6a: Qdrant — Cross-Project Knowledge Database

Qdrant is NOT just "optional memory" — it's your **cross-project knowledge base**.

```
Why Qdrant?
====================================
Without Qdrant:
  - Lessons learned stay in THIS project only
  - When you start a new project, you start from zero
  - No way to search "what did I learn about FastAPI?"

With Qdrant:
  - Lessons, commands, and decisions from ALL your projects are searchable
  - Starting a new project? AID automatically finds relevant knowledge
  - "How did I handle auth last time?" → instant answer from Project B
  - Semantic search: find by meaning, not just keywords

Qdrant runs locally (Docker or embedded). Your data never leaves your machine.
```

Ask PM:
```
Install Qdrant for cross-project knowledge? (Recommended)
(A) Yes — set up Qdrant local (recommended, requires Docker)
(B) No — per-project knowledge only (lessons stay in each project)
```
```

**Step 3: Update memory-config.yaml defaults**

In `defaults/policies/memory-config.yaml`, update to clarify cross-project role:

```yaml
memory:
  enabled: false                          # Set true after Qdrant setup
  collection_name: "aid-memory"           # Single collection for ALL projects
                                          # Entries tagged with project_name for filtering

  cross_project:
    enabled: true                         # Search other projects' knowledge at IDLE
    read_at_idle: true                    # Pre-planning cross-project search
    read_at_executing: true               # Pre-step cross-project search
    exclude_current_project: true         # Don't duplicate local .md file content
    max_results: 3                        # Top N cross-project results to include

  auto_index:
    session_end: true
    epic_done: true
    gate_results: false

  search:
    top_k: 3                              # Reduced from 5 (prompt optimization)
    timeout_seconds: 5
    min_score: 0.4
    pre_step_search: true
```

**Step 4: Update IDLE state to include cross-project read**

In `skills/epic-orchestration.md`, IDLE state section, add:

```markdown
### Cross-Project Knowledge Read (IDLE state)

Before generating the plan:

1. Check `memory-config.yaml → memory.enabled` AND `cross_project.enabled`
2. If both true:
   a. Read `project-profile.yaml` for current project's tech_stack
   b. `qdrant-find` with query = "{EPIC goal} {tech_stack_summary}"
   c. Filter: exclude entries where `metadata.project_name == current_project`
   d. Take top `cross_project.max_results` entries
   e. Format as CROSS-PROJECT KNOWLEDGE block
   f. Pass to Planner as additional context
3. If Qdrant unavailable: skip silently, log to stage_log
```

**Step 5: Commit**

```bash
git add plugins/aid-orchestrator/skills/memory-mcp.md \
       plugins/aid-orchestrator/skills/epic-orchestration.md \
       plugins/aid-orchestrator/skills/session-management.md \
       plugins/aid-orchestrator/commands/aid-setup.md \
       plugins/aid-orchestrator/defaults/policies/memory-config.yaml
git commit -m "feat(knowledge): Qdrant as cross-project knowledge store with project tagging

Qdrant is now the single cross-project knowledge database. All entries tagged
with project_name and tech_stack. IDLE state searches cross-project lessons
before planning. EXECUTING state includes relevant cross-project knowledge
in agent dispatch. /aid-setup explains WHY Qdrant matters for cross-project
learning. Graceful degradation: no Qdrant = per-project only."
```

---

### Task 23: Backlog Categorization by Type and Source

**Why:** User wants backlog split by type (refactoring, bug, new feature) and source (user-submitted vs AI-generated).

**Files:**
- Modify: `plugins/aid-orchestrator/agents/curator.md` (proposal format)
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` (backlog template)

**Step 1: Update backlog template structure**

In `commands/aid-init.md`, update the backlog.md template to include categorized sections:

```markdown
### Updated backlog.md Template

```markdown
# AID Backlog

## Active Proposals

### Bugs
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Features
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Refactoring / Tech Debt
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Performance
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

## Deferred
| ID | Type | Priority | Source | Summary | Reason |
|----|------|----------|--------|---------|--------|

## Rejected
| ID | Type | Source | Summary | Reason |
|----|------|--------|---------|--------|

## Implemented
| ID | Type | Source | Summary | Implemented In |
|----|------|--------|---------|----------------|
```

**Source values:** `user` (submitted by PM), `agent` (discovered by AI agent during EPIC),
`curator` (proposed by Curator post-processing), `audit` (found by Auditor).
```

**Step 2: Update Curator agent to include source and categorize**

In `agents/curator.md`, update the proposal format to include `source` and map to correct category:

```markdown
### Proposal Categorization

When generating proposals, classify each into a category:

- `bug` — something is broken or produces wrong results
- `feature` — new capability not currently present
- `refactoring` — code improvement without behavior change
- `performance` — speed, memory, or token optimization

And track the source:

- `agent` — discovered by a role agent during step execution
- `curator` — identified by Curator's pattern analysis
- `audit` — found by Auditor's compliance check

The Curator writes proposals to the correct section of backlog.md based
on the category. A `bug` goes under "### Bugs", a `feature` under
"### Features", etc.
```

**Step 3: Store proposals in Qdrant for cross-project pattern detection**

In `agents/curator.md`, after writing to backlog.md, add Qdrant write:

```markdown
### Qdrant Proposal Storage

For each proposal, if Qdrant available, store:

```json
{
  "collection_name": "aid-memory",
  "data": "Proposal: {summary}. Category: {category}. Found during {epic_id} step {step_id}. {details}",
  "metadata": {
    "type": "proposal",
    "category": "bug|feature|refactoring|performance",
    "source": "curator|agent|audit",
    "project_name": "{project_name}",
    "epic_id": "{epic_id}",
    "priority": "high|medium|low",
    "timestamp": "{ISO 8601}"
  }
}
```

Cross-project value:
- Planner queries proposals at IDLE: "known issues for {tech_stack}"
- Analytics tracks recurring proposal patterns across projects
- Agents can read relevant proposals before starting work
```

**Step 4: Commit**

```bash
git add plugins/aid-orchestrator/agents/curator.md \
       plugins/aid-orchestrator/commands/aid-init.md
git commit -m "feat(backlog): categorize by type/source + store proposals in Qdrant

Backlog.md split into Bug/Feature/Refactoring/Performance sections.
Each proposal tagged with source (user/agent/curator/audit).
Proposals also indexed in Qdrant for cross-project pattern detection."
```

---

### ~~Task 24: Validate Worktree Isolation with Real Parallel EPIC~~ (DEFERRED — not in v0.3.0)

**Why:** Worktree dispatch code was written but never exercised with a real parallel EPIC (PROP-008). Need a validation EPIC.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/templates/epic-example-parallel.md`

**Step 1: Create a parallel validation EPIC example**

Create `plugins/aid-orchestrator/defaults/templates/epic-example-parallel.md`:

```markdown
# EPIC: VALIDATION-001 — Worktree Parallel Dispatch Validation

## Context
This EPIC validates that AID's worktree-based parallel dispatch works correctly.
It exercises parallel agent execution with real file modifications in isolated
worktrees, verifying that merge conflicts are detected and resolved.

## Goal
Validate worktree isolation by running backend and frontend agents in parallel,
each modifying files in their respective directories, and successfully merging
the results.

## Scope

### Allowed files/paths
- backend/
- frontend/
- docs/

### Forbidden zones
- .aid-o/03-config/

## Artifacts
- Backend API endpoint (1 simple endpoint)
- Frontend component (1 simple component)
- Shared type definition (tests conflict detection)
- Documentation

## Constraints
- Budget: $10 max LLM cost
- Dispatch strategy: worktrees (mandatory for this validation)

## DoD Gates
- tests_pass
- lint_pass

## Acceptance Criteria
- [ ] Backend and frontend ran in separate worktrees
- [ ] Both produced file modifications
- [ ] Worktrees were created and cleaned up
- [ ] Merge completed without manual intervention
- [ ] dispatch_log.json shows per-agent timing
- [ ] No files from one agent leaked into the other's worktree

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Define shared types and API contract | — | — |
| 2 | backend | Implement API endpoint | architect | group-1 |
| 3 | frontend | Implement UI component | architect | group-1 |
| 4 | qa | Test both implementations | backend, frontend | — |

## Notes
This is a VALIDATION epic — its purpose is to test AID infrastructure,
not to produce production software. Keep implementations minimal.
```

**Step 2: Add validation instructions to /aid-help**

In `commands/aid-help.md`, mention the validation EPIC in the `config` or `workflow` topic:

```markdown
### Validating Parallel Dispatch

To validate that worktree isolation works in your environment:

1. Copy `defaults/templates/epic-example-parallel.md` to `.aid-o/02-epics/`
2. Set `dispatch-strategy.yaml → strategy: worktrees`
3. Run `/run-epic E-validation-001`
4. Check evidence for dispatch_log.json with per-agent worktree paths
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/defaults/templates/epic-example-parallel.md \
       plugins/aid-orchestrator/commands/aid-help.md
git commit -m "feat(validation): add parallel worktree validation EPIC template

PROP-008. Provides a ready-to-run EPIC that exercises worktree isolation with
parallel backend+frontend agents, conflict detection, and merge verification."
```

---

### ~~Task 25: Benchmark Framework — AID vs. Vanilla Claude Code~~ (DEFERRED — not in v0.3.0)

**Why:** Need to quantify the value AID adds vs. vanilla Claude Code with superpowers. This informs optimization priorities.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/templates/epic-benchmark.md`
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` (add benchmark topic)

**Step 1: Create benchmark EPIC template**

Create `plugins/aid-orchestrator/defaults/templates/epic-benchmark.md`:

```markdown
# EPIC: BMK-{NNN} — Benchmark: {Topic}

## Context
Benchmark EPIC for comparing AID-orchestrated development against manual
Claude Code development. The same specification will be implemented twice:
once with AID (/run-epic) and once manually (direct Claude Code session).

## Benchmark Metrics

Track these metrics for both runs:

| Metric | AID Run | Manual Run |
|--------|---------|------------|
| Total duration (minutes) | | |
| Total tokens consumed | | |
| Files created/modified | | |
| Test count | | |
| Test pass rate | | |
| Lint issues found | | |
| Security issues found | | |
| Lines of code produced | | |
| Number of PM interactions | | |
| Number of errors/retries | | |

## Comparison Criteria

1. **Quality:** Test coverage, lint cleanliness, security, code structure
2. **Speed:** Wall-clock time from start to finish
3. **Cost:** Token consumption (translates to API cost)
4. **Completeness:** How many acceptance criteria were met
5. **Evidence:** Audit trail quality (AID advantage)
6. **Consistency:** Reproducibility of results

## How to Run

### AID Run
1. `/plan-epic .aid-o/02-epics/BMK-{NNN}.md`
2. `/run-epic BMK-{NNN}`
3. Record metrics from evidence/final_report.md

### Manual Run
1. Start fresh Claude Code session (no AID commands)
2. Paste the Goal and Acceptance Criteria
3. Build manually with Claude Code
4. Record metrics manually (time, files, tests)

### Comparison
1. Fill in the metrics table above
2. Write a comparison summary
3. Add to `.aid-o/04-engine/evidence/benchmarks/BMK-{NNN}/comparison.md`
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/defaults/templates/epic-benchmark.md \
       plugins/aid-orchestrator/commands/aid-help.md
git commit -m "feat(benchmark): add benchmark EPIC template for AID vs. vanilla Claude comparison

Template with structured metrics table for comparing AID-orchestrated vs.
manual Claude Code development: duration, tokens, quality, cost, evidence."
```

---

### Task 26: Analytics Skill + /aid-analytics Command

**Why:** Task 6 stores rich per-agent metrics (timing, self-report, gate results, EPIC summaries) in Qdrant. But raw data without analysis is useless. PM needs a dedicated skill/command to query these metrics, identify patterns, and get actionable optimization recommendations.

**Decision rationale:** PM confirmed:
- Analytics should be a manually-invoked skill, NOT automatic during orchestration (avoid slowing the pipeline)
- `/aid-analytics` will be listed as a recommended option after EPIC completion (Task 8)
- The skill must deeply understand the metric schema from Task 6 (types: `agent_execution`, `epic_summary`, `gate_result`)
- Reports must be actionable — not just "backend was slow" but "backend is consistently slow on test-writing steps; consider splitting into implementation + test steps"

**Files:**
- Create: `plugins/aid-orchestrator/skills/analytics.md`
- Create: `plugins/aid-orchestrator/commands/aid-analytics.md`
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` (add analytics topic)

**Step 1: Create analytics skill**

Create `plugins/aid-orchestrator/skills/analytics.md`:

```markdown
---
name: analytics
description: Analyze orchestration metrics from Qdrant to identify performance patterns, bottlenecks, and optimization opportunities across EPICs and projects.
---

# Analytics Skill

## Purpose

Query Qdrant metric entries (type: "metric") and produce actionable reports
on agent performance, gate efficiency, and orchestration health.

## Metric Types Available

These are stored by the orchestration engine (Task 6) in `aid-memory` collection:

| metric_kind | Stored at | Contains |
|---|---|---|
| `agent_execution` | PHASE_CHECK | Per-step: duration, complexity, bottleneck, errors, files touched |
| `epic_summary` | DONE | Per-EPIC: total duration, step count, slowest step, gate retries |
| `gate_result` | DONE | Per-gate: pass/fail, retries, duration |

All metrics include `project_name`, `epic_id`, and `timestamp`.

## Report Types

### 1. EPIC Report (single EPIC)
Query: all metrics where `epic_id` = {target}

Output:
- Timeline: step-by-step execution with duration bars
- Bottleneck analysis: which steps took longest and WHY (from self-report)
- Error summary: what went wrong and how it was resolved
- Gate performance: which gates failed, retry count, time cost of retries
- Recommendation: specific actionable suggestions (e.g., "Step 3 spent 45%
  of time — consider splitting into 2 smaller steps")

### 2. Project Trends (across EPICs in one project)
Query: all metrics where `project_name` = {target}

Output:
- Trend chart: average EPIC duration over time (improving or regressing?)
- Common bottlenecks: which agent roles are consistently slowest
- Error hotspots: recurring error patterns across EPICs
- Gate efficiency: which gates cause the most retries
- Recommendation: systemic improvements (e.g., "tests_pass gate fails in 60%
  of EPICs — improve pre-lint or test generation quality")

### 3. Cross-Project Comparison
Query: all `epic_summary` metrics across all projects

Output:
- Project ranking: by avg EPIC duration, error rate, gate pass rate
- Best practices: what the fastest projects do differently
- Knowledge transfer: lessons from fast projects applicable to slow ones

## How to Query Qdrant

Use the memory-mcp search tool:
```json
{
  "collection_name": "aid-memory",
  "query": "agent execution metrics for {epic_id}",
  "filter": {
    "must": [
      {"key": "type", "match": {"value": "metric"}},
      {"key": "epic_id", "match": {"value": "{epic_id}"}}
    ]
  },
  "limit": 50
}
```

For trends, omit `epic_id` filter and include `project_name`.

## Output Format

Present results as:
1. **Executive Summary** — 3-5 bullet points with key findings
2. **Detailed Metrics Table** — tabular data with all numbers
3. **Bottleneck Analysis** — ranked list with WHY explanation
4. **Recommendations** — numbered, specific, actionable items
5. **Comparison** (if applicable) — before/after or cross-project

## Important

- If Qdrant has no metrics yet, inform PM and suggest running an EPIC first
- Always include sample size (N EPICs analyzed, N steps analyzed)
- Mark recommendations with confidence: HIGH (clear pattern), MEDIUM (emerging
  pattern), LOW (insufficient data)
```

**Step 2: Create /aid-analytics command**

Create `plugins/aid-orchestrator/commands/aid-analytics.md`:

```markdown
---
name: aid-analytics
description: Analyze orchestration performance metrics and get optimization recommendations
user_invocable: true
---

# /aid-analytics

## Usage

`/aid-analytics [scope]`

Where scope is one of:
- `{epic_id}` — analyze a specific EPIC (e.g., `/aid-analytics BMK-001`)
- `project` — analyze trends across all EPICs in current project
- `global` — compare across all projects (requires Qdrant with multi-project data)
- (no argument) — defaults to the most recently completed EPIC

## Prerequisites

- Qdrant must be configured and accessible (see /aid-setup)
- At least one EPIC must have been completed with metrics (Task 6 format)
- For project/global scope: multiple completed EPICs provide better analysis

## Process

1. Load the `analytics` skill
2. Determine scope from argument (default: last completed EPIC)
3. Query Qdrant for relevant metrics
4. Generate report with findings and recommendations
5. Present to PM in chat

## Output

Structured report with:
- Executive summary
- Detailed metrics
- Bottleneck analysis with root causes
- Actionable recommendations with confidence levels
```

**Step 3: Add analytics topic to aid-help.md**

In `commands/aid-help.md`, add to the topic list:

```markdown
### Topic: analytics
- **What:** Performance analysis of orchestration metrics
- **When:** After completing one or more EPICs, to identify optimization opportunities
- **Command:** `/aid-analytics [epic_id | project | global]`
- **Requires:** Qdrant configured, at least one completed EPIC with metrics
- **Related:** Task 6 (metric collection), Task 22 (cross-project knowledge)
```

**Step 4: Commit**

```bash
git add plugins/aid-orchestrator/skills/analytics.md \
       plugins/aid-orchestrator/commands/aid-analytics.md \
       plugins/aid-orchestrator/commands/aid-help.md
git commit -m "feat(analytics): add analytics skill and /aid-analytics command

New skill queries Qdrant metrics (agent_execution, epic_summary, gate_result)
to produce actionable performance reports. Supports per-EPIC, per-project,
and cross-project analysis with bottleneck root causes and recommendations."
```

---

## Summary

| Phase | Tasks | Files Modified | Files Created | Key Impact |
|-------|-------|---------------|---------------|------------|
| **P1: Critical Bugs** | 1-4 | 8 | 1 | Engine reliability |
| **P2: Performance** | 5-7 | ~25 | 1 | ~80% cost reduction (model selection + file scoping + dispatch trimming + token tracking) |
| **P3: Lifecycle** | 8-13 | 6 | 0 | Complete EPIC lifecycle |
| **P4: UX/Onboarding** | 14-21 | 7 | 0 | Smooth first experience |
| **P5: Knowledge** | 22-23, 26 | 6 | 3 | Cross-project learning + analytics |
| **DEFERRED** | 24, 25 | — | — | Worktree validation, Benchmark |
| **TOTAL** | **24 active tasks** | **~22 unique files** | **6 new files** | |

### Version Bump

After all tasks complete:
- `plugins/aid-orchestrator/.claude-plugin/plugin.json` → version `0.3.0`
- `.claude-plugin/marketplace.json` → version `0.3.0`
- `CHANGELOG.md` → add v0.3.0 section with all changes
- Git tag: `v0.3.0`

### Commit History Target

26 focused commits, one per task. Each commit is self-contained and the plugin
remains valid after every commit.
