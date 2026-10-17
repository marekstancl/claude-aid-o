# Společný rámec: místo rozhodnutí „sdělení“ (obě role)

Studio (AI nástroj „AID studio“) staví weby malých podniků a aplikace. Ve fázi „Podklady a sdělení“ přečte podklady
(starý web, dokumenty od klienta, veřejné recenze a zmínky) a předloží klientovi ke schválení:
1. **dokument o podniku** – co dělá, pro koho (publika a jejich úkoly a obavy), s čím ho zákazník srovnává, čím je jiný
   a proč tomu věřit (positioning), jak mluví zákazníci, důkazy, tón; u každého tvrzení stav (fakt / odhad / hypotéza)
   a zdroj; mezery a rozpory jako řádky „Ke kontrole“ s návrhem;
2. **teze** – 4–6 vět, každá jedna zajímavá myšlenka opřená o fakt podniku (vstup pro logo, slogan, strukturu, texty);
3. **pět sloganů** – 2–7 slov, každý s tím, čím se liší od oboru, a rizikem.

Hodnotí dvě nezávislé role, každá zvlášť a bez znalosti úvah studia i hodnocení druhé:
- **odborník** (stratég značky a copywriter) – síto před klientem: přesnost a podloženost, ostrost positioningu,
  hlas zákazníka, kvalita tezí a sloganů, jazyk a pojmy oboru;
- **klient** (majitel podniku) – vybere slogan a schválí nebo vrátí dokument; posuzuje, jestli se v tom pozná, jestli
  to řekne jeho zákazníkům to podstatné a jestli by to podepsal. Klient **nikdy neschvaluje fakta, která nezná ze
  zkušenosti** (čísla, data, ceny, jména) – nejasné fakt vrací „Ke kontrole“.

Typy, pro které měřítko platí: web místní služby, B2B služba s portfoliem, webová aplikace (u interní aplikace bez
sloganu). Měřítko musí být obecné, ne pro jeden obor.

Co chce zadavatel (PM studia): sdělení, které by předložila špičková strategická a copywriterská agentura – pravdivé,
podložené slovy zákazníků, s jasným rozdílem proti konkurenci, ne obecné fráze, které by sedly na kohokoli v oboru.

Napiš MĚŘÍTKO své role jako YAML (jen YAML):
```yaml
role: <tech|owner>
place: sdeleni
persona: {who: "...", wants: "...", rules: ["..."]}
criteria:
  - id: <snake_case>
    name: "..."
    weight: <celé číslo; součet 100>
    anchors: {4: "...", 6: "...", 8: "...", 10: "..."}
    sources: ["..."]
```
Požadavky: 5–7 kritérií; kotvy rozhodnutelné z dokumentu, tezí, sloganů a jejich zdrojů; kotva 8 = co by předložila
dobrá agentura, 10 = špička; obecné, zaměnitelné sdělení NESMÍ dostat 8 v kritériích o positioningu a sloganu (test
dosazení konkurenta). Opři se o literaturu a praxi (např. April Dunford „Obviously Awesome“, Marty Neumeier „Zag“,
Christensen/Moesta jobs to be done a síly přechodu, Joanna Wiebe / Copyhackers voice of customer, Donald Miller
„Building a StoryBrand“, Ann Handley „Everybody Writes“, David Ogilvy; Nielsen Norman Group o B2B a důvěryhodnosti)
a o přiložená pravidla studia `copy-rules.md`. Zdroje ověř na webu. Hranice přijetí neuváděj – zapiš je do
`web-local.<role>.sdeleni.gates.yaml` (`gates: [{criterion, min, why}]`, případně `weighted_min`). Čeština.
