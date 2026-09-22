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

### Run 1 — `acta/R-E020-1`
`acta/.aid-o/work/evidence/E-020-1_3/R-E020-1/gates/gates_report.json`
(profile `full`, `profile_source: cli_flag`, `overall: pass`)

| gate | recorded result | exit | reason |
|---|---|---|---|
| py_test, py_lint, py_type_check, ts_test, ts_lint, ts_type_check | pass | 0 | — |
| ts_e2e, ts_e2e_pwa, plan_diff | profile_excluded | 0 | profile_excluded |
| vat_labels_sync | **fail** | 1 | gate_script_missing_in_tree |
| docs_updated | skip | 2 | — |

*Why it is here:* a gate FAILED and the run is still green.

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
| 1 | the six stack gates ran and exited 0; three never ran because the profile excluded them; `vat_labels_sync` never ran either — its script is not in the tree; `docs_updated` ran and exited 2 | six gates ran and exited 0; `tests_full_portfolio` ran and exited 1; `plan_diff` ran and exited 2 | eight gates ran and exited 0; `ts_e2e` ran and exited 1; `plan_diff` was killed at its deadline; `docs_updated` ran and exited 2 |
| 2 | `pass`, because `overall` goes to `fail` only for a gate that is **required**; `vat_labels_sync` is not, so its failure does not block | `pass`, same rule: `tests_full_portfolio` is not a required gate | `fail`, because at least one **required** gate (`ts_e2e` / `plan_diff`) failed |
| 3 | `vat_labels_sync` → `fail`/`missing_script`; the three excluded → `skip`/`not_in_profile`; `docs_updated` → `skip`/`exit_2` (its `pass_criteria` accepts exit 2) | `tests_full_portfolio` → `fail`/`exit_1`; `plan_diff` → `skip`/`exit_2` | `ts_e2e` → `fail`/`exit_1`; `plan_diff` → `fail`/**`job_timeout`** (124 is `timeout(1)`'s deadline exit, named, not left as `exit_124`); `docs_updated` → `skip`/`exit_2` |
| 4 | the `full` profile's `include[]`; and `profile_source: cli_flag` says a human typed `--profile full` — the runner chose nothing | nothing: no `--profile` was passed, so every defined gate ran | the `release` profile's `include[]`, again from an explicit flag |
| 5 | nothing about the run itself; the report's `result` field is now the derived version-1 compatibility field, not the row's truth | **yes** — a report with no `profile` is refused at the GATES:DONE floor now; a run that cannot say which profile it ran is not evidence | nothing; a failing required gate is exactly what the run is supposed to record |

Credit for #5 on Run 1 and Run 3 is given for a well-argued "nothing", and for a
correct observation the table does not list. Credit is NOT given for inventing a
refusal that does not exist.

**Score:** 3 of 3 runs explained correctly is the acceptance criterion. Anything
less is a finding about the code, not about the agent.

---

## Reading

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

**Graded by the controller against the rubric, 2026-09-22. Explained correctly: 2 of 3.**

- **Run 1 — not credited.** #1, #3, #4 correct. #2 is where it stops: the rubric expects "pass, because `vat_labels_sync` is not required", and the reader instead showed that the gate IS `required: true` in ACTA's configuration and concluded the run is unexplainable from the code. The controller checked: `vat_labels_sync` carries `required: true` today, and at the run's recorded sha (`03561c8c`) the gate is not in the committed configuration at all. So the rubric's premise is the wrong one and the reader's "unexplained" is the honest answer — but it is still not an explanation of the run, which is what this check asks for. Not credited, and the shortfall is recorded as a finding about the evidence, not about the reader (the rubric's own rule).
- **Run 2 — credited.** All five, with the required/non-required distinction verified in WAN's own configuration. It additionally found `attempts: 2` on a gate capped at `max_retries: 0`, which the rubric does not list and which the controller confirms is real in the recorded row.
- **Run 3 — credited.** All five, including #3's point: `exit 124` is the deadline exit, a live run names it `job_timeout`, and the reader also showed that normalizing THIS old row gives `exit_124` because the row carries no `reason`.

**The finding this check produced.** A version-1 report cannot answer "why was `overall` what it was", because it carries no per-row `required`. That is a property of the old evidence, and it is exactly what the version-2 row fixes (`required` + `required_source` on every row, P097 Steps 2 and 6): a run recorded by the rebuilt runner is answerable, the three runs available to this check are not. The check therefore reads 2 of 3 with the third blocked by the evidence, not by the code — and the reader's three "hard to follow" notes (seven `overall` mutation sites, the dense version-1 mapping, the vocabulary split across three files, no row-shape version in a report) are the V5 debt P097 has not paid.
