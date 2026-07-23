#!/usr/bin/env bats
# test-aid-job.bats — IMP-262 controller-owned background job supervisor.
#
# Proves the two backlog failure modes are structurally prevented and every
# acceptance criterion has a tested outcome:
#   - an EXITED job is never "running" just because a `tail -f` still exists
#   - a STARTED/in-flight job satisfies no evidence claim (collect => not terminal)
#   - a job survives replacement of its controller; a resumed controller collects
#     exactly one terminal result without relaunching
#   - cancel targets the recorded PROCESS GROUP: no orphan child, terminal result
#   - PID reuse, missing result, timeout and tree drift have explicit outcomes
#   - paired red-green receipts accepted; a fabricated pass rejected
#
# Synthetic jobs only (sleep 1-3). The hour-long / controller-restart case is
# simulated by persisting the record and re-invoking status/collect — never by
# actually sleeping an hour.

setup() {
  export TZ=UTC
  SCRIPT="${BATS_TEST_DIRNAME}/../../aid-job.sh"
  TMP="$(mktemp -d)"
  REPO="$TMP/project"
  JOBS="$REPO/.aid-o/work/jobs"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b main
  git config user.email test@test.local
  git config user.name Test
  echo seed > file.txt
  git add file.txt
  git commit -q -m initial
}

