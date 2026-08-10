# AID Brainstorm Deep mode — kritický review a konsolidovaný plán změn

**Datum:** 2026-06-20
**Revize:** 2026-06-21 — (1) doplněn Visual Companion + audit; (2) UI fidelita **vyčleněna**
do samostatné tratě [`UI-design-to-code-fidelity.md`](UI-design-to-code-fidelity.md);
(3) zapsán konsensus a směr pro Deep brainstorming jako základ pro plán.
**Autor:** Claude (na žádost Marka) — review + konsolidovaný konsensus z diskuze
(Claude + nezávislý agent + Marek)
**Předmět review:** [`acta/docs/plans/2026-06-08-aid-fast-brainstorm-mode-design.md`](../../../acta/docs/plans/2026-06-08-aid-fast-brainstorm-mode-design.md) (v0.4)
**Status:** Konsolidovaný review + **schválený směr** pro Deep profil — základ pro napsání
plánu. **NE** hotová executable AID specifikace. **Implementace odložena za Trať A (UI).**

> Tenhle dokument je kritická oponentura k návrhu Fast brainstorm módu a zároveň zápis
> konsensu, na kterém se shodli Claude, nezávislý agent a Marek. Vychází z reálné znalosti
> toho, co AID dnes má (classic `brainstorming.md` skill s validate-then-verify P039,
> section-review kritik, ground-truth re-verifikace) a z [`AID-v3-principles.md`](AID-v3-principles.md).
>
> **Pořadí prací (Markovo rozhodnutí):** UI fidelita ([Trať A](UI-design-to-code-fidelity.md))
> má přednost — bolí dnes a poslouží i Deep režimu. Deep brainstorming (Trať B) zůstává jako
> zrevidovaný návrh **bez implementace**, dokud Trať A nestojí.

---

## 0. Verdikt v jedné větě

Návrh popisuje reálně dobrou metodu, ale **prodává ji pod špatným jménem** a **jako fork**
toho, co by mělo být upgrade — a největší slabina (triáž jako tichý funnel rozhodnutí) je
zároveň největší **korektnostní riziko**, ne jen UX detail. UI fidelita, která byla původně
součástí tohoto dokumentu, je nově samostatná [Trať A](UI-design-to-code-fidelity.md).

---

## Konsensus a směr pro Deep brainstorming (LOCKED) — základ pro plán

Tahle sekce je **zápis dohody**, ze které se má psát executable plán. Body níže jsou
rozhodnuté (LOCKED); rationale ke každému je v očíslovaných sekcích §1–§9.

### K0. Pořadí: Trať A první

Deep brainstorming se **neimplementuje**, dokud nestojí [Trať A — UI fidelita](UI-design-to-code-fidelity.md).
Ne-UI části Deepu mohou vznikat nezávisle; **UI větev Deepu na Trati A závisí**. Tento dokument
zůstává jako zrevidovaný návrh.

### K1. Jeden flow, dva profily — ne druhý skill

- **NEvzniká** druhý brainstorming skill. Jeden flow, dva profily intenzity: `classic` / `deep`.
- Příkaz: `/aid-plan brainstorm --depth deep`. Auto-detekce smí Deep **doporučit**, kvůli
  nákladu jej **nesmí tiše spustit**.
- Sdílená validační kostra zůstává v jádře; Deep-only orchestrace, triáž a kontrakty jsou
  **oddělené reference/protokoly**, ne dalších několik set řádků v už nyní 507řádkovém
  `brainstorming.md`.
- **Spouštěč Deepu = „bohatý vstup × velký dosah chyby"**, ne úspora času. (Jméno „Fast" se ruší.)

### K2. Mechanicky persistovaný active-profile switch

Precedence tabulka (§2.1) **nestačí**. Profil musí být:
- explicitně zvolen na začátku běhu a uložen do run manifestu jako `brainstorm_profile: deep`;
- vložen do **každého** agent dispatch promptu;
- použit pro výběr konkrétního classic/deep protokolu.

Model jej **nesmí znovu odvozovat** u každého pravidla — jinak se konflikt MUST pravidel jen
přesune dovnitř jednoho skillu. Precedence matice z §2.1 platí jako obsah override vrstvy.

### K3. Artifact lifecycle — run namespace → atomická promoce

- Pracovní artefakty vznikají pod `.aid-o/work/brainstorm/{run_id}/`
  (`prebrief`, `validation`, `elaboration`, `triage`, registry).
