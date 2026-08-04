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

C0 has two graph inputs with distinct ownership. Before EPIC generation,
`aid-generation-readiness.sh` derives a plan-global provisional graph directly
from the source plan and binds it to C0. During generation,
`aid-epic-to-json.sh` derives a separate, per-EPIC contract graph. C0 receives
both; neither is allowed to overwrite the other. The provisional graph prevents
the impossible dependency on an EPIC-derived artifact before EPICs exist.

### Artifacts produced

| Artifact | Location | Description |
|----------|----------|-------------|
| `provisional-graph.json` | `.aid-o/work/evidence/{plan_id}/generation/provisional-graph.json` | Plan-global, source-plan graph used before generation; hash-bound to the reviewed source plan |
| `plan-graph.json` | `.aid-o/work/evidence/{plan_id}/c0/plan-graph.json` | Per-EPIC contract graph; it is not evidence of the whole multi-phase plan |
| `contract-manifest.json` | `.aid-o/work/evidence/{plan_id}/c0/contract-manifest.json` | Per-step contract declarations: authority, idempotency class, external calls, reuse candidates |
| `plan-review.json` | `.aid-o/work/evidence/{plan_id}/c0/plan-review.json` | Aggregated lens findings; `would_block` bool; protocol-v2 envelope |

The C0 contract-manifest and plan-review artifacts are protocol-v2 envelopes
validated by `aid-protocol-validate.sh`. The provisional graph is deliberately
a small, hash-bound generation artifact (`aid-source-plan-graph/v1`), validated
by the shared source-plan graph parser before it is sealed into C0 input.

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
C0 block of `aid-auto-pipeline.sh`, running for each generated `plan.json`.
Each result is persisted under
`.aid-o/work/evidence/{plan_id}/generation/epics/{epic_id}/c0/contract-validate.json`
**before** its exit code is inspected, so a later phase can never overwrite an
earlier phase's evidence. After every phase is generated, the pipeline runs
`aid-generation-finalize.sh`: it checks the complete phase set against the
source-plan provisional graph and writes a hash-bound receipt. Only that
receipt unlocks FSM init, run creation and queue mutation. `aid-c0-contract.sh`'s
`review` subcommand reads — never re-runs — the persisted result, so the C0
evidence pack always reflects the real gate outcome.

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

---

## C3 Independent Audit (E8)

C3 is a **risk-gated, distrust-based** independent audit stage, delivered across two EPICs
of plan P057: `E-057-1_2` (auditor conversion, FSM hook, policy) and `E-057-2_2` (Curator
sequencing, invalidation-map observe, red-green tests, this release). It sits between DONE-gate
completion and merge, and — unlike the legacy A-J health audit it grew out of — is designed to
be **wrong on purpose in test fixtures** and prove the pipeline actually catches that.

### Protocol-v2 Artifacts

`audit-report.json` and `audit-input-manifest.json` (`defaults/schemas/audit-report.schema.json`,
`defaults/schemas/audit-input-manifest.schema.json`) follow the same protocol-v2 envelope
convention as every other C-stage artifact: a **type-named top-level key**
(`.audit_report`, matching `.semantic_review.findings` / `.ui_fidelity.result`), with
**findings at the envelope top level** (`scripts/aid-protocol-validate.sh`,
`defaults/schemas/aid-protocol-v2.schema.json`) rather than nested under the type key. Every
audit-report.json carries:
- `.audit_report.blocking_findings` (boolean) — the single source of truth `aid-fsm.sh`
  reads for release blocking (no legacy `.md`/`.yaml` `yaml_field()` parsing for C3 runs).
- `.audit_report.provider` / `.model` / `.process_id` — echoed verbatim from the
  Orchestrator's `audit_trigger` at dispatch time, never self-reported by the auditor agent
  (D7 — self-introspection ban; see `agents/auditor.md`).
- `.audit_report.input_manifest_hash` — provenance linkage to the input manifest the audit
  actually ran against.

### `agents/auditor.md` Dual-Mode

The auditor is now **one agent, two protocols**, selected by `audit_trigger.mode` in the
Orchestrator's dispatch input — never self-detected:
- **`mode: "c3"`** — the risk-gated, distrust-based Independent Audit described here. PASS is
  never the default; the auditor must actively fail to find a blocking issue.
- **`mode: "legacy_health"`** — the original trust-based A–J project-health audit, kept as a
  compat section for callers that still want a general health score. `audit_trigger.mode`
  absent from the dispatch input is a dispatch error, not a silent fallback to legacy.

### Independence Detection — `aid-audit-independence.sh`

