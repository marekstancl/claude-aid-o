---
id: P076
type: plan
status: ready
created: 2026-08-08
author: PM + AI
risk: high
---
> **Closure (2026-08-10):** implemented, merged to `main` and released as **v2.80.0**. Archived from the active plan set.


# Plan: Auto Mode Owns Its Waits

## Stakeholder Brief

Auto mode today dies quietly: an agent writes "waiting for tests" and ends its turn, a crashed session loses a 30-minute test run with nothing to reattach to, a backend is "started" by prose with no health probe, and recovery policy lives as contradictory paragraphs across three documents — one of which cites configuration keys that do not exist. Meanwhile the machinery to fix all of this already ships: `aid-job.sh` is a complete, tested process supervisor (including the exact five-minute resume rule), the runtime-baseline system already measures which gates belong in the background, and P073/P074 delivered the audit, force, and worktree substrate. This plan wires it together. EPIC 1 gives gates an owned background path — a killed session re-attaches to the still-running job instead of restarting it — plus an eager continuation artifact, a single-use `resume` command, and truthful `auto_controller` status states. EPIC 2 gives declared services a real lifecycle (health probes instead of sleeps, per-run ports, acquire-once/release-once, deadline means cancel) and turns the recovery prose into one machine-readable policy with named per-class emitters and formalized Codex adjudication. EPIC 3 closes the loop: every consciously deferred item becomes a numbered backlog entry, and one integration fixture proves the kill-and-resume story end to end. Nothing auto-flips for consumer projects: the /aid-init template gains fields and capability; the two measured long gates flip only in this repository's own configuration. The main risk is destabilizing the gate runner every run depends on; it is mitigated by a byte-identical foreground path and golden regression comparisons.

## Context

