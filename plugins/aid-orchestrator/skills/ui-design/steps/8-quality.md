---
name: ui-design-step-8
description: /aid-ui after finish - the quality loop: two frozen independent critics (owner and technician) rate the web at once with the memory of their findings, the agent triages and fixes, at most three repair rounds or both at 8.5, three blind ratings per role close it
user_invocable: false
---

# Po předání - smyčka kvality

**Last Updated:** 2026-10-13 (P113a, dva kritici)

## Cíl

Web hodnotí dva nezávislí kritici:
- **Majitel** je náročný majitel podniku. Hodnotí první dojem, výjimečnost proti konkurenci, fotky,
  prodejní texty, důvěru a to, jestli zákazník najde cenu a objedná se.
- **Technik** hodnotí to, co majitel neumí posoudit: vyhledávače a hloubku obsahu, strukturovaná data,
  rychlost, přístupnost, mobil, doručení formuláře a připravenost ke spuštění.

Obě měřítka (`critic/<typ>.owner.yaml`, `critic/<typ>.tech.yaml`) napsali dva různí autoři jen ze zadání role
(`critic/role-briefs/`) a každé zrevidoval ten druhý (`critic/AUTHORS.yaml`). Měřítko neměň sám. Změna znamená
nové zadání role, nového autora a revizi.

- **Kolo je přijaté**, když oba dají aspoň 8,5 a žádné kritérium není pod 7.
- **Hodnotí se práce studia, ne to, co klient nedodal** (PM 13. 10. 2026). Drží-li kritérium dole jen otevřený bod
  klienta (vlastní fotky, přístup k hostingu…), kritik dá dvě známky:
  - `score`: jak web vypadá teď,
  - `studio_score` s `limited_by` (id bodů `oi-…`): jak dobře studio naložilo s tím, co mělo.

  Smyčka počítá `studio_score`. Studio i hlášení ukazují obojí („web teď …“). Zveřejnění dál blokují kritické
  otevřené body klienta. Kód odmítne `limited_by`, které není otevřeným bodem klienta.
- **Cesta k 10:** každé kritérium pod 10 nese `to_ten`, tedy konkrétní kroky rozdělené na „udělá studio“
  a „dodá klient“. Bez kroku je odpověď neplatná.
- **Strop:** nejvýš tři kola oprav. Jakmile je kolo přijaté, opravy končí a přijde audit.
- **Práh zná jen kód** (`aid-ui-critic.py`). Kritici ho neznají a nevidí ani minulé známky.

PM do smyčky nevstupuje. Vidí ji ve studiu v panelu Hotovo („Hodnocení majitele a technika“): známky obou rolí, cenu
a čas každého kola. Zprávu dostane jen při zastavení (rozpor nálezů, nic k opravě, strop kol) a na konci.

## Vstupy

- Hotový běh (`aid-ui-state.sh finish` prošel).
- Živý web (`.aid-ui/links.json` → `web`).
- Produktový kontext (`docs/content/product-context.md`, `docs/product-vision.md`, `docs/seo/brief.md`).
- Konkurence: `.aid-ui/critic/competitors.json`, 3-5 místních konkurentů ve tvaru `{name, url, why}`.
  - Vezmi je z části Konkurence v kontextu produktu a adresy dohledej.
  - Kontrola: bez nich majitel nehodnotí.

## Postup

1. **Zmraz kritiky** (jednou na projekt): `aid-ui-critic.py freeze <project> --type web-local`.
   - Obě role se složí ze svých měřítek a z kontextu projektu.
   - Řádky kontextu, které mluví o známkách nebo přijetí, se vyřadí.
   - Jakmile má smyčka kolo, měřítka už nejde změnit. Starší zmrazení s jedním kritikem se odmítne:
     archivuj `rounds/` a zmraz znovu.
2. **Nafoť konkurenci** (jednou na smyčku): `aid-ui-client.py competitors <project>`.
3. **Kolo:** `aid-ui-quality.py round <project> --web <url>`.
   - Před kolem musí projít `aid-ui-state.sh gate-check`: web je zaznamenaný build a brána nad ním nemá
     nepokrytý řádek.
   - Obě role běží souběžně. Každá dostane kopii webu, snímky každé stránky na 1440 a 390 px a registr faktů.
   - Majitel navíc snímky konkurence.
   - Technik navíc výsledky brány pro toto sestavení (rychlost, přístupnost, SEO, doručení formuláře)
     a otevřené body ke spuštění.
   - **Paměť:** každá role dostane své nálezy z předchozích kol i s tím, co se s nimi stalo. Vyřešený nebo
     zamítnutý nález smí zopakovat jen jako `regression_of` s novým důkazem.
   - Celá smyčka běží na adrese a kritikovi z prvního kola. Adresa musí obsluhovat právě tento web.
   - Poskytovatel: Codex na předplatném. Při limitu, prázdné nebo dvakrát neplatné odpovědi zaskočí Claude se
     stejným zadáním. Text nikdy nejde přes placené API.
