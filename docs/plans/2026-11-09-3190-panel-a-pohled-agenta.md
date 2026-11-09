# Zadání 3.19.0 - panel po otázkách a agent vidí živý náhled sám

Stavba mimo AID. PM 9. 11. 2026 po 3.18.1: (1) panel živého náhledu „co volba to jedna stránka, posuvník ke spodní hraně,
sekce vždy na stejném místě: nahoře varianty, popis a doporučení, pak značky, pod tím volný text"; po živé ukázce
„super, jen bez zprůhlednění, text nezkracovat, větší výška, když nevleze ok scroll". (2) „agent, co staví návrh UI,
nemá řešit bezpečnostní sračky, má rovnou rychle stavět" - a WAN P126 (`wan/.aid-o/work/aid-plugin-issues.md`
9. 11.): agent se na živý náhled nepodívá sám, `shots` živou kopii odmítá a do aplikace se neumí přihlásit.

## 1. Panel (hotový návrh, PM viděl živě na kopii WANu P126)

- Jedna otázka na stránku; pevná výška `min(780px, 100vh - 24px)`, části vždy na stejném místě: hlavička „otázka N
  z M", horní část (otázka, varianty s ★ u doporučené a ✓ u vybrané, popis zobrazené, „★ Doporučuji X - proč",
  „Vybrat"), značky (počet, „+ Značka", ukázat/skrýt, nejvýš 3 řádky a „+N"), poznámka k otázce, dole „‹ předchozí ·
  tečky · další ›" a „Odeslat volby · vybráno n z m". Text celý; když se nevejde, posouvá se jen horní část.
- Bez zprůhlednění. Přechod na otázku přepne na její vybranou, jinak doporučenou, jinak první variantu a její obrazovku.
- `live.json` nese u bodu volitelně `doporuceni` (klíč varianty) a `proc` (věta); kit je ověří (klíč existuje, text).
- Poznámky se odešlou při opuštění pole, přechodu na jinou otázku i „Odeslat" (žádná se neztratí).

## 2. Agent vidí, co uvidí PM

- **`live` se po startu proxy sám podívá:** projde každou variantu každého bodu (`cesta?v=klic`) na všech výřezech
  projektu přes proxy (stejná stránka jako PM, bez panelu), vyfotí celou stránku a změří totéž co `shots` (oříznuté
  dialogy, stránka širší než okno). Vrátí `look: [...]` (soubory k přečtení) a `clipped`. Snímky leží v
  `<P>/live-check/` (pracovní složka companionu, mimo repo); `down` je nechá, nový `live` je přepíše.
- **Přihlášení zařídí kit:** `ui.live.login` v `project.yaml` = příkaz (pole jako `dev_cmd`), který vypíše JSON
  `{"localStorage": {...}, "cookies": [...]}`; kit ho spustí před prohlídkou a vloží do prohlížeče. Bez `login`
  prohlídka běží nepřihlášená a výstup to řekne. Selhání příkazu = varování ve výstupu `live`, odkaz pro PM se vydá.
- **`shots` nad živou kopií smí:** v živém režimu jde přes proxy (proměnná varianty jako u PM), API nejde na mocky ale
  do vývojového API, přihlášení z `ui.live.login`, panel se nevloží. Ostatní pravidla `shots` (kroky, výřezy, měření)
  beze změny. Pro dialogy a kliky, které automatická prohlídka nedělá.
- Co zůstává (agent to neřeší, dělá to kit sám): klíč v odkazu PM, seznam povolených adres API, čisté prostředí kopie.

## Hotovo

- **AC1** panel podle bodu 1 (test v prohlížeči: přechod mezi otázkami přepne variantu a obrazovku, poznámka se
  odešle při přechodu, žádné průhlednosti, horní část se posouvá a zbytek panelu stojí).
- **AC2** `live` vrátí `look` se snímkem každé varianty na každém výřezu a `check` u každého; s `ui.live.login` je
  stránka přihlášená (test: napodobená aplikace pustí jen s tokenem v localStorage).
- **AC3** `shots` nad živou kopií projde přes proxy bez mocků a s přihlášením (test).
- **AC4** skill visual-companion (≤ 200 řádků) a brainstorming: po `live` přečíst `look`, pak odkaz PM; CHANGELOG 3.19.0,
  registr verzí; T0+T1, sady companionu, testbed; WANu do hlášení přesný `ui.live.login` (testovací účet
  `e2e-admin@wan.test`, přihlášení ověřeno 9. 11.: 200).

## Po revizi zadání (Codex, 9. 11. 2026) - mění body výš

- **Jedna cesta pro prohlídku i živé `shots`:** `live` vygeneruje `live-check.json` (bod `b<bod>-<klic>`, `path` =
  `cesta?v=klic`, celá stránka) a pustí `shots` s ním do `live-check/`. Prohlídka běží při KAŽDÉM `live`, i když se
  proxy znovu použije (agent změnil varianty), staré snímky smaže.
- **Živé `shots`:** základ = proxy na `127.0.0.1:<port>`; prohlížeč dostane cookie proxy (`aid_t_<port>`), takže
  varianta jde z `?v=` a cookie jako u PM; init skript `window.__AID_LIVE_PANEL__ = true` panel nevloží. Bez mocků a bez
  požadavku na `api_prefix`; jen navigace na cizí origin se zastaví. Připravenost a měření jako dnes (`networkidle`
  + 300 ms, `measure`). Vnitřní scroll (WAN `<main>`) - celá stránka ho nerozvine; agent na to má `{"scroll": …}` v
  `shots` (prohlídka je první pohled, ne náhrada).
- **Přihlášení:** `ui.live.login` se spustí JEDNOU za běh (`cwd` = kořen projektu, prostředí agenta, timeout 20 s),
  výsledek do každého kontextu před načtením; `shots.json` `storage` má přednost; cookies na adresu proxy. Selhání,
  timeout, neplatný JSON = `login: {ok: false, error}` ve výstupu, běh pokračuje nepřihlášený.
- **Selhání snímku nezastaví ostatní** (jen v prohlídce): výstup `{"check": {"complete": bool, "login": {...},
  "results": [{"shot", "bod", "klic", "viewport", "png", "clipped": [...], "error"?}]}, "look": [png…]}`; `live` vždy
  vrátí odkaz (exit 0), agent vidí `complete`.
- **Identita:** `live.json` - `bod` jedinečné, `klic` jedinečný v bodu, stejný `klic` na stejné `cesta` ve dvou bodech
  odmítnut (proměnná varianty je jedna na stránku), `doporuceni` jen existující klíč. Odkaz pro PM otevře první bod na
  jeho doporučené (jinak první) variantě; zobrazení doporučené nic nevybere.
- **Panel:** stav (otázka, volby, poznámky) v `sessionStorage` - přepnutí je `pushState`, stránka se nenačítá znovu.
  Poznámka: přechod čeká na uložení, neúspěch nechá text k dalšímu pokusu (označen neodeslaný).
- **Mimo rozsah:** API na jiném originu (`ui.api_origins`) v živém režimu (beze změny od 3.17).
- **AC4** navíc: na kopii WANu `live` s `ui.live.login` vrátí snímek přihlášené obrazovky (ne přihlašovací stránky).
