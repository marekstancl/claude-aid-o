_generated_by: aid-orchestrator:verifier@cp1-P081
_generated_at: 2026-08-10T00:00:00Z
classification: FULL_REVIEW
verdict: fail
Reviewed-Head: ac99228
checkpoint: cp1
focus: docs-review
behavior_trace_required: false
behavior_trace_skip_reason: "CP1 plan-quality review — no handler diff exists yet"
behavior_trace_count: 0

# CP1 review — P081 Test-Tier Pilot

Target: `.aid-o/plans/P081-test-tier-pilot.md`
Binding source: `/opt/eco/docs/docs/ecosystem/specs/test-standard.md` (published 2026-08-10)
Repo HEAD at review time: `ac99228` (plan claims grounding at `8470b13`; all claims re-verified at `ac99228`)

**Verdict: revise_required.** The plan is unusually well grounded — 27 of 30 factual
claims verified exactly as written, `aid-plan-lint.sh` passes, no forbidden phrases,
phase markers correct, dependency graph acyclic. It fails on four classes of defect:
one refuted core premise (Step 1), three internal contradictions that make Step 3/4/5
unsatisfiable as written, two mandatory standard rules silently dropped (flaky
quarantine; T1 aggregate budget), and one structural break where the nightly artifact
can never reach the surface that is supposed to render it (Step 7 → Step 8).

---

## Part 1 — Codebase grounding pass

### Core premise claims

```yaml
item: lib/aid-test-timing-bats.sh exists
verdict: VERIFIED
command_run: ls -l plugins/aid-orchestrator/scripts/lib/aid-test-timing-bats.sh
output_excerpt: "-rw-rw-r-- 5926 Aug 3 11:59 plugins/aid-orchestrator/scripts/lib/aid-test-timing-bats.sh"
```

```yaml
item: "lib/aid-test-timing-bats.sh has NO caller anywhere" (plan L20, L55, L73)
verdict: ABSENT   # the CLAIM is refuted — a caller exists
command_run: grep -rn "aid-test-timing-bats" --include=* . | grep -v '^\./\.git/'
output_excerpt: |
  plugins/aid-orchestrator/scripts/aid-test-audit-profile.sh:36: source "${SCRIPT_DIR}/lib/aid-test-timing-bats.sh"
  plugins/aid-orchestrator/scripts/aid-test-audit-profile.sh:384: timing_doc="$(bats_timing_parse "$(cat "$log_path")" "$run_unit_id" ...)"
  plugins/aid-orchestrator/scripts/aid-test-audit-profile.sh:139: argv=("${argv[0]}" "--timing" "${argv[@]:1}")
  plugins/aid-orchestrator/scripts/aid-test-audit-profile.sh:137: if [[ "$runner" == "bats" && ... ]] && bats_timing_supported; then
```

```yaml
item: lib/aid-test-audit-measure.sh millisecond stopwatch
verdict: VERIFIED
command_run: grep -n "date +%s" plugins/aid-orchestrator/scripts/lib/aid-test-audit-measure.sh
output_excerpt: "37: wall_start_ms=\"$(date -u +%s%3N)\"  /  106: wall_end_ms=\"$(date -u +%s%3N)\""
```

### run-all-tests.sh

```yaml
item: run-all-tests.sh discovery globs (two flat globs)
verdict: VERIFIED
command_run: sed -n '170,190p' plugins/aid-orchestrator/scripts/tests/run-all-tests.sh
output_excerpt: "172: for f in \"$SCRIPT_DIR\"/test-*.sh ... 177: for f in \"$SCRIPT_DIR\"/bats/test-*.bats"
```

```yaml
item: DELEGATED_SUITES — 5 entries, basename-keyed, bats-loop-only
verdict: VERIFIED
command_run: sed -n '150,185p' plugins/aid-orchestrator/scripts/tests/run-all-tests.sh
output_excerpt: |
  run-all-tests.sh:150 declare -A DELEGATED_SUITES=(
    test-aid-plan-release-boundary.bats, test-aid-plan-final-boundary.bats,
    test-aid-service.bats, test-service-lifecycle.bats, test-p076-integration.bats )
  run-all-tests.sh:180 (inside the bats loop only) if [[ -n "${DELEGATED_SUITES[$bn]:-}" ]]
```

```yaml
item: run-all-tests.sh --list
verdict: VERIFIED
command_run: sed -n '108,130p;192,198p' plugins/aid-orchestrator/scripts/tests/run-all-tests.sh
output_excerpt: "113: --list) ... 194: echo \"INLINE: ...\" 195: echo \"DELEGATED: $entry\"; exit 0"
```

```yaml
item: ledger unit-id derivation from path
verdict: VERIFIED
command_run: grep -n "unit_id=" plugins/aid-orchestrator/scripts/aid-select-tests.sh
output_excerpt: "452: bats) unit_id=\"bats:${test_path%.bats}\" ;;  453: bash) unit_id=\"sh:${test_path%.sh}\" ;;"
```

```yaml
item: non-suite helpers in tests/ (plan says run-all-tests.sh, verify-version-files.sh + three others)
verdict: VERIFIED
command_run: ls plugins/aid-orchestrator/scripts/tests/*.sh | grep -v '/test-'
output_excerpt: "release-policy-surface-check.sh, run-all-tests.sh, ui-calibration-run.sh, ui-calibration-verify.sh, verify-version-files.sh  (5 = 2 named + 3 others)"
```

### Selector

```yaml
item: aid-select-tests.sh hardcoded fallback — nine arms
verdict: VERIFIED
command_run: sed -n '176,222p' plugins/aid-orchestrator/scripts/aid-select-tests.sh
output_excerpt: |
  map_path_to_tests() case arms: aid-run-gates.sh(182), aid-plan-diff.sh(185),
  aid-release-policy.sh(188), aid-fsm.sh(196), aid-prefilter.sh(199),
  aid-evidence-verify.sh(202), defaults/schemas/*(205), delivery-gate.yaml(208),
  lib/ui-fidelity/*(211) = 9 arms
```

