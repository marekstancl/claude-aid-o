# Backlog verification — block 5 (B-005, B-007, B-008, B-002, B-003, B-001)

Repo `/opt/eco/projects/aid-orchestrator`, branch `main`, v2.83.1. All evidence
opened first-hand; test suites run read-only in the repo.

---

## B-005 — CP3 prefilter command can overwrite CP2 verifier evidence (backlog:1815)

verdict: **REAL**

evidence:
- `plugins/aid-orchestrator/scripts/aid-prefilter.sh:96` —
  `local output_file="${evidence_dir}/verifier-output-step-${step_n}.md"`.
  The filename is built from `step_n` only; `checkpoint` never enters it.
- `plugins/aid-orchestrator/scripts/aid-prefilter.sh:62-77` — the `--checkpoint`
  flag IS parsed *before* line 96 (loop at :64-77, validated at :69-72,
  `cp2|cp3|cp4|cp6` accepted). **The recent review's phrasing "computes its
  output filename before it knows the checkpoint" is factually wrong on
  ordering** — the checkpoint is known 19 lines earlier. What is true is that
  the filename simply ignores it. Same defect, wrong causal story.
- `plugins/aid-orchestrator/scripts/aid-prefilter.sh:281` — `cat > "$file"`,
  unconditional truncating overwrite. `:264` — for RUN/FAIL the file is written
  with `verdict: pending`. So a real CP2 verdict is destroyed, not merged.
- The dedicated CP3 convention exists and is enforced:
  `aid-fsm.sh:1463`, `:1823-1828`, `:2509`, `:2954-2984` all read
  `verifier-output-cp3-code-review.md` / `verifier-output-cp3-security.md`.
  `aid-prefilter.sh` writes neither.
