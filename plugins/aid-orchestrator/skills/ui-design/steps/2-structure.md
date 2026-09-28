---
name: ui-design-step-2
description: /aid-ui step 2 - site structure (pages and sections) or app structure (roles, navigation, key flows with seven states), confirmed on the studio page
user_invocable: false
---

# Krok 2 - Struktura

**Last Updated:** 2026-09-28

## Cíl

PM ve studiu schválil strukturu a `aid-ui-state.sh set structure` ji
zapsal; kapitola `struktura` ji ukazuje.

## Vstupy

`PRODUCT.md`, `variant`, potvrzený seznam stránek z `docs/seo/brief.md`
(je-li), `/opt/eco/docs/docs/ecosystem/specs/webapp-tasks-states-standard.md`
a `frontend-build-standard.md` (čti živě).

## Postup

1. Web (`variant.type` = `web`): stránky (id, URL, H1 ze SEO briefu,
   je-li) a na každé sekce v pořadí (co sekce říká, jakou akci nabízí).
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
   `return` s komentářem → uprav JSON i obrázky, nová otázka.
6. Tělo kapitoly `struktura` (strom stránek, u aplikace tabulka tok×stav,
   drátěné modely zkopírované do `docs/brand/assets/`) do souboru
   v `.aid-ui/`, `aid-ui-state.sh body <project> struktura --file <soubor>`,
   `aid-ui-state.sh chapter <project> struktura navrh`.

## Co PM rozhoduje

Stránky a sekce, u aplikace role, navigaci a toky se stavy - ve studiu.

## Zápis

`structure` ve stavu (jen skript), kapitola `struktura`, `docs/brand/assets/`.

## Když krok selže

Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4. `set structure` odmítne JSON
nebo odpověď → ukaž `ERROR:` PM.

**Last Updated:** 2026-09-28
