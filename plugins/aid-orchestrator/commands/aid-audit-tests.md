---
name: aid-audit-tests
description: Test portfolio audit — inventory, safe measurement, and a plain-language recommendation
user_invocable: true
---

# `/aid-audit-tests` — Test Portfolio Audit

Deterministically inventories a project's test portfolio (Bats, package-script/CI,
and declared-gate run_units), optionally measures a bounded subset of it safely,
and ends every run with a mandatory plain-language chat recommendation.

**`STATIC MODE NEVER EXECUTES TESTS`** — `static` mode is discovery-only: static
`@test`/script/gate parsing, never a `bash -c`/test-runner invocation of any kind.

## What this command never does on its own

- Never edits, deletes, renames, or quarantines any test file.
- Never changes `execution.yaml`/gate/quarantine state.
- Never schedules or batches test execution (no scheduler exists in this plan —
  see P069, a separate, dependent follow-up).
- Never modifies `aid-select-tests.sh`.
- **Never auto-invokes itself** — this command runs only when a user (or the
  controller, on an explicit user request) types `/aid-audit-tests`. It is never
  dispatched after an EPIC, a plan, or a release, and it carries no FSM/gate/CI
  wiring of any kind (enforced: `test_audit_never_auto_invoked`,
  `defaults/enforcement-registry.yaml`).

## Invocation

### Bare `/aid-audit-tests` — ASK, never assume

**When the user types `/aid-audit-tests` with no arguments, the controller MUST
ask before running anything.** It does not silently fall back to `static`, and
it does not silently pick a budget. A full audit takes hours and a static one
answers a different question; guessing which the user meant wastes either their
afternoon or their expectations.

Ask ONE short question in the user's own language, offering the defaults
pre-filled so a bare "ano" is enough:

> Pustím **plný audit** (`--mode full`) s rozpočtem **180 minut** na celý
> projekt. Sedí to, nebo chceš něco jiného?
>
> - **plný** — najde všechno včetně toho, co smí běžet paralelně (hodiny)
> - **měřený** — změří časy, paralelismus neřeší (desítky minut)
> - **rychlý** — jen soupis testů, nic nespouští (minuty)

Then run what they confirm. `full` + 180 minutes is the recommended default
because it is the only mode that fills in the catalog's parallel column, which
is what makes the test suite fast afterwards.

Explicit arguments always win — a user who typed them has already answered.

```
/aid-audit-tests [repo|path:<path>|runner:<id>] [--mode static|measure|full]
                  [--budget-minutes N] [--max-agents N] [--repeat N]
                  [--write-plan] [--resume <audit-id>] [--allow-missing-config]
```

| Argument | Meaning |
|---|---|
| `repo` (default) | Scope: the whole project root. |
| `path:<path>` | Scope: a subdirectory only. |
| `runner:<id>` | Scope: one discovered runner family only (e.g. `runner:bats`). |
| `--mode static\|measure\|full` | `static` (default): discovery + static analysis only. `measure`: adds bounded, sequential command execution against the approved-catalog-only allowlist. `full`: adds a deeper flake/order/isolation probe. |
| `--budget-minutes N` | Wall-clock budget for `measure`/`full`. **Required for `--mode full`** — hard error, not a default. The controller supplies it from the question above rather than making the user remember it. |
| `--max-agents N` | Ceiling on concurrent read-only audit agents (independent of `dispatch.max_parallel`). |
| `--repeat N` | Repeat a measured command N times (flake-probing use). |
| `--write-plan` | Non-interactive equivalent of the natural-language "vytvoř plán oprav" continuation (see below) — for CI/scripted use. |
| `--resume <audit-id>` | Resume an interrupted audit; short-circuits to the resumable state machine before any new scan. |
| `--allow-missing-config` | Audit a project that has no `.aid-o/config/execution.yaml` on purpose. Downgrades the disposable-clone refusal below to a warning that names what will be absent. |

### Disposable-clone precondition

`.aid-o/` is gitignored, so a clone made for a disposable audit carries no
config unless someone copied it. Auditing such a clone silently drops **every
declared-command gate** — the report is confidently smaller than the project,
with nothing to show anything is missing.

