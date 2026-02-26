---
sidebar_position: 3
title: "dispatch-strategy.yaml"
description: "Reference for dispatch-strategy.yaml — parallel vs. sequential agent dispatch, git worktree isolation, branch naming, and fallback behavior."
---

# dispatch-strategy.yaml

**Location:** `.aid-o/03-config/policies/dispatch-strategy.yaml`

This file controls how the Controller isolates work when it dispatches multiple agents in parallel. Parallelism is central to AID's performance: independent steps (for example, a backend step and a frontend step with no shared files) can run at the same time instead of one after another. This file determines the isolation mechanism used when that happens.

---

## Full Default Configuration

The default file installed by `/aid-init` (source: `plugins/aid-orchestrator/defaults/policies/dispatch-strategy.yaml`):

```yaml
dispatch:
  strategy: "worktrees"

  worktrees:
    base_dir: ".aid-o/worktrees"
    cleanup_on_merge: true
    cleanup_on_failure: false
    max_parallel: 4

  branches:
    prefix: "aid/"
    include_epic_id: true
    delete_on_merge: true
    base_branch: "main"

  sequential:
    stash_before_step: true
    restore_on_failure: true

  fallback:
    on_worktree_failure: "branches"
    on_branch_failure: "sequential"
    log_fallback: true
```

---

## dispatch.strategy

The top-level strategy setting. Three options are available:

| Value | Description | When to use |
|---|---|---|
| `worktrees` | Each agent gets a dedicated git worktree in `.aid-o/worktrees/<step_id>/` | Default; recommended for all projects with git 2.15+ |
| `branches` | Agents share the working tree but operate on separate branches | When filesystem space is constrained |
| `sequential` | No parallelism — steps run one at a time in the current working tree | Small EPICs, CI environments, or when isolation is not needed |

The `worktrees` and `branches` sections are always present in the file; only the section matching `strategy` is active. `fallback` always applies.

---

## Worktrees Strategy (default)

**Requirement:** git 2.15 or newer.

Git worktrees give each agent a complete, independent filesystem checkout of the repository under `.aid-o/worktrees/<step_id>/`. Agents can run builds, tests, and install dependencies without affecting each other's working trees. This is the strongest isolation available and is the default.

```yaml
worktrees:
  base_dir: ".aid-o/worktrees"
  cleanup_on_merge: true
  cleanup_on_failure: false
  max_parallel: 4
```

### `base_dir`

Root directory where all worktree checkouts are created. Each step gets a subdirectory: `.aid-o/worktrees/<step_id>/`. The Controller creates these directories automatically; you do not need to create them manually.

The default `.aid-o/worktrees` keeps agent isolation contained within the AID workspace. Change this if your disk layout requires worktrees to be placed elsewhere:

```yaml
worktrees:
  base_dir: "/tmp/aid-worktrees"   # Use /tmp for ephemeral environments
```

### `cleanup_on_merge`

`true` — after a step completes successfully and its changes are merged to the base branch, the worktree directory is deleted. This keeps the working directory clean.

`false` — worktrees are preserved after merge. Use this if you want to inspect the final state of each agent's work.

### `cleanup_on_failure`

`true` — delete the worktree after a step fails. Use this to keep disk usage low in CI.

`false` (default) — preserve the worktree after a failure. This lets you inspect the agent's partial work to understand what went wrong. Recommended for development environments.

### `max_parallel`

Maximum number of worktrees (and thus agents) running concurrently. Default is `4`. Setting this to `0` means unlimited — all eligible parallel steps dispatch at once.

Tune this based on your machine's resources. Running 8 parallel agents on a laptop will saturate CPU and memory; `max_parallel: 2` or `3` is more appropriate.

```yaml
worktrees:
  max_parallel: 2    # Conservative — suitable for development machines
```

---

## Branches Strategy

When `strategy: "branches"`, agents create separate git branches and commit their work there. They share the same working tree directory, which means there is risk of file collisions if two parallel agents write to the same path. The Controller uses the plan's `allowed_paths` to separate agent domains and reduce collision risk, but this strategy is less safe than `worktrees` for large parallel groups.

```yaml
branches:
  prefix: "aid/"
  include_epic_id: true
  delete_on_merge: true
  base_branch: "main"
```

### `prefix`

The branch name prefix. Branches are named `aid/<epic_id>/<step_id>` when `include_epic_id` is true, or `aid/<step_id>` when it is false.

Change this if your repository has branch naming conventions:

```yaml
branches:
  prefix: "feature/aid/"   # Creates: feature/aid/<epic_id>/<step_id>
```

