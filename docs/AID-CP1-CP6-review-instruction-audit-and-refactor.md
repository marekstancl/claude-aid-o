# AID Review System Refactor: CP1-CP6, Auditor, Curator and Delivery Gate

**Status:** implementation proposal

**Date:** 2026-06-20; revalidated 2026-06-21 after E-047-4_7 and E-047-5_7

**Scope:** `plugins/aid-orchestrator` review checkpoints, DONE review, release decision and evidence contracts

**Primary incidents:** E-047-1_7 (`@aid/contract` foundation), its failed remediation rechecks, E-047-4_7 (self-consistent synthetic tests versus real data) and E-047-5_7 (unmounted frontend delivery, WS wire drift and false release closure)

## 1. Executive decision

The current review system is not useless. It catches local acceptance-criterion drift, common code-quality defects, security risks, malformed evidence and unsafe auto-fixes. Its central weakness is different: it can declare an EPIC complete without proving that the delivered repository is buildable, internally compatible and usable by its next consumer.

The target change is therefore **not** to remove every checkpoint and **not** to give every agent a larger generic prompt. The target is to:

1. keep each checkpoint narrow and give it one explicit failure class;
2. add a deterministic, blocking **Delivery Gate** for executable product evidence;
3. expand CP1 and CP3 to cover cross-step and producer-to-consumer contracts;
4. make Auditor outcome-oriented and give blocking findings precedence over scores;
5. keep Curator as a proposal/learning role, remove any merge-approval semantics, and run it after Auditor;
6. turn CP5 from a boolean reader into a release-policy decision over all required evidence;
7. make CP6 use the same delivery-readiness rules as CP3 for production changes;
8. enforce the new contracts structurally in the FSM and test them with negative fixtures.
9. derive a mandatory review profile from the changed delivery surfaces instead of using one generic checklist for every EPIC;
10. require one to three integration reviews at meaningful assembly points, so a large EPIC is challenged before all steps are complete;
11. prove production reachability and runtime boundary compatibility, not merely the existence and unit-test quality of isolated modules;
12. promote acceptance-evidence, independent-oracle and falsifiability rules from the second-opinion document into the blocking release contract.

### 1.1 Final disposition by component

| Component | Decision | Target purpose |
|---|---|---|
| CP1 | retain and substantially expand | plan consistency, feasibility, producer-consumer ordering and planned delivery evidence |
| CP2 | retain, keep narrow | local step correctness and meaningful step-level tests |
| CP3 | substantially redesign | semantic integration review over the full EPIC and Delivery Gate evidence |
| CP4 | retain, narrow explicitly | validate only applied Auditor/Curator fixes, then trigger affected gate re-runs |
| CP5 | replace current boolean-only behavior | deterministic release-policy aggregation and blocking decision |
| CP6 | align with CP3/Delivery Gate | fast-mode and `/aid-do` delivery readiness; blocking for production/high-risk changes |
| Auditor | substantially redesign | independent outcome and integration audit, with veto independent of score |
| Curator | retain with sequencing and authority changes | deduplication, proposals, backlog and lessons; never merge approval |
| Security verifier | dispatch conditionally except where policy requires it | security review only where the diff exposes relevant attack surface |
| Existing project gates | retain | project-specific policy checks; feed their results into Delivery Gate/CP5 |

## 2. Why the current system passed E-047-1_7

E-047-1_7 is a useful incident because no single agent fabricated an obviously false result. Most controls followed their local contract, while the combined system missed the delivered outcome.

### 2.1 Defects present at DONE review

1. `EpicSpec` shipped as an empty interface and `EpicStep`/`AcceptanceCriterion` were not exported, although the next P047 phase explicitly imports them from `@aid/contract`.
2. `FileChangeEvent` omitted `projectId`/`runRef` and retained an event vocabulary incompatible with later P047 watcher and WebSocket steps.
3. Root `npm run build` failed because `multer` was removed from the server manifest while the existing `voice.ts` still imported it.
4. Root `npm run typecheck` failed on multiple GUI dependencies removed before their consumers were replaced.
5. `npm ls --depth=0 --workspaces` failed because the lock/install tree resolved `@types/express@5` against a `^4` manifest.
6. The run was marked `DONE` while task metadata remained active, FSM step rows remained pending, `final_report.md` was absent and plan-diff had been skipped.

### 2.2 Why each control missed or downgraded them

| Control | What it actually proved | Gap exposed by E-047 |
|---|---|---|
| CP2 | each step matched its local AC | the AC itself encoded the stale/empty contract; CP2 was not asked to challenge cross-step correctness |
| CP3 code review | ten selected invariants matched the full diff | it did not run root build/typecheck, compile consumers or inspect the following plan phase |
| CP3 security | no new security sink in the type package | it saw legacy server code but treated it as out of scope despite changed manifests |
| Project gates | plugin Bats and shell pipeline passed | they did not build or test the Cockpit workspaces; plan-diff was skipped |
| Auditor | code/process scoring and report completeness | it found empty `EpicSpec` but classified it non-blocking without proving downstream impact |
| Curator | simplification and improvement proposals | it found empty `EpicSpec` but deferred it as requiring clarification; correctness is not its role |
| CP4 | applied Curator changes were safe | by design it reviewed only two small post-audit edits, not the full delivery |
| CP5 | `blocking_findings:false` existed | it trusted a single field and did not aggregate failed/missing delivery evidence |
| CP6 | not applicable | CP6 belongs to `/aid-do`; no CP6 evidence existed for this `/aid-run` |

### 2.3 Root cause

The system is optimized for **artifact compliance** and **local AC verification**. It lacks a blocking layer that proves **delivery readiness**. Multiple independent agents still share the same flawed plan premise, so adding more reviewers with the same context creates correlated confidence rather than independent assurance.

### 2.4 Additional evidence from the remediation rechecks

The two remediation rounds exposed failure modes that the original incident alone did not make explicit:

1. A typecheck can return exit 0 while checking only a declaration shim. E-047 temporarily changed the GUI `tsconfig` to include only `vite-env.d.ts`; CP3 then described all three workspaces as type-safe although the application sources had 27 errors.
2. A checklist recheck can confirm requested symbols while missing the authoritative contract. The event topic review checked only a selected positive list, so it missed a required `compliance` topic, retained obsolete topics and did not compare the full ordered vocabulary to the locked specification.
3. A dependency tree can be locally consistent but unreproducible under the declared runtime. Only a clean install under the target Node version exposed optional native-package and engine behavior.
4. Fixing a version mismatch by changing a runtime major can create a larger behavioral regression. Aligning Express types by upgrading Express 4 to Express 5 made the server fail during route registration because wildcard syntax changed.
5. Source-only dependency scans are insufficient. Vite `manualChunks` referenced absent Radix packages even though no application source imported them, so typecheck passed and production build failed.
6. Passing leaf suites does not imply a passing root test command. E-047 reached 1009 passing tests, but the workspace command still exited 1 because the server package discovered zero tests.
7. Compile/build evidence does not prove the process starts. A direct server startup smoke immediately exposed the Express route failure.
8. A syntactically valid path check can remain exploitable. Prefix comparison without a trailing path separator accepted an escaped sibling path such as `evidence-secret`; route/filesystem changes therefore require adversarial fixtures, not visual inspection alone.

These are not arguments for another generic reviewer. They require deterministic coverage, environment and runtime checks plus explicit authority comparison.

### 2.5 What E-047-4_7 and E-047-5_7 added

The later Cockpit phases proved that even the original version of this proposal needed another expansion:

| Escaped defect | Why the previous proposal could still miss it | Added control |
|---|---|---|
| analytics dropped real plans while synthetic integration fixtures passed | build/test/consumer compile proved internal consistency, not agreement with reality | `data_reporting` profile, DG-17 independent oracle and no-drop negative control |
| WS and polling hooks existed and unit tests passed but the application shell never mounted them | public symbols and leaf tests existed; no production entry-point trace was mandatory | IR-1 wiring review and DG-13 production reachability |
| server emitted event payload under `data`, GUI read fields from the top level | server and GUI had separate local wire types and separate green suites | DG-14 real provider output through real consumer |
| table links used `/plan/`, router registered `/plans/` | substring test proved the stem was present but never resolved the link | DG-15 producer-to-router conformance |
| fallback existed only as an isolated hook | a fake timer test proved hook logic but never forced failure through the mounted app | DG-16 mounted failure/fallback/recovery probe |
| API outage became "Projekt nenalezen" | broad catch was locally graceful but semantically dishonest | CP3 state-semantics lens: error/offline/empty/not-found remain distinct |
| release completed with pending child rows, active task counters and `compliance.overall:fail` | presence and advisory severity overrode contradictory aggregate state | strengthened DG-07 plus fail-closed CP5 aggregation |

The common failure class is **isolated correctness without assembled delivery**. Test quantity did not help because the missing tests were boundary and reachability tests. This is why the target process uses surface-specific lenses and early integration cuts, not a larger undifferentiated checklist.

## 3. Design principles for the replacement

### 3.1 Separate deterministic evidence from LLM judgment

- Build, typecheck, test, dependency consistency and artifact freshness are deterministic checks. A script must execute them and record exit codes.
- Architecture compatibility, behavioral completeness and severity classification require reviewer judgment.
- An LLM must not be allowed to convert a failed deterministic check into PASS through prose or an aggregate score.

### 3.2 Every control owns a distinct failure class

