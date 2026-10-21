---
name: ui-design
description: Steps of /aid-ui - variant, product (vision, logo, SEO), structure, content plan, references, three directions as real pages, build and verification, every PM choice on the studio page
user_invocable: false
---

# ui-design

**Last Updated:** 2026-10-07

> **Model okna.** Návrh vzhledu dělá sama session, žádný dispatchnutý agent. Před spuštěním
> `/aid-ui` přepni okno na Fable (`/model fable`); plugin to za tebe přepnout neumí. Vývoj podle
> plánu (kroky role `frontend`) běží na Sonnetu s prahem návratu (`docs/plans/P107-model-measurement.md`).

Vede PM od varianty produktu přes produkt, strukturu, obsahový plán, vzory
a tři směry jako skutečné stránky až k postavenému a ověřenému webu nebo
aplikaci; výsledky skládá do brand stránky projektu (`<project>/docs/brand/`).
Každou volbu a každé schválení dělá PM na stránce studia; bez zaznamenané
odpovědi se nic nerozhodne (vynucuje `aid-ui-state.sh`, ne jen tento text).

---

## When to Invoke

- `/aid-ui [step]` (`commands/aid-ui.md`) - jediný vstup.

Do NOT invoke for:

- běhy AIDu samotné (`/aid-run`, `/aid-plan`, `/aid-do`) - studio do nich vstupuje jen předávacím balíkem (oddíl Předání);
- backend, hosting, 3D, video.

---

## Hranice

- Plán a běh nevede: konec studia je předávací balík (oddíl Předání), nasazení dělá plán; nic sám veřejně nevystavuje ani neposílá.
- Neobchází blokace galerií; cizí screenshoty nejdou do gitu ani zákazníkovi.
- Stav `docs/design/brand-state.json` píše jen `aid-ui-state.sh`.

## Předání (P115)

Studio navrhuje s PM a klientem, plán a běh AIDu web nasazují a ověřují; mezi nimi je jeden soubor.

1. **Balík.** Převzetí (`aid-ui-state.sh chapter-all`, krok 7 bod 8) zapíše jako poslední krok
   `docs/ui/predani.json` (+ čitelný `predani.md`) podle `references/handover-package.schema.json`: web a jeho
   soubory se sha256, zaznamenaná brána, schválené kapitoly, verdikty míst, úkoly zákazníka, otevřené body,
   podklady ke spuštění, kritéria `launch_only`. Neúplný nebo zastaralý balík (web změněný po bráně) převzetí
   odmítne se jménem chybějící části a odpověď PM zůstane nepoužitá. Po převzetí se balík nemění; `aid-ui-package.py build` ho jen sestaví znovu (po chybě zápisu) a nový otisk pak znamená napsat zadání a plán znovu.
2. **Zadání plánu nasazení.** `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-package.py" zadani docs/ui/predani.json --plan-id P<NNN>` (nebo `/aid-plan`
   s balíkem jako vstupem) napíše zadání: bod hotovo za každý úkol zákazníka, krok spuštění
   (`references/local/spusteni.md`: nasadit přesně balík, HTTPS, hlavičky, 404, citlivé soubory, DNS, e-mail,
   katalogy, přesměrování), podklad ke spuštění (pokud už ho nenese otevřený bod), otevřený bod (kritický blokuje)
   a hodnocení po nasazení.
   Hosting je práce plánu, ne studia.
3. **Brána běhu `check_ui_handover`.** Plán z balíku nese `ui_package:`; brána ho bez balíku, se zastaralým nebo
   upraveným balíkem a s otevřeným kritickým bodem zastaví. Před nasazením tím končí („před nasazením“); po zápisu
   `docs/ui/nasazeni.json` (`url` a `listing` hostingu) ověří i ostrou adresu (`--launch`, bod zadání, bez něj neprojde) a pustí jen přesně soubory
   balíku, všechny formuláře na vlastní adresu webu, které hosting přijme, a kontrolu UI studia nad ostrou adresou.
   Plán bez balíku bránu přeskočí s důvodem.
4. **Hodnocení po nasazení.** `aid-ui-quality.py launch <project> --url <ostrá adresa>` - vlastní smyčka
   v `.aid-ui/critic/launch/` (kritéria `launch_only` se hodnotí), hodnocení stavby zůstane; `launch-status
   --package docs/ui/predani.json` je bod zadání.

## Start (každé spuštění)

1. Projekt = kořen repa, ve kterém PM `/aid-ui` volá (`git rev-parse --show-toplevel`).
2. Prohlížeč - skutečné volání: `mcp__plugin_playwright_playwright__browser_navigate`
   na `about:blank`. Selže → nástroje kroků běží přes `aid-ui-tool.sh` (Node
   Playwright, sám si doinstaluje `lib/ui-fidelity`); řekni to PM. Krok 1i
   (ikony) a krok 4 (vzory) MCP potřebují; bez něj stop s pokynem
   `/plugin install playwright@claude-plugins-official` (MCP hledá značkový Chrome →
   `PLAYWRIGHT_MCP_BROWSER=chromium` do `env` v `~/.claude/settings.json`
   a `npx @playwright/mcp install-browser chrome-for-testing`).
3. Standardy a šablony čti z kopií v pluginu: `references/standards/` (`frontend-build-standard.md`
   FB-1..FB-20, `webapp-tasks-states-standard.md` UA-1..UA-11, `design-system-standard.md`, SEO standard
   a `seo/`, šablony zadání značky a vize). Odkud je která kopie, říká `references/standards/SOURCES`,
   otisk `MANIFEST`; studio tak funguje i tam, kde ekosystémové dokumenty nejsou (P113).
