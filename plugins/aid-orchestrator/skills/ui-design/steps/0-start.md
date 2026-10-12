---
name: ui-design-step-0
description: /aid-ui step 0 - variant chosen on the studio page, existing brand package inventoried, coverage check, brand page skeleton
user_invocable: false
---

# Krok 0 - Start

**Last Updated:** 2026-09-28

## Cíl

Pokrytí standardů sedí, víme, co projekt už má, PM ve studiu zvolil variantu
a volitelné části kroku 1 a brand stránka `docs/brand/` existuje.

## Vstupy

Projekt: `docs/design/brand-package/` (nebo `docs/design/*brand-package*`),
`PRODUCT.md`, `DESIGN.md`, `docs/product-vision.md`, běžící web (`docker ps`
podle názvu projektu), zamítnuté návrhy.

## Postup

1. `aid-ui-coverage.sh check <project>`: exit 1 (mezera v mapě) nebo 2
   (standard nejde přečíst) → stop, ukaž PM výpis. Exit 3 (změnil se jen
   text standardu) → otázka `coverage_drift` ve studiu, `target` = id
   změněných položek seřazená a spojená čárkou; bez odpovědi `approve`
   `finish` v kroku 7 neprojde.
2. Existuje `docs/design/brand-state.json` → nic nepřepisuj, pokračuj krokem
   z něj. Jen staré `docs/brand/state.json` → `aid-ui-state.sh init <project>`
   ho převede; pak pokračuj krokem z něj.
3. Inventura: co z Vstupů existuje. Existující brand balíček (logo, favicony,
   písma) se jen popíše a odkáže, nikdy se nekopíruje podruhé.
   `DESIGN.md` z dřívějšího nástroje **není** zvolený směr.
4. `aid-ui-state.sh init <project>`; zkopíruj
   `brand-page/{index.html,base.css,tokens.css,roles.css}` do `docs/brand/`
   (`__PROJECT__` nahraď HTML-escapovaným názvem projektu).
5. Do `.gitignore` projektu přidej `.aid-ui/` (jen chybí-li).
6. Brand balíček existuje → tělo kapitoly `logo` (logo a odkaz na balíček)
   do souboru v `.aid-ui/`, `aid-ui-state.sh body <project> logo --file <soubor>`,
   `aid-ui-state.sh chapter <project> logo navrh`.
7. Otázka `variant` ve studiu (`SKILL.md` „Jak se ptá PM"), s doporučením
   z inventury u každé volby:
   - `type`: `web` (prezentační web), `webapp` (aplikace s přihlášením),
     `pwa` (instalovatelná aplikace - manifest a ikony pro instalaci jsou
     povinné položky mapy pokrytí);
   - `brand`: `new` (nová identita), `existing` (balíček existuje),
     `none` (interní nástroj - jen favicona, vize volitelná s důvodem);
   - `local`: `true`, když jde o místní firmu (adresa, otevírací doba);
   - volitelné části kroku 1: vize, identita (`"new"`, `"package"`, nebo
     `false`), SEO.
8. Volitelné části jsou druhá otázka druhu `variant`. Obě otázky mají tři karty
   a **každá karta nese `value`** = JSON, který ta karta znamená (u varianty
   `{"type":…,"brand":…,"local":…}`, u voleb `{"vision":…,"identity":…,"seo":…}`);
   `target` otázky = sha256 kanonického JSON mapy `{id karty: value}` všech jejích
   karet. PM tak může vybrat kteroukoli kartu, ne jen doporučenou. Vybere-li PM
   u varianty jinou značku než doporučenou, karty voleb připrav až podle jeho
   odpovědi. `value` vybrané karty zapiš nástrojem Write do
   `<project>/.aid-ui/variant.json` a `<project>/.aid-ui/options.json` (nikdy
   ne jako shellový literál). Po odpovědi `choose`:
   `aid-ui-state.sh set <project> variant "$(cat <project>/.aid-ui/variant.json)" --answer <id>`
   (soubor = `value` karty, kterou PM vybral; cíl odpovědi zůstává otisk mapy karet) a
   `aid-ui-state.sh set <project> options "$(cat <project>/.aid-ui/options.json)" --answer <id>`
   (odpověď na otázku voleb; jen v kroku 0).
9. `aid-ui-serve.sh brand docs/brand` → odkaz na brand stránku pro PM.

## Co PM rozhoduje

Variantu, značku, místní firmu a volitelné části kroku 1 - ve studiu.

## Zápis

`docs/design/brand-state.json` (init, `variant`, `options`), `docs/brand/*`,
`.gitignore`, kapitola `logo`.

## Když krok selže

Ukaž PM řádek `ERROR:` skriptu; krok se neposouvá. Odpověď chybí → odkaz na
studio a čekání podle `SKILL.md` „Jak se ptá PM", bod 4.

**Last Updated:** 2026-09-28
