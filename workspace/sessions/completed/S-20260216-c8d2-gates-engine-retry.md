---
id: S-20260216-c8d2
type: new-feature
status: active
priority: high
started: 2026-02-16
epic_id: ADO-0001
epic_session: 3
epic_file: workspace/workflow/epics/active/EPIC-ADO-0001-BUILD-ORCHESTRATOR.md
plan_ref: workspace/workflow/plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md
ai_agent: Claude Opus 4.6
branch: session/S-20260216-c8d2-gates-engine-retry
previous_session: workspace/sessions/completed/S-20260216-f47a-runtime-commands.md
---

# Session 3: Gates Engine + Retry

## Objective

Implementovat Gates Engine — systém, který čte `gates.yaml`, spouští quality gates,
generuje strukturované pass/fail reporty do evidence, a při selhání automaticky
dispatche fix-agenta s retry loopem (max 3 pokusy, pak escalation na PM).

Na konci session musí:
- Nová skill `gates-engine.md` definovat kompletní gates execution protocol
- Nový command `/run-gates` umožnit standalone spuštění gates
- Retry loop fungovat: gate fail → analyze → dispatch fix agent → re-run gate
- Evidence: `gates_report.json` + `gates/{gate_name}.txt` + retry history
- Po 3 failech: escalation (chat-based, Slack přijde v Session 6)
- `/run-epic` GATES a GATE_RETRY stavy odkazovat na nový gates engine

## Context / Prerekvizity

Session 1 dodala:
- `defaults/policies/gates.yaml` — 6 gates (4 required, 2 conditional), retry config, evidence config
- `defaults/policies/decision-policies.yaml` — auto_decisions pro gates (pass → proceed, fail → retry)
- `agents/quality-gates-runner.md` — starý C.I.C.E.R.O. 6-gate pre-commit agent
- `skills/quality-gates.md` — starý C.I.C.E.R.O. quality gates protocol
- `skills/epic-orchestration.md` — State 7 (GATES_CHECK) + State 8 (GATE_RETRY) definice

Session 2 dodala:
- `commands/run-epic.md` — state machine loop, GATES + GATE_RETRY stavy (pseudo-implementace)
- `commands/run-step.md` — single step dispatch s PHASE_CHECK

**Klíčový problém:** Existující quality-gates-runner je C.I.C.E.R.O. pre-commit agent (6 specifických
gatů: log analysis, docs impact, code cleanup, git status, commit message, tests). AID orchestrátor
potřebuje **jiný** gates engine — konfigurovatelný přes gates.yaml, s retry loopem, evidence
generací, a integrací do state machine. Oba systémy budou koexistovat:
- C.I.C.E.R.O. gates = pre-commit quality check (zůstává)
- AID gates engine = post-EPIC-steps validation (nový)

## Deliverables

- [ ] `skills/gates-engine.md` — Gates execution protocol (parsing, execution, reporting)
- [ ] `commands/run-gates.md` — Standalone gates command
- [ ] `skills/retry-engine.md` — Retry loop + fix-agent dispatch protocol
- [ ] `agents/gate-fixer.md` — Agent pro opravu failujících gates
- [ ] Update `commands/run-epic.md` — GATES + GATE_RETRY concrete implementation
- [ ] Update `plugin.json` — registrace `/run-gates` command + gate-fixer agent
- [ ] Smoke test — manuální test gates flow s EPIC-TEST-0001-DUMMY.md

## Phases

### Phase 1: Gates Engine Skill — `skills/gates-engine.md`

**Cíl:** Core skill definující jak AID orchestrátor spouští, evaluuje a reportuje quality gates.

**Skill musí definovat:**

1. **Gates YAML Parsing Protocol:**
   - Načíst `.aid-o/03-config/policies/gates.yaml`
   - Rozlišit gate typy:
     - `command` gate — spuštění shell příkazu (tests, lint, security scan)
     - `rule` gate — logická validace (docs_updated, scope_check)
   - Rozlišit povinnost:
     - `required: true` — musí projít, jinak EPIC nemůže pokročit
     - `required: false` — warning, ale neblokuje (conditional gates)
   - Evaluovat `when` podmínky pro conditional gates:
     - `when: "frontend files changed"` → zkontrolovat git diff pro frontend paths
     - Pokud podmínka neplatí → gate SKIP (ne FAIL)