4. Postup stavby: `references/adopted/frontend-design-SKILL.md` (snímek
   frontend-design) a řemeslné minimum `references/adopted/impeccable-craft-floor.md`;
   generické vzory vyřazuje `references/genericity-rubric.md`.

## Vrstva dílny a místa rozhodnutí (P113, 17. 10. 2026)

**Vrstva:** `references/local/` drží postupy, které dílna PM ověřila naslepo proti krokům studia (sdělení, logo,
pohyb značky, struktura, vzhled, kontrola). **Postup má přednost před tou částí kroku, kterou jmenuje** v řádku
„Nahrazuje“ - a jen před ní; všechno ostatní z kroku (vstupy, brány, zápisy stavu, nástroje) platí dál. Krok, který
postup nahrazuje, na něj odkazuje v bloku „Vrstva dílny“ a `sections.json` ho jmenuje mezi soubory metody (stvrzenka
`aid-ui-state.sh method` ho tedy vyžaduje).

**Šest míst rozhodnutí** (kolo `aid-ui-quality.py round <projekt> --place <místo>`, nejvýš první hodnocení + tři kola
oprav): `sdeleni` (otázka `vision`), `logo` (`identity`), `pohyb` (hlídá `build-record`), `struktura` (`structure`),
`vzhled` (`direction`), `web` (`handover`; každá role hodnotí měřítky hotového webu, vzhledu i struktury = šest známek).
Na každém místě dvě nezávislé role na Claude Opus (Codex záskok), obě s pamětí hodnotitele: **odborník** (síto:
řemeslo, fakta, zákon) a **klient** (majitel; jedna role přes všechna místa i odpovědi ve studiu). Brány
(`critic/<typ>.<role>.<místo>.gates.yaml`) zná jen kód, role ani studio je nevidí.

**Rozhodnutí místa** (`aid-ui-critic.py place-verdict`, zápis `aid-ui-state.sh place-record`): fakta a zákon > vada
řemesla od odborníka > volba klienta (D5); klient vybírá jen mezi směry, které prošly oběma rolemi (D2; v ručním
režimu vybírá PM `--pm-choice`, PM má vždy veto `--pm-veto`). Drží-li bránu jen chybějící vstup klienta (`studio_score`
s `to_ten.client`), místo končí `accepted_with_reservation` - „schváleno s výhradou, čeká na klienta“ (D1); chybějící
vstup klienta není kritérium práce studia. Schválit otázku místa jde jen s verdiktem nad aktuálními soubory místa
i míst, na kterých stojí. Projekt bez pohybu značky jen výjimkou PM (`place-record --place pohyb --without <odpověď>`).
`aid-ui-state.sh decide --step` bere přesný název kroku z `sections.json` (sdělení i logo patří do „Zadání a obsah“).

## Verze 1 je kompletní, kritik jen dolaďuje (PM 18. 10. 2026; P118 20. 10. 2026, všechna místa)

Kdo vyrábí verzi pro role, dodá ji **se vším ze zadání a ověřenou**: role ji mají nezávisle hodnotit 9-10 a najít jen
detaily. Před každým kolem místa (`aid-ui-quality.py round`, všechna místa, web i aplikace), v tomto pořadí:
1. **Soupis požadavků** ze zadání projektu (zadání, plán fáze, podklady) - každý bod se zdrojem `soubor:řádek`, pokrytý
   (`covered_by`: kde) nebo `out_of_scope` s důvodem. U aplikace na místě struktura míří `covered_by` na `task:<id>` nebo
   `screen:<id>` modelu.
2. **Návrh se píše proti nejvyšší kotvě** měřítek obou rolí místa a u existující aplikace proti tomu, **co appka
   opravdu dělá** (kód, roadmapa, runbook), ne proti zadání obrazovek (P116 kolo 5: tři ukázky popisovaly chování,
   které appka nemá). Fakta vytěží dva nezávislí čtenáři: `aid-ui-client.py facts <projekt>` (postup aplikace 3b).
3. **Lint modelu** (`aid-ui-screens.py check`, sekundy) bez nálezu.
4. **Strojové kontroly zelené:** u aplikace `aid-ui-verify.sh <projekt> --quick` nad kostrou a modelem teď (úlohy,
   stavy, klávesnice, obnova na nejširší šířce, asi 3 minuty; stačí i `--precheck`), u hotového webu brána a
   `gate-check`. Plná předběžná brána rozhoduje až předání.
Zápis `aid-ui-quality.py self <projekt> --place <místo> --file <kontrola.json>` (jen soupis požadavků) to ověří a váže
na otisk podkladů místa; `round` bez platné kontroly nad touto verzí nespustí. **Vlastní známky výrobce se nepíšou**
(P118: v pilotu vždy „9“, role 4,9-8,8 - nic nerozhodovaly).

**Nezávislý ověřovatel běží s rolemi, ne před nimi** (PM 21. 10. 2026, 1A; H5 běh 2: smyčka „ověřovatel dočista, pak
role“ stála hodinu bez jediného kola). `round` ho pustí sám souběžně s rolemi, pokud nad touto verzí ještě neběžel
(`aid-ui-client.py verify <projekt> --place <místo> --web <adresa verze>` jde pustit i ručně, třeba po opravě). Nástroj
nafotí, co člověk na každé adrese verze vidí (i vypnuté akce, obsah polí a potvrzení řečené slovy), a Codex (záskok
Claude Opus) to porovná s modelem, fakty a podklady projektu: ověří opravy minulého kola a hledá rozpory v celé verzi.
Výsledek je podepsaný záznam mimo projekt, který píše jen nástroj (podpis brání omylu a ruční úpravě, ne úmyslu toho,
kdo zná klíč); u každého výroku stojí, kde ho ověřovatel viděl, a nástroj odmítne adresu, která neslouží právě tuhle
verzi, i neúplné nafocení. **Jeho rozpory a opravy, které neviděl, jsou nálezy kola** (role `verify`): výrobce je
převezme a opraví spolu s nálezy rolí, jedním průchodem. Ověřovatel bez platné odpovědi, nebo verze změněná během
kola = kolo neproběhlo; záznam kola nese podpisy záznamů ověřovatele, ze kterých nálezy vzešly. Hodnocení nasazení
(`launch`) ověřovatele nepouští - hodnotí ostrou adresu, ne verzi souborů.

