---
id: P074
type: plan
status: done
created: 2026-08-05
author: PM + AI
risk: high
depends_on_plans: [P073]
---

> **Closure (2026-08-09):** Implemented outside the AID pipeline per PM decision + P075 line; deep-check record in interim-P074.md + evidence/P074/

# Plan: Project-Level Concurrency and the Generation Transaction

## Stakeholder Brief

Today AID assumes one active stream per checkout: while plan A is being implemented, the PM cannot start plan B (a repo-wide clean-tree check refuses on any unrelated edit), cannot generate its EPICs without AID switching branches in their own checkout, and cannot even let a review window overlap with their manual work without invalidating plan A's review. Separately, EPIC generation asks its CP1 gate once per phase, so one PM authorization is consumed by phase 1 and phase 2 blocks on the same already-decided question — and a crash mid-generation leaves a stuck half-package that cannot be resumed. This plan fixes both. EPIC 1 delivers the foundations: a shared root resolver so every script finds the one true `.aid-o` even from a linked worktree, worktree-safe git hooks, a locked plan-ID allocator, a multi-run active-runs map, and preflights scoped to what each operation actually touches. EPIC 2 moves implementation into a dedicated per-plan git worktree — enforced in every lifecycle command, with defined branch topology, teardown, repair, and a status surface that shows both streams. EPIC 3 makes generation one transaction: CP1 once per plan, a sealed generation-authority receipt covering all phases, resume without duplicates, one public `--force --reason`, and proper fixes for the three parser/diagnosis defects found live on 2026-08-04. The main risk is regressing the single-stream paths everyone uses today; it is mitigated by behaviour-preserving defaults, a two-stream integration fixture, and per-consumer regression tests.

## Context

Source document: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` §16a (D26 generation authority, D27 resumable transaction) and §17 (project-level concurrency, PM-requested 2026-08-04). The PM approved the interim design on 2026-08-05 after two independent grounding sweeps (every claim verified file:line against the tree) and an adversarial Codex opponent round whose five blocking findings are folded in below; the decision record is `.aid-o/work/interim-P074.md`. Key grounded conclusions this plan builds on: the real blocker is the working-tree layer, not state (state under `.aid-o` is already per-plan and flock-protected everywhere except plan-ID allocation); `plan-start`/`epic-start` create refs only yet demand a clean repo; `plan-merge-to-main` is pure plumbing yet demands the same; git hooks silently no-op inside linked worktrees; and every building block needed (common-dir root resolution, CAS merges, a disposable-worktree harness, `lib/aid-lock.sh`) already exists in-tree. This plan is NOT the archived intra-plan parallelism plan — multiple agents inside one plan remain out of scope.

## Goal

One PM can plan, generate, and manually develop in the primary checkout while each active plan's implementation runs isolated in its own git worktree, and every PM decision — including a forced generation — covers its whole logical transaction exactly once, with resume instead of duplicates after a crash.

## Scope

**In scope:**
- Shared invoke-root/state-root resolver adopted by the cwd-relative script class, the git hooks, and every lifecycle/status entrypoint execution touches; `AID_PROJECT_ROOT` canonicalized through the common dir.
- Locked plan-ID allocation subcommand replacing the agent's unlocked read-modify-write of `counter.yaml`.
- `active-runs.json` multi-run map (legacy single-slot file tolerated one release) consumed by the pre-commit main-fallback guard.
- Clean-tree preflights dropped where the operation provably writes no tracked files (`plan-start`, `epic-start`, `plan-merge-to-main`) and scoped to the executing worktree elsewhere.
- Per-plan execution worktree at `.aid-worktrees/plan-<id>`: created at plan-start, enforced command-level in every plan-linked lifecycle command, defined in-worktree branch topology, torn down at close/rollback, repairable, visible in `/aid-status`.
- Generation as one transaction: public `aid-auto-pipeline.sh --force --reason`, CP1 gate once per plan, sealed `generation-authority.json` verified by every internal phase call, transaction manifest with hash-derived resume, transaction-aware queue-add, `supersede-generation` recovery, two honest error labels.
- Defect fixes: adjudicator empty-list/nested-key parsing, escaped-pipe table splitting with hard arity errors, target-branch misdiagnosis.
- Every instruction surface enumerated in the grounding tables updated; enforcement-registry entries for each new or removed check.

**Out of scope:**
- Intra-plan parallel dispatch (`dispatch-strategy.yaml`, archived parallelism plan) — untouched.
- §16 auto-mode owned waits (D22-D25) and category-4 entry-point UX — separate streams.
- The ~17 class-B `--show-toplevel` root-resolution sites — deferred (each honours the now-canonicalized `AID_PROJECT_ROOT`); marked still-open in the source doc.
- `host_permission_or_session_blocked` error detection — dropped (no reliable signature); marked still-open in the source doc.
- P069 scheduler and P073 in-flight surfaces beyond declared integration points.

## Approach

**Chosen approach: compose existing primitives, enforce at command level.** The worktree-aware root resolution is extracted from the plan FSM's proven `_pfsm_resolve_project_root` rather than invented; worktree lifecycle copies the disposable-worktree harness (EXIT-safe creation/removal) from `aid-test-isolation-experiment.sh`; locking reuses `lib/aid-lock.sh` (already serving queue and plan-state); the generation-authority verifier copies the exact jq binding shape the generation receipt's only existing consumer uses; and pipeline force follows P073's invocation-scoped audited model with no second grant layer. Enforcement is command-level everywhere: a plan-linked lifecycle command invoked from the wrong tree redirects or refuses by reading recorded state — never a prose convention.

**Alternative A (rejected): disposable clones instead of worktrees.** Clones (the P066 test-lane pattern) fully isolate but cost a full object-store copy per plan, break shared ref visibility (plan/task branches must be pushed back), and make merge-to-plan a remote operation. Worktrees share the object store and refs natively, and git itself already guards "same branch in two worktrees".

**Alternative B (rejected): keep one checkout, serialize streams with a scheduler.** Rejected because it institutionalizes the queue-behind-one-tree model the PM explicitly wants gone, adds a scheduler where git already provides isolation, and does nothing for the review-window invalidation problem.

## Architecture

Everything lives under `plugins/aid-orchestrator/` unless stated. Three subsystems change.

**Roots and shared state (EPIC 1).** One new sourceable helper, `scripts/lib/aid-roots.sh`, exposes `aid_state_root` (the primary checkout's top level, resolved via `git rev-parse --path-format=absolute --git-common-dir` exactly as `aid-plan-fsm.sh:203-237` does today) and `aid_invoke_root` (where the command actually runs — used only for tree operations). All `.aid-o` reads and writes go through `aid_state_root`; an explicit `AID_PROJECT_ROOT` is canonicalized through the same common-dir logic so an override pointing into a linked worktree cannot fork state. The cwd-relative call sites enumerated in the grounding (aid-fsm.sh lines 195, 206, 2740, 2824, 3109; aid-auto-pipeline.sh 187-194; aid-json-to-run.sh 644; aid-plan-close-check.sh 98; lib/aid-plan-state.sh 276; lib/aid-plan-manifest.sh 264) migrate to it; the hooks inline the same resolution (hooks cannot source plugin libs). Plan-ID allocation becomes `aid-fsm.sh alloc plan-id` holding a `counter.yaml.lock` flock via `lib/aid-lock.sh`. The single-slot `active-run-pointer.json` becomes the map `active-runs.json` keyed by epic_id with a `governs_main` flag; the pre-commit main-fallback guard evaluates every entry.

**Per-plan execution worktree (EPIC 2).** `plan-start` creates `.aid-worktrees/plan-<id>` (top-level, gitignored via the `/aid-init` template) checked out on `plan/<id>`, records `worktree_path` in plan-state, and compensates on failure (removes the just-created refs, or records an incomplete-resumable marker). A shared enforcer `_pfsm_require_plan_worktree` runs at the top of every plan-linked lifecycle command that touches a tree: if the recorded worktree exists and the invocation cwd is not inside it, the command re-executes itself with the worktree as cwd (redirect is the default for every stage); refusal happens only when the worktree itself is missing or unregistered, naming the repair. Branch topology inside the worktree mirrors today's model on main: `aid-fsm.sh init` executed there creates/checks out `task/<epic>/main` (the blanket `is_worktree()` enforcement skip narrows to worktrees NOT recorded as the plan's own), and done-advance merges task into `plan/<id>` there. The candidate-drift check evaluates the PLAN worktree's tree, so PM edits in the primary checkout can no longer invalidate a review. Teardown (`plan-close`/`plan-rollback`) runs `git worktree remove --force` plus prune, copying `aid-test-isolation-experiment.sh:93-96`; `plan-state <id> --recreate-worktree --reason` is the audited repair.

**Generation transaction (EPIC 3).** `aid-auto-pipeline.sh` runs the CP1 gate ONCE per plan, before any output, and writes `generation-authority.json` (`aid-generation-authority/v1`: plan_id, plan_sha256, target_branch, target_head, mode, total_phases, phase_derivation_version, cp1 verdict or bypassed conditions with evidence refs, forced_override, invoker, created_at, self_sha256 over canonical JSON minus the hash field). With `--force --reason` (public, P073-style: three audit records, invocation-scoped, honestly classified instruction-only for actors), the same receipt records the bypass; CP1 artifacts are never rewritten as clean. `aid-plan-to-epic.sh --generation-authority <path> --transaction <path>` verifies the receipt (schema, self-hash, plan bytes, target head, phase range, per-phase derived IDs re-derived and compared, transaction linkage via authority_sha256) INSTEAD of invoking the gate; without the flags, the standalone per-invocation gate stays. `transaction.json` (`aid-generation-transaction/v1`) records identity plus per-phase `{epic_id, run_id, epic_sha256, plan_json_sha256}`; a rerun with the same identity derives each phase's status by re-hashing recorded outputs and checking queue membership, regenerating only what fails verification; `aid-queue-add.sh --transaction <path>` converts the duplicate hard-fail into a verified idempotent skip when the transaction owns the entry. A different identity refuses; `supersede-generation` (separate invocation, `--reason` ≥20 chars, audited) archives the incomplete transaction. Failures render as `aid_cp1_blocked` or `aid_generation_force_required` (printing the exact public command); anything else passes through verbatim with a "not an AID gate" note only when AID's own checks passed.

## Implementation Steps

**EPIC 1: Steps 1-6 — Concurrency Foundations**

### Step 1: Shared root resolver and cwd-relative site migration

**Objective:** One sourceable helper resolves the state root (primary checkout) and invoke root (current tree) identically from the primary checkout and from any linked worktree, every enumerated cwd-relative site uses it, and an `AID_PROJECT_ROOT` override pointing into a linked worktree is canonicalized instead of forking state.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-roots.sh` — functions `aid_state_root` (dirname of `git rev-parse --path-format=absolute --git-common-dir`, with the dogfood escape from `_pfsm_resolve_project_root`: an explicitly named root carrying its own `.aid-o/work/plan-state` wins), `aid_invoke_root` (top level of the tree the command runs in), and `aid_canonicalize_project_root` (applies the common-dir normalization to `AID_PROJECT_ROOT`); pure bash + git, no other dependencies.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~195, ~206, ~2740, ~2824, ~3109) — the timeline path helper, `active_run_pointer_path`, the init timeline path, the init dirty-guard `git status` call (gains `-C "$(aid_invoke_root)"`), and the `execution_yaml` fallback all resolve through `aid-roots.sh`; state paths use `aid_state_root`, tree checks use `aid_invoke_root`; the same whole-file `.aid-o`-literal sweep covers every remaining state read/write and subprocess argument reachable from `cmd_init` so an init executed from a worktree touches only the primary state.
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (lines ~187-194) — `counter_yaml`, `queue_yaml`, and the `mkdir -p .aid-o/...` block resolve under `aid_state_root`; ADDITIONALLY a mechanical sweep of the WHOLE file migrates every remaining `.aid-o` literal and — critically — every state path passed as a SUBPROCESS ARGUMENT (`--counter-yaml`, `--output-dir ".aid-o"`, evidence/receipt paths handed to aid-plan-to-epic/aid-epic-to-json/aid-json-to-run/aid-queue-add/aid-generation-finalize) so the entire child chain receives canonical state-root paths; the resolved root is exported once as `AID_PROJECT_ROOT` for the children as a belt-and-braces layer.
- Modify: `plugins/aid-orchestrator/scripts/aid-json-to-run.sh` (lines ~640-650) — `fsm_evidence_dir` resolves under `aid_state_root`, plus the same whole-file `.aid-o`-literal sweep for this entrypoint's own reads/writes and subprocess arguments.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-close-check.sh` (lines ~96-100, ~169) — `PROJECT_ROOT` defaults to `aid_state_root`; `ACTIVE_FILE` follows it.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-state.sh` (lines ~274-278) — the `$(pwd)` fallback becomes `aid_state_root`; the dedicated env override stays but passes through `aid_canonicalize_project_root`.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` (lines ~262-266) — same fallback and override treatment for the manifest root resolution.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-roots-worktree.bats` — fixture repo with a linked worktree: every migrated entrypoint invoked FROM INSIDE the worktree reads and writes the PRIMARY `.aid-o` — INCLUDING the full generation subprocess chain (auto-pipeline → plan-to-epic → epic-to-json → json-to-run → queue-add end-to-end from the worktree, asserting no `.aid-o` directory appears inside the worktree at ANY point of the chain) and an `aid-fsm.sh init` from the worktree; `AID_PROJECT_ROOT` set to the worktree path canonicalizes to the primary root; primary-checkout invocations behave byte-identically to before (golden comparison on a scripted sequence); a guard grep asserts zero remaining unresolved `.aid-o` literals in the two entrypoints outside the resolver-routed helpers.

