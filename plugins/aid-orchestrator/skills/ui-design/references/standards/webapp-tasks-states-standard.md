---
sidebar_position: 16
title: Úlohy a stavy webové aplikace
description: "Co webová aplikace navíc k design systému definuje: mapu úloh se sedmi stavy, hluboké odkazy a zpět, hromadné akce a grafy s přístupnou náhradou."
status: published
owner: "Platform"
created: 2026-09-27
updated: 2026-09-27
---

# Úlohy a stavy webové aplikace

Jednou větou: **webová aplikace má pro každou úlohu uživatele popsaných sedm
stavů, ne jen šťastnou cestu, a stav obrazovky jde sdílet odkazem.**

Tento standard doplňuje [Design systém aplikací](./design-system-standard)
jen o to, co tam chybí. Stavy formulářových polí, prázdný, načítací a chybový
stav obrazovky, fokus a klávesnice, dotykové cíle 44 px a kontrola před
nasazením jsou v design systému
([komponenty](./design-system-standard#komponenty--co-definovat),
[vzory](./design-system-standard#vzory--co-definovat),
[přístupnost](./design-system-standard#přístupnost--závazný-kontrakt),
[platformy](./design-system-standard#co-se-na-platformách-liší-a-musí-být-definované),
[kontrola před nasazením](./design-system-standard#kontrola-před-nasazením))
a tady se neopakují. Při rozporu platí design systém.

Opora: WCAG 2.2 (úroveň AA) a WAI-ARIA Authoring Practices. Pravidla převzatá
z cizích zdrojů jsou přepsaná vlastními slovy a u každého je zdroj; registr
s licencemi drží plugin AID (`skills/ui-design/references/adopted-sources.md`).

## What — co musí aplikace mít

**UA-1 Mapa úloh.** Projektový design standard obsahuje tabulku úloh (co
uživatel v aplikaci dělá: „vystavit fakturu", „pozvat kolegu"). Pro každou
úlohu je popsáno sedm stavů:

| Stav | Co popsat |
|---|---|
| **1. Běžná cesta** | kroky od vstupu po potvrzení výsledku |
| **2. Chyba validace** | co uživatel zadal špatně, kde se to dozví, co zůstane vyplněné (UA-2) |
| **3. Prázdno** | úloha nemá data (první spuštění, filtr bez výsledku) (UA-3) |
| **4. Načítání** | co se načítá a jak dlouho to smí trvat, než přijde vysvětlení (UA-4) |
| **5. Selhání** | síť, server nebo cizí služba selže (UA-5) |
| **6. Oprávnění / role** | co vidí a smí role, která úlohu dělat nesmí, a proč (UA-6) |
| **7. Obnova po přerušení** | zavřený prohlížeč, ztracené spojení, souběžná úprava (UA-7) |

„Nenastává, protože …" je platná odpověď, ale musí být napsaná.

Kromě mapy úloh aplikace definuje hluboké odkazy a zpět (UA-8, UA-9),
hromadné akce (UA-10) a grafy s přístupnou náhradou (UA-11).

## Why — proč to platí

Obrazovka se staví a předvádí na šťastné cestě; ostatní stavy vzniknou až
v provozu, kdy je uživatel poprvé uvidí jako prázdnou stránku nebo nekonečné
kolečko. Design systém říká, že prázdný, chybový a načítací stav musí
existovat u komponenty. Neříká, co se stane s konkrétní úlohou, když selže
uprostřed, nebo když ji otevře role, která na ni nemá právo. To je rozdíl
mezi webem a aplikací a důvod tohoto standardu.

## How — pravidla ke stavům

**UA-2 Chyba validace.** Hláška stojí u pole a říká, co je špatně a jak to
opravit; u delšího formuláře navíc souhrn nahoře s odkazy na pole (WCAG 3.3.1,
3.3.3). Zadaná data po chybě zůstávají. Odeslání se neblokuje dřív, než je
jasné, že je vstup chybný.
*Zdroj: Impeccable `harden.md`; UI UX Pro Max řádky 55, 56.*

**UA-3 Prázdno.** Prázdný stav říká, co tu bude, a nabízí první krok (tlačítko,
které data vytvoří nebo naimportuje). Hledání bez výsledku nabízí úpravu
dotazu nebo zrušení filtrů, nikdy jen „0 výsledků".
*Zdroj: Impeccable `onboard.md`; UI UX Pro Max řádky 79, 90.*

**UA-4 Načítání.** Načítání říká, co se načítá („Načítám faktury…"). Operace
delší než pár sekund ukazuje průběh nebo odhad; akce, která už běží, nejde
spustit podruhé (zablokované tlačítko). Změna stavu je oznámena čtečkám
(`aria-live`, `aria-busy`).
*Zdroj: Impeccable `harden.md`.*

**UA-5 Selhání.** Hláška říká, co se stalo a co dál: tlačítko „Zkusit znovu",
jiná cesta nebo kontakt. Rozlišují se situace, které uživatel vyřeší sám
(síť), od těch, které nevyřeší (chyba serveru). Rozpracovaná data se selháním
neztrácejí.
*Zdroj: UI UX Pro Max řádek 80; Impeccable `harden.md`.*

**UA-6 Oprávnění a role.** Pro každou roli je řečeno, jestli úlohu nevidí,
vidí jen pro čtení, nebo ji smí dělat. Když na zakázanou úlohu uživatel přijde
(např. odkazem), dostane vysvětlení a cestu dál (koho požádat), ne prázdnou
stránku ani obecnou chybu. Vypršené přihlášení vrátí uživatele po novém
přihlášení tam, kde byl.
*Zdroj: Impeccable `harden.md` (Permission states).*

**UA-7 Obnova po přerušení.** Rozpracovaný vstup delší než pár polí přežije
zavření karty nebo výpadek spojení (koncept). Souběžná úprava téhož záznamu
dvěma lidmi se pozná a nekončí tichým přepsáním. Po přerušeném gestu nebo
požadavku jde další akce provést bez obnovení stránky.
*Zdroj: Impeccable `harden.md` (Concurrent operations, Interrupted gestures).*

## How — navigace, hromadné akce, grafy

**UA-8 Hluboké odkazy.** Stav, který má smysl sdílet (vybraný záznam, filtr,
záložka, stránka seznamu), je v adrese. Otevření takové adresy v nové kartě
ukáže totéž, pokud na to má uživatel právo (jinak UA-6).
*Zdroj: UI UX Pro Max řádek 5.*

**UA-9 Zpět.** Tlačítko prohlížeče Zpět dělá, co uživatel čeká: vrací
předchozí obrazovku nebo stav v adrese, nezavírá aplikaci a neztrácí
rozepsaná data bez varování. Otevřené okno zavře Zpět jen tam, kde to vzor
v projektovém standardu řekne.
*Zdroj: vlastní, opřeno o WAI-ARIA Authoring Practices.*

**UA-10 Hromadné akce.** Seznam, kde uživatel dělá stejnou akci s mnoha
položkami, nabízí výběr více položek a lištu akcí s počtem vybraných.
Hromadná destruktivní akce se potvrzuje s počtem položek a po dokončení
hlásí, kolik se povedlo a kolik ne (a které). Výběr se ovládá i klávesnicí.
*Zdroj: UI UX Pro Max řádky 35, 91.*

**UA-11 Grafy s přístupnou náhradou.** Graf nerozlišuje řady jen barvou
(přímé popisky, vzor, styl čáry; WCAG 1.4.1). Každý graf má textové shrnutí
a k dispozici tabulku s daty. Hodnoty, které se ukazují najetím myši, jdou
zobrazit i fokusem z klávesnice. Barvy grafu jdou z tokenů design systému.
*Zdroj: UI UX Pro Max `charts.csv`.*

## Exceptions — výjimky

- Web bez přihlášení a bez úloh (prezentační web) mapu úloh nemá; formuláře
  (kontakt, objednávka) jsou úlohy a mapu mají.
- Úloha, u které stav nedává smysl (jen čtení nemá chybu validace), ho má
  v mapě s důvodem „nenastává, protože …".
- Jiné výjimky schvaluje vlastník projektu a zapisují se do projektového
  standardu.

## Enforcement — jak se vynucuje

- Mapa úloh je součást projektového design standardu; úloha bez mapy je
  v revizi nález stejné váhy jako chyba.
- /aid-ui z mapy vyrábí scénáře „úloha × stav" a ověřuje je v bráně před
  dokončením (viz [Návrh a stavba frontendu](./frontend-build-standard),
  FB-11). Stav, který brána nepokryje, potřebuje jmennou výjimku PM.
