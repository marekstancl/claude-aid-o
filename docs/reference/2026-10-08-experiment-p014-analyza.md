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


## 6. Rozhodnutí 1 rozvedené: lehká cesta po částech, s důkazy (doplněno 8. 10. odpoledne)

PM: „na základě pěti vět se nedá rozhodnout, potřebuju důkazy, že to pomůže.“ Níže je lehká cesta
rozložená na šest částí; u každé je (a) co má dělat, (b) důkaz, že to funguje, z P014 nebo
z nových zkoušek 8. 10., (c) co to stojí, (d) co se tím nezíská. Zkoušky 8. 10. = tři běhy Codexu
nad skutečnými podklady P014 (`scratchpad/probes/p1..p3`), každý read-only, bez plánu a bez AID;
zadání i výstupy jsou uložené vedle tohoto souboru v `2026-10-08-experiment-p014-zkousky/`.

### 6.1 Zadání ve tvaru P014 jako standard (ne plán)

(a) Každá úloha dostane zadání s: PM doslova, změřený výchozí stav (cesty, funkce, data),
„co udělat“ s hranicí „co sem nepatří“, tabulka „kde co je“, pravidla, a číslované
měřitelné body hotovo. Lint odmítne zadání bez měřeného stavu nebo s neměřitelným bodem.
(b) Důkaz: rameno A vzalo bod 2 zadání jako návrhové pravidlo v prvním napsaném souboru
(přepis 20:43) a jako jediné ho splnilo; B a C stavěly z plánu, který ten bod ztratil. Zadání
P014 zabralo PM a agentovi ~30 min a 14 bodů tabulky „kde co je“ dalo A celou orientaci: 15 min
čtení, žádný ztracený krok. Opak: P013-6 (CP1 schválila kritérium o stránkování API, které
neexistuje; šest revizorů, dvě kola) — zadání s měřeným stavem by to neobsahovalo.
(c) ~30–60 min PM + agent na úlohu, lint 1 den práce (gramatika už existuje v `aid-plan-lint`).
(d) Nedá: rozklad na kroky pro souběžnou práci víc oken.

### 6.2 Jedna levná revize zadání (Codex, read-only nad repem)

(a) Před startem jedna revize zadání proti kódu: co nejde splnit, co zadání nevyjmenovává,
co nejde změřit. Nálezy zapracuje PM/agent do zadání, ne do plánu.
(b) Důkaz (zkouška P1, 8. 10.): Codex dostal PŮVODNÍ, široké zadání P014 (`ce43dd3`, před
zúžením) a kopii repa před P014. **Našel totéž, co tři kola CP1 (18 revizorů, 158 nálezů,
44,8 USD):** zrcadlo `hlaseni_stav` je přes `ticket_id` vázané na `tickets`, `conversation_id`
je povinný, ruční hlášení nemá kam uložit vazbu na člověka → nutná migrace (jeho nález 1). To je
přesně důvod, proč PM po třetím kole CP1 zúžil rozsah. K tomu 8 dalších věcných bodů (oznámení
neunese můstek po zavření widgetu, měření nemá schéma ani definici období, konfigurace ve třech
místech, stránka portů předbíhá kód). Rameno B totéž: 4 nálezy Codexu u zadání, všechny skutečné,
předešly chybám v kódu (prázdný e-mail, výjimka mimo karanténu, chybějící vzorek, relace bez
e-mailu). Cena jedné takové revize: 1–3 USD, 5–10 min.
(c) Viz výše. (d) Nedá: revizi po krocích (tu dá 6.5 jednou na konci).

### 6.3 Zadání v ruce každého revizora (a kritik povinný, pokud zůstane těžká cesta)

