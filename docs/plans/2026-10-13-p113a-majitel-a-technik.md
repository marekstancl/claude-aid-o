# P113a: dva kritici (majitel a technik) s pamětí, smyčka 3 kola / 8,5

Zadání PM 13. 10. 2026 po Coufalu (7 kol, známky 7,2-8,4, audit 8,4/8,7/9,0, viditelně skoro beze změn).

## Proč
- Kritik byl jeden, technický. Jeho měřítko je kontrolní seznam lokálního webu. Výjimečnost, fotky ani hloubka obsahu se neměří, takže smyčka je nikdy nehoní.
- Každé kolo začínal bez paměti. Opakoval stejné výtky (doručení formuláře 4×, odborné pojmy 3×) a pokaždé přidal jiné drobnosti.
- Šum kritika (0,6 bodu na stejném webu) je větší než práh zlepšení (+0,3). „Zlepšení“ a „stagnace“ byly náhoda.
- Cena kol se neměřila. Kontrola textů a práce agenta v knize nákladů chyběly.

## Co se staví

### 1. Dvě role, každá s vlastním měřítkem
- **Majitel** (`owner`): majitel podniku s velkými očekáváními, který platí studiu.
  - Netechnický. Srovnává s konkurencí a ptá se: „Je to výjimečné? Přivede mi to zákazníky? Pochlubím se tím? Vypadá to dráž než konkurence? Prodávají texty? Jsou fotky dost dobré?“
  - Hodnotí jen to, co vidí: snímky na počítači a mobilu, texty a snímky konkurence (když jsou v podkladech).
- **Technik** (`tech`): to, co majitel neumí posoudit.
  - SEO: titulky, popisy, strukturovaná data, stránka na hlavní dotazy služba + místo, hloubka obsahu, vnitřní odkazy, sitemap.
  - Dále výkon, přístupnost, mobil, formulář a jeho doručení, bezpečnost hlaviček, připravenost ke spuštění.
  - Čte soubory webu, výsledky brány (`podklady/overenie.json`) a zadání SEO.
- **Každá role má své měřítko** (`critic/<typ>.owner.yaml`, `critic/<typ>.tech.yaml`) se stejným tvarem jako dnes: persona, kritéria s váhou a kotvami 4/6/8/10, readiness.
  - Zmrazení drží obě měřítka zvlášť, každé se svým SHA.
  - Dnešní `web-local.yaml` se rozdělí. Úkoly zákazníka (`task_test`), podklady ke spuštění a komponenty zůstávají společné pro typ.
- **„Nezávisle postavené“:** každé měřítko napíše jiný autor jen ze zadání role a z podkladů typu, bez mého návrhu:
  - majitele Codex,
  - technika nezávislý Claude s čistým kontextem.

  Já je jen zapojím a ověřím tvar. Obsah měním jen podle revize, kterou udělá vždy ten druhý autor.

### 2. Paměť
- Každá role dostane v balíku `podklady/historie.json` se **svými** minulými nálezy z této smyčky: kolo, text, kde, stav (fixed + důkaz, rejected + důvod, blocked + důvod, superseded).
- **Bez minulých známek**, aby se kritik nekotvil. Co měl na srdci, ví z nálezů.
- Pravidla v promptu:
  - fixed nález neopakuje, pokud nevidí regresi (pak to řekne a ukáže kde),
  - rejected nebo blocked neopakuje bez nového argumentu,
  - nálezy seřadí podle dopadu a první tři jsou „co by web posunulo nejvíc“.
- Audit (slepé hodnocení na konci) paměť **nedostává**. Je to nezávislá kontrola, ne další kolo.

### 3. Souběh
- V jednom kole běží obě role souběžně, každá ve vlastním adresáři a se svým balíkem.
- Výpadek jednoho poskytovatele řeší záskok za každou roli zvlášť (dnešní `ask` Codex → Claude).

### 4. Smyčka: nejvýš 3 kola oprav, cíl 8,5 u obou
- Kolo je přijaté, když **majitel ≥ 8,5 a technik ≥ 8,5** a žádné kritérium žádné role není pod 7. Tyto prahy drží jen kód, kritici je nevidí.
- Po přijatém kole přijde **audit**: 3 slepá hodnocení za každou roli, medián obou ≥ 8,5, nejnižší ≥ 8,0.
- Nejvýš **3 kola oprav**. Po třetím bez přijetí smyčka skončí stavem `stop:round_cap` a hlášením PM: nejlepší kolo, známky obou rolí a co brání.
- Pravidla „+0,3 zlepšení“ a „stagnace“ odpadají, jsou pod šumem kritika.

### 5. Cena a čas každého kola
- Kniha nákladů (`.aid-ui/costs.jsonl`) zapisuje i **kontrolu textů** (tokeny z logu Codexu, ceník jako u kritika).
- Zapisuje i **práci agenta**: řádek za kolo s tokeny ze session přepisu Claude Code mezi dvěma koly a ceníkovým ekvivalentem. Ceník Opus je odhad s uvedeným zdrojem.
- `status` ukazuje za každé kolo známky obou rolí, cenu (Codex, Claude záskok, agent, API) a nástěnný čas od začátku smyčky.
- Studio zobrazuje to samé. Hlášení PM po každém kole je jedna věta: kolo, majitel/technik, cena, čas.