### `include_epic_id`

`true` (default) — EPIC ID is included in the branch name, making it easy to find all branches for a given EPIC: `aid/E-20260201-api-v2/step-3-backend`.

`false` — branch names are shorter: `aid/step-3-backend`.

### `delete_on_merge`

`true` (default) — feature branches are deleted from the repository after they are merged to `base_branch`.

`false` — branches are kept. Use this if your team reviews merged branches or your CI system references them.

### `base_branch`

The branch all agents fork from and merge back into. Default is `"main"`. Change this if your project uses a different primary branch:

```yaml
branches:
  base_branch: "develop"   # For Gitflow-style projects
```

---

## Sequential Strategy

When `strategy: "sequential"`, all steps run one at a time in the current working tree. No branches or worktrees are created. This is the simplest option and requires no git configuration beyond a standard initialized repository.

```yaml
sequential:
  stash_before_step: true
  restore_on_failure: true
```

### `stash_before_step`

`true` (default) — the Controller runs `git stash` before each step to preserve any uncommitted changes in the working tree. This prevents agent steps from mixing with any work you have in progress.

`false` — no stash. Use this when your working tree is always clean before EPIC execution (standard CI pipelines).

### `restore_on_failure`

`true` (default) — if a step fails, `git stash pop` is called to restore the working tree to the state before the step started.

`false` — the working tree is left in whatever state the failing step left it. Use `false` when you want to manually inspect partial step output.

---

## Fallback Behavior

The Controller attempts the configured strategy first. If that strategy fails (for example, the worktree directory cannot be created because of filesystem permissions), it falls back in the order defined here.

```yaml
fallback:
  on_worktree_failure: "branches"
  on_branch_failure: "sequential"
  log_fallback: true
```

### `on_worktree_failure`

What to do if worktree creation fails. Options: `"branches"` or `"sequential"` or `"abort"`.

Default is `"branches"` — fall back to branch isolation if worktrees are unavailable. This can happen when:
- git version is below 2.15
- Filesystem does not support symlinks
- The `.aid-o/worktrees` directory has permission issues

### `on_branch_failure`

What to do if branch creation fails. Options: `"sequential"` or `"abort"`.

Default is `"sequential"` — fall back to sequential execution if branching fails. This can happen when the remote repository has branch protection rules that block local branch creation.

### `log_fallback`

`true` (default) — when a fallback triggers, a warning event is written to the evidence log and the Slack status channel (if configured). This makes fallbacks visible and auditable.

`false` — silent fallback. Not recommended.

---

## Choosing a Strategy

### Use worktrees when:
- Your project has a git repository at version 2.15+
- Steps regularly touch overlapping paths and need true filesystem isolation
- Steps run builds, install packages, or start servers (these need independent working trees)
- You want the strongest parallel isolation with the least risk of conflicts

### Use branches when:
- Disk space is constrained and you cannot afford multiple full checkouts
- Parallel steps have cleanly separated `allowed_paths` with no overlap
- Your git version does not support worktrees

### Use sequential when:
- Running in a CI environment where workspace storage is ephemeral
- The EPIC has a small number of steps that do not benefit from parallelism
- You are debugging an EPIC and want to observe each step's output before the next begins
- The project is a single-file script or very small codebase

---

## Example: CI/CD Configuration

For a CI environment where builds run in a fresh clone and parallel jobs are managed externally:

```yaml
dispatch:
  strategy: "sequential"

  sequential:
    stash_before_step: false    # CI workspace is always clean
    restore_on_failure: false   # CI will discard the workspace on failure anyway

  fallback:
    on_worktree_failure: "sequential"
    on_branch_failure: "sequential"
    log_fallback: true
```

## Example: Resource-Constrained Development Machine

For a laptop with limited RAM where running 4 parallel builds would cause thrashing:

```yaml
dispatch:
  strategy: "worktrees"

  worktrees:
    base_dir: ".aid-o/worktrees"
    cleanup_on_merge: true
    cleanup_on_failure: true    # Save disk space even on failure
    max_parallel: 2             # Only 2 agents at a time

  fallback:
    on_worktree_failure: "sequential"
    on_branch_failure: "sequential"
    log_fallback: true
```

---

## Related

- [Parallel Dispatch](../skills/parallel-dispatch) — how the Controller reads this file and manages parallel groups
- [Epic Orchestration](../skills/epic-orchestration) — the state machine that dispatches agents
- [gates.yaml](./gates-yaml) — gates that run after steps complete
