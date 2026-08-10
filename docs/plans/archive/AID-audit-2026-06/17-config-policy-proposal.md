# Proposal — config-policy decoration cluster + 3 instruction ORPHANs (post-I2) — 2026-06-03

Built on 16-coverage-completion.md (corrected after external verification). This proposes a
DISPOSITION per finding. Each premise the proposal rests on is tagged **[ASSUMPTION — verify]** so an
independent reviewer can confirm before any edit. Nothing here is implemented yet.

Guiding principle (AID-v3 §1): a rule with no enforcement is decoration. Two honest ways to fix a
decoration: (1) WIRE it (a script reads it, or an explicit instruction tells the LLM to honor it), or
(2) RECLASSIFY it honestly as advisory PM-config + say so. Pure deletion only when truly redundant.

## A. Config-policy cluster — proposed disposition per knob

| ID | Knob | [ASSUMPTION — verify] | Proposed disposition |
|----|------|------------------------|----------------------|
| E141 | `orchestration.yaml escalation.max_per_session: 3` | Nothing reads it; LLM is not told to count escalations | **WIRE via instruction** — add to pipeline.md ESCALATION section: "honor `escalation.max_per_session`; on the Nth escalation in a session, HARD STOP." LLM-honored soft policy. |
| E142 | `orchestration.yaml release.skip_when` | aid-release.sh never reads it; release sub-phase doesn't mention it | **WIRE via instruction** in pipeline.md §7 release: "before bump/tag, honor `release.skip_when` (skip when no new CHANGELOG version / versions already current)." |
| E143 | `orchestration.yaml skill_conflicts` | A SECOND hardcoded conflict table exists in skills/setup/claude-md.md:~49 → two sources of truth | **SINGLE-SOURCE** — make /aid-setup (claude-md.md) READ orchestration.yaml `skill_conflicts` instead of its hardcoded table; OR delete the yaml block if the table is canonical. Pick one source; eliminate the duplicate. |
| E148 | `execution.yaml escalation_triggers` (HARD STOP set) | Nothing enumerates them in instructions | **WIRE via instruction** — pipeline.md ESCALATION lists these as the canonical hard-stop triggers (or references the key). |
| E149 | `execution.yaml not_acceptable` patterns | [verify] overlap with the ENFORCED pre-filter `fail_patterns[]` in review-checkpoints.yaml | **ASSESS**: if a subset duplicates pre-filter fail_patterns (already enforced), merge/dedupe; for any not-acceptable pattern NOT in pre-filter, either add to pre-filter (real enforcement) or mark advisory. Needs the overlap check first. |
| E151 | `execution.yaml retry.max_attempts: 3` (global) | aid-run-gates.sh reads per-gate `max_retries` (default 1); the global block is read by nothing | **DELETE or DOCUMENT-AS-DEFAULT** — recommend DELETE the global block (it is dead; per-gate `max_retries` is authoritative). If kept, the runner must actually use it as the fallback (it currently defaults to 1, not to the global value). |
| E154 | `integrations.yaml search.min_score: 0.4` | memory-subsystem knob | **DEFER → MEM-AUDIT** (memory read-path is gated by that audit anyway). |
| E155 | `integrations.yaml dedup/merge_threshold` | fields DO NOT EXIST (phantom in inventory) | **DEFER → MEM-AUDIT** + correct the inventory (remove the phantom rows). |
| E157 | `permissions.yaml role_overrides` (capability scoping) | [verify] does /aid-setup permissions translate role_overrides into actual `.claude/settings.local.json` allow/deny rules, or is it decoration? | **SECURITY — ASSESS SEPARATELY**: if it is NOT translated into real permission rules, it is a security-relevant decoration. Either wire it into the permissions dual-write (real enforcement) or explicitly document it as advisory + accept the risk. Do NOT fold into the generic LLM-honor instruction — capability boundaries deserve real enforcement. |

**The "one instruction re-homes many" idea:** add to pipeline.md a single explicit directive — "the
orchestrator MUST load and honor the policy sections of execution.yaml / orchestration.yaml /
permissions.yaml" — which legitimizes E141/E142/E148 as LLM-honored policy in one move. This is
HONEST (turns silent decoration into instructed policy) but is LLM-judgment, NOT a hard gate. Adequate
for soft policy (escalation count, release skip), NOT a substitute for real enforcement on security
items (E157) or for deleting dead ones (E151).

## B. 3 instruction ORPHANs — proposed disposition
| ID | Rule | Proposed disposition |
|----|------|----------------------|
| E161 | frontend MUST emit `## Visual Anchoring` when visual_refs set | **LIGHT ENFORCEMENT** — CP2/step-verify check: when the step has visual_refs, the frontend output must contain a `## Visual Anchoring` section, else FAIL. Medium effort, real quality value. |
| E165 | PHASE-END HARD STOP (wait for PM GO) | **KEEP as manual-mode convention** + one honest line that `--auto` relies on the escalation rules instead of a phase gate. Low. (Building an FSM phase-gate deferred unless PM wants it.) |
| E171 | parallel-group file-conflict → serialize | **DEFER** — parallelism is OFF (orchestration.yaml `max_parallel: 1`); the rule is currently moot. Flag as a prerequisite to re-enabling parallel dispatch (Agent SDK migration). No code now. |

