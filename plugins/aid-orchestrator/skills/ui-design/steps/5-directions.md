---
name: ui-design-step-5
description: /aid-ui step 5 - three directions as real first-viewport pages with real content, logo and checked fonts, three cards on the studio page, re-roll safer or bolder
user_invocable: false
---

# Krok 5 - Tři směry

**Last Updated:** 2026-09-28

## Cíl

PM ve studiu vybral jeden ze tří směrů; každý byl skutečná první obrazovka
se skutečným obsahem, logem a písmy, která prošla kontrolou znaků.

## Vstupy

Vybrané vzory a styly v `.aid-ui/refs/`, brand balíček, vize a tón,
`structure`, `content_plan` a `docs/content/facts.yaml`,
`references/adopted/frontend-design-SKILL.md`, `references/genericity-rubric.md`.

## Postup

1. Tři směry, každý jako HTML první obrazovky domovské stránky (u aplikace
   hlavní obrazovky) v `.aid-ui/directions/<n>/`: skutečné texty z obsahového
   plánu a registru faktů, skutečné logo, žádný zástupný text (MUST 5).
   Směry se liší principem, ne odstínem.
2. Písma: kandidát nejdřív `aid-ui-tool.sh glyph --sample "<rodina>" "Příliš žluťoučký kůň úpěl ďábelské ódy"`;
   `FAIL` → jiné písmo. Hotová stránka: volný port
   `port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')`,
   `python3 -m http.server --bind 127.0.0.1 --directory <project>/.aid-ui/directions "$port" &`
   (zapamatuj `pid=$!`), `aid-ui-tool.sh glyph http://127.0.0.1:$port/<n>/`,
   pak `kill "$pid"`; exit 1 → oprav písmo, směr se neukáže.
3. Snímek první obrazovky (desktop a mobil) přes Playwright, zmenšený
   `aid-ui-tool.sh webp` do `.aid-ui/studio/direction-<n>.webp`.
4. Každý směr projde `references/genericity-rubric.md`; generický se
   přepracuje, neukáže.
5. Tři karty otázky `direction` ve studiu, každá s:
   - `thesis` - princip odvozený ze značky a vybraných vzorů,
   - charakteristické komponenty (2-3, v `body` otázky nebo `thesis`),
   - `uniqueness` - jedna věta, čím se liší od šablony (povinná, bez ní
     karta nevzniká),
   - `palette[]`, `risk`, `preview`.
6. Odpověď `reroll_safer` / `reroll_bolder` (s komentářem PM jako směrem)
   → nové tři směry podle komentáře pod id `next_question`, znovu body 1-5.
   `return` → uprav podle komentáře a otevři znovu.
7. Po `choose`: vybraný směr = karta s `id` = `choice` v `cards`
   zaznamenané odpovědi (snímek karet z okamžiku odpovědi, ne payload;
   náhled jen se shodným `preview_sha256` - `SKILL.md` „Jak se ptá PM",
   bod 5); tělo kapitoly
   `smer` (tento směr, jeho `thesis` beze změny, komponenty,
   snímek zkopírovaný do `docs/brand/assets/`, zamítnuté směry a proč)
   do souboru v `.aid-ui/`, `aid-ui-state.sh body <project> smer --file <soubor>`,
   `aid-ui-state.sh chapter <project> smer navrh`.
8. Smaž `.aid-ui/refs/*.png` (MUST 7); styly `.json` zůstávají.

## Co PM rozhoduje

Jeden ze tří směrů, re-roll bezpečněji nebo odvážněji s popisem - ve studiu.

## Zápis

Kapitola `smer`, `docs/brand/assets/`; odpověď `direction` ve stavu (jen
`record-answer`).

## Když krok selže

`glyph` nenajde písmo s češtinou → řekni PM, které rodiny prošly
`--sample`. Odpověď chybí → odkaz na studio a konec tahu.

**Last Updated:** 2026-09-28
