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

**Likely fix:** Adopt T-151's direction: (a) a documented post-review-fix path
— PM-approved marker file (`post-review-fix-approved.json` with reason +
timestamp, analogous to `--force --reason`) that the hook honors and logs as a
timeline event, or (b) an `aid-fsm.sh` subcommand for a "reopen fix cycle"
that permits commits in DONE/review without forcing premature release. Either
way the hook must offer a legitimate escape hatch so `--no-verify` stops being
the path of least resistance.

---

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
