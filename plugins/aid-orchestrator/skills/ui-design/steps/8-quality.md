---
name: ui-design-step-8
description: /aid-ui after finish - the quality loop: a frozen independent critic rates the web, the agent triages and fixes its findings, three blind ratings close it
user_invocable: false
---

# Po předání - smyčka kvality

**Last Updated:** 2026-10-12 (P113a)

## Cíl

Web dosáhne u nezávislého kritika přijatelné známky (dnes 8/10, žádné kritérium pod 7) a tři slepá
hodnocení ji potvrdí. Cíl je vždy 10/10: po dosažení přijatelné známky se pokračuje, dokud se zlepšuje.
Práh zná jen kód (`aid-ui-critic.py`), kritik ho nezná a nevidí ani minulé známky.

PM do smyčky nevstupuje. Vidí ji ve studiu v panelu Hotovo („Hodnocení nezávislého kritika“) a dostane
zprávu jen při zastavení (rozpor nálezů, stagnace, strop kol) a na konci.

## Vstupy

Hotový běh (`aid-ui-state.sh finish` prošel), živý web (`.aid-ui/links.json` → `web`), produktový kontext
(`docs/content/product-context.md`, `docs/product-vision.md`, `docs/seo/brief.md`).

## Postup

1. **Zmraz kritika** (jednou na projekt): `aid-ui-critic.py freeze <project> --type web-local`. Role se
   složí z měřítka typu (`critic/web-local.yaml`: kritéria, váhy, kotvy 4/6/8/10) a kontextu projektu;
   řádky kontextu, které mluví o známkách nebo přijetí, se vyřadí. Jakmile smyčka má kolo, měřítko
   už nejde změnit.
2. **Kolo:** `aid-ui-quality.py round <project> --web <url>`. Před kolem musí projít
   `aid-ui-state.sh gate-check` (web je zaznamenaný build a brána nad ním nemá nepokrytý řádek).
   Kritik (`aid-ui-client.py critic`) dostane jen kopii webu, snímky každé stránky na 1440 a 390 px
   a zmrazenou roli. Codex na předplatném, při limitu, prázdné nebo dvakrát neplatné odpovědi záskok
   Claude se stejným zadáním; text nikdy přes placené API.
3. **Roztřiď každý nález** (`aid-ui-quality.py triage <project> <id> <stav>`):
   - `accepted --expected "<co se zlepší>"`,
   - `rejected_with_reason --reason`,
   - `duplicate --of <id>`,
   - `blocked --reason`: s `--conflict-with <id>`, když oprava jednoho zhorší druhé. Smyčka se tím zastaví a rozhoduje PM.
   - `superseded --reason`.
   Nálezy vlastníka `client` (fotky, právník, IČO) jsou rovnou `blocked` a patří do připravenosti,
   ne do známky.
4. **Oprav přijaté** stejnou cestou jako v kroku 6 a 7: zdroj webu, přestavba, `build-record`, brána,
   `gate-record`; při změně textů kontrola textů. Každou opravu zapiš:
   `aid-ui-quality.py fixed <project> <id> --evidence "<co se změnilo a kde>"`.
5. **Další krok říká** `aid-ui-quality.py status <project>`:
   - `triage`, `fix` a `round` znamenají pokračovat podle bodů 2 až 4,
   - `audit` znamená bod 6,
   - `stop:*` znamená zprávu PM s důvodem a stavem,
   - `done` znamená konec.
   Pravidla:
   - nejvýš 5 opravných kol;
   - zlepšení je +0,3 známky, nebo méně závažných nálezů a žádné kritérium níž;
   - dvě kola bez zlepšení znamenají stop.
6. **Audit:** `aid-ui-quality.py audit <project> --web <url>`. Jde o tři slepá hodnocení téhož webu,
   na kterém mezitím nic neměň. Přijato je při mediánu ≥ 8, žádném hodnocení < 7,5 a žádném kritériu < 7.
   Výsledek se zapíše do `.aid-ui/critic/verdict.json` včetně `publish_blocked_by`, tedy co musí dodat
   klient. Nepotvrzený audit vrací smyčku k opravám.

## Náklady

Každé volání modelu jde do knihy projektu `.aid-ui/costs.jsonl`. Předplatné se tam vede jako
ceníkový ekvivalent, placené API je jen obrazový model. Ten má strop 2 USD na projekt
(`AID_UI_IMAGE_BUDGET_USD`), hlídaný před každým obrázkem. Přehled vypíše
`aid-ui-client.py costs <project>`.

## Zápis

`.aid-ui/critic/` obsahuje:
- `frozen.json`,
- `rounds/<n>/round.json` a `rounds/<n>/critic/`, kde jsou zadání, snímky, odpověď a `run.json`,
- `audits/<otisk webu>/a1..a3/`,
- `loop.json`, tedy souhrn pro studio,
- `verdict.json`.

## Když krok selže

- Kritik nedal platné hodnocení od žádného poskytovatele: `run.json` říká proč. Kolo se nezapíše.
  Zkus to znovu později, Codex může mít vyčerpaný limit.
- Chybí snímek některé stránky: kritik nehodnotí. Ověř, že web běží (`aid-ui-serve.sh`).
- `stop:conflict`, `stop:stagnation`, `stop:round_cap`: zpráva PM podle „Jak agent píše Markovi“.
  Uveď známky po kolech, co bylo opraveno, co zbývá a možnosti A/B.
