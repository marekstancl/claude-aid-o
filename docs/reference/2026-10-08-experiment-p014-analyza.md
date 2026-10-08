# Experiment P014: vyplatí se AID? Rozbor a doporučení (8. 10. 2026)

Podklady: `/opt/eco/projects/agents/docs/reference/2026-10-07-experiment-p014/` (README, deník,
metriky, akceptace, slepá hodnocení), evidence AID v `agents/.aid-o/work/evidence/` (P014, E-014-*),
přepisy oken ramen, tři nezávislé rozbory (rameno A, B, C) zadané 8. 10. 2026, zápisy
`aid-plugin-issues.md` projektů agents, wan, aid-orchestrator (6.–8. 10.). Čísla jsou z těchto
zdrojů; kde je něco odhad, je to řečeno.

## 1. Co se měřilo a jak to dopadlo

Tři ramena, totéž zadání (9 bodů „hotovo, když“), vlastní pracovní kopie, vlastní testovací DB.

| | A: jen zadání, Fable, bez plánu | B: plán AID + solo okno Opus + Codex po krocích | C: celé AID (`/aid-run --auto`) |
|---|---|---|---|
| Akceptační kontroly (spuštěním) | **9/9** | 8/9 (K2) | 7/9 (K2, K7) |
| Slepí hodnotitelé (Codex, Claude) | 1./1. | 2./2. | 3./3. |
| Aktivní čas | **1:06** | 1:26 | 3:34 (10:22 celkem, ~7 h stání) |
| Cena okna (Claude + Codex, ceník) | 44,5 USD | **39,1 USD** | ≈ 68–72 USD |
| Tahů modelu / přepisů | 187 / 1 | 283 / 7 | 842 / 54 |

**Co ve výsledku chybí: cena plánu.** Ramena B a C stavěla z plánu, který vznikl PŘED startem
(7. 10., 15:27–18:26 UTC): zadání, plán 559 řádků, tři kola CP1 po šesti revizorech
(158 nálezů), zúžení rozsahu. Měřeno z přepisu plánovacího okna a `measurement.json` kol:

| Příprava před startem ramen | čas | cena |
|---|---|---|
| plánovací okno (Opus; zadání, plán, opravy po kolech) | ~3 h | ~37 USD (dopočet z tokenů) |
| revizoři CP1, 3 kola × 6 rolí | 51 min z toho | 44,8 USD (podle AID) |
| **celkem** | **~3 h** | **~80 USD** |

Poctivé účetnictví celé cesty od zadání k hotovu:

| | A | B | C |
|---|---|---|---|
| čas | 1:06 + zadání (~30 min) | 1:26 + ~3 h plán | 3:34 + ~3 h plán (+7 h stání) |
| cena | ~45 USD + zadání (~10 USD) | ~39 + ~80 = **~120 USD** | ~70 + ~80 = **~150 USD** |
| kvalita | 9/9 | 8/9 | 7/9 |

Rameno A přitom těžilo z přípravy, kterou nezaplatilo: zadání bylo zúženo (přestavba zrcadla
do P015) právě proto, že CP1 našla, že původní rozsah nejde do dnešního schématu zapsat. Bez
té revize by A dostalo širší zadání a nevíme, jak by dopadlo.

## 2. Proč to dopadlo takhle (ověřeno v evidenci)

### 2.1 Zadání bylo přesnější než plán, a plán zadání změkčil

- Bod 2 zadání: „neznámá hodnota v konfiguraci skončí chybou při startu, ne tichým přechodem na
  Freelo.“ Plán (559 řádků): v Error Handling „výjimka při startu **úlohy**“, v Edge Cases
  „konfigurace bez klíče → bere se `freelo` a zapíše se do logu“ (opak zadání), a v Success
  Criteria plánu bod 2 **úplně chybí** (8 bodů místo 9; vypadl i „e-mail z těla se ignoruje“
  a „patro podle ceny“).
- B i C stavěly z plánu → obě odmítají vadnou hodnotu až u konkrétní práce, chybějící klíč = Freelo.
  A stavělo ze zadání → služba, brána i čtečka padnou při startu do 1 s (spuštěno měřičem).
  Tenhle bod rozhodl o pořadí.
- Rozhraní podle plánu bylo „Freelo-tvaré“ (údaje, projekt, `ChybaFreela` ven); A bez plánu
  udělalo rozhraní neutrální, což oba hodnotitelé chválí jako jediné splnění přání PM
  („někdo jiný si dodělá svůj konektor“).

