# Zadání: Logo + favicon pro AID Orchestrator

> Volný brief pro grafika. Cílem není svázat ruce, ale dát dost kontextu, aby
> bylo od čeho se odpíchnout. Vizuální styl je otevřený - níže je jen směr,
> ne mantinely.

## Co je AID (kontext pro inspiraci)

**AID (AI Development Orchestrator)** je plugin do **Claude Code** (AI nástroj pro
vývojáře běžící v příkazové řádce). AID z volného "promptování AI" dělá
**disciplinovanou inženýrskou pipeline**: vede vývoj od plánování přes implementaci
až po dodávku jištěnou kvalitativními bránami (quality gates).

Jak to funguje zkráceně:
- **Deterministické operace** (stavový automat, gates, kontrola rozsahu, počítání
  tokenů) běží ve **strojově přesných bash skriptech**.
- **Kreativní práci** (psaní kódu, review, plánování) dělá **AI model**.
- Řídí přitom **víc specializovaných agentů** (implementer, verifier, auditor…) -
  je to tedy **orchestrátor**, dirigent nad více "hráči".

Není to náhrada AI - je to **řád a struktura nad ní**. Z chaotického, ad-hoc
vývoje s AI dělá opakovatelný, kontrolovatelný, kvalitou jištěný proces.

V číslech: 8 příkazů, 7 agentů, 8 skillů, 6stavový FSM. Dva režimy - **Fast**
(`/aid-do` na malé úkoly) a **Epic** (`/aid-plan` + `/aid-run` na velké featury).

## Pro koho

- **Vývojáři používající Claude Code**, kteří chtějí místo nahodilého promptování
  strukturovaný, opakovatelný a kvalitou jištěný AI vývoj.
- **Open-source komunita** - AID je veřejný plugin (GitHub), takže logo poletí
  i na marketplace, README a sociální karty repa.

## Charakter a tón značky (důležité pro pocit loga)

AID je **developer tool**, ne business aplikace. Tomu má odpovídat i vizuál -
technický, čistý, sebevědomý, ne hravý ani korporátní.

- **Orchestrace / dirigování** - hlavní metafora. Jeden řídí mnoho (agentů).
  Koordinace, takt, struktura.
- **Disciplína a řád** - quality gates, stavový automat, opakovatelnost.
  Přesnost, spolehlivost, "věci na svém místě".
- **Pipeline / tok / postup** - plán → kód → brány → dodávka. Posloupnost,
  směr vpřed, etapy.
- **Stroj + kreativita** - deterministická přesnost (FSM/bash) snoubená
  s tvůrčí AI. Řád, který nedusí.

Estetika ze světa vývojářských nástrojů (à la Linear, Vercel, GitHub CLI,
terminál) - **musí výborně fungovat v dark mode**, vývojáři v něm žijí.

## Pocit, který má značka vyvolávat

- **Technicky důvěryhodný a precizní** - "tohle drží pohromadě, tomuhle se dá věřit".
- **Chytrý / AI-driven**, ale bez klišé robota/mozku/neuronky.
- **Strukturovaný a klidný** - řád z paralelismu, ne chaos.
- **Minimalistický** - jednoduchý geometrický mark, který funguje i jako tiny
  ikona v liště / na CLI marketplace.

## Možné vizuální motivy (jen nápady, klidně zahoď)

- Orchestrace: dirigentská taktovka, uzel rozvětvující se k více bodům (1→N agentů)
- Stavový automat / pipeline: navazující uzly a hrany, etapy, brány (gates)
- Písmeno "A" poskládané z pipeline segmentů / uzlů / cesty
- Souhvězdí koordinovaných bodů (víc agentů řízených z jednoho centra)
- Kontrolní brána / checkpoint (motiv quality gates)
- Mřížka / řád vznikající z paralelních toků

> Vyhnout se prosím generickým klišé: ozubené kolo, žárovka, mozek, robot,
> stock "AI" vizuál, dále omšelé dev klišé typu složené závorky `{ }` nebo
> terminálový kurzor (pokud to nebude opravdu svěží).

## Co potřebuju dodat (deliverables)

