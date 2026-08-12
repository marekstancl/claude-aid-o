---
name: aid-status
description: Show EPIC status, queue, and pipeline overview
user_invocable: true
---

Show pipeline status, EPIC details, and queue management — unified view of everything running, queued, or completed.

## Usage

```
/aid-status                                  # overview: active EPICs + queue summary
/aid-status <epic-id>                        # detailed EPIC status (reads fsm-state.yaml)
/aid-status queue                            # queue management view
/aid-status queue add <path> [--priority]    # add EPIC to queue
```

**Priority levels:** `critical` | `high` | `medium` (default) | `low`

## Flow

### `/aid-status` — Overview (default)

Read-only and **grouped by plan**: one block per active plan stream, so two
concurrent streams are visible as two streams. Every value comes from a state
file — nothing is inferred from prose (`work/active.md` is a generated
orientation index, not an input here).

All reads below are relative to the **state root**: the primary checkout,
resolved exactly as `scripts/lib/aid-roots.sh → aid_state_root` resolves it.
Read from there even when `/aid-status` is invoked inside a plan worktree — a
linked worktree has no `.aid-o` of its own.

0. **Resolve the state root** — recipe **`state-root`**: source
   `scripts/lib/aid-roots.sh` and read every path below under
   `aid_state_root`. This is what makes the overview identical from the
   primary checkout, from a subdirectory of it, and from inside a plan
   worktree (which has no `.aid-o` of its own at all).
1. **Scan plan streams** — `.aid-o/work/plan-state/*/plan-state.yaml` carries
   each stream's `plan_id`, lifecycle phase (`plan_state`) and `worktree_path`.
   Recipe **`plan-rows`**: one TSV row per plan —
   `id · phase · worktree · marker · bucket` — already in plan-id order.
   - `bucket=active` — every phase except PLAN_MERGING / CLOSED / ABORTED /
     ROLLED_BACK. These render as work.
   - `bucket=closing` — PLAN_MERGING, CLOSED, ABORTED or ROLLED_BACK lingering
     in plan-state. They render under a separate `Closing:` section, never as
     active work. (`work/active.md` counts PLAN_MERGING as still-active; the
     status surface splits it out — same data, one more bucket.)
   - `marker=missing!` — `worktree_path` is recorded but the directory is not
     on disk. `marker=unreadable` — the plan-state file did not parse.
2. **Scan EPIC runs** — `.aid-o/work/active-runs.json`, the map keyed by
   `epic_id` with `{run_id, state, branch, plan_id, governs_main, updated_at,
   state_file}` plus the two optional live-controller fields `auto_controller`
   and `resume_artifact`. Recipe **`plan-epics`** returns the EPIC rows of one
   plan; recipe **`planless-epics`** returns entries with no `plan_id` (Fast
   Mode and pre-plan runs). Both sort by `epic_id` — a JSON object's key order
   is not an ordering and must never be rendered as one. Both render every row
   through recipe **`controller-state`**, which supplies the `ctl=` column, the
   `STALLED?` marker (recipe **`stalled-runs`**) and the resume lines — see
   "The controller column" and "Stalled runs" below.
3. **Read the queue** — recipe **`queue-rows`** (which defines both
   `queue_rows`, the plan's rows, and `queue_candidate`, its next claimable
   entry) and recipe **`queue-summary`** (the `N queued, N running, N done`
   line plus the auto-pickup flag). Both go through the queue layer's OWN
   readers in
   `scripts/lib/aid-queue-write.sh` — the surface never parses `queue.yaml` a
   second time.
4. **Derive each stream's next actionable EPIC** — recipe **`next-epic`**, the
   single definition `/aid-run`'s multi-plan selection also uses. See
   "Next actionable EPIC" below for the rule.
5. **Scan quick logs** — recipe **`quick-tasks`**: the three newest
   `.aid-o/work/quick/Q-*.md` by mtime (ties broken by filename), rendered as
   id + title.
6. **Display** — recipe **`render-overview`** composes the above: plan blocks in
   plan-id order, then the unassigned-runs block, then `Closing:`, then quick
   tasks and the queue summary. No pagination: more than three streams simply
   prints more blocks.

**Example render.** This is the literal output of `render_overview` against the
two-stream fixture in `scripts/tests/bats/test-status-two-streams.bats`; that
suite compares the assembled output with this block byte-for-byte, so what you
read here is what the recipes actually produce:

```
AID Status
====================================

Plan P901 — EPIC_INTEGRATION
  worktree: .aid-worktrees/plan-P901
  EPICs:
    E-901-1_2  [EXECUTE]  run=R-A  branch=task/E-901-1_2/main  ctl=active  governs-main
    E-901-2_2  [READY]  run=R-B  branch=task/E-901-2_2/main  ctl=manual
    E-901-4_4  [EXECUTE]  run=R-F  branch=task/E-901-4_4/main  ctl=blocked_for_pm
    E-901-5_5  [GATES]  run=R-E  branch=task/E-901-5_5/main  ctl=awaiting_host_resume  STALLED?
      awaiting host resume — .aid-o/work/evidence/E-901-5_5/R-E/auto_resume_required.json is still on disk and no liveness signal is within the stall threshold. Claim it with: aid-fsm.sh resume E-901-5_5
      then run the action that artifact recorded, verbatim (nothing here runs it): bash /x/aid-run-gates.sh run-all exec.yaml E-901-5_5 R-E
      STALLED? no progress within the stall threshold — if a long foreground gate is running this is expected; consider run_mode: background. Recover with: aid-fsm.sh resume E-901-5_5
    E-901-6_6  [EXECUTE]  run=R-G  branch=task/E-901-6_6/main  ctl=active  STALLED?
      STALLED? no progress within the stall threshold — if a long foreground gate is running this is expected; consider run_mode: background. Recover with: aid-fsm.sh resume E-901-6_6
  Queue:
    E-901-3_3  [pending]  high
  next: E-901-1_2  [EXECUTE]

Plan P902 — PLAN_GATES
  worktree: .aid-worktrees/plan-P902   missing!
  EPICs:
    (none active)
  Queue:
    E-902-2_2  [pending]  low
  next: E-902-2_2  [queue:pending, 1 dep(s) unverified]

plan P904: state unreadable — run plan-state P904 --repair

Unassigned EPIC runs (no plan):
  E-900-1_1  [GATES]  run=R-D  branch=task/E-900-1_1/main  ctl=manual

Closing:
  P903 — PLAN_MERGING (worktree -)

Recent Quick Tasks:
  Q-007 — Add login button
  Q-006 — Fix README typo
  Q-005 — Older thing

Queue: 2 queued, 0 running, 1 done | Auto-pickup: active
Use /aid-status <id> for details, /aid-status queue for queue management.
```

**Plan-less projects keep today's flat shape.** When `plan_rows` returns nothing
(no `work/plan-state/` at all — Fast Mode or a pre-plan project), the plan
blocks and the `Closing:` section are omitted entirely and the overview renders
the flat `Active EPICs:` list it always did (also asserted by the suite):

```
AID Status
====================================

Active EPICs:
  E-900-1_1  [GATES]  run=R-D  branch=task/E-900-1_1/main  ctl=manual

Recent Quick Tasks:
  Q-007 — Add login button
  Q-006 — Fix README typo
  Q-005 — Older thing

Queue: 2 queued, 0 running, 1 done | Auto-pickup: active
Use /aid-status <id> for details, /aid-status queue for queue management.
```

