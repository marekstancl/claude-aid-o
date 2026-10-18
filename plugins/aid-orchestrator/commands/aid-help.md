---
name: aid-help
description: AID help with progressive disclosure (Level 0–3)
user_invocable: true
---

Show AID documentation with progressive disclosure — a new user sees the four commands that get a project running, a power user sees every public surface.

## Usage

> **Resolve `$AID_PLUGIN_PATH` before running anything below.** Nothing sets it
> for you — not the plugin, not the workspace, not your shell. Every command
> here would otherwise fail with "file not found", and the reader is left to
> work the path out (which is how this survived unnoticed: a model usually
> does). The workspace records it, and this is the same source
> `commands/aid-run.md` §PRE-FLIGHT already uses:
>
> ```bash
> _aid_installed="$(jq -r '.plugins["aid-orchestrator@claude-aid-o"][0].version' \
>                   ~/.claude/plugins/installed_plugins.json 2>/dev/null)"
> AID_PLUGIN_PATH="$(yq -r '.plugin_path' "$(git rev-parse --show-toplevel)/.aid-o/config/plugin.yaml")"
> # The workspace PINS a version and old copies stay on disk, so "the file is
> # there" is not "the file is current": on 2026-08-24 a session ran its first
> # commands against 2.89.1 while 2.90.0 was the installed one. Compare, do not
> # assume.
> [[ -n "$_aid_installed" && "$AID_PLUGIN_PATH" != *"/$_aid_installed" ]] \
>   && AID_PLUGIN_PATH="$HOME/.claude/plugins/cache/claude-aid-o/aid-orchestrator/$_aid_installed"
> test -f "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" || echo "no plugin at $AID_PLUGIN_PATH — run /aid-init"
> ```


```
/aid-help           # show your level (auto-detected from usage history)
/aid-help <topic>   # jump to one topic (full list under "Help Topics" below)
```

## Level Detection

Auto-detect user level from workspace state:

| Condition | Level |
|-----------|-------|
| No `.aid-o/` or 0 completed tasks | Level 0: Getting Started |
| 1–4 completed tasks (Q-NNN + done runs) | Level 1: Working with Tasks |
| 5+ completed tasks | Level 2: Configuration |
| Custom gates configured OR `autonomous_mode: true` | Level 3: Power User |

Count completed tasks:
- Quick logs: count files in `.aid-o/work/quick/Q-*.md`
- Task runs: count `state: DONE` in `.aid-o/work/evidence/*/*/fsm-state.yaml`

Show all levels up to and including the detected level.

## Level 0: Getting Started (0 tasks completed)

```
AID Orchestrator — Getting Started
====================================
In this order:
  /aid-init         → create the .aid-o/ workspace. Nothing else runs without it.
  /aid-setup        → permissions, integrations, CLAUDE.md, stack scan.
  /aid-do "task"    → implement something small in < 2 min. No planning overhead.
  /aid-status       → see what is running or finished.

Start here: /aid-init, then /aid-setup, then /aid-do "your first task"
Bigger than one sitting? /aid-plan writes the plan, /aid-run executes it.
```

`/aid-setup` refuses to run before `/aid-init` — it configures a workspace that
`/aid-init` has to create first. The order above is the working order, not a
preference.

## Level 1: Working with Tasks (1–4 tasks completed)

```
Planning:
  /aid-plan                → brainstorm + write plan (auto-detect)
  /aid-plan write spec.md  → write plan from spec file
  /aid-run P<NNN>          → run the reviewed plan

Before you trust either end:
  /aid-verify-plan             → one plan reviewer, by hand (not a review round)
  /aid-verify-implementation   → adversarial review of a claimed-done result

Design:
  /aid-ui                  → UI from product type to an approved brand page
```

## Level 2: Configuration (5+ tasks completed)