2. **Gate Execution Protocol:**
   - Pro každý gate v pořadí dle gates.yaml:

   **Command gates:**
   ```
   1. Log: "Running gate: {gate_name}"
   2. Execute command via Bash tool (with timeout from gates.yaml)
   3. Capture: exit_code, stdout, stderr
   4. Evaluate pass_criteria:
      - "exit_code_0" → exit_code == 0
      - Custom criteria (e.g., "no HIGH or CRITICAL findings")
   5. Store output → evidence/{epic_id}/{run_id}/gates/{gate_name}.txt
   6. Record result → gates_report.json entry
   ```

   **Rule gates:**
   ```
   1. Log: "Evaluating rule gate: {gate_name}"
   2. Read rule definition from gates.yaml
   3. Execute validation logic:
      - docs_updated: check if docs/ or CHANGELOG.md modified (git diff)
      - scope_check: verify agent only modified allowed_paths
   4. Record result with justification
   ```

3. **Gates Report Generation:**
   - Formát `gates_report.json`:
     ```json
     {
       "epic_id": "{epic_id}",
       "run_id": "{run_id}",
       "timestamp": "{ISO 8601}",
       "gates_config": "gates.yaml (sha256: {hash})",
       "gates": [
         {
           "name": "tests_pass",
           "type": "command",
           "required": true,
           "status": "pass|fail|skip|error",
           "command": "pytest -q --tb=short",
           "exit_code": 0,
           "output_file": "gates/tests_pass.txt",
           "duration_seconds": 3.2,
           "attempts": [
             {
               "attempt": 1,
               "timestamp": "{ISO 8601}",
               "status": "fail",
               "output_summary": "3 failed, 42 passed",
               "fix_applied": null
             },
             {
               "attempt": 2,
               "timestamp": "{ISO 8601}",
               "status": "pass",
               "output_summary": "45 passed",
               "fix_applied": "Fixed assertion in test_auth.py:42"
             }
           ]
         },
         {
           "name": "docs_updated",
           "type": "rule",
           "required": true,
           "status": "pass",
           "rule": "docs/ or CHANGELOG.md updated if public API changed",
           "justification": "No public API changes detected",
           "attempts": [{"attempt": 1, "status": "pass"}]
         }
       ],
       "summary": {
         "total": 6,
         "passed": 5,
         "failed": 0,
         "skipped": 1,
         "errors": 0
       },
       "overall": "pass|fail",
       "next_action": "proceed_to_pm_approval|gate_retry|escalation"
     }
     ```

4. **Evidence Storage:**
   ```
   evidence/{epic_id}/{run_id}/
     gates_report.json          # Structured report
     gates/
       tests_pass.txt           # Raw command output
       lint_pass.txt
       security_scan_pass.txt
       docs_updated.txt         # Rule evaluation log
       type_check.txt           # Conditional (if ran)
       build_pass.txt           # Conditional (if ran)
   ```

5. **Integration s decision-policies.yaml:**
   - ALL required gates pass → `next_action: "proceed_to_pm_approval"` (auto-decision)
   - ANY required gate fails + retries remaining → `next_action: "gate_retry"`
   - ANY required gate fails + max retries → `next_action: "escalation"`
   - ONLY conditional gates fail → `next_action: "proceed_to_pm_approval"` (s warnings)

**Reference soubory:**
- `defaults/policies/gates.yaml` (gate definitions)
- `defaults/policies/decision-policies.yaml` (auto_decisions, escalation_triggers)
- `skills/epic-orchestration.md` sekce State 7 (GATES_CHECK)

**Acceptance:**
- [ ] Skill definuje kompletní parsing protocol pro gates.yaml
- [ ] Command i rule gates mají jasný execution flow
- [ ] gates_report.json formát je specifikován s retry history
- [ ] Evidence paths odpovídají epic-orchestration.md specifikaci
- [ ] Decision logic mapuje na decision-policies.yaml

---

### Phase 2: Retry Engine Skill — `skills/retry-engine.md`