- `verifier-output-step-N.md` consumers I opened (confirming the review's "7+"):
  `aid-fsm.sh:2477`, `aid-fsm.sh:5705`, `aid-fsm.sh:5730`, `aid-fsm.sh:5756`,
  `aid-acceptance-evidence.sh:164`, `skills/pipeline.md:781,828,839,884`,
  `commands/aid-run.md:615`, `defaults/templates/verifier-output-template.md:15,39`,
  `agents/verifier.md:86,248`. Renaming the CP2 file is not the cheap path.
- **Blast-radius correction the entry does not know about:** since P060 the FSM
  has a checkpoint guard at the CP2 call site —
  `aid-fsm.sh:5752-5760` fails `increment-step` with `wrong_checkpoint_stub`
  when `verifier-output-step-N.md` carries a checkpoint other than `cp2`.
  A cp3-produced stub therefore *blocks* rather than false-greens.
- **Reachability:** no shipped caller passes `--checkpoint cp3`. Grep over
  `skills/`, `commands/`, `agents/`, `scripts/*.sh` returns only
  aid-prefilter.sh's own usage/parse lines. `skills/pipeline.md:940-1010`
  produces CP3 evidence by dispatching two verifier subagents that write the
  `cp3-{focus}` files directly — the prefilter is not in the CP3 path at all.
  No test exercises `--checkpoint` (grep over `scripts/tests/` = 0 hits).

what_is_true: `classify --checkpoint cp3` is an accepted, documented
(`aid-prefilter.sh:16,19,27-29,45`) command surface that writes CP2's file with a
`pending` stub and produces none of CP3's required artifacts. It is a
loaded-but-unaimed gun: nothing in AID fires it, but the surface is advertised in
`--help`, so an agent recovering from a CP3 precondition failure can reach for it.

impact: An operator/agent who runs the advertised cp3 form destroys the CP2
verdict for whatever step number they pass. The run then hard-fails at the next
`increment-step` with `wrong_checkpoint_stub` (aid-fsm.sh:5754) — so the failure
mode is lost evidence plus a confusing blocked run, not a silent false-green.
Recovery = re-dispatch CP2 for that step.

fix_sketch: Drop `cp3` from the accepted values at `aid-prefilter.sh:70` and make
`--checkpoint cp3` die with "CP3 evidence is written by the verifier subagents to
verifier-output-cp3-{focus}.md; the prefilter has no CP3 mode"; update the header
comment block (:19-29) and usage (:45); add one bats case asserting the rejection
and that an existing `verifier-output-step-N.md` is unmodified. Nothing else
changes — no caller, no test, and no consumer of the CP2 filename is touched.
This is strictly cheaper than the alternative (teach `write_output` a
checkpoint-keyed filename), and it also removes the whole B-008 code path.

effort: **S**

---

## B-007 — Step numbering UX: FSM 0-indexed, plans 1-indexed (backlog:1879)

verdict: **ALREADY_FIXED**

evidence:
- `aid-fsm.sh:1128-1141` — `_fsm_human_step <current> <total>` renders
  ` (human: step N of T is next)` / ` (human: step T of T complete)`.
  Used at `aid-fsm.sh:2858`, `:2870`, `:5246`.
- The evidence-integrity half (the escalation recorded as OBS-20260702-11) is
  closed by canonicalization plus binding, not by wording:
  `aid-fsm.sh:5609` — `local verify_file="${evidence_dir}/step-${step}-verify.md"`
  and `:5705` — `verifier-output-step-${step}.md`: **both artifact families are
  indexed by the same 0-based `step`**, so the offset drift described in the
  observation cannot recur.
  `aid-fsm.sh:5834-5856` — `binding_step_id_mismatch` /
  `binding_plan_step_hash_mismatch`: a verify file copied from another step
  fails the increment ("A verify file bound to another step … cannot complete
  step N").
- Backlog itself already records this: line 1353, OBS-20260702-11 marked DONE
  "Also closes B-007" — I verified that claim against the code above rather than
  taking it.
- `aid-fsm.sh:1122` documents the deliberate residual: internal state stays
  0-based ("current_step=2 for the third step").

what_is_true: The harm named in the entry — "agents can easily dispatch or verify
the wrong step" — is now mechanically blocked (single 0-based convention for both
evidence families + per-step binding). The cosmetic ask ("everywhere the FSM
prints a step number") is only partly delivered: `_fsm_human_step` appears in 3
messages; the `increment-step` failure messages (`aid-fsm.sh:5613-5615`,
`:5840-5856`) and the status JSON (`aid-fsm.sh:5450`) still print the raw 0-based
number with no human gloss. That residual is UX polish with no correctness
consequence left behind it.

impact: none outstanding of the kind the entry described. Residual is readability
of a handful of error strings.

fix_sketch: n/a
effort: n/a

---

## B-008 — CP3 `base_commit` fallback can silently widen/narrow review scope (backlog:1902)

verdict: **REAL** (but narrower than written, and subsumed by the B-005 fix)

evidence:
- The review's claim is **confirmed literally**:
  - CP3 path, `aid-prefilter.sh:148-165` — if `base_commit` is missing or
    `fsm-state.yaml` is absent:
    `diff_base=$(git merge-base HEAD origin/main 2>/dev/null || echo "HEAD~5")`
    (`:159` and `:163`), announced only via `log_warn` (`:160`, `:164`).
    Guessing, non-blocking.
  - CP2 path, `aid-prefilter.sh:106-147` — resolution order step_commit →
    base_commit → **`exit 22` with `cp2_range_undetermined` logged** (`:139-146`).
    Fails closed. The `HEAD~1` fallback survives only under an explicit
    `CP2_RANGE_POLICY=observe` opt-in with a timeline event and a loud stderr
    banner (`:130-138`).
  - The third range consumer, `classify`'s sibling `profile` command, also fails
    closed: `aid-prefilter.sh:369-425`, comment "CRITICAL: no silent HEAD~1..HEAD
    fallback (FC-41)", `exit 22` at `:424`.
  So within one file, cp3 is the only range resolver that guesses.
- **What the entry does not know:** this cp3 branch is unreachable from the
  shipped pipeline. CP3's diff range is decided by the dispatching controller —
  `skills/pipeline.md:961-965`, prompt `<full diff (run_start..HEAD) …>` — and the
  verifier subagents write the `cp3-{focus}` files themselves. No caller passes
  `--checkpoint cp3` (grep over `skills/`, `commands/`, `agents/`,
  `scripts/*.sh`), and no test does either.
- The head-side twin the entry's family refers to IS enforced now:
  `aid-fsm.sh:1419-1513` `fsm_check_cp3_freshness` requires `Reviewed-Head:` on
  both CP3 files, rejects disagreement (`:1489`) and non-ancestry (`:1513`);
  consumed at `:3259` (GATES→DONE) and `:7020` (done-advance).

what_is_true: The silently-approximating code is real and sits at
`aid-prefilter.sh:158-165`. It can only be reached by hand-invoking the same dead
cp3 surface that B-005 is about. So B-008 is not an independent defect with its
own live exposure — it is the second symptom of one dead command mode.

impact: Nobody is hurt on the shipped path today. An operator hand-running the
advertised cp3 form gets a review range silently anchored to
`merge-base HEAD origin/main` (or `HEAD~5` in a repo with no `origin/main` —
worth noting: that literal `HEAD~5` is a magic-number guess, not a boundary).

fix_sketch: Delete the whole `elif [[ "$checkpoint" == "cp3" ]]` branch
(`aid-prefilter.sh:148-165`) as part of the B-005 rejection — the branch is
unreachable once `cp3` is refused at `:70`. If cp3 is ever kept instead of
refused, replace `:159`/`:163` with the CP2 pattern: log
`cp3_range_undetermined` and `exit 22`.

effort: **S** (zero extra cost when done with B-005; S standalone)

---

## B-002 — `test-semantic-review.sh` reported 0/0 by the aggregator (backlog:1925)

verdict: **ALREADY_FIXED**

evidence:
- Ran it: `bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --only
  test-semantic-review.sh` → `Suite 1/1: test-semantic-review  [PASS] 25/25
  passed, 0 failed`; `Tests: 25/25 passed, 0 failed`; `RESULT: PASS`.
  (Note for whoever repeats this: `--only` matches the *filename*, so
  `--only test-semantic-review` errors with "matched no discovered suite".)
- Both sides of the mismatch were repaired:
  - Producer: `scripts/tests/test-semantic-review.sh:221` still prints the legacy
    `=== Results: N passed, M failed ===`, and `:225` now additionally prints the
    canonical `Results: N/T passed, M failed`. The comment at `:223` names the
    reason ("matches neither its `^Results:` anchor nor its `N/T` fraction").
  - Consumer: `scripts/tests/run-all-tests.sh:18-94` `parse_suite_result` accepts
    six documented shapes including `=== Results: N passed, M failed ===`
    (`:30`), and — the structural fix — a missing/ambiguous line is `unparsed`
    and **fails the aggregate** instead of counting as zero (`:38-41`, `:85-94`).
- Named fix: commit `d1c2f5f` "feat(aid): P072 Step 9 — every suite is counted,
  and a miscount can no longer pass as a result"; CHANGELOG.md:576
  ("`run-all-tests.sh` result parsing … anything ambiguous is `unparsed` and
  fails the aggregate instead of counting as zero tests").

what_is_true: 25/25 is reported correctly today, and the class of bug (0/0 read as
success) is now structurally impossible, not just patched for this one suite.

impact: none.
fix_sketch: n/a
effort: n/a

---

## B-003 — `test-plan-to-epic` 2/24 pre-existing failures (backlog:1950)

verdict: **ALREADY_FIXED**

evidence:
- Ran it: `run-all-tests.sh --only test-plan-to-epic.sh` →
  `Suite 1/1: test-plan-to-epic  [PASS] 24/24 passed, 0 failed`; `RESULT: PASS`.
  Zero failures; the count 24 matches the entry's denominator, so no test was
  deleted to reach green.
- Both named assertions still exist in the suite — this is not option (c):
  `scripts/tests/test-plan-to-epic.sh:688` still carries
  `fail "remap plan phase 2 exits with code 0" "got exit code $actual_exit"`
  (the self-dep counterpart likewise present in the same block); they simply no
  longer fire.
- Most recent behavioural change to the suite: `930fcd7` "fix(aid): validate
  source plan before epic generation" (the only content commit after `c2e9549`
  v2.38.0, which the entry names as the last touch; `9c455b6` after it is the
  P081 tier-tag stamp, cosmetic).

what_is_true: The suite is fully green at 24/24 on main. The entry's premise
("permanent red in the full suite") no longer holds. I did not bisect which of
the two named tests was fixed by which commit — the entry's actionable claim
(there are 2 permanent failures) is refuted by running it, which is what was
asked.

impact: none.
fix_sketch: n/a
effort: n/a

---

## B-001 — Autonomous validator-assisted section review (backlog:1976)

verdict: **ALREADY_FIXED** (P039 shipped, and shipped *more* than the entry asked)

evidence:
- The plan exists and stayed: `.aid-o/plans/P039-section-validation.md`.
- The product is live in the file the entry names,
  `plugins/aid-orchestrator/skills/brainstorming.md`, inside the Design
  Validation Protocol (`:265-307`):
  - `:277` — "— Validate-then-verify cycle (P039) — caller-agnostic; runs per
    NON-TRIVIAL section BEFORE it is presented to PM."
  - `:286-290` RULE 9 (validate) — dispatches
    `subagent_type: "aid-orchestrator:verifier"` with `focus=section-review`.
  - `:283-285` RULE 8 — trivial floor: Architecture/Data Model/API/
    Implementation/Migration are ALWAYS non-trivial; the skip judgment "may only
    escalate UP, never down".
  - `:292-298` RULE 10 — the anti-hallucination ground-truth requirement the
    entry did not ask for: every critic claim must be re-confirmed with
    grep/Read, "Taking findings at nominal value and re-wording them as 'I agree'
    is the EXACT failure this prevents."
  - `:299-301` RULE 11 — per-finding agree/disagree stance; an unconfirmable
    file:line defaults to DISAGREE.
- The entry's open question "**Enforcement** … must be decided at design time" was
  answered explicitly, not deferred: `:302-306` RULE 12 — "Enforcement =
  AID-v3-principles §1 mechanism #3 (explicit PM confirmation gate with logged
  justification) — NOT an FSM brake"; a verdict without the claim table is
  INCOMPLETE and MUST NOT be shown to PM.
- The entry's proposed 4-part PM message shape shipped as a 6-block format,
  `brainstorming.md:309-332` ("Section Verdict Format"), including the
  `command_run` column called out as "the anti-hallucination affordance", the
  disagreement-must-be-explicit rule (`:325-326`), and reuse of the existing
  `review_result` enum rather than new labels (`:330-332`).
- Open question "which validator model": answered as the Sonnet critic
  (`brainstorming.md:286`, "dispatch the Sonnet critic").

what_is_true: P039 shipped and closes B-001's substance. Two of the entry's open
questions are answered in a way a plan writer should not re-litigate: enforcement
is a PM confirmation gate (deliberately NOT an FSM brake), and the audit trail is
the in-message claim table, NOT a timeline/evidence event — `brainstorming.md:291`
explicitly forbids stage-log wiring here ("Do NOT wire stage-log events here —
dead no-op in brainstorm, no FSM run"). The entry's bullet asking to "capture
validator output in the evidence/timeline trail per AID evidence conventions" was
therefore consciously rejected, not forgotten.

impact: none.
fix_sketch: n/a
effort: n/a