**Architecture Context:** Per the Roots subsystem: this extracts the plan FSM's proven worktree-aware resolution (`aid-plan-fsm.sh:203-237`, invoke/state split at :172-183) into a lib the rest of the plugin can share. The grounded failure mode it removes: a fresh linked worktree has no `.aid-o` (gitignored), so every cwd-relative site would silently create and use a second empty workspace invisible to the primary status surfaces.

**Implementation Detail:** `aid_state_root` caches per process in `_AID_STATE_ROOT_CACHE`. Resolution order: explicit function argument, then canonicalized `AID_PROJECT_ROOT`, then common-dir derivation from `$PWD`. `aid_invoke_root` is `git rev-parse --show-toplevel` of `$PWD` (correct for tree operations by definition). `aid-plan-fsm.sh` itself is NOT migrated in this step — its private resolver already implements the same contract; a follow-up comment cross-references the shared lib so the two cannot drift silently (the bats golden test covers both).

**Error Handling:** Outside any git repository, `aid_state_root` fails with `ERROR: not inside a git repository — AID needs a repo root` (exit 2) rather than falling back to `$PWD`; callers keep their existing not-a-repo failure paths. An `AID_PROJECT_ROOT` naming a directory that is neither a repo root nor carries `.aid-o/work/plan-state` fails with a message naming both accepted forms.

**Edge Cases:**
- Invocation from a subdirectory of the primary checkout: `aid_state_root` still resolves the top level (common-dir logic is cwd-independent within the repo).
- Bare repository or detached common dir layouts (`git worktree` on a bare clone): common-dir parent is not a worktree; the function detects the missing `.git` marker and fails loudly rather than writing state next to a bare repo.
- Nested test fixture repos (fixtures create their own `.aid-o`): the explicit-argument path preserves today's fixture behaviour (the dogfood escape).

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] All worktree-suite bats cases pass, including the no-forked-`.aid-o` assertion for every migrated entrypoint.
- [ ] Golden primary-checkout sequence is byte-identical before/after migration.
- [ ] `grep -n 'pwd)/\.aid-o\|^\s*echo "\.aid-o' plugins/aid-orchestrator/scripts/aid-fsm.sh` shows the migrated sites now route through the resolver (zero raw remnants at the five cited lines).

**Effort:** L
**AID Role:** backend

### Step 2: Worktree-safe git hooks

**Objective:** The installed pre-commit and pre-push hooks resolve `.aid-o` through the common-dir logic inline, so the commit-scope guard and push guard genuinely fire from linked worktrees instead of silently no-opping.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-commit` (lines ~100-110, ~170-180, ~215-225) — an inline `_aid_state_root()` (10 lines: `git rev-parse --path-format=absolute --git-common-dir` parent, `$PWD` fallback for pre-worktree git) prefixes the three `.aid-o` path constants (`_proj`, the runs/evidence scan dirs, `_AID_PTR`); the fail-open contract (lines ~24-26) is preserved for genuinely missing tooling, but "wrong directory" stops being a silent pass.
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-push` — grounding correction: today this hook reads NO `.aid-o` paths at all; the step adds only the same inline resolver preamble as a commented, ready-to-use helper so any future `.aid-o` read starts worktree-safe, and documents that fact — no behavioural change.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-hooks-worktree.bats` — fixture: primary repo with installed hooks, active run state in the primary `.aid-o`, a linked worktree on a guarded branch; a commit from the worktree that violates the run scope IS blocked (proves the regression is closed); a compliant commit passes; a repo with no `.aid-o` anywhere keeps the fail-open pass.

**Architecture Context:** Grounding confirmed hooks live in the common `.git/hooks` and therefore execute in every linked worktree, but their `$PWD`-relative `.aid-o` reads miss there and the fail-open design (`pre-commit:25-26`) turns that into a silent no-op — a real safety regression the moment EPIC 2 moves implementation into worktrees. Hooks cannot source plugin libs reliably (the plugin cache path is not knowable from a consumer repo hook), hence the inline duplicate of the Step 1 logic, kept deliberately tiny and commented as a copy.

**Implementation Detail:** The inline resolver mirrors `aid_state_root` minus caching: `common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; root="${common%/.git}"; [[ -d "$root/.aid-o" ]] || root="$PWD"`. All three constants become `"$root/..."`. `/aid-init`'s hook installation is template-copy, so consumer repos pick this up on the next `aid-init` upgrade — the upgrade note lands in the CHANGELOG entry and in `commands/aid-init.md`'s hook section.

**Error Handling:** If `git rev-parse` itself fails inside the hook (hostile environment), the resolver falls back to `$PWD` — behaviour identical to today, never worse.

**Edge Cases:**
- Consumer repo where `.aid-o` is tracked and therefore DOES exist in the worktree: the `-d "$root/.aid-o"` probe prefers the primary root; a worktree-local tracked `.aid-o` copy is read-only context for hooks anyway (state authority is the primary).
- Git older than `--path-format` support: the command fails, fallback applies, behaviour unchanged.
- pre-push on a repo with no `.aid-o` anywhere and no state root resolvable: both probes miss, `$PWD` fallback applies, fail-open pass with warning — byte-identical to today's degenerate case.

**Dependencies:**
- Depends on: Step 1

**Acceptance Criteria:**
- [ ] Worktree scope-violation commit is blocked in the fixture; the same commit from the primary checkout is blocked identically.
- [ ] No-`.aid-o` repo keeps fail-open behaviour (commit passes with warning).
- [ ] `commands/aid-init.md` documents the hook upgrade requirement for existing projects.

**Effort:** M
**AID Role:** backend

### Step 3: Locked plan-ID allocation

**Objective:** Plan-ID allocation is a locked CLI operation — two concurrent allocations can never mint the same ID — and every instruction surface that told the agent to hand-edit `counter.yaml` now tells it to call the allocator.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (dispatcher region, lines ~6295-6320) — new subcommand `alloc plan-id`: sources `lib/aid-lock.sh`, acquires `<state_root>/.aid-o/config/counter.yaml.lock` (5s timeout, fail closed), reads the `plan:` value, increments, writes back atomically (mktemp+mv preserving comments via sed on the single line), prints `P<NNN>` on stdout; `alloc epic-id` does the same for the `epic:` counter.
- Modify: `plugins/aid-orchestrator/skills/run-management.md` (lines ~60-80) — the ID System section replaces the three-step agent read-increment-write protocol with the single allocator call and marks manual edits as forbidden during any concurrent activity.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (lines ~60-64) — allocation wording updated to the subcommand.
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` (lines ~375-390) — allocation wording updated to the subcommand at both cited sites.
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~27-31) — allocation wording updated to the subcommand here and at the roadmap-plan exception around line 137.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-alloc-lock.bats` — 20 parallel `alloc plan-id` invocations yield 20 distinct sequential IDs (no duplicates, no gaps); lock-timeout path fails closed with the named lock path; comment lines in `counter.yaml` survive allocation byte-identically.

**Architecture Context:** Grounding identified this as the single true corruption risk in the state layer: no script writes `counter.yaml` — `skills/run-management.md:66-70` instructs the agent to read-increment-write with no lock, and generation never touches the counter at all. `lib/aid-lock.sh` already serializes queue and plan-state writes; this step points the existing mechanism at the last unprotected shared file.

**Implementation Detail:** The write preserves the file's comment block by editing only the matching `^plan: [0-9]+` (or `^epic:`) line with sed into a temp copy, then `mv`. The subcommand prints ONLY the new ID on stdout (scripts and agents capture it); diagnostics go to stderr; the dispatcher usage text carries the literal string `alloc plan-id` (plan-level AC7 greps for it). The long historical comment on the `plan:` line is left untouched — the allocator changes the number, never the annotation (annotations remain a human/agent activity documented in run-management.md).

**Error Handling:** Missing `counter.yaml`: refuse with `run /aid-init first` (never invent a counter file). Non-integer current value: fail closed naming the malformed line. Lock timeout: fail closed naming the `.lock` path and the likely concurrent holder.

**Edge Cases:**
- Allocation from inside a linked worktree: `aid_state_root` (Step 1) routes to the primary counter — covered by a bats case.
- Counter at the P999 rollover: three-digit formatting is not assumed anywhere (grep-verified during implementation); the allocator emits `P1000` naturally.

**Dependencies:**
- Depends on: Step 1

**Acceptance Criteria:**
- [ ] Parallel-allocation bats case: 20 invocations, 20 unique sequential IDs.
- [ ] All four instruction surfaces name the subcommand and no surface still instructs a manual read-increment-write.
- [ ] Comments in `counter.yaml` byte-identical after 20 allocations.

**Effort:** S
**AID Role:** backend

### Step 4: Multi-run active-runs map

**Objective:** The single-slot `active-run-pointer.json` is replaced by an `active-runs.json` map so two concurrent runs are both visible to the pre-commit main-fallback guard; the legacy file is tolerated read-only for one release.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~199-224, ~2956) — `write_active_run_pointer` becomes `upsert_active_run` writing `<state_root>/.aid-o/work/active-runs.json`: a map keyed by epic_id with `{run_id, state, branch, plan_id, governs_main, updated_at}`, updated under a `lib/aid-lock.sh` flock; `cmd_init` upserts its entry; done-advance, plan-close, and the abandoned-run sweep remove theirs; the reader helper falls back to the legacy `active-run-pointer.json` (read-only) when the map is absent.
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-commit` (lines ~215-245) — the main-fallback guard reads `active-runs.json` from the Step 2 state root and blocks when ANY entry has `governs_main` true and a guard-active state; the legacy single-slot read stays as fallback for one release.
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` (lines ~440-446) — the active-run detection description updated to the map semantics.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-active-runs-map.bats` — two concurrent runs of different plans both appear in the map; a `main` commit while EITHER has `governs_main` is blocked (the grounded run-B-hides-run-A regression closed); done-advance removes exactly its own entry; a repo carrying only the legacy pointer file is read correctly and the first upsert writes the new map without deleting the legacy file.

