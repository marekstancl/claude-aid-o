---
audit: P041
artifact: fix-plan (PM-facing working tracker)
status: active
generated: 2026-06-01
purpose: plain-language map of WHAT we found, WHAT to fix, in WHAT order — the doc to work from
---

# P041 — Fix Plan (pracovní tracker)

Lidský přehled všech nálezů, seskupený do **8 témat**. U každé opravy je značka:
- **[HNED]** = jasná oprava, žádné tvoje rozhodnutí netřeba, můžu rovnou ukázat změnu.
- **[FEEDBACK]** = potřebuju od tebe rozhodnutí/směr, než to opravím.

Odškrtávej `[ ]` → `[x]`, jak postupujeme.

---

## ČÁST 1 — Co jsme našli (8 témat, lidsky)

**A. Dokumentace lže o kódu.** Některé soubory popisují, jak věci fungují, ale popisují fikci — neexistující příkazy, soubory, funkce. Nejhorší je `planner.md` (úplně vymyšlený). Tohle je nejnebezpečnější, protože agent tomu věří a udělá rozbitou věc.

**B. Funkční bugy.** Pět věcí je reálně rozbitých: `/aid-help` vždy vyhodnotí uživatele jako začátečníka, `/aid-stop` neumí obnovit běh, `/aid-research` čte špatnou konfiguraci, `/aid-init` při opakování přidává duplicitní git háčky, a jedna kontrola (CP4) nikdy nenajde svůj soubor kvůli překlepu v názvu.

**C. Hlavní pojistka (provenience) je rozbitá obousměrně.** Kontrola, která má bránit slití rozbitého kódu, se jednak spouští i na poctivých bězích (kvůli časování), jednak se tiše nespustí, když chybí nástroj `yq`. Musí se opravit oba směry najednou.

**D. Mechanický nepořádek.** Zastaralá data v hlavičkách všech souborů, starý název `state.yaml` místo `fsm-state.yaml` na 4 místech, version-stampy v nadpisech. Nudné, ale všudypřítomné.

**E. Rozpory v pravidlech.** Některé soubory si protiřečí samy v sobě nebo navzájem — auditor má tři různé bodovací stupnice, fronta používá jiné názvy polí než skript, dvě různé škály závažnosti.

**F. Funkce, co jsou popsané, ale neexistují.** `/aid-status` slibuje pause/resume/reorder, ale žádný kód to nedělá. Buď to postavit, nebo smazat z dokumentace (to je produktové rozhodnutí).

**G. Paměť: starý vs nový nástroj.** Plugin používá zakázaný `qdrant-brain` místo `vulcan-memory`. **Už ověřeno a rozhodnuto** (viz níže): přejít na vulcan-memory, konfigurovatelně.

**H. Poučení z reflexí se ztrácejí.** Pár konkrétních lekcí z minulých běhů nikam nedoputovalo (jedna nemá vůbec domov). Potřeba rozhodnout, kam je dát.

**I. Chybí řád (governance).** Není centrální seznam kontrol ani hlídač, který by hlídal soulad. Dva základy (skill-writing, command-writing) jsou napsané, ale ne nasazené. A přes polovinu kontrol ještě není zmapovaná.

---

## ČÁST 2 — Co je potřeba udělat (konkrétní opravy)

### Téma A — Dokumentace lže o kódu
- [x] **A1 [FEEDBACK]** Přepsat `planner.md` od základu proti reálnému skriptu (špatné CLI, špatný formát vstupu, vymyšlený algoritmus). *Potřebuju: jak detailní přepis chceš.* (AID-045)
- [x] **A2 [HNED]** Opravit `aid-run.md` vymyšlené věci: neexistující stav-přechod, špatný název větve, špatný merge cíl. (AID-053)
- [x] **A3 [HNED]** `aid-research.md` odkazuje na neexistující funkce + neexistující volby v menu → opravit/smazat. (AID-053)
- [x] **A4 [HNED]** `memory.md` popisuje pole, co v souboru nejsou → opravit. (AID-053)

### Téma B — Funkční bugy
- [x] **B1 [HNED]** `/aid-help` hledá `state.yaml` (neexistuje) → opravit na `fsm-state.yaml`. (AID-047)
- [x] **B2 [FEEDBACK]** `/aid-stop` ukládá postup tam, kam se při obnově nekouká → opravit. *Potřebuju: potvrdit, jak má resume reálně fungovat.* (AID-047)
- [x] **B3 [HNED]** `/aid-research` čte šablonu místo živé konfigurace → opravit cestu. (AID-047)
- [x] **B4 [HNED]** `/aid-init` přidává duplicitní git háčky při opakování → opravit popis značek. (AID-054)
- [x] **B5 [HNED]** CP4 kontrola hledá soubor pod špatným názvem → sjednotit název. (AID-055)

### Téma C — Provenience (hlavní pojistka)
- [x] **C1 [FEEDBACK]** Párový fix: (a) opravit časové okno, ať nepadá na poctivých bězích, (b) pak teprve zadrátovat blok, (c) zajistit, že nejde tiše vypnout chybějícím `yq`. *Potřebuju: tohle je designový fix, projdeme spolu.* (AID-046) — **DONE `921f3ca`** (2026-06-03): (a) interval-bracket logika (start..complete + tolerance) místo ±60s; navíc poctivý reframe `fabricated`→`unverifiable` (integrity signal, ne fraud); (c) fail-closed blocking podlaha při chybějícím yq; (NOVÉ, PM dodatek) nenegociovatelné anti-fabrikační pravidlo orchestrátorovi v pipeline.md (musí vyslat real verifiera, nesmí self-write/reuse/head-review). +2 regresní bats testy. Reálná obrana proti podvodu = instrukce+auditor+runtime, ne timing (poctivě zdokumentováno).

