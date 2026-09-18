# Skriptové kontroly plánu - zadání

Podklad pro přestavbu kontroly plánu. Stav tématu a rozhodnutí: `interim-cp1-prestavba.md`.
Sepsáno 17. 9. 2026. Každá položka je ověřená proti dnešnímu kódu pluginu (v2.96.1), u každé je
řečeno, odkud požadavek pochází a proč ho má dělat skript a ne model.

## Proč to je hlavní páka

- Agents P005: 9 ze 16 nálezů první kontroly by chytil skript (neexistující proměnná, funkce, přepínač;
  řádky, které neodpovídají; kritérium, které platí už dnes).
- Oba piloty: opravy plánu vyrábějí 19 až 45 % nových chyb, skoro vždy „detail domyšlený místo ověřený".
- Jedno kolo modelových revizorů stojí desítky dolarů. Skript nestojí nic a běží vteřiny.
- Dnes je 28 kontrol „Completeness Gate" jen text ve skillu, který model hodnotí sám o sobě.

## Co lint umí už dnes (nesahat, jen zapojit)

`scripts/aid-plan-lint.sh`: tvar `Files:` bulletů, role z uzavřené množiny, povinná pole kroku,
`## Testing Strategy`, zákaz lidských sekcí, přehrání `Reuse check:`, chybějící `Reuse check:` u `Create:`,
pravidlo N+1 (krok zakládá soubor, další ho přebírá), standardy proti mapě, dokumentační povrchy,
sada jmenovaná jen v próze.

## Nové kontroly

Úroveň: **B** = blokuje vždy, **V** = varování ve výstupu (dostane ho revizor i autor).
Formát kroku, o který se kontroly opírají, je dnes pevný: `### Step N:` a tučná pole
`**Files:**`, `**Dependencies:**`, `**Acceptance Criteria:**`, `**Edge Cases:**`, `**Effort:**`, `**AID Role:**`.

### A. Vnitřní soudržnost plánu (jen z plan.md)

