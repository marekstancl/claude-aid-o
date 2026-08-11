# Backlog verification — block 1 (IMP-280, 281, 470, 484, 485, 486, 487, 488)

Repo `/opt/eco/projects/aid-orchestrator`, branch `main`, HEAD `3da7331` (v2.83.1), 2026-08-11.
Every verdict below rests on a file I opened myself; paths are relative to the repo root unless
absolute. No repo mutation was made.

---

## IMP-280
verdict: REAL
evidence:
- `plugins/aid-orchestrator/reference/P068-plan-branch-dogfood-report.md:398-431` — the incident and
  the requested guard ("compare `git rev-parse --git-common-dir` … refuse or require a namespaced
  target ref"). This is prose in a report, nothing executable.
- Grepped every `--git-common-dir` call site in the plugin: `scripts/aid-plan-fsm.sh:249` and
  `:1302`, `scripts/lib/aid-roots.sh:82`, `scripts/lib/aid-cache-preflight.sh:178`,
  `scripts/aid-run-gates.sh:181`, `scripts/aid-release.sh:907`, `scripts/aid-test-audit-profile.sh:88`.
  Every one uses the common dir to *resolve a state root / exclude file / dogfood-cache comparison*.
  None compares it against a second checkout, and none refuses anything on a match.
- `scripts/lib/aid-cache-preflight.sh:240-290` is the only place that knows the word "dogfood", and
  it means "this repo ships the running plugin" (version/tree-hash skew), not "this run is a test run".
what_is_true: The preflight IMP-280 asks for does not exist anywhere in the plugin. A dogfood run
started in a linked worktree still shares `refs/heads/main` with the source repository and can still
advance the real mainline exactly as it did on 2026-07-27. One important complication the entry does
not mention: since P074 the plugin runs its OWN plans in linked worktrees (`.aid-worktrees/plan-P080`
exists right now) and `plan-merge-to-main` from such a worktree moves the real `main` **by design**
(`aid-plan-fsm.sh:206-256` documents the common-dir collapse and its deliberate dogfood escape). So a
blanket "refuse when the common dir matches" would break normal plan-worktree operation. The
distinguishing fact — "this run is a test of the tool, not real work" — is recorded nowhere machine
readable today.
impact: Whoever runs the next dogfood. It shows up the way it showed up last time: silently, only
discovered afterwards, needing an archive branch plus a compare-and-swap `update-ref` to restore
`main`. Nothing warns during the run.
fix_sketch: Give a dogfood run an explicit marker (flag or env recorded in the lifecycle manifest) and
have `aid-plan-fsm.sh` refuse any ref write to a target branch whose common dir matches the source
repo's unless the target ref is namespaced — ordinary plan worktrees carry no marker and are unaffected.
effort: M

---

## IMP-281
verdict: REAL
evidence:
- `/opt/eco/projects/wan/.aid-o/config/execution.yaml:302-305` — verbatim:
  `docs_updated:` / `command: "true < /dev/null"` / `required: false` / `max_retries: 0`. The gate
  still exists in that shape today, and it is listed in the profile include[] at `:25`, `:62`, `:90`.
- This repo is NOT affected: `plugins/aid-orchestrator/defaults/execution.yaml:91-100` and
  `.aid-o/config/execution.yaml:281-289` both define `docs_updated` with the real two-`git diff`
  api-vs-docs command.
- The older sibling defect IS fixed: `scripts/aid-run-gates.sh:2407-2432` emits an
  `undefined_gate` fail row and forces overall=fail, and `aid-fsm.sh:2918-2933` refuses GATES:DONE
  without `plan_gates_reconciled: true` (OBS-20260702-05).
- The new variant is unguarded: I swept `run_all_gates`' upfront validation block
  (`aid-run-gates.sh:1548-1610` — run_mode sweep, services sweep, profile include[] sweep) and grepped
  every script for any check of gate *command content*. Nothing anywhere inspects whether a gate
  command can fail. `aid-test-audit-profile.sh:163` reads gate commands, but only for the test audit.
what_is_true: The entry's factual claim holds — WAN's `docs_updated` is a literal no-op that reports
pass — with one correction: it is declared `required: false` there, not "required"; it is required only
via the plan.json floor and the profile include lists. AID itself has no mechanism that can tell a
substantive gate command from `true`, so the same fabrication is possible in any consumer project.
impact: Anyone reading a gates report or a DONE summary. `docs_updated: pass` is read as "documentation
relevance was checked" when nothing was inspected; it is invisible in the report, which shows an
ordinary green row.
fix_sketch: In the same upfront sweep that validates `run_mode`, refuse (or mark `advisory` and strip
the pass row) any enabled gate whose resolved command is a trivially-succeeding shell no-op
(`true`, `:`, `exit 0`, plus redirections/whitespace).
effort: S

---

## IMP-470
verdict: REAL
evidence:
- `plugins/aid-orchestrator/scripts/aid-test-content-scan.sh:545-564` — check 11 is purely static: it
  globs `.github/workflows/*.y*ml` + `.gitlab-ci.yml`, regexes each line for a test runner, and emits
  `{"workflows": n, "runs_tests": bool, "evidence": [...], "commented_out": [...]}`. Nothing reads a
  run result.
- `grep -rn "gh run list"` over `plugins/`, `scripts/`, `.github/` returns **zero** hits.
- The nightly streak machinery (`scripts/aid-nightly-report.sh:172-250`) counts consecutive nights a
  *suite* failed in the nightly artifact. It never looks at GitHub Actions conclusions and knows
  nothing about the `CI` workflow on `main`.
- Live check right now: `gh run list --limit 8` shows the `CI` workflow **queued for 50m+** on the last
  three pushes to main (runs 31465921589, 31465895011, 31462260158) while `Version Sync` completes in
  seconds. Nothing in the repo surfaces that.
what_is_true: v2.78.0's "does CI run any tests?" check is a source-file scan and is the only CI-aware
thing in the audit. There is still no reader of CI run conclusions, no streak, and no first-failing-
commit attribution — the audit today cannot distinguish a green CI from a CI that has been red (or, as
right now, stuck) for days.
impact: Everyone on the merge path. It shows up as nothing at all — the audit says "CI runs tests" and
scores clean while merges go in over a CI that has not passed for days.
fix_sketch: Add a check-12 collector to `aid-test-content-scan.sh` that shells `gh run list --json
conclusion,headSha,createdAt,workflowName --branch main`, degrades to `"not_checkable"` when `gh` is
absent/unauthenticated, and reports current red (or non-completing) streak + first failing SHA as a
critical row that blocks a "clean" audit verdict.
effort: M

---

## IMP-484
verdict: DELIBERATE
evidence:
- `plugins/aid-orchestrator/scripts/aid-run-gates.sh:286-323` — `resolve_run_mode` defaults to
  `foreground`, and `validate_all_run_modes` (`:313-323`) fails loud on anything other than
  `foreground`/`background`: "accepted values: foreground, background". `async` is refused by name.
- `aid-run-gates.sh:1201-1204` — the entry's hook point, now shifted from the recorded `:1163` to
  `:1201`: `# ── poll to completion, inside THIS invocation ──` immediately above
  `while true; do` at `:1204`, with `grace_budget=$(( timeout_s + AID_GATE_DEADLINE_GRACE_SEC ))`.
- `aid-run-gates.sh:1051` — background declaration never falls back to the unowned foreground path;
  `:1173-1196` writes/rewrites the continuation pointer and cancels the job if that write fails.
what_is_true: Everything the entry says was shipped is shipped, and everything it says was not built is
not built. Background gates are supervised, resumable and *synchronous*; `async` does not exist and is
rejected at validation time rather than silently accepted. This is a recorded conscious deferral with a
stated precondition (a registered collector, fixture-proven, per AID-v3 §1), not a defect: no run
behaves incorrectly today. The only correction needed is the line number — `:1163` → `:1201`, `:1166` →
`:1204`.
impact: —
fix_sketch: —
effort: —

---

## IMP-485
verdict: MOOT
evidence:
- `plugins/aid-orchestrator/defaults/enforcement-registry.yaml:1523-1533` — `test_audit_resource_map_shared_evidence`
  is `status: removed_scoped`, `removal: "P078 (2026-08-10) — the test-parallelism machinery this row
  guarded was deleted outright (PM decision 2026-08-09 …)"`, `replacement_guard: "none needed —
  execution is sequential by design; the guarded machinery no longer exists"`. The sibling rows
  `test_audit_pilot_evidence_bound` (`:1537`) and `test_catalog_parallel_provenance_binding` (`:1552`)
  carry the same removal.
- `ls plugins/aid-orchestrator/scripts/ | grep -i 'resource\|pilot'` → **empty**.
  `scripts/aid-test-resource-map.sh` no longer exists.
- `scripts/aid-test-audit-consolidate.sh:70` and `scripts/aid-audit-tests-finalize.sh:70` now hard-fail:
  `--resource-maps-dir|--pilots-dir) _die 2 "$1 was removed in P078 with the parallelism machinery …"`.
- The emitter itself is intact: `scripts/lib/aid-service.sh:967-976` (`_aid_svc_emit_resource`), called
  once at `:1218`; contract comment at `:104-111` and `:945-966`. Only consumer of the JSONL anywhere is
  the test `scripts/tests/bats/test-service-lifecycle.bats:67`.
what_is_true: The entry's title task — "teach the classifier about per-run service ports" — has no
subject left. The resource-map classifier, its schema, its script and its enforcement rows were all
deleted in P078 / v2.82.0, so option (a) is impossible. Option (b) ("delete the emitter") is also not
clearly right: the code comment at `aid-service.sh:955-959` states an independent purpose the entry
omits — "It exists so that a human — or a later step that decides to consume it on purpose — can see
which per-run ports a run actually occupied." So what remains is a one-line housekeeping judgement
(keep the human-readable evidence or drop it), not the deferral this entry describes.
impact: —
fix_sketch: —
effort: —

---

## IMP-486
verdict: REAL
evidence:
- `plugins/aid-orchestrator/scripts/aid-run-gates.sh:232` (the entry records `:196`; it has shifted):
  `output=$(LC_ALL=C timeout "$timeout_s" bash -c "$command" </dev/null 2>&1) || exit_code=$?` — no
  `-k`, no `--foreground`, no process group. The only comment above it (`:228-231`) is about `</dev/null`
  and OBS-20260708-07; nothing there claims the missing `-k` is intentional.
- The grace value the fix would reuse does exist and is already wired on the background path:
  `aid-run-gates.sh:284` `AID_GATE_DEADLINE_GRACE_SEC="${AID_GATE_DEADLINE_GRACE_SEC:-30}"`, used at
  `:1203`, `:1232`, `:1237`.
- Reproduced empirically in the scratchpad:
  `time (timeout 2 bash -c 'trap "" TERM; sleep 6; echo NOPE' </dev/null)` → printed `NOPE`,
  `exit=124`, `real 0m6.008s`. The deadline did not stop the child; the call returned only when the
  child finished on its own.
what_is_true: The foreground gate path is exactly as the entry describes and P076 did leave it
byte-identical. `timeout` without `-k` sends one SIGTERM and then waits: a gate that traps or ignores
SIGTERM runs to its own completion, and the runner blocks on the captured-output subshell for that whole
time. `timeout_s` is therefore an advisory number for such a child, not a deadline. Note the fix's blast
radius is real — adding `-k` changes kill semantics for every gate in this repo and every consumer
project, which is why it was deferred to its own change rather than being called intentional-forever.
impact: Anyone running a gate that wedges (a node test server, a stuck `docker exec`, a bats suite that
hangs — precisely the hanging plan-final/plan-boundary suites behind IMP-470's red CI). It shows up as a
run that never returns, with a gate that is nominally past its timeout.
fix_sketch: `timeout -k "$AID_GATE_DEADLINE_GRACE_SEC" "$timeout_s" bash -c …` at
`aid-run-gates.sh:232`, landed with a bats fixture whose child traps SIGTERM and must be reaped.
effort: S

---

## IMP-487
verdict: REAL
evidence:
- `plugins/aid-orchestrator/lib/brainstorm-server/start-server.sh:100-104` (entry records `:100`/`:102`,
  accurate): `nohup env BRAINSTORM_DIR=… BRAINSTORM_HOST=… BRAINSTORM_URL_HOST=… node index.js > "$LOG_FILE" 2>&1 &`
  then `SERVER_PID=$!`, `disown "$SERVER_PID" 2>/dev/null`, pid written to `$PID_FILE`.
- That is exactly the shape `_svc_backgrounding_form` rejects for a declared service:
  `scripts/aid-run-gates.sh:398-430` — `re_amp='(^|[^&])&$'`, `re_word='(^|[[:space:];&|(])(nohup|disown|setsid)[[:space:]]'`,
  with the header "a command that backgrounds itself hands back a pid owning nothing — the one violation
  that produces an UNSTOPPABLE orphan"; the check is invoked at `:615`.
- Not migrated: `grep -rn "aid-service" lib/brainstorm-server/` → nothing; there is no `services:` block
  in `defaults/execution.yaml` or `.aid-o/config/execution.yaml`.
what_is_true: The companion server is still started by an unowned `nohup … & disown`, and
`aid-service.sh` would refuse that same command in a declared service. Two corrections to the entry's
*rationale*, which a planner must not copy verbatim: (1) the server already picks a **random high port**
per session (`start-server.sh:5`), so "give it a per-run port" is already satisfied; (2) a `--foreground`
mode already exists (`:93-98`) for environments that reap detached processes, and `stop-server.sh` kills
by pid file. The genuine remaining gap is ownership: a crash between start and stop leaves an orphan
node process that nothing sweeps (no health probe, no acquire-once/release-once, no teardown on
`resume`/`done-advance`).
impact: A PM running `/aid-plan` brainstorm sessions. It shows up as accumulating stray `node index.js`
processes after a crashed or abandoned session — a slow leak, not a visible failure.
fix_sketch: Declare the companion as a service in `execution.yaml` with a health probe on its already-random
port and a foreground `start_cmd`, keeping the `--url-host` display handling outside the generic layer.
effort: M

---

## IMP-488
verdict: DELIBERATE
evidence:
- `plugins/aid-orchestrator/commands/aid-run.md:108-110` (entry records `:108`, accurate): "*Do not wait
  indefinitely for a missing notification. "Resume" is a named mechanical path, not a judgement call*",
  followed by the artifact contract at `:111-115`.
- The mechanism side exists and is enforced: `scripts/lib/aid-resume-artifact.sh:32`
  `AID_RESUME_ARTIFACT_BASENAME="auto_resume_required.json"` with the comment that both the writer and
  the three FSM globs read it from here; the writer/rewriter is `aid-run-gates.sh:1173-1196` (a failed
  rewrite cancels the just-started job rather than leaving it unresumable).
- The derived state is documented as derived, never stored: `commands/aid-run.md:67-81`
  ("`awaiting_host_resume` … Nobody. It is **derived** at read time … the writer enforces this —
  passing `awaiting_host_resume` to …"), plus `commands/aid-status.md:169` and `:279`.
what_is_true: Everything the entry says shipped is present and behaving as described; the missing piece
is a host-specific push adapter, deferred with an explicit AID-v3 §1 rationale ("AID has no controlled
surface that delivers a notification, so any adapter shipped here would be a detector with no test").
The enforced fallback is the artifact path, and it works without a host. This is a recorded intentional
omission plus a feature request, not a defect in current behaviour.
impact: —
fix_sketch: —
effort: —
