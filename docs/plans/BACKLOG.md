# AID Orchestrator — Backlog

Project-internal backlog items. Ecosystem-shared items live in `/opt/eco/BACKLOG.md`.

Format: each item has a status (`idea` / `scoped` / `ready` / `dropped`), a one-line
summary, context, the proposed change, and open questions. Items graduate to a real
plan via `/aid-plan`.

---

## P068 — DONE, released 2026-07-27

**P068 (plan-final release boundary + cutover) is complete and released as
v2.63.0, repaired by v2.63.1.** Both EPICs merged to `main` in a one-time
bootstrap legacy close: P068 built the plan-final path but was itself built on
the old one, so declaring it `plan_branch` would have been a false record.

- Delivered: `plan_branch` as the guarded default, the plan-final gate/review/C4
  sequence against a frozen candidate, the compare-and-swap merge, `plan-close`
  as a real gate, `ROLLED_BACK` for a merged-then-reverted plan, and the
  completion gate on `epic-merge-to-plan`.
- Live-verified by the **P077** dogfood: `release_ready=true` with zero blockers,
  merged, and `CLOSED` with a durable receipt — first attempt, no manual edit to
  any evidence artifact.
- Full dogfood history (P067 halted at C4, P075 merged then rolled back, P076
  invalidated by controller error, P077 clean) is in
  `plugins/aid-orchestrator/reference/P068-plan-branch-dogfood-report.md` and
  archived on branch `archive/P068-dogfood-P067-P077-20260727`.

**The three items below marked "required before P068 enables `plan_branch`" are
satisfied** — IMP-271 (the mechanical `_pfsm_plan_final_installed` probe, whose
refusal lifted only when both commands landed), IMP-272 (`merge_target`
constrained by `_dep_merge_target_authorized`) and IMP-273 (`cmd_init` now asks
the one fail-closed `_fsm_declared_plan_mode` authority). Their entries are kept
below as the record of what was required and why.

### NEW — IMP-280: a dogfood must not share refs with the repository it tests

**Status:** ready — found by the P068 dogfood itself
**Priority:** high
**Class:** test isolation / false-evidence prevention
**Area:** dogfood preflight

**Summary:** The P067/P075/P076/P077 dogfoods ran in a linked `git worktree`,
which shares `.git` and every ref with the source repository — so the "dogfood
checkout's" `main` WAS the real `main`, and every run advanced the repository's
real mainline. The two-checkout topology isolated the *commits* exactly as
designed (no P068 implementation commit ever entered a candidate) but not the
*refs*, which the report had implicitly assumed. Recovery needed an archive
branch and a compare-and-swap restore of `refs/heads/main`.

**Proposed change:** a dogfood preflight that compares
`git rev-parse --git-common-dir` against the source repository's and, on a match,
either refuses the run or requires a namespaced target ref or a genuinely
separate clone. A dogfood that can move the real target branch is not isolated,
however carefully its commits are kept apart.

---

## Improvement items

### IMP-261 - Project-scoped configuration and INIT/SETUP redesign (analysis first)

**Status:** idea — analysis required before implementation
**Priority:** high
**Class:** architecture / configuration / operator UX
**Area:** `/aid-init`, project setup, policy loading, Codex dispatch, gates and lifecycle defaults

**Summary:** AID currently mixes plugin defaults, hard-coded constants, environment
variables, policy YAML and project-local configuration without one explicit precedence
model. Important behavior therefore cannot always be selected durably per project. As a
confirmed example, C0 and C3 normally both run `gpt-5.6-terra`; their model can be
overridden independently through `AID_C0_CODEX_MODEL` and `AID_C3_CODEX_MODEL`, but the
shared Codex transport hard-codes `model_reasoning_effort=high`. The planned Codex
adjudicator does not yet have a separate model/reasoning profile. Similar fixed or
ambiently-configured choices exist elsewhere in review budgets, timeouts, gate profiles,
parallelism, lifecycle behavior and release orchestration.

**Why it matters:** A consumer project should be able to choose, review and reproduce its
AID operating profile without patching the plugin or remembering shell environment
variables. Today two projects using the same plugin version may behave differently because
of hidden environment state, while other behavior cannot be changed at all because it is
compiled into a script. This is especially problematic for self-hosting, automation and
audits: the effective model, reasoning effort, timeout or enforcement profile may not be
obvious from the project's tracked configuration or resulting evidence.

**Confirmed motivating case:**

- C0 model: invocation override `AID_C0_CODEX_MODEL`; otherwise inherits the C3 default.
- C3 model: invocation override `AID_C3_CODEX_MODEL`; default `gpt-5.6-terra`.
- C0 and C3 reasoning: shared transport currently hard-codes `high`, with no per-action
  project setting.
- Desired initial profiles: C0 plan review = `gpt-5.6-sol` / `medium`; C3 implementation
  audit = `gpt-5.6-terra` / `high`; Codex auto-mode adjudication =
  `gpt-5.6-sol` / `medium`.
- The actually resolved model and reasoning must be written to evidence for every dispatch.

**Required analysis before planning implementation:**

1. Inventory every behavior-affecting constant and override across commands, scripts,
   defaults, policies, environment variables and `.aid-o/config`. For each item record:
   current source, default, existing override, consumers, whether it is safe to configure,
   and whether it belongs to project, host/user, invocation or immutable protocol scope.
2. Identify duplicate and conflicting sources of truth, including settings that are
   documented as configurable but are shadowed by a hard-coded CLI argument.
3. Classify settings. Not every constant should become a knob: protocol invariants and
   fail-closed security properties remain immutable; credentials and machine paths remain
   untracked host-local values; operating policy belongs in reviewable project config.
4. Propose a versioned project configuration schema and an explicit precedence chain. A
   candidate chain to validate is: immutable protocol invariant -> plugin default -> tracked
   project profile -> untracked host/user override -> invocation override. The analysis must
   define which layers are allowed for every setting and reject unknown keys.
5. Decide the durable tracked location for project policy. Do not assume that today's
   gitignored `.aid-o/config` is suitable as the sole source of truth; compare a tracked root
   `aid.yaml`/`.aid/config.yaml` with a deliberate tracked subset plus untracked local
   overrides.
6. Inventory what `/aid-init` and the existing setup path currently create, merge, overwrite
   or silently preserve, including re-init and plugin-upgrade behavior.
7. Design migration and compatibility for existing projects that have no new config file or
   rely on current environment variables. Existing behavior must remain an explicit legacy
   default, not an accidental fallback.

**Recommended command model to evaluate:**

- `/aid-setup` owns interactive discovery and configuration. It offers `--analyze` to inspect
  the repository and propose a project profile without mutating it, and `--write` to create
  or update the chosen configuration after validation.
- `/aid-init` remains deterministic, non-interactive and idempotent. It consumes the resolved
  project profile, installs/scaffolds runtime files and prints an effective-configuration
  summary. It must not silently replace explicit project choices on re-init or upgrade.
- `/aid-init --setup` may be a convenience entry that runs setup first, then init, but setup
  and init should remain separately callable and testable. This gives users one easy command
  without mixing analysis/prompts into every automated init.
- Add a read-only `config explain`/`config effective` surface showing each effective value,
  its source layer and whether an invocation override changed it.

**Initial configuration domains to cover:**

- Codex actions: independent C0, C3 and adjudication model, reasoning effort, timeout and
  availability/fallback policy.
- Review and repair loops: attempt budgets, terminal behavior and which outcomes require
  human risk acceptance.
- Gates and tests: named gate profile, test concurrency/batching, per-gate and aggregate
  timeouts, expensive-suite policy and evidence requirements.
- Lifecycle/orchestration: release mode, branch conventions, auto-mode continuation policy,
  dependency behavior and safe self-dogfood/cache-preflight policy.
- Execution resources: agent concurrency and other project-wide resource ceilings, while
  keeping credentials, account limits and machine-specific paths out of tracked policy.

**Safety and UX constraints:**

- Configuration must not turn a security invariant into a silent fail-open switch. Any
  configurable enforcement reduction must be explicit in effective config and evidence, and
  risk-acceptance decisions remain separately auditable.
- Missing, malformed or unknown configuration must produce a precise diagnostic. Define
  fail-closed versus backward-compatible fallback per field; do not use one blanket rule.
- Model/reasoning selection must be action-specific rather than one global model for all
  Codex work.
- Environment variables remain useful for CI and one-off runs, but must not be the only
  durable project configuration surface.
- INIT/SETUP must be safe to repeat and must show a diff before overwriting tracked project
  configuration.

**Analysis deliverable:** A standalone design/inventory document under `docs/plans/` that
contains the full setting matrix, proposed schema, precedence rules, INIT/SETUP state
transitions, migration plan, security classification and an implementation breakdown. It
must be independently reviewed against the real call sites before `/aid-plan` turns it into
EPICs.

**Candidate acceptance criteria for the later implementation:**

- A project can durably select different model and reasoning profiles for C0, C3 and Codex
  adjudication without editing plugin source.
- A clean init, re-init and plugin upgrade resolve the same effective configuration unless an
  explicit project change is made.
- `config effective` identifies the winning value and source for every supported setting.
- Every Codex evidence artifact records the resolved action profile, concrete model and
  reasoning effort.
- Tests prove precedence, unknown-key rejection, legacy migration, re-init preservation and
  immutable-invariant protection.
- A repository check prevents newly introduced behavior-affecting hard-coded values from
  bypassing the configuration registry without an explicit immutable-constant annotation.

**Open questions:**

- Which project configuration path should be tracked and public-safe?
- Should INIT automatically accept analysis recommendations, or require an explicit
  `--write`/confirmation step outside non-interactive AUTO mode?
- Which current environment variables remain supported aliases, and for how many releases?
- Should resource profiles be a small named preset plus overrides, or fully field-by-field?

### IMP-262 - Controller-owned background job supervisor and AUTO liveness recovery

**Status:** ready — implement manually outside AID after P064, before P068
**Priority:** critical
**Class:** reliability / autonomous execution / process ownership
**Area:** `/aid-run`, pipeline controller, long-running gates and agent dispatch

**Summary:** Replace ad-hoc background execution and notification-based waiting with a small
controller-owned job supervisor. A long-running command must have a durable identity and a
terminal result that a resumed AUTO controller can collect without relying on `tail -f`, an
agent notification or the original shell remaining alive.

**Observed failure:** During E-064-1_2, a completed test process was followed by an orphaned
`tail -f` monitor. The controller treated the absent notification as unfinished work and AUTO
remained idle for hours even though no useful process was running. Other runs lost results when
the controller killed a wrapper while child processes continued. Instructions now forbid those
patterns in v2.60.1, but instruction-only ownership is not sufficient durable recovery.

**Additional recurrence (E-064-1_2 F-2 closure):** An implementer claimed red-green coverage in
its commit message but returned while the proof command was only "in flight" and supplied no
terminal artifact. The controller correctly rejected the claim and independently reproduced the
five selected tests against the pre-fix and post-fix revisions. Three defect tests failed only on
the pre-fix tree while two positive controls passed on both, which is the required polarity. A
started command, agent assertion or commit message is never test evidence.

**Required implementation:**

- Add a small `aid-job-run`/`aid-job-status`/`aid-job-collect` surface, preferably one script
  with subcommands, that starts the command in an identifiable process group and atomically
  writes a job record under `.aid-o/work/jobs/`.
- Record job id, PID and process-start identity, command fingerprint, log/result paths,
  start HEAD and relevant tree hash, start time, expected p95, hard deadline, owner run/EPIC,
  state and terminal exit code.
- Determine completion from the owned process and exit status. `tail -f`, output growth and
  notification delivery must never be treated as process liveness or completion.
- Make `status` safe against PID reuse and make `collect` idempotent. A controller restart must
  rediscover running work or collect its existing terminal result without relaunching it.
- Add a no-progress watchdog: in AUTO, no live owned job plus no repository/evidence mutation
  for the configured interval triggers automatic resume/diagnosis rather than a PM question.
- Bind a successful result to the recorded command and revision. A tree change marks the result
  stale instead of silently reusing it.
- Distinguish `started`, `running`, `terminal_pass`, `terminal_fail`, `timed_out` and `cancelled`.
  Only a terminal record carrying the exit code and output digest may satisfy an evidence claim;
  an agent returning "in flight" transfers job ownership but proves no test outcome.
- For red-green claims, store separate baseline and fixed receipts: exact revision/tree, selected
  test filter, command fingerprint, expected polarity, observed exit code and pass/fail counts.
  Positive controls that should pass on both sides must be identified separately from defect tests
  expected to fail only on the baseline.
- Integrate only at the controller boundary; this helper enables liveness and must not become a
  new release-blocking ceremony.

**Acceptance criteria:**

- A synthetic hour-long job can outlive and survive replacement of its controller process; a
  resumed controller discovers it and collects exactly one terminal result.
