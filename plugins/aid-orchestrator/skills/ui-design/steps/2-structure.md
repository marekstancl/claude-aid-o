---
name: ui-design-step-2
description: /aid-ui step 2 - site structure (pages and sections) or app structure (roles, navigation, key flows with seven states), confirmed on the studio page
user_invocable: false
---

# Krok 2 - Struktura

**Vrstva dílny (P113):** `references/local/struktura-postup.md` má přednost před postupem stromu a sekcí (úkoly zákazníka první, rozsah obsahu je volba klienta - výchozí výběr 8–12 s detailem + úplný seznam). Ze `structure.json` staví živou kostru `aid-ui-serve.sh skeleton <projekt>` na stálé adrese. Místo: `struktura`, kolo `aid-ui-quality.py round <projekt> --place struktura --web <adresa kostry>`.

**Webová aplikace (P116):** u `type: webapp` platí místo bodů 2-6 níže `references/local/aplikace-postup.md` (oddíly 1 a 2):
model obrazovek a úloh `docs/design/screens.json`, kostra z něj a otázka `structure` s cílem
`docs/design/screens.json@<sha>`, kterou zodpoví vlastník: klient-agent (hraje PM, jako nezávislý agent v AID runu), PM ho může přebít.

**Last Updated:** 2026-09-28

## Cíl

PM ve studiu schválil strukturu a `aid-ui-state.sh set structure` ji
zapsal; kapitola `struktura` ji ukazuje.

## Vstupy

`PRODUCT.md`, `variant`, potvrzený seznam stránek z `docs/seo/brief.md`
(je-li), `references/standards/webapp-tasks-states-standard.md`
a `references/standards/frontend-build-standard.md` (kopie v pluginu, zdroj v `references/standards/SOURCES`).

## Postup

1. Web (`variant.type` = `web`): stránky (id, URL, H1 ze SEO briefu,
   je-li) a na každé sekce v pořadí (co sekce říká, jakou akci nabízí).
   Stránka, která nic neprodává a jen plní povinnost (ochrana osobních údajů, obchodní
   podmínky, cookies, reklamační řád), dostane `"legal": true` (`references/copy-rules.md`,
   oddíl Právní stránky); kontrola textů u ní nečeká konverzní body.
2. Aplikace (`webapp`, `pwa`): role, navigace (hlavní položky a kdo je
   vidí), klíčové toky (úlohy z UA-1) a u každého sedm stavů standardu:
   běžná cesta, chyba validace, prázdno, načítání, selhání, oprávnění
   (role), obnova po přerušení. Stav, který u úlohy nedává smysl, se
   vynechá s důvodem. Veřejné stránky aplikace jako u webu.
3. Hrubý drátěný model (wireframe) každé stránky nebo obrazovky toku:
   jednoduché HTML bez barev, vyfocené přes Playwright do PNG pod
   `.aid-ui/studio/`; žádný vymyšlený text - popisky sekcí, ne obsah.
4. JSON struktury: `{"pages":[{"id","url","sections":[…]}],
   "roles":[…], "flows":[{"id","role","states":[…]}]}` (`roles`
   a `flows` jen u aplikace). Otázka `structure` (u aplikace tok×stav
   navíc `task_map`) ve studiu s drátěnými modely jako kartami, `target` =
   sha256 JSON (`SKILL.md` „Jak se ptá PM").
5. JSON zapiš nástrojem Write do `<project>/.aid-ui/structure.json` (nikdy ne
   jako shellový literál) a po `approve`:
   `aid-ui-state.sh set <project> structure "$(cat <project>/.aid-ui/structure.json)" --answer <id>`.
   `return` s komentářem → uprav JSON i obrázky, nová otázka. Komentář z „Vrátit s poznámkami“
   má řádek na stránku (`Stránka „<název>“: <co jinak>`): předělej jen jmenované stránky podle téhož
   rámce (cro, Page-Specific Frameworks) s poznámkou jako vstupem, ostatní nech beze změny.
6. Tělo kapitoly `struktura` (strom stránek, u aplikace tabulka tok×stav,
   drátěné modely zkopírované do `docs/brand/assets/`) do souboru
   v `.aid-ui/`, `aid-ui-state.sh body <project> struktura --file <soubor>`,
   `aid-ui-state.sh chapter <project> struktura navrh`.
7. Jen PWA: otázka `notifications` - co aplikace oznamuje, kdy a komu, a jak vypadá
   oznámení se stavy (nové, přečtené, chyba) jako snímek (`pwa-notifications-standard`).
   Odpověď do kapitoly `struktura`.

## Co PM rozhoduje

Stránky a sekce, u aplikace role, navigaci a toky se stavy - ve studiu.

## Zápis

`structure` ve stavu (jen skript), kapitola `struktura`, `docs/brand/assets/`.

## Když krok selže

Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4. `set structure` odmítne JSON
nebo odpověď → ukaž `ERROR:` PM.

**Last Updated:** 2026-09-28
