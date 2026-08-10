---
id: P079
type: plan
status: draft
created: 2026-08-09
author: PM + AI
risk: high
---
> **Closure (2026-08-10):** implemented, merged to `main` and released as **v2.81.0**. Archived from the active plan set.


# Plan: P076 Aftermath — Twelve Live-Found Fixes (IMP-472..483)

## Stakeholder Brief

The first real P076 run was a working stress test of the whole pipeline, and it surfaced twelve concrete defects — every one either observed live or verified in code the same day. The worst are about truth: gates ran against the wrong tree and reported a confident green about code they never saw (with the risk resolver then picking the cheapest profile off an empty diff); chained EPICs got task branches cut before the previous EPIC's work existed; evidence writes silently failed from the worktree; and a release-blocking deferral lived only in a gitignored file that a merge would erase. The rest cost time or attention: a verdict rejected for uppercase, review findings with no authorized step to land in, a self-development preflight that stops on its own work in progress, a release script that can retitle an already-tagged version, and a whole family of "green tests that check nothing". This plan fixes all twelve with mechanical enforcement and regression tests, plus the measured re-tuning of the plan-final broad suite (cap from a real measurement, background ownership, delegation of the heaviest process suites). It is the first work after P076 merges — the parallelism-removal plan and P078 both build on these fixes. Main risk: the fixes touch the FSM and gate runner that every run depends on; mitigation is one bounded fix per defect, each with its own bats coverage, and anchors grounded in BOTH trees (pre- and post-merge) so the rebase is mechanical.

## Context

Source: `docs/plans/2026-06-29-BACKLOG.md` entries IMP-472..483, all registered 2026-08-09 from the first live P076 run (controller retrospective + PM-forwarded findings). Decision record: `.aid-o/work/interim-P079.md`. PM decisions already made in chat (2026-08-09): P076 merges immediately via PM force (v2.80.0); this plan is the FIRST post-merge work, before the parallelism-removal plan (other session) and before P078; no parallel test execution anywhere (line cancelled, IMP-469 REJECTED). Two grounding agents verified every fix target file:line in BOTH trees — `main:` at d822957 and `p076:` at `.aid-worktrees/plan-P076` (the post-merge shape); where the trees differ, both line numbers are given as `main:N / p076:M` and implementation anchors on the merged tree. Key grounded corrections that reshaped the backlog proposals: IMP-480's stated mechanism was wrong (all four Files verbs already flow through derivation — the defect is the silent drop of unparseable bullets at aid-plan-to-epic.sh:988); IMP-478's branch cut already uses the live plan head — but at REGISTRATION time (generation), and the lineage check (merge-base == recorded base) cannot detect a branch that is merely behind; IMP-476's `carried-obligations.md` has NO writer or reader anywhere in code (it was an ad-hoc controller file); the CHANGELOG byte-identity test the retrospective assumed does not exist (only header-equality in verify-version-files.sh:78-99).

## Goal

Every defect the first P076 run exposed is closed by a mechanical fix with its own regression test: gates always run in and report about the plan's own tree, chained EPICs always build on their predecessors, deferrals and review findings always have a durable, consumed carrier, and the release/test tooling refuses the specific lies it told this week.

## Scope

**In scope:**
- `cmd_advance_to_gates` worktree redirect + gate-runner path resolution through the state root (IMP-475 + IMP-479, one bundle).
- Stale chained task branch detection with fast-forward + base reconciliation at execution start (IMP-478).
- Case-tolerant verdict parsing + doc/template alignment + stale registry cite (IMP-472).
- Loud failure for silently-dropped Files bullets (IMP-480, corrected mechanism).
- Durable carried-obligations mechanism with a plan-close consumer (IMP-476) and a minimal routed-findings record with a done-advance refusal (IMP-473).
- Cache-preflight tolerance for the plugin's own work-in-progress in a plan worktree (IMP-477); prefilter seeding instruction consistency (IMP-474).
- `aid-release.sh` tag-seal guard on both retitle sites + a real CHANGELOG byte-identity assertion (IMP-482).
- Vacuous-green test checks added to the existing content scanner + authoring rule (IMP-481).
- shell_pipeline_smoke re-tuning from the uncapped measurement + `run_mode: background` + delegation of the heaviest P076 process suites (IMP-483).
- Enforcement-registry rows for every new mechanical check, backlog entries annotated `Plan written: P079`, CHANGELOGs and release per policy.

