# P100 — sledování na dalších třech bězích plánů

Plán P100 („Mantinely místo slepých uliček") je vydaný jako 2.106.0. Jeho cíl se
neměří testy, ale na skutečných bězích: **v dalších třech plánech žádný agent
nepotřebuje `--force`, ruční úpravu stavového souboru ani přejmenovaný soubor
evidence, aby prošel odmítnutím.** Tento záznam vyplní ten, kdo pracuje na
prvním, druhém a třetím plánu po vydání.

## Jak změřit

Pro každý projekt, který běžel na 2.106.0 nebo novější (projekt na starší verzi
se nepočítá a jmenuje se níže):

```bash
# odmítnutí a vynucení od data vydání, po důvodech
find /opt/eco/projects/{acta,agents,wan,krok,aid-orchestrator} -path '*evidence*' -name timeline.jsonl -newermt 2026-09-24 \
  | xargs cat | jq -r 'select(.event|test("precondition_fail|force|blocked|_fail$"))|[.event,(.reason//"")]|@tsv' | sort | uniq -c
# ruční zásahy, které agenti nahlásili
grep -n "ručně\|by hand\|hand edit\|--force" /opt/eco/projects/*/.aid-o/work/aid-plugin-issues.md
```

Každé `*_force_override` porovnat s evidencí, zda k němu existuje rozhodnutí PM
(karta Rozhodnutí, odpověď v session). Každý nový důvod odmítnutí, který není
v tabulce `skills/pipeline.md` §„When AID refuses", dostane řádek v opravném
vydání.

## Co vyplnit

| Plán | Projekt | Verze AID | `*_force_override` bez rozhodnutí PM | Ruční úpravy stavu (hlášené) | Odmítnutí po důvodech | Fungoval řádek `next:`? |
|---|---|---|---|---|---|---|
| 1. |  |  |  |  |  |  |
| 2. |  |  |  |  |  |  |
| 3. |  |  |  |  |  |  |

Selhání (vynucení bez PM nebo ruční úprava stavu) otevírá opravné vydání.

## Co se z plánu vědomě nedodalo

- **Krok 10 (zrychlení revizního enginu) vypuštěn.** Jeho cíl — merge cesta pod
  20 minut — splnila už 2.105.0 (9,8 minuty; `test-review-round.bats` přesunut do
  nočního běhu, kde trvá ~7 minut). Rozhodnutí za PM: Codex, varianta A
  (24. 9. 2026). Sada zůstává v noci; optimalizace enginu se otevře, jen když ji
  budeme chtít zpět před mergem.
- **Stránka dodaného plánu neukazuje řádek úklidu.** Stránka vzniká v
  `plan-finalize --stage decide`, úklid až v `plan-close` po ní; co bylo
  odstraněno a co ponecháno, je v `cleanup.json` a ve výstupu `plan-close`.
- **Převzetí brány z běhu EPICu se nekombinuje s předchozím pokusem** — když
  existuje dřívější pokus konce plánu, bere se jen z něj (vzácný případ návratu
  na strom EPICu; kód by se tím zdvojil).

## Velikost pluginu

`scripts/` pluginu (včetně testů): před plánem (0d4ffc6b) 173 883 řádků, po
něm 175 104 řádků (+1 221: +635 v testech, +586 v pravidlech; z toho +199 připadá na
12 oprav z triáže 24. 9.). Růst je v testech nových pravidel a v pravidlech
samých (tabulka odmítnutí, spor k PM, delta kolo, úklid při uzavření, převzetí
bran z EPICu, druh tématu u brainstormingu); nic z toho není nová sada testů.

## Rozhodnutí PM 24. 9. 2026 (tření z běhu P100, před vydáním 2.106.0)

| Bod | Rozhodnutí | Co to znamená |
|---|---|---|
| Pomalé sady (generování 18–19 min, konec plánu 30 min) | nechat | běží v noci; řešit, až to začne vadit |
| Revize plánu pouští nepravdivé předpoklady | **A** | dvě otázky navíc pro `feasibility_deps` (pořadí za běhu, převzatý předpoklad ověřený v kódu); kontrola čerstvosti (C) až při opakování |
| Nestabilní sada při souběžných session | **A** | runner vždy vypíše spadlé případy a jejich výstup; příčina se hledá při dalším výskytu |
| Tiše zahozený řádek brány | nic | týká se jen autorů testů; zapsáno v hlášení |
| Stará verze Codex CLI | odinstalovat | příkaz dán PM: `sudo npm uninstall -g --prefix /usr/local @openai/codex` |