- A job that has already exited is never reported as running because a log watcher still exists.
- Killing the wrapper cannot leave an unowned child process; cancellation targets the recorded
  process group and writes a terminal cancellation result.
- PID reuse, missing result files, timeout and tree drift have explicit tested outcomes.
- AUTO makes progress without PM input after a recoverable controller restart or lost agent
  notification.
- A fabricated pass claim backed only by a commit message or non-terminal `in_flight` job is
  rejected; paired red-green receipts with the expected negative and positive-control polarity are
  accepted.

**Delivery constraint:** Codex implements and verifies this manually outside `/aid-run`; do not
dogfood an unreliable background controller to build its own recovery mechanism. Land after both
P064 EPICs because E-064-2_2 changes gate execution/controller instructions, and before P068 so
the plan-final workflow dogfoods the supervisor.

### IMP-263 - Idempotent increment-step with step-bound evidence binding

**Status:** ready — implement manually outside AID after P064, before P068
**Priority:** critical
**Class:** integrity / FSM correctness / replay safety
**Area:** `aid-fsm.sh increment-step`, step verification evidence, controller output contract

**Summary:** Make step advancement idempotent and cryptographically/logically bound to the exact
plan step and reviewed commit. Repeating a successful invocation must return `already_applied`
without advancing again, and evidence created for step N must be structurally incapable of
completing step N+1.

**Observed failure:** During E-064-1_2, the controller interpreted stdout `1` from a successful
increment as a possible error and invoked `increment-step` again. A duplicate verification file
with the next numerical filename was accepted as evidence for a step that had never run, so the
FSM advanced twice and temporarily claimed unimplemented work was complete.

**Required implementation:**

- Extend step verification evidence with canonical `step_index`, stable `step_id`, hash of the
  corresponding `plan.json` step, reviewed HEAD/commit and an invocation/idempotency token.
- Require `increment-step` to validate every binding against the current plan and FSM state before
  mutation. Filename and `## Result: PASS` alone are insufficient evidence.
- Persist the accepted token and transition atomically with the state mutation. Replaying the same
  token returns success with `already_applied` and never changes `current_step`.
- Reject a different token carrying stale, future-step, wrong-plan, wrong-commit or mismatched-step
  evidence. A copied/renamed prior verification file must fail.
- Replace ambiguous bare numeric stdout with a stable machine-readable result such as
  `status=advanced advanced_from=0 advanced_to=1` or equivalent JSON; define exit codes separately
  from displayed step numbers.
- Preserve and test recovery across interruption before write, after temporary write and after the
  durable state replacement. Never require direct manual editing of `fsm-state.yaml`.
- Define compatibility for legacy evidence explicitly; do not silently accept unbound evidence in
  strict/new runs.

**Acceptance criteria:**

- Two identical sequential or concurrent increment requests produce one transition and one
  `already_applied` result.
- A real step-0 verification copied to the step-1 filename cannot complete step 1.
- Evidence whose plan-step hash or reviewed commit differs from current state is rejected before
  mutation with a precise diagnostic.
- Fault injection at every write boundary leaves either the old valid state or the new valid state,
  never a double advance or partially updated evidence ledger.
- Controller tests prove that stdout cannot be mistaken for an exit code or trigger a retry.

**Delivery constraint:** Codex implements and verifies this manually outside `/aid-run`; do not use
the affected FSM to orchestrate its own integrity repair. Land after P064 because E-064-2_2 also
modifies `aid-fsm.sh` and its gate/controller contracts, and before P068 so plan-final orchestration
starts with replay-safe step evidence.

### IMP-264 - Compute evidence freshness at read time instead of persisting `head_is_current`

**Status:** ready
**Priority:** medium
**Class:** evidence integrity / stale derived state
**Area:** review-profile and delivery-gate producers and consumers

**Summary:** Evidence artifacts persist `head_is_current: true`, but the assertion becomes stale as
soon as another commit lands. E-064-1_2 closed with both `review-profile.json` and
`delivery-gate.json` claiming currentness for older revisions. Stop treating a frozen boolean as
proof: persist the referenced SHA and compute freshness against the actual reviewed/current HEAD at
read time. Add regression coverage for post-generation commits and remove or deprecate stored
freshness booleans.

### IMP-265 - Make lineage fail closed by default and keep healthy repair non-destructive

**Status:** ready
**Priority:** high
**Class:** security / recovery correctness
**Area:** `aid-plan-manifest.sh`, `aid-plan-fsm.sh --repair`

**Summary:** `plan_manifest_add_epic` defaults an omitted lineage argument to `proven`, while
`--repair` currently over-corrects in the opposite direction by degrading an already healthy
manifest to `unproven` and discarding valid attestation metadata. Default omitted lineage to
`unproven`; require the legitimate producer to pass `proven` explicitly. Make repair a no-op for a
healthy manifest and preserve trustworthy fields when reconstructing only damaged portions. Cover
omitted/malformed lineage values and healthy-repair idempotency.

### IMP-266 - Define audited recovery from an incorrect terminal `merged_to_plan` state

**Status:** idea — architecture decision required
**Priority:** medium
**Class:** architecture / lifecycle recovery
**Area:** plan manifest EPIC status state machine

**Summary:** `merged_to_plan` has no outgoing transition. If it is ever assigned incorrectly, the
operator has no sanctioned correction path. Decide between a narrow audited reopen transition,
gated by explicit operator attestation, and a deliberately terminal design with a documented
manual recovery ceremony. Do not add an unlogged generic rollback.

### IMP-267 - Re-derive ancestry fields when attesting repaired lineage

**Status:** ready
**Priority:** high
**Class:** evidence integrity / attestation
**Area:** `aid-plan-fsm.sh attest-source-ref`

**Summary:** Attestation updates source reference, lineage, reason and timestamp but can retain
incorrect `epic_merge_commit` or `epic_base_commit` values produced by repair. Re-derive those
fields from real Git ancestry at attestation time and fail closed if they cannot be proven. The
operator output must show the exact ancestry being attested, but display alone is not a substitute
for mechanical derivation.

### IMP-268 - Remove or harden the debug CLI path that can mint `lineage: proven`

**Status:** ready
**Priority:** medium
**Class:** security hardening / contract accuracy
**Area:** `aid-plan-manifest.sh add-epic` dispatcher

**Summary:** The low-level `add-epic` CLI is an undocumented third writer of `lineage: proven`, so
the code's claim that only `epic-start` and attestation can establish proven lineage is false.
Remove the production-shaped debug path or require an explicit audited maintenance mode, and test
that omission cannot inherit a fail-open default. Update the invariant documentation to enumerate
every remaining writer.

### IMP-269 - Bind C3 AC lenses to an explicit, recorded acceptance-criteria source

**Status:** ready
**Priority:** high
**Class:** audit integrity / false-green prevention
**Area:** C3 manifest builder, audit prompt bundle and profile enforcement

**Summary:** E-064-1_2's terminal C3 run silently fell back from the real plan acceptance criteria
to `final_report.md` because `AID_PLAN_AC_FILE` was unset. The AC bundle was therefore authored by
the implementation under review, while mandatory `ac_to_test_identity` and
`requirement_test_drift` lenses still appeared to run normally. Record `ac_source` as
`plan|final_report_fallback|stub` in the sealed manifest. If the profile requires an AC lens,
anything except an explicit plan source must fail closed; otherwise warn visibly and preserve the
fallback classification in the final report. Tests must prove an unset, missing or unreadable AC
path cannot produce an unqualified AC-review pass.

**Interim operating rule:** Until this lands, every C3 dispatch with an AC-sensitive profile must
set `AID_PLAN_AC_FILE` explicitly and verify that `bundle-plan-ac.md` is not byte-identical to the
implementation-authored final report. This is required for E-064-2_2 but does not reopen the
already adjudicated E-064-1_2 closure.

**E-064-2_2 extension — targeted test evidence:** The explicit AC source worked, but exposed the
next fixed-allowlist gap. A PM-authorized targeted suite produced a real revision-bound,
command-fingerprinted receipt at the reviewed HEAD, yet C3 still returned `unverifiable` because
`build-manifest` could seal only `gates_report.json` and `allowed_recheck_commands` was empty.
Extend the same source-binding principle to test evidence: either seal a typed targeted-run receipt
into `evidence_hashes`, or seal a narrowly scoped recheck command that C3 may execute. Preserve
`unverifiable` as distinct from `fail`, and do not promote C3 to blocking while a quarantined gate
has no truthful hash-bound evidence channel.

### IMP-270 - Gate-scoped PM waiver without broad FSM precondition bypass

**Status:** ready — implement manually outside AID after P064, before P068
**Priority:** critical
**Class:** governance / scoped risk acceptance / FSM integrity
**Area:** gate runner, FSM GATES→DONE transition, waiver schema and evidence

**Summary:** The current FSM `--force` records a visible waiver but skips every precondition of the
transition. E-064-2_2 needed to accept the temporary absence of `bats_all` and the timed-out
`plan_diff`, yet the only available mechanism also bypassed unrelated checks. Add a gate-scoped
authorization bound to the exact project, plan/EPIC, run, HEAD, gate ID and command fingerprint.
The named gate is reported as `waived`, never `pass`; all unrelated gates and FSM preconditions
remain enforced. Missing, stale, forged, reused or cross-run authorizations fail immediately.

**Required tests:** one waiver cannot authorize a different gate, HEAD, run or command; a waived
required gate remains visible in release/PM evidence; non-waived failures still block; replay of a
single-use authorization is rejected or idempotently returns its already-consumed disposition.

### IMP-271 - Require an explicit plan mode until the plan-final compensating control exists

**Status:** ready — required before P068 enables `plan_branch`
**Priority:** high
**Class:** lifecycle safety / fail-safe default
**Area:** `aid-plan-fsm.sh plan-start`

**Summary:** `plan-start` currently defaults an omitted `--mode` to `plan_branch`. P064 made that
mode structurally skip the per-EPIC release stack, while `plan-finalize` and `plan-merge-to-main`
do not exist until P068. Make mode explicit with no silent default, or reject `plan_branch` until
the compensating plan-final commands are installed. Tests must prove omission and incomplete
installation cannot create a plan that skips verification yet cannot close.

### IMP-272 - Constrain queue `merge_target` to an authorized plan or target branch

**Status:** ready — required before P068 enables `plan_branch`
**Priority:** high
**Class:** lineage integrity / semantic validation
**Area:** queue dependency revalidation and claim contract twins

**Summary:** Queue dependency checks prove ancestry against the `merge_target` named by a
hand-editable queue entry, but validate only Git-ref syntax. Pointing the dependency at its own task
branch can therefore self-satisfy the ancestry check. Both readers must constrain the value to the
owning `plan/Pxxx` branch or the resolved target branch and reject any other resolvable ref. Add the
demonstrated self-branch attack as a negative test in both twins.

### IMP-273 - Use one fail-closed committed-manifest authority for plan mode

**Status:** ready — required before P068 enables `plan_branch`
**Priority:** high
**Class:** authority integrity / fail-open removal
**Area:** `aid-fsm.sh cmd_init` and done-advance mode resolution

**Summary:** `done-advance` uses the fail-closed committed-manifest resolver, but `cmd_init` has a
separate reader that can turn missing `yq`, malformed manifests or unknown modes into legacy mode
and skip the plan-branch lineage precondition. Route every mode decision through one committed-tree
authority. Every inability to determine the mode becomes `unresolved` with the existing audited
override path, never a silent legacy downgrade.

### IMP-274 - Enforce the no-`grep -oP` portability invariant across all shell sources

**Status:** ready
**Priority:** medium
**Class:** regression coverage / portability
**Area:** shell portability guard

**Summary:** E-064-2_2 removed `grep -oP` from `aid-fsm.sh` but introduced the same construct in
`aid-queue-add.sh`; the test inspected only the first file. The second code instance was fixed in
`f60efab`, but the detector remains narrow. Scan every relevant shell source under
`plugins/aid-orchestrator/scripts/**` (with an explicit allowlist only if a justified PCRE
dependency exists) so the same class cannot move between files and remain green.

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

**Concrete occurrence (2026-07-12):** P061 EPIC 2 (`E-061-2_6`) went through
Auditor+Curator DONE review and merged to `main` (`446d937`) without ever
running `aid-fsm.sh plan-close` — no Simplifier dispatch, no plan-level
`.aid-o/reports/P061-delivery.md`, so `ca-review-complete` was never written
for that run. This silently blocked the UNRELATED plan P063's own
`aid-fsm.sh init` via the cross-plan DONE gate (`aid-plan-to-epic.sh`
message: "Plan P061 has unreviewed Curator/Auditor findings"). Bypassed via
`--force --reason` to unblock P063 immediately (PM-authorized, time
pressure); P061 EPIC 2's own plan-close (Simplifier + delivery report +
`aid-fsm.sh plan-close E-061-2_6 ...`) is still owed and not yet done.

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


