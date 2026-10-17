# Společný rámec: místo rozhodnutí „pohyb značky“ (obě role)

Studio (AI nástroj „AID studio“) staví weby a značky malých podniků (typ `web-local`). Ke schválenému logu vyrábí
**animované logo** (na webu ≤ 1 s se jménem čitelným hned; pro prezentaci a video na sociální sítě 2–3 s – doplněno F7, neověřeno) a **hero webu odvozené z loga**
(první obrazovka: nadpis h1, krátký podnadpis, tlačítko a animovaná značka). Pohyb má vycházet ze značky a oboru
podniku („pohybový jazyk“), ne z cizího webu.

Hodnotí dvě nezávislé role, každá zvlášť a bez znalosti úvah studia i hodnocení druhé:
- **odborník** (motion designer a front-end inženýr) – síto před klientem: řemeslo pohybu, vztah ke značce,
  použitelnost a technika;
- **klient** (majitel podniku) – vybere nebo vrátí s důvodem; posuzuje, jestli pohyb sedí k jeho podniku
  a zákazníkům a nepůsobí lacino nebo rušivě; řemeslo pohybu nehodnotí.

Role dostane: zadání značky a pohybový jazyk (pár vět, jak se má značka hýbat a proč), schválené logo, a pro každou
variantu: video animovaného loga, video hero (počítač a telefon), filmový pás snímků po 100–200 ms, výsledek
kontrol studia (nadpis čitelný hned, pohyb doběhne, omezit pohyb, obsah bez JavaScriptu) a délky jednotlivých fází.

Co chce zadavatel (PM studia): pohyb, který by předložilo špičkové studio – krátký, záměrný, odvozený ze značky
(u projektanta „rýsování“: linka se vytáhne jako perem, kóta se natáhne), který nikdy nezdrží obsah a nečte se jako
načítání, efekt pro efekt nebo šablona.

Napiš MĚŘÍTKO své role jako YAML (jen YAML):

```yaml
role: <tech|owner>
place: pohyb
persona: {who: "...", wants: "...", rules: ["..."]}
criteria:
  - id: <snake_case>
    name: "..."
    weight: <celé číslo; součet 100>
    anchors: {4: "...", 6: "...", 8: "...", 10: "..."}
    sources: ["..."]
```

Požadavky: 5–7 kritérií; kotvy rozhodnutelné z videí, pásu snímků a výsledků kontrol; kotva 8 = co by předložilo
dobré studio, 10 = špička (např. Pentagram, Koto, DixonBaxi, Collins, Studio Dumbar); efektní, ale se značkou
nesouvisející pohyb nesmí dostat 8 v kritériu o vztahu ke značce. Opři se o přiložené `STANDARDS.md` a
`animate-SKILL.md` (převzatý postup) a o literaturu a praxi (např. Val Head „Designing Interface Animation“,
Rachel Nabors „Animation at Work“, Google Material motion, IBM Design Language motion, Apple HIG Motion, WCAG 2.3.3
a 2.2.2); zdroje ověř na webu a uveď u kritérií. Hranice přijetí neuváděj (zná je jen kód) – zapiš je do zvláštního
souboru `web-local.<role>.pohyb.gates.yaml` ve tvaru `gates: [{criterion, min, why}]`, případně `weighted_min`.
Čeština, obecně pro web-local.
