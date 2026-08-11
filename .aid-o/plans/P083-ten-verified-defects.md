---
id: P083
type: plan
status: draft
created: 2026-08-11
author: PM + AI
risk: high
---

# Plan: Ten Defects That Survived a Live-Code Sieve

## Stakeholder Brief

Forty-six open backlog entries were re-verified against the tree on 2026-08-11, one at a time, with file:line evidence for every verdict. Eleven turned out to be already fixed, moot or deliberate decisions. Thirty-three were real, but most were smaller than their descriptions and seven named the wrong file entirely. The PM then applied a second sieve by hand: keep only what repairs the pipeline we actually run today, only where the benefit is demonstrable, and prefer removing machinery to adding it. Ten items survived. Four of them break something on the path we use every day — a gates report written where nobody reads it, acceptance criteria cut mid-sentence, a release rollback that strands one file, a README frozen at v2.69.0. Three are guards that report success while checking nothing, including one that fails open in production library code. Three are open decisions where both answers are cheap, and the plan's job is to decide them with evidence rather than carry them another month. Nothing here adds a new detector, a new event or a new ceremony; five of the ten steps delete code or narrow a contract.

## Context

Source: `.aid-o/work/evidence/backlog-verify-2026-08-11/block-{1..7}.md` — seven independent verifications of `docs/plans/2026-06-29-BACKLOG.md` against `main` at v2.83.1, each required to open the code first-hand and forbidden to accept an entry's paraphrase.

That method was chosen because the previous approach failed publicly. Plan P082 was written from the backlog's own descriptions of the surviving entries; its CP1-deep review returned **fail with 15 accepted blockers**, seven of twelve steps grounded against code that does not exist, is not the runtime path, or reverses a documented deliberate decision. P082 is superseded by this plan and must not be generated. Its review evidence stays at `.aid-o/work/evidence/P082/` as the record of why this plan is written differently.

Three verification results deserve recording because they changed what is worth doing:

- The `gate_profiles` entry named `defaults/execution.yaml`, which has **no runtime reader at all**. The real defect is one function away and has a different shape: `render_gate_profiles_block` emits two of five canonical profiles and never `release`, while shipped policy sets `plan_final_profile_floor: release`. A consumer therefore flips to `plan_branch` and then hard-fails at `plan-finalize`.
- IMP-491 was reproduced end to end in a throwaway clone, and the reproduction surfaced the fact nobody had written down: `.aid-o/config/project.yaml` is gitignored, so **every worktree and clone takes the buggy fallback path** — which is the live plan-final release path, not a hypothetical one.
- The `grep -oP` portability guard sees 4 of 13 live PCRE call sites. One of the nine it cannot see is `lib/aid-review-signals.sh:24-25`, production library code whose `if` collapses to "enabled" when PCRE is unavailable — a config-honouring toggle that silently ignores `enabled: false`.

## Goal

The ten verified defects are fixed or consciously deleted, each with a regression that pins the specific behaviour the verification observed, and the backlog reflects the verification's verdicts.

## Scope

**In scope:**
- Four live-path repairs: the streamlined integration-review gates-report path; the EPIC generator's acceptance-criteria line filter; the release rollback's incomplete file bookkeeping; the README version updater.
- Three guards that pass without checking: the self-host `plan_diff` gate with no `command`; the fail-open PCRE toggle read in `aid-review-signals.sh`; the consumer profile table that cannot satisfy its own policy floor.
- Three decide-or-delete items: the dead parallel-concurrency vocabulary in the gate-runtime baseline; the C0 plan-review's dependency graph that is always produced after the review it feeds; the test catalog's root `status` that gates every catalog-derived audit command.
- Backlog reconciliation for exactly these ten entries plus the eleven the verification closed.

**Out of scope:**
- The 22 verified-real entries the PM's sieve rejected. They stay in the backlog with their verification verdict recorded, so a later reader sees "verified real, deliberately not scheduled" rather than "unexamined".
- IMP-261 (model/effort configuration), IMP-490 (legal force past a dead stage), IMP-471 (standing whole-plan auto-GO), OBS-20260702-07 (generation supersede cleanup), IMP-487 (visual-companion service migration) — each is its own plan.
- IMP-495 (rendered decision card) — P080 EPIC 3 already covers the substance; only the refusal-without-options half would be new, and it is pointless before P080 lands.
- Widening the `grep -oP` detector itself. Step 6 fixes the one production call site that fails open. Making the guard see all 13 sites adds machinery the PM's sieve rejected; it stays in the backlog with the count recorded.
- Anything in `commands/aid-init.md`, `skills/` help surfaces or `defaults/templates/` — P080 is live in `.aid-worktrees/plan-P080` and owns those files.