**Architecture Context:** Grounding: `write_active_run_pointer` is "a single global slot, always OVERWRITTEN by the next run's init" (aid-fsm.sh:209-213) and its only consumer is the pre-commit main-fallback guard (:216-244) — run B's init makes run A invisible to it; the hook's on-branch path is already multi-run-safe. The map keeps the consumer contract (same fields per entry) and only multiplies the slots.

**Implementation Detail:** jq-based upsert/remove under flock (pattern copied from `lib/aid-queue-write.sh`). `governs_main` is computed exactly as today's pointer semantics define (the run whose merge target is main and whose state is guard-active). No conversion protocol: the writer only writes the new file; the legacy file is never migrated or deleted by code — the next cleanup release drops the fallback reader (recorded in the backlog by Step 19).

**Error Handling:** Corrupt map JSON: the writer refuses (fail closed, naming the file) rather than clobbering; the hook treats unparseable maps as "guard cannot evaluate" and falls back to the legacy file, then to fail-open with a warning (never a false block). Semantics pinned: ABSENT file and PRESENT-but-empty map both mean "no active runs" (guard passes) — only an unparseable file triggers the fallback chain.

**Edge Cases:**
- Crash between init and upsert: no entry — identical exposure to today's crash-before-pointer-write; the run is still guarded by the on-branch hook path.
- Stale entry from a killed run: NEW work in this step (no such sweep exists today — the pointer expires only by init-overwrite): the map helper gains a `prune` mode removing entries whose state file is gone or terminal, invoked by the Step 6 index refresh; one bats case proves a stale entry is swept.
- Map entry for an EPIC whose state file was deleted manually: the same prune drops it and logs which entry was removed.

**Dependencies:**
- Depends on: Step 2

**Acceptance Criteria:**
- [ ] Two-run visibility case passes: both entries present, main commit blocked on either.
- [ ] Legacy-only repo reads correctly; first upsert creates the map.
- [ ] Sweep removes stale entries; done-advance removes only its own.

**Effort:** M
**AID Role:** backend

### Step 5: Preflights scoped to what operations actually touch

**Objective:** `plan-start`, `epic-start`, and `plan-merge-to-main` no longer demand a clean repo (they write no tracked files); the clean-tree checks that remain are evaluated against the tree the operation actually mutates.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~711-718, ~934, ~1163, ~5033) — `_pfsm_preflight` drops `_pfsm_check_clean_worktree` for plan-start/epic-start (detached-head check stays); `cmd_plan_merge_to_main` drops its call at ~5033 (the merge is plumbing-only, grounded at :4851-4873); `epic-merge-to-plan` (~1985) and `plan-finalize` non-exempt stages (~4792) KEEP the check but it now runs `git -C` against the tree the command will check out in — after EPIC 2 that is the plan worktree.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~205-221) — the branch/dirty-tree enforcement table updated: which commands require which tree clean, and why plan-start/epic-start/merge-to-main require none.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — the three dropped preflights get their entries updated in place (type change to `removed_scoped`, rationale, replacement guard named) rather than deleted.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-scoped-preflights.bats` — plan-start and epic-start succeed with an unrelated dirty tracked file in the primary checkout (the P074 headline case, refused today); plan-merge-to-main succeeds with a dirty primary tree (fixture with a valid frozen candidate); epic-merge-to-plan still refuses when ITS target tree is dirty; the detached-head refusal is unchanged.

**Architecture Context:** Grounding proved plan-start/epic-start create refs only (`git branch`, aid-plan-fsm.sh:1052/:1260 — no checkout, no tracked writes) and plan-merge-to-main never touches a worktree (merge-tree/commit-tree/update-ref CAS), yet all three refuse on any unrelated tracked edit via the repo-wide five-path-allowlist check (:273-285). This is the single biggest planning-side blocker to working on two things at once — and removing it is a pure loosening with a per-command grounded justification, PM-confirmed (decision 2) including the merge-with-dirty-tree product tradeoff.

**Implementation Detail:** `_pfsm_preflight` gains a second parameter `needs_clean_tree=0|1` set per caller. The kept checks route through P073's `aid_ancillary_filter_porcelain --mode legacy5` (already the shared classifier after P073 EPIC 3); no new filter logic. The registry entries record the P083-style rationale inversion: the guard was protecting operations that could not be harmed.

**Error Handling:** No new failure paths; removed checks are removed, kept checks keep their exact messages plus the tree path they evaluated.

**Edge Cases:**
- plan-start on an existing plan branch with lineage mismatch: unchanged — lineage checks are independent of tree cleanliness.
- Candidate-drift detection during review windows: untouched by this step (it is an invalidation signal, not a preflight); EPIC 2 Step 10 rebinds it to the plan worktree.
- `aid-fsm.sh init`'s own dirty guard: intentionally NOT dropped (done-advance needs a clean diff to attribute, grounded :2794-2796); after EPIC 2 it evaluates the plan worktree, which is clean by construction.

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] Headline case passes: plan-start + epic-start with unrelated dirty primary tree.
- [ ] plan-merge-to-main completes with a dirty primary tree on the fixture candidate.
- [ ] Registry entries updated in place with rationale; pipeline.md table matches the new reality.

**Effort:** M
**AID Role:** backend

### Step 6: active.md as a generated index with named writers

**Objective:** `work/active.md` becomes a small generated index of all active streams — regenerated by exactly four named writers (init, done-advance, plan-close, plan-rollback) from plan-state and the active-runs map — so two streams stop fighting over one narrative file.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-active-index.sh` — TWO sourceable functions: `aid_active_index_refresh <state_root>` (renders `work/active.md` from `work/plan-state/*/plan-state.yaml` + `work/active-runs.json` + queue summary — one line per active plan: id, phase, worktree path, EPIC states; one header line naming the file as generated; atomic write; flock via `lib/aid-lock.sh`) and `aid_active_boundary_sync <state_root> <epic_id> <action>` (the shared idempotent post-boundary helper both FSMs call: performs the Step 4 active-runs upsert/remove/prune for the boundary, then invokes the refresh — one definition, both layers source this file).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~2950-2960) — cmd_init tail, done-advance completion, and plan-close completion each call one shared idempotent post-boundary helper `aid_active_boundary_sync` (active-runs entry upsert/removal + index refresh in one place) best-effort; a render failure warns, never blocks the lifecycle operation.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (plan-close completion and plan-rollback completion regions) — the PLAN-layer close/rollback call the SAME shared helper, so a direct `aid-plan-fsm.sh plan-close` (invocable without the aid-fsm.sh wrapper) performs identical active-run cleanup and index refresh; the bats file adds a direct plan-layer close case.
- Modify: `plugins/aid-orchestrator/skills/memory.md` (lines ~13-17) — the active.md read instruction updated: agents READ the generated index for orientation and never hand-write it; per-stream detail lives in plan-state.
- Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` (lines ~235-240) — same read-only index wording.
- Modify: `plugins/aid-orchestrator/skills/run-management.md` (lines ~95-102) — the "authoritative current state" wording replaced by the generated-index contract.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~325-332) — the "Update work/active.md" instruction replaced by the automatic-refresh note.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (lines ~56-60) — the context-read instruction updated here and at the write-mode context read around line 296.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-active-index.bats` — two active plans render as two lines; each of the four writers refreshes the index in its fixture; a hand edit is overwritten on next refresh (documented generated-file semantics); render failure (unwritable file) warns without failing the lifecycle command.

**Architecture Context:** Grounding: `active.md` is agent-written prose read by five surfaces as "authoritative current state" — a single narrative two streams would corrupt with lost updates. The Codex round rejected a second presentation system; this is the minimal index with plan-state as the sole detail source and writers named at the four lifecycle boundaries.

**Implementation Detail:** Rendering is pure bash+yq/jq over existing state files; zero new state is introduced. The header line reads `<!-- generated by aid-active-index.sh — do not hand-edit; details live in .aid-o/work/plan-state/ -->` so any agent reading the file learns the contract in-band.

**Error Handling:** Missing plan-state dir or empty map renders a valid "no active streams" index. yq/jq absent: refresh warns and leaves the previous index in place (best-effort contract).

**Edge Cases:**
- Legacy projects with a hand-written active.md: the first refresh overwrites it; `/aid-init` upgrade notes call this out, and the old content is preserved once as `active.md.pre-index` on first overwrite.
- Concurrent refresh from two lifecycle boundaries: flock serializes; last writer wins over identical source state (idempotent render).
- A plan-state file mid-write by a concurrent locked writer: the renderer reads the last committed bytes (plan-state writes are atomic tmp+mv), so a momentarily stale line self-corrects on the next boundary refresh — never a torn read.

**Dependencies:**
- Depends on: Step 4

**Acceptance Criteria:**
- [ ] Two-stream fixture renders both plans; all four writers refresh.
- [ ] First overwrite preserves `active.md.pre-index`.
- [ ] All five instruction surfaces name the generated-index contract.

**Effort:** M
**AID Role:** backend

**EPIC 2: Steps 7-12 — Per-Plan Execution Worktree**

### Step 7: Worktree creation at plan-start with compensating cleanup

**Objective:** `plan-start` creates the plan's execution worktree at `.aid-worktrees/plan-<id>` checked out on `plan/<id>`, records its path in plan-state, and a failure at any point compensates so no live plan ref is left without its required worktree (or a resumable incomplete marker).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (cmd_plan_start region, lines ~1040-1080) — after the existing `git branch "$plan_branch" "$target_head"` succeeds: `git worktree add "$state_root/.aid-worktrees/plan-<id>" "$plan_branch"` (extending the invocation shape of `aid-test-isolation-experiment.sh:83-88` minus `--detach`); on success record `worktree_path` in plan-state (new field, written through the existing locked plan-state writer); on worktree-add failure remove the just-created plan branch (`git branch -D`) and the plan-state entry, print the underlying git stderr, and exit non-zero (nothing half-created); on plan-state-write failure remove the worktree AND the branch (full compensation).
- Modify: `plugins/aid-orchestrator/defaults/.gitignore` — add `.aid-worktrees/` to the block `/aid-init` appends to the project root `.gitignore` (the real install mechanism per `commands/aid-init.md` lines 37-39); the aid-init.md upgrade note names it.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-state.sh` (schema fields region, lines ~280-300) — `worktree_path` accepted as an optional field; validation: when present, must be a repo-root-relative or absolute path string (existence is checked by consumers, not the schema).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-plan-worktree-create.bats` — plan-start creates branch + worktree + records path; a forced `worktree add` failure (pre-created colliding directory) leaves NO plan branch and NO plan-state entry; a forced plan-state-write failure leaves NO worktree and NO branch; re-running plan-start after compensation succeeds cleanly; the worktree's HEAD is `plan/<id>`.

**Architecture Context:** Per the worktree subsystem: `.aid-worktrees/` is top-level (PM decision 1 — state and execution trees deliberately separated, so tearing down a worktree never touches `.aid-o` state) and gitignored via the `/aid-init` template. The Codex round's blocking finding 3 demanded transactional creation: plan-start today creates refs only, and a ref without its required execution worktree would strand every later plan-linked command once Step 8's enforcement lands.

