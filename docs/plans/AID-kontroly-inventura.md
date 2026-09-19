# Inventura kontrol a povinných kroků AID pipeline

Stav k 19. 9. 2026, plugin v2.98.0. Sestaveno z kódu (`scripts/`, `defaults/`,
`skills/pipeline.md`, `skills/review-checkpoint-contracts.md`) a z registru
vynucení (`defaults/enforcement-registry.yaml`, 497 řádků). Účel: seznam všeho,
co v pipeline něco kontroluje nebo musí proběhnout, v pořadí, v jakém to
potkává plán. Každá oblast nese počet řádků kódu, aby bylo vidět, kde je váha.

## Čísla celku

| Co | Kolik |
|---|---|
| Skripty `scripts/*.sh` | 69 souborů, 53 993 řádků |
| Knihovny `scripts/lib/` | 96 souborů, 31 770 řádků |
| Z toho dva stavové automaty (`aid-fsm.sh` + `aid-plan-fsm.sh`) | 20 829 řádků |
| Testy | 282 sad, 103 544 řádků |
| Registr vynucení | 497 řádků (354 blocking, 120 advisory, 16 se starým `fail`) |
| Příkazy / agenti | 12 / 9 |
| Skill `pipeline.md` (instrukce controlleru) | 3 266 řádků |

## Chronologická mapa

### 0. Stále, mimo pipeline (session a repo)

| Kontrola | Kód | Řádků | Co dělá |
|---|---|---|---|
| Hooky harnessu | `aid-hook.sh`, `hook-registry.yaml`, `aid-hook-verify.sh` (kanárek) | 1 129 | SessionStart kapsle kontinuity, PreCompact, Stop; fail-closed jen po ověřeném kanárku |
| Brána zprávy PM | `aid-turn-gate.sh` | 81 | Každá zpráva PM = jedna ze čtyř karet; karta s rozhodnutím musí mít možnosti a doporučení |
| Lint skillů a příkazů | `aid-lint-skill.sh` + `test-skill-lint.sh` | 85 | Mechanická shoda se `skill-writing.md` / `command-writing.md` |
| TTL registru | `aid-registry-ttl-guard.sh` | 178 | Řádek `status: planned` nesmí přežít lhůtu |
| Registr verzí (8 míst) | `tests/verify-version-files.sh`, pre-push hook | – | Jen na hranici vydání, ručně |
| Problémy pluginu | `lib/aid-plugin-issues.sh`, `bin/aid-plugin-issues-collect.sh` | – | Sběr `aid-plugin-issues.md` z projektů |

### 1. Plánování (`/aid-plan`)

| Kontrola | Kód | Řádků | Co dělá |
|---|---|---|---|
| Stav brainstormu | `aid-brainstorm-state.sh` (+ lib opponent, summary) | 375 | Fáze brainstormu musí proběhnout v pořadí |
| Lint plánu | `aid-plan-lint.sh` | 698 | Tvar Files, struktura kroků, tier tag u testů |
| Kontrola plánu (deterministická, 2.97.0) | `aid-plan-check.sh` | 606 | Bloky A/B/C: vnitřní konzistence, podklady, cesty |
| Paralelní skupiny | `aid-plan-parallel-check.sh` | 194 | Skupiny kroků bez konfliktu souborů |
| **CP1 revize plánu (2.98.0, hotovo P093)** | `aid-plan-review-round.sh`, `-adjudicate.sh`, `aid-cp1-gate.sh`, lib config/packet/summary | 1 847 | Šest revizorů, kola, rozhodčí, brána |
| Podklady plánu (P085) | `lib/aid-standards-map.sh`, `aid-source-plan-graph.sh` | – | Standardy podle tagů, graf zdrojů |

### 2. Generování (plán → EPIC → plan.json → run → fronta)

| Kontrola | Kód | Řádků | Co dělá |
|---|---|---|---|
| Transakce a zapečetěná autorita | `aid-auto-pipeline.sh`, `aid-generation-readiness.sh`, `-finalize.sh`, `lib/aid-generation-ids.sh` | 2 382 | Brána CP1 přesně jednou, `generation-authority.json`, každá fáze ji ověřuje (hash, bajty plánu, HEAD) |
| Generátory s vestavěnými kontrolami | `aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh` | 4 173 | 32 řádků registru: schéma plan.json, AC, Files, `_generated_by`, závislosti fronty |
| Start plánu | `aid-plan-fsm.sh plan-start`, `lib/aid-plan-manifest.sh`, `aid-worktree-registry.sh` | (v 11 519) | Větev `plan/<id>`, worktree, manifest s původem (lineage proven) |

### 3. Provedení EPICu (`/aid-run`: READY → EXECUTE)