## Approach

Chosen: **ten independent fixes, each pinned by a regression that reproduces the verification's own observation**, grouped so that each EPIC is separately releasable. The grouping is by who is hurt and how loudly: first the four that break a run we do today, then the three that report success while verifying nothing, then the three decisions.

Alternatives rejected: (a) one "guard hardening" refactor — the verification shows these fail for unrelated reasons (a flat path constant, a line-filter regex, missing array bookkeeping, a missing config key); coupling them would couple ten independent risks; (b) scheduling all 33 verified-real items — the PM's sieve exists precisely because most of them do not repair anything we run; (c) fixing the guards by widening their detectors — that adds machinery, and the sieve's stated rule is to prefer removal.

**Every step's Files list names a line range the verification opened.** Where a step's premise came from a review rather than from a first-hand read, the step says so and its first task is to re-confirm.

## Architecture

Three groups.

1. **The live path (Steps 1-4).** `fsm_check_streamlined_integration_review` reads a flat `gates_report.json` while every writer and every other reader uses the `gates/` subdirectory, so a correct streamlined run is pushed toward a force waiver. `aid-plan-to-epic.sh` filters acceptance criteria to flush-left bullet lines in two copy-pasted awk blocks, so continuation lines vanish from both the human EPIC and the machine-read `ac[]`. `_release_update_files`' fallback path omits three files from `UPDATED[]`, and `_release_rollback_updated` restores only what that array holds. The README updater substitutes a version token with no notion of the structure it edits.
2. **Guards that pass without checking (Steps 5-7).** A gate with no `command` records `skip/no_command` and never touches `overall`; `plan_diff` sits in four merge-path profiles in exactly that state. A `grep -qP` inside an `if` returns "enabled" on any grep without PCRE. A profile table that omits `release` cannot satisfy a policy floor of `release`.
3. **Decide or delete (Steps 8-10).** Each of these three has two acceptable answers and the plan commits to one with evidence: dead vocabulary is deleted; a graph produced after its consumer is either produced earlier or stops being claimed; a catalog whose root status silently disables every catalog-derived command is either approved or the gating is removed with the audit.

## Implementation Steps

**EPIC 1: Steps 1-4 — What breaks on the path we run today**

### Step 1: The streamlined integration review reads the gates report where gates write it

