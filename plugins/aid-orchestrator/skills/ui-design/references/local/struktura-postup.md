# Postup: Struktura a obsah + živá kostra (kroky 1s, 2, 3 studia)

Ověřeno v dílně 15. 10. 2026 na zkušebním podniku (web místní služby, redesign): test naslepo proti dnešním krokům 1s/2/3,
5 kol s pamětí hodnotitele, obě role prošly branou (odborník 7,60 v kole 4, klient 8,15 v kole 5).
Záznam dílny je mimo plugin. Typy B2B a aplikace na papíře (oddíl „Podle typu“).

**Nahrazuje:** ze `steps/1s-seo.md` inventuru a přesměrování starého webu, ze `steps/2-structure.md` postup stromu
a sekcí a ze `steps/3-content-plan.md` plán obsahu s „Co dodáte vy“.
**Platí dál:** výstupy a zápisy těchto kroků (`.aid-ui/structure.json`, `aid-ui-state.sh set structure|content-plan`,
brief pro vyhledávače v `docs/seo/brief.md`).

## Zásada: web je vidět od tohoto kroku (rozhodnutí PM 12. 10.)
Z této fáze vzniká **živá kostra na stálé adrese**: skutečné stránky se skutečnými adresami, menu, hlavičkou
(logo, telefon, „Poptat“) a patičkou; sekce jako popsané bloky; hned v ní to, co je schválené (logo a pohyb z 1i,
slogan a teze z 1p/1v). Další kroky ji v `site/` **jen doplňují** (texty, fotky, vzhled), stavba v kroku 6 na ní pokračuje;
stálá adresa ale ukazuje vždy jen kostru ze stromu (IMP-699), postavený web je vidět v náhledu brány.
Brána a klient ji kontrolují po každém kroku. Drátěné modely jako PNG odpadají.
Nástroj: `aid-ui-serve.sh skeleton <projekt>` postaví ze `structure.json` skutečné stránky (menu, hlavička, patička,
bloky čekající na klienta přerušovaně, u bloku „Důkaz / zdroj“) a servíruje je na stálé adrese
(`AID_UI_SKELETON_PORT`, výchozí 3918); `aid-ui-serve.sh skeleton-check <projekt>` ověří přesměrování a fakta.
Adresa servíruje **čistou kostru** `.aid-ui/skeleton/site/` (IMP-699, 3.10.1): celý strom vždy znovu, nic jiného, ať je
v `site/` cokoli (starý web, postavené stránky). Na ní role hodnotí, ověřovatel fotí a `skeleton-check` kontroluje
každou stránku. Do `site/` se kostra píše dál jako základ stavby; stránku bez značky kostry nepřepíše ani neodsune.

**Stálá adresa pro role (doplněno F7, neověřeno):** jakmile je kostra zveřejněná, každý `pro-role.md` od tohoto kroku
dál uvádí **stálou adresu kostry** (a které stránky posoudit) jako první podklad; role kostru proklikávají, ne čtou
dokumenty. Odborník, který o zveřejnění neví, hodnotí navigaci a „web je vidět“ z papíru (F7 E4 k2: navigace 7 jen
proto, že nevěděl o stálé adrese; brána neprošla o 0,2). Nástroj kostry bere telefon, značku a názvy sekcí
z registru faktů a `structure.json`, čekající bloky podle stavu faktu, nic natvrdo.

## Postup
1. **Úkoly zákazníka první** (Gerry McGovern, Top Tasks): z F3 „Kdo přichází a s čím“, hlasu zákazníka (téma ×
   počet zdrojů) a štítků katalogů. U každého: publikum, zdroj, kde se splní, hlavní / okrajový, „hotovo, když…“.
   Šablona úkolů podle typu, ne price/hours/booking pro všechny (oprava 33).
2. **Inventura starého webu** u redesignu ze **sitemap** (`wp-sitemap.xml`, `sitemap.xml`), ne z ručního výčtu:
   každá adresa jeden cíl 301, včetně souborů (PDF, obrázky), kategorií a výjimek; vzor pro sérii (projekty);
   technické adresy 410. Nic se nemaže bez nového místa (Google Search Central, přesun webu).
2a. **Rozsah obsahu – rozhodnutí klienta/PM, ne studia (doplněno F7, neověřeno).** Z inventury vyjde počet položek
   portfolia (dílna: přes sto položek). Před stromem se rozhodne a zapíše jako otázka pro klienta s doporučením:
   (a) **všechny položky** jako stránky (detail každé zakázky, filtr; úplnost, zachované adresy, víc práce s fotkami
   a texty), (b) **výběr** 8–12 vzorových položek s detailem + úplný seznam bez detailů - **výchozí doporučení, když klient
   neurčí jinak (D3, PM 17. 10. 2026)**, (c) jen výběr. Volbu dělá
   klient (v ručním režimu PM); studio uvede dopad na počet stránek, přesměrování a „Co dodáte vy“. Důkaz F7: běh dal
   všechny (přes 150 stránek), dílna výběr (11 stránek s označenými místy); naslepo obě role zvolily úplnost,
   PM vzhled dílny – bez výslovné volby rozhoduje náhoda postupu.
3. **Strom a menu z úkolů:** hlavní úkoly do jedné volby (položky menu slovy zákazníka, pojem oboru správně –
   pojem podle platného předpisu oboru), kontakt v menu, „Poptat“ a telefon v hlavičce na každé stránce.
