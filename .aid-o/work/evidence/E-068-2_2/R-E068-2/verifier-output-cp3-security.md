# CP3 integration review — security focus

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T19:04:24Z
classification: FULL_REVIEW
verdict: pass
checkpoint: cp3
focus: security
reviewed_range: 4b50272..HEAD
reason: One recurrence of this EPIC's own durability defect found and fixed with a regression; the mode resolver, the migration path and the crash seam each hold their invariant.

## The seam, reviewed as an attack surface

`AID_PLAN_FSM_CRASH_AFTER` can terminate a transactional command, so it deserves
the question: can it be used to break the release boundary?

- It is inert unless the variable is set AND names the exact phase being
  recorded. No wildcard, no numeric form, no default.
- Its only effect is `exit 99`. It writes nothing, moves no ref, changes no
  state — an induced crash is indistinguishable from a power cut, which is what
  makes the matrix meaningful and also what makes the seam harmless.
- Triggering it requires control of the process environment, which is control of
  the shell; an attacker holding that does not need the seam.
- Crucially it cannot cause a WRONG outcome, only an incomplete one, and every
  incomplete outcome is exactly what the resume path is tested against.

## The migration path, reviewed as a privilege question

Stamping is the only mutation `inventory` performs, and it can only write
`legacy_epic_release_mode`, only onto a plan that declares nothing, and only
under `--apply`. There is no path by which it grants a plan the new model — the
direction that would matter, since `plan_branch` changes what may reach the
target branch. Granting `plan_branch` happens solely at plan creation, guarded on
the gate table, and an unknown policy value falls back to legacy rather than
being honoured.

## The default flip, reviewed as a blast radius

The flip is a ceiling, not a promise: `plan_branch` is granted only where a
`gate_profiles` table exists, so a consumer project that merely upgrades the
plugin cannot silently acquire a mode whose gates resolve against nothing. The
fallback is logged as `plan_branch_unavailable: no_gate_profiles` rather than
being silent, which is the difference between a decision and a surprise.

## No findings requiring a fix beyond b030623

No secret or credential handling is introduced. The only writes outside the
plan's own state directories are to the tracked `.aid-lifecycle/` manifest, and
those now go through the same isolated-index path the lifecycle layer uses, with
a read-back check.