The parser refuses (exit 12) when the target is plausibly a **clone of this
project** — same git origin, or its origin points at the invoking worktree —
and prints the exact `cp -r` that fixes it. The check is deliberately narrow:
auditing an unrelated or un-initialized project from inside your own AID
project is ordinary and passes silently, because a warning on every such run
is noise that teaches people to ignore the diagnostics that matter.

A config that exists but cannot be read (a broken symlink, permissions) is
exit 13, not 12 — "cannot read" and "not there" need different fixes, and
telling someone to copy a config over a file that is already there sends them
down the wrong path.

The command file documents this contract; it performs no validation itself. The
controller invokes the real, deterministic parser
(`scripts/aid-audit-tests-cli-parse.sh`) first — every malformed input (unknown
option, nonexistent project root, nonexistent scope, missing `--budget-minutes`
for `full`, `--max-agents 0`, an unrecognized `runner:<id>`) fails loudly with a
distinct exit code, never silently defaulted. The parser's JSON output includes
the resolved, canonical `project_root` — **every later step in this command
(the scanner, the dispatch manifest, the measurement runner) MUST use this
exact value**, never re-resolve or re-derive their own; this is what makes the
parser's own project-root validation load-bearing rather than advisory.

## What it does

1. Parse and validate arguments (`aid-audit-tests-cli-parse.sh`).
2. Run the Wave-0 scanner (`aid-test-inventory.sh`) to resolve `scope` and produce
   the gitignored `test-catalog.proposed.yaml` — zero LLM dispatch.
