# IMP-266 adjudication — Codex unavailable, decision deferred to PM

**When:** 2026-07-23/24 (Phase-1 maintenance).

## What happened

The IMP-266 recovery-model fork (audited reopen edge vs. deliberately terminal +
documented ceremony) was routed to an independent Codex adjudication
(`codex exec -s read-only`), per the maintenance brief's "adjudicate other
decisions via Codex" rule. The Codex process **hung** — it sat in
`Reading additional input from stdin...` without producing a verdict across two
launch attempts (a 10-minute foreground attempt and a detached retry that ran
long without completing), and was terminated. No Codex verdict was produced.

## Disposition

IMP-266 is an "architecture decision required" item, and this Phase-1 pass
**implements nothing** for it — it only prepares the decision. Because it is a
genuine design fork touching a load-bearing safety property (the terminality of
`merged_to_plan`), and the independent adjudicator was unavailable, the decision
is **deferred to explicit PM ratification** rather than picked by the controller.
This satisfies the brief's binding rule: *do not choose the recovery model
silently.*

The full analysis, both options, and the controller's recommendation are in
`docs/plans/IMP-266-merged-to-plan-recovery-DECISION.md`.

## Controller recommendation (for PM ratification)

**Option B — keep `merged_to_plan` terminal; document a PM-authorized manual
recovery ceremony; defer the audited reopen edge (Option A) to P068+ if a real
incident shows the ceremony is too slow or error-prone.**

Grounds: an incorrect `merged_to_plan` is not reachable by any normal flow today
(it needs a hand-edit or a future-caller bug), the plan-branch entry side is
dormant, and IMP-265/267 already hardened the repair/attest paths that could
produce a wrong entry. Adding an outgoing edge to a deliberately terminal state
spends real safety capital to solve a problem no reachable code path yet creates.
The backlog's hard constraint (no unlogged generic rollback) holds under both
options.

**Nothing is implemented for IMP-266 in Phase 1.** PM ratifies A or B; the
implementation (a runbook ceremony for B, or a scoped reopen-edge commit with its
own review for A) is a separate step.

## PM decision (2026-07-24)

The PM ratified **Option B**: `merged_to_plan` stays terminal (accounting is not
erased); a wrong entry is corrected by a documented, audited recovery ceremony —
a new corrective EPIC or the ceremony steps — never an in-tool reverse
transition. The ceremony (the Option B deliverable, doc-only) is in
`docs/plans/IMP-266-merged-to-plan-recovery-CEREMONY.md`. Option A is deferred to
P068+ if a real incident shows the ceremony is too slow or error-prone.

**Last Updated:** 2026-07-24
