# P084 Krok 8 — čím zlevnit kontrolu plánu (experiment Q7)

**Otázka:** tři způsoby, jak nechat kontrolora projít plán. Který najde nejvíc
skutečných vad za nejmíň času?

**Odpověď v jedné větě:** vyhrála varianta **B — celý plán, dvakrát za sebou**:
osm skutečných nálezů, ani jeden falešný, o třetinu dráž než nejlevnější
varianta.

## Uspořádání

- **Testovací případ:** samotný plán P084 (761 řádků), ve stavu, v jakém šel do
  implementace.
- **Kontrolor:** `codex exec` (cizí model), stejný prompt pro všechny varianty,
  stejný **evidence appendix** — výpis skutečných faktů repozitáře ve stavu
  `70b433a1` (kdo sourcuje `aid-scoping.sh`, obsah `scripts/lib/`,
  `defaults/policies/`, seznam testových sad). Kontrolor nečetl žádné soubory;
  všechno měl na stdin. Tím se z porovnání odstranila proměnná „kolik toho
  stihne najít v repozitáři" a zbylo jen to, co se měří: jak se plán rozřeže.
- **Varianty:**
  - **A** — plán rozřezaný na dvě části (kroky 1-4, kroky 5-9), každá zvlášť.
  - **B** — celý plán, dva průchody; druhý s instrukcí být tvrdší na to, co by
    první minul.
  - **C** — mapovací průchod (vypiš každé faktické tvrzení o repozitáři), pak
    cílený průchod, který smí hlásit jen tvrzení vyvrácená appendixem, a to
    s citací obou stran.
- **Kontrolní vada (AB-2):** do plánu byla úmyslně vložena jedna vada třídy
  „celkový rozpor" — v Kroku 1 se `tři volající` změnili na `dva volající`.
  Skutečnost (appendix): čtyři skripty. Důkaz vyžaduje porovnat tvrzení jedné
  části se soubory, které ta část nejmenuje.
- **Vyhodnocení pravdivosti:** nálezy jsem srovnal se **skutečnou implementací**
  P084 — u každého vím, jestli jsem na něj při psaní kódu narazil. To je
  silnější měřítko než úsudek nad plánem.

## Naměřeno

| Varianta | Běhů | Čas | Nálezů | Pravdivých | Falešných | Unikátních pravdivých |
|---|---|---|---|---|---|---|
| **A** (rozřezaný) | 2 | 82 s | 11 | 8 | **3** | 7 |
| **B** (celý, 2×) | 2 | 111 s | 13 | 13 | 0 | **8** |
| **C** (mapa + cíl) | 2 | 94 s | 3 | 3 | 0 | 3 |

„Unikátních pravdivých" = po odečtení duplicit uvnitř varianty.

**Kontrolní vada AB-2: našly ji všechny tři varianty.** Nerozlišila je — a to je
samo o sobě nález o metodě, ne o variantách: jakmile má kontrolor příslušný fakt
v appendixu, je vložený rozpor v číslech triviální. Rozdíl mezi variantami
udělaly vady, které jsem nevkládal.

## Co našla která varianta

Osm skutečných vad, seřazeno podle toho, kolik variant je vidělo:

| # | Vada | A | B | C |
|---|---|---|---|---|
| 1 | `dva volající` vs. čtyři (vložená AB-2) | ✓ | ✓ | ✓ |
| 2 | plán tvrdí, že pro `aid-cp1-gate.sh` neexistuje sada — existuje `test-cp1-gate.sh` | ✓ | ✓ | ✓ |
| 3 | Testing Strategy jmenuje `test-plan-to-epic-tier.bats`, o níž Krok 4 sám říká, že neexistuje | — | ✓ | ✓ |
| 4 | P080 je současně „mění FSM" (měření) i „→ light" (hraniční případ) | ✓ | ✓ | — |
| 5 | vlna 3 pouští souběžně Kroky 6 a 7, oba mění `aid-generation-readiness.sh` | ✓ | ✓ | — |
| 6 | SC1 nemá producenta: `check-classification-reference.sh` nezakládá žádný krok | — | ✓ | — |
| 7 | definice false negative vs. SC1: `medium` je taky „níž", a SC1 to připouští | — | ✓ | — |
| 8 | Krok 3 slibuje, že lint zavolá klasifikaci, ale nemá `aid-plan-lint.sh` ve `Files:` | ✓ | — | — |