Source document: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` §16 (D22 owned jobs, D23 service readiness, D24 honest host continuation, D25 bounded recovery), chosen by the PM on 2026-08-08 as the next stream after P073/P074 shipped. Two independent grounding sweeps verified every claim file:line against main (~v2.79.3); an adversarial Codex round produced six blocking findings, all folded in; the decision record with the PM's five approved choices plus two binding additions (deferred-work registry, explicit consumer-project story) is `.aid-o/work/interim-P076.md`. The prior recovery design `docs/plans/2026-07-21-IMP-auto-mode-stop-taxonomy-and-recovery-policy.md` is reconciled, not rewritten — only its replaced sections get superseded markers. Key grounded facts this plan stands on: `aid-job.sh` (741 lines, bats-covered) already implements group ownership, PID-reuse defeat, HEAD/tree-bound results, and a `watchdog` answering `resume_needed` at 300 s — and nothing in the run pipeline calls any of it; the AUTO ownership contract is written twice as pure instruction; `run_gate` uses a bare `timeout` with no group kill and no durable record; the baseline library computes `run_mode_recommended` with no configuration field to land in; and the enforcement registry's grep guard forbids any second job-supervision implementation, so every mechanism here delegates.

## Goal

An auto-mode run survives its own interruptions: long gates run as owned, re-attachable jobs; declared services are probed, namespaced, and cleaned by their owner; every stop routes through one bounded, machine-readable recovery policy ending in adjudication, escalation, or the P073 force surface; and when the host genuinely cannot continue, AID says so honestly and leaves a single-use resume artifact instead of pretending.

## Scope

**In scope:**
- `run_mode: foreground|background` per gate in the execution.yaml template; background gates delegated to `aid-job.sh` (supervised-resumable-synchronous: the runner polls to completion, a rerun re-attaches to the live job by command fingerprint); foreground path byte-identical.
- The background flip of `bats_all` and `bats_boundary` in THIS repository's `.aid-o/config/execution.yaml` only (the two-layer configuration story: templates gain fields, never flips).
- One observe-only consumer for the baseline `run_mode_recommended` advice (named timeline event with the exact edit) and the registry-statement update that legalizes it.
- Eager `auto_resume_required.json` continuation artifact (written at background-job start, deleted at collect), `auto_controller` states in the active-runs map and status surfaces, and a public single-use `aid-fsm.sh resume` command.
- Declared services in execution.yaml + `lib/aid-service.sh` over aid-job: 1 s health probing, per-run port allocation with one reallocation retry, acquire-once/release-once run lifecycle, deadline-means-cancel, foreground `start_cmd` contract, one authorized restart cycle.
- `defaults/policies/auto-recovery.yaml`: seven stop classes with named emitters and honest mechanical/instruction labels, allowed reversible actions, budgets, the ownership table of existing retry loops (declared, not rewired), and the adjudication/escalation/force terminus; `lib/aid-recovery-adjudicate.sh` formalizing the existing temporary Codex dispatch convention.
- Deferred-work registration as IMP backlog entries; instruction sweep of every surface the groundings enumerated; enforcement-registry entries; integration fixture.

**Out of scope (each registered as an IMP backlog entry by Step 14):**
- Fire-and-return ASYNC gates (the runner returning before completion) — option 5B, deferred.
- Services-to-resource-map classifier integration — emission stays observe-only evidence.
- Foreground-gate `timeout -k` hardening — option 1B, deferred.
- Visual-companion server migration onto `lib/aid-service.sh`.
- A true host push-continuation adapter — task-notification behaviour remains instruction-only host guidance; the artifact is the enforced fallback in every host.
- Intra-plan parallel dispatch, §14/§15 handoff and visual streams, category-4 UX.

## Approach

**Chosen approach: delegate to the shipped supervisor, wire the smallest closing loop.** Every process-ownership need routes through `aid-job.sh` (the registry grep guard makes any alternative a violation); services are a thin readiness lib over the same jobs; recovery becomes one policy file plus one adjudication lib that formalizes the dispatch convention `aid-run.md` already prescribes verbatim; continuation is an artifact plus a claim primitive copied from the shipped single-use PM-override pattern. Where behaviour is genuinely LLM-driven (the controller actually running its loop, executing a printed next action), the plan says so and binds it with mechanical state, budget refusals, and release-time live checks rather than pretending bats can prove it.

**Alternative A (rejected): full async gates now.** The runner returning immediately and a later collector finalizing reports would double the moving parts (who finalizes, when, against which HEAD) for a pain — lost work on session death — that supervised-resumable-synchronous already removes. Deferred as an IMP entry.

**Alternative B (rejected): one grand recovery daemon.** A background watcher process re-invoking the controller would be a second supervisor (grep-guard violation), unstartable in hosts that reap background jobs (the visual-companion CODEX_CI note), and unnecessary: the watchdog is a query the controller loop calls, and death is covered by the eager artifact plus `resume`.

## Architecture

Everything lives under `plugins/aid-orchestrator/` unless stated. Three subsystems change.

**Owned gates and continuation (EPIC 1).** `aid-run-gates.sh` gains a per-gate `run_mode` read (default `foreground` — that path stays byte-identical). A `background` gate routes through `aid-job.sh run` (label = gate name, deadline = the gate's `timeout_seconds`, expected p95 from the baseline record when present) and the runner polls `status`/`collect` at 5 s inside its own invocation, so ownership, group kill, PID-reuse defeat, and the HEAD/tree-bound result all come from the supervisor. Before starting attempt N, the runner checks exactly the deterministic job dir for THIS attempt (`jobs/<gate>-attempt-<N>`, the --id it would use) and RE-ATTACHES (poll/collect) instead of double-starting; the fingerprint is a VALIDATION guard on the found job (command drift check), not a discovery mechanism — so earlier failed attempts never masquerade as this attempt's result — that is the crash-resume story: a killed session reruns `run-all` and continues the same 30-minute suite. BEFORE each background job spawns, the runner eagerly writes `auto_resume_required.json` (run/epic/plan ids, job id — `pending` until the spawn, then atomically rewritten, expected terminal states, the fully resolved resume command, single-use claim fields) and deletes it at successful collect — a dead controller therefore always leaves the pointer, in every crash window. `awaiting_host_resume` is DERIVED by consumers (artifact present + no liveness within the stall threshold), never stored by a dying process. The active-runs map entry gains `auto_controller` (`active | awaiting_host_resume | manual | blocked_for_pm`) and `resume_artifact` via a new locked writer; `/aid-status` renders them, superseding the bare `Mode:` line. `aid-fsm.sh resume <epic_id>` claims the artifact single-use (`mv -n` + source-gone post-check, the shipped pm-override pattern), collects the job result, updates the map, and prints the verified state plus the next controller action — an honest instruction handoff with a mechanical core, idempotent on second call. The baseline recommendation gains its one observe consumer: when `run_mode_recommended == background` and the gate declares no `run_mode`, the runner emits timeline event `gate_run_mode_advice` naming the exact one-line edit; flipping remains the project PM's one-line decision (consistent with the Step 3 consumer story), and the registry sentence claiming recommendations never influence behaviour is rewritten to describe the advisory event.

**Services and recovery (EPIC 2).** execution.yaml gains an optional `services:` map (`start_cmd`, `probe_cmd`, `stop_cmd`, `startup_deadline_seconds`, `max_lifetime_seconds`, `log_hint`, `restart_authorized`, `port_env`); absent block = byte-identical behaviour. `lib/aid-service.sh` implements `aid_service_up_all`/`aid_service_down_all`/`aid_service_status`: port allocation by bind-probe with exactly one reallocation retry on collision, start through `aid-job.sh run` (the job IS the ownership record; `start_cmd` must remain its foreground process — a terminal job with a still-healthy probe is a named refusal), 1 s probe polling until healthy or the startup deadline, startup-deadline expiry → `aid-job cancel` + `stop_cmd` (never a live orphan behind a `timed_out` record; the job's own deadline is the separate max_lifetime_seconds ceiling), all state in a flocked, atomically-written per-run `services.json` in the shared state root; stop/probe/restart always read the recorded port back from the registry. Lifecycle is acquire-once before the gate loop, release-once in the runner's final cleanup with a done-advance safety net; a gate's `needs_services:` only fail-fasts when a named service is not healthy. One authorized repair: `restart_authorized: true` permits exactly one cancel+restart cycle, recorded; anything further is a ladder stop. Recovery policy becomes `defaults/policies/auto-recovery.yaml`: stop classes GATE_TIMEOUT, SERVICE_UNHEALTHY, JOB_LOST, TRANSIENT_INFRA, DISPATCH_ORPHANED, REVIEW_EXHAUSTED, UNCLASSIFIED — each with its named emitter and an honest `detector: mechanical|instruction` label, allowed reversible actions, attempt and wall-clock budgets, and the terminus chain adjudication → ESCALATION decision field → P073 force. Existing retry loops (gate fix 3, CP2 2, C3 4, C0 4) are DECLARED in an ownership table with `authority: existing` — never rewired. `lib/aid-recovery-adjudicate.sh` formalizes the temporary convention from `aid-run.md:75-80`: fact pack (verified facts, FSM state, ladder record, the class allowlist, forbidden actions), dispatch over the existing isolated Codex transport, mechanical in-allowlist validation with one retry then ESCALATION, timeline append. Each attempt lands in `<run>/recovery-ladder.jsonl`; the lib refuses over-budget actions fail-closed.

**Closure (EPIC 3).** Deferred items become IMP entries in `docs/plans/2026-06-29-BACKLOG.md`; status renders and its byte-locked fixture update; the integration fixture drives kill-and-resume, service lifecycle, and ladder exhaustion end to end; registry entries, identical CHANGELOGs, `docs/extending-aid.md` sections, and the source-doc annotation verification land per repository policy.

## Implementation Steps

**EPIC 1: Steps 1-7 — Owned Gates and Honest Continuation**

### Step 1: The run_mode field and the two-layer configuration story

**Objective:** execution.yaml understands `run_mode: foreground|background` per gate — documented in the template with foreground as the unchanged default — and this repository's own configuration flips its two measured long gates to background.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` (per-gate key documentation in the live gate entries, lines ~13-77 — NOT the commented gates_python language example further down) — document the new optional per-gate key `run_mode: foreground|background` (default `foreground`; background = supervised by `aid-job.sh`, re-attachable after a crash) next to the existing `timeout_seconds`/`max_retries` documentation; no template gate sets it (nothing auto-flips for consumer projects).
- Modify: `.aid-o/config/execution.yaml` (gate blocks: `bats_all` starting line ~9, `bats_boundary` starting line ~42 — the boundary block extends past line 87 with its comments) — add `run_mode: background` to both, with a comment citing the measured p95 rationale and P076.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (baseline-advice entry, lines ~1108-1115) — the sentence "never changes orchestrator behavior by itself (a human ... edits execution.yaml's timeout_seconds/run_mode by hand)" is rewritten: the recommendation now has a defined landing field and a named observe-only advisory event (Step 3); flipping remains a human/controller edit.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-run-mode-field.bats` — a gate without `run_mode` resolves foreground; explicit foreground and background parse; an invalid value fails loudly naming the two accepted forms; the shipped template contains the documentation block and zero template gates with `run_mode` set.

**Architecture Context:** Grounded fact F5: the baseline library computes `run_mode_recommended` and the registry itself documents that a human is expected to edit a `run_mode` that does not exist — this step creates the landing field. The Codex round's blocking finding (D22 dormant on shipped config) is answered by the two-layer story the PM approved: template documents capability, only this repository's project config flips its own gates (`bats_all`/`bats_boundary` exist only here).

**Implementation Detail:** The field is read in Step 2 via `yq ".gates.\"${gate_name}\".run_mode // \"foreground\""` with a validation branch rejecting anything else. The template documentation block shows both values, states the crash-re-attach behaviour in one sentence, and cross-references the advisory event so a consumer PM learns the flip from their own project's telemetry rather than from this plan.

**Error Handling:** An invalid `run_mode` value fails the gate run before any command is spawned, naming the gate and the accepted values (never a silent foreground fallback that would mask a typo like `backgroud`).

**Edge Cases:**
- Consumer project whose `.aid-o/config/execution.yaml` predates the field: absent key = foreground everywhere, byte-identical behaviour (regression-asserted in Step 2's golden test).
- A gate with `run_mode: background` but `timeout_seconds` absent: the 60 s default becomes the job deadline — legal, documented, and the advisory event (Step 3) will recommend a realistic timeout once samples exist.
- `bats_boundary` is `required: false` today: backgrounding an advisory gate is legal; its failure semantics are untouched by run_mode.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] All four bats cases pass, including the loud invalid-value failure.
- [ ] `yq '.gates.bats_all.run_mode' .aid-o/config/execution.yaml` prints `background`; `grep -c 'run_mode' plugins/aid-orchestrator/defaults/execution.yaml` shows documentation only (no template gate sets it).
- [ ] The registry advisory-entry text names the field and the advisory event instead of the by-hand-only claim.

**Effort:** S
**AID Role:** backend

### Step 2: The background gate path — delegated, group-owned, re-attachable

**Objective:** A `run_mode: background` gate runs through `aid-job.sh` with full group ownership and a durable HEAD/tree-bound result, the runner polls it to completion inside its own invocation, and a rerun after a crash re-attaches to the still-live job by command fingerprint instead of starting a second one; the foreground path stays byte-identical.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (run_gate region lines ~139-177 and the per-gate dispatch region lines ~585-680) — read `run_mode` (Step 1); foreground: untouched code path; background: resolve the run's jobs dir (`<evidence_dir>/jobs/`), compute the command fingerprint exactly as `aid-job.sh` does (sha256 over NUL-joined argv), and (a) if the deterministic job dir for THIS attempt (`--id <gate>-attempt-<N>`) exists — validate its recorded fingerprint matches the command (mismatch = config drift: cancel, ARCHIVE the stale job dir to a `.superseded-<epoch>` sibling — `aid-job.sh run` refuses an existing dir, so the fresh start needs the path free — then start fresh, all under a named log) and RE-ATTACH (live → poll; terminal → collect idempotently): log `gate_job_reattached`; (b) else `aid-job.sh run --jobs-dir <dir> --id <gate>-attempt-<N> --label <gate> --deadline <timeout_seconds> [--expect-p95 <baseline p95_ms converted to SECONDS when ≥3 samples>] -- bash -c "<command>"`, emit timeline event `gate_job_started` with job_id, then poll `status` at 5 s — emitting a `gate_job_heartbeat` timeline event every 60 s of polling (the Step 6 stall consumer's progress signal; asserted in this step's suite) — and `collect` on terminal. Row mapping is explicit: `duration_ms` computed from the job record's started_at/ended_at (the result record alone carries no duration field); a `timed_out` job synthesizes `exit_code: 124` in the gate row so the existing timeout/censoring/streak logic keys correctly (the raw kill exits 143/137 and is preserved as `job_exit_code`); the gate row gains `job_id` and `job_state`. Branch outcomes, exhaustively: live same-fingerprint job → re-attach; TERMINAL same-fingerprint job → `collect` idempotently, build the row, never re-run; no job → start fresh. A consumer gate with `max_retries > 0` retries under a new deterministic job id — the runner passes `--id <gate>-attempt-<N>` explicitly (the supervisor's own flag), producing the FLAT `jobs/<gate>-attempt-N/` layout the watchdog can scan (it reads only immediate children of the jobs root); without `--id` the supervisor would mint `job-<ts>` names and the fingerprint scan could not distinguish attempts — so a failed terminal job is never re-attached as the retry's result.
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (report assembly lines ~810-830) — background rows carry the job binding fields; report schema stays additive. Durable incremental checkpoint: as each gate COMPLETES, its row is also written to `<evidence_dir>/gates_rows/<gate>.json` (atomic tmp+mv); the final report assembly reads the in-memory rows as today AND treats existing row files as authoritative for gates it did not run in this invocation — this is what a rerun after a crash assembles from, and what resume writes into.
- Modify: `plugins/aid-orchestrator/scripts/aid-job.sh` (dispatcher region ~725-740) — new read-only subcommand `fingerprint -- <cmd...>` exposing the internal sha256-over-NUL-joined-argv computation (one definition, used by run internally and by the runner's re-attach check).
- Create: `plugins/aid-orchestrator/scripts/lib/aid-gate-row.sh` — the job-result→gate-row mapping as one sourceable function (duration composition, 124 synthesis, job binding fields), consumed by this step's poll loop and by Step 5's resume report patching (one definition, two callers).
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/p076/golden-gates-report.json` — the committed pre-P076 reference report captured from the fixture repo BEFORE this step's changes (volatile fields pre-normalized), consumed by this step's golden assertion and Step 16 phase 4.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-gate-background.bats` — a background gate produces a job record + result bound to start HEAD/tree and a gate row with job_id; a KILLED runner (SIGKILL mid-poll) leaves the job alive, and a rerun re-attaches (no second job dir, `gate_job_reattached` in the timeline) and completes the report; a background timeout maps to the existing fail + streak accounting; child processes of a cancelled background gate are dead (group-kill assertion via a spawn-children fixture); GOLDEN: a foreground-only execution.yaml produces a byte-identical gates_report to pre-P076 on the same fixture.

**Architecture Context:** Grounded facts F1/F2/F4/F7: the supervisor exists and is forbidden to be reimplemented (registry grep guard), the gate runner is the highest-value unowned site (bare `timeout`, no group kill, no record), and nothing in the pipeline calls aid-job today. The supervised-resumable-synchronous semantics are PM decision 5: the pain solved is dying-without-record, not blocking; re-attach mirrors the P074 transaction-resume shape.

**Implementation Detail:** Fingerprint computation is extracted from `aid-job.sh` into a shared helper (or invoked via a new `aid-job.sh fingerprint -- <cmd>` subcommand — implementation picks the smaller diff; either way ONE definition). The poll loop honours the deadline + 30 s grace before treating a still-running job as the runner's own timeout signal (the job's deadline timer is authoritative for killing). Re-attach validates the live job's recorded `start_head` against current HEAD: a mismatch (tree moved since the job started) does NOT re-attach — the stale job is cancelled, its dir archived to `.superseded-<epoch>` (freeing the deterministic id for the fresh start), and a fresh one starts, matching `collect --require-current` semantics.

**Error Handling:** `aid-job.sh` unavailable or its `run` fails: the gate fails loudly with the supervisor's stderr — never a silent fallback to the unowned foreground path (a background declaration is a contract). A `lost` job state (process vanished) maps to gate fail with `reason: job_lost` — a Step 13 ladder emitter.

**Edge Cases:**
- Two gates in one run with identical commands (same fingerprint): jobs dirs are keyed per gate name in the flat topology (`jobs/<gate>-attempt-N/`), so fingerprint re-attach never crosses gates.
- Rerun after the job completed while nobody watched: `collect` returns the terminal result idempotently; the gate row is built from it (no re-run of a finished suite — the crash costs zero re-execution).
- Baseline p95 absent (young gate): `--expect-p95` omitted; the job record simply lacks the field.
- `bats_boundary`'s 7200 s deadline: poll loop cadence stays 5 s; no timeout-related special case.

**Dependencies:**
- Depends on: Step 1

**Acceptance Criteria:**
- [ ] Kill-and-re-attach fixture passes: one job dir, `gate_job_reattached` logged, report completed without re-executing the suite.
- [ ] Group-kill fixture: zero surviving child PIDs after cancel/timeout.
- [ ] Golden foreground comparison byte-identical; timeout streak accounting unchanged on a background timeout.
- [ ] Every background gate row carries job_id + job_state; report schema validates.

**Effort:** L
**AID Role:** backend

### Step 3: The advisory event — one observe consumer for the baseline recommendation

**Objective:** When the baseline library recommends background for a gate that declares no `run_mode`, the runner says so once per run as a named timeline event containing the exact one-line edit — the first behavioural consumer of the recommendation, deliberately observe-only.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (baseline summary region, lines ~1110-1130) — alongside the existing stderr summary: for each gate where `gate_baseline_recommend_run_mode` returns `background` AND the gate has no explicit `run_mode`, emit `log_event "$timeline" "gate_run_mode_advice" gate="<name>" p95_ms=<n> edit="set gates.<name>.run_mode: background in .aid-o/config/execution.yaml"` — once per gate per run, observe-only, no behaviour change.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-run-mode-advice.bats` — a fixture baseline with p95 over threshold and no run_mode yields exactly one advice event with the exact edit string; an explicit `run_mode` (either value) suppresses it; under-threshold or under-sampled gates emit nothing.

