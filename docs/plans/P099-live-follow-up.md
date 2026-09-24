# P099 — doměření na prvním živém plánu (2.104.0)

Vydáno 24. 9. 2026. Tenhle záznam vyplní agent, který jako první dokončí plán
na 2.104.0 (v libovolném projektu). Čísla opsat z evidence, ne z paměti.

| Pole | Hodnota | Odkud |
|---|---|---|
| Projekt a plán | | |
| Codex odpověděl (ano/ne za každé kolo CP1/CP2/CP3/CP7) | | `cp*/round-*/codex-*.usage.json` (`answered`, `fallback`) |
| Telegram: kolik „agent čeká", kolik „plán dodán" | | DM eco Alerts; `~/.local/state/aid/alerts/` |
| Stránky: kolik zveřejněno (má být 2) | | |
| Souběžné kroky: překrývající se běhy kroků | | `timeline.jsonl` (`step_dispatch_start` se překrývají) |
| Pokračování: kolik odmítnutí konce tahu, kolik předání kartou | | hook audit (`outcome=refused` / `handed_over`) |
| Pět čísel času (práce / revize / brány / čekání / výpadky) | | stránka dodávky, `plan_summary.time` |
| Tokeny proti P097 / P007 | | `measurement.json` |
| Merge cesta T0+T1 z nočního běhu | | `/aid-status` řádek Nightly |

Po vyplnění: co z cíle P099 platí a co ne, a návrh dalšího kroku PM (A/B/C).
