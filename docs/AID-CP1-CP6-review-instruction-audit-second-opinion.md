# AID CP1-CP6 Review Refactor: Independent Second Opinion

**Status:** independent review note

**Date:** 2026-06-20

**Companion document:** [AID-CP1-CP6-review-instruction-audit-and-refactor.md](./AID-CP1-CP6-review-instruction-audit-and-refactor.md)

**Incident basis:** WAN E-044-2_3 manual document upload across React, FastAPI, SQLAlchemy and MinIO.

**Scope:** semantic acceptance, adversarial review, test-evidence quality and correlated-review controls.

## 1 Conclusion

The direction in sections 1-20 is correct, but it closes only one class of false-DONE:
mechanically undeliverable repositories and broken producer-consumer contracts. It does
not yet close the equally important case where the repository builds and tests pass, but
the implemented behavior violates the accepted plan across runtime boundaries.

The missing capability is not another generic reviewer. It is a structurally enforced
**acceptance-evidence and adversarial behavior contract**:

1. freeze the identity and meaning of every acceptance criterion;
2. trace each criterion through its complete production path;
3. audit whether its test can actually falsify the implementation;
4. require fault injection for stateful multi-system operations;
5. prevent implementation tests from silently redefining the requirement;
6. give one fresh-context semantic auditor responsibility for challenging the evidence.

Delivery Gate should therefore be retained, but must not be described or consumed as
proof of semantic correctness. It proves executable delivery. A separate evidence
contract must prove accepted behavior.

## 2 What the existing proposal gets right

This second opinion agrees with the following decisions:

- keep deterministic checks separate from LLM judgment;
- reduce correlated reviews instead of enlarging every prompt;
- keep CP2 local and make CP3 the integrated semantic review;
- bind all evidence to the reviewed HEAD;
- make Critical/High findings block independently of scores;
- remove merge-approval authority from Curator;
- replace CP5's boolean reader with structured release aggregation;
- simplify redundant review work after the new controls demonstrate value.

These decisions should remain. The amendments below extend them rather than replace
them.

## 3 Failure class not covered by Delivery Gate

E-044-2_3 passed targeted tests, document/session regression tests, TypeScript and almost
the entire backend suite. The escaped defects were semantic and cross-boundary:

| Escaped defect | Why green checks did not catch it | Required review capability |
|---|---|---|
| MinIO cleanup wrapped `flush()`, while the real SQL commit occurred later in a FastAPI dependency | the happy-path test proved upload and flush, not commit-time failure | transaction-boundary trace plus commit fault injection |
| selecting a SupplyContract did not derive and persist its DeliveryPoint | backend and UI were reviewed locally; no end-to-end field lineage was built | request-to-storage-to-read-path trace |
| `moved_away` contracts were accepted despite an explicit plan prohibition | existence/deleted checks looked plausible and no negative test represented the invariant | acceptance-criterion identity plus negative-case proof |
| the 20 MB guard ran only after reading the whole upload into memory | output behavior was correct for small fixtures | operation-order/resource-bound review |
| the plan required API-key agent `403`, but the implementation test changed the expected result to `401` | test and implementation agreed while both diverged from the frozen requirement | requirement/test drift detection |
| backend emitted top-level `message`, while UI read `detail` | mocks reproduced the UI assumption instead of the real middleware contract | producer-consumer response-shape validation |
| closing the modal retained file and hidden field state | component tests covered one mount and one submit only | UI lifecycle/state-transition scenario |
| "eight scenarios" existed, but several required scenarios were replaced by easier ones | review counted tests rather than matching scenario identity | AC-to-test matrix, never count-based evidence |

None of these defects requires a different architecture. They require reviewers to follow
the approved design through real control flow and to challenge whether the supplied
evidence proves it.

## 4 Add an acceptance-evidence contract

Add a structured artifact alongside `delivery-gate.json`:

```text
.aid-o/work/evidence/{epic_id}/{run_id}/acceptance-evidence.json
```

Minimum shape:

