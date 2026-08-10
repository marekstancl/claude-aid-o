# AID v3 — Roadmap (Living Document)

**Last updated:** 2026-05-31 (post-P040)
**Purpose:** Krátký, čitelný overview kde jsme a co je next. Aktualizovat po každém shipnutí plánu.

---

## Recent ship history (poslední 5 releases)

| Version | Plan | Date | What |
|---|---|---|---|
| **v2.25.0** ⭐ | P040 Dispatch Lifecycle Enforcement Bundle | 2026-05-31 | aid-emit-dispatch.sh wrapper + reconciliation backstop + CP4 enforcement + --streamlined mode + state file unification. 4 new blocking checks. NR 8 hole RE-REPRODUCED at own ship (Step 7 timing slip) — fix is P041 territory. |
| v2.24.0 | NR 10-14 carry-over (3 quick wins) | 2026-05-31 | Parser fenced-block fix, permissions.yaml MCP refresh, FSM artifact templates |
| v2.23.0 | P039 Autonomous validator-assisted section review | 2026-05-31 | brainstorming.md Step 6/7 cross-section validation (Sonnet + Opus ground-truth re-grep) |
| v2.22.0-2.22.3 | Visual Companion user-invocable + hotfixes | 2026-05-13/14 | /visual-companion slash command + networking/read-first discovery |
| v2.21.0-2.21.1 | P038 Tiered Severity + Merge Blocking | 2026-05-13 | blocking/advisory registry + promote-check + AID_TEST_MODE guard hotfix |

---

## Active state (2026-05-31)