In that shape the run list is `planless_epics` — runs that declare no `plan_id`.
A run declaring a `plan_id` whose plan has NO plan-state row cannot exist while
the state layer is healthy (plan-state is written at `plan-start`, before any of
that plan's EPICs is initialized). If a project shows plan-less streams and you
suspect an orphaned entry, the map is stale, not the surface: run
`aid-fsm.sh active-runs prune`.

**The controller column.** Every EPIC row carries `ctl=<value>` — what is known
about the controller that owns that run. Three values are STORED in
`active-runs.json` by that run's own writers (`active`, `manual`,
`blocked_for_pm`) and a fourth is DERIVED at render time and stored nowhere:

- `ctl=active` — an autonomous controller is alive and owns the run.
- `ctl=manual` — a person drives it. Also what a **legacy entry** renders: an
  entry written before these fields existed has no `auto_controller`, and the
  render maps that absence to the run's recorded mode (`auto` → `active`,
  anything else → `manual`). It is rendered, never written back: the map is
  written only by its own writers, and this surface backfills nothing.
- `ctl=blocked_for_pm` — the run stopped at a PM-authority decision.
- `ctl=awaiting_host_resume` — **derived, never stored.** A controller that has
  died cannot write its own epitaph, so this state is computed from the two
  facts it provably left behind, and BOTH must hold: the run's continuation
  artifact `auto_resume_required.json` is still on disk, and no liveness signal
  is recent enough (`aid-fsm.sh active-runs stalled`). One fact alone is not
  it — an artifact beside a live controller is simply a background gate in
  flight. Such a row prints the artifact path, the claim command
  (`aid-fsm.sh resume <epic_id>` — when that id may be rendered as a command at
  all, see below), and then the action that artifact recorded, **verbatim**, so
  what is pasted is what was recorded.

**The pointer gives a location; the file is the fact.** `resume_artifact` is a
map field like any other, and its writer validates it against nothing — so this
surface believes it only when it passes BOTH checks, and a pointer failing
either is ignored while the conventional evidence path is probed instead:

1. **Shape.** Its basename is the shared `AID_RESUME_ARTIFACT_BASENAME`
   (`scripts/lib/aid-resume-artifact.sh`, read from there rather than spelled
   again here). A file with any other name is not the continuation artifact.
2. **Containment.** It resolves (`realpath -m`) INSIDE this run's own evidence
   directory, `.aid-o/work/evidence/<epic_id>/<run_id>` — the same rule
   `lib/aid-service.sh:_aid_svc_safe_jobs_dir` applies to a registry-recorded
   `jobs_dir`. Shape alone was not containment: a correctly-named regular file
   anywhere the process could `stat` it — another run's leftovers, `/tmp`,
   outside the repository entirely — was accepted as proof, and this row then
   asserted `awaiting_host_resume` and printed that file's recorded action as a
   pasteable command.

   **And the root that containment is measured against is not the map's to
   choose.** `_aid_svc_safe_jobs_dir` is handed its evidence directory by its
   CALLER — exactly one of the two sides is untrusted, which is the whole
   reason the comparison means anything. A first attempt here assembled the
   root from `<epic_id>/<run_id>` read out of the very entry supplying the
   pointer, so both sides were attacker-chosen and a `run_id` of `../../…`
   (nothing validates that field on the write path either) simply moved the
   root onto the planted file. The root is therefore built from
   `<state_root>/.aid-o/work/evidence` — which the map cannot influence — and
   the two recorded components are admitted only after each is proved to be a
   single path segment (not empty, not `.`, not `..`, no `/`) AND the assembled
   root still canonicalizes inside that base, which also refuses a root reached
   through a symlink that leaves the tree. A component failing either test
   establishes no fact at all: the row falls back to its recorded controller
   value and claims nothing.

   **An entry with no `run_id` is one of those failures.** A single path segment
   is what each component must be, and the empty string is not one: with no
   `run_id` there is no run directory to name, and admitting the entry would
   measure containment against the whole `<epic_id>` directory instead — under
   which another run's leftovers under the same epic, the first case this
   section says is refused, would pass. Such a row claims nothing.

3. **And containment is refused outright when it cannot be computed.** `-m` is a
   GNU coreutils extension and BSD/macOS `realpath(1)` lacks it, so every
   canonicalization here yields the empty string on failure and an empty result
   is refused — the row degrades to its recorded controller value exactly as an
   unreadable basename does. It is never replaced by the un-normalized string: a
   plain prefix comparison of raw strings reproduces the escape this check
   exists to close, because the kernel resolves `..` in a path the comparison
   accepted whole. This is the refusal `_aid_svc_safe_jobs_dir` also makes when
   its own canonicalization comes back empty.

A regular file sitting at an arbitrary recorded path is not evidence that a
controller left a continuation behind, and this row must never assert a state it
cannot prove. A render therefore still never depends on a pointer — or on
`prune` — having been written.

**A printed command is only ever printed for an id that may be one.** Nothing
constrains the charset of a map key (`aid-fsm.sh init` upserts whatever it is
given), so both the claim line above and the `STALLED?` recovery line take their
permission from the shipped derivation: `active-runs stalled` renders
`resume_command` only for an id that would survive `resume`, and returns null
otherwise. When it is null this surface names no command either — the line says
the id is not usable in a command and stops. That gate covers the `verbatim`
action line too: it is the line that actually hands over something to paste, and
it is withheld with the others rather than printed beside a refusal. The
artifact's own path is still named, so the action remains one `cat` away. One
validator, and the surface never contradicts the derivation it quotes.

The `verbatim` line is printed through the same renderer `aid-fsm.sh resume`
uses: a plain command is echoed byte-for-byte, and one carrying shell
metacharacters is shown in `printf %q` form with a warning. The recorded action
is composed by unquoted interpolation upstream, and a status page is a paste
target — a printed line must not be able to do something other than what it says.

**Stalled runs are visible, and the marker is derived — never stored.** A
controller that dies mid-EXECUTE leaves its state file exactly where it was, so
nothing about the map looks wrong: that run would stay "active" forever. Recipe
**`stalled-runs`** closes that hole. An EPIC row renders a trailing `STALLED?`
plus a recovery line when `aid-fsm.sh active-runs stalled` derives it stalled —
the entry is non-terminal and nothing newer than the stall threshold (2100 s by
default, `AID_ACTIVE_RUN_STALL_SEC`) appears in either the map's `updated_at` or
the run's `timeline.jsonl`. Three consequences worth knowing:

- **Nothing is written and nothing must run first.** The verdict is computed at
  read time by the same helper the AUTO controller loop calls. A controller that
  wakes up and writes anything clears the marker by itself, and `active-runs
  prune` is not involved (its removal criteria are unchanged).
- **A long FOREGROUND gate can trip it.** Background gates emit a
  `gate_job_heartbeat` every 60 s, foreground gates emit nothing until they
  finish, so a foreground gate running past the threshold renders `STALLED?`
  while perfectly healthy. The recovery line says so; the honest fix is
  `run_mode: background` for that gate. A visible false marker beats an
  invisible dead controller.
- **An entry whose state file is gone is not stalled** — that is `prune`'s
  removal criterion, and a phantom entry must not be dressed up as a resumable
  run. This is why most rows in the published example render carry no marker:
  the fixture records runs whose state files were never created.
- **When the derivation cannot run, the row says so.** If
  `aid-fsm.sh active-runs stalled` fails or returns something that is not an
  object, the row renders `liveness?` instead of `STALLED?` and keeps the
  RECORDED `ctl=` value: with fact 2 unknown, `awaiting_host_resume` cannot be
  claimed either. A status view never fails because a derivation did, and it
  never guesses in place of one.

**Worktree column rules.**
- A relative `worktree_path` is probed against the state root; an absolute one
  is probed verbatim.
- When the probe fails, the marker is `missing!` and the **recorded path is
  printed verbatim** — including an absolute path that no longer resolves
  because the repository moved. Status reports, it never guesses a new
  location. Repair line to offer: `plan-state <id> --recreate-worktree --reason`.
