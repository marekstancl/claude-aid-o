> Archivováno 2026-10-25: dodáno jako AID 3.12.0. Náhrada: žádná.

# AID 3.12.0 – uzávěr plánu konverguje a neptá se dvakrát

PM 25. 10. 2026, volby 1A, 2A, 3A. Vývoj mimo AID (`/opt/eco/CLAUDE.md`), větev `feat/uzaver-konverguje`
(od 3.11.0), revizor Codex (při výpadku Claude agent s čistým kontextem). PM výslovně: rozhodnutí, která by šla
na něj, rozhoduje nezávislý revizor; ráno hotovo a nasazeno.

## Proč (změřeno 25. 10. 2026)

- **WAN P115:** 5 pokusů o uzávěr (17:04–20:15+), **Trading P004:** 7 pokusů (16:04–20:15). Brány v Tradingu
  prošly pokaždé; uzávěr zastavila celková revize (CP7): závažné nálezy po pokusech 5, 3, 2, 2, 3 – pokaždé jiné.
- **Příčina 1 – revize nekonverguje.** Po opravě kódu je první kolo nového pokusu PLNÁ revize celého plánu
  (P117 (16), `aid-step-review-packet.sh` „This is a FULL round over the new candidate“); potvrzovací kolo jen po
  opravě samotné dokumentace (P117 (15)). Každé plné kolo najde nové věci.
- **Příčina 2 – PM se ptá znovu na totéž.** Rozhodnutí PM (`dispute --pm accepted`) se váže na otisk nálezu
  (`fingerprint` = projekt, kontrola, krok, první citace, prvních 8 slov tvrzení). Nové kolo popíše tentýž problém
  jinými slovy → nový otisk → nová karta. Trading: „bod 7 E2E“ a „denní souhrn“ odsouhlaseny PM třikrát.
  Navíc karta musí obsahovat celý otisk (`aid_pm_card_check`), renderer ho tam nedá → první odpověď PM se nezapsala
  a karta šla znovu (Trading 16:31 a 16:36; hlášení Tradingu bod (5)).
- **Příčina 3 – každá oprava = všechny brány znovu.** Opakování bran podle `inputs:` existuje
  (`_pfsm_gate_reuse_rows`), ale WAN ani Trading `inputs:` nemají → „celý strom“ → nic se nepřenese.
  Změřeno: WAN brány ~13,5 min na pokus, z toho `plan_diff` 8 min (měří body zadání – musí běžet vždy), přenosem by šlo
  ušetřit ~5,5 min; Trading ~4 min, ušetřit ~1,5 min. Hlavní čas berou pokusy a kola revize (příčina 1).

## Co se staví

Verze 3 – zapracováno 11 nálezů první revize zadání a 3 druhé (Claude agent místo Codexu, 25. 10. 2026); značky
`[R<n>]` a `[S<n>]`; `[T<n>]` = nálezy revize kroku 2.

### Z1 – Po opravě potvrzovací kolo, ne plná revize (1A)

1. **Režim kola CP7.** První kolo pokusu je **potvrzovací**, když řetěz pokusů (`fix-class.json → previous_run_dir`,
   průchod jako `_closing_measure`) obsahuje pokus s **uzavřeným** kolem CP7 a od té doby se nic nepřepsalo
   (`fix-class.json reason` prázdný v celém řetězu) – i když bezprostředně předchozí pokus spadl na branách [R3].
   `fix.patch` = `git diff <head toho kola>..HEAD`; otevřené nálezy = otevřené blocker/major toho kola. Jinak plné
   kolo (první pokus, přepsaná větev, nečitelný rozsah). Kolo 2+ v rámci jednoho pokusu CP7 se nemění (CP7 potvrzuje
   v dalším pokusu) [R7].
   **Vědomá změna [S1]:** potvrzovací je i kolo po opravě kódu, když potvrzované kolo PROŠLO (dnes plné, P117 (15)
   jen pro dokumentaci). Bezpečné: `fix.patch` obsahuje VŠECHNY změny od zkontrolované hlavy, takže každý nový kód
   revizor vidí a nález v něm je `open`; `follow_up` může dostat jen nález v kódu, který už plné kolo zkontrolovalo.
2. **Co revizor v potvrzovacím kole dělá** (prompt): (a) u každého otevřeného nálezu ověří, že je opravený všude,
   jinak ho nahlásí znovu stejným tvrzením a první citací; (b) nový problém hlásí, když ho způsobila oprava, a
   **první citace je řádek, který oprava přidala nebo změnila** (v `fix.patch`), i když se projeví jinde; (c) problém,
   který podle pravidel zastavení jeho role blokuje, hlásí vždy, odkudkoli (odkaz na role, žádný nový výčet) [R8];
   (d) role `final_criteria` posuzuje body zadání jako v plném kole (změkčení, vypuštění, bod bez důkazu) – oprava je
   může změnit kdekoli [R2].