| Kontrola | Kód | Řádků | Co dělá |
|---|---|---|---|
| Předpoklady FSM | `aid-fsm.sh` (init, resume, transition, increment-step, amend-scope) | 9 310 | 83 řádků registru; nejvíc ze všech |
| Záznam dispatche | `aid-emit-dispatch.sh`, `lib/aid-dispatch-contract.sh`, `aid-subagent-protocol.sh` | 240 | Každý agent má záznam před a po |
| Protokol výstupu agenta | `aid-protocol-validate.sh` | 661 | Protokol v2: obálka, `_generated_by`, verdikt |
| Ověření kroku controllerem | prose v `pipeline.md` §4 | – | Sekce „Step N Verification", AC checklist, vizuální kontrola |
| **CP2 revize kroku** | verifier agent (`agents/verifier.md`, 382), gate-fixer (240), `aid-prefilter.sh` (759) | – | code-review na diff kroku, fix loop max 2, invalidation-map po opravě |
| Doklad spotřeby a AC | `aid-consumption-proof.sh`, `aid-acceptance-evidence.sh` | 544 | Vazby kontraktu mají důkaz; AC z plan.json mají evidence |
| Balík důkazů | `aid-evidence-verify.sh` | 1 071 | Kontrola evidence adresáře kroku |
| Paměť (Qdrant) | `skills/memory-mcp.md` | – | Použitá / zapsaná paměť v ověření kroku |

### 4. Přechod EXECUTE → GATES

| Kontrola | Kód | Řádků | Co dělá |
|---|---|---|---|
| **CP3 revize EPICu** | verifier ×2 paralelně (code-review + security) | – | Celý diff EPICu, obě testové otázky |
| D0 pozorování po EXECUTE | `pipeline.md` §4 | – | Observe-only bod |
| Předpoklad přechodu | `aid-fsm.sh advance-to-gates` | – | CP3 výstupy přítomné a validní |

### 5. Brány (GATES)

| Kontrola | Kód | Řádků | Co dělá |
|---|---|---|---|
| Běžec bran | `aid-run-gates.sh` + lib profile/row/applicability/outcome | 2 886 | 11 bran: tests_pass, security_scan, docs_updated, scope_check, plan_diff, lint, standards, type_check, build, ui_calibration ×2; profily standard/full/release |
| Cílené testy | `aid-select-tests.sh`, `aid-selector-honesty-check.sh` | 849 | Výběr sad podle změn, poctivost výběru |
| Rozdíl plánu | `aid-plan-diff.sh` | 366 | AC z plánu proti kódu |
| Kontrola rozsahu | `gates/scope-check.sh` | – | Soubory mimo Files kroku |
| Výjimka PM | `aid-gate-waiver.sh` | 368 | Brána vypnutá s důvodem, vázaná na HEAD |
| Jména bran | `aid-gate-name-lint.sh`, `gate-name-allowlist.txt` | 155 | Jen povolená jména |
| Předpoklad GATES → DONE | `aid-fsm.sh` | – | Report bran vázaný na `_generated_by` |

### 6. Konec EPICu (DONE, režim plan_branch)

| Krok | Kód | Co dělá |
|---|---|---|
| Archiv běhu, `final_report.md` | `aid-fsm.sh done-advance` | Soubory přítomné |
| Manifest vstupů auditu | `lib/aid-c3-dispatch.sh build-manifest` | `input_hash` z allowlistu |
| Souhrn EPICu | `aid-epic-summary.sh` (332) | `epic-summary.md` |
| Dokončení a merge do plánu | `aid-plan-fsm.sh epic-complete`, `epic-merge-to-plan` | Podlaha plan-final profilu z rizika EPICu; merge jen do `plan/<id>` |
| Rozhodnutí PM | karta MERGE / FIX / ABORT | – |

### 7. Konec plánu (`plan-finalize --stage gates → inputs → review → release`)

Tady se sbíhá nejvíc mechanismů. Všechno běží jednou proti zmrazenému
kandidátovi (`candidate_sha`); FSM nic nedispatchuje, jen vyžaduje výstupy.