```json
{
  "_generated_by": "aid-acceptance-evidence@1",
  "epic_id": "E-...",
  "run_id": "R-...",
  "base_commit": "...",
  "head_commit": "...",
  "criteria": [
    {
      "id": "AC-07",
      "source": ".aid-o/plans/P044.md:425",
      "requirement": "DB commit failure after upload deletes the MinIO object",
      "production_trace": [
        "wan/api/persons.py:2037 upload",
        "wan/api/persons.py:2063 error boundary",
        "wan/db/session.py:34 actual commit"
      ],
      "positive_tests": [],
      "negative_tests": [
        "tests/integration/test_manual_upload.py::test_commit_failure_deletes_blob"
      ],
      "failure_injection": "AsyncSession.commit raises after MinIO upload",
      "deviations": [],
      "status": "pass"
    }
  ],
  "unmapped_criteria": [],
  "unapproved_deviations": [],
  "acceptance_ready": true
}
```

Normative rules:

- criterion identity is derived from the approved plan/task, never from test names;
- replacing a scenario with another scenario does not satisfy the original criterion;
- changing an expected status, field, failure mode or role is a deviation requiring
  explicit PM approval, not a test update;
- a test path alone is insufficient evidence: the artifact must state what failure the
  test induces and which assertion proves the requirement;
- `production_trace` must include the real owner of commit, serialization, middleware,
  persistence and read-back behavior where applicable;
- omitted criteria, empty required negative evidence or unapproved deviations make
  `acceptance_ready:false`;
- the artifact must be regenerated when either implementation or tests change.

The artifact can initially be produced by CP3 and validated structurally by the FSM. It
must not become another self-authored implementer checklist accepted without review.

## 5 Mandatory test-evidence audit

CP3 and Auditor must treat tests as claims to inspect, not trusted proof. For each
behaviorally significant criterion they MUST verify:

1. the test represents the same scenario and expected result as the approved source;
2. the test reaches the production boundary it claims to test;
3. mocks and fixtures use the real producer contract or are checked against it;
4. assertions inspect the persisted/read-back result, not only the HTTP status;
5. failure tests induce failure at the intended operation, not an earlier substitute;
6. conditional early returns, broad exception suppression and weak `called` assertions
   cannot turn missing setup into PASS;
7. scenario count is never used as a substitute for scenario identity;
8. a changed expectation is reported as requirement drift;
9. broad suite success does not replace a missing acceptance-specific test;
10. test cleanup does not conceal production cleanup defects.

For external side effects, a negative test should assert both sides of the invariant. For
example, commit failure after object upload must prove both that the database transaction
did not commit and that the object no longer exists.

## 6 Risk-triggered behavior traces and fault injection

The high-risk detector should require a behavior trace when any changed path includes:

- database mutation plus filesystem/object-store/network side effects;
- explicit or dependency-owned commit/rollback boundaries;
- authentication, authorization, role or visibility semantics;
- upload/download size, MIME or resource limits;
- public API request/response shapes consumed by another layer;
- IDOR-sensitive parent/child foreign-key binding;
- soft-delete, lifecycle-state or status-machine checks;
- UI state that persists across remount, navigation, tabs or entity switching;
- inheritance/default/clear semantics where empty, absent and inherited differ;
- background jobs, retries, idempotency or compensation behavior.

For these triggers, CP3 output must contain at least one complete trace in this form:

```yaml
behavior_traces:
  - invariant: "contract selection binds document to the contract and its delivery point"
    entrypoint: "UploadDocumentModal.handleSubmit"
    request_fields: ["supply_contract_id"]
    backend_transform: "derive delivery_point_id from SupplyContract"
    persistence_fields: ["documents.supply_contract_id", "documents.delivery_point_id"]
    read_path: "GET /persons/{id} -> DocumentsSection"
    negative_cases: ["foreign contract", "moved_away contract", "conflicting DP"]
    evidence: ["test names and file:line references"]
    result: pass|fail
```

Review instructions must explicitly require following called dependencies and downstream
consumers outside the changed-file list. Restricting semantic review to the diff would
again miss dependency-owned commits and middleware response transformations.

## 7 Checkpoint-specific amendments

