# Extending AID — a contributor reference for enforcements

This is the one place that answers: *"I want to add a new agent / gate / check /
audit signal — where does each piece go, and what makes it real instead of
decoration?"* It distils the binding conventions from
[`docs/plans/AID-v3-principles.md`](plans/AID-v3-principles.md) §1 and the P041
governance recommendation
([`docs/plans/AID-audit-2026-06/03-governance-recommendation.md`](plans/AID-audit-2026-06/03-governance-recommendation.md)),
and ends with the areas added since, one section per plan.

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
| 8 | Hook-enforcement (git) | `defaults/hooks/*` + `agent-protocol.md` git discipline |
| 8h | Hook-enforcement (harness) | `defaults/hook-registry.yaml` (self) + the surface the rule is about — see "Adding a harness hook rule" |
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

## Adding a harness hook rule (P086)

A harness hook is our code that an agentic CLI runs in its own lifecycle —
before a tool call, on a session start, at the end of a turn. AID has **one**
entry point (`plugins/aid-orchestrator/scripts/aid-hook.sh`) and **one**
registry (`plugins/aid-orchestrator/defaults/hook-registry.yaml`). Adding
behaviour is a row plus a handler; it is never an edit to the entry point, and
if it turns out to need one, the layer is wrong rather than the rule.

**Four steps.**

1. **Write the handler.** A bash function in a lib under `scripts/lib/`. It
   reads the event JSON on stdin and exits `0` (pass, stdout is injected into
   the prompt), `2` (refuse, reason on stderr) or `3` (not applicable, reason on
   stderr). Anything else is a broken rule. It must be callable from a fixture
   with no live session — that is what makes it testable.

2. **Add the row.** `id`, `event`, `owner`, `degree`, `failure`, `timeout_s`,
   `lib`, `handler`, `description`. Every field is load-bearing; the two that
   are most often got wrong:

   - `owner` (`controller` / `agent` / `any`) is **mandatory**. Plugin hooks run
     inside subagents too, so a default of "any" silently widens every rule.
   - `failure: closed` is the ONLY declaration that may stop a turn, and only
     while the canary has verified this installation. A `failure: open` row that
     exits 2 is a misdeclaration: the refusal is recorded and ignored.

3. **Declare the event** in `plugins/aid-orchestrator/hooks/hooks.json` if it is
   not already there. Both Claude Code and Codex read a plugin-root
   `hooks/hooks.json` in the same shape. Prefer NO matcher and let the handler
   decide from the payload — which start sources a rule cares about is a
   registry decision, and a matcher whose values you have not measured silently
   never fires.

4. **Register the enforcement**, with `enforcement_degree` and
   `not_guaranteed`. The degree is the ecosystem scale
   (`/ecosystem/specs/agent-hooks/`): **1** code decides and the model has no
   vote; **2** code checks the answer and refuses it; **3** code delivers data
   into the prompt — a delivery, *not* a guarantee; **4** prose. A row without a
   degree has not said whether it enforces or merely delivers, and
   `not_guaranteed` is where the honest remainder goes. Write it before you are
   asked; every P086 row has one.

**Two things a hook may never be.** It may not write into a repository
(`/ecosystem/specs/agent-hooks/` rule 6) — hook-side state goes to the session
store via `scripts/lib/aid-session-store.sh`, outside every working tree. And it
may not be the *only* layer: `Stop` does not exist in Codex's review modes and
never arrives from a killed session, so anything that matters gets a file check
after the CLI returns (`scripts/aid-turn-gate.sh`) with the hook as the earlier
catch. A rule that lives only in `Stop` has holes exactly where it is needed.

**Nothing claims hooks are in force except the canary.**
`scripts/aid-hook-verify.sh --canary` runs a real session and requires AID's own
canary rule to have left a *successful* record. Until it has, every fail-closed
row degrades to fail-open and the degradation is audited. Cite the canary; never
assert enforcement on the strength of a file being in place.

### Phase working copies

`aid-plan-fsm.sh plan-scratch <plan_id> --phase brainstorm|generation` gives a
planning phase its own linked worktree and prints the directory to work in — or
the primary checkout, with a warning, when git will not hand out a second tree.
It never blocks: a stream that cannot be parallel is better than a stream that
cannot start.

What it isolates is the **tree**. State does not fork and is not meant to:
`.aid-o/` is gitignored, so it is never checked out into a linked worktree, and
`scripts/lib/aid-roots.sh` resolves every state read to the primary checkout
from whichever tree the command runs in. One plan-id counter, one run history,
one evidence tree.

