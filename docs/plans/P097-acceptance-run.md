# P097 — the acceptance replay: does the rebuilt gate layer give the recorded verdicts?

**One sentence:** 61 recorded gate runs were replayed against the rebuilt runner
and 60 came out with exactly the same verdict; the one that did not came out
*redder*, because the new runner catches a false green the old one shipped —
and that is the only thing the PM has to accept in writing before Step 9.

Written by Step 8. Sources: `scripts/tests/test-gates-replay.sh` (the replay),
`scripts/tests/fixtures/gates/gates-acceptance.json` (its output),
`scripts/tests/fixtures/gates/gates-sample.json` (Step 1's sample), and
`.aid-o/work/evidence/E-097-1_2/R-E097-1/steps/step_4_backend/acceptance-replay.md`
(Step 4's profile replay, reproduced in §4).

---

## 1. What was replayed, and what was not

For every entry of the Step 1 sample:

1. the project's `execution.yaml` **at the recorded sha**, read with
   `git show <sha>:.aid-o/config/execution.yaml` — read-only; nothing was
   written into ACTA or WAN, not even git worktree metadata;
2. that file upgraded in memory by Step 3's `execution_yaml_upgrade`;
3. every gate `command` replaced by `exit <the recorded exit code>` (from the
   report's `_command_log`, else the row's own `exit_code`);
4. `run-all --profile <the recorded profile>`, then `overall` and the per-gate
   `status` compared against the recorded rows, both sides put through
   `gate_row_normalize` so a version-1 and a version-2 row are read in one
   vocabulary.

**No project test suite was executed.** The stubbing is the point: what P097
changed is the mapping from (profile, exit code, `pass_criteria`) to (status,
`overall`), and that is what is under test. Whether ACTA's pytest still passes
was true at the recorded sha and is not this plan's claim. The tree at the sha is
not materialised at all — with every command stubbed, nothing reads a file from
it, which is why the plan's scratch-worktree step was not needed.

## 2. The numbers

| | |
|---|---|
| runs replayed | **61** (AC asks for ≥ 30) |
| equal after explanation | **61** |
| **raw** equal — no difference of any kind | **18** |
| differences recorded | **61** across 3 classes |

The raw number is printed here on purpose. 18 of 61 runs came back
byte-identical; the other 43 differ in ways that are listed and explained below,
and hiding that behind "equal = 61" would be the exact dishonesty this record
exists to prevent.

| class | count | is it a verdict difference? |
|---|---|---|
| `reason` — same status, renamed reason | 47 | no |
| `config_drift` — a gate only one side defines | 13 | no (see §3) |
| `overall` — the run verdict itself | **1** | **yes** — §5 |
| `status` — a gate both sides have, different status | **0** | — |

**Zero per-gate status differences on 61 runs.** Every gate that both the
recorded configuration and the upgraded one define reached the same
pass/fail/skip.

## 3. The 60 differences that are not verdict differences

**45 × `legacy_row` → `exit_2`.** ACTA's `docs_updated` and both projects'
`plan_diff` exit 2, which their `pass_criteria` accepts as a graceful skip. The
recorded rows say `result: skip` with no reason at all; the version-1 mapping
therefore reads them as `skip/legacy_row`, and the new runner writes
`skip/exit_2`. Same status, and the new row actually says why.

**2 × `exit_124` → `job_timeout`.** ACTA's `plan_diff` in `R-P016-final-1` and
`R-P016-final-2` hit its deadline. 124 is `timeout(1)`'s deadline exit, and the
closed vocabulary now names it instead of leaving a reader to decode the number.
Both rows were `fail` before and are `fail` now.

**13 × `config_drift`.** The recorded report and the `execution.yaml` at that
same sha do not list the same gates — because a gate was added or removed *by the
very EPIC whose head sha the report recorded*. Three gates account for all 13:
`vat_labels_sync` (added during E-016, so it is in the config at 6 later shas
but in no earlier report), `ts_e2e` (4 runs) and `plan_diff` (3 runs, removed
from ACTA's `release` profile after P018). The plan's own edge case says to list
these and never drop them silently, which is what the record does. None of them
changed a run's outcome: `overall` is compared independently, so a drifted gate
that mattered would show up in the `overall` class — and exactly one run does,
for an unrelated reason.

## 4. The profile half, from Step 4

Step 4 replayed the *resolver* on the same sample and its result stands
unchanged here (`steps/step_4_backend/acceptance-replay.md`):

- **ACTA, 17 EPIC runs:** every one recorded `full` with
  `profile_source: cli_flag` — an operator typing `--profile full`, never a
  resolver answer. 0 of 17 recovered path sets match any high-risk glob, so the
  new resolver answers `standard` for all 17. The one run with a timeline event
  shows the OLD resolver also answered `standard`.
- **WAN, 6 runs:** 6 of 6 agree (`standard`). The one run with `profile: null`
  would now be refused at the GATES:DONE floor — a report that cannot say which
  profile it ran is not evidence.
- `release` is never auto-returned by either resolver (no `when_paths` on it).

This replay passed `--profile <the recorded name>` on purpose: the two questions
are separate, and mixing them would have let a resolver disagreement hide inside
a verdict comparison.

## 5. The one verdict difference — **PM decision owed**

### `acta / R-P019-final-5` — recorded `pass`, replays as `fail`

**What happened.** The run's `ts_e2e` gate exited **130** (interrupted — someone
or something sent it a SIGINT). The report records `result: fail` for that gate
and `overall: pass` for the run.

**Why the old runner said pass.** The report was written by
`aid-run-gates.sh@v2.16.0` (2026-08-26), which recorded **no `required` field on
any row** — every row in it has `required: null`. ACTA declared that gate's
requiredness only through `required_when: "frontend/e2e exists"`, a static claim
about a directory that has existed since the project started. Nothing enforced
it. So a release-profile run with a broken end-to-end suite went out green.

**Why the new runner says fail.** Step 3's upgrade replaces a gate's dead
`required_when` with a real `required: true` (it is the gate's only requiredness
claim, and dropping it alone would leave a profile with no required gate at all).
Step 2's `overall` derivation then does what it always said it did: a failing
required gate makes the run fail.

**So the difference is the plan working.** This is a false green from a real
release-boundary run, found by replaying it. Nothing about the inputs changed —
the same exit codes, the same profile, the same configuration — only the
question of whether a "required" claim is enforced.

**What the PM is asked to accept, in writing, before Step 9:**

> `R-P019-final-5` replays as `fail` instead of `pass`, and that is correct:
> the recorded run was green only because `required_when` was never enforced.
> With that accepted, 61 of 61 runs are equal after explanation.

There is no option B worth writing down. The alternative is to keep a rule that
lets an interrupted release gate pass, which is the rule P097 was written to
remove. If the PM does not accept it, the finding is not "the replay failed" —
it is that `required_when` should keep its old meaning, and Step 6 has to be
reopened.

The same sentence is machine-readable in
`gates-acceptance.json.verdict_differences_explained[]`, and the list that
produces it is `EXPLAINED_VERDICT_DIFFS` at the top of
`scripts/tests/test-gates-replay.sh` — one line per accepted difference, in the
open, so a future run cannot quietly absorb a new one.

## 6. Two things found and NOT fixed

The qa role does not change production code. Both are pinned as cases in
`scripts/tests/bats/test-gates-edge-matrix.bats` at their present behaviour,
with the gap named in the case comment, and both are written up in
`docs/plans/P097-wiring-audit.md` §4:

1. **A duplicated gate id is silently resolved to the last definition** — yq
   keeps the last of two identical keys, so an operator who edits a gate twice
   loses the earlier (possibly stricter) one without a word. The run cannot come
   out falsely green, but the refusal that `execution_yaml_upgrade` already
   applies to two top-level `gates:` lines is missing at the gate-id level.
2. **A report that cannot be written is not an error** — with `--report-file`
   pointing into an unwritable directory, the runner prints a raw
   `Permission denied` and then returns the gate verdict's exit code. A caller
   checking only `$?` sees success. What saves it today is that callers check for
   the file (`aid-plan-fsm.sh`: "produced no report").

A third, LOW: `scripts/tests/gates-measure.sh` still lists a suite Step 5 deleted
among the files it counts, so a re-measurement is not directly comparable to
Step 1's 42 089 without saying so.

## 7. How to reproduce

```bash
cd <worktree>
AID_PLUGIN_PATH=$PWD/plugins/aid-orchestrator \
  bash plugins/aid-orchestrator/scripts/tests/test-gates-replay.sh
# ~20 min, 61 runs; writes scripts/tests/fixtures/gates/gates-acceptance.json
# tier t2 — by hand before Step 9, nightly after. NOT on the merge path.
```

The edge matrix that covers what no recorded run reached:

```bash
AID_PLUGIN_PATH=$PWD/plugins/aid-orchestrator \
  bats plugins/aid-orchestrator/scripts/tests/bats/test-gates-edge-matrix.bats
```

The testbed, against this worktree's plugin:

```bash
bash /opt/eco/projects/aid-testbed/bin/verify.sh \
  --plugin <worktree>/plugins/aid-orchestrator
```
