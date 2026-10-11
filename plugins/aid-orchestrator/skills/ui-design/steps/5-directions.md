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
4m. **Soupis pohybu vzoru, před stavbou směrů** (P108, 10. 10. 2026; PM: „animace i níže, ne jen
   úvod"): `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-motion.py" inventory <project>` vyrobí
   `.aid-ui/motion.json` ze záznamu vybraného vzoru (krok 4 bod 7): položka za každý keyframe, každou
   skupinu přechodů (vlastnost + scénář: načtení / posun / najetí / zaměření), každý pohyb řízený
   skriptem a přechod mezi stránkami. U každé položky vyplň `disposition` (`adopt` = převezmu,
   `replace` = nahradím jiným pohybem, `omit` = vynechám), `target` (jméno keyframe nebo vlastnost
   přechodu, které ponesou všechny tři směry i stavba - směry stav nad společným základem), u `replace`
   a `omit` `reason` a `label` (lidské jméno pohybu, které uvidí PM, např. „otáčení pečeti"), u
   načítacích animací `frequency` (`every_load` jako vzor; `first_load_only` jen s důvodem - 9. 10.
   PM úvodní animaci neviděl, protože agent sám zvolil „jednou za relaci"). Vlastní pohyb navíc jde
   jen do `extra` s důvodem. Nic z hlavy: položky jsou jen ze záznamu. Položka `replace` smí nést
   `from` = id DRUHÉHO vzoru, který PM viděl (brand-state `refs`) a jehož záznam
   `.aid-ui/refs/<from>.motion.json` ten pohyb obsahuje (PM 11. 10. 2026, 2B: pohyb pod přehybem z jiného
   vzoru); kontrola ho ověří v tom záznamu i ve stavbě a otázka `direction` ho ukáže jako „nahrazeno z <vzor>".
   Každý směr musí pohyb **nést a prokázat**: po stavbě směru ho nástroj pozoruje jako cizí web -
   `bash "$AID_PLUGIN_PATH/scripts/aid-ui-tool.sh" motion --dir <project>/.aid-ui/directions/<n>
   <project>/.aid-ui/directions/<n>.motion.json` (nástroj složku servíruje sám na volném portu
   a otisk složky zapíše sám; záznam z jiné adresy kontrola s `--dir` odmítne)
   a pak `python3 "$AID_PLUGIN_PATH/scripts/aid-ui-motion.py" check <project> --observed
   <project>/.aid-ui/directions/<n>.motion.json --dir <project>/.aid-ui/directions/<n> --write
   <project>/.aid-ui/directions/<n>.motion.check.json` (záznam i kontrola leží VEDLE složky směru,
   ne v ní). FAIL vyjmenuje, co se nespustilo (keyframe, který neběžel; vyplutí jen nahoře, když vzor
   má i dole; úvod, který při druhém načtení neběžel) - oprav směr a pozoruj znovu. Změna složky po
   pozorování = pozorovat znovu (otisk složky).
5. Tři karty otázky `direction` ve studiu. Všechny tři vycházejí z vybraného vzoru a z toho, co
   k němu PM napsal; liší se tím, jak daleko vzor vezmou (věrně / s obsahem navíc / odvážněji),
   ne tím, že by dva šly jinam. Otázka nese `prior` = přesně zaznamenaná odpověď PM k vzorům
   (`{"question", "choice", "comment"}` z `brand-state.json`), studio ji ukáže nad otázkou; každá karta
   má `honours` (do 300 znaků, jmenuje id vybraného vzoru) = jak směr ctí volbu a slova PM; studio
   hlídá přesnost `prior` a jméno volby v `honours`, slova PM ctíš ty. Bez toho studio otázku odmítne
   (`aid_ui_prior_decision`; PM 9. 10. 2026). Každá karta dál s:
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
9. Otázka `direction` nese soupis (studio ji jinak odmítne, když má projekt vybraný vzor):
   `target` = `smer:<sha256 .aid-ui/motion.json>`, `motion` = `{sha256, sentence, exceptions}` přesně
   z `aid-ui-motion.py summary <project>` (věta „z N pohybů vzoru: a převzato, b nahrazeno,
   c vynecháno" a každé nahrazení či vynechání jmenovitě s důvodem - volba směru je zároveň souhlas
   PM s nimi), každá karta `dir` = jméno složky směru s PASS kontrolou nad aktuálním otiskem složky.
   Vrácení s poznámkou k pohybu → uprav soupis, pozoruj směry znovu, otázku znovu (nový otisk).

## Co PM rozhoduje

Jeden ze tří směrů, re-roll bezpečněji nebo odvážněji s popisem - ve studiu.

## Zápis

Kapitola `smer`, `docs/brand/assets/`; odpověď `direction` ve stavu (jen
`record-answer`).

## Když krok selže

`glyph` nenajde písmo s češtinou → řekni PM, které rodiny prošly
`--sample`. Odpověď chybí → čekání na pozadí podle `SKILL.md` „Jak se ptá PM", bod 4.

**Last Updated:** 2026-09-28
