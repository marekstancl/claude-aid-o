# Postup: Podklady a sdělení (krok 1p + 1v studia)

Ověřeno v dílně 14. 10. 2026 na zkušebním podniku (web místní služby, redesign): 7 kol, test naslepo proti dnešnímu
1p/1v, obě role prošly branou v kole 7 (odborník 7,50, klient 8,85). Záznam dílny je mimo plugin.
Typy B2B s portfoliem a webová aplikace jsou prověřené jen na papíře (oddíl „Podle typu“) – ověřit při Coufalovi.

**Nahrazuje:** `steps/1p-sources.md` bod 5 (osnova dokumentu) a ve `steps/1v-vision.md` generování sloganů.
**Platí dál:** z 1p řádky `Stav:` a `Zdroje:`, registr faktů, stažení podkladů a filtr „NESDÍLET“ (podrobně níže).

## Vztah ke kroku 1p/1v studia (doplněno F7, neověřeno)
Tato vrstva **nahrazuje** v `steps/1p-sources.md` bod 5 (osnova dokumentu: platí 9 českých oddílů níže) a ve
`steps/1v-vision.md` generování sloganů (platí 5 směrů níže; navázání na dřívější motto je jen otázka pro klienta,
ne povinnost). **Dál platí** z 1p: řádky `Stav:` a `Zdroje:` u každého oddílu, registr faktů, stažení podkladů
(`aid-ui-sources.py`), filtr „NESDÍLET“. Schvalování seznamu podkladů a průzkumu na internetu (1p body 1–4, 6–8,
otázky `sources`, `online@…`, `product_context` pro PM) v běhu s rolemi **nahrazuje místo rozhodnutí „sdělení“**:
studio podklady i průzkum udělá samo a obě role je posoudí. Stažení starého webu: stačí stránky; obrázky až ve vzhledu.
Zdroj pravdy otázek pro klienta je **jeden soubor** (`otazky-klientovi.md`) se stálými čísly; oddíl 9 a čistopis z něj
jen čerpají (čistopis ukáže nejvýš 8 bodů s největším dopadem + odkaz na celý seznam). Nové body na konec, čísla se
nemění; pořadí podle dopadu je pohled, ne číslování. Důkaz F7: deník body 2, 3, 10, 11, 14.

## Výstup kroku
1. **Dokument o podniku** (`product-context.md`), oddíly s českými nadpisy pro klienta:
   1. Proč vy a ne jiný – positioning jednou větou + složky (April Dunford: alternativy, odlišnosti, hodnota, pro koho,
      za co se podnik vydává) + „Co neříkat, protože to říká každý“ (výstup průzkumu konkurence);
   2. Teze (4–6);
   3. Kdo přichází a s čím – pro každé publikum spouštěč, úkol, obavy a co ho drží jinde (Moesta: push, pull, úzkost, zvyk);
      u B2B a aplikací zvlášť uživatel a ten, kdo vybírá a platí;
   4. Jak mluví zákazníci – doslovné citace se zdrojem a datem + slovník zákazníka proti slovníku oboru;
   5. Námitky a odpovědi – každá odpověď opřená o fakt, nebo odkaz na Ke kontrole;
   6. Nabídka (jak ji hledá zákazník); 7. Důkazy; 8. Tón s příklady „řekneme / neřekneme“;
   9. Ke kontrole – seřazeno podle dopadu, každý řádek s návrhem a s tím, kterou tezi nebo slogan odpověď mění.
2. **Pět sloganů z pěti různých směrů:** doložený rozsah nebo důkaz, místo nebo zákazník, obava zákazníka, způsob
   práce, nabídka. Každý s „čím se liší“ (s konkrétním konkurentem) a rizikem. Ne pět variací jednoho vzorce.
3. **Čistopis pro klienta na jednu stranu** (bez kódů zdrojů a stavů): hlavní slogan, kdo jste jednou větou, čím se
   lišíte, o čem bude web, další slogany, otázky pro klienta. Podrobná verze jde jako příloha.

## Postup
1. **Podklady:** starý web (texty, obrázky, logo, snímky), dokumenty klienta; README označené „NESDÍLET“ je interní
   a do dokumentu nejde (oprava 22).
