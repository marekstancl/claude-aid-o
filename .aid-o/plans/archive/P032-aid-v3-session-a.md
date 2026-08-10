---
id: P032
type: plan
status: done
created: 2026-05-04
author: PM + AI
---

# Plan: AID v3 Session A — Foundation Hardening

## Stakeholder Brief

Session A je první konkrétní implementační fáze AID v3 redesignu řešící tři P0 compliance gaps identifikované forensickou analýzou 203 EPIC běhů (`docs/plans/AID-v3-diagnostic-findings.md`). **AID-001 — branch hygiene:** 65 % EPICs deklaruje práci na `main` bez task branche, čímž `done-advance` git merge ztrácí audit trail. **AID-005 — fake gates:** 100 % EPIC běhů má `gates_report.json` napsaný ručně místo skutečného spuštění `aid-run-gates.sh`. **AID-006 — missing config:** 71 % projektů nemá `execution.yaml`, takže gate runner neví co spustit. Plán dodává čtyři výstupy: deterministické bash enforcement v `aid-fsm.sh` a `aid-run-gates.sh`, lazy-created `execution.yaml` z auto-detected stacku (Python/TypeScript/Go/Rust/bash), live `compliance.json` per EPIC pro continuous measurement, a nový `svc-mcp-tg-bot` MCP server pro Telegram alerty na opakované FSM precondition fails (≥ 3× stejný fail). Backward compatibility řešena přes grandfather marker — existujících 203 EPIC běhů zůstává validních, nová pravidla se aplikují jen na runy inicializované po deploy. Implementace běží v izolovaném git worktree (eliminuje chicken-and-egg problém), pokrytí 16 bats unit assertions napříč 3 soubory. Effort ~12 hodin / 18 atomic commits / single PR. Cíl post-deploy: ≥ 80 % nových EPICs hit všechny 3 měřené compliance dimensions během prvních 5 EPICs napříč ≥ 2 projekty.

## Context

`docs/plans/AID-v3-diagnostic-findings.md` (forensická analýza 203 EPIC evidence dirs napříč 7 projekty, 2026-05-04) potvrdila že AID v2 FSM funguje na strukturální úrovni (235 `fsm_increment_fail` událostí ukazuje aktivní rejection neúplných verify souborů), ale selhává na obsahové úrovni:

- **AID-001 (branch hygiene):** 17/26 (65 %) `state.yaml` souborů deklaruje `branch: main`. Sousto-na-miru obsahuje verbatim přiznání `result: "implemented directly (FSM bypassed) — code merged to main"` ve 4 stepech jednoho EPICu. `done-advance` release sub-phase (krok 15) předpokládá `git merge epic/...` — bez task branche je merge no-op a release proběhne bez audit trailu.
- **AID-005 (fake gates):** 0/93 timeline.jsonl souborů obsahuje `aid-run-gates.sh` execution marker. 111/112 (99 %) `gates_report.json` má `overall: "pass"` (žádný fail napříč 100+ EPIC běhy = implausible). 97 % gate záznamů nemá `command` field. Self-audit z `agents-outputs.md` přiznává: *"Nespustil jsem aid-run-gates.sh. Napsal jsem gates_report.json ručně."*
- **AID-006 (missing execution.yaml):** 5/7 (71 %) projektů s evidence (vulcan, sousto-na-miru, wan, sousto-na-miru.broken, aid-orchestrator) NEMÁ per-project `execution.yaml`. Bez něj `aid-run-gates.sh` neví co spustit a agent místo toho generuje `gates_report.json` ručně s ad-hoc gate names (`docs_updated`, `syntax_check`, `import_audit`) které se per projekt liší — žádná cross-EPIC consistency.

Krok 1 (`docs/plans/AID-v3-subagent-isolation-test.md`, 12 empirických testů, 2026-05-04) potvrdil že Agent SDK dispatch dává sub-agentům izolovaný kontext a token budget — sub-agent zkonzumoval 103 094 tokenů v testu T6, hlavní okno dostalo jen JSON return + metadata. To umožňuje použít Agent dispatch pro implementer dispatchy v Session A bez kontaminace orchestrátorského okna.

Tento plán je první ze série, která postupně řeší P0 → P1 → P2 patterny z diagnostic findings. Sessions B (verifier dispatch enforcement, AID-003/004) a C (controller-side memory injection, AID-002) navazují po měření Session A impactu.

## Goal

Posunout 3 P0 compliance dimensions (branch hygiene, gates execution, execution.yaml presence) z 0–35 % na ≥ 95 % během prvních 5 post-deploy EPICs napříč ≥ 2 projekty, měřeno deterministicky přes per-EPIC `compliance.json` aggregátor.

## Scope

**In scope:**
- Branch enforcement v `aid-fsm.sh` PRE-FLIGHT (auto-checkout `task/E-{epic_id}/main`, mismatch detection, worktree mode handling, uncommitted-changes guard).
- Lazy-create `execution.yaml` v `aid-init` se stack auto-detection (Python, TypeScript, Go, Rust, bash) a per-stack template fragments composed do final yaml.
- Markery v `aid-run-gates.sh` (timeline events `gate_runner_start` / `gate_runner_complete`) a provenance fields (`_generated_by`, `_generated_at`, `_command_log`) v `gates_report.json`.
- FSM precondition `EXECUTE→GATES` checking `_generated_by` field (post-deploy EPICs only).
- Live `compliance.json` per EPIC v `done-advance` hooku se 6-dimension schema (3 measured pro Session A, 3 `null` pro budoucí Sessions B/C).
- Standalone `aid-compliance-backfill.sh` pro one-shot generování `compliance.json` pro 203 existujících EPIC dirs s `deploy_era: pre-session-a`.
- Parametrizovaný `aid-diagnostic.sh` z Krok 0 forensic logiky.
- Aggregátor `aid-compliance-report.sh` pro pre vs. post comparison.
- Nový MCP server `svc-mcp-tg-bot` (Python FastMCP, stdio + HTTP transport, port 8818) v `services/mcp-tg-bot/` se sdíleným tokenem v `/opt/eco/services/.env`.
- Telegram alert hook v `aid-fsm.sh` pro `fsm_precondition_repeated_fail` event (≥ 3 stejné fails na stejném EPICu) přes HTTP POST na `localhost:8818`, best-effort (graceful degradation).
- 16 bats unit assertions napříč třemi soubory (`test-aid-fsm.bats` 9 assertions, `test-aid-run-gates.bats` 3 assertions, `test-aid-init.bats` 4 assertions).
- Worktree development workflow s `.envrc` direnv bootstrap pro `AID_PLUGIN_PATH=$(pwd)/plugins/aid-orchestrator`.
- Release: version bump na v2.16.0 per CLAUDE.md 8-file sync, CHANGELOG entry, README roadmap update.

**Out of scope:**
- Memory Component 9 enforcement (controller-side `vulcan-find` injection) — Session C, AID-002.
- CP2 / CP3 verifier dispatch enforcement — Session B, AID-003 / AID-004.
- Self-audit FSM checklist feature — Krok 3, AID-012.
- DoD per task / executable acceptance criteria — downstream, AID-010 / AID-015.
- Deprecation / decommission existujícího `shared-telegram` MCP serveru (localhost:8817) — paralelní existence, follow-up plán po ověření `svc-mcp-tg-bot` v praxi.
- Auto-cleanup task branches po `done-advance` release sub-phase — separátní concern, P033 candidate.
- Plugin update v cizích projektech (vulcan, sousto, krok, wan) — manuální PM krok per CLAUDE.md "Plugin Update — MANDATORY after every push".
- Modifikace plan-writing / brainstorming skillů — separate concern.
- E2E smoke test celého EPIC flow — Session B vstupní podmínka, ne Session A scope.

## Approach

### Option A: Full Foundation + MCP Inline (Chosen)

Jeden worktree pro celou Session A, 18 commits každý CI-green, 9 logických implementation Steps. Foundation fixes (3 P0) + telemetry layer (compliance.json + backfill + diagnostic + aggregator) + Telegram MCP server + bats test suite + release dokumentace v jednom PR.

**Pros:**
- Logická koherence — všechny změny souvisí s "Session A enforcement+telemetry"; jeden review vidí celkový dopad.
- Telegram alert end-to-end funguje při deploy (žádný stub).
- compliance.json schéma definovaný jednou (Sessions B/C jen rozšiřují null fields na true/false).
- Worktree izolace eliminuje chicken-and-egg problém (běžící AID v jiných projektech používá stable verzi z `~/.claude/plugins/marketplaces/`, dev pracuje v worktree s `AID_PLUGIN_PATH=$(pwd)`).

**Cons:**
- ~12h efektivní práce ve worktree.
- 18 commits v jednom PR vyžaduje thorough end-to-end review.
- Závisí na dostupnosti `~/.claude/.mcp.json` edit + `services/.env` write access (out-of-band PM kroky dokumentované v PR description).

### Option B: Lite (skip backfill)

Stejný scope minus `aid-compliance-backfill.sh` a `aid-compliance-report.sh`.

**Pros:**
- ~7h místo 12h.

**Cons:**
- Žádný baseline data set — aggregátor nemůže ukázat "before vs after" trend bez ručního lookup do `AID-v3-diagnostic-findings.md` markdown.
- Improvement claim post-deploy je textový, ne datový — slabší ground truth pro PM rozhodování.

### Option C: Use curl instead of MCP

Stejný scope minus svc-mcp-tg-bot, Telegram alert přes přímý `curl` na Telegram Bot API z FSM bashe.

**Pros:**
- ~4h ušetřeno (žádný Python service build).
- Nulové dependencies pro alert (jen `curl`).

**Cons:**
- Bot token musí být v env vars na úrovni FSM bash skriptu (riziko leak do timeline / logs).
- Žádný shared Telegram service pro CC (main + sub-agenti) — ti by museli mít vlastní integration každý zvlášť.
- Dlouhodobě anti-pattern: roztříštěné Telegram integrace per use-case.

### Decision

**Chosen:** Option A
**Rationale:** PM rozhodnutí 2026-05-04 — Telegram MCP musí být centralizovaný v infra dockeru, klíče v `services/.env`, dostupný pro CC main + sub-agenti i FSM bash skripty přes různé transport (stdio + HTTP). Centralizace eliminuje budoucí roztříštěnost a poskytuje single point of management pro bot token, default chat, message formatting. Backfill skript zachován protože compliance.json aggregátor potřebuje datovou baseline pro měření Session A impactu — bez ní je "improvement" jen tvrzení v dokumentu.

## Architecture

### High-Level Component Map

```
┌──────────────────────────────────────────────────────────────────────┐
│  AID Plugin (modified)                                                │
│                                                                       │
│  plugins/aid-orchestrator/scripts/                                   │
│    aid-fsm.sh                — branch enforcement, FSM preconditions │
│      └─ cmd_init()            : auto-checkout, grandfather stamp     │
│      └─ cmd_transition()      : EXECUTE→GATES check, repeated-fail   │
│      └─ cmd_done_advance()    : compliance.json hook                 │
│      └─ try_telegram_alert()  : HTTP POST to localhost:8818          │
│                                                                       │
│    aid-run-gates.sh           — timeline markers + provenance fields │
│    aid-compliance-backfill.sh — NEW: one-shot pre-deploy backfill    │
│    aid-compliance-report.sh   — NEW: pre vs post aggregator          │
│    aid-diagnostic.sh          — NEW: parametrized Krok 0 logic       │
│                                                                       │
│    lib/aid-init-execution-yaml.sh — NEW: stack detect + compose      │
│                                                                       │
│  plugins/aid-orchestrator/defaults/execution-stacks/                 │
│    python.yaml typescript.yaml go.yaml rust.yaml bash.yaml           │
│                                                                       │
│  plugins/aid-orchestrator/scripts/tests/bats/                                     │
│    test-aid-fsm.bats test-aid-run-gates.bats test-aid-init.bats     │
│    test-helpers.bash                                                  │
│                                                                       │
│  plugins/aid-orchestrator/skills/pipeline.md (modified subsections) │
│  plugins/aid-orchestrator/commands/aid-init.md (modified)            │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ HTTP POST (when repeated_fail ≥ 3)
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│  /opt/eco/services/mcp-tg-bot/  (NEW Docker service)                 │
│                                                                       │
│  server.py        — FastMCP, stdio + HTTP transport, port 8818       │
│  Dockerfile       — Python 3.12 slim                                 │
│  pyproject.toml   — fastmcp, python-telegram-bot or httpx            │
│  .env.example     — TELEGRAM_ALERT_BOT_TOKEN, _DEFAULT_CHAT_ID       │
│                                                                       │
│  Tools:                                                              │
│    send_message(text, parse_mode="HTML", chat_id=None)              │
│      └─ default chat from env if chat_id is None                     │
│                                                                       │
│  Transports:                                                         │
│    stdio  — used by CC main + sub-agents via ~/.claude/.mcp.json    │
│    HTTP   — used by FSM bash skripty (curl localhost:8818)          │
└──────────────────────────────────────────────────────────────────────┘
```

### Data Flow — Branch Enforcement (Step 2)

```
PM runs: aid-fsm.sh init E-046-1_3
                 │
                 ▼
        is_worktree() ?
        ├─ yes → skip enforcement, accept current HEAD
        └─ no  → check current_branch:
                  ├─ matches expected → resume case (log_info, accept)
                  ├─ main/master/develop → auto-create + checkout task/E-046-1_3/main
                  ├─ task/E-OTHER/* → emit fsm_branch_mismatch_detected event,
                  │                    die with copy-paste fix
                  └─ other (feat/*, refactor/*, detached HEAD, any non-task pattern)
                       → emit fsm_branch_unusual_detected event,
                                              warn but accept
                 │
                 ▼
        check uncommitted changes
        ├─ clean → proceed
        └─ dirty → die "commit or stash"
                 │
                 ▼
        write state.yaml with created_at: <now ISO 8601 UTC>
```

### Data Flow — Gates Execution (Steps 4 + 5)

```
EXECUTE phase complete (last step incremented)
                 │
                 ▼
        Agent runs: aid-run-gates.sh run-all --state-file ... --report-file ...
                 │
                 ├─► emit timeline event "gate_runner_start"
                 │     {report_path, gate_count, command_list}
                 │
                 │   FOR each gate in execution.yaml:
                 │     execute command, capture stdout/stderr/exit_code
                 │     append to command_log array
                 │
                 ├─► write gates_report.json with extended schema:
                 │     {gates: [...], overall: "pass"|"fail",
                 │      _generated_by: "aid-run-gates.sh@v2.16.0",
                 │      _generated_at: <ISO timestamp>,
                 │      _command_log: [{name, command, exit_code, duration_ms}]}
                 │
                 └─► emit timeline event "gate_runner_complete"
                     {report_path, overall, duration_sec}
                 │
                 ▼
PM runs: aid-fsm.sh transition GATES DONE
                 │
                 ▼
        check_grandfather() ?
        ├─ yes (created_at < deploy_date) → skip new precondition
        └─ no →
              ├─ jq '._generated_by' gates_report.json present? → accept
              └─ missing → count_recent_fails(EXECUTE, GATES, "gates_no_generated_by")
                            ├─ < 3 → die with copy-paste fix
                            └─ ≥ 3 → emit fsm_precondition_repeated_fail event,
                                      try_telegram_alert,
                                      die with copy-paste fix
```

### Data Flow — Compliance Telemetry (Steps 6 + 7 + 9)

