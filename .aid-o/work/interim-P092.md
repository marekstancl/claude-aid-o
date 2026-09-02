# P092 — kdo tu práci dělá: vlastnictví místo odhadu

Založeno 2026-08-31. PM: „chci to už konečně opravit pořádně (…) ať je to
bullet proof, ale ne overengeneered."

## Co se stalo (tři dny, tři pravidla, jedna vada)

V projektu, kde běží víc oken najednou, hooky říkaly oknu A, ať dodělá nebo
opraví práci okna B:

| kdy | pravidlo | co hlásilo |
|---|---|---|
| 28. 8. | `milestone_artifact_rendered` | přerenderovat stránku plánu P062, který měnilo jiné okno |
| 30. 8. | `queue_continuation_notice` | všechny otevřené plány v projektu, na každém tahu |
| 31. 8. | `turn_step_open` | dodělat `step_1_backend` (E-020-2_3), který ve 4:19 dispatchl autonomní běh v jiném okně |

## Příčina (ověřená Codexem)

**AID nikde nezaznamenává, kdo práci začal.** Každé pravidlo, které potřebuje
odpovědět „je tohle moje?", si to musí domyslet — a každé si to domýšlelo jinak:
podle času (`find -newer`, `mtime >= session start`), nebo vůbec ne.

V jednom okně je každý ten odhad správný, protože všechno, co se pohnulo, pohnul
ten jediný, kdo tam byl. Ve dvou oknech jsou všechny stejně špatné:
**„stalo se to po mém startu" není „udělal jsem to já".**

Každé pravidlo se opravovalo zvlášť jinou náhražkou (zmínky v přepisu, parsování
zápisů, whitelist shellových forem). U jednoho z nich pět kol posudku vyrobilo
pět užších verzí a pět nových protipříkladů, až u `echo "tee …/P900.md"`, kde už
statická kontrola nepomůže.

## Co Codex k návrhu dodal (2026-08-31)

Potvrdil základ: *„Recording dispatch provenance is the right foundation."*
A našel tři věci navíc:

1. **Jedna příčina nevysvětluje všechno.** `queue_continuation_notice` má
   druhou, nezávislou vadu: nemá pojem, za které plány session odpovídá.
   Vlastník kontraktu na to neodpoví.
2. **„Kdo dispatchl" ≠ „kdo to má dodělat".** Práci lze převzít, obnovit,
   sledovat z jiného okna. Chce to vědomé převzetí, ne jen razítko původu.
3. **„Nepodepsaný kontrakt = cizí" umí ztratit práci** — rozdělaný krok z doby
   před změnou by neohlásil nikdo.

Plus: `CLAUDE_CODE_SESSION_ID` je použitelný původ, ale u subagentů a obnovených
session se může lišit; samotná rovnost je křehká.

## Stav před plánem
Rozdělané a NEcommitnuté: kontrakt už vlastníka zapisuje, `turn_step_open`
a `turn_write_scope` ho čtou, 15 z 16 testů prochází. Nic z toho není vydané.

## Rozhodnutí (2026-08-31)

PM plán odložil („dáme jej zatím k ledu"), takže tři otázky ze zastavení nebyly
zodpovězeny a plán je píše podle DOPORUČENÍ. Až se plán rozmrazí, jsou to první
tři věci k potvrzení:

1. **Nepodepsaná práce** → nepatří nikomu: na konci tahu mlčí, v přehledu na
   startu session se ukáže. (Alternativa (b) „patří tomu, kdo ji najde" vrací
   přesně tu vadu, která se odstraňuje.)
2. **Převzetí** → jeden příkaz se zdůvodněním, zapíše se. (Ne lease s vypršením:
   vypršení = hlídat čas = zpátky u hádání.)
3. **Za které plány session odpovídá** → ty, jejichž běh dispatchla nebo jejichž
   plán zapsala; odvozeno z téhož zápisu, žádný druhý mechanismus.

## Proč se ceremonie neběžela
Plán jde k ledu, ne do generace. CP1-deep, C0 kola a ledger se pouští před
generací EPICů — dělat je teď znamená měřit znění, které se do té doby může
změnit. Plán prošel lintem, kontrolou vln a readiness; to je to, co má smysl
mít hotové u odloženého plánu.
