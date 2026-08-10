# AID v3 — Status & Roadmap

**Role:** Living status tracker — inventory + session assignments + priority order  
**Aktualizováno:** 2026-05-10 (post P035 + P036 deploy)  
**Zdroje:** `AID-v3-architectural-inventory.md` (AID-001–033), `AID-v3-initial-plan.md` (body a–h), `AID-v3-diagnostic-findings-post-A.md` (round 0.b measurement)

---

## Oddíl 1 — Přehled implementovaného (Sessions A + B)

Pokrytí: **AID-001, 002 (partial), 003, 004, 005, 006, 016, 032** + force_override mitigation + IMP-090

| AID ID | Téma | Stav | Session / Verze | Poznámka |
|---|---|---|---|---|
| AID-001 | PRE-FLIGHT branch enforcement | ✅ | Session A / v2.16.0 | `git checkout -b epic/...` vynuceno v FSM precondition |
| AID-002 | Context Assembly 10/10 components | 🟡 PARTIAL | Session A / v2.16.0 | Dispatch template přepsán, Components 1–8+10 v pipeline.md §4. **Component 9 (MEMORY — vulcan-find):** instrukce je v pipeline.md:203 jako agent-side instruction — controller ji NEVYNUCUJE (agent může přeskočit). Controller-side injection = Session C scope. |
| AID-003 | CP2 per-step verifier enforcement | ✅ | Session B / v2.18.0 | Pre-filter SKIP/RUN/FAIL classifier (aid-prefilter.sh), verifier_outputs object-schema |
| AID-004 | CP3 integration review parallel | ✅ | Session B / v2.18.0 | Parallel code-review + security verifier dispatch |
| AID-005 | Real gates execution | ✅ | Session A / v2.16.0 | `gates_no_generated_by` FSM precondition + wiring |
| AID-006 | execution.yaml lazy-create | ✅ | Session A / v2.16.0 | Vytvořen při `/aid-init` nebo prvním `/aid-run` |
| AID-016 | Verifier deprivation | ✅ | Session B / v2.18.0 | Nuanced: diff + DoD + step.outputs + step.forbidden_paths (Conflict 4 → position_B) |
| AID-032 | Sub-agent isolation verification | ✅ | Krok 1 / 2026-05-04 | T1–T12 empirické testy, isolation confirmed, `docs/plans/AID-v3-subagent-isolation-test.md` |

**Navíc bez přímého AID ID:**
- **force_override unification** — unified `fsm_handle_force_override()` dispatcher s caller field, audit log, --reason enforcement
- **compliance.json telemetrie** — `evaluate_compliance_checks()`, `write_compliance_json()`, `aid-compliance-report.sh` (--era, --compare, --reflect) — toto pokrývá **základ** pro AID-012/027, ale NENÍ totožné (viz Oddíl 2 poznámky)
- **IMP-090 epic-summary.md** — auto-generovaný summary po každém EPICu (5 sekcí), `done-advance` hook
- **Completeness Gate #17 + 17a-d** — codebase grounding rule v plan-writing.md + CP1 verifier dispatch (P035 Phase 1+2, v2.18.0+v2.19.0)
- **svc-mcp-tg-bot** — Telegram alert MCP server (port 8817), `try_telegram_alert` v FSM

**Post-Session-B standalone (v2.19.1 + v2.20.0, 2026-05-10):**
- **P035 Phase 2 (v2.19.0)** — Completeness Gate sub-checks 17a-d (backlog ID, test path, DB field, file removal grounding); `/aid-plan` brainstorm Step 9 verifier prompt; `test-cp1-grounding.sh` smoke test
- **P036 (v2.20.0)** — 4 plan-quality enforcement layers: sub-check 17e (CLI invocation grounding), check #19 (Design Defeat Detection for `type: bug-fix`), `/aid-plan write` Step 9 (CP1 lifecycle), EVIDENCE REQUIREMENT in reviewer prompt; `## Plan Type` taxonomy in template; `test-plan-quality-enforcement.sh` smoke test. Completeness Gate counter: 22→24.

