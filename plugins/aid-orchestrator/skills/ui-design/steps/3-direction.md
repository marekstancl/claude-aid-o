---
name: ui-design-step-3
description: /aid-ui step 3 - pinned direction brief, Impeccable direction round, the PM's choice recorded by aid-ui-state.sh
user_invocable: false
---

# Krok 3 - Směr

**Last Updated:** 2026-09-24

## Cíl

PM vybral směr na stránce Impeccable a `aid-ui-state.sh` ho zaznamenal
z výstupu Impeccable. V neinteraktivním běhu se krok nespouští (MUST 3).

## Vstupy

Potvrzené vzory (`state.json.refs`), styly v `.aid-ui/refs/`, brand balíček,
zamítnuté návrhy s důvodem PM, `$IMP` (`SKILL.md` Start).

## Postup

1. Surface brief: `"$IMP" context --target <route>` vrací `surfaceBriefPath`;
   jinak `.impeccable/surfaces/<slug>.md` ve tvaru existujících briefů. Zapiš
   do něj směrové zadání: vybrané vzory a co z nich převzít, vytažené styly,
   brand, anti-reference (zamítnuté návrhy + důvod PM) a větu
   „PM vyžaduje výslovný výběr směru; bez odpovědi PM se nepokračuje."
   `aid-ui-state.sh set <project> impeccable.surface_brief '"<cesta>"'`.
2. Skill `impeccable` new-work s `IMPECCABLE_QUESTION_FORCE=1`; řekni mu:
   zastav po zamčení směru a zapsání `## Direction contract`, v tomto kroku
   nic nestav.
3. Impeccable vypíše `QUESTION URL: http://127.0.0.1:<p>/` a klíč →
   `aid-ui-serve.sh forward <p>` a PM dej JEHO URL a klíč.
4. `aid-ui-state.sh await-direction <project> --imp "$IMP" --key <k> --page-url <url>`
   (hned po kroku 3, stránka je otevřená):
   - exit 0 → směr zaznamenán;
   - exit 3 → PM chce „znovu": re-roll přes Impeccable (`--update` na stejném
     klíči) a znovu `await-direction`;
   - exit 1 s otevřeným kolem → MUST 1: dej PM URL a klíč, ukonči tah.
     Nikdy nepokračuj s přiděleným směrem.
   - Znovuotevření otevřeného kola: `aid-ui-serve.sh forward <p>` (když neběží),
     PM dej URL a klíč, ukonči tah. `await-direction` se stejným klíčem až na
     další zprávu PM („vybráno" nebo cokoli) - převezme jeho odpověď. Hned po
     znovuotevření ho nevolej: po zavření stránky končí okamžitě „stránka
     zavřena", dokud ji PM znovu neotevře.
5. Kapitola `smer`: vybraná karta (barevné čipy, teze) + odkaz na brief →
   `aid-ui-state.sh chapter <project> smer navrh`.
6. `aid-ui-serve.sh stop forward` (brand server běží dál).
7. Zastav server visual-companion z kroku 2 (poslouchá na `0.0.0.0`): pro každý
   `<project>/.aid-o/work/companion/*/` se souborem `.server.pid`
   `{plugin_path}/lib/brainstorm-server/stop-server.sh <ten adresář>`. Pak smaž
   `.aid-ui/refs/*.png` a obrázky session v `.aid-o/work/companion/`.

`document --seed` se tu nespouští: `DESIGN.md` píše dokumentátor Impeccable
po stavbě (krok 4), takže se neotevře druhé kolo směru.

## Co PM rozhoduje

Směr na stránce Impeccable (případně „znovu").

## Zápis

`state.json.direction` jen přes `await-direction`; `impeccable.surface_brief`;
kapitola `smer`.

## Když krok selže

`serve-question` odmítne start nebo `await-direction` skončí jinou chybou →
ukaž `ERROR:` PM; směr se nezaznamená a krok 4 neběží.

**Last Updated:** 2026-09-24
