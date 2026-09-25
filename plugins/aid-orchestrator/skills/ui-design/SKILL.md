---
name: ui-design
description: Seven steps of /aid-ui - product type, references, a PM-chosen Impeccable direction, build, standard and verification, collected on the project's brand page
user_invocable: false
---

# ui-design

**Last Updated:** 2026-09-25

Vede PM od typu produktu přes výběr vizuálního směru z nalezených vzorů až po
postavený a ověřený vzhled; každý výsledek skládá do statické brand stránky
projektu (`<project>/docs/brand/`). Směr vybírá vždy PM na stránce Impeccable;
bez jeho zaznamenané odpovědi kroky 4-6 neběží (vynucuje `aid-ui-state.sh`,
ne jen tento text). Specifikace: `docs/plans/2026-09-24-aid-ui-skill-design.md`.

---

## When to Invoke

- `/aid-ui [step]` (`commands/aid-ui.md`) - jediný vstup.

Do NOT invoke for:

- běhy AIDu (`/aid-run`, `/aid-plan`, `/aid-do`) - skill se do nich nezapojuje;
- backend, hosting, 3D, video; animace jen v kódu (Impeccable `animate`).

---

## Hranice

- Nezapojuje se do běhů AIDu; nic sám veřejně nevystavuje ani neposílá.
- Neobchází blokace galerií; cizí screenshoty nejdou do gitu ani zákazníkovi.
- Impeccable vlastní výběrové kolo, stránku výběru, `PRODUCT.md`, `DESIGN.md`
  a `.impeccable/`; `docs/design/brand-state.json` na ně jen odkazuje.

## Start (každé spuštění)

1. Projekt = kořen repa, ve kterém PM `/aid-ui` volá (`git rev-parse --show-toplevel`).
2. Impeccable:
   ```bash
   IMP="$(jq -r '.plugins["impeccable@impeccable"][0].installPath' ~/.claude/plugins/installed_plugins.json)/skills/impeccable/scripts/impeccable"
   ```
   Chybí (`null`, soubor neexistuje) → stop, řekni PM: `/plugin install impeccable@impeccable`.
3. Prohlížeč - skutečné volání, ne jen existence nástroje:
   `mcp__plugin_playwright_playwright__browser_navigate` na `about:blank`.
   Selže (nástroj chybí, prohlížeč nejde spustit) → zkus Node Playwright
   (`node -e "require.resolve('playwright')"` nebo `@playwright/test`, z pluginu či projektu,
   a `npx playwright --version`) a řekni PM, že snímky půjdou přes Node Playwright:
   `node <plugin>/lib/ui-fidelity/ui-capture.mjs` z kořene projektu, jinak stejně.
   Nejde ani jedno → stop, řekni PM: `/plugin install playwright@claude-plugins-official`;
   když MCP nestartuje (hledá značkový Chrome), do `env` v `~/.claude/settings.json` dát
   `PLAYWRIGHT_MCP_BROWSER=chromium` (platí od další session) a pustit
   `npx @playwright/mcp install-browser chrome-for-testing` (bez sudo, do `~/.cache/ms-playwright`).
   Krok identity (1i) MCP potřebuje; bez něj skill nabídne ruční náhradu.
