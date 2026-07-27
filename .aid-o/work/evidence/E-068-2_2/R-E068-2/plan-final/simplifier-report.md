> **Location note.** These four reports are PLAN-level artifacts of P068, not
> artifacts of E-068-2_2. They live under this EPIC's evidence directory because
> the commit-scope hook governs the FSM state this run is in and permits only it;
> filing them here keeps them tracked rather than dropping them. The plan-final
> run directory is where they belong once the plan's own boundary runs.

# Simplifier report — P068 plan-final

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T19:10:07Z
reviewed_head: e7e3d5f2821a28d12cd8b44c7ab0845896b56dde

## Applied during the run

- **Two circular AC10 tests discarded.** The first drafts asserted
  `dispatch_counts` against a fixture that seeds `dispatch_counts: {}` — they
  would have proven only that the fixture matches itself. Replaced with tests
  that drive the real review stage and read what it wrote.
- **Two rejected M3 fixes.** Both demanded `release-prep.json` exist, which
  would have made every legitimate no-bump plan unclosable. The shipped check
  reads the record the merge actually writes. Simpler and correct rather than
  simpler and wrong.
- **One over-broad clean-worktree exemption removed** and replaced by
  restore-on-failure at the site of the mutation — less code and a stronger
  guarantee.

## Deferred, L-effort

- **Collapsing the duplicated lock probes** into one shared helper. Crosses a
  file boundary no step owns; the drift it caused was fixed, the duplication
  remains.
- **Splitting `aid-plan-fsm.sh` (5188 lines)** along the plan/EPIC lifecycle
  seam. Correct eventually, disastrous now: it would have made every review diff
  in this EPIC unreadable.
- **Extracting the repeated "stamp then read back from the target ref" idiom.**
  It now appears twice, which is exactly when a helper starts to pay — and the
  fact that the second site forgot it is the argument for extracting it.

## Not simplified, deliberately

The guards are verbose: each failure path names what was and was not written,
and several carry a paragraph explaining what went wrong before. That verbosity
is the deliverable. An operator meeting one of these messages at 3am needs the
sentence, not brevity.