---

## Oddíl 2 — Kritické poznámky k terminologické záměně

> Toto je důležité pro sprint planning. Dvě věci vypadají podobně ale jsou jiné.

### compliance.json ≠ AID-026 (deterministic auditor)

`compliance.json` je strukturovaná zpráva **kterou píše agent sám** do `.aid-o/work/runs/*/compliance.json`. Agregátor (`aid-compliance-report.sh`) čte tato agent-authored data.

**AID-026** (deterministic compliance auditor) je bash script který:
- Čte `timeline.jsonl` — záznam reálných tool calls (agent nemůže falzifikovat)
- Parsuje: byla volána `Agent` tool pro CP2 dispatch? Existuje commit hash z verify souboru v git logu?
- **Agent nemá write access do výstupu** — je out-of-band

→ compliance.json MŮŽE být fabricated. AID-026 NEMŮŽE.  
**Status AID-026: ❌ NOT DONE.** Session A postavila základ ale jiný nástroj.

### aid-compliance-report.sh --reflect ≠ AID-027 (telemetry)

`--reflect` v report.sh počítá pattern přes EPICs: kolik EPICů má daný flag, trend pre/post.

**AID-027** (telemetry) počítá:
- Per-step tool call sequence (typ, pořadí, args)
- Čas per step (anomálně rychlé = suspicious)
- `test_mock_ratio` = mocked_calls / total_test_calls (AID-independent metrika)
- Edit pattern: diff size, testové soubory %

→ --reflect = aggregate trend. AID-027 = per-step forensics.  
**Status AID-027: ❌ NOT DONE.** Existuje jen aggregate vrstva.

---

## Oddíl 3 — Kompletní status všech AID položek

### ✅ Hotovo

| AID ID | Téma | Verze | Poznámka |
|---|---|---|---|
| AID-001 | Branch enforcement v PRE-FLIGHT | v2.16.0 | |
| AID-003 | CP2 per-step verifier | v2.18.0 | |
| AID-004 | CP3 integration review | v2.18.0 | |
| AID-005 | Real gate execution | v2.16.0 | |
| AID-006 | execution.yaml lazy-create | v2.16.0 | |
| AID-016 | Verifier deprivation (nuanced) | v2.18.0 | Conflict 4 → position_B |
| AID-032 | Sub-agent isolation verify | Krok 1 | T1–T12 empirické testy |

### 🟡 Partial — základ položen, finální implementace chybí

| AID ID | Téma | Co je hotové | Co chybí |
|---|---|---|---|
| AID-002 | Context Assembly 10/10 | Components 1–8, 10 v pipeline.md §4 | Component 9 (MEMORY) — instrukce je agent-side, controller-side vulcan-find injection chybí → **Session C** |
| AID-012 | Self-audit FSM step | compliance.json schema + evaluate_compliance_checks() — základ dimenzí | Dedicated self-audit agent dispatch před GATES (agent dostane FSM checklist, produkt = self_audit.json) chybí → **Session D** |
| AID-013 | /aid-reflect | aid-compliance-report.sh --reflect — manuální PM nástroj | Auto-dispatch po každém EPICu, orchestrátor aktivně čte + reaguje → **Session D** |

### ❌ Neimplementováno