- Launch/cost approval autorizuje **jen** vznik těchto run-scoped artefaktů.
- Schválené části se **atomicky promují** do `docs/plans/` / `.aid-o/plans/` až po **finálním
  approval**. Neodsouhlasený brainstorm nesmí průběžně měnit versioned dokumentaci.

### K4. Interakční rozpočet = součást kontraktu (tři brány)

1. **Launch gate** — v jednom turnu: potvrzení pochopení + doporučení Deep + odhad
   agentů/času/nákladu + souhlas se vznikem pracovních artefaktů.
2. **Decision gates** — jen `PM-NOW` a unresolved konflikty; batchované podle společného
   dopadu, vždy s doporučeným defaultem.
3. **Final gate** — jeden konsolidovaný review (rozhodnutí, defer, konflikty, kvalita,
   artefakty, přesný obsah k promoci).

Čtení kódu, hledání komponent, mockup mapping, oprava validator nálezů v mezích LOCKED a
technicky jednoznačné volby **nejsou** důvod ptát se PM.

### K5. Triáž s asymetrickým defaultem (nejdůležitější korektnostní bod)

Auditovatelnost je **až druhá obrana**. První je **asymetrické riziko**:
- **ADOPT jen při vysoké confidence** a bez produktového / UX / právního / bezpečnostního /
  obtížně vratného dopadu;
- **nízká confidence → PM-NOW** (jedna otázka navíc je levná; tichá ztráta rozhodnutí je drahá);
- pochybné položky **batchovat**, ne pokládat jednotlivě;
- měřit hlavně **false-ADOPT / decision-leak rate**, ne počet položek v logu;
- en-bloc potvrzení **vypisuje obsah ADOPT bucketu** (ne jen počet), s možností vyjmout ID;
- DEFER nevyžaduje potvrzení.

Klasifikace běží přes **typovaný decision registry** — každá položka má důvod/provenance.
Vazba na [`AID-v3-principles.md`](AID-v3-principles.md) #1: detektor (`open_for_pm`) bez
enforcementu (skutečné PM rozhodnutí) = dekorace; asymetrický default je ten enforcement.

### K6. Cross-block: prevence primárně, detekce doplňkově

- **Před elaborací** vytvořit **sdílený interface registry**, vložit jako **LOCKED** do všech bloků.
- Agent registry **nesmí tiše měnit** — jen vytvořit change proposal → schválení vytvoří
  **novou verzi registry** a označí dotčené bloky k přepočítání (registry není jednorázově zmražené).
- **Finální seam check** ověřuje **jen deklarované švy a invarianty** (API↔DB, events↔consumers),
  ne „přečti 16 dokumentů a najdi problém" (jeden agent nad vším je příliš slabý).

### K7. Execution adapter — Workflow je optimalizace, ne jediná cesta

- Workflow vyžaduje explicit opt-in → součást **launch gate** (cost approval).
- **Fallback** přes bounded Agent dispatche produkuje **stejná schémata, registry a soubory**.
- Fallback je **resumable přes step manifest** (`stage`, `status`, `input_hash`,
  `registry_version`, `output_file`, `output_validated`), zápisy **atomicky**. Přeskočit lze
  **jen** krok s validním schématem a **odpovídajícím hashem vstupů** — ne „soubor existuje".
- Když není dostupný ani bezpečný agent fan-out → Deep **skončí před elaborací** a nabídne
  classic; tiše degradovat ani změnit kontrakt nesmí.

### K8. n=1 — kalibrovat, ne zabetonovat

ACTA čísla (3 perspektivy, 14 bloků, 6 skupin) **nejsou defaulty**. Před defaultním zapnutím
forward-test (§9): malý greenfield (Deep se nedoporučí), velký backend/spec (méně interakcí bez
ztraceného rozhodnutí), konfliktní API↔DB (seam check zachytí), nedostupný Workflow (fallback
drží kontrakty). Měřit decision-leaks, rework po CP1, rozpory mezi bloky.

### Co plán musí vyrobit

1. Profil switch + run manifest + precedence override vrstva (K1, K2).
2. Run namespace + atomická promoce (K3).
3. Tři brány s interakčním rozpočtem (K4).
4. Typovaný decision registry + asymetrický triáž klasifikátor + metriku decision-leak (K5).
5. Interface registry s verzováním + bariérový seam check (K6).
6. Execution adapter (Workflow + resumable fallback se step manifestem) (K7).
7. Forward-test matici + telemetrii kvality (K8).
8. **Napojení na Trať A** pro UI bloky — Deep UI se povolí až po jejím dokončení (K0).

