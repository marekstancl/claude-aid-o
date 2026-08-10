# AID v3 — Sub-agent Isolation Verification (Krok 1)

**Datum:** 2026-05-04
**Cíl:** Empiricky ověřit chování Agent tool dispatchů v Claude Code, abychom věděli zda jsou sub-agenti použitelní jako izolované execution units pro AID multi-EPIC workflow. Pokrývá AID-032 z architectural-inventory.
**Metoda:** 12 paralelních / sekvenčních testů s ground-truth filesystem cross-checks. Provedeno z hlavního orchestrátorského okna (Claude Opus 4.7, VS Code extension, 2026-05-04 14:30 CET).
**Verdikt:** **PASS s nuancemi.** Sub-agenti jsou izolovaní, ale dědí podstatně méně kontextu než manuálně spuštěné druhé okno.

---

## TL;DR pro PM

Sub-agenti splňují tři ze čtyř požadavků z bodu f) initial planu:

| Požadavek (PM) | Verdikt | Evidence |
|---|---|---|
| Vlastní izolovaný kontext (nesdílí s hlavním oknem) | ✅ ANO | T2, T3, T4 |
| Nežerou kontext hlavního okna (token accounting) | ✅ ANO | T6 (sub-agent zkonzumoval 103 094 tokenů, hlavní okno dostalo cca 50 tokenů JSON + metadata) |
| Funguje jako bych spustil okno manuálně | ⚠️ ČÁSTEČNĚ | T8, T12 — manuální okno má víc kontextu (viz tabulka níže) |
| Dostane kompletní sadu instrukcí | ⚠️ JEN COKOLI EXPLICITNĚ POŠLU | T8, T10, T12 — žádné skills, žádné superpowers, žádné MCP instructions |

**Důsledek pro AID v3:** Sub-agenti jsou použitelní, ale **AID-002 (Context Assembly) je ještě důležitější než říká inventory** — bez explicitního VERBATIM injectu má sub-agent jen CLAUDE.md a 8 tools. Manuální druhé okno má skills, MCP instructions, superpowers — sub-agent nic z toho.

---

## Sekce A — Test matrix s výsledky

| # | Test | Hypotéza | Výsledek | Evidence |
|---|------|---------|----------|----------|
| T1 | Tool call obsah viditelný v hlavním okně? | NE — jen text result | ✅ Potvrzeno | 4 bash echos a Read viditelné jen jako `tool_uses: 4` v metadatech |
| T2 | Sub-agent vidí parent conversation transcript? | NE | ✅ Potvrzeno | 5/5 otázek `I-CANNOT-KNOW`, 0 tool calls |
| T3 | Dva paralelní sub-agenti sdílí stav? | NE | ✅ Potvrzeno | Agent B nezná secret zapsaný Agentem A (kromě filesystem) |
| T4 | Vnitřní reasoning sub-agenta leakuje? | NE | ✅ Potvrzeno | 7 internally-generated stringů nikdy se v parent neobjevily |
| T5 | Ground-truth: agenti reálně dělají co tvrdí? | ANO | ✅ Potvrzeno | filesystem artefakty existují s očekávaným obsahem (12-byte secret, 560-byte handoff.json) |
| T6 | Token consumption izolovaná? | ANO | ✅ Potvrzeno | sub-agent: 103 094 tokenů; parent dostal jen JSON+metadata |
| T7 | `aid-orchestrator:implementer` se chová jako `general-purpose`? | ANO | ✅ Potvrzeno | identická izolace, žádný leakage AID kontextu |
| T8 | Sub-agent dědí CLAUDE.md? | ANO | ✅ Potvrzeno | dědí jak project tak global `~/.claude/CLAUDE.md` |
| T9 | 25 sekvenčních tool calls — viditelné? | NE | ✅ Potvrzeno | metadata `tool_uses: 25`, ale obsahy 23 intermediate calls neviditelné |
| T10 | MCP tools dostupné? | ČÁSTEČNĚ | ⚠️ Deferred — vyžaduje `ToolSearch select:<name>` před použitím |
| T11 | Filesystem handoff (handoff.json) funguje? | ANO | ✅ Potvrzeno | 560-byte JSON, jq-valid, secret token přečten z fs ne z agent response |
| T12 | Skills / superpowers / MCP instructions surfaced? | ❌ NE | 🔴 Sub-agent má `skills_count: 0`, žádné MCP instructions, žádný superpowers SessionStart |

---

## Sekce B — Manual second window vs Agent SDK dispatch

Klíčové porovnání. Z perspektivy PM "spustím druhé okno manuálně" má jiný behavior než `Agent({...})`:

| Aspekt | Manual /aid-run window | Agent tool dispatch | Důsledek pro AID |
|---|---|---|---|
| Project CLAUDE.md (`/opt/eco/projects/.../CLAUDE.md`) | ✅ | ✅ | Bez akce — instrukce z CLAUDE.md fungují obousměrně |
| Global `~/.claude/CLAUDE.md` | ✅ | ✅ | Globální user instrukce dědíme |
| `currentDate`, `userEmail` reminders | ✅ | ✅ | OK |
| Auto-memory reminder | ✅ | ✅ | OK — dědí se |
| **Skills (slash commands)** | ✅ surfaced | ❌ `skills_count: 0` | **Sub-agent NEMŮŽE volat `/aid-do`, `/aid-run`, `/loop`, …** |
| **Superpowers SessionStart hook** | ✅ | ❌ | Sub-agent nemá pravidla "always invoke skill before answering" |
| **MCP server instructions section** | ✅ | ❌ | Sub-agent nemá hint "use context7 for library docs" apod. |
| **MCP tools** | ✅ direct callable | ⚠️ deferred — vyžaduje `ToolSearch select:<name>` | Extra round-trip nebo controller injectne výsledky |
| Tools at spawn | ~30+ | **8** (Bash, Edit, Read, ScheduleWakeup, Skill, ToolSearch, Write, +Agent?) | Minimální surface — vše ostatní přes ToolSearch |
| User permission prompts | jdou na PM | jdou na parent agent | Permissions inherited from invoking session |
| Conversation transcript | nezávislý | nezávislý | OK |
| Token budget | nezávislý | nezávislý | OK — sub-agent sleva pro main context (T6 ground truth) |
| `subagent_type` typy | n/a | `general-purpose`, `aid-orchestrator:*`, `Explore`, `Plan`, … | T7 ověřil že AID-specific subagent_type se chová stejně izolovaně |

**Rozhodující nuance:** Manuální druhé okno = "fresh CC session". Agent dispatch = "fresh CC session minus skills/superpowers/MCP instructions". To je **prakticky znamená že controller MUSÍ paste-injectnout vše co sub-agent potřebuje** — nemůže se spolehnout že sub-agent "ví jak se chovat" jen tím že dostane CLAUDE.md.

---

## Sekce C — Pozorovatelná metadata pro parent

Po každém Agent dispatch parent dostává textový return + tento metadata blok:

```
agentId: a<16 hex>
total_tokens: <int>      # tokeny zkonzumované sub-agentem
tool_uses: <int>         # počet tool invocations
duration_ms: <int>       # wallclock
```

**Důsledky pro AID telemetry (AID-027):**
- ✅ Token count per dispatch — basis pro AID-022 budget
- ✅ Tool call count — anomaly detection (anomálně nízké = suspicious)
- ✅ Duration — anomálně rychlé step = suspicious (např. `Step 3: backend role, 12s (median 180s — ANOMALY)`)
- ❌ Tool call CONTENT neviditelný — telemetrie obsahu MUSÍ jít přes filesystem (sub-agent zapisuje `timeline.jsonl`)
- ✅ `agentId` umožňuje resume přes `SendMessage` — pro multi-turn handoff scénáře

---

## Sekce D — Filesystem jako sdílený kanál

Filesystem je **plně sdílený** mezi parent a všemi sub-agenty. To je dvojsečné:

**+ Pro AID:**
- handoff.json (AID-009 variant A1) ✅ funguje — parent po dispatch čte `cat /path/to/handoff.json`
- timeline.jsonl, step-N-verify.md, gates_report.json — všechno přes filesystem
- Plan lessons (AID-011) přes vulcan-find ALE controller-side (po dispatch parent zavolá vulcan-find pro lessons z dokončeného EPICu)

**− Proti AID (AID-029 — remove affordance):**
- Sub-agent má **plný Bash, Edit, Write** — může psát kamkoli na filesystém
- `permissions.yaml` per-role whitelist NEFUNGUJE čistě v Agent SDK (žádný platform-level enforcement)
- Jediný způsob jak prevent unauthorized writes: **post-dispatch diff revert v controlleru** (parent po `Agent` zkontroluje `git diff` a revertuje cokoli mimo deklarované step.outputs)
- Out-of-band subprocess varianta (AID-029 phase 2) **není možná v Agent SDK** — vyžadovala by separátní proces spawn mimo Agent tool

---

## Sekce E — Doporučení pro AID v3

### E.1 — Přijmout Agent SDK dispatch model jako primární execution unit

Izolace je skutečná, token budget je nezávislý, AID-specific subagent_types fungují identicky. Pokračovat v současné architektuře (Agent tool jako execution unit) je správné rozhodnutí — manuální druhé okno NENÍ jediná validní cesta.

### E.2 — AID-002 (Context Assembly) má vyšší prioritu než inventory naznačoval

Protože sub-agent nedostane skills, superpowers, MCP instructions — controller MUSÍ injectnout VERBATIM:

1. Playbook (skills/pipeline.md relevantní sekce, ne odkaz)
2. Role card (kompletní text, ne odkaz)
3. Standards / permissions context (relevantní sekce CLAUDE.md, ne odkaz)
4. **Memory context** — controller volá `vulcan-find` PŘED dispatch a injectuje top-N výsledky jako VERBATIM. Spoléhat na sub-agenta že si zavolá `vulcan-find` je drahé (deferred MCP → ToolSearch → call) a vynechatelné (sub-agent může skipnout)
5. DoD / AC (z plan.json)
6. Source plan VERBATIM
7. Previous step outputs
8. Visual context (pro UI steps)