- **Plugin:** v2.25.0 (8 version files synced, GitHub release published)
- **Branch:** main (clean tree)
- **Inventory:** v1.12 — [AID-v3-architectural-inventory.md](AID-v3-architectural-inventory.md) (43 items: AID-001 to AID-043; P041 Phase-5 reserves AID-045..058 for audit fixes)
- **Principles:** [AID-v3-principles.md](AID-v3-principles.md) (#1 Detector without Enforcement is Decoration; #5 candidate Enforcement without Instruction is Cargo Cult — P041)
- **Audit:** [AID-audit-2026-06/](AID-audit-2026-06/) — P041 enforcement-vs-instruction + skill/command quality audit (DELIVERED 2026-06-01, fixes pending PM-GATE-C)
- **Reflections:** NR 1-17 [AID-v3-agents-outputs.md](AID-v3-agents-outputs.md) (newest-on-top)

---

## Next plans (priority order)

### 🟢 P041 — Enforcement-vs-Instruction Audit + Skill/Command Quality Audit (DELIVERED audit, fixes pending)

**Status:** audit DELIVERED 2026-06-01 (docs/plans/AID-audit-2026-06/). Scope expanded
from the original nonce-protocol idea (dropped at brainstorm Step 2) to a full
enforcement-vs-instruction alignment audit + quality audit of all skills/agents/commands.
**Anchor:** P041 brainstorm own 7× section-review drift → Principle #5 candidate
(Enforcement without Instruction is Cargo Cult).

What it produced (no code change — recommendations only):
- **Enforcement inventory** ~177 mechanisms (15-type taxonomy); **enforcement-registry.yaml** seed (194 rows).
- **Phase-2 mapping** (E01-E86): 81% ALIGNED, 14 GAP, 1 ORPHAN, 1 CONTRADICTORY, 3 UNREACHABLE.
- **Quality audit** of 15 skills/agents + 10 commands, each in two rounds + adversarial verify.
- **Two authoring standards** (provisional): skill-writing.md + command-writing.md.
- **Governance recommendation**: single registry + type→instruction-home convention + sync-guard (Principle #1 applied to the registry itself).

Headline fixes for follow-up (Phase-5 decision log 04-decisions.md):
- **planner.md FAIL** — fictional script contract (wrong CLI, wrong EPIC format, fabricated wave algorithm). Ground-up rewrite.
- **Provenance broken BOTH ways (P8)** — over-fires (±60s timing false-positive, the original NR 17 §4D fabricated case) AND under-fires (yq-less host silently disarms the blocking check). Pairs with the original "hard block fabricated" idea — but the block must not over-fire on honest runs nor be silently disarmable. This is the residue of the original P041 nonce idea.
- **3 command functional bugs** — aid-help Level detection always 0 (greps legacy state.yaml), aid-stop resume broken (saves to a file --resume never reads), aid-research reads template not live config.
- **qdrant-* vs vulcan-memory** mandate conflict across 3+ files — PM adjudication needed.
- **Coverage limits**: E87-E177 (~91 enforcements) unmapped; setup/ + visual-companion + design-sections unaudited.

The original "wire hard-block fabricated" task survives as ONE Phase-5 item, not the whole plan.

### 🟡 P042 — Plan-writing hardening bundle (AID-037 + AID-042 + AID-043)

**Effort:** ~6-7h bundled
**Anchor:** NR 16 (5 CP1 passes drift class) + NR 17 (plan.json decomposition + parser-safety)

Zabraňuje recurring "plán napsán špatně → parser to nestráví" pattern:
- **AID-037 PRE-FLIGHT validator** + sub-impl rules #9 (per-step outputs disjoint) + #10 (parser dry-run mock)
- **AID-042 cross-section consistency check #21** v plan-writing.md Completeness Gate (counts, naming-collision, classification stability)
- **AID-043 parser-safety pre-flight** — mock-run aid-plan-to-epic + aid-epic-to-json před plan-write completion

Po P042 by mělo být přibližně **nemožné** vyrobit plán s buď (a) sub-step naming jako 1a/1b/A/B, (b) pipe characters v Objective field, (c) per-step outputs all-identical, (d) cross-section count drift napříč 7+ místech. Tj. žádný další plán by neměl trpět 5 CP1 passes pattern.

### 🟢 P043 — AID-035 plan lifecycle closure

**Effort:** ~2h
**Anchor:** 2026-05-09 audit (39/40 archived plans stuck na `status: draft`) + P024 evidence

Done-advance hook auto-updates plan frontmatter `status: draft` → `done` po všech EPICs zavřených. Plus counter.yaml drift detection.

### 🟢 P044 — AID-040 AID-CONSUMER-COMPLETENESS deletion gate

**Effort:** ~3h
**Anchor:** NR 13 VULCAN P054 B-139 critical (DROP TABLE shipl, raw-SQL consumers missed, chytly až Curator+Auditor)

Při DROP TABLE / model deletion auto-inject completeness gate se 3 grepy (raw-SQL bez `grep -v test` / test refs / config refs). Unexplained hit blokuje krok.

### 🟢 P045 — AID-036 V0 cost estimator

**Effort:** ~5h
**Anchor:** P032 + P037 + P038 + P040 wallclock + token baseline accumulated

Pre-EPIC token/time/cost prediction. Per-role, per-model variant. Good-to-have, ne gating risk.

---

## Inventory summary (43 items)

| Range | Theme | Status |
|---|---|---|
| AID-001..030 | Original v3 redesign items (Sessions A/B/C/D/E) | Mix — most shipped via P031/P033/P035/P036 |
| AID-031..036 | Run management, plan format, lifecycle, cost estimator | P035/P036/P037/P038 shipped; AID-035, AID-036, AID-037 partial |
| AID-037 | Plan format gate (PRE-FLIGHT validator + check #20) | **PARTIAL** — check #20 shipped v2.20.2, PRE-FLIGHT validator pending (P042) |
| AID-038 | Verifier output provenance verification | Phase 1+2 deployed v2.21.0, Phase 3 deployed in P040 v2.25.0; **Phase 4 (hard-block fabricated) reframed by P041 audit → AID-046 paired fix: provenance over-fires AND under-fires, must fix both** |
| AID-039 | --streamlined execution mode | Shipped v2.25.0 (P040 Component D) |
| AID-040 | AID-CONSUMER-COMPLETENESS deletion gate | Pending (P044) |
| AID-041 | FSM-init state file unification | Shipped v2.25.0 (P040 Component E) |
| **AID-042** ⭐ NEW | Cross-section consistency invariant check (#21) | Pending (P042) — NR 16 anchor |
| **AID-043** ⭐ NEW | Parser-safety pre-flight (mock-run dry-run) | Pending (P042) — NR 16+17 anchor |

---

## How to use this doc

1. **Po každém shipnutí plánu:** update "Recent ship history" + "Active state" + odebrat shipnutý plán z "Next plans".
2. **Po každé reflexi (NR N):** zkontroluj jestli vznikly nové items v inventory; pokud ano, přidat řádek do "Inventory summary" + případně nový plán do "Next plans".
3. **Začátek nové session:** přečti tento dokument PRVNÍ. Pokud chceš víc detailu, pokračuj na referenced docs (inventory, principles, agents-outputs).
4. **Pokud něco nesedí mezi tímhle dokumentem a `AID-v3-architectural-inventory.md`:** inventory je single source of truth; tento doc je čitelný shortcut.

---

## Cross-references

- [AID-v3-architectural-inventory.md](AID-v3-architectural-inventory.md) — full 43-item registry s evidence chains
- [AID-v3-principles.md](AID-v3-principles.md) — binding principles (currently 1: Detector without Enforcement)
- [AID-v3-agents-outputs.md](AID-v3-agents-outputs.md) — NR 1-17 reflections (post-plan feedback empirical signal)
- [AID-post-plan-reflection-prompt.md](AID-post-plan-reflection-prompt.md) — verbatim prompt PM používá po dokončení plánu (2 modes: POST-EXECUTE + WRITE-ONLY)
- [BACKLOG.md](BACKLOG.md) — project-internal backlog (per-EPIC items, IMP-xxx)
- [brainstorming-v2-current.md](brainstorming-v2-current.md) — brainstorming skill reference
- `archive/` — 11 historical/superseded docs (REDESIGN-PLAN-v2, CRITICAL-ASSESSMENT, aid-setup-v2 plan/design, diagnostic findings, initial-plan, status-and-roadmap, etc.)
