# AID Orchestrator — Backlog

Project-internal backlog items. Ecosystem-shared items live in `/opt/eco/BACKLOG.md`.

Format: each item has a status (`idea` / `scoped` / `ready` / `dropped`), a one-line
summary, context, the proposed change, and open questions. Items graduate to a real
plan via `/aid-plan`.

---

## Live probe observations (B-004 operating mode)

### OBS-20260702-01 - Re-scope re-init reuses run_id, overwrites plan evidence, bypasses duplicate-init guard without audit event

**Observed in:** WAN / P058 / E-058-2_6 / R-E058-2
**AID version:** v2.50.1
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** medium
**Class:** evidence integrity / command surface

**What happened:** The EPIC was narrowed from 3 steps to 1 step (PM decision,
option A). The run was re-initialized under the SAME run_id `R-E058-2`:
`timeline.jsonl` shows two `fsm_init` events (2026-07-01 `total_steps=3`,
2026-07-02 `total_steps=1`) with no `fsm_force_override` event between them.
`aid-fsm.sh` has a duplicate-init guard (`state_file already exists`, ~line 1617)
and its `--force` path logs `fsm_force_override` — absence of that event means the
old `fsm-state.yaml` was deleted manually to get past the guard. `plan.json` and
`epic_input.md` in the canonical evidence dir were overwritten in place (mtimes
2026-07-02 06:03); the original 3-step plan.json is not archived anywhere.

**Why it matters:** Run identity is now ambiguous — `R-E058-2` refers to two
materially different plans over time, and the only surviving trace is the
append-only timeline plus an accidentally-surviving old run.md. The guard exists
but the practical workaround (delete state file) leaves no force/override audit
trail. A later audit that checks "evidence matches plan for R-E058-2" cannot
reconstruct what was descoped. Positive: `base_commit` was correctly refreshed to
the new branch start (`2a06b76`) on re-init, and the append-only timeline is what
made this detectable at all.

**Reproduction:** `cat .aid-o/work/evidence/E-058-2_6/R-E058-2/timeline.jsonl`
(two fsm_init, no force event); mtimes of `plan.json`/`epic_input.md` vs first
`fsm_init` ts; `grep -n "state_file already exists" aid-fsm.sh`.

**Likely fix:** Add a first-class re-scope path: `aid-fsm.sh init --rescope`
that (a) archives prior `plan.json`, `epic_input.md`, `fsm-state.yaml` into
`rescope-<ts>/` inside the run evidence dir, (b) logs an `fsm_rescope` timeline
event with old/new step counts, and (c) refuses plain re-init when evidence
exists. Alternative: require a new run_id suffix (`R-E058-2b`) for any plan-hash
change.

**Recurrence 2026-07-02 (E-058-3_6/R-E058-3):** same pattern on the very next
EPIC — timeline shows two `fsm_init` events (2026-07-01 and 2026-07-02, both
total_steps=3), no `fsm_force_override`, plan.json/epic_input.md/fsm-state.yaml
overwritten in place at 06:35. base_commit again correctly refreshed (9b3cc16).
Two independent EPICs within one plan → **cleanup trigger for this class is
met** ("the same failure class appears in at least two independent EPICs").

### OBS-20260702-02 - run.md for the same run_id exists at two different canonical paths

**Observed in:** WAN / P058 / E-058-2_6 / R-E058-2
**AID version:** v2.50.1
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** low
**Class:** UX indexing / command surface

**What happened:** The 2026-07-01 generation wrote the run file to
`.aid-o/work/runs/R-E058-2/R-E058-2-ocr-pipeline-produkuje-spolehliv-data-gd.md`
(subdirectory per run_id, 26 KB, broad 3-step scope). The 2026-07-02 regeneration
after descope wrote `.aid-o/work/runs/R-E058-2-e-058-2-6-ocr-extrakce-normalizace-docum.md`
(flat file at runs/ top level, 7 KB, narrowed scope). Nothing marks the older
file as superseded.

**Why it matters:** An agent (or the PM) looking up "the run file for R-E058-2"
finds two candidates with different scopes and no supersede marker — exactly the
"file names cause the agent to pick the wrong target" probe class. The stale
broad-scope run.md is the more detailed-looking of the two, which invites picking
the wrong one.

**Reproduction:** `ls .aid-o/work/runs/ | grep -i 058-2` and
`ls .aid-o/work/runs/R-E058-2/` in the WAN repo.

**Likely fix:** Pin one canonical location (`runs/<run_id>/run.md` preferred);
regeneration must replace or archive the previous file at that same path, never
create a differently-named sibling. Related: OBS-20260702-01 (same re-init flow).

### OBS-20260702-03 - CP3 evidence freshness not enforced: GATES→DONE accepts review that predates gate-fix commits

**Observed in:** WAN / P058 / E-058-2_6 / R-E058-2
**AID version:** v2.50.1
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** high
**Class:** stale evidence / evidence integrity

**What happened:** CP3 code-review + security outputs were generated at
04:14-04:16Z and explicitly state they reviewed `git diff 2a06b76..HEAD` when
HEAD was `32323b4`. Gates then FAILED (`moved_integration_tests` — migration
chain test hardcoded old head), a gate-fix commit `96a72df` landed (~04:19Z),
gates re-ran PASS, and the FSM transitioned EXECUTE→GATES (04:20:29Z) and
GATES→DONE (04:20:41Z) with the original CP3 files untouched (mtimes 06:15/06:17
local). `fsm_check_verifier_output` (aid-fsm.sh ~177-236) validates existence,
`_generated_by`, `_generated_at`, `classification`, and `verdict` — it has no
freshness/head-binding check, so a CP3 review that predates later commits
satisfies the DONE precondition. `final_report.md` reports "CP3 — PASS" and
lists commit `96a72df`, without disclosing that CP3 never reviewed it.

**Why it matters:** Gate-fix commits land after CP3 review BY CONSTRUCTION
whenever gates fail — this exact sequence occurs in every fail→fix→pass cycle
(E-058-1 had gate-fix loops with production-code changes). In this run the
uncovered commit was a test-only assertion update (harmless), but the mechanism
lets arbitrarily large post-review commits reach DONE marked "CP3 PASS". At
plan-close the stale PASS becomes release proof. Contrast: the protocol-v2
`delivery-gate.json` in the same run DOES bind evidence to a revision
(`revision.head_sha`, `freshness: current`) — the binding machinery exists in
C0-C4 but legacy CP3 markdown evidence is not revision-bound. This is the
head-side twin of B-008 (base-side range approximation).

**Reproduction:** In the WAN run evidence dir compare
`verifier-output-cp3-*.md` `_generated_at` (04:14/04:16Z) and the reviewed
range stated in the security file vs `git log` (`96a72df` committed ~04:19Z)
and `timeline.jsonl` (GATES→DONE 04:20:41Z, no CP3 re-dispatch, no force
override). `grep -n -A60 'fsm_check_verifier_output()' aid-fsm.sh` — no HEAD
comparison.

**Likely fix:** CP3 verifier outputs must record the reviewed `head_sha`;
GATES→DONE precondition compares it to current HEAD and fails with a clear
recovery instruction (re-dispatch CP3 or explicit `--force --reason` waiver)
when commits exist past the reviewed head. Optionally allow a scoped exception
for diffs touching only test files, but make that an explicit policy, not
silence.

### OBS-20260702-04 - final_report.md omits D0 delivery-gate result (delivery_ready=false, 15 unverifiable findings)

**Observed in:** WAN / P058 / E-058-2_6 / R-E058-2
**AID version:** v2.50.1
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** medium
**Class:** docs drift / merge policy (PM communication)

**What happened:** The D0 observe-mode delivery gate ran at the EXECUTE→GATES
transition (timeline `d0_delivery_gate`, exit_code 0, observe=true) and wrote
`delivery-gate.json` with `status: "fail"`, `verdict.delivery_ready: false`,
and 15 medium findings — all `delivery_gate_unverifiable` (dg01-dg18,
`skip_reason: unverifiable_profile`, i.e. no delivery profile configured for
WAN). `final_report.md` reports CP2 PASS, CP3 PASS, Gates 4/4 PASS and does not
mention the delivery gate at all. Additionally the artifact contradicts itself:
`delivery_gate.freshness: "stale"` while `revision.freshness: "current"`.

**Why it matters:** This is probe class "a report says pass while important
advisory checks failed without clear wording". Observe-mode non-blocking is by
design (E2/E-050 rollout), but a PM reading final_report.md sees all-green and
has no signal that (a) a delivery-readiness artifact exists, (b) it could not
verify anything because the project has no profile, and (c) it says
delivery_ready=false. Silent observe-mode also generates no pressure to ever
configure the profile. The dual freshness fields make the artifact ambiguous
for any future automated consumer (AID Cockpit / read-model class).

**Reproduction:** `python3 -c "import json; d=json.load(open('.aid-o/work/evidence/E-058-2_6/R-E058-2/delivery-gate.json')); print(d['status'], d['verdict'], d['delivery_gate']['freshness'], d['revision']['freshness'])"`
vs `grep -i delivery .aid-o/work/evidence/E-058-2_6/R-E058-2/final_report.md`
(no match).

