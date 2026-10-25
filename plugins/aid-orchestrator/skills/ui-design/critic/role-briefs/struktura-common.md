# Společný rámec: místo rozhodnutí „struktura“ (obě role)

Studio (AI nástroj „AID studio“) staví weby malých podniků a aplikace. Ve fázi „Struktura a obsah“ navrhne
a předloží klientovi ke schválení:
1. **úkoly zákazníka** – s čím lidé na web přijdou (seřazené podle četnosti a důležitosti), u aplikace úlohy rolí;
2. **strom stránek** – stránky s adresou (URL), nadpisem H1, hlavní navigace a pořadí; u aplikace role, navigace
   a toky v sedmi stavech (běžná cesta, chyba validace, prázdno, načítání, selhání, oprávnění, obnova);
3. **sekce každé stránky** v pořadí: co sekce říká (teze ze sdělení), jakou akci nabízí, jaký důkaz nese;
4. u redesignu **inventuru starého webu** (každá stará stránka: zachovat / sloučit / přepsat / zrušit + nová adresa);
5. **plán obsahu** – u každé sekce co je potřeba (text, fotka, ceník, reference), kdo to dodá, stav; fakta jen z registru;
6. **živou kostru** – klikací web na stálé adrese se skutečnými stránkami a navigací, sekce jako popsané bloky.

Hodnotí dvě nezávislé role, každá zvlášť a bez znalosti úvah studia i hodnocení druhé:
- **odborník** (informační architekt, UX a SEO) – síto před klientem: úkoly zákazníka podložené zdroji, najdou se
  do dvou kliknutí, navigace slovy zákazníka, rámce stránek podle typu, nic ze starého webu se neztratí, adresy
  a nadpisy pro vyhledávače, plán obsahu bez zástupného textu, konvence oboru (správné názvy služeb);
- **klient** (majitel podniku) – posuzuje, jestli jsou tam všechny jeho služby a nic navíc, jestli jeho zákazníci
  najdou, co hledají, jestli je jasné, co má sám dodat a zvládne to, a jestli by takový web chtěl. Klient
  **nikdy neschvaluje fakta, která nezná ze zkušenosti** – nejasné vrací „Ke kontrole“.

Typy, pro které měřítko platí: web místní služby, B2B služba s portfoliem, webová aplikace (veřejná i interní).
Měřítko musí být obecné, ne pro jeden obor.

Co chce zadavatel (PM studia): strukturu, kterou by předložila špičková UX agentura – postavenou na úkolech
zákazníka a sdělení podniku, vyzkoušenou před stavbou, bez ztráty obsahu starého webu; a web, který je vidět
co nejdřív (živá kostra) a jen se doplňuje.

Napiš MĚŘÍTKO své role jako YAML (jen YAML):
```yaml
role: <tech|owner>
place: struktura
applies_to: [web_local, b2b_portfolio, webapp, webapp_internal]
persona: {who: "...", wants: "...", rules: ["..."]}
criteria:
  - id: <snake_case>
    name: "..."
    weight: <celé číslo; součet 100>
    anchors: {4: "...", 6: "...", 8: "...", 10: "..."}
    sources: ["..."]
```
Požadavky: 5–7 kritérií; kotvy rozhodnutelné z předložených souborů (úkoly, strom, sekce, inventura, plán, kostra);
kotva 8 = co by předložila dobrá agentura, 10 = špička. Opři se o literaturu a praxi (např. Gerry McGovern „Top
Tasks“, Nielsen Norman Group o informační architektuře, navigaci, tree testingu a B2B webech, Donna Spencer
„A Practical Guide to Information Architecture“, Abby Covert „How to Make Sense of Any Mess“, Kristina Halvorson
„Content Strategy for the Web“, Ginny Redish „Letting Go of the Words“, Steve Krug „Don't Make Me Think“, Google
Search Central o struktuře webu a přesunu webu) a o přiložená pravidla studia `copy-rules.md`. Zdroje ověř na webu.
Hranice přijetí neuváděj – zapiš je do `web-local.<role>.struktura.gates.yaml` (`gates: [{criterion, min, why}]`,
`weighted_min`). Čeština. Brána nad pravdivostí faktů nebo právem má navíc `required: true`: kritérium, které role nemohla posoudit, ji pak nepřeskočí, ale zastaví (IMP-702).

(P113, doplněno po napsání měřítek; brief_sha256 v AUTHORS.yaml je otisk znění, ze kterého autoři psali.)
Prvním podkladem obou rolí na místě struktura je **stálá adresa živé kostry** (`aid-ui-serve.sh skeleton`, výchozí port
3918): role kostru proklikávají jako zákazník, dokumenty jsou až druhý podklad.
