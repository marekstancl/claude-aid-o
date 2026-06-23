# AID Protocol v2 — Schema Directory

This directory contains canonical JSON Schema definitions for AID protocol v2 artifacts.

The validator `aid-protocol-validate.sh` checks fields marked `enforced`; fields marked `reference` are described in the schema but are NOT enforced in E1.

This directory does NOT claim full JSON Schema validation. The JSON Schema files are canonical references; the bash validator enforces a named subset of invariants.

---

## Files

| File | Purpose |
|------|---------|
| `aid-protocol-v2.schema.json` | Canonical shared envelope schema (JSON Schema draft 2020-12) |

Type-specific schemas extend this envelope — Step 4 will add them.

---

## Enforced vs Reference

| Field (jq path) | Type / enum | Enforcement |
|---|---|---|
| `.schema_version` | const `"aid-2.0"` | **enforced** (presence + exact value) |
| `.artifact_type` | enum 14 types | **enforced** (presence + enum member) |
| `.producer` | string `"<tool>@<ver>"` non-empty | **enforced** (presence + non-empty) |
| `.created_at` | string ISO-8601 UTC `Z` | **enforced** (presence + regex `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`) |
| `.control_protocol` | enum `aid-2.0 \| legacy` | **enforced** (presence + enum) |
| `.identity.project_id` | string non-empty | **enforced** (presence) |
| `.identity.{plan_id,epic_id,run_id,step_id}` | string \| null | reference |
| `.subject.subject_hash` | string `sha256:<hex>` | **enforced** (presence + format `^sha256:[0-9a-f]{64}$`) |
| `.subject.{plan_sha256,contract_bundle_sha256}` | string \| null | reference |
| `.revision.base_sha` | string \| null | reference |
| `.revision.head_sha` | string `<hex>` non-empty | **enforced** (presence; mismatch with `--current-head` → fail) |
| `.revision.head_is_current` | bool | **enforced** (must match `--current-head` comparison) |
| `.revision.freshness` | enum `current \| stale` | **enforced** (consistency with head_is_current) |
| `.status` | enum `pass \| fail \| skip \| unverifiable \| pending \| blocked` | **enforced** (presence + enum) |
| `.verdict.kind` | enum `none \| delivery_ready \| release_ready` | **enforced** (presence + enum) |
| `.verdict.ready` | bool | **enforced** (presence; bool) |
| `.provenance.dispatch_mode` | enum `deterministic \| agent_tool \| subagent` | **enforced** (presence + enum) |
| `.provenance.generated_by_tool` | string non-empty | **enforced** (presence) |
| `.findings[]` | array | **enforced** (if present: per-finding invariants below) |
| `.findings[].fingerprint` | string `sha256:<hex>` | **enforced** (presence + format; determinism via helper) |
| `.findings[].occurrence_id` | string non-empty | **enforced** (presence) |
| `.findings[].severity` | enum `critical \| high \| medium \| low \| info` | **enforced** (presence + enum) |
| `.findings[].action_owner` | enum `implementer \| reviewer \| pm \| gate-fixer` | **enforced ONLY when** `severity ∈ {critical,high}` (blocker) |
| `.findings[].{title,human_summary,recommended_remediation}` | string | reference |
| `.findings[].{evidence_refs,log_refs}` | array | reference |
| `.blocking_reasons[]` | array of `{finding_occurrence_id, summary}` | reference |
| `.applicability.{required_lenses,completed_lenses,coverage}` | object | reference |

---

## artifact_type Enum (14 values)

```
plan_review
plan_graph
contract_manifest
review_profile
delivery_gate
ui_fidelity
semantic_review
acceptance_evidence
audit_report
audit_input_manifest
release_decision
pm_decision_brief
curator
delivery_report
```

---

## Legacy Artifacts

Artifacts with `.control_protocol: "legacy"` are skipped by the validator (exit 0 with `legacy_skipped` note); legacy artifacts are not required to carry other enforced envelope fields.

---

## Edge Cases

- `.step_id` allows null: artifacts produced outside a step context (e.g. plan-level reviews) set `step_id: null`.
- `.findings` is optional: absent or empty array are both valid.
- `.blocking_reasons` and `.applicability` are optional reference-only fields.

---

## Freshness (head_sha / subject_hash)

An artifact is considered **stale** if either condition is true:

1. **HEAD mismatch** (`enforced`): `.revision.head_sha` ≠ the current git HEAD at validation time.
   - `aid-protocol-validate.sh --current-head <sha>` checks this.
   - Mismatch → exit 11 (`stale_or_head_mismatch`).
   - `.revision.head_is_current` and `.revision.freshness` must be consistent with the comparison result.

2. **Subject hash change** (`reference`): `.subject.subject_hash` has changed since the artifact was produced, indicating the referenced plan/contract was modified without committing.
   - This is a `reference` invariant in E1 — the validator checks the _format_ of `subject_hash` (exit 7), not the _content match_.
   - Content-mismatch detection is enforced by the owning phase (E4/C0), not E1.

### Per-run `control_protocol` lock

Each run sets `control_protocol: "aid-2.0" | "legacy"` at init. All artifacts produced in that run inherit this value. The validator (Step 2) checks this via exit code 2 (legacy → skip all enforced checks):

- `control_protocol: "legacy"` → validator exits 0 with `legacy_skipped` (no other enforced checks run)
- `control_protocol: "aid-2.0"` → all 13 blocking invariants are checked

**FSM wiring is E2+**: the per-run lock is defined here as schema (`run-control-protocol.schema.json`), but is not written to `fsm-state.yaml` by any E1 code. E2 will wire this into `aid-fsm.sh init`.
