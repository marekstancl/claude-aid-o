---
id: P095
type: bug-fix
status: done
created: 2026-09-19
author: PM + AI
risk: high
lifecycle_strict: true
depends_on_plans: [P094]
---

# Plan: Review Cleanup — the adjudicator takes what reviewers write, Codex has an automatic stand-in, and the plan-final inputs stop lying

## Context

v2.99.0 (P094, released 2026-09-19) put the step review (CP2), the EPIC review (CP3) and the fast-mode review (CP6) on the one round engine that P093 built for the plan review (CP1). Five fresh diffs against the installed plugin the same afternoon (`docs/plans/P094-fresh-diffs.md`) measured it: the Sonnet `step_generalist` found and reproduced the planted defect in 4 of 4 reviewed diffs, and the mechanism reported the right verdict in 2 of 5, because `scripts/aid-review-adjudicate.sh` rejected 4 of the 5 real findings before anyone read them: three carried their reproduction inline as `bash -c '…'` (the schema's `command` pattern at `defaults/schemas/review-finding.schema.json:52` admits only `bash repro/<name>.sh`), one cited a line range `path:9-14` (the `evidence` pattern at line 56 admits one line). The acceptance run of P094 Step 13 had hit the same wall and the relaxation of commit 6cb9e288 was not enough. The adjudicator also prints `local: can only be used in a function` on every `collect` (`aid-review-adjudicate.sh:168`, a loop body outside a function).

The same day, three projects' `aid-plugin-issues.md` files (24 entries, collected 2026-09-19 with `bin/aid-plugin-issues-collect.sh --dry-run`, triaged in `docs/plans/P094-aftermath-and-next.md` §4) named eight defects that the rebuilds did not touch and that are verified in the code: `scripts/lib/aid-brainstorm-opponent.sh` returns 3 five times (lines 179-215) and never falls back when Codex is missing, old (`/usr/local/bin/codex` 0.149.1 shadows `/usr/bin/codex` 0.154.0) or over its usage limit (until 2026-09-21), and the review rounds record a Codex role as `provider_absent` (`scripts/aid-review-round.sh:332`) instead of asking another provider — the PM's instruction of 2026-09-19 (WAN) is that the stand-in is automatic and reported, never asked; `scripts/lib/aid-c3-dispatch.sh cmd_verify` (line 2689) detects that the written `audit-report.json` contradicts Codex's raw verdict (`_vfail` at 2830-2832), prints `verify: NOT verified` (2637) and still exits 0 with the false report on disk (ACTA P024, three findings, two HIGH, reported as none); `scripts/aid-evidence-verify.sh --at-head` run from a plan worktree looks for the evidence pack under that tree (`ROOT` from `AID_PROJECT_ROOT` at 170-171) where it never is, and run from the state root fails `git_clean` on untracked runtime directories and `artifact_head_freshness` because HEAD is `main`, not the candidate — so C4's `verification_report` input cannot pass under `plan_branch` at all (WAN P101, ACTA P024); the plan-level `acceptance-evidence.json` is aggregated by `aid-plan-fsm.sh` from EPIC files nobody writes (verdict `aggregated_with_gaps` at 10467 with `criteria: []`, WAN P101) while `scripts/aid-acceptance-evidence.sh reconstruct` (293 lines, 283) has no caller and reads `verifier-output-step-N.md` that P094 removed (IMP-612); `plan-finalize --stage gates` accepts a skipped `plan_diff` for a plan with no `verification_pattern` (5043) and `--stage inputs` refuses the same file (6577), out of `--force`'s reach (507); `aid-fsm.sh alloc plan-id` (8831) hands out a number a hand-written plan file already carries (WAN got P106 twice); `aid-fsm.sh set-field` (5980) moves `total_steps` and other transition preconditions with no timeline line and no reason; `/aid-run --auto` is documented as writing `auto-mode-state.yaml` (`skills/pipeline.md:2662-2668`) but no script writes it, so every later decision point reads "manual" (ACTA P024). Two P094 leftovers are stale data, not code: the enforcement-registry baseline of `scripts/tests/test-enforcement-registry-test-audit.sh` (fixture `enforcement-registry-baseline-pre-p066-e3.json`, 12 undeclared rows, IMP-607) and four fixtures from before P093 that fail on `main` (IMP-608: `test-roots-worktree.bats:277` and `:592`, `test-release-policy.bats:179`, `test-aid-fsm.bats:2181`), plus `fsm_check_review_round` reading its switches through `yq` without checking the tool exists (`aid-fsm.sh:1268-1275`, IMP-610) and the CP4 template still describing the removed pre-filter (`defaults/templates/verifier-output-template.md:41-42, 89`, IMP-611).

This plan is the first plan the P094 step review runs on for real; its cost and yield per step are the first live measurement the price table (`defaults/prices.yaml:24-31`, Sonnet blended rate marked "estimated") waits for.

## Goal

A reviewer's real finding reaches `merged.json` whether its reproduction is a file under `repro/` or an inline read-only command, and whether it cites one line or a range; the five fresh diffs re-run through the installed plugin give 1 pass, 3 fail, 1 skip; every place that asks Codex for a second opinion (brainstorm opponent, CP1 `generalist_b`, CP3 `epic_security`) gets an automatic Claude stand-in with the same brief when Codex is missing, outdated or rate-limited, recorded as such and reported to the PM without a question; the C3 bridge never leaves a report that contradicts the raw verdict; the at-head verification finds the pack and the candidate head under `plan_branch`; the plan-level acceptance evidence is produced from the gate that actually verified the criteria and says `prose_only` when none could be; the two plan-finalize stages read a skipped `plan_diff` the same way; the allocator, `set-field` and `--auto` leave the traces they claim; the four stale fixtures, the registry baseline, the yq precondition and the CP4 template are current; and the plugin is released as 2.100.0 with the testbed green and every project's issue file annotated.

## Scope

**In scope**
- Adjudicator and schema: `evidence` accepts `path:N-M` (anchored on N for the fingerprint); `command` accepts an inline `bash -c '<read-only>'` whose body uses only the closed verb list of the Data Model (`grep rg ls find sed git wc head tail cat cd mkdir mktemp touch printf echo export jq yq test [[ [ for do done if then else fi`), with no `source`, no nested `bash` and no `eval`, and no redirection to a file; the roles skills and the prompt template say so; `local` outside a function fixed; the five scratch diffs re-run and recorded.
- Codex stand-in: one shared function in `scripts/lib/aid-c3-dispatch.sh` decides Codex availability (binary by version, not first in PATH; a probe for the usage limit) and its callers fall back to a Claude dispatch of the same prompt — the brainstorm opponent through a `general-purpose` agent the controller dispatches on the script's instruction, and the review rounds through the existing controller adapter for the Codex role's prompt — with `provider: claude` and `fallback_reason` recorded and `collect` accepting it.
- C3 bridge `verify`: a raw/report mismatch exits non-zero and rewrites the report to `status: unverifiable` with the raw findings carried verbatim.
- `aid-evidence-verify.sh`: pack always from the state root, head from the pack's manifest when `--candidate <sha>` is given (C4 passes the candidate), no report written when no pack was found, `git_clean` over tracked files only, freshness and fingerprint only over protocol-v2 artifacts.
- Acceptance evidence: `aid-acceptance-evidence.sh` deleted with its paragraph in `agents/verifier.md`; the plan-level `acceptance-evidence.json` built from `plan-diff.json` per-AC results; `verdict: prose_only` when `plan_diff` was skipped for want of patterns; `--stage inputs` accepts that exactly when `--stage gates` accepted it; `--force` reaches the AC-lens assertion or says it does not.
- FSM traces: `alloc` skips ids taken by files; `set-field` logs field, old, new and requires `--reason` for `total_steps`, `current_step`, `plan_json_hash`, `base_commit`; `aid-fsm.sh auto-mode set|get` writes and reads `auto-mode-state.yaml` and `commands/aid-run.md` calls it first; `fsm_check_review_round` fails loudly without `yq`.
- Stale data: registry baseline regenerated with the P094 rows declared; the four fixtures reseeded; the other suites red on `main` and in the nightly of 2026-09-18 (`test-recovery-adjudicate`, streak 1, unknown) verified and fixed when they are fixtures, recorded as backlog rows when they are not; CP4 template header.
- Records: registry rows and breaking tests for every new refusal, successor rows for the deleted script, CHANGELOG 2.100.0 in both files, version registry, release, plugin refresh, testbed, `bin/aid-plugin-issues-collect.sh` run and every taken entry annotated in its project file with `HOTOVO 2.100.0` / `ZAMÍTNUTO`.
- Hygiene rule B (PM 2026-09-18): every modified file leaves with English identifiers and comments and no dead code; a reuse check against `scripts/lib/` for every new file.

**Out of scope**
- `<plan>-delivery.md` producer and its `Head` rule (ACTA 18), `plan_branch` plans whose steps need `main` (ACTA 2026-09-02), the pre-push `chore(release):` label (WAN 2026-09-03), a brainstorm that ends without a plan (WAN 2026-09-04) — recorded as low priority in `docs/plans/P094-aftermath-and-next.md` §4.
- The plan-final boundary's own logic beyond the two inputs named above (verification report, acceptance evidence).
- Changing the reviewer models or the round counts; the measured Sonnet rate is written into `prices.yaml` from this plan's own rounds, nothing else in the table moves.
- Docusaurus documentation.
- Any change inside ACTA, WAN or Agents beyond the annotation lines in their `aid-plugin-issues.md`.

## Standards

| Standard | Why it binds | Deviation |
|---|---|---|
| `/ecosystem/specs/test-standard` | every new or moved case carries a tier from a measurement (`aid-test-tier-assign.sh`); Steps 1, 3, 4, 5, 6, 7, 8 | none |
| `/ecosystem/specs/ci-versioning-standard` | Step 10 releases 2.100.0, edits both CHANGELOGs and the eight version locations | none |
| `/ecosystem/specs/documentation-placement` | agent-facing text in `commands/` and `skills/`; records in `docs/plans/` committed with `git add -f`; Steps 2, 3, 9, 10 | none |
| `/ecosystem/specs/artifact-standard` | the PM page of this plan and the plan-final card | none |
| `/ecosystem/specs/llm-test-cost-control` | Step 2 replays five diffs through a paid model, manual, ceiling written first | none |
| `/ecosystem/specs/backlog-standard` | Step 8 writes `IMP-` rows for suites that are red for a reason other than a stale fixture | none |
| `/ecosystem/specs/claude-md-standard` | no `CLAUDE.md` changes; listed because the map binds it | none |
| `/ecosystem/specs/agent-hooks` | Step 3 edits `scripts/aid-hook-verify.sh` (the hook layer's provider detection) and Step 4 the C3 verify hook call in `aid-fsm.sh`; the hooks' verdict shapes and exit codes are unchanged | none |

## Resources Verification

Checked in the repository at `main` 18ef5720 on 2026-09-19 (line numbers from `grep -n`):

- [x] Adjudicator and schema: `_evidence_item_ok` (scripts/aid-review-adjudicate.sh:84), `_evidence_first_ok` (:123), `_command_ok` (:133), the top-level `local first=""` (:168), `proof_error` jq reading both patterns from the schema (scripts/lib/aid-plan-review-packet.sh:170-177), `command` pattern (defaults/schemas/review-finding.schema.json:52), `evidence` pattern (:56), the evidence-rule prose (skills/step-review-roles.md:50-64, skills/plan-review-roles.md:52 and :215, defaults/prompts/review-prompt-v1.md:20-27 and :56), `fingerprint` five arguments (scripts/lib/aid-finding-fingerprint.sh:8).
- [x] Rounds: `dispatch` codex branch (scripts/aid-review-round.sh:322-345; `codex_absent` at 332), `collect` provider_absent rule (:376-392, :431), `close` degraded flag (:598), controller adapter `scripts/lib/aid-review-adapter-claude.md` quoted in `commands/aid-plan.md` and `commands/aid-run.md` between `<!-- adapter:begin -->`/`<!-- adapter:end -->`; reviewer blocks `defaults/policies/review-checkpoints.yaml` (`plan_review.reviewers` generalist_b codex gpt-5.6-terra; `epic_review.reviewers` epic_security codex).
- [x] Codex: `_run_codex_isolated` calls `codex exec --json` (scripts/lib/aid-c3-dispatch.sh:1117); `/usr/bin/codex` → codex-cli 0.154.0, `/usr/local/bin/codex` → 0.149.1 (both symlinks into node_modules, checked with `--version`); usage limit until 2026-09-21 08:29 (WAN report). Opponent: scripts/lib/aid-brainstorm-opponent.sh return-3 sites :179, :188, :191, :206, :215, dispute record :220 (`provider: "codex"`).
- [x] C3 bridge: `cmd_verify` (scripts/lib/aid-c3-dispatch.sh:2689), `_vfail` message (:2637), status/review_status assertions (:2830-2832).
- [x] Evidence verify: usage (scripts/aid-evidence-verify.sh:4), `ROOT` from `AID_PROJECT_ROOT` (:170-171), `run_git_clean_check` (:203), `no evidence packs found` (:263-264), the no-pack/no-out branch (:889-891); the state-root resolver `aid_state_root` (scripts/lib/aid-roots.sh:140; the verifier does not source that file today); its suites `scripts/tests/test-evidence-verify.sh` (t2, red in the nightly of 2026-09-18, `known: true`) and `scripts/tests/bats/test-evidence-verify-tree.bats` (t0); caller `run_verification_input` (scripts/aid-release-policy.sh:582-647, `add_input verification_report` :936, blocker :938); plan-finalize re-executes the stage inside the plan worktree with `AID_PROJECT_ROOT` set (WAN report; `NOTE: … re-running this command in .aid-worktrees/plan-P101`).
- [x] Acceptance evidence: `scripts/aid-acceptance-evidence.sh` (293 lines, `reconstruct` :283; no runtime caller, two test callers `scripts/tests/test-semantic-review.sh:68` and `:205` (cases T3 and T10), one comment `scripts/lib/aid-plan-manifest.sh:304`, the paragraph agents/verifier.md:200-219, registry rows at defaults/enforcement-registry.yaml:836 and :859, and historical CHANGELOG entries that stay), plan-level aggregation in scripts/aid-plan-fsm.sh (:10252 comment, `aggregated_with_gaps` :10467, `INPUTS PRODUCED` :10505), required input scripts/aid-release-policy.sh:807, manifest row :5179, expected file list :5996, `plan-diff.json` producer scripts/aid-plan-diff.sh (`results[]`, `overall_verdict` skipped at :67-69 and :283-285, per-AC skipped :248), the `gates` acceptance note scripts/aid-plan-fsm.sh:5043, the `inputs` assertion :6561-6577, the force message :507.
- [x] FSM: `cmd_alloc` (scripts/aid-fsm.sh:8831, `local next` :8908), `cmd_set_field` (:5980), `derive_timeline` (:249), `fsm_emit_audit_log` (:2062), `fsm_check_review_round` switch loop (:1266-1276), dispatcher case list (:8952-8998); auto mode: `aid_autonomous_mode()` the one reader (scripts/lib/aid-permissions.sh:34), the env signal `AID_AUTO_MODE` (scripts/aid-fsm.sh:372, :3504), a consumer (scripts/aid-release-policy.sh:79), `auto-mode-state.yaml` named in skills/pipeline.md:1274 and :2662-2668, commands/aid-run.md:46-66 and hand-written by commands/aid-stop.md:43-80 (no script writes it: `grep -rn auto-mode-state scripts/` → only the lint comment at scripts/aid-lint-skill.sh:75); plan-final predicate `_pfsm_plan_has_patterns` (scripts/aid-plan-fsm.sh:4597); config known keys `_AID_RC_KNOWN_KEYS` (scripts/lib/aid-review-config.sh:41, checked at :80); the dispatch record's `codex --version` (scripts/lib/aid-c3-dispatch.sh:2428); the tier runner `scripts/tests/run-all-tests.sh --tier` (:117, pass string :644; CI at .github/workflows/ci.yml:80); the pre-push all-zero-SHA skip (defaults/hooks/pre-push:336).
- [x] Stale data: scripts/tests/test-enforcement-registry-test-audit.sh (`BASELINE_FIXTURE` :18, `DECLARED_AMENDMENTS` :127), fixture scripts/tests/fixtures/enforcement-registry-baseline-pre-p066-e3.json; failing cases test-roots-worktree.bats:277 and :592, test-release-policy.bats:179, test-aid-fsm.bats:2181; also red on main (to verify in Step 8): test-generation-labels 3/7/11/12, test-standards-map.bats:169, test-control-enforcement.bats:40, test-plan-continue.bats:88; nightly 2026-09-18 `test-recovery-adjudicate` streak 1 not in `known`.
- [x] Template: defaults/templates/verifier-output-template.md:41-42 and :88-90 (fixed on the scratch branch `scratch/p094-fresh-diffs` commit 952cee49, to be cherry-picked).
- [x] Records: `docs/plans/P094-fresh-diffs.md`, `docs/plans/P094-aftermath-and-next.md`, scratch branch `scratch/p094-fresh-diffs` (five commits 346a8a36, e8814f7f, 224f60b4, 22ded9fb, 952cee49), evidence `.aid-o/work/evidence/do/20260919T14*/cp6/`; `bin/aid-plugin-issues-collect.sh`; testbed `/opt/eco/projects/aid-testbed/bin/verify.sh` (working tree has two uncommitted fixes; its `.git/objects/{13,0c,ee}` are owned by `agent-runner`, so the commit waits for the PM's `chown`).
- [x] Environment: `AID_PLUGIN_PATH`, `AID_PROJECT_ROOT`, `CODEX_MODEL`. Commands: `yq`, `jq`, `git`, `sha256sum`, `bats`; `codex` optional.
- [x] Registry: `defaults/enforcement-registry.yaml` (`totals:` at :50, 514 rows after P094); successor table `reference/review-successors.md` with `scripts/tests/test-review-successors.sh`.

## Approach

Chosen: **take what the reviewer writes, then remove every silent path, then refresh the data, then release.** Steps 1-2 fix the adjudicator and prove it on the five diffs; Steps 3-7 close the eight silent failures the projects reported, each with a refusal test; Step 8 refreshes fixtures and the baseline; Steps 9-10 record, release and annotate.

Alternatives considered and rejected:
- *Tell the reviewer harder to write `repro/<x>.sh` and single lines*: Sonnet wrote `bash -c` in three of four rounds with the rule in its prompt; a schema that takes what a careful reviewer naturally writes is cheaper than another sentence in bold. The inline form is bounded (read-only verbs only), so the safety the file form gave is kept.
- *A Claude stand-in only for the brainstorm opponent*: the PM's instruction names every second opinion; a round that records `provider_absent` for `epic_security` reviews nothing for security until 2026-09-21.
- *Keep `aid-acceptance-evidence.sh` and repoint it to `merged.json`*: the step review does not judge acceptance criteria; the `plan_diff` gate does, per AC, with a verdict and evidence. The producer that already verifies is the producer.
- *Make the aggregation fail on zero criteria*: blocks every plan with prose criteria at plan-final; `prose_only` says what happened and the `inputs` stage stops contradicting `gates`.
- *Fix `git_clean` by ignoring the untracked runtime directories by name*: a list rots; tracked-only is the invariant C4 needs ("nothing the candidate would carry differs").

## Architecture

Every change below is a refusal or a record added to a path that today passes silently; the engines and files stay where P093 and P094 put them.

```
reviewer-<role>.json ──► aid-review-adjudicate.sh
   command: grep|…|bash repro/x.sh|bash -c '<read-only pipeline>'   ← schema pattern + _command_ok body check
   evidence: path:N | path:N-M | <sha>:path:N | absent:path           ← schema pattern; fingerprint anchors on N
   loop body in a function (no top-level local)

codex second opinion ──► aid_codex_probe (lib/aid-c3-dispatch.sh): binary by version, `codex exec` dry probe
   available   → _run_codex_isolated as today
   unavailable → {answered:false, reason, fallback: claude} in codex-<role>.usage.json / opponent state
                 controller dispatches the SAME prompt to a general-purpose agent (adapter paragraph "stand-in")
                 answer carries provider: claude, fallback_reason; collect accepts it; PM card says so

aid-c3-dispatch.sh verify: raw ≠ report → report rewritten {status: unverifiable, raw_findings: […]}, exit 1

aid-evidence-verify.sh --at-head [--candidate <sha>]: pack under aid_state_root; head = candidate;
   no pack → no report, exit 1; git_clean = `git status --porcelain --untracked-files=no`;
   fingerprint/freshness only for files whose artifact_type is in the protocol registry

plan-finalize --stage inputs: acceptance-evidence.json ← plan-diff.json results[]
   {criteria:[{ac, verdict, evidence}], verdict: verified|partial|prose_only, source: plan-diff.json}
   AC-lens assertion: skipped + no verification_pattern → accepted (same rule as --stage gates)

aid-fsm.sh alloc: skip ids with a file; set-field: timeline field_set {field, old, new, reason};
   auto-mode set|get → .aid-o/work/auto-mode-state.yaml; fsm_check_review_round: no yq → PRECONDITION FAIL
```

## Data Model

**Finding `command` and `evidence`** (`defaults/schemas/review-finding.schema.json`): `command` pattern gains the alternative `bash -c '[^']*'` and `_command_ok` checks the quoted body segment by segment (split on `;`, `|`, `&&`, `||`) against a closed verb list derived from the four inline reproductions recorded on 2026-09-19: `grep rg ls find sed git wc head tail cat cd mkdir mktemp touch printf echo export jq yq test [[ [ for do done if then else fi` — no `source`, no nested `bash`, no `eval` (a verb whose purpose is to run something else is never read-only); `git` only with `grep|log|show|diff|blame|rev-parse|status`; any `>` or `>>` outside quotes, and `rm`, `mv`, `cp`, `curl`, `ssh`, `sudo`, `git push`, `git commit` refuse. The rejection reason is `command_not_read_only`. The existing `bash <path> --help` and `bash repro/<name>.sh` forms are unchanged. `evidence` pattern gains `:[0-9]+(-[0-9]+)?`; `_evidence_item_ok` resolves `path:N-M` when `N ≤ M` and the file has at least N lines; the fingerprint and the cross-round match use `path:N`.

**Codex probe** (`aid_codex_probe <out.json>` in `scripts/lib/aid-c3-dispatch.sh`): `{available: bool, binary: <path>, version: <x.y.z>, reason: none|codex_absent|codex_outdated|rate_limited|timeout|error, probed_at}`; the binary is the highest-version `codex` among `$PATH` entries; a `codex exec` of a one-token prompt with a 30 s timeout decides `rate_limited`/`timeout`. **Stand-in record**: `codex-<role>.usage.json` becomes `{answered: true, provider: "claude", fallback_reason: <reason>, model: <model>, tokens: <n|unknown>}` when the controller dispatched the stand-in; the reviewer file's `provider` is `claude` and `collect` accepts a Codex role with such a record; `measurement.json` prices the role at the stand-in model; the opponent's `dispute.json` gains `provider: "claude"`, `fallback_reason`.

**C3 verify report on mismatch**: `audit-report.json` rewritten as `{status: "unverifiable", reason: "raw/report mismatch: <the _vfail text>", raw: {review_status, blocking_findings, findings: […]}}`; exit 1.

**Acceptance evidence** (`<run>/acceptance-evidence.json`, plan level): `{identity: {plan_id, epic_id: null}, source: "plan-diff.json", verdict: verified|partial|prose_only, criteria: [{ac: "<AC text>", verdict: pass|fail|skipped, evidence: "<from plan-diff>"}], sources: [<contributing EPIC ids as today>]}`; `verified` when every criterion passed, `partial` when any failed or was skipped beside passing ones, `prose_only` when `plan-diff.json.overall_verdict == skipped`.

**Timeline event `field_set`**: `{ts, event: "field_set", field, old, new, reason}` in the run's `timeline.jsonl` (via `derive_timeline`).

**`auto-mode-state.yaml`**: `{mode: auto|manual, set_at, set_by: "aid-run --auto"|"aid-fsm auto-mode"}` under `.aid-o/work/`.

## Implementation Steps

**EPIC 1: Steps 1-10 — one EPIC, chained**

### Step 1: The adjudicator takes line ranges and inline read-only reproductions

**Objective:** A finding with `path:N-M` or `bash -c '<read-only>'` is accepted; a write in an inline command is refused with its own reason; the top-level `local` is gone; the rule text says what the schema does.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/schemas/review-finding.schema.json` (lines 52, 56) — `command` gains `bash -c '[^']*'`, `evidence` gains an optional `-M` range.
- Modify: `plugins/aid-orchestrator/scripts/aid-review-adjudicate.sh` (lines 84-140, 153-190) — `_evidence_item_ok` resolves a range; `_command_ok` checks an inline body word by word and returns the reason `command_not_read_only`; the per-role loop body moves into `_adjudicate_role`; the top-level `local` disappears.
- Modify: `plugins/aid-orchestrator/skills/step-review-roles.md` + `plugins/aid-orchestrator/skills/plan-review-roles.md` — the evidence rule (step roles lines 50-64 and 213; plan roles lines 52 and 215) names both forms.
- Modify: `plugins/aid-orchestrator/defaults/prompts/review-prompt-v1.md` (lines 20-27, 56) — same.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — row `review_adjudicator_evidence` gains the range and inline forms in `instruction`; new row `review_command_read_only` (blocking, test below).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-adjudicate.bats` — a range citation resolves and fingerprints on its first line; a range past the end of file is rejected `evidence_not_found`; each of the four inline commands recorded on 2026-09-19 (copied verbatim from `.aid-o/work/evidence/do/20260919T14*/cp6/round-1/reviewer-step_generalist.json` into the fixture) is accepted; `bash -c 'rm -rf x'`, `bash -c 'echo 1 > f'`, `bash -c 'source x.sh'` and `bash -c 'bash y.sh'` rejected `command_not_read_only`; `collect` on a fixture round has empty stderr (no `local:` line).

**Reuse check:** searched: `grep -n -e 'read-only' -e 'command_ok' plugins/aid-orchestrator/scripts/*.sh plugins/aid-orchestrator/scripts/lib/*.sh` → one match `plugins/aid-orchestrator/scripts/aid-review-adjudicate.sh:132-140` — extended, not duplicated; no other read-only command classifier exists in `scripts/lib/`.

**Parallel group:** ---

**Architecture Context:** The evidence rule stays strict on truth (a citation must resolve) and stops being strict on a form the reviewer never chose.

**Implementation Detail:** The inline body is split on `;`, `|`, `&&`, `||`; the first word of every segment must be in the verb list; `>` or `>>` anywhere outside quotes refuses. The schema pattern is what `proof_error` reads (`aid-plan-review-packet.sh:170-177`), so the jq stays untouched.

**Error Handling:** A `bash -c` whose body cannot be parsed (unbalanced quotes) is `command_not_read_only`.

**Edge Cases:**
- `path:14-9` (reversed range) → `evidence_not_found`.
- A range on a pre-image citation `<sha>:path:N-M` → resolved at the sha, anchored on N.
- Two findings differing only in the range end → same fingerprint → `duplicate`, as today for the same line.

**Dependencies:**
- Depends on: none
- Blocks: Step 2

**Acceptance Criteria:**
- [ ] The new cases in `test-review-adjudicate.bats` pass and the suite's case count grows by at least ten (two range cases, four accepted recorded commands, four refused commands).
- [ ] `bash scripts/aid-review-adjudicate.sh` run by `collect` on the fixture round writes nothing to stderr (the bats case asserts an empty stderr file), so the `local: can only be used in a function` line is gone.
- [ ] `grep -c 'bash -c' plugins/aid-orchestrator/skills/step-review-roles.md plugins/aid-orchestrator/skills/plan-review-roles.md plugins/aid-orchestrator/defaults/prompts/review-prompt-v1.md` is 1 per file, and the registry row `review_command_read_only` names the bats case.
- [ ] Review finding "Scope still describes the inline-command allowlist as containing `source`" is answered: the Scope bullet and the Data Model name the same closed verb list, and `grep -c '\`source\`' .aid-o/plans/P095-review-cleanup.md` finds `source` only in sentences that refuse it.

**Effort:** M
**AID Role:** backend

### Step 2: The five fresh diffs again, through the installed engine of this branch

**Objective:** The five scratch diffs of 2026-09-19 replayed through this branch's adjudicator with the recorded reviewer answers give 1 pass, 3 fail, 1 skip; the record says so.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/test-step-review-acceptance.sh` — mode `--mode replay-do <evidence root> <plugin dir>`: for every `evidence/do/<id>/cp6/round-1/` with a `reviewer-*.json`, copies the round into a temporary directory, runs this branch's `collect` and `close` with `--stub`, and prints `<id> verdict rejected open`.
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/step-review/fresh-diffs-2026-09-19.json` — the five reviewer answers of 2026-09-19 with their step-check verdicts (copied from `.aid-o/work/evidence/do/20260919T14*/cp6/`), and the expected verdicts.
- Test: `plugins/aid-orchestrator/scripts/tests/test-step-review-acceptance.sh` — `--mode replay-do` over the fixture gives the expected column (t2, it runs the adjudicator five times).
- Modify: `docs/plans/P094-fresh-diffs.md` — a second table with the replayed verdicts and the rejected count per diff (committed with `git add -f`).

**Reuse check:** searched: `grep -n -e '--mode' -e 'stub' plugins/aid-orchestrator/scripts/tests/test-step-review-acceptance.sh` → several matching — the `new` mode's stub replay (recorded answers through `collect`/`close --stub`) is the mechanism reused; the new mode differs only in reading answers from a `do/` evidence tree instead of `acceptance.json`.

**Parallel group:** ---

**Architecture Context:** The measurement of P094 Step 15 repeated with the one variable changed; no new reviewer run is paid.

**Implementation Detail:** The replay does not dispatch: the answers are the ones Sonnet wrote; only the adjudicator differs. A live re-run (five new Sonnet rounds, ceiling 4 USD) is done once after the replay and recorded beside it, because the prompt text changed in Step 1.

**Error Handling:** A round directory without `step-check.json` at the recorded head is skipped with a line.

**Edge Cases:**
- Diff 5 has no round (verdict `skip` from the step check): the replay prints `skip` from `step-check.json`.

**Dependencies:**
- Depends on: Step 1
- Blocks: Step 9

**Acceptance Criteria:**
- [ ] `test-step-review-acceptance.sh --mode replay-do` over the fixture prints `pass, fail, fail, fail, skip` in diff order.
- [ ] `docs/plans/P094-fresh-diffs.md` carries the replay table and the live re-run table with costs.

**Effort:** S
**AID Role:** backend

### Step 3: A Claude stand-in wherever Codex is asked for a second opinion

**Objective:** The brainstorm opponent, the CP1 role `generalist_b` and the CP3 role `epic_security` are answered by a Claude agent with the same brief when Codex is missing, outdated or over its limit; the record and the PM card say which provider answered and why; nothing asks the PM.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh` (lines ~1100-1130) — `aid_codex_probe <out.json>`: binary chosen by highest `--version` across `$PATH`, a 30 s one-token `codex exec` probe; `_run_codex_isolated` uses the chosen binary; the `codex_version` recorded in the dispatch record at line 2428 comes from the probe's chosen binary, so the record names what ran; the probe result is cached for 10 minutes in `.aid-o/work/codex-probe.json`, a runtime file created by the probe, never tracked; `AID_CODEX_PROBE_STUB=<file>` makes the probe read a canned result (for tests, never in production paths).
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-brainstorm-opponent.sh` (lines 170-225) — on probe failure it prints `STAND-IN: dispatch <prompt path> to a general-purpose agent (model opus) and pass its answer with --answer <file>` and exits 4; `--answer <file>` records `provider: "claude"`, `fallback_reason` in `dispute.json` and returns 0; the return-3 path stays only for a Codex that answered nothing after a successful probe.
- Modify: `plugins/aid-orchestrator/scripts/aid-review-round.sh` (lines 322-345, 360-410, 549-600) — `dispatch --provider codex` writes `{answered: false, reason, fallback: "claude"}` on probe failure and prints the stand-in instruction; `collect` accepts `reviewer-<role>.json` with `provider: claude` for a Codex role only when `codex-<role>.usage.json` carries `fallback: claude`, else `unexpected_provider`; a record with `fallback: claude` and no answer file is `missing` (the round is invalid, never `provider_absent`), so a stand-in nobody dispatched cannot close a round; `close` marks `degraded: false` only for a role whose record says the stand-in answered and prices it at `RC_STAND_IN_MODEL`; `retry` on a Codex role keeps `codex-<role>.usage.json` when it carries `fallback: claude` (re-running the probe, re-writing the record) instead of deleting it.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-config.sh` (lines 41, 80-95) — `stand_in_model` added to `_AID_RC_KNOWN_KEYS`, exported as `RC_STAND_IN_MODEL` (default `sonnet` for `step_review`/`epic_review`, `opus` for `plan_review`), validated against `banned_models`.
- Modify: `plugins/aid-orchestrator/scripts/aid-hook-verify.sh` + `plugins/aid-orchestrator/scripts/lib/aid-audit-independence.sh` — their `command -v codex` checks (hook verify lines 97 and 273, independence line 132) use the probe's binary choice; verdict shapes unchanged (one case each: the hook still names `codex` as the detected provider; the independence check still detects a same-provider pair). The e2e checks in `scripts/tests/e2e/c3-dogfood*.sh` are deliberately left on `command -v`.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-review-adapter-claude.md` — a "Stand-in for a Codex role" paragraph: dispatch the Codex role's prompt to a `general-purpose` agent with the model the checkpoint names for stand-ins, default `sonnet` for step and EPIC roles and `opus` for plan roles; open and close the dispatch bracket as for any Claude role; the PM card names the stand-in and the reason.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` + `plugins/aid-orchestrator/commands/aid-run.md` — the adapter re-quoted between the `adapter:begin`/`adapter:end` markers; in `aid-plan.md` the Steps 4-7 block describes the rc=4 stand-in path and rc=3 is no longer "present it as a decision".
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` — the opponent paragraph names the stand-in and the record it leaves.
- Modify: `plugins/aid-orchestrator/defaults/policies/review-checkpoints.yaml` — `stand_in_model: sonnet` under `step_review`/`epic_review`, `opus` under `plan_review`; `aid-review-config.sh` reads it (`RC_STAND_IN_MODEL`).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `codex_stand_in_recorded` (a Codex role answered by Claude carries the stand-in record or is `unexpected_provider`), `opponent_stand_in` (the opponent never stops on a missing Codex).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-round.bats` — with the probe stubbed to `codex_absent`, `dispatch` writes the fallback record and exits 0; `collect` accepts a `provider: claude` answer for `epic_security` with the record and rejects it without (`unexpected_provider`); a fallback record with no answer file makes the round invalid with the role listed as `missing`; `retry` on that role keeps the fallback record; `close` prices it at the stand-in model with `degraded: false`; the same for a CP1 round's `generalist_b` on a plan fixture.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-brainstorm-opponent.bats` — an existing t0 suite; every new case stays under 2 s by stubbing the probe through `AID_CODEX_PROBE_STUB`, no real `codex exec`; probe failure exits 4 with the stand-in line; `--answer` records `provider: claude`; a PATH with two stub `codex` scripts printing different versions picks the higher one.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-config.bats` — `stand_in_model` is read into `RC_STAND_IN_MODEL`, not reported as an unknown key on stderr, and refused when it names a banned model.

**Reuse check:** searched: `grep -rn -e 'command -v codex' -e 'codex --version' plugins/aid-orchestrator/scripts` → several matching (`aid-review-round.sh:331`, `aid-hook-verify.sh:97,273`, `lib/aid-audit-independence.sh:132`) — four independent `command -v codex` checks and no version or limit probe; the probe is founded once in `aid-c3-dispatch.sh` and the four callers use it.

**Parallel group:** ---

**Architecture Context:** The controller cannot be called from bash, so the stand-in is the same shape as every Claude reviewer: the script prepares and records, the controller dispatches, `collect` verifies the record. The PM sees a line, not a question (PM instruction 2026-09-19).

**Implementation Detail:** `aid_codex_probe` caches its result for 10 minutes in `.aid-o/work/codex-probe.json` so six roles do not probe six times. `aid-hook-verify.sh` and `lib/aid-audit-independence.sh` switch to the probe's binary choice without changing their verdict shape.

**Error Handling:** A probe that cannot run at all (no `timeout`, no writable cache) reports `error` and the stand-in path applies.

**Edge Cases:**
- Codex answers the probe but the real dispatch is rate-limited mid-run: `dispatch` records `rate_limited` with `fallback: claude` and prints the stand-in line; the controller dispatches the stand-in; the Codex events file is kept.
- A stand-in for `generalist_b` on a `type: docs` plan (two reviewers): the round's floor still counts it.
- The opponent's `--answer` file fails the dispute schema: exit 1, the record says `stand_in_invalid`, one retry allowed.

**Dependencies:**
- Depends on: Step 1
- Blocks: Step 9

**Acceptance Criteria:**
- [ ] With the probe reporting `codex_absent`, a CP3 round with `epic_security` and a CP1 round with `generalist_b` each close with `degraded: false`, `provider: claude` for that role and a priced measurement; the same round with the stand-in never dispatched is invalid with the role `missing`.
- [ ] `aid-brainstorm-opponent.sh` on such a host exits 4 with the `STAND-IN:` line and never 3; the new cases pass and `aid-test-tier-lint.sh` still accepts `test-brainstorm-opponent.bats` at t0.
- [ ] No line that RUNS `command -v codex` remains in `aid-review-round.sh`, `aid-hook-verify.sh` or `lib/aid-audit-independence.sh` (`grep -nE '^[^#"]*command -v codex' <file>` is empty for each; the trace message text at `aid-audit-independence.sh:135` may keep the words); the dispatch record's `codex_version` equals the probe's `version`.
- [ ] Both commands' adapter quotes are byte-identical to the library (existing `test-review-finding-schema.bats` case).

**Effort:** L
**AID Role:** backend

### Step 4: The C3 bridge never leaves a report that contradicts Codex

**Objective:** `aid-c3-dispatch.sh verify` on a raw/report mismatch exits 1 and rewrites the report to `unverifiable` with the raw findings carried, so no downstream reader sees "no findings".

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh` (lines 2637, 2689-2840) — two failure classes: precondition and usage failures (missing jq or sha256sum, `evidence_dir` not a directory, unknown flag; the `_vfail` sites before the raw comparison) keep their immediate non-zero exit with no write; only the raw-vs-report assertions at 2830-2832 become `_vmismatch`, which after the comparison rewrites `audit-report.json` with `status: unverifiable`, `reason`, `raw: {review_status, blocking_findings, findings}` from `codex-last-message.json`, keeps the original as `audit-report.rejected.json`, and returns 1; under `--reference` or `--read-only` (the FSM hook at `aid-fsm.sh:7451` passes it) the mismatch exits 1 with the reason and writes nothing; a report already `unverifiable` with the same reason, or an existing `audit-report.rejected.json`, exits 1 without touching either file.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (line ~7451) — the C3 verify hook passes `--read-only`.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — row `c3_verify_mismatch_unverifiable` (blocking; its test is t2, so it is proven nightly and once before the release in Step 8, and the row says so).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-c3-audit.bats` — an existing t2 suite; a fixture with raw `blocking_findings: true` and a report saying `false`: `verify` exits 1, the rewritten report has `status: unverifiable` and three `raw.findings`, the original is in `audit-report.rejected.json`; a second `verify` exits 1 and both files are byte-identical; the same fixture under `--reference` exits 1 and is byte-identical; a missing `jq` exits non-zero with no write; a consistent pair still exits 0 and is untouched.

**Reuse check:** searched: `grep -n '_vfail' plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh` → several matching — the assertion helper exists; only its consequence changes.

**Parallel group:** ---

**Architecture Context:** The release policy reads the report file (`aid-release-policy.sh:217`), never the raw message; the file is what must not lie.

**Implementation Detail:** The rewrite goes through a temp file and `mv`; the original report is kept as `audit-report.rejected.json` for the record.

**Error Handling:** A raw message that does not parse: `status: unverifiable`, `reason: raw_unreadable`, exit 1.

**Edge Cases:**
- `--stage review` after such a verify: it already treats `unverifiable` as a blocker (`aid-release-policy.sh:51`), so the plan stops where it should.

**Dependencies:**
- Depends on: none
- Blocks: Step 9

**Acceptance Criteria:**
- [ ] The five new `test-c3-audit.bats` cases pass and the suite is green when run alone (it is t2 and red in the nightly of 2026-09-18 with `known: true`; Step 8 runs it alone and records why it was red).
- [ ] `grep -n '_vmismatch' plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh` shows exactly the raw-vs-report assertion sites; every other `_vfail` site is unchanged.

**Effort:** S
**AID Role:** backend

### Step 5: At-head verification finds the pack and the candidate under plan_branch

**Objective:** `aid-evidence-verify.sh --at-head` looks for the pack under the state root, verifies against the candidate head C4 passes, writes nothing when there is no pack, counts only tracked changes as dirt and runs fingerprint and freshness only over protocol artifacts.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-evidence-verify.sh` (lines 4, 100-200, 203-230, 255-270, 880-895) — sources `scripts/lib/aid-roots.sh` (it does not today) and takes the evidence base from `aid_state_root` regardless of `AID_PROJECT_ROOT` or cwd; `--candidate <sha>` (default: `git rev-parse HEAD` of `--tree`); `run_git_clean_check` uses `git status --porcelain --untracked-files=no`; `artifact_head_freshness` compares against the candidate; the artifact loop skips files whose `artifact_type` is not in the protocol registry with a `skipped_non_protocol` list in the report; no pack → exit 1 and no file.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (lines 582-647, 714-736) — `run_verification_input` passes `--candidate "$CANDIDATE_SHA"` only when it is non-empty (plan mode; EPIC mode keeps the HEAD default), and maps "pack or candidate not reachable" to `unverifiable` with the reason, `fail` only to a real mismatch.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — row `evidence_verify_state_root` (the pack path never depends on the calling tree).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-evidence-verify-tree.bats` — an existing t0 suite ("which tree the verifier judges"); each new case builds a two-commit fixture repository and stays under 2 s; from a linked worktree with `AID_PROJECT_ROOT` set to it, the pack under the primary `.aid-o` is found; an untracked directory does not fail `git_clean`; a file with `artifact_type: dispatch_record` is listed as skipped, not failed; `--candidate` equal to the pack head passes freshness while HEAD is elsewhere; no pack → exit 1 and no report file.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats` — an EPIC-mode run passes no `--candidate` and its `verification_report` verdict is unchanged; a plan-mode run passes the candidate sha.

**Reuse check:** searched: `grep -n 'aid_state_root' plugins/aid-orchestrator/scripts/lib/aid-roots.sh plugins/aid-orchestrator/scripts/aid-evidence-verify.sh` → one match `plugins/aid-orchestrator/scripts/lib/aid-roots.sh:140`, none in the verifier — the resolver exists in `aid-roots.sh` and is adopted by sourcing that file.

**Parallel group:** ---

**Architecture Context:** The pack lives in the primary checkout, the candidate in the plan worktree; the verifier reads the first from the state root and takes the second as an argument, so the two trees are never assumed to be one.

**Implementation Detail:** `--candidate` defaults to `git rev-parse HEAD` of `--tree` so every existing caller behaves as before.

**Error Handling:** A `--candidate` not reachable from the tree's history: `artifact_head_freshness: unverifiable` with the sha named.

**Edge Cases:**
- `--tree` pointing at the primary checkout while a plan branch is checked out elsewhere: the pack is found; freshness uses the candidate.
- A plan-final run with `enforcement: blocking` on `verification_report`: now closable.
- A pack whose manifest head is not an ancestor of the candidate (a rebased plan branch): `artifact_head_freshness: fail` with both shas, as a real mismatch should.

**Dependencies:**
- Depends on: none
- Blocks: Step 6

**Acceptance Criteria:**
- [ ] The five new `test-evidence-verify-tree.bats` cases pass under the t0 budget, and the t2 harness `test-evidence-verify.sh` (red in the nightly of 2026-09-18 with `known: true`) is green when run alone.
- [ ] A plan-final `--stage c4` on a fixture plan_branch plan reports `verification_report: pass`.
- [ ] `aid-evidence-verify.sh` with no pack and no `--out` exits 1 and `find <tree> -name verification-report.json -newer <marker>` finds nothing.

**Effort:** M
**AID Role:** backend

### Step 6: Acceptance evidence from the gate that verified it; the two stages read a skip the same way

**Objective:** `acceptance-evidence.json` at plan level is built from `plan-diff.json`, says `prose_only` when nothing was machine-checkable, and `--stage inputs` accepts exactly what `--stage gates` accepted; the orphan script is gone.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-acceptance-evidence.sh` — deleted (`git rm`; 293 lines; no runtime caller, two test callers and one comment, all handled below).
- Modify: `plugins/aid-orchestrator/scripts/tests/test-semantic-review.sh` (lines 4, 49-80, 195-215) — cases T3 and T10, which ran `aid-acceptance-evidence.sh reconstruct`, removed; the header line names the remaining subjects; tier tag unchanged (t2).
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh` (line 304) — the comment names the plan-diff producer instead of the deleted script.
- Modify: `plugins/aid-orchestrator/agents/verifier.md` (lines 200-225) — the "AC↔Evidence" section removed.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines 10252-10505 producer; 6561-6577 assertion; 507 force message) — the producer reads `<run>/plan-diff.json` `results[]` into `criteria[]` with the verdict rule of the Data Model; the AC-lens assertion accepts `overall_verdict: skipped` when the existing `_pfsm_plan_has_patterns` (line 4597, the predicate `--stage gates` already uses at 5043) says the plan declares no `verification_pattern`; `--force` covers the assertion and writes its waiver, and the force message lists what it bypassed.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — the seeds this suite uses for the plan-final inputs updated to the round shape (the suite is red in the nightly of 2026-09-18, `known: true`) before the three new cases are added; this reseed belongs here, not to Step 8.
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` (line 807 region) — `acceptance_evidence` with `verdict: prose_only` is `pass` with a note; `partial` is a blocker naming the failed criteria.
- Modify: `plugins/aid-orchestrator/reference/review-successors.md` — row for `aid-acceptance-evidence.sh` (successor: the plan-diff producer in `aid-plan-fsm.sh`).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (lines ~830-865) — the two rows citing `aid-acceptance-evidence.sh` retired with successors (a retired row keeps the old name in its `source:` field by the registry's own convention); new row `acceptance_evidence_from_plan_diff`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — a plan with two pattern ACs (one passing, one failing) yields `partial` with both criteria; a prose-only plan yields `prose_only` and `--stage inputs` passes; a prose-only plan with a required AC lens and `--force` writes a waiver naming the assertion.
- Test: `plugins/aid-orchestrator/scripts/tests/test-review-successors.sh` — the deleted script's registry ids have successor rows.

**Reuse check:** searched: `grep -n 'plan-diff.json' plugins/aid-orchestrator/scripts/aid-plan-fsm.sh plugins/aid-orchestrator/scripts/aid-release-policy.sh` → several matching — the file is already read by both; the producer reads it once more instead of files nobody writes.

**Parallel group:** ---

**Architecture Context:** One verifier of acceptance criteria (`aid-plan-diff.sh`), one evidence file derived from it, one predicate for "this plan has nothing to run" shared by both stages.

**Implementation Detail:** `sources[]` keeps today's contributing EPIC list so the manifest row at 5179 stays true.

**Error Handling:** `plan-diff.json` missing at `--stage inputs` → the stage stops with `run --stage gates first`, as today for other gate outputs.

**Edge Cases:**
- A plan whose ACs mix prose and patterns: `partial` or `verified` from the pattern ones, the prose ones listed with `verdict: skipped`.
- `test-aid-plan-final-boundary` is red in the nightly (`known: true`); its reseed is this step's own Files entry above, done before the three cases are added.
- A plan whose `plan-diff.json` has `overall_verdict: partial` (a pattern timed out): `partial`, the timed-out criterion listed with `verdict: skipped` and its evidence text, C4 blocks on it by name.

**Dependencies:**
- Depends on: Step 5
- Blocks: Step 9

**Acceptance Criteria:**
- [ ] `ls plugins/aid-orchestrator/scripts/aid-acceptance-evidence.sh` fails; `grep -rln 'aid-acceptance-evidence' plugins/aid-orchestrator/scripts plugins/aid-orchestrator/agents plugins/aid-orchestrator/commands plugins/aid-orchestrator/skills` returns nothing (the CHANGELOG's historical entries and the retired registry rows' `source:` fields are the only remaining mentions, by design).
- [ ] The three new boundary cases pass; a WAN-shaped fixture (six pattern ACs, no EPIC files) yields `verified` with six criteria.
- [ ] `--stage gates` and `--stage inputs` on the same prose-only fixture both exit 0, and the `inputs` stderr carries the same acceptance note as `gates`.

**Effort:** M
**AID Role:** backend

### Step 7: The traces the FSM claims — allocator, set-field, auto mode, yq

**Objective:** `alloc` never hands out a taken id; `set-field` leaves a timeline line and needs a reason for precondition fields; `--auto` writes its state file; a missing `yq` is a loud precondition failure.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines 8908-8930 alloc; 5980-6012 set-field; 1266-1276 review switch; 8952-8998 dispatcher) — the allocator loops `next` past any `P<NNN>-*.md`/`E-<NNN>*.md` present (glob via `compgen -G`) and says how many it skipped; `set-field` reads the old value before the rewrite, appends `field_set` through `derive_timeline`, refuses `total_steps`, `current_step`, `plan_json_hash`, `base_commit` without `--reason "<≥ 20 chars>"`, and for those four fields exits 1 with the path it tried when `derive_timeline` resolves no timeline (a reason with no record is refused, not silently dropped); `auto-mode set auto|manual --by <who> [--reason <text>]` and `auto-mode get` subcommands write and read `.aid-o/work/auto-mode-state.yaml` (the fields `/aid-stop` writes today — `stopped_at`, `stopped_by`, `stop_reason` — kept in the schema, and `get` tolerates a file written by the old `/aid-stop` text); `fsm_check_review_round` returns 1 with `PRECONDITION FAIL: yq is not installed` before the loop (no command substitution).
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-permissions.sh` (line 34) — `aid_autonomous_mode()`, the declared one reader of auto-vs-manual (P090), consults the state file: precedence `auto-mode-state.yaml` `mode: manual` (a PM stop always wins, including over a controller that exported `AID_AUTO_MODE=1`) → `AID_AUTO_MODE=1` (this controller announced itself) → `auto-mode-state.yaml` `mode: auto` → `permissions.yaml` as today; the function keeps its contract and returns `auto` or `manual`, never another word; every decision point keeps calling this one function, so the file is a persisted input of the one reader, never a second reader.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines 46-66) — the first action of `--auto` is `aid-fsm.sh auto-mode set auto --by "aid-run --auto"`; a failure stops the command.
- Modify: `plugins/aid-orchestrator/commands/aid-stop.md` (lines 43-80) — Step 2 writes through `aid-fsm.sh auto-mode set manual --by pm --reason "<stop reason>"` instead of a hand-written file.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines 2662-2668) — the writer and the one reader are named; the fail-safe sentence stays.
- Modify: `plugins/aid-orchestrator/skills/run-management.md` — `set-field` paragraph names the reason rule.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `alloc_skips_taken_ids`, `set_field_traced`, `auto_mode_state_written`, `review_round_needs_yq`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-alloc-lock.bats` — a `P075-x.md` present makes the allocator print `P076` and move the counter to 76, with a NOTE line; the empty-directory case is unchanged.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — `set-field total_steps 2` without `--reason` exits 1; with it, the timeline's last line is `field_set` with `old: 4`, `new: 2`; on a state file with no `epic_id`/`run_id` the same call exits 1 naming the missing timeline; `set-field note x` needs no reason and still logs; `auto-mode set auto` writes the file and `get` prints `auto`; `get` on a file in the old `/aid-stop` shape prints `manual`.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-permissions.bats` — the first suite of `scripts/lib/aid-permissions.sh` (today no suite exercises `aid_autonomous_mode`); tag `# aid-tier: t0` from a first measurement with `aid-test-tier-assign.sh` (three cases over a temporary `.aid-o/work/` directory, well under 2 s each); the only new suite of this plan. Cases: `aid_autonomous_mode` prints `auto` from a state file written by `auto-mode set auto` with no `AID_AUTO_MODE`; prints `manual` when the file says so although `permissions.yaml` allows auto; prints `manual` with `AID_AUTO_MODE=1` exported and a file written by `auto-mode set manual --by pm` (the stop wins). The registry row `auto_mode_state_written` cites these cases.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-review-round-fsm.bats` — with `yq` off PATH, `fsm_check_review_round` returns 1 (not an abort of the sourcing shell) with the yq line.

**Reuse check:** searched: `grep -rn -e 'autonomous_mode' -e 'AID_AUTO_MODE' -e 'auto-mode-state' plugins/aid-orchestrator/scripts plugins/aid-orchestrator/commands` → several matching (`scripts/lib/aid-permissions.sh:34` the one reader, `scripts/aid-fsm.sh:372` and `:3504` the env signal, `scripts/aid-release-policy.sh:79` a consumer, `commands/aid-stop.md:43-76` a hand-written writer of the file, `scripts/aid-lint-skill.sh:75` a lint comment) — the reader exists and is kept as the only one; what is missing is a script that writes the file the documentation and `/aid-stop` already name, so the writer is founded in `aid-fsm.sh` and the reader learns to read it; no second reader.

**Parallel group:** ---

**Architecture Context:** Every mutation of run state leaves a line; every "enabled by default" has a tool check; the number the allocator prints is free.

**Implementation Detail:** The four fresh diffs of 2026-09-19 (scratch branch) are the wrong first drafts of three of these changes, each with the defect the reviewer named; this step writes them correctly (`compgen -G` not `[[ -f glob ]]`; old value before the rewrite; the yq check outside `$(…)`).

**Error Handling:** `auto-mode set` with an unwritable `.aid-o/work` exits 1 with the path.

**Edge Cases:**
- A counter far behind the files (P092 vs P106): the loop skips fourteen ids and says so.
- `set-field` on a field that does not exist yet (append path): logged with `old: ""`.
- `alloc` in a workspace whose `plans/` holds `P075-a.md` and `P075-b.md` (a duplicate by hand): both skipped, one NOTE, `P076`.

**Dependencies:**
- Depends on: none
- Blocks: Step 8

**Acceptance Criteria:**
- [ ] The new cases pass; `grep -c 'auto-mode' plugins/aid-orchestrator/scripts/aid-fsm.sh` ≥ 3; `grep -rln 'auto-mode-state' plugins/aid-orchestrator/scripts --include='*.sh' | grep -v aid-lint-skill.sh` lists exactly `aid-fsm.sh` and `lib/aid-permissions.sh` (one writer, one reader; the lint's comment at `aid-lint-skill.sh:75` is neither).
- [ ] Review finding "The new precedence in Step 7 puts `AID_AUTO_MODE=1` ABOVE `auto-mode-state.yaml`" is answered: with `AID_AUTO_MODE=1` exported and a state file written by `auto-mode set manual --by pm`, `aid_autonomous_mode` prints `manual` (the third `test-aid-fsm.bats` case above).
- [ ] Review finding "Step 7's only breaking test for the new auto-mode precedence" is answered: the three `aid_autonomous_mode` cases live in `test-permissions.bats`, which this step creates, and the registry row `auto_mode_state_written` cites them.
- [ ] Review finding "Step 7's new test line names `scripts/tests/bats/test-permissions.bats`, a suite" is answered: the suite is declared as a `Create:` of this step with a tier tag from `aid-test-tier-assign.sh`, `aid-test-tier-lint.sh` accepts it, and the Testing Strategy names it as the plan's one new suite.
- [ ] `commands/aid-run.md` names the `auto-mode set` call before any other `--auto` action.
- [ ] `aid-fsm.sh set-field total_steps 2 <state>` without `--reason` exits 1 and leaves `<state>` byte-identical.

**Effort:** M
**AID Role:** backend

### Step 8: Stale fixtures, the registry baseline, the CP4 template, and what is red on main

**Objective:** The merge path is green on this branch for reasons this plan can name: every suite red on `main` or in the nightly of 2026-09-18 is either reseeded (stale fixture) or has a backlog row with the real cause.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/fixtures/enforcement-registry-baseline-pre-p066-e3.json` — regenerated (one JSON line) from the registry at this branch's HEAD.
- Modify: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-test-audit.sh` (lines ~127-140) — `DECLARED_AMENDMENTS` trimmed to what the new baseline no longer covers.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-roots-worktree.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — the four cases (roots-worktree 277 and 592, release-policy 179, aid-fsm 2181) reseeded with `aid_fixture_seed_step_review` and the P093 CP1 round seed where the old verifier files were expected.
- Modify: `plugins/aid-orchestrator/defaults/templates/verifier-output-template.md` (lines ~40-90) — cherry-pick of the scratch commit 952cee49 (the pre-filter sentences removed).
- Modify: `.aid-o/work/backlog.md` — a row per suite that stays red for a non-fixture reason (candidates: test-generation-labels 3/7/11/12, test-standards-map:169, test-control-enforcement:40, test-plan-continue:88, test-recovery-adjudicate), with the failing assertion quoted; IMP-607, IMP-608, IMP-610, IMP-611 closed.
- Test: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` — `--tier t0 --verbose` and `--tier t1 --verbose` (the runner CI uses, `.github/workflows/ci.yml:80`; pass string `RESULT: PASS` at `run-all-tests.sh:644`) both pass on this branch.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-c3-audit.bats` + `plugins/aid-orchestrator/scripts/tests/test-semantic-review.sh` + `plugins/aid-orchestrator/scripts/tests/test-evidence-verify.sh` + `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats` — the four t2 suites this plan touches, run alone once here; each green, or its remaining red assertion quoted in a backlog row.

**Reuse check:** searched: `grep -n 'aid_fixture_seed_step_review' plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash` → one match — the P094 seeding helper is reused for every reseed; no new helper.

**Parallel group:** ---

**Architecture Context:** A red suite nobody reads is not a gate; this step makes the merge path mean something again before Step 10 relies on it.

**Implementation Detail:** Each candidate suite is run alone first; a failure whose assertion names a removed file or an old evidence shape is a fixture; anything else gets a backlog row and stays red with its row cited in the CHANGELOG.

**Error Handling:** A reseed that turns one failure into another is reverted and the suite gets a row instead.

**Edge Cases:**
- `test-aid-fsm.bats:2181` asserts `not EXECUTE` after `amend-scope` — the seed must carry a closed cp2 round for the widened step or the transition is refused for the new reason.
- The regenerated baseline makes `DECLARED_AMENDMENTS` empty: the array stays declared with a comment so the next plan has the slot.
- `test-recovery-adjudicate` red for one night only: run three times; a flake gets a row marked `flaky` with the three outputs, not a reseed.

**Dependencies:**
- Depends on: Step 7
- Blocks: Step 9

**Acceptance Criteria:**
- [ ] `bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t0` and `--tier t1` print `RESULT: PASS` on this branch at the step's commit.
- [ ] IMP-607, IMP-608, IMP-610, IMP-611 carry `done` in `.aid-o/work/backlog.md`; every still-red suite has a row.
- [ ] `test-enforcement-registry-test-audit.sh` passes with an empty or shorter `DECLARED_AMENDMENTS`, and the fixture's registry ids equal the registry's at HEAD (`jq`/`yq` comparison in the suite).

**Effort:** M
**AID Role:** backend

### Step 9: Records — registry totals, successors, changelog, the measured Sonnet rate, the issue annotations

**Objective:** Every new refusal has a registry row with a breaking test, every deleted id a successor, the CHANGELOG entry for 2.100.0 exists in both files, `prices.yaml` carries the Sonnet rate measured on this plan's own rounds, and every taken project entry is annotated.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — `totals:` recounted; `test:` fields point at the cases of Steps 1, 3-7.
- Modify: `plugins/aid-orchestrator/defaults/prices.yaml` (lines 24-31) — `blended` for `sonnet` from the `measurement.json` files of this plan's cp2 rounds (`tokens` and the Agent tool's reported input/output split where present), `blended_basis: "measured: P095 cp2 rounds, N rounds, <date>"`.
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — identical `## [2.100.0]` entries (Added: stand-in, auto-mode, alloc collision; Changed: adjudicator forms, acceptance evidence producer, evidence-verify; Fixed: C3 verify, set-field trace, yq, fixtures; Removed: `aid-acceptance-evidence.sh`).
- Modify: `docs/plans/P094-aftermath-and-next.md` — §4 items marked done with the step; the triage list gains the outcome column.
- Modify: `docs/plans/plugin-issues-inbox.md` — the 24 entries appended by `bin/aid-plugin-issues-collect.sh` (run once in this step; the collector itself is not edited), each followed by its outcome line.
- Modify: `/opt/eco/projects/acta/.aid-o/work/aid-plugin-issues.md` + `/opt/eco/projects/agents/.aid-o/work/aid-plugin-issues.md` + `/opt/eco/projects/wan/.aid-o/work/aid-plugin-issues.md` — a `> **HOTOVO 2.100.0 (date):** …`, `> **ZAMÍTNUTO:** …` or `> **NECHAT, ověřit <kdy>**` line under each taken entry, per the triage of the aftermath record (fixed here: acta 14/15/16/19, 2026-09-02 pre-push, 2026-09-03 set-field and gates/inputs; wan 2026-09-02 ×2, 2026-09-19 ×2; rejected as superseded: agents 1/3/6/7, acta 17/20, agents 2b; kept for later: acta 18, acta plan_branch, wan pre-push label, wan brainstorm, agents 2a/4/5 as lessons).
- Test: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh` + `plugins/aid-orchestrator/scripts/tests/test-review-successors.sh` + `plugins/aid-orchestrator/scripts/tests/bats/test-review-summary.bats` — green after the registry and price edits.
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — `2.100.0 --baseline 2.99.0` exits 0.

**Reuse check:** searched: `grep -n 'blended_basis' plugins/aid-orchestrator/defaults/prices.yaml` → one match per model — the field exists for exactly this replacement.

**Parallel group:** ---

**Architecture Context:** The registry and the successor table are the two lists the next plan starts from; the project files are the projects' records.

**Implementation Detail:** The pre-push `(delete)` entry (ACTA 2026-09-02) is annotated `HOTOVO 2.93.0` with the hook line that already skips it (`defaults/hooks/pre-push:336`, the all-zero SHA `continue`), verified on 2026-09-19 by the existing case "a deleted ref is skipped".

**Error Handling:** The collector refuses a project file it cannot mark; the annotation for that project is deferred and named in the CHANGELOG.

**Edge Cases:**
- A project file changed by its own agent between collection and annotation: the annotation goes under the entry by its heading, never by line number.
- A project file with a new, untaken entry written after the collection: left untouched, named in the CHANGELOG as "collected next time".
- The Sonnet measurement has fewer than three cp2 rounds with a known token count: `blended_basis` stays `estimated:` and says how many rounds were measured.

**Dependencies:**
- Depends on: Step 2, Step 3, Step 4, Step 6, Step 8
- Blocks: Step 10

**Acceptance Criteria:**
- [ ] `verify-version-files.sh 2.100.0 --baseline 2.99.0` exits 0; both CHANGELOG sections are identical.
- [ ] `grep -c 'HOTOVO 2.100.0\|ZAMÍTNUTO\|NECHAT' <each project file>` ≥ the number of entries the collector marked taken in that project, as printed by `bin/aid-plugin-issues-collect.sh` on the day (on 2026-09-19: acta 11, agents 7, wan 6 = 24; the Agents entry "2" carries both observations 2a and 2b).
- [ ] `prices.yaml` `sonnet.blended_basis` starts with `measured:` when at least three cp2 rounds of this plan carry a known token count, otherwise with `estimated:` followed by the number of rounds that were priced — one outcome, stated in the same words as the Edge Case.

**Effort:** M
**AID Role:** docs-writer

### Step 10: Release 2.100.0, plugin refresh, testbed, five diffs live

**Objective:** The plugin is released, installed, verified by the testbed, and the five diffs re-run live through the installed plugin give 1 pass, 3 fail, 1 skip.

**Files:**
- Modify: `.claude-plugin/marketplace.json` + `plugins/aid-orchestrator/.claude-plugin/plugin.json` + `plugins/aid-orchestrator/README.md` + `README.md` — version locations 3-8 for 2.100.0; README Roadmap keeps three lines.
- Modify: `docs/plans/P094-fresh-diffs.md` — the third table: live against the installed 2.100.0 (ceiling 4 USD).
- Test: `/opt/eco/projects/aid-testbed/bin/verify.sh` — 0 FAIL, 0 SKIP against the installed 2.100.0 (the two uncommitted testbed fixes of 2026-09-19 must be committed first; needs the PM's `chown`, see Resources Verification).

**Reuse check:** searched: `grep -n 'plugin update' CLAUDE.md` → one match — the refresh procedure of CLAUDE.md is followed, not duplicated.

**Parallel group:** ---

**Architecture Context:** The release boundary of this repository; the testbed verifies the installed copy, never the tree.

**Implementation Detail:** Merge to `main` from the primary checkout, tag `v2.100.0`, `gh release create` with the CHANGELOG section, push, `claude plugin update`, force-refresh of the marketplace clone if the version does not move, `/aid-help` shows 2.100.0, then the testbed, then the five live rounds.

**Error Handling:** A testbed FAIL after release is a 2.100.1, never a silent known finding.

**Edge Cases:**
- The testbed commit still blocked by ownership: the run is done against the working tree's `verify.sh` and the fact is written in the record.

**Dependencies:**
- Depends on: Step 9
- Blocks: none

**Acceptance Criteria:**
- [ ] `jq -r '.plugins["aid-orchestrator@claude-aid-o"][0].version' ~/.claude/plugins/installed_plugins.json` prints `2.100.0`.
- [ ] `docs/plans/P094-fresh-diffs.md` live table: `pass, fail, fail, fail, skip`, cost under the ceiling.

**Effort:** S
**AID Role:** backend

## Testing Strategy

| Behaviour | Where | Tier |
|---|---|---|
| A range citation and an inline read-only reproduction are accepted; a write in an inline command is refused with its own reason; no `local:` noise | `test-review-adjudicate.bats` | t1 |
| The five recorded answers give 1 pass, 3 fail, 1 skip on the fixed adjudicator | `test-step-review-acceptance.sh --mode replay-do` | t2 (five adjudicator runs) |
| A Codex role answered by a Claude stand-in is accepted only with the fallback record; the opponent never stops on a missing Codex; the highest-version binary wins | `test-review-round.bats`, `test-brainstorm-opponent.bats` | t1, t0 (existing tiers) |
| A raw/report mismatch in the C3 bridge exits 1 and leaves `unverifiable` with the raw findings; `--reference` and a second run write nothing | `test-c3-audit.bats` (existing tier) | t2 — nightly, and run alone in Step 8 before the release |
| The pack is found from a worktree, untracked directories are not dirt, non-protocol files are skipped, the candidate head passes freshness, no pack writes nothing; EPIC mode passes no candidate | `test-evidence-verify-tree.bats`, `test-release-policy.bats` | t0, t2 (existing tiers) |
| Acceptance evidence is `verified|partial|prose_only` from plan-diff; `inputs` accepts what `gates` accepted; `--force` waives the AC-lens assertion | `test-aid-plan-final-boundary.bats` | t2 (existing tier; cross-component) |
| The allocator skips taken ids; `set-field` traces and demands a reason; `auto-mode` writes and reads; `fsm_check_review_round` fails loudly without yq | `test-alloc-lock.bats`, `test-aid-fsm.bats`, `test-review-round-fsm.bats` | t2, t2, t1 (existing tiers) |
| `aid_autonomous_mode` reads the state file with the stop winning over `AID_AUTO_MODE=1` | `test-permissions.bats` (new) | t0 from a first measurement |
| The merge path is green and every red suite has a named cause | `run-all-tests.sh --tier t0`, `run-all-tests.sh --tier t1`, backlog rows | merge path |
| Registry cites and successors hold; versions agree | `test-enforcement-registry-cites.sh`, `test-review-successors.sh`, `verify-version-files.sh` | t0, t0, release boundary |
| The installed plugin still refuses the sabotaged plan and diffs | testbed `verify.sh` | live |

One suite is new in this plan: `test-permissions.bats` (Step 7; the first suite of `lib/aid-permissions.sh`; tag from a first measurement with `aid-test-tier-assign.sh`, expected t0). Every other case joins an existing suite and inherits its tag (`test-brainstorm-opponent.bats` is t0 and its new cases stub the probe to stay under the budget; `test-evidence-verify-tree.bats` is t0; `test-c3-audit.bats`, `test-aid-plan-final-boundary.bats`, `test-alloc-lock.bats`, `test-aid-fsm.bats`, `test-release-policy.bats` are t2). `aid-test-tier-lint.sh` is run in Step 8; a suite whose new cases push it past its budget is re-measured with `aid-test-tier-assign.sh` and the move is recorded in the CHANGELOG.

## Constraints

- Language: English in plugin code, comments, skills, commands; Czech in PM cards, `docs/plans/` records and the project annotations.
- Hygiene rule B: no dead code left in a modified file; a registry row with the ten fields and a breaking test for every refusal added.
- No new plugin dependency; `codex` stays optional and is now provably optional.
- Subagents: at most two at once; reviewers of the rounds are what the checkpoint config names; no other subagent without the PM's go with count and model.
- Paid runs (Step 2 live re-run, Step 10 live re-run): ceiling 4 USD each, written in the record before the run.
- Merge path t0 + t1 green at Step 8 and at merge; targeted suites during development.
- Every `docs/plans/` record committed with `git add -f`.

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| The inline-command allowlist admits a write through a verb it does not know | low | a reviewer's repro mutates the tree | the list is a closed allowlist, unknown verbs refuse; redirections refuse regardless of verb; the round runs in the controller's tree where a mutation is visible in `git status` |
| The stand-in changes CP1's degraded semantics for existing evidence | low | old rounds re-read differently | `collect` keeps `provider_absent` for records without `fallback`; only new records carry it |
| Codex returns on 2026-09-21 mid-plan and the stand-in path is never exercised live | medium | the mechanism is tested only by stubs | the tests drive it with `codex` off PATH; a live run with the binary renamed is done once in Step 3 and recorded |
| Reseeding a fixture hides a real regression | medium | a bug ships green | Step 8's rule: a failure that does not name a removed file or an old shape gets a backlog row, not a reseed |
| The acceptance-evidence producer changes what C4 blocks on for plans mid-flight (P076, P080, P087 open) | low | a plan-final that passed would block | `prose_only` and `verified` pass; only `partial` blocks, and it names the failing criterion the gate already reported |
| The first live EPIC of the step review costs more than the acceptance run predicted | medium | budget surprise | every round is priced and visible in `/aid-status`; the PM sees the first three steps' cost on the run card |

## Success Criteria

- [ ] `test-step-review-acceptance.sh --mode replay-do` and the live re-run against the installed 2.100.0 both give `pass, fail, fail, fail, skip` (Steps 2, 10).
- [ ] With `codex` absent, a CP1 round, a CP3 round and a brainstorm opponent run each complete with a recorded Claude stand-in and no PM question (Step 3).
- [ ] `test-c3-audit.bats`, `test-evidence-verify-tree.bats`, `test-evidence-verify.sh`, `test-aid-plan-final-boundary.bats` are green on the branch with the new cases, each run alone (Steps 4-6).
- [ ] `run-all-tests.sh --tier t0` and `--tier t1` pass at merge; every suite still red has a backlog row (Step 8).
- [ ] `defaults/prices.yaml` carries a measured Sonnet rate; the registry totals match the rows; every deleted id has a successor (Step 9).
- [ ] The installed plugin is 2.100.0, the testbed prints 0 FAIL 0 SKIP, and the 24 project entries are annotated (Steps 9, 10).

## Next Steps

- After three EPICs on the step review: compare cost per confirmed finding with `docs/plans/P094-fresh-diffs.md` and decide whether `step_security` stays conditional.
- Codex live as `epic_security` once for one EPIC after 2026-09-21, compared with the stand-in's yield.
- The low-priority quartet of the aftermath record (`delivery.md` producer, plan_branch steps needing `main`, the pre-push label, brainstorm without a plan) as one small plan when the PM chooses.