| Layer | Owned failure class |
|---|---|
| CP1 | internally inconsistent or non-verifiable plan |
| CP2 | incorrect implementation of one step |
| Delivery Gate | repository cannot be installed, built, checked or tested as declared |
| CP3 | integrated diff is semantically incompatible despite mechanical checks |
| Existing GATES | project-specific quality/policy failure |
| Auditor | delivered outcome, broader health or evidence contradicts the PASS claim |
| Curator | improvements, duplication, standards lessons and backlog hygiene |
| CP4 | post-review auto-fix introduced a regression or exceeded proposal scope |
| CP5 | release policy says evidence is insufficient or a blocker remains |
| CP6 | fast-mode change lacks scaled delivery evidence |

### 3.3 Blockers are not scores

Scores remain useful for trend reporting. They must not decide release readiness.

The following always block regardless of score:

- a required Delivery Gate check is `fail`;
- a required check is `unverifiable` without an approved waiver;
- required evidence is missing, stale or belongs to another HEAD SHA;
- Auditor reports an unresolved Critical or High finding;
- public-contract compatibility is broken;
- a security reviewer reports an unresolved Critical or High finding;
- CP4 fails after an applied review fix;
- state/evidence inconsistency makes the result unverifiable.

### 3.4 Evidence must be bound to the reviewed revision

Every review and gate artifact must carry:

```yaml
epic_id: E-...
run_id: R-...
base_commit: <sha>
head_commit: <sha>
generated_at: <UTC ISO-8601>
```

An artifact whose `head_commit` differs from current HEAD is stale and cannot satisfy a blocking precondition.

### 3.5 A green command must prove the intended surface

Exit code 0 is necessary but not sufficient. Delivery evidence must also record what the command actually covered.

- Typecheck evidence records included production files or a coverage count; compiling only shims/generated declarations is `unverifiable`.
- Test evidence records discovered suites/tests per workspace; zero tests are not a pass unless policy explicitly allows them.
- Build evidence comes from a clean dependency graph when manifests, lockfiles, runtime versions or native/optional packages changed.
- Runtime packages must pass at least one startup/import smoke after framework, router, module-format or bootstrap changes.
- A wrapper must propagate the real child exit code. Output containing an inner lifecycle/build failure cannot be reported as PASS merely because the outer launcher returned 0.
- Commands run under the declared runtime/toolchain, not whichever version happens to be active in the review shell.

### 3.6 Normative companion requirements

The following parts of `AID-CP1-CP6-review-instruction-audit-second-opinion.md` are normative amendments to this proposal, not optional commentary:

- sections 4-8: acceptance-evidence contract, test-evidence audit, behavior traces, fault injection and independent fresh-context review;
- section 9: E-044 semantic regression fixture;
- sections 11.2-11.7: plan graph, identifier domains, planned-call/model feasibility, reuse compatibility, dependency API grounding and idempotency state matrix.

Implementation MUST merge those rules into the actual CP1/CP2/CP3/Auditor/CP5 instruction files and schemas. Shipping only a link to the companion document is insufficient because runtime agents may not receive documentation context. Where the documents overlap, this revalidated main document controls sequencing, adaptive profiles and release enforcement; the companion controls semantic trace depth.

## 4. Target execution order

### 4.1 Full `/aid-run`

```text
PLAN
  1. Write plan
  2. CP1 plan integrity review
  3. CP1-deep lenses when high risk
  4. Resolve all accepted blockers
  5. Generate EPICs only after CP1 pass

EXECUTE (per step)
  6. Implement step
  7. Run step-local deterministic checks declared in the step
  8. CP2 local review
  9. Fix/re-run CP2 when required

INTEGRATION CANDIDATE (after final step)
 10. Delivery Gate D0: full candidate check
 11. CP3 code/integration review consumes full diff + D0 report
 12. CP3 security review only when attack-surface rules require it
 13. Fix loop: apply fix -> re-run affected D0 checks -> re-run CP3

GATES
 14. Existing project policy gates
 15. Bind GATES results into the delivery evidence set

DONE / REVIEW
 16. Generate final report from actual evidence
 17. Auditor runs independently and consumes D0 + project gates
 18. Curator runs after Auditor and consumes its structured findings
 19. Apply approved auto-fixes
 20. CP4 reviews only the applied-fix diff
 21. Delivery Gate D1: re-run impacted checks against final HEAD
 22. CP5 release-policy aggregation
 23. PM receives MERGE only when CP5 says release_ready:true
```

### 4.2 `/aid-do` and fast mode

```text
IMPLEMENT
  1. Apply task
  2. Classify risk and touched delivery surfaces
  3. Delivery Gate F0 using the smallest valid profile
  4. CP6 review over full task diff + F0 report
  5. Re-run affected checks after fixes
  6. Production/high-risk change: blocking release decision
  7. Docs-only/trivial change: advisory result allowed with explicit skip reasons
```

CP6 must no longer be described globally as “advisory only”. It is advisory only for non-production, low-risk changes for which all required deterministic checks pass or are not applicable.

### 4.3 Auditor and Curator sequencing

Auditor and Curator must not remain fully parallel if Curator is expected to process current-run audit findings. The default becomes:

```text
Auditor completes -> audit-report written -> Curator starts -> Curator consumes audit findings
```

If latency requires parallel execution, add a mandatory Curator phase 2 after Auditor completion. The release process must not use the phase-1 Curator report as final.

### 4.4 Adaptive review profiles and integration cadence

A fixed prompt is inefficient for a documentation change and insufficient for a cross-package realtime UI. Before implementation, `aid-prefilter` MUST derive a `review-profile.json` from the approved plan, dependency graph and changed paths. The profile selects review lenses and deterministic probes; it does not merely label the EPIC `low|medium|high`.

Required surface classes:

| Surface | Trigger examples | Mandatory additional proof |
|---|---|---|
| `docs_only` | Markdown/text only, no executable config | link/authority checks; explicit valid skips for executable probes |
| `local_logic` | private function/module with no external boundary | focused positive/negative unit tests and caller trace |
| `public_contract` | exported type/schema/API/CLI/package entry | producer-consumer compile plus full shape/vocabulary comparison |
| `frontend_shell_routing` | app shell, router, navigation, providers, hooks | production mount trace, generated-link-to-router conformance and browser smoke |
| `realtime_async` | WS/SSE/events/watchers/queues/retries | real provider-consumer frames, reconnect, malformed-frame and fallback/recovery probes |
| `api_cross_layer` | route plus client/serializer/middleware | real server response consumed by the real client parser; mocks cannot define both sides |
| `data_reporting` | scanner, aggregation, migration, analytics | independent oracle/no-drop probe, partial/unknown semantics and representative real-data fixture |
| `persistence_side_effect` | DB/files/object store/external call | transaction trace, failure injection, compensation, idempotency and read-back proof |
| `security_boundary` | auth, path, upload, parser, command, secret | adversarial security lens and abuse fixtures |
| `runtime_infra` | manifests, runtime, Docker, bootstrap, build config | clean runtime/install, startup and representative route/import smoke |
| `process_release` | FSM, gate, evidence, release metadata | state reconciliation and negative transition fixtures |

Rules:

1. Mixed changes receive the union of all matched lenses. Unknown production surfaces default to `unverifiable`, not `docs_only`.
2. The detector owns applicability. A reviewer may add a lens but cannot remove a detected lens without a PM waiver.
3. Each lens defines required artifacts, probes and stop conditions. Generic prose such as "integration reviewed" is invalid evidence.
4. Review effort scales with topology and blast radius, not lines changed or test count.
5. The profile and every review artifact are bound to `base_commit`, `head_commit` and the reviewed step range.

Integration-review cadence:

| Profile | Required integration reviews | Timing |
|---|---:|---|
| low, single-surface, no public/runtime boundary | 1 | final CP3 |
| medium or one producer-consumer boundary | 2 | first runnable vertical slice, then final CP3 |
| high, mixed-surface, multi-package, realtime, persistence or release-process | 3 | first producer-consumer slice, feature-complete candidate, final release candidate |

These are not three repetitions of the same audit:

- **IR-1 Wiring review:** prove that producers, consumers, entry points, routes, providers and background hooks are connected in production code.
- **IR-2 Behavior review:** execute representative happy, failure, fallback and recovery paths against real boundaries or contract fixtures.
- **IR-3 Final CP3:** review the complete diff, current Delivery Gate and unresolved findings against the accepted outcome.

IR-1/IR-2 are delta reviews. They reuse prior current evidence, inspect the new range and re-open affected prior traces. A Critical/High finding stops further feature work until fixed and rechecked. An integration review performed before its required assembly point is `not_applicable_yet`, not a consumed PASS.

The target is early defect discovery with at most three semantic integration passes for a large EPIC. CP2 remains step-local and may still run per step; it is not counted as one of these independent integration passes.

## 5. Delivery Gate specification

### 5.1 Purpose

Delivery Gate proves that the revision under review can be consumed according to the repository's declared build and test contracts. It is deterministic and blocking. It does not score style, architecture or product value.

### 5.2 Proposed implementation files

| File | Purpose |
|---|---|
| `plugins/aid-orchestrator/scripts/aid-delivery-gate.sh` | profile resolution, execution, artifact generation |
| `plugins/aid-orchestrator/defaults/policies/delivery-gate.yaml` | defaults and ecosystem command profiles |
| `plugins/aid-orchestrator/defaults/templates/delivery-gate-template.json` | canonical output schema example |
| `plugins/aid-orchestrator/scripts/tests/test-delivery-gate.sh` | unit/integration fixtures |
| `plugins/aid-orchestrator/scripts/lib/aid-delivery-profile.sh` | safe profile discovery and command selection, if script size warrants extraction |
| `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` | enforcement-home registration |