```yaml
item: mapping_approval.status is "proposed" today
verdict: VERIFIED
command_run: yq '.mapping_approval' .aid-o/config/test-catalog.yaml
output_excerpt: "status: proposed"
```

```yaml
item: selector exit 3 (unverifiable) and exit 11 (mapping_gap)
verdict: VERIFIED
command_run: grep -n "unverifiable\|mapping_gap\|early_exit_status" plugins/aid-orchestrator/scripts/aid-select-tests.sh
output_excerpt: "54: 3 — fail (unverifiable) / 61: 11 — mapping_gap / 417-424: if $unverifiable || $mapping_gap; then ... $unverifiable || early_exit_status=11"
```

```yaml
item: is_production_surface covers scripts/ and defaults/ ONLY (not in plan, but load-bearing)
verdict: VERIFIED
command_run: sed -n '224,242p' plugins/aid-orchestrator/scripts/aid-select-tests.sh
output_excerpt: |
  aid-select-tests.sh:238 "${PLUGIN_PREFIX}/scripts/"*|"${PLUGIN_PREFIX}/defaults/"*) return 0 ;;
  aid-select-tests.sh:239 *) return 1 ;;
  comment 234-235: "Anything else (skills/, commands/, agents/, docs, README, CHANGELOG, top-level .md, …) is also treated as docs/non-production."
```

### CI / workflows / notification

```yaml
item: .github/workflows/ has NO schedule: trigger
verdict: VERIFIED
command_run: grep -rn "schedule:\|cron:" .github/workflows/
output_excerpt: "0 matches"
```

```yaml
item: ci.yml jobs/paths Step 4 modifies (p076-integration-tests)
verdict: VERIFIED
command_run: grep -n "p076\|runs-on" .github/workflows/ci.yml
output_excerpt: "162: p076-integration-tests: / 163: runs-on: [self-hosted, eco-dev] / 178: run: bats plugins/aid-orchestrator/scripts/tests/bats/test-p076-integration.bats"
```

```yaml
item: /opt/eco/services/scripts/lib/telegram-notify.sh + send_telegram_alert, returns 2 silently
verdict: VERIFIED
command_run: sed -n '1,32p' /opt/eco/services/scripts/lib/telegram-notify.sh
output_excerpt: "21: send_telegram_alert() { ... 24-26: if creds empty; then return 2; fi   header: '2 — credentials not configured (silent skip)'"
```

```yaml
item: nightly can reach the telegram helper (self-hosted runner has /opt/eco)
verdict: VERIFIED
command_run: grep -n "runs-on" .github/workflows/ci.yml
output_excerpt: "all 9 ci.yml jobs: runs-on: [self-hosted, eco-dev]"
```

### Surfaces the plan edits

```yaml
item: test-status-two-streams.bats asserts /aid-status render-overview
verdict: VERIFIED
command_run: grep -n "render-overview" plugins/aid-orchestrator/scripts/tests/bats/test-status-two-streams.bats
output_excerpt: "1187: for r in state-root plan-rows stalled-runs controller-state plan-epics planless-epics queue-rows queue-summary next-epic quick-tasks render-overview; do"
```

```yaml
item: commands/aid-status.md render-overview recipe at ~line 885 (plan cites ~330-900)
verdict: VERIFIED
command_run: grep -n "render-overview" plugins/aid-orchestrator/commands/aid-status.md; wc -l
output_excerpt: "74 and 885; file is 1090 lines"
```

```yaml
item: commands/aid-plan.md orientation reads at ~60-105
verdict: VERIFIED
command_run: sed -n '55,80p' plugins/aid-orchestrator/commands/aid-plan.md
output_excerpt: "aid-plan.md:60 '**Orient before Step 1.** Three reads, all cheap:' (773 lines total)"
```

```yaml
item: CLAUDE.md has no "## Conventions" section
verdict: VERIFIED
command_run: grep -n "^## " CLAUDE.md
output_excerpt: "14 H2s, none named Conventions"
```

```yaml
item: the plugin's own generator template defines "## Conventions"
verdict: VERIFIED
command_run: grep -rn "^## Conventions" plugins/aid-orchestrator/
output_excerpt: "plugins/aid-orchestrator/skills/setup/claude-md.md:37: ## Conventions"
```

```yaml
item: scripts/README.md options table is stale (no --list)
verdict: VERIFIED
command_run: sed -n '708,714p' plugins/aid-orchestrator/scripts/README.md
output_excerpt: "### Test Runner Options | --verbose,-v | --help,-h |  (774 lines; --list absent)"
```

```yaml
item: docs/extending-aid.md addressable at ~1267-1340
verdict: VERIFIED
command_run: wc -l docs/extending-aid.md; sed -n '1266,1272p'
output_excerpt: "1977 lines; 1266: '## Test-portfolio decision quality (P072)'"
```

```yaml
item: lib/aid-scoping.sh Files-bullet classifier (Step 10 extends it)
verdict: VERIFIED
command_run: grep -n "_aid_classify_files_bullet" plugins/aid-orchestrator/scripts/lib/aid-scoping.sh
output_excerpt: "147 (doc comment), 184 (_aid_classify_files_bullet() {) — file is 251 lines; plan cites ~120-230"
```

```yaml
item: aid-test-content-scan.sh vacuous + duplicate checks (Step 11 consumes them)
verdict: VERIFIED
command_run: grep -n "vacuous\|duplicate" plugins/aid-orchestrator/scripts/aid-test-content-scan.sh
output_excerpt: "14: 1. duplicate_test_cases; 450: 10b. vacuous green (P079 Step 11, IMP-481); 569/592 emit duplicate_test_cases + duplicate_pairs"
```

```yaml
item: "age since last failure" as an existing reaper input (Step 11)
verdict: ABSENT
command_run: grep -rn "last_fail\|last_failure\|failed_at" plugins/aid-orchestrator/scripts/aid-test-content-scan.sh plugins/aid-orchestrator/scripts/lib/aid-test-*.sh
output_excerpt: "0 matches — git log --follow yields CHANGE age, not last-failure age; no per-suite failure history exists in the tree"
```

### Counts and target files

