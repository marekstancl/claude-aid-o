# Postup: Kontrola hotového webu (návrh dílny F6, nová kontrola)

**Nahrazuje:** ve `steps/7-verify.md` výběr vzorku stránek a šířek (brána jde přes každou stránku a šířku) a ve
`steps/8-quality.md` hodnocení hotového webu jen měřítky hotového webu (role hodnotí i měřítky vzhledu a struktury).
**Platí dál:** dnešní řádky brány (`aid-ui-verify.sh`), záznam brány (`aid-ui-state.sh gate-record`) a smyčka kvality.

Kontrola je poslední místo rozhodnutí. Běží nad živým webem po každém kole a před předáním. Výsledek: seznam nálezů
(stránka, místo, co, důkaz, závažnost blokující / vážná / drobná, kdo opraví: studio / klient) a známky rolí.

## A. Strojová brána (každá stránka, 1440 / 390 / 320 px, světlý i tmavý režim, omezený pohyb)
**Bez vzorku (doplněno F7, neověřeno):** každá stránka stromu × každá šířka (1440 / 1024 / 768 / 390 / 320) × světlý
i tmavý režim; vzorkování je zakázané i u stránek z jedné šablony, když mají různá data (délky názvů, šířky obrázků).
Výstup brány uvádí počet změřených stránek × šířek a porovná ho s počtem stránek stromu; nesouhlasí-li, brána neprošla.
Důkaz F7: brána v kole 1 běžela na telefonních šířkách jen na vzorku 30 ze 152 stránek a „prošla“; odborník pak našel
11 detailů zakázek přetékajících na 390/320 px (inline `max-width` přebil CSS). Na všech stránkách 0 nálezů až v kole 2.
1. **Odkazy a stránky:** projít všechny interní odkazy a kotvy; každý cíl 200 a existující kotva; 404 má vlastní stránku.
2. **Přístupnost automaticky:** axe-core (WCAG 2.2 A/AA) na každé stránce; kontrast textu ≥ 4,5:1 (velký 3:1);
   alt u obsahových obrázků (dekorativní jen s `aria-hidden` nebo prázdným alt a role); jedno H1 na stránku; pořadí nadpisů.
3. **Klávesnice:** projít Tab celou stránku; každý zaměřený prvek má viditelný fokus (změna obrysu/stínu ≥ 2 px, kontrast ≥ 3:1).
4. **Telefon:** žádný vodorovný posun na 390 a 320 px; dotykové plochy ≥ 44 × 44 px (odkazy v textu výjimka); písmo ≥ 14 px.
5. **Obrázky:** hustota zobrazeného souboru ≥ 2× na 1440 i 390 px (naturalWidth / CSS šířka × DPR 2); rozměry width/height; velikost ≤ 200 kB (hlavní ≤ 300 kB).
   (doplněno F7, neověřeno) U `srcset` s deskriptorem `w` vrací `naturalWidth` šířku přepočtenou hustotou, ne šířku
   souboru – měřit skutečnou šířku souboru (`new Image()` z `currentSrc`). Když originál klienta na 2× nestačí:
   vykreslit nejvýš ½ šířky originálu, nebo položka „větší soubory“ do „Co dodáte vy“ (rozhodne klient).
   Žádné pevné rozměry v inline stylech z generátoru (přebijí pravidla CSS; F7: 11 přetečení).
6. **Pohyb:** po 10 s žádná běžící animace – CSS (`document.getAnimations()`) i skriptová (dva snímky po 1 s se nesmí lišit
   mimo interakci; sledovat změny `style`/`transform` přes MutationObserver); při `prefers-reduced-motion` žádný pohyb.
7. **Soukromí:** před souhlasem žádný požadavek na cizí doménu (zaznamenat všechny požadavky a cookies při načtení).
8. **První vykreslení:** H1 a hlavní text viditelné do 1 s, ne jen v SVG nebo canvasu.
9. **Regrese:** vše, co prošlo v minulém kole, se měří znovu.

## B. Obsah a fakta
10. **Každé tvrzení na webu** (čísla, roky, jména, reference, doporučení, sliby, ceny, doby) dohledat v registru faktů
    (`docs/content/facts.yaml`) a ve schváleném sdělení; tvrzení bez zdroje = blokující; zdroj „ze starého webu / katalogu“
    bez potvrzení klienta smí být jen jako označené místo „čeká na klienta“.
