# P096 krok 11 — akceptační běh: najde nové čtení celku to, co našel auditor?

Založeno 20. 9. 2026 PŘED prvním placeným spuštěním.

## Strop a rozsah (psáno před během)

- **Strop: 25 USD** (z plánu). Očekávaná útrata: do 10 USD.
- **Co se přehrává:** osm skutečných nálezů zrušeného auditora konce plánu
  z WAN a ACTA (`plugins/aid-orchestrator/scripts/tests/fixtures/plan-final/sample.json`),
  každý na commitu, na kterém ho auditor udělal. Čtyři různé kandidáty,
  tedy čtyři kola nového čtení celku (cp7).
- **Kdo čte:** šest spuštění místo dvanácti, kvůli ceně. Tři role najednou
  jen u nejbohatšího kola (WAN P101, kandidát f06c2f0d: nálezy S3, S4, S8),
  jinde jen role, které nález podle svých otázek patří: `final_claims`
  (Sonnet) u WAN P082 a WAN P101 f4b3e539, `final_criteria` (Opus) u ACTA P024.
- **Codex** je přes limit do 21. 9., roli `final_generalist` proto čte zástup
  Claude Sonnet, jak to dělá i ostrý provoz.
- **Pravidlo úspěchu (nemění se):** potvrzeno aspoň 6 z 8 a žádná role nemá
  víc zamítnutých nálezů než přijatých. Když to nevyjde, mazání (část 2 plánu)
  nezačne a upravuje se balík nebo otázky rolí, ne pravidlo.
- Zdrojové repozitáře se nemění: kandidát se rozbalí do `git clone --shared`
  v pracovním adresáři.

## Výsledek (20. 9. 2026)

**7 z 8 potvrzeno, pravidlo splněno.** Záznam shod:
`plugins/aid-orchestrator/scripts/tests/fixtures/plan-final/acceptance.json`,
odpovědi revizorů ve složce `answers/` vedle něj. Přehrání bez modelu
(`test-step-review-acceptance.sh final stub`) výsledek reprodukuje.

| Nález | Projekt, kandidát | Výsledek | Kdo |
|---|---|---|---|
| S1 vypnuté testy v CI u plánu jen na dokumentaci | WAN P082 | nalezen, blokující | čtení celého diffu |
| S2 viditelná změna bez zápisu v CHANGELOGu | WAN P101 f4b3e539 | nalezen | čtení tvrzení |
| S3 CHANGELOG tvrdí chování, které ještě nenastává | WAN P101 f06c2f0d | nalezen, blokující | čtení tvrzení |
| S4 závazné pořadí nasazení žije jen v backlogu | WAN P101 f06c2f0d | nalezen stejným nálezem jako S3 | čtení tvrzení |
| S5 tři kritéria na živých datech bez důkazu | ACTA P024 | nalezen, blokující | čtení kritérií |
| S6 kritérium dokumentace bez důkazu | ACTA P024 | nalezen, blokující | čtení kritérií |
| S7 důkazy pořízené na starším commitu | WAN P082 | nemůže nastat | mechanismus: zmrazení znovu pustí vše, čemu se pohnuly vstupy |
| S8 dvě mezery nového testového hlídače | WAN P101 f06c2f0d | **nenalezen** žádnou ze tří rolí | - |

Žádná role nemá víc zamítnutých nálezů než přijatých (zamítnut jeden ze 22).

### Co nové čtení našlo navíc
Brána porovnání plánu se zapisuje jako zelená, i když část kritérií přeskočí
(ACTA 4 z 9, WAN P082 2 z 9 bez řádku výsledku). Kritéria „testy zelené"
prokázaná bránou, která toleruje 10 pádů. Zastaralý záznam v backlogu, který
odporuje kódu ve stejném diffu.

### Odchylky od rozsahu zapsaného před během (poctivě)
1. **První průchod pravidlo NESPLNIL (5 z 8).** Revizor S3+S4 našel, ale kontrola
   formy nález zahodila: k odkazům na řádky připsal poznámky v závorkách. Podle
   předem zapsaného postupu se upravilo zadání, ne pravidlo: do textu, který
   dostává každý revizor, přibyla věta „jen odkazy, co řádek ukazuje patří do
   tvrzení". Nový revizor načisto s novým zněním: nález přijat.
2. **WAN P082 četly nakonec všechny tři role**, ne jen čtení tvrzení. S1 patří
   čtení celého diffu; úspora na rolích byla můj špatný odhad. Ostrý provoz
   pouští vždy všechny tři.
3. **První čtení f06c2f0d si ověřovalo dnešní běžící bránu k modelům** místo
   stavu commitu a nenašlo nic. Přehrávka minulosti nesmí sahat na živý svět;
   další revizoři to měli v zadání výslovně. Ostrého provozu se to netýká, tam
   je kandidát přítomnost.
4. Celkem 10 spuštění místo 6, zhruba 1,3 mil. tokenů, odhadem do 10 USD
   (přesnou cenu podagentů nástroj nevrací). Strop 25 USD dodržen.

### Známá slabina
S8 je typ nálezu „nová obrana má díru": vyžaduje domyslet, co test nehlídá.
Nové role se ptají na sliby, tvrzení a celek, ne na sílu nových testů. Zůstává
otevřené jako položka backlogu.

Zahození nálezu jen kvůli formě je na konci plánu drahé (blokující věc zmizí
s poznámkou „1 zamítnutý"). Jednorázové vrácení revizorovi k přepsání je změna
všech úrovní revizí, mimo tento plán - položka backlogu.