**What is NOT built:** reading gate configuration from the branch while state
comes from the primary checkout. It is recorded as `gate_config_from_branch`
(`status: planned`) in the enforcement registry with the two measured facts that
block it — `.aid-o/` never reaching a worktree, and hook/gate configuration read
out of a working tree making a downloaded repository able to run code. The drift
it was aiming at (controller code from the installed plugin cache while the
branch's code is under test) is owned by `scripts/lib/aid-cache-preflight.sh`.

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
6. **Say who checks it AFTER generation, and who checks it at development
   runtime** — the `runtime_check:` field (P085). Where a runtime check is not
   needed, write down WHY. "Nobody, and here is the reason" is an answer;
   an empty field is how a plan-time check silently becomes the only check
   anything ever had.

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

## Three obligations a plan carries about its own grounding (P085)

These three are worth knowing before you add anything near plan authoring,
because each one already owns a question a new check would otherwise re-open.

**`plan_reuse_evidence` — did the step look for what already exists?**
A step whose `Files:` carry a `Create:` bullet owes a `**Reuse check:**` field:
the read-only search it ran (`grep`/`rg`/`ls`/`find`/`git grep`, nothing that
pipes or chains) and which of four results it got. `aid-plan-lint.sh` REPLAYS
the command and compares the file count with the claim — the difference between
evidence and a formality. What replay cannot show is whether the search was
WIDE enough; that is the `reuse` reviewer of plan review (CP1). When you
add a check about duplication, decide which of those two halves it belongs to
and extend that one; a third place to ask the same question is the very shape
`plan_reuse_evidence` exists to prevent (see its `N+1 rule`).

**`plan_standards_named` — which ecosystem standards bind these paths?**
`scripts/lib/aid-standards-map.sh` is the ONLY file in AID that reads a foreign
live document, and it exports nothing but a list of standard ids, so the map's
format can age without touching anything else. Do not copy the map into the
repo — a copy is a second map that disagrees with the first, and do not put
path patterns in the reader: they live in the map's own `tag_paths` block, so a
project with its own map is judged by its own layout rather than by this
repository's. Its three states are load-bearing: not configured (owes nothing),
configured-but-unreadable — which now includes a map with no `tag_paths` and a
map declaring an unknown `schema_version` — (broken environment, blocking), and
configured-and-binds-nothing (owes nothing, and that is correct).

**`plan_parallel_group_disjoint` — what may run at the same time?**
Each step declares a wave; `aid-plan-parallel-check.sh` proves two steps in one
wave do not name the same file. It is enforced from
`aid-generation-readiness.sh` rather than from the lint, because disjointness
is a property of the step graph. Since P087 the brake is off: the same check,
scoped to one wave (`--group`), is what the dispatch decision asks before a wave
runs concurrently, and it judges declared interfaces as well as files.

All three run through the plan lint rather than as new checkers. Before adding
a *fourth* plan-time authority, check whether what you want is a row in the
obligations table (`skills/plan-writing.md` §"What every plan owes") plus a
branch in the lint.

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
- `fsm_check_review_round` — `increment-step` and `done-advance` refuse without a closed,
  passing review round at HEAD; fails closed.

**When to choose which.** Use the severity-layer when the signal is new and you
want it advisory-then-promotable (the responsible default under §1's
tiered-severity caveat — hard-blocking on first deployment floods false
positives and trains reflexive `--force`). Use a hard-die only when an immediate
stop is correct regardless of empirical track record (an integrity invariant, a
structural impossibility).

**Plan-boundary vs per-EPIC placement.** A plan-level check belongs to a `plan-finalize`
stage, **not** to a per-EPIC `done-advance` — an intermediate EPIC of a `plan_branch` plan
skips the release stack, so a check placed there never runs for the plan.

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
- the **review rounds**, whose answers are bound to a dispatch bracket, and
- **honest agent instructions** in `pipeline.md` (MUST-dispatch /
  MUST-NOT-self-review).

Hard, non-fabricatable provenance enforcement (the interval-bracket against a
real dispatch timeline) requires **opt-in `subagent` mode**. Don't design a new
check assuming the timeline is there by default — it isn't.

---

## Enforcement Homes Reference

When adding a new detection capability, register it in `defaults/enforcement-registry.yaml` with:
- `id`: unique snake_case identifier
- `type`: `fsm_precondition` | `lm_judgment_advisory` | `out_of_band_hard_fail` | `pm_confirmation_gate`
- `enforcement_mechanism`: the exact mechanism (see AID-v3-principles.md §1)
- `test_anchor`: path to the bats/sh test that proves it works
- `deadline`: ISO date after which the TTL guard flags it if not tested

See also **Plan review (CP1)** in this file for how a plan is reviewed before
generation.

---

## AID Control System v2 Protocol (enforced vs reference)

AID Control System v2 introduces a shared protocol v2 envelope that all control mechanism artifacts (C0-C4) will carry. The definitions live in `defaults/schemas/`.

### Schema files
- `defaults/schemas/aid-protocol-v2.schema.json` — canonical envelope schema (JSON Schema draft 2020-12); every field annotated `$comment: enforced` or `$comment: reference`
- `defaults/schemas/README.md` — enforced-vs-reference table with `aid-protocol-validate.sh`'s exact enforcement scope
- 7 type-specific schemas: `plan-graph.schema.json`, `contract-manifest.schema.json`, `review-profile.schema.json`, `ui-fidelity.schema.json`, `semantic-review.schema.json`, `acceptance-evidence.schema.json`, `release-decision.schema.json`, `pm-decision-brief.schema.json`. The artifact types of retired producers (`audit_report`, `audit_input_manifest`, `curator`, `delivery_report`, `delivery_gate`, `c3_dispatch`) stay in the validator so older evidence still validates; their schema files are gone.
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

## Plan review (CP1)

Before EPIC generation a plan is put to six reviewer roles in rounds; P093
replaced the lens chain, the Codex loop, its ledger and the ceremony bands with
this one path. The pieces, and what to change where:

| Piece | File | What it owns |
|---|---|---|
| the roles and the evidence rule | `skills/plan-review-roles.md` | each role's questions and stop rule; what a finding must carry |
| the answer shape | `defaults/schemas/plan-review-finding.schema.json` | the role enum and the command/evidence patterns the scripts read |
| the prompt | `defaults/prompts/plan-review-prompt-v1.md` | the fixed header every reviewer gets |
| the configuration | `defaults/policies/review-checkpoints.yaml` → `plan_review` | providers, models, rounds, `min_answers` |
| the rounds | `scripts/aid-plan-review-round.sh` | prepare, dispatch, collect, close, retry, fix-check, dispute, finalize, override |
| the adjudicator | `scripts/aid-plan-review-adjudicate.sh` | proof check, merge, yield, rejection reasons |
| the gate | `scripts/aid-cp1-gate.sh` | the evidence generation needs |
| the procedure | `commands/aid-plan.md` "Plan review (CP1)" | what the controller runs, command by command |

**Changing a role's questions** is a text change in the roles skill; the prompt
picks it up on the next `prepare`. **Adding or removing a role** touches the
schema enum, the skill and the configuration together: the config validator and
`test-plan-review-schema.bats` refuse them out of step. **Changing what a
finding must carry** is a schema pattern change; the answer check and the
adjudicator read the pattern from the schema, never from a copy.

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

It is wired as a BLOCKING step of `aid-auto-pipeline.sh`, running for each
generated `plan.json`.
Each result is persisted under
`.aid-o/work/evidence/{plan_id}/generation/epics/{epic_id}/c0/contract-validate.json`
**before** its exit code is inspected, so a later phase can never overwrite an
earlier phase's evidence. After every phase is generated, the pipeline runs
`aid-generation-finalize.sh`: it checks the complete phase set against the
source-plan provisional graph and writes a hash-bound receipt. Only that
receipt unlocks FSM init, run creation and queue mutation.

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

## Closing a plan (P096)

A `plan_branch` plan is closed by `aid-plan-fsm.sh plan-finalize` in four stages — `freeze`,
`gates`, `produce`, `decide` — with the whole-plan review round (`cp7`, three roles, run by
`aid-review-round.sh`) between `produce` and `decide`. The controller instruction is one
section, `commands/aid-run.md` "Closing a plan (plan-final)"; nothing else restates it.

What a contributor has to respect:

- **One attempt, one candidate.** A fix moves the candidate, so it mints the next attempt.
  `freeze` classifies what changed (`fix-class.json`) and keeps every result the change cannot
  have affected: a gate row whose input paths and definition did not move is copied with
  `reused_from`, a reviewer role whose feeds did not move and who had no finding is carried.
- **The decision reads a closed inventory.** `aid-release-policy.sh` decides from
  `gates_report`, `final_review` (the closed `cp7/rounds.json` at the candidate), `obligations`,
  the review profile, the acceptance evidence and the semantic file the round writes. Every file
  a stage writes is recorded in `stage-writes.jsonl`; a decision input edited by hand is refused
  by name.
- **Every refusal names the next command** (`_pfsm_refusal_next`), and says when the PM is the
  way out.
- **Removed, with successors on record** (`reference/review-successors.md`): the reporter, the
  curator, the auditor's plan-final (C3) contract and its Codex bridge, the simplifier as a
  required step, CP4, CP5, the C1 delivery gate and the dual run. The Codex transport they
  shared is `scripts/lib/aid-codex-transport.sh`.

---

## The release decision (`aid-release-policy.sh`)

The release-decision aggregator is the single deterministic place that decides whether an
EPIC's — or, at a plan's close, a plan's — evidence pack is releasable. It is pure bash/jq —
**no LLM** — so its verdict is reproducible and auditable.

### Producer: `aid-release-policy.sh`

`scripts/aid-release-policy.sh <epic_id> <run_id> [--out <path>]` reads the run's evidence pack
and emits a protocol-v2 `release_decision` artifact (`release-decision.json`, self-validated
against `defaults/schemas/` via `aid-protocol-validate.sh`). It aggregates a fixed set of
**inputs**, each classified into the `inputs[]` verdict enum, and derives `release_ready` +
`blockers[]` from them:

| Class | Inputs | Effect when absent/failing |
|-------|--------|----------------------------|
| **REQUIRED** | `review_profile`, `semantic_review_final`, `acceptance_evidence`, `gates_report`, `plan_review`, `verification_report`, `final_review` (the closed `cp7/rounds.json` of a plan, the `cp3` index of an EPIC), `obligations` | `blocked` verdict + a `blocking` blocker → `release_ready: false` |
| **OPTIONAL** | `waiver-*.json` | surfaced in `waivers_applied[]`; **waived ≠ pass** |

`release_ready` is `true` **iff** `blockers` is empty **and** `evidence_verified_at_head` is
`true`. **E9 REQUIRED input checks are presence/freshness-only**: the aggregator verifies each
file exists, is readable JSON, and matches its revision.head_sha (staleness detection). It does
NOT read the content of fields like `semantic_review.status` (status == fail) or check verdict
content — **content-verdict blocking is deferred to E10**. Fail-closed rules the aggregator holds
(each with a red-green case in `scripts/tests/bats/test-release-policy.bats`):

- An empty / whitespace-only / unparseable REQUIRED input is treated as absent (jq 1.6 edge
  case) — never a silent pass.
- The `plan_review` input follows `epic_input.md`'s `plan_ref` frontmatter to the plan's
  sealed `generation/generation-authority.json` (plan review passed, or the PM's recorded
  force); a wrong `plan_ref` → no authority found → blocked. Plan mode reads it by plan id.
- Evidence verification runs `aid-evidence-verify.sh --at-head`. A `--at-head` mismatch and a
  git-dirty tree are BOTH classified as a per-check **`fail`** — *not* `unverifiable`. Only a
  genuine tool error (missing harness, exit 2/10/20, unparseable report) degrades to
  `unverifiable`.

### Consumer: the `done-advance` hook

In `legacy_epic_release_mode` the FSM `done-advance review → release` transition runs the
aggregator and logs a `release_decision` timeline event (`release_ready`, `exit_code`,
`enforcement`, `head_sha`). **Observe by default**; a `RELEASE_DECISION_POLICY` file with
`enforcement: blocking` turns `release_ready: false` into a refusal. A crashed aggregator is
logged and never blocks. For a `plan_branch` plan the decision is `plan-finalize --stage decide`.

### PM handoff: `aid-pm-brief.sh`

`scripts/aid-pm-brief.sh <evidence_dir> [--out-dir <path>] [--validate]` is a pure bash/jq
projection of `release-decision.json` into the PM machine handoff — it reads **exactly one**
evidence file (the decision) and no siblings (cycle-break). It emits `pm-decision-brief.json`
(protocol-v2 `pm_decision_brief`) + a human `pm-summary.md`, then does one idempotent patch-back
of `pm_brief_status` into the decision. The human summary shows evidence / review / waiver
status **in full even for an auto-merge run**, so an auto-merge is never silent — but
see the honest phasing limitation below.

### D11 — release-decision state model

D11 is the set of state fields the decision carries so the PM handoff is legible without
re-deriving anything. All live under `release_decision` and are echoed 1:1 into
`pm-decision-brief.json`:

| Field | Values | Meaning |
|-------|--------|---------|
| `pm_brief_required` | always `true` | every release requires a PM brief |
| `pm_brief_status` | `pending` → `generated` \| `failed` \| `incomplete` | brief lifecycle (see phasing) |
| `evidence_verified_at_head` | boolean | did `aid-evidence-verify.sh --at-head` pass at current HEAD |
| `evidence_verification_status` | `pass` \| `fail` \| `unverifiable` | fail (mismatch/dirty) vs unverifiable (tool error) — distinct |
| `merge_mode` | `auto` \| `manual` \| `blocked` | informative routing, NOT an enforcement gate |
| `delivered_summary_ref` | path \| `null` | already-resolved pointer, echoed not re-opened |
| `summary_for_pm` | string | mechanical one-line template, no LLM |

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
- **The per-EPIC decision defaults to observe, not blocking.** `done-advance` logs it; it does
  not enforce it until a project opts in via `RELEASE_DECISION_POLICY: enforcement: blocking`.
  At a plan's close (`--stage decide`) the decision is always enforced.
- **Evidence-freshness binding is presence/format, not cryptographic** — `head_sha` /
  `input_manifest_hash` are checked for presence and staleness, not recomputed-and-compared for
  hash equality (**IMP-176**, E10 territory).
- **IMP-179 (subagent protocol-cache staleness) is unresolved** — an `aid-orchestrator:*`
  subagent's system prompt resolves from the installed plugin cache, not the live repo, so an
  `agents/*.md` change made inside an EPIC is not picked up by that same EPIC's own dispatches.
  Paste the changed protocol verbatim into the dispatch prompt until a dispatch-time
  freshness-hash check lands.
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

**Last Updated:** 2026-08-25

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

## Test-portfolio decision quality (P072) — removed 2026-09-21

The test-portfolio audit (`/aid-audit-tests`, its five prompts, seven schemas (six `test-audit-*` plus `test-profile`),
`lib/aid-test-audit-*`, the `test-portfolio-analyst` agent, `config/test-audit.yaml`)
was removed after its one real run (2026-08-05) produced no proposal the PM
accepted and the parallelism it was built to decide about was itself removed
(P078). What stays, because the merge path reads it: the test catalog
(`aid-test-inventory.sh` → `aid-test-catalog-approve.sh` → `.aid-o/config/test-catalog.yaml`),
the tier tags and their tools (`aid-test-tier-assign.sh`, `aid-test-tier-lint.sh`,
`lib/aid-test-durations.sh`) and the selection layer (`aid-select-tests.sh`,
adapters, execution units). Registry rows of the removed enforcements carry
`status: removed_scoped` with this note as their `replacement_guard`.

### The test catalog, and who refreshes it now

The catalog (`.aid-o/config/test-catalog.yaml`, schema
`defaults/schemas/test-catalog.schema.json`) is what `aid-select-tests.sh` reads
for approved mappings. It used to be refreshed by step 2 of `/aid-audit-tests`;
with the audit gone nothing on the merge path produces it, so it is refreshed by
hand when suites move or are added:

```bash
bash scripts/aid-test-inventory.sh --project-root . --audit-id catalog-$(date +%Y%m%d) --output-dir .aid-o/work/test-audits/catalog-$(date +%Y%m%d)
bash scripts/aid-test-catalog-approve.sh --proposed .aid-o/work/test-audits/catalog-<date>/test-catalog.proposed.yaml --project-root .
```

The `--audit-id` name and the `.aid-o/work/test-audits/<id>/` output directory
are the inventory's own vocabulary and survived the audit; renaming them is a
separate, cosmetic change. `aid-test-catalog-confirm-mapping.sh` has no runtime
caller since 2026-09-21 (it was only ever named by the deleted command).

### The execution ledger, and the emission path that is easy to forget

`test_execution_no_double_dispatch` is worth reading about before you touch the
gate runner. The ledger records one entry per run unit ACTUALLY DISPATCHED,
from two emission points (P078 deleted the other two — the bats lane and the
scheduler — with the parallelism machinery):

1. `run-all-tests.sh` — one per suite
2. `aid-run-gates.sh` — for any gate whose command invokes a runner **directly**

The second is the one that matters and the one easiest to leave out. This
repository HAD a gate that ran `test-aid-fsm.bats` on its own while the
aggregate ran it too, with the `full` and `release` profiles including both, so
that file executed twice on every full run. With only the fan-out point
instrumented, the ledger would have recorded one entry for it and reported zero
duplicates — certifying as clean the exact defect it was built to detect. It
found it instead, and `bats_fsm` is now absent from those two profiles; the red
proof lives in a fixture so fixing the waste did not blind the check.

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
`AID_EXECUTION_KIND` marks a whole subprocess, which is how the targeted-tests
escalation — which re-invokes the gate runner with the parent's ledger
inherited — avoids being recorded as an accident. Declared repeats appear in the summary as
`deliberate_repeats`: never failing, never invisible, because a rerun somebody
asked for still costs the wall clock twice. The default is `normal`, so silence
is not a declaration and a forgotten mark stays a defect.

### Adding to this area

The command file (`commands/aid-audit-tests.md`) is the operator contract and
is NOT on the lint gate's grandfathered list — keep it clean rather than adding
it. The agent card is verified by the golden-prompt test instead, because
linting it would demand frontmatter fields that are meaningless for a
dispatched agent.

## The force framework, PM overrides, and review equivalence (P073)

P073 loosened three places where AID refused work it had no physical reason to
refuse. Each loosening is paired with an audited receipt: what used to be
unrecorded surgery is now a decision with a name on it.

### Forceable vs hard preconditions

Every plan-level precondition is classified at its call site:

```bash
_pfsm_precondition "clean_worktree" forceable _pfsm_check_clean_worktree "$root" || exit 1
_pfsm_commit_force "plan-merge-to-main" "$plan_id" "$root" || exit 1
```

- **`forceable`** — a bookkeeping obstacle, not a physical impossibility. A
  dirty worktree, an unproven lineage, an unshared source plan. A PM who
  knowingly accepts the state proceeds with `--force --force-reason "<why>"`.
- **`hard`** — identity, evidence integrity, PM authorization. These cannot be
  forced at all. A force that could fake an authorization would be the backdoor
  the framework exists to replace.

The force path is **fail-closed**: `_pfsm_commit_force` writes the waiver
receipt BEFORE the command proceeds, and a receipt that cannot be written
refuses the force rather than passing it unrecorded. `--force` without
`--force-reason` is a usage error, so no waiver is ever anonymous. The refusal
always prints the precondition's own recovery FIRST — the force is offered as
the second option, never the first.

**When you add a precondition,** classify it in the same commit. An unclassified
one is not forceable by default; it simply has no force path, which is the safe
default but also an invisible dead end for the PM.

### Single-use PM-override artifacts

A PM override (the EPIC supersede record, the resume artifact) is a file the producer
writes and exactly one consumer claims. The claim is:

```bash
mv -n "$grant" "$claimed" || return 1
[[ ! -e "$grant" ]] || { echo "PRECONDITION FAIL: the grant is still on disk"; return 1; }
```

The post-check is **not** belt-and-braces. On coreutils 9.1 `mv -n` exits 0 when
it SKIPS the move, so without it the claim reports success while the grant stays
on disk and authorises a second consumer. Any new single-use artifact must carry
the same post-check.

The consumer must also **re-derive** every field it trusts rather than reading
it from the record. A stale record, a forged one, or one written for a different
package then authorises nothing, and the underlying unconditional rule simply
stands.

### Ancillary paths and review equivalence

After a plan-final review freezes a candidate, any tracked write used to throw
the review away — an audit-log append cost a full re-review cycle even though
nothing about the delivery had changed.

Two sets decide this now:

- The **ancillary policy** (`defaults/policies/plan-final-policy.yaml`, project
  override at `.aid-o/config/policies/plan-final-policy.yaml`) lists paths whose
  movement does not describe the delivery.
- The **protected surface**, computed at freeze from every step's
  `allowed_paths` plus the source plan, the lifecycle manifest and the
  close-consumed receipts, and stored in the plan-boundary manifest.

**Protected wins.** Close-consumed evidence lives under `.aid-o/work/`, which is
an ancillary glob, so a path in both sets is protected — in the committed diff
and in the worktree alike.

`plan_final_review_equivalent` returns **three** states:

| Code | Meaning |
|------|---------|
| 0 | the head differs from the candidate in ancillary paths only |
| 1 | it does not — every offending path is named with its classification |
| 2 | equivalence is UNAVAILABLE (legacy freeze, partial protected set, unreadable git) |

A caller that collapses 2 into 0 accepts a head nobody compared. Treat 2 exactly
like today's invalidation.

The predicate is **pure**. Acceptance is a separate deliberate act
(`plan-finalize <plan> --stage accept-ancillary`) that runs under one lock,
re-verifies the head immediately before the write, and binds the receipt with a
compare-and-swap on the frozen candidate and the prior accepted head.

#### Which consumers accept equivalence

| Consumer | Behaviour |
|----------|-----------|
| `_pfsm_review_candidate_drift` (review pre/post, C4) | equivalence-aware — accepts a receipted accepted head |
| `plan-merge-to-main` (head leg) | equivalence-aware, with LIVE re-verification against the current policy |
| PM decision binding | **exact only** — always the frozen candidate |
| pre-commit scope guard, `gates/scope-check.sh` | **exact only** |
| release preparation and staging | **exact only** |
| `--at-head`, CP3, C3, `aid-plan-close-check.sh` | **exact only** |

Exact-only is the default. A consumer becomes equivalence-aware by being wired
deliberately and covered by a test that proves both the accepting and the
refusing case — never by inheriting the predicate because it happened to be in
scope.

**A protected-surface change is a FIX,** not something to accept: re-sync,
re-freeze, re-review. The invalidation message says so, and it offers the
`accept-ancillary` recovery only when the difference really is ancillary-only —
offering it otherwise would send the operator into a refusal loop.

## Two roots, per-plan worktrees, and the generation transaction (P074)

P074 is what made it possible to work on two things at once. Before it,
everything shared one checkout: opening a plan refused on an unrelated
uncommitted edit, starting an EPIC moved the branch under whatever you were
reading, and generating a second plan while the first was being implemented was
not something the tooling had a shape for. Three mechanisms carry that, and if
you add anything that resolves state, touches a tree, or generates EPICs, you
have to know all three.

### The roots contract: state root vs invoke root

There are now two roots, and conflating them is the whole failure mode:

- **The state root** — the ONE `.aid-o` workspace, resolved through the git
  common directory (`git rev-parse --path-format=absolute --git-common-dir`),
  so every linked worktree of a repository reaches the same workspace.
- **The invoke root** — the tree the command operates ON. In a plan worktree it
  is that worktree; in the primary checkout it is the checkout.

```bash
source "${SCRIPT_DIR}/lib/aid-roots.sh"
state_file="$(aid_state_path ".aid-o/work/evidence/${epic_id}/${run_id}/fsm-state.yaml")"
tree="$(aid_invoke_root)"
```

**Every `.aid-o` read and write goes through `aid_state_path`.** A cwd-relative
`.aid-o/...` was harmless while there was one checkout; from a linked worktree
it silently creates a SECOND workspace, and the run that wrote it is the only
thing that will ever find it. `AID_PROJECT_ROOT` is honoured but canonicalized
rather than trusted verbatim.

Two consumers of the same contract live outside the scripts: the installed
`pre-commit` hook carries an inline copy of the resolver (a hook cannot source
the plugin), and `aid-plan-fsm.sh` keeps its own private resolver — deliberately
not migrated, because its resolution order is bound to `--project-root`.

### The per-plan execution worktree

`plan-start` creates `.aid-worktrees/plan-<id>` checked out on `plan/<id>` and
records the absolute path in plan-state. The path is CANONICAL by design: it
stays derivable without reading any state, which is what lets an enforcer fall
back to physical evidence when the state file cannot be read.

Lifecycle, in the order a contributor meets it:

| Stage | Mechanism | What it refuses |
|-------|-----------|-----------------|
| create | `_pfsm_create_plan_worktree` (shared by plan-start and the repair) | a foreign directory at the path, a registered tree on the wrong branch, a failed `worktree add` (git's stderr verbatim) |
| enforce | `_pfsm_require_plan_worktree` / `_fsm_require_plan_worktree` | a missing or unregistered recorded tree, a recorded path that is not a LINKED worktree, the plan-start crash window, a redirect that did not land |
| teardown | `_pfsm_teardown_plan_worktree` at plan-close / plan-rollback | nothing — teardown ALWAYS returns 0, because a stuck worktree must never block a durable close; the inverse guard refuses running it from INSIDE the tree |
| repair | `plan-state <id> --recreate-worktree --reason "<why>"` | a reason under 20 characters, a corrupt or terminal plan, a concurrent worktree transaction (it holds the per-plan worktree lock) |

**The enforcer redirects by default and refuses only when the worktree is
broken.** A plan-linked command that touches a tree re-executes itself with the
worktree as cwd, preserving argv verbatim except that operator-relative path
arguments are absolutized first — the cwd changes underneath them, so a
`--execution-yaml config/exec.yaml` would otherwise resolve inside the worktree
where it does not exist. If you add a path-taking flag to either CLI, add it to
the enumerated list in `_aid_wt_rewrite_args`; a flag missing from it breaks
silently, only after a redirect.

**Two mistakes that are easy to make and cost real time:**

1. *"Registered with git" is not "is the plan's tree."* `git worktree list`
   includes the PRIMARY checkout, so a `worktree_path` recorded as the state
   root passes every existence and registration probe, then matches the cwd as
   "already there" — and every checkout and merge runs in the PM's tree while
   the command reports isolation. Check LINKEDNESS (`<common>/worktrees/…`)
   before comparing cwd.
2. *Never diagnose from an answer you did not get.* `plan_state_get` returns rc
   2 when jq/yq is missing and rc 5 when the state file is corrupt. Collapsing
   those into "the plan records no worktree" made the crash-window refusal fire
   on a missing dependency, telling the operator their plan-start had been
   killed mid-transaction. Cannot-read is a THIRD state, and on it the enforcer
   uses physical evidence: a git-registered linked worktree at the canonical
   path.

Fixtures that simulate a pruned workspace must remove the registration too.
Deleting only the state record while the registered worktree survives is a
DIFFERENT scenario — it is exactly the crash window, and the enforcer refuses it
on purpose.

### The generation transaction

Generation is one transaction per plan, not N independent phase runs.

- **Authority.** CP1 is consulted ONCE and its decision is sealed into
  `generation-authority.json`, bound to the plan bytes, the target branch and
  head, the phase-derivation version and the phase count, with a canonical-JSON
  self-hash. Every phase VERIFIES that receipt (`_verify_generation_authority`)
  instead of re-running the gate; a standalone generator invocation still runs
  the real gate, so there is never a gate-less path. Classified honestly: the
  receipt is forgeable by anyone who can write the evidence directory. The
  enforcement is hash and transaction binding plus audit detectability, not
  actor impossibility.
- **Manifest.** `transaction.json` records each phase's outputs and their
  hashes. Phase status is **derived**, never stored: a rerun re-hashes the
  recorded outputs and reads queue membership, so the files and the queue are
  the truth and the manifest is only the binding that lets a rerun VERIFY
  rather than blindly redo.
- **Resume.** Identity is `plan_sha256|target_head|phase_derivation_version|
  total_phases`. A matching identity resumes; a mismatch over an INCOMPLETE
  transaction refuses, naming both identities, because artifacts from two
  derivations are never mixed.
- **Supersede.** `aid-auto-pipeline.sh supersede-generation --plan <path>
  --reason "<>=20 chars>"` archives the transaction/authority pair with a
  forensic record. It deletes nothing — cleanup of generated EPICs and queue
  entries stays with plan-rollback and queue removal, where it is visible.

Who consumes the transaction, and what each is allowed to conclude from it:

| Consumer | Behaviour |
|----------|-----------|
| `aid-plan-to-epic.sh --generation-authority --transaction` | verifies the sealed authority against schema, self-hash, plan bytes, target head, phase range and transaction linkage; both flags or neither |
| `aid-epic-to-json.sh` | ordinary converter — the transaction records its output hash, it reads nothing from it |
| `aid-queue-add.sh --transaction` (unlocked pre-check) | never decides; defers to the locked writer |
| `lib/aid-queue-write.sh:_queue_tx_owns` | the ONLY place an existing queue entry is judged ours: IDENTITY-bound (same plan path, and either this transaction recorded the queueing or the entry was added within its lifetime) |
| `aid-generation-finalize.sh --rewrite` | rewrites `queue_status` only over a receipt whose schema and `plan_sha256` still match |
| the pipeline's own resume path | skips a phase only when its recorded hashes still verify |

**Ownership is identity-bound, not name-bound.** A queue entry with the right
epic_id and the right plan path, added before this transaction existed, is a
STALE entry — it is refused, not adopted. That distinction is the difference
between resuming and silently blessing somebody else's leftovers.

**Write order is load-bearing in two places.** A phase's outputs are recorded in
the manifest AFTER they are on disk and contract-validated (a crash before that
regenerates the phase; a crash after resumes at the next one). And the three
force-audit records are written BEFORE the forced authority exists — a kill
between them would otherwise leave a valid `forced_override` authority that
every later resume accepts without re-consulting the gate, making the bypass
permanent and invisible.

### Adding to this area

Anything new that resolves state goes through `lib/aid-roots.sh`. Anything new
that touches a tree in a plan-linked command sits BEHIND the enforcer, never
beside it. Anything new that generates or queues per phase reads its ownership
from the transaction, not from the epic id. And every refusal you add gets a row
in `defaults/enforcement-registry.yaml` with its enforcement mechanism named at
design time — a detector without enforcement is decoration.

---

## Owned waits: background gates, declared services, bounded recovery (P076)

Before P076, every long operation in AUTO mode was a wait nobody owned. A
thirty-minute suite ran inline, so a killed session took it with it; the
infrastructure a test needed was started by hand and slept on; and a controller
that died left a run indistinguishable from one making progress. P076 gives each
of those an owner. Three contracts came out of it, and anything you add that
runs long, needs infrastructure, or retries after a failure has to respect the
matching one.

### The owned-job contract

A gate declares how it runs:

```yaml
gates:
  bats_all:
    command: "bash scripts/tests/run-all.sh"
    timeout_seconds: 3600
    run_mode: background        # foreground | background (default: foreground)
```

**Background is not fire-and-return.** The runner still polls the job to
completion inside the same invocation and returns the gate row itself
(`aid-run-gates.sh`, the poll loop under `# ── poll to completion, inside THIS
invocation ──`). What `background` buys is *survivability*: the command runs as
an `aid-job.sh` job — its own process group, PID-reuse defeat, a durable
HEAD/tree-bound terminal receipt — so the work outlives the session that started
it. A runner that returns before the job does is IMP-476 and does not exist;
building one needs a registered collector first, and the runner is written to
refuse an unknown mode rather than to document the requirement.

**Background it when losing the session would cost more than the gate.** The
flip is a PM's one-line decision, and in this repository only `bats_all` and
`bats_boundary` have earned it. The shipped `/aid-init` template documents the
key and declares it nowhere, so a consumer project's gates keep the foreground
path, which is byte-for-byte the code AID always ran.

**Fixed timeouts (P097 Step 5).** A gate's deadline is `timeout_seconds` and
nothing else: absent, the template default of 60 s; not a positive integer,
`run-all` exits 2 naming the gate before any gate runs. The same configuration
and the same code give the same deadline on every host — no history file
steers a run (the P063 runtime baseline, its repeated-timeout block and its
run-mode advice were removed; the measurement that justified it is the
`gate_timeout_fixed` registry row). A gate past its deadline is a
`status: fail, reason: job_timeout` row with no surviving child, whether
`timeout(1)` or the job supervisor stopped it. History informs the number in
the file: the written rule is 2 × p95 of the last 20 measured `duration_ms`
(`job_timeout` rows excluded), rounded up to 30 s, 60–3 600 s, and the
maintainer tool prints it next to what is configured —

```bash
plugins/aid-orchestrator/scripts/aid-gate-runtime-report.sh [--project-root <path>] [gate]
# bats_all proposed_timeout_seconds=2280 (p95 1140000 ms over the last 20 measured durations, 1 job_timeout rows excluded) configured_timeout_seconds=3600
```

(`scripts/lib/aid-gate-runtime-baseline.sh propose <evidence root> <gate>`
underneath; fewer than five measured durations prints `insufficient_history`).
It never writes: a person edits `timeout_seconds`.

**Re-attach, precisely.** The job id is deterministic —
`<gate>-attempt-<N>` — so a rerun looks in exactly the directory this attempt
would use. Finding a job there is not sufficient to trust it:

| Found | What happens |
|-------|--------------|
| fingerprint + start HEAD match, job live | re-attach and keep polling (`gate_job_reattached`); the suite is not re-run |
| fingerprint + start HEAD match, job terminal | collect the receipt — but see currency below |
| command fingerprint drifted | cancel, archive to `.superseded-<epoch>`, start fresh |
| no job, or no result record | start fresh; a missing result maps to an explicit `job_lost` fail row |

The fingerprint is a *validation guard* on the job the id found, never a
discovery mechanism — two gates running an identical command never
cross-attach.

**Currency splits on provenance, not on timing.** A REPLAYED result — a job this
invocation found already terminal — is a result produced before this invocation
existed, so the working tree gets to veto it: `aid-job.sh collect
--require-current` supersedes a stale receipt and the gate genuinely re-runs.
A job this invocation spawned, or re-attached to while still live and polled to
completion, is *watched* work: the command's exit code is the gate's answer, and
tree movement during the run is recorded (`gate_job_tree_moved`,
`tree_moved_during_run` on the row) rather than promoted to a verdict. Getting
this backwards is what made a self-writing gate fail while its identical
foreground twin passed.

**The row is checkpointed, and the checkpoint is bound.** A completed gate's row
lands atomically in `<evidence>/gates_rows/<gate>.json`, restored by a resumed
invocation. It is not what avoids re-execution after a crash — re-attaching to
the still-supervised job is — it is a fail-closed safety net for a gate that
produced no row at all. The envelope carries the head, the tree, the
checkpoint's canonical home directory and a key derived from a per-run 0600
secret, and the restore pass refuses on any mismatch, so a hand-written row or a
copied evidence directory carries no authority.

**The continuation artifact is the contract with a controller that dies.** A
single `auto_resume_required.json` per run is written *before* the job spawns
(`job_id: pending`) and rewritten atomically with the real id immediately after,
so there is no crash window that leaves no pointer; it is deleted only on a
terminal collect with no other background job still live. `aid-fsm.sh resume
<epic_id>` claims it exactly once (`mv -n` plus a source-gone post-check),
collects, writes the durable row and prints three lines — what it found, what it
recorded, what to do next. Executing that next action is the controller's turn,
not the command's.

If you add a code path that starts or collects one of these jobs, use the shared
pieces rather than a second copy: `lib/aid-gate-row.sh` is the ONLY job-result
to gate-row mapping, and `lib/aid-resume-artifact.sh` is the only definition of
the artifact's name (a test fails if a second one appears — they had already
diverged once, fail-open).

### Declaring services

**Removed (P097 Step 6).** The service lifecycle of P076 — the `services:`
block, per-gate `needs_services`, the per-run port registry, the ownership
claim, the entry sweep and the FSM's `_fsm_service_sweep` — is gone, and
nothing replaces it: the sweep only ever signalled service jobs, and the
resume path always left a live background gate alone, so gates keep their one
process owner (`aid-job.sh`, the owned-job contract above) and there is
nothing left to sweep. The measurement behind the decision is the P097 Step 1
baseline: no consumer project declared a service. What the mechanism was, and
the rules it enforced, are history in `CHANGELOG-archive.md` (the P076 entry).
A `services.json` left under a run's evidence by a pre-2.103 run is reported
once by `aid-fsm.sh resume`/`done-advance` and otherwise ignored.

**Removed keys are refused, never ignored (P097 Step 6).** `run-all` stops
with exit 2 before any gate runs when `execution.yaml` still carries
`services:` or `gate_profile_defaults` at the top level, or `required_when` or
`needs_services` on a gate — naming every key found, the gate it sits on, and
the upgrade that removes it
(`bash $AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh upgrade <project root>`).
The key is the signal, not its content: `services: {}` is refused like a
populated block. An ignored key is how `required_when` sat unread in every
generated project for four months; `required:` alone now decides whether a
gate blocks. The registry row is `execution_yaml_dead_keys_refused`.

### The recovery policy, and how a consumer changes it

`defaults/policies/auto-recovery.yaml` is the one machine-readable answer to
"what may an autonomous run do about a stop, and how often". It defines seven
stop classes (`GATE_TIMEOUT`, `SERVICE_UNHEALTHY`, `JOB_LOST`,
`TRANSIENT_INFRA`, `DISPATCH_ORPHANED`, `REVIEW_EXHAUSTED`, `UNCLASSIFIED`),
each carrying:

- `allowed_actions` — drawn from a CLOSED vocabulary of five reversible actions
  (`wait_and_resume`, `retry_once`, `rerun_targeted`, `resume_missing_lenses`,
  `collect_and_continue`; `restart_service_once` left with the service
  lifecycle in P097 Step 6). None of them weakens, waives or bypasses a gate.
  An action name outside the five is a schema error at load, never a silent
  no-op.
- `budget: {attempts, wall_clock_seconds}` — spent per run per class.
- `emitter` — the real `file:line` that classifies this stop, grepped against
  the source by a test that turns red when the anchor moves.
- `terminus: [adjudicate, escalation, pm_force]` — where the class goes when its
  budget is gone. The schema pins the ORDER, not merely the set, so an override
  cannot put the human-only act first.

Three consumers sit on it. `lib/aid-recovery-ladder.sh` loads it
(`aid_recovery_policy_load`), records every attempt in
`<evidence>/recovery-ladder.jsonl` and returns PERMISSION — it never performs an
action. `lib/aid-recovery-adjudicate.sh` takes the exhausted case to the isolated Codex
transport (`_run_codex_isolated`, shared with the review rounds) with a
fact pack, and returns exactly one allowlisted action or the literal `escalate`. And the terminus stamps `auto_controller:
blocked_for_pm` on the run, which `/aid-status` renders.

**Two properties you must not break when you extend this area.** First, the
returnable set is computed from constants IN THE LIBRARY, before any reply
exists — the policy's own `action_vocabulary` is checked against those
constants, never trusted as the authority, and `escalate` is deliberately absent
from the vocabulary so no caller can execute it. Second, the budget is not a
plain counter: the record is hash-chained with a high-water mark written under
the same lock, so truncating the file to buy more attempts is a sticky refusal
rather than a silent reset (deleting BOTH files still resets it — a directory
the writer must write cannot be proof against its writer; what ended is the
*silent* reset).

**A consumer project overrides by file, never per plan.** Write
`.aid-o/config/policies/auto-recovery.yaml`; the loader resolves it after any
explicit path and before the shipped default. The contract for what happens next
is declared in the policy's own `loader_contract` and implemented in the loader:

| Situation | Result |
|-----------|--------|
| override unreadable or schema-invalid | named warning identifying the path and the first error; falls back to the shipped policy |
| override omits a class | that stop routes as `UNCLASSIFIED` — straight to adjudication, never "no recovery" |
| unknown action name | refused at load |
| `attempts: 0` | legal configuration; the class goes straight to adjudication |
| a per-plan override (`AID_RECOVERY_POLICY_PER_PLAN`) | refused by name — the policy is PROJECT-scoped, because two plans running concurrently in one project share it |

To **add a class**, give it all of the above *including a real emitter that
already exists*, and label it honestly on both axes: `detector` (does code find
the condition?) and `ladder_entry` (does code write the record, or does the
AUTO-loop instruction route it?). A class whose ladder entry is an instruction
says `ladder_entry: instruction` and `ladder_entry_status: planned` — the
anti-decoration test derives the wired answer from the repository rather than
from the file's own claim, so a status you assert without a write turns it red.
To **change a budget**, edit the class's `budget` in your override — but check
`existing_loops` first: the gate fix loop, CP2/CP3, C3 rechecks, the CP1 ledger
and per-gate `max_retries` are declared there with `authority: existing` and the
file each budget really lives in. Those are NOT governed by the ladder, and
changing the ladder's numbers will not move them.

### Adding to this area

Anything that runs long enough to outlive a session becomes an `aid-job.sh` job,
not a detached process. Anything a gate depends on gets DECLARED, so the runner
can probe it instead of a human sleeping on it. Anything that retries goes
through the ladder's budget rather than counting for itself. And any state a
dying controller would have to write about itself is DERIVED by its readers
instead — the epitaph rule: the one party that cannot write is the one the flag
would be about.

## The aftermath layer (P079)

P076 was the first plan to run the whole machine at once, and running it is what
found these. Every mechanism below exists because a live run did something
untrue and nothing stopped it. If you touch the worktree seam, a review
checkpoint, or the release script, read the part that covers it.

### The worktree seam: which tree, and where the evidence goes

Two different roots meet in every gate run, and they are not the same root:

- The **tree under test** is the caller's working directory. Gate COMMANDS run
  there, and the report's `head_sha` describes it. This is the candidate code.
- The **state root** is where `.aid-o` lives. It is the primary checkout and
  never moves into a worktree, so every state artifact — timeline, gate report,
  execution ledger, gate-scoped waivers, row checkpoints, project config —
  belongs there.

Before P079 both were "whatever cwd happened to be". `advance-to-gates` was the
one plan-linked tree command with no worktree redirect, so a run driven from the
primary checkout executed every gate against `main` and reported a confident
green about code the commands never saw — and the risk resolver, reading that
empty diff, picked the cheapest profile. Meanwhile the runner's state writes
went looking for evidence directories that were not there; because the ledger,
the rows and the recovery ladder are all `[[ -d ]]`-guarded, they did not fail,
they went quiet.

**Adding to this area.** A command that reads or writes a TREE gets
`_fsm_require_plan_worktree` (aid-fsm.sh) or its plan-FSM twin — there are now
three call sites and they all look identical on purpose. A path that names
`.aid-o` goes through `aid_state_path` / `aid_state_root` (lib/aid-roots.sh),
never through cwd and never through `git rev-parse --show-toplevel`. If you find
yourself writing `${toplevel}/.aid-o/...`, you have written the bug this section
is about.

### Chained EPICs and the two base records

Chain generation registers every EPIC of a plan at once, and `epic-start` cuts
`task/<epic>/main` from the plan head at REGISTRATION time. That cut is correct
when it happens and stale by the time a later chain member executes — its
predecessors have merged since. The shipped lineage check cannot see it, because
merge-base equality is *precisely* what "merely behind" means.

`_pfsm_reconcile_task_branch` runs BEFORE that precondition (a crash mid-repair
breaks the invariant the precondition asserts, so an untouched lineage check
would refuse before any repair code could run), under the plan lock that also
covers the plan-head read. Strictly behind is fast-forwarded; DIVERGED is
refused by name with both heads and never merged automatically.

Note the number of places that record the same fact: the manifest's
`epic_base_commit`, the fsm-state's `base_commit`, and the branch itself. They
move together — the manifest under a CAS, the fsm-state under an ancestor guard
— and every crash window between the writes re-runs clean. **If you add a fourth
record of that fact, you are adding a fourth thing that can disagree.**

### Journals: obligations and routed findings

Two append-only JSONL journals live in the state root's plan-state directory,
which is the one place that outlives every worktree:

- `carried-obligations.jsonl` (lib/aid-obligations.sh) — a deferral the run
  decided to make. `aid-plan-close-check.sh` refuses to close a plan while a
  `release_blocker` is open.
- `routed-findings.jsonl` (lib/aid-routed-findings.sh) — a review finding no
  remaining step may fix. `done-advance` refuses over an open one AND
  reconciles the canonical `semantic-review-final.json` against the journal, so
  an out-of-scope finding nobody recorded fails by fingerprint.

Both exist because the first P076 run improvised a `carried-obligations.md`
inside the plan worktree's gitignored `.aid-o`; the worktree was torn down and
the obligation went with it — and nothing would have read it anyway, because
that file had no writer and no reader anywhere in the codebase.

**Adding to this area.** Indices and identities are assigned at FOLD time, never
embedded at write time — two concurrent appends could otherwise embed the same
index and a later resolve would close an unrelated blocker. An unreadable
journal FAILS CLOSED: "cannot be parsed" and "nothing is owed" must never look
alike. And note the honest split recorded in the registry — recording an
obligation is *instruction* (a deferral is born in a controller decision, with
no artifact to reconcile against), while consuming one is *blocking*. Routed
findings have both halves because they DO have a canonical artifact.

### The release seal

A tagged version's CHANGELOG heading is immutable. Both retitle sites in
`aid-release.sh` were a blind `sed 's/## [$CURRENT]/## [$NEW_VERSION]/'`: on a
version that never shipped that is a correction, on one that did it renames the
entry, and the new release inherits the old one's content while the old release
disappears under a number that does not describe it. `_release_version_sealed`
keys on the git tag and both sites take the same branch — preserve the heading,
prepend a fresh entry — and it FAILS CLOSED when the tag lookup itself cannot
run.

### Tests that cannot fail

`aid-test-content-scan.sh` gained the two MECHANICAL shapes of "green but checks
nothing": an unguarded `grep -c` under `set -e` (it exits 1 on zero matches and
kills the suite before it prints, while the cases already run still read as
green) and a `skip` keyed on whether the SUBJECT exists (a deleted subject
should go red, not skipped). The judgment shapes need a reader and ship as the
authoring rule in `scripts/README.md` instead — named honestly rather than
pretended to be mechanical.