| AID ID | Téma | Priorita | Session |
|---|---|---|---|
| AID-007 | step-N-verify.md lazy template | low | Session D (enabler AID-026) |
| AID-008 | Auto-pickup queue po done-advance | low | standalone |
| AID-009 | handoff.json (auto-handoff) | high | Session D |
| AID-010 | DoD per task (strukturovaný schema) | high | Session D/E |
| AID-011 | Plan Lessons v Qdrant | high | **Session C** |
| AID-014 | Model redistribuce (adversarial → Opus) | medium | Session E |
| AID-015 | Test-from-spec (AC → executable test fixtures) | high | Session E |
| AID-017 | CP4b verifier na auditor changes | medium | Session E |
| AID-018 | Memory Audit Pass / INVALIDATE trigger | medium | Session C (navazuje na AID-011) |
| AID-019 | Queue file ownership preflight | low | standalone |
| AID-020 | Visual context size budget | low | Session F/standalone |
| AID-021 | Orphan sessions (REQUIRES PM DECISION) | - | standalone |
| AID-022 | Per-EPIC cost/wallclock budget + kill switch | medium | Session F |
| AID-023 | WAITING_FOR_PM FSM state | medium | Session F |
| AID-024 | PLAN BOUNDARY L-fixes sekvenčně | low | standalone |
| AID-025 | /aid-plan from-roadmap | low | standalone |
| AID-026 | Deterministic compliance auditor (timeline.jsonl) | high | **Session D** |
| AID-027 | Telemetry layer (per-step + mock_ratio) | high | Session D |
| AID-028 | Standards-as-code s version/applies-to | low | standalone |
| AID-029 | Remove the affordance (capability constraint) | medium | Session E |
| AID-030 | Difficulty-adjusted dispatch | medium | Session E |
| AID-031 | Adversarial commit message format | medium | Session E |
| AID-032 | Sub-agent isolation verification | medium | Session E |
| AID-033 | Security scan skill na konci Plánu | medium | Session E |
| AID-034 | Code quality skill po každém EPICu | medium | Session E |
| AID-035 | Plan-level lifecycle closure (status: draft → done) | low | Session D / standalone |
| AID-036 | Vibe-coding-aware time/cost estimator (pre-flight) | medium | Session D (po AID-027) |

> **Update 2026-05-09:** AID-034 doplněno do `AID-v3-architectural-inventory.md` (předtím chybělo). AID-035 přidáno na základě empirického nálezu z auditu archive/ (39/40 plánů zůstalo ve `status: draft` — strukturální evidence chybějící plan-level closure).
> **Update 2026-05-10:** AID-036 přidáno na základě P021 reflection telemetrie — pre-flight estimátor času/tokenů/ceny založený na empirické baseline (per-role × per-effort), konzumuje AID-027 data, plní AID-022 budget defaults.
> **Update 2026-05-10 (P036 shipped):** AID-035 (plan-level closure) PARTIAL — `/aid-plan write` Step 9 nyní vynucuje CP1 lifecycle review před EXECUTE; automatický `done-advance` hook + status update chybí (to je zbývající scope AID-035). Completeness Gate #17 rozšířen na 24 sub-checks (17a-e + #19). IMP-094..099 přidány do Oddíl 5.

---

## Oddíl 4 — Session roadmap (doporučené pořadí)

### Aktuálně: Measurement period (1–2 týdny)

**Žádná nová session.** 5+ EPICů reálné práce na 2+ projektech (vulcan + sousto), pak:
```bash
aid-compliance-report.sh --era post-session-b --reflect
aid-compliance-report.sh --compare post-session-a,post-session-b
```
Cíle:
- force_override count < 10% (baseline: 40% pre-Session-B)
- 0 EPICů bez verifier_outputs
- Identifikovat nové bypass módy pro Session C priority calibration

Výsledky zapsat do `docs/plans/AID-v3-diagnostic-findings-post-B.md`.

---

### Session C — Memory & Learning (~12–16h)

**Motivace:** Krok 0 ukázal 94 % empty memory reads. Bez paměti agenti ignorují existující vzory,
navrhují duplikátní implementace, a každý EPIC začíná bez kontextu předchozích.

| AID ID | Téma | Effort | Pořadí |
|---|---|---|---|
| AID-002 (dokončení) | Controller-side vulcan-find injection PŘED dispatch | 2h | 1 |
| AID-011 | Plan Lessons Qdrant schema + write/read pipeline | 4h | 2 |
| AID-018 | Memory Audit Pass + INVALIDATE trigger na PLAN BOUNDARY | 4h | 3 |
| AID-013 (lehká verze) | /aid-reflect auto-dispatch post-DONE (čte lessons + compliance) | 4h | 4 |