- A plan with no `worktree_path` (legacy stream, started before per-plan
  worktrees) renders `worktree: -` — that is not an error.

**Unreadable plan-state.** One bad file never aborts the whole status. Its block
collapses to the single line `plan <id>: state unreadable — run plan-state <id>
--repair` and every other block still renders.

**Next actionable EPIC.** One rule, used by this surface and by `/aid-run`'s
multi-plan selection, deterministic so two agents always name the same EPIC:

1. **Live runs first.** Take the plan's entries in `active-runs.json` whose
   `state` is `READY`, `EXECUTE` or `GATES` — the states `/aid-run` can advance
   — and pick the **lowest `epic_id` in byte order**. Object key order is not
   an ordering; the sort is what makes this reproducible.
2. **Otherwise the queue candidate.** Take the first entry **in queue file
   order** that belongs to the plan and whose normalized status is `pending`
   (the legacy literal `queued` reads as `pending`) or `blocked` — exactly the
   claimability test `queue_claim_next` applies (`scripts/lib/aid-queue-write.sh`,
   `queue_claim_next`). It is rendered as a *candidate*, with its
   `depends_on` count when non-empty, because full eligibility includes a live
   `git merge-base --is-ancestor` check per dependency that only
   `queue_claim_next` performs — and that function CLAIMS (it writes `running`
   or `blocked`), so a read-only surface must not call it. The label says so:
   `[queue:pending, N dep(s) unverified]`.
3. **Otherwise** `(none)`.

## Rendering Recipe

The overview is prose-driven — there is no status script, by design. The blocks
below are this surface's executable contract: each defines one (or two closely
related) shell function(s), and the last one composes them. **Concatenating all
blocks in the order they appear here and calling `render_overview` prints the
example render above.** `scripts/tests/bats/test-status-two-streams.bats` does
exactly that — it extracts these blocks from this file by name, runs them
against fixtures and compares the assembled output with the example blocks
byte-for-byte. An instruction deleted here turns that suite red.

Preconditions: run anywhere inside the repository (the recipes resolve the
state root themselves — see `state-root` below), `yq` + `jq` on PATH, and
`$AID_PLUGIN_PATH` pointing at the installed plugin (the recipes source
`lib/aid-roots.sh`, and the queue reads source the queue layer's own library
instead of parsing `queue.yaml` a second time).

```bash
# recipe: state-root — the preamble every recipe below depends on. `.aid-o`
# lives in the PRIMARY checkout ONLY: it is gitignored, so a linked plan
# worktree never has one, and any cwd-relative read from inside a worktree
# would silently see an empty workspace and render an empty overview. Every
# read below therefore goes through lib/aid-roots.sh, which makes /aid-status
# render the SAME overview from the primary checkout, from any subdirectory of
# it, and from inside any plan worktree. Outside a git repository
# `aid_state_root` fails loudly (rc 2) — it never falls back to $PWD.
# shellcheck disable=SC1091
source "${AID_PLUGIN_PATH:?AID_PLUGIN_PATH must point at the installed plugin}/scripts/lib/aid-roots.sh"
```

```bash
# recipe: worktree-line — defines worktree_line(): pracovní kopie, které
# nikdo neuklidí (IMP-502, 2026-08-11).
#
# PROČ TO PATŘÍ SEM a ne do nějakého úklidu: AID svoji kopii uklízí samo
# (`_pfsm_teardown_worktree`) a ta část funguje. Neuklidí ale nic, co vzniklo
# mimo kanonickou cestu — ruční kopie a zmrazené CP3 stromy, o kterých v celém
# pluginu není ani zmínka. Ty jsou tedy ničí, a jediné, co s tím jde udělat
# systémově, je ukázat je tam, kam se člověk dívá.
#
# Řádek se NEVYPISUJE, když není co uklízet — status není seznam všeho, co je
# v pořádku.
worktree_line() {
  local _out _n
  _out="$(bash "${AID_PLUGIN_PATH}/scripts/aid-worktree-report.sh" --json 2>/dev/null)" || return 0
  _n="$(jq -r '.stale_count // 0' <<<"$_out" 2>/dev/null)" || return 0
  [[ "${_n:-0}" -gt 0 ]] || return 0
  printf 'Pracovní kopie: %s k uklizení — `aid-worktree-report.sh` řekne které a proč\n' "$_n"
}
```

```bash
# recipe: nightly-line — defines nightly_line(): the last nightly portfolio
# result, in ONE line, where work starts (P081 Step 8).
#
# WHY IT IS NOT A `.aid-o/` PATH, unlike every other read in this file: the
# nightly job runs in the CI runner's own checkout, where `aid_state_root`
# resolves to that checkout and `.aid-o/work/` is gitignored. An artifact
# written there could never be read from the PM's checkout — this surface
# would render nothing forever and look exactly like a healthy fresh project.
# The nightly writes to a shared HOST path instead, and this reads the same
# one.
#
# The line is DERIVED, never authored: it states what the artifact says. An
# artifact older than two days is itself a finding — a nightly that quietly
# stopped running is the failure mode a "green" memory hides. No artifact at
# all renders NOTHING: a project without a nightly is not in a red state.
nightly_line() {
  local _dir _latest _date _today _age _failed _streak _quar _colour
  _dir="${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}"
  _latest="$_dir/latest.json"
  [ -f "$_latest" ] || return 0

  _date="$(jq -r '.date // empty' "$_latest" 2>/dev/null)" || _date=""
  if [ -z "$_date" ]; then
    printf 'Nightly: result unreadable — %s\n\n' "$_latest"
    return 0
  fi

  _failed="$(jq -r '.failed | length' "$_latest" 2>/dev/null)"; : "${_failed:=0}"
  _streak="$(jq -r '[.failed[]?.streak] | max // 0' "$_latest" 2>/dev/null)"; : "${_streak:=0}"
  _quar="$(jq -r '.quarantined | length' "$_latest" 2>/dev/null)"; : "${_quar:=0}"
  [ "$_quar" -gt 0 ] 2>/dev/null && _quar=" — ${_quar} quarantined" || _quar=""

  _today="$(date -u +%s)"
  _age=$(( ( _today - $(date -u -d "$_date" +%s 2>/dev/null || echo "$_today") ) / 86400 ))
  if [ "$_age" -gt 2 ]; then
    printf 'Nightly: NOT RUN since %s (%s days) — %s\n\n' "$_date" "$_age" "$_latest"
    return 0
  fi

  if [ "$_failed" -gt 0 ]; then
    printf 'Nightly: RED (%s) — %s suite(s) failing, worst streak %s%s — %s\n\n' \
      "$_date" "$_failed" "$_streak" "$_quar" "$_dir/$_date.json"
  else
    printf 'Nightly: green (%s)%s\n\n' "$_date" "$_quar"
  fi
}
```

The line appears in four shapes and no others — a green night with its date, a
red one with the failing count and the worst streak, a nightly that stopped
running, and an artifact this cannot read:

```
Nightly: green (2026-08-10)
Nightly: green (2026-08-10) — 2 quarantined
Nightly: RED (2026-08-10) — 3 suite(s) failing, worst streak 4 — /opt/eco/data/aid-nightly/aid-orchestrator/2026-08-10.json
Nightly: NOT RUN since 2026-08-04 (6 days) — /opt/eco/data/aid-nightly/aid-orchestrator/latest.json
```

A project with no nightly artifact renders none of them, which is why the
example renders below — whose fixtures have no artifact — are unchanged.

