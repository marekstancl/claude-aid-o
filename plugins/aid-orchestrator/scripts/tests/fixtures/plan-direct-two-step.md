---
id: P900
type: regular
status: draft
risk: low
lifecycle_strict: true
---

# Plan: P900 — počítání podle délky (přímý běh)

## Context

Jádro umí spočítat položky jen podle prvního písmene (`tally` v
`src/core/counter.py`). Plán přidá druhý způsob a popíše ho v příručce.

## Goal

Projekt umí počítat položky i podle jejich délky a příručka tu volbu popisuje.

## Implementation Steps

**EPIC 1: Steps 1-2**

### Step 1: Přidat počítání podle délky do jádra

**Objective:** jádro umí spočítat položky podle jejich délky, vedle stávajícího
počítání podle prvního písmene.

**Files:**
- Create: `src/core/lengths.py` — funkce `tally_by_length(items)`

**Reuse check:** searched: `grep -rln "def tally" src/core` → one match — existující `tally` počítá výhradně podle prvního písmene a druhá osa počítání do téhož modulu nepatří

**Architecture Context:**
Čistá funkce nad seznamem řetězců: dostane položky, vrátí slovník délka → počet.

**Error Handling:**
Prázdný seznam vrátí prázdný slovník; položka, která není řetězec, vyhodí
`TypeError` z `len()` a ten projde nahoru.

**Edge Cases:**
Prázdný řetězec → klíč `0`. Klíče jsou celá čísla.

**Dependencies:**
- Depends on: none

**Effort:** S

**Zavírá:** AC1

**AID Role:** backend

### Step 2: Popsat volbu v příručce

**Objective:** uživatel se z příručky dozví, že existují dva způsoby počítání.

**Files:**
- Modify: `prirucka/README.md` — nová sekce o počítání položek

**Architecture Context:**
Příručka je jediná uživatelská plocha projektu; popis se píše ručně.

**Error Handling:**
Textová změna, žádný běhový stav.

**Edge Cases:**
Příručka dnes obsahuje jen úvodní odstavec, sekce se přidává.

**Dependencies:**
- Depends on: Step 1

**Effort:** S

**Zavírá:** AC2

**AID Role:** docs-writer

## Testing Strategy

Ověření spuštěním funkce a kontrolou textu příručky (příkazy v bodech hotovo).

## Resources Verification

- [x] Functions: `tally` (`src/core/counter.py`).
- [x] Commands: `python3`, `grep`.

## Risks

| Riziko | P | Dopad | Zmírnění |
|---|---|---|---|
| Příručka popíše chování, které kód nemá | nízká | střední | bod AC2 kontroluje text |

## Acceptance Criteria

- [ ] AC1: `tally_by_length` vrací počty položek podle jejich délky.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "python3 -c 'from src.core.lengths import tally_by_length as t; assert t([\"jedna\", \"dve\"]) == {5: 1, 3: 1}'"
    expected_exit: 0
  ```
- [ ] AC2: Příručka má sekci o počítání podle délky.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "prirucka/README.md"
    regex: "délk"
  ```

## Success Criteria

- [ ] SC1 — `tally_by_length` vrací počty položek podle délky
- [ ] SC2 — příručka má sekci o počítání podle délky
