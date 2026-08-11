# P081 — what the pilot taught the standard

Binding source: `/ecosystem/specs/test-standard`
(`/opt/eco/docs/docs/ecosystem/specs/test-standard.md`, published 2026-08-10),
which names AID as the pilot and says the pilot's reality feeds back into the
document **before** WAN → ACTA → Sousto → AI-Agenti → VULCAN adopt it.

This file is that feedback. It is a record of what happened, not an argument
that the pilot went well.

---

## 1. The number the pilot exists to move

| | Merge path runs | Measured |
|---|---|---|
| Before | the whole portfolio (`gate:bats_all` globbed the bats tree; `gate:shell_pipeline_smoke` ran `run-all-tests.sh`; `gate:bats_boundary` carried a 7200 s ceiling) | **24 542 s — 6 h 49 min** (202 suites, 4021 tests, eco-dev, 2026-08-10/11) |
| After | `gate:bats_all` = `--tier t0` then `--tier t1` | **793 s — 13 min 14 s** (41 suites, 640 tests, both green) |

Honesty note on "before": the old merge path had **never completed a measured
run**. `gate:bats_all` had two censored samples at its 600 s cap and null
percentiles; `gate:shell_pipeline_smoke`'s only non-censored samples date from
2026-07-15 at a since-changed cap. The one honest whole-portfolio figure in the
tree is P079's 12 200 s (3 h 23 min) measurement on `102a5f3`, which is what the
"before" column quotes. The "after" column is a sum of this pilot's own
per-suite measurements, on the host and date recorded in
`docs/plans/P081-tier-assignment.md`.

## 2. Per-tier counts

| Tier | Suites | Total | Budget | Within budget |
|---|---|---|---|---|
| T0 | 27 | 117 894 ms summed / **172 989 ms wall** | 2 min | summed yes, wall NO — see §4G |
| T1 | 14 | 559 009 ms summed / **620 681 ms wall** | 10 min | summed yes, wall marginal |
| T2 | 161 | 24 447 934 ms (6 h 47 min) | none | — |

Demotions forced by the aggregate budgets, each with its reason, are listed in
the assignment artifact. The budgets are ENFORCED, not checked: while a tier
overflows, `aid-test-tier-assign.sh` demotes its most expensive member. A tool
that only warned would be tolerating the overflow the standard forbids.

## 3. Every standard rule: implemented, amended or deferred

| Rule | Status | Note |
|---|---|---|
| Three tiers with the 2 s / 30 s per-case thresholds | implemented | Header tag `# aid-tier:`, not directories — see §4. |
| Whole-tier budgets (T0 ≤ 2 min, T1 ≤ 10 min) | implemented | Enforced by demotion, not by warning. |
| Tier from measured cost and scope, never importance | implemented | `aid-test-tier-assign.sh`; an unresolvable subject is t2 at any cost. |
| The full suite runs nightly and reports itself | implemented | `.github/workflows/nightly-tests.yml`, 02:40 UTC, AID's own hour. |
| Red reported once, then counted | implemented | Streak counting; a green night sends nothing. |
| A second surface that survives a missed message | implemented | One line in `/aid-status` and at `/aid-plan` orientation. |
| Flaky quarantine with an owner and a deadline | implemented | `aid-test-quarantine.sh`; 14 days ownerless escalates. |
| The selector's honesty check | implemented | Plus a third class the standard does not name — see §5. |
| Budget in: a new test declares its tier | implemented | Generation refuses; existing suites are exempt by design. |
| Review's second question | implemented | CP2 and CP3, with the "name the covering test" guard. |
| Reaper, monthly, no quota | implemented **degraded** | Three of four inputs exist; failure age has no source yet — see §6. |
| Naming rule 2: no plan/EPIC/task number in a filename | implemented | Six suites renamed; allowlist emptied. |
| Naming rule 1: the name states the subject | **deferred** | Needs a subject registry the tier work's scope column will produce. |
| Naming rule 4: one suite = one subject, split at ~500 lines | **deferred** | Same reason; enforcing it on 191 files at once is the churn the plan exists to avoid. |
| Naming rule 5: mandatory header stating what the suite proves | **deferred** | Same. Every suite this plan wrote carries one anyway. |
| Deployment rules (green-nightly-≤24 h tag) | **deferred** | AID is not deployed. Revisit when it is. |
| Cross-project ownership | **deferred, anchored** | Recorded as a convention so the successor has somewhere to start; meaningless until a second project adopts. |

## 4. Amendments the standard should take

