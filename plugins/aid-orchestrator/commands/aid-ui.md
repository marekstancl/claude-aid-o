---
name: aid-ui
description: Guide the PM from product type to a built, verified UI whose direction the PM chose, collected on the project's brand page
user_invocable: true
---

# /aid-ui - UI From Product Type to Approved Brand Page

Six steps as the PM sees them on the studio page, each with its parts in order and, for every
step and part, why it is done, its goal, what it feeds later and what the PM does - all from one map,
`skills/ui-design/sections.json`: 1 Druh webu, 2 Zadání a obsah (Podklady, Vize a slogany, Logo,
Hledání na Googlu, Stránky a jejich části, Obsah stránek), 3 Vzory, 4 Vzhled, 5 Stavba, 6 Kontrola
(Kontrola textů, Technická kontrola, Pravidla vzhledu, Schválení stránek, Předání). The internal step
files (0-7, 1p/1v/1i/1s) are routing only and never named to the PM (table in
`skills/ui-design/SKILL.md`). The agent finds the references, the PM picks, three directions are
dealt as real pages and the PM chooses one; building and checking refuse to run without that
recorded choice. Every PM choice is recorded the same way as the direction.

Copy (P108): step 2 Zadání a obsah starts with Podklady - the project's files, an old site and the PM's
documents the PM names and Claude Code sessions, approved once as a list, become one product context
shown to the PM as one draft; a question on facts always offers three answers taken from the adopted
methods, the first recommended. Vision, content plan and page copy
are written by the adopted marketing methods (`skills/ui-design/references/adopted/marketingskills/`,
MIT) and the language guides; step 6 Kontrola has every page's copy reviewed by an independent model
(Codex; a Claude stand-in only when the Codex run fails or gives no answer), the verdict computed by
a script and checked by the gate row `copy_review`; the PM then gives a verdict on the copy itself
(question `copy_verdict`).

## Arguments

```
/aid-ui [step]
```

- **`step`** - číslo kroku, jak ho vidí PM: `1`-`6` (Druh webu, Zadání a obsah, Vzory, Vzhled, Stavba, Kontrola; mapa `skills/ui-design/sections.json`); default: continue from `<project>/docs/design/brand-state.json`
  (no file → step 1). Step 6 ends with `aid-ui-state.sh finish`. A jump goes through `aid-ui-state.sh step`
  with the internal number, which refuses building and checking without a recorded direction.

## What it does

Load `skills/ui-design/SKILL.md` and follow it: start checks (Impeccable,
Playwright MCP), routing to `skills/ui-design/steps/<n>-*.md`, MUST Rules.

## The studio page

Every PM choice and approval happens on the project's studio page, which shows the run as
six steps in order, each with its outcome in one sentence and who decided it (PM, AI or both).
Detail opens a step's decisions in the order they were made and the cards the PM chose from;
an open question sits inside its step and is answered there. Decisions the agent makes alone
are recorded with `aid-ui-state.sh decide` and appear in the same list, marked AI.

## Reads / Writes

- **Reads (target project):** `PRODUCT.md`, `DESIGN.md`, `.impeccable/`,
  `docs/design/*brand-package*`, `docs/design/brand-state.json`,
  `docs/product-vision.md`, `docs/design/brief-logo-favicon.md`, `docs/seo/`,
  `docs/content/product-context.md`, `docs/content/facts.yaml`, documents the PM named
  (`aid-ui-sources.py --from`, read into redacted snapshots) and Claude Code session logs of the
  project (`~/.claude/projects/<project>/`), used only after ONE approval of the listed sources
  (`sources` answer on `manifest@<sha>`, step 1p; the text snapshots are deleted with
  `aid-ui-sources.py <project> --purge` once the product context is approved);
  ecosystem standards and templates from the plugin's copies (`skills/ui-design/references/standards/`).
- **Writes (target project):** `docs/design/brand-state.json`, chapter bodies and
  statuses in `docs/brand/index.html` (both only through `scripts/aid-ui-state.sh`),
  other `docs/brand/*`, `.aid-ui/`, `.aid-o/work/companion/`,
  `docs/design/design-standard.md`, `docs/product-vision.md`,
  `docs/design/brief-logo-favicon.md`, `docs/design/brand-package/`,
  `docs/seo/`, `docs/content/product-context.md`, `docs/content/facts.yaml`, `.aid-ui/sources/`, `.aid-ui/copy/`,
  `.gitignore`; Impeccable writes its own `PRODUCT.md`,
  `DESIGN.md`, `.impeccable/`.
- **Plugin scripts:** `aid-ui-design-to-css.sh`, `aid-ui-serve.sh`, `aid-ui-state.sh`,
  `aid-ui-ico.py`, `aid-ui-seo-check.py`, `aid-ui-sources.py`, `aid-ui-copy.py`,
  `aid-ui-verify.sh --copy-subject`; `skills/ui-design/references/brand-icons.js`
  (run through the Playwright MCP).

## Handover to plan and run (P115)

The studio ends with one package, `docs/ui/predani.json` (+ `predani.md`), written by the
handover (`aid-ui-state.sh chapter-all`; an incomplete or stale package refuses the handover).
`python3 "$AID_PLUGIN_PATH/scripts/aid-ui-package.py" zadani docs/ui/predani.json --plan-id P<NNN>` turns it into the deployment
brief that `/aid-plan` writes the plan from; the run gate `check_ui_handover` then lets through
only the handed-over files with no critical item open; `aid-ui-quality.py launch` rates the live
web in its own loop. Detail: `skills/ui-design/SKILL.md`, section Předání.

## Relationship

The studio itself runs outside the FSM: no AID run calls it. It hands over to `/aid-plan` and
`/aid-run` through the package above and nothing else.

**Last Updated:** 2026-10-18