**Objective:** A streamlined-mode EPIC that passed its gates advances from review to release without a force waiver.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~1817-1845) — `fsm_check_streamlined_integration_review` reads `${evidence_dir}/gates/gates_report.json`, the path every writer and every other reader already uses, and accepts the flat sibling only as an explicitly-logged legacy fallback so an in-flight run started before this change still advances.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-streamlined-integration-review.bats` — a streamlined run whose report sits at the canonical path passes the precondition; one with no report at either location still fails with the existing named message; a report at the legacy flat path passes and logs that it took the fallback (tier: t1).

**Architecture Context:** Group 1. The one outlier against seven agreeing readers and one writer default, verified at `aid-run-gates.sh:1628-1629` (writer), `aid-fsm.sh:2453,2880,2991,3286,5262` plus `aid-diagnostic.sh:57` and `aid-compliance-backfill.sh:103` (readers), and `commands/aid-run.md:211` / `skills/pipeline.md:1115,1135` (documentation).

**Implementation Detail:** The precondition is called from `cmd_done_advance` at `aid-fsm.sh:6608` when `streamlined_mode: true`. The failure message at `:1834-1836` names the evidence directory, which is why the mismatch reads as "no report" rather than "wrong path" — the message must name the path it actually looked at, in both branches.

**Error Handling:** A report present at both paths uses the canonical one and logs the duplicate; it never silently prefers the stale copy.

**Edge Cases:**
- Report at the flat path only (an in-flight run) — accepted, with the fallback recorded in the log line, not silently.
- Report present but unparseable — the existing invalid-JSON behaviour is unchanged; this step moves a path, not a parser.
- Non-streamlined runs — untouched; the precondition is not reached.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] A streamlined run whose gates wrote to `<evidence>/gates/gates_report.json` advances `done-advance review release` without `--force`.
- [ ] A run with no report at either path still fails, and the failure message names both paths searched.
- [ ] The legacy flat path is accepted and its use appears in the run log.

**Effort:** S
**AID Role:** backend

### Step 2: Acceptance criteria keep their continuation lines

**Objective:** A multi-line acceptance criterion reaches the EPIC and the machine-read `ac[]` whole.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (lines ~909-949) — the two copy-pasted awk blocks (`step_ac` at :909-925 feeding the flattened section, `step_ac_raw` at :936-949 feeding the per-step `ac[]`) are replaced by calls to one shared extractor, so a fix cannot land in one copy and leave the other divergent.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-ac-extract.sh` — the shared extractor: a criterion begins at a flush-left `- ` bullet and continues through indented lines until the next flush-left bullet or the section terminator; continuation lines are joined with a single space.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-ac-extraction.bats` — the P068 Step 2 criterion the verification reproduced comes out whole in both the prefixed and unprefixed forms; a single-line criterion is byte-identical to today's output; a criterion followed by a `**`-prefixed terminator stops there; the two call sites produce the same criterion set (tier: t1).

**Architecture Context:** Group 1. Verified by running the `:909-925` block verbatim against the entry's own example: output ends mid-sentence at "has a matching", and the three continuation lines carrying the binding rule vanish. The same truncated text lands in `ac[]`, so C3's AC lenses verify against a criterion that no longer states its own requirement.

**Implementation Detail:** The cause is a line filter (`if (in_ac && $0 ~ /^-[[:space:]]/)`), not a truncation: indented lines match neither the emit test nor the `^\*\*` terminator. The backlog entry's pointer to `lib/aid-scoping.sh::_aid_extract_*` is wrong — those handle Files bullets — and this step's first task is to leave a comment at that spot saying so, because the wrong pointer is what makes the next reader edit the wrong file.

**Error Handling:** A continuation line that itself looks like a new section heading terminates the criterion rather than being absorbed; the ambiguity is resolved toward under-joining, never toward swallowing the next section.

**Edge Cases:**
- A criterion whose continuation contains a code span with a leading dash — joined, not split (pinned).
- An empty line inside a criterion — terminates it; plans use blank lines between criteria.
- Existing single-line plans — output byte-identical, asserted against the current suites.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] The reproduced P068 criterion emerges whole from both extraction paths.
- [ ] Both call sites produce identical criterion sets for the same plan.
- [ ] Every existing plan-to-epic suite stays green with byte-identical output for single-line criteria.

**Effort:** S
**AID Role:** backend

### Step 3: A rolled-back release leaves no file on the new version

**Objective:** An aborted release restores every file it touched, including the ones the fallback path forgets.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~645-681) — the `.metadata.version` branch (:651-656, comment `# Don't double-add`), the `.plugins[0].version` branch (:657-662) and the README `Plugin: ` branch (:672-675) record their file in `UPDATED[]` exactly once, so `_release_rollback_updated` (:775-791) restores them; the "Updated N files total" count at :681 is derived from the same array it restores from, so the printed count and the rollback set can never disagree again.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-rollback.bats` — a prepare run aborted by a CHANGELOG validation failure leaves `git status --porcelain` empty; the printed file count equals the number of files actually restored; a file whose content already matched the target version is not double-added (tier: t1).

**Architecture Context:** Group 1. Reproduced first-hand in a clone: the run printed seven `Updated:` lines and "Updated 4 files total", then rolled back four files, leaving `.claude-plugin/marketplace.json` at 2.83.2 while everything else returned to 2.83.1.

**Implementation Detail:** The verification's most important finding is why this bites in production and not in the main checkout: `_release_update_files` has a config-driven path (:544-598) and a fallback (:599-677); the config path reads `.aid-o/config/project.yaml`, which is gitignored, so **any clone or worktree takes the fallback** — and plan-final releases run inside plan worktrees. The regression must therefore exercise the fallback path explicitly, not the config path.

**Error Handling:** A file that cannot be restored is a loud failure naming the file and the version it is stranded at; a partial rollback that reports success is the exact defect being fixed.

**Edge Cases:**
- A file listed by config and by fallback — added once (the `# Don't double-add` intent is preserved, only its bookkeeping corrected).
- A rollback with an empty `UPDATED[]` — prints that nothing needed restoring, exit 0.
- A repo where `project.yaml` IS present — the config path is unaffected and its existing suites stay green.

**Dependencies:**
- Depends on: none
- Blocks: Step 4 — both edit the same fallback block and Step 4's test reuses this step's fallback fixture.

**Acceptance Criteria:**
- [ ] After an aborted prepare in a checkout without `.aid-o/config/project.yaml`, the working tree is clean.
- [ ] The printed "Updated N files total" equals the number of files the rollback restores.
- [ ] Existing release suites stay green.

**Effort:** S
**AID Role:** backend

### Step 4: The README version line is updated by structure, not by token substitution