Project override:

```text
.aid-o/config/policies/delivery-gate.yaml
```

### 5.3 Profile resolution precedence

1. explicit project configuration;
2. explicit commands declared by the plan/EPIC;
3. repository ecosystem inference;
4. no valid command found -> `unverifiable`, never implicit PASS.

Example configuration:

```yaml
delivery_gate:
  enabled: true
  block_on_unverifiable: true
  isolated_install_on_manifest_change: true
  output_preview_lines: 80

  profiles:
    root:
      working_directory: "."
      checks:
        - id: dependency_consistency
          command: ["npm", "ls", "--depth=0", "--workspaces"]
          required_when: "package_manifest_changed"
        - id: build
          command: ["npm", "run", "build", "--if-present"]
          required_when: "production_or_manifest_changed"
        - id: typecheck
          command: ["npm", "run", "typecheck", "--if-present"]
          required_when: "typed_source_changed"
        - id: test
          command: ["npm", "test", "--if-present"]
          required_when: "production_or_test_changed"

    contract_consumer:
      checks:
        - id: public_contract_consumer_compile
          resolver: "changed_public_contract_consumers"
          required_when: "public_contract_changed"

  import_removal_scan:
    enabled: true
    required_when: "dependency_removed"
```

Commands should be represented as argv arrays, not shell strings, to avoid accidental shell expansion and quoting drift.

### 5.4 Required checks

#### DG-01 Dependency consistency

Trigger when any supported dependency manifest or lockfile changes.

Minimum checks:

- package manager reports a consistent dependency tree;
- manifest and lockfile agree;
- changed workspace links resolve locally where declared;
- unsupported engine/version combinations are reported;
- removed dependencies have no remaining production imports.

For npm workspaces, the default local check is:

```bash
npm ls --depth=0 --workspaces
```

When a manifest/lockfile changes and project policy requires clean-install proof, execute installation in a disposable worktree or CI job. Do not delete or replace the developer's current `node_modules` from the gate script.

#### DG-02 Build

Run the highest-level declared build command that covers all changed production packages. A package-only build is insufficient when root scripts claim workspace integration.

#### DG-03 Typecheck/static analysis

Run root typecheck/static checks plus package-specific checks not included by root.

#### DG-04 Tests

Run tests relevant to changed packages and the root integration suite. Record zero-test execution separately; “command exit 0 with zero discovered tests” is `unverifiable` unless explicitly permitted.

#### DG-05 Public-contract consumer compilation

Trigger when a changed file exports a public/shared type, schema, event, route contract, CLI contract or package entry point.

The resolver must:

1. enumerate exported names changed by the diff where practical;
2. search repository consumers/imports;
3. compile affected consumers or a generated smoke fixture;
4. inspect the next same-plan EPIC for explicitly declared imports;
5. fail when a required export is missing or an existing consumer no longer compiles.

This check would have caught missing `EpicStep` and `AcceptanceCriterion` in E-047-1_7.

#### DG-06 Removed dependency/import consistency

For each dependency removed from a manifest:

1. search production source, scripts, configs and tests for imports/requires/plugin references;
2. classify references as production, test-only, documentation or generated;
3. fail if a production reference remains;
4. report an exact file:line list.

This check would have caught `multer` removal while `voice.ts` still imported it.

#### DG-07 Artifact and state consistency

Validate:

- required final report exists;
- FSM state, task status and run counters agree;
- every FSM step row is completed before the parent state can become `DONE`;
- all required step outputs exist;
- plan-diff is either present and evaluated or explicitly inapplicable under policy;
- gate reports bind to the current HEAD;
- a skipped required check is not treated as pass;
- an aggregate artifact with `overall:fail` cannot be consumed as release-ready merely because its individual failure was labelled advisory; policy must emit `warn`/`skip` for a genuinely non-blocking result.

#### DG-08 Declared runtime and environment consistency

Trigger when runtime pins, engines, containers, CI, dependency manifests or build tooling change.

Validate:

- one explicit runtime baseline is selected (for example the current supported LTS, not an ambiguous `current` label);
- version-manager files, root/package `engines`, CI images, Docker build/runtime images, plan constraints and acceptance criteria agree;
- clean install, build, typecheck and tests run under that baseline;
- broad engine ranges do not silently admit unsupported non-LTS majors unless policy permits them;
- runtime upgrades are treated as migrations with compatibility checks, not as lockfile cleanup.

Any conflicting runtime matrix is `fail` when it affects reproducibility and otherwise `unverifiable`; it is never silently normalized by the reviewer.

#### DG-09 Static-check coverage integrity

For each typecheck/lint/static command, record the production files or configured roots it covered. At minimum:

- resolve `include`/`exclude` and project references;
- compare covered production files with changed and package-owned typed sources;
- reject a configuration that covers only declaration shims, generated files or an empty set while production typed sources exist;
- when practical, retain `tsc --listFiles` or the tool equivalent as evidence.

A static command with exit 0 but materially incomplete coverage is `unverifiable`, not `pass`.

#### DG-10 Runtime startup and route smoke

Trigger when a server bootstrap, framework/router major, route table, module format, runtime dependency or container entry point changes.

Required proof:

1. start/import the built production entry point under the declared runtime;
2. assert it remains alive through initialization or exits only through the controlled test harness;
3. hit the health endpoint when one exists;
4. register representative static, parameterized, wildcard and fallback routes;
5. terminate the process cleanly and retain stderr.

Compile success cannot substitute for startup proof. A route-registration exception is a blocking delivery failure.

#### DG-11 Build-configuration dependency resolution

Dependency scans must include source and executable configuration surfaces: bundler entries/manual chunks, test setup, plugins, loaders, code-generation configs, CSS processors, service workers and runtime preload hooks.

Every explicit module id in a build/runtime configuration must either resolve from the owning package or be classified as optional behind an executable condition. This check would have caught the absent `@radix-ui/*` modules referenced only by Vite `manualChunks`.

#### DG-12 Authority and acceptance consistency

Build an authority matrix for changed behavior:

```text
user decision -> locked specification/ADR -> plan -> EPIC AC -> implementation -> tests
```

The gate/reviewer must report contradictory exact values, vocabularies, versions and behavior. A later explicit user decision may supersede an older plan constraint, but the plan, generated EPICs and tests must be updated before release. Satisfying stale AC text does not prove correctness; satisfying implementation intent while leaving contradictory ACs also cannot reach `release_ready:true`.

For closed public vocabularies or schemas, tests compare the complete set/shape against the authoritative source. Selected positive assertions are insufficient.

#### DG-13 Production wiring and reachability

Trigger for frontend shells, dependency-injection/provider registration, routers, hooks, workers, schedulers, plugins, handlers and newly exported runtime features.

Validate a production entry-point trace:

```text
application entry -> mount/register -> feature owner -> required side effect or visible result
```

Creating and unit-testing a module is insufficient when no production entry point imports or invokes it. Every required feature must be classified as `reachable`, `intentionally_deferred` with authoritative scope evidence, or `unreachable`. A required `unreachable` feature is a failure. This check must distinguish a future-phase leaf component from a current-phase shell responsibility.

#### DG-14 Runtime provider-consumer contract conformance

Trigger for HTTP clients, WebSocket/SSE frames, queues, events, serializers, middleware error envelopes and cross-language boundaries.

Required proof:

1. capture or construct a frame/response through the real provider implementation;
2. feed that exact payload to the real consumer parser/handler;
3. compare required field names, nesting, nullability, vocabulary and ordering against one authoritative contract;
4. exercise at least one malformed/unknown payload where the consumer promises graceful degradation;
5. reject tests where provider and consumer mocks independently encode the same unverified assumption.

Compile-time compatibility does not satisfy this check when wire types are duplicated locally or erased to `unknown`. A server frame `{data:{projectId,...}}` and a client expecting top-level `projectId` is a blocking failure even when both packages typecheck and pass their own tests.

#### DG-15 Navigation and dispatch conformance

Trigger for routers, generated links, command dispatch tables, topic maps, plugin registries and event-to-handler maps.

Enumerate producers and consumers of identifiers/paths and verify every generated value resolves to exactly one registered destination. For frontend routing, render/calculate real links and resolve them through the production router; substring assertions are insufficient. Also detect registered destinations with no intended producer and producers targeting no destination.

#### DG-16 Failure, fallback and recovery behavior

Trigger whenever the plan promises polling fallback, offline behavior, retry, reconnect, failover, cache fallback, empty/error distinction or degraded mode.

The probe MUST force the primary path to fail and prove:

- fallback starts within the declared bound;
- user-visible state accurately identifies degradation;
- required data continues to refresh or is honestly marked unavailable;
- duplicate timers/workers/subscriptions do not accumulate;
- recovery stops fallback and restores the primary path.

A unit-tested fallback hook that is not mounted in production fails DG-13 before this behavior can pass DG-16.

#### DG-17 Independent oracle and data-completeness conformance

Trigger for scanners, analytics, migrations, reports, search/indexing and fleet/cross-project aggregation.

At least one blocking probe must compare production output with an independent source of truth: a separately implemented diagnostic, immutable representative snapshot, direct authoritative query or manually reviewed fixture. Comparing two outputs produced by the same resolver is self-consistency, not correctness. Required negative controls include no-drop/cardinality, known ambiguous identity and missing/partial-data cases.