**Likely fix:** Final report template gains a mandatory delivery-gate line
(phase, status, delivery_ready, findings count, unverifiable-profile hint with
setup pointer). Define which freshness field is authoritative in
delivery-gate.json and remove or derive the other.

**Recurrence 2026-07-02 (E-058-3_6/R-E058-3):** identical on the next EPIC —
`delivery-gate.json` again `status: fail`, `delivery_ready: false`, 15
unverifiable findings, same internal freshness contradiction
(`delivery_gate.freshness: stale` vs `revision.freshness: current`), and
`final_report.md` again contains zero mention of D0/delivery-gate. Two
independent EPICs → **cleanup trigger for this class is met.**

### OBS-20260702-05 - Plan-declared gate silently never runs when undefined in execution.yaml

**Observed in:** WAN / P058 / E-058-2_6 / R-E058-2
**AID version:** v2.50.1
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** high
**Class:** docs drift / command surface (false-green surface)

**What happened:** `plan.json` declares a top-level `gates: ["docs_updated"]`
for the EPIC. `execution.yaml` defines only `unit_tests`,
`moved_integration_tests`, `counts_invariant_tests`, `ruff_lint` — no
`docs_updated`. The gate runner executed exactly the 4 execution.yaml gates and
reported `overall: pass`; the plan-declared gate never ran, produced no
unknown-gate error, no warning in `gates_report.json`, and no line in
`final_report.md`. The run reached DONE with the documentation gap the gate was
supposed to catch (new API field with zero doc trail). The EPIC-level auditor
(C1 trigger) caught it post-DONE — detection worked at the audit layer, but the
gate layer silently dropped a declared control.

**Why it matters:** A plan author can declare a quality gate that structurally
cannot execute, and every downstream report still says PASS. This is a
false-green surface: the plan→execution contract is not reconciled anywhere.
The failure mode is silent by construction, so it will recur in every project
whose execution.yaml lags behind plan vocabulary. Textbook Principle #1 case
(*Detector without Enforcement is Decoration*): the declaration exists, the
enforcement never fires.

**Reproduction:** In the WAN repo compare
`python3 -c "import json; print(json.load(open('.aid-o/work/evidence/E-058-2_6/R-E058-2/plan.json'))['gates'])"`
(`['docs_updated']`) vs `grep docs_updated .aid-o/config/execution.yaml` (no
match) vs `gates_report.json` `_command_log` (4 gates, overall pass).

**Likely fix:** `aid-run-gates.sh` (or the FSM pre-gates step) must reconcile
`plan.json.gates[]` against execution.yaml gate definitions and hard-fail with
a clear message when a declared gate has no definition — or at minimum write a
`result: fail, reason: undefined_gate` entry into gates_report.json so overall
cannot be pass. plan.schema.json should state which component consumes
`gates[]` and what happens when a name does not resolve.

