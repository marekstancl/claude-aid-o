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

<!-- filled by the controller: the fresh agent's answer, verbatim -->

## Grade

<!-- filled by the controller: per run, per question, against the rubric above;
     then "explained correctly: N of 3" -->