## Probe update 2026-07-08 late / 2026-07-09 (post-BACKLOG-restore consolidation)

Working notes accumulated across the E-059-1_2 merge conflict that deleted this
file from disk/tracking (2026-07-08 ~22:29, resolved via .gitignore restore
2026-07-09). Below: everything unflushed at time of deletion, consolidated in
one pass. Evidence discipline unchanged — every item below is disk/git-verified,
not inferred.

### OBS-20260708-03 — CLOSED at producer/wiring layer, verified end-to-end (update)

**Status update:** the fix (commits 66d2b1e/8f1505b/145d04e/b51784d, IMP-177) was
independently verified live on its own subject EPIC, 2026-07-08 19:30–19:44Z
(E-059-1_2/R-E059-1):
1. `review_profile_emitted` 19:30:16Z (risk_profile: unverifiable, dispatch_mode:
   deterministic, model_calls:0) — first `review-profile.json` ever produced BY
   THE PIPELINE ITSELF since probe start (2026-07-01: 1/289 dirs had one, and
   that one was manual).
2. `audit-input-manifest.json` 19:31:37Z (next pipeline stage).
3. `audit-report.json`+`.md` 19:44Z, dual-emit. Report's own header: *"Mode: C3
   (risk-gated, distrust-based) — first genuinely live firing of this mode
   (this EPIC, IMP-177, is what wired the dead C3 gate)."* `dispatch_mode:
   agent_tool`, `generated_by_tool: auditor-agent` — real Auditor dispatch in
   C3 mode confirmed, not legacy_health fallback.

**Merged** 2026-07-08 ~22:29, commit `65dfa1b` ("merge: E-059-1_2 — AID Control
System v2, E9 C4 Release Policy core (Phase 1/2: IMP-177 C3 activation)").
Merge message independently states *"First-ever live C3 audit fire"* — matches
the probe's own finding. CP3 ran 2 rounds (HIGH fail-open + MEDIUM
cardinality-blindness bug, both closed+reverified). CP4 caught a regression in
curator's own auto-fix (missing `jq -c` flag corrupting `timeline.jsonl`
line-count) — fixed+reverified same run. Gates 266/266 pass.

**Nuance — do not over-claim "fully fixed":** at done-advance, the
`review_profile_missing_lenses` check still fired, listing as "missing" the
exact 6 `required_lenses` the fresh `review-profile.json` itself declares
(behavior_trace, ac_to_test_identity, negative_case, security_threat_model,
requirement_test_drift, field_lineage). Interpretation: the TOP-LEVEL producer
(the file existing, declaring risk_profile + required_lenses) is fixed and
confirmed live. A DEEPER layer — per-lens verification evidence proving each
declared lens was actually exercised — does not exist yet. Not a hidden gap:
the merge message discloses it (*"status=unverifiable (expected — no
cross-provider dispatch wiring exists yet, documented future work)"*), and the
check fired in `enforcement:observe` (non-blocking). Follow-on work belongs to
P059 Phase 2 (C4, E-059-2) or later — already acknowledged by the implementer,
not a reopened finding.

### OBS-20260708-04 — B-142 recurrence #3, needs an owner (update)

VULCAN escalated the same `steps[].status` "pending" gap a third time
(E-56-1_2's own `epic-summary.md`, 2026-07-08, commit `13087c0` in the vulcan
repo: *"B-142 eskalace (3. vyskyt)"*). Three occurrences across two consecutive
EPICs (E-055-2 2026-06-29, E-56-1 2026-07-08) with zero fix attempt in 9+ days.
**PM flag: this needs an assigned owner, not just a tally bump** — bump
severity language in the entry accordingly.

### OBS-20260708-07 — aid-run-gates.sh here-string gate loop silently truncates remaining gates on unguarded ssh stdin, reports overall:pass anyway

**Observed in:** VULCAN / P56 / E-56-2_2 (reproduced TWICE within one EPIC);
mechanism independently re-verified against current AID plugin source 2026-07-09
**AID version:** confirmed live in current `main` (not just VULCAN's cached copy)
**Observed at:** 2026-07-08; verified 2026-07-09
**Status:** confirmed
**Severity:** high
**Class:** false-green prevention

**What happened:** `aid-run-gates.sh`'s gate loop (`aid-run-gates.sh:195`
`while IFS= read -r gate_name; do ...` / `:269` `done <<< "$gate_names"`) reads
gate names from a here-string on stdin. `run_gate()` (`:70`) executes
`output=$(LC_ALL=C timeout "$timeout_s" bash -c "$command" 2>&1)` with **no
stdin redirect** — if any gate's shell command itself invokes `ssh` without
redirecting that ssh's own stdin (no `-n`, no `</dev/null`), the ssh call
consumes the SAME stdin the outer `while read` loop is reading from, silently
truncating the remaining gate list. Gates already run before the offending one
still report correctly; everything after it never executes, and the run still
emits `overall: pass` — `gate_count` is computed (`:179`) but never compared
against a processed count before `overall` is emitted. (Note: the `/dev/null`
4th arg at the `run_gate` call site is the `log_file` parameter, NOT an stdin
redirect — easy to misread.) VULCAN hit this twice in one EPIC: once via
`agent_loop_smoke`'s own `ssh`, once transitively via `deploy_check` → `bash
deploy.sh`'s several unguarded `ssh` calls. Both worked around locally in
`execution.yaml` (`ssh -n`, `</dev/null` on the gate command) — the underlying
tooling gap remains in the plugin.

**Why it matters:** textbook false-green — a gate silently not running folds
into `overall: pass` instead of a hard failure. Any consumer project with an
ssh-invoking gate command (deploy checks, remote smoke tests) is exposed, not
just cross-repo EPICs.

**Reproduction:** any `execution.yaml` gate whose command contains a bare
`ssh ...` call (no `-n`/`</dev/null`) placed before other gates in the list —
those later gates silently do not run. Confirmed against current
`plugins/aid-orchestrator/scripts/aid-run-gates.sh`.

**Likely fix (VULCAN's own recommendation, already concrete):** assert
`processed_gate_count == defined_gate_count` before emitting `overall: pass`.
Source: VULCAN `.aid-o/work/evidence/E-56-2_2/R-E56-2/curator-report.md`
"Recommendations for the Orchestrator" item 1; VULCAN's own `B-145`.
**PM directive: file as a standalone P1 plugin task**, not folded into another
entry — root cause and fix direction are already fully specified.

**RESOLVED (2026-07-10):** fixed exactly as recommended, commit `17a56c2`
(P060 EPIC 1 Step 1, `task/E-060-1_2/main`) — `run_gate()` now redirects
stdin from `/dev/null` (the actual stdin-starvation fix), a null-command
gate emits an explicit skip row instead of a bare `continue`, and a
post-loop `defined_gate_count == processed_gate_count` assert emits an
`_integrity` fail row + `overall: fail` + nonzero exit on any silent row
loss — the exact assertion VULCAN recommended. Bonus hardening in the same
commit: `aid-fsm.sh`'s GATES:DONE precondition now fails loud when `jq` is
missing (was a silent pass before). 3 new regression tests
(`test-aid-run-gates.bats`, F4 scenarios: stdin, no_command, `_integrity`),
verified red→green.

### OBS-20260709-01 — gate-fixer's git-add scope too broad, sweeps unrelated untracked files from other plans

**Observed in:** WAN / P059 / E-059-2_2, commits `f1c25b1` → `41a034b`
**Observed at:** 2026-07-09
**Status:** confirmed (self-caught + self-documented by the implementer)
**Severity:** medium
**Class:** shared-checkout / branch hygiene (new mechanism in the OBS-01 family)

**What happened:** gate-fixer's dispatch for IMP-149/SEC-1 (commit `f1c25b1`)
ran a broad `git add` that swept up 2 unrelated, pre-existing untracked files
sitting in the shared working tree — `.aid-o/plans/P061-structured-output-
compact.md` and `docs/plans/structured-output-compact-field-list-interim.md` —
a completely different plan's WIP draft (`depends_on: [P060]`, nothing to do
with P059), just because they were untracked in the same checkout. Fixed via
`git rm --cached` (content on disk untouched) in `41a034b`, with a
lessons-learned entry (`a51f173`).

**Why it matters:** same family as OBS-20260708-01 (shared-checkout collision)
but a NEW mechanism — not a branch-switch race, gate-fixer's own `git add`
being too broad within a SINGLE branch. Self-caught this time; won't always be.

**Likely fix:** gate-fixer should `git add` only the specific files its own fix
touched, never a broad add (`git add -A`/`git add .`) in a shared checkout.

### OBS-20260709-02 — curator-report.md producer silently failed at plan-close, no FSM precondition caught it

**Observed in:** WAN / P059 / E-059-2_2, commit `7da29b5`
**Observed at:** 2026-07-09
**Status:** confirmed
**Severity:** medium
**Class:** declared-control-dissolves-to-silent-no-op (same meta-pattern as
OBS-20260708-03, one artifact class down)

**What happened:** commit message states verbatim: *"Curator dispatch findings
for E-059-2_2 (IMP-149..158) were fully captured in backlog.md but the formal
curator-report.md artifact required by the FSM's plan-close precondition was
never written to the evidence dir. Reconstructed from the already-completed
analysis (no new review, just archival re-statement)."* The FSM's plan-close
precondition did NOT catch the missing artifact automatically — a human
manually noticed and backfilled it.

**Why it matters:** the underlying analysis was real and correct (findings did
land in backlog.md), but the FORMAL artifact the precondition is supposed to
gate on simply didn't exist, and nothing flagged it until manual review.

**Likely fix:** check whether an FSM precondition for curator-report.md
presence exists at all at plan-close; if not, add one (matching the
review-profile.json precedent from OBS-20260708-03).

### OBS-20260709-03 — task file YAML frontmatter never updates after init, drifts from archival/plan-close state (confirmed)

**Observed in:** WAN / P059, both E-059-1_2 and E-059-2_2
**Observed at:** 2026-07-09 (predicted by PM's local check, confirmed at plan-close)
**Status:** confirmed
**Severity:** medium
**Class:** evidence integrity / bookkeeping staleness

**What happened:** both EPICs' task file YAML frontmatter (`status: active`,
`runs_completed: 0`) persisted UNCHANGED through full plan-close, merge, and
archival to `.aid-o/tasks/archive/` — verified directly on the archived files.
By contrast, `queue.yaml`'s own comment block for the same EPICs IS accurate
and thorough (correctly states done_phase, all checkpoint results, "awaiting
single PM MERGE decision for both P059 branches") — so the drift is specific:
machine-readable YAML frontmatter fields are set once at init and never
written again by any pipeline stage, while human-authored comments stay
current.

**Why it matters:** any tooling that reads the frontmatter fields (rather than
parsing prose comments) sees permanently-stale status on completed EPICs —
same root shape as OBS-20260708-04 (fsm-state `steps[].status` never updated).

**Likely fix:** the same `fsm_increment_pass`/archival hook that should update
`fsm-state.yaml steps[].status` (OBS-20260708-04) should also sync the task
file frontmatter, or archival itself should stamp `status`/`runs_completed`.

### C4 release-decision observability contract — PM-defined, first recurrence found same day

PM specification (2026-07-09) for `release-decision.json` going forward, once
AID E-059-2 (C4 dual-run core, Phase 2 of P059/E9) lands — recorded in the
runbook (`docs/AID-control-system-v2-live-probe.md`, "C4 release-decision
observability contract" section):
1. `release-decision.json` must contain: `release_ready`, `merge_mode`
   (manual|auto|blocked), `pm_brief_required`, `evidence_verified_at_head`,
   `reporter_status`, `reporter_reason`, `summary_for_pm`.
2. Auto-merge must not bypass the PM brief — if `merge_mode: auto`, a stored
   human-readable `pm-decision-brief` artifact MUST exist on disk.
3. Reporter/Simplifier absence must not be silent — status must be exactly one
   of `pass`/`failed`/`missing`/`not_applicable` (with a `reason`), never bare
   omission.
4. Post-merge evidence: either re-verified at the new HEAD, or
   `evidence_verified_at_head: false` and the merge not presented as verified.
5. `.aid-o/reports/` delivery/boundary reports must NOT be committed git
   artifacts (local evidence only).

**Baseline measured 2026-07-08:** WAN has 5 committed delivery/boundary
reports (P039, P058×2, P060×2) — pre-existing practice the contract reverses.

**Recurrence #6+7 confirmed 2026-07-09, SAME DAY the contract was written:**
WAN P059 plan-close (commit `35bb035`) committed BOTH
`.aid-o/reports/P059-delivery.md` and `P059-boundary.md` to git (`git
ls-files` confirms tracked). Content quality is exemplary — `test_outcome:
pass` backed by real evidence (Playwright screenshots of confirm-validation +
CZ-decimal-comma fix, backend e2e 43/43 pass); the defect is purely the
git-hygiene rule (point 5), not report quality.

**Positive:** AID's own E-059-2 (C4 dual-run) EPIC is, as of 2026-07-09,
building `aid-release-policy.sh` with the exact field set and status-enum
semantics above verbatim (`REPORTER_STATUS`/`SIMPLIFIER_STATUS` ∈
{not_applicable, disabled, missing, pass, fail} each with a paired REASON;
`summary_for_pm` explicitly a "mechanical template — no LLM") — direct,
literal implementation of the PM spec, confirmed by reading the in-progress
source.

### Cross-repo CP3 manual-dispatch gap — VULCAN E-56-2_2 (confirmed, deferred from 2026-07-08)

**Observed in:** VULCAN / P56 / E-56-2_2
**Observed at:** 2026-07-08
**Status:** confirmed
**Severity:** medium
**Class:** false-green prevention / verifier independence

**What happened:** step 2's actual work commit (`621a8c2`) lives in a
DIFFERENT repo (`/opt/eco/services`), not vulcan — a cross-repo EPIC, honestly
disclosed by the implementer in `step-1-verify.md`. Both
`verifier-output-cp3-security.md` AND `verifier-output-cp3-code-review.md`
carry the identical self-documented header: *"security/code-review, CP3
integration, MANUAL DISPATCH — cross-repo diff not visible to
aid-prefilter.sh."* Direct proof: AID's automated CP3 dispatch is blind to
cross-repo diffs by construction (single-repo assumption); the services diff
got independent review ONLY because someone manually remembered to dispatch it
outside the normal pipeline.

**Why it matters:** if the manual step is ever skipped, a cross-repo EPIC's
out-of-repo changes get ZERO independent review while the automated pipeline
reports normally — no error, no skip event, the tool literally doesn't know
the other repo's diff exists.

**Likely fix:** `aid-prefilter.sh` should detect step-verify disclosures
naming a different repo and either widen its diff scope or emit an explicit
`cross_repo_diff_unreviewable` warning event instead of silence.

### Plugin-cache dogfood blocker — found and resolved same day, AID's own repo

**Observed in:** aid-orchestrator / E-059-2_2 (C4 dual-run), pre-EXECUTE
**Observed at:** 2026-07-09
**Status:** resolved (Option C), verified safe
**Severity:** high (structural), now mitigated
**Class:** plugin-rollout gap, self-referential instance

**What happened:** the plugin's own repo could not dogfood itself — `/aid-run`
sources the FSM controller from Claude Code's plugin cache
(`~/.claude/plugins/marketplaces/claude-aid-o/...`), which was frozen at
commit `f1d3d91` (v2.51.0): `aid-fsm.sh` 2990 lines, **0** C3-related code
(working repo: 3349 lines, 16 hits), and missing the `4b1d335` plan_path fix
entirely. Running E-059-2_2 against this stale controller would have
reintroduced the exact false-green class (`fsm-state.plan_path` → null →
DONE plan-diff silently skipped) that `4b1d335` exists to fix. Same class as
OBS-05/OBS-08 (plugin rollout gap), now hitting the plugin's own source repo —
the sharpest instance yet: not "consumer forgot to update," but "the plugin
cannot safely dogfood its own unpushed fixes."

**Resolution (PM decision, implementer's own recommendation, Option C of
three offered):** snapshot current working-tree scripts into the cache
directory as regular files, WITHOUT symlinking and WITHOUT touching the
cache's own frozen git tracking. Verified 2026-07-09: cache `aid-fsm.sh` is
now 3349 lines / 16 C3 hits (content matches working repo) but is confirmed a
REGULAR FILE (not a symlink), cache's own `git log` still shows the frozen
`f1d3d91` — no live-mutation risk (Option B, pointing `plugin.yaml` directly
at the working repo, was rejected specifically because EPIC steps are
observed live-editing `aid-fsm.sh` mid-EXECUTE elsewhere in this same session
— a symlinked controller could mutate itself under its own run).

**Why it matters / roadmap cross-ref:** this is the concrete, reproduced
instance of `IMP-179` (already anchored in the roadmap 2026-07-08, "hard
precondition for E10/E11 promotion") — confirms the risk was correctly
anticipated before it happened. Recommend E10/E11 cutover planning treat
this dogfood scenario as a required test case, not just the consumer-project
staleness case.

### Methodology gap — self-critique, three blind spots of a disk-only observer (PM-raised 2026-07-09)

The probe's poll checklist diffs git/FSM/evidence-file mtimes (catches NEW
activity) but historically never cross-checked secondary status descriptions
(active.md prose, queue.yaml status field, task YAML frontmatter) against the
canonical `fsm-state.yaml` — these can drift silently with nothing forcing a
refresh (root cause of OBS-20260709-03 not being self-caught, only PM-caught).
Runbook now updated (2026-07-09) with an explicit bookkeeping-staleness
cross-check on every `done_phase`/`state` change, and a proactive
branch-ancestry check the moment a parent EPIC reaches DONE/merge (not
reactively at the child's own EXECUTE start).

PM also asked directly whether three specific patterns are tracked — recorded
here as explicit, disclosed methodology limitations, not findings:
1. **Aggregate evidence-error rate across EPICs** ("X% wrong at DONE") — not
   measured; the probe does spot-checks and recurrence tallies, never a
   systematic batch audit computing a rate. Would need a dedicated audit pass.
2. **Merge sometimes-asks-sometimes-not pattern** — not trackable by a
   disk-only observer; it can see the outcome (a merge commit, possibly with
   "PM MERGE rozhodnutí" in the message) but not whether an actual
   consultation happened — no visibility into the implementer session's
   conversation.
3. **Reporter/Simplifier output reaching PM chat** — same blind spot; the
   probe confirms disk artifacts exist, never whether their content was
   relayed to the PM conversationally.
If any of these three matter going forward, they need a different observation
method (conversation-transcript review, or an explicit PM-side confirmation
step) — recorded in the runbook as an explicit non-goal of disk-polling.

### OBS-20260708-04 — recurrence #4 (2026-07-09, AID self-dogfood, update)

Same `steps[].status` "pending"/never-updated gap now reproduces inside
AID's own E-059-2_2 run (`R-E059-2`), not just VULCAN-observed runs.
`fsm-state.yaml` still shows `current_step: 1`, all 5 `steps[1..5].status:
pending`, `started_at/completed_at: null` at a point where Step 3
(`3651c5e`) and Step 4 (`6e870e6`) commits are already landed on
`task/E-059-2_2/main`. Confirms the increment path never touches `steps[]`
in the tool's own dogfood use, not only in downstream consumer projects —
raises confidence this is a core-path bug, not project-specific drift.

**FIX IMPLEMENTED (2026-07-12), PENDING MERGE:** commit `0be5e6f` on branch
`fix/plan-close-consistency` (not yet merged to `main` at time of writing —
PM-commissioned plan-close-consistency fix, reviewed and CP2-passed, held
for PM's own verification before merge per explicit instruction). Root
cause confirmed exactly as diagnosed: `cmd_increment_step()` only bumped
the `current_step` scalar via `sed`, never touching `steps[]`. Fix: after
the existing `current_step` update, `increment-step` now also writes
`steps[$step].status = "completed"` + `.completed_at` (ISO 8601 UTC) via
`yq`, backfills `started_at` only if it was still `null`, and emits a new
`step_status_synced` timeline event (every fsm-state mutation is evented).
Guards gracefully when `steps[]` is absent (legacy fsm-state.yaml) — the
authoritative `current_step` update is never put at risk. 4 new bats
tests (happy path, exact this-OBS symptom reproduction with zero
remaining `pending` steps, timeline event field verification, legacy-
format handling); `test-aid-fsm.bats` 74/74 (70 existing + 4 new), zero
regressions. CP2 review independently fuzzed 7 adversarial fixtures
(off-by-one index check across a 3-step fixture, malformed `steps[]`,
duplicate `id` fields) with no corruption found. Same fix branch also adds
a broader mechanical plan-close self-check (`aid-plan-close-check.sh`,
commit `6b9fc3a`) covering report-tracking/head-freshness/queue-active
staleness as a related but separate deliverable — see that commit's own
message for scope; it does NOT resolve IMP-201 or IMP-202 (different
artifacts/mechanisms, tracked separately in `.aid-o/work/backlog.md`).

### OBS-20260709-04 — Subagent committed live EPIC work directly to `main` under test-fixture git identity (self-recovered, root cause of the previously-flagged mystery "init" commit)

**Observed in:** aid-orchestrator / E-059-2_2 (P059 EPIC 2, Step 4)
**AID version:** current main / v2.52.0+
**Observed at:** 2026-07-09
**Status:** confirmed, resolved by implementer before this was reported — no residual impact
**Severity:** high (process/branch-discipline control violation on a shared branch), impact realized: none (caught pre-push)
**Class:** process control / branch discipline / agent-identity hygiene

**What happened:** this is the resolution of the "mystery `a5d380a` init
commit" flagged unresolved in the previous polling cycle. Commit `a5d380a`
("init", author `Test <test@test.local>`, 2026-07-09 14:20Z) landed
directly on `main` carrying the full Step 4 payload — `aid-release-policy.sh`
(627 lines), the `aid-fsm.sh` B1 refactor, `test-release-policy.bats`, and
12+ fixture files. This is *not* the bats test helper `_git_init_commit()`
literally firing — that helper always runs inside a disposable `git init`
sandbox producing only a 2-file `.gitignore`+`README.md` scaffold — so some
other write path reused the same throwaway identity/commit-message
convention while operating for real against the actual repo's `main`,
bypassing `task/E-059-2_2/main` entirely. A follow-up commit `0c04eab`
(proper "Step 4" message, still on `main`) landed at 14:53Z. Per the
implementer's own note on the eventual `6e870e6`: *"Recovery note: rogue
subagent committed this work as 'init' onto main; reassembled cleanly onto
the EPIC branch on top of Step 3; main reset to Marek's 17e7e72."* —
confirmed independently: `main` tip is clean at `17e7e72`+ with no
`a5d380a`/`0c04eab` in its ancestry (both remain reachable only via reflog,
`main@{1}`/`main@{2}`); `origin/main` unaffected (this was never pushed).

**Why it matters:** whatever wrote `a5d380a` had write access to `main` and
used a generic test identity instead of the EPIC branch + real author for
production code — branch target *and* identity were both wrong at once.
Self-corrected here because the implementer caught it pre-push, but the
same slip landing on a branch that another agent had already based work on,
or after a push, would be a genuinely destructive cross-agent incident, not
a same-session recoverable one.

**Likely fix:** identify the write path that lacks task-branch-context
enforcement (candidate: a subagent/tool invoked without `cwd`/branch pinned
to the EPIC worktree) and add a hard precondition — refuse any
AID-orchestrated commit when `git symbolic-ref HEAD` doesn't match the
run's declared `branch` in `fsm-state.yaml`.

**RESOLVED (2026-07-10):** formalized as a permanent, distributed feature —
`plugins/aid-orchestrator/defaults/hooks/pre-commit` (P060 D7, EPIC 2 Step 6,
`task/E-060-2_2/main`, still in progress at report time) is a sophisticated
FSM-state-aware commit-scope + branch guard, cited by name in its own header
comment: *"main is BLOCKED during EXECUTE/GATES (OBS-20260709-04: rogue
commit on main)."* Discovers the active run, enforces state-appropriate
allowed-paths (EXECUTE = current step's scope, GATES/DONE-review = union of
all steps, DONE-release = version-file whitelist), fails open on missing
tooling (never hard-blocks on absent jq/yq), and has a controller-side
companion in `aid-fsm.sh` to catch `--no-verify` residue out-of-band. What
was a temporary, manually-installed guard during E-059-2_2's own run is now
a proper `/aid-init`-distributed plugin feature for every consumer project —
the finding→fix→permanent-enforcement loop closed cleanly.

### OBS-20260709-05 — Dispatched implementer stalled in a confused wait-loop, no commit/no self-report; orchestrator took over manually (self-recovered, evidenced)

**Observed in:** WAN / P061 / E-061-1_4 Step 4
**AID version:** current WAN consumer plugin (v2.5x line)
**Observed at:** 2026-07-09 (Step 4, ~13:00-13:06Z window per surrounding commits)
**Status:** confirmed, resolved by orchestrator before this was reported — no residual impact, fully evidenced
**Severity:** medium (control-loop reliability — an implementer can silently stop making progress with no automatic detection other than the orchestrator's own patience/attention)
**Class:** process control / agent liveness

**What happened:** per `steps/step_4_domain/output.md`: *"the dispatched implementer agent completed the code changes but stalled in a confused wait-loop instead of finishing (no commit, no self-report produced despite one resume attempt)."* The orchestrator itself took over: independently ran the full test suite (1524 unit + 20 integration passed), `ruff check` clean, spot-checked new file content quality and byte-identity of the extracted legacy output-format section against the pre-change file, then committed on the stalled agent's behalf (`13e0f0f`). Fully disclosed in the step's own evidence file and in `final_report.md`'s process notes — not discovered by digging, the pipeline documented its own recovery.

**Why it matters:** this is the same failure shape as OBS-20260709-04 (AID's own rogue-commit incident) from the other side — an agent not doing what it's supposed to (there: wrong branch/identity; here: not finishing/reporting at all) with the ONLY safety net being the orchestrator's own judgment to notice and step in. There's no FSM precondition or timeout that flags "implementer accepted work, went silent, never committed" as a structural condition — it worked here because the orchestrator session stayed engaged, not because a control caught it. A future version where the orchestrator doesn't loop back before ending the session would leave Step 4 permanently stuck with code written but never committed or evidenced.

**Likely fix:** treat "step dispatched, no commit + no step-output artifact within N attempts/timeout" as a first-class FSM precondition-fail class (distinct from `missing_verifier_output`), not just something the orchestrator happens to catch — give it a name and a timeline event so it's queryable across runs instead of only readable inside a step's prose output.md.

### OBS-20260709-06 — active.md/queue.yaml claimed P059 "unmerged, awaiting PM MERGE decision" for 6+ hours after it was actually merged; wrongly gated a downstream EPIC's dependency

**Observed in:** WAN / P059 + P061 (cross-plan bookkeeping) / discovered during E-061-1_4 DONE review
**AID version:** current WAN consumer plugin
**Observed at:** 2026-07-09 (P059 merged 10:38 UTC via `1ee536b`; drift discovered and fixed ~17:15 CEST, commit `40c5d12`, by Marek directly — not caught by any AID automation)
**Status:** confirmed, fixed
**Severity:** high (this is bookkeeping-staleness with a real, not merely cosmetic, downstream consequence)
**Class:** evidence integrity / bookkeeping-staleness (same family as OBS-20260708-04's `steps[]` decoration, but here the stale field actively gated other work instead of just misdisplaying)

**What happened:** P059 (E-058-6_6→E-059-2_2 chain) merged to `main` at 2026-07-09T10:38 UTC (`1ee536b`). `active.md`/`queue.yaml` were never synced afterward and kept declaring it "unmerged, awaiting PM MERGE decision" for 6+ hours. `E-061-2_4`'s queue entry carried a hard dependency on that merge (`ExtractedFieldsForm.tsx` collision with P059's own UI changes) — the queue entry's blocking condition was therefore stale too, and nothing detected this: no FSM precondition, no gate, no audit check cross-referenced "is the branch this queue entry is waiting on actually still unmerged" against real git state. It was caught by a human (Marek) reading closely during E-061-1_4's DONE review, not by the system.

**Why it matters:** this is the bookkeeping-staleness class at its most consequential form observed so far — not a cosmetic "shows pending forever" defect (OBS-20260708-04) but a stale flag that could have kept a real EPIC (E-061-2_4) blocked indefinitely waiting on a merge that had already happened. If this hadn't been caught by chance during an unrelated review, E-061-2_4 might never have started.

**Likely fix:** any queue entry with a `blocked_on: <branch/PR>`-style dependency should be re-validated against live git state (e.g. `git merge-base --is-ancestor <branch> main`) at least at EPIC-start time, not trusted as a static claim written once and never re-checked — same underlying principle as OBS-20260708-04's fix (state that can go stale needs an active revalidation path, not a write-once field).

**RESOLVED (2026-07-10):** fixed exactly as recommended, commit `d61de7c`
(P060 D8, EPIC 2 Step 7, `task/E-060-2_2/main`) — new `aid-fsm.sh
queue_revalidate <epic_id>` with a 4-outcome contract: branch-is-ancestor →
unblock, not-ancestor → stays blocked, branch-deleted-after-merge →
merged-detection (via queue status / evidence DONE / `git log --merges`
grep), no-signal → fail-loud rather than silently trusting the stale
field. `pipeline.md` §12 now requires the consumer to queue-revalidate
before respecting a `blocked` status. 7+ new regression tests
(`test-queue-revalidation.bats`). Third finding this session to go from
observed → fixed → formally logged during the same live-probe window.

### OBS-20260709-07 — `plan_diff` gate's own exemption note names "P038+" as when it becomes required; we're on P059 and it's still `required: false` (plus: gate times out at 120s when actually run)

**Observed in:** aid-orchestrator / E-059-2_2 GATES (self-host)
**AID version:** current main, `.aid-o/config/execution.yaml`
**Observed at:** 2026-07-09, GATES run 17:35-17:37Z
**Status:** confirmed
**Severity:** medium (same family as OBS-20260708-05 — advisory-exemption wallpaper — but here the exemption's own stated expiry condition has already passed)
**Class:** false-green prevention / stale configuration

**What happened:** `execution.yaml`'s `plan_diff` gate carries the note *"required=false for AID self-host: P037 plan predates plan-level AC convention; gate becomes meaningful for P038+."* This EPIC's plan is P059 — 21+ plans past the note's own stated threshold — yet `required: false` was never flipped. In this run's GATES pass, `plan_diff` was actually invoked (not skipped) and failed with exit 124 (timeout, `timeout_seconds: 120` in config) alongside `shell_pipeline_smoke` (already tracked, OBS-20260708-05) and two intentionally-permanent advisory gates (`ui_calibration_result`/`_signoff`, one-time E-056-2_3 calibration, correctly still advisory). `gates_complete overall: pass` regardless — 4 of 6 gates failed, only `bats_fsm`/`bats_all` genuinely passed.

**Why it matters:** unlike the calibration gates, `plan_diff` was written with an explicit, checkable self-expiry condition ("P038+") and nobody re-checked it as plans advanced — the config drifted the same way `active.md`/`queue.yaml` did in OBS-20260709-06, just inside AID's own repo this time. Whether flipping it to `required: true` would even pass right now is unknown, since the gate currently just times out at 120s rather than completing — so there are two stacked issues: the stale exemption, and a functional timeout bug hiding behind it.

**Likely fix:** (1) either bump `plan_diff` to `required: true` now that P059 satisfies the note's own condition, or update the note with a fresh justification/threshold if there's a reason it's still not ready; (2) separately investigate the 120s timeout — `aid-plan-diff.sh --plan {plan_path}` needs to actually complete before its required-ness can be judged. General pattern: any `required: false` note with a stated "becomes required at X" condition should be checked against reality at every plan boundary, not left to a human noticing by chance.

**Update (2026-07-10):** the functional half is fixed — commit `8b9d88b` root-caused it: `aid-plan-diff.sh` ran each AC's `verification_pattern` via a bare unbounded `eval`, so one slow/hanging AC (e.g. a full multi-minute bats suite) wedged the whole plan-diff run. Now wrapped in `timeout "$AC_CMD_TIMEOUT" bash -c` (default 120s, matching the gate's own config), a timed-out AC records `verdict=absent, reason=timeout` instead of hanging, with a regression test added. Surfaced independently while preparing P060, not from this entry directly, but resolves exactly the mechanism described above. The stale `required: false` / "P038+" exemption-threshold question is still open — separate policy decision, not a bug.

## Positive control moments — 2026-07-08 late / 2026-07-09 additions

- CP3 fix-loop on E-059-1_2 (IMP-177 EPIC) worked hard on its own subject:
  Round 1 FAIL (HIGH, fail-open in the new `aid-audit-mode.sh` resolver) → fix
  `42fa1e2`; Round 2 CP4 FAIL (jq `-c` flag missing, corrupted
  `timeline.jsonl` line-count in a curator auto-fix) → fixed+reverified same
  run. The checkpoint system caught real bugs in the very code meant to fix
  the checkpoint system — strongest self-referential validation observed.
- WAN E-059-2 plan-close: dedicated Simplifier→CP4 re-verify pattern
  (established 2026-07-08 on P060) held again — SMP-001 applied and
  independently confirmed byte-for-byte behavior-preserving before merge.
- VULCAN E-56-1_2: after a ~3h pause in GATES, gates were RE-RUN fresh before
  GATES→DONE rather than reusing a stale report — correct freshness
  discipline, third project now doing this correctly.
- AID E-059-1's own audit-report.md (health 92/100) found and evidenced
  OBS-20260708-03 itself, unprompted — the control system self-diagnosed its
  own flagship gap before the fix EPIC even started.
- AID E-059-2_2 Step 4: implementer caught its own rogue commit-to-`main`
  slip (OBS-20260709-04) before push, reset `main` cleanly, and reassembled
  the work on the correct branch with a transparent recovery note in the
  final commit message — self-correction worked, and disclosed itself
  instead of quietly rewriting history unremarked.
- WAN E-061-1_4 Step 4 (OBS-20260709-05): a stalled implementer's takeover
  by the orchestrator was fully evidenced, not papered over — independent
  re-run of the full test suite, content spot-check, and byte-identity
  verification before committing on the agent's behalf, with an honest
  process note instead of a silent commit as if nothing happened.
- AID E-059-2_2 DONE review (Curator+Auditor, commit `23964c8`): caught two
  real HIGH findings in the EPIC's own just-shipped code — IMP-194, the same
  whitespace-only jq 1.6 bug class the aggregator had already been hardened
  against in Step 4, present in the new sibling script `aid-pm-brief.sh`;
  IMP-193, a documentation OVERCLAIM (test disposition + REQUIRED-inputs
  table claimed content-blocking verification that isn't actually
  implemented yet, deferred to E10) — corrected to match reality rather than
  left to over-promise. Both fixed same-day, CP4 PASS.

## Pre-E10 control hygiene block + E10/E11 de-duplication acceptance (PM directives 2026-07-10)

Status: `scoped` (PM-approved direction; plan to be written via `/aid-plan` — will
take the next AID plan number, shifting E10 kalibrace one number down). Grounding:
all 8 items probe-backed (OBS ledger above); Curator fate + C4 input-contract
claims independently verified 2026-07-10 (7-agent workflow: 5 readers over
roadmap/extending-aid/C4-code/FSM/topology + 2 adversarial refuters, both key
conclusions survived at high confidence).

### E10/E11 de-duplication & speed acceptance — PM directive (binding for E10/E11 planning)

The roadmap file (`docs/plans/AID-control-system-v2-roadmap.md`) is untracked
since `df848ce`; this ledger carries the directive until the roadmap's successor
location is settled. PM directive verbatim (2026-07-10):

> Před E10/E11 doplň do roadmapy explicitní "de-duplication and speed
> acceptance". C0-C4 nesmí být trvalá další vrstva. E11 musí obsahovat inventář
> starých CP/Auditor/Curator/Reporter/Simplifier mechanismů s rozhodnutím:
> remove, replace by C0-C4, keep as risk-gated, or keep as alias only. Součástí
> E11 acceptance musí být porovnání dispatch count, wall-clock času a počtu LLM
> review kroků před/po. Pokud se počet kontrol nesníží, E11 není hotové.

Operationalized:
1. **C0-C4 is not a permanent extra layer.** E11 is DONE only if the total
   number of controls decreases vs the pre-v2 baseline.
2. **E11 mechanism inventory (mandatory deliverable):** every legacy
   CP/Auditor/Curator/Reporter/Simplifier mechanism gets an explicit
   disposition — `remove` | `replace_by_c0c4` | `keep_risk_gated` |
   `keep_alias_only` — grounded in E10 unique-detection data.
3. **E11 acceptance metrics:** before/after comparison of (a) dispatch count
   per EPIC, (b) wall-clock pipeline time, (c) number of LLM review steps.
   No decrease in control count ⇒ E11 not done.
4. **Curator anchor (verified 2026-07-10):** NO document commits to removing
   the Curator role — committed state is `utility_only` / `authority: none`
   (E0-approved control-topology) + FC-38 merge-authority removal deferred to
   E9/C4, with the auto-approve consumers (gate-fixer/simplifier/pipeline.md
   `recommended_disposition` contract) still untouched after P059. Curator's
   role fate is decided by the E11 inventory above, not implicitly. FC-38
   completion (neutralizing auto-approve merge-influence) belongs to E10
   promotion, not to the hygiene block.

### Pre-E10 hygiene block — approved 8-item shape + binding plan conditions

Items (each probe-backed): (1) `aid-run-gates.sh` must not lose gates and
report pass — stdin guard `</dev/null` in `run_gate` + assert processed ==
defined count before emitting overall (OBS-20260708-07, P1); (2)
`plan.json.gates[]` reconciled against execution.yaml — undefined declared
gate → `result: fail, reason: undefined_gate` row, overall cannot pass
(OBS-20260702-05); (3) CP3 evidence freshness vs HEAD with explicit policy
for gate-fix/test-only commits, producer records reviewed head_sha first
(OBS-20260702-03); (4) CP2 prefilter diff range from step boundary, never
`HEAD~1..HEAD` (OBS-20260705-01; B-008 base-side explicitly OUT of scope);
(5) runtime/cache preflight — plugin.json version + content-hash of scripts/
vs cache; dogfood repo = hard stop + env override; consumer repos = record
controller version into fsm-state/timeline (plugin-cache dogfood blocker +
OBS-20260708-02; does NOT close IMP-179 agent-instruction staleness, which
stays a separate E10 blocker); (6) commit-path guard — fixer `git add`
restricted via per-step `allowed_paths` (P058 machinery) + branch guard:
refuse orchestrated commit when `git symbolic-ref HEAD` ≠ fsm-state branch
(OBS-20260709-01 + OBS-20260709-04); (7) queue dependency revalidation —
`blocked_on` re-checked via `git merge-base --is-ancestor` at EPIC start
(OBS-20260709-06); (8) **C4 input at-head hardening** — the release-decision
input contract ALREADY EXISTS in `aid-release-policy.sh` (all 12 inputs get
unconditional `{id, artifact, verdict, reason, head_match}` rows; missing
required → blocked → `release_ready=false`; curator_report fully covered as
profile-gated), so no new contract layer; close only the verified gaps:
(a) `head_match` is telemetry-only — `_artifact_head_match` returns true when
`revision.head_sha` is absent and `head_match=false` never blocks; make it
consequential per policy (observe: divergence event; blocking: required input
not at head → blocked); (b) at-head coverage holes — `plan-review.json`
(plan c0 dir), reporter delivery report (`.aid-o/reports/`),
`simplifier-report.md` sit outside the `aid-evidence-verify --at-head` pack;
(c) `waived` inputs[] verdict is never emitted (waivers surface only as
filenames in `waivers_applied[]`). Content-verdict blocking stays deferred to
E10 by design.

**Binding plan conditions (PM, 2026-07-10):**

> Pre-E10 hygiene blok nesmí přidat novou trvalou kontrolní vrstvu. Každý bod
> musí buď opravit existující false-green, nebo připravit odstranění legacy
> duplicity v E11.

Every item in the plan MUST state: (1) which concrete false-green it closes;
(2) whether it is a temporary legacy fix or a C0-C4 target mechanism;
(3) what it enables removing after E11; (4) a red-green test proving the
pre-fix false-green passes and post-fix fails. The block is framed as cutover
hygiene / de-dup enabler, not another review system — after completion it must
be visible which legacy CP checks E11 can switch off or reduce.

Explicitly deferred (PM): steps[]/task-frontmatter stamping (Cockpit
read-model, not false-green), run_id reuse / rescope / transactional epic-gen
(lifecycle cleanup), cross-repo CP3, shell_pipeline_smoke timeout (fix as
perf/config bug outside the plan).

### E11 enablement

What the P060 hygiene block (E-060-2_2) makes removable/cutover-ready in E11.
Each anchor names the legacy mechanism, the P060 step that hardened or replaced
it, and the E11 disposition. This is the concrete input to the mandatory E11
mechanism inventory (`remove` | `replace_by_c0c4` | `keep_risk_gated` |
`keep_alias_only`) above.

- **CP3 markdown freshness branch ← Step 4** — the CP3 head-freshness check
  (`cp3_head_freshness`, observe) is a temporary legacy guard. Removable in E11,
  replaced by C4 at-head evidence verification + C2. Disposition target:
  `replace_by_c0c4`.
- **cp2 prefilter mode ← E11 cutover** — the CP2 step-range prefilter
  (`cp2_step_range`, observe with `CP2_RANGE_POLICY`) stays as the interim
  diff-scoping guard until the E11 cutover decides whether C0/C2 subsume it.
  Disposition target: `replace_by_c0c4` or `keep_risk_gated` (E10 data decides).
- **manual cache verify/snapshot workflow ← Step 5** — the runtime cache-preflight
  (`cache_preflight`, dogfood hard-stop / consumer warn) replaces the manual
  "verify plugin cache / snapshot before run" workflow; the manual step is
  removable in E11 once preflight is trusted. Disposition target: `remove`.
- **OBS-01 family probe tracking ← Step 6** — the OBS-20260709-01/04 commit-scope
  probes are closed by `commit_path_guard`; E11 retires the OBS-01-family probe
  tracking entries once the guard has a clean E10 observation window.
  Disposition target: `remove`.

**K4×K8 (E10-window) binding — MANDATORY, decided in E10 calibration:**
`head_match_policy: blocking` (promoting `c4_head_match_policy` from observe) may
be promoted ONLY simultaneously with (or after) removing the CP3 freshness branch
(Step 4), OR C4 must take over the D4 exception (an allowed-scope commit past pack
head keeps `head_match` true via a disclosure event) — otherwise, in the
transition window, the *same* D4-permitted gate-fix commit would pass CP3 (D4
exception) yet make C4's `head_match==false` and block, structurally cancelling
the PM speed valve. The decision belongs to E10 calibration and this map names it
so it is not lost.

### OBS-20260709-02 — correction (2026-07-10): FSM presence gates DO exist; incident took a bypass window

Verified against `aid-fsm.sh` @ `23964c8` (task/E-059-2_2/main): plan-close
REQUIRES `curator-report.md` (always-required loop, ~:3462 + :3477-3481, exit
1) and done-advance review→release requires `curator-report.{yaml,md}`
(~:2818-2822). The entry's "no FSM precondition caught it" is therefore not a
missing gate on current AID main — the WAN incident must have used a bypass
window: (a) `done-advance --force` skips the whole precondition gauntlet;
(b) `ca-review-complete` marker can be hand-touched (the "Do NOT use touch"
warning is text-only, unenforced) and the cross-plan init gate checks only
marker + audit-report.md, never curator-report; (c) plan-close may simply
never be invoked — only the NEXT plan's `cmd_init` trips over the missing
marker, and only if audit-report.md exists; (d) format asymmetry —
done-advance accepts `.yaml|.md` while plan-close checks only `.md`. Caveat:
WAN runs a consumer plugin copy that may predate these gates — version not
re-verified there. Likely-fix reframed: close the bypass windows (marker
provenance, format unification) rather than "add a presence gate"; per PM
2026-07-10 decision, NOT as Curator-specific investment — covered by the C4
input contract (item 8) + E11 inventory.

## C4 release-decision.json — first live verification against the PM's 7-field contract (2026-07-10)

E-059-2_2 merged to `main` (`2b4b5d3`, v2.53.0, pushed to origin) — the
EPIC that built the entire C4 release-policy layer (Steps 1-7, this same
day). Its own evidence pack produced a real, live `release-decision.json`
(`.aid-o/work/evidence/E-059-2_2/R-E059-2/reporter/smoke/release-decision.json`,
generated `2026-07-09T20:52:08Z`, `head_sha` matching `23964c8`,
`freshness: current`) — checked field-by-field against the PM's original
spec from this runbook:

- `release_ready`: `false` ✓
- `merge_mode`: `"blocked"` ✓ (fail-closed — evidence verification failed,
  3 blockers, so it correctly did NOT default to permissive)
- `pm_brief_required`: `true` ✓
- `evidence_verified_at_head`: `false` (paired `evidence_verification_status:
  "fail"`) ✓
- `reporter_status` / `reporter_reason`: `"not_applicable"` /
  `"not_plan_boundary"` ✓ (correct 5-state CONDITIONAL semantics — this
  EPIC isn't the plan's boundary EPIC, so Reporter correctly doesn't apply)
- `simplifier_status` / `simplifier_reason`: same pattern, same correct result
- `summary_for_pm`: `"release_ready=false; evidence=fail;
  reporter=not_applicable; simplifier=not_applicable; waivers=0;
  blockers=3; merge_mode=blocked"` — exactly the flat, mechanical,
  no-LLM template format specified