4. Ekosystémové standardy čti živě z `/opt/eco/docs/docs/ecosystem/…`
   (`specs/design-system-standard.md`: checklist, platformy, „Kontrola před nasazením"). Chybí-li některý, jmenuj ho
   PM a poznamenej to v kapitole, které se týká.

## Směrování

- Bez argumentu: krok = `jq .step <project>/docs/design/brand-state.json` (soubor
  chybí → krok 0).
- `/aid-ui <n>`: nejdřív `aid-ui-state.sh step <project> <n>`. Kroky 4-6 skript
  odmítne bez zaznamenaného směru a jmenuje krok 3 - řekni to PM a pokračuj
  krokem 3, ne `n`.
- Načti jen `steps/<n>-*.md` a proveď ho. Po úspěchu kroků 0-5
  `aid-ui-state.sh step <project>` s číslem následujícího kroku; po kroku 6
  `aid-ui-state.sh finish <project>` - tím běh končí (kroku 7 není).
- `brand-state.json.finished` vyplněné → řekni PM, že běh je hotový, a nabídni
  krok k opakování (`/aid-ui <n>`; krok zpět vynuluje `finished`, schválení
  jeho kapitol zruš `aid-ui-state.sh reset-approvals`).
- Selže skript: ukaž PM jeho řádek `ERROR:`, krok neposouvej.
- Otevřené kolo (`require-direction` vypíše URL a klíč): znovu otevři TO kolo,
  nezakládej nové. `aid-ui-serve.sh forward <p>` (když neběží), dej PM URL
  a klíč a ukonči tah. Na další zprávu PM („vybráno" nebo cokoli)
  `await-direction` se stejným klíčem - převezme odpověď. Hned po znovuotevření
  ho nevolej: po zavření stránky vrací hned „stránka zavřena".

Skripty (`$AID_PLUGIN_PATH/scripts/`): `aid-ui-state.sh` (jediný zapisovatel
`docs/design/brand-state.json` a stavů, těl kapitol a odkazů na písma v `docs/brand/index.html`), `aid-ui-serve.sh`, `aid-ui-design-to-css.sh`.

## Typ produktu → režim Impeccable

| Typ | Režim | Vzory | Ukázky |
|---|---|---|---|
| presentation | persuade | weby | stránky |
| webapp | operate | aplikace | obrazovky a toky |
| mobile | operate + reference ios/android | aplikace (Mobbin) | obrazovky v rámu telefonu |
| combo | po plochách | obojí | obojí |

## Zprávy PM

Formát podle `/opt/eco/CLAUDE.md` „Jak agent píše Markovi": česky, lidsky,
jedno rozhodnutí = jeden blok s možnostmi a doporučením.

---

## MUST Rules

1. Every choice the PM makes in /aid-ui (direction, build path, composition,
   slogan, logo, pages) is the PM's, never the agent's; the direction round and
   any composition round never close without the PM's answer. `serve-question --wait` `exit 4` or any "proceed unattended" path
   means: `aid-ui-state.sh pending-direction`, give the PM the URL and key, end
   the turn. This rule overrides Impeccable's unattended fallback.
2. Impeccable always runs with `IMPECCABLE_QUESTION_FORCE=1`, and the PM gets
   the URL printed by `aid-ui-serve.sh forward`, never `127.0.0.1`.
3. In a non-interactive or automated run, steps 2 and 3 do not start.
4. Gallery blocks (403/429/captcha) are never bypassed. Third-party screenshots
   live only in `<project>/.aid-ui/refs/` and the visual-companion session
   directory (`.aid-o/work/companion/`), both gitignored and outside the served
   `docs/brand/`, and are deleted after step 3.
5. `docs/design/brand-state.json` is written only by `aid-ui-state.sh` and points
   to Impeccable's files, never copies them. Chapter bodies are written only by
   `aid-ui-state.sh body <project> <id> --file <html>`, never by editing
   `docs/brand/index.html` by hand. Nothing internal lives in the served
   `docs/brand/` (only `index.html`, `*.css`, `assets/`, `fonts/`).
6. Ecosystem standards are read from `/opt/eco/docs/docs/ecosystem/…` on every
   run; a missing one is named and noted on the brand page.
7. The OpenAI key is read from `/opt/eco/services/.env` only into Impeccable's
   environment (`set -a; source <(grep '^OPENAI_API_KEY=' …); set +a` inside the
   command that starts Impeccable), never printed, logged or written anywhere.

---

## Completeness Gate

Před posunem kroku:

- [ ] skript kroku skončil 0 a `docs/design/brand-state.json` odpovídá (`jq`);
- [ ] každá kapitola, kterou krok mění, má tělo přes `aid-ui-state.sh body` a stav přes `aid-ui-state.sh chapter`;
- [ ] od kroku 4 prošel `aid-ui-state.sh require-direction`;
- [ ] PM dostal výsledek v chatu a odkaz na brand stránku (`aid-ui-serve.sh brand docs/brand`);
- [ ] v `docs/brand/` není nic cizího (screenshoty galerií jen v `.aid-ui/refs/`).

---

## Reference Files

- `steps/0-start.md` … `steps/6-verify.md` - postup kroků.
- `references/genericity-rubric.md` - vyřazení generických vzorů.
- `brand-page/` - šablona brand stránky a `state.template.json`.
- `skills/visual-companion/SKILL.md` - obrazovka šesti karet (sekce o vzdáleném hostu).
- `lib/ui-fidelity/ui-capture.mjs`, `scripts/lib/aid-ui-proposal.sh` (`aid_ui_proposal_viewports`).

**Last Updated:** 2026-09-25
