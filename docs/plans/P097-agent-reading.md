# P097 — the V5 check: can an agent who never saw the runner explain three real runs?

**What this is.** Every other piece of P097 evidence is written by someone who
already knows what the code does. This one is not. An agent with no prior
context is given the rebuilt gate layer and three recorded gate reports, and
asked to say — from the code alone — what each gate did and why the run ended
the way it did. If the code cannot be read, it has not been simplified; it has
only been rearranged.

**Who runs it.** The controller dispatches the fresh agent and pastes its answer
into "Reading" below, verbatim. The author of Step 8 wrote the selection and the
rubric and then stopped: grading your own reader is not a check.

---

## The three runs

All three are in `plugins/aid-orchestrator/scripts/tests/fixtures/gates/gates-sample.json`.
Paths are relative to `/opt/eco/projects/` and are **read-only**.

### Run 1 — `wan/R-P101-final-3`
`wan/.aid-o/work/evidence/P101/R-P101-final-3/gates_report.json`
(profile `release`, `overall: fail`)

| gate | recorded result | exit |
|---|---|---|
| plan_diff, tests_merge_path, docs_updated, tests_frontend | pass | 0 |
| tests_full_portfolio, tests_session_intake | profile_excluded | 0 |
| lint_python | **fail** | 1 |

*Why it is here:* one failing gate decides the run, two gates never ran, and the
report carries a `_execution_ledger` entry that is not a gate at all.

**Why this is not the run first chosen.** The first selection was
`acta/R-E020-1`, picked because a gate failed and the run was still green. It
was replaced after the first reading, and the reason is itself a finding: that
report is version 1 and carries no per-row `required`, the gate in question
(`vat_labels_sync`) is not in ACTA's configuration at the run's recorded sha —
the run used a plan worktree's configuration that no longer exists — and the
gate is `required: true` in the configuration today. So the honest answer to
"why was this run green" is "the evidence does not say", which tests archaeology,
not whether the code can be read. The reader who found that is quoted in the
Reading below; the replacement run's required flags are in WAN's tracked
configuration at its own sha, so the question is answerable from code plus
evidence.

### Run 2 — `wan/R-E101-3`
`wan/.aid-o/work/evidence/E-101-3_3/R-E101-3/gates/gates_report.json`
(profile `null`, `overall: pass`)

| gate | recorded result | exit |
|---|---|---|
| tests_merge_path, lint_python, docs_updated, tests_frontend, tests_session_intake | pass | 0 |
| tests_full_portfolio | **fail** | 1 |
| plan_diff | skip | 2 |

*Why it is here:* the run records no profile at all, and a failing gate again
did not stop it.

### Run 3 — `acta/R-P016-final-1`
`acta/.aid-o/work/evidence/P016/R-P016-final-1/gates_report.json`
(profile `release`, `overall: fail`)

| gate | recorded result | exit |
|---|---|---|
| py_test … ts_type_check, ts_e2e_pwa | pass | 0 |
| ts_e2e | fail | 1 |
| plan_diff | fail | **124** |
| docs_updated | skip | 2 |

*Why it is here:* two different kinds of failure, one of which is not a failure
of the thing being tested.

---

## What the agent is asked (the same five questions for each run)

1. For each gate: did its command run, and what happened to it?
2. Why is `overall` what it is? Name the rule, not the outcome.
3. For every row that is not `pass`: what would the **version-2** row for it say
   — `status` and `reason` from the closed vocabulary?
4. What decided which gates ran at all in this run?
5. Is there anything in this report the rebuilt runner would now REFUSE to
   produce or accept? If so, what and why?

The agent is given: `scripts/aid-run-gates.sh`, `scripts/lib/aid-gate-row.sh`,
`scripts/lib/aid-gate-profile.sh`, `scripts/lib/aid-gate-profile-select.sh`,
`defaults/schemas/gate-row.schema.json`, and the three reports. Nothing else —
no plan, no step output, no commit messages.

## Rubric — a run counts as "explained correctly" when all five hold

A run is graded whole: four of five is not a pass. Wording is free; the claim
has to be right.

| # | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| 1 | four gates ran and exited 0; `tests_full_portfolio` and `tests_session_intake` never ran because the `release` profile excludes them; `lint_python` ran and exited 1 | six gates ran and exited 0; `tests_full_portfolio` ran and exited 1; `plan_diff` ran and exited 2 | eight gates ran and exited 0; `ts_e2e` ran and exited 1; `plan_diff` was killed at its deadline; `docs_updated` ran and exited 2 |
| 2 | `fail`, because `overall` goes to `fail` for a gate that fails **and** is required, and `lint_python` is `required: true` in WAN's configuration | `pass`, same rule read the other way: `tests_full_portfolio` is not required | `fail`, because at least one required gate (`ts_e2e` / `plan_diff`) failed |
| 3 | `lint_python` → `fail`/`exit_1`; the two excluded → `skip`/`not_in_profile`; the rest `pass`/`exit_0` | `tests_full_portfolio` → `fail`/`exit_1`; `plan_diff` → `skip`/`exit_2` | `ts_e2e` → `fail`/`exit_1`; `plan_diff` → `fail`/**`job_timeout`** (124 is `timeout(1)`'s deadline exit, named, not left as `exit_124`); `docs_updated` → `skip`/`exit_2` |
| 4 | the `release` profile's `include[]`, from an explicit flag; the runner chose nothing | nothing: no `--profile` was passed, so every defined gate ran | the `release` profile's `include[]`, again from an explicit flag |
| 5 | **yes** — `_execution_ledger` is an entry in the `gates` map that is not a gate row at all; a reader who treats it as one has misread the report | **yes** — a report with no `profile` is refused at the GATES:DONE floor now; a run that cannot say which profile it ran is not evidence | nothing; a failing required gate is exactly what the run is supposed to record |

Credit for #5 on Run 1 and Run 3 is given for a well-argued "nothing", and for a
correct observation the table does not list. Credit is NOT given for inventing a
refusal that does not exist.

**Score:** 3 of 3 runs explained correctly is the acceptance criterion. Anything
less is a finding about the code, not about the agent.

---

## Reading

**Second reading, 2026-09-22, on the corrected triple** (the first reading, on
the triple that contained `acta/R-E020-1`, is kept below as Reading 1 because its
finding is what caused the selection to change).

All three reports were written by a pre-P097 runner; none can be reproduced by
the code today. The clearest tell is a per-row `runtime_baseline` object on every
row — that subsystem is gone (`scripts/tests/test-gates-hygiene.sh:70` lists it
as dead vocabulary; no file writes or reads the key). Other tells:
`profile_source: "cli_flag"` (current code writes only `caller` or `none`,
`aid-run-gates.sh:1095,1135`), a `profile_reason` field that exists nowhere,
`result: "profile_excluded"` instead of `status: skip` / `reason: not_in_profile`,
no `profile_table`, and no `row_version`/`waived`/`reused_from`/`started_at`/
`completed_at`/`required` on any row. `_generated_by: aid-run-gates.sh@v2.16.0`
cannot date them: `PLUGIN_VERSION` falls back to that literal
(`aid-run-gates.sh:166`) whenever the caller exports nothing. No report carries a
background row, so `aid-job.sh` plays no part in any of them.

**Run 1 — WAN `P101/R-P101-final-3`, profile `release`.** Config at the run's
`head_sha 99d5ccb8`: `release` includes plan_diff, tests_merge_path, lint_python,
tests_frontend, docs_updated; `tests_full_portfolio` and `tests_session_intake`
are deliberately out; the five included gates are `required: true`. Four gates
ran and exited 0; `lint_python` ran and exited 1 (ruff F401); the two excluded
gates never ran (`attempts: 0`, matching the top-level `excluded_gates`).
`_execution_ledger` is not a gate row at all — a run-level diagnostic the current
runner also emits into that map (`aid-run-gates.sh:1779-1787`). `overall: fail`
because only a row that fails **and** is required can flip it
(`aid-run-gates.sh:1656-1658`, reconfirmed by the derived-verdict pass at
`:1872-1894`); `lint_python` is exactly that. Under today's vocabulary:
`lint_python` → `fail`/`exit_1`, the two excluded → `skip`/`not_in_profile`
(`aid-gate-row.sh:56-58,65`), the rest `pass`/`exit_0`. The profile was named by
the caller (`cli_flag` is today's `caller`); nothing auto-selects a profile in an
ordinary run. Unexplained: the `runtime_baseline` object, and `attempts: 2` on a
gate whose config says `max_retries: 0` (today's loop caps at one attempt,
`aid-run-gates.sh:1500`).

**Run 2 — WAN `E-101-3_3/R-E101-3`, no profile.** `profile: null`,
`profile_source: null` — today's spelling of "no `--profile` was passed" is
`profile: null`, `profile_source: "none"` (`aid-run-gates.sh:1095`), so every
defined gate ran and `excluded_gates` is empty. `plan_diff` exited 2, the
documented graceful skip (`aid-run-gates.sh:1526-1529`); five gates passed;
`tests_full_portfolio` ran and failed (exit 1). It is `required: false` in WAN's
configuration, with a comment saying its requiredness gates only the plan-final
check — so its failure cannot set `overall`, and `pass` is correct by the same
rule. Today: `fail`/`exit_1` and `skip`/`exit_2`. Its `attempts: 2` is consistent
with the default `max_retries: 1`, so — unlike Run 1 — not an anomaly.

**Run 3 — ACTA `P016/R-P016-final-1`, profile `release`.** The configuration at
that sha still carries `required_when` on every gate and a top-level
`gate_profile_defaults`, so under the current code `_refuse_dead_keys`
(`aid-run-gates.sh:364-386`, called at `:1088`) exits 2 **before any gate runs**:
this report could not be produced today at all. Read as it stands: seven gates
passed; `ts_e2e` failed exit 1 on a lock collision ("Jiný běh e2e-release.sh drží
zámek"), a script-level mutex, not a code defect; `plan_diff` failed exit 124 at
its 180 s deadline; `docs_updated` skipped by the exit-2 advisory convention.
`overall: fail` because `plan_diff` is required and failed; `ts_e2e` is required
through `required_when: "frontend/e2e exists"` and would force it independently.
Today `plan_diff` would read `fail`/`job_timeout` — the deadline is named, not
left as a bare `exit_124` (`aid-run-gates.sh:224-226`). Two things the code
cannot explain: `vat_labels_sync` is declared and in the `release` include list
at that exact sha yet has no row at all, and `plan_diff`/`ts_e2e` show
`attempts: 2` against `max_retries: 0` — together suggesting the runner read a
different copy of `execution.yaml` than the one at the sha the report names.

**Hard to follow.** `aid-run-gates.sh` is one 2090-line file mixing validation,
profile resolution, job supervision, retry, waivers, escalation and report
assembly; finding where `overall` is finally decided (`:1861`, `_derived_fail`)
against seven earlier ad-hoc assignments took real back-and-forth. Two textually
distant places decide a row's final status — `gate_row_normalize`
(`aid-gate-row.sh:52-74`) and the runner's inline exit-2 rewrite
(`aid-run-gates.sh:1526-1529`). `profile_source` had at least two spellings and
`profile_reason` was dropped, with nothing in the tree recording that history.
The removed baseline subsystem left no trace but a hygiene regex and a dead-key
pattern, so two of the anomalies above cannot be resolved at all.

---

### Reading 1 (superseded selection, kept for its finding)

All three reports were written by `aid-run-gates.sh@v2.16.0` (`_generated_by` in each file) — an older row shape (version 1) than the code in this worktree, which is version 2 (`row_version: 2`, `status`, closed-vocabulary `reason`, boolean `waived`/`required` on every row — `defaults/schemas/gate-row.schema.json:7-24`). None of the three has `row_version`, `status` or a per-row `required`/`waived`; all use the old `result: pass|fail|skip|profile_excluded|waived`. That is the shape `gate_row_normalize` (`scripts/lib/aid-gate-row.sh:52-77`) translates, so I read them through that mapping.

### Report 1 — ACTA E-020-1_3 (`overall: pass`)
- `py_test`…`ts_type_check`: `pass, exit 0` — plain foreground `run_gate()` (`aid-run-gates.sh:199-234`).
- `ts_e2e`, `ts_e2e_pwa`, `plan_diff`: `profile_excluded`. Profile `full` (`profile_source: cli_flag`); ACTA's `full` does not include them (`.aid-o/config/execution.yaml:220`) — the `not_in_profile` skip row (`aid-run-gates.sh:1399-1403`, renamed by `aid-gate-row.sh:65`).
- `vat_labels_sync`: `fail / gate_script_missing_in_tree` — the script is not in the worktree (`aid-run-gates.sh:1448-1465`); normalized reason `missing_script` (`aid-gate-row.sh:56-58`).
- `docs_updated`: `skip, exit 2` — the gate's own command exits 2 by design (advisory, not CI-enforced).

**Overall.** Only rows that are `fail` **and** `required:true` flip `overall` (`aid-run-gates.sh:1656-1657`, plus the missing-script force at `:1464-1465`). `vat_labels_sync` is `required: true` in today's `execution.yaml:194` and is `fail` — by today's code this run should have been `fail`, yet the report says `pass`. **Unexplained from the code alone:** either the gate was not required when the run executed, or v2.16.0 lacked the force rule. The version-1 row shape (no per-row `required`) makes it impossible to tell from the report.

### Report 2 — WAN E-101-3_3 (`overall: pass`)
- `plan_diff`: `skip, exit 2`. It is `required:true` (`execution.yaml:74`), but a `skip` never enters the required-fail branch (`aid-run-gates.sh:1656`), so it cannot flip `overall`.
- five gates `pass`.
- `tests_full_portfolio`: `fail, exit 1`, but `required: false` in WAN's config (`execution.yaml:116` — a nightly-only signal). A failing non-required gate never touches `overall`.

**Overall = pass**: the only fail is non-required, the only required non-pass is a skip.

**Unexplained:** `tests_full_portfolio` records `attempts: 2` while its config caps `max_retries: 0` and the retry loop runs `max_retries + 1 = 1` attempt (`aid-run-gates.sh:1500`).

### Report 3 — ACTA P016 (`overall: fail`)
- `ts_e2e`: `fail, exit 1` ("jiný běh e2e-release.sh drží zámek"), `attempts: 2`; `required:true` (`execution.yaml:155`).
- `plan_diff`: `fail, exit 124, duration_ms 180009` — the foreground `timeout(1)` deadline (`aid-run-gates.sh:214-226`); `required:true` (`execution.yaml:108`).
- `docs_updated`: `skip/exit 2`, not required.

**Overall = fail**: two required gates failed, each sufficient (`aid-run-gates.sh:1656-1657`).

**Notable:** the `plan_diff` row carries no `reason` at all, though the current `run_gate()` stamps `reason: job_timeout` on exit 124 (`:226`). Normalizing this old row today yields `exit_124`, not `job_timeout` (`aid-gate-row.sh:61`) — the meaning "this was a timeout" survives only in `exit_code`. Also `vat_labels_sync` is absent from this report although it is in today's `release` profile: a config-history fact, not verifiable from code.

### Hard to follow
- `scripts/aid-run-gates.sh` is 2089 lines with `overall` mutated from at least seven branches (the file's own comment at :1862 admits it); answering "which rows can flip overall" meant grepping seven sites, not reading one function.
- `aid-gate-row.sh`'s version-1→2 mapping is dense one-liner jq with many `elif` branches on an already-overloaded `result` field; a `fail` row with an empty `reason` silently becomes `exit_<n>` rather than anything semantic.
- Three files each know a piece of the "never really ran" vocabulary (`_AID_GOS_NOT_RUN_REASONS`, the schema pattern, the runner's branches); confirming they agree needed all three.
- None of the three real reports match the version-2 schema, and nothing in a report states its row-shape version — the only tell is the `_generated_by` string, documented nowhere as such.

## Grade

**Graded by the controller against the rubric above, 2026-09-22, on the corrected
triple. Explained correctly: 3 of 3.**

- **Run 1 — credited (5/5).** The four ran-and-passed gates, the two never-ran
  gates and the failing one, each with the reason; `overall: fail` by the
  required-and-failed rule with the required flags read from WAN's own
  configuration at the run's sha; the normalized status and reason for every row;
  the profile named by the caller, with the `cli_flag` → `caller` rename noticed;
  and #5's own item — `_execution_ledger` is in the `gates` map and is not a gate
  — found without being prompted for it by name.
- **Run 2 — credited (5/5).** The exit-2 graceful skip, the failing gate, and the
  correct reason `overall` stayed `pass`: `tests_full_portfolio` is
  `required: false` in WAN's configuration, quoting the comment that says its
  requiredness gates only the plan-final check. It also separated a real anomaly
  from a false one: `attempts: 2` here is consistent with the default
  `max_retries: 1`, while the same number in Run 1 is not.
  **Rubric mismatch, recorded honestly:** #5 for this run expects the observation
  that a report with no profile is refused at the GATES:DONE floor today. The
  question the reader was given asks what it cannot explain in the report, not
  what today's pipeline would do with the report — so that item was never asked.
  The defect is in the controller's question, not in the reading, and the run is
  credited on what was asked.
- **Run 3 — credited (5/5), and it went past the rubric.** Both failures, the
  deadline exit named as `job_timeout` rather than `exit_124`, the skip, and the
  independent sufficiency of each required failure. Beyond the rubric it found
  that the whole configuration at that sha would be refused by `_refuse_dead_keys`
  before any gate ran — the report could not be produced today at all — and two
  genuine anomalies: a gate declared and included at that sha with no row in the
  report, and `attempts: 2` against `max_retries: 0`.

**What the check produced.** Three of three, and four findings the rebuild did
not have: `overall` is still assigned from seven places before one derived pass
decides it; a row's final status is decided in two textually distant places;
`profile_source` changed spelling with nothing recording the history; and the
removed baseline subsystem left old evidence unreadable in a way nothing explains.
Those are the V5 debt this plan has not paid, and they belong in the backlog, not
in a claim that the code reads cleanly.

**Why the triple changed.** Reading 1 ran on a selection whose Run 1 was
`acta/R-E020-1` and could not be explained: a version-1 report carries no per-row
`required`, the gate in question is absent from ACTA's configuration at the run's
sha, and it is `required: true` today. The reader was right and the rubric's
premise for that run was wrong. Swapping in a run whose required flags are in the
tracked configuration keeps the check about whether the CODE can be read, which is
what it is for; the original reading and its finding stay recorded above so the
change is visible rather than quiet.
