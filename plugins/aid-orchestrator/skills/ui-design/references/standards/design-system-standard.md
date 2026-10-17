---
sidebar_position: 15
title: Design systém aplikací
description: "Co musí mít ECO projekt s uživatelským rozhraním: brand balíček, závaznou vizuální šablonu a definované chování na webu, mobilu a tabletu."
status: published
owner: "Platform"
created: 2026-08-18
updated: 2026-09-02
---

# Design systém aplikací

Jednou větou: **projekt s uživatelským rozhraním má závaznou vizuální šablonu
dřív, než postaví druhou obrazovku — a každá další obrazovka ji buď používá,
nebo ji vědomě mění v dokumentu, ne jen v kódu.**

## What — co musí projekt mít

Každý ECO projekt s uživatelským rozhraním MUSÍ mít:

1. **Design standard** — vlastní dokument v namespace projektu, který
   naplňuje checklist z tohoto standardu konkrétními hodnotami. Tento
   dokument říká **CO** se definuje; projektový standard říká **JAK**
   to u něj vypadá.
2. **Platformní kontrakt** — u každé komponenty a vzoru řečeno, jak se
   chová na webu, mobilu a tabletu (viz [Platformy](#platformy--web--mobil--tablet)).
   „Žádný rozdíl" je platná odpověď, ale musí být napsaná.
3. **Brand balíček** — produkty s koncovými uživateli nebo veřejnou tváří
   navíc sadu produkčních souborů značky (viz
   [Brand balíček](#brand-balíček-projektu)). Interním nástrojům stačí
   název a favicon.

## Why — proč to platí

Bez závazné šablony si každá nová obrazovka odvodí vzhled od té, kterou měl
její autor zrovna otevřenou. Při vývoji po malých krocích je rozjetý vzhled
jistota, ne riziko: měření na jednom ECO projektu (srpen 2026) našlo na jediné
uživatelské cestě čtyři vizuální jazyky oken a šest podob téhož primárního
tlačítka. Náprava po letech vývoje stojí řádově víc než šablona na začátku.

## Brand balíček projektu

Značka není jen logo v rohu — je to sada produkčních souborů, které aplikace,
PWA instalace, prohlížeč a marketing skutečně konzumují. Balíček žije v repu
projektu (`docs/design/<projekt>-brand-package/` nebo obdobně). Vyrábí se
z něj jen to, co projekt reálně používá — nepoužívané varianty jsou zátěž,
ne úplnost:

| Součást | Co v ní je | Kdy je potřeba |
|---|---|---|
| `symbol/` | Samostatný symbol značky (color / black / white / on-dark) | vždy |
| `icons/` | Favicon (`.svg` + `.ico` s 16/32/48 px), Apple Touch 180×180, PWA 192/512 px — vše v poměru 1:1 | vždy (web app) |
| `logo/` | Plná loga a lockupy (kompozice a barevné varianty podle skutečných kanálů použití) | produkt s veřejnou tváří |
| `lockup/` | Čtvercové PWA/mobilní lockupy s názvem, světlá i tmavá varianta | PWA instalace |
| `source/` | Editovatelný master (s živým textem + informací o fontu a licenci) **a** distribuční verze s textem převedeným na křivky | vždy |
| `brand-brief.md` | Zásady použití: ochranná zóna, minimální velikosti, kdy symbol-only, chování na tmavém podkladu | vždy |

**Jak balíček vzniká:** zadáním pro grafika nebo generativní nástroj podle
šablony [Zadávací prompt — brand balíček](../templates/brand-brief-prompt.md).
Výstup generativního nástroje není hotový balíček — před nasazením projde
kontrolou (čitelnost v malých velikostech, technická kvalita SVG, práva
k fontům, odlišnost od konkurence; detail v šabloně). Hotové balíčky, které
z ní vznikly a slouží jako vzor:

- WAN / LISA — `wan/docs/design/WAN-LISA-brand-package-2/`
- Krok — `krok/docs/krok-brand-package/`
- AID Orchestrator — `aid-orchestrator/docs/design/AID-Orchestrator-production/`

Značka se opírá o [product vision projektu](./product-vision.md) — tón a pocit
značky se odvozují z vize, ne naopak.

## How — tři vrstvy definice

1. **Tokeny** — pojmenované hodnoty, ze kterých se skládá všechno ostatní.
   Nikdy nepoužívat hodnotu přímo tam, kde existuje token.
2. **Komponenty** — stavební prvky složené z tokenů. Opakovaně používaná
   komponenta má jednu sdílenou implementaci; druhá kopie téže komponenty
   je chyba, ne varianta. Jednorázový prvek ve výrazně odlišném kontextu
   se násilně neabstrahuje — sdílí aspoň tokeny a čeká, až se použití
   zopakuje.
3. **Vzory** — jak se komponenty skládají na obrazovku. Vzor říká
   i CHOVÁNÍ, ne jen vzhled.

### Tokeny — co definovat

- **Barvy**: neutrály (plocha, povrch, text, tlumený text, linka), značková
  barva + tlumená verze, sémantické barvy (úspěch / varování / chyba /
  informace) ODDĚLENÉ od značkové, ztmavení pod okny. Světlý/tmavý režim —
  a pokud projekt tmavý režim nemá, výslovná věta, že nemá.
- **Typografie**: rodina písma (+ fallback), škála velikostí s pojmenovanými
  rolemi (nadpis obrazovky, nadpis sekce, tělo, popisek, číselný údaj),
  řezy a proklad. Tabulární číslice pro sloupce čísel.
- **Rozměry**: jedna mezerová škála, pojmenované poloměry zaoblení,
  stíny/elevace, šířky obsahu, breakpointy (a který je hlavní předěl
  mobil/desktop).
- **Pohyb**: délky a křivky přechodů; co se animuje a co ne. Při
  `prefers-reduced-motion` se animace omezí, ale srozumitelný stavový
  přechod zůstává.
- **Ikony**: jedna knihovna, velikosti, síla tahu; kdy ikona sama
  a kdy s popiskem.
- **Vrstvení překryvných prvků**: pojmenované pořadí (obsah / plovoucí
  prvky / navigace / okna / toast) — ad-hoc volená čísla jsou zdroj kolizí.

### Komponenty — co definovat

- **Tlačítko**: role (primární / sekundární / textové / destruktivní),
  velikosti, stavy (klid, hover, aktivní, fokus, zakázané, načítá),
  tlačítko s ikonou, samostatná ikona.
- **Vstupy formuláře**: textové pole, výběr, přepínač, zaškrtávátko,
  textarea, datum; popisek, nápověda, stavy (fokus, chyba s hláškou,
  varování, zakázané, jen pro čtení), povinnost.
- **Okno / dialog**: jeden kanonický PRIMITIV; varianty (potvrzení,
  formulář, filtr) se od něj odvozují — paralelní implementace nesmí
  vznikat. Strop výšky + vnitřní scroll, vždy dosažitelná patka s akcemi,
  ztmavení, způsoby zavření, chování s klávesnicí. Plus vyjmenované
  legitimní výjimky (fullscreen povrchy — prohlížeč obrazů, kamera)
  a jejich jednotný chrom.
- **Překryvné pomocníky**: našeptávač/combobox, popover, tooltip,
  toast/snackbar — kotvení, vrstvení, zavírání.
- **Seznamy a karty**: řádek seznamu, karta, tabulka, prázdný stav,
  načítací stav, stránkování/nekonečný scroll.
- **Navigace**: hlavička obrazovky (titulek + akce + zpět), hlavní
  navigace, taby, drobečky (pokud jsou).
- **Stavové prvky**: badge/chip/pill, odznak počtu, stavová tečka/pruh,
  progres.
- **Nahrávání souborů**: dropzone / výběr / focení, fronta souborů se
  stavy položek, limity a hlášky.
- **Datové vizualizace**: barvy z tokenů, prázdný a chybový stav.

### Vzory — co definovat

- Rozvržení formuláře (kdy 1 vs 2 sloupce, pořadí polí, kde sedí akce).
- Potvrzování destruktivních akcí (kdy dialog, kdy ne, formulace).
- Chybové a prázdné obrazovky; stavy dat (načítání, ukládání, síťová
  chyba a její opakování).
- Vícekrok (průvodce): navigace mezi kroky MUSÍ mít viditelný ovladač,
  gesto smí být navíc, nikdy jediná cesta.
- Hlášení validace (kdy u pole, kdy souhrn, kdy blokovat).

### Scroll a přilepené panely — závazný kontrakt

Obrazovka s bočním panelem (obsah nápovědy, filtry, navigace) má dvě
oblasti, které mohou přetéct. Uživatel od nich čeká jediné pravidlo:
**kolečko hýbe tím, nad čím leží kurzor.** Panel, který se nehýbe pod
kurzorem, ale rozjede se až potom, co doscrolluje hlavní obsah, působí
jako porucha, i když je to jen důsledek přilepení.

Závazně:

1. **Přilepený panel, který může přerůst obrazovku, MUSÍ být vlastní
   scrollovací oblast** se stropem výšky (výška obrazovky minus hlavička).
   Samotné přilepení nestačí — spodek delšího panelu se pak nedá zobrazit
   vůbec a poslední položky menu jsou nedosažitelné.
2. **Scroll uvnitř panelu se nesmí přelít do stránky**, když panel dojede
   na konec (`overscroll-behavior: contain`). Bez toho pokračuje setrvačnost
   v hlavním obsahu a stránka pod kurzorem „uskočí".
3. **Panel, který se na obrazovku vejde celý, scroll nepřebírá** — kolečko
   nad ním hýbe stránkou. Nezavádět prázdnou scrollovací oblast „pro jistotu".
4. **Právě jedna scrollovací oblast na tah.** Dvě oblasti se nikdy nehýbou
   současně z jednoho gesta.

Anti-vzor, který tohle pravidlo vyvolal (WAN, nápověda, 2. 9. 2026): boční
obsah byl jen přilepený sloupec bez vlastní scrollovací oblasti. Kolečko nad
ním scrollovalo stránku, menu se pod kurzorem nehýbalo, a protože bylo vyšší
než obrazovka, jeho spodní témata nešla na nižších monitorech zobrazit vůbec.

Na dotykových zařízeních platí totéž jedním gestem: panel v podobě sheetu
nebo zásuvky drží scroll uvnitř sebe a nepřenáší ho na stránku pod sebou.

### Obsah a texty — co definovat

Konzistence rozhraní není jen barva a komponenta — je to i jazyk:

- Tón textů (jak aplikace mluví s uživatelem) a pravidla formulace akcí
  (sloveso na tlačítku říká, co se stane).
- Formulace chyb: co se stalo + co s tím, bez omluv a bez žargonu.
- Formáty dat, čísel a měn (lokalizace, oddělovače, časová zóna).

### Přístupnost — závazný kontrakt

- Okna drží fokus uvnitř; Escape zavírá (výjimkou jsou nevratné nebo
  právně citlivé kroky, kde je zavření vědomé rozhodnutí — pak to vzor
  řekne); po zavření se fokus vrací na spouštěč.
- Vše ovladatelné klávesnicí, smysluplné pořadí fokusu, viditelný
  fokusový stav.
- Ovladače mají přístupný název (ikonové tlačítko nese popisek pro
  čtečku); chybové hlášky jsou dostupné i čtečkám, ne jen barvou.
- Kontrast textu i netextových ovládacích prvků vůči podkladu; rozhraní
  snese zvětšení textu, aniž se rozpadne.

## Platformy — web / mobil / tablet

Jeden vizuální jazyk pro všechna zařízení: **značka, význam prvků a úroveň
jejich důležitosti jsou všude stejné** — uživatel přecházející z počítače
na telefon poznává tutéž aplikaci. Rozložení, hustota a způsob ovládání se
legitimně liší podle zvyklostí platformy. Projektový standard proto definuje:

### Co je stejné (neplatformní jádro)

Tokeny barev a typografie, role a stavy tlačítek, formulace textů,
ikonografie, sémantika stavových prvků.

### Co se na platformách liší (a musí být definované)

| Oblast | Mobil (dotyk, úzko) | Desktop (myš/klávesnice, široko) | Tablet |
|---|---|---|---|
| **Předěl** | pod hlavním breakpointem | nad ním | projekt řekne, ke které straně se tablet chová — a že dotykové ovládání platí dál |
| **Navigace** | spodní lišta / hamburger; hlavička s titulkem a zpět | boční panel / horní lišta | jako přiřazená strana |
| **Okna** | panel od spodní hrany (sheet), úchyt, strop výšky, patka nad hranou displeje | centrovaný dialog s max šířkou | jako přiřazená strana |
| **Dotyk/kurzor** | cíle ≥ 44 px, žádný hover jako jediný nosič informace | hover a fokus stavy, menší hustota povolena | dotykové cíle i na „desktop" rozložení |
| **Formuláře** | klávesnice podle typu pole, vyšší pole, méně sloupců | kompaktnější rytmus, více sloupců kde to dává smysl | podle šířky |
| **Tabulky/seznamy** | karty nebo redukované řádky, nikdy horizontální scroll celé stránky | plná tabulka | plná tabulka, dotykové ovladače |
| **Systémové okraje** | safe-area (výřez, home indicator) u fixních prvků | — | safe-area při instalaci jako PWA |
| **Gesta** | swipe jen jako doplněk viditelného ovladače | klávesové zkratky jako doplněk | obojí |

PWA instalace (ikony, splash, jméno na ploše) čerpá z brand balíčku — projekt
s PWA ambicí to napíše do svého standardu výslovně.

## Kontrola před nasazením

Závaznost bez kontroly je deklarace. Nová obrazovka nebo změněný klíčový tok
se před nasazením projde takto (stačí ručně, ale pokaždé):

1. Mobilní šířka + desktop — rozložení drží platformní kontrakt.
2. Prázdný, chybový a načítací stav existují (ne jen šťastná cesta).
3. Klávesnice: dá se to projít a ovládat bez myši, fokus je vidět.
4. Žádná nová ad-hoc varianta komponenty; hodnoty jen přes tokeny.

## Exceptions — výjimky

- Interní nástroje bez koncového uživatele brand balíček mít nemusí;
  závaznou šablonu vzhledu ano, pokud mají víc než jednu obrazovku.
- Fullscreen povrchy (prohlížeč dokumentů, kamera, mapa) smí opustit běžný
  chrom obrazovky — ale projektový standard definuje jejich vlastní jednotný
  chrom, výjimka není „cokoliv".
- Jiné výjimky schvaluje vlastník projektu a zapisují se do projektového
  standardu, ne do kódu.

## Enforcement — jak se vynucuje

- Projektový design standard je **závazná šablona**: nová obrazovka nesmí
  zavést vlastní variantu komponenty. Kdo potřebuje něco, co standard nemá,
  nejdřív doplní standard (dokument + sdílená komponenta), pak staví.
- Odchylka od standardu v revizi kódu = nález stejné váhy jako chyba.
- Po každé větší UI vlně se změří skutečnost proti standardu — počítají se
  **ad-hoc varianty komponent** (kolik nezávislých implementací okna,
  tlačítka, vstupu žije v kódu), ne kosmetika — a rozdíl se zapíše jako
  dluh s vlastníkem.
- Referenční implementace tohoto standardu je
  [WAN design standard](../../wan/design-standard.md) — první projekt, který
  jím prošel, včetně změřeného dluhu a migračního postupu.
