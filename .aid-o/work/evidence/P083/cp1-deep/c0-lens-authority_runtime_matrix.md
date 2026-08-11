# CP1-deep — C0 lens authority_runtime_matrix — P083

Question: does any planned mutation cross an ownership, authority or runtime boundary it should not?

Method: every path the plan names was classified against the real tree (plugin / defaults / this
repo's workspace / tracked docs), the P080 worktree was inspected read-only, and each claimed
one-side fix was checked for the other side. Nothing below is taken from the plan's paraphrase.

stop_rule_blockers: 3

- **B1 — Step 5's config fix has no owning checkout, and the plan already knows why that matters.**
  Plan line 199: "Modify: `.aid-o/config/execution.yaml` (lines ~218-228) — the self-host `plan_diff`
  gate regains the `command:`". `.gitignore:96-98` ignores `.aid-o/` and `**/.aid-o/`, so that edit is
  never committed and never merges anywhere. Worse, it is not even shared between checkouts: a live
  plan worktree carries a *snapshot copy*, verified byte-identical today
  (`diff .aid-o/config/execution.yaml .aid-worktrees/plan-P080/.aid-o/config/execution.yaml` →
  identical; the copy at `.aid-worktrees/plan-P080/.aid-o/config/execution.yaml:223-226` still has
  the command-less gate and the "P038+" note). P083 will itself execute in a plan worktree. An edit
  made there dies with the worktree; an edit made in the main checkout does not reach an
  already-created worktree. The plan states the rule for the analogous case and then does not apply
  it to its own step: line 140 "`.aid-o/config/project.yaml`, which is gitignored, so **any clone or
  worktree takes the fallback**", and line 203 "Because `.aid-o/` is gitignored there is no history".
  Compounding it, AC6 (line 435) verifies `yq -r '.gates.plan_diff.command' .aid-o/config/execution.yaml`
  — evaluated in whichever tree the gate run happens to be in, so it passes on a worktree-local edit
  that leaves the repo's live config broken, and fails on a main-checkout edit made after the
  worktree existed. The step needs an explicit rule naming the checkout the edit lands in and a
  worktree-refresh obligation; the AC needs to assert the durable location, not the ambient one.

- **B2 — Step 5's shipped runner refusal fires on in-flight worktrees of this repo, which the plan
  does not consider.** Plan line 200: "a gate that appears in a profile's `include[]` with no
  `command` is a loud configuration refusal, not a `skip/no_command` row, so this cannot silently
  recur in any project." The current behaviour is `aid-run-gates.sh:1953-1963` (WARN + skip row).
  The only blast-radius edge case the plan writes is line 211, "A consumer project whose config
  predates this change — the refusal fires on their first run with a message that says what to add;
  this is stated in the CHANGELOG as a breaking configuration check." That covers other projects and
  misses this one: `.aid-worktrees/plan-P080` already holds a snapshot config with `plan_diff` in
  five profiles and no command, so once the refusal reaches a runner P080's tree executes (its next
  rebase/merge of main, or a plan-final run using a main-derived plugin path), P080's own gate run
  hard-fails on a config it cannot fix by merging. The plan states no ordering requirement between
  the config repair and the runner refusal, and no migration/version guard on the shipped side. A
  CHANGELOG line is not an enforcement mechanism for a hard refusal that lands in other people's
  runtimes mid-flight (AID-v3-principles §1's inverse: enforcement shipped without a migration is
  still an unowned break). Minimum: land the refusal only behind a config-version or opt-in key, or
  sequence config-fix-then-refusal and name the worktree-refresh step.

- **B3 — the P080 constraint names files P080 does not touch and misses the one it is rewriting.**
  Plan line 45: "Anything in `commands/aid-init.md`, `skills/` help surfaces or `defaults/templates/`
  — P080 is live in `.aid-worktrees/plan-P080` and owns those files", repeated at line 476. Verified
  read-only: `git -C .aid-worktrees/plan-P080 status --porcelain` is empty, and
  `git -C .aid-worktrees/plan-P080 diff --name-only main...HEAD` returns exactly:
  `plugins/aid-orchestrator/commands/aid-help.md`,
  `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`,
  `plugins/aid-orchestrator/defaults/help-index.yaml`,
  `plugins/aid-orchestrator/scripts/lib/aid-help-index.sh`,
  `plugins/aid-orchestrator/scripts/tests/bats/test-help-index-coverage.bats`,
  `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh`,
  `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-test-audit.sh`,
  `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh`.
  `commands/aid-init.md` and `defaults/templates/` are not in that set at all. What *is* in it is
  `defaults/enforcement-registry.yaml` and its two cite-tests — and plan line 479 commits P083 to
  writing that exact file: "Steps 5 and 10 add a refusal *inside an existing check*; … both are
  registered in the enforcement registry in the same commit that adds them." So the plan's declared
  constraint protects two files nobody is editing while leaving the single real collision unguarded,
  and Step 7's wait (line 280, "must not be started while P080 holds `.aid-worktrees/plan-P080`")
  guards `lib/aid-init-execution-yaml.sh`, which P080 never touches. Two registries exist
  (`plugins/aid-orchestrator/defaults/enforcement-registry.yaml` and
  `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml`, the latter being what CLAUDE.md
  still names at its pre-archive path) and the plan names neither, so which one Steps 5/10 write is
  also undetermined.

