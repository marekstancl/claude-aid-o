# CP3 integration review — security focus

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T16:31:56Z
classification: FULL_REVIEW
verdict: pass
checkpoint: cp3
focus: security
reviewed_range: 0158a68..HEAD
reason: Every path that can move the target branch is a compare-and-swap bound to the PM-approved head, and no path publishes without a validated authorization.

## The invariant under review

Only the exact candidate the PM authorized may reach the target branch, and a
plan may be declared closed only with durable proof that this happened or that
it was aborted.

## Verified

**Only two code paths move `refs/heads/<target>`, and both compare-and-swap.**
The merge publish (`aid-plan-fsm.sh:3892`) passes the frozen `target_head`
as the expected old value; until it succeeds the merge exists only as a dangling
object, so a rejected swap leaves the target byte-identical and says so. The
plan-mode plumbing commit (`aid-lifecycle.sh:275`) passes the expected parent
and short-circuits when the rebuilt tree already matches it, making a resumed
pass a documented no-op rather than a second commit.

**Authorization is validated before any Git action.** The PM decision is checked
against its schema and bound to plan, attempt, candidate and approved target
head, and its `decided_at` is compared against the manifest's
`candidate_frozen_at`. Every degenerate input — missing, empty or unparseable
freeze time, malformed decision time — blocks rather than being assumed old
enough.

**The stale-authorization guard is not disarmable by history.** It is disarmed
only when our own published merge genuinely explains where the target head is
(CP2 M1); a rewind past that merge blocks and returns the plan for
re-synchronisation. The operation key names the candidate, so a new candidate is
a new operation and cannot be mistaken for a resume of the old one (CP2 M2).

**The push guard checks the remote target, not the local ref name.** Both sides
of a refspec are recorded, so an exempt-looking local branch pushed AT the
guarded remote branch is blocked (CP2 M4), while same-name pushes stay exempt.
Proven end-to-end against a repository state where the guard genuinely blocks.

**The lock-contention exclusion cannot be widened.** `--exclude-lock` accepts
at most one path and only this plan's own close sidecar, so the probe cannot be
disarmed from the command line while still reporting a pass (CP2 M1). The
exclusion is by exact canonical path, so a different lock held by the same
process still blocks. The read-only probe no longer creates the sidecar it
probes (CP2 L1).

**Fail-closed on unknowns.** Unresolvable ancestry is UNKNOWN and blocks, never
"merged". An unrecognised closure state refuses to write a receipt (CP2 L3). An
absent tag record blocks rather than resolving to "no tag required" (CP2 M3).
A missing lifecycle manifest blocks a plan-branch close (this review's finding).

## No findings requiring a fix beyond e6df701

No secret, credential or token handling is introduced anywhere in this diff, and
no path writes outside the plan's own state directories, the tracked
`.aid-lifecycle/` files and the target ref.