3. Dispatch bounded, read-only shard/specialist waves via the
   `test-portfolio-analyst` agent card — one dispatch per manifest entry the
   controller reads from `aid-test-audit-dispatch.sh`'s output (`{max_concurrent_
   agents, entries: [...]}`; at most `max_concurrent_agents` entries live at once
   per `batch` within a wave), writing each result to the entry's
   `artifact_path`. This command's own `audit-state.json` is the complete
   dispatch-progress record.
4. In `measure`/`full` mode, run allowlisted commands sequentially via
   `aid-job.sh` (never batched, never a second process supervisor) —
   `lib/aid-test-audit-measure.sh` (a sourced library, not an executable —
   the path here previously named a top-level script that does not exist)
   checks every command against
   `aid_test_audit_check_allowed` (Step 13) before it ever reaches `aid-job.sh`.
5. In `measure`/`full` mode, decide what owes a **cost profile** and produce it.
   Both halves are scripted, because "was that slow suite ever diagnosed?" must
   be answerable from the artifacts rather than from what the controller
   remembered to do:

   a. `aid-test-audit-profile-select.sh --measurements <jsonl> --project-root
      <root> --audit-id <id> --output <output-dir>/profile-selection.json`
      ranks the terminal measurements and names the units at or above
      `decision.profile_trigger_ms`, capped at `decision.profile_max_units`.
      Units over the trigger but past the cap are written to `deferred` with
      their measured cost — reported, never dropped.

   b. For **each** selected unit,
      `aid-test-audit-profile.sh --run-unit-id <id> --catalog <approved catalog>
      --output-dir <output-dir> --audit-id <id> --target-root <disposable clone>
      --project-root <root>`. The target root MUST be a disposable clone; the
      profiler exits 10 against the live checkout or a linked worktree. Each
      receipt lands in `<output-dir>/profiles/` bound to the audit id and to
      the sha256 of its own evidence log.

   This step is enforced, not advisory: finalization **fails** when a selected
   unit has no receipt (see step 6), so skipping it does not produce a
   quieter audit — it produces no audit.

   c. In `full` mode, assess **parallel safety**, which takes two kinds of
      evidence and never one:

      `aid-test-resource-map.sh --run-unit-id <id> --catalog <catalog>
      --project-root <root> --output <output-dir>/resource-maps/<slug>.json`
      reads each unit's source — following `source`/`.`/`load` to a recorded
      depth cap — and records every resource it touches with the `file:line`
      that justifies it. It executes nothing.

      `aid-test-parallel-pilot.sh --lane-id <id> --unit <id>… --catalog
      <catalog> --output-dir <output-dir> --target-root <disposable clone>
      --project-root <root> --workers N --repeat N` then runs a candidate
      membership serially and concurrently in a clone bound to the audited
      tree, and reports whether concurrency changed anything.

      Only `per-test`/`per-run` units are candidates, and only a pilot for a
      lane's exact membership can propose it. Everything else stays
      sequential — the direction the default has always pointed.

6. **Finalize via `aid-audit-tests-finalize.sh` — the ONE mandatory production
   entrypoint for this closing chain (Step 24, E4 release blocker).** The
   controller MUST call this script, never the individual consolidator/
   renderer/bridge functions directly:
   `aid-audit-tests-finalize.sh --audit-id <id> --wave-artifacts-dir <dir>
   --dispatch-manifest <path> --output-dir <dir> --mode <static|measure|full>
   [--inventory <path>] [--project-root <path>] [--catalog <path>]
   [--profiles-dir <dir>] [--profile-selection <path>]
   [--resource-maps-dir <dir>] [--pilots-dir <dir>] [--write-plan]`.

   All four directory arguments default to their conventional locations under
   `<output-dir>` (`profiles`, `profile-selection.json`, `resource-maps`,
   `pilots`) when those exist, so step 5's artifacts are picked up without
   being named again. What
   they buy is refusal: a receipt that fails schema validation, belongs to
   another audit, or whose evidence log no longer hashes to what the receipt
   recorded stops finalization — as does a selected unit with no receipt at
   all. The version this replaced ended its profile ingestion with
   `|| echo '[]'`, which turned every one of those into an empty action list
   indistinguishable from "nothing needed doing".

   **`--mode` is required for `--write-plan`, and `--mode full` additionally
   requires `--inventory` and `--project-root`** — the inventory is the
   denominator every coverage figure is measured against, and the project root
   is where the unresolved-fraction threshold lives. Neither is guessed: full
   mode fails at argument validation, before any output directory is created
   or any chat turn is printed, because rendering a successful-looking summary
   over an audit that then cannot decide anything is the misleading outcome
   this contract exists to remove. Passing only the pre-P072 argument set to a
   full audit silently produced no decision artifact at all.

   It chains, in order, with no way to skip a stage:
   consolidate (`aid-test-audit-consolidate.sh`, Step 14 — fails closed on
   any wave artifact missing, extra, or mismatched against the dispatch
   manifest) → render the mandatory 5-part chat summary
   (`lib/aid-test-audit-chat-summary.sh`, Step 15 — persists the durable record
   as a side effect; fails closed if that persist fails) → (with
   `--write-plan`, or on a same-conversation continuation reply) the write-
   plan bridge check (`lib/aid-test-audit-write-plan-bridge.sh`, Step 16). The
   script prints the chat text to stdout — the controller presents that
   text VERBATIM as this command's own final turn; the renderer's text is
   ordinary, deterministic, fully Bats-tested code, but the controller's
   act of presenting it as the session's actual final turn is a live,
   session-level behavior verified once at release (Step 24 Part B), never
   claimed as covered by that script's own test suite. A missing durable
   record or an incomplete wave set makes the handoff mechanically
   unreachable, not merely undocumented — verified directly:
   `test-integration-e2e-audit-pipeline.sh` (Part A) and a real fail-closed
   demonstration captured at this plan's own release (Part B).

## Chat handoff (natural-language continuation)

Every completed audit's final turn always contains: (1) a verdict
(`clean`/`needs measurement`/`remediation recommended`), (2) up to 5 evidenced
reasons — one per top finding, never fabricated/padded to reach a minimum
count (a sparse audit with 1 real finding gets exactly 1 real reason), (3) what
changed (nothing, unless a separately-approved step ran), (4) one
plain-language next action, (5) residual risk / PM-decision-needed.

**Same-conversation convention, never a global interceptor.** Immediately
following that turn, in the SAME conversation, a reply like "pokračuj" or "vytvoř
plán oprav" is recognized as authorizing the controller to invoke `/aid-plan write`
for that one audit's durable record (`audit_id`, `verdict`, `recommended_action`).
Outside that specific context — a different conversation, the same conversation
long after the recommendation, or an ambiguous reply — the controller asks for
clarification rather than guessing. This mechanism never fires from anywhere
outside an active `/aid-audit-tests` conversation, and it enforces nothing at any
FSM/gate/release boundary.

**Controller-side contract.** `/aid-plan write` is a skill the LLM controller
invokes directly (not a subprocess a shell script can call). Both `--write-plan`
(CI/scripted use — never required end-user knowledge) and a recognized
same-conversation continuation reply resolve to the **identical** validator
call: `lib/aid-test-audit-write-plan-bridge.sh`'s `aid_test_audit_write_plan_bridge_check`.
The controller (a) runs this validator, and (b) on a `{ready:true}` verdict,
invokes `/aid-plan write` itself with the validator's `brief_path` as input. The
validator itself **never invokes `/aid-plan write`** — it only checks: the
durable record exists and its verdict is `remediation recommended`;
`consolidated-findings.json`/`implementation-plan-brief.{json,md}` exist, are
schema-valid, and the brief was derived from the current findings file (not a
stale one); every cited `run_unit_id` still resolves in the current catalog. A
`clean`/`needs measurement` verdict, or a stale `run_unit_id`, returns
`{ready:false, reason:...}` and blocks the handoff — verified to block it, not
merely asserted to.

## Parallel-safety findings

`safe|constrained|exclusive|unknown` on a run unit is **consumed**, and it is the
single authority for whether that unit may run concurrently with others. Three
consumers read it, all through the same resolver
(`aid_test_catalog_provenance_effective_status`): `aid-bats-parallel-lane.sh`,
`aid-test-scheduler.sh` and `aid-select-tests.sh`. The separate text allowlist
that used to govern the pool is retired.

Promotion out of `unknown` requires TWO kinds of evidence, never one: a
resource map read from source (`aid-test-resource-map.sh`) and a pilot that ran
the exact membership serially and concurrently in a disposable clone
(`aid-test-parallel-pilot.sh`).

A recorded status is bound to the content it was verified against — the unit's
whole dependency closure, including the helpers it sources. Change that
content's resources and the status reverts to `unknown` on its own, with nobody
editing anything.

Reading a run_unit's `parallel.status`:

| Value | Meaning |
|---|---|
| `safe` | Adapter evidence shows no shared fixed ports, no shared mutable paths, and no lock usage that would conflict with a concurrent peer. |
| `constrained` | Can run concurrently, but only under a specific limit — see `parallel.exclusive_resources[]`/`max_workers` for what it actually shares (e.g. a fixed port, a lock target) and how many peers it tolerates at once. |
| `exclusive` | Must run alone — a genuine mutual-exclusion requirement was found (a fixed port, a shared mutable path, or lock usage with no safe concurrency margin). |
| `unknown` | The default absent direct, cited adapter evidence. This command **never promotes a test to `safe` optimistically** — an unexamined or ambiguous run_unit stays `unknown` rather than being guessed into a more permissive class. |

**The audit still recommends; it does not act.** It never writes
`parallel.status`, never edits `execution.yaml`, and never changes a scheduler
mode. What it produces is a decision artifact whose lanes are proposals. Acting
on them is a separate, explicit step.

## `audit_status`, and what an `incomplete` audit refuses

A full audit ends in `complete` or `incomplete`, recorded in `decision.json`.
`incomplete` **blocks** both `--write-plan` and the same-conversation "vytvoř
plán oprav" continuation: an audit that did not finish deciding cannot hand
anyone a remediation plan built on the part it skipped.

The reason is drawn from a controlled vocabulary — never free text — so a
consumer can branch on it. The ones a full audit reaches most often:

| Reason | What happened |
|---|---|
| `coverage_mismatch` | The inventory, the assignment and the disposition counts do not reconcile — typically a unit assigned to a shard that came back with no terminal disposition. |
| `duplicate_dispositions` | A unit received more than one terminal disposition. |
| `unresolved_fraction_exceeded` | More than `decision.max_unresolved_fraction` of the portfolio is unresolved. |
| `budget_exhausted` | The audit ran out of its wall-clock budget before deciding everything. |
| `empty_inventory` | The scan found no run units at all. |

The full list lives in `test-audit-decision.schema.json` (`controlled_reason`);
extending it is a deliberate schema change, which is the point.

Recovery is the same in each case: the chat summary's first section names the
smallest bounded next action, and the audit is re-run after it.

## The six-part chat handoff

Every run ends with a summary in this exact order — the decision first, the
evidence last:

1. What to do now
2. What to fix, merge, split or remove
3. What can run in parallel
4. What must remain serial
5. Test time now, and after the proposed work
6. What is not proved yet
7. Technical evidence (appendix)

Every heading renders even when its section is empty, with an explicit
statement of that: a missing heading reads as an omission, and "nothing here"
is a finding that has to be said. An `estimated` saving always renders with its
label attached, so it can never be read as a measured one.

## Reads / Writes

- Reads: the target project's real `execution.yaml`/`gate_profiles`, the tracked
  `.aid-o/config/test-catalog.yaml` (if approved), `.aid-o/config/test-audit.yaml`.
- Writes: `.aid-o/work/test-audits/<audit-id>/` (gitignored, evidence-only) —
  `inventory.json`, `test-catalog.proposed.yaml`, `audit-state.json`, per-wave
  agent artifacts, `consolidated-findings.json`, `implementation-plan-brief.{md,json}`.
- Never writes to `.aid-o/config/test-catalog.yaml` directly — that is the
  separate, explicit catalog-approval step's job.

### Closing the loop: OFFER the approval, do not make the user find it

The approval boundary stays — the catalog is an execution allowlist and a human
confirms it. What must NOT stay is the user having to know that, or having to
remember two script names to finish what the audit started.

**After a `full` audit renders its summary, the controller offers the approval
in one sentence** and, on a plain yes, runs it:

> Katalog je připravený: **174 testů, 54 z nich ověřeně paralelních**.
> Mám ho schválit, aby se podle něj testy pouštěly?

On yes, run `aid-test-catalog-approve.sh --proposed
<output-dir>/test-catalog.proposed.yaml --project-root <root>` followed by
`aid-test-catalog-confirm-mapping.sh` (read the printed hash, pass it back).
Report the result in one line.

**Name what would be lost, before asking.** If approving would revoke evidence
the current catalog holds — units the new proposal marks `unknown` that the
approved one has proven — say how many and which, because that is a real cost
and the approval script will refuse without an explicit override. Stage 1c has
already carried forward everything it safely could, so a surviving revocation
is a genuine change, not an artifact.

Only then offer the remediation plan. Two questions, in the order the user
cares about: first make the tests run right, then decide what to fix.

### What a full audit proposes (v2.71.0)

Analysts no longer stop at classifying. Where a finding recommends anything but
`keep`, it carries a **proposal**: the exact change with file:line, an effort
bucket built from counted facts (S/M/L/decision-required, with a separate
verify bucket — a delete is S to perform and L to verify, and the verify cost
is the one that decides), and a benefit that is measured, extrapolated,
estimated or **unknown** — unknown being a normal answer, never dressed up as
a number. Time benefits count only on the critical path.

The categories span both directions: remove/merge/strengthen a weak oracle,
fix a fixable parallel blocker (fixed path → temp dir), move tests off a
genuinely unfixable shared resource, `add` a missing error-path test, `rewire`
a gate that runs a unit twice or a timeout below real runtime. Destructive
proposals (remove, merge) are always decision-required and guarded — a test
born in a bugfix commit is presumptively load-bearing.

Proposals carry a stable `proposal_id`. Ones the owner has declined — listed in
`.aid-o/config/test-audit-decisions.yaml` under `declined:` — are marked and
never re-proposed. Contradicting proposals reference each other via
`conflicts_with` instead of being emitted as independent advice. The render
shows the top slice ranked by priority and evidence strength; the full set
stays in `decision.json`.

**Last Updated:** 2026-08-05