All 7 required fields present, correctly typed, and semantically correct
on the system's very first real invocation (not a test fixture — this ran
against the EPIC's own actual evidence pack). `aid-pm-brief.sh` also fired
successfully (`pm-decision-brief.json`, `pm_brief_status: "generated"`,
same head_sha). The dual-run hook stayed observe-only as designed — C4's
own "blocked" verdict didn't gate anything; legacy checks + PM-approved
C3 audit (blocking findings observe-mode) decided the actual merge, and
the merge commit itself documents that split clearly ("observe-only,
legacy still decides").

This is the strongest positive-control result observed this session: a
system built and merged same-day produced a fully spec-compliant output
on first contact with real data, with the fail-closed semantics (blocked
merge_mode under failed evidence) working exactly as the PM's contract
intended.

**Second confirmation (2026-07-10, E-060-2_2 merge, `4b51860`):** the C4
dual-run hook fired again — this time on a genuinely *different* EPIC than
the one that built it, the real test of whether it generalizes.
`.aid-o/work/evidence/E-060-2_2/R-E060-2/release-decision.json`
(`head_sha` matching `1fb6613`, `freshness: current`) — again all 7
required fields present and correctly typed: `release_ready: false`,
`merge_mode: "blocked"`, `pm_brief_required: true`, `pm_brief_status:
"pending"`, `reporter_status`/`simplifier_status` both correctly
`not_applicable`/`not_plan_boundary`, `summary_for_pm` in the same flat
mechanical template. Notably `evidence_verified_at_head: true` this time
(paired `evidence_verification_status: "pass"`) — the *opposite* of
E-059-2_2's `false`/`fail` result, confirming the field genuinely reflects
live evidence state rather than being a hardcoded stub. Two-for-two on
real EPICs now.

E-060-2_2 also landed a post-merge per-plan Curator+Auditor hardening pass
(`d81ea2d`) worth noting: fixed a real `queue_revalidate` substring
false-match risk (`E-016-1` could have matched `E-016-1_3` without proper
regex boundaries), a `fsm_check_cp3_freshness` "last-wins" bug where a
stale code-review + fresh security output would have silently passed, and
hex-validated `head_sha` before shell use in `_artifact_head_match`
(anti-injection). Used `--no-verify` for this commit with an honest,
self-disclosed reason logged inline: the just-completed EPIC's own
commit-guard version-whitelist would otherwise block these non-version
files on `main` — and the implementer flagged that friction itself as a
backlog item rather than silently working around it.

### OBS-20260711-01 - D4's CP3-Freshness-Exception has no equivalent for GATES/evidence-pack staleness; will block merges once C4 enforces

**Observed in:** aid-orchestrator / P061 / E-061-1_6 / R-E061-1 (AID's own
gate_profiles/plan-gate-floor EPIC)
**AID version:** v2.54.0 (current, controller_hash `b7b10852…`)
**Observed at:** 2026-07-11
**Status:** confirmed (Curator-proposed fix auto-approved, not yet applied)
**Severity:** medium
**Class:** false-green prevention / checkpoint ownership (C4 readiness gap)

**What happened:** E-061-1_6 reached GATES→DONE cleanly (6/6 steps,
`final_report.md` claims "overall: pass"). One genuinely cosmetic trailing
commit (`25bff3e`, comment-count fix only) landed after CP3 review and was
correctly exempted from CP3 re-dispatch via the existing D4
`CP3-Freshness-Exception` trailer mechanism. The EPIC's own C3 Auditor
(dispatched at HEAD `25bff3e`) then independently re-ran
`aid-release-policy.sh` **unstubbed** against the real evidence pack and
found `gates_report.json` (stamped `revision.head_sha=9ec4844`, one commit
behind HEAD) is stale: `aid-evidence-verify.sh --at-head` reports the pack
out-of-pack, so the real C4 aggregator computes `verification_report: fail`
/ `gates_report: blocked` — directly contradicting `final_report.md`'s
clean "overall: pass" narrative. Root cause: `fsm_check_cp3_freshness`
(`aid-fsm.sh`) only recognizes the D4 trailer for **CP3 review** staleness;
`aid-evidence-verify.sh` has zero awareness of that trailer at all, so a
verified-cosmetic trailing commit that correctly skips CP3 re-review still
leaves the separate GATES/evidence-pack artifact flagged stale against the
same commit.

**Why it matters:** Currently non-blocking only because
`RELEASE_DECISION_POLICY=observe` (C4 dual-run hasn't started enforcing
yet) — but this EPIC has now demonstrated, on live evidence, the exact
failure pattern that WILL trip a real merge block the moment C4 moves to
enforcing mode: any EPIC with a legitimately-exempted trailing commit will
compute `merge_mode: blocked` even though nothing substantive changed.
That's the C4 system blocking correctly-shipped work over its own coverage
gap — the inverse failure of every prior "false green" finding in this
backlog, but still a false signal. The system caught this on itself,
independently, before it ever reached production enforcement — a genuine
positive-control result for the live-probe's whole premise, worth pinning
alongside the OBS-20260709 C4 verifications.

**Disposition (self-resolving, not yet applied):** Curator converted this
into **IMP-201** (`aid-orchestrator` internal backlog, `.aid-o/work/backlog.md`,
not this ledger) proposing a bounded extension of the existing D4 pattern
to `aid-evidence-verify.sh`/`aid-release-policy.sh`, auto-approved under
this project's Tier2 `curator_auto_rules` (`standards`+`M` effort →
`approve`). Not yet applied at time of writing — EPIC is still
`done_phase: review`, unmerged. Two adjacent Auditor findings from the same
run, also converted to proposals: **IMP-202** (`final_report.md`'s Scope
Corrections section undercounts `timeline.jsonl` events 5-vs-6, prospective
generation-fix only, Tier1 auto-approved) and a 4th confirming occurrence
of the pre-existing **IMP-182** (`audit-input-manifest.json`'s `input_hash`
still not independently re-derivable by any formula in-repo — unchanged
`high`/`L`/`always_defer`, no escalation, 4th EPIC to hit it).

