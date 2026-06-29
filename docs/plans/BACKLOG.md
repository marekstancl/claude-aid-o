# AID Orchestrator — Backlog

Project-internal backlog items. Ecosystem-shared items live in `/opt/eco/BACKLOG.md`.

Format: each item has a status (`idea` / `scoped` / `ready` / `dropped`), a one-line
summary, context, the proposed change, and open questions. Items graduate to a real
plan via `/aid-plan`.

---

## B-002 — test-semantic-review.sh hlášen jako 0/0 v run-all-tests.sh agregátoru

**Status:** idea
**Area:** `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh`
**Nalezeno:** post-merge smoke check E-054-1_1 (2026-06-29)

**Summary:** `run-all-tests.sh` reportuje `test-semantic-review` jako 0 testů (0/0), i
když přímý `bash test-semantic-review.sh` vrátí 25/25. Agregátor špatně parsuje výstup
tohoto harnessu.

**Kontext:** `test-semantic-review.sh` vypisuje `=== Results: 25 passed, 0 failed ===`
kdežto ostatní skripty (`test-protocol-validate.sh` apod.) vypisují formát, který
agregátor umí přečíst. Buď se liší regex pattern, nebo je výstupní formát
test-semantic-review mírně jiný.

**Navrhovaná změna:** Sjednotit výstupní formát `test-semantic-review.sh` se zbytkem
(nebo upravit regex v `run-all-tests.sh`) tak, aby agregátor správně zobrazoval 25/25.
S-effort fix, <30 minut.

**Open questions:** Je formát `=== Results: N passed, 0 failed ===` standard,
nebo má být `[PASS] N/N passed, 0 failed`? Raději sjednotit na ten druhý,
protože ten je konzistentní s ostatními suity.

---

## B-003 — test-plan-to-epic 2/24 pre-existing failures kazí důvěru ve full suite

**Status:** ready
**Area:** `plugins/aid-orchestrator/scripts/tests/test-plan-to-epic.sh`
**Nalezeno:** Reportováno z E-054-1_1 REOPEN iterací jako pre-existing (2026-06-29)

**Summary:** `test-plan-to-epic.sh` má 2 trvale selhávající testy:
- `remap plan phase 2 exits with code 0 -- got exit code 1`
- `self-dep plan phase 2 exits with code 0 -- got exit code 1`

Tyto dva selhávají od v2.28.x (poslední změna souboru: commit ze `c2e9549`, v2.38.0).
Kazí full `run-all-tests.sh` výsledek a snižují důvěru v CI suite jako celek —
nelze jednoduše zkontrolovat "prošlo všechno" když je tam trvalý červený výsledek.

**Navrhovaná změna:** Prošetřit, proč `remap plan phase 2` a `self-dep plan phase 2`
vracejí exit 1 místo 0. Buď:
a) opravit `aid-plan-to-epic.sh` (pokud je to skutečný bug), nebo
b) opravit testovací fixture/očekávání (pokud se sémantika legitimně změnila a
   testy nebyly updatovány), nebo
c) odebrat testy, pokud testovaný scénář byl záměrně opuštěn.

Kandidát na standalone malý EPIC. M-effort (remap/self-dep scénáře mohou být
netriviální), ale izolovaný od ostatní práce.

---

## B-001 — Autonomous validator-assisted section review

**Status:** scoped → P039 (`.aid-o/plans/P039-section-validation.md`, 2026-05-31)
**Area:** `skills/brainstorming.md` → Step 5 (Design Validation Protocol, lines ~265-276)

**Summary:** Make section-by-section brainstorming review more autonomous — the AI
self-validates each section with a second model before bringing it to the PM, so the
PM confirms a consolidated verdict instead of reading and judging raw sections.

**Current behavior:** In Step 5 the author model presents each design section one at a
time and the PM reads the full section, then approves / modifies / skips. All the
review judgment sits with the PM.

**Proposed change:** Insert a self-validation step between "write section" and "PM
approval":

1. AI writes the section.
2. AI validates it with a *different model* (independent validator subagent) — checks
   for gaps, inconsistencies, weak assumptions, missed dependencies.
3. PM receives only a consolidated message per section, in this shape:
   - **Section N is:** `<what the section says, condensed>`
   - **Validator returned:** `<validator's findings / critique>` **and recommends:** `<recommendation>`
   - **I agree / disagree** + **reason why** `<author model's stance on the validator's recommendation>`
4. The PM confirms (or overrides) this consolidated verdict — that is the only thing
   the PM approves per section.

**Why it matters:** Shifts the PM from "read everything and decide" to "review a
pre-vetted verdict and confirm" — less PM attention per section (PM attention is the
documented bottleneck, brainstorming.md principle #5), while keeping a human approval
gate on every section.

**Open questions / design constraints:**
- **Which validator model?** Cross-model (e.g. author Opus → validator Sonnet, or vice
  versa) vs. same model in a fresh adversarial context. Cross-model gives genuine
  independence; decide at design time.