```bash
# recipe: plan-rows — defines plan_rows(): one TSV row per plan-state file,
# columns: id, phase, worktree, marker (ok|missing!|unreadable), bucket
# (active|closing). Sorted by plan id.
plan_rows() {
  local _root _psf _dirid _row _id _rest _phase _wt _probe _mark _bucket
  _root="$(aid_state_root)" || return 1
  for _psf in "$_root"/.aid-o/work/plan-state/*/plan-state.yaml; do
    [ -f "$_psf" ] || continue
    _dirid="$(basename "$(dirname "$_psf")")"
    if ! _row="$(yq -r '[.plan_id // "?", .plan_state // "?", .worktree_path // "-"] | join("|")' "$_psf" 2>/dev/null)"; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$_dirid" "?" "-" "unreadable" "active"
      continue
    fi
    _id="${_row%%|*}"; _rest="${_row#*|}"
    _phase="${_rest%%|*}"; _wt="${_rest#*|}"
    [ "$_id" != "?" ] || _id="$_dirid"
    case "$_wt" in ""|null|"-") _wt="-" ;; esac
    _mark="ok"
    if [ "$_wt" != "-" ]; then
      # Same probe rule the whole surface uses: a relative worktree_path is
      # resolved against the STATE ROOT, never the caller's cwd.
      case "$_wt" in /*) _probe="$_wt" ;; *) _probe="$_root/$_wt" ;; esac
      [ -d "$_probe" ] || _mark="missing!"
    fi
    case "$_phase" in
      PLAN_MERGING|CLOSED|ABORTED|ROLLED_BACK) _bucket="closing" ;;
      *) _bucket="active" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$_id" "$_phase" "$_wt" "$_mark" "$_bucket"
  done | sort
}
```

```bash
# recipe: stalled-runs — defines stalled_json() and stall_hint <epic_id>: the
# STALLED? marker's single authority. The rule (non-terminal entry AND nothing
# newer than the stall threshold in either the map's `updated_at` or the run's
# timeline) is NOT re-implemented here — it lives in exactly one place,
# `scripts/aid-fsm.sh active-runs stalled`, which this surface and the AUTO
# controller loop's watchdog step both call. It is DERIVED at read time and
# stored nowhere, so a controller that wakes up and writes anything clears the
# marker by itself; nothing has to run a sweep first. A failed call renders no
# STALLED? marker at all — a status view must never fail because a derivation
# did — and the affected rows say `liveness?` instead of claiming either way.
stalled_json() {
  bash "${AID_PLUGIN_PATH:?AID_PLUGIN_PATH must point at the installed plugin}/scripts/aid-fsm.sh" \
    active-runs stalled 2>/dev/null || true
}

# The honest caveat belongs in the render, not in a footnote: a FOREGROUND gate
# emits no heartbeat, so a long one can trip this marker. That is the deliberate
# trade — a visible false STALLED? beats an invisible dead controller.
#
# stall_hint <epic_id> <indent> <id_is_renderable 0|1> — the third argument is
# the SHIPPED derivation's verdict on whether this epic id may be interpolated
# into a command at all (`resume_command` non-null in `active-runs stalled`; see
# controller_facts below). `cmd_init` puts no charset constraint on the map key
# it upserts, so a key like `E-OK; curl … | sh` interpolated raw here would be a
# printed, runnable-looking recovery line — the incident that derivation
# documents and refuses. A status page is a paste target: when the id is not
# renderable, this line names no command rather than a plausible-looking one,
# and it DEFAULTS to that (0), so a caller that forgets the argument gets the
# safe answer.
stall_hint() {
  local _epic="${1:-}" _in="${2:-      }" _ok="${3:-0}"
  local _pre='STALLED? no progress within the stall threshold — if a long foreground gate is running this is expected; consider run_mode: background.'
  if [ "$_ok" = "1" ]; then
    printf '%s%s Recover with: aid-fsm.sh resume %s\n' "$_in" "$_pre" "$_epic"
  else
    printf '%s%s This run'"'"'s id is not usable in a command; recover it by hand.\n' "$_in" "$_pre"
  fi
}
```

