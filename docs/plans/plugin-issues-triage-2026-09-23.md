# Hlášení z projektů a pět témat PM — co a jak (23. 9. 2026)

Podklad pro rozhodnutí PM. Plugin ve stavu 2.102.0 / 2.103.0-rc (commit `9de9b9c3`).
Každé hlášení je ověřené proti dnešnímu kódu: **platí** (vada tam je, řádek uveden),
**opraveno** (kde), **zaniklo** (komponenta smazána přestavbou), **ověřit** (nešlo
rozhodnout čtením, potvrdí se testem na fixture při práci na shluku).

Zdroj: `.aid-o/work/aid-plugin-issues.md` v projektech acta, agents, wan a v tomto
repu. Započítaná jsou jen hlášení bez uzavírací značky (HOTOVO / ZAMÍTNUTO / UŽ
ŘEŠENO). Uzavřená, 68 kusů, tu nejsou.

## Společné pravidlo pro všechny opravy (mantinel, ne překážka)

Každé odmítnutí pluginu musí říct tři věci: **co je špatně**, **proč na tom záleží**
a **jeden legální příkaz, jak dál**. `--force` je jen pro PM, nikdy běžná cesta
agenta. Dnes je nejčastější vzorec hlášení opačný: brána zastaví dobrou práci na
formě a cesta ven neexistuje, takže agent obchází (`--force`, ruční úprava JSONu,
přejmenování souborů). Návrh: test, který projde všechna `die`/`PRECONDITION FAIL`
hlášky ve skriptech a odmítne ty, které nejmenují další krok. Tím se pravidlo
nevymáhá slibem, ale kontrolou.

---

## Hlášení z projektů podle příčiny

### K1. Druhý revizor (Codex) fakticky nikdy neodpoví — PLATÍ

| Hlášení | Stav |
|---|---|
| aid-o 21. 9. „Codex nemůže napsat odpověď (sandbox read-only)" | platí |
| aid-o 21. 9. „Codex dispatch padá na velký prompt" | platí |
| agents 21. 9. „CP1 dispatch Codex role padá na délce argumentu" | platí (duplikát) |
| agents 21. 9. „Codex revizor v read-only dostává pokyn zapiš soubor" | platí (duplikát) |
| agents 21. 9. „Codex reviewer nemůže odevzdat JSON" | platí (duplikát) |

**Ověřeno v kódu:** `lib/aid-codex-transport.sh` předává celý prompt jako argument
(`"$prompt"`, řádek ~121) a pouští Codex `--sandbox read-only`; šablona
`defaults/prompts/review-prompt-v1.md:53` mu přitom říká „Write ONE file". Codex
tedy buď nedostane prompt (nad ~128 kB), nebo nesmí zapsat odpověď. Od P093 za
něj pokaždé odpovídá zástup Claude, takže „nezávislý druhý pohled" v revizích
reálně není.

**Co uděláme:** prompt poslat na stdin, šabloně pro Codex říct „odpověz JSONem jako
poslední zprávou" (transport ji už čte přes `--output-last-message`), selhání
spuštění (exit 126) ošetřit stejně jako timeout, tedy automatickým zástupem. Test
s promptem 200 kB. **Práce:** ~2 h.

### K2. Revize kroku: pravdivý nález zahozen kvůli formě, oprava pak nejde potvrdit — PLATÍ

| Hlášení | Stav |
|---|---|
| aid-o 23. 9. „pravdivý blocker zahozen na formu" | platí |
| agents 21. 9. „CP2 kolo prošlo, HEAD se posunul, nové kolo nejde připravit" | platí |
| agents 21. 9. „CP2 zamítlo tři platné nálezy kvůli `bash -c 'grep …'`" | ověřit (místo v kódu jsem nenašel) |
| agents 21. 9. „CP2 nález o chybném textu kritéria jde vyřešit jen přes --force" | platí |
| acta #26 „čerstvost CP3 vynutí celé kolo i po dvouřádkové opravě" | část platí (dnes to samé přes kola revizorů) |

**Ověřeno v kódu:** `aid-review-round.sh:317` odmítne nové kolo slovy „nothing to
confirm", když předchozí kolo nenechalo otevřený nález. Zároveň `aid-fsm.sh:1340`
odmítne posun kroku, protože revizoři neviděli aktuální HEAD. Obě pravidla jsou
rozumná, dohromady tvoří slepou uličku. Stačí k tomu, aby se krok po zavřeném kole
jakkoli změnil.

