# AID Cockpit — Implementation Specification (MVP 1)

*Rev 4.1 (PM-approved MVP1 addendum, 2026-06-20): adds cross-project Plan Outcome Analytics (§13.12) so the Cockpit reports how every discoverable plan ended, including explicit failures, retries, escalations, overrides, compliance and evidence gaps. This is additive to Rev 4 and does not reopen its decisions.*

*Rev 4 (post external-audit round 2): resolves 7 must-fix + 5 should-fix findings against the Rev 3 managerial layer. Single explicit plan-membership precedence (MF1); client-side backlog delta (MF2); structured `ComplianceFailure` end-to-end (MF3); nullable `Checkpoint.provenance` + `provenanceSource` (MF4); `SuccessProbability` envelope keeping the binding MVP1 `value===null && source===null` invariant (MF5); first-class plan-level Reporter delivery + Simplifier proposals (MF6); first-class project-scope audit (MF7); plus depth-1 discovery (SF1), corrected "no new source of truth" wording (SF2), per-signal risk confidence (SF3), the `boundaryAudit` vs `aggregateAudit` disambiguation (SF4), and rewritten Screen B/C wireframes (SF5). All changes are additive to Rev 3 — no Rev 3 decision is re-opened. Change summary: §14.*

*Rev 3 (managerial-cockpit layer): adds the `Brief` read-model (one shape, three scopes — infra / project / plan), the deterministic RISK model (level + reasons, "flag never fake"), Screen G "Co potřebuju vědět" as the non-technical front door, Plan as a first-class entity, and the `/api/brief*` endpoints. Builds on Rev 2 without re-designing it. New material is §13 (model) + §7.5 type additions; the rest of Rev 2 is unchanged.*

*Rev 2 (post external audit): nullable contracts, headline-score thresholds, WS polling fallback, watcher depth fix, per-checkpoint retry sourcing, unified explanation/status model, file-endpoint security, CP6/reporter disambiguation.*

## 1. Summary

AID Cockpit is a thin, read-only web dashboard that watches every AID workspace on the eco host and shows — in plain Czech — where each project stands versus its plan, how faithfully the AID pipeline (the 6-state FSM) is being followed, how plans across all AID projects actually ended, and literally everything AID records to disk: checkpoint reviews CP1-CP6, the auditor/curator/reporter/simplifier role outputs, quality gates, compliance verdicts, timings, and retry counts. It owns no data: the disk under `/opt/eco/projects/*/.aid-o/` is the single source of truth, and the app re-reads it on every load (restart = re-read from disk). It auto-discovers projects (no manual registry), surfaces a live activity stream, and ships as an installable, mobile-first PWA. Every dense technical artifact is paired with a human-explanation layer so a non-expert can read what is happening and what it means.

## 2. Goal & non-goals

### Goal (MVP 1)
- Cross-project deep monitoring, **read-only**. Answer three questions at the right altitude on every screen:
  1. **Kde jsme vs. plán?** — progress, current step, what is left, AC coverage.
  2. **Drží se AID svého procesu?** — FSM adherence, checkpoints passed, compliance, force-overrides.
  3. **Co se právě děje a co to znamená?** — live event plus its plain-Czech translation.
- Auto-discover all `.aid-o/` workspaces under `/opt/eco/projects/`.
- Surface every v3 signal AID writes: FSM state, per-step timeline, CP1-CP6, role reports, gates, compliance, queue, backlog (read), timings, retries.
- Aggregate every discoverable plan across projects into a deterministic outcome (`passed|partial|failed|in_progress|unverifiable`) with failures, gate/CP retries, FSM failures, escalations, force overrides, compliance and evidence-quality warnings (§13.12).
- In-app Help (`/help`) modeled on the ACTA `/napoveda` pattern, reusing the same Czech dictionary as the live UI.
- Installable PWA, fully mobile-responsive (real narrow layouts, not shrunk desktop).

### Non-goals (MVP 1)
- No writes to `.aid-o/` (backlog edit, personal tasks → MVP 1.5).
- No AI companion, chat, or voice (the old `companion/` subsystem is dropped).
- No active improvement agent, no memory/Qdrant view (→ MVP 2).
- No token/cost or time-series metrics (those live in LiteLLM/Langfuse/VictoriaMetrics, not on disk; MVP 1 leaves a deep-link seam only).
- No app-layer auth (VPN/localhost-scoped); no manual project registry; no support for legacy run formats beyond counting them.

## 3. Locked architecture

**Architecture "A": a thin custom web-app.** Backend `packages/aid-server` (Node/Express + WebSocket, port **3911**, eco G-008 range 3910-3919, host port = internal port). Frontend `packages/aid-gui`. Shared types in `packages/aid-contract`. npm-workspaces monorepo at repo root, **fully separate from `plugins/aid-orchestrator/`** (different lifecycle, different distribution — the plugin manifest must never reference `packages/`).

**Locked invariants:**
- DISK IS THE ONLY SOURCE OF TRUTH. App only READS. No database, no duplicated state. Stateless: restart = re-read from disk. The `:ro` container mount enforces this at the kernel level.
- CROSS-PROJECT by auto-discovery: scan `/opt/eco/projects/*/.aid-o/`. No manual registry.
- NEW v3 format ONLY. Legacy runs (`stage_log.jsonl`, `plan_progress.json`, `.aid-o/01-epics/`) are counted but excluded from detail.
- Stack: React 19 + Vite + Tailwind 4 + shadcn + @base-ui/react + @tanstack/react-query + react-router 7 + recharts + zustand + lucide-react. Backend: Express 4 + `ws` + `chokidar@4` + `js-yaml` + `gray-matter`, ESM.

### Data-flow diagram

```
  /opt/eco/projects/                          packages/aid-server (:3911, read-only)
  ├── vulcan/.aid-o/                          ┌──────────────────────────────────────┐
  ├── wan/.aid-o/                             │  ProjectScanner (auto-discovery)       │
  ├── acta/.aid-o/          mounted :ro       │   glob */.aid-o, denylist .broken/.bak │
  ├── krok/.aid-o/      ───────────────────▶  │   latest-run = max(started_at|mtime)   │
  ├── sousto-na-miru/.aid-o/                  │   two-tier cache (index + RunDetail)   │
  ├── aid-orchestrator/.aid-o/  (dogfood)     │           │              ▲             │
  └── vulcan.broken-…, cicero.broken-… (BOTH FILTERED)  │  ▼           │ invalidate  │
                                              │   Parsers (json/yaml/    │             │
        chokidar watch (depth 7)              │   jsonl/markdown, tolerant)            │
        change ──────────────────────────────┤           │              │             │
                                              │           ▼              │             │
                                              │   FileWatcher → PATH_RULES → topic     │
                                              │           │                            │
                                              │   ┌───────┴────────┐                   │
                                              │   ▼                ▼                   │
                                              │  REST /api       WebSocket /ws         │
                                              │  (envelope)      (topic+project subs)  │
                                              │   │                │                   │
                                              │   ▼                ▼                   │
                                              │   explain() ── dictionary.cs.ts        │
                                              └───┼────────────────┼───────────────────┘
                                                  │                │ (shared via aid-contract)
                                                  ▼                ▼
                                       packages/aid-gui (React 19 PWA)
                                       react-query (REST) + WS hook (live)
                                       Screens A-F · Czech explanation layer · Help
```

## 4. Data model & signal inventory

Base path per project: `<proj>/.aid-o/`. Run evidence dir = `.aid-o/work/evidence/{epic_id}/{run_id}/`. Run IDs map `R-E{NNN}-{runseq}` (e.g. `E-046-1_3` → `R-E046-1`).

### 4.0 Reliability findings that break naive parsers (read first)

1. **Root `work/timeline.jsonl` is dead for run/step data** (0 bytes in aid-orchestrator/wan/vulcan.broken; absent in vulcan/sousto). The authoritative event log for run/step/gate/CP2-6 activity is the **per-run** `evidence/{epic}/{run}/timeline.jsonl`; the activity stream aggregates per-run timelines sorted by `ts` and does NOT read the root file for those topics. **Narrow exception — CP1 only:** `focus:cp1` verifier dispatch events (`verifier_dispatch_start`/`_complete` with `step_n:null`, `evidence_dir` = work root) are written to the **root** `work/timeline.jsonl` and nowhere else (verified non-empty in acta 468B and krok 501B; aid-orchestrator's own root file is 0B). The scanner MAY read the root timeline **solely to extract `focus:cp1` events**; it MUST NOT use the root file for any other topic. CP1 *verdict* still comes from the `cp1-review-*.md` file (§4.2), and CP1 *timing* remains in the §5.6 NOT-computable list — so this exception is enrichment, not a dependency.
2. **`fsm-state.yaml` `steps[]` is NOT reliably populated** — on DONE runs `steps[].status` is still `pending`, `steps[].name` empty, `steps[].started_at`/`completed_at` always null. Per-step status/timing is **derived from the timeline** and from presence of `step-N-verify.md` / `verifier-output-step-N.md` mtimes (file-mtime is the realistic primary; see §5.1). Reliable top-level fields (always present on a v3 run): `state`, `current_step`, `total_steps`, `mode`, `branch`, `done_phase`, `started_at`, `gate_retries`, `escalation_count`, `streamlined_mode`, `plan_path`, `base_commit`, `plan_json_hash`. **Conditional fields (present only sometimes — parse all-optional, never assume):** `pm_decision` is written **only once a run reaches merge** (verified absent on E-046-3_3 / `R-E046-3`, which is `done_phase: review`, not yet merged). Treat `pm_decision == undefined` as "not yet decided", never as a value.
3. **`config/check-severity.yaml` is project-conditional** (present in wan, krok, acta; absent in aid-orchestrator, vulcan, sousto). When absent, fall back to the plugin default `plugins/aid-orchestrator/defaults/check-severity.yaml` and label severities "default/advisory".
4. **`queue.yaml` is mixed-indentation / partly malformed** (later entries indented differently; one mojibake epic_id). Parse defensively (line-tolerant), never crash.
5. **`audit-log.jsonl` is dominated by test noise** — filter out `epic_id == "unknown"` and `/tmp/` evidence dirs before display.
6. **`counter.yaml` `epic:` field is stale** (`epic: 0`). Only `plan:` is meaningful.
7. **`plan_path: null` ⇒ plan-diff skipped** → AC coverage unavailable; treat absent plan-diff as "not measured" (render "N/A — fast mode"), never as 0% or failed.
8. **Latest run is NOT lexicographically sortable** (`R-005-4_4-1`, `run_20260224_115f`, `R-ABSPATH-001`). Latest = max `started_at` (when parseable) else max run-dir mtime. Never `runs.sort().pop()`.
9. **Legacy run exclusion:** a v3 run has BOTH `fsm-state.yaml` AND a non-empty per-run `timeline.jsonl`. Runs with only `state.yaml`/`stage_log.jsonl` = legacy (counted, `format:"legacy"`, no detail). Runs with only `timeline.jsonl` = `format:"stub"`.
10. **`.aid-o/work/runs/` is OUT OF SCOPE for MVP 1.** Some workspaces have a `work/runs/` dir (e.g. wan, ~21 entries) alongside `work/evidence/`. It is **not** the v3 evidence tree the scanner reads — the authoritative run data is `work/evidence/{epic}/{run}/`. MVP 1 **ignores `work/runs/` entirely** (neither counted nor detailed); revisit only if a future run format writes there. Stated here so it is not silently picked up or silently dropped.

### 4.1 FSM & progress

Model source of truth: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (states `:21`, transitions `:24`, `check_preconditions()` `:1286`). Instruction layer: `skills/pipeline.md` §1.

**6 states:** `READY EXECUTE GATES ESCALATION DONE ERROR` (plus a bash-only PRE-FLIGHT pseudo-state, no LLM, auto→READY).

> **Raw-contract gap (must extend):** the existing `packages/aid-contract/src/types.ts` `AidFsmState` union has only **5** states today (`READY | EXECUTE | GATES | ESCALATION | DONE`) — it is **missing `ERROR`**. The view-layer `FsmState` (§7.5) correctly has 6. Reusing the raw type as-is would fail raw-type validation on any run that reaches `ERROR`. The extend step in §7.5/§7.1 **MUST add `"ERROR"` to `AidFsmState`** before the scanner reads any run. This is the single concrete edit hiding behind the "reuse/extend" verdict.

**Valid transitions:** `READY→EXECUTE` · `EXECUTE→EXECUTE` (step loop) · `EXECUTE→GATES` · `EXECUTE→ESCALATION` · `GATES→DONE` · `GATES→EXECUTE` · `GATES→ESCALATION` · `ESCALATION→EXECUTE` · `ESCALATION→GATES` · `{READY,EXECUTE,GATES,ESCALATION}→ERROR`.

**Transition preconditions (enforced, exit 1 on fail):**

| Transition | Required evidence |
|---|---|
| READY→EXECUTE | `plan.json` exists, `total_steps >= 1` |
| EXECUTE→GATES | `current_step >= total_steps` + `gates_report.json` has `_generated_by` + CP3 outputs present |
| GATES→DONE | `gates_report.json overall: pass` |
| ESCALATION→EXECUTE/GATES | `escalation_decision` set |
| done-advance review→release | `curator-report.md` + `audit-report.md` + `pm_decision=merge` |

| Signal | Path | Format | Key fields | Meaning |
|---|---|---|---|---|
| Current FSM state | `evidence/{epic}/{run}/fsm-state.yaml` | YAML | `state`, `current_step`, `total_steps`, `mode`, `done_phase`, `branch`, `gate_retries`, `escalation_count`, `streamlined_mode`, `started_at`, `plan_path` (always); `pm_decision` (**conditional — present only post-merge**) | The single "where are we" record per run. `current_step/total_steps` = progress bar. `done_phase` = in-review vs ready-to-merge. |
| State transitions (live) | per-run `timeline.jsonl` | JSONL | `{ts, event:"fsm_transition", from, to}` | Reconstruct full state walk + per-state dwell time (consecutive `ts` deltas). Backbone of the stream. |
| FSM init | same | JSONL | `{event:"fsm_init", epic_id, run_id, total_steps, mode}` | Run-start marker; authoritative `total_steps`. |
| Step increment failures | same | JSONL | `{event:"fsm_increment_fail", step, reason}` | "How many times a step was blocked before advancing." |
| Precondition failures | same | JSONL | `{event:"fsm_precondition_fail", from, to, step, reason}` | FSM-discipline signal; repeated identical reasons = friction. |
| Repeated precondition fail | same | JSONL | `{event:"fsm_precondition_repeated_fail", attempt_count}` | Triggers Telegram alert; stuck transitions. |
| Pre-filter classification | same | JSONL | `{event:"prefilter_classification", step, classification:RUN\|SKIP, matched_rules[]}` | Whether a checkpoint dispatched vs was skipped as trivial. |
| Force override | same + `audit-log.jsonl` | JSONL | `{event:"fsm_force_override", from, to, reason, caller, operator}` | PM bypassed a precondition — high trust-impact. |
| Branch mismatch | same | JSONL | `{event:"fsm_branch_mismatch_detected"}` | Init-time branch hygiene failures. |
| PM decision | `fsm-state.yaml` | YAML | `pm_decision: merge`, `done_phase: release` (`pm_decision` absent until merge) | Final disposition; render "ještě nerozhodnuto" while absent. |

**Complete timeline event vocabulary (the full set the parser must recognize — NOT all present on every run):** `fsm_init`, `fsm_precondition_fail`, `gate_start`, `gate_complete`, `prefilter_classification`, `fsm_transition`, `fsm_increment_fail`, `fsm_branch_mismatch_detected`, `verifier_dispatch_start`, `verifier_dispatch_complete`, `fsm_pre_gates`, `gate_runner_start`, `gates_complete`, `gate_runner_complete`, `compliance_written`, `fsm_done_advance`, `fsm_done_advance_fail`, `plan_diff_start`, `plan_diff_complete`, `fsm_advance_to_gates_fail`, `fsm_force_override`, `fsm_done_advance_blocked`. **Sparsity (verified cross-project, drives §5.1):** only `fsm_init` + `fsm_transition` are near-universal. `verifier_dispatch_start`/`_complete` appear in **3/26** non-empty timelines; `compliance_written` and `fsm_done_advance` in **11/26** each — all three are **absent in E-046-3_3, the newest/fullest run**. Any metric that names these as a source MUST degrade to a fallback or `null`, never assume their presence. Cross-EPIC `audit-log.jsonl` adds: `fsm_orphan_dispatch_fail`, `fsm_orphan_dispatch_waived`, `cp4_glob_evaluated`, `cp4_skip_no_prod_match`, `cp4_missing_fail`, `cp4_skipped_streamlined_advisory`, `check_promoted`, `streamlined_integration_review_fail`, `fsm_done_advance_recovered`.

### 4.2 Checkpoints CP1-CP6

Canonical table (`pipeline.md:1282-1287`). **CP1-CP6 are checkpoints, not agents** — they dispatch the `verifier` agent (except CP1=docs-review/PM, CP5=auditor flag).

| CP | When | Verifier focus | Proof-of-run file (glob in run dir) | Pass/fail field | Enforced? |
|---|---|---|---|---|---|
| CP1 | `/aid-plan` Step 9 (plan boundary) | docs-review | `.aid-o/work/cp1-review-{Pxxx}.md`, `cp1-rereview-*.md`, `cp1-reverify-*.md` (at work root) | prose verdict; PM decides | No (advisory, PM-gated) |
| CP2 | EXECUTE, after each step verify | code-review | `verifier-output-step-{N}.md` | `verdict: pass\|fail` frontmatter | Yes, max 2 retries, E7 on exhaustion |
| CP3 | EXECUTE→GATES transition | code-review + security | `verifier-output-cp3-code-review.md`, `verifier-output-cp3-security.md` | `verdict:` + `_generated_by` | Yes (`cp3_integration_precond`), max 2, E7 |
| CP4 | DONE, after curator+auditor auto-fix | code-review | `verifier-output-cp4-curator-validation.md` (variant `cp4-curator`) | `verdict: pass\|fail` | Yes; skipped if no prod paths touched |
| CP5 | DONE, after auditor | N/A — reads auditor flag | (no own file; reads `audit-report.md`) | `blocking_findings: true\|false` | Yes — blocks MERGE; PM ABORT→E8 |
| CP6 | `/aid-do` post-implementation (**Fast Mode ONLY** — does NOT appear on normal `/aid-run` EPICs) | code-review | `verifier-output-*.md` in aid-do evidence dir | `verdict:` | Advisory only, max 2 |

**CP6 ≠ reporter (disambiguation, Q1).** CP6 is a **code-review checkpoint that runs ONLY in `/aid-do` Fast Mode**; it is advisory and never appears on normal `/aid-run` EPICs. **Reporter** is a separate **plan-boundary AGENT role** (§4.3) that writes `.aid-o/reports/{plan}-delivery.md` + `evidence/{epic}/{run}/reporter/*` — it is **not** CP6. The CheckpointStrip shows CP1-CP5 for normal EPIC runs; CP6 is rendered greyed "jen Fast Mode (/aid-do)" or omitted for `/aid-run` runs. The four plan-boundary roles (auditor/curator/reporter/simplifier) stay in the separate "ROLE AGENTŮ" panel, kept distinct from CP1-CP6.

**Verifier output frontmatter (canonical, top-level since E-046-1_3):**
```
_generated_by: aid-orchestrator:verifier@CP3-code-review-E046-1_3
_generated_at: 2026-06-18T20:30:00Z
classification: FULL_REVIEW | RUN | SKIP
verdict: pass | fail | pending
```
Plus `## Findings` / `## Verdict` body. `verdict: pending` = not dispatched (FSM rejects). Empty `_generated_by`/`_generated_at` ⇒ transition fails (anti-fabrication).

**Provenance — read it, do not re-derive it.** Verifier-output provenance is the value AID already computed and **persisted in `compliance.json`** under `checks.verifier_outputs.*_provenance` (`"agent_tool"` | `"unverifiable"`) and `provenance_aggregate`. **The Cockpit reads those fields directly; it does NOT re-derive provenance by cross-checking `verifier-output-*.md` files against `verifier_dispatch_start`/`_complete` pairs in the per-run timeline.** Reason (verified on disk): 23 of 26 non-empty aid-orchestrator timelines have **zero** `verifier_dispatch_*` events while the `verifier-output-*.md` files DO exist — re-deriving from the timeline would falsely mark essentially every run "unverifiable" and destroy trust in the dashboard. The timeline dispatch pairs, when present, are used only as a **corroborating** signal (an optional "dispatch logged ✓" annotation), never as the source of truth. When `compliance.json` is absent (older/stub runs) provenance is simply `null` ("not recorded"), not `unverifiable`. (For CP1 specifically there is no `compliance.json` provenance field and the only dispatch events live in the root timeline — see §4.0 finding #1 — so CP1 provenance is **not cross-checked at all**; CP1 surfaces verdict + presence only.)

**Pre-filter skip rule:** CP2/CP3/CP6 can be skipped for trivial diffs (`≤ trivial_threshold.max_files`); CP1/CP4/CP5 never skipped by this rule.

### 4.3 Plan-boundary roles (Auditor / Curator / Reporter / Simplifier)

Run in **DONE** at the **plan boundary** (after the last EPIC of a plan). All four are distinct agents (`agents/{auditor,curator,reporter,simplifier}.md`), separate from CP1-CP6 checkpoints.

**Auditor → `audit-report.md`** — the **only reliably-present** auditor field is `blocking_findings: true\|false` (CP5 gate input; `true` blocks MERGE). Everything else is best-effort and **format-variable across runs** (verified on disk):

- **Score** appears in THREE different shapes depending on run vintage — the parser must try all three, in order, and `null` if none match:
  1. frontmatter `overall_score: N` (e.g. E-046-3_3 → `overall_score: 84`);
  2. a `## Score: N/100` heading (e.g. E-046-2_3 → `## Score: 95/100`);
  3. a `**Total** N/100` row inside a `## Score` / `## Scores` / `## Score Overview` table (e.g. E-046-1_3 → `**Total** 89/100`).
- **`_generated_by` / `_generated_at` / `classification` are CONDITIONAL** — present on E-046-1_3, **absent** on E-046-3_3 and E-046-2_3. Do NOT require them and do NOT treat their absence as a fabrication flag for the auditor (unlike the verifier outputs, the auditor report is not FSM-anti-fabrication-gated).

When present, the score table runs per category `/25` or `/100` (weights: Security 27, Code 25, Docs 23, Process 15…; Token Efficiency weight 0 = advisory). Findings: `severity: Critical\|High\|Medium\|Low` (deductions −15/−10/−5/−2), `area` (file:line), `audit_type`, `recommendation`, `effort: S\|M\|L`, `auto_fixable: true\|false`. The auditor signal the UI surfaces is therefore: `blocking_findings` (always) + `overall_score` (best-effort, label "—" when not parseable).

**Curator → `curator-report.md`** — sections `## Applied Fixes (S effort)`, `## Deferred (L effort)`, `## Pending proposals`, `## Summary`. Each IMP item: file, problem, fix-applied / `recommended_disposition: approve\|reject\|defer`. Curator writes proposals to `backlog.md` with sequential `IMP-{NNN}`.

**Reporter → delivery report** — `.aid-o/reports/{plan_id}-delivery.md` (git-tracked) + `evidence/{epic}/{run}/reporter/` (≥1 test-evidence artifact). Frontmatter `_generated_by: aid-orchestrator:reporter@…`, `_generated_at`, `_test_evidence[]` (files that MUST exist on disk — anti-fabrication). Advisory compliance check `delivery_report_present`.

**Simplifier → `simplifier-report.md`** — propose-only (never edits code); required by `plan-close`. Proposals with `recommended_disposition`; gate-fixer applies S/M approve items.

**Plan-close marker:** `ca-review-complete` marker in each EPIC's evidence dir = all plan-boundary roles done; next plan's EPICs unblocked. Its absence blocks cross-plan `aid-fsm.sh init`.

**Final report (per-EPIC, not a role):** `final_report.md` — Outcome PASS/FAIL, per-step table, gate-results table, key artifacts, commits.

**Epic summary (auto telemetry):** `epic-summary.md` — Czech `## ✅ Co bylo dodáno`, `## ⚠️ Varování`, `## ❌ Co se nestihlo`, `## 📋 Co dělat dál`, and `## 🔍 Honest signal — PM trust level` with `Trust: HIGH\|MEDIUM\|LOW` + rationale. Footer `_Generated by aid-epic-summary.sh@vX_`. The single best human-facing per-run summary; its vocabulary seeds the Czech dictionary.

### 4.4 Quality gates

| Signal | Path | Format | Key fields | Meaning |
|---|---|---|---|---|
| Gates report | `evidence/{epic}/{run}/gates/gates_report.json` (also run-dir root in some runs) | JSON | `overall: pass\|fail`, `completed_at`, `gates.{name}.{result, exit_code, duration_ms, attempts, output}`, `_generated_by: aid-run-gates.sh@vX.Y.Z`, `_generated_at`, `_command_log[]` | Per-gate pass/fail + timing + retry count |
| Gate result | `gates.{name}.result` | `pass\|fail\|skip` | `plan_diff` shows `result: pass` with `exit_code: 2` (skip-as-pass) |
| Gate timing | `gates.{name}.duration_ms` | int ms | Precise per-gate timing (prefer over timeline diff) |
| Gate retries | `gates.{name}.attempts` | int | Per-gate retry count |
| Anti-fabrication | `_generated_by`, `_command_log[].command` | string | FSM-enforced: EXECUTE→GATES rejects report missing `_generated_by`. `_command_log` proves gates ran. |
| Gate events (live) | timeline.jsonl | JSONL | `gate_runner_start{gate_count, command_list[]}`, `gate_start{gate}`, `gate_complete{gate, result, attempt}`, `gates_complete{overall}`, `gate_runner_complete{overall, duration_sec}` | Stream gate execution |

Typical gate set (plugin repo): `bats_fsm`, `bats_all`, `shell_pipeline_smoke`, `plan_diff`. Gate definitions come from `.aid-o/config/execution.yaml`.

### 4.5 Compliance

`evidence/{epic}/{run}/compliance.json` — single JSON object written at DONE (`compliance_written` event). Present in ~50/96 runs (aid-orchestrator). Parse all-optional (older runs lack `coverage_mode`/`skipped_dimensions`/`failures`/`force_override_*`).

```
epic_id, run_id, aid_version:"v3", deploy_era, evaluated_at,
coverage_mode: "full" | (partial), skipped_dimensions: [],
checks: {
  branch_correct, execution_yaml_present, gates_generated_by,
  plan_ac_match: true|false|null,      # null = not measured (plan_path null)
  memory_substantive: true|false|null,
  verifier_outputs: {
    cp2_per_step_dispatched, cp2_per_step_verdict, cp2_per_step_provenance: ["agent_tool"|"unverifiable",...],
    cp3_code_review_dispatched, cp3_code_review_verdict, cp3_code_review_provenance,
    cp3_security_dispatched, cp3_security_verdict, cp3_security_provenance,
    aggregate, provenance_aggregate: "agent_tool"|"unverifiable"
  },
  dod_present: null, delivery_report_present: null
},
failures: [ { check, evidence, promoted_at, severity: "blocking"|"advisory" } ],
force_override_count: int, force_override_reasons: [ "..." ],
overall: "pass" | "fail", notes: [ "..." ]
```
**Conditional check keys:** the `checks` object itself is partial across runs — `dod_present` and `delivery_report_present` are **absent entirely in older `compliance.json` (e.g. E-042)**, present (often `null`) in newer ones. The Czech dictionary defines `check:dod_present` / `check:delivery_report_present`, but the parser MUST treat a missing key as "not evaluated" (render nothing or "neevaluováno"), distinct from a key present with value `null` ("evaluated, not measured"). Same all-optional rule applies to `coverage_mode`, `skipped_dimensions`, `force_override_*`.

Meaning: `overall` = headline verdict (pass iff all checks ∈ {true, null} and no blocking failure). `failures[].severity` blocking blocks release, advisory only logged. `provenance_aggregate=unverifiable` is the most common real fail (verifier ran via Agent tool but dispatch not in timeline — integrity gap, "not proof of fraud"). `force_override_count`/`reasons[]` — PM bypass count; `aid-compliance-report.sh --reflect` flags 🔴 SYSTEMATIC if avg > 1, max > 3, ≥30% forced, or low-quality reasons. `coverage_mode` — which dimensions were evaluated.

**Severity mapping:** `config/check-severity.yaml` (per-project, often absent — fall back to `defaults/check-severity.yaml`; default all advisory). Each check: `severity: blocking|advisory`, `promoted_at`, `promoted_reason`. Promotions log `check_promoted` to `audit-log.jsonl`.

### 4.6 Queue & backlog

**Queue — `.aid-o/config/queue.yaml`** (parse defensively): `paused`, `last_modified`; `queue[].epic_id/.path/.priority(high|medium|low)/.status(completed|queued|running)/.added_at/.started_at/.completed_at` (always); `.depends_on:[epic_id]` and `.plan_ref` (**optional — present in acta/krok/vulcan/sousto-na-miru queues, ABSENT in aid-orchestrator's own queue**). Status breakdown drives tiles.

> **Grounding note (one reviewer claim was itself wrong):** a reviewer asserted `depends_on`/`plan_ref` exist "nowhere — 0 occurrences". That is true *only for aid-orchestrator's* queue.yaml; verified on disk, both fields are populated in acta, krok, vulcan, and sousto-na-miru queues (e.g. acta `E-001-2_9` has `depends_on: [E-001-1_9]` and `plan_ref: .aid-o/plans/P001-acta-mvp1.md`). So they are **real but optional**, not invented. The dependency-graph treatment below is therefore demoted to an **optional, degrade-gracefully** feature.

**Dependency edges & plan links (optional):** when `depends_on` is present, `depends_on` = DAG edges and `plan_ref` links EPIC → plan; when absent (aid-orchestrator), the queue renders as a flat priority-ordered list with **no edges and no DAG view** — never as an error or empty graph. Top-20 signal #11 ("dependency edges") MUST render "bez závislostí" rather than a broken graph when the field is missing.

**Backlog — `.aid-o/work/backlog.md` (+ `.aid-o/work/backlog/` dir)** — Markdown. `# Backlog` with `Active proposals: N`, a legacy `PROP-* → IMP-{NNN}` alias table, then `## Active Proposals` table: `| ID | Type | Area | Suggestion | Priority | Source | Status |`. Status per row (`proposed`/`pending`/`approved`/`rejected`/`deferred`); header `Active proposals: N` = running open count; closed = created (counter) − active. `.aid-o/work/backlog/` holds longer docs + `archive/`. Handle both the markdown table and stray YAML-style `status:` fields.

### 4.7 Cross-cutting signals

| Signal | Path | Format | Meaning |
|---|---|---|---|
| Lessons learned | `.aid-o/work/lessons-learned.md` | Markdown table | `\| Date \| Lesson \| Context(epic_id) \|` + `## Known Gotchas` |
| Decisions | `.aid-o/work/decisions.yaml` | YAML | `decisions: []` — frequently empty, not reliable |
| Project profile | `.aid-o/work/project-profile.yaml` | YAML | `project_name`, `tech_stack`, `architecture`, `git.remote/default_branch`, `mcp_servers[]`, `memory.provider/collection`, `initialized`, `scanned_at` — per-project tile metadata |
| Counter | `.aid-o/config/counter.yaml` | YAML | `plan: N` (reliable); `epic: 0` (stale — ignore) |
| Auto-mode state | `.aid-o/work/auto-mode-state.yaml` | YAML | Whether AID runs unattended |
| Enforcement registry | `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (canonical) | YAML | `enforcements[]: {id, type, source, instruction, severity, surface, status, verdict, test}` — system-health/coverage view |
| Handoff / interim / session-state | `.aid-o/work/{handoff,interim,session-state}-*.md` | Markdown | Human notes; surface as attachments |
| Ideas | `.aid-o/work/ideas.json` | JSON | Low-priority |
| Memory (MVP 2) | Qdrant `clavi_facts_{tenant}` via `vulcan-memory` MCP | vector | Out of MVP 1 (not a disk artifact) |

### 4.8 Top 20 signals every MVP 1 screen must show

1. FSM `state` per active run. 2. Progress `current_step/total_steps`. 3. Live activity stream (aggregated per-run timelines). 4. `done_phase` (review vs release). 5. Compliance `overall`. 6. `force_override_count` + reasons (#1 trust signal; flag SYSTEMATIC). 7. PM trust level (`epic-summary.md`). 8. Gates `overall` + per-gate pass/fail + `duration_ms`. 9. CP1-CP6 pass/fail matrix + provenance. 10. Auditor `blocking_findings` (always) + best-effort score (label "—" if not parseable; §4.3). 11. Queue status breakdown + dependency edges **when present** (flat list otherwise — §4.6). 12. `fsm_precondition_fail`/`fsm_increment_fail` counts + reasons. 13. State-transition walk + per-state dwell time. 14. Run duration (anchored at READY→EXECUTE, §5.1). 15. Verifier provenance `agent_tool` vs `unverifiable` **read from `compliance.json` `verifier_outputs.*_provenance`** (NOT re-derived from timeline; §4.2) — `null`/omitted when no compliance.json. 16. Backlog open count + added-vs-closed delta. 17. Curator applied vs deferred. 18. `fsm_force_override` events (filtered for real epics). 19. Branch/mode flags. 20. Per-EPIC `final_report.md` outcome.

## 5. Timing & analytics model

All durations in **seconds (int)**, id suffix `_sec`, computed as `epoch(end) - epoch(start)`. All timestamps ISO-8601 UTC, second precision, `Z`-suffixed; diff in epoch-seconds, render local TZ at display only. Gate-level ms precision only from `gates_report.json duration_ms`.

> **Computability reality (read before §5.1) — set expectations, never fabricate.** The rich timeline events the timing model would love are **sparse on real disk**, so the model is deliberately tiered:
> - `verifier_dispatch_start`/`_complete` exist in only **3 of 26** non-empty aid-orchestrator timelines — and are **absent in the newest, most-complete run (E-046-3_3)**. They are therefore the **optional/best-effort** source for step timing, never the primary.
> - `compliance_written` and `fsm_done_advance` each appear in only **11 of 26** timelines (E-046-3_3 has **neither**). The `run_duration_sec` end-fallback chain frequently lands on its *last* fallback (last transition to DONE) — this is the normal case, not an edge case.
> - **Run-start anchor:** the run-start for `run_duration_sec` is the **`READY→EXECUTE` `fsm_transition`**, NOT `fsm_init`. `fsm_init` fires when the run is created, which can precede real work by hours of PM-thinking/idle time (verified: E-046-3_3 init `06-18 14:04`, first `READY→EXECUTE` `06-19 02:56` — a ~13 h idle gap). Anchoring at `fsm_init` would massively overcount. Fall back to `fsm_init` only if no `READY→EXECUTE` exists, and tag `start_source` so the UI can warn.
> - **Step timing primary = file mtime, not the timeline.** Because dispatch events are usually absent, the *realistic primary* for per-step timing is the **mtime of `step-N-verify.md` / `verifier-output-step-N.md`** (ordered, gives "step N finished around T"); the dispatch-gap method is the optional enhancement when dispatch events happen to exist. **On most runs per-step duration is NOT computable from the timeline at all** — see §5.6.

### 5.1 Duration metrics

| id | definition | start | end | fallback |
|---|---|---|---|---|
| `run_duration_sec` | wall-clock of active work in one run | **`READY→EXECUTE` `fsm_transition.ts`** (NOT `fsm_init`; falls back to `fsm_init.ts` only if no such transition, then tag `start_source:"init_idle_included"` + warn) | `fsm_done_advance.ts` → else `compliance_written.ts` → else last `fsm_transition` to DONE (**the last fallback is the common case**) | open run: `max(file mtime)`, mark `incomplete:true`. No timeline: `null`, `NOT_COMPUTABLE`. Tag `end_source`. A separate `run_wall_incl_idle_sec` from `fsm_init` may be shown alongside, explicitly labeled "vč. čekání". |
| `epic_duration_sec` | across all runs of an EPIC | `min(fsm_init.ts)` | `max(terminal.ts)` | single run = `run_duration_sec` |
| `plan_duration_sec` | first EPIC start → last EPIC end for a plan | `min(fsm_init.ts)` over the plan's §13.6 member EPICs (tiers 1-3) | `max(terminal.ts)` | only tier-4 orphans excluded (§13.6 / MF1); `null` when no member run has a parseable anchor |
| `time_in_state_sec` (per state) | seconds in READY/EXECUTE/GATES/DONE/ESCALATION | entering `fsm_transition.ts` (READY = `fsm_init.ts`) | next leaving `fsm_transition.ts` | terminal DONE end = last terminal event; omit states never entered |
| `step_duration_sec` (per step N) | active work on step N | **PRIMARY: mtime of `step-{N-1}-verify.md` / `verifier-output-step-{N-1}.md`** (start of N ≈ end of N−1; first step starts at `READY→EXECUTE`). **OPTIONAL ENHANCEMENT (only when present):** `verifier_dispatch_start` (`step_n==N`) | **PRIMARY:** mtime of `step-{N}-verify.md` / `verifier-output-step-{N}.md`. **OPTIONAL:** `verifier_dispatch_start` of step N+1; last step = first `fsm_pre_gates.ts` | **On most runs the timeline has no dispatch events — step timing comes from file mtimes, and where even those are missing it is `null`, flag `no_step_timing` (see §5.6, "per-step duration NOT reliably computable").** Streamlined/SKIP steps → `null`, flag `no_dispatch`. Dispatch-gap is corroboration, never the sole source. |
| `dispatch_duration_sec` | one verifier dispatch | `verifier_dispatch_start` | matching `_complete` (same `focus`) | **self-host artifact ~0; surface `unreliable:true` when <2s** |
| `gate_batch_duration_sec` | one gate-runner batch | `gate_runner_start.ts` | `gate_runner_complete.ts` | read `gate_runner_complete.duration_sec` directly; per-batch on retry |
| `gate_duration_sec` (per gate) | one gate's wall-time | `gate_start` | next `gate_complete` | authoritative = `gates_report.json duration_ms` |
| `gates_phase_duration_sec` | total time to get gates green (incl. retries) | first `fsm_pre_gates.ts` | successful EXECUTE→GATES transition | captures retry overhead |
| `review_phase_duration_sec` | DONE review→release | `GATES→DONE.ts` | `fsm_done_advance.ts` (to_phase=release) | span ends at successful advance even after `_fail` |

### 5.2 Count / repeat metrics (int, suffix `_count`)

`gate_retry_count` (Σ `(attempt-1)`; cross-check `fsm-state.yaml gate_retries`) · `gate_fail_count` · `gate_batch_count` (count `gate_runner_start`) · `cp_rereview_count` **per CP, with per-checkpoint sourcing (NOT a single uniform rule — see below)** · `cp1_pass_count` (file count) · `precondition_fail_count` (group by `reason`) · `increment_fail_count` (per step; `repeated_fail` = same `(step,reason)` ≥2×) · `force_override_count` (timeline + `compliance.json` + `audit-log.jsonl`) · `escalation_count` (`fsm-state.yaml` scalar) · `verifier_dispatch_count` (per-focus) · `done_advance_fail_count` · `branch_mismatch_count`.

**`cp_rereview_count` per-checkpoint sourcing (grounded on disk — replaces the old "count `verifier_dispatch_start` by focus minus 1" rule, which broke because dispatch events exist on only ~3/26 timelines):**
- **CP1** — the file inventory at the **work root** is authoritative: count `cp1-review-{P}.md` + `cp1-rereview-*` + `cp1-reverify-*` + `cp1-review-{P}-pass2/pass3.md`. `repeatSource:'files'`. (CP1 outputs are NOT overwritten, so files are a reliable repeat signal.)
- **CP2 / CP3 / CP4** — the `verifier-output-*.md` files are **OVERWRITTEN on retry** (verified — no `-r2` suffix exists on disk), so a file count canNOT show retries. The only retry source is `verifier_dispatch_start` events in the **per-run timeline**, grouped by `focus`. When those events exist → `repeatSource:'timeline'`, count = dispatches − 1. When the timeline has no dispatch events (the common case) → `repeatCount: null`, `repeatSource: null` (render "?" / "neznámo"), **NEVER 0**.
- **Gates** — retry count stays reliable from `gates_report.json gates.{name}.attempts` and `fsm-state.yaml gate_retries` (unchanged). `repeatSource:'files'` is not used for gates; the count is authoritative.

The **≥3-repeats hot-spot flag** only fires when `repeatCount` is actually **known** (not null) — an unknown count never trips the flag.

### 5.3 Derived health metrics

`ac_verified_pct` = `plan-diff.json present_count/ac_count*100` (skipped → `null`, flag `no_plan_ac`) · `ac_present/absent/skipped_count` · `gate_pass_rate_pct` (first-attempt) · `gate_final_pass` · `compliance_pass` · `compliance_checks_pass_rate_pct` (exclude `null` checks from denominator) · `coverage_mode` · `steps_run/skipped_count` + `streamlined_coverage_pct` · `verifier_pass_rate_pct`. The two **headline derived scores** (`fsmAdherenceScore`, project/infra `health`) have explicit formulas in §5.7 — they are NOT hand-waved.

### 5.7 Headline derived scores (explicit formulas — "flag, never fake")

Both numbers are surfaced prominently (Screen E `fsmAdherenceScore`, Screen A infra-tile aggregate health, Screen B per-project health), so per §5.6 they get real formulas, all computed from already-inventoried signals. Each resolves into the §7.5 `Score` envelope (`value`/`partial`/`confidence`/`components`/`warnings`), a **0-100 integer** in `value` rendered **only when its data thresholds are met**. When a component input is missing it is dropped from the weighting and `partial:true` (never silently zeroed). Below threshold ⇒ `value:null`, `partial:true`, `confidence:'low'`, and the UI shows the **component breakdown** + "málo dat (n=N)", **never a single fabricated number**.

> **Why denominators matter (the audit's exact concern):** a missing signal must NEVER be counted as "clean". Each penalty/blend term's denominator is **the count of runs for which that signal is actually available**, NOT the total run count — otherwise an absent event (e.g. a run with no gates_report) would be silently rewarded as good process. A term with zero available runs is dropped from the weighting (re-normalize) and sets `partial:true`.

**`fsmAdherenceScore`** (ComplianceView, answers user question #2 "Drží se AID svého procesu?") — a penalty model over a run set (per project, or all projects for the cross-project view).

**Data threshold:** computed (`value` non-null) only when the scope has **≥3 runs with a parseable `fsm-state.yaml`**. Below that → `value:null`, `partial:true`, `confidence:'low'`, UI shows the four penalty-term breakdown instead of a number.

```
base = 100
penalty =  20 * (force_override_count / runs_with_compliance_or_timeline)   # PM bypasses (strongest)
        + 15 * (runs_with_precondition_fail / runs_with_nonempty_timeline)  # transitions AID refused
        + 10 * (1 - gate_first_pass_rate_over_runs_with_gates_report)       # gates green on first try
        +  5 * (escalation_count / runs_with_fsm_state)                     # human-needed stops
fsmAdherenceScore.value = clamp(round(base - penalty), 0, 100)
```
**Per-term denominators (CRITICAL — each over runs where that signal exists, not total runs):**
- `force_override` term denominator = runs that have a `compliance.json` OR a non-empty timeline (the two sources `force_override_count` is read from).
- `runs_with_precondition_fail` term denominator = runs with a **non-empty per-run timeline** (precondition fails can only appear there).
- `gate_first_pass_rate` term denominator = runs that **HAVE a `gates_report.json`** (first-attempt pass over those only).
- `escalation_count` term denominator = runs with a parseable `fsm-state.yaml` (the scalar source).

If a term has **zero available runs**, drop it from the weighting (re-normalize the remaining weights) and set `partial:true`. `confidence:'high'` **only** when all four terms have **≥3 available runs**; otherwise `confidence:'low'`. Components (`force_override_count`, `runs_with_precondition_fail`, `gate_first_pass_rate`, `escalation_count`) are always exposed in `Score.components` so the breakdown can render. A run with clean process scores 100; one forced bypass on a single-run project costs 20 — but a single-run project is below the ≥3-run threshold, so it renders the breakdown, not a number.

**Aggregate `health`** (Project.health / Screen A infra tile) — a quality blend, distinct from adherence (adherence = *did it follow the process*; health = *is the output sound*).

**Data threshold:** computed only when the scope has **≥1 run with a `compliance.json`**; else `value:null` and the tile shows "bez dat". `confidence:'low'` when fewer than 3 runs contribute; show the component breakdown when `partial`.

```
health.value = round(
    0.50 * compliance_checks_pass_rate_pct          # over NON-NULL checks only; denominator ≥1
  + 0.30 * gate_final_pass_rate_pct                  # over runs that have a gates_report
  + 0.20 * (100 if openViolations == 0 else 0)       # any open blocking compliance fail = hard 0 on this term
)
```
- The 0.50 term's denominator = count of **non-null** checks (must be ≥1; if zero non-null checks, drop the term, `partial:true`).
- `Project.health.compliancePassRate` = `compliance_checks_pass_rate_pct` (the 0.50 term, also exposed raw); `null` when no non-null checks exist.
- `Project.health.openViolations` = count of the **latest run's** `ComplianceFailure[]` entries (MF3) with `severity === 'blocking'` still unresolved. **"Resolved" is defined precisely:** a blocking failure (matched by its `.check`) is considered cleared when a **LATER run of the same EPIC** has no `ComplianceFailure` with that same `.check` value (the resolution source is a newer run's structured `failures[]`, never an in-place edit). `Project.health.openViolations` stays typed `number`; only its *derivation* keys off the structured `ComplianceFailure` type — `severity === 'blocking'` and match-by-`.check`, neither of which was expressible against the old `string[]`.
- If a project has zero runs with `compliance.json`, `health.value = null` and the tile shows "bez dat", never 0 %. The infra-tile "aggregate health score" = runs-weighted mean of per-project `health.value` over projects where `health.value != null`.

### 5.4 Aggregation hierarchy

```
step → run → EPIC → plan → project → infra
```
- **step → run:** step list = distinct `step_n` from cp2-step dispatches (or `total_steps`). `Σ step_duration_sec` ≈ EXECUTE time.
- **run → EPIC:** EPIC value = **latest run** for status/verdict; **sum** for cumulative costs (`gate_retry_count`, `force_override_count`, `verifier_dispatch_count`); `epic_duration_sec` spans first→last across runs.
- **EPIC → plan:** resolve plan membership by the **four-tier precedence** of §13.6 (`plan_path` → frontmatter `plan_ref` → id-derived `E-{NNN}` → `P{NNN}` → orphan), recording the tier in `membershipSource`. Only genuinely-unplaceable EPICs (no `plan_path`, no `plan_ref`, no matching `P{NNN}` plan file) are excluded and counted as `orphan_epic_count`. An id-derived EPIC is an **official-but-weaker** member (tagged `membershipSource:'derived'` + a warning), **NOT** an orphan and **NOT** "fast-mode excluded". (Rev 3 wrongly excluded every `plan_path:null` EPIC here; that contradicted the filename-grouping fallback and is corrected in §13.6 / Rev 4.)
- **plan → project:** project = one `.aid-o/` workspace. Rollups: EPICs by state, `avg_run_duration_sec`, `total_force_override_count`, `avg_gate_pass_rate_pct`, `avg_ac_verified_pct`, `total_escalation_count`.
- **project → infra:** sum/avg across all 6 workspaces; tiles: total runs, active runs (state ∈ {READY,EXECUTE,GATES}), aggregate health score.

### 5.5 "Where are we vs plan" — numeric definition

Two complementary numbers, both required:
1. **Execution progress** (in-flight): `current_step/total_steps*100` + FSM state badge.
2. **Delivery completeness** (vs contract): `ac_verified_pct` from `plan-diff.json` — the true "vs plan".

A run **matches the plan** when `state==DONE` AND `ac_verified_pct==100` AND `compliance_pass==true` AND `gate_final_pass==true`. Surface all four; a green step-counter with absent ACs is the exact failure mode to expose. For a plan: `plan_progress_pct = done_epics/total_epics*100`, `plan_ac_pct = Σpresent/Σac_count`.

### 5.6 NOT computable from disk (flag, never fake)

`verifier_wall_time_sec` (Agent tool bypasses timeline; only inter-dispatch-gap approximation, which also includes controller work) · `token_cost`/`$` (no field on disk; LiteLLM/Langfuse only) · per-step `started_at`/`completed_at` from fsm-state (never written) · **per-step `step_duration_sec` from the timeline on most runs** (dispatch events present in only 3/26 timelines; the file-mtime estimate in §5.1 is a *boundary approximation*, not a true active-work duration — surface it as "≈" and `null` with `no_step_timing` when even the verify-file mtimes are missing) · CP1 timing (file-based; only mtime, no start/end pair — `cp1_pass_count` is computable, duration is not) · idle-vs-active within EXECUTE (not separable) · **the `fsm_init`→first-`READY→EXECUTE` idle gap is real wall-time but is PM-thinking, not run work** — excluded from `run_duration_sec` (see §5.1 anchor), only shown separately as `run_wall_incl_idle_sec` labeled "vč. čekání".

## 6. Human-explanation layer (lidská vrstva)

### 6.1 Mechanism

**Static dictionary keyed by signal id, with `{variable}` interpolation.** A signal arrives as `(kind, id, context)`; the explainer resolves the most-specific key (e.g. `event:fsm_precondition_fail:gates_no_generated_by`), falls back to the generic key (`event:fsm_precondition_fail`), interpolates context vars into the Czech sentence, and returns `{headline, detail, status, color}`. Deterministic, cheap, no LLM, no network — pure function of `(id, context)`. Runs on every timeline line and every tile render. **LLM narration is explicitly MVP 2** (the active monitoring agent), as an optional `narrative` field on entries flagged `llm_eligible:true`; the static layer stays the fallback and the terminology source. The Help page reuses the **same dictionary** so terms never drift.

Lives in the backend (`packages/aid-server/src/explain/`), exported through `packages/aid-contract` so WS stream, REST drill-down, and `/help` render identical text. `explain()` must **never throw**: unknown id → `{headline:"Neznámá událost: {id}", detail:"Tahle událost zatím nemá lidský popis. Surová data jsou níž.", status:"ceka"}`, and the unknown id is logged so the dictionary can grow.

Template format (one entry):
```ts
"event:fsm_precondition_fail:gates_no_generated_by": {
  headline: "Brána odmítla postup — chybí důkaz, kdo testy spustil",
  detail: "AID nechce přejít z fáze EXECUTE do GATES, protože soubor s výsledky " +
          "kontrol (gates_report.json) nemá podpis, kdo a čím ho vygeneroval. " +
          "Bez podpisu nejde ověřit, že kontroly opravdu proběhly — tak je nepustí dál.",
  status: "zablokovano",
},
```

### 6.2 Status / colour vocabulary (8 tokens — THE single canonical table, reused by the whole UI)

This `STATUS` table is the **single source of truth** for status tokens and colours across backend, frontend, Help, and tests. §8.5 does NOT define its own table — it reuses this one. Every state, event and verdict maps to exactly one token. Colours are Tailwind-4 tokens (dark-mode-aware via CSS vars). `eskalace` stays distinct from `zablokovano`: blocked = a machine refusing a transition (often self-clears once evidence appears, "wait"); eskalace = an FSM state needing a human ("act"). DONE maps to `proslo`; an idle project/run with no active work maps to `necinne`.

| status (Czech) | meaning | base | hex | usage |
|---|---|---|---|---|
| `běží` | active work | sky | `#0284c7` | EXECUTE, GATES running, step/dispatch start |
| `čeká` | idle/queued/not run | slate | `#64748b` | READY, pending verdict |
| `prošlo` | passed/clean | emerald | `#059669` | DONE, pass, gate pass, compliance pass |
| `selhalo` | hard failure | red | `#dc2626` | ERROR, gate fail, verdict fail, done_advance_fail |
| `zablokováno` | blocked, recoverable | amber | `#d97706` | precondition_fail, done_advance_blocked, blocking compliance |
| `eskalace` | escalated, needs decision | orange | `#ea580c` | ESCALATION state |
| `pozor` | warning/advisory/override | yellow | `#ca8a04` | force_override, pass_with_notes, advisory failures, branch_mismatch |
| `nečinné` | idle project/run, nothing active | slate | `#475569` | idle project tile, run with no active work |

```ts
export const STATUS = {
  bezi:        { label: "běží",        color: "var(--status-running)",   hex: "#0284c7" },
  ceka:        { label: "čeká",        color: "var(--status-idle)",      hex: "#64748b" },
  proslo:      { label: "prošlo",      color: "var(--status-pass)",      hex: "#059669" },
  selhalo:     { label: "selhalo",     color: "var(--status-fail)",      hex: "#dc2626" },
  zablokovano: { label: "zablokováno", color: "var(--status-blocked)",   hex: "#d97706" },
  eskalace:    { label: "eskalace",    color: "var(--status-escalate)",  hex: "#ea580c" },
  pozor:       { label: "pozor",       color: "var(--status-warn)",      hex: "#ca8a04" },
  necinne:     { label: "nečinné",     color: "var(--status-idle-proj)", hex: "#475569" },
} as const;
export type StatusKey = keyof typeof STATUS;
```

### 6.3 Starter Czech dictionary

#### A. FSM states (6)
```
state:READY      → headline: "Připraveno ke spuštění"
                   detail: "EPICa má hotový plán a čeká, až ji pustíš. Zatím se nic nekóduje — jen sedí ve frontě."
                   status: ceka
state:EXECUTE    → headline: "Pracuje se — krok {step} z {total_steps}"
                   detail: "AID právě píše kód podle plánu. Po každém kroku ho zkontroluje a jde na další. Tohle je nejdelší fáze."
                   status: bezi
state:GATES      → headline: "Kontroly kvality"
                   detail: "Kód je hotový, teď přes něj jdou automatické brány — testy, lint, typová kontrola, bezpečnost. Buď projde, nebo se vrací zpátky k opravě."
                   status: bezi
state:ESCALATION → headline: "Zaseklo se — řeší se problém"
                   detail: "Něco nešlo vyřešit samo (kontrola opakovaně selhává nebo došly pokusy o opravu). EPICa čeká na rozhodnutí nebo na opravu, než půjde dál."
                   status: eskalace
state:DONE       → headline: "Hotovo — probíhá závěrečný úklid"
                   detail: "Kroky i brány prošly. Teď běží kurátor, auditor a reporter: posbírají poznámky, nezávisle to překontrolují a sepíšou, co se dodalo. Pak merge."
                   status: proslo
state:ERROR      → headline: "Chyba — běh se zastavil"
                   detail: "Něco se rozbilo natolik, že AID nemůže pokračovat. Tohle není normální cesta — vyžaduje to ruční zásah."
                   status: selhalo
```

#### B. Timeline events (major)
```
event:fsm_init               → "Běh EPICy {epic_id} nastartoval ({total_steps} kroků, větev {branch})." / bezi
event:fsm_transition         → "Přechod z {from} do {to}." / dle cíle
event:fsm_transition:READY→EXECUTE   → "Začalo se kódovat — z přípravy do práce." / bezi
event:fsm_transition:EXECUTE→GATES   → "Kód hotový, jde se na kontroly kvality." / bezi
event:fsm_transition:GATES→DONE      → "Všechny brány prošly — míříme k dokončení." / proslo
event:fsm_transition:GATES→EXECUTE   → "Brána neprošla — vracíme se opravit kód." / pozor
event:fsm_transition:*→ESCALATION    → "Zaseklo se to, eskaluje se k řešení." / eskalace
event:fsm_transition:*→ERROR         → "Běh spadl do chybového stavu." / selhalo
event:step_start             → "Začal krok {step}: {description}." / bezi
event:step_complete          → "Krok {step} dokončen." / proslo
event:prefilter_classification:RUN   → "Předfiltr rozhodl: tahle změna se musí zkontrolovat (RUN)." / bezi
event:prefilter_classification:SKIP  → "Předfiltr rozhodl: změna je triviální, kontrola se přeskočí (SKIP)." / proslo
event:prefilter_classification:FAIL  → "Předfiltr označil změnu jako rizikovou — kontrola je povinná (FAIL)." / pozor
event:verifier_dispatch_start    → "Spuštěn nezávislý kontrolor (focus: {focus})." / bezi
event:verifier_dispatch_complete → "Kontrolor dokončil práci (focus: {focus})." / proslo
event:gate_start             → "Spuštěna brána {gate}." / bezi
event:gate_complete:pass     → "Brána {gate} prošla." / proslo
event:gate_complete:fail     → "Brána {gate} SELHALA — kód se vrací k opravě." / selhalo
event:gates_complete         → "Všechny brány doběhly." / proslo
event:compliance_written     → "Zapsán soulad s pravidly (verdikt: {overall})." / dle verdiktu
event:fsm_precondition_fail  → "Přechod {from}→{to} odmítnut — nesplněná podmínka ({reason})." / zablokovano
event:fsm_increment_fail     → "Posun na další krok odmítnut — chybí důkaz z kroku ({reason})." / zablokovano
event:fsm_force_override     → "POZOR: PM ručně obešel kontrolu ({blocked_checks}). Důvod: {reason}" / pozor
event:fsm_done_advance       → "Postup ve fázi DONE: {from_phase}→{to_phase}." / bezi
event:fsm_done_advance_blocked → "Merge zablokován — neprošla povinná kontrola ({blocked_checks})." / zablokovano
event:fsm_done_advance_fail  → "Pokus o dokončení selhal — chybí report nebo souhlas k merge." / selhalo
event:fsm_done_advance_recovered → "Předchozí blok vyřešen — cesta k merge je volná." / proslo
event:fsm_branch_mismatch_detected → "Pracuje se na jiné větvi, než plán čekal — možný problém s izolací." / pozor
event:fsm_precondition_repeated_fail → "Stejná kontrola selhává opakovaně — systémový problém, ne náhoda." / pozor
event:log_error              → "Zalogována chyba během běhu." / selhalo
```

#### C. CP1-CP6 checkpoints (KONTROLNÍ BODY, ne agenti)
```
cp:CP1 → "CP1 — kontrola plánu před tím, než se z něj udělá EPICa. U rizikových plánů běží hloubkově: tři nezávislé pohledy (bezpečnost, správnost, architektura) plus rozhodčí, který verdikty sjednotí."
cp:CP2 → "CP2 — kontrola po každém kroku. Nezávislý kontrolor projde jen tu malou změnu (HEAD~1..HEAD) hned, jak vznikne."
cp:CP3 → "CP3 — integrační kontrola celé EPICy před branami. Dva kontroloři paralelně: code-review a bezpečnost, nad celým rozdílem (base..HEAD)."
cp:CP4 → "CP4 — kontrola oprav, které sám AID provedl ve fázi DONE (po kurátorovi a auditorovi). Hlídá, aby automatické zásahy nic nerozbily."
cp:CP5 → "CP5 — poslední pojistka před merge: pokud auditor našel kritický nález (blocking_findings), merge se zablokuje a rozhodne PM."
cp:CP6 → "CP6 - kontrola po implementaci v rychlém režimu (/aid-do). Jen poradní, na běžných EPICách se neobjevuje."
```

#### D. Role verdicts (auditor / curator / reporter / simplifier — agent roles, ne CP)
```
role:auditor:clean        → "Auditor (nezávislý kontrolor po dokončení) nenašel kritické nálezy — čisté." / proslo
role:auditor:blocking     → "Auditor našel kritický nález — merge je zablokovaný, dokud to PM neposoudí." / zablokovano
role:auditor:recommended  → "Auditor doporučil {count} oprav (drobné až střední), které AID umí aplikovat sám." / pozor
role:curator:proposals    → "Kurátor posbíral {count} návrhů na zlepšení z poznámek kontrolorů — neúčtuje je hned, jen je eviduje do backlogu." / proslo
role:curator:empty        → "Kurátor neměl co sbírat — žádné poznámky ke zlepšení." / proslo
role:reporter:pass        → "Reporter dodávku vyzkoušel a sepsal — funguje, s důkazem ({evidence_count} souborů)." / proslo
role:reporter:fail        → "Reporter dodávku vyzkoušel a nefunguje podle zadání." / selhalo
role:reporter:no_evidence → "Reporter nedoložil žádný důkaz, že dodávku spustil — poradní varování." / pozor
role:simplifier:proposals → "Simplifikátor navrhl {count} zjednodušení kódu (jen návrhy, sám kód nemění)." / proslo
role:simplifier:none      → "Simplifikátor nenašel co zjednodušit." / proslo
```

#### E. Verifier classification + verdict (CP2/CP3/CP4 outputs)
```
verdict:RUN          → "Kontrola proběhla naplno." / bezi
verdict:SKIP         → "Kontrola přeskočena (triviální změna): {reason}" / proslo
verdict:FULL_REVIEW  → "Vyžádána plná kontrola (riziková změna)." / pozor
verdict:pass         → "Kontrolor: PROŠLO." / proslo
verdict:pass_with_notes → "Kontrolor: prošlo s poznámkami — drobnosti na zvážení, nic blokujícího." / pozor
verdict:fail         → "Kontrolor: NEPROŠLO — kód se vrací k opravě." / selhalo
verdict:pending      → "Kontrola naplánovaná, ale ještě neproběhla." / ceka
```

#### F. Compliance severities + key checks
```
severity:blocking    → "Blokující porušení pravidel — bez nápravy nebo ručního obejití se nemerguje." / zablokovano
severity:advisory    → "Poradní porušení — zaznamená se, ale postup neblokuje." / pozor
compliance:overall:pass → "Soulad s pravidly: v pořádku." / proslo
compliance:overall:fail → "Soulad s pravidly: porušeno — {blocking_count} blokujících, {advisory_count} poradních." / selhalo
check:verifier_provenance → "Nejde ověřit, kdo a kdy kontrolu provedl (původ výstupu nesedí na záznam o spuštění). Není to důkaz podvodu, je to chybějící stopa — proto blokující." / zablokovano
check:gates_generated_by  → "Výsledky bran nemají podpis nástroje, který je vytvořil — nejde dokázat, že brány opravdu běžely." / zablokovano
check:plan_ac_match       → "Implementace neodpovídá akceptačním kritériím z plánu — dodalo se něco jiného, než plán slíbil." / zablokovano
check:dispatch_orphan_complete → "Kontrolor byl spuštěn, ale chybí záznam o jeho dokončení — visící kontrola, postup blokován." / zablokovano
check:branch_correct      → "Pracuje se mimo očekávané pojmenování větve (task/E-...). Poradní." / pozor
check:memory_substantive  → "Do paměti se nezapsalo nic podstatného z tohoto běhu. Poradní." / pozor
check:dod_present         → "Chybí Definition of Done. Poradní." / pozor
check:delivery_report_present → "Chybí závěrečný report dodávky nebo nemá doložené důkazy. Poradní (časem blokující)." / pozor
```

### 6.4 Backend explainer module shape

**One dictionary type, one runtime type — see §7.5 for the canonical definitions.** `DictionaryEntry` is the static content (ONE source for both live UI and Help); `Explanation` is the runtime resolution returned by `explain()`. `explain()` resolves a `DictionaryEntry` (+ context interpolation) into an `Explanation`; Help renders from `DictionaryEntry` (term/keywords/long-form).

```ts
// packages/aid-server/src/explain/types.ts (types re-exported from aid-contract §7.5)
export interface ExplainInput {
  kind: "state" | "event" | "cp" | "role" | "verdict" | "severity" | "check" | "concept";
  id: string;                        // "fsm_precondition_fail", "READY", "CP3"
  context?: Record<string, unknown>; // {step, total_steps, reason, from, to, focus, count, ...}
}
// Runtime resolution (camelCase view layer, §7.5):
//   Explanation = { headline: string; detail: string; status: StatusKey; color: string }

// packages/aid-server/src/explain/explain.ts
export function explain(input: ExplainInput): Explanation {
  // 1. resolveKey: `${kind}:${id}:${context.reason ?? context.verdict ?? context.to ?? ...}`
  //    then `${kind}:${id}`, then generic unknown template — selects a DictionaryEntry.
  // 2. interpolate {vars} from context into headlineTemplate + detailTemplate.
  // 3. attach STATUS color. Returns Explanation. Deterministic. No async. No LLM. Never throws.
}
```
- **Dictionary file:** `packages/aid-server/src/explain/dictionary.cs.ts` (locale-suffixed for future `.en.ts`), exported as `Record<string, DictionaryEntry>` (§7.5) with `{var}` placeholders in `headlineTemplate`/`detailTemplate`.
- **Key-resolution helper:** `resolveKey(input)` — data-driven per `kind` (event uses `.reason` then `.to`; verdict uses raw `.id`).
- **Shared with frontend** via `packages/aid-contract` so `aid-gui` and `/help` consume the exact same `DictionaryEntry` content and `explain()` output.

## 7. Backend design

**Verdict up front:** keep the **parsers** and a format-agnostic **FsReader**, keep the **WS protocol shape**, keep the **API envelope helpers**. Drop the **companion** subsystem, the **single-active-project ProjectRegistry**, all **write** routes, the **ideas-migration** write-back, the **scheduler**, and the invented 13-state FSM. The two existing server trees (`aid-gui/server`, `aid-server/src`) are a **parts bin**, not a base — the new server is a fresh `packages/aid-server` with a cross-project scanner neither tree has.

### 7.1 Salvage table

Paths relative to `/opt/eco/projects/aid-orchestrator/`. **reuse** = move ~as-is · **adapt** = keep logic, change scope · **drop** = delete.

**Parsers (crown jewels):**
| Module | Verdict | Reason |
|---|---|---|
| `aid-gui/server/parsers/utils.ts` (`snakeToCamel`) | reuse | Recursive, defensive, no project assumptions |
| `aid-gui/server/parsers/json.ts` | reuse | Never-throws `ParseResult<T>` |
| `aid-gui/server/parsers/yaml.ts` | reuse | js-yaml wrapper, captures error line |
| `aid-gui/server/parsers/jsonl.ts` | reuse | Per-line tolerant — exactly right for timeline.jsonl |
| `aid-gui/server/parsers/markdown.ts → parseMarkdownWithFrontmatter` | reuse | gray-matter + section split (EPIC frontmatter, audit-report, epic-summary) |
| `aid-gui/server/parsers/markdown.ts → parseEpicSpec` | adapt | v3-correct; drop the duplicate `parseFrontmatter` in `aid-server/routes/epics.ts` |
| `parseStepsTable` / `parseScope` | **net-new (NOT salvage)** | **These functions do NOT exist in `markdown.ts` today** (verified: the file exports only `parseMarkdownWithFrontmatter` and `parseEpicSpec`). The steps-table and scope-section parse paths must be **written from scratch** with their own vitest fixtures, not "adapted". An earlier draft wrongly listed them as existing — corrected here. |
| `aid-gui/server/parsers/index.ts` | reuse | Barrel export |
| `aid-server/src/services/fs-reader.ts` (`FsReader`) | adapt | Clean read primitives; change to take an absolute `aidoPath` per call so one instance serves all projects |

**Watchers:**
| Module | Verdict | Reason |
|---|---|---|
| `aid-gui/server/watchers/file-watcher.ts` (`FileWatcher`+`PATH_RULES`+`classifyPath`) | adapt | Debounced chokidar + regex classifier; make it one watcher over `/opt/eco/projects` with `depth` limit, emit `projectId` (segment after `projects/`). Reuse the rule table |
| `aid-gui/server/watchers/stage-log-stream.ts` (`StageLogStream`+`CircularBuffer`) | adapt → likely drop | Single-run tailer; replace with chokidar `change` on any `timeline.jsonl` → re-read tail → push delta. Keep `CircularBuffer` for the bounded merged-activity buffer |
| `aid-server/src/ws/handler.ts` inline `startFileWatcher` | drop | Weaker duplicate (no debounce, single-root) |

**WebSocket:**
| Module | Verdict | Reason |
|---|---|---|
| `aid-gui/server/ws/websocket.ts` (`AidWebSocket`) | **adapt + extend** (NOT reuse) | Best impl: topic subscribe/unsubscribe, wildcard, heartbeat 30s, idle 90s, replay-on-subscribe, safeSend. **Real adaptation work, verified against the file:** (1) the broadcast envelope uses field **`timestamp`** today, NOT `ts` — the §7.3 contract standardizes on `ts`, so this is a rename across all `safeSend` sites (lines ~191/231/302/358/372/411); (2) **no `projectId` field and no per-project subscription filter exist** — the topic-AND-project filter is net-new logic; (3) replay is **hardcoded to `pipeline.stage_log` via `setStageLogBufferSupplier`** — must be generalized to a merged "activity buffer" supplier. Budget as adapt+extend, not move-as-is. |
| `aid-server/src/ws/handler.ts` (`WsHandler`) | drop | Weaker typing, couples WS to single FsReader |
| `aid-gui/server/types.ts → EventTopic, ALL_EVENT_TOPICS, InternalEvent, FileChangeEvent, PathClassification, WatcherOptions, ParseResult, ParseWarning` | reuse | The contract parsers+watcher+ws speak; move into `aid-contract` |
| `aid-gui/server/types.ts → 1107-line domain types (13-state `FSMState`)` | drop / rebuild | The `FSMState` union is WRONG (invents PLANNING/GATE_RETRY/CURATOR_RESOLVE). Real FSM = 6 states. Use `aid-contract` `FsmState` |

**API routers** (newer `aid-server/src/routes/*`; `aid-gui/server/api/*` equivalents are drop unless noted):
| Router | Verdict | Reason |
|---|---|---|
| `routes/epics.ts` GET `/` | adapt | Frontmatter parse + status-weight sort is v3-correct. Re-scope to scanner cache |
| `routes/epics.ts` POST `/:epicId/run` | drop | Write (mutates queue.yaml) — MVP 1.5 |
| `routes/pipeline.ts` GET `/`, `/steps`, `/step-statuses`, `/theater/...`, `/timeline`, `/stage-log` | adapt | Salvage run-detail assembly into the scanner's `RunDetail` builder; **fix `runs.sort().pop()`** latest-run bug |
| `routes/queue.ts` | adapt (GET only) | Reads `config/queue.yaml`; strip mutation |
| `routes/path-validation.ts` (`validateEvidencePath`, CWE-22 guard) | reuse | Essential for the raw-file endpoint — backs the §7.4.1 `/file` security spec (realpath + startsWith assert, `..`/absolute/symlink reject, name allow-list, 1 MB cap) |
| `routes/decisions.ts` | **fold into RunDetail/`/file`** | Read-only subset — its data ships in MVP 1 via `EpicDetail.reports` + `RunDetail.files` + the `/file` endpoint, **not as a standalone `/decisions` route**. No dedicated MVP 1 endpoint (reconciles §10). |
| `routes/audit.ts` | **fold into EpicDetail/`/file`** | Reads audit-report — surfaced in MVP 1 through `EpicDetail.reports` (`kind:"audit"`) + `/file`, **no standalone `/audit` route** in the MVP 1 list (§10). |
| `routes/evidence.ts` + `evidence-search.ts` (logic) | **fold into `/file` + RunDetail.files** | Listing/reading evidence is covered by `RunDetail.files` + the path-guarded `/file` endpoint; no standalone `/evidence` route in MVP 1. |
| `routes/backlog.ts` | adapt → MVP 1.5 writes | Read view ships in MVP 1 as `GET /api/backlog`; POST/PATCH deferred to MVP 1.5 |
| `routes/lessons.ts`, `usage.ts`, `knowledge.ts` | **fold into `/file`** / defer | Low priority — lessons-learned reachable via `/file`; no dedicated MVP 1 endpoints |
| `routes/ideas.ts` + `services/ideas-migration.ts` | drop | Write-on-shutdown — violates read-only |
| `routes/companion.ts`, `voice.ts` | drop | Out of scope |
| `routes/projects.ts` | drop / rebuild | Trivial wrapper over rejected registry; rebuild scanner-backed |
| `routes/types.ts` (`ProjectParams`, `isValidPathComponent`) | reuse | Param typing + validation |
| `aid-gui/server/api/middleware.ts` (`sendOk/sendError/send404/send400`, `ApiResponse`/`ApiError`) | reuse | Standard envelope; drop per-request single-project `aidoPath` resolution |
| `aid-gui/server/api/plans.ts, config.ts, others` | drop | Older duplicates |

**Services / companion / scheduling / contract:**
| Module | Verdict | Reason |
|---|---|---|
| `aid-server/src/services/project-registry.ts` | drop / rebuild | Single-project registry — explicitly rejected. Replace with `ProjectScanner`. Keep only the `Project` interface shape |
| `aid-server/src/services/ideas-migration.ts` | drop | Write-back violates read-only |
| `aid-server/src/companion/*` (8 files) | drop | Entire AI-companion subsystem |
| `aid-server/src/index.ts` | adapt (skeleton) | Express+cors+http+ws bootstrap, static GUI serving, graceful shutdown, `/api/health`, `/api/*` 404 catch-all. Rip out registry init, ideas import/export, companion/voice routes |
| `aid-server/src/config.ts` (`loadConfig`) | adapt | Port 3911 default, CORS. Add `AID_PROJECTS_ROOT=/opt/eco/projects` + scan cadence |
| `aid-gui/server/scheduling/scheduler.ts` | drop | Cron EPIC scheduling (write) |
| `aid-contract/src/types.ts` (`AidFsmState`, `AidStateYaml`, `AidTimelineEntry`, `AidGatesReport`, `AidGateDetail`, `AidQuickLog`, `AidProjectYaml`) | reuse / **extend (required edit)** | Closest to real v3 disk shapes (snake_case raw) — the *raw* contract layer. **Mandatory extend, not optional:** `AidFsmState` is `"READY"\|"EXECUTE"\|"GATES"\|"ESCALATION"\|"DONE"` today — **add `"ERROR"`** (it is a real v3 state, see §4.1) or every ERROR-state run fails raw-type validation. |

### 7.2 Scanner design (`ProjectScanner`)

Replaces `ProjectRegistry`. Pure read, auto-discovery, cached.

**Discovery — TOP-LEVEL workspaces ONLY (depth-1, never recursed).** MVP1 monitors **only the top-level** AID workspace of each project — exactly the directories matched by the depth-1 glob `<scanRoot>/*/.aid-o`. It does **not** recurse into a project tree looking for `.aid-o` dirs; nested, empty, and test `.aid-o` dirs are **out of scope** (see the disk-reality note below). This makes the phrase "every AID workspace" precise: one workspace per top-level project dir, not every `.aid-o` directory that happens to exist anywhere under `<scanRoot>`.
```
scanRoot = AID_PROJECTS_ROOT (default /opt/eco/projects)
glob: <scanRoot>/*/.aid-o   (depth 1, dirs only — single path segment between scanRoot and .aid-o; NOT <scanRoot>/**/.aid-o)
exclude project dirs matching: /\.(broken|bak|old)\b/, /-\d{8}-\d{4}$/, leading-dot, names containing "backup"
  AND any without a config/ AND work/ subdir (sanity check vs layout drift)
projectId = basename(dirname(.aid-o))   e.g. "acta", "vulcan"
```
A project is **discovered** if `<scanRoot>/<project>/.aid-o/` exists at depth 1; **active** if `work/evidence/` has ≥1 run dir OR `tasks/*.md` exists. Missing `work/`/`tasks/` → still listed, `partial:true`, never throws. **BOTH broken workspaces MUST be filtered:** `vulcan.broken-20260430-0741` **and** `cicero.broken-20260430-0735` — the `\.(broken)\b` + `-\d{8}-\d{4}$` patterns cover both; the regression test (MVP 1 AC #1) asserts both are excluded. Sibling dirs that have **no `.aid-o`** at all (`cicero`, `myinvoice`, `panopticon`, `_refs`) are excluded by the `*/.aid-o` glob itself and must also be asserted absent in AC #1.

> **Disk reality — nested `.aid-o` dirs exist and are deliberately NOT recursed into (verified `find /opt/eco/projects -maxdepth 5 -type d -name .aid-o`).** Two nested `.aid-o` dirs live *inside* valid top-level projects: `krok/backend/.aid-o` and `vulcan/ui/.aid-o`. Both are **out of scope** for two independent reasons: (1) the depth-1 glob `<scanRoot>/*/.aid-o` never reaches them (they are at depth 2+ — `<scanRoot>/krok/backend/.aid-o`), and (2) even if reached, both contain **only a `work/` subdir** (no `config/`), so the `config/ AND work/` sanity check would reject them anyway. The remaining nested dirs (`vulcan.broken-…/.claude/worktrees/*/.aid-o`, `vulcan.broken-…/ui/.aid-o`) sit under an already-denylisted broken project and are doubly excluded. The single workspace per project is the top-level one (`krok/.aid-o`, `vulcan/.aid-o`), and the cockpit treats `krok` and `vulcan` as one workspace each — the `backend/`/`ui/` sub-workspaces are never surfaced as separate projects nor merged in. (The §7.3 per-`.aid-o` watcher attaches only to these top-level dirs for the same reason, so watcher traversal also never descends into a nested workspace.)

**Build project list (`scan()` → `Project[]`):** per project — (1) `tasks/*.md` (exclude `archive/`) → EPIC list via frontmatter; (2) `work/evidence/*/` → EPIC-run dirs; (3) project rollups (total/active epics, total runs, last activity = max run-dir mtime).

**Latest run per EPIC (the part old code gets wrong):**
```
latestRun(epicDir):
  runDirs = readdir(epicDir, dirsOnly)
  for each run: stat mtime; if fsm-state.yaml present read started_at
  sort by: started_at DESC (when parseable) else mtime DESC; pick first
  # NEVER runs.sort().pop()
```

**Per-run classification:** `fsm-state.yaml` with `state` ∈ 6 → **v3** (full detail). Only `state.yaml`/legacy markers → **legacy** (counted, `format:"legacy"`, no CP/timing detail). Only `timeline.jsonl`/empty → **stub** (`format:"stub"`, minimal). Old `.aid-o/01-epics/`, root `plan_progress.json`/`stage_log.jsonl` are never read.

**Performance (277 runs × 6 projects):**
- **Two-tier cache.** Tier 1: project/EPIC index (dir listing + frontmatter + per-run mtime/state-line), built on boot, sub-second. **Tier-1 also indexes the managerial-projection source files (Rev 3, SF2):** `plans/*.md`, `work/evidence/*/audit-report.md`, `work/backlog.md`, and `work/lessons-learned.md` — for each, the dir listing + frontmatter (where present) + per-file mtime. This is what lets `PlanSummary`/`AuditSummary`/`AuditTrend`/`BacklogDelta`/`LessonsView` (§13.5-§13.8) be served as projections over the cache: Tier-1 carries the *presence + mtime* so the brief and the "co se změnilo" diff (§13.3) work without a per-request scan; the heavy *body* parse of those files is Tier-2 on-demand. Tier 2: full `RunDetail` (plan.json, compliance, gates_report, verifier-output md) **plus the on-demand body parse of the indexed audit/backlog/lessons/plan files** — **lazy on-demand** per `GET /epics/:id` (and `/plans/*`, `/lessons`, `/backlog`, `/audit-trend/*`), memoized in an LRU keyed by `projectId/epicId/runId` (or `projectId/planId` for plan-scope projections).
- **Invalidation: watcher events PRIMARY, max-file-mtime backstop.** A change to a nested file (e.g. `gates/gates_report.json`) may **not** bump the run-DIR mtime, so dir mtime alone is insufficient. The **watcher** (already emitting per-file `change` events, §7.3) is the PRIMARY invalidation: a change under a run dir invalidates that `RunDetail` LRU key. As a backstop, each entry stores the **max mtime over the run's read files** (not the dir mtime); if that max moves, the entry is stale. A 10-min TTL safety sweep catches any missed events.
- **Bounded merged activity:** ring buffer of last 500 timeline events across all projects for `/activity`, refreshed incrementally on `change`.
- **Concurrency:** cap parallel file reads (`p-limit 16`) so a cold scan can't thundering-herd the FS.

### 7.3 Watcher + live stream

**Watch only `.aid-o` subtrees — the parent root contains ~1524 unrelated dirs.** A single chokidar watcher over `AID_PROJECTS_ROOT` with only *negative* `ignored` globs would traverse every sibling project's source (`backend/`, `docs/`, `.ruff_cache/`, `.playwright-mcp/`, `.claude/`, `.superpowers/`, …) and fire on unrelated git/build/cache churn. (The inotify budget is fine — `max_user_watches=366939` — the problem is spurious events and CPU, not watch exhaustion.) The aspirational "keep only paths containing `/.aid-o/`" comment in the earlier draft was **not code**. Pick ONE of two concrete chokidar-4 mechanisms; the spec mandates **(B) per-`.aid-o` watchers** as the default because it is strictly tighter:

**(A) `ignored` as a FUNCTION** (single watcher) — chokidar 4 calls `ignored(path, stats?)`; return `true` for any path whose `projects/<p>/` segment is not immediately followed by `.aid-o`, plus the denylisted project dirs and binary/cache globs:
```ts
const aidoSeg = /\/projects\/[^/]+\/\.aid-o(\/|$)/;
const denyProj = /\/projects\/[^/]+\.(broken|bak|old)\b|-\d{8}-\d{4}(\/|$)/; // covers vulcan.broken-… AND cicero.broken-…
const ignoredFn = (p: string) =>
  denyProj.test(p) ||
  /\/(node_modules|\.git)\//.test(p) ||
  /\.(tmp|swp|png|jpe?g|gif|zip|tar|gz)$/.test(p) ||
  (/\/projects\/[^/]+\//.test(p) && !aidoSeg.test(p)); // inside a project but NOT under .aid-o → ignore
```

**(B) One watcher per discovered `<proj>/.aid-o` (DEFAULT, recommended)** — the `ProjectScanner` discovers `<scanRoot>/*/.aid-o` (denylist applied), then instantiates a chokidar watcher **rooted at each `.aid-o` dir**, so traversal never leaves an AID workspace. Re-scan for newly-created projects on the same 10-min TTL sweep (§7.2) and attach/detach watchers as projects appear/disappear:
```ts
for (const proj of scanner.discover()) {              // already denylist-filtered (excludes *.broken-*, *.bak, *.old)
  chokidar.watch(proj.aidoPath, {                      // e.g. /projects/acta/.aid-o
    ignoreInitial: true, persistent: true, followSymlinks: false,
    depth: 7, // .aid-o/work/evidence/<epic>/<run>/<subdir>/<file> — must agree with §3 diagram (depth 7)
    ignored: [
      '**/node_modules/**','**/.git/**','**/*.tmp','**/*.swp',
      '**/*.png','**/*.jpg','**/*.gif','**/*.zip','**/*.tar','**/*.gz',
    ],
    awaitWriteFinish: { stabilityThreshold: 150, pollInterval: 30 },
  }).on('all', (type, path) => handleChange(proj.id, type, path));
}
```
**Depth must be 7, not 5.** The deepest watched artifacts are `evidence/<epic>/<run>/<subdir>/<file>` — and `gates/gates_report.json`, `reporter/*`, and `steps/*` live at **depth 6** (`.aid-o`=0 → `work`=1 → `evidence`=2 → `<epic>`=3 → `<run>`=4 → `<subdir>`=5 → `<file>`=6 relative to the watched `.aid-o` root, i.e. 7 levels of nesting). A `depth: 5` watcher would **miss** these depth-6 files entirely (gates report, reporter outputs, step verifies), which is why the §3 data-flow diagram already says "depth 7"; §7.3 now agrees.
Debounce 150ms (cross-project churn is bursty). On event: (1) extract `projectId` (segment after `projects/`); denylist → ignore. (2) relative path through reused `PATH_RULES` → `{topic, parser, excluded}`. (3) parse with matching tolerant parser (null on fail). (4) invalidate cache slice (project index entry or RunDetail LRU key from `evidence/<epic>/<run>/`). (5) emit `InternalEvent { projectId, topic, changeType, runRef?, parsedData, ts }`.

**Topics:** `pipeline` (fsm-state/state/plan), `pipeline.timeline` (timeline append), `gates`, `compliance`, `checkpoints` (verifier-output-* add/change), `queue`, `decisions`, `audit`, `epics` (tasks/*.md), `backlog`, `config`, `system`.

**WebSocket contract** (`/ws`, adapted `AidWebSocket`):

Client → server:
```jsonc
{ "type": "subscribe", "topics": ["pipeline","gates","checkpoints"], "projects": ["*"] }
{ "type": "unsubscribe", "topics": ["gates"] }
{ "type": "ping" }
```
Server → client:
```jsonc
{ "type":"connected", "availableTopics":[...], "ts":"…" }
{ "type":"event", "topic":"pipeline", "projectId":"acta",
  "data": { "changeType":"change", "ref": { "epicId":"E-007-3_4","runId":"R-E007-3" },
            "parsed": { /* topic-shaped delta */ } }, "ts":"…" }
{ "type":"replay", "topic":"pipeline.timeline", "data":[ /* last N merged activity */ ], "ts":"…" }
{ "type":"heartbeat", "clientCount":3, "ts":"…" }   // every 30s
{ "type":"error", "message":"…", "ts":"…" }
```
Subscription filter = topic AND (project in set OR `*`). `system`/heartbeat always delivered. Idle close at 90s (code 4001).

**react-query integration:** map topic → query-key prefix (`pipeline`→`['epic',projectId,epicId]`+`['projects']`; `gates`/`compliance`/`checkpoints`→`['epic-detail',projectId,epicId,runId]`; `epics`/`queue`→`['projects']`,`['epics',projectId]`; `pipeline.timeline`→`['activity']`). On WS `event` the hook calls `invalidateQueries` (coarse) or `setQueryData` (fine, timeline append). `replay` rehydrates the activity feed without REST. Coalesce: debounce invalidations per key ~250ms FE-side.

**REST polling fallback (live-monitoring must never go dark).** `/ws` traverses nginx + CF Access (§9.5); the upgrade can fail (proxy/CF issue), or the socket can idle-close (90s) or drop. When the WS is **not OPEN** for any reason, the frontend MUST NOT just go silent — it falls back to **REST polling**: it polls `GET /api/activity` (and re-validates the active EPIC/compliance query keys for the screen in view) **every 5s**, and shows a visible banner **"živé spojení nejede - aktualizuji po 5 s"**. When the WS recovers (re-OPEN), polling stops and the banner clears. This keeps the dashboard live (just coarser) through any proxy/CF hiccup, and is the build-side mitigation for the §9.5/risk #5 `/ws`-through-CF upgrade risk. (Answers auditor Q3 — yes, poll on WS fail.)

### 7.4 REST API surface (all read-only MVP 1)

Envelope: success `{ "ok": true, "data": T, "meta"?: {...} }`; error `{ "ok": false, "error": { "code","message","details"? } }`. Base `/api`. All list endpoints return `meta: { scannedAt, partialProjects: [...] }`.

| Method | Path | Response `data` |
|---|---|---|
| GET | `/api/health` | `{ status, ts }` |
| GET | `/api/brief?since=` | `Brief` (scope `infra`) — cross-infra managerial brief, powers Screen G (§13.4) |
| GET | `/api/brief/:projectId?since=` | `Brief` (scope `project`) — Screen B first tab (§13.4) |
| GET | `/api/brief/:projectId/:planId?since=` | `Brief` (scope `plan`) — Plan screen first tab (§13.4) |
| GET | `/api/plans/:projectId` | `PlanSummary[]` — first-class plans for a project (§13.6). (Equivalent to the task's `/api/projects/:projectId/plans`; the flat `/api/plans/*` form is canonical here, matching `/api/compliance/:projectId`.) |
| GET | `/api/plans/:projectId/:planId` | `PlanDetail` — one plan: brief-ready fields + EPIC members, progress, AC%, `plan_duration_sec`, audit summary, `auditTrend`, current `backlog` rows + counts (the FE computes the `BacklogDelta` client-side, MF2), full `LessonsView` (§13.6) |
| GET | `/api/analytics/plans?project=&outcome=&since=` | `PlanOutcomeAnalytics` — cross-project plan results (§13.12); exact project/outcome filters, `since` applies to `lastActivityAt`; invalid enum/timestamp → 400, unknown explicit project → 404 |
| GET | `/api/lessons?project=&plan=` | `LessonsView` — lessons-per-plan / per-project / cross-infra (scope inferred from params: both → plan, project only → project, neither → infra) (§13.8) |
| ~~GET~~ | ~~`/api/backlog-delta`~~ | **REMOVED from MVP1 (MF2)** — `backlog.md` has no per-row timestamps and the server is stateless, so a server `?since=` field-level delta is not computable. The delta is computed **client-side** from a localStorage `BacklogSnapshot` (§13.7); the server serves current rows via `/api/backlog` (`openCount`/`closedCount` in `meta`). Server-side field-level delta = MVP1.5. |
| GET | `/api/memory` | `MemoryResult` — **MVP1 STUB**: always returns `{ available:false, reason:"MVP2", entries:[] }`; never queries Qdrant. Wired to the read-only `vulcan-memory` MCP in MVP2 (§13.9) |
| GET | `/api/audit-summary/:projectId` | `AuditSummary` (project-scope **`aggregateAudit`**, §13.5.7 / MF7) — the median-EPIC summary across the project's audited EPICs; `present:true, overallScore:null` + a warning when no audited EPIC has a score (e.g. sousto-na-miru) |
| GET | `/api/audit-trend/:projectId` | `AuditTrend` (scope `project`, MF7) — score-over-time across the project's audited EPICs (one point per EPIC's latest audited run, §13.5); powers the Screen B Audit tab |
| GET | `/api/audit-trend/:projectId/:epicId` | `AuditTrend` (scope `epic`) — score-over-time across the EPIC's runs (§13.5); thin chart-only endpoint, also embedded in `EpicDetail.auditTrend` |
| GET | `/api/audit-trend/:projectId/plan/:planId` | `AuditTrend` (scope `plan`) — score-over-time across the plan's EPICs (§13.5); also embedded in `PlanSummary.auditTrend` |
| GET | `/api/projects` | `Project[]` — cross-project tiles |
| GET | `/api/projects/:projectId` | `ProjectDetail` — Project + epics index + queue + recent activity |
| GET | `/api/projects/:projectId/epics` | `EpicSummary[]` |
| GET | `/api/epics/:projectId/:epicId` | `EpicDetail` — spec, all runs, latest `RunDetail`, metrics, explanations |
| GET | `/api/epics/:projectId/:epicId/runs/:runId` | `RunDetail` |
| GET | `/api/epics/:projectId/:epicId/runs/:runId/file?name=…` | `{ format, content }` — **path-validated + name allow-listed per §7.4.1** |
| GET | `/api/compliance` | `ComplianceView` — cross-project rollup |
| GET | `/api/compliance/:projectId` | `ComplianceView` scoped |
| GET | `/api/backlog?project=` | `BacklogItem[]` (current rows, read-only); `meta: { openCount, closedCount, warnings }` carries the absolute counts (§13.7). The FE diffs these rows against its localStorage `BacklogSnapshot` to produce the `BacklogDelta` client-side (MF2). |
| GET | `/api/activity?project=&topic=&limit=` | `ActivityEvent[]` — merged, time-sorted; WS-replay bootstrap |
| GET | `/api/queue?project=` | `QueueEntry[]` |
| GET | `/api/metrics/:projectId/:epicId` | `MetricSet` |
| GET | `/api/explanations?lang=cs` | `Record<string, Explanation>` — Czech dictionary (powers help + tooltips) |
| WS | `/ws` | WebSocket (§7.3) |

`/projects` sorts active/running first. `latestRun` per §7.2.

#### 7.4.1 Raw-file endpoint security (`/file` — concrete spec, not "path-validated + name allow-listed")

The `/file` endpoint serves a single artifact's contents for the raw-artifact drawer. Grounded facts that bound the spec: there are **no symlinks under `.aid-o`**, the largest artifact is **125 KB**, and there are **no real secrets** in evidence — but the endpoint is still hardened against path traversal (CWE-22) because it takes a user-supplied `name`. Resolution goes through the §9.6 `pathmap` (container path for the read, host path only for display). Rules:

1. **Resolution root:** the file is resolved **ONLY** within `<resolved run dir>/` and its known subdirs (`gates/`, `reporter/`, `steps/`), plus `<proj>/.aid-o/reports/`. Anything outside these → **404**.
2. **Name allow-list (artifact patterns):** `name` is matched against an allow-list — `fsm-state.yaml`, `compliance.json`, `gates_report.json`, `plan.json`, `plan-diff.json`, `timeline.jsonl`, `epic-summary.md`, `final_report.md`, `audit-report.md`, `curator-report.md`, `simplifier-report.md`, `verifier-output-*.md`, `step-*-verify.md`, `reporter/*`. Anything else → **404**.
3. **Canonicalize + assert prefix:** resolve with `realpath`, then assert the result `startsWith` the resolved run dir (CWE-22). **Reject** any `name` containing `..`, any absolute path, and any **symlink** — `lstat` the target and if it is a symlink return **403** (no symlinks exist under `.aid-o`, so a symlink is always anomalous).
4. **Size cap 1 MB:** if the file exceeds 1 MB return **413** (and **414** if the request URI / `name` is over-long); the largest real artifact is 125 KB, so 1 MB is a generous safety ceiling.

(This reuses `routes/path-validation.ts` `validateEvidencePath`, §7.1. Answers auditor Q5.)

**Unit test (required):** a `name` containing `../`, an absolute path (`/etc/passwd`), and a symlink are **each rejected** (404/403); an allow-listed artifact (e.g. `gates_report.json`) is **served**.

### 7.5 TypeScript data contracts (`packages/aid-contract`)

Two layers: **raw** (snake_case, mirrors disk — extend existing `aid-contract/src/types.ts`) and **view** (camelCase, the API surface, below).

**Nullability convention (binding):** every value the §5.6 "NOT computable" list can omit is typed `| null`; a null with a `warnings[]`/`source` tag is the honest rendering, never a fabricated 0/pass/fail. Scores, timings, provenance, and per-checkpoint retry counts are all nullable for exactly this reason.

```ts
export type FsmState = 'READY' | 'EXECUTE' | 'GATES' | 'ESCALATION' | 'DONE' | 'ERROR';
export type RunFormat = 'v3' | 'legacy' | 'stub';
export type CheckpointId = 'CP1'|'CP2'|'CP3'|'CP4'|'CP5'|'CP6';
export type Verdict = 'pass' | 'fail' | 'skipped' | 'unverifiable' | null;

// Headline-score envelope (§5.7) — never a bare number; carries honesty metadata.
export interface Score {
  value: number | null;
  partial: boolean;
  confidence: 'high' | 'low';
  components: Record<string, number | null>;
  warnings: string[];
}

export interface Project {
  id: string; name: string; path: string; aidoPath: string;
  discovered: boolean; partial: boolean;
  epicsTotal: number; epicsActive: number; runsTotal: number;
  activeRun: { epicId: string; runId: string; state: FsmState } | null;
  health: {
    value: number | null; partial: boolean; confidence: 'high' | 'low';
    compliancePassRate: number | null; openViolations: number;
    lastGateOverall: 'pass'|'fail'|null; warnings: string[];
  };
  lastActivityAt: string | null;
}
export interface ProjectDetail extends Project {
  epics: EpicSummary[]; queue: QueueEntry[]; recentActivity: ActivityEvent[];
  aggregateAudit: AuditSummary & { scoredEpicCount: number; medianEpicId: string | null };
                                                  // MF7/SF4: project-scope aggregate = the MEDIAN-score audited EPIC's AuditSummary (§13.5.7); overallScore = median; scoredEpicCount===0 → present:true, overallScore:null + warning (e.g. sousto-na-miru). Same shape as PlanDetail.aggregateAudit. Also served standalone by GET /api/audit-summary/:projectId.
  auditTrend: AuditTrend;                         // MF7: project-scope score-over-time, scope:'project', one point per audited EPIC (§13.5.4). Also served by GET /api/audit-trend/:projectId.
}
export interface EpicSummary {
  projectId: string; id: string; title: string; status: string;
  planRef: string | null; runsTotal: number; runsCompleted: number;
  membershipSource?: MembershipSource;            // MF1: how this EPIC was attached to its plan (§13.6); 'derived' (id→Pxxx) is OFFICIAL but weaker (warning), NOT fast-mode-excluded. Optional — only set when the EPIC was resolved into a plan (undefined for a bare cross-project EPIC list).
  latestRun: { runId: string; state: FsmState; format: RunFormat; startedAt: string|null } | null;
  lastActivityAt: string | null;
}
export interface EpicDetail extends EpicSummary {
  spec: EpicSpec; runs: RunSummary[]; latest: RunDetail | null;
  metrics: MetricSet; explanations: DictionaryEntry['id'][];
  auditTrend: AuditTrend;                         // score-over-time across this EPIC's runs (§13.5); empty points[] when no audited run
}
export interface RunSummary {
  runId: string; format: RunFormat; state: FsmState;
  startedAt: string|null; finishedAt: string|null; durationS: number|null;
  overallGate: 'pass'|'fail'|null; complianceOverall: 'pass'|'fail'|null;
}
export interface RunDetail {
  projectId: string; epicId: string; runId: string; format: RunFormat;
  state: FsmState; mode: string; branch: string; baseCommit: string;
  currentStep: number; totalSteps: number; gateRetries: number; escalationCount: number;
  startedAt: string|null; createdAt: string|null; donePhase: string|null; pmDecision: string|null;
  steps: RunStep[]; checkpoints: Checkpoint[]; gates: GateResult[];
  compliance: ComplianceRun | null; reports: ReportRef[];
  audit: AuditSummary;                            // structured per-run audit summary (§13.5); audit.present=false when no audit-report.md
  timeline: ActivityEvent[]; files: string[];
}
export interface RunStep {
  id: string | number; name: string;
  status: 'pending'|'executing'|'done'|'failed'|'completed';
  role: string|null; startedAt: string|null; completedAt: string|null; durationS: number|null;
}
export interface Checkpoint {           // CP1-CP6 are CHECKPOINTS, not agents
  id: CheckpointId; label: string;
  dispatched: boolean; verdict: Verdict;
  provenance: string | string[] | null;        // MF4: "agent_tool"|"unverifiable"|per-step array|null.
                                                //   null = not recorded (CP1 has no provenance field; older/no-compliance runs)
  provenanceSource: 'compliance' | 'timeline' | null;  // MF4: where provenance came from —
                                                //   'compliance' = compliance.json verifier_outputs.*_provenance (source of truth);
                                                //   'timeline' = corroborating dispatch pairs only (rare); null = none recorded
  repeatCount: number | null;           // CP1 from files; CP2/3/4 from timeline or null; gates from attempts
  repeatSource: 'files' | 'timeline' | null;  // how repeatCount was derived; null when unknown ("?")
  outputs: { name: string; relPath: string }[];
}
export interface GateResult {
  gate: string; result: 'pass'|'fail'|'skipped';
  exitCode: number; durationMs: number; attempts: number; outputPreview: string;
}
// MF3 — structured compliance failure (disk shape, §4.5). Replaces the lossy
// `failures: string[]`. Risk (S1), health.openViolations, and the §5.7 "resolved
// blocking failure" rule all need `severity` + `check`, so the structure is
// preserved end-to-end. `promotedAt` mirrors disk `promoted_at` (severity
// promotion provenance, §4.5 check-severity); null/absent on un-promoted rows.
export interface ComplianceFailure {
  check: string;                                  // the failing check id, e.g. "verifier_provenance"
  evidence: string;                               // disk `evidence` string (path / short reason)
  severity: 'blocking' | 'advisory';              // blocking blocks release; advisory only logged (§4.5)
  promotedAt?: string | null;                     // disk `promoted_at` — when severity was promoted; null/absent if never
}
export interface ComplianceRun {
  epicId: string; runId: string; aidVersion: string; deployEra: string; evaluatedAt: string;
  coverageMode: string | null; overall: 'pass'|'fail';
  checks: Record<string, unknown>; failures: ComplianceFailure[];   // MF3: structured {check,evidence,severity,promotedAt}, was string[]
  forceOverrideCount: number; forceOverrideReasons: string[]; notes: string[];
}
export interface ComplianceView {
  scope: 'all' | string; fsmAdherenceScore: Score; passRate: number;
  totals: { runs: number; passed: number; failed: number; forceOverrides: number };
  violations: { projectId: string; epicId: string; runId: string;
    overall: 'fail'; failures: ComplianceFailure[]; forceOverrideCount: number; evaluatedAt: string; }[];  // MF3: structured failures
}
export interface ActivityEvent {
  projectId: string; epicId?: string; runId?: string;
  ts: string; event: string; from?: FsmState; to?: FsmState;
  step?: number|string; gate?: string; role?: string;
  result?: 'pass'|'fail'; durationS?: number; raw: Record<string, unknown>;
}
export interface MetricSet {
  epicWallTimeS: number | null; runCount: number;          // runCount reliable (dir count)
  stepDurationsS: (number | null)[];                       // per-step nullable (§5.1/§5.6)
  avgStepDurationS: number | null;
  longestStep: { id: string|number; durationS: number } | null;
  stepTimingSource: 'mtime' | 'dispatch' | null;           // how step timings were derived
  gateRuns: number; gateRetries: number;                   // reliable from gates_report.json/dir counts
  checkpointRepeats: Record<CheckpointId, number | null>;  // null when not derivable (§MF5)
  escalations: number;
  timeBy: TimeSource[];                                    // SEAM (§13.9): per-actor time. MVP1 = user/dev durationS:null source:null ("neměřeno"); ai/controller best-effort from §5.1. NOT an MVP1 feature, the slot only.
  partial: boolean; warnings: string[];
}
// Static dictionary content — ONE source for both live UI and Help (§6.4, §8.4, §8.2 Help).
export interface DictionaryEntry {
  id: string;
  kind: 'state'|'event'|'cp'|'role'|'verdict'|'severity'|'check'|'concept';
  status: StatusKey;
  headlineTemplate: string;            // one-line, {var}-interpolated by explain()
  detailTemplate: string;              // 1-3 sentences, {var}-interpolated
  term: string;                        // Help display label
  keywords: string[];                  // Help search index
}
// Runtime resolution returned by explain() (§6.4) — distinct from DictionaryEntry.
export interface Explanation {
  headline: string;                    // resolved + interpolated
  detail: string;
  status: StatusKey;                   // drives colour + filter chips
  color: string;                       // resolved CSS var
}
export interface QueueEntry { epicId: string; path: string; priority: string; status: string; addedAt: string; }
export interface BacklogItem { projectId: string; id: string|null; title: string; status: string|null; raw: string; }
export interface ReportRef { kind: 'audit'|'curator'|'reporter'|'epic-summary'|'final'|'other'; name: string; relPath: string; }
export interface EpicSpec { /* parseEpicSpec output: epicId,title,context,goal,scope,steps,acceptanceCriteria,dodGates,hints */ }

// ── Managerial layer (Rev 3, §13) ─────────────────────────────────────────────
// Plan = first-class entity. One Plan groups EPICs by plan_path (§5.4 EPIC→plan).
// How an EPIC was placed into its plan (§13.6 four-tier precedence, MF1).
// 'derived' is an OFFICIAL but WEAKER membership (id E-{NNN} → P{NNN} matched a real plan file),
// NOT fast-mode-excluded; 'orphan' is the only non-member tier (counted in orphanEpicCount).
export type MembershipSource = 'plan_path' | 'plan_ref' | 'derived' | 'orphan';
export interface PlanSummary {
  projectId: string; planId: string;            // plan STEM — PRIMARY identity (e.g. "P046-foo"); number is only an alias (§13.6 stem-primary). An explicit plan_path/plan_ref resolves to its EXACT stem; an id-derived/number-only member attaches only when the number is unambiguous.
  title: string; planRef: string;               // path of the plan .md
  epicIds: string[];                             // member EPIC ids (tiers 1-3; orphans excluded — §13.6)
  epicMembers: { epicId: string; membershipSource: MembershipSource }[]; // per-EPIC resolution tier (MF1); 'derived' rows carry a warning so the weaker grouping is visible
  membershipMixed: boolean;                      // true when members span >1 source tier (e.g. P046: plan_ref + derived) — drives the "přiřazeno podle čísla EPICu" note
  epicsTotal: number; epicsDone: number;
  progressPct: number;                           // done_epics/total_epics*100 (§5.5)
  acPct: number | null;                          // Σpresent/Σac_count (§5.5); null = not measured
  lessonsPreview: { date: string|null; lesson: string; epicId: string|null }[]; // thin list-row lessons-per-plan (§4.7); PlanDetail carries the full LessonsView under `lessons`
  auditTrend: AuditTrend;                         // score-over-time across this plan's EPICs (§13.5); one point per audited latest-run per EPIC
  lastActivityAt: string | null;
}

// ── CROSS-PROJECT PLAN OUTCOMES (Rev 4.1, §13.12) ────────────────────────────
// Pure scanner-cache projection. Missing proof/retry evidence remains unknown;
// it MUST NOT be converted to zero, pass, or a successful plan outcome.
export type PlanOutcome = 'passed' | 'partial' | 'failed' | 'in_progress' | 'unverifiable';
export interface PlanOutcomeSummary {
  projectId: string;
  planId: string;            // plan STEM — PRIMARY identity (e.g. "P046-foo"); colliding numbers stay DISTINCT rows (§13.6 stem-primary)
  ambiguousNumber: boolean;  // true when planId's plan NUMBER is shared by >=2 stems → number alias is unusable (lookup by number → 409)
  title: string;
  outcome: PlanOutcome;
  epicsTotal: number; epicsDone: number; runsTotal: number; failedRuns: number;
  gateFailures: number; gateRetries: number;
  checkpointRetries: { knownTotal: number; unknownCheckpoints: number };
  fsmFailures: { precondition: number; increment: number; doneAdvance: number; other: number };
  escalations: number; forceOverrides: number;
  compliance: { passed: number; failed: number; unknown: number };
  topFailureReasons: { reason: string; count: number }[];
  firstStartedAt: string | null; lastCompletedAt: string | null; lastActivityAt: string | null;
  dataPartial: boolean;
  warnings: string[];
}
export interface PlanOutcomeAnalytics {
  generatedAt: string;
  plans: PlanOutcomeSummary[];
  totals: {
    plans: number; passed: number; partial: number; failed: number;
    inProgress: number; unverifiable: number; failedRuns: number;
    gateFailures: number; gateRetries: number; escalations: number; forceOverrides: number;
  };
  partialProjects: string[];
}

// Deterministic RISK (§13.2). Level from countable real signals only; never a fake probability.
export type RiskLevel = 'nizke' | 'stredni' | 'vysoke' | 'neurceno';
export interface RiskReason {
  text: string;                                  // human Czech line (lidská řeč)
  status: StatusKey;                             // §6.2 token — drives colour
  signal: string;                                // machine id of the firing signal, e.g. "open_blocking_violations"
  value?: number | string;                       // the countable value that fired it (audit trail)
}
export interface Risk {
  level: RiskLevel;                              // 'neurceno' when data coverage insufficient (§13.2 coverage rule)
  reasons: RiskReason[];                         // empty + level 'nizke' = clean; empty + 'neurceno' = no data
  confidence: 'high' | 'low';                    // 'low' when key signals are missing/thin
}

// One BriefItem = one thing the manager should see, already explained (reuses §6 dictionary).
export interface BriefItem {
  id: string;                                    // stable key, e.g. "wan/E-035/plan_ac_match"
  projectId: string; epicId?: string; planId?: string; runId?: string;
  title: string;                                 // short technical label (e.g. "plan_ac_match")
  explanation: Explanation;                      // {headline, detail, status, color} resolved via explain() (§6.4)
  severity: 'blocking' | 'warn' | 'info';        // routing/sort key (blocking first)
  signal: string;                                // machine id, e.g. "open_blocking_violation"
  at: string | null;                             // when the underlying signal last changed (for sorting / lastSeen)
  href: string;                                  // deep-link into Screen B/C/Plan (e.g. "/p/wan/e/E-035")
}

// MF5 — successProbability envelope. Forward-compatible for MVP2 WITHOUT contract
// churn, while the binding MVP1 invariant keeps "flag, never fake": in MVP1
// `value` MUST be null AND `source` MUST be null (no model exists to produce a
// number — D2). MVP2's LLM agent fills `value` with `source:'agent'`. The UI
// renders "přesnější odhad přijde s agentem (MVP2)" while value===null.
export interface SuccessProbability {
  value: number | null;                          // 0-100 probability. MVP1 INVARIANT: MUST be null.
  source: 'agent' | null;                        // MVP1 INVARIANT: MUST be null. MVP2: 'agent'.
  confidence?: 'high' | 'low';                   // optional; only meaningful once value is non-null (MVP2)
}

// THE managerial read-model. ONE shape, THREE scopes (D1). Screen G = infra; Screen B tab 1 = project;
// Plan screen tab 1 = plan. Answers the seven PM questions (§13.1).
export interface Brief {
  scope: 'infra' | 'project' | 'plan';
  projectId: string | null;                      // null for infra scope
  planId: string | null;                         // set only for plan scope
  generatedAt: string;                           // server scan time (ISO-8601 UTC)
  sinceLastSeen: {                               // "co se změnilo od poslední návštěvy" — vs client lastSeen (§13.3)
    since: string | null;                        // the lastSeen timestamp the client sent (null = first visit)
    items: BriefItem[];                          // new/changed runs, new gate fails, new violations, new backlog, transitions since `since`
    counts: { newRuns: number; newGateFails: number; newViolations: number;
              newBacklog: number; stateTransitions: number };
  };
  blockers: BriefItem[];                          // "co blokuje postup" — open blocking failures, ESCALATION, repeated precond fails, stuck/stale, missing PM decision
  watchOuts: BriefItem[];                         // "na co si dát pozor" — advisory violations, force-overrides, retry hot-spots, branch mismatch, stale, non-blocking audit findings
  nextUp: BriefItem[];                            // "co bude následovat" — queue next EPICs, runs in READY/EXECUTE, plan progress
  decisionsNeeded: BriefItem[];                   // "jaká rozhodnutí jsou potřeba" — runs awaiting PM decision/merge, ESCALATION needing a human, blocking audit findings
  risk: Risk;                                     // "odhad rizika" — deterministic level + reasons (§13.2)
  successProbability: SuccessProbability;         // MF5 — envelope; binding MVP1 invariant value===null && source===null;
                                                  //   UI renders "přesnější odhad přijde s agentem (MVP2)" (D2). MVP2 fills value with source:'agent' (no churn)
}

// ── Structured AUDIT SUMMARY + trend (Rev 3, §13.5) ───────────────────────────
// Replaces "render the audit-report.md markdown". A managerial projection over the
// auditor's audit-report.md (§4.3). All fields best-effort + nullable: the ONLY reliably
// present input is blockingFindings; score/categories/findings are absent on many runs.
export type AuditSeverity = 'Critical' | 'High' | 'Medium' | 'Low';
export type AuditEffort = 'S' | 'M' | 'L' | null;          // normalized from S|M|L | small|medium|large
export interface AuditCategoryScore {
  category: string;                              // "Code Quality" | "Security" | "Documentation" | "Process" | …
  score: number;                                 // normalized to /100 (a /25 cell ×4; see §13.5 normalization)
  rawScore: string;                              // verbatim cell, e.g. "22/25" | "92" | "100" (provenance, never lost)
  max: 25 | 100;                                 // detected denominator of rawScore
  status: string | null;                         // "PASS" | "WARN" | … when a Status column exists, else null
}
export interface AuditFinding {
  severity: AuditSeverity;
  area: string | null;                           // file:line when present
  auditType: string | null;                      // "process" | "security" | "code" | …
  finding: string;                               // the finding text (1-3 sentences)
  recommendation: string | null;
  effort: AuditEffort;
  autoFixable: boolean | null;                   // null = field absent (distinct from explicit false)
}
export interface AuditNextStep {
  finding: string;                               // short label of what to do
  severity: AuditSeverity;
  effort: AuditEffort;
  autoFixable: boolean | null;
  rank: number;                                  // sort key: severity-weight × effort-cheapness (§13.5)
}
export interface AuditSummary {
  present: boolean;                              // false = no audit-report.md for this run (render "auditor zatím neběžel")
  overallScore: number | null;                   // best-effort /100; null when no parseable score (§4.3 three shapes)
  scoreSource: 'frontmatter' | 'heading' | 'table' | null;  // which of the 3 shapes matched (provenance)
  blockingFindings: boolean | null;              // the ONLY reliably-present auditor field; null only when even it is unparseable
  blockingFindingsSource: 'frontmatter' | 'heading' | 'bold' | 'inline' | 'numeric' | null; // §13.5 6-form parse
  categories: AuditCategoryScore[];              // [] when no score table present
  topReasons: string[];                          // why the score is what it is — derived from largest deductions / highest-severity findings (§13.5)
  topRisks: AuditFinding[];                       // Critical + High findings, severity-desc
  countsBySeverity: { Critical: number; High: number; Medium: number; Low: number };
  autoFixableCount: number;                       // findings with autoFixable === true
  nextSteps: AuditNextStep[];                      // recommended actions, sorted severity × effort (§13.5)
  headlineCs: string;                              // DETERMINISTIC Czech "proč audit dopadl takhle" (§13.5) — NOT an LLM narrative
  previousScoreHint: { score: number | null; ref: string | null } | null; // auditor's own "Previous audit … Score: N/100" line, when present (§13.5)
  rawRelPath: string;                              // path for the raw-markdown drawer (served via /file, §7.4.1)
  warnings: string[];                              // parse degradations (e.g. "score unparseable", "blocking_findings inferred from prose")
}
// AUDIT TREND — score-over-time across runs of an EPIC and across EPICs of a plan.
export interface AuditTrendPoint {
  runId: string; epicId: string;
  startedAt: string | null;                       // run started_at — the time ORDERING key (§13.5)
  score: number | null;                           // null = real gap (run had no parseable score); NEVER interpolated
  blockingFindings: boolean | null;
}
export interface AuditTrend {
  scope: 'epic' | 'plan' | 'project';              // 'project' = MF7 project-scope trend (one point per audited EPIC)
  points: AuditTrendPoint[];                       // chronological by startedAt; gaps kept as score:null, not dropped
  scoredPointCount: number;                        // how many points actually have a number (drives "málo dat" UI)
  delta: number | null;                            // last scored − first scored; null when <2 scored points
}

// ── PLAN as a first-class entity (Rev 3, §13.6) ───────────────────────────────
// PlanSummary (above) = the list-row / brief-scope projection. PlanDetail = the
// full Plan screen (/p/:project/plans/:planId): brief + phases + EPIC members +
// audit (boundaryAudit + aggregateAudit) + trend + AC + backlog + lessons.
// Membership = the §13.6 four-tier precedence (plan_path → plan_ref → id-derived
// E-{NNN}→P{NNN} → orphan, MF1); tiers 1-3 are members (tier 3 = official-but-weaker,
// 'derived'); ONLY tier-4 orphans are excluded and counted in orphanEpicCount.
export interface PlanDetail extends PlanSummary {
  description: string | null;                      // first prose block of the plan .md (gray-matter body), null when unparseable
  epics: EpicSummary[];                            // member EPICs, status-weighted sort (same order as Screen B)
  orphanEpicCount: number;                         // tier-4 orphan EPICs only (no plan_path, no plan_ref, no matching P{NNN} file — §13.6); NOT id-derived members
  durationS: number | null;                        // plan_duration_sec (§5.1): min EPIC start → max EPIC end; null = no parseable run
  boundaryAudit: AuditSummary;                     // the SINGLE plan-boundary auditor run = latest audited run of the plan's LAST EPIC (§13.5.7); present=false when none
  aggregateAudit: AuditSummary & { scoredEpicCount: number; medianEpicId: string | null };
                                                    // cross-EPIC aggregate = the MEDIAN-score member EPIC's AuditSummary (SF4 / §13.5.7); overallScore = median; medianEpicId names the chosen real report; scoredEpicCount drives sparse handling (0 → overallScore:null + warning; 1 → "n=1" warning)
  deliveryReport: ReporterDelivery;                 // MF6: the plan-boundary Reporter delivery report (§4.3); present=false when no reports/{plan_id}-delivery.md. Rendered on the Plan "Dodávka & zjednodušení" tab.
  simplifierSummary: SimplifierSummary;             // MF6: the plan-boundary Simplifier proposals (§4.3); present=false when no simplifier-report.md. Rendered alongside deliveryReport on the same tab.
  backlog: { items: BacklogItem[]; openCount: number; closedCount: number; warnings: string[] };
                                                    // CURRENT backlog rows + absolute counts for this plan's EPICs (MF2);
                                                    // the FE computes the BacklogDelta locally from its localStorage snapshot (§13.7) —
                                                    // the server does NOT field-level diff (no per-row timestamps, stateless). No backlogDelta on the server response.
  lessons: LessonsView;                             // lessons-per-plan (§13.8); the full view. PlanSummary carries only the thin `lessonsPreview[]` (no field clash — distinct names so `extends` type-checks)
  warnings: string[];                              // aggregation degradations (e.g. "no plan_ref on any EPIC — grouped by filename")
}

// ── REPORTER DELIVERY + SIMPLIFIER (Rev 4, MF6) — plan-boundary role outputs ────
// First-class projections of the two plan-boundary roles the PM explicitly wants at
// PLAN level (§4.3): the Reporter delivery report and the Simplifier proposals. Both
// are best-effort + nullable (many plans have neither yet) and follow flag-never-fake:
// present:false renders "Reporter/Simplifier zatím neběžel", never a fabricated outcome.
export type DeliveryOutcome = 'pass' | 'fail' | 'partial' | null; // mapped from the report's Outcome line; null = not stated/unparseable
export interface ReporterTestEvidence {
  name: string;                                    // artifact file name (anti-fabrication: MUST exist on disk, §4.3 `_test_evidence[]`)
  relPath: string;                                 // path served via /file (§7.4.1) for the link/drawer
  exists: boolean;                                 // verified on disk — false flags a missing/fabricated evidence link (rendered honestly, never silently dropped)
}
export interface ReporterDelivery {
  present: boolean;                                // false = no reports/{plan_id}-delivery.md (render "Reporter zatím neběžel")
  outcome: DeliveryOutcome;                        // PASS/FAIL/PARTIAL headline of the delivery, null when not stated
  summaryCs: string | null;                        // a short Czech "co se dodalo" line (from the report's outcome/summary section), null when unparseable
  generatedBy: string | null;                      // frontmatter `_generated_by` (e.g. "aid-orchestrator:reporter@…"), null when absent
  generatedAt: string | null;                      // frontmatter `_generated_at` ISO, null when absent
  testEvidence: ReporterTestEvidence[];            // the `_test_evidence[]` artifacts (each existence-checked); [] when none
  rawRelPath: string | null;                       // path to the full delivery .md for the drawer (/file); null when present:false
  warnings: string[];                              // parse degradations (e.g. "outcome unparseable", "1 test-evidence file missing on disk")
}
export type SimplifierDisposition = 'approve' | 'reject' | 'defer' | null; // recommended_disposition; null when not stated
export interface SimplifierProposal {
  id: string | null;                               // proposal id when present (IMP-/PROP-), null when none
  area: string | null;                             // file/component the proposal targets
  proposal: string;                                // the simplification text (1-3 sentences)
  disposition: SimplifierDisposition;              // recommended_disposition (the Simplifier proposes only — never edits code, §4.3)
  effort: AuditEffort;                             // S|M|L normalized (reuses the audit effort scale); null when not stated
}
export interface SimplifierSummary {
  present: boolean;                                // false = no simplifier-report.md (render "Simplifier zatím neběžel")
  proposalCount: number;                           // proposals.length (drives "N návrhů na zjednodušení")
  proposals: SimplifierProposal[];                 // the propose-only list; [] when present:false
  headlineCs: string | null;                       // deterministic Czech "co navrhuje zjednodušit" line, null when present:false
  rawRelPath: string | null;                       // path to the full simplifier-report.md for the drawer (/file); null when present:false
  warnings: string[];                              // parse degradations
}

// ── BACKLOG DELTA (Rev 3, §13.7) — "co přibylo / ubylo" — CLIENT-SIDE in MVP1 ──
// MF2 RESOLUTION: backlog.md has NO per-row timestamps and the server is stateless,
// so a server `?since=`-diff cannot know added/closed/priority/status changes. In
// MVP1 the DELTA is computed CLIENT-SIDE: the server serves the current rows
// (`GET /api/backlog`) and the absolute openCount; the FE stores the full row set
// (id+status+priority) in localStorage keyed by scopeKey+lastSeen (§13.3) and diffs
// current-vs-snapshot locally. `BacklogDelta` is therefore a CLIENT-COMPUTED shape
// (contract type so FE store + components agree), NOT a server response. The
// server-side field-level `/api/backlog-delta?since=` endpoint is REMOVED from MVP1
// (server field-level delta = MVP1.5, when a snapshot store exists, §10).
//
// BacklogSnapshot is what the FE persists in localStorage per scopeKey; BacklogDelta
// is the FE-computed diff of the current rows vs the most recent snapshot.
export interface BacklogSnapshotRow {
  id: string | null;                              // IMP-{NNN} / PROP-* (null when the row has no parseable id)
  status: string | null;                          // proposed|pending|approved|rejected|deferred (null when absent)
  priority: string | null;                        // the Priority cell (null when absent)
}
export interface BacklogSnapshot {
  version: 1;                                     // forward-compatible localStorage migration
  scopeKey: string;                               // "project:wan" | "plan:wan/P003" — matches the §13.3 lastSeen scope key
  lastSeen: string;                               // ISO-8601 UTC when this snapshot was taken (the prior-visit marker)
  rows: BacklogSnapshotRow[];                     // the full set of backlog rows captured at lastSeen
}
export interface BacklogDeltaItem {
  id: string | null;                              // IMP-{NNN} / PROP-* (null when the row has no parseable id)
  title: string;                                  // the Suggestion cell (from the current GET /api/backlog rows)
  type: string | null;                            // Type cell
  area: string | null;                            // Area cell
  status: string | null;                          // proposed|pending|approved|rejected|deferred (null when absent)
  priority: string | null;                        // current Priority cell
  changeSince: 'added' | 'closed' | 'priorityChanged' | 'statusChanged' | 'unchanged';
                                                  // vs the localStorage snapshot; 'unchanged' on first visit (no snapshot)
  prevStatus?: string | null;                     // snapshot status, set on statusChanged/closed
  prevPriority?: string | null;                   // snapshot priority, set on priorityChanged
}
export interface BacklogDelta {                   // CLIENT-COMPUTED in MVP1 (FE diff of current rows vs localStorage snapshot)
  scope: 'project' | 'plan';
  projectId: string; planId: string | null;       // planId set only for plan scope
  openCount: number;                              // current "Active proposals: N" (running open count, §4.6) — from GET /api/backlog meta
  closedCount: number;                            // created (counter) − open; 0 when not derivable, flagged in warnings
  firstVisit: boolean;                            // true when no prior localStorage snapshot exists → no comparison, "vše jako nové"
  lastSeen: string | null;                        // the snapshot's lastSeen the diff ran against (null on firstVisit)
  added: BacklogDeltaItem[];                      // rows present now, absent from the snapshot (changeSince:'added')
  closed: BacklogDeltaItem[];                     // rows that moved to a closed status (approved|rejected|deferred) since snapshot
  priorityChanged: BacklogDeltaItem[];            // rows whose Priority cell differs from the snapshot
  statusChanged: BacklogDeltaItem[];              // rows whose status changed but did NOT close (e.g. proposed→pending)
  warnings: string[];                             // e.g. "closedCount not derivable (counter stale)", "first visit - no snapshot, vše jako nové"
}

// ── LESSONS-PER-PLAN (Rev 3, §13.8) ───────────────────────────────────────────
// A managerial projection over work/lessons-learned.md (§4.7), scoped to a plan
// (lessons whose Context epic_id ∈ plan's EPICs) or a project (all). Read-only.
export interface LessonEntry {
  date: string | null;                            // Date cell (ISO when parseable, else raw string, else null)
  lesson: string;                                 // the Lesson cell text
  epicId: string | null;                          // Context(epic_id) cell — links the lesson to an EPIC, null when absent
  kind: 'lesson' | 'gotcha';                      // 'gotcha' = row under "## Known Gotchas"; 'lesson' = main table
}
export interface LessonsView {
  scope: 'plan' | 'project' | 'infra';
  projectId: string | null; planId: string | null;
  entries: LessonEntry[];                         // chronological-desc by date when parseable, else file order
  total: number;                                  // entries.length (drives "N ponaučení")
  warnings: string[];                             // e.g. "lessons-learned.md absent", "table malformed — partial parse"
}

// ── LAST-SEEN (Rev 3, §13.3) — localStorage shape, NOT a server resource (MVP1) ─
// "Co se změnilo od poslední návštěvy". MVP1 = client-side localStorage ONLY
// (keeps the server read-only/stateless — D-locked). The client persists this
// shape per scope key, sends `since` to /api/brief?since=, and the server fills
// Brief.sinceLastSeen by diffing signal change-times against `since`. Server-side
// multi-device lastSeen is MVP1.5 (a real resource then). This type lives in the
// contract so the FE store and the brief endpoint agree on the timestamp meaning.
export interface LastSeen {
  version: 1;                                     // schema version for forward-compatible localStorage migration
  scopes: Record<string, string>;                 // scopeKey ("infra" | "project:wan" | "plan:wan/P003") → ISO-8601 UTC of last visit
}

// ── SEAM: TimeSource (Rev 3, §13.9) — ARCHITECTURE SEAM ONLY, NOT an MVP1 feature ─
// Where measured time per actor would attach. MVP1 returns "neměřeno" (durationS:null,
// source:null) for user/dev; ai/controller may carry a timeline-derived best-effort
// durationS (the same §5.1 numbers, just typed by actor). A future WakaTime
// import/webhook fills user/dev with source:'wakatime'. MVP1 ships the TYPE + the
// null-returning shape; it does NOT measure user/dev time. Slots into MetricSet
// (see timeBy below) so the EPIC/run view can show a "kdo strávil kolik" breakdown
// the moment a source exists, with zero contract churn.
export interface TimeSource {
  kind: 'ai' | 'controller' | 'user' | 'dev';
  durationS: number | null;                       // null = "neměřeno" (MVP1 for user/dev; whenever no source)
  source: 'timeline' | 'wakatime' | null;         // provenance of durationS; null when neměřeno
}

// ── SEAM: Memory taxonomy (Rev 3, §13.9) — types now, READ is MVP2 ────────────
// The query/result shapes for reading AID's architectural memory (Qdrant
// clavi_facts_{tenant} via the vulcan-memory MCP, §4.7). MVP1 ships ONLY the types
// + a stub endpoint that returns { available:false, reason:"MVP2" } — it never
// touches Qdrant. MVP2 wires routes/memory.ts to the read-only MCP query. Defining
// the taxonomy now lets the scanner tag createdDuringRun on future writes and lets
// the FE Paměť view (MVP2) be built against a stable contract.
export type MemoryScope = 'plan' | 'project' | 'global';
export type MemoryType = 'brain' | 'ideas' | 'reflection' | 'skills' | 'projects';
export interface MemoryQuery {
  query: string;                                  // semantic search text
  scope?: MemoryScope;                            // 'plan' | 'project' | 'global' (omit = all scopes)
  projectId?: string;                             // filter to one project (required when scope='plan'|'project')
  planId?: string;                                // filter to one plan (required when scope='plan')
  type?: MemoryType;                              // vulcan-memory type facet (§4.7 / global memory rules)
  createdDuringRun?: string;                      // run_id filter — "co se naučilo během tohoto běhu"
  topK?: number;                                  // result cap (default server-side)
}
export interface MemoryEntry {
  id: string;                                     // Qdrant point id
  text: string;                                   // the stored fact/idea/reflection
  scope: MemoryScope;
  type: MemoryType;
  projectId: string | null;
  planId: string | null;
  createdDuringRun: string | null;               // run_id this memory was written during, when tagged (null = unknown/legacy)
  createdAt: string | null;                       // ISO-8601 when available
  score: number | null;                           // similarity score from the query (null when listing, not searching)
}
export interface MemoryResult {                   // MVP1 stub returns available:false
  available: boolean;                             // false in MVP1 (stub); true once routes/memory.ts is wired (MVP2)
  reason: string | null;                          // "MVP2" in the MVP1 stub; null when available
  entries: MemoryEntry[];                         // [] in the MVP1 stub
}
```
Grounding notes:
- `Checkpoint.provenance` is **read from `compliance.json` `checks.verifier_outputs.*_provenance`** (§4.2), NOT re-derived from timeline dispatch pairs; `Checkpoint` presence comes from the `verifier-output-cp*.md` file inventory. `repeatCount`/`repeatSource` follow the **per-checkpoint rules in §MF5/§5.2**: CP1 from the work-root file inventory (`repeatSource:'files'`); CP2/CP3/CP4 from `verifier_dispatch_start` timeline events when present (`repeatSource:'timeline'`, count = dispatches−1) else `repeatCount:null`/`repeatSource:null` (render "?", NEVER 0) because their `verifier-output-*.md` files are overwritten on retry; gates from `gates_report.json gates.{name}.attempts`. CP4 has two naming variants (`cp4-curator-validation`, `cp4-curator`) — normalize. **`Checkpoint.provenance` is `string | string[] | null` (MF4):** it is read **only** from `compliance.json` `checks.verifier_outputs.*_provenance` (`provenanceSource:'compliance'`, the source of truth), NOT re-derived from timeline dispatch pairs. When `compliance.json` is absent (older/stub runs) provenance is `null` ("not recorded"), never `"unverifiable"`. **CP1 has no `compliance.json` provenance field** (§4.2/§4.0 finding #1) so its `provenance` is always `null` and `provenanceSource:null` — CP1 surfaces verdict + presence only. The optional timeline "dispatch logged ✓" corroboration, when it exists, may set `provenanceSource:'timeline'`; it is never the source of truth.
- `ComplianceView.fsmAdherenceScore` (a `Score`) and `Project.health` are computed by the **explicit formulas + data thresholds in §5.7** — `value` may be `null` (with `components`/`warnings` showing a breakdown) when inputs are below threshold, never improvised. `partial:true` and `confidence:'low'` flag thin data per §5.7.
- `RunDetail.pmDecision` is `null` until the run merges (`pm_decision` is a conditional `fsm-state.yaml` field, §4.0/§4.1).
- `RunDetail.audit` (`AuditSummary`) is a managerial projection of the auditor's `audit-report.md` (§4.3) — **structured, not raw markdown** (§13.5). The raw markdown stays reachable via `audit.rawRelPath` + the `/file` endpoint (§7.4.1) for the drawer. `overallScore` is **best-effort** (the §4.3 three score shapes, recorded in `scoreSource`) and `null` when none parse; `blockingFindings` is the only reliably-present field and is parsed from **six on-disk forms** (§13.5). `headlineCs` is assembled **deterministically from the structured fields** (no LLM — that is MVP2). `EpicDetail.auditTrend`/`PlanSummary.auditTrend` (`AuditTrend`, plus the project-scope `AuditTrend` from `/api/audit-trend/:projectId`, MF7) carry score-over-time; points with no parseable score are kept as `score:null` (a real gap, never interpolated), ordered by run `startedAt`.
- `MetricSet` is computed from timeline deltas + `fsm-state.yaml` scalars + **verify-file mtimes** + run-dir spans; `stepDurationsS` entries are `null`/`≈` per §5.1 on runs without dispatch events, and `stepTimingSource` records whether timings came from `mtime` or `dispatch` (`null` when no step timing at all). `gateRuns`/`gateRetries`/`runCount` stay non-nullable (reliable from `gates_report.json`/dir counts). `checkpointRepeats` entries are `null` for CP2/3/4 when the timeline lacks dispatch events (§MF5). `partial`/`warnings` flag thin data. The contract nulls un-computable fields so `MetricSet` ships incrementally (§10, SF4 gate fields).
- `ComplianceRun.failures` and `ComplianceView.violations[].failures` are `ComplianceFailure[]` (MF3) — the disk `failures[]` objects `{check, evidence, severity, promoted_at}` (§4.5) are preserved verbatim, never flattened to strings. `Risk.S1` (open blocking violations, §13.2.1), `Project.health.openViolations` (§5.7), and the §5.7 "resolved blocking failure" rule all key off `failure.severity === 'blocking'` and match-by-`failure.check` across later runs — none of which is expressible against `string[]`. (`promotedAt` mirrors the disk `promoted_at` severity-promotion provenance, §4.5; null/absent on un-promoted rows.)
- `ComplianceRun.checks` is `Record<string, unknown>` precisely because keys are conditional across run vintages (`dod_present`/`delivery_report_present` absent in older runs, §4.5) — consumers must distinguish "key missing" from "value null".
- `Brief`, `Risk`, `BriefItem`, `PlanSummary` are the **Rev 3 managerial read-model** (§13). `Brief` is computed entirely from already-inventoried §4/§5 signals — it owns no new data and reads nothing new from disk; it is a server-side **projection** over the same scanner cache that backs `Project`/`EpicDetail`/`ComplianceView`. `Brief.risk` is the §13.2 `Risk`; `Brief.successProbability` is a **`SuccessProbability` envelope** (MF5), not a bare `null`. The **binding MVP1 invariant** is `value === null && source === null` — MVP1 has no model to produce a number and the invariant forbids a fabricated one (D2; the UI renders "přesnější odhad přijde s agentem (MVP2)"). MVP2's agent fills `value` with `source:'agent'` — **no contract churn**, the type was forward-compatible from MVP1. Every `BriefItem.explanation` is an `Explanation` resolved through `explain()` (§6.4) so the brief speaks the same Czech as the live UI. `PlanSummary` materializes the first-class Plan entity (D1/D4) by resolving each EPIC's plan via the **four-tier membership precedence** (`plan_path` → `plan_ref` → id-derived `E-{NNN}`→`P{NNN}` → orphan, §13.6 / MF1), recording the tier in `epicMembers[].membershipSource`; only true orphans (tier 4 — no `plan_path`, no `plan_ref`, no matching plan file) are excluded and counted in `orphanEpicCount`. The id-derived tier is an **official-but-weaker** member (carries a warning), **not** fast-mode-excluded — so aid-orchestrator's null-`plan_path` EPICs (e.g. P046 = E-046-1/2/3) are real members, not orphans.
- `PlanDetail` **extends `PlanSummary`** (it is the full Plan-screen read-model, §13.6): same four-tier plan-grouping rule, plus the member EPIC list, `plan_duration_sec` (§5.1, `null` when no parseable run), **two distinct audit metrics — `boundaryAudit` (the single plan-boundary auditor run on the last EPIC) and `aggregateAudit` (the median-EPIC summary across the plan's audited EPICs, SF4 / §13.5.7)**, the current `backlog` rows (MF2), and a `LessonsView`. `PlanSummary.lessonsPreview[]` stays the **thin list-row** shape (a few entries for the brief/row); `PlanDetail.lessons` is the **full `LessonsView`** — the two carry **distinct field names** (so `PlanDetail extends PlanSummary` type-checks cleanly), intentionally two shapes for two altitudes, both projected from the same `lessons-learned.md` (§4.7). Aggregation degradations land in `PlanDetail.warnings` (e.g. an EPIC placed by the weaker id-derived tier, or `aggregateAudit` computed from a single audited EPIC).
- `BacklogDelta` is **CLIENT-COMPUTED in MVP1** (MF2): the server serves only the current rows via `GET /api/backlog` (`BacklogItem[]`) plus the absolute `openCount`/`closedCount` in `meta` — `openCount` = the `Active proposals: N` running open count, `closedCount` = `created − open` (set `0` + a `warnings[]` note when the counter is stale and not derivable, **never a fabricated number**). Because `backlog.md` has **no per-row timestamps** and the server holds **no snapshot**, the server cannot compute a `?since=` field-level delta — so the FE stores the full current row set (`BacklogSnapshotRow` = `{id,status,priority}`) in **localStorage** keyed by `scopeKey`+`lastSeen` (§13.3, same mechanism as `Brief.sinceLastSeen`), and on the next load diffs current-vs-snapshot **locally** into `BacklogDelta { added, closed, priorityChanged, statusChanged, firstVisit }`. **The server-side `/api/backlog-delta` endpoint is REMOVED from MVP1** (server field-level delta = MVP1.5, when a snapshot store exists). On the **first visit** (no snapshot) `firstVisit:true`, the four delta lists are empty, and the UI renders "bez porovnání - vše jako nové" — honest, never a fabricated diff. Backlog **writes** stay MVP1.5 (this is a read view only; the FE-side diff is a pure local computation, no write to disk).
- `LessonsView` is a projection over `work/lessons-learned.md` (§4.7), scoped to a plan (lessons whose `Context(epic_id)` ∈ the plan's EPICs), a project (all), or infra (all projects). `## Known Gotchas` rows carry `kind:'gotcha'`; the main table carries `kind:'lesson'`. Absent/malformed file ⇒ `entries:[]` + a `warnings[]` note, never a throw (the §7.6 never-throw parser rule).
- `LastSeen` is a **localStorage shape, not a server resource in MVP1** (D-locked: keeps the server read-only/stateless). The client owns it, persists per `scopeKey`, and passes the relevant `since` to `/api/brief?since=`; for `Brief.sinceLastSeen` the server is the **pure diff function** of `since` vs signal change-times (file mtimes/`ts`). The **backlog** delta is the exception: it cannot be a server `since`-diff (no per-row timestamps, stateless server), so the FE keeps a companion `BacklogSnapshot` in localStorage under the same `scopeKey` and computes the row-level delta client-side (§13.7, MF2) — `/api/backlog` serves only current rows. `LastSeen` is in the contract so the FE store and the brief endpoint agree on the timestamp's meaning. Server-side multi-device `lastSeen` + a server-side backlog snapshot store become real resources in MVP1.5.
- **`TimeSource` is an architecture SEAM, NOT an MVP1 feature** (§13.9). `MetricSet.timeBy` is the slot: MVP1 emits `user`/`dev` with `durationS:null, source:null` ("neměřeno") and may emit `ai`/`controller` with a best-effort `durationS` from the §5.1 timeline numbers (`source:'timeline'`). A future WakaTime import/webhook fills `user`/`dev` with `source:'wakatime'` — **zero contract churn** when it lands. The UI renders "neměřeno" for any `durationS:null`; it never fabricates a per-actor time.
- **Memory taxonomy (`MemoryQuery`/`MemoryEntry`/`MemoryResult`) is in the contract now; READING is MVP2** (§13.9). MVP1 ships the types + a stub `/api/memory` returning `{ available:false, reason:"MVP2", entries:[] }` — it **never touches Qdrant**. The `scope`/`projectId`/`planId`/`type`/`createdDuringRun` filters are fixed now so MVP2's `routes/memory.ts` (read-only `vulcan-memory` MCP query over `clavi_facts_{tenant}`) and the FE Paměť view build against a stable shape. `createdDuringRun` is the run-scoped facet ("co se naučilo během tohoto běhu").

### 7.6 Build / test approach

- **`packages/aid-contract`** — pure types, no deps, `tsc`, wired as `@aid/contract`.
- **Toolchain pin (Node/Vite engine compatibility).** The host runs **Node v18.20.4**. **Vite 6 supports Node 18; Vite 7 requires Node 20+**, and recent `vite-plugin-pwa` tracks Vite 6/7. To avoid an engine mismatch: **pin `vite@^6` (already in `aid-gui/package.json`) and a `vite-plugin-pwa` version compatible with Vite 6 + Node 18**, OR bump the host/container to Node 20 LTS. The Dockerfile base image controls prod Node regardless; verify `npm run build` succeeds on Node 18 **before** committing the toolchain. This is logged as risk #12 in §11.
- **`packages/aid-server`** — Express 4 + `ws` + `chokidar@4` + `js-yaml` + `gray-matter` + `cors`, ESM. `tsx watch` dev, `tsc` build, `node dist` prod. Port 3911. This is a **fresh package** (the two existing server trees are a parts bin), so its `package.json` is authored explicitly, not inherited:
  - **dependencies (the complete fresh manifest):** `express@^4`, `ws@^8`, `chokidar@^4`, `js-yaml@^4`, `gray-matter@^4`, `cors@^2`, `p-limit@^5`, `@aid/contract` (workspace).
  - **devDependencies:** `tsx`, `typescript`, `vitest`, `supertest`, `@types/{express,ws,js-yaml,cors,node,supertest}`.
  - **MUST NOT carry over from the old `aid-server/package.json`:** `ai`, `ai-sdk-provider-claude-code` (companion/LLM — dropped), `multer` (file upload — write feature, dropped). Their presence in a Cockpit `package.json` is a review-blocker — they are the boundary marker between "fresh package" and "salvaged tree".
- **vitest** — unit-test every parser against **real `.aid-o` fixtures** copied to `tests/fixtures/aid-o/`: v3 happy path (`acta/E-007-3_4/R-E007-3/`), legacy (`state.yaml` array), stub (only timeline.jsonl), malformed (truncated JSON / bad YAML → assert `{data:null, warnings}`, never throw), backup dir (`vulcan.broken-…/.aid-o/` → assert scanner excludes it). Carry over `tests/server/{parsers,watchers/file-watcher,ws/websocket}` re-pointed at cross-project watcher/ws.
- **ScannerSpec tests:** latest-run selection by started_at/mtime not string sort (regression: `R-005-4_4-1` vs `run_20260224_115f`); partial/stub/legacy classification; deny-list exclusion; cache invalidation on simulated mtime bump.
- **API tests:** supertest with `AID_PROJECTS_ROOT` → fixture tree; assert envelope + shapes for `/projects`, `/epics/:p/:e`, `/compliance`.
- **WS tests:** connect, subscribe with `projects` filter, push a fixture change, assert the right client gets the right `event`.
- **Read-only invariant test:** grep **`src/` only** (exclude `node_modules/` and test fixtures) for the forbidden-write pattern `writeFile|writeFileSync|appendFile|appendFileSync|mkdir|mkdirSync|rm|rmSync|rmdir|unlink|unlinkSync|rename|renameSync|createWriteStream|\.open\([^)]*['"][aw]` and fail CI if any match appears outside the allow-listed MVP 1.5 write module path. (The `.open(...,'a'|'w')` clause catches append/write file handles; the MVP 1.5 backlog/personal-task write module is the single allow-listed exception.)
- **Fixture freshness:** `scripts/refresh-fixtures.sh` copies a curated subset of real run dirs; pin the acta v3 run as golden.

## 8. UI design

Stack: React 19 + Vite + Tailwind 4 + shadcn + @base-ui/react + @tanstack/react-query + react-router 7 + recharts + zustand + lucide-react. **The old "hospital/medical" metaphor is dropped entirely**; keep the useful infrastructure (FSM state-color tokens, recharts setup, file-tree, mobile sidebar mechanics) and rebuild for clarity.

### 8.1 Information architecture — screen map (Rev 3: A-G)

**Route impact of D1 — DECIDED.** Screen G "Co potřebuju vědět" (the cross-infra managerial brief) becomes the **landing route `/`**, the non-technical front door. The old Infra Overview (cross-project tiles, Screen A) moves to **`/prehled`** and is also surfaced as a **section at the bottom of Screen G** ("Projekty — celkový stav"), so the tiles are never lost — a manager lands on the brief, scrolls to the tiles; a technician jumps straight to `/prehled`. This is the smallest change that satisfies D1 without re-flowing the A→B→C drill spine: G sits **above** A, and every `BriefItem.href` deep-links down into B/C/Plan exactly as before. (Rejected alternative: keeping A at `/` with G as a tab — fails the "front door for a non-technical user" requirement, because the manager would still land on a tile grid.)

| # | Route | Screen | Satisfies |
|---|-------|--------|-----------|
| **G** | **`/`** | **Co potřebuju vědět (Managerial Brief, infra scope)** | **Cross-infra "what needs my attention" — the non-technical front door (D1)** |
| A | `/prehled` | Přehled (Infra Overview) | Cross-project tiles (also embedded as a section on G) |
| B | `/p/:project` | Projekt (Project Detail) — **tab 1 = Brief (project scope)**; tabs `Brief · EPICy · Plány · Audit · Zdraví` | Per-project drill-down; managerial brief reflows in as the first tab (D1); the **Audit** tab = project-scope `aggregateAudit` + trend (MF7) |
| Plan | `/p/:project/plans/:planId` | Plán (Plan Detail) — **tab 1 = Brief (plan scope)**; tabs `Brief · Fáze · EPICy · Audit · Dodávka & zjednodušení · AC · Backlog · Lekce` | First-class plan entity: brief, phases, EPICs, audit, **delivery & simplifier (MF6)**, AC, backlog delta, lessons (D4) |
| C | `/p/:project/e/:epic` | EPIC (Deep View) | Track EVERYTHING + human explanation of every state |
| D | `/activity` | Dění (Activity Stream) | Live activity stream with human explanations |
| E | `/compliance` | Compliance | Cross-project violations + force-overrides |
| F | `/help` | Nápověda (Help) | In-app docs (ACTA pattern) |

Drill spine: **G → A → B → {Plan, C}**. A Plan is reachable from Screen B (a "Plány" sub-tab / the EPIC's plan-ref chip) and from any `BriefItem.href` with a `planId`; an EPIC (C) is reachable from a tile, an activity event, a Plan's EPIC list, or a `BriefItem`. D, E, F are top-level siblings. Every brief item on G/B/Plan is a deep-link, so the brief is the spine's entry funnel, not a dead end.

**Navigation:** Desktop (≥1024px) — persistent left sidebar (collapsible icon-rail) + project-switcher + breadcrumb. The sidebar order leads with the brief: `Co potřebuju vědět (G) · Přehled (A) · Dění (D) · Compliance (E) · Nápověda (F)`; project + plan are reached by drill, not as top-level rail items. Tablet (768-1023px) — icon-rail by default. Mobile (<768px) — **bottom tab bar, Rev 3 (5 tabs, 56px, safe-area-inset): `Co řešit · Přehled · Dění · Compliance · Více`** — the brief (G) becomes the **first primary tab** ("Co řešit", a short label for "Co potřebuju vědět") and is the default screen on launch; the old "EPIC" tab is dropped from the primary set because an EPIC is always reached by drill (from a tile, a brief item, or an activity row) and never needs a cold top-level entry. "Více" sheet holds Nápověda, project + plan switcher, PWA-install, refresh. Detail screens (B, Plan, C) push full-screen with a back chevron — never a shrunk desktop layout.

> **Mobile bottom-tab rationale (explicit, since the set changed):** Rev 2 was `Přehled · Dění · EPIC · Compliance · Více`. Rev 3 is `Co řešit · Přehled · Dění · Compliance · Více`. Net change: **+ "Co řešit" (G) as tab 1**, **− "EPIC" as a primary tab**. Five tabs is the ergonomic ceiling for a 375px bar with 44px+ targets, so adding G means dropping one — EPIC is the correct drop because it is a leaf, not a hub. Drilling to an EPIC still works from every surface above it.

**PWA install affordance:** dismissible banner on `/` (Screen G) wired to `beforeinstallprompt`; permanent entry in mobile "Více"; desktop top-bar button. SW caches the app shell; live data always hits the network.

### 8.2 ASCII wireframes

#### SCREEN A — Přehled (Infra Overview) · projects + plan outcomes

**DESKTOP**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ [≡] AID    │  Přehled                              [⟳ 4s] [⬇ Instalovat] [hledat]│
│            │  ────────────────────────────────────────────────────────────────  │
│ ▸ Přehled  │  6 projektů · 277 běhů · 1 běží · 2 čekají na PM · 3 porušení        │
│   Projekt  │                                                                      │
│   Dění     │  ┌─ PROJEKTY (tiles) ─────────────────────────────────────────────┐ │
│   Compliance│ │ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │ │
│   Nápověda │  │ │ vulcan       ●│ │ wan         ◐│ │ acta        ✓│            │ │
│            │  │ │ ───────────   │ │ ───────────  │ │ ───────────  │            │ │
│ ───────    │  │ │ E-044-2_6     │ │ E-035-2_3    │ │ — nečinné    │            │ │
│ [project ▾]│  │ │ ███████░░ 7/9 │ │ ░ eskalace   │ │ posl. před 2d│            │ │
│ vulcan     │  │ │ EXECUTE · běží│ │ čeká na PM   │ │ 41 běhů      │            │ │
│            │  │ │ CP ●●●●○○      │ │ CP ●●●✕○○     │ │ compliance ✓ │            │ │
│            │  │ │ 12 min        │ │ 3 porušení ⚠ │ │              │            │ │
│            │  │ └──────────────┘ └──────────────┘ └──────────────┘            │ │
│            │  │ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │ │
│            │  │ │ krok        ✓│ │sousto-na-miru✓│ │aid-orch...   ●│            │ │
│            │  │ │ E-013 hotovo  │ │ — nečinné    │ │ E-046-3_3 běží│            │ │
│            │  │ └──────────────┘ └──────────────┘ └──────────────┘            │ │
│            │  └────────────────────────────────────────────────────────────────┘ │
│            │                                                                      │
│            │  ┌─ DĚJE SE TEĎ (mini live feed, 5 řádků) ──────────────────────┐   │
│            │  │ 14:22  vulcan  CP2 krok 7 prošlo  →  „Kontrola kroku OK"      │   │
│            │  │ 14:21  wan     eskalace          →  „Čeká na rozhodnutí PM"   │   │
│            │  └──────────────────────────────────────────────────────────────┘   │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
Tile anatomy: project name + status dot, active EPIC id, progress bar (`current_step/total_steps`), FSM state + human word, a CheckpointStrip mini (CP1-CP6 dots), elapsed time, violation badge. Idle projects show last-run-ago + lifetime run count. Click tile → Screen B.

Below the mini live feed, Screen A includes the Rev-4.1 **"Výsledky plánů"** band (§13.12): outcome totals, project/outcome filters, JSON-export icon, and a dense table (`Projekt · Plán · Výsledek · EPICy · Selhání · Retry · Eskalace · Override · Poslední změna`). Each row links to Plan detail. On mobile this becomes one full-width card per plan below the project tiles; filters remain above the cards and every unknown proof/retry is shown as `?`/"nelze ověřit", never zero/green.

**MOBILE (~375px)**
```
┌─────────────────────────────┐
│ AID · Přehled        [⟳][⬇] │  ← sticky header
│ 6 proj · 1 běží · 3 ⚠       │
├─────────────────────────────┤
│ ┌─────────────────────────┐ │
│ │ vulcan              ● běží│ │  ← full-width tile, tap = drill
│ │ E-044-2_6  ███████░ 7/9  │ │
│ │ EXECUTE   CP ●●●●○○  12m  │ │
│ └─────────────────────────┘ │
│ ┌─────────────────────────┐ │
│ │ wan          ◐ čeká na PM│ │
│ │ E-035-2_3   ░ eskalace   │ │
│ │ CP ●●●✕○○        3 ⚠      │ │
│ └─────────────────────────┘ │
│ ┌─────────────────────────┐ │
│ │ acta            ✓ nečinné│ │
│ └─────────────────────────┘ │
│            ⋮ (scroll)        │
├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│  ← bottom tab bar
└─────────────────────────────┘
```

#### SCREEN B — Projekt (Project Detail) · tabbed: Brief · EPICy · Plány · Audit · Zdraví

**Rev 3/4 form (rewritten in place — SF5; was the Rev 2 single "EPICy + Zdraví" two-pane).** Screen B is now a **tab strip** with **Brief (project scope) as tab 1, the default landing tab** (D1) and a **new "Audit" tab (MF7)** showing the project-level `aggregateAudit`. Tab set: **`[ Brief ][ EPICy ][ Plány ][ Audit ][ Zdraví ]`**. Nothing from Rev 2 is removed — the old EPIC list is the "EPICy" tab and the old health rail is the "Zdraví" tab; the Brief tab is detailed in "Brief-as-first-tab on Screen B" below. The **Audit** tab is project-scope: it renders `aggregateAudit` (the median-EPIC summary across the project's audited EPICs, §13.5.7), **distinct from a single plan-boundary `boundaryAudit`** (§SF4 / §13.5), by **reusing the shared `AuditSummaryCard` + `AuditTrendChart`** at project scope (no new component — same panels as the Plan/EPIC audit, fed `GET /api/audit-summary/:projectId` + `GET /api/audit-trend/:projectId`, MF7).

**DESKTOP (tab = EPICy — the Rev 2 list + health rail, now re-homed under a tab)**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ Přehled › vulcan                                       [⟳ 4s]      │
│            │ ─────────────────────────────────────────────────────────────────  │
│            │ vulcan   ● běží · 9 EPICů · 1 aktivní · compliance 94 % · 2 plány  │
│            │ [ Brief ][ EPICy ][ Plány ][ Audit ][ Zdraví ]                     │
│            │           ════════                                                  │
│            │ ┌─ EPICY ──────────────────────────────┐ ┌─ ZDRAVÍ PROJEKTU ─────┐ │
│            │ │ [vše][běží][čeká][hotovo][selhalo]    │ │  Compliance trend     │ │
│            │ │ ──────────────────────────────────── │ │  ▁▃▅▆▇▇▇  94%         │ │
│            │ │ ● E-044-2_6  EXECUTE 7/9   běží  12m →│ │  (recharts area)      │ │
│            │ │ ◐ E-044-1_6  GATES   čeká na PM   2d →│ │                       │ │
│            │ │ ✓ E-043-3_3  DONE    hotovo       5d →│ │  Doba běhu / EPIC     │ │
│            │ │ ✕ E-042-1_2  ERROR   selhalo     8d →│ │  ▇▅▇▃▆ (bar, recharts)│ │
│            │ │ ✓ E-041 …                            │ │                       │ │
│            │ │              ⋮                        │ │  Retry hot-spots      │ │
│            │ │                                       │ │  CP3 ×4 · gates ×2    │ │
│            │ │                                       │ │  Fronta: 2 čekají     │ │
│            │ └───────────────────────────────────────┘ └───────────────────────┘ │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
EPIC row: status dot, id, FSM state, progress, human status word, age, → Screen C. (The "Zdraví" rail — compliance trend area, per-EPIC duration bar, retry hot-spots, queue snippet — is its own "Zdraví" tab; on a wide desktop the EPICy tab MAY keep it as a right rail, as drawn, but on the "Zdraví" tab it is the full-width content.)

**DESKTOP (tab = Audit — NEW, MF7: project-scope `aggregateAudit`)**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ Přehled › vulcan                                       [⟳ 4s]      │
│            │ ─────────────────────────────────────────────────────────────────  │
│            │ vulcan   ● běží · 9 EPICů · 1 aktivní · compliance 94 % · 2 plány  │
│            │ [ Brief ][ EPICy ][ Plány ][ Audit ][ Zdraví ]                     │
│            │                              ═════                                  │
│            │ ┌─ AUDIT PROJEKTU (AuditSummaryCard + AuditTrendChart) ────────┐    │
│            │ │  Skóre projektu   87/100   ◀ medián posl. auditů EPIC/plánů  │    │
│            │ │  ze 6 auditovaných EPIC · 3 bez auditu (mezery)              │    │
│            │ │  ──────────────────────────────────────────────────────────│    │
│            │ │  Trend přes EPICy:  89 ▁ 95 ▅ 84 ▂ 88 ▃ 91 ▄ 87 ▃           │    │
│            │ │   E-041 E-042 E-043 E-044 E-045 E-046  (recharts LineChart) │    │
│            │ │   (E-040 bez auditu  -  čára se přeruší, neinterpoluje)        │    │
│            │ │  Δ −2 od prvního auditovaného EPICu                          │    │
│            │ │  ──────────────────────────────────────────────────────────│    │
│            │ │  Proč (aggregateAudit.headlineCs, agreg., deterministicky): │    │
│            │ │   „Napříč projektem medián 87. Nejníž E-043 (84)  -  strženo   │    │
│            │ │    za dokumentaci; nejlíp E-042 (95). Žádný blokující        │    │
│            │ │    nález napříč auditovanými EPICy."                          │    │
│            │ │  ──────────────────────────────────────────────────────────│    │
│            │ │  Hlavní problémy projektu (top issues  -  agreg. topRisks):    │    │
│            │ │   ⚠ High · E-043 · dokumentace · „chybí CHANGELOG"      →     │    │
│            │ │   ⚠ High · E-044 · scanner.ts · „chybí cap na čtení"    →     │    │
│            │ │  Blokující napříč projektem: ✓ žádný                         │    │
│            │ │  Nálezy souhrnně: ✕0 krit · ⚠2 vys · 9 stř · 7 níz          │    │
│            │ │  [ rozpad po EPICech ▾ ]            [ technické detaily ▾ ]   │    │
│            │ └──────────────────────────────────────────────────────────────┘   │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
**Audit-tab field map (MF7, `aggregateAudit`, §13.5.7):** the tab reuses the shared `AuditSummaryCard` (rendering the project-scope `aggregateAudit`, an `AuditSummary`) + `AuditTrendChart` (project-scope `AuditTrend`, one point per EPIC's latest audited run) — **no new component**. `overallScore` = the **median-EPIC's real score** across the project's audited EPICs (`aggregateAudit.overallScore`, never a synthesized mean — §13.5.7), with the `medianEpicId` "z EPICu E-xxx" provenance chip + a "ze N auditovaných · M bez auditu" note; `aggregateAudit.headlineCs`/`topReasons`/`topRisks` are that median EPIC's own deterministic fields (never an LLM narrative), with a deep-link to it; `blockingFindings` is the median-EPIC's (null-aware — "nezjištěno" when unparseable, never "false"). **Honesty (flag-never-fake):** `scoredEpicCount===0` → `aggregateAudit.overallScore:null` and the tab shows "V tomhle projektu zatím není auditovaný EPIC se skóre" (verified on sousto-na-miru — 0 audit-report.md); `===1` → an "agregát z jediného auditu (n=1)" note (never 0 % or a fabricated median). "rozpad po EPICech" lists each contributing EPIC's `AuditSummary`; "technické detaily" opens the median EPIC's raw `audit-report.md` via `/file`.

**MOBILE (tab strip horiz-scroll; default tab = Brief, shown in its own section; here tab = EPICy and tab = Audit)**
```
┌─────────────────────────────┐    ┌─────────────────────────────┐
│ ‹ vulcan             [⟳]    │    │ ‹ vulcan             [⟳]    │
│ ● běží · 9 EPICů · 94%      │    │ ● běží · 9 EPICů · 94%      │
├─────────────────────────────┤    ├─────────────────────────────┤
│ Brief EPICy Plány Audit »   │    │ Brief EPICy Plány Audit »   │
│       ═════                 │    │                   ═════     │
├─────────────────────────────┤    ├─────────────────────────────┤
│  (tab = EPICy)              │    │  (tab = Audit · agregát)    │
│ [vše][běží][čeká][hotovo] » │    │ AUDIT PROJEKTU   87/100     │
│ ┌─────────────────────────┐ │    │ medián · ze 6 EPIC · 3 bez  │
│ │ ● E-044-2_6     běží  →  │ │    │ Trend ▁▅▂▃▄▃ (sparkline)    │
│ │   EXECUTE 7/9      12m   │ │    │ Δ −2                        │
│ ├─────────────────────────┤ │    │ ─────────────────────────── │
│ │ ◐ E-044-1_6  čeká na PM →│ │    │ Proč: medián 87, nejníž     │
│ │   GATES            2d    │ │    │ E-043 (84) za dokumentaci.  │
│ ├─────────────────────────┤ │    │ Blokující: žádný ✓          │
│ │ ✕ E-042-1_2  selhalo  → │ │    │ Problémy (2):               │
│ └─────────────────────────┘ │    │ ⚠ E-043 chybí CHANGELOG  →  │
│ ▸ Zdraví projektu (tab »)   │    │ ⚠ E-044 scanner cap      →  │
│   (compliance + retry rail) │    │ ✕0 ⚠2 stř9 níz7             │
│                             │    │ [rozpad ▾] [detaily ▾]      │
├─────────────────────────────┤    ├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│    │ Co řešit Přehled Dění ⚠ Více│
└─────────────────────────────┘    └─────────────────────────────┘
```
Mobile: the tab strip is a horizontal-scroll `Tabs` (`Brief · EPICy · Plány · Audit · Zdraví`, "Zdraví" past »). EPICy = the Rev 2 list with horiz-scroll filter chips + a "Zdraví projektu" link to the Zdraví tab. The **Audit** tab is the shared `AuditSummaryCard` + `AuditTrendChart` mobile variant fed the project `aggregateAudit` (§13.5.7): score number with the `medianEpicId` chip, sparkline (dots tappable → EPIC Audit), the median EPIC's "proč", null-aware blocking line, top issues, severity tally, the two drawers. Brief / Plány / Zdraví tabs are the layouts defined in their own sections.

#### SCREEN C — EPIC (Deep View) · THE rich screen — "track everything AID provides"

Data sources: `fsm-state.yaml`, per-run `timeline.jsonl`, `compliance.json`, `gates_report.json`, `verifier-output-*.md`, `plan.json`.

**DESKTOP**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ Přehled › vulcan › E-044-2_6                          [⟳ 2s] [▦]  │
│            │ ─────────────────────────────────────────────────────────────────  │
│            │ ┌─ HLAVIČKA ───────────────────────────────────────────────────┐  │
│            │ │ E-044-2_6 · R-E044-2     ● běží                               │  │
│            │ │ EXECUTE · krok 7/9 · auto · branch task/E-044-2_6/main        │  │
│            │ │ ███████████████░░░░  78 %        spuštěno před 12 min          │  │
│            │ │ ⓘ „Pracuje na kroku 7 z 9. Píše kód a sám si ho kontroluje."  │  │  ← human line
│            │ └───────────────────────────────────────────────────────────────┘  │
│            │                                                                      │
│            │ ┌─ FSM TIMELINE ─────────────────────────────┐ ┌─ CO SE DĚJE ─────┐ │
│            │ │ READY ─●─ EXECUTE ══▶ GATES ── DONE         │ │ (narrator panel) │ │
│            │ │   ✓        ● (teď)     ○        ○           │ │ 14:22 CP2 k.7 ✓  │ │
│            │ │           ESCALATION ○   ERROR ○            │ │ → „Kontrola      │ │
│            │ │ ⓘ „Stavový automat: teď je ve fázi EXECUTE  │ │  kroku 7 prošla, │ │
│            │ │   = vykonává plán. GATES = závěrečné        │ │  jde se dál."    │ │
│            │ │   kontroly, DONE = hotovo."                 │ │ 14:18 step_done 6│ │
│            │ └─────────────────────────────────────────────┘ │ → „Krok 6 hotov" │ │
│            │                                                  │ 14:10 cp2 retry  │ │
│            │ ┌─ CHECKPOINTY CP1–CP6 ──────────────────────┐  │ → „Kontrolu k.5  │ │
│            │ │ CP1 ✓  CP2 ✓  CP3 ✓  CP4 ○  CP5 ○  CP6 ○   │  │  opakováno (1×)" │ │
│            │ │  plán  krok  integr cura- audit zpráva     │  │       ⋮          │ │
│            │ │  ●     ●●●●● ●●    tor  it                  │  │ (auto-scroll,    │ │
│            │ │  ⓘ klepni na checkpoint → detail + verdikt │  │  newest on top)  │ │
│            │ └─────────────────────────────────────────────┘ └──────────────────┘ │
│            │                                                                      │
│            │ ┌─ ROLE AGENTŮ (panely) ───────────────────────────────────────┐   │
│            │ │ ┌Auditor──────┐ ┌Curator──────┐ ┌Reporter────┐ ┌Simplifier──┐│   │
│            │ │ │ ○ nespuštěn │ │ ○ nespuštěn │ │ ○ nespuštěn│ │ ✓ doporučil││   │
│            │ │ │ kontrola DoD│ │ slučuje     │ │ delivery   │ │ 2 zjednodu-││   │
│            │ │ │ na konci    │ │ nálezy → fix│ │ report     │ │ šení       ││   │
│            │ │ │ ⓘ „Závěrečný│ │ ⓘ „Hlídač   │ │ ⓘ „Sepíše  │ │ ⓘ „Navrhuje││   │
│            │ │ │  audit…"    │ │  kvality…"  │ │  co vzniklo"│ │  zjedno…"  ││   │
│            │ │ └─────────────┘ └─────────────┘ └────────────┘ └────────────┘│   │
│            │ └───────────────────────────────────────────────────────────────┘   │
│            │                                                                      │
│            │ ┌─ ČASY & RETRY ───────────────┐ ┌─ GATES & COMPLIANCE ──────────┐ │
│            │ │ Krok 1  ▇▇      4m   ✓        │ │ typecheck ✓  build ✓  lint ✓  │ │
│            │ │ Krok 2  ▇▇▇▇    9m   ✓        │ │ ── compliance.json ──         │ │
│            │ │ Krok 5  ▇▇▇▇▇▇  14m  ⟲1 ✓     │ │ verifier_provenance  ✓ block. │ │
│            │ │ Krok 7  ▇▇▇     7m   ● běží   │ │ plan_ac_match        ✓ block. │ │
│            │ │ CP3     ⟲4 (hot-spot ⚠)       │ │ branch_correct       ✕ advis. │ │
│            │ │ ⓘ „Krok 5 se kontroloval 2×; │ │ ⓘ „1 porušení, ale jen        │ │
│            │ │  CP3 se opakoval 4× — pozor." │ │  poznámka (advisory)."        │ │
│            │ └───────────────────────────────┘ └───────────────────────────────┘ │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
Notes: **CheckpointStrip** maps CP1=plan, CP2=per-step (N step-dots), CP3=integration (code-review + security pair), CP4=curator-validation, CP5=auditor. **CP6 is NOT reporter** — CP6 is a Fast-Mode-only (`/aid-do`) advisory checkpoint, so on a normal `/aid-run` EPIC the strip shows **CP1-CP5** and CP6 is rendered greyed "jen Fast Mode (/aid-do)" or omitted (Q1). Reporter is a plan-boundary role shown in the separate ROLE AGENTŮ panel, not in the strip. State is derived from presence/verdict of `verifier-output-*.md` + fsm phase; click → drawer with verdict + findings (rendered from .md) + Czech one-liner. **Retry counts are per-checkpoint-sourced (§MF5/§5.2), NOT a uniform `verifier_dispatch_start` count:** CP1 from the work-root file inventory (`cp1-review/rereview/reverify`, `*-pass{N}`); CP2/CP3/CP4 from `verifier_dispatch_start` timeline events when present (count = dispatches−1) else **"?" / unknown** (their output files overwrite on retry, so a file count canNOT show retries — never render 0); gates from `gates_report.json attempts`. A known repeat → ⟲N badge; the **≥3 hot-spot flag only fires when the count is actually known** (an unknown count never trips it). **Timings** per §5. Agent panels show role + state (nespuštěn/běží/hotovo/doporučil) + a permanent Czech micro-explanation.

**MOBILE** — header band stays; everything below becomes a tab bar of sections; narrator is its own tab; dense panels become accordions.
```
┌─────────────────────────────┐
│ ‹ E-044-2_6          [⟳]    │
│ ● běží · EXECUTE 7/9 · 78%  │
│ ███████████░░░               │
│ ⓘ Pracuje na kroku 7 z 9,   │
│   kód si sám kontroluje.    │
├─────────────────────────────┤
│ FSM·CP·Role·Audit·Časy·Dění»│ ← scrollable section tabs (Rev 3: + Audit)
├─────────────────────────────┤
│  (tab = CP)                 │
│ CP1 ✓ Plán                  │
│ CP2 ✓ Kroky        ●●●●●     │
│ CP3 ✓ Integrace             │
│ CP4 ○ Curator               │
│ CP5 ○ Auditor               │
│ CP6 — jen Fast Mode (/aid-do)│  ← Q1: NE reporter; na /aid-run EPICu šedé/skryté
│ ▸ klepni na řádek = verdikt │  ← row opens bottom sheet w/ .md + Czech
├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│
└─────────────────────────────┘
```
Each section tab is one vertically-scrolled list of accordion cards. "FSM" = vertical stepper (READY↓EXECUTE↓GATES↓DONE, current expanded + Czech). "Role" = 4 stacked agent cards. "Audit" = the `AuditSummaryCard` mobile variant over `RunDetail.audit` (per-run; score/blocking/headline/findings, "auditor zatím neběžel" when absent — §13.5.5). "Časy" = step list with duration bars + retry badges. "Dění" = narrator feed full-screen.

#### SCREEN D — Dění (Activity Stream) · live merged cross-project timeline

**DESKTOP**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ Dění  · živě                          [⏸ pauza] [filtr ▾] [⟳ 2s]  │
│            │ ─────────────────────────────────────────────────────────────────  │
│            │ ┌filtry──┐ ┌─ STREAM (newest top) ──────────────────────────────┐  │
│            │ │ projekt│ │ 14:22 ● vulcan  E-044  CP2 krok 7 prošlo            │  │
│            │ │ ☑ vše  │ │        → „Kontrola kroku 7 dopadla dobře, jede dál."│  │
│            │ │ druh   │ │ 14:21 ◐ wan     E-035  escalation                   │  │
│            │ │ ☑ FSM  │ │        → „Pipeline narazila na problém, čeká na     │  │
│            │ │ ☑ CP   │ │          rozhodnutí PM (člověka)."                  │  │
│            │ │ ☑ gate │ │ 14:18 ● vulcan  E-044  step_done 6 „SQLAlchemy m."  │  │
│            │ │ ☑ audit│ │        → „Krok 6 (SQLAlchemy modely) je hotový."   │  │
│            │ │ závaž. │ │ 14:10 ⟲ vulcan  E-044  verifier_dispatch (cp2 k.5)  │  │
│            │ │ ⚠ jen  │ │        → „Kontrola kroku 5 se spustila podruhé."   │  │
│            │ │  důlež.│ │       ⋮                                            │  │
│            │ └────────┘ └─────────────────────────────────────────────────────┘  │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
Each row: time, project dot, EPIC id, raw event chip, then an indented Czech translation line. Pause freezes auto-scroll. Filter by project / event-kind / severity. Click row → jumps to that EPIC's Screen C narrator at that timestamp.

**MOBILE**
```
┌─────────────────────────────┐
│ Dění živě      [⏸][filtr ▾] │
├─────────────────────────────┤
│ 14:22 ● vulcan · E-044      │
│ CP2 krok 7 prošlo           │
│ → Kontrola kroku 7 OK,      │
│   jede se dál.              │
│ ───────────────────────────│
│ 14:21 ◐ wan · E-035         │
│ eskalace                    │
│ → Problém, čeká na PM.      │
│ ───────────────────────────│
│ 14:18 ● vulcan · E-044      │
│ krok 6 hotov (SQLAlchemy)   │
│       ⋮                     │
├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│
└─────────────────────────────┘
```

#### SCREEN E — Compliance · cross-project violations & force-overrides

**DESKTOP**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ Compliance · napříč projekty                          [⟳ 4s]      │
│            │ ─────────────────────────────────────────────────────────────────  │
│            │ Skóre ekosystému 91 %   ·   3 blokující ✕   ·   5 poznámek ⚠        │
│            │                                                                      │
│            │ ┌─ MATICE (check × projekt) ───────────────────────────────────┐   │
│            │ │ check                   vulc  wan  acta  krok  sous  aid       │   │
│            │ │ verifier_provenance(B)  ✓    ✓    ✓     ✓     —     ✓         │   │
│            │ │ plan_ac_match     (B)   ✓    ✕    ✓     ✓     —     ✓         │   │
│            │ │ gates_generated_by(B)   ✓    ✓    ✓     ✓     —     ✓         │   │
│            │ │ branch_correct    (a)   ✓    ⚠    ✓     ✓     —     ⚠         │   │
│            │ │  (B)=blokující  (a)=advisory  —=nečinné                       │   │
│            │ └───────────────────────────────────────────────────────────────┘   │
│            │ ┌─ AKTIVNÍ PORUŠENÍ ───────────────────────────────────────────┐   │
│            │ │ ✕ wan E-035 · plan_ac_match · BLOKUJÍCÍ                       │   │
│            │ │   → „Hotový kód neodpovídá plánu — release je zablokovaný."   │   │
│            │ │ ⚠ aid E-046 · branch_correct · poznámka (force-override 5/13) │   │
│            │ │   → „Špatná větev, ale PM to vědomě přepsal (advisory)."      │   │
│            │ └───────────────────────────────────────────────────────────────┘   │
└────────────┴──────────────────────────────────────────────────────────────────┘
```

**MOBILE** — the matrix becomes per-project compliance cards (not a wide grid). Toggle "jen porušení" hides green. A "podle checku" segmented view lets you pick one check and see all projects.
```
┌─────────────────────────────┐
│ Compliance      [jen ⚠][⟳] │
│ Ekosystém 91% · 3✕ · 5⚠    │
├─────────────────────────────┤
│ [podle projektu][podle checku]│
├─────────────────────────────┤
│ ┌─ wan ────────────── 78% ─┐│
│ │ ✕ plan_ac_match  BLOK.    ││
│ │  → kód ≠ plán, blokuje    ││
│ │ ⚠ branch_correct poznámka ││
│ └───────────────────────────┘│
│ ┌─ vulcan ──────────── 94% ┐│
│ │ vše ✓                     ││
│ └───────────────────────────┘│
├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│
└─────────────────────────────┘
```

#### SCREEN F — Nápověda (Help) · modeled on ACTA's `/napoveda`

Same architecture as ACTA's `Help.tsx`: hero with embedded search, sticky TOC sidebar with IntersectionObserver scrollspy, metadata-driven `SECTIONS` array, content authored from `<Section>/<Step>/<Demo>/<Kbd>` building blocks, conversational plain-Czech second person. `<Demo>` blocks render the dashboard's REAL components (`CheckpointStrip`, `FsmTimeline`, `StatusBadge`, `MetricBadge`) so "v aplikaci to vypadá takhle" shows the actual UI; Help renders from the same `DictionaryEntry` set (§7.5, via `/api/explanations`) — `term`/`keywords`/long-form — that powers the live UI, so terms match everywhere.

**DESKTOP**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ ┌─ HERO (tmavý gradient) ─────────────────────────────────────┐    │
│            │ │  ✨ Nápověda                                                 │    │
│            │ │  Jak AID funguje                                             │    │
│            │ │  AID je dirigent, který sám vyvíjí software. Tady ti krok    │    │
│            │ │  za krokem ukážu, co dělá a jak to v appce poznáš.           │    │
│            │ │  [🔍 Hledat v nápovědě… ]                                    │    │
│            │ └──────────────────────────────────────────────────────────────┘    │
│            │ ┌Obsah────┐ ┌─ obsah (scroll) ──────────────────────────────────┐   │
│            │ │ Co je   │ │ 01 ● Co je AID a k čemu je                         │   │
│            │ │ FSM     │ │    „Představ si dirigenta…"                        │   │
│            │ │ ▸CP1    │ │ 02 ● Životní cyklus & stavový automat (FSM)        │   │
│            │ │ ▸CP2    │ │    <Demo> READY→EXECUTE→GATES→DONE (FsmTimeline)   │   │
│            │ │ ▸CP3    │ │ 03 ● Checkpointy CP1–CP6                           │   │
│            │ │ ▸CP4    │ │    <Demo> <CheckpointStrip/> živá ukázka           │   │
│            │ │ ▸CP5    │ │ 04 ● Auditor / Curator / Reporter / Simplifier     │   │
│            │ │ Role    │ │ 05 ● Quality gates                                 │   │
│            │ │ Gates   │ │ 06 ● Compliance & force-override                   │   │
│            │ │ Compl.  │ │ 07 ● Jak číst tenhle dashboard                     │   │
│            │ │ Dashbrd │ │    <Demo> <ProjectTile/> + popisky                 │   │
│            │ └─────────┘ └────────────────────────────────────────────────────┘   │
└────────────┴──────────────────────────────────────────────────────────────────┘
```

**MOBILE** — TOC collapses into a sticky "Obsah ▾" dropdown under the search; sections single-column; `<Demo>` components reflow to mobile layouts.
```
┌─────────────────────────────┐
│ ✨ Nápověda                 │
│ Jak AID funguje             │
│ [🔍 Hledat…              ]  │
│ [ Obsah ▾ ]                 │  ← TOC dropdown (was sidebar)
├─────────────────────────────┤
│ 01 ● Co je AID              │
│ Představ si dirigenta…      │
│                             │
│ 02 ● Stavový automat (FSM)  │
│ ┌ V appce to vypadá takhle ┐│
│ │ READY→EXECUTE→GATES→DONE  ││  ← FsmTimeline, mobile variant
│ └───────────────────────────┘│
│ 03 ● Checkpointy CP1–CP6    │
│       ⋮                     │
├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│
└─────────────────────────────┘
```

**Help `SECTIONS` array:**
```ts
const SECTIONS = [
  { id: 'co-je-aid',     title: 'Co je AID',                 keywords: 'co je aid orchestrátor dirigent agenti automatizace vývoj přehled úvod' },
  { id: 'fsm',           title: 'Životní cyklus a stavy (FSM)', keywords: 'fsm stavový automat ready execute gates escalation done error stav pipeline životní cyklus běh' },
  { id: 'cp1',           title: 'CP1 — Kontrola plánu',       keywords: 'cp1 checkpoint plán review adjudikátor riziko light deep kontrola zadání' },
  { id: 'cp2',           title: 'CP2 — Kontrola kroků',       keywords: 'cp2 checkpoint krok step verifier per-step kontrola implementace fix loop retry' },
  { id: 'cp3',           title: 'CP3 — Integrační kontrola',  keywords: 'cp3 integrace code-review security bezpečnost verifier před gates' },
  { id: 'cp4',           title: 'CP4 — Validace Curatorem',   keywords: 'cp4 curator validace nálezy findings sloučení fix' },
  { id: 'cp5',           title: 'CP5 — Audit (DoD)',          keywords: 'cp5 auditor audit definition of done dod hotovo závěrečná kontrola' },
  { id: 'cp6',           title: 'CP6 — Kontrola v rychlém režimu (/aid-do)', keywords: 'cp6 fast mode aid-do rychlý režim code-review poradní checkpoint po implementaci' },
  { id: 'role',          title: 'Role agentů',                keywords: 'auditor curator reporter simplifier implementer verifier gate-fixer role agent kdo co dělá' },
  { id: 'gates',         title: 'Quality gates',              keywords: 'gates typecheck build lint test brány kvalita prošlo selhalo gates_report' },
  { id: 'compliance',    title: 'Compliance a force-override', keywords: 'compliance porušení blokující advisory severity force override přepsání pm provenance plan_ac_match' },
  { id: 'timings-retry', title: 'Časy a opakování',           keywords: 'čas timing doba běhu retry opakování hot-spot kolikrát kontrola' },
  { id: 'cti-dashboard', title: 'Jak číst tenhle dashboard',  keywords: 'dashboard dlaždice tile přehled barvy stav legenda navigace jak číst' },
];
```
Sections 02, 03, 07 use `<Demo>` to render live `FsmTimeline`, `CheckpointStrip`, `ProjectTile`. `<Section>/<Step>/<Demo>/<Kbd>` are lifted verbatim from ACTA (color palette swaps blue→cyan/violet).

> **Help Rev 3 addition:** add three managerial sections to the `SECTIONS` array — `{ id:'co-resit', title:'Co potřebuju vědět (brief)', keywords:'brief co řešit rozhodnutí blokuje pozor riziko přehled manažer' }`, `{ id:'plan', title:'Plán a jeho fáze', keywords:'plán plan fáze epicy ac pokrytí audit trend backlog lekce' }`, `{ id:'riziko', title:'Riziko a odhad úspěchu', keywords:'riziko level nízké střední vysoké pravděpodobnost úspěch agent mvp2 deterministické' }`. Section "riziko" explicitly explains, in plain Czech, that the level is computed from real counts and the probability number "přijde s agentem (MVP2)" — so the manager understands why the slot is empty (D2). These render from the same `DictionaryEntry` set as the live UI.

#### SCREEN G — Co potřebuju vědět (Managerial Brief, infra scope) · the front door (`/`)

The cross-infra brief is the **landing screen**. It renders one `Brief` (scope `infra`, from `GET /api/brief?since=`, §13.4). Every block below maps 1:1 to a `Brief` field; every line in a block is one `BriefItem` rendered via `BriefPanel` → `ExplanationLine` (the `BriefItem.explanation`, already Czech via §6.4), with its `severity` dot and a deep-link (`BriefItem.href`) to its EPIC / plan / project. **Cross-infra prioritization (most urgent first), top to bottom:** (1) **Rozhodnutí** (decisionsNeeded — a human is the blocker), (2) **Co blokuje** (blockers), (3) **Riziko ekosystému** (RiskBadge + reasons), (4) **Na co pozor** (watchOuts), (5) **Co se změnilo** (sinceLastSeen), (6) **Co bude dál** (nextUp), (7) the embedded **Přehled projektů** tiles (Screen A as a section). Within every block, `BriefItem`s sort `severity` blocking → warn → info, then by `at` desc. The probability slot lives in the risk block, always rendering the MVP2 placeholder (D2).

`lastSeen` is read from **localStorage** (MVP1, D-locked) and sent as `?since=`; the "Co se změnilo" block and a "N nových" pill on each other block's header derive from `Brief.sinceLastSeen.counts`. A "Označit jako přečtené" button writes `now()` to localStorage and clears the counts.

**DESKTOP**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ [≡] AID    │  Co potřebuju vědět                  [⟳ 4s] [⬇ Instalovat] [hledat]│
│            │  ────────────────────────────────────────────────────────────────  │
│ ▸ Co řešit │  napříč 6 projekty · naposledy ses díval 18.6. 21:40                │
│   Přehled  │  ┌──────────────────────────────────────┐  [✓ Označit přečtené]    │
│   Dění     │  │ 2 rozhodnutí · 3 blokující · 5 pozor   │  ← shrnutí jednou větou │
│   Compliance│ └──────────────────────────────────────┘                          │
│   Nápověda │                                                                      │
│ ───────    │  ┌─ ROZHODNUTÍ (čeká na tebe) ──────────────────────── 2 ──────────┐ │
│ [project ▾]│  │ ⚠ wan · E-035 · čeká na rozhodnutí PM                          →│ │
│            │  │   „Auditor našel kritický nález  -  merge je zablokovaný, dokud   │ │
│            │  │    to neposoudíš."                              před 2 h         │ │
│            │  │ ⚠ vulcan · E-044-1_6 · hotovo, čeká na souhlas k merge         →│ │
│            │  │   „Kroky i brány prošly. Čeká na tvoje „mergni to"."  před 1 d  │ │
│            │  └──────────────────────────────────────────────────────────────┘ │
│            │  ┌─ CO BLOKUJE POSTUP ─────────────────────────────── 3 ──────────┐ │
│            │  │ ✕ wan · E-035 · plan_ac_match · BLOKUJÍCÍ                      →│ │
│            │  │   „Hotový kód neodpovídá plánu  -  release je zablokovaný."       │ │
│            │  │ ▣ krok · E-013-2_4 · zaseklý přechod (3× po sobě)             →│ │
│            │  │   „Stejná kontrola selhává opakovaně  -  systémový problém."      │ │
│            │  │ ▣ acta · E-007 · běh stojí 6 d beze změny                      →│ │
│            │  └──────────────────────────────────────────────────────────────┘ │
│            │  ┌─ RIZIKO EKOSYSTÉMU ──────────────────────────────────────────┐ │
│            │  │  [ STŘEDNÍ ]   ← RiskBadge (deterministické, §13.2)            │ │
│            │  │  Proč:                                                         │ │
│            │  │   ✕ 1 blokující porušení (wan plan_ac_match)                   │ │
│            │  │   ⚠ 5 force-override za 13 běhů (aid-orchestrator)             │ │
│            │  │   ⚠ CP3 se opakoval 4× (vulcan E-044)  -  hot-spot               │ │
│            │  │  ─────────────────────────────────────────────────────────    │ │
│            │  │  Odhad pravděpodobnosti úspěchu:                               │ │
│            │  │  ⓘ „přesnější odhad přijde s agentem (MVP2)"  ← šedé, neaktivní│ │
│            │  └──────────────────────────────────────────────────────────────┘ │
│            │  ┌─ NA CO SI DÁT POZOR ─────────────────────────────── 5 ─────────┐ │
│            │  │ ⚠ aid-orch · E-046 · branch_correct · poznámka (override 5×)   →│ │
│            │  │   „Špatná větev, ale vědomě přepsáno (advisory)."               │ │
│            │  │ ⚠ vulcan · E-044 · CP3 retry hot-spot (4×)                     →│ │
│            │  │       ⋮  (rozbalit zbytek)                                      │ │
│            │  └──────────────────────────────────────────────────────────────┘ │
│            │  ┌─ CO SE ZMĚNILO OD MINULE ───── 4 nové běhy · 1 selhání ────────┐ │
│            │  │ ● vulcan · E-044 přešlo READY→EXECUTE                          →│ │
│            │  │ ✕ vulcan · nová selhaná brána (lint)                           →│ │
│            │  │ + acta · 2 nové návrhy v backlogu                             →│ │
│            │  └──────────────────────────────────────────────────────────────┘ │
│            │  ┌─ CO BUDE DÁL ────────────────────────────────────────────────┐ │
│            │  │ ▸ wan · fronta: E-036 (až doběhne E-035)                       →│ │
│            │  │ ▸ vulcan · E-044 krok 7/9 rozpracováno                         →│ │
│            │  └──────────────────────────────────────────────────────────────┘ │
│            │  ┌─ PŘEHLED PROJEKTŮ (Screen A jako sekce) ──────────────────────┐ │
│            │  │ [ProjectTile × 6  -  identické dlaždice jako /prehled]   [vše →] │ │
│            │  └──────────────────────────────────────────────────────────────┘ │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
Block-to-field map: ROZHODNUTÍ=`decisionsNeeded` · CO BLOKUJE=`blockers` · RIZIKO=`risk` (RiskBadge=`risk.level`, "Proč"=`risk.reasons[]`, probability=`successProbability.value` always `null` in MVP1→placeholder) · NA CO POZOR=`watchOuts` · CO SE ZMĚNILO=`sinceLastSeen.items` + header counts=`sinceLastSeen.counts` · CO BUDE DÁL=`nextUp` · PŘEHLED PROJEKTŮ=`/api/projects` tiles. Empty blocks collapse to a single calm line ("Nic nečeká na rozhodnutí ✓") rather than disappearing, so the manager learns the block exists. If `risk.level==='neurceno'` the badge reads "neurčeno" and the "Proč" list shows "málo dat" (§13.2 coverage rule).

**MOBILE (~375px)** — same priority order, single column, each block a collapsible card; the summary line + RiskBadge stay pinned near the top. "Co řešit" is the default tab on launch.
```
┌─────────────────────────────┐
│ AID · Co potřebuju vědět [⟳]│  ← sticky header
│ 2 rozhodnutí · 3✕ · 5⚠      │
│ [ Riziko: STŘEDNÍ ]  [✓přeč]│  ← RiskBadge pinned
├─────────────────────────────┤
│ ▾ ROZHODNUTÍ            2    │  ← card, expanded by default
│ ⚠ wan E-035 čeká na PM    → │
│   Auditor našel blokující   │
│   nález, posuď to.  před 2h │
│ ⚠ vulcan E-044-1_6 → merge? │
│   Prošlo, čeká na souhlas.  │
├─────────────────────────────┤
│ ▾ CO BLOKUJE            3   │
│ ✕ wan E-035 plan_ac_match → │
│   Kód ≠ plán, blokuje.      │
│ ▣ krok E-013 zaseklý 3×   → │
├─────────────────────────────┤
│ ▸ NA CO POZOR           5   │  ← collapsed
├─────────────────────────────┤
│ ▸ CO SE ZMĚNILO   4 nové    │  ← collapsed
├─────────────────────────────┤
│ ▸ CO BUDE DÁL               │
├─────────────────────────────┤
│ ▸ Přehled projektů (6)      │
│            ⋮ (scroll)        │
├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│  ← bottom tab bar (Rev 3)
└─────────────────────────────┘
```

#### SCREEN Plan — Plán (Plan Detail) · first-class plan entity (`/p/:project/plans/:planId`)

Renders one `PlanDetail` (`GET /api/plans/:projectId/:planId`) + a plan-scope `Brief` (`GET /api/brief/:projectId/:planId`). **Tabs (Rev 4):** `Brief · Fáze · EPICy · Audit · Dodávka & zjednodušení · AC · Backlog · Lekce`. **Tab 1 (default) = Brief** — the *same* `BriefPanel` component as Screen G, just plan-scoped (D1). The other tabs are the plan's managerial detail; **"Dodávka & zjednodušení" (Rev 4, MF6)** is the new tab carrying the plan-boundary Reporter delivery report + the Simplifier proposals.

> **Tab-count note (MF6, recommended clean set).** Rev 4 adds **one** tab, "Dodávka & zjednodušení", and keeps the auditor on its own "Audit" tab (Audit is a different role than Reporter/Simplifier, so it is not merged in). That is **8 tabs** on desktop — readable on a desktop tab strip, but at the mobile ceiling. To keep the set clean: **on mobile the tab strip is a horizontal-scroll `Tabs`** (the same pattern Rev 3 already uses for `Backlog`/`Lekce` past »); the **primary five** stay left-anchored — `Brief · Fáze · EPICy · Audit · Dodávka` — with `AC · Backlog · Lekce` reachable past ». No tab is dropped or merged: the Reporter/Simplifier outputs are first-class (the PM's explicit ask).

**DESKTOP**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ Přehled › vulcan › Plán P003                          [⟳ 4s]      │
│            │ ─────────────────────────────────────────────────────────────────  │
│            │ P003 · „Memory-driven planning"   ● běží · 5 EPICů · 3 hotové · 60%│
│            │ ███████████░░░░░░░  3/5 EPICů  ·  AC 82 %  ·  poslední změna 12 min │
│            │ [ Brief ][ Fáze ][ EPICy ][ Audit ][ Dodávka&zj. ][ AC ][ Backlog ]│
│            │ ════════                                          [ Lekce ]         │
│            │ ┌─ BRIEF (plan scope  -  stejný BriefPanel jako Screen G) ─────────┐ │
│            │ │  Riziko plánu:  [ NÍZKÉ ]                                       │ │
│            │ │  ┌ Rozhodnutí ──┐ Nic nečeká ✓                                  │ │
│            │ │  ┌ Co blokuje ──┐ Nic neblokuje ✓                              │ │
│            │ │  ┌ Na co pozor ─┐ ⚠ E-044 CP3 retry hot-spot (4×)            →│ │
│            │ │  ┌ Co se změnilo┐ ● E-044 přešlo READY→EXECUTE              →│ │
│            │ │  ┌ Co bude dál ─┐ ▸ E-045 ve frontě (až doběhne E-044)      →│ │
│            │ │  Odhad úspěchu: „přesnější odhad přijde s agentem (MVP2)" ⓘ    │ │
│            │ └──────────────────────────────────────────────────────────────┘ │
│            │  (tab = Fáze)                                                       │
│            │ ┌─ FÁZE PLÁNU (PlanPhaseTimeline) ───────────────────────────────┐ │
│            │ │ E-042 ✓ ──── E-043 ✓ ──── E-044 ● běží ── E-045 ○ ── E-046 ○  │ │
│            │ │ hotovo      hotovo       EXECUTE 7/9    čeká     čeká          │ │
│            │ │ ⓘ „Plán má 5 EPIC v řadě. Tři jsou hotové, na čtvrté se teď    │ │
│            │ │    pracuje, dvě čekají ve frontě."                              │ │
│            │ └──────────────────────────────────────────────────────────────┘ │
│            │  (tab = Audit)                                                      │
│            │ ┌─ AUDIT PLÁNU (AuditSummaryCard + AuditTrendChart) ─────────────┐ │
│            │ │  Audit na konci plánu (boundaryAudit, E-046): 84/100           │ │
│            │ │  Skóre napříč plánem (aggregateAudit, medián EPIC): 88/100     │ │
│            │ │  Trend přes EPICy:  89 ▁ 95 ▅ 84 ▂ 88 ▃   (recharts LineChart) │ │
│            │ │   E-042 E-043 E-044 E-046   (E-045 bez auditu  -  mezera)        │ │
│            │ │  Δ −1 od prvního auditovaného EPICu                            │ │
│            │ │  [otevři audit konkrétní EPICy →]                              │ │
│            │ └──────────────────────────────────────────────────────────────┘ │
│            │  (tab = Dodávka & zjednodušení  -  MF6: Reporter + Simplifier)      │
│            │ ┌─ DODÁVKA (ReporterDeliveryPanel) ─────────────────────────────┐ │
│            │ │  Reporter · dodávka plánu     ✓ PASS    [ celý report ▾ ]     │ │
│            │ │  ⓘ „Sepsal, co plán dodal, a doložil to testy."               │ │
│            │ │  „Dodáno 5 EPIC, všechny brány zelené; migrace DB i UI hotové."│ │
│            │ │  ─────────────────────────────────────────────────────────── │ │
│            │ │  Doklady (testy, _test_evidence  -  musí být na disku):         │ │
│            │ │   ✓ e2e-report.html         · evidence/E-044/R…/reporter/   → │ │
│            │ │   ✓ coverage-summary.txt    · evidence/E-044/R…/reporter/   → │ │
│            │ │   ⚠ perf-bench.json  -  chybí na disku (flag, nezamlčeno)      → │ │
│            │ │  reporter@aid-orchestrator · 18.6. 14:31                       │ │
│            │ └──────────────────────────────────────────────────────────────┘ │
│            │ ┌─ ZJEDNODUŠENÍ (SimplifierPanel) ──────────────────────────────┐ │
│            │ │  Simplifier · návrhy na zjednodušení   3 návrhy               │ │
│            │ │  ⓘ „Navrhuje, co zjednodušit  -  kód nikdy nemění sám."         │ │
│            │ │  „Doporučuje 2 sloučení a 1 odstranění mrtvého kódu."         │ │
│            │ │  ─────────────────────────────────────────────────────────── │ │
│            │ │  ↟ scanner.ts · „sloučit dvě čtecí cesty do jedné"            │ │
│            │ │       doporučeno: přijmout · oprava: S                      → │ │
│            │ │  ↟ pathmap.ts · „odstranit nepoužitý helper resolveLegacy()"  │ │
│            │ │       doporučeno: přijmout · oprava: S                      → │ │
│            │ │  ↟ build-plan.ts · „zploštit trojitý ternární výraz"          │ │
│            │ │       doporučeno: odložit · oprava: M                       → │ │
│            │ │  [ celý simplifier-report ▾ ]                                 │ │
│            │ └──────────────────────────────────────────────────────────────┘ │
│            │  (tab = Backlog)  → BacklogDeltaList   (tab = Lekce) → LessonsTable │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
Tab data map: **Brief**=plan-scope `Brief` (BriefPanel) · **Fáze**=`PlanPhaseTimeline` over `PlanSummary.epicIds` in plan order (each node = an EPIC's latest-run state, links to Screen C) · **EPICy**=an `EpicSummary[]`-style list (the same row component as Screen B, filtered to this plan's members) · **Audit**=`AuditSummaryCard` ×2 — `boundaryAudit` ("audit na konci plánu", the last EPIC's run) and `aggregateAudit` ("skóre napříč plánem", median-EPIC, SF4/§13.5.7) — + `AuditTrendChart` over `PlanSummary.auditTrend` · **Dodávka & zjednodušení** (MF6)=`ReporterDeliveryPanel` over `PlanDetail.deliveryReport` + `SimplifierPanel` over `PlanDetail.simplifierSummary` (two stacked panels) · **AC**=`PlanSummary.acPct` headline + per-EPIC AC bars (null → "neměřeno / fast mode", never 0%) · **Backlog**=`BacklogDeltaList` (added/closed/priority-changed/status-changed since the localStorage `BacklogSnapshot`, computed client-side per MF2, scoped to this plan's EPICs; `firstVisit` → "bez porovnání - vše jako nové") · **Lekce**=`LessonsTable` over `PlanDetail.lessons` (the full `LessonsView`; `PlanSummary.lessonsPreview[]` is only the thin list-row shape).

**Tab "Dodávka & zjednodušení" detail (MF6):** two stacked panels. **ReporterDeliveryPanel** (`PlanDetail.deliveryReport`, `ReporterDelivery`) — `outcome` (PASS/FAIL/PARTIAL `StatusBadge`; `null`→"neuvedeno"), `summaryCs` (the one-line "co se dodalo"; `null`→omit), the `testEvidence[]` list where each row deep-links via `/file` and shows `exists` honestly (a missing-on-disk evidence file renders a `pozor` ⚠ "chybí na disku" row, never silently dropped — flag-never-fake / §4.3 anti-fabrication), `generatedBy`+`generatedAt` footer, and a "celý report ▾" drawer rendering the raw delivery `.md` (`rawRelPath` via `/file`). `deliveryReport.present===false` → "Reporter na tomhle plánu zatím neběžel" (never a fabricated outcome). **SimplifierPanel** (`PlanDetail.simplifierSummary`, `SimplifierSummary`) — `proposalCount` headline + `headlineCs`, then `proposals[]` as a list, each row = the proposal text + `disposition` chip (přijmout/odmítnout/odložit, `null`→"bez doporučení") + `effort` (S/M/L) + a deep-link to the area; a "celý simplifier-report ▾" drawer for the raw `.md`. `present===false` → "Simplifier na tomhle plánu zatím neběžel". Both panels are **read-only** in MVP1 (no apply/dismiss action — applying S/M approved simplifications is the gate-fixer's job at run time, §4.3, not the cockpit's).

**MOBILE**
```
┌─────────────────────────────┐
│ ‹ Plán P003          [⟳]    │
│ ● běží · 3/5 EPICů · AC 82% │
│ ███████████░░░░░             │
├─────────────────────────────┤
│ Brief Fáze EPICy Audit Dod.»│  ← horiz-scroll tabs (Dodávka, AC, Backlog, Lekce za »)
├─────────────────────────────┤
│  (tab = Brief)              │
│ [ Riziko plánu: NÍZKÉ ]     │
│ ▾ Rozhodnutí   nic ✓        │
│ ▾ Co blokuje   nic ✓        │
│ ▾ Na co pozor  1          → │
│   ⚠ E-044 CP3 retry 4×      │
│ ▾ Co se změnilo 1         → │
│ ▾ Co bude dál              → │
│ Odhad úspěchu: MVP2 ⓘ       │
├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│
└─────────────────────────────┘
```
Mobile "Dodávka & zjednodušení" tab (stacked panels):
```
┌─────────────────────────────┐
│ ‹ Plán P003          [⟳]    │
│ ● běží · 3/5 EPICů · AC 82% │
├─────────────────────────────┤
│ Brief Fáze EPICy Audit Dod.»│
│                        ════ │
├─────────────────────────────┤
│ DODÁVKA (Reporter)   ✓ PASS │
│ ⓘ Sepsal co plán dodal +    │
│   doložil testy.            │
│ Dodáno 5 EPIC, brány zelené.│
│ Doklady (testy):            │
│  ✓ e2e-report.html        → │
│  ✓ coverage-summary.txt   → │
│  ⚠ perf-bench.json chybí  → │
│ [ celý report ▾ ]           │
│ ─────────────────────────── │
│ ZJEDNODUŠENÍ      3 návrhy  │
│ ⓘ Navrhuje, kód nemění sám. │
│ ↟ scanner sloučit cesty     │
│   přijmout · S            → │
│ ↟ pathmap smazat helper     │
│   přijmout · S            → │
│ ↟ build-plan zploštit ternár│
│   odložit · M             → │
│ [ celý simplifier-report ▾ ]│
├─────────────────────────────┤
│ Co řešit Přehled Dění ⚠ Více│
└─────────────────────────────┘
```
Other tabs reflow: **Fáze** = vertical stepper (E-042↓…↓E-046, current expanded). **Audit** = score number + a small sparkline (`AuditTrendChart` mobile variant, dots tappable). **Dodávka & zjednodušení** = the two stacked panels above (ReporterDeliveryPanel + SimplifierPanel; drawers open as bottom sheets). **AC / Backlog / Lekce** = stacked cards.

#### Brief-as-first-tab on Screen B (Project Detail) — reflow

Screen B (Rev 2: EPIC list + "Zdraví projektu" rail) gains a **tab strip** at the top, with **Brief (project scope) as tab 1, default**: `[ Brief ][ EPICy ][ Plány ][ Audit ][ Zdraví ]`. The same `BriefPanel` renders the project-scope `Brief` (`GET /api/brief/:projectId`). The Rev 2 EPIC list moves under the "EPICy" tab and the health rail under "Zdraví" — **nothing from Rev 2 is removed, it is re-tabbed.** New "Plány" tab lists the project's `PlanSummary[]` (each row → Plan screen). **New "Audit" tab (Rev 4, MF7) = the project-scope audit panel** — *"Audit projektu: skóre %, trend, vysvětlení, hlavní problémy"*: it reuses the **same `AuditSummaryCard` + `AuditTrendChart`** as the Plan/EPIC audit panels, fed the project-scope **`aggregateAudit`** (`AuditSummary` over all the project's audited EPICs, the median-EPIC pick of §13.5.7 / SF4) and a project-scope `AuditTrend` (`GET /api/audit-trend/:projectId`, one point per audited EPIC). It is **distinct from `boundaryAudit`** (a single plan-boundary auditor run): the project tab is the cross-EPIC quality read, not one report. On desktop ≥1280px the Brief tab MAY render as a left column with EPICy beside it (two-pane), collapsing to stacked tabs below 1280px; mobile is always one tab at a time.

**DESKTOP (tab = Brief, the new default landing tab of Screen B)**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ Přehled › vulcan                                       [⟳ 4s]      │
│            │ ─────────────────────────────────────────────────────────────────  │
│            │ vulcan   ● běží · 9 EPICů · 1 aktivní · compliance 94 % · 2 plány  │
│            │ [ Brief ][ EPICy ][ Plány ][ Audit ][ Zdraví ]                     │
│            │ ════════                                                            │
│            │ ┌─ BRIEF (project scope  -  stejný BriefPanel) ────────────────────┐ │
│            │ │  Riziko projektu:  [ STŘEDNÍ ]                                  │ │
│            │ │  ┌ Rozhodnutí ──┐ ⚠ E-044-1_6 hotovo, čeká na merge          →│ │
│            │ │  ┌ Co blokuje ──┐ Nic neblokuje ✓                              │ │
│            │ │  ┌ Na co pozor ─┐ ⚠ CP3 retry hot-spot (E-044, 4×)          →│ │
│            │ │  ┌ Co se změnilo┐ ● E-044 READY→EXECUTE · ✕ nová selhaná brána│ │
│            │ │  ┌ Co bude dál ─┐ ▸ fronta: E-045                            →│ │
│            │ │  Odhad úspěchu: „přesnější odhad přijde s agentem (MVP2)" ⓘ    │ │
│            │ └──────────────────────────────────────────────────────────────┘ │
│            │  (přepnutím na „EPICy" se zobrazí Rev 2 seznam + „Zdraví" rail)    │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
**MOBILE** — Screen B header band stays; under it the tab strip `[Brief][EPICy][Plány][Audit][Zdraví]` (horiz-scroll). Brief tab = the stacked-card BriefPanel (identical to Screen G mobile, project-scoped). EPICy/Plány/Zdraví tabs are the Rev 2 mobile layouts re-homed under tabs; the **Audit** tab = the `AuditSummaryCard` mobile variant (aggregate score number + sparkline `AuditTrendChart`), project-scoped.

**DESKTOP (tab = Audit, the project-scope audit panel — Rev 4, MF7)**
```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ sidebar    │ Přehled › aid-orchestrator                             [⟳ 4s]      │
│            │ [ Brief ][ EPICy ][ Plány ][ Audit ][ Zdraví ]                     │
│            │                                  ════════                          │
│            │ ┌─ AUDIT PROJEKTU (AuditSummaryCard agreg. + AuditTrendChart) ───┐ │
│            │ │  Skóre projektu (medián auditů EPIC): 92/100   ◀ aggregateAudit │ │
│            │ │   z EPICu E-036 (medián z 5 auditovaných EPIC)                 │ │
│            │ │  Trend přes EPICy:  92 ▅ 92 ▅ 89 ▃ 95 ▇ 84 ▂  (LineChart)      │ │
│            │ │   E-036 E-042 E-046-1 E-046-2 E-046-3  (ostatní bez skóre)      │ │
│            │ │  Proč (headlineCs mediánového EPICu):                          │ │
│            │ │   „Skóre 92/100 - bez blokujících nálezů, jen drobnosti."       │ │
│            │ │  Hlavní problémy (topRisks mediánového EPICu): žádné kritické  │ │
│            │ │  ⚠ agregát z 5 auditovaných EPIC; 9 dalších EPIC bez skóre     │ │
│            │ │  [otevři audit konkrétní EPICy →]   [audit posledního plánu →] │ │
│            │ └──────────────────────────────────────────────────────────────┘ │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
The project Audit tab renders **`aggregateAudit`** (§13.5.7) via the **shared `AuditSummaryCard`** (same component as the Plan/EPIC audit panels) plus the project-scope **`AuditTrendChart`** (`GET /api/audit-trend/:projectId`, one point per audited EPIC, gaps kept). The headline number is the **median-EPIC's real `overallScore`** (never a synthesized mean) and the "proč"/topRisks are that EPIC's own deterministic fields, with a deep-link to it. Sparse/empty is honest: `scoredEpicCount===0` → "napříč projektem zatím není auditovaný EPIC se skóre" (e.g. **sousto-na-miru, 0 audit-report.md**); `===1` → a "agregát z jediného auditu (n=1)" note. This is the project-scope twin of the Plan "Audit" tab; the Plan tab additionally shows `boundaryAudit` ("audit na konci plánu"), which has no project-scope equivalent (a project is not a single plan boundary).

#### SCREEN-shared PANEL — Audit summary (AuditSummaryCard, used on Plan + EPIC detail)

Replaces "render the audit-report.md markdown" (Rev 2 behaviour where the auditor showed up only as a `ReportRef` opened in the raw drawer). Renders one `AuditSummary` (§13.5, from `RunDetail.audit` on Screen C and the aggregate on the Plan Audit tab). **Structured, not raw markdown** — the raw markdown stays one click away in a "technické detaily" drawer (`audit.rawRelPath` via `/file`). Every number is nullable: `present:false`→"auditor zatím neběžel"; `overallScore:null`→"—" with `warnings` shown; `blockingFindings:null`→"nezjištěno" (the single canonical label, never "false" - matches §13.5.6 / AC #17).

**DESKTOP (as a card on Screen C, or the aggregate on the Plan Audit tab)**
```
┌─ AUDIT (AuditSummaryCard) ──────────────────────────────────────────────────┐
│  Skóre  84/100   ◀ z frontmatteru (scoreSource)        [technické detaily ▾] │
│  ┌ Bezpečnost 92 ▇▇▇▇▇ │ Kód 88 ▇▇▇▇ │ Dokumentace 78 ▇▇▇ │ Proces 80 ▇▇▇ ┐│
│  │  (AuditCategoryScore[], normalizováno na /100; rawScore v tooltipu)       ││
│  └──────────────────────────────────────────────────────────────────────────┘│
│  Blokující nález:  ✓ žádný            předtím: 89/100 (Δ −5)  ← previousScoreHint│
│  ─────────────────────────────────────────────────────────────────────────── │
│  Proč to dopadlo takhle (headlineCs, deterministicky):                        │
│   „Skóre 84. Strhlo hlavně 5 nálezů v dokumentaci (−5 každý) a 2 procesní     │
│    (−2). Bezpečnost čistá. Žádný blokující nález."                             │
│  ─────────────────────────────────────────────────────────────────────────── │
│  Hlavní rizika (topRisks  -  Critical+High):                                    │
│   ⚠ High  · scanner.ts:88 · „chybí cap na paralelní čtení" · oprava: M        │
│   ⚠ High  · pathmap.ts   · „hardcoded /opt/eco" · oprava: S · auto-fix ✓       │
│  Doporučené kroky (nextSteps  -  řazeno závažnost × levnost opravy):            │
│   1. pathmap.ts hardcoded cesta (High, S, auto-fix)  →                        │
│   2. scanner.ts paralelní čtení (High, M)            →                        │
│  Nálezy: ✕0 krit · ⚠2 vys · 4 stř · 3 níz · 1 auto-fixovatelný               │
└──────────────────────────────────────────────────────────────────────────────┘
```
Field map: `overallScore` + `scoreSource` chip · `categories[]`→horizontal score bars (`rawScore`/`max` in tooltip, normalized `/100` for the bar) · `blockingFindings`→the ✓/✕ line · `previousScoreHint`→"předtím … (Δ)" · `headlineCs`→the deterministic "proč" prose (NOT an LLM narrative — D2) · `topRisks[]`→risk list · `nextSteps[]`→ranked action list (each links to the EPIC/area) · `countsBySeverity`+`autoFixableCount`→the bottom tally · `warnings[]`→a muted "⚠ část reportu nešlo přečíst: …" line when non-empty · "technické detaily ▾"→base-ui Dialog (sheet) rendering raw `audit-report.md` from `/file`.

**MOBILE**
```
┌─────────────────────────────┐
│ AUDIT            84/100      │
│ frontmatter · předtím 89 ▼−5│
│ Bezp 92 ▇▇▇▇▇               │
│ Kód  88 ▇▇▇▇                │
│ Dok  78 ▇▇▇                 │
│ Proc 80 ▇▇▇                 │
│ Blokující nález: žádný ✓    │
│ ─────────────────────────── │
│ Proč: Skóre 84. Strhly to   │
│ nálezy v dokumentaci a 2    │
│ procesní. Bezpečnost čistá. │
│ ─────────────────────────── │
│ Hlavní rizika (2)           │
│ ⚠ scanner.ts:88 chybí cap M │
│ ⚠ pathmap hardcoded S auto✓ │
│ Kroky: 1. pathmap  2. scan  │
│ ✕0 ⚠2 stř4 níz3 · auto 1    │
│ [ technické detaily ▾ ]     │
└─────────────────────────────┘
```

#### SCREEN-shared PANEL — Backlog delta (BacklogDeltaList)

Shows what changed in the backlog **since last visit**: added / closed / priority-changed / status-changed. Used on the Plan "Backlog" tab (scoped to the plan's EPICs) and as a section in the project-scope Brief's "Co se změnilo". **Source (MF2): the current rows from `GET /api/backlog?project=` diffed CLIENT-SIDE against the localStorage `BacklogSnapshot`** (the full `{id,status,priority}[]` captured at the prior visit, keyed by `scopeKey`, §13.3/§13.7) — a bare `lastSeen` timestamp cannot do this because `backlog.md` has no per-row timestamps, so the FE keeps the full row snapshot. `buildBacklogDelta(currentRows, snapshot)` (FE) yields `added`/`closed`/`priorityChanged`/`statusChanged`; each row deep-links to the originating EPIC/proposal. **First visit / cleared storage (no snapshot)** → `firstVisit:true`, no chips, the panel shows the current open rows under "bez porovnání - vše jako nové". (Read-only in MVP1 — the "Upravit" write mode is MVP1.5, §10.)

**DESKTOP**
```
┌─ BACKLOG  -  co se změnilo (BacklogDeltaList) ──── od 18.6. 21:40 ─────────────┐
│  [+ Přidáno 2]   [✓ Uzavřeno 1]   [↕ Změněná priorita 1]                     │
│  ─────────────────────────────────────────────────────────────────────────── │
│  + IMP-014 · perf · scanner · „cap paralelních čtení (p-limit)"  vys.   →     │
│  + IMP-015 · docs · pathmap · „doplnit příklad mapování cest"    stř.   →     │
│  ✓ IMP-011 · „odstranit hardcoded port" · uzavřeno (approved)           →     │
│  ↕ IMP-009 · „retry hot-spot logging" · stř. → vys.                     →     │
│  ─────────────────────────────────────────────────────────────────────────── │
│  Celkem otevřených návrhů: 12   (přidáno 2 − uzavřeno 1 od minule)            │
└──────────────────────────────────────────────────────────────────────────────┘
```
Row anatomy: a delta-kind glyph (`+` added / `✓` closed / `↕` re-prioritized, each its own `StatusBadge` colour — added=`bezi`, closed=`proslo`, reprioritized=`pozor`), `BacklogItem.id`, type, area, suggestion (truncated), priority, link. **Two distinct empty states (honest, MF2):** when a snapshot exists but nothing differs → "Backlog se od minule nezměnil."; on the **first visit** (`firstVisit:true`, no snapshot) → "bez porovnání - vše jako nové" with the current open rows listed plain (no +/✓/↕ glyphs, since there is no baseline to call them "new"). The three count chips are the panel header; tapping a chip filters to that delta kind.

**MOBILE**
```
┌─────────────────────────────┐
│ BACKLOG · změny od 18.6.    │
│ [+2] [✓1] [↕1]              │
├─────────────────────────────┤
│ + IMP-014 perf scanner  vys│
│   cap paralelních čtení   → │
│ + IMP-015 docs pathmap  stř│
│ ✓ IMP-011 hardcoded port  → │
│ ↕ IMP-009 stř → vys       → │
│ ─────────────────────────── │
│ otevřených: 12 (+2 −1)      │
└─────────────────────────────┘
```

#### SCREEN-shared PANEL — Lessons learned (LessonsTable, per plan)

Renders `PlanDetail.lessons` (the full `LessonsView`; `PlanSummary.lessonsPreview[]` is the thin list-row variant) sourced from `.aid-o/work/lessons-learned.md` (§4.7), filtered to the plan's EPICs by `Context(epic_id)`. Plain table; each lesson links to its EPIC when `epicId` is set. Used on the Plan "Lekce" tab.

**DESKTOP**
```
┌─ LEKCE Z PLÁNU (LessonsTable) ──────────────────────────────────────────────┐
│  Datum     Lekce                                              EPIC            │
│  ────────  ────────────────────────────────────────────────  ────────────    │
│  18.6.     „Latest run nejde řadit lexikograficky  -  max       E-044   →       │
│             started_at, jinak R-005-4_4 přebije run_2026…"                    │
│  15.6.     „compliance.json chybí na starších bězích  -  null,  E-043   →       │
│             ne 0 %, jinak se to tváří jako selhání."                          │
│  12.6.     „chokidar depth 5 mine gates_report.json (hloubka  E-042   →       │
│             6)  -  nastav 7."                                  (bez EPIC)        │
│  ─────────────────────────────────────────────────────────────────────────── │
│  3 lekce · řazeno od nejnovější                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```
When empty: "Z tohohle plánu se zatím nezaznamenala žádná lekce." `date:null`→"—" in the date cell; `epicId:null`→"(bez EPIC)", no link.

**MOBILE** — the table becomes stacked cards (date as a small caption, lesson as the body, EPIC as a footer chip):
```
┌─────────────────────────────┐
│ LEKCE Z PLÁNU (3)           │
├─────────────────────────────┤
│ 18.6. · E-044 →             │
│ Latest run nejde řadit      │
│ lexikograficky  -  max        │
│ started_at.                 │
│ ─────────────────────────── │
│ 15.6. · E-043 →             │
│ compliance.json chybí na    │
│ starších bězích  -  null,     │
│ ne 0 %.                     │
│ ─────────────────────────── │
│ 12.6. · (bez EPIC)          │
│ chokidar depth 5 mine       │
│ gates_report  -  nastav 7.    │
└─────────────────────────────┘
```


### 8.3 Component inventory

**Salvage from old `aid-gui` (keep mechanics, rebuild surface):** `Sidebar.tsx` mobile/hamburger + collapse → desktop sidebar (strip pulse/medical); `index.css` `--color-state-*` tokens → the whole status color system; recharts setup in `HealthObservatory.tsx`/`QueueScheduler.tsx` → Screen B charts; `EvidenceVault.tsx` file-tree → optional raw-artifact drawer in C; `Toast.tsx`, `ErrorBoundary.tsx` → as-is; `App.tsx` mobile-breakpoint + WS hook → shell; ACTA `Help.tsx` building blocks → Screen F.

**Map to library components:** Cards/tiles → shadcn `Card`; filter chips/segmented → `ToggleGroup`/`Tabs`; section tabs (mobile C, E; B/Plan tab strips, Rev 3) → `Tabs`; accordions (mobile Brief blocks, Rev 3) → base-ui `Accordion` (`Collapsible`); drawers/sheets (incl. audit "technické detaily" raw-md drawer) → base-ui `Dialog` (sheet variant); Help search → `Input` + `Command`; ⓘ tooltips → base-ui `Tooltip`/`Popover`; progress (plan/EPIC progress bars) → `Progress`; status + risk + severity badges → `Badge`; charts → recharts `AreaChart`/`BarChart`/`PieChart` + **`LineChart` (audit trend, Rev 3)**; icons → lucide-react.

**NEW components (Rev 2):** `ProjectTile` (A, Help Demo) · `CheckpointStrip` (A mini, C, Help Demo) · `FsmTimeline` (C, Help Demo) · `ExplanationCard`/`ExplanationLine` (ⓘ, everywhere) · `EventRow` (D, C narrator) · `AgentRolePanel` (C) · `MetricBadge` (B, C) · `ComplianceMatrix` (desktop E) / `ComplianceCards` (mobile E) · `StatusBadge`/`StatusDot` (all) · `DurationBar` (C) · `BottomTabBar` (mobile) · `InstallPwaButton` (A, Více).

**NEW components (Rev 3 — managerial layer).** All consume the Rev 3 contract types (§7.5) and reuse the §6 dictionary so they speak the same Czech as the rest of the UI:

| Component | Used on | Renders (contract) | shadcn / base-ui / recharts mapping + reuse |
|---|---|---|---|
| `BriefPanel` | G (infra), B tab 1 (project), Plan tab 1 (plan) | one `Brief` — all seven blocks | shadcn `Card` per block + base-ui `Collapsible` (mobile) + `ToggleGroup` (block filter); each line **reuses `ExplanationLine` + `StatusDot`** (Rev 2); deep-links via react-router `Link`. ONE component, `scope` prop drives which blocks show. |
| `RiskBadge` | inside `BriefPanel` (G/B/Plan) | `Risk.level` + a `Popover` of `Risk.reasons[]` | shadcn `Badge` (colour from §6.2 `STATUS`, matching the §13.10 `concept:risk:*` keys exactly: nízké=`proslo`, střední=`pozor`, vysoké=`zablokovano`, neurčeno=`ceka`) + base-ui `Popover` for reasons; reasons rows reuse `StatusDot`. |
| `DecisionsNeededList` / `ChangedSinceList` | block renderers inside `BriefPanel` | `Brief.decisionsNeeded[]` / `Brief.sinceLastSeen` | thin list wrappers over `ExplanationLine` + `StatusDot`; `ChangedSinceList` also renders the header counts pill (`sinceLastSeen.counts`) and embeds `BacklogDeltaList` for the backlog slice. |
| `AuditSummaryCard` | C (per-run); Plan "Audit" tab (`boundaryAudit` + `aggregateAudit`, SF4); **Screen B "Audit" tab (project `aggregateAudit`, MF7)** | one `AuditSummary` | shadcn `Card`; category bars via recharts `BarChart` (horizontal) **or** a `DurationBar`-style CSS bar (reuse); `Badge` for score/severity tallies; base-ui `Dialog` (sheet) for "technické detaily" raw-md (`/file`); `Popover` for `rawScore` tooltip. The `aggregateAudit` variant shows `medianEpicId` as a "z EPICu E-xxx" provenance chip and the `scoredEpicCount` "n=N" note (§13.5.7). |
| `AuditTrendChart` | C, EPIC detail; Plan "Audit" tab; **Screen B "Audit" tab (project scope, MF7)** | `AuditTrend` (`points[]`) | recharts **`LineChart`** with `connectNulls={false}` so `score:null` gaps render as breaks (never interpolated, §13.5); mobile = compact sparkline variant, dots tappable → that run's audit. The project-scope variant plots one point per audited EPIC (`scope:'project'`). |
| `PlanPhaseTimeline` | Plan "Fáze" tab | `PlanSummary.epicIds` in plan order, each node = latest-run `FsmState` | **adapts `FsmTimeline`** (Rev 2) horizontally for desktop (nodes = EPICs not states), vertical stepper on mobile; node colour from §6.2 `STATUS`; reuses `StatusDot` + `ExplanationLine`. |
| `PlanOutcomeTable` (Rev 4.1) | Screen A "Výsledky plánů" | filtered `PlanOutcomeAnalytics.plans[]` + totals | shadcn `Table` desktop / stacked rows mobile; project select + outcome segmented filter; `StatusBadge` maps all five outcomes; unknown CP/proof values remain `?`; icon+tooltip JSON export uses a client `Blob`, no server write. |
| `BacklogDeltaList` | Plan "Backlog" tab; project-Brief "Co se změnilo" | current `BacklogItem[]` (`GET /api/backlog`) diffed **client-side** vs the localStorage `BacklogSnapshot` (`{id,status,priority}[]` keyed by `scopeKey`, §13.7, MF2) → `added`/`closed`/`priorityChanged`/`statusChanged`; `firstVisit:true` → "bez porovnání" | shadcn `Card` + `ToggleGroup` (the +/✓/↕ count chips as filters); rows reuse `StatusBadge` (added=`bezi`, closed=`proslo`, reprioritized=`pozor`); read-only MVP1 (write toggle = MVP1.5). |
| `LessonsTable` | Plan "Lekce" tab | `PlanDetail.lessons` (`LessonsView`) | shadcn `Table` (desktop) / stacked `Card`s (mobile); EPIC chip = `Badge` + `Link`; empty + null-cell handling per the panel spec. |
| `ReporterDeliveryPanel` (Rev 4, MF6) | Plan "Dodávka & zjednodušení" tab | `PlanDetail.deliveryReport` (`ReporterDelivery`) | shadcn `Card`; `outcome` → `StatusBadge`; `testEvidence[]` rows = `Link` (via `/file`) + an `exists`-driven `StatusDot` (missing-on-disk → `pozor` ⚠, never dropped); base-ui `Dialog` (sheet) for the raw delivery `.md`; `present:false` → "Reporter zatím neběžel". No new primitive. |
| `SimplifierPanel` (Rev 4, MF6) | Plan "Dodávka & zjednodušení" tab | `PlanDetail.simplifierSummary` (`SimplifierSummary`) | shadcn `Card`; `proposals[]` as a list; `disposition` → `Badge` (přijmout/odmítnout/odložit); `effort` chip; row `Link` to area; base-ui `Dialog` (sheet) for the raw `simplifier-report.md`; read-only (no apply action in MVP1); `present:false` → "Simplifier zatím neběžel". No new primitive. |

These managerial components mean Screen G, Screen A outcomes, the Plan screen, the B/Plan first-tab brief, the project/plan audit tabs, and the Rev-4 plan delivery/simplifier tab are built **almost entirely from reused Rev 2 primitives** (`ExplanationLine`, `StatusDot`, `StatusBadge`, `DurationBar`, `FsmTimeline`, `Card`, `Tabs`, `Dialog`, `Popover`, `Badge`) plus one new recharts `LineChart` for the audit trend. `PlanOutcomeTable`, `ReporterDeliveryPanel`/`SimplifierPanel` (MF6), and the project Audit tab (MF7, which reuses `AuditSummaryCard`/`AuditTrendChart`) add **no** new primitive; they compose the standard `Table`/`Card`/`Dialog`/`Badge`/`Link`/`StatusDot` set, keeping the managerial layer visually consistent with the monitoring layer and avoiding a parallel component system.

### 8.4 Human-explanation UX

One module `lib/explain.ts` (FE thin wrapper over the `/api/explanations` dictionary, which returns `Record<string, DictionaryEntry>`), three render surfaces. Each surface ultimately renders a runtime `Explanation` (`{headline, detail, status, color}`, §6.4/§7.5) resolved from a `DictionaryEntry`:
1. **Inline subtitle (default, always visible)** — a muted one-line Czech gloss under any technical label (headers, FSM timeline, agent panels). The core explanation is never hidden behind hover.
2. **ⓘ Popover (on demand)** — deeper "why does this exist" text behind an `ⓘ` icon (base-ui Popover; on mobile a tap-sheet, never hover-only).
3. **Event translation (narrator)** — `explainEvent(event)` resolves a raw timeline/audit row to a runtime `Explanation` (Czech sentence); drives Screen D rows and Screen C narrator.

The dictionary (`DictionaryEntry` set) covers 6 FSM states, all transitions, CP1-CP6, the agent roles, each gate name, each compliance check, severity terms, retry/hot-spot, queue states. Help imports the **same `DictionaryEntry` content** (renders from `term`/`keywords`/long-form) — single source of truth for terminology.

### 8.5 Visual language

**Status vocabulary — reuse the canonical §6.2 `STATUS` table (8 tokens: bezi, ceka, proslo, selhalo, zablokovano, eskalace, pozor, necinne).** §8.5 does **NOT** define its own colours; there is **one table, one colour per token**, referenced by backend, frontend, Help, and tests. DONE maps to `proslo`; an idle project/run maps to `necinne`. The old salvaged `--color-state-*` CSS vars simply **map onto** the canonical tokens (re-pointed at the §6.2 hex), with these dots/icons:

| §6.2 token | Word | Dot/icon | old `--color-state-*` it replaces |
|------|------|------|------|
| `bezi` | běží | ● | `--color-state-executing` |
| `ceka` | čeká | ◐ | `--color-state-pm-approval` |
| `proslo` | prošlo / hotovo (DONE) | ✓ | `--color-state-gates`, `--color-state-done` |
| `selhalo` | selhalo | ✕ | `--color-state-error` |
| `zablokovano` | zablokováno | ▣ | (blocked) |
| `eskalace` | eskalace | ⚠ | `--color-state-curator-resolve` |
| `pozor` | pozor | ⚠ | (warning/advisory/override) |
| `necinne` | nečinné | ○ | `--color-state-idle` |

(Colour hex is whatever §6.2 `STATUS` defines — this table only fixes the dot/icon and the old-var → token mapping, never a separate colour.)

**Theme:** a **light, calm theme** (like ACTA's help) over the old dark glass/grain — reads better on a phone in daylight, matches the "plain, human, decent" brief. Saturated status colors as accents on neutral surfaces. Status color is **never** the only signal — always paired with a word + icon (colorblind-safe). **Density:** Overview airy (cards, generous gaps); EPIC Deep View dense but sectioned (`tabular-nums` for times/counts); mobile single column, 16px gutters, 44px+ touch targets, bottom-tab safe-area padding. Type: Inter, `tabular-nums` for metrics, mono for ids/branch/hashes.

## 9. Eco integration & deployment

### 9.1 Repo layout & versioning

Keep `packages/aid-server` + `packages/aid-gui` + `packages/aid-contract` as an npm-workspaces monorepo at repo root, **fully separate from `plugins/aid-orchestrator/`**. The plugin manifest declares only `commands`+`skills` and `marketplace.json source = ./plugins/aid-orchestrator` — `packages/` is outside the distribution boundary and **MUST NOT** be added to the plugin manifest (shipping a Node server + `/opt/eco/projects` assumptions would break plugin portability and leak infra).

**Versioning — independent, NOT tied to the plugin.** The plugin version (currently 2.33.1, single-source = CHANGELOG header) and the 8-file version registry in `CLAUDE.md` govern only `commands/`+`skills/`. The Cockpit touches none of those. **The "On Plugin Changes" CLAUDE.md rules (dual CHANGELOG, 8 version files, defaults sync, skill-lint) DO NOT apply to `packages/` work.** A Cockpit PR that touches only `packages/` must not bump the plugin version or edit the plugin CHANGELOG. Add a separate `packages/CHANGELOG.md` for the Cockpit's own history (start `0.1.0`). `.gitignore` already excludes `node_modules/`, `dist/`, `.aid-o/` — PWA build output (`dist/sw.js`, `manifest.webmanifest`) is under `dist/`, already covered.

### 9.2 Port & networking (G-008)

- **App port 3911.** Host port = internal port (`3911:3911`). One process serves everything (MVP 1): Express serves built Vite `dist/` at `/`, JSON API under `/api`, WebSocket at `/ws` — all on 3911.
- **Dev:** two-process. `aid-gui` Vite dev server (HMR, 5173) with `server.proxy` for `/api` + `/ws` → `http://localhost:3911` (net-new in `vite.config.ts`); `aid-server` `tsx watch`. `config.ts` CORS already whitelists `localhost:5173`.
- **Prod (= eco-dev mirror):** single container, `node dist/index.js`, static `dist/` baked in. No separate nginx for MVP 1.
- **`AID_HOST`:** compose sets `0.0.0.0` (container reachability); `config.ts` defaults `127.0.0.1` — keep the compose override.

### 9.3 PWA delivery

Net-new (nothing exists today). Tooling: **`vite-plugin-pwa`** (Workbox):
```ts
VitePWA({
  registerType: 'autoUpdate',
  manifest: {
    name: 'AID Cockpit', short_name: 'AID',
    description: 'Cross-project monitoring for the AID orchestrator',
    background_color: '#f8fafc', theme_color: '#0284c7',   // LIGHT — matches §8.5 light theme + canonical brand/status (was dark #0b0f17)
    display: 'standalone', start_url: '/',
    icons: [
      { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
      { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
      { src: '/icon-512-maskable.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
    ],
  },
  workbox: {
    globPatterns: ['**/*.{js,css,html,svg,woff2}'],   // app shell only
    navigateFallback: '/index.html',
    runtimeCaching: [
      { urlPattern: ({ url }) => url.pathname.startsWith('/api'), handler: 'NetworkOnly' },
    ],
  },
})
```
**Caching (the critical correctness point):** the SW caches the **app shell + Help only** (hashed static assets = precache, immutable; `index.html` = revalidate via `registerType:autoUpdate`). **AID live data (`/api/...`) stays `NetworkOnly` — NEVER cached** by the SW. DISK IS THE ONLY SOURCE OF TRUTH; caching API responses would let stale FSM/compliance state masquerade as fresh. When the socket goes down the UI engages the §7.3 REST polling fallback (5s); only when the network itself is unreachable does it show "offline".

**"Last known" data is in-memory only (resolves the audit's NetworkOnly vs last-known conflict, Q4):** the only "last known" values are whatever react-query already holds **in memory for this browser session**. They are shown with their fetch timestamp ("naposledy v HH:MM") so the user always sees how old they are. "Last known" data is **NEVER written to the SW cache or to localStorage** — so it can never be served as if it were a fresh network response, and stale data can never masquerade as live. When the browser is offline and there is **no in-memory value** for a tile, it shows **"bez dat / offline"**, never a fake/zero value.

**Offline posture:** the SW serves the cached app shell + Help (static React content, genuine value-add, renders fully offline). Data tiles render only from in-memory react-query state (timestamped as above) or "bez dat / offline"; no fake/stale monitoring data is ever shown. WebSocket is not cacheable — when offline (or socket-down) the §7.3 polling fallback / offline banner applies.

**HTTPS requirement (installability):** PWA install + SW require a **secure context** (HTTPS or `localhost`/`127.0.0.1`). `http://10.20.20.22:3911` over VPN is NOT secure → SW won't register, phone install won't appear. **Decided (§11.11): (B) is MVP 1.** Phone install runs over `aid.aidlab.dev` via **nginx + the cloudflared tunnel** (CF terminates TLS → valid cert → installs cleanly on phone) + CF Access Google OAuth gating — the PM provisions this infra. **(A) desktop install** via `http://localhost:3911` (host or SSH tunnel `ssh -L 3911:localhost:3911`) stays as the dev/verify path. The build must therefore work behind the proxy (relative URLs, `X-Forwarded-*`, `/ws` through nginx+CF with the `CF_Authorization` cookie — §9.5).

**Icons:** need 192/512/512-maskable PNGs in `aid-gui/public/` (only `favicon.svg` exists) or the manifest is invalid.

### 9.4 Deploy — docker-compose for eco-dev

```yaml
# docker-compose.yml (aid-cockpit MVP1)
services:
  aid-cockpit:
    build: { context: ., dockerfile: Dockerfile }
    container_name: aid-cockpit
    user: "1000:1000"                       # match host owner (marekstancl) → clean reads
    ports:
      - "3911:3911"
    volumes:
      - /opt/eco/projects:/projects:ro      # cross-project read-only mount
    environment:
      - AID_PORT=3911
      - AID_HOST=0.0.0.0
      - AID_PROJECTS_ROOT=/projects         # NEW: parent dir to scan
      - AID_CORS_ORIGINS=http://localhost:3911
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:3911/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 5s
```
Key changes from the existing file: mount `/opt/eco/projects:/projects:ro` (the parent, not `.:/project`) — the cross-project enabler; `:ro` enforces "READS ONLY" at the kernel level. New `AID_PROJECTS_ROOT` replaces single `AID_PROJECT_ROOT`. **Drop `shared-infra` network** for MVP 1 (G-009: declare it only when a `svc-*`/`infra-*` container is reached; the read-only monitor reaches none — re-add in MVP 2 for LiteLLM). Drop `~/.claude`, LiteLLM, Whisper, OpenAI env (AI-companion MVP 2 wiring). `user: "1000:1000"` for clean reads and pre-positioned MVP 1.5 write ownership. G-015 dev override (`docker-compose.override.yml`) runs vite HMR + `tsx watch` — but for a monitor you'll mostly run `npm run dev` natively on the host.

Run: `ssh marekstancl@10.20.20.22 && cd /opt/eco/projects/aid-orchestrator && docker compose up -d --build && curl http://localhost:3911/api/health`.

### 9.5 Auth & access (MVP 1)

**Eco-standard: nginx + cloudflared + CF Access on `aid.aidlab.dev` (PM-provisioned).** Per the §11.11 PM decision, access is gated by **CF Access Google OAuth** (allow `stancl.marek@gmail.com`) in front of an nginx reverse proxy fed by the cloudflared tunnel; CF terminates TLS (valid cert → phone PWA install). **The PM sets up the nginx vhost, the CF tunnel route, and the CF Access policy** — this is infra config, not Cockpit build work. The app itself stays auth-agnostic (no in-app login): it trusts that anything reaching it has already passed CF Access. Build obligations behind the proxy: (1) honour `X-Forwarded-Proto/Host` and use relative URLs so it serves correctly under `https://aid.aidlab.dev` (never hardcode `:3911` in the client); (2) the `/ws` upgrade must succeed through **both** nginx (WS `Upgrade`/`Connection` headers in the vhost) **and** CF Access (the upgrade carries the `CF_Authorization` cookie — risk #5) — this gets an explicit AC and a manual verification step before phone support is declared done. **If the `/ws` upgrade fails or the socket drops, the dashboard does NOT go dark** — the §7.3 REST polling fallback engages within ~5s (`GET /api/activity` + active query re-validation every 5s) with the banner "živé spojení nejede - aktualizuji po 5 s", so live monitoring degrades gracefully rather than failing. Localhost (`http://localhost:3911`, host or SSH tunnel) remains the unauthenticated dev/verify path. The container still binds `0.0.0.0:3911`; on the VPN that is WireGuard-gated, and the public path is CF-Access-gated — both covered.

### 9.6 Cross-project file access (containerized)

Mount `/opt/eco/projects:/projects:ro`; scanner enumerates `/projects/*/.aid-o`. Target dirs are `marekstancl:marekstancl 0755` (world-readable). `:ro` is load-bearing — removing it is a deliberate MVP 1.5 decision with its own review. **Path-translation gotcha (must be actively enforced, not just flagged):** inside the container paths are `/projects/<p>/.aid-o`, but evidence JSONL/yaml embed **absolute host paths** (`/opt/eco/projects/...`) in fields like `evidence_dir`, and some run ids are derived from absolute paths (e.g. `R-ABSPATH-001`). A passive "scan root maps to host root" note is not enough — **every embedded-path read and every run-dir match MUST go through a central path mapper or it will mismatch.** Implement `pathmap.ts` exporting `containerToHost(p)` / `hostToContainer(p)`, both derived from `AID_PROJECTS_ROOT` + a configured `AID_HOST_ROOT` (default `/opt/eco/projects`) — **never hardcode `/opt/eco/projects`** in the server body. Rule: resolve **container** paths for all reads; display **host** paths in the UI (what Marek navigates to). **The `/file` endpoint (§7.4.1) resolves every served artifact through this `pathmap`** — container path for the `realpath`/read, host path only for display — and applies the §7.4.1 allow-list + CWE-22 + symlink/`..`/absolute rejection + 1 MB cap on top. **Unit test (required):** a fixture run whose `timeline.jsonl` embeds an absolute host `evidence_dir` must resolve to the correct in-container file and match its run dir. **Self-inclusion:** the Cockpit's own `aid-orchestrator/.aid-o` is one of the scanned projects (dogfooding) — desired. **Filter both broken workspaces** (`vulcan.broken-20260430-0741` AND `cicero.broken-20260430-0735`) and any `*.broken-*`/`*.bak`/`*.old`/`-YYYYMMDD-HHMM` suffixed dir or dir without `config/`+`work/`.

### 9.7 Observability hook (seam only, not MVP 1)

AID writes its own timeline/audit JSONL — the Cockpit reads those directly, no Loki needed. **Future cost/time-series seam (MVP 2+):** token spend per EPIC, model latency live in LiteLLM → Langfuse (:3190) / VictoriaMetrics (:3820) / Grafana (:3803), not `.aid-o/`. Clean seam: the per-EPIC detail view gets a "View cost in Grafana" deep-link (dashboard URL with EPIC/time-range query params), not the Cockpit querying VM/Loki. **Do not build in MVP 1** — leave a slot. **Alerting seam (MVP 2):** stuck FSM / ESCALATION ping via `@eco_system_alerts_bot` (`services/scripts/lib/telegram-notify.sh`).

## 10. Phasing

### MVP 1 — read-only deep monitoring

> **Scope expectation — deep monitoring is SPARSE on history (consistent with the locked "v3 only" decision).** "Track EVERYTHING AID offers" applies in full only to the ~14 runs (of ~97 dirs cross-project) that have `fsm-state.yaml`, and the *rich* CP/timing/provenance detail only to the even smaller subset (3-11 runs) with rich timeline events. The bulk of historical runs render as `legacy`/`stub` with little detail — **this is expected, not a bug**; the UI must show "starší formát / bez detailu" for them, never a broken deep view. New runs going forward carry the full signal set.
> **Metric incrementality.** §5 inventories ~40 metric ids. The `MetricSet` contract already nulls un-computable fields, so `MetricSet` ships **incrementally** — a metric returning `null` with a flag is acceptable for MVP 1; computing all 40 is NOT an MVP 1 gate. The MVP 1 gate is the AC list below.
>
> **MVP-1 gate fields (which `MetricSet`/`RunDetail` fields MUST be correct & non-null on a v3 run):** FSM `state` + `currentStep`/`totalSteps`; gate `overall` + per-gate pass/fail + `attempts`; compliance `overall` + structured `failures` (`ComplianceFailure[]`, MF3 — `check`+`severity` preserved) + `force_override_count`; CP1-CP5 presence + verdict; `run_duration_sec` (best-effort, with `start_source`/`end_source` tag per §5.1). **Explicitly NOT gating (ship as `null` when unavailable):** per-step durations (`stepDurationsS`), dispatch durations, and CP2/CP3/CP4 retry counts when the timeline lacks dispatch events (`checkpointRepeats` null per §MF5). CP6 is not gated on `/aid-run` EPICs (it is Fast-Mode-only, Q1).

**Backend modules:**
- `packages/aid-contract` — raw + view types (§7.5), `STATUS` (8-token canonical), `DictionaryEntry` + runtime `Explanation` types, `Score`, `EventTopic`/`ALL_EVENT_TOPICS`, **the managerial types** (`Brief`/`BriefItem`/`Risk`/`RiskReason`, `PlanSummary`/`PlanDetail`, `PlanOutcomeSummary`/`PlanOutcomeAnalytics`, `AuditSummary`/`AuditTrend`/`AuditTrendPoint`, `BacklogDelta`/`BacklogDeltaItem`, `LessonsView`/`LessonEntry`, `LastSeen`), and **the two seam types** (`TimeSource`; `MemoryQuery`/`MemoryEntry`/`MemoryResult`, §13.9).
- `packages/aid-server/src/`:
  - `services/scanner.ts` (`ProjectScanner` — discovery, latest-run, two-tier cache, denylist).
  - `services/fs-reader.ts` (adapted, per-call `aidoPath`).
  - `parsers/*` (reused: json, yaml, jsonl, markdown, utils, index).
  - `watchers/file-watcher.ts` (adapted cross-project, `PATH_RULES`, `projectId`).
  - `ws/websocket.ts` (adapted `AidWebSocket`, project filtering, activity-buffer replay).
  - `explain/{types,explain,dictionary.cs}.ts` (full §6.3 dictionary + the §13.10 `concept:*` keys).
  - `routes/{health,projects,epics,compliance,backlog,activity,queue,metrics,explanations,file}.ts` (all read-only, §7.4) + managerial read-only routes `routes/{brief,plans,plan-analytics,lessons,audit-trend,memory}.ts` + `routes/path-validation.ts` (reused) + `api/middleware.ts` (envelope). **No `routes/backlog-delta.ts`** — the backlog delta is client-side in MVP1 (MF2); `/api/backlog` serves current rows + `meta:{openCount,closedCount}`. `routes/memory.ts` is an **MVP1 STUB** returning `{available:false,reason:"MVP2"}` (§13.9) — no Qdrant/MCP call.
  - **Managerial projection builders (pure over the scanner cache, no new source of truth, no writes — reads confined to existing v3 artifacts the Tier-1 index already covers, SF2):** `brief/build-brief.ts` (`buildBrief(runSet, scope, since)`, §13.4) + `brief/risk.ts` (`computeRisk(signals): Risk`, §13.2) read only already-parsed §4/§5 signals; `plan/build-plan.ts` (`buildPlan(planId, scope)`, §13.6), `plan/build-plan-outcomes.ts` (`PlanOutcomeAnalytics`, §13.12), `audit/build-audit-summary.ts` + `audit/build-audit-trend.ts` (`AuditSummary`/`AuditTrend`, §13.5), and `lessons/build-lessons.ts` (`LessonsView`, §13.8) parse the existing `plans/*.md`/`audit-report.md`/`lessons-learned.md` v3 files (Tier-1 indexed, Tier-2 parsed on demand). The Plan Outcome builder reuses scanner objects and MUST NOT execute `aid-diagnostic.sh`; that script is a fixture/regression oracle for overlapping fields only. The **backlog delta** has **no server builder** in MVP1 (MF2): the server only serves current `backlog.md` rows + counts via `routes/backlog.ts`; the diff is the client `buildBacklogDelta(currentRows, snapshot)` in `packages/aid-gui/src/lib/backlog-delta.ts`. None of these writes.
  - `metrics/compute.ts` (§5 metric ids; emits `MetricSet.timeBy` as the §13.9 `TimeSource` seam — `user`/`dev` `null`/"neměřeno").
  - `config.ts` (adapted, `AID_PROJECTS_ROOT`), `index.ts` (adapted skeleton, no registry/ideas/companion).
- Drop: `companion/*`, `services/{project-registry,ideas-migration}.ts`, `routes/{companion,voice,ideas}.ts`, `scheduling/*`, all write routes.

**Frontend (`packages/aid-gui`):** Screens A-F (§8.2) **+ Screen G "Co potřebuju vědět" (the `/` front door, §8.1) + the first-class Plan detail screen (`/p/:project/plans/:planId`, §13.6)**; the `Brief` component (one shape, three scopes — Screen G, Screen B tab 1, Plan tab 1, D1); the Screen A "Výsledky plánů" table/cards + filters + JSON export (§13.12); the audit-summary panel + recharts trend (§13.5.5), backlog-delta panel (§13.7), lessons-per-plan panel (§13.8), deterministic risk-level badge with the MVP2 success-probability placeholder (§13.2/D2); the `lastSeen` localStorage store (§13.3); components from §8.3; `lib/explain.ts`; react-query + WS hook; `vite-plugin-pwa` + manifest + icons + `server.proxy`.

**Endpoints (all read-only, §7.4):** the Rev 2 set (`/api/{health,projects,epics,compliance,backlog,activity,queue,metrics,explanations,file}` + `/ws`) **plus the managerial endpoints** `/api/brief`, `/api/brief/:projectId`, `/api/brief/:projectId/:planId`, `/api/plans/:projectId`, `/api/plans/:projectId/:planId`, `/api/analytics/plans?project=&outcome=&since=`, `/api/lessons`, `/api/audit-summary/:projectId` (project `aggregateAudit`, MF7), `/api/audit-trend/:projectId` (project scope, MF7), `/api/audit-trend/:projectId/:epicId`, `/api/audit-trend/:projectId/plan/:planId`, and the **`/api/memory` MVP1 stub** (`{available:false,reason:"MVP2"}`, §13.9). **No `/api/backlog-delta`** — the backlog delta is computed client-side from a localStorage snapshot (MF2); `/api/backlog` serves the current rows + `meta:{openCount,closedCount}`. (Server-side field-level delta = MVP1.5.)

**Managerial surfaces are MVP1** (moved in per the locked decisions): `ProjectBrief`/`PlanBrief` read-models (the one `Brief`, three scopes), Screen G, the Plan detail screen, cross-project Plan Outcome Analytics (§13.12), the audit-summary panel + trend, the backlog-delta panel, the lessons-per-plan panel, `lastSeen` (localStorage), and the deterministic risk level. **Deferred (NOT MVP1):** the user-notes module + server-side multi-device `lastSeen` + backlog writes → **MVP1.5**; the LLM brief narrative + success-probability % + memory read + active agent + WakaTime import → **MVP2**. The `TimeSource` (§13.9) and memory taxonomy (§13.9) are **seams only** in MVP1 (types + stub, no measurement/read).

**Acceptance criteria** (Rev 2 #1-#11 below; managerial ACs #12-#24 are in §13.11 and Plan Outcome Analytics AC #25 is in §13.12):
1. Visiting `/` lists exactly the 6 valid **top-level** workspaces (aid-orchestrator, wan, vulcan, krok, acta, sousto-na-miru), discovered by the **depth-1** glob `<scanRoot>/*/.aid-o` only. The regression test asserts: (a) **both** broken workspaces are excluded (`vulcan.broken-20260430-0741` AND `cicero.broken-20260430-0735`); (b) sibling dirs with no `.aid-o` (`cicero`, `myinvoice`, `panopticon`, `_refs`) are excluded by the glob; and (c) the **nested** `.aid-o` dirs that exist on disk are NOT discovered as separate projects and NOT recursed into — `krok/backend/.aid-o` and `vulcan/ui/.aid-o` never appear (depth-1 glob can't reach them; they also lack `config/`), and `krok`/`vulcan` each surface as exactly **one** workspace (the top-level one). The count is exactly 6, not 6+nested.
2. Latest-run selection picks the run with max `started_at`/mtime, never lexicographic (regression test with `R-005-4_4-1` vs `run_20260224_115f`).
3. Screen C shows, for a v3 run, all of: FSM state + progress, FSM transition walk, CP1-CP6 strip with verdicts + provenance, 4 agent role panels, per-step timings + retry counts, gates with `duration_ms`, compliance checks with severity — each with a Czech explanation line.
4. The activity stream (Screen D) is built from **per-run** timelines; the root `work/timeline.jsonl` is read **ONLY** to extract `focus:cp1` dispatch-enrichment events (§4.0 finding #1) and for nothing else. Each row carries a Czech translation; a file change on disk appears within ~2s via WS.
5. Compliance (Screen E) shows force-override counts and flags SYSTEMATIC per the §4.5 thresholds; `null` checks render "N/A", never 0%/fail.
6. Help (`/help`) renders the 13 SECTIONS with working search + scrollspy + live `<Demo>` components, reusing the dictionary.
7. `ac_verified_pct` renders "N/A — fast mode" for `plan_path: null` EPICs, never 0%.
8. No write to any `.aid-o/` occurs (the read-only invariant grep test passes; container runs `:ro`).
9. **PWA installs on the phone via `https://aid.aidlab.dev` (eco-standard nginx + cloudflared + CF Access) — PM decision, risk #11 resolved.** Manifest + SW validate in the secure (HTTPS) context CF provides; `/api` is `NetworkOnly` (never cached); offline shows the cached shell + Help with no stale data. The PM provisions the nginx vhost + CF tunnel route + CF Access policy; the build's AC is: (a) the app works behind the proxy under `https://aid.aidlab.dev` (relative URLs / `X-Forwarded-*`, not hardcoded `:3911`); (b) `/ws` upgrades successfully through nginx **and** CF Access (carries the `CF_Authorization` cookie); (c) the **REST polling fallback engages within ~5s of socket loss** (failed upgrade, CF/proxy issue, or idle-close), polling `/api/activity` + re-validating active queries every 5s, with the visible banner "živé spojení nejede - aktualizuji po 5 s"; (d) the PWA installs and runs standalone on a phone over the VPN/CF path. Localhost desktop install (`http://localhost:3911`) remains a supported dev/verify path.
10. Every screen has a real mobile layout (bottom tab bar, single-column, 44px+ targets) — not a shrunk desktop.
11. Parsers never throw on malformed/legacy/stub fixtures (vitest green).

### MVP 1.5 — backlog write + user notes + server-side lastSeen

**Modules/screens/endpoints:**
- New sub-route `/p/:project/backlog` (B tab) with a write-mode toggle ("Upravit"); reuses `EventRow`/`StatusBadge`. (The MVP1 client-side backlog **delta** read view, §13.7/MF2, still works unchanged — this adds *writes* on top.)
- **Server-side field-level backlog delta** (the MVP1 client-side delta, §13.7/MF2, promoted) — add a server snapshot store so `GET /api/backlog-delta?since=` can compute `added`/`closed`/`priorityChanged`/`statusChanged` server-side and sync the "co se změnilo v backlogu" view across devices (multi-device, like server-side `lastSeen` below). The MVP1 `BacklogDelta` contract shape is forward-compatible — only the *source* of the diff moves from the FE localStorage snapshot to the server store; `routes/backlog-delta.ts` is added here (it does **not** exist in MVP1).
- **User-notes module** (its own module) — internal notes / CLIENT notes / ideas / risks / tasks / meeting notes / decisions, with an **internal-vs-client separation**; **own store**, never `.aid-o`. Reached as a project sub-tab + a "Více" entry on mobile; isolated route.
- New top-level nav "Moje" (personal tasks, **own store**, not `.aid-o`) — sidebar item / "Více" entry on mobile; isolated route.
- **Server-side multi-device `lastSeen`** — promote `LastSeen` (§13.3, MVP1 localStorage-only) to a per-user server resource so "co se změnilo od poslední návštěvy" syncs across devices. The `?since=` param and the `LastSeen` contract type are forward-compatible — the source of `since` swaps from localStorage to the server store with **no endpoint change** (§13.3).
- Backend: `POST/PATCH /api/backlog/:project` (write `work/backlog.md`/`backlog/`), `routes/user-notes.ts` + `routes/personal-tasks.ts` (own JSON stores), `routes/last-seen.ts` (per-user lastSeen store).
- Relax the `:ro` mount **deliberately and narrowly** — a separate RW mount scoped to the backlog paths or a dedicated dashboard data dir, NOT blanket `rw` on `/opt/eco/projects`. Update the read-only invariant test's allow-list.

**Acceptance criteria:** backlog edits persist to disk and re-appear on reload (disk is truth); user notes keep internal vs client separation in a separate store and never touch `.aid-o/`; personal tasks live in a separate store and never touch `.aid-o/`; server-side lastSeen syncs the "since last visit" view across devices; the narrow RW mount cannot write outside the allow-listed paths; MVP 1 read screens are unchanged.

### MVP 2 — active improvement agent + memory view

**Modules/screens/endpoints:**
- **Wire `/api/memory` from the MVP1 stub to the real read** — read `vulcan-memory`/Qdrant `clavi_facts_{tenant}` via the read-only MCP, honouring the `MemoryQuery` filters (`scope`/`projectId`/`planId`/`type`/`createdDuringRun`, §13.9). New top-level nav "Paměť" — sibling of Compliance; reuses Help-style `<Section>` cards + search. `routes/memory.ts` (read-only MCP/Qdrant query) replaces the stub.
- **LLM brief narrative + success-probability %** — fill the `Brief.successProbability` envelope (MVP1 invariant `value:null, source:null`, D2) by setting `value` with `source:'agent'`, and add the smart "what this means" narrative on top of the deterministic §13.2 `Risk` (which stays the permanent fallback + terminology source). **Zero contract churn** — the envelope was forward-compatible from MVP1. The deterministic risk level never disappears; the % and narrative are additive.
- **WakaTime time import** — fill `MetricSet.timeBy` `user`/`dev` entries via the §13.9 `TimeSource` seam (`source:'wakatime'`); zero contract churn (the seam is already in `MetricSet`). The "kdo strávil kolik" breakdown appears once the source exists.
- EPIC Deep View narrator gutter gains a 2nd tab "Návrhy agenta" (mobile: another section tab); `AgentRolePanel` extends to interactive proposal cards.
- LLM narration: optional `narrative` field on `explain()` entries flagged `llm_eligible:true`, populated by the agent (static layer stays the fallback).
- Cost deep-links: per-EPIC "View cost in Grafana" link (no inline querying unless `shared-infra` is added).
- Re-add `shared-infra` network + LiteLLM access for the agent; alerting via `@eco_system_alerts_bot` for stuck FSM/ESCALATION.

**Acceptance criteria:** the memory view reads (never writes) the Qdrant collection and honours the `MemoryQuery` filters; the improvement agent proposes (never auto-applies) changes; `Brief.successProbability.value` becomes a model-derived number with `source:'agent'` and the LLM narrative is additive while the deterministic risk level + static dictionary still render when the agent is offline; WakaTime fills `timeBy` user/dev time with no contract change; cost deep-links open the correct Grafana dashboard with EPIC/time-range params.

## 11. Risks & open questions

1. **Single-project registry must be rewritten, not reused.** `config.ts` (`AID_PROJECT_ROOT`) + `ProjectRegistry.init()` (one "default" + manual `projects.yaml`) contradict the locked auto-discovery decision. The manual `projects.yaml` path is deleted (matches "NO manual registry").
2. **Layout drift across projects.** `wan/.aid-o` has extra `runs/` + a stray top-level `.md`. Parsers must treat missing dirs/files as "no data", not crash. Don't assume the 6 workspaces are byte-identical.
3. **The `.broken-` workspace trap is real and present** — **two** of them: `vulcan.broken-20260430-0741` and `cicero.broken-20260430-0735`. Without the denylist the UI shows phantom projects with garbage state. The denylist regex (`\.(broken|bak|old)\b` + `-\d{8}-\d{4}$`) covers both; AC #1 asserts it.
4. **Phone PWA is MVP 1, delivered via eco-standard nginx + cloudflared + CF Access (no longer a fast-follow).** Per the §11.11 PM decision (and §9.3/§10/§11.11), phone install ships in MVP 1 over `https://aid.aidlab.dev` — CF terminates TLS (valid cert → secure context → installable), CF Access Google OAuth gates it, and the PM provisions the nginx vhost + CF tunnel route + CF Access policy. The plain `http://10.20.20.22:3911` path is still not a secure context (so it is dev/localhost-only), but it is no longer the MVP 1 phone path. The residual **build** risk is the `/ws`-through-CF upgrade plus relative-URL / `X-Forwarded-*` proxy correctness (cross-ref risk #5); both now have explicit ACs (§10 AC #9) and the §MF3 / §7.3 REST polling fallback as mitigation so live monitoring degrades gracefully if the socket can't upgrade.
5. **WebSocket + reverse proxy.** When fronted by cloudflared/nginx, `/ws` upgrade must be proxied (WS upgrade headers) and carry the CF Access cookie. WsHandler binds same-origin (works direct); verify through the proxy before declaring phone support done.
6. **Versioning collision.** A future agent following CLAUDE.md "On Plugin Changes" might bump the plugin (2.33.1) when editing `packages/`. **Cockpit work does not touch the plugin version, the dual plugin CHANGELOG, the 8 version files, or `defaults/`.** Use `packages/CHANGELOG.md`.
7. **`:ro` → MVP 1.5 writes boundary.** The read-only mount must be relaxed deliberately and narrowly for backlog/personal-task writes (scoped RW mount), not blanket-`rw`. Flag now so the read-only guarantee isn't silently lost.
8. **`shared-infra` not needed in MVP 1** (G-009). The existing compose joins it for LiteLLM; the monitor doesn't — removing it is correct (note it so nobody "restores" it).
9. **Verifier wall-time and token cost are NOT on disk** (§5.6). The UI must label these "approximate"/"not measured", never fabricate. Cost is a Grafana deep-link seam, not an MVP 1 metric.
10. **The Compliance matrix has no clean mobile analog** — resolved with per-project cards + a "podle checku" toggle, but it is the screen most likely to need iteration once real violation volume is visible.
11. **RESOLVED (PM decision) — phone PWA IS in MVP 1, delivered the eco-standard way.** Phone-over-VPN install is in scope. Delivery = **nginx reverse proxy + cloudflared + CF Access** on `aid.aidlab.dev` (CF terminates TLS → valid cert → phone install works; CF Access Google OAuth gates access, allow `stancl.marek@gmail.com`). **The infra (nginx vhost + CF tunnel route + CF Access policy) is set up by the PM (Marek), not by the Cockpit build** — the build's only obligation is to work correctly behind that proxy. Consequent in-scope engineering tasks (no longer "open"): (a) `/ws` upgrade must traverse nginx (WS `Upgrade`/`Connection` headers) AND CF Access (the upgrade request must carry the `CF_Authorization` cookie — risk #5, now a build task with its own AC); (b) the app must not assume same-origin port 3911 — honour `X-Forwarded-*` / relative URLs so it works under `https://aid.aidlab.dev`; (c) PWA manifest `start_url`/scope must be path-correct behind the proxy. AC #9 updated accordingly. *(Was: feasibility fork. Now: decided — eco-standard nginx+CF.)*

12. **Node/Vite engine mismatch.** Host is Node v18.20.4; Vite 7 requires Node 20+, and `vite-plugin-pwa` tracks Vite 6/7. *Mitigation:* pin `vite@^6` + a Vite-6-compatible `vite-plugin-pwa`, or bump host/container to Node 20 LTS; the Docker image controls prod Node regardless. Verify `npm run build` on Node 18 before committing the toolchain (§7.6). *(Severity: low.)*

13. **Timing analytics are computable on a small minority of runs.** Step/dispatch durations and timeline-derived provenance are advertised first-class but exist on 3-11 of 26 timelines; building UI around them naively shows empty/null for most runs and erodes trust. *Mitigation (already in §5.1/§5.6):* file-mtime step timing is the documented PRIMARY, dispatch-gap the optional enhancement; render absent metrics with explicit "neměřeno na tomto běhu" states (the same pattern already used for `ac_verified_pct` N/A), never 0. *(Severity: medium.)*

14. **Provenance must not be re-derived from the timeline.** Sourcing provenance from timeline dispatch pairs would falsely flag ~23/26 runs "unverifiable" and discredit the dashboard. *Mitigation (§4.2):* read `compliance.json` `verifier_outputs.*_provenance` (exists and populated); timeline cross-check is corroboration only; `null` when no compliance.json. *(Severity: medium.)*

15. **Dependency-graph UI has no data in aid-orchestrator's queue.** `depends_on`/`plan_ref` are present in acta/krok/vulcan/sousto but absent in aid-orchestrator. *Mitigation (§4.6):* treat dependency edges as optional; render a flat priority list ("bez závislostí") when the field is absent; verify presence per queue before committing to a DAG view. *(Severity: low.)*

16. **Two headline scores could be improvised at implementation time** (`fsmAdherenceScore`, aggregate `health`), violating "flag, never fake" and producing a number the user cannot trust for question #2. *Mitigation:* both now have explicit formulas in §5.7, computed from already-inventoried signals (force overrides, precondition fails, gate first-pass rate, blocking compliance failures); `partial:true` when a component is missing, `null` (component breakdown shown) when none compute. *(Severity: low.)*

17. **Single parent-root watcher would walk ~1524 unrelated dirs.** Negative-only `ignored` globs let chokidar traverse sibling project source/caches and fire on unrelated git/build churn (inotify budget is fine — `max_user_watches=366939` — the cost is spurious events + CPU). *Mitigation (§7.3):* default to **one watcher per discovered `<proj>/.aid-o`** (option B), or `ignored`-as-function excluding any in-project path not under `.aid-o` (option A); re-scan on the 10-min TTL for new projects. *(Severity: medium.)*

18. **Container path mismatch on embedded absolute host paths.** Evidence JSONL/YAML embed `/opt/eco/projects/...` while the container sees `/projects/...`; without active normalization, run-dir matching (e.g. `R-ABSPATH-001`) mismatches. *Mitigation (§9.6):* central `pathmap.ts` (`containerToHost`/`hostToContainer`) derived from `AID_PROJECTS_ROOT` + `AID_HOST_ROOT`, never hardcoded; resolve container paths for reads, show host paths in UI; unit-test against a fixture with an embedded absolute host `evidence_dir`. *(Severity: medium.)*

19. **WebSocket adaptation is larger than "reuse".** The existing `AidWebSocket` uses envelope field `timestamp` (not `ts`), has no `projectId` and no per-project subscription filter, and replay is hardcoded to `pipeline.stage_log`. *Mitigation (§7.1/§7.6):* budget as **adapt + extend** — rename `timestamp`→`ts`, add the topic-AND-project filter, generalize the replay supplier to the merged activity ring buffer; add tests for project-filtered delivery. *(Severity: low.)*

20. **Raw contract type + non-existent salvage parsers.** `AidFsmState` lacks `ERROR` (reusing as-is silently breaks ERROR-state runs); `parseStepsTable`/`parseScope` do not exist in `markdown.ts` and cannot be "adapted". *Mitigation:* add `"ERROR"` to `AidFsmState` in the extend step (§7.1/§4.1); write steps-table/scope parsing net-new with its own tests (§7.1). *(Severity: low.)*

21. **Auditor report format varies across runs.** Score appears as frontmatter `overall_score`, `## Score: N/100` heading, or `**Total** N/100` table row; `_generated_by`/`classification` are conditional; `blocking_findings` is the only reliable field. *Mitigation (§4.3):* parse all three score shapes in order, `null` (label "—") if none match; require only `blocking_findings`; never treat missing auditor `_generated_by` as a fabrication flag. *(Severity: low.)*

---

## 13. Managerial-cockpit layer (Rev 3) — the `Brief` read-model + deterministic RISK

**Why this section exists (PM feedback, verbatim intent):** *"MVP1 is currently more 'technical run monitoring' than 'managerial project/plan cockpit'. A non-technical user still ends up studying the timeline, audit reports, and the compliance matrix. MVP1 must have a managerial BRIEF, a first-class PLAN view, a structured AUDIT SUMMARY, a BACKLOG DELTA, and lessons-per-plan — otherwise it's just an observability dashboard for a technician."*

This section adds **one read-model — `Brief`** (the manager's answer surface) and **one deterministic risk model — `Risk`** (the heart of the revision). It introduces **no new SOURCE OF TRUTH and performs no writes — it reads only existing v3 artifacts.** The `Brief`'s `risk`/`blockers`/`watchOuts`/`decisionsNeeded`/`nextUp` dimensions are pure projections over signals already inventoried in §4/§5 (compliance, gates, FSM, queue, timeline) — those add no new file reads at all. The managerial *projections* introduced alongside it (`PlanSummary`/`PlanDetail` §13.6, `AuditSummary`/`AuditTrend` §13.5, `BacklogDelta` §13.7, `LessonsView` §13.8) **do read existing v3 files** — the plan `.md`, `audit-report.md`, `backlog.md`, and `lessons-learned.md` — files that already exist on disk and that the §7.2 scanner **Tier-1 index must include** (dir listing + frontmatter + per-file mtime for `plans/*.md`, `work/evidence/*/audit-report.md`, `work/backlog.md`, `work/lessons-learned.md`), so the projections read parsed/cached data and the on-demand Tier-2 parse never widens the source set. The honest invariant is therefore: **no new source of truth, no writes, reads confined to existing v3 artifacts** — NOT the (false) "no new disk reads", since the audit/backlog/lessons/plan projections necessarily read those files. The `Brief` is a server-side **projection** over the existing scanner cache, rendered in three places by scope (D1).

**Locked decisions this section implements (do not re-litigate):**
- **D1 — three-tier brief.** One `Brief` shape, three scopes (`infra`/`project`/`plan`), rendered as: NEW **Screen G "Co potřebuju vědět"** (infra = the non-technical front door), the **first tab of Screen B** (project), and the **first tab of the Plan screen** (plan). Same component, different scope.
- **D2 — risk is a deterministic LEVEL, never a fake probability.** MVP1 computes `Risk.level` ∈ {nízké, střední, vysoké, neurčeno} + concrete reasons from countable signals only. `successProbability` is a `SuccessProbability` **envelope** whose binding MVP1 invariant is **`value === null && source === null`** (MF5); the UI renders "přesnější odhad přijde s agentem (MVP2)". The smart "what this means" narrative and the `value`/`source` fill (`source:'agent'`) are MVP2 (the LLM agent) — no contract churn.
- **Plan is first-class** (D4) with its own screen `/p/:project/plans/:planId` and `PlanSummary` read-model.
- **lastSeen is localStorage-only in MVP1** (keeps the server read-only/stateless); server-side multi-device lastSeen is MVP1.5.

### 13.1 The seven manager questions → `Brief` fields

The `Brief` (§7.5) answers seven questions. Each field is a **`BriefItem[]`** (except `risk`/`successProbability`), and each `BriefItem` carries a resolved `Explanation` (§6.4) so the answer is already in lidská řeč. The seven answer dimensions are built from §4/§5 signals that are already parsed/cached (compliance, gates, FSM, queue, timeline) — these add **no new file reads**; the plan/audit/backlog/lessons *projections* the brief surfaces (§13.5-§13.8) read existing v3 artifacts, which the scanner Tier-1 index already covers (§13 intro, SF2). No new source of truth, no writes.

| # | PM question (Czech) | `Brief` field | Source signals (already inventoried) |
|---|---|---|---|
| 1 | **Co se změnilo od poslední návštěvy** | `sinceLastSeen.items` + `.counts` | runs/transitions/violations/backlog whose underlying mtime/`ts` > client `since` (§13.3) |
| 2 | **Co blokuje postup** | `blockers` | open blocking `compliance.failures[].severity:"blocking"` (§4.5); `state==ESCALATION` (§4.1); `fsm_precondition_repeated_fail` (§4.1); stuck/stale run (§13.2 S5/S7); `done_phase==review` with no `pm_decision` while a merge gate is unmet |
| 3 | **Na co si dát pozor** | `watchOuts` | advisory `failures[].severity:"advisory"`; `force_override_count>0` (+SYSTEMATIC §4.5); retry hot-spots (≥3, only when count **known** §5.2); `fsm_branch_mismatch_detected`; stale run; auditor non-blocking findings (best-effort score / recommendations §4.3) |
| 4 | **Co bude následovat** | `nextUp` | `queue.yaml` next `status:queued` EPICs by priority (§4.6); runs in `READY`/`EXECUTE` (§4.1); plan progress `done_epics/total_epics` (§5.5) |
| 5 | **Jaká rozhodnutí jsou potřeba** | `decisionsNeeded` | runs `done_phase==review` awaiting `pm_decision`/merge (§4.0/§4.1); `state==ESCALATION` (needs a human); auditor `blocking_findings:true` (CP5 blocks MERGE §4.2) |
| 6 | **Odhad rizika** | `risk` | the deterministic §13.2 model (`Risk` level + reasons) |
| 7 | **Odhad pravděpodobnosti úspěchu** | `successProbability` | **`{value:null, source:null}` envelope in MVP1** (MF5 invariant) — UI renders "přesnější odhad přijde s agentem (MVP2)" (D2) |

**Sorting inside each list:** `blocking` severity first, then `warn`, then `info`; within a severity, newest `at` first. `decisionsNeeded` and `blockers` may overlap (e.g. an ESCALATION is both a blocker and a decision) — the **same `BriefItem.id`** is used in both lists so the FE can de-dupe a "this is the same thing" badge; this is intentional, not double counting.

**`Explanation` reuse (no new dictionary keys needed for the common cases).** Each `BriefItem.explanation` is produced by `explain()` over an existing §6.3 key — e.g. a blocking violation → `explain({kind:"severity", id:"blocking"})` or the check-specific `check:plan_ac_match`; an ESCALATION → `state:ESCALATION`; a force-override → `event:fsm_force_override`; a stale run → a small set of **new `kind:"concept"` keys** added to the dictionary (see §13.10). The brief therefore speaks the exact same Czech as Screen C/D — terminology cannot drift.

### 13.2 Deterministic RISK model (D2 — "flag, never fake")

`Risk` is computed from **countable, real signals only** — the same ones §5.7 already reads. It produces a **LEVEL + human reasons + confidence**, never a probability. The model is an explicit rule table with named thresholds, implementable as-is.

#### 13.2.1 Input signals (all already inventoried)

Computed over the **scope's run set** (one EPIC's latest run for plan/project rollups; the latest run of every active EPIC for infra). Each signal also records its **availability** (was the source present at all) — this drives the coverage rule.

| id | signal | source (§ref) | availability source |
|---|---|---|---|
| S1 | `openBlockingViolations` | count of latest-run `ComplianceFailure[]` (MF3) with `severity === 'blocking'` still unresolved (resolution = §5.7 rule: a LATER run of the same EPIC lacks a `ComplianceFailure` with that `.check`) | a `compliance.json` exists |
| S2 | `escalationCount` | `fsm-state.yaml escalation_count` (scalar) **and** any run currently `state==ESCALATION` | a parseable `fsm-state.yaml` exists |
| S3 | `forceOverrideCount` + `systematic` | `compliance.force_override_count` (+`force_override_reasons`); SYSTEMATIC per §4.5 (`avg>1`, `max>3`, `≥30%` forced, or low-quality reasons) | a `compliance.json` OR non-empty timeline exists |
| S4 | `gateFirstPassRate` | first-attempt gate pass rate over runs **with a `gates_report.json`** (§5.7 denominator) | ≥1 run has a `gates_report.json` |
| S5 | `repeatedPreconditionFails` | `fsm_precondition_repeated_fail` events, **or** `fsm_precondition_fail` with the same `(from,to,reason)` ≥2× (§5.2) | a non-empty per-run timeline exists |
| S6 | `stuckOrLoopingFsm` | long dwell in one state (`time_in_state_sec` over threshold, §5.1) **or** `fsm_increment_fail` repeated on the same `(step,reason)` (§5.2) | a non-empty per-run timeline OR `fsm-state.yaml` mtime exists |
| S7 | `staleRun` | an **active** run (`state ∈ {READY,EXECUTE,GATES,ESCALATION}`) whose `max(file mtime)` is older than `STALE_DAYS` (no activity) | the run dir + its file mtimes exist (always, for a v3 run) |
| S8 | `auditBlockingFindings` | auditor `blocking_findings:true` (§4.2/§4.3) on the latest run of the EPIC | an `audit-report.md` exists |

#### 13.2.2 Named thresholds (tunable constants — single source for the rule table)

```ts
const RISK = {
  STALE_DAYS: 3,                 // active run with no file activity ≥ 3 days → S7 fires
  STUCK_DWELL_SEC: 86400,        // ≥ 24h in one FSM state on an active run → S6 (dwell)
  REPEAT_FAIL_MIN: 2,            // same (from,to,reason) precondition fail ≥ 2× → S5
  INCREMENT_FAIL_MIN: 2,         // same (step,reason) increment fail ≥ 2× → S6 (loop)
  GATE_FIRST_PASS_WARN: 0.6,     // first-pass gate rate < 60% → střední contributor
  GATE_FIRST_PASS_BAD: 0.4,      // first-pass gate rate < 40% → vysoké contributor
  FORCE_OVERRIDE_WARN: 1,        // any force override → at least pozor watch-out + střední
  COVERAGE_MIN_SIGNALS: 2,       // < 2 of the level-relevant signals available → level = 'neurceno'
} as const;
```

#### 13.2.3 The rule table (level + precedence — implementable as-is)

Evaluate **top to bottom**; the **first matching tier sets the level** (precedence is the row order). Every firing signal also appends a `RiskReason` (so reasons accumulate even when a higher tier already set the level — the level is the max, the reasons are the union).

| Tier | Condition (any one true) | Sets level to | Reason text (lidská řeč) | `signal` |
|---|---|---|---|---|
| **T1 — vysoké** | `S1 openBlockingViolations > 0` (unresolved blocking compliance failure) | `vysoke` | "Blokující porušení pravidel není vyřešené - release je zastavený, dokud se to nenapraví nebo PM vědomě nepřepíše." | `open_blocking_violations` |
| **T1 — vysoké** | `S8 auditBlockingFindings == true` (auditor blocking, CP5 blocks merge) | `vysoke` | "Auditor našel kritický nález - merge je zablokovaný, dokud to PM neposoudí." | `audit_blocking_findings` |
| **T1 — vysoké** | `S3 systematic == true` (SYSTEMATIC force-override per §4.5) | `vysoke` | "Kontroly se obcházejí systematicky (ne jednorázově) - proces se přestává dodržovat." | `force_override_systematic` |
| **T1 — vysoké** | `S4 gateFirstPassRate < GATE_FIRST_PASS_BAD` (and ≥3 runs with gates) | `vysoke` | "Brány kvality padají na první pokus ve většině běhů - kód jde do kontrol nehotový." | `gate_first_pass_bad` |
| **T2 — střední** | `S2` any run `state==ESCALATION` | `stredni` | "Něco se zaseklo a eskalovalo - běh čeká na rozhodnutí nebo opravu člověkem." | `escalation_active` |
| **T2 — střední** | `S5 repeatedPreconditionFails` (same transition refused ≥2×) | `stredni` | "Stejný přechod stavového automatu opakovaně neprošel - to není náhoda, drhne tam podmínka." | `repeated_precondition_fail` |
| **T2 — střední** | `S6 stuckOrLoopingFsm` (dwell ≥24h or same step looping) | `stredni` | "Běh se točí na jednom místě (dlouho v jednom stavu nebo opakuje stejný krok) - postup vázne." | `stuck_or_looping` |
| **T2 — střední** | `S3 forceOverrideCount >= FORCE_OVERRIDE_WARN` (any bypass, not yet systematic) | `stredni` | "PM ručně obešel kontrolu - jednorázově, ale stojí to za pozornost." | `force_override` |
| **T2 — střední** | `S4 gateFirstPassRate < GATE_FIRST_PASS_WARN` (and ≥3 runs with gates) | `stredni` | "Brány kvality často padají na první pokus - víc oprav než obvykle." | `gate_first_pass_warn` |
| **T2 — střední** | `S7 staleRun` (active run idle ≥ STALE_DAYS) | `stredni` | "Rozdělaný běh se {staleDays} dní nehnul - buď visí, nebo se na něj zapomnělo." | `stale_run` |
| **T3 — nízké** | none of the above fired, **and** coverage rule satisfied | `nizke` | "Žádné blokující ani varovné signály - proces běží, jak má." | `no_adverse_signal` |

**Precedence in one sentence (the spec's required statement):** *any blocker → at least střední; an unresolved blocking compliance failure, a blocking audit finding, a SYSTEMATIC override, or a collapsing gate pass-rate → vysoké; otherwise střední if any caution signal fires; nízké only when nothing fires and there is enough data to say so.*

**`confidence` is resolved PER-SIGNAL, by signal class — not by a single ≥3-runs gate (SF3).** The signal that *set the level* (the highest-precedence firing signal, the one whose tier the level came from) decides confidence:

- **Authoritative single-file signals → `'high'` from ONE file.** A blocking signal that is a verdict on disk — `S1 openBlockingViolations > 0` (a present `compliance.json` carries a blocking `failures[]` entry) or `S8 auditBlockingFindings == true` (`audit-report.md` says `blocking_findings:true`), and likewise `S3 systematic` when a `compliance.json` is present — is **high confidence from a single run**, because the file *is* the authority; a second run cannot make "release is blocked" more true. These do **not** require ≥3 runs.
- **Rate / trend signals → `'high'` only with ≥3 runs.** A signal that is a *rate or aggregate over runs* — `S4 gateFirstPassRate` (first-pass gate rate) — is statistically meaningless on one or two runs, so it is `'high'` only when **≥3 runs with a `gates_report.json`** back it (matching the §13.2.3 tier-table guards "and ≥3 runs with gates" on the S4 rows) and `'low'` otherwise. The same ≥3-runs floor applies to any future adherence/rate signal.
- **Timeline-pattern signals → `'high'` when the pattern is itself ≥2 occurrences.** `S5 repeatedPreconditionFails` / `S6 stuckOrLoopingFsm` are already defined as "the same (from,to,reason)/(step,reason) ≥2×" (§13.2.2 `REPEAT_FAIL_MIN`/`INCREMENT_FAIL_MIN`), so a firing instance is by construction repeated and is `'high'` from that run's timeline; a single non-repeated fail does not fire them at all. `S2 escalation_active` and `S7 staleRun` are present-state facts → `'high'` when their source is parseable.

A `'low'` confidence **never** upgrades or downgrades the level — it only tells the UI to append "(odhad z mála dat)". When several signals fire across classes, `confidence` follows the **level-setting** signal (above); a low-confidence contributor reason does not drag a high-confidence blocking level down. **This resolves the apparent §13.2.3-vs-§13.2.5 contradiction:** the old blanket "≥3 runs for high" wrongly applied a rate-signal rule to an authoritative single-file blocking signal, so the `E-042-1_1` case (§13.2.5) was both `'high'` and single-run. Under the per-signal rule it is correctly `'high'` — its level was set by S1, an authoritative single-file signal, from its one `compliance.json`.

#### 13.2.4 Data-coverage rule (the "never fake low" guarantee)

> A missing signal is **never** counted as clean. If fewer than `COVERAGE_MIN_SIGNALS` (2) of the **level-relevant signals** are *available* (their source artifact exists), the level is **`neurceno`** with reason "Zatím je málo dat na odhad rizika - chybí výsledky bran, compliance nebo timeline." (`signal:"insufficient_coverage"`), `confidence:'low'`. **It is never `nizke` by absence.** This mirrors §5.7's "missing signal must NEVER be counted as 'clean'".

**"Level-relevant signals" — explicit enumeration (this is the set the `COVERAGE_MIN_SIGNALS` count is taken over):** `S1, S3` (compliance source), `S4` (gates source), `S5, S6` (timeline source), `S8` (audit source). **`S7` (staleRun) and `S2`'s `fsm-state.yaml`-presence are deliberately EXCLUDED from the count** — they are *always* available for any v3 run (S7's availability is literally "the run dir exists", §13.2.1), so counting them would let a thin run trivially reach ≥2 and falsely earn `nizke`. They still *contribute reasons* when they fire; they just don't count toward coverage.

**The floor is the primary guarantee (not the bare count):** `nizke` requires that **at least the compliance source (S1/S3) OR the gates source (S4)** was actually present and clean — a run we know nothing about cannot earn a green risk badge. So even if some always-on signal were miscounted, the floor still forbids a false green. The count rule and the floor are belt-and-suspenders, and the floor wins on conflict.

#### 13.2.5 Worked examples (first is a named real run; 2-3 are illustrative signal-sets)

- **`E-042-1_1 / R-E042-1`** (real, verified on disk): `compliance.failures = [{check:"verifier_provenance", severity:"blocking"}]`, `force_override_count:1`, `overall:"fail"`. → **T1 `vysoke`** (S1 fires). Reasons: open blocking violation + (accumulated) force-override watch. **`confidence:'high'` from this ONE run** — the level was set by S1, an authoritative single-file signal (the present `compliance.json` is the release verdict), so the per-signal rule (§13.2.3, SF3) makes it high without ≥3 runs; the legacy blanket "≥3 runs for high" would have wrongly flagged it `'low'`. This is the canonical "release blocked" case the manager must see at a glance, and the golden `'high'`-from-one-file confidence fixture.
- **A DONE+merged run** (illustrative signal-set: `state:DONE`, `done_phase:release`, `pm_decision:merge`, `gate_retries:0`, `escalation_count:0`, present+clean `compliance.json`): no tier fires, coverage satisfied (compliance + gates sources present and clean) → **T3 `nizke`**, reasons `[no_adverse_signal]`. **`confidence:'high'` because the level rests on the authoritative single-file clean-compliance floor** (§13.2.4) — a present `compliance.json` with no blocking failure is a per-run verdict, high from one run. (Were the *only* clean evidence the gate first-pass rate (S4) with <3 runs, the same `nizke` would carry `confidence:'low'` per the rate-signal rule, never a fake-confident green.)
- **A fresh run with only `fsm-state.yaml`** (illustrative signal-set: no gates/compliance/timeline/audit yet): of the level-relevant set (S1,S3,S4,S5,S6,S8) **zero** sources exist, so coverage < 2 **and** the floor (compliance OR gates present and clean) is not met → **`neurceno`**, `confidence:'low'` — never a fake green. (S7/`fsm-state.yaml`-presence don't count toward coverage, §13.2.4.)

### 13.3 `sinceLastSeen` — "co se změnilo od poslední návštěvy" (localStorage, MVP1)

The client stores a per-scope `lastSeen` ISO timestamp in **localStorage** (`aid.lastSeen.<scope-key>`, e.g. `aid.lastSeen.infra`, `aid.lastSeen.p:wan`, `aid.lastSeen.p:wan:P003`). It passes it as `?since=`. The server stays **stateless/read-only** (no server-side lastSeen in MVP1 — that is MVP1.5, §10). When `since` is absent (first visit, cleared storage) the server returns `sinceLastSeen.items = []` and `since:null`, and the UI shows "první návštěva - zatím není co porovnat" rather than flooding a first-timer with the whole history.

**What counts as "changed since `since`"** (all from already-read mtimes/`ts`, no new file reads):
- **new/changed runs** — a run dir whose `max(file mtime) > since`, or a `fsm-state.yaml` whose `state` changed (compare via mtime; MVP1 has no prior-state store, so a run-dir mtime past `since` = "changed");
- **new gate fails** — a `gates_report.json` with `overall:"fail"` (or any `gates.{name}.result:"fail"`) whose mtime `> since`;
- **new violations** — a `compliance.json` with a `failures[]` entry whose file mtime `> since`;
- **new backlog items** — a `backlog.md` row whose source mtime `> since` (coarse: backlog file mtime `> since` ⇒ surface the open-count delta);
- **state transitions** — `fsm_transition` timeline events with `ts > since`.

`counts` are the per-bucket totals; `items` are the individual `BriefItem`s (capped to the most recent 50 per scope to bound payload, with a `+N dalších` overflow note in `meta`). Because the comparison is mtime/`ts`-based and the server holds no prior snapshot, MVP1's server-side `sinceLastSeen` is a **"touched since you left"** view, not a field-level diff — honest and cheap. Field-level before/after diffs need a server-side snapshot store = MVP1.5.

**Backlog is the one signal with a FINER, client-owned snapshot (MF2).** The coarse "new backlog items" bullet above (server file-mtime ⇒ open-count delta) is all the **server** can honestly say, because `backlog.md` has no per-row timestamps. For the backlog *specifically*, the FE keeps a **second localStorage entry alongside the timestamp** — a full-row `BacklogSnapshot` (`aid.backlog.<scope-key>` → `{version:1, scopeKey, lastSeen, rows:{id,status,priority}[]}`, §7.5) keyed by the **same `scope-key`** as `aid.lastSeen.<scope-key>`. On load the FE diffs the current `GET /api/backlog` rows against that snapshot to get the row-level `added`/`closed`/`priorityChanged`/`statusChanged` (§13.7). The two localStorage families share the scope-key namespace and the `lastSeen` semantics, so "co se změnilo" stays one consistent model: the timestamp drives every *other* signal's "touched since" view; the row snapshot drives the *backlog's* finer field-level delta — both client-side, both MVP1.5-promotable to a server snapshot store with no contract change. On first visit (no `aid.backlog.<scope-key>` snapshot) the backlog delta is `firstVisit:true` → "bez porovnání - vše jako nové" (§13.7), the same honesty as `sinceLastSeen`'s "první návštěva".

### 13.4 Three scopes — how each `Brief` is computed

The same projection runs at three scopes; only the **run set** and **aggregation** differ.

**Infra scope (`GET /api/brief`) — Screen G "Co potřebuju vědět" (the front door).** Aggregates across **all 6 discovered projects** (denylist applied, §7.2). For each project it takes the **latest run of every active EPIC** plus the project's queue. It then:
1. Computes a per-project `Risk` (§13.2) and the per-project `BriefItem`s.
2. **Surfaces top blockers/decisions first, sorted by severity then recency**, across the whole infra — so the very first thing a non-technical user sees is "tyhle 2 věci čekají na tvé rozhodnutí" and "tohle blokuje postup", not a project grid. Each item is tagged with its `projectId` (and EPIC) so one tap deep-links to Screen B/C.
3. `Brief.risk` at infra scope = the **worst (max) level across projects** that have a determinable risk, with the contributing projects named in `reasons` (e.g. "vysoké kvůli wan (blokující porušení) a aid-orchestrator (systematický override)"); projects whose risk is `neurceno` are listed separately as "u {n} projektů zatím málo dat", and do **not** drag the infra level down to a false green.
4. `successProbability:{value:null, source:null}` — the MF5 envelope honoring the MVP1 invariant (D2).

**Project scope (`GET /api/brief/:projectId`) — Screen B first tab.** Same projection over **one project's** active EPICs + queue + that project's plans. Blockers/watch-outs/decisions are project-local; `risk` is the project `Risk`; `nextUp` includes the project's next queued EPICs and plan progress.

**Plan scope (`GET /api/brief/:projectId/:planId`) — Plan screen first tab.** Run set = the plan's member EPICs per the §13.6 four-tier rule (tiers 1-3: `plan_path` / `plan_ref` / id-derived; tier-4 orphans excluded — so aid-orchestrator's null-`plan_path` P046 members ARE in the set, MF1). Adds plan-specific framing: `nextUp` = remaining EPICs of the plan + `PlanSummary.progressPct`; the plan's **lessons** (§4.7 lessons-learned filtered by the plan's EPIC ids) are surfaced as `info` `BriefItem`s ("co jsme se na tomhle plánu naučili"). `risk` is computed over the plan's EPIC runs.

**One implementation, three callers.** Factor the projection as `buildBrief(runSet, scope, since)` in `packages/aid-server/src/brief/build-brief.ts`; the three routes differ only in how they assemble `runSet` from the scanner cache. `Risk` is a pure function `computeRisk(signals): Risk` in `brief/risk.ts` (unit-testable against the §13.2.5 fixtures — the `E-042-1_1` blocking case is the golden vysoké fixture; a clean merged run is the golden nízké; a `fsm-state.yaml`-only run is the golden neurceno). Both modules are pure projections over already-parsed §4/§5 signal data — they add **no new file reads and never write** (the §7.6 read-only grep test still passes unchanged). The plan/audit/backlog/lessons projections the brief *surfaces* do read their existing v3 files (§13.5-§13.8, SF2), but those are likewise read-only and Tier-1-indexed.

### 13.5 Structured AUDIT SUMMARY + score trend

> **Why:** "render the `audit-report.md` markdown" fails the managerial test — a non-technical PM should not have to read an auditor's markdown to learn *did it pass, how good was it, why that score, what now*. This subsection defines a structured `AuditSummary` (§7.5) + an `AuditTrend` series + a **deterministic** Czech headline, all assembled from the auditor's report (§4.3). Grounded on the three E-046 reports plus a 179-report cross-project sweep (`find /opt/eco/projects/*/.aid-o/work/evidence -name audit-report.md`).

#### 13.5.1 Disk reality (what is actually parseable — measured, not assumed)

The auditor report (§4.3) is **format-variable across run vintages**. Verified distribution over the audited runs in the 6 valid workspaces (broken/legacy/duplicate dirs excluded):

- **Score shape — three forms, ~equally common, plus a real "no score" bucket.** Measured: frontmatter `overall_score:` **25**, `## Score: N/100` heading **24**, `**Total**`/`**Overall**` table-row **47**, **no parseable score at all 27**. So roughly a quarter of audited runs have **no machine-readable score** — `overallScore: null` is the *normal* case, not an edge case. The three E-046 reports hit all three positive shapes: E-046-3_3 → frontmatter `overall_score: 84`; E-046-2_3 → `## Score: 95/100`; E-046-1_3 → `**Total** 89/100` table row.
- **`blocking_findings` — NOT universally present, and written in six textual forms.** Of 179 report files, **69 lack the literal token** (mostly broken/legacy/duplicate dirs, but also a handful of valid older runs and the two manual "Project Health Audit" reports at evidence roots). When present it appears as: a bare line `blocking_findings: false`; a `## blocking_findings: false` heading; bold `**blocking_findings: false**`; backtick-wrapped `` `blocking_findings: false` ``; inline-in-prose ("Žádné blocking findings. `blocking_findings: false`"); and **numeric** `blocking_findings: 0` (verified in `R-E027-1`/`R-E027-2`). The parser MUST recognize all six (`blockingFindingsSource` records which fired) and map `0`→false, `1`+→true. When even prose inference fails → `blockingFindings: null` + warning, **never assume false**.
- **Per-category score table — header is wildly variable** (50+ distinct header strings observed: `Category|Dimension|Area` × `Score|Score / 25` × optional `Max|Weight|Status|Notes|Prev|Delta|Trend`). The number column is sometimes `/100` (E-046-3_3: `92`, `100`, `72`, `80`), sometimes `/25` (E-046-1_3: `22/25`, `25/25`, …). Parse by **column-name detection**, not fixed position; keep the verbatim cell in `rawScore` and the detected denominator in `max`.
- **`_generated_by`/`_generated_at`/`classification` are conditional** (present on E-046-1_3, absent on E-046-2_3 and E-046-3_3) — already noted §4.3; the auditor report is **not** FSM-anti-fabrication-gated, so their absence is never a fabrication flag and never required for parsing.
- **Findings block — two layouts.** Either `### Critical|High|Medium|Low` section headers with `**severity:** Low` fields underneath (E-046-2_3, E-046-1_3), or inline `- Severity: Low` lines under a `### <Category>` heading (E-046-3_3). `effort` appears as `Effort: S`/`Effort: small`/`effort: small` and `auto_fixable` as `auto_fixable: true|false` — normalize `effort` to `S|M|L` and treat a missing `auto_fixable` as `null` (distinct from explicit `false`).
- **Auditor's own trend hint.** Many reports carry a `**Previous audit:** … Score: N/100` (or `Previous audit: … overall 93/100`, or `Previous audit: null (baseline)`) line. Capture it into `previousScoreHint` as a **corroborating** signal for the trend — it is the auditor's self-reported predecessor, NOT the source of truth for ordering (that is run `started_at`).

#### 13.5.2 `AuditSummary` derivation (per run)

Built from the run's `audit-report.md` via `parseMarkdownWithFrontmatter` (§7.1) + targeted regex passes:

1. **`present`** — `false` if no `audit-report.md` in the run dir → UI renders "auditor zatím na tomto běhu neběžel" (most in-flight and Fast-Mode runs); all other fields default empty/null. Never fabricate a summary for an unaudited run.
2. **`overallScore` + `scoreSource`** — try the three §4.3 shapes **in order** (frontmatter → heading → table row), first match wins, record which in `scoreSource`; `null`/`scoreSource:null` if none.
3. **`blockingFindings` + `blockingFindingsSource`** — the six-form parse above; the one field that gates CP5/merge.
4. **`categories[]`** — column-name-detected table parse; `score` normalized to /100 (a `/25` cell × 4), `rawScore` keeps the verbatim cell, `max` records the denominator, `status` only when a Status column exists.
5. **`countsBySeverity` + `topRisks`** — count findings per `severity`; `topRisks` = the Critical + High findings (severity-desc). On the E-046 sample all findings are Medium/Low so `topRisks` is `[]` and `countsBySeverity` is e.g. E-046-3_3 `{Critical:0,High:0,Medium:2,Low:4}` — a clean run shows zero top risks, which is itself the managerial signal.
6. **`topReasons[]`** — **why the score is what it is**, derived deterministically from the largest deductions. Prefer explicit deduction text when present (E-046-3_3 has `Documentation (score: 72, -28)`, `Process (score: 80, -20)`; E-046-2_3 has "Score deduction: -5 for AC6 test coverage gap"); else fall back to the lowest-scoring categories + highest-severity findings. Each reason is a short Czech clause naming the category and the count/severity that dragged it (see headline rules below).
7. **`nextSteps[]`** — from the `## Recommended Fixes` section (all three E-046 reports have one) plus each finding's `recommendation`+`effort`+`auto_fixable`. `rank` sorts by **severity-weight × effort-cheapness** (Critical=4…Low=1; S=3,M=2,L=1 → highest product first, so "high-severity & cheap" floats up); auto-fixable items are tagged so the UI can show "AID umí opravit sám".
8. **`autoFixableCount`** — findings with `autoFixable === true` (E-046-3_3: 3 of 6 are auto-fixable per its Recommended-Fixes table).
9. **`previousScoreHint`** — the auditor's self-reported "Previous audit … Score" line when present.
10. **`rawRelPath`** — relative path to `audit-report.md`; the raw markdown stays one click away in a drawer via `/file` (§7.4.1). Structured summary is the default view; raw is the escape hatch.

#### 13.5.3 Deterministic Czech headline (`headlineCs`) — assembled, not generated

A short "proč audit dopadl takhle" sentence built by **string templates over the structured fields** (no LLM — that is MVP2's narrative layer), reusing the §6 dictionary tone (lidská řeč, krátká pomlčka " - "). Rules, in priority:

- **No score, has blocking finding:** `"Auditor našel blokující nález - merge je zablokovaný, dokud to PM neposoudí. (Skóre auditor neuvedl.)"`
- **No score, no blocking finding:** `"Auditor neuvedl skóre, ale nenašel blokující nález ({C} nálezů celkem)."` — honest, never a fabricated number.
- **Has score, clean (no Critical/High):** `"Skóre {N}/100 - bez blokujících nálezů, jen {M} drobností ke zvážení."` → E-046-3_3: `"Skóre 84/100 - bez blokujících nálezů, jen 6 drobností ke zvážení."`
- **Has score, deductions known:** name the 1-2 biggest losers from `topReasons` → `"Skóre {N}/100 - strženo hlavně za {kategorie1} ({důvod1}){ a {kategorie2}}."` Worked example from E-046-3_3 real fields (Documentation -28 = 2 nálezy incl. CHANGELOG gap; Process -20): `"Skóre 84/100 - strženo hlavně za dokumentaci (chybí CHANGELOG, 2 nálezy) a proces (chybí pole v registru, 2 nálezy)."`
- **Has score, has Critical/High:** lead with the risk → `"Skóre {N}/100, ale {K} kritických/vysokých nálezů - {nejhorší oblast}. Než se mergne, koukni na ně."`
- **Trend suffix (optional):** if `previousScoreHint.score` or the EPIC `auditTrend.delta` is known, append `" Oproti minule {lepší|horší} o {Δ}."` Worked example for E-046-2_3 (95) → E-046-3_3 (84): `" Oproti minule horší o 11."` Omitted entirely when no prior scored point exists (never "0" or "stejně").

`headlineCs` is **always** safe to render: every branch is reachable from `present`/`overallScore`/`blockingFindings`/`countsBySeverity` alone, all of which are populated (or explicitly null) by §13.5.2.

#### 13.5.4 `AuditTrend` — score-over-time (honest gaps, real ordering)

- **Ordering key = run `started_at`** (§5.1 anchor family), NOT lexicographic run-id, NOT report mtime. Verified deterministic on the E-046 trio: `started_at` 14:04:10 (E-046-1_3) < 14:04:24 (E-046-2_3) < 14:04:37 (E-046-3_3), so the natural chart order is **89 → 95 → 84**. When `started_at` is unparseable for a run, fall back to run-dir mtime and flag the point (`warnings` on the enclosing summary).
- **EPIC scope** (`/api/audit-trend/:p/:e`, embedded in `EpicDetail.auditTrend`): one point per **run** of the EPIC that has an `audit-report.md`. **Plan scope** (`/api/audit-trend/:p/plan/:planId`, embedded in `PlanSummary.auditTrend`): one point per **EPIC** of the plan, using that EPIC's latest audited run (§5.4 run→EPIC = latest-run rule).
- **Gaps are gaps, never interpolated.** A run/EPIC with no parseable score is kept as a point with `score: null`; recharts renders it as a break in the line (`connectNulls={false}`), not a straight interpolation. `scoredPointCount` drives a "málo dat na trend (n=N)" state when `< 2`.
- **`delta`** = last scored − first scored (chronological); `null` when fewer than 2 scored points. On the E-046 EPIC: first scored 89, last scored 84 → `delta: -5`.

#### 13.5.5 Where it renders (reuses recharts; no new chart lib)

- **EPIC detail (Screen C)** — a new **"Audit" tab/panel** (alongside FSM/CP/Role/Časy/Dění): the `headlineCs` headline, the score as a big number with `scoreSource` provenance, `categories[]` as a small bar/row set, `countsBySeverity` chips, `topReasons` as a bullet list, `nextSteps` as a checklist (auto-fixable tagged), `previousScoreHint`/delta, and a **recharts line** of `EpicDetail.auditTrend` (gaps as breaks). A "Zobrazit původní report" link opens the raw-markdown drawer (`/file`). When `audit.present===false` → "auditor zatím na tomto běhu neběžel"; when `overallScore===null` but findings exist → show blocking + findings + counts, **no fabricated score**.
- **Plan detail (Rev-3 Plan screen, D1/D4)** — the `PlanSummary.auditTrend` recharts line (score per EPIC across the plan) sits with plan progress/AC%/lessons, giving the "is quality trending up or down across this plan" managerial read. One point per EPIC, gaps kept.
- **Brief integration (§13.1-§13.4, sibling-owned):** a **non-blocking** audit finding feeds `Brief.watchOuts` and a **blocking** one feeds `Brief.blockers`/`decisionsNeeded` as a `BriefItem` (severity `warn`/`blocking`), with `explanation` resolved via `explain()` (`role:auditor:*` keys, §6.3 D) so the managerial brief and the audit panel speak identical Czech. The `AuditSummary` is the source the Brief reads from for the audit dimension; the Brief does not re-parse `audit-report.md`.

#### 13.5.6 Honesty contract (the four task requirements, restated as rules)

1. **Unparseable score ⇒ no number.** `overallScore: null`, `headlineCs` takes a no-score branch, the UI shows `blockingFindings` + the finding list + `countsBySeverity` — never a fabricated or default score. (Roughly a quarter of real audited runs land here.)
2. **`blockingFindings` is the floor.** It is parsed from six on-disk forms and is the one field that always drives the CP5/merge surface; `null` only when even prose inference fails, and `null` is rendered as "nezjištěno", never as "false".
3. **Trend shows only real points.** Score gaps stay `null` (line breaks), ordered by `started_at`; `delta`/headline-suffix are emitted only with ≥2 real scored points.
4. **Headline is deterministic.** Assembled from structured fields by string templates; the LLM narrative is explicitly MVP2 (the `successProbability` envelope's `value:null` seam / `narrative`, §13.2/§10), and the static headline remains the permanent fallback and terminology source.

#### 13.5.7 Two distinct plan/project audit metrics — `boundaryAudit` vs `aggregateAudit` (SF4 / MF7)

A "plan audit" or "project audit" is **ambiguous** unless the spec names *which* number. Rev 4 defines **two distinct metrics**, both `AuditSummary`-shaped (and both honestly nullable), so each place picks the right one:

- **`boundaryAudit`** = the **single plan-boundary auditor run** — the `AuditSummary` (§13.5.2) of the **latest audited run of the plan's last EPIC** (the EPIC that triggered the §4.3 plan-boundary roles). It answers *"how did the auditor judge this plan at its close?"*. It is **one report**, with one `overallScore`/`headlineCs`/`blockingFindings`. `present:false` when the last EPIC has no `audit-report.md` (common: aid-orchestrator's P046 last EPIC `E-046-3_3` → `overall_score: 84`).
- **`aggregateAudit`** = an **aggregate across the audited member EPICs** (one latest-run score per EPIC, §5.4 run→EPIC = latest-run). It answers *"how good is quality across the whole plan/project, not just at the boundary?"*. **Definition (chosen): the `AuditSummary` of the EPIC whose latest-run score is the MEDIAN of the member EPICs' scored points** (ties → the later EPIC by `started_at`); its `overallScore` is therefore the **median score**, and its `headlineCs`/`topReasons`/`topRisks` are that real EPIC's — never a synthesized blend.
  - **Why median-EPIC, not arithmetic mean:** the score scale is variable-vintage and ordinal-ish (some reports `/100`, some categories `/25`, a quarter have *no* score at all, §13.5.1); a mean would (a) invent a number that matches no real report and (b) be dragged by a single outlier or a sparse 2-point set. The **median-EPIC** is a real, on-disk report whose `headlineCs`/`topRisks` the UI can show verbatim and link to — it satisfies "flag, never fake" (the displayed `overallScore` is an actual report's score, and the chosen EPIC is named), while still being a robust central tendency. The arithmetic mean of the scored points is carried alongside as `aggregateAudit.warnings`-adjacent context only if ever needed; the headline number is the median EPIC's.
  - **Honest sparse/empty handling (measured on disk):** `scoredEpicCount` (number of member EPICs with a parseable latest-run score) drives degradation. `0` scored EPICs → `aggregateAudit.present:true, overallScore:null, headlineCs` = "napříč plánem zatím není auditovaný EPIC se skóre" + a `warnings[]` note (the honest empty case — e.g. **sousto-na-miru has 0 audit-report.md across its entire workspace**). `1` scored EPIC → the median *is* that EPIC, but a `warnings[]` note "agregát z jediného auditu (n=1)" is added so the UI shows "1 audit" rather than implying a cross-EPIC read. `≥2` → the median is meaningful.
  - **Worked numbers (on disk, verified):** aid-orchestrator project scope — latest-run scores per audited EPIC are `E-036=92`, `E-042=92`, `E-046-1=89`, `E-046-2=95`, `E-046-3=84` (other EPICs `null`, kept out of the median) → median of `{84,89,92,92,95}` = **92** (the `E-036`-or-`E-042` summary, ties→later). The aid-orchestrator P046 plan — `{89,95,84}` → median **89** (the `E-046-1_3` summary), `boundaryAudit` = `E-046-3_3` = **84**. krok P013 plan — `{93,90,89,91,86}` → median **90** (`E-013-2_5`), a real five-EPIC plan aggregate.

The `auditTrend` (§13.5.4) is the **time-series companion** to `aggregateAudit` (one point per EPIC, gaps kept) — `aggregateAudit` is the single headline number, the trend is its shape over EPICs. **`boundaryAudit` is used on the Plan "Audit" tab's headline ("audit na konci plánu"); `aggregateAudit` + `auditTrend` are used for the cross-EPIC/-project read** (the project Audit tab, MF7, uses `aggregateAudit`). Both are produced by `audit/build-audit-summary.ts` (per-run) composed by `audit/build-aggregate-audit.ts` (the median-EPIC pick) — pure projections over the already-parsed audit reports, no new source of truth, no writes (SF2).

### 13.6 PLAN as a first-class entity (`PlanSummary`/`PlanDetail`, D4)

> **Why:** a manager thinks in *plans*, not runs. Rev 2 had no Plan entity — an EPIC's `plan_path`/`plan_ref` was just a string. Rev 3 materializes the Plan as a first-class read-model with its own screen `/p/:project/plans/:planId`, so "kde jsme s plánem P003" is one tap, not a mental rollup over EPIC rows.

A **Plan** is the group of EPICs that resolve to the same plan file. **Membership is decided by a single, explicit four-tier precedence (Rev 4 — resolves the Rev 3 self-contradiction where membership both "excludes every `plan_path:null` EPIC" *and* "groups aid-orchestrator's `plan_path:null` EPICs by filename").** For each EPIC, take the **first** tier that resolves, and record which tier fired in `membershipSource`:

| # | Tier | Source on disk | `membershipSource` | Strength |
|---|---|---|---|---|
| 1 | **`plan_path`** | `fsm-state.yaml plan_path` (the latest run's), when non-null | `'plan_path'` | authoritative |
| 2 | **`plan_ref`** | the EPIC's `tasks/*.md` frontmatter `plan_ref:` (resolved to its `P{NNN}` stem) | `'plan_ref'` | authoritative |
| 3 | **id-derived** | the EPIC id's plan number — `E-{NNN}-…` → `P{NNN}` — **matched against an existing `.aid-o/plans/P{NNN}-*.md` file** | `'derived'` | **official but weaker** (+ warning) |
| 4 | **orphan** | none of the above resolves (no `plan_path`, no `plan_ref`, **and no `P{NNN}` plan file exists**) | `'orphan'` | not a member |

- **The id-derived tier (3) is a real, official membership** — it is **NOT** "fast-mode excluded" and the EPIC **IS** listed in `PlanDetail.epics[]` / `PlanSummary.epicIds`. It is only *weaker*: it carries `membershipSource:'derived'` and a `warnings[]` note ("E-046-3_3 přiřazeno k P046 podle čísla EPICu, ne podle plan_path") so the grouping is **transparent, never hidden**. The deterministic Czech surface uses the new `concept:plan_membership_derived` key (§13.10).
- **Only tier 4 (orphan) is excluded** from membership and counted in `PlanDetail.orphanEpicCount`. The Rev-3 phrase "`plan_path:null` fast-mode EPICs are NOT members" is **wrong as written** and is replaced by this table: a `plan_path:null` EPIC is an orphan **only if it also has no `plan_ref` and no matching `P{NNN}` plan file**.
- **planId** = the plan-file stem (e.g. `P046` from `.aid-o/plans/P046-*.md`), regardless of which tier resolved it. The plan's `title`/`description` come from that file; if the file is missing for an id-derived candidate, the EPIC degrades to orphan (tier 4), never to a broken Plan screen.

> **The id-derivation is verified reliable on disk (Rev 4 grounding).** Across aid-orchestrator and acta, **every** EPIC whose `tasks/*.md` carries a `plan_ref` has the id-derived `P{NNN}` equal to that `plan_ref` stem — `E-019→P019`, `E-020→P020`, `E-021→P021`, `E-039→P039`, `E-042→P042`, `E-046→P046` (aid-orchestrator); `E-001→P001`, `E-003→P003`, `E-007→P007` (acta). The derivation never disagreed with an authoritative `plan_ref` in any sampled EPIC. The lone failure mode is **tier 4 by design**: `E-041` derives `P041` but there is **no `P041-*.md`** on disk (the plan file was never created), so `E-041` correctly resolves to *orphan*, not to a phantom plan.

> **aid-orchestrator is the canonical id-derivation / weaker-membership test fixture (disk reality, verified).** In aid-orchestrator's *own* workspace **`fsm-state.yaml plan_path` is `null` on every E-046 run** (tier 1 never fires). The membership tiers fall out of the **§5.2 scan contract** (`tasks/*.md` **excluding `archive/`** for the EPIC list + `work/evidence/*/` for the run dirs), NOT from frontmatter that the scanner cannot see: only `E-046-3_3` has an **active** `tasks/*.md` file (frontmatter `plan_ref: …/P046-…md`) → **tier 2 (`plan_ref`)** fires for it. `E-046-1_3` and `E-046-2_3` are surfaced into the EPIC list **by their `work/evidence/<epic>/` dirs** (§5.2 step 2); their task files exist **only under `tasks/archive/`** — which §5.2 explicitly excludes — so although those archived files **do** carry `plan_ref: …/P046-…md`, the scanner never reads them, and the two EPICs resolve at **tier 3 (id-derived → P046)**. (Were §5.2 ever to read archived frontmatter, they would resolve at tier 2 instead; the **member set and `planId` are identical either way** — only the `membershipSource` label differs — so the three-member P046 fixture is stable across that scan-rule choice.) Either way P046 is a real three-EPIC plan in the cockpit, exactly the multi-EPIC `89→95→84` trend in §13.5.4. (Only `E-038`/`E-040` carry a real `plan_path`, and both are single-EPIC P038/P040.) Two consequences the implementer must treat as first-class, not edge cases: **(a)** the flagship `89→95→84` audit-trend example (§13.5.4) is a **tier-2+tier-3 (`plan_ref`+id-derived)** plan, *not* a `plan_path`-membership plan — its membership is mixed-source and partly `'derived'` (because the contributing EPICs are evidence-only with archived tasks); **(b)** AC #16/#19's id-derived-membership path is the **primary** validation path for this project, so the Plan screen must be tested against aid-orchestrator's real null-`plan_path` data (P046 = three EPICs via tiers 2+3) rather than assuming `plan_path` membership exists.

**`PlanSummary` (list-row / brief-scope)** carries `epicIds`, `epicMembers[]` (each `{epicId, membershipSource}` per the §13.6 four-tier rule, so the weaker `'derived'` tier is visible at list altitude), `epicsTotal`/`epicsDone`, `progressPct` (`done_epics/total_epics*100`, §5.5), `acPct` (`Σpresent/Σac_count`, `null` when not measured), a thin `lessonsPreview[]` list, `auditTrend` (plan scope), `lastActivityAt`. **`PlanDetail` extends it** with the full Plan screen:

| Tab / panel | Field | Source |
|---|---|---|
| **Brief (tab 1)** | rendered from `GET /api/brief/:projectId/:planId` (`scope:'plan'`, §13.4) | the brief projection over plan members |
| Plán & EPICy | `epics[]` (status-weighted), `progressPct`, `acPct`, `orphanEpicCount`, `durationS` (`plan_duration_sec`, §5.1) | scanner cache |
| Audit | `boundaryAudit` (`AuditSummary` of the **plan-boundary auditor run** on the plan's last EPIC, §13.5) + `aggregateAudit` (`AuditSummary`-shaped **aggregate across the plan's EPIC audits**, SF4) + `auditTrend` (`scope:'plan'`, one point per EPIC) | `boundaryAudit` = latest audited run of the plan's last EPIC; `aggregateAudit` = median-score-EPIC's summary over all audited member EPICs |
| Backlog delta | `backlog` (current `BacklogItem[]` + `openCount`/`closedCount`, §13.7); the FE computes the `BacklogDelta` locally from its localStorage snapshot | `backlog.md` filtered to plan EPICs (server serves current rows only — delta is client-side, MF2) |
| Ponaučení | `lessons` (full `LessonsView`, §13.8) | `lessons-learned.md` filtered to plan EPICs |

`PlanSummary.lessonsPreview[]` (thin) and `PlanDetail.lessons` (full `LessonsView`) are **two altitudes of the same `lessons-learned.md` projection** — distinct field names so `PlanDetail extends PlanSummary` type-checks; the list-row shows a couple, the screen shows all. `plan_duration_sec` is `null` when no member run has a parseable anchor (§5.1). Every aggregation degradation lands in `PlanDetail.warnings`. **One implementation**: `buildPlan(planId, scope)` in `packages/aid-server/src/plan/build-plan.ts`, a pure projection over already-parsed EPIC/run data — no new disk reads, no writes.

### 13.7 BACKLOG DELTA (`BacklogDelta`) — "co přibylo / ubylo" — CLIENT-SIDE in MVP1 (MF2)

> **Why:** the raw backlog table (§4.6) is a technician's view. A manager wants the *delta*: what new improvement proposals appeared, what got closed, what changed priority, since I last looked. This is a read view over `backlog.md` — **backlog writes stay MVP1.5** (this never mutates anything).

**MF2 — the delta cannot be computed from a `since` timestamp alone, so MVP1 computes it CLIENT-SIDE.** `backlog.md` has **no per-row timestamps** (§4.6) and the server is **stateless/read-only** (it holds no prior snapshot), so a server `GET /api/backlog-delta?since=` *cannot* know which rows were added, closed, or re-prioritized — a bare `since` is not enough information. The honest design:

- **The server serves CURRENT rows only.** `GET /api/backlog?project=` returns the current `BacklogItem[]` and the absolute `openCount`/`closedCount` in `meta` (no diff, no `since` param). **The server-side `/api/backlog-delta?since=` endpoint is REMOVED from MVP1** — a real server-side field-level delta needs a snapshot store and is **MVP1.5** (§10).
- **The FE owns the snapshot.** On each visit the FE persists the full current row set as a `BacklogSnapshot` (`{ version:1, scopeKey, lastSeen, rows: {id,status,priority}[] }`, §7.5) in **localStorage**, keyed by `scopeKey` + `lastSeen` — the **same `scopeKey` mechanism as `Brief.sinceLastSeen`** (§13.3: `"project:wan"`, `"plan:wan/P003"`). Each scope keeps its own snapshot.
- **The FE diffs current-vs-snapshot LOCALLY** into `BacklogDelta` (a client-computed shape, §7.5):
  - **`added`** = current rows whose `id` is **absent** from the snapshot rows.
  - **`closed`** = rows whose status moved to a **closed status** (`approved`/`rejected`/`deferred`) when the snapshot had them open (`prevStatus` carries the old value).
  - **`priorityChanged`** = rows whose `priority` cell differs from the snapshot (`prevPriority` carries the old value).
  - **`statusChanged`** = rows whose status changed but did **not** close (e.g. `proposed`→`pending`).
  - Each item is tagged `changeSince: 'added'|'closed'|'priorityChanged'|'statusChanged'`; rows that match the snapshot are `'unchanged'` and not surfaced.
- **First visit (no snapshot)** ⇒ `firstVisit:true`, all four delta lists empty, `lastSeen:null`, and the UI renders **"bez porovnání - vše jako nové"** (a `warnings[]` note `"first visit - no snapshot, vše jako nové"` records it). Honest: a first-timer is never shown a fabricated diff, and rows are not falsely labelled "new" against an empty baseline — they are simply the current backlog with no comparison. Clearing localStorage returns to `firstVisit:true`.
- **`openCount`/`closedCount`** are still the **absolute** server counts (from `GET /api/backlog` meta): `openCount` = the `Active proposals: N` header count (§4.6); `closedCount` = `created (from counter) − open`, set `0` + a `warnings[]` note when the counter is stale/absent (§4.0 finding #6) and not derivable — **never a fabricated count**.

Surfaced as the Plan screen "Backlog" panel and the project-scope tile. **Consistency with `Brief.sinceLastSeen.counts.newBacklog` (§13.1 row 1 / §13.3):** the **server** can only emit a *coarse* `newBacklog` (it sees the backlog file mtime moved past `since`, not which rows — the same "touched since" granularity as the rest of `sinceLastSeen`); the **FE** then renders the *precise* counts (`added.length`/`closed.length`) from its row-level `BacklogDelta`. The FE-computed number is the authoritative display value and supersedes the coarse server count when a snapshot exists; on first visit (no snapshot) the FE shows the coarse server count with the "bez porovnání" caveat. Both are driven by the same client `lastSeen`/snapshot model, so the two stay consistent **without** a server snapshot store. **One implementation**: a pure client function `buildBacklogDelta(currentRows, snapshot): BacklogDelta` in `packages/aid-gui/src/lib/backlog-delta.ts` (FE, unit-testable on fixtures) — there is **no** `aid-server/src/backlog/build-delta.ts` server module in MVP1 (the server only serves current rows; the FE computes the diff). The server stays read-only and writes nothing (the §7.6 grep test passes unchanged). Server-side field-level delta + a snapshot store = MVP1.5.

### 13.8 LESSONS-PER-PLAN (`LessonsView`)

> **Why:** lessons-learned are a per-project flat file (§4.7) today; a plan-scoped view ("co jsme se na tomhle plánu naučili") is the managerial read. Read-only projection — no new disk reads beyond the already-parsed `lessons-learned.md`.

`LessonsView` (§7.5) projects `work/lessons-learned.md` (§4.7) at three scopes:

- **plan** — lessons whose `Context(epic_id)` cell ∈ the plan's member EPICs.
- **project** — all lessons in that project's file.
- **infra** — all projects' lessons merged (for an optional Screen G cross-infra "co jsme se naučili" section).

Each `LessonEntry` carries `date` (ISO when parseable, else the raw cell, else `null`), `lesson`, `epicId` (the Context cell, `null` when absent), and `kind`: rows under `## Known Gotchas` → `kind:'gotcha'`, the main `| Date | Lesson | Context |` table → `kind:'lesson'` (§4.7). Entries sort chronological-desc when the date parses, else file order. **Absent or malformed file ⇒ `entries:[]` + a `warnings[]` note, never a throw** (the §7.6 never-throw parser rule). Endpoint `GET /api/lessons?project=&plan=` (scope inferred: both params → plan, project only → project, neither → infra). Surfaced as the Plan screen "Ponaučení" tab and fed into the plan-scope `Brief` as `info` `BriefItem`s (§13.4 plan scope).

### 13.9 The two SEAMS — `TimeSource` (seam only) and Memory taxonomy (types now, read MVP2)

Both are **locked-decision seams**: the contract reserves the shape now so the future feature lands with zero churn, but **neither is an MVP1 feature**.

**`TimeSource` — architecture seam ONLY, NOT an MVP1 feature.** `MetricSet.timeBy: TimeSource[]` (§7.5) is the slot for measured time **per actor** (`ai` / `controller` / `user` / `dev`). The honest MVP1 behaviour:

- `user` and `dev` → `{ durationS: null, source: null }` — i.e. **"neměřeno"**. MVP1 measures no human/dev time; the UI renders "neměřeno" for any `durationS: null`, never a fabricated number.
- `ai` and `controller` → MAY carry a best-effort `durationS` from the **existing §5.1 timeline numbers** (`source: 'timeline'`) — this is the *same* data the run already exposes, just re-projected by actor; it adds no new measurement.
- **Future fill (MVP2+):** a WakaTime import or webhook populates `user`/`dev` with `source: 'wakatime'`. Because `TimeSource` is already in `MetricSet`, that lands with **no contract change** and the EPIC/run "kdo strávil kolik" breakdown appears the moment a source exists.

This explicitly **does not add an MVP1 capability** — it is the documented insertion point (the seam), consistent with the locked decision "TimeSource = architecture SEAM only; MVP1 shows neměřeno".

**Memory taxonomy — types in the contract now; READING is MVP2.** `MemoryQuery` / `MemoryEntry` / `MemoryResult` (§7.5) define how the Cockpit will read AID's architectural memory — Qdrant `clavi_facts_{tenant}` via the **read-only** `vulcan-memory` MCP (§4.7). The taxonomy is fixed **now**:

- `scope: 'plan' | 'project' | 'global'` — the memory's altitude.
- `projectId` / `planId` — required when `scope` is `project` / `plan` respectively.
- `type: 'brain' | 'ideas' | 'reflection' | 'skills' | 'projects'` — the vulcan-memory type facet (the same taxonomy the global memory rules use).
- `createdDuringRun` — a `run_id` filter, the run-scoped facet ("co se naučilo během tohoto běhu"), pre-positioned so future writes can tag it.

**MVP1 ships ONLY the types + a stub endpoint.** `GET /api/memory` returns `{ available: false, reason: "MVP2", entries: [] }` and **never touches Qdrant** (no MCP call, no network) — it is a typed placeholder so the FE can wire the future "Paměť" view against a stable contract and the read-only invariant is trivially upheld. **MVP2** wires `routes/memory.ts` to the read-only MCP query and builds the Paměť view (§10 MVP2). Defining the taxonomy now is the seam; reading the data is deferred.

### 13.10 New dictionary keys (additive to §6.3)

The brief reuses existing §6.3 keys for the common cases (severities, FSM states, force-override, transitions). It needs a small set of **new `kind:"concept"` keys** for the managerial signals that have no event/state equivalent — added to `dictionary.cs.ts` (and therefore to `/help` automatically, §6.4):

```
concept:risk:nizke        → "Riziko nízké - žádné blokující ani varovné signály." / proslo
concept:risk:stredni      → "Riziko střední - něco drhne (override, opakované selhání, eskalace nebo zaseknutí)." / pozor
concept:risk:vysoke       → "Riziko vysoké - blokující porušení, kritický nález auditu, systematické obcházení kontrol nebo padající brány." / zablokovano
concept:risk:neurceno     → "Riziko zatím nelze určit - málo dat (chybí výsledky bran, compliance nebo timeline)." / ceka
concept:stale_run         → "Rozdělaný běh se {staleDays} dní nehnul - visí, nebo se na něj zapomnělo." / pozor
concept:stuck_or_looping  → "Běh se točí na jednom místě - dlouho v jednom stavu nebo opakuje stejný krok." / pozor
concept:decision_needed   → "Tady je potřeba tvé rozhodnutí (merge, eskalace nebo blokující nález auditu)." / eskalace
concept:success_probability_mvp2 → "Přesnější odhad pravděpodobnosti úspěchu přijde s agentem (MVP2)." / ceka
concept:since_first_visit → "První návštěva - zatím není co porovnat." / ceka
concept:plan_membership_derived → "EPIC přiřazen k plánu podle čísla (E-{nnn} → P{nnn}), ne podle plan_path - slabší, ale oficiální zařazení." / pozor
concept:aggregate_audit_sparse → "Souhrnný audit z {scoredEpicCount} EPIC - málo auditů na spolehlivý průměr." / ceka
```

These follow the §6.1 template/status contract exactly (status drives colour via §6.2), so the brief, Screen G, and Help all render identical Czech.

### 13.11 MVP1 acceptance criteria — managerial layer (additive to §10)

12. `GET /api/brief` returns a `Brief` with `scope:"infra"`, `successProbability:{value:null, source:null}` (MF5 envelope), and blockers/decisions sorted blocking-first across all 6 projects; Screen G renders them as the front door (not a project grid).
13. `computeRisk` returns **`vysoke`** for the real `E-042-1_1 / R-E042-1` fixture (open blocking `verifier_provenance` violation), **`nizke`** for a clean merged run, and **`neurceno`** (never `nizke`) for a run that has only `fsm-state.yaml` — the data-coverage rule is unit-tested.
14. **`successProbability` envelope holds the MVP1 invariant (MF5).** `successProbability.value === null && successProbability.source === null` on every scope, and the UI renders "přesnější odhad přijde s agentem (MVP2)" — there is no fabricated probability anywhere (D2). A unit test asserts the invariant (`value===null && source===null`) on every brief MVP1 produces.
15. `sinceLastSeen` uses the client `?since=` (localStorage) only; with no `since` the server returns `items:[]`/`since:null` and the UI shows "první návštěva"; the server writes nothing (read-only grep test still passes).
16. **Plan membership follows the four-tier precedence (MF1).** The Plan screen (`/api/plans/:projectId/:planId` + `/api/brief/:projectId/:planId`) shows EPIC members, `progressPct`, `acPct` (or "N/A — fast mode"), lessons-per-plan, and the plan-scoped brief. Each member carries a `membershipSource` resolved by §13.6: `plan_path` → `plan_ref` → id-derived (`E-{NNN}`→`P{NNN}` matched to a real `P{NNN}-*.md`) → orphan. **An id-derived EPIC IS a member** (tagged `membershipSource:'derived'` + a warning), **not** an orphan and **not** fast-mode-excluded; **only true orphans** (no `plan_path`, no `plan_ref`, no matching plan file) are excluded and counted in `orphanEpicCount`. Unit-tested on aid-orchestrator real data: **P046 has three members** — `E-046-3_3` resolves at tier-2 `plan_ref` (its **active** `tasks/*.md` carries `plan_ref:` → P046), while `E-046-1_3`/`E-046-2_3` resolve at tier-3 `derived` (surfaced into the EPIC list by their `work/evidence/` dirs; their `plan_ref`-bearing task files live **only under `tasks/archive/`**, which §5.2 excludes from the scan, so the scanner falls to id-derivation) — all three `plan_path:null`; `E-041` (derives `P041`, no `P041-*.md`) resolves to **orphan**.
17. **Audit summary never fabricates a score.** For a run whose `audit-report.md` has no parseable score, `AuditSummary.overallScore` is `null` (`scoreSource:null`), `headlineCs` takes a no-score branch, and the UI shows `blockingFindings` + the finding list + `countsBySeverity` — never a fabricated or zeroed score. `blockingFindings` is parsed from the six on-disk forms (§13.5.1), and rendered "nezjištěno" (never "false") when `null`. Unit-tested against the three E-046 reports (frontmatter `84`, heading `95`, table `89`) **and** a real no-score report.
18. **Audit trend keeps real gaps, ordered by `started_at`.** `AuditTrend.points` are chronological by run `started_at` (89 → 95 → 84 on the E-046 trio), score-less runs kept as `score:null` (a line break, not interpolation); `delta` is `null` until ≥2 scored points (then `-5` on the E-046 EPIC). The project-scope trend (`/api/audit-trend/:projectId`, MF7) is one point per audited EPIC, same gap rules.
19. **Plan screen aggregates correctly under the four-tier rule.** `GET /api/plans/:projectId/:planId` returns a `PlanDetail` whose `epics[]` are exactly the tier-1-to-3 members (tier-4 orphans excluded, counted in `orphanEpicCount`), with `epicMembers[].membershipSource` and `membershipMixed` set; `progressPct`/`acPct`/`durationS` roll up per §5.4/§5.5 (`acPct:null` → "N/A — fast mode", never 0%). A project whose EPICs have no `plan_path`/`plan_ref` but a matching `P{NNN}-*.md` still renders a non-empty Plan via the id-derived tier with a `warnings[]` note (verified on aid-orchestrator P046, three members across `plan_ref`+`derived` tiers) — never an empty screen. `PlanDetail.boundaryAudit` is the last EPIC's auditor run (P046 → `E-046-3_3` = 84) and `aggregateAudit.overallScore` is the median member score (P046 `{89,95,84}` → 89), distinct numbers (SF4).
20. **Backlog delta is computed CLIENT-SIDE off a localStorage snapshot (MF2).** The server exposes only `GET /api/backlog?project=` (current `BacklogItem[]` + absolute `openCount`/`closedCount`); there is **no** `/api/backlog-delta` endpoint in MVP1. The FE persists a `BacklogSnapshot` (`{id,status,priority}[]` keyed by `scopeKey`+`lastSeen`, §13.3/§7.5) and `buildBacklogDelta(currentRows, snapshot)` diffs current-vs-snapshot into `added`/`closed`/`priorityChanged`/`statusChanged`; unit-tested on fixtures (a row gone-to-`approved` → `closed`; a new id → `added`; a changed Priority cell → `priorityChanged`). With **no** snapshot (first visit / cleared storage) it returns `firstVisit:true`, the four lists empty, and the UI renders "bez porovnání - vše jako nové". `closedCount` is `0` + a warning (never fabricated) when the counter is stale. The server writes nothing (read-only grep test passes).
21. **Lessons-per-plan filters correctly and never throws.** `GET /api/lessons?project=&plan=` returns only lessons whose `Context(epic_id)` ∈ the plan's EPICs (plan scope), and an absent/malformed `lessons-learned.md` yields `entries:[]` + a warning, not a crash (vitest green on a malformed fixture).
22. **The two seams ship as seams, not features.** `MetricSet.timeBy` returns `user`/`dev` as `durationS:null, source:null` ("neměřeno") on every MVP1 run (no human/dev time is measured); `GET /api/memory` returns `{ available:false, reason:"MVP2", entries:[] }` and makes **no** Qdrant/MCP call (verified by the read-only invariant test + a unit test asserting the stub response).
23. **Project-scope audit is first-class (MF7).** Screen B has an `Audit` tab fed by `GET /api/audit-summary/:projectId` (project `aggregateAudit` = the median-EPIC `AuditSummary`, §13.5.7) + `GET /api/audit-trend/:projectId` (one point per audited EPIC). `aggregateAudit.medianEpicId` names a real on-disk report and `overallScore` equals its score (never a synthesized mean); `scoredEpicCount===0` → `overallScore:null` + a warning (verified on **sousto-na-miru: 0 audit-report.md** → empty-but-honest), `===1` → an "n=1" warning. Unit-tested on aid-orchestrator (`{92,92,89,95,84}` → median 92) and that `aggregateAudit` ≠ `boundaryAudit` for P046 (89 vs 84).
24. **Plan delivery & simplifier are first-class (MF6).** The Plan screen has a "Dodávka & zjednodušení" tab rendering `PlanDetail.deliveryReport` (`ReporterDelivery`) and `simplifierSummary` (`SimplifierSummary`). The Reporter panel shows `outcome` + `summaryCs` + the `testEvidence[]` list, and a test-evidence file that is **missing on disk** renders an honest "chybí na disku" warning row (`exists:false`), never silently dropped (§4.3 anti-fabrication); the Simplifier panel lists `proposals[]` with `disposition`/`effort`. `present:false` on either → "Reporter/Simplifier zatím neběžel" (no fabricated outcome); both panels are read-only in MVP1. Unit-tested: a plan with no `…-delivery.md`/`simplifier-report.md` yields `present:false` on both (vitest green), and a delivery report citing a non-existent `_test_evidence` file flags `exists:false`.

### 13.12 Cross-project Plan Outcome Analytics (Rev 4.1 MVP1 addendum)

> **Why:** the existing Cockpit model can explain one project, plan, EPIC or run, and `aid-diagnostic.sh` can summarize selected run artifacts. Neither answers the portfolio-level question "jak dopadly všechny plány napříč AID projekty, kde byly faily/retry/eskalace a kde data nestačí?" This read-model closes that gap without adding a new source of truth.

**Source and ownership.** `packages/aid-server/src/plan/build-plan-outcomes.ts` is a pure projection over the same scanner-cache `PlanDetail`, `RunDetail`, checkpoints, timeline, gates and compliance objects used elsewhere. It performs no new disk writes and MUST NOT execute the shell diagnostic on an HTTP request. `plugins/aid-orchestrator/scripts/aid-diagnostic.sh` remains a regression oracle for overlapping fixture fields (gate/compliance verdicts and normalized failure reasons), not the backend implementation.

**Outcome classification (binding precedence):**

1. `failed` — explicit terminal evidence exists: a latest member run is `ERROR`, its final gate fails, compliance is `fail`, or the plan-boundary Reporter says `fail`.
2. `passed` — every member's latest run is v3 `DONE`, AC verification is 100%, final gates pass, and compliance passes. Missing proof can never pass.
3. `in_progress` — no explicit failure exists and at least one latest member run is non-terminal (`READY|EXECUTE|GATES|ESCALATION`). Escalations remain separately counted.
4. `partial` — no run is active or explicitly failed, at least one member qualifies as passed, and another member is known incomplete.
5. `unverifiable` — the remaining cases where legacy/stub/missing artifacts or unknown required proofs prevent a defensible result. This is not failure and not success.

**Aggregates.** Each `PlanOutcomeSummary` includes member/run totals, failed runs, final gate failures and gate retries, known CP repeat total plus `unknownCheckpoints`, FSM failure buckets (`precondition`, `increment`, `doneAdvance`, `other`), escalations, force overrides, compliance pass/fail/unknown counts, normalized top failure reasons, timestamps, `dataPartial` and warnings. If any relevant CP repeat or required proof is missing, the unknown count/warning is visible; the projection MUST NOT fold it into zero. Plans sort attention-first (`failed`, `partial`, `in_progress`, `unverifiable`, `passed`) then newest activity.

**API.** `GET /api/analytics/plans?project=&outcome=&since=` returns `PlanOutcomeAnalytics`. `project` and `outcome` are exact filters. `since` is an ISO-8601 lower bound on `lastActivityAt`. Invalid enum/timestamp returns the standard 400 envelope; unknown explicit project returns 404. `totals` reconcile exactly to the returned filtered rows and `partialProjects` is a sorted unique list.

**UI.** Screen A `/prehled` adds a dense, responsive "Výsledky plánů" section below project tiles: total counters, project/outcome filters, one linked row/card per plan, and an icon button with tooltip "Exportovat JSON". Desktop uses a table; mobile uses stacked rows. JSON export contains the currently filtered response and active filters, is produced client-side with `Blob`, and writes nothing to the server. Unknown values display `?`/"nelze ověřit", never `0`/green.

**MVP1 acceptance criterion (additive):**

25. `GET /api/analytics/plans` returns every discoverable tier-1-to-3 plan with exactly one of the five outcomes and aggregate totals that reconcile to rows. Unit tests cover every classification branch, filters and invalid filters, script-oracle parity for overlapping fields, and a fixture with known+unknown CP repeats proving unknowns are not zeroed. `/prehled` renders totals, plan links, project/outcome filters and filtered JSON export on desktop/mobile; a legacy/stub-only plan is visibly `unverifiable`/"nelze ověřit" with warnings, never passed. The E2E suite validates the API and downloaded JSON against the real six-project tree.

---

## 12. Audit response - round 1

Resolution of the external design audit (Rev 2). Each finding → one-line resolution + section(s) changed.

| Finding | Resolution | Sections changed |
|---|---|---|
| **MF1** | Headline scores/timings/provenance/retry counts made truly nullable: new `Score` envelope; `Project.health` nullable blend; `Checkpoint.repeatCount\|null` + `repeatSource`; `MetricSet` timing fields `\| null` + `stepTimingSource`/`partial`/`warnings` (gate counts kept non-null); added the binding nullability convention note. | §7.5 (types + notes); ripple §5.7, §10 |
| **MF2** | Data thresholds + per-term **available-runs denominators** + confidence rules for both headline scores; missing signal never counted as "clean"; below-threshold ⇒ component breakdown + "málo dat (n=N)"; `health` resolution-source for `openViolations` stated. | §5.7 |
| **MF3** | REST polling fallback every 5s with banner "živé spojení nejede - aktualizuji po 5 s" when WS not OPEN; "last known" = in-memory only (never SW/localStorage), timestamped, else "bez dat / offline"; `/api` stays `NetworkOnly`; AC #9 updated. | §7.3, §9.3, §9.5, §10 AC #9 |
| **MF4** | Watcher `depth: 5` → **7**; noted gates/, reporter/, steps/ live at depth 6 and must be inside the watched depth; §3 and §7.3 now agree on 7. | §7.3 (vs §3 diagram) |
| **MF5** | **Mechanism REFINED, not applied verbatim** (see note below): per-checkpoint retry sourcing — CP1 file inventory; CP2/3/4 timeline-or-`null`; gates from `attempts`; hot-spot flag only when count known. | §5.2, §7.5 `Checkpoint`, §8.2 Screen C note |
| **MF6** | AC #4 reworded: activity stream from per-run timelines; root `work/timeline.jsonl` read ONLY for `focus:cp1` dispatch enrichment — consistent with §4.0 finding #1. | §10 AC #4 |
| **MF7** | (a) Unified explanation model: one `DictionaryEntry` (static) + one runtime `Explanation`; `explain()` resolves entry → runtime; `ExplanationRefs` → `DictionaryEntry['id'][]`. (b) `STATUS` (§6.2) made the single canonical table + added `necinne` (8 tokens); §8.5 reuses it (separate hex table deleted). | §6.2, §6.4, §7.5, §8.2 Help, §8.4, §8.5, §10 |
| **MF8** | `/file` security specified concretely: resolution root + subdirs, artifact allow-list, `realpath`+`startsWith` (CWE-22), reject `..`/absolute/symlink (lstat→403), 1 MB cap (413/414), via §9.6 `pathmap`; required unit test added. | §7.4.1 (new), §7.1, §9.6 |
| **SF1** | Read-only grep broadened (writeFile/append/mkdir/rm/rmdir/unlink/rename/createWriteStream/`.open(...,'a'\|'w')`), scoped to `src/` only, MVP 1.5 write module allow-listed. | §7.6 |
| **SF2** | PWA manifest theme/background changed to light (`#f8fafc`/`#0284c7`) to match §8.5 light theme; PNG-icon build task kept. | §9.3 |
| **SF3** | RunDetail LRU invalidation: watcher events PRIMARY, max-file-mtime backstop (not dir mtime alone). | §7.2 |
| **SF4** | MVP-1 gate `MetricSet`/`RunDetail` fields named; non-gating fields (per-step/dispatch durations, CP2/3/4 retry-when-no-events) ship as `null`. | §10 (under MVP 1) |
| **SF5** | Risk #4 rewritten: phone PWA IS MVP 1 via eco-standard nginx+cloudflared+CF Access (PM-provisioned); residual build risk = `/ws`-through-CF + relative-URL/proxy correctness (xref risk #5), mitigated by ACs + §MF3 polling fallback. | §11 risk #4 |
| **Q1** | CP6 = Fast-Mode-only (`/aid-do`) advisory checkpoint, NOT reporter; reporter is a plan-boundary role; strip shows CP1-CP5 (CP6 greyed/omitted on `/aid-run`); `cp:CP6` dictionary entry corrected. | §4.2, §6.3, §8.2 |
| **Q2** | Min evidence thresholds — answered by MF2. | §5.7 |
| **Q3** | Poll on WS fail — YES, answered by MF3. | §7.3, §10 AC #9 |
| **Q4** | Last-known persistence — in-memory only, never SW/localStorage, answered by MF3. | §9.3 |
| **Q5** | `/file` rules — answered by MF8. | §7.4.1 |

> **Note on MF5 (mechanism refined, not applied verbatim):** the audit proposed file-inventory retry counting. That works **only for CP1** (its `cp1-review/rereview/reverify`/`pass{N}` files are not overwritten). For **CP2/CP3/CP4** the `verifier-output-*.md` files are **overwritten on retry** (no `-r2` suffix on disk), so a file count cannot show retries — those use **timeline `verifier_dispatch_start` events or `null`** (never 0). Gates stay on `gates_report.json attempts`. This per-checkpoint split is the honest grounding the audit's intent demanded.

---

## 12.5 Rev 3 change summary (managerial-cockpit layer)

Rev 3 is additive — it does not re-open any Rev 2 audit finding. What it adds:

> **Baseline note.** This table is the **Rev 3** change record and is preserved as history. Where Rev 4 (audit round 2) supersedes a Rev 3 shape — the `successProbability` envelope (MF5), the client-side backlog delta (MF2), and the structured `ComplianceFailure` (MF3) — the **current contract is §14**, not this table. The Rev 3 wording below (e.g. "`successProbability` always `null`", "backlog delta") stays substantively true under Rev 4 (the envelope's `value` IS always `null` in MVP1) but is intentionally not rewritten here.

| Item | What | Sections |
|---|---|---|
| **D1 — three-tier `Brief`** | One `Brief` read-model (infra / project / plan scope) answering the 7 PM questions; rendered as new Screen G "Co potřebuju vědět" (front door), Screen B tab 1, Plan screen tab 1. | §13.1, §13.4, §7.5 (`Brief`/`BriefItem`) |
| **D2 — deterministic RISK** | `Risk` = level (nízké/střední/vysoké/neurčeno) + human reasons + confidence, from countable signals only; explicit rule table with named thresholds; `successProbability` is a `SuccessProbability` envelope with the binding MVP1 invariant `value===null && source===null` (MF5; "flag, never fake"). | §13.2, §7.5 (`Risk`/`RiskReason`/`SuccessProbability`) |
| **`sinceLastSeen`** | "Co se změnilo od poslední návštěvy" via client localStorage `?since=` only; server stays read-only/stateless; "touched-since" granularity (field-level diff = MVP1.5). | §13.3, §7.5 (`Brief.sinceLastSeen`) |
| **Plan as first-class (D4)** | `PlanSummary` (list-row) + `PlanDetail` (full Plan screen: brief tab, EPIC members, progress, AC%, `plan_duration_sec`, audit summary + trend, backlog delta, lessons); Plan screen `/p/:project/plans/:planId`. | §13.6, §7.5 (`PlanSummary`/`PlanDetail`), §7.4 |
| **Audit summary + trend** | Structured `AuditSummary` (best-effort score, always-present `blockingFindings`, per-category scores, top reasons/risks, ranked next steps, auto-fixable count) + `AuditTrend` score-over-time (real points only, ordered by `started_at`) + a deterministic Czech headline — replaces "render the audit-report.md". | §13.5, §7.5 (`AuditSummary`/`AuditTrend`), §7.4 |
| **Backlog delta (client-side, MF2)** | Server serves current rows + absolute open/closed counts via `/api/backlog`; the FE computes `BacklogDelta` (`added`/`closed`/`priorityChanged`/`statusChanged`/`firstVisit`) by diffing current rows vs a localStorage `BacklogSnapshot` (§13.3). No `/api/backlog-delta` in MVP1 (server field-level delta = MVP1.5); read-only (writes = MVP1.5). | §13.7, §7.5 (`BacklogDelta`/`BacklogSnapshot`), §7.4 |
| **Lessons-per-plan** | `LessonsView` — `lessons-learned.md` projected at plan/project/infra scope; full view on the Plan screen, thin list on `PlanSummary`. | §13.8, §7.5 (`LessonsView`), §7.4 |
| **Seams (types now, deferred behaviour)** | `TimeSource` (`MetricSet.timeBy`, MVP1 "neměřeno", WakaTime fills it MVP2) + Memory taxonomy (`MemoryQuery`/`MemoryEntry`/`MemoryResult`, MVP1 stub `/api/memory` → `{available:false,reason:"MVP2"}`, read wired MVP2). | §13.9, §7.5 (`TimeSource`/`MemoryQuery`), §7.4 |
| **Endpoints** | `GET /api/brief`, `/api/brief/:projectId`, `/api/brief/:projectId/:planId`, `/api/plans/:projectId`, `/api/plans/:projectId/:planId`, `/api/lessons`, `/api/audit-trend/:p/:e`, `/api/audit-trend/:p/plan/:planId`, `/api/memory` (MVP1 stub) — all read-only. (`/api/backlog-delta` removed — backlog delta is client-side, MF2; `/api/backlog` serves current rows + counts.) | §7.4 |
| **Dictionary** | 9 new `kind:"concept"` keys (risk levels, stale/stuck, decision-needed, MVP2-probability, first-visit) — additive, auto-flow into `/help`. | §13.10, §6.3 |
| **Phasing** | Rev 3 managerial surfaces (brief read-models, Screen G, Plan screen, audit summary + trend, backlog delta, lessons, lastSeen-localStorage, deterministic risk) folded into **MVP1**; user-notes + server-side lastSeen + backlog writes = **MVP1.5**; LLM narrative + success-probability % + memory read + WakaTime = **MVP2**. | §10 |
| **Acceptance** | AC #12-#22 (§13.11): brief/risk/probability/lastSeen/plan (#12-#16) + audit-summary never fabricates, audit trend gaps, plan aggregation, backlog delta off localStorage, lessons filtering, seams ship as seams (#17-#22). | §13.11, §10 |

Deferred by design (locked decisions): memory taxonomy in the contract but **read-only MVP2** (Qdrant via vulcan-memory, §13.9); `TimeSource` adapter = architecture seam only (MVP1 shows "neměřeno", WakaTime fills it MVP2, §13.9); user notes module (internal vs client) = **MVP1.5**; server-side multi-device lastSeen = MVP1.5; the smart probability % + narrative = MVP2 (the LLM agent).

*Spec assembled from 6 domain research reports (signals, timings, explain, backend, ui, ops), all grounded in direct disk inspection of the 6 AID v3 workspaces under `/opt/eco/projects/`. Ready for review → implementation plan.*

---

## 14. Rev 4 changelog - audit round 2

Resolution of the external design audit round 2 (against Rev 3). Each finding → resolution + sections changed. All edits are additive to Rev 3; no Rev 3 decision was re-opened. This section is the **current Rev 4 contract** wherever it supersedes the Rev 3 baseline in §12.5.

| Finding | Resolution | Sections changed |
|---|---|---|
| **MF1 — Plan membership self-contradiction** | ONE explicit four-tier precedence: `plan_path` → frontmatter `plan_ref` → id-derived `E-{NNN}`→`P{NNN}` (matched to a real `P{NNN}-*.md`) → orphan, recorded in `membershipSource`. The id-derived tier is an OFFICIAL but weaker member (tagged + warned, `concept:plan_membership_derived`), NOT fast-mode-excluded; only tier-4 orphans are excluded into `orphanEpicCount`. Verified on aid-orchestrator P046 (three members, all `plan_path:null`): `E-046-3_3` resolves at **tier-2 `plan_ref`** (its **active** `tasks/*.md` carries `plan_ref:` → P046), while `E-046-1_3`/`E-046-2_3` resolve at **tier-3 `derived`** — they are surfaced into the EPIC list by their `work/evidence/` dirs (§5.2 step 2), and their `plan_ref`-bearing task files exist **only under `tasks/archive/`**, which §5.2 excludes from the scan, so the scanner falls to id-derivation. (The member set + `planId` are identical whether or not §5.2 ever reads archived frontmatter — only the `membershipSource` label would shift tier-3→tier-2 — so the three-member fixture is stable.) Plus the `E-041`→orphan case (`P041` derived, no `P041-*.md`). | §13.6 (table + both grounding notes), §5.2 (scan rule referenced), §5.4, §5.1 `plan_duration_sec`, §7.5 (`MembershipSource`, `PlanSummary.epicMembers[]`/`membershipMixed`, `EpicSummary.membershipSource`), §13.4 plan scope, AC #16/#19, grounding notes |
| **MF2 — Backlog delta not computable from `since` alone** | Server is stateless and `backlog.md` has no per-row timestamps, so the delta moved CLIENT-SIDE: `GET /api/backlog` serves current rows + absolute `openCount`/`closedCount`; the FE persists a `BacklogSnapshot` (`{id,status,priority}[]` keyed by `scopeKey`+`lastSeen`) in localStorage and diffs current-vs-snapshot into `added`/`closed`/`priorityChanged`/`statusChanged`. `/api/backlog-delta` REMOVED from MVP1 (server field-level delta = MVP1.5). First visit → `firstVisit:true` "bez porovnání - vše jako nové". | §13.7 (rewritten), §13.3, §7.5 (`BacklogSnapshot`/`BacklogSnapshotRow`/`BacklogDelta`/`BacklogDeltaItem`, `PlanDetail.backlog`), §7.4 (endpoint removed), §10, §12.5, AC #20 |
| **MF3 — `ComplianceRun.failures` loses structure** | New `interface ComplianceFailure { check; evidence; severity:'blocking'|'advisory'; promotedAt? }` replacing `failures: string[]` in `ComplianceRun.failures` and `ComplianceView.violations[].failures`; rippled to Risk S1, `health.openViolations`, the "resolved blocking failure" rule, and the §10 gate-field list. | §7.5 (new interface + 2 field types + grounding note), §5.7 `openViolations`, §13.2.1 S1, §10 MVP-1 gate fields |
| **MF4 — `Checkpoint.provenance` not nullable** | `provenance: string | string[] | null` + new `provenanceSource: 'compliance'|'timeline'|null`. CP1 (no compliance provenance) and older/no-compliance runs are `null`, never `"unverifiable"`; read only from `compliance.json` (source of truth), timeline corroboration optional. | §7.5 (`Checkpoint` interface + grounding note), consistent with §4.2 |
| **MF5 — `successProbability: null` literal blocks the MVP2 plan** | New `interface SuccessProbability { value:number|null; source:'agent'|null; confidence? }` envelope with the binding MVP1 invariant **`value===null && source===null`** (UI renders "přesnější odhad přijde s agentem (MVP2)"). MVP2 fills `value`/`source:'agent'` with no contract churn. "flag, never fake" preserved — MVP1 still renders no number; AC #14 asserts the invariant. | §7.5 (new interface + `Brief.successProbability` + grounding note), §13 D2, §13.1 row 7, §13.4, §13.5.6, §10 MVP2 (+AC), §8.2 Screen G map, §13.11 AC #12/#14 |
| **MF6 — Plan screen lacks first-class Reporter + Simplifier** | `PlanDetail.deliveryReport` (`ReporterDelivery`) + `simplifierSummary` (`SimplifierSummary`) + supporting types (`ReporterTestEvidence`, `SimplifierProposal`, `DeliveryOutcome`, `SimplifierDisposition`); new Plan tab "Dodávka & zjednodušení" (two panels — Reporter delivery + Simplifier proposals) with desktop+mobile wireframes; `ReporterDeliveryPanel`/`SimplifierPanel` components. Missing `_test_evidence` files render honest `exists:false`. Audit stays its own tab. | §7.5 (types + `PlanDetail` fields), §8.1 route, §8.2 Plan wireframes + tab strips, §8.3 component inventory, §13.6 Plan tab map, AC #24 |
| **MF7 — Project-level audit not first-class** | New project-scope `Audit` tab on Screen B rendering `aggregateAudit` (the median-EPIC `AuditSummary`, §13.5.7) + project-scope `AuditTrend`, fed `GET /api/audit-summary/:projectId` + `GET /api/audit-trend/:projectId`; reuses the shared `AuditSummaryCard`/`AuditTrendChart` (no new component). `ProjectDetail` gains `aggregateAudit`/`auditTrend`. Honest empty case verified on sousto-na-miru (0 audit reports). | §8.1/§8.2 Screen B, §7.4 (2 endpoints), §7.5 (`ProjectDetail`), §13.5.7, AC #23 |
| **SF1 — Discovery contract** | MVP1 monitors ONLY top-level workspaces (`<scanRoot>/*/.aid-o`, depth-1) with the denylist; nested/empty/test `.aid-o` (e.g. `krok/backend/.aid-o`, `vulcan/ui/.aid-o`) are NOT recursed into. | §7.2, AC #1 |
| **SF2 — "no new disk reads" claim false** | Reworded to "no new source of truth, no writes, reads confined to existing v3 artifacts"; scanner Tier-1 index must include `plans/*.md`, `audit-report.md`, `backlog.md`, `lessons-learned.md`. | §13 intro, §13.1, §13.4, §7.2, §10 builders |
| **SF3 — Risk confidence contradiction** | Per-signal confidence: authoritative single-file signals (S1 blocking compliance, S8 audit blocking, S3 systematic) are HIGH from one file; rate/trend signals (S4 gate first-pass) need ≥3 runs for HIGH; timeline-pattern signals (S5/S6) are HIGH when the pattern is ≥2 occurrences. Resolves the §13.2.3-vs-§13.2.5 contradiction (`E-042-1_1` is correctly HIGH from one file). | §13.2.3, §13.2.5 |
| **SF4 — Plan audit semantic unclear** | Two distinct metrics: `boundaryAudit` (the single plan-boundary auditor run on the last EPIC) vs `aggregateAudit` (the MEDIAN-score member EPIC's `AuditSummary` — never a synthesized mean). The project Audit tab (MF7) uses `aggregateAudit`. | §13.5.7 (new), §7.5 (`PlanDetail.boundaryAudit`/`aggregateAudit`, `AuditTrend.scope:'project'`), §8.2 Plan/Screen-B Audit tabs |
| **SF5 — Stale Rev 2 B/C wireframes** | Screen B rewritten in place to the tabbed `Brief · EPICy · Plány · Audit · Zdraví` form (Brief = first tab, new Audit tab); Screen C reconciled (CP6 Fast-Mode-only line, Audit section tab). Rewritten, not appended. | §8.2 Screen B + Screen C |

> **Note — concurrent-edit reconciliation.** MF1/MF2/MF6/MF7/SF1-SF5 were applied directly to the file by four parallel design streams; MF3, MF4, MF5, the Rev 4 title line, the two umbrella type-consistency fields (`EpicSummary.membershipSource`, `ProjectDetail.aggregateAudit`/`auditTrend`), the MF1 grounding correction (the §5.2 archive-exclusion is why `E-046-1_3`/`E-046-2_3` are tier-3 `derived` rather than tier-2 `plan_ref` — the earlier "they have no task file" wording was factually wrong; their `plan_ref`-bearing task files do exist, only under `tasks/archive/`), and this §14 were applied in the final coordinator pass. The MF6 `ReporterDelivery`/`SimplifierSummary` shapes that landed are the UI-stream variants (with `present`/`outcome`/`summaryCs`/`testEvidence[].exists`); the contracts-stream's overlapping leaner proposal is superseded by them.
