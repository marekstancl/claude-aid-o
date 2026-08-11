# Backlog verification — block 3 (2026-08-11, main @ v2.83.1)

All paths relative to `plugins/aid-orchestrator/` unless stated otherwise.
Read-only verification; nothing was modified.

---

## OBS-20260702-01
verdict: REAL (narrowed — the sanctioned path now exists, the bypass and the evidence overwrite do not)
evidence:
- `scripts/aid-fsm.sh:4586-4589` — the duplicate-init guard is now UNCONDITIONAL (`state_file already exists` → exit 1); it is not waivable by `--force` (the `--force` arm at `:4346-4360` only waives the structured `depends_on_plans` D1 block, stated in its own comment at `:4347-4349`).
- `scripts/aid-fsm.sh:4591-4647` — P073 "ONE narrow supersede exception": re-init is allowed only when a `fsm-state.yaml.superseded-<epoch>` archive exists AND a `plan-state/supersede-<plan>-<epic>-<epoch>.json` record matches on five re-derived fields (plan_id, epic_id, old_run_id, old_state_sha256, new_plan_json_sha256). Consumed exactly once at `:4975-4981`.
- `scripts/aid-plan-fsm.sh:8363-8519` — `plan-state --supersede-epic` is the transaction: ≥20-char `--reason`, refuses `merged_to_plan`, flock-serialized, record-then-archive. It prints `"Evidence artifacts are untouched"` (`:8515`) — i.e. it archives ONLY the state file.
- `scripts/aid-epic-to-json.sh:943-944` — `plan_json_path="${evidence_dir}/plan.json"; echo "$plan_json" > "$plan_json_path"` — regeneration still overwrites plan.json IN PLACE, no archive, no snapshot.
- `scripts/aid-fsm.sh:4724-4726, 4985-4991` — `cmd_init` creates/derives `timeline.jsonl` and appends `fsm_init` with no inspection of pre-existing `fsm_init` events. `grep -n 'fsm_init\b' scripts/aid-fsm.sh` returns exactly two hits (`:4990` write, `:5997` comment) — nothing reads them back.
what_is_true: The entry's "likely fix" largely shipped as P073 supersede: there is now a first-class, audited retire-and-re-init path, and plain re-init over a live state file is refused unconditionally. Two of the entry's three named symptoms survive. (a) The hand-delete bypass is still silent: `rm fsm-state.yaml` leaves no archive, so the supersede check at :4612 never triggers, init proceeds normally and appends a second `fsm_init` that nothing detects. (b) Even on the sanctioned path, `plan.json`/`epic_input.md` are still overwritten in place at regeneration, so the pre-descope plan is still unrecoverable — only the state file is archived. Run_id reuse is now a deliberate property of the supersede design (the record binds the new plan.json hash to the same run dir), not an accident.
impact: A PM or agent that deletes the state file by hand to get past the guard produces a run whose evidence dir describes a plan that is not the one the run started under, with no force/override event and no archived prior package. A later "does evidence match plan for R-xxx" audit reconstructs the wrong thing and reports green.
fix_sketch: In `cmd_init`, before the `fsm_init` append: if `timeline.jsonl` already contains an `fsm_init` event and `_sup_verified` is 0, refuse with the `plan-state --supersede-epic` instruction; and have `aid-epic-to-json.sh:944` `mv` any existing `plan.json` to `plan.json.superseded-<epoch>` before writing.
effort: S

---

