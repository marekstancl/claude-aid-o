# Společný rámec: místo rozhodnutí „logo“ (obě role)

Studio (AI nástroj „AID studio“) staví weby a značky malých podniků (typ `web-local`: lokální služba nebo
řemeslo, např. zubní ambulance, projekční kancelář, kadeřnictví, autoservis). V kroku „logo“ studio vyrobí
několik směrů loga (u podniku se zavedeným logem i jeho oživení) a předloží je klientovi k výběru.

Na tomto místě hodnotí dvě nezávislé role, každá zvlášť a bez znalosti úvah studia i hodnocení té druhé:
- **odborník** (zkušený designér značek) je síto před klientem: hodnotí řemeslo a kvalitu značky.
  Směr pod hranicí přijetí (zná ji jen kód) se klientovi neukáže; studio ho opraví nebo vyřadí.
- **klient** (majitel podniku) vybírá z toho, co prošlo sítem, nebo vrací s důvodem. Hodnotí podnik,
  zákazníka a hodnotu za peníze, ne řemeslo designu.

Každá role dostane totéž: zadání značky (obor, místo, zákazníci, teze a příběh, co podnik nechce),
u zavedeného loga dnešní logo a audit jeho hodnoty, a pro každý směr: logo s názvem, samotnou značku
zvětšenou na 512 px, značku v 16, 32 a 48 px, černobíle a inverzně, a značku v kontextech použití
(hlavička webu, záložka prohlížeče, ikona na telefonu, avatar, vizitka, cedule nebo razítko), plus loga
3–5 konkurentů z regionu. Úvahy studia, bodování studia ani pořadí doporučení role nevidí.

Co chce zadavatel (PM studia): **značku, kterou by předložilo špičkové studio** - jednu jasnou myšlenku,
vlastní, jednoduchou, čitelnou v 16 px, s příběhem, který sedí na tento podnik a ne na celý obor.
Minulá první kola byla „fádní“: technicky čistá, ale zaměnitelná; to nesmí projít.

Napiš MĚŘÍTKO své role jako YAML přesně v tomto tvaru (nic jiného, jen YAML):

```yaml
role: <tech|owner>
place: logo
persona:
  who: "<kdo hodnotí, jednou větou>"
  wants: "<co chce, jednou větou>"
  rules:
    - "<pravidlo, jak hodnotit; konkrétní, kontrolovatelné>"
criteria:
  - id: <snake_case>
    name: "<lidský název>"
    weight: <celé číslo; součet vah všech kritérií = 100>
    anchors:
      4: "<jak vypadá směr za 4 - konkrétní, pozorovatelné na podkladech>"
      6: "<... za 6>"
      8: "<... za 8>"
      10: "<... za 10>"
    sources: ["<odkud kritérium a kotvy vycházejí: autor, dílo, kapitola nebo URL>"]
```

Požadavky na měřítko:
- 5-7 kritérií. Kotvy musí jít rozhodnout z toho, co role vidí (obrázky a zadání), ne z pocitu.
- Kotva 8 = značka, na kterou je podnik hrdý a kterou by předložilo dobré studio; 10 = úroveň špičkových
  studií (Pentagram, Chermayeff & Geismar & Haviv, Landor, Studio Dumbar a podobně). Čistá, ale zaměnitelná
  značka NESMÍ dosáhnout 8 v kritériích o myšlence a odlišnosti.
- Opři kritéria a kotvy o uznávanou praxi a literaturu oboru (např. Paul Rand, Chermayeff & Geismar & Haviv
  „Identify“, Alina Wheeler „Designing Brand Identity“, David Airey „Logo Design Love“, Michael Evamy
  „Logo“, Michael Bierut) a o přiložený převzatý postup `critique.md` a `testing-checklist.md`. U každého
  kritéria uveď zdroj (`sources`). Nic si nevymýšlej; když si zdrojem nejsi jistý, ověř ho na webu.
- U oživení zavedeného loga musí měřítko umět rozlišit dobré oživení (zachová to, co lidé poznávají, a odstraní
  slabiny) od kosmetiky i od zbytečného zahození hodnoty.
- Jazyk měřítka: čeština. Obecné pro typ web-local, ne pro jeden obor.
