# Zadání 3.18.1 - živý náhled zadrátovaný jako výchozí

Stavba mimo AID. Volba PM 1A (9. 11. 2026): „chci to používat všude ve všech projektech nativně, zadrátované, agent ví co dělat".

## Proč

Živý náhled (3.17-3.18) funguje, ale nic ho nezapíná:
- `/aid-init` navrhne `ui.dir`, `ui.dev_cmd`, … (`aid_ui_config_detect`), ale `ui.live` ani nezjistí, ani se na něj neptá;
- žádný projekt `ui.live` nemá (WAN, Trading, Agents ověřeno 9. 11.);
- `skills/brainstorming.md` (podle něj agent jede) vyjmenovává jen fotky (`up`, `proto`, `shots`, `show`); skill
  visual-companion říká „live first", ale agent bez `ui.live` tiše skončí u fotek a PM se nedozví, že mohl mít živou aplikaci.

## Co se mění

1. **Zjištění (`scripts/lib/aid-ui-config.sh`, `aid_ui_config_detect`)** - u Vite přečte z `vite.config.*` proměnnou,
   kterou si config bere adresu API (`process.env.X ?? 'url'` nebo `|| 'url'`), a navrhne `ui.live`:
   - výchozí URL se z hostitele přeloží → `env: {X: <ta URL>}`, `allowed_api: [<její adresy>]`;
   - nepřeloží se (jméno kontejneru, `wan-api-dev:3501`), ale její port na tomhle hostiteli poslouchá →
     `env: {X: http://<LAN IP hostitele>:<port>}`, `allowed_api: [<LAN IP>]` (to, co PM ověřil na WANu);
   - jinak jen komentář s názvem proměnné (adresu doplní PM), nikdy odhad;
   - jméno proměnné, které vypadá jako tajemství (KEY/TOKEN/SECRET/PASS/CREDENTIAL/AUTH), se nenavrhuje (kit ho odmítne);
   - u navržené adresy komentář „ověř, že je to VÝVOJOVÉ API" - zapíše se jen na ano PM (jako zbytek `ui`).
   LAN IP hostitele bere ze stejné funkce jako adresa pro PM (`url_host` se přesune do knihovny, žádná druhá kopie).
2. **Kit to řekne sám (`scripts/aid-companion.sh up`)** - kód, ne próza: na stderr jedna věta
   - projekt má `ui.dir` a nemá `ui.live.env` → „bez ui.live uvidí PM u existující aplikace jen fotky; návrh bloku:
     `aid_ui_config_detect`";
   - má `ui.live.env` → „u existující obrazovky živý náhled: proto --live, live.json, live (fotky jen pro návrh od nuly)".
3. **Agent ví, co dělat (`skills/brainstorming.md`, `skills/visual-companion/SKILL.md`, `commands/aid-init.md`)** -
   rozcestí: existující obrazovka + `ui.live` → živý náhled; existující obrazovka bez `ui.live` → ukázat PM navržený
   blok (`aid_ui_config_detect`), zapsat na ano, pak živý náhled; návrh od nuly nebo aplikace bez vývojového serveru
   (widget, jen build) → fotky. `/aid-init` u projektu, který `ui` má a `ui.live` ne, navrhne jen chybějící `ui.live`.
4. **Projekty** - WAN: blok `ui.live` (`VITE_API_TARGET: http://10.20.20.22:3501`, `allowed_api: [10.20.20.22]`)
   zapíše okno WANu, protože v `project.yaml` má jiné okno necommitnutý blok `ui` (předám mu přesný text do hlášení
   WAN). Trading (UI jen v nesloučené větvi) a Agents (widget bez vývojového serveru) živý náhled dnes nemají na čem
   ukázat - jen poznámka v hlášení, nic se nezapisuje.

## Mimo rozsah

Přihlášení v živé kopii, HMR, doba života proxy (IMP-715); `/aid-setup` (UI modul nemá, `ui` patří `/aid-init`).

## Hotovo

- **AC1** `aid_ui_config_detect` nad Vite configem s `process.env.X ?? 'http://127.0.0.1:<port>'` navrhne `ui.live`
  s tou URL a `allowed_api: [127.0.0.1]`; s nepřeložitelným hostem a poslouchajícím portem LAN IP; s nepřeložitelným
  hostem a zavřeným portem jen komentář; s proměnnou `*_TOKEN` nic. Navržený blok projde kontrolou kitu (`proto --live`
  ho nezamítne) - test.
- **AC2** `up` napíše jednu ze dvou vět podle toho, zda `ui.live.env` je - test.
- **AC3** brainstorming, skill visual-companion a aid-init popisují rozcestí shodně; skill ≤ 200 řádků (AC7 kitu).
- **AC4** CHANGELOG 3.18.1, registr verzí; T0+T1, sady companionu, testbed; text pro WAN do jeho hlášení.

## Po revizi zadání (Codex, 9. 11. 2026) - mění body výš

- **Bez odhadu adresy (nálezy 1, 2):** odpadá „port poslouchá → LAN IP". Navrhne se jen URL, která se z hostitele přeloží;
  jinak komentář s názvem proměnné a PM adresu řekne. `url_host` se nepřesouvá.
- **Tajemství v URL (3):** detekce nenavrhne URL s `user:heslo@` ani s `?` dotazem; kit (`liveEnv`) URL s přihlašovacími
  údaji odmítne, hodnotu nevypíše.
- **Jen cíl proxy (4, 8, 13):** proměnná se bere jen z `target:` (Vite `server.proxy`) nebo `destination:` (Next
  `rewrites`) - tedy API, na které aplikace sahá přes vlastní server, ne z prohlížeče (CSP `connect-src 'self'`).
  Víc různých proměnných → komentář se všemi kandidáty, nic se nevybírá.
- **Existující `ui.dir` (5):** nová funkce `aid_ui_live_detect <root> <ui.dir>`; `/aid-init` u projektu s `ui.dir`
  volá ji, ne celou detekci. `aid_ui_config_detect` ji volá pro složku, kterou sám našel.
- **Tři stavy (6, 11):** `up` (i znovupoužitý server, stdout zůstane čisté JSON) řekne na stderr: bez `ui.dir` nic;
  `ui.live` chybí / je neúplné (chybí `env` nebo `allowed_api`) / je vyplněné. Úplnou kontrolu dál dělá `proto --live`.
- **Brána brainstormingu (7, ověřeno: `aid-brainstorm-state.sh` ř. 289-301 chce `proposal.json`):** `live` zapíše
  podklad `design-system` s `NO LIVE BASELINE — live preview: …` (snímky živých dat se nedělají) do
  `brainstorm/<P>/proposal.json`, jen když složka brainstormu existuje a podklad nevznikl z fotek (`show`).
- **Rozcestí a nabídka (9, 10, 12):** nabídka companionu u obrazovky existující aplikace doporučí ano; větve: blok
  navržený → ano PM → živý náhled; jen komentář → zeptat se PM na adresu vývojového API; PM odmítne nebo `proto --live`
  selže → fotky a říct proč; aplikace bez vývojového serveru (widget) → companion ji neukáže, říct to.
- **AC1** navíc: dvě proměnné → komentář; URL s heslem → nic; navržený blok projde `liveEnv`. **AC2** i pro znovupoužitý
  server. **AC5** `live` zapíše podklad, který projde `aid_ui_proposal_basis_check`, a nepřepíše podklad z `show` - test.