**Adding to this area.** A new check goes in the scanner only if it is
deterministic and its false-positive shape is pinned by a test. If it needs
judgment, write it as a rule where test authors read and say so.

## The entry-point UX layer (P080)

Three surfaces a person actually meets — the help, the two setup commands, and
the last message of every run — had drifted into being maintained by hand next
to the thing they describe. Help listed a `--mode` value the parser rejects.
Two commands wrote the same files with no declared owner. Every boundary
improvised its own final message. This section is the layer that replaced all
three with one authority each, plus a mechanical check that the authority is
still being read.

### The help index, and the coverage test

`defaults/help-index.yaml` is the authority on every surface the plugin ships.
`lib/aid-help-index.sh` is the ONE reader, and `commands/aid-help.md` is
GENERATED from the index rather than maintained beside it. Each row carries a
command, its file, the help topic it routes to, its audience, its disposition,
its purpose, what it writes, and its `final_turn`.

`test-help-index-coverage.bats` (t1, merge path) makes three artifacts agree or
fails: the surfaces the repo mechanically ships, the index that claims to be the
authority on them, and the help file a user actually reads. **A newly added
public command fails here until it is INTENTIONALLY indexed and routed —
silence is not a pass.** Routed means the topic names the command in prose, not
only inside a code fence: a fence is not something a reader searching for a
command name will find.