- **Enforcement (AID-v3-principles.md #1 — "Detector without Enforcement is
  Decoration"):** the validator is effectively a detector. Specify the enforcement
  mechanism — does a validator "disagree" verdict block auto-advance until PM rules on
  it, or is it advisory only? Must be decided at design time, not "later".
- **Per-section vs. batch:** confirm one section at a time (current protocol) vs.
  validate-all-then-present. Per-section preserves dependency flagging (RULE 5).
- **Cost / latency:** a second model call per section adds tokens + wall-clock — worth
  it when sections are substantial, possibly skippable for trivial ones.
- **Disagreement handling:** when author and validator disagree, the PM message must
  make the conflict explicit so the PM can adjudicate, not rubber-stamp.
- **Audit trail:** capture validator output in the evidence/timeline trail per AID
  evidence conventions.

---

---

## P041 Wave 2 — deferred follow-ups (2026-06-04, after v2.28.0 shipped)

P041 audit Waves 1+2 are DONE and released as **v2.28.0** (pushed, tagged, GH release,
plugin cache refreshed). These are the conscious leftovers — see
`docs/plans/AID-audit-2026-06/STATE-session2.md` + `10-fix-plan.md` for full context.

**Big (PM-gated, not started):**
- **MEM-AUDIT** — does the memory subsystem actually get READ by agents (suspicion: written but not used)?
  Absorbs fix-plan **G1** (migrate `qdrant-brain` → `vulcan-memory`, config-driven, `[~]`) +
  **I3** un-sourced memory threshold (`[~]`) + integrations.yaml memory knobs (E154 min_score, E155
  phantom dedup/merge fields). Gates whether vulcan-memory is a viable reflection sink.
- **REFLECT-WIRE** — wire automatic post-EPIC reflection (AID-post-plan-reflection-prompt.md):
  curator slice → local reflection.md + opt-in central .md digest (integrations.yaml
  `reflection.central_digest_path`) + opt-in vulcan-memory push (pending MEM-AUDIT). Enforce via
  FSM done-advance + plan-level gate, NOT auditor. Manual prompt + PM's output file stay AS-IS.
- **SKILL-RETROFIT** — bring the 9 grandfathered skills up to the skill-writing standard (0/9 have
  the line-2 header date; 7/9 lack `## MUST Rules`; 8/9 lack `## Completeness Gate`; agent-protocol +
  pipeline have version-stamped headings). The I1 guard grandfathers them now; retrofit removes them
  from the GRANDFATHERED list in `scripts/tests/test-skill-lint.sh` one at a time.

**Small (consciously skipped/deferred during I2 deep coverage):**
- **E171** — parallel-group file-conflict serialization guard. Moot while `orchestration.yaml
  max_parallel: 1` (parallelism off); prerequisite to re-enabling parallel dispatch (Agent SDK migration).
- **~7 low-value doc GAPs** — script guards that work but aren't pre-documented in LLM-facing
  instructions: E91 (silent malformed-row drop), E106 (atomic write), E107 (detached-HEAD guard),
  E108 (filename truncation), E113 (git/jq preflight), E124 (yq-injection escaping), E126 (yq/write
  guards). Optional one-paragraph addendum in pipeline.md §2; low value.
- **execution.yaml `config` non-role** — the `content_quality.auto_accept_when` list references a
  role `config` that exists in no role enum; the auto_accept/review_required role lists are also
  partial (omit domain/observability/qa/e2e). Latent; needs intent before fixing.

## CI / test-suite follow-ups (2026-06-04, after v2.28.1 shipped)

Surfaced while fixing the red CI build (red on every push since 2026-05-31). v2.28.1 fixed the
`transition --force` crash + wired bats into CI + repaired the 4 stale suites + added one red/green
precondition test. Remaining, deferred:

- **PRECOND-COVERAGE** — deeper precondition-layer tests (the anti-AID-005 gates_report
  `_generated_by` check, CP3 verifier-output checks). v2.28.1 added only the cheap READY→EXECUTE
  plan.json red/green pair. The heavier EXECUTE→GATES / GATES→DONE green paths need real fixtures
  (gates_report.json with `_generated_by`, both CP3 verifier-output md files, grandfather handling).
  Both review verifiers flagged that without these the gates pojistka could be weakened unnoticed.
- **run-all-tests counter off-by-one** — `run-all-tests.sh` reports `Tests: 181/180 passed` (passed >
  total). Cosmetic accounting bug in the bats TAP skip/plan handling (`ok … # skip` is first matched
  as a plain `ok`, and one suite's plan line double-counts). `0 failed` is correct; only the tally is
  off. Fix the parser, don't trust the headline count.
- **GitHub Actions Node 20 → 24** — `actions/checkout@v4` + `actions/setup-node@v4` run on Node 20,
  which GitHub force-migrates to Node 24 on 2026-06-16 (~12 days out) and removes 2026-09-16. Bump to
  the @v5 actions (or pin FORCE_JAVASCRIPT_ACTIONS_TO_NODE24) before then. Currently warnings only.