```yaml
item: "191 suites: 150 bats + 41 sh"
verdict: VERIFIED
command_run: ls plugins/aid-orchestrator/scripts/tests/bats/test-*.bats | wc -l; ls plugins/aid-orchestrator/scripts/tests/test-*.sh | wc -l
output_excerpt: "150 and 41 (= 191)"
```

```yaml
item: exactly six plan-numbered suite filenames
verdict: VERIFIED
command_run: ls plugins/aid-orchestrator/scripts/tests/bats/ plugins/aid-orchestrator/scripts/tests/ | grep -iE "^test-(p|e-|t-)[0-9]"
output_excerpt: "test-p073-integration.bats, test-p074-integration.bats, test-p076-backlog-closure.bats, test-p076-cp3-regressions.bats, test-p076-docs-closure.bats, test-p076-integration.bats — 6, all LOWERCASE"
```

```yaml
item: enforcement-registry test: rows naming the six files
verdict: VERIFIED
command_run: grep -c "test-p07[346]" plugins/aid-orchestrator/defaults/enforcement-registry.yaml
output_excerpt: "registry lines 2366, 2378, 2429, 2441, 2453, 2513, 2549, 2561, 2573, … (multiple rows)"
```

```yaml
item: catalog run_unit_id embeds renamed paths
verdict: VERIFIED
command_run: grep -n "test-p07[346]" .aid-o/config/test-catalog.yaml
output_excerpt: "8918: - run_unit_id: bats:plugins/aid-orchestrator/scripts/tests/bats/test-p073-integration (+ 8921/8923/8933 file lists)"
```

```yaml
item: .aid-o/config/execution.yaml is git-tracked despite the **/.aid-o/ ignore rule
verdict: VERIFIED
command_run: git ls-files .aid-o/ | head
output_excerpt: ".aid-o/config/execution.yaml, .aid-o/config/test-catalog.yaml are tracked (force-added)"
```

```yaml
item: bats_all required:true; shell_pipeline_smoke required:false; both heavy
verdict: VERIFIED
command_run: sed -n '39,68p;95,155p' .aid-o/config/execution.yaml
output_excerpt: "execution.yaml:39 command 'bats $(ls .../bats/*.bats | grep -v -e final-boundary -e release-boundary)' / :40 required: true / :66 run_mode: background ;; shell_pipeline_smoke :150 command 'bash .../run-all-tests.sh' / required: false"
```

```yaml
item: profiles Step 6 must re-point (plan names 5 + 2 quarantine)
verdict: ABSENT   # the enumeration is incomplete
command_run: yq '.gate_profiles | keys' .aid-o/config/execution.yaml   (equivalent grep at :304-393)
output_excerpt: "quick, targeted, standard, full, release, bats_all_quarantine, release_quarantine, p064-closure — p064-closure (line ~366, includes bats_all) is not named in Step 6"
```

```yaml
item: plan-final asserts release_quarantine set-equality against release
verdict: VERIFIED
command_run: sed -n '350,366p' .aid-o/config/execution.yaml; grep -n "_pfsm_profile_include" plugins/aid-orchestrator/scripts/aid-plan-fsm.sh
output_excerpt: "execution.yaml:360-364 'The plan-final stage (aid-plan-fsm.sh plan-finalize --stage gates) asserts this set equality against release and refuses to run otherwise'; aid-plan-fsm.sh:4279 _pfsm_profile_include()"
```

```yaml
item: stale measurement snapshot is 58 of 191 units
verdict: ABSENT   # count differs
command_run: wc -l .aid-o/work/test-audits/TAUD-20260806-0440/measurements.jsonl
output_excerpt: "66 lines (plan says 58 units; either stale or de-duplicated — the qualitative point stands, the number does not reproduce)"
```

```yaml
item: aid_state_root() resolves to the CURRENT checkout's git root
verdict: VERIFIED
command_run: sed -n '140,170p' plugins/aid-orchestrator/scripts/lib/aid-roots.sh
output_excerpt: "aid-roots.sh:157 root=\"$(_aid_roots_common_root \"$PWD\")\" — no cross-checkout awareness"
```

```yaml
item: target files for Step 3/4/12 tests exist
verdict: VERIFIED
command_run: ls -l plugins/aid-orchestrator/scripts/tests/test-run-all-delegation.sh test-epic-to-json-regression.sh verify-version-files.sh test-enforcement-registry-test-audit.sh (in tests/)
output_excerpt: "all four present (5065, 16545, 10405, 13224 bytes)"
```

**ABSENT items and their disposition:** the timing-parser "no caller" claim and the
"age since last failure" input have NO Create step and are load-bearing → contribute to
REVISE_REQUIRED. The `p064-closure` profile omission and the 58-vs-66 count are
correctable text.

---

## Part 2 — plan-writing.md completeness

| Check | Result |
|---|---|
| `aid-plan-lint.sh` | PASS (exit 0); 5 non-blocking description-only path advisories |
| Mandatory per-step fields (Objective/Files/Architecture Context/Implementation Detail/Error Handling/Edge Cases/Dependencies/AC/Effort/AID Role) | PASS — all 13 steps carry all 10 |
| Edge Cases ≥2 (≥3 for M/L) | PASS — every step is M or L and carries exactly 3 |
| AC ≥2 (≥3 for M/L) | PASS — every step carries exactly 3 |
| Forbidden shortcut phrases (21 entries, case-insensitive) | PASS — 0 matches |
| Phase markers match step ranges | PASS — EPIC 1 = 1-5, EPIC 2 = 6-9, EPIC 3 = 10-13, matches actual `### Step` headings |
| Plan-level AC checkboxes each followed within 5 lines by a `verification_pattern` yaml block | PASS — 9/9, all immediately adjacent |
| `verification_pattern.type` ∈ {cmd, must_not_exist, must_contain} | PASS — all 9 are `cmd` |
| Rule 20c self-contained args (no `<placeholder>`, no unresolved `$VAR`) | PASS |
| Dependency lines parseable and acyclic | PASS — 1→2→3→{4,5}; 5→6→7→{8,9}; 3→10; {1,7}→11; {3,5,9,10,11}→12→13. No cycle. |

