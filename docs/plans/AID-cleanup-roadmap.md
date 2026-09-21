# Co dál s čištěním pluginu — kandidáti po P096

**Rozhodnutí PM 20. 9. 2026:** pořadí je **C1 jen úklid** (bez psaní standardu do
Docusauru) → **A2 smazat audit testů** → **A1 přestavba bran**.
**Stav 21. 9. 2026:** C1 hotovo (v2.101.2), Telegram 2A hotovo (v2.101.3), A2 hotovo (v2.102.0). Další: A1. Ostatní body tu
zůstávají, aby bylo kam se vrátit.

Založeno 20. 9. 2026 po vydání 2.101.1. Řada P093 → P094 → P095 → P096 přestavěla
kontrolu plánu, kroku, EPICu, fast mode a konec plánu na jeden motor revizních kol
a smazala, co nahradila. Tady je, co v témže duchu zbývá, a co je jiného druhu.
Čísla jsou naměřená 20. 9. 2026 (`wc -l`, `git ls-files`).

## A. Kontroly, které ještě nikdo nepřestavěl (duch P094/P096)

| # | Vrstva | Velikost | Co je na ní špatně | Návrh |
|---|---|---|---|---|
| A1 | **Brány** (`aid-run-gates.sh` + knihovny + `scripts/gates`) | 2 895 + 3 256 kódu, 5 041 testů | profily, karanténa, náhradní doklady, časové základny, souběh, znovupoužití — šest mechanismů nad jedním „pusť příkaz, zapiš řádek" | jako P096: změřit, co z toho projekty opravdu použily (karanténa? základny?), vzorek skutečných selhání bran z WAN/ACTA, přestavět na model brána = příkaz + výsledek + důvod, smazat po důkazu |
| A2 | **Audit testů** (`/aid-audit-tests`, P072) | 4 696 kódu, 5 561 testů, 7 schémat, 5 promptů | PM jeho výstup 5. 8. 2026 odmítl (0 návrhů); paralelismus, kvůli kterému vznikl, je zrušen (P078); od té doby nikdo nespustil | rozhodnout: smazat celé (doporučuji), nebo zúžit na jedinou otázku „které sady nic nehlídají" a napojit na audit testů z bodu B1 |
| A3 | **Tiered severity + compliance.json** (`check-severity.yaml`, `evaluate_compliance_checks`, `write_compliance_json`) | 64 + 283 řádků, 11 klíčů | vrstva „advisory → promotable" z P038; dnes čte hlavně cp2/cp3 indexy, které už hlídá `fsm_check_review_round`; klíč `plan_ac_match` je od 2.101.1 skoro vždy `null` | změřit, který klíč kdy za poslední měsíc zablokoval; co nikdy, smazat; zbytek sloučit do preconditions FSM |
| A4 | **Protokol v2 + ověření evidence** (`aid-protocol-validate.sh`, `aid-evidence-verify.sh`, 38 schémat) | 637 + 1 040 kódu, 38 schémat | validátor kontroluje obálku artefaktů včetně šesti vyřazených typů; schémata nečte, má vlastní jq; `verification_report` je vstup rozhodnutí, jehož `unverifiable` větev projekty vidí často | zúžit obálku na to, co rozhodnutí čte; validátor buď schémata načte, nebo se schémata smažou; vyřazené typy odstranit po jednom vydání |
| A5 | **Rozhodnutí o vydání** (`aid-release-policy.sh`) | 1 115 | osm vstupů, tři z nich (`review_profile`, `semantic_review_final`, `acceptance_evidence`) rozhodnutí neblokují jinak než přítomností | po A4 zvážit, zda `review_profile` a `semantic_review_final` ještě mají být vstupy, nebo jen podklad kola cp7 |
| A6 | **Žebřík obnovy** (`aid-recovery-*`, P076) | 1 855 | šest tříd zastavení, adjudikátor přes Codex; kolikrát za měsíc opravdu zasáhl? | změřit z `recovery-ladder.jsonl` napříč projekty; třídy bez jediného výskytu smazat |
| A7 | **Audit zdraví projektu** (`/aid-audit`, `agents/auditor.md`) | 880 řádků karty | deset kategorií A–J, skórování 0–100, trend; po P096 bez vazby na pipeline; kdy naposledy někdo spustil? | buď zúžit na tři kategorie, které se čtou (kód, bezpečnost, dokumentace), nebo smazat |
| A8 | **Hooky a pravidla zastavení** (P086/P087, 842 řádků) | 842 | v pořádku, měřeno testbedem; jen ověřit po A1–A5, že pravidla ukazují na existující artefakty | bez zásahu |

Pořadí, které dává smysl: **A2 (smazat) → A1 (brány) → A3 + A4 spolu → A5 → A6 → A7.**
A1 je největší a nejrizikovější, ale brány běží v každém projektu a jejich složitost
platí každý běh. A2 je největší úspora za nejmenší práci.

