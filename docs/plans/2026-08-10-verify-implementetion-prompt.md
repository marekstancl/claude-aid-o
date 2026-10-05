Proveď nezávislý DONE review implementace.

Důležité:
- Nevěř mému summary ani předchozím PASSům.
- Nehodnoť podle toho, že testy prošly.
- Ověř reálný stav kódu, artefaktů, runtime a evidence.
- Chovej se adversariálně: hledej, kde implementace může být falešně zelená.
- Nic zatím neopravuj, pokud k tomu nedostaneš explicitní souhlas. Nejdřív dodej audit.

Postup kontroly:

1. Přečti plán/spec a vyextrahuj skutečná acceptance criteria.
   - Co mělo být dodáno?
   - Co je explicitně out of scope?
   - Jaké důkazy měly vzniknout?
   - Jaký uživatelský nebo systémový problém to mělo řešit?
   - U každého AC typu "vždy", "vše", "každý", "nikdy" ověř přesný rozsah:
     například "pro všechny dokumenty" vs "pro dokumenty s client_id".
     Pokud rozsah není explicitní, AC není objektivně ověřitelné.

2. Zkontroluj skutečný diff/repo stav.
   - Jaké soubory vznikly/změnily se?
   - Není rozsah nepřiměřený?
   - Nejsou tam mrtvé větve, duplicitní implementace, starý kód nebo paralelní resolver?
   - Nejsou tam placeholdery, TODO, hardcoded porty, lokální cesty, falešné defaulty?

3. Ověř runtime, ne jen statiku.
   - Umí to reálně nabootovat/spustit se?
   - Je endpoint/UI/CLI skutečně dosažitelný?
   - Je výstup použitelný proti reálným datům?
   - Nejde jen o knihovní vrstvu bez spotřebitele?
   - Pokud je to frontend, ověř screenshotem a reálným tokem, ne jen komponentami.
   - DONE REVIEW musí mít sekci "independent runtime path check": reálný caller
     flow, který používá produkce/FSM/CLI/API/UI, ne jen izolovanou helper funkci.

4. Ověř testy.
   - Testují reálné chování, nebo jen vlastní mock/synthetic svět?
   - Existují negative controls?
   - Selže test, když zavedeš typickou regresi?
   - Nejsou testy zelené, protože fixture chybí/skipuje se?
   - Nejsou testy přehnaně rozsáhlé bez hodnoty?
   - Každá nová integrační funkce musí mít aspoň jeden test přes caller flow,
     ne jen unit test čisté funkce.

5. Ověř producer-consumer kontrakty.
   - Produkuje implementace artefakty, které další část opravdu čte?
   - Sedí názvy, ID, path, hash, HEAD, timestamp, schema?
   - Není někde druhá paralelní implementace téže logiky?
   - Není důkaz starý, stale, self-consistent nebo nevázaný na aktuální revizi?
   - Eval evidence musí říct, kterou část pipeline skutečně spouští a kterou
     nespouští. Jinak jde jen o důkaz pokrytí daného slice, ne celé pipeline.

6. Ověř proti reálným datům/oraclu.
   - Porovnej výstup s nezávislým zdrojem pravdy, pokud existuje.
   - Nepoužívej jen implementací generovaný výstup jako vlastní důkaz.
   - U cross-project/read-model věcí ověř počty, identity, missing/drop případy a historická vs aktuální data.

7. Zkontroluj bezpečnost a provozní omezení podle typu změny.
   - Path traversal, symlinky, zápis/exec, porty, payload limity, permissions.
   - Read-only invariant, pokud byl slíben.
   - Eco pravidla, environment, Node verze, síťové chování.

8. Zhodnoť skutečnou hodnotu.
   - Dodává to to, co plán sliboval?
   - Je výstup srozumitelný pro cílového uživatele?
   - Není to jen hezky vypadající mrtvý přehled?
   - Nechybí důležité funkce, které z požadavku logicky plynou?

Výstup napiš takto:

Verdikt:
- PASS / PASS S PODMÍNKOU / FAIL / NELZE OVĚŘIT

Nejdůležitější zjištění:
- Seřaď podle závažnosti: BLOCKER / HIGH / MEDIUM / LOW.
- Každý nález musí mít:
  - konkrétní soubor/řádek nebo artefakt,
  - proč je to problém,
  - jaký požadavek/AC to porušuje,
  - jak to ověřit,
  - doporučenou opravu.

Co je opravdu hotové:
- Stručně, bez marketingu.

Independent runtime path check:
- Jaký příkaz/tok byl spuštěn.
- Jaký caller entrypoint byl použit.
- Jaký vstup/fixture a výstup/artefakt vznikl.
- Exit kód/výsledek.
- Zda je to stejná cesta, kterou používá produkce/FSM/CLI/API/UI.
- Co výslovně nebylo otestováno.

Co není prokázané:
- Vypiš chybějící důkazy, runtime mezery, testovací mezery.

Doporučený fix plán:
- Konkrétní pořadí oprav.
- Co má být blokující před DONE.
- Co může jít do backlogu.

Krátké lidské shrnutí pro PM:
- 5-10 vět česky.
- Bez technického balastu.
- Jasně říct, zda tomu můžu věřit a proč.