**Two Part-2 defects that the mechanical lint does not catch:**

- **P2-1 (medium):** Step 3 Files, plan L135 — `Modify: plugins/aid-orchestrator/scripts/tests/`
  is a **directory**, not a file path. The mandatory-fields table requires "at least 1
  concrete file path (no placeholders)". `aid-plan-lint.sh` accepted it, but it makes the
  step's `allowed_paths` the entire tests tree — on the one L-effort step that touches
  191 files, scope-check can no longer distinguish "one header line per file" from "a
  suite was rewritten". Replace with an explicit rule + count, or a generated manifest
  path.
- **P2-2 (low):** Step 3 AC1 (`aid-test-tier-lint.sh` exits 0) and Step 4 AC3 are the same
  assertion. One of the two is redundant, and per F-4 below the Step 3 copy is false at
  Step 3.

---

## Part 3 — Adversarial design review

### 3.1 Contradictions with, and silent drops from, the standard

I walked the standard section by section. Implemented: three tiers and their mechanical
criteria (§Tři patra → Steps 2/3), "patro se určuje podle ceny, ne důležitosti" and the
no-escape-to-T2 rule (Constraints L506), machine-detectable tier via a framework-native
tag recorded in CLAUDE.md (§Jména a sady rule 3 → Steps 3/12), naming rule 2 (§rule 2 →
Steps 3/4), nightly cron + result JSON + red-only single message + streak + second
surface + per-project stagger (§Noční běh 1-4 → Steps 7/8), selector honesty check
(§Selektor → Step 9), reaper with no quota and `git --follow` (§Proti bobtnání → Step 11),
input budget "každý nový test deklaruje patro" (→ Step 10), second review question with
the invalid-answer guard (→ Step 11).

**Dropped, with no amendment and no deferral:**

- **F-1 (CRITICAL) — flaky-test quarantine is absent.** The standard's `## Vrtkavé testy`
  is a mandatory three-state machine: suspicion (fail once, pass on one retry ⇒ marked
  flaky, run continues), quarantine (**owner + date**, does not block merge, **visible in
  every report**), exit (fixed or deleted within 14 days; no owner past the deadline ⇒
  escalate as a red streak) — plus "Počet testů v karanténě je v každém nočním hlášení."
  Grep of the plan for `flak` returns **zero matches**. The only appearance of the word
  quarantine is (a) a `quarantined[]` key in Step 7's JSON with **no producer anywhere in
  the plan**, and (b) `bats_all_quarantine` / `release_quarantine`, which are *gate*
  quarantine — a different, pre-existing concept. Step 8's reminder line does not render a
  quarantine count. So the plan ships a field it never fills and omits the mechanism the
  standard makes mandatory. This is exactly the failure mode the plan itself says it exists
  to prevent (a declared thing with no enforcement).

- **F-2 (CRITICAL) — the T1 aggregate budget is dropped.** Standard §Tři patra: T1
  `Rozpočet: ≤ 10 min na PR **celkem**`, T0 `≤ 2 min`, and explicitly: "Když celkový
  rozpočet T1 na PR přeteče, přebývající sady se přesunou do T2 a je z toho záznam, ne
  tichá tolerance." The plan tiers **per suite** (`<2 s/case`, `<30 s/case`) and never
  sums. Step 6 points `bats_all` at *all* T0+T1 suites. Nothing measures the T1 aggregate,
  nothing enforces the 10-minute ceiling, nothing produces the overflow record. With ~150
  bats suites, a per-case rule of `<30 s` admits an aggregate an order of magnitude over
  budget, and the plan would still report itself compliant. Step 13's before/after
  measurement is a *report*, not a gate: its own Edge Case (L480) says "the measurement
  showing the merge path did not get materially faster ⇒ the feedback document says so
  plainly" — i.e. blowing the standard's budget is an accepted outcome. Needs a step:
  Step 2 must sum per tier and demote the overflow, with the record the standard requires.

- **F-3 (HIGH) — the scope half of the tier criterion is never applied.** Standard §Tři
  patra: tier follows "cena **a rozsah**"; §Co je předmět: "Předmět má cestu v repu — když
  ji nelze ukázat, není to předmět a test patří do T2 (mezikomponentní)." The plan's own
  grounding (L14, L49b) establishes that **119 of 191 suites name a concept, not a file** —
  by the standard's own definition those 119 are cross-component and belong in T2. Step 2
  classifies on measured time **only**; its Architecture Context (L105) asserts "the human
  judgement is confined to scope" but no step, no artifact field, and no AC records a scope
  decision. `aid-test-tier-assign.sh`'s output columns (L101) are suite/runner/ms/cases/
  ms-per-case/tier/reason — no subject, no scope. Consequence: a cheap cross-component
  suite lands in T0/T1 against an explicit rule, and the 119-suite finding — the plan's
  strongest piece of grounding — is used only to reject an alternative, never to classify.
  Applying it is also the main lever on F-2.

- **F-4 (MEDIUM) — naming rules 1, 4 and 5 dropped without a deferral.** Rule 1 ("Jméno =
  předmět") is unenforced; only rule 2 (no plan numbers) is linted. Rule 4 (one suite = one
  subject; fix-an-existing-thing ⇒ new case in the existing suite, split at ~500 lines by
  subject) is unaddressed — Step 10 requires a tier for a new suite but never asks whether
  a new *file* was justified. Rule 5 ("Povinná hlavička" — first lines state what the suite
  proves and its subject) is linted nowhere; Step 4 adds a provenance header to six files
  only. Step 13's AC3 ("every standard rule is marked implemented, amended or deferred")
  defers the whole accounting to the final step, i.e. after every design decision is frozen
  and every EPIC is merged. The rule-by-rule table belongs in the plan **now**.

- **F-5 (LOW) — §Produkce a výjimky and §Mezi projekty are unaddressed.** The green-nightly-
  ≤24 h deploy tag with its named-exception record, and the cross-project ownership rule
  (owner named in CLAUDE.md), have no step. AID is not deployed, so deferral is legitimate —
  but Scope's "Out of scope" list does not mention them, so as written they are dropped
  rather than deferred. Step 12 writes `## Conventions` and is the natural home for the
  ownership line.

