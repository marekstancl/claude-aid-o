# Post-P068 integrity and liveness hardening

**Status:** ready. Small standalone maintenance after P069 is frozen; do not mix
it into P069's scheduler implementation.

## Why this exists

P068 delivered the plan-final boundary. Subsequent code inspection confirms four
small, real gaps around that boundary. None asks an implementer to add a new
ceremony. Each makes an existing operation either safer or fail-loud.

## Scope

### H1 — isolate dogfood Git references (IMP-280)

Before a dogfood can touch a target ref, compare the source checkout's and the
dogfood checkout's absolute `git rev-parse --git-common-dir` values. Equal means
the checkouts share refs (as linked worktrees do): refuse unless a deliberately
namespaced target ref is supplied. A separate clone passes. Record the evaluated
paths and the selected safe mode in the receipt.

This prevents a test run from advancing the real repository's `main` merely
because it was called a disposable checkout.

### H2 — make optional release-version probes safe (IMP-282)

`aid-release.sh` runs under `set -euo pipefail`. A changelog or optional
`pyproject.toml` with no numeric version is normal input, not a shell error.
Make the three zero-match probes deliberate:

- `CHANGELOG_HEADER` discovery;
- optional `pyproject.toml` discovery; and
- existing-header discovery while updating a changelog.

Expected absence must fall through to the next source or to the script's existing
domain-level "Cannot detect version" error. It must never terminate silently in
`grep`. Add regressions for an empty/non-numeric changelog with a valid JSON
version, a no-header changelog being updated, malformed optional `pyproject.toml`,
and no usable source.

### H3 — separate CP3 evidence and fail loud on an unknown range

`aid-prefilter.sh classify --checkpoint cp3` currently writes the generic
`verifier-output-step-N.md`, which can overwrite CP2 evidence for the same step.
Give CP3 its own canonical output name or make it a non-writing classification
path; consumers and tests must read the corresponding checkpoint-specific file.

For CP3, a missing canonical `base_commit` is not evidence that
`merge-base`/`HEAD~5` is the EPIC range. Return an explicit unverifiable/range
undetermined result and do not dispatch a full-EPIC reviewer on guessed history.

## Explicitly out of scope

- P069 scheduler/catalog code and all test-quarantine decisions.
- WAN's `docs_updated: true` configuration report (IMP-281) until reproduced
  against a concrete consumer configuration.
- Broad redesign of release automation or review roles.

## Acceptance proof

1. A linked worktree with shared common-dir is refused before any target ref
   mutation; a separate clone succeeds.
2. A changelog with no numeric heading does not abort release detection under
   `pipefail`; the next valid source is used or a clear domain error is printed.
3. CP2 and CP3 classifications for the same step cannot overwrite each other.
4. CP3 without a canonical base commit is explicitly unverifiable and never
   uses `merge-base` or `HEAD~5` as a silent substitute.
5. Targeted red-green tests pass. Run one final relevant integration check only;
   do not reintroduce repeated `bats_all` runs per small fix.

## Delivery order

Implement H2 first (isolated release liveness), then H3, then H1. Each should be
its own commit and targeted test set. H1 is the only behavior change involving
dogfood execution; keep its proof in a disposable clone.