**Objective:** A release updates the README version references it means to, and stops leaving them years behind.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` (lines ~660-677) — the fallback README updater edits the version list by its real heading rather than substituting a version token across every README within three levels; the anchor is discovered from the file (the root README's list lives under `## Changelog`, the plugin README carries a `- **Plugin:** X.Y.Z` line and no list at all), and a README with no recognisable anchor is skipped with a named warning rather than silently rewritten.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-readme.bats` — the repository's real README shape gains the new version at the top of its list; prose mentioning the previous version outside the list is untouched; a README with no anchor is skipped with the warning and exits 0 (tier: t1).

**Architecture Context:** Group 1, and the visible proof: `README.md:3` still reads v2.69.0 while main is at v2.83.1. The P082 review established that a "Roadmap" anchor does not exist in either README — writing to that heading would have skipped both files forever, which is why this step discovers the anchor rather than assuming one.

**Implementation Detail:** The config path (`project.yaml → versioning.files[]`, executed at :574-577) already does a regex substitution for this repo and is not the failing path in a worktree; this step fixes the fallback, and its test must run in a fixture without `project.yaml` for the same reason as Step 3.

**Error Handling:** No anchor found ⇒ warn, skip that file, continue the release. A release must not fail on a README that never had a version list, and must not guess where a line belongs.

**Edge Cases:**
- Both READMEs present with different shapes — each handled by its own discovered anchor.
- A list already containing the new version (a re-run) — no-op, matching the CHANGELOG's pre-written-entry behaviour.
- A version string inside a fenced code block — untouched, because only the anchored region is edited.

**Dependencies:**
- Depends on: Step 3 — same fallback block, and the fixture is shared.
- Blocks: none

**Acceptance Criteria:**
- [ ] A release run against the repository's real README shape updates the version list and leaves out-of-list prose untouched.
- [ ] A README with no anchor is skipped with a named warning and the release still succeeds.
- [ ] Re-running a release for the same version changes nothing.

**Effort:** S
**AID Role:** backend

**EPIC 2: Steps 5-7 — Guards that report success without checking**

### Step 5: `plan_diff` either checks the plan or leaves the profiles

**Objective:** The merge path stops carrying a gate row that verifies nothing.

**Files:**
- Modify: `.aid-o/config/execution.yaml` (lines ~218-228) — the self-host `plan_diff` gate regains the `command:` the shipped default has had all along (`defaults/execution.yaml:109-116`) and an explicit `required: true`; the self-expiring exemption note that still names "P038+" is replaced by the resolved decision with its date.
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~1944-1963) — a gate that appears in a profile's `include[]` with no `command` is a loud configuration refusal, not a `skip/no_command` row, so this cannot silently recur in any project.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-gate-command-required.bats` — a profile including a command-less gate fails the runner with a message naming the gate and the profile; a gate absent from every profile with no command is ignored; the shipped defaults pass unchanged (tier: t1).

**Architecture Context:** Group 2. Verified: `yq '.gates.plan_diff.command'` returns null on the self-host config while the gate sits in four merge-path profiles, and `aid-run-gates.sh:1953-1963` turns a null command into `skip/no_command` with `required` defaulting to false. Because `.aid-o/` is gitignored there is no history to say when the command disappeared — which is precisely why the runner-side refusal matters more than the config fix.

**Implementation Detail — decision made 2026-08-11, restore not remove.** Measured before writing this step: `aid-plan-diff.sh --plan <this plan> --evidence-dir <tmp> --base-commit HEAD` exits 0 and produces a valid `plan-diff.json`, and the machine-verifiable AC convention it executes is alive — P080 carries 8 `verification_pattern` blocks, P081 nine, P082 eight. The gate is therefore meaningful on every plan we currently write, and its `skip/no_command` row is a pure regression in the self-host config. The exemption note's own threshold ("meaningful for P038+") was reached 45 plans ago. Restoring it also closes OBS-20260702-09's heading concern, since `aid-plan-diff.sh:164` already accepts both `## Acceptance Criteria` and `## Success Criteria`.

**Error Handling:** The runner's new refusal names the gate, the profile and the config file — a misconfiguration must be actionable without reading the runner's source.

**Edge Cases:**
- A gate with a `command` but `required` absent — unchanged behaviour (advisory), since only a *missing command* is the new refusal.
- A consumer project whose config predates this change — the refusal fires on their first run with a message that says what to add; this is stated in the CHANGELOG as a breaking configuration check.
- `release_quarantine` — treated exactly as the other three profiles.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] No profile in this repository's own `execution.yaml` includes a gate without a `command`.
- [ ] The runner refuses, by name, a profile that includes a command-less gate.
- [ ] The "P038+" exemption note no longer exists in any form.

**Effort:** M
**AID Role:** backend

### Step 6: The config toggle stops resolving to "enabled" when it cannot be read