Two of its cases own the output-contract inventory, and their honest scope is
worth carrying:

- **Case 10** reads the `final_turn` VALUE, not merely its presence — the form
  (`renderer:<script>` / `card:<type>` / `internal`), the card vocabulary (the
  four cards defined in `skills/communication.md`, no fifth), and the
  public/internal split, since `internal` is legal only where disposition is
  `intentionally_internal`. For `card:` rows **this is vocabulary and
  disposition consistency only** — it is not proof the surface emits that card
  at run time. Observing a real final turn needs a capture harness this layer
  does not build, and the suite says so in its own header rather than letting
  the row read as stronger than it is.
- **Case 11** is the half that checks CONTENT: a `renderer:` value must name a
  script that exists AND be mentioned by the surface's own file, so an inventory
  entry can never name a mechanism nothing wires.

**Adding to this area.** A new public command gets a `help-index.yaml` row
FIRST, then a mention in prose in its help topic, then `commands/aid-help.md`
regenerated from the index — never edited directly. An internal surface gets
`disposition: intentionally_internal` and `final_turn: internal`, and those two
must agree; do not reach for `internal` to get a user-facing command out of the
inventory, because that is the exact hole the inventory exists to close.

### Registry cites have to resolve

`test-enforcement-registry-cites.sh` (t0, merge path) asserts that every
`source:`/`instruction:` cite in `defaults/enforcement-registry.yaml` names a
file or directory that exists — **except on rows marked `status: dead` or
`status: removed_scoped`, whose path validation is skipped** — and that every row
id is unique.

