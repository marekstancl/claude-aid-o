# Společný rámec (platí pro obě role)

Studio staví weby malých podniků (typ `web-local`: lokální služba, např. zubní ambulance, kadeřnictví, autoservis, řemeslník).
Po každé verzi webu ho hodnotí model v roli kritika; agent nálezy opraví a kolo se opakuje (nejvýš 3 kola oprav).
Kritik dostane: živou adresu webu, snímky celých stránek na počítači (1440 px) a mobilu (390 px), soubory webu,
registr faktů potvrzených podnikem, historii svých minulých nálezů a jejich osud. Práh přijetí kritik nezná.

Co chce zadavatel (PM studia): **unikátní moderní web, plně funkční, s bohatými texty dobrými pro vyhledávače,
kvalitními fotkami** - web, který vypadá a prodává jako od drahého studia, ne zaškrtaný kontrolní seznam.
Minulý kritik (jeden, technický) dával 8/10 slušnému funkčnímu webu, který byl na pohled skoro beze změn; to nesmí opakovat.

Napiš MĚŘÍTKO své role jako YAML přesně v tomto tvaru (nic jiného, jen YAML):

```yaml
role: <owner|tech>
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
      4: "<jak vypadá web za 4 - konkrétní, pozorovatelné>"
      6: "<... za 6>"
      8: "<... za 8>"
      10: "<... za 10>"
```

Požadavky na měřítko:
- 5-8 kritérií. Kotvy musí jít rozhodnout z toho, co kritik vidí (snímky, soubory, živý web), ne z pocitu.
- Kotva 8 = opravdu dobrý web, na který je podnik hrdý; 10 = špička oboru v regionu i mimo něj. Slušný funkční web bez vlastního charakteru NESMÍ dosáhnout 8 v kritériích o dojmu a výjimečnosti.
- Co může dodat jen podnik (vlastní fotky, IČO, právní texty, doména), nehodnoť jako vadu webu, pokud je to zadané klientovi - patří to do „readiness“ (seznam toho, co chybí ke spuštění).
- Žádné vymyšlené fakty o podniku: tvrzení, které nesedí s registrem faktů, je vada.
- Jazyk měřítka: čeština. Obecné pro typ web-local, ne pro jeden konkrétní obor.