## OBS-20260702-02
verdict: REAL (narrowed — the flat-vs-subdir half is gone, the sibling-file half is not)
evidence:
- `scripts/aid-auto-pipeline.sh:1940-1941` and `:2107-2108` — both generation loops compute `run_output_dir="$(aid_state_path ".aid-o/work/runs/${run_id}")"`, `mkdir -p`, and pass it as `--output-dir`. The flat `runs/<file>.md` top-level path the entry describes has no producer left; `aid-auto-pipeline.sh` is the only non-test caller of `aid-json-to-run.sh` (verified by grep over `scripts/`, `skills/`, `commands/`).
- `scripts/aid-json-to-run.sh:616-636` — `output_filename="${run_id}-${goal_slug}.md"`, written via mktemp + `mv` into `$output_dir`. There is no removal, archival or supersede-marking of pre-existing `*.md` in that directory.
what_is_true: The exact WAN symptom (one run.md under `runs/R-xxx/`, another flat at `runs/`) cannot recur: the canonical location is pinned to `runs/<run_id>/`. But the filename still embeds the goal slug, and a re-scope changes the goal — so regeneration under the same run_id writes `R-xxx-<new-slug>.md` beside the old `R-xxx-<old-slug>.md`, with no supersede marker. Same duality, one directory level down.
impact: An agent or PM resolving "the run file for R-xxx" with a glob still gets two candidates after any descope/regeneration, and the stale broader-scope file is usually the longer, more authoritative-looking one.
fix_sketch: In `aid-json-to-run.sh` immediately before the `mv` at `:632`, archive any existing `${output_dir}/${run_id}-*.md` that is not `$output_path` to `*.superseded-<epoch>` (mirroring the state-file convention).
effort: S

---

## OBS-20260702-04
verdict: REAL for the main claim; the "artifact contradicts itself" sub-claim is WRONG_ADDRESS
evidence:
- `skills/pipeline.md:2173-2210` — the full `DONE REVIEW` PM Summary template: steps, gates, auditor score, C3 independence, curator, auto-fixes, blocking findings, key outputs, options. No delivery-gate line.
- `skills/pipeline.md:1388` and `:1823` / `commands/aid-run.md:427` — `final_report.md` is specified only as "Generate `final_report.md`", gated on "file present in evidence dir". `ls defaults/templates/` contains no final-report template, and no script writes or validates its content (`aid-epic-summary.sh:60-64` only greps its first heading).
- `scripts/aid-pm-brief.sh` — `grep -n delivery` returns nothing; the machine PM brief carries no delivery-gate field either.
- `scripts/aid-delivery-gate.sh:197-210` — the two freshness fields are documented as deliberately different axes: `revision.freshness` = protocol-level "is this artifact current right now" (always `current` at creation), `delivery_gate.freshness` = "did commits land after the run started" (`stale` when `HEAD != BASE_SHA`). Not a contradiction — a documented distinction.
- Partial mitigation since: `scripts/aid-release-policy.sh:51,194` lists `delivery_gate` among the REQUIRED release inputs (missing → blocked), so the artifact's *presence* now reaches a blocking surface at C4. Its `delivery_ready` verdict still does not.
what_is_true: The PM-facing surfaces (final_report.md, the PM Summary template, the PM brief) still say nothing about D0. A run whose `delivery-gate.json` says `delivery_ready: false` with 15 `unverifiable_profile` findings reads as all-green to the PM, and a project with no delivery profile gets no nudge to configure one. The freshness half of the entry is a misreading of a documented design.
impact: PM merges on an all-green report while the delivery-readiness artifact on disk says otherwise; projects with no delivery profile stay unverifiable indefinitely because nothing surfaces it.
fix_sketch: Add one mandatory line to the PM Summary template in `skills/pipeline.md:2173` and to the final-report step at `:1823` — `Delivery gate (D0): {status} | delivery_ready={bool} | {n} findings{, profile unverifiable → configure defaults/policies/delivery-gate.yaml}` — read from `delivery-gate.json`.
effort: S

---