### 3.2 Is the tier-tag decision safe?

The mechanism choice is right — I re-verified the blast-radius asymmetry (registry `test:`
fields, catalog `run_unit_id` join keys, five DELEGATED_SUITES basenames, nine ci.yml jobs
with literal paths). A comment tag survives bats preprocessing (bats leaves comments
untouched), shellcheck (comments are not directives unless prefixed `shellcheck`), and the
content scanner (it parses `@test` names and shell constructs, not arbitrary comments).

But there **is** a case where the tag is present and unreadable:

- **F-6 (HIGH) — the ten-line reader window contradicts the stated placement.** Step 3 L133:
  the reader "extracts `# aid-tier: <t0|t1|t2>` **from the first ten lines**". Step 3 L135:
  the tag goes "immediately after the shebang **or the existing header comment**". Those
  are incompatible for a large share of the portfolio. Measured at `ac99228`, the leading
  comment block is ≥40 lines in at least 8 bats suites (`test-status-two-streams.bats`,
  `test-p076-integration.bats`, `test-p076-docs-closure.bats`, `test-p074-integration.bats`,
  `test-release-policy.bats`, `test-recovery-adjudicate.bats`, `test-service-declaration.bats`,
  `test-generation-resume.bats`; my probe capped at 40, so the true headers are longer) and
  ≥47 lines in `test-cp1-gate.sh`. Under the stated rules those suites are stamped, look
  compliant to a human, and read as **untagged** — which under Step 5's Error Handling makes
  `run-all-tests.sh` **refuse the entire run**, and under Step 3's lint fails the tree. The
  contradiction must be resolved explicitly: either "line 2 or 3, before the header comment"
  (and say so), or "anywhere in the file, first match wins" (which then collides with Step 3's
  two-tag violation rule and needs a stated scan bound).

- **F-7 (HIGH) — Step 3's lint regex cannot match the files it is written to catch.** Step 3
  L134 specifies the filename ban as `P[0-9]+`, `E-[0-9]+`, `T-[0-9]+` — **uppercase**. Every
  actual offender is lowercase (`test-p073-integration.bats`, …), and the plan's own AC9
  (L595) uses the lowercase class `test-(p|e-|t-)[0-9]+`. As written the lint passes over all
  six files and Step 4's AC3 ("`aid-test-tier-lint.sh` exits 0 — no plan-numbered filenames
  remain") proves nothing.

### 3.3 Step 6 — does the stated safety net hold? (traced scenario)

**It does not, for the most likely miss class.** The plan's risk table (L517) names the
mitigation as "the selector's `unverifiable`/`mapping_gap` escalation stays". That escalation
fires only when a changed path is **unmapped inside the production surface**. It cannot fire
for a path that IS mapped.

Concrete trace — a change to `plugins/aid-orchestrator/scripts/aid-fsm.sh`:

1. `aid-select-tests.sh:196-198` matches the path exactly and emits one unit:
   `bats:…/tests/bats/test-aid-fsm.bats`. `unverifiable=false`, `mapping_gap=false`,
   exit 0. The escalation the plan relies on is structurally unreachable.
2. Today the miss is caught anyway: `bats_all` (`required: true`, execution.yaml:40) runs the
   whole bats tree minus two files, and `shell_pipeline_smoke` runs all 191. After Step 6,
   `bats_all` runs T0+T1 only.
3. The FSM's *real* integration coverage lives in the heavy suites —
   `test-aid-plan-final-boundary.bats`, `test-aid-plan-release-boundary.bats`,
   `test-p076-integration.bats` — the same suites already delegated for cost. By Step 2's own
   time-only rule they land in **T2** by construction (Step 2 Edge Case L113 concedes exactly
   this: "they … will land in T2").
4. Merge path for an FSM change therefore becomes: one thin unit suite + whatever else happens
   to be T1. The regression surfaces that night.
5. Step 9's honesty check then reports **no gap** — because it asks "would the selector have
   picked *this failing suite*", and the answer for the mapped-but-narrow case is "the selector
   picked *something*, just not this". The check as specified (L332, L335) is blind to the exact
   failure it was added to catch.

- **F-8 (CRITICAL).** The risk-table mitigation is inapplicable to mapped-but-thin paths, and
  the honesty check does not cover them. Two corrections are needed: (i) Step 9 must classify a
  T2 failure whose changed paths were *mapped but to a suite that did not exercise the failing
  behaviour* as a gap of its own class (not `unmappable`, not "selected"); (ii) Step 6 must not
  demote a suite to T2 purely on cost when it is the only merge-path coverage for a mapped
  subject — that is the scope half of F-3, and without it the demotion is exactly the "úniku do
  T2" the standard bans, arrived at mechanically instead of deliberately.

- **F-9 (HIGH) — the standard's "never silently select nothing" rule is violated today and the
  plan neither fixes nor defers it.** `is_production_surface()` (aid-select-tests.sh:236-241)
  limits the production surface to `scripts/` and `defaults/`; its own comment (:234-235) states
  that `skills/`, `commands/`, `agents/`, non-ui-fidelity `lib/` and all docs "fall through to
  the docs/non-production no-op path". So a change to `skills/plan-writing.md` or
  `commands/aid-status.md` selects **zero** suites and exits **0** — precisely what the standard
  forbids ("Co neumí rozřešit, hlásí jako `nerozhodnuto` … nikdy tiše nevybere nic"). This is
  not hypothetical for P081: Steps 8, 10 and 11 edit `commands/aid-status.md`,
  `commands/aid-plan.md`, `skills/plan-writing.md` and `skills/review-checkpoint-contracts.md` —
  the plan's own changes sit in the blind spot, and after Step 6 the broad suite no longer backs
  them up.