findings:

- **F1 (medium) — Step 9 gives C0 write authority over an artifact another stage explicitly owns,
  and does not say where it writes.** Plan line 328: "`build-manifest` produces the provisional graph
  itself, by invoking `aid-generation-readiness.sh --write-provisional` for the plan under review,
  before sealing the manifest." No path is named. The only existing caller is the generation
  producer: `aid-plan-to-epic.sh:136` writes
  `.aid-o/work/evidence/${plan_id}/generation/provisional-graph.json`, and its comment at :129-130
  is a written ownership rule — "Keep it under generation/: c0/plan-graph.json has a different owner
  and meaning after an EPIC exists". Downstream, `aid-generation-finalize.sh:112-120` hard-fails on a
  missing/stale provisional and then asserts `provisional_canonical == final_canonical` — a
  producer-integrity check whose whole point is that the artifact came from the generation run. If
  C0's manifest step writes to that path, the reviewer mints the artifact a later authority validates
  as an independent producer output; if it writes elsewhere, the prompt edit at line 329 must name
  that other path. Either way the step must state the path and, if it is the generation path, say why
  pre-minting does not hollow out `aid-generation-finalize.sh:119`.

- **F2 (low) — Step 5's scope statement undercounts the profiles it changes.** Plan line 203: "the
  gate sits in four merge-path profiles"; line 60 repeats "four". Actual, from the file the step
  edits: `yq '.gate_profiles | to_entries[] | select(.value.include[]? == "plan_diff") | .key'
  .aid-o/config/execution.yaml` → `standard`, `full`, `release`, `bats_all_quarantine`,
  `release_quarantine` — five. Edge case line 212 names only `release_quarantine`, so
  `bats_all_quarantine` is unconsidered. AC line 219 ("No profile in this repository's own
  `execution.yaml` includes a gate without a `command`") sweeps all of them, so the count matters for
  what the step must verify.

Verified clean (checked, no finding):

- **Step 7's side-choice is correct.** `render_gate_profiles_block` at
  `lib/aid-init-execution-yaml.sh:206-266` really does emit only `targeted` and `full`
  (here-doc :258-265), the zero-stacks branch really is :239-242, and the step's refusal to touch
  `defaults/execution.yaml` matches the recorded P064 decision the plan cites. Consumers get their
  table from this composer, not from defaults, so fixing the composer is the consumer-facing side.
- **Step 5's refusal does not break freshly composed consumer workspaces.** The composer builds
  `include[]` only from gate names the detected stack fragments define, plus `targeted_tests`
  (:246-253) — it never emits `plan_diff`, so a command-less gate cannot appear in a composed
  profile. The consumer exposure is limited to hand-written or older copied configs (and to B2's
  in-flight worktrees).
- **`defaults/execution.yaml` is not the defective side.** `defaults/execution.yaml:109-115` carries
  `plan_diff` with `required: true` and a real `command:`, exactly as the plan claims — no
  fix-one-side gap between defaults and the shipped runner.
- **Step 9's prompt is read from the plugin, not from a consumer copy.**
  `lib/aid-c0-plan-review.sh:112` resolves `$PLUGIN_ROOT/defaults/prompts/c0-plan-review-prompt-v1.md`
  and no `.aid-o/config/prompts/` copy exists, so editing the shipped prompt is the whole fix.
- **Step 10's shipped suite touching this repo's tracked backlog has precedent.**
  `docs/plans/2026-06-29-BACKLOG.md` is the one negated path in the `docs/` ignore (`.gitignore:87,93`),
  and `test-deferred-work-registration.bats` / `test-aid-plan-close-check.bats` already reference it —
  not a new boundary. Same for Step 8's dependence on `.aid-o/metrics/gate-runtime-baselines.yaml`
  (`lib/aid-gate-runtime-baseline.sh:125`), which six existing suites already read.
- **No step grants an agent an approval, override or bypass the PM alone should grant.** Steps 5, 6
  and 8 all move in the fail-closed direction (skip→refusal, fail-open toggle→named failure,
  silent branch→named refusal); Step 9 explicitly preserves the plan-hash binding refusal (line 336);
  no step introduces a waiver, force path or self-attested pass.

confidence: high — every boundary claim above is anchored to a first-hand read of the named file at
the named lines and to a read-only inspection of the P080 worktree; the one place I stopped short of
a verdict is F1, where the plan's silence on the write path is itself the finding.
