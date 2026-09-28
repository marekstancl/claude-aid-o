---
name: ui-design
description: Steps of /aid-ui - variant, product (vision, logo, SEO), structure, content plan, references, three directions as real pages, build and verification, every PM choice on the studio page
user_invocable: false
---

# ui-design

**Last Updated:** 2026-09-28

Vede PM od varianty produktu přes produkt, strukturu, obsahový plán, vzory
a tři směry jako skutečné stránky až k postavenému a ověřenému webu nebo
aplikaci; výsledky skládá do brand stránky projektu (`<project>/docs/brand/`).
Každou volbu a každé schválení dělá PM na stránce studia; bez zaznamenané
odpovědi se nic nerozhodne (vynucuje `aid-ui-state.sh`, ne jen tento text).

---

## When to Invoke

- `/aid-ui [step]` (`commands/aid-ui.md`) - jediný vstup.

Do NOT invoke for:

- běhy AIDu (`/aid-run`, `/aid-plan`, `/aid-do`) - skill se do nich nezapojuje;
- backend, hosting, 3D, video.

---

## Hranice

- Nezapojuje se do běhů AIDu; nic sám veřejně nevystavuje ani neposílá.
- Neobchází blokace galerií; cizí screenshoty nejdou do gitu ani zákazníkovi.
- Stav `docs/design/brand-state.json` píše jen `aid-ui-state.sh`.

## Start (každé spuštění)

1. Projekt = kořen repa, ve kterém PM `/aid-ui` volá (`git rev-parse --show-toplevel`).
2. Prohlížeč - skutečné volání: `mcp__plugin_playwright_playwright__browser_navigate`
   na `about:blank`. Selže → nástroje kroků běží přes `aid-ui-tool.sh` (Node
   Playwright, sám si doinstaluje `lib/ui-fidelity`); řekni to PM. Krok 1i
   (ikony) a krok 4 (vzory) MCP potřebují; bez něj stop s pokynem
   `/plugin install playwright@claude-plugins-official` (MCP hledá značkový Chrome →
   `PLAYWRIGHT_MCP_BROWSER=chromium` do `env` v `~/.claude/settings.json`
   a `npx @playwright/mcp install-browser chrome-for-testing`).
3. Standardy čti živě, nikdy z kopie: `/opt/eco/docs/docs/ecosystem/specs/`
   (`frontend-build-standard.md` FB-1..FB-20, `webapp-tasks-states-standard.md`
   UA-1..UA-11, `design-system-standard.md`, SEO standard). Chybí některý →
   jmenuj ho PM a poznamenej v kapitole, které se týká.
4. Postup stavby: `references/adopted/frontend-design-SKILL.md` (snímek
   frontend-design) a řemeslné minimum `references/adopted/impeccable-craft-floor.md`;
   generické vzory vyřazuje `references/genericity-rubric.md`.

## Jak se ptá PM (studio)

Jediný způsob, jak se PM na cokoli ptát nebo mu dát cokoli ke schválení:

1. Zapiš nebo obnov `<project>/.aid-ui/studio/payload.json`:
   `steps[]` (`id`, `title`, `status` done|current|todo), `questions[]`
   (`id`, `kind`, `target`, `opened_at` = teď v ISO, `title`, `prompt`, `body`),
   `cards[]` (`id`, `question`, `title`, `preview` = PNG/JPEG/WebP pod
   `.aid-ui/studio/`, `thesis`, `palette[]`, `risk`, `uniqueness`).
   Druhy otázek: variant, vision, identity, seo_brief, structure, task_map,
   content_plan, defer_content, facts, references, direction, approve_page,
   exception, coverage_drift, design_standard.
2. `target` je to, co PM schvaluje: u `set variant|options|structure|content-plan|refs`
   `sha256:` + `jq -S -c -j . <<<"$json" | sha256sum` přesně toho JSON, který
   pak zapíšeš (JSON vždy v souboru pod `.aid-ui/` psaném nástrojem Write,
   do příkazu jako `"$(cat <soubor>)"`); u převzetí kapitoly
   `aid-ui-state.sh chapter-target <project> <id>`; u ostatních druhů podle
   hlavičky `aid-ui-state.sh`.
3. `aid-ui-serve.sh studio <project>` (spustí nebo použije běžící studio)
   vypíše jednorázový odkaz `URL: http://<host>:3915/?k=<kód>`; ten dej PM
   a **ukonči tah**. Každé další spuštění dá nový odkaz.
4. Na další zprávu PM `aid-ui-state.sh record-answer <project> --question <id>`.
   Exit 1 = odpověď ještě není; dej PM odkaz znovu a ukonči tah.
5. Rozhodnutí `approve`/`choose` → mutace s `--answer <id>` (jen tam, kde
   krok nějakou jmenuje). `return` → PM vrací s komentářem; oprav a otevři
   otázku znovu (nové `opened_at`). `reroll_safer`/`reroll_bolder` → odpověď
   nese `next_question`; vytvoř nové karty podle komentáře a zapiš je pod tím
   id do payloadu.