- **F-10 (MEDIUM) — Step 6 collides with a live plan-final assertion it never names.**
  `execution.yaml:360-364` records that `aid-plan-fsm.sh plan-finalize --stage gates` "asserts
  this set equality against `release` and refuses to run otherwise". `release_quarantine`
  currently lists `shell_pipeline_smoke` explicitly; Step 6 removes that gate "from every
  merge-path profile". Step 6's Edge Case (L247) says quarantine profiles are "re-pointed the
  same way" but its Files list contains neither `aid-plan-fsm.sh` nor any test of the assertion,
  and `_pfsm_profile_include()` (aid-plan-fsm.sh:4279) is the code that will refuse. Step 6 also
  enumerates five profiles + two quarantine profiles; `.aid-o/config/execution.yaml` defines an
  eighth, `p064-closure`, which includes `bats_all`.

- **F-11 (MEDIUM) — Step 6's headline benefit is partly already true, and its headline number is
  not a current measurement.** `shell_pipeline_smoke` is `required: false` today, and `bats_all`
  is `run_mode: background` — so "the full portfolio is a precondition for closing every plan" is
  true of `bats_all` (required) but not of the 191-suite gate. Separately, execution.yaml's own
  comments state `bats_all` "has never completed at all (percentiles null)" and that
  `shell_pipeline_smoke`'s five non-censored samples date to 2026-07-15 under a then-1900 s cap.
  The plan rejects the stale snapshot as a classification input (L49c) but keeps quoting its
  aggregate (12 200 s / 3 h 23 min) as the benefit baseline. Say which part was blocking and mark
  the aggregate as the same unbacked figure the plan elsewhere refuses to inherit.

### 3.4 Ordering: Step 3 before Step 4, and Step 2's measurement

- **F-12 (HIGH) — Step 3's AC1 is unsatisfiable at Step 3.** Step 3 builds a lint that (per L134)
  "asserts no suite filename contains a plan, EPIC or task number", and Step 3's AC1 (L154)
  requires that same lint to "exit 0 over the shipped tree". The six offenders are not renamed
  until **Step 4**, which explicitly `Depends on: Step 3`. So Step 3 cannot close on its own AC.
  Fix: seed the allowlist file with the six basenames in Step 3, and make emptying it part of
  Step 4's AC. The plan already ships the allowlist mechanism (L134, L147) — it just never uses
  it for the migration window.
  *(Stamping 191 files before renaming 6 is otherwise fine: `git mv` moves the tag with the file,
  so there is no tag churn.)*

- **F-13 (HIGH) — Step 1 and Step 2 contradict each other on delegated suites, and the count is
  wrong.** Step 1 Edge Case (L81): "A delegated suite (skipped inline) — **no record is written**;
  classification treats a suite with no measurement as unclassifiable." Step 2 Edge Case (L113):
  "The **two** boundary suites already delegated to their own CI jobs — they are **measured like
  any other** and will land in T2." Both cannot hold. And there are **five**, not two:
  `DELEGATED_SUITES` (run-all-tests.sh:150-166) lists `test-aid-plan-release-boundary.bats`,
  `test-aid-plan-final-boundary.bats`, `test-aid-service.bats`, `test-service-lifecycle.bats`,
  `test-p076-integration.bats` — the plan's own grounding line (L20) says five. So at least five
  suites are structurally unmeasurable by Step 2's single `run-all-tests.sh --timing` invocation,
  while Step 3 must stamp all 191 and Step 3's Error Handling (L142) accepts an unmeasured tag
  "as declared" — leaving five hand-assigned tiers with no rule for who assigns them.

- Step 2's measurement run *does* correctly precede the tags, and that is consistent — the
  assignment tool reads the durations journal and the discovered suite list, neither of which
  needs a tag. No finding.

### 3.5 Self-reference: the plan changes its own gates mid-flight

- **F-14 (HIGH) — the new partition is never validated before the plan closes.** Step 6 rewrites
  `.aid-o/config/execution.yaml` (git-tracked, verified) at the EPIC 2 boundary. EPIC 1's steps
  are verified under the old profile; EPIC 2's and EPIC 3's under the new one; and plan-final runs
  `release`, one of the profiles Step 6 rewrites. Testing Strategy L501 explicitly accepts this
  ("no full-portfolio run is required to close this plan"). The consequence is that the **tier
  assignment produced by this plan is never once proven green across the full portfolio under the
  new configuration before the plan is released** (Step 13). The plan builds the instrument for
  that proof — Step 7's `workflow_dispatch` — and never uses it. Minimum fix: one manual
  `workflow_dispatch` T2 run after Step 6, its green recorded as an AC of Step 13, alongside the
  before/after duration Step 13 already collects.

- **F-15 (MEDIUM) — the runner's fail-closed refusal will fire during this plan's own execution.**
  Step 5 makes `run-all-tests.sh` **refuse the run** when any discovered suite is untagged. Steps
  7, 8, 9 and 11 each create a new bats suite. Only Testing Strategy L497 (a plan-level bullet)
  says new suites carry a tag; no step's Files entry or AC requires it. Any step that creates a
  suite and runs the gates before tagging it bricks every gate invocation in the plan. State the
  requirement per step, or make the refusal name the file and exit before running (it already
  does the former — but the AC should assert it).