```bash
# recipe: controller-state — defines _safe_action(), controller_facts() and
# epic_row(): the `ctl=` column, the DERIVED awaiting_host_resume state, and the
# resume lines. Read-only from end to end: nothing here writes to the map, and
# nothing here depends on `active-runs prune` having run.
#
# _safe_action <artifact_abs> — the artifact's `safe_next_action`, rendered by
# THE shipped renderer (`_resume_render_command` in scripts/aid-fsm.sh, sourced
# in a child shell), never by a second copy of its allowlist. A plain command
# comes back VERBATIM — that is the promise this surface makes, because an
# operator pastes what is printed and a "helpful" reconstruction would be a
# command the artifact never recorded. Anything carrying shell metacharacters
# comes back in `printf %q` form (inert when pasted) with rc 1, so the caller
# can flag it: a status page prints attacker-influenceable strings (the recorded
# action is composed by unquoted interpolation upstream), and a printed line
# must not be able to do something other than what it says.
#   rc 0 = verbatim   rc 1 = quoted   rc ≥ 2 = renderer unavailable
_safe_action() {
  bash -c '
    source "$1" >/dev/null 2>&1 || exit 2
    s="$(jq -r ".safe_next_action // \"\"" "$2" 2>/dev/null || true)"
    [ -n "$s" ] || { printf "%s" "(none recorded)"; exit 0; }
    rc=0
    r="$(_resume_render_command "$s")" || rc=$?
    printf "%s" "$r"
    exit "$rc"
  ' _ "${AID_PLUGIN_PATH:?AID_PLUGIN_PATH must point at the installed plugin}/scripts/aid-fsm.sh" "${1:-}"
}

# _resume_basename — THE continuation artifact's filename, read from the shared
# vocabulary (`lib/aid-resume-artifact.sh`, where it has its single definition)
# rather than spelled a fourth time here. A private copy fails open in exactly
# the way that library's own header describes: rename the artifact and this
# surface would keep probing the old name. Read in a child shell so sourcing the
# library cannot leak names into the render. Empty = unreadable.
_resume_basename() {
  bash -c '
    source "$1" >/dev/null 2>&1 || exit 1
    printf "%s" "${AID_RESUME_ARTIFACT_BASENAME:-}"
  ' _ "${AID_PLUGIN_PATH:?AID_PLUGIN_PATH must point at the installed plugin}/scripts/lib/aid-resume-artifact.sh" 2>/dev/null
}

# _path_segment <s> — true when <s> is ONE path segment that cannot ascend:
# non-empty, not `.`, not `..`, and containing no `/`. Deliberately a structural
# test and not a charset allowlist — this surface already consumes the SHIPPED
# id verdict (`idok`) for anything that renders a command, and a second private
# allowlist would be free to drift from it. What this rules out is narrower and
# absolute: a map-supplied value that changes which DIRECTORY a path names.
_path_segment() {
  case "${1:-}" in ""|.|..|*/*) return 1 ;; esac
  return 0
}

# controller_facts — one TSV row per map entry:
#   epic · ctl · stalled(true|false|unknown) · quoted(0|1|x|-) · idok(0|1) ·
#   artifact · action
# `action` is LAST because a rendered command may legitimately contain a tab.
#
# THE DERIVATION. `awaiting_host_resume` is never stored — a dying controller
# cannot write its own epitaph — so it is computed here from the two facts the
# controller provably LEFT BEHIND, and both must hold:
#   1. the run's continuation artifact is STILL ON DISK. The map's
#      `resume_artifact` pointer supplies a LOCATION, never the fact itself, and
#      it is believed only when it actually NAMES that artifact — its basename
#      must equal the shared `AID_RESUME_ARTIFACT_BASENAME`. A pointer to
#      anything else (`update_active_run_field` validates `auto_controller`
#      against a closed vocabulary and `resume_artifact` not at all) is ignored,
#      because a regular file at an arbitrary path is not evidence that a
#      controller left a continuation behind, and a row must never assert a
#      state it cannot prove. With no usable pointer the conventional evidence
#      path is probed instead, so a render never depends on a pointer (or on a
#      prune) having been written. When the shared basename cannot be read at
#      all, fact 1 is simply not established — the surface claims nothing.
#   2. no liveness signal is recent enough — `stalled == true` from the ONE
#      shared derivation above.
# Neither fact alone renders it: an artifact beside a live controller is an
# in-flight background gate, and a stall with no artifact is a stall.
#
# When the stall derivation itself is unavailable, fact 2 is UNKNOWN: the row
# reports the recorded value with a `liveness?` marker and claims neither
# awaiting_host_resume nor STALLED?. Saying "I cannot tell" is the only honest
# third answer.
#
# MISSING FIELDS ARE RENDERED, NEVER WRITTEN. A legacy entry predating these
# fields renders `manual` unless its state file records `mode: auto` — the same
# conservative default the writer applies (`_active_runs_auto_controller`):
# claiming a live autonomous controller for a run nothing stamped AUTO is
# exactly the false claim the field exists to prevent. Nothing is backfilled;
# the map is written only by its own writers.
#
# The `idok` column is the SHIPPED derivation's verdict on the epic id itself:
# `resume_command` non-null means that derivation was willing to render
# `resume <id>` for this key, having checked it against the same charset
# `resume` enforces before it will act. This surface consumes that verdict
# instead of re-deriving it — one validator, no second allowlist free to drift —
# and prints no command line at all when it is 0.
controller_facts() {
  local _root _map _stall _bn _epic _ac _sf _run _ptr _mode _abs _rel _art _st _ctl _cmd _rc _q _idok
  local _evbase _evbrp _evd _evrp _rp
  _root="$(aid_state_root)" || return 1
  _map="$_root/.aid-o/work/active-runs.json"
  [ -f "$_map" ] || return 0
  _stall="$(stalled_json)"
  printf '%s' "$_stall" | jq -e 'type == "object"' >/dev/null 2>&1 || _stall=""
  _bn="$(_resume_basename)" || _bn=""
  # THE CONTAINMENT BASE, DERIVED FROM THE STATE ROOT ALONE — nothing the map
  # supplies contributes to it. This is the half of the containment rule that a
  # first attempt lost: the per-run root was assembled as
  # `evidence/${_epic}/${_run}` from the SAME attacker-writable map that
  # supplies the pointer being checked, so the check compared untrusted input
  # against a root the same input had chosen. A valid epic id with
  # `run_id: ../../../../../OUT2` — or a map key spelled the same way — walked
  # the root out to the planted file and the escape reopened one field over.
  # `lib/aid-service.sh:_aid_svc_safe_jobs_dir`, the rule this borrows, takes
  # its evidence dir as a CALLER-supplied argument: exactly one side is
  # untrusted, and that asymmetry is what makes the comparison mean anything.
  #
  # AND IT FAILS CLOSED WHEN IT CANNOT CANONICALIZE. `-m` is a GNU coreutils
  # extension; BSD/macOS `realpath(1)` does not have it, so "no `-m`" is a
  # DEFAULT platform, not an exotic edge. A first fix fell back to the raw
  # string (`|| printf '%s' "$_evbase"`) on both sides, which degraded the whole
  # rule to a string-prefix test and reproduced the very escape it closes: with
  # `_abs` = `<root>/.aid-o/work/evidence/E/R/../../../../../tmp/<basename>` and
  # `_evrp` = `<root>/.aid-o/work/evidence/E/R`, the prefix matched, the check
  # PASSED, and `[ -f ]` then succeeded because the KERNEL resolves `..` even
  # though the comparison did not. Every canonicalization below therefore yields
  # the empty string on failure and an empty result is REFUSED, never used:
  # `lib/aid-service.sh:_aid_svc_safe_jobs_dir` does the same (`rp` is required
  # non-empty before the recorded value is honoured), and refusing to claim
  # containment you cannot compute is the only honest answer. The consequence is
  # stated rather than hidden: on a host whose `realpath` lacks `-m`, fact 1 is
  # never established and every row degrades to its recorded controller value —
  # exactly as an unreadable basename does. A surface that cannot prove a state
  # says nothing; it does not lower the bar until it can.
  _evbase="$_root/.aid-o/work/evidence"
  _evbrp="$(realpath -m -- "$_evbase" 2>/dev/null || printf '')"
  while IFS="$(printf '\t')" read -r _epic _ac _sf _run _ptr; do
    [ -n "$_epic" ] || continue
    # A TAB is an IFS *whitespace* character, so `read` collapses a run of them
    # and an empty middle field would silently shift every later one. Absent
    # values therefore travel as the literal `-` and are decoded here.
    [ "$_ac"  != "-" ] || _ac=""
    [ "$_sf"  != "-" ] || _sf=""
    [ "$_run" != "-" ] || _run=""
    [ "$_ptr" != "-" ] || _ptr=""
    _art=""
    # THE CONTAINMENT ROOT: this run's own evidence directory, assembled from
    # the trusted base above and the two map-supplied components — but only
    # after each of those has been proved incapable of choosing a different
    # directory. Two steps, both required:
    #   1. `_epic` and `_run` must each be a SINGLE path segment (`_path_segment`),
    #      so neither can ascend out of the base or reach sideways into another
    #      run's directory. `run_id` is validated NOWHERE on the write path, and
    #      the map key carries no charset constraint either, so this surface
    #      cannot assume either is a name. `_path_segment` rejects the EMPTY
    #      string too, and that is deliberate: an entry with no `run_id` names no
    #      run directory, and treating it as "the epic directory will do" widened
    #      the root by one level — under which ANOTHER run's artifact under the
    #      same epic satisfied containment, the first case §2 above says is
    #      refused, while the conventional candidate two lines below still hard-
    #      codes `/${_run}/`. The two would then disagree. A missing `run_id`
    #      therefore establishes no fact 1, the same as any other component this
    #      surface cannot pin to one directory.
    #   2. the assembled root must still canonicalize INSIDE the canonicalized
    #      base — which additionally refuses a root reached through a symlink
    #      that leaves the tree, the one ascent step 1 cannot see. The base must
    #      itself have canonicalized (`_evbrp` non-empty): with an empty base the
    #      containment pattern would degenerate to `/*` and match every absolute
    #      path there is.
    # A row that fails any step establishes no fact 1 at all: it degrades to
    # its recorded controller value, exactly as an unreadable basename does.
    # Canonicalized once per row, `-m` so a directory that does not exist yet
    # still yields a comparable answer, and — per the base above — an empty
    # result is refused rather than replaced by the raw string.
    _evrp=""
    if [ -n "$_bn" ] && [ -n "$_evbrp" ] && _path_segment "$_epic" && _path_segment "$_run"; then
      _evd="$_evbase/$_epic/$_run"
      _evrp="$(realpath -m -- "$_evd" 2>/dev/null || printf '')"
      case "$_evrp" in "$_evbrp"/*) ;; *) _evrp="" ;; esac
    fi
    if [ -n "$_evrp" ]; then
      for _rel in "$_ptr" ".aid-o/work/evidence/${_epic}/${_run}/${_bn}"; do
        [ -n "$_rel" ] || continue
        # THE SHAPE CHECK: a pointer that does not name the continuation
        # artifact is not a pointer to one, whatever happens to sit there.
        [ "${_rel##*/}" = "$_bn" ] || continue
        case "$_rel" in /*) _abs="$_rel" ;; *) _abs="$_root/$_rel" ;; esac
        # THE CONTAINMENT CHECK: shape alone let a correctly-named file at ANY
        # location — another run's evidence, /tmp, outside the repository — be
        # accepted as proof that this run's controller left a continuation
        # behind, and its recorded action was then printed as a pasteable
        # command. Same rule as lib/aid-service.sh:_aid_svc_safe_jobs_dir,
        # INCLUDING its refusal: a canonicalization that did not happen is not a
        # containment result, so an empty `_rp` skips the candidate instead of
        # falling back to the un-normalized string (see the base above for what
        # that fallback actually let through).
        _rp="$(realpath -m -- "$_abs" 2>/dev/null || printf '')"
        [ -n "$_rp" ] || continue
        case "$_rp" in "$_evrp"/*) ;; *) continue ;; esac
        if [ -f "$_abs" ]; then _art="$_rel"; break; fi
      done
    fi
    if [ -z "$_stall" ]; then
      _st="unknown"; _idok=0
    else
      _st="$(printf '%s' "$_stall" | jq -r --arg e "$_epic" '.[$e].stalled // false' 2>/dev/null || echo false)"
      _idok="$(printf '%s' "$_stall" | jq -r --arg e "$_epic" \
        'if (.[$e].resume_command // null) == null then "0" else "1" end' 2>/dev/null || echo 0)"
    fi
    if [ -n "$_art" ] && [ "$_st" = "true" ]; then
      _ctl="awaiting_host_resume"
    elif [ -n "$_ac" ]; then
      _ctl="$_ac"
    else
      _mode=""
      case "$_sf" in "") _abs="" ;; /*) _abs="$_sf" ;; *) _abs="$_root/$_sf" ;; esac
      [ -n "$_abs" ] && [ -f "$_abs" ] && _mode="$(yq -r '.mode // ""' "$_abs" 2>/dev/null)"
      case "$_mode" in auto) _ctl="active" ;; *) _ctl="manual" ;; esac
    fi
    _cmd=""; _q="-"
    if [ "$_ctl" = "awaiting_host_resume" ]; then
      case "$_art" in /*) _abs="$_art" ;; *) _abs="$_root/$_art" ;; esac
      _rc=0; _cmd="$(_safe_action "$_abs")" || _rc=$?
      case "$_rc" in
        0) _q=0 ;;
        1) _q=1 ;;
        *) _q=x; _cmd="(unavailable — the shared renderer could not be loaded; read the artifact itself)" ;;
      esac
    fi
    # DISPLAY-ONLY HYGIENE, applied after the artifact has been read and never
    # before: the path is echoed into a terminal, so its control bytes go here.
    # TSV framing already neutralizes TAB/CR/LF (jq's `@tsv` escapes them, and a
    # key carrying either fails the lookup and degrades to `manual`); this
    # removes the rest, ESC included, so a crafted directory name cannot
    # recolour or overpaint the rendered line.
    [ -z "$_art" ] || _art="$(printf '%s' "$_art" | tr -d '[:cntrl:]')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_epic" "$_ctl" "$_st" "$_q" "${_idok:-0}" "${_art:--}" "${_cmd:--}"
  done <<EOF
$(jq -r 'to_entries[] | [.key, (.value.auto_controller // "-"), (.value.state_file // "-"),
                         (.value.run_id // "-"), (.value.resume_artifact // "-")] | @tsv' \
    "$_map" 2>/dev/null)
EOF
}

# epic_row <indent> <epic> <state> <run> <branch> <governs> <facts> — ONE
# rendered EPIC row plus the note lines that belong to it, shared by both
# listings so the two can never drift apart.
epic_row() {
  local _in="$1" _epic="$2" _state="$3" _run="$4" _branch="$5" _gm="$6" _facts="$7"
  local _line _f _ctl _st _q _idok _art _cmd
  _f="$(printf '%s\n' "$_facts" | awk -F'\t' -v e="$_epic" '$1 == e { print; exit }')"
  _ctl=""; _st=""; _q=""; _idok=""; _art=""; _cmd=""
  IFS="$(printf '\t')" read -r _ _ctl _st _q _idok _art _cmd <<EOF
$_f
EOF
  [ -n "$_ctl" ] || _ctl="manual"
  [ "$_idok" = "1" ] || _idok=0
  [ "$_art" != "-" ] || _art=""
  [ "$_cmd" != "-" ] || _cmd=""
  _line="${_in}${_epic}  [${_state}]  run=${_run}  branch=${_branch}  ctl=${_ctl}"
  [ -n "$_gm" ] && [ "$_gm" != "-" ] && _line="${_line}  ${_gm}"
  case "$_st" in
    true)    _line="${_line}  STALLED?" ;;
    unknown) _line="${_line}  liveness?" ;;
  esac
  printf '%s\n' "$_line"
  if [ "$_ctl" = "awaiting_host_resume" ]; then
    # The claim command carries the epic id, so it is offered only when the
    # SHIPPED derivation was willing to render one for that id (`idok`). An
    # unrenderable id gets the same answer that derivation gives: no command.
    #
    # THE ACTION LINE IS GATED THE SAME WAY, and this is the CP3 correction: it
    # was printed unconditionally, so the id-renderability guard did not gate
    # the one line that hands over a PASTEABLE COMMAND. An id the shipped
    # derivation refuses is an id this surface will not build a recovery flow
    # around — step 2 without step 1 is not advice, and the artifact that
    # supplied the action was located through a path component named by the
    # very id just declared unusable. The artifact's own path is still printed
    # on the line above, so nothing is hidden: read it there.
    if [ "$_idok" = "1" ]; then
      printf '%s  awaiting host resume — %s is still on disk and no liveness signal is within the stall threshold. Claim it with: aid-fsm.sh resume %s\n' "$_in" "$_art" "$_epic"
      printf '%s  then run the action that artifact recorded, verbatim (nothing here runs it): %s\n' "$_in" "$_cmd"
      [ "$_q" = "1" ] && printf '%s  WARNING: that recorded action carries shell metacharacters and is shown QUOTED — read it before running it.\n' "$_in"
    else
      printf '%s  awaiting host resume — %s is still on disk and no liveness signal is within the stall threshold. This run'"'"'s id is not usable in a command; claim it by hand.\n' "$_in" "$_art"
    fi
  fi
  [ "$_st" = "true" ] && stall_hint "$_epic" "${_in}  " "$_idok"
  return 0
}
```

```bash
# recipe: plan-epics — defines plan_epics <plan_id>: that plan's EPIC runs,
# indented for a plan block, sorted by epic_id. Every row goes through
# epic_row, so the controller column, the STALLED? marker and the resume lines
# are rendered in exactly one place.
plan_epics() {
  local _root _map _facts _epic _state _run _branch _gm
  _root="$(aid_state_root)" || return 1
  _map="$_root/.aid-o/work/active-runs.json"
  [ -f "$_map" ] || return 0
  _facts="$(controller_facts)"
  # Sorted FIRST, then annotated: a note line is emitted with its own row, so
  # it can never be sorted away from it.
  jq -r --arg p "${1:-}" '
    to_entries[] | select((.value.plan_id // "") == $p)
    | [.key, (.value.state // "?"), (.value.run_id // "?"), (.value.branch // "?"),
       (if .value.governs_main then "governs-main" else "-" end)] | @tsv' \
    "$_map" 2>/dev/null | sort | while IFS="$(printf '\t')" read -r _epic _state _run _branch _gm; do
      epic_row "    " "$_epic" "$_state" "$_run" "$_branch" "$_gm" "$_facts"
    done
}
```

```bash
# recipe: planless-epics — defines planless_epics(): EPIC runs with no plan_id
# (Fast Mode, pre-plan runs), sorted by epic_id. Same epic_row renderer as
# plan_epics — one derivation, one row shape, both lists.
planless_epics() {
  local _root _map _facts _epic _state _run _branch _gm
  _root="$(aid_state_root)" || return 1
  _map="$_root/.aid-o/work/active-runs.json"
  [ -f "$_map" ] || return 0
  _facts="$(controller_facts)"
  jq -r '
    to_entries[] | select((.value.plan_id // "") == "")
    | [.key, (.value.state // "?"), (.value.run_id // "?"), (.value.branch // "?"), "-"] | @tsv' \
    "$_map" 2>/dev/null | sort | while IFS="$(printf '\t')" read -r _epic _state _run _branch _gm; do
      epic_row "  " "$_epic" "$_state" "$_run" "$_branch" "$_gm" "$_facts"
    done
}
```

```bash
# recipe: queue-rows — defines _queue_reader(), queue_rows <plan_id> and
# queue_candidate <plan_id>. Every read goes through the queue layer's own
# library: the live queue.yaml is line-oriented and yq is the wrong tool for it
# (see that library's "FILE FORMAT" header). A plan_id of "" selects the rows
# that declare none.
_queue_reader() {
  local _root
  _root="$(aid_state_root)" || return 1
  [ -f "$_root/.aid-o/config/queue.yaml" ] || return 1
  AID_QUEUE_FILE="$_root/.aid-o/config/queue.yaml"
  AID_QUEUE_WRITE_PROJECT_ROOT="$_root"
  export AID_QUEUE_FILE AID_QUEUE_WRITE_PROJECT_ROOT
  # shellcheck disable=SC1091
  source "${AID_PLUGIN_PATH:?AID_PLUGIN_PATH must point at the installed plugin}/scripts/lib/aid-queue-write.sh"
}

queue_rows() {
  local _want="${1:-}" _id _st _pr
  _queue_reader || return 0
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    [ "$(queue_get_field "$_id" plan_id)" = "$_want" ] || continue
    _st="$(queue_get_status "$_id")"
    _pr="$(queue_get_field "$_id" priority)"
    printf '    %s  [%s]  %s\n' "$_id" "${_st:-pending}" "${_pr:--}"
  done <<EOF
$(queue_entry_ids)
EOF
}

# The claimability test of queue_claim_next (lib/aid-queue-write.sh), applied
# READ-ONLY and in the same file order: status pending/blocked/absent. The
# dependency ancestry check is deliberately NOT duplicated here — see
# "Next actionable EPIC".
queue_candidate() {
  local _want="${1:-}" _id _st _nd
  _queue_reader || return 0
  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    [ "$(queue_get_field "$_id" plan_id)" = "$_want" ] || continue
    _st="$(queue_get_status "$_id")"
    case "$_st" in pending|blocked|"") ;; *) continue ;; esac
    _nd="$(queue_get_deps "$_id" | grep -c '[^[:space:]]' || true)"
    if [ "${_nd:-0}" -gt 0 ]; then
      printf '%s  [queue:%s, %s dep(s) unverified]\n' "$_id" "${_st:-pending}" "$_nd"
    else
      printf '%s  [queue:%s]\n' "$_id" "${_st:-pending}"
    fi
    return 0
  done <<EOF
$(queue_entry_ids)
EOF
}
```

```bash
# recipe: queue-summary — defines queue_summary(): the closing status line,
# "<n> queued, <n> running, <n> done[, <n> blocked][, <n> abandoned]
#  [, <n> other] | Auto-pickup: active|paused".
#
# EVERY status in lib/aid-queue-write.sh's STATUS ENUM header is accounted for
# — a queue row must never vanish from the totals, so the buckets always sum to
# the number of entries:
#   queued    = pending, the legacy literal `queued` (normalized to pending by
#               queue_get_status), and an entry with no status line at all
#   running   = running
#   done      = merged_to_plan, released_to_main, legacy completed
#   blocked   = blocked
#   abandoned = abandoned, superseded (terminal, not delivered)
#   other     = any value outside the enum (a hand edit) — surfaced, never
#               dropped, so the row stays visible in the count
# The optional buckets print only when non-zero.
queue_summary() {
  local _id _q=0 _r=0 _d=0 _b=0 _a=0 _o=0 _pick="active" _line
  if _queue_reader; then
    while IFS= read -r _id; do
      [ -n "$_id" ] || continue
      case "$(queue_get_status "$_id")" in
        pending|"")                                _q=$((_q + 1)) ;;
        running)                                   _r=$((_r + 1)) ;;
        merged_to_plan|released_to_main|completed) _d=$((_d + 1)) ;;
        blocked)                                   _b=$((_b + 1)) ;;
        abandoned|superseded)                      _a=$((_a + 1)) ;;
        *)                                         _o=$((_o + 1)) ;;
      esac
    done <<EOF
$(queue_entry_ids)
EOF
    grep -qE '^paused:[[:space:]]*true' "$AID_QUEUE_FILE" 2>/dev/null && _pick="paused"
  fi
  _line="$(printf '%s queued, %s running, %s done' "$_q" "$_r" "$_d")"
  [ "$_b" -gt 0 ] && _line="${_line}$(printf ', %s blocked' "$_b")"
  [ "$_a" -gt 0 ] && _line="${_line}$(printf ', %s abandoned' "$_a")"
  [ "$_o" -gt 0 ] && _line="${_line}$(printf ', %s other' "$_o")"
  printf '%s | Auto-pickup: %s\n' "$_line" "$_pick"
}
```

```bash
# recipe: next-epic — defines next_epic <plan_id>: the plan's next actionable
# EPIC by the rule documented in "Next actionable EPIC" above. Live runs
# (READY/EXECUTE/GATES) win, lowest epic_id first; otherwise the queue
# candidate; otherwise "(none)".
next_epic() {
  local _p="${1:-}" _cand
  _cand="$(plan_epics "$_p" | awk '$2 == "[READY]" || $2 == "[EXECUTE]" || $2 == "[GATES]" { print $1 "  " $2; exit }')"
  if [ -z "$_cand" ]; then _cand="$(queue_candidate "$_p")"; fi
  printf '%s\n' "${_cand:-(none)}"
}
```

```bash
# recipe: quick-tasks — defines quick_tasks(): the three newest
# .aid-o/work/quick/Q-*.md by mtime (ties by filename), as "id — title", the
# title being the file's first `# ` heading.
quick_tasks() {
  local _root _f _title
  _root="$(aid_state_root)" || return 1
  [ -d "$_root/.aid-o/work/quick" ] || return 0
  find "$_root/.aid-o/work/quick" -maxdepth 1 -name 'Q-*.md' -printf '%T@\t%p\n' 2>/dev/null \
    | sort -k1,1nr -k2,2 | head -3 | cut -f2- \
    | while IFS= read -r _f; do
        _title="$(grep -m1 '^# ' "$_f" 2>/dev/null | sed 's/^#[[:space:]]*//')"
        printf '  %s — %s\n' "$(basename "$_f" .md)" "${_title:-(no title)}"
      done
}
```

```bash
# recipe: render-overview — defines render_overview(): the whole `/aid-status`
# overview, composed from the functions above. This IS the display step; the
# example render in this file is its output on the suite's two-stream fixture.
render_overview() {
  local _rows _id _phase _wt _mark _bucket _body _closing=""
  _rows="$(plan_rows)"
  printf 'AID Status\n'
  printf '====================================\n\n'
  nightly_line
  if [ -z "$_rows" ]; then
    printf 'Active EPICs:\n'
    _body="$(planless_epics)"
    printf '%s\n\n' "${_body:-  (none)}"
  else
    while IFS="$(printf '\t')" read -r _id _phase _wt _mark _bucket; do
      [ -n "$_id" ] || continue
      if [ "$_bucket" = "closing" ]; then
        _closing="${_closing}  ${_id} — ${_phase} (worktree ${_wt})
"
        continue
      fi
      if [ "$_mark" = "unreadable" ]; then
        printf 'plan %s: state unreadable — run plan-state %s --repair\n\n' "$_id" "$_id"
        continue
      fi
      if [ "$_mark" = "missing!" ]; then
        printf 'Plan %s — %s\n  worktree: %s   missing!\n' "$_id" "$_phase" "$_wt"
      else
        printf 'Plan %s — %s\n  worktree: %s\n' "$_id" "$_phase" "$_wt"
      fi
      printf '  EPICs:\n'
      _body="$(plan_epics "$_id")"
      printf '%s\n' "${_body:-    (none active)}"
      printf '  Queue:\n'
      _body="$(queue_rows "$_id")"
      printf '%s\n' "${_body:-    (none)}"
      printf '  next: %s\n\n' "$(next_epic "$_id")"
    done <<EOF
$_rows
EOF
    _body="$(planless_epics)"
    if [ -n "$_body" ]; then
      printf 'Unassigned EPIC runs (no plan):\n%s\n\n' "$_body"
    fi
    if [ -n "$_closing" ]; then
      printf 'Closing:\n%s\n' "$_closing"
    fi
  fi
  printf 'Recent Quick Tasks:\n'
  _body="$(quick_tasks)"
  printf '%s\n\n' "${_body:-  (none)}"
  printf 'Queue: %s\n' "$(queue_summary)"
  printf 'Use /aid-status <id> for details, /aid-status queue for queue management.\n'
}
```


### `/aid-status <epic-id>` — Detailed EPIC Status

1. **Find evidence:**
   - Look in `.aid-o/work/evidence/{epic_id}/`
   - Find latest run_id (most recent subdirectory)
   - Load `fsm-state.yaml` (v2 state file)
   - Load `timeline.jsonl` (last 10 entries)

2. **Display:**

```
EPIC Status: E-003-1_2 — Add Auth System
====================================
State: EXECUTE          ← from fsm-state.yaml .state
Step: 4/7               ← executing_step / total_steps (see the rule below)
Controller: manual (mode: manual)   ← ctl from active-runs.json (see the rule below), mode from fsm-state.yaml .mode
Branch: task/E-003-1_2  ← from fsm-state.yaml .branch
Gate retries: 0/2       ← gate_retries
Escalations: 1          ← escalation_count
Started: 2026-03-03T10:00Z