### CP1

In addition to producer-consumer and delivery planning, CP1 should emit a behavioral
contract table for high-risk operations:

- accepted roles and exact rejection semantics;
- state transitions and forbidden lifecycle states;
- transaction owner and compensation sequence;
- request fields, derived fields and persistence targets;
- response shape and UI consumer;
- empty/absent/cleared/default semantics;
- required positive, negative and failure-injection scenarios.

An AC such as "cleanup on DB failure" is not implementation-ready until the failure point
is named (`flush`, `commit`, post-commit response, etc.).

### CP2

CP2 remains local, but a local step that owns a multi-system write cannot pass with only a
happy-path test. It must verify operation ordering and the step's declared failure matrix.
If the actual transaction boundary is delegated to framework/dependency code, CP2 must
follow that call path.

### CP3

CP3 must independently reconstruct `acceptance-evidence.json` from the approved source,
full diff and tests. It must not begin from an implementer assertion that all ACs are
covered. Delivery Gate PASS is an input, not a shortcut.

For every high-risk AC, CP3 must answer:

```text
What production path implements it?
What exact test could fail if the implementation were wrong?
Does that test induce the specified failure/state transition?
Does it assert the final externally visible and persisted outcome?
Did implementation or test semantics drift from the approved source?
```

### Auditor

The final Auditor should run with a fresh review context. Prior CP verdicts and agent
summaries are untrusted leads, not facts. The Auditor must sample and independently replay
the highest-risk acceptance traces, with priority given to:

1. external side effects and compensation;
2. authorization/IDOR;
3. destructive or silent data loss;
4. cross-layer field mapping;
5. tests whose expectations changed during implementation.

The Auditor need not duplicate every CP3 trace. It must challenge enough traces to detect
correlated self-confirmation and must report which traces were independently replayed.

### Curator

No further correctness responsibility should be assigned to Curator. It may identify
patterns such as repeated missing fault injection, but its output is not acceptance
evidence and cannot repair a missing semantic audit.

### CP5

Add `acceptance_evidence` as a required release input:

```text
BLOCK when acceptance-evidence is missing, stale, acceptance_ready:false,
contains unmapped criteria or contains an unapproved deviation.
```

CP5 still does not judge behavior itself. It enforces that the responsible semantic gate
produced current, structurally complete evidence and that no blocking finding contradicts
it.

## 8 Independence and correlated-review controls

More agents are not independent when they inherit the same implementation narrative,
scenario list and test interpretation. Add the following controls:

- CP3 receives the approved plan before implementation summaries;
- the final Auditor receives a clean context and reconstructs selected traces directly
  from repository state;
- verifier prompts must say that existing tests and prior PASS verdicts may be wrong;
- the implementing agent cannot author the final semantic verdict;
- repeated LLM reviews with the same scope should be collapsed rather than counted as
  additional confidence;
- review quality metrics should track escaped defects and independently reproduced
  findings, not number of PASS artifacts.

This is a role/data isolation change, not only a prompt-length change.

## 9 Additional regression fixture

In addition to the E-047 fixture, add an E-044-style semantic fixture containing:

1. an endpoint that uploads an object and flushes a DB row;
2. a framework dependency that commits after endpoint return;
3. cleanup wrapped around flush but not commit;
4. a UI that sends only a parent ID while promising derived child linkage;
5. backend error middleware returning a shape different from the UI mock;
6. eight tests where the count is correct but two required scenarios are absent;
7. a test that changes an approved `403` expectation to `401`.

Expected result:

```text
Delivery Gate: pass
CP2 happy-path/local review: may pass
CP3 acceptance evidence: fail
Auditor independent sample: blocking High findings
CP5: release_ready false
```

This fixture proves that the new process catches semantically incorrect delivery even
when all mechanical delivery checks are green.

## 10 Final second-opinion recommendation

Do not remove all CPs, and do not expand all of them into full audits. Preserve three
distinct layers:

1. **Deterministic Delivery Gate** - executable repository health.
2. **Curated completeness/traceability** - every approved criterion has identifiable
   implementation and evidence; Curator itself remains non-authoritative.