```
Setup: /aid-setup → configure permissions, integrations, CLAUDE.md, stack scan
  /aid-setup permissions    → choose autonomy level (autonomous/custom)
  /aid-setup integrations   → enable/disable MCP servers
  /aid-setup claude-md      → generate project context file
  /aid-setup scan           → re-detect tech stack
  /aid-setup parallel       → how many steps of one wave run at once

Gates: edit .aid-o/config/execution.yaml → customize test/lint/build commands
Project profile: .aid-o/config/project.yaml → stack, test/lint/build commands
Permissions: .aid-o/config/permissions.yaml → autonomous_mode: true for /aid-run --auto

Tests:  /aid-help tests  → test tiers, what runs on the merge path
```

## Level 3: Power User (custom gates or autonomous mode)

```
FSM debugging:
  /aid-status <run-id>                     → shows fsm-state.yaml FSM state
  cat .aid-o/work/evidence/{id}/*/timeline.jsonl | jq .  → full event log

Emergency: /aid-stop → halt auto-mode and return control to you
```

## Help Topics

Ask for any of these with `/aid-help <topic>`:

```
/aid-help do              → /aid-do deep dive (scope detection, escalation triggers)
/aid-help run             → /aid-run deep dive (the direct run /aid-run P<NNN>, repo_roots, cancelling, 6-state FSM)
/aid-help generation      → PRE-FLIGHT: the direct run's transaction (EPICs were removed in 3.0.0)
/aid-help plan            → /aid-plan deep dive (brainstorm, write modes)
/aid-help plan-lifecycle  → plan branches, release model, verification commands
/aid-help ui              → /aid-ui: UI from product type to an approved brand page
/aid-help status          → /aid-status deep dive (overview, run detail)
/aid-help gates           → gate types, execution.yaml configuration, retry logic
/aid-help tests           → test tiers, what runs on the merge path, the nightly
/aid-help recovery        → /aid-stop, resume, escalation, PM overrides
/aid-help auto            → autonomous mode, background gates, resuming a dead run
/aid-help config          → project.yaml, execution.yaml, permissions.yaml reference
/aid-help init            → /aid-init workspace creation and upgrade
/aid-help setup           → /aid-setup deep dive (modules, presets, integrations)
/aid-help fsm             → 6-state FSM diagram, valid transitions, fsm-state.yaml format
/aid-help hooks           → harness hooks: what AID enforces mechanically, and the switches
/aid-help brainstorm      → jak brainstorming ptaní dávkuje a co řeší dva modely mezi sebou
```

### Topic: do

`/aid-do "task"` is Fast Mode — one small change, implemented and logged, with no
plan, no FSM and no evidence directory. It escalates to `/aid-plan` when the work
turns out to be bigger than Fast Mode should carry.

```
/aid-do — Fast Mode
====================================
Scope detection: estimates files + layers before implementation
  > 5 files OR 3+ layers → offers escalation to /aid-plan

Quick log: .aid-o/work/quick/Q-NNN.md (auto-increment)
Post-check: verifies actual scope after implementation, warns if exceeded
```

### Topic: run

`/aid-run P<NNN>` runs a reviewed plan **directly** (P111; the only path since
3.0.0, P114): `aid-plan-fsm.sh plan-run` seals the plan in one resumable
transaction and starts ONE run of the whole plan on `plan/<id>`. Steps commit on `plan/<id>`; the last step's
`done-advance review release <state> --direct` records the run and the close
is `plan-finalize`. A plan that changes another repository declares
`repo_roots:` in its frontmatter and works there in a worktree on
`plan/<id>-<project>` (never the live checkout); the PM merges those branches by
hand after MERGE. `plan-close --administrative` (and `epic-complete --abandon`)
end the run in the FSM and `active-runs.json`. An EPIC id, or a plan generated
the old way, is refused `epic_path_removed`: finish it on 2.118.x, or close the
plan and start a new one.

```
/aid-run — the plan's run
====================================
6-State FSM:
  READY → EXECUTE → GATES → DONE
                 ↘ ESCALATION ↗
                       ↓
                     ERROR

Flags:
  --auto    Autonomous mode (S-effort auto-fix, L-effort always escalates)
  --resume  Resume from fsm-state.yaml after crash
```

