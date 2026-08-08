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
   state_file}`. Recipe **`plan-epics`** returns the EPIC rows of one plan;
   recipe **`planless-epics`** returns entries with no `plan_id` (Fast Mode and
   pre-plan runs). Both sort by `epic_id` — a JSON object's key order is not an
   ordering and must never be rendered as one.
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
    E-901-1_2  [EXECUTE]  run=R-A  branch=task/E-901-1_2/main  governs-main
    E-901-2_2  [READY]  run=R-B  branch=task/E-901-2_2/main
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
  E-900-1_1  [GATES]  run=R-D  branch=task/E-900-1_1/main

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
  E-900-1_1  [GATES]  run=R-D  branch=task/E-900-1_1/main

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
# recipe: plan-epics — defines plan_epics <plan_id>: that plan's EPIC runs,
# indented for a plan block, sorted by epic_id.
plan_epics() {
  local _root _map
  _root="$(aid_state_root)" || return 1
  _map="$_root/.aid-o/work/active-runs.json"
  [ -f "$_map" ] || return 0
  jq -r --arg p "${1:-}" '
    to_entries[] | select((.value.plan_id // "") == $p)
    | "    \(.key)  [\(.value.state // "?")]  run=\(.value.run_id // "?")  branch=\(.value.branch // "?")"
      + (if .value.governs_main then "  governs-main" else "" end)' \
    "$_map" 2>/dev/null | sort
}
```

```bash
# recipe: planless-epics — defines planless_epics(): EPIC runs with no plan_id
# (Fast Mode, pre-plan runs), sorted by epic_id.
planless_epics() {
  local _root _map
  _root="$(aid_state_root)" || return 1
  _map="$_root/.aid-o/work/active-runs.json"
  [ -f "$_map" ] || return 0
  jq -r '
    to_entries[] | select((.value.plan_id // "") == "")
    | "  \(.key)  [\(.value.state // "?")]  run=\(.value.run_id // "?")  branch=\(.value.branch // "?")"' \
    "$_map" 2>/dev/null | sort
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
Mode: manual            ← from fsm-state.yaml .mode
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

**Step rendering rule.** `current_step` in `fsm-state.yaml` is 0-BASED and counts COMPLETED steps, so it is never rendered to a human directly. Derive `executing_step = min(current_step + 1, total_steps)` and render that: while executing it names the step being worked on; once every step is done (`current_step == total_steps`, state GATES/DONE) it caps at `total_steps`, so the line reads `total_steps/total_steps` rather than a nonsensical `T+1 of T`. When `total_steps` is 0 (a degenerate plan) render the machine values only. The machine field itself, the `aid-fsm.sh verify-state` JSON payload, and evidence filenames stay 0-based and are frozen compatibility surfaces.


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


**Last Updated:** 2026-08-06

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