**Existující draft:** `.aid-o/plans/P031-agent-memory-qdrant.md` (status: approved, z 2026-03-19) — potřebuje refresh/brainstorm s aktuálním kontextem.

**Prerekvizita od PM před brainstormem:** výsledky measurement period (post-B diagnostic).

---

### Session D — Self-Audit & Observability (~12–16h)

**Motivace:** Mít ground truth na co agent reálně dělal (vs. co tvrdí). AID-026 je foundation
pro kalibraci AID-012 — bez timeline.jsonl parseru je self-audit fabricatable.

| AID ID | Téma | Effort | Pořadí |
|---|---|---|---|
| AID-007 | step-N-verify.md lazy template | 1h | 1 (enabler) |
| AID-026 | Deterministic compliance auditor (timeline.jsonl bash parser) | 8h | 2 (foundation) |
| AID-027 | Telemetry layer (per-step metrics, test_mock_ratio, time anomaly) | 6h | 3 |
| AID-012 | Self-audit FSM dispatch (agent dostane FSM checklist, produkuje self_audit.json) | 6h | 4 (kalibrovaný AID-026) |
| AID-009 | handoff.json (A1 varianta — agent-written, strukturovaný) | 4h | 5 |

**Conflict 1 decision** (PM): AID-012 bez AID-026 prerekvizity (position_A, uncalibrated) nebo až po AID-026 (position_B)?
- position_A: AID-012 ihned → benefit za 6h, risk fabricated self-audit
- position_B: AID-026 → AID-012 → 14h před prvním benefitem, ale věrohodné

---

### Session E — Quality & Integrity (~14–18h)

**Motivace:** Behavioral oracles (testy nepsané implementerem), adversarial commit format,
security/code quality skills, model redistribuce, capability constraints.

| AID ID | Téma | Effort |
|---|---|---|
| AID-010 | DoD per task (structured schema: functional/artifacts/evidence/out_of_scope) | 8h |
| AID-015 | Test-from-spec (AC → test fixtures generované v plan-writing před dispatch) | 8–10h |
| AID-031 | Adversarial commit message format (parseable header, CP2 cross-check) | 3h |
| AID-033 | Security plan skill na konci Plánu (cross-EPIC scope) | 4h |
| AID-034 | Code quality skill po každém EPICu (dead code, duplicity, naming) | 4h |
| AID-035 | Plan-level closure (done-advance hook + plan status update) | 2h |
| AID-036 | Pre-flight vibe-coding estimator (aid-estimate.sh + heuristika + /aid-run integration) | 5h |
| AID-014 | Model redistribuce (targeted: security verifier + auditor → Opus) | 1h |
| AID-017 | CP4b verifier na auditor-applied changes | 3h |
| AID-029 | Remove affordance — phase 1 (permissions.yaml write_paths whitelist) | 4h |
| AID-030 | Difficulty-adjusted dispatch (classify_step: easy/medium/hard) | 4h |

**Conflict 2 decision** (PM): AID-010 first nebo AID-015 first?
**Conflict 3 decision** (PM): targeted redistribuce (security+auditor → Opus) nebo plošná?

---

### Session F — Operational Polish (low priority, standalone kdykoli)

| AID ID | Téma | Effort |
|---|---|---|
| AID-022 | Per-EPIC cost/wallclock budget + Telegram alert | 3h |
| AID-023 | WAITING_FOR_PM FSM state | 4h |
| AID-020 | Visual context size budget (context_budgets.yaml) | 2h |
| AID-019 | Queue file ownership preflight (optimistic merge protection) | 4h |
| AID-024 | PLAN BOUNDARY L-fixes sequential | 3h |
| AID-025 | /aid-plan from-roadmap | 4h |
| AID-021 | Orphan sessions decision (REQUIRES PM DECISION) | 1–2h |
| AID-028 | Standards-as-code s version/applies-to | 6h |
| AID-008 | Auto-pickup queue po done-advance | 2h |

