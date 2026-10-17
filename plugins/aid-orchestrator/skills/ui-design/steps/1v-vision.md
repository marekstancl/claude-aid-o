---
name: ui-design-step-1v
description: /aid-ui sub-step 1v - product vision, brand tone and a slogan the PM confirms on the studio page
user_invocable: false
---

# Krok 1v - Vize, tón a slogan

**Vrstva dílny (P113):** `references/local/sdeleni-postup.md` má přednost před generováním sloganů (pět směrů, test dosazení); ostatní platí. Otázku `vision` v autonomním běhu rozhoduje klient-role výběrem (`choose`) z karet, ne holým schválením (oprava 29). Místo: `sdeleni`; schválit vizi jde jen s verdiktem místa (`aid-ui-state.sh place-record --place sdeleni`).

**Last Updated:** 2026-09-28

## Cíl

Běží jen při `options.vision`. Projekt má vizi (`docs/product-vision.md`),
odstavec o tónu a slogan potvrzený PM ve studiu; kapitola `vize` to nese.
Interní nástroj (`variant.brand` = `none`) může vizi vynechat - důvod do
kapitoly `vize`.

## Vstupy

`PRODUCT.md`, existující vize (`docs/product-vision.md` nebo stránka
v Docusauru), šablona `/opt/eco/docs/docs/ecosystem/templates/product-vision-prompt.md`
(čti živě), brand brief `docs/design/brand-package/brand-brief.md`, je-li.

## Postup

Nejdřív `aid-ui-state.sh context-check <project>`; neprojde → zpět na krok 1p (`steps/1p-sources.md`).

1. Vize existuje → shrň ji jako otázku `vision` ve studiu, nepřepisuj ji.
2. Jinak si povinné body šablony **odpověz sám** ze schváleného
   `docs/content/product-context.md` (krok 1p; ten už přečetl `PRODUCT.md`, starý web, zadání
   a rozhovory) a z manifestu podkladů `.aid-ui/sources/manifest.json`. PM se ptáš jen na bod
   šablony vize, který dokument o produktu nemá a nedá se odvodit (cena, kontakt, jméno klienta,
   číslo) - jednou otázkou `facts`, nejvýš osm bodů, u každého tvůj návrh; na nic, co dokument
   o produktu už obsahuje, se znovu neptej. Domněnku nikdy nevydávej za fakt:
   co jsi odvodil, označ jako HYPOTÉZU i s tím, odkud plyne.
   Každý fakt, který jsi takto určil sám, zapiš ještě před otázkou `facts` jedním
   voláním na fakt: `aid-ui-state.sh decide <project> --step "Zadání a obsah"
   --title "<fakt, např. Doba odpovědi>" --outcome "<hodnota jednou větou>" --why
   "<odkud plyne>" --source PRODUCT.md` (nebo soubor, ze kterého fakt pochází).
3. Zapiš `docs/product-vision.md` (vrstva 1, fakta oddělená od hypotéz podle
   šablony) podle oddílu „Jak psát" níže. Tón odvoď z vize a z brand briefu
   (existuje-li); jeden odstavec. Brána (řádek `vision_doc`, `aid-ui-vision-check.py`)
   chce: řádek `Vlastník: …` a `Datum: d. m. rrrr`, **Elevator pitch**, oddíly nebo tučné
   štítky Problém, Pro koho, Úspěch (změna chování), Hranice, Klíčové funkce, Ekosystém,
   Konkurence (nebo Diferencátory), Legislativa, a tvrzení označená FAKT/ODHAD/HYPOTÉZA.
   Vize už existuje (i v Docusauru) → do `docs/product-vision.md` ji převezmi beze změny
   obsahu, jen doplň chybějící štítky; nepřepisuj ji.
4. Pět sloganů v jazyce projektu jako karty otázky `vision` (`thesis` =
   slogan, `uniqueness` = čím se liší od běžných v oboru, `risk` = kde může
   narazit); aspoň jeden vychází z dřívějšího sloganu nebo motta projektu
   (je-li), aspoň jeden je nový. PM vybere kartu, vrátí s vlastním sloganem
   v komentáři, nebo požádá o nové (re-roll).
5. Po `choose`/`approve` tělo kapitoly (jádro vize, tón, zvolený slogan =
   `thesis` karty `choice` ze snímku `cards` odpovědi, ne z payloadu -
   `SKILL.md` „Jak se ptá PM", bod 5; zamítnuté) do souboru v `.aid-ui/`,
   `aid-ui-state.sh body <project> vize --file <soubor>`, pak
   `aid-ui-state.sh chapter <project> vize navrh`.

## Jak psát vizi, slogany a texty

Platí pro vizi, slogany a všechny texty webu (kroky 1v, 3, 6). Metoda je převzatá, nepiš
podle vlastního citu:

- **Postup psaní:** `references/adopted/marketingskills/copywriting/SKILL.md` (před psaním
  účel stránky, publikum, nabídka; přínos místo funkce, konkrétně místo obecně, slovy zákazníka,
  jedna myšlenka na sekci).
- **Pravidla AID:** `references/copy-rules.md` (fakta jen z registru, hypotéza řídí jen tón,
  pořadí při rozporu, co blokuje v kontrole).
- **Jazyk:** `references/copy-<jazyk>.md` podle `lang` webu (`copy-cs.md`, `copy-sk.md`,
  `copy-en.md`). Pro jazyk bez příručky řekni PM ve studiu jednou, že kontrola textů takovou
  stránku neprojde bez jeho výjimky, a piš podle `copy-rules.md` a převzatých anglických pravidel.
- **Slogan:** 2–7 slov, dá se říct nahlas, nese jeden rozdíl oproti oboru; test dosazení
  konkurenta (když sedí na jinou firmu, přepiš). Když manifest podkladů (krok 1p) obsahuje
  dřívější motto nebo slogan, aspoň jeden návrh na něj navazuje a karta uvede zdroj.
- **Tón** podle vize a dokumentu o produktu (oddíl Hlas značky); slova zákazníků z oddílu
  Jazyk zákazníků mají přednost před vlastními.

## Co PM rozhoduje

Odpovědi na otázky vize a slogan - ve studiu. Re-roll nejvýš dvakrát, pak
PM napíše vlastní do komentáře.

## Zápis

`docs/product-vision.md`, kapitola `vize`. Projekt v angličtině: slogany
a kapitola anglicky, zprávy PM česky.

## Když krok selže

Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4.

**Last Updated:** 2026-09-28