**Objective:** An explicit `enabled: false` is honoured on any grep, and a toggle that cannot be evaluated fails closed.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh` (lines ~20-30) — `_aid_read_toggle` uses a POSIX-portable match instead of `grep -qP`, and distinguishes "read the toggle, it says enabled" from "could not read the toggle": the unreadable case is a named failure, not a silent `return 0`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-signal-toggle.bats` — `enabled: false` disables on a grep without PCRE support (simulated by a stub grep that exits 2 on `-P`); `enabled: true` enables; an unparseable toggle fails closed with a named message rather than defaulting to enabled (tier: t1).

**Architecture Context:** Group 2. This is the one PCRE site the sieve kept, because it is production library code rather than tooling: on a grep without PCRE both `-qP` calls exit 2, the `if` is false, and the function returns 0 = enabled — the exact fail-open the no-`grep -oP` invariant was created to prevent, invisible to the guard that enforces it.

**Implementation Detail:** The other twelve live PCRE sites and the guard's own blind spots stay out of scope by the PM's sieve; this step records the verified count (4 of 13 seen, `.bats` never scanned, one allowlist row granting three slots to a file with none) in the backlog entry so a later decision has the numbers.

**Error Handling:** An unreadable or malformed toggle is a refusal naming the config key and file — never an implicit "enabled".

**Edge Cases:**
- Toggle absent entirely — the documented default applies, unchanged, and is asserted so this step cannot quietly change it.
- Toggle present with an unexpected value — refusal, not coercion.
- A grep that supports `-P` — behaviour byte-identical to today for every existing case.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] With a stub grep that rejects `-P`, `enabled: false` disables the signal.
- [ ] An unparseable toggle fails with a named message and does not resolve to enabled.
- [ ] Existing review-signal suites stay green on a PCRE-capable grep.

**Effort:** S
**AID Role:** backend

### Step 7: A fresh consumer's profile table can satisfy the policy floor it is held to

**Objective:** A project initialised by `/aid-init` reaches `plan-finalize` without hitting an empty `release` profile.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` (lines ~206-266) — `render_gate_profiles_block` emits the full canonical ladder (`quick < targeted < standard < full < release`) composed from the gates the project's detected stacks actually define, instead of the two profiles (`targeted`, `full`) the here-doc at :256-265 emits today; the zero-stacks branch at :239-242 is left exactly as it is, because its fallback to `legacy_epic_release_mode` is handled and audited.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-init-gate-profiles.bats` — a workspace composed with a detected stack yields all five profiles, each naming only gates the composed file defines, and `release` is non-empty; `gate_profile_max <anything> release` resolves against it; the zero-stacks branch still produces no table and the audited legacy fallback still fires with its named reason (tier: t1).

**Architecture Context:** Group 2, and the only step here motivated by other projects rather than by this one. Verified chain: shipped `plan-boundary-policy.yaml` sets `default_mode: plan_branch` and `plan_final_profile_floor: release`; a consumer with detected stacks gets `{targeted, full}`, so `_pfsm_has_gate_profiles` (`aid-plan-fsm.sh:9869-9880`) returns 0 and the plan flips to `plan_branch`; `aid-plan-fsm.sh:4485` then resolves at least `release` and `:4490-4493` aborts with "profile 'release' has an empty or missing include[]".

**Implementation Detail:** The recorded decision at `aid-plan-fsm.sh:9861-9868` — that P064 deliberately did not add the table to `defaults/execution.yaml` — is respected: this step does not touch that file. It fixes the composer, which is the path consumers actually take, and therefore does not reverse the decision the P082 review flagged.

**Error Handling:** A composed profile naming a gate the composed file does not define is a build-time failure in the new test, not a consumer's first-run surprise.

**Edge Cases:**
- Zero stacks detected — unchanged, still no table, still the audited legacy fallback.
- A stack whose gate set cannot populate `release` meaningfully — `release` includes what exists and the test asserts non-emptiness, not a fixed membership.
- An existing project re-running init — the additive-upgrade contract is unchanged; a project's own hand-written table is not overwritten.

**Dependencies:**
- Depends on: none
- Blocks: none

**Constraint:** this step must not be started while P080 holds `.aid-worktrees/plan-P080`; if that worktree is still live at EPIC 2 start, the step waits rather than editing around it.

**Acceptance Criteria:**
- [ ] A stack-detected workspace composed by `/aid-init` yields five profiles with a non-empty `release`.
- [ ] Every emitted profile names only gates the composed file defines.
- [ ] The zero-stacks path is byte-identical to today, fallback reason included.

**Effort:** M
**AID Role:** backend

**EPIC 3: Steps 8-10 — Three decisions, both answers cheap**

### Step 8: The parallel-concurrency vocabulary leaves the gate-runtime baseline