teardown() {
  # Best-effort: cancel any still-live job so no process leaks past the fixture.
  if [[ -d "$JOBS" ]]; then
    for d in "$JOBS"/*/; do
      [[ -f "$d/job.json" ]] || continue
      local id; id="$(jq -r '.id' "$d/job.json" 2>/dev/null || true)"
      [[ -n "$id" ]] && bash "$SCRIPT" cancel --jobs-dir "$JOBS" --id "$id" >/dev/null 2>&1 || true
    done
  fi
  cd /
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

# Wait until a job has a terminal result.json (bounded).
_await_terminal() {
  local id="$1" max="${2:-60}" i
  for ((i=0; i<max; i++)); do
    [[ -f "$JOBS/$id/result.json" ]] && return 0
    sleep 0.2
  done
  return 1
}

# -- 1. happy path: run -> running -> terminal_pass, collect returns record ------
@test "run then collect yields terminal_pass with exit_code 0" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- bash -c 'echo hi; sleep 1; exit 0')"
  run bash "$SCRIPT" status --jobs-dir "$JOBS" --id "$id"
  [ "$status" -eq 0 ]; [ "$output" = "running" ]
  _await_terminal "$id"
  run bash "$SCRIPT" collect --jobs-dir "$JOBS" --id "$id"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "terminal_pass" and .exit_code == 0 and (.stdout_sha256 | length == 64)'
}

# -- 2. FAILURE MODE 1: exited job is NOT running because a tail -f survives ----
@test "exited job is not reported running even with a live tail -f on its log" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- bash -c 'echo done; exit 0')"
  _await_terminal "$id"
  tail -f "$JOBS/$id/stdout.log" >/dev/null 2>&1 &
  tpid=$!
  run bash "$SCRIPT" status --jobs-dir "$JOBS" --id "$id"
  kill "$tpid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$output" = "terminal_pass" ]
}

# -- 3. FAILURE MODE 2: a started/in-flight job proves no test outcome ----------
@test "collect on an in-flight job is not terminal and exits 3" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- bash -c 'sleep 5; exit 0')"
  run bash "$SCRIPT" collect --jobs-dir "$JOBS" --id "$id"
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.terminal == false and (.state == "in_flight" or .state == "lost")'
}

# -- 4. terminal_fail carries the nonzero exit code ----------------------------
@test "failing command becomes terminal_fail and collect exits 1" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- bash -c 'exit 7')"
  _await_terminal "$id"
  run bash "$SCRIPT" collect --jobs-dir "$JOBS" --id "$id"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.state == "terminal_fail" and .exit_code == 7'
}

# -- 5. survive controller replacement: collect exactly one terminal result -----
@test "job survives its launcher and a resumed controller collects it once, idempotently" {
  # The launcher (this run invocation) returns immediately; the wrapper is
  # setsid-detached, so it is not in this shell's process group / session.
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- bash -c 'sleep 2; exit 0')"
  wpid="$(jq -r '.pid' "$JOBS/$id/job.json")"
  wsid="$(ps -o sid= -p "$wpid" | tr -d ' ')"
  mysid="$(ps -o sid= -p $$ | tr -d ' ')"
  [ "$wsid" != "$mysid" ]                 # detached into its own session
  _await_terminal "$id"
  run bash "$SCRIPT" collect --jobs-dir "$JOBS" --id "$id"
  [ "$status" -eq 0 ]
  c1="$(jq -r '.cookie' "$JOBS/$id/result.json")"
  # A second, independent collect returns the SAME terminal record (no relaunch).
  run bash "$SCRIPT" collect --jobs-dir "$JOBS" --id "$id"
  [ "$status" -eq 0 ]
  c2="$(echo "$output" | jq -r '.cookie')"
  [ "$c1" = "$c2" ]
}

# -- 6. cancel targets the PGID: no orphan child, terminal cancellation result --
@test "cancel kills the whole recorded process group and writes a cancellation result" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- \
        bash -c "sleep 60 & echo \$! > '$TMP/childpid'; wait")"
  # Wait for the grandchild pid to be recorded.
  for _ in $(seq 1 30); do [[ -s "$TMP/childpid" ]] && break; sleep 0.2; done
  child="$(cat "$TMP/childpid")"
  [ -d "/proc/$child" ]                    # grandchild alive before cancel
  run bash "$SCRIPT" cancel --jobs-dir "$JOBS" --id "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "cancelled" ]
  # No orphan: the grandchild is gone because cancel signalled the group.
  sleep 0.5
  [ ! -d "/proc/$child" ]
  jq -e '.state == "cancelled"' "$JOBS/$id/result.json"
}

# -- 7. cancel is idempotent on an already-terminal job ------------------------
@test "cancel on a completed job is a no-op returning its terminal state" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- true)"
  _await_terminal "$id"
  run bash "$SCRIPT" cancel --jobs-dir "$JOBS" --id "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "terminal_pass" ]
}

# -- 8. PID-reuse safety: alive PID with a different starttime is not "running" -
@test "a reused PID (alive but wrong starttime) is reported lost, never running" {
  mkdir -p "$JOBS/forged"
  # pid=self (definitely alive) but proc_starttime deliberately wrong; no result.
  jq -nc --arg id forged --argjson pid "$$" --arg st 1 \
    '{schema:"aid-job/1", id:$id, state:"running", pid:$pid, pgid:$pid,
      proc_starttime:$st, start_head:"x", start_tree:"y"}' > "$JOBS/forged/job.json"
  run bash "$SCRIPT" status --jobs-dir "$JOBS" --id forged
  [ "$status" -eq 0 ]
  [ "$output" = "lost" ]
}

# -- 9. timeout: a job past its hard deadline becomes timed_out -----------------
@test "a job exceeding its hard deadline is timed_out" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" --deadline 1 -- sleep 30)"
  _await_terminal "$id" 60
  run bash "$SCRIPT" status --jobs-dir "$JOBS" --id "$id"
  [ "$output" = "timed_out" ]
}

# -- 10. tree drift: a terminal result on a moved tree is stale -----------------
@test "collect --require-current returns the result when current and stale after tree drift" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- true)"
  _await_terminal "$id"
  run bash "$SCRIPT" collect --jobs-dir "$JOBS" --id "$id" --require-current --repo "$REPO"
  [ "$status" -eq 0 ]
  echo "drift" >> "$REPO/file.txt"        # move the working tree
  run bash "$SCRIPT" collect --jobs-dir "$JOBS" --id "$id" --require-current --repo "$REPO"
  [ "$status" -eq 4 ]
  echo "$output" | jq -e '.stale == true'
}

# -- 11. red-green ACCEPT: same command fails at baseline, passes at fixed ------
@test "paired red-green receipts are accepted when baseline fails and fixed passes" {
  # Identical argv both runs (=> identical fingerprint); polarity flips by revision.
  cmd=(bash -c 'test -f marker')
  b="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" \
        --polarity baseline --expect fail --filter sel -- "${cmd[@]}")"
  _await_terminal "$b"
  touch "$REPO/marker"; git add marker; git commit -q -m "add marker (the fix)"
  f="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" \
        --polarity fixed --expect pass --filter sel -- "${cmd[@]}")"
  _await_terminal "$f"
  # Sanity: baseline observed fail, fixed observed pass.
  jq -e '.observed_polarity == "fail"' "$JOBS/$b/result.json"
  jq -e '.observed_polarity == "pass"' "$JOBS/$f/result.json"
  run bash "$SCRIPT" redgreen --jobs-dir "$JOBS" --baseline "$b" --fixed "$f"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.verdict == "accepted"'
}

# -- 12. red-green REJECT: a fabricated (non-terminal) fixed job proves nothing -
@test "a red-green claim backed by a non-terminal in-flight job is rejected" {
  cmd=(bash -c 'test -f marker')
  b="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" \
        --polarity baseline --expect fail --filter sel -- "${cmd[@]}")"
  _await_terminal "$b"
  # "fixed" job is still in flight (sleeps) — no terminal receipt exists.
  f="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" \
        --polarity fixed --expect pass --filter sel -- bash -c 'sleep 5; exit 0')"
  run bash "$SCRIPT" redgreen --jobs-dir "$JOBS" --baseline "$b" --fixed "$f"
  [ "$status" -eq 5 ]
  echo "$output" | jq -e '.verdict == "rejected" and (.reasons | index("fixed_not_terminal"))'
}

# -- 13. red-green REJECT: fixed observed fail (no real fix) --------------------
@test "a red-green pair where the fixed run still fails is rejected" {
  cmd=(bash -c 'exit 1')
  b="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" \
        --polarity baseline --expect fail --filter sel -- "${cmd[@]}")"
  _await_terminal "$b"
  git commit -q --allow-empty -m advance
  f="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" \
        --polarity fixed --expect pass --filter sel -- "${cmd[@]}")"
  _await_terminal "$f"
  run bash "$SCRIPT" redgreen --jobs-dir "$JOBS" --baseline "$b" --fixed "$f"
  [ "$status" -eq 5 ]
  echo "$output" | jq -e '.reasons | index("fixed_observed_not_pass")'
}

# -- 13b. red-green REJECT (review MEDIUM): empty commit + flaky command is not
# a real fix — HEAD moved but the committed tree object is identical, so it
# cannot masquerade as red->green even when the command flips fail->pass. -----
@test "a red-green pair proven only by an empty commit (identical tree) is rejected" {
  # A command that flips fail->pass purely by external state, not by any code
  # change: absent marker → exit 1, present marker → exit 0. The marker is
  # created WITHOUT committing, then the 'fix' is a git commit --allow-empty, so
  # HEAD moves but the committed tree object does not.
  local cmd=(bash -c 'test -f /tmp does-not-exist-'"$$")
  b="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" \
        --polarity baseline --expect fail --filter sel -- bash -c 'exit 1')"
  _await_terminal "$b"
  git -C "$REPO" commit -q --allow-empty -m "empty advance (no code change)"
  f="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" \
        --polarity fixed --expect pass --filter sel -- bash -c 'exit 0')"
  _await_terminal "$f"
  # HEAD differs (so the old same_revision check passes), observed polarity flips
  # fail->pass, exit codes agree — the ONLY thing that catches the fabrication
  # is the committed-tree-object comparison.
  jq -e '.observed_polarity == "fail"' "$JOBS/$b/result.json"
  jq -e '.observed_polarity == "pass"' "$JOBS/$f/result.json"
  run bash "$SCRIPT" redgreen --jobs-dir "$JOBS" --baseline "$b" --fixed "$f"
  [ "$status" -eq 5 ]
  echo "$output" | jq -e '.reasons | index("same_tree_no_change_proven")'
}

# -- 14. watchdog: resume_needed / idle_ok / busy ------------------------------
@test "watchdog reports resume_needed only when no live job and no recent progress" {
  run bash "$SCRIPT" watchdog --jobs-dir "$JOBS" --now 1000 --last-progress 100 --interval 300
  [ "$status" -eq 0 ]; echo "$output" | jq -e '.state == "resume_needed"'
  run bash "$SCRIPT" watchdog --jobs-dir "$JOBS" --now 200 --last-progress 100 --interval 300
  [ "$status" -eq 0 ]; echo "$output" | jq -e '.state == "idle_ok"'
}

@test "watchdog reports busy while an owned job is live" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- sleep 10)"
  run bash "$SCRIPT" watchdog --jobs-dir "$JOBS" --now 999999 --last-progress 1 --interval 300
  bash "$SCRIPT" cancel --jobs-dir "$JOBS" --id "$id" >/dev/null 2>&1 || true
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state == "busy" and .live_jobs == 1'
}

# -- 15. injection discipline: a bad job id never becomes a path ----------------
@test "job id charset is validated before it becomes a filesystem path" {
  run bash "$SCRIPT" run --jobs-dir "$JOBS" --id '../escape' --repo "$REPO" -- true
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid job id"* ]]
  run bash "$SCRIPT" status --jobs-dir "$JOBS" --id 'bad;rm'
  [ "$status" -ne 0 ]
}

# -- 16. command fingerprint is a sha256, recorded not re-executed -------------
@test "the command fingerprint is a 64-char sha256 stored alongside the argv" {
  id="$(bash "$SCRIPT" run --jobs-dir "$JOBS" --repo "$REPO" -- bash -c 'exit 0')"
  _await_terminal "$id"
  jq -e '(.command_fingerprint | test("^[0-9a-f]{64}$")) and (.command | type == "array")' "$JOBS/$id/job.json"
  jq -e '.command_fingerprint | test("^[0-9a-f]{64}$")' "$JOBS/$id/result.json"
}
