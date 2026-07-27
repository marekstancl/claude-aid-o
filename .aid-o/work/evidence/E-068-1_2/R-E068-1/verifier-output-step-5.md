# Verifier output step 5

_generated_by: aid-orchestrator:verifier (CP2 step-6 code-review + security)
_generated_at: 2026-07-26T10:35:00Z
classification: FAIL
verdict: fail
reason: Two HIGH findings sit directly on the plan-final release boundary — the abort close was single-shot with an unrecoverable crash resume, and its "target branch unchanged" assertion fell open on a nullable field. Six MEDIUM and three LOW also recorded. All findings except M6 and L2 are fixed in c926fca; the fix loop was re-verified and the verdict is superseded below.
checkpoint: cp2

## Reviewed

Commit `0040a09` on `task/E-068-1_2/main` (immutable during review). Read-only:
nothing edited, no FSM command run against the workspace, no suite started
concurrently with the controller's own run.

## Findings

### H1 — the abort close permanently poisons its own re-run (HIGH)

`aid-plan-close-check.sh` Check 5.6 (abort) failed whenever
`target_branch_head_at_candidate_freeze` differed from the live target head. But
the abort path commits `status: aborted` onto the *target branch* through the
plan-mode plumbing — the abort itself advances the target. So a successful abort
close made every subsequent close for that plan fail 5.6, and because an aborted
plan never transitions to CLOSED the `ALREADY CLOSED` short-circuit is
unreachable for `close_mode=abort`: the second run reported `close_marker_invalid`
for a plan that had closed correctly.

The same arithmetic broke crash resume. A death after the `status: aborted`
commit landed but before the marker was moved into place left the prescribed
remedy ("re-run plan-close — it revalidates and converges") permanently refused.
The plan was stuck with a durable abort record on the target and no marker,
forever. Same class as the earlier finding that failure paths must not leave the
command's own remedy unrunnable.

### H2 — Check 5.6 abort fails open when the frozen target head is absent (HIGH)

The whole "target branch unchanged" assertion was guarded behind the frozen head
and the live head both being non-empty; when the frozen head was null the branch
fell through to a PASS whose message asserted exactly the thing it had just
skipped verifying. The field is genuinely nullable — the manifest initialises it
to null, lists it among the nullable SHA fields, and every candidate
invalidation resets it. Fail-open on degenerate input.

### M1 — `--exclude-lock` is unvalidated, repeatable and caller-widenable (MEDIUM)

Any caller-supplied path was appended and skipped by the lock-contention check,
with no assertion that it is the close sidecar or even under the plan-state
directory. Two flags disarmed Check 5.10 entirely while the script still printed
`PASS no relevant lock is held`. Not a live bypass through the shipped gate, but
this script is PM-runnable and its output is evidence.

### M2 — the unfinished-operation guard is keyed on the operation class (MEDIUM)

Check 5.9 dropped every `plan-close:*` record left at intent/git_applied rather
than the one belonging to this transaction, whose op_id the check was never
given. A prior close attempt with a different attempt number, or a crashed abort
close, was silently ignored by the guard whose entire purpose is to notice
exactly that.

### M3 — Check 5.7 fails open on a missing release record (MEDIUM)

With neither `release-prep.json` present, the version resolved to "none" and the
check PASSED, so deleting the release record *unblocked* the tag assertion
instead of blocking it — the inverse of the AC7 property.

### M4 — the delegation hands out `ca-review-complete` for free (MEDIUM)

Once the plan is CLOSED the plan-layer close exits 0, so `aid-fsm.sh` touched
`ca-review-complete` and returned, skipping every required-CA-report check below
it. That marker is the plan-boundary signal read by the next plan's start gate,
so any EPIC of an already-closed plan_branch plan obtained it with zero evidence.

### M5 — the delegated path drops the legacy path's close-check flags (MEDIUM)

The delegation returned before the execution.yaml toggles were read and never
passed `--skip-delivery-report`, so a project with `reporter.enabled:false` hard
-failed Check 1 with no reachable remedy. Fail-closed, but permanently
unsatisfiable for a supported configuration.

### M6 — the delegation is untested (MEDIUM, NOT fixed)

No test exercises `aid-fsm.sh cmd_plan_close`'s plan_branch branch — mode
resolution, the state gate, or the M4 path. Carried to CP3.

### L1 — the two lock probes have drifted (LOW)

`_pfsm_close_lock_contended` / `_pfsm_lock_held` in `aid-plan-fsm.sh` are called
only from the suite; the production probe is `aid-plan-close-check.sh`'s own
`_lock_is_held`, which lacked the existence guard its twin has and would
therefore CREATE the sidecar via `<>` if the path vanished between the listing
and the probe. A read-only check must not write to the workspace it judges.

### L2 — repo hygiene missing (LOW, NOT fixed)

No CHANGELOG entry and no enforcement-registry rows for the new `plan-close`
gate or its Check 5 sub-checks. Both files are outside every step's
`allowed_paths` in this EPIC — the same plan `Files:`-list gap already recorded
for Steps 1 and 2. Carried to the plan's step 9.

### L3 — empty closure state falls through (LOW)

`aid_lifecycle_plan_close`'s `case` had no default arm, so an empty or
unrecognised closure state proceeded to build and commit a receipt.

## Scrutiny items that came back clean

- The manifest-ref override is unset on every exit path, is only ever live
  around readers, and cannot leak into the parent process.
- Restore-on-failure holds on the plan-mode receipt path and the abort path.
- Merge-path crash resume produces no second receipt and no second merge.
- No hardcoded wall-clock comparison was reintroduced (the one date literal in
  the new block is an ops-ledger fixture whose `.phase` alone is read).
- Mode resolution reads the tracked lifecycle manifest, not the runtime one.

## Fix loop

All findings except M6 and L2 are fixed in `c926fca`. Re-verification on that
commit: the AC7 block passes 26/26 under the acceptance criterion's own filter,
and the full suite emitted 132 of 141 result lines with zero failures before its
known teardown hang was terminated; the nine not reached are AC7 cases covered
by the dedicated run.

Two fix attempts at M3 were discarded because the suite caught them: both
demanded `release-prep.json` itself, which the merge path legitimately treats as
"no bump", so they made every no-bump plan unclosable. The shipped fix checks the
record the merge actually writes.

_post_fix_verdict: pass
_post_fix_commit: c926fca
