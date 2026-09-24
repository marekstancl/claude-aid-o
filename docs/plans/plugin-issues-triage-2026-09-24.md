# Roztřídění hlášení pro AID — 24. 9. 2026 (před vydáním 2.106.0)

Sběr `bin/aid-plugin-issues-collect.sh` vypsal 102 otevřených bodů (ACTA, agents,
WAN, aid-orchestrator). 80 z nich je historických: opravilo je P099, P100 nebo
starší vydání, nebo komponenta zanikla (viz `plugin-issues-triage-2026-09-23.md`
a CHANGELOG 2.106.0). Zbylých 22 ověřil jeden nezávislý Claude v kódu (worktree
P100 = main 2.105.2 + nevydané opravy P100) a druhý nezávislý Claude posoudil,
zda navržená oprava zabere. Codex byl do 28. 9. mimo (limit účtu).

**Rozhodnutí PM 24. 9.: varianta B** — opravit teď vysoký přínos a všechny drobnosti,
mimo AID, každý bod se zadáním pro nezávislého Clauda a nezávislým ověřením před
vydáním 2.106.0. Zbytek do backlogu.

Oprava: 📝 text / drobnost (do 15 min), 🔧 malá změna kódu (do hodiny), 🛠 střední (půl dne).

## Opravit teď (před 2.106.0)