4. **Sekce každé stránky:** co říká (teze), akce, typ důkazu a zdroj. Na každé stránce služby „jak dostanete cenu“
   (u podniku bez ceníku způsob nacenění). Sekce bez úkolu nebo sdělení se nenavrhuje. B2B: stránka reference
   zadání → řešení → výsledek, portfolio s filtrem typ × místo × rok.
5. **Brief pro vyhledávače:** adresa, H1, title, popis, dotaz slovy zákazníka (vše odhad); strukturovaná data
   (LocalBusiness, Person s autorizací, BreadcrumbList); bez znaku „|“ v buňkách tabulky; doba držení 301.
6. **Registr faktů** se stavem: každá karta, číslo i jméno v kostře musí mít klíč v `docs/content/facts.yaml`; zakázky ze starého
   webu „uvádět potvrdí klient“. Kostra nesmí nést fakt mimo registr (dílna: dvě karty s vymyšleným rokem shodily
   klientovi bránu „nepodepíšu nic neznámého“).
7. **Plán obsahu + „Co dodáte vy“:** seřazené podle dopadu, u každé položky proč, odhad času klienta, forma a **co se
   stane, když nedodá** (web jde ven po částech). Čísla odkazů držet stabilní (oprava 41).
8. **Místo rozhodnutí „struktura“:** odborník a klient podle `critic/web-local.{tech,owner}.struktura.yaml`, s pamětí;
   klikací test dělají hodnotitelé **v živé kostře** (Playwright, 1280 i 390 px), úkoly vybírají oni z podkladů;
   kolo `aid-ui-quality.py round --place struktura --web <adresa kostry>`.
9. **Zkouška s lidmi:** kostru projde PM (a před spuštěním aspoň 5 lidí mimo studio) se 3–4 úkoly; tvar stránky
   zkoušky naslepo: `vzory/README.md`.

## Doplněno po opakovaném běhu (15. 10. 2026, nový agent jen podle postupu)
1. kolo opakovaného běhu: odborník 7,15 (původně 6,50, brány kritérií prošly, vážený průměr ne), klient 7,60 (původně
6,60; padla jen brána „nepodepíšu nic neznámého“). Pravidla, která chyběla:
- **Kontakty a firemní údaje ze starého webu jsou otázka „platí ještě?“** (telefon, e-mail, adresa, IČO, DIČ) – do
  potvrzení v kostře přerušovaně, v plánu jako položka pro klienta.
- **Obsah, který se slučuje, se nezkracuje bez otázky** (např. seznam podporovaných organizací při sloučení stránek).
- **Hlavní úkol musí mít odpověď i bez čísla od klienta** (u „jak dlouho“: co dobu ovlivňuje, zákonné lhůty úřadu),
  číslo klienta ji jen zpřesní; odpověď na jednom místě, které štítek slibuje.
- **Štítky slovy zákazníka i u portfolia** (ne slovo, které se plete s nabídkou služby); adresa = štítek; filtr
  obsahuje všechny hodnoty z karet.
- **Povinné údaje:** zápis s.r.o. v obchodním rejstříku a IČO (§ 435 OZ), cookies jako řádek Ke kontrole, právní
  stránky; regulovaný titul přesně podle profesní komory oboru.
- **Úkoly zákazníka i z doplňkových služeb, které lidé hledají** (např. podklad pro banku).
- **Přesměrování ročníků a kategorií na statické adresy**, ne na parametr, který brief kanonizuje jinam.
- **Seznam „Co dodáte vy“:** u každé položky termín, celkový čas a stejná čísla jako v kostře.
- Nástroj kostry: telefon a značka z konfigurace (ne natvrdo), čekající bloky podle pole `stav`, ne podle slov v textu,
  víc detailů na sekci; úvod zkoušky podle počtu variant.

## Doplněno F7 (opakovaný běh všech fází 16. 10. 2026, neověřeno)
- **Cíl přesměrování musí ve stromu existovat** – kontrola skriptem „cíl ∈ strom“ (F7 k1: přesměrování na detaily,
  které kostra neměla; vážný nález odborníka).
- **Párovat staré adresy podle `<title>` stažené stránky, ne podle slugu** (F7: slugy starých příspěvků patřily jiné
  zakázce, 5 špatných cílů).
- **Soubory (fotky, PDF) mohou zůstat na stejné adrese** místo 301 1 : 1, když nové místo neexistuje; zapsat jako vzor.
- **Zrušení služby ze starého webu = otázka pro klienta**, stejně jako slučování (F7: poradenství, klient vrátil).
- **Výklad předpisu na webu (lhůty, co nepotřebuje povolení) je tvrzení ke kontrole klientem** se zdrojem a datem;
  pojmy podle platného znění předpisu, ne podle starého webu.
- **Štítek portfolia:** štítek, který slibuje jinou roli, než klient má (F7: klient službu navrhuje, neprovádí),
  neplatí - štítek ověřit v odpovědích klienta.

## Podle typu
| | místní služba | B2B s portfoliem | webová aplikace | interní aplikace |
|---|---|---|---|---|
| Úkoly | cena, kdy otevřeno, objednání (jen má-li podnik) | jak dlouho, vyřídí za mě, cena/nacenění, reference v okolí, poptávka | úlohy rolí | úlohy rolí |
| Inventura | starý web (sitemap) | starý web + portfolio (vzor adres) | dnešní obrazovky | stávající postup (tabulky, e-maily) |
| Strom | služby, ceník, kontakt | služby podle úkolů, portfolio s filtrem, reference | role, navigace, toky v 7 stavech | totéž |
| Kostra | stránky | stránky + detail reference | obrazovky toků (běžná cesta + prázdno) | totéž |
