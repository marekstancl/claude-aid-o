# P084 — inventura runtime kontrolních bodů (CP2–CP6, C1–C4)

**Otázka, na kterou tenhle dokument odpovídá:** P084 mění, jak se rozhoduje
o ceremonii PLÁNU. Čte některý z běhových kontrolních bodů pole plánu, které se
tím mění — a plyne z toho pro něj něco?

**Odpověď v jedné větě:** ne. Běhové kontrolní body neodvozují nic z plánu;
odvozují to z **diffu běhu** přes `review-profile.json`, který vyrábí
`aid-prefilter.sh profile` z `git diff`. Pásmo plánu a `risk_profile` běhu jsou
dvě různé veličiny se dvěma různými vstupy, a P084 se dotýká jen té první.

**Rozsah:** změny běhových kontrolních bodů NEJSOU v rozsahu P084. Tenhle
dokument je inventura, ne návrh.

## Jak jsem to zjistil

```bash
grep -rln "risk_profile\|risk: high" scripts/*.sh scripts/lib/*.sh defaults/policies/*.yaml
grep -rn "risk_profile" scripts/aid-prefilter.sh          # :576-594 — počítá se z diffu
grep -rn "risk:" scripts/aid-fsm.sh                        # nic: FSM frontmatter plánu nečte
```

`aid-prefilter.sh` (`:576-594`) skládá `risk_profile` jako nejvyšší ze
**zasažených povrchů v diffu** (`docs_trivial|low|medium|high|unverifiable`).
Do `review-profile.json` se to zapíše jednou za běh a všichni níže to čtou odtud.

## Tabulka

| Kontrolní bod | Co čte | Dotčen P084 | Proč |
|---|---|---|---|
| **CP2** — revize kroku | `review-profile.json` → `required_lenses`, diff kroku | ne | vstupem je diff kroku, ne plán |
| **CP3** — integrační revize | diff EPIKu + `review-profile.json` | ne | totéž o úroveň výš |
| **CP4** — validace kurátorových návrhů | diff posledního commitu | ne | plán nečte vůbec |
| **CP5** — kritické nálezy auditora blokují DONE | výstup auditora | ne | plán nečte vůbec |
| **CP6** — revize po `/aid-do` | diff `HEAD~1..HEAD` | ne | Fast Mode žádný plán nemá |
| **C1** — delivery engine | `execution.yaml`, stav FSM | ne | pásmo je plan-time veličina |
| **C2** — sémantické čočky | `review-profile.required_lenses` (z diffu) | ne | `aid-prefilter.sh:576` |
| **C3** — nezávislý audit | `review-profile.risk_profile` → `c3-audit-policy.yaml` (`lib/aid-audit-mode.sh:59-63`, `lib/aid-audit-independence.sh:10`) | ne | tentýž `risk_profile` z diffu; s pásmem plánu nemá společné nic než slovo „risk" |
| **C4** — release policy | `review-profile.risk_profile` (`aid-release-policy.sh:281-289`) + brány | ne | totéž |
| **profil bran** | `review-profile.risk_profile` (`lib/aid-gate-profile.sh:318`) | ne | totéž |

## Jedna past, kterou je potřeba pojmenovat

Slovo **risk** teď v systému znamená dvě věci a je snadné je splést:

- **pásmo plánu** (`full|medium|light`) — spočítané z cest, které plán
  DEKLARUJE, ještě než existuje řádek kódu. Rozhoduje o ceremonii plánu.
- **`risk_profile` běhu** (`docs_trivial|low|medium|high|unverifiable`) —
  spočítaný ze SKUTEČNÉHO diffu. Rozhoduje o čočkách, auditu a bránách.

Nesouhlasí spolu záměrně: plán v pásmu `light` může vyprodukovat diff, který
`aid-prefilter.sh` označí `high`, a pak proběhne plná běhová ceremonie. To je
funkce, ne vada — je to přesně ta pojistka, kvůli které si P084 může dovolit
poslat běžný kód do `light`. Plánová ceremonie je o rozhodnutích, běhová
o kódu.

## Co z toho plyne pro Plán 2 a 3

Kdyby se někdy chtělo pásmo plánu promítnout do běhu (například „plán v pásmu
`light` nepotřebuje C3 audit"), je to **nová vazba**, kterou dnes nic nenese:
`review-profile.json` pásmo neobsahuje. Zavést by se musela zápisem pásma do
profilu běhu a změnou `c3-audit-policy.yaml`. P084 to nedělá a nedoporučuje to
bez měření — běhová ceremonie chytá přesně to, co plánová vidět nemůže.

---

**Vyrobeno:** 2026-08-22, P084 Krok 6.