That exception is the point of those two statuses, not a hole in the check: a
dead row records an enforcement that died together with the file it cited, so
the cite is deliberately dangling and is kept as the paper trail for what used to
be wired. Several shipped rows are in exactly that state. The rule to take away
is the one that makes the exception safe: **`status: dead` is the only sanctioned
way to keep a dangling cite, and every other row — including one with no
`status:` key at all — is validated.** An empty status is not a skip; a row
cannot opt out by omitting the field.

A registry row is this plugin's promise that a detector has a real enforcing
surface. A row citing a file that was deleted, renamed or moved still LOOKS
wired while enforcing nothing — the P026 "detector without enforcement" failure
one level up, hiding inside the very file that exists to make enforcement
auditable. P080 found eight such rows.

Three things are deliberate:

- **Line numbers are NOT asserted.** `file:123` drifts on every edit above line
  123; asserting it would make the registry unmaintainable. File existence is
  the invariant, the line is a navigation hint, and a prose grep anchor is the
  better cite when the line has already drifted once.
- **Four bases, not one.** The shipped registry legitimately writes cites
  against the plugin root, the repo root, and `plugin + scripts/` (bare
  `lib/…`). A fifth shape, `/ecosystem/…`, is a Docusaurus namespace path into
  the shared ecosystem docs; it is resolved against that tree when present and
  REPORTED AS SKIPPED when it is not, because a consumer checkout without
  `/opt/eco/docs` is a real situation and must be visible rather than assumed
  away.
- **It fails closed by construction.** It materialises rows before iterating,
  checks `jq`'s exit code, and asserts the extracted row count equals the
  registry's own declared length. An earlier draft let one non-scalar cite field
  abort extraction mid-pipeline and reported success having checked 0 rows.

**Adding to this area.** When a cite dangles, repoint the row at the surface
that really carries the rule, or mark it `status: dead` with the reason the
enforcement died with what it cited. Never allowlist a path to make a row pass.
And when you add a row, recompute the header total from the real count
(`yq '.enforcements | length' defaults/enforcement-registry.yaml`) rather than
adding one to the number that is there.

### Who owns each file init and setup write

The rule is one line: **`/aid-init` CREATES, `/aid-setup` MUTATES, and an init
re-run never rewrites a file that exists.** What made it untrue in practice was
not the rule but the exceptions, which existed and were undeclared.

The fresh-init product is counted ONCE, in `commands/aid-init.md`'s base
manifest, and every other mention refers back to it instead of restating a
number — four different counts had been shipped, each true of a different draft.
Git hooks and conditional writes are labelled separately and excluded from the
count, and the reason is the document's own rule rather than convenience.

Each row's carve-out is cited by file and section name, not line number:

| File | Owner | Carve-out lives at | Test |
|---|---|---|---|
| `config/project.yaml` | `/aid-setup` (module `scan`) | `commands/aid-init.md` → "Ownership — `project.yaml`" | — |
| `config/permissions.yaml` | `/aid-setup` (module `permissions`) | `commands/aid-init.md` → "Ownership — `permissions.yaml`" | `test-aid-config-summary.bats` (reads it) |
| `config/execution.yaml` | `/aid-init` composes; PM hand-edits | `commands/aid-init.md` → "execution.yaml Generation" + "Existing Project — `gate_profiles` Upgrade" | `test-init-idempotency.sh` |
| `config/plugin.yaml` | **two writers** — `/aid-init` and `/aid-run` PRE-FLIGHT (path self-repair); nobody but fresh init or a human writes `dispatch_mode` | `commands/aid-init.md` → "Ownership — `plugin.yaml` has a SECOND writer" | — |
| `config/check-severity.yaml` | **two writers** — `/aid-init` creates once, `aid-fsm.sh promote-check` mutates; `/aid-setup` does not touch it | `commands/aid-init.md` → "check-severity.yaml — severity registry" | — |
| `config/integrations.yaml` (conditional) | `/aid-setup` (module `integrations`); init writes exactly one key at creation | `commands/aid-init.md` → "Ownership — `integrations.yaml`" | — |
| `work/active.md`, `work/backlog.md`, `work/timeline.jsonl` | `/aid-init` creates; the pipeline appends | `commands/aid-init.md` → "active.md template" / "backlog.md template" | — |
| `.gitignore` (not counted) | AID backfills per line | `commands/aid-init.md` → ".gitignore (copied from defaults/.gitignore)" | `test-init-idempotency.sh` |
| `.git/hooks/pre-commit`, `pre-push` (not counted) | AID owns **only within its marker block** | `commands/aid-init.md` → "Git Hook Installation" | — |
| `CLAUDE.md` | `/aid-setup` (module `claude-md`) — `/aid-init` never writes it | `commands/aid-init.md` → "Ownership — `CLAUDE.md`" | — |