Since 2.116.0 (P110) a step buys the review its change needs: a small step
in scope with no security pattern (≤ 3 files, ≤ 120 lines) gets none, a larger
one two light reviewers (security full on a pattern, `full_when`), one round
plus a confirmation over the fix only (`second_round_when:
open_finding_and_fix`). The step's own points run after it
(`aid-plan-diff.sh --step N --plan-json`; a block may carry `timeout:` up to
1800 s); `increment-step` refuses an absent point (`step_criteria_failed`) and
lets it pass only on the PM's answered card (`--defer-criterion AC<n> --reason
… --finding-card <card>`). The EPIC review (CP3) was removed in 3.0.0. The close
measures every point in isolation (`aid-plan-diff.sh --isolated --cwd`,
`verification_env:` for a host database), reads the brief with two roles and
writes what the run and the plan cost (`plan_summary.run_cost`, `plan_cost`).

### Topic: generation

Generation is what `/aid-run P<NNN>` does before the FSM exists: `plan-run`
turns the reviewed plan into ONE run. EPIC files, the queue and task branches
were removed in 3.0.0 (P114) — an old EPIC run is finished on 2.118.x, or its
plan is closed and a new plan started.

```
PRE-FLIGHT (bash, before FSM) — aid-plan-fsm.sh plan-run P<NNN>:
  1. plan-start (plan_branch, the one run E-<nnn>-1_1 declared)
  2. generation-readiness validates the plan
  3. CP1 gate → the seal (needs closed plan review rounds and a passed
     critic check — hard, --force does not waive it) and the PM page
  4. plan.json of the whole plan (lib/aid-plan-json.sh) + contract check (D5)
  5. the worktrees of the plan's repo_roots, the manifest entry, the receipt
  6. aid-fsm.sh init … plan/<id> … --direct → fsm-state.yaml

ONE resumable transaction: rerun the same command after a crash; a run that
made no step starts again with plan-run --restart --reason.
```

### Topic: plan

`/aid-plan` brainstorms a topic or writes a plan from a spec — the mode is
auto-detected from what you pass; a reviewed plan runs with `/aid-run P<NNN>`. When a brainstorm is
about something visual, `/visual-companion` opens the browser-based mockup
companion; you can also invoke `/visual-companion` on its own as a smoke test.

```
/aid-plan — Brainstorm, Write
====================================
Two modes, auto-detected from what you pass:
  /aid-plan "topic"        → brainstorm (9 steps, interactive)
  /aid-plan write spec.md  → write a plan from a spec

Plan IDs come from the locked allocator, never a hand edit:
  aid-fsm.sh alloc plan-id     → prints the next P{NNN}

The brief comes first (2.115.0): .aid-o/plans/P{NNN}-zadani.md from
defaults/templates/zadani.md — six sections, done-when points as AC<n> with a
verification_pattern block. Check it, and check the plan carries it:
  aid-plan-lint.sh --zadani .aid-o/plans/P{NNN}-zadani.md
  aid-plan-lint.sh <plan> --only zadani
The brief is read at review (the CP1 packet), at revision (fix-check) and at
run time (amend-scope names the AC<n> a widening serves).

The independent critic (2.112.0) reads the PM's brief and the proposal at the
end of the brainstorm, and the written plan before CP1, and answers in two
levels: what to fix (the author answers every item in writing) and what the PM
might cut or add (a suggestion on the scope card, never a verdict). Its prompt
is assembled by code from the brief file (or, in a brainstorm, the interim's
`## Zadání PM` and `## Účel a co je v sázce`) — cost figures never reach it —
and its answer is refused without the two headings, with more than five items,
or unanswered. Since 2.115.0 it is MANDATORY: no review round and no run
without a passed check (--force does not waive it):
  source scripts/lib/aid-critic.sh
  aid_critic_prepare  P{NNN} --moment brainstorm|plan [--plan <path>]
  aid_critic_dispatch P{NNN} --moment brainstorm|plan    (Codex; STAND-IN → Claude)
  aid_critic_check    P{NNN} --moment brainstorm|plan [--plan <path>]