## Smyčka bez čekání, výrobce v čerstvém kontextu (P118, PM 20. 10. 2026)

- **Po kole hlas a pokračuj.** Hlášení PM (co role navrhly, co se udělalo, cena a čas) se pošle a smyčka jede dál;
  zastaví se jen na rozhodnutí, které je PM (P116: čekání bylo 3 h 21 min ze 6 h kola).
- **Opravy dělá podagent v čerstvém kontextu.** `aid-ui-quality.py brief <projekt> --place <místo>` napíše brief
  (nálezy k opravě, co dodal klient, lint, otevřené body ověřovatele, červené řádky rychlé kontroly); podagent dostane
  jen jeho cestu a vrátí u každého nálezu větu do `fixed --evidence`. Hlavní vlákno řídí a výpisy brány nečte
  (P116: 605 tis. tokenů kontextu na tah, 92 % ceny).
- **Plugin se během běhu studia nemění**; jeho verze se zapisuje ke kolu (`round.json` `plugin`).

## Opravy po přijatém kole: delta kolo, ne znovuotevření (P118, místa kromě hotového webu)

Když místo prošlo a výrobce verzi ještě opraví (nálezy přijatého kola), smyčka hlásí `delta`: jedno další kolo nad
opravenou verzí, role mají celou paměť nálezů. Teprve pak verdikt místa, aby stál na tom, co se předává. Znovuotevření
(`reopen`) je jen na přání PM; ani ono rolím paměť nemaže (P116 kolo 5: role bez paměti hodnotily místo jako nové).

## Co role nechají na klientovi, dodá klient-agent (P116, PM 19. 10. 2026, všechna místa)

Nález s `owner: client` a položky readiness („musí dodat klient“) nečekají na PM. Hned po kole (po triage) je
smyčka pošle klient-roli - nezávislému agentovi, který hraje vlastníka jako v AID runu:
`aid-ui-client.py supply <projekt> --place <místo>` (decision `supply`; další kolo bez toho nespustí). Klient odpoví
z podkladů projektu: fakt se zdrojem `soubor:řádek` a doslovnou citací (kód ji v souboru najde), volbu vlastníka jen
druhu jméno / výchozí hodnota / pořadí / výběr z možností s důvodem, a co v podkladech není (peníze, termíny, právo,
osobní údaje, dnešní postup) jako `missing`. Nález s odpovědí převezmi (triage) a oprav podle ní; role odpovědi vidí
v podkladech místa. V závěrečném hlášení PM je výpis `aid-ui-client.py decided <projekt>`: co klient-agent rozhodl
bez PM a co zbývá na PM.

## Dvě cesty: web a webová aplikace (P116, 18. 10. 2026)

Druh `webapp` vede vlastní cestou podle `references/local/aplikace-postup.md` (vrstva s předností jako ostatní
postupy); web a `pwa` jdou beze změny. Jedno studio a tytéž nástroje s větví podle druhu, nic se pro aplikaci
nekopíruje. Základem aplikace je model obrazovek a úloh `docs/design/screens.json` (`aid-ui-screens.py check`),
z něhož se staví kostra, testy úloh brány a předávací balík.

- **Části podle druhu:** aplikace má místo „Stránky a jejich části“ část „Obrazovky a úlohy“ a existující aplikace
  navíc „Výchozí stav aplikace“ (`sections.json`, `when: variant.app|variant.site|variant.existing`).
- **Co aplikace vynechá, má důvod:** slogan, hledání a logo (u `brand: existing|none`) se vynechávají volbami kroku 0
  a každá vynechaná část má záznam `decide --title přeskočeno --outcome "<část> přeskočena" --why …`; bez něj
  `aid-ui-state.sh step` aplikaci za krok 1 nepustí.
- **Úlohy schvaluje jen vlastník produktu (PM):** odpověď na otázku `structure` (i `task_map`) aplikace se zapíše jen
  od PM a s cílem `docs/design/screens.json@<sha modelu teď>` (`app_tasks_need_owner`); totéž výjimky
  `baseline@…` a `task@…` (`app_owner_only`). Hodnocení klient-role je podklad, ne rozhodnutí.
- **Předání aplikace:** balík verze 2 nese schválený model a výsledky úloh (`verified_on: skeleton`); `aid-ui-package.py zadani`
  z něj napíše zadání změn kódu (bod za úlohu a za cestu selhání) a brána běhu `check_ui_handover` pustí scénáře úloh
  proti běžící aplikaci projektu (`docs/ui/nasazeni.json`).

## Kroky a části (jak o nich mluvit)

