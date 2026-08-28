# Inventura: kdo všechno mluví o artefaktech (2026-08-28)

PM: „najdi všechny informace, kdo se o těch artefaktech mluví, udělej to tak,
ať je to jasný. Ať ve specifikaci ekosystému není nic o Epicu — ty máš mít svoje
pravidla v AID, a svoji dokumentaci na Docusauru v /aid/."

## Sedm míst, a žádné z nich není jediná autorita

| # | Kde | Co tam je | Komu to patří |
|---|---|---|---|
| 1 | `/opt/eco/docs/.../ecosystem/specs/artifact-standard.md` (374 ř.) | kostra, stropy, tvar rozhodnutí — **a pět AID typů: brainstorming, plan, gates, epic_done, plan_done** | kostra ekosystému ANO; typy NE |
| 2 | `defaults/artifact-profiles.yaml` | povinná pole per typ — **jen dlaždice, jádro nevynucuje** | AID |
| 3 | `defaults/templates/artifact-outcome.html` | šablona, která stropy vynucuje | AID |
| 4 | `defaults/templates/artifact-templates-spec.md` (13 zmínek) | další popis téhož | AID, duplicita s 3 |
| 5 | `skills/communication.md` | čtyři karty pro PM (jedna z nich rozhodovací) | AID |
| 6 | `commands/aid-plan.md` (15 zmínek) + `skills/pipeline.md` (34) | KDY se co renderuje, rozeseto v próze | AID |
| 7 | `defaults/hook-registry.yaml` | jediná vynucená povinnost — a tlačí k VZNIKU | AID |

**AID má na Docusauru vlastní sekci `/aid/`** (getting-started, commands, skills,
agents, architecture, specs, troubleshooting…). V `aid/specs/` leží **jediný**
dokument: `plan-ceremony-bands.md`. O artefaktech tam **není nic** — všechno
o nich je v ekosystémové specifikaci, kam AID typy nepatří.

## Co je špatně, konkrétně

1. **Ekosystémový standard zná `epic_done` a `plan_done`.** EPIC je pojem AID.
   Ekosystém o něm nemá vědět; jeho věc je kostra, stropy a tvar rozhodnutí.
2. **Profil nevynucuje jádro.** Standard u `epic_done` žádá „co celek dodal
   lidsky · kde byly problémy a proč · co našel audit · seznam backlog položek
   s důvodem". Profil vyžaduje čtyři dlaždice a `items`. Renderer tedy projde
   kontrolou s prázdným jádrem — doloženo na třech stránkách WAN P099.
3. **Kdy se renderuje, je rozesetá próza** ve dvou souborech (49 zmínek dohromady)
   a nikdo se neptá na režim ani na stav plánu.
4. **Jediná vynucená věc tlačí opačným směrem** než PM: `plan_artifact_rendered`
   hlídá, aby stránka VZNIKLA.

## Co PM chce od obsahu (doslova, 2026-08-28)

> Co se řeší? Zadání. Jádro, o co jde, popsané lidsky (…) abych já z toho věděl,
> co se dělalo, co bylo dodané, proč se to stalo, proč se na ten audit dívám.
> A potom, pokud z toho plynou nějaké akce, kde já musím dělat rozhodnutí, tak
> lidsky napsané: co jsou ta rozhodnutí, jaké jsou možnosti, která je doporučená
> a proč si mám zrovna tuhle vybrat.

Tři bloky, ne pět: **zadání → jádro lidsky → rozhodnutí s možnostmi a důvodem.**