2. **Hlas zákazníka – povinně** (rozhodnutí PM 3a). Zdroje podle typu (oddíl níže); vždy datum a odkaz. Recenze
   z WebFetch bývají zkrácené – doslovná je jen věta, kterou nástroj vrátil celou; zbytek je parafráze a tak se značí.
   Když hlas zákazníka chybí, dokument to přizná a dá klientovi 3–5 otázek (kotva 6 měřítka).
3. **Průzkum konkurence – povinně, před positioningem.** 8–12 skutečných alternativ v okolí nebo v kategorii (u aplikace
   i stávající postup: tabulka, e-mail, nic nedělat). U každé: co nabízí, hlavní tvrzení doslova, důkazy, tón, zdroj.
   Syntéza: (a) fráze oboru, které říká každý, (b) kandidáti na odlišení s důkazem a silou, (c) co zákazníci konkurence
   chválí a na co si stěžují. Bez průzkumu nejde poctivě udělat test dosazení (dílna: kolo 1 → 2).
4. **Pravidla tvrzení** (nálezy kol 2–5):
   - srovnání s konkurencí je vždy **odhad** s datem průzkumu; „jediný“ a „nikdo jiný“ se nepíše, jen „v průzkumu
     okolí to nikdo další neuvádí“;
   - reference = hotová zakázka; služba z ceníku není reference;
   - zeměpis referencí ověřit (obec mimo region nesmí dokládat místní odlišení);
   - citace v uvozovkách jen doslova; parafráze se značí;
   - síla věty = síla důkazu (jedna recenze = „zákazník uvádí“).
   - (doplněno F7, neověřeno) tvrzení o konkurenci do textů pro klienta (čistopis, web) **nejdou** – zůstávají
     v podrobné verzi jako odhad s datem; klient je v F7 odmítl podepsat;
   - (doplněno F7, neověřeno) odborné pojmy a výklad předpisů podle platného znění (předpis v platném znění); pojmy ze starého webu zkontrolovat, výklad předpisu je otázka pro klienta.
5. **Positioning a teze:** začíná hlavní prací klienta jeho slovy (klient vrátil verzi, kde byla odsunutá); odlišení
   stojí na tom, co klient doloží sám, ne na tom, co konkurence neříká. Teze = jedna myšlenka, opřená o fakt,
   s napětím; fráze oboru jen s konkrétním důkazem (ukázka práce, zakázka).
6. **Slogany** podle bodu 2 výstupu; test dosazení s nejbližšími konkrétními konkurenty z průzkumu.
7. **Místo rozhodnutí „sdělení“:** odborník a klient podle `critic/web-local.{tech,owner}.sdeleni.yaml`, brány zná
   jen kód; kolo `aid-ui-quality.py round --place sdeleni`, rozhodnutí `aid-ui-critic.py place-verdict`. Od druhého kola oba s pamětí podle `critic/role-briefs/pamet-hodnotitele.md`. Studio dostává jen nálezy
   a cestu k 10. Klient fakta, která nezná, neschvaluje – vrací je Ke kontrole.
8. Po schválení: čistopis pro klienta; teze jdou jako vstup do loga (`logo-postup.md`), struktury a textů.

## Doplněno po opakovaném běhu (15. 10. 2026, nový agent jen podle postupu)
Opakovaný běh bez paměti dílny: 1. kolo odborník 6,55 (původně 6,10), klient 6,95 (původně 6,45); brána nepadla na
přesnosti a sloganech. Pravidla, která chyběla:
- **Test dosazení = je věta po dosazení konkurenta stále PRAVDIVÁ?** Ne „ukazuje to konkurent na webu?“. „Přes 120
  projektů“ je pravdivé i pro konkurenta s 300 projekty → zaměnitelné. Odlišený slogan nese vlastnost, kterou konkurent
  nemá (např. dohledatelnost zakázek v okolí), ne číslo nebo rozsah, který má i on.
- **Údaj z cizího zdroje nebo ze starého webu je pro klienta „Ke kontrole“**, i když je doložený: hodnocení a citace
  z katalogů, kontakty, počty, roky zakázek. V čistopisu se uvádí jako otázka, ne jako hotová věc.
