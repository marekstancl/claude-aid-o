# Pilot P116: studio /aid-ui na webové aplikaci Copytrade GG (Trading F1)

Průběžná zpráva pilotu (P116 krok 8). Studio běží nad větví `ui/f1-studio` repa Tradingu (pracovní kopie
`/opt/eco/projects/trading/.aid-worktrees/ui-f1`); kód aplikace se nemění. Výsledky úloh jsou **ověření návrhu
(kostra)** - Trading UI ještě neexistuje; projít v kódu je podmínka plánu Tradingu ze zadání pilotu.

## Kola

### Kolo 0 (18. 10. 2026) - příprava, bez rolí
- Větev a pracovní kopie, stav studia, brand stránka, kontrola pokrytí (431/431).
- Otázky PM ve studiu: druh (doporučeno: webová aplikace v síti bez značky) a volby (doporučeno: nic navíc).
- Návrh modelu F1 `docs/design/screens.json` z `docs/plans/2026-10-12-zadani-ui-obsah.md` a roadmapy F1:
  8 obrazovek, 8 úloh, 54 řádků brány; kontrola modelu prošla. Kostra na stálé adrese jako návrh.
- Cena: jen práce agenta (žádné volání rolí). PM zvolil 1A (webová aplikace v síti, bez značky, nic navíc);
  vynechání sloganu, hledání a loga zapsané s důvodem.

### Kolo 1 (18. 10. 2026, 19:38-19:43) - místo struktura, první hodnocení
- Klient 5,8, odborník 4,9 (brána: obě ≥ 7,5); 21 nálezů (klient 10, odborník 11), nikdo nic nepřijal.
- Hlavní nálezy obou rolí shodně: chybí obrazovka Pozice a ruční zavření jedné pozice (zadání: „ručně zavřu pozici
  nebo všechny“); nejistý signál nejde Provést / Zahodit (jen „Vyřízeno“); potvrzení Paniky nejmenuje, co zavře,
  a fokus je na Potvrdit; lišta (režim, STOP, Panika) jen na Přehledu.
- Cena rolí 1,89 USD (3 volání Opus), čas 5 min. Nástroj ukázal 66,47 USD: 64,58 USD je celá stavba P116 v tomtéž
  sezení, připsaná jako práce agenta před kolem (nález postupu 2).

### Kolo 2 (18. 10. 2026, 20:54-21:01) - místo struktura po verzi 1 podle nového pravidla
- Verze 1 udělaná znovu od soupisu požadavků: 32 požadavků (zadání, roadmapa F1, obsah UI) se zdrojovým řádkem, 12
  obrazovek s lištou, 15 úloh, slovník, data se zdrojem a stářím, ukázky, mimo rozsah s důvodem; předběžná brána
  1089/1089 zelená; vlastní hodnocení 9 u všech 12 kritérií; 21 nálezů kola 1 zapsaných jako opravené.
- Klient 7,75 (prošel bránou), odborník 6,34 (neprošel: obnova 6, architektura 6); 18 nálezů.
- Vlastní hodnocení 9 bylo nadsazené: ukázková čísla téhož obchodu si odporovala (riziko 500 vs 7,2 USDT), hodnoty
  pojistek bez zdroje (páka, denní limit), stavy úloh nejdou v kostře vyvolat, pole nevynucuje meze, tlačítka
  potvrzení v kostře obecná, dostupnost akcí podle režimu chybí, Provést nekontroluje stáří a odchylku ceny.
- Cena: role 2,84 USD (3 volání Opus), práce agenta na verzi 1 a pravidle v pluginu 42,84 USD; čas: příprava verze 1
  77 min, kolo rolí 7 min.

### Kolo 3 (19. 10. 2026) - místo struktura po vynucení obsahu kódem (PM 1A)

- Do pluginu přibylo, co kolo 2 našlo jako slib bez pokrytí: pojmenované hodnoty se zdrojem (`values`, `{klíč}`),
  režimy s dostupností akcí (`modes`, `disabled_reason`; vypnuté tlačítko i odkaz), texty tlačítek potvrzení
  (`confirm_yes`, `confirm_no`, povinné), stavy úloh na zavolání (`?stav=<úloha>.<stav>`), meze polí s hláškou,
  hluboké odkazy (`query`), `aria-busy`, datové tabulky (`tables`); kostra kreslí všechna pole obrazovky.
- Předběžná brána 2079/2079 zelená (51 min); vlastní hodnocení 9 u všech 12 kritérií; 18 nálezů kola 2 zapsaných.
- Klient 8,15 (prošel), odborník 7,44 (neprošel o 0,06: model úloh 7, obnova 7, připravenost 7); 9 nálezů.
- Vlastní hodnocení bylo zase nadsazené, rozdíl menší (9 proti 8,2 / 7,4). Dva doklady oprav byly nepravdivé:
  Provést / Zahodit „u položky“ (kostra kreslí akce obrazovky pod seznamem, model neumí akci položky) a Telegram
  „odstraněn“ (zůstal ve třech textech). Příčina: oprava ověřená hledáním slova v modelu, ne pohledem do kostry.