### Téma D — Mechanický úklid
- [x] **D1 [HNED]** Přejmenovat `state.yaml` → `fsm-state.yaml` napříč docs (legacy fallback nechat). (AID-048)
- [x] **D2 [HNED]** Smazat version-stampy z nadpisů + bumpnout zastaralá data. (AID-049)

### Téma E — Rozpory v pravidlech
- [x] **E1 [FEEDBACK]** `auditor.md` sjednotit tři bodovací stupnice na jednu + `/aid-audit` menu (8 vs 10 typů) + závažnosti. *Potřebuju: na kterou stupnici sjednotit.* (AID-056)
- [x] **E2 [HNED]** `/aid-status` sjednotit názvy polí fronty se skriptem. (AID-053) — **NO-OP ve Wave 2:** `{task_id}`→`{epic_id}` už opraveno ve Wave 1; pause/resume/reorder subcommandy už z aid-status.md odstraněny; Auto-pickup je reálná FSM funkce (pipeline.md §7 queue pickup, gated mode==auto); aid-status žádná pole natvrdo nedokumentuje a vše zobrazované (epic_id/priority/depends_on/status) je v zapsaném queue.yaml entry. Ověřeno 2026-06-03.
- [x] **E3 [HNED]** `brainstorming.md` sjednotit škálu závažnosti + opravit špatný adresář. (AID-053)

### Téma F — Neexistující funkce
- [x] **F1 [FEEDBACK]** `/aid-status` pause/resume/reorder + auto-pickup: **postavit, nebo smazat z dokumentace?** *Produktové rozhodnutí — tvoje volba.* (AID-057)

### Téma G — Paměť (ROZHODNUTO)
- [~] **G1 [HNED]** Přejít z `qdrant-brain` na `vulcan-memory`, konfigurovatelně přes `integrations.yaml mcp_tool`. Dotýká se: memory-mcp.md, project-scanner.md, aid-research.md, pipeline.md. (D-04 → vyřešeno)

### Téma H — Reflexe se ztrácejí
- [x] **H1 [FEEDBACK]** Doplnit ztracená poučení do správných souborů; vyřešit bezdomovecké poučení #21 (4 třídy curator-oprav nemají kam). *Potřebuju: potvrdit kam.* (AID-051) — **DONE** (84a3e53 role-cards homing #10/#15/#20 + 3cd25b1 #21 → gate-fixer fast-path). v2.28.0.

### Téma I — Řád / governance
- [x] **I1 [FEEDBACK]** Povýšit oba základy (skill-writing + command-writing) do pluginu — ale jen **spolu s hlídačem**, jako samostatný code-change s verzí + CHANGELOG. *Potřebuju: kdy do toho jít (je to větší krok).* (AID-050) — **DONE** (da76120: skilly povýšeny + aid-lint-skill.sh + test-skill-lint.sh s grandfather listem). v2.28.0.
- [x] **I2 [FEEDBACK]** Dopnit pokrytí: zmapovat zbylých ~91 kontrol + zauditovat 6 vynechaných souborů. *Potřebuju: jestli teď, nebo později.* (AID-052) — **DONE** (mapping E87–E177 v 16-coverage-completion.md; config-policy náprava dc64d9e + 460b86c; safe fixes 0920727). Zbytek → DEFERRED: MEM-AUDIT (memory prahy E154/E155), SKILL-RETROFIT (9 starých skillů).
- [~] **I3 [HNED]** Doladit memory/implementer drobnosti (un-sourced práh, model-blok). (AID-058)

---

## ČÁST 3 — Řád, jak to opravíme (4 vlny)

**Princip:** nejdřív to, co je rozbité a jasné (rychlé výhry), pak rozhodnutí. Mezi vlnami se zastavíme.

### 🟢 Vlna 1 — "jde hned" (mechanické + jasné bugy)
Tohle můžu připravit a ukázat ti změny rovnou, minimum tvého času:
**B1, B3, B4, B5** (jasné funkční bugy) · **A2, A3, A4** (vymyšlené odkazy) · **D1, D2** (úklid) · **E2, E3** (jasné rozpory) · **I3** (drobnosti).
→ *Výsledek: většina nálezů zmizí, systém přestane lhát na zjevných místech.*

### 🟡 Vlna 2 — "potřebuje tvoje rozhodnutí" (jedno po druhém)
Každý projdeme spolu, ty řekneš směr, já opravím:
**B2** (jak má fungovat resume) · **F1** (postavit/smazat neexistující funkce) · **E1** (na kterou stupnici sjednotit auditor) · **H1** (kam dát poučení) · **A1** (rozsah přepisu planner).

### 🟠 Vlna 3 — "designový fix" (delší, spolu)
**C1** (provenience obousměrně) · **G1** (migrace paměti na vulcan-memory).

### 🔴 Vlna 4 — "velký krok, code-change ceremonie"
**I1** (povýšit základy + postavit hlídač) · **I2** (dopnit pokrytí). Tohle už je verze + CHANGELOG + nasazení pluginu — samostatná akce, až bude zbytek hotový.

---

## Stav rozhodnutí
- **G (paměť):** ✅ rozhodnuto — vulcan-memory, config-driven.
- **Princip #5:** kandidát, na opravy nemá vliv (žádné rozhodnutí netřeba teď).
- Vše ostatní: viz [FEEDBACK] značky výše.

**Další krok:** Vlna 1 — připravím první balík změn k odsouhlasení.