> **Důležité:** výstupem musí být **kompletní balíček = vektory (SVG) ZÁROVEŇ
> s vyrenderovanými rastry (PNG/ICO)**. Nestačí dodat jen SVG - bez rastrů
> favicon a ikony reálně nefungují (viz důvody níže).

### Logo (vektor)
- **Hlavní varianta** (symbol + slovo "AID") - barevná
- **Samotný symbol / značka** (bez textu) - základ pro favicon a ikony
- **Varianty:** color / black (monochrom) / color-on-dark / white - každá zvlášť,
  pro logo i pro symbol. **Dark mode je u dev tool prioritní**, ne dodatek.
- **Wordmark vždy vyoutlinovaný do path** (žádný `<text>` / živý font) - aby se
  vykreslil identicky bez instalovaného fontu
- Formát: **SVG** + jeden **editovatelný master SVG** ve `source/`

### Favicon a ikony (vektor + RASTRY)
- Odvozené ze symbolu. Dvě sady: **transparent** (průhledné pozadí) a
  **dark-background** (plný tmavý zaoblený čtverec + světlý symbol).
- **SVG** v obou sadách ve velikostech 16 / 32 / 48 / 180 / 192 / 512.
- **Rastry (POVINNÉ):**
  - `favicon.ico` (multi-size 16 + 32 + 48) - fallback pro starší prohlížeče
  - `favicon.svg` - moderní prohlížeče
  - PNG faviconů `16×16`, `32×32`, `48×48`
  - **`apple-touch-icon.png` 180×180 - musí být PNG** (iOS Safari SVG apple-touch
    ikonu ignoruje)
  - PWA: **`pwa-192.png` a `pwa-512.png`** (PNG, ne SVG)
- **Primární favicon = dark-background varianta** - drží se viditelná na světlé
  i tmavé liště prohlížeče; transparent dodat taky jako doplněk.
- **16px legibilita:** symbol v 16px musí zůstat čitelný - pokud detail v malém
  zaniká, dodat zjednodušený glyph pro nejmenší velikosti.

### Struktura balíčku (doporučená)

```
logo/        aid-logo-{color,black,white,color-on-dark}.svg
symbol/      aid-symbol-{color,black,white,color-on-dark}.svg
icons/
  favicon.svg, favicon.ico, apple-touch-icon.png
  pwa-192.png, pwa-512.png
  transparent/      aid-icon-{16,32,48,180,192,512}-transparent.svg (+ PNG)
  dark-background/  aid-icon-{16,32,48,180,192,512}-dark.svg (+ PNG)
source/      aid-logo-master-outlined.svg  (editovatelný master)
README.md, brand-brief.md
```

> Bez balastu - žádné `.DS_Store` ani jiné systémové smetí v balíčku.

## Kde se logo použije (kontext nasazení)

- **Claude Code plugin marketplace** - listing pluginu (malá ikona + název)
- **GitHub repo** - README hlavička, sociální náhledová karta
- **Docusaurus dokumentace** (`aid` namespace) - navbar + favicon docs webu
- **AID GUI / Cockpit** - webové rozhraní má placeholder favicon
  (`packages/aid-gui/public/favicon.svg`), ten se nahradí finální ikonou
- **CLI kontext** - mark musí fungovat i monochromaticky / v malém

## Technické / praktické poznámky

- Primárně **digitální použití** (web, CLI, marketplace) - optimalizovat pro
  obrazovku, ne pro tisk.
- Dodat i **definici barev** (HEX) a **font(y)** použité ve wordmarku.
- Ideálně krátký **mini-manuál** (1 strana): ochranná zóna, minimální velikost,
  co se s logem nesmí dělat, light/dark varianty.

## Otevřené body (rozhodne zadavatel)

- **Název v logu:** zatím počítáno s wordmarkem **"AID"** (zkratka = produkt).
  Varianty k rozmyšlení: samotné "AID" / "AID Orchestrator" / "AID" + podtitul
  "Orchestrator".
- **Barevnost** - zatím nestanovena, necháváme na návrhu (klidně 2-3 varianty).
  Pozn.: AID je součást ekosystému (Vulcan, Cicero, Krok…) - zvážit, jestli se
  má vizuálně mírně rodinně držet, nebo stát samostatně jako dev tool.
- Případný **claim / podtitul** - např. "Structured multi-agent development" -
  zatím neřešíme, jen značka a název.