4. **Roztřiď každý nález** (`aid-ui-quality.py triage <project> <id> <stav>`). Id má tvar `r<n>-owner-…` nebo
   `r<n>-tech-…`. Stavy:
   - `accepted --expected "<co se zlepší>"`,
   - `rejected_with_reason --reason`,
   - `duplicate --of <id>`: i napříč rolemi, když obě vidí tutéž vadu,
   - `blocked --reason`: s `--conflict-with <id>`, když oprava jednoho zhorší druhé (typicky velká fotka proti
     rychlosti). Smyčka se zastaví a rozhoduje PM. Brána má vždy přednost.
   - `superseded --reason`.

   Nálezy vlastníka `client` (fotky, právník, IČO) jsou rovnou `blocked` a patří do připravenosti, ne do známky.
5. **Oprav přijaté** podle `to_ten` a `fix` kritika stejnou cestou jako v kroku 6 a 7: zdroj webu, přestavba, `build-record`, brána,
   `gate-record`, při změně textů kontrola textů. Každou opravu zapiš:
   `aid-ui-quality.py fixed <project> <id> --evidence "<co se změnilo a kde>" --method "<krok nebo dovednost | z hlavy: proč postup nebyl>"`.
   Důkaz uvidí příští kolo autor nálezu.
   **Po každém kole zastav a pošli PM hlášení** (PM 13. 10. 2026). Obsahuje:
   - co navrhl majitel a technik (první tři nálezy každého a cestu k 10),
   - co jsi udělal a jak,
   - podle jakého postupu (krok, převzatá dovednost), nebo „z hlavy“ a proč postup nebyl či co na něm bylo špatné,
   - známky obou rolí (i „web teď“), cenu a čas kola.

   Mezery v postupech zapiš do deníku tření.
6. **Další krok řekne** `aid-ui-quality.py status <project>`:
   - `triage`, `fix` a `round`: pokračuj podle bodů 3 až 5.
   - `close`: cíl je splněný nebo kola došla a zbývají přijaté neopravené nálezy. Nastav jim
     `superseded --reason` a pokračuj auditem.
   - `audit`: bod 7.
   - `stop:*`: zpráva PM s důvodem a stavem.
   - `done`: konec.

   Kolo 1 je první hodnocení, kola 2-4 jsou opravná. Nejlepší kolo má vyšší známku slabší role, pak vyšší
   nejslabší kritérium, pak vyšší průměr.
7. **Audit:** `aid-ui-quality.py audit <project> --web <url>`.
   - Tři slepá hodnocení od každé role, bez paměti, nejlepší přijaté verze (`status` → `best`).
   - Když pozdější změna web posunula, vrať tu verzi (zdroj webu, přestavba, `build-record`, brána), jinak audit
     odmítne. Během auditu na webu nic neměň.
   - Přijato, když pro každou roli platí: medián ≥ 8,5, žádné hodnocení < 8 a žádné kritérium pod 7.
   - Výsledek jde do `.aid-ui/critic/verdict.json` včetně `publish_blocked_by`, tedy co musí dodat klient.
   - Když audit web nepotvrdí, nálezy auditorů se stanou kolem k roztřídění (`r<n>-a<k>-<role>-…`). To se
     nepočítá do stropu kol a ten web už audit znovu nedostane.

## Náklady a čas

Každé volání modelu jde do knihy projektu `.aid-ui/costs.jsonl`:
- kritici,
- kontrola textů,
- klient-agent,
- obrázky,
- práce agenta: řádek se zapíše před každým kolem a auditem z přepisu sezení Claude Code (`CLAUDE_CODE_SESSION_ID`,
  i podagenti).

Předplatné se vede jako ceníkový ekvivalent, placené API je jen obrazový model. Ten má strop 2 USD na projekt
(`AID_UI_IMAGE_BUDGET_USD`), hlídaný před každým obrázkem.

`loop.json` má u každého kola cenu podle druhu práce a čas od jeho začátku po další kolo. Práce agenta po kole patří
k tomu kolu, protože jde o opravy jeho nálezů. Bez přepisu sezení je práce agenta „neměřena“.

Přehled vypíše `aid-ui-client.py costs <project>`.

## Zápis

`.aid-ui/critic/` obsahuje:
- `frozen.json` (obě role),
- `competitors/` (snímky a `manifest.json`),
- `rounds/<n>/round.json`,
- `rounds/<n>/owner/` a `rounds/<n>/tech/`: zadání, snímky, odpověď, `run.json`,
- `rounds/<n>/history-<role>.json`: paměť, kterou role dostala,
- `audits/<otisk webu>/a1..a3/{owner,tech}/`,
- `loop.json`,
- `verdict.json`.

## Když krok selže

- **Jedna z rolí nedala platné hodnocení** od žádného poskytovatele: kolo se nezapíše a `run.json` role říká proč.
  Zkus to znovu později, Codex může mít vyčerpaný limit.
- **Chybí snímek některé stránky:** nehodnotí se. Ověř, že web běží (`aid-ui-serve.sh`).
- **Chybí snímky tří konkurentů:** majitel nehodnotí. Spusť znovu `competitors` a uprav `competitors.json`.
- **`stop:conflict`, `stop:stagnation`, `stop:round_cap`:** zpráva PM podle „Jak agent píše Markovi“. Uveď:
  - známky obou rolí po kolech,
  - cenu a čas,
  - co bylo opraveno a co zbývá,
  - možnosti A/B.
