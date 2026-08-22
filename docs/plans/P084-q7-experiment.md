# P084 — experiment Q7: čím zlevnit kontrolu plánu

**Stav: zadání. Nic z toho ještě neběželo.** Tenhle dokument je návod, jak
experiment provést, a místo, kam se zapíšou výsledky. Kdo ho spustí, doplní
tabulku a doporučení; nedoplněná tabulka je platný stav, ne chyba.

## Otázka

Kontrola plánu (CP1-deep, tři lensy + adjudikátor, u pásma `full` navíc kolo
C0 přes druhého poskytovatele) stojí devět agentů. Naměřeno na živých plánech:

| Plán | Nálezů | Z toho přijatých | Čas |
|---|---|---|---|
| P080 | 18 | 18 | (nezaznamenán) |
| P076 | 3 | 0 | ~32 min |
| P079 | 1 | 0 | ~9 min |

Stejná ceremonie, třikrát jiná hodnota. P084 na to odpovídá pásmy — ceremonie
úměrná dosahu. Q7 je druhá, nezávislá otázka: **když už kontrola běží, jak ji
provést, aby našla víc za méně?**

## Tři varianty

Každá dostane TÝŽ plán a týž kontrolní údaj (níže).

- **A — rozřezaný plán.** Plán se rozdělí na části (po EPICích nebo po krocích)
  a kontrolor dostane každou zvlášť, bez zbytku. Levné na kontext, slepé vůči
  rozporům mezi částmi.
- **B — celek dvakrát až třikrát.** Kontrolor dostane celý plán a projde ho
  opakovaně. Drahé na kontext, ale rozpory přes části vidí.
- **C — mapovací průchod + cílený.** První průchod přes celek vyrobí jen mapu
  (co plán tvrdí, kde, a o kterých souborech), druhý průchod jde po jednotlivých
  tvrzeních a u každého nálezu POVINNĚ přikládá důkaz (příkaz nebo `file:line`).

## Metriky

Pro každou variantu: **nálezů celkem**, **z toho přijatých adjudikátorem**,
**kol oprav**, **čas**. Čas se bere z telemetrie zavedené v Kroku 7
(`evidence/<plan_id>/timeline.jsonl`, událost `cp1_gate_result`), ne z odhadu.

## Kontrolní údaj: nález třídy „celkový rozpor"

Definice, aby ho každá varianta vyhodnotila stejně: **nález, jehož důkaz
vyžaduje porovnat tvrzení z JEDNÉ části plánu se skutečností v souborech, které
tato část NEJMENUJE.**

Reprodukovatelný případ (P080, 2026-08-11): plán tvrdil, že definice
„Step rendering rule" existuje ve čtyřech souborech; ve skutečnosti jich je šest
v pěti souborech a existující sada `test-fsm-step-render.bats` vyžaduje plný
text v pěti z nich. Zdroj: `.aid-o/work/evidence/P080/c0/c0-lens-reuse_compat.md`,
nález `C0-RC-1`.

Do experimentu se vloží jako **umělá vada do kopie plánu** a měří se, která
varianta ji najde. Varianta A ji podle konstrukce najít nemůže — pokud ji najde,
je to nález o metodě, ne o variantě, a patří do zápisu.

## Testovací případ

Tento plán (P084). Je dost velký, aby měl části, a jeho rozpory jsou doložené.

## Výsledky

| Varianta | Nálezů | Přijatých | Kol | Čas | Našla AB-2? |
|---|---|---|---|---|---|
| A | — | — | — | — | — |
| B | — | — | — | — | — |
| C | — | — | — | — | — |

**Doporučení:** (nevyplněno — experiment neběžel)

**Důvod:** (nevyplněno)

### Pravidla zápisu

- Varianta, kterou nelze doběhnout, se zapíše jako **nedokončená s důvodem**.
  Nenahrazuje se odhadem.
- Když všechny tři najdou totéž, rozhoduje čas a počet kol.
- Když AB-2 nenajde žádná, je to nález o metodě: zapíše se, že kontrolní údaj
  je mimo dosah všech tří variant, a proč.
- Když je vítěz nejasný, rozhodnutí jde PM, ne autorovi plánu.

## Čísla, která tenhle experiment NEUMÍ dodat

Zapsáno, aby se po nich nesahalo jako po dostupných:

- **Escape rate** — vady, které kontrolou prošly až do implementace. Vznikají
  v CP2/CP3 a v branách, ne tady.
- **Pády povinných testů na skutečné regresi** — vznikají v běžci testů.

Obojí patří k inventuře běhových kontrolních bodů
(`docs/plans/P084-runtime-checkpoint-impact.md`) a k budoucí revizi pásem.
