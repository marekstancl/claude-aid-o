# P094 — akceptační běh nové revize kroku a volba modelu (krok 13)

Zapsáno PŘED během, 19. 9. 2026.

- Vzorek: týchž 20 diffů jako v kroku 1 (`fixtures/step-review/sample.json`; 6 se zaznamenaným `fail`, 14 čistých).
- Tok: `aid-step-check.sh` nad každým diffem (odstupňovaný worktree na revidovaném commitu), pro verdikt `review`/`review+security` jedno kolo `aid-review-round.sh` s rolemi `step_generalist` (+ `step_security` při bezpečnostním vzoru); revizoři dispečováni nástrojem Agent po dvou, každý s otevřenou a uzavřenou závorkou `aid-emit-dispatch.sh`; odpovědi projdou adjudikátorem (nález bez příkazu nebo `path:line` se nepočítá).
- Dva kandidátské modely: **Sonnet** (`sonnet`) a **Opus** (`opus`), v tomto pořadí. Codex na cp2 nefiguruje.
- Strop: **30 USD za oba nové běhy dohromady** (cena z `defaults/prices.yaml`, blended sazba na součet tokenů z nástroje Agent). Při dosažení stropu se běh zastaví a do tabulky se zapíše, co doběhlo; volba modelu používá jen položky dokončené oběma modely.
- Pořadí u Opusu, kdyby strop tlačil: nejdřív 6 selhaných vzorků, pak čisté.
- Baseline (krok 1): dnešní tok se Sonnetem, 0.365 USD na krok, 1.22 USD na potvrzený nález, 0 z 8 skutečných chyb nalezeno, 2 potvrzené nálezy na selhaných vzorcích.

## Pravidlo volby (V8), stanovené před výsledky

Model **kvalifikuje**, když jeho USD na krok není vyšší než baseline (0.365) a jeho USD na potvrzený nález je nižší než baseline (1.22). Z kvalifikujících vyhrává ten s více potvrzenými nálezy; při rovnosti levnější na krok. Nekvalifikuje-li žádný, nález jde zpět do kroku 3 nebo 6 (nikdy do zmírnění pravidla). Podmínka V1: potvrzené nálezy na šesti selhaných vzorcích ve zvolené konfiguraci ≥ 2 (baseline).

Potvrzení nálezů (`findings_confirmed`) dělá controller čtením kódu po běhu; sporné nálezy se označí `disputed` a nepočítají.

## Výsledek (19. 9. 2026, po běhu)

Strojová tabulka: `plugins/aid-orchestrator/scripts/tests/fixtures/step-review/acceptance.json`;
odpovědi revizorů: `fixtures/step-review/answers/<id>-<role>.json` (Sonnet) a `<id>-<role>.opus.json` (Opus).

| | baseline (krok 1) | Sonnet, nový tok | Opus, nový tok |
|---|---|---|---|
| položek | 20 | 20 (22 dispatchů) | 8 z 20 — strop (6 selhaných + s07, s11) |
| nahlášeno / přijato adjudikátorem | 16 | 6 | 18 |
| potvrzeno čtením kódu | 6 (0 skutečných chyb) | 5 (3 skutečné chyby z původních revizí: s02, s03, s04) | 14 (chyby na všech 6 selhaných) |
| potvrzeno na 6 selhaných (V1 ≥ 2) | 2 | 3 | 10 |
| tokeny | 1 738 149 | 2 003 200 | 943 291 |
| USD | 7.30 (sazba 4.2/M z kroku 1) | 13.14 (blended 6.56/M, odhad) | 15.47 (blended 16.4/M, měřeno) |
| USD na krok | 0.365 | 0.657 | 1.934 |
| USD na potvrzený nález | 1.22 | 2.63 | 1.10 |

Utraceno za oba nové běhy: 28.61 USD (strop 30). Opus zastaven po osmi položkách podle pravidla stropu; volba používá jen položky dokončené oběma modely.

**Pravidlo V8 (stanovené před během): nekvalifikuje ani jeden.** Sonnet je 1.8× dražší na krok než baseline (víc tokenů: +15 %, hlavně druhý revizor u bezpečnostního vzoru; a vyšší sazba tabulky než odhad z kroku 1) a dražší na potvrzený nález. Opus je 5× dražší na krok, na potvrzený nález levnější než baseline (1.10 < 1.22), ale kvůli ceně na krok nekvalifikuje. Podle pravidla se nález vrací do kroku 3 nebo 6, ne do zmírnění pravidla — **model není zvolen pravidlem.** Rozhodnutí PM 19. 9. 2026 (varianta A): **Sonnet** zůstává výchozím revizorem kroku (`review-checkpoints.yaml` beze změny) a rozhodčí se zmírní — nález stojí na jedné platné citaci z několika, `absent:path` dokazuje chybějící soubor, `git log/show/diff/blame` jsou čtecí příkazy. Se zmírněním by Sonnet v tomto běhu měl 8 potvrzených nálezů (1.64 USD na nález).

**Co běh ukázal nad rámec pravidla:**
- Dnešní tok (baseline) našel 0 z 8 skutečných chyb; nový tok se Sonnetem 3 (s02 test, který nedokazuje větev; s03 druhý konzument přejmenovaného `ordinal`; s04 recyklované stránky bez content_type) a další 3 skutečné nálezy (s07 nevolaný `_strip_code`, s03 únik PII smazané osoby, s18 nepravdivý registr) adjudikátor **zahodil**, protože jedna z citací mířila za konec souboru. Opus tyto tři našel a citoval správně.
- Adjudikátor je tedy přísnější, než je užitečné: odmítá celý nález, když z několika citací jedna neexistuje. Kandidát na změnu (krok 5): stačí, aby seděla aspoň jedna citace; `git log`/`git show` do allowlistu příkazů (s09); forma důkazu pro „soubor v commitu není" (s20).
- Jediný sporný nález: Sonnet u s11 tvrdil pád `tsc` — `fields_meta` je `Record<string, any>`, překlad projde (Opus totéž místo označil správně jako nerozbité).
