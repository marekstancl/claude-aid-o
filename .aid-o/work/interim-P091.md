# P091 — brainstorming: kdy smí vzniknout stránka pro PM

Založeno 2026-08-28. Téma zadal PM po dvou dnech, kdy mu z běhů chodily stránky,
o které nestál.

## PM zadání, doslova (2026-08-28)

> - do evidence nepotřebuju artefakty!!! potřebuju je jak se dopíše plán, ale
>   OPRAVDU AŽ SE DOPÍŠE A JE SCHVÁLENEJ A JE VE STAVU GENERUJEME EPICY NIKDY NE DŘÍV!!!!!!
> - PŘÍPADNĚ dříve, jen za předpokladu, že se po mě chtějí nějaká rozhodnutí!
> - a potom v manual plánu (po EPicu a nakonci plánu) ale zase až po všech kontrolách!!!
> - v auto plánu pak jen úplně na konci před MERGE po všech kontrolách zase!!

Dřívější zadání ke stejné věci (2026-08-25, po stránce z bran v ACTA):
„hrůza bych řekl hodnota artifactu 0".

## Fakta, na kterých brainstorming stojí (ověřeno, ne dovozeno)

- Renderuje **pět** volajících: `aid-plan-summary.sh`, `aid-gate-outcome-summary.sh`,
  `aid-plan-close-summary.sh`, `aid-brainstorm-summary.sh`, `aid-epic-summary-page.sh`.
  **Žádný z nich se neptá, jestli to má jít PM.**
- WAN vyrobil za dva dny **17 stránek**; PM chtěl jednu.
- Živý příklad bezcenné stránky (WAN E-099-1_3): v bloku „Co se čeká ode mě"
  stálo *„Nic — ozvu se, až bude hotovo"*. Stránka sama řekla, že nic nechce.
- Dnes existuje jediná vynucená povinnost `plan_artifact_rendered` (hook `Stop`),
  a ta tlačí **opačným směrem**: vynucuje, aby stránka VZNIKLA.

## Rozpor, který je jádrem tématu

Systém dnes vynucuje vznik stránky a nikde neřeší její doručení. PM ale nechce
méně renderů — chce méně **doručení**. To jsou dvě různé věci a v kódu se
nerozlišují.

## Důkaz, který přišel sám, uprostřed tohohle brainstormingu (2026-08-28)

Hook `plan_artifact_rendered` si vyžádal přegenerování stránky pro **P062** —
plán, který v tomhle okně nikdo neotevřel a který PM řeší jinde. Vznikl tedy
render pro plán, o kterém PM v týhle chvíli nic vědět nechce, jen proto, že se
soubor někde jinde změnil.

To je celý problém v jedné události: **vynucuje se VZNIK, ne UŽITEČNOST.**
Stránka je teď čerstvá a nikdo si ji nevyžádal.

## Oprava analýzy po PM připomínce (2026-08-28) — měl pravdu, byl jsem vedle

Tvrdil jsem, že problém je jen v DORUČENÍ a že obsah je po P089 v pořádku.
Tvrzení padlo na třech živých stránkách z WANu (E-099-1_3, -2_3, -3_3):

**Jsou prakticky totožné.** Všechny tři říkají „Revize neúplná", „CHYBÍ report
auditu", „CHYBÍ report kurátora" a nabízejí totéž rozhodnutí. Liší se jen
čísly kroků a časem.

**Ani jedna neříká, CO EPIC DODAL.** Jádro zní: „EPIC E-099-3_3 je hotový:
3 kroky za 13 h 46 min." To je všechno. P089 Krok 4 přitom sliboval „co EPIC
dodal lidsky; kde byly problémy a **proč**; co našel audit; seznam backlog
položek s důvodem vzniku".

**A tenhle obsah přitom EXISTUJE, jen o dva soubory vedle:**
`R-E099-3/final_report.md` má sekci „Co EPIC dodal" s konkrétní stránkou,
16 nástroji, verzí 0.28.0; `epic-summary.md` má „Co bylo dodáno" se seznamem
commitů a „Varování a přeskočené kroky" i s celým odůvodněním force override.

**Příčina, doložená v kódu:** `aid-epic-summary-page.sh` čte JEN
`audit-report.{json,md,yaml}` a `curator-report.{json,md}` (řádky 118-154).
Když nejsou, vypíše „chybí" a skončí. Slovo „dodal"/„delivered" se ve skriptu
**nevyskytuje ani jednou** — renderer nemá pojem „co se dodalo". Dívá se do dvou
prázdných šuplíků a plné vedle ignoruje.

### Tři vady, ne jedna
1. **OBSAH** — nese, co v evidenci NENÍ, a ignoruje, co v ní JE.
2. **MNOŽSTVÍ** — tři skoro totožné stránky za jeden plán.
3. **NAČASOVÁNÍ** — po každém EPICu, ne podle PM pravidel.

## Odpověď na PM otázku o žebříku zotavení
Agenti ho v instrukcích **NEMAJÍ**: `agents/*.md` 0 výskytů, `agent-protocol.md`
0, `role-cards.md` 0. Zná ho jedině controller (`pipeline.md`, 8 výskytů).
Proto agent zkouší dokola — pravidlo existuje a jeho adresát o něm neví.
