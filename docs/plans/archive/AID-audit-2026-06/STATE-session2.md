# P041 — STATE handoff (session 2) — read first after compact

## ⏩ LATEST (2026-06-04) — P041 Wave 2 COMPLETE + v2.28.0 SHIPPED
- **P041 audit (Waves 1+2) is DONE and RELEASED as v2.28.0.** Full GitHub release done per PM:
  merged `fix/P041-wave2` → main (ff), tag `v2.28.0` (+ backfilled v2.26.0/v2.27.0), pushed main+tags,
  GH release (https://github.com/marekstancl/claude-aid-o/releases/tag/v2.28.0), plugin cache refreshed.
  Version consistent everywhere (main HEAD `2605fee`). **User must restart Claude Code to load v2.28.0.**
- **Fix-plan A–I all done EXCEPT the memory block** (G1 qdrant→vulcan + I3 threshold = `[~]`, folded
  into deferred MEM-AUDIT). 10-fix-plan.md checkboxes updated.
- **Nothing in flight, working tree clean, on `main`.** No uncommitted work.
- **REMAINING = deferred only** (all in BACKLOG.md "P041 Wave 2 — deferred follow-ups"):
  big = MEM-AUDIT, REFLECT-WIRE, SKILL-RETROFIT; small = E171 (parallelism off, moot), ~7 low-value
  doc GAPs (E91/E106/E107/E108/E113/E124/E126), execution.yaml `config` non-role.
- **Next move is PM's call** — no active task. None of the deferred items start without PM go.
- Working agreements unchanged (below). NOTE: docs/plans/ (incl. this file + BACKLOG.md) is gitignored —
  local-only; root CLAUDE.md also gitignored.

---

Continues STATE.md. Same working agreements: talk human/no internal codes; propose → my internal
check → give Marek copy-paste text for HIS external verifier → on PASS apply; archive-not-delete;
commit per coherent batch, NO push/tag/merge/release without explicit PM say.

## Git
- **Branch:** `fix/P041-wave2`. **HEAD:** `f41a692` (auditor overhaul committed).
- **main:** local-only, at `v2.27.0` (NOT pushed). Wave-2 commits live on `fix/P041-wave2`.
- **Committed on branch:** `9a2e0f8` (Group 1: aid-run fiction + task→epic terminology),
  `19627ee` (planner.md rewrite + agent-protocol branch fix), `f41a692` (auditor.md overhaul + aid-audit.md).
- **Committed `3cd25b1`** (curator overhaul + propose-only + #21 re-home + CP4-post-apply reorder +
  S/M/L auto-apply): auditor.md, curator.md, gate-fixer.md, verifier.md, aid-run.md, pipeline.md.
  The (a)/(b) question RESOLVED: aid-help.md:139 / plan-writing.md:994-995 / aid-run.md:14,30-34,241-244
  are the `--auto` EXECUTE autonomous escalation (mechanism a) → left as-is. Only genuine twins fixed:
  pipeline.md:1186 "CP4 (curator)"→"CP4 (curator+auditor)" + aid-run.md:363 CP4 advisory scope
  (curator-only → §7 curator/auditor auto-fix). Both PASS-verified externally.
- **Committed `84a3e53`** (H1 DONE — role-cards.md holistic unification + model single-source-of-truth):
  13 files. Model SoT = role-cards.md (orchestration.yaml `models:` block removed, pipeline.md phantom
  `role_assignments`/role-tiers removed, planner.md + schema reconciled, optional step.model override).
  e2e now a real step role (added to schema enums + aid-epic-to-json VALID_ROLES; one rich card; dead
  Focus:e2e removed; DoD-driven + conditional Playwright + P022 anti-pattern). `docs`→`docs-writer`
  everywhere (schema/script/epic template+example/execution.yaml/plan-writing/fixtures/auditor table).
  qa full card homing the 3 dropped learnings (mock-vs-real, behavior-vs-AC, env gotchas); behavior-vs-AC
  also in code-review focus. Single footer, Max Parallel annotated "capped at 1", VULCAN = overlays,
  internal NR/# numbers stripped from shipped text. Full analysis: 15-role-cards-holistic.md.
  PM decisions: model SoT=role-cards ✓; e2e=both(2c) ✓; rename to **docs-writer** (not docs) ✓;
  qa full card ✓; Max Parallel keep-with-note ✓. Two external verifier rounds (each found one more
  twin: +5 docs tokens & NR-numbers, then auditor.md:354 token table) → all fixed + PASS.
- **LATENT BUG for backlog (not fixed — out of scope):** execution.yaml content_quality auto_accept
  list references role `config` which is NOT in any role enum; the auto_accept/review_required lists
  are also partial (omit domain/observability/qa/e2e). Needs intent before fixing.
- **E2 DONE (no-op, no commit):** `{task_id}`→`{epic_id}` already fixed in Wave 1; pause/resume/reorder
  subcommands already gone from aid-status.md; Auto-pickup is a real FSM mechanism (pipeline.md §7 queue
  pickup, gated mode==auto); aid-status hardcodes no queue field names and everything it displays exists
  in the written queue.yaml entry (aid-queue-add.sh:444-449: epic_id/path/priority/status/depends_on/added_at).
  Marked [x] in 10-fix-plan.md.
- **CLEAN working tree. HEAD `84a3e53`.** Remaining Wave-2 items are ALL [FEEDBACK]-gated bigger steps,
  do NOT start without PM:
  - **C1 (AID-046) provenance — DONE `921f3ca`** (2026-06-03): interval-bracket window (start..complete +
    tolerance, replaces broken ±60s); `fabricated`→`unverifiable` honest rename (serialized value, all
    surfaces); fail-closed blocking floor when yq/registry unreadable; PM-added non-negotiable
    anti-fabrication rule in pipeline.md Dispatch Protocol (orchestrator MUST dispatch real verifier, MUST
    NOT self-write/reuse/head-review). Honest framing throughout: timing catches accidents, the
    instruction+auditor+runtime are the real anti-fraud. +2 regression bats. 102 bats pass; 2 external
    verifier PASS.
  - **I1 (AID-050) promote foundations** — promote skill-writing + command-writing foundations into the
    plugin WITH a guard, as a versioned code-change (+ CHANGELOG). Bigger step; "kdy do toho jít."
  - **I2 (AID-052) coverage** — map remaining ~91 enforcement checks + audit 6 skipped files. "Teď/později."
  - Plan note: I1+I2 = "version + CHANGELOG + plugin deploy — separate action once the rest is done."
- **I2 (AID-052) coverage mapping — DONE.** Mapped E87–E177 (91 enforcements) + 6 skipped files + #11
  via 5 Explore agents; 2 external verifiers (the FAIL one caught fan-out over-claiming ALIGNED on the
  config-policy group). Findings: 16-coverage-completion.md. Proposal (revised post-verify):
  17-config-policy-proposal.md. Inventory corrections appended to 01-enforcement-inventory.md.
- **I2 SAFE FIXES — DONE `0920727`** (4 files): Visual Anchoring now hard-enforced in cmd_increment_step
  (E161 was a decoration); dead global `retry.max_attempts` block deleted from execution.yaml (E151);
  run-management.md no longer falsely claims the Controller auto-enforces the PM-GO phase boundary
  (E165). +2 bats. 104 bats pass. Two external verifiers PASS.
- **REMAINING I2 = config-policy per-knob decisions (PM-gated, the "rest"):**
  - E142 release.skip_when → DELETE (stale) vs IMPLEMENT in aid-release.sh. NOT an LLM instruction.
  - E157 role_overrides → SECURITY: implement real per-role enforcement vs degrade-to-advisory + remove
    the false "only release/security gets X" claim (+ note the blanket Bash(*) makes scoping moot).
  - E149 not_acceptable + NEW pre-filter config drift (review-checkpoints.yaml vs the actually-read
    pre-filter-rules.yaml) → reconcile the two files, then route each pattern (regex / scope-layer / advisory).
  - E141/E148/E143 → SINGLE-SOURCE (yaml vs hardcoded duplicate in pipeline.md:743/1075 + claude-md.md:49).
  - E154/E155 → MEM-AUDIT (deferred).
  REJECTED by verifiers: the generic "load and honor all policy sections" instruction (sections are
  stale/duplicated → would make the LLM contradict scripts). Go per-knob.
- **THEN:** I1 (promote skill-writing + command-writing foundations + guard) → own versioned step.
- **THEN:** Wave-2 RELEASE (version bump + CHANGELOG + 8-file sync + tag + plugin deploy) — bundles all
  Wave-2 commits 9a2e0f8..HEAD. NOTE: nothing pushed/tagged/released yet (local branch only).
- **Config-policy per-knob — 3 of 4 + skill_conflicts DONE `dc64d9e`** (PM ⭐ all four): release.skip_when
  DELETED (unread); role_overrides DEGRADED to advisory + why-comment (Bash(*) makes scoping moot,
  real enforcement = separate); escalation triggers SINGLE-SOURCED (pipeline.md table authoritative,
  YAML→pointers, cap stays in orchestration.yaml, E1-E7→neutral "table above" since table is E1-E8);
  skill_conflicts SINGLE-SOURCED (deleted unread orchestration.yaml block, claude-md.md table canonical).
  4 files, no code paths changed, YAML valid, 2 verifiers (one caught E1-E7/E1-E8, fixed).
- **REMAINING config-policy = #3 pre-filter (PM: do SEPARATELY, test-first):** reconcile the two
  pre-filter config files (docs reference review-checkpoints.yaml; aid-prefilter.sh:16 actually reads
  defaults/pre-filter-rules.yaml) → pick canonical → then route the 5 unenforced not_acceptable patterns
  (TODO/FIXME w/o issue, disabled security, skipped tests, empty catch → regex rules; forbidden_paths →
  scope/verifier layer, NOT regex). PM caveat: confirm which file is "the read one" first (pre-filter-rules.yaml),
  add regexes ONE BY ONE with bats coverage (false-positive risk). NOT STARTED.
- memory thresholds (min_score/dedup) → MEM-AUDIT (deferred).
- **#3 pre-filter DONE `460b86c`** (I2 COMPLETE): single-sourced pre-filter regexes to
  pre-filter-rules.yaml (removed unread fail_patterns from review-checkpoints, fixed 2 doc refs);
  routed not_acceptable → 3 new ERE-safe fail_rules (debug_leftover excl. print(, skipped_test,
  disabled_security_check); annotated not_acceptable enforcement routing; FIXED pre-existing ERE bug
  in deserialize_dangerous ((?!_safe) lookahead → ERE-safe, was silently never matching). +6 bats
  (110 total). 2 external verifiers PASS.
- **I2 FULLY DONE.** Config-policy cluster closed. Only #3-adjacent leftover deferred: memory knobs → MEM-AUDIT.
- **Branch commits (10):** 9a2e0f8, 19627ee, f41a692, 3cd25b1, 84a3e53, 921f3ca, 0920727, dc64d9e, 460b86c, da76120 (I1).
- **I1 DONE `da76120`** (governance): promoted skill-writing + command-writing to skills/; aid-lint-skill.sh
  (mechanical linter, fence-aware) + test-skill-lint.sh (suite-enforced, grandfather list of 9 skills +
  commands); fixed a Principle-#5 gap (pipeline.md now documents the Visual Anchoring enforcement →
  test-instruction-consistency 75/0). 2 verifiers PASS. (root CLAUDE.md authoring note is local — root
  CLAUDE.md is gitignored.)
- **RELEASE v2.28.0 SHIPPED (2026-06-04, full GH per PM):** release commit `2605fee`; merged ff to main;
  tagged v2.28.0 (+ backfilled v2.26.0/v2.27.0 tags that Wave-1 local-only releases never created);
  pushed main + tags to origin; GH release created
  (https://github.com/marekstancl/claude-aid-o/releases/tag/v2.28.0); plugin cache force-refreshed to
  v2.28.0. NOTE: remote main was at fa554552 (v2.25.0) — the push also published the local-only v2.26.0
  + v2.27.0 commits. **User must restart Claude Code to load v2.28.0.**
- **P041 Wave 2 COMPLETE.** Remaining = DEFERRED only.
- **Still DEFERRED (PM-gated):** MEM-AUDIT, REFLECT-WIRE.
- **NEW DEFERRED — SKILL-RETROFIT (PM said: not now, but RECORD + revisit; "the rules have their purpose"):**
  Bring the 9 existing skills up to the skill-writing standard. Current state (mechanical audit 2026-06-03):
  0/9 have the line-2 header Last Updated; 7/9 lack `## MUST Rules`; 8/9 lack `## Completeness Gate`;
  agent-protocol.md + pipeline.md have version-stamped headings; pipeline.md has no footer date. Commands
  are mostly clean (footers present; legacy state.yaml essentially gone — only aid-run.md:1 bare
  `state.yaml` to verify; aid-stop uses legit `auto-mode-state.yaml`; aid-init has 1 version-stamp).
  Per the standards' own grandfathering rule, retrofit happens at >25% revision — but PM wants a tracked
  pass to do it deliberately. The I1 guard grandfathers these 9 skills for STRUCTURAL checks now.

## What this in-flight batch did (curator overhaul, PM-driven)
1. **curator.md = propose-only** (was self-contradicting: Identity propose-only vs Phase 5/6 dispatch-fix).
   Now: curator recommends disposition; Orchestrator writes status + dispatches gate-fixer. Added
   `## Input` contract, `recommended_disposition` output field, write-authority clarity, Phase 7
   reflection-hook note (lessons → local lessons-learned.md; memory store = memory subsystem, deferred).
2. **#21 re-homed** (4 safe auto-fix classes) → curator auto-approve advisory + **gate-fixer** fast-path
   auto-apply scope (NOT "curator fixes"). gate-fixer.md got a "Curator-Approved Fixes" section + Source Types rows.
3. **PM DECISION: permissive auto-approve S/M/L** (Marek: "auto approve chci i M a L"). default_action:approve
   stays. Only explicit always_defer rules (architecture, standards-L) defer.
4. **PM DECISION (a): CP4 reordered to AFTER apply.** pipeline §7 review sub-phase now: step7 curator
   auto-fix (S/M/L), step8 auditor auto-fix (S/M/L), step9 CP4 reviews the APPLIED curator+auditor
   changes (revert on fail). Was: CP4 before apply (step7) + S+M only. Fixed PM-summary template + the
   epic-summary "PM akce" row + CP-tables. This RESOLVED the recorded PIPELINE-§7-CP4 leftover.
5. Date bumps: curator/gate-fixer/verifier → 2026-06-03.

## ⚠️ OPEN — the last verifier verdict (interrupted) was MIXED: 1 PASS, 1 FAIL with 4 stale twins
The S/M/L + CP4 change rippled. Last FAIL flagged these still saying old "S-effort auto-fix / L-effort
always escalates":
- **aid-run.md:14, :31-33, :241-244** — "S-effort auto-fix, L-effort ALWAYS escalate to PM"
- **aid-help.md:139** — "S-effort auto-fix, L-effort always escalates"
- **plan-writing.md:994-995** — "S-effort fixes auto-approved … L-effort always escalates"
- **pipeline.md:1186** — "CP4 (curator)" stale shorthand (pre-filter context)

### CRITICAL UNRESOLVED QUESTION (decide first next session):
Are those "S auto-fix / L escalate" rules about:
- **(a) the `--auto` EXECUTE-mode escalation** (per-step gate/decision: S auto-fix, L→PM) — a
  DIFFERENT mechanism that legitimately stays S/L-based → NOT a conflict, leave them; OR
- **(b) the curator DONE auto-fix** (which we changed to S/M/L) → stale twins, must fix.
One verifier said (a) (different domain, no conflict); the other flagged them as stale (b). **Must
read aid-run.md:31-33/241-244 + aid-help.md:139 + plan-writing.md:994-995 in context and decide
per-occurrence** which mechanism each describes. Likely: the `--auto` escalation rules (EXECUTE
gate/decision) are (a) and stay; only curator-DONE-auto-fix mentions become S/M/L. pipeline.md:1186
"CP4 (curator)" → harmless shorthand, optionally → "CP4 (curator+auditor)".

## NEXT ACTIONS (in order)
1. Resolve the (a)/(b) question above for each flagged line; fix the genuine twins (b), leave the
   EXECUTE-escalation rules (a). Re-verify.
2. Commit the whole curator/CP4/S-M-L batch (curator+gate-fixer+verifier+auditor+pipeline+aid-run)
   as ONE commit once consistent.
3. **role-cards.md** holistic overhaul (PM wants same treatment as auditor/curator) — home dropped
   learnings: #10 (qa mock-vs-real diagnostic), #15 (verifier behavior-covered vs literal-AC + drift),
   #20 (qa env gotchas). #17 already propagated. #5 deferred (auditor Process). This finishes H1.
4. Then E2 (aid-status queue field names — quick), then Group 3/4.

## DEFERRED (recorded in 14-wave2-plan.md, do NOT start without PM)
- **MEM-AUDIT** — memory subsystem written-but-not-read suspicion (Principle #1); folds in G1
  qdrant→vulcan + AID-058a 0.85 threshold. Gates whether vulcan-memory is a viable reflection sink.
- **REFLECT-WIRE** — automatic per-EPIC reflection (curator slice → local reflection.md + opt-in
  central .md digest via integrations.yaml `reflection.central_digest_path` + opt-in vulcan-memory
  push pending MEM-AUDIT). Enforcement via FSM done-advance + plan-level gate, NOT auditor.
  Manual prompt (AID-post-plan-reflection-prompt.md) + PM's manual output stay AS-IS.

## Wave-2 fix-plan checklist (10-fix-plan.md): done = A1-A4,B1-B5,D1,D2,E1,E3,F1; [~]=G1,I3 (→MEM-AUDIT);
## open = C1 provenance, E2 aid-status queue, H1 (in progress via role-cards), I1 standards promote, I2 coverage.
