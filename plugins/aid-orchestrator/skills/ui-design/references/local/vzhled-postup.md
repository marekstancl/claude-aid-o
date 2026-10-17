# Postup: Vzhled a stavba (kroky 4, 5, 6 studia) – rostoucí živý web

Ověřeno v dílně 16. 10. 2026 na zkušebním podniku: test naslepo 3 směry dnešního studia × 3 nové – všechny tři nové nahoře
u PM, klienta i odborníka; hloubkové kolo na vítězi: odborník 7,25 → 8,15 → ≈ 8,6, klient 7,35 → 7,80 (brány 7,5).
Záznam dílny je mimo plugin.

**Nahrazuje:** ve `steps/4-references.md` výběr jednoho cizího webu jako zdroje směrů a ve `steps/5-directions.md`
zadání tří směrů (směry ze značky a tezí, rovnou jako stránky kostry).
**Platí dál:** zápisy a brány kroků 4–6 (`set refs`, `aid-ui-motion.py inventory`, `build-record`), vzor zadání
směru `vzhled-vzor/`.

## Zásady
- **Vzhled vychází ze značky a sdělení, ne z cizího webu.** Dnešní krok 4 vybral jeden cizí web a všechny tři směry
  z něj vycházely; hodnotitel našel v kódu komentáře s adresou cizí kanceláře a norský popisek tlačítka (opis).
- **Web roste v živé kostře** (F4): směry se staví rovnou jako stránky kostry (úvod, stránka služby, portfolio,
  telefon), vítěz se rozšíří na všechny stránky téže adresy. Krok 6 nestaví nový web, doplňuje kostru.
- **Pohyb:** pohyb značky (F2, `pohyb-znacky.md`) má přednost; ze vzoru jen pohyb níž na stránce, měřený nástrojem.

## Postup
1. **Tokeny ze značky** (`tokens.css`): barvy z loga s kontrolou kontrastu (barva loga pro grafiku, tmavší odstín
   pro text a tlačítka – klientovi vysvětlit v podkladech), písmo loga pro nadpisy + čitelné písmo textu s plnou
   češtinou, mono pro popisky a čísla, mřížka 12 sloupců, škála mezer, rohy, pohyb, poměry výřezů obrázků, tokeny
   podle účelu (`--c-*`), `--error` odlišná od „čeká na klienta“. Písma lokálně (žádný cizí server před souhlasem).
2. **Obrazový materiál klienta**: stáhnout z jeho webu (sitemap → stránky zakázek → nahrané soubory, originály
   bez `-WxH`), WebP do 200 kB (výjimka: hlavní obrázek s ≥ 2× hustotou do 300 kB), 200w/800w/plné, srcset a rozměry.
   Žádné fotobanky ani generované stavby. Přiřazení obrázku k zakázce = fakt „Ke kontrole“, pokud není jisté.
3. **Texty vzorku** (`copy.md`) pro úvod, hlavní službu, portfolio a kontakt – z registru faktů, bloky „ČEKÁ“
   jako označená místa; ostatní stránky jako popsané bloky s podkladem. Celé texty až s fakty klienta.
4. **Tři směry podle principu odvozeného z tezí** (tři různé principy, každý z jiné teze nebo jiného prvku značky),
   každý na úvodu, službě, portfoliu a telefonu, se společnými tokeny a texty (`zadani-smeru.md`). Vzory z oboru
   i mimo něj jen jako inspirace; rubrika obecnosti platí.
5. **Místo rozhodnutí „vzhled“ naslepo** (`aid-ui-quality.py round --place vzhled`): směry studia (i případné od dnešního kroku) zamíchané jako karty
   (počítač + telefon), odborník a klient podle `critic/web-local.{tech,owner}.vzhled.yaml`, PM Top / Jakž takž / Ne.
   Kombinace dvou vítězných směrů je dovolená, když sdílejí jazyk (dílna spojila dva principy se společným obrazovým jazykem).
6. **Hloubkové kolo:** vítěz na všechny stránky kostry, kontrola Playwrightem (1440/390/320 px, světlý i tmavý,
   omezený pohyb, fokus, dotykové plochy, žádný posun do strany), odborník a klient s pamětí do brány.
   Pozor na regrese při opravách (dílna: náhledová verze obrázku shodila jinak opravené kritérium).
7. **Podklady pro klienta:** proč tmavší odstín barvy loga, co dodat za fotky (typ záběru u každého prázdného místa),
   jak přidat položku nebo vyměnit fotku (návod k údržbě), seznam otázek se stejnými čísly jako na webu.

## Doplněno F7 (opakovaný běh 16. 10. 2026, neověřeno)
- **Naslepo doopravdy:** soubory směrů přejmenovat (K1–K3), neutrální `<title>`, z generátoru odstranit názvy směrů;
  seznam souborů, které role nečtou (`zadani-smeru.md`, klíč). F7: title i jména souborů prozrazovaly směr.
- **Kontrola směrů před předáním rolím:** menu ze struktury v jednom řádku na 1280–1440 px; telefon (odkaz `tel:`)
  a hlavní akce nahoře i na 390 px; požadavky klienta z předchozích míst (F7: telefon nahoře z E4) se přenášejí
  seznamem, ne pamětí.
- **Alt obrázku z nadpisu stránky zakázky**, ne z názvu souboru nebo verzálek starého webu.
- **Texty ostatních stránek** (krok 6, mimo vzorek kroku 3) jdou klientovi na kontrolu v hotovém webu jako jedno
  místo rozhodnutí; studio je převádí jen z registru faktů a stromu.
- **Statický export** (stránka na každé adrese, 404, robots, sitemap, `.htaccess` z inventury, canonical) je výstup
  hloubkového kola; poptávkový formulář bez serveru jen jako dočasný `mailto:` s otázkou pro klienta (hosting).
- Pohyb značky na webu podle limitů v `pohyb-znacky.md` (≤ 1 s, jméno hned).

## Podle typu
| | místní služba | B2B s portfoliem | webová aplikace | interní aplikace |
|---|---|---|---|---|
| Směry na | úvod, služba, kontakt, telefon | úvod, služba, portfolio + detail, telefon | hlavní obrazovka + tok ve stavech | totéž, jen monitor |
| Obrazy | fotky provozovny klienta | vizualizace, výkresy, fotky zakázek | skutečná vzorová data | skutečná data |
| Princip směru z | tezí a značky | tezí a značky (obrazový jazyk oboru) | úloh a stavů | knihovny součástí / existujícího systému |
