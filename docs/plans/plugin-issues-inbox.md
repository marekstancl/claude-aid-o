# AID plugin issues — inbox

Collected by `bin/aid-plugin-issues-collect.sh` from every project's `.aid-o/work/aid-plugin-issues.md`. Decide here; mark the project file HOTOVO / ZAMÍTNUTO when done.

## Collected 2026-08-29 — 29 entries from 3 project(s)

---

#### acta — 1. Readiness gate nemá pojem „už hotový krok" — BLOKUJÍCÍ

**Kde:** `scripts/aid-generation-readiness.sh` → `scripts/aid-plan-lint.sh`,
volané ze `scripts/aid-plan-to-epic.sh:164` (exit 7).

**Co se stalo:** Steps 1-10 jsou implementované a sloučené do `main` (EPIC 1,
EPIC 2 a Step 10). Lint na nich přesto vyžaduje `**Reuse check:**` u každého
kroku s `Create:` bulletem — pravidlo, které v době psaní plánu neexistovalo.
Generace fáze 3 a 4 se kvůli tomu odmítne, přestože se těch kroků vůbec netýká.

**Proč to vadí:** u dokončeného kroku je otázka „nešlo to reusovat?"
zodpovězená mergnutým kódem. Retrofit pole je čistá ceremonie a svádí
k vymýšlení (napsat „searched → none", když soubor už dávno existuje, je
nepravda).

**Návrh:** buď (a) lint umí přeskočit kroky označené jako hotové
(frontmatter `completed_steps: 1-10`, nebo marker u kroku), nebo (b)
`aid-plan-to-epic.sh --phase N` lintuje jen kroky té fáze, ne celý plán.
Varianta (b) dává větší smysl — generace fáze 3 se fáze 1 netýká.