**A. Say that the tier mechanism is a decision with a blast radius, and make
the project measure it before choosing.** The standard implies directories.
Here directories would have moved ≈420 literal path references — 201
enforcement-registry `test:` fields with line anchors, ~468 catalog fields whose
ids are join keys for the ledger and receipts, every CI job and gate command.
A header tag broke none of them. WAN and ACTA should each run the count before
choosing, not inherit AID's answer.

**B. Drop the suggestion that a suite's subject can be derived from its name.**
Measured here: 119 of 191 suites (62 %) name a concept, not a file. A
name-derived convention cannot replace an explicit mapping, and the standard
should say the mapping stays.

**C. Add `mapped_but_thin` to the honesty check's vocabulary.** The standard
describes a selector gap as "the selector picked nothing". The dangerous case is
the other one: the selector picked SOMETHING, exited 0, and the suite that
actually failed was not among them. For a path the mapping claims, the
escalation path is structurally unreachable, so a thin mapping fails silently
and confidently. Two more distinctions earned their place: an escalating
selector exit COUNTS AS SELECTION (the merge really did run more), and a
cross-cutting suite no path could select is `unmappable`, not a gap.

**D. Say where the nightly artifact lives, and why it is not project state.**
The obvious place — the project's own workspace directory — is unreachable: a
CI job runs in its own checkout, and that directory is gitignored, so the
standard's mandatory second surface would render nothing forever and look
exactly like a healthy fresh project. The artifact belongs on a shared host
path. This is the kind of mistake every adopting project would make once.

The standard should also make the ASSUMPTION explicit, because AID's own
solution only works by luck of topology: the self-hosted runner and the PM's
checkout are the same host (`eco-dev`). A host path is not a transport —
uploading the file as a CI artifact does not put it on anyone's machine. A
project whose runner lives elsewhere needs a shared mount or a fetch step, and
must be told so rather than discovering a permanently blank status line.

**E. Name the degraded-input rule.** A tool assembling a list from four signals
must say which signal it did not have, rather than proposing from three while
implying four. See §6.

**F. State the "unmeasured is never a tier" rule explicitly.** It is implied but
not written. A suite with no measurement, or whose measurement was cut short,
must be reported separately and the assignment must exit non-zero, or a partial
table gets read as a complete one.

**G. Say whether a tier budget is SUMMED SUITE COST or WALL CLOCK.** This one
was measured, not reasoned about, and the two differ enough to matter:

| Tier | Summed suite cost | Wall clock of the real gate command | Budget |
|---|---|---|---|
| T0 | 117 894 ms (1 min 58 s) | **172 989 ms (2 min 53 s)** | 2 min |
| T1 | 559 009 ms (9 min 19 s) | **620 681 ms (10 min 21 s)** | 10 min |

The gap is the runner's own per-suite overhead — process start, discovery, the
tier scan, result parsing — measured here at roughly 2 s per suite. Enforced on
summed cost, as implemented, T0 fits its budget. Enforced on what a developer
actually waits for, it does not: 2 min 53 s against a 2 min budget.

The budget exists to bound waiting, so the honest reading is wall clock, and
the standard should say so — and then an assigner has to model the per-suite
overhead rather than sum durations. This pilot did NOT re-tier for it: doing so
after the stamping would have invalidated the measurement the tiers came from,
and 13 min 14 s against 6 h 49 min is not a result worth risking to save 53 s.
It is recorded here as the first thing the next adopter should get right.

## 4b. What the measurement run found on its own

The point of running the whole portfolio once, honestly, is that it tells you
things nobody was looking for. It found four:

**Two suites that had been red on `main`, both orphaned by earlier removals.**
`test-integration-e2e-audit-pipeline` still expected the two chat sections P078
deleted with the parallelism line, and `test-integration-self-host-audit`
asserted a `bats_all` command shape this plan replaces. Both repaired here.

**Six of this plan's own new scripts committed 0644.** The repo's own
`REAL REPO: every top-level script is committed executable` guard caught it. An
installed plugin keeps the committed mode, so invoking any of them the way the
docs write them — no `bash` prefix — would have exited 126 at a consumer.

**One of this plan's own tests was vacuous.** `test-tier-gate-routing` read
`.profiles.<name>.include[]`; the live config's key is `gate_profiles:`. `yq`
resolves a missing path to nothing with exit 0, so three of its seven cases
asserted over an EMPTY list and passed. Written, note, by the plan that ships
the vacuous-green reaper. The standard should say plainly that a suite reading
a config path must assert the path resolved — this is not a rare mistake.

