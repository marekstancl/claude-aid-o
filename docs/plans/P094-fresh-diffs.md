# P094 — five fresh diffs against the installed plugin (v2.99.0)

Run 2026-09-19 14:19–14:31 UTC, installed plugin 2.99.0, fast-mode path
(`/aid-do` Step 5: `aid-step-check.sh --checkpoint cp6 --worktree`, then
`aid-review-round.sh prepare / collect / close`), reviewer `step_generalist`
on Sonnet as configured. Scratch branch `scratch/p094-fresh-diffs`
(worktree `.aid-worktrees/fresh-diffs`), one commit per diff; the branch is
a record, nothing on it is meant to merge. Evidence:
`.aid-o/work/evidence/do/20260919T14*/cp6/`.

The diffs were written for the run, four with one planted defect each and
one clean docs edit, so that every result has a known answer.

| # | Diff | Planted defect | Step check | Reviewer found it? | Adjudicator | Verdict | USD |
|---|---|---|---|---|---|---|---|
| 1 | `alloc plan-id` skips ids already taken by files (2 files, 24 lines) | `[[ -f "$dir/P075"*.md ]]` never globs, loop never fires | review | yes, blocker, plus the test that cannot catch it | **rejected: `missing_command`** (repro written as `bash -c '…'`, not `bash repro/<x>.sh`) | pass (wrong) | 0.46 |
| 2 | `set-field` writes field/old/new to timeline (2 files, 13 lines) | old value read after the rewrite, so old == new | review | yes, blocker, reproduced live | accepted | **fail (right)** | 0.47 |
| 3 | pre-push hook skips the guard on delete-only pushes (2 files, 14 lines) | redundant: the per-ref loop already skips zero-sha; test passes for the wrong reason | review | yes, blocker (dead code, and why: `(delete)` is only the local side) + major (test shape) | **rejected ×2: `missing_evidence`** (line ranges `path:9-14`; the schema takes one line) | pass (wrong) | 0.65 |
| 4 | yq missing fails loudly in `fsm_check_review_round` (2 files, 5 lines) | `exit 1` inside `$(…)` kills only the subshell; under `set -e` the failed substitution aborts the caller | review | yes, blocker, reproduced with yq off PATH | **rejected: `missing_command`** (`bash -c '…'` again) | pass (wrong) | 0.50 |
| 5 | CP4 template stops describing the pre-filter (1 file, 10 lines, docs) | none | **skip** (inside scope, no pattern) | — | — | skip (right) | 0 |

Totals: 4 reviewed rounds, 2.08 USD, 317k tokens, about 6 minutes of reviewer
time. The reviewer found the planted defect in **4 of 4** reviewed diffs, with
a live reproduction each time. The mechanism reported the right verdict in
**2 of 5**: the adjudicator threw away 4 of the 5 real findings on the form of
the citation, not on its truth.

## What this says

1. **Sonnet as `step_generalist` is good enough on fresh code.** Every planted
   defect was found and reproduced; the redundant diff 3 was recognised as
   dead code together with the reason (only the local side of a delete push
   is `(delete)`), which the author of the diff had not seen.
2. **The adjudicator is the weak link, twice over.** The reviewer writes its
   reproduction inline as `bash -c '…'` (3 of 4 rounds) instead of a file
   under `repro/`, and cites line ranges (`path:9-14`) where the schema wants
   one line. Both are rejected by pattern before anyone reads them. The
   acceptance run of Step 13 hit the same wall (three real findings rejected
   on citations) and the relaxation of commit 6cb9e288 was not enough.
3. **`aid-review-adjudicate.sh:168` has `local first=""` outside a function**;
   bash prints `local: can only be used in a function` on every collect. The
   value still gets assigned, so nothing else breaks, but it is noise on every
   round and a sign the loop body was moved out of a function untested.

## What goes into P095

- Evidence pattern accepts `path:N-M` (anchor on N) — one regex in
  `defaults/schemas/review-finding.schema.json`, and the prose in
  `skills/step-review-roles.md` / `skills/plan-review-roles.md` says so.
- A repro may be inline: accept `bash -c '…'` when the command is read-only
  (no `>`, no `rm`, no `git push`), or make the prompt say in bold that an
  inline repro is rejected and a `repro/<name>.sh` is required. Preferably
  the first: what the reviewer naturally writes should be what the schema
  takes.
- Fix the top-level `local` in the adjudicator.
- Re-run these five diffs (the scratch branch stays) after the fix: expected
  1 pass, 3 fail, 1 skip.