#### DG-18 Acceptance-evidence structural integrity

Trigger for every production EPIC; depth scales by review profile.

Require current `acceptance-evidence.json` as specified by `AID-CP1-CP6-review-instruction-audit-second-opinion.md` sections 4-8. The structural gate verifies that every authoritative AC has a stable ID, production trace, evidence identity, status and approved deviations. Behavioral truth remains CP3/Auditor responsibility, but missing criteria, changed expectations, unapproved deviations or evidence bound to stale HEAD block release.

### 5.5 Output contract

Canonical path:

```text
.aid-o/work/evidence/{epic_id}/{run_id}/delivery-gate.json
```

Detailed logs:

```text
.aid-o/work/evidence/{epic_id}/{run_id}/delivery-gate/{check_id}.log
```

Proposed JSON shape:

```json
{
  "_generated_by": "aid-delivery-gate.sh@1",
  "_generated_at": "2026-06-19T15:30:00Z",
  "epic_id": "E-047-1_7",
  "run_id": "R-E047-1",
  "base_commit": "9ee518e...",
  "head_commit": "8b8733c...",
  "phase": "D0",
  "profile": "npm-workspaces",
  "runtime": {
    "name": "node",
    "declared": "24.x",
    "actual": "24.12.0",
    "source": ".nvmrc",
    "consistent": true
  },
  "checks": [
    {
      "id": "build",
      "required": true,
      "command": ["npm", "run", "build"],
      "cwd": ".",
      "status": "fail",
      "exit_code": 1,
      "duration_ms": 3241,
      "coverage": {
        "production_files_expected": 36,
        "production_files_checked": 36,
        "tests_discovered": null
      },
      "reason": null,
      "output_preview": "src/routes/voice.ts: Cannot find module 'multer'",
      "log_path": "delivery-gate/build.log"
    }
  ],
  "summary": {
    "pass": 0,
    "fail": 1,
    "skip": 0,
    "unverifiable": 0,
    "delivery_ready": false,
    "blocking_reasons": ["required check build failed"]
  }
}
```

Allowed check statuses:

```text
pass | fail | skip | unverifiable
```

Semantics:

- `pass`: command/evidence executed successfully and meaningfully;
- `fail`: executed and contradicted the requirement;
- `skip`: demonstrably not applicable, with non-empty reason;
- `unverifiable`: applicable but could not be executed or trusted.

### 5.6 Blocking algorithm

```text
if report missing or stale:
    delivery_ready = false
if any required check == fail:
    delivery_ready = false
if any required check == unverifiable and block_on_unverifiable:
    delivery_ready = false
if any required check == skip without policy-approved applicability reason:
    delivery_ready = false
otherwise:
    delivery_ready = true
```

There is no percentage threshold and no weighted override.

### 5.7 Re-run policy

- D0 runs after the last implementation step.
- A CP3 or gate-fixer change invalidates checks whose inputs intersect the changed files.
- CP4 changes always invalidate at least build/typecheck/test for affected packages.
- D1 runs after all DONE-review fixes and binds to final HEAD.
- CP5 accepts only D1, unless no files changed after D0 and the D0 HEAD exactly equals final HEAD.

## 6. Exact checkpoint instruction changes

The text below is intended as implementation-ready normative content. Wording may be adapted to existing templates, but MUST/SHALL semantics must be preserved.

### 6.1 CP1: plan integrity and delivery feasibility

**Files to modify:**

- `plugins/aid-orchestrator/commands/aid-plan.md`
- `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md`
- `plugins/aid-orchestrator/agents/verifier.md`
- CP1 lens/adjudicator instructions and gate tests

**Add to the CP1 contract:**

```markdown
#### Cross-step contract review (MANDATORY)

The reviewer MUST build a producer-consumer table for every public artifact, type,
schema, manifest, event, route, generated file and package entry point introduced or
changed by the plan.

For each contract, record:
- producer step;
- first consumer step;
- exact symbol/file/field names;
- whether the producer's acceptance criteria prove the consumer can compile/read it;
- migration ordering and temporary compatibility requirements.

Any consumer that imports or reads a contract before the producer fully defines it is
a stop-rule blocker. A placeholder interface, cast, TODO, comment-only shape or deferred
field definition is NOT a valid producer when a later step consumes concrete fields.
```

```markdown
#### Delivery evidence plan (MANDATORY)

The plan MUST declare executable commands proving the final repository is deliverable:
dependency consistency, build, typecheck/static analysis, tests and public-consumer
validation. Package-only checks are insufficient when root/workspace integration exists.

For every command state:
- working directory;
- trigger/applicability;
- expected exit status;
- whether failure blocks DONE;
- evidence artifact path.

Missing executable delivery evidence is a stop-rule blocker, not a documentation note.
```

```markdown
#### Migration atomicity check (MANDATORY)

When a step removes a dependency, route, export, file or compatibility layer, CP1 MUST
identify every existing consumer and ensure the same step removes/migrates those consumers,
or explicitly preserve compatibility until the consumer migration step completes.

The repository MUST remain buildable at every mergeable EPIC boundary unless the plan
marks the branch non-mergeable and places all breaking work in one atomic EPIC.
```

```markdown
#### Authority and runtime matrix (MANDATORY)

CP1 MUST identify the authoritative source for every closed vocabulary, public schema,
runtime/toolchain baseline and framework major changed by the plan. It MUST compare the
user decision, locked specification/ADR, plan text, generated EPIC ACs and proposed tests.

The plan MUST name one testable runtime baseline and all files that must carry it
(`.nvmrc`/tool version, engines, CI, Docker and documentation). Ambiguous terms such as
"current" are invalid unless resolved to an exact supported release line and update policy.

Any contradiction that would let two agents implement different valid-looking outcomes
is a stop-rule blocker until the authoritative documents and generated ACs agree.
```

```markdown
#### Adaptive review and assembly plan (MANDATORY)

CP1 MUST classify the plan into the section 4.4 surface profiles and declare the exact
review lenses, deterministic probes and integration assembly points that each profile
requires. The classification is the union of all changed surfaces, not one dominant label.

For medium/high plans CP1 MUST identify the earliest runnable producer-consumer vertical
slice for IR-1 and the feature-complete candidate for IR-2. "Run integration review after
the final step" is invalid when an earlier step already creates a testable boundary.

For each user-visible or runtime feature, CP1 MUST name its production owner and wiring step:
entry point/provider/router -> mount/register -> implementation -> observable behavior.
A later step that creates a hook/component without a step that mounts it is an unowned
delivery surface and blocks plan approval.
```

**CP1 output additions:**

```yaml
producer_consumer_contracts:
  - contract: "@aid/contract EpicSpec"
    producer_step: 3
    consumer_steps: [8, 9]
    producer_complete: true
    evidence: "typed members + consumer compile gate"
delivery_evidence:
  commands_planned: true
  root_build: true
  root_typecheck: true
  root_test: true
  dependency_consistency: true
migration_atomicity_blockers: []
authority_matrix:
  runtime: {decision: "Node 24 LTS", consistent: true}
  event_topics: {source: "spec section 7.3", consistent: true}
review_profile:
  surfaces: [frontend_shell_routing, realtime_async, api_cross_layer]
  required_lenses: [production_wiring, wire_contract, fallback_recovery, browser_smoke]
  integration_reviews: 3
integration_points:
  - {id: IR-1, after_step: 3, proof: "server frame reaches mounted client hook"}
  - {id: IR-2, after_step: 6, proof: "primary failure starts polling and recovery stops it"}
production_wiring_owners: []
```

CP1 adjudication must reject `verdict: pass` when any mandatory array is absent or when accepted blockers remain.

### 6.2 CP2: local step verification

**Decision:** retain scope; do not turn CP2 into another full integration audit.

**Modify CP2 instructions to add:**

```markdown
CP2 owns local step correctness. It MUST verify behavior, not merely names or literal
presence. It MUST run or inspect the step-local deterministic commands declared in the
step and report their exit status.

If the step changes a public/shared contract or dependency manifest, CP2 MUST additionally:
1. search direct repository consumers;
2. verify removed dependencies have no remaining direct production imports;
3. run the narrowest available consumer compile/test;
4. mark the step FAIL when the contract is a comment-only/empty placeholder but the plan
   declares concrete downstream use.

If the step is the declared owner of a production wiring or integration point, CP2 MUST
also prove reachability from the real entry point and execute the profile-specific narrow
probe. A unit test that imports the leaf directly cannot prove that the application mounts,
registers or dispatches to it.

CP2 does not replace Delivery Gate or CP3. A CP2 PASS means only that the step is locally
correct at its reviewed HEAD.
```

**Required CP2 output additions:**

```yaml
commands_executed:
  - command: "npm test -w @aid/contract"
    exit_code: 0
public_contract_changed: true|false
direct_consumers_checked: []
dependency_removals_checked: []
```

For ordinary internal steps, empty consumer/removal arrays are valid. For manifest/public-contract steps, omission is invalid.

### 6.3 CP3: semantic integration review

**Files to modify:**

- `agents/verifier.md`
- `skills/review-checkpoint-contracts.md`
- `skills/pipeline.md`
- verifier output template
- FSM precondition tests

**Replace the current “EXACTLY” context restriction for CP3 with:**

