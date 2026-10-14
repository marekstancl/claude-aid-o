# Zadání: testy s hodnotou (2A, vydání 3.1.0) — verze 2

Verze 2 zapracovává revizi Codexu (12 nálezů, všechny přijaty, rozsah beze změny).

PM 13. 10. 2026 („1b 2a pořadí souhlas go“). Stavěno solo mimo AID podle „Vývoj mimo AID“.
Po něm 1B (triáž nočních sad) jako samostatné vydání.

## Proč

Testy pluginu (~79 tis. řádků) jsou větší než kód (~66 tis.). Každý plán přidává testy
(řádek `Test:`, doklady AC, revize kroku, nálezy revize), nic je neubírá. Značka
„verification-only, delete before plan-final“ existuje od P107 (30. 9.) a
`plan-finalize --stage gates` ji vynucuje, ale použil ji jen P107 sám; solo stavby
(P109–P114) touto kontrolou neprojdou vůbec. 654 z 3 678 bats případů nese v názvu
číslo plánu, kroku nebo nálezu („P094 Step 8“, „CP2 F3“, „IMP-612“) — název popisuje,
odkud test přišel, ne co hlídá, a po uzavření plánu je to první kandidát na archeologii.

## Co se mění

1. **Jedna kontrola názvů nových testů** (`lib/aid-test-tier.sh`,
   `aid_test_names_plan_refs <repo> <base>`; při stavbě přesunuto ze scoping — je to
   věc testů a `aid-release.sh` by jinak načítal celou scoping vrstvu; scoping knihovnu
   test-tier načítá sám, takže plánový automat ji vidí beze změny): porovná `base` s PRACOVNÍM STROMEM
   `repo` (`git diff <base>` — zahrne commity, index i necommitnuté změny sledovaných
   souborů, které by legacy release přibral přes `git add -u`). Čte jen přidané řádky
   (smazané a přejmenované beze změny obsahu ignoruje) v testových souborech: cesta
   obsahuje adresář `test`/`tests`/`spec`/`__tests__`, nebo jméno `test-*`, `test_*`,
   `*_test.*`, `*.test.*`, `*.spec.*`, `*.bats`; vynechá cokoli pod `fixtures/`.
   Deklarace (jeden řádek, odsazení dovoleno):
   - bats `@test "…"` / `@test '…'`,
   - pytest `def test_…` / `async def test_…` (název funkce),
   - JS/TS `it|test|describe` s volitelným `.each|.only|.skip|.todo|.concurrent`
     a prvním argumentem jako literálem v `'…'`, `"…"` nebo `` `…` ``.
   Víceřádkové a dynamické názvy se nečtou (strop, `ponytail:` komentář).
   Odkaz na plán v názvu (bez ohledu na velikost písmen, hranice = začátek/konec nebo
   znak mimo `[a-z0-9]`, takže `_` i mezera i `-` hranicí jsou):
   `p[0-9]{3}` bez další číslice (P123, `test_p123_x`; ne P1234, ne XP123),
   `cp[0-9]+[ _/-]?f[0-9]+` (CP2 F3, cp2_f3), `imp-[0-9]+` (IMP-612; v pytest `imp_612`
   se nehlídá — strop). Číslo kroku se NEhlídá: „step 0“ je v AIDu doménový pojem.
   Návrat: 0 = nic, 1 = nález(y) na stdout `<soubor>\t<název>`, 2 = nelze ověřit
   (base neexistuje, git selže) — volající s 2 odmítá stejně jako s 1 (fail closed).
