# Step 6/6 (index 5) — step_6_backend — Verification

## What the step delivered
`plan-close` becomes a real gate instead of a marker. It is a durable
transaction like every other plan operation: it takes its own lock, runs every
precondition through `aid-plan-close-check.sh --plan-branch`, then follows
intent -> git_applied (the lifecycle receipt, or the abort record) ->
state_committed (the marker) -> CLOSED. It bridges the two plan-state worlds the
PM directive named: the legacy `ca-review-complete` marker and the git-tracked
`.aid-lifecycle/` receipt layer.

## Acceptance criteria

- [x] Individually removing or corrupting EPIC ancestry, the manifest, the final gate report, a required review, the C4 decision, the PM decision, the merge or abort record, the queue state, the active state, the release/tag record and the final SHA binding each blocks close.
- [x] Unknown ancestry blocks rather than passing — an unresolvable merge commit or target ref is UNKNOWN and is never treated as merged.
- [x] Re-running after a simulated crash reconciles state and writes exactly one atomic head-bound close marker, and no second receipt.
- [x] A plan whose `.lock` sidecars exist but are not held closes normally — the probe is `flock -n`, not file existence.
- [x] The owned-lock exception holds and is path-scoped: close succeeds while the transaction holds its own lock; a separate live holder of another relevant sidecar blocks and is named; a different lock held by the same process still blocks.
- [x] `plan-close-complete` is absent until the final merge or a recorded abort; `plan-review-complete` is the separate earlier marker.
- [x] A committed `.aid-lifecycle` receipt is present after close for every non-aborted plan-branch plan; an aborted plan writes an abort record instead and leaves the target branch free of plan content.

## CP2 step review
Verdict: **fail** — two HIGH findings on the release boundary itself, plus six
MEDIUM and three LOW. All are fixed in `c926fca`:

- **H1** — the abort transaction commits `status: aborted` onto the target
  branch, so a successful abort always advances the target; check 5.6 read any
  advance as a violation. Every re-run, including the crash resume its own error
  message prescribes, was permanently refused. 5.6 now asserts what it means for
  an abort — that no plan *content* was published — and recognises exactly the
  abort's own lifecycle commits.
- **H2** — 5.6's "target branch unchanged" assertion fell through to a PASS
  printing that claim when the frozen head was absent. The field is genuinely
  nullable, so the case is reachable. "Cannot verify" now blocks.
- **M1** — `--exclude-lock` was unvalidated and repeatable, so the lock check
  could be disarmed from the command line while still reporting a pass.
- **M2** — the unfinished-operation guard excluded every `plan-close:*` record
  rather than the operation in hand.
- **M3** — a missing `release-prep.json` passed the tag check, so deleting the
  release record unblocked it. Now checked against the record the merge actually
  writes. (Two earlier attempts at this fix demanded `release-prep.json` itself
  and made every no-bump plan unclosable; both were caught by the suite and
  discarded.)
- **M4** — the `aid-fsm.sh` delegation handed out `ca-review-complete` and
  returned, skipping every CA-report check. That marker is the plan-boundary
  signal the next plan's start gate reads.
- **M5** — the delegation returned before the execution.yaml toggles were read,
  making `reporter.enabled:false` unsatisfiable.
- **L1** — the production lock probe would create the sidecar it was probing.
- **L3** — the closure-state case had no default arm.

## Test evidence
- `test-aid-plan-final-boundary.bats` AC7 block: **26 ok / 0 not ok** (the AC7
  verification pattern's own filter), run on this commit's code.
- Full suite on this commit: **132 of 141 result lines emitted, 0 not ok**, before
  the run was terminated in its known teardown hang. The nine tests not reached in
  that run are AC7 cases, all covered green by the dedicated AC7 run above on the
  identical code. Logs: `scratchpad/ac7c.log`, `scratchpad/s6-verify.log`.

## Deferred, with reasons
- **CHANGELOG entry and enforcement-registry rows** for the new `plan-close`
  gate and its eleven Check 5 sub-checks are required by CLAUDE.md but both files
  are outside every step's `allowed_paths` in this EPIC — the same plan
  `Files:`-list gap already recorded for Steps 1 and 2. Carried to the plan's
  own step 9.
- **M6 (the delegation is untested)** — the `aid-fsm.sh` plan_branch branch has
  no direct coverage. Carried to CP3.
- **A pre-existing red test**, `test-aid-plan-release-boundary.bats` #229, whose
  static guard asserts `aid-release.sh` has zero callers under `scripts/`.
  Step 5 legitimately added `aid-release.sh tag-plan`, verified present at
  `a74f9cb` before this step began. The guard's premise is now false. Narrowing
  it touches a test file outside this EPIC's `allowed_paths` and needs a PM
  scope decision.

## Memory Used
- N/A — no relevant memory entries found (reason: this step builds directly on Step 5's plumbing, all of it in this EPIC's own history).

## Memory Written
- N/A — no new reusable patterns introduced (reason: the close transaction reuses the operation-log and plan-mode plumbing patterns Steps 1 and 5 established).

step_index: 5
step_id: step_6_backend
plan_step_hash: 26d5cb9f70d289211b9bf5d3d70883b00dba297eac4cfb2580e799a610478efc
reviewed_commit: c926fcae59f981b159e875a6ff80440c6f139d8f
idempotency_token: E-068-1_2-R-E068-1-step-5-c926fca

## Result: PASS