**Out of scope:**
- Any parallel test execution (cancelled line; IMP-483 is placement/ownership only).
- The full IMP-473 routing vision (cross-checkpoint auto-routing UI) — this plan ships the minimal mechanical carrier + refusal; anything more waits for real usage.
- IMP-481's LLM-judgment checks — only the mechanical subset ships; the authoring rule covers the rest as instruction.
- P078's surfaces (help/init/setup/communication) — separate plan, already written.
- The parallelism-removal work itself (other session's plan; it rebases on this one).
- Re-litigating P076 design decisions — this plan fixes seams P076 exposed, it does not redesign P076 machinery.

## Approach

Chosen: **twelve bounded fixes, one per defect, grouped by blast radius** — tree-correctness first (the fixes every later plan needs), durability/guards second, quality/tuning/release third. Each fix is the smallest mechanical change that makes the observed lie impossible, each carries its own bats case reproducing the live incident shape, and nothing rides on prose alone (AID-v3 §1). Alternatives rejected: (a) one mega-refactor of the worktree seam (rewrite all path handling around a single resolver) — too much blast radius for the gate runner every run depends on; the enumerated per-site fix list (grounded table of 7 constructions) is complete and testable; (b) deferring the small items (474, 477, 482) to "later" — exactly the unregistered-deferral failure mode IMP-476 documents; (c) building IMP-473's full routing engine now — no usage data yet, minimal carrier first.

## Architecture

Three seams, all grounded:

1. **The worktree seam** (Steps 1-3): `_fsm_require_plan_worktree` (main:742 / p076:1036) is the shipped redirect enforcer with exactly two aid-fsm callers today (cmd_init, cmd_done_advance). Step 1 adds the third caller (cmd_advance_to_gates). The gate runner (`aid-run-gates.sh`) has zero root-resolver calls and seven grounded path constructions, five cwd-relative and one git-toplevel-based; Step 2 routes them through `aid_state_path`/`aid_state_root` with the same documented cwd fallback idiom `derive_timeline` already uses (aid-fsm.sh main:214-227), preserving fixture compatibility. Branch topology (Step 3): `cmd_epic_start` (aid-plan-fsm.sh:2111) cuts `task/E-*/main` from the live `plan/<id>` head inside the plan lock (:2247-2261) — correct at registration, stale by execution for chain members; the existing lineage check (:864-877) asserts merge-base equality and passes a stale branch. Two base records exist (manifest `epic_base_commit` via plan_manifest_add_epic (lib/aid-plan-manifest.sh:997); fsm-state `base_commit` from cwd HEAD at aid-json-to-run.sh:660) and nothing reconciles them.
2. **The carrier seam** (Steps 6-7): machine-readable findings already exist per checkpoint (semantic-review-local.json, semantic-review-final.json, audit-report.json with fingerprint lib aid-finding-fingerprint.sh:24-26 and merge lib aid-finding-merge.sh); what is missing is a per-plan durable record that survives worktree teardown and a consumer that refuses completion while it has open entries. Both new records live in the STATE ROOT's plan-state directory (`.aid-o/work/plan-state/<plan_id>/`) — the one place that exists independently of any worktree — and their consumers are the existing precondition ladders: `cmd_done_advance`'s EPIC-local block (aid-fsm.sh main:5566 region) and `aid-plan-close-check.sh`.
3. **The honesty seam** (Steps 4-5, 8-12): parsers, templates, release tooling and test checks each get the specific refusal they lacked, anchored at the grounded sites (verdict case at main:957-961 / p076:1251-1255; silent bullet drop at aid-plan-to-epic.sh:988; retitle seds at aid-release.sh:468 and :577; content scanner aid-test-content-scan.sh as the shipped host for new mechanical checks; runtime baseline lib with its shipped recommendation arithmetic `max(p95*1.5, p95+60s)` at aid-gate-runtime-baseline.sh:207-219).

Post-merge anchor rule: all p076: line numbers are the authoritative post-merge shape; implementation re-verifies each anchor by its quoted code, not its number.

## Implementation Steps

**EPIC 1: Steps 1-5 — Tree correctness**

### Step 1: advance-to-gates runs where the plan's tree is

**Objective:** Add the missing worktree redirect to `cmd_advance_to_gates` so gates always execute in the plan's execution worktree (IMP-475).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — in `cmd_advance_to_gates` (main:3900 / p076:5065), add `_fsm_require_plan_worktree "$(yaml_field "$state_file" epic_id)"` as the first statement after the state-file existence check, mirroring cmd_done_advance's call shape (main:5101 / p076:6266) — the redirect absolutizes the relative state_file argument on re-exec exactly as done-advance's site already proves; placed before the pre-flight guards so the re-executed process is the only one with side effects.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-roots-worktree.bats` — new cases in the existing P074 suite: a plan with a recorded worktree + advance-to-gates invoked from the primary checkout re-executes inside the worktree (fixture gate command records `pwd` into the report; assert the recorded pwd is the worktree); a legacy plan (no worktree) is byte-identical in behavior; a recorded-but-missing worktree refuses with the existing `--recreate-worktree` message.

**Architecture Context:** Third caller of the shipped enforcer (Architecture seam 1). The enforcer's four outcomes (legacy no-op / refuse unrecorded / refuse missing / re-exec) are already implemented and tested; this step only wires the missing call site, which is why it is small despite being the most critical fix.

**Implementation Detail:** Insertion point is immediately after `[[ ! -f "$state_file" ]] && { echo "ERROR: state file not found..." }` — the epic_id must be read from the state file, so the file check stays first; the redirect call uses the same `"$(yaml_field "$state_file" epic_id)"` inline read as done-advance (main:5101). No other line of cmd_advance_to_gates changes in this step (path resolution is Step 2). The `_AID_FSM_ORIG_ARGS` re-exec capture at the dispatch block (post-merge :8582) already preserves the original argv including the subcommand, verified by the existing done-advance redirect tests.

**Error Handling:** The enforcer already fails closed on unreadable records (physical-evidence fallback, main:758-760) and on redirect loops (main:795); no new failure modes are introduced. If epic_id is empty in the state file, `_fsm_epic_plan_nnn` returns empty and the enforcer no-ops (legacy behavior) — the subsequent EXECUTE-state guard then names the real fault.

**Edge Cases:**
- Invocation ALREADY inside the worktree — enforcer detects cwd inside the recorded tree and no-ops (no double re-exec).
- Ad-hoc EPIC with no derivable plan id — enforcer returns 0, byte-identical pre-P074 behavior.
- Relative `--state-file` argument — absolutized by the redirect's argv rewriting (the done-advance precedent explicitly covers this; assert it in the new bats case).

**Dependencies:**
- Depends on: none
- Blocks: Step 2 — the timeline fix is only observable once gates run from the worktree.

**Acceptance Criteria:**
- [ ] New bats cases pass; the pwd-recording fixture proves worktree execution from a primary-checkout invocation.
- [ ] `grep -c '_fsm_require_plan_worktree' plugins/aid-orchestrator/scripts/aid-fsm.sh` returns 5 (header comment + definition + the three call sites: init, done-advance, advance-to-gates).
- [ ] Legacy-plan fixture behavior byte-identical (existing suite stays green).

**Effort:** S
**AID Role:** backend

### Step 2: Gate runner resolves every path through the state root

**Objective:** Eliminate all cwd-relative and git-toplevel path constructions in `aid-run-gates.sh` so evidence, reports, ledgers, waivers and config resolve to the state root regardless of invocation directory (IMP-479).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` — source `lib/aid-roots.sh` as the EIGHTH lib source alongside the existing seven (post-merge source block :60-:81); replace the seven grounded constructions: timeline default (main:326 / p076:1518), report default (main:434 / p076:1640), ledger dir (main:525 / p076:1781), waiver dir (main:747 / p076:2172), the p076-only `_evidence_dir` (p076:1728), plugin.yaml root via `git rev-parse --show-toplevel` (post-merge :1665 — becomes `aid_state_root` with the toplevel as fallback), and the metrics gitignore check (main:102-105) — each becomes `aid_state_path "<rel>" 2>/dev/null || printf '%s' "<rel>"` (the exact documented fallback idiom from `derive_timeline`, aid-fsm.sh main:214-227, which keeps every existing fixture that runs outside a git repo working unchanged).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — `cmd_advance_to_gates` passes its already-resolved `$timeline` as the runner's positional timeline argument (the invocation at main:4032-4040 currently skips the slot), so the FSM-driven path never even relies on the runner's default.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-run-gates-worktree-paths.bats` — new suite: from a linked-worktree cwd with a state root elsewhere, a run-all writes timeline.jsonl, gates_report.json, execution-ledger.json and a waiver read all under the STATE root (assert file existence there and absence under the worktree); report `revision.head_sha` equals the WORKTREE's HEAD (the IMP-475 live-evidence assertion); a bare fixture dir with no git repo still works via the fallback (existing-behavior regression).

**Architecture Context:** Seam 1's second half. The runner deliberately keeps working in the caller's cwd for RUNNING gate commands (that is Step 1's guarantee of correctness — commands must see the candidate tree); only its own STATE writes move to the state root. This split — commands in the tree, evidence in the state root — is the same contract advance-to-gates already implements for the paths it resolves (main:3929-3962).

**Implementation Detail:** `aid_state_path` requires `lib/aid-roots.sh`; the runner sources seven libs in the post-merge block (:60-:81) — add the eighth with the same shellcheck source comment style. For the plugin.yaml site (main:458-461), the semantic change is deliberate and documented in a comment: the project config lives at the STATE root (`.aid-o` never moves into a worktree, per the aid-roots contract), so `git rev-parse --show-toplevel` from a worktree read the WRONG tree's config — fallback order becomes `aid_state_root || git toplevel || pwd`. The head_sha recorded in reports must come from the cwd tree (the candidate), NOT the state root — verify the existing head capture site reads `git rev-parse HEAD` in cwd and leave it there (assert in bats).

**Error Handling:** `aid_state_root` failing (not a git repo) triggers the printf fallback on every site — behavior identical to today for fixtures; a state root that resolves but is unwritable surfaces as the existing per-write error (e.g. the ledger's `return 3` at main:534-537), now with an absolute path in the message.

**Edge Cases:**
- `--report-file` / positional timeline passed explicitly (the FSM path after this step) — explicit arguments always win; defaults are the only thing this step rewrites.
- The metrics gitignore write (main:102-105) touches `.git/info/exclude` — from a linked worktree the shared `.git` dir is the common dir; use `git rev-parse --git-common-dir` for that one write so the exclude lands once, not per-worktree.
- p076's `_gate_ladder_emit` guard `[[ -d "$dir" ]] || return 0` — after resolution the dir exists in the state root, so ladder records start actually persisting from worktree runs (that silent no-op was part of the same defect).

**Dependencies:**
- Depends on: Step 1 — combined bats scenario runs the redirected path end to end.
- Blocks: Step 3 — chain fixture uses the now-trustworthy worktree gate run.

**Acceptance Criteria:**
- [ ] New suite passes: all four evidence artifacts land under the state root from a worktree invocation; head_sha == worktree HEAD.
- [ ] `grep -n 'aid_state_path\|aid_state_root' plugins/aid-orchestrator/scripts/aid-run-gates.sh` shows ≥7 resolved sites; `grep -n '"\.aid-o/work' plugins/aid-orchestrator/scripts/aid-run-gates.sh` shows no remaining unresolved default.
- [ ] Existing gate-runner suites (test-run-gates.sh, bats gate suites) stay green — the no-git-repo fallback preserves fixture behavior.

**Effort:** M
**AID Role:** backend

### Step 3: Chained task branches fast-forward to the live plan head at execution start

**Objective:** An EPIC that starts executing on a task branch cut before its predecessors merged is detected and fast-forwarded (or loudly refused), with both base records updated (IMP-478).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — in `cmd_epic_start`'s branch-already-exists path, the reconciliation runs BEFORE the `epic_lineage` precondition at :2201 (deliberately: after a crash mid-sequence the merge-base no longer equals the recorded base, so the untouched lineage check would refuse before any repair code could run). Trigger covers BOTH recovery shapes: (a) branch strictly behind the plan head with no unique commits (`git merge-base --is-ancestor "$task_branch" "plan/${plan_id}"` rc=0 AND branch head != plan head) ⇒ fast-forward the task branch to the plan head; (b) branch head == plan head but the manifest `epic_base_commit` != branch head (the crash residue between ff and CAS) ⇒ skip the ff, proceed to the manifest update. In both shapes, update the manifest's `epic_base_commit` (writer plan_manifest_add_epic, lib/aid-plan-manifest.sh:997) via the new mutator — CAS on the prior recorded value, AND a no-op success when the manifest already equals the new base (post-CAS re-run) — then log a `task_branch_fastforward` timeline event naming old→new. `merge-base --is-ancestor` rc is branched explicitly: 0 = ancestor, 1 = diverged, ≥2 = error reported verbatim (never misnamed as divergence). Diverged (unique commits AND behind): PRECONDITION FAIL naming both heads and the repair (merge plan into task or re-cut) — never silent. The lineage precondition itself is UNTOUCHED — it runs after the reconciliation and passes because the reconciliation has restored its invariant.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` — add the bounded mutator `plan_manifest_update_epic_base <plan_id> <epic_id> <old_base> <new_base>` (CAS against old_base, same convention as `plan_manifest_set_accepted_head`'s CAS at :1497-1498), refusing on mismatch.
- Modify: `plugins/aid-orchestrator/scripts/aid-json-to-run.sh` (lines ~655-670) — the fsm-state `base_commit` capture (:660, currently cwd HEAD at run-init time) records the task branch's head instead of bare `git rev-parse HEAD` when a plan worktree is in play — covers FUTURE runs whose fsm-state does not exist yet. For CHAINED EPICs the fsm-state already EXISTS at epic-start (generation creates it for every EPIC before execution, and aid-json-to-run initializes only when the state file is absent — :688/:849), so the epic-start reconciliation ALSO updates the existing `fsm-state.yaml`'s `base_commit` in place: the state file is located via the manifest entry's `evidence_dir`, the write uses the FSM's own set-field path under the plan lock, and it applies the same discipline as the manifest mutator — update when the recorded value equals the old base, no-op when it already equals the new base, refuse loudly on any third value. Crash between the manifest CAS and the fsm-state write = a third recovery shape: manifest == branch head but fsm-state behind ⇒ re-run performs only the fsm-state write.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-epic-chain-freshness.bats` — full-chain fixture reproducing the REAL generation flow: plan with 2 EPICs registered together AND both fsm-state.yaml files created BEFORE EPIC 1 merges (the P076 shape); EPIC 1 merges a file into plan/<id>; EPIC 2's epic-start then fast-forwards its branch, the file EXISTS in EPIC 2's tree, AND BOTH persisted base records (manifest epic_base_commit and EPIC 2's pre-existing fsm-state base_commit) equal the new plan head; crash-between-writes re-run fixture converges; diverged-branch fixture refuses with both heads named; single-EPIC and legacy plans byte-identical.

**Architecture Context:** Seam 1's topology half. The cut itself (:2247-2261) is correct — the defect is temporal: chain generation registers all EPICs at once, so later members' branches age while predecessors execute. The existing lineage check (:864-877) is necessary but insufficient (merge-base equality holds for a stale branch); this step adds the sufficiency check at the same call site.

**Implementation Detail:** Fast-forward mechanics: `git -C "$project_root" branch -f "$task_branch" "$plan_head"` is NOT safe for a checked-out branch — the branch may be checked out in the plan worktree; use `git -C "$worktree_path" merge --ff-only "plan/${plan_id}"` when the branch is checked out there, `branch -f` otherwise (detect via `git worktree list --porcelain`). The manifest CAS mutator mirrors `plan_manifest_set_accepted_head`'s validation (40-hex, prior-value compare). The reconciliation in aid-json-to-run.sh only activates when `_fsm_plan_worktree_recorded` resolves (worktree plans); planless/ad-hoc runs keep cwd HEAD.

**Error Handling:** Fast-forward failing (lock contention, unexpected checkout state) → PRECONDITION FAIL with the exact git error and the manual repair line; manifest CAS mismatch (concurrent mutation) → refuse naming both values, never overwrite. The refusal path is the safe default: no automatic merge of diverged branches, ever.

**Edge Cases:**
- EPIC 2 starts while EPIC 1 is still unmerged (parallel-ish operation) — branch equals plan head, no-op, no event.
- Plan head moved by a NON-EPIC commit (PM hotfix on plan branch) — same fast-forward path applies; the event's old→new makes it auditable.
- Crash between fast-forward and manifest update — re-running epic-start hits recovery shape (b): branch == plan head, manifest behind; the reconciliation (running before the lineage precondition) invokes the CAS against the still-recorded old value and the lineage check then passes on the restored invariant — assert the full re-run in bats. Crash AFTER the CAS: the mutator's already-equal no-op branch makes a further re-run a clean pass.

**Dependencies:**
- Depends on: Step 2 — the chain fixture's gate assertions rely on state-root evidence writes.
- Blocks: Step 13 — registry row for the new refusal.

**Acceptance Criteria:**
- [ ] Chain fixture: EPIC 2's tree contains EPIC 1's merged file at epic-start; manifest base updated; event present in timeline.
- [ ] Diverged fixture refuses with both heads in the message; nothing mutated.
- [ ] BOTH persisted base records (manifest epic_base_commit AND the pre-existing fsm-state base_commit) equal the new plan head in the full-chain fixture — the fsm-state file created before EPIC 1's merge included.

**Effort:** L
**AID Role:** backend

### Step 4: Case-tolerant verdict parsing and casing-consistent docs

**Objective:** `verdict: PASS` is accepted as `pass`, the classification enum tolerates lowercase, and every instruction surface shows the casing the parser accepts (IMP-472).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — in `fsm_check_verifier_output` (main:935-982 / p076:1229-1276): normalize the extracted verdict with `tr '[:upper:]' '[:lower:]'` before the case match (main:957-961); normalize the classification token likewise and match against the canonical uppercase set (accepting `skip`/`run`/`fail`/`full_review` in any case); the `## Result: PASS` increment-step anchor (aid-fsm.sh:5475 — a bash `[[ "$_verify_content" == *"## Result: PASS"* ]]` substring match, NOT a grep) becomes case-insensitive by matching against a lowercased copy of the content (`${_verify_content,,} == *"## result: pass"*`) so a verifier writing `## Result: pass` is not rejected either — the canonical form in templates stays uppercase.
- Modify: `plugins/aid-orchestrator/defaults/templates/step-verify-template.md` (lines ~115-121) — add one comment line under the Result heading: verdict lines elsewhere are lowercase (`verdict: pass|fail`); the Result heading is canonical uppercase; both are now case-tolerant at the parser. Also correct the template's stale claim "Enforced via `grep -q`" (lines ~120-121) — the actual enforcement is the bash substring match in cmd_increment_step.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — `increment_result_pass` row's stale `source: "scripts/aid-fsm.sh:1739"` repointed to the actual site (post-merge line of the increment anchor); add the case-tolerance note to its description.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — new cases: `verdict: PASS` accepted, `verdict: Fail` accepted, `verdict: banana` still rejected, `classification: skip` (lowercase) accepted with reason, `## Result: pass` passes increment; `verdict: pending` still returns 1 (prefilter placeholder semantics unchanged).

**Architecture Context:** Seam 3. The live incident: a verifier followed the template's uppercase `## Result: PASS` convention into the `verdict:` field, which is lowercase-only — two opposite casing conventions inside one function (classification UPPERCASE, verdict lowercase, grounded A1/A2). Tolerance for equivalent forms, loud rejection for genuinely unknown values — the P074 adjudicator-parser precedent.

**Implementation Detail:** Normalization happens on the extracted token only, never on the file content (evidence bytes stay untouched); the case arms keep their canonical literals. The prefilter's `verdict="skip"` placeholder for SKIP classification (aid-prefilter.sh:263) is unaffected — the SKIP path returns before the verdict arm and continues to. Sweep for other single-token comparisons was done at grounding (A4 list — all internal producer-consumer pairs with controlled casing); only the two operator-written fields (verdict, classification) plus the Result anchor get tolerance, internal JSON fields do not (their producers are scripts, not humans).

**Error Handling:** An empty verdict after normalization hits the existing `*)` rejection with the unknown-verdict message — unchanged. The registry repoint is validated by P078's future cite test when it lands; here the exact post-merge line is written and quoted in the row description.

**Edge Cases:**
- Mixed-case `PaSs` — normalized, accepted (equivalence, not a typo class).
- `verdict: PASSED` — normalized to `passed`, rejected (not an equivalent form; loud).
- A verify file containing BOTH `## Result: PASS` and `verdict: fail` — existing precedence unchanged (this step changes case handling only, never which field wins); pin current behavior in a bats case as-is.

**Dependencies:**
- Depends on: none
- Blocks: Step 13 — registry totals.

**Acceptance Criteria:**
- [ ] All six new bats cases pass; existing verdict cases stay green.
- [ ] `grep -n "tr '\[:upper:\]'" plugins/aid-orchestrator/scripts/aid-fsm.sh` shows the normalization inside fsm_check_verifier_output.
- [ ] Registry row cites the real line and the suite passes test-enforcement-registry-*.

**Effort:** S
**AID Role:** backend

### Step 5: Silently dropped Files bullets become loud generation errors

**Objective:** A bullet inside a `**Files:**` block that fails the verb grammar can no longer vanish without a word — generation names it and stops (IMP-480, corrected mechanism).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (lines ~985-996) — the `|| continue` on the verb regex (:988) becomes: collect the failing bullet into a `dropped_bullets` array with step number and text; after the step's block, if the array is non-empty, fail generation with one line per drop (`step N: unparseable Files bullet dropped: "<text>"`) and the pointer to the grammar in plan-writing.md. Indented bullets never reach here (the extractor's column-0 rule treats them as prose — that stays; the plan LINT already warns on the split-verb shape).
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-lint.sh` — the existing `no-path`/`bad-shape` ERROR tier already blocks these at plan-write time; add the one missing shape to its checks if reproduction (below) shows a shape the lint misses (implementation first REPRODUCES the live P076 case: run the extractor over the P076 plan's step that named `test-instruction-closure.bats` and identify which drop shape ate it — indented bullet, split verb, or missing label — and pins that exact shape in the test).
- Test: `plugins/aid-orchestrator/scripts/tests/test-epic-to-json-regression.sh` — new cases: a Files block with an unlabelled bullet fails generation naming it; a split verb/path bullet fails; the reproduced P076 shape fails with the exact message; a fully canonical block still generates (regression).

**Architecture Context:** Seam 3. Grounded correction: all four verbs already flow through derivation (aid-scoping.sh:210, regression-pinned since v2.57.2); the defect is the silent `continue`. The fix direction follows the P076-family principle: a parser never silently narrows scope — it either parses or refuses by name.

**Implementation Detail:** The failure is at aid-plan-to-epic.sh level (generation), not in the shared extractor — the extractor's prose-continuation rule is load-bearing for legitimate multi-line prose under a bullet and must not change. Distinguishing "prose continuation" (indented, following a valid bullet) from "dropped path" is exactly what the reproduction determines; if the P076 case was an indented FIRST line (no preceding valid bullet), the extractor change is one guard: an indented line starting with `- <Verb>:` inside a Files block with no preceding column-0 bullet → treated as an error line, not prose.

**Error Handling:** Generation failure here is pre-transaction (before any EPIC file is written in the affected phase) — the existing transaction resume covers re-running after the plan is fixed. The message includes the plan path and step header for direct navigation.

**Edge Cases:**
- Legitimate prose continuation lines under a valid bullet — untouched (assert with a fixture containing exactly the plan-writing.md documented shape).
- A Files block that is entirely prose (zero valid bullets) — already an ERROR at lint; generation now also refuses (defense in depth).
- Bullet with a valid verb but empty path after stripping — falls into the same loud path (currently produces an empty entry silently — assert it now refuses).

**Dependencies:**
- Depends on: none
- Blocks: Step 13 — registry row.

**Acceptance Criteria:**
- [ ] Reproduction documented in the step verify output: the exact P076 drop shape named with the plan text quoted.
- [ ] All four new regression cases pass; canonical fixtures still generate.
- [ ] `grep -n 'continue' plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` shows no bare drop of a Files-block bullet.

**Effort:** M
**AID Role:** backend

**EPIC 2: Steps 6-10 — Durable carriers and guards**

### Step 6: Carried obligations get a durable home and a consuming gate

**Objective:** A release-blocking deferral recorded during a run survives worktree teardown and mechanically blocks plan close until resolved or registered (IMP-476).

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-obligations.sh` — sourceable lib: `aid_obligation_add <plan_id> <severity> <text> <source_ref>` appends a JSON line to `$(aid_state_root)/.aid-o/work/plan-state/<plan_id>/carried-obligations.jsonl` (state root ALWAYS — never the worktree; the lib sources aid-roots.sh and refuses when the root cannot resolve); `aid_obligation_resolve <plan_id> <index> <resolution>` appends a resolution line (append-only journal, no in-place edits); `aid_obligation_open <plan_id>` prints open entries (added minus resolved). Severities: `release_blocker | followup`.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh` — new check: `aid_obligation_open` non-empty with any `release_blocker` ⇒ close refused naming each open obligation and the two exits (resolve it, or register it as a backlog IMP and mark it resolved with the IMP number as resolution — the P076 Step 14 durable-registration convention, grounded at P076 plan :489-517).
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — the controller instruction at the points where deferrals arise (review verdicts, C3 loop outcomes, DONE review): record any release-blocking deferral via `aid_obligation_add` — one sentence per site, replacing nothing.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-obligations.bats` — add from a worktree cwd lands the file in the STATE root; open release_blocker blocks plan-close-check with the named entry; resolve-with-IMP unblocks; `followup` severity never blocks; unresolvable root refuses loudly.

**Architecture Context:** Seam 2. Grounded: `carried-obligations.md` has no writer or reader anywhere — the P076 controller improvised it inside the worktree's gitignored `.aid-o`, where the merge erased it. The state root's plan-state directory is the shipped precedent for exactly this class (pm-auto-go.json, plan-state.yaml live there and survive every worktree operation). HONEST CLASSIFICATION of the producer side: unlike routed findings (which Step 7 reconciles against the canonical CP3 artifact), obligations have NO authoritative source artifact to reconcile against — a deferral is born in a controller decision — so recording them is controller instruction, backed by the blocking consumer once recorded; the Step 13 registry row records the produce side as instruction-severity and the consume side as blocking.

**Implementation Detail:** JSONL schema per line: `{op: "add"|"resolve", ts, plan_id, severity, text, source_ref, index?, resolution?}` — the index is assigned at FOLD time from journal position (never computed and embedded at write time: two concurrent O_APPEND adds could embed the same index and a later `resolve <index>` could silently close an unrelated release blocker — the one duplication path that weakens the guard); `aid_obligation_open` folds the journal with jq and prints fold-time ordinals. The plan-close-check integration follows its existing check style (named check, one-line verdict, exit contribution). No git tracking needed: the state root's `.aid-o` is the PM's persistent workspace — the defect was the WORKTREE's ephemeral copy, not gitignore itself (grounded: the file under work/evidence/ was doubly doomed — gitignored AND in a disposable tree).

**Error Handling:** Concurrent adds from two sessions — appends are O_APPEND single-line writes ≤4 KB (the shipped append-only JSONL precedent is timeline.jsonl's `log_event`, aid-fsm.sh:237/:692/:1196 — NOT aid-job, whose durable state is temp+mv per-job files); the fold tolerates interleaving. A corrupt line fails the fold loudly in plan-close-check (fail closed: unreadable obligations block close naming the line number).

**Edge Cases:**
- Obligation added for a plan that never closes (abandoned) — plan-rollback/abandon paths leave the journal in place; nothing consumes it, harmless, documented in the lib header.
- Same obligation added twice — two entries, both must resolve; dedup is the operator's judgment, not the tool's.
- Legacy plans without plan-state dir — `aid_obligation_add` creates it (mkdir -p), same as other plan-state writers.

**Dependencies:**
- Depends on: none
- Blocks: Step 7 — routed findings reuse the same journal idiom; Step 13 — registry row.

**Acceptance Criteria:**
- [ ] All five bats cases pass; the worktree-cwd case proves state-root placement.
- [ ] plan-close-check refusal names the obligation text and both exits.
- [ ] `grep -rn 'aid_obligation_add' plugins/aid-orchestrator/skills/pipeline.md` shows ≥3 instruction sites.

**Effort:** M
**AID Role:** backend

### Step 7: Routed review findings — minimal carrier plus done-advance refusal

**Objective:** A review finding that no remaining step may fix gets a recorded route (target step, target EPIC, or backlog registration), an EPIC cannot complete while a routed finding is open, AND done-advance mechanically reconciles the canonical CP3 findings against the journal — an unrecorded out-of-scope finding fails closed, not just an unresolved recorded one (IMP-473, minimal mechanical core with a deterministic producer boundary).

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-routed-findings.sh` — same journal idiom as Step 6 in the same plan-state dir (`routed-findings.jsonl`): `aid_finding_route <plan_id> <fingerprint> <source_checkpoint> <target>` where target ∈ `step:<n> | epic:<id> | backlog:<IMP-id> | resolved:<ref>`; `aid_finding_open_for_epic <plan_id> <epic_id>` prints findings routed to this EPIC (or its steps) not yet resolved. Fingerprints are carried as OPAQUE strings copied verbatim from the source artifact — never recomputed (two formulas ship: the generic `fingerprint()` at lib/aid-finding-fingerprint.sh:9-23 for semantic-review findings and `fingerprint_audit_report()` at :46-60 for C3 audit findings); the lib validates only the shared `sha256:<64hex>` envelope.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — in `cmd_done_advance`'s EPIC-local both-modes block: the new precondition inserts AFTER the legacy-only guard's closing `fi` (the pm_decision check at post-merge :6740-6744 sits INSIDE the legacy-only branch; the both-modes EPIC-local block opens before the auditor blocking_findings check at :6762) — TWO checks: (1) `aid_finding_open_for_epic` non-empty ⇒ refuse review→release naming each open finding, its source checkpoint and its two exits (fix in an authorized step and mark resolved, or route to `backlog:<IMP>`); (2) PRODUCER RECONCILIATION — read the run's canonical CP3 artifact (`semantic-review-final.json`), and every finding whose target file lies outside the union of ALL steps' allowed_paths (the same union the pre-commit hook computes for GATES/DONE) MUST have a journal entry (open or resolved) with its fingerprint; a canonical out-of-scope finding with NO journal record refuses by fingerprint — the controller can no longer hold it in prose. Absent journal AND no out-of-scope canonical findings = no-op (zero-cost for runs that never route). The lib is sourced at aid-fsm.sh's top-of-file source block using the guarded `|| true` pattern of the aid-plan-manifest source (post-merge :71).
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — CP2/CP3 verdict-handling instruction gains one rule: a finding whose file is outside every remaining step's allowed_paths MUST be routed via `aid_finding_route` before the checkpoint is closed — and the instruction names the mechanical backstop (done-advance's producer reconciliation refuses an unrecorded out-of-scope CP3 finding by fingerprint, so skipping the routing is caught at the boundary, not lost).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-routed-findings.bats` — route to a later step + resolve ⇒ done-advance passes; open route ⇒ refusal naming the fingerprint; backlog route unblocks; cross-EPIC route (epic:E-x) blocks THAT epic's done-advance, not this one's; NEGATIVE producer case: a semantic-review-final.json fixture carrying an out-of-scope finding with NO journal record ⇒ done-advance refuses naming the fingerprint; no journal AND no out-of-scope findings ⇒ byte-identical behavior.

**Architecture Context:** Seam 2. The recurrence pattern (3× in one run incl. cross-EPIC, grounded) shows the carrier must span EPICs — hence plan-scoped journal, not run-scoped. The full routing vision (auto-derivation of authorized steps, UI) is explicitly deferred; this core makes silent loss impossible, which is the defect.

**Implementation Detail:** The done-advance check inserts after the legacy-only guard's closing `fi` and before the auditor blocking_findings check (post-merge :6762 region) — findings routing is an EPIC-local completeness fact in both release modes, so it must sit on the both-modes path, not inside the legacy-only branch. Target validation: `step:<n>` must be ≤ total_steps of the CURRENT epic when the route targets this epic; `epic:` targets are validated against the plan's manifest epic list when present, else accepted verbatim (planless tolerance). The refusal message format mirrors the auditor-findings refusal style.

**Error Handling:** Corrupt journal line ⇒ fail closed at done-advance naming the line (same rule as Step 6). A route to a nonexistent step refuses at ROUTE time (`aid_finding_route` validates), not at done-advance — errors surface where the operator is.

**Edge Cases:**
- Finding routed to the very step currently in review — legal; resolution recorded after the fix lands, assert the sequence in bats.
- Two findings with the same fingerprint from different checkpoints — two entries (source differs); both must close.
- Plan with no worktree/manifest (ad-hoc EPIC) — plan_id derivation empty ⇒ lib no-ops with a warning; the instruction still applies via backlog routing.

**Dependencies:**
- Depends on: Step 6 — shares the journal idiom and plan-state dir conventions.
- Blocks: Step 13 — registry row.

**Acceptance Criteria:**
- [ ] All five bats cases pass, including the cross-EPIC scoping case.
- [ ] done-advance refusal lists fingerprint + source + exits; absent-journal fixture byte-identical.
- [ ] pipeline.md instruction present at both CP2 and CP3 handling sections.

**Effort:** L
**AID Role:** backend

### Step 8: Cache preflight tolerates the plugin's own work in progress

**Objective:** `verify-state` inside a registered plan worktree whose diff touches `plugins/` warns loudly instead of hard-stopping on the skew that IS the work (IMP-477).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-cache-preflight.sh` — in `run_cache_preflight` (:113-205): before the dogfood hard stop (:157-170), detect the WIP case: the invocation toplevel is a linked worktree (`git rev-parse --git-common-dir` differs from `--git-dir`) AND the toplevel path matches the registered plan-worktree convention (`*/.aid-worktrees/plan-*`) AND `git diff --name-only <base>..HEAD -- plugins/` is non-empty (base = merge-base with the plan branch, falling back to HEAD~20 cap); when all three hold ⇒ emit `cache_preflight_skew_wip` event + a one-line stderr warning naming the skew and continue (return 0). The primary-checkout hard stop is untouched.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-cache-preflight.bats` — extend the existing suite: worktree fixture with a plugins/ diff ⇒ warning + rc 0 + event; worktree WITHOUT plugins/ diff ⇒ hard stop preserved (real staleness in a worktree is still caught); primary checkout with skew ⇒ hard stop unchanged; `AID_CACHE_PREFLIGHT_OVERRIDE=1` behavior unchanged.

**Architecture Context:** Seam 3. Grounded: the dogfood reference resolves to the WORKTREE's own plugins copy (:132-145 uses the invocation toplevel), so a plugin-modifying EPIC always "skews" against itself — a false positive by construction. The check's purpose (controller running stale cached scripts) is preserved: the cache-vs-primary comparison still guards the primary checkout, and a worktree with NO plugin changes still hard-stops.

**Implementation Detail:** The three-condition guard is deliberately conjunctive and cheap (two git plumbing calls + one diff name-only). The event carries running/dogfood hashes exactly like the hard-stop event so telemetry keeps the same fields. The warning text names the diff summary (`N files under plugins/ differ — this is the EPIC's own work; cache check downgraded`).

**Error Handling:** Any of the three detection commands failing ⇒ fall through to the existing hard stop (fail closed — never downgrade on uncertainty).

**Edge Cases:**
- A worktree EPIC that modifies plugins/ AND runs from a genuinely stale cache — the downgrade masks it for this run; accepted and documented in the lib header (the run's own gates execute the tree's scripts; the cache risk window is controller tooling only, and the primary checkout stop still fires for every non-worktree invocation).
- Detached-HEAD worktree state — merge-base fallback path; if base resolution fails entirely, condition 3 is false ⇒ hard stop (fail closed).
- `.aid-worktrees` path customization — the convention match uses the recorded plan-state worktree_path when resolvable, path-glob only as fallback.
- Self-application: this plan's OWN EPIC 1 runs in `.aid-worktrees/plan-P079` BEFORE this step lands (it is in EPIC 2) — EPIC 1's controller is expected to use the documented `AID_CACHE_PREFLIGHT_OVERRIDE=1` relief for its own runs, recorded in the run timeline; the first run after this step merges must NOT need it (assert in the step verify output).

**Dependencies:**
- Depends on: none
- Blocks: Step 13 — registry row update for the preflight.

**Acceptance Criteria:**
- [ ] Four bats cases pass; the no-plugins-diff worktree case proves real staleness still stops.
- [ ] Event `cache_preflight_skew_wip` present with both hashes in the WIP fixture's timeline.
- [ ] Hard-stop message byte-identical for the primary checkout path.

**Effort:** S
**AID Role:** backend

### Step 9: Prefilter seeding is one rule, stated once

**Objective:** The classify/seed behavior is identical for every step — the instruction says so, and a regression pins it (IMP-474).

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~770-780) — prefilter section (classify site at :775 post-merge), one explicit rule: the controller runs `aid-prefilter.sh classify <N> <evidence_dir>` for EVERY step before verifier dispatch — no step-0 special case exists; the seed file `verifier-output-step-<N>.md` is always classify's product, and a verifier finding no seed means classify was skipped (name the recovery: run classify, then re-dispatch).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-prefilter.bats` — pin: classify with N=0 and N=3 produce identically-shaped seed files (same fields, same `_generated_by`); classify is idempotent on re-run (existing verdict overwritten only by the documented rules).

**Architecture Context:** Seam 3. Grounded: no code defect exists (A15 — no step-0 special case anywhere; the observed seed came from a manual invocation). The inconsistency was a controller-behavior artifact; the fix is the instruction stating the invariant plus a shape-pin so any future seeding change is caught.

**Implementation Detail:** The pipeline.md edit is ≤5 lines in the existing prefilter block. The bats shape-pin compares field sets, not bytes (timestamps differ).

**Error Handling:** None new — classify's own error paths unchanged.

**Edge Cases:**
- SKIP-classified step (verdict placeholder `skip`) — shape identical, pinned.
- Re-classify after a fix loop — existing overwrite semantics preserved, pinned as-is.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] Both bats cases pass.
- [ ] pipeline.md states the every-step rule and the no-seed recovery in the prefilter section.

**Effort:** S
**AID Role:** docs-writer

### Step 10: Released versions are sealed against the release script

**Objective:** `aid-release.sh` can never retitle a CHANGELOG heading whose version is already tagged, and the two CHANGELOGs get the byte-identity test that was assumed to exist (IMP-482).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` — guard BOTH retitle sites: in `update_changelog` before the sed (:468) and in the no-config fallback before its sed (:577): if `git -C "$REPO_ROOT" tag -l "v${CURRENT}"` is non-empty ⇒ the entry is sealed — do NOT retitle; instead prepend a fresh `## [$NEW_VERSION] — $TODAY` block (the existing :471-486 prepend branch) and print one line naming the seal (`v$CURRENT is tagged — heading preserved, new entry prepended`); when the tag lookup itself fails (not a git repo), fail closed with the manual instruction rather than guessing.
- Modify: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — add the missing byte-identity assertion: the `## [<NEW_VERSION>]` SECTION BODY (heading to next `## [`) of root and plugin CHANGELOGs must be identical (the repo rule "always identical" finally gets its test — header-equality alone stays too).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-seal.bats` — fixture repo with tagged v1.0.0 at CHANGELOG head: release to v1.0.1 prepends a new heading and v1.0.0's line is byte-unchanged; untagged current version still retitles (existing behavior preserved); the no-config fallback path exercised the same way; non-git fixture fails closed.

**Architecture Context:** Seam 3. Grounded mechanism (B2-B6): the `Unreleased` skip is a side effect of the numeric regex, and the retitle sed exists twice; grounded absence (B8): no identity test exists — only header-equality. Immutability rule: a tagged version is history; tools append, never rewrite.

**Implementation Detail:** The guard is one function `_release_version_sealed <ver>` used at both sites (tag lookup + rc discipline). The prepend branch already generates the placeholder body (:480) that the P073 entry-completeness gate (:624-705) then refuses to release unfilled — the two mechanisms compose: seal forces prepend, completeness forces a real entry. The identity assertion extracts both section bodies with awk and `cmp`s them.

**Error Handling:** Tag lookup in a repo with no tags at all returns empty ⇒ not sealed ⇒ existing behavior (correct for greenfield projects). Fixture-non-git fail-closed message names the manual step (set the heading by hand).

**Edge Cases:**
- CHANGELOG head already hand-set to NEW_VERSION (the P076 case, grounded B10) — the header==NEW_VERSION no-op branch (aid-release.sh:463-466) fires first; seal guard never reached; pinned in bats.
- Tag exists but heading absent (CHANGELOG rewritten historically) — the :471 prepend branch fires as today; seal guard is a no-op there by placement.
- `RELEASED_VERSION`-style env overrides — unaffected; the guard keys on CURRENT only.

**Dependencies:**
- Depends on: none
- Blocks: Step 13 — registry row; Step 14 — this repo's own release runs through the sealed path.

**Acceptance Criteria:**
- [ ] All four bats cases pass; tagged-heading byte-unchanged proven by cmp in the fixture.
- [ ] verify-version-files.sh fails when the two CHANGELOG section bodies differ (negative fixture).
- [ ] `grep -c '_release_version_sealed' plugins/aid-orchestrator/scripts/aid-release.sh` ≥ 3 (definition + two sites).

**Effort:** M
**AID Role:** backend

**EPIC 3: Steps 11-14 — Test quality, tuning, release**

### Step 11: The vacuous-green checks join the content scanner

**Objective:** The mechanical subset of the "green test that checks nothing" pattern is detected by the shipped test-content scanner, and the authoring rule is written where test authors read (IMP-481).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-content-scan.sh` — two new deterministic checks joining the scanner's existing check family: (a) `set_e_grep_count` — a `grep -c` invocation in a plain `.sh` suite under `set -e` context without a `|| true`/`|| echo` guard and outside a bats `run` wrapper; NOTE the scanner's current universe does NOT enumerate plain `.sh` suites at all (aid-test-content-scan.sh:58-74 globs bats/py/ts only), so this check ALSO adds the `scripts/tests/test-*.sh` enumeration — named work, not free; and the originally-grounded targets (test-run-gates.sh:105/:107) are run-wrapped and thus correctly NOT flagged — the implementer re-grounds the live target set before pinning any count; (b) `existence_keyed_skip` — a `skip` guarded by target-file existence (`[[ -f ... ]] || skip` / `[ -f ... ] || skip`), reported with file:line (grounded: 5 live instances). Both emit under content-scan.json's ACTUAL shape — new named keys under the top-level `checks:` map plus `summary:` counters (there is no findings array) — exit-0-with-findings semantics unchanged, and each new check block carries its own try/except (the per-check isolation is conventional, not structural).
- Modify: `plugins/aid-orchestrator/scripts/README.md` (lines ~666-700) — Testing section: the authoring rule, four sentences: a test must FAIL when its subject is absent; skip is legal only when counted and rendered as skipped, never as passed; an assertion must read a different surface than the one that wrote the claim; `grep -c` under `set -e` needs a guard because zero matches exits 1 before printing.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-content-scan.bats` — extend: fixture suites containing each pattern are flagged with correct file:line; guarded `grep -c || true` and legitimate env-keyed skips are NOT flagged (false-positive pins).

**Architecture Context:** Seam 3. The scanner is the shipped, audit-integrated host for exactly this check class (grounded B30 — deterministic, no LLM, exit-0-with-findings); adding checks there means the findings flow through the existing audit report rendering with zero new plumbing. The audit-family ownership note: these two checks are content checks on test FILES, independent of the parallelism machinery being removed — no dependency either way.

**Implementation Detail:** Check (a) parses per-file: track `set -e` presence (shebang region), then flag `grep -c` lines lacking a `||` guard on the same line and not preceded by `run ` — regex-level, deliberately conservative (miss rather than false-positive; the authoring rule covers the rest). Check (b) flags the two grounded skip shapes; an allowlist comment `# content-scan: allow existence-skip — <reason>` on the preceding line suppresses with the reason captured in the finding as suppressed:true.
The five grounded live instances are NOT fixed in this step (they belong to suites the parallelism removal may delete); the scanner reports them and the removal/next audit decides — recorded in the step verify output.

**Error Handling:** Scanner-internal errors keep the existing per-check isolation (one check failing does not kill the scan; the finding notes the check errored).

**Edge Cases:**
- bats files (no `set -e` context) — check (a) skips `.bats` entirely.
- Multi-line command with `grep -c` on a continuation line — out of conservative scope, documented.
- A skip keyed on an env var or platform — not flagged (only file-existence shapes).

**Dependencies:**
- Depends on: none
- Blocks: Step 13 — registry row.

**Acceptance Criteria:**
- [ ] Extended scanner bats pass, including both false-positive pins.
- [ ] Running the scanner over the live tree reports the re-grounded instances (the 5 existence-keyed skips at minimum; the set_e_grep_count total pinned only AFTER re-grounding) — quoted in verify output.
- [ ] README authoring rule present with all four sentences.

**Effort:** M
**AID Role:** qa

### Step 12: shell_pipeline_smoke tuned from the measurement, heaviest suites delegated

**Objective:** The plan-final broad gate gets a cap derived from the real uncapped measurement, background ownership, and loses the ~25 min of P076 process suites to delegated CI jobs (IMP-483).

**Files:**
- Modify: `.aid-o/config/execution.yaml` — `shell_pipeline_smoke` gate entry: `timeout_seconds` set from the collected `shell-pipeline-measure` result via the shipped arithmetic (max(measured×1.5, measured+60 s), rounded up to the minute — the rounding-to-minute is this plan's choice, noted as such in the config comment; the measurement is collected with `aid-job.sh collect --jobs-dir <measure_jobs_dir> --id shell-pipeline-measure` — BOTH flags are mandatory (aid-job.sh:498); the original jobs dir lives in the other session's /tmp scratchpad recorded in E-076-1_3 evidence and may be gone — and its duration + exit code quoted in the step verify output); add `run_mode: background` (the P076 field, matching bats_all/bats_boundary precedent at p076 execution.yaml:61/:86); comment records the measurement date, duration, exit code and this plan id.
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` — `DELEGATED_SUITES` (:141-157) gains three entries: `test-aid-service.bats -> service-lib-tests`, `test-service-lifecycle.bats -> service-lifecycle-tests`, `test-p076-integration.bats -> p076-integration-tests`.
- Modify: `.github/workflows/ci.yml` — three new CI jobs matching the delegation names, each running exactly its suite, added ALONGSIDE the existing delegated jobs in the SAME file (plan-boundary-tests at :56, plan-final-tests at :87, isolation-experiment-tests at :118 — mirror their shape; a second workflow file would split delegation ownership); one grep-check in the step verify output proves every DELEGATED_SUITES value has exactly one matching job name across the workflows dir (the no-suite-silently-unowned assertion from the backlog entry).
- Test: `plugins/aid-orchestrator/scripts/tests/test-run-all-delegation.sh` — asserts the three suites are skipped inline with the DELEGATED report line and that every DELEGATED_SUITES value appears in exactly one workflow file.

**Architecture Context:** Seam 3 / IMP-483 both halves. The recommendation arithmetic is the baseline lib's own (`_gbr_calc_timeout_rec`, grounded B25) applied to the one honest sample; `run_mode: background` engages P076's owned-job path so future plan-finals re-attach instead of blocking. Delegation follows the shipped precedent exactly (grounded B20-B21: map + skip + DELEGATED report). Explicit non-goal restated: no parallelism — placement and ownership only.

**Implementation Detail:** If the measurement job's exit code is non-zero (the suite genuinely fails), the cap is still set from its duration but the step verify output flags the failure for the PM — a failing suite is a different problem than a slow one and must not be hidden by this step. The workflow jobs use the same runner/setup steps as the boundary-tests job; each job's run line is `bats plugins/aid-orchestrator/scripts/tests/bats/<suite>`. Delegated suites remain discoverable by the ledger emission (unit ids unchanged).

**Error Handling:** Measurement job missing/lost at implementation time (collect fails) ⇒ the step falls back to a fresh measured run — exact SELF-CONTAINED command (aid_state_root is a lib function, not an executable, so it must be sourced first): `source plugins/aid-orchestrator/scripts/lib/aid-roots.sh && bash plugins/aid-orchestrator/scripts/aid-job.sh run --jobs-dir "$(aid_state_root)/.aid-o/work/measure" --id shell-pipeline-measure-2 --deadline 21600 -- bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (a durable state-root jobs dir, never /tmp) — and waits on it; never guesses a number; the fallback command AND its resolved jobs dir are quoted in the verify output if taken.

**Edge Cases:**
- Measurement duration under the old p95 (suites got faster post-delegation-decision ordering) — arithmetic still applies; the comment records both numbers.
- A delegated suite renamed/deleted by the parallelism removal later — the delegation test fails naming it, which is the desired loud signal for that plan to update the map.
- run_mode background on a gate the baseline lacks 5 samples for — the field is a declaration, not a recommendation-consumer; P076's validate_all_run_modes accepts it (grounded B28).

**Dependencies:**
- Depends on: Step 2 — background gate runs write evidence through the resolved paths.
- Blocks: Step 14 — release notes cite the new cap.

**Acceptance Criteria:**
- [ ] execution.yaml gate entry carries the measured cap + run_mode: background + provenance comment.
- [ ] Delegation test passes; inline run-all no longer executes the three suites; DELEGATED lines list all three with owners.
- [ ] Verify output quotes the measurement duration and exit code.

**Effort:** M
**AID Role:** backend

### Step 13: Registry, backlog annotations, contributor docs

**Objective:** Every new mechanical refusal is registered, every consumed IMP entry is annotated, and the aftermath layer is documented for contributors.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — new rows (type/source/instruction/severity/surface/test per schema): `advance_to_gates_worktree_redirect`, `gate_runner_state_root_paths`, `task_branch_freshness`, `files_bullet_silent_drop`, `carried_obligations_block_close`, `routed_findings_block_done`, `cache_preflight_wip_downgrade`, `release_version_sealed`, `content_scan_vacuous_green` (one row covering both checks); update `increment_result_pass` (done in Step 4) and `init_idempotency`-adjacent rows only if their cites moved; totals recomputed per the file's own command.
- Modify: `docs/plans/2026-06-29-BACKLOG.md` — each of IMP-472..483 gains a status line `**Plan written: P079** (2026-08-09)`; IMP-473's entry notes the minimal-core/deferred split; IMP-483 notes both halves delivered.
- Modify: `docs/extending-aid.md` — one new section "The aftermath layer (P079)": the worktree seam contract (which commands redirect, which paths resolve where), the obligations/routed-findings journals and their consumers, the release seal, the vacuous-green checks — each with its "Adding to this area" note, placed after the P074 section per the file's chronology.
- Test: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-scheduler.sh` — extend the registry-family test (or its nearest sibling) to assert the nine new row ids exist with non-empty test fields.

**Architecture Context:** The CLAUDE.md mandate (register + document every enforcement) executed in one step, after all mechanisms exist. Registry rows use the block style for prose-heavy entries (precedent rows ~1456+).

**Implementation Detail:** Row sources cite post-merge file:line; instruction fields point at the pipeline.md/README sites written in earlier steps. The backlog annotation is one line per entry, never rewriting the entry bodies (append convention).

**Error Handling:** Totals recompute mismatch fails the registry tests — run them in this step's verify.

**Edge Cases:**
- Registry renumbering collisions from the parallelism-removal session editing the same file — annotations reference IMP ids by number AND title line, so a renumber is detectable at merge.
- P078's future cite-validation test — the rows written here must pass it; file paths only, no line anchors in `test:` fields.
- The registry totals comment drifting because another session added rows between Step 4's edit and this one — always recompute from the file's own command in THIS step, never carry a number from an earlier step's run.

**Dependencies:**
- Depends on: Step 1, Step 2, Step 3, Step 4, Step 5, Step 6, Step 7, Step 8, Step 10, Step 11 — registers what they built.
- Blocks: Step 14.

**Acceptance Criteria:**
- [ ] Registry tests pass with nine new rows; totals match the recompute.
- [ ] All twelve IMP entries carry the Plan written annotation.
- [ ] extending-aid.md section present with four subsections.

**Effort:** M
**AID Role:** docs-writer

### Step 14: Release

**Objective:** The fixes ship as one release with synchronized version surfaces, through the newly sealed release path.

**Files:**
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — identical new entry per the repo format (Added: obligations + routed-findings carriers, vacuous-green checks, chain freshness guard; Fixed: advance-to-gates redirect, gate-runner paths, verdict casing, silent bullet drops, cache-preflight WIP, release seal; Changed: shell_pipeline_smoke cap + background + delegation). Version chosen from the then-current post-P076 head (expected 2.80.x → this is 2.81.0: new mechanisms, no breaking change).
- Modify: `.claude-plugin/marketplace.json` + `plugins/aid-orchestrator/.claude-plugin/plugin.json` + `plugins/aid-orchestrator/README.md` + `README.md` — the remaining version registry locations per CLAUDE.md's 8-location table; README roadmap updated (3 most recent versions).
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — full pass including the new byte-identity assertion from Step 10.

**Architecture Context:** Standard release workflow; this release itself exercises Step 10's seal (the 2.80.x heading below is tagged by then — the prepend path must fire, which is a live validation of the fix).

**Implementation Detail:** Release commit `release: v2.81.0 — the run can trust its own tree`; tag + GitHub release + plugin cache refresh in consumer projects per CLAUDE.md. The version number is read from the actual head at implementation, never hardcoded from this plan. ORDERING (so the seal is actually exercised): run `aid-release.sh` FIRST — the sealed 2.80.x heading forces the prepend branch, producing the new placeholder heading — and only THEN fill the placeholder with the real entry content (the P073 completeness gate refuses an unfilled release); hand-writing the v2.81.0 entries before the script would trigger the header==NEW_VERSION no-op (aid-release.sh:463-466) and the seal guard would never fire, contradicting the live-validation claim.

**Error Handling:** verify-version-files failure blocks the push (existing pre-push discipline); any drift found is fixed before tagging, never after.

**Edge Cases:**
- Another release landed between P076's and this one — bump from the actual current version; CHANGELOG entry position adjusts.
- The parallelism-removal plan releasing concurrently — serialized by PM ordering (this plan first); if violated, the version read-at-head rule absorbs it.

**Dependencies:**
- Depends on: Step 12, Step 13 — releases what they finished.
- Blocks: none — terminal step.

**Acceptance Criteria:**
- [ ] All 8 version locations agree; verify-version-files.sh passes including byte-identity.
- [ ] Both CHANGELOG entries identical; tag pushed; cache refresh command output quoted in verify output.

**Effort:** S
**AID Role:** release

## Testing Strategy

- Every mechanical fix ships with bats/harness coverage reproducing the LIVE incident shape (worktree gate run, stale chain branch, uppercase verdict, dropped bullet, erased obligation, tagged-version retitle) — regression by reproduction, not by description.
- New suites follow the naming convention (auto-discovered); the three delegated suites get a dedicated delegation test.
- Frozen surfaces (machine outputs, evidence filenames, fsm-state fields) pinned by negative assertions in the affected suites.
- One combined pass of all touched suites in Step 13's verify; the full broad suite runs at this plan's own plan-final under the NEW cap — which is itself a live validation of Step 12.

## Constraints

- **Sequencing (hard):** implementation starts only after P076 merges to main. All p076: anchors are the post-merge shape; every step re-verifies anchors by quoted code before editing. This plan lands BEFORE the parallelism-removal plan (PM order 2026-08-09) — that plan rebases on these fixes.
- No parallel test execution anywhere (cancelled line); IMP-483 is placement/ownership only.
- Frozen compatibility surfaces read-only: current_step semantics, verify-state JSON, evidence filenames, fsm-state field set (base_commit VALUE selection changes in Step 3; the field itself is unchanged).
- The gate runner's command-execution cwd contract is preserved (commands run in the invocation tree); only state writes move.
- No new runtime dependencies (bash, jq, yq, awk, git — all existing).
- Language split: plan document English; PM conversation Czech.

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Gate-runner path rewrite breaks a fixture relying on cwd-relative defaults | Medium | High | The documented fallback idiom preserves no-git-repo behavior; full gate suite in Step 2 AC |
| Fast-forward logic corrupts a checked-out task branch | Low | High | ff-only via the worktree when checked out; refusal on divergence; crash-idempotent CAS |
| P076 merge shifts anchors beyond recognition | Medium | Low | Both-tree grounding with quoted code; anchor-by-content rule in Constraints |
| done-advance refusal (Step 7) blocks a legacy run unexpectedly | Low | Medium | Absent-journal no-op is the default path; bats pins byte-identical legacy behavior |
| Measurement job lost before Step 12 | Medium | Low | Explicit re-measure fallback with the same deadline; never a guessed cap |
| Registry edits collide with the parallelism-removal session | Medium | Low | PM-ordered serialization; id+title annotations make renumbering detectable |

## Success Criteria

1. A worktree plan's gate run executes in the worktree, writes evidence to the state root, and reports the worktree's HEAD — proven by the combined bats scenario.
2. A chained EPIC's tree contains its predecessors' merged work at execution start, or the start refuses loudly.
3. `verdict: PASS` costs nothing; a dropped Files bullet stops generation by name.
4. An open release-blocking obligation or routed finding mechanically blocks close/done-advance until resolved or registered.
5. A tagged version heading survives every release run byte-identical; the two CHANGELOGs are provably identical per entry.
6. The plan-final broad gate has a measured cap, background ownership, and runs ~25 min lighter inline with every delegated suite owned by exactly one CI job.

## Acceptance Criteria

- [ ] AC1 — Worktree gate correctness end to end.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-run-gates-worktree-paths.bats"
  expected_exit: 0
```
- [ ] AC2 — Chain freshness guard.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-epic-chain-freshness.bats"
  expected_exit: 0
```
- [ ] AC3 — Case-tolerant verdicts (targeted cases in the FSM suite).
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"
  expected_exit: 0
```
- [ ] AC4 — Obligations journal blocks close.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-obligations.bats"
  expected_exit: 0
```
- [ ] AC5 — Routed findings block done-advance.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-routed-findings.bats"
  expected_exit: 0
```
- [ ] AC6 — Release seal.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-seal.bats"
  expected_exit: 0
```
- [ ] AC7 — Delegation owned and skipped inline.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-run-all-delegation.sh"
  expected_exit: 0
```
- [ ] AC8 — No silent Files-bullet drop remains.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-epic-to-json-regression.sh"
  expected_exit: 0
```

## Next Steps

1. `aid-plan-lint.sh` + `aid-generation-readiness.sh --total 3`; repair diagnostics.
2. CP1 verifier (write-mode Step 9) with the evidence protocol; risk: high (fsm/state patterns) ⇒ CP1-deep + C0 Codex loop at generation time, standing budget policy (5 attempts, then PM force).
3. Generate EPICs after P076 merges (chain mode); implement in `.aid-worktrees/plan-P079`.
4. Hand-off note to the parallelism-removal session: rebase on P079; the delegation map and content-scan checks name the suites it may delete.
