# Kontrolní seznam spuštění webu (P115)

Body, které `aid-ui-package.py zadani` udělá ze zadání plánu nasazení navíc k úkolům zákazníka, podkladům ke spuštění
(`.aid-ui/launch.json`, `aid-ui-launch.py`) a otevřeným bodům. Podklady ke spuštění (IČO, hodiny, fotky, právní
texty, příjem formuláře, doména a hosting) tu nejsou - mají svůj bod z balíku, jednou. Řádky připravenosti (https až
katalogy) jsou seznam z kotev kritéria `bezpecnost_spusteni` (`critic/web-local.tech.yaml`); kotva zůstává textem pro
kritika, tady je tentýž seznam jako body, které jdou ověřit.

Hosting je práce plánu (PM 17. 10. 2026, 2A): žádný generátor konfigurace, jen body „hotovo". Ověření běží z kořene
projektu; `@PLUGIN@` a `@BRIEF@` dosadí `zadani` (cesta k pluginu a k zadání), adresa webu je `url` z
`docs/ui/nasazeni.json`, který zapíše bod `nasadit_balik`. Ruční doklad (katalogy) je řádek `<id>: <co a kde>`
v `docs/ui/dukazy.md`. Svislítko v příkazu je `\|`.

| id | co | vlastník | blokuje spuštění | ověření |
|---|---|---|---|---|
| nasadit_balik | Nasadit přesně soubory z balíku `docs/ui/predani.json` beze změny (soubory navíc smazat), zapsat `docs/ui/nasazeni.json` s `url` a `listing` (`type` ssh, sftp nebo local, `host`, `root`); brána `check_ui_handover --launch` projde | run | ano | `bash @PLUGIN@/scripts/aid-ui-verify.sh --package-gate @BRIEF@ --launch` |
| https | Web běží na HTTPS a http:// přesměruje (301, 302, 307 nebo 308) na https:// | run | ano | `u=$(jq -r .url docs/ui/nasazeni.json); case "$u" in https://*) ;; *) exit 1;; esac; h=$(curl -s -o /dev/null -D - "http://${u#https://}" \| tr -d '\r'); grep -qE '^HTTP/[0-9.]+ 30[1278]' <<<"$h" && grep -qiE '^location: https://' <<<"$h"` |
| hlavicky | Bezpečnostní hlavičky: Content-Security-Policy, Strict-Transport-Security, X-Content-Type-Options | run | ano | `h=$(curl -sI "$(jq -r .url docs/ui/nasazeni.json)"); for k in content-security-policy strict-transport-security x-content-type-options; do grep -qiE "^$k[[:space:]]*:" <<<"$h" \|\| exit 1; done` |
| stranka_404 | Neexistující adresa vrací stránku 404 se stavem 404 | run | ano | `u=$(jq -r .url docs/ui/nasazeni.json); curl -s -o /dev/null -D - "${u%/}/aid-neexistuje-404" \| head -1 \| grep -qE '^HTTP/[0-9.]+ 404'` |
| citlive_soubory | Citlivé a vývojové soubory (.env, .git) nejsou dostupné a balík nemá zdrojové mapy; server musí na každou zkoušku odpovědět | run | ano | `u=$(jq -r .url docs/ui/nasazeni.json); for p in .env .git/HEAD .git/config; do s=$(curl -s -o /dev/null -D - "${u%/}/$p" \| head -1); grep -qE '^HTTP/[0-9.]+ [0-9]{3}' <<<"$s" \|\| exit 1; grep -qE '^HTTP/[0-9.]+ 2' <<<"$s" && exit 1; done; ! jq -e '.site.files[].path \| select(endswith(".map"))' docs/ui/predani.json` |
| dns | Doména webu se překládá (DNS u správce domény) | pm | ano | `python3 -c 'import json,socket,urllib.parse; socket.gethostbyname(urllib.parse.urlparse(json.load(open("docs/ui/nasazeni.json"))["url"]).hostname)'` |
| email | E-mail na doméně webu přijímá zprávy (MX u správce domény, zkušební zpráva došla) | pm | ne | `grep -qE '^email: .+' docs/ui/dukazy.md` |
| katalogy | Google profil, Firmy.cz a ostatní katalogy vedou na novou adresu | client | ne | `grep -qE '^katalogy: .+' docs/ui/dukazy.md` |
| presmerovani | Staré adresy přesměrované na nové (inventář struktury, `.aid-ui/skeleton/redirects.csv`) | run | ano | `python3 @PLUGIN@/scripts/aid-ui-package.py live-redirects .aid-ui/skeleton/redirects.csv` |
| hodnoceni | Hodnocení po nasazení nad ostrou adresou přijaté, pro tutéž adresu a tentýž web | pm | ano | `python3 @PLUGIN@/scripts/aid-ui-quality.py launch-status . --package docs/ui/predani.json` |
