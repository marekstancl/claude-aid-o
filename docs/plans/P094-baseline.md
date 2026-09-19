# P094 — baseline dnešního toku revize kroku (krok 1)

Zapsáno PŘED během, 19. 9. 2026.

- Vzorek: `plugins/aid-orchestrator/scripts/tests/fixtures/step-review/sample.json` (20 diffů: 6 se zaznamenaným `fail`, 14 čistých; 2+7 ACTA, 2+0 WAN, 2+7 aid-orchestrator). Pravidlo výběru je v souboru.
- Tok: dnešní karta verifiera (`agents/verifier.md`, doslovná hlavička zadání), model `claude-sonnet-5`, jeden dispatch na položku, revizor čte repo na zaznamenaném commitu.
- Strop: 15 USD (odhad podle sazby z P093: zhruba 15 USD za 1 M tokenů podagentů). Při překročení se běh zastaví a tabulka zapíše, co doběhlo.
- Příkaz: `scripts/tests/test-step-review-acceptance.sh prepare --mode baseline --out <dir>`, dispatch po dvou, pak `collect --mode baseline --out <dir> --model claude-sonnet-5 --tokens id=in:out ...`.
- Potvrzení nálezů (`findings_confirmed`) dělá controller čtením kódu po běhu; sporné nálezy se označí a nepočítají.

## Výsledek (19. 9. 2026, po běhu)

| id | původní verdikt | baseline verdikt | nahlášeno | potvrzeno | skutečné chyby v původní revizi | tokeny |
|---|---|---|---|---|---|---|
| s01-acta-E-018-2_2-step0 | fail | pass | 0 | 0 | 1 | 82,996 |
| s02-acta-E-024-1_4-step1 | fail | pass | 0 | 0 | 2 | 87,210 |
| s03-wan-E-084-1_1-step0 | fail | fail | 8 | 2 | 2 | 87,363 |
| s04-wan-E-091-3_3-step1 | fail | pass | 0 | 0 | 1 | 99,237 |
| s05-aid-orchestrator-E-065-4_7-step1 | fail | pass | 0 | 0 | 1 | 85,788 |
| s06-aid-orchestrator-E-080-1_3-step2 | fail | pass | 0 | 0 | 1 | 88,059 |
| s07-acta-E-013-1_1-step0 | pass | pass | 1 | 1 | 0 | 78,971 |
| s08-acta-E-014-1_1-step1 | pass | pass | 0 | 0 | 0 | 89,067 |
| s09-acta-E-018-2_2-step2 | pass | pass | 2 | 1 | 0 | 83,153 |
| s10-acta-E-019-3_3-step1 | pass | pass | 0 | 0 | 0 | 84,023 |
| s11-acta-E-020-2_3-step1 | pass | pass | 0 | 0 | 0 | 87,584 |
| s12-acta-E-021-2_3-step1 | pass | pass | 0 | 0 | 0 | 86,074 |
| s13-acta-E-024-4_4-step0 | pass | pass | 0 | 0 | 0 | 81,671 |
| s14-aid-orchestrator-E-063-1_1-step1 | pass | pass | 0 | 0 | 0 | 95,377 |
| s15-aid-orchestrator-E-064-1_2-step1 | pass | pass | 0 | 0 | 0 | 83,124 |
| s16-aid-orchestrator-E-065-2_7-step0 | pass | pass | 1 | 0 | 0 | 98,457 |
| s17-aid-orchestrator-E-065-6_7-step0 | pass | pass | 0 | 0 | 0 | 89,776 |
| s18-aid-orchestrator-E-076-1_3-step0 | pass | fail | 1 | 1 | 0 | 87,578 |
| s19-aid-orchestrator-E-076-3_3-step0 | pass | pass | 0 | 0 | 0 | 83,205 |
| s20-aid-orchestrator-E-061-3_6-step1 | pass | fail | 3 | 1 | 0 | 79,436 |

**Součty:** 20 odpovědí, 16 nahlášených nálezů, 6 potvrzených čtením kódu, z toho 2 na šesti selhaných vzorcích; skutečných chyb v původních selhaných revizích 8, dnešní tok jich našel 0. Tokeny celkem 1,738,149 (průměr 86,907 na revizi).

**Cena:** nástroj Agent hlásí jen součet tokenů, takže USD je odhad: při ceníku Sonnet (90 % vstup po 3 USD/M, 10 % výstup po 15 USD/M) zhruba 7.3 USD za běh, tj. 0.36 USD na revizi a 1.22 USD na potvrzený nález. Strop 15 USD dodržen. (Poznámka: sazba „15 USD za 1 M" ze záhlaví byla sazba Opus z P093; pro Sonnet neplatí.)

**Co to říká:** dnešní revizor se Sonnetem nenašel ani jednu ze šesti skutečných chyb, které původní revize zachytily (tvrzení v nápovědě bez opory v kódu, trvalé krácení kvóty, UI čtoucí odstraněné pole, výjimka shazující dávku, dvě špatné cesty v dokumentaci). U s03 našel jen tři soubory mimo rozsah kroku. U čistých vzorků nahlásil 4 potvrzené drobnosti (nevolaná pomocná funkce, nezměněný soubor ze zadání, nepravdivá věta v registru, DoD neověřitelné z commitu).

**Oprava vzorku během kroku:** dva první výběry (acta E-016-2_4 krok 1, aid-orchestrator E-080-1_3 krok 0) měly v timeline zapsaný `step_commit`, který není předkem revidovaného commitu; diff pak ukazoval cizí změny a revizor na nich „našel" tři vysoké nálezy. Obě položky nahrazeny, generátor i skript nyní kontrolují předka (`git merge-base --is-ancestor`). Původní nálezy na těchto dvou položkách se nepočítají.

Strojově čitelná verze: `plugins/aid-orchestrator/scripts/tests/fixtures/step-review/baseline.json`; odpovědi revizora: `fixtures/step-review/answers/<id>-baseline.md`.
