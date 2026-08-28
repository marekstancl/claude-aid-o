---
sidebar_position: 10
title: Artefakty — jak AID plní ekosystémový standard
description: "Šablona artifact-outcome.html, mapování na sedm bloků standardu, gramatika placeholderů, stropy vynucené v kódu a redakce tajemství."
status: published
owner: AID
created: 2026-08-12
updated: 2026-08-12
---

# Artefakty v AID

Tahle stránka je **projektový záznam** k obecnému
[standardu artefaktů](../../ecosystem/specs/artifact-standard.md). Standard říká,
jak má vypadat artefakt kdekoli v ekosystému; tady je, jak to dopadlo v AID —
který soubor je šablona, jak se plní, co v ní vynucuje kód a co zůstává na
člověku.

Přišlo to s plánem P080 (v2.85.0). Jeden odstavec na úvod, ať je hned jasné, co
tu čtete: AID **vyrábí tělo stránky deterministicky ze zaznamenaných dat**.
Publikaci — tedy volání nástroje Artifact — dělá řídicí agent živě. Žádný skript
v AID netvrdí, že stránka vznikla.

## Co je čím

| Soubor | Role |
|---|---|
| `defaults/templates/artifact-outcome.html` | obecná šablona těla artefaktu (jen tělo — `<!doctype>`, `<head>` a `<body>` dodává nástroj Artifact) |
| `scripts/lib/aid-artifact-render.sh` | jediný vstupní bod, který šablonu plní: `aid_artifact_render <template_id> <facts_json> <prose_json> <out_path>` |
| `scripts/lib/aid-gate-outcome-summary.sh` | hranice bran — spočítá fakta z kanonického reportu bran a nechá tělo vykreslit |
| `scripts/lib/aid-plan-close-summary.sh` | hranice uzavření plánu — spočítá fakta ze dvou kanonických vstupů (PM brief + release decision) |
| `skills/communication.md` | čtyři karty do chatu, pořadí a věta o publikaci; šablona řeší stránku, tenhle soubor řeší zprávu |

Renderer je **čistá funkce** svých dvou JSON vstupů a šablony. Nečte stav běhu,
nic nedopočítává ze sousedních souborů a nepublikuje.

## Mapování na sedm bloků standardu

Standard předepisuje pevné pořadí bloků. Tohle je, čím je každý z nich v AID
naplněn a odkud se to bere.

| # | Blok standardu | Povinný | Čím ho AID plní | Zdroj dat |
|---|---|---|---|---|
| 1 | Hlavička | ano | název výstupu, čeho se týká (plán / EPIC / běh bran), časová značka | `facts_json` — spočítané volajícím z kanonického artefaktu |
| 2 | Dlaždice | ano | čtyři pevné sloty v pořadí **result / duration / scope / unresolved**, každý s `.label`, `.value` a `.state` (`ok\|warn\|critical`) | `facts_json`; dlaždice bez naměřené hodnoty vykreslí pomlčku, nikdy vymyšlené číslo |
| 3 | Shrnutí pro člověka | ano | `prose.summary`, omezené na 320 znaků | `prose_json` (text od modelu) |
| 4 | Jádro | ano | seznam výsledků (max 5) a „jak pokračovat" (max 3) plus `prose.core` (300 znaků) | `facts_json` pro seznamy, `prose_json` pro text |
| 5 | Odkazy na související | **jen když odkazy existují** | názvy, ne cesty; max 5 | `facts_json` |
| 6 | Co se čeká ode mě | ano, **vždy** | `prose.ask` (220 znaků); když se nečeká nic, vykreslí se doslovná věta *„Nic — ozvu se, až bude hotovo"* | `prose_json`, jinak deklarovaný literál |
| 7 | Odkaz na detail | **jen když je cíl detailu výslovný vstup** | jeden odkaz na konci | `facts_json`; knihovna cíl detailu **nikdy neodvozuje** |
| — | Patička s původem | vždy | který report byl vykreslen a **kolik hodnot bylo redigováno** | spočítáno rendererem |

Blok 6 se nevynechává ani tehdy, když se nic nečeká — tiše chybějící blok se čte
jako „ode mě se nic nechce", což je jiná informace než „nic se nečeká".

Mezi blokem 2 a 3 sedí ještě **poplach „shrnutí chybí"**: když text od modelu
nedorazil nebo nešel přečíst, stránka vyjde s dopočítanými čísly a řekne to
větou *„Shrnutí chybí — čísla výše jsou dopočítaná a platí."* Nevyjde
poloprázdná bez vysvětlení.

## Gramatika placeholderů

Šablona je HTML s třemi tvary zástupných značek. Dosazuje se **jedním
průchodem** — hodnota, která sama obsahuje `{{`, se už znovu nerozvíjí.

| Tvar | Odkud | Chybějící hodnota | Escapování |
|---|---|---|---|
| `{{fact:<jq.cesta>}}` | skalár z `facts_json` | pomlčka (`—`), nikdy vymyšlená hodnota | HTML-escapováno při vložení |
| `{{prose:<klíč>}}` | blok textu od modelu z `prose_json` | deklarovaný literál toho stavu | oříznuto po větách, pak po bloku, pak escapováno |
| `{{html:<klíč>}}` | fragment, který si staví knihovna sama (seznamy, odkaz na detail) | — | **jediný tvar vkládaný jako syrové HTML**; volající se k němu nedostane, nečte se z `facts_json` |

Podmíněné oblasti `<!--IF:jméno--> … <!--ENDIF:jméno-->` knihovna zachová nebo
odstraní vcelku. Existující oblasti: `prose_missing`, `items`, `next_steps`,
`links`, `detail`.

## Stropy vynucuje kód, ne prosba