**Co uděláme:**
1. Posunutý HEAD po zavřeném kole = nové potvrzovací kolo je vždy povolené, jen nad
   rozdílem (co se změnilo od kola). To zároveň řeší acta #26 (delta místo celého kola).
2. Nález s chybou formy se nezahodí. Zůstane otevřený s poznámkou „forma neplatná",
   aby ho controller viděl (viz Rozhodnutí 1).
3. `bash -c '<příkaz jen pro čtení>'` se rozbalí a posoudí vnitřek.
4. Nález „chybný text kritéria plánu" dostane cestu `dispute --pm` jako v CP1.

**Práce:** ~1 den.

### K3. Kontrola plánu projde, generátor EPICů pak odmítne — PLATÍ

| Hlášení | Stav |
|---|---|
| acta 1. 9. P024 bod 1 „chybějící EPIC markery odhalí až generace" | platí (lint markery nekontroluje) |
| acta 1. 9. P024 bod 2 „skill píše ‚No dependencies', parser to odmítne" | platí (`skills/plan-writing.md:700`) |
| acta 1. 9. P024 bod 3 „kritéria musí být odrážky, nikde to není" | ověřit |
| acta 1. 9. P024 bod 6 „`Dependencies:` čtou dva parsery jinak" | ověřit |
| wan 2. 9. #1 „chybějící hranice EPICů se hlásí o krok pozdě" | platí |
| wan 2. 9. #2 „lint nekontroluje gramatiku závislostí" | platí |
| aid-o 21. 9. „finalize a generátor si odporují u `(tier: tN)`" | platí |
| acta #1 „lint chce `Reuse check` i u hotových kroků" | platí |
| acta #2 „kontrola připravenosti nemá cestu ven pro PM" | platí |
| wan #3, wan 2. 9. #3 „každá oprava plánu = ruční `supersede-generation`" | platí (IMP-281) |
| wan #4 „výjimka PM se spotřebuje i při běhu, který nic nevytvoří" | platí (IMP-281) |

**Ověřeno v kódu:** `aid-plan-lint.sh` nekontroluje závislosti, hranice EPICů ani
`(tier: tN)`. Všechno tři kontroluje až generátor. Pravidla jsou tedy ve dvou
kopiích a lint je mírnější.

**Co uděláme:** lint bude volat **tytéž funkce** jako generátor, ne vlastní kopii.
Věta „lint PASS" pak znamená „generace projde". Skill opravíme podle parseru
(jeden příklad `Depends on:`, odrážky u kritérií). Kontrola hotových kroků se
přeskočí. Neúspěšná transakce, která nic nevytvořila, se zaarchivuje sama. Výjimka
PM se spotřebuje až úspěchem. **Práce:** ~1-1,5 dne.

### K4. Návrat k rozdělanému plánu přegeneruje hotové EPICy — PLATÍ

| Hlášení | Stav |
|---|---|
| acta #10 „receipt generování je celoplánový" | platí (IMP-280) |
| acta #11 „auto-pipeline spadne na EPICu, který už je ve frontě jako hotový" | platí (IMP-280) |

**Co uděláme:** pojem „fáze už dodaná". Receipt váže jen fáze, které se generují,
a zápis do fronty hotový EPIC přeskočí. **Práce:** ~0,5 dne. Pokud se EPICy
přestanou ukazovat a budou vznikat za běhu (téma 3b), spadne tahle oprava do toho
přepracování.

### K5. Skript čte stav ze špatného místa (hlavní checkout vs. strom plánu) — PLATÍ

| Hlášení | Stav |
|---|---|
| agents 22. 9. „`decide` hlásí NOT READY kvůli vlastnímu artefaktu" | platí (`aid-pm-brief.sh:147`) |
| agents 22. 9. „`decide` u plánu na vlastní větvi nikdy neprojde" | platí (tentýž řádek) |
| agents 22. 9. dodatek „po `plan-close` zůstane smazání receiptu v indexu" | ověřit |
| aid-o 23. 9. „`plan_diff` hledá evidence relativně ke stromu plánu" | platí |
| agents 21. 9. „`plan_path` ukazuje do dočasného stromu generování" | platí (`commands/aid-plan.md:387` pořád radí generovat v dočasném stromu) |
| acta P024 bod 4 „generace v dočasném stromu nesmí běžet" | platí (tatáž příčina) |
| acta 31. 8. „commit kroku přistál na větvi plánu místo větve EPICu" | platí (`lib/aid-dispatch-contract.sh` větev nekontroluje) |
| acta 31. 8. „implementer přepnul větev ve sdíleném stromu" | platí (zákaz není v zadání agenta) |
| acta 31. 8. + wan #17 „ověření evidence měří hlavní checkout" | opraveno v 2.100.0 (P095) |

