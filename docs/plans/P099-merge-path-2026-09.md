# P099 krok 8 — merge cesta (T0+T1): měření a co se změnilo

Měřeno 23. 9. 2026 z nočního deníku trvání (`/opt/eco/data/aid-nightly/aid-orchestrator/test-durations.jsonl`,
běh 2026-09-23 01:xx, eco-dev, sady za sebou). Během vývoje P099 se celé patro nespouštělo
(pokyn PM: jen cílené testy); čísla „po" jsou lokální běhy dotčených sad a odhad součtu.
Skutečné ověření udělá první noční běh po sloučení (`/aid-status` řádek Nightly ukáže
`merge path … over budget`, dokud rozpočet standardu nesplní).

## Před

| patro | sad | součet |
|---|---|---|
| T0 | 74 | 754 s |
| T1 | 39 | 1 797 s |
| **merge cesta** | | **2 551 s (42,5 min)** |

## Co se udělalo

| sada | před | po | co |
|---|---|---|---|
| vykreslení stránek (renderer) | 4,0 s / stránka | 2,3 s | ~15 volání `jq` místo ~79, výstup bajt po bajtu stejný |
| test-aid-artifact-render | 105 s | 79 s | rychlejší renderer |
| test-aid-plan-summary (t0) | 76 s | 54 s | rychlejší renderer (+1 případ) |
| test-artifact-profiles (t0) | 36 s | 15 s | renderer; 4 případy stránky bran pryč |
| test-aid-plan-close-summary | 86 s | 71 s | renderer (+2 případy času) |
| test-brainstorm-summary | 72 s | 52 s | rychlejší renderer |
| test-aid-gate-outcome-summary | 123 s | 23 s | stránka bran zrušena (krok 4), 28 případů místo 38 |
| test-tier-ci-topology-guard | 156 s | → T2 | testuje kontrolor CI, ne chování; kontrola sama (test-tier-ci-topology.sh) zůstává v T1 |
| test-aid-nightly-report | 67 s | → T2 | reportér běží jen v nočním jobu; rozbitý se ukáže ráno v `/aid-status` |
| test-dod-gate-profile-agreement | 82 s (T0) | → T1 | 14 s na případ (skutečná generace), T0 je pod 2 s na případ |
| test-queue-continuation (t0) | 20 s | 34 s | +10 případů odmítnutí konce tahu (krok 5) |

**Odhad po:** T0 ~550 s, T1 ~1 540 s, **merge cesta ~2 090 s (~35 min)**.

## Co zbývá a proč se nepokračovalo

Cíl plánu (< 20 min) se tímto nedosáhl. Další snížení by vyžadovalo stáhnout z merge cesty
jádro revizních kol (`test-review-round.bats`, 416 s, 55 případů, jediná stráž prepare /
collect / close / routingu / CP2 / CP7 / zástupce z P093–P097). Pravidlo kroku 8 to zakazuje
(„sada, jejíž odsunutí by nechalo chování posledních tří plánů bez stráže na merge cestě,
zůstává"). Rozhodnutí za PM (Codex gpt-5.6-terra high, 23. 9. 2026): **varianta A** —
zapsat mezeru, v dalším plánu zrychlit revizní engine (prepare/close) stejně jako renderer,
teprve pak zvažovat přesun.

Největší zbývající položky: test-review-round 416 s, test-plan-fixture-contract ~145 s,
test-aid-run-gates 133 s, test-aid-artifact-render 79 s, test-aid-plan-close-summary 71 s,
test-gate-waiver 69 s, T0 test-evidence-verify-tree 58 s.

Rozpočty standardu, které hlídá noční běh (`aid-nightly-report.sh`): T0 120 s, T1 600 s,
merge cesta 600 s. Mezera k nim zůstává jako další cíl.

`bats_all` v `.aid-o/config/execution.yaml` si drží timeout změřený v P097 (2 × p95); nové
měření celého patra během P099 neproběhlo.