```

### Topic: plan-lifecycle

A plan owns a git worktree and a branch, and declares how it releases.
Before its run a plan goes through plan review (CP1): six reviewer
roles answer the same packet, each finding needs a command and a file:line or
it is rejected, one round by default (2.115.0) — a second when round 1 found a
blocker and its fix passed fix-check — any other only on the PM's recorded
override (`aid-review-round.sh override`). Every reviewer gets the PM's brief
(`zadani.md`) and first answers, point by point, whether the plan keeps it. `/aid-verify-plan`
runs one of those reviewers by hand, outside the rounds; `/aid-verify-implementation`
reviews a result that claims to be done. Both dispatch an independent agent in a
fresh context, so neither is grading its own homework.

Inside a run the same mechanism reviews every step (CP2) and, at the close,
the whole plan (CP7): a deterministic step check first (small, clean, in-scope diffs skip the
round; every reviewed step gets a security reviewer), then a round of
independent reviewers whose answers need a command and a file:line, merged by
fingerprint. A failed round is fixed by the step's own role and confirmed by
the next round; the FSM advances only on a closed passing round at HEAD. Fast
mode (`/aid-do`) runs the same review over the working tree, advisory.

**Release model.** A plan runs in `plan_branch` mode (its committed lifecycle
manifest, `.aid-lifecycle/manifests/<plan_id>.yaml`, key `mode`): its one run
works on the plan branch and **the plan releases once**, at the plan-final
boundary. The per-EPIC release (`legacy_epic_release_mode`) left with the EPIC
path in 3.0.0.

```
Each plan implements in its own git worktree:

  <your checkout>                     you, on your branch, your edits
  .aid-worktrees/plan-P080/           one plan, on its plan/<id> branch
  .aid-worktrees/plan-P081/           another plan, on its own branch

So you can write and start a new plan while another one implements —
with uncommitted work in your checkout, and without your HEAD moving. An edit
you make during another plan's review window no longer invalidates that review.

Plan-linked commands find the right tree themselves; you never cd. The
exception is plan-close and plan-rollback, which refuse to run from INSIDE
the worktree they are about to remove — run those from your own checkout.

See what is running:
  /aid-status                          both streams, per plan
  git worktree list                    every tree, including yours
  aid-fsm.sh active-runs list          which runs are live

If a plan's worktree is missing or broken:
  aid-plan-fsm.sh plan-state <id> --recreate-worktree --reason "<why>"
  (repairs the DIRECTORY only; if the plan/<id> branch itself is gone,
   first: git branch plan/<id> <sha from git reflog>, then the line above)