**Reproduction:** `.aid-o/work/evidence/E-061-1_6/R-E061-1/audit-report.md`
Finding 1; cross-check `gates_report.json`'s `revision.head_sha` (`9ec4844`)
against `git log -1 --format=%H task/E-061-1_6/main` (`25bff3e`); re-run
`aid-evidence-verify.sh --at-head` directly against the run to reproduce
the `fail`/`blocked` verdict live.

**Likely fix:** extend an explicit freshness-exception mechanism to
`aid-evidence-verify.sh`/`aid-release-policy.sh` analogous to D4's CP3
trailer, so a verified-cosmetic trailing commit doesn't leave GATES
evidence flagged stale once `RELEASE_DECISION_POLICY` moves off `observe`.
Track whether IMP-201 actually gets applied before this EPIC (or the P062
family) reaches a live C4-enforcing merge.

### OBS-20260711-02 - CP2 review scope (unit + targeted integration) misses full e2e directory; a deliberate behavior change left a stale, now-incorrect e2e assertion undetected for one full step

**Observed in:** WAN / P062 / E-062-2_3 (Step 3 → caught during Step 4)
**AID version:** v2.54.0
**Observed at:** 2026-07-11
**Status:** confirmed (self-caught same EPIC, fixed same day, no prod impact)
**Severity:** medium
**Class:** false-green prevention / review coverage (CP2 scope narrower than
risk surface)