## OBS-20260702-07
verdict: REAL (narrowed — generation is now transactional; the cleanup path the entry asks for still does not exist, and the pointer offered instead is wrong)
evidence:
- `scripts/aid-auto-pipeline.sh:2093-2099` and `:2153-2155` — generation now writes a manifest (`<generation_dir>/generated-epics.json`) and a receipt via `aid-generation-finalize.sh`; per-phase EPICs wait for a "complete-package receipt" (`:1933`) before run/queue creation.
- `scripts/aid-auto-pipeline.sh:448-461, 740-782` — P074 `supersede-generation` is the audited recovery: it archives the transaction + authority pair with a ≥20-char reason and three fail-closed audit records. Its own header states `"It DELETES NOTHING"` (`:454`) and `:779` prints *"Cleanup of already-created EPIC files, branches and queue entries is NOT done here: use 'aid-plan-fsm.sh plan-rollback' and the queue-removal path for that."*
- `scripts/aid-plan-fsm.sh:10102-10120` — `cmd_plan_rollback` is the post-merge terminal state `ROLLED_BACK`: it records and git-verifies four SHAs (candidate, target head, merge, revert) and requires the merge to still be reachable. It removes no EPIC files, no evidence dirs, no branches, no queue entries. The pointer at `aid-auto-pipeline.sh:779` names a command that does not do what it is offered for.
- `scripts/aid-fsm.sh:4586-4647` — the duplicate-init guard still stands in front of any re-generation, releasable only via `plan-state --supersede-epic` (which itself requires a live `fsm-state.yaml` — `aid-plan-fsm.sh:8408-8412` fails with "no fsm-state.yaml found ... nothing to supersede"). The E-057-2 shape from the entry (evidence dir WITHOUT fsm-state.yaml) therefore still has no supported recovery command.
what_is_true: The crash-mid-generation window is much smaller — a two-phase receipt plus a manifest means a partial generation is now detectable and can be explicitly, audibly retired. What is still missing is exactly the entry's ask: a manifest-driven, whitelist-only cleanup that removes the artifacts a partial generation created. The operator is still between the init guard and the permission layer, and the one hint the tool prints points at `plan-rollback`, which is a merge-revert bookkeeping command.
impact: After a crashed generation the operator is told to run a command that cannot help, so the practical route stays hand-deleting files — which is the root cause of OBS-20260702-01. A half-generated phase whose state file never got written cannot even be superseded.
fix_sketch: Give `supersede-generation` a `--cleanup` mode that deletes only paths enumerated in `generated-epics.json` (epic file, run dir, evidence dir, queue entry, task branch) and, at minimum, correct the pointer text at `aid-auto-pipeline.sh:779`.
effort: M

---

## OBS-20260705-02
verdict: REAL
evidence:
- `scripts/aid-fsm.sh:6090-6119` — the complete `cmd_set_field`: reserved-field rejection for `state`/`done_phase`, then an awk in-place rewrite (or an append when the key is absent) and `mv`. There is no `log_event`, no `fsm_emit_audit_log`, no timeline path derived anywhere in the function.
- `grep -n 'fsm_field_change' scripts/aid-fsm.sh` — zero hits; the event proposed by the entry was never implemented.
- `commands/aid-run.md:167` still states the contract ("all mutations go through `aid-fsm.sh` commands (`transition`, `increment-step`, `set-field`)") — instruction-only, nothing enforces it and nothing records it.
what_is_true: The v2.51.0 hardening the entry mentions (slash/backslash-safe writes via awk + ENVIRON) is visible at `:6100-6116`, but the eventing half was never done. Every `set-field` write — `pm_decision`, `escalation_decision`, `c3_recheck_count`, `plan_path`, `base_commit` — mutates `fsm-state.yaml` with no trace in `timeline.jsonl`.
impact: The timeline cannot be reconciled against the state file, so the OBS-01 class of silent state surgery stays invisible to any audit; a `pm_decision: merge` set by hand is indistinguishable from one the PM gave.
fix_sketch: In `cmd_set_field`, capture the old value before the rewrite, then `derive_timeline "$state_file"` and `log_event ... "fsm_field_change" field= old= new=` (optional `--reason` passthrough) — the helpers are already in the same file.
effort: S

---

