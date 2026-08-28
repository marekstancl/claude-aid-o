# Zadání pro nové okno: dokončit E10 (plán P062)

Pracovní adresář: /opt/eco/projects/aid-orchestrator

## Co po tobě chci

Dokonči E10 — plán `.aid-o/plans/P062-*.md`, který je napsaný, ale nikdy
nespuštěný. Jeho účel je JEDINÝ: **změřit na reálných datech, jestli kontroly
C0-C4 něco chytají, co by jinak prošlo, a za jakou cenu** — a z těch čísel
vyrobit rozhodovací tabulku, která u každé kontroly řekne: povýšit na blokující /
nechat jen pozorovat / porovnávat obě verze / odložit / navrhnout ke smazání.

## Přečti si nejdřív tohle, v tomhle pořadí

1. `.aid-o/plans/P062-*.md` — sekci `## Re-grounding 2026-08-14` čti PRVNÍ,
   přebíjí zbytek dokumentu. Plán je z 12. 7. a od té doby přibylo přes třicet
   vydání; re-ground je poctivý soupis toho, co v něm už neplatí.
2. `docs/plans/2026-06-29-BACKLOG.md`, sekce „Pre-E10 control hygiene block" —
   nese závaznou PM direktivu k E10/E11.
3. `CLAUDE.md` v kořeni projektu — konvence, testovací patra, release workflow.

## Co je na tom podstatné (a proč to nikdo dosud neudělal)

E10 je jediné místo v celé té stavbě, kde se má MĚŘIT místo dohadovat. Dneska
platí: kontrol je devět vrstev, nikdo neví, kolik z nich něco unikátně chytá,
a přesto se přidávají další. PM direktiva to říká natvrdo:

> C0-C4 nesmí být trvalá další vrstva. (…) Pokud se počet kontrol nesníží,
> E11 není hotové.

E10 tedy dodává **data**, E11 pak podle nich **maže**. Bez E10 je mazání hádání.

## Tvrdé podmínky, které plán sám klade

V plánu je sekce `## Preconditions (TVRDÉ)`. Re-ground z 14. 8. je zúžil na tři:
IMP-179, IMP-201 a rozpočet merge cesty. **Ověř jejich stav ZNOVU** — od
re-groundu uplynulo čtrnáct dní a v repu je dnes v2.94.0. Neber je jako platné.

## Čeho se vyvaruj

- Plán míří na verzi v2.56.0 a jmenuje soubory, které neexistují. Re-ground to
  přiznává. **Neimplementuj plán doslova** — nejdřív ho re-grounduj znovu.
- Neměř na fixturách, které si sám vyrobíš tak, aby kontroly vyšly dobře.
  Kalibrační dataset má vycházet z HISTORICKÝCH vad tohohle repozitáře.
- Nepřidávej v rámci E10 žádnou novou kontrolu. E10 měří, nepřidává.

## Co je hotovo (ať to nezkoumáš znovu)

Poslední vydání: v2.94.0. Plány P084-P090 jsou dodané. Dnes (28. 8.) byly
opraveny dvě věci mimo plán: absolutní cesta v kontraktu kroku (IMP-521) a
autonomie plánu založeného před P090 (plán se po EPICu tiše zastavoval).

## Výstup, který chci

Rozhodovací tabulku per kontrola s čísly, o která se opírá, a k tomu
jednu větu, kolik kontrol podle těch dat může zmizet.