3. **Vynucení kódem** (`aid-review-adjudicate.sh`, jen CP7, jen potvrzovací kolo s `fix.patch`): nový nález (jeho
   `match` není mezi otevřenými nálezy potvrzovaného kola a není uzavřený rozhodnutím, Z2) dostane stav
   **`follow_up`**, když platí VŠECHNO:
   - není `blocker`;
   - nehlásí ho (ani jako spoluautor) role `final_criteria` a jeho první citace není `zadani.md:*` ani soubor plánu
     (`.aid-o/plans/*`) – nálezy o bodech zadání a kritériích nikdy nejsou `follow_up` [R2];
   - jeho první citace je `path:line` (nebo `path:a-b`) v repozitáři kandidáta a ten řádek (u rozsahu ŽÁDNÝ jeho řádek
     [S2]) **není** mezi řádky, které `fix.patch` na nové straně přidal (`+`); citace `<sha>:path:line`, `absent:path`, cesta jiného repozitáře
     (`repo_roots`) nebo chybějící `fix.patch` (`confirmation_fallback`) → nikdy `follow_up` (zůstane `open`) [R6].
4. **Nic se neztratí.** Každý `follow_up` se zapíše do `evidence/<plán>/follow-ups.jsonl` (otisk, `match`,
   závažnost, tvrzení, citace, kolo, pokus), bez duplicit podle `match` [R9]. Závěrečná stránka plánu ukáže
   „K dořešení po uzávěru: N“ s řádky; `plan-finalize --stage decide` vypíše počet a cestu k souboru a řadič je
   zapíše do backlogu projektu (pokyn v `pipeline.md`/`aid-run.md`; hlášení PM uvádí počet zapsaných) [R9].
   Stav `follow_up` v `merged.json` je chráněný jako ostatní verdikty: `merged.json` zapisuje `close` do
   `stage-writes.jsonl` a `decide` ruční úpravu po něm odmítne [S3] (test v AC2).
5. **Všechna místa, která počítají otevřené nálezy** [R1]: výčty `AID_SR_OPEN_JQ` (`lib/aid-step-review-packet.sh:51`,
   z něj `_round_verdict` a open-findings), `aid-review-adjudicate.sh:360`, `aid-release-policy.sh:397`,
   `aid-plan-fsm.sh:5089`, `aid-review-round.sh:1609`, `:1827`, `lib/aid-step-review-packet.sh:198`, `:473` –
   `follow_up` v nich není, zůstane tak; místa `status != "fixed"` – `aid-review-round.sh:575-576`, `:587`,
   `lib/aid-review-config.sh:288` – dostanou výjimku pro `follow_up`; `_semantic_final_write`
   (`aid-review-round.sh:1069`) mapuje `follow_up` na `deferred`. CP1 místa (`:256`, `lib/aid-plan-review-packet.sh:210`)
   `follow_up` nikdy nedostanou (jen CP7), přesto výjimka pro jistotu.

### Z2 – Rozhodnutí platí pro věc, ne pro otisk; karta projde napoprvé (2A)

1. **Karta s otisky** (hotovo v kroku 1): pole `quotes`, řádek „Týká se:“.
2. **Seznam rozhodnutí o věci.** `dispute --checkpoint cp7 --pm accepted` zapíše řádek do
   `evidence/<plán>/pm-decisions.jsonl`: id, plán, čas, slova PM, karta + `card_sha256`, otisk, `match`, závažnost,
   `rule`, tvrzení, **první citace** nálezu. Zápis se zaznamená přes `aid_stage_writes_record` [R5]. Kladné rozhodnutí
   delegáta (`dispute.delegated`, třída `technical`) jde do téhož souboru se `source: delegate` a sha jeho verdiktu;
   přenáší se jen podle `match`, nikdy podle citace zadání [R10].