**Recurrence 2026-07-02 (E-058-3_6):** the next EPIC's plan.json again declares
`gates: ["docs_updated"]` while execution.yaml still lacks the definition — the
silent drop will repeat at E3's gates phase and, since the declaration comes
from the shared P058 plan, in every remaining EPIC of the plan. Second
independent EPIC → **cleanup trigger for this class is met.**
Confirmed at E3 gates time (07:38Z): gates_report again ran only the 4
execution.yaml gates, overall pass. Mitigation nuance: this time
`final_report.md` DISCLOSED the gap manually ("docs_updated gate by
triggeroval" in Open Items) — the implementer learned from the E2 audit
finding. The mitigation is agent discipline, not system enforcement; the
silent-drop mechanism itself is unchanged.

### OBS-20260702-06 - FSM pre-commit hook conflicts with per-Plan deferred-merge model, normalizing --no-verify bypass

**Observed in:** WAN / P058 / E-058-1_6 + E-058-2_6 + E-058-3_6 (5 commits)
**AID version:** v2.50.1
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** high
**Class:** docs drift / merge policy (enforcement bypass normalization)

**What happened:** The AID-generated pre-commit hook blocks ANY commit on
`task/*`/`epic/*` branches when `state: DONE && done_phase != release`. The
PM-chosen per-Plan deferred-merge model intentionally holds every EPIC in
`DONE/review` until the whole plan finishes — so every legitimate post-review
action (PM-approved bug fixes, Curator bookkeeping, even the NEXT EPIC's task
scaffold) hits the hook. Result on plan P058: five commits bypassed it with
`--no-verify`, self-documented in their commit messages (`a6174d9`, `4e98076`,
`57d89f0`, `f22f0d1`, `9b3cc16`). The bypass has become the routine, applied
even to commits the hook might not have blocked. The FSM transition table has
no path out of DONE except `done-advance review→release`, so no mechanical
"reopen for fix cycle" exists.

**Why it matters:** A guardrail that legitimate workflow must routinely bypass
trains agents to reach for `--no-verify` by default — which skips ALL hook
checks, not just the FSM guard. This inverts the control system's purpose:
the hook now selects FOR unaudited commits. Every bypass is invisible to the
FSM/timeline (no force-override event, only a good-faith commit-message note).
WAN-side already analyzed this as backlog item T-151 (2026-07-01) with a
concrete proposal; recording here because the fix belongs in the AID plugin,
not in the consumer project.

**Reproduction:** `git log --all --grep="no-verify" --oneline` in the WAN repo
(5 hits on P058); hook source `.git/hooks/pre-commit` (AID-generated block);
WAN `.aid-o/work/backlog.md` T-151.

**Escalation 2026-07-02 (E-058-3_6, commit `c0505fb`):** the normalization has
progressed to SILENT bypass — the E3 DONE-review bookkeeping commit landed on a
DONE/review branch (hook active and blocking by design) with NO `--no-verify`
note in the commit message, unlike the five earlier bypasses which at least
self-documented. The bypass is now invisible: only cross-referencing hook
source + fsm-state at commit time reveals it. Sixth bypass, first undocumented.

**Likely fix:** Adopt T-151's direction: (a) a documented post-review-fix path
— PM-approved marker file (`post-review-fix-approved.json` with reason +
timestamp, analogous to `--force --reason`) that the hook honors and logs as a
timeline event, or (b) an `aid-fsm.sh` subcommand for a "reopen fix cycle"
that permits commits in DONE/review without forcing premature release. Either
way the hook must offer a legitimate escape hatch so `--no-verify` stops being
the path of least resistance.

### OBS-20260702-10 - Auditor/Curator verdicts exist only as implementer prose; no canonical audit-report artifact for E-058-3

**Observed in:** WAN / P058 / E-058-3_6 / R-E058-3
**AID version:** v2.50.1
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** high
**Class:** evidence integrity (missing provenance / self-written review evidence)

**What happened:** The E3 DONE-review bookkeeping commit (`c0505fb`) and
`active.md` cite "Auditor skóre 96/100, blocking_findings=false" and Curator
findings IMP-123/124 — but no `audit-report.yaml`, `audit-report.md`, or any
curator artifact exists anywhere in `.aid-o` for E-058-3 (searched the whole
tree, zero files matching `*audit*`/`*curator*` modified today). Contrast E2:
`evidence/E-058-2_6/audit-report.yaml` with the machine-readable top-level
`blocking_findings: false` field explicitly commented "CANONICAL — FSM reads
this", plus the full `audit-report.md`.

**Why it matters:** The auditor verdict for E3 is unverifiable from artifacts —
it survives only as prose WRITTEN BY THE IMPLEMENTER (active.md + commit
message), which is exactly the "self-written verifier evidence" probe class.
The FSM's done-advance machinery reads `blocking_findings` from
audit-report.yaml; with no file, any later mechanical check (plan-close
aggregating per-EPIC Curator+Auditor results — the whole point of the per-Plan
model) has nothing to read for E3. Artifact persistence is also inconsistent
across consecutive EPICs of the same plan (E2: EPIC-level files; E3: nothing),
so a plan-close aggregator cannot even rely on a stable location.

**Reproduction:** `find .aid-o -iname "*audit*" -newermt "2026-07-02 09:00"`
in the WAN repo (empty) vs `git log -1 --format=%B c0505fb` (cites the score);
`ls .aid-o/work/evidence/E-058-2_6/audit-report.*` (E2 files exist).

**Likely fix:** Auditor/Curator dispatch must write their canonical artifacts
(audit-report.yaml/md, curator findings) to a pinned per-EPIC evidence path as
a hard output contract — and the DONE-review phase should have a precondition
(like CP2/CP3 have) that refuses to record "review complete" without the
artifacts on disk. Prose summaries in active.md are a view, never the source
of truth.

### OBS-20260702-07 - EPIC generation is not idempotent across partial runs and has no clean recovery path

**Observed in:** aid-orchestrator / P057 (e8-c3-independent-audit) / epic-gen for E-057-1_2 + E-057-2_2
**AID version:** HEAD (post v2.50.1)
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** medium
**Class:** command surface / evidence integrity (partial-run recovery)

**What happened:** During P057 epic generation, a git race with a concurrent
observer session (docs commit `8a38f68` landed on the freshly created
`task/E-057-1_2/main` branch — the repo checkout is shared) caused the pipeline
to crash mid-generation on a duplicate/branch-state error. Leftover partial
state on disk: `evidence/E-057-1_2/R-E057-1/` with fsm-state.yaml (READY,
`base_commit: 8a38f68` — the foreign docs commit is baked into the run
identity), `evidence/E-057-2_2/R-E057-2/` WITHOUT fsm-state.yaml (only
epic_input + plan.json + timeline), two task files, two runs dirs, the task
branch, and a queue entry. PM removed the queue entry manually (worked), but
resetting the remaining artifacts required destructive deletes that the
permission layer (correctly) refused — leaving no supported way to return to a
clean pre-generation state.

**Why it matters:** A crashed epic-gen cannot be cleanly re-run: the
duplicate-init guard (see OBS-20260702-01) now blocks regeneration, and manual
cleanup requires exactly the destructive operations agents are prevented from
doing. The operator is stuck between a guard and a denial. Shared-checkout git
races make partial crashes more likely, and foreign commits get recorded as
`base_commit`, contaminating run identity. Recovery friction directly invites
guard-bypass behavior (delete state files by hand — the OBS-01 root cause).

**Reproduction:** In aid-orchestrator repo: `find .aid-o/work/evidence/E-057-* -type f`
(R-E057-2 missing fsm-state.yaml), `grep base_commit
.aid-o/work/evidence/E-057-1_2/R-E057-1/fsm-state.yaml` (foreign docs commit),
`git branch | grep 057`. PM field report 2026-07-02.

**Likely fix:** Make epic generation transactional: stage all generated
artifacts (evidence dirs, task files, run files, queue entry, branch creation)
and commit them atomically at the end, or provide
`aid-auto-pipeline.sh rollback <plan-id>` that removes exactly the artifacts a
partial generation created (reading them from a generation manifest). The
rollback path must be non-destructive-by-whitelist (only deletes files the
manifest lists) so it does not require blanket destructive permissions.

**Recovery outcome (2026-07-02 ~08:00):** PM recovered via manual wipe + full
regeneration — both evidence dirs recreated at 07:59 with single fsm_init each,
branches re-pointed to the current main tip, base_commit now clean (`ac0f287`).
Two follow-up facts for the cleanup session: (a) run_ids R-E057-1/R-E057-2 were
reused for the regenerated runs, and (b) the crashed generation's timeline
(fsm_init 04:40Z, base 8a38f68) was erased with the wipe — unlike the WAN
rescope (OBS-01) where the append-only timeline preserved the history, here the
prior init is documented only in this backlog entry. A transactional gen (or
manifest rollback) would have produced the same clean end state without erasing
run history.

### OBS-20260702-08 - Generated plan.json contracts are malformed and no gate validates them (pointer)

**Observed in:** aid-orchestrator / P057 / E-057-1_2 + E-057-2_2 (generated contracts)
**AID version:** HEAD (post v2.50.1)
**Observed at:** 2026-07-02
**Status:** confirmed (PM manual inspection; independently verified by observer)
**Severity:** high
**Class:** false-green / command surface (generator contract validation)

**What happened:** PM field finding, recorded in full in the
"GENERATOR / CONTRACT-VALIDATION gap" section at the end of this file:
`aid-plan-to-epic.sh` + `aid-epic-to-json.sh` collapse per-step scoping
(every step gets ALL outputs/ACs/allowed_paths), corrupt ACs containing `|`
(split on pipe), leak prose into allowed_paths, and drop inter-step deps —
while C0/CP1 review only the PLAN, so the malformed generated contract passes
everything. Observer verification on E-057-1_2 plan.json: 4 steps with
identical outputs (8) and ACs (13) each, AC[12] is the fragment
"length\`; TTL guard projde." (pipe-split), `depends: [None×4]`.

**Why it matters / likely fix:** see the PM section (fix candidates 1-5; key
one: a NEW GATE validating the generated plan.json contract). Probe-wise this
is the strongest false-green instance so far: it affects every EPIC generation
and has silently degraded per-step contracts across E1-E8.

### OBS-20260702-09 - aid-plan-diff parses only "## Acceptance Criteria" heading; plans use "## Success Criteria" → skip→pass, ACs never executed (pointer)

**Observed in:** aid-orchestrator / plans P049-P058 era / `aid-plan-diff.sh`
**AID version:** HEAD (post v2.50.1)
**Observed at:** 2026-07-02
**Status:** confirmed (PM finding via P058 CP1-deep L3 lens; independently verified by observer)
**Severity:** high
**Class:** false-green / docs drift

**What happened:** PM field finding, recorded in full in the
"PLAN-DIFF heading drift" section at the end of this file. Observer
verification: `aid-plan-diff.sh` AWK range (line ~131) matches only
`/^## Acceptance Criteria/`; P057 and at least 10 recent plans put their
verification_pattern ACs under `## Success Criteria` (P057 line 404, no
Acceptance heading) → `ac_count: 0` → `verdict: skipped`, exit 2 → gate treats
skip as pass. The verification_pattern ACs of those plans were never executed
by plan-diff.

**Why it matters / likely fix:** see the PM section. Probe-wise: second
generator/contract false-green in one day (with OBS-08) — both are
"declared control never actually runs, everything reports green", same class
as OBS-05 (undefined gate silently dropped). Pattern across all three: a
declared control resolves to a no-op without any error surface. Also note the
PM point that skip-as-pass on a plan that HAS ACs should be distinguishable
from a legitimate Fast-Mode skip.

---

### OBS-20260702-11 - Evidence step-numbering offset drift: agents write 1-based files, FSM checks 0-based

**Observed in:** aid-orchestrator / P058 / E-058-1_1 / R-E058-1 (and B-007 corroboration in WAN E-058-2/3)
**AID version:** HEAD (pre-v2.51.0)
**Observed at:** 2026-07-02
**Status:** confirmed
**Severity:** medium
**Class:** UX indexing / evidence integrity

**What happened:** The implementer wrote CP2 evidence for the FIRST step as
`verifier-output-step-1.md` (1-based, matching plan "Step 1"); the FSM
increment demanded 0-based `step-0` files (`fsm_increment_fail:
missing_step_verify`). The agent recovered by DUPLICATING evidence under both
numberings (step-0 + step-1 files for one step), then continued 1-based for
verifier outputs and 0-based for step-N-verify files — a consistent offset:
`verifier-output-step-{k}` is 1-based while `step-{k-1}-verify.md` is 0-based,
and the FSM's per-step check validates a file whose number does not match the
step it gates. No overwrite occurred (each artifact type stayed internally
consistent), but the numbering convention is pinned nowhere and each
session/project picks differently (WAN runs used 0-based verifier outputs).

**Why it matters:** B-007 escalated from UX annoyance to evidence-integrity
risk: one step owning two file numbers invites a later step to overwrite or a
consumer to read the wrong step's verdict. The FSM enforcement caught the
initial mismatch (good), but the recovery created duplicate evidence rather
than a canonical correction.

**Reproduction:** `ls .aid-o/work/evidence/E-058-1_1/R-E058-1/ | grep -E
"step-[0-9]"` — step-0..step-2 files where 0 and 1 are both the first step;
timeline increment_fail events 2026-07-02 08:23Z.

**Likely fix:** Pin ONE canonical numbering for evidence filenames (recommend
1-based to match plans, with FSM translating internally), enforce it in
`fsm_check_verifier_output` (reject wrong-numbered files with a clear message),
and print both forms in all FSM output (`current_step=1 (Plan Step 2)`) per
B-007.

### OBS-20260705-01 - CP2 prefilter classifies by wrong diff range: production step marked docs_only SKIP

**Observed in:** WAN / P058 / E-058-4_6 / R-E058-4 step 0
**AID version:** v2.50.1
**Observed at:** 2026-07-05
**Status:** confirmed (recovered same run)
**Severity:** high
**Class:** false-green / prefilter diff range

**What happened:** Step 1 (`7580ed0`) changed production code (erp_write.py
+19, enums.py +13, validators/format.py +44, +95 test lines). A bookkeeping
commit (`b0ef918`, active.md only) landed on top. CP2 prefilter then classified
the step SKIP with matched rule `docs_only` — it evidently evaluated only the
latest commit instead of the step's full diff range — and wrote a SKIP stub
that `fsm_check_verifier_output` accepts. A production step would have passed
with zero verification. Recovery: the implementer dispatched a real CP2 anyway
(RUN/pass, 11:22), overwrote the stub, and the run continued correctly; the
bogus SKIP event remains in the append-only timeline as proof.

**Why it matters:** Same family as B-008/OBS-03 (wrong diff range), on the
prefilter side: any step whose last commit is docs/bookkeeping gets its
verification silently skipped. Recovery relied on agent discipline, not
enforcement. Contrast: later the same day, a genuinely docs-only step
(E-058-5 step 2) was correctly SKIPped — the rule itself is fine, the range is
wrong.

**Reproduction:** WAN timeline event `prefilter_classification step:0
SKIP docs_only` (2026-07-05 09:16:37Z) vs `git show --stat 7580ed0` and
`b0ef918`.

**Likely fix:** `aid-prefilter.sh` must diff from the step boundary (or
base_commit) to HEAD, never a single commit; `docs_only` must never match when
the range contains production paths.

**Recurrence 2026-07-06 (E-058-6_6 step 1):** identical mechanism — production
step `5209475` (Structured Outputs wiring: config/extractor/json_schema) topped
by docs commit `c127ebf` (D-005) → prefilter SKIP/docs_only (06:13:33Z).
Recovered again by manual CP2 dispatch, this time SELF-DOCUMENTING: the
verifier output header states "manual dispatch — pre-filter misfire correction"
and names the correct reviewed commit. Two EPICs (E4+E6) → **cleanup trigger
met**; the workaround is becoming routine agent labor that the fix should
eliminate.

### OBS-20260705-02 - fsm-state.yaml mutations without timeline events (base_commit, plan_json_hash)

**Observed in:** WAN E-058-4/5/6 starts + aid-orchestrator E-057-1/2 regen
**AID version:** v2.50.1 / HEAD
**Observed at:** 2026-07-05 (3+ instances)
**Status:** confirmed
**Severity:** medium
**Class:** evidence integrity (unevented state mutation)

**What happened:** Three-plus confirmed instances of `fsm-state.yaml` fields
changing with NO corresponding timeline event: (a) E-058-4 start — base_commit
9e858cd→f9faaae; (b) E-057-1/2 — plan_json_hash refreshed after contract
regeneration; (c) E-058-5 start — base_commit 9e858cd→431feb7 (and E-058-6
likewise). All mutations were correct in intent (fresh base for stacked EPICs,
hash matching regenerated plan) and the timelines were preserved (no wipe —
improvement over OBS-01), but the state file history is not reconstructible
from events.

**Why it matters:** The timeline is the audit trail; if routine operations
mutate state silently, "state matches events" cannot be verified and the OBS-01
guard-bypass class stays invisible. The improvement (edit-in-place instead of
wipe+reinit) should be completed with eventing.

**Likely fix:** every fsm-state mutation goes through an `aid-fsm.sh set-field`
style command that logs a `fsm_field_change` timeline event (field, old, new,
reason). Note: v2.51.0 already hardened set-field itself (slash/backslash
bugs) — wiring it as the only mutation path + eventing is the remaining step.

### OBS-20260705-03 - Untracked AID-look-alike branch work never covered by any checkpoint

**Observed in:** WAN / P058 / branch task/E-058-3_6-fe/main (4 commits)
**AID version:** v2.50.1
**Observed at:** 2026-07-05 (structurally confirmed)
**Status:** confirmed
**Severity:** medium
**Class:** branch/run identity / review coverage

**What happened:** FE follow-up work (IMP-123) was done on branch
`task/E-058-3_6-fe/main` — AID naming convention, but NO run: no evidence dir,
no fsm-state, no task file, no CP2/CP3. The integration branch (f9faaae) then
became the base for E-058-4/5/6, placing the 4 FE commits BELOW every later
EPIC's base_commit: E3's CP3 predates them, E4+'s CP3 ranges start after them.
By construction, no AID checkpoint will ever review these commits, yet they
flow to main through the plan lineage at plan-close.

**Why it matters:** The naming makes the branch LOOK AID-managed; a plan-close
reviewer sees task/* branches and assumes coverage. Ad-hoc side work is a PM
prerogative, but the system offers no signal distinguishing "verified EPIC
work" from "untracked work in EPIC clothing" in the merged history.

**Likely fix:** plan-close (C4) should compute review coverage over the full
merge range (which commits were inside some run's verified range) and list
uncovered commits for explicit PM acknowledgment. Optionally: warn when a
task/* branch has no matching run evidence.

### OBS-20260706-01 - gates_report.json written to two different paths across runs/re-runs

**Observed in:** aid-orchestrator / E-058-1_1 / R-E058-1
**AID version:** HEAD (v2.51.0 cycle)
**Observed at:** 2026-07-06
**Status:** confirmed
**Severity:** low
**Class:** UX indexing / command surface

**What happened:** The original gates run wrote
`R-E058-1/gates/gates_report.json` (07-05, contains plan_diff:skip); the
post-fix re-run wrote flat `R-E058-1/gates_report.json` (07-06,
plan_diff:fail). Two reports, two vintages, no supersede marker — a consumer
reading the subdir path sees stale results. Same class as OBS-02 (run.md path
duality), now on gates evidence. WAN runs consistently used the `gates/`
subdir path.

**Likely fix:** one canonical path; re-runs overwrite it (timeline already
preserves per-run history).

### Probe update 2026-07-05/06 — recurrences, escalations, remedies observed

Compact ledger updates to existing findings (details in observer working notes):

- **OBS-03 (CP3 freshness): instance #2 confirmed at E-058-4 DONE** (test-only
  gate-fix `b8f0546` uncovered; GATES→DONE 10:07:55Z with CP3 untouched) →
  cleanup trigger MET. **Instance #3 at aid-orchestrator E-058-1_1** — first
  with a PRODUCTION post-review commit (`765aba5`, regex fix in scoping
  lookup); GATES→DONE with stale CP3, cross-project pattern. **Remedy pattern
  observed at v2.51.0 merge:** independent `verifier-output-pm-fix-cycle.md`
  (FULL_REVIEW, pass, found+fixed one more bug 67ee875) dispatched over ALL
  post-review commits + `BOOTSTRAP-EXCEPTION.md` waiver doc before merge — this
  is the behavior the OBS-03 fix should mechanize.
- **OBS-05 (declared gate silently dropped): recurrence #3+ **— every P058 EPIC
  (WAN E4/E5/E6 + AID E-058-1_1) declares `docs_updated`. Root cause chain:
  `aid-plan-to-epic.sh:843` hardcodes it into every generated EPIC;
  `defaults/execution.yaml:23` defines it but live project configs (WAN + AID)
  drifted and lack it; no reconciliation → silent drop;
  `enforcement-registry.yaml:154` still lists it severity:blocking
  status:active. Cross-project systemic.
- **OBS-06 (hook bypass): tally 9** — 6th (c0505fb) and 7th (3fd7a2c,
  production post-DONE fix) SILENT, undocumented; 8th (8215500) silent; 9th
  (f1f253c) documented again. Note: the aid-orchestrator repo has NO FSM
  pre-commit hook, so the conflict is WAN-deployment-specific.
- **OBS-10 (audit verdict prose-only): recurrences E4 + E5** (no artifacts,
  verdicts only in commit messages; WAN on old plugin). **Positive contrast:**
  AID E-058-1_1 persisted the complete review pack (curator-report,
  audit-report yaml+md, CP4 curator-validation, simplifier-report, reporter
  smoke evidence, verification-report.json, ca-review-complete) — pin this as
  the contract.
- **OBS-08 (generated contracts): fix VERIFIED live** — v2.51.0 per-step
  scoping works on regenerated E-057 contracts (outputs 3/1/2/2, zero AC
  fragments) with `.pre-P058-fix.snapshot` archives (OBS-01 lesson adopted);
  `depends` derivation still open. The fix-EPIC ran on its own malformed
  contract under an explicit, PM-authorized `BOOTSTRAP-EXCEPTION.md`.
- **OBS-09 (plan-diff heading): fix landed** (a22b2cd) — and exposed the next
  layer: `plan_path: null` in fsm-state made the gate skip-as-pass anyway
  (plan_path plumbing never wired at init), then after the YAML-unescape fixes
  the gate finally RUNS and FAILS LOUDLY (advisory) — meta-pattern remedy
  visible in practice.

### OBS-20260708-01 - Shared-checkout session committed EPIC steps to main mid-EXECUTE, duplicating them against the task branch

**Observed in:** aid-orchestrator / P057 / E-057-1_2
**AID version:** v2.51.0+
**Observed at:** 2026-07-08
**Status:** confirmed (resolved safely same day)
**Severity:** medium
**Class:** branch/worktree safety (shared checkout)

**What happened:** E-057-1 steps 1+2 landed TWICE with different SHAs: on main
(46b4f3c/616c1ed) and on task/E-057-1_2/main (d5fdf34/8950bb2, same messages,
task branch still based on old ac0f287). main carried unreviewed mid-EPIC
production commits before the EPIC's CP3/gates ran, and a merge conflict was
pre-programmed. Likely cause: a shared-checkout session committed on main,
work then recreated on the task branch (or vice versa).

**Recovery (positive pattern):** merge commit `16261b2` brought main INTO the
task branch with explicit C3-registry reconciliation and a documented
rationale ("direct merge would have silently dropped P058's work from
history"). Both lineages preserved, zero work loss; final merge to main
(`b1b1ab7`) clean. Pin this as the duplicate-lineage recovery pattern.

**Likely fix:** same family as the observer-commit discipline lesson — the
shared checkout needs a guard: warn/refuse commits to main while an FSM run
owns the checkout (task branch expected), or run EPICs in dedicated worktrees.

### OBS-20260708-02 - Version skew: release advance retroactively demands new-plugin artifacts from old-plugin runs

**Observed in:** WAN / P058 plan-close (all 6 EPICs)
**AID version:** runs v2.50.1, machinery v2.51.0+
**Observed at:** 2026-07-08
**Status:** confirmed
**Severity:** medium
**Class:** checkpoint ownership / upgrade migration

**What happened:** At the first-ever plan-close, `done-advance review→release`
FAILED on ALL 6 P058 EPICs (`review_profile_missing_lenses` +
`fsm_done_advance_fail`, 4 errors each): the runs were executed under
v2.50.1-era expectations, but the release advance was evaluated by newer
machinery demanding review-profile/audit artifacts the old runs never
produced. The merge proceeded via documented --no-verify (#11) with "release
advance follows"; remediation then backfilled audit-report artifacts into run
dirs and re-ran the advances (all 6 eventually reached release, E2 verified
passing compliance after backfill — enforcement→backfill→retry worked).

**Why it matters:** every project that upgrades the plugin mid-plan will hit
fail+bypass at its next release advance. Retroactive preconditions need a
migration/grandfather policy (era-stamped runs, or a documented backfill
command) instead of ad-hoc bypass.

**First plan-close outcome (ledger):** merge message disclosure was EXEMPLARY
(auditor score, plan AC 13/13, conflicts enumerated — all 8 were AID
bookkeeping files, production code conflict-free byte-verified, per-EPIC
scores, delivery report path) — pin as merge-message template. The 4 untracked
FE commits (OBS-20260705-03) merged to main with zero checkpoint coverage,
unmentioned.

### Probe update 2026-07-08 — recurrences, escalations, remedies

- **OBS-11 ESCALATED to high:** WAN E-060-1 — step index 1's prefilter stub
  OVERWROTE verifier-output-step-1.md holding the first step's 1-based
  verifier output (survived only as the 0-based copy). First actual evidence
  overwrite caused by the numbering duality. Also: hand-copied evidence files
  carry unreliable metadata (future timestamp seen).
- **OBS-05 + OBS-08 now in a THIRD project:** VULCAN P56 E-56-1_2 contract has
  outputs 15×7 identical + phantom docs_updated (execution.yaml lacks it).
  Root cause: **plugin rollout gap** — v2.51.0 fixes are released but consumer
  projects (WAN, VULCAN) still run the old plugin. Cleanup must include the
  plugin-update rollout step (CLAUDE.md procedure) across all consumer
  projects, else upstream fixes never reach the fleet.
- **OBS-20260705-01 (prefilter diff-range):** recurrence #2 on WAN E-058-6 was
  recorded (2fdc192); on E-060 the prefilter behaved correctly when steps'
  last commits were the feature commits — the failure mode is specifically
  bookkeeping-commit-on-top.
- **Security fail-open in new C3 hook: found and fixed within the run** —
  automated security review flagged HIGH fail-open (unreadable c3-audit-policy
  → empty required flag → high-risk profile skipped the audit); relayed via
  observer; fixed same day (`8e919d8` fail-closed policy-path resolution, then
  `b2e4672`/`aaa5de6` set -e guards, `48dc54e` schema wiring). Meta-pattern
  instance ("control dissolves into silence on config-read failure") caught
  BEFORE merge this time.
- **E-057-1_2 released** (`b1b1ab7` on main): C3 independent-audit shipped,
  duplicate-lineage recovered safely, full evidence pack persisted incl.
  compliance.json; first C3 done-advance fired on its own EPIC.

### Probe update 2026-07-08 (afternoon flush — E-057-2 run + VULCAN/WAN watches)

- **OBS-20260708-02 refinement — producer/consumer gap within ONE plugin
  version:** WAN E-060-1 (FRESH run under current plugin) also hit
  `review_profile_missing_lenses` + `fsm_done_advance_fail` (09:43Z). The
  failure is NOT only old-runs-vs-new-machinery: the done-advance consumer
  demands `review-profile.json` that the same plugin's run machinery never
  produces. Producer must be wired, or the check made era/capability-aware.
  See OBS-20260708-03 for the deeper consumer-side fail-open.
  **Recurrence #3 (VULCAN, 2026-07-08 12:57-12:58Z):** E-56-1_2 done-advance —
  `review_profile_missing_lenses: unverifiable` fired, first advance attempt
  FAILED (errors: 1), retry 8s later passed (after
  `fsm_done_advance_recovered: verifier_provenance`). All three probe projects
  now hit the same missing-producer wall at release advance. Bonus circular
  check observed: dg07 reports "compliance.json overall=fail (delivery gate
  cannot proceed)" while compliance.json is only written BY the successful
  advance itself — chicken-and-egg in observe mode.
- **OBS-01/OBS-11 family instance #4 (record/reality drift, inverse):**
  E-057-2 branch was re-pointed onto fresh main (merge-base `89d30ee`) but
  fsm-state `base_commit` stayed `ac0f287` (pre-release era) — state NOT
  updated when git reality moved, no event. No false-green: CP3 verifier
  computed the actual base and stated the range explicitly ("89d30ee..HEAD"),
  and delivery-gate.json independently used `base_sha: 89d30ee` — two
  consumers compensating for stale state by agent/tool discipline.
  **Instance #5 (VULCAN E-56-2_2, 13:07Z):** branch correctly re-pointed onto
  merge `e29449a` (contains Phase 1), but fsm-state `base_commit` still holds
  init-time `9200e97` (pre-merge) — same record/reality drift, no event.
  Also: first branch commit is AGAIN a manual execution.yaml↔AC gate sync
  (`087f63d`, same as E-56-1's `32c2682`) — the OBS-20260708-06(b) old-plugin
  startup tax repeats on every VULCAN EPIC.
- **plan_diff silent-skip recurrence on fresh v2.52 run:** E-057-2
  plan-diff.json has `plan_path: None`, `ac_count: 0`, gate result `skip`
  exit 2 under `overall: pass` — the plan_path-null no-op family replays on
  the newest plugin (execution.yaml note declares it advisory for AID
  self-host; still a declared-but-validating-nothing gate).
- **Positives to pin (calibration):** (a) E-057-2 CP3 was a 3-round
  adversarial fix-loop — 2× FAIL(HIGH) with real-fixture reproduction
  (`55808d6`, `145d04e` fail-closed fixes), round 3 exhaustive pass 240/240;
  strongest CP3 observed. (b) curator-report.json dual-emit (run + EPIC dir,
  identical) with honest `verdict: {kind: none, ready: false}` while its C3
  input was missing — no fake pass. (c) VULCAN E-56-1 re-ran gates fresh
  after a 3h pause (and again pre-merge) instead of reusing a stale report;
  CP3/CP4 artifacts at canonical names in a third project. (d) E-057-2
  final_report.md disclosed advisory fails, the smoke timeout, and
  pre-existing failures honestly (PM-communication done right).

### OBS-20260708-03 - C3 audit gate never fires: absent review-profile.json silently resolves to "C3 not required"

**Observed in:** aid-orchestrator / P057 / E-057-2_2 / R-E057-2 (+ WAN, VULCAN)
**AID version:** v2.52.0 (current)
**Observed at:** 2026-07-08
**Status:** confirmed
**Severity:** high
**Class:** false-green prevention / checkpoint ownership

**What happened:** The C3 independent-audit gate that P057 exists to deliver
has never fired for a real EPIC. AID's own E-057-2 audit (audit-report.md,
health 92/100) found and evidenced it: `review-profile.json` exists in 1 of
289 evidence run dirs, and `aid-fsm.sh`'s C3 risk-profile resolution has no
else-branch for "file totally absent" — it silently resolves to "C3 not
required", contradicting `skills/pipeline.md`'s documented default (absent →
`unverifiable` → C3 REQUIRED). Live demonstration in the same run: E-057-2's
own done-advance emitted `review_profile_missing_lenses: unverifiable`
(observe) at 12:56:44Z, `audit-report.json` was never emitted (only .md), the
brand-new Curator content-ref guard had nothing to hold (honest
`ready: false` but C3-not-required → no-op), and the advance proceeded to
release. Same silent-no-op-on-absence bug class the CP3 fix-loop fixed for
the Curator guard one layer down — missed by both CP3 reviewers, caught by
the audit.

**Why it matters:** the flagship control of the last two plans is decoration
in practice (Principle #1); every risk-gated hook keyed on risk_profile
inherits the fail-open.
**Reproduction:** audit-report.md in E-057-2_2/R-E057-2 (section "one
significant, evidence-backed gap"); timeline 12:56:44Z; `ls **/review-profile.json`.
**Likely fix:** else-branch: absent file → `unverifiable` (fail-closed, per
documented default) + wire a producer for review-profile.json into the run
pipeline; migration policy for the 288 legacy dirs.

### OBS-20260708-04 - fsm-state steps[].status born "pending", never updated — read-model decoration (VULCAN B-142)

**Observed in:** VULCAN E-56-1_2 + E-055-2_2 audits; verified in plugin source
**AID version:** all since P040 Component E (incl. v2.52.0)
**Observed at:** 2026-07-08
**Status:** confirmed
**Severity:** medium
**Class:** evidence integrity / GUI read-model

**What happened:** `fsm_init` writes `steps[]` with `status: pending`,
`started_at/completed_at: null` (aid-fsm.sh ~1839-1848) declared "single
source of truth", but no code path ever updates them — increment only seds
`current_step` (~2348). VULCAN's audit hit it twice (E-055-2 F1 2026-06-29,
E-56-1 2026-07-08, escalated as their B-142): DONE epic shows 7× pending.

**Why it matters:** write-once decoration masquerading as state; any Cockpit
read-model shows all-pending on finished runs.
**Likely fix:** increment/verify path writes `steps[N].status: completed` +
`completed_at` and emits a timeline event (rule: every fsm-state mutation is
evented).

### OBS-20260708-05 - Permanently-failing advisory gate: shell_pipeline_smoke times out every EPIC under overall:pass

**Observed in:** aid-orchestrator / P057 (E-057-2 and, per its final report, every prior EPIC of the plan)
**AID version:** v2.52.0
**Observed at:** 2026-07-08
**Status:** confirmed
**Severity:** low
**Class:** false-green prevention / performance-cost

**What happened:** `shell_pipeline_smoke` fails exit 124 (300s timeout ceiling)
on every EPIC of the plan; `required: false` keeps `overall: pass`.
final_report.md admits "same as every prior EPIC in this plan". A gate that
fails identically on every run provides zero signal and burns 5 min per gate
run — dead decoration.

**Why it matters:** advisory-fail wallpaper trains everyone to ignore gate
fails; timeout class hides real hangs.
**Likely fix:** raise ceiling or shrink smoke scope; add rule "advisory gate
failing N consecutive runs must be surfaced to PM as a defect".

### OBS-20260708-06 - VULCAN startup friction: ~1h lost before first step, invisible in timeline

**Observed in:** VULCAN / P56 / E-56-1_2 + E-56-2_2 init (2026-07-08 morning)
**AID version:** old plugin (pre-v2.51 consumer) + current generators
**Observed at:** 2026-07-08
**Status:** confirmed
**Severity:** medium
**Class:** UX indexing / docs drift / observability

**What happened:** PM-reported lost hour is on disk as: (a)
`fsm_branch_mismatch_detected` on E-56-2 init 07:57 — sequential multi-EPIC
generation in one checkout fights the per-EPIC branch preflight (each init
expects its own branch checked out); (b) old-plugin malformed contract
(OBS-08) + phantom docs_updated gate (OBS-05) forced the implementer's FIRST
commit to be a manual execution.yaml↔AC sync (`32c2682`) before any step
work; (c) increment-before-evidence + duplicate prefilter (known classes);
(d) META: 43+43-min silent gaps between init→EXECUTE→first activity with only
6 timeline events total — the worst friction is invisible because preflight
failures/retries are not evented.

**Why it matters:** startup friction is where consumer projects bleed time,
and the timeline can't even show it.
**Likely fix:** epic-gen init must not require branch checkout (defer to
EXECUTE start); event all preflight failures/retries; plugin rollout step.

## B-004 — Live usage probe for AID v2 control-system friction

**Status:** scoped
**Area:** AID Control System v2 operations / verification
**Nalezeno:** 2026-07-01, field report from real AID v2.50.1 usage during a multi-EPIC plan run

**Summary:** Run a temporary live probe in a second observer session while another
agent uses the latest AID on real work. The probe records concrete control-system
friction before starting a broader cleanup/refactor.

**Kontext:** Several issues surfaced only during real usage: ambiguous checkpoint
commands, evidence overwrite risk, undocumented required fields, 0-index/1-index
step confusion, and CP3 review range fallback. These are AID-system findings, not
project-specific implementation findings.

**Navrhovaná změna:** Use `docs/AID-control-system-v2-live-probe.md` as the
operating mode for the next several EPICs/plans. Store each observation with date,
AID version, source, severity, reproduction, and likely fix. After enough evidence,
open a dedicated AID cleanup/refactor plan instead of patching every symptom
immediately.

**Open questions:** How many EPICs are enough before cleanup? Suggested threshold:
at least 2 independent EPICs or any one confirmed evidence-corruption path.

---

## B-005 — CP3 prefilter command can overwrite CP2 verifier evidence

**Status:** ready
**Area:** `plugins/aid-orchestrator/scripts/aid-prefilter.sh`
**Nalezeno:** 2026-07-01, live AID v2.50.1 field report; confirmed by code inspection

**Summary:** `aid-prefilter.sh classify --checkpoint cp3` is a supported command
surface, but it writes to `verifier-output-step-N.md`, the same file used by CP2.
This can overwrite a valid per-step verifier output with a pending stub.

**Kontext:** CP3 documentation expects dedicated files:
`verifier-output-cp3-code-review.md` and `verifier-output-cp3-security.md`.
The current CP3 prefilter command does not write those files and does not fit the
documented CP3 flow.

**Navrhovaná změna:** Either remove/disable `--checkpoint cp3` from `classify`, or
change CP3 prefilter to write only CP3-specific evidence files. Add a regression test:
running CP3 prefilter must not modify an existing `verifier-output-step-N.md`.

**Open questions:** Should CP3 have any prefilter at all? Current pipeline says CP3
always dispatches code-review + security; safest short-term fix is to reject
`--checkpoint cp3` with a clear message.

---

## B-006 — DONE merge policy is ambiguous: per-EPIC release vs per-Plan closure

**Status:** scoped
**Area:** `plugins/aid-orchestrator/skills/pipeline.md`, FSM plan-close semantics
**Nalezeno:** 2026-07-01, live AID v2.50.1 field report; confirmed by docs/script review

**Summary:** `pipeline.md` contains two competing models: the newer
"dispatch per EPIC, validate per Plan" section and the older per-EPIC DONE Closure
Checklist with MERGE/release. Scripts enforce a plan-boundary `ca-review-complete`
gate for cross-plan starts, but do not cleanly state whether intermediate EPICs
should merge.

**Kontext:** This causes PM ambiguity on multi-EPIC plans: should each EPIC merge
after Curator/Auditor, or should branches stay open until the entire plan finishes?
Keeping many EPIC branches unmerged increases stale evidence and merge conflict risk.

**Navrhovaná změna:** Make the policy explicit:
`release/merge per EPIC, closure/reporting per Plan`.
Update `pipeline.md`, DONE summaries, and any prompt text so agents stop asking this
as an architectural decision during every multi-EPIC plan.

**Open questions:** Are there plan types where per-Plan merge is still required?
If yes, make it an explicit plan flag rather than the default interpretation.

---

## B-007 — Step numbering UX: FSM is 0-indexed while plans are 1-indexed

**Status:** idea
**Area:** FSM output, evidence naming, pipeline instructions
**Nalezeno:** 2026-07-01, live AID v2.50.1 field report

**Summary:** `fsm-state.yaml.current_step` and evidence files such as
`step-0-verify.md` are 0-indexed, while plans are presented to humans as Step 1..N.
Agents can easily dispatch or verify the wrong step.

**Kontext:** The field report described repeated mistakes caused by this mismatch.
The internal index can stay 0-based, but every human/LLM-facing output should show
the mapped plan step.

**Navrhovaná změna:** Add helper wording everywhere the FSM prints or instructs a
step number: `current_step=0 (Plan Step 1)`. Consider evidence aliases or report
labels that include both forms.

**Open questions:** Should evidence file names remain 0-indexed for compatibility,
or should new files adopt plan-step labels while preserving old reads?

---

## B-008 — CP3 base_commit fallback can silently widen/narrow review scope

**Status:** ready
**Area:** `plugins/aid-orchestrator/scripts/aid-prefilter.sh`, CP3 review range handling
**Nalezeno:** 2026-07-01, live AID v2.50.1 field report; confirmed by code inspection

**Summary:** CP3 range resolution falls back to `git merge-base HEAD origin/main`
or `HEAD~5` when it cannot read the run `base_commit`. That can silently include
unrelated commits or miss relevant ones.

**Kontext:** CP3 is supposed to review the full EPIC diff. A guessed range undermines
the independence and relevance of CP3 review. In live use this created uncertainty
about whether the review covered one extra older commit.

**Navrhovaná změna:** For CP3, require exact `base_commit` from the canonical
`fsm-state.yaml`. If unavailable, return `unverifiable`/hard fail with a clear
recovery command. Do not silently approximate.

**Open questions:** If CP3 prefilter is disabled by B-005, this still applies to any
other CP3 tooling that resolves review range.

---

## B-002 — test-semantic-review.sh hlášen jako 0/0 v run-all-tests.sh agregátoru

**Status:** idea
**Area:** `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh`
**Nalezeno:** post-merge smoke check E-054-1_1 (2026-06-29)

**Summary:** `run-all-tests.sh` reportuje `test-semantic-review` jako 0 testů (0/0), i
když přímý `bash test-semantic-review.sh` vrátí 25/25. Agregátor špatně parsuje výstup
tohoto harnessu.

**Kontext:** `test-semantic-review.sh` vypisuje `=== Results: 25 passed, 0 failed ===`
kdežto ostatní skripty (`test-protocol-validate.sh` apod.) vypisují formát, který
agregátor umí přečíst. Buď se liší regex pattern, nebo je výstupní formát
test-semantic-review mírně jiný.

**Navrhovaná změna:** Sjednotit výstupní formát `test-semantic-review.sh` se zbytkem
(nebo upravit regex v `run-all-tests.sh`) tak, aby agregátor správně zobrazoval 25/25.
S-effort fix, <30 minut.

**Open questions:** Je formát `=== Results: N passed, 0 failed ===` standard,
nebo má být `[PASS] N/N passed, 0 failed`? Raději sjednotit na ten druhý,
protože ten je konzistentní s ostatními suity.

---

## B-003 — test-plan-to-epic 2/24 pre-existing failures kazí důvěru ve full suite

**Status:** ready
**Area:** `plugins/aid-orchestrator/scripts/tests/test-plan-to-epic.sh`
**Nalezeno:** Reportováno z E-054-1_1 REOPEN iterací jako pre-existing (2026-06-29)

**Summary:** `test-plan-to-epic.sh` má 2 trvale selhávající testy:
- `remap plan phase 2 exits with code 0 -- got exit code 1`
- `self-dep plan phase 2 exits with code 0 -- got exit code 1`

Tyto dva selhávají od v2.28.x (poslední změna souboru: commit ze `c2e9549`, v2.38.0).
Kazí full `run-all-tests.sh` výsledek a snižují důvěru v CI suite jako celek —
nelze jednoduše zkontrolovat "prošlo všechno" když je tam trvalý červený výsledek.

**Navrhovaná změna:** Prošetřit, proč `remap plan phase 2` a `self-dep plan phase 2`
vracejí exit 1 místo 0. Buď:
a) opravit `aid-plan-to-epic.sh` (pokud je to skutečný bug), nebo
b) opravit testovací fixture/očekávání (pokud se sémantika legitimně změnila a
   testy nebyly updatovány), nebo
c) odebrat testy, pokud testovaný scénář byl záměrně opuštěn.

Kandidát na standalone malý EPIC. M-effort (remap/self-dep scénáře mohou být
netriviální), ale izolovaný od ostatní práce.

---

## B-001 — Autonomous validator-assisted section review

**Status:** scoped → P039 (`.aid-o/plans/P039-section-validation.md`, 2026-05-31)
**Area:** `skills/brainstorming.md` → Step 5 (Design Validation Protocol, lines ~265-276)

**Summary:** Make section-by-section brainstorming review more autonomous — the AI
self-validates each section with a second model before bringing it to the PM, so the
PM confirms a consolidated verdict instead of reading and judging raw sections.

**Current behavior:** In Step 5 the author model presents each design section one at a
time and the PM reads the full section, then approves / modifies / skips. All the
review judgment sits with the PM.

**Proposed change:** Insert a self-validation step between "write section" and "PM
approval":

1. AI writes the section.
2. AI validates it with a *different model* (independent validator subagent) — checks
   for gaps, inconsistencies, weak assumptions, missed dependencies.
3. PM receives only a consolidated message per section, in this shape:
   - **Section N is:** `<what the section says, condensed>`
   - **Validator returned:** `<validator's findings / critique>` **and recommends:** `<recommendation>`
   - **I agree / disagree** + **reason why** `<author model's stance on the validator's recommendation>`
4. The PM confirms (or overrides) this consolidated verdict — that is the only thing
   the PM approves per section.

**Why it matters:** Shifts the PM from "read everything and decide" to "review a
pre-vetted verdict and confirm" — less PM attention per section (PM attention is the
documented bottleneck, brainstorming.md principle #5), while keeping a human approval
gate on every section.

**Open questions / design constraints:**
- **Which validator model?** Cross-model (e.g. author Opus → validator Sonnet, or vice
  versa) vs. same model in a fresh adversarial context. Cross-model gives genuine
  independence; decide at design time.
- **Enforcement (AID-v3-principles.md #1 — "Detector without Enforcement is
  Decoration"):** the validator is effectively a detector. Specify the enforcement
  mechanism — does a validator "disagree" verdict block auto-advance until PM rules on
  it, or is it advisory only? Must be decided at design time, not "later".
- **Per-section vs. batch:** confirm one section at a time (current protocol) vs.
  validate-all-then-present. Per-section preserves dependency flagging (RULE 5).
- **Cost / latency:** a second model call per section adds tokens + wall-clock — worth
  it when sections are substantial, possibly skippable for trivial ones.
- **Disagreement handling:** when author and validator disagree, the PM message must
  make the conflict explicit so the PM can adjudicate, not rubber-stamp.
- **Audit trail:** capture validator output in the evidence/timeline trail per AID
  evidence conventions.

---

---

## P041 Wave 2 — deferred follow-ups (2026-06-04, after v2.28.0 shipped)

P041 audit Waves 1+2 are DONE and released as **v2.28.0** (pushed, tagged, GH release,
plugin cache refreshed). These are the conscious leftovers — see
`docs/plans/AID-audit-2026-06/STATE-session2.md` + `10-fix-plan.md` for full context.

**Big (PM-gated, not started):**
- **MEM-AUDIT** — does the memory subsystem actually get READ by agents (suspicion: written but not used)?
  Absorbs fix-plan **G1** (migrate `qdrant-brain` → `vulcan-memory`, config-driven, `[~]`) +
  **I3** un-sourced memory threshold (`[~]`) + integrations.yaml memory knobs (E154 min_score, E155
  phantom dedup/merge fields). Gates whether vulcan-memory is a viable reflection sink.
- **REFLECT-WIRE** — wire automatic post-EPIC reflection (AID-post-plan-reflection-prompt.md):
  curator slice → local reflection.md + opt-in central .md digest (integrations.yaml
  `reflection.central_digest_path`) + opt-in vulcan-memory push (pending MEM-AUDIT). Enforce via
  FSM done-advance + plan-level gate, NOT auditor. Manual prompt + PM's output file stay AS-IS.
- **SKILL-RETROFIT** — bring the 9 grandfathered skills up to the skill-writing standard (0/9 have
  the line-2 header date; 7/9 lack `## MUST Rules`; 8/9 lack `## Completeness Gate`; agent-protocol +
  pipeline have version-stamped headings). The I1 guard grandfathers them now; retrofit removes them
  from the GRANDFATHERED list in `scripts/tests/test-skill-lint.sh` one at a time.

**Small (consciously skipped/deferred during I2 deep coverage):**
- **E171** — parallel-group file-conflict serialization guard. Moot while `orchestration.yaml
  max_parallel: 1` (parallelism off); prerequisite to re-enabling parallel dispatch (Agent SDK migration).
- **~7 low-value doc GAPs** — script guards that work but aren't pre-documented in LLM-facing
  instructions: E91 (silent malformed-row drop), E106 (atomic write), E107 (detached-HEAD guard),
  E108 (filename truncation), E113 (git/jq preflight), E124 (yq-injection escaping), E126 (yq/write
  guards). Optional one-paragraph addendum in pipeline.md §2; low value.
- **execution.yaml `config` non-role** — the `content_quality.auto_accept_when` list references a
  role `config` that exists in no role enum; the auto_accept/review_required role lists are also
  partial (omit domain/observability/qa/e2e). Latent; needs intent before fixing.

## CI / test-suite follow-ups (2026-06-04, after v2.28.1 shipped)

Surfaced while fixing the red CI build (red on every push since 2026-05-31). v2.28.1 fixed the
`transition --force` crash + wired bats into CI + repaired the 4 stale suites + added one red/green
precondition test. Remaining, deferred:

- **PRECOND-COVERAGE** — deeper precondition-layer tests (the anti-AID-005 gates_report
  `_generated_by` check, CP3 verifier-output checks). v2.28.1 added only the cheap READY→EXECUTE
  plan.json red/green pair. The heavier EXECUTE→GATES / GATES→DONE green paths need real fixtures
  (gates_report.json with `_generated_by`, both CP3 verifier-output md files, grandfather handling).
  Both review verifiers flagged that without these the gates pojistka could be weakened unnoticed.
- **run-all-tests counter off-by-one** — `run-all-tests.sh` reports `Tests: 181/180 passed` (passed >
  total). Cosmetic accounting bug in the bats TAP skip/plan handling (`ok … # skip` is first matched
  as a plain `ok`, and one suite's plan line double-counts). `0 failed` is correct; only the tally is
  off. Fix the parser, don't trust the headline count.
- **GitHub Actions Node 20 → 24** — `actions/checkout@v4` + `actions/setup-node@v4` run on Node 20,
  which GitHub force-migrates to Node 24 on 2026-06-16 (~12 days out) and removes 2026-09-16. Bump to
  the @v5 actions (or pin FORCE_JAVASCRIPT_ACTIONS_TO_NODE24) before then. Currently warnings only.

## E6 Deferred (P055 honest-minimal)

- **DG-13 Reachability Analysis** — Requires AST/runtime tooling to reliably detect unreachable routes; heuristic grep approach rejected (false-positive risk). Deferred to AST tooling foundation phase.
- **DG-14 Wire Shape** — Deterministic cross-layer type contract verification requires AST; deferred.
- **DG-16 Fallback Invocation** — Call-graph analysis needed to verify fallback retry/reconnect coverage; deferred.
- **Living Contract Enforcement** — map_drift + C0 preflight + delivery_areas substrate; requires dedicated delivery-map schema/setup phase before enforcement can be meaningful.
- **aid-init delivery-map proposal** — Auto-generate skeleton delivery-map.yaml during `/aid-init`; deferred pending living-contract design.

## E8 Deferred (P057 E8 core — recorded 2026-07-01, do NOT forget)

E8 (P057) is deliberately **C3 audit core**, not a full external audit + auto-rerun system.
The following are explicitly deferred out of P057 and MUST be picked up later:

- **Curator merge-authority removal** → **E9/C4** (release-policy territory, FC-38). E8 only does
  Curator *sequencing* (after C3) + *vocabulary* (PROPOSALS_READY/NO_PROPOSALS/INPUT_INCOMPLETE).
  The real auto-approve `recommended_disposition` merge-influence is a shared contract consumed by
  gate-fixer.md:48/180 + simplifier.md:100 + pipeline.md:918 — removing it before C4 exists would
  break the auto-apply pipeline. Replace/remove it only when C4 release-policy provides the substitute.
- **Full `codex exec` adapter** → follow-up. E8 delivers only Codex *capability detection* +
  graceful degrade to `unverifiable`. The actual subprocess dispatch (codex exec, output-schema
  parsing, merge into audit-report.json) is net-new infra deferred. cross_provider audit stays
  "detected → unverifiable until dispatch is wired".
- **Codex `auth` detection mechanism** → research + follow-up. Every design doc says "auth OK" as a
  detection factor but none specify the actual check (no codex login-status mechanism exists in-repo).
  E8 treats un-confirmable auth as → unverifiable (fail-closed), and flags the concrete auth probe as TBD.
- **Automatic selective C1/C2 re-run orchestration** → follow-up. E8 delivers `invalidation-map.json`
  as an **observe** artifact (deterministic C1 subset + registry row + timeline event) only. It does
  NOT re-invoke C1/C2. Auto re-run orchestration (a new FSM/pipeline primitive) is deferred.
- **Precise C2-mode affectedness derivation** → follow-up. C2 modes (wiring/behavior/final) are
  triggered by plan-graph assembly position, not by file path — there is no path→mode substrate.
  E8 marks C2 affectedness *conservatively* (any change touching a C2 evidence surface → all relevant
  C2 modes affected). Fine-grained per-mode derivation is deferred (do not pretend path-based C2 derivation).
- **C4 consumption of audit-report/curator/invalidation** into release-decision → **E9**.
- **Large legacy A-J project-health audit cleanup / separation** → later. E8 keeps A-J as a legacy
  compat section on the converted auditor; a proper split into a standalone project-health tool is deferred.

## GENERATOR / CONTRACT-VALIDATION gap (found P057/E8 manual inspection, 2026-07-02)

**Class:** false-green — plan passes C0/CP1 but the GENERATED executable EPIC contract is malformed.
**Severity:** high (affects every EPIC generation; degrades per-step contracts silently).

The plan→EPIC.md→plan.json pipeline (`aid-plan-to-epic.sh` + `aid-epic-to-json.sh`) produces malformed
executable contracts that the review gates do NOT catch:
- **Step-scoping collapse:** outputs/acceptance_criteria/allowed_paths are aggregated at EPIC level and
  copied to EVERY step (per-step scoping only exists for role/objective/depends/parallel). Result: each
  step claims all files + all ACs → "what did THIS step deliver" is meaningless. (E-057-1_2: every step
  has all 8 outputs+13 AC; E-057-2_2: every step all 13 outputs.)
- **AC split on `|`:** `aid-epic-to-json.sh` splits an AC line on the pipe char → a single jq expression
  (`jq '...enum | length == 3'`) becomes two bogus ACs (plan.json:57/58, 62). Any AC containing `|`
  (jq pipes, enum alternations) is corrupted.
- **Prose in allowed_paths:** `aid-plan-to-epic.sh` doesn't extract just the path from
  "Create: `path` — description"; whole prose lines land in allowed_paths ("CHANGELOG + version 2.51.0…").
- **No inter-step deps:** step table depends column is always `---`; real Step N→Step M deps lost.
- **META (the important one):** C0 `plan-review.json` = status:pass, `lens_dispatch_observed: 0/5`,
  no findings — the gates review the PLAN, nothing validates the generated plan.json/task contract.

**Fix candidates:** (1) per-step scoping in the generator (parse each step's Files/AC sub-section, assign
to the right step object); (2) stop splitting ACs on `|` (use a safe delimiter / preserve verification_pattern
blocks verbatim); (3) extract clean path from Files entries (strip "Verb:" prefix + "— description"/"(note)");
(4) derive step deps; (5) **NEW GATE: validate the generated plan.json contract** (per-step scoping sane,
allowed_paths are real paths, ACs well-formed) so malformed generation fails a gate instead of reaching /aid-run.
NB: E1-E8 EPICs likely all had degraded per-step contracts (ran anyway because implementer works holistically).

## PLAN-DIFF heading drift (found P058 CP1-deep L3, 2026-07-02)

**Class:** false-green — `aid-plan-diff.sh` reports skip→pass while the plan's verification_pattern ACs are never run.
**Severity:** high (systemic across P049-P058).

`aid-plan-diff.sh:131` parses only `/^## Acceptance Criteria/` for verification_pattern AC blocks, but the plan
template + every recent plan (P052-P058 confirmed: `## Success Criteria`=1, `## Acceptance Criteria` heading=0)
put their AC1..N + `verification_pattern` blocks under **`## Success Criteria`**. Result: `aid-plan-diff` finds
`ac_count:0` → graceful skip (exit 2) → the plan_diff gate's pass_criteria treats skip as PASS → **the
verification_pattern ACs of every one of these plans were never executed by plan-diff** (decorative at that gate).

**P058 fixes the parser** (`:131` → `/^## (Acceptance Criteria|Success Criteria)/`) so it retroactively runs for
all existing plans. **Remaining backlog:** decide the canonical heading (align the plan template + plan-writing
skill to ONE of `## Acceptance Criteria` / `## Success Criteria`), and audit whether the per-step
`**Acceptance Criteria:**` checklists (which DO flow to plan.json via aid-plan-to-epic) vs the plan-level
`## Success Criteria` verification_patterns are both meant to be enforced and by which gate. Also: aid-plan-diff
skip-as-pass should arguably be distinguishable from real pass in gate evidence (a skip on a plan that HAS ACs is
a bug, not a legitimate Fast-Mode skip).

## STALE PLUGIN CACHE for agent instructions (external auditor, 2026-07-08)

**Cross-ref: IMP-179** (`.aid-o/work/backlog.md`) — the DEEPER layer of the same failure class: subagent
system prompts do not pick up `agents/*.md` changes within the same session (dogfood-proven on
E-057-2_2 Curator dispatch). This section = marketplace-cache layer; IMP-179 = session/dispatch layer.
BOTH must be resolved before E10/E11 promotion (anchored in roadmap E10 "Tvrdé preconditions").

**Class:** instruction drift — dispatched agents (Auditor/Curator/…) may read agent .md instructions from
the marketplace plugin CACHE (`~/.claude/plugins/marketplaces/claude-aid-o/...` per `.aid-o/config/plugin.yaml`
`plugin_path`), not from the repo working tree. After in-repo changes (e.g. E8's auditor.md C3 conversion,
curator.md sequencing), agents can silently run with OUTDATED instructions until `claude plugin update` /
force-refresh runs (same trap class as P058 Step 5 working-tree-vs-cache regen finding).

**Priority: HIGH. Does NOT block E057 merge / interim phases. DOES block the hard cutover (E10/E11)** —
promotion to blocking must not happen while instruction delivery is potentially stale. Fix candidates:
(a) pipeline preflight comparing cache vs repo plugin version/hash → warn/fail on drift; (b) documented
mandatory refresh step in release workflow (exists in CLAUDE.md but unenforced); (c) dispatch agents from
working-tree paths within this repo. Decide in E10 cutover plan at the latest.

### Contract-validate gate gap: path-like ≠ real repo path (PM, 2026-07-08, E-059 gen)

`aid-contract-validate.sh` allowed_paths_shape check only rejects prose-shaped entries (` + `, `(`,
trailing sentence). Bare short fragments like `pm-decision-brief.schema.json` (missing the full
`plugins/.../defaults/schemas/` prefix) PASS as "path-like" — E-059-2 shipped such fragments and the
gate said clean. Enhancement candidate: for `Modify:` entries, verify the path exists in the repo
(Create: targets exempt); or at minimum require a `/` for known-tree files. Same class as P058's
original findings — the gate closed prose, not wrongness.