| # | Kontrola | Úr. | Odkud |
|---|----------|-----|-------|
| A1 | Graf z `**Dependencies:**` je acyklický a odkazuje jen na existující kroky. Dnes se cykly počítají až z plan.json po schválení plánu (`aid-c0-contract.sh`, knihovna `lib/aid-plan-graph.sh` existuje a je testovaná) | B | Gate 13, Codex check 2a |
| A2 | Čísla kroků jsou jedinečná a souvislá; tabulka `## High-Level Steps` sedí na `### Step N` (počet, čísla) | B | `identifier_domain` |
| A3 | Krok velikosti M nebo L má aspoň 3 kritéria přijetí a aspoň 3 hraniční případy | B | Gate 6, 7 |
| A4 | Zakázané fráze z tabulky ve `skills/plan-writing.md` (včetně českých: „atd.", „apod.", „a podobně", „dle potřeby", „případně") mimo bloky kódu | B | Gate 9; Agents: lint hlídá jen `etc.` |
| A5 | Každá cesta jmenovaná v kritériu přijetí nebo v `verification_pattern` je ve `Files:` některého kroku, nebo v repu existuje | B | nové |
| A6 | `verification_pattern`: platný typ (`cmd`, `must_not_exist`, `must_contain`), povinná pole typu, žádné `<...>` ani `{...}` zástupné znaky | B | Gate 20a-c |
| A7 | Krok, který soubor jen `Modify:`, a soubor v repu neexistuje ani ho dřívější krok nezakládá (pořadí podle A1) | B | Codex check 2b, částečně |
| A9 | Velikost: víc než 10 kroků nebo víc než 800 řádků. Hláška: „plán téhle velikosti se v pilotech nepodařilo dokontrolovat, zvaž rozdělení" (prahy doladit měřením) | V | ACTA P025: 16 kroků, 1211 řádků, nekonvergoval |
| A8 | Žádná prázdná sekce `##` a žádný text šablony ve složených závorkách | B | Gate 2 |
| A11 | Plán s `type: docs` v hlavičce (kontrolují ho jen dva generalisté) nesmí v `Create:`/`Modify:`/`Rewrite:` deklarovat kód: přípona `sh bash py js ts tsx jsx go rs java rb php sql yaml yml json toml` nebo cesta pod `scripts/`, `src/`, `bin/`, `lib/`. `Test:` se nepočítá | B | P093: hlavička nesmí schovat kód před čtyřmi revizory |

Vědomě NEzařazeno: „krok B čte pole, které krok A nevyrábí". Plán nemá pole vstupů a výstupů kroku,
ze kterého by to šlo spočítat, a `producer_consumer_order` v `aid-c0-contract.sh` kontroluje jen to,
že topologické pořadí respektuje hrany (po řazení tautologie). Zůstává revizorovi R4.

### B. Plán proti repu (ukotvení)

| # | Kontrola | Úr. | Odkud |
|---|----------|-----|-------|
| B1 | Každý identifikátor v zpětných apostrofech, který vypadá jako cesta, existuje, nebo ho zakládá `Create:` krok | B | Gate 17 |
| B2 | `Modify: \`soubor\` (lines ~N-M)`: soubor má aspoň M řádků; je-li u rozsahu jmenovaný symbol, leží v rozsahu ±30 řádků | V | Agents nález „symbol u (lines ~N-M)" |
| B3 | „smazat X" a `must_not_exist`: X dnes existuje | B | Gate 17d |
| B4 | Jmenovaná funkce, proměnná prostředí a přepínač příkazu: `grep` v repu najde definici, nebo ji zakládá krok plánu. Seznam se bere z bloku `## Resources Verification`, který šablona už má | B | Gate 17, 17e; Agents 9/16 |
| B5 | Externí příkaz ze seznamu zdrojů: `command -v` | V | Gate 17 |
| B6 | ID backlogu (`T-NNN`, `IMP-NNN`, `B-NNN`) nekoliduje s commity za posledních 24 h | V | Gate 17a |
| B8 | `Create:` cesta, která v repu už existuje (typicky číslo migrace obsazené jinou relací) | B | ACTA 17. 9.: migrace 0036 obsadila druhá relace |
| B7 | `verification_pattern` typu `cmd` nebo `must_contain`, který je splněný už na dnešním HEAD, nic nedokazuje | V | Agents nález „AC, které platí už dnes" |

B4 stojí na tom, že autor blok `## Resources Verification` vyplní. Skript proto kontroluje i opačný směr:
identifikátor v zpětných apostrofech v kroku, který není v bloku ani není cestou, je varování „nezapsaný zdroj".

### C. Po opravě plánu (nová tvrzení)

| # | Kontrola | Úr. | Odkud |
|---|----------|-----|-------|
| C1 | Před každou opravou se uloží snímek plánu do evidence (`kolo-N/plan.md`). Bez snímku oprava nezačne | B | oba piloty: verze se nesnímkují |
| C2 | Na přidané a změněné řádky (diff snímek → plán) se pustí B1, B3, B4 zvlášť a výsledek se vypíše jako „nová tvrzení opravy" | B | regrese 19-45 % |
| C3 | Hodnota nebo jméno změněné opravou, které se v plánu vyskytuje i jinde ve starém znění (stejný token ve starém i novém tvaru) | V | ACTA: „oprava na jednom místě, staré tvrzení zůstalo jinde" 4 z 8 regresí |
| C4 | Oprava sáhla na kroky, které nejsou v seznamu provedených oprav | V | kontrola rozsahu opravy |
| C5 | Oprava PŘIDALA chování: nový krok, nový `Create:`/`Modify:` soubor, nové kritérium přijetí nebo nový hraniční případ mimo kroky jmenované v nálezech. Hláška: „tohle je změna návrhu, ne oprava: vyjmi z plánu, nebo předlož PM" | B | ACTA 17. 9.: blokátory 26, 3, 11, 10, každá revize přidala mechanismus |

## Kdy a kdo to spouští (zadrátování)

Jeden příkaz, jeden výstup: `aid-plan-check.sh <plan>` spustí lint + A + B (+ C, když existuje snímek)
a zapíše `evidence/<plan>/plan-check.json` s otiskem plánu (sha256), výsledkem a seznamem varování.

1. **Autor po napsání a po každé opravě.** Ne jako věta v textu: balík pro revizory skládá skript
   (`aid-review-packet.sh`) a ten odmítne balík složit, když `plan-check.json` chybí, neprošel, nebo jeho
   otisk nesedí na plán. Bez balíku není čím revizory spustit. Agent nemusí nic zjišťovat, chybová hláška
   říká přesně jeden příkaz, který má pustit.
2. **Před generováním úkolů.** `aid-generation-readiness.sh` dnes volá lint; nově ověří `plan-check.json`
   se sedícím otiskem.
3. Varování (V) neblokují, ale jdou do balíku revizorům jako „na tohle se podívej".

## Co s dnešní „Completeness Gate" (28 kontrol ve skillu)

- Strojové (4, 5, 6, 7, 9, 13, 14, 17a, 17b, 17d, 17e, 18, 20a-c): z textu skillu zmizí, nahradí je věta
  „pusť `aid-plan-check.sh`, dokud neprojde".
- Kontrola 8 (rozsah řádků u každého `Modify:`) se ruší jako povinnost, nikdy nebyla vynucená; zůstává B2 tam, kde rozsah je.
- Úsudkové (1-3, 10-12, 15, 16, 17c, 19, 21): přesunou se do otázek revizorů, autor je nehodnotí sám o sobě.

## Povinné přílohy změny (pravidla repa)

Řádky v `defaults/enforcement-registry.yaml` pro A, B, C a pro podmínku balíku (typ, zdroj, závažnost,
mechanismus vynucení), testy v patře t0/t1, úprava `commands/aid-plan.md` a `skills/plan-writing.md`,
oba CHANGELOGy, a ověření na zkušebním projektu `aid-testbed` včetně sabotovaného plánu
(jedna záměrná vada na každou novou kontrolu, očekává se odmítnutí).

## Jak to ověřit dřív, než se to postaví

Uložené verze plánů z pilotů jsou hotová zkušební sada: ACTA `plan-v3-pred-revizi.md` → `plan-v4.md`
a Agents `plan-v2` až `plan-v5`, ke každému přechodu je známý seznam regresí. Prototyp B a C se pustí
na tyto dvojice a spočítá se, kolik známých regresí a nálezů chytil. Cíl: aspoň polovina regresí z oprav.

## Odchylky implementace od zadání (po nezávislém ověření 17. 9. večer)

Ověřovatel (Opus, čerstvý kontext) potvrdil čtyři nálezy skriptu ručně a tři sabotované kontroly
testy chytily. Před mergem opraveno: B4 blokovalo jména, která plán sám zakládá, a tečkované názvy;
pád na plánu bez kroků; A3 padalo na české znaky v regexu; B7 spouštělo příkazy z plánu ve
výchozím stavu (teď jen s `--run-cmds`); B5 zahazovalo celý řádek kvůli slovu docker; A4 chybělo
„případně". Brána před generováním nově zapisuje `plan-check.json` do evidence plánu.

Vědomě odložené (backlog, rozhodne PM):
- A2 tabulka vs kroky, A8 zástupné znaky, B1 cesta mimo repo, B3 „smazat X" v próze: varování místo blokace.
- A5 nekryje `verification_pattern.file`; B4 nekontroluje přepínače příkazů (`--x`); C2 přehrává jen cesty.
- C1 (snímek před opravou) a celá rodina C nemají volajícího: čeká na skript balíku pro revizory (krok 2).
  Registr je vede jako advisory, ne fail.
- Výkon: C2 a B10 dělají jeden grep přes repo na token; sabotovaný plán v `aid-testbed` chybí.
- Poctivá míra na Agents: skript kryje 3 až 5 z 16 nálezů prvního kola, ne 9 (F2 env proměnné, F4/F5
  rozsahy řádků, půl F7). Na ACTA před revizí nedává blokaci; jeho hodnota je v kontrolách po opravě.
