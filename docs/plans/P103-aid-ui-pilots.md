# P103 Step 9: zpětná kontrola a piloty `/aid-ui` (akceptační záznam)

Jednou větou: nová brána `/aid-ui` Truhlárnu Dub zamítla na všech čtyřech
známých vadách (písmo, logo, zástupné texty, těžké obrázky); piloty Needless
a Objednávky čekají na běh s PM.

Summary (EN, for the plan AC check): Truhlárna Dub: FAIL as expected (glyph_coverage, brand_assets, no_placeholders, image_weight all fail); Needless: pending; Objednávky: pending.

Zapsáno 2026-09-28. Testovaný kód: worktree `.aid-worktrees/plan-P103`,
větev `task/E-103-3_3/main`.

## Truhlárna Dub (zpětná kontrola)

| | |
|---|---|
| Co běželo | brána `aid-ui-verify.sh` na kopii webu z `.aid-o/work/P103-zkouska/truhlarna-p102/site/` (stav založený, build zapsaný), 5 stránek × chromium/webkit × 390/768/1440 px |
| Výsledek | **FAIL** (očekávaný), exit 3 |
| Řádky celkem | 420: pass 288, fail 99, not_covered 30, warn 3 |

Padající kontroly (jedna ukázka detailu na kontrolu):

| Kontrola | Řádků | Detail |
|---|---|---|
| `glyph_coverage` | 3 | `/postup/` nadpis „Od zaměření po montáž": 3 znaky v systémovém Liberation Sans, zbytek v Karantině (písmo nemá českou diakritiku) |
| `brand_assets` | 30 | „not from the brand package: inline `<svg>` in a.brand" na každé stránce - logo nakreslené v hlavičce ručně, ne symbol z brand balíčku |
| `no_placeholders` | 6 | `/kontakt/`: text „fiktivn…" a `mailto:dilna@example.invalid` |
| `image_weight` | 30 | `/assets/plates/table-plate.png` je PNG a má 1751 kB, `/assets/plates/paper.png` je PNG |
| `required_files` | 30 | chybí `404.html`, žádný `og:image` |

Nepokryté: `facts_match` (30 řádků) - projekt nemá `docs/content/facts.yaml`,
není s čím fakta porovnat. Varování: `lighthouse_mobile` na úvodní stránce,
výkon 70/100 (3 řádky).

Oprava brány, kterou kontrola odhalila: `brand_assets` dřív kontroloval jen
loga v `<img>` a favikony, takže ručně nakreslené SVG logo v hlavičce prošlo.
Teď se kontroluje každé logo (obrázek i vložené SVG uvnitř odkazu na úvod nebo
prvku pojmenovaného logo/brand) a vložené SVG se porovná tvarem (viewBox
a geometrie tvarů, bez barev, mezer a id) s každým SVG v brand balíčku.
První běh brány před opravou hlásil `brand_assets` pass, druhý běh po opravě fail.

Výjimky udělené PM: žádné.

## Needless

Čeká na pilot s PM.

## Objednávky (Truhlárna)

Čeká na pilot s PM.