**Co uděláme:** jedna funkce „kde je stav" a jedna „kde je kandidát", všechny
skripty přes ně. Test na plánu, který běží na vlastní větvi (tam se to láme).
`aid-plan.md` přestane radit generovat v dočasném stromu. Commit kroku ověří
větev. Zadání agenta zakáže přepínat větev ve sdíleném stromu. **Práce:** ~1 den.

### K6. Brány (spolehlivost) — většinu řeší P097

| Hlášení | Stav |
|---|---|
| aid-o 23. 9. „změna lhůty brány nic nezmění" | opraveno v P097 krok 9 (`aid-run-gates.sh:563`) |
| aid-o 23. 9. „konec plánu neznovupoužil bránu se stejným stromem" | platí (klíč je commit, má být strom) |
| aid-o 23. 9. „T0+T1 trvá 44 minut" | platí, viz téma Merge cesta |
| acta 30. 8. + P024 #11 „`overall: pass` navzdory spadlé bráně" | opraveno (v2.96.0 + `aid-run-gates.sh` ~1455/1481), ověřím testem |
| acta 31. 8. „výsledek brány se přehrál i po opravě (bez otisku stromu)" | ověřit po P097 |
| wan #16 „dvojí běh bran → dva `gate_runner_start`, kontrola odmítne" | ověřit po P097 |

**Co uděláme:** po vydání P097 jeden test na každé „ověřit". Znovupoužití brány
klíčovat stromem (tree sha), ne commitem. **Práce:** ~0,5 dne.

### K7. Rozsah změn (co krok smí měnit) nepokrývá běžné situace — PLATÍ

| Hlášení | Stav |
|---|---|
| acta #28 „do backlogu nejde zapsat nález během bran" | platí |
| acta 31. 8. „`amend-scope` po posledním kroku odmítá" | platí (`aid-fsm.sh:5448`) |
| agents 22. 9. „`amend-scope` bere jen relativní cesty" | platí (`aid-fsm.sh:5454`) |
| agents 21. 9. „kontrola kroku nevidí změny v jiném repu" | platí |
| aid-o 22. 9. „smazaný testovací soubor nejde vrátit jako výsledek kroku" | platí |

**Co uděláme:** backlog a záznam chyb pluginu smí agent měnit vždy.
`amend-scope` bude fungovat i během bran a vezme absolutní cesty do deklarovaných
cizích repozitářů. Kontrola kroku změří rozdíl i v nich. Výsledek kroku umí
deklarovat smazaný soubor. **Práce:** ~1 den.

### K8. Uzavření plánu — převážně přestavěno v P096, zbytek ověřit

| Hlášení | Stav |
|---|---|
| acta 1. 9. „nejde zavřít plán dodaný mimo AID" | opraveno (`closure_kind: administrative`, `aid-plan-fsm.sh:7457`) |
| acta 31. 8. „`plan-reconcile` u plánu na větvi vždy unverifiable" | pravděpodobně opraveno (`aid-fsm.sh:7336`), ověřit |
| acta 1. 9. „kontrola uzávěru tiše umře na starém reportu" | ověřit (funkce přejmenovaná) |
| acta 1. 9. „`plan-close` přepsal ruční report prázdnou šablonou" | ověřit |
| acta #18 „`plan-close` chce `delivery.md`, nikdo neřekne kdo ho píše" | ověřit po P096 |
| acta 31. 8. „fronta neměla záznamy EPICů plánu" | ověřit |
| acta 31. 8. „`epic-start` zapsal jiné `run_id`" | ověřit |

**Co uděláme:** jeden průchod testem na fixture plánu. Co spadne, opravíme. Co
projde, zavřeme. **Práce:** ~0,5 dne + opravy podle nálezů.

### K6/K8 — přezkoušení pěti starších hlášení na 2.105 (P100 krok 6, 24. 9. 2026)

