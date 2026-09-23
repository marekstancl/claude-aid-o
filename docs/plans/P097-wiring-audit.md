# P097 — the independent reading: is anything unwired or dead?

**What this is.** P097 rebuilt the gate row, the profile table, the timeouts and
removed three key families. EPIC 2 (Steps 9–10) then DELETES what the record
shows unused. Deleting on the word of the author who just wrote it is how a
still-used layer disappears, so this file is the second pair of eyes: every new
function must have a caller, every removed layer must have no reader, every
comment that names a file must name a file that exists.

**Who fills the verdict.** Sections 1–3 below are the MECHANICAL half, measured
by the Step 8 author and reproducible line by line — the commands are printed so
the reader can re-run them rather than believe them. Section 4 is the
independent reader's (Codex, or the Claude stand-in the controller dispatches),
and it is the only part that decides anything.

Branch: `task/E-097-1_2/main`. Base for every diff below:
`7a81f6db9a74156a75697058e50cef393b043658` (the last commit before Step 1).
Scope: Steps 1–7 (Step 8's own files are test/record artifacts and carry no
production callers by design).

---

## 1. Every new function has a caller

```bash
git diff <base>..HEAD -- '*.sh' | grep -E '^\+[a-zA-Z_][a-zA-Z0-9_]*\(\) *\{'
```

22 functions were added. Each was then grepped across `scripts/` for a call site
that is neither its own definition nor a comment.

| function | home | called from |
|---|---|---|
| `gate_row_normalize` (bash + the jq def) | `lib/aid-gate-row.sh` | `aid-run-gates.sh`, `aid-fsm.sh`, `aid-plan-fsm.sh`, `lib/aid-step-review-packet.sh` and 15 more sites |
| `gate_row_check` | `lib/aid-gate-row.sh` | `_gate_row_finalize` in `aid-run-gates.sh` |
| `_gate_row_finalize` | `aid-run-gates.sh` | `aid-run-gates.sh:1636` (every row on its way into a report) |
| `_refuse_dead_keys` | `aid-run-gates.sh` | `aid-run-gates.sh` run-all entry, before any gate runs |
| `validate_all_timeouts` | `aid-run-gates.sh` | same entry, next line |
| `gate_profile_table` | `lib/aid-gate-profile-select.sh` | `aid-run-gates.sh`, `aid-fsm.sh`, `aid-plan-fsm.sh` (5 sites) |
| `gate_profile_index` | `lib/aid-gate-profile-select.sh` | the floor and the resolver (5 sites) |
| `gate_profile_exists` | `lib/aid-gate-profile-select.sh` | `aid-run-gates.sh` `--profile` validation (3 sites) |
| `gate_profile_has_required_gate` | `lib/aid-gate-profile-select.sh` | `aid-run-gates.sh`, the resolver |
| `gate_profile_for_paths` | `lib/aid-gate-profile-select.sh` | `aid-fsm.sh`, `aid-plan-fsm.sh` (4 sites) |
| `gate_profile_floor_verdict` | `lib/aid-gate-profile-select.sh` | `aid-fsm.sh:2632` (the GATES:DONE floor) |
| `gate_profile_wider` | `lib/aid-gate-profile-select.sh` | the plan-final profile resolution (5 sites) |
| `gate_profile_upgrade_hint` | `lib/aid-gate-profile-select.sh` | every refusal message that names the upgrade (4 sites) |
| `_gps_json` | `lib/aid-gate-profile-select.sh` | internal, 4 sites in its own library |
| `execution_yaml_upgrade` | `lib/aid-init-execution-yaml.sh` | the library's own `upgrade` main; `/aid-init` |
| `execution_yaml_default_when_paths` | `lib/aid-init-execution-yaml.sh` | `execution_yaml_upgrade`, the composer (4 sites) |
| `_eyu_locate` | `lib/aid-init-execution-yaml.sh` | `execution_yaml_upgrade` (4 sites) |
| `gate_baseline_propose` | `lib/aid-gate-runtime-baseline.sh` | `aid-gate-runtime-baseline.sh propose` |
| `_fsm_pre_2103_services_note` | `aid-fsm.sh` | `aid-fsm.sh:3322` (resume), `:6211` (done-advance) |
| `_config_row`, `_report_row` | `scripts/tests/gates-measure.sh` | that script's own sweep (lines 166, 174) |
| `_configured` | `lib/aid-gate-profile-select.sh` | its own library |

**Result: 22 of 22 have a caller. No orphan.**

Two of them are called only from inside their own file (`_gps_json`,
`_configured`) and two only from the measurement script that defines them
(`_config_row`, `_report_row`) — private helpers, which is what a private
helper is supposed to look like, not a finding.

## 2. Every removed layer has no reader

