# Stránky AID pro PM přes share (AID 3.10.0)

PM 22.–24. 10. 2026: stránky, které AID vyrábí pro PM (stránka plánu po CP1, stránka uzávěru, stránka brainstormu),
nemají být claude.ai artefakty — PM přepíná účty a artefakt vidí jen v jednom. Share to od 23. 10. umí
(`share-admin.sh publish-for-pm`: stálý odkaz pro PM, přepsání na stejném odkazu, jméno a logo projektu).
Ostatní artefakty se nemění. AID je veřejný plugin: výchozí zůstává artefakt, share se zapne nastavením.

## Co se staví

1. **`scripts/aid-pm-page-publish.sh <page.html> --plan <Pnnn> --kind plan|close|brainstorm --title "<název>" [--project-root <r>]`**
   - Bez nastavení vypíše `artifact <cesta k tělu>` a skončí 0: řadič stránku zveřejní nástrojem Artifact jako dnes.
   - S nastavením `AID_PM_PAGE_PUBLISHER` (příkaz, např. `/opt/eco/projects/aidlab-apps/share/scripts/share-admin.sh publish-for-pm`)
     zabalí tělo stránky do úplného HTML dokumentu (doctype, `<meta charset>`, viewport, `<title>`), zavolá příkaz
     s `--key <projekt>-<otisk>/<plán>/<druh> --title <název> --project <projekt> [--logo <svg>]` a stránkou na stdin a vypíše
     `link <odkaz>` (jeden řádek). Stejný klíč = stejný odkaz, přepsání stránky ho zachová.
   - Jméno projektu: `project_name` z `.aid-o/config/project.yaml` (klíč, který píše `/aid-init`; `name` jako záloha), jinak jméno adresáře kořene stavu. Logo: `pm_page.logo`
     z `project.yaml` (cesta v repu), jinak první existující z běžných míst (`frontend/public/favicon.svg`,
     `ui/public/favicon.svg`, `public/favicon.svg`, `src/app/favicon.svg`); nic = bez loga (share dá logo značky).
   - Selže-li příkaz (share neběží, odmítne stránku), skončí nenulově s jednou větou a výpisem; **nepřepadne
     na artefakt** (pravidlo share). Řadič to řekne v kartě jednou větou; karta v chatu nese rozhodnutí i bez stránky.
2. **Jeden pokyn místo „Publish the artifact body via the Artifact tool“** na všech místech, která ho dnes nesou
   (`communication.md`, `pipeline.md`, `brainstorming.md`, `aid-plan.md` ×2, `aid-run.md`), doslova stejný,
   hlídaný `test-communication-wiring.sh`.
3. **Nastavení na hostech PM:** `AID_PM_PAGE_PUBLISHER` v `~/.claude/settings.json` → `env` jen na eco-dev
   (share běží jen tam); na eco-prod zůstane artefakt.
4. **Dokumentace:** CHANGELOG (oba), `aid-run.md`/`aid-plan.md`, Docusaurus `/aid/` (stránky pro PM), pravidlo
   v `/opt/eco/CLAUDE.md` („artefakt pro Marka zůstává artefaktem“ → kromě stránek AID).

## Hotovo, když

- [ ] Bez nastavení skript vypíše `artifact <cesta>` a nic nevolá (test).
- [ ] S nastavením (v testu falešný publisher) dostane publisher úplný HTML dokument, klíč `<projekt>-<otisk>/<plán>/<druh>`, název, projekt a logo; skript vypíše `link <odkaz>`; druhé volání se stejným klíčem vypíše týž odkaz (test).
- [ ] Logo z `project.yaml`, jinak z běžných míst, jinak žádné (test); jméno projektu z `project.yaml`, jinak adresář.
- [ ] Selhání publisheru = nenulový návrat, žádný artefakt, věta pro kartu (test).
- [ ] Všech 6 míst nese nový pokyn doslova; `test-communication-wiring.sh` zelený.
- [ ] Na eco-dev skutečná stránka plánu (zkušební) přes share otevřená zvenku, odkaz 200.
- [ ] T0 + T1 + přímé sady zelené, zkušební projekt nad `git archive`, revize Codexem.

