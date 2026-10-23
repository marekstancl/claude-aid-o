# Společný rámec: webová aplikace (typ `webapp`, P116; obě role)

Studio (AI nástroj „AID studio“) navrhuje **webové aplikace**: nástroje, ve kterých lidé dělají každodenní práci
(objednávky, sklad, schvalování, obchodování, evidence) - interní (síť firmy, LAN, jeden nebo pár uživatelů) i veřejné
za přihlášením. Ne prezentační weby: aplikace se nehodnotí podle toho, jestli prodává, ale jestli v ní člověk
**dokončí svou práci správně, rychle a bez ztráty dat, i když se něco pokazí**, a jestli věří tomu, co vidí (čísla,
stavy, peníze).

Co studio u aplikace předkládá na třech místech rozhodnutí:
1. **struktura (obrazovky a úlohy)** - model `screens.json`: obrazovky (účel, akce s cílem a druhem navigace /
   odeslání / nevratná akce s potvrzením, čtyři stavy prázdno / načítání / chyba / naplněno) a úlohy uživatelů
   (role, kroky, ověřitelný výsledek „hotovo, když…“, sedm stavů standardu: běžná cesta, chyba validace, prázdno,
   načítání, selhání, oprávnění, obnova po přerušení; stav, který nenastane, je napsaný „nenastává, protože …“),
   cesty selhání (kde selže, vstup zůstane, akce obnovy) a u existující aplikace náhradu každé dnešní úlohy;
   k tomu **proklikávací kostru** na stálé adrese (navigace, obrazovky s přepínačem stavů `?stav=`, akce vedou
   na cílové obrazovky, nevratné akce přes potvrzení) a výsledky automatických testů úloh na ní;
2. **vzhled** - tři směry vzhledu nad kostrou aplikace: hlavní obrazovka, obrazovka úlohy s formulářem nebo tabulkou
   a stavy (chyba, prázdno, načítání), na počítači i telefonu; knihovna součástí (tlačítka, pole, tabulky, hlášky)
   místo „úvodní stránky“;
3. **hotová aplikace** (místo `web`) - postavená aplikace (nebo její ověřovací stavba) na stálé adrese, výsledky brány
   studia: úlohy doběhly k výsledku (`app_flows`), každá obrazovka ve všech stavech (`app_states`), úloha jen
   klávesnicí (`keyboard_flows`), vnucená chyba neztratí vstup a cesta dál existuje (`task_recovery`), přístupnost
   (axe), přetékání, dotykové cíle; u existující aplikace srovnání s dnešními úlohami.

Hodnotí dvě nezávislé role, každá zvlášť, bez znalosti úvah studia i hodnocení druhé, s pamětí mezi koly
(`pamet-hodnotitele.md`):
- **odborník** - UX a interakční designér aplikací a technik kvality (úlohy a stavy, chybové stavy, přístupnost,
  klávesnice, výkon, data);
- **klient** - **vlastník produktu a klíčový uživatel** aplikace: člověk, který v ní bude každý den pracovat a za ni
  odpovídá. Studio ho postaví z kódu a zadání projektu (co aplikace dělá, pro koho, jaké úlohy, jaká data). Klient
  **neschvaluje** úlohy za PM (to dělá skutečný vlastník produktu ve studiu); jeho hodnocení je podklad.

Co chce zadavatel (PM studia): aplikaci, které uživatel věří u peněz a dat - úloha jde dokončit, žádný stav není
prázdná stránka ani nekonečné kolečko, chyba nikdy nesmaže rozdělanou práci, obrazovky jsou vidět a proklikat
hned od struktury, a výsledek se dá předat k naprogramování bez domýšlení.

Ekosystémové standardy, o které se měřítka opírají (kopie v pluginu): Úlohy a stavy webové aplikace UA-1..UA-11
(mapa úloh se sedmi stavy, chyba validace u pole a data zůstanou, prázdno s prvním krokem, načítání s vysvětlením
a zablokovanou akcí, selhání s „Zkusit znovu“, oprávnění s důvodem a koho požádat, obnova rozdělané práce,
hluboké odkazy, Zpět, hromadné akce, grafy s přístupnou náhradou); Design systém aplikací (komponenty, stavy polí,
fokus a klávesnice, dotykové cíle 44 px, kontrola před nasazením); WCAG 2.2 AA.

Tvar výstupu: každé měřítko jako YAML přesně v tomto tvaru (jen YAML):
```yaml
role: <owner|tech>
place: <struktura|vzhled|web>
applies_to: [webapp]
persona: {who: "...", wants: "...", rules: ["..."]}
criteria:
  - id: <ascii snake_case>
    name: "..."
    weight: <celé číslo; součet vah měřítka = 100>
    anchors: {4: "...", 6: "...", 8: "...", 10: "..."}
    sources: ["autor, název, rok, adresa: co z něj kotva bere"]
```
a ke každému měřítku soubor bran (zná je jen kód, role je nevidí):
```yaml
role: <owner|tech>
place: <struktura|vzhled|web>
gates:
  - {criterion: <id kritéria téhož měřítka>, min: <číslo>, why: "proč právě tady, lidsky"}
weighted_min: <číslo>
# jen u place web navíc:
audit: {median_min: 8.5, any_min: 8.0, criterion_median_min: 7.0}
```
Požadavky:
- 5-7 kritérií na měřítko; kotvy rozhodnutelné z toho, co role dostane (model, kostra, snímky, výsledky brány,
  kód aplikace u hotové aplikace), nikdy z pocitu. Mezi kotvami (5, 7, 9) = nižší celá a část vyšší; 1-3 = ani 4.
- Kotva 8 = co by předložil dobrý tým produktového designu; 10 = špička oboru (nástroje, kterým lidé věří u peněz).
- Slušná funkční aplikace bez ošetřených stavů a obnovy NESMÍ dostat 8 v kritériích o úlohách a stavech.
- Co může dodat jen klient (skutečná data, přístupy, účty, podklady), není vada studia - patří do „readiness“.
- Žádné vymyšlené údaje o podniku ani o datech: tvrzení nebo číslo bez zdroje je vada.
- Brány: na místech struktura a vzhled `weighted_min` kolem 7,5 a minima kritérií 6-7 tam, kde je chyba nevratná
  (ztráta dat, nedokončitelná úloha, nevratná akce bez potvrzení) přísněji; u hotové aplikace `weighted_min` 8,5
  a žádné kritérium pod 7 (rozhodnutí PM 13. 10. 2026 pro hotový web).
- Jazyk: čeština. Obecné pro typ `webapp`, ne pro jeden obor ani jeden projekt.