| Hlášení | Jak ověřeno | Výsledek | Akce |
|---|---|---|---|
| acta 31. 8. „`plan-reconcile` u plánu na větvi vždy unverifiable" | kód: dispatch `plan-reconcile` v `aid-fsm.sh` zahajuje režim plánu z manifestu (`_fsm_plan_mode_args`), jinak odmítne jménem | opraveno ve 2.96.0 | zavřeno |
| acta 1. 9. „kontrola uzávěru tiše umře na starém reportu" | kód: `aid-plan-close-check.sh` čte manifest přes `_pbm`, který pod `set -e` nikdy neskončí | opraveno (P096) | zavřeno |
| acta 1. 9. „`plan-close` přepsal ruční report prázdnou šablonou" | kód: `cmd_plan_close` už žádný report nepíše; stránku dodaného plánu skládá `plan-finalize` z evidence | zaniklo s P096 | zavřeno |
| wan #16 „dvojí běh bran → dva `gate_runner_start`, kontrola odmítne" | test `test-plan-final-decide.bats` (osiřelý start po spadlém běhu) | **platilo**: běh, který spadl před reportem, zablokoval plán navždy | opraveno v P100: počítají se dokončené běhy (`gate_runner_complete`) |
| acta 31. 8. „výsledek brány se přehrál i po opravě (bez otisku stromu)" | kód: `aid-run-gates.sh` ruší přehrání výsledku úlohy, jejíž strom se posunul (`result_tree_moved`); popředí se nepřehrává, běží pokaždé | opraveno (P087/P097) | zavřeno |

Znovupoužití brány při konci plánu: z posledního běhu EPICu na stejném stromu, brány s tokenem běhu (`{base_commit}` …) běží vždy znovu (P100 krok 6).

### K9. Zaniklo s přestavbami — zavřít bez práce

Komponenty, na které hlášení míří, už neexistují (ověřeno: soubor/funkce není).

| Hlášení | Proč zaniklo |
|---|---|
| acta #5 Codex hash manifestu | `lib/aid-c0-plan-review.sh` smazán (P093) |
| acta 31. 8. 2× `aid-c3-dispatch.sh normalize` | skript smazán (P094/P096) |
| acta 31. 8. obálka kostry plan-final | funkce `_pfsm_verify_plan_final_skeleton_envelope` smazána (P096) |
| wan #6 rozpočet revizí C0 | `lib/aid-cp1-ledger.sh` smazán (P093) |
| acta 2. 9. „CP1-deep není v PRE-FLIGHT" | pásma a CP1-deep zrušeny (P093) |
| agents 17. 9. #1 pásmo `full` kvůli `package.json` | pásma zrušena (P093) |
| agents 17. 9. #2 kontrola umřela na limitu, `detect` lže | `aid-brainstorm-opponent.sh`, `aid-audit-independence.sh` smazány; poučení „zapisuj průběžně" ověřit v zadání revizorů |
| agents 17. 9. #3 tabulka čoček | čočky nahrazeny šesti revizory (P093) |
| acta 17. 9. pilot konvergence (4 zápisy) | podklad P093; návrhy převzaty nebo zamítnuty tam |
| agents 17. 9. #7 srovnání s Codexem | nelze: Codex od P093 neodpověděl (K1); po K1 změřit znovu |
| acta 30. 8. unicode ve jméně souboru | opraveno (`quotepath` v `lib/aid-dispatch-contract.sh`) |
| acta 31. 8. `docker cp` do hlavního checkoutu | není vada pluginu (projektová past), vlastní chyba agenta |
| acta 31. 8. „moje chyba: status/verdict v kostře" | komponenta smazána (P096) |

**Co uděláme:** do projektových souborů zapíšu `> **UŽ ŘEŠENO …**` s důvodem.
**Práce:** 20 min.

### K10. Návrh UI (visual companion) — povinné kroky nic nevynucuje — PLATÍ

| Hlášení | Stav |
|---|---|
| agents 21. 9. „povinné kroky přeskočené, nic nespadlo" | platí |
| wan 19. 9. #1 „chybí pravidlo skládat z existujících komponent" | platí |
| wan 19. 9. #2 „příklad ‚kresli' povoluje kreslení od nuly" | platí |
| wan 19. 9. #3 „nic nevynucuje `proposal.json`" | platí |

**Co uděláme:** brána fáze návrhu u UI tématu vyžaduje `proposal.json`. Skill
dostane krok „vypiš sdílené komponenty a použij je". Příklad „kresli" zmizí.
**Práce:** ~0,5 dne.

### K11. Stránka plánu pro PM se vykresluje špatně — PLATÍ

| Hlášení | Stav |
|---|---|
| wan 2. 9. „místo názvu kroku useknutý Objective" | platí (`lib/aid-plan-summary.sh:194`, záměr, který nefunguje) |
| wan 2. 9. „u posledního kroku se sečtou všechna kritéria v souboru" | ověřit |
| acta 17. 9. „role `e2e` se usekne na `e`" | platí (`lib/aid-plan-summary.sh:135`, `[a-z-]*`) |

