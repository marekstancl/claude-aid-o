# P113 - ověření na Coufalovi přes nové studio (17. 10. 2026)

Stav: **nedokončeno** - čtyři místa vrácená po vyčerpání kol a hotový web se nedal hodnotit (build-record odmítl
zápis buildu, protože pohyb stojí na logu bez přijatého verdiktu - ochrana kroku 2 funguje). Zpráva drží otevřené
výsledky; krok 11 se uzavře po rozhodnutí PM.

Běh: kopie projektu `coufal2` v `.aid-o/work/P113-coufal/coufal2` (originál netknutý, servery PM nad ním běží dál),
plugin z větve `feat/p113-studio-podle-dilny`, role na Claude Opus, PM varianta C (bez zastávek do konce).
Značka PM: `coufal-clinic-brand.zip` (rozbaleno do `.aid-ui/brand-pm/`, nasazeno do `docs/design/brand-package/`).

## Místa

| Místo | Kola (klient / odborník) | Verdikt | Co rozhodlo |
|---|---|---|---|
| sdělení | k1 6,05/6,20 · k2 7,15/6,55 · k3 7,55/7,15 · k4 7,75/7,55 | returned | nálezy `fakt` kola 4 (slogan „meno lekára“ vs. externí lékaři, datum a počet v registru) - opraveny po kole 4, další kolo už kód nedovolil |
| logo | k1 5,35/5,56 · k2 5,80/6,48 (dodáno PM, `--supplied`) | returned | tvar značky PM (myšlenka nečitelná z loga, tah vs. „tenká rytina“ předlohy) - studio dodanou značku nemění, rozhoduje PM |
| pohyb | k1 7,35/6,49 · k2 7,50/7,15 | accepted | webová verze z geometrie značky PM (0,9 s, jméno hned, rozdíl konce 0 px); animace PM 2,6 s = verze pro video |
| struktura | k1 7,40/6,80 · k2 7,60/7,15 · k3 7,95/7,80 · k4 8,25/8,25 | returned | brána klienta „nepodepíšu nic neznámého“ 6 < 8 (výklady zkratek a protéz na webu) - opraveno po kole 4 |
| vzhled | k1 4,60/5,00 · k2 7,05/6,05 · k3 6,70/6,60 · k4 7,40/6,85 (směr 2, klient) | returned | brány „dám to udržovat“ 5 < 6 (klient) a mřížka 6 < 7 (odborník) |
| hotový web | neběželo | - | build-record odmítl: pohyb stojí na logu bez přijatého verdiktu |

Audit naslepo: neproběhl (hotový web nebyl hodnocen).

Volání rolí: 33 hodnocení na Opusu v pěti místech, Claude Opus 33, Codex 1 (vzhled k2 odborník: Opus dvakrát mimo
schéma, odpověděl záskok Codex - podle plánu se do AC12 nepočítá a má se zopakovat na Opusu).

Náklady (ceníkový ekvivalent předplatného, `costs.jsonl` od 17. 10.): role 57,91 USD (53 záznamů), práce agenta
280,36 USD (18 záznamů); placené obrazové API 0 USD (žádný obrázek se negeneroval).
Čas: 17. 10. 2026 13:20-16:45 (sdělení k1 až vzhled k4).

## Vady pluginu, které běh našel (opraveny v tomto kroku, s testem)

| Vada | Commit |
|---|---|
| zhoršení nálezu, který byl duplicitou opraveného, se nedalo zapsat (kolo odmítnuto) | bf13108b |
| karta směru: inverzní panel barevné značky na černé | bf13108b |
| animace řízená skriptem se měřila jako „bez pohybu“ (fakticky prominutí) | b6905f59 |
| nástroj pohybu neuměl jméno v křivkách | 756557e3 |
| souhrn kola místa se směry spadl (`criteria` po směrech) | 0f135355 |
| karta: černobílý panel šedil terakotu, kontexty byly jen popisky | bf94bfdf |
| stránka pohybu `lang="cs"` na slovenském webu, kreslení při každé stránce | dda7fa1e |
| Stop hook `decision_card_complete` četl celý přepis (158 MB, přes 5 s) | dec58e71 |

## Matice oprav dílny 62-79

| Oprava | Výsledek | Kde / proč |
|---|---|---|
| 62 | ověřeno | pohyb k1-k2: brány `metrics` odmítly animaci PM 2,6 s se skrytým jménem a pustily webovou verzi 0,9 s (`.aid-ui/critic/rounds/pohyb/`, `metrics-pohyb-*.json`) |
| 63 | ověřeno | pohyb: přesah tahů, konec bez švu (`final_frame_diff_px` 0), pás snímků `aid-ui-tool.sh strip` |
| 64 | ověřeno | místní půlka: zasazené vady 13/13 přes všechny stránky × šířky (`.aid-o/work/evidence/P113/overeni-dilny.md`) |
| 65 | ověřeno | struktura k1-k4 hodnocena na stálé adrese kostry (`aid-ui-serve.sh skeleton`) |
| 66 | nevyzkoušeno | nový souhlas s podklady se v běhu neschvaloval (PM nebyl v běhu) |
| 67 | nevyzkoušeno | výhrada „čeká na klienta“ se nespustila - místa vrátily nálezy `fakt` dřív (D5) |
| 68 | nevyzkoušeno | Coufal má 5 starých stránek, rozsah obsahu nebyl otázkou |
| 69 | opraveno | karty směru: kontexty, inverze, černobíle (bf13108b, bf94bfdf) |
| 70 | ověřeno | logo `--supplied`, volba PM (`chosen_by: pm`), paměť klienta přes místa (`rounds/logo/`) |
| 71 | ověřeno | D5: sdělení a struktura vráceny nálezem `fakt` přes přijetí klienta (`verdict-*.json`) |
| 72 | ověřeno | sdělení k2-k4: srovnání s konkurencí jen interně, řádek pro právníka |
| 73 | ověřeno | sdělení k3-k4: otázky pro klienta v jedné tabulce, čistopis bez interních klíčů |
| 74 | ověřeno | struktura k2-k4: inventura po stránkách, otázky starého FAQ, adresy mimo menu (`inventura_presun` 6 → 8) |
| 75 | ověřeno | vzhled k1-k4: hlavička na 320/390 px, telefon jako tlačítko, menu na telefonu |
| 76 | opraveno | vzory přeneseny do pluginu (`references/local/vzory/`, krok 4) |
| 77 | ověřeno | role na Opusu (33 volání); jeden záskok Codex zaznamenán výše |
| 78 | opraveno | strop `--max-seconds`, kontrola prostředí, záznam odmítnutí obrazu (krok 9, ce09b96d) |
| 79 | nevyzkoušeno | Coufal nemá zákonné lhůty v textech |

## Co čeká na PM

- Logo: přijmout značku tak, jak je (pak se místo zapíše přes `--pm-choice`), nebo ji upravit (16 px řez s trojúhelníkem,
  poměr znaku a nápisu, čitelnost příběhu).
- Sdělení, struktura, vzhled: znovu otevřít jedním kolem nad opravenými podklady (`aid-ui-quality.py reopen`), nebo
  přijmout s výhradou.
- Upravený dokument o ambulanci `docs/content/product-context.navrh-p113.md` čeká na schválení (do té doby platí
  schválená verze, aby šla kontrola textů).