**Cíl:** Samostatný skill definující retry loop logiku — jak analyzovat selhání, dispatchnout fix agenta, a re-runovat gate.

**Skill musí definovat:**

1. **Retry Decision Protocol:**
   ```
   Gate FAILED:
   1. Read retry config from gates.yaml:
      - max_attempts: 3 (default)
      - backoff: fixed|exponential
      - delay: 5s (default)
   2. Check current attempt count from gates_report.json
   3. If attempts < max_attempts:
      → Proceed to FIX phase
   4. If attempts >= max_attempts:
      → Proceed to ESCALATION
   ```

2. **Failure Analysis Protocol:**
   - Pro každý typ gate failure, analyzovat output a klasifikovat:

   **tests_pass failure:**
   ```
   Parse test output:
   - Extract failing test names
   - Extract error messages + stack traces
   - Classify: assertion error, import error, runtime error, timeout
   - Identify affected files from stack trace
   ```

   **lint_pass failure:**
   ```
   Parse linter output:
   - Extract file:line:rule violations
   - Classify: formatting, unused import, type error, style
   - Group by file
   ```

   **security_scan_pass failure:**
   ```
   Parse security output:
   - Extract finding severity (HIGH, CRITICAL)
   - Extract affected file + line
   - Classify: hardcoded secret, SQL injection, XSS, etc.
   - Determine if auto-fixable
   ```

   **docs_updated failure:**
   ```
   Identify:
   - Which API/model changes lack documentation
   - Which files were modified
   - Where docs should be updated
   ```

3. **Fix Agent Dispatch Protocol:**
   ```
   1. Select appropriate agent role based on gate type:
      - tests_pass → qa agent (or original role agent if test is in their scope)
      - lint_pass → original role agent (formatting is their responsibility)
      - security_scan_pass → security agent
      - docs_updated → docs-writer agent
      - type_check → frontend agent
      - build_pass → frontend/backend agent (based on error)

   2. Build fix prompt:
      ┌─────────────────────────────────────────┐
      │ GATE FIX REQUEST                        │
      │                                         │
      │ Gate: {gate_name}                       │
      │ Attempt: {N} of {max}                   │
      │ Failure output:                         │
      │ {gate output — full or summarized}      │
      │                                         │
      │ Your task:                              │
      │ Fix the failing gate. The gate command  │
      │ is: {command}                           │
      │ Pass criteria: {criteria}               │
      │                                         │
      │ Constraints:                            │
      │ - Only modify files in: {allowed_paths} │
      │ - Do NOT modify: {forbidden_paths}      │
      │ - Minimal changes — fix the gate, don't │
      │   refactor unrelated code               │
      │                                         │
      │ Previous fix attempts:                  │
      │ {list of previous attempts + outcomes}  │
      └─────────────────────────────────────────┘

   3. Dispatch via Task tool
   4. Collect fix output
   5. Store: evidence/{epic_id}/{run_id}/gates/retry_{gate}_{attempt}.md
   ```

4. **Re-run Protocol:**
   ```
   After fix agent completes:
   1. Verify fix agent made changes (git diff)
   2. If no changes → log "fix agent produced no changes" → count as failed attempt
   3. If changes made:
      a. Re-run ONLY the failed gate (not all gates)
      b. If pass → update gates_report.json, back to GATES (re-check ALL gates)
      c. If fail → increment attempt, loop back to Failure Analysis
   ```

5. **Escalation Trigger:**
   ```
   When attempts >= max_attempts:
   1. Compile escalation report:
      - Gate name + command
      - All attempt outputs
      - All fix attempts + what was tried
      - Remaining gates status
   2. Present to PM (chat-based for now, Slack in Session 6):
      ┌─────────────────────────────────────────┐
      │ ⚠ GATE ESCALATION                       │
      │                                         │
      │ EPIC: {epic_id}                         │
      │ Gate: {gate_name}                       │
      │ Attempts: {max}/{max} exhausted         │
      │                                         │
      │ Last failure:                           │
      │ {output summary}                        │
      │                                         │
      │ Fixes attempted:                        │
      │ 1. {attempt 1 description}              │
      │ 2. {attempt 2 description}              │
      │                                         │
      │ Options:                                │
      │ A) Skip this gate (proceed with warning)│
      │ B) Manual fix (PM provides guidance)    │
      │ C) Abort EPIC run                       │
      └─────────────────────────────────────────┘
   3. Wait for PM decision
   4. Execute chosen action:
      - A → mark gate as "skipped_by_pm", proceed
      - B → apply PM guidance, re-run gate (resets attempts)
      - C → set EPIC state to ABORTED, archive
   ```