`scripts/lib/aid-audit-independence.sh detect --required <level>` reports whether the
**required** independence level for the current run's risk profile is actually achievable —
never "what's the best available", matching D8's fail-closed intent. Three levels:
`context_only` (always available, no external dependency), `cross_model` (requires
`AID_AUDIT_ALT_MODEL` env var to differ from the auditor's own configured model),
`cross_provider` (requires Codex binary in PATH + `codex exec --help` sanity + confirmed
`codex login status` + `--json`/`--output-schema` flags present). This script is
**detection-only** — it never invokes `codex exec` with a real prompt and never dispatches a
real audit; unconfirmable or missing signals degrade to `unverifiable`, never to a silent pass.

### `c3-audit-policy.yaml` — Risk Profile → Required Independence

`defaults/policies/c3-audit-policy.yaml` is the authoritative source of
`required_independence_level` per risk profile (D8). Only two profiles carry `c3_required: true`
today: `high` (requires `cross_model`) and `unverifiable` (requires `cross_provider` — a
profile that, by construction, itself will likely report `status: unverifiable` and block,
rather than silently skip the audit). `docs_trivial`/`low`/`medium` are not C3-required.

### FSM Done-Advance C3 Hook (`aid-fsm.sh`)

`cmd_done_advance()` carries a C3 hook (anchored by the search text `C3 independent-audit hook`,
not a line number — it drifted across fix rounds within the same EPIC) that fires only when the
run's risk profile (from `review-profile.json`) is `high` or `unverifiable` — the two
`c3_required: true` profiles. When it fires, it fail-closed blocks release on any of:
- `.audit_report.blocking_findings == true` (critical/high finding),
- `.status == "unverifiable"` (required independence level could not be confirmed),
- missing/unparseable `audit-report.json`,
- missing `.audit_report.input_manifest_hash` (provenance — presence/format check only, see
  "What E8 Does NOT Deliver" below),
- a stale `.revision.head_sha` that no longer matches the run's current HEAD.

No `// false` jq fallback anywhere in this hook — absence or unreadability is always treated as
blocking, never as a silent pass. Runs with no `review-profile.json` at all (pre-C3 runs) leave
the hook a no-op and fall through unchanged to the legacy check.

### Curator Runs Serially After C3 (E-057-2_2 Step 1)

`skills/pipeline.md` now dispatches **Auditor (C3), then Curator — serial, not parallel** (state
table, DONE checklist, and both narrative sequencing notes were updated; see `agents/curator.md`
"Dispatched by... AFTER the Auditor (C3) completes — serial, not parallel"). The Curator reads
`audit-report.json` as a **required** input and dual-emits both the existing
`curator-report.md` (unchanged FSM plan-close/CP4 `.md` checks) and a new `curator-report.json`
carrying `proposal_status: PROPOSALS_READY|NO_PROPOSALS|INPUT_INCOMPLETE` plus
`.curator.audit_report_ref` — the sha256 of the actual bytes of the `audit-report.json` the
Curator consumed. `aid-fsm.sh`'s content-ref sequencing guard validates the integrity chain:
when `curator-report.json` exists, recomputes `sha256sum` of the current `audit-report.json`
and compares it against `.curator.audit_report_ref`; a mismatch or missing field blocks
(fail-closed). When the risk profile requires C3 (high/unverifiable), absence of the entire
`curator-report.json` file also blocks — because Curator is required to dual-emit it.
When risk profile does not require C3 (other profiles), absence is a silent no-op (pre-C3
Curator runs have no JSON file). This proves genuine consumption-order (the Curator actually
read the current audit output), not merely "same HEAD commit" — a same-HEAD check alone
cannot distinguish a Curator that ran before C3 from one that ran after. **`recommended_disposition` (the
approve/reject/defer merge-influence contract consumed by `gate-fixer.md`, `simplifier.md`, and
`pipeline.md`) is completely untouched** — E8 only changes sequencing and vocabulary, never
merge-authority.

### `invalidation-map.json` — Observe-Only (E-057-2_2 Step 2)

`scripts/lib/aid-invalidation-map.sh` is a new, standalone producer (schema:
`defaults/schemas/invalidation-map.schema.json`) that, given an applied fix's changed paths,
derives:
- `affected_c1_checks[]` — a **deterministic subset**: it reads `changed_paths_match` globs
  directly from `delivery-gate.yaml` via `yq` and re-implements the same glob-matching approach
  (rather than calling `aid-delivery-gate.sh`'s private `_check_applicable`, which is not
  designed for reuse — an explicit correction made during E8).
- `affected_c2_modes[]` — **conservative, not precise**: any changed path touching a C2-relevant
  surface marks ALL four canonical C2 modes (local/wiring/behavior/final) as affected. There is
  no path→mode substrate today, so this script is honest about the imprecision instead of
  pretending derivation it can't deliver.

It emits `invalidation-map.json` plus a timeline `log_event` (`invalidation_map_produced`) and is
registered in the enforcement registry as `invalidation_map_observe` (advisory, `status: active`,
same shape as the existing `c2_wiring_gate_observe` pattern). Critically, it **never** invokes
`aid-delivery-gate.sh` or the semantic-review engine itself — `require_rerun` is a flag/request
for a human or a future automation to act on, not a trigger. This is proven behaviorally in
`scripts/tests/bats/test-invalidation-map.bats`.

### What E8 Does NOT Deliver

E8 is deliberately **C3 audit core**, not a full external-audit-and-auto-rerun system. See
[`docs/plans/2026-06-29-BACKLOG.md` § "E8 Deferred"](plans/2026-06-29-BACKLOG.md) for the authoritative list; the
items that most affect how you should read the guarantees above:

- **No real `codex exec` dispatch** — `aid-audit-independence.sh` only *detects* whether
  `cross_provider` independence is achievable (binary present, `--help` sane, login confirmed,
  required flags exposed). The actual subprocess dispatch, output-schema parsing, and merge into
  `audit-report.json` is net-new infra, deferred. A `cross_provider`-required run today stays
  "detected → unverifiable until dispatch is wired", never a false pass.
- **No automatic invalidation-triggered re-run** — `invalidation-map.json` is observe-only.
  `require_rerun` is recorded, never acted on; a new FSM/pipeline re-run primitive is a
  separate, deferred piece of work.
- **No precise C2-mode affectedness derivation** — C2 modes are triggered by plan-graph assembly
  position, not file path; E8 marks affectedness conservatively (see above) rather than
  pretending a path-based derivation that doesn't exist.
- **C4 consumption of release decisions — deferred to E9.** Nothing in E8 wires
  `audit-report.json` / `curator-report.json` / `invalidation-map.json` into an actual
  release-policy decision; that is C4/E9 territory.
- **Merge-authority is completely untouched, deferred to E9.** The Curator's
  `recommended_disposition` auto-approve/reject/defer logic — the actual merge-influence
  contract — is not modified by E8 in any way; only sequencing (Curator after C3) and vocabulary
  (`proposal_status`) changed.
- **No cryptographic hash-equality binding, in either of the two places E8 introduces a
  "prove real consumption via hash" mechanism.** Both `.audit_report.input_manifest_hash` (the
  C3 audit report's own provenance hash, E-057-1_2) and `.curator.audit_report_ref` (this
  EPIC's Curator content-ref sequencing guard) are **presence/format checks**, not a
  cryptographic chain of custody — self-disclosed as deferred (Curator finding IMP-176,
  `E-057-1_2` final report). They prove "a hash of the right shape is present and, for the
  Curator case, matches the current file's sha256" — not a signed or otherwise
  tamper-evident provenance chain.
- **Large legacy A-J project-health audit cleanup** — the converted auditor keeps A-J as a
  legacy-compat section (`agents/auditor.md` "Legacy Compat: A–J Health Audit"); splitting it
  into a standalone project-health tool is deferred.
- **Codex auth detection mechanism is a best-effort probe, not a researched standard** — no
  `codex login-status` convention existed in-repo before E8; the current check treats anything
  other than a clear "Logged in" signal as unconfirmed (fail-closed), and the concrete auth
  probe itself is flagged TBD for follow-up research.

---

## C3 Cross-Provider Dispatch Bridge (P065)

P065 resolves the single largest deferral of the E8 C3 core (see "What E8 Does
NOT Deliver" → *No real `codex exec` dispatch*). Where E8 only **detected**
whether `cross_provider` independence was achievable, P065 ships the real
subprocess dispatch, the trust boundary that turns an untrusted external
response into an `audit-report.json`, and the FSM verification that binds that
report back to the raw Codex output at HEAD. The audit is now performed by an
actual second vendor (Codex), not an in-process Claude `Agent()` call.

### `aid-c3-dispatch.sh` — three subcommands

`scripts/lib/aid-c3-dispatch.sh` is the bridge. It has three deterministic
subcommands, each a distinct stage of the dispatch lifecycle:

- **`build-manifest`** — assembles the hash-manifested Codex brief (the audit
  input): the changed-file set, the run's risk profile, and the versioned prompt
  rendered against the run's facts. The manifest is content-hashed so the audit
  can later be proven to have run against exactly these inputs.
- **`dispatch`** — invokes the real Codex CLI as a fresh subprocess. It is
  **always probed as `cross_provider`** (a different vendor than the auditor's
  own model) and is **non-sticky** — each run re-probes availability rather than
  trusting a cached "codex is here" flag. The untrusted response crosses the
  trust boundary through `_validate_response` (schema + shape, hardened against a
  multi-document-JSON bypass), `_normalize`, and `_write_report` /
  `_write_unverifiable`.
- **`verify [--reference]`** — the provenance + faithful-transform check: it
  re-binds the written `audit-report.json` to the raw Codex output it was
  transformed from, and confirms the report describes HEAD. This is the exit-0
  signal the FSM gate consumes.

### The two contracts

The bridge sits between two schemas:

- **Input manifest** — the `build-manifest` output; the hash-manifested brief the
  Codex process reads.
- **Codex response** (`defaults/schemas/c3-codex-response.schema.json`) — the
  shape the external process must return. A response that fails this schema is
  routed to `_write_unverifiable`, never coerced into a pass.

The versioned prompt template (`c3-audit-prompt-v1.md`) is rendered by the
deterministic `aid-render-prompt.sh`, so the same run facts always produce the
same brief — the prompt is data with a version, not an ad-hoc string.

### Normalization and raw-binding (faithful-transform proof)

The external response is **untrusted input**. `_normalize` maps it into the
protocol-v2 `audit-report.json` envelope; the report retains a binding back to
the raw Codex output so `verify` can prove the report is a **faithful transform**
of what Codex actually returned — not a fabricated or drifted summary. The
faithful-transform binding plus the provenance chain (input-manifest hash →
dispatch → report → HEAD) is what makes the C3 report trustworthy without
trusting the auditor to self-report.

### Independence via provider, not sandbox

Codex reads the repository **read-only** — independence does **not** come from a
filesystem jail. It comes from being a **different vendor running in a fresh
process**: a distinct model family, distinct training, distinct execution
context. A read-only repo view is sufficient because the guarantee being sought
is *independent judgment*, not *containment*. Do not design the bridge assuming a
sandbox boundary; the boundary is the vendor split.

### `c3_on_unavailable` — degradation policy

`c3-audit-policy.yaml`'s `c3_executor` block is executor-first with a
`cross_provider` probe and `c3_on_unavailable: unverifiable`. When Codex is not
available, the run degrades to `unverifiable` (which the C3-required profiles
treat as blocking — fail-closed, never a silent pass). The alternative
`degraded_advisory` disposition — where an unavailable executor downgrades to a
non-blocking advisory instead of blocking — ships in a **later phase of this same
plan**, not here.

### Observe → blocking staging

The FSM `done-advance` C3 hook shells out to `scripts/lib/aid-c3-dispatch.sh verify`, making
the full report↔raw faithful-transform binding a **real, deterministic,
merge-blocking capability** — code, not prose. The shipped default enforcement
stays **`observe`**; the real blocking activation is decided at a later milestone
(**E10**), after calibration, consistent with every other C-stage gate's
observe→blocking promotion pattern. Registered as `c3_cross_provider_dispatch`
(`type: 1`, `surface: internal-guard`) in `defaults/enforcement-registry.yaml`.

---

## C4 Release Policy (E9)

C4 is the release-decision aggregator: the single deterministic place that decides whether an
EPIC's evidence pack is releasable. It is pure bash/jq — **no LLM** — so its verdict is
reproducible and auditable, and it is the first control layer to actually consume the C1/C2/C3
artifacts into a release decision (E8 explicitly deferred that consumption to here).

### Producer: `aid-release-policy.sh`

`scripts/aid-release-policy.sh <epic_id> <run_id> [--out <path>]` reads the run's evidence pack
and emits a protocol-v2 `release_decision` artifact (`release-decision.json`, self-validated
against `defaults/schemas/` via `aid-protocol-validate.sh`). It aggregates a fixed set of
**inputs**, each classified into the `inputs[]` verdict enum, and derives `release_ready` +
`blockers[]` from them:

| Class | Inputs | Effect when absent/failing |
|-------|--------|----------------------------|
| **REQUIRED** | `review_profile`, `delivery_gate`, `semantic_review_final`, `acceptance_evidence`, `gates_report`, `plan_review`, `verification_report` | `blocked` verdict + a `blocking` blocker → `release_ready=false` |
| **PROFILE-GATED** | `audit_report`, `curator_report` | required only when the C3 risk gate is active for the run's `review-profile.json`; otherwise `advisory` |
| **ADVISORY** | `invalidation_map` | never blocks (records `require_rerun` as a request, not an enforcement) |
| **CONDITIONAL** | `reporter`, `simplifier` | see the D11 CONDITIONAL model below |
| **OPTIONAL** | `waiver-*.json` | surfaced in `waivers_applied[]`; **waived ≠ pass** |

`release_ready` is `true` **iff** `blockers` is empty **and** `evidence_verified_at_head` is
`true`. **E9 REQUIRED input checks are presence/freshness-only**: the aggregator verifies each
file exists, is readable JSON, and matches its revision.head_sha (staleness detection). It does
NOT read the content of fields like `semantic_review.status` (status == fail) or check verdict
content — **content-verdict blocking is deferred to E10**. Fail-closed rules the aggregator holds
(each with a red-green case in `scripts/tests/bats/test-release-policy.bats`):

- An empty / whitespace-only / unparseable REQUIRED input is treated as absent (jq 1.6 edge
  case) — never a silent pass.
- The `plan_review` hop follows `epic_input.md`'s `plan_ref` frontmatter to the plan's C0
  evidence; a wrong `plan_ref` → `plan-review.json` not found → blocked.
- Evidence verification runs `aid-evidence-verify.sh --at-head`. A `--at-head` mismatch and a
  git-dirty tree are BOTH classified as a per-check **`fail`** — *not* `unverifiable`. Only a
  genuine tool error (missing harness, exit 2/10/20, unparseable report) degrades to
  `unverifiable`.

### Dual-run consumer: the `done-advance` hook

The FSM `done-advance review → release` transition runs C4 in an **observe** dual-run hook
alongside the legacy release checks and emits a `release_policy_dual_run` timeline event
comparing the two verdicts. The event carries `head_sha`, `match`, `legacy_ready`, and a
never-empty `divergence_class` from a total 8-value taxonomy: `none`, `verification_only`,
`reporter_missing`, `simplifier_missing`, `required_input`, `c4_permissive`, `mixed`,
`unclassified` (the fail-closed floor — the classifier never returns empty/null, even on
aggregator crash).

The hook is **observe-only by default** (divergence never blocks the transition). Setting
`RELEASE_DECISION_POLICY` to a policy file with `enforcement: blocking` flips it to a live
blocking branch. A broken aggregator emits `result: crash` + `divergence_class: unclassified`
and done-advance **still passes** (`set -e` safe). When a hard-exit legacy gate (tiered
compliance, streamlined-integration, cp4-curator) preempts the C4 slot, a
`release_policy_preempted` event records which gate fired instead. These two observe events plus
the force→waiver writer are registered in
[`enforcement-registry.yaml`](../plugins/aid-orchestrator/defaults/enforcement-registry.yaml)
as `release_policy_dual_run` / `release_policy_preempted` / `force_writes_waiver`.

### PM handoff: `aid-pm-brief.sh`

`scripts/aid-pm-brief.sh <evidence_dir> [--out-dir <path>] [--validate]` is a pure bash/jq
projection of `release-decision.json` into the PM machine handoff — it reads **exactly one**
evidence file (the decision) and no siblings (cycle-break). It emits `pm-decision-brief.json`
(protocol-v2 `pm_decision_brief`) + a human `pm-summary.md`, then does one idempotent patch-back
of `pm_brief_status` into the decision. The human summary shows evidence / Reporter / Simplifier
/ waiver status **in full even for an auto-merge run**, so an auto-merge is never silent — but
see the honest phasing limitation below.

### D11 — release-decision state model

D11 is the set of state fields the C4 decision carries so the PM handoff is legible without
re-deriving anything. All live under `release_decision` and are echoed 1:1 into
`pm-decision-brief.json`:

| Field | Values | Meaning |
|-------|--------|---------|
| `pm_brief_required` | always `true` | every release requires a PM brief |
| `pm_brief_status` | `pending` → `generated` \| `failed` \| `incomplete` | brief lifecycle (see phasing) |
| `evidence_verified_at_head` | boolean | did `aid-evidence-verify.sh --at-head` pass at current HEAD |
| `evidence_verification_status` | `pass` \| `fail` \| `unverifiable` | fail (mismatch/dirty) vs unverifiable (tool error) — distinct |
| `reporter_status` / `simplifier_status` | `pass` \| `fail` \| `missing` \| `disabled` \| `not_applicable` | CONDITIONAL 5-enum |
| `merge_mode` | `auto` \| `manual` \| `blocked` | informative routing, NOT an enforcement gate |
| `delivered_summary_ref` | path \| `null` | already-resolved pointer, echoed not re-opened |
| `summary_for_pm` | string | mechanical one-line template, no LLM |

**Reporter / Simplifier CONDITIONAL model.** Reporter and Simplifier are **plan-boundary** roles.
Their C4 status is decided over the SAME underlying signals the FSM's
`fsm_eval_delivery_report_present` / `fsm_eval_simplifier_present` compliance evaluators use (the
`ca-review-complete` marker, the `execution.yaml` enable toggle via
`scripts/lib/aid-review-signals.sh`, and — for Reporter — the delivery report's
`_test_evidence[]` on disk):

1. **Off the plan boundary** (no `ca-review-complete` marker) → `not_applicable`
   (`reason: not_plan_boundary`). Does NOT affect `release_ready` — the per-EPIC case.
2. **On the boundary but disabled** (`reporter.enabled:false` / `simplifier.enabled:false`) →
   `disabled`. Does NOT affect `release_ready`.
3. **On the boundary, enabled, artifact absent** → `missing` → a `blocking` blocker →
   `release_ready=false`.
4. **On the boundary, enabled, artifact present + valid** → `pass`.

The 5-enum maps onto `inputs[]` via `_status_to_verdict` (`missing→blocked`,
`disabled`/`not_applicable→advisory`), mirroring how the existing compliance-gate evaluators
collapse `disabled`/`not_applicable` into the same non-blocking result — C4 adds the richer
5-enum on top without changing that regression surface.

**Auto-merge-brief phasing — the honest L1-F2 limitation.** `pm_brief_status` is **always
`pending`** at C4-write time — even for a `release_ready:true` / `merge_mode:auto` decision. The
transition to `generated` happens **later**, when `aid-pm-brief.sh` runs and patches the field
back (`failed` on a write-failure seam; `incomplete` on a missing-state / echo-mismatch). The
original invariant *"release_ready must not be true without a `generated` brief"* is **not
implementable against its own sequencing** (CP1 finding L1-F2): C4 writes the decision *before*
the brief step runs. What the mechanism guarantees instead: the field NEVER silently becomes
`generated` (only a successful brief run patches it, so a `pending` after a completed
done-advance is itself a failure signal); a read-only evidence dir correctly leaves it `pending`
rather than faking `generated`; and `merge_mode` is informative — nothing here blocks a merge
that lacks a brief.

### What E9 core Does NOT Deliver

Per Principle #1 (a detector is not enforcement), E9 core delivers the C4 **mechanism** but not:

- **No structural merge gate on the brief.** Nothing in `aid-pm-brief.sh` or `aid-fsm.sh` blocks
  a merge that lacks a PM brief. "Auto-merge never silent" is an E9 *pipeline convention*, not a
  structural guarantee. Enforcement (a `--validate`-gated MERGE that fails closed when
  `pm_brief_status != generated`) is deferred to **E10**.
- **Dual-run defaults to observe, not blocking.** The `release_policy_dual_run` hook records
  divergence; it does not enforce C4 until a project opts in via
  `RELEASE_DECISION_POLICY: enforcement: blocking`. C4 becoming the sole release authority is E10.
- **PROFILE-GATED inputs depend on live review-profile production.** The C3 risk gate that makes
  `audit_report` / `curator_report` REQUIRED only fires when `review-profile.json` is present
  (**IMP-177**, now resolved-by-P059 for the C3-activation half; end-to-end metric verification
  is E10).
- **Evidence-freshness binding is presence/format, not cryptographic** — `head_sha` /
  `input_manifest_hash` are checked for presence and staleness, not recomputed-and-compared for
  hash equality (**IMP-176**, E10 territory).
- **IMP-179 (subagent protocol-cache staleness) is unresolved** — Curator/Auditor subagent
  system prompts resolve from the installed plugin cache, not the live repo, so an `agents/*.md`
  change made inside an EPIC is not picked up by that same EPIC's own DONE-phase review dispatch
  (evidenced 3×). Paste the changed protocol verbatim into the dispatch prompt until a
  dispatch-time freshness-hash check lands.
- **IMP-191 (finding-fingerprint collision) is deliberately deferred from P059** —
  `fingerprint_audit_report()` in `scripts/lib/aid-finding-fingerprint.sh` joins its 7 fields
  with a raw `0x1F` byte and is not injective; it is a determinism/tamper-evidence check (no
  HMAC), so this is a soundness gap in the binding guarantee, not a new privilege escalation.

---

## Plan-level closure (IMP-232, v2.58.0)

Canonical, evidence-anchored, PUBLIC-SAFE plan lifecycle. Source of truth is the
validated evidence bundle (git merges + review reports + evidence); the git-tracked
`.aid-lifecycle/` artifacts are the durable materialization that survives a clean
clone and the eco-dev↔eco-prod mirror.

- **Library:** `scripts/lib/aid-lifecycle.sh` (sourced by `aid-fsm.sh` for the D1
  init gate; and by the `aid-lifecycle.sh` CLI). Key functions:
  `aid_repo_id` (stable UUID, immutable after first creation),
  `aid_plan_closure_state` (state resolver),
  `aid_lifecycle_parse_legacy_epics` (STRICT `**EPIC N:**`/`**EPIC N / Backlog:**`
  grammar; anything else ⇒ `legacy-unverifiable`),
  `aid_lifecycle_plan_close`, `aid_lifecycle_plan_reconcile`,
  `aid_lifecycle_bind_delivery` (strict historical binding),
  `aid_lifecycle_validate_artifact` (schema + public-safe gate).
- **CLI:** `scripts/aid-lifecycle.sh` — `repo-id | state | declared | parse-legacy |
  validate | publicsafe | plan-close | plan-reconcile | target-branch`.
- **Artifacts (git-tracked, public-safe):** `.aid-lifecycle/repo-identity.yaml`,
  `.aid-lifecycle/manifests/P<NN>.yaml`, `.aid-lifecycle/receipts/P<NN>.yaml`.
  Schemas: `defaults/schemas/plan-lifecycle-{identity,manifest,receipt}.schema.json`
  (`additionalProperties:false`). The **public-safe contract is binding**: these files
  carry ONLY technical fields (repo/plan/EPIC IDs, state, delivery/review SHAs,
  normalized verdict, blocker count, schema/tool version, timestamps, hashes) — NEVER
  report bodies, findings text, prompts, agent output, absolute/local paths, secrets,
  PII, customer names, or free-form waiver reasons. `aid_lifecycle_validate_artifact`
  MUST pass (schema + secret/abs-path/free-text-key net) before any artifact is committed.

### Enforcement registered (per AID-v3-principles §1 — Detector needs Enforcement)

| Enforcement | Mechanism | Surface |
|-------------|-----------|---------|
| Dependency-scoped init gate (D1) | `aid-fsm.sh cmd_init` — hard-fail on a structured `depends_on_plans` target whose derived state ≠ `closed` (both former cross-plan regions removed); `--force`-overridable + audited | `init` PRECONDITION FAIL |
| `closed` requires committed+reachable receipt | `aid_lifecycle_receipt_durable` (`git cat-file` on `target_branch`); a staged/uncommitted receipt is `closing_pending_commit`, never `closed` | state resolver |
| Required-only denominator + strict legacy grammar | `aid_lifecycle_parse_legacy_epics` (ambiguous ⇒ `legacy-unverifiable`, never a guess); backlog EPICs recorded but excluded from closing | resolver / reconcile |
| `delivered` needs provenance-bound merge | `aid_lifecycle_bind_delivery` — unambiguous merge reachable from `target_branch` + reviewed-head ancestor + accepted audit; a well-named merge alone never closes | reconcile |
| Public-safe artifact gate | `aid_lifecycle_validate_artifact` before every `.aid-lifecycle/` commit | plan-close / reconcile |
| per_step_scoping authoritative-block-first | `gates/aid-contract-validate.sh` Check 1 (shared `lib/aid-scoping.sh`); R1-R7 | contract gate |

### Known boundaries

- **Two-phase delivery has no new FSM hook.** Phase-1 reviewed-head provenance is the
  existing `audit-report.json` in gitignored evidence; Phase-2 (bind `delivery_sha` +
  commit the git-tracked manifest/receipt) happens ONLY in the orchestration-layer
  `plan-close`/`plan-reconcile` commands, so the FSM never commits or dirties the tree.
- **`ca-review-complete` marker is not removed** — the new closure model supersedes it
  as the D1 source of truth, but the legacy per-EPIC marker (written by
  `aid-fsm.sh cmd_plan_close`) still exists for backward-compatible consumers during
  the transition; readers of closure state use the receipt-first resolver.
- **Squash/rebase delivery workflows** weaken the historical binding's merge-topology
  assumption; the receipt's durable per-EPIC provenance is the fallback, and an
  unverifiable binding yields `legacy-unverifiable` rather than a guess.

---

**Last Updated:** 2026-07-27

## The plan-boundary layer (P064 + P068)

*Added 2026-07-27. This file is git-tracked — it is the negation-free exception
to `.gitignore`'s `docs/` rule, so unlike the roadmap and design notes beside it
this text IS distributed. An earlier draft of this section claimed the opposite;
it was wrong, and the claim is removed rather than softened.*

If you are adding anything to AID that decides **when** work is released, read
this first.

### What changed

Releases used to happen per EPIC: each EPIC bumped a version, tagged, and merged
to the target branch on its own. The consequence was structural, not cosmetic —
what reached the target branch was never reviewed as a whole, and "the plan is
done" was an assertion rather than something the system could verify.

The plan-boundary layer moves the release to the plan. In `plan_branch` mode an
EPIC merges into a plan branch and releases nothing; the plan freezes a candidate
commit, runs its gates once against it, has the specialists review it once, takes
one PM authorization naming that candidate and the approved target head, and
merges with a compare-and-swap. Only then can it be declared closed, and only on
the strength of a receipt committed in git.

### The three rules a contributor has to respect

**1. The declaration must be durable, not merely written.** A plan's mode lives
in `.aid-lifecycle/manifests/<plan_id>.yaml`, and every reader resolves it from
the TARGET BRANCH's committed tree — not from the worktree copy. Writing the
field with `yq -i` and stopping there produces a plan that declares nothing where
it counts. This exact bug was introduced twice during P068's own implementation,
in two different files, and caught both times by read-back checks. If your code
writes anything under `.aid-lifecycle/`, commit it and read it back from the ref
before reporting success.

**2. Nothing may move the target ref except a compare-and-swap.** There are two
such paths (`aid-plan-fsm.sh`'s merge publish and `aid-lifecycle.sh`'s plumbing
commit), and both pass the expected old value to `git update-ref`. If you add a
third, it must do the same: a rejected swap has to leave the branch
byte-identical, and the merge commit must exist only as a dangling object until
the swap succeeds.

**3. "Cannot verify" is never "verified".** Every guard on this path fails
closed. A missing frozen head, an absent tag record, an unrecognised closure
state, an unresolvable ancestry, a missing lifecycle manifest under
`plan_branch` — each blocks. If you find yourself writing a branch that passes
because a field was empty, you have found the bug this layer exists to prevent.

### Where the enforcement is recorded

`plugins/aid-orchestrator/defaults/enforcement-registry.yaml` is the tracked
authority. Every detection capability you add needs a row there with its type,
source, severity, surface and verdict, and `test-control-boundary.sh` asserts
that the required rows exist, that planned rows stay planned, and that the header
total is derived rather than hand-written.

### Roadmap position

E9.5 sits between E9 and E10: the plan-boundary layer is its own phase, not a
sub-task of E9, because E10's calibration promotion depends on the plan-final
cadence existing. The specialist stack is dispatched once per PLAN, not once per
EPIC — if you are budgeting dispatches, budget them per plan.

---

## Test-portfolio decision quality (P072)

Fifteen enforcements were added by P072. This section is a contributor's index
to them; the parallel-safety rules live on one page of their own, in
[`P072-authority-boundary.md`](plans/P072-authority-boundary.md), and are not
restated here — one source, linked to, rather than two that drift.

### The decision artifact

A `full` audit produces `decision.json` (`aid-test-audit-decision-v1`) beside
its findings. It carries `audit_status`, one terminal disposition per run unit,
the portfolio arithmetic, the proposed actions with their impact, the
parallelization lanes, and what remains unresolved.

Two properties make it worth having, and both are enforced rather than
conventional:

- **`audit_status: incomplete` blocks the handoff.** `--write-plan` and the
  same-conversation continuation both refuse. Building a remediation plan on
  the part an audit skipped makes the skipped units read as
  examined-and-healthy.
- **`impact.kind` cannot overstate.** `measured` needs two comparable runs;
  `estimated` needs its assumptions stated; `unknown` may carry a `before_ms`
  but must then qualify it, because a bare number on an unfinished run reads as
  a measured total.

### The fifteen enforcements

| Row | What it stops |
|---|---|
| `test_audit_incomplete_blocks_write_plan` | A remediation plan built on an audit that did not finish deciding |
| `test_audit_disposition_reconciliation` | A partial shard result rendering as a verdict on the whole portfolio |
| `test_audit_coverage_reduction_requires_falsification` | Deleting a test on `unproved` — which is not an argument for deletion |
| `test_audit_clone_config_precondition` | Auditing a config-less clone, which silently drops every declared-command gate |
| `test_audit_aggregate_unparsed_fails` | An unparseable suite result counting as zero tests and passing |
| `test_audit_inventory_arithmetic_guard` | A run unit vanishing between adapters |
| `test_audit_profile_ingestion_fail_closed` | A corrupt profile receipt becoming an empty action list that reads as "nothing needed doing" |
| `test_audit_profile_selection_owed` | A slow suite the audit selected for diagnosis, and nobody diagnosed |
| `test_audit_profile_supervised_execution` | A deadline kill filed as an operator cancel — both arrive as exit 143 |
| `test_audit_resource_map_shared_evidence` | A shared-state claim resting on a pattern match rather than read source |
| `test_audit_pilot_evidence_bound` | A lane promoted on a pilot that was retried until it went green |
| `test_catalog_parallel_provenance_binding` | A `safe` status outliving the content it was verified against |
| `test_lane_single_parallel_authority` | Two consumers disagreeing about the same unit |
| `test_audit_lane_membership_exact` | A lane promoted on evidence gathered for a different set |
| `test_execution_no_double_dispatch` | A run unit executed twice in one gate run |

Each row records its **recovery behaviour**: what an operator actually does
when it fires. A blocking enforcement with no stated recovery is a wall, and
the registry test refuses a row that omits it.

### The execution ledger, and its fourth emission path

`test_execution_no_double_dispatch` is worth reading about before you touch the
gate runner. The ledger records one entry per run unit ACTUALLY DISPATCHED, and
it has **four** emission points, not the three obvious ones:

1. `aid-bats-parallel-lane.sh` — pool, sequential and boundary buckets alike
2. `run-all-tests.sh` — one per suite
3. `aid-test-scheduler.sh` — one per scheduled unit
4. `aid-run-gates.sh` — for any gate whose command invokes a runner **directly**

The fourth is the one that matters and the one easiest to leave out. This
repository HAD a gate that ran `test-aid-fsm.bats` on its own while the
parallel pool ran it too, with the `full` and `release` profiles including
both, so that file executed twice on every full run. With only the fan-out
points instrumented, the ledger would have recorded one entry for it and
reported zero duplicates — certifying as clean the exact defect it was built to
detect. It found it instead, and `bats_fsm` is now absent from those two
profiles; the red proof lives in a fixture so fixing the waste did not blind
the check.

The third point was also missing for a while, which is worth knowing because it
failed quietly: units the SCHEDULER ran were absent from the accounting
entirely, so a unit run by both the scheduler and a gate looked like a unit run
once. The scheduler now appends BEFORE launching each unit, and a failed append
cancels that dispatch — recording an execution that then does not happen is
recoverable; running one that nothing records is not.

There is deliberately **no membership exemption**. Exempting "the pool gate
contains this unit" was implemented, and it silenced that same defect. Each
dispatch point appends once per execution it actually performs, so two entries
under two gate ids are two executions; `--contains` is recorded for a reader
but suppresses nothing.

**Everything inside an accounted run is fail-closed.** A failed open, a failed
append, a ledger path that names a file that is not there, a close that cannot
be evaluated — each fails the gate run, because a ledger with a gap reports zero
duplicates exactly like a clean one. There is no `|| true` on any emission
path, and there used to be. The ONE permitted no-op is a dispatch point with no
ledger path at all: a developer running a suite by hand has no run to account
for. "The path was set but the file is missing" is NOT that case, and was once
treated as though it were.

What DOES excuse a repeat is a declaration made when it happens.
`--execution-kind normal|retry|escalation` marks a single append;
`AID_EXECUTION_KIND` marks a whole subprocess, which is how P069's escalation —
which re-invokes the gate runner with the parent's ledger inherited — avoids
being recorded as an accident. Declared repeats appear in the summary as
`deliberate_repeats`: never failing, never invisible, because a rerun somebody
asked for still costs the wall clock twice. The default is `normal`, so silence
is not a declaration and a forgotten mark stays a defect.

### Adding to this area

The command file (`commands/aid-audit-tests.md`) is the operator contract and
is NOT on the lint gate's grandfathered list — keep it clean rather than adding
it. The agent card is verified by the golden-prompt test instead, because
linting it would demand frontmatter fields that are meaningless for a
dispatched agent.
