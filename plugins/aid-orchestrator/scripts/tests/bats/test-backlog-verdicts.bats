#!/usr/bin/env bats
# aid-tier: t1
# test-backlog-verdicts.bats — P083 Step 10: the backlog records what the
# 2026-08-11 verification found.
#
# WHAT THIS PROVES. Seven independent verification blocks
# (.aid-o/work/evidence/backlog-verify-2026-08-11/block-{1..7}.md) re-checked
# 46 backlog entries against the live tree, one at a time. Every one of those
# 46 entries must carry exactly one dated verdict line — never zero (silently
# left as-is), never two (an old annotation left dangling next to a new one).
# This suite is the mechanical proof that the edit satisfied that rule, and
# that it did not break the one other consumer of this file's shape found in
# the tree: test-deferred-work-registration.bats's `^#+ .*IMP-nnn` heading
# scan (case 5, line ~123).
#
# WHY 46 HARD-CODED HEADING NEEDLES. The 46 entries touched by the
# verification are a fixed, named set — not "every entry in the file" (most
# of the file's ~135 entries are untouched, and their silence is honest: not
# examined by this pass). Four of the 46 carry no IMP-/OBS-/B-nnn id at all
# (their backlog entries are un-ID'd, headed only by a descriptive title), so
# they are matched by a literal heading substring instead of a token.
#
# WHAT IS ASSERTED, AND AT WHICH ALTITUDE. Token presence and count, never
# prose content: this suite does not re-litigate whether a verdict is
# correct (that was the verification's job), only that every touched entry
# carries one, dated, non-contradictory verdict line, and that the file's
# heading shape survived the edit.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"; export REPO_ROOT
  BACKLOG="$REPO_ROOT/docs/plans/2026-06-29-BACKLOG.md"; export BACKLOG
  [ -f "$BACKLOG" ]

  # The 46 entries the 2026-08-11 verification touched, identified by a
  # heading needle unique to each entry (an id token where one exists, a
  # literal heading-text fragment for the four un-ID'd entries).
  NEEDLES_FILE="$BATS_TEST_TMPDIR/needles.txt"
  cat > "$NEEDLES_FILE" <<'NEEDLES'
IMP-280
IMP-281
IMP-470
IMP-484
IMP-485
IMP-486
IMP-487
IMP-488
IMP-261
IMP-268
IMP-274
OBS-20260702-01
OBS-20260702-02
OBS-20260702-04
OBS-20260702-07
OBS-20260705-02
OBS-20260705-03
OBS-20260706-01
OBS-20260708-02
OBS-20260708-03
OBS-20260708-04
OBS-20260708-05
B-005
B-007
B-008
B-002
B-003
B-001
OBS-20260709-03
OBS-20260709-07
OBS-20260711-01
OBS-20260711-02
OBS-20260711-03
OBS-20260711-04
OBS-20260711-05
IMP-471
IMP-490
IMP-491
IMP-492
IMP-493
IMP-495
IMP-496
### Shipped `defaults/execution.yaml` has no `gate_profiles` block
### EPIC generator truncates multi-line acceptance criteria to their first line
### C0 plan-review requires a dependency graph that no pre-generation producer creates
### Cross-repo CP3 manual-dispatch gap — VULCAN E-56-2_2 (confirmed, deferred from 2026-07-08)
NEEDLES
  export NEEDLES_FILE
}

# _entry_body <needle> — the exact entry: from the FIRST heading line whose
# text contains <needle> to the next heading of any level (### or ##),
# exclusive. Mirrors the extraction test-deferred-work-registration.bats
# uses for its own per-entry body (case 6), so both suites read the file the
# same way.
_entry_body() {
  local needle="$1"
  awk -v needle="$needle" '
    BEGIN { inblk = 0; found = 0 }
    !found && /^#+ / && index($0, needle) > 0 { inblk = 1; found = 1; print; next }
    inblk && /^#+ / { inblk = 0 }
    inblk { print }
  ' "$BACKLOG"
}

@test "1: every needle matches at least one entry heading in the backlog" {
  local needle count bad=0
  while IFS= read -r needle; do
    [ -n "$needle" ] || continue
    # How many heading (## or ###) lines contain this needle, literal match.
    count="$(grep -cF "$needle" <(grep -E '^#{2,3} ' "$BACKLOG") || true)"
    if [ "$count" -lt 1 ]; then
      echo "FAIL: needle '$needle' matches no heading in $BACKLOG" >&2
      bad=$((bad + 1))
    fi
  done < "$NEEDLES_FILE"
  [ "$bad" -eq 0 ]
}

@test "2: each of the 46 touched entries carries exactly one current verdict and no superseded one" {
  # Three conditions, one pass over each entry body (the extraction is the
  # expensive part): the current dated verdict is present, it is present only
  # once, and the entry does not ALSO still carry its own superseded v2.82.0
  # annotation — the "retracted framing left dangling next to the current one"
  # the plan forbids. (The file legitimately keeps v2.82.0 annotations on
  # entries OUTSIDE the 46; those are correct and untouched.)
  local needle body current superseded bad=0
  while IFS= read -r needle; do
    [ -n "$needle" ] || continue
    body="$(_entry_body "$needle")"
    if [ -z "$body" ]; then
      echo "FAIL: empty entry body for needle '$needle'" >&2
      bad=$((bad + 1))
      continue
    fi
    current="$(grep -c 'verified 2026-08-11 against v2\.83\.1' <<<"$body" || true)"
    superseded="$(grep -c 'verified 2026-08-11 against v2\.82\.0' <<<"$body" || true)"
    if [ "$current" -ne 1 ]; then
      echo "FAIL: '$needle' carries $current dated 2026-08-11/v2.83.1 verdict lines (expected exactly 1)" >&2
      bad=$((bad + 1))
    fi
    if [ "$superseded" -ne 0 ]; then
      echo "FAIL: '$needle' still carries the superseded v2.82.0 annotation next to its v2.83.1 verdict" >&2
      bad=$((bad + 1))
    fi
  done < "$NEEDLES_FILE"
  [ "$bad" -eq 0 ]
}

@test "3: exactly 46 entries in the file carry the 2026-08-11/v2.83.1 verdict marker" {
  local n
  n="$(grep -c 'verified 2026-08-11 against v2\.83\.1' "$BACKLOG" || true)"
  [ "$n" -eq 46 ] || {
    echo "FAIL: expected exactly 46 occurrences of the 2026-08-11/v2.83.1 verdict marker, found $n" >&2
    false
  }
}

@test "4: the file still parses for test-deferred-work-registration.bats's IMP-nnn heading scan" {
  # That suite (case 5, ~line 123) does:
  #   grep -qE "^#+ .*\b${imp}\b" "$BACKLOG"
  # for each of the five IMP numbers named in a source document's deferred-
  # work §16 block, and (case 7) grep -cE the same pattern expecting exactly
  # one heading match. Prove the P083 edits did not break that consumer by
  # running its actual suite, not a reimplementation of its regex.
  run bats "$REPO_ROOT/plugins/aid-orchestrator/scripts/tests/bats/test-deferred-work-registration.bats"
  [ "$status" -eq 0 ] || {
    echo "FAIL: test-deferred-work-registration.bats no longer passes against the edited backlog" >&2
    echo "$output" >&2
    false
  }
}
