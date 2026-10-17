---
sidebar_position: 56
title: Zadávací prompt — brand balíček
description: "Šablona zadání pro grafika nebo generativní nástroj: z čeho vznikne logo, favicon a brand balíček projektu — a jak se výstup kontroluje."
status: published
owner: "Platform"
created: 2026-08-19
updated: 2026-08-19
---

# Zadávací prompt — brand balíček

Šablona zadání, ze kterého vzniká logo a brand balíček projektu
(viz [Design systém aplikací → Brand balíček](../specs/design-system-standard.md#brand-balíček-projektu)).
Funguje jako volný brief pro grafika i jako prompt pro generativní nástroj
(ChatGPT, Claude). Má dvě části: **kreativní brief** (strategie a pocit —
tady je volnost) a **technický checklist předání** (tady volnost není).

Reálná zadání, která z této kostry vznikla:

- WAN / LISA — `wan/docs/design/brief-logo-favicon.md` (speciální případ:
  symbol už existoval a byl zamčený)
- Krok — `krok/docs/krok-brand-package/brief-logo-favicon.md`
- AID Orchestrator — `aid-orchestrator/docs/design/brief-logo-favicon.md`

## Část 1 — kreativní brief (šablona)

```markdown
# Zadání: Logo + favicon pro {NÁZEV PROJEKTU}

> Volný brief. Cílem není svázat ruce, ale dát dost kontextu, aby bylo
> od čeho se odpíchnout. Vizuální styl je otevřený — níže je směr,
> ne mantinely.

## Co je {NÁZEV} (kontext pro inspiraci)

{2–4 odstavce: co produkt dělá, pro jaký problém, jak funguje ve zkratce.
Zakonči jednou větou tučně — „elevator pitch" produktu.}

## Pro koho

{Cílové skupiny s krátkým popisem, co od produktu chtějí.
Z product vision projektu.}

## Pozicování — kde značka stojí

{Kategorie produktu a hlavní alternativy, vůči kterým se vymezuje.
Proč mu má člověk věřit (důvod důvěry). A výslovně: čím značka NENÍ
(např. „ne korporát, ne hravý startup") — bez hranic vzniknou generické
motivy.}

## Vize a tón značky

{Vize a mise jednou větou. 3–5 odrážek tónu — klíčové metafory a slogany,
které se táhnou komunikací. Z product vision projektu.}

## Pocit, který má značka vyvolávat

{3–5 odrážek protikladů: „důvěryhodný, ale ne korporátně nudný",
„chytrý/AI, ale bez klišé robotů"…}

## Kde bude značka žít (kontexty použití, seřazené podle důležitosti)

{Např.: 1. aplikace (horní lišta, přihlášení), 2. ikona na ploše telefonu,
3. favicon, 4. e-mailový podpis, 5. tištěné materiály. Výstupy se řídí
tímhle seznamem — co tu není, nevzniká.}

## Možné vizuální motivy (druhotné — strategie výš má přednost)

{3–6 odrážek konkrétních motivů z domény produktu. U generativního
nástroje pozor: motivy snadno převáží a vyrobí doslovný, zaměnitelný
symbol — proto až za pozicováním.}

## Zamčené vstupy (pokud jsou)

{Existující symbol/barvy/typografie, které MUSÍ zůstat zachované 1:1.
Pokud nic: sekci vynech.}
```

## Část 2 — technický checklist předání

Vyrábí se jen to, co plyne ze seznamu kontextů použití; nepoužívané
varianty jsou zátěž, ne úplnost.

```markdown
## Požadované výstupy

- `symbol/` — samostatný symbol: color, black, white, color-on-dark (SVG)
- `icons/` — `favicon.svg` + `favicon.ico` (16/32/48 px),
  `apple-touch-icon.png` 180×180; při PWA ambici 192/512 px vč. maskable
  varianty (definovaná plocha + safe zone — transparentní ikona na
  některých launcherech selže); vše ve skutečném poměru 1:1
- `logo/` + `lockup/` — jen kompozice a varianty odpovídající kontextům
  použití (horizontální/vertikální, světlá/tmavá, PWA lockup s názvem)
- `source/` — editovatelný master s ŽIVÝM textem + název a licence
  použitého fontu, A VEDLE něj distribuční verze s textem převedeným
  na křivky
- `brand-brief.md` — zásady použití: ochranná zóna, minimální velikosti,
  kdy symbol-only, chování na tmavém podkladu
- `README.md` — obsah balíčku a primární použití (které soubory kam)

## Technické požadavky

- Favicon čitelný na světlém i tmavém rozhraní prohlížeče (osvědčený
  vzor: plný tmavý zaoblený čtverec se světlým symbolem).
- Pro 16/32 px smí vzniknout opticky zesílená mikrovarianta symbolu;
  master zůstává beze změny.
- Definuj zlomové velikosti, pod kterými se přepíná na jednodušší
  variantu loga.
- Práva: u fontů a převzatých assetů uveď licenci; výstup musí být
  volně použitelný pro komerční užití projektu.
```

## Kontrola výstupu (povinná — hlavně u generativních nástrojů)

Generativní nástroj není výrobce produkčního balíčku — jeho výstup se
před nasazením zkontroluje:

1. **Čitelnost v reálných velikostech**: favicon 16 px v záložce, ikona
   na ploše telefonu, logo v hlavičce aplikace — na světlém i tmavém.
2. **Technická kvalita SVG**: validní soubory, rozumný počet bodů,
   skutečný poměr 1:1 u ikon, žádé rastrové vložky kde má být vektor.
3. **Práva a odlišnost**: font s licencí, symbol bez nápadné podobnosti
   s existující značkou v oboru (stačí obrazové vyhledání).
4. **Úplnost vůči kontextům použití** z části 1 — nic víc, nic míň.

## Jak šablonu použít

1. Vyplň kontext z [product vision projektu](../specs/product-vision.md) —
   tón značky se odvozuje z vize, ne naopak. Stačí i minimální jádro vize
   (publikum, problém, pozicování, tón).
2. Ulož vyplněné zadání do repa projektu
   (`docs/design/brief-logo-favicon.md`) — zadání je součást historie
   značky, ne jednorázová zpráva.
3. Výsledný balíček ulož vedle něj, projdi kontrolou výš a teprve pak
   nasazuj.