(a) Kdokoli něco posuzuje (zadání, plán, diff), dostane zadání PM a otázku „zachovává, změkčuje,
vypouští, odporuje?“ bod po bodu.
(b) Důkaz (zkouška P2, 8. 10.): Codex dostal zadání + plán P014 a tuhle otázku. **Během jednoho
běhu našel, že Success Criteria plánu bod 2 úplně vypouští**, body 1, 4 a 8 vypouští zčásti
(test procházející zdroje, „e-mail z těla se ignoruje“, patro podle ceny) a že architektura říká
čtyři úkony, krok sedm. Tři kola CP1 (bez zadání) to neviděla; jeden revizor navrhl bod 2 vypustit.
Cena: ~1 USD.
(c) Změna packetu CP1/CP2/CP3/CP7 o jeden soubor; kritik povinný = jedno odmítnutí v `prepare`.
(d) Nedá nic navíc, jen odstraní slepotu; platí i pro těžkou cestu, pokud zůstane.

### 6.4 Samostatné okno v pracovní kopii, commit po bodech hotovo

(a) Jedno okno (Opus nebo Fable), vlastní worktree, žádné EPICy, kontrakty ani kola během práce;
commit po každém splněném bodu hotovo (ne jeden na konci jako A), deník tření jako dnes.
(b) Důkaz: A 1:06, B 1:26 (B commitovalo po krocích a první výsledek mělo za 20 min — to je
lepší zvyk než A). C 3:34 aktivně, 61 % tahů orchestrátoru účetnictví, 4 běhy testů proti ~25 u A
a ~72 u B. Za 14 dní stály revize AID 41–261 USD na plán a plány trvaly 12–116 h od první
revize k uzavření (tabulka níže).
(c) Nic nového; `git worktree` a `aid-plugin-issues.md` existují.
(d) Nedá: souběh víc oken na jedné úloze; obnovu po přerušení z evidence (zůstává přepis + git);
PM karty během práce. Rizika doložená u A: kontext 598 k bez zhuštění (hranice: úloha
stupně ≤ 4 nebo rozdělit na dvě zadání), omyl v checkoutu (zadání musí jmenovat kopii).

### 6.5 Přijetí spuštěním proti bodům hotovo (měřič)

(a) Po dokončení jeden měřič (subagent s vlastní DB, síť zakázaná) spustí každý bod hotovo tak,
jak je napsaný (start s vadnou konfigurací, celá cesta, mutace), ne čtením kódu.
(b) Důkaz: v P014 měřič našel K2 u B i C a K7 u C — vady, které **34 revizních běhů AID
(CP2, CP3, CP7) a 9 revizí Codexu v B neviděly**, protože nikdo proces nespustil. Mutace ukázaly
u všech ramen stejnou díru (M5b). Cena měřiče: ~10 USD a ~20 min na rameno (subagent `agent-a7`:
27,6 M čtení cache, 0,9 M zápis).
(c) Nástroje už existují (`skills/srovnavaci-experiment-aid/nastroje`, `sablona-zadani-merice.md`);
zobecnit na „měřič hotovo“ = 1 den.
(d) Nedá: nic o kvalitě kódu mimo body hotovo (to dělá 6.6).

### 6.6 Jedna revize celého diffu kotvená na zadání + bezpečnostní a provozní seznam

(a) Na konci jeden nezávislý revizor (Codex; u změn dat nebo oprávnění druhý, Opus, s otázkami
bezpečnostní role AID) dostane zadání, diff a krátký seznam: nový osobní údaj a jeho mazání,
rozložení repo vs. hostitel (deploy-manifest), nové závislosti v CI i na hostiteli, build
dokumentace, únik údajů do logu/Telegramu, hranice účtů.
(b) Důkaz (zkouška P3, 8. 10.): Codex dostal zadání + diff ramene A + ten seznam. **Našel obě
vady, které A vynechalo a které nechytila žádná ze tří vrstev hodnocení experimentu:** retenci
`sessions.email` (nález 1, s odkazem na `uklid.py:295`) a rozložení na hostiteli (nález 2:
test čte bránu z `bin/`, manifest ji kopíruje do `telegram/` — přesně to, na čem nasazení A
8. 10. spadlo). Nenašel chybějící PyYAML v jobu brány v CI (řekl „bez nálezu“, protože
`requirements.txt` ho má — job brány ho ale neinstaluje): seznam musí říkat „každý job CI zvlášť“.
V P014 to našlo CP2 až ve druhém kole. Cena: ~2 USD, 10 min. Rameno A: jeho vlastní závěrečná
revize Codexem dala 5 nálezů, všechny zapracované, včetně testu startu služby, který pak chytil
mutaci. Rameno B: závěrečná revize zvedla body 2 a 7 z „částečně“ na „platí“.
Bezpečnost: v evidenci AID je **71 opravených bezpečnostních nálezů** (blocker/major) ze CP2/CP3
za 14 dní (podvržené cesty, únik údajů do chybového výstupu, padělané schválení PM, symlinky
při mazání, XSS přes font). To je skutečná hodnota role `security`; lehká cesta ji neztrácí,
když tuhle roli pustí jednou na konci (a u rizikových kroků i uprostřed) místo v každém kole.
(c) ~2–10 USD na úlohu. (d) Nedá: nálezy po krocích uprostřed práce — u úloh, kde chyba
v kroku 1 zdražuje kroky 2–5, je to ztráta (viz hranice v 6.8).