**Objective:** The baseline library stops reading as though a scheduler still existed.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-gate-runtime-baseline.sh` (lines ~319-591, plus :853 and the usage string at :874) — the acceptor at :329-333 narrows to `sequential`; the non-sequential branches at :401, :507-527, :535, :561 and :591 and the `*_by_context` assembly are deleted; the two map fields stay present-but-empty so a legacy baseline file still reads.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-gate-baseline-sequential-only.bats` — a legacy baseline containing `observe_parallel` samples reads without error and reports them under the sequential aggregate or ignores them by a stated rule; a non-sequential context argument is refused by name; the live baseline's numbers are unchanged before and after (tier: t1).

**Architecture Context:** Group 3, and a pure deletion. Verified: both producers hardcode `sequential` (`aid-run-gates.sh:2024`/`:2101` and `aid-fsm.sh:3762-3769`, whose body is `printf 'sequential'` with a comment saying P078 removed the scheduler), the receipt schema is already `enum: ["sequential"]`, and the live baseline has empty `*_by_context` maps on every entry — there is nothing to migrate here.

**Implementation Detail:** The read-compatibility case is the whole risk: other projects' baseline files may carry non-sequential samples. Budget the effort on that test, not on the deletion.

**Error Handling:** A non-sequential context passed by a caller is a named refusal, so a resurrection attempt fails loudly instead of silently taking a deleted branch.

**Edge Cases:**
- A legacy file with populated `*_by_context` — reads, with the stated rule applied and asserted.
- A caller passing no context at all — the existing default applies, unchanged.
- `--help` text — updated in the same step; a stale usage string is how the vocabulary survives a deletion.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] `grep -c 'observe_parallel\|parallel' aid-gate-runtime-baseline.sh` returns only the refusal message and the read-compat handling.
- [ ] A legacy baseline file with non-sequential samples reads without error.
- [ ] The live baseline's percentiles are numerically identical before and after.

**Effort:** S
**AID Role:** backend

### Step 9: The C0 plan review stops claiming an input it never receives

**Objective:** The dependency-graph question in the C0 review is either answered from a real artifact or removed from the prompt.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh` (lines ~440-465) — `build-manifest` produces the provisional graph itself, by invoking `aid-generation-readiness.sh --write-provisional` for the plan under review, before sealing the manifest; the existing `absent_pre_generation` path survives only for a plan whose graph genuinely cannot be produced, and the reason is recorded rather than assumed.
- Modify: `plugins/aid-orchestrator/defaults/prompts/c0-plan-review-prompt-v1.md` (lines ~30-45) — mandatory check-table item 2 names the artifact it now actually receives, and states the text-derived substitute it must use in the remaining absent case; the phrase "the pre-generation authority" at :32 becomes true.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-c0-plan-graph-input.bats` — a `build-manifest` for a lint-clean plan seals a real `plan_sha256`-bound graph, not `absent_pre_generation`; a plan that fails readiness still seals the absent status with its recorded reason; a graph bound to a different plan hash is still refused (tier: t1).

**Architecture Context:** Group 3. Measured, not inferred: `P080/c0/codex/codex-prompt-vars.json` records both graph paths as `absent_pre_generation`, and the graph file's mtime is 37 minutes *after* the review it feeds. P076 and P079 show the same. The zero-byte-seal complaint in the original entry is already fixed and the graph is validated when present — only the ordering defeats it.

**Implementation Detail — decision made 2026-08-11, produce it earlier.** The open question was whether the producer needs generation state. It does not: `aid-generation-readiness.sh` (`:16-27`) takes a plan path and nothing else, sources `lib/aid-source-plan-graph.sh`, and writes the artifact from the plan text alone. Run against this plan before generation existed, it exited 0 in about a second and emitted `aid-source-plan-graph/v1` with 11 steps, 2 edges, no cycles, bound to the plan's own sha256. So the graph is a pure function of the plan and there is no reason for the review not to have it — the 37-minute gap is ordering, not dependency.

**Error Handling:** A graph present but not bound to the reviewed plan hash is refused as it is today; this step does not loosen that.

**Edge Cases:**
- A plan whose graph cannot be produced pre-generation — the prompt's substitute wording applies and is asserted.
- A re-review after a plan revision — the graph must re-bind to the new hash or be absent; a stale graph must never pass.
- Low-risk plans that skip C0 entirely — unaffected.

**Dependencies:**
- Depends on: none
- Blocks: none

**Acceptance Criteria:**
- [ ] No shipped prompt describes an artifact the manifest records as absent.
- [ ] A dispatch records either a plan-hash-bound graph or an explicit stated non-input, and the two cases are distinguishable in the evidence.
- [ ] The existing C0 review suites stay green.