11. **Sliby a reklama:** žádné „nejlepší, nejrychlejší, levně“ bez doložení (zákon č. 40/1995 Sb.), žádná doporučení
    třetích stran bez souhlasu.
12. **Povinné údaje:** IČO a zápis v rejstříku (§ 435 OZ), informace o zpracování osobních údajů u formuláře (GDPR čl. 13),
    ochrana osobních údajů, cookies (lišta jen pokud web cookies používá).
13. **Struktura a vyhledávače:** H1 a title proti briefu; strom stránek proti struktuře.

## C. Role (s pamětí, měřítka míst)
14. **Odborník** podle `web-local.tech.vzhled.yaml` a `web-local.tech.struktura.yaml` (hotový web = obě místa)
    a dnešního `web-local.tech.yaml`; **klient** podle `web-local.owner.vzhled.yaml`, `web-local.owner.struktura.yaml`
    a `web-local.owner.yaml`; fakta, která klient nezná, neschválí. Kolo: `aid-ui-quality.py round --place web`.
15. **Audit naslepo** na konci: nová instance obou rolí bez paměti; rozdíl proti poslednímu kolu > 1 bod = kalibrace.

## D. Lidé
16. **Zkouška s lidmi:** 3–5 lidí mimo studio, 4 úkoly zákazníka na živém webu; výsledek je řádek brány. Bez lidí =
    otevřený bod před spuštěním.

## Ověřeno v dílně (16. 10. 2026, zkušební podnik)
- **Zasazené vady (error seeding, Mills 1972):** 13 vad do kopie hotového webu. Dnešní kontrola 10/13 (neviděla
  rozmazaný obrázek, skriptovou animaci, malé dotykové plochy), nová 13/13. Dnešní kontrola ale našla skutečné vady,
  které nová neměla (přetečení na 768 px, favicon, JSON-LD, robots, sitemap, canonical) → **nová = dnešní brána + body
  výše, ne náhrada.** Umělá sada k opakování v testech pluginu: `scripts/tests/fixtures/aid-ui/verify-site/`
  (klíč vad v jejím `README.md`).
- **Šířky:** k 1440/390/320 vždy i 1024 a 768 (tablet: boční panel, zalomení H1, překryv razítek).
- **Jednosouborová verze** (náhled) musí mít `meta viewport`, jinak se na telefonu vykreslí na 980 px a kontrola
  v emulaci prohlížeče lže.
- **Pohyb značky se musí dostat do stavby:** F2 dodá pohyb, krok stavby ho zapojí (`pohyb-znacky.md`), kontrola ověří,
  že na úvodu běží (dílna: stavbař dostal „žádná animace loga“ a pohyb chyběl, dokud si PM nevšiml). Měří se: jméno
  v logu čitelné od začátku, značka ≤ 1 s, detail oboru 400–500 ms, po 1 s nic neběží, omezený pohyb = hotový stav.
  (doplněno F7, neověřeno) Stejné limity jsou nově v `pohyb-znacky.md` a v `critic/web-local.*.pohyb.gates.yaml`
  (`metrics`); v F7 si odporovaly (pohyb schválený v E3 2,2 s × kontrola ≤ 1 s).
  PM pohyb posuzuje na samostatné stránce s „Přehrát znovu“ a „Zpomaleně 4×“ – na webu běží jednou a v 44 px.
- **Inventura a přesun** jsou brána struktury i u hotového webu: `.htaccess` (301) + `.aid-ui/skeleton/redirects.csv`, každý cíl
  existuje i s kotvou; filtr čte parametry ze starých adres.
- **Čísla otázek** na webu a na stránce „co schválit“ ze stejného zdroje (skript), každý štítek „čeká na klienta“ má číslo.
- **Zkouška s lidmi:** měřicí lišta musí brát stránku podle viditelné sekce, ne podle kotvy (`#poptavka` je na Kontaktu;
  dílna zapsala úspěšný úkol jako „jinde“).
- **Výsledek pro klienta:** stránka „Co schválit“ (shrnutí, změny, otázky, fotky, údržba, značka, náhradní úvod,
  zaškrtávací seznam). Tvar: `vzory/README.md`.