**Architecture Context:** Grounded F5: the recommendation existed with zero behavioural consumers and the registry codified that as by-hand-only; Step 1 already updated that registry text. Observe-only is deliberate (the P069 observe-then-promote discipline): a consumer project's PM gets a loud, precise nudge from their own telemetry, and flipping stays a one-line human decision — the consumer-project story the PM required.

**Implementation Detail:** Reuses the existing per-gate baseline read at the summary site (no second baseline pass); the `edit=` string is built from the gate name only, so it is copy-pasteable in any project.

**Error Handling:** Baseline file unreadable: no advice, no failure (matching the baseline system's fail-open telemetry contract).

**Edge Cases:**
- Gate already backgrounded: suppressed (advice would be noise).
- Recommendation flips back to foreground after quieter samples: no reverse advice is emitted (removing a flip is a human judgment; the plan records this asymmetry deliberately).

**Dependencies:**
- Depends on: Step 1, Step 2

**Acceptance Criteria:**
- [ ] All three advice cases pass with the exact edit string asserted.
- [ ] Zero behaviour difference in gate execution with advice present (observe-only proven by the Step 2 golden fixture running with an advice-triggering baseline).

**Effort:** S
**AID Role:** backend

### Step 4: Eager continuation artifact and live controller state

**Objective:** Every background job start eagerly writes a single authoritative `auto_resume_required.json` (written BEFORE the job spawns, deleted on successful collect), and the active-runs entry carries `auto_controller` + `resume_artifact` fields through a new locked writer. `awaiting_host_resume` is a DERIVED state, never stored by a dying process: every consumer (status render, resume) computes it as "resume artifact exists AND no liveness signal within the stall threshold" — a dead controller cannot set anything, so the truth is derived from what it provably left behind; stored values cover only what a LIVE writer can set (active, manual, blocked_for_pm).

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/auto-resume-required.schema.json` — `aid-auto-resume/1`: required plan_id, epic_id, run_id, job_id (a job id OR the literal `pending` — the pre-spawn value, pattern-constrained), jobs_dir, gate, command_fingerprint (what the pending-recovery scan matches on), expected_terminal_states[], safe_next_action (exact command string; pattern forbids the `<` character), created_at; additionalProperties false — every field the two-phase write produces is declared, so the pending artifact validates.
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (background start site from Step 2) — ordering guarantees the pointer through EVERY crash window: the artifact is written (mktemp+mv) BEFORE `aid-job.sh run`, carrying `job_id: pending` plus the jobs_dir and gate name; immediately after the job starts it is atomically rewritten with the real job_id; `safe_next_action` is stored FULLY RESOLVED (the plugin path resolved at write time, the literal epic id — the schema forbids the `<` character in the field, so no placeholder can persist); on successful collect of the LAST outstanding background job: delete it and set `auto_controller: active`. Crash between write and start: resume finds `job_id: pending`, scans the jobs_dir by fingerprint, and reports truthfully (job found → collect; none → "no job was started — rerun run-all"). Crash between start and rewrite: the same fingerprint scan covers it.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (active-runs region, lines ~319-360) — new function `update_active_run_field <epic_id> <field> <value>` (same flock + atomic + fail-closed-on-corrupt discipline as `upsert_active_run`); the entry schema gains optional `auto_controller` and `resume_artifact`; `cmd_init` stamps `auto_controller` by EXTENDING `upsert_active_run` itself with the two optional fields (upsert replaces entries wholesale, so a separate post-init write would race it), and `update_active_run_field` serves all later changes.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-auto-resume-artifact.bats` — artifact appears at background start and validates against the schema; deleted after clean collect with `auto_controller` back to `active`; SIGKILL mid-run leaves artifact + map fields pointing at it; corrupt map still refuses clobbering (fail-closed regression); one artifact per run even with two sequential background gates (second start rewrites atomically, same path).

**Architecture Context:** The Codex round's blocking finding: continuation must not depend on a future watchdog loop that may never run — hence eager write at job start (grounded F6: a died-mid-EXECUTE controller is invisible today). One authoritative artifact + map fields holding only the pointer is the opponent's accepted simplification. `update_active_run_field` is the "live field needs a new writer" consequence of grounded F9 (map state is stamped-at-upsert today).

**Implementation Detail:** The artifact is per-run (one path), rewritten atomically when a new background job starts; `expected_terminal_states` lists aid-job's terminal vocabulary verbatim. Deletion happens only when no other live background job remains in the run's jobs dirs (checked via `aid-job.sh status` sweep, cheap).

**Error Handling:** Artifact write failure fails the background gate start AND compensates by cancelling the just-started job via `aid-job.sh cancel` (fail-closed WITH cleanup: an unresumable background job must not keep running — the accepted crash-window rule; a cancel failure is reported with the manual command). Map update failure warns (the artifact is authoritative; the map is presentation).

**Edge Cases:**
- Manual (non-auto) run with a background gate: artifact still written (resume is mode-independent); `auto_controller` stays `manual`.
- Artifact present from a previous crashed run when a new run starts: `cmd_init` refuses if the referenced job is still live (two controllers, one job — the named message points at `resume`); a dead referenced job lets init proceed and archives the stale artifact `.superseded-<epoch>`.
- `blocked_for_pm` state: set by the ladder terminus (Step 13), not by this step — field defined here, that writer lands there.

**Dependencies:**
- Depends on: Step 2

**Acceptance Criteria:**
- [ ] All five bats cases pass, including the SIGKILL pointer truth and fail-closed map regression.
- [ ] Background start with an unwritable evidence dir refuses before spawning the job.
- [ ] `cmd_init` live-job refusal names `resume`; stale artifact archived, not deleted.

**Effort:** M
**AID Role:** backend

### Step 5: The resume command — single-use, idempotent, honest

**Objective:** `aid-fsm.sh resume <epic_id>` claims the continuation artifact exactly once, collects the referenced job's terminal result, updates the map, and prints the verified state plus the exact next controller action — a mechanical core with an honestly instruction-only final hop.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (dispatcher region + new command function) — `cmd_resume <epic_id>`: locate the run's `auto_resume_required.json` via the active-runs entry (fallback: newest run evidence dir); check the referenced job: STILL RUNNING → read-only path, NO claim, artifact untouched (report state + remaining deadline; the artifact stays valid for the next resume — one code path, no re-arm dance); TERMINAL → claim the artifact single-use (`mv` to `.claimed-<epoch>` with the mv -n + source-gone post-check pattern), `collect`, write the gate row to the durable `gates_rows/<gate>.json` checkpoint via `lib/aid-gate-row.sh` (Step 2's incremental-row mechanism — the next run-all assembles it into the report; resume never edits a final report in place), update `auto_controller`, print a three-line summary (what was found, what is recorded, the next action). The claim therefore happens exactly when a result is consumed — never for a status look. Second invocation with no artifact: report current state from the map + jobs dir, exit 0 (idempotent, no claim).
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~44-62) — the AUTO contract's "resume or diagnose" sentence now names the mechanical path: artifact, then `resume`, then the printed next action; explicitly classified: executing the printed action is the controller's turn (instruction), everything before it is mechanical.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~33-69) — same mechanical-path naming and classification in the AUTO section.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-resume-command.bats` — resume after SIGKILL collects the finished job, updates report + map, prints the next action, and the artifact is claimed exactly once (parallel double-resume race: one winner via mv -n + post-check, loser reports already-claimed); resume with the job still running is a READ-ONLY status report — the artifact is untouched and still claimable later (asserted: two consecutive running-state resumes see the same artifact bytes; the claim fires only on the terminal-collect path), so a later resume still works (asserted — the live-job-has-exactly-one-artifact invariant holds through the claim); resume with no artifact is an idempotent status report.

**Architecture Context:** The Codex round's blocking finding 2: resume must be classified honestly — it cannot execute the controller's next turn, so its contract is mechanical-collection + truthful print. The claim primitive is the shipped pm-override single-use pattern (grounded F9); the running-job re-arm (claim, then rewrite pointing at the same job) keeps the invariant "a live background job always has exactly one artifact".

**Implementation Detail:** Report patching sources `lib/aid-gate-row.sh` (Step 2's shared job-result → gate-row mapping — one definition, two callers). Single-writer rule, stated: the gates report is written by exactly one process — the live runner when one exists, `resume` only for a dead controller; `resume` therefore refuses to patch when `aid-job.sh watchdog` reports a live job AND the run's timeline shows a heartbeat within the stall threshold (a living runner owns the report; resume then only prints status). The 60 s courtesy poll makes the common case (resume typed just after the suite finished) one command instead of two; the still-running branch prints remaining deadline from the job record.

**Error Handling:** Referenced job dir missing entirely (evidence wiped): claim proceeds, the command reports `job records missing — the run cannot prove the gate result; rerun the gate` and sets `auto_controller: active` (truthful dead end, never a fabricated result).

**Edge Cases:**
- Resume invoked from inside the plan worktree or the primary checkout: state resolution via aid-roots (P074) makes both work; asserted.
- Artifact references a job whose result is `stale` (tree moved): reported verbatim with the rerun instruction — stale is never patched into the report as current evidence.
- Two different EPICs each with artifacts: resume takes the epic_id argument; no cross-EPIC ambiguity.

**Dependencies:**
- Depends on: Step 4

**Acceptance Criteria:**
- [ ] Race fixture: exactly one claim winner; loser output names the winner's claim file.
- [ ] Running-job resume keeps exactly one live artifact; finished-job resume writes a row file identical to the in-line path's (diff-asserted), and the subsequent run-all assembles it into the report.
- [ ] No-artifact resume is idempotent exit 0; stale result never enters the report as current.

**Effort:** M
**AID Role:** backend

### Step 6: Watchdog wiring and visible stalls

**Objective:** The controller loop has a mechanical liveness step — `aid-job.sh watchdog` consulted each loop with `resume_needed` routed into the recovery ladder — and a dead controller's run becomes VISIBLE: status marks entries stalled when their state file is live but nothing has progressed.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (AUTO controller loop checklist, lines ~33-69) — the loop gains the explicit step: after each dispatch/gate action, run `aid-job.sh watchdog --jobs-dir <run jobs dir> --last-progress <last timeline event epoch>`; `busy` → continue polling; `resume_needed` → enter the ladder as JOB_LOST or TRANSIENT_INFRA per the newest job record's state (Step 13 consumes this).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (prune_active_runs region, lines ~396-450) — STALLED is DERIVED at read time, exactly like awaiting_host_resume (nothing depends on prune running): a consumer (the status render, the watchdog loop step) computes it as "non-terminal entry AND the NEWER of map `updated_at` and the run timeline's last event timestamp is older than the threshold (default 2100 s, env-overridable)" — Step 2's `gate_job_heartbeat` therefore counts as progress. `prune_active_runs` gains no flag-writing duty (it keeps its existing removal criteria); the derivation rule lives in one sourceable helper both consumers share.
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` (overview render, lines ~40-80) — stalled entries render with a `STALLED?` marker + the resume command; the byte-locked fixture updates in the same commit (Step 15 carries the full render sweep; this step updates only the stalled row case).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-watchdog-stall.bats` — the shared derivation helper flags an aged non-terminal entry (map data untouched); a fresh entry and one with a recent timeline heartbeat are not flagged; a stalled-derived entry with an artifact renders the resume command; terminal entries still prune as today (regression).

**Architecture Context:** Grounded F6: three detectors exist, none resumes, and prune's file-existence criterion keeps a died-mid-EXECUTE controller invisible forever — the exact gap. The Codex round accepted stalled-flagging as visibility (not continuation) with the eager artifact (Step 4) as the actual continuation guarantee; the watchdog stays a query the controller calls (no daemon — Alternative B rejection).

**Implementation Detail:** `--last-progress` is derived from the run's timeline.jsonl mtime/last event ts (cheap, no new bookkeeping). The stall threshold (2100 s) deliberately sits ABOVE the shipped 1800 s dispatch-deadline clamp so a stall flag never races a dispatch pinned exactly at the clamp.

**Error Handling:** watchdog invocation failure inside the loop is logged and skipped (the loop step is belt-and-braces around the eager artifact; its absence must not block gates).

**Edge Cases:**
- A stalled-derived entry whose controller wakes and continues: the next map write or timeline event refreshes the newer-of-two signal, so the derivation flips back by itself (no stored flag to clear).
- A long FOREGROUND gate in a consumer project (no heartbeat possible without changing the byte-identical path): a false STALLED marker is possible past 35 min — the render text says so honestly ("if a long foreground gate is running this is expected; consider run_mode: background"), documented as the deliberate trade of decision 1A.
- Runs with no jobs dir (pure-foreground legacy runs): watchdog reports no live jobs; `resume_needed` only fires when `--last-progress` says idle — routed to diagnosis, not to a job collect.
- A legitimately long background-gate poll (the runner alive, emitting timeline events while polling): last-progress stays fresh because the poll loop logs a heartbeat event every 60 s, so the stall flag never fires on a healthy long wait (heartbeat asserted in the Step 2 suite).

**Dependencies:**
- Depends on: Step 4

**Acceptance Criteria:**
- [ ] Stall fixture passes: flag set, data kept, resume command rendered, cleared on next live write.
- [ ] Terminal-prune regression byte-identical.
- [ ] pipeline.md loop checklist names the watchdog step with both routing outcomes.

**Effort:** M
**AID Role:** backend

### Step 7: Instruction closure for EPIC 1

**Objective:** The Controller-boundary/no-detach contract becomes one shared section every agent card references, the AUTO surfaces describe the `auto_controller` states and the honest host card before work starts, and the context-prose prohibition gains its explicit carve-out.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` (new section after Script Execution, lines ~255-265) — the shared "Controller boundary" section (verbatim content of implementer.md:13-27: no detach/nohup/tail -f, async handoff shape, no stale results) now lives here once.
- Modify: `plugins/aid-orchestrator/agents/implementer.md` (lines ~13-27) — the section shrinks to a two-line reference to agent-protocol.md (content moved, not duplicated).
- Modify: `plugins/aid-orchestrator/agents/verifier.md` + `plugins/aid-orchestrator/agents/gate-fixer.md` + `plugins/aid-orchestrator/agents/auditor.md` + `plugins/aid-orchestrator/agents/curator.md` + `plugins/aid-orchestrator/agents/simplifier.md` + `plugins/aid-orchestrator/agents/reporter.md` + `plugins/aid-orchestrator/agents/project-scanner.md` + `plugins/aid-orchestrator/agents/test-portfolio-analyst.md` — each gains the same two-line reference (grounded F8: today only implementer carries the contract; the directory holds nine cards and the dynamic grep test counts all of them).
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~41-62 AUTO contract, ~120-124 context-prose rule) — `--auto` documents the four `auto_controller` states and the resume flow before starting work (the D24 requirement); the "do NOT pause" rule gains: "The one legitimate turn-ending message is the awaiting_host_resume card: the artifact exists, the resume command is printed, and nothing false is claimed."
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` (auto-mode topic region) — one paragraph: what background gates mean, what `resume` does, what the states mean.
- Test: `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` — run over all modified cards/skills (verification, not modification); plus a grep test in `plugins/aid-orchestrator/scripts/tests/bats/test-instruction-closure.bats` asserting every agent card (all nine, dynamically enumerated) references the shared section and none carries a divergent copy.

**Architecture Context:** Grounded F8 (six of seven agent cards silent on detach) and F10 (the context-prose prohibition would contradict the honest card without a carve-out). One shared section with references is the anti-kočkopes rule applied to instructions themselves.

**Implementation Detail:** The card text for `awaiting_host_resume` follows §14 D17 card 3 (Zastaveno / Dopad / Doporučené řešení / the exact resume command) — the shape only; full §14 renderer work stays out of scope.

**Error Handling:** Not applicable (documentation step); the grep test is the enforcement that references exist.

**Edge Cases:**
- Future agent cards: the grep test enumerates the agents directory dynamically, so a new card without the reference fails the suite (the closure stays closed).
- Consumer projects with cached plugin cards: the standard plugin-update path applies; no special handling.
- A card QUOTING the boundary contract inside an example block: the grep test keys on the reference marker line, not on contract phrases, so quoted examples never satisfy or trip the check.

**Dependencies:**
- Depends on: Step 5

**Acceptance Criteria:**
- [ ] Grep suite passes: 9/9 cards reference the shared section; zero divergent copies.
- [ ] Skill lint clean over every modified file.
- [ ] aid-run.md documents all four states + the carve-out sentence; aid-help.md carries the paragraph.

**Effort:** M
**AID Role:** docs-writer

**EPIC 2: Steps 8-13 — Service Readiness and the Recovery Ladder**

### Step 8: Service declarations in execution.yaml

**Objective:** execution.yaml accepts an optional `services:` map with a fully specified per-service contract, absent block means byte-identical behaviour, and the template documents it for every consumer project.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` (new documented block after the gates section) — `services:` syntax: per service `start_cmd` (must remain the foreground process of its job), `probe_cmd` (exit 0 = healthy), `stop_cmd`, `startup_deadline_seconds` (the health-probe budget: absent→starting must reach healthy within it), `max_lifetime_seconds` (the aid-job whole-process deadline, default 86400 — a run-lifetime ceiling deliberately SEPARATE from the startup budget, closing the dual-role ambiguity), `log_hint`, `restart_authorized: true|false`, `port_env` (the env var carrying the allocated per-run port); the template ships the block as commentary with one worked example, no active service.
- Create: `plugins/aid-orchestrator/defaults/schemas/service-declaration.schema.json` — the map's shape; `start_cmd`/`probe_cmd`/`startup_deadline_seconds` required per service, the rest optional with defaults (`restart_authorized: false`); additionalProperties false.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-service-declaration.bats` — a valid block parses; a service missing probe_cmd fails schema validation naming the field; an execution.yaml with no services block behaves byte-identically at the runner (golden reuse from Step 2); the template contains the commentary example and zero active services.

