---
audit: P041
artifact: Wave 2 plan (PM-facing) — what remains after v2.26.0 + v2.27.0
status: active
generated: 2026-06-02
purpose: plain-language map of remaining P041 work so PM understands the plan
---

# P041 — Co zbývá po v2.26.0 + v2.27.0 (podklad pro Vlnu 2)

## Už hotové a zalité do main (lokálně, nepushnuto)

**v2.26.0 (Vlna 1):**
- aid-research + knowledge + Context7 odstraněny (AID-047 částečně, archiv obnovitelný)
- aid-help level detection (state→fsm-state) — AID-047
- aid-init pre-push hook marker — AID-054
- CP4 curator-validation filename — AID-055
- implementer model pointer — AID-058(b)
- brainstorming glob + severity — AID-053 částečně
- version-stampy + zastaralá data — AID-049

**v2.27.0:**
- FSM state file sjednocen na `fsm-state.yaml` napříč vším — AID-048 (D-05) HOTOVO
- /aid-stop + /aid-run --resume na reálná pole — AID-047 (B2) HOTOVO
- queue pause/resume/reorder odstraněny — AID-057 (F1) HOTOVO

→ Z 8 témat fix-planu jsou **D (úklid), F (neexistující funkce), velká část B (bugy)** hotové.

---

## Co zbývá — 4 skupiny

### Skupina 1 — Rychlé pravdy o kódu (nízké riziko, [HNED])
Dokumentace pořád na pár místech popisuje fikci. Agent tomu věří → udělá rozbitou věc.

1. **aid-run.md — vymyšlené věci** (AID-053): neexistující stav-přechod `DONE→ERROR`,
   špatný název větve (per-step vs single `task/{epic_id}/main`), špatný merge cíl
   `merge epic/{id}`, paralelní režim popsaný jako aktivní (přitom je vypnutý).
   → opatrný průchod, ověřit proti reálnému FSM.
2. **memory.md — pole co neexistují** (AID-053/AID-058): `cat fsm-state.yaml` cituje pole,
   která tam nejsou. (Jméno souboru už opraveno migrací; zbývá ověřit pole.)
3. **task → epic terminologie** (NOVÉ, dnešní): `/aid-run`, `/aid-status`, `/aid-help` říkají
   uživateli `<task-id>`, ale systém klíčuje vše na `epic_id` (ID jsou E-NNN). Sjednotit
   CLI na `<epic-id>` / `--epic`. `/aid-do` nechat „task" (tam je to věcně správně).
   Složku `.aid-o/tasks/` zatím neřešit (cesta = větší riziko).

### Skupina 2 — Rozhodnutí o pravidlech ([FEEDBACK] — potřebuju směr)
4. **planner.md — přepsat od základu** (AID-045, FAIL): nejnebezpečnější soubor. Popisuje
   úplně vymyšlený skript-kontrakt (špatné CLI, špatný formát EPIC tabulky, vymyšlený wave
   algoritmus; přesná je jen Kahnova detekce cyklů). → **rozhodnutí: jak detailní přepis.**
5. **auditor.md — tři bodovací stupnice** (AID-056): koexistují mrtvá `10/5/2/1`, živá
   `-15/-10/-5/-2`, Memory-Health `0-20×5`; TODO handling si protiřečí s execution.yaml
   `max_todo_count:0`; aid-audit menu má 8 typů vs auditor 10 kategorií + jiná slovní závažnost.
   → **rozhodnutí: na kterou stupnici sjednotit.**