3. **One independent adversarial semantic audit** - cross-layer traces, test challenge and
   fault injection for risk-triggered behavior.

After those layers are enforced, remove or narrow redundant LLM reviews that merely
restate green commands or count artifacts. Fewer controls with distinct failure classes
provide stronger assurance than multiple reviewers sharing the same assumptions.

## 11 P045 plan-review addendum: plan executability gaps

**Date:** 2026-06-21

**Incident basis:** WAN P045 manual contract-group wizard, reviewed before EPIC generation.

This addendum records only failure classes not already covered above or in the companion
document. The existing proposal already covers transaction-owner tracing, request-to-storage
field lineage, absent/cleared/inherited semantics, idempotency as a risk trigger, dependency
and runtime consistency, and acceptance-scenario identity. Those requirements remain valid
and are not repeated here.

### 11.1 Newly observed escaped classes

| Escaped plan defect | Why the current CP1 shape could still pass it | Required new control |
|---|---|---|
| Step 3 consumed Steps 5-6 while Step 5 depended on Step 3; Steps 8 and 9 also depended on each other | the review described the graph as acyclic without constructing or validating it | machine-checkable directed step graph plus topological-sort stop rule |
| One field named `ordinal` meant request-array position, persistent person-scoped OM ordinal and RHF storage slot | symbol names matched locally, but their identity domains and stability rules were never compared | identifier-domain and reference-integrity table |
| The plan said to reuse `AddDeliveryPointModal` logic, but the component immediately persisted data and reset commodity to EAN | existence/import grounding treated a component as reusable without auditing its side effects and initialization assumptions | reuse-compatibility contract for every reused service/component |
| The plan proposed ORM constructor fields and helper behavior that did not exist or belonged to a different model | file and symbol existence checks did not validate every planned call signature and field owner | planned-call/model-field feasibility matrix |
| An unversioned install of `react-window` resolved to v2 while the plan specified the v1 `FixedSizeList` API and a deprecated external type package | runtime consistency was planned for delivery, but the plan-time API assumption was not resolved against the package version to be installed | exact dependency-version/export grounding before CP1 PASS |
| Redis was declared fail-open while success criteria promised duplicate-proof retries; `pending`, committed and failed states had no complete replay contract | idempotency was recognized as high-risk, but no state-machine proof was mandatory | idempotency state matrix with failure semantics and payload identity |

### 11.2 CP1 plan-graph validation

CP1 MUST construct a directed graph from every explicit and implicit dependency statement,
including `Depends on`, `Blocks`, "integrates Step N", future-file imports and acceptance
steps that require an earlier artifact. It MUST then:

1. reject every cycle;
2. emit one valid topological order;
3. verify that each mergeable EPIC contains complete producers for everything it consumes;
4. reject a step that claims to integrate an artifact produced only by a later EPIC;
5. treat a prose claim such as "DAG is acyclic" as untrusted until the graph is derived.

Required output:

```yaml
plan_graph:
  edges:
    - {from: 1, to: 2, reason: "schema consumed by service"}
  topological_order: [1, 2, 5, 6, 3, 4]
  cycles: []
  epic_boundary_violations: []
```

Any non-empty `cycles` or `epic_boundary_violations` is a CP1 stop-rule blocker.

### 11.3 Identifier-domain and reference-integrity review

For every identifier used across request, UI state, persistence or document targeting, CP1
MUST record:

- semantic domain (array position, stable client reference, database primary key, display
  ordinal, person-scoped ordinal, temporary UI slot);
- uniqueness and stability scope;
- whether reordering, filtering, insertion or deletion changes it;
- producer and all consumers;
- conversion rules between domains;
- negative cases for stale, foreign and ambiguous references.

Reusing one field name for incompatible domains is a blocker unless the plan defines an
explicit conversion and tests reorder/filter/add/remove cases. Positional references MUST
NOT target independently reorderable entities without a stable reference contract.

### 11.4 Planned-call and model-field feasibility matrix

Codebase grounding MUST go beyond proving that a file or symbol exists. For every proposed
production call or ORM construction, CP1 MUST verify against current code:

- exact callable signature, required arguments and return type;
- transaction preconditions and side effects (`flush`, `commit`, network or persistence);
- every constructor/input field exists on the named model/schema;
- each field's real owner and type;
- conversion rules for UI values, dates, numeric folds, nullable values and registry IDs;
- required companion behavior currently performed by the path being replaced.

Required output:

```yaml
planned_calls:
  - call: "create_contract_group(db, person_id, point_type, scan_batch_id, members)"
    source: "wan/services/contract_group_service.py:12"
    planned_step: 2
    signature_matches: true
    transaction_preconditions_verified: true
model_field_mappings:
  - input: "delivery_points[].tzd"
    target: "delivery_points.tzd"
    target_exists: true
    conversion: "ISO date -> date"
unresolved_field_mappings: []
```

An absent target field, unresolved owner, wrong callable signature or omitted conversion is
a CP1 blocker, not an implementation detail to discover during the run.

### 11.5 Reuse-compatibility contract

Whenever a plan says `reuse`, `wrap`, `extract logic from` or `use existing component`, CP1
MUST inspect the reused implementation and record:

- whether it is presentational, stateful or persistence-owning;
- network, DB, storage and navigation side effects;
- internal commits or transaction ownership;
- default values and reset behavior;
- controlled/uncontrolled form semantics and remount behavior;
- authorization and parent-ownership assumptions;
- which behavior is reused unchanged, which is extracted and which is prohibited.

Importability is not reuse compatibility. A component that immediately POSTs data cannot be
used as a local aggregate draft without an explicit extraction/refactor step and a regression
test preserving its original standalone behavior.

### 11.6 New-dependency API grounding at plan time

If a plan adds a dependency and names a concrete API, CP1 MUST resolve the exact version that
the declared install command and lock policy will select. It MUST verify:

- the named runtime exports exist in that version;
- the import path and API shape match the planned code;
- whether types are bundled or require a separate package;
- framework/runtime peer compatibility;
- whether the version is pinned or intentionally ranged.

An unversioned install instruction plus a version-specific code sample is unverifiable and
cannot PASS CP1. Deprecated stub type packages and APIs removed from the resolved major must
be reported before EPIC generation.

### 11.7 Idempotency state-machine completeness

The existing high-risk idempotency trigger is extended with a mandatory state matrix. A plan
that promises at-most-once creation MUST define behavior for:

| State/failure | Required decision |
|---|---|
| first request owns key | payload fingerprint, actor/tenant scope and lease duration |
| concurrent duplicate while pending | distinct in-progress response; never treated as completed success |
| replay after committed success | stable response/result identity |
| same key with different payload | explicit conflict; never replay unrelated result |
| failure before DB commit | key release/retry behavior and side-effect compensation |
| process loss after DB commit but before result publication | recovery/reconciliation behavior |
| idempotency store unavailable | fail-open or fail-closed must match the advertised guarantee |
| lease/TTL expiry | proof that expiry cannot create a duplicate accepted operation |

If `fail-open` can violate a stated duplicate-proof success criterion, the plan is internally
contradictory and CP1 MUST fail it. Frontend button disabling is not server idempotency proof.

### 11.8 Regression fixture

Add a P045-style plan fixture containing all of the following while keeping files and symbols
plausible:

1. a two-node step dependency cycle hidden across `Depends on` and prose `integrates` text;
2. one identifier used as array index, persistent ordinal and UI slot;
3. an ORM constructor field that belongs to another model;
4. a reused component that performs an immediate POST and resets a locked domain value;
5. an unversioned dependency install with a code sample from the previous major API;
6. fail-open idempotency paired with an at-most-once success criterion.

Expected result:

```text
CP1 structure/completeness: pass
CP1 plan graph: fail
CP1 identifier/reuse/call feasibility: fail
CP1 dependency API grounding: fail
CP1 idempotency state matrix: fail
EPIC generation: blocked
```

This fixture is important because every named file may exist and every section may be
complete while the plan is still impossible to implement correctly without redesign during
the run.
