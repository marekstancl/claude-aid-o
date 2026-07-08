# Extending AID — a contributor reference for enforcements

This is the one place that answers: *"I want to add a new agent / gate / check /
audit signal — where does each piece go, and what makes it real instead of
decoration?"* It distils the binding conventions from
[`docs/plans/AID-v3-principles.md`](plans/AID-v3-principles.md) §1 and the P041
governance recommendation
([`docs/plans/AID-audit-2026-06/03-governance-recommendation.md`](plans/AID-audit-2026-06/03-governance-recommendation.md)),
and uses **P045 (Simplifier + Reporter)** as the end-to-end worked example.

The two binding rules behind everything below:

- **Principle #1 — Detector without Enforcement is Decoration.** A check that
  fires but blocks nothing trains the PM and the agent to ignore it. Name the
  enforcement mechanism at design time, never "later".
- **Candidate Principle #5 — Enforcement without Instruction is Cargo Cult.** The
  inverse: every enforcement needs a matching LLM-facing instruction in the
  type's canonical home, or the rule is rediscovered by failure each time.

---

## Where each enforcement type lives (the type→instruction-home table)

Every enforcement has a `type` (1–15) and exactly one canonical place where its
human/LLM-facing instruction (its "cedule") must live. This is the binding
convention from governance Component 2 — authors never have to wonder where the
instruction goes:

| Type | Enforcement | Canonical instruction home |
|------|-------------|----------------------------|
| 1 | FSM-precondition (orchestrator) | `skills/pipeline.md` (state/transition sections) |
| 2 | FSM-precondition (subagent output) | `agents/verifier.md` **or** `skills/agent-protocol.md` |
| 3 | Dispatch-wrapper | `skills/pipeline.md` §4 Dispatch Protocol |
| 4 | Structural-check | `skills/pipeline.md` (relevant §) or the generating script's header |
| 5 | Pre-filter-regex | `defaults/pre-filter-rules.yaml` (self) + `pipeline.md` §13 |
| 6 | Schema-validator (plan) | `skills/plan-writing.md` + `skills/planner.md` |
| 7 | Command-orchestration-rule | `commands/<cmd>.md` |
| 8 | Hook-enforcement | `defaults/hooks/*` + `agent-protocol.md` git discipline |
| 9 | YAML-policy-driven | the policy YAML (self) + `pipeline.md` if FSM-consumed |
| 10 | Template-shaped | the template (self) + consumer skill |
| 11 | Audit-log invariant | `agent-protocol.md` "P040 audit events" table |
| 12 | Skill-loaded-protocol | the skill itself |
| 13 | Agent-contract | `agents/<agent>.md` or `skills/role-cards.md` |
| 14 | Test-regression-gate | the `test-*.sh` itself |
| 15 | Stack-gate-binding | `defaults/execution-stacks/<lang>.yaml` |

`surface` (separate from type) splits drift risk: `llm-facing` enforcements
**require** an instruction in their home; `internal-guard` mechanisms (nonces,
flocks, source-only helpers) may set `instruction: n/a`.

---

## Checklist to add an enforcement

Do all five in the **same change** that introduces the check — "register +
document" is definition-of-done, not later cleanup:

1. **Add a registry entry** in
   `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` with
   `id` / `type` / `source` / `instruction` / `severity` / `surface` / `status`.
   The `instruction` field forces the enforcement to name *where* its cedule is;
   a blank `instruction` on an `llm-facing` entry is exactly the GAP class.
2. **Put the instruction in the type's canonical home** from the table above.
3. **Declare `severity` and `surface`.** Per AID-v3-principles.md §1 tiered
   severity, new checks default to `advisory` (logged, not blocking) and are
   auto-promoted to `blocking` only after empirical validation (≈N=5 consecutive
   EPICs with no `--force` for that check, or explicit PM promotion with reason).
   `surface` is `llm-facing` or `internal-guard`.