```

### Topic: ui

`/aid-ui` vede PM od typu produktu přes vzory až k postavenému a ověřenému vzhledu.
Směr vybírá PM na stránce Impeccable; bez jeho zaznamenané odpovědi se kroky 4-6
nespustí (skript `aid-ui-state.sh` je odmítne). Postup nese skill `/ui-design`,
který načítá `/aid-ui` a sám se nevolá.

Na kroku 0 nabídne čtyři volitelné části, každou s doporučením podle toho, co
projekt už má: vize a slogany, identita (logo a ikony), SEO a obrázkové návrhy
(comps přes Impeccable). Vize, identita a SEO běží uvnitř kroku 1 před vzory;
SEO kontrola se přidá ke kroku 6. Každou volbu PM (slogan, logo, seznam stránek,
kompozici) bere skript jen z odpovědi na stránce, stejně jako směr.

Od 3.5.0 má studio šest míst rozhodnutí: sdělení, logo, pohyb, struktura, vzhled
a hotový web. Na každém hodnotí dvě role na Claude Opus s pamětí: klient (majitel)
a odborník; brány zná jen kód (`critic/*.gates.yaml`) a kolo místa je
`aid-ui-quality.py round <projekt> --place <místo>` (nejvýš tři opravná kola).
Odpověď ve studiu ani zápis buildu nejdou bez přijatého verdiktu místa, na kterém
stojí. Struktura se hodnotí na živé kostře (`aid-ui-serve.sh skeleton`, port 3918).
Po opravě udělá strojovou část jeden příkaz `aid-ui-state.sh cycle <projekt>`
(pohyb, build, kontrola textů, měření, brána a stránka pro zákazníka, gate-check)
a zastaví na prvním neúspěchu.

Od 3.6.0 studio končí předávacím balíkem `docs/ui/predani.json`. Z něj
`aid-ui-package.py zadani docs/ui/predani.json --plan-id P<NNN>` (nebo `/aid-plan`
s balíkem) napíše zadání plánu nasazení. Brána běhu `check_ui_handover` má dvě
fáze: před nasazením ověří balík, web a kritické body; po zápisu
`docs/ui/nasazeni.json` (a vždy s `--launch`, bod zadání) i soubory na hostingu,
formuláře a kontrolu UI nad ostrou adresou. `aid-ui-quality.py launch` ohodnotí
ostrou adresu ve vlastní smyčce. Plán bez balíku bránu přeskočí.

### Topic: status

`/aid-status` is the one place that answers "what is happening". Its overview
is grouped by plan stream — two concurrent plans show as two streams.

```
/aid-status                                  overview: active plans and their runs
/aid-status <run-id>                         one run in detail (reads fsm-state.yaml)
```

**What to do next:** run `/aid-status` — its next line is computed by the
shipped `next-epic` recipe from real state files, so it is the answer, not a
guess to be re-derived by hand.

### Topic: gates

Gates are the quality checks between `GATES` and `DONE`. They are the table
under `gates:` in `config/execution.yaml` (written by `/aid-init`), and
`/aid-run` runs them through `scripts/aid-run-gates.sh`.

```
Quality Gates
====================================
config/execution.yaml:
  gates:
    security_scan:
      command: "npm audit --audit-level=high"
      required: true          # true blocks GATES → DONE; false is advisory
      timeout_seconds: 180    # the deadline, the only one (default 60)
      max_retries: 2          # retries inside one run (default 1)
      run_mode: background    # optional: survives a dead session (aid-job.sh)

  default_profile: standard   # profiles: ordered lists, narrowest first
  gate_profiles:
    targeted: {include: [tests_pass]}
    standard: {include: [tests_pass, security_scan]}
    full:     {include: [tests_pass, security_scan], when_paths: ["*/aid-fsm.sh"]}

Which profile runs: the last declared one whose when_paths matches a changed
path, else default_profile. A profile with no required gate is refused.
Each gate's row: status pass|fail|skip + reason (exit_<n>, job_timeout, ...).
Retries exhausted on a required gate → gate-fixer, then ESCALATION.
Choosing timeout_seconds: aid-gate-runtime-report.sh prints 2 × p95 of the
last 20 runs next to the configured value; it never writes.
```

A key the runner no longer reads stops the run before any gate starts and
names the fix: `aid-init-execution-yaml.sh upgrade <project root>` (see
`/aid-help init`).

The project's tests (2.116.0, P110): `project_tests:` (globs; `**/` = any
depth) and a gate flagged `runs_project_tests: true` whose command writes
`--evidence-file {evidence_dir}/gates/<gate>.evidence.json` (`run-all-tests.sh`
writes it; `aid-run-gates.sh record-tests --glob … --evidence-file … -- <cmd>`
wraps a whole-suite runner). A change to the tests with no such gate in the
profile fails `profile_skips_project_tests`; a flagged gate that did not run
the changed tests fails `project_tests_not_selected`.
`aid-run-gates.sh --lint-profiles <execution.yaml>` checks every profile.

### Topic: tests

Every suite carries one tier tag in its header (`# aid-tier: t0|t1|t2`).
This is about **tests**.

```
Tiers: t0 = the pulse, t1 = what blocks a merge, t2 = nightly.
The merge path runs t0 + t1; the full portfolio runs nightly and its
result shows as one line in /aid-status.
aid-test-tier-assign.sh   proposes tiers from measured durations
aid-test-tier-lint.sh     every suite has exactly one tag, no plan numbers in names
```

