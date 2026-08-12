---
name: aid-verify-implementation
description: Independent adversarial DONE review of an implementation before it is trusted as complete
user_invocable: true
---

# /aid-verify-implementation — Independent DONE Review

Dispatch an **independent** agent to adversarially review an implementation that
claims to be done. Catches false-green DONE: code that passed its own tests but
does not boot, has no real consumer, or does not deliver what the plan promised.

## Arguments

```
/aid-verify-implementation [EPIC-id | git-range]
```

- **No argument (default)** — review the implementation that is live in *this*
  session: the work just completed here. The target diff is the current branch's
  work (e.g. `git diff main...HEAD` plus uncommitted changes), reviewed against
  the plan/EPIC it was meant to satisfy.
- **`EPIC-id | git-range`** — an explicit EPIC to review, or a git range
  (e.g. `HEAD~3..HEAD`) to scope the diff.

**Which tree the diff is taken in.** "The current branch's diff" means the
branch of the tree the *work* lives in, which is not always the tree you invoke
from. When the target belongs to a plan whose
`.aid-o/work/plan-state/<plan_id>/plan-state.yaml` records a `worktree_path`,
take the diff **in that plan worktree** (`git -C <resolved worktree path> diff
…`) — the primary checkout is on another branch and would yield a diff of
someone else's stream, or an empty one.

**Resolve the recorded path before using it.** `worktree_path` is normally
stored RELATIVE (e.g. `.aid-worktrees/plan-P901`), and a relative path in
`git -C` resolves against the caller's cwd — so from `primary/src/`, or from
another worktree, the same recording either reports an existing worktree as
missing or targets a different directory entirely. Resolve it first, using the
same probe rule `/aid-status` documents for its `missing!` marker: a relative
`worktree_path` is joined onto the **state root** (the primary checkout,
`scripts/lib/aid-roots.sh` → `aid_state_root`), an absolute one is used
verbatim. Probe the resolved path, then pass the resolved path to `git -C`. Two concurrent plans mean two worktrees, so name the
tree explicitly in the dispatch instead of relying on cwd. If the recorded
worktree is missing on disk, say so and stop — do not silently fall back to the
primary checkout, which is exactly how a review of the wrong tree passes.
Plans with no recorded `worktree_path` (legacy streams) keep today's behaviour:
the diff is taken where the command runs.

## What it does

1. **Identify the target.** Resolve the implementation from the current session
   context (the change just made), or from the argument: gather the diff, the
   changed files, and the plan/EPIC + acceptance criteria it was meant to meet.
2. **Dispatch an independent subagent.** Dispatch a `general-purpose` Agent in a
   **fresh context** with the Review Protocol below, the diff/repo, and the plan.
   Do **not** review inline — the protocol explicitly says "do not trust my
   summary or prior PASSes", which only holds with a fresh context.
3. **Relay the verdict.** Return the subagent's structured findings to the PM.
   The human summary is delivered in the PM's conversation language and in the
   card shape `skills/communication.md` defines (Finished when the verdict is
   PASS, Blocked or failed when it is FAIL or CANNOT VERIFY, Decision required
   when the PM must choose); severity labels and verdict keep their canonical
   form. The subagent **audits only — it does
   not fix anything** without explicit PM approval.

## Why independent

A session that just implemented something is primed to believe its tests prove it
works. The whole value of this review is a fresh agent with no stake, instructed
to verify runtime reality and producer-consumer contracts rather than trust green
tests. This mirrors the project rule: *adversarially verify before claiming done.*

## Review Protocol (subagent instruction — pass verbatim)

