---
id: P096
type: refactor
status: draft
created: 2026-09-20
author: PM + AI
risk: high
lifecycle_strict: true
depends_on_plans: [P095]
---

# Plan: Plan-Final Rebuild — five stages, one independent reading of the whole plan, a decision that can say yes

## Context

When every EPIC of a plan is done, `aid-plan-fsm.sh plan-finalize` closes the plan in eight stages (`sync`, `freeze`, `gates`, `inputs`, `review`, `c4`, `summary`, `accept-ancillary`; `scripts/aid-plan-fsm.sh:4069-7051` and `:10265`). The `review` stage requires by hash the outputs of nine mechanisms (`_pfsm_review_required_outputs`, `:5168-5182`): C1 delivery gate (`scripts/aid-delivery-gate.sh`, 15 checks under `scripts/lib/delivery-checks/`), C2 semantic review, the C3 auditor on Codex (`agents/auditor.md`, `scripts/lib/aid-c3-dispatch.sh`), the curator (`agents/curator.md`), CP4 (a verifier over the curator's and auditor's own diffs), CP5, the simplifier (`agents/simplifier.md`), the reporter (`agents/reporter.md`) and the memory scanner, and C4 (`scripts/aid-release-policy.sh`) aggregates them. A fix after the freeze clears the candidate binding (`plan_final_invalidate`, `:4016`) and every stage runs again under a new run id `R-<plan>-final-<N>` (`:3982`). The controller's instructions are `skills/pipeline.md` §7, lines 1293-2635.

Measured on 2026-09-20 over every plan-final run on disk (ACTA 6 plans / 25 runs, WAN 9 plans / 50 runs; `.aid-o/work/interim-P096.md`): a plan closes in a median of 4 to 5 attempts (up to 11), 2.3 to 3.5 hours from the first attempt to the last; 34 of 75 attempts ended right after the gates stage; C4 said `release_ready: true` in 0 of 14 decisions, every time blocked by `verification_report`, and 112 waiver files lie in the two evidence trees; the delivery gate ran with `enforcement: observe` in 37 of 37 runs (`defaults/policies/delivery-gate.yaml:14`); CP4 returned pass in 109 of 109 runs; the simplifier reported no change in 15 of 27; the reporter is the longest wait (median 7 to 12 minutes) although the PM page is already computed by `scripts/aid-pm-brief.sh` without a model. The auditor is the one mechanism with a proven yield: eight high findings (an acceptance criterion with no executed test, criteria recorded unverified, a CHANGELOG claiming behaviour that does not occur, a docs-only plan that changed code, a binding deployment order living only in the backlog).

An independent opponent (Claude Opus standing in for Codex, which is over its limit until 2026-09-21; `.aid-o/work/brainstorm/P096/opponent-cc.md`, seven disagreements, the four central ones verified in code) corrected the reading of those numbers: C4 never says yes because `run_git_clean_check` is a bare `git status --porcelain` (`scripts/aid-evidence-verify.sh:203`) while the FSM's own drift detector filters ancillary paths (`scripts/aid-plan-fsm.sh:5886-5893`, through `aid_ancillary_filter_porcelain --mode legacy5`, a hard-coded five-path list that does not read the policy), and AID itself dirties the tree with the tracked `.aid-o/config/counter.yaml`, which neither that list nor `defaults/policies/plan-final-policy.yaml:43-58` names; the C2 lenses "never failed" because all 17 surface globs of `defaults/policies/review-profiles.yaml` start with `plugins/aid-orchestrator/`, so 40 of 40 consumer runs resolved to `risk_profile: unverifiable`, and `scripts/aid-review-profile.sh:69` has no project override; gates are re-run in full on every attempt although nothing in `_pfsm_finalize_gates` (`:4689-4760`) reads the previous attempt; the eleven-file inventory is hard-coded three times (`scripts/aid-plan-fsm.sh:5169-5181`, `:5996`, `scripts/lib/aid-lifecycle.sh:201`); `compute_reporter` makes the reporter mandatory (`scripts/aid-release-policy.sh:446-461`); and nine registry rows for the reporter and the simplifier are `status: planned` with `deadline: "2026-09-30"` (`defaults/enforcement-registry.yaml:381-387`, `:1364`, `:1467`; added 2026-06-18 by commit 6702c5e4 so that prose-only checks would not rot), two more rows carry `deadline: "2026-09-01"` but are `status: active`, which the guard does not evaluate (`:400`, `:413`), while `scripts/aid-registry-ttl-guard.sh` is a required check of the evidence verifier: from 2026-10-01 plan-final would fail in every project.