**Implementation Detail:** Creation order is: plan-op INTENT record (the existing operations.jsonl write-ahead) → branch → worktree → plan-state `worktree_path` record → op completion. Compensation runs in reverse of what succeeded AND rolls back the plan-op ledger record with it — deleting the branch while the op record says `git_applied` would make the next plan-start hard-fail at the existing exit-5 consistency check (`aid-plan-fsm.sh:1021` region), so the ledger rollback is part of the same compensation, asserted by the re-run AC. The worktree directory name is exactly `plan-<id>` (no slug) so the Step 8 enforcer can derive it without reading state in the degenerate lookup case. `git worktree add` on the just-created branch cannot collide with the primary checkout (git refuses the same branch twice — the primary is on the PM's branch, never `plan/<id>`).

**Error Handling:** A pre-existing `.aid-worktrees/plan-<id>` directory that is NOT a registered worktree (leftover from a crash plus manual prune) is reported with the exact recovery (`git worktree prune` then re-run, or `--recreate-worktree` after Step 11); plan-start never deletes a directory it did not just create. Stale installed hooks (an existing project that has not re-run `/aid-init` since Step 2): worktree creation probes the installed `.git/hooks/pre-commit` for the Step 2 resolver marker; when absent it prints `WARNING: installed hooks predate worktree support — commits from the plan worktree are unguarded until you re-run /aid-init` (warn-not-block, matching the hooks' own fail-open contract; the Step 19 fixture asserts the warning and the enforcement-registry entry records warn-only as the deliberate severity).

**Edge Cases:**
- Filesystem without hardlink/worktree support quirks (network mounts): `git worktree add` failure is compensated and reported verbatim — plan-start fails atomically rather than degrading to checkout-hijack mode.
- Resumed plan-start on an existing plan branch (the current resume path): if plan-state already records a worktree that exists and is registered, creation is skipped idempotently; if recorded but missing, plan-start refuses and names `--recreate-worktree`.
- Kill between worktree registration and the plan-state record (the registered-but-unrecorded window): the INTENT op record proves the plan is worktree-mode, so a resumed plan-start completes the record instead of the plan masquerading as legacy; independently, Step 8's enforcer treats "no `worktree_path` BUT `.aid-worktrees/plan-<id>` exists or is git-registered" as a REFUSAL naming plan-start resume and `--recreate-worktree` — never a legacy pass.
- Disk-space failure mid-add: git leaves a partial admin entry; compensation runs `git worktree remove --force` then `git worktree prune` before deleting the branch.

**Dependencies:**
- Depends on: Step 1

**Acceptance Criteria:**
- [ ] Create/record path passes; worktree HEAD is the plan branch.
- [ ] Both forced-failure fixtures compensate fully (no branch, no state, no worktree remnant that blocks a clean re-run).
- [ ] `.aid-worktrees/` present in the installed gitignore template and aid-init upgrade note.

**Effort:** M
**AID Role:** backend

### Step 8: Command-level worktree enforcement for plan-linked lifecycle commands

**Objective:** Every plan-linked lifecycle command that operates on a tree resolves the plan's recorded worktree and either transparently re-executes itself there or refuses with the exact path — a direct operator call from the primary checkout can never silently run tree operations against the wrong tree.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (new function near the preflight block, lines ~700-720, plus call sites at cmd_epic_merge_to_plan ~1985, cmd_plan_finalize ~4790, and the finalize stage bodies) — `_pfsm_require_plan_worktree <plan_id>`: reads `worktree_path` from plan-state; when absent AND no `.aid-worktrees/plan-<id>` directory or git registration exists (true legacy plan) return 0 with a one-line notice; when absent BUT the directory/registration exists (crash window), REFUSE naming plan-start resume and `--recreate-worktree` — never a legacy pass; when recorded and the invoke root differs, re-exec the same command with `cd` into the worktree (argv preserved verbatim, `$0` canonicalized via realpath BEFORE the cd, guarded against sourced contexts via a BASH_SOURCE check, loop-guard env `AID_WT_REDIRECTED=1` so a second redirect is impossible); when recorded but the directory is missing/unregistered, refuse naming `--recreate-worktree`.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (cmd_init branch-enforcement region, lines ~2723-2801, AND cmd_done_advance entry) — for an EPIC whose plan records a worktree, init invoked outside it redirects identically (same helper, sourced), and `done-advance` — a plan-linked tree operation driven by cwd today — gains the SAME enforcer call before its first tree/state operation; the dirty-tree guard then evaluates the worktree tree (clean by construction after Step 7). The bats file adds a direct primary-checkout `done-advance` case proving redirect.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~205-221 enforcement table, plus the plan-final stage descriptions ~1307-1330) — every affected command documents the redirect/refuse behaviour and the loop-guard; the agent-dispatch section additionally states that the controller dispatches implementer/specialist agents for a worktree-recorded plan WITH cwd = the plan worktree.
- Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` (lines ~255-265) — the Script Execution CWD rule ("always the project root") gains the worktree clause: for an EPIC of a worktree-recorded plan, the working directory is the PLAN WORKTREE (state reads still resolve to the primary `.aid-o` via the Step 1 roots contract); the mechanical backstop is named honestly: done-advance runs in the worktree and attributes the EPIC diff there, so work committed to the wrong tree surfaces as an empty task-branch diff at done-advance, and the Step 19 fixture asserts an implementer-style commit lands in the worktree.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-worktree-enforcement.bats` — each of epic-merge-to-plan, plan-finalize sync/gates, and aid-fsm init invoked FROM THE PRIMARY checkout on a worktree-recorded plan executes against the worktree (asserted via a marker file diff and unchanged primary HEAD); a missing worktree refuses with the recovery command; legacy plans without `worktree_path` behave byte-identically to today; the redirect loop-guard fires if plan-state lies (worktree_path pointing at the primary root).

**Architecture Context:** The Codex round's blocking finding 1: dispatching agents with a cwd is a prose promise — finalize/sync/gates today act on the operator checkout (grounded :2613/:3056/:3974), so without command-level enforcement a direct PM invocation still hijacks or pins the primary checkout. Redirect-not-refuse is chosen for non-interactive stages so existing muscle memory and scripts keep working; the refusal path exists only where the worktree itself is broken.

**Implementation Detail:** Re-exec form: `AID_WT_REDIRECTED=1 exec bash "$0" "${ORIG_ARGS[@]}"` with cwd set to the worktree — one process boundary, no argument re-parsing drift (ORIG_ARGS captured before parsing). The helper runs AFTER argument parsing (needs plan_id) and BEFORE any tree operation or preflight that inspects a tree. `plan-merge-to-main` deliberately does NOT get the enforcer (pure plumbing, Step 5 dropped its tree requirement); `plan-start` runs pre-worktree by definition. `plan-close` and `plan-rollback` get the INVERSE enforcement: they perform their lifecycle-file work via plumbing/state-root paths and must NOT run from inside the worktree they are about to remove — invoked with cwd inside `.aid-worktrees/plan-<id>` they refuse with the exact `cd <state_root>` instruction (deleting the tree under your own feet is never redirected around), covered by a bats case each.

**Error Handling:** Redirect into a worktree whose HEAD is not the expected plan/task branch does not silently proceed: the command's own existing branch/candidate preconditions fire there and report against the worktree path (messages gain the tree path per Step 5's convention).

**Edge Cases:**
- PM intentionally cd'd INTO the worktree and runs the command: invoke root matches, no redirect, zero overhead.
- Nested invocation (a lifecycle command shelling out to another): the inner one sees `AID_WT_REDIRECTED=1` only if the outer redirected; the guard is per-command scoped by unsetting it after the cwd check passes, so legitimate inner redirects for a DIFFERENT plan still work.
- Worktree on a different filesystem: `cd` + exec is filesystem-agnostic; no path assumptions beyond plan-state's recorded absolute path.

**Dependencies:**
- Depends on: Step 7

**Acceptance Criteria:**
- [ ] All redirect fixtures pass with unchanged primary HEAD and correct worktree-side effects.
- [ ] Missing-worktree refusal names `--recreate-worktree`; legacy plans unchanged.
- [ ] Loop-guard case terminates with a clear error instead of recursing.

**Effort:** L
**AID Role:** backend

### Step 9: Branch topology inside the plan worktree

**Objective:** EPIC execution inside the plan worktree uses exactly today's branch model — `aid-fsm.sh init` creates/checks out `task/<epic>/main` there, done-advance merges task into `plan/<id>` there — and the blanket `is_worktree()` enforcement skip narrows to worktrees that are NOT the plan's own recorded one.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~2723-2790, branch enforcement; ~230-234 is_worktree) — the worktree-mode early-skip (:2747-2748) becomes: if the current worktree IS the plan's recorded worktree (path match against plan-state), branch enforcement RUNS (expected branch `task/<epic>/main`, auto-create from `plan/<id>` instead of from main); if it is a foreign/unrecorded worktree, the existing skip stays ("caller controls branch").
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (done-advance merge region) — the merge target for a plan-linked EPIC inside the worktree is `plan/<id>` (already the case under plan_branch mode via epic-merge-to-plan; this step asserts the worktree context and updates the operator messages to name the worktree).
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~205-213, the HEAD-state table) — a new row: plan worktree on `plan/<id>` → auto-checkout `task/<epic>/main` created from the plan branch; foreign worktree row unchanged.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-worktree-topology.bats` — init inside the plan worktree on `plan/<id>` creates `task/<epic>/main` from the plan head and checks it out THERE (primary checkout untouched); a second EPIC of the same plan after the first merges gets its branch from the advanced plan head; init inside a foreign worktree keeps the skip; the full cycle task-branch → done-advance → epic-merge-to-plan lands the merge on `plan/<id>` with the worktree ending on the plan branch.

**Architecture Context:** The Codex round's blocking finding 2: the draft never specified how the per-EPIC branch model survives inside the worktree — and `is_worktree()`'s blanket skip (grounded :2747) would have left init sitting on `plan/<id>` with no task branch, breaking done-advance's diff attribution. This step defines the topology: the plan worktree behaves exactly like a dedicated "main" for that plan, with `plan/<id>` playing the integration role.

**Implementation Detail:** Recorded-worktree detection reuses the Step 8 helper's plan-state read (sourced, not duplicated). Task-branch creation base changes from the current-branch head to `plan/<id>`'s head when in the plan worktree — one conditional in the existing auto-create block. The hard-fail on `task/E-<other>` (grounded :2771) keeps firing inside the worktree (two EPICs of one plan still execute sequentially there; intra-plan parallelism stays out of scope).

**Error Handling:** Init inside the plan worktree while `plan/<id>` has diverged from the recorded lineage: the existing lineage preconditions fire unchanged (they are tree-independent); messages name the worktree path.

**Edge Cases:**
- Worktree HEAD manually moved to an unrelated branch: enforcement treats it like today's "on feat/*" case — warn and accept only when the branch matches the expected task pattern; anything else names the expected topology.
- Legacy plan (no recorded worktree) run in the primary checkout: the main/master/develop auto-checkout path is byte-identical to today (regression-asserted).
- `plan/<id>` deleted by manual surgery while the worktree survives: init inside the worktree fails on the missing base ref with the existing branch-resolution error naming the plan branch and `--recreate-worktree` is NOT the remedy (the message points at plan-state repair instead).

**Dependencies:**
- Depends on: Step 8

**Acceptance Criteria:**
- [ ] Full in-worktree cycle passes with primary checkout untouched throughout.
- [ ] Foreign-worktree skip and legacy primary-checkout behaviour are regression-asserted byte-identical.
- [ ] pipeline.md table carries the new row.

**Effort:** M
**AID Role:** backend

### Step 10: Plan-final stages and candidate drift bound to the plan worktree

**Objective:** `plan-finalize` sync/gates/review/c4 and `epic-merge-to-plan` operate in the plan worktree via the Step 8 enforcer, gates stamp the candidate from the worktree HEAD, and the candidate-drift check evaluates the plan worktree's tree — so PM edits in the primary checkout can no longer invalidate a review.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (drift detector `_pfsm_review_candidate_drift` region, lines ~3608-3623) — the porcelain dirty check runs `git -C <worktree_path>` when plan-state records a worktree (falling back to the state root for legacy plans); the head-comparison legs are ref-based and unchanged.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (finalize stage messages, lines ~3974, ~4525) — the "requires the worktree to BE the frozen candidate" messages name the PLAN worktree path (the PM's primary checkout is explicitly not involved); the review/c4 stage-entry redirect comes from Step 8.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~1307-1330) — the plan-final boundary rule rewritten: tracked writes IN THE PLAN WORKTREE are the fix signal; the PM's primary checkout is free during review windows.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-drift-worktree.bats` — with a frozen candidate in the plan worktree: an unrelated tracked edit in the PRIMARY checkout does NOT invalidate (the P074 headline review case); a tracked edit inside the PLAN worktree still invalidates exactly as today; gates run in the worktree stamp `revision.head_sha` equal to the candidate; legacy plans (no worktree) keep today's state-root evaluation byte-identically.