### 2.2 Kontrola plánu (CP1) zadání nevidí, a kritik neběžel

- Balíček CP1 nese `plan.md`, plan-check, standardy, lint. **Zadání PM v něm není.** Žádná ze
  šesti rolí nemá otázku „odpovídá plán tomu, co PM chtěl?“ Role porovnávají plán s kódem a
  plán sám se sebou.
- Jediný mechanismus, který zadání drží (kritik, 2.112.0), **neběžel**: plán vznikl ze zadání
  v docs, ne z brainstormu, kritik chce interim, a nic neodmítne CP1 bez kritika.
- Revizor CP1 (behaviour_edges, kolo 1) bod 2 viděl a navrhl ho **vypustit** („kritérium si
  plán vyrobil sám“) — bez zadání v ruce považoval požadavek PM za výmysl plánu.
- Plán, který se stavěl (`25b6f39`), **neprošel žádným kolem CP1** — po kole 3 (4 otevřené
  blokery, 26 majorů) se zúžil rozsah a brána CP1 pustila výsledek přes `fix_check`.

### 2.3 Revize AID optimalizují artefakt proti sobě, ne proti zadání

- CP3 E1 (`epic_behaviour-1`, major): „vadná aplikace by zastavila čtečku všech“ → přijato jako
  `scope_amended` → čtečka místo chyby aplikaci přeskočí. Provozně obhajitelné, **proti bodu 2**,
  nikdo to s definicí hotovo nesrovnal. Spustilo kaskádu dvou dalších oprav v CP7.
- Bilance 34 nálezů CP2/CP3/CP7 v C: ~7 výsledek zlepšilo (výběr v bráně, PyYAML v CI, retence
  `sessions.email`, počty testů, CHANGELOG, text stránek), 1 zhoršil, zbytek nic. Za to ~43 USD
  a ~118 min. **Na K2 a K7 nepřišel nikdo z 34 revizních běhů**, protože nikdo program se
  špatnou konfigurací nespustil a test cesty nikdo nepustil s mutací.
- V B revize Codexu (9 relací, ~5 USD, 19 nálezů, ~17 skutečných) zvedly body 2 a 7 z „částečně“
  na „platí“ — levná, na diff a zadání kotvená revize funguje; drahá, mnohorolová, nad celým
  packetem, méně.

### 2.4 Kde šly peníze a čas v C

- Implementace: 68 min, 11,6 USD (19 % ceny C). Pět implementátorů dohromady 7,75 USD.
- Revize a opravy po nich (CP2+CP3): 54 min, 26,4 USD (44 %). Uzavření plánu (CP7, 3 pokusy):
  64 min, 16,4 USD (27 %). Orchestrátor 70 M tokenů, 21 USD.
- Z 231 volání nástrojů orchestrátoru je 141 (61 %) účetnictví (stav, kontrakt, evidence),
  4 běhy testů. 11 z 25 commitů je režie. 6× `scope_amended`, 9× odmítnutí/obejití.
- Brány EPICů profilu `full` **přeskočily testy asistenta** (`asistent_t0`, t1 v žádné bráně),
  kde leží většina nových testů. `plan_diff`: „skipped, 27 odrážek neměřeno“ — AID strojově
  neověřil ani jedno akceptační kritérium. Dvě ze čtyř „záruk“ AID byly v tomhle běhu prázdné.
- Blokace 7 h: pokyn dozoru (docs do vlastní kopie) × neměnný kontrakt s absolutní cestou do
  cizího repa × klasifikátor zamítl `--force`. Příčina půl na půl dozor/AID, délka = noc.
  **Bez blokace má C 3:34 aktivně, 2,5–3× víc než A i B.** Blokace pořadí nevysvětluje.

### 2.5 Co AID udělalo lépe (poctivě)

- Bezpečnostní revize CP2 našla retenci `sessions.email` (osobní údaj navždy u relace). A ani B
  to nemají; PM to převzal do main. Cena ~2,3 USD. Jediný věcný rozdíl ve prospěch AID.
- CP2 našlo chybějící PyYAML v CI; A na to po sloučení narazilo (CI spadlo).
- CP7 vynutilo správné počty testů v Docusauru (bod 8 díky ní prošel).
- Záznam: 54 přepisů, timeline, evidence; víme přesně, co se stalo. U A víme jen z jednoho přepisu.

### 2.6 Byla výhra A náhoda?