The test-portfolio audit (`/aid-audit-tests`, P072) was removed on 2026-09-21:
its one real run (2026-08-05) produced no decision the PM accepted.

### Removed commands

`/aid-audit` (the 0-100 health score, categories A–J) was removed in 2.112.0
(P107): it ran once in its life. What it scored is checked where the work
happens — the step review (CP2) reads every diff, the plan-final review reads
the whole plan, and `/aid-status` shows the nightly result.

### Topic: recovery

Something is stuck, wrong, or running when it should not be. `/aid-stop`
disengages autonomous mode immediately and hands control back to you. The FSM has
already written the run's position (run, completed step, state) to
`fsm-state.yaml`, so `/aid-run --resume` picks it up — `/aid-stop` itself saves
nothing. The step that was mid-flight is not checkpointed and runs again on
resume, so check what it had already done before you resume.

```
Stop an autonomous run:
  /aid-stop                     immediate, no confirmation, always completes

Pick it back up:
  /aid-run --resume             continue from fsm-state.yaml
  /aid-status <epic-id>         where it actually stopped, and why

When a precondition blocks you:
  follow its `next:` line — skills/pipeline.md §"When AID refuses" has a row per reason
```

`--force` is a PM decision, never an agent's: it is logged to the audit trail, it
never rewrites a failing result as clean, and some failure classes refuse it
outright and say so by name. ESCALATION means a person is expected — the run
waits rather than inventing a way past.

### Topic: auto

`/aid-run --auto` hands the run to an autonomous controller: S-effort failures are
auto-fixed, L-effort always escalates to you.

```
AUTO MODE, BACKGROUND GATES AND RESUME
A gate whose execution.yaml entry says run_mode: background is started as a
supervised job (aid-job.sh) instead of a plain in-line command, and the gate
runner polls that job to completion in the same invocation — so nothing is
fire-and-forget, and a run killed mid-gate re-attaches to the still-live job
next time instead of paying the whole suite twice. Before spawning, the run
writes ONE continuation pointer, .aid-o/work/evidence/<epic>/<run>/
auto_resume_required.json, and deletes it only on a clean terminal collect.

  aid-fsm.sh resume <epic-id>

claims that pointer exactly once, collects the job's terminal result, records
it as a gate-row checkpoint the next run-all assembles, and prints what it
found, what it recorded and the next action. A job still running is a
read-only status report — nothing is claimed. It never invents a result: a
missing job record, a lost job or a stale result each come back as such, with
the rerun instruction.

Run state lives in .aid-o/work/active-runs.json as auto_controller:
  active           an autonomous controller is alive and owns the run
  manual           a human drives it (the default for a non-AUTO run)
  blocked_for_pm   the run stopped at a PM-authority decision and waits for a
                   person; written by aid_ladder_escalate
                   (lib/aid-recovery-ladder.sh) when a class's recovery
                   terminus reaches escalation
  awaiting_host_resume
                   DERIVED, never stored — the pointer is still on disk and
                   nothing has signalled liveness. A dead controller cannot
                   write a flag on its way out, so consumers compute this one
                   instead; the writer rejects any attempt to store it.

  aid-fsm.sh active-runs stalled     which runs look stuck, and why
```

### Topic: config

The config files you will actually touch live under `.aid-o/config/`. `/aid-init`
creates them at workspace setup, and `/aid-setup` is what changes them afterwards. The
full list of what a fresh init produces is in `/aid-help init`; the four below are
the ones worth knowing by name.

```
Configuration Files
====================================
config/project.yaml       — project stack, commands (auto-detected by /aid-init)
config/permissions.yaml   — autonomous mode, auto-commit, auto-push
config/execution.yaml     — gate definitions (generated eagerly by /aid-init;
                            aid-fsm.sh init recreates it if it is missing)
```

