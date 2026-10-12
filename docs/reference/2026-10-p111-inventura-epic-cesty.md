# Inventura kontrol EPIC cesty (P111, krok 6)

Datum: 11. 10. 2026, AID 2.117.0 (větev `feat/p111-bez-epicu`). Zdroj: řádky registru
`plugins/aid-orchestrator/defaults/enforcement-registry.yaml`, jejichž `id` jmenuje EPIC cestu
(`epic`, `generation`, `queue`, `plan_to_epic`, `json_to_run`). Zadání čekalo 50 řádků (stav
po 2.116.1); změřeno po doplnění řádků přímé cesty: **52** — dva nové řádky P111
(`plan_run_excludes_generation`, `epic_complete_direct`) mají ve jménu `generation`/`epic`.

Verdikty (tři pevná slova, P112 je počítá):

- `přechází → replacement_guard: <id>` — co řádek hlídá, hlídá na přímé cestě jiný řádek; P112
  zkopíruje id do pole `replacement_guard` řádku, který vyřadí.
- `zaniká v P112 (důvod)` — mechanismus patří jen EPIC cestě (generátory, fronta, task větve,
  merge EPICu) a s ní zmizí.
- `zůstává` — mechanismus na EPIC souborech nezávisí (sdílená pečeť a zámek, kola revize běhu)
  nebo je řádek už vyřazený a zůstává jako záznam.

Souhrn: přechází 16, zaniká v P112 24, zůstává 12.

Nic se v P111 nemaže (PM 2B, 11. 10. 2026); P112 maže podle této tabulky.