Nejdůležitější věta celého standardu zní: *neříkej modelu „piš stručně"*. AID ji
bere doslova — stropy jsou konstanty v `aid-artifact-render.sh`, ne pokyn
v promptu.

| Co | Strop | Konstanta |
|---|---|---|
| Položek ve výsledcích | 5 | `_AID_ARTIFACT_CAP_ITEMS` |
| Kroků v „jak pokračovat" | 3 | `_AID_ARTIFACT_CAP_NEXT` |
| Souvisejících odkazů | 5 | `_AID_ARTIFACT_CAP_LINKS` |
| Znaků na větu | ~220 | `_AID_ARTIFACT_CAP_SENTENCE` |
| Znaků v `prose.summary` | 320 | `_AID_ARTIFACT_CAP_SUMMARY` |
| Znaků v `prose.core` | 300 | `_AID_ARTIFACT_CAP_CORE` |
| Znaků v `prose.ask` | 220 | `_AID_ARTIFACT_CAP_ASK` |

**Přetečení není nikdy tiché.** Vykreslí se věta *„a dalších N v technickém
detailu"* se skutečným zbývajícím počtem — useknutý seznam se čte jako useknutý,
ne jako celý příběh.

Čísla se **počítají, netvrdí**: dlaždice, počty a trvání se odvozují ze vstupního
JSON. Když v datech číslo není, je tam pomlčka.

## Tajemství: rediguj, počítej, nepadej

Standard zakazuje hesla, tokeny, klíče **a jejich části** v jakémkoli artefaktu.
Pole `output` u bran nese libovolný výstup příkazu přímo z běhu, takže escapování
samo o sobě není politika.

Každý vstup, který knihovna vykresluje — `facts_json`, `prose_json` i výstup
příkazu v nich zabalený — se prohledá **dřív, než se zapíše jediný bajt**. Nález
se **rediguje** (`<redacted:JMÉNO>`), nepadá se na něm: fail-closed v prezentační
vrstvě by spolkl právě tu zprávu, která říká, že se běh rozbil. Redakce se ale
**počítá a počet se vykreslí v patičce**, takže nikdy není tichá. Escapování se
aplikuje **až po** redakci, ne místo ní.

Že to platí, se dokazuje, ne tvrdí: testovací sada nese fixture se schválně
vloženými řetězci ve tvaru tajemství (všechny syntetické) a kontroluje stránku,
kartu i **záložní** kartu.

## Jak přidat novou šablonu

1. Přidejte `defaults/templates/artifact-<id>.html`. Tělo, žádný `<!doctype>`,
   `<head>` ani `<body>`; veškeré CSS inline — obsah blokuje přísné CSP, takže
   nesmí přibýt žádné externí `src=`, `@import` ani odkaz na cizí origin.
2. Držte pořadí sedmi bloků. Šablona mění **obsahové sloty**, nikdy rozvržení.
3. Nová data berte přes `{{fact:…}}` nebo `{{prose:…}}`. `{{html:…}}` je vyhrazený
   knihovně — volající do něj nesmí dosáhnout.
4. Nový strop patří jako konstanta vedle stávajících, ne jako věta v promptu.
5. Přidejte případ do `scripts/tests/bats/test-aid-artifact-render.bats`
   (pořadí bloků, chybějící próza, přetečení, escapování) a fixture do
   `scripts/tests/fixtures/handoff/` s golden souborem pořadí bloků.
6. Vykreslení **nikdy nepublikuje**. Publikaci zapojte na místě volajícího a
   doslovnou větou z `skills/communication.md` — `test-communication-wiring.sh`
   ji hlídá znak po znaku.

## Co tahle vrstva nedělá

- **Nepublikuje.** Renderery zapisují soubor a tisknou kartu. Volání nástroje
  Artifact je živý úkon řídicího agenta, zapojený v `commands/*.md` a
  `skills/pipeline.md`.
- **Nedopočítává ze sousedních důkazů.** Renderer hranice plánu čte přesně dva
  vstupy a nic dalšího — jmenuje cestu k reportu bran, ale neotevře ho.
- **Netvrdí dokončení z tvrzení delegovaného agenta.** Karta i stránka čtou jen
  kanonický verdikt řídicího agenta.

## Kde to hlídá stroj

| Kontrola | Co drží | Patro |
|---|---|---|
| `test-aid-artifact-render.bats` | pořadí bloků, stropy, přetečení, escapování, redakce | t1 (cesta k merge) |
| `test-communication-wiring.sh` | doslovná věta o publikaci u každého volajícího rendereru | t0 (cesta k merge) |
| `test-integration-handoff-rendering.sh` | tři renderery přes pět případů doručení, golden pořadí bloků | t2 (jen noční) |

Všechny tři jsou zapsané v registru vynucení (`artifact_template_caps`,
`artifact_secret_redaction`, `artifact_publication_wiring`,
`handoff_renderer_contract`) — každá se svým patrem, takže je z registru vidět,
která z nich merge opravdu blokuje a která ne.

## `{{prose:deliverables_heading}}` — the deliverables block's own heading

The block that lists what was produced carries a heading that follows the
`artifact_type`, because the same words cannot describe a promise and a result:

| `artifact_type` | heading |
|---|---|
| `plan` | Co plán dodá |
| `epic_done` | Co EPIC dodal |
| `plan_done` | Co plán dodal |

The template holds `{{prose:deliverables_heading}}`; `lib/aid-artifact-render.sh`
resolves it from the type before substitution. A producer supplies nothing for
it — it is derived, never passed — and a template that hard-codes one of the
three strings would print a plan's promise over a finished EPIC's result
(the state before 2026-08-28).

`deliverables` itself is required by the `plan`, `epic_done` and `plan_done`
profiles: a finished page that cannot say what it produced does not render.
