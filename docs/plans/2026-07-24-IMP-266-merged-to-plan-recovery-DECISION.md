# IMP-266 — recovery from an incorrect terminal `merged_to_plan`: decision brief

**Status:** RATIFIED — the PM chose **Option B** on 2026-07-24: keep
`merged_to_plan` deliberately terminal and correct a wrong entry via a
documented, audited recovery ceremony, never an in-tool reverse transition. The
ceremony (the Option B deliverable) is written in
[`IMP-266-merged-to-plan-recovery-CEREMONY.md`](IMP-266-merged-to-plan-recovery-CEREMONY.md).
No code change — `merged_to_plan` is already terminal. Option A (a narrow audited
reopen edge) is deferred to P068+ if a real incident shows the ceremony is too
slow or error-prone.
**Prepared:** 2026-07-23 (Phase-1 maintenance). **Ratified:** 2026-07-24 (PM).
**Adjudication:** independent Codex was unavailable (hung); the controller
recommended B and the PM ratified B.

## The problem (verbatim from backlog)

> `merged_to_plan` has no outgoing transition. If it is ever assigned
> incorrectly, the operator has no sanctioned correction path. Decide between a
> narrow audited reopen transition, gated by explicit operator attestation, and a
> deliberately terminal design with a documented manual recovery ceremony. Do not
> add an unlogged generic rollback.

## Current state (verified in code)

`lib/aid-plan-manifest.sh` `_AID_EPIC_STATUS_TRANSITIONS` (~:885) makes
`merged_to_plan`, `abandoned`, `superseded` terminal — no outgoing edge. A
`merged_to_plan` entry additionally carries a non-null `epic_merge_commit`, and
the manifest invariant (`:434`) binds the two: `epic_merge_commit != null` iff
`status == merged_to_plan`. `merged_to_plan` is only reached with a Git-proven
ancestor merge commit (IMP-272 authorization + `_pfsm_is_ancestor`), so an
*incorrect* `merged_to_plan` is not a normal-flow outcome — it requires manual
manifest editing, a `plan_manifest_set_epic_status` misuse, or a future bug.

## How could an incorrect `merged_to_plan` even arise?

1. A hand-edited manifest (the substrate treats the manifest as authoritative but
   the file is writable).
2. A future caller of `plan_manifest_set_epic_status … merged_to_plan <sha>`
   passing a real-but-wrong merge commit (one that IS an ancestor of the plan
   branch but does not actually deliver the EPIC's work — e.g. an unrelated merge).
3. A repair/attestation defect (largely closed by IMP-265/267, which now
   re-derive ancestry and never mint proven).

In all three the *entry* claims delivery the EPIC did not make, or attributes the
wrong commit — and there is today no sanctioned way to correct it without editing
the file by hand, which is exactly the "unlogged generic rollback" the backlog
forbids.

## Option A — narrow audited reopen transition

Add exactly one new edge `merged_to_plan → running` (or `→ blocked`), gated by an
explicit operator attestation artifact (mirroring `--attest-source-ref`): a
subcommand `plan-state <plan> --reopen-epic <epic> --reason '<text>'` that
requires the operator to state why, records the reopen in the operation log with
the prior `epic_merge_commit`, clears `epic_merge_commit` back to null (restoring
the manifest invariant), and moves the entry to `running`. Never generic, never
unlogged: one named edge, one audited command.

- **Pros:** a sanctioned, in-tool, fully-audited correction path; keeps the
  manifest the single source of truth; symmetric with the attestation model
  IMP-267 already establishes; recoverable without leaving the substrate.
- **Cons:** adds an outgoing edge to a state whose terminality is itself a safety
  property — every future reader of the state machine must now reason about a
  `merged_to_plan` entry possibly reverting; widens the trusted surface; risks
  becoming a soft "undo" that normalizes reversing delivery.
- **Effort:** M — one transition, one subcommand, op-log record, invariant
  restoration, and a Security-F-2-adjacent test set proving the reopen is audited
  and cannot itself mint proven.

## Option B — deliberately terminal + documented manual recovery ceremony

Keep `merged_to_plan` terminal. Document a manual recovery *ceremony* for the rare
incorrect assignment: a written, PM-authorized procedure (in the runbook) that
re-scopes the affected EPIC in the git-tracked lifecycle manifest and, if needed,
rebuilds the runtime manifest via `plan-state --repair` (now non-destructive per
IMP-265) followed by an explicit `--attest-source-ref` for the entries that are
genuinely provable. No new code edge; the correction is an auditable human act
recorded in the lifecycle manifest and op log.

- **Pros:** preserves terminality as a hard safety property — no code path can
  ever reverse a delivery claim; the rare correction is a deliberate,
  PM-authorized, human-reviewed act rather than a tool affordance; smallest
  attack surface.
- **Cons:** the "ceremony" is prose, not mechanism — its correctness depends on
  the operator following it; slower recovery; relies on `--repair` +
  attestation composing correctly for this case (they do, post IMP-265/267, but
  it is indirect).
- **Effort:** S — a runbook section; no code change.

## Recommendation

**Option B (deliberately terminal + documented ceremony), for now**, with Option
A explicitly deferred to P068 or later if a real incident shows the ceremony is
too slow or error-prone.

Reasoning: an incorrect `merged_to_plan` is not reachable by any normal flow
today (it needs a hand-edit or a future-caller bug), the plan-branch entry side
is entirely dormant, and IMP-265/267 already hardened the paths that could
produce a wrong entry. Adding a reopen edge now spends real safety capital —
`merged_to_plan`'s terminality is load-bearing in the substrate's threat model —
to solve a problem no reachable code path yet creates. The ceremony gives a
sanctioned, audited (lifecycle manifest + op log) correction without weakening
the state machine. If P068's dogfood surfaces a genuine need for in-tool reopen,
Option A is a clean M-effort follow-up whose design is already sketched above.

Either way, the backlog's hard constraint holds: **no unlogged generic
rollback** — Option A is one audited edge, Option B is an audited human ceremony.

## Codex adjudication

See `.aid-o/work/maintenance/imp-266-adjudication.md` for the independent
bounded adjudication and its rationale.

## What happened next

- The PM ratified **Option B** on 2026-07-24.
- The Option B deliverable — a documented, PM-authorized recovery ceremony — is
  written in [`IMP-266-merged-to-plan-recovery-CEREMONY.md`](IMP-266-merged-to-plan-recovery-CEREMONY.md).
  It is doc-only: `merged_to_plan` stays terminal and no code edge is added.
- Option A (a narrow audited reopen edge) is deferred to P068+; it is not
  implemented and is only revisited if a real incident shows the ceremony is too
  slow or error-prone.

**Last Updated:** 2026-07-24