- Nové věcné nálezy: rozvrh čtení Discordu je od 15. 10. po oknech podle kanálu (model má jedno okno), ruční
  zavření pozice nemá nejistý výsledek ani souběh s panikou, položka „SL odmítnut“ nemá akci, která ji vyřeší.
- Cena: role 3,11 USD (Opus), smyčka celkem 181,3 USD (agent i role, od vzniku studia); čas: kolo rolí 7 min,
  smyčka od začátku studia 1144 min (včetně stavby pluginu a čekání).

## Místa

| místo | kola | známka klienta | známka odborníka | stav | cena | čas |
|---|---|---|---|---|---|---|
| struktura | 3 | 8,15 | 7,44 | kolo 3: klient prošel, odborník ne (o 0,06) | 7,84 USD (role), smyčka 181,3 USD | 19 min rolí |

## Matice nálezů postupu

| # | stav | nález | cíl (soubor) | commit | ověřeno (místo, kolo) |
|---|---|---|---|---|---|
| 1 | opraveno | filtr úniku známek vyhodil ze zadání projektu řádky o jeho vlastních prazích („akceptační kritéria“, „práh jistoty“) | scripts/aid-ui-critic.py (LEAK jen na texty studia) | 0447c7b3 | - (ověří nové zmrazení: místo vzhled) |
| 2 | opraveno | cena kola připíše agentovi celé sezení od jeho začátku (i stavbu pluginu), ne práci na projektu | scripts/lib/aid_ui_costs.py (book_agent od vzniku studia) | 0447c7b3 | - |
| 3 | opraveno | potvrzovací dialog kostry dává fokus na Potvrdit: Enter hned provede nevratnou akci | scripts/lib/aid-ui-skeleton.py | 0447c7b3 | - |
| 4 | opraveno | kostra ukazuje výsledek úlohy staticky na cílové obrazovce: brána ověří text, ne že ho akce způsobila | scripts/lib/aid-ui-skeleton.py | 0447c7b3 | - |
| 5 | opraveno | model neumí lištu dostupnou na každé obrazovce (STOP, Panika): akce jen na jedné obrazovce | references/screens.schema.json + kostra | 0447c7b3 | - |
| 6 | opraveno | kostra ukazuje jen čtyři stavy obrazovky, ne stavy úlohy (chyba validace, oprávnění) u akce | scripts/lib/aid-ui-skeleton.py | 0447c7b3 | - |
| 7 | opraveno | výrobce dodal verzi 1 bez soupisu požadavků; kritik našel chybějící body zadání (PM: generické pravidlo) | aid-ui-quality.py self + round, aid-ui-verify.sh --precheck, SKILL.md, /opt/eco/CLAUDE.md | 0447c7b3, e0d2c463 | - |
| 8 | opraveno | model neuměl stopu požadavků, slovník, mimo rozsah, zdroj a stáří dat, popisky polí, ukázky, Zpět | screens.schema.json, aid-ui-screens.py, kostra | 88f6aee9, 092e799e | - |
| 9 | opraveno | lišta v kostře bez obsahu (jen tlačítka); chybový stav bez Zkusit znovu; změna stavu bez oznámení | scripts/lib/aid-ui-skeleton.py | 092e799e | - |
| 10 | opraveno | záznam opravy spadne na argumentu s rozpůleným znakem (UnicodeEncodeError) | scripts/aid-ui-quality.py (argumenty) | a45b30cc | - |
| 11 | opraveno | čísla ukázek si odporují, hodnoty pojistek bez zdroje | screens.schema.json `values`, aid-ui-screens.py, kostra | b1f16f9d | struktura, kolo 3 (duvera_v_data 9) |
| 12 | opraveno | potvrzení v kostře s obecnými tlačítky Potvrdit / Zrušit | `confirm_yes`, `confirm_no` povinné u nevratné akce | b1f16f9d | struktura, kolo 3 |
| 13 | opraveno | dostupnost akcí podle režimu jen větou; vypnutý odkaz šel kliknout | `modes`, `disabled_reason`, kostra | b1f16f9d, c055707a | struktura, kolo 3 |
| 14 | opraveno | stavy úloh v kostře nejdou vyvolat, pole nevynucuje meze | kostra `?stav=<úloha>.<stav>`, meze polí | b1f16f9d | struktura, kolo 3 |
| 15 | opraveno | detail bez id, filtr bez polí, Zkusit znovu zahodí id | `query`, pole obrazovky, Zkusit znovu | b1f16f9d, c055707a | struktura, kolo 3 |
| 16 | opraveno | graf bez datové tabulky | `tables` v modelu i kostře | 997962e9, 7545a4b5 | struktura, kolo 3 |
| 17 | otevřeno | model neumí akci jedné položky seznamu: Provést / Zahodit / Vyřídit jsou pod celým seznamem | screens.schema.json + kostra | - | - |
| 18 | otevřeno | vlastní kontrola ověřuje opravu slovem v modelu, ne v postavené kostře; doklady dvou oprav nepravdivé | aid-ui-quality.py fixed / self | - | - |