| id | co vynucuje (stav v registru) | verdikt | proč |
|---|---|---|---|
| epic_specialist_review_exception | RETIRED by P096 Step 12: no specialist is left to dispatch mid-plan; the EPIC owes its cp3 round. (removed_scoped) | zůstává | řádek už vyřazený P096 (removed_scoped) — zůstává jako záznam |
| json_to_run_base_commit | Step-18 empty HEAD SHA → error_exit (companion to detached-HEAD) (active) | přechází → replacement_guard: plan_run_direct | základ přímého běhu je tip `plan/<id>` zapsaný do manifestu; `init --direct` ho ověří |
| init_cross_epic_branch | cmd_init cross-EPIC branch mismatch → die (AID-001) (active) | přechází → replacement_guard: direct_commit_branch | přímý běh nemá task větev; jeho větev je `plan/<id>` vázaná na stav běhu |
| json_to_run_detached_head | detached HEAD → hard fail (unanchorable base_commit) (active) | přechází → replacement_guard: plan_run_direct | `init --direct` vyžaduje HEAD = `plan/<id>` (`direct_run_needs_plan_branch`) |
| generation_receipt_before_init | strict/high-risk plan FSM init requires a hash-bound complete-package receipt; --force cannot substitute it (active) | přechází → replacement_guard: plan_run_transaction | stupeň účtenky `plan-run` před `init`: graf, bajty plánu a otisk `plan.json` |
| generation_phase_evidence_retained | per-EPIC contract validation evidence is retained and bound into the generation receipt; later phases cannot overwrite it (active) | přechází → replacement_guard: plan_run_transaction | D5 výsledek přímého běhu leží v `generation/c0/` a stupeň se zapíše do transakce |
| epic_to_json_io_guards | I/O write guards (evidence/plan.json/state.yaml/EPIC copy) (active) | přechází → replacement_guard: plan_json_shared_builder | atomický zápis `plan.json` je v knihovně stavitele |
| epic_id_extraction | EPIC-ID extraction failure → error_exit (active) | zaniká v P112 (id se nečte z jména EPIC souboru; `aid_gen_epic_id` ho odvodí) | — |
| epic_template_found | EPIC template not found → error_exit (Run /aid-init) (active) | zaniká v P112 (bez EPIC souboru není šablona EPICu) | — |
| json_to_run_writable | output-dir writability gate (exit 3) (active) | zaniká v P112 (přímý běh nevykresluje run.md) | — |
| json_to_run_zero_steps | plan.json zero steps → error_exit (active) | přechází → replacement_guard: plan_json_shared_builder | stavitel odmítne plán bez kroků (exit 2) |
| json_to_run_atomic_write | atomic temp+mv write, cleanup on failure (3 guards) (active) | zaniká v P112 (run.md se nepíše) | — |
| json_to_run_filename_cap | output filename >200 chars truncated (active) | zaniká v P112 (run.md se nepíše) | — |
| epic_review_semantic_final | P094 Step 7: every cp3 close writes <run>/semantic-review-final.json — the union of the cp3 rounds' merged.json by fingerprint mapped to … (active) | zůstává | CP3 kola běhu nejsou vázaná na EPIC soubor; platí i pro přímý běh, když projekt CP3 drží |
| epic_to_json_schema | Step-14 structural jq validation; constraints not surfaced to plan author (active) | přechází → replacement_guard: plan_json_shared_builder | strukturní kontrola `plan.json` je v knihovně stavitele |
| queue_epic_id_format | epic-id E- format not instructed in any skill (active) | zaniká v P112 (bez fronty) | — |
| json_to_run_json_valid | plan.json must be valid JSON (jq empty) (active) | přechází → replacement_guard: plan_run_transaction | stupeň účtenky čte `plan.json` přes jq a porovná otisk |
| epic_sub_validators | dangling dep edges, parallel minItems:2, analysis_groups, gate enum (active) | přechází → replacement_guard: plan_json_shared_builder | závislosti, vlny, analýzy a jména bran kontroluje stavitel |
| epic_compliance_coverage_ratio | registered advisory check with NO evaluator code anywhere (dead) | zaniká v P112 (mrtvý řádek bez vyhodnocení) | — |
| epic_template_contract | EPIC scope (allowed/forbidden paths) + DoD gates block (active) | zaniká v P112 (rozsah kroku čte kontrakt z `plan.json`, ne z bloku EPICu) | — |
| queue_dep_revalidation | at EPIC start (queue pickup) each depends_on dependency is re-checked via git merge-base --is-ancestor; a queue that cannot be parsed (qu… (active) | zaniká v P112 (bez fronty; pořadí kroků drží jeden běh) | — |
| plan_queue_append_locked | APPEND half — wired: aid-queue-add.sh delegates its only write to lib/aid-queue-write.sh:queue_append_entry, so the append and every late… (active) | zaniká v P112 (bez fronty) | — |
| plan_queue_entry_block_structure | APPEND-DOOR INTEGRITY — wired: runs on every aid-queue-add.sh invocation. The locking row above covers HOW the append is written; this ro… (active) | zaniká v P112 (bez fronty) | — |
| plan_queue_scripted_transitions | TRANSITION half — BUILT AND TESTED, NOT YET WIRED. queue_set_status validates against the seven-value enum (exit 2, nothing written, for … (planned) | zaniká v P112 (bez fronty; řádek planned) | — |
| epic_merge_ancestry_proof | _pfsm_is_ancestor (git merge-base --is-ancestor) is the ONE primitive epic-merge-to-plan accepts as proof that an EPIC's work is containe… (active) | přechází → replacement_guard: epic_complete_direct | přímý běh se nemerguje; `merged_to_plan` se zapíše na tipu `plan/<id>` |
| epic_lineage_unproven_merge_gate | epic-merge-to-plan refuses (exit 1, epic_lineage_unproven) to record a merge for a manifest entry whose lineage is not `proven` — minting… (active) | přechází → replacement_guard: epic_complete_direct | záznam přímého běhu je `proven` od `plan-run`; `init --direct` lineage ověří |
| epic_merge_in_progress_guard | _pfsm_check_no_merge_in_progress blocks epic-merge-to-plan when the repository is already mid-merge, testing MERGE_HEAD and any unmerged … (active) | zaniká v P112 (žádný merge EPICu se neprovádí) | — |
| gate_profile_epic_boundary_cap | RETIRED by P097 (Step 4 removed the cap, Step 9 the library). Was: In plan_branch mode both aid-fsm.sh call sites route gate_profile_reso… (removed_scoped) | zůstává | řádek už vyřazený P097 (removed_scoped) — zůstává jako záznam |
| epic_supersede_bound_reinit | P073 Step 13 — a PM-audited transaction that retires a stale EPIC FSM run and authorises exactly ONE re-initialisation. `aid-fsm.sh init`… (active) | zůstává | nové `init` téhož běhu po supersede se netýká EPIC souboru; platí i pro id přímého běhu |
| epic_start_clean_worktree_preflight | P074 Step 5 — epic-start's clean-worktree preflight is REMOVED: it creates the task branch as a ref only (`git branch` — no checkout, no … (removed_scoped) | zůstává | řádek už vyřazený P074 (removed_scoped) — zůstává jako záznam |
| generation_cp1_once_per_plan | P074 Step 13 (D26) — CP1 used to be consulted once PER PHASE, so a three-phase plan asked for the same approval three times and a rerun a… (active) | přechází → replacement_guard: plan_run_transaction | `plan-run` pečetí CP1 jednou ve stupni seal |
| generation_authority_verification | P074 Step 14 — the per-phase generator, when driven by the pipeline, replaces its own CP1 gate call with a VERIFICATION of the sealed aut… (active) | zaniká v P112 (ověřuje pečeť pro generátor po fázích; `plan-run` ji pečetí a váže ve stejné transakci — plan_run_transaction) | — |
| generation_transaction_identity | P074 Step 15 — an existing INCOMPLETE transaction whose recorded identity differs from this invocation's derives from DIFFERENT plan byte… (active) | přechází → replacement_guard: plan_run_transaction | `plan_changed_since_seal` odmítne plán změněný po pečeti |
| queue_add_transaction_owned_skip | P074 Step 15 — a resumed generation must neither duplicate a queue entry nor die on its own earlier one (the 2026-08-04 failure). An exis… (active) | zaniká v P112 (bez fronty) | — |
| generation_rollover_stale_queue_entries | P074 Step 15 — before a COMPLETE transaction rolls over for edited plan bytes, any queue entry carrying one of that transaction's EPIC id… (active) | zaniká v P112 (bez fronty a bez přechodu transakce) | — |
| generation_supersede_transaction | P074 Step 16 — the audited recovery for an incomplete transaction whose plan changed underneath it, kept as a SEPARATE deliberate invocat… (active) | přechází → replacement_guard: plan_run_transaction | obnova = archivace transakce `plan-run`, jak říká `plan_changed_since_seal` |
| generation_force_override_audit | P074 Step 13 — the override an operator actually needs is a PUBLIC, invocation-scoped flag with a mandatory >=20-character reason and the… (active) | zůstává | tělo pečeti `aid_gen_seal` sdílí `plan-run --force` |
| generation_force_audit_before_authority | P074 Step 13 — the ORDERING half of generation_force_override_audit, recorded separately because it is a distinct failure mode with its o… (active) | zůstává | tělo pečeti `aid_gen_seal` sdílí `plan-run --force` |
| generation_single_hold_lock | P074 Step 15 — the whole generation runs under ONE re-entrant hold of a per-plan lock, so two concurrent invocations for the same plan ca… (active) | zůstává | `aid_gen_lock` drží i `plan-run` |
| generation_transaction_vanished_mid_run | P074 Step 15 — the transaction manifest disappearing mid-run (superseded or removed underneath the process) aborts immediately and states… (active) | zůstává | `aid_gen_tx_update` zapisuje i stupně `plan-run` |
| generation_receipt_rewrite_binding | P074 Step 15 — the receipt's per-EPIC `queue_status` used to stay at the placeholder `pending_receipt` forever, because nothing rewrote i… (active) | zaniká v P112 (stav fronty v účtence; bez fronty) | — |
| generation_steps_table_arity | P074 Step 17 — a Steps-table row whose cell contained an escaped pipe was split into the wrong number of columns, and the converter PADDE… (active) | zaniká v P112 (parser tabulky kroků EPICu) | — |
| generation_failure_label_classification | P074 Step 18 — exactly TWO AID-owned failure labels, printed as line 1 of stderr, and one of them carries a copy-pasteable force command.… (active) | zůstává | štítky odmítnutí CP1 tiskne sdílená pečeť i pro `plan-run` |
| generation_not_an_aid_gate_note | P074 Step 18 — when a generation dies AFTER AID's own CP1 decision passed and the failure is not an AID-owned gate, one honest line is ap… (active) | zaniká v P112 (poznámka při ukončení pipeline) | — |
| generation_epic_start_registration | P075 — `epic-start` was a fully built, tested command with NO production caller: the plan-branch lifecycle was assembled across P064/P068… (active) | přechází → replacement_guard: plan_run_direct | záznam běhu v manifestu zapíše `plan-run` (direct, bez task větve) |
| json_to_run_branch_restore_before_failure | P075 — the branch restore after FSM init only ever ran when init SUCCEEDED. `aid-json-to-run.sh` runs under `set -euo pipefail`, so a ref… (active) | zaniká v P112 (přímý běh nepřepíná větve při init) | — |
| queue_peek_readonly | P090 Step 1 — before this, asking the queue what was next MEANT taking it: `queue_claim_next` selected and wrote `status=running` in the … (active) | zaniká v P112 (bez fronty) | — |
| queue_continuation_notice | P090 Step 5, a refusal since P099 Step 5 — the agent ended its turn in the middle of an autonomous run about ten times in P097. On `Stop`… (active) | zaniká v P112 (pokračování vybírá další EPIC z fronty; přímý plán má jeden běh) | — |
| generation_delivered_phase | P100 Step 5: a phase whose EPIC an earlier generation queued with a merge_target that git ancestry proves merged is recorded delivered an… (active) | zaniká v P112 (fáze a jejich dodání patří generaci) | — |
| plan_lint_epic_grammar | 2.107.0: the plan's EPIC lines are read by the same parser plan-start writes the lifecycle manifest with (lib/aid-lifecycle.sh aid_lifecy… (active) | zůstává | lint dál čte řádky EPIC striktních plánů; zda je P112 zruší, rozhodne P112 |
| plan_run_excludes_generation | P111 — the two roads never mix on one plan: plan-run refuses a plan with any generation trace (generation_already_started) and the pipeli… (active) | zaniká v P112 (bez generace není co vylučovat) | — |
| epic_complete_direct | P111 — done-advance review release --direct records the direct run merged_to_plan at the tip of plan/<id> and moves the plan to PLAN_SYNC… (active) | zůstává | zápis přímého běhu na konci (`done-advance --direct`) je mechanismus nové cesty |
