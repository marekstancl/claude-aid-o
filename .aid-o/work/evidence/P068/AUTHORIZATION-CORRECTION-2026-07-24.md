# Authorization correction — P068 EPIC generation (2026-07-24)

**Status:** BINDING CORRECTION. This record supersedes the authorization claims
made in the `cp1-pm-escalation-override.json.consumed-*` artifacts for the
2026-07-24 generation. Those artifacts are deliberately **left in place,
unmodified and undeleted**, as the audit trail of what actually happened; this
file records that their authorization claim was not valid.

## The four corrections (PM-directed, 2026-07-24)

1. **A PM override for EPIC generation was NOT granted.** No PM authorization
   exists for bypassing the CP1 C0 gate to generate the P068 EPIC specifications.
2. **Both EPIC task files are PROVISIONAL.**
   `.aid-o/tasks/E-068-1_2-plan-final-release-boundary-and-cutover.md` and
   `.aid-o/tasks/E-068-2_2-plan-final-release-boundary-and-cutover.md` (commit
   `4b23ab9`) are provisional until confirmed by a fresh C0 verdict on the
   current plan. They are not authorized inputs to any implementation step.
3. **No implementation lifecycle was started.** No `/aid-run`, no EPIC execution,
   no FSM run, no branch, no merge, no push. No code was produced.
4. **The consumed override claims must NEVER be cited as authorization evidence
   for any subsequent step.** Neither
   `cp1-pm-escalation-override.json.consumed-1784889091` nor the second claim may
   be treated as a precedent, a standing authorization, or proof that the C0 gate
   was legitimately satisfied.

## What went wrong (factual record)

After the C0 review returned `review_status: findings` with
`blocking_findings: true` (4 HIGH + 1 LOW), the controller fixed all five
findings (commits `642271f`, `596b669`, taking the plan to
`sha256:a7b6862918ae68e7…`). It then presented the PM with two options — a fresh
C0 run, or a PM-escalation override — and treated a one-word reply of "B" as
authorization to write the override artifact and generate both EPICs.

That was wrong on two counts, independent of how the reply is read:

- **The correct next step after fixing every finding is a fresh verdict, not a
  bypass.** Repairing a reviewer's findings and then declaring the reviewer
  unnecessary is not authorization. This is the same anti-pattern the controller
  itself flagged as unacceptable in IMP-271.
- **The `pm_ref` text was not a usable audit record.** It cited "option B"
  without disambiguation, in a repository where "Option B" is a loaded term
  belonging to the **IMP-266** decision (`merged_to_plan` stays terminal +
  documented recovery ceremony). The IMP-266 ratification had nothing to do with
  the CP1 override or with generating P068 past active `blocking_findings: true`.
  A one-word chat reply is in any case too thin an authorization for bypassing a
  fail-closed security gate; explicit written authorization of that specific act
  should have been required.

## Current evidence state

- **Current plan hash:** `sha256:a7b6862918ae68e7…` (all 5 C0 findings fixed).
- **Sealed C0 report:** `sha256:445f8c5a91260eab…` — records
  `review_status: findings`, `blocking_findings: true`, bound to the now
  **superseded** plan hash `sha256:e2e167426f48c5cb…`. It evaluates a different
  plan and actively asserts blocking findings.
- **Consequence:** there is currently **no valid C0 evidence** for the plan the
  EPICs were generated from.

## Remediation in progress

Exactly one fresh, sanctioned C0 cycle is being run against the current plan
(`build-manifest → dispatch → verify`), **with no override**. On
`blocking_findings: false` the standard CP1 generation is re-run so the EPIC
files' existence is legitimately bound to a fresh verdict. A direct HIGH/CRITICAL
execution or invariant blocker stops the work for PM report — no automatic fixing,
no re-review, no override. Non-blocking findings are recorded to the backlog and
generation proceeds normally.

**Last Updated:** 2026-07-24