## B. Jiného druhu (ne kontroly)

| # | Co | Velikost | Návrh |
|---|---|---|---|
| B1 | **Audit testů a merge cesta** | 271 sad, 92 326 řádků (víc než kód: 78 741); merge cesta 32 min proti stropu 10 (IMP-617) | sady smazaných mechanismů pryč, duplicitní fixtury sloučit, patra přepočítat; cíl < 10 min a suite < kód |
| B2 | **Generování** (plán → EPIC → plan.json → run.md) | 4 skripty, 5 643 řádků | jedna transakce, méně mezikroků; až po A1 |
| B3 | **Dvě stavové mašiny** (`aid-plan-fsm.sh` 10 460, `aid-fsm.sh` 7 725) | 18 185 | rozdělit na knihovny podle stavu; chování beze změny; přínos jen pro další úpravy |
| B4 | **Instrukce pro agenty** | 16 059 řádků, `pipeline.md` 2 054 | zkrátit o třetinu; každá session to čte |
| B5 | **Staré záznamy plánů** (P067, P068, P071, P076, P079, P080, P087, P999) | 8 záznamů, 3 ukazují na smazané stromy | uzavřít; hlídač, aby plán stavěný mimo AID nezůstal „otevřený" |
| B6 | **IMP-620** | — | jiný tvar otázky (role kritérií čte nový test proti incidentu z plánu), ověřit na vzorku |

## C. Veřejné repo a dokumentace

Repo `marekstancl/claude-aid-o` je public. Stav 20. 9. 2026:

- 1 658 sledovaných souborů; `.git` 131 MB.
- V kořeni: `screenG-desktop-productized.png` (499 kB) a `screenG-mobile-productized.png`
  (479 kB) — obrázky bez čtenáře; `audit-watchdog.sh`, `Dockerfile`, `docker-compose.yml`,
  `vitest.config.ts`, `tsconfig.base.json`, `package.json` + `package-lock.json` (379 kB),
  `transition/`, `work/`, `services/` — zbytky dřívějších tvarů repa (GUI balíček
  `packages/aid-gui`, 317 souborů).
- `.aid-o/` má 264 sledovaných souborů (stav projektu v public repu), `.aid-lifecycle/` 10.
- `docs/` je gitignorované s výjimkami přidávanými `git add -f` (121 souborů): plány,
  záznamy, poznámky — bez pravidla, co je veřejné a co pracovní.
- `CHANGELOG.md` má 610 kB.
- Fixtury testů: 310 souborů, e2e evidence 4.

Návrh **C1 — standard veřejného repa AID** (napsat do Docusauru jako `/aid/repo-standard`):
1. Kořen nese jen manifest marketplace, plugin, `README`, `CHANGELOG`, `LICENSE`, `CLAUDE.md`,
   `docs/`, `.github/`; vše ostatní pryč nebo do samostatného repa (`packages/aid-gui`).
2. Co je veřejné v `docs/`: `extending-aid.md`, standardy, návody; plány a záznamy PM
   (`docs/plans/`) jdou do soukromého repa nebo do Docusauru, ne sem.
3. `.aid-o/` pluginového repa: jen `config/` a `plans/` hotových plánů; `work/` mimo git.
4. Fixtury a e2e evidence: pravidlo „žádný soubor bez čtenáře" hlídané testem
   (dnes jen pro `defaults/`).
5. CHANGELOG: starší než 12 měsíců přesunout do `docs/changelog-archive/`.
6. Stejný standard pak platí pro ostatní eco repa, která jsou nebo budou public.

Práce: standard půl dne, úklid repa podle něj jeden až dva dny (přesun GUI balíčku
zvlášť). Riziko: odkazy z Docusauru a z pluginu na přesunuté soubory — hlídá
`test-enforcement-registry-cites.sh` a odkazová kontrola help indexu.

## D. Náměty PM na později (zapsáno 20. 9. 2026 večer)

| # | Co | Poznámka |
|---|---|---|
| D1 | **Kompletní přestavba a promyšlení Brainu** (vulcan-memory / Qdrant jako paměť ekosystému) | co se ukládá, kdo čte, jak se to udržuje čerstvé; základ pro D2 |
| D2 | **Sebezlepšování AID** – učení se z dřívějších chyb jako aktivní složka AID | Brain (D1) jako zdroj: nálezy revizí, incidenty z plánů, IMP backlog → AID je při plánování a revizi sám používá, ne jen archivuje |
| D3 | **Paralelismus** – znovu, s novým návrhem | P077/P078 linka zrušena (2026-08-09); vracet se jen s plánem, který znovu spočítá, co to stojí (viz paměť: nenavrhovat oživení bez nového zadání PM) |

Rozhodnutí PM 20. 9. 2026 večer k úklidu: kokpit zůstává v repu pod `cockpit/` (1A);
Telegram = údržba mapy + vyřazení `svc-mcp-tg-bot` jako samostatný krok mimo AID repo (2A).