---

## 1. Jméno „Fast" je proti návrhu — přerámovat na Deep/Rigorous

**Nejdůležitější bod.** Celý dokument je psaný v jazyce **úspory** („zrychlená varianta",
„šetří pozornost", „úspora času"). Ale reálná hodnota, kterou ACTA běh naměřil, je **kvalita**:
adversariální validace + consensus chytily **83 oprav + 3 blokery**, které by classic
single-pass přehlédl. To není rychlý mód — je to **důkladný mód**, který shodou okolností
spotřebuje míň PM pozornosti.

Proč na tom záleží prakticky:
- Pojmenováno „Fast" → PM po tom sáhne kvůli času → překvapí ho **3M tokenů / 37 min / 28 agentů** na jeden plán.
- Pojmenováno „Deep" / „Rigorous" → PM po tom sáhne, **když je vysoký dosah chyby** (greenfield
  architektura, celé MVP, něco těžko zpětně měnitelného). To je správný spouštěč.

**Akce:**
- Přejmenovat profil (`/aid-plan brainstorm --depth deep`, ne `fast`).
- Přepsat rozhodovací pravidlo §3 zdrojového dokumentu: dnes stojí na „chci ušetřit čas".
  Má stát na **„bohatý vstup × velký dosah chyby"**. Časová úspora je vedlejší efekt, ne kritérium.

---

## 2. Fork vs. upgrade — architektonická vidlice (rozhodnout PRVNÍ)

Návrh staví Fast jako **druhou větev** vedle classic. Ale to, co je na Fastu reálně lepší —
adversariální validace, consensus jako nezávislý editor, verify-hardest-claim, LOCKED inject,
triáž — **není inherentně „rychlé".** Všechno by zlepšilo i classic brainstorming.

A classic už **má jádro téže filozofie**: validate-then-verify (P039), section-review kritik,
ground-truth re-verifikace každého claimu ([`brainstorming.md`](../../plugins/aid-orchestrator/skills/brainstorming.md)).
Fast „consensus = nezávislý editor" je **doslova ten samý mechanismus**, jen škálovaný přes
Workflow na paralelní bloky místo sekvenčních sekcí.

> **Závěr: Fast není jiná filozofie. Je to classic validation filozofie aplikovaná ve velkém
> přes orchestraci.**

To silně argumentuje pro **jeden brainstorming skill, jednu sdílenou validační kostru, dva
režimy intenzity** (sekvenční pro malý scope / paralelní orchestrace pro velký) — místo dvou
paralelních codepaths, které za půl roku rozjedou drift. Fork dvou skillů je údržbová zátěž,
kterou jednočlenný tým neunese.

**Doporučené rozhodnutí:** nedělat druhý brainstorming skill. Použít jeden flow a explicitní
profil intenzity, ideálně `/aid-plan brainstorm --depth deep`. Auto-detekce může Deep
**doporučit**, ale kvůli nákladu jej nesmí sama tiše spustit. Sdílené principy zůstanou v
jádru; Deep-only orchestrace, triáž a kontrakty mají být oddělené reference/protokoly, ne
dalších několik set řádků v už nyní 507řádkovém `brainstorming.md`.

### 2.1 Deep profil potřebuje explicitní precedence matici

Deep nelze přidat jen jako nový flag pod současná `MUST` pravidla. Jeho metoda je v přímém
konfliktu minimálně s „one question at a time", „2–3 approaches always", section-by-section PM
approval, zákazem zápisu před Step 7 a pravidlem „brainstorming only creates a new plan file".
Bez explicitních override pravidel bude model náhodně poslouchat classic nebo Deep větev.

| Sdílený princip | Classic profil | Deep override |
|---|---|---|
| Rozhodovací otázky | Jedna otázka v jednom turnu | Jeden koherentní decision block; závislá rozhodnutí lze batchovat, nesouvisející ne |
| Varianty | 2–3 varianty vždy | Varianty jen pro skutečná rozhodnutí; ověřený technický fakt se nepřevléká za falešnou volbu |
| Validace sekcí | Validator → PM po každé sekci | Elaborate → consensus automaticky; PM pouze při `PM-NOW`, konfliktu nebo finálním schválení |
| Zápis artefaktů | Až po explicitním Step 7 approval | Launch/cost approval autorizuje pouze run-scoped pracovní artefakty; finální dokumenty až po final approval |
| Povolené soubory | Jeden nový plan file | Jen nový run namespace; žádné úpravy produktového kódu ani cizích plánů |