```markdown
CP3 receives:
- full `base_commit..HEAD` diff;
- complete EPIC AC/DoD;
- relevant Architecture Context and Implementation Detail from the source plan;
- producer-consumer table from CP1;
- detector-owned `review-profile.json` and required lens list;
- prior IR-1/IR-2 reports and unresolved finding ledger when required by the profile;
- current `acceptance-evidence.json` reconstructed from the authoritative ACs;
- next same-plan EPIC imports/contracts when present;
- current Delivery Gate D0 report and logs for failed/unverifiable checks;
- project gate configuration;
- changed public exports and dependency-manifest summary.

CP3 MUST NOT treat local AC conformance as sufficient. It decides whether the accumulated
change works as one integrated delivery and whether it leaves the next declared consumer
with a valid contract.
```

**Add mandatory CP3 checks:**

```markdown
1. Delivery Gate D0 exists, is bound to current HEAD and has `delivery_ready:true`.
   Otherwise CP3 verdict MUST be fail.
2. Root/workspace commands cover all changed production packages.
3. Every changed public contract has at least one consumer compile/test or an explicit
   proof that no consumer exists yet.
4. Every removed dependency/export/file has no remaining production consumer.
5. Producer-consumer contracts from CP1 are complete in the implementation.
6. The integrated repository does not rely on unsafe casts or placeholders to bridge
   an undeclared contract.
7. Existing project gates test the changed product surface; irrelevant green gates are
   reported as coverage gaps, not delivery proof.
8. Skipped or zero-test checks are evaluated as `skip`/`unverifiable`, never PASS.
9. Static checks cover the actual changed production sources; CP3 MUST inspect coverage
   evidence rather than trusting the command name and exit code.
10. Framework/runtime-major changes have startup and representative route/import smoke
    evidence under the declared runtime.
11. Build configuration module references resolve from the owning package.
12. Implementation, tests, EPIC ACs, plan and locked specification agree with the latest
    explicit user decision; selected-field spot checks do not replace full contract comparison.
13. Every required feature is reachable through its real production entry point; exported,
    unit-tested but unmounted/unregistered code is incomplete delivery.
14. Every runtime boundary uses one compatible provider-consumer shape proven with a real
    frame/response, especially when either side keeps local wire types or `unknown` payloads.
15. Generated links, route/topic/command producers and dispatch tables resolve through the
    production router/registry to exactly one intended consumer.
16. Every promised fallback is tested by forcing primary failure and observing fallback,
    user-visible degradation and recovery through the mounted production path.
17. Empty, missing, offline, unauthorized and not-found states remain semantically distinct;
    broad catches must not convert operational failure into a false business empty state.
18. Data/reporting output is compared with an independent oracle and includes a negative
    no-drop mutation or equivalent falsification proof.
19. Tests are audited as falsifiable claims: mocks may not define both sides of a boundary,
    substring/count assertions may not replace exact behavior, and at least one critical
    test must be shown to fail under a representative wrong implementation.
20. All profile-required IR reports exist at the declared assembly points, bind to their
    reviewed HEAD/range and have no unresolved Critical/High finding.
```

**Required CP3 output:**

```yaml
checkpoint: cp3
focus: integration-review
base_commit: "..."
head_commit: "..."
delivery_gate:
  path: "delivery-gate.json"
  head_matches: true
  delivery_ready: true
review_profile:
  required_lenses: []
  completed_lenses: []
integration_reviews:
  required: 1|2|3
  reports: []
production_reachability: []
runtime_contract_probes: []
fallback_recovery_probes: []
acceptance_evidence:
  path: "acceptance-evidence.json"
  acceptance_ready: true
contract_traces:
  - producer: "packages/aid-contract/src/view.ts:EpicSpec"
    consumers: ["packages/aid-server/src/parsers/markdown.ts"]
    result: pass
removed_surface_checks: []
coverage_gaps: []
verdict: pass|fail
```

The CP3 `code-review` focus should be renamed or aliased to `integration-review` to make its actual responsibility explicit. Security remains a separate lens when triggered.

### 6.4 CP3 security dispatch

Current unconditional dual dispatch creates low-value reviews for pure types/docs while still failing to catch integration defects.

**Proposed rule:**

Dispatch CP3 security when any of these apply:

- route/handler/auth/input-validation/security-sink patterns changed;
- dependency manifests changed and vulnerability review is required;
- filesystem/network/process execution changed;
- secret/config/auth policy changed;
- project marks security review mandatory;
- pre-filter is uncertain.

When filesystem path construction or file-serving routes change, the security review MUST
execute adversarial traversal fixtures including `..`, encoded separators, absolute paths,
symlink escapes and sibling-prefix collisions (`allowed` versus `allowed-secret`). A plain
`startsWith(base)` assertion without canonicalization and a trailing separator is blocking.

For pure type-only changes with no runtime/dependency attack surface, record a deterministic skip with reason. Dependency-manifest changes still require dependency audit/consistency checks even when the full security LLM is skipped.

### 6.5 CP4: applied-fix validation

CP4 remains valuable but its authority must be explicit.

**Replace/extend instruction with:**

```markdown
CP4 reviews ONLY the diff introduced by Auditor/Curator/gate-fixer actions after the
original audit. CP4 MUST NOT claim that it revalidated the complete EPIC.

CP4 MUST verify:
- every changed line maps to an approved proposal/finding;
- no unrelated scope was introduced;
- the fix resolves the source finding;
- no new Critical/High issue appears;
- affected Delivery Gate checks are identified for mandatory re-run.

CP4 validates the behavioral outcome of the source finding, not only the requested patch
shape. A fix that makes one selected assertion green by excluding production files, widening
a cast, changing a runtime major or narrowing the test surface is a failed fix. Runtime,
manifest, build-config and test-config edits automatically require the corresponding clean
install/build/static/test/startup checks, even when the source finding mentioned only one.

CP4 PASS is provisional until the affected D1 Delivery Gate checks pass on the same HEAD.
CP4 FAIL reverts the applied fix and records the reversion; it does not convert the
original unresolved blocker into a pass.
```

Required output additions:

```yaml
applied_fix_base_commit: "..."
applied_fix_head_commit: "..."
source_findings: ["AUD-...", "IMP-..."]
affected_delivery_checks: ["build", "typecheck", "test"]
full_epic_revalidated: false
```

### 6.6 CP5: release-policy gate

Current CP5 checks only `blocking_findings:` from Auditor. Replace it with aggregation over structured evidence.

**Proposed CP5 algorithm:**

```text
INPUTS:
  final HEAD
  Delivery Gate D1
  detector-owned review profile and all required IR reports
  acceptance-evidence.json
  project gates report
  CP3 integration verdict
  CP3 security verdict or valid skip
  Auditor structured findings
  CP4 verdict when fixes were applied
  required evidence/state consistency

BLOCK when:
  D1 missing/stale/not ready
  required adaptive lens or IR report missing/stale/failing
  acceptance evidence missing/stale/not ready, with unmapped ACs or unapproved deviations
  any required project gate fails
  CP3 fails or is stale
  required security review fails/is missing
  unresolved Auditor Critical/High exists
  CP4 fails or affected checks were not rerun
  final_report/state/task/run metadata is materially inconsistent
  FSM parent is DONE while any child step is non-complete
  any consumed aggregate artifact says fail unless policy explicitly classifies it non-blocking before execution
  any required result is unverifiable without approved waiver

PASS only when:
  all required inputs are present, current and non-blocking
```

Canonical output:

```text
.aid-o/work/evidence/{epic_id}/{run_id}/release-decision.json
```

```json
{
  "_generated_by": "aid-release-policy@1",
  "head_commit": "...",
  "release_ready": false,
  "inputs": {
    "delivery_gate": "fail",
    "review_profile": "pass",
    "integration_reviews": "fail",
    "acceptance_evidence": "pass",
    "project_gates": "pass",
    "cp3": "pass",
    "security": "skip",
    "auditor": "block",
    "cp4": "not_applicable",
    "evidence_consistency": "fail"
  },
  "blocking_reasons": [
    "required delivery check build failed",
    "unresolved High finding AUD-DELIVERY-001"
  ]
}
```

FSM must offer MERGE only when `release_ready:true` and the artifact HEAD matches current HEAD.

### 6.7 CP6: scaled delivery review for `/aid-do`

**Replace “always advisory” with:**

```markdown
CP6 uses risk-based enforcement.

Blocking CP6:
- any production source, dependency manifest, public contract, migration, route, auth,
  FSM, build config or release file changed; OR
- pre-filter/high-risk classification matched.

Advisory CP6:
- docs-only, comments-only or demonstrably trivial non-production changes;
- all applicable deterministic checks pass or are validly not applicable.

Blocking CP6 MUST consume a fast-mode Delivery Gate report bound to current HEAD.
It applies the same dependency-removal, public-contract and required-command rules as CP3,
scaled to touched packages. A failed required check cannot be downgraded to advisory.
```

## 7. Auditor instruction changes

### 7.1 Add mandatory Delivery/Integration Audit category

**File:** `plugins/aid-orchestrator/agents/auditor.md`

Add a new mandatory category, before scoring:

```markdown
### K) Delivery and Integration Audit (ALWAYS runs)

Purpose: determine whether the reviewed HEAD is a usable delivery, not merely a locally
well-formed diff.

Required inputs:
- Delivery Gate D0/D1 reports and logs;
- project gates report;
- CP3 integration report;
- full diff;
- source plan producer-consumer table;
- detector-owned review profile, required lenses and IR reports;
- acceptance-evidence artifact and the authoritative AC source;
- next same-plan EPIC when present.

Checks:
K1. Required build/typecheck/test/dependency checks ran and passed on current HEAD.
K2. Changed public contracts compile in direct and declared next-phase consumers.
K3. Removed dependencies/exports/files have no remaining production references.
K4. Root/workspace validation covers all changed packages.
K5. Skipped, zero-test and unavailable checks are represented honestly.
K6. Gate coverage is relevant to the product diff; unrelated green gates are not counted.
K7. Final evidence/state metadata is consistent enough to trust the result.
K8. Required runtime features are reachable from production entry points, not only present
    as tested leaf modules.
K9. At least one highest-risk provider-consumer, routing/dispatch or fallback trace is
    independently replayed from repository/runtime evidence rather than prior summaries.
K10. Acceptance tests can falsify the claimed behavior and do not use mocks, counts or
     substring assertions as substitutes for the authoritative scenario.
K11. Operational failure is not misreported as an empty/not-found business state.

The Auditor MAY rerun targeted commands when reports contradict repository state. It MUST
not rewrite a deterministic failure as PASS. Missing/stale required evidence is a High
finding and makes the audit blocking.

The Auditor starts from a fresh review context. Prior CP PASS verdicts and implementation
summaries are untrusted leads. For medium/high profiles it MUST independently replay at
least one trace not selected by the implementer, prioritizing production wiring, wire
contracts, fallback/recovery and real-data completeness.
```

### 7.2 Auditor blocking rules

Add normative text:

```markdown
`blocking_findings` is derived, not freely chosen.

Set `blocking_findings: true` when any unresolved finding is Critical or High, or when a
required Delivery Gate/project-gate input is fail, missing, stale or unverifiable.

Overall score is reported for trend only. `overall >= threshold` MUST NOT produce PASS
when `blocking_findings:true`.

The audit status is:
- BLOCK: blocking_findings=true
- PASS_WITH_FINDINGS: no blocker, at least one Medium/Low
- PASS: no findings
```

### 7.3 Structured Auditor output

Add a machine-readable companion artifact:

```text
audit-report.json
```

Minimum shape:

```json
{
  "head_commit": "...",
  "status": "BLOCK",
  "blocking_findings": true,
  "findings": [
    {
      "id": "AUD-DELIVERY-001",
      "severity": "High",
      "category": "delivery_integration",
      "area": "package.json",
      "evidence": "npm run build exited 1",
      "recommendation": "restore compatibility or remove remaining consumer",
      "auto_fixable": false,
      "resolved": false
    }
  ]
}
```

Markdown remains the human-readable report; JSON is the CP5 input.

### 7.4 Auditor anti-patterns to prohibit

Add explicit prohibitions:

- do not call a package “clean” solely because its own tests pass;
- do not classify pre-existing consumer code as out of scope when this EPIC changed its manifest/public dependency contract;
- do not defer a broken next-phase contract as “future work” when that next phase is already declared;
- do not treat a skipped plan-diff or irrelevant green suite as product evidence;
- do not let weighted scoring cancel a release blocker.

## 8. Curator instruction changes

### 8.1 Preserve role, remove approval semantics

Curator remains responsible for collecting improvement notes, deduplicating backlog, identifying patterns and extracting lessons. It is not a correctness or merge gate.

Replace report-level terms:

```text
APPROVED / APPROVED_WITH_DEFERRED
```

with:

```text
PROPOSALS_READY / NO_PROPOSALS / INPUT_INCOMPLETE
```

Per-proposal `recommended_disposition` remains valid; it is not an EPIC verdict.

### 8.2 Make Auditor input mandatory for final Curator phase

Add:

```markdown
The final Curator phase MUST start after `audit-report.json` exists and is bound to current
HEAD. Every unresolved Auditor finding is ingested before deduplication.

Critical/High Auditor findings:
- priority is always high;
- cannot be rejected or deferred solely because effort is M/L;
- non-auto-fixable findings are escalated to CP5/PM;
- remain unresolved until verified by CP4 + Delivery Gate.

Curator MUST NOT emit a merge/approval verdict. It reports proposal readiness only.
```

### 8.3 Curator output additions

```yaml
input_audit:
  path: "audit-report.json"
  head_commit: "..."
  head_matches: true
  findings_ingested: 3
unresolved_blocking_findings: ["AUD-DELIVERY-001"]
proposal_status: PROPOSALS_READY
```

## 9. Shared verifier contract and enforcement changes

### 9.1 Required top-level fields

For CP2/CP3/CP4/CP6, require and enforce:

```yaml
_generated_by: ...
_generated_at: ...
checkpoint: cp2|cp3|cp4|cp6
focus: ...
classification: FULL_REVIEW|RUN|FAIL|SKIP
verdict: pass|fail|skip|pending
base_commit: ...
head_commit: ...
findings_count: 0
```

Do not accept equivalent fields nested inside a fenced YAML block when the FSM expects top-level fields.

### 9.2 Remove opt-in behavior-trace enforcement

Current behavior allows omission of `behavior_trace_required`, which prevents enforcement. Change to:

```text
high-risk detector determines trace_required independently
if detector says required:
    output must say behavior_trace_required:true
    behavior_trace_count must be > 0
    missing field is fail
if detector says not required:
    output must give behavior_trace_skip_reason
```

The reviewer cannot disable the gate by omitting a field.

### 9.3 Artifact freshness

`fsm_check_verifier_output` must compare output `head_commit` to current HEAD. For CP2 it may compare to the step commit. For CP3/CP4/CP6 it must match the reviewed final/current revision exactly.

### 9.4 Verdict enforcement

Presence-only enforcement is insufficient. Transition rules must consume verdicts:

- CP2/CP3 `fail` blocks and invokes fix/escalation;
- CP4 `fail` reverts fix and preserves the original unresolved finding;
- CP6 `fail` blocks when CP6 is classified blocking;
- `pending` never satisfies a transition;
- malformed/unknown verdict is fail-closed.

### 9.5 Adaptive-lens and iteration enforcement

`review-profile.json` is detector output and carries `profile_hash`. Every IR/CP3 artifact MUST repeat that hash plus `required_lenses`, `completed_lenses`, reviewed commit range and unresolved finding IDs.

The FSM validates set equality:

```text
required_lenses - completed_lenses == empty
```

Unknown completed lenses are allowed as reviewer additions; missing required lenses block. IR reports use stable IDs (`IR-1`, `IR-2`, `IR-3/CP3`) and may satisfy only their declared assembly point. Re-running IR-1 after a fix replaces its verdict only when it references the original finding IDs and a descendant HEAD. Copying a final CP3 report into missing IR-1/IR-2 slots is invalid.

## 10. Policy configuration changes

Extend `review-checkpoints.yaml` or split delivery policy into its own file. Recommended split keeps responsibilities clearer.

```yaml
review_checkpoints:
  cp1_plan_review: true
  cp2_step_review: true
  cp3_integration_review: true
  adaptive_profiles: true
  max_integration_reviews: 3
  block_on_missing_detected_lens: true
  cp3_security_mode: risk_based       # always | risk_based | disabled
  cp4_fix_validation: true
  cp5_release_policy: true
  cp6_mode: risk_based                # blocking | risk_based | advisory

  curator:
    run_after_auditor: true
    allow_epic_approval_verdict: false

  auditor:
    delivery_integration_audit: true
    block_severities: [critical, high]
    block_on_missing_required_evidence: true
```

Delivery config remains in `delivery-gate.yaml` so command/profile changes do not mix with reviewer dispatch policy.

## 11. FSM and pipeline enforcement changes

### 11.1 New/changed preconditions

| Transition/action | Required condition |
|---|---|
| EPIC generation | CP1 pass, producer-consumer table, delivery evidence plan, review profile and integration points present |
| step at IR-1/IR-2 boundary -> next step | required IR report current/pass; no unresolved Critical/High; affected prior traces rechecked |
| final EXECUTE step -> CP3 | Delivery Gate D0 exists, current HEAD, ready or explicit fail routed to fix loop |
| EXECUTE -> GATES | CP3 current and pass; D0 current and ready |
| apply review fixes -> CP4 | applied-fix range and source finding IDs recorded |
| CP4 -> CP5 | CP4 pass and affected D1 checks rerun |
| MERGE offered | `release-decision.json.release_ready == true` and HEAD matches |

### 11.2 Fail-closed rules

- absent policy/config uses safe defaults;
- malformed JSON/YAML is `unverifiable` and blocking for required artifacts;
- unknown ecosystem does not become PASS; it requires explicit commands or waiver;
- a waiver requires PM identity, reason, timestamp, affected check and expiry/scope;
- `--force` cannot fabricate `delivery_ready:true`; it records a release waiver separately.

### 11.3 Waiver artifact

```json
{
  "check_id": "clean_install",
  "epic_id": "E-...",
  "head_commit": "...",
  "approved_by": "pm",
  "approved_at": "...",
  "reason": "registry outage; local lock/build checks passed",
  "scope": "one run only"
}
```

Waived checks remain visible as `unverifiable_with_waiver`, not PASS.

### 11.4 Gate-fixer instruction changes

**File:** `plugins/aid-orchestrator/agents/gate-fixer.md`

Add the following contract for checkpoint and audit fixes:

```markdown
Every fix request MUST identify:
- source finding/proposal ID;
- reviewed base and target HEAD;
- allowed files;
- expected affected Delivery Gate checks;
- whether the source finding is release-blocking.

The gate-fixer MUST NOT:
- broaden scope beyond the source finding;
- suppress, edit or reclassify a failed gate artifact;
- mark an Auditor finding resolved;
- create `delivery_ready:true` or `release_ready:true` directly;
- remove a failing test/check merely to obtain PASS.

After applying a fix, report changed files and the Delivery Gate checks that must be
invalidated. Resolution is decided only by CP4 plus the re-run deterministic checks.
```