2. **Vynucení tam, kudy projde plán i solo vydání:**
   - `plan-finalize --stage gates` (AID cesta; `prepare-plan` běží před freeze, takže
     jeho změny verze kandidát obsahuje) hned za `verification_only_removed`: nález
     `test_named_after_plan` → PRECONDITION FAIL, base = `plan_base_commit`, strom =
     kandidát; žádný `gates_report.json` nevznikne. Bez nálezu `PASS [test_named_after_plan]`.
   - `aid-release.sh` legacy cesta (`auto|patch|minor|major`): nová pojistka hned za
     `_release_fsm_guard`, tedy PŘED výstupem `--dry-run` a před jakoukoli změnou souborů;
     poslední tag si zjistí sama (nezávisle na typu bumpu). Repo bez tagu = kontrola
     se přeskočí s INFO (první vydání nemá od čeho porovnat). `--force` ji neobchází.
   - `tag-plan` jen taguje sloučený kandidát, který prošel gates — kontrolu nepotřebuje.
3. **Psaní plánu** (`skills/plan-writing.md`, oddíl „Tests are designed, not counted“):
   - Testing Strategy dostane 4. otázku: „Které testy plán maže?“ (test chování, které
     plán odstraňuje nebo mění, i jednorázové kontroly).
   - Výčet druhů, které nikdy nejsou trvalé a vždy nesou značku verification-only:
     důkaz, že krok proběhl („X už neexistuje“), zmrazený seznam starých jmen/čísel,
     hlídač, který selže při jakékoli změně, hledání věty v návodu (výjimka: text, který
     kód cituje doslova).
   - Trvalý test se jmenuje podle chování, ne podle plánu — a říct, že to kontroluje bod 2.
4. **Revize kroku** (`skills/step-review-roles.md` otázka 3, `skills/review-checkpoint-contracts.md`
   „The Two Test Questions“): doplnit „Které existující testy tahle změna zneplatnila
   (hlídají odstraněné chování, zmrazený seznam nebo text, který diff mění)? Pojmenuj je;
   mažou se v tomto kroku.“
5. **Solo stavby v tomto repu** (`CONTRIBUTING.md`): jedna věta — solo plán značí
   jednorázové testy stejně a smaže je před merge; release odmítne případ pojmenovaný
   po plánu.
6. **Dokumentace**: CHANGELOG 3.1.0, Docusaurus `/aid/testing` (oddíl o plánových
   a trvalých testech), help-index pokud tam téma je.

## Co se NEmění

- Žádné přejmenování stávajících 654 případů ani mazání sad — to je 1B.
- Značka verification-only a její kontrola zůstávají, jak jsou.
- Patra T0/T1/T2 a jejich kontrola beze změny.

## Hotovo, když (akceptační body)

- AC1 Nová bats sada (t0) kontroly: matice — `@test "P123 refuses X"`, `@test "cp2 f3 …"`,
  `@test "IMP-612 …"`, `def test_p123_x`, `it.each("P123 …")` → nález; `@test "refuses X"`,
  `@test "step 0 runs"`, `XP123`, `P1234`, nezměněný starý případ s P-číslem, řádek pod
  `fixtures/`, necommitnutá změna sledovaného souboru (nález), neexistující base (návrat 2).
- AC2 `plan-finalize --stage gates` s takovým případem na kandidátovi: návrat 1,
  `FAIL [test_named_after_plan]`, `gates_report.json` nevznikne, stav zůstane PLAN_GATES;
  bez něj `PASS [test_named_after_plan]` a brány proběhnou (případ v test-aid-plan-final-boundary).
- AC3 `aid-release.sh patch --dry-run` s takovým případem od posledního tagu (commitnutým
  i jen upraveným ve stromu) odmítne s návratem 1 a nezmění žádný soubor; bez něj projde
  jako dosud; repo bez tagu projde s INFO.
- AC4 plan-writing, step-review-roles, review-checkpoint-contracts, CONTRIBUTING
  a Docusaurus `/aid/testing` popisují stejná pravidla (kontroluje revizor celého diffu,
  ne nový test na znění vět).
- AC5 `run-all-tests.sh --tier t0` a `--tier t1` zelené; sady, které se mění
  (test-aid-plan-final-boundary, test-aid-release*), zelené; testbed `bin/verify.sh` 42/42.
- AC6 Vydání projde svou vlastní kontrolou (žádný nový případ s číslem plánu).
