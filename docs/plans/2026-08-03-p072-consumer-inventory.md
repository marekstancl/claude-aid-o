# P072 Step 1 — Consumer inventory of audit verdicts, artifacts and `--write-plan`

**Purpose.** Establish, before any contract changes, every code path and document that reads an
audit verdict, the consolidated findings, the remediation brief or the durable record — so a later
step cannot change a contract a hidden consumer depends on.

**Grounded at:** branch `feat/p072-test-audit-decision-quality`, base `602c045` (v2.68.0),
2026-08-03. Every row below carries the command that produced it and an excerpt of its real output.

> **This document was delivered late, and that had a measurable cost.** Steps 2–6 were implemented
> before this inventory existed. The consumer this inventory would have surfaced first — the
> production `finalize` → `consolidate` call site — was exactly the one that was missed: the new
> decision gate was built, tested and unreachable from the real entrypoint. That defect is recorded
> in §4 and was fixed as part of delivering this document.

---

## 1. Method

Three sweeps, each run from the repository root:

```bash
# A — artifact filenames
grep -rn "consolidated-findings\|implementation-plan-brief\|durable-record\|decision.json" \
  plugins/ --include=*.sh --include=*.md | grep -v node_modules

# B — verdict strings
grep -rln "remediation recommended\|needs measurement" \
  plugins/ --include=*.sh --include=*.md --include=*.json | grep -v node_modules

# C — call sites of the two production scripts
grep -rn "aid-audit-tests-finalize.sh\|aid-test-audit-consolidate.sh" \
  plugins/ --include=*.sh --include=*.md | grep -v node_modules
```

---

## 2. Producers

| Artifact | Producer | Evidence |
|---|---|---|
| `consolidated-findings.json` | `scripts/aid-test-audit-consolidate.sh` | sweep A: 21 hits, the highest of any file |
| `implementation-plan-brief.{json,md}` | `scripts/aid-test-audit-consolidate.sh` | same file, brief block |
| `durable-record.json` | `lib/aid-test-audit-write-plan-bridge.sh` (`…_persist`), called by `lib/aid-test-audit-chat-summary.sh:134` | sweep A |
| `decision.json` (**new, P072**) | `scripts/aid-test-audit-consolidate.sh` via `lib/aid-test-audit-decision.sh` | Step 2 |

---

## 3. Consumers

| Consumer | Reads | Would a new top-level `audit_status` field break it? |
|---|---|---|
| `lib/aid-test-audit-write-plan-bridge.sh` | verdict string, findings file, brief, catalog | **No** — it reads named fields, and the new field lives in a separate artifact |
| `lib/aid-test-audit-chat-summary.sh` | findings file, verdict | **No** — same |
| `scripts/aid-audit-tests-finalize.sh` | chains all three stages | **No**, but see §4 — it was passing the wrong argument set |
| `commands/aid-audit-tests.md` | documents the contract for the controller | **Yes, as documentation** — it stated an invocation that omits the new arguments (§4) |
| `defaults/schemas/test-audit-plan-brief.schema.json` | pins `verdict: "remediation recommended"` | **No** — the brief is unchanged |
| `defaults/schemas/test-audit-consolidated-findings.schema.json` | `additionalProperties: false` at lines 18 and 50 | **Would have**, had `audit_status` been added to the FINDINGS file. It is deliberately in a separate `decision.json` instead — this row is why. |
| `scripts/tests/test-integration-e2e-audit-pipeline.sh` | finalize + bridge | Fixture only; updated in Step 3 |
| `scripts/tests/test-integration-remediation-handoff.sh` | consolidate + bridge | Fixture only; updated in Step 3 |

### Not consumers, despite matching the sweep

`aid-plan-fsm.sh`, `aid-pm-brief.sh`, `aid-release-policy.sh`, `aid-plan-close-check.sh`,
`aid-fsm.sh` and `aid-protocol-validate.sh` all matched sweep A on `decision.json`. They are
**unrelated**:

```bash
$ for f in aid-plan-fsm aid-pm-brief aid-release-policy aid-plan-close-check aid-fsm aid-protocol-validate; do
    printf "%-24s " "$f.sh"; grep -o "[a-z0-9-]*decision\.json" plugins/aid-orchestrator/scripts/$f.sh | sort -u | tr '\n' ' '; echo; done
aid-plan-fsm.sh          decision.json pm-plan-decision.json release-decision.json
aid-pm-brief.sh          release-decision.json
aid-release-policy.sh    release-decision.json
aid-plan-close-check.sh  pm-plan-decision.json release-decision.json
aid-fsm.sh               release-decision.json
aid-protocol-validate.sh release-decision.json
```

The only bare `decision.json` is `aid-plan-fsm.sh:3273`, and it is a usage comment, not a read:

```
3273:#   <release_decision.json> <release_decision_dual_run.json> <pm_decision_file>
```

The audit's `decision.json` lives under `.aid-o/work/test-audits/<audit-id>/`, so there is no
filename collision with the plan-lifecycle decision artifacts.

### Zero-match results, recorded rather than omitted

Sweep B found **no** consumer of the verdict strings outside the audit chain, its schemas and its
own tests. A zero-match is recorded here deliberately: a silently absent consumer is the blind spot
this inventory exists to close.

---

## 4. The consumer this inventory was supposed to catch

`aid-audit-tests-finalize.sh` is the single mandatory production entrypoint, and it invoked the
consolidator like this:

```bash
bash "${SCRIPT_DIR}/aid-test-audit-consolidate.sh" \
  --audit-id "$audit_id" --wave-artifacts-dir "$wave_artifacts_dir" \
  --dispatch-manifest "$dispatch_manifest" --output-dir "$output_dir"
```

No `--mode`, no `--inventory`, no `--project-root`. The consolidator therefore fell back to its own
default `audit_mode="measure"`, and `decision.json` is written only under `full`. Proven against the
real entrypoint before the fix:

```
$ aid-audit-tests-finalize.sh --audit-id p1 … --mode full
finalize --mode full rc=0
decision.json ABSENT
```

A real full audit produced no decision at all, and `--write-plan` then failed with
`decision_artifact_missing` — the gate was unreachable from production. After wiring the three
arguments through, the same invocation:

```
rc=0
decision.json WRITTEN: audit_status=complete
```

and full mode without `--inventory` now fails at argument validation, before any output directory is
created or any chat turn printed:

```
rc=2
--mode full requires --inventory (the consolidator measures coverage against it; …)
no output dir created — failed before doing anything
```

---

## 5. P069 scheduler read surface

Recorded here because P072 changes the meaning of a field the scheduler reads.

| Location | Reads |
|---|---|
| `aid-test-scheduler.sh:187` | `${project_root}/.aid-o/config/test-catalog.yaml` |
| `aid-test-scheduler.sh:204` | `${project_root}/.aid-o/config/test-scheduler-parallel-overlay.yaml` |
| `aid-test-scheduler.sh:226` | `($ru.parallel.status) as $catalog_status` |
| `aid-test-scheduler.sh:227-228` | overlay `promoted_status` **overrides** the catalog when the overlay is approved and `catalog_fingerprint_at_promotion` matches `runtime.fingerprint` |

This is the third parallel-safety authority recorded in the plan's Context. Step 25 re-grounds and
subordinates it; nothing in EPIC 1 touches it.

---

## 6. Conclusions carried into later steps

1. `audit_status` goes in a **separate** `decision.json`, never into `consolidated-findings.json` —
   that file validates with `additionalProperties: false` (§3).
2. Every production call site must pass the full contract explicitly; the consolidator's defaults
   are safe for a library but wrong for the entrypoint (§4).
3. `commands/aid-audit-tests.md` is a consumer in its own right: an agent following it exactly is a
   real caller, so a stale documented invocation is a real defect, not a docs nit.
4. The bridge, the renderer and both integration suites read named fields only, so they tolerate a
   new sibling artifact without change.
