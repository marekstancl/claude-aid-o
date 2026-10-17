# Společný rámec: místo rozhodnutí „vzhled“ (obě role)

Studio (AI nástroj „AID studio“) staví weby malých podniků a aplikace. Ve fázi „Vzhled a stavba“ předloží:
1. **tokeny vzhledu** (barvy s kontrastem, písma nadpisů a textu, mřížka, mezery, zaoblení) odvozené ze značky;
2. **tři směry vzhledu** – každý na úvodní stránce, stránce služby, portfoliu (nebo hlavní obrazovce a toku u aplikace)
   a na telefonu, se skutečnými texty a obrázky podniku; směry se liší principem kompozice, ne odstínem;
3. po výběru **hotové stránky** (vzhled, texty, obrázky, pohyb) v živé kostře na stálé adrese.

Hodnotí dvě nezávislé role, každá zvlášť a bez znalosti úvah studia i hodnocení druhé:
- **odborník** (vizuální a interakční designér) – síto před klientem: mřížka a zarovnání, **proporce a vyvážení
  kompozice** (opticky na středu, rovnoměrná vizuální váha, přirozené poměry, nic „nalepeného“ ani nesrovnaného),
  rytmus a mezery, typografie (hierarchie, délka řádku, čeština: diakritika, nezlomitelné mezery), barva a kontrast
  (WCAG 2.2 AA), přístupnost, telefon, obrázky (kvalita, výřez, poměr), pohyb (účel, délka, omezení pohybu),
  originalita proti šabloně (rubrika obecnosti studia), soulad se značkou a se sdělením (teze);
- **klient** (majitel podniku, ne designér) – posuzuje, jestli se ve vzhledu pozná, jestli působí důvěryhodně pro
  jeho zákazníky, jestli je čitelný a jestli by takový web chtěl ukázat; fakta, která nezná, neschvaluje.

Zadavatel (PM studia) má výslovný vkus, který měřítko odborníka MUSÍ umět posoudit: vyvážené, proporční kompozice –
prvky opticky na středu, přirozené proporce (písmo ani tvary ne zploštělé), rovnoměrná vizuální váha, zarovnané texty.

Typy: web místní služby, B2B služba s portfoliem, webová aplikace (veřejná i interní; u aplikace knihovna součástí
a stavy místo „směrů úvodní obrazovky“). Měřítko obecné, ne pro jeden obor.

Napiš MĚŘÍTKO své role jako YAML (jen YAML):
```yaml
role: <tech|owner>
place: vzhled
applies_to: [web_local, b2b_portfolio, webapp, webapp_internal]
persona: {who: "...", wants: "...", rules: ["..."]}
criteria:
  - id: <snake_case>
    name: "..."
    weight: <celé číslo; součet 100>
    anchors: {4: "...", 6: "...", 8: "...", 10: "..."}
    sources: ["..."]
```
Požadavky: 5–8 kritérií; kotvy rozhodnutelné ze snímků (počítač 1280–1440 px, telefon 390 px), kódu stránky
a měření (kontrast, velikosti, odstupy); hodnotitel smí stránky otevřít v Playwrightu a měřit. Kotva 8 = dobrá
agentura, 10 = špička. Opři se o literaturu a praxi (např. Josef Müller-Brockmann „Grid Systems“, Robert
Bringhurst „The Elements of Typographic Style“, Ellen Lupton „Thinking with Type“, Gestalt principy, Refactoring UI
(Wathan, Schoger), Lindgaard a kol. 2006 o prvním dojmu, Stanford Web Credibility / B. J. Fogg, NN/g o vizuální
hierarchii a fotkách, WCAG 2.2, Val Head o pohybu) a o rubriku obecnosti studia (přiložena níže). Zdroje ověř na webu.
Hranice přijetí neuváděj – zapiš je do `web-local.<role>.vzhled.gates.yaml` (`gates`, `weighted_min`). Čeština.

Rubrika obecnosti studia (vyřadit při jednom tvrdém nebo dvou měkkých): tvrdé – SaaS sada stejných zaoblených karet
se stínem a gradientem; šablonový rám (ALL-CAPS nadpisek nad každým nadpisem, řetězce A · B · C, šipky na tlačítkách);
hero „velké číslo + popisek + gradient“. Měkké – krémové pozadí + patkové písmo + terakota; skoro černé pozadí +
kyselý akcent; vlasové linky a husté novinové sloupce; značky 01/02/03 na něčem, co není posloupnost; stejné
vyjetí na každé sekci; jedno systémové písmo nebo Inter všude.