3. **Automatické uzavření v dalších kolech a pokusech** (`aid-review-adjudicate.sh`, CP7): otevřený nález dostane
   `fixed` + `dispute.pm` z rozhodnutí + `settled_by: <id>`, když:
   - jeho `match` je `match` některého rozhodnutí a nález není závažnější než rozhodnutý (blocker jen rozhodnutím
     o blockeru) [T3]; NEBO
   - (jen rozhodnutí PM) jeho **první** citace je `zadani.md:N` a je shodná s první citací rozhodnutí, nález
     **není blocker** a jeho závažnost **není vyšší** než u rozhodnutého nálezu [R4].
   Zadání je během uzávěru zamčené (`cp7_brief_sha_mismatch`), řádky se nemění. Pro `match` platí POSLEDNÍ záznam:
   pozdější `dispute --pm rejected` zapíše odvolání a rozhodnutí přestane platit [T4]. Nález, který už nese odpověď
   PM nebo verdikt delegáta, se nikdy nepřepisuje; uzavření rozhodnutím delegáta se zapíše jako delegátovo
   (`dispute.delegated`), ne jako PM [T5].
   Opakovaný sběr kola značku `settled_by` zachová [U-A]; pozdější NE (PM `--pm rejected`, delegátův technický
   verdikt `rejected`/`fix`) odvolá rozhodnutí podle `match` i podle první citace zadání [U-C, U-D]; `decide` odmítne
   rozhodnutí, na které kolo plánu později řeklo NE, i kdyby někdo smazal řádek odvolání [U-B].
4. **Ochrana proti podvrhu** [R5, T1, T2]: `plan-finalize --stage decide` u každého nálezu se `settled_by` ověří, že
   rozhodnutí v `pm-decisions.jsonl` existuje, patří tomuto plánu, karta / verdikt se nezměnily, A ŽE rozhodnutý nález
   je v některém kole CP7 tohoto plánu se stejnou odpovědí (PM: `dispute.pm.answer accepted` s touž kartou; delegát:
   touž cestou a sha verdiktu), stejným `match`, závažností a první citací; karta PM cituje jeho otisk; verdikt
   delegáta je jeho soubor pro ten nález (`adjudicator-delegated-<fp16>.json`), třída `technical`, odpověď `accepted`
   nebo `dismiss`. Ručně dopsaný řádek tak neprojde (test: karta s odpovědí NE, cizí JSON jako verdikt). Záznam
   `../pm-decisions.jsonl` do `stage-writes.jsonl` se nedělá – kontrola zapsaných souborů vidí jen adresář běhu.
5. **Revizor to ví předem.** Balík kola CP7 ukáže „Rozhodnutí v tomto plánu“ (slova, čeho se týká) s pokynem: nehlásit
   znovu; nesouhlas jen s novým faktem a jinou citací.
6. **Viditelnost** [R4]: závěrečná stránka ukáže „Uzavřeno dřívějším rozhodnutím: N nálezů (rozhodnutí X: …)“.
7. **Co se nepřenáší:** přijaté riziko (`accept-risk`, P117 (14)) zůstává vázané na kandidáta.

### Z3 – Brány bez `inputs:` (3A, v rozsahu, který jde udělat bezpečně)

1. **Viditelnost** [R11]: `plan-finalize --stage gates` vypíše řádek u každé brány, která minule prošla, má stejné
   `definition_sha256`, nemá `inputs:` a strom se změnil: brána, `duration_ms` minule, „deklaruj `inputs:`“. Pro
   `plan_diff` nic (běží vždy).
2. **Dokumentace** `inputs:` v šabloně `defaults/execution.yaml` a v `skills/pipeline.md`.
3. **WAN a Trading:** jejich konfigurace mají rozpracované změny – nesahá se. Návrh `inputs:` (soubor v evidenci
   tohoto plánu), zrevidovaný nezávislým revizorem, jde PM v hlášení.
4. **Mimo rozsah:** automatický odhad `inputs:`.

## Co se nemění

- Plné kolo CP7 v prvním pokusu, měření bodů zadání (`plan_diff`) v každém pokusu, blokující nálezy blokují vždy.
- Přijaté riziko vázané na kandidáta (P117 (14)); rozhodnutí o rozsahu (zúžení zadání) dál patří PM – jen se ptá
  jednou.
- Stand-in (3.8.0) a třídy odmítnutí beze změny.

## Hotovo, když

- [ ] AC1: Potvrzovací kolo: po opravě kódu (i po PROŠLÉM kole [S1]), i když předchozí pokus spadl na branách (řetěz), `mode: confirmation`,
  `fix.patch` od hlavy posledního uzavřeného kola CP7, prompt s (a)–(d); první pokus a přepsaná větev → `full`.
- [ ] AC2: `follow_up`: ne-blocker mimo řádky opravy → `follow_up` + řádek v `follow-ups.jsonl` (bez duplicit);
  na řádku opravy → `open`; blocker mimo opravu → `open`; nový major `final_criteria` mimo opravu → `open`; první
  citace `zadani.md:*` nebo plán → `open`; citace `<sha>:…`, `absent:…`, cizí repo, chybějící `fix.patch` → `open`.