**Effort:** S
**AID Role:** backend

### Step 10: The test catalog's root status stops silently disabling the audit

**Objective:** A `--mode measure|full` audit either runs its catalog commands or the catalog gating is removed with the audit that needed it.

**Files:**
- Modify: `.aid-o/config/test-catalog.yaml` (line 3) — the root `status` is set to `approved` through the sanctioned writer (`aid-test-catalog-approve.sh:136`), or the file and its gating are removed together.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-test-audit-command-allowlist.sh` (lines ~117-119) — if the decision is removal, `_tacl_matches_approved_catalog_command`'s root-status gate goes with it; if the decision is approval, the refusal at :117-119 gains a message naming the field and the approval command, because today it returns 1 silently.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-catalog-status-gate.bats` — a `proposed` catalog refuses catalog-derived commands with a message naming the field; gate-registered commands still pass through their independent path; an `approved` catalog admits both (tier: t1).

**Architecture Context:** Group 3. The original backlog entry claimed the field had no reader; that is false and the correction is verified — `:117-119` gates every catalog-derived command, while `aid_test_audit_check_allowed` keeps an independent allow-path for gate-registered commands. The live value is `proposed` despite commit `5f24304` announcing approval, so a real audit measures only registered gates, which for a bats portfolio is almost nothing.

**Implementation Detail:** The decision turns on whether test-portfolio audits are still wanted after the parallelism line was cancelled. The step must answer that question explicitly and record the answer in the backlog entry, replacing the entry's retracted original framing rather than leaving both versions side by side.

**Error Handling:** Whichever way it goes, a silent `return 1` is not acceptable: either the refusal explains itself, or the code path does not exist.

**Edge Cases:**
- A consumer project with an approved catalog — unaffected by either outcome.
- A catalog file absent entirely — existing behaviour, asserted so this step does not change it accidentally.
- Removal chosen — the enforcement registry entry goes too, in the same commit.

**Dependencies:**
- Depends on: none
- Blocks: Step 11's backlog reconciliation records this decision.

**Acceptance Criteria:**
- [ ] A `--mode measure` audit either admits its catalog commands or the catalog path no longer exists.
- [ ] No silent `return 1` remains on the status check.
- [ ] The backlog entry states the decision and its date, with the retracted framing deleted.

**Effort:** S
**AID Role:** backend

### Step 11: The backlog records what the verification found

**Objective:** Every entry the 2026-08-11 verification touched carries its verdict, so no later plan is written from a stale description again.

**Files:**
- Modify: `docs/plans/2026-06-29-BACKLOG.md` — the eleven verified-closed entries (7 already fixed, 2 moot, 2 deliberate) are marked closed with the file:line evidence that closed them; the ten entries this plan fixes point at it; the 22 verified-real-but-not-scheduled entries carry `verified real 2026-08-11` plus the sieve's reason for not scheduling them; the seven wrong-address entries have their descriptions replaced by what is actually true.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-backlog-verdicts.bats` — every entry touched by the verification carries a verdict line with a date; no entry carries two contradictory framings; the file parses as the status extractor expects (tier: t0).

**Architecture Context:** Group 3. This is the step that makes the whole exercise durable: the P082 failure was caused by descriptions that had drifted from the code, and a verdict line with a date is what stops the next reader trusting a stale one.

**Implementation Detail:** No archive split, no file move — the P082 review established that `docs/` is gitignored except for this one negated path, so a new file under `docs/plans/archive/` cannot be committed. Everything stays in the tracked file.

**Error Handling:** An entry the verification could not resolve is marked `UNRESOLVED` with what would be needed — never quietly left as-is.

**Edge Cases:**
- An entry with a later correction elsewhere in the file — the correction wins and the original framing is deleted, not annotated.
- An entry outside the verification's 46 — untouched and unmarked, so the absence of a verdict line means "not examined", which is honest.

**Dependencies:**
- Depends on: Step 10 — its decision is one of the verdicts recorded.
- Blocks: none

**Acceptance Criteria:**
- [ ] Every one of the 46 verified entries carries a dated verdict line.
- [ ] No entry contains both a retracted and a current framing.
- [ ] The eleven closed entries name the evidence that closed them.

**Effort:** S
**AID Role:** docs

## Success Criteria