## Verze 2 po revizi zadání (Codex 24. 10., `.aid-o/work/evidence/P-stranky-share/brief-review.md`)

Přijato (mění body výš):
- **Karta a odkaz (1):** karta zůstává doslovná; za ni řadič přidá právě jeden řádek, který vypíše skript:
  `Stránka: <odkaz>` po úspěchu, nebo `Stránka se nezveřejnila: <důvod>` po selhání. Bez nastavení se nic nepřidává
  (artefakt jako dnes).
- **Doručení, ne jen vykreslení (2):** s nastaveným publisherem skript po úspěchu zapíše vedle stránky
  `<page>.published.json` (sha256 stránky, klíč, druh, čas — NE odkaz, ten nese klíč PM a patří jen do chatu; atomicky). Povinnost stránky
  (`lib/aid-artifact-obligation.sh`) a `aid-brainstorm-state.sh approve` pak vyžadují záznam, jehož sha256 sedí na
  dnešní stránku; jejich hlášky jmenují `aid-pm-page-publish.sh`. Bez nastavení beze změny.
- **Nastavení bez spouštění textu (4):** `AID_PM_PAGE_PUBLISHER` = cesta ke spustitelnému souboru, nepovinně
  `AID_PM_PAGE_PUBLISHER_SUBCOMMAND` = jedno slovo (`publish-for-pm`), nic se nevyhodnocuje shellem; test s mezerou
  a metaznaky v hodnotě.
- **Tělo beze změny (5):** stránka se posílá tak, jak ji vykreslil renderer (share přidá vlastní hlavičku); `--title`
  nese název.
- **Limit (6):** nad 2 MiB (UTF-8 bajty) skript odmítne před voláním, test na hranici.
- **Výstup publisheru (7):** stdout a stderr zvlášť; úspěch = exit 0 a právě jeden řádek `https://…`; jinak selhání.
  Upozornění ze stderr (logo) skript vypíše na stderr, nikdy do karty.
- **Klíč (8):** `<id projektu>/<plán>/<druh>`, id projektu = jméno adresáře kořene stavu (stabilní, ne zobrazované
  jméno), zúžené na `[a-z0-9-]`, nejvýš 60 znaků; zobrazované jméno z `project.yaml` `project_name`, jinak adresář. Klíč stránky je `<adresář>-<8 hex otisku repo_id, jinak cesty>/<plán>/<druh>` (bezpečnostní kontrola 24. 10.: samotné jméno adresáře mohlo kolidovat).
  Dokumentace řekne, že jméno a logo vidí i ten, kdo zná adresu stránky bez klíče.
- **Logo (9):** jen soubor uvnitř kořene projektu (po vyřešení odkazů), běžný soubor, nejvýš 8 KiB, obsahuje `<svg`;
  neplatné `pm_page.logo` = chyba, neplatný nalezený kandidát se přeskočí s větou na stderr.
- **Všech šest míst (10):** `test-communication-wiring.sh` jmenuje každé místo zvlášť, pokyn tam musí být doslova,
  stará věta nikde.
- **Živé ověření (11):** jedna skutečná stránka plánu na eco-dev přes share, otevřená prohlížečem (obsah, styl, bez
  chyb v konzoli) — ruční krok před vydáním, ne test v sadě (share je jen na eco-dev).
- **Negativní testy (12)**, **stabilita odkazu je vlastnost share (13)**, **veřejný popis protokolu (14)**,
  **přesná místa dokumentace (15):** ano.

Odmítnuto s důvodem:
- **(3) nová klasifikace citlivého obsahu:** stránka jde dnes jako artefakt na claude.ai (cizí služba); share je
  služba PM na jeho hostu a odkaz s klíčem dostane jen PM, takže share není horší cesta než dnešní. Renderery už
  před vykreslením tajemství redigují (`_aid_artifact_redact`). Nová vrstva klasifikace by byla nová funkce mimo
  zadání PM; dokumentace řekne, co se kam posílá a na jak dlouho (30 dní, přepsání obnoví).