## OBS-20260705-03
verdict: REAL (narrowed to `legacy_epic_release_mode`; `plan_branch` plans got structural coverage)
evidence:
- `skills/pipeline.md:1554-1557` — `plan-finalize --stage review` writes `review-requirements.json` containing "the review range `plan_base_commit..candidate_sha`", and `:1512-1520` states every plan-level review runs once against the frozen candidate, validated against `candidate_sha`. Under `plan_branch`, ad-hoc commits merged into the plan branch fall INSIDE that range, so the "below every EPIC's base_commit ⇒ never reviewed by construction" argument no longer holds there.
- `scripts/aid-plan-close-check.sh` — `grep -in 'coverage|uncovered|orphan|task/'` returns nothing; the five plan-close checks are stale reports, head freshness, queue/active.md staleness and fsm-state consistency. No commit-range coverage computation.
- `grep -rn 'uncovered_commits|review_coverage' scripts/ skills/` — zero hits repo-wide. The entry's proposed C4 coverage computation and the "warn when a `task/*` branch has no matching run evidence" check are both absent.
- `skills/pipeline.md:1378-1383` — `legacy_epic_release_mode` remains a live mode in which steps 3-9 are per-EPIC and there is no plan-final whole-range review.
what_is_true: The specific WAN topology is now largely covered for plan-branch plans, because the plan-final boundary reviews `plan_base_commit..candidate_sha` rather than a union of per-EPIC ranges. What is genuinely still missing everywhere is the *signal*: nothing computes which commits in a merge range were inside some verified run, and nothing flags an AID-named `task/*` branch that has no run evidence. In legacy mode the original gap is intact.
impact: In `legacy_epic_release_mode`, ad-hoc commits on an AID-looking `task/*` branch reach main with zero checkpoint coverage and no marker distinguishing them from verified EPIC work; in both modes a plan-close reviewer has no list of uncovered commits to acknowledge.
fix_sketch: In `aid-plan-close-check.sh`, add a check that diffs `git rev-list <plan_base>..<head>` against the union of the manifest's `epic_runs[].epic_base_commit..epic_merge_commit` ranges and prints the uncovered SHAs as an explicit acknowledge-me list.
effort: M

---

## OBS-20260706-01
verdict: REAL — and worse than the entry describes: the path split is now inside the shipped code, not just across runs
evidence:
- `scripts/aid-run-gates.sh:1628-1629` — the writer's default: `report_path="${report_file:-}"; [[ -z "$report_path" ]] && report_path="${_evidence_dir}/gates/gates_report.json"`. Canonical path = `gates/` subdir.
- Readers agreeing with it: `scripts/aid-fsm.sh:2453, 2880, 2991, 3286, 5262`, plus `scripts/aid-diagnostic.sh:57` and `scripts/aid-compliance-backfill.sh:103` — all `${...}/gates/gates_report.json`.
- Documentation agreeing with it: `commands/aid-run.md:211`, `skills/pipeline.md:1115, 1135` all pass `--report-file <evidence_dir>/gates/gates_report.json`.
- The outlier: `scripts/aid-fsm.sh:1825` — `local gates="${evidence_dir}/gates_report.json"` inside `fsm_check_streamlined_integration_review` (function at `:1817-1845`), a FLAT path with no fallback. It is a live hard block, called at `scripts/aid-fsm.sh:6608` from `cmd_done_advance` (review→release) whenever `streamlined_mode: true`, and its failure message at `:1834-1836` names the evidence dir itself.
what_is_true: The two-path problem the entry saw across runs is now baked into one file. Gates always write to `<evidence>/gates/gates_report.json`; the streamlined integration-review precondition looks for `<evidence>/gates_report.json`. A streamlined run that did everything right therefore fails `done-advance review release` with "missing required integration-review evidence: gates_report.json" and is pushed toward the audited `--force --blocked-checks streamlined_integration_review` override — a false blocker that trains people to force.
impact: Every streamlined-mode EPIC hits a spurious hard block at review→release, and the sanctioned way past it is a force waiver that lands in the C4 waiver aggregate as if a real check had been bypassed.
fix_sketch: At `scripts/aid-fsm.sh:1825`, read `${evidence_dir}/gates/gates_report.json` (optionally accepting the flat path as a legacy fallback), and add a bats case covering a streamlined run whose report sits at the canonical path.
effort: S