Two entries are honest rather than tidy on purpose. `project.yaml` has a third,
DELEGATED writer — `agents/project-scanner.md`, triggered by `/aid-setup` — and
it may only extend auto-detected sections; the merge rule in
`skills/setup/project-scan.md` governs, and it is merge, never overwrite.
`CLAUDE.md` carries a recorded KNOWN GAP: `skills/setup/claude-md.md` does not
yet emit an ecosystem-reference block for the `vulcan` profile, so init's
pointer would have pointed at something that does not exist. That was written
down as a gap instead of being smoothed over.

**Adding to this area.** A new init-written file gets an owner declared at its
write site in the same "Ownership — `<file>`" form, and if it has a second
writer, name it — an undeclared second writer is the whole defect class this
section exists to close. Do not restate the manifest count anywhere; refer to
it.

### One read-only configuration summary

`scripts/aid-config-summary.sh` renders the effective AID configuration once,
and BOTH `/aid-init` (as its closing output) and `/aid-setup` (before its module
menu) present its output VERBATIM. Before this, each described the result in its
own prose from its own reads, and the two drifted — most visibly around
`active_preset`, where a fresh workspace reads `autonomous` next to
`autonomous_mode: false` and each surface improvised its own wording. That pair
now has two cases and two fixed strings, used verbatim by three surfaces.

The read-only contract is the load-bearing half, and it is PROVED rather than
declared: `test-aid-config-summary.bats` (t0) snapshots the whole project tree
around an invocation, runs the script against a write-protected tree, checks
`TMPDIR` is left clean, and greps the source for any write operation. A missing
workspace, a missing config file and an unparseable config file are all REPORT
LINES, not errors — a summary must be able to summarize a broken configuration
rather than crash on it — and no rendered value is ever empty, because an
absence with no word for it reads as a value.

`test-init-idempotency.sh` (t1) pins the re-run contract, and its scope is
narrower than the command's: it drives the SCRIPTED substrate — the
execution.yaml composer, the `.gitignore` backfill lib, the base manifest, a
DECLINED `gate_profiles` upgrade. It does **not** cover the prose-executed steps
such as hook installation, which have no shipped library to drive at this HEAD.
That is why Step 8 mapped the harness onto the EXISTING `init_idempotency`
registry row instead of appending a second row: two rows for one check is a
duplication `registry_cite_validation` structurally cannot catch, because the
ids differ and uniqueness stays green.

**Adding to this area.** A new configuration value gets a line in the summary
with an explicit word for its absence, and a case in the summary suite. If it
needs a write, the write belongs in the command that owns the file — a summary
that writes is a summary in the wrong place.

### The communication contract, the renderer family, and the artifact layer

`skills/communication.md` defines, ONCE: the four PM cards (finished,
decision-required, blocked, progress), the D16 output-product table with each
product's audience, the ordering rule (outcome first, identifiers and paths
last), the language rule, and the publish-before-present clause. Other surfaces
REFERENCE it; none may restate a card skeleton.

`test-communication-wiring.sh` (t0, merge path) is what makes that a mechanism
rather than a preference:

1. **Reference** — every surface that talks to the PM at a boundary names
   `skills/communication.md` literally.
2. **Publication** — every site invoking a deterministic renderer carries the
   canonical publish clause VERBATIM. One literal, defined in the contract and
   pasted unchanged: a loose grep passes on a paraphrase, which is exactly how
   two differently-worded clauses ship and neither is enforced. The sites are
   FOUR, not three — `skills/pipeline.md` carries two distinct renderer
   invocations (gates phase and plan boundary), each anchored on its own
   renderer name, because listing the file once would let the gates path pass on
   the plan path's clause.
3. **Superseded fragments** — the shapes the contract replaced are gone: the
   metrics-first DONE-review header, the hardcoded Czech language mandate in the
   two verify commands, and any second definition of a card skeleton, counted
   over UNFENCED text only (a card inside a fence is an example; the contract's
   own cards are fenced by design and it is exempt, verified separately).

**What none of this claims: that a page was ever published.** The renderers
write a body file and print a card. The Artifact tool call is a live controller
act, wired in `commands/*.md` and `skills/pipeline.md`. The wiring check runs
happily on a CI box with no Artifact tool at all, and the registry rows are
worded as wiring-presence guards for exactly that reason.

The renderer family is three libraries with one shape:

| Library | Boundary | Canonical input |
|---|---|---|
| `lib/aid-artifact-render.sh` | none — the generic body renderer everything else builds on | `facts_json` + `prose_json` |
| `lib/aid-gate-outcome-summary.sh` | the gates run | the runner's gates report (`--report-file`, else nested, else flat — first hit wins, and the resolved path goes in the provenance footer) |
| `lib/aid-plan-close-summary.sh` | plan-final / close | the PM brief AND the release decision, both required |

Each is a pure function of its inputs plus the template. Numbers are COUNTED,
never asserted — there is no EPIC total field, so `epics | length` is counted
from the array — and both boundary renderers FAIL CLOSED when a canonical input
is missing rather than narrating around the gap. `aid-plan-close-summary.sh`
names the gate report path but deliberately does not open it, because that would
reintroduce the sibling-evidence read the D6/D9 cycle-break exists to forbid.

The artifact layer itself is `lib/aid-artifact-render.sh` plus
`defaults/templates/artifact-outcome.html`, and its full spec — the 7-block
mapping table, the placeholder grammar, the caps and the redaction policy — is
authored at `defaults/templates/artifact-templates-spec.md` in this repo, ready
for the PM to publish into the ecosystem docs (see IMP-503; publication is a
cross-repo act this repo has no authority to perform). In short:

- **Placeholder grammar.** `{{fact:<jq.path>}}` is a scalar from `facts_json`,
  HTML-escaped, missing → the em dash, never invented. `{{prose:<key>}}` is a
  bounded model-written block, sentence-capped then block-capped then escaped,
  missing → the declared literal for that state. `{{html:<key>}}` is a fragment
  the library builds itself and is the ONLY grammar inserted as raw markup —
  callers cannot reach it. Substitution is SINGLE PASS, so a value containing
  `{{` is never re-expanded.
- **Caps in code, not in a prompt.** 5 items, 3 next steps, 5 links, ~220 chars
  per sentence, 320/300/220 for summary/core/ask. Overflow emits the declared
  literal carrying the TRUE remaining count, so a truncated list reads as
  truncated.
- **Blocks 1-4 and 6 always render**; 5 only with links, 7 only with an EXPLICIT
  detail target, never inferred. Block 6 is never omitted even when nothing is
  asked, because a silently absent ask block reads as "nothing is required of
  me".
- **Secrets are redacted, counted, and never fatal.** Every input is scanned
  before a byte is written; matches become `<redacted:NAME>`; the count is
  rendered in the provenance footer so a redaction is never silent; escaping is
  applied AFTER redaction, never instead of it. Failing closed here would
  swallow the very message telling the PM a run broke.

`test-integration-handoff-rendering.sh` (t2, **nightly only**) drives all three
renderers over checked-in fixtures for five delivery cases — finished,
decision-required, blocked, force-used, and incomplete (facts arrived, prose did
not). Its goldens record BLOCK ORDER only, so a wording edit inside a block does
not churn a fixture while a block that moves, vanishes or appears does fail, and
regeneration is a human act that exits 2 with the diff and never reports a pass.
Its malicious fixtures carry synthetic secret-shaped strings on purpose, so
leakage is proven impossible rather than merely absent.

One more single-authority repair belongs here. The rule turning the FSM's
0-based `current_step` into a human "Plan Step N of T" existed as six full prose
copies across five files; `skills/pipeline.md` now holds the only definition and
the other five carry a one-line reference. The human form is APPENDED after the
machine values, so every machine-parsed seam is byte-unchanged — verify-state's
JSON, the `status=advanced` stdout line the controller parses, the CP2 verdict
JSON, and every `step-N-verify.md` binding diagnostic, which keeps speaking
0-based because that is the evidence filename an operator must create.
`test-fsm-step-render.bats` asserts the single-authority shape, and it is **t2,
so nightly-only**: a drift detector, not a merge blocker, registered saying so.

**Adding to this area.** A new PM-facing boundary references
`skills/communication.md` and never re-specifies a card. A new renderer is a
pure function of canonical inputs, writes a body, prints a card, and its wiring
site pastes the publish clause unchanged. A new template keeps the seven blocks
in order and adds a constant, not a sentence asking a model to be brief. And
nothing anywhere — code, docs or a registry row — may say a page was published;
the strongest true statement is that the body renders and the publication is
wired.

## Test tiers (P081)

AID is the ecosystem's pilot for `/ecosystem/specs/test-standard`. The whole
point of the change: **the merge path stopped running the full portfolio.**
191 suites, last timed at 12 200 s (3 h 23 min), used to gate every plan
closure. They now run at 02:40 UTC, where they delay nobody.

### Choosing a tier

A suite declares its tier in its leading comment block, once:

```bash
#!/usr/bin/env bats
# aid-tier: t1
```

| Tier | Cost per case | Whole-tier budget | Runs |
|------|---------------|-------------------|------|
| `t0` | under 2 s     | under 2 min       | merge path |
| `t1` | under 30 s    | under 10 min      | merge path — this is what blocks a merge |
| `t2` | more than that, **or cross-component whatever it costs** | none | nightly |

Tier follows **measured cost and scope**. Not importance. Not "this one matters,
so it should block". A suite you cannot resolve to a subject file is
cross-component and therefore t2 however cheap it is — the scope half of the
rule is what stops T1 filling up with integration suites.

`aid-test-tier-assign.sh` proposes tiers from real measurements and ENFORCES the
aggregate budgets: while T0 exceeds 2 min or T1 exceeds 10 min it demotes the
most expensive member and prints why. The standard forbids tolerating an
overflow quietly, and a tool that only warned would be tolerating it.

### How the tag is read, and why it is a tag

`lib/aid-test-tier.sh` is the ONE reader — the runner's `--tier` filter, the
lint and the plan-time check all come through it. It scans the whole leading
comment block however long (nine suites in this tree open with 40-47-line
headers), and two tags anywhere in a file is a violation naming both lines,
never first-wins.

It is a tag and not a `tests/t0|t1|t2/` directory because the directories were
COSTED: ≈420 literal path references would have had to move with the files —
201 enforcement-registry `test:` fields with line anchors, ~468 catalog fields
whose ids are join keys for the ledger and receipts, every CI job, every gate
command. The tag costs zero of those. Re-open the decision only with a plan that
counts again.

### Measuring

```bash
run-all-tests.sh --timing --include-delegated     # one record per suite
aid-test-tier-assign.sh --format md               # the proposed table
aid-test-tier-lint.sh                             # the tree agrees with itself
```

`--timing` is opt-in and every existing invocation is byte-identical without it.
Records append to `.aid-o/work/test-durations.jsonl` under the STATE root, so a
measurement taken from a plan worktree survives that worktree's teardown. The
nightly passes `--timing`, which is why tier assignments stay honest without
anyone ever running a measurement campaign again.