6. **Reflexe se ztrácejí** (AID-051): pár poučení z minulých běhů nikam nedoputovalo; jedno
   (#21, 4 třídy curator-oprav) nemá vůbec domov. → **rozhodnutí: kam je dát.**

### Skupina 3 — Designové / větší (projdeme spolu)
7. **Provenience obousměrně** (AID-046, PŮVODNÍ P041 úkol): hlavní pojistka proti slití
   rozbitého kódu je rozbitá dvakrát — (a) padá i na poctivých bězích kvůli ±60s časování,
   (b) tiše se nespustí když chybí `yq` → tiché self-merge. Párový fix: opravit okno PŘED
   zadrátováním bloku + zajistit, že nejde vypnout chybějícím yq. → designový, projdeme spolu.
8. **qdrant → vulcan-memory** (D-04, ROZHODNUTO): plugin používá zakázaný qdrant-brain.
   Přejít na vulcan-memory, konfigurovatelně přes integrations.yaml. Dotýká se memory-mcp.md,
   project-scanner.md, pipeline.md. → rozhodnuto, jen udělat.
9. **memory-mcp drobnost** (AID-058a): hard-coded práh `0.85` je un-sourced pro `memory`
   sekci (0.85 v yaml je pod `knowledge`). → malá oprava.

### Skupina 4 — Infrastruktura (samostatný code-change s verzí + CHANGELOG)
10. **Povýšit skill-writing.md + command-writing.md + postavit hlídač** (AID-050): dva
    standardy jsou napsané (provisional), ale nenasazené. Povýšit do pluginu JEN spolu
    s governance hlídačem — jinak je to Principle-#1 dekorace. → větší krok, vlastní verze.
11. **Dopnit pokrytí** (AID-052): zmapovat zbylých ~91 kontrol (E87–E177) + zauditovat
    6 vynechaných souborů (setup/*, visual-companion, design-sections).
12. **Opravit 19 baseline padajících testů** (test-fsm.sh, test-integration-phase1.sh aj.) —
    červené na main už dlouho, nesouvisí s migrací; vlastní úklid.

---

## Otevřená produktová rozhodnutí (PM-GATE-C)
- **Principle #5** („Enforcement without Instruction is Cargo Cult") — povýšit na závazný, nebo
  nechat jako kandidát? (Neblokuje opravy.)
- **Pořadí Vlny 2** — čím začít? Návrh: Skupina 1 (rychlé, nízké riziko) → Skupina 2 (rozhodnutí)
  → Skupina 3 (design) → Skupina 4 (infra). Provenience (#7) je ale původní úkol P041 — možná
  napřed.

---

## DEFERRED — to investigate (recorded 2026-06-03, not yet started)

### MEM-AUDIT — Memory subsystem audit (Principle #1 suspicion)
PM is convinced memory is **written but not read/used** by agents (write-without-read = decoration).
Full audit needed (auditor-overhaul style):
- Write path: `memory_writes` (agent-protocol, REQUIRED) — actually written?
- Read path: `memory_context` injection (pipeline §4) — actually injected AND consumed by the agent?
- Closed loop: write→store→inject→read→use, or is half dead?
- Folds in: G1 qdrant→vulcan migration, AID-058a memory-mcp 0.85 threshold, the "agents read
  architecture from memory" project.
- **Gates** whether vulcan-memory is a viable reflection sink.

### REFLECT-WIRE — Automatic post-EPIC reflection (refined design, blocked on MEM-AUDIT)
Manual prompt (`AID-post-plan-reflection-prompt.md`) + PM's manual output stay AS-IS.
New automatic path:
- **Per-EPIC slice** by curator (fresh data) → appends to accumulating local `reflection.md`.
- **Per-plan synthesis** at the per-plan checkpoint (light pass over slices).
- **Output sinks (config-driven, fork-friendly):**
  - Local `.aid-o/work/reflection.md` — always (enforcement artifact).
  - **Central `.md` digest** — `integrations.yaml → reflection.central_digest_path` (opt-in);
    PM's reliable human-readable channel for improving AID. Fork leaves unset → local only.
  - vulcan-memory push (`type=reflection`) — opt-in, **only if MEM-AUDIT confirms read path lives**.
- **Enforcement (FSM, not auditor — timing):** `done-advance` requires the per-EPIC slice before
  release; plan-level gate requires the assembled synthesis before next plan. (Auditor F.6 dropped
  — it runs before the reflection exists.)

### PIPELINE-§7-CP4 — RESOLVED 2026-06-03 (CP4 reordered after apply + S/M/L extension per PM)
pipeline.md §7 step 7 says "CP4 verifier on curator-proposed CHANGES; if FAIL → revert curator
changes" — but under the confirmed **propose-only** curator, the curator makes no changes, and CP4
(step 7) is positioned before the gate-fixer apply (step 8). So the CP4 wording is a leftover from
the pre-propose-only model. Align pipeline §7: CP4 reviews the gate-fixer's APPLIED changes (after
step 8), or reword to match propose-only. Curator.md now delegates the exact sequence to §7 rather
than asserting it.