Jediný zdroj číslování a smyslu je mapa `sections.json`: šest kroků studia
(Druh webu, Zadání a obsah, Vzory, Vzhled, Stavba, Kontrola) a jejich části v pořadí, každý krok i část s `why` (proč),
`goal` (cíl - podle čeho PM pozná, že je to dobře), `feeds` (k čemu výsledek poslouží dál) a část
navíc s `you` (co od PM chce). Studio je ukazuje samo (server čte mapu a stav). PM i ve zprávách
v chatu mluv jen takhle: „Krok 2 z 6: Zadání a obsah · část 5 z 6: Stránky a jejich části"
(části se počítají všechny v pořadí mapy, i vynechané - studio je ukazuje přeškrtnuté jako „vynecháno"). Nikdy vnitřní čísla souborů (0-7, 1p, 1v, 1i, 1s) ani zkratky
typu „2.5". Cíl a smysl nepiš do jednotlivých otázek - patří kroku a části a studio je ukáže.

| Soubor kroku (vnitřní) | Krok pro PM | Část |
|---|---|---|
| `steps/0-start.md` | 1 Druh webu | Co stavíme a co připravit |
| `steps/1-product.md`, `steps/1p-sources.md` | 2 Zadání a obsah | Podklady |
| `steps/1v-vision.md` | 2 Zadání a obsah | Vize a slogany |
| `steps/1i-identity.md` | 2 Zadání a obsah | Logo |
| `steps/1s-seo.md` | 2 Zadání a obsah | Hledání na Googlu |
| `steps/2-structure.md` | 2 Zadání a obsah | Stránky a jejich části |
| `steps/3-content-plan.md` | 2 Zadání a obsah | Obsah stránek |
| `steps/4-references.md` | 3 Vzory | Vzory |
| `steps/5-directions.md` | 4 Vzhled | Tři návrhy vzhledu |
| `steps/6-build.md` | 5 Stavba | Stavba webu |
| `steps/7-verify.md` bod 1a, 1b | 6 Kontrola | Kontrola textů |
| `steps/7-verify.md` bod 1-3 | 6 Kontrola | Technická kontrola |
| `steps/7-verify.md` bod 4 | 6 Kontrola | Pravidla vzhledu |
| `steps/7-verify.md` bod 5 | 6 Kontrola | Schválení stránek |
| `steps/7-verify.md` bod 6-9 | 6 Kontrola | Předání |
| `steps/8-quality.md` | po předání (panel Hotovo) | Hodnocení majitele a technika |

## Jak se ptá PM (studio)

Jediný způsob, jak se PM na cokoli ptát nebo mu dát cokoli ke schválení:

0. **Postup před výstupem** (PM 7. 10. 2026). Než napíšeš otázku s kartami, přečti postup jejího
   druhu: `aid-ui-state.sh method <project> <druh>` vypíše soubory postupu z mapy
   (`sections.json` → `methods`) a zapíše stvrzenku `.aid-ui/method/<druh>.json`. Otázku otevři
   až potom (`opened_at` po stvrzence, nejvýš 12 h) a na každé kartě napiš `method` = který
   soubor postupu a co z něj karta uplatňuje (vzorec, typ značky, rámec stránky; do 300 znaků,
   jméno souboru v něm musí být). Studio otázku druhu s výstupem (product_context, facts, vision,
   identity, seo_brief, structure, task_map, content_plan, references, direction) bez stvrzenky,
   se starou nebo s kartou bez `method` odmítne; hotová otázka projde jen se zaznamenanou
   odpovědí. Po každém zápisu payloadu spusť `aid-ui-state.sh payload-check <project>` - ukáže
   odmítnutí dřív než PM. Druh, který má v mapě `null`, postup nemá: nic nevymýšlej, polož otázku
   `no_method` (`part` části, target `no_method@<druh>`, tři karty s `value` adopt / pm / without,
   bez `method`); po odpovědi `method` zapíše waiver (pm: karty pak nesou `source` podklady,
   without: bez postupu), nebo postup převezmi (adopt: snímek do `references/adopted/`, řádky
   v `adopted-sources.md`, soubory do mapy) a `method` spusť znovu. Mapu čte studio při startu.
0b. **Předchozí rozhodnutí PM se nese dál** (PM 9. 10. 2026). Otázka, která staví na dřívější volbě PM
   (dnes `direction` na `references`; mapa `PRIOR` v serveru), nese `prior` = přesně zaznamenanou
   odpověď (`question`, `choice`, `comment`) a každá karta `honours` = jak volbu a slova PM ctí.
   Studio hlídá, že `prior` je přesně zaznamenaná odpověď a že `honours` jmenuje id volby; zda karta
   slova PM opravdu ctí, hlídá jen tvůj úsudek. Volbu i slova PM ukáže nad otázkou - PM nemá znovu
   vysvětlovat, co už řekl.
0c. **Méně kol, víc rozdílů (P113a bod 8).**
   - **Rozdíl:** otázka, která se vrací k věci, kterou PM nebo klient už jednou viděl (po vrácení nebo po změně),
     nese `previous` = id té dřívější otázky (stejný druh, stejný soubor nebo stránka). Studio i klient-agent
     dostanou jen to, co se změnilo: řádky souboru u souborového cíle (`<cesta>@<sha256>`), text stránky
     u `approve_page`. Snímek verze ukládá studio při prvním zobrazení otázky
     (`.aid-ui/studio/snapshots/`).
   - **Milník:** několik stránek nebo výjimek z jednoho okruhu je jedna otázka `approve_page` nebo `exception`
     s `items` a `target` `items@<sha položek>`. Každou položku spotřebuj
     `--answer <id> --answer-item <položka>` (kroky 7 bod 3 a 5). Studio odmítne payload s víc než jednou
     otevřenou samostatnou otázkou `approve_page`.
   - `previous` musí být zodpovězená otázka (rozdíl je proti tomu, na co čtenář odpověděl). U milníku
     se porovnávají položky se stejným id, společný styl (`_shared`) nese větu „změnil se vzhled, viz náhled“.
   - Ostatní druhy otázek zatím slučované nejsou (IMP-698).
1. Zapiš nebo obnov `<project>/.aid-ui/studio/payload.json`:
   `now` (`title`, `text` = co právě děláš, např. „Připravuji tři návrhy vzhledu…", `at` = kdy jsi to
   napsal, `part` = id části, pro kterou platí; studio tvou poznámku ukáže jen dokud je novější než
   poslední odpověď PM a patří k části, na které se pracuje, pak píše samo
   „Zpracovávám vaši odpověď: …" a `next` té otázky - proto `now` přepiš hned po každém `record-answer`;
   obnov ho při každé změně, stránka ho ukazuje vždy a sama bez otázek jen jeho),
   `steps[]` nepiš: kroky, části a jejich stav bere studio z mapy `sections.json` a ze stavu
   (`decide --step` dál bere název kroku z mapy), `questions[]`
   (`id`, `kind`, `part` = id části z mapy (povinné u `facts` a u druhu, který patří víc částem;
   jinak ho studio odvodí), `target`, `opened_at` = teď v ISO, `title`, `prompt`, `body`,
   `next` = co uděláš po schválení, `outcome` = výsledek po schválení jednou větou
   (povinné u všech druhů kromě výběru z karet, viz níže); volitelně `eyebrow` = nadpis
   nad otázkou místo výchozího podle druhu, u `set options` (druh variant) „Co připravit"),
   `cards[]` (`id`, `question`, `title`, `preview` = PNG/JPEG/WebP pod
   `.aid-ui/studio/`, `thesis`, `palette[]`, `risk`, `uniqueness`; volitelně
   `eyebrow` = řádek nad názvem karty, `tags[]` = štítky vedle palety, `url`
   u referencí, a další textová pole, která se ukážou na rubu karty „Detaily").
   Druhy otázek: variant, vision, identity, seo_brief, structure, task_map,
   content_plan, defer_content, facts, references, direction, approve_page,
   exception, coverage_drift, design_standard, handover, sources (krok 1p: jedno schválení
   seznamu podkladů `manifest@<sha>`, nebo průzkumu `online@<projekt>`), product_context (krok 1p: schválení dokumentu o produktu),
   copy_verdict (verdikt PM k textům webu), no_method (bod 0), notifications (PWA: posílá aplikace
   oznámení, o jakých událostech a proč; když ano, obrazovka přihlášení k odběru a karta povolení
   se stavy jako snímek - `pwa-notifications-standard`).
   Na co PM odpovídá textem nebo potvrzením (fakta k ověření, souhlasy, kontrola názvu),
   polož jako otázku `facts` s `outcome` a **třemi kartami s návrhy odpovědi**: první je doporučená
   (studio ji tak označí), vlastní odpověď dá PM přes „Chci to jinak"; každá karta má `thesis`
   (co to znamená), `uniqueness` (čím se liší od ostatních dvou, s číslem nebo faktem, když ho máš),
   `risk` a `source` - to platí pro karty všech otázek, ne jen pro údaje; karta jen s nadpisem
   a rizikem je tenká a PM z ní nevybere; každá karta má `source`
   z mapy `sources` (z čeho návrh vychází: `product-marketing:jobs|objections|switching|customer-language|proof`,
   `copywriting:before-writing`, `podklady`, `registr`, nebo `odhad` = tvůj odhad, který PM potvrdí).
   Otázku samotnou ber z převzatého postupu, který `source` jmenuje (product-marketing: za co si
   firmu zákazníci najímají, tři nejčastější námitky, co je žene od dnešního stavu, co je táhne, co je
   drží, čeho se bojí, jejich doslovná slova; copywriting: účel stránky, publikum, nabídka, odkud
   lidé přicházejí), nikdy z vlastní hlavy. Studio otázku `facts` bez tří karet s `source` odmítne;
   pravdivost zdroje neověří - to je na tobě. Co zvládneš sám (rešerše názvu v rejstříku a na
   webu, dohledání údaje), udělej předem a PM dej rozhodnutí nad výsledkem („Našel jsem
   tyto podobné názvy: … Ponechat Needless?"), ne úkol „zkontrolujte". Jeden slovník
   stavu: „návrh (náhled) hotový" → „před zveřejněním zbývá" → „zveřejněný"; nepiš
   „předán", „spuštěn".

   **Jak napsat otázku.** `title` = krátká lidská otázka (do ~12 slov). `body[]` =
   2–4 krátké věty: co navrhuješ, proč (odkud to víš, např. „z vašeho zadání")
   a co to znamená pro web. `next` = co uděláš po schválení. Vykej. Zakázané:
   názvy souborů, technické zkratky bez vysvětlení (404, SEO, JSON…),
   angličtina, „Souhlasí?".
   - Špatně: „Needless: prezentační web (jedna stránka + 404), značka existuje
     (znak N, písma Archivo a Caveat), místní firma z Mohelnice. Souhlasí?"
   - Dobře: `title` „Jaký web pro Needless postavíme?", `body` „Navrhuji jednu
     delší stránku, na které návštěvník během pár vteřin pozná, co děláte a pro
     koho, a může vám rovnou napsat." „Vycházím z vašeho zadání, kde je jedna
     stránka a vlastní stránka pro neexistující adresu.", `next` „Připravím
     zadání pro vyhledávače a obsah stránky." (`next` se ukáže až po schválení,
     proto začíná tím, co udělám, ne „Po schválení…")
   **Jak napsat `outcome`.** Platný výsledek, ne další krok ani průběh; srozumitelný bez
   otázky; do 120 znaků; bez „Schváleno", „Doplním", „Takhle". U výběru z karet (druh
   s `choose`) ho nepiš: stránka ukáže název vybrané karty z uložené odpovědi, aby text
   nemohl odporovat tomu, co PM vybral.
   - Špatně: „Schváleno." · „Doplním to do vize." · „Takhle budou stránky poskládané."
   - Dobře: „Klasický web se samostatnou stránkou pro každé téma." · „Sedm stránek, každá
     odpovídá na jednu věc, kterou lidé hledají." · „Texty všech stránek schváleny; čtyři
     údaje zbývá ověřit."
   V žádném textu, který PM uvidí (otázky, karty, `outcome`, `now`, záznamy `decide`), nepoužívej: agent, kapitola, kolo,
   převzetí, payload, standard (kromě odkazu na report), skill.
   Studio ukazuje běh jako šest kroků pod sebou: u každého výsledek jednou větou a kdo
   rozhodl (PM, AI, nebo oba). Detail kroku otevře jeho rozhodnutí a karty, ze kterých PM
   vybíral; čekající otázka je uvnitř svého kroku. Každou přijatou odpověď si studio samo
   uloží i s otázkou, kartami a kopií náhledů do `.aid-ui/studio/history.jsonl`; ten
   záznam je jen pro zobrazení, nečti ho jako rozhodnutí.

   **Když rozhoduje agent sám.** Když krok rozhoduje sám (fakt z PRODUCT.md, volba podle
   standardu, výsledek stavby), zapíše to hned příkazem `aid-ui-state.sh decide <project>
   --step "<název kroku>" --title "<co>" --outcome "<výsledek jednou větou>" --why "<odkud
   to plyne>" [--source <soubor>]`; bez zápisu rozhodnutí neexistuje. `outcome` platí
   stejná pravidla jako u otázek (do 120 znaků, `title` do 80, `why` do 300). `decide`
   nic nemění ve stavu: fakt nebo volbu dál zapisuje její vlastní příkaz, `decide` jen
   zaznamená, že ji udělal agent. Opakovaný krok, který rozhodne totéž (stejný krok,
   `title` a `outcome`), dostane exit 0 a druhý záznam nevznikne. Exit 1/2 zastaví krok
   jako každý jiný příkaz stavu. Kde přesně krok volá `decide`, říká jeho `Postup`.
2. `target` je to, co PM schvaluje: u `set variant|options|structure|content-plan|refs`
   `sha256:` + `jq -S -c -j . <<<"$json" | sha256sum` přesně toho JSON, který
   pak zapíšeš (JSON vždy v souboru pod `.aid-ui/` psaném nástrojem Write,
   do příkazu jako `"$(cat <soubor>)"`); u převzetí kapitoly
   `aid-ui-state.sh chapter-target <project> <id>` (váže id kapitoly i její
   uložené tělo, odpověď pro jinou kapitolu neplatí), u převzetí všech kapitol
   najednou (`handover`, krok 7) `aid-ui-state.sh chapter-all-target <project>`;
   u ostatních druhů podle
   hlavičky `aid-ui-state.sh`.
3. `aid-ui-serve.sh studio <project>` (spustí nebo použije běžící studio)
   vypíše jednorázový odkaz `URL: http://<host>:3915/?k=<kód>`; ten dej PM
   (jen při první otázce běhu nebo po restartu studia - stránka ukazuje další
   otázky sama).
4. Na odpověď čekej sám, PM nemá psát do chatu: spusť na pozadí
   (`run_in_background`) `until aid-ui-state.sh record-answer <project> --question <id> ||
   aid-ui-state.sh changes <project>; do sleep 5; done` a ukonči tah; po jeho dokončení pokračuj.
   Smyčka skončí odpovědí, nebo tím, že PM u některé uložené odpovědi stiskl „Změnit": `changes`
   vypíše novou otázku `<id>.c<n>` (stejný druh, cíl, část, text, karty). Přidej ji do payloadu
   i s kartami, počkej na její odpověď a proveď mutaci kroku znovu s `--answer <nové id>`. Když ji
   skript odmítne, protože běh už pokročil (např. `set options` jen v prvním kroku), vrať běh
   `aid-ui-state.sh step` na vnitřní krok té části, zopakuj ji a vše, co z ní plyne, a pokračuj.
   Zodpovězené otázky z payloadu nemaž: po `record-answer` jim nastav `"done": true`
   a `"answer_title"` (co PM vybral, slovy), studio je ukazuje jako „Uloženo" s tlačítkem
   „Změnit". Kartu PM vybere klikem kamkoli na ni a odešle tlačítkem „Další"; pod kartami je jeden
   řádek: Bezpečněji, Znovu, Odvážněji, „Chci to jinak" (otevře okno na text: PM ho pošle jako svou
   odpověď = `return` s komentářem, nebo jako pokyn pro nové návrhy = `reroll` s komentářem; u otázky
   bez karet i jako souhlas s poznámkou = `approve` s komentářem) a vpravo „Další". Studio ukazuje
   šest kroků jako pruh nahoře (u prohlíženého kroku (i) s tím, o čem je) a pod ním jen jeden krok;
   části kroku jsou řada pilulek vždy na stejném místě, pod otázkou je jeden odstavec o části (`text`
   z mapy `sections.json`); z každé části je vidět jedna otevřená otázka po druhé („Otázka 1 ze 2")
   a po poslední studio přejde samo na další část. Více otevřených
   otázek = jedna smyčka na každou. Napíše-li PM mezitím do chatu, zkus
   `record-answer` hned; exit 1 = odpověď ještě není.
5. Rozhodnutí `approve`/`choose` → mutace s `--answer <id>` (jen tam, kde
   krok nějakou jmenuje). Po `choose` je vybraná karta ta s `id` = `choice`
   zaznamenané odpovědi (`jq '.answers["<id>"].choice' brand-state.json`)
   mezi `cards` téže odpovědi - snímkem karet, jak je studio PM ukázalo
   v okamžiku odpovědi (`jq '.answers["<id>"].cards' brand-state.json`,
   uložil ho `record-answer`), nikdy znovu z payloadu (ten se mohl
   od odpovědi změnit); do stavu nebo těla kapitoly jde obsah té karty beze
   změny (`thesis`, `url`, `palette`, náhled), nikdy karta jiné otázky.
   Náhled zkopíruj, jen když `sha256sum` souboru = `preview_sha256` karty;
   jinak se od odpovědi změnil a otázku otevři znovu.
   `return` → PM vrací s komentářem; oprav a otevři
   otázku znovu (nové `opened_at`). `reroll`/`reroll_safer`/`reroll_bolder`
   (Znovu = ve stejném duchu / Bezpečněji / Odvážněji) → odpověď
   nese `next_question`; vytvoř nové karty podle komentáře a zapiš je pod tím
   id do payloadu.

## Co ještě nástroj hlídá (P108, 10. 10. 2026 - po pilotu Coufal 6/10)

- **Pohyb vzoru** (`aid-ui-tool.sh motion`, `aid-ui-motion.py`): záznam vybraného vzoru pozoruje nástroj
  za běhu (načtení, druhé načtení, posun, najetí, zaměření, přechod stránky); soupis
  `.aid-ui/motion.json` říká u každého pohybu převzat / nahrazen / vynechán s důvodem a lidským
  jménem; studio odmítne otázku `direction` bez soupisu (cíl `smer:<otisk>`, blok `motion`) nebo se
  směrem, jehož pozorování soupis neprokáže (server kontrolu přepočítá sám); `build-record` odmítne
  stavbu bez stvrzenky postupu `build` a bez téhož důkazu nad stavbou; brána má řádky
  `content_without_js` a `first_paint_visible` (FB-27: obsah čitelný bez skriptu, hned po načtení a při omezeném pohybu),
  `motion_settled` (měří po doběhnutí animací, úvod jen přes `data-aid-intro`) a `motion_fidelity`
  (pozoruje stavbu sama). Pohyb se nikdy neosekává kvůli bráně. Od 11. 10. 2026 (PM 2B) záznam vzoru
  pokrývá i podstránky (`--pages 8`, položky s `pages`) a soupis smí u `replace` uvést `from` = druhý vzor
  PM, jehož záznam pohyb prokáže.
- **Konec běhu**: `links` (dvě adresy, 200) před otázkou `handover`, která je nese v textu a má tři
  karty (převzít / s výhradou / vrátit = hodnocení PM); `chapter-all` jen po poslední bráně nad
  stránkou pro zákazníka a zprávě souladu; `finish` zapíše `finish.json` a studio ukáže Hotovo
  s odkazy, otevřenými body (`open-item`, PM si přidá sám) a větou z převzetí.
- **Stará historie studia** (před 9. 10. bez otisku karet): obnovená odpověď nese otisk karet z dnešního
  payloadu a `migrated: true`; stavový skript ji přijme jen při shodě s otiskem, který zapsal živě.

## Směrování

- Bez argumentu: krok = `jq .step <project>/docs/design/brand-state.json` (soubor
  chybí → krok 0).
- `/aid-ui <n>` (číslo kroku pro PM 1-6) → vnitřní krok podle tabulky výše (1→0, 2→1, 3→4, 4→5,
  5→6, 6→7), `aid-ui-state.sh step <project> <vnitřní>`, pak ten krok.
- Načti jen soubor kroku a proveď ho. Po úspěchu kroků 0-6
  `aid-ui-state.sh step <project>` s číslem následujícího kroku; krok 7 končí
  `aid-ui-state.sh finish <project>`.
- `brand-state.json.finished` vyplněné → běh je hotový; nabídni krok
  k opakování (`/aid-ui <n>`; krok zpět vynuluje `finished`).
- Selže skript: ukaž PM jeho řádek `ERROR:`, krok neposouvej.

| Krok | Soubor |
|---|---|
| 0 | `steps/0-start.md` - varianta, inventura, kontrola pokrytí |
| 1 | `steps/1-product.md` (+ `steps/1p-sources.md`, `steps/1v-vision.md`, `steps/1i-identity.md`, `steps/1s-seo.md`) |
| 2 | `steps/2-structure.md` - stránky, role, toky; aplikace: obrazovky a úlohy (`references/local/aplikace-postup.md`) |
| 3 | `steps/3-content-plan.md` - obsah a fakta |
| 4 | `steps/4-references.md` - vzory |
| 5 | `steps/5-directions.md` - tři směry jako stránky |
| 6 | `steps/6-build.md` - stavba |
| 7 | `steps/7-verify.md` - ověření, schválení, `finish` |
| po `finish` | `steps/8-quality.md` - smyčka kvality se dvěma kritiky (majitel a technik, souběžně, s pamětí) do 8,5 u obou nebo tří kol oprav (není krok stavu, `step 8` neexistuje) |

Skripty (`$AID_PLUGIN_PATH/scripts/`): `aid-ui-state.sh` (jediný zapisovatel
stavu a těl kapitol v `docs/brand/index.html`), `aid-ui-serve.sh`,
`aid-ui-coverage.sh`, `aid-ui-tool.sh` (`glyph`, `webp`, `verify`, `measure`, `wordmark`, `png`),
`aid-ui-design-to-css.sh`, `aid-ui-ico.py`, `aid-ui-seo-check.py` (SEO a AI, krok 1s a brána),
`aid-ui-brand-package.py` (balíček značky), `aid-ui-design-standard.py` (design standard, krok 7),
`aid-ui-vision-check.py` (vize), `aid-ui-customer-page.py` (stránka pro zákazníka po bráně, krok 7 bod 7b),
`aid-ui-sources.py` (podklady, krok 1p), `aid-ui-copy.py` (kontrola textů, krok 7 bod 1a; texty stránek dává
`aid-ui-verify.sh <project> --copy-subject`), `aid-ui-critic.py` (měřítka majitele a technika, zmrazení), `aid-ui-client.py`
(klient-agent ve studiu, hodnocení kritika, kniha nákladů), `aid-ui-quality.py` (smyčka kvality po předání), `aid-ui-launch.py` (podklady ke spuštění, krok 0 bod 10), `aid-ui-photos.py` (vlastní fotky klienta ze starého webu, krok 3 bod 2c), `aid-ui-preview.py` (náhled a příjemce formuláře).

## Zprávy PM

Formát podle `/opt/eco/CLAUDE.md` „Jak agent píše Markovi": česky, lidsky,
jedno rozhodnutí = jedna otázka ve studiu s doporučením; chat nese shrnutí
a odkaz.

---

## MUST Rules

1. Never without the PM: every choice and approval (variant, vision, slogan,
   logo, SEO pages, structure, content plan, references, direction, pages,
   exceptions) is the PM's. A missing answer ends the turn with a background
   wait for it ("Jak se ptá PM", step 4); no step proceeds unattended and no step writes state directly.
2. Answers come only through `aid-ui-state.sh record-answer`, and a mutation
   that needs the PM takes `--answer <id>`; an answer read from chat is never
   a decision.
3. Ecosystem standards and templates are read from the plugin's copies in `references/standards/`
   (source in `SOURCES`, blob ids in `MANIFEST`, P113); nothing is read from the ecosystem docs tree.
4. The build follows the frontend-design snapshot
   `references/adopted/frontend-design-SKILL.md`; no other design tool.
5. No invented facts (prices, addresses, references, numbers, quotes): a fact
   comes from the PM or the project and is listed in `docs/content/facts.yaml`.
   No placeholders (lorem ipsum, "Váš text", fake logos) in anything the PM
   sees or the build ships; missing material goes through step 3.
6. Step 0 runs `aid-ui-coverage.sh check`; exit 1 or 2 stops the run.
7. Gallery blocks (403/429/captcha) are never bypassed. Third-party screenshots
   live only in `<project>/.aid-ui/refs/` (gitignored, outside `docs/brand/`)
   and are deleted after step 5.
8. Chapter bodies are written only by `aid-ui-state.sh body <project> <id> --file <html>`;
   nothing internal lives in the served `docs/brand/`.
9. A page is "reviewed" only with a `copy_review` pass of the independent copy review (step 7
   point 1a: `aid-ui-copy.py`, verdict computed by the script, `aid-ui-state.sh copy-record`) or a
   PM exception; the agent never reviews its own copy, never writes a run's `run.json` or answer by
   hand, and writes copy only by the adopted method (`references/copy-rules.md`, `copy-<jazyk>.md`).
11. Steps and parts are named only by the map `sections.json` ("Krok N z 6: … · část M z K: …"); internal
   step numbers never reach the PM. A `facts` question carries `part` and at least three cards, each
   with a `source` from the map; the studio refuses the payload otherwise.
10. A decision a step makes without the PM (only where its `Postup` says so) is recorded
   at once with `aid-ui-state.sh decide` ("Když rozhoduje agent sám"); an unrecorded
   agent decision does not exist for the PM.
12. The method before the output: no card of a receipt kind is written before
   `aid-ui-state.sh method` printed that kind's method files (the studio refuses it);
   a kind whose method is null is a `no_method` question to the PM, never an output
   from the agent's own head ("Jak se ptá PM", point 0).

---

13. P113: a procedure under `references/local/` wins over the part of a step it names ("Nahrazuje") and only that
    part; an accepting answer of a decision place's question (vision, identity, structure, direction, handover) and
    `build-record` need that place's current verdict (`aid-ui-state.sh place-record`); the roles never see the gates.

## Completeness Gate

Před posunem kroku:

- [ ] každá otázka kroku má zaznamenanou odpověď (`jq .answers <state>`) a její mutace prošla;
- [ ] každá kapitola, kterou krok mění, má tělo přes `aid-ui-state.sh body` a stav přes `aid-ui-state.sh chapter`;
- [ ] PM dostal v chatu shrnutí a odkaz (studio nebo `aid-ui-serve.sh brand docs/brand`);
- [ ] v `docs/brand/` není nic cizího (screenshoty galerií jen v `.aid-ui/refs/`).

---

## Reference Files

- `steps/0-start.md` … `steps/7-verify.md` - postup kroků (tabulka výše); `steps/8-quality.md` - smyčka kvality po předání.
- `references/adopted/frontend-design-SKILL.md`, `references/adopted/impeccable-craft-floor.md`.
- `references/genericity-rubric.md` - vyřazení generických vzorů a směrů.
- `references/adopted/marketingskills/` - převzaté postupy textů (product-marketing, copywriting,
  copy-editing, customer-research, cro; MIT, commit `dda3841`, `MANIFEST`); kdo je čte, říká
  `references/adopted-sources.md`.
- `references/copy-rules.md`, `references/copy-cs.md`, `references/copy-sk.md`, `references/copy-en.md` -
  pravidla textů AID a jazykové příručky; `references/copy-review.schema.json` - tvar odpovědi revizora.
- `references/brand-icons.js` - vykreslení ikon (krok 1i).
- `coverage/{map,checks,sources}.yaml` - pokrytí standardů.
- `brand-page/` - šablona brand stránky a `state.template.json`.

**Last Updated:** 2026-10-07
