# P096 Step 8 — delivery gate triage

Recorded 2026-09-20. Every `delivery-gate.json` on disk was read: WAN and ACTA
(101 EPIC runs, 1 485 check rows) and this repository (38 runs). The numbers
were re-measured by an independent reviewer (Claude Opus standing in for Codex,
over its usage limit until 2026-09-21), who also read every check script.

    find /opt/eco/projects/{wan,acta}/.aid-o/work/evidence -name delivery-gate.json \
      | xargs jq -r '.delivery_gate.checks[]? | "\(.id) \(.status) \(.skip_reason // "")"' | sort | uniq -c

## What the numbers say

- **Consumer projects: 0 executions.** Every one of the 1 485 rows is
  `unverifiable / unverifiable_profile`. The gate knows two ecosystems
  (npm workspaces, and this repository's own layout); WAN and ACTA are Python, so
  no profile ever matched and no check ever ran. `would_block` was false in
  101 of 101 runs because nothing was evaluated.
- **This repository: one fail in 38 runs** (dg08, once). dg04 re-runs the
  merge-path test tiers that the required `tests_pass` gate has just run: a
  second 13 to 32 minute test run per EPIC.
- The policy sat at `enforcement: observe` from the day it was written, so even
  that one fail blocked nothing.

## Verdict per check

| Check | What it guards | Ran in consumers | Covered elsewhere | Verdict |
|---|---|---|---|---|
| dg01 dependency-consistency | runs a project-supplied dependency command | 0 of 101 | a project `deps` gate in `execution.yaml` | removed |
| dg02 build | runs the declared build command | 0 of 101 | the project's `build` gate | removed |
| dg03 typecheck | runs the declared typecheck command | 0 of 101 | the project's `type_check` gate | removed |
| dg04 test | runs the declared test command | 0 of 101 | the required `tests_pass` gate (same command, run twice) | removed |
| dg05 consumer-compile | compiles changed consumer paths | 0 of 101 | the project's build gate | removed |
| dg06 removed-dep | npm-only diff heuristic | 0 of 101 | the cp3 and cp7 diff reviews | removed |
| dg07 state-consistency | step completeness, open dispatches, compliance fail | 0 of 101 | hard FSM preconditions that already block upstream (`aid-fsm.sh` advance-to-gates, orphan-dispatch check, `evaluate_compliance_checks`) | removed |
| dg08 runtime-env | Node / Dockerfile major versions agree | 0 of 101 | nothing; npm-specific, fired once here | removed |
| dg09 static-coverage | "0 files checked" is not a pass | 0 of 101 | nothing; the idea is kept as IMP-618 for the gate rebuild | removed |
| dg10 startup-smoke | runs a project smoke command | 0 of 101 | a project gate | removed |
| dg11 build-config | runs a project command on config change | 0 of 101 | a project gate | removed |
| dg12 authority | policy YAML: enforcement enum, `blocking` with `planned` | 0 of 101 | kept as a merge-path lint (`test-enforcement-registry-cites.sh`) | removed, rule kept |
| dg15 route-resolve | literal links against declared routes | 0 of 101 | needs a `delivery-map.yaml` no project has | removed |
| dg17 oracle-nodrop | analytics cardinality baseline | 0 of 101 | needs `oracle_baselines` no project has | removed |
| dg18 acceptance-struct | provenance only; by its own header never fails | 0 of 101 | P095's acceptance evidence built from `plan-diff.json` | removed |

## Decision

All fifteen are removed, and with them the runner, the profile and map
libraries, the policy, the EPIC FSM's D0 and DG-07 hooks, the plan-level
aggregate, the `delivery_gate` input of the release decision and the evidence
verifier's `observe_blocking_interpretation` check (it read only this gate's
output). `aid-promote-checks.sh` stays: the plan named it as part of this gate,
but it renders promotion candidates of the COMPLIANCE checks
(`check-severity.yaml`), a different mechanism. The artifact type
`delivery_gate` stays valid in the protocol so that evidence written before
this release still verifies.

Successor: **the project's own blocking gates in `.aid-o/config/execution.yaml`**
(run at EPIC GATES and again at plan close) **and the `final_criteria` role of
the whole-plan round**, which ties every acceptance criterion to an executed
test.

Why not flip it to blocking instead: every Python plan would then fail on
`unverifiable_profile`, or "no profile matched" would have to read as
not-applicable, which is a blocking gate that blocks nothing. Writing ecosystem
profiles for every consumer is a project nobody asked for.

Two guards were unique and are kept in a smaller form: dg12's two rules as a
merge-path lint over the shipped policies and the registry; dg09's idea
("a gate whose output says 0 tests is unverifiable, not a pass") as backlog row
IMP-618 for the plan that rebuilds the gate runner.