Recent events (last 5 from timeline.jsonl):
  10:05 step_complete step_2_backend — pass
  10:03 step_dispatch step_2_backend — dispatched
  10:01 step_complete step_1_architect — pass
  09:58 step_dispatch step_1_architect — dispatched
  09:55 fsm_init — READY

Evidence: .aid-o/work/evidence/E-003-1_2/{run_id}/
```

**Controller rendering rule.** The old `Mode:` line named only half of what a
reader needs. `Controller: <ctl> (mode: <mode>)` renders BOTH: `<ctl>` is the
run's `auto_controller` from `.aid-o/work/active-runs.json`, derived exactly as
the overview derives it (`awaiting_host_resume` when the continuation artifact
is still on disk AND no liveness signal is recent enough; the recorded value
otherwise; `manual` when the entry has no such field and the run's mode is not
`auto`), and `<mode>` is `fsm-state.yaml`'s own `.mode`, unchanged. An
`awaiting_host_resume` detail view repeats the overview's resume lines — the
artifact path, `aid-fsm.sh resume <epic_id>`, and the recorded action verbatim.
When the EPIC has no entry in the map at all, render `Controller: (no active
run entry) (mode: <mode>)` — never a value nothing recorded.

**Step rendering rule.** Humans always read `Plan Step N of T is next` (or `all T steps complete`); the `current_step` field, the `verify-state` JSON payload and evidence filenames stay 0-BASED and frozen. Authoritative definition: the Step rendering rule in skills/pipeline.md — do not restate it here.


**Status when no run started:**
```
EPIC: E-003-1_2 — Add Auth System
Status: Plan ready, not started

