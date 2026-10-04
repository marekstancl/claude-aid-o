# Registr převzatého materiálu (/aid-ui)

Každý cizí text, který /aid-ui nese nebo z něhož vychází ekosystémový standard, má tady
řádek. Soubor v `adopted/` bez řádku je chyba: test
`scripts/tests/bats/test-aid-ui-adopted-sources.bats` na něm spadne. Každá licence ve
sloupci Licence má svůj text v `LICENSES/` (soubor začíná jejím SPDX kódem).

Aktualizace snímku: nový soubor se porovná se starým (diff), po revizi se soubor nahradí
a řádek (commit/verze, změny) se přepíše ve stejném commitu. Novější verze v cache pluginu
sama nic nemění, skill čte snímek.

Pravidla ve standardech jsou přepsaná vlastními slovy, ne kopie; u každého pravidla je
zdroj. Při rozporu s [design systémem](https://docs.aidlab.dev/ecosystem/specs/design-system-standard)
platí design systém.

| Soubor / pravidlo | Zdroj | Commit / verze | Místní změny | Licence | Notice | Čte ho |
|---|---|---|---|---|---|---|
| `adopted/frontend-design-SKILL.md` | Anthropic, skill frontend-design (claude-plugins-official) | `022b3c274938` | žádné, doslovná kopie | Apache-2.0 | `LICENSES/Apache-2.0.txt` | — |
| `adopted/impeccable-craft-floor.md` | Impeccable, `reference/craft-floor.md` (Paul Bakaus, github.com/pbakaus/impeccable) | 4.3.1 | přidána hlavička s popisem změn; použití jen jako heuristika | Apache-2.0 | `LICENSES/NOTICE-impeccable.txt` | — |
| `lib/aid-ui-studio/studio.html` (stránka studia) | Impeccable, rozhodovací stránka (CSS proměnné `--ks-*`, balíček karet, lišta, lightbox; Paul Bakaus) | 4.3.1 | české popisky, data ze studia AID (payload, odpovědi), druhy otázek (text, schválení stránky, výjimka), lišta kroků, bez loga Impeccable | Apache-2.0 | `LICENSES/NOTICE-impeccable.txt` | — |
| Standard „Úlohy a stavy webové aplikace", UA-1, UA-4, UA-6, UA-7 | Impeccable, `reference/harden.md` (Error Handling, Edge Cases) | 4.3.1 | přepsáno česky, doplněno o sedm stavů úlohy | Apache-2.0 | `LICENSES/NOTICE-impeccable.txt` | — |
| Standard „Úlohy a stavy webové aplikace", UA-3 | Impeccable, `reference/onboard.md` (Empty State Design); UI UX Pro Max `ux-guidelines.csv` řádky 79, 90 | 4.3.1; `09170ee` | přepsáno česky | Apache-2.0, MIT | `LICENSES/NOTICE-impeccable.txt`, `LICENSES/MIT-ui-ux-pro-max.txt` | — |
| Standard „Úlohy a stavy webové aplikace", UA-2, UA-5, UA-8, UA-10 | UI UX Pro Max (github.com/nextlevelbuilder/ui-ux-pro-max-skill), `ux-guidelines.csv` řádky 5, 35, 55, 56, 80, 91 | `09170ee` | přepsáno česky | MIT | `LICENSES/MIT-ui-ux-pro-max.txt` | — |
| Standard „Úlohy a stavy webové aplikace", UA-11 | UI UX Pro Max, `charts.csv` (sloupce Accessibility Notes, A11y Fallback) | `09170ee` | přepsáno česky, zobecněno | MIT | `LICENSES/MIT-ui-ux-pro-max.txt` | — |
| nepřevzato: UI UX Pro Max `app-interface.csv` | UI UX Pro Max | `09170ee` | nepřevzato: pravidla pro React Native, /aid-ui staví web | MIT | `LICENSES/MIT-ui-ux-pro-max.txt` | — |
| `adopted/marketingskills/product-marketing/SKILL.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), skill product-marketing | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/1p-sources.md` (krok P108-3) |
| `adopted/marketingskills/customer-research/SKILL.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), skill customer-research | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/1p-sources.md` (krok P108-3) |
| `adopted/marketingskills/customer-research/references/interviews-and-surveys.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), customer-research, rozhovory a dotazníky | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/1p-sources.md` (krok P108-3) |
| `adopted/marketingskills/customer-research/references/source-guides.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), customer-research, průvodce zdroji | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/1p-sources.md` (krok P108-3) |
| `adopted/marketingskills/copywriting/SKILL.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), skill copywriting | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/6-build.md`, `skills/ui-design/steps/1v-vision.md` |
| `adopted/marketingskills/copywriting/references/copy-frameworks.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), copywriting, rámce textů | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/6-build.md` |
| `adopted/marketingskills/copywriting/references/natural-transitions.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), copywriting, přechody | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/6-build.md` |
| `adopted/marketingskills/copywriting/references/ai-tells.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), copywriting, fráze prozrazující AI text | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/6-build.md` |
| `adopted/marketingskills/cro/SKILL.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), skill cro (konverze stránky) | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/3-content-plan.md` |
| `adopted/marketingskills/cro/references/form.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), cro, formuláře | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `scripts/aid-ui-copy.py` (krok P108-5) |
| `adopted/marketingskills/copy-editing/SKILL.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), skill copy-editing | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `scripts/aid-ui-copy.py` (krok P108-5) |
| `adopted/marketingskills/copy-editing/references/checklist.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), copy-editing, kontrolní seznam | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `scripts/aid-ui-copy.py` (krok P108-5) |
| `adopted/marketingskills/copy-editing/references/content-refresh.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), copy-editing, obnova starých textů | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `skills/ui-design/steps/1p-sources.md` (krok P108-3) |
| `adopted/marketingskills/copy-editing/references/plain-english-alternatives.md` | coreyhaines31/marketingskills (Corey Haines, github.com/coreyhaines31/marketingskills), copy-editing, jednoduchá angličtina | `dda3841` | žádné, doslovná kopie (otisk v `MANIFEST`) | MIT | `LICENSES/MIT-marketingskills.txt` | `scripts/aid-ui-copy.py` (krok P108-5) |
| `adopted/marketingskills/MANIFEST` | vlastní: git blob id každého převzatého souboru z commitu `dda3841` | `dda3841` | vlastní soubor | MIT | `LICENSES/MIT-marketingskills.txt` | `scripts/tests/bats/test-aid-ui-adopted-sources.bats` |

