# Pekárna U Mlýna - design standard

*Pracovní verze z 3. 10. 2026 (/aid-ui, krok 7). Do Docusauru se publikuje až po schválení PM. Tokeny jsou z `DESIGN.md` (z nich se generuje CSS webu), komponenty změřené na postaveném webu, vzory a texty sepsané z postaveného webu a schválené PM.*

## Značka

Zdroj: brand balíček `docs/design/brand-package/` (symbol, logo s názvem, ikony, zdroje).

- Logo se nikdy neskládá z textu, vždy soubor z balíčku.

## Tokeny

Jediný zdroj: frontmatter `DESIGN.md` → CSS proměnné (`aid-ui-design-to-css.sh`).

### Barvy

| token | hodnota |
|---|---|
| `ink` | `#1a1a1a` |
| `flour` | `#faf6ee` |

### Typografie

| role | písmo | velikost | tučnost | řádkování | prostrkání |
|---|---|---|---|---|---|

### Rozměry

- zlomy šířky (změřeno v CSS): žádné

### Pohyb

- přechody (změřeno, nad 10 ms): žádné
- při `prefers-reduced-motion` se nic nehýbe (změřeno)

### Ikony

- ikon na webu (změřeno: `svg`/`img` do 48 px mimo logo): 0

### Vrstvy

- prvky s `z-index` (změřeno, i skryté): žádné

## Komponenty

### Tlačítka

Role změřené na webu (tlačítka, `[role=button]` a odkazy s plochou nebo rámečkem; stav najetí, zaměření a zakázaný změřen na jednom prvku role):

| role | plocha | text | rámeček | zaoblení | výška 390 / 1440 px | písmo 390 / 1440 px | najetí | zaměření | zakázané | výskyty | příklady |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `#1a1a1a` (ink) | `#faf6ee` (flour) | none | 4px | 44 / 44 | 600 16px / 600 16px | - | - | odkaz | 1 | Objednat |

## Vzory

*Doplní agent z postaveného webu, schválí PM.*

## Obsah a terminologie

*Doplní agent, schválí PM.*

## Platformní kontrakt

*Z DESIGN.md, „Platformní kontrakt“:*

| | Mobil | Počítač | Tablet |
|---|---|---|---|
| Předěl | jeden sloupec | dva sloupce | jako počítač |
| Navigace | pod logem | vpravo | jako počítač |
| Dotyk/kurzor | 44 px | najetí | dotyk |
| Formuláře | jeden sloupec | jeden sloupec | jako počítač |
| Systémové okraje | žádné | - | - |
| Gesta | žádná | žádné | - |

## Výjimky

- žádné (brána /aid-ui bez otevřených výjimek)

## Vynucení

- Každý build projde bránou /aid-ui (`aid-ui-verify.sh`), kontroly: `http_200`, `glyph_coverage`, `no_overflow`, `one_line_controls`, `no_placeholders`, `facts_match`, `brand_assets`, `links_resources`, `required_files`, `axe`, `image_weight`, `lighthouse_mobile`, `seo`, `brand_package`, `design_standard_doc`, `ai_search`, `app_task_states`, `no_overlap`, `brand_consistency`, `page_weight`, `business_minimum`, `screenshots_reviewed`.
- Hodnoty jen z tokenů `DESIGN.md`; nová varianta komponenty se nejdřív zapíše sem a do `DESIGN.md`.
- Po každé větší úpravě vzhledu se web znovu změří (`aid-ui-tool.sh measure`) a tento dokument se vygeneruje znovu.
- Druh projektu: web.