```
done-advance completes (DONE → release → archived)
                 │
                 ▼
        write_compliance_json():
          deploy_era = "post-session-a" (or "pre-session-a" if grandfather)
          checks = {
            branch_correct:           evaluate from state.yaml.branch
            execution_yaml_present:   evaluate from project root
            gates_generated_by:       evaluate from gates_report.json._generated_by
            memory_substantive:       null (Session B/C territory)
            verifier_outputs:         null (Session B territory)
            dod_present:              null (downstream)
          }
          overall = "pass" if all checks (true OR null), else "fail"
          write to evidence_dir/compliance.json
        emit timeline event "compliance_written"

ONE-SHOT (post-deploy, manual):
  aid-compliance-backfill.sh --deploy-date 2026-05-XX
    └─ scan all 203 evidence dirs, write pre-Session-A compliance.json
       (only branch_correct + execution_yaml_present retro-evaluable)

AGGREGATION (ad-hoc):
  aid-compliance-report.sh --since 2026-04-01
    └─ read all compliance.json, output table:
       Pre-Session-A baseline (45 EPICs):  branch=35%  execution=29%  gates=0%
       Post-Session-A (12 EPICs):          branch=100% execution=92% gates=95%
```

### Modified Files

| File | Lines (approx) | Change Type |
|------|----------------|-------------|
| `plugins/aid-orchestrator/scripts/aid-fsm.sh` | +180 | Modify (5 functions) |
| `plugins/aid-orchestrator/scripts/aid-run-gates.sh` | +100 | Rewrite (yq-driven loop, markers + provenance — current ~150 → target ~250 lines) |
| `plugins/aid-orchestrator/commands/aid-init.md` | +25 | Modify (add execution.yaml section) |
| `plugins/aid-orchestrator/skills/pipeline.md` | +120 | Modify (3 subsections rewrite) |
| `plugins/aid-orchestrator/CHANGELOG.md` | +35 | Modify (v2.16.0 entry) |
| Root `CHANGELOG.md` | +35 | Modify (v2.16.0 entry, identical to plugin) |
| `plugins/aid-orchestrator/.claude-plugin/plugin.json` | 1 line | Modify (version field) |
| `.claude-plugin/marketplace.json` | 2 lines | Modify (metadata.version + plugins[0].version) |
| `plugins/aid-orchestrator/README.md` | 1 line | Modify (Plugin: vX.Y.Z) |
| Root `README.md` | ~10 lines | Modify (version + roadmap) |

### New Files (Plugin)

| File | Lines (approx) | Purpose |
|------|----------------|---------|
| `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` | 140 | Stack detect + template merge helper |
| `plugins/aid-orchestrator/scripts/aid-compliance-backfill.sh` | 90 | One-shot backfill of pre-deploy EPICs |
| `plugins/aid-orchestrator/scripts/aid-compliance-report.sh` | 130 | Aggregator pre vs. post |
| `plugins/aid-orchestrator/scripts/aid-diagnostic.sh` | 220 | Parametrized Krok 0 forensic logic |
| `plugins/aid-orchestrator/defaults/execution-stacks/python.yaml` | 25 | py_test, py_lint, py_type_check templates |
| `plugins/aid-orchestrator/defaults/execution-stacks/typescript.yaml` | 25 | ts_test, ts_lint, ts_type_check templates |
| `plugins/aid-orchestrator/defaults/execution-stacks/go.yaml` | 20 | go_test, go_lint, go_build templates |
| `plugins/aid-orchestrator/defaults/execution-stacks/rust.yaml` | 20 | rust_test, rust_clippy, rust_build templates |
| `plugins/aid-orchestrator/defaults/execution-stacks/bash.yaml` | 18 | bash_syntax (bash -n), shellcheck templates |
| `plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash` | 80 | Shared bats helpers: `setup_test_evidence_dir`, `teardown_test_evidence_dir`, `mock_git_worktree`, `assert_timeline_event` |
| `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` | 200 | 9 assertions on FSM preconditions |
| `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` | 80 | 3 assertions on gate runner markers |
| `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` | 100 | 4 assertions on stack detection |

### New Files (Services — MCP)

| File | Lines (approx) | Purpose |
|------|----------------|---------|
| `services/mcp-tg-bot/server.py` | 130 | FastMCP server, stdio + HTTP transport, port 8818 |
| `services/mcp-tg-bot/Dockerfile` | 25 | Python 3.12 slim base, pip install fastmcp |
| `services/mcp-tg-bot/pyproject.toml` | 30 | Dependencies: fastmcp, httpx, python-dotenv |
| `services/mcp-tg-bot/.env.example` | 8 | Token + default chat ID placeholders |
| `services/mcp-tg-bot/README.md` | 50 | Deploy guide, MCP integration snippet |
| `docker-compose.yml` (root, eco-dev + eco-prod) | +12 | svc-mcp-tg-bot service block |

## Data Schemas

### `execution.yaml` (per-project, lazy-created by aid-init)

```yaml
# AUTO-GENERATED by aid-init at <ISO timestamp>
# Detected stacks: <list>
# Review and customize commands; remove sections for stacks you don't use.

version: "1.0"
generated_by: "aid-init v2.16.0"

gates:
  # === Python (pyproject.toml or requirements.txt detected) ===
  py_test:
    # DEPENDENCY: pytest must be installed (pip install pytest)
    command: "pytest -q"
    required_when: "*.py exists"
  py_lint:
    # DEPENDENCY: ruff must be installed (pip install ruff)
    command: "ruff check ."
    required_when: "*.py exists"
  py_type_check:
    # DEPENDENCY: mypy must be installed (pip install mypy)
    command: "mypy --strict src/"
    required_when: "*.py exists"

  # === TypeScript (package.json detected) ===
  ts_test:
    # DEPENDENCY: package.json scripts.test must exist
    command: "npm test"
    required_when: "*.ts OR *.tsx exists"
  ts_lint:
    # DEPENDENCY: eslint must be installed (npm install --save-dev eslint)
    command: "npx eslint . --ext .ts,.tsx"
    required_when: "*.ts OR *.tsx exists"
  ts_type_check:
    # DEPENDENCY: typescript must be installed (npm install --save-dev typescript)
    command: "npx tsc --noEmit"
    required_when: "tsconfig.json exists"

  # === bash (>= 6 shell scripts found) ===
  bash_syntax:
    # DEPENDENCY: bash (always present)
    command: "find . -name '*.sh' -exec bash -n {} +"
    required_when: "*.sh exists"
  bash_lint:
    # DEPENDENCY: shellcheck must be installed (apt install shellcheck)
    command: "shellcheck $(find . -name '*.sh' -not -path './node_modules/*')"
    required_when: "*.sh exists"

notifications:
  telegram:
    enabled: false               # default off; set true after svc-mcp-tg-bot deployed
    chat_id: null                # null → use TELEGRAM_ALERT_DEFAULT_CHAT_ID from server env
    alert_on_repeated_precondition_fail: true
    alert_threshold: 3
```

### `compliance.json` (per-EPIC, written by done-advance hook)

```json
{
  "epic_id": "E-045-1_8",
  "run_id": "R-E045-1",
  "aid_version": "v3",
  "deploy_era": "post-session-a",
  "evaluated_at": "2026-05-15T08:32:11Z",
  "checks": {
    "branch_correct":         true,
    "execution_yaml_present": true,
    "gates_generated_by":     true,
    "memory_substantive":     null,
    "verifier_outputs":       null,
    "dod_present":            null
  },
  "overall": "pass",
  "notes": []
}
```

**Field semantics:**
- `deploy_era`: `pre-session-a` (grandfathered run, `state.yaml.created_at < deploy_date`) | `post-session-a` (new run after deploy)
- `checks.<dim>: true` — measured and passed
- `checks.<dim>: false` — measured and failed
- `checks.<dim>: null` — not yet measured by deployed Session (Session A measures 3 of 6; B/C will fill remaining; null **never** means "not applicable")
- `overall: "pass"` if all checks ∈ {true, null}; else `"fail"`. **IMPORTANT comment in code:** When Sessions B/C deploy, currently-null fields become true|false — overall logic must remain consistent (null still allowed when feature genuinely not deployed in measured era).

### Timeline Events (added)

| Event | Payload Fields | Emitted By |
|-------|---------------|------------|
| `fsm_branch_mismatch_detected` | `current_branch`, `expected_branch`, `epic_id` | aid-fsm.sh PRE-FLIGHT |
| `fsm_branch_unusual_detected` | `current_branch`, `expected_branch`, `epic_id` | aid-fsm.sh PRE-FLIGHT (warning case) |
| `fsm_precondition_repeated_fail` | `from`, `to`, `reason`, `attempt_count` | aid-fsm.sh transition (≥ 3rd same-reason fail) |
| `gate_runner_start` | `report_path`, `gate_count`, `command_list` (array of names) | aid-run-gates.sh entry |
| `gate_runner_complete` | `report_path`, `overall`, `duration_sec` | aid-run-gates.sh exit |
| `compliance_written` | `deploy_era`, `overall`, `checks_passed` (count), `checks_failed` (count) | done-advance hook |

### Branch Naming Convention

```
^task/E-[A-Z0-9_-]+/main$
```