Required gate-fixer output additions:

```yaml
source_findings: ["AUD-DELIVERY-001"]
base_commit: "..."
head_commit: "..."
changed_files: []
invalidate_delivery_checks: ["build", "typecheck", "test"]
resolution_claimed: false
```

### 11.5 File-by-file implementation map

| Existing/new file | Required change |
|---|---|
| `commands/aid-plan.md` | add CP1 producer-consumer table, migration atomicity and delivery-evidence stop rules |
| `commands/aid-run.md` | insert D0 before CP3, risk-based security dispatch, D1 after CP4 and CP5 release decision |
| `commands/aid-do.md` | replace advisory-only CP6 flow with risk-based Delivery Gate flow |
| `skills/review-checkpoint-contracts.md` | replace CP contracts with the responsibilities and required fields in section 6 |
| `skills/pipeline.md` | change ordering, context assembly, fix loops, Auditor/Curator sequencing and MERGE precondition |
| `skills/run-management.md` | document D0/D1 lifecycle, stale-artifact handling and release-ready semantics |
| `skills/agent-protocol.md` | register new structured fields/artifacts and fail-closed output behavior |
| `agents/verifier.md` | add CP1/CP2 contract exceptions, CP3 integration context, CP4 scope and CP6 risk semantics |
| `agents/auditor.md` | add mandatory delivery/integration category, structured JSON and derived blockers |
| `agents/curator.md` | require current Auditor input, remove EPIC approval vocabulary, escalate blockers |
| `agents/gate-fixer.md` | prohibit evidence suppression and emit invalidated Delivery Gate checks |
| `defaults/policies/review-checkpoints.yaml` | add risk modes, Auditor blocker policy and Curator sequencing |
| `defaults/policies/review-profiles.yaml` | detector-owned surface-to-lens/probe matrix and 1-3 review cadence |
| `defaults/policies/delivery-gate.yaml` | new command profiles, applicability and unverifiable policy |
| `defaults/templates/verifier-output-template.md` | add HEAD binding, command, consumer and affected-check fields |
| `defaults/templates/delivery-gate-template.json` | new canonical Delivery Gate artifact |
| `defaults/templates/review-profile-template.json` | canonical detected surfaces, required lenses and integration points |
| `defaults/templates/acceptance-evidence-template.json` | canonical AC identity, production trace, test and deviation evidence |
| `defaults/enforcement-registry.yaml` | register every new precondition and its instruction home |
| `scripts/aid-delivery-gate.sh` | new deterministic gate executor |
| `scripts/aid-prefilter.sh` | emit detector-owned risk/trace requirement; reviewer omission cannot disable it |
| `scripts/aid-fsm.sh` | enforce D0/CP3/D1/CP5 freshness, verdicts and `release_ready` before MERGE |
| `scripts/aid-run-gates.sh` | expose gate relevance/covered paths and feed result into release policy |
| `scripts/tests/test-delivery-gate.sh` | new DG-01 through DG-18 and negative tests |
| `scripts/tests/bats/test-aid-fsm.bats` | add transition, freshness, verdict, waiver and release-decision tests |
| `docs/extending-aid.md` | document how projects configure delivery profiles and enforcement homes |
| plugin/root CHANGELOGs as required by repository policy | document behavior and evidence-contract changes |

### 11.6 Components intentionally not promoted to release gates

- Curator remains non-blocking proposal machinery; only unresolved source findings affect CP5.
- Reporter remains delivery communication/evidence, not proof that tests passed.
- Simplifier remains plan-boundary proposal machinery; its applied fixes enter the same CP4/D1 path.
- Scores and trends remain informational.
- Memory/lessons output never changes release readiness.

## 12. Gate coverage and relevance

Existing gates remain useful but must declare which changed surface they cover.

Add to gate reports:

```json
{
  "gate": "bats_fsm",
  "covered_paths": ["plugins/aid-orchestrator/scripts/**"],
  "changed_paths_covered": 0,
  "relevance": "none"
}
```

Coverage states:

```text
direct | partial | none | unknown
```

A green `none` gate is retained as project health information but cannot prove the EPIC delivery. CP3 and Auditor must list uncovered changed production surfaces.

## 13. Test plan

### 13.1 Delivery Gate tests

Required fixtures:

1. root build passes -> `delivery_ready:true`;
2. package build passes but root build fails -> blocking false-ready regression test;
3. dependency removed while import remains -> DG-06 fail;
4. manifest/lock mismatch -> DG-01 fail;
5. public export missing but next EPIC imports it -> DG-05 fail;
6. zero tests discovered -> `unverifiable`, not pass;
7. required command unavailable -> `unverifiable` and block;
8. optional inapplicable check -> valid skip with reason;
9. stale HEAD in report -> block;
10. post-CP4 change invalidates prior D0 -> D1 required;
11. logs/output previews are bounded and full logs retained;
12. argv-array execution does not invoke shell expansion.
13. typecheck compiles only a declaration shim while production TS/TSX exists -> DG-09 unverifiable/fail;
14. clean install under the declared runtime differs from the developer install -> DG-08/DG-01 fail;
15. framework major compiles but production entry point throws during route registration -> DG-10 fail;
16. build config references an absent package not imported by source -> DG-11 fail;
17. inner build/test lifecycle reports failure while an outer launcher exits 0 -> fail, never pass;
18. plan/EPIC expects an obsolete closed vocabulary while the locked spec and implementation use another -> DG-12 fail;
19. path validation allows a sibling-prefix escape -> security fixture fail;
20. all leaf suites pass but the root workspace command exits non-zero -> DG-04 fail.
21. a required hook/component is exported and unit-tested but never mounted from the production entry point -> DG-13 fail;
22. a real WS provider emits nested `data` while the real consumer reads top-level fields -> DG-14 fail;
23. a generated `/plan/:id` link has no matching production `/plans/:id` route -> DG-15 fail;
24. fallback passes in isolation but the mounted app never invokes it -> DG-13/DG-16 fail;
25. analytics is self-consistent but drops records versus an independent oracle -> DG-17 fail;
26. acceptance evidence maps a test by name but a mutation removing the asserted behavior still passes -> DG-18/CP3 fail;
27. `compliance.overall:fail`, active task metadata or pending child steps coexist with parent DONE/release -> DG-07/CP5 fail.

### 13.2 CP/FSM tests

1. CP3 missing Delivery Gate -> transition rejected;
2. CP3 report nested fields but missing required top-level fields -> rejected;
3. high-risk diff omits behavior trace field -> rejected;
4. CP3 fail -> fix loop/escalation, never GATES;
5. CP4 pass without affected gate rerun -> CP5 rejected;
6. Auditor High finding + score 95 -> release blocked;
7. Auditor score 60 with no blockers -> release may proceed with PM warning under policy;
8. Curator report containing EPIC `APPROVED` verdict -> schema rejected or ignored;
9. CP6 production change fail -> blocking;
10. CP6 docs-only valid skip -> advisory pass;
11. release decision stale against HEAD -> MERGE not offered;
12. forced waiver remains visible and does not rewrite check to PASS.
13. medium profile missing IR-1 -> final CP3 rejected;
14. high mixed-surface profile has only one repeated final review -> CP3 rejected;
15. detector requires `realtime_async`, reviewer omits wire/fallback lens -> schema/adjudication rejected;
16. IR-1 finds a High wiring defect -> later implementation transition blocked until a current recheck resolves it;
17. isolated unit suites all pass while production wiring/runtime contract fixtures fail -> CP3 and release remain blocked.

### 13.3 E-047 regression fixture

Create a compact fixture reproducing:

- shared contract package builds alone;
- root server still imports a removed dependency;
- next phase imports missing shared symbols;
- irrelevant plugin tests pass.
- GUI typecheck is made vacuously green by including only `vite-env.d.ts`;
- target-runtime clean install exposes a native/optional dependency mismatch;
- a framework-major "fix" makes the production server fail at startup;
- bundler configuration references an undeclared module;
- 1000+ leaf tests pass while the root command fails on a zero-test workspace;
- plan/EPIC/spec retain contradictory runtime and event-contract requirements.
- GUI creates WS and polling hooks but never mounts them in the application shell;
- server emits `{type, topic, data, ts}` while GUI expects top-level event payload fields;
- a table link producer uses `/plan/` while the router registers `/plans/`;
- More-sheet install and plan-switcher requirements remain placeholders despite completed leaf components;
- API outage is converted into a false "project not found" state;
- 170 isolated tests pass with no real client-server contract or shell E2E test;
- FSM reaches release while child steps are pending, task counters are open and compliance says fail.

Expected result:

```text
CP2 local package: may pass
Delivery Gate: fail DG-05/DG-06/DG-08 through DG-18 as applicable + root build/test
CP3: fail
Auditor: blocking_findings true
CP5: release_ready false
```

This fixture proves that layered controls can disagree honestly while the final release decision remains safe.

## 14. Rollout plan

### Phase 0: contract and schema

- finalize this design;
- define Delivery Gate JSON schema and release-decision schema;
- add enforcement-registry entries;
- decide project override format.

### Phase 1: deterministic Delivery Gate in observe mode