---

## Oddíl 5 — IMP backlog items v scope AID v3

Toto jsou backlog položky (IMP-NNN) které jsou přímo relevantní pro AID v3 sessions:

| IMP ID | Téma | Priorita | Session |
|---|---|---|---|
| IMP-085 | Automatizace --reflect (auto-trigger po N EPICů / Telegram při SYSTEMATIC) | medium | standalone nebo Session C |
| IMP-086 | Automated brainstorming (Opus orchestrátor → Sonnet) | medium-high | Session C příprava |
| IMP-087 | aid-epic-to-json.sh ARG_MAX bug pro plány >120 KB | medium | standalone (bug) |
| IMP-088 | docs-writer role rejected, valid je docs | low | standalone (bug, 30 min) |
| IMP-089 | Configurable branch convention (wan feature/p* pattern false alarms) | low | standalone |
| IMP-094 | test-cp1-grounding.sh: chybí negative-case fixture (well-grounded plan → 0 extractions) | low | standalone (P035 follow-up) |
| IMP-095 | Shellcheck CI job / pre-commit pro scripts/tests/*.sh | low | standalone (CI setup) |
| IMP-096 | plan-writing.md §Frontmatter: stale `type: plan` příklad → update na `type: regular` + enum komentář | low | standalone (P036 follow-up) |
| IMP-097 | aid-plan.md: Mode: Generate EPIC validate krok + auto-detect tabulka neznají nový enum (`regular\|bug-fix\|refactor\|docs`) | low | standalone (P036 follow-up) |
| IMP-098 | test-plan-quality-enforcement.sh: layer 1 fixture self-referenční, layer 1c trvale SKIP (--state-file existuje od v2.18.x) | low | standalone (P036 follow-up) |
| IMP-099 | plan-writing.md #19: přidat větu že false-positive pre-screen aktivace je OK — autoritativní gate je Q2/Q3 LLM | low | standalone (P036 follow-up) |

---

## Oddíl 6 — Otevřené PM decisions z inventáře

| Conflict ID | Otázka | Blokuje |
|---|---|---|
| Conflict 1 | AID-012 self-audit: uncalibrated okamžitě (position_A) nebo čekat na AID-026 (position_B)? | Session D pořadí |
| Conflict 2 | DoD schema first (AID-010) nebo test-from-spec first (AID-015)? | Session E pořadí |
| Conflict 3 | Model redistribuce: targeted (security+auditor) nebo plošná? | Session E scope |
| AID-021 | Orphan sessions: zrušit nebo aid-orphan-import.sh? | Session F |
| AID-022 | Telegram budget alert: CC Updates skupina nebo jiný kanál? | Session F |

---

## Oddíl 7 — Souhrn v číslech

| Kategorie | Počet | AID IDs |
|---|---|---|
| ✅ Hotovo | 7 | 001, 003, 004, 005, 006, 016, 032 |
| 🟡 Partial | 3 | 002, 012, 013 |
| ❌ Session C | 3–4 | 002(rest), 011, 018, 013(plná verze) |
| ❌ Session D | 5 | 007, 009, 026, 027, 012(plná) |
| ❌ Session E | 9 | 010, 014, 015, 017, 029, 030, 031, 033, 034 |
| ❌ Session F | 9 | 008, 019, 020, 021, 022, 023, 024, 025, 028 |
| **Celkem** | **36** | AID-001 až AID-036 |

**Pokrytí Sessions A+B: ~30–35 % inventory.** Zbývá ~65 % — ale nejhorší cheat surfaces jsou z velké části adresovány.

---

*Dokument aktualizovat po každé session nebo measurement period. Zdrojové dokumenty: `AID-v3-architectural-inventory.md` (spec), `AID-v3-initial-plan.md` (PM zápisník), `docs/plans/AID-v3-diagnostic-findings-post-*.md` (empirická data).*