**Architecture Context:** Grounding: review/c4 today pin the operator checkout to the candidate ("stay there", :3974) and the drift check's dirty leg reads the operator tree — the concurrency-killing combination for review windows. With Steps 7-9 the candidate lives in the plan worktree; this step re-points the two tree-reading consumers and finishes the isolation story. P073's ancillary classifier continues to filter the dirty paths (this step only changes WHICH tree is read).

**Implementation Detail:** The drift function gains one resolved-root variable at the top; every `git -C "$root"` in its body becomes `git -C "$drift_root"`. Stage-entry checks that compare `HEAD` against the candidate resolve HEAD from the worktree (they already run there post-redirect; the assertion is belt-and-braces with a clear message). No change to invalidation reasons, exit codes, or the P073 equivalence path (which is ref/manifest-based and tree-independent).

**Error Handling:** Recorded worktree missing at a finalize stage: the Step 8 refusal fires before any drift evaluation (never a false invalidation from a missing tree).

**Edge Cases:**
- Ancillary-classified dirt inside the plan worktree (P073 EPIC 3 behaviour): still tolerated — the classifier is tree-independent.
- Plan worktree deliberately used by the PM for a quick manual fix during PLAN_FIX: supported — that IS the fix workflow; the next freeze happens from the worktree state.
- Both trees dirty simultaneously (worktree fix in progress AND unrelated primary edits): only the worktree tree is consulted — asserted by a fixture carrying dirt in both trees at once.

**Dependencies:**
- Depends on: Step 9

**Acceptance Criteria:**
- [ ] Headline review case passes: primary-checkout edit during review does not invalidate; worktree edit does.
- [ ] Gates stamp the worktree candidate SHA; legacy behaviour regression-asserted.
- [ ] pipeline.md boundary rule names the plan worktree.

**Effort:** M
**AID Role:** backend

### Step 11: Worktree teardown and audited repair

**Objective:** `plan-close` and `plan-rollback` remove the plan's worktree safely; a damaged or missing worktree is restored by an audited `plan-state <id> --recreate-worktree --reason` transaction; no leftover worktree or registration can strand a later plan.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (plan-close completion region and plan-rollback completion region) — teardown: `git worktree remove --force <path>` then `git worktree prune`, extending `aid-test-isolation-experiment.sh:93-96` (which has `remove --force` only — the prune is this plan's addition); failure downgrades to a warning naming the manual cleanup (`git worktree remove -f -f <path> ; git worktree prune` — the doubled -f is required for a locked worktree) — close/rollback never block on teardown; plan-state's `worktree_path` is cleared in the same locked write that records closure.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (plan-state flag region, lines ~5995-6020) — new flag `--recreate-worktree` with mandatory `--reason` (≥20 chars): validates the plan is open, prunes any stale registration, re-runs the Step 7 creation sequence against the existing `plan/<id>` head — or, when a matching worktree is ALREADY git-registered at `.aid-worktrees/plan-<id>` but plan-state lost its record (state-file loss + `plan_state_init` reconstruction, which cannot know the path), ADOPTS it by verifying the registration via `git worktree list` and re-recording `worktree_path` — and records the audit trail via the P073 audit PRIMITIVES directly (timeline event `plan_worktree_recreated` + audit-log append) — deliberately NOT the force-waiver writer: no `forced_override` flag, no C4 waiver artifact, because nothing is bypassed; this is a repair log with instruction-only actor semantics stated as such.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-worktree-teardown.bats` — close removes worktree + registration + clears plan-state; rollback likewise; a REMOVAL-BLOCKING worktree fixture (on Linux an open file does not block unlink, so the fixture makes the parent directory read-only via chmod — a condition that genuinely fails `git worktree remove`) downgrades to the warning and close still completes; `--recreate-worktree` restores a deleted worktree with HEAD on `plan/<id>` and writes the audit record; recreate on a CLOSED plan refuses.

**Architecture Context:** Completes the worktree lifecycle transaction demanded by the Codex round (blocking finding 3): create (Step 7) — enforce (Step 8) — repair/teardown (this step). Teardown is best-effort because a stuck NFS handle must never make a plan unclosable (the P082 lesson: terminal operations must complete); the warning names the exact manual cleanup.

**Implementation Detail:** `git worktree remove --force` handles dirty worktree trees (post-close they are merged or abandoned by definition); `prune` clears any half-removed admin state. The recreate path is Step 7's creation function extracted into `_pfsm_create_plan_worktree` (shared by both callers — no duplicated creation logic).

**Error Handling:** Recreate when `plan/<id>` no longer exists (post-merge cleanup already deleted it): refuse with "the plan branch is gone — nothing to execute; this plan needs no worktree".

**Edge Cases:**
- Worktree directory already deleted by hand but registration remains: teardown and recreate both start with `prune`, making the hand-deletion harmless.
- Two plans closing concurrently: each touches only its own `.aid-worktrees/plan-<id>` and its own plan-state file (flocked) — no shared mutable state in teardown.
- Recreate while `plan/<id>` is checked out in ANOTHER linked worktree (manual duplication of the setup): git refuses the add; the error passes through verbatim with a `git worktree list` hint so the operator finds the collision.

**Dependencies:**
- Depends on: Step 8

**Acceptance Criteria:**
- [ ] Close and rollback fixtures remove worktree, registration, and state pointer.
- [ ] Busy-worktree fixture warns and completes; manual cleanup line printed verbatim.
- [ ] Recreate restores a working worktree with the audit record; closed-plan recreate refuses.

**Effort:** M
**AID Role:** backend

### Step 12: Two-stream status surface and multi-plan selection

**Objective:** `/aid-status` groups by plan and shows each stream's worktree, phase, and EPIC states; `/aid-run` auto-detection handles multiple active plans with a named selection instead of assuming one; the concurrency instruction sweep lands.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` (lines ~24-48, ~151-168) — the scan flow reads `work/plan-state/*/plan-state.yaml` + `active-runs.json` + queue and renders one block per active plan: plan id, lifecycle phase, `worktree_path` (with a `missing!` marker when recorded but absent), its EPICs' FSM states, queue rows; the single-EPIC template remains for plan-less runs.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~455-462) — auto-detect: zero active → suggest plans; one active → today's behaviour; multiple active → named selection list (plan id + phase + next actionable EPIC), never "the single active EPIC".
- Modify: `plugins/aid-orchestrator/commands/aid-verify-implementation.md` (lines ~18-22) — "the current branch's diff" clarified: for a worktree-recorded plan the target diff is taken in the PLAN worktree.
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` (lines ~25-30) — the global sequential-dispatch note gains one sentence: per-plan worktrees isolate PLANS from each other; the per-plan dispatch cap is unchanged.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-status-two-streams.bats` — a fixture with two active plans (one with a worktree, one legacy) renders both blocks with correct worktree column; the missing-worktree marker appears when the directory is deleted; single-plan and plan-less fixtures render today's shapes.

**Architecture Context:** Grounding: `/aid-status` renders multiple EPICs but has no plan grouping and no stream column, and `aid-run.md:458` hard-codes the single-active assumption — the PM cannot SEE two streams even where the state layer supports them. This step is presentation + instruction only; all data comes from state files earlier steps maintain.