Pracovní artefakty mají vznikat pod například
`.aid-o/work/brainstorm/{run_id}/` (`prebrief`, `validation`, `elaboration`, `triage`, registry).
Až po finálním approval se schválené části atomicky promují do cílových `docs/plans/` a
`.aid-o/plans/`. Tím zůstává zachována možnost multi-agent práce bez toho, aby neodsouhlasený
brainstorm průběžně měnil versioned dokumentaci.

### 2.2 Interakční rozpočet musí být součást kontraktu

Pokud je cílem méně a přesnějších interakcí, nestačí to uvést jako benefit. Deep profil má mít
explicitní rozpočet a důvod každého PM gate:

1. **Launch gate:** v jednom turnu spojit potvrzení pochopení, doporučení Deep profilu, odhad
   agentů/času/nákladu a souhlas se vznikem pracovních artefaktů.
2. **Decision gates:** jen `PM-NOW` a unresolved konflikty; seskupovat podle společného dopadu a
   vždy ukázat doporučený default. ADOPT se zobrazí jako auditovatelný přehled s možností
   vyjmout konkrétní ID, DEFER nevyžaduje potvrzení.
3. **Final gate:** jeden konsolidovaný review — rozhodnutí, defer položky, konflikty, kvalita,
   artefakty a přesný obsah, který bude promován.

Čtení kódu, hledání komponent, mockup mapping, oprava validator nálezů v mezích LOCKED rozhodnutí
a technicky jednoznačné volby nejsou důvod ptát se PM. Pokud triáž vyrobí příliš mnoho `PM-NOW`
(prahová hodnota se má kalibrovat, ne opsat z ACTA), Deep transparentně doporučí přechod do
classic dialogu místo maskování nezralého scope.

---

## 3. Triáž je zlato i mina — a je to porušení vlastního principu P026

Nejcennější empirický nález je schovaný v §F zdrojového dokumentu: consensus revieweři jsou
konzervativní, vyhodili **64 `open_for_pm`, ale jen 14 bylo skutečných**. Bez triáže Fast selže.
To je load-bearing zjištění.

Ale je to **korektnostní riziko, ne jen UX**:
- Triáž ADOPT/DEFER/PM-NOW dělal hlavní kontext **ručně**, heuristika není specifikovaná.
- En-bloc potvrzení ADOPT bucketu je **měkké**.
- Když triáž špatně zařadí jedno genuine byznys rozhodnutí do ADOPT, **PM o tom rozhodnutí
  tiše přijde** — odklepne ho en-bloc, aniž by ho viděl jako rozhodnutí.

**Napojení na vlastní architekturu:** [`AID-v3-principles.md`](AID-v3-principles.md) #1 —
*Detector without Enforcement is Decoration*, kotvený na incidentu P026 (WAN, 2026-05-13).
Consensus reviewer **detekuje**, že rozhodnutí patří PM (`open_for_pm`). Enforcement, že to PM
reálně rozhodne, je triáž + en-bloc. Pokud ADOPT bucket auto-akceptuje, **je to přesně P026
vzor**: funkční detektor, jehož enforcement se obešel. Vlastní principy to zakazují.