- [ ] AC3: `follow_up` neblokuje: verdikt kola, `aid-release-policy.sh`, sada přijatého rizika v decide,
  `semantic-review-final.json` (`deferred`), kontrola pokroku `:575` – každý test.
- [ ] AC4: Karta s `quotes` vypíše otisky; `dispute --pm accepted` i `accept-risk` projdou napoprvé (krok 1; kolo 2
  revize našlo, že `accept-risk` hledal jen 16znakový otisk – opraveno, test).
- [ ] AC5: `pm-decisions.jsonl` po `dispute --pm accepted`; v dalším pokusu: stejný `match` → `fixed` + `settled_by`;
  stejná první citace zadání, ne-blocker, ne vyšší závažnost → `fixed`; tatáž citace jako blocker → `open`;
  jiná citace → `open`; `accept-risk` se nepřenese; podvržený / změněný záznam nebo karta → decide odmítne.
- [ ] AC6: Balík CP7 obsahuje rozhodnutí s pokynem.
- [ ] AC7: Brány podle [R11] vypíší řádek s dobou; `plan_diff` ne; šablona a `pipeline.md` popisují `inputs:`.
- [ ] AC8: Závěrečná stránka ukáže `follow_up` i uzavřené dřívějším rozhodnutím; decide vypíše počet `follow_up`.
- [ ] AC9: Dokumentace ve stejném kroku: `skills/pipeline.md` (+ tabulka odmítnutí), `commands/aid-run.md`,
  `skills/communication.md`, `skills/step-review-roles.md`, registry, oba CHANGELOGy.
- [ ] AC10: T0 + T1 zelené, dotčené sady zelené, testbed nad `git archive` prochází.
- [ ] AC11: Revize nezávislým revizorem: zadání, každý krok, celek.
- [ ] AC12: Návrh `inputs:` pro WAN a Trading zrevidovaný, v hlášení.

## Postup po krocích

1. Z2a karta s `quotes` (nejrychlejší úleva).
2. Z2b seznam rozhodnutí PM + automatické uzavření + balík.
3. Z1 potvrzovací kolo + `follow_up` + `follow-ups.jsonl` + stránka.
4. Z3 viditelnost + dokumentace + návrh pro WAN/Trading.
5. Kontrola celku, testy, testbed, vydání 3.12.0.

## Stav (25. 10. 2026 večer)

- Krok 1 commit 60693965, krok 2 commit bcb01022 (revize Claude místo Codexu - limit; nálezy zapracované).
- Kroky 3 a 4: revize Claude místo Codexu (limit do 22:25). Nálezy 1-7, 9-11 opravené: testy řetězu pokusů,
  jednotkový test značení follow-upů (citace zadání, plánu, commitu, cizího repa, rozsah přes opravu,
  obrácený rozsah, bez fix.patch), konec uzávěru s follow-upem a ruční přepis na follow_up; čtení fix.patch
  podle počtů hunku; soubory z kandidáta, ne z indexu; follow_up se drží i při dalším sběru; prázdné `inputs: []`
  a EPIC tokeny u výpisu brány; počet FOLLOW-UPS bez věcí, které pozdější kolo vrátilo jinak; dokumentace
  pro revizora a kartu. Nález 8 neopraven: `round.json` po uzavření kola hlídá stage-writes a decide nad
  neuzavřeným kolem neprojde. Kontrola postupu v kolech 2+ (`ROUND >= 2`) u CP7 nenastane (kolo 2 CP7 se
  odmítá, protože oprava mění kandidáta), proto bez testu s follow_upem.
- Oprava během kroku 3: nález s citací `absent:` jq tiše vypustil (prázdný capture) - opraveno, hlídá test.
- Kontrola celku (Claude s čistým kontextem, Codex limit): opraveno 1 (přeformulovaný otevřený nález - stejný
  soubor první citace nebo stejné pravidlo zůstává otevřený), 2 (balík revize jen s platnými rozhodnutími),
  3 (karta PM se kopíruje do `evidence/<plán>/decision-cards/`), 4 (jeden výpočet živých follow-upů pro decide
  i stránku), 5 (odvolání podle citace jen u `zadani.md:`), 6 (řádek odmítnutí), 7 (cesty s mezerou); testy
  doplněné (stránka uzávěru, accept-risk se nepřenáší, platná rozhodnutí). Neopraveno: test, že follow_up
  nepatří do množiny přijatých rizik - množina vyjmenovává stavy open/disputed/form_invalid výslovně;
  „zahodit settled_by, které verify odmítne“ - po kopii karty už přepsání cesty nenastane.
