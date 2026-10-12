Proveď nezávislý review implementačního plánu.

Důležité:
- Nic neimplementuj.
- Nevěř tomu, že plán je správný jen proto, že je dlouhý nebo formálně vypadá dobře.
- Chovej se adversariálně: hledej, kde plán může vést k falešně zelené implementaci, zbytečné práci nebo nedoručení skutečné hodnoty.
- Ověř plán proti reálnému repo stavu, ne jen proti textu zadání.

Postup kontroly:

1. Ověř, co má plán skutečně dodat.
   - Jaký problém má vyřešit?
   - Jaký konkrétní výsledek má vzniknout?
   - Kdo je uživatel/consumer výsledku?
   - Je jasné, podle čeho poznáme DONE?

2. Porovnej plán s realitou repozitáře.
   - Existují uvedené soubory, skripty, registry, commands, skills?
   - Neplánuje změny do špatných cest?
   - Neignoruje existující implementaci nebo zavádí paralelní systém?
   - Neopírá se o neexistující helpery, schémata, porty, fixtures, služby?

3. Zkontroluj scope.
   - Není plán moc široký na jeden EPIC/krok?
   - Neobsahuje skrytou runtime změnu, i když tvrdí, že je jen dokumentační/schématický?
   - Neřeší vedlejší problémy, které mají být samostatný plán?
   - Nechybí naopak kritická část bez které výsledek nebude použitelný?

4. Zkontroluj acceptance criteria.
   - Jsou AC konkrétní, ověřitelná a blokující?
   - Má každý krok/fáze vlastní AC?
   - Nejsou AC jen “testy projdou” nebo “soubor existuje”?
   - Je jasné, co znamená PASS, FAIL, PARTIAL, UNVERIFIABLE?
   - U každého AC typu "vždy", "vše", "každý", "nikdy" musí být jasný rozsah:
     například "pro všechny dokumenty" vs "pro dokumenty s client_id".
     Pokud rozsah není explicitní, vyžádej opravu plánu.

5. Zkontroluj producer-consumer kontrakty.
   - Kdo artefakt produkuje?
   - Kdo ho čte?
   - Jak je vázaný na HEAD/revizi/hash?
   - Jak se pozná stale evidence?
   - Neexistuje cyklus nebo chybějící consumer?
   - U každého eval/evidence artefaktu musí být jasné, kterou část pipeline
     opravdu spouští a kterou ne. Částečný běh se nesmí prezentovat jako plné
     pokrytí.

6. Zkontroluj testovací strategii.
   - Jsou tam positive i negative fixtures?
   - Existují negative controls, které musí selhat při typické regresi?
   - Není plán závislý jen na synthetic datech?
   - Je zahrnuté ověření proti reálným datům/oraclu tam, kde je to potřeba?
   - Je jasné, jak se testuje absence důkazu, stale evidence a špatný enum/schema?
   - Každá nová integrační funkce musí mít aspoň jeden test přes caller flow,
     ne jen unit test čisté funkce.

7. Zkontroluj rizika falešně zeleného výsledku.
   - Může plán projít, i když výsledek nejde použít?
   - Může LLM přepsat deterministický fail na pass?
   - Může starý důkaz platit pro nový commit?
   - Může chybějící fixture způsobit skip místo fail?
   - Může implementátor dodat jen formální artefakt bez funkčního consumeru?

8. Zkontroluj návaznost na AID kontrolní systém.
   - Je jasné, jestli jde o C0/C1/C2/C3/C4 nebo legacy CP alias?
   - Je jasné, co je observe, dual-run a blocking?
   - Nezapíná plán blocking příliš brzy?
   - Má plán jasné místo v roadmapě a závislostech?
   - Nezdvojuje Auditor/Curator/CP logiku místo sjednocení?

9. Zkontroluj provozní a bezpečnostní dopady.
   - Nezavádí novou závislost bez zdůvodnění?
   - Nevyžaduje neexistující verzi Node/Python/toolingu?
   - Neotevírá porty mimo pravidla?
   - Nezavádí write/exec schopnosti tam, kde má být read-only?
   - Má rollback nebo bezpečný observe režim?

10. Zkontroluj hodnotu pro PM/uivatele.
   - Bude po implementaci výsledek srozumitelný?
   - Pomůže to odhalit konkrétní minulé chyby?
   - Je jasné, jak to zlepší kontroly oproti dnešku?
   - Není to jen další dokument/vrstva bez enforcementu?

Výstup napiš takto:

Verdikt:
- PASS / PASS S PODMÍNKOU / FAIL / NELZE OVĚŘIT

Nejdůležitější nálezy:
- Seřaď podle závažnosti: BLOCKER / HIGH / MEDIUM / LOW.
- Každý nález musí mít:
  - konkrétní místo v plánu,
  - proč je to problém,
  - jaký požadavek nebo princip porušuje,
  - co přesně změnit.

Chybějící rozhodnutí:
- Vypiš otázky, bez kterých se plán nemá implementovat.

Chybějící acceptance / testy:
- Co musí být doplněno, aby šel plán objektivně ověřit.

Chybějící runtime/eval coverage:
- Kde plán neříká reálný caller path, pipeline slice, vstupy, výstupy a
  neotestované části.

Doporučený upravený postup:
- Konkrétní pořadí oprav plánu.
- Co musí být blokující před spuštěním implementace.
- Co může zůstat jako pozdější rozšíření.

Krátké lidské shrnutí pro PM:
- 5-10 vět česky.
- Jasně říct, zda plán pustit do implementace.
- Bez technického balastu.
