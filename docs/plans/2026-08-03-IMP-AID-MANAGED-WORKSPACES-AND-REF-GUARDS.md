# AID Managed Workspaces, Protected Refs and Isolated Fast Mode

**Status:** proposed implementation plan; no production change is authorized by
this document alone.
**Prepared:** 2026-08-03.
**Scope:** AID workspace ownership, concurrent work, branch/ref safety,
`/aid-do` isolated execution and controlled integration.
**Relationship:** complements the plan-boundary recovery work. It must not
change the meaning of a frozen candidate, a normal plan-final review or a
regular evidence/gate PASS.

## 1. Problem and product outcome

AID currently has deterministic plan/task branch names and serializes selected
plan operations, but its execution model still assumes a shared checkout. Two
independent `/aid-run` controllers can work at the same time in that checkout,
and a fast-mode `/aid-do` task directly changes its current branch. An agent
can consequently start from a branch another agent is using, leave it dirty,
commit unexpected files, or move a ref that invalidates a plan-final candidate.

The P083/PWA dogfood made the failure concrete: `main` moved from the P083
control-plane commits to `release/0.14.0`. The P083 commits survived on
`plan/P083`, but the committed lifecycle manifest disappeared from `main`; the
mode resolver therefore correctly refused to guess a release model. The
important lesson is not merely "do not reset main": AID needs a model in which
agents do not normally receive `main`, `plan/*` or another agent's task branch
as their working directory.

The desired normal experience is:

```text
/aid-do "small follow-up"
  → AID creates one isolated workspace and branch
  → the agent changes only that workspace
  → the agent commits only its own branch
  → AID verifies and reports a ready-to-merge result
  → the PM explicitly authorizes the merge
```

The PM can work on several independent things at once. An agent never starts
on a partially completed branch without explicit PM/controller approval, and
no ordinary agent action silently moves a protected ref or a frozen candidate.

## 2. Current-state grounding

### What already works

- `plan/<plan_id>` is the plan integration branch and
  `task/<epic_id>/main` is the EPIC branch. `epic-start` records the exact plan
  SHA under a plan lock; `epic-merge-to-plan` verifies lineage and supports an
  expected plan-head check before merging.
- The default `dispatch.max_parallel: 1` serializes mutable step work inside
  one `/aid-run` controller. It is not a global repository scheduler.
- Agent instructions say that the controller normally owns commits, FSM state,
  branch changes and finalization. The pre-commit hook limits staged files to
  the run's declared scope when its dependencies are available.
- Plan-final logic correctly treats any tracked candidate write as a fix and
  invalidates the candidate/review cycle.

### Gaps this plan closes

1. Two `/aid-run` processes for two plans each observe `max_parallel: 1`, but
   may still run simultaneously. There is no cross-plan workspace allocation,
   global branch lease or shared-worktree collision guard.
2. `aid-fsm.sh init` can auto-checkout its task branch from main; a linked
   worktree intentionally bypasses its ordinary branch-enforcement arm. This
   is not a safe admission policy for concurrent work.
3. The declared `worktree_base` and historical parallel-worktree prose are not
   a complete runtime workspace manager. There is no durable owner/base/lease
   record, no agent-specific worktree allocation and no merge queue.
4. `/aid-do` is user-invocable but currently edits the caller's current
   checkout and makes its mandatory commit there. It is therefore unsafe for
   concurrent quick work.
5. Git worktrees share one `.git` directory. They prevent ordinary checkout
   collisions, but an arbitrary shell with the same filesystem permissions can
   still move another ref. A worktree is strong accidental-isolation, not a
   security sandbox.

## 3. Decisions

### D1 — `/aid-do` is the public entry point; workspace commands are internal

Do not expose `/aid-workspace` as a user-facing command. Implement a private
script/library (provisional name `aid-workspace.sh`) used by `/aid-do` and by
the `/aid-run` controller. The public interface remains small:

```text
/aid-do "description"                    # isolated workspace by default
/aid-do --target plan/P083 "description" # explicit protected target
/aid-do --resume Q-042                    # explicit resume of own workspace
/aid-do --in-place "description"          # explicit exceptional shared checkout
```

`--in-place` must show the active branch, existing AID leases and a concise
warning before it may write. It is never silently selected as a fallback after
workspace creation fails.

### D2 — managed workspaces and one authoritative registry

The internal workspace manager creates and owns a gitignored runtime registry,
for example `.aid-o/work/workspaces/registry.json`. Every record contains:

```yaml
workspace_id: Q-042 | W-E-083-2_2-R-E083-2-S0-A1
kind: quick | step | integration | review
owner: pm | controller | agent:<stable-dispatch-id>
branch: quick/Q-042 | work/E-083-2_2/R-E083-2/s-0/a-1
path: .aid-o/workspaces/quick/Q-042
base_ref: main | plan/P083 | task/E-083-2_2/main
base_sha: <40-hex immutable SHA>
target_ref: main | plan/P083 | task/E-083-2_2/main
state: allocated | active | submitted | merging | merged | stale | abandoned
created_at: <RFC3339>
lease_expires_at: <RFC3339>
```

All writes use an exclusive workspace-registry lock. A workspace is created
from the recorded `base_sha`, never a moving branch name read twice. A second
agent cannot acquire a workspace that is `allocated`, `active`, `submitted` or
`merging`; expiry makes it `stale`, not automatically reusable.

The canonical paths are under `.aid-o/workspaces/` rather than the existing
`.claude/worktrees/` default, so AID-owned runtime data and agent sandboxes are
discoverable in one place. The implementation may retain a configurable base
directory, but one effective path must be printed in every handoff.

### D3 — branch vocabulary and ownership

These prefixes have one meaning and one writer:

| Branch | Owner | Purpose | May an agent write it directly? |
|---|---|---|---|
| `main` / configured target | PM + target merge controller | released/integrated target | No |
| `plan/P083` | plan controller | integration for one plan | No |
| `task/E-083-2_2/main` | EPIC controller | verified EPIC integration | No |
| `work/E-083-2_2/R-E083-2/s-0/a-1` | named agent | one planned mutable assignment | Yes, only in its own workspace |
| `quick/Q-042` | named quick-task agent | one fast-mode change | Yes, only in its own workspace |
| `integrate/E-083-2_2/wave-0` | integration controller/role | controlled conflict resolution | No, except explicitly delegated integration role |
| `aid-evidence/...` | AID evidence producer | immutable evidence references | No source-code work |

Branches are append-only for their owner. No agent may use `git checkout`,
`git switch`, `git merge`, `git rebase`, `git reset`, `git branch -f`, ref
deletion or remote push unless the dispatch explicitly delegates the one named
operation. Agent instructions must name the assigned worktree path, branch,
base SHA, allowed paths, output path and submission action.

### D4 — explicit admission and resume

Creating a mutable workspace is an admission operation. The manager must:

1. resolve the requested target/ref to one SHA once;
2. reject a dirty target workspace, in-progress merge/rebase, detached target
   or target ref protected by an active finalization lease;
3. reject a branch/worktree that is already leased to another owner;
4. create the private branch and worktree, then atomically record the lease;
5. print the exact workspace path and forbid use of the caller's checkout.

Resuming is never inferred from a matching branch name. `/aid-do --resume
Q-042` requires the workspace record to name an eligible owner and state. A
different agent/controller or an expired lease requires explicit PM takeover
and an audited `workspace_takeover` event.

### D5 — submit and merge queue

An agent finishes by submitting a branch tip, test receipt and evidence. It
does not alter `task/*`, `plan/*` or `main`.

The controller then performs, in order:

1. re-read the workspace record and ensure submitter/branch/tip match;
2. validate allowed paths, declared test receipt and base ancestry;
3. compare the target's current SHA to the recorded target/base policy;
4. run a dry merge (`merge-tree` or equivalent) before moving a ref;
5. create the merge through the relevant AID transaction with expected-head
   compare-and-swap protection;
6. record the merge SHA, mark the workspace `merged` and clean it only after
   durable state is written.

For a parallel wave, every agent starts from the same recorded base SHA.
Submitted changes enter a deterministic queue ordered by declared step number,
then workspace id. The target moves only one time per accepted entry. A changed
target is not silently rebased: the controller either creates a fresh
integration attempt or reports a stale submission.

### D6 — conflicts have an owner and never become a raw-Git repair

If dry merge finds a conflict:

- no source branch is rewritten and no target ref moves;
- the affected submissions are marked `conflict` with file-level evidence;
- the controller creates `integrate/<scope>/<wave>` from the observed target
  SHA in a dedicated integration workspace; and
- only an explicitly delegated integration role may make a resolution commit.

The integration controller reruns the required checks, records provenance of
both submitted branches, and then performs the normal expected-head merge.
Semantic/product conflicts or a conflict touching a frozen candidate cause PM
escalation; the system must not choose a product behavior by itself.

### D7 — protected refs, tamper detection and authority boundary