> Perform an independent DONE review of an implementation.
>
> **Important:**
> - Do not trust my summary or any prior PASSes.
> - Do not judge by the fact that tests passed.
> - Verify the real state of code, artifacts, runtime, and evidence.
> - Be adversarial: look for where the implementation can be false-green.
> - Do not fix anything yet unless you get explicit approval. Deliver the audit
>   first.
>
> **Review steps:**
>
> 1. **Read the plan/spec and extract the real acceptance criteria.** What was
>    meant to be delivered? What is explicitly out of scope? What evidence was
>    supposed to be produced? What user or system problem was it meant to solve?
>    For every AC that says "always", "all", "each", "never", or similar,
>    verify that the universe is explicit (for example: "all documents" vs
>    "documents with `client_id`"). If the universe is implicit, mark the AC as
>    not objectively verifiable.
> 2. **Check the actual diff/repo state.** Which files were created/changed? Is
>    the scope disproportionate? Any dead branches, duplicate implementations,
>    leftover old code, or a parallel resolver? Any placeholders, TODOs,
>    hardcoded ports, local paths, fake defaults?
> 3. **Verify runtime, not just statics.** Can it actually boot/run? Is the
>    endpoint/UI/CLI really reachable? Is the output usable against real data? Is
>    it just a library layer with no consumer? If it is frontend, verify with a
>    screenshot and a real flow, not just components. DONE review must include
>    an **independent runtime path check**: exercise the real caller path used by
>    production/FSM/CLI/API/UI, not only a helper function or isolated unit.
> 4. **Verify the tests.** Do they test real behaviour, or only their own
>    mock/synthetic world? Are there negative controls? Does a test fail when you
>    introduce a typical regression? Are tests green only because a fixture is
>    missing/skipped? Are tests oversized without value? Every new integration
>    function must have at least one test through its caller flow; a unit test of
>    the pure helper alone is not enough.
> 5. **Verify producer-consumer contracts.** Does the implementation produce
>    artifacts that another part actually reads? Do the names, IDs, paths, hash,
>    HEAD, timestamp, schema line up? Is there a second parallel implementation
>    of the same logic? Is the evidence old, stale, self-consistent, or not bound
>    to the current revision? Any evaluation evidence must state which part of
>    the pipeline was actually executed and which parts were not; otherwise it
>    only proves coverage for the executed slice, not the whole pipeline.
> 6. **Verify against real data / an oracle.** Compare the output with an
>    independent source of truth if one exists. Do not use implementation-
>    generated output as its own evidence. For cross-project/read-model things,
>    verify counts, identities, missing/dropped cases, and historical vs current
>    data.
> 7. **Check security and operational limits by change type.** Path traversal,
>    symlinks, write/exec, ports, payload limits, permissions. The read-only
>    invariant if one was promised. Eco rules, environment, Node version, network
>    behaviour.
> 8. **Assess the real value.** Does it deliver what the plan promised? Is the
>    output understandable to the target user? Is it just a nice-looking dead
>    overview? Are important functions missing that logically follow from the
>    requirement?
>
> **Write the output like this:**
>
> **Verdict:** PASS / PASS WITH CONDITION / FAIL / CANNOT VERIFY
>
> **Most important findings:** ordered by severity BLOCKER / HIGH / MEDIUM / LOW.
> Each finding must have: the concrete file/line or artifact, why it is a
> problem, which requirement/AC it violates, how to verify it, and the
> recommended fix.
>
> **What is genuinely done:** briefly, no marketing.
>
> **Independent runtime path check:** command/flow executed, caller entrypoint,
> inputs or fixture, artifact/output path, exit code/result, whether this is the
> same path production/FSM/CLI/API/UI uses, and what was explicitly not
> exercised.
>
> **What is not proven:** list the missing evidence, runtime gaps, test gaps.
>
> **Recommended fix plan:** the concrete order of fixes; what must be blocking
> before DONE; what can go to the backlog.
>
> **Short human summary for the PM:** 5–10 sentences in the PM's conversation
> language (the card contract is `skills/communication.md` — outcome first,
> identifiers last). No technical noise. Clearly say whether the PM can trust
> it, and why.

## Reads / Writes

- **Reads:** the target diff/changed files (`git diff`, the EPIC or git range);
  the plan/EPIC + acceptance criteria; runtime artifacts; repo state (read-only,
  via the subagent).
- **Writes:** nothing. The review audits only — it produces a verdict for the PM
  and proposes (does not apply) fixes.

## Relationship to FSM / skills

- **Standalone PM tool, outside the FSM** — like `/aid-do`, it does not write
  `fsm-state.yaml`, does not create an evidence dir, and does not touch the
  pending-dispatches ledger. The `aid-emit-dispatch.sh` wrapper therefore does
  not apply: outside an FSM run there is no orphan-dispatch reconciliation to
  feed.
- **Complements `agents/verifier.md`** — that agent runs the in-pipeline review
  checkpoints (CP2–CP5) and the GATES DONE checks during `/aid-run`.
  `/aid-verify-implementation` is the manual DONE gut-check the PM fires by hand
  on work that already claims to be complete.

**Last Updated:** 2026-08-12
