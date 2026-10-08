# P014 - hlášení z e-mailu, oznámení a měření (společné zadání)

Stav: **zadání pro experiment**, 7. 10. 2026. Tentýž text dostanou všechna tři
ramena srovnávacího experimentu (pravidla experimentu: `/opt/eco/CLAUDE.md`,
sekce „Srovnávací experiment: vyplatí se AID?").

## 1. Co PM chce

Doslova, 7. 10. 2026:

> „potřebuju aby asistent byl pořád vyvýjen tak aby byl použitelnej i jinde, čili
> sem ho pak mohl zabalit a mohl ho využít v jiné aplikaci nebo někdo jiný"
>
> „mě ale nevadí jedno freelo! tam mám přístum jen a pouze já - vývoj!! spíše aby
> freelo a další nástroje byly jako connector, někdo jiný kdo si veme asistena
> celýho nemusí chtít používat freelo tak si dodělá svůj konektor"
>
> „oznámení - to že uděláme naši stranu ok - ale musí vzniknout i zadání pro WAN!!"
>
> „nechci to moc komplikovat tut P014 ale vesměs to architektonicky táhnout
> správným směrem"

Rozhodnutí PM k rozsahu: duplicita (rozpoznání už nahlášeného) **vypadla**;
z oznámení se dělá **naše půlka** plus zadání pro WAN; přenositelnost se řeší
variantou A („pojmenovat porty a jeden doplnit"), ne obecnou konektorovou vrstvou.

Jak to chápu: P014 dodělá zpětnou vazbu pro lidi, kteří hlásí mimo Lisu, dá
hlášení cestu ven z widgetu a začne měřit, kolik z nich mohl asistent vyřešit
sám - a přitom nikde nepřidá závislost na Freelu, kterou by druhý zákazník musel
rozplétat.

## 2. Změřený výchozí stav (ověřeno v kódu a v datech 7. 10. 2026)

- **P013 je hotové a v hlavní větvi**: `asistent/api/routery/hlaseni.py`
  (`POST /api/hlaseni`, `/api/hlaseni/detail`, `/api/hlaseni/doplneni`),
  migrace `asistent/api/migrace/014_hlaseni.sql` (`hlaseni_stav`,
  `hlaseni_udalost`), čtečka `bin/asistent-hlaseni-sync.py`, záložka ve widgetu
  `asistent/widget/app/Hlaseni.tsx`, konfigurace `hlaseni` v `apps.yaml`
  (`vidi_vse_role`, `perioda_min`, `okno_doplneni_dnu`, mapa `sloupce`).
- **E-mail uživatele se nikde neukládá.** Vstupenka ho nese
  (`asistent/api/token.py`), ale použije se jen na allowlist; `sessions` sloupec
  nemá a profil ho vědomě vylučuje (`asistent/api/profil.py`: „E-mail a UUID do
  profilu nepatří"). Bez něj nejde ani párování, ani jméno s e-mailem v popisu úkolu.
- **Freelo není v asistentovi.** Volá ho jen brána (`bin/freelo_rest.py`,
  `bin/telegram-gateway.py`) pod účtem `agent-runner`; asistent předává hlášení
  schránkou `runtime/asistent-intake` (povolené druhy `ticket` a `hlaseni_komentar`).
- **Události pro widget existují** (`asistent/api/routery/events.py`, tabulka
  `events` s `precteno`, druh `hlaseni_novinka` od P013); widget zná uzavřený
  výčet druhů (`asistent/widget/app/api.ts`, `ZNAME_DRUHY`).
- **Můstek k hostiteli** ve widgetu posílá typ a identifikátor, cestu skládá
  hostitel (`asistent/widget/app/most.ts`).
- **Jedno Freelo je v pořádku** (PM: přístup má jen on, je to vývoj). Oddělení
  cílových seznamů per zákazník tedy NENÍ předmětem P014.

## 3. Co udělat

Pořadí je doporučené, ne závazné; co na sobě závisí, je napsané u položky.

**(1) E-mail u člověka a jméno v úkolu.**
Při ověření vstupenky se uloží dvojice `app_id` + e-mail → `subject_id` (jen to, co
už ve vstupence je; při každém přihlášení se přepíše). Popis úkolu ve Freelu pak
u „Kdo" nese jméno, e-mail a lidskou roli - dnes jen roli.

**(2) Hlášení, která vznikla mimo Lisu.** Závisí na (1).
Podpora vyplní u ručně založeného úkolu pole „nahlásil (e-mail)". Čtečka projde
úkoly cílového seznamu, vybere ty, které v přehledu nejsou, podle e-mailu najde
člověka a založí jim záznam s příznakem, že komunikace běží e-mailem. V detailu
takového hlášení stojí věta „Na tohle hlášení odpovídáme e-mailem" a nejsou u něj
tlačítka Doplnit ani Otevřít konverzaci.

**(3) Oznámení - naše půlka.**
Když se zveřejní text od podpory, vznikne kromě dnešní události i **oznámení pro
hostitele**: posílá se můstkem jako typ události a identifikátor, bez obsahu
hlášení. Co s ním hostitel udělá (push, e-mail, nic), není věc asistenta.
Součástí je **zadání pro WAN** (jejich půlka: přijmout událost z můstku, převést
naši identitu na uživatele WANu a poslat Web Push) - napsané v jejich repozitáři
jako samostatný dokument, stejně jako W8 až W12.

**(4) Měření „mohl to asistent vyřešit sám".**
Podpora označí hlášení štítkem. Výpis vrací počet hlášení za období, kolik z nich
štítek má, a **kolik se nedalo posoudit** - podíl má pojmenovaný jmenovatel, není
to známka. K tomu vzorek konverzací, kde hlášení vůbec nevzniklo, aby se neměřilo
jen to, co selhalo.

**(5) Přenositelnost (varianta A, PM 7. 10.).**
- Doručení hlášení dostane **pojmenované rozhraní** (založ úkol, přečti stav, přidej
  komentář, přečti štítky) a Freelo bude jeho první a jediná implementace. Nic
  jiného v asistentovi ani v bráně o Freelu vědět nemusí.
- Pole, štítky a sloupce, které dnes drží kód nebo prostředí, jdou do konfigurace
  aplikace vedle `hlaseni`.
- Do Docusaurusu přibude stránka **„čtyři porty asistenta"**: data z hostitelské
  aplikace, nástroje přes MCP s připnutým seznamem, můstek k hostiteli, doručení
  hlášení. Je to zápis toho, co platí, aby to příští člověk nemusel luštit z kódu.

**Co do P014 nepatří:** rozpoznání duplicity (PM 7. 10. vyňal), oddělení cílových
seznamů ve Freelu per zákazník, implementace Web Pushe na straně WANu, obecná
konektorová vrstva („registr konektorů"), změna priority nebo zavírání hlášení
uživatelem.

## 4. Kde co je

| Co | Kde |
|---|---|
| API hlášení | `asistent/api/routery/hlaseni.py` |
| schéma zrcadla a osy | `asistent/api/migrace/014_hlaseni.sql` |
| čtečka stavu z Freela | `bin/asistent-hlaseni-sync.py` |
| klient Freela | `bin/freelo_rest.py` |
| brána, schránka, předávky | `bin/telegram-gateway.py` |
| vstupenka a relace | `asistent/api/token.py`, `asistent/api/migrace/001_schema.sql` |
| profil uživatele | `asistent/api/profil.py` |
| události a odznak | `asistent/api/routery/events.py`, `asistent/widget/app/api.ts` |
| můstek k hostiteli | `asistent/widget/app/most.ts` |
| záložka Hlášení | `asistent/widget/app/Hlaseni.tsx` |
| konfigurace aplikací | `asistent/config/apps.yaml` |
| nasazení a soupis kopií | `deploy.sh`, `deploy-manifest.txt`, `tests/fixtures/deploy-inventar.txt` |
| počty testů | `CLAUDE.md` (tabulka sad i souhrnná sedmička), `/opt/eco/docs/docs/agents/platforma/testy.md` |
| dokumentace asistenta | `/opt/eco/docs/docs/agents/asistent/` |
| zadání pro WAN | `/opt/eco/projects/wan/docs/plans/` |

## 5. Pravidla práce

Platí `/opt/eco/CLAUDE.md` (styl zpráv, vývoj mimo AID) a
`/opt/eco/projects/agents/CLAUDE.md` (pravidla platformy). Z nich to, co pro tuhle
práci platí nejvíc:

- **Měř, nehádej.** Jméno funkce, cesta ani řádek se neopisuje z paměti.
- **Hranice jsou produkt:** nástroje připnuté a ověřené otiskem, tajemství per
  aplikace, schránka mezi službou a bránou je výčet povolených druhů.
- **Konfigurace dodává data, nikdy věty pro uživatele** - ty jsou v kódu.
- **Dokumentace je součást změny**, ne úklid po ní; počty testů se přeměří.
- **Experiment:** vlastní pracovní kopie, **nikdo nemerguje a nikdo nenasazuje**,
  vlastní testovací databáze, žádné volání Freela mimo testovací seznam.

## 6. Hotovo, když

1. Přihlášení uloží dvojici e-mail → člověk a popis nového úkolu ve Freelu nese jméno, e-mail i roli.
2. Ruční úkol s e-mailem přihlášeného člověka se objeví v jeho přehledu označený jako e-mailový, bez tlačítek Doplnit a Otevřít konverzaci.
3. Neznámý e-mail nespáruje nic a je to vidět v čidlech, ne jen v logu.
4. Zveřejnění textu od podpory pošle oznámení můstkem; bez hostitelovy půlky zůstane odznak a nic nespadne.
5. Zadání pro WAN existuje v jejich repozitáři a popisuje tvar události i převod identity.
6. Výpis měření vrací počet hlášení, kolik má štítek a kolik se nedalo posoudit.
7. Doručení hlášení jde přes pojmenované rozhraní; mimo jeho implementaci se slovo Freelo v asistentovi nevyskytuje.
8. Stránka „čtyři porty asistenta" je v Docusaurusu a odkazuje na ni dokumentace asistenta.
9. Testy: nové případy mají domovskou sadu, patro podle ceny, a počty v `CLAUDE.md` i v Docusaurusu sedí se skutečným sběrem.
10. Nic z toho se nenasazovalo a nemergovalo - výsledek zůstává v pracovní kopii.