Run /aid-run E-003-1_2 to start execution.
```

### `/aid-status queue` — Queue Management View

1. Read `.aid-o/config/queue.yaml`
   - If not found: "No queue configured. Use `/aid-status queue add` to start."
2. Compute eligibility for each entry
3. Display:

```
EPIC Queue
====================================
  [READY]    E-015-1_2  (high)   — no dependencies
  [RUN]      E-014-1_2  (high)   — started 2h ago
  [WAITING]  E-015-2_2  (medium) — waiting on: E-015-1_2
  [BLOCKED]  E-013-1_1  (medium) — blocked by failed: E-012-1_1
  [DONE]     E-014-1_2  (high)   — completed 3h ago

Auto-pickup: Active (1 READY, 1 WAITING, 1 BLOCKED)
```

**Eligibility tags:**
- `[READY]` — eligible for pickup (no deps or all deps completed)
- `[WAITING]` — deps in progress
- `[BLOCKED]` — deps failed or missing
- `[RUN]` — currently running
- `[DONE]` — completed
- `[FAIL]` — failed

### `/aid-status queue add <path> [--priority <level>]`

1. Validate EPIC file exists and has required sections
2. Reject if duplicate (already queued or running)
3. Create `.aid-o/config/queue.yaml` if it doesn't exist (lazy-create)
4. Add entry with default priority `medium`
5. Confirm: `Added to queue: {epic_id} (priority: {level}), position {N}`

## Edge Cases

**No EPICs found:**
```
No EPICs found.