**Co uděláme:** název kroku z nadpisu, kritéria ohraničit sekcí, regex s číslicemi.
Patří do tématu 5 (zůstanou dvě stránky, ty musí sedět). **Práce:** ~2 h.

### K12. Jednotlivosti

| Hlášení | Stav | Co uděláme |
|---|---|---|
| acta #6 kolize čísel migrací | platí | obecná kontrola: `Create:` souboru, který na HEAD už existuje = chyba lintu (pokryje i migrace) |
| acta P024 #8 plán neuvádí testy, které krok rozbije | platí | skript v kontrole plánu: pro každý soubor z `Files:` najdi testy, které ho jmenují (stejný návrh agents 17. 9. #6) |
| acta P024 #9 ztracený výsledek kroku po ztrátě kontextu | platí | při dispatchi zapsat „dispatchnuto v <čas>, strom <hash>"; stav pak rozliší „nezačal" od „doběhl a výsledek se ztratil" |
| acta P024 #10 oprava smazala test a počet testů stoupl | platí | kontrola kroku porovná jména testů před/po; zmizelý test = nález |
| acta P024 #7 `queue.yaml` není platný YAML | ověřit | test čtení fronty přes `yq` |
| acta 30. 8. Stop hook opakuje výzvu i po předání kartou | ověřit (hooky P086/P087) | test |
| acta 2. 9. krok, který v režimu plánové větve nejde provést (potřebuje `main`) | platí | odstavec do `plan-writing.md` + otázka pro revizory plánu |
| acta 2. 9. plány obsahují nespuštěný kód (odloženo) | odloženo | patří k P092, beze změny |
| agents 17. 9. #4 a #6 opravy plánu vyrábějí vady, revize nekonverguje | část platí | potvrzovací kolo dostane seznam provedených oprav (u ACTA to zabralo); jinak řešeno v P093 |
| agents 17. 9. #5 drobnosti (snímek verze plánu, odkazy karty verifieru) | ověřit | jednotlivě |
| wan pre-push hook kontroluje prefix, ne verzi (odloženo) | ověřit | release guard z P089 hook vyměnil v tomto repu; zjistit, co instaluje `/aid-init` do projektů |
| wan brainstorm bez plánu nezanechá záznam (odloženo) | platí | `approve` i bez plánu (návrh 1 z hlášení) |

### Proces schránky

`docs/plans/plugin-issues-inbox.md` má 90 převzatých záznamů a u žádného v ní není
rozhodnutí. Rozhodnutí z 20. 9. se psala rovnou do projektových souborů, takže
schránka je jen kopie. **Návrh:** schránku zrušit. Jediný záznam je projektový
soubor, sběrný skript jen vypíše, co v projektech nemá rozhodnutí.
`bin/aid-plugin-issues-collect.sh` přestane kopírovat.

---

## Pět témat PM

### T1. Merge cesta 44 minut místo pod 20

**Zjištěno (naměřeno 23. 9. na eco-dev):** T0 753 s (75 sad, 978 testů), T1 1 895 s
(39 sad, 644 testů). Standard slibuje T0 ≤ 2 min a T1 ≤ 10 min. Spouštěč
(`scripts/tests/run-all-tests.sh`) pouští sady jednu po druhé. Na odebírání kódu
to nemá vliv, protože se neubírají testy. Hlídač rozpočtu pater
(`aid-test-tier-assign.sh`) nezasáhl a proč, zatím nevím. P081 měl 13 min, od té
doby přibyly sady.

**Co uděláme:** změřit každou sadu (`--timing`), nejdražší přeřadit do T2 (běží
v noci), opravit hlídač, aby na přetečení reagoval, a z brány udělat test, který
spadne, když T0+T1 přeleze 20 min. Paralelní běh sad je samostatná volba, viz
Rozhodnutí 2.

### T2. Měření času: jak dlouho trvalo tvořit plány „v Agentech" a „v AID"

Zadání chápu takto: vzít plány z posledních týdnů a pro každý změřit fáze (návrh →
schválený plán → vygenerované EPICy → dodáno) a najít, kde čas mizí. Zdroj: časové
záznamy plánů (`timeline.jsonl`, stavové soubory, git). Výstup: tabulka po plánech
a pět největších žroutů času s čísly. Viz otázka v Rozhodnutí 7.