**Mitigace (povýšit z „open" na „must-solve"):**
- En-bloc potvrzení **musí vypsat, co adoptuje** (ne jen počet).
- ADOPT klasifikace musí být **auditovatelná** (durable záznam s odůvodněním, proč ADOPT a ne PM-NOW).
- Triáž heuristiku ze §10 zdroje formálně specifikovat (kdy je rozhodnutí „technicky správné"
  vs „byznys/preference") — ideálně jako samostatný klasifikační krok s definovaným kontraktem.

---

## 4. Cross-block konzistence není „open bod", je to díra

§10 zdroje to má jako otevřenou otázku, ale je to **fundamentální failure mode paralelní
orchestrace**. `pipeline()` bez bariéry → blok „API" a blok „db schema" se elaborují nezávisle
a **můžou si protiřečit** (API cituje sloupec, který schema pojmenuje jinak). Consensus stage
ověřuje každý blok proti LOCKED, ale **ne proti sourozeneckým elaboracím**. Na ACTA buď štěstí,
nebo to zalepil hlavní kontext ručně.

Klasické „lokálně konzistentní, globálně rozbité". Pro produkční skill potřebuje odpověď, ne
„k doladění":
- **Buď** finální cross-block index pass (bariéra po pipeline — jeden agent čte všech N souborů,
  hledá rozpory rozhraní),
- **nebo** sdílené interface kontrakty injektnuté jako LOCKED do všech bloků.

Řešit před shipnutím.

---

## 5. Workflow nemusí být dostupný — a návrh na něm stojí

Fáze E **tvrdě závisí** na `Workflow` tool. Jenže Workflow vyžaduje **explicitní opt-in**
(ultracode, nebo to user výslovně vyžádá) — není to nástroj, který hlavní kontext jen tak
zavolá. Dokument s tím nepočítá. (Marek to sám flagnul: „orchestrátor by měl využívat workflow
**pokud je dostupný**".)

**Skill musí ošetřit dvě věci:**
1. **Kdo Workflow spustí?** Skill musí PM-ovi říct „tohle rozjede orchestraci ~28 agentů, ~$X,
   ~40 min — pustit?" a tím získat opt-in. To je zároveň **cost gate**, který v §3 chybí.
2. **Co když Workflow není k dispozici?** Fáze E je srdce hodnoty. Potřebuje definovaný
   degradation path. Doporučený design je execution adapter: Workflow je optimalizace, fallback
   používá běžné Agent dispatches ve bounded dávkách a produkuje stejná vstupní/výstupní schémata,
   registry a soubory. Pokud není dostupný ani bezpečný agent fan-out, Deep se ukončí před
   elaborací a nabídne classic; **tiše degradovat nebo změnit kontrakt nesmí.**

---

## 6. UI fidelita — vyčleněna do samostatné tratě

> **Tato sekce se přesunula.** Celý UI design-to-code řetězec (audit současného stavu, krux
> „baseline z běžící stránky", scoped fidelity, UI Change Contract, role, mechanická kontrola,
> worked examples, změnová plocha) je nově samostatný dokument:
> **[`UI-design-to-code-fidelity.md`](UI-design-to-code-fidelity.md) (Trať A).**

Důvod vyčlenění: UI mezery jsou v `implementer.md` / `role-cards.md` / `pipeline.md` / FSM /
`plan.schema.json` / `/aid-do` — **ani jedna není Deep-specifická**. UI pravidla musí platit
napříč (`/aid-do`, běžný plán, jednou i Deep), a bolí **dnes**. Proto Trať A běží **samostatně
a dřív**.

**Vztah k Deepu:** Deep UI větev **závisí** na Trati A (viz K0). Ne-UI Deep běží nezávisle.
Když Deep elaboruje UI blok, použije UI Change Contract a verifikaci z Tratě A — nezavádí
vlastní paralelní mechaniku.

---

## 7. Co je vyloženě dobré (zachovat)

- **Verify-hardest-claim** — výborný a v classicu podceněný princip. Port konflikt byl reálný. Přenést všude.
- **LOCKED inject verbatim** — správný pattern proti re-litigaci zafixovaných rozhodnutí.
- **Durable soubory > velký návrat** — správná workflow hygiena (agenti píšou do `elaboration/*.md`).
- **Block-pass batch** — legitimní attention-saver bez ztráty kvality.
- **§12 pipeline friction** (git init, parser `|`, docs-writer step-id) — čisté zlato pro handoff
  fázi, reálné bugy ne hypotézy.
- **Sebereflexe dokumentu** — že přiznává 3 blokery a 6 re-runů — nejlepší vlastnost dokumentu.

---

## 8. `docs-writer` bug už není otevřený blocker

Původní ACTA nález byl platný, ale v aktuálním checkoutu je opraven: [`aid-epic-to-json.sh`](../../plugins/aid-orchestrator/scripts/aid-epic-to-json.sh)
sanitizuje roli přes `${step_roles[$i]//-/_}` a regresní test očekává
`step_2_docs_writer` při zachování role `docs-writer`. V plánu jej ponechat jen jako vyřešený
historický nález a **nezařazovat do nové implementační práce**.

---

## 9. Upřímný disclaimer, který v návrhu chybí: n=1

Je to **jeden běh**, na ACTA, což byl greenfield s neobvykle bohatým vstupem (spec + účetní
doména + eco infra). Čísla jako „3 review perspektivy", „14 bloků", „6 tematických skupin" jsou
**ACTA-specifická**, ne ověřené defaulty. Skill je nesmí zabetonovat jako pravidla — tvar má
vyplývat ze scope. Jinak si do skillu vpašuješ ACTA jako šablonu vesmíru. Dokument by měl říct
„kalibrováno na jednom běhu, dolaď přes víc běhů".

Před defaultním zapnutím je potřeba forward-test minimálně na těchto scénářích:

1. malý greenfield bez bohatého vstupu — Deep se nedoporučí;
2. velký backend/spec — Deep sníží PM interakce bez ztraceného byznys rozhodnutí;
3. existující UI s malou vizuální deltou — nedotčené regiony zůstanou 1:1;
4. konfliktní API ↔ DB elaborace — cross-block pass rozpor zachytí;
5. nedostupný Workflow — fallback zachová kontrakty a jasně vykáže náklad/degradaci.

Měřit nejen počet otázek, ale i počet decision leaks, rework po CP1, rozpory mezi bloky,
vizuální mismatch a collateral změny existujícího UI.

---

## 10. Pořadí prací — dvě tratě

Práce je rozdělená na dvě samostatně shippovatelné tratě. **Trať A běží první** (Markovo
rozhodnutí). Detail jednotlivých Deep kroků je v sekci „Co plán musí vyrobit" výše (K1–K8).

| Trať | Co | Stav | Dokument |
|------|-----|------|----------|
| **A — UI fidelita** | Řetězec návrh UI → implementace → vizuální ověření; platí napříč `/aid-do`, plán, Deep | **Nejdřív** — bolí dnes | [`UI-design-to-code-fidelity.md`](UI-design-to-code-fidelity.md) |
| **B — Deep brainstorming** | Profil, triáž, registry, execution adapter | **Po Trati A** — zatím jen zrevidovaný návrh | tento dokument |

### Trať B (Deep) — exit conditions kroků

| # | Akce (→ K-bod) | Výstup / exit condition |
|---|---|---|
| 1 | Přejmenovat na **Deep**, jeden skill s `--depth deep` (K1) | Command syntax + pravidlo „bohatý vstup × dosah chyby"; auto-detekce jen doporučuje |
| 2 | Sdílené jádro + Deep override vrstva + active-profile switch (K1, K2) | Žádný druhý codepath; `brainstorm_profile` v run manifestu a v každém dispatchi |
| 3 | Run namespace + atomická promoce (K3) | Neschválené výstupy zůstávají v `.aid-o/work/brainstorm/{run_id}/` |
| 4 | Tři brány + interakční rozpočet (K4) | Launch / decision / final gate; PM jen na `PM-NOW` a konflikty |
| 5 | Typovaný decision registry + asymetrická triáž + decision-leak metrika (K5) | ADOPT jen high-confidence bez produktového dopadu; en-bloc vypisuje obsah |
| 6 | Interface registry s verzováním + bariérový seam check (K6) | Sdílené kontrakty jako LOCKED; finální check jen na deklarovaných švech |
| 7 | Execution adapter: Workflow + resumable fallback (K7) | Oba pathy stejná schémata; fallback skip jen dle hashe vstupů, ne existence souboru |
| 8 | Forward-test matice + telemetrie kvality (K8) | Scénáře z §9 projdou; měří se decision-leaks, konflikty, rework |
| 9 | Rollout feature-gated, auto jen doporučuje | Deep se nikdy nespustí tiše; defaulty se kalibrují po více bězích |

### Ship blockers — Trať B

Produkční Deep profil není připravený, dokud nejsou současně uzavřeny:

- auditovatelná triáž s asymetrickým defaultem (K5);
- profilová precedence + mechanický switch + lifecycle artefaktů (K2, K3);
- cross-block konzistence (interface registry + seam check) (K6);
- Workflow cost/availability contract + resumable fallback (K7);
- napojení UI bloků na hotovou **Trať A** (K0);
- testy na více než jednom ACTA-like běhu (K8).

Jméno, command routing a počet agentů jsou až druhotné.

---

*Zdrojový ACTA návrh zůstává deskriptivním záznamem metody. Tento dokument je jeho konsolidovaný
kritický review **a zápis konsensu** (Claude + nezávislý agent + Marek); detailní executable AID
plán pro Trať B má vzniknout až po dokončení [Tratě A](UI-design-to-code-fidelity.md).*