**Marketingové postupy (P108):** `adopted/marketingskills/` je doslovný snímek pěti skillů
z commitu `dda3841` (2. 10. 2026). `MANIFEST` drží git blob id každého souboru (`git hash-object`),
takže shodu s originálem lze ověřit bez sítě (`git -C <klon> rev-parse dda3841:skills/<cesta>`).
Sloupec „Čte ho" jmenuje soubor pluginu, který převzatý soubor čte; test ho ověřuje. Odkazy uvnitř
převzatých souborů na soubory, které ve snímku nejsou (např. `cro/references/experiments.md`), se
nesledují. Aktualizace = nový snímek, nový `MANIFEST` a nový commit v řádcích v jednom commitu.

**Vlastní práce, bez cizí licence:** rozvržení stránky studia jako průběhu stavby
(`lib/aid-ui-studio/studio.html`: kroky pod sebou, výsledek a kdo rozhodl, Detail, otázka
uvnitř kroku) je práce AID z brainstormu P106 (návrh B, Codex, 30. 9. 2026); nic z něj není
převzaté. Vzhled stránky (paleta, karty, lišta) zůstává převzatý podle řádku Impeccable výše.

**Nesoulad licence Impeccable:** jeho `SKILL.md` uvádí `license: Apache 2.0`, `plugin.json`
uvádí `MIT` a v distribuci chybí soubor LICENSE i NOTICE. Používáme přísnější Apache 2.0
(text licence, NOTICE s atribucí, popis změn).