An unmeasured suite is never defaulted into a tier, and a run cut short is
recorded `censored` and treated as unmeasured. A partial table exits non-zero
so nobody mistakes it for a complete one.

### What the nightly does

`.github/workflows/nightly-tests.yml` runs T2, then:

* writes `/opt/eco/data/aid-nightly/aid-orchestrator/<date>.json` plus
  `latest.json` — a shared HOST path, deliberately NOT under `.aid-o/`, because
  the CI job runs in the runner's own checkout where `.aid-o/work/` is
  gitignored and nothing written there could ever be read from your checkout;
* retries each failing suite exactly ONCE — passing on the retry makes it
  `flaky`, which is quarantined (`aid-test-quarantine.sh`) rather than counted
  as a failure or waved through as green;
* sends ONE Telegram message on a NEW failure; a failure already in last
  night's artifact increments a streak instead of sending again; a green night
  sends nothing;
* renders one line in `/aid-status` and at `/aid-plan` orientation — the second
  surface exists so a muted channel never means a lost result, and a nightly
  that silently STOPPED running renders as its own finding.

### The selector's honesty check

Once the merge path is T0+T1, the targeted selector is most of what stands
between a change and a merge. `aid-selector-honesty-check.sh` replays
`aid-select-tests.sh --dry-run` over the merges since the last nightly and asks,
of every failing suite, whether that merge's own gate would have picked it.

Three classes, because they need three different fixes: `unmapped` (the mapping
has no opinion), `mapped_but_thin` (it had an opinion and it was wrong — the
class that matters most, because for a mapped path the selector's exit-3/exit-11
escalation is structurally unreachable, so it fails silently and confidently),
and `unmappable` (a cross-cutting invariant no path could ever select — not a
gap). An escalating exit COUNTS AS SELECTION: manufacturing gaps out of a safety
net produces a report nobody believes.

### The reaper

Five places in this process add tests and, before this, none removed any.
`aid-test-reaper.sh` runs on the first nightly of each month and PROPOSES, with
a reason per row, from the content scanner's vacuous-green and duplicate
findings and from the durations journal. It performs no deletion — deleting is a
normal reviewed PR — and it has **no quota**, because a quota turns a clean-up
into a hunt for something to sacrifice.

It names the input it does not have. The standard's fourth signal — how long
since a suite last caught a REAL regression — had no source in this tree (`git
log` gives change age, not failure age), so it fills in as nightly artifacts
accumulate and the tool says so rather than proposing from three while implying
four.

### Adding to this area

A new suite declares its tier in the plan that creates it — `- Test: \`path\`
(tier: t1) — what it proves` — and generation refuses without it. Adding a case
to an EXISTING suite needs no declaration and never will: that is the move worth
encouraging. If you add a signal to the reaper, it proposes; if you add a check
to the lint, it must be mechanical and its false-positive shape pinned by a test
(the naming rule matches segment-wise precisely so `test-cp1-gate.sh` is not
condemned for containing "p1"). And if you find yourself wanting a tier for a
reason that is not cost or scope, the answer is no — that is the rule the whole
standard rests on.


## Concurrent agents, three hook rules and a gate check, credible UI proposals (P087)

### Adding a step to a concurrent wave

A wave is the plan's `**Parallel group:**` value; two steps share a wave when
they may run at the same time. To put a step into one:

1. Declare its `Files:` honestly — the wave check
   (`scripts/aid-plan-parallel-check.sh`) proves two steps of one wave name no
   common path.
2. Declare `**Shared interfaces:**` when the step changes an endpoint, a
   schema, a configuration key or a registered name — the second dimension the
   check compares (normalised: case, surrounding slashes, whitespace). Absent
   means "none", and that is the honest answer for most steps.
3. Know what the isolation buys and what it does not. Each step runs in its own
   worktree (`<dispatch.worktree_base>/step-<step_id>`, default `.aid-worktrees`,
   on `step/<step_id>`); a collision surfaces as a **merge conflict**, the
   merge is aborted, the tree left untouched, the step's tree reset onto the new
   base (`aid_parallel_step_reset`) and the step repeated. What it does NOT buy is
   caught nowhere here: two steps changing the same behaviour through different
   files and an interface nobody declared merge cleanly. That boundary is written
   into the registry (`parallel_dispatch_wave_check`, `not_guaranteed`).

The decision is `aid_parallel_decide` (`scripts/lib/aid-parallel-dispatch.sh`):
`concurrent slots=N` or `serial: <reason>`, exit 0 either way — the brake
(`dispatch.max_parallel: 1`), a strategy other than `worktrees`, a repository
that cannot hand out worktrees, a wave of one, a collision in THIS wave, a check
that cannot run: every one degrades to the sequential path. `pipeline.md §4`
"Parallel groups" is the controller's instruction.

### The dispatch contract