Ne náhoda, ale ne čistě „Fable“. Co rozhodlo (rozbor přepisu A):
- **Zadání** (měřený výchozí stav, tabulka „kde co je“, 9 měřitelných bodů, výčet „co nepatří“);
  A vzalo bod 2 jako návrhové pravidlo v prvním napsaném souboru.
- **Disciplína modelu**: 15 min jen čtení (60 čtecích příkazů, dávkovaně), pak kód, pak 8 kol
  oprav podle testů, procesy spouštělo, ne četlo.
- **Jedna revize na konci** (Codex, 5 nálezů, všechny zapracované) — test „služba při startu
  spadne v samostatném procesu“ vznikl až po ní a právě ten chytil mutaci.
- **Dozor a štěstí**: A začalo v hlavním checkoutu (kde pracovalo C) a dozor ho přesunul; chtělo
  přepsat zadání v kopii (zamítnuto) a náhodou četlo zúžené z mainu; docs kopii nařídil dozor.

Co A **vynechalo** a solo cesta vynechá znovu: retenci osobního údaje (dvě stopy v kontextu,
`uklid.py` nikdy neotevřelo, revizorovi to nezadalo), rozdíl rozložení repo vs. hostitel
(test hledal bránu v `bin/`, na hostiteli je v `telegram/` → **nasazení 8. 10. spadlo**
a vrátilo zálohu; nechytil to nikdo ze tří vrstev hodnocení), build Docusauru, mutaci M5b.
Kontext A rostl na 598 k bez zhuštění za 66 min — na 2–3× větší úloze by narazil.

**Jedno měření, úloha příznivá pro solo** (jedno repo, rychlé testy, přesné zadání, backend,
žádné UI, žádná migrace dat se zákazníky). Nevíme, jak by A dopadlo na Opusu (rameno A mění
model i postup naráz), ani na úloze, kde zadání nevyjmenuje dotčená místa.

## 3. Co je strukturální (opakovalo by se) a co náhodné

Strukturální, doložené i mimo P014 (zápisy P010, P012, P013, P108):
1. **Smyčka revizí nemá kotvu v zadání.** Kola optimalizují plán a kód proti sobě; nálezy
   vyrobené opravami (P010: 4 z posledních nálezů, P108: 4× za sebou, P012 CP3: nový blocker v každé
   opravě). 2.114.0 to začalo měřit, ale příčinu neřeší.
2. **Cena je v počtu rolí × velikost packetu × počet kol**, ne v psaní kódu. CP1 u 14 plánů
   za dva týdny: 11–45 USD a 46–158 nálezů na plán, průměr ~28 USD, než se napíše řádek kódu.
3. **Účetnictví a kontrakty zastavují běh** častěji, než chrání: neměnný kontrakt, dvě kopie
   deníku, bracket, `codex-probe.json`, karta, které PM nerozumí (P108 bod 19), delegace na Codex,
   kterou AID neumí provést (P013-14/16).
4. **Záruky, které se nespustí:** brány bez testů asistenta, `plan_diff` nic neměří, CP7 chce
   řádek brány pro testy, které projekt vědomě drží v noci.

Náhodné / přípravné: blokace 7 h (pokyn dozoru), DB vlastník, docs worktree.

## 4. Co z toho plyne

**U úloh typu P014** (jedno repo, rychlé testy, zadání, které vyjmenuje dotčená místa a má
měřitelné body hotovo, bez UI a bez migrace zákaznických dat) dodal model s dobrým zadáním a jednou
kotvenou revizí výsledek za hodinu a 45 USD; AID na téže úloze stál 3× víc času i peněz a dodal
hůř, a příčiny jsou strukturální (revize bez zadání, cena = role × packet × kola, účetnictví, které
stojí víc než pojistky). **Pro tenhle typ úloh se AID jako výchozí cesta nevyplatí.** Co z AID stojí
za to zachovat jako pojistky: bezpečnostní otázka u změn dat, měření, izolace v pracovní kopii,
záznam, companion pro UI, a hlavně **tvar zadání**, který je dnes jeho nejcennější výstup.

Co experiment neměří a kde závěr neplatí automaticky: úlohy delší než jedno okno (kontext A
598 k za 66 min), práce ve více repozitářích nebo týmech souběžně, předání mezi lidmi a okny,
spor o původ rozhodnutí, UI, migrace dat. Tam má evidence a dělení na kroky hodnotu, kterou P014
nezměřil. Co by závěr vyvrátilo: opakování s týmž modelem ve všech ramenech, úloha na druhé straně
hranice (delší, více rep, UI) se stejným pořadím A < C, a vyčíslení odvrácených vad (retence
osobního údaje) proti ceně revizí.