## Co se nemění
- Kritik ani auditor nevidí práh. Hodnotí jen adresu se shodnou domovskou stránkou a vyžaduje snímky 1440 a 390.
- Placené API jen obrázky, strop 2 USD.
- Triáž, `fixed --evidence`, `reopen` a záznamy kol zůstávají. Nález nese roli (`r<n>-owner-<id>`, `r<n>-tech-<id>`).

## Hotovo když
1. `critic/web-local.owner.yaml` a `.tech.yaml` existují, napsali je dva různí autoři (záznam autora a revize u každého) a zmrazení drží obě se SHA.
2. `round` spustí obě role souběžně. Každá dostane jen svou historii nálezů, bez známek. Test ověří obsah obou balíků a že běžely souběžně.
3. `status`: přijato jen při obou ≥ 8,5 a žádném kritériu pod 7; po 3 kolech oprav `stop:round_cap`. Testy na všechny tři hrany.
4. Audit: 3 + 3 slepá hodnocení bez historie, přijetí podle mediánů. Test.
5. Kniha nákladů má řádky kontroly textů a agenta. `status` je sčítá po kolech. Test.
6. Coufal: jedno kolo s novými kritiky. PM dostane známky obou rolí, prvních 3 „největších posunů“ od každé a cenu kola.
7. Dokumentace: `steps/8-quality.md`, SKILL.md, CHANGELOG a nápověda studia popisují dvě role a nová pravidla.

## Revize zadání (Codex, 13. 10. 2026) - co přebírám
1. **Původ každého hodnocení:** run.json nese poskytovatele, model, SHA promptu a SHA balíku. Každé hodnocení i každá replika auditu běží v samostatném čistém volání (už dnes).
   - *Nepřebírám* povinnou rozmanitost modelů: Claude jako záskok za Codex je pravidlo PM.
2. **Konkurence je povinná pro majitele:** `.aid-ui/critic/competitors.json` obsahuje 3-5 místních konkurentů (název, URL, proč) a příkaz `competitors` k nim jednou na začátku smyčky nafotí domovskou stránku 1440/390 s datem. Bez toho se kolo nespustí.
3. **Majitel vidí celý web:** živou adresu a snímky všech stránek 1440/390 (jako dnes), k tomu snímky konkurence. Stavy formuláře hodnotí technik z brány.
4. **Kdo co hodnotí:** majitel viditelný účinek a přesvědčivost (dojem, výjimečnost, fotky, texty, cesta k objednání očima zákazníka). Technik měřitelnou funkčnost (SEO, výkon, přístupnost, mobil technicky, formulář, připravenost). Stejná vada od obou rolí se při triáži označí `duplicate --of` napříč rolemi.
5. **Kalibraci navíc nepřebírám:** přijaté kolo jen spustí audit a o přijetí rozhoduje audit (3 hodnocení za roli).
6. **Algoritmus auditu:** 3 platná hodnocení za roli. Medián celkové známky každé role ≥ 8,5, každé z 6 hodnocení ≥ 8,0, medián každého kritéria ≥ 7. Neplatná odpověď po záskoku znamená, že audit nerozhodl (exit 1, nic se nepřijme).
7. **Paměť:** nález má id a kritérium. Kritik smí opakovat vyřešený nález jen s polem `regression_of: <id>` a důkazem. Validátor odmítne `regression_of` na id, které v historii není. Přeformulované opakování chytá triáž (`duplicate`).
   - *Nepřebírám* otisky a automatické slučování: rozpoznat přeformulovaný nález umí jen model.
8. **Pořadí kola:** obě hodnocení platná → triáž všech nálezů → opravy s důkazem → brána (`gate-check`) → další kolo. Rozpor mezi rolemi řeší `blocked --conflict-with` (smyčka se zastaví pro PM). Brána má vždy přednost.
9. **Číslování:** kolo 1 je první hodnocení, kola 2-4 jsou kola oprav (nejvýš 3). Audit není kolo. Nejlepší kolo = nejvyšší `min(majitel, technik)`, pak nejvyšší nejnižší kritérium, pak průměr.
10. **Tvrdé brány už jsou:** `gate-check` před každým kolem a kritické otevřené body blokují zveřejnění. Mění se jen dokumentace.
11. **Autorství měřítek:** `critic/AUTHORS.yaml` u každého měřítka obsahuje autora (poskytovatel a model), datum, SHA zadání role, SHA výsledku a revizora. Zmrazení drží SHA obou rolí. Měřítko se během smyčky nemění (už dnes).
12. **Náklady:** každý řádek knihy nese `round` (číslo kola, nebo `build` mimo kolo), `purpose`, `attempt`, zdroj a datum ceníku a příznak odhadu. Čas kola je interval od startu kola k startu dalšího, ne součet souběžných úloh. Řádek agenta za kolo = tokeny přepisu v tomtéž intervalu: je to cena celé práce agenta mezi koly, včetně oprav.