## Směrování

- Bez argumentu: krok = `jq .step <project>/docs/design/brand-state.json` (soubor
  chybí → krok 0).
- `/aid-ui <n>` → `aid-ui-state.sh step <project> <n>`, pak ten krok.
- Načti jen soubor kroku a proveď ho. Po úspěchu kroků 0-6
  `aid-ui-state.sh step <project>` s číslem následujícího kroku; krok 7 končí
  `aid-ui-state.sh finish <project>`.
- `brand-state.json.finished` vyplněné → běh je hotový; nabídni krok
  k opakování (`/aid-ui <n>`; krok zpět vynuluje `finished`).
- Selže skript: ukaž PM jeho řádek `ERROR:`, krok neposouvej.

| Krok | Soubor |
|---|---|
| 0 | `steps/0-start.md` - varianta, inventura, kontrola pokrytí |
| 1 | `steps/1-product.md` (+ `steps/1v-vision.md`, `steps/1i-identity.md`, `steps/1s-seo.md`) |
| 2 | `steps/2-structure.md` - stránky, role, toky |
| 3 | `steps/3-content-plan.md` - obsah a fakta |
| 4 | `steps/4-references.md` - vzory |
| 5 | `steps/5-directions.md` - tři směry jako stránky |
| 6 | `steps/6-build.md` - stavba |
| 7 | `steps/7-verify.md` - ověření, schválení, `finish` |

Skripty (`$AID_PLUGIN_PATH/scripts/`): `aid-ui-state.sh` (jediný zapisovatel
stavu a těl kapitol v `docs/brand/index.html`), `aid-ui-serve.sh`,
`aid-ui-coverage.sh`, `aid-ui-tool.sh` (`glyph`, `webp`, `verify`),
`aid-ui-design-to-css.sh`, `aid-ui-ico.py`.

## Zprávy PM

Formát podle `/opt/eco/CLAUDE.md` „Jak agent píše Markovi": česky, lidsky,
jedno rozhodnutí = jedna otázka ve studiu s doporučením; chat nese shrnutí
a odkaz.

---

## MUST Rules

1. Never without the PM: every choice and approval (variant, vision, slogan,
   logo, SEO pages, structure, content plan, references, direction, pages,
   exceptions) is the PM's. A missing answer ends the turn with the studio
   link; no step proceeds unattended and no step writes state directly.
2. Answers come only through `aid-ui-state.sh record-answer`, and a mutation
   that needs the PM takes `--answer <id>`; an answer read from chat is never
   a decision.
3. Ecosystem standards are read live from `/opt/eco/docs/docs/ecosystem/…` on
   every run; a missing one is named to the PM and noted on the brand page.
4. The build follows the frontend-design snapshot
   `references/adopted/frontend-design-SKILL.md`; no other design tool.
5. No invented facts (prices, addresses, references, numbers, quotes): a fact
   comes from the PM or the project and is listed in `docs/content/facts.yaml`.
   No placeholders (lorem ipsum, "Váš text", fake logos) in anything the PM
   sees or the build ships; missing material goes through step 3.
6. Step 0 runs `aid-ui-coverage.sh check`; exit 1 or 2 stops the run.
7. Gallery blocks (403/429/captcha) are never bypassed. Third-party screenshots
   live only in `<project>/.aid-ui/refs/` (gitignored, outside `docs/brand/`)
   and are deleted after step 5.
8. Chapter bodies are written only by `aid-ui-state.sh body <project> <id> --file <html>`;
   nothing internal lives in the served `docs/brand/`.

---

## Completeness Gate

Před posunem kroku:

- [ ] každá otázka kroku má zaznamenanou odpověď (`jq .answers <state>`) a její mutace prošla;
- [ ] každá kapitola, kterou krok mění, má tělo přes `aid-ui-state.sh body` a stav přes `aid-ui-state.sh chapter`;
- [ ] PM dostal v chatu shrnutí a odkaz (studio nebo `aid-ui-serve.sh brand docs/brand`);
- [ ] v `docs/brand/` není nic cizího (screenshoty galerií jen v `.aid-ui/refs/`).

---

## Reference Files

- `steps/0-start.md` … `steps/7-verify.md` - postup kroků (tabulka výše).
- `references/adopted/frontend-design-SKILL.md`, `references/adopted/impeccable-craft-floor.md`.
- `references/genericity-rubric.md` - vyřazení generických vzorů a směrů.
- `references/brand-icons.js` - vykreslení ikon (krok 1i).
- `coverage/{map,checks,sources}.yaml` - pokrytí standardů.
- `brand-page/` - šablona brand stránky a `state.template.json`.

**Last Updated:** 2026-09-28