**Architecture Context:** Grounded F1 (Pillar 2): AID starts no service anywhere; the e2e role card's "Infrastructure startup" is prose with no mechanism and a no-sleep rule with no alternative. Declarations live in execution.yaml because that is the per-project gate/runtime contract every project already owns — the consumer story is automatic (VULCAN declares postgres, this repo declares nothing).

**Implementation Detail:** Validation is a NAMED implementation with a named hook: `aid-run-gates.sh` gains `_validate_services_config` (bash + yq/jq checks mirroring the schema: required fields, enum values, duplicate-port_env refusal) invoked at `run_all` entry BEFORE any service or gate action; the schema.json file is the documentation + bats authority, the bash validator is the runtime enforcement — both asserted equivalent by a shared fixture set. `port_env` is optional: a service with a fixed external port (existing shared database) declares no port_env and the lib skips allocation for it (documented as the shared-resource escape hatch, honestly named).

**Error Handling:** Schema violation fails the runner before any gate or service action, naming service and field.

**Edge Cases:**
- Service with `restart_authorized` absent: defaults false (repairs are opt-in authority, per §16 D23).
- `stop_cmd` absent: teardown relies on job cancel alone (group kill); documented as acceptable for processes without external state.
- Two services declaring the same port_env name: schema-level uniqueness check refuses (one env var, one owner).

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] All schema cases pass including the duplicate-port_env refusal.
- [ ] No-services golden byte-identical.
- [ ] Template commentary block present with zero active services.