| # | Co se děje | Výskyty | Oprava | Návrh (s úpravou od druhého Clauda) |
|---|---|---|---|---|
| 17 | Kontrola kroku z hlavní kopie hodnotí špatné repo a zapíše „beze změn" — krok projde bez revize | P101 + „všude `--project-root`" | 🛠 | sdílená funkce najde worktree s větví běhu (`branch:` z `fsm-state.yaml`, `git worktree list`); jen cp2/cp3 bez `--project-root`; bez zapsané větve zůstat u cwd; chyba jen když větev zapsaná je a nikde vyzvednutá není (`aid-step-check.sh:72`, `aid-review-round.sh:120`) |
| 1 | Plán bez `**EPIC N:**` projde vším a spadne při startu s „rc=2" | ACTA, WAN, agents | 🔧 | lint u `lifecycle_strict` volá `aid_lifecycle_parse_legacy_epics` (chytí i řádek bez dvojtečky); plan-start vypíše důvod (`lib/aid-lifecycle.sh:651/661`, `aid-plan-fsm.sh:2438`) |
| 12 | Změna registru vynucení spustí celou sadu (~40 min) | P101 | 📝 | `aid-select-tests.sh` mapa → 11 sad, které registr čtou (test-audit neexistuje); upravit `test-selector-snapshot-readonly.bats:38`, který mezeru očekává |
| 6a | Revizor dostává falešné „zápis mimo rozsah" | agents, P101 | 🔧 | umlčet jen adresáře revizních kol (`evidence/*/*/cp2|cp3|cp7/…`), ne celé `.aid-o/` |
| 11 | Runner nezapíše, které testy spadly | P101 + P100 | 🔧 | při pádu sady vždy `not ok` + 5 řádků; u `.sh` a „bats chybí" posledních ~10 řádků; s `--verbose` nevypisovat dvakrát (`tests/run-all-tests.sh:472`) |
| 3 | Kontrola plánu píše „round closed (pass)" i s blokery | agents | 📝 | jen CP1: „kolo platné, otevřených blockerů: N" (`aid-review-round.sh:785/815`) |
| 5 | Karta neřekne, že odpovídal zástup za Codex | agents | 📝 | krátce na začátek řádku shrnutí („codex→claude N×"), řádek se ořezává na 120 znaků (`lib/aid-review-summary.sh:124`) |
| 9 | Revizor vidí číslo kroku od nuly | P101 3× | 📝 | číslo z `^step_([0-9]+)` id, index v závorce (`lib/aid-step-review-packet.sh:64,67`) |
| 10 | Nález přijatý PM se ukáže jako „opraveno" | nalezeno při P101 | 📝 | vnitřní stav `fixed` nechat (čte ho 6 míst), výpisy podle `.dispute.pm.answer == "accepted"` |
| 14 | Pre-push nepozná `chore(release):` | WAN | 📝 | u projektů bez `versioning` přijmout `*(release):` (`defaults/hooks/pre-push:314`) |
| 22 | Staré pracovní kopie v agents | úklid | 📝 | smazat `brainstorm-P002`, `brainstorm-P004`, `plan-P003` (čisté, v main); `plan-P008` nechat |

### Stav 24. 9. večer: všech 11 bodů + 2A opraveno (commit 43fe23fc), NEVYDÁNO

Zadání ke každému bodu ověřil proti kódu nezávislý Claude; jeho úpravy jsou v kódu:
- 17: i `increment-step` se přesměruje do worktree plánu, jinak by se zacyklil na `step_check_stale`. Nastavení revize se čte z hlavní kopie. Větev, která už neexistuje, zůstane u cwd.
- 1: opraven i návod `skills/plan-writing.md`, který tvrdil, že jednofázový plán řádek EPIC nepotřebuje. Parser přeskakuje bloky kódu.
- 10: „accepted" znamená, že PM nález zamítl → výpis říká „dismissed by the PM (dispute accepted)". Nález se nepočítá do výtěžku revizora.
- 14: jen `chore(release):`. `fix(release):` zůstává oprava.
- 12: přidán i `test-evidence-verify.sh`.
- 5: počet se bere z `fallback_reason` v measurement.json.

Navíc: `test-gates-hygiene.sh` byl červený od P099 (soubor ztratil štítek „WHY THIS FILE EXISTS"), štítek je vrácen.

## Do backlogu (střední přínos, jednorázová hlášení)

| # | IMP | Co |
|---|---|---|
| 4a+4b | IMP-653 | kontrola plánu: falešné poplachy B10 a B2 |
| 13 | IMP-654 | kolize čísel migrací |
| 20 | IMP-655 | readiness lintuje dodané kroky |
| 19 | IMP-656 | zadání kroku bez architektury plánu |
| 2 | IMP-657 | `auto_controller: manual` pod `--auto` |
| 16 | IMP-658 | mrtvá cesta k pluginu v `plugin.yaml` |
| 8 | IMP-659 | `AID-WAIT` a Agent bez parametru |
| 6b | IMP-660 | cesta u nové složky ve worktree |
| 15 | IMP-661 | brainstorming bez plánu bez záznamu |
| 21 | IMP-662 | závazek z kroku do kroku (samostatný plán) |

## Nedělat

| # | Co | Proč |
|---|---|---|
| 7 | krok, který jen maže, bez revize | bezpečnostní vzory se hledají jen v přidaných řádcích; smazaná kontrola by prošla bez revize kroku |
| 18 | vynutit prohlášení „přečetl jsem celý podklad" | model ho napíše vždy, nic to neověří |

## Dřívější rozhodnutí téhož dne (tření z běhu P100)

Revize plánu: dvě otázky navíc pro `feasibility_deps` (A); runner vypíše spadlé
případy (A, bod 11 výše); pomalé sady a tiše zahozený řádek brány: nic; stará
verze Codex CLI: odinstalovat. Záznam v `P100-live-follow-up.md`.

## Druhá dávka 24. 9. večer (P101 + agents P008) — PM varianta A, vše opraveno

Nezávislý Claude ověřil 30 položek v kódu: 13 už opravených, 17 platných. Opraveno 13 bodů (N1–N11, N13, N14):
- N1: upgrade `/aid-init` přenese starou `gate_profile_defaults.epic` do `default_profile`.
- N2: `aid-plan-fsm.sh plan-record-decision` zapíše rozhodnutí PM, které sloučení přijme.
- N3: index hlavní kopie po uzavření plánu.
- N4: brány bez `--profile` to řeknou.
- N5: poslední trasa nálezu platí.
- N6: commit kroku vezme ignorovaný soubor, ne stav AIDu, a jmenuje soubor z jiného repozitáře.
- N7: `decide` jmenuje spadlou kontrolu; zámky jsou pomocné soubory.
- N8: `--bump auto` se u plánu zeptá.
- N9: háček konce tahu přijme kartu ekosystému.
- N10: nová složka ve worktree.
- N11, N13, N14: drobnosti.

N12 (dvojí `test-aid-fsm`) se udělal až po sloučení P101, v konfiguraci tohoto repozitáře.
Nedělat: A21 (carry v CP7 je záměr), Impeccable/Playwright (prostředí).
Do backlogu: pevné počty testů v kritériích, delší paměť pro limit Codexu.

## Třetí dávka 24. 9. v noci (doplněk P101) — PM varianta A, vše opraveno

Hlavní příčinu „decide nikdy READY" odstranil už P100 (podklad z worktree plánu). Poslední kus opravuje M1.
- M1: čistota stromu na konci plánu i posouzení změny kandidáta se dívá na worktree plánu, ne na hlavní kopii.
- M2: rozhodnutí o znovupoužití bran; spadlá brána jmenuje příkaz k zopakování.
- M3: `aid-fsm.sh alloc imp-id`.
- M4: `\bxit\(`.
- M5: pořadí vydání v CONTRIBUTING.
- M6: `done-advance` archivuje soubor EPICu sám.
- M7: bez varování review_profile.
- M8: rada bez `rm`.
- M9: B3.
- M10: zápis hlášení jedním blokem.

Nedělat: „otrávený" pokus (opraveno v P100) a `--force` na sloučení (záměr).
Do backlogu:
- `produce` spouští sady T2, které jmenují kritéria;
- lidská věta pro PM, když Codex nahradil Claude;
- release-policy v režimu EPIC soudí hlavní kopii (jen pozoruje);
- mrtvý pokyn v `skills/pipeline.md` (review-profile per EPIC).
