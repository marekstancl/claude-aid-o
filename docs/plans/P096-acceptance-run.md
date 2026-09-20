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

## Ukázka zbytečné složitosti (ostré čtení, strop 1 USD)
Revizor kroku (Sonnet, 70 tis. tokenů, 33 s) nastraženou věc našel: ruční smyčka
po znacích místo `basename`. Nahlásil ji jako závažnou podle otázky 7 a jinak
nic. Jeho skutečná odpověď nahradila ve fixtuře ručně psanou.

## Testbed (proti tomuto pracovnímu stromu)
`bin/verify.sh --plugin <strom>`: 37 prošlo, 0 selhalo. Nově sedm kontrol
uzavření plánu: zdravý plán projde; odmítá se otevřený blokující nález, červená
brána, nevypořádaný závazek, **odpověď revizora bez záznamu o spuštění, ručně
přepsané rozhodnutí a kandidát posunutý po revizi** (tři podvrhy z plánu).
Testbed pouští případy z `test-plan-final-decide.bats` nainstalovaného pluginu,
vlastní kopii fixtur nemá.

## Přehrání času (deset zaznamenaných běhů)
**Není to přehrání od začátku do konce**, a říkám to předem: brány WAN a ACTA
(pytest, databáze) se v odloženém klonu pustit nedají. Čas nového pokusu je
proto složený ze tří změřených částí: skutečná doba bran z daného běhu + režie
nových kroků bez modelů (68 s, třikrát měřeno, včetně stavby fixtury) +
nejpomalejší revizor kola z dnešního ostrého čtení (role běží souběžně).

| Běh | Brány | Starý pokus celkem | Nový pokus (složeno) |
|---|---|---|---|
| WAN P101 pokusy 7-11 | 3,6-3,9 min | 6,3 / 12,7 / 17,4 / 22,4 / 43,5 min | 8,5-8,8 min |
| ACTA P024 pokusy 1-3 | 4,6-4,9 min | 8,7 / 28,2 / 57,1 min | 7,9-8,2 min |
| ACTA P021 pokus 1 | 4,6 min | 96,5 min | 7,9 min |
| ACTA P020 pokus 5 | 17,5 min | 36,4 min | 20,8 min |

Medián nového pokusu: **WAN 8,7 min proti 10,7, ACTA 8,2 min proti 22,6.**
Kritérium (pod základem u obou projektů) splněno, u WAN těsně. Hlavní úspora
není v minutách na pokus, ale v počtu pokusů: oprava dokumentace už neplatí
brány ani dvě ze tří rolí znovu. To se ukáže až na živých plánech
(`P096-live-follow-up.md`).

## Cena a doporučení
Zhruba 10 USD na šest nálezů potvrzených revizorem, tedy kolem 1,7 USD za nález.
**Doporučení: pokračovat částí 2 (mazání).** Pravidlo splněno 7 z 8, nové čtení
navíc našlo věci, které auditor neviděl, a obě slabiny (S8, zahazování na formu)
jsou zapsané jako backlog, ne zametené.