## C. Inventory-doc corrections (local 01-enforcement-inventory.md; NO plugin change)
E140 (stale ±60s desc → interval-bracket), E155 (remove phantom dedup/merge rows), E175 (paused→manual,
no resumable), E161 line ref (:92→:136), E171 line ref (:172→:183), E121 (GAP→ALIGNED), E106 (ALIGNED→GAP).

## D. Low-priority GAP docs — proposed: DEFER/SKIP by default
E91, E106, E107, E108, E113, E124, E126 — enforcement works, just not pre-documented (GAP = the
less-dangerous direction). Optional one-paragraph addendum in pipeline.md §2; low value.

## Sequencing proposal
1. Inventory corrections (C) — safe housekeeping, do anytime.
2. Config-policy: decide per bucket — WIRE-via-instruction (E141/E142/E148), SINGLE-SOURCE (E143),
   DELETE (E151), MEM-AUDIT (E154/E155), SECURITY-ASSESS (E157), OVERLAP-CHECK (E149).
3. Instruction ORPHANs: E161 light enforcement; E165 document; E171 defer.
4. This is sizeable — candidate for its own focused step rather than squeezing into the Wave-2 close.

---

## ⚠️ CORRECTIONS after external verification (2026-06-03, 2 reviewers) — REVISED dispositions
Both reviewers confirmed all premises (P1–P7) and **rejected the single generic "load and honor policy
sections" instruction** as the riskiest move: several policy sections are stale or already duplicated
as hardcoded copies in pipeline.md, so a blanket "honor all" would make the LLM contradict the scripts.
→ GO PER-KNOB. Revised:

- **E141 (max_per_session) + E148 (escalation_triggers)** — NOT a generic instruction. They ALREADY
  have hardcoded copies in pipeline.md (max "3" at pipeline.md:1075; a trigger table at pipeline.md:743
  that does NOT exactly match execution.yaml:158). This is a SINGLE-SOURCE/drift problem like E143.
  Remedy: pick ONE source — either make the pipeline.md text REFERENCE the YAML key, or explicitly mark
  the YAML advisory and keep pipeline.md canonical. Do NOT add a third general sentence.
- **E142 (release.skip_when)** — LLM-instruction is WRONG/risky: release is deterministic
  (pipeline.md:1003 just calls aid-release.sh; aid-release.sh:203 has its own changelog/version logic).
  An LLM-honored skip could skip a needed bump/tag. Remedy: **DELETE skip_when as stale config**, OR
  **implement it inside aid-release.sh**. PM picks. (Not an instruction.)
- **E149 (not_acceptable)** — bigger than "assess overlap": (i) there is a PRE-FILTER CONFIG DRIFT —
  aid-prefilter.sh reads `defaults/pre-filter-rules.yaml` (aid-prefilter.sh:16), NOT
  review-checkpoints.yaml; reconcile those two first. (ii) Real enforced overlap is ~1/7 (hardcoded
  secret in pre-filter-rules.yaml:22); 5/7 not_acceptable patterns (TODO/FIXME w/o issue, disabled
  security, skipped tests, forbidden paths, empty catch) are enforced by NOTHING. (iii) forbidden-paths
  belongs in the scope/verifier layer, NOT a regex pre-filter. Remedy: reconcile the two pre-filter
  files → route each not_acceptable pattern to regex-rule / scope-layer / advisory. Sizeable.
- **E157 (role_overrides)** — confirmed security decoration, PLUS: permissions.yaml has a blanket
  `Bash(*)` (permissions.yaml:32) that makes the per-role extra Bash perms REDUNDANT (not scoping) even
  conceptually. Remedy: implement real per-role enforcement in the permissions dual-write, OR degrade
  role_overrides to advisory AND remove the false "only release/security gets X" security claim.
- **E151 (global retry)** — DELETE, + a one-line comment in execution.yaml that per-gate `max_retries`
  is the only retry knob (avoids a doc hole + the max_attempts/max_retries naming confusion).
- **E161** — check `steps/step_{N}_frontend/output.md` for `^## Visual Anchoring`, conditional on
  `role == frontend && visual_refs length > 0` (hook: cmd_increment_step at aid-fsm.sh:1722). Doesn't
  prove "before code" timing but is a real stop with zero impact on non-frontend steps.
- **E165** — keep-as-convention BUT also FIX a stale claim: run-management.md:142 currently states the
  controller enforces the phase boundary automatically — it does NOT (no FSM gate). Qualify it as a
  manual-mode convention / `--auto` relies on escalation rules.
- **E143 / E151 / E171 / E106 / E121 / E140 / E175** — dispositions unchanged (single-source / delete /
  defer / inventory fixes).

**NEW finding (surfaced by verification): pre-filter config drift** — two pre-filter config files exist
(`review-checkpoints.yaml` referenced in docs vs `pre-filter-rules.yaml` actually read by
aid-prefilter.sh:16). Reconcile / single-source. Add to the work list.

**Net:** the "one instruction fixes many" shortcut is dead. Each knob is delete / single-source /
hard-wire(script) / security-fix / advisory-with-honest-label. This is clearly its own focused step.