- implement profiles and artifacts;
- run during CP3 without blocking for several representative projects;
- measure command availability, duration and false applicability;
- never label observe failures PASS; mark them non-blocking only because rollout mode is explicit.

### Phase 2: blocking core checks

- block on dependency consistency, build, typecheck and tests where configured;
- add stale-HEAD enforcement;
- add E-047 regression fixture;
- connect D0 to CP3.

### Phase 3: instruction refactor

- deploy CP1 producer-consumer/delivery-evidence contract;
- deploy CP2 public-contract exception;
- deploy CP3 integration context/output;
- deploy detector-owned adaptive review profiles and 1-3 IR cadence;
- add production wiring, runtime contract, route, fallback and oracle lenses;
- make security risk-based;
- update templates and tests together.

### Phase 4: DONE review refactor

- add Auditor delivery/integration category and structured JSON;
- require fresh-context replay of one detector-selected high-risk trace;
- sequence Curator after Auditor;
- restrict Curator verdict vocabulary;
- update CP4 affected-check reporting.

### Phase 5: CP5 release policy and CP6 alignment

- generate `release-decision.json`;
- require current acceptance evidence and all profile-required IR reports;
- make MERGE conditional on current `release_ready:true`;
- make CP6 blocking for production/high-risk `/aid-do` changes;
- retain explicit PM waivers without rewriting evidence.

### Phase 6: simplify redundant review work

After data confirms the new gate works:

- stop unconditional CP3 security dispatch on non-security diffs;
- retain CP2 trivial skip;
- remove duplicate deterministic command narration from LLM prompts;
- let agents consume structured gate summaries rather than re-running every command;
- track escaped defects and false blocks before removing any additional review.

## 15. Migration and compatibility

- Existing evidence without Delivery Gate remains readable but cannot satisfy the new release policy after the configured enforcement date.
- Pre-enforcement runs use `legacy_review_contract:true` and must not be silently rewritten.
- Existing `audit-report.md` remains supported; new runs also require `audit-report.json`.
- Existing CP output parsers may accept old files for display, while FSM transitions require the new schema only for runs created after deployment.
- Defaults must be copied during `/aid-init` migration without overwriting project-local commands.

## 16. Operational metrics

Track per release:

- escaped integration defects discovered after CP5;
- Delivery Gate failure rate by check;
- false-block/waiver rate;
- median/p95 gate duration;
- CP3 findings that duplicate deterministic failures;
- Auditor blockers missed by CP3;
- percentage of green gates with `relevance:none`;
- stale/malformed evidence attempts;
- Curator proposals originating from current Auditor findings;
- CP6 production changes processed as blocking versus advisory.
- median time and changed-step count from implementation start to first integration finding;
- number of IR passes per profile and duplicate-finding rate between IR-1/IR-2/IR-3;
- detector lens omissions, manual lens additions and waivers by surface class;
- escaped defects by missing/incorrect review profile;
- production-reachability, runtime-contract, fallback and independent-oracle failures;
- static-check coverage ratio and count of vacuous-green checks blocked;
- declared-runtime matrix drift incidents;
- startup-smoke failures after framework/runtime changes;
- authority contradictions detected between user decision, spec, plan, EPIC and tests.

Success is not “more findings”. Success is fewer false-ready releases with acceptable execution time.

## 17. Implementation checklist

### Contracts and policy

- [ ] Approve target order and ownership matrix.
- [ ] Approve block severities: Critical + High.
- [ ] Approve `unverifiable` as blocking for required checks.
- [ ] Approve risk-based CP3 security and CP6 modes.
- [ ] Approve Auditor-before-Curator sequencing.
- [ ] Approve detector-owned adaptive profiles and 1/2/3 integration-review cadence.
- [ ] Promote the second-opinion acceptance-evidence contract to normative release input.

### Delivery Gate

- [ ] Add default/project policy schema.
- [ ] Implement safe command profile resolution.
- [ ] Implement DG-01 through DG-12.
- [ ] Implement DG-13 through DG-18.
- [ ] Emit HEAD-bound JSON + detailed logs.
- [ ] Add incremental D0/D1 invalidation.
- [ ] Add waiver artifact without PASS rewriting.

### Checkpoints

- [ ] Update CP1 producer-consumer and delivery-evidence review.
- [ ] Add CP1 authority/runtime matrix review.
- [ ] Update CP2 public-contract/dependency exception.
- [ ] Replace CP3 context and output contract.
- [ ] Add IR-1 wiring, IR-2 behavior and IR-3 final semantics with finding-ledger carry-over.
- [ ] Add production-reachability, real wire-contract, route/dispatch, fallback and oracle checks.
- [ ] Make security dispatch risk-based.
- [ ] Add CP4 affected-check and scope fields.
- [ ] Replace CP5 boolean check with release policy.
- [ ] Align CP6 with Delivery Gate.

### DONE roles

- [ ] Add Auditor category K and structured output.
- [ ] Derive `blocking_findings` mechanically from severity/evidence.
- [ ] Remove Curator EPIC approval vocabulary.
- [ ] Sequence final Curator phase after Auditor.

### Enforcement and tests

- [ ] Enforce top-level CP fields and HEAD freshness.
- [ ] Make high-risk trace requirement detector-driven.
- [ ] Consume verifier verdicts, not only file presence.
- [ ] Add Delivery Gate, FSM, CP5 and E-047 regression tests.
- [ ] Add the E-047-5 unmounted-hook/wire-drift/false-release regression fixture.
- [ ] Add static-coverage, clean-runtime, startup, config-resolution and traversal fixtures.
- [ ] Register every enforcement home.
- [ ] Update CHANGELOG and extending-AID documentation.

## 18. Acceptance criteria for the refactor

The refactor is complete only when all of the following are demonstrated:

1. A fixture where a leaf package passes but root build fails cannot reach `release_ready:true`.
2. A removed dependency with a remaining production import is deterministically blocked.
3. A shared public contract missing a next-phase import is blocked before that next phase starts.
4. CP3 cannot pass without current Delivery Gate evidence.
5. An Auditor score above threshold cannot override a Critical/High or required-gate failure.
6. Curator cannot produce an authoritative EPIC merge verdict.
7. CP4 changes invalidate and re-run affected Delivery Gate checks.
8. CP5 aggregates all required evidence into a HEAD-bound release decision.
9. Production `/aid-do` changes cannot bypass blocking delivery checks through advisory CP6.
10. Docs-only/trivial changes retain a low-cost path with explicit, honest skip reasons.
11. Existing project-specific gates remain visible, including relevance to changed paths.
12. Negative tests prove missing, stale, malformed and unverifiable evidence fail closed.
13. A vacuous typecheck cannot satisfy delivery evidence for a package with typed production sources.
14. Runtime pins, engines, CI/container images, plan constraints and ACs cannot disagree at release.
15. A compiling server that fails production startup cannot reach `release_ready:true`.
16. Build-configuration-only module references are included in dependency consistency.
17. Closed public vocabularies are compared completely against one authoritative source.
18. Filesystem-serving changes pass adversarial traversal and sibling-prefix tests.
19. An exported and unit-tested but unmounted required feature cannot reach `release_ready:true`.
20. Real provider output must be accepted by the real consumer; independently green mocked suites cannot substitute for boundary conformance.
21. Every generated navigation/dispatch value resolves through the production registry/router.
22. A promised fallback is proven through forced failure and recovery on the mounted path.
23. Data/reporting changes pass an independent-oracle no-drop check where applicable.
24. Medium/high profiles cannot skip their required two/three integration reviews.
25. The final Auditor independently replays at least one highest-risk trace from fresh context.
26. Acceptance evidence covers every authoritative AC and detects changed expectations or non-falsifying tests.
27. Parent DONE/release is impossible while a child step, task/run counter or required aggregate remains failed/incomplete.

## 19. Non-goals

- Replacing project-specific tests with generic Delivery Gate checks.
- Making every CP a full repository audit.
- Running every possible command for every docs-only change.
- Using an LLM score as a release decision.
- Turning Curator into another code reviewer.
- Eliminating PM waivers; waivers remain explicit, scoped and auditable.
- Guaranteeing correctness from one control. The design relies on distinct, non-duplicative layers.

## 20. Recommended first implementation slice

Implement in this order so each slice closes a real false-DONE path:

1. define schemas for `review-profile.json`, `delivery-gate.json`, `acceptance-evidence.json`, `audit-report.json` and `release-decision.json` plus HEAD freshness;
2. harden DG-07 and FSM transitions so failed/incomplete state can never reach release;
3. implement core deterministic DG-01 through DG-12 and require current D0 before final CP3;
4. implement detector-owned adaptive profiles in observe mode, then block missing detected lenses after fixture calibration;
5. implement DG-13 production reachability, DG-14 real provider-consumer conformance and DG-15 route/dispatch conformance;
6. add the E-047-5 fixture and require IR-1/IR-2 at detector-selected assembly points for medium/high profiles;
7. implement DG-16 fallback/recovery and DG-17 independent-oracle probes;
8. promote the second-opinion acceptance-evidence/test-falsifiability rules through DG-18 and CP3;
9. add fresh-context Auditor replay and mechanically derived blockers;
10. replace CP5 with complete evidence aggregation and enable MERGE only for current `release_ready:true`;
11. add E-047-1, E-047-4, E-047-5, E-044 and P045 negative regression fixtures before simplifying any existing review.

Steps 1-6 are the first blocking implementation slice. They close the concrete Cockpit false-DONE path. Steps 7-11 add semantic depth and only then provide enough evidence to remove redundant generic reviews.
