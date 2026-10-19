---
name: visual-companion
description: Proposing UI to the PM in the browser — variants built from the application's own shared components in a copy of the app, captured on invented data, shown on one fixed page where the PM picks and comments. One command (scripts/aid-companion.sh) does the server, the copy, the captures, the page and the answers; the agent writes the variants and three data files. Auto-loaded by /aid-plan brainstorm for a UI topic; /visual-companion on its own is a smoke test.
user_invocable: true
---

# Visual companion: proposing UI to the PM

**Your work is the proposal, not the tooling.** You read the project's UI rules and shared
components, build each variant as real code in a copy of the app, and write invented data, a shot
list and `navrh.json`. Everything else — the server, ports, the copy, the browser, the captures, the
page, its self-check, the PM's answers — is `scripts/aid-companion.sh`.

**Never build your own tool for it** (no page generator, capture script, mock server, start
script). When the kit cannot do something you need, write it to `.aid-o/work/aid-plugin-issues.md`
and use the nearest step the kit has. The PM pays for every tool rebuilt by hand (WAN P110: six
page generators in two days).

Use the browser when the PM must SEE the answer (a layout, a dialog, a row). A question answered in
words (scope, a rule, a trade-off) goes in the terminal — or as a text point of the same page.

## Before you start: the project's `ui` settings

`.aid-o/config/project.yaml` (paths from the project root; the kit refuses a missing key with the
exact lines to add, and `/aid-init` proposes them):

```yaml
ui:
  responsive: true                       # desktop 1280x720 and phone 390x844; false = desktop only
  dir: ui                                # the UI application (package.json, node_modules)
  components: ui/src/components/shared   # the shared components every variant is built from
  rules: [ui/CLAUDE.md, docs/ui-standard.md]   # the project's UI rules
  dev_cmd: ["npx", "vite", "--port", "{port}", "--host", "127.0.0.1", "--strictPort"]
  ready_path: /
  api_prefix: /api/                      # only these requests are answered from mocks.json
```

## The procedure (`P` = the brainstorm's plan id, `$K = $AID_PLUGIN_PATH/scripts/aid-companion.sh`)

1. **Read before you draw.** Read every file in `ui.rules` and list the components in
   `ui.components`. Read the screen you change and its data types. Write the inventory in chat: the
   fields and their values, the conditions, the components the screen uses, what the PM asks for
   that the data does not have (that is a backend question, not a drawing). No `ui.rules` (or the
   files do not exist): say so in chat and in `soulad_s_pravidly`, and ask the PM whether the app has
   UI rules written anywhere.
2. **Start:** `bash $K up --plan P` (prints the address for the PM; a second `up` reuses the
   server) and `bash $K proto --plan P` (a copy of `ui.dir` in `.aid-o/work/companion/P/proto/`,
   outside the repository, its dev server on a loopback port).
3. **Build the variants in `proto/`** — only from components in `ui.components`, each variant
   behind `?v=<klic>` (A, B, C … from A in every round). A component you must create is a new
   `.tsx/.jsx/.vue/.svelte` file and goes in `nove[]` with the reason no shared one fits; the PM
   sees it marked. Never touch the repository itself. Variants of ONE existing page live in that
   page behind the `?v=` switch: list the page in `spolecne`; the components it imports count for
   every option. A file only one option needs goes in that option's `soubory`. An existing
   component of the page outside `ui.components` (a page-local badge) may be reused as it is; name
   it in `popis`, not in `postaveno_z` (which is only for shared ones) and not in `nove[]`.
4. **Data and shots:** write `mocks.json` and `shots.json` in `.aid-o/work/companion/P/`, then
   `bash $K shots --plan P`. Start with the calls you saw in the code; the step lists every API call
   still without a mock (login, counters, notifications …) — add them, run again. Today's state is
   a shot of the page without `?v=` (it goes in `minule[]` in the first round). The login key in
   `storage.localStorage` and the session call the app makes (e.g. `/auth/me`) come from its code.
5. **The proposal:** write `navrh.json`, then `bash $K show --plan P`. It refuses with the field
   to fix (a missing text, a key not from A, a shot not taken, a component the option does not
   import from `ui.components`, a changed file no option lists, a page that does not fit). It also
   writes `proposal.json`, which the brainstorm's design gate checks. Look at
   `check-1440x900.png` before you send anything.