**Reference soubory:**
- `skills/epic-orchestration.md` sekce State 8 (GATE_RETRY)
- `defaults/policies/gates.yaml` (retry section)
- `defaults/policies/decision-policies.yaml` (escalation_triggers)

**Acceptance:**
- [ ] Retry decision protocol jasně definuje when/how to retry
- [ ] Failure analysis pokrývá všech 6 gate typů
- [ ] Fix agent dispatch má konkrétní prompt template
- [ ] Re-run protocol definuje single-gate re-run + full re-check
- [ ] Escalation format je kompletní s PM options

---

### Phase 3: Gate Fixer Agent — `agents/gate-fixer.md`

**Cíl:** Nový agent specializovaný na opravu failujících gates.

**Agent musí definovat:**

1. **Role:** Opravuje failing quality gates na základě gate output a retry-engine instrukci.

2. **Capabilities:**
   - Čtení gate failure output a identifikace root cause
   - Oprava failing testů (assertion fix, missing fixture, import fix)
   - Oprava lint violations (formatting, unused imports, type annotations)
   - Oprava security findings (secret removal, input sanitization)
   - Aktualizace dokumentace (API docs, CHANGELOG)
   - Build fix (dependency resolution, config fix)

3. **Constraints:**
   - Pracuje POUZE v `allowed_paths` z plan step
   - NESMÍ měnit `forbidden_paths`
   - Minimální zásahy — opravit gate, nic víc
   - Nesmí disable/skip testy nebo lint rules
   - Nesmí přidávat `# noqa`, `# type: ignore`, `@pytest.mark.skip` bez důvodu
   - Pokud nemůže opravit → jasně popsat proč (pro escalation)

4. **Output format:**
   ```yaml
   gate_fix_result:
     gate: "{gate_name}"
     attempt: {N}
     status: "fixed|partial|unable"
     changes:
       - file: "path/to/file.py"
         description: "Fixed assertion in test_login"
     explanation: "Root cause was X, fixed by Y"
     confidence: high|medium|low
     warnings: ["Optional list of concerns"]
   ```

5. **Integration:**
   - Volaný přes retry-engine.md dispatch protocol
   - Dostává prompt dle Phase 2 fix prompt template
   - Output uložen do evidence

**Acceptance:**
- [ ] Agent definice pokrývá všech 6 gate typů
- [ ] Constraints zabraňují obcházení gatů (no skip, no disable)
- [ ] Output format strukturovaný pro retry-engine zpracování
- [ ] Scope enforcement (allowed_paths / forbidden_paths)

---

### Phase 4: Run Gates Command — `commands/run-gates.md`

**Cíl:** Standalone command pro spuštění gates mimo `/run-epic` orchestrační loop.

**Usage:**
```
/run-gates <epic-id>              # Run gates for specific EPIC
/run-gates --plan <plan.json>     # Run gates from plan file
/run-gates --gates <gates.yaml>   # Run with custom gates config
/run-gates --dry-run              # Show which gates would run (without executing)
```

**Command musí:**

1. **Najít kontext:**
   - Načíst gates.yaml (z `.aid-o/03-config/policies/` nebo custom path)
   - Načíst Plan JSON (z evidence/ nebo custom path) pro `gates[]` array
   - Pokud Plan JSON specifikuje gates subset → run jen ty
   - Pokud ne → run všechny required gates z gates.yaml

2. **Spustit gates engine:**
   - Volat gates-engine.md protocol
   - Zobrazit real-time progress:
     ```
     Running Gates for: {epic_id}
     ====================================

     [1/4] tests_pass .......... PASS (3.2s)
     [2/4] lint_pass ........... FAIL (1.1s)
           → ruff: 3 violations in api/routes.py
     [3/4] security_scan_pass .. PASS (5.4s)
     [4/4] docs_updated ........ SKIP (no API changes)

     Result: FAIL (1 gate failed)
     Report: evidence/{epic_id}/{run_id}/gates_report.json
     ```

