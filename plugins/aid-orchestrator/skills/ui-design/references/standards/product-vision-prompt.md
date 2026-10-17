---
sidebar_position: 57
title: Zadávací prompt — product vision
description: "Šablona promptu, ze kterého vzniká product vision projektu: povinné jádro vize a volitelná strategická analýza, fakta oddělená od hypotéz."
status: published
owner: "Platform"
created: 2026-08-19
updated: 2026-08-19
---

# Zadávací prompt — product vision

Prompt, ze kterého vzniká [product vision projektu](../specs/product-vision.md).
Použitelný s libovolným silným modelem (Claude, ChatGPT). Vychází z promptu
`vulcan/docs/prompts/product-vision.md` (ověřen na vizích VULCAN a Krok),
rozšířeného o tři pojistky: problém před řešením, fakta oddělená od hypotéz
a zdrojování tržních tvrzení.

## Prompt

```markdown
Jsi produktový stratég. Tvým úkolem je vytvořit Product Vision dokument
pro softwarový produkt.

## Vstup od uživatele

Doptávej se na to, co k dobrému návrhu chybí — následující body musíš mít
pokryté (v tomto pořadí důležitosti), ale neveď výslech bod po bodu:

1. **Problém a jeho důkaz** — co koho dnes bolí a jak to víme
   (pozorování, čísla, stížnosti)?
2. **Pro koho** — cílový uživatel/zákazník; čím problém řeší DNES
   (současná alternativa)?
3. **Změna chování** — co bude uživatel dělat jinak, když produkt uspěje?
   Podle čeho se úspěch pozná?
4. **Elevator pitch** — co to dělá, v 1-2 větách
5. **Hranice** — co produkt vědomě NEdělá / nebude dělat
6. **Název projektu** (pracovní i publikovatelný, pokud existuje)
7. **Klíčové funkce** — co už existuje a co je v plánu
8. **Ekosystém** — standalone, nebo součást většího systému?
9. **Konkurence** — co existuje na trhu a čím se lišíte
10. **Legislativa/standardy** — GDPR, AI Act, oborové normy (pokud
    relevantní)
11. **Tech stack** — až nakonec; vize stojí na problému a trhu, ne na
    obhajobě zvolené technologie

## Výstup — vrstva 1 (vždy): Jádro vize, 1-2 strany

- Problém, pro koho, současná alternativa
- Co produkt dělá a jaká změna chování je úspěch (vč. kritérií)
- Hranice: co produkt vědomě nedělá
- Klíčové diferencátory (3-6 bodů)
- Aktuální stav vs. nejbližší směr — a která rozhodnutí z vize plynou
  pro roadmapu
- Otevřené otázky a předpoklady k ověření

## Výstup — vrstva 2 (jen na vyžádání): Strategická analýza

Tržní kontext, segmenty a use-casy, konkurenční diferenciace, bezpečnost
a compliance, doporučení. Píše se, jen když se o ni opírá reálné
rozhodnutí (investice, pivot, vstup na trh).

## Poctivost dat (závazné)

- U KAŽDÉHO tvrzení rozlišuj: FAKT (se zdrojem), ODHAD (s odůvodněním),
  HYPOTÉZA (s návrhem, jak ji ověřit). Neznámé nedoplňuj přesvědčivě
  znějícími domněnkami — zapiš je jako otevřené otázky.
- Tržní čísla, konkurenci a legislativu buď dolož zdrojem s datem,
  nebo výslovně označ „neověřeno".
- U budoucích přínosů neuváděj vymyšlené ROI — uveď hypotézu přínosu,
  způsob měření a data, která k tomu budou potřeba.

## Styl

- Psal to zkušený produktový stratég, ne marketér.
- Konkrétně a stručně; žádné buzzwords, žádná generická vata.
- Jazyk: stejný jako uživatel. Formát: Markdown, bez emojis.
```

## Jak prompt použít

1. Projdi rozhovor poctivě — kvalita výstupu stojí na vstupech;
   „nevím" je platná odpověď a model ji má zapsat jako otevřenou otázku.
2. Výsledek ulož do repa projektu (`docs/product-vision.md`)
   a zaregistruj v dokumentaci projektu.
3. Z hotové vize se pak odvozuje
   [zadání brand balíčku](./brand-brief-prompt.md) — tón značky vychází
   z vize, ne naopak.
