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

## The replay after P095 Step 1 (2026-09-20)

The recorded answers, unchanged, re-adjudicated by the branch
`feat/p095-review-cleanup`. No model was called; only the adjudicator differs.
The command (the project root is the scratch checkout, because the pre-image
shas the reviewers cited live on `scratch/p094-fresh-diffs`, not on `main`):

```
bash plugins/aid-orchestrator/scripts/tests/test-step-review-acceptance.sh replay-do \
  --evidence /opt/eco/projects/aid-orchestrator/.aid-o/work/evidence \
  --project-root /opt/eco/projects/aid-orchestrator/.aid-worktrees/fresh-diffs
```

| Diff | Before (2026-09-19) | After | Why |
|---|---|---|---|
| 1 `36f0e429` (alloc glob) | pass — `missing_command` | pass — `command_not_read_only` | its inline reproduction runs `mkdir`, `cd` and `touch`: it WRITES, and after the hardening below no writing verb is on the list (the first draft accepted it, which is what the review caught) |
| 2 `346a8a36` (set-field) | fail, 1 blocker | **fail**, 1 blocker | unchanged; its citations were always plain `path:line` |
| 3 `e8814f7f` (pre-push) | pass — `missing_evidence` ×2 | **fail**, 1 blocker | the range `diff.patch:9-14` passes the schema, and the finding stands on its second citation, the pre-image `e8814f7fa701:…/pre-push:58` |
| 4 `224f60b4` (yq check) | pass — `missing_command` | pass — `command_not_read_only` | its reproduction runs `source aid-fsm.sh` and `git init`: `source` is on no list and `git` is restricted to its reading subcommands, so it is refused on purpose |
| 5 `22ded9fb` | skip (no round) | skip | the step check gave `skip`; nothing was reviewed |

**Measured: 2 of 4 reviewed diffs now report the defect, against 1 before.**
The plan predicted `1 pass, 3 fail, 1 skip`; the measured outcome is
`2 pass, 2 fail, 1 skip`. The plan expected all four recorded inline commands to
be accepted, and two of them are not read-only commands at all: diff 1 creates
files in /tmp to show a glob bug, diff 4 sources `aid-fsm.sh` and runs `git
init`. Both are legitimate reproductions and both belong in a
`repro/<name>.sh` file, which is exactly what the file form is for. What the adjudicator stopped losing is ONE
finding, diff 3's, rejected on the FORM of its citation (a line range). Diff 2
was never lost — its citations were plain `path:line` all along — and diffs 1
and 4 are still rejected, now for what their reproductions DO rather than for
the form they are written in.

**The verb list is shorter than the plan's.** An independent review on
2026-09-20 walked through what the planned list admitted and found it was a
first-word check over a string the reviewer model writes: `if true; then rm -rf
x; fi` passed (only `then` was checked), a newline hid a second command from the
segment splitter entirely, `export PATH=/tmp/evil:$PATH` re-pointed every later
verb, and `find -exec`, `sed -i` and `yq -i` all write. So `cd mkdir mktemp
touch export find sed yq` and the shell keywords are not on the list, a newline,
a backslash, a redirection, a command or process substitution and any in-place
flag refuse outright, and the recorded diff-1 command (`mkdir -p /tmp/wan-check
&& cd … && touch …`) would be refused today as well. The table above is the re-measurement after
the hardening; the first draft scored 3 of 4 by accepting diff 1's writing
reproduction.

**No fixture was created.** The plan's `fixtures/step-review/fresh-diffs-2026-09-19.json`
would have to pin pre-image shas that live only on a scratch branch; a fixture
that rots the day the branch is pruned is worse than no fixture. `replay-do` is
a measurement command, run by hand against an evidence tree, and the durable
regression coverage lives in the three new cases of
`scripts/tests/bats/test-review-adjudicate.bats` (Step 1), which build their
own repository.