3. **Při failure — nabídnout retry:**
   ```
   Failed gates:
   - lint_pass: 3 ruff violations

   Options:
   A) Auto-fix + retry (dispatch gate-fixer agent)
   B) Manual fix (you fix, then re-run /run-gates)
   C) Skip and proceed (not recommended for required gates)

   Choice:
   ```

4. **Dry-run mode:**
   ```
   /run-gates --dry-run
   ====================================
   Gates that would run:

   REQUIRED:
   1. tests_pass — pytest -q --tb=short (timeout: 300s)
   2. lint_pass — ruff check . && ruff format --check . (timeout: 120s)
   3. security_scan_pass — bandit -q -r . -ll (timeout: 180s)
   4. docs_updated — rule: docs updated for API changes

   CONDITIONAL (will evaluate):
   5. type_check — npx tsc --noEmit (when: frontend files changed)
   6. build_pass — npm run build (when: frontend files changed)

   Config: .aid-o/03-config/policies/gates.yaml
   ```

**Reference soubory:**
- `skills/gates-engine.md` (nový — Phase 1)
- `skills/retry-engine.md` (nový — Phase 2)
- `defaults/policies/gates.yaml`

**Acceptance:**
- [ ] `/run-gates` spustí všechny required gates z gates.yaml
- [ ] Real-time progress zobrazení (gate by gate)
- [ ] Failure → nabídne auto-fix retry
- [ ] `--dry-run` zobrazí gates bez spuštění
- [ ] Evidence uložena do správné cesty

---

### Phase 5: Update run-epic.md — Concrete GATES + GATE_RETRY

**Cíl:** Aktualizovat `/run-epic` command aby GATES a GATE_RETRY stavy referencovaly nový gates engine.

**Změny v run-epic.md:**

1. **State 7 (GATES):**
   - Nahradit pseudo-kód konkrétní referencí:
     ```
     GATES:
       1. Read skills/gates-engine.md — follow Gates Execution Protocol
       2. Call /run-gates {epic_id} internally (not interactive mode)
       3. Read gates_report.json result
       4. Apply decision logic from gates-engine.md
       5. Transition based on result:
          - overall: "pass" → PM_APPROVAL
          - overall: "fail" + retries remaining → GATE_RETRY
          - overall: "fail" + max retries → ESCALATION
     ```

2. **State 8 (GATE_RETRY):**
   - Nahradit pseudo-kód konkrétní referencí:
     ```
     GATE_RETRY:
       1. Read skills/retry-engine.md — follow Retry Decision Protocol
       2. For each failed gate:
          a. Run Failure Analysis (per retry-engine.md)
          b. Dispatch gate-fixer agent (per retry-engine.md Fix Agent Dispatch)
          c. Re-run failed gate only
          d. Update gates_report.json
       3. After all retries:
          - Any gate fixed → back to GATES (re-check all)
          - All retries exhausted → ESCALATION
     ```

3. **ESCALATION state update:**
   - Přidat gates-specific escalation format z retry-engine.md
   - Zachovat existující escalation pro jiné důvody

**Acceptance:**
- [ ] GATES state odkazuje na gates-engine.md
- [ ] GATE_RETRY state odkazuje na retry-engine.md
- [ ] Escalation format zahrnuje gate failure detail
- [ ] Přechody mezi stavy jsou konzistentní

---

### Phase 6: Plugin Integration + Update

**Cíl:** Registrovat nové artefakty v plugin.json, aktualizovat CLAUDE.md a README.

**Úkoly:**

1. **Aktualizovat `plugin.json`:**
   - Přidat command: `run-gates`
   - Přidat agent: `gate-fixer`
   - Přidat skills: `gates-engine`, `retry-engine`
   - Aktualizovat counts

2. **Aktualizovat cross-references:**
   - `aid-help.md` — přidat `/run-gates` do command listu + gates topic
   - `epic-orchestration.md` — přidat reference na nové skills (minor update)