`/aid-init` never overwrites an existing `execution.yaml` — a project's gate
config is its own, and an upgrade only offers to append what is missing.

### Topic: init

`/aid-init` creates the `.aid-o/` workspace, or upgrades an existing one. It is
idempotent: run it again after every plugin update. Run it before `/aid-setup`.

```
/aid-init         create or upgrade .aid-o/ (plans, tasks, config, work)

Creates: config/project.yaml, config/permissions.yaml, config/execution.yaml,
         config/plugin.yaml, config/check-severity.yaml
         and, only when Qdrant memory is detected, config/integrations.yaml
Upgrade: offers the gate_profiles block if execution.yaml predates it —
         declining runs every gate at every boundary (see gates)
Re-installs the git hooks, so run it again after upgrading the plugin.
```

### Topic: setup

`/aid-setup` is modular project configuration — run everything, or one module at
a time. It requires `/aid-init` to have run first.

```
/aid-setup — Project Configuration
====================================
  /aid-setup permissions    → choose preset: autonomous (default) or custom
  /aid-setup integrations   → detect & enable MCP servers (Qdrant, Slack, ...)
  /aid-setup claude-md      → generate CLAUDE.md with project context
  /aid-setup scan           → re-detect tech stack, update project.yaml
  /aid-setup all            → run everything (recommended for first setup)

Permission presets:
  autonomous (default): Bash(*) + all non-destructive MCPs allowed, auto_commit: true
  custom: configure each setting manually
```

### Topic: fsm

The six states a plan's run moves through. `/aid-status <epic-id>` shows where a run
currently sits. The list below is the normal path; on top of it, READY, EXECUTE, GATES
and ESCALATION can each go to the terminal `ERROR` state on an unrecoverable failure
or a PM abort.

```
6-State FSM Reference
====================================
Valid transitions:
  READY → EXECUTE         (PM or auto approve)
  EXECUTE → EXECUTE       (next step, internal)
  EXECUTE → GATES         (all steps done)
  EXECUTE → ESCALATION    (hard failure)
  GATES → DONE            (all gates pass)
  GATES → EXECUTE         (gate retry, max 2)
  GATES → ESCALATION      (retries exhausted)
  ESCALATION → EXECUTE    (fix applied, resume)
  ESCALATION → GATES      (skip gate)
  READY → ERROR           (PM abort)
  EXECUTE → ERROR         (unrecoverable failure)
  GATES → ERROR           (unrecoverable failure)
  ESCALATION → ERROR      (PM abort)

State file: .aid-o/work/evidence/{id}/{run_id}/fsm-state.yaml
Event log: .aid-o/work/evidence/{id}/{run_id}/timeline.jsonl
```

### Topic: brainstorm

Brainstorming se tě ptá na **jednom plánovaném místě**, ne na pěti. Mezi tím
zastavením a výsledkem pracují dva modely.

**To zastavení nese tři věci najednou:**

1. **jak jsem zadání pochopil** — ve dvou sekcích, `Ověřeno` (u každého tvrzení,
   kde se to ověřilo) a `Předpokládám`. Třetí sekce není. *Nezaručuje to, že v
   první sekci je pravda — nikdo ta tvrzení se zdrojem neporovnává. Nutí to
   ale každé tvrzení zařadit a uvést původ, takže nepodložené je vidět.*
2. **vizi** (teze + jak se pozná, že platí), když ji běh dluží;
3. **všechny otázky najednou**, jako dávku.

**Ptá se tě jen na pět věcí:** k čemu to je, pro koho, jaké riziko bereš, smí se
rozbít zpětná kompatibilita, a co nejde vzít zpátky. Cokoli jiného si modely
vyřeší mezi sebou - **včetně toho, na čem se neshodnou**: jejich spor o metodu
nebo tvar rozhodnou samy a do artefaktu zapíšou volbu i námitku poražené strany.
K tobě jde spor jen tehdy, když je z těch pěti druhů. „Oponent nesouhlasil" sám
o sobě není důvod utrácet tvoji pozornost, a šestý druh otázky není opatrnost,
je to starý výslech, který se vrací po jedné.