Format: `task/E-{epic_id}/main`. No step-level subbranches (anti-pattern per Krok 0 — wan project's `step_2_backend` style caused release issues, not adopted).

## Infrastructure

### svc-mcp-tg-bot Docker Service

**Location:** `/opt/eco/services/mcp-tg-bot/`
**Container name:** `svc-mcp-tg-bot`
**Image:** Built from local Dockerfile (Python 3.12 slim base)
**Port:** 8818 (HTTP transport for FSM bash callers)
**Network:** `host` mode (or bridge with `ports: ["8818:8818"]`) — host mode preferred per CLAUDE.md infra pattern
**Restart policy:** `unless-stopped`
**Env source:** `/opt/eco/services/.env` (shared across all infra services per ekosystém pattern)

**Required env vars:**
- `TELEGRAM_ALERT_BOT_TOKEN` — bot token from BotFather (sdílený s ostatními telegram-related services pokud nějaké budou)
- `TELEGRAM_ALERT_DEFAULT_CHAT_ID` — default chat ID (např. "CC Updates" group ID)
- `MCP_HTTP_PORT=8818` (default, override-able)

**docker-compose.yml entry:**
```yaml
  svc-mcp-tg-bot:
    build: ./services/mcp-tg-bot
    container_name: svc-mcp-tg-bot
    env_file: /opt/eco/services/.env
    network_mode: host
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8818/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

**MCP transport setup:**
- **stdio:** for Claude Code main + sub-agents via `~/.claude/.mcp.json`. PM adds entry post-deploy out-of-band:
  ```json
  "svc-mcp-tg-bot": {
    "command": "docker",
    "args": ["exec", "-i", "svc-mcp-tg-bot", "python", "-m", "server", "--transport", "stdio"],
    "env": {}
  }
  ```
- **HTTP:** for FSM bash callers via `curl localhost:8818/send_message`. POST body: `{"text": "...", "parse_mode": "HTML", "chat_id": null}`. Response: `{"ok": true, "message_id": 123}`.

**Dependency on existing infra:**
- Docker daemon available on eco-dev (10.20.20.22) — confirmed per CLAUDE.md infra context.
- `/opt/eco/services/.env` writable by user `marekstancl` — confirmed (PM has direct edit access).
- Bot token already exists (PM has Telegram bot from prior `shared-telegram` MCP setup) — reused.

**Existing service preserved:**
- `shared-telegram` MCP at localhost:8817 keeps running paralelně. Decommission tracked separátně po ověření nového MCP v praxi (P033 candidate).

## Security

Tato sekce konsoliduje security-relevant aspekty rozprostřené napříč Architecture / Infrastructure / Risks. Tři kategorie:

### S.1 — Bot token storage

- **Source of truth:** `/opt/eco/services/.env` (per-host file, **NOT** committed to git, per CLAUDE.md ekosystem konvence pro shared secrets).
- **Distribution:** PM manuálně edituje per-host (eco-dev a eco-prod oddělené tokens akceptovatelné — prod alerty mohou jít do jiného chatu než dev).
- **Container access:** `env_file: /opt/eco/services/.env` v docker-compose.yml — token loaded jen jako env var, nikdy zapsán do logů (FastMCP/python-dotenv standard practice).
- **Repo hygiene:** `services/mcp-tg-bot/.env.example` v repu obsahuje jen placeholder values (`TELEGRAM_ALERT_BOT_TOKEN=` prázdné). `.env` MUSÍ být v `.gitignore` (verify pre-commit).
- **Token rotation:** revocation přes BotFather (`/revoke` command). Po rotation: edit `.env` na obou hostech, `docker compose restart svc-mcp-tg-bot`. Žádný code change.
- **Risk acceptance:** dva hosts × jeden token = 2 file copies. Kompromise mezi hostem a operability — alternativa (centralized secrets manager) je out-of-scope Session A.

### S.2 — MCP HTTP attack surface

- **Bind localhost only:** `MCP_HTTP_HOST=127.0.0.1` env var v compose, server.py default 127.0.0.1 (NOT 0.0.0.0 — viz Risks table). Even s `network_mode: host` HTTP listener přijímá jen localhost connections.
- **No authentication on HTTP transport:** přijatelné protože bind je localhost — only processes on the same host can call. FSM bash skripty (running on host) jsou trusted callers.
- **Stdio transport:** process-local IPC, žádný network exposure. CC main + sub-agents používají přes `docker exec -i`.
- **Audit step:** post-deploy `iptables -L INPUT | grep 8818` musí vrátit jen `ACCEPT 127.0.0.1` (nebo žádné explicit rule pokud default policy je restrictive).
- **Rate limiting:** žádný app-level rate limit v MCP serveru (best-effort bestrov), ale Telegram Bot API enforces 1 msg/sec per chat (viz Risks).

### S.3 — Git-tracked vs. out-of-band secrets

- **Git-tracked v repu:** `.env.example` (placeholders), `Dockerfile`, `docker-compose.yml` entry, `server.py`, README.md. **NIKOLI** real `.env`.
- **Out-of-band PM kroky (v PR description deploy guide):**
  - `cp services/mcp-tg-bot/.env.example /opt/eco/services/.env` (or merge if exists), fill `TELEGRAM_ALERT_BOT_TOKEN` + `TELEGRAM_ALERT_DEFAULT_CHAT_ID`.
  - Edit `~/.claude/.mcp.json` (per-machine, per-user — nikoli per-repo).
  - Verify `.env` permissions: `chmod 600 /opt/eco/services/.env` (read jen ownerem).
- **Token reuse:** Pokud PM má existing Telegram bot token z `shared-telegram` MCP (8817), může se reuse. Jen otázka separation policy — různé tokens = lepší blast radius.

## Implementation Steps

**EPIC 1: Steps 1-9 — Foundation Hardening + Telemetry + MCP**

### Step 1: Stack Templates + execution.yaml Lazy-Create

**Objective:** Implementovat per-stack template fragmenty pro `execution.yaml` a integrovat lazy-create do `aid-init` plus auto-recovery v `aid-fsm.sh cmd_init`.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/execution-stacks/python.yaml` — Python gate templates (py_test pytest, py_lint ruff, py_type_check mypy --strict).
- Create: `plugins/aid-orchestrator/defaults/execution-stacks/typescript.yaml` — TypeScript gate templates (ts_test npm test, ts_lint eslint, ts_type_check tsc --noEmit).
- Create: `plugins/aid-orchestrator/defaults/execution-stacks/go.yaml` — Go gate templates (go_test go test ./..., go_lint golangci-lint run, go_build go build ./...).
- Create: `plugins/aid-orchestrator/defaults/execution-stacks/rust.yaml` — Rust gate templates (rust_test cargo test, rust_clippy cargo clippy, rust_build cargo build --release).
- Create: `plugins/aid-orchestrator/defaults/execution-stacks/bash.yaml` — bash gate templates (bash_syntax `bash -n` recursive, bash_lint shellcheck).
- Create: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` — bash helper with `detect_stacks()` + `compose_execution_yaml()` functions.
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` (lines ~80-110, after permissions setup section) — add invocation of `aid-init-execution-yaml.sh` step with `# AUTO-GENERATED — review and customize` comment in output.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_init` (after argument validation, before state.yaml creation) — auto-recovery: if `execution.yaml` missing AND post-deploy era, call helper inline.

**Architecture Context:**
Současná architektura `aid-init` (per `commands/aid-init.md`) provádí permissions setup + project.yaml seed + standards profile selection, ale ne `execution.yaml` provisioning. Tento Step zaplňuje gap. `aid-fsm.sh::cmd_init` aktuálně neví o `execution.yaml` existenci — Step přidá auto-recovery cestu pro projekty inicializované před Session A deploy ale nově spouštějící post-deploy EPIC. Stack detection logika respektuje multi-stack realitu (vulcan = Python+TS, sousto = TS+Python, aid-orchestrator sám = bash+TS+md) — místo single primary stack composer merge-uje per-stack template fragments do single `execution.yaml`.

**Implementation Detail:**

`detect_stacks()` v `aid-init-execution-yaml.sh`:
```bash
detect_stacks() {
  local project_root=$1
  local stacks=()
  [[ -f "$project_root/pyproject.toml" || -f "$project_root/requirements.txt" || -f "$project_root/setup.py" ]] && stacks+=("python")
  [[ -f "$project_root/package.json" ]] && stacks+=("typescript")
  [[ -f "$project_root/go.mod" ]] && stacks+=("go")
  [[ -f "$project_root/Cargo.toml" ]] && stacks+=("rust")
  local sh_count
  sh_count=$(find "$project_root" -maxdepth 3 -name "*.sh" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l)
  (( sh_count > 5 )) && stacks+=("bash")
  printf '%s\n' "${stacks[@]}"
}

compose_execution_yaml() {
  local project_root=$1 output_file=$2 detected_stacks=("${@:3}")
  local plugin_dir="${AID_PLUGIN_PATH:-$HOME/.claude/plugins/marketplaces/claude-aid-o/plugins/aid-orchestrator}"

  {
    cat <<EOF
# AUTO-GENERATED by aid-init at $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Detected stacks: ${detected_stacks[*]:-none}
# Review and customize commands; remove sections for stacks you don't use.

version: "1.0"
generated_by: "aid-init v2.16.0"

gates:
EOF
    for stack in "${detected_stacks[@]}"; do
      local frag="$plugin_dir/defaults/execution-stacks/${stack}.yaml"
      [[ -f "$frag" ]] && {
        echo "  # === ${stack^} (auto-detected) ==="
        # strip top-level "gates:" line from fragment, indent rest
        tail -n +2 "$frag" | sed 's/^/  /'
        echo
      }
    done
    cat <<EOF

notifications:
  telegram:
    enabled: false               # default off; set true after svc-mcp-tg-bot deployed
    chat_id: null                # null → use server default
    alert_on_repeated_precondition_fail: true
    alert_threshold: 3
EOF
  } > "$output_file"
}
```

`aid-init` integrace (per `commands/aid-init.md` aktualizace):
```bash
# After permissions + project.yaml + standards setup:
if [[ ! -f .aid-o/config/execution.yaml ]]; then
  source "$AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh"
  mapfile -t stacks < <(detect_stacks "$PWD")
  compose_execution_yaml "$PWD" ".aid-o/config/execution.yaml" "${stacks[@]}"
  log_info "Created .aid-o/config/execution.yaml with stacks: ${stacks[*]:-none}"
fi
```

`aid-fsm.sh::cmd_init` auto-recovery:
```bash
# After argument validation, before state.yaml creation:
if [[ ! -f .aid-o/config/execution.yaml ]] && fsm_is_post_deploy; then
  log_warn ".aid-o/config/execution.yaml missing — running lazy-create"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh"
  mapfile -t stacks < <(detect_stacks "$PWD")
  compose_execution_yaml "$PWD" ".aid-o/config/execution.yaml" "${stacks[@]}"
fi
```

Bash threshold `> 5` brání false positive na utility scripty (≤ 5 = utility, ≥ 6 = stack). AID-orchestrator project má desítky shell skriptů, projde správně.

**Error Handling:**
- Pokud `$plugin_dir` neexistuje (neresolvuje `AID_PLUGIN_PATH` ani fallback): die with message `"Plugin path not resolvable. Set AID_PLUGIN_PATH or install plugin via /plugin install."`.
- Pokud žádné stacky detekované: composer napíše `execution.yaml` s prázdnou `gates:` sekcí + komentář `# No stacks detected — add gate definitions manually.` Žádný die — uživatel může mít custom workflow.
- Pokud `execution.yaml` už existuje: lazy-create kód skip-uje (idempotent). `aid-init` může být bezpečně re-run.
- Permission denied při Write to `.aid-o/config/`: die with `"Cannot write to .aid-o/config/execution.yaml — check permissions or run /aid-init first."`.

**Edge Cases:**
- **Multi-stack projekt s edge case kombinacemi:** vulcan má pyproject.toml + package.json + 50+ shell skriptů → composer vyrobí execution.yaml se 3 sekcemi (Python, TypeScript, bash), všechny s `# DEPENDENCY` komentáři. PM si první post-deploy EPIC ověří, pravděpodobně musí ručně doinstalovat něco (mypy, eslint).
- **Projekt s `.python-version` ale bez pyproject.toml:** detect_stacks() zatím to nedetekuje (jen pyproject.toml / requirements.txt / setup.py). Akceptovaná false negative — PM doplní ručně.
- **`*.sh` count přesně 5:** threshold je `> 5`, takže 5 skriptů → bash NENÍ stack. To je úmyslné (utility scripty neaktivují bash gates).
- **AID-orchestrator project sám:** má `package.json` (TypeScript) a 30+ shell skriptů → composer vytvoří TS + bash sekce. Bez `pyproject.toml` → Python sekce chybí. Správné chování.

**Dependencies:**
- Depends on: nothing (foundational).
- Blocks: Step 3 (gates execution potřebuje execution.yaml), Step 7 (aid-init bats test potřebuje helper), Step 4 (compliance check `execution_yaml_present` reads file).

**Acceptance Criteria:**
- [ ] Helper skript `lib/aid-init-execution-yaml.sh` exportuje funkce `detect_stacks` a `compose_execution_yaml`, callable jak ze `aid-init` tak z `aid-fsm.sh`.
- [ ] Pět template souborů `execution-stacks/{python,typescript,go,rust,bash}.yaml` existuje s 2-4 gate definicemi each + `# DEPENDENCY` komentářem u každé command.
- [ ] V testovacím projektu s pyproject.toml + package.json + 6+ shell skriptů composer vytvoří `execution.yaml` se třemi gate sekcemi (Python, TypeScript, bash) označenými `# === <Stack> (auto-detected) ===`.
- [ ] V testovacím projektu bez markerů composer vytvoří execution.yaml s prázdnou `gates:` sekcí + warning komentář.
- [ ] aid-init re-run na projektu s existujícím execution.yaml ho NEPŘEPÍŠE (idempotent).
- [ ] `aid-fsm.sh init` na post-deploy projektu bez execution.yaml ho lazy-vytvoří jako side effect.

**Effort:** M
**AID Role:** backend

---

### Step 2: PRE-FLIGHT Branch Enforcement

**Objective:** Vynutit per-EPIC task branch v `aid-fsm.sh::cmd_init`, detekovat mismatch s copy-paste fix message, zachytit unusual branche pro diagnostic visibility, respektovat worktree mode.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_init` (lines ~120-180 — after argument validation, before state.yaml write) — add `is_worktree()` helper, `current_branch` detection, case dispatch (resume / fresh / mismatch / unusual / dirty), `state.yaml.created_at` timestamp.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (find existing PRE-FLIGHT subsection or add at line ~85) — rewrite "Branch enforcement" subsection citing new behavior + timeline events.

**Architecture Context:**
Krok 0 diagnostic findings (Sekce A, řádek F1) prokázalo že 17/26 (65 %) `state.yaml` deklaruje `branch: main` — agent pracuje na main bez task branche, čímž `done-advance` release sub-phase (krok 15 v pipeline.md, `git merge epic/...`) ztrácí smysl (no-op merge bez audit trailu). Sousto-na-miru obsahuje verbatim přiznání FSM bypass ve 4 souborech. Tento Step přesouvá branch hygiene z policy ask (pipeline.md textová instrukce) na deterministic enforcement (bash skript skutečně vytvoří branch nebo selže s clear remediation). Worktree exception nutná protože `superpowers:using-git-worktrees` workflow vytváří dedikovaný branch před AID init — opětovný checkout by zničil worktree disciplínu.

**Implementation Detail:**

```bash
# Helper: detect worktree mode
is_worktree() {
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
  [[ "$git_dir" == *.git/worktrees/* ]]
}

# In cmd_init, after argument parsing:
if is_worktree; then
  log_info "Worktree mode detected (git_dir under .git/worktrees/) — skipping branch enforcement"
else
  local current_branch expected_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || die "Not in a git repository"
  expected_branch="task/E-${epic_id}/main"

  case "$current_branch" in
    "$expected_branch")
      log_info "Resume case: HEAD already on $expected_branch"
      ;;
    main|master|develop)
      log_info "Auto-creating branch: $expected_branch"
      git checkout -b "$expected_branch" || die "Failed to create branch $expected_branch"
      ;;
    task/E-*)
      # Different EPIC's task branch — hard fail with copy-paste fix
      log_event "$timeline" "fsm_branch_mismatch_detected" \
        current_branch="$current_branch" expected_branch="$expected_branch" epic_id="$epic_id"
      die "ERROR: Currently on $current_branch, expected $expected_branch.

Reason: AID v3 requires one task branch per EPIC for clean audit trail.
        Different-EPIC branches indicate stale workspace from prior session.

Fix: git checkout main && git branch -d $current_branch
Then retry: aid-fsm.sh init $epic_id"
      ;;
    *)
      # feat/* or other unusual — emit event, warn, but accept
      log_event "$timeline" "fsm_branch_unusual_detected" \
        current_branch="$current_branch" expected_branch="$expected_branch" epic_id="$epic_id"
      log_warn "Unusual branch: $current_branch (expected $expected_branch). Continuing — PM-controlled context assumed."
      ;;
  esac
fi

# Uncommitted changes guard (always runs, regardless of worktree mode)
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "Uncommitted changes present. Commit or stash before init:
       git status   # review
       git stash    # or commit"
fi

# Stamp grandfather marker into state.yaml (always)
echo "created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$state_file"
```

**Logger:** Use existing `log_event` from `plugins/aid-orchestrator/scripts/lib/aid-stage-log.sh` (sourced by `aid-fsm.sh`). Signature: `log_event "$timeline_file" "event_name" key=value key2=value2`. Auto-detects numeric/boolean/null values (no quoting), auto-escapes strings. Existing `aid-fsm.sh` uses this helper 14 times across these event types: `fsm_init`, `fsm_init_blocked`, `fsm_force_override`, `fsm_precondition_fail`, `fsm_transition`, `fsm_increment_fail`. Preserve consistency — do NOT introduce a parallel logging primitive. The `$timeline` variable is set in `cmd_init` and other commands as `${evidence_dir}/timeline.jsonl`.

**Error Handling:**
- Not in git repository: `git rev-parse` fails → die with `"Not in a git repository"` (cmd_init musí být voláno v git working tree).
- Branch creation fails (e.g., remote conflict): `git checkout -b` exit non-zero → die with `"Failed to create branch $expected_branch"` + suggestion to check `git status`.
- Mismatch case: emit event, die with full copy-paste remediation.
- Uncommitted changes: die with stash/commit suggestion.
- Worktree detection edge: pokud git dir is `.git/worktrees/foo` ale skript běží v main repo workdir: `is_worktree` je true → enforcement skipped. To je správně (worktree workflow respect).

**Edge Cases:**
- **Resume scenario** (PM přerušil v půli, pokračuje): HEAD = `task/E-XXX/main`, init s `XXX` → resume case, log_info, accept.
- **Mismatch from prior session** (vulcan typical): HEAD = `task/E-044-4_7/step_2_backend` (stará branch), init `E-046-1_3` → emit event, hard fail s konkrétním cleanup příkazem.
- **PM intentional non-task branch** (feat/refactor work-in-progress): HEAD = `feat/foo` → emit `fsm_branch_unusual_detected`, log_warn, ale accept (PM context-aware).
- **Detached HEAD** (PM forgot to checkout branch): `git rev-parse --abbrev-ref HEAD` returns `HEAD` → matches *) catch-all → emit unusual event, warn, accept. PM má visibility v logs.
- **Worktree mode v dedicated worktree** (Session A development workflow): `.envrc` sets AID_PLUGIN_PATH, current dir je `~/.claude-worktrees/aid-v3-session-a/` → is_worktree() returns true → enforcement skipped. Caller's branch (`feat/aid-v3-session-a`) accepted.

**Dependencies:**
- Depends on: Step 1 (logically — execution.yaml lazy-create musí být dostupná pro stejný cmd_init flow) — though Step 2 lze technically merge bez Step 1, sequence pro coherent CI green per commit.
- Blocks: Step 3 (gate runner uses same `log_event` helper pattern), Step 4 (compliance check `branch_correct` reads state.yaml.branch).

**Acceptance Criteria:**
- [ ] `aid-fsm.sh init E-test` na čistém main branchi auto-vytvoří `task/E-test/main` a checkout.
- [ ] `aid-fsm.sh init E-test` na existujícím `task/E-test/main` (resume) projde s log_info bez modifikace branche.
- [ ] `aid-fsm.sh init E-test` na `task/E-OTHER/main` selže s exit non-zero, stderr obsahuje string `git checkout main && git branch -d task/E-OTHER/main`, timeline.jsonl obsahuje `fsm_branch_mismatch_detected` event s payload `{current_branch, expected_branch, epic_id}`.
- [ ] `aid-fsm.sh init E-test` na `feat/foo` projde s log_warn, timeline.jsonl obsahuje `fsm_branch_unusual_detected` event.
- [ ] `aid-fsm.sh init E-test` v dedikovaném git worktree (verified `git rev-parse --git-dir` returns path containing `.git/worktrees/`) projde se zprávou `"Worktree mode detected"`, žádné branche nemodifikuje.
- [ ] `aid-fsm.sh init E-test` při `git diff --quiet` returns non-zero (uncommitted changes) selže s exit non-zero a stderr suggesting `git stash` nebo commit.
- [ ] `state.yaml` po úspěšném init obsahuje `created_at: <ISO 8601 UTC timestamp>` field.

**Effort:** M
**AID Role:** backend

---

### Step 3: Gate Runner Markers + Provenance Fields + EXECUTE→GATES Precondition

**Objective:** Modifikovat `aid-run-gates.sh` aby emit-oval timeline events při start/complete a zapisoval provenance fields (`_generated_by`, `_generated_at`, `_command_log`) do `gates_report.json`. Modifikovat `aid-fsm.sh::cmd_transition` aby precondition `EXECUTE→GATES` vyžadovala `_generated_by` (post-deploy only) a emit-ovala `fsm_precondition_repeated_fail` při ≥ 3 stejných failech.

**Files:**
- **Rewrite:** `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (current ~150 lines, target ~250 lines — `run_gate()` and `run_all_gates()` functions are largely replaced; control flow shifts from inline gate iteration to yq-driven loop with command_log accumulation). Add `gate_runner_start` / `gate_runner_complete` events via existing `log_event`, build `command_log` array per executed gate, `jq`-merge provenance fields into `gates_report.json` before write. **New system dependency:** `yq` (Go-based mikefarah variant, `apt install yq` or `brew install yq` — NOT the Python `yq` package).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_transition` (lines ~250-310 — EXECUTE→GATES branch) — add `fsm_check_grandfather()` short-circuit, `_generated_by` field check, `count_recent_fails()` helper for repeated-fail detection.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (sekce GATES, kolem řádku ~140) — rewrite "EXECUTE→GATES precondition" subsection s novou behaviorem + grandfather caveat.

**Architecture Context:**
Krok 0 diagnostic Sekce A řádek B (CP2 verifier) a Sekce A řádek D (fake gates) společně ukazují že agent obchází gate execution kompletně — 0/93 timelines obsahuje gate runner event, 99 % gates_report.json má `overall: pass` bez reálného běhu. Tento Step zavádí tři vrstvy enforcement: (1) timeline events poskytují forensic stopu (gate runner skutečně běžel), (2) provenance fields v reportu poskytují "anti-fabrikace" marker (agent nemůže snadno fake `_command_log` array s reálnými exit codes a duration_ms), (3) FSM precondition odmítá transition bez markeru. Grandfather logika přes `state.yaml.created_at` zachovává existing 203 EPIC běhy validní. Repeated-fail detection (≥ 3 stejné fails) odlišuje single mistake (PM zapomněl spustit `aid-run-gates.sh` → reads error, opraví, jede dál) od stuck pattern (něco systematicky nefunguje, PM potřebuje notification).

**Implementation Detail:**

`aid-run-gates.sh` modifikace:
```bash
# At entry, after argument parsing:
local command_list_json
command_list_json=$(jq -n --argjson gates "$(yq -o=json '.gates | keys' "$execution_yaml")" '$gates')

local gate_count
gate_count=$(yq '.gates | length' "$execution_yaml")
log_event "$timeline" "gate_runner_start" \
  report_path="$report_path" gate_count="$gate_count" \
  command_list="$(yq -o=json '.gates | keys' "$execution_yaml" | tr -d '\n ')"
# Note: command_list serialized as compact JSON string (log_event quotes it as string field —
# downstream consumers parse via `jq -r .command_list | jq .` if array access needed)

# Build command_log array as gates execute:
declare -a command_log
for gate_name in $gate_names; do
  local cmd=$(yq ".gates.${gate_name}.command" "$execution_yaml")
  local start_ms=$(date +%s%3N)
  local stdout_capture stderr_capture exit_code
  set +e
  stdout_capture=$(eval "$cmd" 2>/tmp/gate_stderr_$$)
  exit_code=$?
  set -e
  stderr_capture=$(cat /tmp/gate_stderr_$$); rm -f /tmp/gate_stderr_$$
  local duration_ms=$(( $(date +%s%3N) - start_ms ))
  command_log+=("$(jq -nc \
    --arg name "$gate_name" --arg command "$cmd" \
    --argjson exit "$exit_code" --argjson dur "$duration_ms" \
    '{name:$name, command:$command, exit_code:$exit, duration_ms:$dur}')")
  # ... existing per-gate result aggregation ...
done

# Before writing report, jq-merge provenance:
local command_log_array
command_log_array=$(printf '%s\n' "${command_log[@]}" | jq -s '.')

jq --arg gen "aid-run-gates.sh@${PLUGIN_VERSION:-v2.16.0}" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --argjson cl "$command_log_array" \
   '. + {_generated_by: $gen, _generated_at: $ts, _command_log: $cl}' \
   "$report_path" > "$report_path.tmp" && mv "$report_path.tmp" "$report_path"

log_event "$timeline" "gate_runner_complete" \
  report_path="$report_path" overall="$overall" duration_sec="$total_duration"
```

`aid-fsm.sh::cmd_transition` EXECUTE→GATES branch:
```bash
# Inside transition validation logic, when from=EXECUTE to=GATES:
if [[ "$from" == "EXECUTE" && "$to" == "GATES" ]]; then
  if fsm_check_grandfather; then
    log_info "Grandfathered EPIC (created_at < deploy_date) — skipping new EXECUTE→GATES precondition"
  else
    local gates_report="${evidence_dir}/gates/gates_report.json"
    if [[ ! -f "$gates_report" ]] || ! jq -e '._generated_by' "$gates_report" >/dev/null 2>&1; then
      local attempt_count
      attempt_count=$(fsm_count_recent_fails "$from" "$to" "gates_no_generated_by")
      if (( attempt_count >= 3 )); then
        log_event "$timeline" "fsm_precondition_repeated_fail" \
          from="$from" to="$to" reason="gates_no_generated_by" attempt_count="$attempt_count"
        try_telegram_alert "Repeated precondition fail (×${attempt_count}): EPIC=${epic_id}, transition=${from}→${to}"
      fi
      die "ERROR: gates_report.json missing _generated_by field.

Reason: AID v3 requires gates to be executed by aid-run-gates.sh,
        not hand-written. This ensures gates actually ran and produces
        forensic evidence (timeline events, command_log, exit codes).

Fix: rm $gates_report
     bash \$AID_PLUGIN_PATH/scripts/aid-run-gates.sh run-all \\
       --state-file $state_file \\
       --report-file $gates_report
Then retry: aid-fsm.sh transition GATES → DONE"
    fi
  fi
fi

# Helpers (added at top of aid-fsm.sh):
fsm_check_grandfather() {
  local created_at
  created_at=$(grep '^created_at:' "$state_file" 2>/dev/null | awk '{print $2}')
  [[ -z "$created_at" ]] && return 1   # no marker → not grandfathered (treat as post-deploy)
  local deploy_date="${AID_DEPLOY_DATE:-$(cat "$AID_PLUGIN_PATH/DEPLOY_DATE" 2>/dev/null)}"
  [[ -z "$deploy_date" ]] && return 1
  [[ "$created_at" < "$deploy_date" ]]   # bash lexicographic compare works for ISO 8601
}

fsm_count_recent_fails() {
  local from=$1 to=$2 reason=$3
  local timeline="${evidence_dir}/timeline.jsonl"
  [[ ! -f "$timeline" ]] && { echo 0; return; }
  jq --arg f "$from" --arg t "$to" --arg r "$reason" \
     'select(.event=="fsm_precondition_fail" and .from==$f and .to==$t and .reason==$r)' \
     "$timeline" | jq -s 'length'
}

try_telegram_alert() {
  local message=$1
  curl -s -X POST http://localhost:8818/send_message \
    -H "Content-Type: application/json" \
    --data "$(jq -nc --arg t "$message" '{text:$t, parse_mode:"HTML"}')" \
    --max-time 3 \
    > /dev/null 2>&1 \
    || log_info "Telegram alert skipped (svc-mcp-tg-bot not available — non-fatal)"
}
```

`AID_DEPLOY_DATE` env var nebo `DEPLOY_DATE` file v plugin root (set during deploy v Step 9 release process) — fallback grandfather to "treat as post-deploy" if neither defined (fail-safe: nový plugin without deploy date = enforce strict).

**Error Handling:**
- `yq` not installed: `aid-run-gates.sh` die with `"yq (mikefarah variant) required — install via: sudo apt install yq (Debian/Ubuntu) or brew install yq (macOS) or pacman -S go-yq (Arch). NOT the Python yq PyPI package which has incompatible CLI."`
- `execution.yaml` missing: caller is `aid-fsm.sh` which lazy-creates via Step 1 — if still missing at gate runner entry, die with `"execution.yaml missing — run aid-init or invoke aid-fsm.sh init"`.
- Gate command itself fails (exit non-zero): captured in `command_log[].exit_code`, marked as gate failure but execution continues for remaining gates (full report).
- Timeline write fails (disk full, permission): die with `"Cannot write to $timeline_file"`.
- `_generated_by` field check fails on grandfathered run: short-circuit returns before precondition check, no error.
- Repeated-fail count > threshold: emit event + best-effort Telegram alert. Alert failure is non-fatal (logged, transition still dies on the precondition).

**Edge Cases:**
- **First post-deploy EPIC, gates_report.json absent entirely:** `[[ ! -f $gates_report ]]` triggers, fail with copy-paste fix → PM runs `aid-run-gates.sh` → report created with provenance → retry succeeds.
- **PM hand-writes gates_report.json (legacy habit):** missing `_generated_by` → fail. Fix is `rm` + run gate script. After 3rd same fail (PM stuck) → Telegram alert.
- **Grandfathered run with hand-written report:** `fsm_check_grandfather` returns true → skip precondition entirely → accept legacy report.
- **`AID_DEPLOY_DATE` not set anywhere:** `fsm_check_grandfather` returns 1 (false) → treat as post-deploy → strict enforcement. This is fail-safe (better strict than permissive).
- **Multiple gates failing simultaneously (real failure, not hand-write):** `aid-run-gates.sh` produces report with `_generated_by: aid-run-gates.sh@v2.16.0` and `overall: "fail"`. FSM precondition checks `_generated_by` (present) → accepts transition. Then GATES→DONE precondition checks `overall: "pass"` separately (existing behavior preserved).
- **Concurrent PM running `aid-run-gates.sh` and parallel `aid-fsm.sh` transition:** race condition possible — `_generated_by` written but other field still being merged. Mitigate: `aid-run-gates.sh` writes via `report.tmp` + atomic `mv`. FSM read happens after.

**Dependencies:**
- Depends on: Step 2 (introduces use of existing `log_event` for new event types — `fsm_branch_*` events already emitted via `log_event` in Step 2).
- Blocks: Step 5 (compliance check `gates_generated_by` reads field), Step 6 (telegram alert hook called from this Step).

**Acceptance Criteria:**
- [ ] `aid-run-gates.sh` na testovacím EPICu zapisuje `gates_report.json` se všemi třemi provenance fields (`_generated_by`, `_generated_at`, `_command_log`).
- [ ] `_command_log` je array s entries per executed gate, každá obsahuje `name`, `command`, `exit_code`, `duration_ms`.
- [ ] `timeline.jsonl` po `aid-run-gates.sh` obsahuje `gate_runner_start` event s `report_path`, `gate_count`, `command_list` (array of names).
- [ ] `timeline.jsonl` obsahuje matching `gate_runner_complete` event s `report_path`, `overall`, `duration_sec`.
- [ ] `aid-fsm.sh transition EXECUTE GATES` na post-deploy EPICu s ručně psaným gates_report.json (bez `_generated_by`) selže s exit non-zero, stderr obsahuje `Reason:` sekci a copy-paste `aid-run-gates.sh run-all` příkaz.
- [ ] Stejný transition na grandfathered EPICu (state.yaml.created_at < deploy_date) projde bez kontroly `_generated_by`.
- [ ] Při ≥ 3 stejných precondition fails na stejném EPICu (`fsm_count_recent_fails` returns ≥ 3) emit `fsm_precondition_repeated_fail` event + best-effort `try_telegram_alert` call.
- [ ] `try_telegram_alert` při nedostupném MCP serveru nebo network error log-uje info zprávu, NE error, transition selhání zůstává atomic (alert je side-effect).

**Effort:** M
**AID Role:** backend

---

### Step 4: Compliance.json Schema + done-advance Hook

**Objective:** Definovat `compliance.json` schéma a integrovat per-EPIC writer do `aid-fsm.sh::cmd_done_advance`. Automatický zápis při dokončení EPICu, deploy_era detection, 6-dimension checks (3 measured pro Session A, 3 null).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_done_advance` (po release sub-phase, line ~420) — call `write_compliance_json()` jako post-hook, pak emit `compliance_written` event.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — add `write_compliance_json()` + `evaluate_compliance_checks()` helper functions.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (DONE phase section, řádek ~200) — add "Compliance Telemetry" subsection vysvětlující compliance.json schema + null/false/true semantika.

**Architecture Context:**
Krok 0 diagnostic findings (Sekce E.6) identifikoval že self-audit feature neexistuje (0/203 EPICs s self_audit.json) a Sekce E.4 acceptance criteria for Session A vyžaduje měřitelné dimensions — bez automatické telemetrie post-deploy improvement claim je textový. Tento Step zavádí continuous per-EPIC measurement which becomes data feed pro `aid-compliance-report.sh` aggregátor (Step 5). Schema je konzervativní: 3 měřené pole (branch_correct, execution_yaml_present, gates_generated_by) odpovídají Session A scope, 3 null pole (memory_substantive, verifier_outputs, dod_present) jsou placeholders pro Sessions B/C — když ty deploy, jejich done-advance hooks rozšíří `evaluate_compliance_checks()` aby doplnil ty fields. `null` semantika je striktní: znamená "feature ještě nedeplojená v této verzi", NIKOLI "neaplikuje se" — to umožňuje aggregátoru odlišit "0% pass protože nemeasurable" od "0% pass protože failed".

**Implementation Detail:**

```bash
# Helper: evaluate per-EPIC checks
evaluate_compliance_checks() {
  local epic_id=$1 state_file=$2 evidence_dir=$3 project_root=$4

  # branch_correct: state.yaml.branch matches ^task/E-
  local branch_value branch_correct
  branch_value=$(grep '^branch:' "$state_file" 2>/dev/null | awk '{print $2}')
  if [[ "$branch_value" =~ ^task/E- ]]; then
    branch_correct=true
  else
    branch_correct=false
  fi

  # execution_yaml_present: file exists in project's .aid-o/config/
  local exec_yaml_present
  if [[ -f "$project_root/.aid-o/config/execution.yaml" ]]; then
    exec_yaml_present=true
  else
    exec_yaml_present=false
  fi

  # gates_generated_by: gates_report.json has _generated_by field
  local gates_report="${evidence_dir}/gates/gates_report.json"
  local gates_genby
  if [[ -f "$gates_report" ]] && jq -e '._generated_by' "$gates_report" >/dev/null 2>&1; then
    gates_genby=true
  else
    gates_genby=false
  fi

  # Output JSON
  jq -nc \
    --argjson bc "$branch_correct" \
    --argjson eyp "$exec_yaml_present" \
    --argjson ggb "$gates_genby" \
    '{
      branch_correct:         $bc,
      execution_yaml_present: $eyp,
      gates_generated_by:     $ggb,
      memory_substantive:     null,
      verifier_outputs:       null,
      dod_present:            null
    }'
}

# Writer: per-EPIC compliance.json
write_compliance_json() {
  local epic_id=$1 run_id=$2 state_file=$3 evidence_dir=$4 project_root=$5
  local compliance_file="${evidence_dir}/compliance.json"

  local deploy_era="post-session-a"
  if fsm_check_grandfather; then
    deploy_era="pre-session-a"
  fi

  local checks
  checks=$(evaluate_compliance_checks "$epic_id" "$state_file" "$evidence_dir" "$project_root")

  # overall = "pass" if all checks ∈ {true, null}; else "fail"
  # IMPORTANT: when Sessions B/C deploy, currently-null fields become true|false —
  #            overall logic remains consistent (null ALWAYS means "not measured in this era",
  #            not "not applicable" — so it's permissively counted as pass for the era's overall verdict).
  local overall
  overall=$(echo "$checks" | jq -r '
    [.[] | (. == true or . == null)] | all | if . then "pass" else "fail" end
  ')

  jq -nc \
    --arg epic "$epic_id" \
    --arg run "$run_id" \
    --arg ver "v3" \
    --arg era "$deploy_era" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson chks "$checks" \
    --arg ov "$overall" \
    '{
      epic_id: $epic, run_id: $run, aid_version: $ver,
      deploy_era: $era, evaluated_at: $ts,
      checks: $chks, overall: $ov, notes: []
    }' > "$compliance_file"

  # Emit timeline event
  local checks_passed checks_failed
  checks_passed=$(echo "$checks" | jq '[.[] | select(. == true)] | length')
  checks_failed=$(echo "$checks" | jq '[.[] | select(. == false)] | length')

  log_event "$timeline" "compliance_written" \
    deploy_era="$deploy_era" overall="$overall" \
    checks_passed="$checks_passed" checks_failed="$checks_failed"
}

# Hook in cmd_done_advance, after release sub-phase:
# (existing release sub-phase logic ends with state.yaml status update)
write_compliance_json "$epic_id" "$run_id" "$state_file" "$evidence_dir" "$project_root"
```

**Error Handling:**
- `state.yaml` missing during evaluation: branch_correct → false (no claim → assumed wrong).
- `gates/gates_report.json` missing: gates_generated_by → false. Pre-Session-A grandfathered EPICs with this scenario will report false on this check — acceptable (data-truthful).
- Write failure on compliance.json: log_warn, don't fail done-advance (telemetry is best-effort, primary release path is preserved).
- `evaluate_compliance_checks` exit non-zero (jq failure, file system issue): log_warn, write fallback compliance.json with all checks `null` and `notes: ["evaluation failed: <stderr>"]`.

**Edge Cases:**
- **Pre-deploy grandfathered EPIC:** `deploy_era: pre-session-a`, but checks STILL evaluated (just measured for retrospective baseline) — branch_correct may be false (EPIC ran on main), execution_yaml_present may be false, gates_generated_by definitely false. Provides historical ground truth for aggregator.
- **Post-deploy EPIC immediately after deploy where execution.yaml just created:** all 3 checks = true. `overall: pass`.
- **Post-deploy EPIC where PM accidentally bypassed branch check (worktree mode):** branch_correct evaluates state.yaml.branch which may be `feat/foo` from worktree — returns false. PM sees one false dimension in compliance.json, can investigate. Worktree mode skipped enforcement at init time (Step 2), but compliance check is independent.
- **EPIC where gates_report.json missing entirely (early failure, never reached GATES):** gates_generated_by → false. Aggregator counts these as "incomplete EPICs" via overall=fail.
- **Concurrent done-advance retries:** `compliance.json` write is idempotent (same logic, same data) — repeated overwrites OK.

**Dependencies:**
- Depends on: Step 2 (uses existing `log_event` for `compliance_written` event), Step 3 (`fsm_check_grandfather` helper).
- Blocks: Step 5 (aggregator reads compliance.json files; backfill skript DUPLICATES `evaluate_compliance_checks` logic — see Step 5 Dependencies for rationale on why duplication is intentional).

**Acceptance Criteria:**
- [ ] Po dokončení post-deploy EPICu (done-advance) existuje `evidence/<epic>/compliance.json` se schema fields `epic_id`, `run_id`, `aid_version`, `deploy_era`, `evaluated_at`, `checks`, `overall`, `notes`.
- [ ] `checks` má 6 polí: 3 boolean (branch_correct, execution_yaml_present, gates_generated_by), 3 explicit `null` (memory_substantive, verifier_outputs, dod_present).
- [ ] `overall: "pass"` když všechny `checks` ∈ {true, null}, jinak `"fail"`.
- [ ] Komentář v `aid-fsm.sh` u `overall` logiky vysvětluje null semantics pro Sessions B/C.
- [ ] `timeline.jsonl` obsahuje `compliance_written` event s `deploy_era`, `overall`, `checks_passed`, `checks_failed`.
- [ ] Pro grandfathered EPIC (created_at < deploy_date) compliance.json má `deploy_era: pre-session-a` a checks evaluovány retro (může být false).
- [ ] Selhání writer (jq error, FS issue) NEZASTAVÍ done-advance — zaloguje warning a fallback compliance.json se všemi checks `null` + notes `["evaluation failed: ..."]`.

**Effort:** M
**AID Role:** backend

---

### Step 5: Backfill Script + Diagnostic Parametrize + Aggregator

**Objective:** Tři standalone skripty pro telemetrii: `aid-compliance-backfill.sh` (one-shot pre-deploy compliance.json generation), parametrizovaný `aid-diagnostic.sh` (znovu-použitelná Krok 0 forensic logika), `aid-compliance-report.sh` (aggregátor pre vs. post).

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-compliance-backfill.sh` (~90 řádků) — one-shot, scan all evidence dirs, write `compliance.json` s `deploy_era: pre-session-a` pro každý kde chybí.
- Create: `plugins/aid-orchestrator/scripts/aid-diagnostic.sh` (~220 řádků) — refactor Krok 0 forensic logiky do reusable bash s `--evidence-root`, `--output md|json`, `--limit` parametry.
- Create: `plugins/aid-orchestrator/scripts/aid-compliance-report.sh` (~130 řádků) — read all compliance.json souborů (přes `--evidence-root` paths), output trend table (markdown nebo JSON).

**Architecture Context:**
Krok 0 diagnostic findings byl jednorázová analýza generovaná z Python / bash skriptování v rámci sub-agent dispatch. Pro kontinuální measurement musí být logika reusable a callable as utility skript. Backfill skript existuje jako separate one-shot tool (per PM rozhodnutí — neznečisťovat hlavní `aid-diagnostic.sh` podmínkami "jsme v backfill módu"). Aggregátor poskytuje business value (PM vidí pre vs. post number side by side bez ručního lookup).

**Implementation Detail:**

`aid-compliance-backfill.sh`:
```bash
#!/usr/bin/env bash
# One-shot post-Session-A deploy: generate pre-Session-A compliance.json for all existing EPIC dirs.
# Usage: aid-compliance-backfill.sh --deploy-date 2026-05-15 [--evidence-roots "p1 p2"]
set -euo pipefail

main() {
  local deploy_date="" evidence_roots=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deploy-date) deploy_date=$2; shift 2 ;;
      --evidence-roots) read -ra evidence_roots <<< "$2"; shift 2 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$deploy_date" ]] && { echo "Usage: --deploy-date REQUIRED" >&2; exit 1; }
  [[ ${#evidence_roots[@]} -eq 0 ]] && evidence_roots=(
    "/opt/eco/projects/vulcan/.aid-o/work/evidence"
    "/opt/eco/projects/sousto-na-miru/.aid-o/work/evidence"
    "/opt/eco/projects/krok/.aid-o/work/evidence"
    "/opt/eco/projects/wan/.aid-o/work/evidence"
    "/opt/eco/projects/aid-orchestrator/.aid-o/work/evidence"
  )

  local count=0 skipped=0
  for root in "${evidence_roots[@]}"; do
    [[ ! -d "$root" ]] && { echo "Root not found: $root (skip)" >&2; continue; }
    while IFS= read -r epic_dir; do
      [[ ! -d "$epic_dir" ]] && continue
      local run_dirs
      mapfile -t run_dirs < <(find "$epic_dir" -maxdepth 1 -mindepth 1 -type d -name "R-*")
      for run_dir in "${run_dirs[@]}"; do
        local compliance="${run_dir}/compliance.json"
        [[ -f "$compliance" ]] && { skipped=$((skipped+1)); continue; }
        generate_pre_compliance "$run_dir" "$deploy_date" > "$compliance"
        count=$((count+1))
      done
    done < <(find "$root" -maxdepth 1 -mindepth 1 -type d -name "E-*")
  done
  echo "Backfill complete: $count compliance.json generated, $skipped already present (skipped)."
}

generate_pre_compliance() {
  local run_dir=$1 deploy_date=$2
  local epic_id run_id state_file gates_report
  epic_id=$(basename "$(dirname "$run_dir")")
  run_id=$(basename "$run_dir")
  state_file="${run_dir}/state.yaml"
  gates_report="${run_dir}/gates/gates_report.json"

  # Retro-evaluate only branch_correct + execution_yaml_present + gates_generated_by
  # (which are filesystem-readable). Others stay null.
  local branch_value="" branch_correct=false
  [[ -f "$state_file" ]] && branch_value=$(grep '^branch:' "$state_file" 2>/dev/null | awk '{print $2}')
  [[ "$branch_value" =~ ^task/E- ]] && branch_correct=true

  # execution.yaml is per-PROJECT not per-EPIC; need to walk up to project root
  local project_root
  project_root=$(echo "$run_dir" | sed 's|/.aid-o/work/evidence/.*||')
  local exec_yaml_present=false
  [[ -f "$project_root/.aid-o/config/execution.yaml" ]] && exec_yaml_present=true

  local gates_genby=false
  [[ -f "$gates_report" ]] && jq -e '._generated_by' "$gates_report" >/dev/null 2>&1 && gates_genby=true

  jq -nc \
    --arg epic "$epic_id" --arg run "$run_id" --arg ver "v3" \
    --arg era "pre-session-a" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson bc "$branch_correct" --argjson eyp "$exec_yaml_present" --argjson ggb "$gates_genby" \
    --arg note "Backfilled $deploy_date — pre-Session-A run, retro-evaluated 3 dimensions only" \
    '{
      epic_id: $epic, run_id: $run, aid_version: $ver,
      deploy_era: $era, evaluated_at: $ts,
      checks: {
        branch_correct: $bc, execution_yaml_present: $eyp, gates_generated_by: $ggb,
        memory_substantive: null, verifier_outputs: null, dod_present: null
      },
      overall: ([$bc, $eyp, $ggb] | all | if . then "pass" else "fail" end),
      notes: [$note]
    }'
}

main "$@"
```

`aid-diagnostic.sh` — refactor Krok 0 forensic logiky do bash s opcemi:
```bash
#!/usr/bin/env bash
# Parametrized forensic analyzer. Generates AID-v3-diagnostic-findings.md style report.
# Usage: aid-diagnostic.sh [--evidence-root <path>] [--output md|json] [--limit N]
set -euo pipefail

# Top-level: count files, scan timeline events, scan verify files, scan gates_reports, scan audit-reports.
# Output: frequency table per AID-XXX category, top FSM transition reasons, smoking guns (fastest EPICs).
# Logic ported from Krok 0 sub-agent's analytical sweep — see AID-v3-diagnostic-findings.md Sekce A.

# Major output sections:
#   - File counts (timelines, verify, gates_reports, audit-reports, final_reports, self_audits)
#   - Branch hygiene: % state.yaml with branch=main vs task/E-
#   - Memory dimension: % verify with "## Memory Used" empty/N/A/<50chars
#   - CP2/CP3 evidence: % EPIC dirs with verifier-output files
#   - Fake gates: % gates_report.json without _generated_by
#   - Mass-skip: EPICs with EXECUTE→GATES wallclock < 5min and ≥3 steps
#   - FSM transition failure top reasons

# (Full implementation: ~220 lines; concrete forensic queries via grep/jq across evidence dirs)
```

`aid-compliance-report.sh`:
```bash
#!/usr/bin/env bash
# Aggregator: read all compliance.json files, output trend table.
# Usage: aid-compliance-report.sh [--since YYYY-MM-DD] [--era pre|post|both] [--output md|json]
set -euo pipefail

main() {
  local since="" era="both" output="md"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since=$2; shift 2 ;;
      --era) era=$2; shift 2 ;;
      --output) output=$2; shift 2 ;;
      *) shift ;;
    esac
  done

  local evidence_roots=(
    "/opt/eco/projects/vulcan/.aid-o/work/evidence"
    "/opt/eco/projects/sousto-na-miru/.aid-o/work/evidence"
    "/opt/eco/projects/krok/.aid-o/work/evidence"
    "/opt/eco/projects/wan/.aid-o/work/evidence"
    "/opt/eco/projects/aid-orchestrator/.aid-o/work/evidence"
  )

  local all_compliance="[]"
  for root in "${evidence_roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r f; do
      all_compliance=$(jq --slurpfile newf "$f" '. + $newf' <<< "$all_compliance")
    done < <(find "$root" -name "compliance.json" -path "*/E-*/R-*/*")
  done

  # Group by era, count pass/fail per dimension
  local pre_count post_count
  pre_count=$(jq '[.[] | select(.deploy_era=="pre-session-a")] | length' <<< "$all_compliance")
  post_count=$(jq '[.[] | select(.deploy_era=="post-session-a")] | length' <<< "$all_compliance")

  if [[ "$output" == "md" ]]; then
    cat <<EOF
# AID Compliance Trend Report

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Pre-Session-A baseline: ${pre_count} EPICs
Post-Session-A measured: ${post_count} EPICs

| Dimension | Pre (% pass) | Post (% pass) | Δ |
|-----------|--------------|---------------|----|
EOF
    for dim in branch_correct execution_yaml_present gates_generated_by; do
      local pre_pass post_pass
      pre_pass=$(jq --arg d "$dim" '[.[] | select(.deploy_era=="pre-session-a") | .checks[$d]] | map(select(.==true)) | length' <<< "$all_compliance")
      post_pass=$(jq --arg d "$dim" '[.[] | select(.deploy_era=="post-session-a") | .checks[$d]] | map(select(.==true)) | length' <<< "$all_compliance")
      local pre_pct=$(( pre_count > 0 ? pre_pass * 100 / pre_count : 0 ))
      local post_pct=$(( post_count > 0 ? post_pass * 100 / post_count : 0 ))
      local delta=$(( post_pct - pre_pct ))
      printf "| %s | %d%% | %d%% | %+d%% |\n" "$dim" "$pre_pct" "$post_pct" "$delta"
    done
  else
    # JSON output: full grouped data
    jq -n --argjson all "$all_compliance" \
      '{pre: [$all[] | select(.deploy_era=="pre-session-a")],
        post: [$all[] | select(.deploy_era=="post-session-a")]}'
  fi
}

main "$@"
```

**Error Handling:**
- Backfill: missing evidence root → skip with warning. Missing run dir → skip silently. JSON write failure → exit non-zero with stderr details.
- Diagnostic: missing evidence root → exit with usage. jq/grep failures captured as informational warnings, don't kill whole report.
- Aggregator: zero compliance.json files found → output empty table with note. JSON parse error in compliance.json → log warning, skip that file.

**Edge Cases:**
- **Backfill re-run:** existing compliance.json files skipped (`[[ -f $compliance ]] && continue`). Idempotent.
- **Backfill on project without `.aid-o/config/execution.yaml`:** all retro evaluations of execution_yaml_present return false. Aggregator shows pre-deploy 0% on this dimension — correct historical truth.
- **Diagnostic on project with mixed pre/post EPICs:** report is timeline-agnostic — counts current state, doesn't distinguish era. Use compliance-report for era split.
- **Aggregator with --since 2026-04-01 but no post-deploy EPICs yet:** pre count populated, post count = 0, all post percentages = 0%. Acceptable initial state.
- **Aggregator after Sessions B/C deploy:** compliance.json files have new measurements (verifier_outputs, dod_present become true|false). Currently hardcoded `for dim in branch_correct execution_yaml_present gates_generated_by` loop covers only Session A dimensions. **Future extension (1-line change for Sessions B/C):** replace hardcoded loop with `for dim in $(jq -r '.[0].checks | keys[]' <<< "$all_compliance"); do ...` — auto-discovers dimensions from first compliance.json's `checks` keys. Migration becomes mechanical when those Sessions deploy.

**Dependencies:**
- Depends on: Step 4 (compliance.json schema definition; backfill DUPLICATES `evaluate_compliance_checks` logic intentionally because `generate_pre_compliance` runs outside `aid-fsm.sh` runtime context — sourcing the helper would require re-architecting state.yaml resolution, accepted as small duplication).
- Blocks: nothing (release-time tools, run after merge).

**Mid-FSM grandfather backfill (NEW per CP1 M2):**
For EPICs in mid-FSM state at deploy time (i.e., EPICs that hit `fsm_done_advance_fail` previously and sit half-finished — diagnostic-findings.md identifies 14 such EPICs), `state.yaml` lacks the `created_at` field that `fsm_check_grandfather()` requires. Without it, `fsm_check_grandfather` returns false → strict enforcement → these EPICs become unresumable.

`aid-compliance-backfill.sh` MUST also retroactively stamp `created_at` into existing `state.yaml` files when missing:

```bash
# In backfill main loop, BEFORE generating compliance.json:
backfill_state_created_at() {
  local state_file=$1 timeline_file=$2

  if grep -q '^created_at:' "$state_file" 2>/dev/null; then
    return  # already stamped
  fi

  # Source: earliest timeline event ts (most accurate)
  local earliest_ts=""
  if [[ -f "$timeline_file" ]]; then
    earliest_ts=$(jq -r '.ts' "$timeline_file" | sort | head -1)
  fi

  # Fallback: state.yaml file mtime (less accurate post-migration but better than nothing)
  if [[ -z "$earliest_ts" ]]; then
    earliest_ts=$(date -u -r "$state_file" +%Y-%m-%dT%H:%M:%SZ)
  fi

  echo "created_at: $earliest_ts" >> "$state_file"
  log_info "Backfilled created_at=$earliest_ts into $state_file"
}
```

Called in main loop before `generate_pre_compliance` for each run dir. Idempotent (skip if field already exists).

**Acceptance Criteria:**
- [ ] `aid-compliance-backfill.sh --deploy-date 2026-05-15` na vulcan + sousto + krok + wan + aid-orchestrator generuje `compliance.json` v každém EPIC R-*/run dir kde chybí, s `deploy_era: pre-session-a`.
- [ ] Backfill je idempotent (re-run nepřepisuje existující compliance.json).
- [ ] `aid-diagnostic.sh --evidence-root /opt/eco/projects/vulcan/.aid-o/work/evidence --output md` generuje markdown report s frequency table.
- [ ] `aid-diagnostic.sh --output json` generuje validní JSON pro programatické konzumace.
- [ ] `aid-compliance-report.sh` čte všechny compliance.json files napříč 5 default project roots a vypisuje trend table s pre/post percentage per dimension a delta.
- [ ] Report má parameter `--since YYYY-MM-DD` filtrující compliance.json podle `evaluated_at` field.
- [ ] Report má parameter `--era pre|post|both` filtrující podle `deploy_era`.

**Effort:** M
**AID Role:** backend

---

### Step 6: svc-mcp-tg-bot MCP Server (Scaffold + Tool + Docker)

**Objective:** Vytvořit nový Docker službu `svc-mcp-tg-bot` v `/opt/eco/services/mcp-tg-bot/` s FastMCP serverem podporujícím stdio + HTTP transport, tool `send_message`, integrace do `docker-compose.yml` a sdílení tokenu přes `/opt/eco/services/.env`.

**Files:**
- Create: `services/mcp-tg-bot/server.py` (~130 řádků) — FastMCP app, dvě transport možnosti (stdio default, HTTP via `--transport http --port 8818`), tool `send_message`, health endpoint, env loading via `python-dotenv`.
- Create: `services/mcp-tg-bot/Dockerfile` (~25 řádků) — Python 3.12 slim, `pip install -e .`, expose 8818, default CMD = `python -m server --transport http --port 8818`.
- Create: `services/mcp-tg-bot/pyproject.toml` (~30 řádků) — dependencies: `fastmcp`, `httpx`, `python-dotenv`, `python-telegram-bot` (optional, fallback to direct Bot API HTTP via httpx).
- Create: `services/mcp-tg-bot/.env.example` (~8 řádků) — `TELEGRAM_ALERT_BOT_TOKEN=` + `TELEGRAM_ALERT_DEFAULT_CHAT_ID=` placeholders + comment instructions.
- Create: `services/mcp-tg-bot/README.md` (~50 řádků) — deploy guide (setup .env, docker compose up, MCP integration snippet pro `~/.claude/.mcp.json`).
- Modify: root `docker-compose.yml` (eco-dev path) — add `svc-mcp-tg-bot` service block.
- Modify: docker-compose.yml on eco-prod (10.20.20.21) — eco-prod pulls root `docker-compose.yml` from git mirror per CLAUDE.md "code je na eco-prod jako mirror z migrace 2026-04-29", so single edit propagates after `git pull` on eco-prod. PM separately maintains `/opt/eco/services/.env` per-host (different bot tokens / chat IDs possible per env).

**Architecture Context:**
Krok 0 diagnostic Sekce E a Krok 1 isolation findings Sekce E.6 ukazují že telemetry layer potřebuje reliable alert kanál pro repeated-fail patterns. Existující `shared-telegram` MCP (localhost:8817) má podle PM zpráv funkční problémy s "CC Updates" group routing, takže potřebujeme nový dedicated service. FastMCP framework podporuje stdio + HTTP zároveň, což pokrývá oba use case (CC main/sub-agents přes stdio, FSM bash skripty přes HTTP). Service umístěný v `/opt/eco/services/` per ekosystem konvenci (svc-litellm:8830, infra-postgres:5432, atd.), token sdílený v `/opt/eco/services/.env` (per CLAUDE.md infra context).

**Implementation Detail:**

`services/mcp-tg-bot/server.py`:
```python
"""svc-mcp-tg-bot — Telegram Alert MCP Server for AID v3+."""
import os
import sys
import argparse
from typing import Any
import httpx
from fastmcp import FastMCP
from dotenv import load_dotenv

load_dotenv()

mcp = FastMCP(name="svc-mcp-tg-bot", version="1.0.0")

BOT_TOKEN = os.environ.get("TELEGRAM_ALERT_BOT_TOKEN", "")
DEFAULT_CHAT_ID = os.environ.get("TELEGRAM_ALERT_DEFAULT_CHAT_ID", "")
HTTP_PORT = int(os.environ.get("MCP_HTTP_PORT", "8818"))


@mcp.tool()
async def send_message(
    text: str,
    parse_mode: str = "HTML",
    chat_id: str | None = None,
) -> dict[str, Any]:
    """Send a Telegram message via the alert bot.

    Args:
        text: Message body. HTML parse_mode supports <b>, <i>, <code>, <pre>, <a>.
        parse_mode: "HTML" (default), "Markdown", or "MarkdownV2".
        chat_id: Target chat ID. None → uses TELEGRAM_ALERT_DEFAULT_CHAT_ID.

    Returns:
        {"ok": bool, "message_id": int | None, "error": str | None}
    """
    if not BOT_TOKEN:
        return {"ok": False, "message_id": None, "error": "TELEGRAM_ALERT_BOT_TOKEN not set"}

    target_chat = chat_id or DEFAULT_CHAT_ID
    if not target_chat:
        return {"ok": False, "message_id": None,
                "error": "No chat_id provided and TELEGRAM_ALERT_DEFAULT_CHAT_ID not set"}

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {"chat_id": target_chat, "text": text, "parse_mode": parse_mode}

    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            resp = await client.post(url, json=payload)
            data = resp.json()
            if data.get("ok"):
                return {"ok": True, "message_id": data["result"]["message_id"], "error": None}
            return {"ok": False, "message_id": None, "error": data.get("description", "Unknown error")}
        except httpx.HTTPError as e:
            return {"ok": False, "message_id": None, "error": str(e)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--transport", choices=["stdio", "http"], default="stdio")
    parser.add_argument("--port", type=int, default=HTTP_PORT)
    args = parser.parse_args()

    if args.transport == "stdio":
        mcp.run(transport="stdio")
    else:
        # HTTP transport — bind to 127.0.0.1 by default (NOT 0.0.0.0)
        # to prevent LAN exposure with docker network_mode: host.
        # Override via MCP_HTTP_HOST env if explicit external access needed.
        host = os.environ.get("MCP_HTTP_HOST", "127.0.0.1")
        mcp.run(transport="http", host=host, port=args.port)


@mcp.custom_route("/health")
async def health_check(request):
    """Health endpoint for docker healthcheck."""
    return {"status": "ok", "service": "svc-mcp-tg-bot", "version": "1.0.0"}


if __name__ == "__main__":
    main()
```

`services/mcp-tg-bot/Dockerfile`:
```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml ./
RUN pip install --no-cache-dir -e .

COPY server.py ./

EXPOSE 8818

CMD ["python", "-m", "server", "--transport", "http", "--port", "8818"]
```

`services/mcp-tg-bot/pyproject.toml`:
```toml
[project]
name = "svc-mcp-tg-bot"
version = "1.0.0"
description = "Telegram Alert MCP Server for AID v3 ecosystem"
requires-python = ">=3.12"
dependencies = [
  "fastmcp>=0.2.0",
  "httpx>=0.27.0",
  "python-dotenv>=1.0.0",
]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools]
py-modules = ["server"]
```

`services/mcp-tg-bot/.env.example`:
```bash
# svc-mcp-tg-bot environment template
# Copy to /opt/eco/services/.env or service-local .env, fill in values.

# Bot token from BotFather (https://t.me/BotFather → /newbot or existing token)
TELEGRAM_ALERT_BOT_TOKEN=

# Default chat ID (e.g., "CC Updates" group). Use "@your_channel" or numeric ID like -1001234567890.
TELEGRAM_ALERT_DEFAULT_CHAT_ID=

# Optional: HTTP transport port (default 8818)
# MCP_HTTP_PORT=8818
```

`docker-compose.yml` přírůstek (root file):
```yaml
  svc-mcp-tg-bot:
    build: ./services/mcp-tg-bot
    container_name: svc-mcp-tg-bot
    env_file: /opt/eco/services/.env
    environment:
      - MCP_HTTP_HOST=127.0.0.1   # bind to localhost only — prevent LAN exposure
      - MCP_HTTP_PORT=8818
    network_mode: host
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8818/health || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

**Error Handling:**
- Missing `TELEGRAM_ALERT_BOT_TOKEN` env: tool returns `{"ok": false, "error": "TELEGRAM_ALERT_BOT_TOKEN not set"}`. Client (bash FSM) sees non-fatal, continues.
- Missing chat_id (parameter null AND env empty): tool returns `{"ok": false, "error": "No chat_id provided..."}`.
- Telegram API error (token invalid, chat not found, rate limit): catch `httpx.HTTPError`, return error in response. Client continues.
- HTTP transport port already in use: docker fails to bind 8818 → container restart loop. PM detects via `docker ps` showing unhealthy. Resolution: either kill conflicting process or change `MCP_HTTP_PORT`.
- Health check fails: docker restarts container. PM sees in logs `docker logs svc-mcp-tg-bot`.

**Edge Cases:**
- **Bot token revoked by Telegram:** API returns 401, response `{"ok": false, "error": "Unauthorized"}`. PM gets none alert until re-issued. Manual fix.
- **Chat ID typed wrong (no minus prefix for groups):** API returns 400, response includes Telegram error message. PM fixes in `.env`.
- **Container running but tool blocked by firewall (CC main calling stdio via docker exec):** unusual — stdio is process-local, no network. If `docker exec` itself fails, MCP integration is broken. Resolution: verify docker socket permissions for `marekstancl` user.
- **HTTP transport port 8818 conflicts with another service:** PM changes via `MCP_HTTP_PORT` env, updates `try_telegram_alert` URL or adds `--port` flag in calling skript.
- **Concurrent requests (FSM bash + CC main both trying alerts):** FastMCP handles concurrent calls per default async event loop. No issue.

**Dependencies:**
- Depends on: nothing (independent service development).
- Blocks: Step 3 partially (FSM `try_telegram_alert` calls localhost:8818 — works without service running, just logs degradation).

**Acceptance Criteria:**
- [ ] `services/mcp-tg-bot/` adresář obsahuje server.py, Dockerfile, pyproject.toml, .env.example, README.md.
- [ ] `docker compose up -d svc-mcp-tg-bot` na eco-dev startuje container, `docker ps` ukazuje status `healthy` po 30s.
- [ ] `curl -fsS http://localhost:8818/health` vrací 200 OK.
- [ ] `curl -X POST http://localhost:8818/send_message -H "Content-Type: application/json" -d '{"text":"test"}'` při validním token + default chat ID v .env odešle Telegram zprávu, vrátí `{"ok": true, "message_id": <int>}`.
- [ ] Stejný call při missing token vrací `{"ok": false, "error": "..."}` se status 200 (graceful — chyba je v body, ne HTTP status).
- [ ] `python -m server --transport stdio` spustí MCP server na stdio (testovatelné přes MCP client lib).
- [ ] README.md obsahuje copy-paste snippet pro `~/.claude/.mcp.json`.

**Effort:** L
**AID Role:** backend

---

### Step 7: bats Test Suite

**Objective:** Implementovat 16 unit assertions napříč třemi bats soubory pro pokrytí Step 1-5 funkcionalit (FSM preconditions, gate runner markers, init stack detection). Bootstrap bats infrastructure (test-helpers.bash s mktemp evidence dir patterns).

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash` (~80 řádků) — shared helpers: `setup_test_evidence_dir()`, `teardown_test_evidence_dir()`, `mock_git_repo()`, `assert_timeline_event()`.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` (~200 řádků) — 9 assertions:
  1. PRE-FLIGHT: HEAD=main → auto-checkout creates `task/E-test/main`.
  2. PRE-FLIGHT: HEAD=`task/E-test/main` → resume accepted (no branch change).
  3. PRE-FLIGHT: HEAD=`task/E-OTHER/main` → hard fail with copy-paste fix in stderr.
  4. PRE-FLIGHT: HEAD=`feat/foo` → emit `fsm_branch_unusual_detected` event, accept.
  5. PRE-FLIGHT: in worktree (mocked `.git/worktrees/`) → skip enforcement.
  6. PRE-FLIGHT: uncommitted changes → reject.
  7. EXECUTE→GATES: missing `_generated_by` (post-deploy) → hard fail.
  8. EXECUTE→GATES: present `_generated_by` → accept.
  9. EXECUTE→GATES: pre-deploy grandfather (created_at < deploy_date) → accept regardless.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` (~80 řádků) — 3 assertions:
  1. After run: gates_report.json has `_generated_by`, `_generated_at`, `_command_log` fields.
  2. After run: timeline.jsonl has `gate_runner_start` event with required payload fields.
  3. After run: timeline.jsonl has `gate_runner_complete` event with `report_path`, `overall`, `duration_sec`.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` (~100 řádků) — 4 assertions:
  1. Project with pyproject.toml → `python` in detected stacks → execution.yaml has Python gate sections.
  2. Project with package.json → `typescript` in detected stacks → execution.yaml has TS gate sections.
  3. Project with 6+ shell scripts → `bash` in detected stacks (threshold > 5).
  4. Multi-stack (Python + TS) project → execution.yaml has both gate sections in correct order.

**Architecture Context:**
PM rozhodnutí Q6 + T1 — bats unit testy pro Session A. AID-orchestrator project má existing shell-script integration test suite (`scripts/tests/run-all-tests.sh` registered v `defaults/execution.yaml` jako `tests_pass.command`); tento Step přidává bats jako paralelní unit-test layer pro nové bash helpery zavedené ve Steps 1-3. Bats poskytuje standardizovaný bash testing s minimal bootstrap — apt/brew install bats-core. Test-helpers.bash poskytuje shared setup/teardown patterns napříč soubory aby individuální testy nebyly verbose. Decision pro tento Session: bats suite je advisory (run manuálně před merge, `bats scripts/tests/bats/`); integration do `tests_pass` gate je tracked jako follow-up po Sessions B/C — current shell suite zůstává primary tests_pass driver během Session A rollout.

**Implementation Detail:**

`tests/test-helpers.bash`:
```bash
#!/usr/bin/env bash
# Shared test helpers for bats unit suites.

setup_test_evidence_dir() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_PROJECT_ROOT="$TEST_TMPDIR/project"
  export TEST_EVIDENCE_DIR="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-test/R-test"
  mkdir -p "$TEST_EVIDENCE_DIR"
  cd "$TEST_PROJECT_ROOT"
  git init -q
  git config user.email "test@test.local"
  git config user.name "Test"
  echo "init" > .gitkeep
  git add .gitkeep && git commit -q -m "initial"
}

teardown_test_evidence_dir() {
  cd /
  rm -rf "$TEST_TMPDIR"
}

mock_git_worktree() {
  # Force git_dir to look like worktree
  mkdir -p "$TEST_PROJECT_ROOT/.git/worktrees/test-wt"
  GIT_DIR="$TEST_PROJECT_ROOT/.git/worktrees/test-wt"
  export GIT_DIR
}

assert_timeline_event() {
  local timeline=$1 expected_event=$2
  jq -e --arg ev "$expected_event" 'select(.event == $ev)' "$timeline" >/dev/null
}
```

`tests/test-aid-fsm.bats` (sample assertion):
```bash
#!/usr/bin/env bats

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  export AID_PLUGIN_PATH="$BATS_TEST_DIRNAME/.."
  export AID_DEPLOY_DATE="2026-05-15T00:00:00Z"
}

teardown() {
  teardown_test_evidence_dir
}

@test "PRE-FLIGHT: HEAD=main auto-creates task/E-test/main" {
  run "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" init E-test
  [ "$status" -eq 0 ]
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$current_branch" == "task/E-test/main" ]
}

@test "PRE-FLIGHT: HEAD=task/E-OTHER/main hard fails with copy-paste fix" {
  git checkout -b task/E-OTHER/main -q
  run "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" init E-test
  [ "$status" -ne 0 ]
  [[ "$output" =~ "git checkout main && git branch -d task/E-OTHER/main" ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_branch_mismatch_detected"
}

# ... (7 more assertions)
```

**Error Handling:**
- bats not installed: instructions in test-helpers.bash header comment + CONTRIBUTING.md update v Step 9. PR doesn't block on bats availability — tests are advisory before merge.
- Test isolation: each test sets up fresh `mktemp` dir, teardown cleans. Concurrent runs OK.
- Git config conflicts: tests set local `user.email` / `user.name` to avoid using PM's global identity.

**Edge Cases:**
- **bats version difference:** assertions written for bats-core ≥ 1.5 (modern syntax). Older versions might not support `load` properly.
- **TMPDIR full:** mktemp fails → setup hard-fails, test count = 0. PM sees clear error.
- **Network access during tests:** none required (tests don't call external APIs).
- **Git worktree mocking:** `GIT_DIR` env var override is sufficient for `is_worktree()` check (it uses `git rev-parse --git-dir`).

**Dependencies:**
- Depends on: Steps 1-5 (testů přepokládají implementované funkce).
- Blocks: Step 9 (CHANGELOG must reference test count).

**Acceptance Criteria:**
- [ ] `bats tests/` v plugin dir spustí všech 16 assertions, exit code 0.
- [ ] test-aid-fsm.bats pokrývá 9 scenarios z Steps 2 + 3 (branch enforcement + EXECUTE→GATES + grandfather).
- [ ] test-aid-run-gates.bats pokrývá 3 markers + provenance fields ze Step 3.
- [ ] test-aid-init.bats pokrývá 4 stack detection scenarios ze Step 1.
- [ ] Každý test je idempotent (lze spustit opakovaně bez state leakage).
- [ ] Tests běží < 30 sekund celkově (bash setup overhead jen).

**Effort:** M
**AID Role:** qa

---

### Step 8: Pipeline Documentation Updates

**Objective:** Aktualizovat `plugins/aid-orchestrator/skills/pipeline.md` aby odrážela novou Session A behavior — branch enforcement v PRE-FLIGHT, gates execution requirements (EXECUTE→GATES precondition), compliance telemetry v DONE phase.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — three subsection rewrites:
  - PRE-FLIGHT section (~lines 50-100): rewrite "Branch enforcement" subsection with new behavior + timeline events catalog.
  - GATES section (~lines 130-180): rewrite "EXECUTE→GATES precondition" subsection with `_generated_by` requirement + grandfather caveat + repeated-fail behavior.
  - DONE section (~lines 200-240): add new "Compliance Telemetry" subsection s compliance.json schema reference + null/false/true semantika.

**Architecture Context:**
Pipeline.md je primární spec dokument pro AID FSM execution. Změny v aid-fsm.sh / aid-run-gates.sh chování musí být reflected v dokumentaci aby agenti dostali aktuální Component 1 (Playbook) v Context Assembly. Z Krok 0 forensic Sekce E.4 vyplývá že aktuální pipeline.md popisuje verifier dispatch jako "max 2 retries" což agent interpretuje jako optional — analogická úprava pro gates wording: "must be executed by aid-run-gates.sh" místo "ensure gates are run".

**Implementation Detail:**

PRE-FLIGHT subsection rewrite (sample):
```markdown
### Branch Enforcement (NEW v2.16.0 — AID v3)

`aid-fsm.sh init` automatically validates branch context per Section 5.0 spec:

- **Worktree mode:** detected by `.git/worktrees/` ancestry → enforcement skipped, caller's branch accepted.
- **Resume case:** HEAD == `task/E-{epic_id}/main` → log_info, accept (continuing previous session).
- **Fresh init:** HEAD ∈ {main, master, develop} → auto-checkout `task/E-{epic_id}/main` (creates branch).
- **Mismatch:** HEAD == `task/E-OTHER/main` (different EPIC's branch) → hard fail with copy-paste cleanup, emit `fsm_branch_mismatch_detected` timeline event.
- **Unusual:** HEAD == anything else (feat/*, refactor/*, detached HEAD, any non-task pattern) → emit `fsm_branch_unusual_detected` event, log_warn, accept (PM context-aware).
- **Dirty workdir:** uncommitted changes → hard fail with stash/commit suggestion.

The `state.yaml.created_at` timestamp is stamped at init for grandfather logic (used by EXECUTE→GATES precondition). Grandfather threshold is `AID_DEPLOY_DATE` env var or `$AID_PLUGIN_PATH/DEPLOY_DATE` file.
```

EXECUTE→GATES subsection rewrite (sample):
```markdown
### EXECUTE→GATES Precondition (UPDATED v2.16.0)

For post-deploy EPICs (`state.yaml.created_at >= AID_DEPLOY_DATE`):

- `gates_report.json` MUST contain `_generated_by` field (set by `aid-run-gates.sh`).
- Hand-written `gates_report.json` rejected with copy-paste remediation in error message.
- Repeated-fail detection: ≥ 3 same-reason fails on same EPIC → emit `fsm_precondition_repeated_fail` event, attempt best-effort Telegram alert via `try_telegram_alert()` (HTTP POST to localhost:8818).

For pre-deploy grandfathered EPICs (`created_at < AID_DEPLOY_DATE`): precondition skipped (legacy compat).

Required workflow:
1. Complete EXECUTE phase (all steps incremented).
2. Run `bash $AID_PLUGIN_PATH/scripts/aid-run-gates.sh run-all --state-file <state.yaml> --report-file <gates_report.json>`.
3. Run `aid-fsm.sh transition EXECUTE GATES` (validates `_generated_by`).
4. On fail: read error, run remediation command from error message, retry transition.
```

DONE section addition:
```markdown
### Compliance Telemetry (NEW v2.16.0)

After every successful `done-advance`, `aid-fsm.sh` writes `evidence/<epic>/compliance.json` with 6-dimension schema:

| Dimension | Session A status | Source |
|-----------|------------------|--------|
| `branch_correct` | measured | `state.yaml.branch` matches `^task/E-` |
| `execution_yaml_present` | measured | file exists at `<project>/.aid-o/config/execution.yaml` |
| `gates_generated_by` | measured | `gates_report.json._generated_by` field present |
| `memory_substantive` | `null` (Session B/C) | TBD |
| `verifier_outputs` | `null` (Session B) | TBD |
| `dod_present` | `null` (downstream) | TBD |

`null` ALWAYS means "feature not yet measured by deployed Session" (NEVER "not applicable"). When Sessions B/C deploy, currently-null fields become `true|false`.

`overall: "pass"` if all checks ∈ {true, null}; else `"fail"`.

Aggregator: `bash $AID_PLUGIN_PATH/scripts/aid-compliance-report.sh --since YYYY-MM-DD` produces pre vs. post comparison table.

Backfill (one-shot post-deploy): `bash $AID_PLUGIN_PATH/scripts/aid-compliance-backfill.sh --deploy-date YYYY-MM-DD` retroactively generates `compliance.json` for existing EPICs with `deploy_era: pre-session-a`.
```

**Error Handling:**
N/A — documentation update.

**Edge Cases:**
- **Markdown rendering edge:** ensure code blocks use proper triple-backtick syntax for bash and yaml fenced blocks.
- **Cross-references:** if pipeline.md links to legacy gate behavior elsewhere, update or add cross-reference.

**Dependencies:**
- Depends on: Steps 2 (branch enforcement), 3 (EXECUTE→GATES precondition), 4 (compliance schema).
- Blocks: nothing.

**Acceptance Criteria:**
- [ ] pipeline.md PRE-FLIGHT subsection mentions all 5 branch states (worktree, resume, fresh, mismatch, unusual) and 2 timeline events.
- [ ] pipeline.md GATES subsection explicitly states `_generated_by` requirement, grandfather behavior, and repeated-fail Telegram alert.
- [ ] pipeline.md DONE section includes new "Compliance Telemetry" subsection with 6-dimension table and `null` semantics caveat.
- [ ] Every code snippet in pipeline.md uses proper fenced code blocks (` ```bash `, ` ```yaml `).
- [ ] Forbidden phrase scanner clean — pipeline.md edits avoid the 17 phrases listed in plan-writing.md §"Forbidden Shortcuts" table.

**Effort:** S
**AID Role:** docs-writer

---

### Step 9: Release — CHANGELOG, Version Bump, Roadmap

**Objective:** Bump version na v2.16.0 v 8 source-of-truth souborech per CLAUDE.md, zapsat CHANGELOG entry pro Session A, aktualizovat README roadmap. Připravit deploy guide pro post-merge actions.

**Files:**
- Modify: root `CHANGELOG.md` — add `## [2.16.0] — 2026-05-XX` section with Added / Changed / Fixed entries (one bold name per logical change, em-dash separator per CLAUDE.md format).
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical content to root CHANGELOG.md (per CLAUDE.md "Both CHANGELOGs are always identical").
- Modify: `.claude-plugin/marketplace.json` — `metadata.version: "2.16.0"` and `plugins[0].version: "2.16.0"`.
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — `version: "2.16.0"`.
- Modify: `plugins/aid-orchestrator/README.md` — line containing `**Plugin:** 2.X.Y` → `2.16.0`.
- Modify: root `README.md` — `## Roadmap` section, prepend `- **v2.16.0** (current) — Session A Foundation Hardening: branch enforcement, real gates execution, lazy execution.yaml, compliance telemetry, svc-mcp-tg-bot MCP`.
- Create: `plugins/aid-orchestrator/DEPLOY_DATE` (1 line, just ISO 8601 timestamp) — used by `fsm_check_grandfather()` as deploy_date threshold.
- Modify: `plugins/aid-orchestrator/README.md` — add new section "Worktree Development" with `.envrc` direnv bootstrap snippet (pro budoucí Session B/C development).

**Architecture Context:**
Per CLAUDE.md "Version Management" sekce — 8 souborů musí být v sync, Pre-push check je dokumentovaná 4-příkazová sekvence. CHANGELOG entries follow Keep a Changelog format with bold name + em-dash. Plugin update post-merge je manuální per-machine (`claude plugin update` nebo force-refresh přes git fetch + reset). DEPLOY_DATE soubor je nový artefakt — slouží `fsm_check_grandfather()` jako threshold; alternativa je env var `AID_DEPLOY_DATE` set v PM shell rc.

**Implementation Detail:**

CHANGELOG entry (root + plugin):
```markdown
## [2.16.0] — 2026-05-XX

### Added
- **Branch Enforcement in PRE-FLIGHT** — `aid-fsm.sh init` automatically creates `task/E-{epic_id}/main` from main/master/develop, detects mismatch with copy-paste fix, respects worktree mode.
- **Real Gates Execution** — `aid-run-gates.sh` emits `gate_runner_start`/`gate_runner_complete` timeline events and writes `_generated_by`/`_generated_at`/`_command_log` provenance fields into `gates_report.json`. EXECUTE→GATES precondition rejects hand-written reports.
- **Lazy execution.yaml Creation** — `aid-init` (and `aid-fsm.sh` auto-recovery) generates per-project `execution.yaml` from auto-detected stacks (Python, TypeScript, Go, Rust, bash) with DEPENDENCY hint comments per gate command.
- **Compliance Telemetry** — `done-advance` writes per-EPIC `compliance.json` with 6-dimension schema (3 measured for Session A, 3 `null` placeholder for Sessions B/C). Standalone `aid-compliance-backfill.sh` for one-shot pre-deploy backfill. Aggregator `aid-compliance-report.sh` produces pre vs. post comparison.
- **svc-mcp-tg-bot MCP Server** — new Docker service in `services/mcp-tg-bot/` (FastMCP, stdio + HTTP transport on port 8818). Tool `send_message` with HTML parse_mode default. Token shared via `/opt/eco/services/.env`.
- **FSM Repeated-Fail Telegram Alert** — `aid-fsm.sh` emits `fsm_precondition_repeated_fail` event and best-effort `try_telegram_alert()` HTTP POST to localhost:8818 when same precondition fails ≥ 3 times on same EPIC.
- **Parametrized Diagnostic Script** — `aid-diagnostic.sh` reusable forensic analyzer (refactored from Krok 0 logic, supports `--evidence-root`, `--output md|json`, `--limit`).
- **bats Unit Test Suite** — 16 assertions across `test-aid-fsm.bats`, `test-aid-run-gates.bats`, `test-aid-init.bats` covering all new FSM preconditions, gate runner markers, and stack detection.
- **Worktree Development Guide** — README section + `.envrc` direnv bootstrap snippet for `AID_PLUGIN_PATH=$(pwd)` isolation.

### Changed
- **pipeline.md** — three subsection rewrites: PRE-FLIGHT branch enforcement catalog, EXECUTE→GATES precondition with `_generated_by` requirement and grandfather caveat, DONE phase compliance telemetry section.
- **state.yaml schema** — adds `created_at` field (ISO 8601 UTC timestamp) used by grandfather logic for backward compat with pre-deploy EPICs.

### Fixed
- **Branch hygiene gap** — addresses 65% of pre-Session-A `state.yaml` files claiming `branch: main` (no actual task branch). New auto-checkout closes the loop with `done-advance` release sub-phase `git merge`.
- **Fake gates reports** — addresses 0% gate runner execution evidence in 93 analyzed timelines. New provenance fields make hand-written reports mechanically detectable.
- **Missing execution.yaml** — addresses 5/7 (71%) projects lacking gate config, which forced agents to ad-hoc gate names per EPIC with no cross-project consistency.
```

Worktree section pro README (plugin):
```markdown
## Worktree Development

When developing the plugin itself (not using it in another project), work in a dedicated git worktree to avoid chicken-and-egg problems:

\```bash
git worktree add ~/.claude-worktrees/aid-v3-session-a -b feat/aid-v3-session-a
cd ~/.claude-worktrees/aid-v3-session-a
direnv allow   # one-shot per worktree
# AID_PLUGIN_PATH automatically set to $(pwd)/plugins/aid-orchestrator via .envrc
\```

Other projects continue using stable plugin via `~/.claude/plugins/marketplaces/`.
```

DEPLOY_DATE generation in commit:
```bash
date -u +%Y-%m-%dT%H:%M:%SZ > plugins/aid-orchestrator/DEPLOY_DATE
git add plugins/aid-orchestrator/DEPLOY_DATE
```

**Error Handling:**
- Version mismatch detection per CLAUDE.md pre-push check fails: `grep -n '"version"' .claude-plugin/marketplace.json plugins/aid-orchestrator/.claude-plugin/plugin.json` shows mismatch → fix manually before push.
- CHANGELOG format violation: ensure both files are byte-identical (compare with `diff CHANGELOG.md plugins/aid-orchestrator/CHANGELOG.md`).
- Git tag conflict: `git tag v2.16.0` fails if tag exists → either bump to v2.16.1 or delete stale tag.

**Edge Cases:**
- **Concurrent v2.16.x release attempts:** unlikely but possible if multiple Sessions A revisions. Handle with bumped patch version.
- **Plugin update fails on PM machines:** documented fallback in CLAUDE.md (force-refresh via `git -C ~/.claude/plugins/... fetch + reset`).
- **Roadmap section order:** ensure new line is prepended (latest first), older versions move down.

**Dependencies:**
- Depends on: Steps 1-8 (release bundles all changes).
- Blocks: nothing (release is final commit).

**Acceptance Criteria:**
- [ ] All 8 version-bearing files show `2.16.0` (per CLAUDE.md pre-push check commands).
- [ ] CHANGELOG.md root and plugin are byte-identical, contain v2.16.0 section with Added/Changed/Fixed entries (each entry: bold name + em-dash + one specific sentence).
- [ ] Root README.md `## Roadmap` section has v2.16.0 as first entry with one-line summary.
- [ ] `plugins/aid-orchestrator/DEPLOY_DATE` file exists with valid ISO 8601 UTC timestamp.
- [ ] Plugin README.md has new "Worktree Development" section with .envrc snippet.
- [ ] `git tag v2.16.0` succeeds (no pre-existing tag).
- [ ] PR description includes deploy guide checklist for post-merge actions (run backfill, deploy svc-mcp-tg-bot, edit ~/.claude/.mcp.json).

**Effort:** S
**AID Role:** release

---

## Testing Strategy

**Unit testing (bats — Step 7):**
- 16 assertions napříč 3 soubory pokrývající FSM preconditions, gate runner markers, stack detection.
- Test izolace přes `mktemp -d` per-test directories.
- Run: `bats tests/` z plugin root.
- Target runtime: < 30 seconds entire suite.

**Integration testing (deferred to Session B):**
- E2E smoke skript (run full EPIC flow on throwaway project, assert compliance.json) je explicitně out-of-scope Session A — vstupní podmínka pro Session B.

**Manual verification (post-deploy):**
1. Po merge: `claude plugin update aid-orchestrator@claude-aid-o`, restart CC.
2. Run `bash $AID_PLUGIN_PATH/scripts/aid-compliance-backfill.sh --deploy-date $(date -u +%Y-%m-%d)` v hlavním aid-orchestrator project root.
3. Deploy svc-mcp-tg-bot: edit `services/.env`, `docker compose up -d svc-mcp-tg-bot`, verify `docker ps` shows healthy.
4. Add svc-mcp-tg-bot do `~/.claude/.mcp.json`, restart CC.
5. Run sample EPIC v vulcan nebo sousto project: `aid-fsm.sh init E-test`, ověřit auto-checkout `task/E-test/main`.
6. Po dokončení EPICu ověřit `evidence/<epic>/compliance.json` má `deploy_era: post-session-a` a 3 measured fields.
7. Po 5 EPICs napříč ≥ 2 projekty spustit `aid-compliance-report.sh` — verify ≥ 80 % post-deploy hits all 3 dimensions.

**Regression testing:**
- Pre-deploy EPICs (grandfathered): manuálně ověřit že `aid-fsm.sh transition GATES → DONE` projde i když gates_report.json nemá `_generated_by` (pre-deploy era).
- Test grandfather threshold: tam, kde `state.yaml.created_at` chybí, treat as post-deploy (fail-safe).

## Constraints

- **Bash-only enforcement layer** — no Python/JS for FSM logic per AID architectural principle (deterministic, debuggable, easy to test in isolation).
- **System dependencies introduced:** `yq` (Go-based mikefarah variant — `apt install yq` on Debian/Ubuntu, `brew install yq` on macOS, `pacman -S go-yq` on Arch — explicitly **NOT** the Python `yq` PyPI package which has incompatible CLI). Required by `aid-run-gates.sh` for execution.yaml parsing. Verify via `yq --version` showing `mikefarah/yq` in version string.
- **Write access verification (out-of-band, both hosts):** PM confirms `marekstancl` user has write permissions on `/opt/eco/services/.env` on **both** eco-dev (10.20.20.22) AND eco-prod (10.20.20.21) before deploy. Without it, MCP service can't read tokens on second host.
- **localhost-only HTTP binding for MCP:** `svc-mcp-tg-bot` HTTP transport binds 127.0.0.1 only (not 0.0.0.0) despite `network_mode: host`. Audit via `iptables -L INPUT | grep 8818` post-deploy.
- **Backward compatibility** — 203 existing EPIC evidence dirs MUST remain readable and resumable. Implemented via `state.yaml.created_at` grandfather logic.
- **Worktree isolation** — Session A development MUST happen in dedicated git worktree to avoid breaking running AID instances in other projects (vulcan, sousto). `AID_PLUGIN_PATH` env var set via `.envrc` direnv.
- **Single PR, 18 atomic commits** — each commit CI-green standalone (per PM Q8 directive).
- **Telegram MCP must be infra-deployed** — token in `/opt/eco/services/.env`, container in main `docker-compose.yml`, NO standalone curl-based alerts (per PM final preference).
- **Out-of-band PM steps documented** — `~/.claude/.mcp.json` edit, `services/.env` edit, plugin update. PR description includes copy-paste checklist.
- **Version sync (8 files)** — per CLAUDE.md, single source CHANGELOG header, all 8 files must show v2.16.0 before push.
- **No CI infrastructure changes** — bats tests are advisory, run manually before merge. CI integration for AID self-testing is out-of-scope.
- **Czech language for plan / English for code & commit messages** — per project convention.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| FSM precondition zlomí mid-session resume of pre-deploy EPIC | low | medium | Grandfather logic via `state.yaml.created_at` field stamped at init; `AID_DEPLOY_DATE` env var or DEPLOY_DATE file as threshold; if marker absent → fail-safe to post-deploy strict (better strict than permissive) |
| Stack detection false negative (multi-stack edge cases — Python projekt s `.python-version` ale bez pyproject.toml) | medium | low | AUTO-GENERATED + DEPENDENCY hint comments encourage PM customization; `aid-init` is idempotent (re-run safe); manuální doplnění gate sekcí akceptovatelné |
| `aid-run-gates.sh` mismatch s ručně psanými legacy gate names z evidence | medium | medium | Grandfather skip pro pre-deploy; nové gate names z execution.yaml templates jsou per-stack standardy (py_test, ts_lint), legacy reports nadále akceptované jako-is |
| svc-mcp-tg-bot Docker build complications (FastMCP version, network mode conflicts) | medium | low | Best-effort `try_telegram_alert` (graceful degradation); foundation Session A funguje bez MCP (jen není alert pro repeated-fail); README deploy guide má troubleshooting sekci |
| bats not pre-installed on PM machine | low | low | Install instructions v test-helpers.bash header + CONTRIBUTING.md update; PR doesn't block on bats availability — tests are advisory |
| Worktree dev forgets to `direnv allow` | low | medium | `.envrc` committed do worktree branch; README "Worktree Development" sekce explicitně mentions `direnv allow` step |
| `~/.claude/.mcp.json` edit collisions s jinými MCP servery | low | low | PR description obsahuje exact JSON snippet; non-destructive merge (přidat entry, nesahat do existujících) |
| Telegram bot token leak (komitnut do .env nebo docker logs) | low | high | `.env.example` jen template; actual `.env` na `/opt/eco/services/` (out-of-repo); container logs scrub token via `python-dotenv` standard practice (env-only loading) |
| Aggregator hardcoded dimension list nepokryje Sessions B/C dimensions | low | low | Documented constraint v aid-compliance-report.sh — Session B/C work parametrizuje dimensions seznam (1-line change to auto-discovery via jq keys, see Step 5 Edge Cases) |
| Existing `shared-telegram` MCP (8817) port conflict s newcomers | none | none | `svc-mcp-tg-bot` používá 8818, dokumented v Section 3 |
| Telegram per-chat rate limit (1 msg/sec for groups, 30 msg/sec global) hit by simultaneous repeated-fail across multiple EPICs | low | low | `try_telegram_alert` is best-effort with 3-sec timeout (already swallows errors); `alert_threshold: 3` ensures sub-EPIC noise stays low; if rate-limit hit, missed alerts are logged via `log_info` to timeline.jsonl as fallback record |
| `svc-mcp-tg-bot` HTTP endpoint (port 8818) reachable from LAN due to `network_mode: host` — anyone on 10.20.20.0/24 could spam alert chat | low | medium | Bind explicitly to 127.0.0.1 via `MCP_HTTP_HOST=127.0.0.1` env var (default in .env.example), `server.py` uses `mcp.run(host=os.environ.get("MCP_HTTP_HOST","127.0.0.1"), ...)`. FSM bash callers stay local (curl localhost:8818). Audit `iptables -L` post-deploy to confirm no exposure. |
| Mid-FSM EPICs (14 identified) without `created_at` field become unresumable post-deploy due to strict grandfather logic | medium | medium | Backfill skript (Step 5) retroactively stamps `created_at` from earliest timeline event timestamp before generating compliance.json. PM verifies via spot-check on E-044-3, E-045-6, E-006-1 before declaring rollout complete. |

## Success Criteria

- [ ] **Compliance metrics post-deploy:** ≥ 80 % post-deploy EPICs (n ≥ 5 across ≥ 2 projects) hit all 3 measured dimensions (`branch_correct`, `execution_yaml_present`, `gates_generated_by`) within 5 EPICs of deploy.
- [ ] **Backfill complete:** `aid-compliance-backfill.sh` executed successfully, all 203 existing EPIC dirs have `compliance.json` with `deploy_era: pre-session-a`.
- [ ] **Aggregator delivers data:** `aid-compliance-report.sh --since <deploy-date>` produces markdown table showing pre vs. post percentages per dimension with positive deltas (post > pre).
- [ ] **MCP server operational:** `docker ps` shows `svc-mcp-tg-bot` healthy, manual `curl` test succeeds, MCP entry in `~/.claude/.mcp.json` allows CC main + sub-agents to call `send_message` tool.
- [ ] **FSM enforcement validated:** sample EPIC across vulcan + sousto + krok shows auto-checkout of `task/E-...` branch, `aid-run-gates.sh` produces `gates_report.json` with provenance fields, EXECUTE→GATES transition rejects hand-written reports.
- [ ] **Tests pass:** `bats tests/` shows all 16 assertions green.
- [ ] **No regressions on grandfathered EPICs:** Pick 3 random pre-Session-A EPICs (e.g., E-044-3, E-045-6, E-006-1) and verify (a) `state.yaml` has `created_at` field stamped by backfill skript with valid ISO 8601 timestamp, (b) `aid-fsm.sh transition GATES DONE` succeeds without `_generated_by` requirement triggering (grandfather skip path), (c) `compliance.json` written with `deploy_era: pre-session-a`.
- [ ] **Telegram alert verified:** simulated repeated precondition fail (≥ 3) on test EPIC triggers `fsm_precondition_repeated_fail` event in timeline.jsonl + Telegram message arrives in default chat.
- [ ] **Documentation accurate:** pipeline.md sections (PRE-FLIGHT, GATES, DONE) reflect new behavior; CHANGELOG.md root + plugin byte-identical; README.md root + plugin show v2.16.0; DEPLOY_DATE file exists.
- [ ] **PR review complete:** all 18 commits CI-green standalone (or as standalone as bash dependencies allow); PR description has post-merge deploy checklist.

## Next Steps

- [ ] Create EPIC(s) from this plan via `/aid-plan epic .aid-o/plans/P032-aid-v3-session-a.md`. Single phase plan → 1 EPIC, 9 steps.
- [ ] Establish worktree: `git worktree add ~/.claude-worktrees/aid-v3-session-a -b feat/aid-v3-session-a`, set `.envrc`, `direnv allow`.
- [ ] Confirm `AID_DEPLOY_DATE` strategy — file vs. env var. Default: file at `plugins/aid-orchestrator/DEPLOY_DATE` populated v Step 9, fallback to env var.
- [ ] Stub `services/mcp-tg-bot/` directory creation if absent, verify `/opt/eco/services/` has write permissions for `marekstancl`.
- [ ] PM out-of-band preparation (before deploy): obtain Telegram bot token (if not reusing existing), identify "CC Updates" group chat ID.
- [ ] Schedule plugin update plan for downstream projects (vulcan, sousto, krok, wan) post v2.16.0 release per CLAUDE.md "Plugin Update — MANDATORY after every push".
- [ ] After Session A measurement period (5 EPICs across 2+ projects), evaluate whether to proceed with Session B (CP2/CP3 verifier dispatch enforcement) or revisit Session A patterns based on compliance.json aggregator data.

---

**Last Updated:** 2026-05-04
