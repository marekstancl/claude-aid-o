---
name: ui-design-step-1v
description: /aid-ui sub-step 1v - product vision, brand tone and a slogan the PM confirms on the studio page
user_invocable: false
---

# Krok 1v - Vize, tón a slogan

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

1. Vize existuje → shrň ji jako otázku `vision` ve studiu, nepřepisuj ji.
2. Jinak si povinné body šablony **odpověz sám** ze všeho, co projekt má:
   `PRODUCT.md`, dosavadní web a jeho texty, dřívější slogany a motta, zadání,
   dokumentace, repozitář. PM se ptáš jen na fakt, který nikde není a nedá se
   odvodit (cena, kontakt, jméno klienta, číslo) - jednou otázkou `facts`,
   nejvýš osm bodů, u každého tvůj návrh. Domněnku nikdy nevydávej za fakt:
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

Platí pro vizi, slogany a všechny texty webu, které skill navrhuje (kroky 1v, 3, 6).

- **Začni problémem zákazníka jeho slovy**, ne firmou: co ho dnes stojí čas
  nebo peníze („účetní přepisuje faktury ručně"), ne „nabízíme řešení".
- **Proč teď:** co se změnilo, že to jde jinak (nová technologie, nižší cena,
  kratší doba), a proč je to pro zákazníka dostupné.
- **Konkrétní místo obecného:** podstatná jména a slovesa z provozu zákazníka,
  čísla jen se zdrojem v `facts.yaml`. Zakázaná prázdná slova: řešení,
  inovativní, revoluční, transformovat, komplexní, na míru bez vysvětlení čeho,
  „posuneme vás dál".
- **Krátce:** věta do ~15 slov, odstavec do tří vět; nadpis říká výsledek,
  ne kategorii („Faktury se zapíšou samy", ne „Automatizace").
- **Slogan:** 2–7 slov, dá se říct nahlas, nese jeden rozdíl oproti oboru;
  žádná slovní hříčka, kterou je třeba vysvětlovat; nesmí sedět na libovolnou
  jinou firmu (test: dosaď konkurenta - když sedí, přepiš).
- **Navazuj na to, co projekt už říká:** dřívější motto, slogany a oblíbená
  slova PM zachovej nebo rozviň, neodhazuj je bez důvodu.
- **Tón podle vize**, vykání, jazyk projektu; žádná angličtina v českém textu.
- **Kontrola před ukázáním PM:** přečti text nahlas očima zákazníka - pozná
  do pěti vteřin, co firma dělá, pro koho a proč právě ona? Když ne, přepiš.

## Co PM rozhoduje

Odpovědi na otázky vize a slogan - ve studiu. Re-roll nejvýš dvakrát, pak
PM napíše vlastní do komentáře.

## Zápis

`docs/product-vision.md`, kapitola `vize`. Projekt v angličtině: slogany
a kapitola anglicky, zprávy PM česky.

## Když krok selže

Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4.

**Last Updated:** 2026-09-28
