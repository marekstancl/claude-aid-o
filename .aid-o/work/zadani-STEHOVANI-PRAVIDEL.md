# Zadání: rozdělit pravidla artefaktů mezi ekosystém a AID

Pro agenta, který spravuje dokumentaci. Zadal PM 2026-08-28.

## Problém, jednou větou

Ekosystémová specifikace `/opt/eco/docs/docs/ecosystem/specs/artifact-standard.md`
obsahuje typy artefaktů, které patří výhradně AID (`epic_done`, `plan_done`,
`gates`, `plan`, `brainstorming`) — ekosystém o EPICu ani o plánu AID nemá co
vědět. AID přitom má na Docusauru vlastní sekci `/aid/`, kde o artefaktech není
ani řádek.

## Co udělat

### 1. Z ekosystémové specifikace ODEBRAT
Sekci `## Profily podle typu` (řádky ~72-153) — pět podsekcí:
`brainstorming`, `plan`, `gates`, `epic_done`, `plan_done`.

### 2. V ekosystémové specifikaci PONECHAT
Všechno, co platí pro každý projekt bez ohledu na nástroj:
- `## Kdy artefakt použít`
- `## Povinná kostra` (sedm bloků) + „každý artefakt deklaruje svůj typ"
- „Odkaz je jméno, ne cesta"
- `## Jedna A4, detail zvlášť`, stropy, zakázané formulace
- `## Rozhodovací artefakt` — tvar rozhodnutí (možnosti → doporučení → proč →
  co se stane, když nerozhodneš)
- `## Vzhled`, `## Interní versus externí`

Doplnit jednu větu: *typy artefaktů si definuje každý nástroj sám ve své
dokumentaci; standard určuje kostru, stropy a tvar rozhodnutí.*

Čistý řez: v ekosystémovém standardu NEsmí zůstat odkaz na AID stránku ani
zmínka o konkrétním nástroji. Věta výše stojí sama, bez „viz /aid/specs/…".
(Rozhodl PM 2026-08-28.)

### 3. Do dokumentace AID PŘIDAT
Nová stránka `/opt/eco/docs/docs/aid/specs/artefakty.md` (sekce `aid/specs/`
existuje a je skoro prázdná — leží v ní jen `plan-ceremony-bands.md`).
Obsahuje pět typů AID **v podobě, kterou PM zadal 2026-08-28** — tedy NE jako
dnes, ale ve třech blocích:

> **zadání** (co se řešilo) → **jádro lidsky** (co se dělalo, co bylo dodáno,
> proč se to stalo, proč se dívám na audit) → **rozhodnutí** (jaká, jaké
> možnosti, která je doporučená a proč zrovna ta)

PM doslova: „Co se řeší? Zadání. Jádro, o co jde, popsané lidsky (…) abych já
z toho věděl, co se dělalo, co bylo dodané, proč se to stalo, proč se na ten
audit dívám. A potom, pokud z toho plynou nějaké akce, kde já musím dělat
rozhodnutí, tak lidsky napsané: co jsou ta rozhodnutí, jaké jsou možnosti, která
je doporučená a proč si mám zrovna tuhle vybrat."

### 4. Sladit odkazy
`sidebars.ts` (nová stránka do navigace) a v pluginu odkazy na standard:
`defaults/templates/artifact-templates-spec.md`, `skills/communication.md`,
`commands/aid-plan.md`.

## Co NEDĚLAT
- Nesahat na `defaults/artifact-profiles.yaml` VŮBEC — ani na povinná pole, ani
  na odkaz na standard uvnitř. Celý soubor opravuje AID souběžně, jeden soubor =
  jeden vlastník. Odkaz na novou strukturu si tam doladí AID sám.
  (Rozhodl PM 2026-08-28.)
- Nevymýšlet nové typy ani nová pravidla. Přesouváš a přepisuješ do PM tvaru.

## Doklad, proč to vzniklo
Tři stránky dokončených EPICů z WAN P099 (E-099-1_3, -2_3, -3_3) jsou prakticky
totožné, ani jedna neříká, co EPIC dodal, a přitom to leží vedle ve
`final_report.md` téhož běhu. Standard to předepisuje, profil to nevynucuje,
renderer to nedodá — tři vrstvy a každá spoléhá na druhou.
