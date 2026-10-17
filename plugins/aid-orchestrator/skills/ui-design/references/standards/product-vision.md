---
sidebar_position: 3
title: Product vision projektu
description: "Každý ECO produkt má product vision: co obsahuje, jak vzniká ze šablonového promptu a kde žije. Vize je základ pro značku i priority."
status: published
owner: "Platform"
created: 2026-03-27
updated: 2026-08-19
---

# Product vision projektu

Jednou větou: **každý ECO produkt má zapsanou product vision dřív, než se
rozhoduje o značce, prioritách nebo veřejné prezentaci — vize je dokument,
ze kterého se tyhle věci odvozují, ne obráceně.**

:::note
Do 19. 8. 2026 na této adrese žila product vision VULCANU. Přestěhovala se
tam, kam patří: [Product Vision — VULCAN](../../vulcan/product-vision.md).
Tato stránka je ekosystémový standard — pravidlo pro všechny projekty.
:::

## What — co je pravidlo

1. Každý produkt (aplikace s uživateli nebo zákazníkem) MUSÍ mít product
   vision dokument v repu projektu — kanonicky `docs/product-vision.md`
   (samostatný, dohledatelný dokument; brand balíček z něj čerpá, ale
   není jeho domov).
2. **Jádro vize** (povinné, 1–2 strany): jaký problém a pro koho, čím to
   dnes uživatel řeší, co se má jeho chováním změnit, dlouhodobý směr,
   hranice („co produkt vědomě nedělá") a podle čeho se pozná úspěch.
3. **Strategická analýza** (trh, segmenty, konkurence, technologie) je
   volitelná druhá vrstva — vzniká, když se na ní opírá reálné rozhodnutí
   (investice, pivot, vstup na trh), ne automaticky.
4. Vize **rozlišuje fakta, předpoklady a otevřené otázky** — u malého
   produktu je většina tvrzení hypotéza a musí to být poznat.
5. Vize má **vlastníka a datum**; reviduje se při změně směru (jiný
   segment, jiný ceník, jiný klíčový problém). Starší vize zůstává platná,
   dokud nese datum a je z ní poznat, co je dnes jinak.
6. Vize je **vstup pro navazující artefakty** — v tomto pořadí:
   product vision → [brand balíček](./design-system-standard.md#brand-balíček-projektu)
   → [design standard projektu](./design-system-standard.md). Tón značky
   a vizuál se odvozují z vize; vize se nikdy nedopisuje zpětně podle loga.

## Why — proč to platí

Bez zapsané vize se „co vlastně stavíme a pro koho" nese ústně a každý
navazující artefakt (logo, marketing, priority backlogu) si odpověď domyslí
jinak. Přesně tak na této adrese skončila vize jednoho projektu (VULCAN)
vydávaná za směr celého ekosystému.

## How — jak vize vzniká

Šablonovým promptem
[Zadávací prompt — product vision](../templates/product-vision-prompt.md):
řízený rozhovor → jádro vize (a volitelně analýza). Prompt vede k rozlišení
faktů od hypotéz a ke zdrojování tržních tvrzení.

Kde jsou existující vize:

| Projekt | Vize | Poznámka |
|---|---|---|
| VULCAN | [Product Vision — VULCAN](../../vulcan/product-vision.md) | přestěhována z této adresy |
| Krok | `krok/docs/krok-brand-package/product-vision.md` | historicky v brand balíčku; při revizi přesunout do `docs/` |
| WAN / LISA | — | **dluh** — brand balíček existuje, vize ne |
| Sousto | — | dluh |
| ACTA | — | dluh |

## Exceptions — výjimky

- Interní nástroje bez koncového zákazníka (deployment skripty, ops MCP)
  vizi mít nemusí.
- Projekty ve fázi experimentu (spike, prototyp) vizi odkládají do
  rozhodnutí „stavíme to" — pak je první krok.
- Tvorbu značky bez hotové plné vize lze pustit s minimálním prahem:
  zapsané publikum, problém, pozicování a tón (tj. jádro vize v bodech).
  Bez toho ne — brief by vznikl z dojmů.

## Enforcement — jak se vynucuje

- Zadání brand balíčku ([šablona](../templates/brand-brief-prompt.md))
  vyžaduje vstupy z vize — projekt bez aspoň minimálního jádra je při
  tvorbě značky zastaven u prvního kroku.
- Tabulka výš je zdroj pravdy o stavu; nový produkt se do ní přidává
  s odkazem, dluh se vede jmenovitě.