Toto je již v inventory ale po T8/T10/T12 to není "best practice" — je to **fundamental requirement bez kterého sub-agent nemůže vědět co dělat**.

### E.3 — handoff.json přes filesystem (AID-009 varianta A1) je správná cesta

Variant A2 (out-of-band subprocess který sub-agent nemůže ovlivnit) **není dosažitelná** v Agent SDK. Dosažitelná je hybrid:

1. Sub-agent zapíše `handoff.json` na konci EPICu (povinně)
2. Controller PO `Agent` dispatch:
   - Přečte `handoff.json`
   - Cross-check proti `git log` (commits skutečně existují?)
   - Cross-check proti `timeline.jsonl` (FSM transitions reálně proběhly?)
   - Cross-check proti `step-N-verify.md` souborům (existují, mají očekávané sekce?)
3. Pokud cross-check selže → flag fabrication, force re-dispatch nebo escalate PM

To je hybrid agent-written + controller-validated. Lepší než pure agent-written, dosažitelnější než pure out-of-band.

### E.4 — Permissions enforcement musí být controller-side

`permissions.yaml` per-role write_paths whitelist (AID-029 phase 1) je v Agent SDK pouze policy — sub-agent má plný Edit/Write. Enforcement:

1. Controller PŘED dispatch zachytí baseline `git status`
2. Po dispatch zachytí `git diff` proti baseline
3. Zkontroluje že každý changed file je v `step.outputs[]` z plan.json
4. Pokud najde unauthorized change → `git checkout -- <file>` revert

To je **post-dispatch enforcement**, ne prevence. Ale je to to nejlepší co Agent SDK umožňuje.

### E.5 — Telemetry leverage z metadat

Při každém `Agent({...})` parent dostane `total_tokens`, `tool_uses`, `duration_ms`, `agentId`. Controller by měl po každém dispatch:

```bash
echo '{"epic":"E-...","step":N,"role":"...","agentId":"...","tokens":...,"tool_uses":...,"duration_ms":...,"timestamp":"..."}' \
  >> .aid-o/work/evidence/<epic>/dispatch-telemetry.jsonl
```

Z toho `aid-telemetry.sh` (AID-027) může detekovat:
- Anomálně rychlé steps (≪ median per role)
- Anomálně málo tool_uses (≪ median per step type)
- Token spikes (basis pro AID-022 budget alert)

### E.6 — Vulcan memory cross-window unified

Důležité potvrzení: vulcan-find/store funguje stejně z parent i z sub-agent (po ToolSearch load). Per CLAUDE.md (B-051): VULCAN orchestrátor + Claude Code + Cweb sdílí stejnou Qdrant kolekci. Tj. self-learning per PLAN ID (AID-011) může bezpečně škálovat napříč sessions a okny — to je důležité pro `/aid-reflect`.

---

## Sekce F — Otevřené otázky po této verifikaci

| # | Otázka | Důvod | Block jakého kroku |
|---|--------|-------|--------------------|
| F1 | Co když sub-agent commituje (git commit) — může commit message obsahovat strukturovaný format z AID-031? | Test neprokázal že git commit z sub-agenta funguje. Dosud netestováno. | AID-031 (adversarial commit) |
| F2 | Co když sub-agent dispatchne další sub-agent (recursive Agent tool)? | Multi-level dispatch zvyšuje cost a může mít kompound izolační efekty. | Multi-EPIC orchestrace pokud chceme sub-controllery |
| F3 | User permission prompts při deferred MCP tool selectu — promptují PM nebo se inheritují z parent settings? | Pokud PM se zeptá pokaždé když sub-agent volá `vulcan-find`, je to UX šum. | AID-002 Component 9 (Memory Context) |
| F4 | Jak se chová `subagent_type=Plan` nebo `Explore` (dedicated read-only) — mají jiné tool surface než general-purpose? | Specialized subagent types mohou eliminovat afordance ke psaní (Explore nemá Edit/Write per dokumentace). | AID-029 (capability constraint) |

Tyto otázky **neblokují** Krok 2 (Context Assembly fix). Můžou se vyřešit lazy během implementace.

---

## Sekce G — Závěr

**Verdict pro bod f) z initial-planu:** Sub-agenti **JSOU použitelní** pro AID multi-EPIC workflow.

**Conditions:**
1. Controller MUSÍ injectnout VERBATIM vše co sub-agent potřebuje (skills, MCP instructions, memory) — sub-agent NENÍ "fresh manual window"
2. handoff.json přes filesystem + post-dispatch cross-check (varianta A1+ s controller validation)
3. Permissions enforcement post-dispatch (git diff revert, ne policy ask)
4. Telemetry z dispatch metadat + filesystem timeline.jsonl

**Není potřeba:** Eliminovat sub-agenty z AID. Architektura je validní.

**Další krok (per initial-plan):** Krok 0 (Diagnostická analýza existujících EPIC výstupů). Krok 1 hotový.

---

*Vygenerováno z empirických testů T1–T12 provedených 2026-05-04. Všechny ground truth checky filesystem-verified. Test artefakty cleaned up po dokončení.*