**Effort:** S
**AID Role:** backend

### Step 9: lib/aid-service.sh — readiness over owned jobs

**Objective:** One thin sourceable lib brings declared services up and down through `aid-job.sh`: per-run port allocation with one reallocation retry, 1 s health probing to healthy or deadline, deadline means cancel plus stop, a flocked per-run registry that stop/probe/restart read ports back from, the foreground start_cmd contract enforced, and exactly one authorized restart cycle.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-service.sh` — functions `aid_service_up_all <run_evidence_dir>` (for each declared service: allocate a free port by bind-probe when port_env is declared, export it, start via `aid-job.sh run --jobs-dir <evidence>/service-jobs/<name>/ --deadline <max_lifetime_seconds> -- bash -c "<start_cmd>"`, poll probe_cmd every 1 s until exit 0 or startup_deadline_seconds; the registry write is EAGER and two-phase: `{service, run_id, port, state: starting}` is written to `<evidence>/services.json` (flock + atomic tmp+mv) BEFORE the job spawns, updated with `job_id` immediately after spawn, and flipped to `healthy` after the probe — so a crash in any window leaves a registry entry every teardown path can see; belt-and-braces, the sweep (in `aid_service_down_all` and its callers) enumerates `<evidence>/service-jobs/<name>/*/job.json` — the supervisor's documented one-job-one-dir layout — and for each found id calls `aid-job.sh status --jobs-dir <evidence>/service-jobs/<name>/ --id <dirname>` (status has NO list mode; enumeration is the caller's job, per-id queries are the supervisor's), cancelling any live job without a registry entry (cancel + log), `aid_service_down_all` (per service: `aid-job.sh cancel` + stop_cmd best-effort with the recorded port re-exported, registry state → stopped), `aid_service_status <name>` (job state + one probe run, port read from the registry never re-derived); states exactly `absent → starting → healthy | unhealthy | timed_out | lost`; startup-deadline or unhealthy-after-restart → cancel + stop + named failure; `restart_authorized: true` permits exactly ONE recorded cancel+restart cycle; a TERMINAL job whose probe still reports healthy is the daemonized-start_cmd violation → named refusal `start_cmd must remain its job's foreground process`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-service.bats` — a fixture service implemented with a python3 one-line listener (bash `/dev/tcp` is connect-only — it can neither LISTEN nor truly bind-probe, empirically verified; python3 joins yq/jq in the named-skip list when absent) goes absent→starting→healthy with the allocated port recorded; a SIGKILL between job spawn and the healthy flip leaves a `starting` registry entry that down_all cancels (the accepted crash-window case, orphan-free asserted); port collision (pre-bound port) triggers exactly one reallocation then success; deadline expiry cancels the job AND runs stop_cmd (no live orphan — asserted by process sweep); unhealthy with restart_authorized restarts once then fails named; daemonizing start_cmd fixture hits the named refusal; down_all reads the recorded port (env cleared beforehand to prove registry read-back); registry survives two concurrent up/status calls (flock assertion).

**Architecture Context:** Grounded F1-F3 (Pillar 2): zero readiness code exists; the resource-map vocabulary and the scheduler's owner-cancels-children pattern are the precedents; the no-second-supervisor boundary makes aid-job the only process owner (the service job IS the ownership record); the state root is deliberately shared, so the registry is per-run-keyed in evidence, not in the worktree. All four Codex blocking findings for this pillar land here: registry locking, deadline-cancels, port-race single-retry, foreground start_cmd contract.

**Implementation Detail:** Port allocation: `python3 -c` transient socket bind (the ONLY genuine bind-probe available — bash `/dev/tcp` is connect-only and a connect-scan cannot prove bindability; python3 is therefore a declared dependency of the services feature, named-skip in tests and a named refusal at `aid_service_up_all` when absent while a port_env service is declared); the race window between release and service bind is closed pragmatically: if the started service's probe fails AND its log/stderr matches bind-failure, ONE reallocation with a fresh port; a second collision is a named failure (honest best-effort, documented). Probe interval fixed 1 s (Codex simplification — no adaptive polling, no startup_p95 field).

**Error Handling:** `aid-job.sh` failures propagate verbatim behind a `service <name>:` prefix. A registry write failure fails the up (a service without its record is unmanageable — fail-closed, mirroring Step 4's artifact rule).

**Edge Cases:**
- Service healthy but its job later `lost` (supervisor lost the process): status reports lost; the ladder (Step 13) owns the response; down_all still runs stop_cmd with the recorded port.
- up_all invoked twice in one run (rerun after crash): existing healthy registry entries are verified by one probe and reused — idempotent, no double start (mirrors Step 2's re-attach).
- No services declared: all three functions are cheap no-ops returning 0.

**Dependencies:**
- Depends on: Step 8

**Acceptance Criteria:**
- [ ] All seven bats scenarios pass, including orphan-free deadline teardown and the daemonize refusal.
- [ ] Idempotent rerun reuses healthy services (no second job dir).
- [ ] Registry is the sole port source for stop/status (env-cleared assertion).

**Effort:** L
**AID Role:** backend

### Step 10: Service lifecycle wired into the run

**Objective:** Services are acquired once before the gate loop and released once in run-final cleanup with a done-advance safety net; a gate's `needs_services` only fail-fasts on unhealthy; the e2e role card's infrastructure prose becomes an instruction to use the lib; the per-run service ports land as observe-only evidence.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (run_all entry ~560-585 and final cleanup/report region ~1090-1110) — before the gate loop: `aid_service_up_all` when the config declares services (failure = the whole run fails before any gate, named); per gate with `needs_services: [names]`: verify each is healthy in the registry, else fail that gate fast with `reason: service_unhealthy`; after the report is written (pass or fail): `aid_service_down_all` (release-once — never per gate, per the Codex parallel-teardown finding).
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (run_all entry, same region as the acquire) — the crash safety net lives where crash recovery actually happens: a RERUN of `run-all` sweeps stale service state at entry (before acquire — `aid_service_down_all` for non-stopped registry entries plus the unregistered-job enumeration; the idempotent up_all then reuses or restarts cleanly), because a SIGKILLed runner can never reach any completion hook.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (cmd_resume from Step 5, plus done-advance completion region) — `resume` runs the sweep ONLY on its terminal-collect path (a dead run being wrapped up); its running-job path is fully read-only INCLUDING services — a live background gate may depend on a declared service, and sweeping it would kill the very dependency the surviving job needs. done-advance keeps a last-resort sweep for completed-but-uncleaned runs; all three callers use the one `aid_service_down_all` path.
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` (e2e card, lines ~210-245) — "Infrastructure startup" rewritten: declare services in execution.yaml and use the lib (the no-arbitrary-sleeps rule finally names its alternative: probe_cmd); manual docker prose demoted to the no-declaration fallback.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-service.sh` (evidence emission, small addition) — on reaching healthy, append `{kind: external_service, namespace: per-run, id: "<name>:<port>"}` to `<evidence>/service-resources.jsonl` — observe-only evidence filling the schema's unclaimed slot; the resource-map classifier is NOT touched (deferred, IMP entry in Step 14).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-service-lifecycle.bats` — a two-gate run with one declared service: up once, both gates see healthy, down once (job dir count asserted); a gate with needs_services on an unhealthy service fails fast with the named reason while other gates run; runner SIGKILLed mid-gates → the NEXT run-all rerun's entry sweep (and equally a resume call) cancels the stale service before re-acquiring (no orphan; done-advance is NOT the crash path — it can never run after a mid-gates kill); the evidence JSONL appears with the per-run port.

**Architecture Context:** The acquire-once/release-once shape is the Codex round's accepted fix for the parallel-teardown race (two gates sharing a service, one tearing it down under the other). The done-advance net mirrors the P074 teardown philosophy: terminal operations sweep, never block. Observe-only evidence is PM decision 3.

**Implementation Detail:** `needs_services` is a per-gate optional list validated against declared service names at config check (unknown name = config error, loud). The safety net reuses `aid_service_down_all` verbatim (one teardown definition).

**Error Handling:** down_all failure at cleanup: warning with the manual commands (stop_cmd + `aid-job.sh cancel` lines) — the report is already written; cleanup never un-writes evidence.

**Edge Cases:**
- Service declared but no gate needs it: still up/down with the run (declared = wanted for the run; a per-gate-only future mode is not in scope).
- needs_services under `run_mode: background` gates: the health check happens at gate start in the runner (before job spawn) — the service registry read is cheap.
- Legacy execution.yaml without services: zero calls, golden-identical (Step 8 assertion reused).

**Dependencies:**
- Depends on: Step 9

**Acceptance Criteria:**
- [ ] Two-gate lifecycle fixture: exactly one up, one down; fail-fast case named; safety-net sweep proven orphan-free.
- [ ] Unknown needs_services name refused at config validation.
- [ ] e2e card names the lib and the probe alternative; evidence JSONL asserted.

**Effort:** M
**AID Role:** backend

### Step 11: auto-recovery.yaml — one machine-readable recovery policy

**Objective:** Recovery policy becomes one shipped file: seven stop classes with named emitters and honest detector labels, allowed reversible actions, attempt and wall-clock budgets, the ownership table declaring every existing retry loop, and the adjudication → escalation → force terminus; the dangling permissions-defaults reference and the July stop-taxonomy document are reconciled to it.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/policies/auto-recovery.yaml` — `stop_classes:` GATE_TIMEOUT (emitter: run-gates timeout/streak path, detector: mechanical), SERVICE_UNHEALTHY (aid-service probe/restart exhaustion, mechanical), JOB_LOST (aid-job state lost, mechanical), TRANSIENT_INFRA (C0/C3 dispatch unavailable/rate_limited/timeout outcomes, mechanical), DISPATCH_ORPHANED (fsm_check_orphan_dispatches die site, detector: instruction — the die message names the ladder entry), REVIEW_EXHAUSTED (C0/C3/CP1 budget exhaustion paths, mechanical), UNCLASSIFIED (default, routes straight to adjudication); per class `allowed_actions:` drawn from {wait_and_resume, retry_once, restart_service_once, rerun_targeted, resume_missing_lenses, collect_and_continue}, `budget: {attempts, wall_clock_seconds}`, `terminus: adjudicate → escalation → pm_force`; `existing_loops:` ownership table — gate fix loop (3/check), CP2 (2), C3 (4), C0 (4), gate max_retries — each `authority: existing`, budget location cited, explicitly NOT governed by the ladder.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~31-39) — the S/M/L tier text's "use default decision from `config/permissions.yaml`" (keys that do not exist — grounded F5) is rewritten to point at auto-recovery.yaml as the defaults authority; the tier prose stays, its mechanical backing is now real.
- Modify: `docs/plans/2026-07-21-IMP-auto-mode-stop-taxonomy-and-recovery-policy.md` (section headers of the replaced parts only) — superseded-by-P076 markers on the stop-class table and decision-vocabulary sections; the deferred CLI sketches (`resume-incomplete-gates`, `wait-and-resume`) are annotated as partially delivered (resume, ladder) with the remainder listed still-open there.
- Create: `plugins/aid-orchestrator/defaults/schemas/auto-recovery.schema.json` — the policy shape; every class requires emitter, detector + ladder_entry labels, allowed_actions (enum-constrained to the six defined action names — an unknown action is a schema error, never a silent no-op), budget, terminus.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-auto-recovery-policy.bats` — shipped policy validates against its schema; every emitter named in the policy greps to a real code site (the anti-decoration assertion); the existing_loops budgets match the live values in their cited files (drift test: C3 max_rechecks 4, ledger MAX_ATTEMPTS 5, gate fix 3); UNCLASSIFIED has no allowed_actions except adjudicate.

**Architecture Context:** Grounded F4/F5 (Pillar 2): the ladder is over-specified in prose across three documents with no mechanical owner, and the cited defaults keys do not exist; the July document is reconciled per the Codex round (only replaced sections superseded, vocabulary preserved). The declared-not-rewired ownership table is PM decision 4 — one table of truth, zero risky rewiring.

**Implementation Detail:** Detector labels are honest per the Codex round and split into TWO axes recorded per class: `detector:` (is the condition detected by code?) and `ladder_entry:` (does code write the ladder record, or does the AUTO-loop instruction route it?). GATE_TIMEOUT, JOB_LOST, and SERVICE_UNHEALTHY are mechanical on both axes (Step 13 writes their entries in code); TRANSIENT_INFRA and REVIEW_EXHAUSTED are `detector: mechanical, ladder_entry: instruction` (their C0/C3/CP1 code sites detect and report, the AUTO-loop instruction routes them into the ladder); DISPATCH_ORPHANED is instruction on both (the die message names the entry command). The drift test is the enforcement that keeps the ownership table truthful as budgets evolve.

**Error Handling:** Malformed project override of the policy (consumer copies it into .aid-o): loader falls back to shipped defaults with a named warning (fail-closed to known-good policy, matching the P073 ancillary-policy pattern).

**Edge Cases:**
- A class fires with zero remaining budget on entry: straight to adjudication (budget zero is legal configuration, not an error).
- Consumer project deletes a class from its override: loader treats missing classes as UNCLASSIFIED routing (never silently no-recovery).
- Two plans running concurrently in one project (P074 worktrees) with different override needs: the policy is project-scoped by design — per-plan overrides are refused at load with a named message (one project, one recovery policy).

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] Policy validates; every emitter greps to a live site; drift test pins the three existing budgets.
- [ ] aid-run.md no longer references nonexistent permissions keys (grep-asserted).
- [ ] July doc carries section-scoped supersede markers only (its untouched sections free of markers).

**Effort:** M
**AID Role:** backend

### Step 12: The adjudication lib — the temporary convention formalized

**Objective:** `lib/aid-recovery-adjudicate.sh` implements the dispatch convention aid-run.md already prescribes verbatim: fact pack in, one allowlisted action out, mechanical validation with one retry then escalation, timeline-recorded — with the authority ceiling enforced by construction.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-recovery-adjudicate.sh` — `aid_recovery_adjudicate <run_evidence_dir> <stop_class> <facts_file>`: builds the prompt pack (verified facts, current FSM state via get-state, the ladder record so far, the class's allowed_actions from auto-recovery.yaml as an explicit allowlist, the forbidden list: any authority-expanding action); dispatches through the existing isolated Codex transport (the aid-c3-dispatch transport function, reused not reimplemented); validates the reply names exactly one action IN the allowlist plus a rationale (reject otherwise, ONE retry with the rejection quoted, then return `escalate`); appends `{class, action, rationale, ts}` to timeline.jsonl and the ladder record; prints the selected action.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~75-80) — the "temporary dispatch convention" paragraph is replaced by the lib invocation (the convention text moves into the lib's header as its specification).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-recovery-adjudicate.bats` — with a stubbed transport: an in-allowlist reply is accepted and recorded; an out-of-allowlist reply is rejected once, a second bad reply returns escalate; the prompt pack contains the allowlist and the forbidden list verbatim (fixture-asserted); transport unavailability returns escalate (never a silent pass); the timeline entry shape is pinned.

**Architecture Context:** Grounded F4: aid-run.md:75-80 already specifies exactly this ("explicit allowlist of reversible in-scope actions... Reject an answer outside the allowlist... append to timeline") as a temporary convention — this step is codification, not design. The ceiling (adjudicator cannot grant PM authority, :72-73) is enforced by construction: the allowlist never contains authority-expanding actions, and the validator rejects everything else.

**Implementation Detail:** Transport reuse: the same isolated dispatch function the C3 bridge uses, with a distinct artifact prefix (`recovery-adjudication-<ts>.json` in run evidence) storing prompt hash, raw reply, and verdict — auditable like every Codex exchange in the system.

**Error Handling:** Facts file missing/empty: refuse before dispatching (an adjudication without facts is theater). Codex transport failure: `escalate` with the transport error attached.

**Edge Cases:**
- Reply names an allowed action plus extra prose: accepted if exactly one action token parses; two action tokens = reject (ambiguity).
- UNCLASSIFIED class: allowlist is empty by policy → the lib short-circuits to escalate without dispatching (asserted).
- A syntactically valid but EMPTY reply (no action token at all): treated as out-of-allowlist — one retry quoting the emptiness, then escalate (never interpreted as consent).

**Dependencies:**
- Depends on: Step 11

**Acceptance Criteria:**
- [ ] All five stub cases pass; prompt pack contents pinned; artifact written per exchange.
- [ ] aid-run.md paragraph replaced by the lib reference; convention text present in the lib header.
- [ ] Empty-allowlist short-circuit asserted.

**Effort:** M
**AID Role:** backend

### Step 13: The ladder — record, budgets, emitters, terminus

**Objective:** Every recovery attempt lands in a per-run ladder record, over-budget actions are refused fail-closed into adjudication then escalation, the named emitters actually enter the ladder, and the terminus wires into the existing ESCALATION decision field and the P073 force surface.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-recovery-ladder.sh` — `aid_ladder_attempt <run_evidence_dir> <stop_class> <action>`: loads the class from auto-recovery.yaml; refuses an action not in allowed_actions (named); counts prior attempts of the class in `<evidence>/recovery-ladder.jsonl` against `budget.attempts` and wall-clock; within budget → records `{class, action, attempt_n, ts, outcome: started}` and returns 0 (the caller performs the action, then records the outcome via `aid_ladder_outcome`); over budget → records `budget_exhausted` and returns the adjudicate signal; adjudication returning escalate → the caller routes to the ESCALATION state whose transition already mechanically requires `escalation_decision`, and the map gains `auto_controller: blocked_for_pm` (the Step 4 field's writer); continuation past a refused terminal state is exactly the P073 `--force` surface — never a ladder bypass.
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (timeout/streak path lines ~707-727 and the job-lost mapping from Step 2) — both emit their class entry (GATE_TIMEOUT, JOB_LOST) into the ladder record when running under a run evidence dir (mechanical emitters); the existing behaviour (fail + streak + policy block) is unchanged — the ladder records and routes, it does not replace the gate verdict.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-service.sh` (restart-exhaustion path) — emits SERVICE_UNHEALTHY (mechanical).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (fsm_check_orphan_dispatches die message, lines ~1240-1246) — the message additionally names the ladder entry command (instruction-labelled emitter per the policy; the die semantics unchanged).
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (AUTO loop from Step 6) — `resume_needed` and C0/C3 `unavailable` outcomes route via `aid_ladder_attempt` with their classes (TRANSIENT_INFRA/JOB_LOST); REVIEW_EXHAUSTED routes to adjudication-then-escalation per the policy.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-recovery-ladder.bats` — within-budget attempt records and returns 0; the budget-th+1 attempt refuses with budget_exhausted and the adjudicate signal; a disallowed action for the class refuses named; wall-clock budget expiry refuses even with attempts remaining; the GATE_TIMEOUT emitter writes a ladder entry on a timeout fixture while the gate verdict stays identical; escalate outcome sets blocked_for_pm in the map.

**Architecture Context:** Grounded F6 (Pillar 2): budgets exist per-mechanism with no unified record; the ESCALATION decision field is the mechanically enforced sink; P073 force is the terminus (fail-closed waiver receipts). The Codex round's missing-wiring findings land here: named emitters per class (with honest labels) and the explicit non-rewiring of existing loops (they keep their budgets; the ladder only RECORDS their exhaustion as REVIEW_EXHAUSTED for visibility and terminus routing).

**Implementation Detail:** The ladder record is append-only JSONL, and the budget check + append happen under one `lib/aid-lock.sh` flock on the record's sidecar (closing the two-concurrent-attempts TOCTOU — count and write are one critical section). Wall-clock budget is measured from the class's first entry in the record. `restart_service_once` is not a free action: it delegates to aid-service's restart path, which enforces `restart_authorized` and the one-cycle limit (a ladder action can never smuggle authority the service declaration withheld).

**Error Handling:** Policy unreadable at attempt time: fail closed to `adjudicate` (a broken policy must not permit unbounded retries).

**Edge Cases:**
- Two different classes interleaving in one run: budgets are per class; the record keeps both threads legible (class field on every line).
- A ladder action that itself starts a background job (rerun_targeted): the job routes through Step 2's machinery — the ladder never spawns unsupervised work.
- Manual (non-auto) runs: emitters still record (evidence value); routing to adjudication happens only under auto (manual = the human IS the adjudicator; documented).

**Dependencies:**
- Depends on: Step 4, Step 6, Step 9, Step 12

**Acceptance Criteria:**
- [ ] All six ladder cases pass; gate verdict invariance on the emitter fixture proven.
- [ ] blocked_for_pm lands in the map on escalate; ESCALATION transition still requires the decision field (regression).
- [ ] Every class with `ladder_entry: mechanical` (GATE_TIMEOUT, JOB_LOST, SERVICE_UNHEALTHY) has a bats-pinned code write; the instruction-routed classes are asserted present in the AUTO-loop checklist text and the DISPATCH_ORPHANED die output names the entry command.

**Effort:** L
**AID Role:** backend

**EPIC 3: Steps 14-17 — Closure**

### Step 14: The deferred-work registry

**Objective:** Every consciously deferred item from this plan exists as a numbered IMP entry in the project backlog, cross-referenced from the source document's STILL OPEN block — nothing survives only in chat or plan prose.

**Files:**
- Modify: `docs/plans/2026-06-29-BACKLOG.md` (IMP table) — five new entries with the next free IMP numbers: fire-and-return ASYNC gates (runner returns before completion; supervised-synchronous shipped by P076 Step 2); services-to-resource-map classifier integration (observe-only JSONL shipped by Step 10); foreground-gate `timeout -k` hardening (option 1B, foreground kept byte-identical); visual-companion server migration onto lib/aid-service.sh; host push-continuation adapter (task-notification behaviour as a verified mechanism rather than instruction-only guidance). Each entry: what shipped instead, why deferred, where the hook point is (file:line of the P076 mechanism it would extend).
- Modify: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` (§16 STILL OPEN block) — each still-open line gains its allocated IMP number (verification that the promise "each registered as an IMP backlog entry" is literally true).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-p076-backlog-closure.bats` — greps: every §16 STILL OPEN line carries an IMP-number token; every named IMP number exists in the backlog file; the five entries name their hook points.

**Architecture Context:** The PM's binding addition 1 (2026-08-08): deferred work must be durably registered, following the repository's existing IMP convention (the backlog file that already carries IMP-469/470).

**Implementation Detail:** IMP numbers are allocated at implementation time from the backlog's current maximum (the plan deliberately does not guess numbers); the bats test keys on cross-reference consistency, not specific values.

**Error Handling:** Not applicable beyond the test's consistency enforcement.

**Edge Cases:**
- An item delivered early (before this step runs) by parallel work: its entry is written as already-delivered with the commit reference instead of being silently dropped (the registry records decisions, not just futures).
- Backlog file format drift: the test asserts token presence, not table layout.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] Five IMP entries exist with hook points; §16 lines cross-reference them; bats closure test passes.
- [ ] The bats closure test enumerates exactly five IMP tokens in the §16 STILL OPEN block and finds each in the backlog (a count assertion — executable, no gitignored input; the interim cross-check is an implementation-review activity, not an acceptance criterion).

**Effort:** S
**AID Role:** docs-writer

### Step 15: Status surfaces — the four states rendered

**Objective:** `/aid-status` renders `auto_controller` for every active run (superseding the bare Mode line), stalled and awaiting-resume entries show their exact resume command, and the byte-locked two-stream fixture is updated in the same change.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` (overview render lines ~40-80 and per-EPIC detail lines ~465-490) — the overview row renders the auto_controller value — with `awaiting_host_resume` AND `STALLED?` both DERIVED at render time via the shared Step 6 helper (artifact-present and no-progress rules; the render never depends on prune having run) — each rendering the resume command verbatim; the detail view's `Mode:` line becomes `Controller: <auto_controller> (mode: <mode>)`.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-status-two-streams.bats` (byte-locked fixture) — fixture output updated to the new rows; one added case: a run with a live resume artifact renders the command; a stalled entry renders the marker.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-status-two-streams.bats` — the updated byte-for-byte comparison passes; legacy entries without the new fields render with `Controller: active (mode: manual)` defaults (no crash, no blank).

**Architecture Context:** Grounded F9: active-runs is the multi-run surface, the detail Mode line is what auto_controller supersedes, and the overview render is deliberately byte-locked to its fixture — so the fixture update is part of the change, not an afterthought.

**Implementation Detail:** Missing-field defaults are rendered, never invented in state: the map is only written by the Step 4 writers; the renderer maps absent → `active`/`manual` per mode.

**Error Handling:** Unparseable map already renders the existing unreadable-state row; unchanged.

**Edge Cases:**
- All four states covered in the fixture (active, awaiting_host_resume, blocked_for_pm, manual) plus stalled — five rows pinned.
- Plan-worktree invocation: state root resolution unchanged (P074); asserted once.

**Dependencies:**
- Depends on: Step 6

**Acceptance Criteria:**
- [ ] Byte-locked fixture passes with all five row shapes.
- [ ] Legacy-entry defaults render correctly.
- [ ] Resume command string in the render matches the artifact's safe_next_action verbatim.

**Effort:** S
**AID Role:** docs-writer

### Step 16: Integration fixture — kill it, resume it, exhaust it

**Objective:** One end-to-end fixture proves the plan's promise: a background gate survives a SIGKILLed controller and resumes without re-execution, a declared service lives and dies with its run leaving no orphan, and a budget-exhausted recovery routes through adjudication to a PM-blocked escalation — with every artifact the chain promises present and schema-valid.

**Files:**
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-p076-integration.bats` — fixture repo with one declared service and an execution.yaml whose slow gate is `run_mode: background`: (1) run-all starts service (healthy, port recorded) + background gate; SIGKILL the runner mid-poll; assert artifact present + live job + the STATUS RENDER derives awaiting_host_resume (the derived-state rule — nothing stored it); (2) `aid-fsm.sh resume` collects, patches the report, single-use claim asserted; rerun run-all completes remaining gates and tears the service down (no orphan PIDs, registry stopped); (3) a forced GATE_TIMEOUT fixture drives ladder attempts to budget exhaustion → stubbed adjudication returns escalate → ESCALATION requires the decision field and the map shows blocked_for_pm; (4) golden: the same fixture with foreground-only config and no services matches the COMMITTED pre-P076 reference `scripts/tests/fixtures/p076/golden-gates-report.json` after normalizing the volatile fields (duration_ms, timestamps, output truncation tails) — byte-identity is asserted on the normalized form; Codex-dependent steps stubbed; yq/setsid absence skips with named reasons.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — entries for: run_mode contract + background delegation (Step 2), eager artifact fail-closed + job-cancel compensation (Step 4), resume single-use claim + single-writer rule (Step 5), stalled flagging (Step 6), instruction-closure structural grep check (Step 7), service-declaration schema refusals (Step 8), service registry eager-write + foreground start_cmd contract + deadline-cancels (Step 9), acquire/release-once lifecycle + needs_services fail-fast (Step 10), auto-recovery policy + emitter drift test (Step 11), adjudication allowlist validation (Step 12), ladder budget refusal under flock (Step 13); each with type/source/instruction/severity/surface and honest mechanical/instruction labels; `instruction:` fields cite the TRACKED source-doc section (§16) or skill/command headings — never the gitignored plan file path (registry convention).
- Test: `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` — verification run over every skill/command modified across Steps 1-15.

**Architecture Context:** The fixture is the plan's acceptance instrument, exercising the exact pain sequence the PM described (session dies mid-test) plus the two new subsystems; the registry pass is the AID-v3 §1 closure for every new mechanism.

**Implementation Detail:** The fixture reuses the P074 integration suite's repo-building helpers where they exist (one fixture-construction idiom); runtime registers with the P069 catalog via the existing approval flow with a measured baseline (same contract as P073/P074 closure steps).

**Error Handling:** Assertion failures name the phase (1-4) and the artifact under test.

**Edge Cases:**
- CI without /proc or setsid (non-Linux): whole suite skips named (aid-job's documented requirements).
- Slow CI making the "background" fixture gate finish before the SIGKILL: the fixture gate is a controlled sleep-loop script, deterministic by construction.
- resume invoked from inside the plan worktree (P074 layout): state-root resolution finds the primary evidence and the collect works identically — asserted once in phase 2.

**Dependencies:**
- Depends on: Step 5, Step 7, Step 8, Step 10, Step 13, Step 15

**Acceptance Criteria:**
- [ ] All four phases pass on a clean checkout; golden phase byte-identical.
- [ ] Registry entries exist for every listed mechanism (grep-asserted in the suite).
- [ ] Skill lint clean.

**Effort:** L
**AID Role:** qa

### Step 17: Release metadata and documentation closure

**Objective:** Both CHANGELOGs, the contributor reference, the source-document annotations, and every Last Updated stamp reflect what shipped — verified, not assumed.

**Files:**
- Modify: `CHANGELOG.md` — entry per the repository format (Added: background gates over aid-job with crash re-attach, resume command, auto_controller states, declared services with health probing, auto-recovery policy + adjudication lib + ladder; Changed: run_mode field + advisory event, status renders, e2e card, AUTO contract mechanics; Fixed: the dangling permissions-defaults reference, the invisible-dead-controller stall gap); release itself lands at the plan-final boundary under plan_branch mode.
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — byte-identical entry.
- Modify: `docs/extending-aid.md` — sections: the owned-job contract (when a gate must be backgrounded, how re-attach works), declaring services, the recovery policy file and how a consumer adds a class or budget override.
- Modify: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` (§16 annotation block) — verification-only sweep: the Plan-written/STILL-OPEN blocks match delivery; discrepancies corrected in the blockquote only.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (footer Last Updated line) — stamp verification pass covering every skill/command touched in Steps 1-15; each owning step already bumps its own stamp, this step only verifies completeness.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-p076-docs-closure.bats` — both CHANGELOG entries byte-identical (diff assertion); extending-aid.md contains the three section headings; §16 STILL OPEN lines still carry IMP tokens (Step 14 regression).

**Architecture Context:** CLAUDE.md's mandatory-update rules (identical CHANGELOGs, Last Updated, registry) and the PM's marking discipline from P073/P074 applied one more time.

**Implementation Detail:** Static text; numbers and names copied from the shipped code, never derived claims.

**Error Handling:** Not applicable beyond the diff assertions.

**Edge Cases:**
- Plan-final release timing: the CHANGELOG section header lands unversioned-pending per plan_branch convention and is versioned by the release sub-phase — matching current practice.
- Docs-closure suite runs in consumer checkouts missing docs/: skips named (plugin-repo-only suite).

**Dependencies:**
- Depends on: Step 14, Step 16

**Acceptance Criteria:**
- [ ] Docs-closure suite passes; CHANGELOGs identical; three contributor sections present.
- [ ] §16 annotation verified truthful post-delivery.
- [ ] Last Updated stamps present on every touched skill/command.

**Effort:** S
**AID Role:** docs-writer

## Testing Strategy

Every step lands with its own bats coverage in `plugins/aid-orchestrator/scripts/tests/bats/` — sixteen new suite files named in the step Files entries (`test-run-mode-field`, `test-gate-background`, `test-run-mode-advice`, `test-auto-resume-artifact`, `test-resume-command`, `test-watchdog-stall`, `test-instruction-closure`, `test-service-declaration`, `test-aid-service`, `test-service-lifecycle`, `test-auto-recovery-policy`, `test-recovery-adjudicate`, `test-recovery-ladder`, `test-p076-backlog-closure`, `test-p076-integration`, `test-p076-docs-closure` — a `Test:` entry naming a nonexistent file IS the instruction to create it in that step) plus edits to the byte-locked `test-status-two-streams.bats`. Tiers: function-level (field parsing, fingerprint re-attach decision, port reallocation, ladder budgets, allowlist validation), command-level fixtures (each builds a disposable repo with a controlled slow-gate script and a bash fixture service in `$BATS_TEST_TMPDIR`), and the four-phase integration fixture. Regression discipline: the foreground golden comparison and the no-services golden guard every step that touches the runner; the byte-locked status fixture pins renders; the policy drift test pins existing budgets. Stubs: Codex transport stubbed everywhere (the adjudication lib takes a transport function injection point for tests); `yq`/`setsid`/`/proc` absence skips with named reasons, never false PASS. New suites enter the P069 catalog via its existing approval flow with measured baselines. Live-behaviour boundary stated honestly: that the controller actually runs its loop and presents the honest card as its final turn is verified once at release by the live-check pattern, never claimed as bats-covered.

## Constraints

- Implementation from current `main` (post-P073/P074, ~v2.79.3); no dependency on unmerged work.
- The registry grep guard is binding: zero new setsid/process-group management outside `aid-job.sh` — every mechanism delegates (the guard's grep must stay green).
- Foreground gate path and no-services configuration are byte-identical — golden-asserted, not promised.
- Nothing auto-flips for consumer projects: the template gains fields and documentation only; the `bats_all`/`bats_boundary` flip lands solely in this repository's `.aid-o/config/execution.yaml`.
- Existing retry loops keep their budgets and code paths; the ladder declares them and records their exhaustion, never rewires them.
- No daemons, no cron, no fire-and-return async in this plan (each deferred item is a numbered IMP entry per Step 14).
- All plugin code and documentation in English; PM conversation in Czech; CHANGELOG discipline and Last Updated stamps per CLAUDE.md; every new detection capability registered in `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` with honest mechanical/instruction labels at design time.
- Machine compatibility surfaces frozen: gates_report schema additive only; aid-job record/result schemas untouched; active-runs additions optional fields; fsm-state untouched.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Background path destabilizes the gate runner every run depends on | Medium | High | Foreground byte-identical (golden); background opt-in per gate; timeout/streak semantics mapped, not replaced |
| Re-attach patches a stale or foreign job result into a report | Low | High | Fingerprint + start_head validation before re-attach; stale results refused verbatim (aid-job --require-current semantics) |
| Service fixture flakiness in CI (ports, timing) | Medium | Medium | Deterministic bash fixture service; one-reallocation port logic; named skips for missing prerequisites |
| Ladder/adjudication adds friction to manual runs | Low | Medium | Emitters record everywhere, routing only under --auto; manual = human adjudicates (documented) |
| The two-layer config story confuses consumer upgrades | Low | Medium | Template documents capability with the advisory event naming the exact edit; nothing flips without a project-config line |
| Instruction-only pieces read as mechanical promises | Medium | Medium | Honest detector labels in the policy, explicit instruction-handoff classification on resume, live-check boundary stated in Testing Strategy |
| Orphaned processes from cancelled services with external children | Low | Medium | Group kill via aid-job + stop_cmd with recorded port; orphan sweep assertions in three suites |

## Success Criteria

- A SIGKILLed session mid-30-minute suite costs zero re-execution: rerun re-attaches, `resume` collects, the report completes (integration phase 1-2).
- No gate, service, or job this plan touches can die leaving a live orphan process (group-kill and teardown sweeps asserted in three suites).
- A declared service is probed to health in ≤ deadline, its port is per-run, and it is gone when the run is (phase 2).
- Every stop class in the policy has a named, honestly-labelled emitter that greps to live code; budget exhaustion lands in ESCALATION with `blocked_for_pm` visible in status (phase 3).
- `/aid-status` never shows a dead controller as silently active: stalled entries are flagged with their resume command.
- Foreground-only and no-services configurations are byte-identical to pre-P076 (golden).
- All new suites green; skill lint clean; registry complete; both CHANGELOGs identical; five IMP entries cross-referenced from §16.

## Acceptance Criteria

- [ ] AC1: The background delegation exists in the gate runner.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-run-gates.sh
  regex: "aid-job.sh"
```
- [ ] AC2: This repository's config flips its long gate to background.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c 'yq -r \".gates.bats_all.run_mode\" .aid-o/config/execution.yaml | grep -qx background'"
  expected_exit: 0
```
- [ ] AC3: The resume command exists in the FSM dispatcher.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-fsm.sh
  regex: "cmd_resume"
```
- [ ] AC4: The continuation-artifact schema ships.
```yaml
verification_pattern:
  type: cmd
  cmd: "test -f plugins/aid-orchestrator/defaults/schemas/auto-resume-required.schema.json"
  expected_exit: 0
```
- [ ] AC5: The service lib ships and parses.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -n plugins/aid-orchestrator/scripts/lib/aid-service.sh"
  expected_exit: 0
```
- [ ] AC6: The recovery policy ships.
```yaml
verification_pattern:
  type: cmd
  cmd: "test -f plugins/aid-orchestrator/defaults/policies/auto-recovery.yaml"
  expected_exit: 0
```
- [ ] AC7: The dangling permissions-defaults reference is gone.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c '! grep -n \"default decision from .config/permissions.yaml.\" plugins/aid-orchestrator/commands/aid-run.md'"
  expected_exit: 0
```
- [ ] AC8: The integration suite exists.
```yaml
verification_pattern:
  type: cmd
  cmd: "test -f plugins/aid-orchestrator/scripts/tests/bats/test-p076-integration.bats"
  expected_exit: 0
```

## Next Steps

- All five interim decision points plus the PM's two binding additions were approved on 2026-08-08 (decision record: `.aid-o/work/interim-P076.md`); the source document §16 carries the P076 annotation with the five STILL OPEN items. No PM decision is pending; like any plan, this document remains revisable through the normal review mechanisms.
- `/aid-plan epic .aid-o/plans/P076-auto-mode-owned-waits.md` — EPIC generation (chain queue mode: EPIC 1 → 2 → 3); the plan is high-risk, so CP1-deep plus the C0 cross-provider review loop gate generation.
- After P076, the doc's own front-runner is §18 (IMP-469 standalone `aid-test-parallel.sh`), whose producer-side observe_parallel campaign is accumulating unlock evidence now.