| Kontrola | Kód | Řádků | Co dělá |
|---|---|---|---|
| Plan-final brány | `plan-finalize --stage gates` | (v plan-fsm) | Profil bran přesně jednou |
| Vstupy revize | `--stage inputs` | (v plan-fsm) | `review-profile.json`, `plan-diff.json`, `delivery-gate.json`, `acceptance-evidence.json`, kostry protokolu v2 |
| Sken paměti (scanner) | `agents/project-scanner.md` (1 105) | – | Registrovaná utilita, přesně jednou |
| **C3 auditor** | `agents/auditor.md` (1 315), `lib/aid-c3-dispatch.sh`, `aid-audit-mode.sh`, `policies/c3-audit-policy.yaml` | – | `audit-report.json` vázaný na manifest vstupů; blokuje podle policy |
| **Kurátor** | `agents/curator.md` (364) | – | Čte audit, `curator-report.json` |
| **C2 sémantická revize** | `policies/semantic-review.yaml`, `review-profiles.yaml`, 12 čoček, 4 režimy | – | `semantic-review-final.json` |
| **C1 brána dodání** | `aid-delivery-gate.sh`, `lib/delivery-checks/`, `policies/delivery-gate.yaml` | 940 | `delivery-gate.json`, kandidáti na povýšení (`aid-promote-checks.sh`) |
| CP4 ověření oprav | verifier na diff kurátora a auditora | – | `verifier-output-cp4-*.md` |
| CP5 blokující nálezy | `aid-fsm.sh done-advance` čte `blocking_findings:` | – | Blokuje MERGE |
| **Simplifier** | `agents/simplifier.md` (150) | – | `simplifier-report.md` s `Head:` |
| **Reporter** | `agents/reporter.md` (208), `aid-pm-brief.sh` (486) | – | `delivery-report.json` poslední, `.aid-o/reports/<id>-delivery.md` |
| Záznam dispatchů | `dispatch-record.json` | – | Každý specialista přesně jednou |
| Přenesené závazky | `lib/aid-obligations.sh` | – | Otevřený `release_blocker` brání zavření |
| Samokontrola zavření | `aid-plan-close-check.sh` | 1 215 | Mechanický checklist před `plan-close` |
| **C4 rozhodnutí o vydání** | `aid-release-policy.sh`, `policies/release-decision-policy.yaml` | 1 365 | Agregát C1–C3 + CP1 (od 2.98.0 z `generation-authority.json`) |
| Vydání a merge do main | `aid-release.sh` (1 294), `aid-release-check.sh`, `plan-merge-to-main`, `plan-rollback` | – | V režimu plan_branch bez automatického bumpu verze |

### 8. Mimo hlavní tok

| Oblast | Kód | Řádků | Co dělá |
|---|---|---|---|
| Rychlý režim `/aid-do` | CP6 advisory | – | Nikdy neblokuje |
| Audit testů `/aid-audit-tests` | 17 skriptů `aid-test-*`, `aid-audit-tests-*`, `aid-nightly-report.sh` + 20 knihoven | 6 689 (+ lib) | Inventura, obsahový sken, karanténa, reaper, patra t0/t1/t2, katalog, ledger, noční report |
| Obnova a eskalace | `lib/aid-recovery-ladder.sh`, `-adjudicate.sh`, `policies/auto-recovery.yaml`, `aid-plan-continue.sh` (932) | – | Žebřík obnovy, pokračování plánu |
| Karty a artefakty | `lib/aid-decision-card.sh`, `aid-artifact-render.sh`, `artifact-profiles.yaml`, `decision-card-labels.yaml` | – | Tvar zpráv PM a stránek |
| Oprávnění a prostředí | `policies/permissions.yaml`, `lib/aid-permissions.sh`, `aid-env-name-denylist.sh`, `aid-cache-preflight.sh` | – | – |
| Diagnostika a stav | `aid-diagnostic.sh`, `aid-config-summary.sh`, `aid-worktree-report.sh`, `aid-check-deps.sh`, `aid-job.sh` | – | Čtení, ne kontrola |

## Co z toho vypadá jako kandidát na stejnou přestavbu jako CP1

Měřítko: kolik kódu nese, kolik různých mechanismů dělá totéž, a jestli
instrukce pro agenta říká, co má dělat.

1. **Konec plánu (oddíl 7):** devět mechanismů (C1, C2, C3, kurátor, CP4, CP5,
   simplifier, reporter, C4) a k tomu FSM stage, které vyžaduje jejich výstupy
   podle hashů. Kód: 6 749 řádků C1–C4 + podstatná část `aid-plan-fsm.sh`
   (11 519) + `aid-plan-close-check.sh` (1 215). Největší váha i největší
   křehkost (P082 rozpor reportera, D2/D3 kostry).
2. **CP2 + CP3 (oddíly 3 a 4):** verifier + gate-fixer + prefilter +
   invalidation-map. Chronologicky hned po CP1 a stejný vzor (revizor, fix
   loop), který P093 u CP1 právě nahradil.
3. **Brány (oddíl 5):** 2 886 řádků běžce pro 11 bran, z nichž 5 je ve výchozím
   stavu vypnutých; profily, waiver, výběr testů.
4. **Generování (oddíl 2):** 6 555 řádků; transakce a autorita jsou z P088–P090
   nové, generátory starší.
5. **Audit testů (oddíl 8):** 6 689 řádků + 20 knihoven; PM 9. 8. zrušil
   paralelismus, zbytek zůstal.