### 6.7 Čísla za 14 dní (všechny projekty, jen revizoři, bez orchestrátoru a implementátorů)

| Plán | CP1 | CP2+CP3 (kol) | CP7 (pokusů) | revize celkem | nálezů / opraveno kódem | od 1. revize k uzavření |
|---|---|---|---|---|---|---|
| agents P010 | 43 | 137 (45) | 80 (20) | **261 USD** | 178 / 64 | 116 h |
| wan P108 | 29 | 149 (36) | 52 (8) | **229 USD** | 76 / 23 | 74 h |
| agents P013 | 37 | 106 (26) | 17 (3) | 160 USD | 67 / 17 | 24 h (nedokončeno) |
| agents P012 | 34 | 87 (27) | 37 (7) | 159 USD | 66 / 26 | 33 h |
| agents P014 (C) | 45 | 47 (14) | 18 (3) | 109 USD | 35 / 12 | 12 h |
| aid-orch. P102 | 24 | 41 (22) | 8 (2) | 73 USD | 34 / 10 | – |
| agents P009 | 30 | 21 (13) | 17 (4) | 69 USD | 18 / 3 | 63 h |

Kódu se dotkla třetina nálezů (P010 36 %, P108 30 %, P012 39 %, P014 34 %); 10–16 % padlo na
formě; zhruba polovina zůstala otevřená, přenesená nebo routovaná. Cena jednoho nálezu, který změnil
kód: 4–10 USD. V rameni B stál jeden skutečný nález Codexu ~0,3 USD (19 nálezů, 17 skutečných,
5 USD). Zkoušky 8. 10.: tři revize, které našly totéž co CP1, odhalily změkčení plánu a obě
díry ramene A, dohromady pod 10 USD a půl hodiny.

### 6.8 Hranice: kdy lehká cesta ne

Z dat P014 a zápisů P010/P012/P013/P108 lehká cesta neunese: (1) úlohu nad stupeň 4 nebo takovou,
kde kontext jednoho okna překročí ~600 k (A: 598 k za 66 min) — rozdělit na dvě zadání, nebo
těžká cesta; (2) souběžnou práci víc oken na jedné úloze; (3) úlohu s víc než jedním cizím
repozitářem, kde dnes i AID stojí (kontrakt s absolutní cestou); (4) UI úlohu bez companionu —
companion zůstává povinný (2.114.0). Pro (1) a (2) zůstává těžká cesta, ale až po 6.3.

### 6.9 Co by ukázalo, že lehká cesta nepomáhá

Druhý experiment na úloze z druhé strany hranice (UI nebo dvě repa nebo migrace zákaznických dat),
ramena: solo Opus se zadáním + 6.2/6.5/6.6, solo Fable totéž, těžká cesta po 6.3. Kontroly zmrazené
před startem, stejný model v ramenech A. Pokud těžká cesta dodá lépe nebo rychleji při poctivém
účtu (včetně plánu), lehká cesta se omezí na úlohy do stupně 3.

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
