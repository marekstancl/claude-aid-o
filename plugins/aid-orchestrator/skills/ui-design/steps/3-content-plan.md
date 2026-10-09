---
name: ui-design-step-3
description: /aid-ui step 3 - content plan per page and section (need, owner, due, status) and the facts register, confirmed on the studio page
user_invocable: false
---

# Krok 3 - Obsahový plán

**Last Updated:** 2026-10-03

## Cíl

Každá sekce každé stránky má položku obsahu s potřebou, vlastníkem,
termínem a stavem; fakta leží v `docs/content/facts.yaml`; PM plán schválil
a chybějící podstatný materiál buď dodal, nebo ho odložil.

## Vstupy

`structure` ze stavu, `PRODUCT.md`, `docs/product-vision.md`,
`docs/seo/brief.md`, materiál od PM (texty, fotky, ceník).

## Postup

Nejdřív `aid-ui-state.sh context-check <project>`; neprojde → zpět na krok 1p (`steps/1p-sources.md`).

1. Pro každou stránku a sekci položka: `id` (`<stránka>.<sekce>`), `need`
   (co je potřeba: text, fotka, ceník, reference), `owner` (PM, klient,
   agent), `due` (datum), `status`: `missing`, `draft`, `confirmed_client`,
   `deferred_by_pm`. PM, který dodal všechny texty: jeho položky začínají
   `confirmed_client` tam, kde to sám označí.
2. Registr faktů `docs/content/facts.yaml`: každé tvrzení, které stavba
   použije (ceny, adresa, otevírací doba, čísla, citace, reference), se
   zdrojem (`PM`, soubor projektu). Co v registru není, stavba nesmí
   napsat (MUST 5). Otázka `facts` ve studiu, když fakt chybí: s `part` `obsah` a třemi
   návrhy odpovědi, každý se zdrojem z mapy (`SKILL.md` „Jak se ptá PM"); u příběhů, výsledků a důkazů
   ber otázku z product-marketing (`product-marketing:proof`, `:jobs`, `:switching`), ne z hlavy.
   Brána (`facts_match`) chytí i počty s významem (klienti, projekty, roky praxe), procenta a
   e-maily: zapiš je do registru s klíčem, který význam nese (`klienti: 200`, ne jen `200`).
   Registr je mapa `klíč: {value, source}`; údaje o firmě mají pevné klíče, podle kterých
   brána porovná strukturovaná data webu: `brand` (název), `ico`, `email`, `telephone`,
   `domain` (`https://…`), `place`. Klíč, který firma nemá (telefon), se vynechá; bez
   `brand` a `ico` brána firmu jen varuje jako nezkontrolovanou.
3. Agent smí psát `draft` jen z faktů registru a podle „Jak psát vizi,
   slogany a texty" (`steps/1v-vision.md`); `confirmed_client` dává jen PM.
   Pořadí a obsah sekcí každé stránky navrhni podle rámce stránky z
   `references/adopted/marketingskills/cro/SKILL.md` (Page-Specific Frameworks: Homepage,
   Landing Page, Pricing Page, Feature Page; stránka služby nebo produktu jde podle Feature Page) a podle „Page Structure Framework"
   převzatého copywritingu; právní stránka (`legal: true` z kroku 2) rámec nemá. Jazyk stránky
   bez `references/copy-<jazyk>.md`: piš podle `copy-rules.md` a převzatých anglických pravidel
   a PM ve studiu jednou řekni, že kontrola textů takovou stránku pustí jen s jeho výjimkou.
4. Otázka `content_plan` ve studiu: tabulka položek (stránka, sekce,
   potřeba, vlastník, termín, stav), `target` = sha256 JSON pole položek.
   JSON zapiš nástrojem Write do `<project>/.aid-ui/content-plan.json` (nikdy ne
   jako shellový literál) a po `approve`:
   `aid-ui-state.sh set <project> content-plan "$(cat <project>/.aid-ui/content-plan.json)" --answer <id>`.
5. Chybí podstatný materiál (`missing` u sekce, bez které stránka nedává
   smysl) → PM ho dodá, nebo otázka `defer_content` s `target` = id
   položky a po `approve`
   `aid-ui-state.sh defer-content <project> <item id> --answer <id>`.
   Nikdy zástupný text místo materiálu.
6. Tělo kapitoly `obsah` (tabulka plánu, co chybí a kdo to dodá) do
   souboru v `.aid-ui/`, `aid-ui-state.sh body <project> obsah --file <soubor>`,
   `aid-ui-state.sh chapter <project> obsah navrh`.

## Co PM rozhoduje

Plán obsahu, fakta, dodání materiálu nebo jeho odložení - ve studiu.
`finish` v kroku 7 pustí jen položky `confirmed_client` nebo `deferred_by_pm`; `confirmed_client` dává
schválený verdikt textů (`confirm-content`, krok 7 bod 1b) nebo odpověď na údaj u jedné položky.

## Zápis

`content_plan` ve stavu (jen skript), `docs/content/facts.yaml`, kapitola
`obsah`.

## Když krok selže

Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4. Skript odmítne → `ERROR:` PM.

**Last Updated:** 2026-10-03