P093 rebuilt the plan review and P094 the step, EPIC and fast-mode reviews on one round engine (`scripts/aid-review-round.sh`, `scripts/aid-review-adjudicate.sh`, `scripts/lib/aid-review-config.sh`, `scripts/lib/aid-review-summary.sh`, one finding schema, USD from `defaults/prices.yaml`); P095 (in development, this plan depends on it) adds the automatic Claude stand-in for Codex roles, the tracked-only `git_clean`, the state-root pack lookup and the plan-level acceptance evidence built from `plan-diff.json`. This plan applies the same method to the end of the plan. The vision is `.aid-o/work/brainstorm/P096/vision.md` (V1 to V10, approved 2026-09-20 with the PM's amendments: quality first, line counts only measured; everything wired; clean code at the source). PM decisions: the reporter goes entirely; the simplifier leaves the flow; no compatibility with in-flight plans; the independent reading runs on Codex when available and on the automatic stand-in otherwise; nothing is deleted before its successor passes on the same sample; the TTL deadline is handled inside this plan.

## Goal

A plan whose work is sound closes on the first attempt with its time and cost visible (under 15 minutes is the post-release target tracked on three live plans by `docs/plans/P096-live-follow-up.md`; before release the replay of Step 11 must be faster than the baseline): `freeze` fixes the candidate, `gates` runs only the gates whose inputs changed since the previous attempt, `produce` derives the review inputs, one round of the P093/P094 engine reads the whole plan with three roles (criteria against executed tests, claims against code, a generalist on another provider) and findings that carry evidence, the role that wrote the code fixes what stays open and a confirmation round re-checks only that, and `decide` says `release_ready: true` when the gates are green, the round is closed and the obligations are settled, without a waiver. A fix after the freeze invalidates only what depends on what it changed. The reporter, the simplifier as a plan-final step, the curator, the auditor's separate bridge, CP4 and CP5 are gone with a named successor or a recorded reason each, only after the new round has confirmed the auditor's eight real findings on replay; the delivery gate's checks either block or are gone; the risk profile resolves in a consumer project; the controller reads one section; the programming role carries a short clean-code ladder and the step reviewer asks about needless complexity.

## Scope

**In scope**
- Deadline first: the seven `planned` reporter and simplifier rows due 2026-09-30 get `deferred_until: "2026-10-31"`, `deferred_by` and `deferred_reason` in Step 1 and are removed with a replacement guard in Step 12; the two other `planned` rows of the same date (`plan_queue_scripted_transitions`, `plan_final_required_gates_record`, both owned by the P068 line and outside this plan) are re-dated to 2026-12-31 with their own reason and are never removed here (the two `active` rows dated 2026-09-01 are not evaluated by the guard and are left alone), so the TTL guard cannot break plan-final in consumer projects whatever happens to the rest of the plan.
- Baseline and replay sample: the eight auditor high findings of ACTA and WAN whose reviewed commits still exist, the attempts and minutes per plan, and the line count of the area, in tracked fixture files, before anything changes.
- Risk profile outside this repository: a project override `.aid-o/config/policies/review-profiles.yaml` that may add surfaces or raise a level and never lower the default's verdict, generic default globs, and a close path that refuses a lens or role name outside the run's expected roles.
- A decision that can say yes: `git_clean` through the ancillary filter, `.aid-o/config/counter.yaml` ancillary in the policy and in the strict fallback list, a project policy that cannot declare its own delivery paths ancillary, a sabotage set of four plans; a switched-off whole-plan review blocks the decision unless the PM waives it for that candidate.
- Checkpoint `cp7` on the round engine: reviewer block `final_review`, roles `final_criteria`, `final_claims`, `final_generalist`, a packet builder for the range `plan_base_commit..candidate_sha`, namespace `final_review`, `close` writing `semantic-review-final.json` at the run root in today's shape, measurement in tokens and USD, the P095 stand-in, an FSM check.
- Gates reused across attempts by input fingerprint.
- Fix after freeze in three classes (ancillary, evidence-local, delivery) with stage-dependent invalidation; `sync` folded into `freeze`; `accept-ancillary` a flag of `freeze`.
- Stage `decide`: one aggregate replacing `c4` and `summary`; receipt `schema_version` `aid-plan-final-evidence-2` in all three inventory sites and the close check; time and cost on the PM page, the card and `/aid-status`.
- Delivery gate triage: each of the 15 checks becomes blocking or is removed; `enforcement: observe` disappears as a permanent state.
- Clean code at the source: a ladder in `skills/role-cards.md`, a seventh question for `step_generalist`, a sabotaged diff proving it.
- Instructions: one "Plan close" section, `skills/pipeline.md` §7 reduced to a pointer, every refusal printing the next command and the escalation path.
- Acceptance: the eight findings replayed through `cp7`, the sabotage set in the testbed, ten recorded runs replayed for time; the recorded result gates EPIC 2.
- Removal (EPIC 2): reporter, simplifier as a step, curator, the plan-final (C3) contract of the auditor card and the audit half of `aid-c3-dispatch.sh` (the Codex transport and the P095 probe stay; `agents/auditor.md` itself stays because `/aid-audit` and `lib/aid-audit-independence.sh` read it), CP4 and CP5 code, the memory scanner's plan-final dispatch, the lens table of the plan-final review, the delivery-report template, their tests and registry rows, with a successor table (`defaults/policies/semantic-review.yaml` stays: the C2 wiring gate of the step advance reads it, `scripts/aid-fsm.sh:5754`); the same round and `decide` serve `legacy_epic_release_mode` at the EPIC boundary (2 of 29 manifests on disk use it).
- Hygiene rule B: every modified file leaves with English identifiers and comments, no dead code, a registry row and a breaking test per enforcement, a reuse check against `scripts/lib/`.

**Out of scope**
- The gate runner, gate profiles and test selection (`scripts/aid-run-gates.sh`, `aid-select-tests.sh`): only the reuse hook in `_pfsm_finalize_gates` changes; the next plan in the series rebuilds the gates.
- Generation, the test audit, the EPIC FSM beyond the legacy DONE hand-over named above.
- `plan-merge-to-main`, `plan-rollback`, `aid-release.sh`: unchanged.
- Compatibility with in-flight plans (P076, P080, P087 here; any in a consumer project): after the release they close through the new flow from `freeze`; old evidence stays on disk as history.
- Docusaurus documentation.
- Any change inside ACTA, WAN or Agents; their evidence is read-only input of the sample.

## Standards

| Standard | Why it binds | Deviation |
|---|---|---|
| `/ecosystem/specs/test-standard` | every new suite carries a tier from a measurement; moved cases are re-measured; Steps 1 to 12 | none |
| `/ecosystem/specs/ci-versioning-standard` | Step 13 releases 2.101.0 and edits both CHANGELOGs and the version registry | none |
| `/ecosystem/specs/documentation-placement` | agent-facing text in `commands/` and `skills/`, records in `docs/plans/` with `git add -f`; Steps 10, 11, 13 | none |
| `/ecosystem/specs/help-authoring-standard` | Step 10 rewrites the plan-close paragraph of `commands/aid-help.md` | none |
| `/ecosystem/specs/artifact-standard` | the PM page and card at plan close keep the seven-block skeleton; Step 7 | none |
| `/ecosystem/specs/llm-test-cost-control` | Step 11 replays findings through paid models; manual, ceiling written first | none |
| `/ecosystem/specs/backlog-standard` | Step 12 writes `IMP-` rows for what the triage defers | none |
| `/ecosystem/specs/claude-md-standard` | no `CLAUDE.md` changes; listed because the map binds it | none |

## Resources Verification

Checked in the repository at `main` 7d817b58 on 2026-09-20 (line numbers from `grep -n`); P095's changes are named where this plan builds on them:

- [x] Plan FSM: `_pfsm_next_plan_final_attempt` (scripts/aid-plan-fsm.sh:3982), `plan_final_invalidate` with its legality pre-check (:4016-4046), `_pfsm_finalize_sync` (:4069), `_pfsm_finalize_freeze` (:4211; run id at :4307), `_pfsm_finalize_gates` (:4689; same-candidate resume at :4718-4730), `_pfsm_finalize_gates_body` (:4807), `_pfsm_review_required_outputs` (:5168-5182), `_pfsm_finalize_accept_ancillary` (:5624; refusal text :5664), the drift detector's filtered status (:5886-5893) and conditional hint (:5857-5866), the receipt schema comment and inventory literal (:5977-6004), `_pfsm_finalize_review` (:6230), the simplifier `Head:` assertion (:6543-6546), the AC-lens assertion (:6561-6577), `_pfsm_finalize_c4` (:6811), `_pfsm_finalize_summary` (:6962), `cmd_plan_finalize` (:7051; usage :7095), `_pfsm_finalize_inputs` (:10265), `_pfsm_plan_has_patterns` (:4597).
- [x] Release policy: `_c3_gate_active` fail-closed (scripts/aid-release-policy.sh:341-364), `compute_reporter` (:446-461), `compute_simplifier` (:527), `run_verification_input` (:598), required inputs (:807 region), input enum (:216-217).
- [x] Evidence verify: `run_git_clean_check` (scripts/aid-evidence-verify.sh:203-223), the check list in `main` (:1055-1060), the TTL check among the required ones; P095 Step 5 changes `git_clean` to tracked-only and the pack lookup to `aid_state_root`.
- [x] Ancillary: `scripts/lib/aid-ancillary.sh` (`aid_ancillary_load` fail-closed :93-96, mandatory `--mode` :190, `_aid_ancillary_glob_match` :124, `aid_ancillary_filter_porcelain`), `defaults/policies/plan-final-policy.yaml` (`ancillary_paths` :43, `.aid-o/config/queue.yaml` :50, protected-over-ancillary rule :16-23).
- [x] Inventory sites: scripts/aid-plan-fsm.sh:5169-5181 and :5996, scripts/lib/aid-lifecycle.sh:201, `_check2_receipt_covers_candidate` (scripts/aid-plan-close-check.sh:376).
- [x] Round engine: checkpoint guard `^cp[236]$` (scripts/aid-review-round.sh:111), the block map (:117-119), packet call (:285), prompt render (:298), `_semantic_final_write` for cp3; block-to-toggle map (scripts/lib/aid-review-config.sh:33-48), known keys (:41); `aid_step_review_packet_build` requires `plan.json` and `step-check.json` (scripts/lib/aid-step-review-packet.sh:7-44); roles skill `skills/step-review-roles.md` (`step_generalist` questions :118-126); prompt template `defaults/prompts/review-prompt-v1.md`; finding schema `defaults/schemas/review-finding.schema.json`; semantic schema `defaults/schemas/semantic-review.schema.json` (lens not constrained to the policy vocabulary: WAN P101 final-9 carries an invented `merge_integrity`); `fsm_check_review_round` (scripts/aid-fsm.sh); `grep -rn cp7 scripts commands skills defaults` returns nothing, the name is free.
- [x] Risk profile: `scripts/aid-review-profile.sh:69` reads only the plugin's `defaults/policies/review-profiles.yaml` (17 globs with the `plugins/aid-orchestrator/` prefix, `unknown_surface_profile: unverifiable` at :3).
- [x] Delivery gate: `scripts/aid-delivery-gate.sh` (940 lines), 15 checks `scripts/lib/delivery-checks/dg01` to `dg12`, `dg15`, `dg17`, `dg18`, policy `defaults/policies/delivery-gate.yaml` (`enforcement: observe` :14), project override lookup at scripts/aid-plan-fsm.sh:10440-10442.
- [x] PM page: `scripts/aid-pm-brief.sh` (pure bash/jq, reads `release-decision.json`), `scripts/lib/aid-plan-close-summary.sh` (`aid_plan_close_render`), status recipes `review_line` and `epic_review_line` (commands/aid-status.md:464-481, :877).
- [x] Agents and text: `agents/reporter.md` (208), `agents/simplifier.md` (150), `agents/curator.md` (364), `agents/auditor.md` (1 315), `agents/project-scanner.md` (1 105); mentions of reporter or simplifier in `commands/aid-plan.md`, `commands/aid-run.md`, `skills/role-cards.md`, `skills/agent-protocol.md`, `agents/gate-fixer.md`, `skills/pipeline.md`; `skills/pipeline.md` §7 lines 1293-2635, §13 checkpoint table :2806-2894 (CP4 "revert on fail" :2823); role cards (skills/role-cards.md: backend :104, frontend :131, qa :168, security :278, docs-writer :328).
- [x] Registry: `defaults/enforcement-registry.yaml` planned rows at :381-387 (`delivery_report_present`, `delivery_report_test_evidence`, `simplifier_pass`, `delivery_report`, `reporter_focus_allowlist`, `reports_scope_allowed`, `delivery_report_template`), `deadline: "2026-09-30"` also at :1364 and :1467, `deadline: "2026-09-01"` at :400 and :413; guard `scripts/aid-registry-ttl-guard.sh` (`deferred_until` honoured, header :37-39).
- [x] Suites of the area (21): `scripts/tests/test-delivery-gate.sh`, `test-evidence-verify.sh`, `test-semantic-review.sh`, `release-policy-surface-check.sh`, and under `scripts/tests/bats/`: `test-aid-c3-dispatch`, `test-aid-plan-close-check`, `test-aid-plan-final-boundary`, `test-c3-activation`, `test-c3-advisory`, `test-c3-audit-prompt`, `test-c3-audit`, `test-c3-fix-loop`, `test-delivery-report`, `test-evidence-verify-tree`, `test-pipeline-c3-dispatch`, `test-plan-final-floor`, `test-plan-final-plan-source`, `test-pm-brief`, `test-release-policy-surface-check`, `test-release-policy`, `test-reporter-boundary`.
- [x] Sample: WAN and ACTA plan-final evidence (`/opt/eco/projects/wan/.aid-o/work/evidence/P*/R-P*final*`, `/opt/eco/projects/acta/...`); auditor high findings at WAN P078 final-6, P082 final-2, P101 final-2 and final-4 (two), ACTA P024 final-3 (two), one more to be chosen from the medium list when a commit is gone; release modes on disk: 27 manifests `plan_branch`, 2 `legacy_epic_release_mode`.
- [x] Environment and commands: `AID_PLUGIN_PATH`, `AID_PROJECT_ROOT`, `CODEX_MODEL`; `yq`, `jq`, `git`, `sha256sum`, `bats`; `codex` optional.
- [x] External: the testbed `/opt/eco/projects/aid-testbed/bin/verify.sh` and its fingerprint file under that repository's `expected/` directory (another repository), extended in Step 11.

## Approach

Chosen: **fix what is broken so the numbers mean something, build the new close beside the old one, prove it on the auditor's real findings, then remove.** EPIC 1 (Steps 1 to 11) defers the deadline, records the baseline, repairs the risk profile and the cleanliness check, adds `cp7`, gate reuse, the fix classes and `decide`, and measures; EPIC 2 (Steps 12 and 13) deletes and releases, only after Step 11's record says the new round confirmed at least what the auditor found.

Alternatives considered and rejected:
- *Delete by the numbers* (the author's first hypothesis: CP4, the quiet C2 lenses and the empty acceptance evidence go because they found nothing): refuted by the opponent with evidence. Three of those numbers measure bugs, not uselessness. The lenses are replaced by roles of a round whose profile input works, and CP4 disappears with the self-applied curator and auditor fixes it reviewed, not on its pass rate.
- *Keep the auditor's Codex bridge and only trim the rest*: two finding shapes, two evidence rules and two adjudications stay (V8 fails), and ACTA P024 showed the bridge dropping Codex's findings (P095 Step 4 patches the symptom).
- *A new release engine for C4*: the blocker is one unfiltered `git status` and one missing policy line; the aggregate is simplified, not reinvented.
- *Keep binary invalidation and make each attempt cheaper*: attempts would still number 4 to 11; the classes remove the cause.
- *Rebuild the PM page*: `aid-pm-brief.sh` already computes it from files; it gains time and cost and loses its reporter input.
- *Depend on the ponytail plugin for clean code*: a consumer project may not have it; its ladder goes into the role card in our own words and the step reviewer enforces it.

## Architecture

The end of a plan becomes five stages whose outputs are files bound to the candidate; every refusal names the next command.

```
plan-finalize <plan> --stage freeze [--accept-ancillary]
  merges the target into plan/<id> (today's sync), records candidate_sha, plan_base_commit, protected paths,
  run id R-<plan>-final-<N>, and gate_fingerprints {gate id -> sha256 over `git rev-parse <candidate>:<input path>`}
  fix after an earlier freeze: classify changed paths
     ancillary        -> equivalence receipt, nothing invalidated
     evidence-local   -> decide only
     delivery         -> gates by fingerprint; docs-only -> role final_claims alone; code -> the whole round
        │
--stage gates     gate fingerprint unchanged since attempt N-1 and green there -> row copied with reused_from
                  else run; writes gates_report.json, gates_rows/, plan-diff.json, execution-ledger.json
        │
--stage produce   review-profile.json (project override honoured), acceptance-evidence.json (P095: from plan-diff),
                  delivery-gate.json (blocking checks only), the cp7 packet, review-requirements.json
        │
aid-review-round.sh prepare|collect|close --checkpoint cp7 --evidence-dir <final run dir>
   roles final_criteria, final_claims, final_generalist (codex, stand-in claude) from skills/step-review-roles.md
   packet: diff.patch base..candidate, plan acceptance criteria, plan-diff.json, gates_report.json,
           open or carried findings of every EPIC's cp3, CHANGELOG and docs hunks
   adjudicator namespace final_review; close writes cp7/rounds.json, measurement.json and
   <run>/semantic-review-final.json (today's shape); open blocker -> the step's role fixes -> round 2 confirms
        │
--stage decide    inputs: gates_report, cp7 rounds (closed, at candidate), delivery-gate, acceptance-evidence,
                  generation-authority, obligations, verification report (ancillary-filtered git_clean)
                  writes release-decision.json, pm-decision-brief.json, pm-summary.md, plan-close page with
                  minutes and USD; seals receipt aid-plan-final-evidence-2
        ▼
PM card MERGE | FIX | ABORT  ->  plan-merge-to-main (unchanged)
```

## Data Model

**Gate fingerprints** (manifest field `gate_fingerprints`, written by `freeze`): `{<gate id>: {inputs: [<glob>], sha256: <hash of the sorted `path blob-sha` lines of the candidate tree matched by the gate's inputs>}}`; a gate's inputs come from `execution.yaml` (`inputs:` on the gate row; a gate without declared inputs fingerprints the whole tree, so it is reused only when nothing changed). A reused row in `gates_report.json` carries `reused_from: "R-<plan>-final-<N>"` and the original timestamps.

**Fix classes** (`<run dir>/fix-class.json`, written by `freeze` on any freeze after the first): `{previous_candidate, candidate, changed_paths: [], class: ancillary|evidence_local|delivery, docs_only: bool, invalidated: [gates:<ids>|round:<roles>|decide], carried: [gates:<ids>|round:<roles>]}`. The classifier reads the git range only, and the run directory is not in it (`.aid-o/` is gitignored in consumer projects), so there are two classes: `ancillary` requires every path to match `plan_final.ancillary_paths` and none to be protected; anything else is `delivery`. The run directory's integrity is a separate mechanism: every stage appends `{path, sha256, stage, at}` for each file it writes to `<run dir>/stage-writes.jsonl`, and `decide` refuses as tampering, naming the file, any decision input (`cp7/**`, `semantic-review-final.json`, `gates_report.json`, `gates_rows/**`, `acceptance-evidence.json`, `review-profile.json`, `delivery-gate.json`, `plan-diff.json`) whose digest differs from the last write a stage recorded for it; a file rewritten by `gates`, `produce` or `close` during the attempt is a recorded write and therefore normal output. PM-facing outputs are re-rendered by `decide` and need no class. For a `delivery` change `fix-class.json` records per path which packet part it feeds (`feeds: [criteria|claims|diff|gates]`): the plan file and anything else that feeds `criteria.md` re-runs `final_criteria`, CHANGELOG, README and docs hunks re-run `final_claims`, a code path re-runs the whole round, a path inside a gate's `inputs` re-runs that gate. The ancestry check (the previous candidate is an ancestor of the new one) and the receipt-hash check stay absolute.

**Reviewer block** (`defaults/policies/review-checkpoints.yaml`):

```yaml
final_review:
  rounds_default: 2
  stand_in_model: sonnet
  banned_models: [haiku, gpt-5-mini, gpt-4o-mini]
  reviewers:
    - {role: final_criteria,   provider: claude, model: opus}
    - {role: final_claims,     provider: claude, model: sonnet}
    - {role: final_generalist, provider: codex,  model: gpt-5.6-terra}
```

Toggle `cp7_plan_final_review` (default true). Roles in `skills/step-review-roles.md`: `final_criteria` (for every acceptance criterion of the plan: which executed test or gate row proves it, by `path:line` and the `plan-diff.json` result; stop rule: a criterion with no executed proof is a blocker), `final_claims` (every behavioural claim in the CHANGELOG, README and docs hunks of the range against the code at the candidate; a binding instruction that lives only outside the delivered files; a plan type that the diff contradicts; stop rule: a false claim is a blocker), `final_generalist` (the range as a colleague from another provider reads it: consumers broken across EPICs, anything the per-EPIC cp3 rounds could not see because it spans them). Finding shape, evidence rule, fingerprints and `merged.json` are the engine's; namespace `final_review`, third fingerprint argument `plan`.

**Risk profile** (`review-profile.json`): policy file resolved as `.aid-o/config/policies/review-profiles.yaml` when present, else the plugin default; default surface globs lose the repository prefix and gain generic ones (`**/migrations/**`, `**/auth/**`, `**/*.sql`, dependency manifests, CI workflows); an override may add surfaces or raise a level, and `review-profile.json` records `default_verdict`, `override_verdict` and `effective` = the stricter of the two, so a project cannot lower its own review; the two schemas keep a name pattern for `lens` and `role`, and the run-dependent rule is enforced in code: `collect` refuses a reviewer `role` outside the round's `reviewers_expected`, and the semantic-file validator of `close` refuses a `semantic_review.findings[].lens` or a `lenses_run[]` entry outside `reviewers_expected` plus the writer's own literal `step_check` (the fallback `_semantic_final_write` emits for a finding of the deterministic step check, `aid-review-round.sh:493`).

**Decision** (`release-decision.json`, same artifact type, inputs reduced): `gates_report`, `final_review` (cp7 `rounds.json`: closed, `head_sha == candidate_sha`, no open blocker unless carried with a PM-accepted dispute; the toggle `cp7_plan_final_review: false` is honoured only as it stood at `plan_base_commit` (`git show <base>:<policy file>`), so a plan cannot switch off its own review; even then the input is `blocked` with reason `final_review_disabled` unless a waiver exists, written only by `plan-finalize --stage decide --waive-final-review --reason "<the PM's words>"`, which binds it to the current `candidate_sha`, logs it to the timeline and the cross-plan audit log like `--force`, and is shown on the PM card and in `/aid-status`; a waiver file without its audit-log entry, or for another candidate, is refused), `delivery_gate` (blocking checks), `acceptance_evidence`, `plan_review` (from `generation-authority.json`, unchanged), `obligations`, `verification_report`. `plan_summary` gains `close: {attempts, minutes, usd, usd_unknown_roles}`. Receipt `schema_version: "aid-plan-final-evidence-2"` with inventory `acceptance-evidence.json, delivery-gate.json, gates_report.json, plan-diff.json, review-profile.json, semantic-review-final.json, cp7/rounds.json, release-decision.json`; a receipt of version 1 is refused by the close check with the command to re-close.

**Registry deferral** (Step 1): the seven reporter and simplifier rows gain `deferred_until: "2026-10-31"`, `deferred_by: "P096"` and `deferred_reason: "P096 removes this mechanism"` (the registry's documented fields, header lines 38-41); Step 12 sets them `status: removed_scoped` with `replacement_guard:` and a row in `reference/review-successors.md`, the vocabulary `test-review-successors.sh` already selects. The two P068-line rows gain `deferred_until: "2026-12-31"`, `deferred_by: "PM 2026-09-20"` and `deferred_reason: "owned by the P068 line; re-dated so the TTL guard does not break plan-final in consumer projects; out of P096 scope"` and keep `status: planned`.

## Implementation Steps

**EPIC 1: Steps 1-11 — Repair what the numbers hid, build the new close beside the old one, prove it**

### Step 1: Deadline deferred, baseline and replay sample recorded

**Objective:** The TTL guard cannot break plan-final on 2026-10-01; the numbers this plan is judged against and the eight real findings are in tracked files before anything changes.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (lines ~381-387) — the seven reporter and simplifier rows at 381-387 gain `deferred_until: "2026-10-31"`, `deferred_by` and `deferred_reason`; the blocks `plan_queue_scripted_transitions` (~1355) and `plan_final_required_gates_record` (~1458) gain `deferred_until: "2026-12-31"` with the P068-line reason of the Data Model; new row `ttl_guard_date_override_test_only`.
- Modify: `plugins/aid-orchestrator/scripts/aid-registry-ttl-guard.sh` (lines ~30-40) — `TODAY` is the system date; `AID_TTL_TODAY` is honoured only together with `AID_TEST_MODE=1` (the suites' existing marker), is refused when it is not an ISO date, and is ignored with a warning otherwise, so a production run of the evidence verifier cannot be handed a past date.
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/plan-final/baseline.json` — per project: attempts per plan, minutes per attempt (median, p90), first-to-last hours, C4 verdicts, the counts of the Context, the area's line count by file, measured by the script below on 2026-09-20.
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/plan-final/sample.json` — eight entries `{id, project, plan, run, base_sha, candidate_sha, finding: {severity, claim, evidence}, source: audit-report.json}`, only entries whose two commits resolve in the source repository.
- Create: `plugins/aid-orchestrator/scripts/tests/plan-final-measure.sh` — the measurement as a repeatable read-only script over `<projects root>/*/.aid-o/work/evidence/P*/R-P*final*` (attempts, minutes from file mtimes, artifact verdict tallies) with `--as-of <ISO date>` counting only runs whose newest file is at or before the cut-off, printing the JSON of `baseline.json`, which records the cut-off it was taken at.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-registry-ttl.bats` — with `AID_TTL_TODAY=2026-10-01` the guard exits 0 on the shipped registry; on a copy with the deferral removed from one row it exits 1 naming the row; on a fixture copy of this step's registry with `AID_TTL_TODAY=2026-11-01` it exits 1 (the deferral is a date, not an exemption; a fixture, so the case stays true after Step 12 removes the rows); a malformed override is refused; the override without `AID_TEST_MODE=1` is ignored with a warning.

**Reuse check:** searched: `grep -rln 'R-P.*final' plugins/aid-orchestrator/scripts/tests` → several matching (`test-aid-plan-final-boundary.bats`, `test-plan-final-floor.bats` build fixture runs) — they seed fixtures, none reads real evidence trees; the P094 sample script `scripts/tests/test-step-review-acceptance.sh` replays diffs at a sha in another repository and its materialising code is the pattern copied for Step 11, not for this read-only measurement.

**Parallel group:** ---

**Architecture Context:** Quality first needs a baseline that exists before the change, and the deadline is removed as a risk before any design work.

**Implementation Detail:** `plan-final-measure.sh` takes `--projects-root` and never writes outside stdout; `baseline.json` records the command and the date. `sample.json` stores shas and the finding text only; the diffs are materialised at replay time from the source repository.

**Error Handling:** A project without plan-final runs is listed with zero counts, not skipped silently.

**Edge Cases:**
- A reviewed commit was garbage-collected in the source repository: the entry is dropped and the next medium finding of the same kind takes its place; the record says so.
- A run directory with no files (seven in WAN): counted as an attempt with zero minutes.
- The guard's date is taken from `AID_TTL_TODAY` when set (test only); unset, it is the system date.

**Dependencies:**
- Depends on: none
- Blocks: Step 2, Step 3, Step 4, Step 11

**Acceptance Criteria:**
- [ ] `AID_TEST_MODE=1 AID_TTL_TODAY=2026-10-01 bash plugins/aid-orchestrator/scripts/aid-registry-ttl-guard.sh` exits 0 on the shipped registry.
- [ ] Review finding "The round-2 fix pins the nine deferred rows" is answered: only the seven rows at 381-387 carry the P096 reason; `plan_queue_scripted_transitions` and `plan_final_required_gates_record` carry their own reason, stay `planned`, and appear in no removal list of Step 12.
- [ ] `baseline.json` and `sample.json` exist, `sample.json` has eight entries whose `base_sha` and `candidate_sha` resolve (`git -C <project> cat-file -e`).
- [ ] `plan-final-measure.sh --projects-root /opt/eco/projects --as-of <the cut-off recorded in baseline.json>` reproduces the attempts-per-plan arrays of `baseline.json`.

**Effort:** M
**AID Role:** backend

### Step 2: The risk profile resolves in a consumer project; an invented lens or role is refused

**Objective:** `review-profile.json` names real surfaces and a real risk level in a project that is not this repository, and no artifact can carry a lens or role name nobody defined.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-review-profile.sh` (lines ~60-110) — the plugin default is always evaluated; `.aid-o/config/policies/review-profiles.yaml` under the state root, when it exists and parses, is evaluated too and may only add surfaces or raise the level; the report records `default_verdict`, `override_verdict`, `effective` (the stricter) and which files were read.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-config.sh` (lines ~55-70) — the inline project-first lookup becomes `aid_policy_file <root> <basename> [<yq probe>]`: the project file is chosen only when it exists and the optional probe (for the config loader `.review_checkpoints.<block>`, exactly today's `yq -e` test at lines 62-68) succeeds, else the default with today's warning text, so the loader's behaviour for an override lacking the block is unchanged; used by the config loader and by `aid-review-profile.sh` (probe `.profiles`); the other inline copies of the pattern (`aid-fsm.sh:1270`, `aid-step-check.sh:197`, `lib/aid-ancillary.sh:62`, `lib/aid-recovery-ladder.sh:308`) are left and get one backlog row in Step 12.
- Modify: `plugins/aid-orchestrator/scripts/aid-review-round.sh` (lines ~317-410, 490-505) — `collect` marks an answer whose `role` is not in the round's `reviewers_expected` invalid with `unknown_role`; the semantic-file validator of `close` rejects a `semantic_review.findings[].lens` or `lenses_run[]` entry outside that list plus the literal `step_check`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-round.bats` — an answer with a role outside `reviewers_expected` is invalid with `unknown_role`; a semantic file with `lens: merge_integrity` is refused by `close`; the file `_semantic_final_write` itself produces for a cp3 fixture (with a `step_check` finding) is accepted.
- Modify: `plugins/aid-orchestrator/defaults/policies/review-profiles.yaml` — the 17 surface globs lose the `plugins/aid-orchestrator/` prefix where they describe a kind of file (scripts, schemas, policies) and generic surfaces are added (migrations, auth, SQL, dependency manifests, CI workflows); this repository's own paths move to `.aid-o/config/policies/review-profiles.yaml` of this repository.
- Create: `.aid-o/config/policies/review-profiles.yaml` — this repository's own surfaces (state machines, gate runner, generation chain, release boundary), so the plugin default stops describing one project; `.aid-o/config` is gitignored here, so the file is committed with `git add -f` and CI sees it.
- Modify: `plugins/aid-orchestrator/defaults/schemas/semantic-review.schema.json` + `plugins/aid-orchestrator/defaults/schemas/review-finding.schema.json` — `lens` and `role` carry the name pattern `[a-z][a-z0-9_]*` as documentation of the shape; the enforcement is the code named above, because nothing evaluates these files as JSON Schema (the validator is the jq check at `aid-review-round.sh:496-502`).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `review_profile_override_never_lowers`, `review_role_name_known`.
- Test: `plugins/aid-orchestrator/scripts/tests/test-review-profile.sh` — a fixture project with a `src/auth/login.py` change resolves to a named surface and a level other than `unverifiable`; a project override adds a surface and raises the level; an override that would lower the level leaves `effective` at the default's and records both; an unparseable override falls back to the default with a warning and exit 0; a change matching nothing keeps `unverifiable` (fail-closed direction unchanged).

**Reuse check:** searched: `grep -rn 'config/policies' plugins/aid-orchestrator/scripts` → several matching (at least six inline copies: `aid-plan-fsm.sh:10440-10442`, `lib/aid-review-config.sh:62`, `aid-fsm.sh:1270`, `aid-step-check.sh:197`, `lib/aid-ancillary.sh:62`, `lib/aid-recovery-ladder.sh:308`) — no reusable function exists, every copy is inline and hard-wired to its own file name; this step founds `aid_policy_file` by extracting the copy in `aid-review-config.sh` and converts the two call sites it touches, rather than adding a seventh copy.

**Parallel group:** ---

**Architecture Context:** The round of Step 4 arms `final_generalist` and sizes its packet from the profile; a profile that says `unverifiable` for every consumer makes every plan the most expensive case.

**Implementation Detail:** `_c3_gate_active`'s fail-closed resolution is untouched; what changes is that the strict answer stops being the only answer.

**Error Handling:** An override file that names a profile level the policy does not define is refused with the list of valid levels.

**Edge Cases:**
- A docs-only range: level `docs`, surfaces empty, not `unverifiable`.
- A consumer project with its own `plugins/` directory: no default glob matches it by accident any more.
- A reviewer answer naming a role outside the run's expected list: `collect` marks the file invalid with `unknown_role`.

**Dependencies:**
- Depends on: Step 1
- Blocks: Step 4, Step 6

**Acceptance Criteria:**
- [ ] The five new `test-review-profile.sh` cases pass.
- [ ] Replaying `aid-review-profile.sh` over three WAN ranges from `sample.json` gives a level other than `unverifiable` for each.
- [ ] In `test-review-round.bats` a reviewer answer with a role outside `reviewers_expected` is invalid with `unknown_role`, and a semantic file with `lens: merge_integrity` is refused by `close`.
- [ ] Review finding "The new close-path rule (refuse a `lenses[].lens` outside" is answered: the rule names the real fields `semantic_review.findings[].lens` and `lenses_run[]`, accepts `step_check`, and the writer's own cp3 output passes the validator in the suite.

**Effort:** M
**AID Role:** backend

### Step 3: A verification that can pass — ancillary-filtered cleanliness and the counter among ancillary paths

**Objective:** On a healthy plan under `plan_branch` the verification report passes without a waiver, and a tree that is dirty for a real reason still fails.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-evidence-verify.sh` (lines ~203-223) — `run_git_clean_check` sources `lib/aid-ancillary.sh` and pipes the tracked-only status (P095) through `aid_ancillary_filter_porcelain --mode policy --project-root <state root>`, the one mode that reads `plan_final.ancillary_paths` (`lib/aid-ancillary.sh:190` accepts `legacy5|legacy4|policy`); every filtered path is then intersected with the manifest's `protected_paths`, and a protected path fails the check whatever glob matched it (the filter itself knows nothing about the protected set, so this intersection is the "protected wins" mechanism); the evidence lists what was filtered, which policy file was read and whether it differed from the shipped default.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-ancillary.sh` (lines ~25-100) — `.aid-o/config/counter.yaml` joins the strict fallback list `_AID_ANCILLARY_LEGACY5` beside `queue.yaml` (the plan FSM's drift-detector fallback and `_pfsm_check_clean_worktree` at `aid-plan-fsm.sh:313` both use that list and stay on it: the detector's primary branch already classifies through the policy with `aid_ancillary_match`, and the strict list is its deliberate fallback for a manifest without a complete protected set); `aid_ancillary_load` refuses a project `ancillary_paths` entry that is neither in the shipped default nor under `.aid-o/`, naming it, so a project cannot declare its own delivery paths ancillary.
- Modify: `plugins/aid-orchestrator/defaults/policies/plan-final-policy.yaml` (lines ~43-58) — `.aid-o/config/counter.yaml` joins `ancillary_paths` beside `queue.yaml`, with the comment why (AID writes it during every allocation).
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/plan-final/sabotage/README.md` — the four fixture plans of the sabotage set (healthy, open blocker, red gate, unsettled obligation) described with the verdict each must get; the fixtures themselves are built by the suite from this description.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `verify_git_clean_ancillary_filtered`, `ancillary_policy_cannot_widen`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-evidence-verify-tree.bats` — a tree with a modified `.aid-o/config/counter.yaml` and an untracked runtime directory passes `git_clean`, is not reported as drift by the plan FSM's detector and does not stop `freeze` at `_pfsm_check_clean_worktree` (three call sites, one fixture); a project policy that lists `src/**` as ancillary is refused at load naming the entry; a tree with a modified tracked source file fails it; a protected path that also matches an ancillary glob still fails (protected wins).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats` — on the healthy fixture `verification_report` is `pass` and is not among the blockers.

**Reuse check:** searched: `grep -n 'aid_ancillary_filter_porcelain' plugins/aid-orchestrator/scripts/*.sh plugins/aid-orchestrator/scripts/lib/*.sh` → several matching (`lib/aid-ancillary.sh` defines it, `aid-plan-fsm.sh:5886-5893` uses it) — reused as is; deliberately defective fixtures with expected refusals already exist in the testbed (`/opt/eco/projects/aid-testbed/fixtures/plan-sabotaged.md` and its fingerprint file) for the installed plugin, and Step 11 extends them; the four plan-final fixtures of this step live in the plugin suite because they are built by bats from a fixture repository on every run and must block a merge, which the testbed (run after release) cannot; the README names the testbed cases that mirror them so the two surfaces do not drift.

**Parallel group:** ---

**Architecture Context:** One definition of "clean" for the whole boundary; the 112 waivers exist because two definitions disagreed.

**Implementation Detail:** The filter's mandatory `--mode` keeps the verifier from inheriting a wider exception set; `aid_ancillary_load`'s fail-closed fallback means an unparseable policy narrows, never widens.

**Error Handling:** `aid-ancillary.sh` missing or unloadable: the check is `unverifiable` with the reason, as today for a failing `git status`.

**Edge Cases:**
- A project that removed `counter.yaml` from its own policy override: its tree fails honestly and the message names the file.
- `.aid-o/work/**` matched as ancillary while holding close-consumed evidence: protected-over-ancillary keeps it protected.
- Run from a plan worktree: the tree judged is `--tree`, the policy comes from the state root (P095 rule).

**Dependencies:**
- Depends on: Step 1
- Blocks: Step 7

**Acceptance Criteria:**
- [ ] The four new cases pass in their suites' tiers.
- [ ] On the healthy sabotage fixture `aid-release-policy.sh` reports no `verification_report` blocker.
- [ ] `grep -n 'git status --porcelain' plugins/aid-orchestrator/scripts/aid-evidence-verify.sh` shows the filtered pipeline only, and `grep -c 'counter.yaml' plugins/aid-orchestrator/scripts/lib/aid-ancillary.sh` is at least 1.
- [ ] Review finding "Step 3 routes the cleanliness check and the" is answered: a project `plan-final-policy.yaml` naming a path outside `.aid-o/` that the shipped default does not list is refused by `aid_ancillary_load` with the entry named, and the suite has the case.

**Effort:** S
**AID Role:** backend

### Step 4: Checkpoint cp7 — one round that reads the whole plan

**Objective:** `aid-review-round.sh --checkpoint cp7` prepares, collects and closes a round over `plan_base_commit..candidate_sha` with three roles, writes the semantic file the boundary already reads, and the FSM can require it.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-review-round.sh` (lines ~105-130, 280-300) — `cp7` accepted: base `<final run dir>/cp7`, namespace `final_review`, block `final_review`; `prepare` needs `<run dir>/gates_report.json` and the manifest's `candidate_sha` equal to the tree's HEAD instead of a `step-check.json`; `close` writes `<run dir>/semantic-review-final.json` through `_semantic_final_write`, which is parameterised in this step: today it reads the range from `step-check.json` and the base from `fsm-state.yaml` and hard-codes `generated_by: "… close cp3"` (`aid-review-round.sh:476-489`); it takes `<base> <head> <checkpoint>` as arguments, cp3 passes what it read before (regression case), cp7 passes `plan_base_commit` and `candidate_sha` from the plan-final manifest.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-config.sh` (lines ~33-48) — block `final_review` with toggle `cp7_plan_final_review`.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-step-review-packet.sh` — `aid_final_review_packet_build <root> <round_dir> <run_dir> <plan_file> <base> <candidate> [<prev_round_dir>]`: `diff.patch`, `criteria.md` (the plan's acceptance criteria and success criteria), `plan-diff.json`, `gates_report.json`, `epic-findings.json` (open, carried or routed findings of every contributing EPIC's cp3), `claims.patch` (CHANGELOG, README and docs hunks), `manifest.json`; no `plan.json` needed.
- Modify: `plugins/aid-orchestrator/skills/step-review-roles.md` — roles `final_criteria`, `final_claims`, `final_generalist` with questions and stop rules as in the Data Model.
- Modify: `plugins/aid-orchestrator/defaults/prompts/review-prompt-v1.md` — the `cp7` block (what the packet holds, where the answer goes).
- Modify: `plugins/aid-orchestrator/defaults/policies/review-checkpoints.yaml` — the `final_review` block and the toggle.
- Modify: `plugins/aid-orchestrator/scripts/aid-review-adjudicate.sh` — namespace `final_review`, third fingerprint argument `plan`.
- Modify: `plugins/aid-orchestrator/scripts/aid-emit-dispatch.sh` (lines ~25-35) — `AID_DISPATCH_FOCUS_RE` at line 30 gains `cp7-[a-z][a-z0-9-]*`, with the comment that enumerates the allowed foci.
- Modify: `plugins/aid-orchestrator/defaults/schemas/review-finding.schema.json` (line ~33) — the `checkpoint` enum gains `cp7`.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — `fsm_check_review_round` accepts `cp7` with the final run directory (used by the plan FSM in Step 7).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `final_review_round_required`, `final_review_head_bound`, `final_review_semantic_file`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-round.bats` — in a fixture project with no `plan.json` anywhere, `prepare`, stub answers, `collect` and `close` at `cp7` give a closed `rounds.json` and a schema-valid `semantic-review-final.json` with `range` equal to base..candidate; `prepare` refuses when HEAD is not the candidate; `close` refuses a reviewer file without a dispatch bracket; a confirmation round carries the open findings and the fix diff; a cp7 finding validates against the finding schema; a cp3 close still writes the same semantic file as before the parameterisation.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-config.bats` — the `final_review` block loads, the toggle switches it off, a banned model is refused.

**Reuse check:** searched: `grep -n -e '_semantic_final_write' -e 'aid_step_review_packet_build' plugins/aid-orchestrator/scripts/aid-review-round.sh plugins/aid-orchestrator/scripts/lib/aid-step-review-packet.sh` → several matching — the semantic-file writer is reused but not unchanged: it is bound to cp3 inputs and is parameterised here; the step packet builder requires `plan.json` and `step-check.json` (`aid-step-review-packet.sh:31-44`), which a plan-final range has not, so a second builder function is founded in the same library rather than a new file.

**Parallel group:** ---

**Architecture Context:** The fourth checkpoint on the one engine: same finding shape, evidence rule, adjudicator, measurement, stand-in and fix paragraph as CP1, CP2, CP3 and CP6.

**Implementation Detail:** `epic-findings.json` tells the roles what the per-EPIC rounds already judged so that they do not repeat it; the role texts say to read across EPICs. The fix goes to the role of the step that owns the file (`git log` on the path → the step's commit trailer → its role card); a finding in a file no step owns goes to `backend`.

**Error Handling:** A contributing EPIC without cp3 evidence (closed before 2.99.0): listed in `manifest.json` as `cp3: absent`; the round runs and `final_generalist` is told the EPIC was not reviewed as a whole.

**Edge Cases:**
- A range of more than 400 files: `diff.patch` is split per EPIC and the prompt names the parts; nothing is truncated silently.
- `cp7_plan_final_review: false`: `prepare` exits 3 and `decide` blocks with `final_review_disabled` unless the PM's waiver is recorded (Step 7).
- A docs-only fix after a closed round: `prepare --round N+1 --only final_claims` (the fix class decides, Step 6).
- Codex over its limit: the P095 stand-in answers `final_generalist`; the record says so.

**Dependencies:**
- Depends on: Step 1, Step 2
- Blocks: Step 6, Step 7, Step 11

**Acceptance Criteria:**
- [ ] The cp7 cases pass; the suite's case count grows by at least six.
- [ ] `aid-review-round.sh prepare --checkpoint cp7` in the fixture prints three prompts with foci `cp7-final-criteria`, `cp7-final-claims`, `cp7-final-generalist`.
- [ ] `semantic-review-final.json` written by a cp7 `close` validates against `semantic-review.schema.json` and names only the run's roles as lenses.
- [ ] `fsm_check_review_round <run dir> cp7` returns 0 on the closed passing fixture round and 1 with a next command on a missing one.

**Effort:** L
**AID Role:** backend

### Step 5: Gates reused across attempts by input fingerprint

**Objective:** A gate whose declared inputs did not change since the previous attempt, and which was green there, is copied forward instead of executed.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~4211-4320, 4689-4830) — `freeze` writes `gate_fingerprints`; `_pfsm_finalize_gates_body` looks up the previous attempt's `gates_report.json` and fingerprints, copies a green row with `reused_from`, executes the rest, and logs `gate_reused` events.
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` — optional `inputs:` glob list on a gate row, documented; absent means the whole tree.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — row `plan_final_gate_reuse_fingerprinted`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — attempt 2 after a docs-only fix reuses the `tests_pass` row (its `inputs` exclude docs) and re-runs `docs_updated`; a red row is never reused; a gate without `inputs` is reused only when the tree is byte-identical; a reused row whose source run directory vanished is executed.

**Reuse check:** searched: `grep -n -e 'fingerprint' -e 'reused' plugins/aid-orchestrator/scripts/aid-plan-fsm.sh plugins/aid-orchestrator/scripts/aid-run-gates.sh` → several matching in `aid-run-gates.sh` (`.gate_row_key`, the per-row resume key of one run) — the row key identifies a row within one run and is reused as the row identity; what is founded is the comparison across attempts, which nothing does today.

**Parallel group:** ---

**Architecture Context:** The opponent's highest-value single change for the 15-minute goal: WAN P101 paid 2 to 4 minutes of gates on each of eleven attempts over an unchanged tree.

**Implementation Detail:** The fingerprint is over blob shas of the candidate tree, so it needs no checkout and cannot be fooled by mtimes. The gate runner itself is not modified; the plan FSM decides which gate ids to pass it.

**Error Handling:** A previous report that fails its own `_generated_by` binding is ignored and every gate runs.

**Edge Cases:**
- A gate that was skipped with a waiver in attempt N-1: not reusable; it runs.
- The gate profile changed between attempts (risk floor raised): rows of gates not in the old profile run; the rest follow the fingerprint rule.
- `--substitute-receipt` on a reused gate: refused, the receipt belongs to an executed gate.

**Dependencies:**
- Depends on: none
- Blocks: Step 6, Step 11

**Acceptance Criteria:**
- [ ] The four reuse cases pass.
- [ ] A fixture second attempt after a docs-only fix executes strictly fewer gates than the first and its `gates_report.json` validates as today.
- [ ] `grep -c 'reused_from' <fixture gates_report.json>` equals the number of copied rows and each names an existing run directory.

**Effort:** M
**AID Role:** backend

### Step 6: A fix after the freeze invalidates only what depends on it; sync folds into freeze

**Objective:** `freeze` classifies what changed since the previous candidate and keeps every result the change cannot have affected; `sync` and `accept-ancillary` stop being stages.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~4016-4320, 5624-5900, 7051-7110) — `freeze` performs today's `sync` first; on a second or later freeze it writes `fix-class.json` and clears only the invalidated results (`plan_final_invalidate` gains a scope argument and keeps its legality pre-check and write order); `--accept-ancillary` is a flag of `freeze` producing today's equivalence receipt; the stages `sync` and `accept-ancillary` print the new command and exit 2; the drift detector's conditional hint names the new flag.
- Modify: `plugins/aid-orchestrator/scripts/aid-review-round.sh` — `prepare --round N+1 --carry <roles>` marks carried roles `carried_from` in `round.json`, and `collect` counts them as answered with their previous findings; `close` at cp7 appends its writes to `stage-writes.jsonl`.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `plan_final_fix_class`, `plan_final_ancestry_absolute`, `plan_final_stage_writes_digest`; the `sync`-stage rows retired with successors.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — an ancillary-only change keeps gates, round and decision and writes the receipt; a docs-only change to CHANGELOG or README keeps gates by fingerprint, carries `final_criteria` and `final_generalist`, re-runs `final_claims`; a change to the plan file's acceptance criteria re-runs `final_criteria` as well; a code change re-runs the round; running `gates` twice in one attempt and freezing again is accepted (both writes are in `stage-writes.jsonl`); a hand-edited `gates_report.json` or `cp7/round-1/reviewer-final_criteria.json` makes `decide` refuse with the file named; a rewritten branch (candidate not an ancestor) is refused whatever the class; a vanished receipt keeps no review alive.

**Reuse check:** searched: `grep -n -e 'aid_ancillary_filter_porcelain' -e '_pfsm_finalize_accept_ancillary' plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` → several matching — the ancillary predicate and the equivalence receipt exist and are reused; only the binary invalidation around them is replaced.

**Parallel group:** ---

**Architecture Context:** The cause of 4 to 11 attempts. Two guards are not softened: ancestry and the receipt hash.

**Implementation Detail:** Each attempt keeps its own run directory; carrying forward copies with provenance (`carried_from`, `reused_from`) and never writes into a sealed directory.

**Error Handling:** A change set the classifier cannot read (submodule, mode-only change): class `delivery`, everything downstream re-runs, and the reason is written.

**Edge Cases:**
- A fix touching both docs and code: `delivery`, `docs_only: false`.
- A fix that only deletes a file under `.aid-o/work/` that is protected: protected wins, class `delivery`.
- Two fixes between freezes: the class is computed over the whole range previous candidate to new candidate.

**Dependencies:**
- Depends on: Step 2, Step 4, Step 5
- Blocks: Step 7, Step 10

**Acceptance Criteria:**
- [ ] The class cases pass, including the plan-file edit, the double `gates` run and the hand-edited sealed file.
- [ ] Review finding "The new tamper refusal and the narrowed `evidence_local`" is answered: the classifier reads only the git range, the `evidence_local` class is gone, and run-directory integrity is decided from `stage-writes.jsonl` digests at `decide`.
- [ ] Review finding "The new tamper rule refuses any change to" is answered: a file rewritten by a stage during the attempt is a recorded write and passes; only a digest no stage recorded is refused, and the suite has both cases.
- [ ] `plan-finalize <plan> --stage sync` exits 2 printing `plan-finalize <plan> --stage freeze`.
- [ ] After a docs-only fix in the fixture the second attempt dispatches one role (from `round.json` `reviewers_expected` minus `carried_from`).
- [ ] `plan_final_invalidate` still refuses an illegal target state before writing anything (the existing case stays green).

**Effort:** L
**AID Role:** backend

### Step 7: Stage decide — one aggregate, a receipt of version 2, time and cost on the PM page

**Objective:** `plan-finalize --stage decide` replaces `c4` and `summary`, reads the reduced input set, can say yes, seals the version-2 receipt, and the PM page shows attempts, minutes and USD.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~5168-5182, 5977-6030, 6230-7050) — stage `decide` (the bodies of `_pfsm_finalize_c4` and `_pfsm_finalize_summary` merged); `_pfsm_review_required_outputs` and the receipt literal carry the version-2 inventory; `review` as a stage name prints the round commands of Step 4 and exits 2; `produce` replaces `inputs` (same body plus the cp7 packet call); `c4` and `summary` print the new command.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` + `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh` — the version-2 inventory (lifecycle line ~201, close check lines ~376-420); a version-1 receipt is refused with `re-close with: plan-finalize <plan> --stage freeze`.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines ~200-220, 446-600, 800-940) — inputs `final_review` (cp7 `rounds.json`) and `obligations` added; `compute_reporter`, `compute_simplifier`, the curator, audit-report and dispatch-record inputs stop being required in plan mode and in `legacy_epic_release_mode` (where the EPIC boundary passes its own cp7 round over `base_commit..HEAD`); `plan_summary.close` filled from the run directories and `aid_review_summary`.
- Modify: `plugins/aid-orchestrator/scripts/aid-pm-brief.sh` + `plugins/aid-orchestrator/scripts/lib/aid-plan-close-summary.sh` — the tile and the card line "Uzavření: N pokusů, M min, X USD"; no reporter field read.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-summary.sh` (lines ~10-130) — a cp7 arm: the run-level summary walks `<final run dir>/cp7/round-*/measurement.json` beside cp1, cp2, cp3 and cp6.
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` (lines ~464-490) — recipe `final_review_line <plan_id>`.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `plan_final_decide_inputs`, `plan_final_receipt_v2`, `plan_final_cost_visible`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats` — the four sabotage fixtures: healthy → `release_ready: true`, `merge_mode` not `blocked`, no reporter file present; open cp7 blocker → false naming the finding; red gate → false naming the gate; open `release_blocker` obligation → false naming it; `cp7_plan_final_review: false` at the plan's base → false with blocker `final_review_disabled`; the toggle flipped inside the plan's own range is ignored and the round is required; true only after `--waive-final-review --reason` for this candidate, with the audit-log entry present; a hand-written waiver file, or one for another candidate, is refused.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-close-check.bats` — a version-1 receipt is refused with the re-close command; a version-2 receipt missing `cp7/rounds.json` is refused as a short pack.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-pm-brief.bats` — the numbers on the page equal the source JSON (attempts from run directories, USD from `measurement.json`), and the renderer runs with no model dispatch.

**Reuse check:** searched: `grep -n -e 'aid_review_summary' -e 'plan_summary' plugins/aid-orchestrator/scripts/aid-release-policy.sh plugins/aid-orchestrator/scripts/aid-pm-brief.sh plugins/aid-orchestrator/scripts/lib/aid-review-summary.sh` → several matching — the summary library already prices a round and `plan_summary` already feeds the page; both are reused, nothing is founded.

**Parallel group:** ---

**Architecture Context:** The receipt's inventory is part of its schema version's contract (the comment at `aid-plan-fsm.sh:5977-5990`), so the list changes by minting version 2 in all three sites at once.

**Implementation Detail:** `decide` runs the evidence verifier with `--candidate` (P095) and the filtered `git_clean` (Step 3). The old stage names stay as refusals for one release so that an agent following old text is told what to run.

**Error Handling:** `decide` before a closed cp7 round: refusal with the three round commands; with the round switched off by the toggle: the decision is `release_ready: false` with blocker `final_review_disabled`; only a recorded PM waiver lifts it, and the PM card then says in its first block that the plan was not read as a whole.

**Edge Cases:**
- A carried blocker with a PM-accepted dispute: `release_ready: true` with the dispute on the card.
- USD unknown for a stand-in role: `usd_unknown_roles` lists it; the figure is never zeroed.
- A legacy-mode EPIC boundary: same aggregate with `mode: epic`; `plan_review` resolved through the `plan_ref` hop as today.

**Dependencies:**
- Depends on: Step 3, Step 4, Step 6
- Blocks: Step 8, Step 10, Step 11

**Acceptance Criteria:**
- [ ] The healthy sabotage fixture gives `release_ready: true` with zero waiver files in its run directory.
- [ ] The three broken fixtures give `false`, each with exactly the named blocker.
- [ ] The three inventory literals (`_pfsm_review_required_outputs` and the receipt check in `aid-plan-fsm.sh`, the receipt check at `aid-lifecycle.sh:201`) and `_check2_receipt_covers_candidate` name only the version-2 files; the lifecycle library's separate review-status reader is repointed in Step 12, not here.
- [ ] Review finding "The new final-review-waiver.json lifts the final_review_disabled blocker on" is answered: the waiver exists only through `--waive-final-review`, is bound to the candidate and the audit log, a toggle flipped inside the plan's range is ignored, and the suite refuses a hand-written waiver.
- [ ] Review finding "Step 7's new acceptance criterion requires `grep -c`" is answered: the criterion above names the literals it changes, and `_aid_lc_plan_review_status` is handled in Step 12 with its own case.
- [ ] The PM page of the healthy fixture shows attempts, minutes and USD equal to the source files, the USD read from a cp7 `measurement.json`.

**Effort:** L
**AID Role:** backend

### Step 8: Delivery gate — every check blocks or goes

**Objective:** Each of the 15 delivery checks is either enforced at `produce` or removed with a reason; `enforcement: observe` is no longer a state a release can live in.

**Files:**
- Create: `docs/plans/P096-delivery-gate-triage.md` — one row per check (dg01 to dg12, dg15, dg17, dg18): what it guards, how often it said `would_block` in the 37 measured runs, whether another gate already covers it, verdict `blocking` or `removed` with the reason (committed with `git add -f`).
- Modify: `plugins/aid-orchestrator/defaults/policies/delivery-gate.yaml` — `enforcement: blocking`; per-check `enabled:` from the triage; the skip-reason list kept.
- Modify: `plugins/aid-orchestrator/scripts/aid-delivery-gate.sh` — the observe-only branches and `would_block` telemetry removed; a failing enabled check fails the gate with the check's own message and next step.
- Modify: `plugins/aid-orchestrator/scripts/lib/delivery-checks/dg18-acceptance-struct.sh` — removed (`git rm`): provenance-only, never emits fail, and P095's acceptance evidence carries the structure.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows of removed checks retired with successors; remaining rows `severity: blocking`.
- Test: `plugins/aid-orchestrator/scripts/tests/test-delivery-gate.sh` — an enabled check that fails makes `delivery-gate.json` verdict `fail` and `decide` blocks on it; a removed check's id in a project override is reported as unknown; the policy refuses `enforcement: observe`.

**Reuse check:** searched: `grep -rn 'would_block' plugins/aid-orchestrator/scripts plugins/aid-orchestrator/defaults` → several matching (the gate, its policy, `aid-promote-checks.sh`) — the promotion machinery existed to move checks from observe to blocking one by one and was never used (0 promotions on disk); the triage does the promotion once and `aid-promote-checks.sh` is retired in Step 12.

**Parallel group:** ---

**Architecture Context:** Principle 1 of `docs/plans/AID-v3-principles.md`: a detector without enforcement is decoration.

**Implementation Detail:** Checks that duplicate a gate (`dg02-build`, `dg03-typecheck`, `dg04-test` against the `build`, `type_check`, `tests_pass` gates) are the first candidates for removal; the triage records the overlap per check from the measured runs.

**Error Handling:** A check whose tool is absent in the project (no build system): skip with a listed reason, as the policy's skip list already allows.

**Edge Cases:**
- A project override that still says `observe`: refused at load with the message to choose per-check `enabled: false` instead.
- A check enabled here that fails on a consumer's first close: the message names the check, the file and the policy key to disable it, and the PM card shows it as a blocker, not a crash.
- `dg17-independent-oracle-nodrop`: kept only if the triage finds a run where it would have blocked a real defect.

**Dependencies:**
- Depends on: Step 7
- Blocks: Step 11

**Acceptance Criteria:**
- [ ] `docs/plans/P096-delivery-gate-triage.md` has 15 rows, each with a verdict and a number from the measured runs.
- [ ] `grep -c 'observe' plugins/aid-orchestrator/defaults/policies/delivery-gate.yaml plugins/aid-orchestrator/scripts/aid-delivery-gate.sh` is 0 outside comments about history.
- [ ] The three new `test-delivery-gate.sh` cases pass.

**Effort:** M
**AID Role:** backend

### Step 9: Clean code at the source — the ladder in the role card, the question in the step review

**Objective:** The role that writes a step is told how to write less, and the step reviewer reports needless complexity while the diff is small.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` (lines ~46-375) — one shared paragraph "Write the least code that works" referenced by every step role: does it need to exist; is it already in this codebase (name where you looked); does the standard library or the platform do it; an installed dependency before a new one; the shortest diff that is correct; deletion before addition; no abstraction with one use, no configuration nobody sets; a deliberate shortcut carries a comment naming its ceiling.
- Modify: `plugins/aid-orchestrator/skills/step-review-roles.md` (lines ~118-130) — question 7 for `step_generalist`: "Is anything here more than the step needs: a hand-written replacement of a standard function, an abstraction with one use, a dependency for a few lines, scaffolding for later? Name what to delete or what replaces it." Severity `major` when the diff would be materially shorter, else `minor`.
- Modify: `plugins/aid-orchestrator/scripts/tests/fixtures/step-review/sample.json` — one sabotaged entry (a diff with a hand-rolled `basename` loop and a one-use wrapper function), with its recorded answer under `plugins/aid-orchestrator/scripts/tests/fixtures/step-review/answers/`; `acceptance.json` is the recorded result of the P094 run and is not edited.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `role_card_least_code_ladder` and `step_review_needless_complexity`, each citing its test.
- Test: `plugins/aid-orchestrator/scripts/tests/test-instruction-consistency.sh` — the ladder paragraph exists once and every step role card references it; the reviewer question exists.
- Test: `plugins/aid-orchestrator/scripts/tests/test-step-review-acceptance.sh` (line ~212) — the hard-coded expected answer count moves from 20 to 21, and the stub replay of the new entry yields an accepted finding tagged with the question.

**Reuse check:** searched: `grep -n -i -e 'yagni' -e 'simplest' -e 'standard library' plugins/aid-orchestrator/skills/role-cards.md plugins/aid-orchestrator/agents/implementer.md plugins/aid-orchestrator/agents/simplifier.md` → several matching in `agents/simplifier.md` only — the simplifier's criteria are the source of the ladder's wording; the role cards say nothing today, which is why cleanup happened at the end.

**Parallel group:** ---

**Architecture Context:** The PM's instruction: the person who programs works so that a cleanup is not needed; the simplifier leaves the flow (Step 12).

**Implementation Detail:** The paragraph is ours, written from the simplifier card and the PM's pointer to the ponytail ladder; the plugin takes no dependency on another plugin.

**Error Handling:** Not applicable to text; the consistency test is the guard.

**Edge Cases:**
- A step whose acceptance criteria demand an abstraction (a plugin interface): the reviewer question says "more than the step needs", so the criterion wins.
- A reviewer who reports style under question 7: the evidence rule still applies; a finding without a named replacement or deletion is rejected as today.

**Dependencies:**
- Depends on: none
- Blocks: Step 11, Step 12

**Acceptance Criteria:**
- [ ] `test-instruction-consistency.sh` passes with the two new assertions.
- [ ] The sabotaged entry's stub replay yields the finding (the live Sonnet run over that entry, ceiling 1 USD, belongs to Step 11, which depends on this step).

**Effort:** S
**AID Role:** docs-writer

### Step 10: One instruction section for closing a plan; every refusal names the next command

**Objective:** The controller reads one section of at most 200 lines; `skills/pipeline.md` §7 becomes a pointer; each refusal of the five stages prints what to run next and when to go to the PM.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` — section "Closing a plan (plan-final)": the five stages as commands, the adapter pointer for the cp7 round, the fix paragraph (who fixes, how the class decides what re-runs), the escalation table (refusal → what to try once → the decision card to show), the PM card at the end.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~1293-2635) — §7 reduced to the DONE-state facts that are not plan-final and a pointer to the command section; the specialist dispatch, C3 bridge, reporter, simplifier and PM hand-off passages removed; §13's checkpoint table loses CP4 and CP5 and gains CP7.
- Modify: `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` + `plugins/aid-orchestrator/commands/aid-help.md` + `plugins/aid-orchestrator/commands/aid-plan.md` — the plan-final paragraphs point at the one section; the "Plan-final / close boundary" part of `aid-plan.md` keeps only the card and page rendering.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — every `PRECONDITION FAIL` of `freeze`, `gates`, `produce` and `decide` ends with `next: <command>` or `escalate: <what to show the PM>`.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — row `plan_final_refusal_names_next_step`.
- Test: `plugins/aid-orchestrator/scripts/tests/test-instruction-consistency.sh` — the section exists once, is at most 200 lines, names the five stages, and no live instruction file teaches `--stage sync|inputs|review|c4|summary|accept-ancillary`, the reporter, the curator or CP4.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — for each refusal of the four stages (a table in the suite), stderr contains `next:` or `escalate:`.

**Reuse check:** searched: `grep -n 'adapter:begin' plugins/aid-orchestrator/commands/aid-run.md plugins/aid-orchestrator/commands/aid-plan.md` → one match per file — the adapter is already quoted in `aid-run.md` for CP2 and CP3; the new section points at that quote instead of a third copy (the P094 line count grew by exactly such a copy).

**Parallel group:** ---

**Architecture Context:** V6: what the agent reads is what the code enforces, in one place, and a stuck agent is told the way out by the tool, not by memory of a 1 343-line section.

**Implementation Detail:** The escalation table has five rows: a red gate that is a real failure; a cp7 blocker still open after round 2; a delivery-gate failure the project disputes; a candidate that is not an ancestor; a verification failure. Each names the card kind from `skills/communication.md`.

**Error Handling:** Not applicable to text; the two tests are the guard.

**Edge Cases:**
- An agent running an old stage name: the refusal of Steps 6 and 7 prints the new command, and the consistency test keeps old names out of live text.
- The legacy-mode DONE phase: two sentences in the same section, no second section.
- The section over 200 lines at review time: cut examples first; the commands stay.

**Dependencies:**
- Depends on: Step 6, Step 7
- Blocks: Step 11

**Acceptance Criteria:**
- [ ] The section is at most 200 lines (`awk` between its heading and the next `## `).
- [ ] `test-instruction-consistency.sh` passes with the retired-name category.
- [ ] Every refusal in the suite's table carries `next:` or `escalate:`.

**Effort:** M
**AID Role:** docs-writer

### Step 11: Acceptance — the auditor's findings replayed, the sabotage set in the testbed, time replayed

**Objective:** A recorded result says whether the new close finds at least what the auditor found, refuses what it must, and is faster than the baseline; EPIC 2 starts only on a passing record.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/test-step-review-acceptance.sh` — subcommand `final` beside the existing ones: for each entry of `fixtures/plan-final/sample.json`, materialise a worktree of the source repository at `candidate_sha`, build the cp7 packet for `base_sha..candidate_sha`, run the round (live with a written ceiling, or stub from recorded answers), and report per entry whether a finding matching the auditor's claim was accepted.
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/plan-final/acceptance.json` — per entry: roles' answers (recorded), matched yes or no, tokens, USD, minutes; totals against `baseline.json`; the rule: pass when matched ≥ 6 of 8 and no role's rejected count exceeds its accepted count.
- Create: `docs/plans/P096-acceptance-run.md` — the record in Czech for the PM: what was found, what was missed and why, cost per confirmed finding, the time replay of ten recorded runs, the sabotage results, and the recommendation to proceed or not (committed with `git add -f`).
- Test: `plugins/aid-orchestrator/scripts/tests/test-step-review-acceptance.sh` — the stub replay of `acceptance.json` reproduces its matched column (t2, nightly).

**Reuse check:** searched: `grep -n -e 'worktree add' -e 'stub' plugins/aid-orchestrator/scripts/tests/test-step-review-acceptance.sh` → several matching — the P094 suite already materialises a diff at a sha in another repository and replays recorded answers; the new subcommand reuses both and differs only in the packet it builds.

**Parallel group:** ---

**Architecture Context:** V4 and V8: the successor is proven on the predecessor's own real catches before the predecessor is deleted.

**Implementation Detail:** Ceiling for the live run: 25 USD, written in the record before the first dispatch; eight ranges, three roles, Opus for `final_criteria`; the one-entry live Sonnet run of Step 9's over-built diff (ceiling 1 USD) is part of the same record. The testbed (`/opt/eco/projects/aid-testbed`) gains three refusals run against the working tree with `--plugin`: a forged cp7 reviewer file without a dispatch bracket, a forged `release-decision.json`, a close with a stale candidate. The time replay runs the five stages with stub reviewers over ten recorded WAN and ACTA runs and compares minutes with `baseline.json`.

**Error Handling:** A range whose worktree cannot be materialised: dropped with the reason; fewer than six usable entries means the sample is refilled from the medium findings before the run counts.

**Edge Cases:**
- The new round finds a real defect the auditor missed: recorded as an extra, verified by reading the code, not counted toward the six.
- A finding matched only by `final_generalist` on the stand-in: counted, and the record notes the provider.
- The rule fails (fewer than six): EPIC 2 does not start; the record goes to the PM with the two numbers and the misses, and the packet or the role questions are revised, never the rule.

**Dependencies:**
- Depends on: Step 1, Step 4, Step 5, Step 7, Step 8, Step 9, Step 10
- Blocks: Step 12

**Acceptance Criteria:**
- [ ] `acceptance.json` records matched ≥ 6 of 8 with every matched finding carrying a resolving `path:line`.
- [ ] The three testbed refusals pass with `bin/verify.sh --plugin <this tree>`.
- [ ] The time replay's median minutes per attempt is below the baseline's for both projects.
- [ ] `docs/plans/P096-acceptance-run.md` states the cost per confirmed finding and the recommendation.

**Effort:** L
**AID Role:** qa

**EPIC 2: Steps 12-13 — Remove what the new close replaced, release**

### Step 12: Removal with a successor table

**Objective:** The reporter, the simplifier as a step, the curator, the auditor's plan-final contract and the audit bridge, CP4, CP5, the scanner's plan-final dispatch, the promotion script and their tests are gone; every removed registry id has a successor row or a recorded reason.

**Files:**
- Modify: `plugins/aid-orchestrator/agents/reporter.md` + `plugins/aid-orchestrator/agents/curator.md` — removed (`git rm`).
- Modify: `plugins/aid-orchestrator/agents/auditor.md` — kept for the project-health audit (`commands/aid-audit.md:9` and `scripts/lib/aid-audit-independence.sh:91` read it, both out of this plan's scope); its plan-final C3 sections (the audit-report contract, the input manifest, the Codex bridge protocol) removed.
- Modify: `plugins/aid-orchestrator/agents/simplifier.md` — kept as an agent the PM may invoke after a plan; its plan-final contract (the `Head:` line, the required report) removed.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh` — the audit half (`build-manifest`, `dispatch`, `verify`, the audit prompts' plumbing) removed; `_run_codex_isolated` and the P095 probe stay, moved unchanged into `plugins/aid-orchestrator/scripts/lib/aid-codex-transport.sh` if the remaining file would otherwise keep the audit name.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-codex-transport.sh` — the Codex transport and probe under a name that says what they are, sourced by its four consumers.
- Modify: `plugins/aid-orchestrator/scripts/aid-review-round.sh` + `plugins/aid-orchestrator/scripts/lib/aid-brainstorm-opponent.sh` + `plugins/aid-orchestrator/scripts/lib/aid-recovery-adjudicate.sh` — their `source` line repointed at `aid-codex-transport.sh` (the recovery adjudicator sources `aid-c3-dispatch.sh` at line 190 and calls `_run_codex_isolated` at line 728).
- Modify: `plugins/aid-orchestrator/scripts/aid-emit-dispatch.sh` (lines ~25-35) — `reporter` and `simplifier` leave `AID_DISPATCH_FOCUS_RE` and the duration table.
- Modify: `plugins/aid-orchestrator/agents/gate-fixer.md` + `plugins/aid-orchestrator/agents/verifier.md` + `plugins/aid-orchestrator/skills/agent-protocol.md` + `plugins/aid-orchestrator/skills/role-cards.md` + `plugins/aid-orchestrator/commands/aid-init.md` — the curator-proposal source of the gate-fixer and the CP4 section of the verifier removed with successor rows; the agent roster and the CP4 event table of the protocol skill lose the reporter, the curator and CP4; the role cards' reporter and simplifier hand-over sentences removed; the init command's product list loses the delivery-report template.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~225-260) — `_aid_lc_plan_review_status` reads the plan's cp7 `rounds.json` instead of `audit-report.json` and `curator-report.json`, with the same verdict vocabulary.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-lifecycle-reconcile.bats` — the plan review status is derived from a closed cp7 round and is `none` with a reason when there is none.
- Modify: `plugins/aid-orchestrator/scripts/tests/test-regression.sh` + `plugins/aid-orchestrator/scripts/tests/test-communication-wiring.sh` + `plugins/aid-orchestrator/scripts/tests/bats/test-subagent-protocol-notice.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-cache-preflight.bats` — the assertion that `pipeline.md` references the curator and auditor cards (test-regression line ~920) replaced by the close-section assertion; the reporter row of the wiring suite removed; the two bats suites that use a removed card as a fixture repointed at `agents/implementer.md`.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` + `plugins/aid-orchestrator/scripts/aid-fsm.sh` + `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — `compute_reporter`, `compute_simplifier`, the curator and audit inputs, `fsm_check_cp4_curator_validation`, the CP5 read, the `review` stage body and the specialist dispatch record deleted; old stage names' refusals kept for this release.
- Modify: `plugins/aid-orchestrator/scripts/aid-promote-checks.sh` + `plugins/aid-orchestrator/scripts/lib/aid-audit-mode.sh` + `plugins/aid-orchestrator/defaults/policies/c3-audit-policy.yaml` + `plugins/aid-orchestrator/defaults/templates/delivery-report.md` — removed (`git rm`); `defaults/policies/semantic-review.yaml` stays, because the C2 wiring gate of the step advance reads it (`scripts/aid-fsm.sh:5754-5757`) and is not a plan-final artefact.
- Modify: `plugins/aid-orchestrator/defaults/prompts/c3-audit-prompt-v1.md` + `plugins/aid-orchestrator/defaults/prompts/c3-audit-prompt-v2.md` — removed (`git rm`).
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-c3-activation.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-c3-advisory.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-c3-audit-prompt.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-c3-audit.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-c3-fix-loop.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-pipeline-c3-dispatch.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-delivery-report.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-reporter-boundary.bats` — removed (`git rm`) after each surviving behaviour (Codex transport isolation, probe) has its case in `test-aid-c3-dispatch.bats`, renamed in content to the transport.
- Modify: `plugins/aid-orchestrator/reference/review-successors.md` — a row per removed registry id: id, what it guarded, successor id or the recorded reason (reporter: the page is computed; CP4: no self-applied fixes remain to review; curator: findings go to the step's role; auditor: `final_review_round_required`; lenses: the three roles).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — the removed rows `status: removed_scoped` with `replacement_guard:` (the registry's existing vocabulary, header line 25; `test-review-successors.sh:29-30` selects exactly this status); the seven reporter and simplifier rows of Step 1 among them, never `plan_queue_scripted_transitions` or `plan_final_required_gates_record`; `totals:` recounted.
- Modify: `.aid-o/work/backlog.md` — `IMP-` rows for what the triage and the acceptance record deferred, and one row for the four remaining inline copies of the project-first policy lookup (Step 2).
- Create: `docs/plans/P096-wiring-audit.md` — the wiring audit of the area (functions without callers, files without readers, registry rows without a test) and the independent reading's verdict (committed with `git add -f`).
- Test: `plugins/aid-orchestrator/scripts/tests/test-review-successors.sh` — every retired id has a row; no active row cites a deleted file.
- Test: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh` — green after the removal.

**Reuse check:** searched: `grep -rn -e '_run_codex_isolated' -e 'aid_codex_probe' plugins/aid-orchestrator/scripts --include='*.sh'` → several matching (`aid-review-round.sh`, `lib/aid-brainstorm-opponent.sh`, `lib/aid-recovery-adjudicate.sh:190` and `:728`, `lib/aid-c3-dispatch.sh`) — the transport has four consumers counting its home, and that home carries an audit name; the new library file is that same code under a truthful name, no second implementation.

**Parallel group:** ---

**Architecture Context:** The P094 order: split out what survives, prove, then delete; the successor table is what makes "nothing is lost silently" checkable.

**Implementation Detail:** The caller lists are re-derived with `grep -rn` at the step's start and recorded in the commit message, because line numbers in this plan will have moved by then. The wiring audit of the area (functions without callers, files without readers) is run before the merge and its independent reading (Codex when available, else one Claude agent) is recorded in `docs/plans/P096-wiring-audit.md`.

**Error Handling:** A consumer of a removed file found late: the removal of that file is reverted within the step and the consumer is repointed first.

**Edge Cases:**
- `agents/project-scanner.md` stays (it serves `/aid-init` and memory scans); only its plan-final dispatch requirement goes.
- A consumer project's `.aid-o/config` that still names `c3-audit-policy.yaml`: ignored with one line at load, never an error.
- The legacy-mode DONE phase: its specialist calls are replaced by the cp7 round at the EPIC boundary in the same commit as the removal, so no commit leaves legacy mode without a review.

**Dependencies:**
- Depends on: Step 9, Step 11
- Blocks: Step 13

**Acceptance Criteria:**
- [ ] `ls plugins/aid-orchestrator/agents/reporter.md plugins/aid-orchestrator/agents/curator.md` fails for both; `agents/auditor.md` exists without the strings `audit-report.json` and `audit-input-manifest`; `/aid-audit`'s suite stays green.
- [ ] `test-review-successors.sh` and `test-enforcement-registry-cites.sh` pass with every row this plan removed selected by the successor test (`status: removed_scoped`); the TTL guard with `AID_TTL_TODAY=2027-01-01` reports none of the rows this plan touched.
- [ ] `grep -rln -e 'reporter' -e 'curator' plugins/aid-orchestrator/commands plugins/aid-orchestrator/skills plugins/aid-orchestrator/agents` lists no file after this step's edits of `gate-fixer.md`, `verifier.md`, `agent-protocol.md`, `role-cards.md`, `aid-init.md` and Step 10's five files; the successor table under `reference/` is the one place that keeps the words.
- [ ] Review finding "Step 12's rewritten criterion demands that `grep -rln -e reporter -e curator`" is answered: the five files it named are in this step's Files with what happens to each.
- [ ] Review finding "Step 12's tightened criterion that `grep -rln -e reporter -e curator`" is answered: `agents/gate-fixer.md` no longer applies curator proposals and `agents/verifier.md` carries no CP4 contract, each with a successor row.
- [ ] `docs/plans/P096-wiring-audit.md` carries the independent reading's verdict.

**Effort:** L
**AID Role:** backend

### Step 13: Line counts, changelog, release 2.101.0, plugin refresh, testbed, live follow-up

**Objective:** The plugin is released and installed, the testbed is green against the installed copy, the before and after line counts are recorded, and the three-live-plans follow-up is scheduled in a tracked record.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/plan-final/line-count.json` — the area's lines before (from `baseline.json`) and after, by file, with no threshold.
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — identical `## [2.101.0]` entries with a "Změna chování — přečti před upgradem" paragraph: plans in flight re-close from `freeze`; the reporter, curator and auditor are gone; `delivery-gate.yaml` no longer accepts `observe`.
- Modify: `.claude-plugin/marketplace.json` + `plugins/aid-orchestrator/.claude-plugin/plugin.json` + `plugins/aid-orchestrator/README.md` + `README.md` — version locations 3 to 8; Roadmap keeps three lines.
- Create: `docs/plans/P096-live-follow-up.md` — the three live plans to watch (one each in ACTA, WAN and this repository), the numbers to record per close (attempts, minutes, USD, findings confirmed), and the V1 and V2 thresholds (committed with `git add -f`).
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — `2.101.0 --baseline 2.100.0` exits 0.

**Reuse check:** searched: `ls plugins/aid-orchestrator/scripts/tests/fixtures/step-review/line-count.json` → one match `plugins/aid-orchestrator/scripts/tests/fixtures/step-review/line-count.json` — the P094 record's shape is reused for this area's file; the follow-up record is founded because V1 and V2 can only be tested on plans that do not exist yet.

**Parallel group:** ---

**Architecture Context:** The release boundary of this repository; V1 and V2 are closed by measurement after release, as P094's fresh diffs were.

**Implementation Detail:** Merge from the primary checkout, tag `v2.101.0`, `gh release create`, push, `claude plugin update`, force-refresh of the marketplace clone when the version does not move, then `/opt/eco/projects/aid-testbed/bin/verify.sh` against the installed plugin.

**Error Handling:** A testbed FAIL after the release is a 2.101.1, never a known finding.

**Edge Cases:**
- The after line count is higher than before: recorded as is with the files that grew; V8 has no threshold by the PM's decision.
- A consumer project closes a plan between the release and its own `/aid-init` upgrade: the old stage names refuse with the new command.
- The marketplace clone does not move after `claude plugin update`: the force-refresh of CLAUDE.md is applied and the installed version is checked again before the testbed runs.

**Dependencies:**
- Depends on: Step 12
- Blocks: none

**Acceptance Criteria:**
- [ ] `verify-version-files.sh 2.101.0 --baseline 2.100.0` exits 0 and both CHANGELOG sections are identical.
- [ ] The installed plugin version is 2.101.0 and the testbed prints 0 FAIL against it, including the three plan-final refusals.
- [ ] `line-count.json` and `docs/plans/P096-live-follow-up.md` exist.

**Effort:** M
**AID Role:** backend

## Testing Strategy

| Behaviour | Where | Tier |
|---|---|---|
| The TTL guard passes on and after 2026-10-01 for every row this plan touches | `test-registry-ttl.bats` | existing tier |
| The risk profile resolves in a project that is not this repository; an invented lens or role is refused | `test-review-profile.sh`, `test-review-round.bats` | t2, t1 (existing) |
| `git_clean` passes over AID's own ancillary writes and fails over a real change | `test-evidence-verify-tree.bats` | t0 (existing) |
| A cp7 round prepares without `plan.json`, binds to the candidate, refuses an undispatched answer, writes the semantic file | `test-review-round.bats`, `test-review-config.bats` | t1, t0 (existing) |
| A green gate with unchanged inputs is reused, a red or waived one never | `test-aid-plan-final-boundary.bats` | t2 (existing; cross-component) |
| A fix invalidates by class; ancestry and the receipt hash stay absolute | `test-aid-plan-final-boundary.bats` | t2 |
| The decision says yes on the healthy plan and no with a named reason on three broken ones and on a switched-off review; receipt version 1 is refused | `test-release-policy.bats`, `test-aid-plan-close-check.bats` | t2, t1 (existing tags) |
| The PM page's numbers equal the source files and no model is dispatched to render it | `test-pm-brief.bats` | existing tier |
| An enabled delivery check that fails blocks; `observe` is refused | `test-delivery-gate.sh` | t2 (existing) |
| The ladder and the reviewer question exist; a sabotaged over-built diff gets a finding | `test-instruction-consistency.sh`, `test-step-review-acceptance.sh` | t2, t2 (nightly; both run alone before the merges of Steps 9 and 10) |
| One close section of at most 200 lines; no live text teaches a retired stage or agent; every refusal names the next step | `test-instruction-consistency.sh`, `test-aid-plan-final-boundary.bats` | t2, t2 (nightly; run alone before the merge of Step 10) |
| The new round confirms at least six of the auditor's eight findings | `test-step-review-acceptance.sh final` (stub nightly, live manual with a ceiling) | t2 |
| Every retired id has a successor; no active row cites a deleted file | `test-review-successors.sh`, `test-enforcement-registry-cites.sh` | t0 |
| The installed plugin refuses a forged round answer, a forged decision and a stale candidate | testbed `verify.sh` | live |

No suite is created: every case joins a suite that exists and inherits its tag; `aid-test-tier-lint.sh` runs before the merge and a suite pushed past its budget is re-measured with `aid-test-tier-assign.sh`. The central refusals of the boundary live in t2 suites (cross-component by the standard), so the merge path proves the engine cases (t0, t1) and the nightly proves the boundary; Steps 7 and 12 run the touched t2 suites alone before their commits.

## Constraints

- Language: English in plugin code, comments, skills and commands; Czech in PM cards, pages and `docs/plans/` records.
- Hygiene rule B: no dead code left in a modified file; a registry row with the ten fields and a breaking test for every refusal added.
- No new plugin dependency, and none on the ponytail plugin.
- Quality first: EPIC 2 starts only when `acceptance.json` passes its rule and the PM has seen `docs/plans/P096-acceptance-run.md`; line counts are recorded, never a target.
- Subagents during implementation: at most two at once, none without the PM's go with count and model, except the reviewers the checkpoints configure.
- Paid runs: Step 9 ceiling 1 USD, Step 11 ceiling 25 USD, written in the record before the run.
- Merge path t0 + t1 green throughout; touched t2 suites run alone at Steps 7 and 12.
- Every `docs/plans/` record committed with `git add -f`; every number a criterion cites lives in a tracked file under `plugins/aid-orchestrator/`.
- P095 is merged before this plan's EPIC 1 starts; where both touch a file (`aid-evidence-verify.sh`, `aid-release-policy.sh`, `aid-review-round.sh`, `aid-plan-fsm.sh`), this plan builds on P095's result.

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| The new round confirms fewer than six of the eight findings | medium | the auditor cannot be deleted | EPIC 2 is gated on the record; the packet and role questions are revised, the rule is not; the old flow keeps working meanwhile |
| Delivery checks turned blocking fail on a consumer's first close | medium | a plan stops at `produce` | the triage enables only checks with measured value; each failure names the policy key to disable it; the CHANGELOG paragraph warns |
| Carrying results across attempts lets a stale result through | medium | a change escapes review | the class is computed from paths against declared inputs, unknown means `delivery`; ancestry and receipt hash absolute; cases for each class in Step 6 |
| The plan FSM edit (11 519 lines) breaks an unrelated plan command | medium | plan start, continue or merge regress | old stage names refuse rather than vanish; `test-aid-plan-final-boundary`, `test-plan-final-floor`, `test-plan-final-plan-source` and the testbed run before each of Steps 6, 7 and 12 merges |
| Legacy-mode projects lose their DONE review in the gap between removal and hand-over | low | an EPIC merges unreviewed | the hand-over to the cp7 round and the removal are one commit (Step 12 edge case); a legacy fixture case in `test-release-policy.bats` |
| P095 slips and this plan starts on a moving base | medium | conflicts in four shared files | the Constraint: P095 merged first; Step 1 has no overlap and can start at once |
| Cost of the whole-plan round on a large range | medium | budget surprise at close | measured in Step 11 and shown on the page; `final_claims` on Sonnet; the profile fix stops every plan from being the most expensive case |
| The 2026-09-30 deadline | low after Step 1 | plan-final fails everywhere on 2026-10-01 | Step 1 is first and independent; if even that slipped, the deferral is a one-line hotfix |

## Success Criteria

- [ ] `AID_TTL_TODAY=2026-10-01` TTL guard passes on the shipped registry from Step 1 on, and every row this plan touched is retired with a successor at the end (Steps 1, 12).
- [ ] The healthy sabotage plan gets `release_ready: true` with no waiver; the three broken ones get `false` with the named reason (Step 7).
- [ ] `acceptance.json`: at least six of the auditor's eight real findings confirmed by the cp7 round, each with resolving evidence, recorded before anything is removed (Step 11).
- [ ] A docs-only fix after a closed round re-runs one role and no unchanged gate; a code fix re-runs the round; a rewritten branch is refused (Steps 5, 6).
- [ ] One close section of at most 200 lines; every refusal names the next step; no live text teaches a retired stage or agent (Step 10).
- [ ] The reporter and curator cards do not exist and the auditor card carries no plan-final contract; every removed registry id has a successor row; the wiring audit carries an independent verdict (Step 12).
- [ ] The installed 2.101.0 passes the testbed with the three plan-final refusals; the follow-up record for three live plans exists with the V1 and V2 thresholds (Step 13).

## Next Steps

- After three live plan closes (ACTA, WAN, this repository): fill `docs/plans/P096-live-follow-up.md`, compare attempts, minutes and USD with `baseline.json`, and decide with the PM whether `final_generalist` earns its place and whether `final_criteria` needs Opus.
- The gates (runner, profiles, selection, five gates off by default) are the next plan in the series; it inherits the `inputs:` declaration this plan adds to gate rows, and the two re-dated P068-line rows: `plan_final_required_gates_record` is a writer whose intended reader is the plan-final `gates` stage, so that plan either wires the reader or removes the row before 2026-12-31.
- Then generation and the test audit, by the inventory `docs/plans/AID-kontroly-inventura.md`.
