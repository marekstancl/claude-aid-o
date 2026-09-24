---
name: aid-ui
description: Guide the PM from product type to a built, verified UI whose direction the PM chose, collected on the project's brand page
user_invocable: true
---

# /aid-ui - UI From Product Type to Approved Brand Page

Seven steps (0 start, 1 product, 2 references, 3 direction, 4 build,
5 standard, 6 verify). The agent finds the references, the PM picks, Impeccable
deals directions and the PM chooses one on Impeccable's page over the VPN.
Steps 4-6 refuse to run without that recorded choice.

## Arguments

```
/aid-ui [step]
```

- **`step`** - `0`-`6`; default: continue from `<project>/docs/brand/state.json`
  (no file → step 0). A jump goes through `aid-ui-state.sh step`, which refuses
  4-6 without a recorded direction and names step 3.

## What it does

Load `skills/ui-design/SKILL.md` and follow it: start checks (Impeccable,
Playwright MCP), routing to `skills/ui-design/steps/<n>-*.md`, MUST Rules.

## Reads / Writes

- **Reads (target project):** `PRODUCT.md`, `DESIGN.md`, `.impeccable/`,
  `docs/design/*brand-package*`, `docs/brand/state.json`; ecosystem standards
  under `/opt/eco/docs/docs/ecosystem/`.
- **Writes (target project):** `docs/brand/*` (`state.json` only through
  `scripts/aid-ui-state.sh`), `.aid-ui/`, `.aid-o/work/companion/`,
  `docs/design/design-standard.md`, `.gitignore`; Impeccable writes its own
  `PRODUCT.md`, `DESIGN.md`, `.impeccable/`.
- **Plugin scripts:** `aid-ui-design-to-css.sh`, `aid-ui-serve.sh`, `aid-ui-state.sh`.

## Relationship

Outside the FSM: no AID run, no EPIC, no gate. `/aid-run`, `/aid-plan` and
`/aid-do` never call it.

**Last Updated:** 2026-09-24
