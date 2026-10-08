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
přenositelnost se řeší variantou A („pojmenovat porty a jeden doplnit"), ne
obecnou konektorovou vrstvou. **Po třetím kole revize plánu PM rozsah ještě
zúžil** (7. 10. 2026): přestavba zrcadla hlášení, párování úkolů z e-mailu
a oznámení jdou do navazujícího plánu P015, protože přestavba běžícího schématu
táhne za sebou patnáct dalších míst a nepatří do jednoho balíku s novou prací.

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

**(1) Doručení hlášení za pojmenovaným rozhraním.**
Dnes volá Freelo přímo brána, čtečka i testovací scénář. Vznikne rozhraní se
sedmi úkony (založ úkol, detail, komentáře, komentář, nastav štítky, výpis úkolů
seznamu, přesun) a Freelo bude jeho jediná implementace; vybírá se podle
konfigurace aplikace. Mimo rozhraní smí o Freelu vědět jen nahrávání příloh,
čtení přihlašovacích údajů, výjimky a konstanty - a ten výčet je úplný a měří ho
test. Kdo si vezme asistenta a Freelo nepoužívá, napíše vlastní implementaci.

**(2) E-mail u člověka a jméno v úkolu.**
Při ověření vstupenky se uloží dvojice e-mail → člověk a e-mail i do relace.
Popis úkolu pak u „Kdo" nese jméno, e-mail a lidskou roli - dnes jen jméno
a roli, takže podpora neví, komu odpovědět.

**(3) Měření „mohl to asistent vyřešit sám".**
Podpora označí hlášení štítkem. Výpis vrací počet hlášení za období, kolik z nich
štítek má a **kolik se nedalo posoudit** - podíl má pojmenovaný jmenovatel, není
to známka. K tomu vzorek konverzací, kde hlášení vůbec nevzniklo.

**(4) Čtyři porty asistenta v dokumentaci.**
Stránka v Docusaurusu: data hostitelské aplikace, nástroje přes MCP s připnutým
seznamem, můstek k hostiteli, doručení hlášení. U každého portu co jím chodí, co
drží hranici a co musí dodat cizí hostitel.

**(5) Ověření bez nasazení.**
Celá cesta (přihlášení → hlášení → běh čtečky → výpis měření) musí projít testem
proti atrapě rozhraní, nad testovací databází. Žádné nasazení, žádné skutečné
Freelo.

**Co do tohohle zadání nepatří** (jde do P015): přestavba zrcadla, aby uneslo
hlášení bez ticketu; párování úkolů založených ve Freelu ručně podle e-mailu;
oznámení ze služby hostiteli a zadání pro WAN. Dál nepatří: rozpoznání duplicity,
dělení cílových seznamů ve Freelu podle zákazníka, obecná konektorová vrstva.

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

1. Mimo implementaci rozhraní a vyjmenované výjimky se klient Freela v kódu nevolá; měří to test, který prochází zdroje.
2. Zakládání úkolu, čtečka i testovací scénář jdou přes rozhraní; neznámá hodnota v konfiguraci skončí chybou při startu, ne tichým přechodem na Freelo.
3. Po přihlášení existuje dvojice e-mail → člověk a e-mail je i u relace.
4. Popis nového úkolu nese jméno, e-mail i roli; e-mail poslaný v těle požadavku se ignoruje.
5. Měření vypíše celkem, se štítkem a neposouzeno s pojmenovaným jmenovatelem; při nečitelných štítcích u víc než poloviny skončí nenulovým kódem.
6. Stránka „čtyři porty asistenta" je v Docusaurusu a odkazuje na ni index i runbook pro vložení do projektu.
7. Celá cesta projde testem proti atrapě rozhraní, bez nasazení a bez skutečného Freela.
8. Testy mají domovskou sadu a patro podle ceny; počty v `CLAUDE.md` (tabulka i souhrnná sedmička) a v Docusaurusu sedí se skutečným sběrem.
9. Nic se nenasazovalo ani nemergovalo - výsledek zůstává v pracovní kopii.