**Implementation Detail:** The status flow stays prose-driven (no new script — consistent with the surface's current design); the rendering recipe in the command doc names the exact files and jq/yq reads so any agent reproduces the same blocks. The `missing!` marker keys off plan-state's `worktree_path` versus directory existence — the same probe Step 8's enforcer uses.

**Error Handling:** Unparseable plan-state file: its block renders as `plan <id>: state unreadable — run plan-state <id> --repair` instead of aborting the whole status.

**Edge Cases:**
- Plan in PLAN_MERGING/CLOSED lingering in plan-state: rendered under a "closing" section, not as active work.
- More than three active streams: blocks render in plan-id order; no pagination logic (YAGNI — the PM is one human).
- A worktree_path recorded as an absolute path that no longer resolves (repository moved on disk): the `missing!` marker renders with the recorded path verbatim — status reports, never guesses a new location.

**Dependencies:**
- Depends on: Step 11

**Acceptance Criteria:**
- [ ] Two-stream fixture renders both blocks with worktree column and missing-marker case.
- [ ] Multi-active `/aid-run` selection documented; single-active unchanged.
- [ ] role-cards and verify-implementation wording updated.

**Effort:** M
**AID Role:** docs-writer

**EPIC 3: Steps 13-19 — Generation as One Transaction**

### Step 13: CP1 once per plan and the generation-authority receipt

**Objective:** `aid-auto-pipeline.sh` runs the CP1 gate exactly once per plan before any output, accepts public `--force --reason` following the P073 audited model, and seals the decision into `generation-authority.json` bound to the exact plan bytes, target head, and phase set.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (argument loop lines ~43-55, pre-output region ~330-436) — new flags `--force` and `--reason` (reject `--force` without a ≥20-char reason); after the lifecycle-manifest ensure and BEFORE the phase loop: invoke `aid-cp1-gate.sh --plan "$plan" --project-root "$state_root"` once; on gate pass write the authority receipt; on gate fail WITHOUT `--force` exit with the Step 18 labels; on gate fail WITH `--force` write the three P073 audit records (timeline event `generation_force_override`, audit-log append, HEAD-bound waiver artifact with the failed conditions as `bypassed_preconditions`) and write the authority receipt with `forced_override: true` plus every failed condition.
- Create: `plugins/aid-orchestrator/defaults/schemas/generation-authority.schema.json` — `aid-generation-authority/v1`: required plan_id, plan_sha256, target_branch, target_head, mode, total_phases, phase_derivation_version, cp1 (object: verdict OR bypassed_conditions[] + evidence_refs[]), forced_override (bool), invoker, created_at, self_sha256; additionalProperties false.
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (authority writer function, new, near the receipt helpers ~300-320) — canonical-JSON self-hash: `self_sha256 = sha256(jq -S -c '.self_sha256 = null')`, a plain stated convention (no in-tree precedent hashes an embedded-self-field envelope this way): canonical JSON via `jq -S -c` with the hash field nulled, piped to sha256sum; atomic mktemp+mv into `.aid-o/work/evidence/<plan_id>/generation/generation-authority.json`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-generation-authority.bats` — a passing low-risk plan writes a verdict-bearing authority; a high-risk plan with a blocking C0 review and `--force --reason` writes forced authority + all three audit records; `--force` without `--reason` dies; the CP1 gate is invoked exactly ONCE for a 3-phase plan (call-count via a wrapper stub); CP1 artifacts on disk are untouched by a forced run (byte-compare).

**Architecture Context:** Grounding F2: the gate runs per phase today because `aid-plan-to-epic.sh:144-150` calls it unconditionally per invocation and the one-shot override memo is function-local — 3 phases demanded 3 PM artifacts on 2026-08-04, worked around with the watcher anti-pattern §16a explicitly forbids normalizing. Moving the single gate call into the pipeline (the transaction boundary) makes generation authority plan-scoped by construction. Force follows P073's invocation-scoped model (PM decision 4): the PM typing the public command IS the authorization, honestly classified instruction-only for actors, with the full three-record audit.

**Implementation Detail:** Concurrency ordering: the FIRST act after the committed-source preflight is acquiring the transaction lock (`lib/aid-lock.sh` on the transaction sidecar) and writing the identity-only transaction SKELETON (identity tuple + empty phases) — only then does the CP1 gate run and the authority get written, both still under that serialization point, so two concurrent invocations can never both observe "no transaction" and double-run CP1 or race the fixed authority path (Step 15 extends the same skeleton file rather than creating its own). The gate call itself happens after the committed-source preflight (P083, unchanged) so a forced generation still cannot run from an uncommitted plan. `phase_derivation_version` is a literal constant (`1`) bumped only when the phase-detection algorithm (lines ~219-280) changes semantically — it exists so a resumed transaction can detect that a plugin upgrade changed how phases would be derived. `cp1.evidence_refs` records the paths of `c0-plan-review.json` and the cp1-deep evidence dir with their sha256s at decision time (audit provenance; Step 14 re-verifies bytes only for the authority itself, not the referenced evidence — the gate already validated those).

**Error Handling:** Authority write failure fails the whole run before any phase output (nothing to resume, nothing half-made). A gate invocation that itself crashes (not a clean fail) is reported verbatim per Step 18's passthrough rule.

**Edge Cases:**
- Low-risk plan (gate exits 0 fast): authority carries `cp1.verdict: low_risk_pass` — phases still verify the receipt, so the transaction contract is uniform.
- `--force` on a plan whose gate would PASS: the force is recorded as unused (`force_unused: true` in the timeline event, no waiver written — nothing was bypassed), matching P073 Step 8 semantics.
- Re-run after a completed transaction: Step 15's resume logic short-circuits before this step's gate call (identity match, all phases verified) — the gate is not re-consulted for an already-authorized identical transaction.

**Dependencies:**
- Depends on: Step 1

**Acceptance Criteria:**
- [ ] The pipeline's plan-level gate call runs exactly once per invocation (unit-level assertion on the new pre-phase block; the full 3-phase once-only count across the wired chain is Step 15's AC, since phase wiring lands there); forced and unforced authorities validate against the schema.
- [ ] Forced run writes all three audit records and leaves CP1 artifacts byte-identical.
- [ ] `--force` without `--reason` and short reasons die with the P073-consistent message.

**Effort:** L
**AID Role:** backend

### Step 14: Authority verification inside the phase generator

**Objective:** `aid-plan-to-epic.sh` invoked by the pipeline verifies the sealed authority instead of re-running the CP1 gate — bound to plan bytes, target head, phase range, per-phase derived IDs, and the owning transaction — while standalone invocation keeps the full gate. Honest classification (AID-v3 §1): the receipt, like every AID artifact, is forgeable by a Bash-capable actor — the enforcement is the hash/transaction binding (a forged or replayed receipt fails verification against the real plan bytes, target head, and transaction) plus audit detectability, never actor impossibility.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (argument loop ~30-70, gate call site ~144-150) — new flags `--generation-authority <path>` and `--transaction <path>` (both or neither; one without the other dies); when present, replace the gate call with `_verify_generation_authority`: schema-validate, recompute self_sha256, `plan_sha256 == sha256(current plan bytes)`, `target_head == git rev-parse <target_branch>`, `1 <= phase <= total_phases`, re-derive this phase's epic_id/run_id from plan_num+phase and compare against the transaction's recorded entry, and `transaction.authority_sha256 == authority.self_sha256`; ANY mismatch dies naming the exact field; without the flags the existing gate call runs unchanged.
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (phase-loop invocation ~442-448) — DEFERRED WIRING NOTE: the pipeline starts passing both flags only in Step 15 (which creates the transaction writer); in this step the flags are exercised exclusively by fixtures with hand-built authority/transaction files, keeping producer-before-consumer ordering clean. This Files entry lands as a comment marker at the invocation site; the functional edit is Step 15's.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-authority-verify.bats` — pipeline path: 3 phases verify one authority with zero gate invocations; tampered authority (one byte) dies on self-hash; edited plan after sealing dies on plan_sha256; moved target head dies on target_head; authority replayed with a foreign transaction file dies on linkage; `--generation-authority` without `--transaction` dies; standalone invocation without flags still runs the CP1 gate (call-count stub).

**Architecture Context:** Grounding F5: exactly one sealed-receipt-verified-downstream pattern exists (`aid-generation-finalize.sh` producer → `aid-json-to-run.sh:669-672` jq consumer) and NOTHING verifies receipts at generation start — this step adds the missing upstream consumer copying that exact jq binding shape. The Codex round's missing-wiring findings demanded the transaction linkage and per-phase ID re-derivation so a leaked authority file is useless outside its own transaction (the flag is public CLI; the binding, not obscurity, is the enforcement).

**Implementation Detail:** `_verify_generation_authority` is ~40 lines of jq + git, structured as one check per line with a named failure message each (the aid-json-to-run:666-672 style). ID re-derivation reuses the exact existing derivation code path (plan_num extraction :157, epic_id :162) — asserted equal to the transaction record, so derivation drift between pipeline versions is caught at verify time, not at queue time.

**Error Handling:** Unreadable/missing authority or transaction file: die with the "run aid-auto-pipeline.sh" pointer (never fall back to gate-less generation). Schema-validation unavailable (jq missing): die — the verifier is fail-closed by definition.

**Edge Cases:**
- Authority sealed under a different phase_derivation_version than the running script: die naming both versions ("plugin upgraded mid-transaction — supersede and regenerate").
- Legacy direct callers (tests, docs snippets) without the new flags: byte-identical behaviour, regression-asserted.
- Authority present but the transaction file deleted between phases: the next phase dies on the linkage check naming the exact missing path — a transaction is never implicitly recreated mid-run.

**Dependencies:**
- Depends on: Step 13

**Acceptance Criteria:**
- [ ] All seven verification fixtures pass with the named-field failure messages.
- [ ] Pipeline path shows zero CP1 gate invocations after phase 1 across a 3-phase run.
- [ ] Standalone path regression-asserted gate-active.

**Effort:** M
**AID Role:** backend

### Step 15: Transaction manifest with hash-derived resume

**Objective:** Generation records a durable transaction manifest before phase 1 and a rerun with the same identity resumes — verifying each phase's recorded outputs by hash and queue membership, regenerating only what fails verification — while a different identity refuses cleanly.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (pre-phase region after the authority write, phase loop ~437-733, stage-2 loop ~739-778) — write `transaction.json` (`aid-generation-transaction/v1`: plan_id, plan_sha256, target_head, phase_derivation_version, total_phases, authority_sha256, phases map N → {epic_id, run_id, epic_sha256, plan_json_sha256}, created_at, updated_at) before phase 1; after each phase's outputs are written, update its entry atomically (mktemp+mv) BEFORE proceeding; on startup, if a transaction with MATCHING identity exists, resume: per phase verify recorded hashes against the files on disk and (stage 2) queue membership — verified phases are skipped with a log line, failed verification regenerates that phase; MISMATCHED identity: when the existing transaction is INCOMPLETE, refuse naming both identities and `supersede-generation`; when it is COMPLETE, roll over automatically — atomically archive the completed authority/transaction pair to `.completed-<epoch>` siblings (shared epoch) and start the new transaction, so a completed record is never clobbered at its fixed live path (changed-plan-after-completion fixture asserts the archive pair + fresh start).
- Create: `plugins/aid-orchestrator/defaults/schemas/generation-transaction.schema.json` — the shape above, additionalProperties false, phases-map values requiring epic_id/run_id, allowing the two hashes to be absent until written, and declaring the optional `queued` boolean the adopt-from-queue path sets.
- Modify: `plugins/aid-orchestrator/scripts/aid-queue-add.sh` (duplicate check region ~330-345) — new flag `--transaction <path>`: when the queue already holds the epic_id AND the transaction's recorded entry matches the queued entry (epic_id + plan_ref), the duplicate becomes a verified idempotent SKIP (exit 0, log line); a duplicate NOT owned by the transaction keeps today's hard fail.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-queue-write.sh` (lines ~1055-1070, `queue_append_entry`) — the SECOND, status-blind duplicate refusal inside the locked writer gains the same transaction-ownership awareness (threaded as an optional parameter), so the skip decision is made once and consistently under the lock — never a pass at the CLI layer followed by a hard fail inside the writer.
- Modify: `plugins/aid-orchestrator/scripts/aid-generation-finalize.sh` (receipt composer ~115-125) — after stage 2 completes, the pipeline rewrites the receipt's per-epic `queue_status` to the final values and recomputes the receipt's self-consistency (fixing the grounded stale-`pending_receipt` defect); per-epic hashes are untouched; the update is a full re-canonicalize + atomic rewrite by the same composer function (single writer).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-generation-resume.bats` — kill after phase 1 → rerun resumes at phase 2 with identical IDs and ZERO duplicate queue entries (the 2026-08-04 live failure, now green); kill between stage 1 and stage 2 → rerun skips regeneration, completes packaging/queueing; a corrupted phase output (hash mismatch) is regenerated in place; an edited plan (new identity) refuses naming `supersede-generation`; the final receipt carries real queue statuses.

**Architecture Context:** Grounding F3/F4: today a rerun regenerates from phase 1, silently overwrites outputs, and dies at the queue duplicate leaving phases 2..N stranded — there is no state to resume from. The Codex round simplified the manifest to identity + IDs + hashes with DERIVED status (no five-state enum to keep synchronized): the files and the queue are the truth, the manifest is the binding that lets the pipeline verify rather than blindly redo.

**Implementation Detail:** Identity = (plan_sha256, target_head, phase_derivation_version, total_phases) — the exact tuple the authority seals, so authority and transaction can never disagree (linked by authority_sha256, verified per phase by Step 14). Hash verification reuses the sha256 helpers `aid-generation-finalize.sh` already applies to the same files. Every transaction.json update is a locked read-modify-write (`lib/aid-lock.sh` flock on a `.lock` sidecar, then atomic tmp+mv) so two pipeline invocations never interleave a lost update; the adopt-from-queue path records an optional per-phase `queued: true` field (declared in the schema) when it adopts an entry the manifest missed; and the resume completion check treats a transaction whose final receipt queue-status rewrite has not happened as INCOMPLETE — the completion short-circuit fires only after the rewrite, so a crash before it can always resume. The stage-2 receipt rewrite happens after the last queue-add so `queue_status` is final at write time; `aid-json-to-run.sh`'s existing consumer contract (schema + plan_sha256 + per-epic binding) is unaffected because those fields never change on rewrite (regression-asserted in the bats file).

**Error Handling:** Transaction write failure at any transition aborts before the state it records exists on disk unverified (write-ahead ordering). A resume finding the queue entry present but the transaction UNAWARE of it (crash before manifest update, after queue-add) treats the queue as truth: verify the queued entry matches the derived IDs, adopt it into the manifest, continue.

**Edge Cases:**
- Resume after the plugin was upgraded (derivation version changed): identity mismatch → refuse with the supersede pointer (never mix artifacts from two derivations).
- Total-phase count changed by a plan edit: new identity by definition (plan_sha256 changed) — same refusal.
- Two concurrent pipeline invocations for the SAME plan: the second sees the transaction with matching identity and resumes — verification makes this converge (both verify, at worst one regenerates what the other just wrote and hash-verifies equal); queue-add's flock serializes the append.

**Dependencies:**
- Depends on: Step 14

**Acceptance Criteria:**
- [ ] Kill/resume fixtures pass at both kill points with zero duplicates and identical IDs; the wired chain invokes the CP1 gate exactly ONCE across a full 3-phase run (call-count stub — the plan-scoped authority AC deferred from Step 13).
- [ ] Corrupted-output regeneration and identity-mismatch refusal pass.
- [ ] Final receipt carries real queue statuses; `aid-json-to-run.sh` consumer contract regression-asserted.

**Effort:** L
**AID Role:** backend

### Step 16: supersede-generation recovery

**Objective:** An incomplete generation transaction can be explicitly archived by a PM with an audited reason, unblocking a changed-identity regeneration without ever silently mixing artifacts from two derivations.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (argument loop ~43-55, new top-level mode) — `supersede-generation --plan <path> --reason "<≥20 chars>"` as a separate invocation (never combined with generation flags; PM-only is an instruction-only actor rule, stated as such — the audit record is the enforcement surface): renames `transaction.json` and `generation-authority.json` to `.superseded-<epoch>` siblings, writes an audit record (P073 three-record pattern, event `generation_superseded`, the reason and both identities), prints what was generated (from the archived manifest) and the explicit note that cleanup of already-created EPIC files/branches/queue entries stays with the existing recovery commands (`plan-rollback`, queue removal); it deletes nothing itself.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (Generate EPIC section, lines ~356-372) — documents the flag pair, the transaction/resume behaviour, and supersede as the recovery for a changed plan.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — entries for the authority verification (Step 14), transaction identity refusal (Step 15), and the supersede transaction (this step), each with type/source/instruction/severity/surface.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-supersede-generation.bats` — supersede archives both files with the same epoch and writes the audit record; a subsequent generation with the new identity starts a fresh transaction; supersede with a short reason dies; supersede with NO incomplete transaction refuses ("nothing to supersede"); the archived manifest is listed in the command's output verbatim.

**Architecture Context:** The Codex round moved supersession out of the ordinary pipeline (a differing identity plainly refuses; archiving is a deliberate separate PM act) and demanded its documentation + registry entry explicitly. The no-deletion rule mirrors §16a's cancellation contract: record what was generated, leave destructive cleanup to the lifecycle-safe recovery paths.

**Implementation Detail:** Epoch shared between both renames so the pair is identifiable; the audit record carries both files' post-rename paths and sha256s. Refusal when the existing transaction is COMPLETE (all phases verified, queue statuses final): a complete transaction needs no supersession — the Step 15 automatic rollover archives it to `.completed-<epoch>` and a changed plan starts fresh; the command says exactly that and names the rollover.

**Error Handling:** Rename failure mid-pair (first succeeded, second failed): the command retries the second once, then reports the half-archived state with the exact mv to finish — and a REPEATED supersede call detects the half-archived pair (one `.superseded-*` sibling present, its partner live) and completes exactly the missing rename instead of archiving a fresh epoch, making recovery idempotent.

**Edge Cases:**
- Supersede while a pipeline process is live on the same transaction: the live process's next atomic manifest update fails on the missing file and aborts with a clear message — acceptable, and the bats file pins that message.
- Repeated supersede calls: each archives whatever incomplete pair exists at that moment; with none present, the "nothing to supersede" refusal makes it idempotent in effect.
- `--plan` pointing at a different plan than the incomplete transaction's recorded plan_id: refuse naming both IDs — the flag must match the archived identity, never a cross-plan archive.

**Dependencies:**
- Depends on: Step 15

**Acceptance Criteria:**
- [ ] Archive + audit + fresh-start fixtures pass; short-reason and nothing-to-supersede refusals pass.
- [ ] Registry entries exist for Steps 14, 15, and 16 mechanisms.
- [ ] aid-plan.md documents transaction, resume, and supersede in the Generate EPIC section.

**Effort:** M
**AID Role:** backend

### Step 17: Parser and diagnosis defect fixes

**Objective:** The three generation defects found live on 2026-08-04 are fixed properly: the adjudicator empty-list forms parse as empty, the steps-table splitter honours escaped pipes with hard arity errors, and an off-target-branch run is diagnosed as exactly that.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-cp1-gate.sh` (lines ~520-546) — after `accepted_blockers:` the forms `- []`, `- none`, `- (none)` (case-insensitive, whitespace-tolerant) parse as EMPTY; a genuine `- <text>` item still fails; an INDENTED/nested `accepted_blockers:` key (today a silent "no field" pass, lines ~522-526) becomes a loud structural error naming the line; the same treatment applies to the `rejected_blockers` read.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (line ~942) — the producer escape becomes an unambiguous two-rule grammar: literal backslash → `\\` FIRST, then literal pipe → `\|` (today only pipes are escaped, so `\|` in a cell is ambiguous between "escaped pipe" and "field-final backslash + delimiter").
- Modify: `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh` (lines ~176-196) — replace the `IFS='|' read` split with a small character-walk splitter decoding that grammar (`\\`→`\`, `\|`→`|`, backslash-flag walk — now unambiguous by construction); replace the silent short-row `---` padding (lines ~184-189) with a hard error naming the row and its field count versus the expected five; legacy rows containing neither escape decode byte-identically.
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (lifecycle-ensure error region, lines ~389-400) — discriminate rc=3 from the manifest-ensure call: the message becomes `you are on '<current>' but lifecycle writes require '<target>' — run: git checkout <target>, or run generation for a worktree-recorded plan from its plan worktree` with NO grammar advice on this path; other rcs keep the existing message.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-generation-parsers.bats` — adjudicator: all three empty forms pass, a real blocker item fails, the nested-key case errors loudly; table: an Objective containing one and two `|` characters round-trips intact through plan-to-epic → epic-to-json (depends_on lands correctly), a hand-broken four-field row dies naming the row; branch: an off-target run produces the branch message with zero grammar advice, an on-target grammar failure keeps the grammar message.

**Architecture Context:** Grounding items F6-F8 confirmed all three with exact mechanics: the syntactic `- ` probe at gate :539, the escape-blind byte split plus masking pad at epic-to-json :181-189, and the rc-blind exit-6 message at pipeline :396. Each fix is the proper version the Codex round selected (no sentinel characters, no tolerance for masked arity errors, no stacked diagnoses).

**Implementation Detail:** The character-walk splitter is a ~15-line bash loop (append char unless unescaped `|`, track a backslash flag) producing an array; it replaces only the row-splitting — field trimming and downstream logic unchanged. The rc discrimination threads the ensure call's rc into the error branch (today it is interpolated but not branched on).

**Error Handling:** All three fixes convert silent wrong behaviour into named errors; no new silent paths are introduced (the arity error names row content, the nested-key error names the line number, the branch message names both branches).

**Edge Cases:**
- Objective ending in a literal backslash before a real delimiter: the producer escapes only pipes, so a trailing `\` is data; the splitter emits it verbatim and the round-trip case covers it.
- Adjudicator file using inline `accepted_blockers: []` (the current canonical form): parses as empty exactly as today — regression-asserted.
- Legacy adjudicator fixtures in existing test suites: swept during implementation for the three empty forms; any fixture relying on the old `- []`-fails behaviour is updated with the fix (expected: the P073-era fixtures).

**Dependencies:**
- Depends on: ---

**Acceptance Criteria:**
- [ ] All adjudicator, table, and branch-message fixtures pass, including round-trip pipes in Objectives.
- [ ] The nested-key silent pass is now a loud error (regression case).
- [ ] No grammar advice appears on the rc=3 path; existing grammar failures unchanged.

**Effort:** M
**AID Role:** backend

### Step 18: Honest failure labels and generation instruction sweep

**Objective:** Generation failures render as exactly two AID-owned labels — `aid_cp1_blocked` and `aid_generation_force_required` (printing the exact public force command) — with everything else passed through verbatim, and every instruction surface describing per-phase gate/override behaviour is rewritten to the transaction model.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (gate-failure branch from Step 13, exit paths) — first line of stderr on a gate failure is the label: `aid_cp1_blocked:` when force is unavailable for the failed condition class, `aid_generation_force_required:` plus the verbatim `aid-auto-pipeline.sh --plan <path> --queue-mode <mode> --force --reason '<why>'` when force applies; any subprocess failure that is NOT a recognized gate outcome is passed through verbatim, appending `note: AID's own checks passed — this failure is not an AID gate` ONLY when the gate had already passed in this run.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (C0 loop and override sections, lines ~425-602) — the per-gate override semantics rewritten: the ledger/recheck loop is unchanged during PLAN REVIEW, but EPIC GENERATION consumes one plan-scoped authority (the `.consumed-<epoch>` per-gate claim wording at ~553-568 scoped to standalone invocations); the pm-override grant section cross-references the pipeline `--force` as the generation-time PM path.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~178-236) — the PRE-FLIGHT generation chain now reads: authority once, phases verify, finalize, init/queue with transaction.
- Modify: `plugins/aid-orchestrator/skills/planner.md` (lines ~24-100) — the chain/stage sections rewritten to the transaction model; the error table around lines 215-233 gains the authority/transaction failure rows.
- Modify: `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` (lines ~109-261) — line ~157 states the gate is called once per TRANSACTION by the pipeline and per invocation standalone; the once-per-plan override wording at line ~247 corrected to the authority model.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (PRE-FLIGHT lines ~146-179) — the numbered chain and progress block gain the authority/transaction stages.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-generation-labels.bats` — a blocked high-risk fixture prints `aid_generation_force_required:` with the exact copy-pasteable command; a hard-blocked condition prints `aid_cp1_blocked:`; a stubbed subprocess crash after gate pass prints the verbatim error plus the not-an-AID-gate note; a crash BEFORE gate pass prints verbatim with no note.

**Architecture Context:** PM decision 3 dropped the host-error detector as guesswork; what remains is fully decidable from AID's own state: which gate condition failed, whether force could cover it, and whether AID's checks had passed when the foreign failure occurred. The instruction sweep covers every surface the grounding enumerated as describing per-phase CP1/override behaviour — the "no kočkopes" directive: after this step no live instruction claims the old model.

**Implementation Detail:** Label constants live in the pipeline script only (two call sites); the force-required label includes the user's actual `--plan`/`--queue-mode` values so the printed command is executable as-is. The instruction rewrites are static text with the new static numbers/paths — no derivation claims.

**Error Handling:** The labeling wraps existing failures; no failure class loses information (the underlying gate stderr always follows the label line).

**Edge Cases:**
- Gate failure where SOME conditions are forceable and one is hard: `aid_cp1_blocked` wins (force would not unblock), and the message names the hard condition first.
- Resume runs (Step 15) that skip the gate: label logic never fires; a resume-time authority verification failure uses Step 14's named-field messages.
- A gate stderr that already begins with one of the two labels (wrapper double-invocation): the pipeline checks the first line before prefixing so a label is never duplicated.

**Dependencies:**
- Depends on: Step 15

**Acceptance Criteria:**
- [ ] All four label fixtures pass with copy-pasteable force command.
- [ ] `grep -rn 'per phase' plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` confirms the gate call-site sentence states the transaction model.
- [ ] No live instruction surface still describes per-phase override consumption for pipeline runs (sweep grep in the bats file).

**Effort:** M
**AID Role:** docs-writer

### Step 19: Two-stream integration fixture, registry closure, and release metadata

**Objective:** One integration fixture proves the whole promise — plan B is written and generated while plan A implements in its worktree, and a killed generation resumes — and every enforcement, CHANGELOG, and source-document annotation lands.

**Files:**
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-p074-integration.bats` — fixture repo with two plans: plan A started (worktree created, one EPIC init'd and mid-execution inside the worktree); WHILE A is active and the primary checkout carries an unrelated dirty edit: allocate plan B's ID (locked), write its plan file, run generation end-to-end (authority once, 3 phases, queued) — all from the primary checkout with its HEAD never switching (asserted before/after each command); kill B's generation after phase 1 and resume to completion; run A's done-advance + epic-merge-to-plan in the worktree; `/aid-status` data files render both streams; a main-branch commit is blocked while either run governs main.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — closure verification pass: entries from Steps 5, 14, 15, 16 exist (Steps 5/16 self-register, this step verifies); new entries for the worktree enforcer (Step 8), topology enforcement (Step 9), hook worktree-resolution (Step 2), locked allocation (Step 3), active-runs map + prune (Step 4), the authority writer (Step 13), and the parser hard-errors (Step 17), each with type/source/instruction/severity/surface.
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — identical entries (Added: per-plan execution worktrees, locked ID allocation, active-runs map, generation transaction with resume + public force, supersede-generation; Changed: scoped preflights, status two-stream view, hook worktree safety; Fixed: adjudicator empty-list parse, escaped-pipe table split, target-branch diagnosis, stale receipt queue_status); release itself happens at the plan-final boundary under plan_branch mode.
- Modify: `docs/extending-aid.md` — sections for the roots contract (state root vs invoke root), the worktree lifecycle (create/enforce/teardown/repair), and the generation transaction (authority, manifest, resume, supersede) with the consumer table.
- Modify: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` (§16a and §17 annotation blocks) — verification-only sweep: the "Plan written: P074" and "STILL OPEN" blocks match what this plan actually delivers; discrepancies found during implementation are corrected in the annotations (blockquote lines only).
- Modify: `plugins/aid-orchestrator/skills/memory.md` (footer) — `Last Updated` bumps for every skill/command touched across Steps 1-18 (verification pass; each owning step already bumps its own).
- Test: `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` — run over every modified skill/command; new files lint clean.

**Architecture Context:** CLAUDE.md mandates registry completeness, identical CHANGELOGs, and Last Updated bumps; the PM directive mandates that adopted source-doc points stay truthfully marked. The integration fixture is the plan's acceptance instrument: it exercises the exact 2026-08-04/2026-08-05 pain sequence (dirty tree + plan B + kill + resume + review isolation) end to end. New suites register with the P069 catalog through its existing approval flow (`aid-test-catalog-approve.sh`), and runtimes feed the existing baseline tooling — same contract P073 Step 19 uses.

**Implementation Detail:** The fixture builds on `$BATS_TEST_TMPDIR` with a scripted primary repo + installed hooks, reusing the stubbing approach of the existing plan-final suites for review outputs; Codex-dependent stages are stubbed; `yq` absence skips with a named reason (never a false PASS). HEAD-stability assertions bracket every plan-B command (`git symbolic-ref HEAD` before/after byte-equal).

**Error Handling:** Any integration assertion failure names the stream (A or B), the command, and the fixture commit driving it, so regressions bisect to one step.

**Edge Cases:**
- CI without worktree-capable git (ancient version): suite skips with a named reason and the version found.
- Runtime budget: the fixture registers a measured baseline; if it exceeds the bats_all headroom, it is registered in the slow lane per the P069 catalog contract rather than silently trimmed.
- The two-stream fixture on a filesystem without flock: allocation/queue cases skip with a named reason (matching lib/aid-lock.sh's documented degradation).

**Dependencies:**
- Depends on: Step 18

**Acceptance Criteria:**
- [ ] `test-p074-integration.bats` passes end-to-end on a clean checkout, including HEAD-stability and kill/resume assertions.
- [ ] Registry closure pass finds every Step 2/3/4/5/8/9/13/14/15/16/17 mechanism registered.
- [ ] Both CHANGELOGs identical; skill lint clean; source-doc annotations verified truthful.

**Effort:** L
**AID Role:** qa

## Testing Strategy

Every step lands with its own bats coverage in `plugins/aid-orchestrator/scripts/tests/bats/` — twelve new suite files named in the step Files entries (`test-roots-worktree`, `test-hooks-worktree`, `test-alloc-lock`, `test-active-runs-map`, `test-scoped-preflights`, `test-active-index`, `test-plan-worktree-create`, `test-worktree-enforcement`, `test-worktree-topology`, `test-drift-worktree`, `test-worktree-teardown`, `test-status-two-streams`) plus the EPIC 3 files (`test-generation-authority`, `test-authority-verify`, `test-generation-resume`, `test-supersede-generation`, `test-generation-parsers`, `test-generation-labels`) and the closing `test-p074-integration.bats`. Convention note: a `Test:` Files entry naming a bats file that does not yet exist IS the instruction to create it in that step; all files are auto-discovered by `scripts/tests/run-all-tests.sh`. Test tiers: function-level (resolver, splitter, allocator), command-level fixtures (each builds a disposable git repo with linked worktrees in `$BATS_TEST_TMPDIR`), and the one end-to-end two-stream fixture. Regression discipline: every step that changes behaviour for legacy plans (no recorded worktree) carries a byte-identical legacy assertion; golden comparisons cover the migrated root-resolution paths from the primary checkout. Runtime discipline per the quarantine policy: no full-suite requirement per step; new suites enter the P069 catalog via its approval flow with measured baselines.

## Constraints

- Implementation starts only after P073 merges to `main`: Step 5 reuses P073's ancillary classifier, Steps 8/11/13/16 reuse its force/audit writers, and both plans edit the same preflight/pipeline regions (declared as `depends_on_plans: [P073]` in frontmatter).
- P069's scheduler and test-catalog contract are untouched beyond registering new suites through the existing approval flow.
- All plugin code and documentation in English; PM conversation in Czech.
- CHANGELOG discipline per CLAUDE.md: root and plugin CHANGELOGs identical; version bumps only through the plan-final release boundary (`plan_branch` mode).
- Every new or removed detection capability is registered in `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` with its enforcement mechanism named at design time (AID-v3-principles §1); removed preflights are recorded in place, never silently deleted.
- Machine compatibility surfaces frozen: `fsm-state.yaml` fields, `get-state` JSON, evidence filenames and layout, queue entry shape, the `aid-generation-receipt/v1` fields consumed by `aid-json-to-run.sh`.
- Legacy single-stream behaviour is preserved wherever a plan has no recorded worktree; nothing forces existing in-flight plans onto the new model.
- The PM loosening directive is binding: the only NEW refusals this plan introduces are validity checks inside its own new mechanisms (authority/transaction verification, supersede preconditions, nested-key parser error, table arity error) — each converts a silent wrong outcome into a named error and prints its recovery.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Worktree redirect breaks an existing caller's cwd assumptions | Medium | High | Redirect preserves argv verbatim with a loop-guard; legacy plans bypass entirely; byte-identical legacy assertions in every EPIC 2 suite |
| Root-resolver migration changes primary-checkout behaviour | Low | High | Golden before/after comparison on a scripted primary-checkout sequence (Step 1 AC) |
| Authority/transaction adds friction to the happy path | Low | Medium | Zero new PM interaction on a passing plan (authority is written and verified silently); resume strictly removes friction |
| Hook inline resolver diverges from lib logic over time | Medium | Low | Commented as a copy with the lib named; worktree hook suite fails on divergence in behaviour |
| Two concurrent pipelines on one plan corrupt the transaction | Low | Medium | Atomic manifest writes + hash verification converge; queue flock serializes; explicit bats case |
| P073 merge conflicts (same regions) | Medium | Medium | Hard sequencing via depends_on_plans; grounding cites post-P073 line anchors where known stale |
| Teardown failure blocks plan closure | Low | High | Teardown is best-effort with verbatim manual cleanup; terminal operations never block (P082 lesson) |

## Success Criteria

- The PM writes and fully generates plan B — locked ID, plan file, authority, 3 phases, queue — from the primary checkout while plan A's EPIC executes in its worktree, with a dirty primary tree throughout and the primary HEAD never moving (integration fixture).
- A PM edit in the primary checkout during plan A's review window does not invalidate the review; an edit inside the plan worktree still does.
- A 3-phase high-risk generation consumes exactly one CP1 gate decision and, when forced, exactly one PM `--force --reason`; a kill at any phase boundary resumes with identical IDs and zero duplicate queue entries.
- Commits from linked worktrees are guarded by the same hooks as the primary checkout; a main-branch commit is blocked while ANY active run governs main.
- Every previously silent failure this plan touches (adjudicator format, table arity, wrong-branch, forked `.aid-o`, duplicate plan ID) now fails loudly with a named recovery.
- All new suites green; skill lint clean; enforcement registry complete; both CHANGELOGs identical.

## Acceptance Criteria

- [ ] AC1: The shared root resolver exists and parses.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -n plugins/aid-orchestrator/scripts/lib/aid-roots.sh"
  expected_exit: 0
```
- [ ] AC2: The pipeline carries the force-required label and therefore the public force path.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh
  regex: "aid_generation_force_required"
```
- [ ] AC3: The generation-authority schema ships.
```yaml
verification_pattern:
  type: cmd
  cmd: "test -f plugins/aid-orchestrator/defaults/schemas/generation-authority.schema.json"
  expected_exit: 0
```
- [ ] AC4: The phase generator carries the authority verifier.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh
  regex: "_verify_generation_authority"
```
- [ ] AC5: The preflight carries the per-caller clean-tree parameter introduced by Step 5.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-plan-fsm.sh
  regex: "needs_clean_tree"
```
- [ ] AC6: The worktree enforcer exists in the plan FSM.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-plan-fsm.sh
  regex: "_pfsm_require_plan_worktree"
```
- [ ] AC7: The locked allocator subcommand exists.
```yaml
verification_pattern:
  type: must_contain
  file: plugins/aid-orchestrator/scripts/aid-fsm.sh
  regex: "alloc plan-id"
```
- [ ] AC8: The integration suite exists.
```yaml
verification_pattern:
  type: cmd
  cmd: "test -f plugins/aid-orchestrator/scripts/tests/bats/test-p074-integration.bats"
  expected_exit: 0
```

## Next Steps

- All five interim decision points were approved by the PM on 2026-08-05 (decision record: `.aid-o/work/interim-P074.md`); the source document carries the P074 annotations with explicit STILL OPEN blocks. No PM decision is currently pending; like any plan, this document remains revisable through the normal review mechanisms.
- `/aid-plan epic .aid-o/plans/P074-project-concurrency-generation-transaction.md` — EPIC generation (chain queue mode: EPIC 1 → 2 → 3); the plan is high-risk, so CP1-deep plus the C0 cross-provider review loop gate generation.
- Implementation begins only after P073 merges to `main` per the Constraints section (`depends_on_plans: [P073]`).