`scripts/lib/aid-dispatch-contract.sh` builds a PACKET from `plan.json`
(objective, allowed paths, dependencies, expected artifacts, acceptance
criteria, UI contract, the step's own evidence directory) with a version, and
judges the agent's `aid-return` block against the packet and the DISK: the
version must match, promised artifacts must exist, every file git sees changed
must be declared, out-of-scope files are named, another step's evidence
directory is refused. `aid-fsm.sh increment-step` re-runs the validation for a
contracted step and refuses to advance without an accepted return — that is the
enforcement; the library is the mechanism. The controller commits each accepted
return itself (`aid_dispatch_contract_commit`, which validates first), one at a
time — the protocol against a mega-commit; what the FSM guarantees is that a
contracted step never advances on an unvalidated, unfinished or rejected return.

### The three hook rules, and the one that is deliberately not a guard

Rows in `defaults/hook-registry.yaml`, handlers in
`scripts/lib/aid-hook-rules-turn.sh` and `scripts/lib/aid-worktree-registry.sh`,
following the four steps of "Adding a harness hook rule" above:

- `turn_step_open` (`Stop`, controller, degree 2, fail-closed) refuses to end
  a turn while a step this session dispatched has not been advanced, unless the
  last message is a Decision card or a Blocked card (`blocked` is now a label in
  `defaults/decision-card-labels.yaml`).
- `turn_write_scope` (`PreToolUse`, any, degree 3, fail-open) names a Write/Edit
  outside the open step's allowed paths BEFORE it lands, as context. It does
  not block, on purpose: the catch sees Write and Edit and never a shell
  redirection, so blocking here would be protection with a hole the size of
  `bash`. The contract validation at return time is what refuses.
- `worktree_registry_notice` (`SessionStart`, controller, degree 3) reports
  plan worktree records that need a decision — a recorded tree that is gone,
  a closed plan's tree still on disk — each with its audited command.
  `aid-plan-fsm.sh worktrees` is the same scan on demand. Nothing removes a
  tree; the suite asserts the library contains no removal.

### Gate scripts come from the branch; gate configuration does not

`aid-run-gates.sh` fails a gate BY NAME when a repo-relative script its
command names is not in the tree the gate runs in, with no fallback to the
primary checkout (`gate_script_in_tree`). Configuration (`execution.yaml`) stays
at the state root, and `gate_config_from_branch` records why that half is not
built: `.aid-o/` never reaches a worktree, and configuration read out of a
working tree would let a downloaded repository run code.

### UI proposals

`scripts/lib/aid-ui-proposal.sh` builds a proposal's basis from the application:
the real screen captured per viewport on fixture data (no fixture, no capture —
production data is never photographed), or the design system inventoried from
the tree, MARKED as having no live baseline. `ui.responsive` in `project.yaml`
(default true) decides the viewports — desktop and mobile, or desktop alone —
and `aid_ui_proposal_check` refuses a proposal missing one, naming it. Two
models get the same brief through `lib/aid-brainstorm-opponent.sh`; the PM
decides.


**Last Updated:** 2026-08-25

## Artifact profiles and the file-based release scope (P089)

Two independent mechanisms landed in the same window. They share nothing but
the observation behind both: a rule that decides from a PROMISE — a block
heading, a commit label — cannot be trusted, and a rule that decides from
STATE can.

### What a page of a given type owes

`lib/aid-artifact-render.sh` renders every PM-facing page in AID, and until
P089 it enforced one skeleton for all of them: seven blocks, caps, no paths in
the link blocks. What belongs INSIDE a block it did not say — so the gates page
could satisfy every structural rule and still be worthless (it announced "6 of
9 passed" over a run where **nothing** failed and three gates had simply not
run).

`facts.artifact_type` now names one of five types, and
`defaults/artifact-profiles.yaml` says what each owes. **Adding a type is a
section in that file**, never a branch in the renderer.

| `artifact_type` | Renderer/caller |
|---|---|
| `brainstorming` | `lib/aid-brainstorm-summary.sh` |
| `plan` | `lib/aid-plan-summary.sh` |
| `gates` | `lib/aid-gate-outcome-summary.sh` |
| `epic_done` | `lib/aid-epic-summary-page.sh` |
| `plan_done` | `lib/aid-plan-close-summary.sh` |

Three things the profile decides:

1. **Required fields.** A page missing one of its type's fields does not
   render, and the refusal names the type and the field.
2. **State-derived wording.** A type marked `outcome_from_state` hands the
   renderer four counts (`passed` / `failed` / `not_run` / `waived`, plus an
   optional `blocked`) and the renderer COMPOSES the result, verified and
   did-not-run tiles from them, dropping whatever the caller wrote there.
   This is the important half: "zero failures" beside a sentence about failure
   is now impossible to write, rather than something a vocabulary check would
   have to catch — and no vocabulary check is ever complete.
3. **Between-field contradictions.** Block 6 may not say "nothing is expected"
   beside a list of next steps; a link may not be nameless, may not repeat the
   detail target, and **may not be a file path** in blocks 5 or 7.

What is NOT checked is whether the page is any good. That is a reader's
judgement, and the boundary is written into the standard the same way.

**Adding a caller.** Build `facts` with `artifact_type`, call
`aid_artifact_render`. If the renderer refuses, the profile is telling you
what your type owes — the fix belongs in the profile or in your facts, never
in an exception in the renderer. A caller that passes no `artifact_type` keeps
the pre-P089 behaviour and says so on stderr; no production caller is on that
branch, and `test-artifact-profiles.bats` asserts that over the whole caller
set rather than per caller.

**A milestone owes a page.** `lib/aid-artifact-obligation.sh` refuses to close
a turn that finished one of three milestones without rendering its page: a
written plan, an EPIC whose review ended, a closed plan. **A step owes nothing,
and a failed step owes nothing either.** The EPIC page is produced by
`cmd_done_advance` on the review→release edge — named, not instructed, because
a rule that demands a page nobody produces is exactly the kind of rule this
plan exists to stop writing.

### Whether a range of work requires a release

The pre-push guard used to decide from the commit subject. Both directions were
wrong: `fix(tests):` blocked a push that changed no application code, and
`chore:` could change the application and pass.

`lib/aid-release-scope.sh` decides from the FILES, in a fixed order that is the
same in all three copies of it:

1. list the commits in `<last tag reachable from the judged commit>..<commit>`
   and **remove** those carrying a `No-Release: <reason>` footer;
2. take the **UNION** of the paths the remaining commits touched;
3. decide that set against `versioning.release_exempt_paths` and
   `versioning.app_paths` from `.aid-o/config/project.yaml`.

A union and not a diff: once commits are removed the remainder is no longer a
contiguous range, and `git diff` has nothing to compute over it — two
implementations would each invent an answer. Consequences deliberately accepted
and pinned by tests: a revert adds its own paths (a change and its undo still
require a release); a merge commit contributes only its own first-parent diff,
while the commits it brought in count on their own, because merged work is work
being released; where an exempt and a non-exempt commit touch the same path,
the non-exempt one wins.

**The `release:` label does not move the boundary.** Anyone can write a commit
whose subject starts `release:` after an application change; the boundary is
the last version tag, which is a verifiable statement about what shipped.

Three consumers, one authority:

| Consumer | What it does |
|---|---|
| `defaults/hooks/pre-push` | blocks, naming the commits that caused it |
| `scripts/aid-release-check.sh` | prints the same verdict into CI and **always exits 0** |
| `scripts/aid-release.sh` | asks the library before reading any commit subject |

The hook cannot source the library — it runs in the consumer's repository — so
it carries a **verbatim copy** between `AID-RELEASE-SCOPE-PORTABLE-START/END`.
`test-release-scope.bats` byte-compares the two. If you change the library,
copy the region across; the test is the reason two copies are survivable.

**Fail-open on purpose.** No `yq`, no config, or no
`versioning.release_exempt_paths` → verdict `no_config` and every consumer
keeps the old label behaviour, with one hint line. A repository with no version
tag → `no_tag`, and it passes: a first push must not demand a release.

**`scripts/gates/release-paths-drift.sh`** compares those two lists against a
Dockerfile's `COPY`/`ADD` sources, because the config and the image are two
claims about the same thing. In THIS repository it is wired as
`check_release_paths` with `required: false` in the `full` and `release`
profiles: a disagreement is reported and the run continues, because the split
between AID's two products — the image carries `packages/`, the plugin travels
through the git marketplace and never enters the image — is a question for a
person, not a defect the running EPIC introduced. It matches LITERALLY, so a
glob in the Dockerfile (`COPY package*.json`) needs the same glob in
`app_paths`. A consumer project has it attached to nothing until they wire it.

## The plan continues itself (P090)

**The question this answers:** a plan has six EPICs; who starts the second one?
Until P090 the answer was "whoever remembers" — `skills/pipeline.md` described
the sequence to a human, and a test could prove at most that the description
existed. It is now four layers, and they are worth keeping apart because they
have very different strength.

### Layer 1 — the ask (`queue_peek_next`)

Everything else stands on one split. `queue_claim_next` used to select AND write
`status=running` in the same breath, so **asking the queue what was next meant
taking it**: a turn that then ended left an EPIC marked running with nothing
running. The selection is now one shared function, `_queue_scan_next`; `peek`
applies none of its writes, `claim` applies all of them. One selection, so the
two can never drift.

`aid-plan-fsm.sh next-epic <plan_id>` is that read as a command. Same exit
codes as `claim-next` (0 an id, 1 `blocked:`/`none`, 2 usage, 3 lock), plus one
rule that matters more than the rest: **a lock it could not take is exit 3 and
never `none`.** "I could not look" read as "there is nothing left" is precisely
how a plan ends while it is unfinished. For the same reason `next-epic` refuses
a plan this repository never started, rather than answering `none` for it.

### Layer 2 — the loop (`scripts/aid-plan-continue.sh`)

Five links, and it stops at the first that fails:

| # | Link | Guarantee |
|---|---|---|
| 0 | **proof** | `git merge-base --is-ancestor <task branch> plan/<id>`. Nothing is written before it passes |
| 1 | **mirror** | `set-status <epic> merged_to_plan`, skipped if already there — that is what makes a re-run harmless |
| 2 | **ask** | `next-epic`, no side effect, recorded in the plan timeline |
| 3 | **claim** | `claim-next`; if the queue moved since the ask, the claim wins and the difference is recorded |
| 4 | **start** | `epic-start` on exactly what the claim took; if it fails, the claim is undone |

Link 0 exists because of one asymmetry: a queue entry that carries no
`merge_target` is judged **by its status alone**, so an unearned
`merged_to_plan` there would falsely unblock its dependent. The mirror has to be
earned against Git before it is written.

`epic-merge-to-plan` calls this itself after a successful merge, **implicitly**,
whenever the plan's own `autonomy` field says `auto`. Implicitly and not behind
a flag: a flag leaves the main path callable without it, and "nobody has to
remember" would be false the first time someone typed the command by hand.
`--no-continue` turns it off, `--continue` forces it for a manual plan.

**The `autonomy` field is WRITE-ONCE, and that is the sharpest limit on all of
this.** `plan-start` sets it from `--autonomy auto|manual`, or — since no
production caller passes that flag today, `aid-auto-pipeline.sh` included — from
`.aid-o/config/permissions.yaml` (`autonomous_mode: true`, read fail-closed, a
real YAML boolean or nothing). Nothing changes it afterwards. So a plan started
before autonomy was switched on reads as manual for its whole life, one started
after it stays `auto` even while a PM drives it by hand (`--no-continue` is the
per-merge escape), and a workspace with no `permissions.yaml` — which includes
**this** repository — resolves every plan to manual and leaves the continuation
inert. Changing a live plan's mind means editing `plan-state.yaml`.

**The field lives on the PLAN, in `plan-state.yaml`** — not on the run record. `auto_controller` is the obvious
candidate and is the wrong one: a run removes its own entry on the
`done-advance review→release` edge (`aid-fsm.sh:286`), so by the time an EPIC
merges there is nothing left to read. Absence reads as `manual`, so every plan
created before P090 is silent rather than surprising.

**The boundary at `aid-plan-fsm.sh:89-92` is intact.** That command still writes
nothing to the queue. It hands over to a separate program which establishes its
own proof — the queue write stays something a program earned, not something the
merge path asserted.

### Layer 3 — the spawn (off by default)

`epic-start` prepares state; it does not RUN an EPIC — an agent does. With
`autonomy.spawn_next_epic: true` in `.aid-o/config/project.yaml`, the claimed
EPIC is started as a supervised job:

```
aid-job.sh run --jobs-dir .aid-o/work/jobs --id <pre-allocated> --deadline <n> \
  -- env AID_JOB_ID=<pre-allocated> claude -p "/aid-run --auto --epic <id>"
```

Four things in that line were decided rather than assumed:

- **The slash form.** That `claude -p "/aid-run …"` dispatches a command rather
  than echoing prose was not taken on trust. One run, with the predicate fixed
  BEFORE it:

  | | |
  |---|---|
  | command | `claude -p "/aid-help" --output-format stream-json --verbose` |
  | predicate (declared beforehand) | `grep -c -o '/aid-[a-z-]*'` ≥ **2** |
  | measured | **44** — and `is_error: false`, `subtype: success`, 3 turns |
  | verdict | SATISFIED → the slash form ships |

  The answer was the `/aid-help` skill's own output, i.e. the command was
  dispatched, not echoed. The fallback the plan had prepared — a sentence saying
  what to run — is therefore not used. The raw transcript is in the gitignored
  evidence directory (`.aid-o/work/evidence/P090/steps/step_6/`), which is why
  the numbers are written here, where a reader outside the authoring tree can
  check that a measurement happened at all.
- **`--auto --epic`, never bare `/aid-run <epic>`.** The bare form is MANUAL
  mode. A session recorded as manual would not continue the plan after its own
  merge, and the chain would stop — a second time, by another route.
- **The pre-allocated id, passed twice.** `aid-job.sh` generates an id only
  after assembling argv and exports nothing, so the session has no other way to
  learn its own. It goes to the supervisor as `--id` and into the session's
  environment as `env AID_JOB_ID=`. Which matters because of the next point.
- **The self-exclusion.** The session started here reaches its own merge, calls
  the loop again, and the job it would find running is **the job it is running
  inside**. Refusing on that would stop the chain at length one, and nothing
  would restart it — `aid-job.sh` is a supervisor, not a daemon. So the check
  ignores `AID_JOB_ID`.

The cap, the running check, the reservation **and the launch** all happen inside
one hold of the queue's own lock, so two racing continuations cannot both start
a session.

The lock is the **jobs directory's**, not the queue's: nothing in this decision
reads or writes the queue file, and holding the queue lock across a launch would
block `peek-next` and `claim-next` for every other plan in the workspace while
one session starts.

That single hold is only safe because of a fix that landed one level down.
`aid-job.sh` detaches with `setsid` and used to redirect only 0/1/2, so the
wrapper — and the deadline watchdog it starts, a `sleep <deadline>` that lives
for the whole deadline, an hour by default — inherited every other descriptor
the caller held. Two consequences: a caller holding an flock kept holding it for
the job's lifetime (flock drops only on the last descriptor), and a caller whose
output was read through a pipe never reached EOF. **`aid-job.sh` now closes every
descriptor above stderr inside its own detach**, which is where it belongs: five
scripts already call `run`, and each had the same latent hazard.

That was measured, not reasoned about: a bats suite ran all its cases and then
sat for fifteen minutes with no children, because six `sleep 3600` processes
still held fd 3. `test-continue-spawn.bats` now pipes a spawning run through
`cat` and fails if EOF does not arrive.

An earlier cut of this code instead released the lock before launching, which
left a window where a second continuation saw a raised count but no job
directory yet and started a second session.

A reservation that cannot be written, or a spawn decision that cannot be
recorded in the plan's timeline, is a **refusal** — a session nobody could later
find or count is not an auditable action. A slot reserved and then failed to
launch stays spent: under-spawning by one costs a session, double-spawning costs
two. And a job record that cannot be READ counts as live, for the same reason.

`autonomy.max_spawned_epics` is **per plan**, not per workspace. Two plans with
spawning on do not add up. That is a choice; the enforcement registry records it.

### Layer 4 — the reminder (`lib/aid-queue-continuation.sh`)

Two hook rows, both degree 3, both `failure: open`. On `Stop` it names every
autonomous plan that still has work; on `SessionStart` it reads back the
continuation guidance an interrupted run left — after a dead controller, the
only reader that guidance has.

**It is degree 3 because it cannot be anything else.** `aid-hook.sh:315-319`
sets `no_block=1` the moment the harness reports `stop_hook_active: true`: a
Stop rule may still speak, but no refusal from it may stop the turn again. A
barrier built here would hold exactly once and then go quiet — worse than no
barrier, because everyone would believe it was one.

It asks through `peek`, never `claim`. A reminder that consumed the queue would
create the very orphan it exists to warn about.

A plan whose queue it cannot read gets **no line at all**, and the reason goes
to stderr. Silence there is not a claim that the plan is finished — nothing is
claimed — and a reminder built on "I do not know" is noise that teaches a reader
to skim past the ones that mean something.

### The guidance file

`.aid-o/work/evidence/<plan>/continue-state.json`, schema `aid-plan-continue/1`,
written atomically at the end of **every** run — including the ones that failed,
since those are the ones somebody comes back to. It carries `job_id`,
`jobs_dir`, `job_fingerprint` and `spawned_count` as well as the plan's own
position, because `aid-job.sh status`/`collect` need an exact job id and nothing
else in the plan knows it after an interruption, and because a cap that does not
survive a restart is not a cap.

It is a **guidance, not an authority**: the next run reads it, refuses an
out-of-sequence mirror on the strength of it, and then asks the queue anyway —
what is merged can have changed while the turn was gone. It is deliberately NOT
the existing `aid-auto-resume/1`, which `aid-run-gates.sh` writes about an
unfinished gate and `aid-fsm.sh` reads: folding a queue answer into it would
change a schema somebody else parses.

### The one state nothing cleans up

An entry left at `running` by a dead process is either a crash between claim and
start, or somebody else's live run — indistinguishable from the outside. It is
**reported by name** on every path that gets past the mirror — a run that stops
at the proof has established nothing about this plan and says so instead — and
released only by a human's
`aid-plan-continue.sh --reclaim <epic_id>`, which no automation calls. Taking a
live run's entry out from under it is worse than waiting.