```bash
grep -rn --include='*.sh' "<key>" scripts/ | grep -v '/tests/' | grep -vE ':[0-9]+: *#'
```

| removed | non-comment hits in production code | what they are |
|---|---|---|
| `services:` (top level), `needs_services` | 2 | ONLY inside `_refuse_dead_keys`'s refusal list — the key is named to be rejected, never read |
| `required_when` | 4 | `_refuse_dead_keys`'s list, and `execution_yaml_upgrade`'s removal + `required: true` replacement |
| `gate_profile_defaults` | 3 | the same two places, plus `aid-init-execution-yaml.sh:321` where its presence is detected on a NOT-yet-upgraded file |
| `runtime_baseline`, `baseline`, `baseline_*`, `quarantine` | 1 (shared) | the dead-key regex `_EYU_DEAD_KEY_RE` |
| `notifications.telegram.{enabled,chat_id,alert_threshold,alert_on_repeated_precondition_fail}` | 0 | gone |
| `_fsm_service_sweep`, `lib/aid-service.sh` as a runner dependency | 0 | gone from the gate path |

**Result: no removed key has a reader. Every surviving mention is a refusal, an
upgrade rule, or a detector on a file that has not been upgraded yet** — which
is the opposite of a dead key, and is what `execution_yaml_keys_have_readers`
(the registry row Step 9 adds) is meant to keep true.

### One thing the reader should look at, not a defect

`gate_profile_rank` and `gate_profile_max` still exist in
`lib/aid-gate-profile.sh`. They are called from **nowhere outside that library**
— only from three of its own functions (lines 338, 386–387, 407–409). The plan's
Data Model says `gate_profile_index` replaces them at their five call sites,
and Step 4's fix commit recorded the same state ("old profile library named only
by the library itself"). So: correctly disconnected from the runner, and still
present. Removing it is EPIC 2's job (Step 9), not Step 8's. The question for
the reader is whether anything outside `scripts/` — a skill, a command, a
project's own tooling — still reaches into it.

## 3. Every comment names a file that exists

151 distinct file paths appear in lines the branch added. Each was resolved
against the plugin root, the `scripts/` root and the repository root.

24 did not resolve. All 24 were then located by hand:

- **21 are fixture DATA, not comments**: strings inside
  `scripts/tests/bats/test-init-gate-profiles.bats`,
  `test-hook-rules-turn.bats` and the project fixtures under
  `scripts/tests/fixtures/gates/projects/` — deliberately fictional paths
  (`defaults/schemas/x.json`, `docs/x.md`, `scripts/no-such-gate-script.sh`) or
  the OTHER projects' real gate scripts (`scripts/run_py_test_gate.sh` is
  ACTA's, in ACTA's tree). A test fixture that names a file which must NOT exist
  is the test working.
- **1 is a comment naming a deleted file, and says so**:
  `test-init-gate-profiles.bats:283` — "Since 2.96.0
  (`lib/aid-gate-applicability.sh`, deleted in Step 6) …". It names the file as
  deleted, which is history, not a broken pointer. The reader may still judge it
  better phrased as "the applicability layer".
- **2 are a stale list entry (LOW, real):**
  `scripts/tests/gates-measure.sh:57` still lists
  `scripts/tests/bats/test-gate-baseline-sequential-only.bats` among the files
  it counts, and that suite was deleted by Step 5. `--line-count` completes
  without error (the missing file is silently skipped, total 42 089), so the
  only consequence is that a re-measurement is not comparable to Step 1's
  number without saying so. Not fixed here: `gates-measure.sh` is production
  code and this step may not change it.

## 4. Two things Step 8 found and did NOT fix

Both are pinned as cases in `scripts/tests/bats/test-gates-edge-matrix.bats`, at
the behaviour they have TODAY, with the gap named in the case comment. Neither
is fixed here: the qa role may not change production code.

1. **A duplicated gate id is silently resolved to the last definition.** yq
   takes the last of two identically-named keys, so the earlier (possibly
   stricter) gate vanishes and `gate_count` never notices. The run cannot come
   out falsely green — the surviving definition really runs — but an operator
   who edits a gate twice loses the first edit without a word.
   `execution_yaml_upgrade` already refuses a file with two top-level `gates:`
   lines; the same idea applied to gate ids would close this.

2. **A report that cannot be written is not an error.** With `--report-file`
   pointing into an unwritable directory, the runner emits a raw
   `Permission denied` from the redirect and then returns the GATE verdict's
   exit code — so a caller that checks only `$?` sees success and no report.
   What saves it today is that the callers check for the file:
   `aid-plan-fsm.sh` refuses with "produced no report". A `|| { echo ERROR;
   return 1; }` on the write would make the failure local instead of relying on
   every caller remembering.

