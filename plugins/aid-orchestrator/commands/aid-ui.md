---
name: aid-ui
description: Guide the PM from product type to a built, verified UI whose direction the PM chose, collected on the project's brand page
user_invocable: true
---

# /aid-ui - UI From Product Type to Approved Brand Page

Seven steps (0 start, 1 product, 2 references, 3 direction, 4 build,
5 standard, 6 verify). The agent finds the references, the PM picks, Impeccable
deals directions and the PM chooses one on Impeccable's page over the VPN.
Steps 4-6 refuse to run without that recorded choice. Step 0 offers four
optional parts with a recommendation - vision and slogans, identity, SEO, image
comps; vision, identity and SEO run inside step 1 (1v, 1i, 1s) before the
references, and the SEO check joins step 6. Every PM choice in them (slogan,
logo, page list, composition) is recorded the same way as the direction.

Copy (P108): step 1 starts with Podklady (1p) - the project's files, an old site and the PM's
own Claude Code sessions the PM approves on the studio page become one product context, and the
PM is asked only about what is missing, contradictory or stale. Vision, content plan and page copy
are written by the adopted marketing methods (`skills/ui-design/references/adopted/marketingskills/`,
MIT) and the language guides; step 7 has every page's copy reviewed by an independent model
(Codex; a Claude stand-in only when the Codex run fails or gives no answer), the verdict computed by
a script and checked by the gate row `copy_review`; the PM then gives a verdict on the copy itself
(question `copy_verdict`).

## Arguments

```
/aid-ui [step]
```

- **`step`** - `0`-`6`; default: continue from `<project>/docs/design/brand-state.json`
  (no file → step 0). After step 6 the flow ends with `aid-ui-state.sh finish`. A jump goes through `aid-ui-state.sh step`, which refuses
  4-6 without a recorded direction and names step 3.

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
  `docs/content/product-context.md`, `docs/content/facts.yaml`, Claude Code session logs of the
  project the PM approved (`~/.claude/projects/<project>/`, step 1p);
  ecosystem standards under `/opt/eco/docs/docs/ecosystem/`.
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

## Relationship

Outside the FSM: no AID run, no EPIC, no gate. `/aid-run`, `/aid-plan` and
`/aid-do` never call it.

**Last Updated:** 2026-09-30