Co už z hlášení víme (jako hypotézy k ověření měřením): kola kontroly plánu
(P005: pět kol, 3,9 M tokenů), generace padající na tvaru plánu (P024: 4 pokusy),
merge cesta 44 min, brány spuštěné znovu bez znovupoužití (13 min), slepé uličky
revizí (ruční obchvaty).

### T3. Paralelizace „bez ptaní, když ji plán navrhl"

**Stav:** paralelismus byl odstraněn v P078 (v2.82.0). `aid-plan-parallel-check.sh`
(194 řádků) ale pořád existuje a ověřuje vlny, které generátor zahodí
(`parallel_groups: []`, hlášení acta 1. 9. #5). IMP-179: podagent typu
`aid-orchestrator:*` bere pokyny z nainstalované kopie pluginu, ne z repa. Při
práci na pluginu tedy běží se starým protokolem.

**Návrh:** plán smí označit kroky jako nezávislé (stejná vlna). Controller je pak
pustí souběžně **bez ptaní**: max 2-3 agenti, každý ve vlastním stromu, výsledky se
slučují postupně a při konfliktu se krok přehraje sériově. Agent dostane protokol
vložený do zadání (obchází IMP-179). Kde plán vlnu neoznačil, běží se sériově.
Strop počtu agentů kvůli limitu účtu (8 agentů 20. 9. vyčerpalo limit za minuty).
Viz Rozhodnutí 5.

### T3b. Potřebuje PM vidět EPICy?

**Názor:** ne. EPIC je vnitřní jednotka: kus práce s vlastní revizí a bránami. PM
rozhoduje o plánu a přebírá dodávku. Dnes plán musí EPICy deklarovat
(`**EPIC N: …**`) a generace na nich padá (K3). Hlášení, stránky i Telegram
mluví o EPICech.

**Návrh:** plán obsahuje jen kroky a závislosti. AID si ho rozdělí sám podle grafu
závislostí a velikosti. PM vidí „krok 7 z 16", ne „E-097-2_2". Viz Rozhodnutí 4.

### T4. Auto-režim: kde mergovat

**Zjištěno (ověřeno):** výchozí je už teď merge po celém plánu
(`defaults/policies/plan-boundary-policy.yaml:28 default_mode: plan_branch`).
Ze 32 plánů se záznamem ve čtyřech projektech jich takhle běželo 30, zbylé dva
jsou staré. Druhý
režim (merge po každém EPICu) ale v kódu zůstává a nastoupí potichu, když projekt
nemá profily bran (`aid-plan-fsm.sh:9475`). `plan-start` navíc výchozí hodnotu
nepoužije a chce `--mode` napsat ručně.

Merge po plánu je i rychlejší: drahá merge cesta (44 min) se platí jednou, ne po
každém EPICu. Viz Rozhodnutí 3.

### T5. Telegram a stránky

**Zjištěno (ověřeno):** AID posílá na Telegram čtyři druhy zpráv z běhu:
předpoklad plánu selhal, předpoklad obejit, soulad s plánem zablokován, soulad
obnoven (`aid-fsm.sh` ~1994, 2383, 4782, 4790, 6038). K tomu noční report. Žádná
z nich neříká „potřebuju tě", ani „hotovo". Stránky vznikají tři: napsaný plán,
hotový EPIC a uzavřený plán (`lib/aid-artifact-obligation.sh`).

**Co uděláme (tvoje zadání, beru ho jako rozhodnuté):**
- Stránky dvě: **plán k rozhodnutí** a **plán dodán**. Stránka EPICu zmizí
  i s povinností a jejími testy.
- Telegram dva druhy: **„potřebuju tě"** (běh stojí na rozhodnutí PM, s odkazem na
  stránku) a **„plán dodán"** (s odkazem). Čtyři dnešní druhy půjdou jen do záznamu
  běhu a na stránku dodávky.
- Noční report viz Rozhodnutí 6.

---

## Navržené pořadí

1. **Hned po vydání P097 (malé, jasné):** K9 zavřít, K1 Codex, T5 notifikace
   + K11 stránka, T1 merge cesta (přeřazení sad).
2. **Tření agenta:** K2 revize, K3 lint = generátor, K7 rozsah + společné pravidlo
   „každé odmítnutí má cestu dál".
3. **Cesty a stav:** K5, K6 (ověření po P097), K8, K4.
4. **Měření T2** → na jeho číslech jeden plán: skryté EPICy (T3b) + paralelizace
   (T3) + jediný režim mergu (T4).
5. **Zbytek:** K10, K12, zrušení schránky.
