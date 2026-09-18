# P093 — akceptační běh nové kontroly plánu (krok 12)

Datum: 2026-09-18. Plugin: větev `feat/p093-plan-review`. Cíle byly zapsané před
během: `plugins/aid-orchestrator/scripts/tests/fixtures/plan-review/targets.json`.
Evidence běhu (JSON soubory kol): `docs/plans/P093-acceptance-evidence/P998/`.
Noční přehrání bez modelu: `scripts/tests/test-plan-review-acceptance.sh` (t2, 12/12).

## Výsledek jednou větou

Plán, na kterém starý řetězec 17. 9. nezkonvergoval, prošel novým tokem za dvě
kola a 16 USD celkem, bránou PASS.

## ACTA P025 (kopie jako P998)

Běh v klonu ACTA na commitu 9b68f91c98a0 ve scratchpadu; projekt ACTA se nezměnil.
Codex měl vyčerpaný limit do 21. 9., `generalist_b` proto běžel na stejném modelu
jako `generalist_a` (Claude Opus), kolo je zapsané jako `degraded: true`.

| Kolo | Revizoři | Nálezy (blokující / významné / drobné) | Odmítnuto | Tokeny | USD (16,4 / M) |
|---|---|---|---|---|---|
| 1 | 6 z 6 | 1 / 4 / 9 | 0 | 609 963 | 10,0 |
| 2 (potvrzovací) | 4 z 4 | 1 / 6 / 0 | 0 | 354 058 | 5,8 |

- Před kolem 1 plán neprošel deterministickou kontrolou (B8: stránka Docusaurus,
  kterou plán zakládá, mezitím vznikla). Autor změnil jeden bullet Create → Modify;
  jiné zásahy před revizí nebyly.
- Po kole 1 autor opravil kroky 1, 3, 12 a 14; `fix-check` prošel.
- Kolo 2 potvrdilo opravy kroků 1, 3 a 14 a našlo, že oprava kroku 12 byla
  neúplná (nové pravidlo přidané vedle starého) a že jedna oprava šla do jiného
  kroku, než nález chtěl. Stejný problém nahlásili čtyři revizoři čtyřmi slovy.
- Po kole 2 autor opravil krok 12 a 5, otevřený blokující ocitoval v kritériu
  přijetí kroku 12 a spustil `finalize`. Brána: PASS.

**Cíle:** kola ≤ 2 splněno (2); USD na kolo < 20 splněno (10,0 a 5,8), žádná
neznámá hodnota tokenů; každý nález, který prošel, má příkaz i `cesta:řádek`
(100 %, 0 odmítnutých); všechny archivní soubory kol jsou na disku.

**Srovnání:** pilot 17. 9. (starý řetězec, ACTA + Agents): kola s 26, 3, 11 a 10
blokujícími, bez konvergence, asi 43 USD za kolo. Ruční kolo 1 plánu P093: šest
revizorů, 787 k tokenů. Tady kolo 1 = 610 k tokenů a kolo 2 se zúžilo na 4
revizory a 354 k.

## Druhý plán: neproběhl, a proč

Plán P093 jmenoval jako druhý cíl P080 tohoto repozitáře. P080 je z větší části
postavený: 15 souborů, které zakládá, už existuje, a deterministická kontrola ho
oprávněně blokuje (B8). Revize takového plánu by nic neměřila. Náhradní kandidát
z pilotu, Agents P005, je na tom stejně (18 blokujících nálezů kontroly, části
postavené). Akceptace proto stojí na jednom živém běhu; první skutečné použití
bude příští nový plán v kterémkoli projektu.

## Co běh ukázal na samotném nástroji (opraveno před dokončením)

1. **Výzva se do agenta nevkládá.** Výzva s plánem ACTA má ~218 kB; šest kopií
   vložených do volání by zahltilo kontext controlleru. Adaptér teď předává cestu
   k souboru a revizor si ho čte sám.
2. **Potvrzovací kolo muselo dostat kontext.** Bez předchozích nálezů a diffu
   opravy by revizoři kola 2 znovu prošli celý plán. Balík kola 2+ nese otevřené
   blokující a významné nálezy a diff opravy s pokynem hlásit jen neopravené a to,
   co oprava nově rozbila.
3. **Drobné nálezy se nesmějí počítat jako opravené**, když je potvrzovací kolo
   nevidí. Opraveno (`yield.json` v uložené evidenci je ještě z doby před opravou
   a u kola 1 proto ukazuje drobné nálezy jako opravené).

## Co zůstává otevřené

- **Slučování nálezů podle znění.** Stejný problém od čtyř revizorů zůstal jako
  čtyři položky, protože otisk nálezu obsahuje prvních osm slov tvrzení.
  `also_reported_by` je proto skoro vždy 1. Nic se podle něj nerozhoduje (jen
  informace), ale počet „nálezů" je nafouknutý.
- **Velké plány revizoři nečtou celé.** Tři ze šesti revizorů výslovně přiznali,
  že plán s 1 400 řádky přečetli jen z třetiny a zbytek prohledali. Varování A9
  (velikost plánu) to předem hlásí; rozdělit plán je rozhodnutí autora.
