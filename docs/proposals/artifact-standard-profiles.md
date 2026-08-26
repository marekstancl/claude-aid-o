# Návrh změny: profily artefaktů podle typu

**Stav:** návrh, nepublikovaný.
**Cíl:** sekce, která se doplní do ekosystémového standardu
[Artefakty - standard pro sdílené stránky](/opt/eco/docs/docs/ecosystem/specs/artifact-standard.md).
**Vznikl:** P089 Krok 1, 2026-08-26.

## Proč

Dnešní standard popisuje **jednu kostru pro všechny stránky**: sedm bloků, stropy,
zákaz cest v odkazech. Co má být *uvnitř* bloku, ale neříká - a tak se stalo tohle
(PM, 25. 8. 2026, o stránce z bran: „hodnota artefaktu 0"):

- dlaždice hlásily „6/9 prošlo", ačkoliv selhalo **nula** bran - tři jen neběžely;
- jádro jen přepsalo dlaždice do věty a nikdy neřeklo, **které** brány běžely
  a co ověřily;
- bloky 5 a 7 nesly třikrát tutéž **cestu k souboru**, kterou standard zakazuje;
- blok 6 řekl „nic se ode mě nečeká" a hned pod tím stál příkaz ke spuštění.

Kostra byla dodržená ve všech čtyřech případech. Stránka byla přesto bezcenná.
Chybí **per-typ povinnosti**: co konkrétně dluží dlaždice, jádro a rozhodovací blok
u stránky o plánu, a co u stránky o branách. Tenhle návrh je doplňuje.

## Obecná pravidla (platí pro každý typ)

### 1. `artifact_type` je povinné pole

Každý artefakt deklaruje svůj typ. Bez typu se stránka nevyrenderuje.

Platná je **právě tato pětice**:

| `artifact_type` | Kdy vzniká |
|---|---|
| `brainstorming` | po dokončeném brainstormingu, před psaním plánu |
| `plan` | po napsání plánu, před generací EPIKŮ |
| `gates` | po doběhnutí bran |
| `epic_done` | po dokončené revizi hotového EPIKU |
| `plan_done` | po uzávěrce celého plánu |

Typ mimo tuhle pětici je **chyba**, ne důvod k improvizaci. Nový typ se přidává
sekcí v tomhle standardu, ne výjimkou v kódu.

### 2. Odkaz je jméno, ne cesta

Standard to už říká u bloku 5 („**názvy**, ne cesty ani URL"). Tenhle návrh to
rozšiřuje výslovně i na **blok 7** a dělá z toho strojovou kontrolu:

> **Cesta k souboru v bloku 5 nebo 7 je vada stránky.** Nikoli styl, nikoli
> doporučení. Řetězec, který vypadá jako cesta (obsahuje `/` a příponu, nebo
> začíná `/`, `./`, `../`, `~/`), se v těchhle blocích nesmí objevit.

Cesta patří do provenience v patičce, kde už dnes je. Čtenář publikované stránky
s cestou nic neudělá - a tři kopie téže cesty ve dvou blocích jsou přesně ten
šum, kvůli kterému stránku přestal číst.

### 3. Formulace se odvozuje ze stavu, nepíše se prózou

Věta o výsledku (blok 3 a dlaždice bloku 2) se **skládá z čísel**, která stránka
už nese - ne z prózy, kterou by pak někdo kontroloval na slovník.

> **Kde stroj umí větu složit ze stavu, tam ji model psát nesmí.**

Důvod je konkrétní: „nula selhání" a věta o selhání vedle sebe je rozpor, který
se detekcí slovníku chytá nespolehlivě (jazyk selhání lze napsat stovkou způsobů),
zatímco odvozením ze stavu **nemůže vzniknout**.

### 4. Vnitřní rozpory jsou vada, kterou hlídá stroj

| Rozpor | Pravidlo |
|---|---|
| „nic se nečeká" vedle neprázdného seznamu dalších kroků | vzájemně se vylučují |
| sekce s nulovým počtem položek | sekce se **nerenderuje**, nerenderuje se prázdná |
| odkaz bez jména | vada |
| odkaz duplikující cíl bloku 7 | vada |

Hranice zůstává tam, kde ji standard má: **stroj hlídá přítomnost, tvar
a vnitřní rozpory; kvalitu posuzuje čtenář** (u agentů kontrolní model).

## Blok 6: tvar rozhodnutí

Blok „Co se čeká ode mě" přebírá **doslova** tvar z
[Jak Marek rozhoduje](/opt/eco/docs/docs/ecosystem/ai-agents/marek-rozhodovani.md#jak-se-mu-předkládá-rozhodnutí):

1. **Lidský popis problému.** Co se stalo a koho to postihlo. Bez technického chrleče.
2. **Možnosti.** Vždycky víc než jedna, s tím, co která stojí a čím se riskuje.
3. **Doporučení.** Jedno, ne menu.
4. **Proč zrovna to.** Bez tohohle bodu je doporučení jen názor.

A **pátý bod navíc** (PM, 25. 8. 2026):

5. **Co se stane, když nerozhodneš.** Výchozí stav není „nic" - něco běží dál,
   něco stojí. Čtenář má vědět co.

Vlastník ani lhůta se **neuvádí**: vlastník je vždy PM.

Druhá platná podoba bloku zůstává beze změny: **„rozhodovat není o čem"** s jednou
větou proč a co bude dál. Chybějící blok je vada; blok, který říká, že se
rozhodovat nemá o čem, je informace.

## Profily

Níže je pro každý typ výčet toho, co dluží **blok 2** (dlaždice), **blok 4**
(jádro) a **blok 6** (co se čeká). Forma je převzatá z
[Hotovo, když](/opt/eco/docs/docs/ecosystem/ai-agents/definition-of-done.md):
obecné pravidlo nahoře, per typ odškrtnutelné položky.

Bloky 1, 3, 5 a 7 se řídí obecnou kostrou a per-typ povinnosti nemají.

### `brainstorming`

- **Dlaždice:** počet zvažovaných variant · počet shod · počet sporů · počet
  otevřených neznámých
- **Jádro:** problém, který se řešil · kritéria, podle kterých se vybíralo ·
  varianty a **důvod volby** té jedné · spory, pokud nějaké zbyly
- **Co se čeká:** rozhodnutí o zvolené variantě, nebo výslovné „rozhodovat není
  o čem, píšu plán"

Sekce sporů se nerenderuje, když žádný spor nezbyl.

### `plan`

- **Dlaždice:** pásmo ceremonie · počet kroků · počet deklarovaných souborů ·
  počet rizik
- **Jádro:** cíl plánu lidsky · **co plán dodá** (řádek na krok, seskupeno po
  EPICech) · rizika, která plán sám pojmenoval
- **Co se čeká:** přečíst plán a říct, co v něm chybí

### `gates`

- **Dlaždice:** **kolik selhalo** (ne poměr prošlých) · kolik neběželo · kolik
  bylo prominuto · doba běhu · pokus v pořadí
- **Jádro:** které brány **běžely a co ověřily** · u těch, co neběžely, **proč**
  (mimo profil / přeskočeno / nespuštěno kvůli infrastruktuře) · u prominutých,
  **kdo prominutí schválil** · u druhého a dalšího pokusu, co se změnilo od minula
- **Co se čeká:** rozhodnutí jen tehdy, když nějaké je; jinak výslovné „nic se
  nečeká" **bez příkazu vedle**

Kategorie výsledku jsou čtyři a jsou uzavřené: **prošlo · selhalo · neběželo ·
prominuto**. Prominutí se nikdy nepočítá mezi prošlé. Brána, která spadla na
infrastruktuře a ne na kódu, patří mezi „neběželo" a stránka ten důvod jmenuje;
brána, která spadla z neznámého důvodu, patří mezi „selhalo" s větou, že důvod
není znám - přiznaná nejistota je lepší než tichý přesun mezi kategoriemi.

### `epic_done`

- **Dlaždice:** doba · počet kroků · nálezy auditu podle závažnosti · počet nově
  vzniklých backlog položek
- **Jádro:** co EPIC dodal lidsky · kde byly problémy a **proč** se staly · co
  našel audit · **seznam backlog položek s důvodem vzniku**
- **Co se čeká:** mergnout / vrátit / mergnout s výhradami - s doporučením a důvodem

Chybí-li report auditu nebo kurátora, stránka **vznikne a pojmenuje, co chybí**.
Nikdy se netváří, že revize proběhla úplně. Sekce nálezů a sekce backlogu se
nerenderují, když jsou prázdné.

### `plan_done`

- **Dlaždice:** vydaná verze · počet EPIKŮ · doba od začátku plánu · počet
  otevřených položek
- **Jádro:** co je venku · co se odložilo a **kam** · co plán nesplnil
- **Co se čeká:** rozhodnutí o odložených položkách, nebo „nic se nečeká"

Plán vydaný bez EPIKŮ (čistě dokumentační) to v dlaždici **řekne** - ne nula bez
kontextu.

## Co tenhle návrh nemění

- Kostra zůstává **sedmibloková** a v tomtéž pořadí.
- Stropy zůstávají beze změny (5 položek, 3 další kroky, 5 odkazů, ~220 znaků
  na větu).
- Rozhodovací bloky A/B/C a jejich stropy platí dál; bod 5 („co se stane, když
  nerozhodneš") je doplněk, ne náhrada.
- Typy stránky pro **selhaný krok**, **replan** a **incident** se nezavádí -
  nastávají zřídka a jejich obsah zatím nikdo nezná.

## Next Steps

**Publikace je ruční krok a je vědomě mimo tenhle soubor.** Znění vzniká
v repozitáři AID; do
`/opt/eco/docs/docs/ecosystem/specs/artifact-standard.md` ho přenese PM nebo
samostatný běh **v repozitáři `docs`**.

Důvod je mechanický, ne organizační: kontrakt kroku (P087) ověřuje očekávané
artefakty jako `${root}/${cesta}` a změny sbírá `git -C "$root" status` - obojí
nad repozitářem plánu (`aid-dispatch-contract.sh:264,273`). Krok, který deklaruje
soubor v **jiném** git repozitáři, skončí `verdict: reject` s odůvodněním
„expected artifacts are missing on disk", i když ten soubor na disku je a agent
práci udělal správně. Podpora druhého kořene v kontraktu je zapsaná jako
**IMP-519**.

Dokud publikace neproběhne, platí kontrakt **uvnitř AID** a mimo něj nikoho
neváže. EPIC 1 nesmí tvrdit, že standard je venku.

---

**Last Updated:** 2026-08-26