**Vyruší tě znovu jen dvakrát:** když druhý model nejede - a to nejvýš třikrát za
běh, pak už to ani nezkusí a pokračuje sám se zápisem, a když narazí na něco zásadního, co
nejde bezpečně odhadnout — a řekne, že je to výjimka a proč.

**Než se napíše plán** uvidíš, co dodá a co vědomě nedodá. Ta druhá půlka je
důležitější: rozsah se kontroluje na hranicích.

**Nezodpovězená otázka se nestává předpokladem.** Zeptá se znovu, jen na to,
co zbylo — jinak by autonomní část rozhodla zrovna to, co jsi měl rozhodnout ty.

**Co si nekupuješ:** když se oba modely shodnou na chybě, nedozvíš se to. Proto
vize zůstává na tvém schválení.

### Topic: hooks

AID runs its own code inside the harness's lifecycle — on a session start,
before a compaction, at the end of a turn, when a subagent starts. One entry
point, one registry:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-hook-verify.sh" --status   # is any of it in force here?
bash "$AID_PLUGIN_PATH/scripts/aid-hook-verify.sh" --canary   # measure it now
```

**Nothing claims hooks are running except the canary.** Both harnesses fail
silently and in opposite directions — Codex skips an unapproved hook without a
word, Claude Code runs a crashed one and carries on — so a hook file being in
place is never evidence. Until `--canary` passes, every rule that could stop a
turn is degraded to fail-open, and the degradation is written to the audit trail.

**What is wired, and how strongly** (the ecosystem scale: 1 code decides,
2 code checks the answer, 3 code delivers data into the prompt, 4 prose):

| Rule | Event | Degree | What it does |
|---|---|---|---|
| `hook_canary` | SessionStart | 4 | leaves one audit line per start, so the canary can prove a harness reached AID |
| `decision_card_complete` | Stop | 2 | refuses a turn whose card asks you to decide with no options, recommendation or reason |
| `milestone_artifact_rendered` | Stop | 2 | refuses a turn that finished a milestone — a written plan or a closed plan — without rendering your page for it; a step and a failed step owe nothing |
| `queue_continuation_notice` | Stop | 2 | sends the session that drives an autonomous plan back to work while work is left, up to a budget; a card or the spent budget ends it with one "agent is waiting" message |
| `pm_reply_marker` | UserPromptSubmit | 3 | your reply gives the budget back and re-arms the "agent is waiting" message |
| `continuity_capture` / `continuity_restore` | PreCompact / SessionStart | 3 | saves the run's bearings before a compaction and puts them back after |
| `subagent_protocol_notice` | SubagentStart | 3 | tells a role agent when its installed protocol differs from this checkout's |

**Three switches, all audited**, in order of how much they turn off:

```bash
AID_HOOKS_OFF_RULES=decision_card_complete   # one rule off, the rest keep running
AID_HOOKS_OFF=1                              # everything off — the emergency brake
# disabled: true on a row in defaults/hook-registry.yaml — permanent
```

A hook never writes into the repository: its audit trail and the canary verdict
live in `${XDG_STATE_HOME:-~/.local/state}/aid/hooks/`.

Adding a rule is a row plus a handler — never an edit to `aid-hook.sh`. See
`docs/extending-aid.md` → "Adding a harness hook rule".

## Important

- **Progressive disclosure** — show only relevant levels, don't overwhelm new users
- **Level 0 = 4 commands** — /aid-init, /aid-setup, /aid-do, /aid-status, in that order
- **All commands in help exist** — never reference deleted v1 commands
- **The index is the authority** — `defaults/help-index.yaml` lists every public
  surface; every routed one has a `### Topic:` section here that names it in prose
- **Topics are deep dives** — show when PM asks `/aid-help <topic>`
- If `$ARGUMENTS` is empty → show auto-detected level overview
- If `$ARGUMENTS` matches a topic → show that topic section only


**Last Updated:** 2026-10-17