**What happened:** Step 3 of E-062-2_3 (`3742454`) deliberately changed
routing behavior: a confirm batch with exactly one delivery point (single
OM) now attaches a supplier SoD document even without an EAN match
("single-OM fallback"), since the target is unambiguous. Step 3's CP2
code-review ran `tests/unit/` plus the new targeted
`tests/integration/test_sod_attach.py` — it never ran `tests/e2e/`, so it
never noticed that a pre-existing P042-era e2e test
(`test_doc_routing_e2e.py::test_doc_routing_smlouva_unmatched`) asserted
exactly the OLD (now-superseded) behavior for precisely this single-OM
scenario. CP2 passed Step 3 clean; the stale assertion sat undetected
through the whole step. It only surfaced because Step 4's e2e-role
implementer ran the *full* `tests/e2e/` directory for its own capstone
test and hit the failure — initially mis-read as possible flakiness,
correctly re-diagnosed as a deterministic regression before being fixed
(`017cce5`, same-day) and logged (`3a31660`, **IMP-195**).

**Why it matters:** This is the same family as OBS-20260702-05/OBS-20260705-01
(declared/expected control resolves to a no-op or narrower-than-intended
scope, everything still reports green) but on a new axis: CP2's own scope
selection (unit + *targeted* integration, not the full suite) is a
judgment call made per-step, and nothing forces "full e2e" for steps that
touch shared routing/attach logic even when a deliberate behavior change
is exactly the kind of edit most likely to invalidate an existing e2e
assertion elsewhere in the tree. The implementer's own process
recommendation (recorded in IMP-195) is correct but currently exists only
as backlog prose, not an enforced rule — nothing stops the next step that
touches `erp_write.py`/`doc_routing.py` from repeating exactly this gap.
Positive notes: caught same EPIC (before merge, before any release
decision), self-diagnosed correctly on the second look, fixed same day,
and the fix + backlog note both landed same session — the whole loop
closed within about two hours of the original step landing.

