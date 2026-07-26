> **Location note.** These four reports are PLAN-level artifacts of P068, not
> artifacts of E-068-2_2. They live under this EPIC's evidence directory because
> the commit-scope hook governs the FSM state this run is in and permits only it;
> filing them here keeps them tracked rather than dropping them. The plan-final
> run directory is where they belong once the plan's own boundary runs.

# Curator report — P068 plan-final

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T19:09:39Z
reviewed_head: e7e3d5f2821a28d12cd8b44c7ab0845896b56dde
blocking_findings: false

## Consistency

- Both CHANGELOG files are byte-identical, as the repository requires.
- The enforcement registry total (320) is derived and asserted equal to the row
  count by `test-control-boundary.sh`, so it cannot drift by hand-editing.
- Every new registry row carries all nine required keys; no id is duplicated.
- Headings avoid version stamps, which the skill linter rejects.
- Every agent-facing surface carries a disposition, enforced by exit 2 rather
  than by review attention.

## Proposals

### Applied

- The mode-fork qualification on `pipeline.md`'s DONE-summary MERGE option —
  found by the sweep the same EPIC added, and fixed rather than allowlisted.
- Hook reinstall from templates, with hashes recorded before and after.

### Deferred, with reasons

- **The two lock probes remain duplicated** (`_pfsm_lock_held` in the FSM,
  `_lock_is_held` in the close check). CP2 L1 noted they had already drifted;
  the missing existence guard was fixed in the production copy, but the
  duplication itself survives because collapsing them crosses a file boundary
  that no step of either EPIC owns. Deferred to the plan's own follow-up rather
  than smuggled in.
- **`_pfsm_close_lock_contended` is only called from tests.** It is not dead —
  it documents and exercises the path-scoped exclusion — but it is not the
  shipped probe either. Recorded so a later reader does not mistake it for the
  production path.
- **`aid-plan-fsm.sh` is now 5188 lines.** That is large for one file and the
  natural split (plan lifecycle vs EPIC lifecycle) is visible. A split during a
  release-boundary EPIC would have made every review diff unreadable, so it is
  deliberately not attempted here.

## Verdict

No blocking findings. The deferrals are recorded with reasons rather than left
as silent debt.