- **Žádná zobecnění bez doložení** („každý rok“, „nikdo si vás nepředává“, „stejná péče“) – co dělají spolupracovníci
  (navazující odborné profese), se nesmí zamlčet větou o jednom člověku.
- **Hlavní důraz klienta zůstává, i když je to fráze oboru** (u zkušebního podniku jeho hlavní řemeslná přednost): nevyřazuje
  se, doloží se konkrétním příkladem (ukázka práce, zakázka). Klient se jinak „nepozná“.
- **Jeden seznam otázek pro klienta** – čistopis a Ke kontrole mají stejné body ve stejném pořadí.
- **Typ podniku:** živnost nebo kancelář s portfoliem zakázek a bez ceníku (projektant, architekt, řemeslník na zakázku)
  se řídí sloupcem „B2B s portfoliem“, i když zákazníci jsou soukromé osoby.

## Bez hlasu zákazníka a bez případové zakázky (doplněno F7, neověřeno)
Typicky B2B s portfoliem nebo sólo podnik s tenkými podklady (F7: 3 viditelné recenze z 5, portfolio jen „obec – druh
stavby“, bez zadání a výsledku). Postup:
1. Přiznat to v dokumentu (oddíl 4 a 7) a nevymýšlet náhradu; průměr hodnocení, které nejde přečíst celé, uvést jako
   odhad Ke kontrole.
2. **Hned v kole 1** dát klientovi dvě konkrétní cesty doplnění: (a) **20minutový telefonát** – studio připraví 5 otázek
   na jednu zakázku zadání → řešení → výsledek a 3 otázky „co o vás říkají zákazníci“; (b) kontakt na 3–5 zákazníků
   (s jejich souhlasem) na krátký rozhovor. U B2B i reference a e-maily klientů.
3. Do té doby: odlišení stavět na **doložitelné schopnosti** (rozsah, skladba a dohledatelnost zakázek z inventury),
   ne na tom, co konkurence neuvádí; test dosazení posuzuje **pravdivost** pro konkurenta – nelze-li ji zjistit,
   je slogan „částečně zaměnitelný“ a tak se uvede.
4. Když podklady nedají aspoň 3 odlišené slogany, studio to napíše poctivě (kolik a proč) a místo rozhodnutí končí
   stavem **„schváleno s výhradou – čeká na klienta (KK …)“**, ne dalším kolem přepisování (F7: dvě kola, brána
   odborníka 7,3 < 7,5 jen kvůli chybějícímu důkazu zákazníků). Brána to rozhoduje sama (D1, P113): drží-li ji jen
   chybějící vstup klienta (`studio_score` + `to_ten.client`), místo končí `accepted_with_reservation`.

## Podle typu
| | místní služba | B2B s portfoliem | webová aplikace (veřejná) | interní aplikace |
|---|---|---|---|---|
| Hlas zákazníka | recenze (Firmy.cz, Google), diskuze v oboru, poptávky | reference a e-maily klientů, zadání zakázek, LinkedIn; při 2–5 klientech 3–5 otázek pro rozhovor | recenze aplikací, tikety, rozhovory, fóra | tikety, rozhovory s uživateli, stávající postup |
| Konkurence | projektanti/řemeslníci v dojezdu, katalog, svépomoc | podobná studia v oboru a regionu, in-house tým | jiné nástroje + tabulka/e-mail/nic | jen stávající postup |
| Publika | zákazník; obec/firma zvlášť | uživatel × kdo vybírá a platí | uživatel × kupující | uživatelé podle role |
| Slogany | 5 směrů | 5 směrů | 5 směrů | bez sloganu (váha se rozdělí) |
| Důkaz odlišení | zakázky v okolí | zakázka zadání → řešení → výsledek | funkce + výsledek uživatele | úspora proti stávajícímu postupu |

Na papíře: B2B s portfoliem – hlas zákazníka z referencí a zadání, konkurence = studia v regionu; aplikace –
konkurence = stávající postup a jiné nástroje. Obojí v měřítku už je (persona rules), postup to výše
pojmenovává.