## 5. What this audit did NOT check

Stated so its absence is not read as a pass:

- the registry rows the Data Model names (`gate_row_contract_v2`,
  `gate_profile_unknown_refused`, `gate_profile_from_caller`,
  `execution_yaml_keys_have_readers`, `gate_timeout_fixed`) **do not exist on
  this branch**. Step 9 adds them. Their absence is planned, not a finding.
- whether the SKILLS and COMMANDS still describe the gate layer correctly
  (Step 7's subject) beyond the file-citation check in section 3.
- anything on the live merge path other than the suites this step ran.

---

## Verdict

**Reader:** Codex (`codex exec --sandbox read-only`), three readings on
2026-09-22 at HEAD 9825352f, d7653b8e and 95a39065. The first two returned
`fail`; each finding was answered by a fix or by a correction of the question,
and the third reading is reproduced below. The controller did not grade itself:
the verdict line is the reader's.

**Reading 1 (HEAD 9825352f) — fail.** (a) All added functions have callers.
(b) The baseline file was still listed as an ancillary exception in
`lib/aid-ancillary.sh` and `defaults/policies/plan-final-policy.yaml` with
nothing saying it is legacy-only. (c) No broken comment citation. (d) The reader
counted EPIC 2's removal list as a blocker because the files still exist — a
misreading of the question, since Step 9 deletes them and has not run.
→ Fixed (b) in `d7653b8e`: both entries now say in a comment that nothing has
written the file since Step 5 and the exception exists only so a tree upgraded
from an older AID does not read as dirty. Question 4 was restated.

**Reading 2 (HEAD d7653b8e) — fail.** (b) accepted as resolved. (d) accepted:
no runtime call site, only test readers, listed as Step 9 notes. New blocker in
(c): two comments naming files that do not exist —
`defaults/enforcement-registry.yaml:4` (a gitignored seed of the June 2026
audit) and `scripts/tests/fixtures/gates/projects/wan.yaml:114`.
→ The registry header was rewritten (`95a39065`). The WAN file is a verbatim
copy of another repository's `execution.yaml`, kept byte-identical on purpose so
the upgrade and replay fixtures are real samples; its comments cite paths inside
that repository. `scripts/tests/fixtures/**` was therefore excluded from
question 3 as foreign data.

**Reading 3 (HEAD 95a39065), verbatim:**

> 1. Yes. At current HEAD `95a3906536fbdd8a06ca08de9963371919f4e45f`, I
>    extracted added shell definitions with `git diff -U0 5701bafa~1..HEAD` and
>    counted non-comment occurrences using `git grep -w`. All 20 added functions
>    have callers: counts range from 2 (`validate_all_timeouts`,
>    `_gate_row_finalize`, `gate_profile_floor_verdict`) to 20
>    (`gate_row_normalize`). The nested `_eyu_del` has six calls in addition to
>    its definition.
> 2. No removed layer retains an active reader. The grep found only refusals,
>    upgrade logic, detectors/tests, and historical records. The remaining
>    baseline entries in `aid-ancillary.sh`, `plan-final-policy.yaml` and
>    `aid-fsm.sh` are justified legacy-upgrade exceptions: their comments state
>    that nothing writes the files after Step 5 and that the exact old paths are
>    ignored only so upgraded trees are not falsely dirty. The entry itself need
>    not leave with the runtime layer.
> 3. No. I enumerated path-like citations in comments of every touched file,
>    excluding all `scripts/tests/fixtures/**` as instructed, and resolved the
>    concrete repository paths against HEAD. No comment names a missing file.
>    The corrected enforcement-registry header is clean.
> 4. No unnoticed runtime reader exists. `git grep` for all five Step 9 paths
>    and for actual `source`/function calls returned no non-test runtime call
>    site. Step 9 should nevertheless update the readily discoverable test
>    readers: `test-init-gate-profiles.bats` sources `aid-gate-profile.sh`, and
>    `test-recovery-ladder.bats` sources and calls `aid-service.sh`. It should
>    also retire the `SERVICE_UNHEALTHY` emitter entries in
>    `defaults/policies/auto-recovery.yaml` and clean meta-test references such
>    as `test-run-all-tier-filter.bats`, `test-run-all-timing.bats` and
>    `gates-measure.sh`. These are visible test/config references, not hidden
>    breakage.

**Step 9 inherits from this audit** (nothing here blocks EPIC 2): the two test
sources above, the `SERVICE_UNHEALTHY` class and its emitter anchors in
`defaults/policies/auto-recovery.yaml`, the meta-test and `gates-measure.sh`
references to the deleted suites, and the `MIRRORED BY:` comment in
`lib/aid-env-name-denylist.sh` naming `defaults/schemas/service-declaration.schema.json`.

verdict: pass