Rozhodnutí a volby jsou v chatu (8. 10. 2026). Co bude rozhodnuto, sem doplnit.

## 4a. Výhrady oponenta (Codex, 8. 10. 2026) a jak s nimi

1. Akceptační kontroly vznikly po zhlédnutí A a B; běžné testy a mutace mají všechna ramena
   stejně (12/13). → Pořadí v P014 platí, zobecnění je slabší; příště kontroly zmrazit předem.
2. „Za hodinu a 45 USD“ uspělo jen rameno s Fable; B na Opusu trvalo déle a nesplnilo K2;
   model a postup se měnily naráz. → Opakování se stejným modelem v ramenech (viz rozhodnutí 2).
3. Čas přípravy je nástěnný, čas ramen aktivní; plán je zčásti použitelný dál (podklad P015);
   cena C je dopočet. → Účty jsou odhad ±15 %, rozdíl 3× ale přežije i chybu odhadu.
4. Počet nálezů není hodnota pojistky: retence osobního údaje a PyYAML v CI jsou konkrétní
   odvrácené vady, jejichž provozní cena vyčíslená není. → Souhlas; proto se bezpečnostní otázka
   a kontrola prostředí (CI, hostitel) do lehké cesty přebírají.
5. P014 nezkouší dlouhou úlohu, souběh, předání po výměně kontextu; 54 přepisů má hodnotu při
   sporu o původ. → Zapsáno výš jako mez platnosti.
6. A těžilo ze zúženého zadání po placené CP1 a mělo dozor; cena dozoru a oprava po spadlém
   nasazení v 45 USD není. → Pravda; poctivý účet A je ~45 + zadání + ~10 min dozoru + oprava
   (`390eab1`); stále zlomek B/C.
7. Prázdné brány a `plan_diff` jsou nález o konfiguraci běhu, ne o AID s opravenými branami;
   blokace je i vada přípravy. → Souhlas; i bez blokace a s branami je C 2,5–3× dražší na čase
   (revize a uzavření, ne brány).
8. Doporučení přesahuje jedno backendové měření. → Proto je rozhodnutí formulované pro úlohy
   typu P014 s hranicí a druhým experimentem na druhé straně hranice, ne jako konec AID.

## 5. Nové zápisy v plugin issues (6.–8. 10.), roztříděné

- **Tření těžké cesty** (kola, kontrakty, delegace): P012 (10 zápisů: delegace na Codex nejde
  provést, karta bez otisku, deník blokuje kolo, AC „po nasazení“, CP3 se živí sám, codex-probe
  ve worktree, dvě cesty v jedné odrážce Files, amend-scope jen z plan.json EPICu, absolutní
  artefakt v cizím repu, auto-mode-state jeden na projekt); P013 (17 zápisů: plugin.yaml
  zastaralý, start z CP1 bez jednoho příkazu, deník v hlavní kopii, AC na živém Freelu, CP1
  schválila neexistující stránkování API, revizoři sekvenčně, standing chce --step, D4 výjimka,
  codex-probe blokuje merge, amend-scope rozbije hash, delegace na Codex 3×, override 4 kol);
  P108 WAN (19 bodů: execution.yaml upgrade zahodil klíče, delta kolo kvůli .aid-o commitům,
  git add -f vs. git rm, env bran z worktree, obrazy compose, fix_of role, verify binding,
  form_invalid k fixerovi, nové nálezy po poslední revizi, prepare-plan verze, Codex at capacity,
  freeze konflikt deníku, cílený důkaz místo noční brány, karta uzávěru nesrozumitelná);
  P014 C (generace na main, docs v jiném repu, absolutní artefakt, scope_amended unknown).
- **Zjištění experimentu** (bez návrhů, viz výše).
- **/aid-ui studio** (aid-orchestrator 7.–8. 10.): jednorázový odkaz spotřebuje náhled chatu;
  relace v paměti po pádu; `studio` nerestartuje kód. Větev P103.
- **Jiné (2.114.0):** plan_diff gate proti živému cizímu repu; ověřovací skript proti systémovému
  systemctl.

Většina z ~55 nových zápisů je tření mechanismů těžké cesty (kola, kontrakty, deníky, karty).
Pokud se výchozí cesta změní, většina z nich ztratí naléhavost; opravovat je jednotlivě znamená
dál stavět to, co experiment zpochybnil.