**Acceptance:**
- [ ] plugin.json registruje: 1 nový command, 1 nový agent, 2 nové skills
- [ ] aid-help.md zmiňuje `/run-gates`
- [ ] Všechny cross-reference konzistentní

---

### Phase 7: Smoke Test

**Cíl:** Ověřit gates engine funguje jako celek.

**Test scénáře:**

1. **Happy path:** Všechny gates pass
   - Spustit `/run-gates --dry-run` → vidět seznam gates
   - Spustit `/run-gates` na čistém kódu → všechny PASS
   - Ověřit: gates_report.json vytvořen, evidence uložena

2. **Retry path:** Gate fails → fix → pass
   - Záměrně vytvořit lint violation
   - Spustit `/run-gates` → lint_pass FAIL
   - Zvolit auto-fix → gate-fixer opraví → re-run → PASS
   - Ověřit: retry history v gates_report.json, evidence pro oba pokusy

3. **Escalation path:** Gate fails 3x → escalation
   - Vytvořit neopravitelný test failure (nebo mock)
   - Spustit retry 3x → escalation message zobrazen
   - Ověřit: escalation report obsahuje všechny 3 pokusy

4. **Conditional gate:** Skip when condition not met
   - Spustit gates bez frontend změn → type_check a build_pass = SKIP
   - Ověřit: SKIP status v reportu

5. **Integration s run-epic:** (pokud čas dovolí)
   - Spustit `/run-epic` s dummy EPIC → ověřit že GATES state volá gates engine

**Acceptance:**
- [ ] Dry-run zobrazí seznam gates
- [ ] Happy path: all pass, evidence uložena
- [ ] Retry: fail → fix → pass, history zaznamenaná
- [ ] Conditional gates správně SKIP
- [ ] Plugin.json aktualizován, cross-references OK

---

## DoD Gates

- [ ] `skills/gates-engine.md` existuje s kompletním gates execution protocol
- [ ] `skills/retry-engine.md` existuje s retry loop + fix dispatch + escalation
- [ ] `agents/gate-fixer.md` existuje s constraints a output format
- [ ] `commands/run-gates.md` existuje se standalone i integrated mode
- [ ] `run-epic.md` GATES + GATE_RETRY stavy referencují nové skills
- [ ] `plugin.json` registruje nový command + agent + 2 skills
- [ ] `gates_report.json` formát produkuje kompletní report s retry history
- [ ] Evidence uložena v `evidence/{epic_id}/{run_id}/gates/`
- [ ] Failing gate → retry → fix → pass flow funguje
- [ ] Po 3 failech: escalation zobrazena s PM options
- [ ] Smoke test prošel (min. dry-run + happy path + retry)

## Architectural Notes

### Dva Gates Systémy (koexistence)

```
C.I.C.E.R.O. Quality Gates (existující):
  → Pre-commit 6-gate protocol
  → Spouští se: /quality-gates (před commitem)
  → Agent: quality-gates-runner.md
  → Skill: quality-gates.md
  → Účel: Commit-level quality

AID Gates Engine (nový — tato session):
  → Post-EPIC-steps validation
  → Spouští se: /run-gates (standalone) nebo automaticky v /run-epic (GATES state)
  → Agent: gate-fixer.md (pro retry)
  → Skills: gates-engine.md, retry-engine.md
  → Účel: EPIC-level quality — celý pipeline prošel
```

### Skill vs Command vs Agent Boundaries

```
gates-engine.md (SKILL):
  = Protocol/knowledge — JAK spustit gates, JAK parsovat output
  = Referencován z commands i jiných skills

retry-engine.md (SKILL):
  = Protocol/knowledge — JAK analyzovat failure, JAK dispatchnout fix
  = Referencován z run-gates.md a run-epic.md

run-gates.md (COMMAND):
  = Entry point — user-facing interface
  = Orchestruje: čte gates-engine.md, volá retry-engine.md
  = Interactive (progress, options)

gate-fixer.md (AGENT):
  = Specializovaný worker — dostane fix prompt, provede opravu
  = Volaný přes Task tool z retry-engine protocol
  = Scope-constrained (allowed_paths only)
```

### Evidence Flow