- **F-16 (MEDIUM) — the consumer-degradation rule and the runner's refusal are in conflict.**
  Step 6 Edge Case (L248): "A consumer project with no tiers yet — the shipped template's
  tier-filtered command must degrade to 'run everything' when no suite carries a tag." Step 5
  Error Handling: an untagged suite makes the *runner* refuse. A fresh consumer project has 100 %
  untagged suites, so it hits the runner's refusal before the gate command's degradation can
  matter. These must be one rule (e.g. "refuse only when at least one suite in the tree carries a
  tag"), stated once, in one step.

### 3.6 "Already exists" claims that do not

- **F-17 (HIGH) — the Step 1 premise is false.** Plan L20 ("`lib/aid-test-timing-bats.sh` parses
  `bats --timing` TAP but **no caller anywhere** invokes `--timing`"), L55 ("nothing calls it") and
  L73 ("has no caller anywhere in the tree — this step supplies the caller"). A caller exists:
  `aid-test-audit-profile.sh:36` sources the library, `:137` gates on `bats_timing_supported`,
  `:139` inserts `--timing` into argv, `:384` calls `bats_timing_parse`. The step is still worth
  doing (the profiler is a per-unit diagnostic path, not a portfolio runner), but the plan must
  rewrite the premise — and, more usefully, must **inherit the profiler's scar tissue**, which it
  currently ignores: the plugin CHANGELOG records that `--timing` inserted into the wrong argv slot
  produced `bash --timing -c …` for shell-form commands, and `aid-test-audit-profile.sh:184-201`
  carries the "approve the EXACT executed argv, `--timing` permitted only as a checked one-token
  diff" guard that came out of it. Step 1 re-implements `--timing` insertion in `run-all-tests.sh`
  with no reference to either. This is a documented prior incident on the identical mechanism.

- **F-18 (MEDIUM) — one of the reaper's four standard-mandated inputs does not exist.** Step 11 L405:
  "Every input already exists … so this step is assembly, not new detection." The standard's four
  inputs are vacuous-green, duplicates, **stáří posledního pádu**, and run cost. Vacuous-green and
  duplicates verify (content-scan.sh:14, :450); cost comes from Step 1. "Age since last failure" does
  not exist: `git log --follow` (L407) gives *change* age, and grep finds no per-suite failure history
  anywhere in the tree. Step 1's journal records exit codes going forward only, so the signal has no
  data until the nightly has run for months. Either add the detection or state the input as
  degraded-at-first with the standard's "which input was unavailable" note (Step 11's Error Handling
  already has the shape for it — it just names the wrong missing input).

- **F-19 (LOW) — the snapshot count.** Plan L20/L49c say the existing measurement covers "58 of 191";
  `measurements.jsonl` has 66 lines. The qualitative argument (partial, sibling worktree, lists
  deleted suites) is unaffected; the number should be corrected or its derivation stated.

### 3.7 The structural break nobody named

- **F-20 (CRITICAL) — the nightly artifact can never reach the surface that renders it.** Step 7
  writes `$(aid_state_root)/.aid-o/work/nightly/<date>.json` **inside the GitHub Actions job**.
  Step 8's `/aid-status` reads `.aid-o/work/nightly/latest.json` from the **PM's checkout**. Three
  verified facts make these different files: (a) `aid_state_root()` (aid-roots.sh:157) resolves to
  the git root of `$PWD` with no cross-checkout awareness; (b) the self-hosted runner checks out
  into its own `_work/…` workspace, not `/opt/eco/projects/aid-orchestrator`; (c) `.gitignore:98`
  ignores `**/.aid-o/`, so the artifact cannot travel by commit. The result is that Step 8 — the
  standard's mandatory **second surface**, added precisely so a missed Telegram message is not a
  lost result — renders nothing, forever, and does so silently (Step 8 L311: "No `.aid-o/work/nightly/`
  at all ⇒ nothing rendered; a project without a nightly is not in a red state"). The failure is
  indistinguishable from the healthy fresh-project case. Every AC in Step 8 passes because they are
  all fixture-driven (L302: "green, red-with-streak and absent-artifact **fixtures**"), and Testing
  Strategy L500 makes that explicit: "no test depends on a real scheduled run." The plan needs a
  named transport (workflow commits the JSON to a tracked path outside `.aid-o/`, or the reporter
  writes to a host path both trees can read, or the job pushes to a branch/release asset) plus one
  end-to-end acceptance that the PM's `/aid-status` shows a result the CI job produced.
  The staleness rule Step 8 L306 defines ("not run since <date>" past two days) would be the only
  thing rendered — and it would fire permanently, which is at least loud, but the plan does not
  reach that conclusion.

---

## What would make this a pass

Nine edits, in the plan, before generation:

1. Add a flaky-suspicion → quarantine (owner + date) → 14-day exit mechanism with the count in
   the nightly report and the `/aid-status` line, or move it to Out of scope with the PM's reason
   and a named follow-up (F-1).
2. Make Step 2 sum per tier, enforce the standard's T0 ≤ 2 min / T1 ≤ 10 min aggregates, and emit
   the overflow-demotion record (F-2).
3. Add the scope criterion to Step 2's assignment: a suite with no resolvable subject path is T2
   regardless of measured cost; record the subject column in the assignment artifact (F-3, F-8ii).
4. Fix Step 3: case-insensitive filename regex; a stated, unambiguous tag placement and scan window
   verified against the ≥40-line headers in the tree; the six offenders allowlisted in Step 3 and
   the allowlist emptied in Step 4's AC (F-6, F-7, F-12).
5. Reconcile Step 1 and Step 2 on delegated suites, correct "two" → five, and state who assigns a
   tier to a structurally unmeasurable suite (F-13).
6. Name a transport for the nightly artifact from CI to the PM's checkout, with one non-fixture
   acceptance criterion (F-20).
7. Extend Step 9 with a mapped-but-thin gap class, and add the selector's `skills/`/`commands/`/
   `agents/`/`lib/` blind spot to Scope as either a step or an explicit deferral (F-8i, F-9).
8. Add `aid-plan-fsm.sh`'s `release_quarantine` set-equality assertion and the `p064-closure`
   profile to Step 6's Files and ACs (F-10).
9. Correct Step 1's premise, cite the `bash --timing -c` argv incident and the profiler's argv
   guard as the pattern to follow, and fix the reaper's "age since last failure" input claim
   (F-17, F-18).

---

```
verdict: revise_required
findings:
- [critical] F-1 flaky-test quarantine (standard §Vrtkavé testy — owner+date, 14-day exit, count in every nightly report) is absent from the plan entirely; grep "flak" on P081 returns 0 matches, and Step 7 L268 emits a `quarantined[]` JSON key with no producer anywhere in the plan
- [critical] F-2 the standard's aggregate budgets (T0 ≤ 2 min, T1 ≤ 10 min per PR total, overflow demoted with a record) are dropped; the plan tiers per-suite only (L101) and Step 6 L235 runs ALL T0+T1 on the merge path with nothing summing or capping them
- [critical] F-8 Step 6's stated safety net does not hold for a mapped-but-thin path: a change to scripts/aid-fsm.sh matches aid-select-tests.sh:196-198, selects one unit, exits 0 — so exit 3/11 is structurally unreachable — while the FSM's real coverage (test-aid-plan-final-boundary/-release-boundary/test-p076-integration) lands in T2 by Step 2's cost-only rule (conceded at L113), and Step 9's check reports "no gap" because the selector did pick something
- [critical] F-20 the nightly artifact can never reach the surface that renders it: Step 7 L268 writes $(aid_state_root)/.aid-o/work/nightly/<date>.json inside the CI job, Step 8 L299 reads it from the PM's checkout; aid-roots.sh:157 resolves to $PWD's git root, the self-hosted runner uses its own _work checkout, and .gitignore:98 ignores **/.aid-o/ — the standard's mandatory second surface silently renders nothing, and every Step 8 AC still passes because all three are fixtures (L302, L500)
- [high] F-3 the scope half of the tier criterion (standard §Co je předmět: no resolvable path ⇒ T2) is never applied; Step 2 L101 classifies on measured time only and its columns carry no subject, so the plan's own 119-of-191 no-resolvable-subject finding (L14, L49b) is used to reject an alternative and never to classify
- [high] F-6 Step 3's tag reader window and tag placement contradict: L133 reads "the first ten lines", L135 places the tag "after the existing header comment" — ≥8 bats suites and test-cp1-gate.sh have leading comment blocks of 40-47+ lines, so those suites read as untagged, failing the lint and triggering Step 5's whole-run refusal
- [high] F-7 Step 3 L134's filename ban regex is uppercase (`P[0-9]+`, `E-[0-9]+`, `T-[0-9]+`) and cannot match any of the six lowercase offenders (`test-p073-integration.bats`, …); the plan's own AC9 L595 uses the lowercase class, so Step 4's AC3 proves nothing
- [high] F-9 the standard's "nikdy tiše nevybere nic" rule is violated by the live selector and the plan neither fixes nor defers it: is_production_surface() (aid-select-tests.sh:236-241, comment :234-235) treats skills/, commands/, agents/ and non-ui-fidelity lib/ as non-production and exits 0 selecting nothing — and Steps 8/10/11 edit exactly those paths
- [high] F-12 Step 3's AC1 (L154, lint exits 0 over the shipped tree) is unsatisfiable at Step 3, because the same lint bans plan-numbered filenames and the six offenders are not renamed until Step 4, which depends on Step 3; the allowlist mechanism the plan already defines (L134/L147) is never used for the migration window
- [high] F-13 Step 1 Edge Case L81 ("a delegated suite — no record is written") contradicts Step 2 Edge Case L113 ("they are measured like any other"), and L113 says "two" delegated boundary suites when run-all-tests.sh:150-166 lists five (the plan's own L20 says five) — leaving ≥5 suites structurally unmeasurable with no stated rule for assigning their tier
- [high] F-14 the plan rewrites its own merge-path gate profile mid-flight (Step 6, .aid-o/config/execution.yaml, git-tracked) and Testing Strategy L501 waives any full-portfolio validation, so the tier partition this plan invents is never proven green under the new configuration before Step 13 releases it — despite Step 7 L267 building the workflow_dispatch that would prove it
- [high] F-17 Step 1's premise is refuted: the plan asserts "no caller anywhere" for lib/aid-test-timing-bats.sh (L20, L55, L73) but aid-test-audit-profile.sh:36/137/139/384 sources it, gates on bats_timing_supported, inserts --timing and calls bats_timing_parse — and the plan cites neither the recorded `bash --timing -c` argv-slot bug nor the argv-exactness guard at aid-test-audit-profile.sh:184-201
- [medium] F-10 Step 6 removes shell_pipeline_smoke from every merge-path profile but never names the plan-final set-equality assertion that release_quarantine must satisfy (execution.yaml:360-364; aid-plan-fsm.sh:4279 _pfsm_profile_include), and omits the eighth profile p064-closure (execution.yaml ~366) which includes bats_all
- [medium] F-11 Step 6's benefit is overstated and its baseline is the same unbacked figure the plan elsewhere refuses: shell_pipeline_smoke is required:false today and bats_all is run_mode:background, while execution.yaml's own comments record that bats_all has never completed (percentiles null) and shell_pipeline_smoke's last non-censored samples are from 2026-07-15 under a 1900 s cap
- [medium] F-15 Steps 7, 8, 9 and 11 each create a new bats suite, and Step 5's runner refuses any run containing an untagged suite; only the plan-level Testing Strategy L497 requires the tag, no step's Files entry or AC does
- [medium] F-16 Step 6 Edge Case L248 (untiered consumer degrades to "run everything") and Step 5's Error Handling (untagged suite ⇒ refuse) are contradictory rules in two different layers; a fresh consumer hits the runner's refusal before the gate command's degradation applies
- [medium] F-18 Step 11 L405 claims "every input already exists"; "stáří posledního pádu" does not — git log --follow (L407) gives change age, no per-suite failure history exists in the tree, and Step 1's journal only accumulates going forward
- [medium] F-4 standard naming rules 1 (jméno = předmět), 4 (one suite = one subject, ~500-line split) and 5 (povinná hlavička) are unimplemented and undeferred; Step 13's AC3 defers the whole rule-by-rule accounting to the terminal step, after every design decision is frozen
- [medium] P2-1 Step 3 Files L135 declares a directory (`plugins/aid-orchestrator/scripts/tests/`) rather than file paths, making allowed_paths the entire tests tree on the one L-effort step that touches 191 files — scope-check can no longer distinguish a one-line header stamp from a rewritten suite
- [low] F-5 standard §Produkce a výjimky (green-nightly-≤24 h deploy tag with named exception) and §Mezi projekty (owner in CLAUDE.md) have no step and are not listed in Out of scope, so they read as dropped rather than deferred
- [low] F-19 the snapshot size is misstated: L20/L49c say 58 of 191 units, measurements.jsonl has 66 lines
- [low] P2-2 Step 3 AC1 and Step 4 AC3 are the same assertion; per F-12 the Step 3 copy is false where it stands
```
