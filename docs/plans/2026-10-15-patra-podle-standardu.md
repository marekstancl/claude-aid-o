# Patra testů AID podle ekosystémového standardu (PM 15. 10. 2026: 1A, 2A)

Postup „Vývoj mimo AID“ (zadání → revize → kroky s revizí → dokumentace → revize celku).

## Proč

- Noční výsledek 15. 10. 2026: cesta k merge (T0 + T1) trvá 919 s místo 600 s
  (T0 252 s / 120 s, T1 667 s / 600 s). Noční zpráva `rozpocet-testu` to od dneška hlásí.
- Ekosystémový standard (`/ecosystem/specs/test-standard`) definuje T0 jako
  „lint, syntax, typová kontrola, žádné procesy ani síť, < 2 s / případ“. AID si
  v CONTRIBUTING nechal jen „< 2 s / případ“, takže v T0 skončilo 51 funkčních sad
  (studio přes HTTP, start companionu, generování loga…) a žádná statická kontrola.
- Kontrola pater (`aid-test-tier-lint.sh`, brána `tier_lint`) to dnes hlásí
  (2 sady ve špatném patře, T0 214 s / 90 s, T1 576 s / 390 s), ale běží jen
  v branách AID plánů. Vydání mimo AID (všechna od 3.0.0) ji obchází.
- Standard si sám odporuje: < 2 s / případ a ≤ 2 min / patro dovolí 60 případů,
  AID jich v T0 má 410 po 0,5 s.

## Co se mění

1. **Pojistka ve vydání (2A).** `aid-release.sh` spustí kontrolu pater proti nočnímu
   deníku měření před jakoukoli změnou souborů (jako `_release_test_names_guard`).
   Neprojde-li, vydání se zastaví se zprávou, co opravit; `--force` ji neobchází.
   Chybí-li deník (jiný stroj), vydání se zastaví a řekne to. Po zrychlení sady,
   které deník ještě nezná, se změří znovu (`run-all-tests.sh --tier tN --timing`
   s `AID_DURATIONS_DIR` na deník) – zpráva pojistky to říká.
2. **T0 jen statické kontroly (1A).** T0 = kontroly, které nic z AID nespouštějí:
   syntaxe všech skriptů (bash -n, node --check, py_compile), platnost JSON/YAML
   v pluginu, a stávající sady, které jen čtou soubory. Nová sada `test-static.sh`
   (t0). Všechny funkční sady dostanou t1. CONTRIBUTING (tabulka pater) převezme
   definici ze standardu. Kontrola pater vynutí mechanicky, co jde: sada t0 nesmí
   být bats sada, která `run`/spouští skripty pluginu – přesné pravidlo určí krok
   (nesmí falešně padat), jinak jen rozpočet.
3. **Zrychlit tak, aby T0 + T1 skutečným během bylo ≤ 10 min** na eco-dev bez zátěže
   nočního běhu. Postup podle měření, nejdražší první: sdílená příprava jednou na
   sadu (`snapshot.bash`), zúžení případů, kde test opakuje totéž; sada, která
   hlídá mezikomponentní tok, smí podle standardu do T2 se záznamem (CHANGELOG +
   komentář v hlavičce). `tier-core.txt` zůstává na cestě k merge.
   Rozpočty v `lib/aid-test-tier.sh` (T0 90 s, T1 390 s jako součty sad) se přepočítají
   podle nového rozdělení (T0 malé, T1 většina), součet + režie runneru ≤ 10 min.
4. **Noční zpráva o rozpočtu jmenuje 5 nejdražších sad cesty k merge** (z nočního
   deníku, jen sady s t0/t1), aby se opravovalo podle měření.
5. **Standard ekosystému:** odstranit rozpor (limit na případ vs. na patro) a přidat
   oddíl „Jak zůstat v rozpočtu“ (drahá příprava jednou na sadu, T0 jen statické,
   co dělat, když patro přeteče, kontrola pater i u vydání mimo plán). `aid/testing.md`.

## Hotovo, když

- AC1: `aid-release.sh` s porušenou kontrolou pater skončí 1 a nic nezmění (test).
- AC2: v T0 jsou jen sady bez spouštění AID; kontrola pater projde proti čerstvému
  měření.
- AC3: skutečný běh `--tier t0` + `--tier t1` na eco-dev ≤ 600 s (změřeno, číslo
  v hlášení); žádná sada nezmizela z portfolia bez záznamu (přesun do T2 nebo smazání
  podle pravidel testů s hodnotou).
- AC4: noční zpráva nad rozpočtem nese 5 nejdražších sad (test v test-aid-nightly-report).
- AC5: CONTRIBUTING, aid/testing.md a test-standard.md říkají totéž; changelog standardu.
- AC6: T0 + T1 zelené, testbed zelený, vydání 3.4.0.

## Mimo rozsah

Ostatní projekty (WAN, ACTA, agents) – návrh přijde po dokončení AID (PM 15. 10. 2026).
Blokace merge podle červeného nočního běhu (PM: později).

## Revize zadání (Codex, 15. 10. 2026) a co s ní

1. *prepare-plan obchází pojistku* – NE: vydání z plánu prochází branami plánu a `tier_lint`
   je mezi nimi; pojistka je pro vydání mimo plán (`_release_legacy_bump`), kde brány nejsou.
2. *nezměřená sada projde (UNVERIFIED)* – NE: nová sada nemá měření až do další noci; blokovat
   ji by zastavilo každé vydání, které přidá test. Další noc ji změří a další vydání ji zkontroluje.
3. *měření vázané na SHA kandidáta* – NE: noční deník je pravda o stavu main a odchylku chytí
   do dne; vázání na SHA je samostatný systém měření bez úměrného přínosu.
4. *merge cesta = i CI joby* – ANO, upřesnění: cockpit (vitest) běží v CI jako samostatný
   souběžný job a do rozpočtu pater nepatří; AC3 měří `run-all-tests.sh --tier t0` + `--tier t1`,
   což je přesně brána `bats_all` i CI job „Merge path“.
5. *dvojí rozpočty (90+390 součtem vs 120+600 skutečně)* – ANO: jeden model. Skutečný běh
   (noční měření) je rozhodující; součty sad v lintu jsou odvozené od něj odečtením naměřené
   režie a konstanty mají jedno místo (`lib/aid-test-tier.sh`), noční zpráva čte totéž.
6. *ztráta pokrytí přesunem do T2* – ANO: každá sada, která opustí cestu k merge, má v CHANGELOGu
   řádek „co hlídala a proč to cesta k merge nepotřebuje“ (nebo náhradní T1 test); `tier-core.txt`
   se nemění.
7. *mechanické rozpoznání T0 grepem* – ANO, vypuštěno: falešné pády. Standard upřesní „nic
   z produktu se nespouští“ (parsery a lint nástroje ano); T0 hlídá rozpočet a limit na případ.
8. *statické kontroly fail-closed* – ANO: nulový počet souborů daného typu i chybějící parser
   je pád; jeden případ s vadným souborem každého typu dokazuje, že kontrola chytá.
9. *5 nejdražších sad* – ANO, zjednodušeně: nejnovější necenzurovaný záznam každé sady s
   aktuální značkou t0/t1, řazeno časem sestupně, pak jménem; méně než 5 = kolik jich je.
10. *ověřitelnost AC5/AC6* – ANO: dokumenty jsou `CONTRIBUTING.md` (tabulka pater),
   `/opt/eco/docs/docs/aid/testing.md`, `/opt/eco/docs/docs/ecosystem/specs/test-standard.md`;
   testbed z privátní kopie s tímto checkoutem; tag na merge commitu.