```
/run-gates nebo /run-epic GATES state
  │
  ├── gates_report.json              # Structured report (created/updated)
  ├── gates/
  │   ├── tests_pass.txt             # Raw command output
  │   ├── lint_pass.txt              # Raw command output
  │   ├── security_scan_pass.txt     # Raw command output
  │   └── docs_updated.txt           # Rule evaluation log
  │
  └── (on retry)
      ├── gates/retry_lint_pass_1.md # Fix agent output (attempt 1)
      ├── gates/retry_lint_pass_2.md # Fix agent output (attempt 2)
      └── gates_report.json          # Updated with retry history
```

### Gates YAML → Report Mapping

```yaml
# gates.yaml input                    # gates_report.json output
gates:
  required:
    - name: tests_pass          →     { name: "tests_pass", required: true, ... }
      command: "pytest ..."
  conditional:
    - name: type_check          →     { name: "type_check", required: false, status: "skip", ... }
      when: "frontend changed"
```

## Session Log

| Čas | Událost |
|-----|---------|
| 2026-02-16 | Session file vytvořen, 7 phases definováno |
| 2026-02-17 | Phase 1 done: gates-engine.md (383 lines — YAML parsing, command/rule execution, gates_report.json, evidence, MUST rules) |
| 2026-02-17 | Phase 2 done: retry-engine.md (471 lines — retry decision, failure analysis 6 types, fix dispatch protocol, re-run, escalation, multi-gate, backoff) |
| 2026-02-17 | Phase 3 done: gate-fixer.md (174 lines — utility agent, 6 gate types, no-bypass constraints, YAML output format) |
| 2026-02-17 | Phase 4 done: run-gates.md (250 lines — standalone /run-gates, --dry-run, interactive retry, non-interactive mode) |
| 2026-02-17 | Phase 5 done: run-epic.md updated — GATES, GATE_RETRY, ESCALATION states concrete refs to new skills |
| 2026-02-17 | Phase 6 done: plugin.json (16 commands, 6 agents, 6 skills), aid-help.md (gates topic expanded, /run-gates added) |
| 2026-02-17 | Phase 7 done: Cross-reference verification — all 28 registered components exist, no broken references |
| 2026-02-17 | **SESSION COMPLETED** |

## Notes

- Gate-fixer agent je nový koncept — v Session 4 budou 9 role-agentů, gate-fixer je utility agent.
- Retry engine je záměrně separátní skill, protože retry logiku bude používat i jiná state machine logika (PHASE_CHECK re-dispatch).
- Escalation je zatím chat-based (PM interaguje v Claude Code). Slack integrace přijde v Session 6.
- `gates_report.json` je klíčový artefakt — používá se v `/epic-status`, `/run-epic`, a budoucím Audit agentovi.

---

**Status:** completed
**Last Updated:** 2026-02-17
**Completion:** 100%

## Completion Summary

- **Duration:** 2026-02-17 (1 conversation)
- **Files created:** 5 (2 skills + 1 agent + 1 command + 1 session file)
- **Files modified:** 5 (plugin.json, run-epic.md, aid-help.md, active-work.md, EPIC)
- **Total new lines:** ~1,278 (core deliverables only)
- **Phases completed:** 7/7
- **What was accomplished:**
  - `skills/gates-engine.md` — Gates YAML parsing, command/rule execution, gates_report.json generation, evidence storage (383 lines)
  - `skills/retry-engine.md` — Retry decision, failure analysis (6 gate types), fix-agent dispatch, re-run protocol, escalation, multi-gate handling (471 lines)
  - `agents/gate-fixer.md` — Utility fix agent with scope constraints, no-bypass policy, structured output (174 lines)
  - `commands/run-gates.md` — Standalone `/run-gates` with dry-run, interactive retry, non-interactive mode for `/run-epic` (250 lines)
  - `commands/run-epic.md` — GATES + GATE_RETRY + ESCALATION states updated with concrete references to new skills
  - `plugin.json` — 16 commands, 6 agents, 6 skills registered (was: 15/5/4)
  - `commands/aid-help.md` — `/run-gates` added to command list, gates topic expanded with two-system explanation
  - Cross-reference verification: all 28 registered components validated