**Všech osm jsem při implementaci potkal.** Vada 5 (kolize vlny 3) a vada 8
(chybějící soubor ve `Files:`) mě stály reálnou práci; vada 6 taky — skript
`check-classification-reference.sh` jsem musel založit mimo deklarovaný rozsah.

## Co je vidět v číslech

**Rozřezání (A) je jediná varianta, která si vyrobila falešné nálezy.** Všechny
tři byly totéž nedorozumění: kontrolor s částí plánu si špatně přečetl strukturu
testovacího stromu a tvrdil, že adresář `scripts/tests/bats/` neexistuje. Část
plánu je málo kontextu na to, aby si to sám opravil.

**Rozřezání zároveň nevidí přes řez.** Vady 3, 6 a 7 spojují Krok 1 nebo 4 se
Success Criteria a s Testing Strategy — tedy hlavičku plánu s jeho koncem.
Varianta A nenašla ani jednu. Naopak vadu 5 našla, protože oba kolidující kroky
padly do stejné části: řez rozhoduje o tom, co je vidět, a řez je náhodný vůči
tomu, kde vady jsou.

**Druhý průchod celku (B2) je nejlevnější přidaná hodnota v celém experimentu.**
Sám o sobě dal 8 nálezů, všechny pravdivé, včetně tří, které první průchod minul
— za 73 sekund a nula falešných.

**Varianta C je přesná, ale ze své podstaty krátkozraká.** Instrukce „hlas jen
tvrzení vyvrácená appendixem" má stoprocentní přesnost a najde jen vady třídy
„plán tvrdí o repozitáři něco nepravdivého". Kolizi rozvrhu ani chybějícího
producenta success kritéria najít nemůže, protože to nejsou tvrzení o
repozitáři. Za 34 sekund ovšem vyrobila mapu 28 faktických tvrzení plánu, což je
použitelný vstupní seznam pro cokoliv dalšího.

## Doporučení

**Používat B: celý plán, dva průchody.** Nejvíc pravdivých nálezů, žádný falešný,
111 sekund. Druhý průchod není opakování — je to nejlevnější zdroj nálezů, jaký
tenhle experiment našel.

**Nerozřezávat plán na části.** Je to nejlevnější varianta a platí se za to
dvakrát: falešnými nálezy z chybějícího kontextu a slepotou vůči rozporům přes
řez. Kdyby plán někdy přerostl kontextové okno, rozřezání je nouzové řešení, ne
volba.

**C přidávat jako filtr, ne jako náhradu**, a to tam, kde je otázka „jsou fakta
v plánu pravdivá" (typicky Reuse check a Doklad hledání). Mapovací průchod C1
stojí půl minuty a dá seznam tvrzení, který se dá strojově odškrtat.

Rozhodnutí, jestli se to promítne do `review-checkpoints.yaml` jako závazný tvar
CP1-deep, patří PM (V7). Tenhle dokument dodává čísla, ne změnu konfigurace.

## Otevřená čísla, která tenhle experiment nedodal

Zapsáno vědomě — sběr těchto dvou veličin je mimo rozsah P084, protože vznikají
v implementační a běhové vrstvě (viz Krok 7 a
`P084-runtime-checkpoint-impact.md`):

1. **Escape rate** — kolik vad projde plánovou kontrolou a vyplave až v CP2/CP3
   nebo v bránách. Bez toho se nedá říct, jestli osm nálezů je hodně, nebo jestli
   dalších dvacet prošlo.
2. **Pády povinných testů na skutečné regresi** — jestli testy, které plán
   zakládá, vůbec někdy chytnou vadu. Vzniká v runneru.

---

**Vyrobeno:** 2026-08-22, P084 Krok 8. Surová data: 6 běhů `codex exec`,
výstupy v `.aid-o/work/evidence/P084/q7/` (mimo git — `.aid-o/` je ignorované).