1. A streamlined-mode EPIC advances review→release without a force waiver, and a multi-line acceptance criterion survives generation intact in both the human section and `ac[]`.
2. An aborted release in a worktree leaves a clean working tree, and `README.md` shows the current version after the next release.
3. No profile in this repository's `execution.yaml` includes a gate without a `command`, the runner refuses one by name, and `plan_diff` verifies this plan's own criteria instead of skipping.
4. `enabled: false` is honoured on a grep without PCRE support, and a stack-detected `/aid-init` workspace yields a non-empty `release` profile.
5. The gate-runtime baseline carries no live non-sequential branch while a legacy file still reads, and the C0 review receives a plan-hash-bound dependency graph instead of describing one it never had.
6. The catalog-status decision is made, implemented and recorded, and all 46 verified backlog entries carry a dated verdict.

## Acceptance Criteria

- [ ] AC1 — The streamlined integration review reads the gates report where gates write it.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-streamlined-integration-review.bats"
  expected_exit: 0
```
- [ ] AC2 — Multi-line acceptance criteria survive generation in both extraction paths.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-ac-extraction.bats"
  expected_exit: 0
```
- [ ] AC3 — A rolled-back release restores every file it touched.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-rollback.bats"
  expected_exit: 0
```
- [ ] AC4 — The README version list is edited by structure, not by token substitution.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-release-readme.bats"
  expected_exit: 0
```
- [ ] AC5 — A profile including a command-less gate is refused by name.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-gate-command-required.bats"
  expected_exit: 0
```
- [ ] AC6 — The self-host `plan_diff` gate has a command again.
```yaml
verification_pattern:
  type: cmd
  cmd: "test -n \"$(yq -r '.gates.plan_diff.command // \"\"' .aid-o/config/execution.yaml)\""
  expected_exit: 0
```
- [ ] AC7 — The review-signal toggle fails closed instead of open.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-review-signal-toggle.bats"
  expected_exit: 0
```
- [ ] AC8 — A composed consumer workspace yields five profiles with a non-empty `release`.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-init-gate-profiles.bats"
  expected_exit: 0
```
- [ ] AC9 — The gate-runtime baseline is sequential-only and still reads legacy files.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-gate-baseline-sequential-only.bats"
  expected_exit: 0
```
- [ ] AC10 — The C0 manifest seals a real plan-bound dependency graph.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-c0-plan-graph-input.bats"
  expected_exit: 0
```
- [ ] AC11 — The catalog status gate explains itself or no longer exists.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-catalog-status-gate.bats"
  expected_exit: 0
```
- [ ] AC12 — Every verified backlog entry carries a dated verdict.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-backlog-verdicts.bats"
  expected_exit: 0
```

## Constraints

- **P080 owns `commands/aid-init.md`, the help surfaces and `defaults/templates/`** while `.aid-worktrees/plan-P080` is live. No step in this plan edits those files; Step 7 additionally waits if that worktree is still checked out at EPIC 2 start.
- **P082 is superseded**, not paused. It must not be generated; its CP1 evidence is retained as the record of why.
- Evidence filenames (`verifier-output-step-N.md` and the CP3 sibling) are frozen; no step renames them.
- No step adds a new detector, telemetry field or FSM precondition. Steps 5 and 10 add a refusal *inside an existing check*; that is the only new enforcement surface in the plan, and both are registered in the enforcement registry in the same commit that adds them.
- Every new suite carries an `# aid-tier:` tag matching what its step declares.

## Risks

- **Step 5's decision could go either way and the profiles are the merge path.** Mitigation: the decision is made from one real `aid-plan-diff.sh` run against this plan, before the config is edited, and the runner-side refusal lands regardless of which way it goes.
- **Step 7 changes what every future consumer's workspace looks like.** Mitigation: the zero-stacks branch is untouched and asserted byte-identical; only the populated branch grows, and the new test proves every emitted profile is internally satisfiable.
- **Step 8 deletes ~90 lines from a hot library.** Mitigation: the live data has nothing to migrate (verified empty `*_by_context` maps); the entire risk is other projects' files, which is exactly what the read-compat test pins.
- **Step 3 and Step 4 edit the same block.** Mitigation: explicit dependency and a shared fallback fixture, so the second inherits the first's regression rather than re-deriving it.
- **The verification itself could be wrong somewhere.** Mitigation: every step names the line range its premise came from, and any step whose first read contradicts its premise stops and reports instead of proceeding — the P082 failure is the reason this sentence is here.

## Deferred

- Widening the `grep -oP` guard to see all 13 live PCRE sites, `.bats` files included, and re-deriving its stale allowlist (the counts are recorded in the backlog entry).
- The 22 verified-real entries the PM's sieve rejected, each with its recorded reason.
- IMP-261, IMP-490, IMP-471, IMP-487, OBS-20260702-07 — separate plans.
- IMP-495 — waits for P080.
- IMP-496 (plans are never archived) — the verification found tasks have an enforcement and plans have nothing; doing it by hand until it hurts.
