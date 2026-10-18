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
6a. **Webová aplikace (P116):** u `type: webapp` platí `references/local/aplikace-postup.md` (oddíly 0 a 1): `existing: true`
   u aplikace, která už běží; volby `vision: false`, `seo: false`, `identity: false` u `brand: existing|none`;
   každá vynechaná část dostane záznam `decide --title přeskočeno` s důvodem.
7. Otázka `variant` ve studiu (`SKILL.md` „Jak se ptá PM"), s doporučením
   z inventury u každé volby:
   - `type`: `web` (prezentační web), `webapp` (aplikace s přihlášením),
     `pwa` (instalovatelná aplikace - manifest a ikony pro instalaci jsou
     povinné položky mapy pokrytí);
   - `existing` (jen `webapp`): `true`, když aplikace už běží (část Výchozí stav aplikace);
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
10. **Podklady ke spuštění (P113a), hned po volbě druhu webu:**
    - `aid-ui-launch.py card <project> --type web-local` vytvoří seznam podle typu: IČO a údaje firmy,
      hodiny, ceník, fotky, právní texty, příjem formuláře a doména.
    - Veřejné údaje dohledej sám a zapiš se zdrojem a dnem čtení:
      `aid-ui-launch.py record <project> <id> --value … --source <adresa> --date RRRR-MM-DD`.
      Zdroje jsou rejstřík, starý web, profil a katalog. Odhad se nezapisuje.
    - `aid-ui-launch.py question <project>` vypíše otázku `launch_inputs` (část Podklady) do `payload.json`.
      Klient ji potvrdí jednou odpovědí, v pilotu za něj odpovídá klient-agent.
    - Po odpovědi `aid-ui-launch.py confirm <project> --answer <id>`. Potvrzené údaje zapíše sám do
      `docs/content/facts.yaml` jako `launch_<id>` (zdroj, den čtení, potvrzení klientem). Z chybějících vzniknou otevřené body
      s vlastníkem a termínem. Kritické blokují zveřejnění, ne stavbu ani smyčku kvality.
    - Nepotvrzený údaj se na web nedostane.

## Co PM rozhoduje

Variantu, značku, místní firmu a volitelné části kroku 1 - ve studiu.

## Zápis

`docs/design/brand-state.json` (init, `variant`, `options`), `docs/brand/*`,
`.gitignore`, kapitola `logo`.

## Když krok selže

Ukaž PM řádek `ERROR:` skriptu; krok se neposouvá. Odpověď chybí → odkaz na
studio a čekání podle `SKILL.md` „Jak se ptá PM", bod 4.

**Last Updated:** 2026-09-28
