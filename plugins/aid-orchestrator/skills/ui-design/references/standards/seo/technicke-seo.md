---
title: Technické SEO
description: Sdílené best practices pro titulky, schema, indexaci, výkon a základní AI-search připravenost.
status: published
owner: Master
created: 2026-07-28
updated: 2026-07-28
---

# Technické SEO

Praktická reference pro audit i implementaci. Při Google-specifickém tvrzení má přednost aktuální Google Search Central před marketingovými články.

## Titulek stránky

- Titulek má být unikátní a odpovídat obsahu i hledanému dotazu.
- Klíčové téma a případná lokalita patří dopředu, značka obvykle až za ně.
- Orientační délka je 50-60 znaků; důležitější než přesný limit je srozumitelný a nezkreslující význam.
- U šablonových CMS ověř skutečné HTML živé stránky, ne jen název pole v administraci.

## Meta description

- Meta description přímo neurčuje pozici, ale ovlivňuje důvod ke kliknutí a CTR.
- Má vystihnout konkrétní přínos stránky; orientačně 150-160 znaků.
- Vyhledávač může použít vlastní úryvek - kvalitní popis se přesto vyplatí.

## Structured data

- Používej JSON-LD a nejkonkrétnější pravdivý typ, který odpovídá obsahu.
- Data musí souhlasit s viditelným obsahem a s údaji o firmě napříč webem.
- Validuj přes Schema.org Validator a Google Rich Results Test.
- Structured data zlepšují strojové porozumění a způsobilost pro rich result, negarantují zobrazení ani pozici.
- Nevkládej self-serving `aggregateRating` z externího profilu jen proto, aby stránka zobrazila hvězdičky.

## Indexace a měření

- Google Search Console je základ pro ověření indexace, dotazů, impresí, kliknutí a CTR.
- Ověření vlastnictví přes DNS TXT bývá odolnější vůči redesignu než vložení kódu do šablony.
- Zkontroluj robots, `noindex`, canonical a sitemap na živém webu.
- `robots.txt` řídí hlavně crawl, není sám o sobě jistým prostředkem pro vyřazení URL z indexu.

## Výkon a Core Web Vitals

- Posuzuj přednostně polní data z PageSpeed Insights/CrUX, pokud jsou dostupná, a odděluj je od laboratorního měření.
- Největší páky bývají správná velikost a formát obrázků, omezení třetích stran a objemu JavaScriptu, plus rychlá odezva serveru.
- Cookie lišty, overlaye a pozdně načítané prvky mohou zhoršit LCP, INP a CLS - posuzuj je i jako UX problém.

## AI-search připravenost

- Základem zůstává indexovatelný, veřejně dostupný, užitečný a originální obsah. Pro Google AI funkce musí být stránka způsobilá pro Google Search a snippet; podrobnosti jsou v [oficiálním průvodci Google](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide).
- Jasně definuj hlavní entitu a účel stránky; používej srozumitelné nadpisy, přímé odpovědi a doložená fakta.
- Udržuj konzistentní údaje o firmě, autorovi, datu a zdrojích.
- FAQ a schema přidávej jen tam, kde přirozeně pomáhají návštěvníkovi; nejsou samostatnou ranking taktikou.
- Ověř `robots.txt`, robots hlavičky, anonymní dostupnost, WAF/CDN ochranu a render hlavního obsahu. Stránka za loginem, CAPTCHA, JS challenge nebo s blokovaným crawlerem nemůže být spolehlivě použita jako veřejný zdroj.
- Rozlišuj povolení pro vyhledávací crawler od souhlasu s jiným účelem crawleru, například trénováním. Před změnou robots nebo WAF nejprve stanov business politiku.
- `llms.txt` nepřidávej automaticky - není to podmínka pro AI viditelnost.

## Anti-patterns

- Keyword stuffing, meta keywords, skrytý text, doorway pages a kupované odkazy/PBN.
- Schema, které neodpovídá viditelnému obsahu.
- Hodnocení technického stavu jen podle nastavení CMS bez kontroly skutečné URL.