Get started:
  /aid-do "quick task"     — implement something small
  /aid-plan                — plan something bigger
```

**EPIC exists but no evidence:**
```
EPIC: {id} — {title}
Status: Not started (no evidence directory)

Run /aid-run {id} to start execution.
```

## Evidence Paths

```
.aid-o/work/evidence/{epic_id}/{run_id}/   — run evidence root
  fsm-state.yaml                                — FSM state (replaces plan_progress.json)
  timeline.jsonl                            — event log (replaces stage_log.jsonl)
.aid-o/tasks/                               — EPIC files (replaces 02-epics/)
.aid-o/config/queue.yaml                    — queue (replaces 04-engine/epic-queue.yaml)
.aid-o/work/plan-state/{plan_id}/plan-state.yaml  — per-plan phase + worktree_path
.aid-o/work/active-runs.json                — map of active EPIC runs (keyed by epic_id)
```

## Reference Files

- `skills/pipeline.md` — FSM states, evidence structure
- `scripts/aid-fsm.sh` — fsm-state.yaml format and transitions
- `scripts/lib/aid-stage-log.sh` — timeline.jsonl format

## Important

- **Read-only by default** — `/aid-status` and `/aid-status <id>` never modify files
- **Queue subcommands modify** — `add` writes to queue.yaml
- **Lazy queue creation** — `.aid-o/config/queue.yaml` created on first `queue add`
- **v2 paths only** — reads `fsm-state.yaml` (not `plan_progress.json`), `timeline.jsonl` (not `stage_log.jsonl`)
- **State root, not cwd** — every read resolves under the primary checkout (`aid_state_root`); a plan worktree has no `.aid-o` and must never be scanned as one
- **One bad file degrades one block** — an unparseable plan-state renders its own `state unreadable` line; the rest of the overview still renders
- If `$ARGUMENTS` is empty → show overview (default)


**Last Updated:** 2026-08-12

## Plan mode

A plan declares its release model in its committed lifecycle manifest
(`.aid-lifecycle/manifests/<plan_id>.yaml`, key `mode`). Under `plan_branch` an
EPIC merges into the plan branch and only the plan releases, once, at the
plan-final boundary; under `legacy_epic_release_mode` each EPIC releases as
before. New plans default to `plan_branch` when the project declares a
`gate_profiles` table, and otherwise fall back to legacy with a logged
`plan_branch_unavailable: no_gate_profiles`. Fast Mode (`/aid-do`) neither
creates nor releases a plan branch. Reinstall the Git hooks after upgrading
(`/aid-init`) so the commit-scope and pre-push guards match the new model.