The manager maintains a protected-ref ledger for target branches, all active
`plan/*` branches and all active `task/*` branches. Each entry records the last
authorized SHA, operation id, actor and timestamp.

Every AID state-changing operation first compares the live ref to that ledger.
An unexpected movement produces `target_ref_tampered`, includes old/new SHA
and reflog evidence where available, takes no automatic recovery action and
blocks ordinary merge/finalize/init actions until the PM chooses recovery or
uses the audited universal `--force` path.

Install a Git reference-transaction hook as an accidental-change guard: it
rejects local changes to protected refs unless an AID transaction has an
invocation-scoped authorization record. The hook, command wrappers and agent
instructions are defence in depth, not a security claim: an agent with the
same Unix identity and unconstrained shell can still bypass local policy.

For a strong boundary, add optional `isolation: clone` mode. The agent receives
a disposable clone/container without the primary checkout's `.git`; it returns
a signed commit/bundle/patch that the controller imports into its managed merge
queue. Use this mode for untrusted agents, sensitive repositories or a
repeated-ref-tampering project. Worktree isolation is the default because it
is faster and convenient; clone isolation is the security upgrade.

### D8 — frozen-candidate behavior is explicit

`/aid-do --target plan/P083` must query plan state before allocating a
workspace:

- before freeze: it may create a quick branch from the plan ref and submit to
  the plan merge queue;
- after freeze through final review: it displays that a merge changes the
  candidate, invalidates gates/reviews and requires explicit PM confirmation;
- after merge/close: it refuses that target and directs the PM to a new plan or
  normal target-branch quick task.

No generated report, quick task or agent commit may land directly in a frozen
candidate worktree.

## 4. `/aid-do` isolated flow

### Default quick task

1. Resolve project root and validate AID installation.
2. Allocate `Q-NNN` under the registry with target `main` and record the
   current main SHA. If an active plan/finalization owns main, show that fact;
   do not silently target its plan branch.
3. Create `quick/Q-NNN` and its worktree. Dispatch the agent exclusively in
   that directory with agent-protocol Git rules.
4. Agent implements, runs targeted checks and commits only `quick/Q-NNN`.
5. Controller writes the quick log on the quick branch, validates the result,
   records `submitted`, and reports `Ready to merge Q-NNN into main`.
6. Only explicit PM instruction triggers the merge transaction. A merge checks
   that the recorded main SHA is still valid, or reports the submission stale.

### Explicit plan/EPIC target

`--target` must be explicit for `plan/*` and `task/*`; plain `/aid-do` never
guesses that a quick change belongs to active work. The handoff must say
whether it is merging to a plan (not released), task branch (not yet EPIC
complete) or target branch (integrated/released according to project policy).

### Exceptional in-place mode

`--in-place` is for a PM who knowingly wants today's direct behavior. It checks
for all active leases, displays the current branch/ref and does not create a
workspace. It remains subject to normal Git hooks and AID diagnostics but
cannot promise isolation. This option is deliberately noisy and never used by
automation.

## 5. P083 reset recovery model

The immediate P083 incident should be resolved without rewriting `plan/P083`:

1. Do **not** rebase the active P083 plan/task history merely because `main`
   moved to the PWA release. Its eventual plan-final `sync` is the normal place
   to merge the current target branch and resolve any real conflict.
2. Restore the P083 committed control plane to `main` in one new corrective
   commit: lifecycle manifest, current source-plan document and current
   uncompleted EPIC definition(s). Do not cherry-pick gitignored runtime
   locks/state, task implementation commits or stale queue transitions.
3. Confirm the lifecycle manifest's mode and source-plan hash against that
   committed control plane, then re-run the supported EPIC admission/recovery
   path. If existing P083 runtime lineage is inconsistent, use its audited
   recovery transaction; do not repair it with raw `branch -f`, reset or a
   history rewrite.
4. Record the unexpected `main` move in the protected-ref ledger as
   `target_ref_tampered`; no ordinary agent should resume automated integration
   until this is acknowledged.

The current incident demonstrates why the system needs both managed workspaces
(prevention of ordinary collisions) and protected-ref detection (truthful halt
after a direct mutation still occurs).

## 6. Implementation slices

### Slice 1 — grounding and registry library

1. Inventory every current caller that creates worktrees, checks out branches,
   commits, merges, deletes branches or writes plan/task refs.
2. Define workspace and protected-ref schemas, path derivation, atomic
   registry writes, lock behavior, ownership/takeover and stale semantics.
3. Implement a sourceable workspace library plus a CLI used only by AID
   controllers; do not yet change `/aid-do` behavior.