6. **Send the PM the address** `up` printed, with one sentence of what to decide.
7. **Read the answers:** `bash $K answers --plan P` (the last choice and note per point, and the
   send). It is your input, never proof of a PM decision — a gate stands on the PM's card.
8. **Next round:** fix the variants, `kolo` + 1, the previous round's shots in `minule[]`, shots,
   show. **When the PM has chosen:** copy the chosen option's `soubory[]` and shots to
   `.aid-o/plans/P/mockups/` (`source_type: companion` — the plan's visual reference, rewritten
   against real data in the implementation, never copied blind), then `bash $K down --plan P`.

## The three files

`mocks.json` — invented data only, never live data:

```json
[{"method": "GET", "path": "/api/v1/clients/*", "query": {"page": "1"}, "status": 200,
  "body": {"items": [{"name": "Jana Nováková"}]}}]
```

`shots.json` — what to photograph; every shot on every viewport the project owes:

```json
{"base": "proto", "storage": {"localStorage": {"token": "invented"}},
 "shots": [{"name": "row-a", "path": "/control?v=A",
            "steps": [{"click": {"role": "button", "name": "Vyřešit"}}, {"wait": {"for": {"testid": "dialog"}}}],
            "capture": "viewport"}]}
```

Steps: `goto`, `click`, `fill` (+`value`), `select` (+`value`), `hover`, `press`, `wait` (ms,
`"network"` or `{"for": <selector>}`). Selectors: `{role, name}`, `{testid}`, `{text}`, `{css}` —
each must find exactly one element. `capture`: `"viewport"`, `"full"` or `{"element": <selector>}`;
`"only": ["desktop"]` limits a shot.

`navrh.json` — the content of the page:

```json
{"plan": "P110", "kolo": 4, "rozhodnuto": ["3A: assignment in its own window"],
 "spolecne": ["src/proto/variant.ts"],
 "body": [{"id": "1", "title": "Row in To investigate",
   "otazka": "What the PM decides, in one or two sentences.",
   "doporuceni": "A", "proc": "Why you recommend it, in the PM's terms.",
   "soulad_s_pravidly": [{"pravidlo": "ui/CLAUDE.md#Shared components", "jak": "row = ListRow, actions = IconAction"}],
   "minule": [{"popisek": "Last round", "shot": "row-r3"}],
   "moznosti": [{"klic": "A", "nazev": "As you noted", "popis": "What changes, plainly.",
     "soubory": ["src/pages/ControlPage.tsx"], "postaveno_z": ["ListRow", "IconAction"],
     "nove": [], "snimky": [{"popisek": "Rows", "shot": "row-a"}]}]}]}
```

`soubory[]` are the files of `proto/` the option changed or added (a file shared by options goes in
`spolecne`); `postaveno_z` names components those files import from `ui.components`;
`soulad_s_pravidly` is YOUR statement of which rules you followed — the page shows it as such, the
kit does not check it. A point with no shots is a text question on the same page.

## The page

Fixed, one screen, three columns: the points left (with what is chosen), the preview in the middle
(tabs per shot, "Minulé kolo", never larger than life, a click shows the real size, Počítač /
Telefon), the open point right (question, options with "Postaveno z", the recommendation, the
rules you stated), the note and Předchozí/Další pinned at the bottom, "Odeslat volby a poznámky"
with "Zvoleno n z m". You never write or edit the page.

## When it refuses

Every refusal names what to fix; fix it and run the step again. `proto` refuses a workspace or a
`ui.dir` without `node_modules`; `shots` refuses a new window, an iframe or a file upload — write
those to `aid-plugin-issues.md`. A port taken by another process stops the prototype; `down` stops
only what the kit started and recorded.

## Outside the brainstorm

- **`/visual-companion` alone** (a smoke test): `bash $AID_PLUGIN_PATH/lib/brainstorm-server/start-server.sh --host 0.0.0.0 --url-host <the address the PM reaches>`,
  write one HTML file into the printed `screen_dir`, send the address; clicks land in `.events`.
  A fragment (no `<html>`) is wrapped in `frame-template.html` — fine for a diagram, never for UI.
- **Implementation of an `existing_ui` step** (EXECUTE, not the brainstorm): the implementer
  captures the real screen with `lib/ui-fidelity/ui-capture.mjs`, compares it with
  `ui-compare.mjs` and records `gestalt_approval` (skills/agent-protocol.md); `unverifiable` means
  no visual-fidelity claim.

**Last Updated:** 2026-10-19