**Reproduction:** `git show 3742454 --stat` (Step 3, no `tests/e2e/` path
touched) vs `git show 636ac08` (Step 4, adds `tests/e2e/` capstone) vs
`git show 017cce5` (the fix, `tests/e2e/test_doc_routing_e2e.py` only);
`.aid-o/work/backlog.md` IMP-195 for the full narrative.

**Likely fix:** make "does this step touch `wan/connectors/erp_write.py`
or `wan/connectors/doc_routing.py` (or equivalent routing/attach-layer
paths)?" a mechanical CP2 scope-selection rule that adds `tests/e2e/` to
the required run, rather than leaving it to per-step implementer judgment
— same shape of fix as every other "declared control, no enforcement"
finding in this backlog (Principle #1).

### OBS-20260711-03 - commit_scope_violation companion (D7c) false-positives on unresolved `{rev}` migration-filename template — first live firing, immediately wrong

**Observed in:** WAN / P062 / E-062-3_3 / R-E062-3, step 0
**AID version:** v2.54.0
**Observed at:** 2026-07-11
**Status:** confirmed (non-blocking telemetry, no impact today)
**Severity:** medium
**Class:** false-positive / evidence integrity (signal-fatigue risk)

**What happened:** Step 0's plan.json declares
`allowed_paths: ["wan/db/enums.py", "wan/db/models.py",
"migrations/versions/{rev}_add_request_type.py",
"tests/unit/test_request_type_model.py"]` — the migration entry is a
literal unresolved template (`{rev}` is meant to become the real Alembic
revision id, e.g. `042`, but nothing in the plan→epic generation pipeline
ever substitutes it). The implementer, correctly following Alembic
convention, created the real file at
`migrations/versions/042_add_request_type.py`. At step-advance, the new
`commit_scope_violation` companion (`aid-fsm.sh` ~2794-2831, introduced
this plan's predecessor cycle per D7c/OBS-20260709-01/04, this is its
**first live firing on real data**) does a literal string-equality/prefix
check (`[[ "$_cf" == "$_sp" || "$_cf" == "$_sp"/* ]]`) with no glob/pattern
expansion — `migrations/versions/042_add_request_type.py` never equals or
prefix-matches the literal string `migrations/versions/{rev}_add_request_type.py`,
so the check fires `commit_scope_violation` with `out_of_scope_count: 1`
for a file that is, by construction, exactly what the step was asked to
produce. The CP2 verifier (LLM judgment, not the mechanical check)
correctly recognized the file as in-scope ("`git show --stat 686f216`:
... All within allowed paths") — the mechanical companion and the human/LLM
reviewer disagree, and the mechanical one is wrong.

**Why it matters:** The companion is explicitly documented as
"NON-BLOCKING telemetry — never fails the increment," so there is zero
impact today (confirmed: `current_step` advanced normally, CP2 dispatched
and passed). But this is a *systematic* false-positive, not a one-off:
every plan that declares a new Alembic migration via the `{rev}` template
convention (a documented, presumably common pattern for "create exactly
one new migration file, revision TBD") will trigger this exact violation
on that step, every time. A telemetry signal that fires wrongly on every
qualifying step trains reviewers to skim past `commit_scope_violation`
events without checking them — the same signal-fatigue mechanism as
OBS-20260708-05 (permanently-failing advisory gate), now on a brand-new,
otherwise-promising out-of-band scope guard that exists specifically to
catch `--no-verify` bypasses of the pre-commit hook (a real, serious class
of risk this backlog has tracked since OBS-20260702-06). A guard that
cries wolf on its very first live commit undermines exactly the case it
was built for.

**Reproduction:** `.aid-o/work/evidence/E-062-3_3/R-E062-3/timeline.jsonl`
event `commit_scope_violation` (`step_n: 0`, `files:
migrations/versions/042_add_request_type.py`); compare against
`plan.json`'s `.steps[0].allowed_paths` (literal `{rev}` string) and the
step's `verifier-output-step-1.md` scope-check section (independently
concludes in-scope). Source: `aid-fsm.sh` grep `commit_scope_violation`.

**Likely fix:** either (a) resolve `{rev}`-style templates to a glob
(`migrations/versions/*_add_request_type.py`) at plan.json generation
time, or (b) have the companion's path-match step treat a `{placeholder}`
segment in an `allowed_paths` entry as a wildcard before the literal
comparison. Either way, false-positives on a brand-new anti-bypass guard
should be fixed before the guard has fired enough times to become
background noise.

### OBS-20260711-04 - CP2 verifier output written to repo root instead of canonical evidence directory (new instance of the OBS-02/OBS-11 evidence-path-duality family, this time missing the evidence dir entirely)

**Observed in:** WAN / P062 / E-062-3_3 / R-E062-3, step 0
**AID version:** v2.54.0
**Observed at:** 2026-07-11
**Status:** confirmed (untracked, not yet committed)
**Severity:** low
**Class:** evidence integrity / UX indexing (same family as OBS-20260702-02,
OBS-20260702-11, OBS-20260706-01)

**What happened:** The Step 0 CP2 code-review output landed as
`verifier-output-step-1.md` at the **repository root** (`/opt/eco/projects/wan/verifier-output-step-1.md`,
untracked, `git status` shows `??`) instead of the canonical
`.aid-o/work/evidence/E-062-3_3/R-E062-3/verifier-output-step-1.md`. The
content itself is correct and complete (`_generated_by`, `Reviewed-Head`
matching `686f216`, `verdict: pass`) — this is a pure file-placement miss,
not a content problem. The step's OTHER two evidence artifacts for the
same step (`step-0-verify.md`, and the plan/timeline/fsm-state files) all
correctly landed in the canonical run directory, so the miss is specific
to this one file/dispatch, not a systemic path misconfiguration for the
whole run.

**Why it matters:** Same class as OBS-20260702-02 (run.md path duality)
and OBS-20260706-01 (gates_report.json two paths), and adjacent to
OBS-20260702-11 (1-based/0-based numbering drift, also visible here:
`verifier-output-step-1.md` for what the canonical dir calls
`step-0-verify.md` — the same step, two numbering conventions, now also
two directories) — but this instance is a step further: not "two
locations for the same logical artifact," but "the artifact isn't in
ANY blessed location at all." Since it's untracked, it currently poses no
git-history risk, but if a future commit's broad `git add` sweeps it up
(a pattern already seen elsewhere in this backlog, e.g. the P059 window's
gate-fixer broad-add incident) it would land a stray root-level file in
the repo permanently. More immediately: any consumer reading
"canonical evidence for E-062-3_3 step 0" from `.aid-o/work/evidence/...`
alone would see `step-0-verify.md` but miss this CP2 output entirely
unless they also know to check the repo root.

**Reproduction:** `git status --short` in the WAN repo shows
`?? verifier-output-step-1.md` at top level; compare
`.aid-o/work/evidence/E-062-3_3/R-E062-3/` contents (has `step-0-verify.md`,
lacks `verifier-output-step-1.md`).

**Likely fix:** same as OBS-20260702-11's recommendation — pin one
canonical numbering AND one canonical directory for all verifier-output
artifacts, and have whichever dispatch step writes this file resolve its
output path from the run's evidence-dir variable rather than a
cwd-relative default that silently falls back to the process's working
directory when unset.

### OBS-20260711-05 - Release automation misattributes a pre-written `[Unreleased]` CHANGELOG entry to the PREVIOUS release's header; same bug still live and unfixed in README.md Roadmap on current main

**Observed in:** aid-orchestrator / P061 EPIC 1/6 release cut (v2.55.0)
**AID version:** v2.54.0 → v2.55.0 (self-host release of the tool itself)
**Observed at:** 2026-07-11
**Status:** confirmed — CHANGELOG.md instance fixed same day (doc-only
patch); **README.md instance CONFIRMED STILL PRESENT on current main HEAD**
**Severity:** high
**Class:** release-integrity / version-registry drift (self-host tooling
bug, not a consumer-facing AID Control System defect, but breaks this
project's own documented single-source-of-truth guarantee)

**What happened:** This project's `scripts/aid-release.sh` had a
pre-written `## [Unreleased] — pending P061 EPIC1 release` section in
`CHANGELOG.md` (the real content for the release about to be cut) sitting
above the still-correctly-labeled `## [2.54.0] — 2026-07-10` section (the
real, previously-released P060/E-060-2_2 content). `update_changelog()`'s
header detector (`grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' | head -1`)
only recognizes numeric `## [X.Y.Z]` headers — `[Unreleased]` doesn't
match, so it skipped straight past the real pending entry and found
`2.54.0` (the OLD, correctly-labeled release) as "the" header. Since
`2.54.0 == CURRENT` (the version being bumped from), the script's
existing-header-rename branch fired: `sed -i "s/## \[2.54.0\].*/##
[2.55.0] — $TODAY/"` — renaming P060's real header to `2.55.0` **without
touching the content beneath it**, so `2.55.0` briefly pointed at P060's
bullet list while the actual new P061-EPIC1 content sat unpromoted under
`[Unreleased]`. Caught and hand-fixed same day (commit `a506a87`,
doc-only, `[2.54.0]` restored as P060's real entry, a proper `[2.55.0]`
entry written with P061 EPIC1's actual shipped content).

**The identical failure mode independently hit `README.md`'s Roadmap
section via a separate code path, and it is NOT fixed** — confirmed live
on current `main` (`4bcc86a`) at time of observation. `aid-release.sh`'s
README updater does a blind global substitution:
`sed -i "s/v$CURRENT/v$NEW_VERSION/g" "$readme"` — it finds the literal
string `v2.54.0` anywhere in the file (the Roadmap's `- **v2.54.0**
(current) — P060 false-green / stale-evidence hardening (E-060-2_2): ...`
line) and renames just the version token to `v2.55.0`, **leaving the
entire P060/E-060-2_2 description text attached under the new number**.
This is not merely "not yet updated" — it is actively wrong: `README.md`
right now claims `v2.55.0 (current)` is "P060 false-green / stale-evidence
hardening (E-060-2_2)", which is what `v2.54.0` actually shipped; the real
`v2.55.0` (gate_profiles substrate + plan-gate floor, D8/D9) has no
Roadmap entry at all, and the CLAUDE.md-mandated "add a new line, move the
previous version down, keep 3 most recent" step never happened.

**Why it matters:** This is the project's OWN release tooling breaking the
OWN documented invariant (`CLAUDE.md` §"Single Source of Truth" +
"README Roadmap Update", both explicit, both violated). Comments in
`aid-release.sh` (lines 120-131, "IMP-093 fix... prevents the 3x-observed
bug where a pre-written CHANGELOG entry... was treated as the [current]
one") show this exact CLASS of misattribution has already recurred at
least 3 times and been patched narrowly each time — but only for the case
where the pre-written entry already carries the literal new version
number. The very common `[Unreleased]` convention (not literal-version
pre-writing) was never covered by that fix, so this is effectively the
**4th occurrence** of the same root defect, wearing a different trigger.
Consequence if unfixed: every future release cut that follows the
`[Unreleased]`-heading convention will corrupt the CHANGELOG (now guarded
only by manual review, since the automation itself doesn't detect it) and
silently mislabel the README Roadmap (not guarded by anything — no manual
catch happened here). E-061-2_6 (EPIC 2/6 of this same plan) has already
started; the next release cut is a live re-trigger risk.

**Reproduction:** `git show a506a87 -- CHANGELOG.md` (the fix diff, shows
the before/after misattribution); `sed -n '110,120p' README.md` on current
`main` (still shows `v2.55.0 (current)` with `v2.54.0`'s real description);
`git show 6e5113e -- README.md` (the original blind-sed commit); root
cause at `plugins/aid-orchestrator/scripts/aid-release.sh` lines ~138
(`CHANGELOG_HEADER` numeric-only grep), ~199-229 (`update_changelog()`
three-branch logic, no `[Unreleased]` recognition), ~351-359 (README
updater, unconditional `sed -i s/v$CURRENT/v$NEW_VERSION/g`).

**Likely fix:** (a) `update_changelog()` gains a fourth, first-checked
branch: if the file contains a literal `## [Unreleased]` section (any
suffix text), treat that as the pending entry — rename ONLY that header
to `## [$NEW_VERSION] — $TODAY`, leave every numeric header below it
untouched. (b) The README updater must stop doing a blind version-token
substitution and instead: detect the existing top Roadmap line, move its
*exact current text* down to become the new second-from-top entry, and
insert a genuinely new top line for `$NEW_VERSION` (content TBD by
PM/agent, same "fill in" pattern `update_changelog()` already uses for its
prepend branch) — mirroring the CHANGELOG fix's shape. (c) Given this is a
4th occurrence of the same defect class, consider a post-release
self-check step (`aid-release.sh --verify` or equivalent) that asserts the
CHANGELOG/README content under the new version header textually overlaps
with the actual `git diff $LAST_TAG..HEAD` shipped changes, catching a
misattribution mechanically instead of relying on a human noticing a
wrong changelog paragraph.

**Update (2026-07-11, same day):** README.md instance hand-fixed
(`4c4eb54` on side branch `fix/plan-close-consistency`, 1 commit ahead of
`main` at time of writing, not yet merged back) — v2.55.0 restored with
P061 EPIC1's real content, v2.54.0 re-added with P060's real content,
explicitly citing this OBS entry and explicitly re-confirming the root
cause in `aid-release.sh` is still open (doc-only patch, matching this
entry's own recommendation). **Historical confirmation this is a chronic,
recurring defect, not a one-off:** `git branch -vv` surfaces
`task/E-042-1_1/main`'s tip commit `a2f37a5 fix: update README tagline to
v2.29.0 (aid-release.sh missed the header)` — the exact same
README-tagline desync was hand-patched once before, at v2.29.0, long
before this session. Combined with the 3 prior IMP-093 CHANGELOG fixes
already referenced in `aid-release.sh`'s own comments, this defect class
has now been manually patched at least 5 times across the project's
history (3× CHANGELOG/IMP-093, 1× README tagline/v2.29.0, 1× this
session's CHANGELOG+README pair) without the root cause ever being fixed
in the script itself. Status: CHANGELOG + this specific README instance
both resolved; **root cause still open, will recur at the next release
cut using the `[Unreleased]` convention.**

### OBS-20260711-06 - CP3 security review under-rated a real profile-selection-bypass vulnerability as MEDIUM/data-exfiltration-only; PM's own independent reproduction found it fully defeats the plan-gate floor mechanism

**Observed in:** aid-orchestrator / P061 EPIC 2/6 / E-061-2_6 / R-E061-2
**AID version:** v2.55.0-dev (self-host, mid-EPIC)
**Observed at:** 2026-07-11
**Status:** confirmed — fully fixed same day (`89f80e0`), logging as a
review-calibration finding, not an open defect
**Severity:** medium (as a process/calibration finding; the underlying
vulnerability itself was HIGH — full bypass of the plan-gate floor)
**Class:** review-calibration / false-negative-adjacent (detector fired,
but under-rated impact — a new sub-class of the false-green family: not
"no detector" or "detector out of scope," but "detector correctly
triggered, severity assessment wrong")

**What happened:** `aid-run-gates.sh`'s new `--profile` flag (E-061-1_6/
E-061-2_6, the gate_profiles/plan-gate-floor substrate this whole plan
exists to build) resolves `.gate_profiles."${profile}"` via `yq` using
unescaped string interpolation of the user-supplied `--profile` value.
CP3's own security review caught the unescaped interpolation and rated it
**MEDIUM, data-exfiltration-only**. The PM independently reproduced a
worse outcome: a crafted `--profile` value using yq's `//` alternation
operator (`nonexistent" // ["test_gate"] #`) makes the failed lookup fall
through to an **attacker-supplied literal `include[]` array**, letting an
unrecognized profile name silently behave as a real one with
attacker-chosen gate exclusions while `gates_report.json` still reports
`overall: pass`. That is not data exfiltration — it is a complete bypass
of the exact protection (plan-gate floor / profile-based gate exclusion)
this plan exists to build, from the single flag surface most directly
exposed to CLI/automation input.

**Why it matters:** The review layer worked in the sense that CP3 found
*something* real at this exact interpolation site — but its own severity
call (MEDIUM/data-exfil) would not have blocked merge or triggered urgent
same-day escalation on its own; it took the PM's own hands-on
reproduction to establish the true blast radius (a security-control
bypass, not an info leak) and escalate accordingly. This is the mirror
image of OBS-20260711-01/03 (detector exists but doesn't cover enough
ground) — here the detector covered the right ground but miscalibrated
what it found. Worth tracking as a distinct pattern: automated CP3
security review's severity heuristics may need a specific check for
"does this injection let an attacker supply a *replacement value* the
system then trusts as legitimate config" (structural bypass) vs. generic
injection-implies-leak defaults.

**Positive to pin:** once escalated, the fix was fast, correct, and
independently re-verified beyond the PM's own PoC — switched all 3
interpolation sites (2 in `aid-run-gates.sh`, 1 in `aid-fsm.sh`) from
string interpolation to yq's `strenv()` with the value passed via
environment variable (profile name never parsed as part of the yq
expression), added 2 regression tests reproducing the exact PoC + a
variant, and the fixer re-verified with 5 additional attacker-constructed
payloads beyond the PM's own before committing — not just trusting its
own claim. `test-aid-run-gates.bats` 31/31, `test-aid-fsm.bats` 70/70,
`test-aid-gate-profile.bats` 30/30, zero regressions. Same-day
catch-to-fix cycle on a genuinely high-impact vulnerability, in code that
had not yet reached `main`.

**Reproduction:** `git show 89f80e0` (the fix + full PM's PoC description
in the commit message); the vulnerable pre-fix interpolation sites were
`aid-run-gates.sh`'s `.gate_profiles."${profile}"` yq lookups (×2) and
`aid-fsm.sh`'s gate-profile validation (×1).

**Likely fix:** none needed — already fixed. Recommend folding "does a
crafted value change what the system treats as trusted config, not just
what it can read" into CP3's security-review checklist for any future
`--profile`/name-driven config lookups, so this class of impact is rated
correctly on first pass rather than requiring PM escalation to surface.

## P068 re-grounding follow-ups (2026-07-24, v2.62.1)

Unrelated findings surfaced while re-grounding the P068 plan against current
code. Recorded here, NOT folded into P068 (they do not block P068 execution and
are out of its scope). Numbering deferred per the POST-P064 checklist's
"dedup/renumber Curator IMP-271+ proposals" note.

### Shipped `defaults/execution.yaml` has no `gate_profiles` block

**Status:** idea — verify scope before acting.
**Context:** P068 Step 2 resolves the plan-final profile via the `gate_profiles`
table (`gate_profile_max`, `release` ⊃ `full`), which P064 Step 8 delivers. That
table exists only in the self-host `.aid-o/config/execution.yaml`; the shipped
`plugins/aid-orchestrator/defaults/execution.yaml` ships **no** `gate_profiles`
block. A consumer project initialised from defaults would have no profile table
for a plan-final release run to resolve against.
**Proposed change:** confirm whether P064 Step 8 was meant to seed the profile
table into `defaults/execution.yaml` (and `/aid-init`), or whether consumers are
expected to author it. If the former, it is a P064-scope defect to fix in P064,
not worked around in P068.
**Open question:** is this already tracked under a P064/P066 item? Dedup before
filing.

### EPIC generator truncates multi-line acceptance criteria to their first line

**Status:** idea — observed 2026-07-24 during P068 EPIC regeneration.
**Context:** `aid-plan-to-epic.sh` copies each plan AC into the EPIC's
`## Acceptance Criteria` list but keeps only the FIRST LINE. A multi-line AC
loses everything after it — e.g. the P068 Step 2 criterion "Every quarantined
gate satisfied by a substitute has a matching `quarantine_substitutes[]` entry
carrying gate_id, receipt_sha256, command_sha256, head_sha == candidate_sha …"
appears in the EPIC as just "Every quarantined gate satisfied by a substitute has
a matching". The field list, the binding rules and the fail-closed conditions are
all dropped.
**Why it matters:** an implementer working from the EPIC alone gets an
incomplete, sometimes mid-sentence criterion. The full text survives only in the
plan (reachable via `plan_ref`), so nothing is lost from the record — but the
EPIC is the artifact the role pipeline reads.
**Proposed change:** carry the full AC block (all continuation lines) into the
EPIC, or explicitly mark truncated ACs with a pointer to the plan's AC id.
**Open question:** is the first-line-only behaviour deliberate (EPIC as a
deliberately condensed index) or incidental? Check `_aid_extract_*` in
`lib/aid-scoping.sh` before changing.

### C0 plan-review requires a dependency graph that no pre-generation producer creates

**Status:** idea — raised by the C0 review of P068, 2026-07-24. **Owner: the C0
bridge (P065), not P068.**
**Context:** `lib/aid-c0-plan-review.sh` seals
`<evidence_dir>/c0/plan-graph.json` into its input manifest and the C0 prompt
asks for graph-based acyclicity / output-producer analysis. The graph is produced
by `aid-c0-contract.sh` from `plan.json`, which only exists *after* EPIC
generation — so at plan-review time the file is genuinely absent. The bridge
currently seals it as a zero-byte entry (empty-string sha256, size 0), which stops
the review failing but leaves the mandatory graph analysis with no artifact.
**Proposed change:** either (a) add a pre-generation graph producer with an
explicit schema-valid output and make the review depend on it, or (b) remove the
graph from the required C0 input contract and define the text-derived dependency
analysis that replaces it.
**Open question:** does any consumer rely on the zero-byte-seal representation?
Changing it shifts every sealed `input_hash` and the golden fixture in
`test-c0-plan-review.bats`.