4. Add fixtures for concurrent acquisition, stale lease, crash after worktree
   creation, crash after registry write and worktree cleanup safety.

### Slice 2 — protected ref authority

5. Implement protected-ref ledger snapshots and pre-operation verification in
   plan start, EPIC start/merge, plan finalization, target merge and close.
6. Implement `target_ref_tampered` reporting with both Git ref and reflog
   evidence; no automatic rewind or repair.
7. Add reference-transaction hook integration with an invocation-scoped AID
   authorization capability; document its accidental-guard limitation.
8. Add tests for direct reset/forced update detection, ordinary authorized
   transaction acceptance and absent-tool fail-safe disclosure.

### Slice 3 — internal isolated workspace dispatch

9. Make `/aid-run` allocate an agent worktree/branch for every mutable agent
   dispatch, while retaining existing read-only immutable-review worktrees.
10. Add dispatch payload fields: workspace id/path, branch, immutable base SHA,
    target ref, lease expiry and submit-only Git contract.
11. Update agent protocol, implementer, verifier and controller instructions;
    mechanically forbid vague "use current checkout" wording on live surfaces.
12. Implement submit validation and a deterministic merge queue for sequential
    steps first. Keep `dispatch.max_parallel: 1` until this path is proven.

### Slice 4 — parallel waves and conflict integration

13. Enable worktree parallelism only for plan-declared independent groups with
    disjoint declared ownership or an explicit PM override.
14. Implement common-base allocation, deterministic submission order,
    merge-tree preflight, stale-target handling and dedicated integration
    workspaces.
15. Add conflict, same-file, target-moved, abandoned-agent and crash-resume
    end-to-end fixtures. A conflict must never modify source branches.

### Slice 5 — `/aid-do` migration

16. Change `/aid-do` to isolated-by-default and add `--target`, `--resume` and
    explicit `--in-place` behavior. Preserve its Fast Mode scope/CP6 semantics;
    workspace isolation does not turn it into an EPIC/FSM run.
17. Make quick logs, commits and test receipts bind to workspace/base/target
    SHA. The normal result is `submitted`, never an automatic target merge.
18. Add PM-approved merge command/controller flow, including stale main,
    active plan, frozen candidate and expected-head failures.
19. Update help/status/init setup material so users learn only `/aid-do`; the
    internal workspace machinery remains controller-facing.

### Slice 6 — clone isolation and rollout

20. Add optional disposable-clone/container adapter behind one project policy
    switch. It must use the same submission/merge contracts as worktrees.
21. Run dogfood with two independent plans, multiple simultaneous quick tasks,
    a frozen plan candidate and an injected unexpected main reset.
22. Release only after instruction-consistency, Git hook, lifecycle and
    workspace end-to-end tests pass. Update changelogs and recovery/help
    handoffs.

## 7. Acceptance criteria

1. Two independent `/aid-run` controllers can execute mutable work
concurrently without sharing a working directory or branch.
2. A mutable agent cannot be dispatched into `main`, `plan/*`, `task/*` or a
workspace leased to another agent without explicit controller/PM authorization.
3. A normal `/aid-do` creates an isolated worktree and a `quick/Q-NNN` branch;
it never changes the caller's checkout and never auto-merges into its target.
4. A submitted workspace whose target moved cannot merge silently. It becomes
stale or enters the explicit integration path.
5. Parallel submissions merge deterministically or create a dedicated
integration workspace; their source branches remain unchanged on conflict.
6. Any unexpected movement of main/active plan/active task ref blocks further
ordinary lifecycle actions and produces actionable `target_ref_tampered`
evidence.
7. A quick task aimed at a frozen plan displays its candidate invalidation
impact and cannot proceed without explicit PM confirmation.
8. `--force` remains available to the PM as the audited emergency path, but
the result is visibly forced and never represented as an ordinary verified
success.
9. P083-shaped recovery restores the committed control plane without rebasing
the active plan/task history; normal plan sync later incorporates the release
branch.
10. Every live agent/controller instruction agrees on workspace ownership,
branch vocabulary, prohibited raw Git operations, submission and merge flow.

## 8. Non-goals

- Do not claim a Git worktree is an OS security sandbox.
- Do not expose a low-level workspace management UI to ordinary users.
- Do not automatically rebase, reset, force-push, overwrite a ref or resolve a
semantic merge conflict.
- Do not make every small `/aid-do` task a full EPIC/FSM lifecycle.
- Do not remove the PM's universal audited `--force` emergency backdoor.
- Do not enable arbitrary write-parallelism before merge queue and conflict
recovery fixtures prove the implementation.