**A pre-existing failure NOT caused by this plan and NOT fixed by it.**
`test-aid-plan-release-boundary.bats` case 107 — *"AC4: a task branch whose
ACTUAL base does not match its RECORDED epic_base_commit (stale) is rejected —
no manifest mutation"* — expects `epic-start` to exit non-zero and it exits 0.
`aid-plan-fsm.sh` is untouched by this plan (`git diff db07c8a..HEAD` over that
file is empty), so this is a real gap in the plan-boundary lineage check that
predates the tier work. It is left for its own plan, deliberately: diagnosing
someone else's subsystem from a red assertion is how a tier migration turns
into a two-day detour.

Consequence to state plainly: **the first nightly will be red on that suite**,
with a streak that grows until it is fixed. That is the mechanism working, not
a defect in it — the failure existed all along inside a delegated CI job nobody
was reading, and the nightly is what makes it impossible to keep ignoring.

## 5. What the pilot could not do

- **The reaper's failure-age input does not exist yet.** `git log --follow`
  gives CHANGE age, not failure age, and no per-suite failure history existed
  before this plan's nightly journal. The tool names the input as unavailable.
  It fills in as nightlies accumulate.
- **`CLAUDE.md` is untracked in this repository**, so the `## Conventions`
  section the plan called for could not land on the branch. The block is in §7
  below, ready to paste. This is a PM action, not a code change.
- **The `workflow_dispatch` proof is owed.** The nightly's transport is proved
  end to end in `test-nightly-reminder.bats` case 8 — the REAL reporter writes
  the artifact and the REAL `/aid-status` recipe reads it — but a real CI run
  can only happen after this branch is on `main`. See §8.

## 6. The honest state of each input

| Input | Source | State |
|---|---|---|
| vacuous green | `aid-test-content-scan.sh` → `weak_oracle` | live |
| duplication | `aid-test-content-scan.sh` → `duplicate_test_cases` | live |
| cost | `.aid-o/work/test-durations.jsonl` | live from this plan |
| failure age | nightly artifacts | **empty until nightlies accumulate** |

## 7. PM action — the `## Conventions` block for `CLAUDE.md`

`CLAUDE.md` is untracked in this repo (`git ls-files` lists no `CLAUDE.md`), so
this cannot be delivered by a merge. Paste it above `## MCP Tools (G-020)`:

```markdown
## Conventions

### Test tiers (P081 — AID is the ecosystem pilot)

Binding source: `/ecosystem/specs/test-standard`
(`/opt/eco/docs/docs/ecosystem/specs/test-standard.md`).

Every test suite declares its tier in its leading comment block, once:

    #!/usr/bin/env bats
    # aid-tier: t1

| Tier | Cost per case | Whole-tier budget | When it runs |
|------|---------------|-------------------|--------------|
| `t0` | under 2 s     | under 2 min       | merge path (the pulse) |
| `t1` | under 30 s    | under 10 min      | merge path — this is what blocks a merge |
| `t2` | more, **or cross-component at any cost** | none | nightly, 02:40 UTC |

Tier follows measured cost and scope — never importance, and never a wish to
avoid blocking. `aid-test-tier-assign.sh` proposes from measurements and
enforces the aggregate budgets by demoting; `aid-test-tier-lint.sh` enforces
that every suite carries exactly one tag, that no filename carries a plan
number, and that no tier is cheaper than its newest measurement supports.

A tag and not a `tests/t0|t1|t2/` directory: directories were costed at ≈420
literal path references (registry `test:` fields, catalog join keys, CI jobs,
gate commands). Re-open only with a plan that counts again.

A suite filename states its subject, never the plan that produced it.
Provenance goes in the header. `scripts/tests/tier-lint-allowlist.txt` holds
sanctioned exceptions and is currently empty.

The merge path is T0 + T1. The full portfolio runs nightly
(`.github/workflows/nightly-tests.yml`), writes
`/opt/eco/data/aid-nightly/aid-orchestrator/<date>.json`, reports red once with
a streak, and shows one line in `/aid-status`.

Cross-project ownership (from the standard, anchored here for the successor):
the project that owns the code owns its tests and its nightly hour. A
cross-project suite belongs to the project whose behaviour it asserts, not to
whoever wrote it.
```

## 8. Owed after merge

1. `.aid-o/config/test-catalog.yaml` `run_unit_id`s for the six renamed suites
   are updated on this branch; confirm no other workspace copy still names the
   old paths.
2. Trigger one `workflow_dispatch` run of `nightly-tests.yml` and confirm the
   artifact it writes is rendered by `/aid-status` from the PM's checkout. This
   is the one acceptance criterion no local test can discharge.
3. Feed §4 into `/ecosystem/specs/test-standard` before WAN adopts it.

**Last Updated:** 2026-08-10
