# P096 — sledování tří živých plánů po vydání 2.101.0

Založeno 20. 9. 2026 při vydání. Dva body vize P096 se nedají změřit na starých
datech, protože se týkají plánů, které ještě neexistují. Tady se doměří.

## Co se má potvrdit

- **V1 — plán se zavře na první pokus, když je práce v pořádku.** Další pokus smí
  vzniknout jen z opravy skutečného nálezu, nikdy z toho, že se pohnul kandidát
  nebo chyběl soubor.
  **Práh:** u každého ze tří plánů je počet pokusů = 1 + počet oprav skutečných
  nálezů. Jediný pokus navíc z jiného důvodu = V1 nesplněno a důvod se zapíše.
  Základ k porovnání: medián 4 až 5 pokusů na plán (`baseline.json`).
- **V2 — uzavření bez nálezu trvá do 15 minut a jeho cena je známá.**
  **Práh:** pokus bez nálezu do 15 minut od `freeze` po `decide`; u každé role je
  cena v USD vyplněná (`usd_unknown_roles` prázdné). Čas nad 15 minut se rozepíše
  na brány, revizory a zbytek, aby bylo vidět, kde leží.

## Které plány

Jeden v každém ze tří projektů, vždy první plán, který se po upgradu zavře:

| Projekt | Plán | Zavřen | Pokusů | Z toho oprav nálezů | Minut (pokus bez nálezu) | USD | Nálezů potvrzeno / zamítnuto | V1 | V2 |
|---|---|---|---|---|---|---|---|---|---|
| ACTA | | | | | | | | | |
| WAN | | | | | | | | | |
| aid-orchestrator | | | | | | | | | |

Čísla se opisují ze stránky pro PM (řádek „Uzavření: N pokusů, M min, X USD"),
z `release-decision.json` → `plan_summary.close` a z `cp7/round-1/measurement.json`.
Nic se neodhaduje; chybějící číslo se zapíše jako chybějící.

## Co se rozhodne po třetím plánu

1. Vyplatí se role `final_generalist` (druhý poskytovatel)? Kolik nálezů našla jen
   ona a kolik jich bylo zamítnuto.
2. Potřebuje role `final_criteria` Opus, nebo stačí Sonnet? Cena role proti počtu
   potvrzených nálezů.
3. Drží znovupoužití bran a rolí mezi pokusy? Kolik řádků bran neslo `reused_from`
   a jestli se někde znovupoužil výsledek, který se znovupoužít neměl.
4. Otevřené slabiny z akceptačního běhu: IMP-620 (síla nových testů) a IMP-621
   (nález zahozený kvůli formě) — objevily se i naživo?

Výsledek se předloží PM jako rozhodnutí s možnostmi, ne jako tabulka.
