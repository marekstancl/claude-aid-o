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

| Soubor / pravidlo | Zdroj | Commit / verze | Místní změny | Licence | Notice |
|---|---|---|---|---|---|
| `adopted/frontend-design-SKILL.md` | Anthropic, skill frontend-design (claude-plugins-official) | `022b3c274938` | žádné, doslovná kopie | Apache-2.0 | `LICENSES/Apache-2.0.txt` |
| `adopted/impeccable-craft-floor.md` | Impeccable, `reference/craft-floor.md` (Paul Bakaus, github.com/pbakaus/impeccable) | 4.3.1 | přidána hlavička s popisem změn; použití jen jako heuristika | Apache-2.0 | `LICENSES/NOTICE-impeccable.txt` |
| `lib/aid-ui-studio/studio.html` (stránka studia) | Impeccable, rozhodovací stránka (CSS proměnné `--ks-*`, balíček karet, lišta, lightbox; Paul Bakaus) | 4.3.1 | české popisky, data ze studia AID (payload, odpovědi), druhy otázek (text, schválení stránky, výjimka), lišta kroků, bez loga Impeccable | Apache-2.0 | `LICENSES/NOTICE-impeccable.txt` |
| Standard „Úlohy a stavy webové aplikace", UA-1, UA-4, UA-6, UA-7 | Impeccable, `reference/harden.md` (Error Handling, Edge Cases) | 4.3.1 | přepsáno česky, doplněno o sedm stavů úlohy | Apache-2.0 | `LICENSES/NOTICE-impeccable.txt` |
| Standard „Úlohy a stavy webové aplikace", UA-3 | Impeccable, `reference/onboard.md` (Empty State Design); UI UX Pro Max `ux-guidelines.csv` řádky 79, 90 | 4.3.1; `09170ee` | přepsáno česky | Apache-2.0, MIT | `LICENSES/NOTICE-impeccable.txt`, `LICENSES/MIT-ui-ux-pro-max.txt` |
| Standard „Úlohy a stavy webové aplikace", UA-2, UA-5, UA-8, UA-10 | UI UX Pro Max (github.com/nextlevelbuilder/ui-ux-pro-max-skill), `ux-guidelines.csv` řádky 5, 35, 55, 56, 80, 91 | `09170ee` | přepsáno česky | MIT | `LICENSES/MIT-ui-ux-pro-max.txt` |
| Standard „Úlohy a stavy webové aplikace", UA-11 | UI UX Pro Max, `charts.csv` (sloupce Accessibility Notes, A11y Fallback) | `09170ee` | přepsáno česky, zobecněno | MIT | `LICENSES/MIT-ui-ux-pro-max.txt` |
| nepřevzato: UI UX Pro Max `app-interface.csv` | UI UX Pro Max | `09170ee` | nepřevzato: pravidla pro React Native, /aid-ui staví web | MIT | `LICENSES/MIT-ui-ux-pro-max.txt` |

**Nesoulad licence Impeccable:** jeho `SKILL.md` uvádí `license: Apache 2.0`, `plugin.json`
uvádí `MIT` a v distribuci chybí soubor LICENSE i NOTICE. Používáme přísnější Apache 2.0
(text licence, NOTICE s atribucí, popis změn).