4. **Wire the evaluator** — pick one of the three acceptable enforcement
   mechanisms and name it now, never "later":
   - FSM precondition block (refuses a state transition),
   - out-of-band hard fail (CI / pre-push hook / maintainer script the agent
     can't skip),
   - explicit PM confirmation gate with logged justification.
5. **Add a regression test** (a `test-*.sh` / bats case) so the check can't
   silently rot, and record it in the registry's `test:` field.

**What an instruction (cedule) must contain** — the 4-part minimal contract from
governance Component 2:

1. **The rule** — plain imperative ("gates_report.json must carry
   `_generated_by`").
2. **The trigger** — when the check fires (which transition / which diff / which
   output).
3. **The failure mode** — the exact reason string the user will see.
4. **The fix** — the copy-paste remediation (most `die()` messages already embed
   this).

---

## The FSM precondition pattern

There are two distinct shapes in `aid-fsm.sh`. Choose by whether you want a
promotable advisory signal or an immediate hard stop.

### Severity-layer (soft, advisory→promotable)

A top-level scalar in `evaluate_compliance_checks` whose **`false` value
`fsm_build_failures` turns into a failure entry**. The rule is simple: any
top-level boolean-`false` scalar becomes a failure (enriched with `severity` +
`promoted_at` from `check-severity.yaml`, defaulting to `advisory`); `null` and
`true` are ignored — `null` means "not applicable" and can never fail.

These failures are surfaced **only** at `cmd_done_advance review→release`, via
`_blocking_count` (it counts only `severity == "blocking"` failures; an advisory
failure is logged into `compliance.json` but release still proceeds).

- **Worked example:** `delivery_report_present` (the P045 check). Its helper
  `fsm_eval_delivery_report_present` (aid-fsm.sh ~:840) echoes a JSON literal:
  `null` before the plan boundary, `true` when the report exists and references
  ≥1 on-disk evidence artifact, `false` otherwise. Because it defaults to
  advisory, a missing report is logged but release still ships.
- **Prior art:** `dod_present` and `memory_substantive` — same soft scalar shape,
  same severity layer.

### Hard-die precondition

A `die()` / `exit 1` directly in a command path — no severity layer, no
override-by-default. Two repo examples:

- The **cross-plan init guard** (~aid-fsm.sh:1479–1501): `cmd_init` refuses to
  start a new plan when the previous plan has an `audit-report.md` but no
  `ca-review-complete` marker — `exit 1` with a remediation message.
- `fsm_check_cp4_curator_validation` (aid-fsm.sh:283) — requires the CP4 curator
  validation output when a curator commit touched production code; fails closed.

**When to choose which.** Use the severity-layer when the signal is new and you
want it advisory-then-promotable (the responsible default under §1's
tiered-severity caveat — hard-blocking on first deployment floods false
positives and trains reflexive `--force`). Use a hard-die only when an immediate
stop is correct regardless of empirical track record (an integrity invariant, a
structural impossibility).

**Plan-boundary vs per-EPIC placement.** A plan-level check must attach to the
`ca-review-complete` marker (the plan boundary), **not** to a per-EPIC
`done-advance`. `fsm_eval_delivery_report_present` returns `null` (not
applicable) until `ca-review-complete` exists in the EPIC's evidence dir —
that's what stops a plan-final check from false-blocking every non-final EPIC of
the plan.

---

## Dispatch-mode reality (agent_tool default)

`agent_tool` is the **default** dispatch mode (set in P043, commit `39a2b61`).
Resolution order: project `.aid-o/config/plugin.yaml` `dispatch_mode` → plugin
`defaults/orchestration.yaml` `dispatch.mode` → hard fallback `agent_tool`.

This matters for anti-fabrication. In `agent_tool` mode the CC Agent tool writes
**no timeline events**, so `verify_provenance` returns the non-blocking
`agent_tool` **sentinel** without checking — the timeline interval-bracket
(`verifier_dispatch_start`..`verifier_dispatch_complete`) only runs in
`subagent` mode. So in the default mode the anti-fabrication floor is:

- **structural-presence** checks (the output file actually exists),
- an **independent Auditor** pass, and
- **honest agent instructions** in `pipeline.md` (MUST-dispatch /
  MUST-NOT-self-review).

Hard, non-fabricatable provenance enforcement (the interval-bracket against a
real dispatch timeline) requires **opt-in `subagent` mode**. Don't design a new
check assuming the timeline is there by default — it isn't.

---

## Worked example: P045 Simplifier + Reporter

P045 added two plan-boundary agents end-to-end. Each artifact maps to its type
and canonical home:

- **Agent contracts (type 13).** `agents/simplifier.md` (propose-only; never
  edits code) and `agents/reporter.md` (tests the delivery, writes the report).
- **Template (type 10).** `defaults/templates/delivery-report.md` — the shape of
  `.aid-o/reports/{plan_id}-delivery.md`, including the `_test_evidence[]`
  frontmatter the structural check reads.
- **Orchestration (types 1/3).** `skills/pipeline.md` §4 (dispatch-wrapper:
  wrap reporter/simplifier dispatch by mode, emit `aid-emit-dispatch.sh`
  start/complete with `--focus reporter|simplifier`) and §7 DONE (the
  plan-boundary sequence: Simplifier after C+A fixes, Reporter last after CP4).
- **Structural check (type 4).** `fsm_eval_delivery_report_present` feeds the
  **severity layer** as `delivery_report_present` — advisory by default, surfaced
  only at `review→release`, `null` until the plan boundary.
- **Policy (type 9).** `check-severity.yaml` (the check's severity registry),
  `defaults/policies/review-checkpoints.yaml` (`simplifier_pass` /
  `delivery_report` toggles) and `execution.yaml`.
- **Dispatch guard.** `aid-emit-dispatch.sh` enforces a focus allowlist so
  `reporter` / `simplifier` are recognized dispatch foci.
- **Registry.** Entries for the new check and agents in
  `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`.

**agent_tool caveat.** Because the default dispatch mode is `agent_tool`, the
Reporter's delivery report is held honest by structural presence + the
independent Auditor + the §7 dispatch instructions — not by timeline provenance.
The `delivery_report_present` check verifies the report exists and references a
real on-disk artifact; it does not (and cannot, in `agent_tool` mode) prove the
Reporter was independently dispatched. That hard guarantee needs `subagent` mode.

---

## Enforcement Homes Reference

When adding a new detection capability, register it in `defaults/enforcement-registry.yaml` with:
- `id`: unique snake_case identifier
- `type`: `fsm_precondition` | `lm_judgment_advisory` | `out_of_band_hard_fail` | `pm_confirmation_gate`
- `enforcement_mechanism`: the exact mechanism (see AID-v3-principles.md §1)
- `test_anchor`: path to the bats/sh test that proves it works
- `deadline`: ISO date after which the TTL guard flags it if not tested

### Plan Boundary Enforcement

- **plan-close gate**: `aid-fsm.sh:cmd_plan_close()` — enforces all 4 required reports (curator-report, audit-report, simplifier-report, delivery-report) before `ca-review-complete` marker. Bypass: toggle-skip pattern with PM rationale.
- **CI floor**: `defaults/ci/plan-boundary-required-check.yml` — GitHub Actions check for committed boundary manifests in `.aid-o/reports/`. Requires `!.aid-o/reports/` in `.gitignore` (see `commands/aid-init.md`).

### CP5 Contract

- **blocking_findings check**: `aid-fsm.sh:cmd_done_advance()` — reads `blocking_findings` field from `audit-report.md` as a structured top-level field (not prose). `blocking_findings: true` blocks the MERGE option in the PM summary.
- **Contract location**: `skills/review-checkpoint-contracts.md` §CP5 Contract (see CP4 Contract for the adjudicator flow).

### behavior_trace Enforcement

- **High-risk patterns**: 8 categories in `skills/review-checkpoint-contracts.md` (auth, routes, validation, migrations, fsm, security sinks, payment, dep manifests).
- **Structural gate**: `aid-fsm.sh:fsm_check_verifier_output()` — fires when `behavior_trace_required: true` explicitly set in verifier output. Returns non-zero if `behavior_trace_count == 0`.
- **Per-checkpoint diff scope**: `aid-prefilter.sh --checkpoint <cp2|cp3|cp4|cp6>` — CP2=step diff, CP3=base_commit..HEAD, CP4=applied C+A diff.

---

## AID Control System v2 Protocol (enforced vs reference)

AID Control System v2 introduces a shared protocol v2 envelope that all control mechanism artifacts (C0-C4) will carry. The definitions live in `defaults/schemas/`.

### Schema files
- `defaults/schemas/aid-protocol-v2.schema.json` — canonical envelope schema (JSON Schema draft 2020-12); every field annotated `$comment: enforced` or `$comment: reference`
- `defaults/schemas/README.md` — enforced-vs-reference table with `aid-protocol-validate.sh`'s exact enforcement scope
- 14 type-specific schemas: `plan-review.schema.json`, `plan-graph.schema.json`, `contract-manifest.schema.json`, `review-profile.schema.json`, `delivery-gate.schema.json`, `ui-fidelity.schema.json`, `semantic-review.schema.json`, `acceptance-evidence.schema.json`, `audit-report.schema.json`, `audit-input-manifest.schema.json`, `release-decision.schema.json`, `pm-decision-brief.schema.json`, `curator.schema.json`, `delivery-report.schema.json`
- `defaults/schemas/run-control-protocol.schema.json` — per-run protocol lock (E2+ wiring)

### Validator: `aid-protocol-validate.sh`

**This is the authoritative source of truth for E1 enforcement.** The JSON Schema files are canonical references; the bash validator enforces a named subset of invariants.

**This does NOT claim full JSON Schema validation.** Full JSON Schema validation (with `$ref` resolution, `if/then`, deep `allOf`) is NOT implemented in E1 and will be a separate C1 extension if needed.

```
aid-protocol-validate.sh <artifact.json> [--current-head <sha>] [--check-fingerprint]
```

Exit codes:
- `0` — all blocking invariants pass
- `2` — invalid JSON
- `3` — missing required envelope field
- `4` — bad schema_version (must be `aid-2.0`)
- `5` — bad artifact_type (not in 14-value enum)
- `6` — bad created_at format (not ISO-8601 UTC)
- `7` — bad subject_hash format (must be `sha256:<64-hex>`)
- `8` — bad status or verdict.kind enum value
- `9` — bad provenance (unknown dispatch_mode or empty generated_by_tool)
- `10` — critical/high severity finding without action_owner
- `11` — head_sha mismatch with `--current-head` (stale artifact)
- `12` — missing type-specific minimal payload key
- `13` — finding fingerprint doesn't match recomputed hash (`--check-fingerprint`)

Legacy artifacts (`control_protocol: "legacy"`) → exit 0 with `legacy_skipped`; no other checks run.

### Finding fingerprint
`scripts/lib/aid-finding-fingerprint.sh fingerprint <project_id> <artifact_type> <check_id> <target_path> <finding_class>` returns `sha256:<64-hex>` — deterministic (same inputs → same hash). Used to track finding lifecycle across runs.

### Extension points
- The validator is **standalone in E1** — not wired into any FSM precondition. Wiring is E2+.
- New artifact types add a type-specific schema in `defaults/schemas/` and a case in the validator's type-payload map (step 12).
- See `defaults/schemas/README.md` for the complete enforced-vs-reference table.

---

## C1 Delivery Engine (E2)

The C1 Delivery Engine (`aid-delivery-gate.sh`) is a deterministic (no-LLM) gate
that runs after every EXECUTE phase in observe mode. It produces a protocol-v2
`delivery-gate.json` artifact.

### Profiles

The engine auto-detects the project profile from `defaults/policies/delivery-gate.yaml`:

| Profile | Detected by |
|---------|-------------|
| `plugin-bash` | `.claude-plugin/plugin.json` present |
| `npm-workspaces` | `package.json` with `"workspaces"` |
| `npm-workspaces+plugin-bash` | Both above (union) |
| `unverifiable` | Neither detected |

The profile determines which check commands to run for each DG check (DG-01..12).

### Checks (DG-01..12)

| ID | Name | Applicability |
|----|------|---------------|
| DG-01 | dependency-consistency | lockfile present |
| DG-02 | build | build command declared |
| DG-03 | typecheck | `.ts` files present |
| DG-04 | test | always |
| DG-05 | consumer-compile | public exports changed |
| DG-06 | removed-dep | deps removed from manifest |
| DG-07 | state-consistency | always |
| DG-08 | runtime-env | `.nvmrc` or `engines` present |
| DG-09 | static-coverage | typecheck/lint command declared |
| DG-10 | startup-smoke | built entry point present |
| DG-11 | build-config | bundler config present |
| DG-12 | authority | authority policy files present |

### Observe -> Blocking Promotion

E2 is **observe mode only**. The engine writes telemetry but never blocks FSM transitions.

To promote to blocking (E10):
1. Set `enforcement: blocking` in `defaults/policies/delivery-gate.yaml`
2. All DG checks must have green baselines on your codebase first
3. Update enforcement-registry entries from `status: planned` to `status: active`

### Reading delivery-gate.json

```json
{
  "delivery_gate": {
    "delivery_ready": false,
    "profile": "npm-workspaces+plugin-bash",
    "phase": "D0",
    "checks": [
      { "id": "dg01", "name": "dependency-consistency", "status": "skip",
        "skip_reason": "legacy_no_child_rows", "output_preview": "" }
    ],
    "summary": { "total": 12, "pass": 0, "fail": 0, "skip": 11, "unverifiable": 1, "would_block": false }
  }
}
```

Full artifact is a protocol-v2 envelope validated by `aid-protocol-validate.sh`.

---

## Evidence Pack Verifier (E2.5)

`aid-evidence-verify.sh` is a standalone deterministic CLI that verifies an evidence pack for a completed run. It does not modify FSM state — it is a PM/CI tool for post-DONE validation.

### How to run

```bash
# Verify specific run
bash plugins/aid-orchestrator/scripts/aid-evidence-verify.sh <epic_id> <run_id>

# Strict mode (pack_head must equal current HEAD — for live DONE-review)
bash plugins/aid-orchestrator/scripts/aid-evidence-verify.sh <epic_id> <run_id> --at-head

# Write report to custom path
bash plugins/aid-orchestrator/scripts/aid-evidence-verify.sh <epic_id> <run_id> --out /tmp/vr.json

# Auto-detect most recent epic/run
bash plugins/aid-orchestrator/scripts/aid-evidence-verify.sh
```

Exit codes: 0 = pack verified, non-zero = one or more required checks failed.

### What it verifies

| Check | When it fails |
|-------|---------------|
| `git_clean` | Working tree has uncommitted changes |
| `evidence_pack_found` | No evidence pack dir or no v2 artifacts |
| `artifact_head_freshness` | Artifacts disagree on head_sha, or pack_head not reachable from HEAD |
| `protocol_validate` | Any artifact fails `aid-protocol-validate.sh` |
| `fingerprint` | Any artifact has nondeterministic finding fingerprint |
| `ttl_registry` | Registry has planned row past deadline without deferral |
| `observe_blocking_interpretation` | `delivery-gate.json` missing `enforcement` key, or value not in {observe, dual_run, blocking} |

### Observe-vs-blocking rule

The `observe_blocking_interpretation` check fires only when `delivery-gate.json` is in the evidence pack. If absent → `skip` (not a failure). The check validates that:
- `delivery_gate.summary.enforcement` is present and not null
- Its value is in `{observe, dual_run, blocking}`
- If `enforcement: observe` → `would_block` is a bool (present and not null)

This catches the real E2 finding: `delivery-gate.json` has `summary.would_block: true` but `enforcement` key is **absent** — the verifier reports `observe_blocking_interpretation: fail`.

### Output

Writes `verification-report.json` (protocol-v2 artifact) to the evidence pack dir (or `--out` path). The artifact self-validates: `aid-protocol-validate.sh verification-report.json` exits 0.

Human summary is printed to stdout. Example (failing pack):

```
============================================
 Evidence Pack Verification — NOT VERIFIED
============================================
 Epic:    E-050-1_1
 Run:     R-E050-1
 Pack:    a5da342...
 HEAD:    7bfe57e...
--------------------------------------------
 Checks:
  ✓  git_clean                            pass
  ✓  evidence_pack_found                  pass
  ✓  artifact_head_freshness              pass
  ✓  protocol_validate                    pass
  ✓  fingerprint                          pass
  ✓  ttl_registry                         pass
  ✗  observe_blocking_interpretation      fail
--------------------------------------------
 Blocking issues:
  • observe_blocking_interpretation: enforcement key absent or null
============================================
```

---

## Adaptive Review Profile (E3)

E3 adds a **deterministic, LLM-free profile resolver** (`aid-prefilter.sh profile`)
that computes which review lenses are required for a given EPIC run. It operates in
**observe mode** — it emits telemetry but never blocks.

### How it works

1. **Plan-time surfaces (best-effort):** Reads surface hints from the plan/EPIC file.
   Missing plan section → empty list `[]`. Authoritative plan-time contract is E4.

2. **Candidate-time surfaces:** `git diff <range>` over actual changed files + content
   signals. Path globs and content signals (bash `case`/`grep -F`) determine which
   surfaces are touched.

3. **Monotonic union (FC-41):** `matched_surfaces = plan_time ∪ candidate_time`.
   The profile only grows, never shrinks. An unplanned candidate surface expands
   the profile — it does NOT invalidate it (invalidation is E5/E9).

4. **Unknown surface = `unverifiable`:** A production path that doesn't match any
   surface glob and isn't in `docs_allowlist` → `risk_profile: unverifiable`.
   Never silently downgrade to `docs_trivial`.

5. **Range required:** No `--range` and no `base_commit` in `fsm-state.yaml` →
   `risk_profile: unverifiable` + exit 22 (`range_undetermined`). No silent
   `HEAD~1..HEAD` fallback (would miss earlier-step surfaces — FC-41 risk).

6. **Profile hash:** `aid-profile-hash.sh profile_hash <pid> <plan_surfaces>
   <candidate_surfaces> <lenses>` → `sha256:<64 hex>`. Inputs sorted before
   hashing (deterministic). Hash change = profile change (E5 uses this).

### Observe mode semantics

The FSM hook (`cmd_done_advance` review→release) calls `review-profile-check.sh`:
- Exit 0 → no missing lenses (completed_lenses ⊇ required_lenses) → silent
- Exit 1 → missing lenses → `log_event review_profile_missing_lenses` + **proceed**
  (observe: non-blocking)
- Exit 2 → unverifiable → `log_warn` + **proceed** (always observe for unverifiable)

`completed_lenses` is always `[]` in E3 — C2/C3 don't exist yet. E5 will populate
the evidence markers. This means in E3 every non-trivial profile will log missing
lenses telemetry — that is intentional, not a defect.

Promotion to **blocking** is planned for E10 after calibration.

### enforcement-registry.yaml entry

```yaml
- id: review_profile_missing_lenses
  type: fsm_precondition
  source: "scripts/aid-fsm.sh (lib/review-profile-check.sh)"
  enforcement: observe
  promotion_phase: E10
  description: "review profile detector (aid-prefilter.sh profile emits
    review-profile.json, authority none) gated by observe FSM hook
    computing missing_lenses"
```

See [`plugins/aid-orchestrator/defaults/enforcement-registry.yaml`](../plugins/aid-orchestrator/defaults/enforcement-registry.yaml) for the full entry.

### Adding a new surface

1. Add an entry to `defaults/policies/review-profiles.yaml` under `surfaces:`:
   ```yaml
   my_new_surface:
     match:
       path_globs: ["path/to/**/*.ext"]
       content_signals: ["keyword_in_diff"]
     risk: medium
     lenses: [behavior_trace, ac_to_test_identity]
     probes: ["what to check in this surface"]
   ```
2. Lenses MUST be from the C2 vocabulary in `docs/design/control-topology.yaml`
   (`C2.lenses`). No invented names.
3. Add fixtures in `scripts/tests/fixtures/review-profile/<scenario>/` and cover
   in `test-review-profile.sh`.

---

## C0 Plan Contract Gate (E4)

C0 is an **observe-only gate layer** that runs in `aid-auto-pipeline.sh` after
`aid-epic-to-json` extracts the plan graph. It produces three artifacts and
dispatches five semantic lenses (via CP1-deep) — all in observe mode. No FSM
transition is blocked in E4. Blocking promotion is planned for E10.

### Artifacts produced

| Artifact | Location | Description |
|----------|----------|-------------|
| `plan-graph.json` | `.aid-o/work/evidence/{plan_id}/c0/plan-graph.json` | Directed acyclic graph of plan steps with dependency edges; produced by `scripts/lib/aid-plan-graph.sh` `build_plan_graph` + `topological_order` |
| `contract-manifest.json` | `.aid-o/work/evidence/{plan_id}/c0/contract-manifest.json` | Per-step contract declarations: authority, idempotency class, external calls, reuse candidates |
| `plan-review.json` | `.aid-o/work/evidence/{plan_id}/c0/plan-review.json` | Aggregated lens findings; `would_block` bool; protocol-v2 envelope |

All artifacts are protocol-v2 envelopes validated by `aid-protocol-validate.sh`.

### Implementation

The producer script `scripts/aid-c0-contract.sh` implements both the `contract` and `review` subcommands. The `contract` subcommand computes the binding hashes and manifest, while the `review` subcommand performs the five structural checks and lens evidence scan.

### The 5 semantic lenses

Each lens is dispatched by the orchestrator in CP1-deep and runs in **observe
mode** (advisory, never blocking in E4). Findings are appended to
`plan-review.json`.

| Lens | id | What it checks |
|------|----|----------------|
| Reuse compatibility | `c0_lens_reuse_compat` | Planned implementations that duplicate existing helpers or APIs |
| Planned call feasibility | `c0_lens_planned_call_feasibility` | External/internal calls declared in the plan that don't exist or have incompatible signatures |
| Dependency API grounding | `c0_lens_dep_api_grounding` | Library/API usage in plan steps where the imported API differs from what the dependency exposes |
| Idempotency matrix | `c0_lens_idempotency_matrix` | Steps without idempotency class declaration, or classes that conflict with their callers |
| Authority runtime matrix | `c0_lens_authority_runtime_matrix` | Authority declarations in contract-manifest that conflict with runtime permission model |

Lens contracts (stop rules, stop_rule_blockers count, severity) live in
`skills/review-checkpoint-contracts.md` §C0 Lenses.

### Policy file

`defaults/policies/c0-contract.yaml` governs the gate:

```yaml
enforcement: observe        # observe | blocking (promote to blocking in E10)
promotion_phase: E10
lenses:
  - reuse_compat
  - planned_call_feasibility
  - dep_api_grounding
  - idempotency_matrix
  - authority_runtime_matrix
```

### Observe log

`c0-observe.jsonl` in the evidence directory records every `c0_would_block`
event. Each line is a JSON object:

```json
{"event": "c0_would_block", "plan_id": "P-001", "lens": "reuse_compat",
 "finding_count": 2, "timestamp": "2026-06-28T10:00:00Z"}
```

The log is append-only. The FSM never reads it — it exists for PM telemetry and
E10 calibration.

### Promotion to blocking (E10)

To promote C0 from observe to blocking:

1. Set `enforcement: blocking` in `defaults/policies/c0-contract.yaml`
2. All five lenses must have green baselines on your codebase (zero
   `would_block` events across ≥5 EPICs)
3. Update all seven `c0_*` entries in `defaults/enforcement-registry.yaml`
   from `status: planned` to `status: active`
4. Wire `c0_would_block` as an FSM precondition in `aid-auto-pipeline.sh`

### Adding a new C0 lens

1. Create `skills/c0-lens-{name}.md` with the lens contract:
   - `stop_rule_blockers: N` — number of blockers that trigger `would_block`
   - `severity`: advisory | fail
   - `probes`: list of questions the lens answers
2. Add the lens to the `lenses:` list in
   `defaults/policies/c0-contract.yaml`
3. Add a `c0_lens_{name}` entry in
   `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`
4. Register the lens in `skills/review-checkpoint-contracts.md` §C0 Lenses
5. Add fixtures in `scripts/tests/fixtures/c0/<scenario>/` and cover in
   `test-c0-contract.sh`

---

## Per-Step Scoping (D2) and Contract Validation Gate (D5)

P058 fixed a class of generator bugs where `aid-plan-to-epic.sh` /
`aid-epic-to-json.sh` **broadcast** EPIC-level content to every step instead
of scoping it per step: every step's `outputs`/`allowed_paths` ended up
byte-identical (the flat `## Artifacts` section copied verbatim to all
steps), and a `|`-split parsing bug fragmented multi-clause Acceptance
Criteria into extra bogus array entries. Both defects made `plan.json`
internally inconsistent without ever failing loudly. D2 is the source-side
fix (scope content per step at generation time); D5 is the gate that catches
any recurrence structurally, regardless of which generator produced the
`plan.json`.

### Per-step scoping block (D2)

`aid-plan-to-epic.sh` emits one HTML-comment metadata block per EPIC step,
under `## Step UI Contracts`, using the same inert-comment convention as the
existing `ui_change_mode` per-step block:

```
<!-- step-N: files=["Create: `path` — desc","Modify: `a` + `b`"]; ac=["AC text 1","AC text 2"] -->
```

- `files[]` — one JSON string per step-local Files bullet, verbatim (label +
  backticks + description kept) except for the leading `- `. `outputs` is
  derived verbatim from this array; `allowed_paths` is derived by cleaning
  it (stripping the `Create:`/`Modify:` verb prefix and description).
- `ac[]` — one JSON string per step-local Acceptance Criteria bullet, with
  the leading `- [ ]` checkbox stripped but no `[role]` prefix (the block is
  already step-scoped).
- Both arrays are JSON-encoded (`jq -R -s -c`), one string per source line.
  A literal `-->` inside a value is replaced with a sentinel before encoding
  so it can never truncate the block early; `aid-epic-to-json.sh` reverses
  the substitution after decoding.

`aid-epic-to-json.sh` (P058 Step 3) reads this block **per step** instead of
assigning the flattened EPIC-level sections to every step — this is what
makes `outputs`/`allowed_paths`/`acceptance_criteria` distinct per step in
`plan.json`. Legacy EPICs that predate this block fall back to the flat
`## Acceptance Criteria` section's `[role]`-tagged bullets.

### Contract Validation Gate (D5)

`scripts/gates/aid-contract-validate.sh` is a **blocking** structural gate
over the generated `plan.json` (+ optional `task/EPIC.md`), modeled on
`scope-check.sh` (stdin-free, `<plan_json_path> [epic_md_path]` args, JSON on
stdout, exit 0 = pass / exit 1 = fail):

| Check | What it catches |
|-------|------------------|
| `per_step_scoping` | Multi-step plan where every step's `outputs` OR every step's `allowed_paths` is byte-identical across ALL steps — the broadcast bug D2 fixes. Partial overlap is not a violation; only full identity is. |
| `ac_no_fragments` | Each step's `acceptance_criteria` array length must equal the count of source AC bullets attributed to that step (from the D2 per-step block, or the legacy `[role]`-tagged fallback). Independently, a defense-in-depth heuristic flags any AC string that — outside balanced backtick spans — contains a bare `length ==`/`.enforcements` substring or an odd count of `'` characters, the textual signature of a `\|`-split mid-fragment. |
| `allowed_paths_shape` | Any `allowed_paths` entry containing whitespace, `(`, or `)` — real repo paths never contain these; a hit means a verb prefix or trailing prose leaked through. |

It is wired as the one BLOCKING exception inside the otherwise observe-only
C0 block of `aid-auto-pipeline.sh`, running immediately after
`aid-epic-to-json.sh` produces `plan.json` and before FSM init / `json-to-run`
/ queue-add / branch creation. The result is persisted to
`.aid-o/work/evidence/{plan_id}/c0/contract-validate.json` **before** the
exit code is inspected (so a later phase's failure can never hide behind an
earlier phase's stale pass), then `error_exit ... 4` aborts the pipeline on
`result: "fail"`. `aid-c0-contract.sh`'s `review` subcommand exposes a Check
6 (`contract_validation`) that reads — never re-runs — that persisted
result, so the C0 evidence pack always reflects the real gate outcome.

Registered as `contract_validation_gate` (`type: 4`, Structural-check;
severity `blocking`) in `defaults/enforcement-registry.yaml`.

---

## C2 Semantic Review Engine (E5)

The C2 Semantic Review Engine runs in **observe/best-effort mode** (E5). Findings are
emitted as additive JSON evidence; the existing `.md` gate is unchanged (D1).

### How to Add a New Lens

1. **Define the lens** in `skills/review-checkpoint-contracts.md` → `## C2 Semantic Review — Lens Catalog` table.
   Give it: FC code, lens name, dispatch mode (local/wiring/behavior/final), trigger, stop condition, negative fixture.

2. **Register in enforcement-registry.yaml**: add entry with `type: 4`, `source: agents/verifier.md`, `severity: advisory`, `status: active`.

3. **Write the negative fixture** in `scripts/tests/fixtures/semantic-review/<fc-XX>-<lens>-neg.json`.
   Format: `semantic_review.findings[]` with a finding that the negative fixture should trigger.

4. **Add a test case** in `scripts/tests/test-semantic-review.sh` — verify the fixture validates.

### Dual-Emit Protocol (D1 Safety)

The `.md` gate verdict (`verdict: pass|fail`) is the FSM gate signal. It MUST NOT be
changed by C2. The `semantic-review-{mode}.json` file is additive evidence only.

When `c2_mode` is absent in the task input, skip dual-emit entirely. This ensures
existing non-C2 pipelines are unaffected.

### Fingerprint Format

Every C2 finding MUST carry a `fingerprint` field:
```
fingerprint <project_id> semantic_review <check_id> <target_path> <finding_class>
```
Use `scripts/lib/aid-finding-fingerprint.sh` to compute it.

### Policy and Promotion

E5 policy (`defaults/policies/semantic-review.yaml`):
- `enforcement: observe` — findings log, never block
- `promotion_phase: E10` — blocking mode deferred to E10

To test blocking behavior without waiting for E10:
```bash
SEMANTIC_REVIEW_POLICY=blocking bash scripts/aid-fsm.sh increment-step ...
```

---

## Delivery Map Configuration (E6)

The `delivery-map.yaml` file (`.aid-o/config/delivery-map.yaml`) configures opt-in C1 probes for DG-15, DG-17, and DG-18. Without this file, all three probes are skipped (not-applicable).

### Schema

```yaml
# .aid-o/config/delivery-map.yaml
meta:
  status: active        # draft | active | deprecated
  confidence: high      # low | medium | high
  stack: react-router+express

routes:
  framework: react-router   # react-router | express
  route_files: ["src/routes/**/*.tsx"]
  link_globs: ["src/**/*.tsx"]

oracle_baselines:
  events_log:
    analytics_output_file: "data/events.json"
    expected_cardinality: 100
    cardinality_method: jq_length  # jq_length | grep_count
```

### DG-15 — Route Resolve (literal links only)
Checks that `<Link to="...">` paths resolve to declared routes. Scope: **literal strings only** — dynamic links (computed values, template literals) are not checked and no false-negative is claimed.

Dynamic links (`to={variable}`, `to={computedPath}`, template literals) are **out of scope** — the probe cannot see them and makes no false-negative claim for those patterns.

### DG-17 — Independent Oracle No-Drop
Checks that analytics output files meet declared minimum cardinality. Requires `analytics_output_file` and `expected_cardinality` per baseline. Without a file → config_missing (not a fake pass).

### DG-18 — Acceptance Provenance
Reads FSM step-*-verify.md evidence, surfaces acceptance history into delivery-gate.json. Never emits a fail — skip is handled by the dispatcher.

### What E6 Does NOT Deliver
- DG-13 (reachability analysis) — requires AST tooling
- DG-14 (wire shape) — requires AST tooling
- DG-16 (fallback invocation) — requires call-graph analysis
- Living-contract enforcement (map_drift, C0 preflight, delivery_areas) — separate schema/setup phase
- Automatic delivery-map generation (`aid-init` proposal)

**Last Updated:** 2026-06-29