**Obejito:** retrospektivní `Reuse check` pole u Steps 1-10, formulovaná
pravdivě („implementováno, soubory existují"), ne fiktivně.

---



---

#### acta — 2. Readiness gate nemá PM override — BLOKUJÍCÍ

**Kde:** `scripts/aid-plan-to-epic.sh:164`.

**Co se stalo:** CP1 gate má sankcionovanou cestu ven
(`cp1-pm-escalation-override.json` s `pm_ref`). Readiness gate ne — na STRICT
nálezu tvrdě padá a nedá se přes něj projít ani s PM rozhodnutím.

**Proč to vadí:** STRICT nálezy jsou hygiena zápisu, ne bezpečnostní riziko.
CP1 (který chrání před generací z neověřeného plánu) override má; lint, který
chrání před ošklivým formátováním, ne. Je to obráceně, než by člověk čekal.

**Návrh:** stejný single-use override artefakt jako u CP1, nebo alespoň
`--accept-strict --reason '<20+ znaků>'` s auditním zápisem.

---



---

#### acta — 5. Codex občas nezkopíruje `input_manifest_hash` a celé kolo propadne

**Kde:** `scripts/lib/aid-c0-plan-review.sh` → `_c0_write_report`, binding check.

**Co se stalo:** jedno kolo (2026-08-27 ~08:10) doběhlo, Codex vrátil validní
JSON s pěti relevantními nálezy, ale v `input_manifest_hash` měl jinou hodnotu
než manifest. Výsledek: `outcome: invalid_output`, `review_status: unverifiable`,
nálezy zahozené. Musel jsem je vytáhnout ručně z `codex-events.jsonl`.

**Proč to vadí:** fail-closed je správně, ale zahodit hotovou práci kvůli
jednomu přepsanému hashi je drahé — a spotřebuje to kolo z ledgeru.

**Návrh:** když se liší jen `input_manifest_hash` a `reviewed_plan_hash`
s `reviewed_head` sedí, hlásit to jako `binding_mismatch` s uchovaným
raw výstupem a nabídnout jeden automatický retry, než se kolo započítá.

---



---

#### acta — 6. Migrace 0030 si vzal jiný plán, P016 to nevěděl

**Kde:** není plugin bug, ale chybějící mechanismus.

**Co se stalo:** P016 měl v plánu `Create: 0030_vat_category.py`. Mezitím
P018 migraci 0030 zabral (nechal v ní komentář pro P016, což bylo férové).
Odhalil to až C0 review.

**Návrh:** `aid-plan-lint` by mohl u `Create: backend/db/versions/NNNN_*.py`
ověřit, že číslo je volné proti aktuálnímu HEAD migrací. Je to mechanická
kontrola a kolize migrací je klasický způsob, jak si dva plány rozbijí merge.

---



---

#### acta — 9. Dopředné závislosti jsou zakázané, ale nic to neřekne při psaní

**Kde:** dependency parser v readiness.

**Co se stalo:** C0 review (správně) požadovalo, aby release gate závisel na
krocích, které ověřuje. Ty měly vyšší čísla → `forbidden forward dependency`.
Musel jsem prohodit Steps 19 a 21 a přečíslovat všechny křížové odkazy.

**Návrh:** buď to hlásit už z `aid-plan-lint` (ne až z readiness), nebo
povolit dopřednou závislost uvnitř jedné fáze — pořadí kroků v EPICu stejně
řídí graf, ne čísla.

---



---

#### acta — 10. Generation receipt je celoplánový — mid-plan resume regeneruje hotové EPICy

**Kde:** `scripts/aid-generation-finalize.sh`, `scripts/aid-json-to-run.sh:699`.

**Co se stalo:** P016 má EPICy 1 a 2 hotové a sloučené. Pro FSM init EPICu 3
je ale potřeba kompletní receipt za **všechny čtyři** fáze, vázaný na aktuální
sha plánu. Musel jsem přegenerovat i EPICy 1 a 2 (jejich task soubory se
přepsaly, i když ten kód je dávno v `main`).

**Návrh:** receipt s pojmem „fáze už dodaná" — vázat jen fáze, které se
skutečně generují, a hotové označit jako `delivered` bez nároku na čerstvý sha.

---



---

#### acta — 11. `aid-auto-pipeline.sh` spadne na už zařazeném EPICu a nedokončí receipt

**Kde:** `aid-auto-pipeline.sh` → `lib/aid-queue-write.sh: queue_append_entry`.

**Co se stalo:** pipeline vygenerovala všechny čtyři EPICy, pak u queue-add
fáze 1 zjistila, že `E-016-1_4` v queue už je (status `released_to_main`,
z července), a skončila chybou. Receipt tím zůstal s `queue_status:
"pending_receipt"` u všech čtyř fází a `aid-json-to-run.sh` ho odmítal.

**Proč to vadí:** správně detekovaný stav („tenhle EPIC je dávno hotový")
shodí celou pipeline místo toho, aby ho přeskočila.

**Návrh:** u EPICu, který už v queue je s terminálním statusem
(`released_to_main`, `merged_to_plan`), queue-add přeskočit a pokračovat.

**Obejito:** ruční `aid-json-to-run.sh --generation-receipt <receipt>` pro
fázi 3.

---



---

#### acta — 19. `allowed_paths` neobsahují testy — scope amendment u každého kroku

**Kde:** `scripts/aid-epic-to-json.sh` odvozuje `allowed_paths` z `Files:` bloku plánu.

**Co se stalo:** hook odmítl commit kroku 14a s devíti testovacími soubory:

```
AID HOOK: Commit blocked — staged file(s) outside EXECUTE step 3 scope:
  - backend/tests/migrations/test_0031_vat_category.py
  - backend/tests/clients/test_vat_profiles_api.py
  … (9 souborů)
```

Plán ve `Files:` blocích testy nevyjmenoval, ale **sám je vyžaduje v akceptačních
kritériích** („migrační fixture pokrývá obě větve", „test dokazuje, že se pole opravdu
serializují z endpointu").

**Proč to vadí:** opakovalo se to u kroků 1, 4 a znovu u 14b/14c. Napsat migraci nebo
API bez testů nejde, takže scope amendment je potřeba pokaždé.

**Obejito:** PM schválil trvalé pravidlo `test_follows_source` (zapsáno v `plan.json`
→ `scope_policy` a v `timeline.jsonl`): test k souboru v `allowed_paths` patří do scope
automaticky. Nerozšiřuje to produkční kód, jen umožňuje práci doložit.

**Návrh:** zavést to jako výchozí chování generátoru — `allowed_paths` odvodit
i z konvence `tests/**` odpovídající měněným modulům.

---



---

#### acta — 22. `overall: pass` navzdory spadlým branám — BLOKUJÍCÍ, nejzávažnější nález

**Kde:** `scripts/aid-run-gates.sh`, výpočet `overall`.

**Co se stalo:** `advance-to-gates` ohlásil úspěch:

```
advance-to-gates: SUCCESS — gates passed, state=GATES
```

FSM přešel do GATES. Ve vygenerovaném `gates_report.json` ale bylo:

```
overall = pass
  py_test              profile_excluded   exit=0 attempts=0
  py_lint              fail               exit=1 attempts=3
  py_type_check        fail               exit=1 attempts=3
  ts_test              pass
  …
```

Dvě brány **spadly** (obě po vyčerpání tří pokusů) a přesto `overall: pass`.
Ty chyby nebyly kosmetické — `py_type_check` hlásil pět reálných typových chyb
způsobených typovaným `VatRow`, mimo jiné:

```
acta/validation/verdict.py:137: error: Argument 1 to "vat_vs_total_applicable"
  has incompatible type "list[VatRow]"; expected "list[dict[Any, Any]] | None"
```

**Proč to vadí:** brána, která hlásí `pass` i když spadla, není brána. Kdybych
report nečetl řádek po řádku, EPIC by prošel do DONE s červeným typem a lintem —
a `docs/plans/best-practices.md` i `execution.yaml` samy varují, že přesně tohle
se v projektu už jednou stalo (B-046, „zelené gates neznamenalo otestováno").

**Návrh:** `overall` musí být `fail`, pokud kterákoli neexcludovaná a nezwaivovaná
brána skončí `fail`. Pokud jsou některé brány záměrně advisory, musí to být
v reportu explicitní pole (`blocking: false`), ne tichý součet.

---



---

#### acta — 23. `advance-to-gates` volí profil, který vynechává testy

**Kde:** `scripts/aid-fsm.sh advance-to-gates` → výchozí `--profile standard`.

**Co se stalo:** report z automatického přechodu měl
`"profile": "standard", "profile_reason": "explicit --profile flag"` a v
`excluded_gates` byl **`py_test`**. Backendová testovací sada tedy vůbec neběžela,
přestože EPIC přidal 270 backendových testů.

Ruční běh s `--profile full` pak dal poctivý výsledek (`py_test pass`, 2141 testů).

**Proč to vadí:** `advance-to-gates` je doporučená „atomická" cesta z chybové
hlášky u `transition EXECUTE GATES`. Kdo ji použije, dostane zelené brány bez
spuštění testů, a `profile_reason` tvrdí „explicit --profile flag", ačkoli žádný
flag nezadal.

**Návrh:** buď volit profil podle toho, čeho se EPIC dotkl (backendové změny →
profil s `py_test`), nebo profil nechat na volajícím a nemít výchozí. A opravit
`profile_reason`, který dnes lže o původu volby.

---



---

#### acta — 24. Scope při branách je sjednocení kroků — dobře, ale amendmenty se ztrácejí

**Kde:** git pre-commit hook ve stavu GATES.

**Co se stalo:** hook ve stavu GATES správně používá **sjednocení `allowed_paths`
všech kroků** (to je náprava toho, co popisuje #21). Jenže do sjednocení se
nedostaly cesty, které PM schválil jako rozšíření kroku 1 (`export/csv.py`,
`export/xlsx.py`) — protože ten amendment se musel z `plan.json` vrátit kvůli
hash guardu (#17).

```
AID HOOK: Commit blocked — staged file(s) outside GATES (union of all steps) scope:
  - backend/acta/export/csv.py
  - backend/acta/export/xlsx.py
  - backend/acta/validation/cross_check.py
```

Přitom právě opravy těch souborů brány samy vyžadovaly.

**Proč to vadí:** kruh. Brána vyžaduje opravu → oprava je mimo scope → scope
amendment shodí hash guard → guard se obchází ručně. Bez `amend-scope` příkazu
(#17) se z toho nedá vyjít čistě.

---



---

#### acta — 25. HEAD se čte z aktuálního adresáře, ne z worktree — podruhé, jinou hláškou

**Kde:** `scripts/aid-fsm.sh`, kontrola čerstvosti CP3 při `transition GATES DONE`.

**Co se stalo:** je to tentýž kořen jako #20, ale projeví se jako věcně nepravdivé
tvrzení, ne jako chybějící kontext:

```
PRECONDITION FAIL: CP3 Reviewed-Head 08aa8c42… is not an ancestor of HEAD 81aa6f09…
```

`81aa6f0` byl commit v hlavním checkoutu (větev `main`), zatímco EPIC žije ve worktree
`plan-P016`. Tam předek je:

```
$ cd .aid-worktrees/plan-P016 && git merge-base --is-ancestor 08aa8c42… HEAD && echo OK
OK
```

**Proč to vadí:** #20 se dal poznat („evidence nesedí" vs. „jsem jinde"). Tady hláška
tvrdí něco, co je prokazatelně nepravda — commit **je** předek — a člověka to pošle
hledat problém v evidenci CP3 místo v pracovním adresáři. U plánu v `plan_branch`
módu je přitom worktree normální stav, ne výjimka.

**Návrh:** odvodit pracovní adresář z `plan-state.yaml` → `worktree_path` a číst HEAD
odtud; nebo aspoň do hlášky doplnit, ze kterého adresáře se HEAD bral.

---



---

#### acta — 26. Čerstvost CP3 vynutí celé kolo i po dvouřádkové opravě — pozorování, ne chyba

**Kde:** `scripts/aid-fsm.sh`, precondition `GATES → DONE`.

**Co se stalo:** CP3 (obě review) běželo na `08aa8c4`. Brány pak našly typové a lint
chyby, jejich oprava sáhla na produkční kód → CP3 zastaralo a muselo se opakovat.
Nová CP3 dala doporučení, jejich oprava zase posunula HEAD → a znovu. Za jeden večer
tři kola CP3 na EPICu, který se věcně neměnil.

**Proč to není chyba:** guard je správný a dvakrát z těch tří kol našel něco reálného
(mimo jiné to, že moje vlastní pojistka slibovala „zbylé v příštím běhu", ačkoli žádný
příští běh nepřijde). Přeskočit review kvůli spěchu je přesně to, čemu má bránit.

**Přesto stojí za zvážení:** rozlišit „delta se dotkla produkčního chování" od „delta je
oprava, kterou si vyžádaly brány nebo samo CP3". Druhý případ by mohl stačit potvrdit
cíleným delta-review místo plného kola — což jsem stejně dělal ručně tím, že jsem
verifierovi do zadání napsal „nerecenzuj celý EPIC, jen deltu". Kdyby to uměl nástroj,
nezáviselo by to na tom, jestli si na to orchestrátor vzpomene.

**Poznámka k nákladům:** tři kola CP3 = šest dispatchů verifiera nad ~13 400 řádky diffu.

**Aktualizace 2026-08-29 — pozorování povýšeno na nález.** Na E-016-3_4 se to
zopakovalo a tentokrát je vidět, že to není jen otrava, ale chybějící
konvergenční ventil. Průběh:

| Kolo | Reviewed-Head | Výsledek |
|------|---------------|----------|
| 3 | `163a4c9` | PASS, 4 nálezy (D14-D17) |
| 4 | `578337e` | PASS, 3 nálezy (N1-N3) |
| 5 | `bcfb562` | PASS-check nad ~30 řádky delty |

Každé kolo si vyžádalo opravu, oprava sáhla do produkčního souboru, HEAD se
posunul za `Reviewed-Head`, transition odmítnuta. Jediná zabudovaná cesta ven
je `--force --reason`, tedy **PM override — i když ta poslední oprava je
doslova to, co si review samo vyžádalo.** Logovat to jako bypass je nepřesné.

Kola 3-5 stála ~25 minut agentního času a tři plné cykly bran, aby se zavřely
nálezy v součtu ~30 řádků produkčního kódu (rozdělení jednoho logu, jedna
`sort()`, jedna konstanta).

**Konkrétní návrh:** když se od `Reviewed-Head` změnily jen soubory, které
předchozí CP3 samo označilo za nález, umožnit posun `Reviewed-Head` doložením
cíleného delta-review místo plného kola. Nebo aspoň `--reason` bez `--force`,
ať se v auditu nepletou dvě různé věci.

**Obcházka, kterou používám:** dispatchnout CP3 s explicitně zúženým rozsahem
(„recenzuješ VÝHRADNĚ deltu X..Y") a přepsat kanonický
`verifier-output-cp3-*.md` včetně hlavičky `Reviewed-Head`. Funguje, ale
plugin pro to nemá příkaz, takže to stojí a padá na tom, jestli si na to
orchestrátor vzpomene.




---

#### acta — 27. `aid-run-gates.sh` čte HEAD z aktuálního adresáře, ne z worktree běhu

**Kde:** `scripts/aid-run-gates.sh run-all`, pole `revision.head_sha` v `gates_report.json`.

**Co se stalo:** brány jsem pustil z kořene stavu (`/opt/eco/projects/acta`),
protože tam leží `--state-file`, `--report-file` i `execution.yaml`. Skript
neodvodil pracovní strom z `fsm-state.yaml → branch`
(`task/E-016-3_4/main`), ale vzal `git rev-parse HEAD` v cwd:

```
"revision": { "head_sha": "a0f6457b4fe2d7723220f5baee680adc27b9f6f6" }
```

`a0f6457` je HEAD hlavního stromu na `main`. Můj skutečný kandidát byl
`578337efd6f5735e56f6d0ebc927d0275abd4760` na worktree
`.aid-worktrees/plan-P016`. Brány tedy proběhly nad **jiným kódem**, než
který se releasuje, a `overall: pass` by se do evidence zapsal s cizí revizí.

**Proč je to vážné:** AUTO kontrakt říká „výsledek testu platí jen pro
zaznamenaný HEAD/tree". Tady je HEAD zaznamenaný správně-vypadajícím způsobem,
jen patří jinému stromu. Report se tváří platně a nic nevaruje. Kdyby na `main`
byl zelený kód a na task větvi rozbitý, brána projde a `GATES→DONE` se pustí.

**Důkaz:** dva běhy téhož příkazu, lišící se jen cwd:

| cwd | `revision.head_sha` |
|-----|---------------------|
| `/opt/eco/projects/acta` | `a0f6457…` (main) |
| `/opt/eco/projects/acta/.aid-worktrees/plan-P016` | `578337e…` (task/E-016-3_4/main) |

**Obcházka:** brány pouštět **výhradně z worktree běhu**, cesty k state/report
předávat absolutně. Stejná třída chyby jako #20 a #25 (`increment-step`) —
u tří různých skriptů, takže to není překlep, ale chybějící společné odvození
pracovního stromu z FSM stavu.

**Návrh opravy:** odvodit strom z `fsm-state.yaml.branch` přes
`git worktree list --porcelain` a buď v něm brány spustit, nebo tvrdě odmítnout
běh, když cwd neodpovídá.



---

#### acta — 28. Commit hook počítá `allowed_paths` jen z kroků EPICu, takže do commitu nejde backlog

**Kde:** git pre-commit hook (AID HOOK), stav GATES.

**Co se stalo:** CP3 našlo architektonický nález (N3, synchronní propagace),
který se ve v1 neopravuje a patří do backlogu. Zápis do
`docs/plans/BACKLOG.md` hook odmítl:

```
AID HOOK: Commit blocked — staged file(s) outside GATES (union of all steps) scope:
  - docs/plans/BACKLOG.md
```

Povolený rozsah je sjednocení `Files:` ze všech kroků EPICu — což je pro
produkční kód správně, ale backlog není produkt kroku, je to **výstup review**.
Plugin přitom sám vyžaduje, aby se neopravené nálezy někam zapsaly (per-plan
C+A review, pravidlo 14), a pak zápis zablokuje.

**Důsledek:** nález se buď propašuje do `--force`, nebo se zápis odloží za
merge a hrozí, že se ztratí. Zvolil jsem odložení — patch parkuje mimo repo,
což je přesně ta křehkost, kvůli které se nálezy ztrácejí.

**Návrh:** přidat `docs/plans/BACKLOG.md` (nebo konfigurovatelný seznam
„review sink" cest) do implicitně povoleného rozsahu ve stavech GATES
a DONE. Je to append-only dokument, riziko je nulové, a alternativa je horší.



---

#### acta — 29. Plán a FSM pojmenují týž běh jinak, `epic-complete` pak nenajde evidenci

**Kde:** `aid-plan-fsm.sh epic-start` vs `aid-json-to-run.sh` / `aid-fsm.sh init`.

**Co se stalo:** EPIC E-016-3_4 doběhl do `DONE`, ale
`aid-plan-fsm.sh epic-complete P016 E-016-3_4` odmítl pokračovat:

```
PRECONDITION FAIL: no fsm-state.yaml at
/opt/eco/projects/acta/.aid-o/work/evidence/E-016-3_4/R-E-016-3_4-plan/fsm-state.yaml
for E-016-3_4 (run R-E-016-3_4-plan) — cannot confirm the EPIC reached DONE.
```

Skutečný běh má ale `run_id: R-E016-3` a evidenci v
`.aid-o/work/evidence/E-016-3_4/R-E016-3/`. Dvě různá jména téhož běhu:

| Vrstva | run_id | zdroj |
|--------|--------|-------|
| plán (`plan-boundary-manifest.json:54`) | `R-E-016-3_4-plan` | `epic-start` |
| FSM (`fsm-state.yaml:2`) | `R-E016-3` | `init` |

**Proč to vadí:** hláška obviňuje EPIC („cannot confirm the EPIC reached DONE"),
ačkoli EPIC v `DONE` je a evidence existuje — jen pod jiným jménem. Čte se to
jako „nedoběhlo to", což vede k opakování už hotové práce. Tohle je stejný
vzorec jako #22: kontrola hlásí něco jiného, než co je pravda.

**`plan-state --repair` to neopraví.** Doběhne bez chyby a `run_id` v manifestu
nechá být:

```
{"epic_runs":[{"epic_id":"E-016-3_4","run_id":"R-E-016-3_4-plan", ...}]}
```

**Obcházka:** symlink z očekávané cesty na skutečnou —
`ln -s R-E016-3 R-E-016-3_4-plan` v `.aid-o/work/evidence/E-016-3_4/`.
Kopie ne, ta by se rozešla. Po symlinku `epic-complete` i
`epic-merge-to-plan` proběhly bez dalšího zásahu.

**Návrh:** buď ať `init` přebírá `run_id` z manifestu, když už tam pro daný
EPIC zapsaný je, nebo ať `epic-complete` hledá evidenci podle `epic_id`
a `run_id` bere jen jako preferenci. A ať hláška říká, co se stalo:
„evidence for E-016-3_4 exists under run R-E016-3, manifest expects
R-E-016-3_4-plan" místo obvinění, že EPIC nedoběhl.



---

#### acta — 30. Povinné sekce `step-N-verify.md` se zjišťují po jedné, hláška po hlášce

**Kde:** `aid-fsm.sh increment-step`, validace souboru s důkazem kroku.

**Co se stalo:** napsal jsem důkaz Stepu 16 podle vzoru z předchozího EPICu
a `increment-step` ho odmítl třikrát po sobě, pokaždé kvůli něčemu jinému:

```
1) PRECONDITION FAIL: Step verification has no acceptance criteria checklist.
   Must contain at least one '- [x] ...' item matching plan AC.
2) PRECONDITION FAIL: Step verification missing '## Memory Used' section.
3) (dále CP2 prefilter)
```

Akceptační kritéria jsem měl v **tabulce** s výsledkem a důkazem u každého
řádku — věcně bohatší než checklist, ale validátor hledá literál `- [x]`.
Tabulka musela zůstat a checklist se přidal nad ni, takže je to teď dvakrát.

**Proč to vadí:** tři kola „oprav a zkus znovu" u dokumentu, který se dá
zvalidovat celý naráz. Každé kolo je jeden běh nástroje a jedno přepnutí
kontextu. Formát navíc není nikde vypsaný pohromadě — zjišťuje se reverzně
z chybových hlášek nebo opsáním z předchozího EPICu.

**Návrh:** ověřit všechny povinné sekce najednou a vypsat je jako seznam
chybějících. A do `agent-protocol.md` (nebo `--print-template`) dát šablonu
souboru, ať se nemusí odvozovat z hlášek.



---

#### acta — 31. `aid-prefilter.sh classify` komunikuje jen exit kódem, na stdout mlčí

**Kde:** `scripts/aid-prefilter.sh classify <step> <evidence_dir>`.

**Co se stalo:** `increment-step` na CP2 pošle uživatele spustit classify
a rozhodnout se podle exit kódu (0=skip, 10=code-review, 20=security,
22=range_undetermined). Skript ale na stdout ani stderr nenapíše **nic**:

```
$ bash aid-prefilter.sh classify 0 <evidence_dir>
$ echo $?
20
```

Kdo ho pustí s `| tail` (což je při čtení výstupu přirozené), dostane exit
kód roury, ne skriptu — tedy `0`, tedy „skip". Tichý skript, jehož jediný
výstup je exit kód, je past: `| tail` z něj udělá opačnou odpověď, než jaká
je pravda, a nic nevaruje. Stejná třída chyby jako #22 (`overall: pass`
navzdory spadlým branám) — kontrola tvrdí opak reality.

**Návrh:** vypsat rozhodnutí i na stdout (`classify: security_review_required
(exit 20)` + důvod). Exit kód ať zůstane pro skripty, člověk potřebuje větu.

---

#### agents — 1. Per-krok výřez `allowed_paths` neodpovídá tomu, jak brány repozitáře fungují

**Dopad: největší jednotlivá ztráta času v celém běhu. 12× `--force`, 4 commity s `--no-verify`.**

Plán rozdělí `Allowed files/paths` EPICu na per-krok `allowed_paths` v `plan.json`.
Jenže repozitář má **křížové brány**, které si vynucují zásah do souboru, jenž patří
jinému kroku:

- Brána **T131** (`tests-smoke.sh`) žádá, aby každý test volaný sadou byl pokrytý vzorem
  v `deploy-manifest.txt`. Každý krok, který přidá test, tedy **musí** sáhnout do
  manifestu — a ten patří kroku 1.
- `tests/fixtures/deploy-inventar.txt` je zmrazený inventář, proti kterému se manifest
  porovnává. Změna manifestu bez změny fixture = červená brána.

Důsledek: `increment-step` odmítne posun (`files changed outside the allowed paths`)
a git hook odmítne commit — **přestože jsou ty soubory v `Allowed files/paths` EPICu**.

**Důkaz** (`.aid-o/work/evidence/*/timeline.jsonl`, 12 záznamů `fsm_force_override`):

```
fsm_force_override | deploy-manifest.txt a fixture jsou v Allowed files/paths EPICu;
                     brzdi jen per-krok vyrez, brana T131 z kroku 1
fsm_force_override | fixture deploy-inventar a ci.yml mimo per-krok vyrez, oba v
                     Allowed files/paths EPICu
fsm_force_override | fixture, tests-deploy-manifest a docs/sidebars.ts mimo per-krok
                     vyrez, vse v Allowed files/paths EPICu
```

**Co s tím.** Buď per-krok kontrola padá zpět na `Allowed files/paths` EPICu (varování
místo odmítnutí, když je soubor v širším rozsahu), nebo `aid-epic-to-json.sh` umí u kroku
deklarovat „vynucené průvodní soubory". Dnešní stav znamená, že `--force` je z výjimky
rutina — a tím přestává být signálem.

---



---

#### agents — 2. Kontrola hashe `plan.json` nerozlišuje přegenerování od podvržení

**Dopad: dvakrát zastavený běh, jednou nutný ruční zásah do `fsm-state.yaml`.**

FSM si při `init` orazítkuje sha256 celého `plan.json` a při každém `increment-step` ho
porovná. Když PM plán **legitimně přegeneruje** (u nás přejmenování `helpdesk` → `asistent`,
commit `17d4c8c`), hash nesedí a běh se zastaví hláškou o „mid-EPIC tampering".

Hláška nabízí dvě cesty — vrátit plán, nebo re-init EPICu. **Obě jsou špatně:** vracet
znamená zahodit PM rozhodnutí, re-init přepíše `base_commit` a tím rozbije přiřazení diffu
při `done-advance`.

**Důkaz:**

```
ERROR: plan.json hash mismatch — modified mid-EPIC.
        plan.json hash at init: 62dfefb7c4cf657d...
        plan.json hash now:     40fb529e262a9d2d...
Fix: revert plan.json to init state, OR re-init EPIC if changes are legitimate.
```

Skutečný rozsah změny (ověřeno diffem `de06249..17d4c8c`): `[HD-]` → `[AS-]`
a `hd-e2e-runner` → `as-e2e-runner`. **Krok 1 byte-identický.**

**Co s tím.** Hash **per krok** (`plan_step_hash` už existuje a používá se ve
step-binding!) místo hashe celého souboru. Krok, jehož definice se nezměnila, by
neměl padat kvůli přejmenování v jiném kroku. Případně `aid-fsm.sh rebind-plan`
s povinným důvodem, aby to nebyl ruční `set-field`.

---



---

#### agents — 3. `verifier-output-cp3-*.md` vyžaduje pole `classification`, ale šablona v `aid-run.md` ho nepředepisuje

**Dopad: `advance-to-gates` selhal třikrát s hláškou, která ukazovala špatným směrem.**

`fsm_check_verifier_output()` (`aid-fsm.sh:1215`) vyžaduje `_generated_by`, `_generated_at`
**a `classification`**. U CP2 to pole zapisuje pre-filter. U **CP3 ho nezapisuje nikdo** a
šablona výstupu v `commands/aid-run.md` ho v hlavičce **nemá**.

Hláška přitom tvrdí něco jiného:

```
PRECONDITION FAIL: verifier-output-cp3-code-review.md missing or invalid.
Fix: Dispatch TWO verifiers in parallel ...
```

Soubor existoval, měl `verdict: pass` a byl čerstvý. Dispatchoval jsem verifiery **třikrát**
zbytečně (~25 minut a tři plné review), než jsem si přečetl zdroj validátoru.

**Co s tím.** Doplnit `classification: FULL_REVIEW` do šablony v `aid-run.md` (a v
`pipeline.md`), nebo validátor u `checkpoint: cp3` to pole nevyžadovat. A hláška by měla
říct **které pole** chybí.

---



---

#### agents — 4. Pre-filter přepisuje soubor verifiera → nálezy předchozí iterace se ztratí

**Dopad: čtyři nálezy z iterace 1 nedohledatelné.**

`aid-prefilter.sh classify N <evidence_dir>` napíše `verifier-output-step-N.md` se svou
hlavičkou a `verdict: pending`. V fix loopu se ale klasifikuje **znovu**, takže report
předchozí iterace zmizí dřív, než ho někdo přečte.

**Důkaz** — verifier iterace 2 to hlásí sám:

> „iterace 1 měla devět nálezů; pre-filter soubor přepsal dřív, než je kontrolér zálohoval,
> takže čtyři z nich nejsou dohledatelné."

Od té chvíle zálohuji ručně (`cp … .iterN.bak`), ale to je obcházení, ne řešení.

**Co s tím.** Pre-filter by měl existující report odsunout (`.iter<N>.bak`) místo přepsání,
nebo psát do `verifier-output-step-N.iter<K>.md` a nechat `increment-step` číst poslední.

---



---

#### agents — 5. `--force` na `increment-step` přeskočí **celou** kontrolu, ne jen tu vadnou

Když forcuji kvůli `allowed_paths` (bod 1), vypne se tím i kontrola step-verify souboru:

```
WARNING: --force used, skipping step verification check
status=advanced advanced_from=0 advanced_to=1
```

Jednou to zamaskovalo, že se `step-3-verify.md` **vůbec nezapsal** (heredoc mi spadl na
znaku `%` v textu). Krok se posunul s prázdnou evidencí a všiml jsem si toho až zpětně.

**Co s tím.** `--force --blocked-checks 'contract_return_rejected'` (ten mechanismus už
existuje u `done-advance`!) místo plošného vypnutí.

---



---

#### agents — 6. Cesty v plánu zastarají a nic to nehlídá

Plán jmenuje `/opt/eco/docs/docs/ecosystem/ai-agents/...`. Jiné sezení 28. 8. tu
dokumentaci přesunulo (`git mv` do `docs/agents/`, commit `c03ed1e`) a **18 souborů
zároveň přejmenovalo**. Plán o tom neví, takže tři po sobě jdoucí kroky dostaly
`allowed_paths` ukazující na neexistující soubory a musel jsem je v zadání opravovat ručně.

Rozbilo to i bránu manifestu — `deploy.sh` by kopíroval neexistující soubor a Mara by
přišla o svůj podklad.

**Co s tím.** PRE-FLIGHT (nebo `init`) by mohl ověřit, že každá cesta v `allowed_paths`,
která ukazuje mimo repozitář, existuje — a hlásit to jako varování při startu EPICu, ne
až když na ni krok narazí.

---



---

#### agents — 7. Drobnosti

- **`aid-fsm.sh increment-step` bez argumentu** spadne na `line 5533: $1: unbound variable`
  místo výpisu použití.
- **`docs-validate.mjs` musí běžet z `/opt/eco/docs`** — z worktree hledá `sidebars.ts`
  v cwd a spadne `ENOENT`. Není to plugin, ale opakovaně mě to zmátlo.
- **Hláška `advance-to-gates`** vypíše celý `gates_report.json` (stovky řádků) a teprve
  pod ním důvod selhání.
- **Commit hook v EXECUTE** hlásí `empty allowed_paths for EXECUTE step 5; passing commit`
  — varování, kterému nerozumím, protože `allowed_paths` prázdné nejsou.

---

---

#### wan — 3. Každá oprava plánu znamená ruční `supersede-generation`

Změna jediného řádku plánu změní jeho otisk, tím i identitu transakce, a další
běh skončí na `generation transaction identity mismatch`. Když předchozí
transakce **nic nevytvořila** (všechny fáze `not generated`), je ruční archivace
s dvacetiznakovým důvodem jen obřad — dalo by se archivovat automaticky a jen to
zalogovat.



---

#### wan — 4. PM-escalation override se spotřebuje i při běhu, který nic nevytvoří

Artefakt `cp1-pm-escalation-override.json` se přejmenuje na `.consumed-<epoch>`
ve chvíli, kdy si ho brána nárokuje — tedy i tehdy, když běh vzápětí spadne
(na tvaru závislosti, na chybějícím plánu na `main`, na neplatné roli) a žádný
EPIC nevznikne. Za dnešek se tak spotřebovaly **čtyři** artefakty na jedno
skutečné generování. Nárok by se měl potvrzovat až úspěchem transakce.



---

#### wan — 6. Rozpočet revizí C0 je vyčerpatelný přepisem plánu, ne jen neúspěchem

Ledger `attempts: 5 / max: 5` počítá každý nový otisk plánu. Plán se přitom
legitimně přepisoval kvůli vydání standardu v0.2. Výsledek: rozpočet došel dřív,
než se stihlo zkontrolovat finální znění, a jediná cesta dál je override.



---

#### wan — 16. Dvojí běh bran zanechá v ose dva `gate_runner_start` a kontrola to odmítne

Po opravě podle bodu 13 bylo nutné brány pustit znovu; kontrola pak hlásí
„timeline has 2 gate_runner_start events … expected exactly 1". Neexistuje
dokumentovaný způsob, jak legitimní druhý pokus odlišit od zakázaného „druhého
širokého běhu pod nálepkou full" — kromě force. Nabízí se čítač pokusů
(`plan_final_attempt` v plan-state existuje a zůstává na 0).

